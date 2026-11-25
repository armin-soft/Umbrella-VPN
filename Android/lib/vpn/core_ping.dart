import 'dart:async';
import 'dart:math' as math;

import '../core/app_config.dart';
import '../models/models.dart';
import '../platform/native.dart';
import 'clash_api.dart';
import 'cores.dart';
import 'ping.dart';
import 'vpn_controller.dart';

/// سنجش تاخیر واقعی گره ها در اندروید.
///
/// هنگام اتصال فعال، از رابط کلش هسته (`127.0.0.1:16756`) تاخیر واقعی هر
/// خروجی درون هسته خوانده می شود؛ در حالت قطع، با سنجش موازی اتصال TCP/TLS
/// زمان پاسخ دهی سرورها بدون ایجاد تداخل با سرویس VPN اندازه گرفته می شود.
class CorePinger {
  CorePinger(this._provisioner, {NativeBridge? native})
      : _ping = PingService(native ?? NativeBridge());

  // نگه داشتن مرجع جهت هم راستا شدن API با نسخه دسکتاپ.
  // ignore: unused_field
  final CoreProvisioner _provisioner;
  final PingService _ping;

  bool _stopped = false;
  bool _busy = false;
  String _lastError = '';

  bool get busy => _busy;

  Future<void> stopAll() async {
    _stopped = true;
    _busy = false;
  }

  static const int _maxNodes = 24;

  static bool supports(VpnNode node) => node.protocol != NodeProtocol.clash;

  Future<Map<String, int>> measure(
    List<VpnNode> nodes, {
    required AppSettings settings,
    int concurrency = 4,
    Duration budget = const Duration(seconds: 40),
    int maxNodes = _maxNodes,
  }) async {
    final Map<String, int> delays = <String, int>{};
    _stopped = false;
    _busy = true;
    _lastError = '';
    try {
      final List<VpnNode> ordered = nodes
          .where((VpnNode node) =>
              supports(node) &&
              VpnController.usable(node) &&
              node.host.isNotEmpty &&
              node.port > 0)
          .toList()
        ..sort((VpnNode a, VpnNode b) {
          if (a.hasPing != b.hasPing) return a.hasPing ? -1 : 1;
          return a.pingMs.compareTo(b.pingMs);
        });
      if (ordered.isEmpty) return delays;

      final int limit = maxNodes < 1 ? _maxNodes : maxNodes;
      final List<VpnNode> targets =
          ordered.length > limit ? ordered.sublist(0, limit) : ordered;

      // اگر هسته هم اکنون در حال اجرا است، از Clash API تاخیر خروجی را بخوانیم.
      final CoreProxySnapshot status = await ClashApi.status(
        port: AppConfig.coreClashPort,
        secret: AppConfig.coreClashSecret,
      );
      if (status.reachable && !_stopped) {
        final DateTime deadline = DateTime.now().add(budget);
        int cursor = 0;
        final int workers = math.min(math.max(1, concurrency), targets.length);
        Future<void> clashWorker() async {
          while (!_stopped && DateTime.now().isBefore(deadline)) {
            final int i = cursor++;
            if (i >= targets.length) return;
            final VpnNode node = targets[i];
            final int delayMs = await ClashApi.testDelay(
              node.name,
              port: AppConfig.coreClashPort,
              secret: AppConfig.coreClashSecret,
              timeout: const Duration(seconds: 4),
            );
            if (delayMs >= 5) {
              delays[node.id] = delayMs;
            }
          }
        }

        await Future.wait(<Future<void>>[
          for (int w = 0; w < workers; w++) clashWorker(),
        ]);
        if (delays.isNotEmpty) return delays;
      }

      // حالت قطع یا نبود پاسخ کلش: سنجش سریع TCP به پورت سرورها.
      final DateTime deadline = DateTime.now().add(budget);
      int cursor = 0;
      final int workers = math.min(6, targets.length);
      Future<void> tcpWorker() async {
        while (!_stopped && DateTime.now().isBefore(deadline)) {
          final int i = cursor++;
          if (i >= targets.length) return;
          final VpnNode node = targets[i];
          final VpnNode measured = await _ping.measure(node, attempts: 1);
          if (measured.pingMs >= 5) {
            delays[node.id] = measured.pingMs;
          }
        }
      }

      await Future.wait(<Future<void>>[
        for (int w = 0; w < workers; w++) tcpWorker(),
      ]);
      return delays;
    } catch (e) {
      _lastError = '$e';
      return delays;
    } finally {
      _busy = false;
    }
  }

  Future<String> lastError() async => _lastError;
}
