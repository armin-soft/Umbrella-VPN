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
import 'config_builders.dart';
import 'cores.dart';
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
  });

  final bool ok;
  final String message;
  final bool needsElevation;
  final bool needsCores;
}

class _AttemptResult {
  const _AttemptResult({
    required this.message,
    this.ok = false,
    this.needsCores = false,
  });

  final String message;
  final bool ok;
  final bool needsCores;
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

class LaunchPlan {
  const LaunchPlan({
    required this.cores,
    required this.configPaths,
    required this.readinessPort,
    required this.primaryBinary,
    required this.tunnelHint,
    required this.chained,
    this.warning = '',
    this.proxyPort = 0,
  });

  final List<CoreLaunch> cores;
  final List<String> configPaths;
  final int readinessPort;
  final String primaryBinary;
  final String tunnelHint;
  final bool chained;
  final String warning;

  /// اگر بزرگ تر از صفر باشد، هسته یک سرور پروکسی محلی روی این پورت می سازد و
  /// برنامه پروکسی سیستمی ویندوز را به آن وصل می کند.
  final int proxyPort;

  bool get usesSystemProxy => proxyPort > 0;
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
  /// کیل سوییچ مانند نسخه ویندوز هیدیفای وجود ندارد؛ همیشه خاموش است.
  bool get killSwitchOn => false;

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
    _realIp = await _ip.fetchIp(force: true);
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
    // سرور متصل از سنجش کنار گذاشته می شود: نه پینگش نمایش داده می شود و نه
    // با سنجش دوباره آزار می شود.
    final String activeId = _activeNode?.id ?? '';
    final List<VpnNode> pool =
        _nodes.where((VpnNode node) => node.id != activeId).toList();
    if (pool.isEmpty) {
      _measuring = false;
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
    // تاخیر واقعی تونل: هسته سینگ باکس هر سرور را یک بار امتحان می کند و
    // عدد دقیق را می دهد؛ اگر هسته در دسترس نباشد، نتیجه تی سی پی و آی سی
    // ام پی همان طور می ماند.
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

  /// اتصال با تلاش روی چند سرور: اگر یک سرور بالا نیامد، سرور بعدی امتحان
  /// می شود تا کاربر مجبور نشود دستی سرور عوض کند.
  Future<ConnectOutcome> connect({VpnNode? requested}) async {
    if (_status.active) {
      return const ConnectOutcome(ok: false, message: 'اتصال از قبل برقرار است.');
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
        'هیچ سروری از ${Fa.num(_nodes.length)} سرور اشتراک با هسته های همراه '
        'نسخه سازگار نبود.',
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
      final String message = _settings.corePreference == CorePreference.auto
          ? 'سروری که با این نسخه کار کند در اشتراک شما نیست.'
          : 'سروری برای هسته «${_settings.corePreference.faName}» در اشتراک '
              'شما نیست؛ هسته دیگری را انتخاب کنید.';
      _setStatus(VpnStatus.failed, message);
      return ConnectOutcome(ok: false, message: message);
    }
    _log.add(
      'درخواست اتصال: ${Fa.num(_nodes.length)} سرور در فهرست، '
      '${Fa.num(fitting.length)} سرور با هسته '
      '«${_settings.corePreference.faName}» قابل استفاده.',
    );
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
        final VpnNode candidate = candidates[index];
        if (candidates.length > 1) {
          _setStatus(
            VpnStatus.preparing,
            'تلاش ${Fa.num(index + 1)} از ${Fa.num(candidates.length)}: ${candidate.name}',
          );
        }
        final _AttemptResult attempt = await _attempt(candidate);
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
  bool _fitsPreference(VpnNode node) {
    switch (_settings.corePreference) {
      case CorePreference.auto:
        return true;
      case CorePreference.xray:
        return node.protocol != NodeProtocol.hysteria2 &&
            node.protocol != NodeProtocol.tuic &&
            node.protocol != NodeProtocol.wireguard;
      case CorePreference.clash:
        return node.protocol != NodeProtocol.mieru &&
            node.protocol != NodeProtocol.wireguard;
      case CorePreference.wireguard:
        return node.protocol == NodeProtocol.wireguard;
      case CorePreference.mieru:
        return node.protocol == NodeProtocol.mieru;
      case CorePreference.amnezia:
        return node.protocol == NodeProtocol.amnezia;
    }
  }

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
        message: 'این سرور با هسته های همراه نسخه سازگار نیست؛ سرور بعدی امتحان می شود.',
      );
    }

