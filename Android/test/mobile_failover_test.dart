import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/vpn/clash_api.dart';
import 'package:umbrella_vpn/vpn/mobile_failover.dart';

void main() {
  const dead = CoreProxySnapshot(reachable: true,
      connectivity: CoreConnectivityState.noAvailableProxies, activeTag: 'private-tag');
  test('retests active route and selector without treating core status as verified TUN', () async {
    final calls = <String>[];
    final health = MobileFailover(snapshot: () async => dead,
      testDelay: (tag) async { calls.add(tag); return 7; },
      verifyTun: () async => false);
    final result = await health.check(allowFailover: true, previouslyVerified: true, isCurrent: () => true);
    expect(calls, ['private-tag', 'select']);
    expect(result.nudged, isTrue);
    expect(result.verified, isFalse);
  });

  test('manual selection does not silently switch routes', () async {
    final calls = <String>[];
    final health = MobileFailover(snapshot: () async => dead,
      testDelay: (tag) async { calls.add(tag); return 1; }, verifyTun: () async => false);
    final result = await health.check(allowFailover: false, previouslyVerified: true, isCurrent: () => true);
    expect(calls, isEmpty);
    expect(result.verified, isFalse);
    expect(result.nudged, isFalse);
  });

  test('unreachable control API does not invent a result; stale session stops', () async {
    var calls = 0;
    final health = MobileFailover(snapshot: () async => CoreProxySnapshot.offline,
      testDelay: (_) async { calls++; return 1; }, verifyTun: () async { calls++; return true; });
    expect((await health.check(allowFailover: true, previouslyVerified: true, isCurrent: () => true)).verified, isNull);
    expect((await health.check(allowFailover: true, previouslyVerified: true, isCurrent: () => false)).stale, isTrue);
    expect(calls, 0);
  });

  test('restoration requires traffic verification even if monitor reports started', () async {
    final health = MobileFailover(snapshot: () async => const CoreProxySnapshot(reachable: true,
        connectivity: CoreConnectivityState.started, activeDelayMs: 42),
      testDelay: (_) async => 1, verifyTun: () async => false);
    final result = await health.check(allowFailover: true, previouslyVerified: false, isCurrent: () => true);
    expect(result.verified, isFalse);
    expect(result.ping, 42);
  });
}
