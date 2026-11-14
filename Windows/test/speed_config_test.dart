import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/vpn/config_builders.dart';

/// آزمون تنظیمات سرعت: تونل کامل، بافرها، fast open و multiplexing.
void main() {
  VpnNode node(NodeProtocol protocol, Map<String, dynamic> params) => VpnNode(
        id: 'n',
        name: 'test',
        protocol: protocol,
        host: 'example.com',
        port: 443,
        sourceId: 's',
        params: params,
      );

  group('پیکربندی تونل', () {
    test('تونل فقط کلیدهایی دارد که سینگ باکس همراه قبول می کند', () {
      final Map<String, dynamic> config = SingBoxConfig.build(
        node: node(NodeProtocol.vless, <String, dynamic>{'id': 'u'}),
        settings: const AppSettings(),
      );
      final Map<String, dynamic> inbound =
          (config['inbounds'] as List<dynamic>).first as Map<String, dynamic>;
      expect(inbound['type'], 'tun');
      expect(inbound['auto_route'], isTrue);
      // tcp_fast_open و tcp_multi_path هم روی inbound تونل شناخته نمی شوند و
      // همان خطای «json: unknown field» را می دادند.
      expect(inbound.containsKey('tcp_fast_open'), isFalse);
      expect(inbound.containsKey('tcp_multi_path'), isFalse);
      // gso و gso_max_size در سینگ باکس ۱.۱۱ به بعد حذف شده اند و همان
      // کلیدها باعث خطای «json: unknown field» و بالا نیامدن تونل می شدند.
      expect(inbound.containsKey('gso'), isFalse);
      expect(inbound.containsKey('gso_max_size'), isFalse);
    });

    test('حالت اتصال پیش فرض تونل کامل است', () {
      expect(const AppSettings().tunMode, isTrue);
    });

    test('انتخاب صریح کاربر در JSON می ماند', () {
      const AppSettings settings =
          AppSettings(tunMode: false, modeChoiceExplicit: true);
      final AppSettings restored =
          AppSettings.fromJson(settings.toJson());
      expect(restored.tunMode, isFalse);
      expect(restored.modeChoiceExplicit, isTrue);
    });
  });

  group('سرعت خروجی', () {
    test('وی لس چند سرویسی (multiplex) روشن دارد', () {
      final Map<String, dynamic> outbound = SingBoxConfig.outboundFor(
        node(NodeProtocol.vless, <String, dynamic>{'id': 'u'}),
        const AppSettings(),
      );
      final Map<String, dynamic> mux =
          outbound['multiplex'] as Map<String, dynamic>;
      expect(mux['enabled'], isTrue);
      expect(mux['protocol'], 'h2mux');
    });

    test('روی انتقال gRPC و xhttp چند سرویسی روشن نمی شود', () {
      // سرور برای این انتقال ها ۴۰۳ می داد؛ هیدیفای هم mux را خاموش می کند.
      for (final String network in <String>['grpc', 'xhttp', 'ws', 'httpupgrade']) {
        final Map<String, dynamic> outbound = SingBoxConfig.outboundFor(
          node(NodeProtocol.vless, <String, dynamic>{
            'id': 'u',
            'type': network,
            'path': '/x',
          }),
          const AppSettings(),
        );
        expect(
          outbound.containsKey('multiplex'),
          isFalse,
          reason: 'انتقال $network نباید mux داشته باشد',
        );
      }
    });

    test('اگر کاربر multiplex را خاموش کند اعمال می شود', () {
      final Map<String, dynamic> outbound = SingBoxConfig.outboundFor(
        node(NodeProtocol.vless, <String, dynamic>{'id': 'u', 'multiplex': 'off'}),
        const AppSettings(),
      );
      expect(outbound.containsKey('multiplex'), isFalse);
    });

    test('وایرگارد multiplex نمی گیرد', () {
      final Map<String, dynamic> outbound = SingBoxConfig.outboundFor(
        node(NodeProtocol.wireguard,
            <String, dynamic>{'privateKey': 'a', 'publicKey': 'b'}),
        const AppSettings(),
      );
      expect(outbound.containsKey('multiplex'), isFalse);
    });

    test('ALPN تحمیلی حذف شده است', () {
      final Map<String, dynamic> outbound = SingBoxConfig.outboundFor(
        node(NodeProtocol.trojan, <String, dynamic>{
          'password': 'p',
          'security': 'tls',
          'sni': 'example.com',
        }),
        const AppSettings(),
      );
      final Map<String, dynamic> tls = outbound['tls'] as Map<String, dynamic>;
      expect(tls.containsKey('alpn'), isFalse);
    });
  });
}
