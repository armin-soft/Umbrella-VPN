import 'dart:io';

import '../core/malicious_link_guard.dart';
import '../models/advanced_network.dart';
import 'umbrella_core.dart';

/// Finalize the pinned core's `build` output for `srun`, matching official
/// Hiddify (`hiddify-app` + `hiddify-core v5.9.15`) startup semantics AND
/// patching upstream `builder.go` / `outbound.go` gaps so every setting in
/// Umbrella Windows takes real effect on the live tunnel:
///
/// * Leaf proxy outbounds use `lazy: true` (`adapter/outbound/h_lazy.go`) so
///   box startup instantiates zero transports upfront and unloads idle ones.
/// * Standard subscriptions (`<= autoKeepTopThreshold` proxies) run with
///   `keep_top` disabled (matching Hiddify's default `keep-top: -1`), allowing
///   `cycleOrder` to probe every proxy immediately without batch-stage stalls.
/// * Very large subscriptions (`> autoKeepTopThreshold` proxies) automatically
///   enable quick staged `keep_top` to keep memory and socket usage bounded.
/// * Enables `route.find_process = true` whenever per-app process rules exist
///   (`builder.go` hardcodes `FindProcess: false`).
/// * Preserves `bypass-lan` (`ip_is_private -> direct §hide§`) when custom
///   `route-rule` entries (content control or per-app routes) are present.
/// * Wires `resolve-destination` (`{"action": "resolve"}` route rule) which is
///   commented out in upstream `builder.go`.
/// * Wires `tls-tricks.enable-padding` + `padding-size` with a fixed uTLS
///   ClientHello spec (disabled behind `if false` in upstream `outbound.go`).
/// * Ensures explicit `ttl` on `sticky-sessions` load-balancer outbounds.
class RuntimeConfig {
  const RuntimeConfig._();
  static const Set<String> lazyTypes = <String>{
    'vless', 'vmess', 'trojan', 'shadowsocks', 'socks', 'http', 'hysteria',
    'hysteria2', 'tuic', 'anytls', 'shadowtls', 'ssh', 'naive', 'mieru',
    'snell', 'trusttunnel', 'sudoku',
  };

  // Client endpoints supported by upstream 5.9.15's LazyProxyTags.
  static const Set<String> lazyEndpointTypes = <String>{
    'wireguard', 'awg', 'openvpn-client', 'openconnect', 'masque-client', 'warp',
  };

  static bool _isChainHop(String tag) {
    final String display = tag.split('§').first.trim();
    return display.startsWith('🔒 Extra Security') ||
        display.startsWith('🔓 Unblocker');
  }

  static const Set<String> _tlsTrickOutboundTypes = <String>{
    'vless', 'vmess', 'trojan',
  };

  static const Set<String> _tlsTrickTransports = <String>{
    'ws', 'grpc', 'httpupgrade', 'xhttp', 'http',
  };

  /// Fixed uTLS ClientHello fingerprints supported by `utls.UTLSIdToSpec` for
  /// ClientHello extension padding (`common/tls/utls_client.go:326`).
  static const Set<String> _fixedUtlsFingerprints = <String>{
    'chrome', 'firefox', 'safari', 'ios', 'android', 'edge', '360', 'qq',
  };

  static const Set<String> _validDomainStrategies = <String>{
    'prefer_ipv4', 'prefer_ipv6', 'ipv4_only', 'ipv6_only',
  };

  static const String directOutboundTag = 'direct §hide§';
  static const String blockPageOutboundTag = 'umbrella-block-page';

  /// Profiles up to this size behave identically to Hiddify's default
  /// `keep-top = -1` (immediate full-pool `cycleOrder` without batch gating).
  static const int autoKeepTopThreshold = 128;
  static const int keepTopCount = 8;
  static const int keepTopBatch = 32;
  static const int monitoringWorkers = 16;

