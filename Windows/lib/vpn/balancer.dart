import 'dart:math' as math;

import '../models/models.dart';

class SelectionResult {
  const SelectionResult({required this.node, required this.reason});

  final VpnNode? node;
  final String reason;
}

/// انتخاب سرور بر اساس حالت های اتصال: خودکار، گردشی، هش پایدار و چسبنده.
class NodeBalancer {
  NodeBalancer();

  int _roundRobinIndex = 0;
  String _stickyNodeId = '';
  DateTime? _stickySince;
  final Map<String, DateTime> _failures = <String, DateTime>{};

  /// سروری که همین حالا اتصالش شکست خورده، تا مدتی پیشنهاد نمی شود.
  void markFailed(String nodeId) {
    if (nodeId.isEmpty) {
      return;
    }
    _failures[nodeId] = DateTime.now();
  }

  bool recentlyFailed(VpnNode node, {int cooldownSeconds = 120}) {
    final DateTime? at = _failures[node.id];
    if (at == null) {
      return false;
    }
    return DateTime.now().difference(at).inSeconds < cooldownSeconds;
  }

  SelectionResult pick({
    required List<VpnNode> nodes,
    required SelectionMode mode,
    required String deviceSeed,
    String preferredNodeId = '',
    int stickyMinutes = 30,
    bool allowFailover = true,
  }) {
    final List<VpnNode> all = nodes
        .where((VpnNode node) => !node.disabled && node.host.isNotEmpty)
        .toList();
    final List<VpnNode> fresh = all
        .where((VpnNode node) => !recentlyFailed(node))
        .toList();
    final List<VpnNode> usable = fresh.isEmpty ? all : fresh;
    if (usable.isEmpty) {
      return const SelectionResult(node: null, reason: 'سرور قابل استفاده ای وجود ندارد.');
    }

    switch (mode) {
      case SelectionMode.manual:
        final VpnNode? chosen = _byId(usable, preferredNodeId);
        return SelectionResult(
          node: chosen ?? _bestAuto(usable),
          reason: chosen == null
              ? 'سرور انتخابی در دسترس نبود؛ خودکار انتخاب شد.'
              : 'سرور انتخابی شما.',
        );
      case SelectionMode.roundRobin:
        final int index = _roundRobinIndex % usable.length;
        _roundRobinIndex = (index + 1) % usable.length;
        final VpnNode node = usable[index];
        return SelectionResult(
          node: node,
          reason: 'انتخاب گردشی برای پخش بار (نوبت ${node.name}).',
        );
      case SelectionMode.consistentHash:
        final VpnNode node = _consistentHash(usable, deviceSeed);
        return SelectionResult(
          node: node,
          reason: 'انتخاب پایدار بر اساس هش دستگاه.',
        );
      case SelectionMode.stickySession:
        final bool sameSession = _stickySince != null &&
            DateTime.now().difference(_stickySince!) <
                Duration(minutes: stickyMinutes);
        final VpnNode? sticky = _byId(usable, _stickyNodeId);
        if (sameSession && sticky != null) {
          return SelectionResult(
            node: sticky,
            reason: 'همان سرور نشست قبلی برای پایداری بیشتر.',
          );
        }
        if (allowFailover && preferredNodeId.isNotEmpty) {
          final VpnNode? preferred = _byId(usable, preferredNodeId);
          if (preferred != null &&
              preferred.hasPing &&
              preferred.stability > 0.55) {
            _stickyNodeId = preferred.id;
            _stickySince = DateTime.now();
            return SelectionResult(
              node: preferred,
              reason: 'سرور قبلی شما پایدار بود و نگه داشته شد.',
            );
          }
        }
        final VpnNode? best = _bestAuto(usable);
        if (best != null) {
          _stickyNodeId = best.id;
          _stickySince = DateTime.now();
        }
        return SelectionResult(
          node: best,
          reason: 'شروع نشست چسبنده با پایدارترین سرور.',
        );
      case SelectionMode.auto:
        final VpnNode? current = _byId(usable, preferredNodeId);
        final VpnNode? best = _bestAuto(usable);
        if (best == null) {
          return SelectionResult(
            node: current ?? usable.first,
            reason: 'پینگی اندازه گیری نشد؛ نزدیک ترین گزینه انتخاب شد.',
          );
        }
        // اگر سرور فعلی نزدیک به بهترین است، برای پایداری عوض نمی شود.
        if (current != null && current.hasPing && current.pingMs <= best.pingMs * 1.2) {
          return SelectionResult(
            node: current,
            reason: 'سرور فعلی همچنان پایدار و نزدیک به بهترین است.',
          );
        }
        return SelectionResult(
          node: best,
          reason: 'پایدارترین سرور با کمترین پینگ انتخاب شد.',
        );
    }
  }

  VpnNode? _byId(List<VpnNode> nodes, String id) {
    if (id.isEmpty) {
      return null;
    }
    for (final VpnNode node in nodes) {
      if (node.id == id) {
        return node;
      }
    }
    return null;
  }

  VpnNode? _bestAuto(List<VpnNode> nodes) {
    final List<VpnNode> measured =
        nodes.where((VpnNode node) => node.hasPing).toList();
    if (measured.isEmpty) {
      return null;
    }
    measured.sort((VpnNode a, VpnNode b) => _score(a).compareTo(_score(b)));
    return measured.first;
  }

  /// امتیاز کمتر بهتر است: پینگ پایین و پایداری بالا.
  double _score(VpnNode node) {
    final double stability = node.stability <= 0 ? 0.35 : node.stability;
    final double penalty = 1.6 - stability;
    return node.pingMs * penalty + node.jitterMs * 0.8;
  }

  /// هش پایدار: حلقه ای از گره ها و انتخاب نزدیک ترین نقطه به هش دستگاه.
  VpnNode _consistentHash(List<VpnNode> nodes, String seed) {
    final List<int> ring = nodes
        .map((VpnNode node) => _fnv1a('${node.id}|$seed'))
        .toList();
    final int key = _fnv1a(seed);
    int bestIndex = 0;
    int bestDistance = 1 << 31;
    for (int i = 0; i < ring.length; i++) {
      final int distance = (ring[i] - key).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return nodes[bestIndex];
  }

  int _fnv1a(String value) {
    int hash = 0x811C9DC5;
    for (final int byte in value.codeUnits) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash;
  }

  /// نشان دادن بهترین گزینه بدون تغییر وضعیت انتخاب.
  VpnNode? preview(List<VpnNode> nodes, SelectionMode mode, String seed) {
    final List<VpnNode> usable =
        nodes.where((VpnNode node) => !node.disabled).toList();
    if (usable.isEmpty) {
      return null;
    }
    switch (mode) {
      case SelectionMode.consistentHash:
        return _consistentHash(usable, seed);
      case SelectionMode.roundRobin:
        return usable[_roundRobinIndex % usable.length];
      default:
        return _bestAuto(usable) ?? usable.first;
    }
  }

  void resetSticky() {
    _stickyNodeId = '';
    _stickySince = null;
  }

  void markConnected(String nodeId) {
    _stickyNodeId = nodeId;
    _stickySince = DateTime.now();
  }

  Duration get stickyAge {
    if (_stickySince == null) {
      return Duration.zero;
    }
    return DateTime.now().difference(_stickySince!);
  }

  int get worstPenaltyMs => math.max(0, 0);
}
