import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../core/utils.dart';

/// آماده کردن پیکربندی کلش متا (mihomo) برای این دستگاه.
///
/// چرا این راه؟ خود پنل همین سرور یک فایل YAML کامل می دهد
/// (`clash/meta/all.yml`) که در آن هر گره با همه جزئیاتش هست: پدینگ، هدرهای
/// مرورگر، ALPN، fragment و finger-print. همان فایل در کلاینت های دیگر
/// (v2rayNG، هیدیفای و نیکوباکس) کار می کند. ساختن دستی همین گره ها از روی
/// لینک اشتراک به ۴۰۰ و ۴۰۳ می خورد، چون آن جزئیات در لینک نیست.
///
/// پس فایل پنل را دست نمی زنیم و فقط سه چیز را عوض می کنیم:
/// ۱. پورت محلی که پنل گفته (۷۸۹۰) با پورت خود برنامه عوض می شود تا با اجرای
///    همزمان یک برنامه دیگر تعارض نکند.
/// ۲. پنل مدیریت محلی روی پورت آزاد خودمان می رود.
/// ۳. کارت شبکه مجازی و دی ان اس با حالت انتخابی کاربر هماهنگ می شوند.
class ClashConfig {
  const ClashConfig._();

  /// مسیر کارت شبکه مجازی؛ در همه جای برنامه همین نام است.
  static const String tunDevice = 'Umbrella-Tunnel';

  /// فایل YAML پنل را برای این دستگاه تنظیم می کند.
  static String adapt(
    String raw, {
    required bool tun,
    required int mixedPort,
    int apiPort = 0,
    String preferred = '',
  }) {
    final Object? document = loadYaml(raw);
    if (document is! Map) {
      throw const FormatException('ساختار فایل کلش نامعتبر است.');
    }
    // تبدیل کامل به نقشه و فهرست ساده دارت؛ بدون این کار تغییر گروه ها روی
    // نسخه خود yaml اعمال نمی شد و بی صدا از بین می رفت.
    final Map<String, dynamic> config = _deepMap(document);

    // پورت و پنل مدیریت همان چیزی می شود که خود برنامه تعیین می کند.
    config['mixed-port'] = mixedPort;
    config['allow-lan'] = false;
    config['mode'] = JsonX.text(config['mode'], 'rule');
    config['log-level'] = 'info';
    config.remove('port');
    config.remove('socks-port');
    if (apiPort > 0) {
      config['external-controller'] = '127.0.0.1:$apiPort';
      // راز پنل پاک می شود تا برنامه بتواند وضعیت اتصال را بخواند.
      config['secret'] = '';
    }

    if (tun) {
      config['tun'] = <String, dynamic>{
        ...JsonX.asMap(config['tun']),
        'enable': true,
        // «mixed» هم TCP و هم UDP را پوشش می دهد و روی ویندوز پایدارتر از
        // gvisor است.
        'stack': 'mixed',
        'auto-route': true,
        'auto-detect-interface': true,
        'dns-hijack': <String>['any:53'],
        'device': tunDevice,
      };
      final Map<String, dynamic> dns = JsonX.asMap(config['dns']);
      dns['enable'] = true;
      // در حالت تونل، دی ان اس روی ۵۳ شنیده می شود تا dns-hijack کار کند؛
      // پورت خود پنل (۶۸۶۸) ممکن است در این رایانه گرفته باشد.
      dns['listen'] = '127.0.0.1:53';
      config['dns'] = dns;
    } else {
      config['tun'] = <String, dynamic>{'enable': false};
      final Map<String, dynamic> dns = JsonX.asMap(config['dns']);
      dns['enable'] = true;
      dns.remove('listen');
      config['dns'] = dns;
    }

    if (preferred.isNotEmpty) {
      _preferProxy(config, preferred);
    }

    // `profile` فقط برای ذخیره انتخاب کاربر در کلاینت گرافیکی است و در اجرای
    // فرمانی معنی ندارد؛ نگه داشتنش ضرری ندارد و پاک نمی شود.
    return _verified(config);
  }

  /// خروجی YAML دوباره خوانده می شود تا اگر نویسنده جایی اشتباه کرد، هسته با
  /// فایل خراب اجرا نشود و همان لحظه پیام روشن به کاربر برسد.
  static String _verified(Map<String, dynamic> config) {
    final String text = _dump(config);
    final Object? check = loadYaml(text);
    if (check is! Map) {
      throw const FormatException('خروجی YAML کلش خوانده نشد.');
    }
    final List<String> before = nodeNames(_dump(<String, dynamic>{
      'proxies': config['proxies'],
    }));
    final List<String> after = nodeNames(text);
    if (before.length != after.length) {
      throw const FormatException('فهرست سرورهای کلش در تبدیل ناقص شد.');
    }
    return text;
  }

  static Map<String, dynamic> _deepMap(Object? value) {
    final Map<String, dynamic> out = <String, dynamic>{};
    if (value is Map) {
      value.forEach((Object? key, Object? item) {
        out[key.toString()] = _deep(item);
      });
    }
    return out;
  }

  static Object? _deep(Object? value) {
    if (value is Map) {
      return _deepMap(value);
    }
    if (value is List) {
      return <dynamic>[for (final Object? item in value) _deep(item)];
    }
    return value;
  }

