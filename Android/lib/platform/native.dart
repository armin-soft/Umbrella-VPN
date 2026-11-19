import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/utils.dart';
import '../models/models.dart';

/// پاسخ درخواست HTTP بومی اندروید (BoringSSL + مخزن گواهی سیستم).
class NativeHttpResponse {
  const NativeHttpResponse({
    required this.ok,
    required this.statusCode,
    required this.bodyBytes,
    this.contentType = '',
    this.winError = 0,
    this.error = '',
  });

  final bool ok;
  final int statusCode;
  final Uint8List bodyBytes;
  final String contentType;
  final int winError;
  final String error;
}

/// نتیجه راه اندازی سرویس تونل اندروید.
class AndroidCoreStartResult {
  const AndroidCoreStartResult({
    required this.ok,
    this.state = '',
    this.error = '',
    this.permissionDenied = false,
  });

  final bool ok;
  final String state;
  final String error;
  final bool permissionDenied;
}

/// مشخصات یک برنامه نصب شده روی اندروید برای مسیریابی انتخابی.
class InstalledAndroidApp {
  const InstalledAndroidApp({
    required this.packageName,
    required this.appName,
    this.isSystem = false,
  });

  final String packageName;
  final String appName;
  final bool isSystem;
}

/// پل ارتباط فلاتر با سرویس تونل و امکانات بومی اندروید.
class NativeBridge {
  NativeBridge();

  static const MethodChannel _channel = MethodChannel('ir.umbrella.app/native');
  static const EventChannel _trayChannel = EventChannel('ir.umbrella.app/tray');

  bool _available = true;
  bool get available => _available;

