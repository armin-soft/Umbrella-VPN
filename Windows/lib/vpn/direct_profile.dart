import 'dart:convert';

import '../core/utils.dart';
import '../models/models.dart';

/// Converts a direct panel profile to the pinned core's sing-box input.
/// This is a single-profile config: it must never be mixed with share links.
class DirectProfile {
  const DirectProfile._();

  static bool handles(VpnNode node) =>
      node.protocol == NodeProtocol.wireguard ||
      node.protocol == NodeProtocol.amnezia ||
      (node.protocol == NodeProtocol.mieru && node.raw.trim().startsWith('{'));

  static String encode(VpnNode node) {
    final Map<String, dynamic> p = node.params;
    const String tag = 'umbrella-direct-profile';
    if (node.protocol == NodeProtocol.mieru) {
      final List<dynamic> bindings = JsonX.asList(p['portBindings']);
      if (bindings.isEmpty) throw const FormatException('Missing mieru bindings');
      return jsonEncode(<String, dynamic>{
        'outbounds': <Object>[
          <String, dynamic>{
            'type': 'mieru', 'tag': tag, 'server': node.host,
            'username': JsonX.text(p['username']),
            'password': JsonX.text(p['password']),
            'portBindings': bindings,
            'multiplexing': JsonX.text(p['multiplexing'], 'MULTIPLEXING_OFF'),
            'handshake_mode': JsonX.text(p['handshakeMode'], 'HANDSHAKE_DEFAULT'),
          },
        ],
      });
    }
    final List<String> addresses = JsonX.asList(p['address'])
        .map((dynamic value) => value.toString()).where((String v) => v.isNotEmpty).toList();
    if (addresses.isEmpty) throw const FormatException('Missing tunnel address');
    final bool awg = node.protocol == NodeProtocol.amnezia;
    final Map<String, dynamic> peer = <String, dynamic>{
      'address': node.host, 'port': node.port,
      'public_key': JsonX.text(p['publicKey']),
      if (JsonX.text(p['presharedKey']).isNotEmpty)
        (awg ? 'preshared_key' : 'pre_shared_key'): JsonX.text(p['presharedKey']),
      'allowed_ips': JsonX.text(p['allowedIps'], '0.0.0.0/0, ::/0')
          .split(',').map((String s) => s.trim()).where((String s) => s.isNotEmpty).toList(),
      'persistent_keepalive_interval': JsonX.integer(p['keepalive'], 25),
    };
    final Map<String, dynamic> awgOptions = <String, dynamic>{};
    for (final String key in <String>['jc', 'jmin', 'jmax', 's1', 's2', 's3', 's4']) {
      if (p.containsKey(key)) {
        final int? value = int.tryParse('${p[key]}');
        if (value == null) throw const FormatException('Invalid Amnezia parameter');
        awgOptions[key] = value;
      }
    }
    for (final String key in <String>['h1', 'h2', 'h3', 'h4', 'i1', 'i2', 'i3', 'i4', 'i5']) {
      if (p.containsKey(key)) awgOptions[key] = '${p[key]}';
    }
    if (awg && awgOptions.isEmpty) throw const FormatException('Missing Amnezia parameters');
    return jsonEncode(<String, dynamic>{
      'outbounds': <Object>[],
      'endpoints': <Object>[
        <String, dynamic>{
          'type': awg ? 'awg' : 'wireguard', 'tag': tag,
          'address': addresses, 'private_key': JsonX.text(p['privateKey']),
          'mtu': JsonX.integer(p['mtu'], 1420), 'peers': <Object>[peer],
          if (awg) 'awg': awgOptions,
        },
      ],
    });
  }
}