  /// سروری که کاربر انتخاب کرده باید همان سروری باشد که ترافیک از آن رد می
  /// شود. گروه اول پنل از نوع «select» است و mihomo اولین گزینه را برمی دارد،
  /// پس نام سرور انتخاب شده به ابتدای همان فهرست منتقل می شود.
  static void _preferProxy(Map<String, dynamic> config, String preferred) {
    final Object? groups = config['proxy-groups'];
    if (groups is! List || groups.isEmpty) {
      return;
    }
    for (final Object? group in groups) {
      final Map<String, dynamic> map = JsonX.asMap(group);
      final String type = JsonX.text(map['type']).toLowerCase();
      if (type != 'select' && type != 'relay') {
        continue;
      }
      final Object? proxies = map['proxies'];
      if (proxies is! List) {
        continue;
      }
      // اگر این نام در گروه نبود، فهرست دست نمی خورد تا انتخاب پنل خراب نشود.
      if (!proxies.any((Object? item) => JsonX.text(item) == preferred)) {
        continue;
      }
      map['proxies'] = <dynamic>[
        preferred,
        ...proxies.where((Object? item) => JsonX.text(item) != preferred),
      ];
      return;
    }
  }

  /// هدرهای یک گره کلش.
  ///
  /// خواننده کلش هر نقشه تودرتو را به رشته JSON تبدیل می کند، پس هدرها هم
  /// گاهی نقشه و گاهی رشته اند. اینجا هر دو یکسان خوانده می شوند.
  static Map<String, String> flatHeaders(Map<String, dynamic> proxy) {
    final Object? raw = proxy['headers'];
    Map<String, dynamic> source = <String, dynamic>{};
    if (raw is Map) {
      source = _deepMap(raw);
    } else if (raw is String && raw.trim().startsWith('{')) {
      try {
        source = _deepMap(jsonDecode(raw));
      } on FormatException {
        source = <String, dynamic>{};
      }
    }
    final Map<String, String> out = <String, String>{};
    source.forEach((String key, Object? value) {
      final String text = JsonX.text(value);
      if (text.isNotEmpty) {
        out[key] = text;
      }
    });
    return out;
  }

  /// نام گره هایی که در فایل پنل هستند (برای گزارش خطا به کاربر).
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

  /// نوشتن نقشه به YAML. پکیج yaml فقط می خواند و نویسنده ندارد، پس اینجا
  /// یک نویسنده ساده و قابل پیش بینی داریم: نقشه، فهرست، رشته، عدد و بولین.
  static String _dump(Map<String, dynamic> config) {
    final StringBuffer out = StringBuffer();
    _writeMap(out, config, 0);
    return out.toString();
  }

  static void _writeMap(StringBuffer out, Map<String, dynamic> map, int indent) {
    final String pad = '  ' * indent;
    map.forEach((String key, Object? value) {
      out.write('$pad${_key(key)}:');
      _writeValue(out, value, indent);
    });
  }

  static void _writeValue(StringBuffer out, Object? value, int indent) {
    final String pad = '  ' * indent;
    if (value is Map) {
      final Map<String, dynamic> map = JsonX.asMap(value);
      if (map.isEmpty) {
        out.writeln(' {}');
        return;
      }
      out.writeln();
      _writeMap(out, map, indent + 1);
      return;
    }
    if (value is List) {
      if (value.isEmpty) {
        out.writeln(' []');
        return;
      }
      out.writeln();
      for (final Object? item in value) {
        if (item is Map) {
          final Map<String, dynamic> map = JsonX.asMap(item);
          bool first = true;
          map.forEach((String key, Object? child) {
            if (first) {
              out.write('$pad  - ${_key(key)}:');
              first = false;
            } else {
              out.write('$pad    ${_key(key)}:');
            }
            _writeValue(out, child, indent + 2);
          });
          continue;
        }
        out.writeln('$pad  - ${_scalar(item)}');
      }
      return;
    }
    out.writeln(' ${_scalar(value)}');
  }

  static String _key(String key) {
    if (RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(key)) {
      return key;
    }
    return _scalar(key);
  }

  static String _scalar(Object? value) {
    if (value == null) {
      return 'null';
    }
    if (value is bool) {
      return value ? 'true' : 'false';
    }
    if (value is num) {
      return value.toString();
    }
    final String text = value.toString();
    if (text.isEmpty) {
      return "''";
    }
    // هر رشته ای داخل کوتیشن دوتایی می رود: رمز و نام گره می توانند عدد یا
    // کلمه ای مثل on باشند و بدون کوتیشن، YAML آن را بولین یا عدد می خواند و
    // پیکربندی بی سر و صدا خراب می شود.
    final String escaped = text
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n');
    return '"$escaped"';
  }
}

/// اجرای mihomo با فایل تنظیم شده پنل.
///
/// هسته کلش متا برای این سرور انتخاب اول است: پیکربندی خود پنل روی آن اجرا
/// می شود و هیچ تبدیلی لازم نیست. اگر mihomo در نسخه نصب نباشد، برنامه همان
/// مسیرهای قبلی (سینگ باکس و ایکس ری) را امتحان می کند.
class ClashPlanner {
  const ClashPlanner._();

  /// فایل تنظیمات آماده را در پوشه اجرا می نویسد و مسیرش را برمی گرداند.
  ///
  /// جدا از اجرای هسته است تا بتوان بی آنکه چیزی اجرا شود آزمون نوشت.
  static Future<String> writeConfig({
    required Directory runDir,
    required String rawYaml,
    required bool tun,
    required int mixedPort,
    int apiPort = 0,
    String preferred = '',
  }) async {
    await runDir.create(recursive: true);
    final File file =
        File('${runDir.path}${Platform.pathSeparator}clash-meta.yaml');
    await file.writeAsString(
      ClashConfig.adapt(
        rawYaml,
        tun: tun,
        mixedPort: mixedPort,
        apiPort: apiPort,
        preferred: preferred,
      ),
      flush: true,
    );
    return file.path;
  }
}
