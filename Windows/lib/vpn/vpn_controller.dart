import 'direct_profile.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../core/core_display.dart';
import '../core/malicious_link_guard.dart';
import '../core/safe_url_launcher.dart';
import '../core/storage.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../core/network_redaction.dart';
import '../models/models.dart';
import '../platform/native.dart';
import '../platform/services.dart';
import 'balancer.dart';
import 'clash_api.dart';
import 'content_block_server.dart';
import 'core_runtime.dart';
import 'https_ad_filter_proxy.dart';
import 'local_ca.dart';
import 'startup_verification.dart';
import 'cli_session.dart';
import 'cores.dart';
import 'umbrella_core.dart';
import 'core_ping.dart';
import 'link_preparation.dart';
import 'ping.dart';
import 'tunnel_probe.dart';
import 'speed_test.dart';
import 'verified_probe.dart';
import 'windows_crash.dart';

/// سرعت میانگین بر حسب بایت در ثانیه با فاصله واقعی نمونه ها.
double trafficBytesPerSecond(int delta, Duration elapsed) {
  if (delta <= 0 || elapsed.inMicroseconds <= 0) return 0;
  return delta * Duration.microsecondsPerSecond / elapsed.inMicroseconds;
}

enum VpnStatus {
  disconnected,
  preparing,
  connecting,
  connected,
  switching,
  reconnecting,
  disconnecting,
  failed,
}

extension VpnStatusX on VpnStatus {
  String get label {
    switch (this) {
      case VpnStatus.disconnected:
        return 'قطع';
      case VpnStatus.preparing:
        return 'آماده سازی';
      case VpnStatus.connecting:
        return 'در حال اتصال';
      case VpnStatus.connected:
        return 'متصل';
      case VpnStatus.switching:
        return 'تغییر سرور';
      case VpnStatus.reconnecting:
        return 'اتصال دوباره';
      case VpnStatus.disconnecting:
        return 'در حال قطع';
      case VpnStatus.failed:
        return 'خطا در اتصال';
    }
  }

  String get image {
    switch (this) {
      case VpnStatus.connected:
        return BrandAssets.connected;
      case VpnStatus.preparing:
      case VpnStatus.connecting:
        return BrandAssets.connecting;
      case VpnStatus.switching:
        return BrandAssets.switching;
      case VpnStatus.reconnecting:
        return BrandAssets.reconnecting;
      case VpnStatus.disconnecting:
        return BrandAssets.paused;
      case VpnStatus.failed:
        return BrandAssets.failed;
      case VpnStatus.disconnected:
        return BrandAssets.disconnected;
    }
  }

  bool get busy =>
      this == VpnStatus.preparing ||
      this == VpnStatus.connecting ||
      this == VpnStatus.switching ||
      this == VpnStatus.reconnecting ||
      this == VpnStatus.disconnecting;

  bool get active => this == VpnStatus.connected || busy;

  String get trayKey {
    switch (this) {
      case VpnStatus.connected:
        return 'connected';
      case VpnStatus.failed:
        return 'failed';
      case VpnStatus.disconnected:
        return 'disconnected';
      default:
        return 'connecting';
    }
  }
}

class ConnectOutcome {
  const ConnectOutcome({
    required this.ok,
    required this.message,
    this.needsElevation = false,
    this.needsCores = false,
    this.needsRenewal = false,
    this.needsSecurityCleanup = false,
    this.cancelled = false,
  });

  final bool ok;
  final String message;
  final bool needsElevation;
  final bool needsCores;

  /// اشتراک کاربر اجازه اتصال نمی دهد (منقضی، مسدود یا تمام شده).
  final bool needsRenewal;

  /// بدافزار یا فیلترشکن ناسازگار روی سیستم فعال است و پیش از اتصال باید پاکسازی شود.
  final bool needsSecurityCleanup;

  /// کاربر خودش وسط کار دکمه لغو را زد؛ این خطا نیست و نباید پیام خطا بدهد.
  final bool cancelled;
}

class _AttemptResult {
  const _AttemptResult({
    required this.message,
    this.ok = false,
    this.needsCores = false,
    this.cancelled = false,
    this.unusable = false,
  });

  final String message;
  final bool ok;
  final bool needsCores;
  final bool cancelled;

  /// هسته این سرور را حتی نتوانست بسازد (لینک برایش قابل خواندن نبود)؛
  /// تلاش دوباره بی فایده است.
  final bool unusable;
}

class CoreLaunch {
  const CoreLaunch({
    required this.exe,
    required this.args,
    required this.workDir,
    required this.name,
  });

  final String exe;

  /// آرگومان ها به صورت فهرست، تا فراخوانی مستقیم ویندوز بدون شل انجام شود.
  final List<String> args;
  final String workDir;
  final String name;

  String get binaryName => exe.split(Platform.pathSeparator).last;
}

/// نقشه اجرای هسته برای یک سرور.
///
/// این نسخه یک هسته دارد (موتور هسته)، پس نقشه چیزی جز «همین هسته با این
/// فایل لینک و این حالت» نیست. نگه داشتنش به صورت یک کلاس، تلاش دوباره با حالت
/// دیگر و آزمون پذیری را ساده می کند.
class LaunchPlan {
  const LaunchPlan({
    required this.cores,
    required this.linksPath,
    required this.runDir,
    required this.readinessPort,
    required this.primaryBinary,
    required this.tunnelHint,
    required this.chained,
    this.warning = '',
    this.proxyPort = 0,
    this.tun = false,
    this.systemProxy = true,
  });

  final List<CoreLaunch> cores;

  /// فایل لینک سرور که به هسته داده می شود (`-c`).
  final String linksPath;

  /// پوشه داده هسته برای همین اتصال (`-D`).
  final String runDir;

  final int readinessPort;
  final String primaryBinary;
  final String tunnelHint;
  final bool chained;
  final String warning;

  /// اگر بزرگ تر از صفر باشد، هسته یک سرور پروکسی محلی روی این پورت می سازد.
  final int proxyPort;

  /// آیا این نقشه تونل کامل است (`--tun`)؟
  final bool tun;

  /// آیا پروکسی سیستم عامل روی [proxyPort] تنظیم شود؟ در حالت «فقط پروکسی» خاموش است.
  final bool systemProxy;

  bool get usesSystemProxy => proxyPort > 0 && !tun && systemProxy;
}

/// مغز اتصال: انتخاب سرور، ساخت پیکربندی، اجرای هسته، کیل سوییچ، پایش و
/// قطع تمیز. تمام کارهای شبکه از راه پلاگین بومی انجام می شود.
class VpnController extends ChangeNotifier {
  VpnController({
    required NativeBridge native,
    required IpService ipService,
    required SoundService sound,
    required TrayService tray,
    required CoreProvisioner provisioner,
    required AppSettings settings,
    this.onSettingsChanged,
    this.onRequireElevation,
    this.onRequireCores,
    this.accessGuard,
    this.securityGuard,
    this.canAutoConnect,
  })  : _native = native,
        _ip = ipService,
        _sound = sound,
        _tray = tray,
        _provisioner = provisioner,
        _settings = settings,
        _ping = PingService(native),
        _corePing = CorePinger(provisioner);

  final NativeBridge _native;
  final IpService _ip;
  final SoundService _sound;
  final TrayService _tray;
  final CoreProvisioner _provisioner;
  final PingService _ping;
  final CorePinger _corePing;
  final NodeBalancer _balancer = NodeBalancer();
  final AppLogger _log = AppLogger.instance;

  final ValueChanged<AppSettings>? onSettingsChanged;
  final VoidCallback? onRequireElevation;
  VoidCallback? onTunnelConnected;
  Future<void> Function(List<CoreActivitySample> samples)?
      onNetworkConnectionsObserved;
  Future<void> Function(String host, String category)?
      onBlockedMaliciousHost;
  Future<bool> Function(Uri uri, {required String title, required String body})?
      onLaunchBlockedPage;

  /// بررسی دسترسی حساب پیش از هر اتصال. اگر رشته غیرخالی برگرداند، اتصال
  /// انجام نمی شود و همان پیام به کاربر نشان داده می شود (اشتراک منقضی،
  /// مسدود یا تمام شده).
  final String Function()? accessGuard;

  /// بررسی سپر امنیتی پیش از هر اتصال برای مسدودسازی بدافزار و VPN های ناسازگار.
  final Future<String> Function()? securityGuard;

  /// شرط مجاز بودن اتصال خودکار در شروع برنامه (عبور از معرفی، ورود به حساب و
  /// داشتن اشتراک سالم) تا برنامه در صفحه معرفی یا ورود هرگز خودکار وصل نشود.
  final bool Function()? canAutoConnect;

  bool get _mayAutoConnectNow =>
      _settings.autoConnect && (canAutoConnect?.call() ?? true);

  final VoidCallback? onRequireCores;

  AppSettings _settings;
  AppSettings get settings => _settings;

  List<VpnNode> _nodes = <VpnNode>[];
  List<VpnNode> get nodes => List<VpnNode>.unmodifiable(_nodes);
  List<VpnNode> _emergencyNodes = <VpnNode>[];
  bool _emergencySession = false;
  bool get emergencySession => _emergencySession;
  List<VpnNode> get emergencyNodes => List<VpnNode>.unmodifiable(_emergencyNodes);
  List<VpnNode> get _sessionNodes => _emergencySession ? _emergencyNodes : _nodes;

  /// Public nodes are never persisted or mixed into the personal auto pool.
  void setEmergencyNodes(List<VpnNode> nodes, {required bool enabled}) {
    _emergencyNodes = enabled ? List<VpnNode>.of(nodes) : <VpnNode>[];
    if (!enabled && _emergencySession && (_connectInFlight || _status.active || _status.busy)) {
      unawaited(cancel());
    }
    if (!_disposed) notifyListeners();
  }


  VpnStatus _status = VpnStatus.disconnected;
  VpnStatus get status => _status;

  VpnNode? _activeNode;
  VpnNode? get activeNode => _activeNode;

  String _message = 'برای اتصال دکمه را بزنید.';
  String get message => _message;

  TunnelStats _stats = TunnelStats.empty;
  TunnelStats get stats => _stats;
  bool _batterySaving = false;
  bool get batterySaving => _batterySaving;
  bool _appVisible = true;
  bool get appVisible => _appVisible;
  final Stopwatch _statsClock = Stopwatch();
  Duration? _lastStatsSample;
  Duration? _lastTraySpeedUpdate;

  /// تغییر بازه ها بدون بازنشانی اتصال، آمار یا اندازه گیری زنده.
  void setBatterySaving(bool value) {
    if (_disposed || _batterySaving == value) return;
    _batterySaving = value;
    if (_statsTimer?.isActive ?? false) _scheduleStatsTimer();
    if (_liveTimer?.isActive ?? false) _scheduleLiveTimer();
    _notify();
  }

  void setAppVisible(bool visible) {
    if (_disposed || _appVisible == visible) return;
    _appVisible = visible;
    if (_statsTimer?.isActive ?? false) _scheduleStatsTimer();
    if (_liveTimer?.isActive ?? false) _scheduleLiveTimer();
    if (visible && _status == VpnStatus.connected) {
      unawaited(_tickStats());
      unawaited(_refreshLivePing());
    }
  }

  GeoInfo _geo = GeoInfo.empty;
  GeoInfo get geo => _geo;

  String _realIp = '';
  String _realCountryCode = '';
  int _sameIpWarnedEpoch = -1;
  String get realIp => _realIp;

  /// آیا در همین لحظه مجاز به ثبت آی پی واقعی (پیش از اتصال) هستیم؟
  /// فقط زمانی که هیچ تونل، اتصال در حال انجام یا فرایند هسته ای فعال نیست.
  bool get _canCaptureBaselineIp =>
      !_disposed &&
      !_shuttingDown &&
      !_connectInFlight &&
      _status == VpnStatus.disconnected &&
      _exitIp.isEmpty &&
      !_hasTrackedCoreProcesses;

  /// تشخیص دقیق اینکه آیا آی پی خروجی خوانده شده واقعاً نشت بدون تونل است یا
  /// آی پی سالم سرور خارجی است (مثلاً وقتی پیش از اتصال یک فیلترشکن دیگر باز
  /// بوده یا `_realIp` قبلاً از سرور خارجی ثبت شده است).
  static bool isUntunneledExitIp({
    required String exitIp,
    required String exitCountryCode,
    required String realIp,
    required String realCountryCode,
    required bool fromCoreMonitor,
  }) {
    final String cleanExit = exitIp.trim();
    if (cleanExit.isEmpty) {
      return false;
    }
    final String exitCc = exitCountryCode.trim().toLowerCase();
    if (exitCc == 'ir') {
      return true;
    }
    // پایش داخلی خود هسته (ipinfo) مستقیماً از دل خروجی پروکسی اجرا می شود؛
    // وقتی کشور غیر ایران گزارش کرده، ترافیک قطعاً از سرور خارجی خارج شده است.
    if (fromCoreMonitor && exitCc.isNotEmpty) {
      return false;
    }
    final String cleanReal = realIp.trim();
    if (cleanReal.isEmpty || cleanExit != cleanReal) {
      return false;
    }
    final String realCc = realCountryCode.trim().toLowerCase();
    // اگر آی پی خروجی صراحتاً متعلق به کشور خارجی است و آی پی پایه هم از همان
    // کشور خارجی بوده (اجرای قبلی فیلترشکن)، این نشت بدون تونل نیست.
    if (exitCc.isNotEmpty && realCc.isNotEmpty && realCc != 'ir') {
      return false;
    }
    return true;
  }

  String _exitIp = '';
  String get exitIp => _exitIp;

  bool _tunnelVerified = false;
  bool get tunnelVerified => _tunnelVerified;

  DeviceProfile _device = DeviceProfile.empty;
  DeviceProfile get device => _device;

  DateTime? _connectedAt;
  DateTime? get connectedAt => _connectedAt;

  int _proxyPort = 0;
  final Map<String, Process> _coreProcesses = <String, Process>{};

  /// اگر آخرین ساخت پیکربندی به خاطر نبود فایل هسته شکست خورده باشد.
  bool _lastPlanNeedsCore = false;
  /// کیل سوییچ در این نسخه وجود ندارد؛ همیشه خاموش است.
  bool get killSwitchOn => false;

  /// پینگ زنده سرور متصل، روی همان اتصال باز سنجیده می شود.
  int _livePing = 0;
  int get livePing => _livePing;

  /// سرعت اندازه گیری شده روی سرور متصل (بایت بر ثانیه) و زمان سنجش.
  double _liveSpeed = 0;
  double get liveSpeed => _liveSpeed;
  DateTime? _speedMeasuredAt;
  DateTime? get speedMeasuredAt => _speedMeasuredAt;
  SpeedTestRunner? _speedRunner;
  SpeedTestResult? _speedResult;
  SpeedTestResult? get speedResult => _speedResult;
  bool get speedTesting => _speedRunner != null;
  String _speedPhase = '';
  String get speedPhase => _speedPhase;
  String _speedError = '';
  String get speedError => _speedError;
  final Set<String> _networkSecrets = <String>{};
  ChainSettings _activeChain = const ChainSettings();
  ChainSettings get activeChain => _activeChain;
  FilterSettings _contentFilter = FilterSettings.empty;
  FilterSettings get contentFilter => _contentFilter;
  Timer? _filterReloadTimer;
  Timer? _autoConnectRetryTimer;
  bool _shuttingDown = false;
  bool _pendingLiveReload = false;
  String _launchedFilterSignature = FilterSettings.empty.effectSignature;
  bool _activePlanTun = false;
  int _activeMixedPort = AppConfig.httpPortUmbrella;
  bool _activeLocalProxyOpen = true;
  String _activeLocalProxySecret = '';
  ProxyLink? _link;
  Timer? _liveTimer;

  /// پورت ترکیبی محلی تنظیم شده توسط کاربر (با بازگشت امن به پیش فرض).
  int get _configuredMixedPort =>
      LanSharing.isValidPort(_settings.mixedPort)
          ? _settings.mixedPort
          : _umbrellaPort;

  /// پورت مناسب برای سنجش سلامت، پینگ، آی پی و تست سرعت روی اتصال فعلی
  /// (۰ یعنی مسیر مستقیم کارت شبکه تونل وقتی پورت محلی در حالت VPN بسته است).
  int get _probeProxyPort {
    if (_activePlanTun && !_activeLocalProxyOpen) {
      return 0;
    }
    if (_proxyPort > 0) {
      return _proxyPort;
    }
    return _activeMixedPort > 0 ? _activeMixedPort : _configuredMixedPort;
  }

  String get _probeProxyUser =>
      _probeProxyPort > 0 && _activeLocalProxySecret.isNotEmpty
          ? LanSharing.coreAuthUser
          : '';

  String get _probeProxyPassword =>
      _probeProxyPort > 0 ? _activeLocalProxySecret : '';

  String get _desiredSelectGroup => switch (_settings.selectionMode) {
        SelectionMode.roundRobin ||
        SelectionMode.consistentHash ||
        SelectionMode.stickySession =>
          'balance',
        SelectionMode.auto || SelectionMode.manual => 'lowest',
      };

  /// به روز رسانی قوانین کنترل محتوا (از تنظیمات برنامه یا همگام سازی زنده ربات).
  /// اگر تونل هم اکنون متصل باشد، قوانین جدید بدون دخالت کاربر روی اتصال فعال می شوند.
  void updateContentFilter(FilterSettings next) {
    if (_contentFilter.sameEffectAs(next)) {
      _contentFilter = next;
      return;
    }
    _contentFilter = next;
    if (_disposed || _shuttingDown) {
      return;
    }
    _filterReloadTimer?.cancel();
    if (_connectInFlight) {
      // به محض کامل شدن اتصال در حال انجام، تفاوت `_launchedFilterSignature`
      // بررسی و قوانین تازه بلافاصله اعمال می شوند.
      return;
    }
    if (_status == VpnStatus.connected) {
      _scheduleFilterHotReload(next);
    } else if (!_status.active && !_status.busy) {
      _scheduleRuntimePrewarm();
    }
  }

  void _scheduleFilterHotReload(FilterSettings targetFilter) {
    _filterReloadTimer?.cancel();
    _filterReloadTimer = Timer(const Duration(milliseconds: 500), () {
      if (_disposed ||
          _shuttingDown ||
          _connectInFlight ||
          _status != VpnStatus.connected) {
        return;
      }
      _log.add(
        targetFilter.hasActiveRules
            ? 'اعمال قوانین جدید کنترل محتوا روی اتصال فعال...'
            : 'غیرفعال سازی قوانین کنترل محتوا روی اتصال فعال...',
      );
      unawaited(() async {
        final VpnNode? requested =
            _autoSession ? null : (_singleNodeSession ? _activeNode : null);
        final bool emergency = _emergencySession;
        unawaited(ClashApi.closeAllConnections());
        await disconnect(silent: true);
        unawaited(_native.flushDns());
        if (!_disposed && !_shuttingDown) {
          await connect(requested: requested, emergency: emergency);
          unawaited(_native.flushDns());
        }
      }());
    });
  }

  /// پینگ سرور متصل: عدد زنده تونل اگر آماده باشد، وگرنه پینگ شبکه همان
  /// سرور. این عدد هرگز صفر نمی ماند چون سرور متصل از فهرست سنجش هسته ای
  /// کنار گذاشته می شود و پیش از این همیشه «در حال سنجش» می ماند.
  int get activePingMs {
    if (_livePing > 0) {
      return _livePing;
    }
    if (_status.busy || _status == VpnStatus.failed) {
      return 0;
    }
    final VpnNode? node = _activeNode;
    if (node == null) {
      return 0;
    }
    if (PingService.plausible(node.pingMs)) {
      return node.pingMs;
    }
    return 0;
  }

  int _pingProgressDone = 0;
  int _pingProgressTotal = 0;
  bool _measuring = false;
  bool get measuring => _measuring;
  double get pingProgress =>
      _pingProgressTotal == 0 ? 0 : _pingProgressDone / _pingProgressTotal;

  final List<int> _runningPids = <int>[];
  final List<String> _runningBinaries = <String>[];
  Timer? _statsTimer;
  Timer? _healthTimer;
  Timer? _ipTimer;
  Timer? _pingTimer;
  Timer? _prewarmTimer;
  Future<void>? _prewarmInFlight;
  bool _prewarmCancelled = false;
  final Set<Process> _prewarmProcesses = <Process>{};
  DateTime? _sessionStartUtc;
  int _healthFailures = 0;

  /// هسته ای که برای هر سرور جواب داده است (شناسه سرور → نام هسته).
  final Map<String, String> _preferredCore = <String, String>{};
  int _reconnectAttempts = 0;

  VpnNode? _requestedNode;
  bool _autoSession = false;
  bool get autoSession =>
      _autoSession && (_connectInFlight || _status.active || _status.busy);

  bool _waitingForNetwork = false;
  bool get waitingForNetwork => _waitingForNetwork;
  bool _lastNetworkOnline = true;
  String _lastNetworkFingerprint = '';
  Timer? _networkWatchTimer;
  bool _networkProbeInFlight = false;
  final Map<String, String> _resolvedProcessLabels = <String, String>{};

  /// سرورهایی که در همین تلاش اتصال با خطای «قابل اجرا نبود» رد شده اند.
  ///
  /// هسته ای که سروری را نمی تواند بسازد، با تلاش دوباره هم نمی تواند؛ پیش
  /// از این همان سرور چهار بار پشت سر هم امتحان می شد و کاربر فقط «×(۴)»
  /// می دید (گزارش ۱٫۰۶). این مجموعه در هر connect پاک می شود.
  final Set<String> _unusableInThisRun = <String>{};
  bool _disposed = false;
  bool _healthInFlight = false;
  int _connectionEpoch = 0;

  bool get isConnected => _status == VpnStatus.connected;
  bool get isBusy => _status.busy;

  Future<void> bootstrap() async {
    await _provisioner.init();
    unawaited(refreshHttpsCaStatus());
    _device = await _native.deviceInfo();
    if (_device.elevated && _native.available) {
      // پروکسی سیستم از اجرای قبلی پاک می شود.
      await _native.restoreNetworkDefaults();
    }
    await _loadCachedNodes();
    final String last = _settings.lastNodeId;
    if (last.isNotEmpty) {
      for (final VpnNode node in _nodes) {
        if (node.id == last) {
          _activeNode = node;
          break;
        }
      }
    }
    _notify();
    if (_mayAutoConnectNow && _nodes.isNotEmpty) {
      unawaited(_runStartupAutoConnect());
    } else {
      _autoConnectRetryTimer?.cancel();
      _autoConnectRetryTimer = null;
      _scheduleRuntimePrewarm();
    }
    // خواندن آی پی واقعی دستگاه کاملاً غیرمسدودکننده انجام می شود تا باز شدن
    // برنامه و دکمه اتصال حتی در شبکه محدود در کسری از ثانیه آماده باشد.
    unawaited(_discoverInitialIp());
  }

  /// اتصال خودکار شروع برنامه؛ فقط وقتی اجرا می شود که کاربر گزینه «اتصال
  /// خودکار در شروع برنامه» را در تنظیمات عمومی به صورت صریح روشن کرده باشد.
  Future<void> _runStartupAutoConnect() async {
    if (!_mayAutoConnectNow || _status.active || _status.busy) {
      return;
    }
    final int startedCancelGeneration = _cancelGeneration;
    _log.add(
      'اتصال خودکار در شروع برنامه فعال است؛ در حال برقراری اتصال '
      '(برای غیرفعال سازی به تنظیمات > عمومی بروید).',
    );
    final ConnectOutcome outcome = await connect();
    if (outcome.ok ||
        outcome.cancelled ||
        _cancelGeneration != startedCancelGeneration ||
        _disposed ||
        _shuttingDown ||
        !_mayAutoConnectNow) {
      return;
    }
    _autoConnectRetryTimer?.cancel();
    _autoConnectRetryTimer = Timer(const Duration(seconds: 8), () {
      _autoConnectRetryTimer = null;
      if (_disposed ||
          _shuttingDown ||
          _cancelGeneration != startedCancelGeneration ||
          !_mayAutoConnectNow ||
          _status.active ||
          _status.busy ||
          _nodes.isEmpty) {
        return;
      }
      unawaited(connect());
    });
  }

  Future<void> _discoverInitialIp() async {
    if (!_canCaptureBaselineIp) return;
    final GeoInfo fetched = await _ip.fetch(force: true);
    if (!_canCaptureBaselineIp) return;
    if (fetched.ip.isNotEmpty) {
      _realIp = fetched.ip;
      _realCountryCode = fetched.flagCode.toLowerCase();
      _geo = fetched;
      _notify();
      return;
    }
    final String local = await _native.localIp();
    if (!_canCaptureBaselineIp) return;
    if (local.isNotEmpty && _realIp.isEmpty) {
      _realIp = local;
      _realCountryCode = '';
      _notify();
    }
  }

  Future<void> _loadCachedNodes() async {
    // هر فایل پروفایل کلش بازمانده از نسخه های پیشین پاک می شود تا فقط
    // سرورهای مسیر `/sub/` در برنامه بمانند.
    await LocalStore.instance.deleteFile(StoreKeys.legacyPanelProfile);
    try {
      final String? raw = await LocalStore.instance.readFile(StoreKeys.nodesCache);
      if (raw == null || raw.isEmpty) {
        return;
      }
      final List<dynamic> list = JsonX.asList(jsonDecode(raw));
      _nodes = list
          .map((Object? item) => VpnNode.fromJson(JsonX.asMap(item)))
          // عددهای غیرممکن (۰ و ۱ میلی ثانیه) از نسخه های قبلی پاک می شوند تا
          // کاربر پینگ اشتباه نبیند؛ سنجش بعدی مقدار درست را می آورد.
          .map(
            (VpnNode node) => node.hasPing && node.pingMs < 4
                ? node.copyWith(pingMs: 0, jitterMs: 0, stability: 0)
                : node,
          )
          .toList();
    } on Exception {
      _nodes = <VpnNode>[];
    }
  }

  Future<void> _cacheNodes() async {
    if (_disposed) {
      return;
    }
    final String raw = jsonEncode(
      _nodes.map((VpnNode node) => node.toJson()).toList(),
    );
    if (_disposed) {
      return;
    }
    await LocalStore.instance.writeFile(StoreKeys.nodesCache, raw);
  }

  /// سرورهای تازه خوانده شده از اشتراک ها؛ پینگ ها از قبل موجود حفظ می شوند.
  Future<void> applyNodes(List<VpnNode> nodes, {bool measure = true}) async {
    if (_disposed) {
      return;
    }
    final Map<String, VpnNode> previous = <String, VpnNode>{
      for (final VpnNode node in _nodes) node.id: node,
    };
    _nodes = nodes.map((VpnNode node) {
      final VpnNode? old = previous[node.id];
      if (old == null) {
        return node;
      }
      return node.copyWith(
        pingMs: old.pingMs,
        jitterMs: old.jitterMs,
        stability: old.stability,
        checkedAt: old.checkedAt,
        favorite: old.favorite,
      );
    }).toList();
    await _cacheNodes();
    if (_disposed) {
      return;
    }
    _notify();
    if (_nodes.isNotEmpty && !_status.active && !_status.busy) {
      _scheduleRuntimePrewarm();
      if (measure) {
        unawaited(refreshPings(all: false, tunnelProbe: false));
      }
    }
  }

  /// چند سرور در هر دور با خود هسته سنجیده می شود.
  ///
  /// هر نمونه یک فرایند هسته است و دو پورت ثابت هسته را می گیرد؛ سنجیدن همه
  /// ۲۴ سرور چند دقیقه طول می کشید و در آن مدت اتصال ممکن نبود. دور اول روی
  /// ۸ سرور است، دورهای بعدی بقیه را هم می سنجند.
  final int _tunnelProbeCount = 8;

  /// آیا خبر «نتیجه نداد» یک بار گفته شده است؟
  bool _tunnelFailureReported = false;

