// سرویس های اندروید: صدا، آی پی، مناسبت ها و گزارش برنامه.
//
// این فایل جایگزین platform/services.dart ویندوز است. WindowService و
// TrayService ویندوز روی اندروید وجود ندارند (پنجره و سینی دسکتاپ) و
// UpdateService ویندوز (نصب کننده exe) با نصب APK جایگزین شده است؛
// آن بخش در state/update_controller.dart پیاده شده است.

import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Brightness, Color, Size;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';

import '../core/app_config.dart';
import '../core/utils.dart';
import '../models/models.dart';
import 'native.dart';

/// Android equivalent of the window controls used by the unchanged shared UI.
class WindowService {
  WindowService(this._native);
  final NativeBridge _native;
  bool closeToTray = true;
  bool notificationsEnabled = true;
  bool get isHiddenToTray => false;
  Future<void> Function()? onBeforeQuit;
  Brightness? _brightness;
  bool _quitting = false;

  Future<void> init({Size? size, Brightness initialBrightness = Brightness.dark}) async {
    syncBrightness(initialBrightness);
  }

  void syncBrightness(Brightness brightness) {
    if (_brightness == brightness) return;
    _brightness = brightness;
    final dark = brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: const Color(0x00000000),
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: dark ? const Color(0xff07080b) : const Color(0xfff5f6fa),
      systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    ));
  }

  Future<void> minimize() => _native.minimizeApp();
  Future<void> hide() => _native.minimizeApp();
  Future<void> show() async {}
  Future<void> toggleMaximize() async {}
  Future<void> startDragging() async {}
  Future<void> onWindowClose() => closeToTray ? hide() : quit();
  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    try {
      await onBeforeQuit?.call();
      await SystemNavigator.pop();
    } finally {
      _quitting = false;
    }
  }
}

/// Same notification interface used by the shared account controller.
/// Android has no desktop tray; event notifications are delegated to the OS.
class TrayService {
  TrayService(this._native);
  final NativeBridge _native;

  Future<void> balloon(String title, String body, {bool warning = false}) async {
    await _native.showNotification(title: title, body: body, warning: warning);
  }
}

/// پخش صداهای کوتاه برنامه (اتصال، قطع، خطا و اعلان).
class SoundService {
  SoundService() {
    _player.setReleaseMode(ReleaseMode.stop);
  }

  final AudioPlayer _player = AudioPlayer();
  bool enabled = true;

  Future<void> play(String name) async {
    if (!enabled) {
      return;
    }
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/$name.wav'), volume: 0.65);
    } on Exception {
      // صدا اختیاری است؛ نبود کارت صدا نباید اتصال را متوقف کند.
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}

/// خواندن آی پی و موقعیت خروجی از چند سرویس مستقل.
class IpService {
  IpService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  GeoInfo _cache = GeoInfo.empty;
  DateTime _cachedAt = DateTime.fromMillisecondsSinceEpoch(0);

  GeoInfo get last => _cache;

