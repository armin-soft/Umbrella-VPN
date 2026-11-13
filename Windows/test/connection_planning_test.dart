import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/core/app_config.dart';
import 'package:umbrella_vpn/data/parsers.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/vpn/config_builders.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

/// آزمون انتخاب سرور و ساخت پیکربندی: سروری که شناسه ندارد هرگز نباید اجرا
/// شود (ایکس ری با «invalid UUID» بسته می شود) و پروتکل های بدون هسته نباید
/// وارد چرخه اتصال شوند.
void main() {
  const String uuid = '9b9d9f5d-9841-45bf-a6b9-0479de273c11';

  VpnNode node({
    required NodeProtocol protocol,
    Map<String, dynamic> params = const <String, dynamic>{},
  }) {
    return VpnNode(
      id: 'n-${protocol.name}',
      name: protocol.label,
      protocol: protocol,
      host: 'example.com',
      port: 443,
      sourceId: 'user-xray',
      params: params,
    );
  }

  test('سرور وی لس با شناسه قابل استفاده است', () {
    expect(
      VpnController.usable(
        node(protocol: NodeProtocol.vless, params: <String, dynamic>{'id': uuid}),
      ),
      isTrue,
    );
  });

  test('سرور وی لس بدون شناسه کنار گذاشته می شود', () {
    expect(
      VpnController.usable(node(protocol: NodeProtocol.vless)),
      isFalse,
    );
  });

  test('پروتکل های بدون هسته همراه هرگز انتخاب نمی شوند', () {
    for (final NodeProtocol protocol in <NodeProtocol>[
      NodeProtocol.amnezia,
      NodeProtocol.wireguard,
      NodeProtocol.clash,
    ]) {
      expect(
        VpnController.usable(
          node(
            protocol: protocol,
            params: <String, dynamic>{
              'id': uuid,
              'password': 'x',
              'publicKey': 'y',
              'privateKey': 'z',
            },
          ),
        ),
        isFalse,
        reason: '${protocol.name} نباید قابل استفاده باشد',
      );
    }
  });

  test('هیستریا ۲ و تی یو آی سی با هسته سینگ باکس قابل استفاده اند', () {
    expect(
      VpnController.usable(
        node(
          protocol: NodeProtocol.hysteria2,
          params: <String, dynamic>{'password': 'p'},
        ),
      ),
      isTrue,
    );
    expect(
      VpnController.usable(
        node(
          protocol: NodeProtocol.tuic,
          params: <String, dynamic>{'id': uuid, 'password': 'p'},
        ),
      ),
      isTrue,
    );
    expect(
      VpnController.usable(
        node(protocol: NodeProtocol.hysteria2),
      ),
      isFalse,
      reason: 'بدون رمز نباید انتخاب شود',
    );
  });

  test('پیکربندی تونل کارت شبکه مجازی درست ساخته می شود', () {
    final Map<String, dynamic> config = SingBoxConfig.build(
      node: node(
        protocol: NodeProtocol.trojan,
        params: <String, dynamic>{'password': 'p'},
      ),
      settings: const AppSettings(tunMode: true),
      clashApiPort: 19091,
    );
    final List<dynamic> inbounds = config['inbounds'] as List<dynamic>;
    expect((inbounds.first as Map<String, dynamic>)['type'], 'tun');
    final Map<String, dynamic> experimental =
        config['experimental'] as Map<String, dynamic>;
    final Map<String, dynamic> api =
        experimental['clash_api'] as Map<String, dynamic>;
    expect(api['external_controller'], '127.0.0.1:19091');
    expect((config['route'] as Map<String, dynamic>)['final'], 'proxy');
  });

  test('پیکربندی سینگ باکس برای تونل درست ساخته می شود', () {
    final Map<String, dynamic> config = SingBoxConfig.buildProxy(
      node: node(
        protocol: NodeProtocol.trojan,
        params: <String, dynamic>{'password': 'p'},
      ),
      settings: const AppSettings(),
      port: 2080,
    );
    expect(config['inbounds'], isA<List<dynamic>>());
    final List<dynamic> inbounds = config['inbounds'] as List<dynamic>;
    expect((inbounds.first as Map<String, dynamic>)['listen_port'], 2080);
    final List<dynamic> outbounds = config['outbounds'] as List<dynamic>;
    expect((outbounds.first as Map<String, dynamic>)['tag'], 'proxy');
    expect((config['route'] as Map<String, dynamic>)['final'], 'proxy');
    expect(
      List<dynamic>.of(config['outbounds'] as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .any((Map<String, dynamic> item) => item['type'] == 'direct'),
      isTrue,
    );
  });

  test('میرو با نام کاربری و رمز قابل استفاده است', () {
    expect(
      VpnController.usable(
        node(
          protocol: NodeProtocol.mieru,
          params: <String, dynamic>{'username': 'u', 'password': 'p'},
        ),
      ),
      isTrue,
    );
  });

  test('پیکربندی ایکس ری برای سرور خوانده شده از کلش شناسه دارد', () {
    const String yaml = '''
proxies:
  - name: Clash-VLESS
    type: vless
    server: 5.6.7.8
    port: 443
    uuid: $uuid
    servername: cdn.example.com
    tls: true
    network: ws
    ws-opts:
      path: /ws
      headers:
        Host: cdn.example.com
''';
    final ParseReport report = SubscriptionParser.parseAuto(yaml, 'user-clash');
    expect(report.nodes, hasLength(1));
    final VpnNode parsed = report.nodes.first;

    expect(VpnController.usable(parsed), isTrue);

    final Map<String, dynamic> config = XrayConfig.build(parsed, 2081);
    // پروکسی ویندوز یک پروکسی HTTP می خواهد؛ پورت SOCKS برای آن کار نمی کند.
    final Map<String, dynamic> httpInbound =
        (config['inbounds'] as List<dynamic>).first as Map<String, dynamic>;
    expect(httpInbound['protocol'], 'http');
    expect(httpInbound['port'], AppConfig.httpPortXray);
    expect(httpInbound['listen'], '127.0.0.1');
    final Map<String, dynamic> outbound =
        (config['outbounds'] as List<dynamic>).first as Map<String, dynamic>;
    final Map<String, dynamic> settings =
        outbound['settings'] as Map<String, dynamic>;
    final Map<String, dynamic> vnext =
        (settings['vnext'] as List<dynamic>).first as Map<String, dynamic>;
    final Map<String, dynamic> user =
        (vnext['users'] as List<dynamic>).first as Map<String, dynamic>;
    expect(user['id'], uuid);

    final Map<String, dynamic> stream =
        outbound['streamSettings'] as Map<String, dynamic>;
    expect(stream['network'], 'ws');
    expect(stream['security'], 'tls');
    final Map<String, dynamic> ws = stream['wsSettings'] as Map<String, dynamic>;
    expect(ws['path'], '/ws');
    final Map<String, dynamic> tls =
        stream['tlsSettings'] as Map<String, dynamic>;
    expect(tls['serverName'], 'cdn.example.com');
  });
}
