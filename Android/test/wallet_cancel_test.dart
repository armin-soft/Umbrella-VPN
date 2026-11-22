import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbrella_vpn/core/storage.dart';
import 'package:umbrella_vpn/data/gateway_client.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/state/auth_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<AuthController> controller(http.Client client) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final LocalStore store = LocalStore.instance;
    await store.init();
    await store.writeJson(StoreKeys.session, SessionData(
      token: 'synthetic-token', uuid: 'synthetic-user', deviceId: 'test-device',
      account: Account.empty, filter: FilterSettings.empty,
    ).toJson());
    final AuthController auth = AuthController(
      native: NativeBridge(), store: store,
      gateway: GatewayClient(baseUrl: 'https://gateway.example.test',
        enableNativeTransport: false, client: client),
    );
    await auth.restore();
    return auth;
  }
  http.Response response(Map<String, Object?> data, [int code = 200]) =>
      http.Response(jsonEncode(data), code,
        headers: <String, String>{'content-type': 'application/json'});

  test('missing secure order id never sends an unsafe cancellation', () async {
    int cancellations = 0;
    final AuthController auth = await controller(MockClient((request) async {
      if (request.url.path == '/wallet/status') {
        return response(<String, Object?>{'ok': true, 'payment_pending': true});
      }
      if (request.url.path == '/wallet/cancel') cancellations++;
      return response(<String, Object?>{'ok': false, 'error': 'unavailable'}, 503);
    }));
    try {
      expect(await auth.refreshWallet(), isTrue);
      expect(await auth.cancelWalletPayment(), isFalse);
      expect(auth.error, contains('شناسه امن'));
      expect(cancellations, 0);
    } finally { auth.dispose(); }
  });

  test('only the order confirmed by user is submitted; server must confirm result', () async {
    int cancellations = 0;
    bool confirm = false;
    const String id = 'synthetic-order-id';
    final AuthController auth = await controller(MockClient((request) async {
      if (request.url.path == '/wallet/status') {
        return response(<String, Object?>{'ok': true, 'payment_pending': true, 'pending_id': id});
      }
      if (request.url.path == '/wallet/cancel') {
        cancellations++;
        expect(jsonDecode(request.body), <String, dynamic>{'token': 'synthetic-token', 'pending_id': id});
        return confirm
            ? response(<String, Object?>{'ok': true, 'payment_pending': false})
            : response(<String, Object?>{'ok': true});
      }
      return response(<String, Object?>{'ok': false, 'error': 'unavailable'}, 503);
    }));
    try {
      expect(await auth.refreshWallet(), isTrue);
      expect(await auth.cancelWalletPayment(expectedPendingId: 'other'), isFalse);
      expect(cancellations, 0);
      expect(await auth.cancelWalletPayment(expectedPendingId: id), isFalse);
      expect(auth.walletPaymentPending, isTrue);
      confirm = true;
      expect(await auth.cancelWalletPayment(expectedPendingId: id), isTrue);
      expect(auth.walletPaymentPending, isFalse);
      expect(cancellations, 2);
    } finally { auth.dispose(); }
  });
}
