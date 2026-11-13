import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/data/parsers.dart';
import 'package:umbrella_vpn/models/models.dart';
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
    const String singbox = """
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
    """;

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
      const String wg = """
[Interface]
PrivateKey = aGVsbG8=
Address = 10.0.0.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = d29ybGQ=
Endpoint = wg.example.com:51820
AllowedIPs = 0.0.0.0/0
""";
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
  });
}
