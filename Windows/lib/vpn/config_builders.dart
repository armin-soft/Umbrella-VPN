import 'dart:convert';

import '../core/app_config.dart';
import '../core/utils.dart';
import '../models/models.dart';

/// ساخت پیکربندی سینگ باکس برای تونل کامل (TUN) و همه پروتکل ها.
class SingBoxConfig {
  const SingBoxConfig._();

  static Map<String, dynamic> build({
    required VpnNode node,
    required AppSettings settings,
    Map<String, dynamic>? outboundOverride,
    List<Map<String, dynamic>> extraInbounds = const <Map<String, dynamic>>[],
  }) {
    final Map<String, dynamic> outbound =
        outboundOverride ?? outboundFor(node, settings);
    return <String, dynamic>{
      'log': <String, dynamic>{
        'level': settings.logLevel,
        'timestamp': true,
      },
      'dns': _dns(settings),
      'inbounds': <Map<String, dynamic>>[
        _tunInbound(settings),
        ...extraInbounds,
      ],
      'outbounds': <Map<String, dynamic>>[
        outbound,
        <String, dynamic>{'type': 'direct', 'tag': 'direct'},
        <String, dynamic>{'type': 'block', 'tag': 'block'},
      ],
      'route': _route(settings),
      'experimental': <String, dynamic>{
        'cache_file': <String, dynamic>{
          'enabled': true,
          'store_fakeip': false,
        },
      },
    };
  }

  static String encode(Map<String, dynamic> config) =>
      const JsonEncoder.withIndent('  ').convert(config);

  static Map<String, dynamic> _tunInbound(AppSettings settings) {
    final List<String> addresses = <String>[AppConfig.tunAddress];
    if (!settings.blockIpv6) {
      addresses.add(AppConfig.tunAddress6);
    }
    return <String, dynamic>{
      'type': 'tun',
      'tag': 'tun-in',
      'interface_name': 'Umbrella-Tunnel',
      'address': addresses,
      'mtu': settings.mtu > 0 ? settings.mtu : AppConfig.defaultMtu,
      'auto_route': true,
      'strict_route': settings.strictRoute,
      'stack': settings.tunStack.name,
      'endpoint_independent_nat': true,
      'udp_timeout': '5m',
    };
  }

  static Map<String, dynamic> _dns(AppSettings settings) {
    return <String, dynamic>{
      'servers': <Map<String, dynamic>>[
        <String, dynamic>{
          'tag': 'dns-remote',
          'address': settings.turboMode
              ? 'https://1.1.1.1/dns-query'
              : 'https://dns.google/dns-query',
          'detour': 'proxy',
        },
        <String, dynamic>{
          'tag': 'dns-local',
          'address': '223.5.5.5',
          'detour': 'direct',
        },
      ],
      'final': settings.dnsOverTunnel ? 'dns-remote' : 'dns-local',
      'strategy': settings.blockIpv6 ? 'ipv4_only' : 'prefer_ipv4',
    };
  }

  static Map<String, dynamic> _route(AppSettings settings) {
    final List<Map<String, dynamic>> rules = <Map<String, dynamic>>[
      <String, dynamic>{'action': 'sniff'},
      <String, dynamic>{'protocol': 'dns', 'action': 'hijack-dns'},
      <String, dynamic>{'ip_is_private': true, 'outbound': 'direct'},
    ];
    if (settings.blockIpv6) {
      rules.add(<String, dynamic>{'ip_version': 6, 'action': 'reject'});
    }
    return <String, dynamic>{
      'rules': rules,
      'final': 'proxy',
      'auto_detect_interface': true,
      'default_mark': 0,
    };
  }

