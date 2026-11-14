import 'dart:io';

import '../core/app_config.dart';

/// تنها هسته اتصال برنامه: هسته هیدیفای.
///
/// مستندات هسته ([hiddify.com/core](https://hiddify.com/core/)) می گوید هسته
/// فقط به «پروکسی ها» نیاز دارد و بقیه پیکربندی را خودش می سازد:
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
/// نیست. فایل اجرایی همان `HiddifyCli.exe` است که با نام `UmbrellaCli.exe`
/// همراه نسخه نصب می شود.
class HiddifyCore {
  const HiddifyCore._();

  /// نام فایل اجرایی خط فرمان (همان HiddifyCli با نام آمبرلا).
  static const String cliBinary = 'UmbrellaCli.exe';

  /// نام فایل اجرایی موتور (همان HiddifyCoreEngine با نام آمبرلا). این فایل
  /// زیرسیستم گرافیکی دارد، پس هیچ پنجره کنسولی باز نمی کند.
  static const String engineBinary = 'UmbrellaCoreEngine.exe';

  /// شناسه هسته در فهرست همراه نسخه.
  static const String id = 'hiddify';

  /// پورت پروکسی مختلط محلی.
  static const int port = AppConfig.httpPortHiddify;

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
      '${port ?? HiddifyCore.port}',
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
  /// (`v2/config/hiddify_option.go`) و با خط تیره نوشته می شوند، مثل
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
  static String directoryOf(String appDir) =>
      '$appDir${Platform.pathSeparator}cores'
      '${Platform.pathSeparator}hiddify';

  /// آیا فایل های هسته در نسخه نصب هستند؟
  static bool installed(String appDir) =>
      File('${directoryOf(appDir)}${Platform.pathSeparator}$cliBinary')
          .existsSync();
}

/// تنظیمات هسته که در فایل جلسه CLI هم استفاده می شود.
class HiddifySession {
  const HiddifySession._();

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
