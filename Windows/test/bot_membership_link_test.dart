import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:umbrella_vpn/data/gateway_client.dart';

void main() {
  test('account requests a private server-issued bot link', () async {
    final gateway = GatewayClient(
      baseUrl: 'https://gateway.example.test', enableNativeTransport: false,
      client: MockClient((http.Request request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/account/bot-link');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body, <String, dynamic>{'token': 'session-token'});
        return http.Response(jsonEncode(<String, dynamic>{'ok': true,
          'linked': false, 'url': 'https://t.me/test_bot?start=app_123',
          'expires_in': 600}), 200,
          headers: <String, String>{'content-type': 'application/json'});
      }),
    );
    final result = await gateway.createBotMembershipLink('session-token');
    expect(result['url'], 'https://t.me/test_bot?start=app_123');
    expect(result['linked'], false);
  });

  test('link status reads only the authenticated server response', () async {
    final gateway = GatewayClient(
      baseUrl: 'https://gateway.example.test', enableNativeTransport: false,
      client: MockClient((http.Request request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/account/bot-link-status');
        expect(request.url.queryParameters['token'], 'session-token');
        return http.Response('{"ok":true,"linked":true}', 200,
          headers: <String, String>{'content-type': 'application/json'});
      }),
    );
    expect(await gateway.botMembershipStatus('session-token'), true);
  });
}
