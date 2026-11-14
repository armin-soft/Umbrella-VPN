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
    int clashApiPort = 0,
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
        // پورت سنجش آمادگی تونل: با باز شدن این پورت، هسته واقعا بالا آمده
        // است. حالت تونل پورت پروکسی محلی ندارد، پس آمادگی از این راه
        // سنجیده می شود.
        if (clashApiPort > 0)
          'clash_api': <String, dynamic>{
            'external_controller': '127.0.0.1:$clashApiPort',
          },
      },
    };
  }

  static String encode(Map<String, dynamic> config) =>
      const JsonEncoder.withIndent('  ').convert(config);

  /// آیا سینگ باکس این نوع انتقال را می شناسد؟
  ///
  /// بیشتر سرورهای این سرویس از `xhttp` (همان split-http ایکس ری) استفاده می
  /// کنند و سینگ باکس آن را ندارد؛ اجرای سینگ باکس برای این سرورها فقط چند
  /// ثانیه تلف می کرد و در پایان «هیچ هسته ای تونل را بالا نیاورد» می داد.
  /// برای این سرورها مستقیم سراغ ایکس ری می رویم.
  static bool supportsTransport(VpnNode node) {
    final String network = JsonX.text(
      node.params['network'] ?? node.params['type'],
    ).toLowerCase();
    switch (network) {
      case 'xhttp':
      case 'splithttp':
      case 'kcp':
      case 'mkcp':
        return false;
      default:
        return true;
    }
  }

  /// حالت پروکسی محلی برای سرور وایرگارد.
  ///
  /// سینگ باکس وایرگارد را به شکل endpoint می شناسد؛ یک پورت مختلط محلی
  /// ساخته می شود و تونل وایرگارد خروجی آن است.
  static Map<String, dynamic> buildWireGuardProxy({
    required VpnNode node,
    required int port,
    required int mtu,
    bool tcpFastOpen = true,
  }) {
    final Map<String, dynamic> params = node.params;
    final List<String> addresses = _addresses(params['address']);
    final int keepalive = JsonX.integer(params['keepalive'], 25);
    return <String, dynamic>{
      'log': <String, dynamic>{'level': 'info', 'timestamp': true},
      'inbounds': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'mixed',
          'tag': 'mixed-in',
          'listen': '127.0.0.1',
          'listen_port': port,
          if (tcpFastOpen) 'tcp_fast_open': true,
        },
      ],
      'endpoints': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'wireguard',
          'tag': 'proxy',
          'system': false,
          'address': addresses.isEmpty
              ? <String>['10.0.0.2/32']
              : addresses,
          'private_key': JsonX.text(params['privateKey']),
          'mtu': JsonX.integer(params['mtu'], mtu > 0 ? mtu : 1420),
          'peers': <Map<String, dynamic>>[
            <String, dynamic>{
              'address': node.host,
              'port': node.port,
              'public_key': JsonX.text(params['publicKey']),
              if (JsonX.text(params['presharedKey']).isNotEmpty)
                'pre_shared_key': JsonX.text(params['presharedKey']),
              'allowed_ips': <String>['0.0.0.0/0', '::/0'],
              'persistent_keepalive_interval': keepalive,
            },
          ],
        },
      ],
      'outbounds': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'direct', 'tag': 'direct'},
      ],
      'route': <String, dynamic>{
        'rules': <Map<String, dynamic>>[
          <String, dynamic>{'action': 'sniff'},
          <String, dynamic>{'ip_is_private': true, 'outbound': 'direct'},
        ],
        'final': 'proxy',
        'auto_detect_interface': true,
      },
    };
  }

  /// حالت پروکسی محلی: یک inbound مختلط (http و socks روی یک پورت) و یک
  /// outbound به سرور. همان روشی که کلاینت ویندوز هیدیفای در حالت
  /// system proxy استفاده می کند.
  static Map<String, dynamic> buildProxy({
    required VpnNode node,
    required AppSettings settings,
    required int port,
    bool tcpFastOpen = true,
  }) {
    final Map<String, dynamic> outbound = outboundFor(node, settings);
    return <String, dynamic>{
      'log': <String, dynamic>{'level': 'info', 'timestamp': true},
      'inbounds': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'mixed',
          'tag': 'mixed-in',
          'listen': '127.0.0.1',
          'listen_port': port,
          if (tcpFastOpen) 'tcp_fast_open': true,
        },
      ],
      'outbounds': <Map<String, dynamic>>[
        outbound,
        <String, dynamic>{'type': 'direct', 'tag': 'direct'},
      ],
      'route': <String, dynamic>{
        'rules': <Map<String, dynamic>>[
          <String, dynamic>{'action': 'sniff'},
          <String, dynamic>{'ip_is_private': true, 'outbound': 'direct'},
        ],
        'final': 'proxy',
        'auto_detect_interface': true,
      },
    };
  }

  static Map<String, dynamic> _tunInbound(AppSettings settings) {
    final List<String> addresses = <String>[AppConfig.tunAddress];
    if (!settings.blockIpv6) {
      addresses.add(AppConfig.tunAddress6);
    }
    // بافرهای بزرگ تر و استک سیستم: همان تنظیماتی که سرعت بالای کلاینت
    // هیدیفای از آن می آید. mtu = 0 در سینگ باکس یعنی انتخاب خودکار که برای
    // tcp بهتر از عددهای بزرگ دستی است.
    //
    // ⚠️ gso و gso_max_size از سینگ باکس ۱.۱۱ به بعد حذف شده اند و نسخه
    // همراه این برنامه همان‌ها را با خطای «json: unknown field» رد می کند؛
    // همان خطایی که باعث می شد هیچ هسته ای تونل را بالا نیاورد. این کلیدها
    // هرگز نباید نوشته شوند. در عوض همان کاری که خود سینگ باکس در نسخه های
    // تازه انجام می دهد: فقط استک و mtu.
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
      'tcp_fast_open': true,
      'tcp_multi_path': false,
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

  /// چند سرویس روی یک اتصال (multiplexing).
  ///
  /// کلاینت هیدیفای همین را روشن می کند: هر درخواست جدید لازم نیست یک دست
  /// دادن TLS و TCP تازه بگیرد، پس هم سرعت بارگذاری صفحه بیشتر می شود و هم
  /// پینگ پایدارتر است. اگر سروری پشتیبانی نکند، اتصال مستقیم ادامه پیدا
  /// می کند و چیزی خراب نمی شود.
  static Map<String, dynamic>? _multiplex(
    Map<String, dynamic> params,
    NodeProtocol protocol,
  ) {
    // میرو و وایرگارد خودشان مدیر جریان هستند.
    if (protocol == NodeProtocol.mieru ||
        protocol == NodeProtocol.wireguard ||
        protocol == NodeProtocol.amnezia) {
      return null;
    }
    if (JsonX.text(params['multiplex']).toLowerCase() == 'off') {
      return null;
    }
    // روی انتقال های جریانی (gRPC، xhttp و websocket) چند سرویس روی یک اتصال
    // باعث خطای ۴۰۳ سرور می شود؛ خود هیدیفای هم برای همین سرورها mux را خاموش
    // می کند. پس همان کاری را می کنیم که سرور انتظار دارد.
    final String network =
        JsonX.text(params['network'] ?? params['type']).toLowerCase();
    if (network == 'grpc' ||
        network == 'xhttp' ||
        network == 'splithttp' ||
        network == 'ws' ||
        network == 'httpupgrade') {
      return null;
    }
    final int concurrency =
        JsonX.integer(params['mux'] ?? params['maxConnections'], 8);
    return <String, dynamic>{
      'enabled': true,
      'protocol': 'h2mux',
      'max_streams': concurrency > 0 ? concurrency : 8,
      'padding': true,
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
          if (_multiplex(params, node.protocol) != null)
            'multiplex': _multiplex(params, node.protocol),
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
          if (_multiplex(params, node.protocol) != null)
            'multiplex': _multiplex(params, node.protocol),
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
          if (_multiplex(params, node.protocol) != null)
            'multiplex': _multiplex(params, node.protocol),
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
          // میرو روی همین پورت سوکس محلی گوش می دهد؛ پورت هاست خود ایکس ری
          // (۲۰۸۰) اینجا اشتباه است و باعث حلقه می شود.
          'server_port': AppConfig.socksPortMieru,
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
    // سرورهایی که صریحا security=none دارند نباید لایه TLS بگیرند؛ پیش از این
    // فقط داشتن sni کافی بود و همان سرورهای بی TLS با دست دادن TLS ناموفق
    // می شدند (خطای 301 و «هیچ هسته ای تونل را بالا نیاورد»).
    if (!enabled) {
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
      // فقط همان چیزی که سرور اعلام کرده؛ تحمیل ALPN اضافی دست دادن TLS را
      // کند می کند و در برخی سرورها اتصال را کند یا ناموفق می کند.
      tls['alpn'] = alpn.map((Object? item) => item.toString()).toList();
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
      // ایکس اچ تی تی پی (نوع xhttp در اشتراک های هیدیفای): بیشتر سرورهای
      // این اشتراک از همین استفاده می کنند. سینگ باکس آن را با نوع http
      // می شناسد؛ اگر پشتیبانی نکند خودش خطا می دهد و هسته بعدی امتحان
      // می شود.
      case 'xhttp':
      case 'splithttp':
        return <String, dynamic>{
          'type': 'http',
          'path': path.isEmpty ? '/' : path,
          if (host.isNotEmpty) 'host': <String>[host],
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

  /// پل اچ تی تی پی برای هسته ای که فقط سوکس می دهد (مثل میرو).
  ///
  /// پروکسی سیستمی ویندوز فقط اچ تی تی پی را می فهمد؛ اگر به پورت سوکس وصل
  /// شود، برنامه ها «وصل» نشان می دهند ولی هیچ صفحه ای باز نمی شود. این
  /// پیکربندی یک پورت اچ تی تی پی می سازد و ترافیک را به سوکس محلی می فرستد.
  static String frontSocks(int socksPort) =>
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'log': <String, dynamic>{'loglevel': 'warning'},
        'inbounds': <Map<String, dynamic>>[
          <String, dynamic>{
            'tag': 'umbrella-http',
            'listen': '127.0.0.1',
            'port': AppConfig.httpPortXray,
            'protocol': 'http',
            'settings': <String, dynamic>{'allowTransparent': false},
          },
        ],
        'outbounds': <Map<String, dynamic>>[
          <String, dynamic>{
            'tag': 'proxy',
            'protocol': 'socks',
            'settings': <String, dynamic>{
              'servers': <Map<String, dynamic>>[
                <String, dynamic>{
                  'address': '127.0.0.1',
                  'port': socksPort,
                },
              ],
            },
          },
          <String, dynamic>{'tag': 'direct', 'protocol': 'freedom'},
        ],
      });

  static Map<String, dynamic> build(VpnNode node, int socksPort) {
    return <String, dynamic>{
      'log': <String, dynamic>{'loglevel': 'info'},
      'inbounds': <Map<String, dynamic>>[
        // پروکسی سیستمی ویندوز به این پورت وصل می شود.
        <String, dynamic>{
          'tag': 'umbrella-http',
          'listen': '127.0.0.1',
          'port': AppConfig.httpPortXray,
          'protocol': 'http',
          'settings': <String, dynamic>{'allowTransparent': false},
          'sniffing': <String, dynamic>{
            'enabled': true,
            'destOverride': <String>['http', 'tls', 'quic'],
          },
        },
        <String, dynamic>{
          'tag': 'umbrella-socks',
          'listen': '127.0.0.1',
          'port': socksPort,
          'protocol': 'socks',
          'settings': <String, dynamic>{
            'auth': 'noauth',
            'udp': true,
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
                    'id': JsonX.text(params['id'] ?? params['uuid']),
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
                    'id': JsonX.text(params['id'] ?? params['uuid']),
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
                'method': JsonX.text(
                  params['method'] ?? params['cipher'],
                  'aes-256-gcm',
                ),
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
    final String sni = JsonX.text(
      params['sni'] ?? params['servername'] ?? params['host'],
      node.host,
    );
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
    } else if (network == 'xhttp' || network == 'splithttp') {
      // ایکس اچ تی تی پی از ایکس ری ۲۵ شناخته می شود؛ همان مسیر و میزبان
      // سرور، بدون بازنویسی شبکه به tcp.
      stream['xhttpSettings'] = <String, dynamic>{
        'path': JsonX.text(params['path'], '/'),
        'host': JsonX.text(params['host'], sni),
        'mode': JsonX.text(params['mode'], 'auto'),
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
