import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:umbrella_vpn/data/gateway_client.dart';

void main() {
  test('wallet status returns shared balance and pending server order', () async {
    final gateway = GatewayClient(
      baseUrl: 'https://gateway.example.test', enableNativeTransport: false,
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/wallet/status');
        expect(request.url.queryParameters['token'], 'session-token');
        return http.Response(jsonEncode(<String, dynamic>{
          'ok': true, 'balance': 1250.5, 'min_topup': 80000,
          'max_topup': 100000000, 'payment_pending': true,
          'pending_wallet_topup': true, 'pending_credit': 80000,
          'pending_amount': 80100.5,
          'checkout_url': 'https://pay.example.test/order',
        }), 200, headers: <String, String>{'content-type': 'application/json'});
      }),
    );
    final result = await gateway.walletStatus('session-token');
    expect(result['balance'], 1250.5);
    expect(result['min_topup'], 80000);
    expect(result['pending_amount'], 80100.5);
    expect(result['checkout_url'], 'https://pay.example.test/order');
  });

  test('wallet topup sends amount but never client-supplied success or fee', () async {
    final gateway = GatewayClient(
      baseUrl: 'https://gateway.example.test', enableNativeTransport: false,
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/wallet/topup');
        expect(jsonDecode(request.body), <String, dynamic>{
          'token': 'session-token', 'amount': 80000,
        });
        return http.Response(jsonEncode(<String, dynamic>{
          'ok': true, 'status': 'payment_required', 'credit': 80000,
          'gateway_amount': 80100.5, 'fee': 100.5,
          'checkout_url': 'https://pay.example.test/order',
        }), 200, headers: <String, String>{'content-type': 'application/json'});
      }),
    );
    final result = await gateway.startWalletTopup(token: 'session-token', amount: 80000);
    expect(result['status'], 'payment_required');
    expect(result['fee'], 100.5);
  });

  test('verify asks server to check its stored pending order only', () async {
    final gateway = GatewayClient(
      baseUrl: 'https://gateway.example.test', enableNativeTransport: false,
      client: MockClient((request) async {
        expect(request.url.path, '/wallet/verify');
        expect(jsonDecode(request.body), <String, dynamic>{'token': 'session-token'});
        return http.Response('{"ok":true,"balance":80000,"payment_pending":false}',
          200, headers: <String, String>{'content-type': 'application/json'});
      }),
    );
    final result = await gateway.verifyWalletTopup('session-token');
    expect(result['balance'], 80000);
    expect(result['payment_pending'], false);
  });
}
