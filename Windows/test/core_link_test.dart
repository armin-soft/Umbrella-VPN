import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/models/models.dart';
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
}
