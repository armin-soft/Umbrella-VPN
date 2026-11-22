import 'clash_api.dart';

/// Windows-style in-place failover: ask the same core to retest its active
/// path and selector; do not destroy the Android TUN or accept proxy status as
/// proof that device traffic actually crosses the VPN.
class MobileFailover {
  MobileFailover({
    required this.snapshot,
    required this.testDelay,
    required this.verifyTun,
  });

  final Future<CoreProxySnapshot> Function() snapshot;
  final Future<int> Function(String) testDelay;
  final Future<bool> Function() verifyTun;

  Future<MobileHealthResult> check({required bool allowFailover, required bool previouslyVerified, required bool Function() isCurrent}) async {
    final status = await snapshot();
    if (!isCurrent()) return const MobileHealthResult(stale: true);
    if (!status.reachable) return const MobileHealthResult();
    if (status.connectivity == CoreConnectivityState.noAvailableProxies) {
      if (allowFailover) {
        if (status.activeTag.isNotEmpty) {
          await testDelay(status.activeTag);
          if (!isCurrent()) return const MobileHealthResult(stale: true);
        }
        await testDelay('select');
        if (!isCurrent()) return const MobileHealthResult(stale: true);
      }
      final verified = await verifyTun();
      if (!isCurrent()) return const MobileHealthResult(stale: true);
      return MobileHealthResult(verified: verified, nudged: allowFailover);
    }
    if (!previouslyVerified && status.connectivity == CoreConnectivityState.started) {
      final verified = await verifyTun();
      if (!isCurrent()) return const MobileHealthResult(stale: true);
      return MobileHealthResult(verified: verified, ping: status.activeDelayMs);
    }
    return MobileHealthResult(ping: status.activeDelayMs);
  }
}

class MobileHealthResult {
  const MobileHealthResult({this.verified, this.ping = 0, this.nudged = false, this.stale = false});
  /// Null means no evidence either way, not a successful traffic test.
  final bool? verified;
  final int ping;
  final bool nudged;
  final bool stale;
}
