import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/data/subscription_endpoints.dart';
import 'package:umbrella_vpn/models/models.dart';

/// آزمون ساخت نشانی پنج اشتراک کاربر از داده ای که سرور می دهد. هیچ نشانی از
/// کاربر پرسیده نمی شود و همه مسیرها باید با مسیرهای واقعی پنل یکی باشند.
void main() {
  const String base = 'https://user.umbrella-server.ir/D6qnVQXRwa/';
  const String uuid = '9b9d9f5d-9841-45bf-a6b9-0479de273c11';

  test('هشت نشانی واقعی پنل ساخته می شود (به ترتیب مستندات)', () {
    final List<SubscriptionSource> sources = SubscriptionEndpoints.build(
      subscriptionUrl: '$base$uuid/sub/',
      accountBase: base,
      uuid: uuid,
    );

    final List<String> urls =
        sources.map((SubscriptionSource item) => item.url).toList();
    // مسیرهای اصلی، همان هایی که پنل مستند کرده است.
    expect(urls.take(8).toList(), <String>[
      '$base$uuid/sub/',
      '$base$uuid/all.txt',
      '$base$uuid/sub64/',
      '$base$uuid/clash/meta/all.yml',
      '$base$uuid/full-singbox.json',
      '$base$uuid/wireguard',
      '$base$uuid/amnezia',
      '$base$uuid/mieru',
    ]);
    // مسیرهای جایگزین هم پشتیبان هستند؛ مسیر ۴۰۴ قدیمی کلش دیگر ساخته
    // نمی شود و مسیر درست کلش متا در فهرست اصلی است.
    expect(urls, isNot(contains('$base$uuid/mihomo/all.yml')));
    expect(urls, contains('$base$uuid/clash/meta/all.yml'));
    expect(urls, contains('$base$uuid/wireguard/?asn=unknown'));
    expect(sources.every((SubscriptionSource item) => item.personal), isTrue);
  });

  test('عنوان هر نشانی همان نام مستند پنل است', () {
    final List<SubscriptionSource> sources = SubscriptionEndpoints.build(
      subscriptionUrl: '$base$uuid/sub/',
      accountBase: base,
      uuid: uuid,
    );
    expect(
      sources.take(8).map((SubscriptionSource item) => item.title).toList(),
      <String>[
        'خودکار',
        'فهرست ساده',
        'فهرست Base 64',
        'کلش متا',
        'سینگ باکس',
        'وایرگارد',
        'آمنزیا',
        'میرو',
      ],
    );
  });

  test('پایه از خود نشانی اشتراک هم درست استخراج می شود', () {
    final List<SubscriptionSource> sources = SubscriptionEndpoints.build(
      subscriptionUrl: '$base$uuid/sub/',
      accountBase: 'https://user.umbrella-server.ir/',
      uuid: uuid,
    );

    expect(sources.first.url, '$base$uuid/sub/');
  });

  test('بدون شناسه کاربر فقط نشانی خام سرور استفاده می شود', () {
    final List<SubscriptionSource> sources = SubscriptionEndpoints.build(
      subscriptionUrl: '$base$uuid/sub/',
      accountBase: base,
      uuid: '',
    );

    expect(sources, hasLength(1));
    expect(sources.first.url, '$base$uuid/sub/');
    expect(sources.first.personal, isTrue);
  });

  test('نشانی بدون مسیر راز پنل با پایه کامل برنامه اصلاح می شود', () {
    final List<SubscriptionSource> sources = SubscriptionEndpoints.build(
      subscriptionUrl: 'https://user.umbrella-server.ir/$uuid/sub/',
      accountBase: 'https://user.umbrella-server.ir/',
      uuid: uuid,
    );

    // آدرس نباید فقط /<شناسه>/sub/ باشد؛ مسیر پنل هم لازم است.
    expect(
      Uri.parse(sources.first.url).pathSegments.length,
      greaterThan(2),
    );
    expect(sources.first.url, endsWith('/$uuid/sub/'));
  });

  test('اگر سرور هیچ نشانی ندهد پایه خود برنامه استفاده می شود', () {
    final List<SubscriptionSource> sources = SubscriptionEndpoints.build(
      subscriptionUrl: '',
      accountBase: '',
      uuid: uuid,
    );

    expect(sources, isNotEmpty);
    expect(sources.first.url, contains(uuid));
    expect(Uri.parse(sources.first.url).pathSegments.length, greaterThan(2));
    expect(sources.first.url, endsWith('/$uuid/sub/'));
  });
}
