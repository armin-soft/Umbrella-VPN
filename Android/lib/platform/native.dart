// پل بومی اندروید (MethodChannel به Kotlin).
//
// این فایل جایگزین platform/native.dart ویندوز است و همان نام کلاس
// (NativeBridge) را نگه می دارد تا فایل های مشترک (ping.dart و
// umbrella_core.dart) بدون تغییر کار کنند. تفاوت ها:
//   * پینگ TCP با سوکت Dart انجام می شود (همان جایگزین ویندوز) و پینگ ICMP
//     روی اندروید بدون دسترسی ریشه ممکن نیست، پس فقط TCP سنجیده می شود.
//   * مدیریت پورت/فرایند ویندوز (netstat/taskkill) روی اندروید معنی ندارد؛
//     اندروید خودش فرایندها را مدیریت می کند و این متدها مقدار خالی می دهند.
//   * کارهای اندرویدی (مجوز VPN، سرویس پیش زمینه، اطلاعات دستگاه، نصب APK)
//     از MethodChannel به Kotlin می روند.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/models.dart';

/// پاسخ درخواست HTTP (برای سازگاری با امضای ویندوز؛ روی اندروید استفاده نمی شود).
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

/// وضعیت باتری اندروید؛ مقدار نامشخص هرگز به معنی باتری فرض نمی شود.
class BatteryPowerState {
  const BatteryPowerState({
    required this.hasBattery,
    required this.onBattery,
    required this.energySaver,
    this.isLaptop,
    this.powerKnown = true,
  });
  final bool hasBattery;
  final bool onBattery;
  final bool energySaver;
  final bool? isLaptop;
  final bool powerKnown;
  bool get shouldOptimize =>
      isLaptop == true && powerKnown && hasBattery && (onBattery || energySaver);
}

/// پل ارتباط با لایه بومی اندروید.
///
/// هر متد در صورت نبود پلاگین مقدار امن برمی گرداند تا رابط کاربری هرگز
/// از کار نیفتد؛ مثلا در حالت اجرای آزمایشی روی ماشین بدون Kotlin.
class NativeBridge {
  NativeBridge();

  static const MethodChannel _channel = MethodChannel('ir.umbrella.app/android');

  bool _available = true;
  bool get available => _available;

  /// آخرین خطای پل بومی؛ برای گزارش ها نگه داشته می شود.
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

  // ── پینگ (جایگزین Dart؛ روی اندروید پلاگین بومی لازم نیست) ─────────────

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

  /// پینگ TCP به پورت خود سرور؛ همان مسیری که تونل استفاده می کند.
  Future<int> tcpPing(String host, int port, {int timeoutMs = 1500}) async {
    if (host.isEmpty || port <= 0) {
      return -1;
    }
    return _dartTcpPing(host, port, timeoutMs);
  }

  /// پینگ ICMP روی اندروید بدون ریشه ممکن نیست؛ فقط TCP سنجیده می شود.
  /// برای سازگاری امضا با ویندوز نگه داشته شده و همیشه -۱ برمی گرداند.
  Future<int> ping(String host, {int timeoutMs = 1500}) async => -1;

  // ── سازگاری با umbrella_core.dart (مدیریت پورت ویندوز) ─────────────────
  // روی اندروید هیچ فرایند خارجی پورت هسته را نمی گیرد؛ اندروید خودش
  // چرخه حیات فرایندها را مدیریت می کند. این متدها عمداً خالی هستند.

  Future<List<int>> pidsHoldingPort(int port) async => <int>[];

  Future<String> processNameOf(int pid) async => '';

  Future<String> processPathOf(int pid) async => '';

  Future<bool> killPid(int pid) async => false;

  Future<int> killByName(String name) async => 0;

  Future<bool> isRunning(String name) async => false;

  Future<List<String>> runningCores() async => <String>[];

  // ── مجوز و سرویس VPN ────────────────────────────────────────────────────

  /// آیا مجوز VPN قبلاً داده شده است؟
  Future<bool> isVpnPrepared() async =>
      await _invoke<bool>('isVpnPrepared') ?? false;

  /// نمایش دیالوگ سیستمی مجوز VPN؛ true یعنی کاربر قبول کرد.
  Future<bool> requestVpnPermission() async =>
      await _invoke<bool>('requestVpnPermission') ?? false;

  /// شروع سرویس پیش زمینه VPN (هسته موبایل در آن بالا می آید).
  Future<bool> startService({
    required String baseDir,
    required String workingDir,
    required String tempDir,
    int grpcPort = 17078,
    bool debug = false,
  }) async =>
      await _invoke<bool>('startService', <String, dynamic>{
        'baseDir': baseDir,
        'workingDir': workingDir,
        'tempDir': tempDir,
        'grpcPort': grpcPort,
        'debug': debug,
      }) ??
      false;

