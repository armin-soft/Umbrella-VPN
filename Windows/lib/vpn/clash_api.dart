import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/app_config.dart';

/// Snapshot of the running core's outbound monitoring state via loopback Clash API.
///
/// Used strictly to coordinate startup timing, live delay display, and seamless
/// in-core failover — never as a substitute for TLS-verified tunnel probes.
class CoreProxySnapshot {
  const CoreProxySnapshot({
    required this.reachable,
    this.activeTag = '',
    this.activeDelayMs = 0,
    this.bestTag = '',
    this.bestDelayMs = 0,
    this.aliveCount = 0,
    this.failedCount = 0,
    this.untestedCount = 0,
    this.totalCount = 0,
  });

  static const CoreProxySnapshot offline = CoreProxySnapshot(reachable: false);

  final bool reachable;
  final String activeTag;
  final int activeDelayMs;
  final String bestTag;
  final int bestDelayMs;
  final int aliveCount;
  final int failedCount;
  final int untestedCount;
  final int totalCount;

  /// True once the running core has measured at least one responsive outbound
  /// in the active session and can route through it immediately.
  bool get hasLiveSelection => activeDelayMs > 0 || aliveCount > 0;

  /// True only when every single outbound in the pool was freshly tested in the
  /// current session and none of them answered.
  bool get allTestedAndDead =>
      reachable &&
      totalCount > 0 &&
      aliveCount == 0 &&
      untestedCount == 0 &&
      failedCount >= totalCount;
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

/// Loopback-only reader for the running core's Clash control port (`127.0.0.1`).
class ClashApi {
  const ClashApi._();

  /// Delays at or above this value represent timeout sentinels in sing-box
  /// (`monitoring.TimeoutDelay = 65535`).
  static const int maxValidDelayMs = 65000;

  static bool isAliveDelay(int delay) => delay > 0 && delay < maxValidDelayMs;

  /// Pure parser for `GET /proxies` JSON payloads.
  ///
  /// When [since] is provided, only history entries recorded at or after
  /// `since - 1s` count as current-session results (older entries come from
  /// `data/clash.db` and stay treated as untested until re-measured).
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
      return const CoreProxySnapshot(reachable: true);
    }

    final DateTime? cutoff = since?.toUtc().subtract(const Duration(seconds: 1));

    bool isGroup(Map<String, dynamic> entry) => entry['all'] is List;

    /// Returns positive ms when alive, `-1` when timed out in this session,
    /// or `0` when not yet tested in this session.
    int classifyDelay(Map<String, dynamic> entry) {
      final Object? rawHistory = entry['history'];
      if (rawHistory is! List || rawHistory.isEmpty) {
        return 0;
      }
      final Object? last = rawHistory.last;
      if (last is! Map) {
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
      final int delay = rawDelay is num
          ? rawDelay.round()
          : int.tryParse('$rawDelay') ?? 0;
      if (isAliveDelay(delay)) {
        return delay;
      }
      return -1;
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
        final String type = '${info['type'] ?? ''}'.toLowerCase();
        if (type != 'direct' && type != 'reject' && type != 'dns') {
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

    if (proxies.containsKey('select')) {
      collectLeaves('select', <String>{});
    } else if (proxies.containsKey('lowest')) {
      collectLeaves('lowest', <String>{});
    } else {
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

    return CoreProxySnapshot(
      reachable: true,
      activeTag: activeTag,
      activeDelayMs: activeDelay,
      bestTag: bestTag,
      bestDelayMs: bestDelay,
      aliveCount: alive,
      failedCount: failed,
      untestedCount: untested,
      totalCount: leafTags.length,
    );
  }

  /// Queries `GET /proxies` on loopback.
  static Future<CoreProxySnapshot> status({
    int port = AppConfig.coreClashPort,
    String secret = AppConfig.coreClashSecret,
    Duration timeout = const Duration(milliseconds: 1200),
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

  /// Triggers an on-demand HTTPS URL test on [tag] via `GET /proxies/{tag}/delay`.
  ///
  /// Inside the core this updates monitoring history and immediately notifies
  /// `lowest`/`balance` groups, allowing seamless failover without restarting
  /// the engine or dropping the TUN interface.
  static Future<int> testDelay(
    String tag, {
    int port = AppConfig.coreClashPort,
    String secret = AppConfig.coreClashSecret,
    String testUrl = 'https://www.gstatic.com/generate_204',
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
