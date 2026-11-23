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
    for (final AudioPlayer player in <AudioPlayer>[
      _clickPlayer,
      _statePlayer,
      _alertPlayer,
    ]) {
      unawaited(player.setReleaseMode(ReleaseMode.stop).catchError((Object _) {}));
    }
    if (!kIsWeb && Platform.isAndroid) {
      unawaited(
        _clickPlayer.setPlayerMode(PlayerMode.lowLatency).catchError((Object _) {}),
      );
      final AudioContext sfxContext = AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
          audioFocus: AndroidAudioFocus.none,
        ),
      );
      for (final AudioPlayer player in <AudioPlayer>[
        _clickPlayer,
        _statePlayer,
        _alertPlayer,
      ]) {
        unawaited(player.setAudioContext(sfxContext).catchError((Object _) {}));
      }
    }
  }

  final AudioPlayer _clickPlayer = AudioPlayer();
  final AudioPlayer _statePlayer = AudioPlayer();
  final AudioPlayer _alertPlayer = AudioPlayer();
  bool enabled = true;
  bool _failureReported = false;
  DateTime? _lastClick;
  String _lastStateEvent = '';
  DateTime? _lastStateEventAt;
  String _lastAlertEvent = '';
  DateTime? _lastAlertEventAt;

  Future<void> play(String name) async {
    if (!enabled ||
        !const <String>{'click', 'connect', 'disconnect', 'error', 'notify'}
            .contains(name)) {
      return;
    }
    final DateTime now = DateTime.now();
    final AudioPlayer player;
    if (name == 'click') {
      if (_lastClick != null &&
          now.difference(_lastClick!) < const Duration(milliseconds: 40)) {
        return;
      }
      _lastClick = now;
      player = _clickPlayer;
    } else if (name == 'connect' || name == 'disconnect') {
      if (_lastStateEvent == name &&
          _lastStateEventAt != null &&
          now.difference(_lastStateEventAt!) < const Duration(milliseconds: 500)) {
        return;
      }
      _lastStateEvent = name;
      _lastStateEventAt = now;
      player = _statePlayer;
    } else {
      if (_lastAlertEvent == name &&
          _lastAlertEventAt != null &&
          now.difference(_lastAlertEventAt!) < const Duration(milliseconds: 500)) {
        return;
      }
      _lastAlertEvent = name;
      _lastAlertEventAt = now;
      player = _alertPlayer;
    }
    try {
      await player.stop();
      if (!enabled) return;
      await player.play(
        AssetSource('sounds/$name.wav'),
        volume: name == 'click' ? 0.55 : 0.85,
      );
      _failureReported = false;
    } catch (_) {
      if (!_failureReported) {
        _failureReported = true;
        AppLogger.instance.add(
          'پخش صدای برنامه ناموفق بود؛ وضعیت صدای دستگاه را بررسی کنید.',
          level: 'warning',
        );
      }
    }
  }

  Future<void> dispose() async {
    await _clickPlayer.dispose();
    await _statePlayer.dispose();
    await _alertPlayer.dispose();
  }
}

/// هماهنگ کننده چرخه عمر برنامه و نوار وضعیت سیستم عامل اندروید.
class WindowService {
  WindowService(this._native);

  // نگه داشتن مرجع native برای هم راستا شدن سازنده با سایر کنترلرها.
  // ignore: unused_field
  final NativeBridge _native;

  bool notificationsEnabled = true;
  bool closeToTray = true;
  bool _visible = true;
  VoidCallback? onVisibilityChanged;
  Future<void> Function()? onBeforeQuit;
  Brightness? _appliedBrightness;

  bool get isVisible => _visible;
  bool get isHiddenToTray => !_visible;
  bool get isFocused => _visible;

  Future<void> init({
    Size? size,
    Brightness initialBrightness = Brightness.dark,
    bool startHidden = false,
  }) async {
    syncBrightness(initialBrightness);
    _visible = !startHidden;
    onVisibilityChanged?.call();
  }

