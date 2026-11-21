import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbrella_vpn/core/storage.dart';
import 'package:umbrella_vpn/data/gateway_client.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/state/auth_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('phone validation keeps the original login message and skips network', () async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.instance.init();
    var requests = 0;
    final gateway = GatewayClient(client: MockClient((request) async {
      requests++;
      return http.Response('{}', 200);
    }));
    final auth = AuthController(native: NativeBridge(), gateway: gateway);
    expect(await auth.submitPhone('123'), isFalse);
    expect(auth.error, 'شماره موبایل معتبر نیست؛ نمونه: ۰۹۱۲۳۴۵۶۷۸۹');
    expect(requests, 0);
    auth.dispose();
    gateway.close();
  });

  test('login sends Android device profile without saving the OTP', () async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(request.url.queryParameters['AppApi'], 'auth/start');
      expect(body['phone'], '09123456789');
      expect(body['platform'], contains('اندروید'));
      expect(body.containsKey('code'), isFalse);
      return http.Response('{"ok":true,"challenge":"test","stage":"code","resend_after":0}', 200);
    });
    final gateway = GatewayClient(client: client);
    final auth = AuthController(native: NativeBridge(), gateway: gateway);
    await auth.restore();
    expect(await auth.submitPhone('09123456789'), isTrue);
    expect(auth.phase, AuthPhase.code);
    auth.dispose();
    gateway.close();
  });
}
