import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/vpn/clash_config.dart';
import 'package:umbrella_vpn/vpn/hiddify_core.dart';

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

    test('تنظیمات هسته دقیقا همان کلیدهای هیدیفای را دارد', () {
      // کلیدها از `v2/config/hiddify_option.go` خود هسته گرفته شده اند و با
      // خط تیره نوشته می شوند؛ کلید با زیرخط را هسته نادیده می گیرد.
      final Map<String, dynamic> settings = HiddifyCore.settingsJson(
        tun: true,
        systemProxy: false,
        port: HiddifyCore.port,
      );
      expect(settings.containsKey('enable-tun'), isTrue);
      expect(settings.containsKey('set-system-proxy'), isTrue);
      expect(settings['enable-tun'], isTrue);
      // در حالت تونل، پروکسی سیستمی روشن نمی شود.
      expect(settings['set-system-proxy'], isFalse);
      expect(settings['mixed-port'], HiddifyCore.port);
      // هیچ کلیدی با زیرخط نیست؛ فقط مقادیر (مثل نشانی تست سرعت) می توانند
      // زیرخط داشته باشند.
      for (final String key in settings.keys) {
        expect(key.contains('_'), isFalse, reason: key);
      }
      expect(jsonEncode(settings).isNotEmpty, isTrue);
    });

    test('آرگومان ها همان آرگومان های مستند هسته اند', () {
      final List<String> args = HiddifyCore.args(
        links: r'C:\Users\a\links.txt',
        runDir: r'C:\Users\a\run',
        tun: true,
        settingsPath: r'C:\Users\a\settings.json',
      );
      expect(args.first, 'run');
      expect(args.contains('-c'), isTrue);
      expect(args.contains('-d'), isTrue);
      expect(args.contains('--in-proxy-port'), isTrue);
      expect(args.contains('--tun'), isTrue);
      // تونل و پروکسی سیستمی با هم نمی آیند.
      expect(args.contains('--system-proxy'), isFalse);
      expect(args.contains('--disable-color'), isTrue);
    });
  });
}
