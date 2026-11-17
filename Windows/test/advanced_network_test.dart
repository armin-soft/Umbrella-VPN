import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/core/network_redaction.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/vpn/umbrella_core.dart';

void main() {
  Map<String, dynamic> core(AppSettings settings, {bool tun = true}) => UmbrellaCore.settingsJson(
    tun: tun, systemProxy: !tun, port: 12334, networkSettings: settings);

  test('default and old saved settings keep chain and process rules off', () {
    final AppSettings old = AppSettings.fromJson(<String, dynamic>{'mtu': 1400});
    expect(core(old)['chain-status'], 'off');
    expect(core(old).containsKey('route-rule'), false);
    expect(core(old)['local-proxy-in-vpn'], true);
    expect(core(old)['allow-connection-from-lan'], false);
  });
  test('every exposed hop maps to real pinned-core keys in both directions', () {
    for (final ChainPosition position in <ChainPosition>[ChainPosition.extraSecurity, ChainPosition.unblocker]) {
      for (final ChainTransport transport in ChainTransport.values) {
        final ChainSettings chain = ChainSettings(position: position, transport: transport);
        final AppSettings roundTrip = AppSettings.fromJson(AppSettings(chain: chain).toJson());
        final Map<String, dynamic> json = core(roundTrip);
        expect(json['chain-status'], position.coreValue);
        final String key = position == ChainPosition.extraSecurity ? 'extra-security' : 'unblocker';
        final Map<String, dynamic> hop = json[key] as Map<String, dynamic>;
        expect(hop['mode'], transport.coreValue);
        expect(hop.containsKey('profile'), false);
        expect(hop.containsKey(transport == ChainTransport.psiphon ? 'psiphon' : 'warp'), true);
      }
    }
  });
  test('scanner limits and MASQUE options reach core without disabling TLS', () {
    const ChainSettings chain = ChainSettings(position: ChainPosition.unblocker,
      endpoint: WarpEndpoint.scan, scanCount: 32, scanConcurrency: 4, scanTimeout: 3000,
      scanMaxRtt: 1500, searchNoise: false, mtu: 1280, masqueProtocol: 'h3');
    final Map<String, dynamic> hop = chain.toCoreOptions()['unblocker'] as Map<String, dynamic>;
    final Map<String, dynamic> warp = hop['warp'] as Map<String, dynamic>;
    expect(warp['scanner'], <String, dynamic>{'count': 32, 'concurrency': 4, 'timeout': 3000, 'max-rtt': 1500, 'search-noise': false});
    expect(warp['mtu'], 1280);
    expect(warp['masque'], <String, dynamic>{'vhttp': 'h3', 'tls-insecure': false});
    expect(warp.containsKey('clean-ip'), false);
  });
  test('custom endpoint is an IP, not a subscription or imported configuration', () {
    const ChainSettings valid = ChainSettings(position: ChainPosition.unblocker,
      transport: ChainTransport.wireguard, endpoint: WarpEndpoint.custom, address: '162.159.192.1', port: 2408);
    expect(valid.validationError, isNull);
    final Map<String, dynamic> warp = (valid.toCoreOptions()['unblocker'] as Map<String, dynamic>)['warp'] as Map<String, dynamic>;
    expect(warp['clean-ip'], '162.159.192.1');
    expect(warp['clean-port'], 2408);
    for (final String address in <String>['https://external.invalid/sub', '127.0.0.1', '::1', '0.0.0.0', '192.0.2.1\n--flag']) {
      expect(ChainSettings(position: ChainPosition.unblocker, endpoint: WarpEndpoint.custom, address: address).validationError, isNotNull);
    }
  });
  test('invalid enabled chain fails instead of silently connecting without it', () {
    for (final ChainSettings invalid in <ChainSettings>[
      const ChainSettings(position: ChainPosition.unblocker, port: 0),
      const ChainSettings(position: ChainPosition.unblocker, mtu: 99999),
      const ChainSettings(position: ChainPosition.unblocker, scanConcurrency: 99),
      const ChainSettings(position: ChainPosition.extraSecurity, endpoint: WarpEndpoint.scan),
      const ChainSettings(position: ChainPosition.unblocker, endpoint: WarpEndpoint.custom, address: '162.159.192.1', transport: ChainTransport.masque),
    ]) {
      expect(invalid.toCoreOptions, throwsFormatException);
    }
  });
  test('ordered process rules use protobuf JSON names; proxy mode omits them', () {
    const AppSettings settings = AppSettings(appRoutes: <AppRouteRule>[
      AppRouteRule(process: 'browser.exe', action: AppRouteAction.direct),
      AppRouteRule(process: r'C:\Apps\blocked.exe', action: AppRouteAction.block),
      AppRouteRule(process: 'other.exe', enabled: false),
    ]);
    final AppSettings reloaded = AppSettings.fromJson(jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>);
    final List<dynamic> rules = (core(reloaded)['route-rule'] as Map<String, dynamic>)['rules'] as List<dynamic>;
    expect(rules[0]['process_name'], <String>['browser.exe']);
    expect(rules[1]['process_path'], <String>[r'C:\Apps\blocked.exe']);
    expect(rules[0]['outbound'], 'direct');
    expect(rules[1]['outbound'], 'block');
    expect(rules[2]['enabled'], false);
    expect(rules[0]['list_order'], 0);
    expect(rules[1]['list_order'], 1);
    expect(core(reloaded, tun: false).containsKey('route-rule'), false);
  });
  test('rules never become unconditional and diagnostic processes cannot bypass', () {
    for (final String process in <String>['', '*', 'x', 'app.exe\n', r'..\app.exe', r'\\server\app.exe', 'UmbrellaVPN.exe', 'UmbrellaCli.exe', 'app?.exe']) {
      expect(AppRouteRule(process: process).validationError, isNotNull, reason: process);
    }
    expect(const AppRouteRule(process: 'app.exe').validationError, isNull);
    expect(const AppRouteRule(process: r'C:\Program Files\App\app.exe').validationError, isNull);
    expect(() => core(const AppSettings(appRoutes: <AppRouteRule>[AppRouteRule(process: '')])), throwsFormatException);
  });
  test('diagnostic redaction hides WARP license and local API secret', () {
    final String text = jsonEncode(<String, dynamic>{'warp': <String, dynamic>{'license-key': 'abc-123'}, 'web-secret': 'secret', 'mtu': 1400});
    final String clean = redactNetworkSecrets(text);
    expect(clean, isNot(contains('abc-123')));
    expect(clean, isNot(contains(':"secret"')));
    expect(clean, contains('1400'));
    expect(redactNetworkSecrets('core used abc-123', knownSecrets: <String>['abc-123']), 'core used [redacted]');
  });
  test('auxiliary hop cannot replace account gating or authorized input', () {
    final String controller = File('lib/vpn/vpn_controller.dart').readAsStringSync();
    final int start = controller.indexOf('Future<ConnectOutcome> _connectInner');
    final String connect = controller.substring(start, controller.indexOf('final List<VpnNode> regionalNodes', start));
    expect(connect.indexOf('accessGuard?.call()'), lessThan(connect.indexOf('_settings.chain')));
    expect(connect, contains('if (_nodes.isEmpty)'));
    expect(controller, contains('networkSettings: _settings'));
    expect(controller, contains('VerifiedProbe.check(proxyPort: _umbrellaPort'));
    expect(controller, isNot(contains('return _coreReportsWorkingTunnel')));
    final String source = File('lib/state/subscription_controller.dart').readAsStringSync();
    expect(source, contains('AppConfig.allowedSubscriptionHosts.contains(host)'));
    expect(source, contains('if (!personal)'));
  });
}