  /// خواندن آی پی و موقعیت؛ اگر تونل فعال است، درخواست از همان پروکسی محلی
  /// می رود تا آی پی واقعی به جای آی پی خروجی گزارش نشود.
  Future<GeoInfo> fetch({
    bool force = false,
    String proxy = '',
    String proxyUser = '',
    String proxyPassword = '',
  }) async {
    if (!force && proxy.isEmpty && _cache.ip.isNotEmpty &&
        DateTime.now().difference(_cachedAt) < const Duration(minutes: 3)) {
      return _cache;
    }
    // چند سرویس مستقل: اگر یکی در دسترس نباشد (فیلتر، دی ان اس یا قطعی خود
    // سرویس)، بعدی امتحان می شود. `ipwho.is` و `ipify` بدون کلید کار می
    // کنند و از داخل ایران باز هستند.
    final List<String> endpoints = <String>[
      'https://ipwho.is/',
      'https://api.ip.sb/geoip',
      'https://ipinfo.io/json',
      'https://api.myip.com',
      'https://api.ipify.org?format=json',
    ];
    http.Client? temporary;
    http.Client client = _client;
    if (proxy.isNotEmpty) {
      final HttpClient inner = HttpClient();
      inner.findProxy = (Uri _) => 'PROXY $proxy';
      inner.connectionTimeout = const Duration(seconds: 5);
      if (proxyUser.isNotEmpty && proxyPassword.isNotEmpty) {
        final HttpClientBasicCredentials creds =
            HttpClientBasicCredentials(proxyUser, proxyPassword);
        final int sep = proxy.lastIndexOf(':');
        if (sep > 0) {
          final String pHost = proxy.substring(0, sep);
          final int? pPort = int.tryParse(proxy.substring(sep + 1));
          if (pPort != null && pPort > 0) {
            inner.addProxyCredentials(pHost, pPort, '', creds);
          }
        }
        inner.authenticateProxy =
            (String host, int port, String scheme, String? realm) async {
          inner.addProxyCredentials(host, port, realm ?? '', creds);
          return true;
        };
      }
      temporary = IOClient(inner);
      client = temporary;
    }
    try {
      for (final String endpoint in endpoints) {
        try {
          final http.Response response = await client
              .get(
                Uri.parse(endpoint),
                headers: <String, String>{
                  'Accept': 'application/json',
                  'User-Agent': 'Umbrella-Android/${AppConfig.version}',
                },
              )
              .timeout(const Duration(seconds: 5));
          if (response.statusCode >= 300) {
            continue;
          }
          final Map<String, dynamic> json = JsonX.asMap(
            jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true)),
          );
          // ipwho.is هنگام محدودیت نرخ با کد ۲۰۰ و `success: false` جواب می دهد.
          if (json['success'] == false || json['status'] == 'fail') {
            continue;
          }
          final Map<String, dynamic> connection = JsonX.asMap(json['connection']);
          final Object? rawTz = json['timezone'];
          final String timezone = rawTz is Map
              ? JsonX.text(rawTz['id'])
              : JsonX.text(rawTz ?? json['timezone_id']);
          final GeoInfo geo = GeoInfo.fromJson(<String, dynamic>{
            'ip': json['ip'] ??
                json['query'] ??
                json['ip_addr'] ??
                json['ip_address'],
            'city': json['city'],
            'country': json['country'] ?? json['country_name'],
            'countryCode': json['country_code'] ??
                json['countryCode'] ??
                json['cc'],
            'region': json['region'] ?? json['regionName'] ?? json['region_name'],
            'isp': json['isp'] ??
                json['org'] ??
                connection['isp'] ??
                JsonX.asMap(json['asn'])['org'],
            'timezone': timezone,
            'latitude': json['latitude'] ?? json['lat'],
            'longitude': json['longitude'] ?? json['lon'],
          });
          if (geo.ip.isNotEmpty) {
            if (proxy.isEmpty) {
              _cache = geo;
              _cachedAt = DateTime.now();
            }
            return geo;
          }
        } on Exception {
          continue;
        }
      }
    } finally {
      temporary?.close();
    }
    // وقتی درخواست اجباری (`force`) یا از مسیر پروکسی/تونل بوده و هیچ سرویسی
    // جواب نداده، هرگز کش قبلی (آی پی واقعی پیش از اتصال) برگردانده نمی شود.
    if (proxy.isNotEmpty || force) {
      return GeoInfo.empty;
    }
    return _cache;
  }

  Future<String> fetchIp({bool force = false}) async {
    final GeoInfo geo = await fetch(force: force);
    if (geo.ip.isNotEmpty) {
      return geo.ip;
    }
    try {
      final http.Response response = await _client
          .get(Uri.parse(AppConfig.ipCheckPrimary))
          .timeout(const Duration(seconds: 6));
      final Map<String, dynamic> json = JsonX.asMap(
        jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true)),
      );
      return JsonX.text(json['ip']);
    } on Exception {
      return '';
    }
  }

  void close() => _client.close();
}

