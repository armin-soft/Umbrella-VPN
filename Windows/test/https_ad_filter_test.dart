import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/vpn/https_ad_filter_proxy.dart';
import 'package:umbrella_vpn/vpn/local_ca.dart';
import 'package:umbrella_vpn/vpn/runtime_config.dart';
import 'package:umbrella_vpn/vpn/umbrella_core.dart';

class _MockSocks5Relay {
  _MockSocks5Relay({
    required this.expectedUser,
    required this.expectedPass,
    required this.hostPorts,
  });

  final String expectedUser;
  final String expectedPass;
  final Map<String, int> hostPorts;

  ServerSocket? _server;
  final List<String> connectedTargets = <String>[];
  bool sawAuthSuccess = false;

  int get port => _server?.port ?? 0;

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((Socket client) => unawaited(_handle(client)));
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  Future<void> _handle(Socket client) async {
    final StreamIterator<Uint8List> it = StreamIterator<Uint8List>(client);
    final List<int> buf = <int>[];

    Future<Uint8List> readN(int n) async {
      while (buf.length < n) {
        if (!await it.moveNext()) break;
        buf.addAll(it.current);
      }
      final int take = n <= buf.length ? n : buf.length;
      final Uint8List out = Uint8List.fromList(buf.sublist(0, take));
      buf.removeRange(0, take);
      return out;
    }

    Socket? upstream;
    try {
      final Uint8List head = await readN(2);
      if (head.length < 2 || head[0] != 0x05) {
        client.destroy();
        return;
      }
      final Uint8List methods = await readN(head[1]);
      if (!methods.contains(0x02)) {
        client.add(const <int>[0x05, 0xff]);
        client.destroy();
        return;
      }
      client.add(const <int>[0x05, 0x02]);

      final Uint8List authVer = await readN(2);
      final Uint8List u = await readN(authVer[1]);
      final Uint8List pLen = await readN(1);
      final Uint8List p = await readN(pLen[0]);
      final String user = utf8.decode(u);
      final String pass = utf8.decode(p);
      if (user != expectedUser || pass != expectedPass) {
        client.add(const <int>[0x01, 0x01]);
        client.destroy();
        return;
      }
      sawAuthSuccess = true;
      client.add(const <int>[0x01, 0x00]);

      final Uint8List req = await readN(4);
      final int atyp = req[3];
      String host = '';
      if (atyp == 0x03) {
        final Uint8List len = await readN(1);
        host = utf8.decode(await readN(len[0]));
      } else if (atyp == 0x01) {
        host = (await readN(4)).join('.');
      }
      final Uint8List portBytes = await readN(2);
      final int dstPort = (portBytes[0] << 8) | portBytes[1];
      connectedTargets.add('$host:$dstPort');

      final int? targetPort = hostPorts[host.toLowerCase()];
      if (targetPort == null) {
        client.add(const <int>[0x05, 0x04, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
        client.destroy();
        return;
      }

      upstream = await Socket.connect(InternetAddress.loopbackIPv4, targetPort);
      client.add(const <int>[0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
      if (buf.isNotEmpty) {
        upstream.add(Uint8List.fromList(buf));
        buf.clear();
      }
      upstream.listen(
        (Uint8List d) {
          try {
            client.add(d);
          } catch (_) {
            upstream?.destroy();
          }
        },
        onError: (_) => client.destroy(),
        onDone: () => client.destroy(),
      );
      while (await it.moveNext()) {
        upstream.add(it.current);
      }
    } catch (_) {
    } finally {
      await it.cancel();
      upstream?.destroy();
      client.destroy();
    }
  }
}

void main() {
  group('Option 1 & 2 - AdBlock Domains, Local CA & HTTPS Deep Filter', () {
    test('Option 1 includes PersianBlocker, Brave, and uAssets ad/tracker suffixes', () {
      final List<Map<String, dynamic>> adsRules =
          UmbrellaCore.contentControlRules(
        const FilterSettings(enabled: true, categories: <String>['ads']),
        includeRemoteRuleSets: false,
      );
      final List<String> ads = <String>[
        for (final Map<String, dynamic> r in adsRules)
          if (r['domain_suffix'] is List<dynamic>)
            ...(r['domain_suffix'] as List<dynamic>).cast<String>(),
      ];
      expect(ads, contains('hadeseh.simra.cloud'));
      expect(ads, contains('dsp.aparat.com'));
      expect(ads, contains('adengine.telewebion.ir'));
      expect(ads, contains('analytics.zoomit.ir'));
      expect(ads, contains('pagead.l.doubleclick.net'));
      expect(ads, contains('youtube.cleverads.vn'));
    });

    test('LocalCaManager generates persistent P-256 CA and valid 395-day leaf certs', () async {
      final Directory tmp =
          await Directory.systemTemp.createTemp('umbrella_ca_win_');
      addTearDown(() async {
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      });

      final LocalCaManager ca1 = LocalCaManager(storageDir: tmp.path);
      await ca1.ensureInitialized();
      expect(ca1.isInitialized, isTrue);
      expect(ca1.caCertPem, contains('-----BEGIN CERTIFICATE-----'));
      expect(ca1.caSha1Hex.length, 40);
      expect(ca1.caSha256Hex.length, 64);

      final LocalCaManager ca2 = LocalCaManager(storageDir: tmp.path);
      await ca2.ensureInitialized();
      expect(ca2.caSha256Hex, ca1.caSha256Hex);
      expect(ca2.caSha1Hex, ca1.caSha1Hex);

      final ({String leafCertPem, String chainPem, String keyPem}) leaf =
          await ca1.issueLeafPemForHost('www.youtube.com');
      expect(leaf.leafCertPem, contains('-----BEGIN CERTIFICATE-----'));
      expect(leaf.chainPem, contains(ca1.caCertPem.trim()));
      expect(leaf.keyPem, contains('-----BEGIN PRIVATE KEY-----'));

      final SecurityContext ctx1 =
          await ca1.securityContextForHost('www.youtube.com');
      final SecurityContext ctx2 =
          await ca1.securityContextForHost('www.youtube.com');
      expect(identical(ctx1, ctx2), isTrue);

      final SecurityContext ipCtx =
          await ca1.securityContextForHost('192.168.1.50');
      expect(ipCtx, isNotNull);
    });

    test('YouTubeJsonPruner strips ad keys and ad cards while keeping video details', () {
      final String input = jsonEncode(<String, dynamic>{
        'videoDetails': <String, dynamic>{
          'videoId': 'dQw4w9WgXcQ',
          'title': 'Real Video',
        },
        'adPlacements': <dynamic>[<String, dynamic>{'id': 'pre-roll'}],
        'playerAds': <dynamic>[<String, dynamic>{'id': 'overlay'}],
        'adSlots': <dynamic>[<String, dynamic>{'id': 'slot1'}],
        'contents': <dynamic>[
          <String, dynamic>{
            'richItemRenderer': <String, dynamic>{
              'content': <String, dynamic>{
                'adSlotRenderer': <String, dynamic>{'ad': true},
              },
            },
          },
          <String, dynamic>{
            'richItemRenderer': <String, dynamic>{
              'content': <String, dynamic>{
                'videoRenderer': <String, dynamic>{'videoId': 'keep-me'},
              },
            },
          },
        ],
      });

      final String? pruned = YouTubeJsonPruner.pruneJsonString(input);
      expect(pruned, isNotNull);
      final Map<String, dynamic> decoded =
          jsonDecode(pruned!) as Map<String, dynamic>;
      expect(decoded.containsKey('adPlacements'), isFalse);
      expect(decoded.containsKey('playerAds'), isFalse);
      expect(decoded.containsKey('adSlots'), isFalse);
      expect(decoded['videoDetails']['title'], 'Real Video');
      expect((decoded['contents'] as List<dynamic>).length, 1);
      expect(
        decoded['contents'][0]['richItemRenderer']['content']['videoRenderer']
            ['videoId'],
        'keep-me',
      );
      expect(YouTubeJsonPruner.pruneJsonString('{"ok":true}'), isNull);
    });

    test('HtmlAdFilterEngine guards non-HTML, rewrites YouTube HTML & syncs CSP nonce', () {
      final ({String html, String? nonceToAllow}) plainRes =
          HtmlAdFilterEngine.filterHtml(
        host: 'varzesh3.com',
        rawHtml: '{"just":"json"}',
      );
      expect(plainRes.nonceToAllow, isNull);
      expect(plainRes.html, '{"just":"json"}');

      const String rawYtHtml = '''<!doctype html>
<html>
<head><title>YouTube</title></head>
<body>
<script>var ytInitialPlayerResponse = {"videoDetails":{"title":"Test</script>"},"adPlacements":[{"ad":1}]};</script>
</body>
</html>''';
      final ({String html, String? nonceToAllow}) ytRes =
          HtmlAdFilterEngine.filterHtml(
        host: 'www.youtube.com',
        rawHtml: rawYtHtml,
        existingCsp:
            "default-src 'self'; script-src-elem 'nonce-ytNonce42'; style-src 'self'",
      );
      expect(ytRes.nonceToAllow, 'ytNonce42');
      expect(ytRes.html, contains('id="umbrella-cosmetic-filter" nonce="ytNonce42"'));
      expect(ytRes.html, contains('id="umbrella-yt-scriptlet" nonce="ytNonce42"'));
      expect(ytRes.html, isNot(contains('"adPlacements"')));
      expect(ytRes.html, contains(r'Test<\/script>'));

      final String? patchedCsp = HtmlAdFilterEngine.patchCspHeader(
        "default-src 'self'; script-src-elem 'nonce-ytNonce42'; style-src 'self'",
        'newNonce99',
      );
      expect(patchedCsp, contains("script-src-elem 'nonce-ytNonce42' 'nonce-newNonce99'"));
      expect(patchedCsp, contains("style-src 'self' 'nonce-newNonce99'"));
    });

    test('HtmlAdFilterEngine path matcher blocks ad scripts and stats endpoints', () {
      final blockedYt = HtmlAdFilterEngine.matchBlockedPath(
        'www.youtube.com',
        '/api/stats/ads?ns=yt',
      );
      expect(blockedYt?.statusCode, 204);

      final blockedYektanet = HtmlAdFilterEngine.matchBlockedPath(
        'www.varzesh3.com',
        '/assets/yektanet.js?v=1',
      );
      expect(blockedYektanet?.statusCode, 200);
      expect(blockedYektanet?.contentType, contains('javascript'));
    });

    test('AppSettings defaults httpsAdFilter to false and smart mode safely', () {
      const AppSettings defaults = AppSettings();
      expect(defaults.httpsAdFilter, isFalse);
      expect(defaults.httpsAdFilterMode, 'smart');

      final AppSettings restored = AppSettings.fromJson(<String, dynamic>{
        'httpsAdFilter': true,
        'httpsAdFilterMode': 'BROAD',
      });
      expect(restored.httpsAdFilter, isTrue);
      expect(restored.httpsAdFilterMode, 'broad');

      final AppSettings sanitized = AppSettings.fromJson(<String, dynamic>{
        'httpsAdFilterMode': 'unknown-value',
      });
      expect(sanitized.httpsAdFilter, isFalse);
      expect(sanitized.httpsAdFilterMode, 'smart');
    });

    test('RuntimeConfig wires anti-loop HTTPS filter routing and QUIC reject', () {
      final Map<String, dynamic> config = <String, dynamic>{
        'inbounds': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'tun', 'tag': 'tun-in'},
          <String, dynamic>{'type': 'mixed', 'tag': 'mixed-in', 'listen_port': 12334},
        ],
        'outbounds': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'selector', 'tag': 'select'},
          <String, dynamic>{'type': 'direct', 'tag': 'direct §hide§'},
          <String, dynamic>{'type': 'block', 'tag': 'block'},
        ],
        'route': <String, dynamic>{
          'rules': <Map<String, dynamic>>[
            <String, dynamic>{'action': 'sniff'},
            <String, dynamic>{
              'domain_suffix': <String>['doubleclick.net'],
              'action': 'reject',
            },
            <String, dynamic>{
              'rule_set': <String>['geosite-ir'],
              'outbound': 'direct §hide§',
            },
          ],
        },
      };

      RuntimeConfig.finalize(
        config,
        profileTags: const <String>{},
        httpsFilterPort: 41001,
        httpsFilterEgressPort: 41002,
        httpsFilterSecret: 'secret123',
        httpsFilterBroadMode: true,
      );

      final List<dynamic> inbounds = config['inbounds'] as List<dynamic>;
      expect(
        inbounds.any(
          (dynamic i) =>
              i is Map &&
              i['tag'] == RuntimeConfig.httpsFilterEgressInboundTag &&
              i['listen_port'] == 41002 &&
              i['type'] == 'socks',
        ),
        isTrue,
      );

      final List<dynamic> outbounds = config['outbounds'] as List<dynamic>;
      expect(
        outbounds.any(
          (dynamic o) =>
              o is Map &&
              o['tag'] == RuntimeConfig.httpsFilterOutboundTag &&
              o['server_port'] == 41001 &&
              o['type'] == 'http',
        ),
        isTrue,
      );

      final List<dynamic> rules =
          (config['route'] as Map<String, dynamic>)['rules'] as List<dynamic>;
      final int adsRejectIdx = rules.indexWhere(
        (dynamic r) =>
            r is Map &&
            r['action'] == 'reject' &&
            '${r['domain_suffix']}'.contains('doubleclick.net'),
      );
      final int httpsRouteIdx = rules.indexWhere(
        (dynamic r) =>
            r is Map && r['outbound'] == RuntimeConfig.httpsFilterOutboundTag,
      );
      final int iranDirectIdx = rules.indexWhere(
        (dynamic r) => r is Map && r['outbound'] == 'direct §hide§',
      );
      expect(adsRejectIdx, greaterThanOrEqualTo(0));
      expect(httpsRouteIdx, greaterThan(adsRejectIdx));
      expect(iranDirectIdx, greaterThan(httpsRouteIdx));

      // تایید ضد-حلقه: ورودی umbrella-egress-in هرگز در قوانین فیلتر نیست
      final Map<String, dynamic> broadRouteRule =
          rules[httpsRouteIdx] as Map<String, dynamic>;
      expect(broadRouteRule['type'], 'logical');
      final List<dynamic> subRules = broadRouteRule['rules'] as List<dynamic>;
      final List<dynamic> inboundList = subRules[0]['inbound'] as List<dynamic>;
      expect(inboundList, containsAll(<String>['tun-in', 'mixed-in']));
      expect(inboundList, isNot(contains(RuntimeConfig.httpsFilterEgressInboundTag)));
      final Map<String, dynamic> invertSub = subRules.last as Map<String, dynamic>;
      expect(invertSub['invert'], isTrue);
      expect(invertSub['domain_suffix'], contains('shaparak.ir'));
      expect(invertSub['domain_suffix'], contains('googlevideo.com'));
    });

    test('HttpsAdFilterProxy end-to-end MITM, gzip JSON prune, path block, and pass-through', () async {
      final Directory tmp =
          await Directory.systemTemp.createTemp('umbrella_proxy_win_e2e_');
      addTearDown(() async {
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      });

      final LocalCaManager ca = LocalCaManager(storageDir: tmp.path);
      await ca.ensureInitialized();

      final ({String leafCertPem, String chainPem, String keyPem}) ytCert =
          await ca.issueLeafPemForHost('www.youtube.com');
      final SecurityContext ytCtx = SecurityContext(withTrustedRoots: false)
        ..useCertificateChainBytes(utf8.encode(ytCert.chainPem))
        ..usePrivateKeyBytes(utf8.encode(ytCert.keyPem));
      final HttpServer ytUpstream = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        ytCtx,
      );
      addTearDown(() => ytUpstream.close(force: true));

      ytUpstream.listen((HttpRequest req) async {
        if (req.uri.path == '/watch') {
          req.response
            ..statusCode = HttpStatus.ok
            ..headers.set(
              HttpHeaders.contentTypeHeader,
              'text/html; charset=utf-8',
            )
            ..headers.set(
              'Content-Security-Policy',
              "default-src 'self'; script-src-elem 'nonce-abc123'",
            )
            ..write(
              '<html><head></head><body><script>var ytInitialPlayerResponse = {"videoDetails":{"title":"Clean"},"adPlacements":[{"id":"ad1"}]};</script></body></html>',
            );
          await req.response.close();
          return;
        }
        if (req.uri.path == '/youtubei/v1/player') {
          final List<int> gz = gzip.encode(utf8.encode(jsonEncode(<String, dynamic>{
            'playerAds': <dynamic>[<String, dynamic>{'x': 1}],
            'videoDetails': <String, dynamic>{'videoId': 'vid42'},
          })));
          req.response
            ..statusCode = HttpStatus.ok
            ..headers.set(HttpHeaders.contentTypeHeader, 'application/json')
            ..headers.set(HttpHeaders.contentEncodingHeader, 'gzip')
            ..add(gz);
          await req.response.close();
          return;
        }
        req.response
          ..statusCode = HttpStatus.ok
          ..write('unexpected');
        await req.response.close();
      });

      final ({String leafCertPem, String chainPem, String keyPem}) bankCert =
          await ca.issueLeafPemForHost('shaparak.ir');
      final SecurityContext bankCtx = SecurityContext(withTrustedRoots: false)
        ..useCertificateChainBytes(utf8.encode(bankCert.chainPem))
        ..usePrivateKeyBytes(utf8.encode(bankCert.keyPem));
      final HttpServer bankUpstream = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        bankCtx,
      );
      addTearDown(() => bankUpstream.close(force: true));

      bankUpstream.listen((HttpRequest req) async {
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.set(HttpHeaders.contentTypeHeader, 'text/plain')
          ..write('bank-passthrough-ok');
        await req.response.close();
      });

      final _MockSocks5Relay socksRelay = _MockSocks5Relay(
        expectedUser: 'umbrella',
        expectedPass: 'e2eSecret',
        hostPorts: <String, int>{
          'www.youtube.com': ytUpstream.port,
          'shaparak.ir': bankUpstream.port,
        },
      );
      await socksRelay.start();
      addTearDown(socksRelay.stop);

      final SecurityContext clientAndUpstreamTrust =
          SecurityContext(withTrustedRoots: false)
            ..setTrustedCertificatesBytes(utf8.encode(ca.caCertPem));

      final HttpsAdFilterProxy proxy = HttpsAdFilterProxy(
        caManager: ca,
        broadMode: true,
        egressPort: socksRelay.port,
        egressUsername: 'umbrella',
        egressSecret: 'e2eSecret',
        upstreamSecurityContext: clientAndUpstreamTrust,
      );
      await proxy.start();
      addTearDown(proxy.stop);

      final HttpClient client = HttpClient(context: clientAndUpstreamTrust)
        ..findProxy = (_) => 'PROXY 127.0.0.1:${proxy.proxyPort}';
      addTearDown(() => client.close(force: true));

      final HttpClientRequest watchReq =
          await client.getUrl(Uri.parse('https://www.youtube.com/watch?v=1'));
      final HttpClientResponse watchRes = await watchReq.close();
      final String watchBody = await utf8.decoder.bind(watchRes).join();
      expect(watchRes.statusCode, 200);
      expect(watchBody, contains('umbrella-yt-scriptlet'));
      expect(watchBody, isNot(contains('"adPlacements"')));
      expect(
        watchRes.headers.value('content-security-policy'),
        contains("'nonce-abc123'"),
      );

      final HttpClientRequest playerReq = await client.getUrl(
        Uri.parse('https://www.youtube.com/youtubei/v1/player'),
      );
      final HttpClientResponse playerRes = await playerReq.close();
      final String playerBody = await utf8.decoder.bind(playerRes).join();
      expect(playerRes.statusCode, 200);
      expect(playerBody, isNot(contains('playerAds')));
      expect(playerBody, contains('vid42'));

      final HttpClientRequest adReq = await client.getUrl(
        Uri.parse('https://www.youtube.com/pagead/viewthroughconversion/123'),
      );
      final HttpClientResponse adRes = await adReq.close();
      expect(adRes.statusCode, 204);

      final HttpClientRequest bankReq =
          await client.getUrl(Uri.parse('https://shaparak.ir/pay'));
      final HttpClientResponse bankRes = await bankReq.close();
      final String bankBody = await utf8.decoder.bind(bankRes).join();
      expect(bankRes.statusCode, 200);
      expect(bankBody, 'bank-passthrough-ok');

      expect(socksRelay.sawAuthSuccess, isTrue);
      expect(
        socksRelay.connectedTargets,
        containsAll(<String>['www.youtube.com:443', 'shaparak.ir:443']),
      );
      expect(proxy.stats.interceptedConnections, greaterThanOrEqualTo(1));
      expect(proxy.stats.bypassedConnections, greaterThanOrEqualTo(1));
      expect(proxy.stats.blockedRequests, 1);
      expect(proxy.stats.prunedJsonResponses, 1);
      expect(proxy.stats.injectedHtmlPages, 1);
    });
  });
}
