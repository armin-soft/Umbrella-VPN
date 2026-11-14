import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/vpn/clash_config.dart';

/// آزمون نگه داشتن پیکربندی خود پنل (کلش متا).
///
/// این فایل، همان ساختاری را دارد که پنل این سرویس می دهد: نام گره های فارسی،
/// rule-providers، دی ان اس با fake-ip و تونل. بعد از تنظیم برای دستگاه،
/// mihomo باید بتواند همان فایل را بخواند.
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
  fake-ip-filter:
    - "user.umbrella-server.ir"
  default-nameserver:
    - 1.1.1.1
  nameserver:
    - https://8.8.8.8/dns-query#h3=true
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - automatic
      - "سروش سرور \\\\xA7 443 2"
  - name: automatic
    type: url-test
    url: "http://cp.cloudflare.com"
    interval: 300
    proxies:
      - "سروش سرور \\\\xA7 443 2"
proxies:
- name: "سروش سرور \\\\xA7 443 2"
  type: vless
  server: direct.umbrella-server.ir
  port: 443
  udp: true
  alpn:
  - http/1.1
  client-fingerprint: chrome
  uuid: 9b9d9f5d-9841-45bf-a6b9-0479de273c11
  servername: www.informationsverige.se
  tls: true
  flow: xtls-rprx-vision
  network: tcp
  reality-opts:
    public-key: Nq3ta7rL_bUIfT7l5OXnu2wPbsgErVikyfW7Ad7OL2E
    short-id: 792ac262
rules:
  - MATCH,PROXY
tun:
  enable: true
  stack: system
  dns-hijack:
    - any:53
  auto-route: true
''';

  test('پورت و پنل مدیریت با تنظیمات دستگاه هماهنگ می شوند', () {
    final String out = ClashConfig.adapt(
      panel,
      tun: true,
      mixedPort: 2080,
      apiPort: 19093,
    );
    expect(out, contains('mixed-port: 2080'));
    expect(out, contains('external-controller: "127.0.0.1:19093"'));
    // راز پنل پاک می شود تا برنامه بتواند وضعیت را بخواند.
    expect(out, contains('secret: \'\''));
    // پورت قبلی نباید بماند.
    expect(out, isNot(contains('7890')));
  });

  test('گره های پنل با همه جزئیاتشان دست نمی خورند', () {
    final String out = ClashConfig.adapt(
      panel,
      tun: true,
      mixedPort: 2080,
      apiPort: 19093,
    );
    // همین جزئیات است که در لینک اشتراک نبود و باعث ۴۰۰ می شد.
    expect(out, contains('Nq3ta7rL_bUIfT7l5OXnu2wPbsgErVikyfW7Ad7OL2E'));
    expect(out, contains('792ac262'));
    expect(out, contains('xtls-rprx-vision'));
    expect(out, contains('client-fingerprint: chrome'));
    expect(out, contains('www.informationsverige.se'));
    expect(out, contains('MATCH,PROXY'));
  });

  test('کارت شبکه مجازی نام ثابت برنامه را می گیرد', () {
    final String out = ClashConfig.adapt(
      panel,
      tun: true,
      mixedPort: 2080,
    );
    expect(out, contains('device: "${ClashConfig.tunDevice}"'));
    expect(out, contains('stack: mixed'));
    expect(out, contains('any:53'));
    // در حالت تونل، دی ان اس باید روی ۵۳ شنیده شود تا hijack کار کند.
    expect(out, contains('listen: "127.0.0.1:53"'));
  });

  test('در حالت پروکسی سیستمی تونل خاموش می شود', () {
    final String out = ClashConfig.adapt(
      panel,
      tun: false,
      mixedPort: 2080,
    );
    expect(out, contains('tun:'));
    expect(out, contains('enable: false'));
    expect(out, isNot(contains('dns-hijack')));
    // دی ان اس محلی روی ۵۳ نباید باز بماند.
    expect(out, isNot(contains('127.0.0.1:53')));
  });

  test('سروری که کاربر انتخاب کرده اول فهرست گروه می آید', () {
    // گروه select پنل اولین گزینه را برمی دارد؛ پس انتخاب کاربر باید اول باشد
    // وگرنه ترافیک از سرور دیگری رد می شود.
    final List<String> names = ClashConfig.nodeNames(panel);
    final String out = ClashConfig.adapt(
      panel,
      tun: true,
      mixedPort: 2080,
      preferred: names.first,
    );
    final int groupAt = out.indexOf('name: "PROXY"');
    expect(groupAt, greaterThan(-1));
    final int firstItem = out.indexOf('      - ', groupAt);
    expect(out.substring(firstItem), startsWith('      - "'));
    expect(
      out.substring(firstItem).split('\n').first,
      contains('سروش'),
    );
  });

  test('خروجی دوباره خوانده می شود و گره ها کم نمی شوند', () {
    final String out = ClashConfig.adapt(
      panel,
      tun: true,
      mixedPort: 2080,
      apiPort: 19093,
    );
    // اگر نویسنده YAML اشتباه کند، همین خواندن خطا می داد.
    expect(ClashConfig.nodeNames(out).length, ClashConfig.nodeNames(panel).length);
  });

  test('نام گره های فارسی خوانده می شوند', () {
    final List<String> names = ClashConfig.nodeNames(panel);
    expect(names.length, 1);
    expect(names.first, contains('سروش'));
  });
}
