import 'dart:io';

import '../models/advanced_network.dart';

/// Finalize the pinned core's `build` output for `srun`, matching official
/// Hiddify (`hiddify-app` + `hiddify-core v5.9.11`) startup semantics AND
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
  }) {
    if (config['outbounds'] is! List ||
        config['experimental'] is! Map ||
        config['experimental']['monitoring'] is! Map) {
      throw const FormatException(
        'Built runtime has no outbound monitoring configuration',
      );
    }
    final List<dynamic> outbounds = config['outbounds'] as List<dynamic>;
    final Map<String, dynamic> experimental =
        config['experimental'] as Map<String, dynamic>;
    final Map<String, dynamic> monitoring =
        experimental['monitoring'] as Map<String, dynamic>;
    monitoring['workers'] = monitoringWorkers;
    monitoring['debounce_window'] = '200ms';
    monitoring['url_test_timeout'] = '4s';

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
    (config['log'] as Map<String, dynamic>?)?.remove('output');

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

      if (profileTags.contains(tag) && lazyTypes.contains(type)) {
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

    if (lazyCount > autoKeepTopThreshold) {
      monitoring['keep_top'] = <String, dynamic>{
        'count': keepTopCount,
        'batch': keepTopBatch,
        'quick': true,
      };
    } else {
      monitoring.remove('keep_top');
    }
    // Download detours are looked up when a transport is constructed.
    outbounds.insertAll(0, extra);

    // Patch route configuration (process matching, LAN bypass, destination resolve).
    _finalizeRoute(config, outbounds, coreSettings);
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

    // 1. Enable socket-to-process lookup whenever any rule matches a process.
    final bool needsFindProcess = rawRules.any((dynamic item) {
      if (item is! Map) return false;
      return _nonEmptyRuleField(item['process_name']) ||
          _nonEmptyRuleField(item['process_path']) ||
          _nonEmptyRuleField(item['process_path_regex']) ||
          _nonEmptyRuleField(item['package_name']);
    });
    if (needsFindProcess) {
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
      if (action == 'reject' &&
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
    final String remote = '${settings['remote-dns-domain-strategy'] ?? ''}'.trim();
    if (_validDomainStrategies.contains(remote)) {
      return remote;
    }
    final String ipv6 = '${settings['ipv6-mode'] ?? ''}'.trim();
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
