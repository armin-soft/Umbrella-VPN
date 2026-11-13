import '../core/app_config.dart';
import '../models/models.dart';

/// ساخت نشانی پنج اشتراک کاربر از داده ای که سرور می دهد.
///
/// سرور پایه اشتراک هر کاربر را می فرستد (مثلا
/// `https://user.umbrella-server.ir/<token>/<uuid>/sub/`) و برنامه همان پایه را
/// با مسیرهای استاندارد پنل ترکیب می کند:
///
/// * `all.txt` (ایکس ری)
/// * `clash/meta/all.yml` (کلش متا)
/// * `wireguard/?asn=unknown`
/// * `amnezia/?asn=unknown`
/// * `mieru/?asn=unknown`
///
/// هیچ نشانی از کاربر پرسیده نمی شود؛ اگر سرور داده کافی ندهد فقط همان نشانی
/// خام به عنوان یک منبع برگردانده می شود.
class SubscriptionEndpoints {
  const SubscriptionEndpoints._();

  static const List<String> paths = <String>[
    // «خودکار»: پنل خودش قالب مناسب را می دهد.
    'sub/',
    'all.txt',
    'sub64/',
    'clash/meta/all.yml',
    'full-singbox.json',
    'wireguard',
    'amnezia',
    'mieru',
  ];

  /// مسیرهای جایگزین هر قالب؛ پنل های مختلف یکی از این ها را دارند.
  static const Map<String, List<String>> alternates = <String, List<String>>{
    'clash': <String>['clash/meta/all.yml', 'mihomo/all.yml'],
    'wireguard': <String>['wireguard', 'wireguard/', 'wireguard/?asn=unknown'],
    'amnezia': <String>['amnezia', 'amnezia/', 'amnezia/?asn=unknown'],
    'mieru': <String>['mieru', 'mieru/', 'mieru/?asn=unknown'],
  };

  /// قالب هر مسیر، دقیقا هم ترتیب با [paths].
  static const List<SubscriptionFormat> formats = <SubscriptionFormat>[
    SubscriptionFormat.xray, // sub/  (خودکار)
    SubscriptionFormat.xray, // all.txt
    SubscriptionFormat.xray, // sub64/
    SubscriptionFormat.clash,
    SubscriptionFormat.clash, // full-singbox.json
    SubscriptionFormat.wireguard,
    SubscriptionFormat.amnezia,
    SubscriptionFormat.mieru,
  ];

  static const List<String> titles = <String>[
    'خودکار',
    'فهرست ساده',
    'فهرست Base 64',
    'کلش متا',
    'سینگ باکس',
    'وایرگارد',
    'آمنزیا',
    'میرو',
  ];

  static const List<String> icons = <String>[
    'auto',
    'bolt',
    'code',
    'grid',
    'box',
    'shield',
    'lock',
    'route',
  ];

  /// نشانی پایه اشتراک: هر چه پیش از بخش شناسه کاربر در نشانی باشد.
  ///
  /// اگر سرور نشانی ای بدهد که مسیر راز پنل را ندارد (مثل
  /// `https://host/<uuid>/sub/`)، همان نشانی کد ۴۰۴ می دهد؛ پنل ها معمولا
  /// یک بخش راز پیش از شناسه دارند. بنابراین پایه ای که مسیر دارد بر پایه
  /// «فقط میزبان» ترجیح داده می شود و در آخرین مرحله نشانی پایه خود برنامه
  /// (که همان مسیر کامل پنل را دارد) امتحان می شود.
  static String baseFrom({
    required String subscriptionUrl,
    required String accountBase,
    required String uuid,
  }) {
    final List<String> candidates = <String>[
      subscriptionUrl.trim(),
      accountBase.trim(),
      AppConfig.subscriptionRoot.trim(),
    ];
    String fallback = '';
    for (final String candidate in candidates) {
      final String base = _prefixOf(candidate, uuid);
      if (base.isEmpty) {
        continue;
      }
      final String path = Uri.tryParse(base)?.path ?? '';
      if (path.isEmpty || path == '/') {
        // این پایه هیچ مسیری ندارد؛ فقط اگر چیز بهتری پیدا نشد استفاده می شود.
        if (fallback.isEmpty) {
          fallback = base;
        }
        continue;
      }
      return base;
    }
    return fallback;
  }

  static String _prefixOf(String candidate, String uuid) {
    if (candidate.isEmpty) {
      return '';
    }
    if (uuid.isNotEmpty) {
      final int index = candidate.indexOf(uuid);
      if (index > 0) {
        return candidate.substring(0, index);
      }
    }
    // نشانی بدون شناسه اما با مسیر اشتراک، پایه حساب است.
    final int sub = candidate.lastIndexOf('/sub');
    if (sub > 0) {
      final int cut = candidate.lastIndexOf('/', sub - 1);
      if (cut > 0) {
        return candidate.substring(0, cut + 1);
      }
    }
    return '';
  }

  /// فهرست منابع اشتراک همین کاربر. اگر شناسه کاربر مشخص نباشد، فقط نشانی خام
  /// سرور به عنوان یک منبع با تشخیص خودکار قالب برگردانده می شود.
  static List<SubscriptionSource> build({
    required String subscriptionUrl,
    required String accountBase,
    required String uuid,
  }) {
    final String raw = subscriptionUrl.trim();
    final String base = baseFrom(
      subscriptionUrl: raw,
      accountBase: accountBase,
      uuid: uuid,
    );
    if (uuid.isEmpty || base.isEmpty) {
      if (raw.isEmpty) {
        return const <SubscriptionSource>[];
      }
      return <SubscriptionSource>[
        SubscriptionSource(
          id: 'user',
          title: 'اشتراک من',
          url: raw,
          format: SubscriptionFormat.xray,
          icon: 'user',
          personal: true,
        ),
      ];
    }
    final List<SubscriptionSource> sources = <SubscriptionSource>[
      for (int index = 0; index < paths.length; index++)
        SubscriptionSource(
          id: 'user-${_slug(paths[index])}',
          title: titles[index],
          url: '$base$uuid/${paths[index]}',
          format: formats[index],
          icon: icons[index],
          personal: true,
        ),
    ];
    // مسیرهای جایگزین هر قالب (پنل های مختلف یکی را دارند) به عنوان منبع
    // پشتیبان اضافه می شوند؛ فقط اگر مسیر اصلی جواب ندهد استفاده می شوند.
    alternates.forEach((String format, List<String> candidates) {
      final SubscriptionFormat kind = format == 'clash'
          ? SubscriptionFormat.clash
          : (format == 'wireguard'
              ? SubscriptionFormat.wireguard
              : (format == 'amnezia'
                  ? SubscriptionFormat.amnezia
                  : SubscriptionFormat.mieru));
      for (final String path in candidates) {
        if (paths.contains(path)) {
          continue;
        }
        sources.add(
          SubscriptionSource(
            id: 'user-${_slug(path)}',
            title: '${titles[formats.indexOf(kind)]} (مسیر جایگزین)',
            url: '$base$uuid/$path',
            format: kind,
            icon: icons[formats.indexOf(kind)],
            personal: true,
          ),
        );
      }
    });
    return sources;
  }

  /// شناسه کوتاه و پایدار برای هر مسیر.
  static String _slug(String path) => path
      .replaceAll('/', '-')
      .replaceAll('?', '-')
      .replaceAll('=', '-')
      .replaceAll(RegExp(r'-+$'), '');

  /// آیا این نشانی از سرور آمده و کامل است (برای نمایش در گزارش ها).
  static bool isComplete(List<SubscriptionSource> sources) =>
      sources.length >= paths.length;
}