class Occasion {
  const Occasion({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tint,
    required this.startMonth,
    required this.startDay,
    required this.endMonth,
    required this.endDay,
    this.secondaryTint,
    this.accentTint,
    this.gregorian = false,
    this.hijri = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final String icon;
  final int tint;
  final int? secondaryTint;
  final int? accentTint;
  final int startMonth;
  final int startDay;
  final int endMonth;
  final int endDay;
  final bool gregorian;
  final bool hijri;

  factory Occasion.fromJson(Map<String, dynamic> json) {
    final List<int> start = _split(JsonX.text(json['start']));
    final List<int> end = _split(JsonX.text(json['end']));
    return Occasion(
      id: JsonX.text(json['id']),
      title: JsonX.text(json['title']),
      subtitle: JsonX.text(json['subtitle']),
      icon: JsonX.text(json['icon'], 'auto_awesome'),
      tint: _color(JsonX.text(json['tint'])),
      secondaryTint: _optionalColor(json['secondary_tint']),
      accentTint: _optionalColor(json['accent_tint']),
      startMonth: start[0],
      startDay: start[1],
      endMonth: end[0],
      endDay: end[1],
      gregorian: JsonX.text(json['calendar']).toLowerCase() == 'gregorian',
      hijri: JsonX.boolean(json['hijri']),
    );
  }

  static List<int> _split(String value) {
    final List<String> parts = value.split('-');
    if (parts.length != 2) {
      return <int>[1, 1];
    }
    return <int>[int.tryParse(parts[0]) ?? 1, int.tryParse(parts[1]) ?? 1];
  }

  static int _color(String value) {
    final String hex = value.replaceAll('#', '').replaceAll('0x', '');
    final int? parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) {
      return 0xFFE11D2E;
    }
    return 0xFF000000 | parsed;
  }

  static int? _optionalColor(Object? value) {
    final String text = JsonX.text(value).trim();
    if (text.isEmpty) {
      return null;
    }
    final String hex = text.replaceAll('#', '').replaceAll('0x', '');
    final int? parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? null : 0xFF000000 | parsed;
  }
}

class OccasionService {
  OccasionService._();

  static final OccasionService instance = OccasionService._();
  List<Occasion> _items = <Occasion>[];

  List<Occasion> get items => _items;

  Future<void> load() async {
    if (_items.isNotEmpty) {
      return;
    }
    try {
      final String raw = await _readAsset('assets/data/occasions.json');
      final Map<String, dynamic> json = JsonX.asMap(jsonDecode(raw));
      _items = JsonX.asList(json['items'])
          .map((Object? item) => Occasion.fromJson(JsonX.asMap(item)))
          .toList();
    } on Exception {
      _items = <Occasion>[];
    }
  }

  Future<String> _readAsset(String path) async {
    try {
      return await rootBundle.loadString(path);
    } on Exception {
      return '{}';
    }
  }

  Occasion? get active => activeAt(DateTime.now());

  /// Resolves an occasion using its declared calendar.
  /// Accepts a date for deterministic checks.
  Occasion? activeAt(DateTime now) {
    if (_items.isEmpty) {
      return null;
    }
    final List<int> jalaliToday = <int>[
      Fa.jalali(now).month,
      Fa.jalali(now).day,
    ];
    final List<int> gregorianToday = <int>[now.month, now.day];
    final int hijriMonth = _hijriMonth(now);
    for (final Occasion occasion in _items) {
      if (occasion.hijri) {
        if (hijriMonth == 9) {
          return occasion;
        }
        continue;
      }
      final List<int> today = occasion.gregorian ? gregorianToday : jalaliToday;
      if (_within(today, occasion.startMonth, occasion.startDay,
          occasion.endMonth, occasion.endDay)) {
        return occasion;
      }
    }
    return null;
  }

  bool _within(List<int> today, int sm, int sd, int em, int ed) {
    final int value = today[0] * 100 + today[1];
    final int start = sm * 100 + sd;
    final int end = em * 100 + ed;
    if (start <= end) {
      return value >= start && value <= end;
    }
    return value >= start || value <= end;
  }

