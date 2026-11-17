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
import '../core/network_redaction.dart';
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
import 'speed_test.dart';
import 'verified_probe.dart';

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

  /// سرورهایی که در همین تلاش اتصال با خطای «قابل اجرا نبود» رد شده اند.
  ///
  /// هسته ای که سروری را نمی تواند بسازد، با تلاش دوباره هم نمی تواند؛ پیش
  /// از این همان سرور چهار بار پشت سر هم امتحان می شد و کاربر فقط «×(۴)»
  /// می دید (گزارش ۱٫۰۶). این مجموعه در هر connect پاک می شود.
  final Set<String> _unusableInThisRun = <String>{};
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

  /// چند سرور در هر دور با خود هسته سنجیده می شود.
  ///
  /// هر نمونه یک فرایند هسته است و دو پورت ثابت هسته را می گیرد؛ سنجیدن همه
  /// ۲۴ سرور چند دقیقه طول می کشید و در آن مدت اتصال ممکن نبود. دور اول روی
  /// ۸ سرور است، دورهای بعدی بقیه را هم می سنجند.
  int _tunnelProbeCount = 8;

  /// آیا خبر «نتیجه نداد» یک بار گفته شده است؟
  bool _tunnelFailureReported = false;

  Future<void> refreshPings({bool all = true}) async {
    if (_measuring || _nodes.isEmpty) {
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
      // سنجش خودش مهلت دارد و نمونه هایش را می بندد؛ `Future.timeout` این
      // کار را نمی کرد و هسته های یتیم، پورت ۱۷۰۷۸ را تا اتصال بعدی گرفته
      // نگه می داشتند.
      tunnelDelays = await _corePing.measure(
        target,
        settings: _settings,
        maxNodes: _tunnelProbeCount,
        budget: const Duration(seconds: 60),
      );
    } catch (_) {
      tunnelDelays = <String, int>{};
    }
    // اگر اتصال در این میان شروع شده باشد، سنجش را خودمان بستیم؛ گزارش
    // «تاخیر تونل برای ۰ سرور» آن وقت فقط گیج کننده است.
    if (_status.active) {
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
    await _cacheNodes();
    // تنها وقتی خبری برای گفتن هست که چیزی به دست نیامده باشد؛ و آن هم یک
    // بار، نه هر دو دقیقه یک بار. پینگ شبکه ای که در فهرست آمده، عدد کاربر
    // را دارد و همین کافی است.
    if (tunnelDelays.isNotEmpty) {
      // سنجش دوباره کار می کند؛ اگر بعداً یک بار دیگر نتیجه نداد، همان یک بار
      // گزارش می شود.
      _tunnelFailureReported = false;
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
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 4));
    while (DateTime.now().isBefore(deadline)) {
      final List<int> held = await UmbrellaCore.heldReservedPorts();
      if (held.isEmpty) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
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
      (_) {
        // در حین اتصال یا پس از آن، عدد زنده همان اتصال خوانده می شود؛
        // بالا آوردن هسته سنجش، خود اتصال را می کشت.
        if (_status.active) {
          return;
        }
        unawaited(refreshPings(all: false));
      },
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
    // فقط یک اتصال همزمان.
    //
    // در گزارش ۱٫۰۱۲ دو «درخواست اتصال» با سه ثانیه فاصله آمد و هر دو
    // اجرا شدند. هر کدام هسته خودش را بالا می آورد، هر دو پورت ثابت ۱۷۰۷۸ را
    // می خواستند، و نتیجه اش همان «port 17078 is already in use» پشت سر هم و
    // کشته شدن هسته ای بود که تازه کار کرده بود. `_status.active` اینجا کافی
    // نیست چون وضعیت تا وقتی به `preparing` نرسیده هنوز `disconnected` است.
    if (_connectInFlight) {
      return const ConnectOutcome(
        ok: false,
        message: 'یک اتصال در حال انجام است؛ چند لحظه صبر کنید.',
      );
    }
    if (_status.active) {
      return const ConnectOutcome(ok: false, message: 'اتصال از قبل برقرار است.');
    }
    _connectInFlight = true;
    try {
      return await _connectInner(requested: requested);
    } finally {
      _connectInFlight = false;
    }
  }

  Future<ConnectOutcome> _connectInner({VpnNode? requested}) async {
    _cancelRequested = false;
    // سنجش در جریان همین حالا بسته می شود: نمونه هایش پورت های ثابت هسته
    // (۱۷۰۷۸ و ۱۶۷۵۶) را گرفته اند و اتصال بدون آن ها ممکن نیست.
    await _stopProbes();
    // دسترسی حساب: اشتراک منقضی، مسدود یا تمام شده حق اتصال ندارد.
    final String blocked = accessGuard?.call() ?? '';
    if (blocked.isNotEmpty) {
      _log.add('اتصال رد شد: $blocked', level: 'warning');
      _setStatus(VpnStatus.failed, blocked);
      return ConnectOutcome(ok: false, message: blocked, needsRenewal: true);
    }
    final String? chainError = _settings.chain.enabled ? _settings.chain.validationError : null;
    final String? routeError = _settings.appRoutes
        .map((AppRouteRule rule) => rule.validationError).whereType<String>().firstOrNull;
    if (chainError != null || routeError != null || _settings.appRoutes.length > 64) {
      return ConnectOutcome(ok: false, message: chainError ?? routeError ?? 'حداکثر ۶۴ قانون برنامه مجاز است');
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
      return const ConnectOutcome(
        ok: false,
        message: 'سروری که با این نسخه کار کند در اشتراک شما نیست.',
      );
    }

    final List<VpnNode> regionalNodes =
        usableNodes.where(_matchesServerRegion).toList();
    if (regionalNodes.isEmpty) {
      final String region = _serverRegionLabel(_settings.serverRegionCode);
      final String message = 'در منطقه $region سرور سازگار و فعالی پیدا نشد.';
      _setStatus(VpnStatus.failed, message);
      return ConnectOutcome(ok: false, message: message);
    }
    final List<VpnNode> fitting = regionalNodes
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

      _unusableInThisRun.clear();
      final List<VpnNode> candidates = _candidates(node, selection.reason);
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
            'بودجه زمانی اتصال تمام شد: ${Fa.num(attempted)} سرور از '
            '${Fa.num(candidates.length)} سرور اشتراک امتحان شد و هیچ '
            'کدام تونل نساخت.',
            level: 'warning',
          );
          break;
        }
        final VpnNode candidate = candidates[index];
        if (candidates.length > 1) {
          _setStatus(
            VpnStatus.preparing,
            'تلاش ${Fa.num(index + 1)} از ${Fa.num(candidates.length)}: ${candidate.name}',
          );
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

  /// آیا کشور این سرور با فیلتر منطقه انتخاب شده هماهنگ است؟
  bool _matchesServerRegion(VpnNode node) {
    final String selected = _settings.serverRegionCode;
    if (selected == 'all' || selected.isEmpty) return true;
    final String code = node.flagCode.toLowerCase();
    if (selected == 'unknown') return code.isEmpty;
    return code == selected.toLowerCase();
  }

  static String _serverRegionLabel(String code) {
    if (code == 'unknown') return 'نامشخص';
    if (code == 'all' || code.isEmpty) return 'همه کشورها';
    return countryNameFa(code).isEmpty ? code.toUpperCase() : countryNameFa(code);
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
    if (_settings.selectionMode == SelectionMode.manual ||
        !_settings.autoFailover) {
      return list;
    }
    final List<VpnNode> rest = _nodes
        .where((VpnNode node) =>
            node.id != first.id &&
            !node.disabled &&
            usable(node) &&
            !_unusableInThisRun.contains(node.id) &&
            _matchesServerRegion(node) &&
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
                _matchesServerRegion(candidate) &&
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
      // پیش از هر تلاش، پورت های هسته آزاد می شوند.
      //
      // تا ۱٫۰٫۱۰ این کار فقط یک بار در ابتدای اتصال انجام می شد. وقتی تلاش
      // اول شکست می خورد و هسته قبلی هنوز در حال خاموش شدن بود، تلاش دوم و
      // سوم و چهارم همگی با «port 17078 is already in use» برمی گشتند؛ یعنی
      // هر بار همان پورت خودمان جلوی خودمان را می گرفت.
      await _stopCores();
      final bool portFree = await _freeCorePortsWithRetry();
      if (!portFree) {
        _log.add(
          'پورت هسته پیش از تلاش بعدی آزاد نشد؛ این حالت امتحان نمی شود.',
          level: 'warning',
        );
        continue;
      }
      _setStatus(VpnStatus.connecting, 'اجرای هسته و ساخت تونل...');
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
            node: node,
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
        continue;
      }

      // Open sockets, byte counters and dial log entries are not evidence of
      // successful traffic. Require authenticated HTTPS with an expected body.
      final Duration probeTimeout = Duration(seconds: _activeChain.enabled ? 30 : 8);
      final bool proxyFlows = await VerifiedProbe.check(proxyPort: _umbrellaPort, timeout: probeTimeout);
      final bool flows = proxyFlows && (!plan.tun ||
          await VerifiedProbe.check(proxyPort: 0, timeout: probeTimeout));
      if (_cancelRequested) {
        await _stopCores();
        await _disableProxy();
        return const _AttemptResult(cancelled: true, message: 'اتصال لغو شد.');
      }
      if (!flows) {
        final String coreLog = '${_provisioner.dataDir}'
            '${Platform.pathSeparator}run${Platform.pathSeparator}'
            '${plan.cores.first.name}-core.log';
        final String tail = await _readLogTail(coreLog);
        _log.add(
          'هسته بالا آمد ولی سنجش HTTPS پاسخ معتبر نگرفت؛ اتصال تأیید نشد.'
          '${tail.isEmpty ? '' : ' خروجی هسته: $tail'}',
          level: 'error',
          details: await _coreDiagnostics(
            plan.cores.first,
            coreLog,
            plan: plan,
            node: node,
          ),
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
            details: <LogDetail>[
              LogDetail(
                title: 'تنظیم پروکسی ویندوز',
                text: <String>[
                  'آدرس پروکسی: 127.0.0.1:${Fa.num(plan.proxyPort)}',
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
      }
      _connectedAt = DateTime.now();
      _healthFailures = 0;
      _reconnectAttempts = 0;
      _setStatus(VpnStatus.connected, 'اتصال برقرار شد.');
      _balancer.markConnected(node.id);
      _startTimers();
      await _sound.play('connect');
      // نام سرور در سینی ویندوز و اعلان نمی آید.
      //
      // کاربر خواست پس از اتصال هیچ جا نام سرور دیده نشود، فقط «به آمبرلا
      // متصل شد»؛ جزئیات سرور فقط در گزارش ها می ماند. اعلان هم پینگ واقعی
      // را می گوید، نه پینگ لحظه انتخاب.
      await _tray.update(
        state: 'connected',
        tooltip: '${AppConfig.appName} - متصل شد',
        connected: true,
      );
      // آی پی خروجی از سطر MONITORING خود هسته؛ اگر خوانده نشود، سنجش وب
      // جای آن را می گیرد.
      final String coreIp = await _coreExitIp(_coreLogPath(plan));
      if (coreIp.isNotEmpty) {
        _log.add('آی پی خروجی از گزارش هسته: $coreIp');
        _notify();
      }
      if (_settings.notificationsEnabled) {
        final int shownPing = activePingMs > 0 ? activePingMs : node.pingMs;
        await _tray.balloon(
          'به آمبرلا متصل شد',
          shownPing > 0 ? 'پینگ ${Fa.ms(shownPing)}' : 'اتصال امن برقرار است',
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
      port: _umbrellaPort,
      tun: tun,
      systemProxy: !tun,
      logLevel: CoreLogLevel.normalize(_settings.logLevel),
    );
  }

  /// لینک سرور برای دادن به هسته (برای سنجش پینگ و پنجره CLI هم استفاده
  /// می شود).
  static String linkFor(VpnNode node) {
    final String raw = node.raw.trim();
    if (raw.contains('://')) {
      return _normalizeLegacyTransportLink(raw);
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
  String _umbrellaLink(VpnNode node) => linkFor(node);

  /// چند لینک برای دادن به هسته، به ترتیب اولویت.
  ///
  /// سرور انتخاب شده همیشه اول است، پس اگر خود هسته هم چیزی انتخاب نکند،
  /// همان گره ای می شود که کاربر خواسته. بعد از آن، همه سرورهای دیگری که
  /// با این هسته کار می کنند می آیند تا خود هسته بتواند بینشان سنجش کند،
  /// سریع ترین را نگه دارد و هنگام افتادن یکی، به بعدی سوییچ کند — همان
  /// کاری که کاربر از یک فیلترشکن انتظار دارد.
  ///
  /// بیشترین تعداد لینکی که در یک اجرا به هسته داده می شود.
  ///
  /// **شکایت کاربر (۱٫۰٫۱۹):** این عدد تا ۱٫۰٫۱۹ روی ۳۰ بود، پس از ۳۳۱
  /// سرور اشتراک فقط ۳۰ تای اول (بعد از مرتب سازی بر اساس پینگ) به هسته
  /// می رسید و خود هسته هم نمی توانست سرورهای دیگر را امتحان کند. حالا این
  /// عدد فقط یک سقف ایمنیتی برای اشتراک های بی نهایت بزرگ است، نه سقف
  /// رفتاری: هر لینک معتبر اشتراک — از هر منبع، از جمله لینک های ایکس ری —
  /// در فایل لینک هسته می آید تا خود هسته همه را با `lowest-delay` بسنجد.
  /// `keep-top` هم چند گره زنده نگه می دارد، ولی سنجش روی همه انجام می شود.
  static const int _maxPoolLinks = 1000;

  List<String> _linkPool(VpnNode chosen) {
    final List<String> pool = <String>[];
    final Set<String> seen = <String>{};

    void add(VpnNode n) {
      if (pool.length >= _maxPoolLinks) {
        return;
      }
      if (!usable(n)) {
        return;
      }
      final String link = linkFor(n).trim();
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
      final String key = link.split('#').first;
      if (!seen.add(key)) {
        return;
      }
      pool.add(link);
    }

    add(chosen);
    // بعد از انتخاب فعلی، پین ها اول به هسته داده می شوند تا در مجموعه
    // keep-top شانس ماندن داشته باشند؛ سپس بقیه سرورها به ترتیب پینگ می آیند.
    final List<VpnNode> rest = _nodes
        .where((VpnNode n) =>
            n.id != chosen.id &&
            !n.disabled &&
            n != chosen &&
            _matchesServerRegion(n))
        .toList()
      ..sort((VpnNode a, VpnNode b) {
        final int pa = a.pingMs <= 0 ? 1 << 30 : a.pingMs;
        final int pb = b.pingMs <= 0 ? 1 << 30 : b.pingMs;
        if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
        return pa.compareTo(pb);
      });
    for (final VpnNode n in rest) {
      add(n);
    }
    if (pool.length >= _maxPoolLinks) {
      _log.add(
        'اشتراک لینک بیشتری دارد ولی فایل لینک هسته به سقف '
        '${Fa.num(_maxPoolLinks)} لینک رسید؛ سرور انتخاب شده و کم پینگ '
        'ترین ها به هسته داده می شوند.',
        level: 'warning',
      );
    }
    // اگر هیچ کدام سازگار نبود، لااقل همان یکی.
    return pool.isEmpty ? <String>[linkFor(chosen).trim()] : pool;
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
    // ریلیتی: بدون این پارامترها دست‌دادن TLS انجام نمی شود. `fp` پایین تر
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
        // تله‌ای که ۱٫۰٫۱۰ را شکست: در منابع کلش، `type` نام **پروتکل** است
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
    _lastLaunchUnusable = false;
    await _stopCores();
    // _freeCorePorts خودش دلیل و نتیجه را گزارش می کند، پس اینجا تکرار
    // نمی شود.
    if (!await _freeCorePorts()) {
      return false;
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
    _activeChain = _settings.chain;
    if (_activeChain.licenseKey.isNotEmpty) _networkSecrets.add(_activeChain.licenseKey);
    await File(settingsPath).writeAsString(
      jsonEncode(
        UmbrellaCore.settingsJson(
          tun: plan.tun,
          systemProxy: plan.usesSystemProxy,
          port: plan.proxyPort > 0 ? plan.proxyPort : _umbrellaPort,
          logFile: coreLog,
          networkSettings: _settings,
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

  /// توضیح اینکه چرا هیچ سروری برای اجرا قبول نشد.
  String _whyNoUsableServer() {
    final List<VpnNode> disabled =
        _nodes.where((VpnNode node) => node.disabled).toList();
    final List<VpnNode> noHost =
        _nodes.where((VpnNode node) => node.host.trim().isEmpty).toList();
    final List<VpnNode> notUsable =
        _nodes.where((VpnNode node) => !usable(node)).toList();
    return <String>[
      'کل سرورها: ${Fa.num(_nodes.length)}',
      'غیرفعال شده: ${Fa.num(disabled.length)}',
      'بدون میزبان: ${Fa.num(noHost.length)}',
      'پروتکل پشتیبانی نشده: ${Fa.num(notUsable.length)}',
      if (notUsable.isNotEmpty)
        'اولین سرور پشتیبانی نشده: ${notUsable.first.name} '
            '(${notUsable.first.protocol.name})',
    ].join('\n');
  }

  /// چند سرور از هر پروتکل در اشتراک هست.
  String _protocolBreakdown() {
    final Map<String, int> counts = <String, int>{};
    for (final VpnNode node in _nodes) {
      counts[node.protocol.name] = (counts[node.protocol.name] ?? 0) + 1;
    }
    if (counts.isEmpty) {
      return 'هیچ سروری خوانده نشده است.';
    }
    final List<String> rows = counts.entries
        .map((MapEntry<String, int> e) => '${e.key}: ${Fa.num(e.value)}')
        .toList()
      ..sort();
    return rows.join('\n');
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
      return 'هست (${mb.toStringAsFixed(1)} مگابایت، آخرین تغییر: '
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

    // اگر هسته بلافاصله بسته شود، خروجی خودش دلیل را می گوید.
    final int? exited = await Future.any<int?>(<Future<int?>>[
      process.exitCode,
      Future<int?>.delayed(const Duration(milliseconds: 1500), () => null),
    ]);
    if (exited != null) {
      await _reportCoreExit(core, coreLog, exited);
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

  /// آزادسازی پورت های هسته با تلاش دوباره، پیش از اجرای هسته.
  ///
  /// **گزارش ۱٫۰۱۸:** `_freeCorePorts` صاحب پورت را بست و پورت را «آزاد»
  /// خواند، ولی هسته تازه بلافاصله با `port 17078 is already in use` مرد.
  /// ویندوز پس از `TerminateProcess` چند صد میلی ثانیه پورت را در TIME_WAIT
  /// نگه می دارد و فرزندِ در حال مرگ هم هنوز گوش می دهد. آزاد بودن فهرست
  /// بلافاصله بعد از kill، تضمین آزاد بودن هنگام اجرا نیست. پس: چند تلاش،
  /// با فاصله فزاینده، و در هر تلاش فهرست واقعی دوباره خوانده می شود.
  Future<bool> _freeCorePortsWithRetry() async {
    const List<Duration> gaps = <Duration>[
      Duration(milliseconds: 250),
      Duration(milliseconds: 500),
      Duration(milliseconds: 900),
      Duration(seconds: 2),
    ];
    for (int attempt = 0; attempt < gaps.length; attempt++) {
      if (await _freeCorePorts()) {
        // یک بار دیگر بعد از مکث کوتاه تایید می شود؛ اگر همان لحظه کسی
        // پورت را گرفت، دور بعدی.
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (await UmbrellaCore.heldReservedPorts().then(
              (List<int> held) => held.isEmpty,
            )) {
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
    final List<int> appHeld = await _heldPorts(UmbrellaCore.appPorts);
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

  /// کدام یک از این پورت ها همین حالا گرفته اند.
  Future<List<int>> _heldPorts(List<int> ports) async {
    final List<int> held = <int>[];
    for (final int port in ports) {
      if (await UmbrellaCore.inUse(port)) {
        held.add(port);
      }
    }
    return held;
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
    int code,
  ) async {
    final String full = await _readLogFull(coreLog);
    if (_stoppingOwnCore && code == 0) {
      // بستن عمدی خودمان؛ این «خرابی» نیست و نباید در گزارش خطا بیاید.
      _lastLaunchUnusable = false;
      return;
    }
    final String tail = await _readLogTail(coreLog);
    _log.add(
      '${core.binaryName} بلافاصله بسته شد (کد خروج ${Fa.num(code)}).'
      '${tail.isEmpty ? '' : ' خروجی هسته: $tail'}',
      level: 'error',
      details: await _coreDiagnostics(core, coreLog, code: code),
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
    VpnNode? node,
  }) async {
    final List<LogDetail> details = <LogDetail>[];

    // ۱. خروجی کامل هسته؛ مهمترین چیز برای فهمیدن دلیل.
    final String full = (await _readLogFull(coreLog)).trim();
    details.add(
      LogDetail(
        title: 'خروجی کامل هسته (${core.name})',
        text: full.isEmpty
            ? 'هسته هیچ خروجی‌ای نداد. یعنی پیش از نوشتن هر خطی بسته شد؛ '
                'بیشتر وقت ها دلیلش نبود دسترسی، آنتی ویروس یا فایل اجرایی '
                'ناقص است.'
            : full,
      ),
    );

    // ۲. فرمان اجرا و مسیرها؛ برای بازتولید همان اجرا بیرون از برنامه.
    details.add(
      LogDetail(
        title: 'فرمان اجرا و مسیرها',
        text: <String>[
          'برنامه: ${core.binaryName}',
          'مسیر: ${core.exe}',
          'پوشه اجرا: ${core.workDir}',
          'فایل گزارش هسته: $coreLog',
          if (plan != null) 'فایل لینک سرور: ${plan.linksPath}',
          if (plan != null) 'حالت اتصال: ${plan.tun ? 'تونل کامل' : 'پروکسی سیستمی'}',
          if (plan != null && plan.proxyPort > 0)
            'پورت محلی: ${Fa.num(plan.proxyPort)}',
          if (code != null) 'کد خروج: ${Fa.num(code)}',
        ].join('\n'),
      ),
    );

    // ۳. سروری که با آن تلاش شد؛ بدون رمز و شناسه، فقط آنچه برای تشخیص لازم
    // است. نام و میزبان برای پیدا کردن سرور مشکل دار کافی است.
    if (node != null) {
      details.add(
        LogDetail(
          title: 'سروری که با آن تلاش شد',
          text: <String>[
            'نام: ${node.name}',
            'پروتکل: ${node.protocol.name}',
            'میزبان: ${node.host}',
            'پورت: ${Fa.num(node.port)}',
          ].join('\n'),
        ),
      );
    }

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

  /// A failed endpoint race is retried by the existing health-failure counter;
  /// neither transmitted bytes nor a stale core log can override it.
  Future<bool> _tunnelFlowsNow() async {
    final bool proxy = await VerifiedProbe.check(proxyPort: _umbrellaPort,
        timeout: const Duration(seconds: 6));
    return proxy && (_proxyPort > 0 || await VerifiedProbe.check(proxyPort: 0,
        timeout: const Duration(seconds: 6)));
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
      return last;
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
          await Future<void>.delayed(const Duration(milliseconds: 500));
          return true;
        }
      } else {
        // کارت شبکه تونل، همان چیزی که هسته در اولین ثانیه می سازد
        // (`inbound/tun[tun-in]: started at tun0`). اینجا فقط «ساخته شد یا
        // نه» سنجیده می شود؛ عبور ترافیک کار سنجش بعدی است. پیش از این،
        // انتظار ۲۵ ثانیه ای برای کارت، اتصال سالم را هم رد می کرد.
        final TunnelStats stats = await _native.tunnelStats(hint: plan.tunnelHint);
        if (stats.available) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          return true;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return false;
  }

  bool _verifyInFlight = false;

  /// آیا ترافیک واقعاً از تونل **برگشت**؟
  ///
  /// این سنجش با خواندن شمارنده کارت شبکه فرق دارد: یک درخواست HTTP کامل
  /// (درخواست + پاسخ) می فرستد و منتظر **بدنه پاسخ** می ماند. اگر پاسخ
  /// برگشت، تونل واقعاً کار می کند؛ اگر فقط ارسال زیاد شد و پاسخی نیامد،
  /// تونل مرده است — همان چیزی که در گزارش ۱٫۰۱۷ «متصل ولی هیچی باز نمی
  /// کند» را ساخت.
  ///
  /// نشانی ها همان `generate_204` هستند: سبک، بدون بدنه بزرگ و در بیشتر
  /// شبکه ها باز. فقط پاسخ HTTPS معتبر با محتوای مورد انتظار پذیرفته است.
  Future<bool> _trafficReturns({Duration timeout = const Duration(seconds: 8)}) async {
    final bool proxy = await VerifiedProbe.check(proxyPort: _umbrellaPort,
        minimumSuccesses: 2, timeout: timeout);
    return proxy && (_proxyPort > 0 || await VerifiedProbe.check(proxyPort: 0, timeout: timeout));
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
      // اگر آی پی خوانده نشد، این هیچ چیزی را درباره تونل ثابت نمی کند.
      //
      // در گزارش ۱٫۰۱۲ همین حالت تونل سالم را کشت: اتصال برقرار شد، ولی
      // سرویس های خواندن آی پی (ipinfo/ip-api/…) از مسیر تونل جواب ندادند،
      // `geo.ip` خالی ماند و کد آن را «آی پی خروجی با آی پی قبلی یکسان است»
      // خواند و `_reconnect()` را صدا زد. یعنی خودمان تونل درست را کشتیم.
      // خوانده نشدن آی پی یک ناشناخته است، نه یک شکست.
      if (geo.ip.isEmpty) {
        // آی پی خوانده نشد. این به خودی خود شکست نیست، ولی **نشانه** است:
        // اگر تونل کار کند، درخواست ما از مسیرش بیرون می رود و پاسخ می آید.
        // پس یک سنجش عبور ترافیک می کنیم تا معلوم شود تونل زنده است یا نه.
        //
        // در گزارش ۱٫۰۱۷ سه بار همین پیام آمد و کاربر گفت «متصل هست ولی
        // هیچی باز نمی کند»: تونل مرده بود، ولی ما فقط هشدار می دادیم و
        // همان گره مرده را نگه می داشتیم.
        final bool alive = await _trafficReturns();
        if (alive) {
          _log.add(
            'آی پی خروجی خوانده نشد، ولی ترافیک واقعی از تونل برگشت؛ '
            'اتصال معتبر است.',
            level: 'warning',
          );
          _tunnelVerified = true;
          _notify();
          return;
        }
        // ترافیکی برنگشت: این گره واقعاً کار نمی کند.
        _tunnelVerified = false;
        _log.add(
          'آی پی خروجی خوانده نشد و ترافیکی هم از تونل برنگشت؛ '
          'این سرور کار نمی کند و سرور بعدی امتحان می شود.',
          level: 'error',
        );
        _notify();
        if (_settings.autoFailover && _reconnectAttempts < 3) {
          _reconnectAttempts++;
          _verifyInFlight = false;
          await _reconnect();
        }
        return;
      }
      // اگر آی پی بدون تونل خوانده نشده باشد، مقایسه بی معنی است و نباید
      // اتصال سالم را «ناموفق» اعلام کند (خطای ۰ سرور در شمارش پینگ).
      final bool ipKnown = _realIp.isNotEmpty;
      final bool ipChanged = !ipKnown || geo.ip != _realIp;
      // **گزارش «وصل میشه الکی»:** تا ۱٫۰۱۸ فقط تغییر نکردن آی پی بررسی می
      // شد. یعنی اگر آی پی عوض می شد، اتصال «تایید شده» اعلام می شد حتی اگر
      // هیچ درخواستی از تونل رد نمی شد. حالا عبور واقعی ترافیک هم شرط است:
      // دو پاسخ ۲xx مستقل. اگر تونل جواب ندهد، پرچم تایید برداشته می شود و
      // در صورت فعال بودن جابه جایی خودکار، گره بعدی امتحان می شود.
      final bool passes = await _trafficReturns();
      _tunnelVerified = ipChanged && passes;
      if (!ipChanged) {
        _log.add(
          'آی پی خروجی با آی پی قبلی یکسان است؛ ممکن است تونل کامل برقرار نشده باشد.',
          level: 'warning',
        );
      } else if (!passes) {
        _log.add(
          'آی پی خروجی عوض شد (${Fa.num(geo.ip)}) ولی هیچ درخواستی از تونل '
          'برنگشت؛ این اتصال معتبر نیست و سرور بعدی امتحان می شود.',
          level: 'error',
        );
      }
      if (!_tunnelVerified) {
        _notify();
        // اتصالی که ترافیک از آن رد نمی شود نباید «وصل» بماند.
        if (_settings.autoFailover && _reconnectAttempts < 3) {
          _reconnectAttempts++;
          _verifyInFlight = false;
          await _reconnect();
          return;
        }
      } else {
        _log.add('آی پی خروجی: ${Fa.num(geo.ip)} | ${geo.flagEmojiFreeLabel}');
      }
      _notify();
      if (_settings.notificationsEnabled && _tunnelVerified) {
        // نام کشور از کد دوحرفی و به فارسی؛ `countryLabel` ممکن است نام
        // انگلیسی سرویس (مثل `Iran`) باشد و کاربر فارسی خواسته است.
        final String where = countryNameFa(geo.flagCode);
        await _tray.balloon(
          'آی پی جدید شما',
          where.isEmpty
              ? Fa.num(geo.ip)
              : '${Fa.num(geo.ip)} | $where',
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
      proxyPort: _umbrellaPort,
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
    if (_status != VpnStatus.connected || _speedRunner != null ||
        (accessGuard?.call() ?? '').isNotEmpty) return;
    final SpeedTestRunner runner = SpeedTestRunner();
    _speedRunner = runner;
    _speedResult = null;
    _speedError = '';
    _liveSpeed = 0;
    _speedMeasuredAt = null;
    _notify();
    try {
      final SpeedTestResult result = await runner.run(
        // The loopback mixed listener stays enabled in TUN mode too. Never
        // measure through a system route which could escape during disconnect.
        proxyPort: _umbrellaPort,
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
      //
      // Three consecutive failed races are required before failover. A raw
      // byte counter or dial log cannot override failed HTTPS validation.
      final bool flows = await _tunnelFlowsNow();
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
    // سنجشی که بعد از قطع اتصال شروع شود، هسته ای بالا می آورد و پورت ها را
    // می گیرد؛ همان چیزی که اتصال بعدی را رد می کرد.
    await _stopProbes();
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
    cancelSpeedTest();
    _activeChain = const ChainSettings();
    _stoppingOwnCore = true;
    try {
      await _stopCoresInner();
    } finally {
      _stoppingOwnCore = false;
    }
  }

  Future<void> _stopCoresInner() async {
    await _sweepOrphanChildren();
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
    } on Exception {
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
