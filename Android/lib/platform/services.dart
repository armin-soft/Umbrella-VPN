import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';

import '../core/app_config.dart';
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

/// مدیریت نوار وضعیت، پس زمینه و چرخه حیات برنامه در فلاتر اندروید.
class WindowService {
  WindowService(this._native);

  final NativeBridge _native;
  bool closeToTray = true;
  bool notificationsEnabled = true;
  bool _initialized = false;
  bool _quitting = false;
  bool _hiddenToTray = false;

  /// آیا برنامه به پس زمینه منتقل شده است.
  bool get isHiddenToTray => _hiddenToTray;

  /// پیش از خروج کامل برنامه صدا زده می شود تا سرویس تونل تمیز بسته شود.
  Future<void> Function()? onBeforeQuit;
  Brightness? _appliedBrightness;

  static void _applyOverlay(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor:
            isDark ? const Color(0xFF07080B) : const Color(0xFFF5F6FA),
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
    );
  }

  Future<void> init({
    Size? size,
    Brightness initialBrightness = Brightness.dark,
  }) async {
    if (_initialized) {
      return;
    }
    _appliedBrightness = initialBrightness;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _applyOverlay(initialBrightness);
    unawaited(_native.syncSystemBars(dark: initialBrightness == Brightness.dark));
    _initialized = true;
  }

  /// همگام سازی رنگ نوار وضعیت و نوار ناوبری اندروید با تم روشن و تاریک.
  void syncBrightness(Brightness brightness) {
    if (_appliedBrightness == brightness) {
      return;
    }
    _appliedBrightness = brightness;
    _applyOverlay(brightness);
    if (_initialized) {
      unawaited(_native.syncSystemBars(dark: brightness == Brightness.dark));
    }
  }

  Future<void> minimize() async {
    _hiddenToTray = true;
    await _native.minimizeApp();
  }

  Future<void> toggleMaximize() async {}

  Future<void> hide() async {
    _hiddenToTray = true;
    await _native.minimizeApp();
  }

  Future<void> show() async {
    _hiddenToTray = false;
  }

  Future<void> quit() async {
    if (_quitting) {
      return;
    }
    _quitting = true;
    bool ranCleanup = false;
    try {
      final Future<void> Function()? cleanup = onBeforeQuit;
      if (cleanup != null) {
        await cleanup().timeout(
          const Duration(milliseconds: 2200),
          onTimeout: () {},
        );
        ranCleanup = true;
      }
    } catch (_) {
      // خطای پاک سازی نباید مانع بسته شدن برنامه شود.
    }
    try {
      await _native.shutdownCores(skipIfClean: ranCleanup).timeout(
            const Duration(milliseconds: 900),
            onTimeout: () => 0,
          );
    } catch (_) {}
    await SystemNavigator.pop();
    _quitting = false;
  }

  Future<void> startDragging() async {}

  Future<void> onWindowClose() async {
    if (_quitting) {
      return;
    }
    if (closeToTray) {
      await hide();
      return;
    }
    await quit();
  }
}

/// مدیریت اعلان های وضعیت و پیام های سیستمی در اندروید.
class TrayService {
  TrayService(this._native);

  final NativeBridge _native;
  bool _initialized = false;

  Future<bool> init() async {
    if (_initialized) {
      return true;
    }
    _initialized = await _native.trayInit();
    return _initialized;
  }

  Future<void> update({
    required String state,
    required String tooltip,
    required bool connected,
  }) async {
    if (!_initialized) {
      return;
    }
  }

  Future<void> balloon(String title, String body, {bool warning = false}) async {
    if (!_initialized) {
      return;
    }
    final String cleanTitle = AppNotification.summarizeTitle(title, body);
    final String cleanBody =
        AppNotification.summarizeBody(body, title: title, maxChars: 120);
    await _native.trayBalloon(
      title: cleanTitle,
      body: cleanBody,
      warning: warning,
    );
  }