  static void finalize(
    Map<String, dynamic> config, {
    required Set<String> profileTags,
    int? clashApiPort,
    Map<String, dynamic>? coreSettings,
    int stickyMinutes = 15,
    int? blockPagePort,
    bool preserveLogOutput = false,
    Map<String, String>? localRuleSetPaths,
    String? localDataDir,
  }) {
    if (config['outbounds'] is! List || config['experimental'] is! Map) {
      throw const FormatException(
        'Built runtime has no experimental/outbounds configuration',
      );
    }
    final List<dynamic> outbounds = config['outbounds'] as List<dynamic>;
    final Map<String, dynamic> experimental =
        config['experimental'] as Map<String, dynamic>;
    final Object? rawMonitoring = experimental['monitoring'];
    if (!preserveLogOutput && rawMonitoring is! Map) {
      throw const FormatException(
        'Built runtime has no outbound monitoring configuration',
      );
    }
    final Map<String, dynamic>? monitoring =
        rawMonitoring is Map<String, dynamic> ? rawMonitoring : null;
    if (monitoring != null) {
      monitoring['workers'] = monitoringWorkers;
      monitoring['debounce_window'] = '200ms';
      monitoring['url_test_timeout'] = '4s';
    }

    // No dashboard download on the connection path. Clash API remains loopback.
    final Map<String, dynamic>? clash =
        experimental['clash_api'] as Map<String, dynamic>?;
    clash?.remove('external_ui');
    clash?.remove('external_ui_download_url');
    if (clash != null && clashApiPort != null) {
      if (clashApiPort <= 0) {
        experimental.remove('clash_api');
      } else {
        clash['external_controller'] = '127.0.0.1:$clashApiPort';
      }
    }

    // The controller captures stdout; do not let two writers truncate one log.
    if (!preserveLogOutput) {
      (config['log'] as Map<String, dynamic>?)?.remove('output');
    }

    // ارتقای خودکار فیلدهای منسوخ شده `sing-box 1.14+` که هسته `v5.9.11` هنوز
    // به شکل قدیمی تولید می کند (`download_detour` روی `rule_set`، `store_rdrc`،
    // `independent_cache`، `rule_set_ip_cidr_accept_empty` و `strategy` روی
    // قوانین DNS) تا اجرای `srun` روی هیچ تنظیمی با خطای `FATAL` متوقف نشود.
    _migrateSingBox114Deprecations(config, experimental);
    _configureDirectWireGuardResolver(config, profileTags, coreSettings);

    final _ResolvedTlsPadding? tlsPadding = _extractTlsPadding(coreSettings);
    final _ResolvedTlsFragment? tlsFragment = _extractTlsFragment(coreSettings);
    final bool mixedSniWanted = _extractMixedSniCase(coreSettings);
    final int clampedSticky = stickyMinutes.clamp(1, 1440);

    int lazyCount = 0;
    final List<Map<String, dynamic>> extra = <Map<String, dynamic>>[];
    for (final dynamic value in outbounds) {
      if (value is! Map<String, dynamic>) continue;
      final Map<String, dynamic> outbound = value;
      final String type = '${outbound['type'] ?? ''}';
      final String tag = '${outbound['tag'] ?? ''}';

      if (type == 'balancer' &&
          outbound['strategy'] == 'sticky-sessions' &&
          outbound['ttl'] == null) {
        outbound['ttl'] = '${clampedSticky}m';
      }

      if (profileTags.contains(tag) && !_isChainHop(tag) && lazyTypes.contains(type)) {
        outbound['lazy'] = true;
        lazyCount++;
      }

      if (profileTags.contains(tag) &&
          (tlsPadding != null || tlsFragment != null || mixedSniWanted)) {
        _patchOutboundTlsTricks(
          outbound,
          padding: tlsPadding,
          fragment: tlsFragment,
          mixedSniCase: mixedSniWanted,
        );
      }

      final dynamic transport = outbound['transport'];
      if (transport is! Map || transport['type'] != 'xhttp') continue;
      final dynamic download = transport['download'];
      if (download is! Map ||
          download['server'] is! String ||
          InternetAddress.tryParse(download['server'] as String) != null ||
          (download['server'] as String).isEmpty ||
          '${download['detour'] ?? ''}'.isNotEmpty ||
          '${outbound['detour'] ?? ''}'.isNotEmpty ||
          InternetAddress.tryParse('${outbound['server']}') == null) {
        continue;
      }
      // XHTTP reuses the upload dialer for its separate download endpoint.
      // For an IP upload that dialer has NO resolver, hence the immediate
      // "domain not resolved" (not a DNS timeout). A direct outbound always
      // constructs a resolving dialer. Preserve endpoint/TLS/Host/path and
      // the upload's dial options; never override an explicit/chain detour.
      String dlTag = 'umbrella-xhttp-download-${extra.length}';
      while (outbounds.any((dynamic item) => item['tag'] == dlTag) ||
          extra.any((Map<String, dynamic> item) => item['tag'] == dlTag)) {
        dlTag = '$dlTag-';
      }
      final Map<String, dynamic> resolver = <String, dynamic>{
        'type': 'direct',
        'tag': dlTag,
      };
      for (final String key in <String>[
        'bind_interface', 'inet4_bind_address', 'inet6_bind_address',
        'bind_address_no_port', 'protect_path', 'disable_tcp_keep_alive',
        'tcp_keep_alive', 'tcp_keep_alive_interval', 'routing_mark',
        'reuse_addr', 'connect_timeout', 'tcp_fast_open', 'tcp_multi_path',
        'udp_fragment', 'domain_resolver', 'domain_strategy',
        'network_strategy', 'network_type', 'fallback_network_type',
        'fallback_delay', 'netns', 'tls_fragment', 'finalmask',
      ]) {
        if (outbound.containsKey(key)) resolver[key] = outbound[key];
      }
      download['detour'] = dlTag;
      extra.add(resolver);
    }

    final List<Map<String, dynamic>> lazyEndpoints = <Map<String, dynamic>>[];
    final dynamic rawEndpoints = config['endpoints'];
    if (rawEndpoints is List) {
      for (final dynamic item in rawEndpoints) {
        if (item is! Map<String, dynamic>) continue;
        final String type = '${item['type'] ?? ''}';
        final String tag = '${item['tag'] ?? ''}';
        if (!profileTags.contains(tag) || _isChainHop(tag) || !lazyEndpointTypes.contains(type)) continue;
        // Listening WireGuard/AWG/WARP endpoints serve peers and must not sleep.
        final dynamic listenPort = item['listen_port'];
        if (const <String>{'wireguard', 'awg', 'warp'}.contains(type) &&
            listenPort != null && listenPort != 0) continue;
        lazyEndpoints.add(item);
      }
    }
    if (lazyCount + lazyEndpoints.length > autoKeepTopThreshold) {
      for (final Map<String, dynamic> endpoint in lazyEndpoints) {
        endpoint['lazy'] = true;
      }
      if (monitoring != null) {
        monitoring['keep_top'] = <String, dynamic>{
          'count': keepTopCount,
          'batch': keepTopBatch,
          'quick': true,
          'refresh': '1h',
        };
      }
    } else {
      monitoring?.remove('keep_top');
    }
    // Download detours are looked up when a transport is constructed.
    outbounds.insertAll(0, extra);

    // Patch route configuration (process matching, LAN bypass, destination resolve).
    _finalizeRoute(config, outbounds, coreSettings);
    final Map<String, String> localRuleSets =
        _discoverLocalRuleSets(localRuleSetPaths, localDataDir);
    _ensureRequestedLocalFilterRuleSets(
      config,
      coreSettings,
      localPaths: localRuleSets,
    );
    _configureContentBlockRouting(
      config,
      outbounds,
      blockPagePort: blockPagePort,
    );
    _configureOfflineIranBypass(
      config,
      outbounds,
      coreSettings,
      localRuleSetPaths: localRuleSetPaths,
      localDataDir: localDataDir,
    );
  }

  /// A domain-named WireGuard peer must be resolved before the tunnel can
  /// carry the remote DNS traffic. Without an explicit resolver, the core can
  /// route that lookup to dns-remote-group via the very endpoint being opened.
  /// Use the existing direct DNS group only for our own direct profile. Never
  /// override a custom resolver or bypass a configured chain/detour.
  static void _configureDirectWireGuardResolver(
    Map<String, dynamic> config,
    Set<String> profileTags,
    Map<String, dynamic>? coreSettings,
  ) {
    final String chain = '${coreSettings?['chain-status'] ?? 'off'}';
    if (chain != 'off') return;
    final dynamic dns = config['dns'];
    final dynamic servers = dns is Map ? dns['servers'] : null;
    if (servers is! List || !servers.any((dynamic entry) =>
        entry is Map && entry['tag'] == 'dns-direct-group')) return;
    final dynamic endpoints = config['endpoints'];
    if (endpoints is! List) return;
    for (final dynamic item in endpoints) {
      if (item is! Map<String, dynamic> ||
          (item['type'] != 'wireguard' && item['type'] != 'awg') ||
          item['tag'] != 'umbrella-direct-profile' ||
          !profileTags.contains(item['tag']) ||
          '${item['detour'] ?? ''}'.isNotEmpty ||
          item['domain_resolver'] != null) continue;
      final dynamic peers = item['peers'];
      if (peers is! List || !peers.any((dynamic peer) {
        if (peer is! Map) return false;
        final String host = '${peer['address'] ?? ''}'.trim();
        return host.isNotEmpty && InternetAddress.tryParse(host) == null;
      })) continue;
      item['domain_resolver'] = <String, dynamic>{'server': 'dns-direct-group'};
    }
  }

  static void _finalizeRoute(
    Map<String, dynamic> config,
    List<dynamic> outbounds,
    Map<String, dynamic>? coreSettings,
  ) {
    final dynamic rawRoute = config['route'];
    if (rawRoute is! Map<String, dynamic>) {
      return;
    }
    final dynamic rawRules = rawRoute['rules'];
    if (rawRules is! List<dynamic>) {
      return;
    }

    // 1. Enable socket-to-process lookup whenever any rule matches a process or
    //    when Clash API is active so opened applications/sites can be observed.
    final bool needsFindProcess = rawRules.any((dynamic item) {
      if (item is! Map) return false;
      return _nonEmptyRuleField(item['process_name']) ||
          _nonEmptyRuleField(item['process_path']) ||
          _nonEmptyRuleField(item['process_path_regex']) ||
          _nonEmptyRuleField(item['package_name']);
    });
    final bool hasClashApi = config['experimental'] is Map &&
        (config['experimental'] as Map<dynamic, dynamic>)['clash_api'] is Map;
    if (needsFindProcess || hasClashApi) {
      rawRoute['find_process'] = true;
    }

    // 2. Preserve `bypass-lan` when `route-rule` suppressed upstream BypassLAN.
    final bool bypassLan = coreSettings?['bypass-lan'] == true;
    if (bypassLan) {
      final bool hasPrivateBypass = rawRules.any(
        (dynamic item) => item is Map && item['ip_is_private'] == true,
      );
      final String? directTag = _findDirectOutboundTag(outbounds);
      if (!hasPrivateBypass && directTag != null) {
        final int insertAt = _bypassLanInsertIndex(rawRules, directTag);
        rawRules.insert(insertAt, <String, dynamic>{
          'ip_is_private': true,
          'outbound': directTag,
        });
      }
    }

    // 3. Enforce `resolve-destination` (commented out in upstream builder.go).
    final bool resolveDestination = coreSettings?['resolve-destination'] == true;
    if (resolveDestination) {
      final bool alreadyHasResolve = rawRules.any(
        (dynamic item) =>
            item is Map &&
            item['action'] == 'resolve' &&
            item.keys.every(
              (Object? k) =>
                  k == 'action' || k == 'strategy' || k == 'server',
            ),
      );
      if (!alreadyHasResolve) {
        final String? strategy = _effectiveResolveStrategy(coreSettings);
        final Map<String, dynamic> resolveRule = <String, dynamic>{
          'action': 'resolve',
          if (strategy != null) 'strategy': strategy,
        };
        final int insertAt = _resolveInsertIndex(rawRules);
        rawRules.insert(insertAt, resolveRule);
      }
    }
  }

