import 'dart:io';

import '../core/app_config.dart';
import '../core/persian.dart';
import '../platform/native.dart';
import '../models/models.dart';

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

  /// پورت هایی که هسته **همیشه** می گیرد و راهی برای عوض کردنشان نیست.
  ///
  /// در نسخه ۵٫۹٫۱، دستور `run` سرور gRPC را روی `127.0.0.1:17078`
  /// (`buildStandaloneConfig` در `v2/hcore/standalone.go`) و رابط کلش را روی
  /// `127.0.0.1:16756` باز می کند؛ هر دو در خود هسته ثابت نوشته شده اند و
  /// هیچ پرچمی برای عوض کردنشان نیست (`run` فقط پرچم های `addHConfigFlags`
  /// را دارد؛ `--listen` مال دستور `core` است، نه `run`). پس اگر این پورت ها
  /// گرفته باشند، اجرا با «already in use» می میرد — دلیل شکست ۱٫۰٫۴.
  ///
  /// راه درست، آزاد کردن این پورت ها پیش از اجرا است، نه فرستادن پرچم.
  static const List<int> reservedPorts = <int>[
    AppConfig.coreGrpcPort,
    AppConfig.coreClashPort,
  ];

  /// پورت های خود برنامه (پروکسی مختلط و بقیه).
  ///
  /// اگر نمونه بازمانده ای این ها را گرفته باشد، هسته نمی تواند پروکسی را
  /// بالا بیاورد و اتصال با «پورت در اختیار» رد می شود — همان مشکلی که برای
  /// پورت های ثابت داشتیم.
  static const List<int> appPorts = <int>[
    AppConfig.httpPortUmbrella,
    12335,
    12336,
    12337,
    12338,
  ];

  /// همه پورت هایی که پیش از اتصال باید آزاد باشند.
  static const List<int> allPorts = <int>[...reservedPorts, ...appPorts];

  /// آیا این پورت روی لوکال هاست گرفته شده است؟
  static Future<bool> inUse(int port) async {
    ServerSocket? socket;
    try {
      socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: false,
      );
      return false;
    } on SocketException {
      return true;
    } finally {
      await socket?.close();
    }
  }

  /// بستن نمونه های بازمانده با نام، پیش از اجرای یک نمونه تازه.
  ///
  /// سنجش پینگ و اجرای اصلی هر دو پورت های ثابت هسته را می خواهند؛ یک نمونه
  /// که از دور قبل زنده مانده، پورت را گرفته و نمونه بعدی را می کشد.
  static Future<void> releasePorts() async {
    if (!Platform.isWindows) {
      return;
    }
    for (final String name in <String>[
      cliBinary,
      engineBinary,
      adminBinary,
    ]) {
      try {
        await Process.run(
          'taskkill',
          <String>['/F', '/IM', name],
          runInShell: false,
        );
      } on Exception {
        // نمونه ای با این نام باز نبود.
      }
    }
  }

  /// پورت های رزروشده ای که همین حالا گرفته اند.
  static Future<List<int>> heldReservedPorts() async {
    final List<int> held = <int>[];
    for (final int port in reservedPorts) {
      if (await inUse(port)) {
        held.add(port);
      }
    }
    return held;
  }

  /// نام برنامه ای که این پورت ها را گرفته است.
  ///
  /// قبلاً گزارش فقط می گفت «پورت در اختیار برنامه دیگری است» و کاربر نمی
  /// دانست چه را ببندد؛ در گزارش ۱٫۰۷ همین پیام چهار بار آمد و هیچ راهی برای
  /// پیدا کردن مقصر نداشت. با `Get-NetTCPConnection` نام فرایند خوانده می شود.
  static Future<String> portHolders(List<int> ports) async {
    if (!Platform.isWindows || ports.isEmpty) {
      return '';
    }
    final String filter =
        ports.map((int port) => "\$_.LocalPort -eq $port").join(' -or ');
    final String script =
        'Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | '
        'Where-Object { $filter } | '
        'ForEach-Object { '
        '\$p = Get-Process -Id \$_.OwningProcess -ErrorAction SilentlyContinue; '
        'if (\$p) { "\$(\$_.LocalPort)=\$(\$p.ProcessName)" } }';
    try {
      final ProcessResult result = await Process.run(
        'powershell',
        <String>['-NoProfile', '-NonInteractive', '-Command', script],
        runInShell: false,
      );
      final String out = '${result.stdout}'.trim();
      if (out.isEmpty) {
        return '';
      }
      final List<String> names = out
          .split(RegExp(r'\r?\n'))
          .map((String line) => line.trim())
          .where((String line) => line.isNotEmpty)
          .toSet()
          .toList();
      return names.join('، ');
    } on Exception {
      return '';
    }
  }

  /// پروسه هایی که این پورت ها را گرفته اند، با نام و مسیرشان.
  ///
  /// برای این که برنامه بتواند تصمیم بگیرد: اگر مال خودمان است ببندد، اگر
  /// برنامه دیگری است کاربر را خبر کند، و اگر مال نسخه دیگری از همان هسته
  /// است (مثل `Hiddify`) با نام درست گزارش دهد.
  static Future<List<PortHolder>> holders(
    List<int> ports, {
    required NativeBridge native,
  }) async {
    final List<PortHolder> found = <PortHolder>[];
    for (final int port in ports) {
      for (final int pid in await native.pidsHoldingPort(port)) {
        if (found.any((PortHolder h) => h.pid == pid)) {
          found
              .firstWhere((PortHolder h) => h.pid == pid)
              .ports
              .add(port);
          continue;
        }
        final String name = await native.processNameOf(pid);
        final String path = await native.processPathOf(pid);
        found.add(
          PortHolder(pid: pid, name: name, path: path, ports: <int>[port]),
        );
      }
    }
    return found;
  }

  /// بستن یک پردازش با شناسه.
  static Future<bool> killPid(
    int pid, {
    required NativeBridge native,
  }) async {
    if (pid <= 0) {
      return false;
    }
    return native.killPid(pid);
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
    AppSettings? networkSettings,
  }) {
    return <String, dynamic>{
      // ── گزارش ──────────────────────────────────────────────────────────
      'log-level': CoreLogLevel.normalize(networkSettings?.logLevel ?? logLevel),
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
      'local-proxy-in-vpn': true, // Loopback-only diagnostic path, also in TUN mode.
      // پیش فرض خود هسته: `sing15` یعنی پشته پیش فرض sing-tun و `9000` همان
      // ام تی یو خودش. صفر گذاشتن این دو، تونل را بی بسته می کند.
      'tun-implementation': networkSettings == null || networkSettings.tunStack == TunStack.auto
          ? 'sing15' : networkSettings.tunStack.name,
      'mtu': (networkSettings?.mtu ?? 9000).clamp(1280, 9000),
      'strict-route': networkSettings?.strictRoute ?? true,
      'auto-redirect': true,
      'router-mode': false,
      // ── دی ان اس: خالی گذاشتن این دو، هسته را با «نشانی نامعتبر» می بندد ──
      'remote-dns-address': networkSettings == null ? remoteDns : NetworkDns.normalize(networkSettings.remoteDns),
      'direct-dns-address': networkSettings == null ? directDns : NetworkDns.normalize(networkSettings.directDns),
      'remote-dns-domain-strategy': 'as_is',
      'direct-dns-domain-strategy': 'as_is',
      'independent-dns-cache': false,
      'enable-fake-dns': false,
      // ── مسیر و انتخاب سرور ────────────────────────────────────────────
      'region': 'other',
      ...(networkSettings?.chain ?? const ChainSettings()).toCoreOptions(),
      if (tun && networkSettings != null && networkSettings.appRoutes.isNotEmpty)
        'route-rule': <String, dynamic>{
          'rules': <Map<String, dynamic>>[
            for (int i = 0; i < networkSettings.appRoutes.length; i++)
              networkSettings.appRoutes[i].toCoreRule(i),
          ],
        },
      // In this core as_is still disables IPv6 for clients. PreferIPv4 allows
      // both families, while ipv4_only requests IPv4 client destinations.
      'ipv6-mode': networkSettings == null ? 'as_is'
          : networkSettings.blockIpv6 ? 'ipv4_only' : 'prefer_ipv4',
      'resolve-destination': false,
      'bypass-lan': false,
      'allow-connection-from-lan': false,
      'block-quic': false,
      'block-ads': false,
      'enable-full-config': false,
      'use-xray-core-when-possible': false,
      // رابط کلش روشن است؛ خود هسته در حالت `run` آن را روی ۱۶۷۵۶ باز می
      // کند و همین رابط است که گره ها را می سنجد و سرور سالم را نگه می دارد.
      'enable-clash-api': true,
      'clash-api-port': AppConfig.coreClashPort,
      // خالی گذاشتن این کلید یعنی هسته خودش رمز ناشناس می سازد و ما دیگر
      // نمی توانیم از رابط کلش بپرسیم (۴۰۱). رمز ثابت ما را ببینید در
      // `AppConfig.coreClashSecret`.
      'web-secret': AppConfig.coreClashSecret,
      // نشانی سنجش سلامت گره. پیش از این `speedTestUrl` بود که از داخل
      // ایران ۳۰۱/۴۰۳ می دهد، پس هسته گره سالم را «no answer» می خواند.
      'connection-test-url': AppConfig.connectionTestUrls.first,
      'connection-test-urls': AppConfig.connectionTestUrls,
      // هر ۳۰ ثانیه به جای ۶۰۰ تا گره تازه وصل‌شده سریع دیده شود.
      'url-test-interval': 30,
      // نشانی خواندن آی پی و موقعیت خروجی.
      //
      // این کلید در گزارش های پیشین تنظیم نشده بود، پس هسته خط
      // `MONITORING result <گره>: ... IP: ...` را نمی نوشت و ما همیشه
      // «آی پی خروجی خوانده نشد» می دیدیم.
      //
      // **درس ۱٫۰٫۱۸:** `ipapi.co` از این شبکه پاسخ ۴۰۳ (Forbidden) می داد
      // و هسته با `Failed try 0 to get IP info ... 403` رهایش می کرد؛
      // نتیجه همان «آی پی خروجی خوانده نشد» بود که به کلادفلر و گره ربطی
      // نداشت. `ipwho.is` همان قالب را می دهد، کلید می خواهد نه توکن، و
      // از داخل ایران هم باز است.
      'ipinfo-url': 'https://ipwho.is/',
      // چند گره زنده بمانند تا خود هسته بتواند سوییچ کند.
      //
      // ۳ خیلی کم بود: با ۳ گره، اگر دو تای اول کند یا افتاده باشند کار
      // تمام است و کاربر فقط «سرور عوض کن» می بیند. ۸ تعادل است بین
      // سرعت اجرا و داشتن جایگزین.
      'keep-top': 8,
      // مانند Hiddify، انتخاب سریع فعال است: هسته می تواند با تکیه بر سنجش های
      // تازه، زودتر مجموعه گزینه های سریع را برگزیند و پایش گره های اشتراک را
      // ادامه دهد. این گزینه لینک های جدید را از سنجش حذف نمی کند.
      'keep-top-quick': true,
      // انتخاب پیش فرض روی گروه «کم ترین تاخیر» باشد، نه گره اول.
      //
      // در `setOutbounds` خود هسته (`v2/config/builder.go`) مقدار `lowest`
      // یعنی `DefaultProxyLowest` و گروه انتخاب را روی بالانسر
      // `lowest-delay` می گذارد. یعنی سریع ترین گره برمی دارد و تا وقتی
      // یکی افت نکرده، همان می ماند؛ هنگام افتادن هم خودش به بعدی می رود.
      // `balancer-strategy` را عمداً نمی گذاریم: مقدارش در این نسخه هسته
      // با `lowest-delay` یکی نیست و پیکربندی را رد می کند.
      'default-proxy': 'lowest',
      // ── بقیه پیش فرض های هسته، تا صفر نشوند ───────────────────────────
      'enable-ntp': true,
      // موتور TLS ویندوز باید خاموش بماند.
      //
      // در ۱٫۰٫۱۲ این کلید روشن بود و ریلیتی را می کشت. هسته برای گرهی که
      // fingerprint ندارد TLS ویندوز را انتخاب می کند (engine=windows)، ولی
      // ریلیتی در همان فایل انتخاب موتور کنار گذاشته می شود و به دست دادن
      // پیش فرض می رسد، نه به اثر انگشت کروم. سرور ریلیتی دست دادن پیش فرض
      // را رد می کند و هیچ اتصالی برقرار نمی شود.
      //
      // خاموش گذاشتنش یعنی هسته uTLS با اثر انگشت کروم را برمی دارد؛ همان
      // چیزی که زیکس‌ری هم به طور پیش فرض انجام می دهد و ریلیتی با آن کار
      // می کند. هزینه اش فقط این است که گره های TLS معمولی هم از uTLS می روند.
      'use-system-tls-engine': false,
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

/// برنامه ای که یک پورت را گرفته است.
class PortHolder {
  PortHolder({
    required this.pid,
    required this.name,
    required this.path,
    required this.ports,
  });

  final int pid;

  /// نام فایل اجرایی، مثل `Hiddify.exe`.
  final String name;

  /// مسیر کامل؛ ممکن است خالی باشد اگر ویندوز اجازه خواندن نداد.
  final String path;

  final List<int> ports;

  /// آیا این پردازش هسته خود ماست؟
  ///
  /// نام اجرایی هسته `UmbrellaCli.exe` است، ولی فرزندهایش نام های دیگری
  /// دارند؛ همه با `umbrella` شروع می شوند.
  bool get isOurs => name.toLowerCase().startsWith('umbrella');

  /// آیا پورت را یک هسته *دیگر* گرفته، نه هسته خود آمبرلا؟
  ///
  /// **تله ای که ۱٫۰٫۱۵ را زمین زد:** در گزارش کاربر، هسته ای که خودمان
  /// اجرا کردیم (`UmbrellaCli.exe`، شناسه ۱۱۳۵۲) بلافاصله بسته شد، ولی
  /// صاحب پورت ۱۷۰۷۸ یک «هسته فیلترشکن دیگر» با شناسه ۱۳۶۰۰ بود. آن پورت
  /// در واقع **فرزند همان هسته خودمان** بود که هنوز یک لحظه زنده مانده بود.
  ///
  /// چون آن را «بیگانه» دیدیم، سه دور آزادسازی را صرف بستن فرزند کردیم و
  /// هر بار هسته تازه دوباره همان پورت را می گرفت. حلقه بی پایان شد و
  /// کاربر فقط پیام «هیچ هسته ای نتوانست» را دید.
  ///
  /// پس فقط وقتی پورت را «بیگانه» می دانیم که مسیرش با هسته خودمان یکی
  /// نباشد. اگر مسیر خوانده نشود، `isForeignCore` تصمیم می گیرد.
  bool get holdsPortAgainstUs {
    if (isOurs) {
      return false;
    }
    // مسیر یا نام، هر کدام که «آمبرلا» را داشته باشد یعنی مال ماست.
    //
    // **گزارش ۱٫۰۱۸:** پورت ۱۷۰۷۸ سه بار در دست «یک هسته فیلترشکن دیگر» با
    // شناسه های ۶۲۴۰ / ۴۷۲۸ / ۴۴۷۲ دیده شد و هر بار بسته شد، ولی هسته تازه
    // بلافاصله با «port 17078 is already in use» مرد. آن پردازش در واقع
    // **فرزند همان `UmbrellaCli.exe`** بود که نام اجرایی اش `UmbrellaCli…`
    // نبود و مسیرش هم خوانده نمی شد. پس فقط نام و مسیر کافی نیست؛ اگر پدرِ
    // پردازش مال ماست، پورت مال ماست.
    final String lowerPath = path.toLowerCase();
    final String lowerName = name.toLowerCase();
    if (lowerPath.isNotEmpty &&
        (lowerPath.contains('umbrella') || lowerPath.contains('umb\u200c'))) {
      return false;
    }
    if (lowerName.isNotEmpty &&
        (lowerName.contains('umbrella') || lowerName.contains('umb'))) {
      return false;
    }
    if (sameInstallerAsUs) {
      return false;
    }
    return isForeignCore;
  }

  /// آیا این پردازش از همان پوشه نصب ما اجرا شده است؟
  ///
  /// فرزندهای خود هسته (پروسه های کمکی و پردازش هایی که هسته با نام دیگری
  /// اجرا می کند) مسیرشان همان پوشه نصب آمبرلاست. بستن آن ها فقط هسته تازه
  /// را دوباره به همان جنگ پورت می اندازد.
  bool get sameInstallerAsUs {
    final String lower = path.toLowerCase();
    if (lower.isEmpty) {
      return false;
    }
    for (final String folder in <String>['umbrella vpn', 'umbrella-vpn', '\\umbrella\\']) {
      if (lower.contains(folder)) {
        return true;
      }
    }
    return false;
  }


  /// آیا این پردازش، هسته یک فیلترشکن است؟
  ///
  /// فقط نام های شناخته شده هسته؛ هیچ برنامه دیگری (مرورگر، بازی، سرویس
  /// ویندوز) در این فهرست نیست و هرگز بسته نمی شود. این فهرست داخلی است و
  /// هیچ جا نمایش داده نمی شود.
  bool get isForeignCore {
    if (isOurs) {
      return true;
    }
    final String lower = name.toLowerCase();
    if (lower.isEmpty) {
      return false;
    }
    return _coreNames.any(lower.startsWith);
  }

  static const List<String> _coreNames = <String>[
    'hiddify',
    'sing-box',
    'xray',
    'v2ray',
    'mihomo',
    'clash',
    'nekoray',
    'nekobox',
    'hysteria',
    'tuic',
    'wireguard',
    'amnezia',
    'awg',
    'mieru',
    'shadowsocks',
    'ss-local',
    'trojan',
    'naive',
    'openvpn',
    'outline',
    'psiphon',
    'warp',
    'tun2socks',
  ];

  /// نام نمایشی برای گزارش.
  ///
  /// نام هسته های شناخته شده با نام تجاری خودشان نوشته نمی شود؛ در تمام
  /// برنامه فقط «آمبرلا» دیده می شود. خود فایل روی دیسک دست نمی خورد و نام
  /// واقعی اش در بخش «مسیر» می آید، چون همان چیزی است که کاربر باید در
  /// Task Manager پیدا کند.
  String get label {
    if (name.isEmpty) {
      return 'پردازش با شناسه ${Fa.num(pid)}';
    }
    if (isForeignCore && !isOurs) {
      return 'یک هسته فیلترشکن دیگر';
    }
    return name;
  }
}