  Future<void> destroy() async {
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
    // سرویس)، بعدی امتحان می شود. پیش از این اگر هر سه به دی ان اس ناسالم
    // می خوردند، آی پی خوانده نمی شد و برنامه به آی پی داخلی برمی گشت.
    // `ipapi.co` از این شبکه ۴۰۳ می دهد (در گزارش ۱٫۰٫۱۸ دیدیم)، پس اول
    // `ipwho.is` و `ipify` می آیند: هر دو بدون کلید کار می کنند و از داخل
    // ایران باز هستند.
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
          // api.ipify.org پاسخ تخت `{"ip": "..."}` می دهد و بقیه فیلدها را
          // ندارد؛ همان آی پی برای نمایش کافی است.
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
    // جواب نداده، هرگز کش قبلی (آی پی واقعی پیش از اتصال) برگردانده نمی شود؛
    // برگرداندن آی پی قبلی در حالت تونل باعث می شد `_verifyTunnel` به اشتباه
    // تصور کند آی پی عوض نشده و اتصال سالم را قطع کند.
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

class _DigestCapture implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

/// بررسی، دانلود درون برنامه ای با تایید SHA-256 و نصب بی وقفه نسخه ویندوز
/// در دو کانال اصلی (پایدار) و بتا (آزمایشی).
class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<UpdateInfo?> check({
    UpdateChannel channel = UpdateChannel.stable,
  }) async {
    final ({UpdateInfo? available, List<UpdateInfo> releases}) catalog =
        await fetchCatalog(channel: channel);
    return catalog.available;
  }

  Future<({UpdateInfo? available, List<UpdateInfo> releases})> fetchCatalog({
    UpdateChannel channel = UpdateChannel.stable,
  }) async {
    if (AppConfig.updateManifestUrl.isNotEmpty) {
      final UpdateInfo? manual = await _checkManifest(channel: channel);
      if (manual != null) {
        return (available: manual, releases: <UpdateInfo>[manual]);
      }
    }
    final List<UpdateInfo> list = await _fetchGithubReleases(channel: channel);
    if (list.isNotEmpty) {
      UpdateInfo latest = list.first;
      if (latest.isNewer && latest.sha256.isEmpty && latest.tagName.isNotEmpty) {
        final String sha = await _shaForRelease(
          tag: latest.tagName,
          version: latest.version,
          assetName: latest.assetName,
        );
        if (sha.isNotEmpty) {
          latest = UpdateInfo(
            version: latest.version,
            url: latest.url,
            sha256: sha,
            notes: latest.notes,
            mandatory: latest.mandatory,
            sizeBytes: latest.sizeBytes,
            publishedAt: latest.publishedAt,
            preRelease: latest.preRelease,
            tagName: latest.tagName,
            assetName: latest.assetName,
          );
          list[0] = latest;
        }
      }
      return (
        available: latest.isNewer ? latest : null,
        releases: list,
      );
    }
    if (channel == UpdateChannel.stable) {
      final UpdateInfo? single = await _checkGithubRelease();
      if (single != null) {
        return (
          available: single.isNewer ? single : null,
          releases: <UpdateInfo>[single],
        );
      }
    }
    return (available: null, releases: const <UpdateInfo>[]);
  }

  /// خواندن فهرست JSON دستی (اگر کسی تنظیم کرده باشد).
  Future<UpdateInfo?> _checkManifest({
    UpdateChannel channel = UpdateChannel.stable,
  }) async {
    try {
      final http.Response response = await _client
          .get(
            Uri.parse(AppConfig.updateManifestUrl),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode >= 300) {
        return null;
      }
      final Map<String, dynamic> json = JsonX.asMap(
        jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true)),
      );
      final UpdateInfo? candidate = _accept(json);
      if (candidate == null) {
        return null;
      }
      if (channel == UpdateChannel.stable && candidate.preRelease) {
        return null;
      }
      return candidate;
    } on Exception {
      return null;
    }
  }

  /// خواندن فهرست انتشارها از API گیت هاب برای هر دو کانال پایدار و بتا.
  Future<List<UpdateInfo>> _fetchGithubReleases({
    required UpdateChannel channel,
  }) async {
    try {
      final http.Response response = await _client
          .get(Uri.parse(AppConfig.releasesListApiUrl), headers: _headers)
          .timeout(const Duration(seconds: 14));
      if (response.statusCode >= 300) {
        return <UpdateInfo>[];
      }
      final Object? decoded =
          jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
      final List<Object?> items = JsonX.asList(decoded);
      final List<UpdateInfo> parsed = <UpdateInfo>[];
      for (final Object? raw in items) {
        final UpdateInfo? info = parseGithubRelease(
          JsonX.asMap(raw),
          includePreReleases: channel == UpdateChannel.beta,
        );
        if (info != null) {
          parsed.add(info);
        }
      }
      parsed.sort(
        (UpdateInfo a, UpdateInfo b) =>
            UpdateInfo.compareVersions(b.version, a.version),
      );
      return parsed;
    } on Exception {
      return <UpdateInfo>[];
    }
  }

  /// خواندن آخرین انتشار پایدار از API گیت هاب (مسیر پشتیبان کانال اصلی).
  Future<UpdateInfo?> _checkGithubRelease() async {
    try {
      final http.Response response = await _client
          .get(Uri.parse(AppConfig.releaseApiUrl), headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode >= 300) {
        return null;
      }
      final Map<String, dynamic> json = JsonX.asMap(
        jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true)),
      );
      final UpdateInfo? info =
          parseGithubRelease(json, includePreReleases: false);
      if (info == null) {
        return null;
      }
      if (info.sha256.isNotEmpty || !info.isNewer) {
        return info;
      }
      final String sha = await _shaForRelease(
        tag: info.tagName,
        version: info.version,
        assetName: info.assetName,
      );
      return UpdateInfo(
        version: info.version,
        url: info.url,
        sha256: sha,
        notes: info.notes,
        mandatory: info.mandatory,
        sizeBytes: info.sizeBytes,
        publishedAt: info.publishedAt,
        preRelease: info.preRelease,
        tagName: info.tagName,
        assetName: info.assetName,
      );
    } on Exception {
      return null;
    }
  }

  /// تجزیه یک انتشار گیت هاب، تشخیص دقیق بتا / پایدار و استخراج فایل نصبی و SHA-256.
  static UpdateInfo? parseGithubRelease(
    Map<String, dynamic> json, {
    required bool includePreReleases,
    String? preferredAbi,
  }) {
    if (json.isEmpty || JsonX.boolean(json['draft'])) {
      return null;
    }
    final String tag = JsonX.text(json['tag_name']);
    if (RegExp(r'-(windows|ios|macos)$', caseSensitive: false).hasMatch(tag)) {
      return null;
    }
    final String version = UpdateInfo.normalizeVersion(tag);
    if (version.isEmpty || !RegExp(r'^\d+\.\d+\.\d+').hasMatch(version)) {
      return null;
    }
    final List<Map<String, dynamic>> assets = JsonX.asList(json['assets'])
        .map(JsonX.asMap)
        .where((Map<String, dynamic> item) => item.isNotEmpty)
        .toList();
    final Map<String, dynamic>? installerAsset = _pickAndroidApk(
      assets,
      preferredAbi: preferredAbi,
    );
    if (installerAsset == null && !_isReleaseForAndroid(tag)) {
      return null;
    }
    final bool isPreRelease =
        JsonX.boolean(json['prerelease']) || UpdateInfo.isPreReleaseTag(tag);
    if (isPreRelease && !includePreReleases) {
      return null;
    }

    final String releaseBody = JsonX.text(json['body']);
    String url = '';
    String assetName = '';
    int size = 0;
    String sha = '';
    if (installerAsset != null) {
      url = JsonX.text(installerAsset['browser_download_url']);
      assetName = JsonX.text(installerAsset['name']);
      size = JsonX.integer(installerAsset['size']);
      sha = _extractDigestSha256(JsonX.text(installerAsset['digest']));
    }
    if (sha.isEmpty && releaseBody.isNotEmpty) {
      sha = _extractBodySha256(releaseBody, assetName: assetName);
    }
    if (url.isEmpty) {
      final String coreVersion = _versionOf(tag);
      if (coreVersion.isEmpty) {
        return null;
      }
      assetName = 'UmbrellaVPN-$coreVersion-universal.apk';
      url = _installerUrl(tag, coreVersion);
    }
    return UpdateInfo(
      version: version,
      url: url,
      sha256: sha,
      notes: releaseBody,
      mandatory: false,
      sizeBytes: size,
      publishedAt: JsonX.dateTime(json['published_at']),
      preRelease: isPreRelease,
      tagName: tag,
      assetName: assetName,
    );
  }

  static String _preferredAbi() {
    final String v = Platform.version.toLowerCase();
    if (v.contains('android_arm64') || v.contains('arm64')) {
      return 'arm64-v8a';
    }
    if (v.contains('android_arm')) {
      return 'armeabi-v7a';
    }
    if (v.contains('android_x64') || v.contains('x86_64')) {
      return 'x86_64';
    }
    return 'universal';
  }

  static Map<String, dynamic>? _pickAndroidApk(
    List<Map<String, dynamic>> assets, {
    String? preferredAbi,
  }) {
    final String abi = (preferredAbi ?? _preferredAbi()).toLowerCase();
    Map<String, dynamic>? universalApk;
    Map<String, dynamic>? fallbackApk;
    for (final Map<String, dynamic> asset in assets) {
      final String name = JsonX.text(asset['name']).toLowerCase();
      final String url = JsonX.text(asset['browser_download_url']);
      if (url.isEmpty || !name.endsWith('.apk')) continue;
      if (abi != 'universal' && name.contains(abi)) {
        return asset;
      }
      if (universalApk == null && name.contains('universal')) {
        universalApk = asset;
      }
      fallbackApk ??= asset;
    }
    return universalApk ?? fallbackApk;
  }

  static String _extractDigestSha256(String digest) {
    final RegExpMatch? match = RegExp(
      r'^(?:sha256:)?([0-9a-fA-F]{64})$',
    ).firstMatch(digest.trim());
    return match?.group(1)?.toLowerCase() ?? '';
  }

  static String _extractBodySha256(String body, {String assetName = ''}) {
    final String fromSums = parseSha256Sums(body, assetName: assetName);
    if (fromSums.isNotEmpty) {
      return fromSums;
    }
    final RegExpMatch? labeled = RegExp(
      r'sha[-_ ]?256\s*[:=]\s*`?([0-9a-fA-F]{64})`?',
      caseSensitive: false,
    ).firstMatch(body);
    return labeled?.group(1)?.toLowerCase() ?? '';
  }

  Map<String, String> get _headers => <String, String>{
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Umbrella-Android/${AppConfig.version}',
      };

  /// فقط نسخه اندروید این مخزن به روز رسانی دارد.
  static bool _isReleaseForAndroid(String tag) =>
      tag.toLowerCase().contains('android');

  /// `v1.0.0-android` یا `1.0.0` → `1.0.0`.
  static String _versionOf(String tag) {
    final RegExpMatch? match = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(tag);
    return match?.group(1) ?? '';
  }

  /// مسیر مستقیم بسته نصب اندروید در مخزن رسمی انتشار.
  static String _installerUrl(String tag, String version) =>
      'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/'
      '$tag/UmbrellaVPN-$version-universal.apk';

  /// اثر انگشت SHA-256 فایل نصب در صورتی که در گیت هاب یا متن انتشار نیامده باشد.
  Future<String> _shaForRelease({
    required String tag,
    required String version,
    String assetName = '',
  }) async {
    final List<String> candidates = <String>[
      'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/'
          '$tag/SHA256SUMS.txt',
    ];
    for (final String url in candidates) {
      try {
        final http.Response response = await _client
            .get(Uri.parse(url), headers: _headers)
            .timeout(const Duration(seconds: 10));
        if (response.statusCode >= 300) {
          continue;
        }
        final String body =
            utf8.decode(response.bodyBytes, allowMalformed: true);
        final String parsed = parseSha256Sums(body, assetName: assetName);
        if (parsed.isNotEmpty) {
          return parsed;
        }
      } on Exception {
        // نشانی بعدی امتحان می شود.
      }
    }
    return '';
  }

  static String parseSha256Sums(String body, {String assetName = ''}) {
    final String wanted = assetName.trim().toLowerCase();
    String firstHash = '';
    for (final String rawLine in body.split(RegExp(r'\r?\n'))) {
      final RegExpMatch? match = RegExp(
        r'^\s*([0-9a-fA-F]{64})(?:\s+[* ]?(.+))?$',
      ).firstMatch(rawLine.trim());
      if (match == null) continue;
      final String hash = match.group(1)!.toLowerCase();
      final String file = (match.group(2) ?? '').trim().toLowerCase();
      firstHash = firstHash.isEmpty ? hash : firstHash;
      if (wanted.isNotEmpty && file.endsWith(wanted)) {
        return hash;
      }
      if (wanted.isEmpty && file.endsWith('.apk')) {
        return hash;
      }
    }
    return firstHash;
  }

  /// پذیرش فقط اگر نسخه واقعا تازه تر باشد.
  UpdateInfo? _accept(Map<String, dynamic> json) {
    if (json.isEmpty) {
      return null;
    }
    final UpdateInfo info = UpdateInfo.fromJson(json);
    if (info.version.isEmpty || info.url.isEmpty || !info.isNewer) {
      return null;
    }
    return info;
  }

  static String _safeInstallerName(UpdateInfo info) {
    final String raw = info.assetName.isNotEmpty
        ? info.assetName
        : Uri.tryParse(info.url)?.pathSegments.lastOrNull ?? '';
    final String cleaned =
        raw.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '').trim();
    if (cleaned.toLowerCase().endsWith('.apk')) {
      return cleaned;
    }
    return 'UmbrellaVPN-${info.version}-universal.apk';
  }

  Future<bool> _matchesSha256(File file, String expectedHex) async {
    final _DigestCapture capture = _DigestCapture();
    final ByteConversionSink hashSink =
        sha256.startChunkedConversion(capture);
    await for (final List<int> chunk in file.openRead()) {
      hashSink.add(chunk);
    }
    hashSink.close();
    final String actual = capture.value?.toString().toLowerCase() ?? '';
    return actual == expectedHex.toLowerCase();
  }

  Future<File?> download(
    UpdateInfo info, {
    required void Function(double progress, int received, int total) onProgress,
    bool Function()? isCancelled,
    Directory? targetDir,
  }) async {
    File? partFile;
    IOSink? sink;
    try {
      final Directory dir;
      if (targetDir != null) {
        dir = targetDir;
      } else {
        final Directory base = await getTemporaryDirectory();
        dir = Directory(
          '${base.path}${Platform.pathSeparator}umbrella-updates',
        );
      }
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final String name = _safeInstallerName(info);
      final File target = File('${dir.path}${Platform.pathSeparator}$name');

      // اگر فایل معتبر قبلاً کامل دریافت و تایید شده باشد، بی درنگ آماده نصب است.
      if (info.sha256.isNotEmpty && await target.exists()) {
        if (await _matchesSha256(target, info.sha256)) {
          final int len = await target.length();
          onProgress(1.0, len, len);
          return target;
        }
        await target.delete();
      }

      final Uri? downloadUri = Uri.tryParse(info.url.trim());
      if (downloadUri == null ||
          downloadUri.scheme.toLowerCase() != 'https' ||
          downloadUri.host.isEmpty) {
        return null;
      }

      partFile = File('${target.path}.part');
      if (await partFile.exists()) {
        await partFile.delete();
      }

      final http.Request request = http.Request('GET', downloadUri);
      request.headers['User-Agent'] = 'Umbrella-Android/${AppConfig.version}';
      final http.StreamedResponse response =
          await _client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode >= 300) {
        return null;
      }
      final int total = (response.contentLength ?? 0) > 0
          ? response.contentLength!
          : info.sizeBytes;
      final IOSink activeSink = partFile.openWrite();
      sink = activeSink;
      final _DigestCapture capture = _DigestCapture();
      final ByteConversionSink hashSink =
          sha256.startChunkedConversion(capture);
      int received = 0;

      await for (final List<int> chunk
          in response.stream.timeout(const Duration(seconds: 45))) {
        if (isCancelled?.call() == true) {
          await activeSink.close();
          sink = null;
          hashSink.close();
          if (await partFile.exists()) {
            await partFile.delete();
          }
          return null;
        }
        activeSink.add(chunk);
        hashSink.add(chunk);
        received += chunk.length;
        onProgress(
          total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0,
          received,
          total,
        );
      }
      await activeSink.flush();
      await activeSink.close();
      sink = null;
      hashSink.close();

      if (received <= 0 || (total > 0 && received < total)) {
        if (await partFile.exists()) {
          await partFile.delete();
        }
        return null;
      }

      if (info.sha256.isNotEmpty) {
        final String actual = capture.value?.toString().toLowerCase() ?? '';
        if (actual != info.sha256.toLowerCase()) {
          if (await partFile.exists()) {
            await partFile.delete();
          }
          return null;
        }
      }

      if (await target.exists()) {
        await target.delete();
      }
      final File ready = await partFile.rename(target.path);
      await _pruneOldInstallers(dir, keepName: name);
      return ready;
    } on Exception {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (partFile != null && await partFile.exists()) {
          await partFile.delete();
        }
      } catch (_) {}
      return null;
    }
  }

  /// نصب درون برنامه ای بسته رسمی APK در اندروید از طریق نصب کننده امن سیستم.
  Future<bool> install(
    File file,
    NativeBridge native, {
    bool silentRelaunch = true,
  }) async {
    final String lower = file.path.toLowerCase();
    if (lower.endsWith('.apk')) {
      return native.installApk(file.path);
    }
    return native.openPath(file.path);
  }

  static Future<void> _pruneOldInstallers(
    Directory dir, {
    required String keepName,
  }) async {
    try {
      await for (final FileSystemEntity entity in dir.list()) {
        if (entity is! File) continue;
        final String base =
            entity.path.split(Platform.pathSeparator).last.toLowerCase();
        if (base == keepName.toLowerCase()) continue;
        if (base.endsWith('.apk') || base.endsWith('.part')) {
          try {
            await entity.delete();
          } on FileSystemException {
            // فایل قدیمی قفل شده نادیده گرفته می شود.
          }
        }
      }
    } on FileSystemException {
      // پاک سازی کش موقت اختیاری است.
    }
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

  static final RegExp _proxyUriPattern = RegExp(
    r'\b(?:vless|vmess|trojan|ssr?|hysteria2?|hy2|tuic|wireguard|wg|warp|socks5?|anytls|ssh|mieru)://[^\s\)\]>"\x27،؛]+',
    caseSensitive: false,
  );
  static final RegExp _webUriPattern = RegExp(
    r'\b(?:https?|wss?|quic|h3|tls)://[^\s\)\]>"\x27،؛]+',
    caseSensitive: false,
  );
  static final RegExp _subPathPattern = RegExp(
    r'(?:/[A-Za-z0-9_-]{3,})*/sub(?:/[^\s\)\]>"\x27،؛]*|\b)',
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
    r'\b(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+(?:ir|com|net|org|io|co|me|xyz|top|site|online|cloud|dev|app|pro|info|biz|cc|gg|tv|ru|de|nl|uk|fr|us|ca|tr|ae|fi|se|ch|pl|cz|at|es|it|jp|sg|hk|kr|in|au|br|pw|club|shop|store|tech|space|live|link|click|work|fun|cfd|sbs|cyou|icu|vip|win|one|host|server|network|services|digital|world)\b(?::[0-9\u06F0-\u06F9\u0660-\u0669]{1,5})?(?:/[^\s\)\]>"\x27،؛]*)?',
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
    r'[^\s"\x27]*umbrella-core-link\.txt',
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

  /// تکرارِ بی وقفه یک پیام، گزارش را ناخوانا می کند و کاربر را به این باور
  /// می برد که برنامه در حال «تلاش بی پایان» است. خط تکراری پشت سر هم فقط
  /// یک بار می ماند و بعد از آن تعدادش کنار همان خط می آید.
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
    final String arch = Platform.version.contains('arm64')
        ? 'آرم ۶۴ بیت'
        : (Platform.version.contains('arm') ? 'آرم ۳۲ بیت' : '۶۴ بیت');
    if (Platform.isAndroid) {
      return Fa.num('اندروید • $arch');
    }
    return Fa.num('اندروید • $arch');
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
      // جزئیات با تورفتگی زیر همان خط می آید تا در فایل هم معلوم باشد مال
      // کدام خطا است.
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
    // فایل روی دیسک، کامل ترین نسخه است: محیط سیستم هم بالای آن می آید تا
    // کاربر فقط همان یک فایل را بفرستد.
    final String env = await environmentText();
    await file.writeAsString('$env\n\n${exportText()}', flush: true);
    return file.path;
  }
}
