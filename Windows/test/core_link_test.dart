import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/data/parsers.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/vpn/umbrella_core.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

/// ساختن لینک از فیلدهای گره.
///
/// گزارش ۱٫۰٫۱۰ نشان داد لینک وی لس با `type=vless` ساخته می شد و هسته آن را
/// با «unknown transport type: vless» رد می کرد. علت: در نقشه کلش، `type`
/// نام پروتکل است و کد آن را به جای نوع انتقال می گذاشت.
void main() {
  VpnNode nodeOf(Map<String, dynamic> params, {String raw = ''}) {
    return VpnNode(
      id: 'n1',
      name: 'www.informationsverige.se reality tcp direct vless',
      protocol: NodeProtocol.vless,
      host: 'direct.umbrella-server.ir',
      port: 443,
      sourceId: 's',
      params: params,
      raw: raw,
    );
  }

  group('لینک وی لس', () {
    test('نوع پروتکل هرگز به جای نوع انتقال نمی نشیند', () {
      // همان داده‌ای که در گزارش بود: type نام پروتکل است، network نداریم.
      final String link = VpnController.linkFor(
        nodeOf(<String, dynamic>{
          'type': 'vless',
          'id': '9b9d9f5d-9841-45bf-a6b9-0479de273c11',
          'security': 'reality',
          'sni': 'www.informationsverige.se',
          'pbk': 'abc',
          'sid': 'ff',
        }),
      );
      expect(link, contains('type=tcp'));
      expect(link, isNot(contains('type=vless')));
    });

    test('نوع انتقال از network خوانده می شود', () {
      final String link = VpnController.linkFor(
        nodeOf(<String, dynamic>{
          'network': 'grpc',
          'id': 'u',
          'serviceName': 'svc',
        }),
      );
      expect(link, contains('type=grpc'));
      expect(link, contains('serviceName=svc'));
    });

    test('پارامترهای وب سوکت نوشته می شوند', () {
      final String link = VpnController.linkFor(
        nodeOf(<String, dynamic>{
          'network': 'ws',
          'id': 'u',
          'path': '/ray',
          'host': 'cdn.example.com',
        }),
      );
      expect(link, contains('type=ws'));
      expect(link, contains('path=%2Fray'));
      expect(link, contains('host=cdn.example.com'));
    });

    test('پارامترهای ریلیتی حفظ می شوند', () {
      final String link = VpnController.linkFor(
        nodeOf(<String, dynamic>{
          'id': 'u',
          'security': 'reality',
          'pbk': 'pubkey',
          'sid': 'a1b2',
          'fp': 'chrome',
          'sni': 'www.informationsverige.se',
        }),
      );
      expect(link, contains('security=reality'));
      expect(link, contains('pbk=pubkey'));
      expect(link, contains('sid=a1b2'));
      expect(link, contains('fp=chrome'));
    });

    test('اگر خود سرور لینک داشته باشد همان دست نخورده می ماند', () {
      const String raw =
          'vless://uuid@host:443?type=ws&security=tls#name';
      expect(VpnController.linkFor(nodeOf(<String, dynamic>{}, raw: raw)), raw);
    });

    test('نوع انتقال ناشناخته به tcp برمی گردد، نه نام پروتکل', () {
      final String link = VpnController.linkFor(
        nodeOf(<String, dynamic>{'network': 'vless', 'id': 'u'}),
      );
      expect(link, contains('type=tcp'));
    });
  });

  group('لینک تروجان', () {
    test('همان تله type در تروجان هم بسته شده است', () {
      final VpnNode trojan = VpnNode(
        id: 't1',
        name: 'trojan node',
        protocol: NodeProtocol.trojan,
        host: 'example.com',
        port: 443,
        sourceId: 's',
        params: <String, dynamic>{'password': 'p', 'type': 'trojan'},
      );
      final String link = VpnController.linkFor(trojan);
      expect(link, contains('type=tcp'));
      expect(link, isNot(contains('type=trojan')));
    });
  });

  group('لینک وی مس', () {
    test('net از network می آید و هرگز نام پروتکل نمی شود', () {
      final VpnNode vmess = VpnNode(
        id: 'v1',
        name: 'vmess node',
        protocol: NodeProtocol.vmess,
        host: 'example.com',
        port: 443,
        sourceId: 's',
        params: <String, dynamic>{
          'id': 'u',
          'type': 'vmess',
          'network': 'ws',
        },
      );
      final String link = VpnController.linkFor(vmess);
      expect(link, startsWith('vmess://'));
    });
  });

  group('پارامترهای ریلیتی از فایل کلش', () {
    test('اثر انگشت مرورگر و ALPN حفظ می شوند', () {
      // در فایل کلش پنل، همین گره `client-fingerprint: chrome` و
      // `alpn: [http/1.1]` دارد. ریلیتی بدون اثر انگشت مرورگر دست نمی دهد،
      // پس اگر این دو از دست بروند گره سالم هم وصل نمی شود.
      final String link = VpnController.linkFor(
        nodeOf(<String, dynamic>{
          'id': '9b9d9f5d-9841-45bf-a6b9-0479de273c11',
          'security': 'reality',
          'pbk': 'Nq3ta7rL_bUIfT7l5OXnu2wPbsgErVikyfW7Ad7OL2E',
          'sid': '792ac262',
          'sni': 'www.informationsverige.se',
          'fp': 'chrome',
          'alpn': 'http/1.1',
          'flow': 'xtls-rprx-vision',
          'network': 'tcp',
        }),
      );
      expect(link, contains('fp=chrome'));
      expect(link, contains('alpn=http%2F1.1'));
      expect(link, contains('flow=xtls-rprx-vision'));
      expect(link, contains('pbk='));
      expect(link, contains('sid=792ac262'));
      expect(link, contains('security=reality'));
      expect(link, contains('type=tcp'));
    });
  });

  group('نوع انتقال پشتیبانی نشده', () {
    test('xhttp و splithttp برای این هسته قابل اجرا نیستند', () {
      // این دو مخصوص زیکس‌ری هستند؛ هسته آمبرلا (سینگ باکس) نمی شناسدشان.
      // ساختن `tcp` حدسی یعنی اتصال با تنظیمات غلط و سرور «خراب» به نظر
      // می رسد.
      VpnNode withNetwork(String network) => VpnNode(
            id: 'x',
            name: 'node',
            protocol: NodeProtocol.vless,
            host: 'h',
            port: 443,
            sourceId: 's',
            params: <String, dynamic>{'id': 'u', 'network': network},
          );
      expect(VpnController.transportSupported(withNetwork('xhttp')), isFalse);
      expect(
        VpnController.transportSupported(withNetwork('splithttp')),
        isFalse,
      );
      expect(VpnController.transportSupported(withNetwork('tcp')), isTrue);
      expect(VpnController.transportSupported(withNetwork('ws')), isTrue);
      expect(VpnController.transportSupported(withNetwork('grpc')), isTrue);
      expect(
        VpnController.transportSupported(withNetwork('httpupgrade')),
        isTrue,
      );
      // خالی یعنی پیش فرض (tcp) و مشکلی نیست.
      expect(VpnController.transportSupported(withNetwork('')), isTrue);
    });

    test('گره xhttp از فهرست قابل استفاده کنار گذاشته می شود', () {
      final VpnNode node = VpnNode(
        id: 'x',
        name: 'سرور آمبرلا xhttp',
        protocol: NodeProtocol.vless,
        host: 'direct.umbrella-server.ir',
        port: 443,
        sourceId: 's',
        params: <String, dynamic>{'id': 'u', 'network': 'xhttp'},
      );
      expect(VpnController.usable(node), isFalse);
    });
  });

  group('خواندن فایل کلش پنل', () {
    test('اثر انگشت مرورگر و ALPN از کلش خوانده می شوند', () {
      // همان شکل واقعی که پنل می دهد: `client-fingerprint` و `alpn` جدا از
      // `reality-opts` هستند. تا ۱٫۰٫۱۱ هیچ کدام خوانده نمی شد، پس گره
      // ریلیتی از مسیر کلش با دست دادن اشتباه به هسته می رفت.
      const String yaml = '''
proxies:
  - name: reality-node
    type: vless
    server: direct.umbrella-server.ir
    port: 443
    uuid: 9b9d9f5d-9841-45bf-a6b9-0479de273c11
    udp: true
    alpn:
      - http/1.1
    skip-cert-verify: false
    client-fingerprint: chrome
    servername: www.informationsverige.se
    tls: true
    packet-encoding: xudp
    flow: xtls-rprx-vision
    network: tcp
    reality-opts:
      public-key: Nq3ta7rL_bUIfT7l5OXnu2wPbsgErVikyfW7Ad7OL2E
      short-id: 792ac262
''';
      final ParseReport report = SubscriptionParser.parseAuto(yaml, 'panel');
      expect(report.nodes, hasLength(1));
      final VpnNode node = report.nodes.first;
      expect(node.params['fp'], 'chrome');
      expect(node.params['alpn'], 'http/1.1');
      expect(node.params['pbk'], 'Nq3ta7rL_bUIfT7l5OXnu2wPbsgErVikyfW7Ad7OL2E');
      expect(node.params['sid'], '792ac262');
      expect(node.params['security'], 'reality');
      expect(node.params['network'], 'tcp');
      expect(node.params['flow'], 'xtls-rprx-vision');

      // و لینکی که از همین گره ساخته می شود باید همه این ها را داشته باشد.
      final String link = VpnController.linkFor(node);
      expect(link, contains('fp=chrome'));
      expect(link, contains('alpn=http%2F1.1'));
      expect(link, contains('security=reality'));
      expect(link, contains('type=tcp'));
    });
  });

  group('تنظیمات هسته', () {
    test('موتور TLS ویندوز خاموش است تا ریلیتی دست بدهد', () {
      // در ۱٫۰٫۱۲ این کلید روشن بود. هسته برای گره بدون اثر انگشت، TLS
      // ویندوز را انتخاب می کند، ولی ریلیتی از انتخاب موتور کنار گذاشته
      // می شود و به دست دادن پیش فرض Go می رسد؛ سرور ریلیتی آن را رد می کند
      // و هیچ اتصالی برقرار نمی شود.
      final Map<String, dynamic> settings = UmbrellaCore.settingsJson(
        tun: true,
        systemProxy: false,
        port: 12334,
      );
      expect(settings['use-system-tls-engine'], isFalse);
    });
  });
}
