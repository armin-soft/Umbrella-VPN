import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/utils.dart';
import '../models/models.dart';

/// پاسخ درخواست HTTP بومی اندروید (OkHttp).
class NativeHttpResponse {
  const NativeHttpResponse({
    required this.ok,
    required this.statusCode,
    required this.bodyBytes,
    this.contentType = '',
    this.headers = const <String, String>{},
    this.error = '',
  });

  final bool ok;
  final int statusCode;
  final Uint8List bodyBytes;
  final String contentType;
  final Map<String, String> headers;
  final String error;
}

/// وضعیت بهینه سازی باتری و انرژی گوشی اندروید.
class BatteryPowerState {
  const BatteryPowerState({
    required this.hasBattery,
    required this.onBattery,
    required this.energySaver,
    this.powerKnown = true,
    this.batteryPercent = -1,
    this.ignoringBatteryOptimizations = true,
  });

  final bool hasBattery;
  final bool onBattery;
  final bool energySaver;
  final bool powerKnown;
  final int batteryPercent;
  final bool ignoringBatteryOptimizations;

  bool get isLaptop => hasBattery;

  bool get isCriticallyLowBattery =>
      powerKnown &&
      hasBattery &&
      onBattery &&
      batteryPercent >= 0 &&
      batteryPercent < 5;

  bool get shouldOptimize =>
      powerKnown && hasBattery && (onBattery || energySaver);
}

/// رویداد وضعیت سرویس VPN / Proxy اندروید.
class AndroidServiceEvent {
  const AndroidServiceEvent({
    required this.type,
    this.status = '',
    this.alert = '',
    this.message = '',
    this.messages = const <String>[],
  });

  final String type;
  final String status;
  final String alert;
  final String message;
  final List<String> messages;

  factory AndroidServiceEvent.fromMap(Map<Object?, Object?> raw) {
    final List<String> msgList = <String>[];
    final Object? msgs = raw['messages'];
    if (msgs is List) {
      for (final Object? item in msgs) {
        if (item != null) msgList.add(item.toString());
      }
    }
    return AndroidServiceEvent(
      type: JsonX.text(raw['type']),
      status: JsonX.text(raw['status']),
      alert: JsonX.text(raw['alert']),
      message: JsonX.text(raw['message']),
      messages: msgList,
    );
  }
}

/// اطلاعات اپلیکیشن نصب شده در گوشی برای فیلترشکن برنامه ها (Per-App Proxy).
class InstalledAppInfo {
  const InstalledAppInfo({
    required this.packageName,
    required this.name,
    this.isSystem = false,
  });

  final String packageName;
  final String name;
  final bool isSystem;

  factory InstalledAppInfo.fromMap(Map<Object?, Object?> raw) {
    return InstalledAppInfo(
      packageName: JsonX.text(raw['packageName']),
      name: JsonX.text(raw['name'], JsonX.text(raw['packageName'])),
      isSystem: JsonX.boolean(raw['isSystem']),
    );
  }
}

/// نتیجه دریافت URL از طریق هسته بومی (`hiddify-core` FetchUrl با uTLS کروم).
class CoreFetchNativeResult {
  const CoreFetchNativeResult({
    required this.ok,
    required this.statusCode,
    required this.headers,
    required this.bodyBytes,
    required this.error,
    required this.errorDetail,
  });

  final bool ok;
  final int statusCode;
  final Map<String, String> headers;
  final Uint8List bodyBytes;
  final String error;
  final String errorDetail;
}

/// پل ارتباط با لایه بومی اندروید (`ir.umbrella.vpn`).
class NativeBridge {
  NativeBridge();

  static const MethodChannel _channel = MethodChannel('ir.umbrella.app/native');
  static const EventChannel _serviceChannel =
      EventChannel('ir.umbrella.app/service_events');

  bool _available = true;
  bool get available => _available;

  String _lastError = '';
  String get lastError => _lastError;

  Stream<AndroidServiceEvent>? _serviceEvents;

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

