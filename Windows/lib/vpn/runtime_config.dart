import 'dart:io';

/// Finalize the pinned core's `build` output for `srun`. Unlike `run`, this
/// preserves monitoring/cache settings and explicitly activates lazy keep-top.
/// Source: hiddify-core v5.9.1 v2/hcore/keep_top.go and config/keep_top.go.
class RuntimeConfig {
  const RuntimeConfig._();
  static const Set<String> lazyTypes = <String>{
    'vless', 'vmess', 'trojan', 'shadowsocks', 'socks', 'http', 'hysteria',
    'hysteria2', 'tuic', 'anytls', 'shadowtls', 'ssh', 'naive', 'mieru',
    'snell', 'trusttunnel', 'sudoku',
  };

  static void finalize(Map<String, dynamic> config, {required Set<String> profileTags}) {
    if (config['outbounds'] is! List || config['experimental'] is! Map ||
        config['experimental']['monitoring'] is! Map) {
      throw const FormatException('Built runtime has no outbound monitoring configuration');
    }
    final List<dynamic> outbounds = config['outbounds'] as List<dynamic>;
    final Map<String, dynamic> experimental = config['experimental'] as Map<String, dynamic>;
    final Map<String, dynamic> monitoring = experimental['monitoring'] as Map<String, dynamic>;
    monitoring['keep_top'] = <String, dynamic>{'count': 8, 'batch': 4, 'quick': true};
    // No dashboard download on the connection path. Clash API remains loopback.
    final Map<String, dynamic>? clash = experimental['clash_api'] as Map<String, dynamic>?;
    clash?.remove('external_ui');
    clash?.remove('external_ui_download_url');
    // The controller captures stdout; do not let two writers truncate one log.
    (config['log'] as Map<String, dynamic>?)?.remove('output');
    final List<Map<String, dynamic>> extra = <Map<String, dynamic>>[];
    for (final dynamic value in outbounds) {
      final Map<String, dynamic> outbound = value as Map<String, dynamic>;
      if (profileTags.contains(outbound['tag']) && lazyTypes.contains(outbound['type'])) {
        outbound['lazy'] = true;
      }
      final dynamic transport = outbound['transport'];
      if (transport is! Map || transport['type'] != 'xhttp') continue;
      final dynamic download = transport['download'];
      if (download is! Map || download['server'] is! String ||
          InternetAddress.tryParse(download['server'] as String) != null ||
          (download['server'] as String).isEmpty ||
          '${download['detour'] ?? ''}'.isNotEmpty ||
          '${outbound['detour'] ?? ''}'.isNotEmpty ||
          InternetAddress.tryParse('${outbound['server']}') == null) continue;
      // XHTTP reuses the upload dialer for its separate download endpoint.
      // For an IP upload that dialer has NO resolver, hence the immediate
      // "domain not resolved" (not a DNS timeout). A direct outbound always
      // constructs a resolving dialer. Preserve endpoint/TLS/Host/path and
      // the upload's dial options; never override an explicit/chain detour.
      String tag = 'umbrella-xhttp-download-${extra.length}';
      while (outbounds.any((dynamic item) => item['tag'] == tag) ||
          extra.any((Map<String, dynamic> item) => item['tag'] == tag)) {
        tag = '$tag-';
      }
      final Map<String, dynamic> resolver = <String, dynamic>{'type': 'direct', 'tag': tag};
      for (final String key in <String>[
        'bind_interface', 'inet4_bind_address', 'inet6_bind_address',
        'bind_address_no_port', 'protect_path', 'disable_tcp_keep_alive',
        'tcp_keep_alive', 'tcp_keep_alive_interval', 'routing_mark', 'reuse_addr', 'connect_timeout', 'tcp_fast_open',
        'tcp_multi_path', 'udp_fragment', 'domain_resolver', 'domain_strategy',
        'network_strategy', 'network_type', 'fallback_network_type',
        'fallback_delay', 'netns', 'tls_fragment', 'finalmask',
      ]) {
        if (outbound.containsKey(key)) resolver[key] = outbound[key];
      }
      download['detour'] = tag;
      extra.add(resolver);
    }
    // Download detours are looked up when a transport is constructed.
    outbounds.insertAll(0, extra);
  }
}
