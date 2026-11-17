import 'package:flutter_test/flutter_test.dart';

import 'package:umbrella_vpn/core/app_config.dart';
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

  test('منبع پیش فرض پشتیبان برنامه دقیقا همان نشانی `/sub/` است', () {
    expect(AppConfig.subscriptionSources, hasLength(1));
    expect(AppConfig.subscriptionSources.single.id, 'sub');
    expect(
      AppConfig.subscriptionSources.single.url,
      'https://user.umbrella-server.ir/D6qnVQXRwa/9b9d9f5d-9841-45bf-a6b9-0479de273c11/sub/',
    );
    expect(
      AppConfig.defaultSubscriptionUrl,
      'https://user.umbrella-server.ir/D6qnVQXRwa/9b9d9f5d-9841-45bf-a6b9-0479de273c11/sub/',
    );
  });
}
