import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'dart:convert';

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
      final PanelClient panel = PanelClient(client: client);
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
          await PanelClient(client: client).user('a');
      expect(account!.usageLimitGb, 10);
      expect(account.currentUsageGb, 2.5);
      expect(account.remainingGb, 7.5);
    });

    test('پاسخ ناموفق یا خالی باعث خطا نمی شود', () async {
      final _FakeClient failing =
          _FakeClient('{"detail":"not found"}', status: 404);
      expect(await PanelClient(client: failing).user('a'), isNull);
      final _FakeClient broken = _FakeClient('<html>error</html>');
      expect(await PanelClient(client: broken).user('a'), isNull);
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
  });
}