  Stream<AndroidServiceEvent> serviceEvents() {
    _serviceEvents ??= _serviceChannel
        .receiveBroadcastStream()
        .where((Object? event) => event is Map)
        .map((Object? event) =>
            AndroidServiceEvent.fromMap(event! as Map<Object?, Object?>));
    return _serviceEvents!;
  }

  Future<Map<String, dynamic>> getPlatformInfo() async {
    final Map<Object?, Object?>? raw =
        await _invoke<Map<Object?, Object?>>('getPlatformInfo');
    return JsonX.asMap(raw);
  }

  Future<Map<String, dynamic>> setupDirectories({
    String? baseDir,
    String? workingDir,
    String? tempDir,
    int? grpcServicePort,
    int? grpcUtilityPort,
    bool? debug,
  }) async {
    final Map<Object?, Object?>? raw = await _invoke<Map<Object?, Object?>>(
      'setupDirectories',
      <String, dynamic>{
        if (baseDir != null) 'baseDir': baseDir,
        if (workingDir != null) 'workingDir': workingDir,
        if (tempDir != null) 'tempDir': tempDir,
        if (grpcServicePort != null) 'grpcServicePort': grpcServicePort,
        if (grpcUtilityPort != null) 'grpcUtilityPort': grpcUtilityPort,
        if (debug != null) 'debug': debug,
      },
    );
    return JsonX.asMap(raw);
  }

  Future<bool> ensureVpnPermission() async {
    final bool? granted = await _invoke<bool>('ensureVpnPermission');
    return granted ?? false;
  }

  Future<Map<String, dynamic>> startCore({
    required String configPath,
    required String settingsJson,
    required String profileName,
    String serviceMode = 'vpn',
  }) async {
    final Map<Object?, Object?>? raw = await _invoke<Map<Object?, Object?>>(
      'startCore',
      <String, dynamic>{
        'configPath': configPath,
        'settingsJson': settingsJson,
        'profileName': profileName,
        'serviceMode': serviceMode,
      },
    );
    return JsonX.asMap(raw);
  }

  Future<bool> stopCore() async {
    final bool? ok = await _invoke<bool>('stopCore');
    return ok ?? false;
  }

  Future<Map<String, dynamic>> getCoreStatus() async {
    final Map<Object?, Object?>? raw =
        await _invoke<Map<Object?, Object?>>('getCoreStatus');
    return JsonX.asMap(raw);
  }

  Future<({bool ok, String content, String message})> parseConfig({
    String content = '',
    String configPath = '',
    String tempPath = '',
    bool debug = false,
  }) async {
    final Map<Object?, Object?>? raw = await _invoke<Map<Object?, Object?>>(
      'parseConfig',
      <String, dynamic>{
        'content': content,
        'configPath': configPath,
        if (tempPath.isNotEmpty) 'tempPath': tempPath,
        'debug': debug,
      },
    );
    final Map<String, dynamic> map = JsonX.asMap(raw);
    return (
      ok: JsonX.boolean(map['ok']),
      content: JsonX.text(map['content']),
      message: JsonX.text(map['message']),
    );
  }

  Future<CoreFetchNativeResult?> fetchUrlWithCore({
    required String url,
    required String userAgent,
    int timeoutMs = 15000,
  }) async {
    final Map<Object?, Object?>? raw = await _invoke<Map<Object?, Object?>>(
      'fetchUrlWithCore',
      <String, dynamic>{
        'url': url,
        'userAgent': userAgent,
        'timeoutMs': timeoutMs,
      },
    );
    if (raw == null) return null;
    final Map<String, dynamic> map = JsonX.asMap(raw);
    final Map<String, String> headers = <String, String>{};
    final Map<String, dynamic> rawHeaders = JsonX.asMap(map['headers']);
    for (final MapEntry<String, dynamic> entry in rawHeaders.entries) {
      headers[entry.key.toLowerCase()] = JsonX.text(entry.value);
    }
    final Object? bodyRaw = raw['bodyBytes'];
    final Uint8List bytes = bodyRaw is Uint8List
        ? bodyRaw
        : (bodyRaw is List
            ? Uint8List.fromList(bodyRaw.cast<int>())
            : Uint8List(0));
    return CoreFetchNativeResult(
      ok: JsonX.boolean(map['ok']),
      statusCode: JsonX.integer(map['statusCode']),
      headers: headers,
      bodyBytes: bytes,
      error: JsonX.text(map['error']),
      errorDetail: JsonX.text(map['errorDetail']),
    );
  }

