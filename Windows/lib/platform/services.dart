import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_config.dart';
import '../core/persian.dart';
import '../core/utils.dart';
import '../models/models.dart';
import 'native.dart';

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

/// مدیریت پنجره بدون قاب پیش فرض ویندوز: کوچک کردن، بزرگ کردن، بستن به سینی.
class WindowService with WindowListener {
  WindowService(this._native);

  final NativeBridge _native;
  bool closeToTray = true;
  bool _initialized = false;

  Future<void> init({Size? size}) async {
    if (_initialized) {
      return;
    }
    await windowManager.ensureInitialized();
    final WindowOptions options = WindowOptions(
      size: size ?? const Size(1280, 820),
      minimumSize: const Size(1120, 720),
      center: true,
      backgroundColor: const Color(0xFF07080B),
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    _initialized = true;
  }

  Future<void> minimize() async {
    await windowManager.minimize();
  }

  Future<void> toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Future<void> hide() async {
    await windowManager.hide();
  }

  Future<void> show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> quit() async {
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  Future<void> startDragging() async {
    await windowManager.startDragging();
  }

  @override
  void onWindowClose() async {
    if (closeToTray) {
      await windowManager.hide();
      await _native.trayBalloon(
        title: 'فیلترشکن آمبرلا',
        body: 'برنامه در سینی سیستم اجرا می شود؛ برای باز کردن روی آیکون کلیک کنید.',
      );
      return;
    }
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }
}

/// آیکون سینی سیستم و منوی آن.
class TrayService {
  TrayService(this._native);

  final NativeBridge _native;
  bool _initialized = false;

  static const Map<String, String> _iconFiles = <String, String>{
    'connected': 'state-connected.ico',
    'connecting': 'state-connecting.ico',
    'failed': 'state-failed.ico',
    'disconnected': 'state-disconnected.ico',
    'idle': 'state-idle.ico',
  };

  Future<bool> init() async {
    if (_initialized) {
      return true;
    }
    _initialized = await _native.trayInit();
    await update(
      state: 'disconnected',
      tooltip: '${AppConfig.appName} - قطع',
      connected: false,
    );
    return _initialized;
  }

  String _iconPath(String state) {
    final String file = _iconFiles[state] ?? _iconFiles['idle']!;
    final String exe = Platform.resolvedExecutable;
    final String dir = exe.substring(0, exe.lastIndexOf(Platform.pathSeparator));
    return '$dir${Platform.pathSeparator}data${Platform.pathSeparator}flutter_assets'
        '${Platform.pathSeparator}assets${Platform.pathSeparator}icons'
        '${Platform.pathSeparator}tray${Platform.pathSeparator}$file';
  }

  Future<void> update({
    required String state,
    required String tooltip,
    required bool connected,
  }) async {
    if (!_initialized) {
      return;
    }
    await _native.trayIcon(_iconPath(state));
    await _native.trayTooltip(tooltip);
    await _native.trayMenu(
      connectLabel: 'اتصال به فیلترشکن',
      disconnectLabel: 'قطع اتصال',
      connected: connected,
    );
  }

  Future<void> balloon(String title, String body, {bool warning = false}) async {
    if (!_initialized) {
      return;
    }
    await _native.trayBalloon(title: title, body: body, warning: warning);
  }

  Future<void> destroy() async {
    if (!_initialized) {
      return;
    }
    await _native.trayDestroy();
    _initialized = false;
  }
}

/// بررسی آی پی و موقعیت دستگاه (کشور و شهر) پیش از اتصال.
class IpService {
  IpService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  GeoInfo _cache = GeoInfo.empty;
  DateTime _cachedAt = DateTime.fromMillisecondsSinceEpoch(0);

  GeoInfo get last => _cache;

  Future<GeoInfo> fetch({bool force = false}) async {
    if (!force && _cache.ip.isNotEmpty &&
        DateTime.now().difference(_cachedAt) < const Duration(minutes: 3)) {
      return _cache;
    }
    final List<String> endpoints = <String>[
      'https://ipapi.co/json/',
      'http://ip-api.com/json/?fields=status,country,countryCode,regionName,city,isp,timezone,lat,lon,query',
      'https://ipwho.is/',
    ];
    for (final String endpoint in endpoints) {
      try {
        final http.Response response = await _client
            .get(
              Uri.parse(endpoint),
              headers: <String, String>{
                'Accept': 'application/json',
                'User-Agent': 'Umbrella-Windows/${AppConfig.version}',
              },
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode >= 300) {
          continue;
        }
        final Map<String, dynamic> json = JsonX.asMap(
          jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true)),
        );
        final Map<String, dynamic> connection = JsonX.asMap(json['connection']);
        final GeoInfo geo = GeoInfo.fromJson(<String, dynamic>{
          'ip': json['ip'] ?? json['query'],
          'city': json['city'],
          'country': json['country'] ?? json['country_name'],
          'countryCode': json['country_code'] ?? json['countryCode'],
          'region': json['region'] ?? json['regionName'] ?? json['region_name'],
          'isp': json['isp'] ??
              json['org'] ??
              connection['isp'] ??
              JsonX.asMap(json['asn'])['org'],
          'timezone': json['timezone'] ?? json['timezone_id'],
          'latitude': json['latitude'] ?? json['lat'],
          'longitude': json['longitude'] ?? json['lon'],
        });
        if (geo.ip.isNotEmpty) {
          _cache = geo;
          _cachedAt = DateTime.now();
          return geo;
        }
      } on Exception {
        continue;
      }
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

/// بررسی و نصب به روز رسانی نسخه ویندوز با نمایش درصد پیشرفت.
class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<UpdateInfo?> check() async {
    try {
      final http.Response response = await _client
          .get(
            Uri.parse(AppConfig.updateManifestUrl),
            headers: <String, String>{
              'Accept': 'application/json',
              'User-Agent': 'Umbrella-Windows/${AppConfig.version}',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode >= 300) {
        return null;
      }
      final Map<String, dynamic> json = JsonX.asMap(
        jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true)),
      );
      if (json.isEmpty) {
        return null;
      }
      final UpdateInfo info = UpdateInfo.fromJson(json);
      if (info.version.isEmpty || info.url.isEmpty || !info.isNewer) {
        return null;
      }
      return info;
    } on Exception {
      return null;
    }
  }

  Future<File?> download(
    UpdateInfo info, {
    required void Function(double progress, int received, int total) onProgress,
  }) async {
    try {
      final Directory dir = await getTemporaryDirectory();
      final String name = info.url.split('/').last;
      final File target = File('${dir.path}${Platform.pathSeparator}$name');
      if (await target.exists()) {
        await target.delete();
      }
      final http.Request request = http.Request('GET', Uri.parse(info.url));
      final http.StreamedResponse response =
          await _client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode >= 300) {
        return null;
      }
      final int total = response.contentLength ?? info.sizeBytes;
      final IOSink sink = target.openWrite();
      int received = 0;
      await for (final List<int> chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(total > 0 ? (received / total).clamp(0, 1) : 0, received, total);
      }
      await sink.flush();
      await sink.close();

      if (info.sha256.isNotEmpty) {
        final String hash =
            sha256.convert(await target.readAsBytes()).toString().toLowerCase();
        if (hash != info.sha256.toLowerCase()) {
          await target.delete();
          return null;
        }
      }
      return target;
    } on Exception {
      return null;
    }
  }

