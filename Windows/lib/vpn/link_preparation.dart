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

  static String _key(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[_-]'), '');

  static const Set<String> _muxKeys = <String>{
    'muxtype',
    'muxmaxc',
    'muxsmax',
    'mux',
    'muxpad',
    'muxup',
    'muxdown',
  };

  /// `sing-box/protocol/naive` fatally rejects ALPN, uTLS fingerprint,
  /// insecure, disable_sni, cipher_suites and TLS fragment options and aborts
  /// the entire core startup if a panel appends them to a `naive://` link.
  static const Set<String> _naiveRejectedTlsKeys = <String>{
    'alpn',
    'fp',
    'fingerprint',
    'insecure',
    'allowinsecure',
    'nosni',
    'pcs',
    'cs',
    'ciphersuites',
    'fragment',
    'fgsize',
    'fgsleep',
  };

  /// Normalizes a single share link for core compatibility without performing
  /// any DNS lookup (e.g. NaiveProxy forbidden TLS params and split SIP003
  /// `obfs-local` parameters on Shadowsocks links).
  static String normalizeLink(String link) {
    final _EndpointLink? parsed = _EndpointLink.parse(link);
    if (parsed == null) {
      return link;
    }
    return parsed.render(null);
  }

  /// Canonical endpoint key without `#fragment` so byte-identical entries in a
  /// subscription do not occupy duplicate probe slots in the core pool.
  static String canonicalTarget(String link) {
    final String trimmed = link.trim();
    if (trimmed.startsWith('vmess://') || trimmed.startsWith('svmess://')) {
      final int sep = trimmed.indexOf('://');
      final String scheme = trimmed.substring(0, sep).toLowerCase();
      final String rest = trimmed.substring(sep + 3);
      final int hash = rest.indexOf('#');
      final String payload = hash < 0 ? rest : rest.substring(0, hash);
      try {
        final Object? decoded =
            jsonDecode(utf8.decode(base64.decode(base64.normalize(payload))));
        if (decoded is Map<String, dynamic>) {
          final Map<String, dynamic> copy = Map<String, dynamic>.of(decoded)
            ..remove('ps');
          if (copy['add'] is String) {
            copy['add'] = (copy['add'] as String).toLowerCase();
          }
          final List<String> keys = copy.keys.toList()..sort();
          return '$scheme:${jsonEncode(<String, dynamic>{
            for (final String k in keys) k: copy[k],
          })}';
        }
      } on Object {
        // Fall through to raw comparison.
      }
      return '$scheme://$payload';
    }
    final int hash = trimmed.indexOf('#');
    return hash < 0 ? trimmed : trimmed.substring(0, hash);
  }

  static Future<PreparedLinks> prepare(
    List<String> links, {
    Future<List<InternetAddress>> Function(String)? lookup,
    Duration budget = const Duration(seconds: 8),
    Duration perHostTimeout = const Duration(milliseconds: 1500),
    bool resolveEndpoints = true,
  }) async {
    final List<_EndpointLink?> parsed = links.map(_EndpointLink.parse).toList();
    final List<String> hosts = parsed
        .whereType<_EndpointLink>()
        .where((_EndpointLink link) => link.canBootstrap)
        .map((_EndpointLink link) => link.host.toLowerCase())
        .where((String host) =>
            host.isNotEmpty && InternetAddress.tryParse(host) == null)
        .toSet()
        .toList();
    final Map<String, String> addresses = <String, String>{};
    final Stopwatch clock = Stopwatch()..start();
    int next = 0;
    bool finished = false;
    final Future<List<InternetAddress>> Function(String) resolve =
        lookup ?? InternetAddress.lookup;
    Future<void> worker() async {
      while (!finished && next < hosts.length && clock.elapsed < budget) {
        final String host = hosts[next++];
        try {
          final Duration remaining = budget - clock.elapsed;
          if (remaining <= Duration.zero) break;
          final Duration lookupLimit =
              perHostTimeout > Duration.zero && perHostTimeout < remaining
                  ? perHostTimeout
                  : remaining;
          final List<InternetAddress> result =
              await resolve(host).timeout(lookupLimit);
          // Prefer IPv4 but allow an IPv6-only endpoint. Ignore unspecified,
          // loopback and the known filtering response (not a usable endpoint).
          final List<InternetAddress> usable = result
              .where((InternetAddress ip) =>
                  !ip.isLoopback &&
                  !ip.isLinkLocal &&
                  ip.address != '0.0.0.0' &&
                  ip.address != '::' &&
                  !ip.address.startsWith('10.10.34.') &&
                  !ip.address
                      .toLowerCase()
                      .startsWith('2001:4188:2:600:10:10:34:'))
              .toList()
            ..sort((InternetAddress a, InternetAddress b) =>
                (a.type == InternetAddressType.IPv4 ? 0 : 1)
                    .compareTo(b.type == InternetAddressType.IPv4 ? 0 : 1));
          if (!finished && usable.isNotEmpty) {
            addresses[host] = usable.first.address;
          }
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
      <String>[
        for (int i = 0; i < links.length; i++)
          parsed[i]?.render(addresses[parsed[i]!.host.toLowerCase()]) ??
              links[i],
      ],
      resolvedHosts: addresses.length,
      unresolvedHosts: resolveEndpoints ? hosts.length - addresses.length : 0,
    );
  }
}

class PreparedLinks {
  const PreparedLinks(
    this.links, {
    required this.resolvedHosts,
    required this.unresolvedHosts,
  });

  final List<String> links;
  final int resolvedHosts;
  final int unresolvedHosts;
}

class _EndpointLink {
  _EndpointLink(this.uri, this.data, this.host, {this.fragment = ''});

  final Uri uri;
  final Map<String, dynamic>? data;
  final String host;
  final String fragment;

  static const Set<String> _v2raySchemes = <String>{
    'vless',
    'svless',
    'vmess',
    'svmess',
    'trojan',
    'strojan',
  };

  static const Set<String> _naiveSchemes = <String>{
    'naive',
    'naive+https',
    'naive+quic',
  };

  static const Set<String> _tlsOnlySchemes = <String>{
    'naive',
    'naive+https',
    'naive+quic',
    'anytls',
    'tuic',
    'hysteria2',
    'hy2',
    'hysteria',
  };

  static const Set<String> _supportedUriSchemes = <String>{
    'vless',
    'svless',
    'trojan',
    'strojan',
    'ss',
    'ssh',
    'tuic',
    'hysteria2',
    'hy2',
    'hysteria',
    'naive',
    'naive+https',
    'naive+quic',
    'anytls',
  };

  String get _scheme => uri.scheme.toLowerCase();

  bool get canBootstrap {
    if (!_v2raySchemes.contains(_scheme)) {
      return true;
    }
    final Map<String, dynamic> values = data ??
        <String, dynamic>{
          for (final MapEntry<String, String> entry
              in uri.queryParameters.entries)
            LinkPreparation._key(entry.key): entry.value,
        };
    final String transport = '${values['net'] ?? values['type'] ?? ''}';
    // Plain gRPC has no share-link authority override in the pinned parser.
    // Keep its endpoint name rather than silently changing HTTP/2 :authority.
    return transport != 'grpc' || _hasTls(values);
  }

  bool _hasTls(Map<String, dynamic> values) =>
      values['tls'] == 'tls' ||
      values['security'] == 'tls' ||
      values['security'] == 'reality' ||
      ((_scheme == 'trojan' || _scheme == 'strojan') &&
          !values.containsKey('security') &&
          '${values['tls'] ?? ''}'.isEmpty);

  static _EndpointLink? parse(String link) {
    try {
      final String trimmed = link.trim();
      if (trimmed.startsWith('vmess://') || trimmed.startsWith('svmess://')) {
        final int sep = trimmed.indexOf('://');
        final String scheme = trimmed.substring(0, sep).toLowerCase();
        final String rest = trimmed.substring(sep + 3);
        final int hash = rest.indexOf('#');
        final String payload = hash < 0 ? rest : rest.substring(0, hash);
        final String frag = hash < 0 ? '' : rest.substring(hash + 1);
        final Object? decoded =
            jsonDecode(utf8.decode(base64.decode(base64.normalize(payload))));
        if (decoded is! Map<String, dynamic> || decoded['add'] is! String) {
          return null;
        }
        return _EndpointLink(
          Uri(scheme: scheme),
          decoded,
          decoded['add'] as String,
          fragment: frag,
        );
      }
      final Uri uri = Uri.parse(trimmed.replaceAll('&amp;', '&'));
      if (!_supportedUriSchemes.contains(uri.scheme.toLowerCase())) {
        return null;
      }
      if (!uri.hasAuthority || uri.host.isEmpty) return null;
      // Validate percent-encoding now so one malformed link cannot abort the pool.
      uri.queryParameters;
      return _EndpointLink(uri, null, uri.host);
    } on Exception {
      return null;
    }
  }

  static String _partKey(String part) =>
      LinkPreparation._key(Uri.decodeQueryComponent(part.split('=').first));

  String render(String? address) {
    if (!canBootstrap) address = null;
    if (data != null) {
      final Map<String, dynamic> result = Map<String, dynamic>.of(data!);
      result.removeWhere((String key, dynamic _) =>
          LinkPreparation._muxKeys.contains(LinkPreparation._key(key)));
      if (address != null) {
        _preserveV2RayNames(result);
        result['add'] = address;
      }
      final String encoded =
          '$_scheme://${base64Encode(utf8.encode(jsonEncode(result)))}';
      return fragment.isEmpty ? encoded : '$encoded#$fragment';
    }

    // Retain raw encoding, duplicate parameters, extra/xmux and credentials.
    // Remove optional protocol mux (matching mux.enable=false) and normalize
    // protocol-specific query parameters required by the bundled core.
    final List<String> query =
        uri.query.isEmpty ? <String>[] : uri.query.split('&');
    query.removeWhere(
      (String part) => LinkPreparation._muxKeys.contains(_partKey(part)),
    );

    if (_naiveSchemes.contains(_scheme)) {
      query.removeWhere((String part) =>
          LinkPreparation._naiveRejectedTlsKeys.contains(_partKey(part)));
    } else if (_scheme == 'ss') {
      _normalizeShadowsocksPlugin(query);
    }

    if (address != null) {
      final Map<String, dynamic> originalNames = <String, dynamic>{
        for (final MapEntry<String, List<String>> entry
            in uri.queryParametersAll.entries)
          LinkPreparation._key(entry.key): entry.value.join(','),
      };
      if (_v2raySchemes.contains(_scheme)) {
        final Map<String, dynamic> names =
            Map<String, dynamic>.of(originalNames);
        _preserveV2RayNames(names);
        for (final String key in <String>['sni', 'host']) {
          if ('${originalNames[key] ?? ''}'.trim().isEmpty &&
              names.containsKey(key)) {
            query.removeWhere((String part) => _partKey(part) == key);
            query.add('$key=${Uri.encodeQueryComponent('${names[key]}')}');
          }
        }
      } else if (_tlsOnlySchemes.contains(_scheme)) {
        final String explicitSni =
            '${originalNames['sni'] ?? originalNames['servername'] ?? originalNames['peer'] ?? ''}'
                .trim();
        if (explicitSni.isEmpty) {
          query.removeWhere((String part) => _partKey(part) == 'sni');
          query.add('sni=${Uri.encodeQueryComponent(host)}');
        }
      }
      // `ss` and `ssh` do not use TLS SNI or V2Ray transport Host headers;
      // replacing the endpoint IP preserves their keys/plugins untouched.
    }

    String rendered =
        uri.replace(host: address, query: query.join('&')).toString();
    if (query.isEmpty) {
      rendered = rendered.replaceFirst('?#', '#');
      if (rendered.endsWith('?')) {
        rendered = rendered.substring(0, rendered.length - 1);
      }
    }
    return rendered;
  }

  /// Folds split panel query parameters (`plugin=obfs-local&obfs=http&obfs-host=...`)
  /// into standard SIP002 `plugin=obfs-local;obfs=http;obfs-host=...` so
  /// `ray2sing` passes the full option string to `sip003.ObfsLocal`.
  void _normalizeShadowsocksPlugin(List<String> query) {
    final Map<String, String> params = <String, String>{
      for (final MapEntry<String, String> entry in uri.queryParameters.entries)
        LinkPreparation._key(entry.key): entry.value,
    };
    final String plugin = (params['plugin'] ?? '').trim();
    final String pluginOpts = (params['pluginopts'] ?? '').trim();
    if (plugin.isNotEmpty && !plugin.contains(';') && pluginOpts.isEmpty) {
      final List<String> opts = <String>[];
      final String obfs = (params['obfs'] ?? '').trim();
      final String obfsHost = (params['obfshost'] ?? '').trim();
      final String mode = (params['mode'] ?? '').trim();
      final String path = (params['path'] ?? '').trim();
      if (obfs.isNotEmpty) {
        opts.add('obfs=$obfs');
      }
      if (obfsHost.isNotEmpty) {
        opts.add('obfs-host=$obfsHost');
      }
      if (mode.isNotEmpty && plugin.contains('v2ray')) {
        opts.add('mode=$mode');
      }
      if (path.isNotEmpty && plugin.contains('v2ray')) {
        opts.add('path=$path');
      }
      if (opts.isNotEmpty) {
        final String merged = '$plugin;${opts.join(';')}';
        query.removeWhere((String part) {
          final String k = _partKey(part);
          return k == 'plugin' || k == 'obfs' || k == 'obfshost';
        });
        query.insert(0, 'plugin=${Uri.encodeQueryComponent(merged)}');
      }
    } else if (plugin.isEmpty && !params.containsKey('uot')) {
      final String uot = (params['udpovertcp'] ?? '').trim().toLowerCase();
      if (uot == 'true' || uot == '1') {
        query.add('uot=1');
      }
    }
  }

  void _preserveV2RayNames(Map<String, dynamic> values) {
    // Match ray2sing's SNI fallback: explicit SNI, first HTTP host, endpoint.
    // Preserve it before replacing the endpoint by an IP; never weaken TLS.
    if ('${values['sni'] ?? ''}'.trim().isEmpty) {
      final String transportHost =
          '${values['host'] ?? ''}'.split(',').first.trim();
      final Uri? authority = Uri.tryParse('https://$transportHost');
      values['sni'] =
          transportHost.isEmpty ? host : (authority?.host ?? transportHost);
    }
    String transport = '${values['net'] ?? values['type'] ?? ''}'.toLowerCase();
    if ((transport == 'tcp' || transport == 'raw') &&
        (values['headertype'] == 'http' || values['type'] == 'http')) {
      transport = 'http';
    }
    final bool tls = _hasTls(values);
    final int port = data == null
        ? (uri.hasPort ? uri.port : 443)
        : int.tryParse('${values['port']}') ?? 443;
    final String authority =
        host.contains(':') ? '[$host]:$port' : '$host:$port';
    if ('${values['host'] ?? ''}'.isEmpty) {
      // Preserve the pinned core's transport-specific Host fallback, including
      // ports. XHTTP/HTTPUpgrade over TLS already fall back to preserved SNI;
      // overriding them with the endpoint would break CDN virtual-host routing.
      if (<String>['ws', 'http', 'h2'].contains(transport) ||
          (transport == 'httpupgrade' && !tls)) {
        values['host'] = authority;
      } else if (<String>['xhttp', 'splithttp'].contains(transport) && !tls) {
        values['host'] = host;
      }
    }
  }
}