  Future<List<InstalledAppInfo>> getInstalledApps() async {
    final List<Object?>? raw =
        await _invoke<List<Object?>>('getInstalledApps');
    if (raw == null) return const <InstalledAppInfo>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(InstalledAppInfo.fromMap)
        .where((InstalledAppInfo app) => app.packageName.isNotEmpty)
        .toList();
  }

  Future<bool> setPerAppProxy({
    required String mode,
    List<String>? includePackages,
    List<String>? excludePackages,
  }) async {
    final bool? ok = await _invoke<bool>(
      'setPerAppProxy',
      <String, dynamic>{
        'mode': mode,
        if (includePackages != null) 'includePackages': includePackages,
        if (excludePackages != null) 'excludePackages': excludePackages,
      },
    );
    return ok ?? false;
  }

  Future<bool> setAutostart(bool enabled) async {
    final bool? ok = await _invoke<bool>(
      'setStartOnBoot',
      <String, dynamic>{'enabled': enabled},
    );
    return ok ?? false;
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    final bool? ok = await _invoke<bool>('getBatteryOptimizationStatus');
    return ok ?? true;
  }

  Future<bool> requestIgnoreBatteryOptimization() async {
    final bool? ok = await _invoke<bool>('requestIgnoreBatteryOptimization');
    return ok ?? false;
  }

  Future<bool> openVpnSystemSettings() async {
    final bool? ok = await _invoke<bool>('openVpnSystemSettings');
    return ok ?? false;
  }

  Future<({bool ok, String reason})> installApk(String path) async {
    final Map<Object?, Object?>? raw = await _invoke<Map<Object?, Object?>>(
      'installApk',
      <String, dynamic>{'path': path},
    );
    final Map<String, dynamic> map = JsonX.asMap(raw);
    return (
      ok: JsonX.boolean(map['ok']),
      reason: JsonX.text(map['reason']),
    );
  }

  Future<List<String>> consumeRecentNativeCrashes() async {
    final List<Object?>? raw =
        await _invoke<List<Object?>>('consumeRecentCrashes');
    if (raw == null) return const <String>[];
    return raw.map((Object? e) => e?.toString() ?? '').where((String s) => s.isNotEmpty).toList();
  }

  Future<List<String>> getLanIps() async {
    final List<Object?>? raw = await _invoke<List<Object?>>('getLanIps');
    if (raw == null) return const <String>[];
    return raw.map((Object? e) => e?.toString() ?? '').where((String s) => s.isNotEmpty).toList();
  }

