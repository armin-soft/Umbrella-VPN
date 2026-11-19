import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/data/parsers.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/vpn/link_preparation.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

/// آزمون خواندن اشتراکی که سرور می دهد: قالب از روی خود پاسخ تشخیص داده
/// می شود و هیچ نشانی از کاربر گرفته نمی شود.
void main() {
  const String uuid = '11111111-2222-3333-4444-555555555555';

  test('فهرست لینک استاندارد داخل base64 خوانده می شود', () {
    const String list =
        'vless://$uuid@1.2.3.4:443?type=ws&security=tls&sni=a.example.com&path=%2Fws#Tehran-1';
    final String body = base64.encode(utf8.encode(list));

    final ParseReport report = SubscriptionParser.parseAuto(body, 'user');

    expect(report.nodes, hasLength(1));
    final VpnNode node = report.nodes.first;
    expect(node.protocol, NodeProtocol.vless);
    expect(node.host, '1.2.3.4');
    expect(node.port, 443);
    expect(node.sourceId, 'user');
  });

  test('لینک های استاندارد بدون base64 هم خوانده می شوند', () {
    const String body =
        'vless://$uuid@1.2.3.4:443?type=ws&security=tls#A\n'
        'trojan://pass@5.6.7.8:8443?security=tls&sni=b.example.com#B';

    final ParseReport report = SubscriptionParser.parseAuto(body, 'user');

    expect(report.nodes, hasLength(2));
    expect(report.nodes[1].protocol, NodeProtocol.trojan);
    expect(report.nodes[1].port, 8443);
  });

  test('پاسخ کلش متا (YAML) تشخیص داده می شود', () {
    const String body = '''
proxies:
  - name: Clash-1
    type: vless
    server: 5.6.7.8
    port: 8443
    uuid: $uuid
    tls: true
    network: ws
''';

    final ParseReport report = SubscriptionParser.parseAuto(body, 'user');

    expect(report.nodes, hasLength(1));
    expect(report.nodes.first.host, '5.6.7.8');
    expect(report.nodes.first.port, 8443);
  });

  test('پیکربندی وایرگارد تشخیص داده می شود', () {
    const String body = '''
[Interface]
PrivateKey = YWJjZGVmZ2hpamtsbW5vcA==
Address = 10.66.0.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = cXJzdHV2d3h5ejEyMzQ1Ng==
Endpoint = 9.9.9.9:51820
AllowedIPs = 0.0.0.0/0
''';

    final ParseReport report = SubscriptionParser.parseAuto(body, 'user');

    expect(report.nodes, hasLength(1));
    expect(report.nodes.first.protocol, NodeProtocol.wireguard);
    expect(report.nodes.first.host, '9.9.9.9');
    expect(report.nodes.first.port, 51820);
  });

  test('پیکربندی وایرگارد داخل base64 هم خوانده می شود', () {
    const String ini = '''
[Interface]
PrivateKey = YWJjZGVmZ2hpamtsbW5vcA==
Address = 10.66.0.2/32

[Peer]
PublicKey = cXJzdHV2d3h5ejEyMzQ1Ng==
Endpoint = 9.9.9.9:51820
''';
    final String body = base64.encode(utf8.encode(ini));

    final ParseReport report = SubscriptionParser.parseAuto(body, 'user');

    expect(report.nodes, hasLength(1));
    expect(report.nodes.first.protocol, NodeProtocol.wireguard);
    expect(report.nodes.first.host, '9.9.9.9');
  });

  test('شناسه کلش در فیلد id هم قرار می گیرد تا ایکس ری بخواند', () {
    const String body = '''
proxies:
  - name: Clash-VLESS
    type: vless
    server: 5.6.7.8
    port: 443
    uuid: $uuid
    servername: cdn.example.com
    tls: true
''';

    final ParseReport report = SubscriptionParser.parseAuto(body, 'user');

    expect(report.nodes, hasLength(1));
    final VpnNode node = report.nodes.first;
    expect(node.params['id'], uuid);
    expect(node.params['sni'], 'cdn.example.com');
  });

  test('پاسخ خالی خطای روشن می دهد و سرور جعلی نمی سازد', () {
    final ParseReport report = SubscriptionParser.parseAuto('   ', 'user');

    expect(report.nodes, isEmpty);
    expect(report.problems, isNotEmpty);
  });

  test('پاسخ نامفهوم سرور هیچ سروری نمی سازد', () {
    final ParseReport report =
        SubscriptionParser.parseAuto('<html>not found</html>', 'user');

    expect(report.nodes, isEmpty);
    expect(report.problems, isNotEmpty);
  });

  group('فایل سینگ باکس (full-singbox.json)', () {
    const String singbox = '''
    {
      "outbounds": [
        {"type": "selector", "tag": "select", "outbounds": ["proxy"]},
        {"type": "vless", "tag": "proxy", "server": "de1.example.com",
         "server_port": 443, "uuid": "9b9d9f5d-9841-45bf-a6b9-0479de273c11",
         "tls": {"enabled": true, "server_name": "de1.example.com"},
         "transport": {"type": "ws", "path": "/ws", "headers": {"Host": "de1.example.com"}}},
        {"type": "direct", "tag": "direct"}
      ]
    }
    ''';

    test('خروجی سینگ باکس به سرور قابل اتصال تبدیل می شود', () {
      final ParseReport report =
          SubscriptionParser.parseSingBox(singbox, 'user-full-singbox.json');
      expect(report.nodes, hasLength(1));
      final VpnNode node = report.nodes.first;
      expect(node.host, 'de1.example.com');
      expect(node.port, 443);
      expect(node.protocol, NodeProtocol.vless);
      expect(node.params['id'], '9b9d9f5d-9841-45bf-a6b9-0479de273c11');
      expect(node.params['network'], 'ws');
      expect(node.params['path'], '/ws');
    });

    test('direct و selector و block سرور حساب نمی شوند', () {
      final ParseReport report = SubscriptionParser.parseSingBox(
        '{"outbounds":[{"type":"direct","tag":"d"},{"type":"block","tag":"b"}]}',
        'n',
      );
      expect(report.nodes, isEmpty);
      expect(report.problems, isNotEmpty);
    });

    test('فایل سینگ باکس در تشخیص خودکار هم خوانده می شود', () {
      final ParseReport report =
          SubscriptionParser.parseAuto(singbox, 'user-full-singbox.json');
      expect(report.nodes, hasLength(1));
    });
  });

  group('فایل های مستقیم پنل', () {
    test('فهرست Base64 همان لینک های استاندارد را می دهد', () {
      const String line =
          'vless://9b9d9f5d-9841-45bf-a6b9-0479de273c11@ca1.example.com:443'
          '?security=tls&sni=ca1.example.com&type=ws&path=%2Fws#Canada';
      final String encoded = base64Encode(utf8.encode(line));
      final ParseReport report =
          SubscriptionParser.parseAuto(encoded, 'user-sub64-');
      expect(report.nodes, hasLength(1));
      expect(report.nodes.first.host, 'ca1.example.com');
    });

    test('فایل وایرگارد مستقیم (بدون پرس وجو) خوانده می شود', () {
      const String wg = '''
[Interface]
PrivateKey = aGVsbG8=
Address = 10.0.0.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = d29ybGQ=
Endpoint = wg.example.com:51820
AllowedIPs = 0.0.0.0/0
''';
      final ParseReport report =
          SubscriptionParser.parseAuto(wg, 'user-wireguard');
      expect(report.nodes, isNotEmpty);
      final VpnNode node = report.nodes.first;
      expect(node.protocol, NodeProtocol.wireguard);
      expect(node.host, 'wg.example.com');
      expect(node.port, 51820);
      expect(node.params['publicKey'], 'd29ybGQ=');
      expect(VpnController.usable(node), isTrue);
    });

    test('خروجی کامل مسیر `/sub/` با هر ۹ پروتکل بدون اتلاف و بدون خطا خوانده و نرمال می شود', () async {
      const String subId = '00000000-0000-4000-8000-000000000042';
      // Synthetic SS2022 key containing both `+` and `/` so base64 userInfo decoding
      // never breaks host parsing.
      const String ssUser =
          'MjAyMi1ibGFrZTMtYWVzLTI1Ni1nY206Ky84K0FBRUNBd1FGQmdjSUNRb0xEQTBPRHhBUkVoTVVGUllYR0JrYUd4dz06UC83N0Nnc01EUTRQRUJFU0V4UVZGaGNZR1JvYkhCMGVIeUFoSWlNa0pTWT0=';
      const String sshPk =
          '-----BEGIN%20OPENSSH%20PRIVATE%20KEY-----'
          'b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZWQyNTUxOQAAACAmSNL4l8dIef4GYSZPSsyAOWHWkRewEPH4wPmYxRDjzwAAAIg8nAPcPJwD3AAAAAtzc2gtZWQyNTUxOQAAACAmSNL4l8dIef4GYSZPSsyAOWHWkRewEPH4wPmYxRDjzwAAAEDq%2FGSaM6bh5FjaXbl259%2FcSf2PwIlmeHrDklne%2BnnlcyZI0viXx0h5%2FgZhJk9KzIA5YdaRF7AQ8fjA%2BZjFEOPPAAAAAAECAwQF'
          '-----END%20OPENSSH%20PRIVATE%20KEY-----';
      const String sshHk =
          'ssh-ed25519%20AAAAC3NzaC1lZDI1NTE5AAAAICZI0viXx0h5%2FgZhJk9KzIA5YdaRF7AQ8fjA%2BZjFEOPP%2C%0A';
      final String vmessXhttp = base64Encode(utf8.encode(jsonEncode(<String, dynamic>{
        'v': '2',
        'ps': 'سرور آمبرلا tls_h2 xhttp dl=h2 vmess',
        'add': 'edge.umbrella.invalid',
        'port': 443,
        'id': subId,
        'aid': 0,
        'scy': 'auto',
        'net': 'xhttp',
        'type': 'packet-up',
        'host': 'edge.umbrella.invalid',
        'path': '/xhttp-vmess',
        'tls': 'tls',
        'sni': 'edge.umbrella.invalid',
        'alpn': 'h2',
        'fp': 'chrome',
        'extra': <String, dynamic>{
          'scMaxEachPostBytes': 1000000,
          'downloadSettings': <String, dynamic>{
            'address': 'dl.umbrella.invalid',
            'port': 443,
            'network': 'xhttp',
            'security': 'tls',
            'tlsSettings': <String, dynamic>{
              'serverName': 'dl.umbrella.invalid',
              'alpn': <String>['h2'],
              'fingerprint': 'chrome',
            },
            'xhttpSettings': <String, dynamic>{
              'path': '/xhttp-vmess',
              'host': 'dl.umbrella.invalid',
              'mode': 'auto',
            },
          },
        },
      })));
      final String subBody = <String>[
        'trojan://1@127.0.0.1?sni=fake_ip_for_sub_link#%F0%9F%91%A4%20TestUser',
        '#Watashi auto ip: 198.51.100.10',
        'vless://$subId@direct.umbrella.invalid:443?sni=www.speedtest.net&security=reality&pbk=AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA&sid=01234567&type=tcp&flow=xtls-rprx-vision&fp=chrome#Reality%20VLESS',
        'vless://$subId@ProxY.uMbrella.invalid:443?sni=proxy.umbrella.invalid&type=httpupgrade&security=tls&path=%2Fup&host=proxy.umbrella.invalid&headers=%7B%27User-Agent%27%3A%20%27Mozilla%2F5.0%27%7D&fp=chrome#HTTPUpgrade%20VLESS',
        'vmess://$vmessXhttp',
        'trojan://$subId@direct.umbrella.invalid:443?sni=direct.umbrella.invalid&type=grpc&security=tls&mode=gun&serviceName=%2Fgrpc&authority=direct.umbrella.invalid&alpn=h2&fp=chrome#gRPC%20Trojan',
        'ss://$ssUser@direct.umbrella.invalid:20443?udp-over-tcp=true#Direct%20SS2022',
        'ss://$ssUser@direct.umbrella.invalid:443?plugin=obfs-local&obfs-host=www.wechat.com&obfs=http&udp-over-tcp=true#FakeTLS%20SS2022',
        'ssh://$subId@direct.umbrella.invalid:55240/?file=ssh&hk=$sshHk&pk=$sshPk#Direct%20SSH',
        'tuic://$subId:$subId@direct.umbrella.invalid:54053?congestion_control=bbr&udp_relay_mode=native&sni=www.speedtest.net&alpn=h3#Direct%20TUIC',
        'hysteria2://$subId@direct.umbrella.invalid:443?obfs=salamander&obfs-password=testobfs&sni=www.speedtest.net&alpn=h3&mport=61001-62000#Direct%20Hysteria2',
        'naive://$subId@direct.umbrella.invalid:443?sni=direct.umbrella.invalid&type=custom&security=tls&alpn=http%2F1.1&fp=chrome#Direct%20Naive',
        'anytls://$subId@direct.umbrella.invalid:443/?alpn=http%2F1.1&sni=direct.umbrella.invalid#Direct%20AnyTLS',
      ].join('\n');

      final ParseReport report = SubscriptionParser.parse(
        subBody,
        const SubscriptionSource(
          id: 'user-sub',
          title: 'اشتراک خودکار',
          url: 'https://user.umbrella-server.ir/secret/00000000-0000-4000-8000-000000000042/sub/',
          format: SubscriptionFormat.xray,
          icon: 'auto',
          personal: true,
        ),
      );
      expect(report.problems, isEmpty);
      expect(report.nodes, hasLength(11));

      final Set<NodeProtocol> protocols =
          report.nodes.map((VpnNode n) => n.protocol).toSet();
      expect(
        protocols,
        containsAll(<NodeProtocol>[
          NodeProtocol.vless,
          NodeProtocol.vmess,
          NodeProtocol.trojan,
          NodeProtocol.shadowsocks,
          NodeProtocol.ssh,
          NodeProtocol.tuic,
          NodeProtocol.hysteria2,
          NodeProtocol.naive,
          NodeProtocol.anytls,
        ]),
      );

      for (final VpnNode node in report.nodes) {
        expect(VpnController.usable(node), isTrue, reason: '${node.protocol}: ${node.name}');
        expect(VpnController.linkFor(node), isNotEmpty, reason: node.name);
      }

      // NaiveProxy link strips `alpn` and `fp` (fatal in sing-box naive) while preserving `sni`.
      final VpnNode naive =
          report.nodes.firstWhere((VpnNode n) => n.protocol == NodeProtocol.naive);
      final Uri naiveUri = Uri.parse(VpnController.linkFor(naive));
      expect(naiveUri.queryParameters.containsKey('alpn'), isFalse);
      expect(naiveUri.queryParameters.containsKey('fp'), isFalse);
      expect(naiveUri.queryParameters['sni'], 'direct.umbrella.invalid');

      // Shadowsocks obfs-local folds split `obfs` and `obfs-host` into SIP002 `plugin`,
      // and plain SS2022 translates `udp-over-tcp=true` to `uot=1`.
      final List<VpnNode> ssNodes = report.nodes
          .where((VpnNode n) => n.protocol == NodeProtocol.shadowsocks)
          .toList();
      expect(ssNodes, hasLength(2));
      final Uri plainSsUri = Uri.parse(VpnController.linkFor(ssNodes[0]));
      expect(plainSsUri.queryParameters['uot'], '1');
      final Uri fakeTlsSsUri = Uri.parse(VpnController.linkFor(ssNodes[1]));
      expect(
        fakeTlsSsUri.queryParameters['plugin'],
        'obfs-local;obfs=http;obfs-host=www.wechat.com',
      );
      expect(fakeTlsSsUri.queryParameters.containsKey('uot'), isFalse);

      // DNS IP bootstrap resolves all 9 protocols while keeping TLS SNI untouched
      // and never adding spurious `sni`/`host` parameters to `ss` or `ssh`.
      final PreparedLinks prepared = await LinkPreparation.prepare(
        report.nodes.map(VpnController.linkFor).toList(),
        lookup: (_) async => <InternetAddress>[InternetAddress('198.51.100.25')],
      );
      expect(prepared.links, hasLength(11));
      expect(prepared.resolvedHosts, greaterThanOrEqualTo(3));
      final Uri resolvedSsh = Uri.parse(
        prepared.links.firstWhere((String l) => l.startsWith('ssh://')),
      );
      expect(resolvedSsh.host, '198.51.100.25');
      expect(resolvedSsh.port, 55240);
      expect(resolvedSsh.queryParameters.containsKey('sni'), isFalse);
      expect(resolvedSsh.queryParameters.containsKey('host'), isFalse);
      expect(resolvedSsh.queryParameters['pk'], startsWith('-----BEGIN OPENSSH PRIVATE KEY-----'));

      final Uri resolvedNaive = Uri.parse(
        prepared.links.firstWhere((String l) => l.startsWith('naive://')),
      );
      expect(resolvedNaive.host, '198.51.100.25');
      expect(resolvedNaive.queryParameters['sni'], 'direct.umbrella.invalid');
      expect(resolvedNaive.queryParameters.containsKey('alpn'), isFalse);
      expect(resolvedNaive.queryParameters.containsKey('fp'), isFalse);
      expect(resolvedNaive.queryParameters.containsKey('host'), isFalse);

      final Uri resolvedAnytls = Uri.parse(
        prepared.links.firstWhere((String l) => l.startsWith('anytls://')),
      );
      expect(resolvedAnytls.host, '198.51.100.25');
      expect(resolvedAnytls.queryParameters['sni'], 'direct.umbrella.invalid');
    });
  });
}
