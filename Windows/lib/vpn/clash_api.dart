import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/app_config.dart';

/// Core connectivity states mirroring `hiddify-core v5.9.1`
/// (`v2/hcore/connectivity.go` + `hiddify-app` `ConnectionRepositoryImpl`):
///
/// * [offline] — loopback Clash controller has not started listening yet.
/// * [waiting] — core is up (`CoreStates_WAITING`), outbound URL tests running.
/// * [started] — `lowest` (or the active proxy leaf) has a fresh non-cached
///   URL-test ping (`0 < delay < 65000`) -> immediately `CoreStates_STARTED`.
/// * [noAvailableProxies] — every monitored proxy leaf timed out in this run
///   (`CoreStates_NO_AVAILABLE_PROXIES`).
enum CoreConnectivityState {
  offline,
  waiting,
  started,
  noAvailableProxies,
}

/// Live exit IP metadata populated by the core's built-in outbound monitoring
/// (`adapter.URLTestHistory.IpInfo` in `hiddify-sing-box`).
class CoreExitIpInfo {
  const CoreExitIpInfo({
    required this.ip,
    this.countryCode = '',
    this.region = '',
    this.city = '',
    this.org = '',
    this.asn = 0,
    this.fromCache = false,
  });

  final String ip;
  final String countryCode;
  final String region;
  final String city;
  final String org;
  final int asn;
  final bool fromCache;

  Map<String, dynamic> toGeoJson() => <String, dynamic>{
        'ip': ip,
        if (countryCode.isNotEmpty) 'country_code': countryCode,
        if (region.isNotEmpty) 'region': region,
        if (city.isNotEmpty) 'city': city,
        if (org.isNotEmpty) 'org': org,
        if (asn > 0) 'asn': 'AS$asn',
      };
}

/// Snapshot of the running core's outbound monitoring state via loopback Clash API.
class CoreProxySnapshot {
  const CoreProxySnapshot({
    required this.reachable,
    this.connectivity = CoreConnectivityState.offline,
    this.activeTag = '',
    this.activeDelayMs = 0,
    this.bestTag = '',
    this.bestDelayMs = 0,
    this.aliveCount = 0,
    this.failedCount = 0,
    this.untestedCount = 0,
    this.totalCount = 0,
    this.exitIpInfo,
  });

  static const CoreProxySnapshot offline = CoreProxySnapshot(
    reachable: false,
    connectivity: CoreConnectivityState.offline,
  );

  final bool reachable;
  final CoreConnectivityState connectivity;
  final String activeTag;
  final int activeDelayMs;
  final String bestTag;
  final int bestDelayMs;
  final int aliveCount;
  final int failedCount;
  final int untestedCount;
  final int totalCount;
  final CoreExitIpInfo? exitIpInfo;

  /// True once the running core has measured at least one responsive outbound
  /// in the active session (`CoreStates_STARTED` in `connectivity.go`).
  bool get hasLiveSelection =>
      connectivity == CoreConnectivityState.started ||
      activeDelayMs > 0 ||
      aliveCount > 0;

  /// True only when every single outbound in the pool was freshly tested in the
  /// current session and none of them answered (`CoreStates_NO_AVAILABLE_PROXIES`).
  bool get allTestedAndDead =>
      connectivity == CoreConnectivityState.noAvailableProxies ||
      (reachable &&
          totalCount > 0 &&
          aliveCount == 0 &&
          untestedCount == 0 &&
          failedCount >= totalCount);
}

/// Cumulative byte counters reported by the local core's `/connections` endpoint.
class CoreTrafficTotals {
  const CoreTrafficTotals({
    required this.rxBytes,
    required this.txBytes,
    required this.activeConnections,
  });

  final int rxBytes;
  final int txBytes;
  final int activeConnections;
}

/// یک نشست باز از دید Clash `/connections` برای ثبت رصد سایت و نرم افزار/اپ.
class CoreActivitySample {
  const CoreActivitySample({
    required this.id,
    this.host = '',
    this.process = '',
    this.downBytes = 0,
    this.upBytes = 0,
  });

