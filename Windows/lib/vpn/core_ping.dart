import 'dart:async';
import 'dart:io';

import '../core/app_config.dart';
import '../models/models.dart';
import 'config_builders.dart';
import 'cores.dart';
import 'tunnel_probe.dart';

/// سنجش تاخیر واقعی هر سرور با هسته سینگ باکس.
///
/// برای هر سرور یک نمونه سینگ باکس کوتاه اجرا می شود که یک پورت محلی می سازد
/// و همان درخواست کوچک از داخل تونل رد می شود؛ عددی که به دست می آید تاخیر
/// واقعی اتصال است. این روش به رابط مدیریتی کلش وابسته نیست و روی هر نسخه
/// هسته کار می کند.
class CorePinger {
  CorePinger(this._provisioner);

  final CoreProvisioner _provisioner;

  /// پورت های سنجش، یکی برای هر نمونه همزمان.
  static const int _firstPort = 19200;

  /// بیشتر از این تعداد سرور در یک دور سنجیده نمی شود تا زمان معقول بماند.
  static const int _maxNodes = 24;

  /// پروتکل هایی که سینگ باکس می تواند برایشان تست تاخیر انجام دهد.
  static bool supports(VpnNode node) {
    switch (node.protocol) {
      case NodeProtocol.vless:
      case NodeProtocol.vmess:
      case NodeProtocol.trojan:
      case NodeProtocol.shadowsocks:
      case NodeProtocol.socks:
      case NodeProtocol.hysteria2:
      case NodeProtocol.tuic:
        return true;
      case NodeProtocol.mieru:
      case NodeProtocol.clash:
      case NodeProtocol.wireguard:
      case NodeProtocol.amnezia:
        return false;
    }
  }

  /// تاخیر هر سرور بر حسب میلی ثانیه. سرورهایی که جواب ندهند در نقشه نیستند.
  Future<Map<String, int>> measure(
    List<VpnNode> nodes, {
    required AppSettings settings,
    int concurrency = 4,
    Duration budget = const Duration(seconds: 70),
  }) async {
    final Map<String, int> delays = <String, int>{};
    final String? exe = await _provisioner.locateBinary('sing-box.exe');
    if (exe == null || exe.isEmpty) {
      return delays;
    }

    // اول سرورهایی که تا حالا پینگ خوبی داشته اند، بعد بقیه.
    //
    // سرورهای xhttp از این سنجش کنار گذاشته می شوند: سینگ باکس آن انتقال را
    // نمی شناسد، پس اجرای هسته برایشان فقط بودجه سنجش را می سوزاند و در
    // پایان «تاخیر تونل برای ۰ سرور» در گزارش می آمد.
    final List<VpnNode> ordered = nodes
        .where((VpnNode node) =>
            supports(node) &&
            SingBoxConfig.supportsTransport(node) &&
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
    final File config = File(
      '${runDir.path}${Platform.pathSeparator}ping-$slot.json',
    );
    Process? process;
    IOSink? sink;
    try {
      await config.writeAsString(
        SingBoxConfig.encode(
          SingBoxConfig.buildProxy(
            node: node,
            settings: settings,
            port: port,
          ),
        ),
        flush: true,
      );
      process = await Process.start(
        exe,
        <String>['run', '-c', config.path],
        workingDirectory: workDir,
        runInShell: false,
      );
      sink = File(
        '${runDir.path}${Platform.pathSeparator}ping-$slot.log',
      ).openWrite(mode: FileMode.write);
      process.stdout.listen(sink.add);
      process.stderr.listen(sink.add);

      if (!await _waitForPort(port, const Duration(milliseconds: 2500))) {
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