  Future<bool> install(File file, NativeBridge native) async {
    final String path = file.path.toLowerCase();
    if (path.endsWith('.msi')) {
      final int pid = await native.spawn(
        exe: 'msiexec.exe',
        args: '/i "$path" /passive /norestart',
        hidden: false,
      );
      return pid > 0;
    }
    if (path.endsWith('.exe')) {
      return native.runElevated(file.path);
    }
    return native.openPath(file.path);
  }
}

/// مناسبت های ایرانی: شب یلدا، نوروز، چهارشنبه سوری، سیزده بدر و مهرگان.
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
    this.hijri = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final String icon;
  final int tint;
  final int startMonth;
  final int startDay;
  final int endMonth;
  final int endDay;
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
      startMonth: start[0],
      startDay: start[1],
      endMonth: end[0],
      endDay: end[1],
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
      final String raw =
          await _readAsset('assets/data/occasions.json');
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

  Occasion? get active {
    if (_items.isEmpty) {
      return null;
    }
    final DateTime now = DateTime.now();
    final List<int> today = <int>[
      Fa.jalali(now).month,
      Fa.jalali(now).day,
    ];
    final int hijriMonth = _hijriMonth(now);
    for (final Occasion occasion in _items) {
      if (occasion.hijri) {
        if (hijriMonth == 9) {
          return occasion;
        }
        continue;
      }
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

  void add(String message, {String level = 'info'}) {
    _lines.add(LogLine(message, level: level));
    if (_lines.length > 400) {
      _lines.removeAt(0);
    }
    if (kDebugMode) {
      debugPrint('[${level.toUpperCase()}] $message');
    }
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }
}
