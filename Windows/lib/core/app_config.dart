import '../models/models.dart';

/// تنظیمات ثابت برنامه: نسخه، آدرس سرویس ها و تنها منابع اشتراک مجاز.
///
/// آدرس ها با `--dart-define` هم قابل تغییر هستند تا نصب های مختلف بدون
/// تغییر کد بتوانند به سرور خودشان وصل شوند.
class AppConfig {
  const AppConfig._();

  static const String appName = 'فیلترشکن آمبرلا';
  static const String shortName = 'آمبرلا';
  static const String version = '1.0.0';
  static const int buildNumber = 1;
  static const String versionLabel = 'نسخه ۱٫۰٫۰';
  static const String company = 'آرمین سافت';
  static const String developer = 'آرمین سافت';
  static const String developerSite = 'https://armin-soft.ir';
  static const String supportUrl = 'https://t.me/UmbrellaSupport';
  static const String channelUrl = 'https://t.me/UmbrellaChannel';
  static const String botUsername = String.fromEnvironment(
    'UMBRELLA_BOT',
    defaultValue: 'UmbrellaServerBot',
  );

  /// درگاه برنامه (همان AppGateway ربات). مسیرها به آن اضافه می شوند:
  /// auth/start ، auth/verify ، auth/status ، auth/session ،
  /// account/refresh ، app/notifications ، filter/get ، filter/save
  static const String gatewayBase = String.fromEnvironment(
    'UMBRELLA_GATEWAY',
    defaultValue: 'https://user.umbrella-server.ir/bot/app',
  );

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

  static const String ipCheckPrimary = 'https://api.ipify.org?format=json';
  static const String ipCheckFallback = 'https://ifconfig.co/json';
  static const String ipCheckCloudflare = 'https://www.cloudflare.com/cdn-cgi/trace';

  /// فایل به روز رسانی نسخه ویندوز؛ JSON با کلیدهای version, url, sha256, notes
  static const String updateManifestUrl = String.fromEnvironment(
    'UMBRELLA_UPDATE_MANIFEST',
    defaultValue:
        'https://user.umbrella-server.ir/5mkVYdBkp8OS/api/windows/update.json',
  );

  /// پیشوند نام آداپتور تونل که برای خواندن آمار مصرف استفاده می شود.
  static const String tunAdapterHint = 'sing-box';

  static const String tunAddress = '172.19.0.1/30';
  static const String tunAddress6 = 'fdfe:dcba:9876::1/126';
  static const int defaultMtu = 9000;
  static const int socksPortXray = 2081;
  static const int socksPortMieru = 2082;
  static const int socksPortChained = 2080;
  static const int apiPortSingBox = 9090;

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