  Future<void> refreshPings({bool all = true, bool tunnelProbe = true}) async {
    if (_disposed || _measuring || _nodes.isEmpty) {
      return;
    }
    // سنجش هسته ای و اتصال هر دو پورت های ثابت هسته (۱۷۰۷۸ و ۱۶۷۵۶) را
    // می خواهند؛ اگر سنجش در جریان باشد، اتصال با «پورت در اختیار برنامه
    // دیگری است» رد می شد (گزارش ۱٫۰۷).
    if (_status.busy) {
      return;
    }
    // در حین اتصال سنجش هسته ای انجام نمی شود: سنجش، پروسه هسته را بالا می آورد
    // و می تواند تونل فعال کاربر را قطع کند. به جای آن فقط پینگ شبکه خوانده
    // می شود تا عددها زنده بمانند و اتصال دست نخورد.
    final bool liveTunnel = _status.active;
    _measuring = true;
    _pingProgressDone = 0;
    // سرور متصل از سنجش هسته ای کنار گذاشته می شود تا تونل کاربر دست نخورد،
    // ولی پینگ شبکه اش (تی سی پی) خوانده می شود تا عدد سرور متصل هرگز صفر
    // نماند. عدد زنده تونل، وقتی آماده باشد، جای این را می گیرد.
    final String activeId = _activeNode?.id ?? '';
    final VpnNode? active =
        _activeNode ?? (_nodes.isEmpty ? null : _nodes.first);
    final List<VpnNode> pool =
        _nodes.where((VpnNode node) => node.id != activeId).toList();
    if (pool.isEmpty) {
      _measuring = false;
      if (active != null) {
        await _measureActiveNetworkPing(active);
      }
      _notify();
      return;
    }
    _pingProgressTotal = all ? pool.length : pool.take(24).length;
    _notify();
    final List<VpnNode> target = all ? pool : pool.take(24).toList();
    List<VpnNode> measured = target;
    try {
      measured = await _ping.measureAll(
        target,
        concurrency: 8,
        onProgress: (int done, int total) {
          if (_disposed) return;
          _pingProgressDone = done;
          _pingProgressTotal = total;
          _notify();
        },
      );
    } on Exception catch (error) {
      _log.add('سنجش پینگ ناموفق بود: ${error.toString()}', level: 'warning');
    }
    if (_disposed) {
      _measuring = false;
      return;
    }
    // تاخیر واقعی تونل: هسته هر سرور را یک بار امتحان می کند و عدد دقیق را
    // می دهد؛ اگر هسته در دسترس نباشد، نتیجه تی سی پی و آی سی ام پی همان
    // طور می ماند.
    Map<String, int> tunnelDelays = <String, int>{};
    if (tunnelProbe && !liveTunnel && !_status.busy && !_cancelRequested) {
      try {
        tunnelDelays = await _corePing.measure(
          target,
          settings: _settings,
          maxNodes: _tunnelProbeCount,
          budget: const Duration(seconds: 45),
        );
      } catch (_) {
        tunnelDelays = <String, int>{};
      }
    }
    // اگر اتصال در این میان شروع شده باشد، سنجش را خودمان بستیم؛ گزارش
    // «تاخیر تونل برای ۰ سرور» آن وقت فقط گیج کننده است.
    if (_disposed || _status.active) {
      _measuring = false;
      _notify();
      return;
    }
    final List<VpnNode> fused = measured
        .map((VpnNode node) {
          final int? delay = tunnelDelays[node.id];
          return delay == null ? node : _ping.withTunnelDelay(node, delay);
        })
        .toList();
    final Map<String, VpnNode> results = <String, VpnNode>{
      for (final VpnNode node in fused) node.id: node,
    };
    _nodes = _nodes
        .map((VpnNode node) => results[node.id] ?? node)
        .toList()
      ..sort(_sortNodes);
    // سرور متصل (اگر بیرون از فهرست سنجش مانده باشد) هم پینگ شبکه می گیرد.
    if (active != null && !results.containsKey(active.id)) {
      await _measureActiveNetworkPing(active);
    }
    _measuring = false;
    if (_disposed) {
      return;
    }
    await _cacheNodes();
    if (!_status.active && !_disposed) {
      _scheduleRuntimePrewarm();
    }
    // تنها وقتی خبری برای گفتن هست که چیزی به دست نیامده باشد؛ و آن هم یک
    // بار، نه هر دو دقیقه یک بار. پینگ شبکه ای که در فهرست آمده، عدد کاربر
    // را دارد و همین کافی است.
    if (tunnelDelays.isNotEmpty) {
      // سنجش دوباره کار می کند؛ اگر بعداً یک بار دیگر نتیجه نداد، همان یک بار
      // گزارش می شود.
      _tunnelFailureReported = false;
    }
    if (!tunnelProbe) {
      _notify();
      return;
    }
    final bool nothing = tunnelDelays.isEmpty &&
        !liveTunnel &&
        !fused.any((VpnNode node) => node.hasPing);
    _log.add(
      'سنجش پینگ: تاخیر تونل برای ${Fa.num(tunnelDelays.length)} سرور و '
      'پینگ شبکه برای ${Fa.num(fused.where((VpnNode node) => node.hasPing).length)} '
      'سرور به دست آمد.'
      '${_medianNote(fused)}'
      '${_tunnelNote(tunnelDelays)}',
      level: nothing ? 'warning' : 'info',
    );
    if (nothing && !_tunnelFailureReported) {
      _tunnelFailureReported = true;
      final String detail = await _corePing.lastError();
      _log.add(
        'سنجش تاخیر تونل نتیجه نداد${detail.isEmpty ? '' : ': $detail'}',
        level: 'warning',
        details: <LogDetail>[
          LogDetail(
            title: 'وضعیت سنجش',
            text: <String>[
              'سرورهای سنجیده شده در این دور: '
                  '${Fa.num(_tunnelProbeCount)}',
              'پینگ شبکه (تی سی پی) برای '
                  '${Fa.num(fused.where((VpnNode node) => node.hasPing).length)} '
                  'سرور به دست آمد؛ همان عدد در فهرست نشان داده می شود.',
              if (detail.isNotEmpty) 'آخرین خطای هسته سنجش: $detail',
              if (detail.isEmpty)
                'هسته سنجش هیچ خطایی نداد؛ احتمالا مهلت ۶۰ ثانیه ای برای '
                    'این سرورها کافی نبود.',
              'پورت های ثابت هسته در همین لحظه: '
                  '${(await UmbrellaCore.heldReservedPorts()).isEmpty ? 'آزاد' : 'گرفته شده'}',
            ].join('\n'),
          ),
        ],
      );
    }
    _notify();
  }