  final String id;
  final String host;
  final String process;
  final int downBytes;
  final int upBytes;
}

class _BufferedActivity {
  int hits = 0;
  int down = 0;
  int up = 0;
}

/// بافر سبک در حافظه برای تجمیع سایت ها، برنامه ها و صفحه های باز شده در برنامه.
class ActivityMonitorBuffer {
  ActivityMonitorBuffer();

  static final ActivityMonitorBuffer instance = ActivityMonitorBuffer();

  final Map<String, _BufferedActivity> _pending = <String, _BufferedActivity>{};
  final Map<String, ({int down, int up})> _watermarks =
      <String, ({int down, int up})>{};
  String _currentScreen = '';

  String get currentScreen => _currentScreen;

  void recordScreen(String label) {
    final String clean = label.trim();
    if (clean.isEmpty) return;
    _currentScreen = clean;
    final _BufferedActivity entry =
        _pending.putIfAbsent('screen\x00$clean', () => _BufferedActivity());
    entry.hits += 1;
    _trimOverflow();
  }

  void recordConnections(List<CoreActivitySample> samples) {
    for (final CoreActivitySample sample in samples) {
      final String connId = sample.id.trim();
      int deltaDown = sample.downBytes;
      int deltaUp = sample.upBytes;
      bool isNew = true;

      if (connId.isNotEmpty) {
        final ({int down, int up})? prev = _watermarks[connId];
        if (prev != null) {
          isNew = false;
          deltaDown =
              sample.downBytes >= prev.down ? sample.downBytes - prev.down : 0;
          deltaUp = sample.upBytes >= prev.up ? sample.upBytes - prev.up : 0;
        }
        _watermarks[connId] = (down: sample.downBytes, up: sample.upBytes);
        if (_watermarks.length > 600) {
          final List<String> oldest =
              _watermarks.keys.take(_watermarks.length - 400).toList();
          for (final String k in oldest) {
            _watermarks.remove(k);
          }
        }
      }

      if (sample.host.isNotEmpty) {
        final _BufferedActivity site = _pending.putIfAbsent(
          'site\x00${sample.host}',
          () => _BufferedActivity(),
        );
        if (isNew) site.hits += 1;
        site.down += deltaDown;
        site.up += deltaUp;
      }

      if (sample.process.isNotEmpty) {
        final _BufferedActivity app = _pending.putIfAbsent(
          'app\x00${sample.process}',
          () => _BufferedActivity(),
        );
        if (isNew) app.hits += 1;
        app.down += deltaDown;
        app.up += deltaUp;
      }
    }
    _trimOverflow();
  }

  List<Map<String, dynamic>> snapshotPayload({int maxItems = 50}) {
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final MapEntry<String, _BufferedActivity> item in _pending.entries) {
      if (out.length >= maxItems) break;
      final int sep = item.key.indexOf('\x00');
      if (sep <= 0) continue;
      final String category = item.key.substring(0, sep);
      final String target = item.key.substring(sep + 1);
      final _BufferedActivity v = item.value;
      if (v.hits <= 0 && v.down <= 0 && v.up <= 0) continue;
      out.add(<String, dynamic>{
        'category': category,
        'target': target,
        'hits': v.hits > 0 ? v.hits : 1,
        'down': v.down,
        'up': v.up,
      });
    }
    return out;
  }

  void confirmSent(List<Map<String, dynamic>> sentItems) {
    for (final Map<String, dynamic> item in sentItems) {
      final String cat = '${item['category'] ?? ''}';
      final String target = '${item['target'] ?? ''}';
      final String key = '$cat\x00$target';
      final _BufferedActivity? cur = _pending[key];
      if (cur == null) continue;
      cur.hits -= (item['hits'] as int?) ?? 0;
      cur.down -= (item['down'] as int?) ?? 0;
      cur.up -= (item['up'] as int?) ?? 0;
      if (cur.hits <= 0 && cur.down <= 0 && cur.up <= 0) {
        _pending.remove(key);
      } else {
        if (cur.hits < 0) cur.hits = 0;
        if (cur.down < 0) cur.down = 0;
        if (cur.up < 0) cur.up = 0;
      }
    }
  }

  void _trimOverflow() {
    if (_pending.length <= 160) return;
    final List<String> excess =
        _pending.keys.take(_pending.length - 120).toList();
    for (final String k in excess) {
      _pending.remove(k);
    }
  }

  void clear() {
    _pending.clear();
    _watermarks.clear();
    _currentScreen = '';
  }
}

