import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../core/persian.dart';
import '../core/storage.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../models/models.dart';
import '../platform/native.dart';
import '../platform/services.dart';
import 'balancer.dart';
import 'clash_config.dart';
import 'cli_session.dart';
import 'cores.dart';
import 'umbrella_core.dart';
import 'core_ping.dart';
import 'ping.dart';
import 'tunnel_probe.dart';

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
    this.cancelled = false,
  });

  final bool ok;
  final String message;
  final bool needsElevation;
  final bool needsCores;

  /// اشتراک کاربر اجازه اتصال نمی دهد (منقضی، مسدود یا تمام شده).
  final bool needsRenewal;

  /// کاربر خودش وسط کار دکمه لغو را زد؛ این خطا نیست و نباید پیام خطا بدهد.
  final bool cancelled;
}

class _AttemptResult {
  const _AttemptResult({
    required this.message,
    this.ok = false,
    this.needsCores = false,
    this.cancelled = false,
  });

  final String message;
  final bool ok;
  final bool needsCores;
  final bool cancelled;
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
    this.grpcPort = 0,
    this.clashPort = 0,
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

  /// اگر بزرگ تر از صفر باشد، هسته یک سرور پروکسی محلی روی این پورت می سازد و
  /// برنامه پروکسی سیستمی ویندوز را به آن وصل می کند.
  final int proxyPort;

  /// آیا این نقشه تونل کامل است (`--tun`)؟
  final bool tun;

  bool get usesSystemProxy => proxyPort > 0 && !tun;
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

  /// بررسی دسترسی حساب پیش از هر اتصال. اگر رشته غیرخالی برگرداند، اتصال
  /// انجام نمی شود و همان پیام به کاربر نشان داده می شود (اشتراک منقضی،
  /// مسدود یا تمام شده).
  final String Function()? accessGuard;

  final VoidCallback? onRequireCores;

  AppSettings _settings;
  AppSettings get settings => _settings;

  List<VpnNode> _nodes = <VpnNode>[];
  List<VpnNode> get nodes => List<VpnNode>.unmodifiable(_nodes);

  VpnStatus _status = VpnStatus.disconnected;
  VpnStatus get status => _status;

  VpnNode? _activeNode;
  VpnNode? get activeNode => _activeNode;

  String _message = 'برای اتصال دکمه را بزنید.';
  String get message => _message;

  TunnelStats _stats = TunnelStats.empty;
  TunnelStats get stats => _stats;

  GeoInfo _geo = GeoInfo.empty;
  GeoInfo get geo => _geo;

  String _realIp = '';
  String get realIp => _realIp;

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
  ProxyLink? _link;
  Timer? _liveTimer;

