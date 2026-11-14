import 'dart:io';

import '../core/app_config.dart';

/// تنها هسته اتصال برنامه: موتور هسته (کتابخانه هسته به همراه لانچرهای آمبرلا).
///
/// مستندات هسته می گوید هسته فقط به «پروکسی ها» نیاز دارد و بقیه پیکربندی را
/// خودش می سازد:
///
/// * `run -c <links.txt>` برای فایل لینک ها، لینک اشتراک، پیکربندی کلش یا
///   ایکس ری و فایل وایرگارد؛ هسته پورت محلی، دی ان اس، مسیرها و انتخاب
///   بهترین سرور را خودش می سازد.
/// * `--tun` برای تونل کامل (نیاز به دسترسی مدیر) و `--system-proxy` برای
///   پروکسی سیستمی.
/// * `--in-proxy-port` پورت پروکسی مختلط محلی.
///
/// همین یک هسته همه پروتکل های اشتراک این پنل را پوشش می دهد (از جمله xhttp
/// و Reality) و به هسته های دستی (سینگ باکس، ایکس ری، کلش متا، میرو) نیازی
/// نیست. فایل اجرایی، لانچر خود ما است (`native/umbrella_launcher.c`) که
/// کتابخانه هسته را از مسیرش بار می کند.
class UmbrellaCore {
  const UmbrellaCore._();

  /// نام فایل اجرایی خط فرمان (لانچر کنسولی آمبرلا).
  static const String cliBinary = 'UmbrellaCli.exe';

  /// نام فایل اجرایی موتور. این فایل زیرسیستم گرافیکی دارد، پس هیچ پنجره
  /// کنسولی باز نمی کند.
  static const String engineBinary = 'UmbrellaCoreEngine.exe';

  /// نام فایل اجرایی مدیر (زیرسیستم گرافیکی با مانیفست requireAdministrator).
  static const String adminBinary = 'UmbrellaAdmin.exe';

  /// شناسه هسته در فهرست همراه نسخه.
  static const String id = 'hiddify';

  /// کتابخانه کرونت که هسته کنار خودش می خواهد.
  static const String cronetDll = 'libcronet.dll';

  /// کتابخانه خود هسته (همان hiddify-core.dll با نام اصلی خودش).
  ///
  /// چرا نامش عوض نمی شود؟ چون نام کتابخانه داخل خودش و داخل وابستگی هایش
  /// ثبت است؛ در ۱٫۰٫۲ با عوض شدن نام، ویندوز فایل اجرایی را با کد
  /// 0xC0000135 (کتابخانه پیدا نشد) می بست. این فایل هیچ وقت مستقیم اجرا
  /// نمی شود و در هیچ پنجره، مسیر یا گزارشی به کاربر نشان داده نمی شود؛
  /// برنامه آن را با همین نام از پوشه خودش بار می کند.
  static const String coreDll = 'hiddify-core.dll';

  /// پورت پروکسی مختلط محلی.
  static const int port = AppConfig.httpPortUmbrella;

  /// آرگومان های اجرای هسته.
  ///
  /// [links] مسیر فایل لینک ها است (یک لینک در هر خط). [tun] تونل کامل را
  /// روشن می کند و [systemProxy] پروکسی سیستمی را. هر دو با هم نمی آیند.
  static List<String> args({
    required String links,
    required String runDir,
    int? port,
    bool tun = false,
    bool systemProxy = false,
    String logLevel = 'info',
    String settingsPath = '',
    bool disableColor = true,
  }) {
    return <String>[
      'run',
      '-c',
      links,
      '-D',
      runDir,
      if (settingsPath.isNotEmpty) ...<String>['-d', settingsPath],
      '--in-proxy-port',
      '${port ?? UmbrellaCore.port}',
      if (tun) '--tun',
      if (systemProxy && !tun) '--system-proxy',
      '--log-level',
      logLevel,
      if (disableColor) '--disable-color',
    ];
  }