  /// شماره ماه قمری با الگوریتم کویتی (دقت یک روز).
  static int _hijriMonth(DateTime time) {
    int l = _julianDay(time) - 1948440 + 10632;
    final int n = (l - 1) ~/ 10631;
    l = l - 10631 * n + 354;
    final int j = ((10985 - l) ~/ 5316) * ((50 * l) ~/ 17719) +
        (l ~/ 5670) * ((43 * l) ~/ 15238);
    l = l -
        ((30 - j) ~/ 15) * ((17719 * j) ~/ 50) -
        (j ~/ 16) * ((15238 * j) ~/ 43) +
        29;
    final int month = (24 * l) ~/ 709;
    return month.clamp(1, 12);
  }

  static int _julianDay(DateTime time) {
    int year = time.year;
    int month = time.month;
    final int day = time.day;
    if (month < 3) {
      year -= 1;
      month += 12;
    }
    final int a = year ~/ 100;
    final int b = 2 - a + a ~/ 4;
    return (365.25 * (year + 4716)).floor() +
        (30.6001 * (month + 1)).floor() +
        day +
        b -
        1524;
  }
}

/// گزارش های برنامه برای صفحه «گزارش ها».
class AppLogger extends ChangeNotifier {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  final List<LogLine> _lines = <LogLine>[];
  List<LogLine> get lines => List<LogLine>.unmodifiable(_lines.reversed.toList());

  static final RegExp _proxyUriPattern = RegExp(
    r'\b(?:vless|vmess|trojan|ssr?|hysteria2?|hy2|tuic|wireguard|wg|warp|socks5?|anytls|ssh|mieru)://[^\s\)\]>\"\x27،؛]+',
    caseSensitive: false,
  );
  static final RegExp _webUriPattern = RegExp(
    r'\b(?:https?|wss?|quic|h3|tls)://[^\s\)\]>\"\x27،؛]+',
    caseSensitive: false,
  );
  static final RegExp _subPathPattern = RegExp(
    r'(?:/[A-Za-z0-9_-]{3,})*/sub(?:/[^\s\)\]>\"\x27،؛]*|\b)',
    caseSensitive: false,
  );
  static final RegExp _uuidPattern = RegExp(
    r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
  );
  static final RegExp _outboundTagPattern = RegExp(
    r'\boutbound/[A-Za-z0-9_-]+(?:\[[^\]]*\])?',
    caseSensitive: false,
  );
  static final RegExp _hostPortPattern = RegExp(
    r'\b(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,24}:[0-9\u06F0-\u06F9\u0660-\u0669]{1,5}(?![0-9\u06F0-\u06F9\u0660-\u0669])',
    caseSensitive: false,
  );
  static final RegExp _domainPattern = RegExp(
    r'\b(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+(?:ir|com|net|org|io|co|me|xyz|top|site|online|cloud|dev|app|pro|info|biz|cc|gg|tv|ru|de|nl|uk|fr|us|ca|tr|ae|fi|se|ch|pl|cz|at|es|it|jp|sg|hk|kr|in|au|br|pw|club|shop|store|tech|space|live|link|click|work|fun|cfd|sbs|cyou|icu|vip|win|one|host|server|network|services|digital|world)\b(?::[0-9\u06F0-\u06F9\u0660-\u0669]{1,5})?(?:/[^\s\)\]>\"\x27،؛]*)?',
    caseSensitive: false,
  );
  static final RegExp _ipv4Pattern = RegExp(
    r'(?<![0-9\u06F0-\u06F9\u0660-\u0669.])([0-9\u06F0-\u06F9\u0660-\u0669]{1,3}(?:\.[0-9\u06F0-\u06F9\u0660-\u0669]{1,3}){3})(?::[0-9\u06F0-\u06F9\u0660-\u0669]{1,5})?(?![0-9\u06F0-\u06F9\u0660-\u0669.])',
  );
  static final RegExp _ipv6PortPattern = RegExp(
    r'\[([0-9a-fA-F:]{2,})\]:[0-9\u06F0-\u06F9\u0660-\u0669]{1,5}',
  );
  static final RegExp _protocolTokenPattern = RegExp(
    r'\b(?:vmess|vless|trojan|shadowsocks|hysteria2?|hy2|tuic|httpupgrade|splithttp|xhttp|reality|shadowtls|anytls|mieru|tls|cdn)\b',
    caseSensitive: false,
  );
  static final RegExp _linkFilePattern = RegExp(
    r'[^\s\"\x27]*umbrella-core-link\.txt',
    caseSensitive: false,
  );
  static final RegExp _inlineSpacesPattern = RegExp(r'[ \t]{2,}');