    // هر هسته به ترتیب امتحان می شود: سینگ باکس (همان هسته هیدیفای) و اگر
    // بالا نیامد، ایکس ری یا میرو. این طور حتی اگر یک هسته روی سیستم مشکل
    // داشته باشد، اتصال از راه دیگر برقرار می شود.
    for (final LaunchPlan plan in plans) {
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
      if (!ready) {
        final String coreLog = '${_provisioner.dataDir}'
            '${Platform.pathSeparator}run${Platform.pathSeparator}'
            '${plan.cores.first.name}-core.log';
        final String tail = await _readLogTail(coreLog);
        _log.add(
          'پورت تونل (${Fa.num(plan.readinessPort)}) در '
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
      final bool flows = plan.usesSystemProxy
          ? await TunnelProbe.check(
              proxyPort: plan.proxyPort,
              timeout: Duration(seconds: plans.length > 1 ? 6 : 8),
            )
          : await _exitIpChanged();
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

  /// پروتکل هایی که هسته های همراه نسخه پشتیبانی می کنند.
  ///
  /// سینگ باکس: وی لس، وی مس، تروجان، شادوساکس، ساکس، تی یو آی سی و
  /// هایستریا ۲ (همان هسته ای که کلاینت هیدیفای استفاده می کند)
  /// ایکس ری: وی لس، وی مس، تروجان، شادوساکس و ساکس
  /// میرو: پروتکل میرو
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
        return true;
      case NodeProtocol.clash:
      case NodeProtocol.amnezia:
        return false;
    }
  }

  /// آیا این سرور با هسته های همراه نسخه قابل استفاده است؟ سروری که شناسه یا
  /// رمزش خالی است هرگز نباید اجرا شود؛ ایکس ری با «invalid UUID» بسته می شود.
  /// هم arguments required for a usable connection are checked here so the
  /// selector never wastes a cycle on a server that cannot work.
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
      case NodeProtocol.clash:
        return false;
    }
  }

  /// فهرست نقشه های اجرا برای یک سرور، به ترتیب اولویت.
  ///
  /// سینگ باکس همان هسته ای است که کلاینت ویندوز هیدیفای استفاده می کند و
  /// پروتکل های بیشتری (از جمله تی یو آی سی و هایستریا ۲) را پوشش می دهد؛
  /// ایکس ری و میرو به عنوان پشتیبان می آیند.
  Future<List<LaunchPlan>> _buildPlans(VpnNode node) async {
    final List<LaunchPlan> plans = <LaunchPlan>[];
    final LaunchPlan? tun = await _buildTunPlan(node);
    if (tun != null) {
      plans.add(tun);
    }
    final LaunchPlan? singbox = await _buildSingBoxPlan(node);
    if (singbox != null) {
      plans.add(singbox);
    }
    final LaunchPlan? fallback = await _buildPlan(node);
    if (fallback != null) {
      plans.add(fallback);
    }
    // هسته انتخابی کاربر: فقط همان مسیر مجاز است.
    final CorePreference pref = _settings.corePreference;
    if (pref != CorePreference.auto) {
      plans.removeWhere((LaunchPlan plan) {
        final String core = plan.cores.first.name;
        switch (pref) {
          case CorePreference.xray:
            return core != 'xray' && core != 'mieru' && core != 'xrayfront';
          case CorePreference.clash:
            return core != 'singbox' && core != 'singboxtun';
          case CorePreference.mieru:
            return core != 'mieru';
          case CorePreference.wireguard:
            return core != 'singbox' && core != 'singboxtun';
          case CorePreference.amnezia:
          case CorePreference.auto:
            return false;
        }
      });
    }

    // هسته ای که آخرین بار برای همین سرور جواب داد، اول امتحان می شود تا
    // هر بار چند ثانیه صرف هسته ای نشود که با این سرور کار نمی کند.
    final String preferred = _preferredCore[node.id] ?? '';
    if (preferred.isNotEmpty && plans.length > 1) {
      plans.sort((LaunchPlan a, LaunchPlan b) {
        final bool aFirst = a.cores.first.name == preferred;
        final bool bFirst = b.cores.first.name == preferred;
        if (aFirst == bFirst) {
          return 0;
        }
        return aFirst ? -1 : 1;
      });
    }
    return plans;
  }

  /// پورت محلی که فقط برای سنجش آمادگی تونل باز می شود.
  static const int _tunReadyPort = 19091;