  /// فایل تنظیمات هسته (`-d`).
  ///
  /// کلیدها همان کلیدهای `HiddifyOptions` در خود هسته اند
  /// (`v2/config/hiddify_option.go` در خود هسته) و با خط تیره نوشته می شوند، مثل
  /// `log-level`، `enable-tun`، `set-system-proxy` و `mixed-port`.
  static Map<String, dynamic> settingsJson({
    required bool tun,
    required bool systemProxy,
    required int port,
    String logLevel = 'info',
    String logFile = '',
  }) {
    return <String, dynamic>{
      'log-level': logLevel,
      if (logFile.isNotEmpty) 'log-file': logFile,
      'enable-tun': tun,
      'set-system-proxy': systemProxy && !tun,
      'mixed-port': port,
      'enable-clash-api': false,
      // کارت شبکه مجازی هسته، همان پیش فرض خودش.
      'tun-implementation': 'system',
      // سرعت انتخاب سرور در خود هسته: بهترین گره نگه داشته می شود، پس اگر
      // یک سرور افت کرد، خود هسته بدون قطعی سراغ بعدی می رود.
      'keep-top': 3,
      'connection-test-url': AppConfig.speedTestUrl,
    };
  }

  /// پوشه هسته در نسخه نصب: همه فایل های هسته باید کنار هم بمانند.
  ///
  /// [appDir] یا پوشه خود برنامه است یا پوشه `cores`؛ هر دو پذیرفته می شود تا
  /// فراخوان ها لازم نباشد بدانند کدام یکی را دارند. نام پوشه `umbrella` است
  /// تا حتی مسیرهای خطا هم نامی جز آمبرلا نداشته باشند.
  static String directoryOf(String appDir) {
    final String clean = appDir.endsWith(Platform.pathSeparator)
        ? appDir.substring(0, appDir.length - 1)
        : appDir;
    if (clean.endsWith('${Platform.pathSeparator}cores')) {
      return '$clean${Platform.pathSeparator}umbrella';
    }
    return '$clean${Platform.pathSeparator}cores'
        '${Platform.pathSeparator}umbrella';
  }

  /// پوشه خود برنامه (جایی که فایل های اجرایی هستند).
  ///
  /// [appDir] ممکن است خود برنامه، پوشه `cores` یا پوشه `cores\umbrella` باشد؛
  /// هر سه به پوشه برنامه برمی گردند تا بررسی نصب از هر مسیری درست کار کند.
  static String rootOf(String appDir) {
    final String separator = Platform.pathSeparator;
    String clean = appDir.endsWith(separator)
        ? appDir.substring(0, appDir.length - 1)
        : appDir;
    if (clean.endsWith('${separator}umbrella')) {
      clean = clean.substring(0, clean.lastIndexOf(separator));
    }
    if (clean.endsWith('${separator}cores')) {
      clean = clean.substring(0, clean.lastIndexOf(separator));
    }
    return clean;
  }

  /// آیا فایل های هسته در نسخه نصب هستند؟
  ///
  /// دو جا بررسی می شود، چون دو بخش دارد:
  ///
  /// * فایل های اجرایی (لانچرهای آمبرلا) کنار خود برنامه هستند.
  /// * کتابخانه هسته و کرونتش در پوشه `cores\umbrella`.
  ///
  /// اگر یکی نباشد، اتصال با «کتابخانه پیدا نشد» شکست می خورد و کاربر پیام
  /// روشنی نمی بیند؛ برای همین پیش از هر تلاشی بررسی می شود.
  static bool installed(String appDir) {
    final String root = rootOf(appDir);
    final String dir = directoryOf(root);
    bool has(String base, String name) =>
        File('$base${Platform.pathSeparator}$name').existsSync();
    for (final String name in <String>[cliBinary, engineBinary, adminBinary]) {
      if (!has(root, name) && !has(dir, name)) {
        return false;
      }
    }
    for (final String name in <String>[coreDll, cronetDll]) {
      if (!has(dir, name) && !has(root, name)) {
        return false;
      }
    }
    return true;
  }
}

/// تنظیمات هسته که در فایل جلسه CLI هم استفاده می شود.
class UmbrellaSession {
  const UmbrellaSession._();

  /// فایل `links.txt` را می نویسد و مسیرش را برمی گرداند.
  static Future<String> writeLinks({
    required String runDir,
    required List<String> links,
  }) async {
    await Directory(runDir).create(recursive: true);
    final File file =
        File('$runDir${Platform.pathSeparator}umbrella-core-link.txt');
    await file.writeAsString('${links.join('\n')}\n', flush: true);
    return file.path;
  }
}
