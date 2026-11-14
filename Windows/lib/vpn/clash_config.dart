import 'package:yaml/yaml.dart';

import '../core/utils.dart';

/// خواندن پیکربندی خود پنل (کلش متا).
///
/// پنل این سرویس یک فایل YAML کامل می دهد (`clash/meta/all.yml`) که در آن هر
/// گره با جزئیاتش هست. هسته همین فایل را مستقیم می خواند و هیچ
/// بازنویسی ای لازم نیست؛ اینجا فقط نام گره ها خوانده می شود تا سرورهای فهرست
/// با نام های پنل تطبیق داده شوند و کاربر بداند کدام سرور همان گره پنل است.
class ClashConfig {
  const ClashConfig._();

  static List<String> nodeNames(String raw) {
    final Object? document = loadYaml(raw);
    if (document is! Map) {
      return <String>[];
    }
    final Object? proxies = document['proxies'];
    if (proxies is! List) {
      return <String>[];
    }
    return <String>[
      for (final Object? item in proxies)
        if (item is Map) JsonX.text(item['name']),
    ].where((String name) => name.isNotEmpty).toList();
  }

}
