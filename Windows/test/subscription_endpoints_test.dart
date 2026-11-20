import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:umbrella_vpn/core/app_config.dart';
import 'package:umbrella_vpn/data/parsers.dart';
import 'package:umbrella_vpn/data/subscription_endpoints.dart';
import 'package:umbrella_vpn/models/models.dart';

void main() {
  const String base = 'https://user.umbrella-server.ir/D6qnVQXRwa/';
  const String uuid = '9b9d9f5d-9841-45bf-a6b9-0479de273c11';

  test('فقط یک نشانی `/sub/` اختصاصی کاربر ساخته می شود و مسیرهای اضافه حذف شده اند', () {
    final List<SubscriptionSource> sources = SubscriptionEndpoints.build(
      subscriptionUrl: '$base$uuid/sub/',
      accountBase: base,
      uuid: uuid,
    );
    expect(sources, hasLength(1));
    expect(sources.single.id, 'user-sub');
    expect(sources.single.title, 'اشتراک خودکار');
    expect(sources.single.url, '$base$uuid/sub/');
    expect(sources.single.format, SubscriptionFormat.xray);
    expect(sources.single.personal, isTrue);
    expect(SubscriptionEndpoints.isComplete(sources), isTrue);
  });

  test('اگر سرور نشانی قدیمی all.txt یا کلش بفرستد باز هم فقط به `/sub/` تبدیل می شود', () {
    for (final String legacy in <String>[
      '$base$uuid/all.txt',
      '$base$uuid/sub64/',
      '$base$uuid/clash/meta/all.yml',
      '$base$uuid/full-singbox.json',
      '$base$uuid/wireguard/?asn=unknown',
      '$base$uuid/sub',
    ]) {
      final List<SubscriptionSource> sources = SubscriptionEndpoints.build(
        subscriptionUrl: legacy,
        accountBase: '',
        uuid: uuid,
      );
      expect(sources, hasLength(1), reason: legacy);
      expect(sources.single.url, '$base$uuid/sub/', reason: legacy);
      expect(sources.single.personal, isTrue, reason: legacy);
    }
  });

  test('بدون پارامتر uuid هم شناسه را از نشانی بیرون می کشد و به `/sub/` نرمال می کند', () {
    final List<SubscriptionSource> sources = SubscriptionEndpoints.build(
      subscriptionUrl: '$base$uuid/all.txt',
      accountBase: '',
      uuid: '',
    );
    expect(sources, hasLength(1));
    expect(sources.single.id, 'user-sub');
    expect(sources.single.url, '$base$uuid/sub/');
    expect(sources.single.personal, isTrue);
  });

  test('مسیر راز پنل را از accountBase جایگزین می کند وقتی در نشانی جا افتاده است', () {
    final List<SubscriptionSource> sources = SubscriptionEndpoints.build(
      subscriptionUrl: 'https://user.umbrella-server.ir/$uuid/sub/',
      accountBase: base,
      uuid: uuid,
    );
    expect(sources, hasLength(1));
    expect(sources.single.url, '$base$uuid/sub/');
  });

  test('نشانی پیش فرض برنامه را به کار می برد اگر سرور مسیر راز پنل را ندهد', () {
    const String otherUuid = '11111111-2222-4333-8444-555555555555';
    final List<SubscriptionSource> sources = SubscriptionEndpoints.build(
      subscriptionUrl: 'https://user.umbrella-server.ir/$otherUuid/sub/',
      accountBase: '',
      uuid: otherUuid,
    );
    expect(sources, hasLength(1));
    expect(sources.single.url, '$base$otherUuid/sub/');
  });

  test('شناسه تکرارشده سرور قدیمی (host/<uuid>/<uuid>/sub/) به مسیر راز درست اصلاح می شود', () {
    const String otherUuid = '11111111-2222-4333-8444-555555555555';
    final List<SubscriptionSource> built = SubscriptionEndpoints.build(
      subscriptionUrl:
          'https://user.umbrella-server.ir/$otherUuid/$otherUuid/sub/',
      accountBase: 'https://user.umbrella-server.ir/$otherUuid/',
      uuid: otherUuid,
    );
    expect(built, hasLength(1));
    expect(built.single.personal, isTrue);
    expect(built.single.url, '$base$otherUuid/sub/');
  });

  test('بدون حساب کاربر هیچ منبع اشتراک عمومی یا رایگانی ساخته نمی شود', () {
    final List<SubscriptionSource> empty = SubscriptionEndpoints.build(
      subscriptionUrl: '',
      accountBase: '',
      uuid: '',
    );
    expect(empty, isEmpty);
    expect(AppConfig.subscriptionSources, isEmpty);
    expect(AppConfig.subscriptionBaseUrl, base);
    expect(
      AppConfig.subscriptionBaseUrl.contains(
        '9b9d9f5d-9841-45bf-a6b9-0479de273c11',
      ),
      isFalse,
    );
  });

  test('پاسخ Base64 همراه با سرآیندهای توضیحات `/sub/` به درستی رمزگشایی می شود', () {
    const String vless =
        'vless://11111111-2222-3333-4444-555555555555@de1.example.com:443?encryption=none&security=tls&sni=de1.example.com#Germany-01';
    final String encoded = base64Encode(utf8.encode('$vless\n'));
    final String body = <String>[
      '#profile-title: Umbrella Personal',
      '#subscription-userinfo: upload=0; download=1024; total=10737418240; expire=1999999999',
      '#profile-web-page-url: ${base}11111111-2222-3333-4444-555555555555/',
      encoded,
    ].join('\n');

    final ParseReport report = SubscriptionParser.parseAuto(body, 'user-sub');
    expect(report.nodes, hasLength(1));
    expect(report.nodes.single.host, 'de1.example.com');
    expect(report.nodes.single.sourceId, 'user-sub');
  });

  test('پاسخ HTML به عنوان صفحه وب تشخیص داده شده و سرور جعلی نمی سازد', () {
    const String html =
        '<!DOCTYPE html><html><head><title>Panel</title></head><body><a href="https://example.com">link</a></body></html>';
    expect(SubscriptionParser.looksLikeHtml(html), isTrue);
    final ParseReport report = SubscriptionParser.parseAuto(html, 'user-sub');
    expect(report.nodes, isEmpty);
  });
}
