import '../models/models.dart';

/// تنظیمات ثابت برنامه: نسخه، آدرس سرویس ها و تنها منابع اشتراک مجاز.
///
/// آدرس ها با `--dart-define` هم قابل تغییر هستند تا نصب های مختلف بدون
/// تغییر کد بتوانند به سرور خودشان وصل شوند.
class AppConfig {
  const AppConfig._();

  static const String appName = 'فیلترشکن آمبرلا';
  static const String shortName = 'آمبرلا';
  static const String version = '1.0.22';
  static const int buildNumber = 23;
  /// شماره نسخه برای نمایش، همان طور که در نوار کناری خواسته شد: `1.0.18`.
  ///
  /// از همان `version` ساخته می شود تا هیچ وقت عقب نماند (در ۱٫۰٫۸ اینجا
  /// هنوز «۱٫۰٫۰» نوشته بود). بدون کلمه «نسخه» و با رقم لاتین، چون کاربر
  /// دقیقا همین را زیر منوی کناری خواست.
  static String get versionLabel => version;

  /// همان شماره با پیشوند فارسی، برای جاهایی که متن جمله است (تنظیمات،
  /// گزارش خطا): «نسخه ۱٫۰٫۱۶».
  static String get versionPhrase => 'نسخه ${version.split('.').join('٫')}';
  static const String company = 'آرمین سافت';
  static const String developer = 'آرمین سافت';
  static const String developerSite = 'https://armin-soft.ir';
  static const String supportUrl = 'https://t.me/UmbrellaSupport';
  static const String channelUrl = 'https://t.me/UmbrellaChannel';
  static const String botUsername = String.fromEnvironment(
    'UMBRELLA_BOT',
    defaultValue: 'UmbrellaVPN_BOT',
  );

  /// درگاه برنامه (همان AppGateway ربات). مسیرها به آن اضافه می شوند:
  /// auth/start ، auth/verify ، auth/status ، auth/session ،
  /// account/refresh ، app/notifications ، filter/get ، filter/save
  static const String gatewayBase = String.fromEnvironment(
    'UMBRELLA_GATEWAY',
    defaultValue:
        'https://armin-soft.ir/Tools/Telegram-BOT/Umbrella-VPN/index.php?AppApi=',
  );

  /// نشانی پایه درگاه؛ کاربر می تواند در تنظیمات آن را عوض کند و مقدار
  /// ذخیره شده بر این پیش فرض اولویت دارد.
  static const String gatewayStoreKey = 'gateway.base';

  /// پنل وب سرویس برای دریافت مستقیم مصرف و پروفایل (مسیر پشتیبان).
  static const String panelBase = String.fromEnvironment(
    'UMBRELLA_PANEL',
    defaultValue: 'https://user.umbrella-server.ir/5mkVYdBkp8OS/',
  );
  static const String panelApiKey = String.fromEnvironment(
    'UMBRELLA_PANEL_KEY',
    defaultValue: 'ae467ee4-2249-4b67-bfa8-e59ca3125286',
  );

  static const String subscriptionRoot =
      'https://user.umbrella-server.ir/D6qnVQXRwa/9b9d9f5d-9841-45bf-a6b9-0479de273c11';

  /// تنها میزبان هایی که برنامه اجازه دانلود اشتراک از آن ها را دارد.
  static const List<String> allowedSubscriptionHosts = <String>[
    'user.umbrella-server.ir',
  ];

  /// شناسه اشتراک شخصی کاربر که نشانی اش از سرور می آید.
  static const String personalSourceId = 'user';

