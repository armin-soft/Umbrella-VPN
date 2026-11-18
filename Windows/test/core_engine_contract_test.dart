import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/data/parsers.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/vpn/clash_api.dart';
import 'package:umbrella_vpn/vpn/umbrella_core.dart';
import 'package:umbrella_vpn/vpn/link_preparation.dart';
import 'package:umbrella_vpn/vpn/core_runtime.dart';
import 'package:umbrella_vpn/vpn/runtime_config.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

/// Exercises the actual bundled DLL through our native launcher. `build` only
/// compiles configuration: it never starts a VPN, enrolls WARP or changes routes.
/// Enabled explicitly after the native build/download stage in Windows CI.
void main() {
  final String? binary = Platform.environment['UMBRELLA_CORE_SMOKE'];
  final bool enabled = Platform.isWindows && binary != null;

  Future<Map<String, dynamic>> generate(
    ChainSettings chain, {
    bool startRuntime = false,
    SelectionMode selectionMode = SelectionMode.auto,
    int? clashApiPort,
  }) async {
    final String executable = binary!;
    final Directory temp = await Directory.systemTemp.createTemp('umbrella-core-contract-');
    Process? process;
    try {
      final File links = File('${temp.path}/links.txt');
      final File settings = File('${temp.path}/settings.json');
      final PreparedLinks prepared = await LinkPreparation.prepare(<String>[
        'vless://00000000-0000-4000-8000-000000000001@proxy.example.invalid:443?security=tls&sni=example.invalid&type=xhttp&mode=packet-up&path=%2Fupload&extra=%7B%22noGRPCHeader%22%3Atrue%7D&muxtype=h2mux&muxup=100&muxdown=100#offline-fixture',
      ], lookup: (_) async => <InternetAddress>[InternetAddress('192.0.2.1')],
        resolveEndpoints: chain.position != ChainPosition.unblocker);
      await links.writeAsString('${prepared.links.single}\n');
      final Map<String, dynamic> options = UmbrellaCore.settingsJson(
        tun: !startRuntime,
        systemProxy: false,
        port: 12334,
        logFile: '${temp.path}/core.log',
        networkSettings: AppSettings(
          chain: chain,
          mtu: 1400,
          selectionMode: selectionMode,
          appRoutes: const <AppRouteRule>[
            AppRouteRule(process: 'offline-direct.exe', action: AppRouteAction.direct),
            AppRouteRule(process: r'C:\Offline\blocked.exe', action: AppRouteAction.block),
          ],
        ),
      );
      await settings.writeAsString(jsonEncode(options));
      final File output = await CoreRuntime.compile(
        executable: executable,
        workDir: File(executable).parent.path,
        runDir: temp.path,
        linksPath: links.path,
        settingsPath: settings.path,
        clashApiPort: clashApiPort,
        cancelled: () => false,
        onStarted: (Process value) { process = value; },
        onFinished: (_) { process = null; },
      );
      if (startRuntime) {
        // Verify level-2 cache hit (even with a different log-file path) spawns
        // zero core subprocesses, enabling Hiddify-speed instant `srun`.
        int cacheHitSpawns = 0;
        final Map<String, dynamic> rotatedLogOptions =
            Map<String, dynamic>.from(options)
              ..['log-file'] = '${temp.path}/session-2.log';
        await settings.writeAsString(jsonEncode(rotatedLogOptions));
        final File cachedOutput = await CoreRuntime.compile(
          executable: executable,
          workDir: File(executable).parent.path,
          runDir: temp.path,
          linksPath: links.path,
          settingsPath: settings.path,
          clashApiPort: clashApiPort,
          cancelled: () => false,
          onStarted: (_) { cacheHitSpawns++; },
        );
        expect(cacheHitSpawns, 0, reason: 'unchanged links+settings must hit runtime cache');
        expect(cachedOutput.path, output.path);
        // Changing settings while links stay identical hits level-1 parsed cache
        // (runs only `build`, skipping `parse`).
        int partialHitSpawns = 0;
        final Map<String, dynamic> mtuChanged =
            Map<String, dynamic>.from(rotatedLogOptions)..['mtu'] = 1420;
        await settings.writeAsString(jsonEncode(mtuChanged));
        await CoreRuntime.compile(
          executable: executable,
          workDir: File(executable).parent.path,
          runDir: temp.path,
          linksPath: links.path,
          settingsPath: settings.path,
          clashApiPort: clashApiPort,
          cancelled: () => false,
          onStarted: (_) { partialHitSpawns++; },
        );
        expect(partialHitSpawns, 1, reason: 'settings-only change must reuse parsed.json');
        // Restore original 1400-MTU runtime so downstream assertions check exact output.
        await settings.writeAsString(jsonEncode(options));
        await CoreRuntime.compile(
          executable: executable,
          workDir: File(executable).parent.path,
          runDir: temp.path,
          linksPath: links.path,
          settingsPath: settings.path,
          clashApiPort: clashApiPort,
          cancelled: () => false,
        );
      }
      if (startRuntime) {
        final Process running = await Process.start(executable,
          <String>['srun', '-c', output.path, '-D', temp.path],
          workingDirectory: File(executable).parent.path, runInShell: false);
        process = running;
        final StringBuffer logs = StringBuffer();
        running.stdout.transform(utf8.decoder).listen(logs.write);
        running.stderr.transform(utf8.decoder).listen(logs.write);
        final HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
        bool ready = false;
        try {
          for (int i = 0; i < 8; i++) {
            try {
              final HttpClientRequest request = await client.getUrl(Uri.parse('http://127.0.0.1:16756/version')).timeout(const Duration(milliseconds: 700));
              request.headers.set('authorization', 'Bearer ${options['web-secret']}');
              final HttpClientResponse response = await request.close().timeout(const Duration(milliseconds: 700));
              await response.drain<void>().timeout(const Duration(milliseconds: 700));
              if (response.statusCode == 200) { ready = true; break; }
            } on Exception { /* wait for initialized core, not merely Process.start */ }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(ready, true, reason: logs.toString());
          expect(await File('${temp.path}/data/clash.db').exists(), true, reason: logs.toString());
          final CoreProxySnapshot snapshot = await ClashApi.status(
            secret: '${options['web-secret']}',
          );
          expect(snapshot.reachable, true, reason: logs.toString());
          expect(snapshot.totalCount, greaterThanOrEqualTo(1), reason: logs.toString());
          final CoreTrafficTotals? traffic = await ClashApi.trafficTotals(
            secret: '${options['web-secret']}',
          );
          expect(traffic, isNotNull, reason: logs.toString());
          final int? exit = await Future.any<int?>(<Future<int?>>[
            running.exitCode, Future<int?>.delayed(const Duration(milliseconds: 500), () => null),
          ]);
          expect(exit, isNull, reason: logs.toString());
        } finally { client.close(force: true); }
      }
      return jsonDecode(await output.readAsString()) as Map<String, dynamic>;
    } finally {
      process?.kill();
      if (process != null) await process!.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
      await temp.delete(recursive: true);
    }
  }

  test('full compiled runtime starts in a fresh directory with cache and authenticated Clash API', () async {
    await generate(const ChainSettings(), startRuntime: true);
    await generate(
      const ChainSettings(),
      startRuntime: true,
      selectionMode: SelectionMode.roundRobin,
    );
    for (final SelectionMode mode in SelectionModeList.visible) {
      await generate(
        const ChainSettings(),
        selectionMode: mode,
        clashApiPort: mode == SelectionMode.auto ? 0 : null,
      );
    }
  }, skip: enabled ? false : 'Requires bundled Windows core', timeout: const Timeout(Duration(seconds: 60)));

  test('bundled core compiles and starts all 9 /sub/ protocols together without fatal error', () async {
    const String subId = '00000000-0000-4000-8000-000000000099';
    const String ssUser =
        'MjAyMi1ibGFrZTMtYWVzLTI1Ni1nY206Ky84K0FBRUNBd1FGQmdjSUNRb0xEQTBPRHhBUkVoTVVGUllYR0JrYUd4dz06UC83N0Nnc01EUTRQRUJFU0V4UVZGaGNZR1JvYkhCMGVIeUFoSWlNa0pTWT0=';
    const String sshPk =
        '-----BEGIN%20OPENSSH%20PRIVATE%20KEY-----'
        'b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZWQyNTUxOQAAACAmSNL4l8dIef4GYSZPSsyAOWHWkRewEPH4wPmYxRDjzwAAAIg8nAPcPJwD3AAAAAtzc2gtZWQyNTUxOQAAACAmSNL4l8dIef4GYSZPSsyAOWHWkRewEPH4wPmYxRDjzwAAAEDq%2FGSaM6bh5FjaXbl259%2FcSf2PwIlmeHrDklne%2BnnlcyZI0viXx0h5%2FgZhJk9KzIA5YdaRF7AQ8fjA%2BZjFEOPPAAAAAAECAwQF'
        '-----END%20OPENSSH%20PRIVATE%20KEY-----';
    const String sshHk =
        'ssh-ed25519%20AAAAC3NzaC1lZDI1NTE5AAAAICZI0viXx0h5%2FgZhJk9KzIA5YdaRF7AQ8fjA%2BZjFEOPP%2C%0A';
    final String vmessXhttpStringExtra = base64Encode(utf8.encode(jsonEncode(<String, dynamic>{
      'v': '2',
      'ps': 'sub-vmess-xhttp-panel',
      'add': 'proxY.EXaMpLe.invalid',
      'port': 443,
      'id': subId,
      'aid': 0,
      'scy': 'auto',
      'net': 'xhttp',
      'type': 'none',
      'host': 'PROxy.ExAmPLe.invalid',
      'alpn': 'h2',
      'path': '/vx-panel',
      'tls': 'tls',
      'sni': 'pROxy.exAmPLe.invalid',
      'fp': 'chrome',
      'core': 'xray',
      'extra': jsonEncode(<String, dynamic>{
        'headers': <String, String>{
          'User-Agent': 'Mozilla/5.0',
          'Pragma': 'no-cache',
        },
        'downloadSettings': <String, dynamic>{
          'address': 'dl.example.invalid',
          'port': 443,
          'network': 'xhttp',
          'security': 'tls',
          'tlsSettings': <String, dynamic>{
            'serverName': 'dl.example.invalid',
            'alpn': <String>['h2'],
            'fingerprint': 'chrome',
          },
          'xhttpSettings': <String, dynamic>{
            'path': '/vx-panel',
            'host': 'dl.example.invalid',
            'mode': 'auto',
            'extra': <String, dynamic>{
              'headers': <String, String>{
                'User-Agent': 'Mozilla/5.0',
                'Pragma': 'no-cache',
              },
            },
          },
        },
      }),
      'fragment': '10-100,50-200,tlshello',
      'mc': 1,
      'padsize': '50-200',
      'muxtype': 'smux',
      'muxmaxc': 4,
      'mux': 4,
      'muxsmax': 0,
      'muxpad': false,
      'muxup': 100,
      'muxdown': 100,
    })));
    final String vmessXhttpMapExtra = base64Encode(utf8.encode(jsonEncode(<String, dynamic>{
      'v': '2',
      'ps': 'sub-vmess-xhttp-map',
      'add': 'edge.example.invalid',
      'port': 443,
      'id': subId,
      'aid': 0,
      'scy': 'auto',
      'net': 'xhttp',
      'type': 'none',
      'host': 'edge.example.invalid',
      'path': '/vx-map',
      'tls': 'tls',
      'sni': 'edge.example.invalid',
      'alpn': 'h3',
      'fp': 'chrome',
      'extra': <String, dynamic>{
        'scMaxEachPostBytes': 1000000,
        'downloadSettings': <String, dynamic>{
          'address': 'dl.example.invalid',
          'port': 443,
          'network': 'xhttp',
          'security': 'tls',
          'tlsSettings': <String, dynamic>{
            'serverName': 'dl.example.invalid',
            'alpn': <String>['h3'],
            'fingerprint': 'chrome',
          },
          'xhttpSettings': <String, dynamic>{
            'path': '/vx-map',
            'host': 'dl.example.invalid',
            'mode': 'auto',
          },
        },
      },
    })));
    final String subFeed = <String>[
      'trojan://1@127.0.0.1?sni=fake_ip_for_sub_link#InfoHeader',
      '#Watashi auto ip: 198.51.100.1',
      'vless://$subId@direct.example.invalid:443?sni=www.speedtest.net&security=reality&pbk=AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA&sid=01234567&type=tcp&flow=xtls-rprx-vision&fp=chrome#sub-vless-reality',
      'vless://$subId@ProxY.eXaMpLe.invalid:443?sni=cdn.example.invalid&type=xhttp&security=tls&path=%2Fx&host=cdn.example.invalid&mode=packet-up&alpn=h3&fp=chrome&fragment=10-100,50-200,tlshello&mc=1&padsize=50-200#sub-vless-xhttp',
      'vless://$subId@ProxY.eXaMpLe.invalid:443?sni=cdn.example.invalid&type=httpupgrade&security=tls&path=%2Fhu&host=cdn.example.invalid&headers=%7B%27User-Agent%27%3A%20%27Mozilla%2F5.0%27%2C%20%27Pragma%27%3A%20%27no-cache%27%7D&fp=chrome#sub-vless-httpupgrade',
      'vmess://$vmessXhttpStringExtra',
      'vmess://$vmessXhttpMapExtra',
      'trojan://$subId@direct.example.invalid:443?sni=direct.example.invalid&type=grpc&security=tls&mode=gun&serviceName=%2Fgrpc&authority=direct.example.invalid&alpn=h2&fp=chrome#sub-trojan-grpc',
      'ss://$ssUser@direct.example.invalid:20443?udp-over-tcp=true#sub-ss-direct',
      'ss://$ssUser@direct.example.invalid:443?plugin=obfs-local&obfs-host=www.wechat.com&obfs=http&udp-over-tcp=true#sub-ss-faketls',
      'ssh://$subId@direct.example.invalid:55240/?file=ssh&hk=$sshHk&pk=$sshPk#sub-ssh',
      'tuic://$subId:$subId@direct.example.invalid:54053?congestion_control=bbr&udp_relay_mode=native&sni=www.speedtest.net&alpn=h3#sub-tuic',
      'hysteria2://$subId@direct.example.invalid:443?obfs=salamander&obfs-password=testobfs&sni=www.speedtest.net&alpn=h3&mport=61001-62000#sub-hysteria2',
      'naive://$subId@direct.example.invalid:443?sni=direct.example.invalid&type=custom&security=tls&alpn=http%2F1.1&fp=chrome#sub-naive',
      'anytls://$subId@direct.example.invalid:443/?alpn=http%2F1.1&sni=direct.example.invalid#sub-anytls',
    ].join('\n');

    final ParseReport parsed = SubscriptionParser.parseAuto(subFeed, 'user-sub');
    expect(parsed.problems, isEmpty);
    expect(parsed.nodes, hasLength(13));
    expect(parsed.nodes.every(VpnController.usable), isTrue);

    final PreparedLinks prepared = await LinkPreparation.prepare(
      parsed.nodes.map(VpnController.linkFor).toList(),
      lookup: (_) async => <InternetAddress>[InternetAddress('192.0.2.10')],
    );

    final String executable = binary!;
    final Directory temp = await Directory.systemTemp.createTemp('umbrella-sub-all9-');
    Process? process;
    try {
      final File links = File('${temp.path}/links.txt');
      final File settings = File('${temp.path}/settings.json');
      await links.writeAsString('${prepared.links.join('\n')}\n');
      final Map<String, dynamic> options = UmbrellaCore.settingsJson(
        tun: false,
        systemProxy: false,
        port: 12334,
        logFile: '${temp.path}/core.log',
      );
      await settings.writeAsString(jsonEncode(options));
      final File output = await CoreRuntime.compile(
        executable: executable,
        workDir: File(executable).parent.path,
        runDir: temp.path,
        linksPath: links.path,
        settingsPath: settings.path,
        cancelled: () => false,
        onStarted: (Process value) => process = value,
        onFinished: (_) => process = null,
      );
      final Map<String, dynamic> compiled =
          jsonDecode(await output.readAsString()) as Map<String, dynamic>;
      final List<Map<String, dynamic>> outbounds =
          (compiled['outbounds'] as List<dynamic>).cast<Map<String, dynamic>>();
      final Set<String> types =
          outbounds.map((Map<String, dynamic> o) => '${o['type']}').toSet();
      expect(
        types,
        containsAll(<String>[
          'vless',
          'vmess',
          'trojan',
          'shadowsocks',
          'ssh',
          'tuic',
          'hysteria2',
          'naive',
          'anytls',
        ]),
      );

      final Map<String, dynamic> naiveOut =
          outbounds.firstWhere((Map<String, dynamic> o) => o['type'] == 'naive');
      final Map<String, dynamic> naiveTls =
          (naiveOut['tls'] as Map<dynamic, dynamic>).cast<String, dynamic>();
      expect(naiveTls['server_name'], 'direct.example.invalid');
      expect(naiveTls['alpn'], isNull);
      expect(naiveTls['utls'], isNull);

      final Map<String, dynamic> fakeTlsOut = outbounds.firstWhere(
        (Map<String, dynamic> o) =>
            o['type'] == 'shadowsocks' && o['plugin'] == 'obfs-local',
      );
      expect(fakeTlsOut['plugin_opts'], 'obfs=http;obfs-host=www.wechat.com');
      expect(compiled['experimental']['monitoring']['keep_top'], isNull);
      final List<Map<String, dynamic>> dnsServers =
          ((compiled['dns'] as Map<String, dynamic>)['servers'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
      expect(
        dnsServers.any(
          (Map<String, dynamic> s) => s['type'] == 'tcp' && s['server'] == '8.8.8.8',
        ),
        isTrue,
      );

      // Actually boot sing-box (`srun`) with ALL 11 outbounds across all 9 protocols!
      final Process running = await Process.start(
        executable,
        <String>['srun', '-c', output.path, '-D', temp.path],
        workingDirectory: File(executable).parent.path,
        runInShell: false,
      );
      process = running;
      final StringBuffer logs = StringBuffer();
      running.stdout.transform(utf8.decoder).listen(logs.write);
      running.stderr.transform(utf8.decoder).listen(logs.write);
      CoreProxySnapshot snapshot = const CoreProxySnapshot(reachable: false);
      for (int i = 0; i < 15; i++) {
        snapshot = await ClashApi.status(secret: '${options['web-secret']}');
        if (snapshot.reachable) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      expect(snapshot.reachable, isTrue, reason: logs.toString());
      expect(snapshot.totalCount, 13, reason: logs.toString());
      final int? earlyExit = await Future.any<int?>(<Future<int?>>[
        running.exitCode,
        Future<int?>.delayed(const Duration(milliseconds: 500), () => null),
      ]);
      expect(earlyExit, isNull, reason: logs.toString());
    } finally {
      process?.kill();
      if (process != null) {
        await process!.exitCode
            .timeout(const Duration(seconds: 5), onTimeout: () => -1);
      }
      await temp.delete(recursive: true);
    }
  }, skip: enabled ? false : 'Requires bundled Windows core', timeout: const Timeout(Duration(seconds: 60)));

  test('bundled srun starts lazy monitoring and resolves XHTTP split download with an IP upload', () async {
    final Directory temp = await Directory.systemTemp.createTemp('umbrella-srun-');
    final HttpServer endpoint = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final Completer<void> downloadReached = Completer<void>();
    endpoint.listen((HttpRequest request) async {
      if (request.uri.path.startsWith('/download') && !downloadReached.isCompleted) {
        expect(request.headers.value('host'), 'download-host.test');
        downloadReached.complete();
      }
      request.response.statusCode = request.uri.path == '/test' ? 204 : 200;
      try { await request.response.close(); } on Exception { /* core closed test */ }
    });
    final ServerSocket reservation = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final int port = reservation.port;
    await reservation.close();
    Process? process;
    final StringBuffer logs = StringBuffer();
    try {
      final Map<String, dynamic> config = <String, dynamic>{
        'log': <String, dynamic>{'level': 'debug', 'disabled': false},
        'inbounds': <dynamic>[<String, dynamic>{'type': 'mixed', 'tag': 'mixed', 'listen': '127.0.0.1', 'listen_port': port}],
        'dns': <String, dynamic>{'servers': <dynamic>[<String, dynamic>{'type': 'local', 'tag': 'local'}]},
        'route': <String, dynamic>{'default_domain_resolver': <String, dynamic>{'server': 'local', 'strategy': 'ipv4_only'}, 'final': 'split'},
        'experimental': <String, dynamic>{'monitoring': <String, dynamic>{'urls': <String>['http://127.0.0.1:${endpoint.port}/test'], 'interval': '10m'}},
        'outbounds': <dynamic>[
          <String, dynamic>{'type': 'vless', 'tag': 'split', 'server': '127.0.0.1', 'server_port': endpoint.port,
            'uuid': '00000000-0000-4000-8000-000000000001',
            'transport': <String, dynamic>{'type': 'xhttp', 'mode': 'packet-up', 'path': '/upload',
              'download': <String, dynamic>{'server': 'localhost', 'server_port': endpoint.port,
                'path': '/download', 'host': 'download-host.test'},
            },
          },
        ],
      };
      RuntimeConfig.finalize(config, profileTags: <String>{'split'});
      final File file = File('${temp.path}/runtime.json');
      await file.writeAsString(jsonEncode(config));
      process = await Process.start(binary!, <String>['srun', '-c', file.path, '-D', temp.path],
        workingDirectory: File(binary).parent.path, runInShell: false);
      process.stdout.transform(utf8.decoder).listen(logs.write);
      process.stderr.transform(utf8.decoder).listen(logs.write);
      bool ready = false;
      for (int i = 0; i < 60; i++) {
        try {
          final Socket socket = await Socket.connect('127.0.0.1', port, timeout: const Duration(milliseconds: 100));
          socket.destroy(); ready = true; break;
        } on SocketException { await Future<void>.delayed(const Duration(milliseconds: 100)); }
      }
      expect(ready, true, reason: logs.toString());
      // A VLESS server is NOT simulated here. Only prove the split transport
      // reaches its hostname download endpoint, rather than failing in 1ms.
      final HttpClient client = HttpClient()..findProxy = (_) => 'PROXY 127.0.0.1:$port';
      try {
        final HttpClientRequest request = await client.getUrl(Uri.parse('http://192.0.2.1/test'));
        unawaited(request.close().then<void>((HttpClientResponse response) async { await response.drain<void>(); }).catchError((Object _) {}));
        await downloadReached.future.timeout(const Duration(seconds: 10));
      } finally { client.close(force: true); }
      expect(logs.toString(), isNot(contains('domain not resolved')));
    } finally {
      process?.kill();
      if (process != null) await process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
      await endpoint.close(force: true);
      await temp.delete(recursive: true);
    }
  }, skip: enabled ? false : 'Requires bundled Windows core', timeout: const Timeout(Duration(seconds: 30)));

  for (final ChainPosition position in <ChainPosition>[ChainPosition.off, ChainPosition.extraSecurity, ChainPosition.unblocker]) {
    for (final ChainTransport transport in position == ChainPosition.off ? <ChainTransport>[ChainTransport.automatic] : ChainTransport.values) {
      test('bundled core builds ${position.name}/${transport.name} with XHTTP and Windows process rules', () async {
        final Map<String, dynamic> output = await generate(ChainSettings(position: position, transport: transport));
        final List<Map<String, dynamic>> inbounds = (output['inbounds'] as List<dynamic>).cast<Map<String, dynamic>>();
        final Map<String, dynamic> tun = inbounds.firstWhere((Map<String, dynamic> item) => item['type'] == 'tun');
        expect(tun['mtu'], 1400);
        expect(tun['strict_route'], true);
        final List<Map<String, dynamic>> mixed = inbounds.where((Map<String, dynamic> item) => item['type'] == 'mixed').toList();
        expect(mixed, isNotEmpty);
        expect(mixed.every((Map<String, dynamic> item) => <String>['127.0.0.1', '::1'].contains(item['listen'])), true);
        final List<Map<String, dynamic>> outbounds = (output['outbounds'] as List<dynamic>).cast<Map<String, dynamic>>();
        final Map<String, dynamic> vless = outbounds.firstWhere((Map<String, dynamic> item) => item['type'] == 'vless');
        expect(vless['server'], position == ChainPosition.unblocker ? 'proxy.example.invalid' : '192.0.2.1');
        expect(vless['tls']['server_name'], 'example.invalid');
        expect(vless['multiplex'], isNull, reason: 'mux=false must remove inherited mux/brutal');
        expect(vless['lazy'], true);
        expect(output['experimental']['monitoring']['keep_top'], isNull);
        expect(output['experimental']['monitoring']['workers'], 16);
        expect(output['experimental']['monitoring']['debounce_window'], '200ms');
        expect(output['experimental']['cache_file']['enabled'], true);
        expect(output['experimental']['debug']?['procs']?['enabled'], true);
        expect(vless['transport']['type'], 'xhttp');
        expect(vless['transport']['mode'], 'packet-up');
        expect(vless['transport']['path'], '/upload');
        final Map<String, dynamic> route = output['route'] as Map<String, dynamic>;
        final List<Map<String, dynamic>> rules = (route['rules'] as List<dynamic>).cast<Map<String, dynamic>>();
        final Map<String, dynamic> direct = rules.firstWhere((Map<String, dynamic> item) => '${item['process_name']}'.contains('offline-direct.exe'));
        expect(direct['outbound'], startsWith('direct'));
        final Map<String, dynamic> block = rules.firstWhere((Map<String, dynamic> item) => '${item['process_path']}'.contains('blocked.exe'));
        expect(block['action'], 'reject');
        expect(rules.indexOf(direct), lessThan(rules.indexOf(block)));
        if (position == ChainPosition.off) {
          expect(route['final'], 'select');
        } else {
          final Map<String, dynamic> hop;
          if (transport == ChainTransport.psiphon) {
            hop = outbounds.firstWhere((Map<String, dynamic> item) => item['type'] == 'psiphon');
          } else {
            final List<Map<String, dynamic>> endpoints = (output['endpoints'] as List<dynamic>).cast<Map<String, dynamic>>();
            hop = endpoints.firstWhere((Map<String, dynamic> item) => item['type'] == 'warp');
            expect(hop['mode'], switch (transport) {
              ChainTransport.automatic => 'auto', ChainTransport.wireguard => 'wg',
              ChainTransport.awg => 'awg', ChainTransport.masque => 'masque', ChainTransport.psiphon => '',
            });
          }
          if (position == ChainPosition.extraSecurity) {
            expect(route['final'], hop['tag']);
            expect(hop['detour'], 'select');
          } else {
            expect(route['final'], 'select');
            expect(vless['detour'], hop['tag']);
          }
        }
      }, skip: enabled ? false : 'Set UMBRELLA_CORE_SMOKE after bundling the Windows DLLs', timeout: const Timeout(Duration(seconds: 45)));
    }
  }

  test(
    'v5.9.11 core compiles bot-synced content control and custom domain block rules cleanly',
    () async {
      final String executable = binary!;
      final Directory temp =
          await Directory.systemTemp.createTemp('umbrella-filter-');
      try {
        final File links = File('${temp.path}/links.txt');
        final File settings = File('${temp.path}/settings.json');
        await links.writeAsString(
          'vless://11111111-1111-1111-1111-111111111111@192.0.2.1:443?security=tls&sni=example.invalid&type=ws&path=%2Fws#filter-smoke\n',
        );
        final Map<String, dynamic> options = UmbrellaCore.settingsJson(
          tun: false,
          systemProxy: false,
          port: 12334,
          logFile: '${temp.path}/core.log',
          logLevel: 'debug',
          remoteDns: 'https://sky.rethinkdns.com/dns-query',
          contentFilter: const FilterSettings(
            enabled: true,
            categories: <String>['adult', 'gambling', 'ads', 'dating'],
            customDomains: <String>['blocked.example.com'],
            updatedBy: 'telegram',
          ),
        );
        expect(options['log-level'], 'debug');
        expect(options['log-level-after'], 'warn');
        expect(options['log-level-until'], isA<String>());
        await settings.writeAsString(jsonEncode(options));

        final File compiledFile = await CoreRuntime.compile(
          executable: executable,
          workDir: File(executable).parent.path,
          runDir: temp.path,
          linksPath: links.path,
          settingsPath: settings.path,
          cancelled: () => false,
          onStarted: (_) {},
          onFinished: (_) {},
        );
        final Map<String, dynamic> compiled =
            jsonDecode(await compiledFile.readAsString())
                as Map<String, dynamic>;
        final List<Map<String, dynamic>> routeRules =
            ((compiled['route'] as Map<String, dynamic>)['rules']
                    as List<dynamic>)
                .cast<Map<String, dynamic>>();
        final List<Map<String, dynamic>> rejectRouteRules = routeRules
            .where((Map<String, dynamic> item) => item['action'] == 'reject')
            .toList();
        expect(rejectRouteRules.length, greaterThanOrEqualTo(5));
        expect(
          jsonEncode(rejectRouteRules),
          allOf(
            contains('pornhub.com'),
            contains('bet365.com'),
            contains('doubleclick.net'),
            contains('tinder.com'),
            contains('blocked.example.com'),
          ),
        );
        final List<Map<String, dynamic>> dnsRules =
            ((compiled['dns'] as Map<String, dynamic>)['rules']
                    as List<dynamic>)
                .cast<Map<String, dynamic>>();
        expect(
          jsonEncode(dnsRules),
          contains('blocked.example.com'),
        );
      } finally {
        await temp.delete(recursive: true);
      }
    },
    skip: enabled ? false : 'Set UMBRELLA_CORE_SMOKE after bundling the Windows DLLs',
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
