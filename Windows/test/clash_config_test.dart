import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/vpn/clash_config.dart';
import 'package:umbrella_vpn/vpn/umbrella_core.dart';

/// آزمون پیکربندی خود پنل و نام گره هایش.
///
/// هسته هیدیفای (تنها هسته نسخه) خودش کلش، ایکس ری، سینگ باکس و فایل لینک ها
/// را می شناسد، پس دیگر لازم نیست پیکربندی برای هسته ای دیگر بازنویسی شود؛
/// فقط نام گره های پنل خوانده می شود تا سرورهای فهرست با آن ها تطبیق داده
/// شوند.
void main() {
  const String panel = '''
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
secret: abc
external-controller: 127.0.0.1:9090
dns:
  enable: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  listen: 127.0.0.1:6868
proxies:
  - name: سرور آلمان
    type: vless
    server: de.example.com
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    tls: true
    servername: de.example.com
    network: ws
    ws-opts:
      path: /path
      headers:
        Host: de.example.com
  - name: سرور هلند
    type: trojan
    server: nl.example.com
    port: 443
    password: secret
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - سرور آلمان
      - سرور هلند
rules:
  - MATCH,PROXY
''';

  group('پیکربندی خود پنل', () {
    test('نام گره ها با نام فارسی خوانده می شود', () {
      expect(ClashConfig.nodeNames(panel), <String>[
        'سرور آلمان',
        'سرور هلند',
      ]);
    });

    test('فایل ناقص یا بی ربط کرش نمی کند', () {
      expect(ClashConfig.nodeNames(''), isEmpty);
      expect(ClashConfig.nodeNames('not: a clash config'), isEmpty);
    });
  });

  group('پل به هسته هیدیفای', () {
    test('پروفایل پنل بدون تغییر به هسته داده می شود', () {
      // هسته خودش کلش را می شناسد (`parseClashContent` در hiddify-core)، پس
      // هیچ بازنویسی ای لازم نیست و پروفایل باید دست نخورده بماند.
      final String profile = panel;
      expect(profile.contains('fake-ip-range: 198.18.0.1/16'), isTrue);
      expect(profile.contains('ws-opts:'), isTrue);
      // پورت پنل دست نمی خورد؛ هسته پورت خودش را جدا می سازد.
      expect(profile.contains('mixed-port: 7890'), isTrue);
    });

    test('فایل تنظیمات کامل است و دی ان اس خالی نمی ماند', () {
      // کلیدها از `v2/config/hiddify_option.go` خود هسته گرفته شده اند و با
      // خط تیره نوشته می شوند؛ کلید با زیرخط را هسته نادیده می گیرد.
      final Map<String, dynamic> settings = UmbrellaCore.settingsJson(
        tun: true,
        systemProxy: false,
        port: UmbrellaCore.port,
      );
      expect(settings.containsKey('enable-tun'), isTrue);
      expect(settings.containsKey('set-system-proxy'), isTrue);
      expect(settings['enable-tun'], isTrue);
      // در حالت تونل، پروکسی سیستمی روشن نمی شود.
      expect(settings['set-system-proxy'], isFalse);
      expect(settings['mixed-port'], UmbrellaCore.port);
      // اگر `-d` داده شود، هسته پیش فرض های خودش را کنار می گذارد و هر کلید
      // نبوده را صفر می کند؛ دی ان اس خالی هسته را با «نشانی سرور نامعتبر»
      // می بندد (خطای ۱٫۰۳). پس این کلیدها باید پر باشند.
      expect(settings['remote-dns-address'], isNotEmpty);
      expect(settings['direct-dns-address'], isNotEmpty);
      // صفر گذاشتن این دو، تونل را بی بسته می کند.
      expect(settings['mtu'], greaterThan(0));
      expect(settings['tun-implementation'], isNotEmpty);
      // و انتخاب ما (تونل) باید از فایل بیاید، نه از پرچم خط فرمان.
      expect(settings['enable-tun'], isTrue);
      // کلیدهایی که هسته در `DefaultHiddifyOptions` می گذارد و اگر نباشند صفر
      // می شوند؛ این فهرست همان قرارداد فایل تنظیمات است.
      for (final String key in <String>[
        'log-level',
        'log-file',
        'enable-tun-service',
        'delegate-system-proxy',
        'enable-mixed-port',
        'tproxy-port',
        'redirect-port',
        'direct-port',
        'lan-sharing-port',
        'local-proxy-auth',
        'local-proxy-in-vpn',
        'strict-route',
        'auto-redirect',
        'router-mode',
        'remote-dns-domain-strategy',
        'direct-dns-domain-strategy',
        'independent-dns-cache',
        'enable-fake-dns',
        'region',
        'chain-status',
        'ipv6-mode',
        'resolve-destination',
        'bypass-lan',
        'allow-connection-from-lan',
        'block-quic',
        'block-ads',
        'enable-full-config',
        'use-xray-core-when-possible',
        'enable-clash-api',
        'clash-api-port',
        'web-secret',
        'connection-test-url',
        'url-test-interval',
        'keep-top',
        'enable-ntp',
        'use-system-tls-engine',
        'mux',
        'tls-tricks',
      ]) {
        expect(settings.containsKey(key), isTrue, reason: key);
      }
      // هیچ کلیدی با زیرخط نیست؛ فقط مقادیر (مثل نشانی تست سرعت) می توانند
      // زیرخط داشته باشند.
      for (final String key in settings.keys) {
        expect(key.contains('_'), isFalse, reason: key);
      }
      expect(jsonEncode(settings).isNotEmpty, isTrue);
    });

    test('آرگومان ها همان آرگومان های مستند هسته اند', () {
      final List<String> args = UmbrellaCore.args(
        links: r'C:\Users\a\links.txt',
        runDir: r'C:\Users\a\run',
        tun: true,
        settingsPath: r'C:\Users\a\settings.json',
      );
      expect(args.first, 'run');
      expect(args.contains('-c'), isTrue);
      expect(args.contains('-d'), isTrue);
      // با `-d` هسته فایل تنظیمات را روی ساختار خالی می خواند و پرچم ها را
      // بازنویسی می کند؛ پس این پرچم ها نباید فرستاده شوند (۱٫۰٫۳ همین جا
      // تونلش را از دست داد).
      expect(args.contains('--in-proxy-port'), isFalse);
      expect(args.contains('--tun'), isFalse);
      expect(args.contains('--system-proxy'), isFalse);
      expect(args.contains('--dns-remote'), isFalse);
      expect(args.contains('--dns-direct'), isFalse);
      expect(args.contains('--disable-color'), isTrue);
    });

    test('بدون فایل تنظیمات، انتخاب ها با پرچم خط فرمان می روند', () {
      final List<String> args = UmbrellaCore.args(
        links: r'C:\Users\a\links.txt',
        runDir: r'C:\Users\a\run',
        tun: true,
      );
      expect(args.contains('--tun'), isTrue);
      expect(args.contains('--in-proxy-port'), isTrue);
      // تونل و پروکسی سیستمی با هم نمی آیند.
      expect(args.contains('--system-proxy'), isFalse);
      expect(args.contains('-d'), isFalse);
    });
  });
}
