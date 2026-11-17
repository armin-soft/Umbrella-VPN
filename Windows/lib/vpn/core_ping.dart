import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/app_config.dart';
import '../models/models.dart';
import 'cores.dart';
import 'umbrella_core.dart';
import 'link_preparation.dart';
import 'vpn_controller.dart';
import 'tunnel_probe.dart';
import 'verified_probe.dart';

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

  /// نمونه های در حال اجرا.
  ///
  /// `Future.timeout` آینده را رها می کند ولی کار را متوقف نمی کند؛ پیش از
  /// این هر سنجش، هسته ای زنده می گذاشت که پورت ثابت ۱۷۰۷۸ را می گرفت و
  /// اتصال کاربر را با «پورت در اختیار برنامه دیگری است» می کشت (گزارش ۱٫۰۷).
  final List<Process> _running = <Process>[];

  /// آیا سنجش جاری باید متوقف شود؟
  bool _stopped = false;

  /// آیا نمونه ای در حال اجراست؟
  bool get busy => _running.isNotEmpty;

  /// بستن همه نمونه های در حال اجرا؛ سنجش جاری هم ادامه نمی دهد.
  Future<void> stopAll() async {
    _stopped = true;
    final List<Process> running = List<Process>.of(_running);
    _running.clear();
    for (final Process process in running) {
      try {
        process.kill();
      } on Exception {
        // فرایند از قبل بسته شده است.
      }
    }
  }

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
    // یک نمونه در هر لحظه. هسته دو پورت ثابت (۱۷۰۷۸ و ۱۶۷۵۶) می خواهد؛ با
    // چند نمونه همزمان، هر کدام پورت دیگری را می گرفت و یا نمونه دیگری را
    // می کشت و سنجش بی نتیجه می ماند («۰ سرور» در گزارش ۱٫۰٫۶).
    int concurrency = 1,
    Duration budget = const Duration(seconds: 70),
    int maxNodes = _maxNodes,
  }) async {
    final Map<String, int> delays = <String, int>{};
    _stopped = false;
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
    final int limit = maxNodes < 1 ? _maxNodes : maxNodes;
    final List<VpnNode> targets =
        ordered.length > limit ? ordered.sublist(0, limit) : ordered;

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
        if (_stopped || DateTime.now().isAfter(deadline)) {
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
    // فایل تنظیمات کامل، کنار همان پوشه ای که هسته در آن اجرا می شود.
    // هسته `log-file` را نسبت به همین پوشه می نویسد و پیش از هر کاری آن را
    // باز می کند؛ اگر پوشه اش نباشد یا قابل نوشتن نباشد، اجرا بی هیچ پیامی
    // می میرد و سنجش خالی می ماند.
    final File settingsFile = File(
      '$workDir${Platform.pathSeparator}${AppConfig.coreSettingsFile}',
    );
    final File log = File(
      '$workDir${Platform.pathSeparator}data${Platform.pathSeparator}box.log',
    );
    Process? process;
    IOSink? sink;
    try {
      // هسته خودش پیکربندی را از لینک می سازد؛ یک لینک کافی است.
      final PreparedLinks prepared = await LinkPreparation.prepare(
        <String>[link], resolveEndpoints: false,
      );
      if (_stopped) return -1;
      await config.writeAsString('${prepared.links.single}\n', flush: true);
      await log.parent.create(recursive: true);
      await settingsFile.writeAsString(
        jsonEncode(
          UmbrellaCore.settingsJson(
            tun: false,
            systemProxy: false,
            port: port,
            networkSettings: settings,
            logFile: log.path,
            // Use the same resolver and IPv6 policy as an actual connection.
          ),
        ),
        flush: true,
      );
      // هر نمونه سنجش هم پورت های ثابت هسته (۱۷۰۷۸ و ۱۶۷۵۶) را می خواهد؛
      // اگر نمونه قبلی هنوز زنده باشد، این یکی با «already in use» می میرد و
      // هیچ عددی به دست نمی آید. پس پیش از هر نمونه، پورت ها آزاد می شوند.
      await UmbrellaCore.releasePorts();
      if (_stopped) {
        return -1;
      }
      process = await Process.start(
        exe,
        UmbrellaCore.args(
          links: config.path,
          runDir: runDir.path,
          port: port,
          tun: false,
          systemProxy: false,
          logLevel: CoreLogLevel.normalize(settings.logLevel),
          settingsPath: settingsFile.path,
          remoteDns: VpnController.pingDns,
          directDns: VpnController.pingDns,
        ),
        workingDirectory: workDir,
        runInShell: false,
      );
      _running.add(process);
      sink = File(
        '${runDir.path}${Platform.pathSeparator}ping-$slot.log',
      ).openWrite(mode: FileMode.write);
      process.stdout.listen(sink.add);
      process.stderr.listen(sink.add);

      if (!await _waitForPort(port, const Duration(milliseconds: 6000))) {
        return -1;
      }
      if (!await VerifiedProbe.check(proxyPort: port,
          timeout: Duration(seconds: settings.chain.enabled ? 30 : 6)) || _stopped) return -1;
      return await TunnelProbe.latency(
        proxyPort: port,
        timeout: const Duration(seconds: 5),
      );
    } catch (_) {
      return -1;
    } finally {
      process?.kill();
      if (process != null) {
        _running.remove(process);
      }
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
