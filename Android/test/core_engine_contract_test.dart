import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/core/network_redaction.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/vpn/umbrella_core.dart';

void main() {
  Map<String, dynamic> core(AppSettings settings, {bool tun = true}) =>
      UmbrellaCore.settingsJson(
        tun: tun,
        systemProxy: !tun,
        port: 12334,
        networkSettings: settings,
      );

  test('default and partial saved settings keep chain and rules clean', () {
    final AppSettings old = AppSettings.fromJson(<String, dynamic>{'mtu': 1400});
    final Map<String, dynamic> defaults = core(old);
    expect(defaults['chain-status'], 'off');
    final List<dynamic> rules =
        ((defaults['route-rule'] as Map<String, dynamic>?)?['rules']
                as List<dynamic>?) ??
            const <dynamic>[];
    expect(
      rules.every(
        (dynamic r) => r is Map && r['name'] == 'umbrella-block-ads',
      ),
      isTrue,
    );
    expect(defaults['local-proxy-in-vpn'], isTrue);
    expect(defaults['allow-connection-from-lan'], isFalse);
    expect(defaults['enable-tun'], isTrue);
  });

  test('every exposed auxiliary hop maps to pinned-core keys', () {
    for (final ChainPosition position in <ChainPosition>[
      ChainPosition.extraSecurity,
      ChainPosition.unblocker,
    ]) {
      for (final ChainTransport transport in ChainTransport.values) {
        final ChainSettings chain = ChainSettings(
          position: position,
          transport: transport,
        );
        final AppSettings roundTrip = AppSettings.fromJson(
          AppSettings(chain: chain).toJson(),
        );
        final Map<String, dynamic> json = core(roundTrip);
        expect(json['chain-status'], position.coreValue);
        final String key = position == ChainPosition.extraSecurity
            ? 'extra-security'
            : 'unblocker';
        final Map<String, dynamic> hop = json[key] as Map<String, dynamic>;
        expect(hop['mode'], transport.coreValue);
        expect(hop.containsKey('profile'), isFalse);
        expect(
          hop.containsKey(
            transport == ChainTransport.psiphon ? 'psiphon' : 'warp',
          ),
          isTrue,
        );
      }
    }
  });

  test('Android app route rules use package_name and reject invalid/self packages', () {
    const AppSettings settings = AppSettings(
      appRoutes: <AppRouteRule>[
        AppRouteRule(
          process: 'org.telegram.messenger',
          action: AppRouteAction.direct,
        ),
        AppRouteRule(
          process: 'com.example.blocked',
          action: AppRouteAction.block,
        ),
        AppRouteRule(
          process: 'com.example.disabled',
          enabled: false,
        ),
      ],
    );
    final AppSettings reloaded = AppSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
    );
    expect(reloaded.appRoutes, hasLength(3));
    expect(reloaded.appRoutes[2].enabled, isFalse);

    final List<dynamic> allRules =
        (core(reloaded)['route-rule'] as Map<String, dynamic>)['rules']
            as List<dynamic>;
    final List<dynamic> rules = allRules
        .where((dynamic r) => r is Map && r['package_name'] != null)
        .toList(growable: false);
    expect(rules, hasLength(2));
    expect(
      allRules.any((dynamic r) => r is Map && r['name'] == 'umbrella-block-ads'),
      isTrue,
    );
    expect(rules[0]['package_name'], <String>['org.telegram.messenger']);
    expect(rules[1]['package_name'], <String>['com.example.blocked']);
    expect(rules[0]['outbound'], 'direct');
    expect(rules[1]['outbound'], 'block');
    expect(rules[0]['list_order'], 0);
    expect(rules[1]['list_order'], 1);

    for (final String bad in <String>[
      '',
      'singleword',
      'org.telegram.messenger\n',
      'ir.umbrella.vpn',
      '../bad',
    ]) {
      expect(AppRouteRule(process: bad).validationError, isNotNull, reason: bad);
    }
    expect(const AppRouteRule(process: 'com.whatsapp').validationError, isNull);
  });

  test('diagnostic redaction hides WARP license, LAN password, and Clash secret', () {
    final String text = jsonEncode(<String, dynamic>{
      'warp': <String, dynamic>{'license-key': 'abc-123'},
      'lan-sharing-password': 'LanPw-7742',
      'web-secret': 'secret',
      'mtu': 1400,
    });
    final String clean = redactNetworkSecrets(text);
    expect(clean, isNot(contains('abc-123')));
    expect(clean, isNot(contains('LanPw-7742')));
    expect(clean, isNot(contains(':"secret"')));
    expect(clean, contains('1400'));
    expect(
      redactNetworkSecrets('core used abc-123', knownSecrets: <String>['abc-123']),
      'core used [redacted]',
    );
  });
}