  /// منابع عمومی برنامه؛ فقط پشتیبان هستند تا پیش از ورود هم سروری نمایش داده
  /// شود. اشتراک اصلی هر کاربر همان است که سرور می دهد.
  static const List<SubscriptionSource> subscriptionSources =
      <SubscriptionSource>[
    SubscriptionSource(
      id: 'xray',
      title: 'ایکس ری',
      url: '$subscriptionRoot/all.txt',
      format: SubscriptionFormat.xray,
      icon: 'bolt',
    ),
    SubscriptionSource(
      id: 'clash',
      title: 'کلش متا',
      url: '$subscriptionRoot/clash/meta/all.yml',
      format: SubscriptionFormat.clash,
      icon: 'grid',
    ),
    SubscriptionSource(
      id: 'wireguard',
      title: 'وایرگارد',
      url: '$subscriptionRoot/wireguard/?asn=unknown',
      format: SubscriptionFormat.wireguard,
      icon: 'shield',
    ),
    SubscriptionSource(
      id: 'amnezia',
      title: 'آمنزیا',
      url: '$subscriptionRoot/amnezia/?asn=unknown',
      format: SubscriptionFormat.amnezia,
      icon: 'lock',
    ),
    SubscriptionSource(
      id: 'mieru',
      title: 'میرو',
      url: '$subscriptionRoot/mieru/?asn=unknown',
      format: SubscriptionFormat.mieru,
      icon: 'route',
    ),
  ];

  /// فایل های استاندارد حساب کاربر روی پنل (نتایج واقعی آزمایش، ۹ آبان):
  /// sub/ خودکار، all.txt فهرست ساده، sub64/ فهرست base64،
  /// clash/meta/all.yml کلش متا، full-singbox.json سینگ باکس،
  /// wireguard، amnezia و mieru فایل های مستقیم.
  /// تنها مسیر درست کلش متا در این پنل `clash/meta/all.yml` است؛ مسیر قدیمی
  /// `mihomo/all.yml` با کد ۴۰۴ پاسخ می دهد و دیگر امتحان نمی شود.
  static const List<String> mihomoPaths = <String>[
    'clash/meta/all.yml',
  ];

  static const String ipCheckPrimary = 'https://api.ipify.org?format=json';
  static const String ipCheckFallback = 'https://ifconfig.co/json';
  static const String ipCheckCloudflare = 'https://www.cloudflare.com/cdn-cgi/trace';

  /// فایل به روز رسانی نسخه ویندوز؛ JSON با کلیدهای version, url, sha256, notes
  ///
  /// اگر این متغیر نده شود، نسخه از **صفحه انتشار گیت هاب** خوانده می شود.
  /// نشانی پیشین `user.umbrella-server.ir` بود که از داخل ایران اغلب باز
  /// نمی شود؛ به همین دلیل دکمه «بررسی به روز رسانی» در گزارش کاربر هیچ
  /// کاری نمی کرد. گیت هاب برای همین بررسی همیشه در دسترس است.
  static const String updateManifestUrl = String.fromEnvironment(
    'UMBRELLA_UPDATE_MANIFEST',
    defaultValue: '',
  );

  /// آخرین انتشار ویندوز در گیت هاب (همان مخزنی که نصب کننده از آن می آید).
  static const String releaseApiUrl =
      'https://api.github.com/repos/armin-soft/Umbrella-VPN/releases/latest';

  /// صفحه انتشار، برای وقتی که خودکار نمی شود.
  static const String releasesPageUrl =
      'https://github.com/armin-soft/Umbrella-VPN/releases/latest';

  /// پیشوند نام آداپتور تونل که برای خواندن آمار مصرف استفاده می شود.
  ///
  /// این رشته فقط برای پیدا کردن آداپتور در فهرست شبکه است و هیچ جا نمایش داده
  /// نمی شود؛ باید با نامی که خود هسته روی کارت شبکه می گذارد یکی باشد، وگرنه
  /// آداپتور پیدا نمی شود و آمار حالت تونل صفر می ماند. مسیر نمایشی نام کارت
  /// جداگانه است (`packages/umbrella_native` نام آمبرلا را می گذارد).
  static const String tunAdapterHint = 'hiddify';

  /// نشانی کارت شبکه تونل؛ همان چیزی که خود هسته می گذارد
  /// (`v2/config/builder.go`: `172.19.0.1/28`).
  static const String tunAddress = '172.19.0.1/28';
  static const String tunAddress6 = 'fdfe:dcba:9876::1/126';
  static const int defaultMtu = 9000;

  /// زمان سنجش سرعت روی سرور متصل. یک مگابایت کافی است تا عدد واقعی سرعت
  /// به دست بیاید ولی مصرف کاربر بی دلیل بالا نرود.
  static const String speedTestUrl =
      'https://speed.cloudflare.com/__down?bytes=1000000';

