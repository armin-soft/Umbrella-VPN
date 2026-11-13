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
      // اول اتصال TCP به پورت خود سرور؛ سریع تر است و همان مسیری را می سنجد
      // که تونل استفاده می کند. فقط اگر بسته شد، پینگ ICMP هم امتحان می شود.
      final int tcp = await _native.tcpPing(node.host, node.port, timeoutMs: 1200);
      final int icmp = tcp >= 0 ? -1 : await _native.ping(node.host, timeoutMs: 1200);
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

    return _derive(node, samples.reduce(math.min));
  }

  /// ثبت تاخیر اندازه گیری شده با هسته (تاخیر واقعی تونل).
  ///
  /// عدد تونل دقیق تر از تی سی پی و آی سی ام پی است؛ پس همان مبنای نمایش
  /// قرار می گیرد و جیتر از تاریخچه حساب می شود.
  VpnNode withTunnelDelay(VpnNode node, int delayMs) {
    if (delayMs <= 0) {
      return node;
    }
    final List<int> history = _history.putIfAbsent(node.id, () => <int>[]);
    history.add(delayMs);
    if (history.length > 6) {
      history.removeAt(0);
    }
    return _derive(node, history.reduce(math.min));
  }

  VpnNode _derive(VpnNode node, int bestPing) {
    final List<int> history = _history[node.id] ?? <int>[bestPing];
    final double average =
        history.reduce((int a, int b) => a + b) / history.length;
    final double variance = history.length < 2
        ? 0
        : history
                .map((int value) => math.pow(value - average, 2).toDouble())
                .reduce((double a, double b) => a + b) /
            history.length;
    final int jitter = math.sqrt(variance).round();

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
