import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Session-only preparation of already-authorized subscription links. Never
/// writes back to the subscription, changes credentials, or imports a source.
/// Resolve endpoint names BEFORE TUN takes over the system resolver: Cronet and
/// other native transports can otherwise ask Windows DNS through the very proxy
/// whose address they are trying to discover. Ordinary destination DNS remains
/// the core's responsibility. No IPs are cached between sessions.
class LinkPreparation {
  const LinkPreparation._();

  static String _key(String value) => value.trim().toLowerCase().replaceAll(RegExp(r'[_-]'), '');

  static const Set<String> _muxKeys = <String>{
    'muxtype', 'muxmaxc', 'muxsmax', 'mux', 'muxpad', 'muxup', 'muxdown',
  };

  static Future<PreparedLinks> prepare(
    List<String> links, {
    Future<List<InternetAddress>> Function(String)? lookup,
    Duration budget = const Duration(seconds: 8),
    bool resolveEndpoints = true,
  }) async {
    final List<_EndpointLink?> parsed = links.map(_EndpointLink.parse).toList();
    final List<String> hosts = parsed.whereType<_EndpointLink>()
        .map((_EndpointLink link) => link.host.toLowerCase())
        .where((String host) => host.isNotEmpty && InternetAddress.tryParse(host) == null)
        .toSet().toList();
    final Map<String, String> addresses = <String, String>{};
    final Stopwatch clock = Stopwatch()..start();
    int next = 0;
    bool finished = false;
    final Future<List<InternetAddress>> Function(String) resolve = lookup ?? InternetAddress.lookup;
    Future<void> worker() async {
      while (!finished && next < hosts.length && clock.elapsed < budget) {
        final String host = hosts[next++];
        try {
          final Duration remaining = budget - clock.elapsed;
          if (remaining <= Duration.zero) break;
          final List<InternetAddress> result = await resolve(host).timeout(remaining);
          // Prefer IPv4 but allow an IPv6-only endpoint. Ignore unspecified,
          // loopback and the known filtering response (not a usable endpoint).
          final List<InternetAddress> usable = result.where((InternetAddress ip) =>
              !ip.isLoopback && !ip.isLinkLocal && ip.address != '0.0.0.0' &&
              ip.address != '::' && !ip.address.startsWith('10.10.34.') &&
              !ip.address.toLowerCase().startsWith('2001:4188:2:600:10:10:34:')).toList()
            ..sort((InternetAddress a, InternetAddress b) =>
                (a.type == InternetAddressType.IPv4 ? 0 : 1)
                    .compareTo(b.type == InternetAddressType.IPv4 ? 0 : 1));
          if (!finished && usable.isNotEmpty) addresses[host] = usable.first.address;
        } on Exception {
          // Keep the domain and let the core's configured direct resolver try.
          // Never log a share link, password, UUID, or DNS exception text.
        }
      }
    }
    if (resolveEndpoints && budget > Duration.zero) {
      await Future.wait(<Future<void>>[for (int i = 0; i < 4; i++) worker()])
          .timeout(budget, onTimeout: () => <void>[]);
    }
    finished = true;
    return PreparedLinks(
      <String>[for (int i = 0; i < links.length; i++)
        parsed[i]?.render(addresses[parsed[i]!.host.toLowerCase()]) ?? links[i]],
      resolvedHosts: addresses.length,
      unresolvedHosts: resolveEndpoints ? hosts.length - addresses.length : 0,
    );
  }
}

class PreparedLinks {
  const PreparedLinks(this.links, {required this.resolvedHosts, required this.unresolvedHosts});
  final List<String> links;
  final int resolvedHosts;
  final int unresolvedHosts;
}

class _EndpointLink {
  _EndpointLink(this.uri, this.data, this.host);
  final Uri uri;
  final Map<String, dynamic>? data;
  final String host;

