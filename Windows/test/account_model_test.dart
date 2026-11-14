import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/models/models.dart';

/// آزمون نگاشت پروفایل کامل کاربر از سرور، همان ساختاری که در
/// `docs/API.md` قرارداد شده است.
void main() {
  const String uuid = '11111111-2222-3333-4444-555555555555';

  final Map<String, dynamic> payload = <String, dynamic>{
    'uuid': uuid,
    'name': 'آرمین',
    'phone': '09121234567',
    'telegram_id': '123456789',
    'comment': '',
    'enable': true,
    'is_active': true,
    'usage_limit_GB': 100.0,
    'current_usage_GB': 12.4,
    'package_days': 30,
    'start_date': '2026-11-01',
    'expiry_date': '2026-12-01',
    'last_online': '2026-11-10 12:00:00',
    'mode': 'xray',
    'subscription_url': 'https://user.umbrella-server.ir/$uuid/sub/',
    'account_base': 'https://user.umbrella-server.ir/',
  };

  test('همه فیلدهای پروفایل از سرور خوانده می شوند', () {
    final Account account = Account.fromJson(payload);

    expect(account.uuid, uuid);
    expect(account.name, 'آرمین');
    expect(account.phone, '09121234567');
    expect(account.telegramId, '123456789');
    expect(account.usageLimitGb, 100);
    expect(account.currentUsageGb, 12.4);
    expect(account.packageDays, 30);
    expect(account.mode, 'xray');
    expect(account.startDate, isNotNull);
    expect(account.expiryDate, isNotNull);
    expect(account.lastOnline, isNotNull);
  });

  test('نشانی اشتراک شخصی از سرور می آید', () {
    final Account account = Account.fromJson(payload);

    expect(account.subscriptionUrl, contains('/sub/'));
    expect(account.subscriptionUrl, contains(uuid));
    expect(account.accountBase, 'https://user.umbrella-server.ir/');
  });

  test('حجم باقی مانده و درصد مصرف درست حساب می شود', () {
    final Account account = Account.fromJson(payload);

    expect(account.remainingGb, closeTo(87.6, 0.001));
    expect(account.usagePercent, closeTo(12.4, 0.001));
  });

  test('وضعیت حساب و نوع سرویس از داده سرور ساخته می شود', () {
    final Account account = Account.fromJson(payload);

    expect(account.healthy, isTrue);
    expect(account.planLabel, contains('۳۰'));

    final Account expired = Account.fromJson(<String, dynamic>{
      ...payload,
      'expiry_date': '2020-01-01',
    });
    expect(expired.expired, isTrue);
    expect(expired.healthy, isFalse);
    expect(expired.daysLeft, 0);
  });

  test('اگر سرور نشانی اشتراک ندهد مقدار خالی می ماند', () {
    final Account account = Account.fromJson(<String, dynamic>{
      'uuid': uuid,
      'name': 'آرمین',
    });

    expect(account.subscriptionUrl, isEmpty);
    expect(account.accountBase, isEmpty);
    expect(account.displayName, 'آرمین');
  });

  test('بدون نام، به جای خالی نام پیش فرض نمایش داده می شود', () {
    final Account account = Account.fromJson(<String, dynamic>{'uuid': uuid});

    expect(account.displayName, isNotEmpty);
    expect(account.healthy, isTrue);
  });
}
