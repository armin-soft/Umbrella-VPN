import '../models/models.dart';
import 'persian.dart';

/// تنظیمات ثابت برنامه اندروید آمبرلا: نسخه، آدرس سرویس ها و منابع مجاز.
class AppConfig {
  const AppConfig._();

  static const String appName = 'فیلترشکن آمبرلا';
  static const String shortName = 'آمبرلا';
  static const String version = '1.0.0';
  static const int buildNumber = 1;

  static String get versionLabel => version;
  static String get versionPhrase => Fa.num('نسخه ${version.split('.').join('٫')}');

  static const String company = 'آرمین سافت';
  static const String developer = 'آرمین سافت';
  static const String developerSite = 'https://armin-soft.ir';
  static const String supportUrl = 'https://t.me/UmbrellaSupport';
  static const String channelUsername = String.fromEnvironment(
    'UMBRELLA_CHANNEL',
    defaultValue: 'UmbrellaVPN_Channel',
  );
  static const String channelHandle = '@$channelUsername';
  static const String channelUrl = 'https://t.me/$channelUsername';
  static const String channelAppUrl = 'tg://resolve?domain=$channelUsername';
  static const String botUsername = String.fromEnvironment(
    'UMBRELLA_BOT',
    defaultValue: 'UmbrellaVPN_BOT',
  );

  /// درگاه برنامه (همان AppGateway ربات تلگرام).
  static const String gatewayBase = String.fromEnvironment(
    'UMBRELLA_GATEWAY',
    defaultValue:
        'https://armin-soft.ir/Tools/Telegram-BOT/Umbrella-VPN/index.php?AppApi=',
  );

  static const String gatewayStoreKey = 'gateway.base';

  static const String subscriptionBaseUrl = String.fromEnvironment(
    'UMBRELLA_SUB_BASE',
    defaultValue: 'https://user.umbrella-server.ir/D6qnVQXRwa/',
  );

  static const List<String> allowedSubscriptionHosts = <String>[
    'user.umbrella-server.ir',
  ];

  static const String personalSourceId = 'user';

  static const List<SubscriptionSource> subscriptionSources =
      <SubscriptionSource>[];

  static const String ipCheckPrimary = 'https://api.ipify.org?format=json';
  static const String ipCheckFallback = 'https://ifconfig.co/json';
  static const String ipCheckCloudflare = 'https://www.cloudflare.com/cdn-cgi/trace';

  static const String updateManifestUrl = String.fromEnvironment(
    'UMBRELLA_UPDATE_MANIFEST',
    defaultValue: '',
  );

  static const String releaseApiUrl =
      'https://api.github.com/repos/armin-soft/Umbrella-VPN-Releases/releases/latest';

  static const String releasesListApiUrl =
      'https://api.github.com/repos/armin-soft/Umbrella-VPN-Releases/releases?per_page=20';

  static const String releasesPageUrl =
      'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/latest';

  static const String allReleasesPageUrl =
      'https://github.com/armin-soft/Umbrella-VPN-Releases/releases';

  static const String tunAdapterHint = 'tun0';
  static const String tunAddress = '172.19.0.1/28';
  static const String tunAddress6 = 'fdfe:dcba:9876::1/126';
  static const int defaultMtu = 9000;

  static const String speedTestUrl =
      'https://speed.cloudflare.com/__down?bytes=1000000';

  static const List<String> connectionTestUrls = <String>[
    'http://connectivitycheck.gstatic.com/generate_204',
    'http://captive.apple.com/hotspot-detect.html',
    'http://captive.apple.com/generate_204',
    'http://cp.cloudflare.com/',
  ];

  static const int httpPortUmbrella = 12334;
  static const int coreGrpcPort = 17078;
  static const int coreUtilityGrpcPort = 17079;
  static const int coreClashPort = 16756;
  static const String coreClashSecret = 'umbrella-local-16756';
  static const String coreSettingsFile = 'umbrella-settings.json';
  static const String androidPackageId = 'ir.umbrella.vpn';

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
        'subscription/offers',
        'subscription/claim',
      ];
}