/// Loopback-only reader for the running core's Clash control port (`127.0.0.1`).
class ClashApi {
  const ClashApi._();

  /// Delays at or above this value represent timeout sentinels in sing-box
  /// (`monitoring.TimeoutDelay = 65535`, `connectivity.maxPing = 65000`).
  static const int maxValidDelayMs = 65000;

  static const Set<String> _nonProxyTags = <String>{
    'direct',
    'bypass',
    'block',
    'direct §hide§',
    'bypass §hide§',
    'direct-fragment §hide§',
  };

  static bool isAliveDelay(int delay) => delay > 0 && delay < maxValidDelayMs;

  static bool _isProxyTag(String tag, Map<String, dynamic> info) {
    if (tag.isEmpty ||
        tag == 'GLOBAL' ||
        _nonProxyTags.contains(tag) ||
        tag.contains('§hide§')) {
      return false;
    }
    final String type = '${info['type'] ?? ''}'.toLowerCase();
    return type != 'direct' && type != 'reject' && type != 'dns';
  }

  /// Pure parser for `GET /proxies` JSON payloads, implementing the exact
  /// `decideConnectivity` semantics of `hiddify-core v5.9.1/v2/hcore/connectivity.go`.
  static CoreProxySnapshot parseProxies(
    Map<String, dynamic> payload, {
    DateTime? since,
  }) {
    final Object? rawMap = payload['proxies'];
    if (rawMap is! Map) {
      return CoreProxySnapshot.offline;
    }
    final Map<String, Map<String, dynamic>> proxies =
        <String, Map<String, dynamic>>{};
    rawMap.forEach((Object? key, Object? value) {
      if (key is String && value is Map) {
        proxies[key] = value.map(
          (Object? k, Object? v) => MapEntry<String, dynamic>('$k', v),
        );
      }
    });
    if (proxies.isEmpty) {
      return const CoreProxySnapshot(
        reachable: true,
        connectivity: CoreConnectivityState.waiting,
      );
    }

    // Small 250ms clock skew allowance while rejecting stale cached histories.
    final DateTime? cutoff =
        since?.toUtc().subtract(const Duration(milliseconds: 250));

    bool isGroup(Map<String, dynamic> entry) => entry['all'] is List;

    Map<String, dynamic>? latestHistory(Map<String, dynamic> entry) {
      final Object? rawHistory = entry['history'];
      if (rawHistory is! List || rawHistory.isEmpty) {
        return null;
      }
      final Object? last = rawHistory.last;
      if (last is! Map) {
        return null;
      }
      return last.map(
        (Object? k, Object? v) => MapEntry<String, dynamic>('$k', v),
      );
    }

    /// Mirrors `connectivity.historyDelay`: returns positive ms when alive in
    /// the current run, `-1` when timed out in this run, or `0` when untested
    /// or loaded from `data/clash.db` (`from_cache == true`).
    int classifyDelay(Map<String, dynamic> entry) {
      final Map<String, dynamic>? last = latestHistory(entry);
      if (last == null) {
        return 0;
      }
      if (last['from_cache'] == true) {
        return 0;
      }
      if (cutoff != null) {
        final String rawTime = '${last['time'] ?? ''}';
        final DateTime? parsed = DateTime.tryParse(rawTime)?.toUtc();
        if (parsed != null && parsed.isBefore(cutoff)) {
          return 0;
        }
      }
      final Object? rawDelay = last['delay'];
      final int delay =
          rawDelay is num ? rawDelay.round() : int.tryParse('$rawDelay') ?? 0;
      if (isAliveDelay(delay)) {
        return delay;
      }
      // Both standard sing-box (`delay: 0`) and hiddify-sing-box
      // (`delay: 65535`) record a history entry only after a completed test;
      // untested outbounds have an empty `history` list (`last == null`).
      return -1;
    }

    CoreExitIpInfo? extractIpInfo(Map<String, dynamic> entry) {
      final Map<String, dynamic>? last = latestHistory(entry);
      if (last == null) return null;
      final Object? rawIpInfo = last['ipinfo'];
      if (rawIpInfo is! Map) return null;
      final String ip = '${rawIpInfo['ip'] ?? ''}'.trim();
      final String cc = '${rawIpInfo['country_code'] ?? ''}'.trim();
      if (ip.isEmpty || cc.toLowerCase() == 'ir') {
        return null;
      }
      final bool ipFromCache =
          last['ipinfo_from_cache'] == true || last['from_cache'] == true;
      if (since != null && ipFromCache) {
        return null;
      }
      final Object? rawAsn = rawIpInfo['asn'];
      final int asn = rawAsn is num ? rawAsn.toInt() : int.tryParse('$rawAsn') ?? 0;
      return CoreExitIpInfo(
        ip: ip,
        countryCode: cc,
        region: '${rawIpInfo['region'] ?? ''}'.trim(),
        city: '${rawIpInfo['city'] ?? ''}'.trim(),
        org: '${rawIpInfo['org'] ?? ''}'.trim(),
        asn: asn,
        fromCache: ipFromCache,
      );
    }

    String resolveLeaf(String startTag) {
      String current = startTag;
      final Set<String> visited = <String>{};
      while (current.isNotEmpty && visited.add(current)) {
        final Map<String, dynamic>? info = proxies[current];
        if (info == null || !isGroup(info)) {
          return current;
        }
        final String next = '${info['now'] ?? ''}';
        if (next.isEmpty) {
          return '';
        }
        current = next;
      }
      return '';
    }

    final Set<String> leafTags = <String>{};
    void collectLeaves(String tag, Set<String> visited) {
      if (tag.isEmpty || !visited.add(tag)) {
        return;
      }
      final Map<String, dynamic>? info = proxies[tag];
      if (info == null) {
        return;
      }
      if (!isGroup(info)) {
        if (_isProxyTag(tag, info)) {
          leafTags.add(tag);
        }
        return;
      }
      for (final dynamic item in info['all'] as List<dynamic>) {
        if (item is String) {
          collectLeaves(item, visited);
        }
      }
    }

    // Match `connectivity.proxiesConnectivity`: inspect `lowest` first when
    // built (multi-proxy profiles), falling back to `select` (1-proxy profiles).
    if (proxies.containsKey('lowest')) {
      collectLeaves('lowest', <String>{});
    }
    if (leafTags.isEmpty && proxies.containsKey('select')) {
      collectLeaves('select', <String>{});
    }
    if (leafTags.isEmpty) {
      for (final String tag in proxies.keys) {
        if (tag != 'GLOBAL') {
          collectLeaves(tag, <String>{});
        }
      }
    }

    final String root = proxies.containsKey('select')
        ? 'select'
        : (proxies.containsKey('lowest') ? 'lowest' : '');
    final String activeTag = root.isNotEmpty
        ? resolveLeaf(root)
        : (leafTags.length == 1 ? leafTags.first : '');
    final int activeState =
        activeTag.isNotEmpty && proxies.containsKey(activeTag)
            ? classifyDelay(proxies[activeTag]!)
            : 0;
    final int activeDelay = activeState > 0 ? activeState : 0;

    final int lowestGroupDelay = proxies.containsKey('lowest')
        ? classifyDelay(proxies['lowest']!)
        : 0;

    int alive = 0;
    int failed = 0;
    int untested = 0;
    String bestTag = '';
    int bestDelay = 0;

    for (final String tag in leafTags) {
      final Map<String, dynamic>? info = proxies[tag];
      if (info == null) {
        continue;
      }
      final int state = classifyDelay(info);
      if (state > 0) {
        alive++;
        if (bestDelay == 0 || state < bestDelay) {
          bestDelay = state;
          bestTag = tag;
        }
      } else if (state < 0) {
        failed++;
      } else {
        untested++;
      }
    }

    // Exact `decideConnectivity` rules from `hiddify-core/v2/hcore/connectivity.go`.
    final CoreConnectivityState connectivity;
    if (lowestGroupDelay > 0 || activeDelay > 0 || alive > 0) {
      connectivity = CoreConnectivityState.started;
    } else if (leafTags.isNotEmpty && untested == 0 && failed >= leafTags.length) {
      connectivity = CoreConnectivityState.noAvailableProxies;
    } else {
      connectivity = CoreConnectivityState.waiting;
    }

    CoreExitIpInfo? exitIpInfo;
    if (activeTag.isNotEmpty && proxies.containsKey(activeTag)) {
      exitIpInfo = extractIpInfo(proxies[activeTag]!);
    }
    if (exitIpInfo == null && bestTag.isNotEmpty && proxies.containsKey(bestTag)) {
      exitIpInfo = extractIpInfo(proxies[bestTag]!);
    }
    if (exitIpInfo == null && alive > 0) {
      for (final String tag in leafTags) {
        final Map<String, dynamic>? info = proxies[tag];
        if (info != null && classifyDelay(info) > 0) {
          exitIpInfo = extractIpInfo(info);
          if (exitIpInfo != null) break;
        }
      }
    }

    return CoreProxySnapshot(
      reachable: true,
      connectivity: connectivity,
      activeTag: activeTag,
      activeDelayMs: activeDelay,
      bestTag: bestTag,
      bestDelayMs: bestDelay,
      aliveCount: alive,
      failedCount: failed,
      untestedCount: untested,
      totalCount: leafTags.length,
      exitIpInfo: exitIpInfo,
    );
  }

