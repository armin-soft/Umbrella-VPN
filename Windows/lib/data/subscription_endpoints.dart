import '../core/app_config.dart';
import '../models/models.dart';

/// ساخت تنها نشانی اشتراک مجاز هر کاربر (`<base><uuid>/sub/`).
///
/// برنامه هیچ فایل یا قالب اضافه ای غیر از مسیر `/sub/` دانلود نمی کند؛ اگر سرور
/// نشانی قدیمی تری برگرداند یا مسیر راز پنل در نشانی جا افتاده باشد، همین کلاس
/// آن را به نشانی استاندارد `<base><uuid>/sub/` تبدیل می کند و در صورت نبود
/// اشتراک شخصی، منبع پیش فرض [AppConfig.defaultSubscriptionUrl] به کار می رود.
class SubscriptionEndpoints {
  const SubscriptionEndpoints._();

  /// تنها مسیر اشتراک مجاز روی پنل.
  static const String subPath = 'sub/';

  static const List<String> paths = <String>[subPath];

  static const List<SubscriptionFormat> formats = <SubscriptionFormat>[
    SubscriptionFormat.xray,
  ];

  static const List<String> titles = <String>['اشتراک خودکار'];

  static const List<String> icons = <String>['auto'];

  static final RegExp _uuidPattern = RegExp(
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
  );

  /// نشانی پایه اشتراک: هر چه پیش از شناسه کاربر در نشانی باشد.
  ///
  /// اگر سرور نشانی ای بدهد که مسیر راز پنل را ندارد (مثل
  /// `https://host/<uuid>/sub/`)، پایه ای که مسیر راز دارد از `accountBase`
  /// یا [AppConfig.defaultSubscriptionUrl] جایگزین می شود تا خطای ۴۰۴ رخ ندهد.
  static String baseFrom({
    required String subscriptionUrl,
    required String accountBase,
    required String uuid,
  }) {
    final List<String> candidates = <String>[
      subscriptionUrl.trim(),
      accountBase.trim(),
      AppConfig.defaultSubscriptionUrl.trim(),
    ];
    String fallback = '';
    for (final String candidate in candidates) {
      final String base = _prefixOf(candidate, uuid);
      if (base.isEmpty) {
        continue;
      }
      final String path = Uri.tryParse(base)?.path ?? '';
      if (path.isEmpty || path == '/') {
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
      SubscriptionSource(
        id: 'user-sub',
        title: titles.first,
        url: '$base$resolvedUuid/$subPath',
        format: SubscriptionFormat.xray,
        icon: icons.first,
        personal: true,
      ),
    ];
  }

  /// آیا منبع اشتراک `/sub/` کاربر آماده است.
  static bool isComplete(List<SubscriptionSource> sources) =>
      sources.length == 1 && sources.first.url.endsWith('/$subPath');
}
