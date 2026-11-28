import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/core/app_config.dart';
import 'package:umbrella_vpn/core/persian.dart';
import 'package:umbrella_vpn/models/models.dart';

void main() {
  group('مرز امنیتی اطلاعات حساب', () {
    test('کلید و کلاینت API مدیریتی پنل در کلاینت ویندوز وجود ندارند', () {
      final String config = File('lib/core/app_config.dart').readAsStringSync();
      final String gateway =
          File('lib/data/gateway_client.dart').readAsStringSync();
      final String auth =
          File('lib/state/auth_controller.dart').readAsStringSync();
      final String docs = File('docs/API.md').readAsStringSync();

      for (final String content in <String>[config, gateway, auth, docs]) {
        expect(content, isNot(contains('Hiddify-API-Key')));
        expect(content, isNot(contains('Watashi-API-Key')));
        expect(content, isNot(contains('UMBRELLA_PANEL_KEY')));
      }
      expect(config, isNot(contains('panelApiKey')));
      expect(gateway, isNot(contains('class PanelClient')));
      expect(auth, isNot(contains('PanelUserApi')));
      expect(File('lib/data/panel_client.dart').existsSync(), isFalse);

      // تنها مسیر اطلاعات زنده حساب باید از درگاه احراز هویت شده سرور باشد.
      expect(gateway, contains("_get('account/refresh'"));
      expect(auth, contains('_gateway.refresh(session.token)'));
    });

    test('مدل حساب، پاسخ Gateway را می خواند و هیچ کلید خصوصی ذخیره نمی کند', () {
      final Account account = Account.fromJson(<String, dynamic>{
        'id': 2,
        'uuid': '11111111-2222-4333-8444-555555555555',
        'name': 'Umbrella User',
        'phone': '09120000000',
        'usage_limit_GB': 60.0,
        'current_usage_GB': 15.5,
        'package_days': 30,
        'start_date': '2026-11-01T10:00:00Z',
        'expire_date': '2026-12-01T10:00:00Z',
        'last_online': 1762600000,
        'enable': true,
        'is_active': true,
        'wg_ipv4': '10.90.0.3',
        'awg_ipv4': '10.91.0.3',
        'wg_pk': 'SECRET_WG_PK',
        'wg_psk': 'SECRET_WG_PSK',
        'ed25519_private_key': 'SECRET_ED25519_PRIVATE',
      });

      expect(account.panelId, 2);
      expect(account.name, 'Umbrella User');
      expect(account.usageLimitGb, 60.0);
      expect(account.currentUsageGb, 15.5);
      expect(account.remainingGb, 44.5);
      expect(account.usagePercent, closeTo(25.83, 0.05));
      expect(account.expiryDate, isNotNull);
      expect(account.lastOnline, isNotNull);
      expect(account.wgIpv4, '10.90.0.3');
      expect(account.awgIpv4, '10.91.0.3');

      final String serialized = jsonEncode(account.toJson());
      for (final String secret in <String>[
        'SECRET_WG_PK',
        'SECRET_WG_PSK',
        'SECRET_ED25519_PRIVATE',
        'wg_pk',
        'wg_psk',
        'ed25519_private_key',
      ]) {
        expect(serialized, isNot(contains(secret)));
      }
    });

    test('حساب نامحدود و سقف مصرف صحیح محاسبه می شوند', () {
      const Account unlimited = Account(usageLimitGb: 0, currentUsageGb: 5);
      expect(unlimited.usagePercent, 0);
      expect(unlimited.remainingGb, 0);
      expect(unlimited.unlimited, isTrue);

      const Account overLimit =
          Account(usageLimitGb: 10, currentUsageGb: 12);
      expect(overLimit.usagePercent, 100);
      expect(overLimit.remainingGb, 0);
      expect(overLimit.overLimit, isTrue);
    });

    test('اعداد فارسی و تاریخ های شمسی دقیق باقی می مانند', () {
      expect(Fa.num('123'), '۱۲۳');
      expect(Fa.date(DateTime.utc(2025, 3, 20)), '۱۴۰۳/۱۲/۳۰');
      expect(Fa.date(DateTime.utc(2025, 3, 21)), '۱۴۰۴/۰۱/۰۱');
      expect(Fa.date(DateTime.utc(2026, 3, 20)), '۱۴۰۴/۱۲/۲۹');
      expect(Fa.date(DateTime.utc(2026, 3, 21)), '۱۴۰۵/۰۱/۰۱');
      expect(Fa.parseServerDateTime('0001-01-01 00:00:00'), isNull);
      expect(Fa.parseServerDateTime('0000-00-00'), isNull);

      DateTime cursor = DateTime.utc(2000, 1, 1);
      final DateTime end = DateTime.utc(2060, 1, 1);
      while (cursor.isBefore(end)) {
        final JalaliDate date = JalaliDate.fromDateTime(cursor);
        expect(date.day, inInclusiveRange(1, date.monthLength));
        expect(date.toUtcDate(), cursor);
        cursor = cursor.add(const Duration(days: 1));
      }
    });

    test('مشخصات حساب و دستگاه در صفحه های جدا هستند', () {
      final String device =
          File('lib/ui/pages/device_page.dart').readAsStringSync();
      final String account =
          File('lib/ui/pages/account_page.dart').readAsStringSync();

      for (final String accountOnly in <String>[
        'auth_controller.dart',
        'AuthController',
        'usageLimitGb',
        'currentUsageGb',
        'effectiveExpiryDate',
        'telegramId',
        'wgIpv4',
        'awgIpv4',
        'subscriptionUrl',
        'حجم قابل استفاده',
        'تاریخ پایان اعتبار',
        'شناسه تلگرام',
        'شماره موبایل',
      ]) {
        expect(device, isNot(contains(accountOnly)), reason: accountOnly);
      }
      expect(account, contains('refreshAccount'));
      expect(account, contains('Fa.tehranFullDate'));
      for (final String forbidden in <String>[
        'DeviceProfile',
        'ramTotalMb',
        'diskTotalMb',
        'cpuLabelFa',
        'machineId',
        'subscriptionUrl',
        'wg_pk',
        'wg_psk',
        'ed25519_private_key',
      ]) {
        expect(account, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });

  test('نسخهٔ ویندوز با نسخهٔ انتشار همسان است', () {
    expect(AppConfig.version, '1.0.3');
  });
}
