import '../core/app_config.dart';
import '../models/models.dart';

/// ساخت تنها نشانی اشتراک اختصاصی هر کاربر (`<base><uuid>/sub/`).
///
/// هیچ منبع عمومی یا رایگان در برنامه وجود ندارد؛ فقط اشتراک اختصاصی حساب
/// کاربر واردشده ساخته می شود و اگر مسیر راز پنل در نشانی سرور جا افتاده باشد
/// یا شناسه تکرار شده باشد، به شکل استاندارد `<base><uuid>/sub/` اصلاح می شود.
class SubscriptionEndpoints {
  const SubscriptionEndpoints._();

  /// تنها مسیر اشتراک مجاز روی پنل.
  static const String subPath = 'sub/';

  static const List<String> paths = <String>[subPath, 'wireguard/', 'amnezia/', 'mieru/'];

  static const List<SubscriptionFormat> formats = <SubscriptionFormat>[
    SubscriptionFormat.xray, SubscriptionFormat.wireguard,
    SubscriptionFormat.amnezia, SubscriptionFormat.mieru,
  ];

  static const List<String> titles = <String>['اشتراک خودکار', 'وایرگارد', 'آمنزیا', 'میرو'];

  static const List<String> icons = <String>['auto', 'wireguard', 'amnezia', 'mieru'];

  static final RegExp _uuidPattern = RegExp(
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
  );

  /// نشانی پایه اشتراک: هر چه پیش از شناسه کاربر در نشانی باشد.
  ///
  /// اگر سرور نشانی ای بدهد که مسیر راز پنل را ندارد (مثل
  /// `https://host/<uuid>/sub/` یا `https://host/<uuid>/<uuid>/sub/`)، پایه
  /// مسیر راز از `accountBase` یا [AppConfig.subscriptionBaseUrl] جایگزین
  /// می شود تا خطای ۴۰۴ رخ ندهد.
  static String baseFrom({
    required String subscriptionUrl,
    required String accountBase,
    required String uuid,
  }) {
    final List<String> candidates = <String>[
      subscriptionUrl.trim(),
      accountBase.trim(),
      AppConfig.subscriptionBaseUrl.trim(),
    ];
    String fallback = '';
    for (final String candidate in candidates) {
      final String base = _prefixOf(candidate, uuid);
      if (base.isEmpty) {
        continue;
      }
      final Uri? parsed = Uri.tryParse(base);
      final String path = parsed?.path ?? '';
      final List<String> segments = (parsed?.pathSegments ?? const <String>[])
          .where((String s) => s.isNotEmpty)
          .toList();
      final bool onlyUuidPath = segments.isNotEmpty &&
          segments.every((String s) => _uuidPattern.hasMatch(s));
      if (path.isEmpty || path == '/' || onlyUuidPath) {
        if (fallback.isEmpty && !onlyUuidPath) {
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
      final int index = candidate.toLowerCase().indexOf(uuid.toLowerCase());
      if (index > 0) {
        return _ensureTrailingSlash(candidate.substring(0, index));
      }
    }
    final RegExpMatch? anyUuid = _uuidPattern.firstMatch(candidate);
    if (anyUuid != null && anyUuid.start > 0) {
      return _ensureTrailingSlash(candidate.substring(0, anyUuid.start));
    }
    final int sub = candidate.lastIndexOf('/sub');
    if (sub > 0) {
      final int cut = candidate.lastIndexOf('/', sub - 1);
      if (cut > 0) {
        return _ensureTrailingSlash(candidate.substring(0, cut + 1));
      }
    }
    final Uri? uri = Uri.tryParse(candidate);
    if (uri != null &&
        uri.hasScheme &&
        uri.host.isNotEmpty &&
        uri.path.isNotEmpty &&
        uri.path != '/') {
      return _ensureTrailingSlash(candidate);
    }
    return '';
  }

  static String _ensureTrailingSlash(String value) =>
      value.endsWith('/') ? value : '$value/';

  static String _normalizeRawSubUrl(String raw) {
    final Uri? uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return raw;
    }
    final List<String> segments = uri.pathSegments
        .where((String segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) {
      return uri.replace(path: '/$subPath', query: '', fragment: '').toString();
    }
    final int subIndex = segments.lastIndexOf('sub');
    if (subIndex >= 0) {
      final String cleanPath = '/${segments.take(subIndex + 1).join('/')}/';
      return uri.replace(path: cleanPath, query: '', fragment: '').toString();
    }
    return raw;
  }

  /// تنها منبع اشتراک `/sub/` همین کاربر را می سازد.
  static List<SubscriptionSource> build({
    required String subscriptionUrl,
    required String accountBase,
    required String uuid,
  }) {
    final String raw = subscriptionUrl.trim();
    final String resolvedUuid = uuid.trim().isNotEmpty
        ? uuid.trim()
        : (_uuidPattern.firstMatch(raw)?.group(0) ?? '');
    final String base = baseFrom(
      subscriptionUrl: raw,
      accountBase: accountBase,
      uuid: resolvedUuid,
    );
    if (resolvedUuid.isEmpty || base.isEmpty) {
      if (raw.isEmpty) {
        return const <SubscriptionSource>[];
      }
      return <SubscriptionSource>[
        SubscriptionSource(
          id: 'user-sub',
          title: titles.first,
          url: _normalizeRawSubUrl(raw),
          format: SubscriptionFormat.xray,
          icon: icons.first,
          personal: true,
        ),
      ];
    }
    return <SubscriptionSource>[
      for (int i = 0; i < paths.length; i++)
        SubscriptionSource(
          id: i == 0 ? 'user-sub' : 'user-${icons[i]}',
          title: titles[i],
          url: '$base$resolvedUuid/${paths[i]}',
          format: formats[i],
          icon: icons[i],
          personal: true,
        ),
    ];
  }

  /// آیا منبع اشتراک `/sub/` کاربر آماده است.
  static bool isComplete(List<SubscriptionSource> sources) =>
      sources.length == paths.length &&
      sources.asMap().entries.every((entry) => entry.value.url.endsWith('/${paths[entry.key]}'));
}