  void setLifecycleVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    onVisibilityChanged?.call();
  }

  void syncBrightness(Brightness brightness) {
    if (_appliedBrightness == brightness) return;
    _appliedBrightness = brightness;
    final bool isDark = brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor:
            isDark ? const Color(0xFF0A0C10) : const Color(0xFFF5F6FA),
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
    );
  }

  Future<void> minimize() async => hide();
  Future<void> toggleMaximize() async {}

  Future<void> hide() async {
    _visible = false;
    onVisibilityChanged?.call();
    await SystemNavigator.pop();
  }

  Future<void> show() async {
    _visible = true;
    onVisibilityChanged?.call();
  }

  Future<void> onWindowClose() async => quit();

  Future<void> quit() async {
    final Future<void> Function()? before = onBeforeQuit;
    if (before != null) {
      try {
        await before();
      } on Exception {
        // خروج متوقف نمی شود.
      }
    }
    await SystemNavigator.pop();
  }
}

/// هماهنگ کننده وضعیت نوار اعلان و کاشی سریع اندروید.
class TrayService {
  TrayService(this._native);

  final NativeBridge _native;
  bool notificationsEnabled = true;
  bool showSpeedInTray = true;
  Future<void> Function()? onConnect;
  Future<void> Function()? onDisconnect;
  Future<void> Function()? onOpen;
  Future<void> Function()? onQuit;

  Future<void> init() async {
    await _native.setNotificationsEnabled(notificationsEnabled);
  }

  Future<void> update({
    required String state,
    required String tooltip,
    required bool connected,
  }) async {
    // اعلان نوار بالای اندروید دقیقاً هم تراز ویندوز است: عنوان «به آمبرلا متصل شد»
    // و متن پینگ یا وضعیت امن، بنابراین با برچسب سرعت بازنویسی نمی شود.
  }

  Future<void> syncConnectedNotification({required String body}) async {
    final String cleanBody = Fa.num(body);
    await _native.updateConnectedNotification(
      title: 'به آمبرلا متصل شد',
      body: cleanBody,
      alert: false,
    );
  }

  Future<void> balloon(String title, String body, {bool warning = false}) async {
    final String cleanTitle = Fa.num(AppNotification.summarizeTitle(title, body));
    final String cleanBody = Fa.num(
      AppNotification.summarizeBody(body, title: title, maxChars: 105),
    );
    if (!notificationsEnabled) return;
    AppLogger.instance.add(
      cleanBody.isEmpty ? cleanTitle : '$cleanTitle: $cleanBody',
      level: warning ? 'warning' : 'info',
    );
    await _native.showTrayBalloon(
      title: cleanTitle,
      body: cleanBody,
      warning: warning,
    );
  }

  Future<void> destroy() async {}
}

/// بررسی آی پی و موقعیت دستگاه (کشور و شهر) پیش از اتصال.
class IpService {
  IpService({http.Client? client})
      : _injectedClient = client != null,
        _client = client ?? _createClient(direct: true);

  final bool _injectedClient;
  final http.Client _client;
  GeoInfo _cache = GeoInfo.empty;
  DateTime _cachedAt = DateTime.fromMillisecondsSinceEpoch(0);

  GeoInfo get last => _cache;

  static http.Client _createClient({required bool direct}) {
    final HttpClient inner = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 10);
    inner.findProxy =
        direct ? (Uri _) => 'DIRECT' : HttpClient.findProxyFromEnvironment;
    return IOClient(inner);
  }

  /// خواندن آی پی و موقعیت؛ اگر تونل فعال است، درخواست از همان پروکسی محلی
  /// می رود تا آی پی واقعی به جای آی پی خروجی گزارش نشود.
  Future<GeoInfo> fetch({
    bool force = false,
    String proxy = '',
    String proxyUser = '',
    String proxyPassword = '',
  }) async {
    if (!force &&
        proxy.isEmpty &&
        _cache.ip.isNotEmpty &&
        DateTime.now().difference(_cachedAt) < const Duration(minutes: 3)) {
      return _cache;
    }
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

  void close() {
    if (!_injectedClient) {
      _client.close();
    }
  }

  void dispose() => close();
}

