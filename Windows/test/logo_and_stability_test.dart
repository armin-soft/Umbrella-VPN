import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:umbrella_vpn/core/app_config.dart';
import 'package:umbrella_vpn/core/theme.dart';
import 'package:umbrella_vpn/data/parsers.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/platform/services.dart';
import 'package:umbrella_vpn/state/subscription_controller.dart';
import 'package:umbrella_vpn/ui/shell/app_shell.dart';
import 'package:umbrella_vpn/ui/widgets/common.dart';
import 'package:umbrella_vpn/vpn/clash_api.dart';
import 'package:umbrella_vpn/vpn/link_preparation.dart';
import 'package:umbrella_vpn/vpn/runtime_config.dart';
import 'package:umbrella_vpn/vpn/umbrella_core.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

void main() {
  test('unfocused visible Windows window keeps UI tickers and status art alive', () {
    expect(AppShell.isLifecycleVisible(null), isTrue);
    expect(AppShell.isLifecycleVisible(AppLifecycleState.resumed), isTrue);
    expect(AppShell.isLifecycleVisible(AppLifecycleState.inactive), isTrue);
    expect(AppShell.isLifecycleVisible(AppLifecycleState.hidden), isFalse);
    expect(AppShell.isLifecycleVisible(AppLifecycleState.paused), isFalse);
    expect(AppShell.isLifecycleVisible(AppLifecycleState.detached), isFalse);
  });

  testWidgets('every brand and status PNG decodes and transitions without blanking',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      for (final String asset in <String>[
        BrandAssets.logo,
        BrandAssets.iconRound,
        ...BrandAssets.all,
      ]) {
        final ByteData bytes = await rootBundle.load(asset);
        expect(bytes.lengthInBytes, greaterThan(1024), reason: asset);
        final ui.Codec codec =
            await ui.instantiateImageCodec(bytes.buffer.asUint8List());
        final ui.FrameInfo frame = await codec.getNextFrame();
        expect(frame.image.width, greaterThanOrEqualTo(256), reason: asset);
        expect(frame.image.height, greaterThanOrEqualTo(256), reason: asset);
        frame.image.dispose();
        codec.dispose();
      }
    });

    for (final VpnStatus status in VpnStatus.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            // Even when parent TickerMode is disabled (e.g. tray transition),
            // StatusOrb keeps its image TickerMode enabled and gapless.
            body: TickerMode(
              enabled: false,
              child: Center(
                child: StatusOrb(
                  image: status.image,
                  color: const Color(0xFF0A84FF),
                  size: 240,
                  active: status.busy,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final Image image = tester.widget<Image>(find.byType(Image).first);
      expect(image.gaplessPlayback, isTrue, reason: status.name);
      expect(find.byIcon(Icons.shield_outlined), findsNothing, reason: status.name);
    }
  });

  test('subscription deduplication collapses overlapping formats without losing distinct clients', () {
    const String uuid1 = '11111111-2222-3333-4444-555555555555';
    const String uuid2 = '99999999-2222-3333-4444-555555555555';
    const String share =
        'vless://$uuid1@de1.example.com:443?security=tls&sni=de1.example.com&type=ws&path=%2Fws&host=de1.example.com#DE-1';
    const String secondClient =
        'vless://$uuid2@de1.example.com:443?security=tls&sni=de1.example.com&type=ws&path=%2Fws&host=de1.example.com#DE-2';
    const String clash = '''
proxies:
  - name: DE-1
    type: vless
    server: de1.example.com
    port: 443
    uuid: $uuid1
    tls: true
    servername: de1.example.com
    network: ws
    ws-opts:
      path: /ws
      headers:
        Host: de1.example.com
''';
    const String singbox = '''
{
  "outbounds": [
    {"type": "vless", "tag": "DE-1", "server": "de1.example.com", "server_port": 443,
     "uuid": "$uuid1", "tls": {"enabled": true, "server_name": "de1.example.com"},
     "transport": {"type": "ws", "path": "/ws", "headers": {"Host": "de1.example.com"}}}
  ]
}
''';

    final List<VpnNode> combined = <VpnNode>[
      ...SubscriptionParser.parseAuto(clash, 'user-clash-meta-all.yml').nodes,
      ...SubscriptionParser.parseAuto(share, 'user-all.txt').nodes,
      ...SubscriptionParser.parseAuto(
        base64Encode(utf8.encode(share)),
        'user-sub64-',
      ).nodes,
      ...SubscriptionParser.parseSingBox(singbox, 'user-full-singbox.json').nodes,
      ...SubscriptionParser.parseAuto(secondClient, 'user-all.txt').nodes,
    ];
    expect(combined.length, 5);

    final List<VpnNode> unique = SubscriptionController.deduplicateNodes(combined);
    expect(unique.length, 2);
    // Native share link wins over lossy Clash reconstruction even when Clash came first,
    // and preserves `#fragment` so the core names each outbound accurately.
    expect(unique.first.sourceId, 'user-all.txt');
    expect(unique.first.raw, share);
    expect(unique.last.raw, secondClient);
  });

  test('ClashApi parses session delays, ignores stale cache, and serves loopback checks', () async {
    final DateTime sessionStart = DateTime.utc(2026, 11, 17, 12, 0, 0);
    final String staleTime = DateTime.utc(2026, 11, 17, 11, 0, 0).toIso8601String();
    final String freshTime = DateTime.utc(2026, 11, 17, 12, 0, 3).toIso8601String();

    final CoreProxySnapshot staleOnly = ClashApi.parseProxies(
      <String, dynamic>{
        'proxies': <String, dynamic>{
          'select': <String, dynamic>{
            'type': 'Selector',
            'now': 'lowest',
            'all': <String>['lowest', 'p1', 'p2'],
          },
          'lowest': <String, dynamic>{
            'type': 'Balancer',
            'now': 'p1',
            'all': <String>['p1', 'p2'],
          },
          'p1': <String, dynamic>{
            'type': 'VLESS',
            'history': <Map<String, dynamic>>[
              <String, dynamic>{'time': staleTime, 'delay': 65535},
            ],
          },
          'p2': <String, dynamic>{
            'type': 'VLESS',
            'history': <Map<String, dynamic>>[
              <String, dynamic>{'time': staleTime, 'delay': 120},
            ],
          },
        },
      },
      since: sessionStart,
    );
    expect(staleOnly.hasLiveSelection, isFalse);
    expect(staleOnly.allTestedAndDead, isFalse);
    expect(staleOnly.connectivity, CoreConnectivityState.waiting);
    expect(staleOnly.untestedCount, 2);

    // Direct fresh leaf response (even before `lowest` settles or when ipinfo
    // is still pending / cached) transitions connectivity to STARTED immediately,
    // matching `hcore/connectivity.go`.
    final CoreProxySnapshot fastLeaf = ClashApi.parseProxies(
      <String, dynamic>{
        'proxies': <String, dynamic>{
          'select': <String, dynamic>{
            'type': 'Selector',
            'now': 'lowest',
            'all': <String>['lowest', 'p1', 'p2'],
          },
          'lowest': <String, dynamic>{
            'type': 'Balancer',
            'now': 'p2',
            'all': <String>['p1', 'p2'],
          },
          'p1': <String, dynamic>{
            'type': 'VLESS',
            'history': <Map<String, dynamic>>[
              <String, dynamic>{
                'time': freshTime,
                'delay': 112,
                'from_cache': true,
              },
            ],
          },
          'p2': <String, dynamic>{
            'type': 'Hysteria2',
            'history': <Map<String, dynamic>>[
              <String, dynamic>{
                'time': freshTime,
                'delay': 94,
                'ipinfo': <String, dynamic>{
                  'ip': '104.234.135.175',
                  'country_code': 'CA',
                  'region': 'Ontario',
                  'city': 'Toronto',
                  'org': 'Example Net',
                  'asn': 64500,
                },
                'ipinfo_from_cache': false,
              },
            ],
          },
          '🔒 Extra Security §hide§': <String, dynamic>{
            'type': 'WireGuard',
            'history': <Object>[],
          },
        },
      },
      since: sessionStart,
    );
    expect(fastLeaf.connectivity, CoreConnectivityState.started);
    expect(fastLeaf.activeDelayMs, 94);
    expect(fastLeaf.exitIpInfo?.ip, '104.234.135.175');
    expect(fastLeaf.exitIpInfo?.countryCode, 'CA');
    expect(GeoInfo.fromJson(fastLeaf.exitIpInfo!.toGeoJson()).countryLabel, 'کانادا');
    // Cached or IR ipinfo must never be surfaced as a live exit IP.
    final CoreProxySnapshot cachedIp = ClashApi.parseProxies(
      <String, dynamic>{
        'proxies': <String, dynamic>{
          'p1': <String, dynamic>{
            'type': 'VLESS',
            'history': <Map<String, dynamic>>[
              <String, dynamic>{
                'time': freshTime,
                'delay': 120,
                'ipinfo': <String, dynamic>{'ip': '1.2.3.4', 'country_code': 'DE'},
                'ipinfo_from_cache': true,
              },
            ],
          },
        },
      },
      since: sessionStart,
    );
    expect(cachedIp.connectivity, CoreConnectivityState.started);
    expect(cachedIp.exitIpInfo, isNull);

    final CoreProxySnapshot allDead = ClashApi.parseProxies(
      <String, dynamic>{
        'proxies': <String, dynamic>{
          'select': <String, dynamic>{
            'type': 'Selector',
            'now': 'lowest',
            'all': <String>['lowest', 'p1', 'p2'],
          },
          'lowest': <String, dynamic>{
            'type': 'Balancer',
            'now': 'p1',
            'all': <String>['p1', 'p2'],
          },
          'p1': <String, dynamic>{
            'type': 'VLESS',
            'history': <Map<String, dynamic>>[
              <String, dynamic>{'time': freshTime, 'delay': 65535},
            ],
          },
          'p2': <String, dynamic>{
            'type': 'VLESS',
            'history': <Map<String, dynamic>>[
              <String, dynamic>{'time': freshTime, 'delay': 0},
            ],
          },
        },
      },
      since: sessionStart,
    );
    expect(allDead.allTestedAndDead, isTrue);
    expect(allDead.connectivity, CoreConnectivityState.noAvailableProxies);

    final HttpServer server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((HttpRequest req) async {
      if (req.headers.value(HttpHeaders.authorizationHeader) != 'Bearer test-secret') {
        req.response.statusCode = 401;
        await req.response.close();
        return;
      }
      if (req.uri.path == '/proxies') {
        req.response.write(jsonEncode(<String, dynamic>{
          'proxies': <String, dynamic>{
            'select': <String, dynamic>{
              'type': 'Selector',
              'now': 'lowest',
              'all': <String>['lowest', 'vless-fast', 'vless-dead'],
            },
            'lowest': <String, dynamic>{
              'type': 'Balancer',
              'now': 'vless-fast',
              'all': <String>['vless-fast', 'vless-dead'],
            },
            'vless-fast': <String, dynamic>{
              'type': 'VLESS',
              'history': <Map<String, dynamic>>[
                <String, dynamic>{'time': freshTime, 'delay': 138},
              ],
            },
            'vless-dead': <String, dynamic>{
              'type': 'VLESS',
              'history': <Map<String, dynamic>>[
                <String, dynamic>{'time': freshTime, 'delay': 65535},
              ],
            },
          },
        }));
      } else if (req.uri.path == '/proxies/vless-fast/delay') {
        req.response.write(jsonEncode(<String, dynamic>{'delay': 142}));
      } else if (req.uri.path == '/connections') {
        req.response.write(jsonEncode(<String, dynamic>{
          'downloadTotal': 20480,
          'uploadTotal': 4096,
          'connections': <Object>[<String, dynamic>{}],
        }));
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });

    final HttpOverrides? previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() {
      HttpOverrides.global = previousOverrides;
    });
    final CoreProxySnapshot live = await ClashApi.status(
      port: server.port,
      secret: 'test-secret',
      since: sessionStart,
    );
    expect(live.reachable, isTrue);
    expect(live.hasLiveSelection, isTrue);
    expect(live.activeTag, 'vless-fast');
    expect(live.activeDelayMs, 138);
    expect(live.aliveCount, 1);
    expect(live.failedCount, 1);
    expect(live.allTestedAndDead, isFalse);

    final int delay = await ClashApi.testDelay(
      'vless-fast',
      port: server.port,
      secret: 'test-secret',
    );
    expect(delay, 142);

    final CoreTrafficTotals? traffic = await ClashApi.trafficTotals(
      port: server.port,
      secret: 'test-secret',
    );
    expect(traffic?.rxBytes, 20480);
    expect(traffic?.txBytes, 4096);
    expect(traffic?.activeConnections, 1);
  });

  test('selection modes, DNS cache isolation, and pinger Clash isolation are wired', () {
    final Map<String, dynamic> auto = UmbrellaCore.settingsJson(
      tun: true,
      systemProxy: false,
      port: 12334,
      networkSettings: const AppSettings(selectionMode: SelectionMode.auto),
    );
    expect(auto['default-proxy'], 'lowest');
    expect(auto.containsKey('balancer-strategy'), isFalse);
    expect(auto['independent-dns-cache'], isFalse);
    expect(auto['url-test-interval'], 600);
    expect(auto['keep-top'], -1);
    expect(auto['ipinfo-url'], '');
    expect(auto['remote-dns-address'], 'tcp://8.8.8.8');
    expect(auto['direct-dns-address'], '1.1.1.1');
    expect(auto['log-level'], 'warn');

    for (final (SelectionMode mode, String strategy) in <(SelectionMode, String)>[
      (SelectionMode.roundRobin, 'round-robin'),
      (SelectionMode.consistentHash, 'consistent-hashing'),
      (SelectionMode.stickySession, 'sticky-sessions'),
    ]) {
      final Map<String, dynamic> cfg = UmbrellaCore.settingsJson(
        tun: true,
        systemProxy: false,
        port: 12334,
        networkSettings: AppSettings(selectionMode: mode),
      );
      expect(cfg['default-proxy'], 'balance');
      expect(cfg['balancer-strategy'], strategy);
    }

    // User browsing hosts must not be forced onto direct DNS via connectionTestUrls.
    for (final String url in AppConfig.connectionTestUrls) {
      final String host = Uri.parse(url).host.toLowerCase();
      expect(host, isNot('www.google.com'));
      expect(host, isNot('www.gstatic.com'));
    }

    final Map<String, dynamic> pingRuntime = <String, dynamic>{
      'log': <String, dynamic>{'output': 'box.log'},
      'experimental': <String, dynamic>{
        'clash_api': <String, dynamic>{'external_controller': '127.0.0.1:16756'},
        'monitoring': <String, dynamic>{},
      },
      'outbounds': <dynamic>[
        <String, dynamic>{'type': 'vless', 'tag': 'n1', 'server': 'example.com'},
      ],
    };
    RuntimeConfig.finalize(
      pingRuntime,
      profileTags: <String>{'n1'},
      clashApiPort: 0,
    );
    expect((pingRuntime['experimental'] as Map<String, dynamic>).containsKey('clash_api'), isFalse);
  });

  test('per-host DNS timeout keeps slow domains from starving fast endpoints', () async {
    final PreparedLinks prepared = await LinkPreparation.prepare(
      <String>[
        for (int i = 0; i < 4; i++)
          'vless://u@slow$i.example.invalid:443?security=tls&type=ws#s$i',
        'vless://u@fast.example.invalid:443?security=tls&type=ws#fast',
      ],
      budget: const Duration(milliseconds: 500),
      perHostTimeout: const Duration(milliseconds: 60),
      lookup: (String host) async {
        if (host.startsWith('slow')) {
          await Future<void>.delayed(const Duration(seconds: 5));
        }
        return <InternetAddress>[InternetAddress('198.51.100.10')];
      },
    );
    expect(prepared.resolvedHosts, 1);
    expect(Uri.parse(prepared.links.last).host, '198.51.100.10');
  });

  test('forced exit-IP lookup never returns stale pre-connect device IP on failure', () async {
    int phase = 0;
    final IpService service = IpService(
      client: MockClient((http.Request request) async {
        if (phase == 0) {
          return http.Response(
            jsonEncode(<String, dynamic>{'ip': '5.120.10.20', 'country_code': 'IR'}),
            200,
          );
        }
        // Simulate rate-limited ipwho.is (HTTP 200 with success: false) and 429s.
        if (request.url.host == 'ipwho.is') {
          return http.Response(
            jsonEncode(<String, dynamic>{'ip': '5.120.10.20', 'success': false}),
            200,
          );
        }
        return http.Response('rate limited', 429);
      }),
    );

    final GeoInfo initial = await service.fetch(force: true);
    expect(initial.ip, '5.120.10.20');

    phase = 1;
    final GeoInfo afterConnect = await service.fetch(force: true);
    expect(afterConnect.ip, isEmpty);
  });
}