  /// توقف سرویس پیش زمینه VPN و بستن هسته.
  Future<bool> stopService() async =>
      await _invoke<bool>('stopService') ?? false;

  /// گواهی همان سرور محلی که سرویس ساخته؛ برای pin کردن mTLS.
  Future<Uint8List?> coreServerCertificate() => _invoke<Uint8List>('serverCertificate');

  /// آیا سرویس VPN هم اکنون در حال اجراست؟
  Future<bool> isServiceRunning() async =>
      await _invoke<bool>('isServiceRunning') ?? false;

  /// آیا کتابخانه هسته موبایل (AAR) در APK هست؟
  Future<bool> coreAvailable() async =>
      await _invoke<bool>('coreAvailable') ?? false;

  /// مسیرهای پوشه داده هسته (از Kotlin؛ همان جایی که Mobile.setup می خواهد).
  Future<Map<String, String>> coreDirectories() async {
    final Map<dynamic, dynamic>? raw =
        await _invoke<Map<dynamic, dynamic>>('coreDirectories');
    if (raw == null) {
      return <String, String>{};
    }
    return raw.map((dynamic k, dynamic v) => MapEntry<String, String>(
          k.toString(),
          v.toString(),
        ));
  }

  // ── اطلاعات دستگاه ─────────────────────────────────────────────────────

  /// اطلاعات دستگاه اندروید (مدل، نسخه اندروید، باتری، شبکه).
  Future<DeviceProfile> deviceInfo() async {
    final Map<dynamic, dynamic>? raw =
        await _invoke<Map<dynamic, dynamic>>('deviceInfo');
    if (raw == null) {
      return DeviceProfile.empty;
    }
    final Map<String, dynamic> json = raw.map(
      (dynamic k, dynamic v) => MapEntry<String, dynamic>(k.toString(), v),
    );
    return DeviceProfile.fromNative(json);
  }

  /// سطح باتری (۰ تا ۱۰۰) یا -۱ اگر خوانده نشد.
  Future<int> batteryLevel() async =>
      await _invoke<int>('batteryLevel') ?? -1;

  /// آیا دستگاه در حال شارژ است؟
  Future<bool> isCharging() async => await _invoke<bool>('isCharging') ?? false;

  /// نشانی IP محلی دستگاه.
  Future<String> localIp() async => await _invoke<String>('localIp') ?? '';

  // ── برنامه های نصب شده (برای مسیریابی بر اساس برنامه) ─────────────────

  /// فهرست برنامه های نصب شده: packageName و نام نمایشی.
  Future<List<InstalledApp>> installedApps() async {
    final List<dynamic>? raw = await _invoke<List<dynamic>>('installedApps');
    if (raw == null) {
      return <InstalledApp>[];
    }
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> item) => InstalledApp(
              packageName: item['package']?.toString() ?? '',
              label: item['label']?.toString() ?? '',
            ))
        .where((InstalledApp app) => app.packageName.isNotEmpty)
        .toList();
  }

  // ── به روز رسانی APK ────────────────────────────────────────────────────

  /// نصب APK دانلود شده با FileProvider و دیالوگ سیستمی نصب.
  Future<bool> installApk(String apkPath) async =>
      await _invoke<bool>('installApk', <String, dynamic>{'path': apkPath}) ??
      false;

  /// درخواست معافیت از بهینه سازی باتری (برای پایداری سرویس پیش زمینه).
  Future<bool> requestIgnoreBatteryOptimizations() async =>
      await _invoke<bool>('requestIgnoreBatteryOptimizations') ?? false;

  /// آیا معافیت بهینه سازی باتری داده شده است؟
  Future<bool> isIgnoringBatteryOptimizations() async =>
      await _invoke<bool>('isIgnoringBatteryOptimizations') ?? false;

  // ── اعلان ───────────────────────────────────────────────────────────────

  /// نمایش اعلان سیستمی (اتصال/قطع/خطا)؛ در اندروید اعلان سرویس پیش زمینه
  /// همیشه هست و این فقط برای پیام های رویدادی است.
  Future<bool> showNotification({
    required String title,
    required String body,
    bool warning = false,
  }) async =>
      await _invoke<bool>('showNotification', <String, dynamic>{
        'title': title,
        'body': body,
        'warning': warning,
      }) ??
      false;

  // ── باز کردن نشانی ─────────────────────────────────────────────────────

  Future<bool> openUrl(String url) async =>
      await _invoke<bool>('openUrl', <String, dynamic>{'url': url}) ?? false;
}

/// یک برنامه نصب شده روی دستگاه (برای انتخاب در مسیریابی بر اساس برنامه).
class InstalledApp {
  const InstalledApp({required this.packageName, required this.label});

  final String packageName;
  final String label;
}