  /// Inserts `ip_is_private -> direct` right before regional direct rules (and
  /// after `sniff`, `hijack-dns`, content-filter blocks, and per-app rules).
  static int _bypassLanInsertIndex(List<dynamic> rules, String directTag) {
    for (int i = 0; i < rules.length; i++) {
      final dynamic item = rules[i];
      if (item is! Map) continue;
      if (item['outbound'] == directTag &&
          !_nonEmptyRuleField(item['process_name']) &&
          !_nonEmptyRuleField(item['process_path']) &&
          (_nonEmptyRuleField(item['rule_set']) ||
              _nonEmptyRuleField(item['domain_suffix']))) {
        return i;
      }
    }
    // Otherwise place before protocol=quic reject or at the end of route rules.
    for (int i = rules.length - 1; i >= 0; i--) {
      final dynamic item = rules[i];
      if (item is Map &&
          item['action'] == 'reject' &&
          _containsString(item['protocol'], 'quic')) {
        return i;
      }
    }
    return rules.length;
  }

  /// Inserts `{"action": "resolve"}` after `sniff`, `hijack-dns`, DNS-inbound
  /// rules, and domain/process-level reject rules so blocked sites drop with
  /// zero DNS traffic, while all allowed traffic has its destination resolved
  /// before IP rules (`ip_is_private`, `geoip-*`) and outbound dialing.
  static int _resolveInsertIndex(List<dynamic> rules) {
    int index = 0;
    while (index < rules.length) {
      final dynamic item = rules[index];
      if (item is! Map) break;
      final String action = '${item['action'] ?? ''}';
      if (action == 'sniff' || action == 'hijack-dns') {
        index++;
        continue;
      }
      if (_containsString(item['protocol'], 'dns') ||
          item['port'] == 53 ||
          _containsInt(item['port'], 53)) {
        index++;
        continue;
      }
      if ((action == 'reject' ||
              ((action == 'route' || action.isEmpty) &&
                  item['outbound'] == blockPageOutboundTag)) &&
          !_nonEmptyRuleField(item['ip_cidr']) &&
          item['ip_is_private'] != true &&
          !_containsString(item['protocol'], 'quic')) {
        index++;
        continue;
      }
      break;
    }
    return index;
  }

  static void _configureContentBlockRouting(
    Map<String, dynamic> config,
    List<dynamic> outbounds, {
    int? blockPagePort,
  }) {
    final bool hasBlockPage =
        blockPagePort != null && blockPagePort > 0 && blockPagePort <= 65535;
    if (hasBlockPage) {
      final bool hasBlockPageOutbound = outbounds.any(
        (dynamic item) => item is Map && item['tag'] == blockPageOutboundTag,
      );
      if (!hasBlockPageOutbound) {
        outbounds.add(<String, dynamic>{
          'type': 'http',
          'tag': blockPageOutboundTag,
          'server': '127.0.0.1',
          'server_port': blockPagePort,
        });
      }
    }

    final Object? rawRoute = config['route'];
    if (rawRoute is Map<String, dynamic> && rawRoute['rules'] is List) {
      final List<dynamic> routeRules = rawRoute['rules'] as List<dynamic>;
      final List<dynamic> rewrittenRules = <dynamic>[];
      for (final dynamic item in routeRules) {
        if (item is! Map<String, dynamic>) {
          rewrittenRules.add(item);
          continue;
        }
        final bool isBlockRule =
            item['action'] == 'reject' || item['outbound'] == 'block';
        if (isBlockRule && _isPrimaryContentBlockRule(item)) {
          rewrittenRules.addAll(
            _expandOrBlockRule(item, routeToBlockPage: hasBlockPage),
          );
        } else if (isBlockRule && _isDomainLevelBlockRule(item)) {
          rewrittenRules.addAll(
            _expandOrBlockRule(item, routeToBlockPage: false),
          );
        } else {
          rewrittenRules.add(item);
        }
      }

      final bool hasTrojanRule = rewrittenRules.any((dynamic item) {
        if (item is! Map) return false;
        if (item['outbound'] != blockPageOutboundTag) return false;
        return _containsString(item['domain_suffix'], 'grabify.link');
      });

      int lastPreRouteIdx = -1;
      for (int i = 0; i < rewrittenRules.length; i++) {
        final dynamic item = rewrittenRules[i];
        if (item is Map && _isPreRouteRule(item)) {
          lastPreRouteIdx = i;
        }
      }

      final List<dynamic> prefix = <dynamic>[];
      final List<dynamic> promotedBlocks = <dynamic>[];
      final List<dynamic> suffix = <dynamic>[];

      if (hasBlockPage && !hasTrojanRule) {
        promotedBlocks.addAll(<Map<String, dynamic>>[
          <String, dynamic>{
            'domain_suffix':
                MaliciousLinkGuard.knownMaliciousDomains.toList(growable: false),
            'action': 'route',
            'outbound': blockPageOutboundTag,
          },
          <String, dynamic>{
            'domain_keyword': MaliciousLinkGuard.phishingPhrases,
            'action': 'route',
            'outbound': blockPageOutboundTag,
          },
        ]);
      }

      for (int i = 0; i < rewrittenRules.length; i++) {
        final dynamic item = rewrittenRules[i];
        if (i <= lastPreRouteIdx) {
          prefix.add(item);
        } else if (item is Map && _isDomainLevelBlockRule(item)) {
          promotedBlocks.add(item);
        } else {
          suffix.add(item);
        }
      }

      rawRoute['rules'] = <dynamic>[
        ...prefix,
        ...promotedBlocks,
        ...suffix,
      ];
    }

    // در حالت TUN با صفحه مسدودی فعال، قوانین DNS مربوط به دسته های صفحه دار
    // (غیر از تبلیغات) را اجازه می دهیم به لایه route برسند تا مرورگر به جای
    // خطای DNS به صفحه مدرن آمبرلا هدایت شود. قوانین تبلیغات (ads) همچنان در
    // DNS مسدود می مانند و قوانین چندفیلدی DNS نیز به قواعد OR مستقل شکسته می شوند.
    final Object? rawDns = config['dns'];
    if (rawDns is Map<String, dynamic> && rawDns['rules'] is List) {
      final List<dynamic> dnsRules = rawDns['rules'] as List<dynamic>;
      final List<dynamic> rewrittenDns = <dynamic>[];
      for (final dynamic item in dnsRules) {
        if (item is! Map<String, dynamic>) {
          rewrittenDns.add(item);
          continue;
        }
        final bool isRejectDns = item['action'] == 'reject' ||
            item['server'] == 'dns-block' ||
            item['outbound'] == 'block';
        if (!isRejectDns) {
          rewrittenDns.add(item);
          continue;
        }
        if (hasBlockPage && _isPrimaryContentBlockRule(item)) {
          continue;
        }
        rewrittenDns.addAll(_expandDnsBlockRule(item));
      }
      rawDns['rules'] = rewrittenDns;
    }
  }

