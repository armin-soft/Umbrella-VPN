import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/vpn/config_builders.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

/// آزمون پیکربندی هسته برای شرایط واقعی اشتراک کاربر:
/// گره های xhttp، سرورهای بدون TLS و سرورهای grpc.
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

  group('انتقال xhttp', () {
    test('سینگ باکس برای xhttp انتقال http با میزبان می سازد', () {
      final Map<String, dynamic> config = SingBoxConfig.buildProxy(
        node: node(NodeProtocol.vless, <String, dynamic>{
          'id': 'u',
          'type': 'xhttp',
          'path': '/abc',
          'host': 'proxy.example.com',
          'security': 'tls',
          'sni': 'proxy.example.com',
        }),
        settings: const AppSettings(),
        port: 2080,
      );
      final Map<String, dynamic> outbound =
          (config['outbounds'] as List<dynamic>).first as Map<String, dynamic>;
      final Map<String, dynamic> transport =
          outbound['transport'] as Map<String, dynamic>;
      expect(transport['type'], 'http');
      expect(transport['path'], '/abc');
      expect(transport['host'], <String>['proxy.example.com']);
    });

    test('ایکس ری برای xhttp بخش xhttpSettings می سازد', () {
      final Map<String, dynamic> config = XrayConfig.build(
        node(NodeProtocol.vless, <String, dynamic>{
          'id': 'u',
          'type': 'xhttp',
          'path': '/abc',
          'host': 'proxy.example.com',
          'security': 'tls',
        }),
        2081,
      );
      final Map<String, dynamic> outbound =
          (config['outbounds'] as List<dynamic>).first as Map<String, dynamic>;
      final Map<String, dynamic> stream =
          outbound['streamSettings'] as Map<String, dynamic>;
      final Map<String, dynamic> settings =
          stream['xhttpSettings'] as Map<String, dynamic>;
      expect(settings['path'], '/abc');
      expect(settings['host'], 'proxy.example.com');
      expect(stream['network'], 'xhttp');
    });
  });

  group('انتخاب هسته', () {
    test('انتقال xhttp با سینگ باکس رد و با ایکس ری قبول می شود', () {
      expect(
        SingBoxConfig.supportsTransport(node(NodeProtocol.vless, <String, dynamic>{
          'id': 'u',
          'type': 'xhttp',
        })),
        isFalse,
      );
      expect(
        SingBoxConfig.supportsTransport(node(NodeProtocol.vless, <String, dynamic>{
          'id': 'u',
          'type': 'ws',
        })),
        isTrue,
      );
    });
  });

  group('لایه TLS', () {
    test('سرور با security=none حتی با sni، TLS نمی گیرد', () {
      final Map<String, dynamic> outbound = SingBoxConfig.outboundFor(
        node(NodeProtocol.vless, <String, dynamic>{
          'id': 'u',
          'security': 'none',
          'sni': 'proxy.example.com',
          'type': 'httpupgrade',
          'path': '/x',
        }),
        const AppSettings(),
      );
      expect(outbound.containsKey('tls'), isFalse);
    });

    test('سرور با security=tls لایه TLS دارد', () {
      final Map<String, dynamic> outbound = SingBoxConfig.outboundFor(
        node(NodeProtocol.vless, <String, dynamic>{
          'id': 'u',
          'security': 'tls',
          'sni': 'proxy.example.com',
        }),
        const AppSettings(),
      );
      final Map<String, dynamic> tls = outbound['tls'] as Map<String, dynamic>;
      expect(tls['enabled'], isTrue);
      expect(tls['server_name'], 'proxy.example.com');
    });
  });

  group('انتقال وب سرور پنل', () {
    Map<String, dynamic> xrayStream(Map<String, dynamic> params) {
      final Map<String, dynamic> config = XrayConfig.build(
        node(NodeProtocol.vless, params),
        2080,
      );
      final Map<String, dynamic> outbound =
          (config['outbounds'] as List<dynamic>).first as Map<String, dynamic>;
      return outbound['streamSettings'] as Map<String, dynamic>;
    }

    test('هدرهای مرورگر سرور در xhttpSettings نوشته می شوند', () {
      // بدون این هدرها سرور همین سرویس درخواست را با ۴۰۰ رد می کرد.
      final Map<String, dynamic> stream = xrayStream(<String, dynamic>{
        'id': 'u',
        'type': 'xhttp',
        'path': '/xhttp',
        'host': 'cdn.example.com',
        'security': 'tls',
        'sni': 'cdn.example.com',
        'extra':
            '{"headers":{"User-Agent":"Mozilla/5.0 Chrome/154","Pragma":"no-cache"}}',
      });
      final Map<String, dynamic> xhttp =
          stream['xhttpSettings'] as Map<String, dynamic>;
      final Map<String, dynamic> headers =
          xhttp['headers'] as Map<String, dynamic>;
      expect(headers['User-Agent'], contains('Chrome'));
      expect(headers['Pragma'], 'no-cache');
      // ALPN درخواستی سرور http/2 است.
      final Map<String, dynamic> tls = stream['tlsSettings'] as Map<String, dynamic>;
      expect(tls['alpn'], contains('h2'));
    });

    test('وب سوکت هم هدرهای اضافه سرور را می گیرد', () {
      final Map<String, dynamic> stream = xrayStream(<String, dynamic>{
        'id': 'u',
        'type': 'ws',
        'path': '/ws',
        'host': 'cdn.example.com',
        'headers': '{"User-Agent":"Mozilla/5.0"}',
      });
      final Map<String, dynamic> ws =
          stream['wsSettings'] as Map<String, dynamic>;
      final Map<String, dynamic> headers =
          ws['headers'] as Map<String, dynamic>;
      expect(headers['Host'], 'cdn.example.com');
      expect(headers['User-Agent'], contains('Mozilla'));
    });

    test('سینگ باکس برای xhttp نقشه نمی سازد', () {
      // سینگ باکس انتقال xhttp ندارد؛ پیش از این، اجرای آن فقط وقت می گرفت.
      final VpnNode xhttp = node(NodeProtocol.vless, <String, dynamic>{
        'id': 'u',
        'type': 'xhttp',
        'path': '/x',
      });
      expect(SingBoxConfig.supportsTransport(xhttp), isFalse);
      expect(
        VpnController.supports(xhttp),
        isTrue,
        reason: 'ایکس ری همین سرور را اجرا می کند',
      );
    });
  });

  group('تونل سینگ باکس', () {
    test('کلیدهای حذف شده در هیچ حالتی نوشته نمی شوند', () {
      for (final TunStack stack in TunStack.values) {
        final Map<String, dynamic> config = SingBoxConfig.build(
          node: node(NodeProtocol.vless, <String, dynamic>{'id': 'u'}),
          settings: AppSettings(tunStack: stack),
        );
        final Map<String, dynamic> inbound =
            (config['inbounds'] as List<dynamic>).first as Map<String, dynamic>;
        expect(inbound.containsKey('gso'), isFalse);
        expect(inbound.containsKey('gso_max_size'), isFalse);
        expect(inbound['stack'], stack.name);
      }
    });
  });
}
