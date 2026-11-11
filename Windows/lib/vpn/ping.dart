import 'dart:async';
import 'dart:math' as math;

import '../models/models.dart';
import '../platform/native.dart';

/// اندازه گیری پینگ هر گره با آی سی ام پی و اتصال تی سی پی.
///
/// بهترین مقدار از هر دو روش گرفته می شود و پراکندگی (جیتر) هم سنجیده می شود
/// تا «پایدارترین» سرور از «سریع ترین» جدا شود.
class PingService {
  PingService(this._native);

  final NativeBridge _native;
  final Map<String, List<int>> _history = <String, List<int>>{};

  Future<VpnNode> measure(VpnNode node, {int attempts = 2}) async {
    final List<int> samples = <int>[];
    int icmpBest = -1;
    int tcpBest = -1;

    for (int attempt = 0; attempt < attempts; attempt++) {
      final List<int> results = await Future.wait<int>(<Future<int>>[
        _native.ping(node.host, timeoutMs: 1400),
        _native.tcpPing(node.host, node.port, timeoutMs: 1400),
      ]);
      final int icmp = results[0];
      final int tcp = results[1];
      if (icmp >= 0) {
        icmpBest = icmpBest < 0 ? icmp : math.min(icmpBest, icmp);
      }
      if (tcp >= 0) {
        tcpBest = tcpBest < 0 ? tcp : math.min(tcpBest, tcp);
      }
      final int best = _best(icmp, tcp);
      if (best > 0) {
        samples.add(best);
      }
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }

    if (samples.isEmpty) {
      return node.copyWith(
        pingMs: 0,
        jitterMs: 0,
        stability: 0,
        checkedAt: DateTime.now(),
      );
    }

    final List<int> history = _history.putIfAbsent(node.id, () => <int>[]);
    history.add(samples.reduce(math.min));
    if (history.length > 6) {
      history.removeAt(0);
    }

    final double average =
        history.reduce((int a, int b) => a + b) / history.length;
    final double variance = history.length < 2
        ? 0
        : history
                .map((int value) => math.pow(value - average, 2).toDouble())
                .reduce((double a, double b) => a + b) /
            history.length;
    final int jitter = math.sqrt(variance).round();
    final int bestPing = history.reduce(math.min);

    // پایداری: کمترین پینگ و کمترین پراکندگی بهترین است.
    final double stability = (1 -
            ((jitter / math.max(bestPing, 40)).clamp(0.0, 0.65)) -
            ((bestPing / 900).clamp(0.0, 0.3)))
        .clamp(0.0, 1.0);

    return node.copyWith(
      pingMs: bestPing,
      jitterMs: jitter,
      stability: stability,
      checkedAt: DateTime.now(),
    );
  }

  int _best(int icmp, int tcp) {
    if (icmp >= 0 && tcp >= 0) {
      return math.min(icmp, tcp);
    }
    if (icmp >= 0) {
      return icmp;
    }
    if (tcp >= 0) {
      return tcp;
    }
    return -1;
  }

  /// سنجش همه گره ها با محدودیت همزمانی تا شبکه اشباع نشود.
  Future<List<VpnNode>> measureAll(
    List<VpnNode> nodes, {
    int concurrency = 8,
    void Function(int done, int total)? onProgress,
  }) async {
    if (nodes.isEmpty) {
      return nodes;
    }
    final List<VpnNode> result = List<VpnNode>.of(nodes);
    int cursor = 0;
    int done = 0;

    Future<void> worker() async {
      while (true) {
        final int index = cursor;
        cursor++;
        if (index >= nodes.length) {
          return;
        }
        result[index] = await measure(nodes[index]);
        done++;
        onProgress?.call(done, nodes.length);
      }
    }

    final List<Future<void>> workers = <Future<void>>[
      for (int i = 0; i < math.min(concurrency, nodes.length); i++) worker(),
    ];
    await Future.wait(workers);
    return result;
  }

  void forget(String nodeId) => _history.remove(nodeId);
}