  /// پینگ سرور متصل: عدد زنده تونل اگر آماده باشد، وگرنه پینگ شبکه همان
  /// سرور. این عدد هرگز صفر نمی ماند چون سرور متصل از فهرست سنجش هسته ای
  /// کنار گذاشته می شود و پیش از این همیشه «در حال سنجش» می ماند.
  int get activePingMs {
    if (_livePing > 0) {
      return _livePing;
    }
    final VpnNode? node = _activeNode;
    if (node == null) {
      return 0;
    }
    if (node.pingMs > 0) {
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
  int _healthFailures = 0;

  /// هسته ای که برای هر سرور جواب داده است (شناسه سرور → نام هسته).
  final Map<String, String> _preferredCore = <String, String>{};
  int _reconnectAttempts = 0;
  bool _disposed = false;

  bool get isConnected => _status == VpnStatus.connected;
  bool get isBusy => _status.busy;

  Future<void> bootstrap() async {
    await _provisioner.init();
    _device = await _native.deviceInfo();
    // آی پی واقعی دستگاه پیش از هر اتصالی خوانده می شود تا صفحه اتصال هرگز
    // «نامشخص» نشان ندهد. اگر یک سرویس جواب نداد، سرویس بعدی امتحان می شود و
    // در آخر آی پی داخلی کارت شبکه می ماند.
    _realIp = await _ip.fetchIp(force: true);
    if (_realIp.isEmpty) {
      final String local = await _native.localIp();
      if (local.isNotEmpty) {
        _realIp = local;
      }
      _log.add(
        'آی پی بیرونی خوانده نشد؛ آی پی داخلی دستگاه نمایش داده می شود.',
        level: 'warning',
      );
    }
    _geo = _ip.last;
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
    if (_settings.autoConnect) {
      unawaited(connect());
    }
  }

  Future<void> _loadCachedNodes() async {
    // پیکربندی کلش پنل هم مثل فهرست سرورها نگه داشته می شود تا پس از اجرای
    // دوباره برنامه، بدون اینترنت دوباره در دسترس باشد.
    try {
      final String? yaml =
          await LocalStore.instance.readFile(StoreKeys.panelProfile);
      if (yaml != null && yaml.trim().isNotEmpty) {
        _panelProfile = yaml;
        _clashNames = ClashConfig.nodeNames(yaml).toSet();
      }
    } on Exception {
      // پیکربندی ذخیره نشده است؛ هسته از لینک ها استفاده می کند.
    }
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
    final String raw = jsonEncode(
      _nodes.map((VpnNode node) => node.toJson()).toList(),
    );
    await LocalStore.instance.writeFile(StoreKeys.nodesCache, raw);
  }

  /// سرورهای تازه خوانده شده از اشتراک ها؛ پینگ ها از قبل موجود حفظ می شوند.
  Future<void> applyNodes(List<VpnNode> nodes, {bool measure = true}) async {
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
    _notify();
    if (measure && _nodes.isNotEmpty) {
      unawaited(refreshPings());
    }
  }

  Future<void> refreshPings({bool all = true}) async {
    if (_measuring || _nodes.isEmpty) {
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
    _pingProgressTotal = all ? pool.length : pool.take(12).length;
    _notify();
    final List<VpnNode> target = all ? pool : pool.take(12).toList();
    List<VpnNode> measured = target;
    try {
      measured = await _ping.measureAll(
        target,
        concurrency: 8,
        onProgress: (int done, int total) {
          _pingProgressDone = done;
          _pingProgressTotal = total;
          _notify();
        },
      );
    } on Exception catch (error) {
      _log.add('سنجش پینگ ناموفق بود: ${error.toString()}', level: 'warning');
    }
    // تاخیر واقعی تونل: هسته هر سرور را یک بار امتحان می کند و عدد دقیق را
    // می دهد؛ اگر هسته در دسترس نباشد، نتیجه تی سی پی و آی سی ام پی همان
    // طور می ماند.
    Map<String, int> tunnelDelays = <String, int>{};
    try {
      if (liveTunnel) {
        throw StateError('اتصال فعال است');
      }
      tunnelDelays = await _corePing
          .measure(target, settings: _settings)
          .timeout(
            const Duration(seconds: 100),
            onTimeout: () => <String, int>{},
          );
    } catch (_) {
      tunnelDelays = <String, int>{};
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
    await _cacheNodes();
    _log.add(
      'سنجش پینگ: تاخیر تونل برای ${Fa.num(tunnelDelays.length)} سرور و '
      'پینگ شبکه برای ${Fa.num(fused.where((VpnNode node) => node.hasPing).length)} '
      'سرور به دست آمد.'
      '${_medianNote(fused)}'
      '${_tunnelNote(tunnelDelays)}',
      level: tunnelDelays.isEmpty && !liveTunnel ? 'warning' : 'info',
    );
    if (tunnelDelays.isEmpty && !liveTunnel) {
      final String detail = await _corePing.lastError();
      _log.add(
        'سنجش تاخیر تونل نتیجه نداد${detail.isEmpty ? '' : ': $detail'}',
        level: 'warning',
      );
    }
    _notify();
  }

  /// پینگ شبکه سرور متصل (باز کردن اتصال تی سی پی به خود سرور).
  ///
  /// این سنجش تونل کاربر را دست نمی زند و فقط برای این است که عدد پینگ سرور
  /// متصل هیچ وقت صفر نماند.
  Future<void> _measureActiveNetworkPing(VpnNode node) async {
    final VpnNode updated = await _ping.measure(node, attempts: 1);
    if (!updated.hasPing) {
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
    _notify();
  }

  void updateSettings(AppSettings settings) {
    _settings = settings;
    _sound.enabled = settings.soundEnabled;
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(
      Duration(seconds: settings.pingIntervalSeconds.clamp(120, 3600)),
      (_) => unawaited(refreshPings(all: false)),
    );
    _notify();
  }

  /// درخواست لغو اتصال در حال انجام.
  ///
  /// ساخت تونل چند ثانیه طول می کشد و کاربر باید هر لحظه بتواند پشیمان شود؛
  /// با زدن دکمه قطع، این پرچم بالا می رود، حلقه تلاش هسته ها می شکند و همه
  /// چیز تمیز بسته می شود.
  bool _cancelRequested = false;
  bool get cancelling => _cancelRequested;

  /// لغو فوری اتصال در حال انجام (دکمه «لغو اتصال»).
  Future<void> cancel() async {
    if (!_status.busy && _status != VpnStatus.connected) {
      return;
    }
    _cancelRequested = true;
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
    _stopLiveMeasurement();
    _connectedAt = null;
    _stats = TunnelStats.empty;
    _tunnelVerified = false;
    _exitIp = '';
    _cancelRequested = false;
    _activeNode = null;
    _setStatus(VpnStatus.disconnected, 'اتصال قطع شد.');
    unawaited(
      _tray.update(
        state: 'disconnected',
        tooltip: '${AppConfig.appName} - قطع',
        connected: false,
      ),
    );
    _log.add('اتصال لغو شد و تنظیمات شبکه به حالت عادی بازگشت.');
  }

  /// اتصال با تلاش روی چند سرور: اگر یک سرور بالا نیامد، سرور بعدی امتحان
  /// می شود تا کاربر مجبور نشود دستی سرور عوض کند.
  Future<ConnectOutcome> connect({VpnNode? requested}) async {
    if (_status.active) {
      return const ConnectOutcome(ok: false, message: 'اتصال از قبل برقرار است.');
    }
    _cancelRequested = false;
    // دسترسی حساب: اشتراک منقضی، مسدود یا تمام شده حق اتصال ندارد.
    final String blocked = accessGuard?.call() ?? '';
    if (blocked.isNotEmpty) {
      _log.add('اتصال رد شد: $blocked', level: 'warning');
      _setStatus(VpnStatus.failed, blocked);
      return ConnectOutcome(ok: false, message: blocked, needsRenewal: true);
    }
    if (_nodes.isEmpty) {
      return const ConnectOutcome(
        ok: false,
        message: 'هیچ سروری موجود نیست؛ اشتراک در حال دریافت از سرور است.',
      );
    }
    final List<VpnNode> usableNodes =
        _nodes.where((VpnNode node) => usable(node) && !node.disabled).toList();
    if (usableNodes.isEmpty) {
      _log.add(
        'هیچ سروری از ${Fa.num(_nodes.length)} سرور اشتراک برای هسته آمبرلا '
        'ورودی معتبر نداشت.',
        level: 'error',
      );
      return const ConnectOutcome(
        ok: false,
        message: 'سروری که با این نسخه کار کند در اشتراک شما نیست.',
      );
    }

    final List<VpnNode> fitting = usableNodes
        .where(_fitsPreference)
        .toList();
    if (fitting.isEmpty) {
      const String message = 'سروری که با این نسخه کار کند در اشتراک شما نیست.';
      _setStatus(VpnStatus.failed, message);
      return const ConnectOutcome(ok: false, message: message);
    }
    _log.add(
      'درخواست اتصال: ${Fa.num(_nodes.length)} سرور در فهرست، '
      'حالت «${_settings.corePreference.faName}» با هسته آمبرلا.',
    );
    if (_clashNames.isNotEmpty) {
      _log.add(
        'پیکربندی پنل ${Fa.num(_clashNames.length)} گره دارد و نگه داشته '
        'شده است؛ اگر سرورها با این پروفایل جواب ندهند، همان ها با لینک '
        'اجرا می شوند.',
      );
    }
    _setStatus(VpnStatus.preparing, 'آماده سازی هسته و بررسی شبکه...');
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

      _realIp = await _ip.fetchIp(force: true);

      final SelectionResult selection = requested != null
          ? SelectionResult(node: requested, reason: 'سرور انتخابی شما.')
          : _balancer.pick(
              nodes: fitting,
              mode: _settings.selectionMode,
              deviceSeed: _device.machineId.isNotEmpty
                  ? _device.machineId
                  : _device.hostname,
              preferredNodeId: _settings.lastNodeId,
              stickyMinutes: _settings.stickyMinutes,
              allowFailover: _settings.autoFailover,
            );

      final VpnNode? node = selection.node;
      if (node == null) {
        _setStatus(VpnStatus.failed, selection.reason);
        return ConnectOutcome(ok: false, message: selection.reason);
      }

      final List<VpnNode> candidates = _candidates(node, selection.reason);
      String lastMessage = '';
      for (int index = 0; index < candidates.length; index++) {
        if (_cancelRequested) {
          return const ConnectOutcome(ok: false, cancelled: true, message: 'اتصال لغو شد.');
        }
        final VpnNode candidate = candidates[index];
        if (candidates.length > 1) {
          _setStatus(
            VpnStatus.preparing,
            'تلاش ${Fa.num(index + 1)} از ${Fa.num(candidates.length)}: ${candidate.name}',
          );
        }
        final _AttemptResult attempt = await _attempt(candidate);
        if (attempt.cancelled) {
          return const ConnectOutcome(ok: false, cancelled: true, message: 'اتصال لغو شد.');
        }
        if (attempt.ok) {
          return const ConnectOutcome(ok: true, message: 'اتصال برقرار شد.');
        }
        lastMessage = attempt.message;
        _balancer.markFailed(candidate.id);
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

  /// سرور انتخاب شده و اگر حالت خودکار باشد دو گزینه بعدی با کمترین پینگ.
  List<VpnNode> _candidates(VpnNode first, String reason) {
    final List<VpnNode> list = <VpnNode>[first];
    if (_settings.selectionMode == SelectionMode.manual ||
        !_settings.autoFailover) {
      return list;
    }
    final List<VpnNode> rest = _nodes
        .where((VpnNode node) =>
            node.id != first.id && usable(node) && _fitsPreference(node))
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
            if (candidate.id != first.id && usable(candidate)) {
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
    for (final VpnNode node in rest) {
      if (node.disabled || node.host.isEmpty) {
        continue;
      }
      list.add(node);
      if (list.length >= 4) {
        break;
      }
    }
    return list;
  }

  /// یک تلاش اتصال به یک سرور مشخص.
  Future<_AttemptResult> _attempt(VpnNode node) async {
    _activeNode = node;
    _notify();

    // ۱. بستن هر فیلترشکن و پروکسی فعال دیگر
    await _terminateForeignCores();
    await _native.disableSystemProxy();

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
      _setStatus(VpnStatus.preparing, 'سرور بعدی امتحان می شود.');
      return const _AttemptResult(
        message: 'هسته آمبرلا برای این سرور ورودی معتبری نداشت؛ سرور بعدی امتحان می شود.',
      );
    }

    // یک هسته است، دو حالت: اگر راه اول (تونل کامل یا پروکسی سیستمی) بالا
    // نیامد، همان هسته با حالت دیگر امتحان می شود. این همان کاری است که
    // همان کاری که کلاینت رسمی هسته می کند، با عوض کردن حالت به جای هسته.
    for (final LaunchPlan plan in plans) {
      if (_cancelRequested) {
        await _stopCores();
        await _disableProxy();
        return const _AttemptResult(cancelled: true, message: 'اتصال لغو شد.');
      }
      if (plan.warning.isNotEmpty) {
        _log.add(plan.warning, level: 'warning');
      }
      _setStatus(VpnStatus.connecting, 'اجرای هسته و ساخت تونل...');
      final bool started = await _launch(plan);
      if (!started) {
        await _stopCores();
        await _disableProxy();
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
        );
        await _stopCores();
        await _disableProxy();
        continue;
      }

      // تایید واقعی: تا وقتی ترافیک از تونل رد نشود، «وصل شد» اعلام نمی شود.
      // در حالت تونل، درخواست مستقیم هم از کارت شبکه مجازی رد می شود؛ پس
      // معیار درست، عوض شدن آی پی خروجی است نه باز شدن پورت.
      // تایید عبور ترافیک: در حالت پروکسی سیستمی، درخواست از همان پروکسی محلی
      // می رود. در حالت تونل کامل، درخواست مستقیم هم از کارت شبکه مجازی رد
      // می شود، پس بازگشت پاسخ ۲۰۴ خودش یعنی تونل کار می کند.
      //
      // پیش از این در حالت تونل فقط عوض شدن آی پی معیار بود و اگر سرویس
      // خواندن آی پی جواب نمی داد، اتصال سالم هم رد می شد (همان خطای
      // «هیچ هسته ای نتوانست تونل را بالا بیاورد»).
      final Duration probeTimeout =
          Duration(seconds: plans.length > 1 ? 6 : 8);
      final bool flows;
      if (plan.usesSystemProxy) {
        flows = await TunnelProbe.check(
          proxyPort: plan.proxyPort,
          timeout: probeTimeout,
        );
      } else {
        final bool direct = await TunnelProbe.check(timeout: probeTimeout);
        if (!direct) {
          flows = false;
        } else if (_realIp.isEmpty) {
          // آی پی پیش از اتصال خوانده نشده؛ برای مقایسه چیزی نداریم.
          flows = true;
        } else {
          final bool changed = await _exitIpChanged();
          if (!changed) {
            _log.add(
              'ترافیک از کارت شبکه مجازی رد شد ولی آی پی خروجی عوض نشد؛ '
              'به عنوان اتصال معتبر پذیرفته نمی شود.',
              level: 'warning',
            );
          }
          flows = changed;
        }
      }
      if (!flows) {
        final String coreLog = '${_provisioner.dataDir}'
            '${Platform.pathSeparator}run${Platform.pathSeparator}'
            '${plan.cores.first.name}-core.log';
        final String tail = await _readLogTail(coreLog);
        _log.add(
          'هسته بالا آمد ولی هیچ ترافیکی از تونل رد نشد؛ این اتصال معتبر نیست.'
          '${tail.isEmpty ? '' : ' خروجی هسته: $tail'}',
          level: 'error',
        );
        await _stopCores();
        await _disableProxy();
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
          );
          await _stopCores();
          await _disableProxy();
          continue;
        }
      }
      _connectedAt = DateTime.now();
      _healthFailures = 0;
      _reconnectAttempts = 0;
      _setStatus(VpnStatus.connected, 'اتصال برقرار شد.');
      _balancer.markConnected(node.id);
      _startTimers();
      await _sound.play('connect');
      await _tray.update(
        state: 'connected',
        tooltip: '${AppConfig.appName} - متصل به ${node.name}',
        connected: true,
      );
      if (_settings.notificationsEnabled) {
        await _tray.balloon(
          'اتصال برقرار شد',
          '${node.name} | ${Fa.ms(node.pingMs)}',
        );
      }

      unawaited(_verifyTunnel());
      _preferredCore[node.id] = plan.cores.first.name;
      _log.add(
        'اتصال به ${node.name} (${node.host}:${node.port}) با هسته '
        '${plan.primaryBinary} برقرار شد.',
      );
      _settings = _settings.copyWith(lastNodeId: node.id);
      onSettingsChanged?.call(_settings);
      return const _AttemptResult(message: 'اتصال برقرار شد.', ok: true);
    }

    _preferredCore.remove(node.id);
    _setStatus(VpnStatus.failed, 'هیچ هسته ای نتوانست اتصال را برقرار کند.');
    return const _AttemptResult(
      message: 'هیچ هسته ای نتوانست تونل را بالا بیاورد؛ گزارش ها را ببینید.',
    );
  }

  Future<void> _terminateForeignCores() async {
    final List<String> running = await _native.runningCores();
    for (final String core in running) {
      if (_runningBinaries.contains(core)) {
        continue;
      }
      final int killed = await _native.killByName(core);
      if (killed > 0) {
        _log.add('فیلترشکن یا هسته فعال دیگر بسته شد: $core', level: 'warning');
      }
    }
    final bool proxy = await _native.systemProxyEnabled();
    if (proxy) {
      await _native.disableSystemProxy();
      _log.add('پروکسی سیستمی ویندوز غیرفعال شد.', level: 'warning');
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
    switch (node.protocol) {
      case NodeProtocol.vless:
      case NodeProtocol.vmess:
        return JsonX.text(params['id'] ?? params['uuid']).isNotEmpty;
      case NodeProtocol.tuic:
        return JsonX.text(params['id'] ?? params['uuid']).isNotEmpty &&
            JsonX.text(params['password']).isNotEmpty;
      case NodeProtocol.trojan:
      case NodeProtocol.hysteria2:
        return JsonX.text(params['password']).isNotEmpty;
      case NodeProtocol.shadowsocks:
        return JsonX.text(params['password']).isNotEmpty &&
            JsonX.text(params['method'] ?? params['cipher']).isNotEmpty;
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

  /// نام گره هایی که در پیکربندی خود پنل هستند.
  ///
  /// فقط برای همین گره ها نام پنل با نام سرور یکی است، پس در گزارش ها می شود
  /// هر دو را به هم نسبت داد.
  Set<String> _clashNames = <String>{};

  /// نام گره های پنل (برای گزارش ها: کاربر می بیند کدام سرور همان گره پنل
  /// است). وقتی پنل پروفایل کاملی داده باشد پر می شود.
  Set<String> get panelNodeNames => Set<String>.unmodifiable(_clashNames);

  /// آخرین پیکربندی کاملی که خود پنل داد (کلش یا قالب کامل موتور).
  ///
  /// این فایل تنها جایی است که پدینگ، هدرهای مرورگر، ALPN و finger-print گره
  /// ها با هم هست؛ همان چیزی که سرور انتظار دارد. خود هسته این فایل
  /// را درست می شناسد، پس نگه داشته می شود تا اگر کاربر خواست همان پروفایل
  /// اجرا شود، آماده باشد.
  String _panelProfile = '';

  String get panelProfile => _panelProfile;

  /// ذخیره پیکربندی خود پنل (متن YAML یا JSON).
  Future<void> applyClashProfile(String yaml) async {
    if (yaml.trim().isEmpty || yaml.trim() == _panelProfile.trim()) {
      return;
    }
    _panelProfile = yaml;
    try {
      _clashNames = ClashConfig.nodeNames(yaml).toSet();
    } on Exception {
      _clashNames = <String>{};
    }
    await LocalStore.instance.writeFile(StoreKeys.panelProfile, yaml);
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
  static const String pingDns = 'https://1.1.1.1/dns-query';

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
    final CoreInfo? core = _provisioner.info(umbrellaCoreId);
    final String binary = core?.binary ?? umbrellaCliBinary;
    final String? exe = await _provisioner.locateBinary(binary);
    if (exe == null || exe.isEmpty) {
      _lastPlanNeedsCore = true;
      _log.add(
        'هسته آمبرلا ($binary) در نسخه نصب نیست؛ برنامه را با نصب کننده '
        'رسمی دوباره نصب کنید.',
        level: 'error',
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
    await links.writeAsString('$link\n', flush: true);

    // همان حالتی که کاربر خواسته: تونل کامل اگر روشن باشد و دسترسی مدیر هم
    // داشته باشیم، وگرنه پروکسی سیستمی.
    bool tun = _settings.tunMode;
    if (tun && !_device.elevated) {
      _log.add(
        'حالت تونل به دسترسی مدیر نیاز دارد؛ این بار با پروکسی سیستمی وصل '
        'می شویم. برای تونل، برنامه را با دسترسی مدیر اجرا کنید.',
        level: 'warning',
      );
      tun = false;
    }
    // پورت های هر اجرا. هسته هر اجرا یک سرور gRPC روی ۱۷۰۷۸ بالا می آورد و
    // اگر نمونه قبلی (یا پنجره CLI بازمانده) هنوز آن را گرفته باشد، با
    // «port 17078 is already in use» می میرد و هیچ تونلی ساخته نمی شود.
    // پس برای هر اجرا پورت آزاد انتخاب می شود (نمونه های کهنه در _attempt
    // پیش از این بسته شده اند).
    final int grpcPort = await UmbrellaCore.freeGrpcPort();
    final int clashPort = await UmbrellaCore.freeClashPort();
    return <LaunchPlan>[
      LaunchPlan(
        cores: <CoreLaunch>[
          CoreLaunch(
            exe: exe,
            args: _umbrellaArgs(
              exe: exe,
              links: links.path,
              runDir: runDir.path,
              tun: tun,
              grpcPort: grpcPort,
            ),
            workDir: _umbrellaDir(exe),
            name: tun ? 'umbrella-tun' : 'umbrella',
          ),
        ],
        linksPath: links.path,
        // در حالت پروکسی سیستمی، باز شدن پورت محلی نشانه آمادگی است؛ در
        // حالت تونل، کارت شبکه مجازی نشانه آن است.
        readinessPort: tun ? 0 : _umbrellaPort,
        primaryBinary: binary,
        tunnelHint: tun ? AppConfig.tunAdapterHint : '',
        chained: false,
        proxyPort: tun ? 0 : _umbrellaPort,
        runDir: runDir.path,
        tun: tun,
        grpcPort: grpcPort,
        clashPort: clashPort,
      ),
    ];
  }

  /// شناسه هسته در فهرست همراه نسخه.
  static const String umbrellaCoreId = UmbrellaCore.id;

  /// نام فایل خط فرمان هسته (همان HiddifyCli با نام آمبرلا).
  static const String umbrellaCliBinary = UmbrellaCore.cliBinary;

  /// چند فرایند بازمانده از اجرای قبلی در این اجرا بسته شد.
  int _orphansKilled = 0;

  /// پورت محلی هسته. خود هسته ۱۲۳۳۴ را پیش فرض دارد و همین عدد در برنامه هم
  /// ثابت است تا پروکسی سیستمی همیشه همان جا وصل شود.
  static const int _umbrellaPort = AppConfig.httpPortUmbrella;

  /// آرگومان های هسته.
  ///
  /// `run -c <links>` همان دستوری است که مستندات هسته برای «فقط لینک ها دارم»
  /// می دهد: هسته خودش پیکربندی، دی ان اس و مسیرها را می سازد.
  static List<String> _umbrellaArgs({
    required String exe,
    required String links,
    required String runDir,
    required bool tun,
    int grpcPort = 0,
  }) {
    return UmbrellaCore.args(
      links: links,
      runDir: runDir,
      port: _umbrellaPort,
      tun: tun,
      systemProxy: !tun,
      grpcPort: grpcPort,
    );
  }

  /// لینک سرور برای دادن به هسته (برای سنجش پینگ و پنجره CLI هم استفاده
  /// می شود).
  static String linkFor(VpnNode node) {
    final String raw = node.raw.trim();
    if (raw.contains('://')) {
      return raw;
    }
    return _linkFromNode(node);
  }

  /// لینک سرور برای دادن به هسته.
  ///
  /// لینک اصلی همان چیزی است که در اشتراک بود؛ اگر نبود، از فیلدهای سرور
  /// ساخته می شود. هسته خودش جزئیات پروتکل را می فهمد.
  String _umbrellaLink(VpnNode node) => linkFor(node);

  /// ساختن لینک از فیلدهای سرور برای منابعی که لینک ندارند (کلش، وایرگارد
  /// و مانند آن). هسته همه این پروتکل ها را می شناسد.
  static String _linkFromNode(VpnNode node) {
    final Map<String, dynamic> params = node.params;
    final String host = node.host;
    final int port = node.port;
    final String name = Uri.encodeComponent(node.name);
    switch (node.protocol) {
      case NodeProtocol.vless:
        return 'vless://${JsonX.text(params['id'])}@$host:$port'
            '?encryption=none&security=${JsonX.text(params['security'], 'none')}'
            '&type=${JsonX.text(params['network'] ?? params['type'], 'tcp')}'
            '&sni=${JsonX.text(params['sni'], host)}'
            '&path=${Uri.encodeComponent(JsonX.text(params['path'], '/'))}'
            '&host=${JsonX.text(params['host'], host)}'
            '#$name';
      case NodeProtocol.vmess:
        return 'vmess://${base64Encode(utf8.encode(jsonEncode(<String, dynamic>{
              'v': '2',
              'ps': node.name,
              'add': host,
              'port': '$port',
              'id': JsonX.text(params['id']),
              'aid': '${JsonX.integer(params['alterId'])}',
              'scy': JsonX.text(params['method'], 'auto'),
              'net': JsonX.text(params['network'] ?? params['type'], 'tcp'),
              'type': 'none',
              'host': JsonX.text(params['host'], host),
              'path': JsonX.text(params['path'], '/'),
              'tls': JsonX.text(params['security']) == 'tls' ? 'tls' : '',
              'sni': JsonX.text(params['sni'], host),
            })))}';
      case NodeProtocol.trojan:
        return 'trojan://${Uri.encodeComponent(JsonX.text(params['password']))}'
            '@$host:$port?sni=${JsonX.text(params['sni'], host)}'
            '&type=${JsonX.text(params['network'] ?? params['type'], 'tcp')}'
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
        return 'tuic://${JsonX.text(params['id'])}:'
            '${Uri.encodeComponent(JsonX.text(params['password']))}'
            '@$host:$port?sni=${JsonX.text(params['sni'], host)}#$name';
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

  /// نام سرور برای گزارش ها. بعضی نام ها خودشان با واژه سرور شروع می شوند و
  /// تکرار آن واژه در گزارش ها زشت و گمراه کننده بود.
  static String _nodeLabel(VpnNode node) {
    final String name = node.name.trim();
    if (name.startsWith('سرور')) {
      return name;
    }
    return 'سرور $name';
  }

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
  Future<bool> _launch(LaunchPlan plan) async {
    await _stopCores();
    if (_orphansKilled > 0) {
      // هسته ای که از اجرای قبلی باز مانده بود پورت هایش را هم گرفته بود؛
      // همان چیزی که اجرای بعدی را با «already in use» می کشت.
      _log.add(
        'نمونه بازمانده از اجرای قبلی بسته شد '
        '(${Fa.num(_orphansKilled)} فرایند) تا پورت هایش آزاد شود.',
        level: 'warning',
      );
      _orphansKilled = 0;
    }
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
    await File(settingsPath).writeAsString(
      jsonEncode(
        UmbrellaCore.settingsJson(
          tun: plan.tun,
          systemProxy: plan.usesSystemProxy,
          port: plan.proxyPort > 0 ? plan.proxyPort : _umbrellaPort,
          logFile: coreLog,
          clashPort: plan.clashPort > 0
              ? plan.clashPort
              : UmbrellaCore.defaultClashPort,
        ),
      ),
      flush: true,
    );

    // با `-d` هسته همه تنظیمات را از فایل می خواند و پرچم های تونل و پورت را
    // نادیده می گیرد؛ پس فایل کامل نوشته می شود (UmbrellaCore.settingsJson) و
    // فقط مسیر فایل به آرگومان ها اضافه می شود.
    final List<String> args = <String>[...core.args, '-d', settingsPath];

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
            'پنجره Umbrella CLI باز نشد؛ هسته بدون پنجره اجرا می شود.',
            level: 'warning',
          );
        } else {
          _log.add(
            'هسته در پنجره Umbrella CLI اجرا شد: ${core.binaryName} '
            '(پورت ${Fa.num(plan.proxyPort)})',
          );
          // فرایند هسته فرزند همان پنجره است؛ با نامش سنجیده و بسته می شود.
          _runningBinaries.add(core.binaryName);
          _log.add('فایل تنظیمات هسته: $settingsPath');
          return true;
        }
      }

      // نبودِ پنجره: اجرای بی صدا با همان آرگومان ها.
      final Process process = await Process.start(
        core.exe,
        args,
        workingDirectory: core.workDir,
        runInShell: false,
      );
      final bool started = await _track(process, core, coreLog);
      _log.add('فایل تنظیمات هسته: $settingsPath');
      return started;
    } on ProcessException catch (error) {
      _log.add(
        'اجرای ${core.binaryName} ناموفق بود: ${error.message} '
        '(کد ${Fa.num(error.errorCode)})',
        level: 'error',
      );
      _log.add('مسیر هسته: ${core.exe}', level: 'error');
      _logLaunchHint(error.errorCode);
      return false;
    } on FileSystemException catch (error) {
      _log.add(
        'اجرای ${core.binaryName} ناموفق بود: ${error.message}',
        level: 'error',
      );
      _log.add('مسیر هسته: ${core.exe}', level: 'error');
      return false;
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
    final File logFile = File(coreLog);
    await logFile.parent.create(recursive: true);
    final IOSink sink = logFile.openWrite(mode: FileMode.append);
    process.stdout.listen(sink.add);
    process.stderr.listen(sink.add);

    // اگر هسته بلافاصله بسته شود، خروجی خودش دلیل را می گوید.
    final int? exited = await Future.any<int?>(<Future<int?>>[
      process.exitCode,
      Future<int?>.delayed(const Duration(milliseconds: 1500), () => null),
    ]);
    if (exited != null) {
      final String tail = await _readLogTail(coreLog);
      _log.add(
        '${core.binaryName} بلافاصله بسته شد (کد خروج ${Fa.num(exited)}).'
        '${tail.isEmpty ? '' : ' خروجی هسته: $tail'}',
        level: 'error',
      );
      // دلیل را به زبان کاربر هم می گوییم؛ خروجی خام بالا برای عیب یابی
      // می ماند، ولی خودش راه حل نمی دهد.
      final String cause = _explainCoreExit(tail);
      if (cause.isNotEmpty) {
        _log.add(cause, level: 'error');
      }
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
        _log.add(
          '${core.binaryName} بسته شد (کد خروج ${Fa.num(code)}).',
          level: 'warning',
        );
      }),
    );
    _coreProcesses[core.name] = process;
    _runningPids.add(process.pid);
    _runningBinaries.add(core.binaryName);
    _log.add('${core.binaryName} اجرا شد (شناسه ${Fa.num(process.pid)}).');
    return true;
  }

  /// دلیل بسته شدن هسته، از خروجی خودش، به زبان کاربر.
  ///
  /// در ۱٫۰٫۴ کاربر فقط «بلافاصله بسته شد» و یک دیوار متن انگلیسی می دید.
  /// اینجا همان خروجی خوانده می شود و دلیل واقعی با راه حل گفته می شود.
  static String _explainCoreExit(String output) {
    final String text = output.toLowerCase();
    if (text.contains('already in use')) {
      return 'پورت هسته پیش از این گرفته شده است؛ یعنی یک نمونه دیگر از هسته '
          '(یا یک برنامه دیگر) باز مانده است. یک بار «قطع» را بزنید و دوباره '
          'وصل شوید؛ اگر تکرار شد، UmbrellaCli.exe و UmbrellaCoreEngine.exe را '
          'در Task Manager ببندید.';
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

  /// آخرین خطوط خروجی یک هسته برای نمایش در گزارش ها.
  Future<String> _readLogTail(String path, {int maxChars = 600}) async {
    try {
      final File file = File(path);
      if (!await file.exists()) {
        return '';
      }
      final String text = await file.readAsString();
      final String compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (compact.length <= maxChars) {
        return compact;
      }
      return compact.substring(compact.length - maxChars);
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
          await Future<void>.delayed(const Duration(milliseconds: 500));
          return true;
        }
      } else {
        final TunnelStats stats = await _native.tunnelStats(hint: plan.tunnelHint);
        if (stats.available) {
          return true;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return false;
  }

  bool _verifyInFlight = false;

  /// آیا آی پی خروجی با آی پی بدون تونل فرق کرده است؟
  Future<bool> _exitIpChanged() async {
    try {
      final GeoInfo geo = await _ip.fetch(force: true);
      if (geo.ip.isEmpty) {
        return false;
      }
      if (_realIp.isEmpty) {
        return true;
      }
      return geo.ip != _realIp;
    } on Exception {
      return false;
    }
  }

  Future<void> _verifyTunnel() async {
    if (_verifyInFlight) {
      return;
    }
    _verifyInFlight = true;
    try {
      final GeoInfo geo = await _ip.fetch(
        force: true,
        proxy: _proxyPort > 0 ? '127.0.0.1:$_proxyPort' : '',
      );
      _geo = geo;
      _exitIp = geo.ip;
      // اگر آی پی بدون تونل خوانده نشده باشد، مقایسه بی معنی است و نباید
      // اتصال سالم را «ناموفق» اعلام کند (خطای ۰ سرور در شمارش پینگ).
      final bool ipKnown = _realIp.isNotEmpty;
      _tunnelVerified = geo.ip.isNotEmpty && (!ipKnown || geo.ip != _realIp);
      if (!_tunnelVerified) {
        _log.add(
          'آی پی خروجی با آی پی قبلی یکسان است؛ ممکن است تونل کامل برقرار نشده باشد.',
          level: 'warning',
        );
        // اتصالی که ترافیک از آن رد نمی شود نباید «وصل» بماند.
        if (_settings.autoFailover && _reconnectAttempts < 3) {
          _reconnectAttempts++;
          _verifyInFlight = false;
          await _reconnect();
          return;
        }
      } else {
        _log.add('آی پی خروجی: ${geo.ip} | ${geo.flagEmojiFreeLabel}');
      }
      _notify();
      if (_settings.notificationsEnabled && _tunnelVerified) {
        await _tray.balloon(
          'آی پی جدید شما',
          '${Fa.num(geo.ip)} | ${geo.flagEmojiFreeLabel}',
        );
      }
    } on Exception catch (error) {
      _log.add('بررسی آی پی ناموفق: $error', level: 'warning');
    } finally {
      _verifyInFlight = false;
    }
  }

  void _startTimers() {
    _startLiveMeasurement();
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickStats());
    _healthTimer?.cancel();
    _healthTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _tickHealth());
    _ipTimer?.cancel();
    _ipTimer = Timer.periodic(const Duration(seconds: 90), (_) {
      unawaited(_verifyTunnel());
    });
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(
      Duration(seconds: _settings.pingIntervalSeconds.clamp(120, 3600)),
      (_) => unawaited(refreshPings(all: false)),
    );
  }

  /// سنجش زنده سرور متصل. روی یک اتصال باز انجام می شود تا عدد، پینگ واقعی
  /// تونل باشد نه زمان دست دادن دوباره TCP.
  void _startLiveMeasurement() {
    _liveTimer?.cancel();
    _livePing = 0;
    _link?.close();
    // عدد اولیه پینگ سرور متصل همان لحظه خوانده می شود تا کاربر به جای
    // «در حال سنجش» یک عدد واقعی ببیند.
    final VpnNode? node = _activeNode;
    if (node != null) {
      unawaited(_measureActiveNetworkPing(node));
    }
    if (_proxyPort <= 0) {
      // در حالت تونل کامل، عدد پینگ از همان مسیر سیستم خوانده می شود.
      _liveTimer = Timer.periodic(const Duration(seconds: 5), (Timer _) {
        unawaited(_measureLiveTunnel());
      });
      unawaited(_measureLiveTunnel());
      return;
    }
    unawaited(() async {
      _link = await TunnelProbe.openLink(_proxyPort);
      await _measureLiveLink();
    }());
    _liveTimer = Timer.periodic(const Duration(seconds: 5), (Timer _) {
      unawaited(_measureLiveLink());
    });
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
      proxyPort: _proxyPort,
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
    if (!_status.active) {
      _liveSpeed = 0;
      return;
    }
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    if (_proxyPort > 0) {
      client.findProxy = (Uri _) => 'PROXY 127.0.0.1:$_proxyPort';
    }
    final Stopwatch watch = Stopwatch();
    try {
      final HttpClientRequest request = await client
          .getUrl(Uri.parse(AppConfig.speedTestUrl))
          .timeout(const Duration(seconds: 10));
      final HttpClientResponse response =
          await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode >= 300) {
        _liveSpeed = 0;
        _notify();
        return;
      }
      int bytes = 0;
      int timedOutAfter = 0;
      watch.start();
      await for (final List<int> chunk in response.timeout(
        const Duration(seconds: 8),
        onTimeout: (EventSink<List<int>> sink) => sink.close(),
      )) {
        bytes += chunk.length;
        timedOutAfter = watch.elapsedMilliseconds;
        if (timedOutAfter > 8000) {
          break;
        }
      }
      final int ms = watch.elapsedMilliseconds;
      if (bytes > 0 && ms > 0) {
        _liveSpeed = bytes * 1000 / ms;
        _speedMeasuredAt = DateTime.now();
        _log.add(
          'سنجش سرعت سرور متصل: ${Fa.speed(_liveSpeed)} '
          '(${Fa.num((bytes / 1024).round())} کیلوبایت در '
          '${Fa.num((ms / 1000).toStringAsFixed(1))} ثانیه)',
        );
      }
    } catch (error) {
      _liveSpeed = 0;
      _log.add('سنجش سرعت ناموفق بود: $error', level: 'warning');
    } finally {
      client.close(force: true);
      _notify();
    }
  }

  void _stopLiveMeasurement() {
    _liveTimer?.cancel();
    _liveTimer = null;
    _link?.close();
    _link = null;
    _livePing = 0;
    _liveSpeed = 0;
    _speedMeasuredAt = null;
  }

  Future<void> _tickStats() async {
    if (!_status.active) {
      return;
    }
    final TunnelStats raw = _proxyPort > 0
        ? TunnelStats.empty
        : await _native.tunnelStats(hint: AppConfig.tunAdapterHint);
    final int downDelta = raw.rx - _stats.rx;
    final int upDelta = raw.tx - _stats.tx;
    _stats = _stats.copyWith(
      rx: raw.rx,
      tx: raw.tx,
      available: raw.available,
      adapter: raw.adapter,
      downSpeed: downDelta > 0 ? downDelta.toDouble() : 0,
      upSpeed: upDelta > 0 ? upDelta.toDouble() : 0,
      connectedFor: _connectedAt == null
          ? Duration.zero
          : DateTime.now().difference(_connectedAt!),
    );
    if (_settings.showSpeedInTray && _connectedAt != null) {
      final int seconds = DateTime.now().difference(_connectedAt!).inSeconds;
      if (seconds % 5 == 0) {
        await _tray.update(
          state: 'connected',
          tooltip:
              '${AppConfig.appName} - ${Fa.speed(_stats.downSpeed)} / ${Fa.speed(_stats.upSpeed)}',
          connected: true,
        );
      }
    }
    _notify();
  }

  Future<void> _tickHealth() async {
    if (!_status.active) {
      return;
    }
    final VpnNode? node = _activeNode;
    if (node == null) {
      return;
    }
    final bool alive = _runningBinaries.isEmpty
        ? true
        : await _native.isRunning(_runningBinaries.first);
    if (!alive) {
      _healthFailures++;
      _log.add('هسته اتصال متوقف شد؛ تلاش برای بازیابی...', level: 'warning');
    } else {
      // زنده بودن فرایند کافی نیست؛ خود تونل هم باید جواب بدهد.
      final bool flows = await TunnelProbe.check(
        proxyPort: _proxyPort,
        attempts: 1,
        timeout: const Duration(seconds: 6),
      );
      if (flows) {
        if (_healthFailures > 0) {
          _log.add('تونل دوباره سالم شد.');
        }
        _healthFailures = 0;
        return;
      }
      _healthFailures++;
      _tunnelVerified = false;
      _log.add(
        'ترافیک از تونل رد نمی شود؛ بررسی سلامت ناموفق بود.',
        level: 'warning',
      );
      _notify();
    }
    if (_healthFailures >= 3) {
      if (_settings.autoFailover && _reconnectAttempts < 3) {
        _reconnectAttempts++;
        await _reconnect();
      } else {
        await _failAndCleanup('اتصال پایدار نماند؛ دوباره تلاش کنید.');
      }
    }
  }

  Future<void> _reconnect() async {
    _setStatus(VpnStatus.reconnecting, 'اتصال دوباره...');
    await _stopCores();
    await _disableProxy();
    await Future<void>.delayed(const Duration(seconds: 2));
    _status = VpnStatus.disconnected;
    final ConnectOutcome outcome = await connect();
    if (!outcome.ok) {
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
    _setStatus(VpnStatus.switching, 'تغییر سرور به ${node.name}...');
    await _stopCores();
    await _disableProxy();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _status = VpnStatus.disconnected;
    final ConnectOutcome outcome = await connect(requested: node);
    if (!outcome.ok) {
      await _failAndCleanup(outcome.message);
    }
    return outcome;
  }

  Future<void> disconnect({bool silent = false}) async {
    if (_status == VpnStatus.disconnected && _runningPids.isEmpty) {
      return;
    }
    _setStatus(VpnStatus.disconnecting, 'قطع اتصال...');
    await _stopCores();
    await _disableProxy();
    _statsTimer?.cancel();
    _healthTimer?.cancel();
    _ipTimer?.cancel();
    _stopLiveMeasurement();
    _connectedAt = null;
    _stats = TunnelStats.empty;
    _tunnelVerified = false;
    _exitIp = '';
    _setStatus(VpnStatus.disconnected, 'اتصال قطع شد.');
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

  Future<void> _stopCores() async {
    // اگر هسته در پنجره CLI اجرا شده باشد، اول همان بسته می شود تا هیچ هسته
    // ای بیرون از برنامه نماند و پروکسی سیستمی به حالت عادی برگردد.
    await _stopCliCore();
    await CliSession.instance.close();
    for (final Process process in _coreProcesses.values) {
      try {
        process.kill();
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
    await _stopCores();
    await _disableProxy();
    _statsTimer?.cancel();
    _healthTimer?.cancel();
    _ipTimer?.cancel();
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
    _geo = await _ip.fetch(force: true);
    _realIp = _geo.ip;
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
    _statsTimer?.cancel();
    _healthTimer?.cancel();
    _ipTimer?.cancel();
    _pingTimer?.cancel();
    unawaited(_stopCores());
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