/// سرویس بررسی، دانلود و نصب به روز رسانی فایل APK اندروید.
class UpdateService {
  UpdateService({http.Client? client, String? preferredAbi})
      : _injectedClient = client != null,
        _preferredAbi = preferredAbi ?? 'arm64-v8a',
        _client = client ?? _createClient();

  final bool _injectedClient;
  final String _preferredAbi;
  final http.Client _client;

  static http.Client _createClient() {
    final HttpClient inner = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..idleTimeout = const Duration(seconds: 15);
    return IOClient(inner);
  }

  static bool hasValidSha256(String value) =>
      RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value.trim());

  Map<String, String> get _headers => <String, String>{
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Umbrella-Android/${AppConfig.version}',
      };

  Future<({UpdateInfo? available, List<UpdateInfo> releases})> fetchCatalog({
    required UpdateChannel channel,
  }) async {
    final bool includeBeta = channel == UpdateChannel.beta;
    if (AppConfig.updateManifestUrl.isNotEmpty) {
      final UpdateInfo? direct =
          await _fetchManifest(AppConfig.updateManifestUrl);
      if (direct != null) {
        return (
          available: direct.isNewer ? direct : null,
          releases: <UpdateInfo>[direct],
        );
      }
    }

    final List<UpdateInfo> all = await _fetchReleases(includePreReleases: includeBeta);
    UpdateInfo? best;
    for (final UpdateInfo item in all) {
      if (!item.isNewer) continue;
      if (best == null ||
          UpdateInfo.compareVersions(item.version, best.version) > 0) {
        best = item;
      }
    }
    return (available: best, releases: all);
  }

  Future<UpdateInfo?> _fetchManifest(String url) async {
    try {
      final http.Response res = await _client
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode >= 300) return null;
      final Map<String, dynamic> map = JsonX.asMap(
        jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true)),
      );
      return _accept(map);
    } on Exception {
      return null;
    }
  }

  Future<List<UpdateInfo>> _fetchReleases({
    required bool includePreReleases,
  }) async {
    try {
      final http.Response res = await _client
          .get(Uri.parse(AppConfig.releasesListApiUrl), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode >= 300) {
        return const <UpdateInfo>[];
      }
      final List<dynamic> list = JsonX.asList(
        jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true)),
      );
      final List<UpdateInfo> items = <UpdateInfo>[];
      for (final Object? entry in list) {
        final Map<String, dynamic> map = JsonX.asMap(entry);
        final UpdateInfo? parsed =
            await _parseGithubRelease(map, includePreReleases: includePreReleases);
        if (parsed != null) items.add(parsed);
      }
      return items;
    } on Exception {
      return const <UpdateInfo>[];
    }
  }

  Future<UpdateInfo?> _parseGithubRelease(
    Map<String, dynamic> json, {
    required bool includePreReleases,
  }) async {
    if (json.isEmpty || JsonX.boolean(json['draft'])) {
      return null;
    }
    final String tag = JsonX.text(json['tag_name']);
    final String version = UpdateInfo.normalizeVersion(tag);
    if (version.isEmpty || !RegExp(r'^\d+\.\d+\.\d+').hasMatch(version)) {
      return null;
    }
    final bool isPreRelease =
        JsonX.boolean(json['prerelease']) || UpdateInfo.isPreReleaseTag(tag);
    if (isPreRelease && !includePreReleases) {
      return null;
    }
    final List<Map<String, dynamic>> assets = JsonX.asList(json['assets'])
        .map(JsonX.asMap)
        .where((Map<String, dynamic> item) => item.isNotEmpty)
        .toList();
    final Map<String, dynamic>? apkAsset = _pickAndroidApk(assets);
    if (apkAsset == null) {
      return null;
    }
    final String releaseBody = JsonX.text(json['body']);
    final String url = JsonX.text(apkAsset['browser_download_url']);
    final String assetName = JsonX.text(apkAsset['name']);
    final int size = JsonX.integer(apkAsset['size']);
    String sha = _extractDigestSha256(JsonX.text(apkAsset['digest']));
    if (sha.isEmpty && releaseBody.isNotEmpty) {
      sha = _extractBodySha256(releaseBody, assetName: assetName);
    }
    if (sha.isEmpty) {
      sha = await _shaForRelease(tag: tag, assetName: assetName);
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

  Map<String, dynamic>? _pickAndroidApk(List<Map<String, dynamic>> assets) {
    final String abi = _preferredAbi.toLowerCase();
    Map<String, dynamic>? universalApk;
    Map<String, dynamic>? anyApk;
    for (final Map<String, dynamic> asset in assets) {
      final String name = JsonX.text(asset['name']).toLowerCase();
      final String url = JsonX.text(asset['browser_download_url']);
      if (url.isEmpty || !name.endsWith('.apk')) continue;
      anyApk ??= asset;
      if (abi.isNotEmpty && name.contains(abi)) {
        return asset;
      }
      if (name.contains('universal') ||
          (!name.contains('arm64') &&
              !name.contains('armeabi') &&
              !name.contains('x86_64'))) {
        universalApk ??= asset;
      }
    }
    return universalApk ?? anyApk;
  }

  static String _extractDigestSha256(String digest) {
    final RegExpMatch? match =
        RegExp(r'^(?:sha256:)?([0-9a-fA-F]{64})$').firstMatch(digest.trim());
    return match?.group(1)?.toLowerCase() ?? '';
  }

  static String _extractBodySha256(String body, {String assetName = ''}) {
    final String fromSums = parseSha256Sums(body, assetName: assetName);
    if (fromSums.isNotEmpty) {
      return fromSums;
    }
    final RegExpMatch? androidMatch = RegExp(
      r'sha[-_ ]?256\s*\(\s*android[^)]*\)\s*[:=]\s*`?([0-9a-fA-F]{64})`?',
      caseSensitive: false,
    ).firstMatch(body);
    if (androidMatch != null) {
      return androidMatch.group(1)!.toLowerCase();
    }
    final RegExpMatch? labeled = RegExp(
      r'sha[-_ ]?256\s*[:=]\s*`?([0-9a-fA-F]{64})`?',
      caseSensitive: false,
    ).firstMatch(body);
    return labeled?.group(1)?.toLowerCase() ?? '';
  }

  Future<String> _shaForRelease({
    required String tag,
    String assetName = '',
  }) async {
    final String url =
        'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/'
        '$tag/SHA256SUMS.txt';
    try {
      final http.Response response = await _client
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode >= 300) return '';
      final String body = utf8.decode(response.bodyBytes, allowMalformed: true);
      return parseSha256Sums(body, assetName: assetName);
    } on Exception {
      return '';
    }
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

  UpdateInfo? _accept(Map<String, dynamic> json) {
    if (json.isEmpty) return null;
    final UpdateInfo info = UpdateInfo.fromJson(json);
    if (info.version.isEmpty ||
        info.url.isEmpty ||
        !info.isNewer ||
        !hasValidSha256(info.sha256)) {
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
    return 'UmbrellaVPN-${info.version}.apk';
  }

  Future<bool> _matchesSha256(File file, String expectedHex) async {
    final _DigestCapture capture = _DigestCapture();
    final ByteConversionSink hashSink = sha256.startChunkedConversion(capture);
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
      final String expectedSha256 = info.sha256.trim().toLowerCase();
      if (!hasValidSha256(expectedSha256)) {
        return null;
      }
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

      if (await target.exists()) {
        if (await _matchesSha256(target, expectedSha256)) {
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

      final http.Request req = http.Request('GET', downloadUri)
        ..headers.addAll(<String, String>{
          'Accept': 'application/octet-stream',
          'User-Agent': 'Umbrella-Android/${AppConfig.version}',
        });
      final http.StreamedResponse streamed =
          await _client.send(req).timeout(const Duration(seconds: 30));
      if (streamed.statusCode >= 300) {
        return null;
      }
      final int total = streamed.contentLength ?? info.sizeBytes;
      int received = 0;
      final IOSink activeSink = partFile.openWrite();
      sink = activeSink;
      await for (final List<int> chunk in streamed.stream) {
        if (isCancelled != null && isCancelled()) {
          await activeSink.close();
          sink = null;
          if (await partFile.exists()) await partFile.delete();
          return null;
        }
        activeSink.add(chunk);
        received += chunk.length;
        final double progress =
            total > 0 ? (received / total).clamp(0.0, 0.99) : 0.0;
        onProgress(progress, received, total);
      }
      await activeSink.flush();
      await activeSink.close();
      sink = null;

      onProgress(1.0, received, received);
      if (!await _matchesSha256(partFile, expectedSha256)) {
        await partFile.delete();
        return null;
      }
      if (await target.exists()) {
        await target.delete();
      }
      await partFile.rename(target.path);
      await _pruneOldInstallers(dir, keepName: name);
      return target;
    } on Exception {
      try {
        await sink?.close();
      } on Exception {
        // نادیده گرفته می شود.
      }
      try {
        if (partFile != null && await partFile.exists()) {
          await partFile.delete();
        }
      } on Exception {
        // نادیده گرفته می شود.
      }
      return null;
    }
  }

  /// درخواست نصب فایل APK از طریق سیستم عامل اندروید پس از تایید مجدد SHA-256.
  Future<bool> install(
    File file,
    NativeBridge native, {
    required String expectedSha256,
    bool silentRelaunch = true,
  }) async {
    final String lower = file.path.toLowerCase();
    final String digest = expectedSha256.trim().toLowerCase();
    if (!hasValidSha256(digest) || !lower.endsWith('.apk')) {
      return false;
    }
    try {
      if (!await file.exists() || !await _matchesSha256(file, digest)) {
        return false;
      }
    } on Exception {
      return false;
    }
    final ({bool ok, String reason}) result = await native.installApk(file.path);
    return result.ok;
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
            // نادیده گرفته می شود.
          }
        }
      }
    } on FileSystemException {
      // نادیده گرفته می شود.
    }
  }

  void dispose() {
    if (!_injectedClient) {
      _client.close();
    }
  }
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

