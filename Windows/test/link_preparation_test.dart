import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/vpn/link_preparation.dart';

void main() {
  Future<List<InternetAddress>> lookup(String _) async => <InternetAddress>[InternetAddress('192.0.2.10')];

  test('resolves mixed-case endpoint names once and preserves TLS/HTTP identity', () async {
    final List<String> calls = <String>[];
    final PreparedLinks result = await LinkPreparation.prepare(<String>[
      'vless://test@Proxy.Example:443?security=tls&type=ws&path=%2Fa%3Fed%3D2048#one',
      'trojan://p%40ss@proxy.example:443?type=grpc&sni=cdn.example&serviceName=svc#two',
    ], lookup: (String host) async { calls.add(host); return lookup(host); });
    expect(calls, <String>['proxy.example']);
    expect(result.resolvedHosts, 1);
    expect(result.unresolvedHosts, 0);
    final Uri first = Uri.parse(result.links.first);
    expect(first.host, '192.0.2.10');
    expect(first.userInfo, 'test');
    expect(first.queryParameters['sni'], 'proxy.example');
    expect(first.queryParameters['host'], 'proxy.example');
    expect(first.queryParameters['path'], '/a?ed=2048');
    final Uri second = Uri.parse(result.links.last);
    expect(second.userInfo, 'p%40ss');
    expect(second.queryParameters['sni'], 'cdn.example');
    expect(second.queryParameters['serviceName'], 'svc');
  });

  test('mux off really removes inherited mux/brutal but not XHTTP xmux or extra', () async {
    const String extra = '%7B%22xmux%22%3A%7B%22maxConcurrency%22%3A%224-8%22%7D%7D';
    final PreparedLinks result = await LinkPreparation.prepare(<String>[
      'vless://test@192.0.2.1:443?security=reality&type=xhttp&mode=packet-up&extra=$extra'
      '&muxtype=h2mux&muxup=100&muxdown=100&mux=8&sni=cdn.example&pbk=key&sid=ab&fp=chrome#name',
    ], lookup: (_) => throw StateError('numeric addresses must not trigger DNS'));
    final Uri uri = Uri.parse(result.links.single);
    expect(uri.queryParameters.containsKey('muxtype'), false);
    expect(uri.queryParameters.containsKey('muxup'), false);
    expect(uri.queryParameters.containsKey('muxdown'), false);
    expect(uri.queryParameters['extra'], '{"xmux":{"maxConcurrency":"4-8"}}');
    expect(uri.queryParameters['mode'], 'packet-up');
    expect(uri.queryParameters['pbk'], 'key');
    expect(uri.queryParameters['sid'], 'ab');
    expect(uri.queryParameters['fp'], 'chrome');
  });

  test('case and spelling aliases match the core without overriding explicit SNI', () async {
    final PreparedLinks result = await LinkPreparation.prepare(<String>[
      'vless://test@proxy.example:443?security=tls&TYPE=ws&SNI=cdn.example&HOST=edge.example&mux-type=smux&amp;mux_up=10',
    ], lookup: lookup);
    final Uri uri = Uri.parse(result.links.single);
    expect(uri.queryParameters['SNI'], 'cdn.example');
    expect(uri.queryParameters.containsKey('sni'), false);
    expect(uri.queryParameters['HOST'], 'edge.example');
    expect(uri.queryParameters.containsKey('host'), false);
    expect(uri.queryParameters.containsKey('mux-type'), false);
    expect(uri.queryParameters.containsKey('mux_up'), false);
  });

  test('vmess retains fields, explicit Host and implicit SNI', () async {
    final Map<String, dynamic> source = <String, dynamic>{
      'v': '2', 'add': 'proxy.example', 'port': 443, 'id': 'test', 'aid': 0,
      'tls': 'tls', 'net': 'ws', 'host': 'cdn.example', 'path': '/socket',
      'muxtype': 'smux', 'muxup': 10, 'muxdown': 10,
    };
    final PreparedLinks result = await LinkPreparation.prepare(<String>[
      'vmess://${base64Encode(utf8.encode(jsonEncode(source)))}',
    ], lookup: lookup);
    final Map<String, dynamic> decoded = jsonDecode(utf8.decode(base64Decode(result.links.single.substring(8)))) as Map<String, dynamic>;
    expect(decoded['add'], '192.0.2.10');
    expect(decoded['sni'], 'cdn.example');
    expect(decoded['host'], 'cdn.example');
    expect(decoded['id'], source['id']);
    expect(decoded['port'], source['port']);
    expect(decoded['path'], source['path']);
    expect(decoded.containsKey('muxtype'), false);
    expect(source['add'], 'proxy.example'); // Never change persisted profile.
  });

  test('timeout, filtering response and malformed links fall back without inventing an IP', () async {
    const String link = 'vless://test@proxy.example:443?type=tcp&security=tls';
    for (final Future<List<InternetAddress>> Function(String) resolver in <Future<List<InternetAddress>> Function(String)>[
      (_) => throw const SocketException('unreachable'),
      (_) async => <InternetAddress>[InternetAddress('10.10.34.34')],
      (_) => Completer<List<InternetAddress>>().future,
    ]) {
      final PreparedLinks result = await LinkPreparation.prepare(<String>[link, 'vmess://bad-data'],
          lookup: resolver, budget: const Duration(milliseconds: 20));
      expect(Uri.parse(result.links.first).host, 'proxy.example');
      expect(result.links.last, 'vmess://bad-data');
      expect(result.unresolvedHosts, 1);
    }
  });

  test('unblocker chain can retain remote resolution; no DNS for unsupported links', () async {
    final PreparedLinks result = await LinkPreparation.prepare(<String>[
      'vless://test@proxy.example:443?type=tcp&muxtype=smux', 'ss://opaque',
    ], resolveEndpoints: false, lookup: (_) => throw StateError('must not resolve'));
    expect(Uri.parse(result.links.first).host, 'proxy.example');
    expect(result.links.first, isNot(contains('muxtype')));
    expect(result.links.last, 'ss://opaque');
  });

  test('IPv6 endpoints keep valid URI syntax and empty SNI falls back to original name', () async {
    final PreparedLinks result = await LinkPreparation.prepare(<String>[
      'trojan://secret@proxy.example:443?type=ws&sni=&host=',
    ], lookup: (_) async => <InternetAddress>[InternetAddress('2001:db8::1')]);
    final Uri uri = Uri.parse(result.links.single);
    expect(uri.host, '2001:db8::1');
    expect(uri.queryParameters['sni'], 'proxy.example');
    expect(uri.queryParameters['host'], 'proxy.example');
    expect(uri.queryParameters.containsKey('allowInsecure'), false);
  });

  test('bootstrap concurrency is bounded and late lookups cannot change a result', () async {
    int active = 0;
    int maximum = 0;
    final PreparedLinks result = await LinkPreparation.prepare(<String>[
      for (int i = 0; i < 20; i++) 'vless://test@node$i.example:443?security=tls',
    ], lookup: (_) async {
      active++;
      if (active > maximum) maximum = active;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      active--;
      return lookup('ignored');
    });
    expect(maximum, lessThanOrEqualTo(4));
    expect(result.resolvedHosts, 20);
  });

  test('console defaults off, migrates legacy default-on, and retains new explicit choices', () {
    expect(const AppSettings().showCli, false);
    expect(AppSettings.fromJson(<String, dynamic>{'showCli': true}).showCli, false);
    expect(AppSettings.fromJson(const AppSettings(showCli: true).toJson()).showCli, true);
    expect(AppSettings.fromJson(const AppSettings(showCli: false).toJson()).showCli, false);
  });
}