  /// Queries `GET /proxies` on loopback.
  static Future<CoreProxySnapshot> status({
    int port = AppConfig.coreClashPort,
    String secret = AppConfig.coreClashSecret,
    Duration timeout = const Duration(milliseconds: 900),
    DateTime? since,
  }) async {
    final Map<String, dynamic>? json = await _getJson(
      path: '/proxies',
      port: port,
      secret: secret,
      timeout: timeout,
    );
    if (json == null) {
      return CoreProxySnapshot.offline;
    }
    return parseProxies(json, since: since);
  }

  /// Triggers an on-demand URL test on [tag] via `GET /proxies/{tag}/delay`.
  ///
  /// Inside the core this updates monitoring history and immediately notifies
  /// `lowest`/`balance` groups, allowing seamless failover without restarting
  /// the engine or dropping the TUN interface.
  static Future<int> testDelay(
    String tag, {
    int port = AppConfig.coreClashPort,
    String secret = AppConfig.coreClashSecret,
    String testUrl = 'http://connectivitycheck.gstatic.com/generate_204',
    Duration timeout = const Duration(milliseconds: 4000),
  }) async {
    if (tag.trim().isEmpty) {
      return -1;
    }
    final int ms = timeout.inMilliseconds.clamp(500, 15000);
    final String encodedTag = Uri.encodeComponent(tag);
    final String encodedUrl = Uri.encodeQueryComponent(testUrl);
    final Map<String, dynamic>? json = await _getJson(
      path: '/proxies/$encodedTag/delay?url=$encodedUrl&timeout=$ms',
      port: port,
      secret: secret,
      timeout: timeout + const Duration(milliseconds: 800),
    );
    if (json == null) {
      return -1;
    }
    final Object? raw = json['delay'];
    final int delay = raw is num ? raw.round() : int.tryParse('$raw') ?? -1;
    return isAliveDelay(delay) ? delay : -1;
  }

