import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:umbrella_vpn/data/gateway_client.dart';

void main() {
  test('Android gateway builds the AppApi route and client headers', () async {
    final client = GatewayClient(
      baseUrl: 'https://example.com/index.php?AppApi=',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.queryParameters['AppApi'], 'app/ping');
        expect(request.headers['X-Umbrella-Client'], startsWith('Android/'));
        return http.Response('{"ok":true}', 200);
      }),
    );
    expect(await client.ping(), isTrue);
    client.close();
  });

  test('authentication POST retries WAF response as form data', () async {
    var requests = 0;
    final client = GatewayClient(
      baseUrl: 'https://example.com/index.php?AppApi=',
      client: MockClient((request) async {
        requests++;
        expect(request.url.queryParameters['AppApi'], 'auth/resend');
        if (requests == 1) {
          expect(jsonDecode(request.body)['challenge'], 'abc');
          return http.Response('blocked', 403);
        }
        expect(request.headers['Content-Type'],
            startsWith('application/x-www-form-urlencoded'));
        expect(jsonDecode(Uri.splitQueryString(request.body)['_json']!)['challenge'], 'abc');
        return http.Response('{"ok":true}', 200);
      }),
    );
    await client.resend('abc');
    expect(requests, 2);
    client.close();
  });
}
