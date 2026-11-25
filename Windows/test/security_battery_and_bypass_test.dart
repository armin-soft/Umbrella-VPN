import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/core/malicious_link_guard.dart';
import 'package:umbrella_vpn/core/persian.dart';
import 'package:umbrella_vpn/core/safe_url_launcher.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/vpn/runtime_config.dart';
import 'package:umbrella_vpn/vpn/umbrella_core.dart';

void main() {
  test('bundled offline Iran .srs datasets exist and are valid SRS v1 binaries', () {
    for (final String name in const <String>[
      'geoip-ir.srs',
      'geosite-ir.srs',
      'geoip-arvancloud.srs',
      'geoip-parspack.srs',
      'geoip-derakcloud.srs',
      'geoip-iranserver.srs',
    ]) {
      final File file = File('${Directory.current.path}/assets/data/$name');
      expect(file.existsSync(), isTrue, reason: 'missing $name');
      final List<int> bytes = file.readAsBytesSync();
      expect(bytes.length, greaterThan(16));
      expect(utf8.decode(bytes.sublist(0, 3)), 'SRS');
      expect(bytes[3], 1);
    }
  });

  test('FilterSettings splits IP/CIDR and domain bypass rules cleanly', () {
    expect(FilterSettings.isIpOrCidr('185.143.232.10'), isTrue);
    expect(FilterSettings.isIpOrCidr('5.200.0.0/16'), isTrue);
    expect(FilterSettings.isIpOrCidr('2001:db8::/32'), isTrue);
    expect(FilterSettings.isIpOrCidr('snapp.ir'), isFalse);

    const FilterSettings filter = FilterSettings(
      bypassIran: true,
      bypassDomains: <String>[
        'snapp.ir',
        '185.143.232.10',
        '5.200.0.0/16',
      ],
    );
    final Map<String, dynamic> settings = UmbrellaCore.settingsJson(
      tun: true,
      systemProxy: false,
      port: 12334,
      networkSettings: const AppSettings(),
      contentFilter: filter,
      batterySaving: true,
    );
    expect(settings['url-test-interval'], 1800);

    final List<Map<String, dynamic>> rules =
        ((settings['route-rule'] as Map<String, dynamic>)['rules']
                as List<dynamic>)
            .cast<Map<String, dynamic>>();
    final Map<String, dynamic> domainRule = rules.firstWhere(
      (Map<String, dynamic> r) => r['name'] == 'umbrella-bypass-user',
    );
    final Map<String, dynamic> ipRule = rules.firstWhere(
      (Map<String, dynamic> r) => r['name'] == 'umbrella-bypass-user-ip',
    );
    expect(domainRule['domain_suffix'], contains('snapp.ir'));
    expect(domainRule['domain_suffix'], isNot(contains('185.143.232.10')));
    expect(ipRule['ip_cidr'], containsAll(<String>['185.143.232.10/32', '5.200.0.0/16']));
  });

  test('RuntimeConfig.finalize configures offline Iran bypass without DNS poisoning', () {
    final Map<String, dynamic> coreSettings = UmbrellaCore.settingsJson(
      tun: true,
      systemProxy: false,
      port: 12334,
      networkSettings: const AppSettings(),
      contentFilter: const FilterSettings(
        bypassIran: true,
        bypassDomains: <String>['bankmellat.ir', '185.143.232.0/24'],
      ),
    );
    final Map<String, dynamic> runtime = <String, dynamic>{
      'experimental': <String, dynamic>{
        'monitoring': <String, dynamic>{},
      },
      'outbounds': <dynamic>[
        <String, dynamic>{'type': 'direct', 'tag': RuntimeConfig.directOutboundTag},
        <String, dynamic>{'type': 'selector', 'tag': 'select'},
      ],
      'dns': <String, dynamic>{
        'servers': <dynamic>[
          <String, dynamic>{'tag': 'dns-remote-group', 'type': 'udp', 'server': '1.1.1.1'},
          <String, dynamic>{'tag': 'dns-direct-group', 'type': 'udp', 'server': '8.8.8.8'},
        ],
        'rules': <dynamic>[
          <String, dynamic>{'domain': <String>['example.com'], 'server': 'dns-fake'},
        ],
      },
      'route': <String, dynamic>{
        'rule_set': <dynamic>[
          <String, dynamic>{
            'tag': 'geosite-ir',
            'type': 'remote',
            'format': 'binary',
            'url': 'https://raw.githubusercontent.com/umbrella/geo/geosite-ir.srs',
          },
          <String, dynamic>{
            'tag': 'geoip-ir',
            'type': 'remote',
            'format': 'binary',
            'url': 'https://raw.githubusercontent.com/umbrella/geo/geoip-ir.srs',
          },
        ],
        'rules': <dynamic>[
          <String, dynamic>{'ip_cidr': <String>['185.143.232.0/24'], 'outbound': RuntimeConfig.directOutboundTag},
          <String, dynamic>{'action': 'resolve'},
          <String, dynamic>{'rule_set': <String>['geosite-ir'], 'outbound': RuntimeConfig.directOutboundTag},
          <String, dynamic>{'domain_suffix': <String>['bankmellat.ir'], 'outbound': RuntimeConfig.directOutboundTag},
          <String, dynamic>{'rule_set': <String>['geoip-ir'], 'outbound': RuntimeConfig.directOutboundTag},
        ],
      },
    };

    RuntimeConfig.finalize(
      runtime,
      profileTags: const <String>{},
      coreSettings: coreSettings,
      localDataDir: '${Directory.current.path}/assets/data',
    );

    final List<Map<String, dynamic>> ruleSets =
        ((runtime['route'] as Map<String, dynamic>)['rule_set'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
    final Map<String, dynamic> geositeIr = ruleSets.firstWhere((r) => r['tag'] == 'geosite-ir');
    expect(geositeIr['type'], 'local');
    expect(geositeIr['path'].toString(), endsWith('geosite-ir.srs'));
    expect(ruleSets.any((r) => r['tag'] == 'geoip-arvancloud' && r['type'] == 'local'), isTrue);

    final List<Map<String, dynamic>> routeRules =
        ((runtime['route'] as Map<String, dynamic>)['rules'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
    final int resolveIdx = routeRules.indexWhere((r) => r['action'] == 'resolve');
    expect(resolveIdx, greaterThan(0));
    expect(routeRules[resolveIdx]['server'], 'dns-remote-group');

    final int directDomainIdx = routeRules.indexWhere(
      (r) => r['domain_suffix'] is List && (r['domain_suffix'] as List).contains('bankmellat.ir'),
    );
    final int directIpIdx = routeRules.indexWhere(
      (r) => r['ip_cidr'] is List && (r['ip_cidr'] as List).contains('185.143.232.0/24'),
    );
    expect(directDomainIdx, lessThan(resolveIdx));
    expect(directIpIdx, greaterThan(resolveIdx));

    final List<Map<String, dynamic>> dnsRules =
        ((runtime['dns'] as Map<String, dynamic>)['rules'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
    final int iranDnsIdx = dnsRules.indexWhere((r) => r['server'] == 'dns-direct-group');
    final int fakeDnsIdx = dnsRules.indexWhere((r) => r['server'] == 'dns-fake');
    expect(iranDnsIdx, greaterThanOrEqualTo(0));
    expect(iranDnsIdx, lessThan(fakeDnsIdx));
  });

  test('SafeUrlLauncher blocks malicious external URLs and notifies security monitor', () async {
    int rawLaunchCount = 0;
    final List<MaliciousLinkMatch> blockedMatches = <MaliciousLinkMatch>[];
    final void Function(MaliciousLinkMatch)? prevCallback =
        SafeUrlLauncher.onThreatBlocked;
    SafeUrlLauncher.onThreatBlocked = (MaliciousLinkMatch m) => blockedMatches.add(m);
    addTearDown(() => SafeUrlLauncher.onThreatBlocked = prevCallback);

    final bool openedBad = await SafeUrlLauncher.open(
      Uri.parse('https://grabify.link/track'),
      launcher: (_, __) async {
        rawLaunchCount++;
        return true;
      },
    );
    expect(openedBad, isFalse);
    expect(rawLaunchCount, 0);
    expect(blockedMatches, hasLength(1));

    final bool openedGood = await SafeUrlLauncher.open(
      Uri.parse('https://t.me/umbrella_support'),
      launcher: (_, __) async {
        rawLaunchCount++;
        return true;
      },
    );
    expect(openedGood, isTrue);
    expect(rawLaunchCount, 1);
  });

  test('Fa.stripEmojis strips emoji characters while keeping Persian & numbers', () {
    expect(
      Fa.stripEmojis('⚠️ حساب شما مسدود شد (۳۰۰ ثانیه) 🚀'),
      'حساب شما مسدود شد (۳۰۰ ثانیه)',
    );
  });

  test('Account parses channelDisabled and channelGraceRemaining cleanly', () {
    final Account acct = Account.fromJson(<String, dynamic>{
      'uuid': 'u-1',
      'enable': false,
      'is_active': false,
      'channel_disabled': true,
      'channel_status': 'left',
      'channel_grace_remaining': 140,
    });
    expect(acct.channelDisabled, isTrue);
    expect(acct.channelStatus, 'left');
    expect(acct.channelGraceRemaining, 140);
    expect(acct.canConnect, isFalse);
  });
}
