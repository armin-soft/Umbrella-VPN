import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:umbrella_vpn/data/emergency_feeds.dart';

void main() {
  const link = 'vless://9b9d9f5d-9841-45bf-a6b9-0479de273c11@example.org:443#test';
  test('fixed public feeds and safe basic links', () {
    expect(EmergencyFeeds.urls.length, 6);
    final result = EmergencyFeeds.parse('$link\nvless://9b9d9f5d-9841-45bf-a6b9-0479de273c11@127.0.0.1:443#local', 0);
    expect(result.nodes.length, 1);
    expect(result.nodes.single.sourceId, 'emergency-0');
    expect(EmergencyFeeds.parse('warp://auto\npsiphon://auto', 0).nodes, isEmpty);
    expect(EmergencyFeeds.parse('//comment\n[{"type":"direct"}]', 5).nodes, isEmpty);
  });
  test('fetch does not follow redirects or send account credentials', () async {
    final client = MockClient((request) async {
      expect(request.followRedirects, isFalse);
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(request.url.toString(), EmergencyFeeds.urls[0]);
      return http.Response(link, 200);
    });
    expect((await EmergencyFeeds.fetch(client, 0)).nodes.length, 1);
    client.close();
  });
  test('oversized and HTML responses are rejected', () async {
    expect(EmergencyFeeds.parse('<html>invalid</html>', 0).nodes, isEmpty);
    final client = MockClient((_) async => http.Response.bytes(List<int>.filled(EmergencyFeeds.maxBytes + 1, 65), 200));
    expect((await EmergencyFeeds.fetch(client, 0)).nodes, isEmpty);
    expect(utf8.encode('test').length, 4);
    client.close();
  });
}
