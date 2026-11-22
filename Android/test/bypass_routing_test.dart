import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/vpn/umbrella_core.dart';

void main() {
  test('direct site rules remain separate from and below content blocks', () {
    const filter = FilterSettings(enabled: true, customDomains: <String>['blocked.example'],
      bypassIran: true, bypassDomains: <String>['example.org']);
    final json = UmbrellaCore.settingsJson(tun: true, systemProxy: false, port: 12334,
      networkSettings: const AppSettings(), contentFilter: filter);
    final rules = ((json['route-rule'] as Map<String, dynamic>)['rules'] as List<dynamic>).cast<Map<String, dynamic>>();
    final block = rules.indexWhere((r) => r['name'] == 'umbrella-filter-custom');
    final direct = rules.indexWhere((r) => r['name'] == 'umbrella-bypass-user');
    final iran = rules.indexWhere((r) => r['name'] == 'umbrella-bypass-iran');
    expect(block, greaterThanOrEqualTo(0));
    expect(direct, greaterThan(block));
    expect(rules[direct]['outbound'], 'direct');
    expect(rules[direct]['domain_suffix'], contains('example.org'));
    expect(rules[iran]['domain_suffix'], contains('.ir'));
    expect(rules[iran]['rule_set'], isNotEmpty);
    expect(FilterSettings.fromJson(filter.toJson()).bypassDomains, ['example.org']);
    expect(FilterSettings.fromJson(filter.toJson()).bypassIran, isTrue);
  });
  test('direct rules work even with content filtering off', () {
    const filter = FilterSettings(bypassDomains: <String>['example.org']);
    expect(filter.sameEffectAs(FilterSettings.empty), isFalse);
    final json = UmbrellaCore.settingsJson(tun: true, systemProxy: false, port: 12334,
      networkSettings: const AppSettings(), contentFilter: filter);
    expect(((json['route-rule'] as Map<String, dynamic>)['rules'] as List<dynamic>).any((dynamic r) => r['name'] == 'umbrella-bypass-user'), isTrue);
  });
}