  /// تبدیل گره به خروجی سینگ باکس.
  static Map<String, dynamic> outboundFor(VpnNode node, AppSettings settings) {
    final Map<String, dynamic> params = node.params;
    final String tag = 'proxy';
    switch (node.protocol) {
      case NodeProtocol.vless:
        return <String, dynamic>{
          'type': 'vless',
          'tag': tag,
          'server': node.host,
          'server_port': node.port,
          'uuid': JsonX.text(params['id']),
          if (JsonX.text(params['flow']).isNotEmpty) 'flow': JsonX.text(params['flow']),
          'packet_encoding': 'xudp',
          if (_tls(params) != null) 'tls': _tls(params),
          if (_transport(params) != null) 'transport': _transport(params),
        };
      case NodeProtocol.vmess:
        return <String, dynamic>{
          'type': 'vmess',
          'tag': tag,
          'server': node.host,
          'server_port': node.port,
          'uuid': JsonX.text(params['id']),
          'security': JsonX.text(params['security'], 'auto'),
          'alter_id': JsonX.integer(params['alterId']),
          'packet_encoding': 'xudp',
          if (_tls(params) != null) 'tls': _tls(params),
          if (_transport(params) != null) 'transport': _transport(params),
        };
      case NodeProtocol.trojan:
        return <String, dynamic>{
          'type': 'trojan',
          'tag': tag,
          'server': node.host,
          'server_port': node.port,
          'password': JsonX.text(params['password']),
          'tls': _tls(params) ??
              <String, dynamic>{
                'enabled': true,
                'server_name': JsonX.text(params['sni'], node.host),
              },
          if (_transport(params) != null) 'transport': _transport(params),
        };
      case NodeProtocol.shadowsocks:
        return <String, dynamic>{
          'type': 'shadowsocks',
          'tag': tag,
          'server': node.host,
          'server_port': node.port,
          'method': JsonX.text(params['method'], 'aes-256-gcm'),
          'password': JsonX.text(params['password']),
        };
      case NodeProtocol.wireguard:
      case NodeProtocol.amnezia:
        return <String, dynamic>{
          'type': 'wireguard',
          'tag': tag,
          'server': node.host,
          'server_port': node.port,
          'local_address': _addresses(params['address']),
          'private_key': JsonX.text(params['privateKey']),
          'peer_public_key': JsonX.text(params['publicKey']),
          if (JsonX.text(params['presharedKey']).isNotEmpty)
            'pre_shared_key': JsonX.text(params['presharedKey']),
          'mtu': JsonX.integer(params['mtu'], 1420),
        };
      case NodeProtocol.hysteria2:
        return <String, dynamic>{
          'type': 'hysteria2',
          'tag': tag,
          'server': node.host,
          'server_port': node.port,
          'password': JsonX.text(params['password']),
          if (JsonX.text(params['obfs']).isNotEmpty)
            'obfs': <String, dynamic>{
              'type': JsonX.text(params['obfs']),
              'password': JsonX.text(params['obfs-password'] ?? params['obfsPassword']),
            },
          'tls': _tls(params) ??
              <String, dynamic>{
                'enabled': true,
                'server_name': JsonX.text(params['sni'], node.host),
              },
        };
      case NodeProtocol.tuic:
        return <String, dynamic>{
          'type': 'tuic',
          'tag': tag,
          'server': node.host,
          'server_port': node.port,
          'uuid': JsonX.text(params['uuid']),
          'password': JsonX.text(params['password']),
          'congestion_control': JsonX.text(params['congestion_control'], 'bbr'),
          'tls': _tls(params) ??
              <String, dynamic>{
                'enabled': true,
                'server_name': JsonX.text(params['sni'], node.host),
              },
        };
      case NodeProtocol.socks:
        return <String, dynamic>{
          'type': 'socks',
          'tag': tag,
          'server': node.host,
          'server_port': node.port,
          'version': '5',
          'username': JsonX.text(params['username']),
          'password': JsonX.text(params['password']),
        };
      case NodeProtocol.mieru:
      case NodeProtocol.clash:
        return <String, dynamic>{
          'type': 'socks',
          'tag': tag,
          'server': '127.0.0.1',
          'server_port': AppConfig.socksPortChained,
          'version': '5',
        };
    }
  }

  /// آدرس های محلی وایرگارد هم به شکل فهرست و هم به شکل رشته با کاما می آیند.
  static List<String> _addresses(Object? value) {
    if (value is List<dynamic>) {
      return value
          .map((Object? item) => item.toString().trim())
          .where((String item) => item.isNotEmpty)
          .toList();
    }
    final String text = JsonX.text(value);
    if (text.isEmpty) {
      return <String>[];
    }
    return text
        .split(',')
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList();
  }

  static Map<String, dynamic>? _tls(Map<String, dynamic> params) {
    final String security = JsonX.text(params['security'] ?? params['tls']).toLowerCase();
    final String sni = JsonX.text(
      params['sni'] ?? params['servername'] ?? params['host'],
    );
    final bool reality = security == 'reality' || JsonX.text(params['pbk']).isNotEmpty;
    final bool enabled = security == 'tls' ||
        security == 'reality' ||
        security == 'xtls' ||
        JsonX.boolean(params['tls']) ||
        reality;
    if (!enabled && sni.isEmpty) {
      return null;
    }
    final Map<String, dynamic> tls = <String, dynamic>{
      'enabled': true,
      'server_name': sni,
      'insecure': JsonX.boolean(params['allowInsecure']),
      'utls': <String, dynamic>{
        'enabled': true,
        'fingerprint': JsonX.text(params['fp'] ?? params['fingerprint'], 'chrome'),
      },
    };
    final List<dynamic> alpn = JsonX.asList(params['alpn']);
    if (alpn.isNotEmpty) {
      tls['alpn'] = alpn.map((Object? item) => item.toString()).toList();
    } else {
      tls['alpn'] = <String>['h2', 'http/1.1'];
    }
    if (reality) {
      tls['reality'] = <String, dynamic>{
        'enabled': true,
        'public_key': JsonX.text(params['pbk'] ?? params['public-key']),
        'short_id': JsonX.text(params['sid'] ?? params['short-id']),
      };
    }
    return tls;
  }