  String _lastError = '';
  String get lastError => _lastError;

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    if (!_available) {
      return null;
    }
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException catch (error) {
      _available = false;
      _lastError = 'MissingPluginException: ${error.message ?? method}';
      return null;
    } on PlatformException catch (error) {
      _lastError = '${error.code}: ${error.message ?? method}';
      return null;
    }
  }

  Future<int> _dartTcpPing(String host, int port, int timeoutMs) async {
    final Stopwatch watch = Stopwatch()..start();
    try {
      final Socket socket = await Socket.connect(
        host,
        port,
        timeout: Duration(milliseconds: timeoutMs),
      );
      socket.destroy();
      return watch.elapsedMilliseconds;
    } on Object {
      return -1;
    }
  }

  Future<int> _dartPing(String host, int timeoutMs) async {
    final int waitSec = ((timeoutMs + 999) ~/ 1000).clamp(1, 5);
    try {
      final ProcessResult result = await Process.run(
        'ping',
        <String>['-c', '1', '-W', '$waitSec', host],
        runInShell: false,
      );
      final String text = '${result.stdout}\n${result.stderr}';
      final RegExpMatch? match =
          RegExp(r'time[=<]\s*([0-9]+(?:\.[0-9]+)?)\s*ms').firstMatch(text);
      if (match != null) {
        final double? value = double.tryParse(match.group(1) ?? '');
        if (value != null) {
          return value.round();
        }
      }
    } on Object {
      return -1;
    }
    return -1;
  }

  Stream<String> get trayEvents {
    if (!_available) {
      return const Stream<String>.empty();
    }
    return _trayChannel
        .receiveBroadcastStream()
        .map((Object? event) => event?.toString() ?? '')
        .handleError((Object error) => '');
  }

  /// در اندروید یعنی مجوز ساخت تونل VPN تایید شده است.
  Future<bool> isElevated() async =>
      await _invoke<bool>('hasVpnPermission') ?? false;

  /// درخواست مجوز استاندارد ساخت تونل VPN در اندروید.
  Future<bool> relaunchElevated() async =>
      await _invoke<bool>('requestVpnPermission') ?? false;

  Future<bool> requestNotificationPermission() async =>
      await _invoke<bool>('requestNotificationPermission') ?? false;

  Future<bool> coreInstalled() async =>
      await _invoke<bool>('coreInstalled') ?? false;

  Future<AndroidCoreStartResult> startAndroidCore({
    required String linksPath,
    required String settingsJson,
    required String serviceMode,
    String perAppMode = 'off',
    List<String> perAppPackages = const <String>[],
    bool showSpeed = true,
    bool debugMode = false,
    bool autoConnect = false,
    int proxyPort = 12334,
    int clashPort = 16756,
  }) async {
    final Map<Object?, Object?>? raw =
        await _invoke<Map<Object?, Object?>>('startCore', <String, dynamic>{
      'linksPath': linksPath,
      'settingsJson': settingsJson,
      'serviceMode': serviceMode,
      'perAppMode': perAppMode,
      'perAppPackages': perAppPackages,
      'showSpeed': showSpeed,
      'debugMode': debugMode,
      'autoConnect': autoConnect,
      'proxyPort': proxyPort,
      'clashPort': clashPort,
    });
    if (raw == null) {
      return AndroidCoreStartResult(
        ok: false,
        state: 'failed',
        error: _lastError.isNotEmpty
            ? _lastError
            : 'سرویس تونل اندروید در دسترس نیست.',
      );
    }
    final Map<String, dynamic> map = Map<String, dynamic>.from(raw);
    return AndroidCoreStartResult(
      ok: JsonX.boolean(map['ok']),
      state: JsonX.text(map['state']),
      error: JsonX.text(map['error']),
      permissionDenied: JsonX.boolean(map['permissionDenied']),
    );
  }

  Future<int> stopAndroidCore() async =>
      await _invoke<int>('stopCore') ?? 0;

  Future<Map<String, dynamic>> coreStatus() async {
    final Map<Object?, Object?>? raw =
        await _invoke<Map<Object?, Object?>>('coreStatus');
    if (raw == null) {
      return const <String, dynamic>{};
    }
    return Map<String, dynamic>.from(raw);
  }

  Future<bool> isIgnoringBatteryOptimizations() async =>
      await _invoke<bool>('isIgnoringBatteryOptimizations') ?? true;

  Future<bool> requestIgnoreBatteryOptimizations() async =>
      await _invoke<bool>('requestIgnoreBatteryOptimizations') ?? false;

  Future<bool> openVpnSettings() async =>
      await _invoke<bool>('openVpnSettings') ?? false;

  Future<bool> setShowSpeedInNotification(bool enabled) async =>
      await _invoke<bool>('setShowSpeed', <String, dynamic>{
        'enabled': enabled,
      }) ??
      false;

  Future<bool> installApk(String path) async =>
      await _invoke<bool>('installApk', <String, dynamic>{'path': path}) ??
      false;

  Future<bool> shareText(String text, {String title = ''}) async =>
      await _invoke<bool>('shareText', <String, dynamic>{
        'text': text,
        if (title.isNotEmpty) 'title': title,
      }) ??
      false;

  Future<bool> syncSystemBars({required bool dark}) async =>
      await _invoke<bool>('syncSystemBars', <String, dynamic>{'dark': dark}) ??
      false;

  Future<bool> minimizeApp() async =>
      await _invoke<bool>('minimizeApp') ?? false;

  Future<List<InstalledAndroidApp>> installedApps() async {
    final List<Object?>? raw =
        await _invoke<List<Object?>>('installedApps');
    if (raw == null || raw.isEmpty) {
      return const <InstalledAndroidApp>[];
    }
    final List<InstalledAndroidApp> apps = <InstalledAndroidApp>[];
    for (final Object? item in raw) {
      final Map<String, dynamic> map = JsonX.asMap(item);
      final String pkg = JsonX.text(map['packageName']).trim();
      if (pkg.isEmpty) continue;
      final String name = JsonX.text(map['appName']).trim();
      apps.add(
        InstalledAndroidApp(
          packageName: pkg,
          appName: name.isEmpty ? pkg : name,
          isSystem: JsonX.boolean(map['isSystem']),
        ),
      );
    }
    return apps;
  }

  Future<bool> runElevated(String exe, {String args = ''}) async =>
      installApk(exe);

  Future<DeviceProfile> deviceInfo() async {
    final Map<Object?, Object?>? raw =
        await _invoke<Map<Object?, Object?>>('deviceInfo');
    if (raw == null || raw.isEmpty) {
      return DeviceProfile.empty;
    }
    return DeviceProfile.fromNative(Map<String, dynamic>.from(raw));
  }

  Future<String> localIp() async => await _invoke<String>('localIp') ?? '';

  Future<String> adapterName() async =>
      await _invoke<String>('adapterName') ?? '';

  Future<int> ping(String host, {int timeoutMs = 1500}) async {
    final int icmp = await _dartPing(host, timeoutMs);
    if (icmp >= 0) {
      return icmp;
    }
    return _dartTcpPing(host, 443, timeoutMs);
  }

  Future<int> tcpPing(String host, int port, {int timeoutMs = 1500}) =>
      _dartTcpPing(host, port, timeoutMs);

  Future<int> spawn({
    required String exe,
    String args = '',
    String workDir = '',
    bool hidden = true,
    String logPath = '',
  }) async =>
      -1;

  Future<String> lastSpawnError() async => _lastError;

  Future<bool> attachCoreJob(int pid) async => false;

  static bool _nativeHttpAvailable = true;

  /// فعال سازی مجدد مسیر HTTP بومی برای آزمون واحد.
  static void resetHttpAvailabilityForTest() {
    _nativeHttpAvailable = true;
  }

  /// ارسال درخواست HTTPS/HTTP از مسیر بومی اندروید (مستقیم روی شبکه فیزیکی
  /// یا از مسیر پروکسی محلی تونل فعال) بدون قفل کردن رابط کاربری.
  static Future<NativeHttpResponse?> performHttpRequest({
    required String method,
    required String url,
    Map<String, String> headers = const <String, String>{},
    String body = '',
    int timeoutMs = 15000,
    bool useProxy = false,
  }) async {
    if (!Platform.isAndroid || !_nativeHttpAvailable) {
      return null;
    }
    try {
      final Map<Object?, Object?>? raw =
          await _channel.invokeMethod<Map<Object?, Object?>>(
        'httpRequest',
        <String, dynamic>{
          'method': method,
          'url': url,
          'headers': headers,
          'body': body,
          'timeoutMs': timeoutMs,
          'useProxy': useProxy,
        },
      ).timeout(Duration(milliseconds: timeoutMs + 3000));
      if (raw == null) {
        return null;
      }
      final Object? rawBytes = raw['bodyBytes'];
      final Uint8List bytes;
      if (rawBytes is Uint8List) {
        bytes = rawBytes;
      } else if (rawBytes is List<int>) {
        bytes = Uint8List.fromList(rawBytes);
      } else {
        bytes = Uint8List(0);
      }
      return NativeHttpResponse(
        ok: raw['ok'] == true,
        statusCode: JsonX.integer(raw['statusCode']),
        bodyBytes: bytes,
        contentType: raw['contentType']?.toString() ?? '',
        winError: JsonX.integer(raw['winError']),
        error: raw['error']?.toString() ?? '',
      );
    } on MissingPluginException {
      _nativeHttpAvailable = false;
      return null;
    } on PlatformException {
      return null;
    } on TimeoutException {
      return NativeHttpResponse(
        ok: false,
        statusCode: 0,
        bodyBytes: Uint8List(0),
        winError: 12002,
        error: 'channel_timeout',
      );
    } on Object {
      return null;
    }
  }

  /// توقف کامل سرویس تونل آمبرلا در اندروید.
  Future<int> shutdownCores({bool skipIfClean = false}) async =>
      await _invoke<int>(
        'shutdownCores',
        <String, dynamic>{'skipIfClean': skipIfClean},
      ) ??
      0;

  Future<bool> killPid(int pid) async => false;

  Future<int> killByName(String name) async => shutdownCores();

  Future<List<int>> pidsHoldingPort(int port) async => const <int>[];

  Future<String> processNameOf(int pid) async => '';

  Future<String> processPathOf(int pid) async => '';

  Future<bool> isRunning(String name) async =>
      await _invoke<bool>('isRunning', <String, dynamic>{'name': name}) ??
      false;

  Future<List<String>> runningCores() async {
    final List<Object?>? raw = await _invoke<List<Object?>>('runningCores');
    if (raw == null || raw.isEmpty) {
      return const <String>[];
    }
    return raw.map((Object? item) => item.toString()).toList();
  }

  Future<bool> setSystemProxy({
    String host = '127.0.0.1',
    required int port,
  }) async =>
      await _invoke<bool>('setSystemProxy', <String, dynamic>{
        'host': host,
        'port': port,
      }) ??
      true;

  Future<bool> disableSystemProxy() async =>
      await _invoke<bool>('disableSystemProxy') ?? true;

  Future<bool> systemProxyEnabled() async =>
      await _invoke<bool>('systemProxyEnabled') ?? false;

  Future<bool> flushDns() async => await _invoke<bool>('flushDns') ?? true;

  Future<TunnelStats> tunnelStats({String hint = 'tun0'}) async {
    final Map<Object?, Object?>? raw = await _invoke<Map<Object?, Object?>>(
      'tunnelStats',
      <String, dynamic>{'hint': hint},
    );
    if (raw == null) {
      return TunnelStats.empty;
    }
    final Map<String, dynamic> map = Map<String, dynamic>.from(raw);
    return TunnelStats(
      rx: JsonX.integer(map['rx']),
      tx: JsonX.integer(map['tx']),
      available: JsonX.boolean(map['available']),
      adapter: JsonX.text(map['adapter']),
    );
  }

  Future<bool> setAutostart(
    bool enabled, {
    String appName = 'UmbrellaVPN',
  }) async =>
      await _invoke<bool>('autostart', <String, dynamic>{
        'enabled': enabled,
        'appName': appName,
      }) ??
      false;

  Future<bool> autostartEnabled({String appName = 'UmbrellaVPN'}) async =>
      await _invoke<bool>('autostartEnabled', <String, dynamic>{
        'appName': appName,
      }) ??
      false;

  Future<String> exePath() async => await _invoke<String>('exePath') ?? '';

  Future<String> dataDir() async => await _invoke<String>('dataDir') ?? '';

  Future<bool> openPath(String path) async =>
      await _invoke<bool>('openPath', <String, dynamic>{'path': path}) ?? false;

  Future<bool> restoreNetworkDefaults() async {
    await shutdownCores();
    await flushDns();
    return true;
  }

  Future<bool> trayInit() async => await _invoke<bool>('trayInit') ?? true;

  Future<bool> trayIcon(String path) async => true;

  Future<bool> trayTooltip(String text) async => true;

  Future<bool> trayMenu({
    required String connectLabel,
    required String disconnectLabel,
    required bool connected,
  }) async =>
      true;

  Future<bool> trayBalloon({
    required String title,
    required String body,
    bool warning = false,
  }) async =>
      await _invoke<bool>('trayBalloon', <String, dynamic>{
        'title': title,
        'body': body,
        'warning': warning,
      }) ??
      false;

  Future<bool> trayDestroy() async => true;
}
