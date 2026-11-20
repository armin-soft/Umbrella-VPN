import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/data/parsers.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/vpn/umbrella_core.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

void main() {
  Map<String, dynamic> build(AppSettings settings, {bool tun = true}) =>
      UmbrellaCore.settingsJson(tun: tun, systemProxy: !tun, port: 12334, networkSettings: settings);

  test('every supported stack reaches the pinned core', () {
    for (final TunStack stack in TunStack.values) {
      expect(build(AppSettings(tunStack: stack))['tun-implementation'],
          stack == TunStack.auto ? 'sing15' : stack.name);
    }
    expect(AppSettings.fromJson(<String, dynamic>{}).tunStack, TunStack.auto);
    expect(AppSettings.fromJson(<String, dynamic>{'tunStack': 'mixed'}).tunStack, TunStack.mixed);
  });

  test('network settings persist and reach runtime in tunnel and proxy mode', () {
    const AppSettings original = AppSettings(
      tunStack: TunStack.system, mtu: 1400, strictRoute: false,
      blockIpv6: true, remoteDns: 'https://9.9.9.9/dns-query',
      directDns: '8.8.8.8', logLevel: 'error',
    );
    final AppSettings reloaded = AppSettings.fromJson(original.toJson());
    for (final bool tun in <bool>[true, false]) {
      final Map<String, dynamic> json = build(reloaded, tun: tun);
      expect(json['mtu'], 1400);
      expect(json['strict-route'], false);
      expect(json['ipv6-mode'], 'ipv4_only');
      expect(json['remote-dns-address'], original.remoteDns);
      expect(json['direct-dns-address'], original.directDns);
      expect(json['log-level'], 'error');
      expect(json['enable-tun'], tun);
      expect(json['set-system-proxy'], !tun);
      expect(json['allow-connection-from-lan'], false);
      expect(json['chain-status'], 'off');
    }
    expect(build(original.copyWith(blockIpv6: false))['ipv6-mode'], 'prefer_ipv4');
  });

  test('invalid persisted options cannot produce invalid core options', () {
    expect(build(const AppSettings(mtu: -1))['mtu'], 1280);
    expect(build(const AppSettings(mtu: 99999))['mtu'], 9000);
    expect(build(const AppSettings(logLevel: 'invalid'))['log-level'], 'warn');
    final AppSettings settings = AppSettings.fromJson(<String, dynamic>{
      'coreDefaultsVersion': AppSettings.currentCoreDefaultsVersion,
      'mtu': 99999,
      'tunStack': 'invalid',
      'remoteDns': 'https://unknown.invalid/dns-query',
      'directDns': '',
    });
    expect(settings.mtu, 9000);
    expect(settings.tunStack, TunStack.auto);
    expect(build(settings)['remote-dns-address'], NetworkDns.defaultRemote);
    expect(build(settings)['direct-dns-address'], NetworkDns.defaultDirect);
    expect(
      build(settings.copyWith(directDns: 'udp://1.1.1.1'))['direct-dns-address'],
      '1.1.1.1',
    );
    for (final String dns in NetworkDns.presets.keys) {
      expect(build(settings.copyWith(remoteDns: dns))['remote-dns-address'], dns);
    }
    // No invented enable-dns-routing key: the pinned core has no such toggle.
    expect(build(settings).containsKey('enable-dns-routing'), false);
  });

  test('legacy settings migrate untouched defaults to Hiddify TCP DNS while keeping custom choices', () {
    final AppSettings migrated = AppSettings.fromJson(<String, dynamic>{
      'remoteDns': 'https://1.1.1.1/dns-query',
      'directDns': '1.1.1.1',
      'logLevel': 'info',
    });
    expect(migrated.remoteDns, 'tcp://8.8.8.8');
    expect(migrated.directDns, '1.1.1.1');
    expect(migrated.logLevel, 'warn');
    expect(migrated.toJson()['coreDefaultsVersion'], AppSettings.currentCoreDefaultsVersion);

    // Explicit user choice after migration is never overwritten again.
    final AppSettings reChosen = AppSettings.fromJson(
      migrated.copyWith(remoteDns: 'https://1.1.1.1/dns-query', logLevel: 'info').toJson(),
    );
    expect(reChosen.remoteDns, 'https://1.1.1.1/dns-query');
    expect(reChosen.logLevel, 'info');

    // Legacy user who already customized DNS/log keeps their exact values.
    final AppSettings customized = AppSettings.fromJson(<String, dynamic>{
      'remoteDns': 'https://9.9.9.9/dns-query',
      'directDns': '8.8.8.8',
      'logLevel': 'debug',
    });
    expect(customized.remoteDns, 'https://9.9.9.9/dns-query');
    expect(customized.directDns, '8.8.8.8');
    expect(customized.logLevel, 'debug');
  });

  VpnNode node(Map<String, dynamic> params, {String raw = ''}) => VpnNode(
    id: 'test', name: 'authorized panel node', host: 'example.com', port: 443,
    protocol: NodeProtocol.vless, sourceId: 'panel', params: params, raw: raw,
  );

  test('XHTTP link retains mode, extra, path, host, encryption and TLS fields', () {
    final Map<String, dynamic> extra = <String, dynamic>{
      'noGRPCHeader': true, 'xPaddingBytes': '100-200',
      'xmux': <String, dynamic>{'maxConcurrency': '4-8'},
    };
    for (final String transport in <String>['xhttp', 'splithttp']) {
      final VpnNode server = node(<String, dynamic>{
        'id': 'uuid', 'network': transport, 'mode': 'stream-one', 'extra': extra,
        'path': '/a?b=c', 'host': 'cdn.example.com', 'sni': 'tls.example.com',
        'security': 'tls', 'alpn': 'h3', 'encryption': 'custom.encryption',
      });
      expect(VpnController.usable(server), true);
      final Map<String, String> query = Uri.parse(VpnController.linkFor(server)).queryParameters;
      expect(query['type'], transport);
      expect(query['mode'], 'stream-one');
      expect(jsonDecode(query['extra']!), extra);
      expect(query['path'], '/a?b=c');
      expect(query['host'], 'cdn.example.com');
      expect(query['sni'], 'tls.example.com');
      expect(query['encryption'], 'custom.encryption');
      expect(query['alpn'], 'h3');
    }
  });

  test('raw authorized links are passed intact including XHTTP extra', () {
    const String raw = 'vless://uuid@example.com:443?type=xhttp&mode=packet-up&extra=%7B%22noGRPCHeader%22%3Atrue%7D#panel';
    expect(VpnController.linkFor(node(<String, dynamic>{'id': 'uuid'}, raw: raw)), raw);
    expect(VpnController.usable(node(<String, dynamic>{'id': 'uuid'}, raw: raw)), true);
    expect(VpnController.usable(node(<String, dynamic>{'id': 'uuid', 'network': 'unknown'})), false);
    expect(VpnController.usable(node(<String, dynamic>{'network': 'xhttp'})), false);
  });

  test('Clash XHTTP options survive parsing and link generation', () {
    final ParseReport report = SubscriptionParser.parseAuto('''
proxies:
  - name: panel-xhttp
    type: vless
    server: example.com
    port: 443
    uuid: uuid
    network: xhttp
    tls: true
    xhttp-opts:
      path: /upload
      host: cdn.example.com
      mode: packet-up
      extra:
        noGRPCHeader: true
''', 'panel');
    final Map<String, String> query = Uri.parse(VpnController.linkFor(report.nodes.single)).queryParameters;
    expect(query['type'], 'xhttp');
    expect(query['mode'], 'packet-up');
    expect(query['path'], '/upload');
    expect(query['host'], 'cdn.example.com');
    expect(jsonDecode(query['extra']!), <String, dynamic>{'noGRPCHeader': true});
  });

  test('launch and pinger both use persisted settings; CLI uses same file', () {
    final String controller = File('lib/vpn/vpn_controller.dart').readAsStringSync();
    final String ping = File('lib/vpn/core_ping.dart').readAsStringSync();
    expect(controller, contains('networkSettings: _settings'));
    expect(ping, contains('networkSettings: settings'));
    expect(controller, contains('settingsPath: settingsPath,'));
    expect(controller, contains('linksPath: sessionLinks.path'));
    expect(controller, contains("['srun', '-c', runtime.path, '-D', plan.runDir]"));
    expect(controller, contains('LinkPreparation.prepare('));
    expect(ping, contains('LinkPreparation.prepare('));
    expect(controller, contains('args: args,')); // CLI and background share arguments.
    expect(controller, contains('accessGuard?.call()'));
    // Existing account/source implementation is intentionally unchanged.
    final String subscriptions = File('lib/state/subscription_controller.dart').readAsStringSync();
    expect(subscriptions, contains('AppConfig.allowedSubscriptionHosts.contains(host)'));
    expect(subscriptions, contains('if (!personal)'));
  });
}
