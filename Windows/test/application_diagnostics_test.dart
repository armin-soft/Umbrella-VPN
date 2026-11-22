import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:umbrella_vpn/data/gateway_client.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/platform/services.dart';
import 'package:umbrella_vpn/state/toast_controller.dart';
import 'package:umbrella_vpn/state/update_controller.dart';

void main() {
  setUp(() => AppLogger.instance.clear());
  tearDown(() => AppLogger.instance.clear());

  test('gateway logs account and payment failures without payloads or server messages', () async {
    final client = MockClient((request) async => http.Response(
      '{"ok":false,"error":"PRIVATE_CODE","message":"private-password 09121234567"}', 403));
    final gateway = GatewayClient(client: client);
    addTearDown(() { gateway.close(); });
    for (var i = 0; i < 2; i++) {
      await expectLater(gateway.startWalletTopup(token: 'private-token', amount: 5000), throwsA(anything));
    }
    await expectLater(gateway.refresh('private-token'), throwsA(anything));
    final lines = AppLogger.instance.lines;
    expect(lines.length, 2); // repeated polling failure is throttled
    final output = AppLogger.instance.exportText();
    expect(output, contains('wallet/topup'));
    expect(output, contains('account/refresh'));
    expect(output, contains('HTTP 403'));
    for (final secret in ['PRIVATE_CODE', 'private-password', '09121234567', 'private-token']) {
      expect(output, isNot(contains(secret)));
    }
  });

  test('UI error and warning categories are recorded without user messages', () {
    final toast = ToastController();
    addTearDown(toast.dispose);
    toast.error('خرید انجام نشد', 'private-token 09121234567');
    toast.warning('ذخیره تنظیمات', 'private-password');
    toast.success('موفق');
    final output = AppLogger.instance.exportText();
    expect(output, contains('پرداخت و کیف پول'));
    expect(output, contains('تنظیمات'));
    expect(output, isNot(contains('private-token')));
    expect(output, isNot(contains('private-password')));
    expect(output, isNot(contains('09121234567')));
    expect(AppLogger.instance.lines.length, 2);
  });

  test('silent update failure is logged once and can be retried', () async {
    final client = MockClient((_) async => throw const SocketException('secret'));
    final updates = UpdateController(NativeBridge(), service: UpdateService(client: client));
    addTearDown(() { updates.dispose(); client.close(); });
    await updates.check(silent: true);
    await updates.check(silent: true);
    expect(AppLogger.instance.lines.where((line) => line.message.contains('بررسی به روز رسانی ناموفق')).length, 1);
    expect(AppLogger.instance.exportText(), isNot(contains('secret')));
  });
}