  /// نقشه تونل کامل: سینگ باکس یک کارت شبکه مجازی می سازد و تمام ترافیک
  /// سیستم از آن رد می شود. همان حالت پیش فرض کلاینت هیدیفای روی ویندوز؛
  /// به دسترسی مدیر نیاز دارد.
  Future<LaunchPlan?> _buildTunPlan(VpnNode node) async {
    if (!_settings.tunMode || !usable(node)) {
      return null;
    }
    if (!_device.elevated) {
      _log.add(
        'حالت تونل به دسترسی مدیر نیاز دارد؛ این بار با پروکسی سیستمی وصل '
        'می شویم. برای تونل، برنامه را با دسترسی مدیر اجرا کنید.',
        level: 'warning',
      );
      return null;
    }
    final CoreInfo? core = _provisioner.info('singbox');
    if (core == null) {
      return null;
    }
    final String? exe = await _provisioner.locateBinary(core.binary);
    if (exe == null || exe.isEmpty) {
      return null;
    }

    final Directory runDir = Directory(
      '${_provisioner.dataDir}${Platform.pathSeparator}run',
    );
    await runDir.create(recursive: true);
    final File config = File(
      '${runDir.path}${Platform.pathSeparator}singbox-tun.json',
    );
    await config.writeAsString(
      SingBoxConfig.encode(
        SingBoxConfig.build(
          node: node,
          settings: _settings,
          clashApiPort: _tunReadyPort,
        ),
      ),
      flush: true,
    );
    return LaunchPlan(
      cores: <CoreLaunch>[
        CoreLaunch(
          exe: exe,
          args: <String>['run', '-c', config.path],
          workDir: _dirOf(exe),
          name: 'singboxtun',
        ),
      ],
      configPaths: <String>[config.path],
      readinessPort: _tunReadyPort,
      primaryBinary: 'sing-box.exe',
      tunnelHint: 'Umbrella-Tunnel',
      chained: false,
    );
  }

  /// نقشه اجرای سینگ باکس: پروکسی محلی مختلط روی پورت http و اتصال به سرور.
  ///
  /// همان کاری که کلاینت هیدیفای در حالت «پروکسی سیستمی» می کند، با همان
  /// هسته و همان پروتکل ها (وی لس، وی مس، تروجان، شادوساکس، تی یو آی سی و
  /// هایستریا ۲).
  Future<LaunchPlan?> _buildSingBoxPlan(VpnNode node) async {
    // میرو پروتکل اختصاصی خودش را دارد و سینگ باکس آن را نمی شناسد.
    if (!usable(node) || node.protocol == NodeProtocol.mieru) {
      return null;
    }
    final CoreInfo? core = _provisioner.info('singbox');
    if (core == null) {
      return null;
    }
    final String? exe = await _provisioner.locateBinary(core.binary);
    if (exe == null || exe.isEmpty) {
      _log.add('هسته sing-box.exe در نسخه نصب نیست؛ هسته پشتیبان امتحان می شود.');
      return null;
    }

    final Directory runDir = Directory(
      '${_provisioner.dataDir}${Platform.pathSeparator}run',
    );
    await runDir.create(recursive: true);
    final int port = AppConfig.httpPortXray;
    final File config = File(
      '${runDir.path}${Platform.pathSeparator}singbox.json',
    );
    final Map<String, dynamic> built = node.protocol == NodeProtocol.wireguard
        ? SingBoxConfig.buildWireGuardProxy(
            node: node,
            port: port,
            mtu: _settings.mtu,
          )
        : SingBoxConfig.buildProxy(
            node: node,
            settings: _settings,
            port: port,
          );
    await config.writeAsString(SingBoxConfig.encode(built), flush: true);
    return LaunchPlan(
      cores: <CoreLaunch>[
        CoreLaunch(
          exe: exe,
          args: <String>['run', '-c', config.path],
          workDir: _dirOf(exe),
          name: 'singbox',
        ),
      ],
      configPaths: <String>[config.path],
      readinessPort: port,
      primaryBinary: 'sing-box.exe',
      tunnelHint: '',
      chained: false,
      proxyPort: port,
    );
  }

