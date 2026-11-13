import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/models.dart';
import 'config_builders.dart';
import 'cores.dart';

/// سنجش تاخیر واقعی هر سرور با هسته سینگ باکس.
///
/// همان روشی که کلاینت هیدیفای برای «تاخیر» استفاده می کند: هسته یک
/// outbound برای هر سرور می سازد و آدرس تولید ۲۰۴ را از داخل همان تونل
/// می گیرد. عددی که به دست می آید تاخیر واقعی اتصال است، نه فقط پینگ
/// آی سی ام پی یا باز شدن پورت سرور.
class CorePinger {
  CorePinger(this._provisioner);

  final CoreProvisioner _provisioner;

  static const int _apiPort = 19090;
  static const int _listenPort = 19191;
  static const String _testUrl = 'http://cp.cloudflare.com/generate_204';

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
    int concurrency = 8,
    Duration perNodeTimeout = const Duration(seconds: 5),
  }) async {
    final Map<String, int> delays = <String, int>{};
    final List<VpnNode> targets = <VpnNode>[];
    final Map<String, String> tags = <String, String>{};
    for (final VpnNode node in nodes) {
      if (!supports(node) || node.host.isEmpty || node.port <= 0) {
        continue;
      }
      final String tag = 'node${targets.length}';
      tags[node.id] = tag;
      targets.add(node);
    }
    if (targets.isEmpty) {
      return delays;
    }

    final String? exe = await _provisioner.locateBinary('sing-box.exe');
    if (exe == null || exe.isEmpty) {
      return delays;
    }

    final Directory runDir = Directory(
      '${_provisioner.dataDir}${Platform.pathSeparator}run',
    );
    await runDir.create(recursive: true);
    final File config = File(
      '${runDir.path}${Platform.pathSeparator}singbox-ping.json',
    );

    final List<Map<String, dynamic>> outbounds = <Map<String, dynamic>>[];
    for (final VpnNode node in targets) {
      final Map<String, dynamic> outbound = SingBoxConfig.outboundFor(
        node,
        settings,
      );
      outbound['tag'] = tags[node.id];
      outbounds.add(outbound);
    }
    outbounds.add(<String, dynamic>{'type': 'direct', 'tag': 'direct'});

    await config.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'log': <String, dynamic>{'level': 'warn', 'timestamp': false},
        'inbounds': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'mixed',
            'tag': 'mixed-in',
            'listen': '127.0.0.1',
            'listen_port': _listenPort,
          },
        ],
        'outbounds': outbounds,
        'route': <String, dynamic>{
          'rules': <Map<String, dynamic>>[
            <String, dynamic>{'action': 'sniff'},
          ],
          'final': 'direct',
          'auto_detect_interface': true,
        },
        'experimental': <String, dynamic>{
          'clash_api': <String, dynamic>{
            'external_controller': '127.0.0.1:$_apiPort',
            'default_mode': 'global',
          },
        },
      }),
      flush: true,
    );

    Process process;
    try {
      process = await Process.start(
        exe,
        <String>['run', '-c', config.path],
        workingDirectory: File(exe).parent.path,
        runInShell: false,
      );
    } on ProcessException {
      return delays;
    }
    final IOSink sink = File(
      '${runDir.path}${Platform.pathSeparator}singbox-ping.log',
    ).openWrite(mode: FileMode.write);
    process.stdout.listen(sink.add);
    process.stderr.listen(sink.add);

    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2);
    try {
      if (!await _waitForApi(client)) {
        return delays;
      }
      int cursor = 0;
      Future<void> worker() async {
        while (true) {
          final int index = cursor++;
          if (index >= targets.length) {
            return;
          }
          final VpnNode node = targets[index];
          final int delay = await _delay(
            client,
            tags[node.id]!,
            perNodeTimeout,
          );
          // تاخیر کمتر از ۵ میلی ثانیه برای یک سرور بیرونی معنی ندارد؛
          // چنین عددی نشانه خطای سنجش است، نه سرور سریع.
          if (delay >= 5) {
            delays[node.id] = delay;
          }
        }
      }

      final int workers = concurrency < 1
          ? 1
          : (concurrency > targets.length ? targets.length : concurrency);
      await Future.wait(<Future<void>>[
        for (int i = 0; i < workers; i++) worker(),
      ]);
    } finally {
      client.close(force: true);
      process.kill();
      await sink.flush();
      await sink.close();
    }
    return delays;
  }

  Future<bool> _waitForApi(HttpClient client) async {
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final HttpClientRequest request = await client
            .getUrl(Uri.parse('http://127.0.0.1:$_apiPort/version'))
            .timeout(const Duration(milliseconds: 800));
        final HttpClientResponse response =
            await request.close().timeout(const Duration(milliseconds: 800));
        await response.drain<void>();
        if (response.statusCode == 200) {
          return true;
        }
      } catch (_) {
        // هسته هنوز بالا نیامده؛ دوباره امتحان می شود.
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  Future<int> _delay(HttpClient client, String tag, Duration timeout) async {
    final int timeoutMs = timeout.inMilliseconds;
    final Uri uri = Uri.parse(
      'http://127.0.0.1:$_apiPort/proxies/${Uri.encodeComponent(tag)}/delay'
      '?url=${Uri.encodeQueryComponent(_testUrl)}&timeout=$timeoutMs',
    );
    try {
      final HttpClientRequest request =
          await client.getUrl(uri).timeout(timeout);
      final HttpClientResponse response =
          await request.close().timeout(timeout);
      final String body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout, onTimeout: () => '');
      if (response.statusCode != 200) {
        return -1;
      }
      final Object? json = jsonDecode(body);
      if (json is Map<String, dynamic>) {
        final Object? delay = json['delay'];
        if (delay is int) {
          return delay;
        }
        if (delay is num) {
          return delay.round();
        }
      }
      return -1;
    } catch (_) {
      return -1;
    }
  }
}
