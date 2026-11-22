import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/data/emergency_feeds.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/vpn/proxy_security.dart';

VpnNode node(NodeProtocol protocol, Map<String, dynamic> params, {String raw = ''}) => VpnNode(
  id: 'n', name: 'n', protocol: protocol, host: 'example.org', port: 443,
  sourceId: 'source', params: params, raw: raw,
);

void main() {
  test('known plaintext VLESS and unencrypted shadowsocks get warnings', () {
    final nodes = EmergencyFeeds.parse('vless://9b9d9f5d-9841-45bf-a6b9-0479de273c11@example.org:443?type=ws#plain', 0).nodes;
    expect(nodes, hasLength(1));
    expect(ProxySecurity.warning(nodes.single), contains('بدون TLS'));
    expect(ProxySecurity.description(nodes.single), contains('WS'));
    expect(ProxySecurity.warning(node(NodeProtocol.shadowsocks, {'method':'none'})), isNotNull);
    expect(ProxySecurity.warning(node(NodeProtocol.socks, {}, raw: 'socks5://a:1')), isNotNull);
  });
  test('unverified TLS warns but pinned or unknown configurations are not called safe', () {
    expect(ProxySecurity.warning(node(NodeProtocol.trojan, {'allowInsecure':true})), isNotNull);
    expect(ProxySecurity.warning(node(NodeProtocol.trojan, {'allowInsecure':true, 'certificate':'pin'})), isNull);
    expect(ProxySecurity.warning(node(NodeProtocol.vless, {'security':'reality'}, raw:'vless://x')), isNull);
    expect(ProxySecurity.warning(node(NodeProtocol.mieru, {})), isNull);
    expect(ProxySecurity.description(node(NodeProtocol.vless, {'type':'xhttp', 'security':'reality'})), contains('XHTTP · REALITY'));
  });
}