  Future<LaunchPlan?> _buildPlan(VpnNode node) async {
    _lastPlanNeedsCore = false;
    if (!supports(node)) {
      // سرورهای آمنزیا و وایرگارد با هسته های همراه این نسخه اجرا نمی شوند و
      // نباید هر بار هشدار بدهند؛ فقط یک بار در گزارش ها می آید.
      _log.add(
        'سرور ${node.name} (${node.protocol.label}) با هسته های همراه این نسخه '
        'اجرا نمی شود و از فهرست انتخاب کنار گذاشته شد.',
        level: 'info',
      );
      return null;
    }
    if (!usable(node)) {
      _log.add(
        'اطلاعات سرور ${node.name} ناقص است (شناسه یا رمز خالی)؛ کنار گذاشته شد.',
        level: 'info',
      );
      return null;
    }

    // تی یو آی سی و هایستریا ۲ را فقط سینگ باکس اجرا می کند؛ ایکس ری چنین
    // inbound هایی ندارد و پیکربندی نامعتبر می سازد.
    if (node.protocol == NodeProtocol.hysteria2 ||
        node.protocol == NodeProtocol.tuic) {
      _log.add(
        'سرور ${node.name} از پروتکل ${node.protocol.label} استفاده می کند و '
        'فقط با هسته سینگ باکس اجرا می شود؛ هسته پشتیبان برای این پروتکل نیست.',
        level: 'info',
      );
      return null;
    }

    final Directory runDir = Directory(
      '${_provisioner.dataDir}${Platform.pathSeparator}run',
    );
    await runDir.create(recursive: true);

    if (node.protocol == NodeProtocol.mieru) {
      final String? mieru = await _provisioner.locateBinary('mieru.exe');
      if (mieru == null) {
        _lastPlanNeedsCore = true;
        _log.add(
          'این سرور میرو است و هسته mieru.exe در نسخه نصب نیست.',
          level: 'error',
        );
        return null;
      }
      final File config = File('${runDir.path}${Platform.pathSeparator}mieru.json');
      await config.writeAsString(
        MieruConfig.encode(node, AppConfig.socksPortMieru),
        flush: true,
      );
      // میرو فقط سوکس می دهد؛ ایکس ری به عنوان پل اچ تی تی پی جلوی آن می
      // نشیند تا پروکسی سیستمی ویندوز واقعا کار کند.
      final String? front = await _provisioner.locateBinary('xray.exe');
      final List<CoreLaunch> cores = <CoreLaunch>[
        CoreLaunch(
          exe: mieru,
          args: <String>['run', '-c', config.path],
          workDir: _dirOf(mieru),
          name: 'mieru',
        ),
      ];
      final List<String> paths = <String>[config.path];
      int proxyPort = AppConfig.socksPortMieru;
      int readinessPort = AppConfig.socksPortMieru;
      if (front != null) {
        final File bridge =
            File('${runDir.path}${Platform.pathSeparator}mieru-front.json');
        await bridge.writeAsString(
          XrayConfig.frontSocks(AppConfig.socksPortMieru),
          flush: true,
        );
        cores.add(
          CoreLaunch(
            exe: front,
            args: <String>['run', '-c', bridge.path],
            workDir: _dirOf(front),
            name: 'xrayfront',
          ),
        );
        paths.add(bridge.path);
        proxyPort = AppConfig.httpPortXray;
        readinessPort = AppConfig.httpPortXray;
      }
      return LaunchPlan(
        cores: cores,
        configPaths: paths,
        readinessPort: readinessPort,
        primaryBinary: 'mieru.exe',
        tunnelHint: '',
        chained: front != null,
        proxyPort: proxyPort,
      );
    }

    final String? xray = await _provisioner.locateBinary('xray.exe');
    if (xray == null) {
      _lastPlanNeedsCore = true;
      _log.add(
        'هسته xray.exe پیدا نشد. مسیر جستجو: ${_provisioner.bundledDir}',
        level: 'error',
      );
      return null;
    }
    final File config = File('${runDir.path}${Platform.pathSeparator}xray.json');
    await config.writeAsString(
      XrayConfig.encode(node, AppConfig.socksPortXray),
      flush: true,
    );
    return LaunchPlan(
      cores: <CoreLaunch>[
        CoreLaunch(
          exe: xray,
          args: <String>['run', '-c', config.path],
          workDir: _dirOf(xray),
          name: 'xray',
        ),
      ],
      configPaths: <String>[config.path],
      readinessPort: AppConfig.httpPortXray,
      primaryBinary: 'xray.exe',
      tunnelHint: '',
      chained: false,
      proxyPort: AppConfig.httpPortXray,
    );
  }

  String _dirOf(String path) {
    final int index = path.lastIndexOf(Platform.pathSeparator);
    return index <= 0 ? path : path.substring(0, index);
  }

  Future<bool> _launch(LaunchPlan plan) async {
    await _stopCores();
    final String logDir = '${_provisioner.dataDir}${Platform.pathSeparator}run';
    await Directory(logDir).create(recursive: true);
    for (final CoreLaunch core in plan.cores) {
      final String coreLog =
          '$logDir${Platform.pathSeparator}${core.name}-core.log';
      Process process;
      try {
        process = await Process.start(
          core.exe,
          core.args,
          workingDirectory: core.workDir,
          runInShell: false,
        );
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
    }
    return true;
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

  static const Duration _tunnelTimeout = Duration(seconds: 15);

  Future<bool> _waitForTunnel(LaunchPlan plan) async {
    final DateTime deadline = DateTime.now().add(_tunnelTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_disposed) {
        return false;
      }
      // هسته هایی که خودمان اجرا کرده ایم را با دستگیره فرایند می سنجیم؛
      // جست وجوی نام در tasklist فقط پشتیبان است.
      final bool alive = _coreProcesses.isNotEmpty ||
          await _native.isRunning(plan.primaryBinary);
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
      _tunnelVerified = geo.ip.isNotEmpty && geo.ip != _realIp;
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
