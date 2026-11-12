import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/data/parsers.dart';
import 'package:umbrella_vpn/models/models.dart';

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
}
