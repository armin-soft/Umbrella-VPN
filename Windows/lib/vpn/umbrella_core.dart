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

  /// کتابخانه خود هسته، با نام آمبرلا.
  ///
  /// در ۱٫۰٫۲ عوض کردن این نام خطرناک بود: فایل اجرایی همراه بسته، کتابخانه
  /// را با پیوند نام صدا می زد و ویندوز پیش از اجرا آن را با 0xC0000135
  /// (کتابخانه پیدا نشد) می بست. حالا لانچر خودمان (`UmbrellaCli.exe`) کتابخانه
  /// را با مسیر بار می کند ([LoadLibraryExW])، پس نام فایل آزاد است و نام
  /// آمبرلا هم همین جا انتخاب شده تا در Explorer هم چیزی جز آمبرلا دیده نشود.
  ///
  /// لانچر نام قدیمی را هم به عنوان جایگزین امتحان می کند، تا ارتقای درجا از
  /// نسخه ای که فایل را با نام قدیمی نصب کرده هم کار کند.
  static const String coreDll = 'UmbrellaCore.dll';

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
    String remoteDns = defaultDns,
    String directDns = defaultDns,
    bool disableColor = true,
  }) {
    return <String>[
      'run',
      '-c',
      links,
      '-D',
      runDir,
      if (settingsPath.isNotEmpty) ...<String>['-d', settingsPath],
      // با فایل تنظیمات، خود فایل همه چیز را می گوید (و پرچم ها را نادیده
      // می گیرد)؛ این پرچم ها فقط برای اجرای بدون فایل (سنجش پینگ) هستند.
      if (settingsPath.isEmpty) ...<String>['--in-proxy-port', '${port ?? UmbrellaCore.port}'],
      if (settingsPath.isEmpty && tun) '--tun',
      if (settingsPath.isEmpty && systemProxy && !tun) '--system-proxy',
      if (settingsPath.isEmpty) ...<String>['--dns-remote', remoteDns],
      if (settingsPath.isEmpty) ...<String>['--dns-direct', directDns],
      '--log-level',
      logLevel,
      if (disableColor) '--disable-color',
    ];
  }

  /// دی ان اس پیش فرض هسته (همان پیش فرض خودش در `DefaultHiddifyOptions`).
  static const String defaultDns = '1.1.1.1';

  /// فایل تنظیمات کامل هسته (`-d`).
  ///
  /// **تله‌ای که ۱٫۰٫۳ را شکست:** اگر `-d` داده شود، هسته فایل را با
  /// `json.Unmarshal` روی یک ساختار **خالی** می خواند و همه پیش فرض های خودش را
  /// کنار می گذارد (`readHiddifyOptionsAt` در `v2/hcore/standalone.go`). یعنی
  /// هر کلیدی که در فایل نباشد خالی و صفر می شود — و پرچم های خط فرمان هم دیگر
  /// اثری ندارند، چون پس از خواندن فایل اعمال می شوند. نتیجه در گزارش کاربر:
  /// `remote-dns-address` خالی ⇒ «نشانی سرور نامعتبر» از `v2/config/dns.go`،
  /// و `enable-tun` صفر ⇒ اصلاً تونلی ساخته نمی شد.
  ///
  /// پس این فایل باید **کامل** باشد: هر کلیدی که خود هسته در
  /// `DefaultHiddifyOptions` می گذارد، با همان مقدار، به اضافه انتخاب های ما.
  /// [args] دیگر نباید `-tun`/`--system-proxy`/`--in-proxy-port` را هم بفرستد؛
  /// همان ها اینجا هستند. اگر روزی کلیدی از هسته اضافه شد و اینجا نبود، همان
  /// مقدار پیش فرض خودش (صفر) می شود؛ برای همین تا جای ممکن همه می نویسیم.
  static Map<String, dynamic> settingsJson({
    required bool tun,
    required bool systemProxy,
    required int port,
    String logLevel = 'info',
    String logFile = '',
    String remoteDns = defaultDns,
    String directDns = defaultDns,
  }) {
    return <String, dynamic>{
      // ── گزارش ──────────────────────────────────────────────────────────
      'log-level': logLevel,
      'log-file': logFile,
      // ── ورودی ها (تونل یا پروکسی سیستمی) ───────────────────────────────
      'enable-tun': tun,
      'enable-tun-service': false,
      'set-system-proxy': systemProxy && !tun,
      'delegate-system-proxy': false,
      'mixed-port': port,
      'enable-mixed-port': true,
      'tproxy-port': 12335,
      'redirect-port': 12336,
      'direct-port': 12337,
      'lan-sharing-port': 12338,
      'local-proxy-auth': false,
      'local-proxy-in-vpn': false,
      // پیش فرض خود هسته: `sing15` یعنی پشته پیش فرض sing-tun و `9000` همان
      // ام تی یو خودش. صفر گذاشتن این دو، تونل را بی بسته می کند.
      'tun-implementation': 'sing15',
      'mtu': 9000,
      'strict-route': true,
      'auto-redirect': true,
      'router-mode': false,
      // ── دی ان اس: خالی گذاشتن این دو، هسته را با «نشانی نامعتبر» می بندد ──
      'remote-dns-address': remoteDns,
      'direct-dns-address': directDns,
      'remote-dns-domain-strategy': 'as_is',
      'direct-dns-domain-strategy': 'as_is',
      'independent-dns-cache': false,
      'enable-fake-dns': false,
      // ── مسیر و انتخاب سرور ────────────────────────────────────────────
      'region': 'other',
      // زنجیره (chain) خاموش: مقدار خالی «off» است؛ با ایمن سازی، دی ان اس
      // گروه اضافه ای می سازد که این نسخه لازم ندارد.
      'chain-status': 'off',
      'ipv6-mode': 'as_is',
      'resolve-destination': false,
      'bypass-lan': false,
      'allow-connection-from-lan': false,
      'block-quic': false,
      'block-ads': false,
      'enable-full-config': false,
      'use-xray-core-when-possible': false,
      'enable-clash-api': false,
      'clash-api-port': 16756,
      'web-secret': '',
      'connection-test-url': AppConfig.speedTestUrl,
      'url-test-interval': 600,
      // سرعت انتخاب سرور در خود هسته: بهترین گره نگه داشته می شود، پس اگر
      // یک سرور افت کرد، خود هسته بدون قطعی سراغ بعدی می رود.
      'keep-top': 3,
      // ── بقیه پیش فرض های هسته، تا صفر نشوند ───────────────────────────
      'enable-ntp': true,
      // اگر کلید نباشد، «خاموش» خوانده می شود و هسته به جای TLS خود ویندوز
      // از uTLS کروم استفاده می کند؛ پیش فرض خودش روشن است.
      'use-system-tls-engine': true,
      'mux': <String, dynamic>{
        'enable': false,
        'padding': true,
        'max-streams': 8,
        'protocol': 'h2mux',
      },
      'tls-tricks': <String, dynamic>{
        'enable-fragment': false,
        'fragment-size': '10-100',
        'fragment-sleep': '50-200',
        'mixed-sni-case': false,
        'enable-padding': false,
        'padding-size': '1200-1500',
      },
      'rules': <dynamic>[],
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