  /// پاک سازی خودکار اطلاعات محرمانه سرور و لینک اشتراک از تمام گزارش ها.
  static String redact(String input) {
    if (input.isEmpty) {
      return input;
    }
    String text = input;
    text = text.replaceAll(_proxyUriPattern, '[محافظت شده]');
    text = text.replaceAll(_webUriPattern, '[لینک محافظت شده]');
    text = text.replaceAll(_subPathPattern, '[اشتراک محافظت شده]');
    text = text.replaceAll(_uuidPattern, '[شناسه محافظت شده]');
    text = text.replaceAll(_outboundTagPattern, 'خروجی [محافظت شده]');
    text = text.replaceAll(_linkFilePattern, '[محافظت شده]');
    text = text.replaceAll(_hostPortPattern, '[سرور محافظت شده]');
    text = text.replaceAll(_domainPattern, '[سرور محافظت شده]');
    text = text.replaceAllMapped(_ipv4Pattern, (Match match) {
      final String full = match.group(0)!;
      final String ip = Fa.toEn(match.group(1)!);
      final List<String> parts = ip.split('.');
      if (parts.length != 4) {
        return full;
      }
      for (final String part in parts) {
        final int? octet = int.tryParse(part);
        if (octet == null || octet < 0 || octet > 255) {
          return full;
        }
      }
      if (ip == '127.0.0.1' || ip == '0.0.0.0') {
        return full;
      }
      return '[سرور محافظت شده]';
    });
    text = text.replaceAllMapped(_ipv6PortPattern, (Match match) {
      final String host = match.group(1)!.toLowerCase();
      if (host == '::1' || host == '::') {
        return match.group(0)!;
      }
      return '[سرور محافظت شده]';
    });
    text = text.replaceAll(_protocolTokenPattern, '');
    return text
        .split('\n')
        .map((String line) {
          final int indentEnd = line.length - line.trimLeft().length;
          final String indent = line.substring(0, indentEnd);
          final String body =
              line.substring(indentEnd).replaceAll(_inlineSpacesPattern, ' ').trimRight();
          return '$indent$body';
        })
        .join('\n');
  }

  /// تکرارِ بی وقفه یک پیام، گزارش را ناخوانا می کند. خط تکراری پشت سر هم
  /// فقط یک بار می ماند و بعد از آن تعدادش کنار همان خط می آید.
  void add(
    String message, {
    String level = 'info',
    List<LogDetail> details = const <LogDetail>[],
  }) {
    final String clean = redact(message).trim();
    if (clean.isEmpty) {
      return;
    }
    final List<LogDetail> safeDetails = details.isEmpty
        ? const <LogDetail>[]
        : details
            .map(
              (LogDetail detail) => LogDetail(
                title: redact(detail.title).trim(),
                text: redact(detail.text).trim(),
              ),
            )
            .where((LogDetail detail) => detail.text.isNotEmpty)
            .toList(growable: false);
    if (_lines.isNotEmpty &&
        _lines.last.message == clean &&
        _lines.last.level == level) {
      _lines.last.repeat++;
      if (kDebugMode) {
        debugPrint('[${level.toUpperCase()}] $clean');
      }
      notifyListeners();
      return;
    }
    _lines.add(LogLine(clean, level: level, details: safeDetails));
    if (_lines.length > 2000) {
      _lines.removeRange(0, _lines.length - 2000);
    }
    if (kDebugMode) {
      debugPrint('[${level.toUpperCase()}] $clean');
    }
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }

  int countOf(String level) =>
      _lines.where((LogLine line) => line.level == level).length;