  /// Reads cumulative session traffic from `GET /connections` (used in system
  /// proxy mode where no virtual TUN adapter exists).
  static Future<CoreTrafficTotals?> trafficTotals({
    int port = AppConfig.coreClashPort,
    String secret = AppConfig.coreClashSecret,
    Duration timeout = const Duration(milliseconds: 900),
  }) async {
    final Map<String, dynamic>? json = await _getJson(
      path: '/connections',
      port: port,
      secret: secret,
      timeout: timeout,
    );
    if (json == null) {
      return null;
    }
    final Object? down = json['downloadTotal'];
    final Object? up = json['uploadTotal'];
    if (down is! num && up is! num) {
      return null;
    }
    final Object? conns = json['connections'];
    return CoreTrafficTotals(
      rxBytes: down is num ? down.toInt() : 0,
      txBytes: up is num ? up.toInt() : 0,
      activeConnections: conns is List ? conns.length : 0,
    );
  }

  /// استخراج لیست سایت ها و نرم افزارها/اپ های باز شده از خروجی `GET /connections`.
  static List<CoreActivitySample> parseConnections(Map<String, dynamic> json) {
    final Object? rawList = json['connections'];
    if (rawList is! List) return const <CoreActivitySample>[];

    final List<CoreActivitySample> out = <CoreActivitySample>[];
    for (final Object? entry in rawList) {
      if (entry is! Map) continue;
      final Object? metaRaw = entry['metadata'];
      if (metaRaw is! Map) continue;

      final String id = '${entry['id'] ?? ''}'.trim();
      final String host = _cleanObservedHost(
        '${metaRaw['host'] ?? metaRaw['sniffHost'] ?? ''}',
      );
      final String process = _cleanObservedProcess(
        '${metaRaw['processPath'] ?? metaRaw['process'] ?? metaRaw['packageName'] ?? metaRaw['user'] ?? ''}',
      );
      if (host.isEmpty && process.isEmpty) continue;

      final Object? downRaw = entry['download'];
      final Object? upRaw = entry['upload'];
      out.add(CoreActivitySample(
        id: id,
        host: host,
        process: process,
        downBytes: downRaw is num ? downRaw.toInt().clamp(0, 1 << 60) : 0,
        upBytes: upRaw is num ? upRaw.toInt().clamp(0, 1 << 60) : 0,
      ));
    }
    return out;
  }