  /// نشانی سنجش سلامت گره که به خود هسته داده می شود.
  ///
  /// این باید یک نشانی سبک و همه جا در دسترس باشد، **نه** نشانی سنجش سرعت.
  /// تا ۱٫۰٫۱۴ کلید `connection-test-url` روی `speed.cloudflare.com` بود و
  /// همان، گره های سالم را «خراب» نشان می داد: در گزارش کاربر ترافیک واقعی
  /// از تونل رد شد (گوگل، تلگرام، DNS) ولی هسته می نوشت
  /// `MONITORING vless § 0: no answer after 1s`. علتش این بود که آن دامنه
  /// از داخل ایران ۳۰۱/۴۰۳ برمی گرداند و پاسخی که هسته انتظار دارد نمی دهد.
  ///
  /// این سه نشانی، همان هایی هستند که اندروید و ویندوز خودشان برای تشخیص
  /// «اینترنت وصل است؟» استفاده می کنند؛ سبک اند (۲۰۴ بدون بدنه) و در
  /// بیشتر شبکه ها باز.
  static const List<String> connectionTestUrls = <String>[
    'https://www.gstatic.com/generate_204',
    'http://connectivitycheck.gstatic.com/generate_204',
    'http://cp.cloudflare.com/generate_204',
    'https://www.google.com/generate_204',
  ];
  /// پورت محلی هسته (پروکسی مختلط HTTP/SOCKS). همان پورتی که
  /// مستندات هسته پیش فرض می دهد.
  static const int httpPortUmbrella = 12334;

  /// پورت gRPC هسته وقتی در پنجره CLI جداگانه اجرا می شود.
  ///
  /// این عدد در خود هسته ثابت است (نسخه ۵٫۹٫۱، `buildStandaloneConfig`) و
  /// هیچ پرچمی برای عوض کردنش در دستور `run` نیست. همین پورت (نه پورت
  /// پروکسی) چیزی است که در ۱٫۰٫۴ با «port 17078 is already in use» می بست؛
  /// پس برنامه پیش از هر اتصال آن را آزاد می کند.
  static const int coreGrpcPort = 17078;

  /// پورت رابط کلش هسته؛ در خود هسته هم ثابت است.
  static const int coreClashPort = 16756;

  /// رمز رابط کلش هسته.
  ///
  /// **چرا نمی توانیم خالی بگذاریم:** در `setExperimental` خود هسته
  /// (`v2/config/builder.go`) این خط هست:
  ///   if hopt.ClashApiSecret == "" { hopt.ClashApiSecret = defaultClashApiSecret() }
  /// یعنی وقتی `web-secret` خالی باشد، هسته خودش یک رمز **ناشناس** می سازد.
  /// ما بی خبر از آن رمز به `127.0.0.1:16756/connections` می زدیم، جواب ۴۰۱
  /// می گرفتیم، `_clashTunnelVerdict()` مقدار `null` برمی گرداند و درست همان
  /// چیزی می شد که در گزارش ۱٫۰۱۴ دیدیم: پرسش از هسته هرگز جواب نداد و
  /// تصمیم آخر را یک سنجش درونی شکست خورده گرفت.
  ///
  /// رمز فقط روی `127.0.0.1` شنیده می شود، پس مقدار ثابت و ساده کافی است.
  static const String coreClashSecret = 'umbrella-local-16756';

  /// فایل تنظیمات هسته (همان فایل تنظیمات موتور، با نام آمبرلا).
  static const String coreSettingsFile = 'umbrella-settings.json';


  static const String appMutexName = 'UmbrellaVPN.Desktop.SingleInstance';
  static const String autostartName = 'UmbrellaVPN';

  static List<String> get routes => const <String>[
        'auth/start',
        'auth/verify',
        'auth/status',
        'auth/session',
        'auth/resend',
        'auth/signout',
        'auth/device',
        'account/refresh',
        'app/notifications',
        'app/ping',
        'filter/get',
        'filter/save',
      ];
}
