import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/models/models.dart';

/// قاعده دسترسی: اشتراک منقضی، مسدود، غیرفعال یا تمام شده حق اتصال ندارد.
void main() {
  final DateTime future = DateTime.now().add(const Duration(days: 12));
  final DateTime past = DateTime.now().subtract(const Duration(days: 2));

  group('دسترسی حساب', () {
    test('حساب سالم اجازه اتصال دارد', () {
      final Account account = Account(
        enable: true,
        isActive: true,
        usageLimitGb: 60,
        currentUsageGb: 10,
        expiryDate: future,
      );
      expect(account.healthy, isTrue);
      expect(account.canConnect, isTrue);
      expect(account.accessReason, isEmpty);
    });

    test('اشتراک منقضی اجازه اتصال ندارد', () {
      final Account account = Account(
        enable: true,
        isActive: true,
        usageLimitGb: 60,
        currentUsageGb: 10,
        expiryDate: past,
      );
      expect(account.expired, isTrue);
      expect(account.canConnect, isFalse);
      expect(account.accessReason, contains('منقضی'));
    });

    test('حساب مسدود اجازه اتصال ندارد', () {
      const Account account = Account(
        enable: false,
        isActive: true,
        usageLimitGb: 60,
        currentUsageGb: 1,
      );
      expect(account.canConnect, isFalse);
      expect(account.accessReason, contains('مسدود'));
    });

    test('اشتراک غیرفعال اجازه اتصال ندارد', () {
      const Account account = Account(
        enable: true,
        isActive: false,
        usageLimitGb: 60,
        currentUsageGb: 1,
      );
      expect(account.canConnect, isFalse);
      expect(account.accessReason, contains('فعال نیست'));
    });

    test('اتمام حجم اجازه اتصال را می بندد', () {
      final Account account = Account(
        enable: true,
        isActive: true,
        usageLimitGb: 30,
        currentUsageGb: 30.4,
        expiryDate: future,
      );
      expect(account.quotaFinished, isTrue);
      expect(account.canConnect, isFalse);
      expect(account.accessReason, contains('حجم'));
    });

    test('بسته بدون سقف حجم با اتمام حجم بسته نمی شود', () {
      final Account account = Account(
        enable: true,
        isActive: true,
        usageLimitGb: 0,
        currentUsageGb: 900,
        expiryDate: future,
      );
      expect(account.quotaFinished, isFalse);
      expect(account.canConnect, isTrue);
    });

    test('چند دلیل هم زمان، همه در پیام می آیند', () {
      final Account account = Account(
        enable: false,
        isActive: true,
        usageLimitGb: 5,
        currentUsageGb: 5,
        expiryDate: past,
      );
      expect(account.accessReason, contains('مسدود'));
      expect(account.accessReason, contains('منقضی'));
      expect(account.accessReason, contains('حجم'));
      expect(account.accessReason, contains('تمدید'));
    });
  });
}
