import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/data/parsers.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/vpn/direct_profile.dart';

void main() {
  const String config = '''
[Interface]
PrivateKey = private-test
Address = 10.0.0.2/32
MTU = 1280
Jc = 4
Jmin = 10
Jmax = 20
S1 = 32
H1 = 123
[Peer]
PublicKey = public-test
PresharedKey = psk-test
Endpoint = example.invalid:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 20
''';
  test('Amnezia endpoint carries obfuscation, peer and address', () {
    final VpnNode node = SubscriptionParser.parseAuto(config, 'test').nodes.single;
    final Map<String, dynamic> data = jsonDecode(DirectProfile.encode(node));
    final Map<String, dynamic> endpoint = data['endpoints'][0];
    expect(endpoint['type'], 'awg');
    expect(endpoint['awg']['jc'], 4);
    expect(endpoint['awg']['h1'], '123');
    expect(endpoint['peers'][0]['preshared_key'], 'psk-test');
    expect(endpoint['peers'][0]['persistent_keepalive_interval'], 20);
    expect(endpoint['address'], <String>['10.0.0.2/32']);
  });
  test('Mieru carries both transport bindings and handshake settings', () {
    final String body = jsonEncode(<String, dynamic>{
      'activeProfile': 'a', 'profiles': <Object>[
        <String, dynamic>{'profileName': 'a', 'user': <String, String>{'name': 'u', 'password': 'p'},
          'servers': <Object>[<String, dynamic>{'ipAddress': '192.0.2.1', 'portBindings': <Object>[
            <String, dynamic>{'protocol': 'TCP', 'port': 1234},
            <String, dynamic>{'protocol': 'UDP', 'port': 5678},
          ]}], 'multiplexing': <String, String>{'level': 'MULTIPLEXING_LOW'},
          'handshakeMode': 'HANDSHAKE_NO_WAIT'}]});
    final VpnNode node = SubscriptionParser.parseAuto(body, 'test').nodes.single;
    final Map<String, dynamic> data = jsonDecode(DirectProfile.encode(node));
    expect(data['outbounds'][0]['portBindings'], hasLength(2));
    expect(data['outbounds'][0]['handshake_mode'], 'HANDSHAKE_NO_WAIT');
    expect(data['outbounds'][0]['multiplexing'], 'MULTIPLEXING_LOW');
  });
}
