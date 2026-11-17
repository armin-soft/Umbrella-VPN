import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:umbrella_vpn/core/persian.dart';
import 'package:umbrella_vpn/data/panel_client.dart';
import 'package:umbrella_vpn/models/models.dart';

/// پاسخ نمونه پنل (همان شکل API نسخه Watashi) برای آزمون خواندن دقیق اعداد.
class _FakeClient extends http.BaseClient {
  _FakeClient(this.body, {this.status = 200});

  final String body;
  final int status;
  Uri? lastUri;
  Map<String, String>? lastHeaders;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastUri = request.url;
    lastHeaders = request.headers;
    final List<int> bytes = utf8Encode(body);
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      status,
      headers: <String, String>{'content-type': 'application/json'},
      request: request,
    );
  }
}

List<int> utf8Encode(String value) => utf8.encode(value);

void main() {
  group('پنل: خواندن حساب', () {
    test('اعداد مصرف، حجم و تاریخ انقضا درست خوانده می شوند', () async {
      final _FakeClient client = _FakeClient('''
      {
        "uuid": "11111111-2222-3333-4444-555555555555",
        "name": "Umbrella User",
        "phone": "09120000000",
        "usage_limit_GB": 60.0,
        "current_usage_GB": 15.5,
        "package_days": 30,
        "expire_date": "2026-12-01T10:00:00Z",
        "start_date": "2026-11-01T10:00:00Z",
        "last_online": 1762600000,
        "enable": true
      }
      ''');
      final PanelUserApi panel = PanelUserApi(client: client);
      final Account? account = await panel.user('1111');

      expect(account, isNotNull);
      expect(account!.name, 'Umbrella User');
      expect(account.usageLimitGb, 60.0);
      expect(account.currentUsageGb, 15.5);
      expect(account.remainingGb, 44.5);
      expect(account.usagePercent, closeTo(25.83, 0.05));
      expect(account.totalGb, 60.0);
      expect(account.expiryDate, isNotNull);
      expect(account.lastOnline, isNotNull);
      expect(client.lastUri.toString(),
          contains('/api/v2/admin/user/1111/'));
      expect(client.lastHeaders!['Watashi-API-Key'], isNotNull);
    });

    test('کلیدهای دیگر (usageLimit / currentUsage) هم پذیرفته می شوند', () async {
      final _FakeClient client = _FakeClient('''
      {"uuid":"a","name":"x","usageLimit":10,"currentUsage":2.5}
      ''');
      final Account? account =
          await PanelUserApi(client: client).user('a');
      expect(account!.usageLimitGb, 10);
      expect(account.currentUsageGb, 2.5);
      expect(account.remainingGb, 7.5);
    });

    test('پاسخ ناموفق یا خالی باعث خطا نمی شود', () async {
      final _FakeClient failing =
          _FakeClient('{"detail":"not found"}', status: 404);
      expect(await PanelUserApi(client: failing).user('a'), isNull);
      final _FakeClient broken = _FakeClient('<html>error</html>');
      expect(await PanelUserApi(client: broken).user('a'), isNull);
    });
  });

  group('محاسبه های حساب', () {
    test('حجم نامحدود درصد مصرف صفر دارد و باقی مانده بی نهایت نیست', () {
      const Account account = Account(usageLimitGb: 0, currentUsageGb: 5);
      expect(account.usagePercent, 0);
      expect(account.remainingGb, 0);
      expect(account.unlimited, isTrue);
    });

    test('مصرف بیش از سقف، درصد را بالای ۱۰۰ نمی برد', () {
      const Account account = Account(usageLimitGb: 10, currentUsageGb: 12);
      expect(account.usagePercent, 100);
      expect(account.remainingGb, 0);
      expect(account.overLimit, isTrue);
    });

    test('نسخه فارسی اعداد، ارقام لاتین را تبدیل می کند', () {
      expect(Fa.num('123'), '۱۲۳');
    });

    test('پاسخ کامل نسخه ۲ پنل با دقت کامل شمسی و بدون نشت کلید خصوصی خوانده می شود', () async {
      final _FakeClient client = _FakeClient('''
      {
        "added_by_uuid": "75303f38-8bc0-4313-966a-66439de29c76",
        "awg_ipv4": "10.91.0.3",
        "awg_ipv6": "fd42:42:91::3",
        "comment": "09358983854",
        "current_usage_GB": 425.154737457633,
        "ed25519_private_key": "SECRET_ED25519_PRIVATE",
        "ed25519_public_key": "PUBLIC_ED25519",
        "enable": true,
        "id": 2,
        "is_active": true,
        "lang": "fa",
        "last_online": "2026-11-17 21:20:31",
        "last_reset_time": "2026-10-31 00:00:00",
        "mode": "no_reset",
        "name": "آرمین اسکندری",
        "package_days": 365,
        "start_date": "2026-08-03",
        "telegram_id": 592526230,
        "usage_limit_GB": 1000,
        "username": null,
        "uuid": "9b9d9f5d-9841-45bf-a6b9-0479de273c11",
        "wg_ipv4": "10.90.0.3",
        "wg_ipv6": "fd42:42:90::3",
        "wg_pk": "SECRET_WG_PK",
        "wg_psk": "SECRET_WG_PSK",
        "wg_pub": "PUBLIC_WG_PUB"
      }
      ''');

      final Account? account = await PanelUserApi(client: client)
          .user('9b9d9f5d-9841-45bf-a6b9-0479de273c11');
      expect(account, isNotNull);
      expect(account!.panelId, 2);
      expect(account.displayName, 'آرمین اسکندری');
      expect(account.effectivePhone, '09358983854');
      expect(Fa.phoneFa(account.effectivePhone), '۰۹۳۵-۸۹۸-۳۸۵۴');
      expect(account.telegramId, '592526230');
      expect(account.planLabel, 'بسته ۳۶۵ روزه');
      expect(account.packageDurationLabel, 'یک ساله (۳۶۵ روز)');
      expect(account.modeLabelFa, 'بدون بازنشانی دوره ای');
      expect(account.langLabelFa, 'فارسی');
      expect(account.statusLabelFa, 'فعال و مجاز');
      expect(account.wgIpv4, '10.90.0.3');
      expect(account.wgIpv6, 'fd42:42:90::3');
      expect(account.awgIpv4, '10.91.0.3');
      expect(account.awgIpv6, 'fd42:42:91::3');
      expect(account.remainingGb, closeTo(574.845, 0.01));
      expect(account.usagePercent, closeTo(42.515, 0.01));

      // بررسی تاریخ و ساعت دقیق شمسی به وقت رسمی ایران (UTC+03:30)
      expect(Fa.tehranDate(account.startDate), '۱۴۰۵/۰۵/۱۲');
      expect(Fa.tehranFullDate(account.startDate), 'دوشنبه ۱۲ مرداد ۱۴۰۵');
      expect(Fa.tehranDate(account.effectiveExpiryDate), '۱۴۰۶/۰۵/۱۲');
      expect(
        Fa.tehranFullDate(account.effectiveExpiryDate),
        'سه شنبه ۱۲ مرداد ۱۴۰۶',
      );
      expect(Fa.tehranDate(account.lastResetTime), '۱۴۰۵/۰۸/۰۹');
      expect(
        Fa.tehranFullDateTime(account.lastResetTime),
        'شنبه ۹ آبان ۱۴۰۵ • ساعت ۰۰:۰۰:۰۰',
      );
      expect(Fa.tehranDate(account.lastOnline), '۱۴۰۵/۰۸/۲۶');
      expect(
        Fa.tehranFullDateTime(account.lastOnline),
        'سه شنبه ۲۶ آبان ۱۴۰۵ • ساعت ۲۱:۲۰:۳۱',
      );

      // زمان سنجی دقیق در لحظه 2026-11-17 21:20:45 به وقت تهران
      final DateTime refNow = Fa.parseServerDateTime('2026-11-17 21:20:45')!;
      expect(account.isOnlineRecently(refNow), isTrue);
      expect(account.daysElapsedAt(refNow), 106);
      expect(account.daysLeftAt(refNow), 258);
      expect(
        Fa.spanFa(account.remainingDuration(refNow)),
        '۲۵۸ روز و ۲ ساعت و ۳۹ دقیقه',
      );
      expect(account.dailyAverageGb(refNow), closeTo(3.98, 0.02));

      // هیچ کلید خصوصی نباید در خروجی ذخیره سازی وجود داشته باشد
      final String serialized = jsonEncode(account.toJson());
      expect(serialized.contains('SECRET_ED25519_PRIVATE'), isFalse);
      expect(serialized.contains('SECRET_WG_PK'), isFalse);
      expect(serialized.contains('SECRET_WG_PSK'), isFalse);
      expect(serialized.contains('wg_pk'), isFalse);
      expect(serialized.contains('wg_psk'), isFalse);
      expect(serialized.contains('ed25519_private_key'), isFalse);
    });
  });

  group('تقویم دقیق هجری شمسی و صفحه دستگاه من', () {
    test('سال های کبیسه ۴ ساله و ۵ ساله و تبدیل دوطرفه کاملاً دقیق است', () {
      expect(JalaliDate.isLeap(1403), isTrue);
      expect(JalaliDate.isLeap(1404), isFalse);
      expect(JalaliDate.isLeap(1407), isFalse);
      expect(JalaliDate.isLeap(1408), isTrue);

      expect(Fa.date(DateTime.utc(2025, 3, 20)), '۱۴۰۳/۱۲/۳۰');
      expect(Fa.fullDate(DateTime.utc(2025, 3, 20)), 'پنجشنبه ۳۰ اسفند ۱۴۰۳');
      expect(Fa.date(DateTime.utc(2025, 3, 21)), '۱۴۰۴/۰۱/۰۱');
      expect(Fa.date(DateTime.utc(2026, 3, 20)), '۱۴۰۴/۱۲/۲۹');
      expect(Fa.date(DateTime.utc(2026, 3, 21)), '۱۴۰۵/۰۱/۰۱');
      expect(Fa.date(DateTime.utc(2030, 3, 20)), '۱۴۰۸/۱۲/۳۰');
      expect(Fa.fullDate(DateTime.utc(2030, 3, 20)), 'چهارشنبه ۳۰ اسفند ۱۴۰۸');
      expect(Fa.date(DateTime.utc(2030, 3, 21)), '۱۴۰۹/۰۱/۰۱');

      expect(Fa.parseServerDateTime('0001-01-01 00:00:00'), isNull);
      expect(Fa.parseServerDateTime('0000-00-00'), isNull);

      DateTime cursor = DateTime.utc(2000, 1, 1);
      final DateTime end = DateTime.utc(2060, 1, 1);
      while (cursor.isBefore(end)) {
        final JalaliDate j = JalaliDate.fromDateTime(cursor);
        expect(j.day, inInclusiveRange(1, j.monthLength));
        expect(j.toUtcDate(), cursor);
        cursor = cursor.add(const Duration(days: 1));
      }
    });

    test('صفحه دستگاه من بدون نیم فاصله و بدون افشای کلید خصوصی یا لینک اشتراک است', () {
      final String device = File('lib/ui/pages/device_page.dart').readAsStringSync();
      expect(device.contains('\u200C'), isFalse);
      expect(device.contains('subscriptionUrl'), isFalse);
      expect(device.contains('wg_pk'), isFalse);
      expect(device.contains('wg_psk'), isFalse);
      expect(device.contains('ed25519_private_key'), isFalse);
      expect(device.contains('refreshFromPanel'), isTrue);
      expect(device.contains('Fa.tehranFullDate'), isTrue);
    });
  });
}