  static List<Map<String, dynamic>> _expandDnsBlockRule(
    Map<String, dynamic> source,
  ) {
    const List<String> matchKeys = <String>[
      'domain_suffix',
      'domain',
      'domain_keyword',
      'rule_set',
    ];
    final List<String> presentKeys = matchKeys
        .where((String k) => _nonEmptyRuleField(source[k]))
        .toList();
    if (presentKeys.contains('domain_suffix') &&
        presentKeys.contains('domain')) {
      presentKeys.remove('domain');
    }
    if (presentKeys.length <= 1) {
      final Map<String, dynamic> single = Map<String, dynamic>.from(source);
      if (!presentKeys.contains('domain') &&
          _nonEmptyRuleField(source['domain']) &&
          _nonEmptyRuleField(source['domain_suffix'])) {
        single.remove('domain');
      }
      return <Map<String, dynamic>>[single];
    }
    final Map<String, dynamic> base = Map<String, dynamic>.from(source)
      ..remove('domain')
      ..remove('domain_suffix')
      ..remove('domain_keyword')
      ..remove('rule_set');
    return presentKeys
        .map(
          (String key) => <String, dynamic>{
            ...base,
            key: source[key],
          },
        )
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> _expandOrBlockRule(
    Map<String, dynamic> source, {
    required bool routeToBlockPage,
  }) {
    const List<String> matchKeys = <String>[
      'domain_suffix',
      'domain',
      'domain_keyword',
      'rule_set',
    ];
    final List<String> presentKeys = matchKeys
        .where((String k) => _nonEmptyRuleField(source[k]))
        .toList();
    if (presentKeys.contains('domain_suffix') &&
        presentKeys.contains('domain')) {
      presentKeys.remove('domain');
    }

    void applyTarget(Map<String, dynamic> rule) {
      if (routeToBlockPage) {
        rule.remove('method');
        rule.remove('no_drop');
        rule['action'] = 'route';
        rule['outbound'] = blockPageOutboundTag;
      } else {
        rule.remove('outbound');
        rule['action'] = 'reject';
      }
    }

    if (presentKeys.length <= 1) {
      final Map<String, dynamic> single = Map<String, dynamic>.from(source);
      if (!presentKeys.contains('domain') &&
          _nonEmptyRuleField(source['domain']) &&
          _nonEmptyRuleField(source['domain_suffix'])) {
        single.remove('domain');
      }
      applyTarget(single);
      return <Map<String, dynamic>>[single];
    }

    final Map<String, dynamic> base = Map<String, dynamic>.from(source)
      ..remove('domain')
      ..remove('domain_suffix')
      ..remove('domain_keyword')
      ..remove('rule_set');
    applyTarget(base);

    return presentKeys
        .map(
          (String key) => <String, dynamic>{
            ...base,
            key: source[key],
          },
        )
        .toList(growable: false);
  }

  static bool _isPreRouteRule(Map<dynamic, dynamic> item) {
    final String action = '${item['action'] ?? ''}';
    return action == 'sniff' ||
        action == 'hijack-dns' ||
        _containsString(item['protocol'], 'dns') ||
        item['port'] == 53 ||
        _containsInt(item['port'], 53);
  }

  static bool _isDomainLevelBlockRule(Map<dynamic, dynamic> item) {
    final bool isBlockTarget = item['outbound'] == blockPageOutboundTag ||
        item['action'] == 'reject' ||
        item['outbound'] == 'block';
    if (!isBlockTarget) return false;
    if (_nonEmptyRuleField(item['ip_cidr']) ||
        item['ip_is_private'] == true ||
        item['ip_version'] != null ||
        _containsString(item['protocol'], 'quic') ||
        _nonEmptyRuleField(item['process_name']) ||
        _nonEmptyRuleField(item['process_path']) ||
        _nonEmptyRuleField(item['process_path_regex']) ||
        _nonEmptyRuleField(item['package_name'])) {
      return false;
    }
    return _nonEmptyRuleField(item['domain']) ||
        _nonEmptyRuleField(item['domain_suffix']) ||
        _nonEmptyRuleField(item['domain_keyword']) ||
        _nonEmptyRuleField(item['rule_set']);
  }

  static bool _isPrimaryContentBlockRule(Map<dynamic, dynamic> rule) {
    if (_nonEmptyRuleField(rule['process_name']) ||
        _nonEmptyRuleField(rule['process_path']) ||
        _nonEmptyRuleField(rule['process_path_regex']) ||
        _nonEmptyRuleField(rule['package_name']) ||
        _nonEmptyRuleField(rule['ip_cidr']) ||
        rule['ip_is_private'] == true ||
        _containsString(rule['protocol'], 'quic')) {
      return false;
    }

    final List<String> ruleSets = _stringValues(rule['rule_set']);
    if (ruleSets.isNotEmpty) {
      final bool hasPrimaryRuleSet = ruleSets.any((String rs) {
        final String lower = rs.toLowerCase();
        return lower.contains('porn') ||
            lower.contains('adult') ||
            lower.contains('gambling') ||
            lower.contains('betting');
      });
      if (hasPrimaryRuleSet) {
        return true;
      }
      final bool hasAdsRuleSet = ruleSets.any((String rs) {
        final String lower = rs.toLowerCase();
        return lower.contains('ads') || lower.contains('adblock');
      });
      if (hasAdsRuleSet) {
        return false;
      }
    }

    final List<String> domains = <String>[
      ..._stringValues(rule['domain']),
      ..._stringValues(rule['domain_suffix']),
      ..._stringValues(rule['domain_keyword']),
    ];
    if (domains.isEmpty) {
      return false;
    }

    for (final String d in domains) {
      if (MaliciousLinkGuard.inspectHost(d) != null ||
          UmbrellaCore.isPrimaryBlockSiteHost(d)) {
        return true;
      }
    }

    // دامنه های سفارشی کاربر (`custom`) نه پسوندهای صرفاً تبلیغاتی دارند و نه rule_set تبلیغاتی.
    const Set<String> knownAdMarkers = <String>{
      'doubleclick.net',
      'googlesyndication.com',
      'googleadservices.com',
      'google-analytics.com',
      'adservice.google.com',
      'adnxs.com',
      'taboola.com',
      'outbrain.com',
      'criteo.com',
    };
    final bool looksLikeAdRule = domains.any(
      (String d) => knownAdMarkers.contains(d.trim().toLowerCase()),
    );
    return !looksLikeAdRule;
  }

  static List<String> _stringValues(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return <String>[value.trim()];
    }
    if (value is List) {
      return value
          .map((Object? item) => '${item ?? ''}'.trim())
          .where((String s) => s.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  static String? _findDirectOutboundTag(List<dynamic> outbounds) {
    for (final dynamic item in outbounds) {
      if (item is Map && item['tag'] == directOutboundTag) {
        return directOutboundTag;
      }
    }
    for (final dynamic item in outbounds) {
      if (item is Map &&
          item['type'] == 'direct' &&
          item['tag'] is String &&
          !(item['tag'] as String).startsWith('umbrella-xhttp-download-')) {
        return item['tag'] as String;
      }
    }
    return null;
  }

  static String? _effectiveResolveStrategy(Map<String, dynamic>? settings) {
    if (settings == null) return null;
    final String ipv6 = '${settings['ipv6-mode'] ?? ''}'.trim();
    final String remote = '${settings['remote-dns-domain-strategy'] ?? ''}'.trim();
    if (ipv6 == 'ipv4_only' && remote != 'ipv6_only') {
      return 'ipv4_only';
    }
    if (_validDomainStrategies.contains(remote)) {
      return remote;
    }
    if (_validDomainStrategies.contains(ipv6)) {
      return ipv6;
    }
    return null;
  }

  static _ResolvedTlsPadding? _extractTlsPadding(
    Map<String, dynamic>? settings,
  ) {
    final dynamic raw = settings?['tls-tricks'];
    if (raw is! Map || raw['enable-padding'] != true) {
      return null;
    }
    final String size = '${raw['padding-size'] ?? ''}'.trim();
    final String valid = TlsTricksSettings.isValidRange(
      size,
      min: 1,
      max: TlsTricksSettings.maxPaddingSize,
    )
        ? size
        : TlsTricksSettings.defaultPaddingSize;
    return _ResolvedTlsPadding(size: valid);
  }

  static _ResolvedTlsFragment? _extractTlsFragment(
    Map<String, dynamic>? settings,
  ) {
    final dynamic raw = settings?['tls-tricks'];
    if (raw is! Map || raw['enable-fragment'] != true) {
      return null;
    }
    final String rawSize = '${raw['fragment-size'] ?? ''}'.trim();
    final String rawSleep = '${raw['fragment-sleep'] ?? ''}'.trim();
    final String size = TlsTricksSettings.isValidRange(rawSize)
        ? rawSize
        : TlsTricksSettings.defaultFragmentSize;
    final String sleep = TlsTricksSettings.isValidRange(rawSleep, min: 0)
        ? rawSleep
        : TlsTricksSettings.defaultFragmentSleep;
    return _ResolvedTlsFragment(size: size, sleep: sleep);
  }

  static bool _extractMixedSniCase(Map<String, dynamic>? settings) {
    final dynamic raw = settings?['tls-tricks'];
    return raw is Map && raw['mixed-sni-case'] == true;
  }

  static void _patchOutboundTlsTricks(
    Map<String, dynamic> outbound, {
    required _ResolvedTlsPadding? padding,
    required _ResolvedTlsFragment? fragment,
    required bool mixedSniCase,
  }) {
    final String type = '${outbound['type'] ?? ''}';
    if (!_tlsTrickOutboundTypes.contains(type)) {
      return;
    }
    final dynamic transport = outbound['transport'];
    final String transportType =
        transport is Map ? '${transport['type'] ?? ''}' : '';
    // Plain TCP (`transport == null`) and all TCP-based V2Ray transports
    // support TLS ClientHello tricks; QUIC uses standard TLS without uTLS.
    if (transportType.isNotEmpty &&
        !_tlsTrickTransports.contains(transportType)) {
      return;
    }
    final dynamic rawTls = outbound['tls'];
    if (rawTls is! Map<String, dynamic> || rawTls['enabled'] != true) {
      return;
    }
    final dynamic reality = rawTls['reality'];
    if (reality is Map && reality['enabled'] == true) {
      return;
    }

    if (fragment != null) {
      final dynamic existingFrag = outbound['tls_fragment'];
      final bool alreadyEnabled =
          existingFrag is Map && existingFrag['enabled'] == true;
      if (!alreadyEnabled) {
        outbound['tcp_fast_open'] = false;
        outbound['tls_fragment'] = <String, dynamic>{
          'enabled': true,
          'size': fragment.size,
          'sleep': fragment.sleep,
        };
      }
    }

    final Map<String, dynamic> tricks = rawTls['tls_tricks'] is Map
        ? Map<String, dynamic>.from(rawTls['tls_tricks'] as Map)
        : <String, dynamic>{};
    if (mixedSniCase) {
      tricks['mixedcase_sni'] = true;
    }
    if (padding != null) {
      tricks['padding_mode'] = 'random';
      tricks['padding_size'] = padding.size;

      // `h_tls_tricks.go` applies ClientHello extension padding on fixed uTLS
      // specs; ensure uTLS is enabled with a concrete browser fingerprint.
      final Map<String, dynamic> utls = rawTls['utls'] is Map
          ? Map<String, dynamic>.from(rawTls['utls'] as Map)
          : <String, dynamic>{};
      final String fp = '${utls['fingerprint'] ?? ''}'.trim().toLowerCase();
      utls['enabled'] = true;
      if (!_fixedUtlsFingerprints.contains(fp)) {
        utls['fingerprint'] = 'chrome';
      }
      rawTls['utls'] = utls;
    }
    if (tricks.isNotEmpty) {
      rawTls['tls_tricks'] = tricks;
    }
  }

  /// مهاجرت فیلدهای منسوخ در `sing-box 1.14/1.15` به معادل استاندارد جدید:
  /// - `route.rule_set[*].download_detour` -> `http_client: { detour: <tag> }`
  /// - `experimental.cache_file.store_rdrc` -> حذف (در 1.14+ خودکار است)
  /// - `dns.independent_cache` -> حذف (در 1.14+ کش هر سرور DNS ذاتاً مستقل است)
  /// - `dns.rules[*].strategy` -> تبدیل `ipv4_only`/`ipv6_only` به قانون پیش از آن
  ///   با `query_type: [AAAA|A]` و `action: predefined, rcode: NOERROR` و حذف فیلد
  /// - `dns.rules[*].rule_set_ip_cidr_accept_empty` و `geoip-*` در DNS -> پاک سازی
  static void _migrateSingBox114Deprecations(
    Map<String, dynamic> config,
    Map<String, dynamic> experimental,
  ) {
    final Object? cacheFile = experimental['cache_file'];
    if (cacheFile is Map<String, dynamic>) {
      cacheFile.remove('store_rdrc');
    }

    final Object? rawRoute = config['route'];
    if (rawRoute is Map<String, dynamic>) {
      final Object? rawRuleSets = rawRoute['rule_set'];
      if (rawRuleSets is List) {
        for (final dynamic item in rawRuleSets) {
          if (item is! Map<String, dynamic>) continue;
          final Object? legacyDetour = item.remove('download_detour');
          final String detour = '${legacyDetour ?? ''}'.trim();
          if (item['type'] == 'remote' && item['http_client'] == null) {
            item['http_client'] = <String, dynamic>{
              'detour': detour.isNotEmpty ? detour : 'select',
            };
          }
        }
      }
    }

    final Object? rawDns = config['dns'];
    if (rawDns is! Map<String, dynamic>) {
      return;
    }
    rawDns.remove('independent_cache');

    final Object? rawDnsRules = rawDns['rules'];
    if (rawDnsRules is! List) {
      return;
    }
    const Set<String> dnsActionKeys = <String>{
      'action',
      'server',
      'speculative',
      'tag',
      'timeout',
      'strategy',
      'disable_cache',
      'disable_optimistic_cache',
      'rewrite_ttl',
      'client_subnet',
      'remove_client_subnet',
      'bypass_if_failed',
      'ipv6_by_outbound',
      'race',
      'rcode',
      'answer',
      'ns',
      'extra',
      'method',
      'no_drop',
    };
    final List<dynamic> migrated = <dynamic>[];
    for (final dynamic rawRule in rawDnsRules) {
      if (rawRule is! Map<String, dynamic>) continue;
      rawRule.remove('rule_set_ip_cidr_accept_empty');
      rawRule.remove('rule_set_ip_cidr_match_source');

      final Object? rs = rawRule['rule_set'];
      if (rs is List) {
        final List<String> kept = rs
            .map((Object? e) => '$e')
            .where((String tag) => !tag.toLowerCase().startsWith('geoip-'))
            .toList(growable: false);
        if (kept.isEmpty && rs.isNotEmpty) {
          rawRule.remove('rule_set');
          final bool hasOtherMatch = rawRule.keys
              .any((String k) => !dnsActionKeys.contains(k));
          if (!hasOtherMatch) {
            continue;
          }
        } else if (kept.length != rs.length) {
          rawRule['rule_set'] = kept;
        }
      }

      final String strategy = '${rawRule.remove('strategy') ?? ''}'.trim();
      final bool isRouteAction =
          rawRule['action'] == null || rawRule['action'] == 'route';
      if (isRouteAction &&
          rawRule['query_type'] == null &&
          (strategy == 'ipv4_only' || strategy == 'ipv6_only')) {
        final Map<String, dynamic> suppressRule = <String, dynamic>{};
        for (final MapEntry<String, dynamic> entry in rawRule.entries) {
          if (!dnsActionKeys.contains(entry.key)) {
            suppressRule[entry.key] = entry.value;
          }
        }
        suppressRule['query_type'] = <String>[
          strategy == 'ipv4_only' ? 'AAAA' : 'A',
        ];
        suppressRule['action'] = 'predefined';
        suppressRule['rcode'] = 'NOERROR';
        migrated.add(suppressRule);
      }
      migrated.add(rawRule);
    }
    rawDns['rules'] = migrated;
  }

  static const List<String> _iranLocalRuleSetTags = <String>[
    'geoip-ir',
    'geosite-ir',
    'geoip-arvancloud',
    'geoip-parspack',
    'geoip-derakcloud',
    'geoip-iranserver',
  ];

  static const List<String> _iranIpRuleSetTags = <String>[
    'geoip-ir',
    'geoip-arvancloud',
    'geoip-parspack',
    'geoip-derakcloud',
    'geoip-iranserver',
  ];

  static const List<String> _contentFilterLocalRuleSetTags = <String>[
    'filter-adult',
    'filter-gambling',
    'filter-ads',
    'filter-youtube-ads',
  ];

  static const Map<String, String> _localRuleSetTagAliases = <String, String>{
    'geosite-category-porn': 'filter-adult',
    'geosite-category-gambling': 'filter-gambling',
    'geosite-category-betting': 'filter-gambling',
    'geosite-category-betting-ru': 'filter-gambling',
    'geosite-category-ads-all': 'filter-ads',
  };

  static const Map<String, List<String>> _filterCategoryLocalTags =
      <String, List<String>>{
    'adult': <String>['filter-adult'],
    'gambling': <String>['filter-gambling'],
    'ads': <String>['filter-ads', 'filter-youtube-ads'],
  };

  static Map<String, String> _discoverLocalRuleSets(
    Map<String, String>? explicitPaths,
    String? localDataDir,
  ) {
    final Map<String, String> resolved = <String, String>{};
    if (explicitPaths != null) {
      for (final MapEntry<String, String> e in explicitPaths.entries) {
        final String key = e.key.trim().toLowerCase();
        final String path = e.value.trim();
        if (key.isNotEmpty && path.isNotEmpty) {
          resolved[key] = path;
        }
      }
    }
    if (localDataDir != null && localDataDir.trim().isNotEmpty) {
      final String sep = Platform.pathSeparator;
      final String base = localDataDir.endsWith(sep)
          ? localDataDir.substring(0, localDataDir.length - 1)
          : localDataDir;
      for (final String tag in <String>[
        ..._iranLocalRuleSetTags,
        ..._contentFilterLocalRuleSetTags,
      ]) {
        if (resolved.containsKey(tag)) continue;
        final File candidate = File('$base$sep$tag.srs');
        if (candidate.existsSync() && candidate.lengthSync() >= 32) {
          resolved[tag] = candidate.path;
        }
      }
    }
    return resolved;
  }

  static String? _matchingLocalTag(
    Map<String, dynamic> ruleSet,
    Map<String, String> localPaths,
  ) {
    final String tag = '${ruleSet['tag'] ?? ''}'.trim().toLowerCase();
    if (tag.isNotEmpty) {
      if (localPaths.containsKey(tag)) {
        return tag;
      }
      final String? alias = _localRuleSetTagAliases[tag];
      if (alias != null && localPaths.containsKey(alias)) {
        return alias;
      }
    }
    final String url = '${ruleSet['url'] ?? ''}'.trim().toLowerCase();
    if (url.isNotEmpty) {
      for (final String candidate in localPaths.keys) {
        if (url.endsWith('/$candidate.srs') || url.endsWith('$candidate.srs')) {
          return candidate;
        }
      }
      for (final MapEntry<String, String> entry
          in _localRuleSetTagAliases.entries) {
        if (localPaths.containsKey(entry.value) &&
            (url.endsWith('/${entry.key}.srs') ||
                url.endsWith('${entry.key}.srs'))) {
          return entry.value;
        }
      }
    }
    return null;
  }

  static void _ensureRequestedLocalFilterRuleSets(
    Map<String, dynamic> config,
    Map<String, dynamic>? coreSettings, {
    required Map<String, String> localPaths,
  }) {
    if (localPaths.isEmpty) return;
    final Object? rawRoute = config['route'];
    if (rawRoute is! Map<String, dynamic>) return;

    final List<dynamic> ruleSets = rawRoute['rule_set'] is List
        ? (rawRoute['rule_set'] as List<dynamic>)
        : <dynamic>[];
    final Map<String, String> knownTagByLocalKey = <String, String>{};
    for (final dynamic item in ruleSets) {
      if (item is! Map<String, dynamic>) continue;
      final String existingTag = '${item['tag'] ?? ''}'.trim();
      final String? matchedKey = _matchingLocalTag(item, localPaths);
      if (matchedKey != null) {
        final String localPath = localPaths[matchedKey]!;
        final String finalTag =
            existingTag.isNotEmpty ? existingTag : matchedKey;
        item
          ..['type'] = 'local'
          ..['tag'] = finalTag
          ..['format'] = 'binary'
          ..['path'] = localPath
          ..remove('url')
          ..remove('http_client')
          ..remove('download_detour')
          ..remove('update_interval');
        knownTagByLocalKey[matchedKey] = finalTag;
      } else if (existingTag.isNotEmpty) {
        knownTagByLocalKey.putIfAbsent(
          existingTag.toLowerCase(),
          () => existingTag,
        );
      }
    }

    final Set<String> requestedFilterTags = <String>{};
    final Object? routeRule = coreSettings?['route-rule'];
    if (routeRule is Map && routeRule['rules'] is List) {
      for (final dynamic rawRule in routeRule['rules'] as List<dynamic>) {
        if (rawRule is! Map || rawRule['enabled'] == false) continue;
        final String name = '${rawRule['name'] ?? ''}'.trim().toLowerCase();
        if (name.startsWith('umbrella-filter-')) {
          final String category = name.substring('umbrella-filter-'.length);
          final List<String>? mapped = _filterCategoryLocalTags[category];
          if (mapped != null) {
            for (final String tag in mapped) {
              if (localPaths.containsKey(tag)) {
                requestedFilterTags.add(tag);
              }
            }
          }
        }
        final Object? rawSets = rawRule['rule_set'];
        if (rawSets is List) {
          for (final Object? entry in rawSets) {
            final String lower = '$entry'.trim().toLowerCase();
            for (final String tag in _contentFilterLocalRuleSetTags) {
              if (localPaths.containsKey(tag) &&
                  (lower == tag ||
                      lower.endsWith('/$tag.srs') ||
                      lower.endsWith('$tag.srs'))) {
                requestedFilterTags.add(tag);
              }
            }
            for (final MapEntry<String, String> alias
                in _localRuleSetTagAliases.entries) {
              if (_contentFilterLocalRuleSetTags.contains(alias.value) &&
                  localPaths.containsKey(alias.value) &&
                  (lower == alias.key ||
                      lower.endsWith('/${alias.key}.srs') ||
                      lower.endsWith('${alias.key}.srs'))) {
                requestedFilterTags.add(alias.value);
              }
            }
          }
        }
      }
    }
    if (requestedFilterTags.isEmpty) {
      if (ruleSets.isNotEmpty) {
        rawRoute['rule_set'] = ruleSets;
      }
      return;
    }

    final List<dynamic> routeRules = rawRoute['rules'] is List
        ? (rawRoute['rules'] as List<dynamic>)
        : <dynamic>[];
    final Object? rawDns = config['dns'];
    final List<dynamic>? dnsRules =
        rawDns is Map<String, dynamic> && rawDns['rules'] is List
            ? rawDns['rules'] as List<dynamic>
            : null;

    for (final String tag in requestedFilterTags) {
      final String? path = localPaths[tag];
      if (path == null) continue;
      final String finalTag = knownTagByLocalKey.putIfAbsent(tag, () {
        ruleSets.add(<String, dynamic>{
          'type': 'local',
          'tag': tag,
          'format': 'binary',
          'path': path,
        });
        return tag;
      });

      final bool hasRouteRule = routeRules.any(
        (dynamic r) => r is Map && _containsString(r['rule_set'], finalTag),
      );
      if (!hasRouteRule) {
        routeRules.add(<String, dynamic>{
          'rule_set': <String>[finalTag],
          'action': 'reject',
        });
      }

      if (dnsRules != null) {
        final bool hasDnsRule = dnsRules.any(
          (dynamic r) => r is Map && _containsString(r['rule_set'], finalTag),
        );
        if (!hasDnsRule) {
          int insertAt = dnsRules.indexWhere((dynamic r) {
            if (r is! Map) return false;
            final String srv = '${r['server'] ?? ''}';
            return srv == 'dns-fake' || srv == 'dns-remote-group';
          });
          if (insertAt < 0) insertAt = dnsRules.length;
          dnsRules.insert(insertAt, <String, dynamic>{
            'rule_set': <String>[finalTag],
            'action': 'reject',
          });
        }
      }
    }

    if (ruleSets.isNotEmpty) {
      rawRoute['rule_set'] = ruleSets;
    }
    if (rawRoute['rules'] == null && routeRules.isNotEmpty) {
      rawRoute['rules'] = routeRules;
    }
  }

  static void _configureOfflineIranBypass(
    Map<String, dynamic> config,
    List<dynamic> outbounds,
    Map<String, dynamic>? coreSettings, {
    Map<String, String>? localRuleSetPaths,
    String? localDataDir,
  }) {
    final Object? rawRoute = config['route'];
    if (rawRoute is! Map<String, dynamic>) return;
    final Object? rawRules = rawRoute['rules'];
    if (rawRules is! List<dynamic>) return;

    final Map<String, String> localPaths =
        _discoverLocalRuleSets(localRuleSetPaths, localDataDir);

    final List<dynamic> ruleSets = rawRoute['rule_set'] is List
        ? (rawRoute['rule_set'] as List<dynamic>)
        : <dynamic>[];
    final Map<String, String> knownTagByLocalKey = <String, String>{};
    for (final dynamic item in ruleSets) {
      if (item is! Map<String, dynamic>) continue;
      final String existingTag = '${item['tag'] ?? ''}'.trim();
      final String? matchedKey = _matchingLocalTag(item, localPaths);
      if (matchedKey != null) {
        final String localPath = localPaths[matchedKey]!;
        final String finalTag =
            existingTag.isNotEmpty ? existingTag : matchedKey;
        item
          ..['type'] = 'local'
          ..['tag'] = finalTag
          ..['format'] = 'binary'
          ..['path'] = localPath
          ..remove('url')
          ..remove('http_client')
          ..remove('download_detour')
          ..remove('update_interval');
        knownTagByLocalKey[matchedKey] = finalTag;
      } else if (existingTag.isNotEmpty) {
        knownTagByLocalKey.putIfAbsent(existingTag.toLowerCase(), () => existingTag);
      }
    }

    final String? directTag = _findDirectOutboundTag(outbounds);
    final bool hasIranBypass = _hasIranBypassConfig(
      coreSettings,
      rawRules,
      directTag: directTag,
    );

    if (hasIranBypass && localPaths.isNotEmpty) {
      for (final String key in _iranLocalRuleSetTags) {
        final String? path = localPaths[key];
        if (path == null || knownTagByLocalKey.containsKey(key)) continue;
        ruleSets.add(<String, dynamic>{
          'type': 'local',
          'tag': key,
          'format': 'binary',
          'path': path,
        });
        knownTagByLocalKey[key] = key;
      }
      if (ruleSets.isNotEmpty) {
        rawRoute['rule_set'] = ruleSets;
      }
    }

    final Object? rawDns = config['dns'];
    final List<dynamic>? dnsServers =
        rawDns is Map<String, dynamic> && rawDns['servers'] is List
            ? rawDns['servers'] as List<dynamic>
            : null;
    final bool hasRemoteDnsGroup = dnsServers != null &&
        dnsServers.any((dynamic s) => s is Map && s['tag'] == 'dns-remote-group');
    final bool hasDirectDnsGroup = dnsServers != null &&
        dnsServers.any((dynamic s) => s is Map && s['tag'] == 'dns-direct-group');

    if (hasIranBypass && directTag != null) {
      final List<String> extraIpTags = <String>[
        for (final String key in _iranIpRuleSetTags)
          if (knownTagByLocalKey.containsKey(key)) knownTagByLocalKey[key]!,
      ];
      if (extraIpTags.isNotEmpty) {
        bool attached = false;
        for (final dynamic item in rawRules) {
          if (item is! Map<String, dynamic>) continue;
          if (item['outbound'] != directTag) continue;
          final Object? rs = item['rule_set'];
          if (rs is List &&
              rs.any((Object? t) => '$t'.toLowerCase().contains('geoip-ir'))) {
            final List<String> merged = <String>[
              for (final Object? t in rs) '$t',
            ];
            for (final String tag in extraIpTags) {
              if (!merged.contains(tag)) merged.add(tag);
            }
            item['rule_set'] = merged;
            attached = true;
            break;
          }
        }
        if (!attached) {
          rawRules.add(<String, dynamic>{
            'rule_set': extraIpTags,
            'outbound': directTag,
          });
        }
      }
    }

    final bool hasIpBypass = rawRules.any(
      (dynamic r) =>
          r is Map &&
          directTag != null &&
          r['outbound'] == directTag &&
          (_nonEmptyRuleField(r['ip_cidr']) ||
              r['ip_is_private'] == true ||
              _ruleHasGeoIpRuleSet(r['rule_set'])),
    );
    if (hasRemoteDnsGroup && hasIpBypass) {
      final bool alreadyHasResolve = rawRules.any(
        (dynamic item) => item is Map && item['action'] == 'resolve',
      );
      if (!alreadyHasResolve) {
        final String? strategy = _effectiveResolveStrategy(coreSettings);
        rawRules.insert(_resolveInsertIndex(rawRules), <String, dynamic>{
          'action': 'resolve',
          'server': 'dns-remote-group',
          if (strategy != null) 'strategy': strategy,
        });
      }
    }

    final int resolveIdx =
        rawRules.indexWhere((dynamic r) => r is Map && r['action'] == 'resolve');
    if (resolveIdx >= 0 && hasRemoteDnsGroup) {
      final Map<String, dynamic> resolveRule =
          rawRules[resolveIdx] as Map<String, dynamic>;
      resolveRule['server'] ??= 'dns-remote-group';
    }

    if (resolveIdx >= 0 && directTag != null) {
      final List<dynamic> domainDirectBeforeResolve = <dynamic>[];
      final List<dynamic> ipDirectAfterResolve = <dynamic>[];
      final List<dynamic> remaining = <dynamic>[];
      for (final dynamic item in rawRules) {
        if (item is Map<String, dynamic> && item['outbound'] == directTag) {
          if (_isPureDomainDirectRule(item)) {
            domainDirectBeforeResolve.add(item);
            continue;
          }
          if (_isPureIpDirectRule(item)) {
            ipDirectAfterResolve.add(item);
            continue;
          }
        }
        remaining.add(item);
      }
      if (domainDirectBeforeResolve.isNotEmpty ||
          ipDirectAfterResolve.isNotEmpty) {
        final int insertDomainAt = _resolveInsertIndex(remaining);
        remaining.insertAll(insertDomainAt, domainDirectBeforeResolve);
        final int newResolveIdx = remaining
            .indexWhere((dynamic r) => r is Map && r['action'] == 'resolve');
        if (newResolveIdx >= 0) {
          final int bypassIdx = _bypassLanInsertIndex(remaining, directTag);
          final int insertIpAt =
              bypassIdx > newResolveIdx ? bypassIdx : newResolveIdx + 1;
          remaining.insertAll(insertIpAt, ipDirectAfterResolve);
        } else {
          remaining.addAll(ipDirectAfterResolve);
        }
        rawRoute['rules'] = remaining;
      }
    }

    if (hasDirectDnsGroup && rawDns is Map<String, dynamic> && rawDns['rules'] is List) {
      final List<dynamic> dnsRules = rawDns['rules'] as List<dynamic>;
      final List<String> directDomains = _extractUserBypassDomains(coreSettings);
      final List<String> directSuffixes = <String>[
        if (hasIranBypass) '.ir',
        ...directDomains,
      ];
      final String? geositeIrTag = knownTagByLocalKey['geosite-ir'];
      final bool needsDnsRule =
          directSuffixes.isNotEmpty || (hasIranBypass && geositeIrTag != null);
      if (needsDnsRule) {
        final bool alreadyHasIranDirectDns = dnsRules.any((dynamic r) {
          if (r is! Map || r['server'] != 'dns-direct-group') return false;
          if (hasIranBypass &&
              (_containsString(r['domain_suffix'], '.ir') ||
                  (geositeIrTag != null &&
                      _containsString(r['rule_set'], geositeIrTag)))) {
            return true;
          }
          return directDomains.isNotEmpty &&
              directDomains.every(
                (String d) => _containsString(r['domain_suffix'], d),
              );
        });
        if (!alreadyHasIranDirectDns) {
          int insertAt = dnsRules.indexWhere((dynamic r) {
            if (r is! Map) return false;
            final String srv = '${r['server'] ?? ''}';
            return srv == 'dns-fake' || srv == 'dns-remote-group';
          });
          if (insertAt < 0) insertAt = dnsRules.length;
          final List<Map<String, dynamic>> directRules = <Map<String, dynamic>>[
            if (directSuffixes.isNotEmpty)
              <String, dynamic>{
                'domain_suffix': directSuffixes,
                'server': 'dns-direct-group',
              },
            if (hasIranBypass && geositeIrTag != null)
              <String, dynamic>{
                'rule_set': <String>[geositeIrTag],
                'server': 'dns-direct-group',
              },
          ];
          dnsRules.insertAll(insertAt, directRules);
        }
      }
    }
  }

  static bool _hasIranBypassConfig(
    Map<String, dynamic>? coreSettings,
    List<dynamic> rules, {
    String? directTag,
  }) {
    if ('${coreSettings?['region'] ?? ''}'.toLowerCase() == 'ir') return true;
    final Object? routeRule = coreSettings?['route-rule'];
    if (routeRule is Map && routeRule['rules'] is List) {
      for (final dynamic item in routeRule['rules'] as List) {
        if (item is Map &&
            '${item['name'] ?? ''}'.startsWith('umbrella-bypass-iran')) {
          return true;
        }
      }
    }
    if (directTag == null) return false;
    return rules.any((dynamic r) {
      if (r is! Map || r['outbound'] != directTag) return false;
      return _containsString(r['domain_suffix'], '.ir') ||
          _ruleHasGeoIrRuleSet(r['rule_set']);
    });
  }

  static bool _ruleHasGeoIrRuleSet(Object? value) {
    if (value is String) {
      final String l = value.toLowerCase();
      return l.contains('geoip-ir') || l.contains('geosite-ir');
    }
    if (value is List) {
      return value.any((Object? e) {
        final String l = '$e'.toLowerCase();
        return l.contains('geoip-ir') || l.contains('geosite-ir');
      });
    }
    return false;
  }

  static bool _ruleHasGeoIpRuleSet(Object? value) {
    if (value is String) return value.toLowerCase().contains('geoip-');
    if (value is List) {
      return value.any((Object? e) => '$e'.toLowerCase().contains('geoip-'));
    }
    return false;
  }

  static bool _isPureDomainDirectRule(Map<String, dynamic> rule) {
    if (_nonEmptyRuleField(rule['process_name']) ||
        _nonEmptyRuleField(rule['process_path']) ||
        _nonEmptyRuleField(rule['process_path_regex']) ||
        _nonEmptyRuleField(rule['package_name']) ||
        _nonEmptyRuleField(rule['ip_cidr']) ||
        rule['ip_is_private'] == true ||
        _ruleHasGeoIpRuleSet(rule['rule_set'])) {
      return false;
    }
    return _nonEmptyRuleField(rule['domain']) ||
        _nonEmptyRuleField(rule['domain_suffix']) ||
        _nonEmptyRuleField(rule['domain_keyword']) ||
        _nonEmptyRuleField(rule['rule_set']);
  }

  static bool _isPureIpDirectRule(Map<String, dynamic> rule) {
    if (_nonEmptyRuleField(rule['process_name']) ||
        _nonEmptyRuleField(rule['process_path']) ||
        _nonEmptyRuleField(rule['process_path_regex']) ||
        _nonEmptyRuleField(rule['package_name']) ||
        _nonEmptyRuleField(rule['domain']) ||
        _nonEmptyRuleField(rule['domain_suffix']) ||
        _nonEmptyRuleField(rule['domain_keyword'])) {
      return false;
    }
    return rule['ip_is_private'] == true ||
        _nonEmptyRuleField(rule['ip_cidr']) ||
        _ruleHasGeoIpRuleSet(rule['rule_set']);
  }

  static List<String> _extractUserBypassDomains(
    Map<String, dynamic>? coreSettings,
  ) {
    final Object? routeRule = coreSettings?['route-rule'];
    if (routeRule is! Map || routeRule['rules'] is! List) {
      return const <String>[];
    }
    final List<String> out = <String>[];
    for (final dynamic item in routeRule['rules'] as List) {
      if (item is! Map || item['name'] != 'umbrella-bypass-user') continue;
      for (final String key in const <String>['domain_suffix', 'domain']) {
        final Object? raw = item[key];
        if (raw is List) {
          for (final Object? entry in raw) {
            final String v = '$entry'.trim().toLowerCase();
            if (v.isNotEmpty && !out.contains(v)) out.add(v);
          }
        }
      }
    }
    return out;
  }

  static bool _nonEmptyRuleField(Object? value) {
    if (value is String) return value.trim().isNotEmpty;
    if (value is List) return value.isNotEmpty;
    return false;
  }

  static bool _containsString(Object? value, String needle) {
    if (value is String) return value == needle;
    if (value is List) return value.any((Object? item) => '$item' == needle);
    return false;
  }

  static bool _containsInt(Object? value, int needle) {
    if (value is int) return value == needle;
    if (value is List) return value.any((Object? item) => item == needle);
    return false;
  }
}

class _ResolvedTlsPadding {
  const _ResolvedTlsPadding({required this.size});
  final String size;
}

class _ResolvedTlsFragment {
  const _ResolvedTlsFragment({required this.size, required this.sleep});
  final String size;
  final String sleep;
}