  static Future<NativeHttpResponse?> performHttpRequest({
    required String method,
    required String url,
    Map<String, String> headers = const <String, String>{},
    String body = '',
    int timeoutMs = 15000,
    String? proxyHost,
    int proxyPort = 0,
    bool followRedirects = true,
  }) async {
    try {
      final Map<Object?, Object?>? raw =
          await _channel.invokeMethod<Map<Object?, Object?>>(
        'httpRequest',
        <String, dynamic>{
          'method': method,
          'url': url,
          'headers': headers,
          if (body.isNotEmpty) 'bodyBytes': Uint8List.fromList(body.codeUnits),
          'timeoutMs': timeoutMs,
          if (proxyHost != null && proxyHost.isNotEmpty) 'proxyHost': proxyHost,
          if (proxyPort > 0) 'proxyPort': proxyPort,
          'followRedirects': followRedirects,
        },
      );
      if (raw == null) return null;
      final int status = JsonX.integer(raw['statusCode']);
      final Map<String, String> respHeaders = <String, String>{};
      final Map<String, dynamic> rawH = JsonX.asMap(raw['headers']);
      for (final MapEntry<String, dynamic> e in rawH.entries) {
        respHeaders[e.key.toLowerCase()] = JsonX.text(e.value);
      }
      final Object? bytesObj = raw['bodyBytes'];
      final Uint8List bytes = bytesObj is Uint8List
          ? bytesObj
          : (bytesObj is List
              ? Uint8List.fromList(bytesObj.cast<int>())
              : Uint8List(0));
      return NativeHttpResponse(
        ok: status > 0,
        statusCode: status,
        bodyBytes: bytes,
        contentType: respHeaders['content-type'] ?? '',
        headers: respHeaders,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      return NativeHttpResponse(
        ok: false,
        statusCode: 0,
        bodyBytes: Uint8List(0),
        error: error.message ?? error.code,
      );
    }
  }

  Future<int> tcpPing(String host, int port, {int timeoutMs = 1500}) async {
    if (host.trim().isEmpty || port <= 0) return -1;
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

  Future<int> ping(String host, {int timeoutMs = 1500}) async {
    return tcpPing(host, 443, timeoutMs: timeoutMs);
  }

  Future<bool> isElevated() async => true;

  Future<BatteryPowerState> powerStatus() async {
    final bool ignoring = await isIgnoringBatteryOptimizations();
    final Map<String, dynamic> info = await getPlatformInfo();
    final int pct = JsonX.integer(info['batteryPercent'], -1);
    final bool plugged = JsonX.boolean(info['powerPlugged']);
    return BatteryPowerState(
      hasBattery: true,
      onBattery: !plugged,
      energySaver: !ignoring,
      powerKnown: true,
      batteryPercent: pct,
      ignoringBatteryOptimizations: ignoring,
    );
  }

  Future<String> localIp() async {
    final List<String> ips = await getLanIps();
    if (ips.isNotEmpty) return ips.first;
    try {
      final List<NetworkInterface> ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final NetworkInterface iface in ifaces) {
        for (final InternetAddress addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } on Object {
      // نادیده گرفته می شود.
    }
    return '';
  }

  Future<DeviceProfile> deviceInfo() async {
    final Map<String, dynamic> info = await getPlatformInfo();
    final List<String> ips = await getLanIps();
    final String deviceName = JsonX.text(info['deviceName'], 'دستگاه اندروید');
    final String manufacturer = JsonX.text(info['manufacturer']);
    final String model = JsonX.text(info['model']);
    final String osVersion = JsonX.text(info['osVersion']);
    final int sdkInt = JsonX.integer(info['sdkInt']);
    final String abi = JsonX.text(info['abi'], 'arm64-v8a');
    return DeviceProfile(
      hostname: deviceName,
      username: '$manufacturer $model'.trim(),
      os: osVersion.isNotEmpty
          ? 'اندروید $osVersion (API $sdkInt)'
          : Platform.operatingSystemVersion,
      osDisplayVersion: osVersion,
      osBuild: sdkInt,
      arch: abi,
      cpuCores: Platform.numberOfProcessors,
      ramTotalMb: JsonX.integer(info['ramTotalMb']),
      ramUsedMb: JsonX.integer(info['ramUsedMb']),
      ramLoadPercent: JsonX.integer(info['ramLoadPercent']),
      diskTotalMb: JsonX.integer(info['diskTotalMb']),
      diskFreeMb: JsonX.integer(info['diskFreeMb']),
      hasBattery: true,
      batteryPercent: JsonX.integer(info['batteryPercent'], -1),
      powerPlugged: JsonX.boolean(info['powerPlugged'], fallback: true),
      uptimeSeconds: JsonX.integer(info['uptimeSeconds']),
      localIp: ips.isNotEmpty ? ips.first : await localIp(),
      elevated: true,
      batteryOptimized: JsonX.boolean(info['batteryOptimized']),
      canRequestInstallPackages:
          JsonX.boolean(info['canRequestInstallPackages'], fallback: true),
      notificationGranted:
          JsonX.boolean(info['notificationGranted'], fallback: true),
    );
  }

  Future<int?> processCpuTimeMicros(int pid) async => null;

  /// Android VpnService resets interface DNS automatically on restart/stop.
  Future<bool> flushDns() async => true;

  /// No global OS proxy settings exist to reset on Android.
  Future<bool> restoreNetworkDefaults() async => true;

  Future<bool> shutdownCores() async => stopCore();
}