/// مناسبت های تقویم شمسی و میلادی به همراه مناسبت های قمری.
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
    if (parts.length != 2) return <int>[1, 1];
    return <int>[int.tryParse(parts[0]) ?? 1, int.tryParse(parts[1]) ?? 1];
  }

  static int _color(String value) {
    final String hex = value.replaceAll('#', '').replaceAll('0x', '');
    final int? parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return 0xFFE11D2E;
    return 0xFF000000 | parsed;
  }

  static int? _optionalColor(Object? value) {
    final String text = JsonX.text(value).trim();
    if (text.isEmpty) return null;
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
    if (_items.isNotEmpty) return;
    try {
      final String raw = await rootBundle.loadString('assets/data/occasions.json');
      final Map<String, dynamic> json = JsonX.asMap(jsonDecode(raw));
      _items = JsonX.asList(json['items'])
          .map((Object? item) => Occasion.fromJson(JsonX.asMap(item)))
          .toList();
    } on Exception {
      _items = <Occasion>[];
    }
  }

  Occasion? get active => activeAt(DateTime.now());

  Occasion? activeAt(DateTime now) {
    if (_items.isEmpty) return null;
    final List<int> jalaliToday = <int>[
      Fa.jalali(now).month,
      Fa.jalali(now).day,
    ];
    final List<int> gregorianToday = <int>[now.month, now.day];
    final int hijriMonth = _hijriMonth(now);
    for (final Occasion occasion in _items) {
      if (occasion.hijri) {
        if (hijriMonth == 9) return occasion;
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
  final List<String> _previousCrashes = <String>[];
  List<LogLine> get lines => List<LogLine>.unmodifiable(_lines.reversed.toList());

  void attachPreviousCrashes(List<String> reports) {
    _previousCrashes
      ..clear()
      ..addAll(reports
          .map((String item) => redact(item).trim())
          .where((String item) => item.isNotEmpty));
  }

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

  static String redact(String input) {
    if (input.isEmpty) return input;
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
      if (parts.length != 4) return full;
      for (final String part in parts) {
        final int? octet = int.tryParse(part);
        if (octet == null || octet < 0 || octet > 255) return full;
      }
      if (ip == '127.0.0.1' || ip == '0.0.0.0') return full;
      return '[سرور محافظت شده]';
    });
    text = text.replaceAllMapped(_ipv6PortPattern, (Match match) {
      final String host = match.group(1)!.toLowerCase();
      if (host == '::1' || host == '::') return match.group(0)!;
      return '[سرور محافظت شده]';
    });
    text = text.replaceAll(_protocolTokenPattern, '');
    return text
        .split('\n')
        .map((String line) {
          final int indentEnd = line.length - line.trimLeft().length;
          final String indent = line.substring(0, indentEnd);
          final String body = line
              .substring(indentEnd)
              .replaceAll(_inlineSpacesPattern, ' ')
              .trimRight();
          return '$indent$body';
        })
        .join('\n');
  }

  void add(
    String message, {
    String level = 'info',
    List<LogDetail> details = const <LogDetail>[],
  }) {
    final String clean = redact(message).trim();
    if (clean.isEmpty) return;
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
      if (kDebugMode) debugPrint('[${level.toUpperCase()}] $clean');
      notifyListeners();
      return;
    }
    _lines.add(LogLine(clean, level: level, details: safeDetails));
    if (_lines.length > 2000) {
      _lines.removeRange(0, _lines.length - 2000);
    }
    if (kDebugMode) debugPrint('[${level.toUpperCase()}] $clean');
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }

  int countOf(String level) =>
      _lines.where((LogLine line) => line.level == level).length;

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
      'تعداد هسته پردازنده: ${Fa.num(Platform.numberOfProcessors)}',
      'پوشه داده: $dataDir',
      'پورت کنترل هسته: ${Fa.num(AppConfig.coreGrpcPort)}',
      'پورت رابط هسته: ${Fa.num(AppConfig.coreClashPort)}',
      'زمان گزارش: ${Fa.dateTime(DateTime.now())}',
    ].join('\n');
  }

  static String _systemLabel() {
    final String raw = Platform.operatingSystemVersion;
    return Fa.num('اندروید • $raw');
  }

  String environmentTextSync() => <String>[
        'برنامه: ${AppConfig.appName} ${Fa.num(AppConfig.version)}',
        'سیستم: ${_systemLabel()}',
        'تعداد هسته پردازنده: ${Fa.num(Platform.numberOfProcessors)}',
        'پورت کنترل هسته: ${Fa.num(AppConfig.coreGrpcPort)}',
        'پورت رابط هسته: ${Fa.num(AppConfig.coreClashPort)}',
        'زمان گزارش: ${Fa.dateTime(DateTime.now())}',
      ].join('\n');

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
        if (text.isEmpty) continue;
        if (detail.title.isNotEmpty) {
          buffer.writeln('    ── ${detail.title} ──');
        }
        for (final String row in text.split('\n')) {
          buffer.writeln('    $row');
        }
      }
    }
    if (_previousCrashes.isNotEmpty) {
      buffer.writeln('── گزارش خطای نشست قبلی ──');
      for (final String crash in _previousCrashes) {
        buffer.writeln(crash);
        buffer.writeln('---');
      }
    }
    return buffer.toString();
  }

  static String lineDetailText(LogLine line) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('${Fa.date(line.time)} — ${Fa.clock(line.time)}')
      ..writeln('سطح: ${line.level}')
      ..writeln('پیام: ${redact(line.message)}');
    for (final LogDetail detail in line.details) {
      final String detailText = redact(detail.text).trim();
      if (detailText.isEmpty) continue;
      buffer.writeln();
      final String detailTitle = redact(detail.title).trim();
      if (detailTitle.isNotEmpty) {
        buffer.writeln('── $detailTitle ──');
      }
      buffer.writeln(detailText);
    }
    return buffer.toString();
  }

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
