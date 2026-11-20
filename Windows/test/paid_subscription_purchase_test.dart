import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:umbrella_vpn/data/gateway_client.dart';
import 'package:umbrella_vpn/models/models.dart';

void main() {
  test('tariff payload maps paid plans and their live shared-wallet balance', () async {
    final GatewayClient gateway = GatewayClient(
      baseUrl: 'https://gateway.example.test',
      enableNativeTransport: false,
      client: MockClient((http.Request request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/subscription/plans');
        expect(request.url.queryParameters['token'], 'session-token');
        return http.Response(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'plans': <Map<String, dynamic>>[
              <String, dynamic>{
                'month': '1',
                'name': '۱ ماهه',
                'days': 30,
                'price': 250000,
              },
              <String, dynamic>{
                'month': '3',
                'name': '۳ ماهه',
                'days': 90,
                'price': 600000,
              },
            ],
            'balance': 125000,
            'custom': <String, dynamic>{'day_rate': 1000.5, 'min_days': 2,
              'max_days': 365, 'min_gb': 0.5, 'max_gb': 1000},
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );
    final ({List<SubscriptionPlan> plans, int balance, CustomSubscriptionTerms? custom}) result =
        await gateway.subscriptionPlans('session-token');
    expect(result.balance, 125000);
    expect(result.custom!.priceForDays(10), 10005);
    expect(result.custom!.minGb, 0.5);
    expect(result.plans, hasLength(2));
    expect(result.plans.first.month, '1');
    expect(result.plans.first.days, 30);
    expect(result.plans.first.price, 250000);
  });

  test('purchase sends only the selected server tariff key and handles checkout response', () async {
    final GatewayClient gateway = GatewayClient(
      baseUrl: 'https://gateway.example.test',
      enableNativeTransport: false,
      client: MockClient((http.Request request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/subscription/purchase');
        final Map<String, dynamic> body =
            jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['token'], 'session-token');
        expect(body['month'], '3');
        expect(body.containsKey('amount'), isFalse);
        expect(body.containsKey('paid'), isFalse);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'status': 'payment_required',
            'checkout_url': 'https://pay.example.test/order',
            'gateway_amount': 485000,
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );
    final Map<String, dynamic> result = await gateway.purchaseSubscription(
      token: 'session-token',
      month: '3',
    );
    expect(result['status'], 'payment_required');
    expect(result['checkout_url'], 'https://pay.example.test/order');
  });
  test('custom purchase submits selection and quote, not a payment result', () async {
    final GatewayClient gateway = GatewayClient(
      baseUrl: 'https://gateway.example.test', enableNativeTransport: false,
      client: MockClient((http.Request request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.url.path, '/subscription/purchase');
        expect(body['type'], 'custom');
        expect(body['days'], 10);
        expect(body['gb'], 5.5);
        expect(body['quoted_price'], 10005);
        expect(body.containsKey('amount'), isFalse);
        expect(body.containsKey('paid'), isFalse);
        return http.Response(jsonEncode(<String, dynamic>{
          'ok': true, 'status': 'activated',
        }), 200, headers: <String, String>{'content-type': 'application/json'});
      }),
    );
    final result = await gateway.purchaseCustomSubscription(
      token: 'session-token', days: 10, gb: 5.5, quotedPrice: 10005,
    );
    expect(result['status'], 'activated');
  });

}
