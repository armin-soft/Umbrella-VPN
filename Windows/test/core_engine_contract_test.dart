import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/vpn/umbrella_core.dart';

/// Exercises the actual bundled DLL through our native launcher. `build` only
/// compiles configuration: it never starts a VPN, enrolls WARP or changes routes.
/// Enabled explicitly after the native build/download stage in Windows CI.
void main() {
  final String? binary = Platform.environment['UMBRELLA_CORE_SMOKE'];
  final bool enabled = Platform.isWindows && binary != null;

  Future<Map<String, dynamic>> generate(ChainSettings chain) async {
    final String executable = binary!;
    final Directory temp = await Directory.systemTemp.createTemp('umbrella-core-contract-');
    Process? process;
    try {
      final File links = File('${temp.path}/links.txt');
      final File settings = File('${temp.path}/settings.json');
      final File output = File('${temp.path}/generated.json');
      await links.writeAsString('vless://00000000-0000-4000-8000-000000000001@192.0.2.1:443?security=tls&sni=example.invalid&type=xhttp&mode=packet-up&path=%2Fupload&extra=%7B%22noGRPCHeader%22%3Atrue%7D#offline-fixture\n');
      final Map<String, dynamic> options = UmbrellaCore.settingsJson(tun: true, systemProxy: false, port: 12334,
        logFile: '${temp.path}/core.log', networkSettings: AppSettings(chain: chain, mtu: 1400,
          appRoutes: const <AppRouteRule>[
            AppRouteRule(process: 'offline-direct.exe', action: AppRouteAction.direct),
            AppRouteRule(process: r'C:\Offline\blocked.exe', action: AppRouteAction.block),
          ]));
      await settings.writeAsString(jsonEncode(options));
      process = await Process.start(executable, <String>['build', '-c', links.path, '-d', settings.path, '-o', output.path, '-D', temp.path],
        workingDirectory: File(executable).parent.path, runInShell: false);
      final Future<String> stdout = process.stdout.transform(utf8.decoder).join();
      final Future<String> stderr = process.stderr.transform(utf8.decoder).join();
      final int code = await process.exitCode.timeout(const Duration(seconds: 30));
      final String logs = '${await stdout}\n${await stderr}';
      expect(code, 0, reason: logs);
      // The console launcher can return 0 for a library-level error; an actual
      // output file and parsed structure are required, not the exit code alone.
      expect(await output.exists(), true, reason: logs);
      return jsonDecode(await output.readAsString()) as Map<String, dynamic>;
    } finally {
      process?.kill();
      if (process != null) await process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
      await temp.delete(recursive: true);
    }
  }

  for (final ChainPosition position in <ChainPosition>[ChainPosition.off, ChainPosition.extraSecurity, ChainPosition.unblocker]) {
    for (final ChainTransport transport in position == ChainPosition.off ? <ChainTransport>[ChainTransport.automatic] : ChainTransport.values) {
      test('bundled core builds ${position.name}/${transport.name} with XHTTP and Windows process rules', () async {
        final Map<String, dynamic> output = await generate(ChainSettings(position: position, transport: transport));
        final List<Map<String, dynamic>> inbounds = (output['inbounds'] as List<dynamic>).cast<Map<String, dynamic>>();
        final Map<String, dynamic> tun = inbounds.firstWhere((Map<String, dynamic> item) => item['type'] == 'tun');
        expect(tun['mtu'], 1400);
        expect(tun['strict_route'], true);
        final List<Map<String, dynamic>> mixed = inbounds.where((Map<String, dynamic> item) => item['type'] == 'mixed').toList();
        expect(mixed, isNotEmpty);
        expect(mixed.every((Map<String, dynamic> item) => <String>['127.0.0.1', '::1'].contains(item['listen'])), true);
        final List<Map<String, dynamic>> outbounds = (output['outbounds'] as List<dynamic>).cast<Map<String, dynamic>>();
        final Map<String, dynamic> vless = outbounds.firstWhere((Map<String, dynamic> item) => item['type'] == 'vless');
        expect(vless['transport']['type'], 'xhttp');
        expect(vless['transport']['mode'], 'packet-up');
        expect(vless['transport']['path'], '/upload');
        final Map<String, dynamic> route = output['route'] as Map<String, dynamic>;
        final List<Map<String, dynamic>> rules = (route['rules'] as List<dynamic>).cast<Map<String, dynamic>>();
        final Map<String, dynamic> direct = rules.firstWhere((Map<String, dynamic> item) => '${item['process_name']}'.contains('offline-direct.exe'));
        expect(direct['outbound'], startsWith('direct'));
        final Map<String, dynamic> block = rules.firstWhere((Map<String, dynamic> item) => '${item['process_path']}'.contains('blocked.exe'));
        expect(block['action'], 'reject');
        expect(rules.indexOf(direct), lessThan(rules.indexOf(block)));
        if (position == ChainPosition.off) {
          expect(route['final'], 'select');
        } else {
          final Map<String, dynamic> hop;
          if (transport == ChainTransport.psiphon) {
            hop = outbounds.firstWhere((Map<String, dynamic> item) => item['type'] == 'psiphon');
          } else {
            final List<Map<String, dynamic>> endpoints = (output['endpoints'] as List<dynamic>).cast<Map<String, dynamic>>();
            hop = endpoints.firstWhere((Map<String, dynamic> item) => item['type'] == 'warp');
            expect(hop['mode'], switch (transport) {
              ChainTransport.automatic => 'auto', ChainTransport.wireguard => 'wg',
              ChainTransport.awg => 'awg', ChainTransport.masque => 'masque', ChainTransport.psiphon => '',
            });
          }
          if (position == ChainPosition.extraSecurity) {
            expect(route['final'], hop['tag']);
            expect(hop['detour'], 'select');
          } else {
            expect(route['final'], 'select');
            expect(vless['detour'], hop['tag']);
          }
        }
      }, skip: enabled ? false : 'Set UMBRELLA_CORE_SMOKE after bundling the Windows DLLs', timeout: const Timeout(Duration(seconds: 45)));
    }
  }
}
