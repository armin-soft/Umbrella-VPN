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
    String logLevel = CoreLogLevel.defaultLevel,
    String settingsPath = '',
    String remoteDns = defaultRemoteDns,
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

  /// متغیر محیطی مالک پردازش؛ لانچر بومی (`umbrella_launcher.c`) به محض بسته
  /// شدن این PID همه پردازش های هسته و پنجره CLI را کامل می بندد.
  static Map<String, String> ownerEnvironment([
    Map<String, String> extra = const <String, String>{},
  ]) =>
      <String, String>{
        ...extra,
        'UMBRELLA_OWNER_PID': '$pid',
      };

  /// بستن نمونه های بازمانده و زیرشاخه هایشان پیش از اجرا یا هنگام خروج.
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
          <String>['/F', '/T', '/IM', name],
          runInShell: false,
        );
      } on Exception {
        // نمونه ای با این نام باز نبود.
      }
    }
  }

  /// ترجمه کدهای خروج و استثناهای سطح پایین ویندوز (NTSTATUS) هسته به فارسی روشن.
  static String describeWindowsExitCode(int code) {
    final int unsigned = code & 0xFFFFFFFF;
    if (unsigned == 0x40010004) {
      final String codeFa = Fa.num(unsigned);
      return 'هسته به دلیل خاموشی یا راه اندازی مجدد ویندوز بسته شد (کد $codeFa).';
    }
    if (unsigned < 0x80000000) {
      return '';
    }
    final String codeFa = Fa.num(unsigned);
    return switch (unsigned) {
      0xC000013A => 'هسته با سیگنال توقف بسته شد (کد $codeFa).',
      0xC0000135 =>
        'کتابخانه مورد نیاز هسته پیدا نشد (کد $codeFa)؛ برنامه را با فایل نصب رسمی دوباره نصب کنید.',
      0xC0000142 =>
        'راه اندازی کتابخانه هسته ناموفق بود (کد $codeFa)؛ پوشه نصب را در استثنای آنتی ویروس بگذارید.',
      0xC0000005 =>
        'خطای غیرمنتظره دسترسی حافظه در هسته (کد $codeFa)؛ جزئیات در بخش رویدادهای ویندوز ثبت شده است.',
      0xC0000409 =>
        'سرریز بافر محافظت شده در هسته (کد $codeFa)؛ دوباره متصل شوید.',
      0xC00000FD => 'سرریز پشته در هسته (کد $codeFa)؛ دوباره متصل شوید.',
      0xC0000374 => 'آسیب حافظه داخلی در هسته (کد $codeFa)؛ دوباره متصل شوید.',
      0xC0000017 => 'حافظه آزاد سیستم برای اجرای هسته کافی نبود (کد $codeFa).',
      0xC000001D => 'دستورالعمل پردازنده ناسازگار در هسته (کد $codeFa).',
      0xC000009A => 'منابع سیستمی کافی برای اجرای هسته در دسترس نبود (کد $codeFa).',
      0xC0000094 => 'خطای محاسباتی غیرمنتظره در هسته (کد $codeFa)؛ دوباره متصل شوید.',
      0xE06D7363 =>
        'خطای پردازش داخلی در کتابخانه هسته (کد $codeFa)؛ دوباره تلاش کنید.',
      _ => 'هسته به صورت غیرمنتظره متوقف شد (کد ویندوز $codeFa).',
    };
  }

  /// قوانین مسدودسازی آفلاین و آنی کنترل محتوا برای سه دسته همگام با ربات تلگرام
  static const String _geoRuleSetBase =
      'https://raw.githubusercontent.com/$id/$id-geo/rule-set';

  /// نشانی قوانین داخلی مسدودسازی محتوا که با فایل های محلی `.srs` همراه برنامه جایگزین می شوند.
  static const String _localFilterRuleSetBase = 'https://local.umbrella';

  /// مجموعه قوانین رسمی مسدودسازی تبلیغات، بدافزار، فیشینگ و استخراج رمز ارز در هسته.
  static const List<String> adBlockRuleSetUrls = <String>[
    '$_geoRuleSetBase/block/geoip-phishing.srs',
    '$_geoRuleSetBase/block/geoip-malware.srs',
    '$_geoRuleSetBase/block/geosite-malware.srs',
    '$_geoRuleSetBase/block/geosite-phishing.srs',
    '$_geoRuleSetBase/block/geosite-cryptominers.srs',
    '$_geoRuleSetBase/block/geosite-category-ads-all.srs',
  ];

  /// الگوی نشانی قوانین منطقه ای هسته (مستقیم کردن سایت ها و آی پی های داخلی).
  static List<String> regionalRuleSetUrls(String regionCode) => <String>[
        '$_geoRuleSetBase/country/geoip-$regionCode.srs',
        '$_geoRuleSetBase/country/geosite-$regionCode.srs',
      ];

  /// (`adult`, `gambling`, `ads`) و دامنه های سفارشی کاربر.
  ///
  /// هر دسته قوانین آفلاین فوری (`domain_suffix` و `domain_keyword`) به صورت قوانین
  /// مجزا دارد و مجموعه قوانین کامل `.srs` همراه برنامه را نیز به شکل قانون مستقل
  /// اعمال می کند تا هر نوع تطبیق (`OR`) بدون دانلود اینترنتی در لایه DNS و مسیر/SNI عمل کند.
  static List<Map<String, dynamic>> contentControlRules(
    FilterSettings? filter, {
    int startOrder = 0,
    bool includeRemoteRuleSets = true,
  }) {
    if (filter == null || !filter.enabled) {
      return const <Map<String, dynamic>>[];
    }
    final List<Map<String, dynamic>> rules = <Map<String, dynamic>>[];
    int order = startOrder;

    for (final String category in filter.activeBotCategories) {
      final _CategoryFilterSpec? spec = _categoryFilterSpecs[category];
      if (spec == null) continue;
      if (spec.suffixes.isNotEmpty) {
        rules.add(<String, dynamic>{
          'list_order': order++,
          'enabled': true,
          'name': 'umbrella-filter-$category',
          'outbound': 'block',
          'domain_suffix': spec.suffixes,
        });
      }
      if (spec.keywords.isNotEmpty) {
        rules.add(<String, dynamic>{
          'list_order': order++,
          'enabled': true,
          'name': 'umbrella-filter-$category',
          'outbound': 'block',
          'domain_keyword': spec.keywords,
        });
      }
      if (includeRemoteRuleSets && spec.ruleSets.isNotEmpty) {
        rules.add(<String, dynamic>{
          'list_order': order++,
          'enabled': true,
          'name': 'umbrella-filter-$category',
          'outbound': 'block',
          'rule_set': spec.ruleSets,
        });
      }
    }

    final List<String> custom = filter.normalizedCustomDomains;
    if (custom.isNotEmpty) {
      rules.add(<String, dynamic>{
        'list_order': order++,
        'enabled': true,
        'name': 'umbrella-filter-custom',
        'outbound': 'block',
        'domain_suffix': custom,
      });
    }
    return rules;
  }

  /// بررسی قطعی و آفلاین اینکه آیا یک نام میزبان توسط قوانین کنترل محتوا مسدود می شود.
  static bool matchesContentFilter(FilterSettings? filter, String rawHost) =>
      matchesContentFilterCategory(filter, rawHost) != null;

  /// تعیین کلید دقیق دسته کنترل محتوا (`custom`, `adult`, `gambling`, `ads`)
  /// که نام میزبان را مسدود کرده است (یا `null` در صورت مجاز بودن).
  static String? matchesContentFilterCategory(
    FilterSettings? filter,
    String rawHost,
  ) {
    if (filter == null || !filter.hasActiveRules) {
      return null;
    }
    final String? host = FilterSettings.normalizeDomainSuffix(rawHost);
    final String probe = (host ?? rawHost.trim().toLowerCase())
        .replaceFirst(RegExp(r'\.+$'), '');
    if (probe.isEmpty) {
      return null;
    }
    bool matchesSuffix(String suffix) =>
        probe == suffix || probe.endsWith('.$suffix');

    for (final String custom in filter.normalizedCustomDomains) {
      if (matchesSuffix(custom)) {
        return 'custom';
      }
    }
    for (final String category in filter.activeBotCategories) {
      final _CategoryFilterSpec? spec = _categoryFilterSpecs[category];
      if (spec == null) continue;
      if (spec.suffixes.any(matchesSuffix)) {
        return category;
      }
      if (spec.keywords.any(probe.contains)) {
        return category;
      }
    }
    return null;
  }

  /// کلیدواژه ها و پسوندهای اختصاصی دسته های کنترل محتوای نیازمند صفحه مسدودی
  /// (همه دسته های غیر از تبلیغات).
  static bool isPrimaryBlockSiteHost(String rawHost) {
    final String? host = FilterSettings.normalizeDomainSuffix(rawHost);
    final String probe = (host ?? rawHost.trim().toLowerCase())
        .replaceFirst(RegExp(r'\.+$'), '');
    if (probe.isEmpty) return false;
    bool matchesSuffix(String suffix) =>
        probe == suffix || probe.endsWith('.$suffix');
    for (final String category in const <String>['adult', 'gambling']) {
      final _CategoryFilterSpec? spec = _categoryFilterSpecs[category];
      if (spec == null) continue;
      if (spec.suffixes.any(matchesSuffix) || spec.keywords.any(probe.contains)) {
        return true;
      }
    }
    return false;
  }

  /// بررسی اینکه آیا نام میزبان در فهرست تبلیغات/ردیاب مسدودی همیشگی قرار دارد یا خیر.
  static bool isAlwaysBlockedAdHost(String rawHost) {
    final String? host = FilterSettings.normalizeDomainSuffix(rawHost);
    final String probe = (host ?? rawHost.trim().toLowerCase())
        .replaceFirst(RegExp(r'\.+$'), '');
    if (probe.isEmpty) return false;
    final _CategoryFilterSpec? adSpec = _categoryFilterSpecs['ads'];
    if (adSpec == null) return false;
    bool matchesSuffix(String suffix) =>
        probe == suffix || probe.endsWith('.$suffix');
    return adSpec.suffixes.any(matchesSuffix) ||
        adSpec.keywords.any(probe.contains);
  }

  static const Map<String, _CategoryFilterSpec> _categoryFilterSpecs =
      <String, _CategoryFilterSpec>{
    'adult': _CategoryFilterSpec(
      ruleSets: <String>[
        '$_localFilterRuleSetBase/filter-adult.srs',
      ],
      suffixes: <String>[
        'xxx',
        'porn',
        'sex',
        'adult',
        'pornhub.com',
        'phncdn.com',
        'xvideos.com',
        'xv-cdn.com',
        'xnxx.com',
        'xnxx-cdn.com',
        'xhamster.com',
        'xhamsterlive.com',
        'xhcdn.com',
        'redtube.com',
        'rdtcdn.com',
        'youporn.com',
        'ypncdn.com',
        'spankbang.com',
        'sb-cd.com',
        'onlyfans.com',
        'fansly.com',
        'chaturbate.com',
        'highwebmedia.com',
        'mmcdn.com',
        'stripchat.com',
        'bongacams.com',
        'bngpt.com',
        'livejasmin.com',
        'myfreecams.com',
        'cam4.com',
        'camsoda.com',
        'flirt4free.com',
        'imlive.com',
        'brazzers.com',
        'realitykings.com',
        'bangbros.com',
        'naughtyamerica.com',
        'mofos.com',
        'vixen.com',
        'tushy.com',
        'blacked.com',
        'eporner.com',
        'hqporner.com',
        'beeg.com',
        'tnaflix.com',
        'drtuber.com',
        'sunporno.com',
        'txxx.com',
        'upornia.com',
        'fuq.com',
        'tube8.com',
        'xtube.com',
        'motherless.com',
        'redgifs.com',
        'rule34.xxx',
        'rule34.paheal.net',
        'nhentai.net',
        'hanime.tv',
        'e-hentai.org',
        'gelbooru.com',
        'danbooru.donmai.us',
        'javhd.com',
        'missav.com',
        'jable.tv',
        'porn.com',
        'sex.com',
        'erome.com',
        'fapello.com',
        'literotica.com',
      ],
      keywords: <String>[
        'pornhub',
        'xvideos',
        'xnxx',
        'xhamster',
        'redtube',
        'youporn',
        'spankbang',
        'chaturbate',
        'bongacams',
        'brazzers',
        'sexvid',
        'sexcam',
        'sextube',
        'hentai',
      ],
    ),
    'gambling': _CategoryFilterSpec(
      ruleSets: <String>[
        '$_localFilterRuleSetBase/filter-gambling.srs',
      ],
      suffixes: <String>[
        'bet',
        'casino',
        'poker',
        'bingo',
        'lotto',
        'bet365.com',
        '1xbet.com',
        '1xstavka.ru',
        'melbet.com',
        'mostbet.com',
        'linebet.com',
        'megapari.com',
        '22bet.com',
        '20bet.com',
        'betwinner.com',
        'betway.com',
        'betfair.com',
        'pokerstars.com',
        'ggpoker.com',
        'partypoker.com',
        '888casino.com',
        '888poker.com',
        '888sport.com',
        'bwin.com',
        'unibet.com',
        'stake.com',
        'roobet.com',
        'rollbit.com',
        'duelbits.com',
        'gamdom.com',
        'bc.game',
        'parimatch.com',
        'williamhill.com',
        'ladbrokes.com',
        'coral.co.uk',
        'paddypower.com',
        'betvictor.com',
        'betano.com',
        'betsson.com',
        'leovegas.com',
        'pinnacle.com',
        'draftkings.com',
        'fanduel.com',
        'betmgm.com',
        'bovada.lv',
        'betonline.ag',
        'mybookie.ag',
        'dafabet.com',
        '188bet.com',
        'sbobet.com',
        'winamax.fr',
        'polymarket.com',
        'betforward.com',
        'cannonbet.com',
        'hazarat.com',
        'takbet.com',
        'jetbet.com',
        'hotbet.com',
        'abt90.com',
        'tinobet.com',
        'yasbet.com',
        'pinbahis.com',
        'shartbandi.com',
        'persianbet.com',
      ],
      keywords: <String>[
        '1xbet',
        'melbet',
        'bet365',
        'mostbet',
        'linebet',
        'megapari',
        'pokerstars',
        'betforward',
        'cannonbet',
        'shartbandi',
        'enfejar',
        'casino',
        'betting',
      ],
    ),
    'ads': _CategoryFilterSpec(
      ruleSets: <String>[
        '$_localFilterRuleSetBase/filter-ads.srs',
        '$_localFilterRuleSetBase/filter-youtube-ads.srs',
      ],
      suffixes: <String>[
        'doubleclick.net',
        'googlesyndication.com',
        'googleadservices.com',
        'google-analytics.com',
        'googletagmanager.com',
        'googletagservices.com',
        'adservice.google.com',
        '2mdn.net',
        'adnxs.com',
        'adsrvr.org',
        'taboola.com',
        'outbrain.com',
        'criteo.com',
        'criteo.net',
        'pubmatic.com',
        'rubiconproject.com',
        'openx.net',
        'casalemedia.com',
        'indexww.com',
        'smartadserver.com',
        'advertising.com',
        'adform.net',
        'moatads.com',
        'scorecardresearch.com',
        'quantserve.com',
        'popads.net',
        'popcash.net',
        'propellerads.com',
        'adsterra.com',
        'exoclick.com',
        'exosrv.com',
        'juicyads.com',
        'trafficjunky.net',
        'trafficstars.com',
        'hilltopads.net',
        'clickadu.com',
        'mgid.com',
        'revcontent.com',
        'amazon-adsystem.com',
        'ads-twitter.com',
        'ads.yahoo.com',
        'ads.linkedin.com',
        'ads.tiktok.com',
        'analytics.tiktok.com',
        'an.facebook.com',
        'pixel.facebook.com',
        'adcolony.com',
        'unityads.unity3d.com',
        'applovin.com',
        'vungle.com',
        'ironsrc.com',
        'chartboost.com',
        'inmobi.com',
        'startappservice.com',
        'appsflyer.com',
        'adjust.com',
        'hotjar.com',
        'mouseflow.com',
        'clarity.ms',
        'mc.yandex.ru',
        'an.yandex.ru',
        'yektanet.com',
        'tapsell.ir',
        'sabavision.com',
        'mediaad.org',
        'kaprila.com',
        'adivery.com',
        'najva.com',
        'deemanetwork.com',
        'raykaad.com',
      ],
      keywords: <String>[
        'doubleclick',
        'googlesyndication',
        'googleadservices',
        'adserver',
        'popads',
        'propellerads',
        'adsterra',
        'exoclick',
      ],
    ),
  };

  /// پورت های رزروشده ای که همین حالا گرفته اند.
  static Future<List<int>> heldReservedPorts() async {
    final List<bool> states = await Future.wait<bool>(
      reservedPorts.map(inUse),
    );
    return <int>[
      for (int i = 0; i < reservedPorts.length; i++)
        if (states[i]) reservedPorts[i],
    ];
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
        ports.map((int port) => '\$_.LocalPort -eq $port').join(' -or ');
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

  /// دی ان اس پیش فرض هسته (هم راستا با Hiddify: راه دور `tcp://8.8.8.8` و
  /// مستقیم `1.1.1.1` / `udp://1.1.1.1`).
  static const String defaultRemoteDns = NetworkDns.defaultRemote;
  static const String defaultDns = NetworkDns.defaultDirect;

  /// فایل تنظیمات کامل هسته (`-d`).
  ///
  /// **تله ای که ۱٫۰٫۳ را شکست:** اگر `-d` داده شود، هسته فایل را با
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
  static String _toIpCidr(String value) {
    if (value.contains('/')) {
      return value;
    }
    final InternetAddress? addr = InternetAddress.tryParse(value);
    if (addr == null) {
      return value;
    }
    return addr.type == InternetAddressType.IPv6 ? '$value/128' : '$value/32';
  }

  static Map<String, dynamic> settingsJson({
    required bool tun,
    required bool systemProxy,
    required int port,
    String logLevel = CoreLogLevel.defaultLevel,
    String logFile = '',
    String remoteDns = defaultRemoteDns,
    String directDns = defaultDns,
    AppSettings? networkSettings,
    FilterSettings? contentFilter,
    bool isolatedProbe = false,
    bool batterySaving = false,
    bool includeFilterRuleSets = true,
  }) {
    final String normalizedLog =
        CoreLogLevel.normalize(networkSettings?.logLevel ?? logLevel);
    final bool timedDiagnostic =
        normalizedLog == 'debug' || normalizedLog == 'trace';
    // در `hiddify-core v5.9.11` به محض ارسال `route-rule`، قوانین داخلی
    // `block-ads`، `bypass-lan` و `region` خاموش می شوند (`useAppRules`).
    // بنابراین قوانین با ترتیب اولویت دقیق ساخته می شوند:
    // ۱) کنترل محتوا (بالاترین اولویت — حتی دامنه داخلی هم اگر مسدود شده رد می شود)
    // ۲) مسیریابی بر اساس برنامه (در همه حالت های سرویس روی ویندوز فعال است)
    // ۳) مسدودسازی تبلیغات و بدافزار (در صورت روشن بودن `blockAds`)
    // ۴) مسیریابی مستقیم منطقه انتخابی (مانند `.ir` + `geoip-ir` + `geosite-ir`)
    // قانون `bypass-lan` (`ip_is_private`) نیز در `RuntimeConfig.finalize` حفظ می شود.
    final List<Map<String, dynamic>> combinedRules = <Map<String, dynamic>>[];
    if (!isolatedProbe) {
      final List<Map<String, dynamic>> filterRules = contentControlRules(
        contentFilter,
        startOrder: 0,
        includeRemoteRuleSets: includeFilterRuleSets,
      );
      combinedRules.addAll(filterRules);
      // Content blocks precede user direct routes, so bypass cannot defeat an
      // administrator policy. The core also emits matching direct DNS rules.
      if (contentFilter != null && contentFilter.bypassDomains.isNotEmpty) {
        final List<String> directDomains = <String>[];
        final List<String> directCidrs = <String>[];
        for (final String rawTarget in contentFilter.bypassDomains) {
          final String? normalized =
              FilterSettings.normalizeBypassTarget(rawTarget);
          if (normalized == null) continue;
          if (FilterSettings.isIpOrCidr(normalized)) {
            final String cidr = _toIpCidr(normalized);
            if (!directCidrs.contains(cidr)) directCidrs.add(cidr);
          } else {
            if (!directDomains.contains(normalized)) {
              directDomains.add(normalized);
            }
          }
        }
        if (directDomains.isNotEmpty) {
          combinedRules.add(<String, dynamic>{
            'list_order': combinedRules.length,
            'enabled': true,
            'name': 'umbrella-bypass-user',
            'outbound': 'direct',
            'domain_suffix': directDomains,
          });
        }
        if (directCidrs.isNotEmpty) {
          combinedRules.add(<String, dynamic>{
            'list_order': combinedRules.length,
            'enabled': true,
            'name': 'umbrella-bypass-user-ip',
            'outbound': 'direct',
            'ip_cidr': directCidrs,
          });
        }
      }
      if (contentFilter?.bypassIran ?? false) {
        combinedRules.add(<String, dynamic>{
          'list_order': combinedRules.length, 'enabled': true,
          'name': 'umbrella-bypass-iran', 'outbound': 'direct',
          'domain_suffix': <String>['.ir'],
        });
        // Keep suffix, geosite and geoip independent: they are alternatives,
        // and only name-based sets should generate DNS rules.
        for (final String url in regionalRuleSetUrls('ir')) {
          combinedRules.add(<String, dynamic>{
            'list_order': combinedRules.length, 'enabled': true,
            'name': 'umbrella-bypass-iran-set', 'outbound': 'direct',
            'rule_set': <String>[url],
          });
        }
      }

      if (networkSettings != null) {
        for (final AppRouteRule route in networkSettings.appRoutes) {
          final Map<String, dynamic> built =
              route.toCoreRule(combinedRules.length);
          if (route.enabled) {
            combinedRules.add(built);
          }
        }
      }

      if (!isolatedProbe && includeFilterRuleSets) {
        final bool adsAlreadyInFilter = (contentFilter?.enabled ?? false) &&
            (contentFilter?.activeBotCategories.contains('ads') ?? false);
        final _CategoryFilterSpec? adSpec = _categoryFilterSpecs['ads'];
        if (!adsAlreadyInFilter && adSpec != null) {
          if (adSpec.suffixes.isNotEmpty) {
            combinedRules.add(<String, dynamic>{
              'list_order': combinedRules.length,
              'enabled': true,
              'name': 'umbrella-block-ads',
              'outbound': 'block',
              'domain_suffix': adSpec.suffixes,
            });
          }
          if (adSpec.keywords.isNotEmpty) {
            combinedRules.add(<String, dynamic>{
              'list_order': combinedRules.length,
              'enabled': true,
              'name': 'umbrella-block-ads',
              'outbound': 'block',
              'domain_keyword': adSpec.keywords,
            });
          }
          combinedRules.add(<String, dynamic>{
            'list_order': combinedRules.length,
            'enabled': true,
            'name': 'umbrella-block-ads',
            'outbound': 'block',
            'rule_set': <String>[
              ...adBlockRuleSetUrls,
              ...adSpec.ruleSets,
            ],
          });
        }
      }

      if (networkSettings != null) {
        final RoutingRegion region = networkSettings.routingRegion;
        if (region != RoutingRegion.other) {
          final String code = region.coreValue;
          combinedRules.add(<String, dynamic>{
            'list_order': combinedRules.length,
            'enabled': true,
            'name': 'umbrella-region-$code',
            'outbound': 'direct',
            'domain_suffix': <String>['.$code'],
          });
          for (final String url in regionalRuleSetUrls(code)) {
            combinedRules.add(<String, dynamic>{
              'list_order': combinedRules.length,
              'enabled': true,
              'name': 'umbrella-region-$code',
              'outbound': 'direct',
              'rule_set': <String>[url],
            });
          }
        }
      }
    }
    final int validLanPort = networkSettings != null &&
            LanSharing.isValidPort(
              networkSettings.lanSharingPort,
              forbiddenPort: port,
            )
        ? networkSettings.lanSharingPort
        : (port == LanSharing.defaultLanPort
            ? LanSharing.defaultLanPort + 1
            : LanSharing.defaultLanPort);
    final bool lanShared =
        !isolatedProbe && (networkSettings?.allowConnectionFromLan ?? false);
    final String proxySecret =
        isolatedProbe ? '' : (networkSettings?.lanSharingPassword.trim() ?? '');
    final bool localAuth = !isolatedProbe &&
        !(systemProxy && !tun) &&
        (networkSettings?.localProxyAuth ?? false) &&
        proxySecret.isNotEmpty;
    final TlsTricksSettings tlsTricks =
        networkSettings?.tlsTricks ?? const TlsTricksSettings();
    return <String, dynamic>{
      // ── گزارش (با بازگشت خودکار ۱۰ دقیقه ای در سطح عیب یابی هم راستا با 5.9.11) ──
      'log-level': normalizedLog,
      if (timedDiagnostic) ...<String, dynamic>{
        'log-level-until': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 10))
            .toIso8601String(),
        'log-level-after': 'warn',
      },
      'log-file': logFile,
      // ── ورودی ها (VPN، پروکسی سیستمی یا پروکسی محلی + اشتراک LAN) ───────
      'enable-tun': tun,
      'enable-tun-service': false,
      'set-system-proxy': systemProxy && !tun,
      'delegate-system-proxy': false,
      'mixed-port': port,
      'enable-mixed-port': true,
      'enable-tproxy-port': false,
      'enable-redirect-port': false,
      'enable-direct-port': false,
      'tproxy-port': 12335,
      'redirect-port': 12336,
      'direct-port': 12337,
      'lan-sharing-port': validLanPort,
      if (proxySecret.isNotEmpty) 'lan-sharing-password': proxySecret,
      'local-proxy-auth': localAuth,
      'local-proxy-in-vpn': networkSettings?.localProxyInVpn ?? true,
      // پیش فرض خود هسته: `sing15` یعنی پشته پیش فرض sing-tun و `9000` همان
      // ام تی یو خودش. صفر گذاشتن این دو، تونل را بی بسته می کند.
      'tun-implementation': networkSettings == null ||
              networkSettings.tunStack == TunStack.auto
          ? 'sing15'
          : networkSettings.tunStack.name,
      'mtu': (networkSettings?.mtu ?? 9000).clamp(1280, 9000),
      'strict-route': networkSettings?.strictRoute ?? true,
      'auto-redirect': true,
      'router-mode': false,
      // ── دی ان اس: هم راستا با Hiddify (`tcp://8.8.8.8` تونل + `1.1.1.1` مستقیم) ──
      'remote-dns-address': networkSettings == null
          ? remoteDns
          : NetworkDns.normalizeRemote(networkSettings.remoteDns),
      'direct-dns-address': networkSettings == null
          ? directDns
          : NetworkDns.normalizeDirect(networkSettings.directDns),
      'remote-dns-domain-strategy':
          (networkSettings?.remoteDnsStrategy ?? DnsDomainStrategy.asIs)
              .coreValue,
      'direct-dns-domain-strategy':
          (networkSettings?.directDnsStrategy ?? DnsDomainStrategy.asIs)
              .coreValue,
      // در sing-box 1.14+ کش هر سرور DNS به صورت پیش فرض مستقل است و کلید
      // قدیمی `independent_cache: true` منسوخ شده و در `srun` خطای FATAL می دهد.
      'independent-dns-cache': false,
      'enable-fake-dns':
          !isolatedProbe && (networkSettings?.enableFakeDns ?? false),
      // ── مسیر و انتخاب سرور ────────────────────────────────────────────
      'region': (networkSettings?.routingRegion ?? RoutingRegion.other).coreValue,
      ...(networkSettings?.chain ?? const ChainSettings()).toCoreOptions(),
      if (combinedRules.isNotEmpty)
        'route-rule': <String, dynamic>{
          'rules': combinedRules,
        },
      // Match Hiddify's default `ipv4_only` (`verify_ipv6: false`) unless the
      // user explicitly enables IPv6 (`prefer_ipv4` / `prefer_ipv6`).
      'ipv6-mode': networkSettings == null
          ? 'ipv4_only'
          : networkSettings.ipv6RouteMode.coreValue,
      'resolve-destination': networkSettings?.resolveDestination ?? false,
      'bypass-lan': networkSettings?.bypassLan ?? false,
      'allow-connection-from-lan': lanShared,
      'block-quic': networkSettings?.blockQuic ?? false,
      'block-ads': !isolatedProbe && includeFilterRuleSets,
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
      // پایش اولیه در لحظه شروع اجرا بی درنگ انجام می شود؛ دوره بازسنجی
      // ۱۸۰ ثانیه است تا اتصال های باز کاربر هر ۳۰ ثانیه با سوییچ بی مورد قطع
      // نشوند ولی اگر گرهی افت کرد به موقع جایگزین شود.
      // هم راستا با Hiddify (۱۰ دقیقه = ۶۰۰ ثانیه؛ در حالت بهینه سازی باتری ۳۰ دقیقه):
      // پایش اولیه در لحظه شروع بی درنگ اجرا می شود و از بازسنجی های پرفشار جلوگیری می شود.
      'url-test-interval': batterySaving ? 1800 : 600,
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
      // هم راستا با Hiddify: چرخش خودکار بین همه سرویس های ipinfo + پشتیبان Cloudflare trace.
      'ipinfo-url': '',
      // چند گره زنده بمانند تا خود هسته بتواند سوییچ کند.
      //
      // ۳ خیلی کم بود: با ۳ گره، اگر دو تای اول کند یا افتاده باشند کار
      // تمام است و کاربر فقط «سرور عوض کن» می بیند. ۸ تعادل است بین
      // سرعت اجرا و داشتن جایگزین.
      // هم راستا با پیش فرض Hiddify (`keep-top: -1`): بدون صف بندی مرحله ای روی
      // اشتراک های متعارف تا سریع ترین گره در زیر یک ثانیه پاسخ دهد؛ روی اشتراک های
      // بسیار بزرگ، `RuntimeConfig.finalize` خودکار `keep_top` مرحله ای می سازد.
      'keep-top': -1,
      'keep-top-quick': true,
      // انتخاب پیش فرض روی گروه «کم ترین تاخیر» (`lowest`) است تا سریع ترین
      // گره سالم برداشته شود و هنگام افتادن بی درنگ به بعدی برود؛ اگر کاربر
      // یکی از حالت های توزیع بار را برگزیده باشد روی گروه `balance` با همان
      // راهبرد می رود.
      ..._selectionOptions(networkSettings?.selectionMode),
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
        // چیزی که زیکس ری هم به طور پیش فرض انجام می دهد و ریلیتی با آن کار
      // می کند. هزینه اش فقط این است که گره های TLS معمولی هم از uTLS می روند.
      'use-system-tls-engine': false,
      'mux': <String, dynamic>{
        'enable': false,
        'padding': true,
        'max-streams': 8,
        'protocol': 'h2mux',
      },
      'tls-tricks': tlsTricks.toCoreOptions(),
      'rules': <dynamic>[],
    };
  }

  /// نگاشت حالت انتخاب کاربر به کلیدهای واقعی گروه خروجی هسته.
  static Map<String, dynamic> _selectionOptions(SelectionMode? mode) {
    switch (mode) {
      case SelectionMode.roundRobin:
        return const <String, dynamic>{
          'default-proxy': 'balance',
          'balancer-strategy': 'round-robin',
        };
      case SelectionMode.consistentHash:
        return const <String, dynamic>{
          'default-proxy': 'balance',
          'balancer-strategy': 'consistent-hashing',
        };
      case SelectionMode.stickySession:
        return const <String, dynamic>{
          'default-proxy': 'balance',
          'balancer-strategy': 'sticky-sessions',
        };
      case SelectionMode.auto:
      case SelectionMode.manual:
      case null:
        return const <String, dynamic>{
          'default-proxy': 'lowest',
        };
    }
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
    if (lowerPath.isNotEmpty && lowerPath.contains('umbrella')) {
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

class _CategoryFilterSpec {
  const _CategoryFilterSpec({
    required this.suffixes,
    this.keywords = const <String>[],
    this.ruleSets = const <String>[],
  });

  final List<String> suffixes;
  final List<String> keywords;
  final List<String> ruleSets;
}