  static Future<List<CoreActivitySample>> activeConnections({
    int port = AppConfig.coreClashPort,
    String secret = AppConfig.coreClashSecret,
    Duration timeout = const Duration(milliseconds: 800),
  }) async {
    final Map<String, dynamic>? json = await _getJson(
      path: '/connections',
      port: port,
      secret: secret,
      timeout: timeout,
    );
    if (json == null) return const <CoreActivitySample>[];
    return parseConnections(json);
  }

  static String _cleanObservedHost(String raw) {
    String h = raw.trim().toLowerCase();
    if (h.isEmpty) return '';
    h = h.replaceAll(RegExp(r':\d+$'), '').replaceAll(RegExp(r'^\.+|\.+$'), '');
    if (h.isEmpty ||
        h == 'localhost' ||
        h.endsWith('.local') ||
        h.endsWith('.arpa') ||
        h == '127.0.0.1' ||
        h == '::1' ||
        h.startsWith('10.') ||
        h.startsWith('192.168.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(h)) {
      return '';
    }
    if (!h.contains('.')) return '';
    return h.length > 180 ? h.substring(0, 180) : h;
  }

  static String _cleanObservedProcess(String raw) {
    String p = raw.trim();
    if (p.isEmpty) return '';
    if (p.contains('\\')) p = p.split('\\').last;
    if (p.contains('/')) p = p.split('/').last;
    p = p.trim();
    final String lower = p.toLowerCase();
    if (lower.isEmpty ||
        lower == 'sing-box' ||
        lower.startsWith('sing-box.') ||
        lower == 'umbrella' ||
        lower.startsWith('umbrella.') ||
        lower.startsWith('umbrellacore') ||
        lower.startsWith('umbrella_vpn') ||
        lower.startsWith('umbrella-vpn') ||
        lower == 'ir.umbrella.vpn') {
      return '';
    }
    return p.length > 120 ? p.substring(0, 120) : p;
  }

  /// انتخاب خروجی فعال یک گروه (`selector`) در رابط کلش هسته و بستن اتصال های
  /// قبلی روی مسیر کهنه تا تغییر `selectionMode` در لحظه اثر کند.
  static Future<bool> selectOutbound(
    String groupTag,
    String targetTag, {
    int port = AppConfig.coreClashPort,
    String secret = AppConfig.coreClashSecret,
    Duration timeout = const Duration(milliseconds: 1200),
  }) async {
    if (port <= 0 ||
        port > 65535 ||
        groupTag.trim().isEmpty ||
        targetTag.trim().isEmpty) {
      return false;
    }
    final HttpClient client = HttpClient()..connectionTimeout = timeout;
    client.findProxy = (Uri _) => 'DIRECT';
    try {
      final String encoded = Uri.encodeComponent(groupTag);
      final Uri uri = Uri.parse('http://127.0.0.1:$port/proxies/$encoded');
      final HttpClientRequest request =
          await client.putUrl(uri).timeout(timeout);
      request.followRedirects = false;
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(<String, String>{'name': targetTag})));
      final HttpClientResponse response =
          await request.close().timeout(timeout);
      await response.drain<void>().timeout(
            const Duration(milliseconds: 300),
            onTimeout: () {},
          );
      return response.statusCode == 204 || response.statusCode == 200;
    } on Exception {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// بستن تمام اتصال های باز در هسته تا قوانین تازه کنترل محتوا یا مسیریابی روی
  /// نشست های از قبل باز هم بی درنگ اعمال شوند.
  static Future<bool> closeAllConnections({
    int port = AppConfig.coreClashPort,
    String secret = AppConfig.coreClashSecret,
    Duration timeout = const Duration(milliseconds: 1000),
  }) async {
    if (port <= 0 || port > 65535) {
      return false;
    }
    final HttpClient client = HttpClient()..connectionTimeout = timeout;
    client.findProxy = (Uri _) => 'DIRECT';
    try {
      final Uri uri = Uri.parse('http://127.0.0.1:$port/connections');
      final HttpClientRequest request =
          await client.deleteUrl(uri).timeout(timeout);
      request.followRedirects = false;
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      final HttpClientResponse response =
          await request.close().timeout(timeout);
      await response.drain<void>().timeout(
            const Duration(milliseconds: 300),
            onTimeout: () {},
          );
      return response.statusCode >= 200 && response.statusCode < 300;
    } on Exception {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>?> _getJson({
    required String path,
    required int port,
    required String secret,
    required Duration timeout,
  }) async {
    if (port <= 0 || port > 65535) {
      return null;
    }
    final HttpClient client = HttpClient()..connectionTimeout = timeout;
    client.findProxy = (Uri _) => 'DIRECT';
    try {
      final Uri uri = Uri.parse('http://127.0.0.1:$port$path');
      final HttpClientRequest request =
          await client.getUrl(uri).timeout(timeout);
      request.followRedirects = false;
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final HttpClientResponse response =
          await request.close().timeout(timeout);
      if (response.statusCode != 200) {
        await response.drain<void>().timeout(
              const Duration(milliseconds: 300),
              onTimeout: () {},
            );
        return null;
      }
      final List<int> bytes = <int>[];
      await for (final List<int> chunk in response.timeout(timeout)) {
        bytes.addAll(chunk);
        // Bound local control responses to 4 MB even for large subscriptions.
        if (bytes.length > 4 * 1024 * 1024) {
          return null;
        }
      }
      final Object? decoded = jsonDecode(
        utf8.decode(bytes, allowMalformed: true),
      );
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (Object? k, Object? v) => MapEntry<String, dynamic>('$k', v),
        );
      }
      return null;
    } on Exception {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