  /// بستن سنجش های در جریان و صبر تا آزاد شدن پورت های ثابت هسته.
  Future<void> _stopProbes() async {
    if (!_measuring && !_corePing.busy) {
      return;
    }
    _measuring = false;
    await _corePing.stopAll();
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      final List<int> held = await UmbrellaCore.heldReservedPorts();
      if (held.isEmpty) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// پینگ شبکه سرور متصل (باز کردن اتصال تی سی پی به خود سرور).
  ///
  /// این سنجش تونل کاربر را دست نمی زند و فقط برای این است که عدد پینگ سرور
  /// متصل هیچ وقت صفر نماند.
  Future<void> _measureActiveNetworkPing(VpnNode node) async {
    if (_disposed) {
      return;
    }
    final VpnNode updated = await _ping.measure(node, attempts: 1);
    if (_disposed || !updated.hasPing) {
      return;
    }
    _nodes = _nodes
        .map((VpnNode item) => item.id == node.id ? updated : item)
        .toList();
    if (_activeNode?.id == node.id) {
      _activeNode = updated;
    }
  }

  /// بازه تاخیر تونل برای گزارش ها؛ برای عیب یابی سنجش.
  static String _tunnelNote(Map<String, int> delays) {
    if (delays.isEmpty) {
      return '';
    }
    final List<int> values = delays.values.toList()..sort();
    return ' بازه تاخیر تونل: ${Fa.num(values.first)} تا ${Fa.num(values.last)} '
        'میلی ثانیه.';
  }

  /// خلاصه عددی پینگ برای گزارش ها (کمترین و میانه).
  static String _medianNote(List<VpnNode> nodes) {
    final List<int> values = <int>[
      for (final VpnNode node in nodes)
        if (node.hasPing) node.pingMs,
    ]..sort();
    if (values.isEmpty) {
      return '';
    }
    return ' کمترین ${Fa.num(values.first)} و میانه '
        '${Fa.num(values[values.length ~/ 2])} میلی ثانیه.';
  }

  /// ترتیب فهرست سرورها بر اساس حالت انتخاب کاربر.
  ///
  /// در حالت گردشی ترتیب اشتراک نگه داشته می شود تا نوبت ها دیده شوند، در
  /// حالت هش پایدار ترتیب بر اساس شناسه ثابت می ماند و در حالت نشست چسبنده
  /// سرور فعلی بالا می ماند؛ حالت خودکار همان کمترین پینگ است.
  int _sortNodes(VpnNode a, VpnNode b) {
    switch (_settings.selectionMode) {
      case SelectionMode.roundRobin:
        return 0;
      case SelectionMode.consistentHash:
        return _stableHash(a.id).compareTo(_stableHash(b.id));
      case SelectionMode.stickySession:
        final bool aPinned = a.id == _settings.lastNodeId;
        final bool bPinned = b.id == _settings.lastNodeId;
        if (aPinned != bPinned) {
          return aPinned ? -1 : 1;
        }
        return _byPing(a, b);
      case SelectionMode.auto:
      case SelectionMode.manual:
        break;
    }
    return _byPing(a, b);
  }

  static int _byPing(VpnNode a, VpnNode b) {
    if (a.hasPing != b.hasPing) {
      return a.hasPing ? -1 : 1;
    }
    if (!a.hasPing) {
      return a.name.compareTo(b.name);
    }
    return a.pingMs.compareTo(b.pingMs);
  }

  static int _stableHash(String value) {
    int hash = 5381;
    for (final int code in value.codeUnits) {
      hash = ((hash << 5) + hash + code) & 0x7fffffff;
    }
    return hash;
  }

  Future<void> toggleFavorite(VpnNode node) async {
    _nodes = _nodes
        .map(
          (VpnNode item) => item.id == node.id
              ? item.copyWith(favorite: !item.favorite)
              : item,
        )
        .toList();
    await _cacheNodes();
    _scheduleRuntimePrewarm();
    _notify();
  }

  void updateSettings(AppSettings settings) {
    final AppSettings previous = _settings;
    _settings = settings;
    if (!settings.autoConnect) {
      _autoConnectRetryTimer?.cancel();
      _autoConnectRetryTimer = null;
    }
    _sound.enabled = settings.soundEnabled;
    final bool pingChanged = _pingTimer == null ||
        previous.pingIntervalSeconds != settings.pingIntervalSeconds;
    if (pingChanged) {
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(
        Duration(seconds: settings.pingIntervalSeconds.clamp(120, 3600)),
        (_) {
          // در حین اتصال یا پس از آن، عدد زنده همان اتصال خوانده می شود؛
          // بالا آوردن هسته سنجش، خود اتصال را می کشت.
          if (_status.active) {
            return;
          }
          unawaited(refreshPings(all: false));
        },
      );
    }
    final bool runtimeChanged = _runtimeSettingsChanged(previous, settings);
    if (runtimeChanged) {
      _scheduleRuntimePrewarm();
    }
    final bool traySpeedChanged =
        previous.showSpeedInTray != settings.showSpeedInTray;
    if (traySpeedChanged && _status == VpnStatus.connected) {
      final String tooltip = settings.showSpeedInTray && _stats.available
          ? '${AppConfig.appName} - ${Fa.speed(_stats.downSpeed)} / ${Fa.speed(_stats.upSpeed)}'
          : '${AppConfig.appName} - متصل';
      unawaited(
        _tray.update(
          state: 'connected',
          tooltip: tooltip,
          connected: true,
        ),
      );
    }
    // تغییر صرفاً ظاهری (مثل جابه جایی تم روشن/تاریک) نباید همه مصرف کنندگان
    // `VpnController` را دوباره بسازد یا پیش گرم سازی هسته را راه بیندازد.
    if (runtimeChanged || pingChanged || traySpeedChanged) {
      _notify();
    }
  }

  static bool _runtimeSettingsChanged(AppSettings a, AppSettings b) {
    if (a.tunMode != b.tunMode ||
        a.corePreference != b.corePreference ||
        a.serviceMode != b.serviceMode ||
        a.selectionMode != b.selectionMode ||
        a.autoFailover != b.autoFailover ||
        a.stickyMinutes != b.stickyMinutes ||
        a.freeCorePorts != b.freeCorePorts ||
        a.killSwitch != b.killSwitch ||
        a.showCli != b.showCli ||
        a.tunStack != b.tunStack ||
        a.mtu != b.mtu ||
        a.blockIpv6 != b.blockIpv6 ||
        a.ipv6RouteMode != b.ipv6RouteMode ||
        a.strictRoute != b.strictRoute ||
        a.mixedPort != b.mixedPort ||
        a.localProxyInVpn != b.localProxyInVpn ||
        a.localProxyAuth != b.localProxyAuth ||
        a.allowConnectionFromLan != b.allowConnectionFromLan ||
        a.lanSharingPort != b.lanSharingPort ||
        a.lanSharingPassword != b.lanSharingPassword ||
        a.remoteDns != b.remoteDns ||
        a.directDns != b.directDns ||
        a.remoteDnsStrategy != b.remoteDnsStrategy ||
        a.directDnsStrategy != b.directDnsStrategy ||
        a.enableFakeDns != b.enableFakeDns ||
        a.routingRegion != b.routingRegion ||
        a.bypassLan != b.bypassLan ||
        a.blockAds != b.blockAds ||
        a.httpsAdFilter != b.httpsAdFilter ||
        a.httpsAdFilterMode != b.httpsAdFilterMode ||
        a.resolveDestination != b.resolveDestination ||
        a.blockQuic != b.blockQuic ||
        a.tlsTricks != b.tlsTricks ||
        a.logLevel != b.logLevel ||
        a.serverRegionCode != b.serverRegionCode ||
        a.lastNodeId != b.lastNodeId ||
        _chainChanged(a.chain, b.chain) ||
        a.appRoutes.length != b.appRoutes.length) {
      return true;
    }
    if (identical(a.appRoutes, b.appRoutes)) {
      return false;
    }
    for (int i = 0; i < a.appRoutes.length; i++) {
      final AppRouteRule x = a.appRoutes[i];
      final AppRouteRule y = b.appRoutes[i];
      if (x.process != y.process ||
          x.action != y.action ||
          x.enabled != y.enabled) {
        return true;
      }
    }
    return false;
  }

  static bool _chainChanged(ChainSettings a, ChainSettings b) {
    if (identical(a, b)) {
      return false;
    }
    return a.position != b.position ||
        a.transport != b.transport ||
        a.endpoint != b.endpoint ||
        a.address != b.address ||
        a.port != b.port ||
        a.mtu != b.mtu ||
        a.scanCount != b.scanCount ||
        a.scanConcurrency != b.scanConcurrency ||
        a.scanTimeout != b.scanTimeout ||
        a.scanMaxRtt != b.scanMaxRtt ||
        a.searchNoise != b.searchNoise ||
        a.configurationInvalid != b.configurationInvalid ||
        a.masqueProtocol != b.masqueProtocol ||
        a.licenseKey != b.licenseKey ||
        a.psiphonRegion != b.psiphonRegion ||
        a.noiseMode != b.noiseMode ||
        a.noiseCount != b.noiseCount ||
        a.noiseSize != b.noiseSize ||
        a.noiseDelay != b.noiseDelay;
  }

  Timer? _liveReloadTimer;

  /// بازاعمال خودکار تنظیمات هسته روی اتصال فعال (حالت سرویس، اشتراک LAN،
  /// امنیت بیشتر، رفع فیلتر پروکسی، مسیریابی، DNS، ورودی و ترفندهای TLS).
  void scheduleLiveReload() {
    _liveReloadTimer?.cancel();
    if (_connectInFlight) {
      _pendingLiveReload = true;
      return;
    }
    if (!_status.active) {
      return;
    }
    _liveReloadTimer = Timer(const Duration(milliseconds: 350), () {
      if (_disposed || _shuttingDown) {
        return;
      }
      if (_connectInFlight) {
        _pendingLiveReload = true;
        return;
      }
      if (!_status.active) {
        return;
      }
      unawaited(() async {
        final VpnNode? target =
            _autoSession ? null : (_singleNodeSession ? _activeNode : null);
        final bool emergency = _emergencySession;
        await disconnect(silent: true);
        if (!_disposed && !_shuttingDown) {
          await connect(requested: target, emergency: emergency);
        }
      }());
    });
  }

  /// درخواست لغو اتصال در حال انجام.
  ///
  /// ساخت تونل چند ثانیه طول می کشد و کاربر باید هر لحظه بتواند پشیمان شود؛
  /// با زدن دکمه قطع، این پرچم بالا می رود، حلقه تلاش هسته ها می شکند و همه
  /// چیز تمیز بسته می شود.
  int _cancelGeneration = 0;
  int _lastLoggedCancelGeneration = -1;
  bool _cancelRequested = false;
  bool _singleNodeSession = false;
  String _activeCoreLogPath = '';
  bool get cancelling => _cancelRequested;

  /// لغو فوری اتصال در حال انجام (دکمه «لغو اتصال»).
  Future<void> cancel() async {
    _autoConnectRetryTimer?.cancel();
    _autoConnectRetryTimer = null;
    if (!_waitingForNetwork &&
        !_connectInFlight &&
        !_status.busy &&
        _status != VpnStatus.connected) {
      return;
    }
    _cancelGeneration++;
    _cancelRequested = true;
    _waitingForNetwork = false;
    _stopNetworkWatcher();
    _requestedNode = null;
    _autoSession = false;
    _log.add('درخواست لغو اتصال از طرف کاربر.', level: 'warning');
    _setStatus(VpnStatus.disconnecting, 'لغو اتصال...');
    await _stopCores();
    await _disableProxy();
    _finishCancel();
  }

  void _finishCancel() {
    _statsTimer?.cancel();
    _healthTimer?.cancel();
    _ipTimer?.cancel();
    _waitingForNetwork = false;
    _stopNetworkWatcher();
    _stopLiveMeasurement();
    _connectedAt = null;
    _stats = TunnelStats.empty;
    _tunnelVerified = false;
    _exitIp = '';
    // Keep cancellation latched until the in-flight connect has unwound.
    if (!_connectInFlight) {
      _cancelRequested = false;
      _requestedNode = null;
      _autoSession = false;
    }
    _activeNode = null;
    _setStatus(VpnStatus.disconnected, 'اتصال قطع شد.');
    unawaited(
      _tray.update(
        state: 'disconnected',
        tooltip: '${AppConfig.appName} - قطع',
        connected: false,
      ),
    );
    if (_lastLoggedCancelGeneration != _cancelGeneration) {
      _lastLoggedCancelGeneration = _cancelGeneration;
      _log.add('اتصال لغو شد و تنظیمات شبکه به حالت عادی بازگشت.');
    }
  }

  /// اتصال با تلاش روی چند سرور: اگر یک سرور بالا نیامد، سرور بعدی امتحان
  /// می شود تا کاربر مجبور نشود دستی سرور عوض کند.
  Future<ConnectOutcome> connect({
    VpnNode? requested,
    bool isAutoReconnect = false,
    bool emergency = false,
  }) async {
    // فقط یک اتصال همزمان.
    //
    // در گزارش ۱٫۰۱۲ دو «درخواست اتصال» با سه ثانیه فاصله آمد و هر دو
    // اجرا شدند. هر کدام هسته خودش را بالا می آورد، هر دو پورت ثابت ۱۷۰۷۸ را
    // می خواستند، و نتیجه اش همان «port 17078 is already in use» پشت سر هم و
    // کشته شدن هسته ای بود که تازه کار کرده بود. همچنین وضعیت بلافاصله در
    // ورود به `connect()` تغییر می کند تا کاربر از همان لحظه اول «در حال اتصال»
    // را ببیند.
    if (_connectInFlight) {
      return const ConnectOutcome(
        ok: false,
        message: 'یک اتصال در حال انجام است؛ چند لحظه صبر کنید.',
      );
    }
    if (_status.active) {
      return const ConnectOutcome(ok: false, message: 'اتصال از قبل برقرار است.');
    }
    if (!isAutoReconnect) {
      _waitingForNetwork = false;
      _reconnectAttempts = 0;
      _emergencySession = emergency;
      _requestedNode = requested;
      _autoSession = requested == null && !emergency;
    }
    _connectInFlight = true;
    _cancelRequested = false;
    _setStatus(
      isAutoReconnect ? VpnStatus.reconnecting : VpnStatus.connecting,
      isAutoReconnect ? 'در حال اتصال دوباره...' : 'در حال آماده سازی اتصال...',
    );
    try {
      final ConnectOutcome outcome = await _connectInner(requested: requested);
      return _cancelRequested ? const ConnectOutcome(ok: false, cancelled: true, message: 'اتصال لغو شد.') : outcome;
    } finally {
      final bool wasCancelled = _cancelRequested;
      if (wasCancelled) {
        await _stopCores();
        await _disableProxy();
        _finishCancel();
      }
      _connectInFlight = false;
      _cancelRequested = false;
      final bool reloadQueued = _pendingLiveReload;
      _pendingLiveReload = false;
      if (!wasCancelled && !_disposed && !_shuttingDown && _status == VpnStatus.connected) {
        if (reloadQueued) {
          scheduleLiveReload();
        } else if (_launchedFilterSignature != _contentFilter.effectSignature) {
          _scheduleFilterHotReload(_contentFilter);
        }
      }
    }
  }

  /// ساخت زنجیره چندمرحله ای اتصال خودکار (`خودکار`):
  /// ۱) گروه اشتراک عمومی (`!DirectProfile.handles`) به ترتیب انتخاب گر؛
  /// ۲) پروفایل های مستقیم (`DirectProfile.handles`: WireGuard / AmneziaWG / Mieru)؛
  /// ۳) مسیر اضطراری (`emergencyNodes`) به عنوان آخرین پشتیبان در صورت نبود یا شکست مراحل قبل.
  @visibleForTesting
  static List<VpnNode> buildAutoCandidates({
    required List<VpnNode> personalNodes,
    required List<VpnNode> emergencyNodes,
    required NodeBalancer balancer,
    required SelectionMode mode,
    required String deviceSeed,
    required String preferredNodeId,
    required int stickyMinutes,
    required bool allowFailover,
    required bool emergencyOnly,
    required bool Function(VpnNode node) accepts,
  }) {
    if (emergencyOnly) {
      final List<VpnNode> emUsable = emergencyNodes.where(accepts).toList();
      if (emUsable.isEmpty) return const <VpnNode>[];
      final List<VpnNode> emPool = emUsable
          .where((VpnNode n) => !DirectProfile.handles(n))
          .toList();
      final List<VpnNode> emDirect = emUsable
          .where((VpnNode n) => DirectProfile.handles(n))
          .toList();
      final List<VpnNode> emStages = <VpnNode>[];
      if (emPool.isNotEmpty) {
        final SelectionResult picked = balancer.pick(
          nodes: emPool,
          mode: mode,
          deviceSeed: deviceSeed,
          preferredNodeId: preferredNodeId,
          stickyMinutes: stickyMinutes,
          allowFailover: allowFailover,
        );
        emStages.add(picked.node ?? emPool.first);
      }
      emStages
        ..addAll(emDirect.where((VpnNode n) => n.favorite))
        ..addAll(emDirect.where((VpnNode n) => !n.favorite));
      return emStages;
    }

    final List<VpnNode> usablePersonal =
        personalNodes.where(accepts).toList();
    final List<VpnNode> poolNodes = usablePersonal
        .where((VpnNode n) => !DirectProfile.handles(n))
        .toList();
    final List<VpnNode> directNodes = usablePersonal
        .where((VpnNode n) => DirectProfile.handles(n))
        .toList();

    final List<VpnNode> stages = <VpnNode>[];
    final List<VpnNode> pinnedDirect =
        directNodes.where((VpnNode n) => n.favorite).toList();
    final List<VpnNode> normalDirect =
        directNodes.where((VpnNode n) => !n.favorite).toList();

    VpnNode? pickedPool;
    if (poolNodes.isNotEmpty) {
      final SelectionResult picked = balancer.pick(
        nodes: poolNodes,
        mode: mode,
        deviceSeed: deviceSeed,
        preferredNodeId: preferredNodeId,
        stickyMinutes: stickyMinutes,
        allowFailover: allowFailover,
      );
      pickedPool = picked.node ?? poolNodes.first;
    }

    final bool preferredIsHealthyDirect = preferredNodeId.isNotEmpty &&
        directNodes.any(
          (VpnNode n) =>
              n.id == preferredNodeId && !balancer.recentlyFailed(n),
        );
    final bool allPoolFailed = poolNodes.isNotEmpty &&
        poolNodes.every(balancer.recentlyFailed) &&
        directNodes.any((VpnNode n) => !balancer.recentlyFailed(n));

    if ((preferredIsHealthyDirect || allPoolFailed) && directNodes.isNotEmpty) {
      if (preferredIsHealthyDirect) {
        final VpnNode pref = directNodes.firstWhere(
          (VpnNode n) => n.id == preferredNodeId,
        );
        stages.add(pref);
        stages
          ..addAll(pinnedDirect.where((VpnNode n) => n.id != pref.id))
          ..addAll(normalDirect.where((VpnNode n) => n.id != pref.id));
      } else {
        stages
          ..addAll(pinnedDirect)
          ..addAll(normalDirect);
      }
      if (pickedPool != null) {
        stages.add(pickedPool);
      }
    } else {
      if (pickedPool != null) {
        stages.add(pickedPool);
      }
      stages
        ..addAll(pinnedDirect)
        ..addAll(normalDirect);
    }

    final List<VpnNode> emPool = emergencyNodes
        .where((VpnNode n) => !DirectProfile.handles(n) && accepts(n))
        .toList();
    final List<VpnNode> emDirect = emergencyNodes
        .where((VpnNode n) => DirectProfile.handles(n) && accepts(n))
        .toList();
    if (emPool.isNotEmpty) {
      final SelectionResult emPicked = balancer.pick(
        nodes: emPool,
        mode: mode,
        deviceSeed: deviceSeed,
        preferredNodeId: '',
        stickyMinutes: stickyMinutes,
        allowFailover: allowFailover,
      );
      stages.add(emPicked.node ?? emPool.first);
    }
    stages.addAll(emDirect);
    return stages;
  }

  Future<ConnectOutcome> _connectInner({VpnNode? requested}) async {
    _cancelRequested = false;
    _singleNodeSession = requested != null || (!_emergencySession &&
        (_settings.selectionMode == SelectionMode.manual || !_settings.autoFailover));
    await _cancelRuntimePrewarm();
    if (_cancelRequested) return const ConnectOutcome(ok: false, cancelled: true, message: 'اتصال لغو شد.');
    // سنجش در جریان همین حالا بسته می شود: نمونه هایش پورت های ثابت هسته
    // (۱۷۰۷۸ و ۱۶۷۵۶) را گرفته اند و اتصال بدون آن ها ممکن نیست.
    await _stopProbes();
    if (_cancelRequested) return const ConnectOutcome(ok: false, cancelled: true, message: 'اتصال لغو شد.');
    // دسترسی حساب: اشتراک منقضی، مسدود یا تمام شده حق اتصال ندارد.
    final String blocked = accessGuard?.call() ?? '';
    if (blocked.isNotEmpty) {
      _log.add('اتصال رد شد: $blocked', level: 'warning');
      _setStatus(VpnStatus.failed, blocked);
      return ConnectOutcome(ok: false, message: blocked, needsRenewal: true);
    }
    // بستن تمام وی پی ان ها و هسته های باز قبلی پیش از بررسی سپر امنیتی و اتصال.
    if (_native.available) {
      await _terminateForeignCores();
      if (_cancelRequested) {
        return const ConnectOutcome(ok: false, cancelled: true, message: 'اتصال لغو شد.');
      }
    }
    // سپر امنیتی همیشه فعال: در صورت وجود بدافزار یا VPN ناسازگار (مثل JumpJump یا Psiphon) اتصال مسدود می شود.
    if (securityGuard != null) {
      final String secBlocked = await securityGuard!();
      if (_cancelRequested) {
        return const ConnectOutcome(ok: false, cancelled: true, message: 'اتصال لغو شد.');
      }
      if (secBlocked.isNotEmpty) {
        _log.add('اتصال به دلیل سپر امنیتی رد شد: $secBlocked', level: 'warning');
        _setStatus(VpnStatus.failed, secBlocked);
        return ConnectOutcome(
          ok: false,
          message: secBlocked,
          needsSecurityCleanup: true,
        );
      }
    }
    final String? chainError = _settings.chain.enabled ? _settings.chain.validationError : null;
    final String? routeError = _settings.appRoutes
        .map((AppRouteRule rule) => rule.validationError).whereType<String>().firstOrNull;
    if (chainError != null || routeError != null || _settings.appRoutes.length > 64) {
      final String msg = chainError ?? routeError ?? 'حداکثر ۶۴ قانون برنامه مجاز است';
      _setStatus(VpnStatus.failed, msg);
      return ConnectOutcome(ok: false, message: msg);
    }
    if (_settings.appRoutes.any((AppRouteRule rule) => rule.enabled) &&
        (!_settings.tunMode || !_device.elevated)) {
      const String msg =
          'قواعد برنامه فعال است؛ تونل را روشن و برنامه را با دسترسی مدیر اجرا کنید، یا قواعد را غیرفعال کنید.';
      _setStatus(VpnStatus.failed, msg);
      return ConnectOutcome(
        ok: false,
        needsElevation: _settings.tunMode && !_device.elevated,
        message: msg,
      );
    }
    final bool hasAnyPool = _sessionNodes.isNotEmpty ||
        (requested == null && !_emergencySession && _emergencyNodes.isNotEmpty);
    if (!hasAnyPool) {
      const String msg = 'هیچ سروری موجود نیست؛ اشتراک در حال دریافت از سرور است.';
      _setStatus(VpnStatus.failed, msg);
      return const ConnectOutcome(ok: false, message: msg);
    }
    final List<VpnNode> usableSessionNodes = _sessionNodes
        .where((VpnNode node) => usable(node) && !node.disabled)
        .toList();
    final List<VpnNode> usableEmergencyFallback =
        (requested == null && !_emergencySession)
            ? _emergencyNodes
                .where((VpnNode node) => usable(node) && !node.disabled)
                .toList()
            : const <VpnNode>[];
    if (usableSessionNodes.isEmpty && usableEmergencyFallback.isEmpty) {
      _log.add(
        'هیچ سروری از ${Fa.num(_nodes.length)} سرور اشتراک برای هسته آمبرلا '
        'ورودی معتبر نداشت.',
        level: 'error',
        details: <LogDetail>[
          LogDetail(
            title: 'چرا هیچ سروری قبول نشد',
            text: _whyNoUsableServer(),
          ),
          LogDetail(
            title: 'پروتکل سرورهای اشتراک',
            text: _protocolBreakdown(),
          ),
        ],
      );
      const String msg = 'سروری که با این نسخه کار کند در اشتراک شما نیست.';
      _setStatus(VpnStatus.failed, msg);
      return const ConnectOutcome(ok: false, message: msg);
    }

    if (requested != null &&
        !usableSessionNodes.any((VpnNode node) => node.id == requested.id)) {
      const String msg = 'پروفایل انتخابی معتبر نیست.';
      _setStatus(VpnStatus.failed, msg);
      return const ConnectOutcome(ok: false, message: msg);
    }

    final String deviceSeed = _device.machineId.isNotEmpty
        ? _device.machineId
        : _device.hostname;
    final List<VpnNode> autoStages = requested == null
        ? buildAutoCandidates(
            personalNodes: _nodes,
            emergencyNodes: _emergencyNodes,
            balancer: _balancer,
            mode: _settings.selectionMode,
            deviceSeed: deviceSeed,
            preferredNodeId: _settings.lastNodeId,
            stickyMinutes: _settings.stickyMinutes,
            allowFailover: _settings.autoFailover,
            emergencyOnly: _emergencySession,
            accepts: (VpnNode node) =>
                usable(node) && !node.disabled && _fitsPreference(node),
          )
        : const <VpnNode>[];

    final List<VpnNode> candidates;
    if (requested != null) {
      if (!_fitsPreference(requested)) {
        const String message = 'سروری که با این نسخه کار کند در اشتراک شما نیست.';
        _setStatus(VpnStatus.failed, message);
        return const ConnectOutcome(ok: false, message: message);
      }
      candidates = _singleNodeSession
          ? _candidates(requested, 'سرور انتخابی شما.')
          : <VpnNode>[requested];
    } else {
      if (autoStages.isEmpty) {
        const String message = 'سروری که با این نسخه کار کند در اشتراک شما نیست.';
        _setStatus(VpnStatus.failed, message);
        return const ConnectOutcome(ok: false, message: message);
      }
      candidates = _singleNodeSession
          ? <VpnNode>[autoStages.first]
          : autoStages;
    }

    final String profileLabel = _emergencySession
        ? 'اضطراری'
        : (requested == null ? 'خودکار' : requested.protocol.label);
    _log.add(
      'درخواست اتصال: نوع «$profileLabel»، ${Fa.num(requested == null ? candidates.length : 1)} مرحله مسیر برای این انتخاب، '
      'حالت «${_settings.corePreference.faName}» با هسته آمبرلا.',
    );
    _setStatus(VpnStatus.connecting, 'آماده سازی هسته و بررسی شبکه...');
    try {
      if (_native.available && !_device.elevated) {
        final bool ok = await _native.relaunchElevated();
        _setStatus(VpnStatus.disconnected, 'نیاز به دسترسی مدیر');
        onRequireElevation?.call();
        return ConnectOutcome(
          ok: false,
          needsElevation: true,
          message: ok
              ? 'برنامه با دسترسی مدیر دوباره باز می شود.'
              : 'برای ساخت تونل، برنامه را با دسترسی مدیر اجرا کنید.',
        );
      }

      // Real-IP discovery already runs at initialization. It is diagnostic,
      // not a prerequisite for opening the VPN (blocked geo APIs took ~19s).
      if (_cancelRequested) return const ConnectOutcome(ok: false, cancelled: true, message: 'اتصال لغو شد.');

      _unusableInThisRun.clear();
      // کل اشتراک امتحان می شود، نه چند سرور اول. بودجه زمانی فقط برای وقتی
      // است که هیچ کدام جواب نمی دهند؛ در آن حالت برنامه نباید برای همیشه
      // روی «تلاش N از M» بماند و باید به کاربر بگوید چه کرد.
      final DateTime connectDeadline = DateTime.now().add(_connectBudget);
      String lastMessage = '';
      int attempted = 0;
      for (int index = 0; index < candidates.length; index++) {
        if (_cancelRequested) {
          return const ConnectOutcome(ok: false, cancelled: true, message: 'اتصال لغو شد.');
        }
        if (index > 0 && DateTime.now().isAfter(connectDeadline)) {
          _log.add(
            'بودجه زمانی اتصال تمام شد: ${Fa.num(attempted)} مرحله از '
            '${Fa.num(candidates.length)} مسیر امتحان شد و هیچ '
            'کدام تونل نساخت.',
            level: 'warning',
          );
          break;
        }
        final VpnNode candidate = candidates[index];
        if (candidates.length > 1) {
          final String stageLabel = candidate.sourceId.startsWith('emergency-')
              ? 'اضطراری'
              : (DirectProfile.handles(candidate)
                  ? candidate.protocol.label
                  : 'اشتراک');
          _setStatus(
            VpnStatus.connecting,
            'تلاش ${Fa.num(index + 1)} از ${Fa.num(candidates.length)}: $stageLabel',
          );
          if (index > 0) {
            _log.add(
              'مسیر قبلی پاسخ نداد؛ تلاش خودکار روی مسیر «$stageLabel»...',
              level: 'info',
            );
          }
        }
        attempted++;
        final _AttemptResult attempt = await _attempt(candidate);
        if (attempt.cancelled) {
          return const ConnectOutcome(ok: false, cancelled: true, message: 'اتصال لغو شد.');
        }
        if (attempt.ok) {
          return const ConnectOutcome(ok: true, message: 'اتصال برقرار شد.');
        }
        lastMessage = attempt.message;
        _balancer.markFailed(candidate.id);
        if (attempt.unusable) {
          // لینک این سرور با هسته خوانده نمی شود؛ تلاش دوباره با همان لینک
          // همان نتیجه را می دهد، پس در این دور کنار گذاشته می شود.
          _unusableInThisRun.add(candidate.id);
        }
        if (attempt.needsCores) {
          return ConnectOutcome(
            ok: false,
            needsCores: true,
            message: attempt.message,
          );
        }
      }

      await _failAndCleanup(
        lastMessage.isEmpty ? 'اتصال برقرار نشد.' : lastMessage,
      );
      return ConnectOutcome(ok: false, message: lastMessage);
    } on ApiError catch (error) {
      await _failAndCleanup(error.message);
      return ConnectOutcome(ok: false, message: error.message);
    } on Exception catch (error) {
      await _failAndCleanup('خطای غیرمنتظره: $error');
      return const ConnectOutcome(
        ok: false,
        message: 'خطای غیرمنتظره در اتصال؛ گزارش ها را ببینید.',
      );
    }
  }

  /// آیا این سرور با هسته انتخابی کاربر اجرا می شود؟
  bool _fitsPreference(VpnNode node) =>
      fitsPreference(_settings.corePreference, node);

  /// همان بررسی برای آزمون پذیری.
  ///
  /// هسته یکی است و همه پروتکل ها را می شناسد، پس حالت انتخابی هیچ سروری را
  /// حذف نمی کند؛ فقط تعیین می کند اول با تونل کامل وصل شود یا با پروکسی
  /// سیستمی. اگر راه اول نشد، همان هسته با حالت دیگر امتحان می شود.
  static bool fitsPreference(CorePreference preference, VpnNode node) => true;

  /// سرور انتخاب شده و بعد از او **همه** سرورهای اشتراک، به ترتیب اولویت.
  ///
  /// **شکایت کاربر (۱٫۰٫۱۹):** تا این نسخه این فهرست فقط چهار تای اول را
  /// می داد و رابط «تلاش ۱ از ۴» می نوشت. یعنی از ۳۳۱ سروری که اشتراک
  /// خوانده بود فقط چهار تای اول امتحان می شد؛ اگر آن ها بی جواب می ماندند،
  /// کاربر «هیچ هسته ای نتوانست تونل را بالا بیاورد» می دید، در حالی که
  /// هدیفای همه لینک های داخل اشتراک را یک جا می سنجد و سراغ سرور بعدی
  /// می رود. حالا کل اشتراک در امتحان می آید.
  ///
  /// خود هسته هم همه لینک ها را در یک اجرا می گیرد ([_linkPool])، پس سنجش
  /// «همه سرورها» در یک نوبت انجام می شود؛ این حلقه برای عیب یابی و برای
  /// زمانی است که هسته اصلاً بالا نیامده باشد. بودجه زمانی [_connectBudget]
  /// مانع می شود درخواست برای همیشه روی همین حلقه بماند.
  List<VpnNode> _candidates(VpnNode first, String reason) {
    final List<VpnNode> list = <VpnNode>[first];
    if (_singleNodeSession) {
      return list;
    }
    final List<VpnNode> rest = _nodes
        .where((VpnNode node) =>
            node.id != first.id &&
            !node.disabled &&
            usable(node) &&
            !_unusableInThisRun.contains(node.id) &&
            _fitsPreference(node))
        .toList();
    switch (_settings.selectionMode) {
      case SelectionMode.roundRobin:
        // پس از سرور فعلی، نوبت سرورهای بعدی در همان ترتیب اشتراک است.
        final int start =
            _nodes.indexWhere((VpnNode node) => node.id == first.id);
        if (start >= 0 && _nodes.length > 1) {
          final List<VpnNode> rotation = <VpnNode>[];
          for (int step = 1; step < _nodes.length; step++) {
            final VpnNode candidate = _nodes[(start + step) % _nodes.length];
            if (candidate.id != first.id &&
                !candidate.disabled &&
                usable(candidate) &&
                !_unusableInThisRun.contains(candidate.id) &&
                _fitsPreference(candidate)) {
              rotation.add(candidate);
            }
          }
          rotation.addAll(
            rest.where(
              (VpnNode node) =>
                  !rotation.any((VpnNode item) => item.id == node.id),
            ),
          );
          rest
            ..clear()
            ..addAll(rotation);
        }
        break;
      case SelectionMode.consistentHash:
        rest.sort(
          (VpnNode a, VpnNode b) =>
              _stableHash(a.id).compareTo(_stableHash(b.id)),
        );
        break;
      case SelectionMode.stickySession:
      case SelectionMode.auto:
      case SelectionMode.manual:
        rest.sort(_byPing);
    }
    // پین ها پیش از سایر گزینه های failover می آیند تا اولویت کاربر حفظ شود.
    final List<VpnNode> pinned = rest.where((VpnNode node) => node.favorite).toList();
    final List<VpnNode> ordinary = rest.where((VpnNode node) => !node.favorite).toList();
    // همه سرورهای سازگار اشتراک به امتحان می آیند، نه چند تای اول.
    list..addAll(pinned)..addAll(ordinary);
    return list;
  }

  /// یک تلاش اتصال به یک سرور مشخص.
  Future<_AttemptResult> _attempt(VpnNode node) async {
    _activeNode = node;
    _livePing = 0;
    _stats = TunnelStats.empty;
    _notify();

    // ۱. بستن هر فیلترشکن فعال دیگر و پروکسی بازمانده پیش از اجرا.
    await _terminateForeignCores();
    _proxyPort = 0;

    // ۲. آماده سازی هسته ها از نسخه نصب (بدون هیچ دانلودی)
    for (final CoreInfo core in _provisioner.catalog) {
      if (core.requiredCore) {
        await _provisioner.provision(core);
      }
    }
    final List<LaunchPlan> plans = await _buildPlans(node);
    if (plans.isEmpty) {
      if (_lastPlanNeedsCore) {
        _setStatus(VpnStatus.failed, 'هسته لازم در دسترس نیست.');
        onRequireCores?.call();
        return const _AttemptResult(
          message: 'هسته اتصال در دسترس نیست؛ برنامه را با نصب کننده رسمی دوباره نصب کنید.',
          needsCores: true,
        );
      }
      _setStatus(VpnStatus.connecting, 'سرور بعدی امتحان می شود.');
      return const _AttemptResult(
        message: 'هسته آمبرلا برای این سرور ورودی معتبری نداشت؛ سرور بعدی امتحان می شود.',
      );
    }

    // یک هسته است، دو حالت: اگر راه اول (تونل کامل) به دلیل کارت شبکه یا
    // مسیر ویندوز بالا نیامد ولی خود پروکسی هسته سالم بود، همان هسته با
    // پروکسی سیستمی وصل می شود؛ اما اگر هیچ سروری پاسخ نداد، وقت کاربر با
    // تکرار بی فایده همان فهرست گرفته نمی شود.
    bool allowProxyFallbackNow = false;
    for (int planIndex = 0; planIndex < plans.length; planIndex++) {
      final LaunchPlan plan = plans[planIndex];
      if (planIndex > 0 && plan.usesSystemProxy && !allowProxyFallbackNow) {
        break;
      }
      if (_cancelRequested) {
        await _stopCores();
        await _disableProxy();
        return const _AttemptResult(cancelled: true, message: 'اتصال لغو شد.');
      }
      if (plan.warning.isNotEmpty) {
        _log.add(plan.warning, level: 'warning');
      }
      // پیش از هر تلاش، پورت های هسته آزاد می شوند.
      await _stopCores();
      if (_cancelRequested) return const _AttemptResult(cancelled: true, message: 'اتصال لغو شد.');
      final bool portFree = await _freeCorePortsWithRetry();
      if (!portFree) {
        _log.add(
          'پورت هسته پیش از تلاش بعدی آزاد نشد؛ این حالت امتحان نمی شود.',
          level: 'warning',
        );
        continue;
      }
      if (_cancelRequested) return const _AttemptResult(cancelled: true, message: 'اتصال لغو شد.');
      _setStatus(VpnStatus.connecting, 'اجرای هسته و ساخت تونل...');
      final DateTime sessionStart = DateTime.now().toUtc();
      final bool started = await _launch(plan);
      if (!started) {
        final bool unusable = _lastLaunchUnusable;
        await _stopCores();
        await _disableProxy();
        if (unusable) {
          return _AttemptResult(
            message: '${_nodeLabel(node)} با موتور هسته خوانده نشد؛ سرور بعدی '
                'امتحان می شود.',
            unusable: true,
          );
        }
        if (plan.tun) {
          allowProxyFallbackNow = true;
        }
        continue;
      }

      final bool ready = await _waitForTunnel(plan);
      if (_cancelRequested) {
        await _stopCores();
        await _disableProxy();
        return const _AttemptResult(cancelled: true, message: 'اتصال لغو شد.');
      }
      if (!ready) {
        final String coreLog = _coreLogPath(plan);
        final String tail = await _readLogTail(coreLog);
        _log.add(
          plan.tun
              ? 'کارت شبکه تونل در ${Fa.num(_tunnelTimeout.inSeconds)} ثانیه '
                  'آماده نشد.'
                  '${tail.isEmpty ? '' : ' خروجی هسته: $tail'}'
              : 'پورت محلی هسته (${Fa.num(plan.readinessPort)}) در '
                  '${Fa.num(_tunnelTimeout.inSeconds)} ثانیه باز نشد.'
                  '${tail.isEmpty ? '' : ' خروجی هسته: $tail'}',
          level: 'error',
          details: await _coreDiagnostics(
            plan.cores.first,
            coreLog,
            plan: plan,
          ),
        );
        final String full = await _readLogFull(coreLog);
        final String why = _explainCoreExit(full);
        if (why.isNotEmpty) {
          _log.add(why, level: 'error');
        }
        final bool unusable = _linkUnusable(full);
        await _stopCores();
        await _disableProxy();
        if (unusable) {
          return _AttemptResult(
            message: '${_nodeLabel(node)} با موتور هسته خوانده نشد؛ سرور بعدی '
                'امتحان می شود.',
            unusable: true,
          );
        }
        if (plan.tun) {
          allowProxyFallbackNow = true;
        }
        continue;
      }

      // Match `hiddify-app` + `hiddify-core v5.9.1/v2/hcore/connectivity.go`:
      // once the box and inbound (TUN / mixed port) are running, enter Waiting
      // and transition to Connected the instant the core's outbound monitor
      // records a fresh non-cached URL-test reply (`0 < delay < 65000`), or stop
      // immediately on `NO_AVAILABLE_PROXIES` when every outbound timed out.
      // When an auxiliary chain hop (WARP / Psiphon / profile) is enabled, also
      // verify end-to-end HTTPS through the loopback mixed port because the hop
      // sits outside the `lowest` group.
      _setStatus(VpnStatus.connecting, 'در انتظار پاسخ سرور...');
      bool proxyEverVerified = false;
      bool poolExhausted = false;
      bool directRetested = false;
      int initialDelayMs = 0;
      CoreExitIpInfo? initialIpInfo;
      final Stopwatch waitClock = Stopwatch()..start();
      final bool flows = await StartupVerification.wait(
        cancelled: () => _cancelRequested || _disposed || poolExhausted,
        alive: () async => _coreProcesses.isNotEmpty ||
            await _native.isRunning(plan.primaryBinary),
        budget: (_singleNodeSession || DirectProfile.handles(node)) &&
                !_activeChain.enabled
            ? const Duration(seconds: 20)
            : const Duration(seconds: 60),
        interval: const Duration(milliseconds: 120),
        attemptTimeout: const Duration(seconds: 8),
        probe: (Duration timeout) async {
          final CoreProxySnapshot snapshot = await ClashApi.status(
            since: sessionStart,
            timeout: const Duration(milliseconds: 800),
          );
          if (_cancelRequested || _disposed) {
            return false;
          }
          if (snapshot.reachable) {
            if (snapshot.connectivity ==
                CoreConnectivityState.noAvailableProxies) {
              // A single direct profile can time out while its tunnel or DNS is
              // warming up. Test the same endpoint once against a second URL;
              // never silently switch to the automatic subscription.
              if (DirectProfile.handles(node) &&
                  !_activeChain.enabled && !directRetested) {
                directRetested = true;
                _log.add('مسیر «${node.protocol.label}» پاسخ نداد؛ همان مسیر با نشانی سنجش دیگری دوباره بررسی می شود.', level: 'warning');
                final int delay = await ClashApi.testDelay(
                  'umbrella-direct-profile',
                  testUrl: AppConfig.connectionTestUrls[2],
                  timeout: const Duration(seconds: 6),
                );
                if (_cancelRequested || _disposed) return false;
                if (PingService.plausible(delay)) {
                  initialDelayMs = delay;
                  proxyEverVerified = true;
                  return true;
                }
              }
              poolExhausted = true;
              return false;
            }
            if (snapshot.connectivity == CoreConnectivityState.started) {
              if (PingService.plausible(snapshot.activeDelayMs)) {
                initialDelayMs = snapshot.activeDelayMs;
              } else if (PingService.plausible(snapshot.bestDelayMs)) {
                initialDelayMs = snapshot.bestDelayMs;
              }
              initialIpInfo = snapshot.exitIpInfo;
              if (!_activeChain.enabled) {
                proxyEverVerified = true;
                return true;
              }
              // Chain hop enabled: ensure the hop finished handshaking too.
              final Duration cap = timeout < const Duration(seconds: 6)
                  ? timeout
                  : const Duration(seconds: 6);
              final bool chainOk = await VerifiedProbe.check(
                proxyPort: _probeProxyPort,
                proxyUser: _probeProxyUser,
                proxyPassword: _probeProxyPassword,
                timeout: cap,
              );
              if (chainOk) {
                proxyEverVerified = true;
              }
              return chainOk;
            }
            return false;
          }
          // Fallback only if the loopback Clash controller fails to respond
          // after initial startup while the engine process is still alive.
          if (waitClock.elapsed < const Duration(milliseconds: 2500)) {
            return false;
          }
          final Duration proxyCap = timeout < const Duration(seconds: 5)
              ? timeout
              : const Duration(seconds: 5);
          final bool proxy = await VerifiedProbe.check(
            proxyPort: _probeProxyPort,
            proxyUser: _probeProxyUser,
            proxyPassword: _probeProxyPassword,
            timeout: proxyCap,
          );
          if (proxy) {
            proxyEverVerified = true;
          }
          return proxy;
        },
      );
      if (_cancelRequested) {
        await _stopCores();
        await _disableProxy();
        return const _AttemptResult(cancelled: true, message: 'اتصال لغو شد.');
      }
      if (!flows) {
        if (plan.tun && proxyEverVerified) {
          allowProxyFallbackNow = true;
        }
        final String coreLog = _coreLogPath(plan);
        final String tail = await _readLogTail(coreLog);
        _log.add(
          _singleNodeSession
              ? 'مسیر انتخاب شده «${node.protocol.label}» در مهلت سنجش پاسخ نداد. '
                  'این خطا به تنهایی علت مشکل یا وضعیت سایر مسیرها را مشخص نمی کند.'
                  '${tail.isEmpty ? '' : ' خروجی هسته: $tail'}'
              : poolExhausted
                  ? 'هسته برای مسیرهای حالت خودکار پاسخی دریافت نکرد.'
                      '${tail.isEmpty ? '' : ' خروجی هسته: $tail'}'
                  : 'هسته بالا آمد ولی در مهلت تعیین شده پاسخی دریافت نشد.'
                      '${tail.isEmpty ? '' : ' خروجی هسته: $tail'}',
          level: 'error',
          details: await _coreDiagnostics(
            plan.cores.first,
            coreLog,
            plan: plan,
          ),
        );
        await _stopCores();
        await _disableProxy();
        if (poolExhausted && !_singleNodeSession) {
          return const _AttemptResult(
            message: 'هیچ سرور در دسترسی پاسخ نداد.',
          );
        }
        continue;
      }

      if (plan.usesSystemProxy) {
        final bool proxyOk = await _enableProxy(plan);
        if (!proxyOk) {
          // بدون پروکسی سیستمی، هسته کار می کند ولی هیچ برنامه ای از آن
          // استفاده نمی کند؛ پس این اتصال «وصل» حساب نمی شود.
          _log.add(
            'پروکسی سیستمی ویندوز تنظیم نشد؛ این اتصال معتبر نیست و سرور '
            'بعدی امتحان می شود.',
            level: 'error',
            details: <LogDetail>[
              LogDetail(
                title: 'تنظیم پروکسی ویندوز',
                text: <String>[
                  'نشانی پروکسی: ${Fa.num('127.0.0.1')}:${Fa.num(plan.proxyPort)}',
                  'پورت محلی هسته: ${Fa.num(plan.proxyPort)}',
                  if (plan.proxyPort > 0)
                    'پورت باز است: '
                        '${await UmbrellaCore.inUse(plan.proxyPort) ? 'بله' : 'نه'}',
                  '',
                  'اگر پورت باز نیست، هسته بالا نیامده است؛ اگر باز است ولی '
                      'پروکسی تنظیم نشد، دسترسی به تنظیمات ویندوز (رجیستری) '
                      'بسته است و برنامه باید با دسترسی مدیر اجرا شود.',
                ].join('\n'),
              ),
            ],
          );
          await _stopCores();
          await _disableProxy();
          continue;
        }
      } else if (!plan.tun) {
        // حالت «فقط سرویس پروکسی»: پورت محلی باز است و پروکسی ویندوز دست نخورده می ماند.
        await _disableProxy();
      }
      if (_cancelRequested || _disposed) {
        await _stopCores();
        await _disableProxy();
        return const _AttemptResult(cancelled: true, message: 'اتصال لغو شد.');
      }
      _connectedAt = DateTime.now();
      _sessionStartUtc = sessionStart;
      _activeCoreLogPath = _coreLogPath(plan);
      _tunnelVerified = true;
      _healthFailures = 0;
      // شمارنده `_reconnectAttempts` اینجا صفر نمی شود؛ فقط در اتصال دستی یا پس
      // از تایید کامل سلامت مسیر صفر می شود تا بازاتصال خودکار هرگز به حلقه
      // بی پایان قطع و وصل تبدیل نشود.
      if (initialDelayMs > 0) {
        _livePing = initialDelayMs;
      }
      if (initialIpInfo != null && initialIpInfo!.ip.isNotEmpty) {
        _geo = GeoInfo.fromJson(initialIpInfo!.toGeoJson());
        _exitIp = initialIpInfo!.ip;
      }
      _setStatus(VpnStatus.connected, 'اتصال برقرار شد.');
      _ensureNetworkWatcherStarted();
      onTunnelConnected?.call();
      _balancer.markConnected(node.id);
      _startTimers(initialPingMs: initialDelayMs);
      unawaited(_sound.play('connect'));
      // نام سرور در سینی ویندوز و اعلان نمی آید.
      unawaited(
        _tray.update(
          state: 'connected',
          tooltip: '${AppConfig.appName} - متصل شد',
          connected: true,
        ),
      );
      if (initialIpInfo != null && initialIpInfo!.ip.isNotEmpty) {
        _log.add(
          'آی پی خروجی: ${_geo.ip}'
          '${_geo.flagEmojiFreeLabel.isEmpty ? '' : ' | ${_geo.flagEmojiFreeLabel}'}',
        );
      }
      if (_settings.notificationsEnabled) {
        final int shownPing = activePingMs;
        unawaited(
          _tray.balloon(
            'به آمبرلا متصل شد',
            shownPing > 0 ? 'پینگ ${Fa.ms(shownPing)}' : 'اتصال امن برقرار است',
          ),
        );
      }

      // خواندن غیرمسدودکننده آی پی و موقعیت خروجی در پس زمینه (ابتدا از ipinfo
      // داخلی خود هسته و در صورت نیاز از وب) بدون یک میلی ثانیه تاخیر در اتصال.
      final int connectedEpoch = _connectionEpoch;
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 900), () async {
          if (!_disposed &&
              connectedEpoch == _connectionEpoch &&
              _status == VpnStatus.connected) {
            await _verifyTunnel();
          }
        }),
      );
      // در حالت چندسروره، گروه انتخابی کاربر (`lowest` یا `balance`) صریحاً روی
      // `select` ست می شود تا مقدار کش شده قدیمی در `data/clash.db` آن را خنثی نکند.
      if (!_singleNodeSession) {
        unawaited(ClashApi.selectOutbound('select', _desiredSelectGroup));
      }
      if (_contentFilter.hasActiveRules) {
        unawaited(_native.flushDns());
      }
      _preferredCore[node.id] = plan.cores.first.name;
      final String modeLabel = plan.tun
          ? 'تونل کامل'
          : (plan.usesSystemProxy ? 'پروکسی سیستمی' : 'فقط سرویس پروکسی');
      _log.add('اتصال امن آمبرلا با موفقیت برقرار شد ($modeLabel).');
      _settings = _settings.copyWith(lastNodeId: node.id);
      onSettingsChanged?.call(_settings);
      return const _AttemptResult(message: 'اتصال برقرار شد.', ok: true);
    }

    _preferredCore.remove(node.id);
    final String failure = _singleNodeSession
        ? 'اتصال «${node.protocol.label}» تأیید نشد؛ گزارش ها را ببینید.'
        : 'اتصال خودکار تأیید نشد؛ گزارش ها را ببینید.';
    _setStatus(VpnStatus.failed, failure);
    return _AttemptResult(message: failure);
  }

  Future<void> _terminateForeignCores() async {
    if (!_native.available) {
      return;
    }
    int nativeClosed = 0;
    try {
      nativeClosed = await _native.closeConflictingVpns(
        excludeDirs: <String>[
          if (_provisioner.dataDir.isNotEmpty) _provisioner.dataDir,
        ],
        excludePids: List<int>.of(_runningPids),
      );
    } catch (_) {}
    if (nativeClosed > 0) {
      _log.add(
        'فیلترشکن ها یا اتصالات وی پی ان باز قبلی بسته شدند (${Fa.num(nativeClosed)} مورد).',
        level: 'warning',
      );
    }
    final List<Object> results = await Future.wait<Object>(<Future<Object>>[
      _native.runningCores(),
      _native.systemProxyEnabled(),
    ]);
    final List<String> running = results[0] as List<String>;
    final bool proxy = results[1] as bool;
    final List<String> targets = running
        .where((String core) => !_runningBinaries.contains(core))
        .toList(growable: false);
    final List<Future<void>> tasks = <Future<void>>[
      for (final String core in targets)
        _native.killByName(core).then((int killed) {
          if (killed > 0) {
            _log.add('فیلترشکن یا هسته فعال دیگر بسته شد: $core', level: 'warning');
          }
        }),
      if (proxy)
        _native.disableSystemProxy().then((_) {
          _log.add('پروکسی سیستمی ویندوز غیرفعال شد.', level: 'warning');
        }),
    ];
    if (tasks.isNotEmpty) {
      await Future.wait(tasks);
    }
  }

  /// پروتکل هایی که هسته پشتیبانی می کند.
  ///
  /// وی لس، وی مس، تروجان، شادوساکس، ساکس، هایستریا ۲، تی یو آی سی، وایرگارد،
  /// آمنزیا و میرو؛ پس هیچ سروری به خاطر «هسته سازگار نیست» کنار گذاشته
  /// نمی شود.
  static bool supports(VpnNode node) {
    switch (node.protocol) {
      case NodeProtocol.vless:
      case NodeProtocol.vmess:
      case NodeProtocol.trojan:
      case NodeProtocol.shadowsocks:
      case NodeProtocol.ssh:
      case NodeProtocol.naive:
      case NodeProtocol.anytls:
      case NodeProtocol.socks:
      case NodeProtocol.mieru:
      case NodeProtocol.hysteria2:
      case NodeProtocol.tuic:
      case NodeProtocol.wireguard:
      case NodeProtocol.amnezia:
        return true;
      case NodeProtocol.clash:
        return false;
    }
  }

  /// آیا این سرور با این هسته قابل استفاده است؟
  ///
  /// سروری که شناسه یا رمزش خالی است هرگز نباید اجرا شود؛ هسته با
  /// «invalid UUID» بسته می شود. همه چیزهایی که برای یک اتصال سالم لازم است
  /// همین جا بررسی می شود تا انتخاب گر روی سروری که کار نمی کند وقت تلف نکند.
  static bool usable(VpnNode node) {
    if (!supports(node)) {
      return false;
    }
    if (node.host.isEmpty || node.port <= 0) {
      return false;
    }
    final Map<String, dynamic> params = node.params;
    // گرهی که در نقشه کلش `type: vless` دارد داده اش غلط نیست، فقط نام
    // پروتکل در جای نوع انتقال نشسته؛ لینک ساز آن را به `tcp` عادی می کند
    // (`_transportOf`).
    //
    // Match the pinned core's transport capabilities; XHTTP is implemented in
    // hiddify-core 5.9.1 and its pinned ray2sing converter.
    if (!transportSupported(node)) {
      return false;
    }
    switch (node.protocol) {
      case NodeProtocol.vless:
      case NodeProtocol.vmess:
        return JsonX.text(params['id'] ?? params['uuid']).isNotEmpty;
      case NodeProtocol.tuic:
        return JsonX.text(params['id'] ?? params['uuid']).isNotEmpty &&
            JsonX.text(params['password']).isNotEmpty;
      case NodeProtocol.trojan:
      case NodeProtocol.hysteria2:
      case NodeProtocol.anytls:
        return JsonX.text(params['password']).isNotEmpty;
      case NodeProtocol.shadowsocks:
        return JsonX.text(params['password']).isNotEmpty &&
            JsonX.text(params['method'] ?? params['cipher']).isNotEmpty;
      case NodeProtocol.ssh:
        return JsonX.text(params['username']).isNotEmpty &&
            (JsonX.text(params['password']).isNotEmpty ||
                JsonX.text(
                  params['privateKey'] ?? params['pk'] ?? params['private_key'],
                ).isNotEmpty);
      case NodeProtocol.naive:
        return JsonX.text(params['username']).isNotEmpty ||
            JsonX.text(params['password']).isNotEmpty;
      case NodeProtocol.mieru:
        return JsonX.text(params['username']).isNotEmpty &&
            JsonX.text(params['password']).isNotEmpty;
      case NodeProtocol.socks:
        return true;
      case NodeProtocol.wireguard:
        return JsonX.text(params['privateKey']).isNotEmpty &&
            JsonX.text(params['publicKey']).isNotEmpty;
      case NodeProtocol.amnezia:
        return JsonX.text(params['privateKey']).isNotEmpty &&
            JsonX.text(params['publicKey']).isNotEmpty;
      case NodeProtocol.clash:
        return false;
    }
  }

  /// پوشه هسته: همه فایل های هسته کنار هم می مانند، پس پوشه کار هسته
  /// همان پوشه خود فایل اجرایی است.
  String _umbrellaDir(String exe) => _dirOf(exe);

  /// دی ان اس سنجش پینگ: سریع و بی وابستگی به شبکه کاربر.
  ///
  /// در سنجش پینگ، هسته فقط پیکربندی را می سازد و یک پروکسی محلی باز می کند؛
  /// اگر دی ان اس داخل تونل، سرور را از طریق خودش ترجمه کند، آماده شدن پورت
  /// طول می کشد و سنجش (که فقط چند ثانیه صبر می کند) بی نتیجه می ماند —
  /// همان «تاخیر تونل برای ۰ سرور» در گزارش کاربر.
  static const String pingDns = UmbrellaCore.defaultRemoteDns;

  /// نقشه اجرا برای یک سرور.
  ///
  /// تنها هسته ای که وجود دارد موتور هسته است.
  /// یک نقشه برگردانده می شود و اگر راه اول جواب نداد، همان هسته با حالت
  /// دیگر امتحان می شود (تونل کامل و پروکسی سیستمی). این کار عیناً همان چیزی
  /// است که لانچر رسمی هسته هم همان را می کند.
  ///
  /// ورودی هسته، خود لینک سرور است (`-c links.txt`)؛ هسته خودش پیکربندی
  /// کامل، دی ان اس و مسیرها را می سازد.
  Future<List<LaunchPlan>> _buildPlans(VpnNode node) async {
    if (!usable(node)) {
      return <LaunchPlan>[];
    }
    final String binary = CliSession.wanted(_settings)
        ? umbrellaCliBinary : UmbrellaCore.engineBinary;
    final String? exe = await _provisioner.locateBinary(binary);
    if (exe == null || exe.isEmpty) {
      _lastPlanNeedsCore = true;
      _log.add(
        'هسته آمبرلا ($binary) در نسخه نصب نیست؛ برنامه را با نصب کننده '
        'رسمی دوباره نصب کنید.',
        level: 'error',
        details: <LogDetail>[
          LogDetail(
            title: 'کجای نصب را بگردید',
            text: <String>[
              'فایل اجرایی: $binary',
              'پوشه برنامه: ${_provisioner.appDir}',
              'پوشه هسته ها: ${_provisioner.bundledDir}',
              'پوشه داده: ${_provisioner.dataDir}',
              '',
              'این مسیرها بررسی شد و فایل در هیچ کدام نبود:',
              for (final String path in _binaryCandidates(binary))
                '  • $path ${await File(path).exists() ? '(هست)' : '(نیست)'}',
            ].join('\n'),
          ),
        ],
      );
      return <LaunchPlan>[];
    }
    final Directory runDir = Directory(
      '${_provisioner.dataDir}${Platform.pathSeparator}run',
    );
    await runDir.create(recursive: true);
    final String link = _umbrellaLink(node);
    if (link.isEmpty) {
      _log.add(
        '${_nodeLabel(node)} لینک قابل اجرا ندارد؛ هسته آمبرلا برای این '
        'سرور ورودی نمی شناسد.',
        level: 'info',
      );
      return <LaunchPlan>[];
    }
    final File links = File(
      '${runDir.path}${Platform.pathSeparator}umbrella-core-link.txt',
    );
    // همه سرورهای سازگار نوشته می شوند، نه فقط همین یکی.
    //
    // **شکایت درست کاربر:** تا ۱٫۰٫۱۵ فایل لینک فقط یک خط داشت، پس هسته
    // گروه انتخاب و بالانسر خودش را روی «یک» گره می ساخت و هیچ وقت نمی
    // توانست سوییچ کند. کاربر ۴۶۰ سرور در فهرست داشت و دائم به همان یک
    // سرور وصل می شد.
    //
    // خود هسته کاری که باید بکند را بلد است: از چند گره، گروه `select` و
    // بالانسر `lowest-delay` می سازد، همه را می سنجد و سریع ترین را نگه
    // می دارد (`keep-top`). برای همین کافی است همه لینک ها را بدهیم.
    final List<String> pool = _linkPool(node);
    await links.writeAsString('${pool.join('\n')}\n', flush: true);
    if (pool.length > 1) {
      _log.add(
        'فایل لینک هسته ${Fa.num(pool.length)} سرور از اشتراک را دارد؛ خود '
        'هسته همه را می سنجد، سریع ترین را انتخاب می کند و اگر افت کرد '
        'به بعدی سوییچ می کند.',
      );
    }

    // همان حالتی که کاربر خواسته: تونل کامل اگر روشن باشد و دسترسی مدیر هم
    // داشته باشیم، وگرنه پروکسی سیستمی. در حالت «خودکار» اگر آداپتور یا مسیر
    // تونل توسط ویندوز/فایروال بسته شود ولی خود پروکسی هسته کار کند، پروکسی
    // سیستمی به عنوان پشتیبان آماده است.
    final InboundServiceMode requestedMode = _settings.serviceMode;
    final int activeMixedPort = LanSharing.isValidPort(_settings.mixedPort)
        ? _settings.mixedPort
        : _umbrellaPort;
    bool tun = requestedMode == InboundServiceMode.vpn &&
        _settings.corePreference != CorePreference.systemProxy &&
        _settings.tunMode;
    bool sysProxy = requestedMode == InboundServiceMode.systemProxy;
    if (tun && !_device.elevated) {
      _log.add(
        'حالت تونل به دسترسی مدیر نیاز دارد؛ این بار با پروکسی سیستمی وصل '
        'می شویم. برای تونل، برنامه را با دسترسی مدیر اجرا کنید.',
        level: 'warning',
      );
      tun = false;
      sysProxy = true;
    }
    final bool hasActiveAppRoutes =
        _settings.appRoutes.any((AppRouteRule rule) => rule.enabled);
    final bool allowProxyFallback = tun &&
        _settings.corePreference == CorePreference.auto &&
        !hasActiveAppRoutes &&
        !_settings.killSwitch;
    LaunchPlan makePlan({
      required bool useTun,
      required bool useSystemProxy,
      String warning = '',
    }) {
      return LaunchPlan(
        cores: <CoreLaunch>[
          CoreLaunch(
            exe: exe,
            args: _umbrellaArgs(
              exe: exe,
              links: links.path,
              runDir: runDir.path,
              tun: useTun,
            ),
            workDir: _umbrellaDir(exe),
            name: useTun ? 'umbrella-tun' : 'umbrella',
          ),
        ],
        linksPath: links.path,
        readinessPort: useTun ? 0 : activeMixedPort,
        primaryBinary: binary,
        tunnelHint: useTun ? AppConfig.tunAdapterHint : '',
        chained: false,
        proxyPort: useTun ? 0 : activeMixedPort,
        runDir: runDir.path,
        tun: useTun,
        systemProxy: useSystemProxy,
        warning: warning,
      );
    }

    return <LaunchPlan>[
      makePlan(useTun: tun, useSystemProxy: sysProxy),
      if (allowProxyFallback)
        makePlan(
          useTun: false,
          useSystemProxy: true,
          warning:
              'مسیر کارت شبکه تونل روی این سیستم پاسخ نداد؛ اتصال با پروکسی '
              'سیستمی برقرار می شود.',
        ),
    ];
  }

  /// شناسه هسته در فهرست همراه نسخه.
  static const String umbrellaCoreId = UmbrellaCore.id;

  /// نام فایل خط فرمان هسته (همان HiddifyCli با نام آمبرلا).
  static const String umbrellaCliBinary = UmbrellaCore.cliBinary;

  /// چند فرایند بازمانده از اجرای قبلی در این اجرا بسته شد.
  int _orphansKilled = 0;

  /// نتیجه آخرین اجرای هسته: آیا اصلاً نتوانست سرور را بسازد؟
  bool _lastLaunchUnusable = false;

  /// پورت محلی هسته. خود هسته ۱۲۳۳۴ را پیش فرض دارد و همین عدد در برنامه هم
  /// ثابت است تا پروکسی سیستمی همیشه همان جا وصل شود.
  static const int _umbrellaPort = AppConfig.httpPortUmbrella;

  /// آرگومان های هسته.
  ///
  /// `run -c <links>` همان دستوری است که مستندات هسته برای «فقط لینک ها دارم»
  /// می دهد: هسته خودش پیکربندی، دی ان اس و مسیرها را می سازد.
  List<String> _umbrellaArgs({
    required String exe,
    required String links,
    required String runDir,
    required bool tun,
  }) {
    return UmbrellaCore.args(
      links: links,
      runDir: runDir,
      port: _configuredMixedPort,
      tun: tun,
      systemProxy: !tun,
      logLevel: CoreLogLevel.normalize(_settings.logLevel),
    );
  }

  /// لینک سرور برای دادن به هسته (برای سنجش پینگ و پنجره CLI هم استفاده
  /// می شود).
  static String linkFor(VpnNode node, {bool batterySaving = false}) {
    if (DirectProfile.handles(node)) {
      return DirectProfile.encode(node, batterySaving: batterySaving);
    }
    final String raw = node.raw.trim();
    if (raw.contains('://')) {
      final String normalized =
          node.protocol == NodeProtocol.vless ||
                  node.protocol == NodeProtocol.trojan
              ? _normalizeLegacyTransportLink(raw)
              : raw;
      return LinkPreparation.normalizeLink(normalized);
    }
    return _linkFromNode(node);
  }

  /// `h2` در فرمت های قدیمی لینک، معادل انتقال HTTP/2 است؛ ولی نسخه هسته
  /// همراه آمبرلا نوع انتقالی به نام `h2` نمی شناسد و با
  /// `unknown transport type: h2` خارج می شود. در فرمت لینک sing-box این
  /// انتقال با نام `http` شناخته می شود. فقط پارامتر نوع انتقال نرمال می شود؛
  /// سایر پارامترهای لینک خام دست نخورده می مانند.
  static String _normalizeLegacyTransportLink(String link) {
    return link.replaceAllMapped(
      RegExp(r'([?&]type=)h2(?=(&|#|$))', caseSensitive: false),
      (Match match) => '${match.group(1)}http',
    );
  }

  /// لینک سرور برای دادن به هسته.
  ///
  /// لینک اصلی همان چیزی است که در اشتراک بود؛ اگر نبود، از فیلدهای سرور
  /// ساخته می شود. هسته خودش جزئیات پروتکل را می فهمد.
  String _umbrellaLink(VpnNode node) =>
      linkFor(node, batterySaving: _batterySaving);

  /// چند لینک برای دادن به هسته، به ترتیب اولویت.
  ///
  /// سرور انتخاب شده همیشه اول است، پس اگر خود هسته هم چیزی انتخاب نکند،
  /// همان گره ای می شود که کاربر خواسته. بعد از آن، همه سرورهای دیگری که
  /// با این هسته کار می کنند می آیند تا خود هسته بتواند بینشان سنجش کند،
  /// سریع ترین را نگه دارد و هنگام افتادن یکی، به بعدی سوییچ کند — همان
  /// کاری که کاربر از یک فیلترشکن انتظار دارد.
  ///
  /// همه لینک های یکتای مجاز حفظ می شوند؛ keep-top مصرف هم زمان را محدود می کند.
  List<String> _linkPool(VpnNode chosen) {
    final List<String> pool = <String>[];
    final Set<String> seen = <String>{};

    void add(VpnNode n) {
      if (!usable(n)) {
        return;
      }
      final String link = linkFor(n, batterySaving: _batterySaving).trim();
      if (link.isEmpty) {
        return;
      }
      // یک لینک دو بار نوشته نمی شود؛ هسته با نام تکراری گیج می شود.
      //
      // کلید، خود لینک است اما بدون بخش نام (`#...`). پیش از این اصلاح کلید
      // `میزبان:پورت|پروتکل|انتقال|امنیت` بود؛ یعنی چند کلاینت مختلف روی
      // یک سرور (رایج ترین حالت: یک سرور با چند شناسه کاربر) به یکی
      // کاهش می یافتند و فقط یکی از آن ها به هسته می رسید. حالا هر لینک
      // یکتا یک کلاینت است و همه شان امتحان می شوند.
      final String key = LinkPreparation.canonicalTarget(link);
      if (!seen.add(key)) {
        return;
      }
      pool.add(link);
    }

    // An explicit selection (or disabled failover) must not launch a monitor
    // over the entire subscription or silently select a different server.
    if (_singleNodeSession || DirectProfile.handles(chosen)) {
      add(chosen);
      return pool.isEmpty
          ? <String>[linkFor(chosen, batterySaving: _batterySaving).trim()]
          : pool;
    }
    // سرور انتخاب شده همیشه اولین لینک قرار می گیرد؛ بعد گره های پین شده
    // و بقیه گره های اشتراک بر اساس سلامت و کمترین تاخیر رتبه بندی می شوند
    // تا sing-box سریع ترین سرورها را در همان دسته اول بیازماید و گره های
    // اخیراً ناموفق یا تست نشده عقب بیفتند.
    add(chosen);
    final List<VpnNode> candidates =
        (chosen.sourceId.startsWith('emergency-') ? _emergencyNodes : _nodes)
            .where((VpnNode n) => !n.disabled && !DirectProfile.handles(n))
            .toList();
    final Map<String, int> originalOrder = <String, int>{
      for (int i = 0; i < candidates.length; i++) candidates[i].id: i,
    };
    int rankPoolNode(VpnNode a, VpnNode b) {
      final bool aFailed = _balancer.recentlyFailed(a);
      final bool bFailed = _balancer.recentlyFailed(b);
      if (aFailed != bFailed) {
        return aFailed ? 1 : -1;
      }
      if (a.hasPing != b.hasPing) {
        return a.hasPing ? -1 : 1;
      }
      if (a.hasPing && b.hasPing) {
        final int cmp = _balancer.score(a).compareTo(_balancer.score(b));
        if (cmp != 0) return cmp;
      }
      return (originalOrder[a.id] ?? 0).compareTo(originalOrder[b.id] ?? 0);
    }
    final List<VpnNode> pinned = candidates
        .where((VpnNode n) => n.favorite)
        .toList()
      ..sort(rankPoolNode);
    final List<VpnNode> ordinary = candidates
        .where((VpnNode n) => !n.favorite)
        .toList()
      ..sort(rankPoolNode);
    for (final VpnNode n in pinned) {
      add(n);
    }
    for (final VpnNode n in ordinary) {
      add(n);
    }
    // اگر هیچ کدام سازگار نبود، لااقل همان یکی.
    return pool.isEmpty
        ? <String>[linkFor(chosen, batterySaving: _batterySaving).trim()]
        : pool;
  }

  VpnNode? _pickPrewarmPoolNode() {
    final String deviceSeed = _device.machineId.isNotEmpty
        ? _device.machineId
        : _device.hostname;
    final List<VpnNode> stages = buildAutoCandidates(
      personalNodes: _nodes,
      emergencyNodes: const <VpnNode>[],
      balancer: _balancer,
      mode: _settings.selectionMode,
      deviceSeed: deviceSeed,
      preferredNodeId: _settings.lastNodeId,
      stickyMinutes: _settings.stickyMinutes,
      allowFailover: _settings.autoFailover,
      emergencyOnly: false,
      accepts: (VpnNode n) =>
          usable(n) && !n.disabled && !DirectProfile.handles(n) && _fitsPreference(n),
    );
    return stages.isEmpty ? null : stages.first;
  }

  /// پیش آماده سازی بی صدا و پس زمینه `parsed.json` و `runtime.json` پس از
  /// دریافت اشتراک یا تغییر تنظیمات تا کلیک روی «اتصال» در کسری از ثانیه مستقیم
  /// وارد `srun` شود (دقیقاً مشابه پروفایل از پیش پارس شده Hiddify).
  void _scheduleRuntimePrewarm() {
    if (!Platform.isWindows || _disposed) {
      return;
    }
    _prewarmTimer?.cancel();
    if (_status.active ||
        _status.busy ||
        _connectInFlight ||
        _nodes.isEmpty ||
        _settings.selectionMode == SelectionMode.manual ||
        !_settings.autoFailover) {
      return;
    }
    _prewarmTimer = Timer(const Duration(milliseconds: 350), () {
      _prewarmTimer = null;
      if (_disposed ||
          _status.active ||
          _status.busy ||
          _connectInFlight ||
          _measuring ||
          _corePing.busy) {
        return;
      }
      final Future<void> job = _runRuntimePrewarm();
      _prewarmInFlight = job;
      unawaited(
        job.whenComplete(() {
          if (identical(_prewarmInFlight, job)) {
            _prewarmInFlight = null;
          }
        }),
      );
    });
  }

  Future<void> _cancelRuntimePrewarm() async {
    _prewarmTimer?.cancel();
    _prewarmTimer = null;
    for (final Process process in List<Process>.of(_prewarmProcesses)) {
      try {
        process.kill();
      } catch (_) {}
    }
    final Future<void>? running = _prewarmInFlight;
    if (running == null) {
      return;
    }
    _prewarmCancelled = true;
    try {
      await running.timeout(
        const Duration(milliseconds: 250),
        onTimeout: () {},
      );
    } catch (_) {
      // Prewarm is strictly best-effort; connect always validates/builds.
    } finally {
      _prewarmCancelled = false;
      if (identical(_prewarmInFlight, running)) {
        _prewarmInFlight = null;
      }
    }
  }

  Future<void> _runRuntimePrewarm() async {
    _prewarmCancelled = false;
    bool shouldAbort() =>
        _prewarmCancelled ||
        _disposed ||
        _cancelRequested ||
        _status.active ||
        _status.busy ||
        _connectInFlight;
    try {
      if (shouldAbort()) return;
      final VpnNode? picked = _pickPrewarmPoolNode();
      if (picked == null) return;
      final String binary = CliSession.wanted(_settings)
          ? umbrellaCliBinary
          : UmbrellaCore.engineBinary;
      final String? exe = await _provisioner.locateBinary(binary);
      if (exe == null || exe.isEmpty || shouldAbort()) return;
      final String workDir = _umbrellaDir(exe);
      final Directory runDir = Directory(
        '${_provisioner.dataDir}${Platform.pathSeparator}run',
      );
      await runDir.create(recursive: true);

      final bool savedSingle = _singleNodeSession;
      _singleNodeSession = false;
      final List<String> pool;
      try {
        pool = _linkPool(picked);
      } finally {
        _singleNodeSession = savedSingle;
      }
      if (pool.isEmpty || shouldAbort()) return;

      final PreparedLinks prepared = await LinkPreparation.prepare(
        pool,
        resolveEndpoints: false,
      );
      if (prepared.links.isEmpty || shouldAbort()) return;

      final bool tun = _settings.serviceMode == InboundServiceMode.vpn &&
          _settings.corePreference != CorePreference.systemProxy &&
          _settings.tunMode &&
          _device.elevated;
      final bool sysProxy = !tun &&
          _settings.serviceMode != InboundServiceMode.proxy;
      final int activeMixedPort = LanSharing.isValidPort(_settings.mixedPort)
          ? _settings.mixedPort
          : _umbrellaPort;
      final String logPath =
          '${runDir.path}${Platform.pathSeparator}umbrella-core.log';
      final File prewarmLinks = File(
        '${runDir.path}${Platform.pathSeparator}prewarm-links.txt',
      );
      final File prewarmSettings = File(
        '${runDir.path}${Platform.pathSeparator}prewarm-settings.json',
      );
      await prewarmLinks.writeAsString(
        '${prepared.links.join('\n')}\n',
        flush: true,
      );
      await prewarmSettings.writeAsString(
        jsonEncode(
          UmbrellaCore.settingsJson(
            tun: tun,
            systemProxy: sysProxy,
            port: activeMixedPort,
            logFile: logPath,
            networkSettings: _settings,
            contentFilter: _contentFilter,
            batterySaving: _batterySaving,
          ),
        ),
        flush: true,
      );
      if (shouldAbort()) return;
      final ContentBlockServer? blockServer = await ensureBlockServerStarted();
      if (shouldAbort()) return;
      await _provisioner.ensureDataRuleSets(
        extraDataDir: '${runDir.path}${Platform.pathSeparator}data',
      );
      await CoreRuntime.compile(
        executable: exe,
        workDir: workDir,
        runDir: runDir.path,
        linksPath: prewarmLinks.path,
        settingsPath: prewarmSettings.path,
        stickyMinutes: _settings.stickyMinutes,
        blockPagePort: (blockServer != null && blockServer.proxyPort > 0)
            ? blockServer.proxyPort
            : null,
        localRuleSetPaths: _provisioner.localRuleSetPaths,
        cancelled: shouldAbort,
        onStarted: _prewarmProcesses.add,
        onFinished: _prewarmProcesses.remove,
      );
    } catch (_) {
      // Silent best-effort prewarm; foreground connect logs any real error.
    }
  }

  /// آیا نوع انتقال این گره برای هسته شناخته شده است؟
  ///
  /// فقط `network` ملاک است؛ اگر خالی باشد یعنی پیش فرض (`tcp`) و مشکلی
  /// نیست. مقدار ناشناخته (مثل نام پروتکل) یعنی گره با این هسته بالا نمی آید.
  static bool _transportKnown(Map<String, dynamic> params) {
    final String raw = JsonX.text(params['network']).trim().toLowerCase();
    if (raw.isEmpty) {
      return true;
    }
    return _coreTransports.contains(raw) || raw == 'mkcp';
  }

  /// لینک وی لس از فیلدهای گره.
  ///
  /// پارامترهای مخصوص هر نوع انتقال فقط وقتی نوشته می شوند که به آن نوع
  /// مربوط باشند؛ فرستادن `path` برای `tcp` یا `security` خالی، هسته را
  /// گیج می کرد.
  static String _vlessLink(VpnNode node, String transport) {
    final Map<String, dynamic> params = node.params;
    final String host = node.host.isEmpty ? '127.0.0.1' : node.host;
    final String sni = JsonX.text(params['sni'], host);
    final String security = JsonX.text(params['security'], 'none');
    final bool streamed = transport == 'ws' ||
        transport == 'http' ||
        transport == 'h2' ||
        transport == 'httpupgrade' ||
        transport == 'xhttp' ||
        transport == 'splithttp';
    final List<String> query = <String>[
      'encryption=${Uri.encodeComponent(JsonX.text(params['encryption'], 'none'))}',
      'security=$security',
      'type=$transport',
      'sni=${Uri.encodeComponent(sni)}',
    ];
    if (streamed) {
      final String path = JsonX.text(params['path'], '/');
      query.add('path=${Uri.encodeComponent(path)}');
      final String streamHost = JsonX.text(params['host'], sni);
      if (streamHost.isNotEmpty) {
        query.add('host=${Uri.encodeComponent(streamHost)}');
      }
    }
    if (transport == 'xhttp' || transport == 'splithttp') {
      for (final String key in <String>['mode', 'extra']) {
        final dynamic value = params[key];
        final String text = value is Map || value is List ? jsonEncode(value) : JsonX.text(value);
        if (text.isNotEmpty) query.add('$key=${Uri.encodeComponent(text)}');
      }
    }
    if (transport == 'grpc') {
      final String service =
          JsonX.text(params['serviceName'] ?? params['service_name']);
      if (service.isNotEmpty) {
        query.add('serviceName=${Uri.encodeComponent(service)}');
      }
    }
    // ریلیتی: بدون این پارامترها دست دادن TLS انجام نمی شود. `fp` پایین تر
    // با توضیح خودش اضافه می شود.
    for (final String key in <String>['pbk', 'sid', 'spx']) {
      final String value = JsonX.text(params[key]);
      if (value.isNotEmpty) {
        query.add('$key=${Uri.encodeComponent(value)}');
      }
    }
    final String flow = JsonX.text(params['flow']);
    if (flow.isNotEmpty) {
      query.add('flow=${Uri.encodeComponent(flow)}');
    }
    // `h2` و `http/1.1` یکی نیستند؛ اگر سرور فقط یکی را بپذیرد، فرستادن هردو
    // یا هیچ کدام، دست دادن را خراب می کند.
    final String alpn = JsonX.text(params['alpn']);
    if (alpn.isNotEmpty) {
      query.add('alpn=${Uri.encodeComponent(alpn)}');
    }
    // ریلیتی بدون اثر انگشت مرورگر (uTLS) دست نمی دهد: سرور انتظار دست دادن
    // کروم را دارد و دست دادن پیش فرض Go را رد می کند.
    final String fp = JsonX.text(params['fp']);
    if (fp.isNotEmpty) {
      query.add('fp=${Uri.encodeComponent(fp)}');
    }
    if (JsonX.boolean(params['allowInsecure'])) {
      query.add('allowInsecure=1');
    }
    final String id = JsonX.text(params['id'] ?? params['uuid']);
    final String name = Uri.encodeComponent(node.name);
    return 'vless://$id@$host:${node.port}?${query.join('&')}#$name';
  }

  /// Supported by hiddify-core 5.9.1 / ray2sing 6974ad6. Unknown transports
  /// still fail closed; known XHTTP must not be rewritten as TCP or filtered out.
  static const List<String> _coreTransports = <String>[
    'tcp',
    'ws',
    'grpc',
    'http',
    'h2',
    'quic',
    'httpupgrade',
    'xhttp',
    'splithttp',
    'mkcp',
    'kcp',
  ];

  /// آیا این گره با نوع انتقالش برای هسته آمبرلا قابل اجراست؟
  static bool transportSupported(VpnNode node) {
    // فقط پروتکل های خانواده V2Ray از پارامتر انتقال (`tcp`/`ws`/`grpc`/`xhttp`)
    // استفاده می کنند؛ پروتکل های مستقل مثل `naive` (با `type=custom`)، `ssh`،
    // `anytls`، `ss`، `tuic` و `hysteria2` انتقال داخلی خودشان را دارند.
    if (node.protocol != NodeProtocol.vless &&
        node.protocol != NodeProtocol.vmess &&
        node.protocol != NodeProtocol.trojan) {
      return true;
    }
    final String network = _networkOf(node);
    if (network.isEmpty) {
      return true;
    }
    return _coreTransports.contains(network);
  }

  /// نوع انتقال گره، از پارامترها یا از خود لینک.
  ///
  /// Raw subscription links can specify the transport without a parsed
  /// network field. Inspect both so unknown values are still rejected.
  static String _networkOf(VpnNode node) {
    final String fromParams =
        JsonX.text(node.params['network']).trim().toLowerCase();
    if (fromParams.isNotEmpty) {
      return fromParams;
    }
    final String raw = node.raw.trim();
    if (!raw.contains('://')) {
      return '';
    }
    try {
      final Uri? uri = Uri.tryParse(raw);
      final String type =
          (uri?.queryParameters['type'] ?? '').trim().toLowerCase();
      return type;
    } on FormatException {
      return '';
    }
  }

  /// نوع انتقال لینک (`tcp`، `ws`، `grpc`، `http`، `h2`).
  ///
  /// فقط از `network` خوانده می شود؛ `type` در نقشه کلش نام پروتکل است و
  /// فرستادنش به عنوان نوع انتقال، هسته را با «unknown transport type» می
  /// کشت. اگر مقدار ناشناخته بود، `tcp` می شود.
  static String _transportOf(Map<String, dynamic> params) {
    final String raw =
        JsonX.text(params['network']).trim().toLowerCase();
    if (raw.isNotEmpty && _transportKnown(params)) {
      // `h2` نام قدیمی همان انتقالی است که هسته با نام `http` می شناسد.
      return raw == 'h2' ? 'http' : raw;
    }
    // بعضی منابع `network` را با نام دیگر می دهند.
    if (JsonX.boolean(params['grpc'])) {
      return 'grpc';
    }
    if (JsonX.boolean(params['ws']) || JsonX.text(params['ws-opts']).isNotEmpty) {
      return 'ws';
    }
    return 'tcp';
  }

  /// ساختن لینک از فیلدهای سرور برای منابعی که لینک ندارند (کلش، وایرگارد
  /// و مانند آن). هسته همه این پروتکل ها را می شناسد.
  static String _linkFromNode(VpnNode node) {
    final Map<String, dynamic> params = node.params;
    final String host = node.host;
    final int port = node.port;
    final String name = Uri.encodeComponent(node.name);
    switch (node.protocol) {
      case NodeProtocol.vless:
        // تله ای که ۱٫۰٫۱۰ را شکست: در منابع کلش، `type` نام **پروتکل** است
        // (`type: vless`)، نه نوع انتقال. خواندن `params['type']` باعث می شد
        // لینک `type=vless` بسازد و هسته با «unknown transport type: vless»
        // آن را رد کند. نوع انتقال فقط از `network` می آید.
        return _vlessLink(node, _transportOf(params));
      case NodeProtocol.vmess:
        return 'vmess://${base64Encode(utf8.encode(jsonEncode(<String, dynamic>{
              'v': '2',
              'ps': node.name,
              'add': host,
              'port': '$port',
              'id': JsonX.text(params['id']),
              'aid': '${JsonX.integer(params['alterId'])}',
              'scy': JsonX.text(params['method'], 'auto'),
              'net': _transportOf(params),
              'type': 'none',
              'host': JsonX.text(params['host'], host),
              'path': JsonX.text(params['path'], '/'),
              'tls': JsonX.text(params['security']) == 'tls' ? 'tls' : '',
              'sni': JsonX.text(params['sni'], host),
            })))}';
      case NodeProtocol.trojan:
        // همین تله `type` در تروجان هم بود؛ نوع انتقال فقط از `network`.
        return 'trojan://${Uri.encodeComponent(JsonX.text(params['password']))}'
            '@$host:$port?sni=${Uri.encodeComponent(JsonX.text(params['sni'], host))}'
            '&type=${_transportOf(params)}'
            '#$name';
      case NodeProtocol.shadowsocks:
        final String user = base64Encode(
          utf8.encode(
            '${JsonX.text(params['method'], 'aes-256-gcm')}:'
            '${JsonX.text(params['password'])}',
          ),
        );
        // نشانی شادوساکس وقتی نام کاربری و رمز جدا باشند خواناتر است.
        if (user.isEmpty) {
          return 'ss://$host:$port#$name';
        }
        return 'ss://$user@$host:$port#$name';
      case NodeProtocol.hysteria2:
        return 'hysteria2://${Uri.encodeComponent(JsonX.text(params['password']))}'
            '@$host:$port?sni=${JsonX.text(params['sni'], host)}#$name';
      case NodeProtocol.tuic:
        return 'tuic://${JsonX.text(params['id'] ?? params['uuid'])}:'
            '${Uri.encodeComponent(JsonX.text(params['password']))}'
            '@$host:$port?sni=${JsonX.text(params['sni'], host)}#$name';
      case NodeProtocol.ssh:
        final String user = Uri.encodeComponent(JsonX.text(params['username']));
        final String pass = JsonX.text(params['password']);
        final String auth =
            pass.isEmpty ? user : '$user:${Uri.encodeComponent(pass)}';
        final List<String> sshQuery = <String>[];
        final String pk = JsonX.text(
          params['privateKey'] ?? params['pk'] ?? params['private_key'],
        );
        final String hk = JsonX.text(params['hostKey'] ?? params['hk']);
        if (pk.isNotEmpty) {
          sshQuery.add('pk=${Uri.encodeQueryComponent(pk)}');
        }
        if (hk.isNotEmpty) {
          sshQuery.add('hk=${Uri.encodeQueryComponent(hk)}');
        }
        final String sshSuffix =
            sshQuery.isEmpty ? '' : '?${sshQuery.join('&')}';
        return 'ssh://$auth@$host:$port$sshSuffix#$name';
      case NodeProtocol.naive:
        final String user = Uri.encodeComponent(JsonX.text(params['username']));
        final String pass = JsonX.text(params['password']);
        final String auth =
            pass.isEmpty ? user : '$user:${Uri.encodeComponent(pass)}';
        final String sni = JsonX.text(params['sni'], host);
        final String scheme =
            JsonX.boolean(params['quic']) ? 'naive+quic' : 'naive+https';
        return '$scheme://$auth@$host:$port?sni=${Uri.encodeQueryComponent(sni)}#$name';
      case NodeProtocol.anytls:
        final String sni = JsonX.text(params['sni'], host);
        return 'anytls://${Uri.encodeComponent(JsonX.text(params['password']))}'
            '@$host:$port?sni=${Uri.encodeQueryComponent(sni)}#$name';
      case NodeProtocol.mieru:
        return 'mieru://${JsonX.text(params['username'])}:'
            '${Uri.encodeComponent(JsonX.text(params['password']))}'
            '@$host:$port?transport=${JsonX.text(params['transport'], 'TCP')}'
            '#$name';
      case NodeProtocol.wireguard:
      case NodeProtocol.amnezia:
      case NodeProtocol.clash:
      case NodeProtocol.socks:
        // این پروتکل ها در اشتراک های دیگر با فایل کامل می آیند؛ هسته
        // خود هسته همان فایل را می خواند. لینک ساختگی ساخته نمی شود.
        return '';
    }
  }

  /// برچسب عمومی سرور برای گزارش ها بدون افشای نام، پروتکل یا نشانی سرور.
  static String _nodeLabel(VpnNode node) => 'مسیر انتخابی آمبرلا';

  String _dirOf(String path) {
    final int index = path.lastIndexOf(Platform.pathSeparator);
    return index <= 0 ? path : path.substring(0, index);
  }

  /// مسیر فایل گزارش هسته برای یک نقشه اجرا.
  String _coreLogPath(LaunchPlan plan) =>
      '${plan.runDir}${Platform.pathSeparator}'
      '${plan.cores.first.name}-core.log';

  /// اجرای هسته.
  ///
  /// هسته در یک پنجره کنسول جداگانه بالا می آید: فایل
  /// `UmbrellaCli.exe` (همان `HiddifyCli.exe`) اجرا می شود و کاربر گزارش زنده
  /// را در همان پنجره می بیند. اگر باز کردن پنجره ممکن نشد، هسته بی صدا و
  /// بدون پنجره اجرا می شود تا اتصال از دست نرود.
  final Set<Process> _preparingProcesses = <Process>{};

  Future<bool> _launch(LaunchPlan plan) async {
    if (_cancelRequested || _disposed) return false;
    _lastLaunchUnusable = false;
    if (_coreProcesses.isNotEmpty || _runningPids.isNotEmpty) {
      await _stopCores();
    }
    final int preparationEpoch = _connectionEpoch;
    final Directory runDir = Directory(plan.runDir);
    await runDir.create(recursive: true);
    final CoreLaunch core = plan.cores.first;
    final String coreLog = _coreLogPath(plan);

    // فایل تنظیمات هسته: همان تنظیماتی که پنجره CLI و خود برنامه هر دو
    // می خوانند. لاگ در همان پوشه جلسه نوشته می شود.
    // همان فایل تنظیماتی که هسته می شناسد (`-d`)، با همان نامی که
    // خودش استفاده می کند.
    final String settingsPath =
        '${plan.runDir}${Platform.pathSeparator}${AppConfig.coreSettingsFile}';
    _activeChain = _settings.chain;
    if (_activeChain.licenseKey.isNotEmpty) {
      _networkSecrets.add(_activeChain.licenseKey);
    }
    if (_settings.lanSharingPassword.trim().isNotEmpty) {
      _networkSecrets.add(_settings.lanSharingPassword.trim());
    }
    final int configuredMixedPort = _configuredMixedPort;
    final int effectivePort =
        plan.proxyPort > 0 ? plan.proxyPort : configuredMixedPort;
    final String proxySecret = _settings.lanSharingPassword.trim();
    final bool localAuthEnabled = !(plan.usesSystemProxy && !plan.tun) &&
        _settings.localProxyAuth &&
        proxySecret.isNotEmpty;
    _activePlanTun = plan.tun;
    _activeMixedPort = effectivePort;
    _activeLocalProxyOpen = !plan.tun || _settings.localProxyInVpn;
    _activeLocalProxySecret = localAuthEnabled ? proxySecret : '';
    _launchedFilterSignature = _contentFilter.effectSignature;
    await File(settingsPath).writeAsString(
      jsonEncode(
        DirectProfile.sessionSettings(_activeNode, UmbrellaCore.settingsJson(
          tun: plan.tun,
          systemProxy: plan.usesSystemProxy,
          port: effectivePort,
          logFile: coreLog,
          networkSettings: _settings,
          contentFilter: _contentFilter,
          batterySaving: _batterySaving,
        )),
      ),
      flush: true,
    );

    final List<String> originalLinks = await File(plan.linksPath).readAsLines();
    // هم راستا با Hiddify: هیچ درخواست DNS مسدودکننده ای پیش از اجرای هسته زده
    // نمی شود؛ خود موتور sing-box با `dns-direct-group` و فیلتر ضد جعل در لحظه
    // اتصال موازی نشانی میزبان ها را حل می کند و فقط نرمال سازی لینک ها در چند
    // میلی ثانیه انجام می شود.
    final PreparedLinks prepared = await LinkPreparation.prepare(
      originalLinks.where((String line) => line.trim().isNotEmpty).toList(),
      resolveEndpoints: false,
    );
    if (_cancelRequested || _disposed || preparationEpoch != _connectionEpoch) return false;
    final File sessionLinks = File('${plan.runDir}${Platform.pathSeparator}prepared-links.txt');
    await sessionLinks.writeAsString('${prepared.links.join('\n')}\n', flush: true);

    // با `-d` هسته همه تنظیمات را از فایل می خواند و پرچم های تونل و پورت را
    // نادیده می گیرد؛ پس فایل کامل نوشته می شود (UmbrellaCore.settingsJson) و
    // فقط مسیر فایل به آرگومان ها اضافه می شود.
    final ContentBlockServer? blockServer = await ensureBlockServerStarted();
    final ({int? filterPort, int? egressPort, String secret, bool broadMode})
        httpsCfg = await _prepareHttpsFilterForSession();
    await _provisioner.ensureDataRuleSets(
      extraDataDir: '${plan.runDir}${Platform.pathSeparator}data',
    );
    final File runtime;
    try {
      runtime = await CoreRuntime.compile(
        executable: core.exe, workDir: core.workDir, runDir: plan.runDir,
        linksPath: sessionLinks.path, settingsPath: settingsPath,
        stickyMinutes: _settings.stickyMinutes,
        blockPagePort: (blockServer != null && blockServer.proxyPort > 0)
            ? blockServer.proxyPort
            : null,
        httpsFilterPort: httpsCfg.filterPort,
        httpsFilterEgressPort: httpsCfg.egressPort,
        httpsFilterSecret: httpsCfg.secret,
        httpsFilterBroadMode: httpsCfg.broadMode,
        localRuleSetPaths: _provisioner.localRuleSetPaths,
        cancelled: () => _cancelRequested || _disposed || preparationEpoch != _connectionEpoch,
        onStarted: _preparingProcesses.add,
        onFinished: _preparingProcesses.remove,
      );
    } on Exception catch (error) {
      if (!_cancelRequested) _log.add('ساخت پیکربندی اجرایی هسته ناموفق بود: $error', level: 'error');
      return false;
    }
    final List<String> args = <String>['srun', '-c', runtime.path, '-D', plan.runDir];
    if (_cancelRequested || _disposed || preparationEpoch != _connectionEpoch) return false;

    try {
      if (CliSession.wanted(_settings) && Platform.isWindows) {
        // اجرا در یک پنجره کنسول جدا. `start` پنجره را
        // می سازد و خودش فورا برمی گردد؛ خود هسته فرایند فرزند است.
        final String sessionPath = await CliSession.writeSession(
          CliSessionFile(
            exe: core.exe,
            args: args,
            workDir: core.workDir,
            coreName: core.binaryName,
            logPath: coreLog,
            title: CliSession.titleFor(
              _activeNode ?? _nodeFallback,
              _settings,
            ),
          ),
          plan.runDir,
        );
        final bool opened = await CliSession.openWindow(
          session: sessionPath,
          title: CliSession.titleFor(_activeNode ?? _nodeFallback, _settings),
        );
        if (!opened) {
          // پنجره باز نشد؛ همان هسته بی صدا اجرا می شود (پایین همین تابع).
          _log.add(
            'پنجره فرمان هسته باز نشد؛ هسته بدون پنجره اجرا می شود.',
            level: 'warning',
          );
        } else {
          _log.add(
            'هسته در پنجره فرمان اجرا شد (پورت ${Fa.num(plan.proxyPort)})',
          );
          // فرایند هسته فرزند همان پنجره است؛ با نامش سنجیده و بسته می شود.
          _runningBinaries.add(core.binaryName);
          _log.add('فایل تنظیمات هسته: $settingsPath');
          return true;
        }
      }

      // نبودِ پنجره: اجرای بی صدا با همان آرگومان ها و نگهبان عمر والد.
      final Process process = await Process.start(
        core.exe,
        args,
        workingDirectory: core.workDir,
        environment: UmbrellaCore.ownerEnvironment(),
        runInShell: false,
      );
      unawaited(_native.attachCoreJob(process.pid));
      if (_cancelRequested || _disposed || preparationEpoch != _connectionEpoch) {
        process.kill();
        await process.exitCode.timeout(const Duration(seconds: 3), onTimeout: () => -1);
        return false;
      }
      final bool started = await _track(process, core, coreLog);
      _log.add('فایل تنظیمات هسته: $settingsPath');
      return started;
    } on ProcessException catch (error) {
      _log.add(
        'اجرای ${core.binaryName} ناموفق بود: ${error.message} '
        '(کد ${Fa.num(error.errorCode)})',
        level: 'error',
        details: <LogDetail>[
          LogDetail(
            title: 'فرمان اجرا و مسیرها',
            text: <String>[
              'برنامه: ${core.binaryName}',
              'مسیر: ${core.exe}',
              'پوشه اجرا: ${core.workDir}',
              'کد خطای ویندوز: ${Fa.num(error.errorCode)}',
              'نوع خطا: ${error.runtimeType}',
              if (args.isNotEmpty) 'آرگومان ها: ${args.join(' ')}',
            ].join('\n'),
          ),
          LogDetail(
            title: 'آیا فایل اجرایی هست؟',
            text: await _executableState(core.exe),
          ),
        ],
      );
      _log.add('مسیر هسته: ${core.exe}', level: 'error');
      _logLaunchHint(error.errorCode);
      return false;
    } on FileSystemException catch (error) {
      _log.add(
        'اجرای ${core.binaryName} ناموفق بود: ${error.message}',
        level: 'error',
        details: <LogDetail>[
          LogDetail(
            title: 'فرمان اجرا و مسیرها',
            text: <String>[
              'برنامه: ${core.binaryName}',
              'مسیر: ${core.exe}',
              'پوشه اجرا: ${core.workDir}',
              'مسیر مشکل دار: ${error.path ?? 'نامشخص'}',
              'آیا فایل اجرایی هست؟ ${await _executableState(core.exe)}',
            ].join('\n'),
          ),
        ],
      );
      _log.add('مسیر هسته: ${core.exe}', level: 'error');
      return false;
    }
  }

  /// همان مسیرهایی که برای پیدا کردن فایل اجرایی بررسی می شوند.
  List<String> _binaryCandidates(String binary) => <String>[
        '${_provisioner.appDir}${Platform.pathSeparator}$binary',
        '${_provisioner.bundledDir}${Platform.pathSeparator}$binary',
        '${_provisioner.bundledDir}${Platform.pathSeparator}umbrella'
            '${Platform.pathSeparator}$binary',
        '${_provisioner.bundledDir}${Platform.pathSeparator}bin'
            '${Platform.pathSeparator}$binary',
        '${_provisioner.binDir}${Platform.pathSeparator}$binary',
      ];

  /// توضیح اینکه چرا هیچ سروری برای اجرا قبول نشد (بدون افشای نام یا پروتکل سرور).
  String _whyNoUsableServer() {
    final List<VpnNode> disabled =
        _nodes.where((VpnNode node) => node.disabled).toList();
    final List<VpnNode> noHost =
        _nodes.where((VpnNode node) => node.host.trim().isEmpty).toList();
    final List<VpnNode> notUsable =
        _nodes.where((VpnNode node) => !usable(node)).toList();
    return <String>[
      'کل مسیرها: ${Fa.num(_nodes.length)}',
      'غیرفعال شده: ${Fa.num(disabled.length)}',
      'ناقص: ${Fa.num(noHost.length)}',
      'ناسازگار با این نسخه: ${Fa.num(notUsable.length)}',
    ].join('\n');
  }

  /// خلاصه وضعیت مسیرهای اشتراک بدون افشای نوع پروتکل یا مشخصات سرور.
  String _protocolBreakdown() {
    if (_nodes.isEmpty) {
      return 'هیچ مسیری خوانده نشده است.';
    }
    final int ready =
        _nodes.where((VpnNode node) => usable(node) && !node.disabled).length;
    return <String>[
      'مسیرهای دریافت شده: ${Fa.num(_nodes.length)}',
      'مسیرهای قابل استفاده: ${Fa.num(ready)}',
    ].join('\n');
  }

  /// وضعیت فایل اجرایی هسته: هست یا نه، چه اندازه ای دارد، آخرین تغییرش کِی
  /// بوده. فایل نیمه دانلود شده یا پاک شده با آنتی ویروس، همین جا معلوم می شود.
  Future<String> _executableState(String path) async {
    try {
      final File file = File(path);
      if (!await file.exists()) {
        return 'فایل وجود ندارد: $path';
      }
      final FileStat stat = await file.stat();
      final double mb = stat.size / (1024 * 1024);
      return 'هست (${Fa.num(mb.toStringAsFixed(1)).replaceAll('.', '٫')} مگابایت، آخرین تغییر: '
          '${Fa.dateTime(stat.modified)})';
    } on FileSystemException catch (error) {
      return 'وضعیت فایل خوانده نشد: ${error.message}';
    }
  }

  /// نام جایگزین وقتی هنوز سروری انتخاب نشده است.
  VpnNode get _nodeFallback => VpnNode(
        id: 'core',
        name: AppConfig.appName,
        protocol: NodeProtocol.vless,
        host: '',
        port: 0,
        sourceId: '',
        params: const <String, dynamic>{},
      );

  /// ثبت فرایند هسته ای که بی صدا اجرا شده است.
  Future<bool> _track(
    Process process,
    CoreLaunch core,
    String coreLog,
  ) async {
    _coreProcesses[core.name] = process;
    _runningPids.add(process.pid);
    _runningBinaries.add(core.binaryName);
    final File logFile = File(coreLog);
    await logFile.parent.create(recursive: true);
    // هر اجرا گزارش تازه خودش را دارد.
    //
    // تا ۱٫۰٫۱۰ این فایل با `FileMode.append` باز می شد، پس خروجی همه اجراهای
    // قبلی روی هم تلنبار می شد. در گزارش کاربر صدها خط از اجرای عصر روز قبل
    // آمده بود و خطای واقعی همان لحظه (که دو خط بود) بین آن ها گم شده بود.
    final IOSink sink = logFile.openWrite(mode: FileMode.write);
    process.stdout.listen(sink.add);
    process.stderr.listen(sink.add);

    // اگر هسته بلافاصله بسته شود (پورت یا پیکربندی نامعتبر)، در همان چند صد
    // میلی ثانیه اول خارج می شود؛ بقیه آمادگی در `_waitForTunnel` سنجیده می شود.
    final int? exited = await Future.any<int?>(<Future<int?>>[
      process.exitCode,
      Future<int?>.delayed(const Duration(milliseconds: 60), () => null),
    ]);
    if (exited != null) {
      if (identical(_coreProcesses[core.name], process)) _coreProcesses.remove(core.name);
      _runningPids.remove(process.pid);
      await _reportCoreExit(core, coreLog, exited, pid: process.pid);
      // جریان خروجی هم بسته می شود تا فایل گزارش نیمه باز نماند.
      await sink.flush();
      await sink.close();
      return false;
    }

    unawaited(
      process.exitCode.then((int code) async {
        await sink.flush();
        await sink.close();
        if (identical(_coreProcesses[core.name], process)) {
          _coreProcesses.remove(core.name);
        }
        _runningPids.remove(process.pid);
        if (_runningPids.isEmpty) {
          _runningBinaries.clear();
        }
        // اگر همین لحظه پیش از آماده شدن بسته شد، _launch خودش گزارش داده
        // است؛ دو بار گفتن همان حرف، گزارش را گمراه کننده می کرد.
        if (_reportedExitFor == code) {
          _reportedExitFor = null;
          return;
        }
        if (_stoppingOwnCore) {
          // خودمان بستیم؛ هشدار «بسته شد» گمراه کننده است.
          return;
        }
        final String full = await _readLogFull(coreLog);
        final String goHeadline = WindowsCrash.goCrashHeadline(full);
        final String crashReason = UmbrellaCore.describeWindowsExitCode(code);
        final String winEvent =
            (code != 0 && (full.trim().isEmpty || crashReason.isNotEmpty))
                ? await WindowsCrash.lookupApplicationError(process.pid)
                : '';
        final List<LogDetail> extraDetails = <LogDetail>[
          if (goHeadline.isNotEmpty)
            LogDetail(title: 'جزئیات خرابی هسته', text: goHeadline),
          if (winEvent.isNotEmpty)
            LogDetail(
              title: 'رویداد خطای ویندوز (شناسه ۱۰۰۰)',
              text: winEvent,
            ),
        ];
        _log.add(
          crashReason.isNotEmpty
              ? '${core.binaryName}: $crashReason'
              : winEvent.isNotEmpty
                  ? winEvent
                  : goHeadline.isNotEmpty
                      ? 'هسته آمبرلا با خطای داخلی متوقف شد (کد خروج ${Fa.num(code)}).'
                      : 'هسته آمبرلا بسته شد (کد خروج ${Fa.num(code)}).',
          level: (crashReason.isNotEmpty ||
                  goHeadline.isNotEmpty ||
                  winEvent.isNotEmpty)
              ? 'error'
              : 'warning',
          details: extraDetails,
        );
      }),
    );
    if (_cancelRequested || _disposed) return false;
    _log.add('هسته آمبرلا اجرا شد (شناسه ${Fa.num(process.pid)}).');
    return true;
  }

  /// آزادسازی پورت های هسته با تلاش دوباره، پیش از اجرای هسته.
  ///
  /// **گزارش ۱٫۰۱۸:** `_freeCorePorts` صاحب پورت را بست و پورت را «آزاد»
  /// خواند، ولی هسته تازه بلافاصله با `port 17078 is already in use` مرد.
  /// ویندوز پس از `TerminateProcess` چند صد میلی ثانیه پورت را در TIME_WAIT
  /// نگه می دارد و فرزندِ در حال مرگ هم هنوز گوش می دهد. آزاد بودن فهرست
  /// بلافاصله بعد از kill، تضمین آزاد بودن هنگام اجرا نیست. پس: چند تلاش،
  /// با فاصله فزاینده، و در هر تلاش فهرست واقعی دوباره خوانده می شود.
  Future<bool> _freeCorePortsWithRetry() async {
    // حالت عادی: پورت ها از همان اول آزادند؛ بدون هیچ مکث اضافی ادامه بده.
    if ((await _heldPorts(UmbrellaCore.allPorts)).isEmpty) {
      return true;
    }
    const List<Duration> gaps = <Duration>[
      Duration(milliseconds: 200),
      Duration(milliseconds: 400),
      Duration(milliseconds: 800),
      Duration(milliseconds: 1500),
    ];
    for (int attempt = 0; attempt < gaps.length; attempt++) {
      if (await _freeCorePorts()) {
        // پس از بستن فرایند مزاحم، یک مکث کوتاه برای آزاد شدن TIME_WAIT.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if ((await UmbrellaCore.heldReservedPorts()).isEmpty) {
          return true;
        }
      }
      await Future<void>.delayed(gaps[attempt]);
    }
    return _freeCorePorts();
  }

  /// بستن پورت های هسته: نمونه های بازمانده، بعد هسته های دیگر.
  ///
  /// تا ۱٫۰٫۹ اگر برنامه دیگری گرفته بود، فقط پیام خطا می دادیم و کاربر باید
  /// خودش برنامه را پیدا و ببندد. در گزارش ۱٫۰٫۹ صاحب پورت `Hiddify` بود.
  ///
  /// حالا برنامه خودش این کار را می کند: هر پردازشی که این پورت ها را گرفته
  /// بسته می شود، اما فقط وقتی که یکی از این دو باشد:
  ///
  /// ۱. خودِ هسته های ما (UmbrellaCli/CoreEngine/Admin) — همیشه.
  /// ۲. هسته های فیلترشکن دیگری که همین پورت را گرفته اند — چون تا وقتی
  ///    باز باشند، هیچ اتصالی ممکن نیست؛ و کاربر خودش آمبرلا را باز کرده
  ///    که وصل شود.
  ///
  /// پردازش های دیگر ویندوز (مرورگر، سرویس های سیستم) هرگز بسته نمی شوند؛
  /// برای آن ها فقط گزارش می دهیم تا کاربر خودش تصمیم بگیرد. این کار با
  /// اجازه کاربر انجام می شود (تنظیم `freeCorePorts`).
  Future<bool> _freeCorePorts() async {
    List<int> held = await UmbrellaCore.heldReservedPorts();
    // پورت های خود برنامه هم بررسی می شوند: نمونه بازمانده آمبرلا که پورت
    // پروکسی را گرفته باشد، همان قدر اتصال را می کشد.
    final List<int> defaultAppHeld = await _heldPorts(UmbrellaCore.appPorts);
    final List<int> extraAppPorts = <int>[
      if (!UmbrellaCore.appPorts.contains(_configuredMixedPort))
        _configuredMixedPort,
      if (_settings.allowConnectionFromLan &&
          LanSharing.isValidPort(_settings.lanSharingPort) &&
          !UmbrellaCore.appPorts.contains(_settings.lanSharingPort) &&
          _settings.lanSharingPort != _configuredMixedPort)
        _settings.lanSharingPort,
    ];
    final List<int> appHeld = extraAppPorts.isEmpty
        ? defaultAppHeld
        : <int>[...defaultAppHeld, ...await _heldPorts(extraAppPorts)];
    if (held.isEmpty && appHeld.isEmpty) {
      return true;
    }
    if (held.isEmpty) {
      // فقط پورت های برنامه گرفته اند؛ با بستن نمونه بازمانده آزاد می شوند.
      final int killed = await _killOwnCores();
      if (await _waitForPorts(appHeld)) {
        _log.add(
          'پورت پروکسی از اجرای قبلی باز مانده بود و آزاد شد'
          '${killed > 0 ? ' (${Fa.num(killed)} فرایند)' : ''}.',
          level: 'warning',
        );
        return true;
      }
    }

    // ۱. همیشه اول نمونه های خودمان.
    final int own = await _killOwnCores();
    _orphansKilled += own;
    if (await _waitForPorts(held)) {
      _log.add(
        'پورت هسته از اجرای قبلی باز مانده بود و آزاد شد'
        '${_orphansKilled > 0 ? ' (${Fa.num(_orphansKilled)} فرایند)' : ''}.',
        level: 'warning',
      );
      _orphansKilled = 0;
      return true;
    }

    // ۲. برنامه دیگری پورت را گرفته. اگر اجازه داشته باشیم، خودش می بندد.
    held = await UmbrellaCore.heldReservedPorts();
    final List<PortHolder> holders =
        await UmbrellaCore.holders(held, native: _native);
    final List<PortHolder> cores =
        holders.where((PortHolder holder) => holder.isForeignCore).toList();
    final List<PortHolder> strangers =
        holders.where((PortHolder holder) => !holder.isForeignCore).toList();

    if (cores.isNotEmpty && _settings.freeCorePorts) {
      final String names =
          cores.map((PortHolder holder) => holder.label).join('، ');
      _log.add(
        'برنامه دیگری پورت هسته را گرفته بود ($names)؛ خودکار بسته شد تا '
        'اتصال ممکن شود.',
        level: 'warning',
        details: <LogDetail>[
          LogDetail(title: 'چه چیزی بسته شد', text: _holderText(cores)),
          LogDetail(
            title: 'چرا',
            text: 'هسته آمبرلا پورت های ثابت ۱۷۰۷۸ و ۱۶۷۵۶ را می خواهد و '
                'راهی برای عوض کردنشان ندارد؛ تا وقتی برنامه دیگری روی آن '
                'ها گوش می دهد، هسته اصلا بالا نمی آید.\n'
                'اگر نمی خواهید برنامه دیگری بسته شود، در تنظیمات '
                '«آزادسازی خودکار پورت های هسته» را خاموش کنید.',
          ),
        ],
      );
      // بستن با خواندن دوبارهٔ فهرست، تا سه بار.
      //
      // در گزارش ۱٫۰۱۴ سه بار پشت سر هم هسته «خارجی» با شناسه های
      // ۱۱۸۶۰ و ۵۲۳۶ و ۵۲۴۴ بسته شد و هر سه بار بعدش
      // `port 17078 is already in use` آمد. یعنی شناسه ای که بستیم صاحب
      // واقعی پورت نبود: یا پردازش فرزند جای دیگری گوش می داد، یا بلافاصله
      // پردازش تازه ای همان پورت را گرفت. یک بار بستن کافی نیست.
      // فقط هسته هایی که واقعاً مال ما نیستند بسته می شوند. پورت ۱۷۰۷۸
      // اغلب در دست فرزند همان هسته خودمان است که لحظه ای زنده مانده؛
      // بستن آن فقط هسته تازه را دوباره به همان جنگ می اندازد.
      for (int round = 0; round < 3; round++) {
        final List<PortHolder> current = await UmbrellaCore.holders(
          await UmbrellaCore.heldReservedPorts(),
          native: _native,
        );
        final List<PortHolder> stillCores = current
            .where((PortHolder holder) => holder.holdsPortAgainstUs)
            .toList();
        // فرزندان خودمان: فقط کشته می شوند، گزارش «برنامه دیگری» برایشان
        // نوشته نمی شود، چون واقعاً برنامه دیگری نیست.
        for (final PortHolder holder in current) {
          if (!holder.holdsPortAgainstUs && !holder.isOurs) {
            await _native.killPid(holder.pid);
          }
        }
        if (stillCores.isEmpty) {
          if (await _waitForPorts(held, timeout: const Duration(seconds: 3))) {
            return true;
          }
          continue;
        }
        for (final PortHolder holder in stillCores) {
          await _native.killPid(holder.pid);
        }
        if (await _waitForPorts(held, timeout: const Duration(seconds: 3))) {
          return true;
        }
        if (round < 2) {
          _log.add(
            'پورت هسته هنوز گرفته بود؛ دوباره بررسی و آزادسازی می شود '
            '(تلاش ${Fa.num(round + 2)} از ۳).',
            level: 'warning',
          );
        }
      }
      if (await _waitForPorts(held)) {
        return true;
      }
    }

    // ۳. هنوز گرفته است: حالا دقیق بگویید چه چیزی مانده و چرا خودکار بسته نشد.
    final List<int> still = await UmbrellaCore.heldReservedPorts();
    if (still.isEmpty) {
      return true;
    }
    final String ports = still.map((int port) => Fa.num(port)).join('، ');
    final String names =
        strangers.map((PortHolder holder) => holder.label).join('، ');
    final bool blockedByStranger = strangers.isNotEmpty;
    _log.add(
      'پورت $ports آزاد نشد و هسته برای کار به همان ها نیاز دارد.'
      '${names.isEmpty ? '' : ' (در اختیار: $names)'}',
      level: 'error',
      details: <LogDetail>[
        LogDetail(
          title: 'پورت های هسته در همین لحظه',
          text: <String>[
            for (final int port in UmbrellaCore.reservedPorts)
              '${Fa.num(port)}: '
                  '${still.contains(port) ? 'گرفته شده' : 'آزاد'}',
          ].join('\n'),
        ),
        if (holders.isNotEmpty)
          LogDetail(title: 'برنامه های صاحب پورت', text: _holderText(holders)),
        LogDetail(
          title: 'چرا خودکار بسته نشد',
          text: blockedByStranger
              ? 'این برنامه ها هسته فیلترشکن نیستند (یا ویندوز اجازه بستنشان '
                  'را نداد)، پس برنامه عمداً آن ها را نبست. اگر می دانید کار '
                  'همان برنامه را مختل نمی کند، خودتان ببندیدش و دوباره وصل '
                  'شوید.'
              : _settings.freeCorePorts
                  ? 'برنامه تلاش کرد صاحب پورت را ببندد ولی پورت آزاد نشد؛ '
                      'احتمالاً ویندوز اجازه نداد. برنامه را با دسترسی مدیر '
                      'اجرا کنید.'
                  : '«آزادسازی خودکار پورت های هسته» در تنظیمات خاموش است. '
                      'با روشن کردن آن، آمبرلا خودش برنامه مزاحم را می بندد.',
        ),
      ],
    );
    return false;
  }

  /// بستن نمونه های خود آمبرلا با نام؛ تعداد بسته شده برمی گردد.
  Future<int> _killOwnCores() async {
    int killed = 0;
    for (final String binary in <String>[
      umbrellaCliBinary,
      UmbrellaCore.engineBinary,
      UmbrellaCore.adminBinary,
    ]) {
      killed += await _native.killByName(binary);
    }
    return killed;
  }

  /// کدام یک از این پورت ها همین حالا گرفته اند (بررسی موازی و سریع).
  Future<List<int>> _heldPorts(List<int> ports) async {
    final List<bool> states = await Future.wait<bool>(
      ports.map(UmbrellaCore.inUse),
    );
    return <int>[
      for (int i = 0; i < ports.length; i++)
        if (states[i]) ports[i],
    ];
  }

  /// انتظار کوتاه تا آزاد شدن پورت ها (یا پایان مهلت).
  Future<bool> _waitForPorts(
    List<int> ports, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if ((await UmbrellaCore.heldReservedPorts()).isEmpty) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return (await UmbrellaCore.heldReservedPorts()).isEmpty;
  }

  /// متن خوانا از صاحب های پورت، برای گزارش.
  static String _holderText(List<PortHolder> holders) {
    if (holders.isEmpty) {
      return 'نام برنامه خوانده نشد (ویندوز اجازه نداد).';
    }
    return holders
        .map(
          (PortHolder holder) => <String>[
            '${holder.label} (شناسه ${Fa.num(holder.pid)})',
            // مسیر فقط برای هسته های شناخته شده پنهان می شود؛ برای بقیه
            // کاربر باید بداند کدام برنامه را ببندد.
            if (holder.path.isNotEmpty && !holder.isForeignCore)
              '  مسیر: ${holder.path}',
            '  پورت: '
                '${holder.ports.map((int port) => Fa.num(port)).join('، ')}',
          ].join('\n'),
        )
        .join('\n');
  }

  /// نام فایل اجرایی صاحب پورت، فقط وقتی که هسته شناخته شده نیست.
  ///
  /// برای هسته های شناخته شده نام تجاری نمایش داده نمی شود (قاعده «فقط
  /// آمبرلا»)، ولی شناسه پردازش و پورت گفته می شود تا در Task Manager
  /// پیدا شود.

  /// آیا هسته همین سرور را نتوانست بخواند؟
  ///
  /// `unable to determine config format` یعنی لینک این سرور با هسته خوانده
  /// نمی شود؛ تلاش دوباره با همان لینک همان نتیجه را می دهد.
  static bool _linkUnusable(String output) {
    final String text = output.toLowerCase();
    return text.contains('unable to determine config format') ||
        text.contains('no outbounds found');
  }

  /// کد خروجی که همین حالا در `_launch` گزارش شد، تا گزارش دوباره تکرار نشود.
  int? _reportedExitFor;

  /// آیا همین حالا یک اتصال در جریان است؟
  ///
  /// تا ۱٫۰۱۲ دو درخواست همزمان هر دو اجرا می شدند و بر سر پورت ثابت هسته
  /// با هم می جنگیدند.
  bool _connectInFlight = false;

  /// هنگام خاموش کردن عمدی هسته روشن می شود.
  ///
  /// تا ۱٫۰٫۱۰، وقتی خود برنامه هسته را می کشت، خروج با کد ۰ به گزارش
  /// می آمد و به شکل «بلافاصله بسته شد (کد خروج ۰)» نمایش داده می شد؛
  /// یعنی کاربر فکر می کرد هسته خودش مرده، در حالی که خودمان بسته بودیمش.
  bool _stoppingOwnCore = false;

  /// گزارش بسته شدن هسته با دلیلش، یک بار و کامل.
  Future<void> _reportCoreExit(
    CoreLaunch core,
    String coreLog,
    int code, {
    int pid = 0,
  }) async {
    final String full = await _readLogFull(coreLog);
    if (_stoppingOwnCore && code == 0) {
      // بستن عمدی خودمان؛ این «خرابی» نیست و نباید در گزارش خطا بیاید.
      _lastLaunchUnusable = false;
      return;
    }
    final String tail = await _readLogTail(coreLog);
    final String ntDesc = UmbrellaCore.describeWindowsExitCode(code);
    final String goHeadline = WindowsCrash.goCrashHeadline(full);
    final String winEvent = (pid > 0 &&
            (full.trim().isEmpty || ntDesc.isNotEmpty || code < 0 || code > 255))
        ? await WindowsCrash.lookupApplicationError(pid)
        : '';
    final List<LogDetail> details =
        await _coreDiagnostics(core, coreLog, code: code);
    if (goHeadline.isNotEmpty) {
      details.add(LogDetail(title: 'نشانه خطای هسته', text: goHeadline));
    }
    if (winEvent.isNotEmpty) {
      details.add(
        LogDetail(
          title: 'رویداد خطای ویندوز (شناسه ۱۰۰۰)',
          text: winEvent,
        ),
      );
    }
    _log.add(
      ntDesc.isNotEmpty
          ? '$ntDesc${tail.isEmpty ? '' : ' خروجی هسته: $tail'}'
          : 'هسته آمبرلا بلافاصله بسته شد (کد خروج ${Fa.num(code)}).'
              '${tail.isEmpty ? '' : ' خروجی هسته: $tail'}',
      level: 'error',
      details: details,
    );
    // دلیل را به زبان کاربر هم می گوییم؛ خروجی خام بالا برای عیب یابی
    // می ماند، ولی خودش راه حل نمی دهد.
    final String cause = _explainCoreExit(full);
    if (cause.isNotEmpty) {
      _log.add(cause, level: 'error');
    }
    _lastLaunchUnusable = _linkUnusable(full);
    _reportedExitFor = code;
  }

  /// همه چیزهایی که برای فهمیدن «مشکلش چیست» لازم است.
  ///
  /// پیام خطا یک جمله است و کاربر را به جایی نمی رساند؛ در گزارش ۱٫۰٫۷ هم
  /// معلوم نبود کدام سرور، با چه فرمانی و در چه وضعیتی بسته شد. اینجا خروجی
  /// کامل هسته (نه ۶۰۰ نویسه آخر)، فرمان اجرا، مسیر فایل ها، پورت های گرفته
  /// شده و نام برنامه ای که گرفته، یک جا جمع می شود.
  Future<List<LogDetail>> _coreDiagnostics(
    CoreLaunch core,
    String coreLog, {
    int? code,
    LaunchPlan? plan,
  }) async {
    final List<LogDetail> details = <LogDetail>[];

    // ۱. خروجی کامل هسته؛ مهمترین چیز برای فهمیدن دلیل.
    final String full = (await _readLogFull(coreLog)).trim();
    details.add(
      LogDetail(
        title: 'خروجی کامل هسته (${core.name})',
        text: full.isEmpty
            ? 'هسته هیچ خروجی ای نداد. یعنی پیش از نوشتن هر خطی بسته شد؛ '
                'بیشتر وقت ها دلیلش نبود دسترسی، آنتی ویروس یا فایل اجرایی '
                'ناقص است.'
            : displayOwnCoreOutput(full, engineId: UmbrellaCore.id),
      ),
    );

    // ۲. فرمان اجرا و مسیرهای محلی (بدون مسیر فایل لینک یا مشخصات سرور).
    details.add(
      LogDetail(
        title: 'فرمان اجرا و مسیرها',
        text: <String>[
          'برنامه: ${core.binaryName}',
          'مسیر: ${core.exe}',
          'پوشه اجرا: ${core.workDir}',
          'فایل گزارش هسته: $coreLog',
          if (plan != null)
            'حالت اتصال: ${plan.tun ? 'تونل کامل' : 'پروکسی سیستمی'}',
          if (plan != null && plan.proxyPort > 0)
            'پورت محلی: ${Fa.num(plan.proxyPort)}',
          if (code != null) 'کد خروج: ${Fa.num(code)}',
        ].join('\n'),
      ),
    );

    // ۳. مشخصات سرور، دامنه، آی پی، پورت و پروتکل هرگز در گزارش ثبت نمی شود.

    // ۴. وضعیت پورت های ثابت هسته؛ اگر گرفته باشند، صاحبش.
    //
    // نام خام ویندوز (`17078=Hiddify`) اینجا نوشته نمی شود: طبق قرارمان در
    // متن نمایش داده شده فقط نام «آمبرلا» می آید. `PortHolder.label` همان
    // هسته های رقیب را «یک هسته فیلترشکن دیگر» می نامد.
    final List<int> held = await UmbrellaCore.heldReservedPorts();
    if (held.isNotEmpty) {
      final List<PortHolder> holders =
          await UmbrellaCore.holders(held, native: _native);
      details.add(
        LogDetail(
          title: 'پورت های هسته در همین لحظه',
          text: <String>[
            for (final int port in held)
              '${Fa.num(port)}: '
                  '${holders.any((PortHolder holder) => holder.ports.contains(port)) ? 'گرفته شده' : 'آزاد'}',
            if (holders.isNotEmpty) '─ صاحب پورت ─',
            if (holders.isNotEmpty) _holderText(holders),
          ].join('\n'),
        ),
      );
    }

    // ۵. فایل تنظیماتی که به هسته داده شد؛ اگر کلیدی غلط یا خالی باشد،
    // همان جا دیده می شود.
    if (plan != null) {
      final String settingsPath = '${plan.runDir}'
          '${Platform.pathSeparator}${AppConfig.coreSettingsFile}';
      final String settings = (await _readLogFull(settingsPath)).trim();
      if (settings.isNotEmpty) {
        details.add(
          LogDetail(title: 'فایل تنظیمات هسته', text: settings),
        );
      }
    }
    return details;
  }

  /// بررسی سلامت سبک هم راستا با Hiddify: تا وقتی پایش داخلی هسته روی خروجی
  /// فعال سالم است (`STARTED`) بدون هیچ سربار HTTPS اضافه اتصال تایید می شود؛
  /// فقط در حالت زنجیره یا هنگام گزارش افت در پایش هسته سنجش HTTPS اجرا می شود.
  Future<bool> _tunnelFlowsNow() async {
    if (!_activeChain.enabled) {
      final CoreProxySnapshot snapshot = await ClashApi.status(
        since: _sessionStartUtc,
        timeout: const Duration(milliseconds: 900),
      );
      if (snapshot.reachable) {
        if (snapshot.connectivity == CoreConnectivityState.started) {
          return true;
        }
        if (snapshot.connectivity == CoreConnectivityState.noAvailableProxies) {
          return false;
        }
      }
    }
    return VerifiedProbe.check(
      proxyPort: _probeProxyPort,
      proxyUser: _probeProxyUser,
      proxyPassword: _probeProxyPassword,
      timeout: const Duration(seconds: 5),
    );
  }

  /// آی پی و کشور خروجی از سطر `MONITORING result` خود هسته.
  ///
  /// گزارش ۱٫۰٫۱۵ نشان داد خواندن آی پی از سرویس های وب در ایران کار نمی کند
  /// (همه فیلتر یا کند هستند)، پس برنامه همیشه «آی پی خروجی خوانده نشد» می
  /// نوشت و کاربر نمی توانست مطمئن شود تونل کار می کند. خود هسته بعد از
  /// تنظیم `ipinfo-url` این سطر را می نویسد:
  ///   MONITORING result vless § 0: 1573 ms, IP: 1.2.3.4, Country: DE ...
  /// و همان، مدرک مستقیم خروج از کشور دیگر است.
  Future<String> _coreExitIp(String coreLog) async {
    final String full = await _readLogFull(coreLog);
    if (full.isEmpty) {
      return '';
    }
    final RegExp pattern = RegExp(
      r'MONITORING result [^:]*:\s*[0-9.]+\s*ms,\s*IP:\s*([0-9a-fA-F.:]+),'
      r'\s*Country:\s*([A-Za-z]{2})(?:,|\s|$)',
      caseSensitive: false,
    );
    for (final RegExpMatch match in pattern.allMatches(full)) {
      final String ip = match.group(1) ?? '';
      final String country = (match.group(2) ?? '').toLowerCase();
      // `direct` هم همین سطر را دارد؛ آی پی ایران یعنی تونل نبوده.
      if (ip.isEmpty || country == 'ir') {
        continue;
      }
      _exitIp = ip;
      return ip;
    }
    return '';
  }

  /// متن کامل گزارش هسته (برای تصمیم گیری، بی برش).
  Future<String> _readLogFull(String path) async {
    try {
      final File file = File(path);
      if (!await file.exists()) {
        return '';
      }
      return redactNetworkSecrets(await file.readAsString(), knownSecrets: _networkSecrets);
    } on FileSystemException {
      return '';
    }
  }

  /// دلیل بسته شدن هسته، از خروجی خودش، به زبان کاربر.
  ///
  /// در ۱٫۰٫۴ کاربر فقط «بلافاصله بسته شد» و یک دیوار متن انگلیسی می دید.
  /// اینجا همان خروجی خوانده می شود و دلیل واقعی با راه حل گفته می شود.
  static String _explainCoreExit(String output) {
    final String text = output.toLowerCase();
    if (text.contains('already in use')) {
      // پیش از ۱٫۰٫۱۲ اینجا از کاربر خواسته می شد خودش در Task Manager
      // برنامه را ببندد. طبق قرارمان، بستن پورت کار خود برنامه است.
      return 'پورت هسته هنگام این تلاش گرفته شده بود. آمبرلا پیش از هر تلاش '
          'خودش هسته قبلی را می بندد و پورت را آزاد می کند؛ این حالت دوباره '
          'امتحان می شود. اگر همه حالت ها همین را گفتند، تنظیم «آزادسازی '
          'خودکار پورت های هسته» را روشن بگذارید تا برنامه مزاحم هم خودکار '
          'بسته شود.';
    }
    if (text.contains('failed to serve grpc') ||
        text.contains('start core grpc server')) {
      return 'هسته نتوانست سرور داخلی خودش را بالا بیاورد (پورت ۱۷۰۷۸ یا '
          '۱۶۷۵۶ گرفته شده است). یک نمونه بازمانده یا یک فیلترشکن دیگر را '
          'ببندید و دوباره وصل شوید.';
    }
    if (text.contains('unknown flag')) {
      return 'این نسخه از هسته پرچمی را که برنامه فرستاده نمی شناسد؛ نسخه '
          'برنامه و هسته با هم نمی خوانند. برنامه را با نصب کننده رسمی همین '
          'نسخه دوباره نصب کنید.';
    }
    if (text.contains('unable to determine config format') ||
        text.contains('no outbounds found')) {
      return 'هسته نتوانست سرور را از لینک بسازد؛ این سرور قابل اجرا نبود و '
          'سرور بعدی امتحان می شود.';
    }
    if (text.contains('permission') || text.contains('access is denied')) {
      return 'ویندوز اجازه اجرای هسته را نداد؛ برنامه را با دسترسی مدیر اجرا '
          'کنید یا پوشه نصب را در استثناهای آنتی ویروس بگذارید.';
    }
    final RegExpMatch? ntstatus = RegExp(
      r'exception\s+0x([0-9a-f]{8})',
      caseSensitive: false,
    ).firstMatch(output);
    if (ntstatus != null) {
      final int? parsed = int.tryParse(ntstatus.group(1)!, radix: 16);
      if (parsed != null) {
        final String decoded = UmbrellaCore.describeWindowsExitCode(parsed);
        if (decoded.isNotEmpty) {
          return decoded;
        }
      }
    }
    return '';
  }

  /// توضیح فارسی برای خطاهای رایج ویندوز هنگام اجرای هسته.
  void _logLaunchHint(int code) {
    if (code == 225 || code == 1260) {
      _log.add(
        'آنتی ویروس یا سیاست ویندوز اجرای هسته را مسدود کرده است. '
        'پوشه نصب برنامه را در استثناهای آنتی ویروس اضافه کنید.',
        level: 'error',
      );
    } else if (code == 5) {
      _log.add(
        'دسترسی به فایل هسته ممکن نیست؛ برنامه را با دسترسی مدیر اجرا کنید.',
        level: 'error',
      );
    } else if (code == 2 || code == 3) {
      _log.add(
        'فایل هسته در پوشه نصب پیدا نشد؛ نسخه نصب را دوباره اجرا کنید.',
        level: 'error',
      );
    }
  }

  /// خلاصه خروجی یک هسته برای همان یک خط پیام.
  ///
  /// قبلاً ۶۰۰ نویسه آخر همه خطوط به هم چسبیده بود و گزارش را ناخوانا می کرد.
  /// متن کامل، دیگر در بخش جزئیات می آید؛ اینجا فقط آخرین خطی می آید که
  /// واقعاً چیزی می گوید (خطوط خالی و تزئینی رد می شوند).
  Future<String> _readLogTail(String path, {int maxChars = 300}) async {
    try {
      final File file = File(path);
      if (!await file.exists()) {
        return '';
      }
      final String text = redactNetworkSecrets(await file.readAsString(), knownSecrets: _networkSecrets);
      final List<String> rows = text
          .split(RegExp(r'\r?\n'))
          .map((String row) => row.trim())
          // خطوط تزئینی هسته (کادر و فاصله) چیزی نمی گویند.
          .where(
            (String row) =>
                row.isNotEmpty &&
                !RegExp(r'^[\-=_*\s]+$').hasMatch(row),
          )
          .toList();
      if (rows.isEmpty) {
        return '';
      }
      String last = rows.last;
      if (last.length > maxChars) {
        last = '…${last.substring(last.length - maxChars)}';
      }
      return displayOwnCoreOutput(last, engineId: UmbrellaCore.id);
    } on FileSystemException {
      return '';
    }
  }

  /// پروکسی سیستمی ویندوز را به هسته فعال وصل می کند.
  Future<bool> _enableProxy(LaunchPlan plan) async {
    if (!plan.usesSystemProxy) {
      return false;
    }
    final bool ok = await _native.setSystemProxy(
      host: '127.0.0.1',
      port: plan.proxyPort,
    );
    _proxyPort = ok ? plan.proxyPort : 0;
    if (ok) {
      _log.add('پروکسی ویندوز روی پورت ${Fa.num(plan.proxyPort)} تنظیم شد.');
    } else {
      _log.add('تنظیم پروکسی سیستمی ناموفق بود.', level: 'warning');
    }
    return ok;
  }

  Future<void> _disableProxy() async {
    if (_proxyPort == 0) {
      return;
    }
    await _native.disableSystemProxy();
    _proxyPort = 0;
    _log.add('پروکسی سیستمی برداشته شد.');
  }

  /// هسته اول پیکربندی را می سازد، بعد کارت شبکه را بالا می آورد و
  /// تست سرعت سرورها را شروع می کند؛ ۲۵ ثانیه برای همین کافی است.
  static const Duration _tunnelTimeout = Duration(seconds: 25);

  /// بودجه زمانی یک درخواست اتصال.
  ///
  /// با این اصلاح کل اشتراک امتحان می شود، پس این بودجه لازم است: اگر هیچ
  /// سروری تونل نسازد، حلقه تلاش باید بعد از این مدت بسته شود و کاربر
  /// بفهمد چند سرور امتحان شد، نه اینکه برای همیشه «در حال اتصال» بماند.
  /// در حالت عادی (هسته همه لینک ها را یک جا می سنجد) نوبت اول کافی است و
  /// این بودجه اصلا به پایان نمی رسد.
  static const Duration _connectBudget = Duration(minutes: 5);

  Future<bool> _waitForTunnel(LaunchPlan plan) async {
    final DateTime deadline = DateTime.now().add(_tunnelTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_disposed || _cancelRequested) {
        return false;
      }
      // اگر خودمان فرایند را در دست داریم با دستگیره اش می سنجیم؛ در حالت
      // پنجره CLI، فرایند فرزند آن پنجره است و با نامش پیدا می شود.
      final bool alive = _coreProcesses.isNotEmpty
          ? true
          : await _native.isRunning(plan.primaryBinary);
      if (!alive && plan.readinessPort <= 0) {
        // در حالت تونل، ممکن است هسته هنوز کارت شبکه را نساخته باشد؛ کارت
        // شبکه خودش نشانه زنده بودن است.
        final TunnelStats probe =
            await _native.tunnelStats(hint: plan.tunnelHint);
        if (probe.available) {
          return true;
        }
      }
      if (!alive) {
        return false;
      }
      if (plan.readinessPort > 0) {
        final int probe = await _native.tcpPing('127.0.0.1', plan.readinessPort);
        if (probe >= 0) {
          return true;
        }
      } else {
        // کارت شبکه تونل، همان چیزی که هسته در اولین ثانیه می سازد
        // (`inbound/tun[tun-in]: started at tun0`). اینجا فقط «ساخته شد یا
        // نه» سنجیده می شود؛ عبور ترافیک کار سنجش بعدی است.
        final TunnelStats stats =
            await _native.tunnelStats(hint: plan.tunnelHint);
        if (stats.available) {
          return true;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 35));
    }
    return false;
  }

  /// جابه جایی بدون قطع اتصال داخل خود هسته در حال اجرا.
  ///
  /// وقتی سرور فعلی در میانه کار کند یا مسدود شود، به جای بستن کل هسته و قطع
  /// کارت شبکه تونل، از رابط محلی هسته می خواهیم تاخیر خروجی فعال و گروه
  /// انتخاب را بازسنجی کند تا بالانسر در کسری از ثانیه به گره سالم بعدی برود.
  Future<void> _nudgeCoreFailover() async {
    final CoreProxySnapshot snapshot = await ClashApi.status(
      timeout: const Duration(milliseconds: 1200),
    );
    if (!snapshot.reachable) {
      return;
    }
    if (snapshot.activeTag.isNotEmpty) {
      await ClashApi.testDelay(
        snapshot.activeTag,
        timeout: const Duration(milliseconds: 3000),
      );
    }
    await ClashApi.testDelay(
      'select',
      timeout: const Duration(milliseconds: 3500),
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  bool _verifyInFlight = false;

  /// آیا ترافیک واقعاً از تونل **برگشت**؟
  ///
  /// فقط پاسخ HTTPS معتبر با گواهی درست و بدنه مورد انتظار از دست کم دو نشانی
  /// مستقل پذیرفته می شود.
  Future<bool> _trafficReturns({Duration timeout = const Duration(seconds: 8)}) async {
    final int port = _probeProxyPort;
    if (port == 0) {
      return VerifiedProbe.check(
        proxyPort: 0,
        minimumSuccesses: 2,
        timeout: timeout,
      );
    }
    final bool proxy = await VerifiedProbe.check(
      proxyPort: port,
      proxyUser: _probeProxyUser,
      proxyPassword: _probeProxyPassword,
      minimumSuccesses: 2,
      timeout: timeout,
    );
    return proxy &&
        (_proxyPort > 0 ||
            await VerifiedProbe.check(proxyPort: 0, timeout: timeout));
  }

  Future<void> _verifyTunnel({bool allowRetry = true}) async {
    if (_verifyInFlight || _status != VpnStatus.connected) {
      return;
    }
    _verifyInFlight = true;
    final int epoch = _connectionEpoch;
    try {
      final String previousExitIp = _exitIp;
      // ۱. اول بدون هیچ درخواست خارجی اضافه، آی پی و کشور خروجی را از پایش
      // داخلی خود هسته (Hiddify ipinfo) می خوانیم که با چرخش چند سرویس از دل
      // همان پروکسی فعال پر می شود.
      final CoreProxySnapshot snapshot = await ClashApi.status(
        since: _sessionStartUtc,
        timeout: const Duration(milliseconds: 900),
      );
      if (epoch != _connectionEpoch || _status != VpnStatus.connected) return;
      GeoInfo geo = GeoInfo.empty;
      final CoreExitIpInfo? coreIpInfo = snapshot.exitIpInfo;
      if (coreIpInfo != null && coreIpInfo.ip.isNotEmpty) {
        geo = GeoInfo.fromJson(coreIpInfo.toGeoJson());
      }
      if (PingService.plausible(snapshot.activeDelayMs) &&
          _livePing != snapshot.activeDelayMs) {
        _livePing = snapshot.activeDelayMs;
      }

      // ۲. اگر هسته هنوز جست وجوی ipinfo را تمام نکرده (در حالت زنجیره یا
      // ثانیه اول اتصال)، یک بار بعد از ۲ ثانیه دوباره از هسته می خوانیم و در
      // نوبت دوم در صورت خالی ماندن از سرویس وب پشتیبان از دل پروکسی محلی
      // می خوانیم.
      if (geo.ip.isEmpty && allowRetry && !_activeChain.enabled) {
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 1800), () async {
            if (!_disposed &&
                epoch == _connectionEpoch &&
                _status == VpnStatus.connected) {
              await _verifyTunnel(allowRetry: false);
            }
          }),
        );
        _notify();
        return;
      }
      if (geo.ip.isEmpty) {
        final int localProxy = _probeProxyPort;
        geo = await _ip.fetch(
          force: true,
          proxy: localProxy > 0 ? '127.0.0.1:$localProxy' : '',
          proxyUser: _probeProxyUser,
          proxyPassword: _probeProxyPassword,
        );
        if (epoch != _connectionEpoch || _status != VpnStatus.connected) return;
      }
      if (geo.ip.isEmpty && _activeCoreLogPath.isNotEmpty) {
        final String loggedIp = await _coreExitIp(_activeCoreLogPath);
        if (epoch != _connectionEpoch || _status != VpnStatus.connected) return;
        if (loggedIp.isNotEmpty) {
          geo = GeoInfo.fromJson(<String, dynamic>{'ip': loggedIp});
        }
      }
      if (geo.ip.isNotEmpty) {
        _geo = geo;
        _exitIp = geo.ip;
      }
      final bool coreHealthy = !_activeChain.enabled &&
          snapshot.connectivity == CoreConnectivityState.started;
      // اگر آی پی خوانده نشد، این هیچ چیزی را درباره تونل ثابت نمی کند؛ سلامت
      // مسیر از خود هسته یا بازگشت واقعی ترافیک سنجیده می شود.
      if (geo.ip.isEmpty) {
        if (coreHealthy) {
          _tunnelVerified = true;
          _healthFailures = 0;
          _notify();
          return;
        }
        bool alive = await _trafficReturns();
        if (epoch != _connectionEpoch || _status != VpnStatus.connected) return;
        if (!alive && !_singleNodeSession) {
          await _nudgeCoreFailover();
          if (epoch != _connectionEpoch || _status != VpnStatus.connected) return;
          alive = await _trafficReturns();
          if (epoch != _connectionEpoch || _status != VpnStatus.connected) return;
        }
        if (alive) {
          _tunnelVerified = true;
          _healthFailures = 0;
          _notify();
          return;
        }
        _tunnelVerified = false;
        _healthFailures++;
        _log.add(
          'سنجش دوره ای آی پی و ترافیک پاسخ نگرفت؛ پایش سلامت در حال جابه جایی '
          'خودکار مسیر است.',
          level: 'warning',
        );
        _notify();
        return;
      }
      final bool fromCoreMonitor =
          coreIpInfo != null && coreIpInfo.ip.isNotEmpty && geo.ip == coreIpInfo.ip;
      // اگر پایش خود هسته کشور خارجی را تایید کرده ولی `_realIp` با آن برابر
      // است، یعنی `_realIp` قبلاً هنگام فعال بودن فیلترشکن دیگری ثبت شده بوده؛
      // آن را پاک می کنیم تا معیار اشتباه باقی نماند.
      if (fromCoreMonitor &&
          geo.flagCode.isNotEmpty &&
          geo.flagCode.toLowerCase() != 'ir' &&
          _realIp == geo.ip) {
        _realIp = '';
        _realCountryCode = '';
      }
      final bool untunneled = isUntunneledExitIp(
        exitIp: geo.ip,
        exitCountryCode: geo.flagCode,
        realIp: _realIp,
        realCountryCode: _realCountryCode,
        fromCoreMonitor: fromCoreMonitor,
      );
      final bool ipChanged = !untunneled;
      bool passes = coreHealthy;
      if (!passes && ipChanged) {
        passes = await _trafficReturns();
        if (epoch != _connectionEpoch || _status != VpnStatus.connected) return;
        if (!passes && !_singleNodeSession) {
          await _nudgeCoreFailover();
          if (epoch != _connectionEpoch || _status != VpnStatus.connected) return;
          passes = await _trafficReturns();
          if (epoch != _connectionEpoch || _status != VpnStatus.connected) return;
        }
      }
      _tunnelVerified = ipChanged && passes;
      if (!ipChanged) {
        // هرگز تونل سالم را صرفاً به خاطر یک پاسخ آی پی قطع و راه اندازی مجدد
        // نکن: ابتدا از بالانسر داخلی هسته بخواه بدون قطع تونل گره را بازسنجی
        // کند، و اگر هسته یا ترافیک واقعی سالم است اتصال را برقرار نگه دار.
        if (!_singleNodeSession && _settings.autoFailover) {
          await _nudgeCoreFailover();
          if (epoch != _connectionEpoch || _status != VpnStatus.connected) return;
        }
        final bool flows = coreHealthy || await _trafficReturns();
        if (epoch != _connectionEpoch || _status != VpnStatus.connected) return;
        if (flows) {
          _tunnelVerified = true;
          _healthFailures = 0;
          if (_sameIpWarnedEpoch != epoch) {
            _sameIpWarnedEpoch = epoch;
            _log.add(
              'سرویس تشخیص آی پی نشانی قبلی را برگرداند اما مسیر امن هسته فعال و برقرار است.',
              level: 'info',
            );
          }
          _notify();
          return;
        }
        if (_sameIpWarnedEpoch != epoch) {
          _sameIpWarnedEpoch = epoch;
          _log.add(
            'آی پی خروجی با آی پی قبلی یکسان است و ترافیک از تونل عبور نکرد.',
            level: 'warning',
          );
        }
        _notify();
        if (!_singleNodeSession && _activeNode != null) {
          _balancer.markFailed(_activeNode!.id);
        }
        if (_settings.autoFailover && _reconnectAttempts < 5) {
          _reconnectAttempts++;
          _verifyInFlight = false;
          await _reconnect();
        } else {
          _healthFailures++;
        }
        return;
      }
      if (!passes) {
        _healthFailures++;
        _log.add(
          'سنجش کمکی مسیر موقتاً کند بود؛ پایش سلامت ادامه دارد.',
          level: 'warning',
        );
        _notify();
        return;
      }
      _healthFailures = 0;
      _reconnectAttempts = 0;
      if (geo.ip != previousExitIp && previousExitIp.isNotEmpty) {
        _log.add('مسیر امن اتصال به روز شد.');
        if (_settings.notificationsEnabled) {
          final String where = countryNameFa(geo.flagCode);
          if (where.isNotEmpty) {
            unawaited(_tray.balloon('تغییر مسیر اتصال', 'موقعیت جدید: $where'));
          }
        }
      } else if (geo.ip != previousExitIp) {
        _log.add('مسیر امن اتصال تایید و فعال شد.');
      }
      _notify();
    } on Exception {
      _log.add('بررسی دوره ای سلامت مسیر موقتاً پاسخ نداد.', level: 'warning');
    } finally {
      _verifyInFlight = false;
    }
  }

  void _startTimers({int initialPingMs = 0}) {
    _startLiveMeasurement(initialPingMs: initialPingMs);
    _startCoreBlockLogMonitor();
    _statsClock
      ..reset()
      ..start();
    _lastStatsSample = null;
    _lastTraySpeedUpdate = null;
    _scheduleStatsTimer();
    _healthTimer?.cancel();
    _healthTimer =
        Timer.periodic(const Duration(seconds: 8), (_) => _tickHealth());
    _ensureNetworkWatcherStarted();
    _ipTimer?.cancel();
    _ipTimer = Timer.periodic(const Duration(seconds: 120), (_) {
      unawaited(_verifyTunnel());
    });
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(
      Duration(seconds: _settings.pingIntervalSeconds.clamp(120, 3600)),
      (_) {
        // در حین اتصال عدد زنده از خود هسته خوانده می شود و نیازی به سنجش
        // جداگانه فهرست نیست.
        if (_status.active || _status.busy) {
          return;
        }
        unawaited(refreshPings(all: false, tunnelProbe: false));
      },
    );
  }

  void _scheduleStatsTimer() {
    _statsTimer?.cancel();
    final int seconds = !_appVisible
        ? (_batterySaving ? 20 : 12)
        : (_batterySaving ? 5 : 1);
    _statsTimer =
        Timer.periodic(Duration(seconds: seconds), (_) => _tickStats());
  }

  void _scheduleLiveTimer() {
    _liveTimer?.cancel();
    final int seconds = !_appVisible
        ? (_batterySaving ? 90 : 45)
        : (_batterySaving ? 30 : 10);
    _liveTimer = Timer.periodic(
        Duration(seconds: seconds), (_) => unawaited(_refreshLivePing()));
  }

  /// خواندن پینگ واقعی خروجی فعال: ابتدا بدون سربار شبکه از پایش داخلی خود
  /// هسته، و فقط در صورت نبود عدد، با یک درخواست سبک از پروکسی محلی.
  void _startLiveMeasurement({int initialPingMs = 0}) {
    _liveTimer?.cancel();
    _livePing = PingService.plausible(initialPingMs) ? initialPingMs : 0;
    _link?.close();
    _link = null;
    final int epoch = _connectionEpoch;
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 1500), () {
        if (!_disposed &&
            epoch == _connectionEpoch &&
            _status == VpnStatus.connected) {
          unawaited(_refreshLivePing());
        }
      }),
    );
    unawaited(
      Future<void>.delayed(const Duration(seconds: 4), () {
        if (!_disposed &&
            epoch == _connectionEpoch &&
            _status == VpnStatus.connected) {
          unawaited(_refreshLivePing());
        }
      }),
    );
    _scheduleLiveTimer();
  }

  Future<void> _refreshLivePing() async {
    if (_status != VpnStatus.connected || _disposed) {
      return;
    }
    final CoreProxySnapshot snapshot = await ClashApi.status(
      since: _sessionStartUtc,
      timeout: const Duration(milliseconds: 900),
    );
    if (_status != VpnStatus.connected || _disposed) {
      return;
    }
    bool changed = false;
    final int delay = PingService.plausible(snapshot.activeDelayMs)
        ? snapshot.activeDelayMs
        : (PingService.plausible(snapshot.bestDelayMs)
            ? snapshot.bestDelayMs
            : 0);
    if (delay > 0 && _livePing != delay) {
      _livePing = delay;
      changed = true;
    }
    // وقتی خود هسته روی گره سریع تر سوییچ کرد، آی پی خروجی جدیدش بدون درخواست
    // اضافه در رابط کاربری هم به روز می شود.
    final CoreExitIpInfo? coreIp = snapshot.exitIpInfo;
    if (!_activeChain.enabled &&
        coreIp != null &&
        coreIp.ip.isNotEmpty &&
        coreIp.countryCode.toLowerCase() != 'ir' &&
        coreIp.ip != _exitIp) {
      if (_realIp == coreIp.ip && coreIp.countryCode.isNotEmpty) {
        _realIp = '';
        _realCountryCode = '';
      }
      _geo = GeoInfo.fromJson(coreIp.toGeoJson());
      _exitIp = coreIp.ip;
      changed = true;
    }
    if (changed) {
      _notify();
    }
    if (delay > 0) {
      return;
    }
    if (_proxyPort > 0) {
      await _measureLiveLink();
    } else {
      await _measureLiveTunnel();
    }
  }

  Future<void> _measureLiveLink() async {
    if (!_status.active) {
      return;
    }
    ProxyLink? link = _link;
    if (link == null || !link.alive) {
      link = await TunnelProbe.openLink(_proxyPort);
      _link = link;
    }
    if (link == null) {
      return;
    }
    final int ms = await link.fetch(TunnelProbe.probeUrl);
    if (ms > 0) {
      _livePing = ms;
      _notify();
    }
  }

  Future<void> _measureLiveTunnel() async {
    if (!_status.active) {
      return;
    }
    final int ms = await TunnelProbe.latency(
      proxyPort: _probeProxyPort,
      proxyUser: _probeProxyUser,
      proxyPassword: _probeProxyPassword,
      timeout: const Duration(seconds: 4),
    );
    if (ms > 0) {
      _livePing = ms;
      _notify();
    }
  }

  /// سنجش سرعت واقعی روی سرور متصل؛ از همان مسیری می رود که ترافیک کاربر
  /// می رود (تونل کامل یا پروکسی محلی).
  Future<void> measureSpeed() async {
    if (_status != VpnStatus.connected ||
        _speedRunner != null ||
        (accessGuard?.call() ?? '').isNotEmpty) {
      return;
    }
    final SpeedTestRunner runner = SpeedTestRunner();
    _speedRunner = runner;
    _speedResult = null;
    _speedError = '';
    _liveSpeed = 0;
    _speedMeasuredAt = null;
    _notify();
    try {
      final int speedPort = _probeProxyPort;
      final SpeedTestResult result = await runner.run(
        proxyPort: speedPort,
        proxyUser: _probeProxyUser,
        proxyPassword: _probeProxyPassword,
        allowDirectTunnel: speedPort == 0 && _activePlanTun,
        onPhase: (String phase) { _speedPhase = phase; _notify(); },
      );
      if (identical(_speedRunner, runner) && _status == VpnStatus.connected &&
          (accessGuard?.call() ?? '').isEmpty) {
        _speedResult = result;
        _liveSpeed = result.download.bytesPerSecond;
        _speedMeasuredAt = result.measuredAt;
      }
    } on SpeedTestCancelled {
      // Explicit cancellation or a connection transition: never publish a result.
    } catch (_) {
      if (identical(_speedRunner, runner)) {
        _speedError = 'سنجش کامل نشد؛ مسیر یا سرویس آزمایش پاسخ معتبر نداد.';
      }
    } finally {
      runner.cancel();
      if (identical(_speedRunner, runner)) { _speedRunner = null; _speedPhase = ''; }
      _notify();
    }
  }

  void cancelSpeedTest() {
    _speedRunner?.cancel();
    _speedRunner = null;
    _speedPhase = '';
    _notify();
  }

  void _stopLiveMeasurement() {
    cancelSpeedTest();
    _speedResult = null;
    _speedError = '';
    _liveTimer?.cancel();
    _liveTimer = null;
    _link?.close();
    _link = null;
    _livePing = 0;
    _sessionStartUtc = null;
    _liveSpeed = 0;
    _speedMeasuredAt = null;
  }

  bool _statsInFlight = false;
  DateTime? _lastActivitySample;

  Future<void> _sampleActivityIfDue({bool force = false}) async {
    final DateTime now = DateTime.now();
    if (!force &&
        _lastActivitySample != null &&
        now.difference(_lastActivitySample!) < const Duration(seconds: 6)) {
      return;
    }
    _lastActivitySample = now;
    try {
      final List<CoreActivitySample> samples = await ClashApi.activeConnections(
        timeout: Duration(milliseconds: force ? 300 : 650),
      );
      if (samples.isNotEmpty) {
        if (!force && _native.available) {
          final List<String> missing = samples
              .map((CoreActivitySample s) => s.process)
              .where((String p) =>
                  p.isNotEmpty && !_resolvedProcessLabels.containsKey(p))
              .toSet()
              .take(16)
              .toList(growable: false);
          if (missing.isNotEmpty) {
            final Map<String, String> resolved = await _native
                .resolveProcessLabels(missing)
                .timeout(
                  const Duration(milliseconds: 350),
                  onTimeout: () => const <String, String>{},
                );
            if (_resolvedProcessLabels.length > 256) {
              _resolvedProcessLabels.clear();
            }
            for (final String p in missing) {
              final String? label = resolved[p] ?? resolved[p.toLowerCase()];
              if (label != null && label.trim().isNotEmpty) {
                _resolvedProcessLabels[p] = label.trim();
                _resolvedProcessLabels[p.toLowerCase()] = label.trim();
              } else {
                _resolvedProcessLabels[p] = '';
              }
            }
          }
        }
        ActivityMonitorBuffer.instance.recordConnections(
          samples,
          resolvedLabels: _resolvedProcessLabels,
        );
        if (onNetworkConnectionsObserved != null) {
          unawaited(onNetworkConnectionsObserved!(samples));
        }
      }
    } catch (_) {}
  }

  Future<void> _tickStats() async {
    if (!_status.active || _statsInFlight) {
      return;
    }
    _statsInFlight = true;
    try {
      TunnelStats raw = _proxyPort > 0
          ? TunnelStats.empty
          : await _native.tunnelStats(hint: AppConfig.tunAdapterHint);
      if (!raw.available) {
        final CoreTrafficTotals? clash = await ClashApi.trafficTotals(
          timeout: const Duration(milliseconds: 700),
        );
        if (clash != null) {
          raw = TunnelStats(
            rx: clash.rxBytes,
            tx: clash.txBytes,
            available: true,
            adapter: _proxyPort > 0 ? 'SystemProxy' : 'Core',
          );
        }
      }
      if (!_status.active) {
        return;
      }
      final Duration now = _statsClock.elapsed;
      final Duration elapsed = _lastStatsSample == null
          ? Duration.zero : now - _lastStatsSample!;
      final bool hadPrevious = raw.available &&
          _stats.available && _stats.adapter == raw.adapter;
      _lastStatsSample = raw.available ? now : null;
      final int downDelta = hadPrevious ? raw.rx - _stats.rx : 0;
      final int upDelta = hadPrevious ? raw.tx - _stats.tx : 0;
      _stats = _stats.copyWith(
        rx: raw.rx,
        tx: raw.tx,
        available: raw.available,
        adapter: raw.adapter,
        downSpeed: trafficBytesPerSecond(downDelta, elapsed),
        upSpeed: trafficBytesPerSecond(upDelta, elapsed),
        connectedFor: _connectedAt == null
            ? Duration.zero
            : DateTime.now().difference(_connectedAt!),
      );
      if (_settings.showSpeedInTray && _connectedAt != null) {
        if (_lastTraySpeedUpdate == null ||
            now - _lastTraySpeedUpdate! >= const Duration(seconds: 5)) {
          _lastTraySpeedUpdate = now;
          await _tray.update(
            state: 'connected',
            tooltip:
                '${AppConfig.appName} - ${Fa.speed(_stats.downSpeed)} / ${Fa.speed(_stats.upSpeed)}',
            connected: true,
          );
        }
      }
      await _sampleActivityIfDue();
      _notify();
    } finally {
      _statsInFlight = false;
    }
  }

  Future<void> _tickHealth() async {
    if (_healthInFlight || _status != VpnStatus.connected) return;
    _healthInFlight = true;
    try { await _tickHealthInner(); } finally { _healthInFlight = false; }
  }

  Future<void> _tickHealthInner() async {
    final int epoch = _connectionEpoch;
    if (!_status.active) {
      return;
    }
    final VpnNode? node = _activeNode;
    if (node == null) {
      return;
    }
    final bool alive = _coreProcesses.isNotEmpty ||
        (_runningBinaries.isEmpty
            ? true
            : await _native.isRunning(_runningBinaries.first));
    if (epoch != _connectionEpoch || _status != VpnStatus.connected) return;
    if (!alive) {
      final ({bool online, String adapter, String ip, String fingerprint})?
          netState = await _native.networkState();
      if (epoch != _connectionEpoch || _status != VpnStatus.connected) return;
      if (netState != null && !netState.online) {
        await _enterWaitingForNetwork();
        return;
      }
      _log.add('هسته اتصال متوقف شد؛ تلاش برای بازیابی فوری...', level: 'warning');
      if (!_singleNodeSession) {
        _balancer.markFailed(node.id);
      }
      if (_settings.autoFailover && _reconnectAttempts < 5) {
        _reconnectAttempts++;
        await _reconnect();
      } else {
        await _failAndCleanup('هسته اتصال به صورت غیرمنتظره متوقف شد.');
      }
      return;
    }

    // زنده بودن فرایند کافی نیست؛ خود تونل هم باید پاسخ HTTPS معتبر بدهد.
    // اگر سرور فعال افت کرده باشد، ابتدا از خود هسته خواسته می شود بدون قطع
    // تونل روی گره سالم بعدی سوییچ کند، و فقط در صورت شکست پیاپی بازاتصال کامل
    // انجام می شود.
    bool flows = await _tunnelFlowsNow();
    if (epoch != _connectionEpoch || _status != VpnStatus.connected) return;
    if (!flows && !_singleNodeSession && _settings.autoFailover) {
      await _nudgeCoreFailover();
      if (epoch != _connectionEpoch || _status != VpnStatus.connected) return;
      flows = await _tunnelFlowsNow();
      if (epoch != _connectionEpoch || _status != VpnStatus.connected) return;
      if (flows) {
        _log.add('سرور فعال کند شد؛ هسته بدون قطع اتصال به مسیر سالم بعدی جابه جا شد.');
        unawaited(_refreshLivePing());
      }
    }
    if (flows) {
      if (_healthFailures > 0) {
        _log.add('تونل دوباره سالم شد.');
      }
      _healthFailures = 0;
      if (_reconnectAttempts > 0 &&
          _connectedAt != null &&
          DateTime.now().difference(_connectedAt!) >=
              const Duration(seconds: 30)) {
        _reconnectAttempts = 0;
      }
      if (!_tunnelVerified) {
        _tunnelVerified = true;
        _notify();
      }
      return;
    }

    final ({bool online, String adapter, String ip, String fingerprint})?
        netState = await _native.networkState();
    if (epoch != _connectionEpoch || _status != VpnStatus.connected) return;
    if (netState != null && !netState.online) {
      await _enterWaitingForNetwork();
      return;
    }

    _healthFailures++;
    _tunnelVerified = false;
    _log.add(
      'ترافیک از تونل رد نمی شود؛ بررسی سلامت ناموفق بود '
      '(${Fa.num(_healthFailures)} از ۲).',
      level: 'warning',
    );
    _notify();
    if (_healthFailures >= 2) {
      if (!_singleNodeSession) {
        _balancer.markFailed(node.id);
      }
      if (_settings.autoFailover && _reconnectAttempts < 5) {
        _reconnectAttempts++;
        await _reconnect();
      } else {
        await _failAndCleanup('اتصال پایدار نماند؛ دوباره تلاش کنید.');
      }
    }
  }

  void _ensureNetworkWatcherStarted() {
    if (_disposed || _shuttingDown) return;
    if (_networkWatchTimer != null && _networkWatchTimer!.isActive) return;
    _networkWatchTimer = Timer.periodic(
      const Duration(milliseconds: 2500),
      (_) => unawaited(_pollNetworkState()),
    );
  }

  void _stopNetworkWatcher() {
    _networkWatchTimer?.cancel();
    _networkWatchTimer = null;
  }

  Future<void> _pollNetworkState() async {
    if (_disposed ||
        _shuttingDown ||
        _networkProbeInFlight ||
        (!_waitingForNetwork && !_status.active && !_status.busy)) {
      return;
    }
    _networkProbeInFlight = true;
    try {
      final ({bool online, String adapter, String ip, String fingerprint})?
          state = await _native.networkState();
      if (state == null || _disposed || _shuttingDown) return;
      _onNetworkStateChanged(state.online, state.fingerprint);
    } finally {
      _networkProbeInFlight = false;
    }
  }

  void _onNetworkStateChanged(bool online, String fingerprint) {
    if (_disposed || _shuttingDown) return;
    if (!online) {
      _lastNetworkOnline = false;
      if (_status == VpnStatus.connected && !_waitingForNetwork) {
        unawaited(_enterWaitingForNetwork());
      }
      return;
    }
    final bool wasOffline = !_lastNetworkOnline;
    final bool interfaceChanged = _lastNetworkFingerprint.isNotEmpty &&
        fingerprint.isNotEmpty &&
        fingerprint != _lastNetworkFingerprint;
    _lastNetworkOnline = true;
    _lastNetworkFingerprint = fingerprint;

    if (_waitingForNetwork && !_connectInFlight) {
      _waitingForNetwork = false;
      _stopNetworkWatcher();
      _reconnectAttempts = 0;
      _log.add('اینترنت دستگاه برقرار شد؛ اتصال خودکار مجدد به آمبرلا...');
      unawaited(_resumeAfterNetworkRestore());
      return;
    }

    if (!wasOffline &&
        interfaceChanged &&
        _status == VpnStatus.connected &&
        !_connectInFlight &&
        !_healthInFlight) {
      final int epoch = _connectionEpoch;
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 1200), () async {
          if (_disposed ||
              _shuttingDown ||
              epoch != _connectionEpoch ||
              _status != VpnStatus.connected) {
            return;
          }
          final bool flows = await _tunnelFlowsNow();
          if (!flows &&
              epoch == _connectionEpoch &&
              _status == VpnStatus.connected &&
              _settings.autoFailover) {
            _log.add('شبکه دستگاه تغییر کرد؛ بازیابی سریع مسیر امن...');
            _reconnectAttempts = 1;
            await _reconnect();
          }
        }),
      );
    }
  }

  Future<void> _enterWaitingForNetwork() async {
    if (_disposed || _shuttingDown || _waitingForNetwork) return;
    _waitingForNetwork = true;
    _lastNetworkOnline = false;
    _statsTimer?.cancel();
    _healthTimer?.cancel();
    _ipTimer?.cancel();
    _stopLiveMeasurement();
    _connectedAt = null;
    _activeCoreLogPath = '';
    _stats = TunnelStats.empty;
    _tunnelVerified = false;
    _setStatus(
      VpnStatus.reconnecting,
      'اتصال اینترنت قطع شد؛ در انتظار برقراری مجدد...',
    );
    _log.add(
      'اتصال اینترنت دستگاه قطع شد؛ به محض برقراری شبکه اتصال به صورت خودکار ادامه می یابد.',
      level: 'warning',
    );
    await _stopCoreBlockLogMonitor();
    await _stopCores();
    await _disableProxy();
    _ensureNetworkWatcherStarted();
  }

  Future<void> _resumeAfterNetworkRestore() async {
    final int generation = _cancelGeneration;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (_disposed ||
        _shuttingDown ||
        generation != _cancelGeneration ||
        _connectInFlight ||
        _status == VpnStatus.connected) {
      return;
    }
    _status = VpnStatus.disconnected;
    final ConnectOutcome outcome = await connect(
      requested: _requestedNode,
      isAutoReconnect: true,
      emergency: _emergencySession,
    );
    if (!outcome.ok && !outcome.cancelled && !_waitingForNetwork) {
      await _failAndCleanup(outcome.message);
    }
  }

  Future<void> _reconnect() async {
    final int generation = _cancelGeneration;
    _statsTimer?.cancel();
    _healthTimer?.cancel();
    _ipTimer?.cancel();
    _stopLiveMeasurement();
    _connectedAt = null;
    _activeCoreLogPath = '';
    _stats = TunnelStats.empty;
    _setStatus(VpnStatus.reconnecting, 'اتصال دوباره...');
    await _stopCores();
    await _disableProxy();
    final ({bool online, String adapter, String ip, String fingerprint})?
        netState = await _native.networkState();
    if (netState != null && !netState.online) {
      await _enterWaitingForNetwork();
      return;
    }
    final int backoffMs =
        (1000 * _reconnectAttempts.clamp(1, 5)).clamp(1000, 10000);
    await Future<void>.delayed(Duration(milliseconds: backoffMs));
    if (_disposed || _shuttingDown || generation != _cancelGeneration) return;
    final ({bool online, String adapter, String ip, String fingerprint})?
        postWaitNet = await _native.networkState();
    if (_disposed || _shuttingDown || generation != _cancelGeneration) return;
    if (postWaitNet != null && !postWaitNet.online) {
      await _enterWaitingForNetwork();
      return;
    }
    _status = VpnStatus.disconnected;
    final ConnectOutcome outcome = await connect(
      requested: _requestedNode,
      isAutoReconnect: true,
      emergency: _emergencySession,
    );
    if (!outcome.ok && !outcome.cancelled && !_waitingForNetwork) {
      final ({bool online, String adapter, String ip, String fingerprint})?
          afterNet = await _native.networkState();
      if (afterNet != null && !afterNet.online) {
        await _enterWaitingForNetwork();
        return;
      }
      await _failAndCleanup(outcome.message);
    }
  }

  /// جابه جایی به یک سرور مشخص (انتخاب دستی کاربر).
  Future<ConnectOutcome> switchTo(VpnNode node) async {
    if (_status.busy) {
      return const ConnectOutcome(
        ok: false,
        message: 'برنامه در حال اتصال است؛ چند لحظه صبر کنید.',
      );
    }
    if (!_status.active) {
      return connect(requested: node);
    }
    final int generation = _cancelGeneration;
    _setStatus(VpnStatus.switching, 'در حال جابه جایی مسیر اتصال...');
    await _stopCores();
    await _disableProxy();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (_disposed || generation != _cancelGeneration) {
      return const ConnectOutcome(ok: false, cancelled: true, message: 'اتصال لغو شد.');
    }
    _status = VpnStatus.disconnected;
    final ConnectOutcome outcome = await connect(requested: node);
    if (!outcome.ok && !outcome.cancelled) {
      await _failAndCleanup(outcome.message);
    }
    return outcome;
  }

  ContentBlockServer? _blockServer;
  WebSocket? _coreLogsSocket;
  StreamSubscription<dynamic>? _coreLogsSub;
  bool _blockLaunchInFlight = false;
  DateTime? _lastAnyBlockLaunch;
  final Map<String, DateTime> _recentBlockLaunches = <String, DateTime>{};
  final Map<String, DateTime> _recentDirect403Hosts = <String, DateTime>{};
  final Map<String, DateTime> _recentMaliciousAlertHosts = <String, DateTime>{};
  final Map<String, String> _recentLogConnHosts = <String, String>{};

  static const Duration _blockHostCooldown = Duration(seconds: 45);
  static const Duration _blockBurstCooldown = Duration(seconds: 12);
  static const Duration _directHttp403Cooldown = Duration(seconds: 20);

  int get contentBlockUiPort => _blockServer?.uiPort ?? 0;
  int get contentBlockProxyPort => _blockServer?.proxyPort ?? 0;

  LocalCaManager? _httpsCaManager;
  HttpsAdFilterProxy? _httpsFilterProxy;
  int _httpsFilterEgressPort = 0;
  String _httpsFilterSecret = '';
  bool _httpsCaTrusted = false;
  bool _httpsCaStatusChecked = false;
  HttpsFilterStats _httpsFilterStats = const HttpsFilterStats();
  Timer? _httpsStatsNotifyTimer;

  bool get httpsCaTrusted => _httpsCaTrusted;
  bool get httpsCaStatusChecked => _httpsCaStatusChecked;
  String get httpsCaCertPath => _httpsCaManager?.certPath ?? '';
  HttpsFilterStats get httpsFilterStats => _httpsFilterStats;
  bool get isHttpsFilterProxyActive => _httpsFilterProxy?.isRunning ?? false;

  String get _httpsCaStorageDir {
    final String base = _provisioner.dataDir.trim();
    if (base.isNotEmpty) {
      return '$base${Platform.pathSeparator}ca';
    }
    return '${Directory.systemTemp.path}${Platform.pathSeparator}umbrella-ca';
  }

  Future<LocalCaManager> _ensureCaInitialized() async {
    final LocalCaManager manager =
        _httpsCaManager ??= LocalCaManager(storageDir: _httpsCaStorageDir);
    await manager.ensureInitialized();
    return manager;
  }

  Future<bool> refreshHttpsCaStatus({bool notify = true}) async {
    try {
      final LocalCaManager ca = await _ensureCaInitialized();
      final bool trusted = _native.available
          ? await _native.isHttpsCaTrusted(sha1Hex: ca.caSha1Hex)
          : false;
      _httpsCaTrusted = trusted;
      _httpsCaStatusChecked = true;
      if (notify) {
        _notify();
      }
      return trusted;
    } catch (_) {
      _httpsCaTrusted = false;
      _httpsCaStatusChecked = true;
      if (notify) {
        _notify();
      }
      return false;
    }
  }

  Future<({bool ok, bool needsManualConfirm, String message})> installHttpsCa() async {
    final LocalCaManager ca = await _ensureCaInitialized();
    final ({bool ok, bool needsManualConfirm, String message}) res =
        await _native.installHttpsCa(
      certPath: ca.certPath,
      certPem: ca.caCertPem,
    );
    await refreshHttpsCaStatus();
    if (_httpsCaTrusted && _settings.httpsAdFilter && _status.active) {
      scheduleLiveReload();
    }
    return res;
  }

  Future<({bool ok, String message})> removeHttpsCa() async {
    final LocalCaManager ca = await _ensureCaInitialized();
    final bool removed = await _native.removeHttpsCa(
      sha1Hex: ca.caSha1Hex,
    );
    await refreshHttpsCaStatus();
    if (!_httpsCaTrusted && _settings.httpsAdFilter && _status.active) {
      scheduleLiveReload();
    }
    final bool ok = removed || !_httpsCaTrusted;
    return (
      ok: ok,
      message: ok
          ? 'گواهی محلی آمبرلا از مخزن ویندوز حذف شد.'
          : 'حذف گواهی از مخزن ویندوز لغو شد یا ناموفق بود.',
    );
  }

  static String _generateSessionSecret() {
    final Random rng = Random.secure();
    const String alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List<String>.generate(
      24,
      (_) => alphabet[rng.nextInt(alphabet.length)],
    ).join();
  }

  static Future<int> _reserveFreeLoopbackPort() async {
    final ServerSocket sock =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final int port = sock.port;
    await sock.close();
    return port;
  }

  void _onHttpsFilterStats(HttpsFilterStats stats) {
    _httpsFilterStats = stats;
    if (_httpsStatsNotifyTimer != null) {
      return;
    }
    _httpsStatsNotifyTimer = Timer(const Duration(milliseconds: 800), () {
      _httpsStatsNotifyTimer = null;
      if (!_disposed && !_shuttingDown) {
        _notify();
      }
    });
  }

  Future<({int? filterPort, int? egressPort, String secret, bool broadMode})>
      _prepareHttpsFilterForSession() async {
    final bool broad = _settings.httpsAdFilterMode == 'broad';
    if (!_settings.blockAds || !_settings.httpsAdFilter || _disposed || _shuttingDown) {
      await _stopHttpsFilterProxy();
      return (filterPort: null, egressPort: null, secret: '', broadMode: broad);
    }

    final bool trusted = await refreshHttpsCaStatus(notify: false);
    if (!trusted) {
      await _stopHttpsFilterProxy();
      _log.add(
        'فیلتر عمیق HTTPS به دلیل نصب نبودن گواهی محلی روی ویندوز متوقف ماند تا مرورگرها خطای گواهی ندهند.',
        level: 'warning',
      );
      return (filterPort: null, egressPort: null, secret: '', broadMode: broad);
    }

    try {
      final LocalCaManager ca = await _ensureCaInitialized();
      if (_httpsFilterEgressPort <= 0) {
        _httpsFilterEgressPort = await _reserveFreeLoopbackPort();
      }
      if (_httpsFilterSecret.isEmpty) {
        _httpsFilterSecret = _generateSessionSecret();
      }
      final HttpsAdFilterProxy proxy = _httpsFilterProxy ??= HttpsAdFilterProxy(
        caManager: ca,
        broadMode: broad,
        egressPort: _httpsFilterEgressPort,
        egressUsername: 'umbrella',
        egressSecret: _httpsFilterSecret,
        onStatsChanged: _onHttpsFilterStats,
        onLog: (String msg, {String level = 'info'}) =>
            _log.add('[HTTPS-Filter] $msg', level: level),
      );
      proxy.updateRoutingConfig(
        broadMode: broad,
        egressPort: _httpsFilterEgressPort,
        egressUsername: 'umbrella',
        egressSecret: _httpsFilterSecret,
      );
      await proxy.start();
      _httpsFilterStats = proxy.stats;
      return (
        filterPort: proxy.proxyPort,
        egressPort: _httpsFilterEgressPort,
        secret: _httpsFilterSecret,
        broadMode: broad,
      );
    } catch (error) {
      await _stopHttpsFilterProxy();
      _log.add(
        'راه اندازی موتور فیلتر عمیق HTTPS ممکن نشد: $error',
        level: 'warning',
      );
      return (filterPort: null, egressPort: null, secret: '', broadMode: broad);
    }
  }

  Future<void> _stopHttpsFilterProxy() async {
    _httpsFilterEgressPort = 0;
    _httpsFilterSecret = '';
    _httpsStatsNotifyTimer?.cancel();
    _httpsStatsNotifyTimer = null;
    try {
      await _httpsFilterProxy?.stop();
    } catch (_) {}
  }

  static String _throttleHostKey(String host) {
    final String clean = ContentBlockServer.sanitizeHost(host);
    if (clean.isEmpty ||
        clean.contains(':') ||
        RegExp(r'^\d+(?:\.\d+)+$').hasMatch(clean)) {
      return clean;
    }
    final List<String> parts = clean
        .split('.')
        .where((String p) => p.isNotEmpty)
        .toList(growable: false);
    if (parts.length <= 2) {
      return clean;
    }
    const Set<String> multiPartTlds = <String>{
      'co.uk',
      'org.uk',
      'ac.uk',
      'gov.uk',
      'co.ir',
      'ac.ir',
      'org.ir',
      'net.ir',
      'gov.ir',
      'com.tr',
      'com.au',
      'com.br',
      'co.jp',
      'co.kr',
    };
    final String tail2 = '${parts[parts.length - 2]}.${parts.last}';
    if (multiPartTlds.contains(tail2) && parts.length >= 3) {
      return '${parts[parts.length - 3]}.$tail2';
    }
    return tail2;
  }

  bool _isDirect403Recent(String host) {
    final String key = _throttleHostKey(host);
    if (key.isEmpty) return false;
    final DateTime? at = _recentDirect403Hosts[key];
    return at != null && DateTime.now().difference(at) < _directHttp403Cooldown;
  }

  void _recordDirect403(String host) {
    final String key = _throttleHostKey(host);
    if (key.isEmpty) return;
    _recentDirect403Hosts[key] = DateTime.now();
    if (_recentDirect403Hosts.length > 64) {
      _recentDirect403Hosts.remove(_recentDirect403Hosts.keys.first);
    }
  }

  void _notifyBlockedMaliciousHost(String host, String category) {
    final String key = _throttleHostKey(host);
    if (key.isEmpty) return;
    final DateTime now = DateTime.now();
    final DateTime? last = _recentMaliciousAlertHosts[key];
    if (last != null && now.difference(last) < _blockHostCooldown) {
      return;
    }
    _recentMaliciousAlertHosts[key] = now;
    if (_recentMaliciousAlertHosts.length > 64) {
      _recentMaliciousAlertHosts.remove(_recentMaliciousAlertHosts.keys.first);
    }
    unawaited(
      onBlockedMaliciousHost?.call(host, category) ?? Future<void>.value(),
    );
  }

  void _clearBlockThrottleState() {
    _blockLaunchInFlight = false;
    _lastAnyBlockLaunch = null;
    _recentBlockLaunches.clear();
    _recentDirect403Hosts.clear();
    _recentMaliciousAlertHosts.clear();
  }

  @visibleForTesting
  void debugHandleInterceptedBlock(InterceptedBlockEvent event) {
    _handleInterceptedBlockEvent(event);
  }

  @visibleForTesting
  void debugProcessCoreLogLine(String rawLine) {
    final CoreLogEntry? entry = ClashApi.parseCoreLogLine(rawLine);
    if (entry != null) {
      _processCoreLogEntry(entry);
    }
  }

  Future<ContentBlockServer?> ensureBlockServerStarted() async {
    if (_disposed || _shuttingDown) return null;
    final ContentBlockServer? existing = _blockServer;
    if (existing != null && existing.isRunning) {
      return existing;
    }
    final ContentBlockServer server = existing ??
        ContentBlockServer(
          filterProvider: () => _contentFilter,
          onIntercepted: _handleInterceptedBlockEvent,
        );
    _blockServer = server;
    try {
      await server.start();
      return server;
    } catch (_) {
      return null;
    }
  }

  /// بازکردن پیش نمایش زنده صفحه مسدودی مرورگر از بخش کنترل محتوا.
  Future<bool> openBlockedPreviewPage({
    String sampleDomain = 'content-control.umbrella.vpn',
  }) async {
    final ContentBlockServer? server = await ensureBlockServerStarted();
    if (server == null || !server.isRunning) {
      return false;
    }
    final String firstCategory = _contentFilter.activeBotCategories
        .firstWhere((String c) => c != 'ads', orElse: () => 'content_control');
    final Uri uri = server.buildBlockedPageUri(
      sampleDomain,
      categoryHint: firstCategory,
      filter: _contentFilter,
    );
    return _launchBlockedPageUri(
      uri,
      title: 'سپر کنترل محتوای آمبرلا فعال است',
      body: 'پیش نمایش صفحه مسدودی مرورگر آمبرلا',
    );
  }

  void _handleInterceptedBlockEvent(InterceptedBlockEvent event) {
    if (_disposed || _shuttingDown) return;
    final BlockedHostDetails details = event.details;
    if (details.domain.isEmpty) return;

    if (details.isSecurityThreat) {
      _notifyBlockedMaliciousHost(details.domain, details.category);
    }

    // روی HTTP (پورت 80)، خود تب مرورگر پاسخ 403 با صفحه کامل آمبرلا را
    // دریافت کرده است و نیازی به باز کردن تب جدید نیست.
    if (!event.needsBrowserLaunch) {
      _recordDirect403(details.domain);
      return;
    }
    if (details.category == 'ads') {
      return;
    }

    unawaited(
      _openBlockedBrowserPage(
        details.domain,
        categoryHint: details.category,
      ),
    );
  }

  Future<void> _openBlockedBrowserPage(
    String host, {
    String? categoryHint,
  }) async {
    if (_disposed || _shuttingDown || _blockLaunchInFlight) return;
    final String clean = ContentBlockServer.sanitizeHost(host);
    if (clean.isEmpty || clean == '127.0.0.1' || clean == 'localhost') {
      return;
    }
    final String rootKey = _throttleHostKey(clean);
    if (_isDirect403Recent(clean)) {
      return;
    }
    final DateTime now = DateTime.now();
    final DateTime? lastForHost = _recentBlockLaunches[rootKey];
    if (lastForHost != null && now.difference(lastForHost) < _blockHostCooldown) {
      return;
    }
    if (_lastAnyBlockLaunch != null &&
        now.difference(_lastAnyBlockLaunch!) < _blockBurstCooldown) {
      return;
    }
    _blockLaunchInFlight = true;
    _recentBlockLaunches[rootKey] = now;
    _lastAnyBlockLaunch = now;
    if (_recentBlockLaunches.length > 64) {
      _recentBlockLaunches.remove(_recentBlockLaunches.keys.first);
    }

    try {
      final ContentBlockServer? server = await ensureBlockServerStarted();
      if (server == null || !server.isRunning || _disposed || _shuttingDown) {
        return;
      }
      final BlockedHostDetails details = ContentBlockServer.classifyBlockedHost(
        clean,
        filter: _contentFilter,
        categoryHint: categoryHint,
      );
      if (details.category == 'ads') {
        return;
      }
      final Uri uri = server.buildBlockedPageUri(
        clean,
        categoryHint: details.category,
        filter: _contentFilter,
      );
      final String title = details.isSecurityThreat
          ? 'لینک مخرب توسط سپر امنیتی آمبرلا مسدود شد'
          : 'سپر کنترل محتوای آمبرلا فعال است';
      final String body = '${details.domain} (${details.categoryLabel})';
      _log.add(
        'صفحه مسدودی آمبرلا برای $clean (${details.categoryLabel}) در مرورگر باز شد.',
        level: details.isSecurityThreat ? 'warning' : 'info',
      );
      await _launchBlockedPageUri(uri, title: title, body: body);
    } finally {
      _blockLaunchInFlight = false;
    }
  }

  Future<bool> _launchBlockedPageUri(
    Uri uri, {
    required String title,
    required String body,
  }) async {
    if (onLaunchBlockedPage != null) {
      try {
        return await onLaunchBlockedPage!(uri, title: title, body: body);
      } catch (_) {
        return false;
      }
    }
    try {
      return await SafeUrlLauncher.open(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  void _startCoreBlockLogMonitor() {
    unawaited(_stopCoreBlockLogMonitor());
    final int epoch = _connectionEpoch;
    final String logLevel = _contentFilter.hasActiveRules ? 'debug' : 'info';
    unawaited(() async {
      await ensureBlockServerStarted();
      final WebSocket? socket = await ClashApi.openLogsStream(
        level: logLevel,
        timeout: const Duration(seconds: 2),
      );
      if (socket == null) return;
      if (_disposed ||
          _shuttingDown ||
          epoch != _connectionEpoch ||
          _status != VpnStatus.connected) {
        try {
          await socket.close();
        } catch (_) {}
        return;
      }
      _coreLogsSocket = socket;
      _coreLogsSub = socket.listen(
        (dynamic raw) {
          if (_disposed || _shuttingDown || epoch != _connectionEpoch) return;
          if (raw is! String) return;
          final CoreLogEntry? entry = ClashApi.parseCoreLogLine(raw);
          if (entry == null) return;
          _processCoreLogEntry(entry);
        },
        onError: (_) {},
        onDone: () {
          _coreLogsSocket = null;
          _coreLogsSub = null;
        },
        cancelOnError: true,
      );
    }());
  }

  void _processCoreLogEntry(CoreLogEntry entry) {
    if (entry.host.isNotEmpty && entry.connectionTag.isNotEmpty) {
      _recentLogConnHosts[entry.connectionTag] =
          '${entry.host}|${entry.port}';
      if (_recentLogConnHosts.length > 128) {
        _recentLogConnHosts.remove(_recentLogConnHosts.keys.first);
      }
    }

    String host = entry.host;
    int port = entry.port;
    if (host.isEmpty && entry.connectionTag.isNotEmpty) {
      final String? stored = _recentLogConnHosts[entry.connectionTag];
      if (stored != null) {
        final List<String> parts = stored.split('|');
        host = parts.first;
        if (parts.length > 1) {
          port = int.tryParse(parts[1]) ?? 0;
        }
      }
    }
    if (host.isEmpty) return;

    final MaliciousLinkMatch? malicious = MaliciousLinkGuard.inspectHost(host);
    if (malicious != null) {
      _notifyBlockedMaliciousHost(host, 'malicious_link');
      if (entry.isBlockedEvent && port != 80 && !_isDirect403Recent(host)) {
        unawaited(_openBlockedBrowserPage(host, categoryHint: 'malicious_link'));
      }
      return;
    }

    if (!entry.isBlockedEvent) return;
    final String? matchedCategory =
        UmbrellaCore.matchesContentFilterCategory(_contentFilter, host) ??
            (entry.matchedRuleHint.isNotEmpty ? entry.matchedRuleHint : null);
    if (matchedCategory == 'ads') return;
    if (matchedCategory == null && !_contentFilter.hasActiveRules) return;

    // برای پورت 80 HTTP در ویندوز پاسخ HTML مستقیم در همان تب فرستاده شده است.
    if ((port == 80 && !entry.isDnsRejection) || _isDirect403Recent(host)) {
      return;
    }
    unawaited(_openBlockedBrowserPage(host, categoryHint: matchedCategory));
  }

  Future<void> _stopCoreBlockLogMonitor() async {
    final StreamSubscription<dynamic>? sub = _coreLogsSub;
    final WebSocket? socket = _coreLogsSocket;
    _coreLogsSub = null;
    _coreLogsSocket = null;
    _recentLogConnHosts.clear();
    _clearBlockThrottleState();
    if (sub != null) {
      try {
        await sub.cancel();
      } catch (_) {}
    }
    if (socket != null) {
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  bool get _hasTrackedCoreProcesses =>
      _runningPids.isNotEmpty ||
      _runningBinaries.isNotEmpty ||
      _coreProcesses.isNotEmpty ||
      _preparingProcesses.isNotEmpty ||
      CliSession.instance.running;

  Future<void> disconnect({bool silent = false}) async {
    _cancelGeneration++;
    _filterReloadTimer?.cancel();
    _autoConnectRetryTimer?.cancel();
    if (_connectInFlight || _waitingForNetwork) { await cancel(); return; }
    if (_status == VpnStatus.disconnected && !_hasTrackedCoreProcesses) {
      return;
    }
    _stopNetworkWatcher();
    _requestedNode = null;
    _autoSession = false;
    _setStatus(VpnStatus.disconnecting, 'قطع اتصال...');
    await _sampleActivityIfDue(force: true);
    // سنجشی که بعد از قطع اتصال شروع شود، هسته ای بالا می آورد و پورت ها را
    // می گیرد؛ همان چیزی که اتصال بعدی را رد می کرد.
    await _stopProbes();
    await _stopCoreBlockLogMonitor();
    await _stopCores();
    await _stopHttpsFilterProxy();
    await _disableProxy();
    _statsTimer?.cancel();
    _healthTimer?.cancel();
    _ipTimer?.cancel();
    _stopLiveMeasurement();
    _connectedAt = null;
    _activeCoreLogPath = '';
    _stats = TunnelStats.empty;
    _tunnelVerified = false;
    _exitIp = '';
    _sameIpWarnedEpoch = -1;
    _setStatus(VpnStatus.disconnected, 'اتصال قطع شد.');
    if (!silent) {
      unawaited(refreshIp());
    }
    await _tray.update(
      state: 'disconnected',
      tooltip: '${AppConfig.appName} - قطع',
      connected: false,
    );
    if (!silent) {
      await _sound.play('disconnect');
    }
    _log.add('اتصال قطع شد و تنظیمات شبکه به حالت عادی بازگشت.');
  }

  Future<void>? _shutdownInFlight;

  /// بستن قطعی، سریع و بدون تکرار هسته، پنجره CLI، پروب های پینگ، پروکسی
  /// سیستمی و آیکون سینی هنگام خروج از برنامه، خاموشی ویندوز یا نصب به روز رسانی.
  Future<void> shutdownForExit() {
    return _shutdownInFlight ??= _performShutdownForExit();
  }

  Future<void> _performShutdownForExit() async {
    _shuttingDown = true;
    _cancelRequested = true;
    _cancelGeneration++;
    _connectionEpoch++;
    _prewarmCancelled = true;
    _prewarmTimer?.cancel();
    _filterReloadTimer?.cancel();
    _liveReloadTimer?.cancel();
    _autoConnectRetryTimer?.cancel();
    _waitingForNetwork = false;
    _stopNetworkWatcher();
    _statsTimer?.cancel();
    _healthTimer?.cancel();
    _ipTimer?.cancel();
    _pingTimer?.cancel();
    _stopLiveMeasurement();
    await _stopCoreBlockLogMonitor();
    await _blockServer?.stop();
    await _stopHttpsFilterProxy();
    cancelSpeedTest();

    // آیکون سینی در همان ابتدا برداشته می شود تا روی نوار وظیفه باقی نماند.
    try {
      await _tray.destroy().timeout(
            const Duration(milliseconds: 250),
            onTimeout: () {},
          );
    } catch (_) {}

    // بستن فوری پروب ها و دستگیره های دارت بدون صبر چندثانیه ای روی exitCode
    // یا اجرای تکراری taskkill/ServerSocket.
    if (_measuring || _corePing.busy) {
      _measuring = false;
      try {
        await _corePing.stopAll().timeout(
              const Duration(milliseconds: 300),
              onTimeout: () {},
            );
      } catch (_) {}
    }
    for (final Process process in List<Process>.of(_prewarmProcesses)) {
      try {
        process.kill();
      } catch (_) {}
    }
    _prewarmProcesses.clear();
    for (final Process process in List<Process>.of(_preparingProcesses)) {
      try {
        process.kill();
      } catch (_) {}
    }
    _preparingProcesses.clear();
    for (final Process process in List<Process>.of(_coreProcesses.values)) {
      try {
        process.kill();
      } catch (_) {}
    }
    _coreProcesses.clear();
    CliSession.instance.dropForShutdown();

    final List<int> extraPids = List<int>.of(_runningPids);
    _runningPids.clear();
    _runningBinaries.clear();
    _activeChain = const ChainSettings();
    _activePlanTun = false;

    for (final int pid in extraPids) {
      try {
        await _native.killPid(pid).timeout(
              const Duration(milliseconds: 150),
              onTimeout: () => false,
            );
      } catch (_) {}
    }

    try {
      final File pidFile = File(
        '${_provisioner.dataDir}${Platform.pathSeparator}run'
        '${Platform.pathSeparator}umbrella-core.pid',
      );
      if (pidFile.existsSync()) {
        pidFile.deleteSync();
      }
    } catch (_) {}

    // یک گذر بومی واحد روی رشته پس زمینه: بستن Job Object، تمام پردازش های
    // هسته و فرزندانشان، پنجره های CLI، و پاک سازی فوری پروکسی لوکال هاست.
    final bool hadProxy = _proxyPort != 0;
    _proxyPort = 0;
    try {
      await _native.shutdownCores().timeout(
            const Duration(milliseconds: 900),
            onTimeout: () => 0,
          );
    } catch (_) {}
    if (hadProxy) {
      try {
        await _native.disableSystemProxy().timeout(
              const Duration(milliseconds: 500),
              onTimeout: () => false,
            );
      } catch (_) {}
    }
  }

  Future<void>? _stopInFlight;
  Future<void> _stopCores() async {
    _connectionEpoch++;
    final Future<void>? pending = _stopInFlight;
    if (pending != null) return pending;
    final Future<void> stopping = _stopCoresOwned();
    _stopInFlight = stopping;
    try { await stopping; } finally { _stopInFlight = null; }
  }

  Future<void> _stopCoresOwned() async {
    cancelSpeedTest();
    _activeChain = const ChainSettings();
    _activePlanTun = false;
    _activeMixedPort = _configuredMixedPort;
    _activeLocalProxyOpen = true;
    _activeLocalProxySecret = '';
    _stoppingOwnCore = true;
    try {
      await _stopCoresInner();
    } finally {
      _stoppingOwnCore = false;
    }
  }

  Future<void> _stopCoresInner() async {
    for (final Process process in List<Process>.of(_prewarmProcesses)) {
      try {
        process.kill();
      } catch (_) {}
    }
    _prewarmProcesses.clear();
    final List<Process> prepping = List<Process>.of(_preparingProcesses);
    _preparingProcesses.clear();
    if (prepping.isNotEmpty) {
      await Future.wait(
        prepping.map((Process process) async {
          try {
            process.kill();
            await process.exitCode.timeout(
              const Duration(milliseconds: 250),
              onTimeout: () => -1,
            );
          } catch (_) {}
        }),
      );
    }
    await _sweepOrphanChildren();
    // اگر هسته در پنجره CLI اجرا شده باشد، اول همان بسته می شود تا هیچ هسته
    // ای بیرون از برنامه نماند و پروکسی سیستمی به حالت عادی برگردد.
    await _stopCliCore();
    await CliSession.instance.close();
    for (final Process process in List<Process>.of(_coreProcesses.values)) {
      try {
        process.kill();
        await process.exitCode.timeout(
          const Duration(milliseconds: 400),
          onTimeout: () => -1,
        );
      } on Exception {
        // فرایند از قبل بسته شده است.
      }
    }
    _coreProcesses.clear();
    for (final int pid in List<int>.of(_runningPids)) {
      await _native.killPid(pid);
    }
    for (final String binary in List<String>.of(_runningBinaries)) {
      await _native.killByName(binary);
    }
    _runningPids.clear();
    _runningBinaries.clear();
  }

  /// بستن پردازش هایی که هسته با نام دیگری اجرا کرده و پورت های ما را گرفته
  /// اند.
  ///
  /// **گزارش ۱٫۰۱۸:** در فهرست پردازش ها سه `UmbrellaCli.exe` بازمانده با
  /// شناسه های ۱۲۸۷۶ / ۱۴۲۲۴ / ... دیده شد. `_stopCores` فقط شناسه هایی را
  /// می بست که خودش ثبت کرده بود و فرزندانِ هسته ثبت نمی شدند. تجمع آن ها
  /// همان چیزی است که دفعه بعد پورت ۱۷۰۷۸ را می گیرد و اتصال را می کشد.
  Future<void> _sweepOrphanChildren() async {
    try {
      final List<int> held = await UmbrellaCore.heldReservedPorts();
      if (held.isEmpty) {
        return;
      }
      final List<PortHolder> holders =
          await UmbrellaCore.holders(held, native: _native);
      for (final PortHolder holder in holders) {
        if (holder.isOurs && !_runningPids.contains(holder.pid)) {
          await _native.killPid(holder.pid);
          _orphansKilled++;
        }
      }
    } on Object {
      // پاکسازی نباید هرگز جلوی بستن اتصال را بگیرد.
    }
  }

  /// بستن هسته ای که در پنجره CLI اجرا شده است.
  ///
  /// هسته خودش با `SIGINT`/`SIGTERM` تمیز بسته می شود و پروکسی سیستمی را
  /// برمی گرداند؛ ویندوز معادل آن، بستن پنجره یا کشتن همان فرایند است.
  Future<void> _stopCliCore() async {
    for (final String binary in <String>[
      umbrellaCliBinary,
      UmbrellaCore.engineBinary,
      UmbrellaCore.adminBinary,
    ]) {
      final int killed = await _native.killByName(binary);
      if (killed > 0) {
        // هسته ای که از اجرای قبلی باز مانده بود، پورت هایش را هم گرفته
        // بود؛ همان چیزی که اجرای بعدی را با «already in use» می کشت.
        // این پایان کار عادی است و هر بار لاگ نمی شود.
        _orphansKilled += killed;
      }
    }
    // فایل قفل هسته پاک می شود تا اجرای بعدی معطل نشود.
    try {
      final File pid = File(
        '${_provisioner.dataDir}${Platform.pathSeparator}run'
        '${Platform.pathSeparator}umbrella-core.pid',
      );
      if (await pid.exists()) {
        await pid.delete();
      }
    } on FileSystemException {
      // فایل نبود؛ کاری لازم نیست.
    }
  }

  Future<void> _failAndCleanup(String reason) async {
    _waitingForNetwork = false;
    _stopNetworkWatcher();
    _requestedNode = null;
    _autoSession = false;
    await _stopCoreBlockLogMonitor();
    await _stopCores();
    await _disableProxy();
    _statsTimer?.cancel();
    _healthTimer?.cancel();
    _ipTimer?.cancel();
    _stopLiveMeasurement();
    _connectedAt = null;
    _activeCoreLogPath = '';
    _tunnelVerified = false;
    _stats = TunnelStats.empty;
    _setStatus(VpnStatus.failed, reason);
    await _sound.play('error');
    await _tray.update(
      state: 'failed',
      tooltip: '${AppConfig.appName} - خطای اتصال',
      connected: false,
    );
    if (_settings.notificationsEnabled) {
      await _tray.balloon('اتصال برقرار نشد', reason, warning: true);
    }
    _log.add(reason, level: 'error');
  }

  Future<void> restoreNetwork() async {
    await _native.restoreNetworkDefaults();
    _proxyPort = 0;
    _log.add('تنظیمات شبکه به حالت پیش فرض بازگشت.', level: 'warning');
    _notify();
  }

  Future<void> refreshIp() async {
    if (_disposed || _shuttingDown || _connectInFlight || _status.busy) {
      return;
    }
    // هنگام اتصال فعال هرگز `_realIp` (آی پی واقعی پیش از تونل) را با آی پی
    // خروجی تونل بازنویسی نکن؛ فقط اطلاعات آی پی خروجی تونل را به روز کن.
    if (_status == VpnStatus.connected) {
      await _verifyTunnel(allowRetry: false);
      return;
    }
    if (!_canCaptureBaselineIp) {
      return;
    }
    final GeoInfo fetched = await _ip.fetch(force: true);
    if (!_canCaptureBaselineIp || fetched.ip.isEmpty) {
      return;
    }
    _geo = fetched;
    _realIp = fetched.ip;
    _realCountryCode = fetched.flagCode.toLowerCase();
    _notify();
  }

  VpnNode? get recommended =>
      _balancer.preview(_nodes, _settings.selectionMode, _device.machineId);

  void _setStatus(VpnStatus status, String message) {
    _status = status;
    _message = message;
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _prewarmCancelled = true;
    _prewarmTimer?.cancel();
    _filterReloadTimer?.cancel();
    _liveReloadTimer?.cancel();
    _autoConnectRetryTimer?.cancel();
    _waitingForNetwork = false;
    _stopNetworkWatcher();
    _statsTimer?.cancel();
    _healthTimer?.cancel();
    _ipTimer?.cancel();
    _pingTimer?.cancel();
    unawaited(_stopCoreBlockLogMonitor());
    unawaited(_blockServer?.stop());
    unawaited(_stopHttpsFilterProxy());
    if (_hasTrackedCoreProcesses ||
        _prewarmProcesses.isNotEmpty ||
        _prewarmInFlight != null ||
        _connectInFlight ||
        _status != VpnStatus.disconnected ||
        _proxyPort != 0) {
      unawaited(_stopCores());
      unawaited(_native.shutdownCores());
    }
    super.dispose();
  }
}

/// نگاشت وضعیت اتصال به رنگ ها و تصاویر، برای مصرف در رابط کاربری.
class VpnVisuals {
  const VpnVisuals._();

  static Color color(BuildContext context, VpnStatus status) {
    final UmbrellaColors colors = context.colors;
    switch (status) {
      case VpnStatus.connected:
        return colors.success;
      case VpnStatus.failed:
        return colors.danger;
      case VpnStatus.disconnected:
        return colors.textSecondary;
      default:
        return colors.warning;
    }
  }

  static IconData icon(VpnStatus status) {
    switch (status) {
      case VpnStatus.connected:
        return Icons.shield_rounded;
      case VpnStatus.failed:
        return Icons.error_outline_rounded;
      case VpnStatus.disconnected:
        return Icons.shield_outlined;
      case VpnStatus.disconnecting:
        return Icons.pause_circle_outline_rounded;
      default:
        return Icons.sync_rounded;
    }
  }
}