  static _EndpointLink? parse(String link) {
    try {
      if (link.startsWith('vmess://')) {
        final Map<String, dynamic> data = jsonDecode(utf8.decode(
            base64.decode(base64.normalize(link.substring(8))))) as Map<String, dynamic>;
        return _EndpointLink(Uri(scheme: 'vmess'), data, '${data['add'] ?? ''}');
      }
      final Uri uri = Uri.parse(link.replaceAll('&amp;', '&'));
      if (uri.scheme != 'vless' && uri.scheme != 'trojan') return null;
      if (!uri.hasAuthority || uri.host.isEmpty) return null;
      // Validate percent-encoding now so one malformed link cannot abort the pool.
      uri.queryParameters;
      return _EndpointLink(uri, null, uri.host);
    } on Exception {
      return null;
    }
  }

  String render(String? address) {
    if (data != null) {
      final Map<String, dynamic> result = Map<String, dynamic>.of(data!);
      result.removeWhere((String key, dynamic _) => LinkPreparation._muxKeys.contains(LinkPreparation._key(key)));
      if (address != null) {
        _preserveNames(result);
        result['add'] = address;
      }
      return 'vmess://${base64Encode(utf8.encode(jsonEncode(result)))}';
    }
    // Retain raw encoding, duplicate parameters, extra/xmux and credentials.
    // Only remove the core's optional protocol mux, matching mux.enable=false.
    final List<String> query = uri.query.isEmpty ? <String>[] : uri.query.split('&');
    query.removeWhere((String part) => LinkPreparation._muxKeys.contains(
        LinkPreparation._key(Uri.decodeQueryComponent(part.split('=').first))));
    if (address != null) {
      final Map<String, dynamic> originalNames = <String, dynamic>{
        for (final MapEntry<String, List<String>> entry in uri.queryParametersAll.entries)
          LinkPreparation._key(entry.key): entry.value.join(','),
      };
      final Map<String, dynamic> names = Map<String, dynamic>.of(originalNames);
      _preserveNames(names);
      for (final String key in <String>['sni', 'host']) {
        if ('${originalNames[key] ?? ''}'.trim().isEmpty && names.containsKey(key)) {
          query.removeWhere((String part) => LinkPreparation._key(Uri.decodeQueryComponent(part.split('=').first)) == key);
          query.add('$key=${Uri.encodeQueryComponent('${names[key]}')}');
        }
      }
    }
    return uri.replace(host: address, query: query.join('&')).toString();
  }

  void _preserveNames(Map<String, dynamic> values) {
    // Match ray2sing's SNI fallback: explicit SNI, first HTTP host, endpoint.
    // Preserve it before replacing the endpoint by an IP; never weaken TLS.
    if ('${values['sni'] ?? ''}'.trim().isEmpty) {
      final String transportHost = '${values['host'] ?? ''}'.split(',').first.trim();
      final Uri? authority = Uri.tryParse('https://$transportHost');
      values['sni'] = transportHost.isEmpty ? host : (authority?.host ?? transportHost);
    }
    String transport = '${values['net'] ?? values['type'] ?? ''}'.toLowerCase();
    if ((transport == 'tcp' || transport == 'raw') &&
        (values['headertype'] == 'http' || values['type'] == 'http')) transport = 'http';
    final bool tls = values['tls'] == 'tls' || values['security'] == 'tls' ||
        values['security'] == 'reality' || (uri.scheme == 'trojan' &&
        !values.containsKey('security') && '${values['tls'] ?? ''}'.isEmpty);
    final int port = data == null ? (uri.hasPort ? uri.port : 443)
        : int.tryParse('${values['port']}') ?? 443;
    final String authority = host.contains(':') ? '[$host]:$port' : '$host:$port';
    if ('${values['host'] ?? ''}'.isEmpty) {
      // Preserve the pinned core's transport-specific Host fallback, including
      // ports. XHTTP/HTTPUpgrade over TLS already fall back to preserved SNI;
      // overriding them with the endpoint would break CDN virtual-host routing.
      if (<String>['ws', 'http', 'h2'].contains(transport) || (transport == 'httpupgrade' && !tls)) {
        values['host'] = authority;
      } else if (<String>['xhttp', 'splithttp'].contains(transport) && !tls) {
        values['host'] = host;
      }
    }
  }
}
