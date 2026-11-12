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
import 'ping.dart';

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

class CoreLaunch {
  const CoreLaunch({
    required this.exe,
    required this.args,
    required this.workDir,
    required this.name,
  });

  final String exe;
  final String args;
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
  });

  final List<CoreLaunch> cores;
  final List<String> configPaths;
  final int readinessPort;
  final String primaryBinary;
  final String tunnelHint;
  final bool chained;
  final String warning;
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
        _ping = PingService(native);

  final NativeBridge _native;
  final IpService _ip;
  final SoundService _sound;
  final TrayService _tray;
  final CoreProvisioner _provisioner;
  final PingService _ping;
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

  bool _killSwitchOn = false;
  bool get killSwitchOn => _killSwitchOn;

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
      final bool active = await _native.killSwitchActive();
      if (active) {
        // اگر اجرای قبلی نیمه کاره بسته شده باشد، شبکه به حالت عادی برمی گردد.
        await _native.restoreNetworkDefaults();
      }
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
    _measuring = true;
    _pingProgressDone = 0;
    _pingProgressTotal = all ? _nodes.length : _nodes.take(12).length;
    _notify();
    final List<VpnNode> target = all ? _nodes : _nodes.take(12).toList();
    final List<VpnNode> measured = await _ping.measureAll(
      target,
      concurrency: 8,
      onProgress: (int done, int total) {
        _pingProgressDone = done;
        _pingProgressTotal = total;
        _notify();
      },
    );
    final Map<String, VpnNode> results = <String, VpnNode>{
      for (final VpnNode node in measured) node.id: node,
    };
    _nodes = _nodes
        .map((VpnNode node) => results[node.id] ?? node)
        .toList()
      ..sort(_sortNodes);
    _measuring = false;
    await _cacheNodes();
    _notify();
  }

  int _sortNodes(VpnNode a, VpnNode b) {
    if (a.hasPing != b.hasPing) {
      return a.hasPing ? -1 : 1;
    }
    if (!a.hasPing) {
      return a.name.compareTo(b.name);
    }
    return a.pingMs.compareTo(b.pingMs);
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
      Duration(seconds: settings.pingIntervalSeconds.clamp(30, 3600)),
      (_) => unawaited(refreshPings(all: false)),
    );
    _notify();
  }

  Future<ConnectOutcome> connect({VpnNode? requested}) async {
    if (_status.active) {
      return const ConnectOutcome(ok: false, message: 'اتصال از قبل برقرار است.');
    }
    if (_nodes.isEmpty) {
      return const ConnectOutcome(
        ok: false,
        message: 'هیچ سروری موجود نیست؛ ابتدا اشتراک ها را به روز کنید.',
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
              nodes: _nodes,
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
      final LaunchPlan? plan = await _buildPlan(node);
      if (plan == null) {
        _setStatus(VpnStatus.failed, 'هسته لازم در دسترس نیست.');
        onRequireCores?.call();
        return const ConnectOutcome(
          ok: false,
          needsCores: true,
          message: 'هسته اتصال در دسترس نیست؛ برنامه را با نصب کننده رسمی دوباره نصب کنید.',
        );
      }
      if (plan.warning.isNotEmpty) {
        _log.add(plan.warning, level: 'warning');
      }

      // ۳. کیل سوییچ قبل از بالا آمدن تونل
      if (_settings.killSwitch) {
        await _enableKillSwitch(plan);
      }

      _setStatus(VpnStatus.connecting, 'اجرای هسته و ساخت تونل...');
      final bool started = await _launch(plan);
      if (!started) {
        await _failAndCleanup('هسته اتصال اجرا نشد. گزارش ها را بررسی کنید.');
        return const ConnectOutcome(
          ok: false,
          message: 'اجرای هسته ناموفق بود؛ گزارش ها را بررسی کنید.',
        );
      }

      final bool ready = await _waitForTunnel(plan);
      if (!ready) {
        await _failAndCleanup('تونل در زمان مقرر بالا نیامد.');
        return const ConnectOutcome(
          ok: false,
          message: 'تونل بالا نیامد؛ سرور دیگری را امتحان کنید.',
        );
      }

      _connectedAt = DateTime.now();
      _healthFailures = 0;
      _reconnectAttempts = 0;
      _setStatus(VpnStatus.connected, 'اتصال برقرار شد. ${selection.reason}');
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
      _log.add('اتصال به ${node.name} (${node.host}:${node.port}) برقرار شد.');
      _settings = _settings.copyWith(lastNodeId: node.id);
      onSettingsChanged?.call(_settings);
      return ConnectOutcome(ok: true, message: 'اتصال برقرار شد.');
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

  Future<LaunchPlan?> _buildPlan(VpnNode node) async {
    final String? singbox = await _provisioner.locateBinary('sing-box.exe');
    if (singbox == null) {
      return null;
    }
    final String binDir = _provisioner.binDir;
    final Directory runDir = Directory(
      '${_provisioner.dataDir}${Platform.pathSeparator}run',
    );
    await runDir.create(recursive: true);

    final bool useXray = <NodeProtocol>[
      NodeProtocol.vless,
      NodeProtocol.vmess,
      NodeProtocol.trojan,
      NodeProtocol.shadowsocks,
    ].contains(node.protocol) &&
        await _provisioner.hasCore('xray');

    final bool useMieru =
        node.protocol == NodeProtocol.mieru && await _provisioner.hasCore('mieru');

    if (useXray) {
      final String? xray = await _provisioner.locateBinary('xray.exe');
      if (xray != null) {
        final File config = File('${runDir.path}${Platform.pathSeparator}xray.json');
        await config.writeAsString(
          XrayConfig.encode(node, AppConfig.socksPortXray),
          flush: true,
        );
        final File tunConfig =
            File('${runDir.path}${Platform.pathSeparator}singbox.json');
        await tunConfig.writeAsString(
          SingBoxConfig.encode(
            SingBoxConfig.build(
              node: node,
              settings: _settings,
              outboundOverride:
                  SingBoxConfig.localSocksOutbound(AppConfig.socksPortXray),
            ),
          ),
          flush: true,
        );
        return LaunchPlan(
          cores: <CoreLaunch>[
            CoreLaunch(
              exe: xray,
              args: 'run -c "${config.path}"',
              workDir: binDir,
              name: 'xray',
            ),
            CoreLaunch(
              exe: singbox,
              args: 'run -c "${tunConfig.path}"',
              workDir: binDir,
              name: 'singbox',
            ),
          ],
          configPaths: <String>[config.path, tunConfig.path],
          readinessPort: AppConfig.socksPortXray,
          primaryBinary: 'xray.exe',
          tunnelHint: AppConfig.tunAdapterHint,
          chained: true,
        );
      }
    }

    if (useMieru) {
      final String? mieru = await _provisioner.locateBinary('mieru.exe');
      if (mieru != null) {
        final File config = File('${runDir.path}${Platform.pathSeparator}mieru.json');
        await config.writeAsString(
          MieruConfig.encode(node, AppConfig.socksPortMieru),
          flush: true,
        );
        final File tunConfig =
            File('${runDir.path}${Platform.pathSeparator}singbox.json');
        await tunConfig.writeAsString(
          SingBoxConfig.encode(
            SingBoxConfig.build(
              node: node,
              settings: _settings,
              outboundOverride:
                  SingBoxConfig.localSocksOutbound(AppConfig.socksPortMieru),
            ),
          ),
          flush: true,
        );
        return LaunchPlan(
          cores: <CoreLaunch>[
            CoreLaunch(
              exe: mieru,
              args: 'run -c "${config.path}"',
              workDir: binDir,
              name: 'mieru',
            ),
            CoreLaunch(
              exe: singbox,
              args: 'run -c "${tunConfig.path}"',
              workDir: binDir,
              name: 'singbox',
            ),
          ],
          configPaths: <String>[config.path, tunConfig.path],
          readinessPort: AppConfig.socksPortMieru,
          primaryBinary: 'mieru.exe',
          tunnelHint: AppConfig.tunAdapterHint,
          chained: true,
        );
      }
    }

    final File tunConfig = File('${runDir.path}${Platform.pathSeparator}singbox.json');
    await tunConfig.writeAsString(
      SingBoxConfig.encode(
        SingBoxConfig.build(node: node, settings: _settings),
      ),
      flush: true,
    );
    final bool obfuscated = node.protocol == NodeProtocol.amnezia &&
        (node.params['jc'] != null || node.params['h1'] != null);
    return LaunchPlan(
      cores: <CoreLaunch>[
        CoreLaunch(
          exe: singbox,
          args: 'run -c "${tunConfig.path}"',
          workDir: binDir,
          name: 'singbox',
        ),
      ],
      configPaths: <String>[tunConfig.path],
      readinessPort: 0,
      primaryBinary: 'sing-box.exe',
      tunnelHint: AppConfig.tunAdapterHint,
      chained: false,
      warning: obfuscated
          ? 'این سرور آمنزیا پارامترهای مبهم سازی دارد؛ اگر اتصال برقرار نشد، هسته آمنزیا را از تنظیمات هسته ها نصب کنید.'
          : '',
    );
  }

  Future<bool> _launch(LaunchPlan plan) async {
    _runningPids.clear();
    _runningBinaries.clear();
    for (final CoreLaunch core in plan.cores) {
      final int pid = await _native.spawn(
        exe: core.exe,
        args: core.args,
        workDir: core.workDir,
      );
      if (pid <= 0) {
        _log.add('اجرای ${core.binaryName} ناموفق بود.', level: 'error');
        return false;
      }
      _runningPids.add(pid);
      _runningBinaries.add(core.binaryName);
      _log.add('${core.binaryName} اجرا شد (شناسه ${Fa.num(pid)}).');
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return true;
  }

  Future<bool> _waitForTunnel(LaunchPlan plan) async {
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline)) {
      if (_disposed) {
        return false;
      }
      final bool alive = await _native.isRunning(plan.primaryBinary);
      if (!alive) {
        return false;
      }
      if (plan.chained) {
        final int probe = await _native.tcpPing('127.0.0.1', plan.readinessPort);
        if (probe >= 0) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
          return true;
        }
      } else {
        final TunnelStats stats = await _native.tunnelStats(hint: plan.tunnelHint);
        if (stats.available) {
          return true;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  Future<void> _verifyTunnel() async {
    try {
      final GeoInfo geo = await _ip.fetch(force: true);
      _geo = geo;
      _exitIp = geo.ip;
      _tunnelVerified = geo.ip.isNotEmpty && geo.ip != _realIp;
      if (!_tunnelVerified) {
        _log.add(
          'آی پی خروجی با آی پی قبلی یکسان است؛ ممکن است تونل کامل برقرار نشده باشد.',
          level: 'warning',
        );
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
      Duration(seconds: _settings.pingIntervalSeconds.clamp(30, 3600)),
      (_) => unawaited(refreshPings(all: false)),
    );
  }

  Future<void> _tickStats() async {
    if (!_status.active) {
      return;
    }
    final TunnelStats raw = await _native.tunnelStats(hint: AppConfig.tunAdapterHint);
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
    if (alive) {
      _healthFailures = 0;
      return;
    }
    _healthFailures++;
    _log.add('هسته اتصال متوقف شد؛ تلاش برای بازیابی...', level: 'warning');
    if (_healthFailures >= 2) {
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
    if (_settings.killSwitch) {
      await _native.disableKillSwitch();
      _killSwitchOn = false;
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    _status = VpnStatus.disconnected;
    final ConnectOutcome outcome = await connect();
    if (!outcome.ok) {
      await _failAndCleanup(outcome.message);
    }
  }

  Future<void> switchTo(VpnNode node) async {
    if (_status.busy) {
      return;
    }
    if (!_status.active) {
      await connect(requested: node);
      return;
    }
    _setStatus(VpnStatus.switching, 'تغییر سرور به ${node.name}...');
    await _stopCores();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _status = VpnStatus.disconnected;
    final ConnectOutcome outcome = await connect(requested: node);
    if (!outcome.ok) {
      await _failAndCleanup(outcome.message);
    }
  }

  Future<void> disconnect({bool silent = false}) async {
    if (_status == VpnStatus.disconnected && _runningPids.isEmpty) {
      return;
    }
    _setStatus(VpnStatus.disconnecting, 'قطع اتصال...');
    await _stopCores();
    if (_killSwitchOn) {
      await _native.disableKillSwitch();
      _killSwitchOn = false;
    }
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
    for (final int pid in List<int>.of(_runningPids)) {
      await _native.killPid(pid);
    }
    for (final String binary in List<String>.of(_runningBinaries)) {
      await _native.killByName(binary);
    }
    _runningPids.clear();
    _runningBinaries.clear();
  }

  Future<void> _enableKillSwitch(LaunchPlan plan) async {
    final List<String> allowed = <String>[
      ...plan.cores.map((CoreLaunch core) => core.exe),
      await _native.exePath(),
    ].where((String path) => path.isNotEmpty).toList();
    final bool ok = await _native.enableKillSwitch(allowedExes: allowed);
    _killSwitchOn = ok;
    if (ok) {
      _log.add('کیل سوییچ روشن شد: فقط ترافیک تونل اجازه عبور دارد.');
    } else {
      _log.add('روشن کردن کیل سوییچ ناموفق بود.', level: 'warning');
    }
  }

  Future<void> _failAndCleanup(String reason) async {
    await _stopCores();
    if (_killSwitchOn) {
      await _native.disableKillSwitch();
      _killSwitchOn = false;
    }
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

  Future<void> rebuildKillSwitch() async {
    if (!_killSwitchOn) {
      return;
    }
    await _native.disableKillSwitch();
    _killSwitchOn = false;
    if (_settings.killSwitch) {
      final VpnNode? node = _activeNode;
      if (node == null) {
        return;
      }
      final LaunchPlan? plan = await _buildPlan(node);
      if (plan != null) {
        await _enableKillSwitch(plan);
      }
    }
  }

  Future<void> restoreNetwork() async {
    await _native.restoreNetworkDefaults();
    _killSwitchOn = false;
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