  static Map<String, dynamic>? _transport(Map<String, dynamic> params) {
    final String network =
        JsonX.text(params['network'] ?? params['type']).toLowerCase();
    final String path = JsonX.text(params['path'], '/');
    final String host = JsonX.text(params['host']);
    switch (network) {
      case 'ws':
        return <String, dynamic>{
          'type': 'ws',
          'path': path.isEmpty ? '/' : path,
          if (host.isNotEmpty) 'headers': <String, String>{'Host': host},
          'max_early_data': 2048,
          'early_data_header_name': 'Sec-WebSocket-Protocol',
        };
      case 'grpc':
        return <String, dynamic>{
          'type': 'grpc',
          'service_name': JsonX.text(params['serviceName'] ?? params['path']),
        };
      case 'httpupgrade':
        return <String, dynamic>{
          'type': 'httpupgrade',
          'path': path.isEmpty ? '/' : path,
          if (host.isNotEmpty) 'headers': <String, String>{'Host': host},
        };
      case 'h2':
      case 'http':
        return <String, dynamic>{
          'type': 'http',
          'path': path.isEmpty ? '/' : path,
          if (host.isNotEmpty) 'host': <String>[host],
        };
      default:
        return null;
    }
  }

  /// خروجی محلی برای حالت زنجیره ای: تونل سینگ باکس به سوکس هسته دیگر.
  static Map<String, dynamic> localSocksOutbound(int port) => <String, dynamic>{
        'type': 'socks',
        'tag': 'proxy',
        'server': '127.0.0.1',
        'server_port': port,
        'version': '5',
      };
}

/// پیکربندی هسته ایکس ری (سوکس محلی) برای پروتکل های وی لس، وی مس، تروجان و
/// شادوساکس. تونل کامل را سینگ باکس می سازد و ایکس ری لایه پروتکل است.
class XrayConfig {
  const XrayConfig._();

  static String encode(VpnNode node, int socksPort) =>
      const JsonEncoder.withIndent('  ').convert(build(node, socksPort));

  static Map<String, dynamic> build(VpnNode node, int socksPort) {
    return <String, dynamic>{
      'log': <String, dynamic>{'loglevel': 'warning'},
      'inbounds': <Map<String, dynamic>>[
        <String, dynamic>{
          'tag': 'umbrella-socks',
          'listen': '127.0.0.1',
          'port': socksPort,
          'protocol': 'socks',
          'settings': <String, dynamic>{
            'auth': 'noauth',
            'udp': true,
            'ip': '127.0.0.1',
          },
          'sniffing': <String, dynamic>{
            'enabled': true,
            'destOverride': <String>['http', 'tls', 'quic'],
          },
        },
      ],
      'outbounds': <Map<String, dynamic>>[
        outbound(node),
        <String, dynamic>{'protocol': 'freedom', 'tag': 'direct'},
      ],
      'routing': <String, dynamic>{
        'domainStrategy': 'AsIs',
        'rules': <Map<String, dynamic>>[],
      },
    };
  }

