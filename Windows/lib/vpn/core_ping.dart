import 'dart:async';
import 'dart:io';

import '../models/models.dart';
import 'cores.dart';
import 'umbrella_core.dart';
import 'vpn_controller.dart';
import 'tunnel_probe.dart';

/// سنجش تاخیر واقعی هر سرور با موتور هسته.
///
/// برای هر سرور یک نمونه کوتاه از همان هسته اجرا می شود: هسته از یک لینک،
/// پروکسی محلی می سازد و همان درخواست
/// کوچک از داخلش رد می شود. عددی که به دست می آید تاخیر واقعی همان پروتکل
/// است و چون خود هسته پیکربندی را می سازد، برای xhttp و همه انتقال های دیگر
/// هم درست کار می کند.
class CorePinger {
  CorePinger(this._provisioner);

  final CoreProvisioner _provisioner;

  /// پورت های سنجش، یکی برای هر نمونه همزمان.
  static const int _firstPort = 19200;

  /// بیشتر از این تعداد سرور در یک دور سنجیده نمی شود تا زمان معقول بماند.
  static const int _maxNodes = 24;

  /// هسته همه این پروتکل ها را برای تست تاخیر می شناسد.
  static bool supports(VpnNode node) => node.protocol != NodeProtocol.clash;

  /// تاخیر هر سرور بر حسب میلی ثانیه. سرورهایی که جواب ندهند در نقشه نیستند.
  Future<Map<String, int>> measure(
    List<VpnNode> nodes, {
    required AppSettings settings,
    int concurrency = 4,
    Duration budget = const Duration(seconds: 70),
  }) async {
    final Map<String, int> delays = <String, int>{};
    final String? exe =
        await _provisioner.locateBinary(VpnController.umbrellaCliBinary);
    if (exe == null || exe.isEmpty) {
      return delays;
    }

    // اول سرورهایی که تا حالا پینگ خوبی داشته اند، بعد بقیه.
    //
    final List<VpnNode> ordered = nodes
        .where((VpnNode node) =>
            supports(node) &&
            VpnController.usable(node) &&
            node.host.isNotEmpty &&
            node.port > 0)
        .toList()
      ..sort((VpnNode a, VpnNode b) {
        if (a.hasPing != b.hasPing) {
          return a.hasPing ? -1 : 1;
        }
        return a.pingMs.compareTo(b.pingMs);
      });
    if (ordered.isEmpty) {
      return delays;
    }
    final List<VpnNode> targets = ordered.length > _maxNodes
        ? ordered.sublist(0, _maxNodes)
        : ordered;

    final Directory runDir = Directory(
      '${_provisioner.dataDir}${Platform.pathSeparator}run',
    );
    await runDir.create(recursive: true);
    final String workDir = File(exe).parent.path;

    final DateTime deadline = DateTime.now().add(budget);
    int cursor = 0;
    final int workers = concurrency < 1
        ? 1
        : (concurrency > targets.length ? targets.length : concurrency);

    Future<void> worker(int slot) async {
      final int port = _firstPort + slot;
      while (true) {
        if (DateTime.now().isAfter(deadline)) {
          return;
        }
        final int index = cursor++;
        if (index >= targets.length) {
          return;
        }
        final VpnNode node = targets[index];
        final int ms = await _measureOne(
          exe: exe,
          workDir: workDir,
          runDir: runDir,
          node: node,
          settings: settings,
          port: port,
          slot: slot,
        );
        // تاخیر کمتر از ۵ میلی ثانیه برای یک سرور بیرونی معنی ندارد.
        if (ms >= 5) {
          delays[node.id] = ms;
        }
      }
    }

    await Future.wait(<Future<void>>[
      for (int slot = 0; slot < workers; slot++) worker(slot),
    ]);
    return delays;
  }

  Future<int> _measureOne({
    required String exe,
    required String workDir,
    required Directory runDir,
    required VpnNode node,
    required AppSettings settings,
    required int port,
    required int slot,
  }) async {
    final String link = VpnController.linkFor(node);
    if (link.isEmpty) {
      return -1;
    }
    final File config = File(
      '${runDir.path}${Platform.pathSeparator}ping-$slot.txt',
    );
    Process? process;
    IOSink? sink;
    try {
      // هسته خودش پیکربندی را از لینک می سازد؛ یک لینک کافی است.
      await config.writeAsString('$link\n', flush: true);
      process = await Process.start(
        exe,
        UmbrellaCore.args(
          links: config.path,
          runDir: runDir.path,
          port: port,
          tun: false,
          systemProxy: false,
          logLevel: 'warn',
          // دی ان اس داخل تونل در سنجش، آماده شدن پورت را عقب می اندازد.
          remoteDns: VpnController.pingDns,
          directDns: VpnController.pingDns,
        ),
        workingDirectory: workDir,
        runInShell: false,
      );
      sink = File(
        '${runDir.path}${Platform.pathSeparator}ping-$slot.log',
      ).openWrite(mode: FileMode.write);
      process.stdout.listen(sink.add);
      process.stderr.listen(sink.add);

      if (!await _waitForPort(port, const Duration(milliseconds: 6000))) {
        return -1;
      }
      return await TunnelProbe.latency(
        proxyPort: port,
        timeout: const Duration(seconds: 5),
      );
    } catch (_) {
      return -1;
    } finally {
      process?.kill();
      if (sink != null) {
        await sink.flush();
        await sink.close();
      }
    }
  }

  Future<bool> _waitForPort(int port, Duration timeout) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final Socket socket = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: const Duration(milliseconds: 300),
        );
        socket.destroy();
        return true;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
    return false;
  }

  /// خلاصه ای از فایل گزارش آخرین سنجش، برای عیب یابی در صفحه گزارش ها.
  Future<String> lastError() async {
    try {
      final File log = File(
        '${_provisioner.dataDir}${Platform.pathSeparator}run'
        '${Platform.pathSeparator}ping-0.log',
      );
      if (!await log.exists()) {
        return '';
      }
      final List<String> lines = await log.readAsLines();
      final Iterable<String> errors = lines
          .where((String line) => line.contains('ERROR') || line.contains('FATAL'))
          .take(2);
      return errors.join(' | ');
    } catch (_) {
      return '';
    }
  }
}