  /// اطلاعات محیط؛ بدون آن، خروجی خام هسته معلوم نمی کند روی چه سیستمی و با
  /// چه تنظیماتی رخ داده است.
  Future<String> environmentText() async {
    String dataDir = '';
    try {
      final Directory dir = await getApplicationSupportDirectory();
      dataDir = dir.path;
    } on Exception {
      dataDir = 'نامشخص';
    }
    return <String>[
      'برنامه: ${AppConfig.appName} ${Fa.num(AppConfig.version)}',
      'سیستم: ${_systemLabel()}',
      'پیوند هسته های پردازنده: ${Fa.num(Platform.numberOfProcessors)}',
      'پوشه داده: $dataDir',
      'پورت کنترل هسته: ${Fa.num(AppConfig.coreGrpcPort)}',
      'پورت رابط هسته: ${Fa.num(AppConfig.coreClashPort)}',
      'زمان گزارش: ${Fa.dateTime(DateTime.now())}',
    ].join('\n');
  }

  /// نام سیستم عامل به فارسی و خوانا.
  static String _systemLabel() {
    final String raw = Platform.operatingSystemVersion;
    final String arch =
        Platform.version.contains('arm64') ? 'آرم ۶۴ بیت' : '۶۴ بیت';
    return Fa.num('اندروید • $arch • $raw');
  }

  /// همان اطلاعات محیط، به صورت متن آماده؛ برای جایی که await ممکن نیست.
  String environmentTextSync() => <String>[
        'برنامه: ${AppConfig.appName} ${Fa.num(AppConfig.version)}',
        'سیستم: ${_systemLabel()}',
        'پیوند هسته های پردازنده: ${Fa.num(Platform.numberOfProcessors)}',
        'پورت کنترل هسته: ${Fa.num(AppConfig.coreGrpcPort)}',
        'پورت رابط هسته: ${Fa.num(AppConfig.coreClashPort)}',
        'زمان گزارش: ${Fa.dateTime(DateTime.now())}',
      ].join('\n');

  /// متن کامل گزارش ها برای کپی یا ارسال به پشتیبانی.
  String exportText() {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln(
      '${AppConfig.appName} ${Fa.num(AppConfig.version)} | ${Fa.dateTime(DateTime.now())}',
    );
    buffer.writeln(environmentTextSync());
    buffer.writeln('──────────────────────────────');
    for (final LogLine line in _lines) {
      buffer.writeln(
        '${Fa.date(line.time)} ${Fa.clock(line.time)} | ${line.level} | '
        '${line.message}${line.repeat > 1 ? ' (×${Fa.num(line.repeat)})' : ''}',
      );
      for (final LogDetail detail in line.details) {
        final String text = detail.text.trim();
        if (text.isEmpty) {
          continue;
        }
        if (detail.title.isNotEmpty) {
          buffer.writeln('    ── ${detail.title} ──');
        }
        for (final String row in text.split('\n')) {
          buffer.writeln('    $row');
        }
      }
    }
    return buffer.toString();
  }

  /// متن یک خط با همه جزئیات آن.
  static String lineDetailText(LogLine line) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('${Fa.date(line.time)} — ${Fa.clock(line.time)}')
      ..writeln('سطح: ${line.level}')
      ..writeln('پیام: ${redact(line.message)}');
    for (final LogDetail detail in line.details) {
      final String detailText = redact(detail.text).trim();
      if (detailText.isEmpty) {
        continue;
      }
      buffer.writeln();
      final String detailTitle = redact(detail.title).trim();
      if (detailTitle.isNotEmpty) {
        buffer.writeln('── $detailTitle ──');
      }
      buffer.writeln(detailText);
    }
    return buffer.toString();
  }

  /// ذخیره گزارش در پوشه داده برنامه و برگرداندن مسیر فایل.
  Future<String> saveToFile() async {
    final Directory dir = await getApplicationSupportDirectory();
    final Directory logs = Directory('${dir.path}${Platform.pathSeparator}logs');
    await logs.create(recursive: true);
    final DateTime now = DateTime.now();
    final String stamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
        '-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final File file =
        File('${logs.path}${Platform.pathSeparator}umbrella-$stamp.log');
    final String env = await environmentText();
    await file.writeAsString('$env\n\n${exportText()}', flush: true);
    return file.path;
  }
}