  static Map<String, dynamic> outbound(VpnNode node) {
    final Map<String, dynamic> params = node.params;
    final Map<String, dynamic> stream = _stream(params, node);
    switch (node.protocol) {
      case NodeProtocol.vless:
        return <String, dynamic>{
          'tag': 'proxy',
          'protocol': 'vless',
          'settings': <String, dynamic>{
            'vnext': <Map<String, dynamic>>[
              <String, dynamic>{
                'address': node.host,
                'port': node.port,
                'users': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'id': JsonX.text(params['id']),
                    'encryption': 'none',
                    if (JsonX.text(params['flow']).isNotEmpty)
                      'flow': JsonX.text(params['flow']),
                  },
                ],
              },
            ],
          },
          'streamSettings': stream,
        };
      case NodeProtocol.vmess:
        return <String, dynamic>{
          'tag': 'proxy',
          'protocol': 'vmess',
          'settings': <String, dynamic>{
            'vnext': <Map<String, dynamic>>[
              <String, dynamic>{
                'address': node.host,
                'port': node.port,
                'users': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'id': JsonX.text(params['id']),
                    'alterId': JsonX.integer(params['alterId']),
                    'security': JsonX.text(params['security'], 'auto'),
                  },
                ],
              },
            ],
          },
          'streamSettings': stream,
        };
      case NodeProtocol.trojan:
        return <String, dynamic>{
          'tag': 'proxy',
          'protocol': 'trojan',
          'settings': <String, dynamic>{
            'servers': <Map<String, dynamic>>[
              <String, dynamic>{
                'address': node.host,
                'port': node.port,
                'password': JsonX.text(params['password']),
              },
            ],
          },
          'streamSettings': stream,
        };
      case NodeProtocol.shadowsocks:
        return <String, dynamic>{
          'tag': 'proxy',
          'protocol': 'shadowsocks',
          'settings': <String, dynamic>{
            'servers': <Map<String, dynamic>>[
              <String, dynamic>{
                'address': node.host,
                'port': node.port,
                'method': JsonX.text(params['method'], 'aes-256-gcm'),
                'password': JsonX.text(params['password']),
              },
            ],
          },
        };
      default:
        return <String, dynamic>{'protocol': 'freedom', 'tag': 'proxy'};
    }
  }

  static Map<String, dynamic> _stream(Map<String, dynamic> params, VpnNode node) {
    final String network =
        JsonX.text(params['network'] ?? params['type'], 'tcp').toLowerCase();
    final String security =
        JsonX.text(params['security'] ?? params['tls']).toLowerCase();
    final String sni = JsonX.text(params['sni'] ?? params['host'], node.host);
    final bool reality = security == 'reality' || JsonX.text(params['pbk']).isNotEmpty;
    final Map<String, dynamic> stream = <String, dynamic>{
      'network': network.isEmpty ? 'tcp' : network,
      'security': reality ? 'reality' : (security == 'tls' ? 'tls' : 'none'),
    };
    if (stream['security'] == 'tls' || stream['security'] == 'reality') {
      stream['tlsSettings'] = <String, dynamic>{
        'serverName': sni,
        'allowInsecure': JsonX.boolean(params['allowInsecure']),
        'fingerprint': JsonX.text(params['fp'], 'chrome'),
        if (JsonX.asList(params['alpn']).isNotEmpty)
          'alpn': JsonX.asList(params['alpn'])
              .map((Object? item) => item.toString())
              .toList(),
      };
    }
    if (reality) {
      stream['realitySettings'] = <String, dynamic>{
        'serverName': sni,
        'fingerprint': JsonX.text(params['fp'], 'chrome'),
        'publicKey': JsonX.text(params['pbk'] ?? params['public-key']),
        'shortId': JsonX.text(params['sid'] ?? params['short-id']),
        'spiderX': JsonX.text(params['spx'], '/'),
      };
    }
    if (network == 'ws') {
      stream['wsSettings'] = <String, dynamic>{
        'path': JsonX.text(params['path'], '/'),
        'headers': <String, dynamic>{
          'Host': JsonX.text(params['host'], sni),
        },
      };
    } else if (network == 'grpc') {
      stream['grpcSettings'] = <String, dynamic>{
        'serviceName': JsonX.text(params['serviceName'] ?? params['path']),
      };
    } else if (network == 'h2' || network == 'http') {
      stream['httpSettings'] = <String, dynamic>{
        'path': JsonX.text(params['path'], '/'),
        'host': <String>[JsonX.text(params['host'], sni)],
      };
    }
    return stream;
  }
}

/// پیکربندی کلاینت میرو.
class MieruConfig {
  const MieruConfig._();

  static String encode(VpnNode node, int socksPort) =>
      const JsonEncoder.withIndent('  ').convert(build(node, socksPort));

  static Map<String, dynamic> build(VpnNode node, int socksPort) {
    final Map<String, dynamic> params = node.params;
    final String transport = JsonX.text(params['transport'], 'TCP').toUpperCase();
    return <String, dynamic>{
      'profiles': <Map<String, dynamic>>[
        <String, dynamic>{
          'profileName': node.id,
          'user': <String, dynamic>{
            'name': JsonX.text(params['username']),
            'password': JsonX.text(params['password']),
          },
          'serverEndpoint': <String, dynamic>{
            'ipAddress': node.host,
            'portBindings': <Map<String, dynamic>>[
              <String, dynamic>{
                'port': node.port,
                'protocol': transport,
              },
            ],
          },
          'mtu': JsonX.integer(params['mtu'], 1400),
          if (JsonX.text(params['multiplexing']).isNotEmpty)
            'multiplexing': <String, dynamic>{
              'level': JsonX.text(params['multiplexing'], 'MULTIPLEXING_OFF'),
            },
        },
      ],
      'rpc': <String, dynamic>{'port': 0},
      'socks5Port': socksPort,
      'loggingLevel': 'INFO',
    };
  }
}
