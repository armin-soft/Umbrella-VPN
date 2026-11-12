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
    'all.txt',
    'clash/meta/all.yml',
    'wireguard/?asn=unknown',
    'amnezia/?asn=unknown',
    'mieru/?asn=unknown',
  ];

  static const List<SubscriptionFormat> formats = <SubscriptionFormat>[
    SubscriptionFormat.xray,
    SubscriptionFormat.clash,
    SubscriptionFormat.wireguard,
    SubscriptionFormat.amnezia,
    SubscriptionFormat.mieru,
  ];

  static const List<String> titles = <String>[
    'ایکس ری',
    'کلش متا',
    'وایرگارد',
    'آمنزیا',
    'میرو',
  ];

  static const List<String> icons = <String>[
    'bolt',
    'grid',
    'shield',
    'lock',
    'route',
  ];

  /// نشانی پایه اشتراک: هر چه پیش از بخش شناسه کاربر در نشانی باشد.
  static String baseFrom({
    required String subscriptionUrl,
    required String accountBase,
    required String uuid,
  }) {
    final List<String> candidates = <String>[
      subscriptionUrl.trim(),
      accountBase.trim(),
    ];
    for (final String candidate in candidates) {
      if (candidate.isEmpty) {
        continue;
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
    }
    final String fallback = accountBase.trim().isNotEmpty
        ? accountBase.trim()
        : subscriptionUrl.trim();
    if (fallback.isEmpty) {
      return '';
    }
    return fallback.endsWith('/') ? fallback : '$fallback/';
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
    return <SubscriptionSource>[
      for (int index = 0; index < paths.length; index++)
        SubscriptionSource(
          id: 'user-${formats[index].name}',
          title: titles[index],
          url: '$base$uuid/${paths[index]}',
          format: formats[index],
          icon: icons[index],
          personal: true,
        ),
    ];
  }

  /// آیا این نشانی از سرور آمده و کامل است (برای نمایش در گزارش ها).
  static bool isComplete(List<SubscriptionSource> sources) =>
      sources.length == paths.length;
}
