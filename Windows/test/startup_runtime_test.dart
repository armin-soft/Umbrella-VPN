import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/vpn/runtime_config.dart';
import 'package:umbrella_vpn/vpn/startup_verification.dart';

void main() {
  test('instant probe failures retry the same session until a valid result', () async {
    int attempts = 0;
    expect(await StartupVerification.wait(
      probe: (_) async => ++attempts == 4, cancelled: () => false,
      alive: () async => true, interval: Duration.zero,
    ), true);
    expect(attempts, 4);
  });
  test('cancel during a pending probe returns without retry or late success', () async {
    bool cancelled = false;
    int attempts = 0;
    final Completer<bool> pending = Completer<bool>();
    final Future<bool> result = StartupVerification.wait(
      probe: (_) { attempts++; cancelled = true; return pending.future; },
      cancelled: () => cancelled, alive: () async => true,
    );
    expect(await result.timeout(const Duration(seconds: 1)), false);
    pending.complete(true);
    expect(attempts, 1);
  });
  test('exited core and expired deadline do not become connected', () async {
    int attempts = 0;
    expect(await StartupVerification.wait(probe: (_) async { attempts++; return true; },
      cancelled: () => false, alive: () async => false), false);
    expect(attempts, 0);
    expect(await StartupVerification.wait(probe: (_) async => false,
      cancelled: () => false, alive: () async => true,
      interval: const Duration(milliseconds: 1), budget: const Duration(milliseconds: 15)), false);
  });

  Map<String, dynamic> fixture({String upload = '192.0.2.1', String detour = '', String downloadDetour = ''}) => <String, dynamic>{
    'log': <String, dynamic>{'output': 'same-log.txt'},
    'experimental': <String, dynamic>{
      'monitoring': <String, dynamic>{'interval': '10m'},
      'cache_file': <String, dynamic>{'enabled': true},
      'clash_api': <String, dynamic>{'external_controller': '127.0.0.1:16756', 'secret': 'test', 'external_ui': 'webui'},
    },
    'outbounds': <dynamic>[
      <String, dynamic>{'type': 'vless', 'tag': 'profile', 'server': upload, 'detour': detour,
        'bind_interface': 'Ethernet', 'transport': <String, dynamic>{'type': 'xhttp',
          'download': <String, dynamic>{'server': 'DoWnLoAd.invalid', 'server_port': 443,
            'detour': downloadDetour, 'host': 'virtual.invalid', 'path': '/unchanged',
            'tls': <String, dynamic>{'enabled': true, 'server_name': 'certificate.invalid'},
          },
        },
      },
      <String, dynamic>{'type': 'socks', 'tag': 'chain-hop', 'server': '127.0.0.1'},
    ],
  };
  test('runtime activates lazy selection without deleting any authorized node or chain hop', () {
    final Map<String, dynamic> config = fixture();
    for (int i = 0; i < 1100; i++) {
      (config['outbounds'] as List<dynamic>).add(<String, dynamic>{'type': 'vmess', 'tag': 'node-$i'});
    }
    RuntimeConfig.finalize(config, profileTags: <String>{'profile', for (int i = 0; i < 1100; i++) 'node-$i'});
    final List<dynamic> outbounds = config['outbounds'] as List<dynamic>;
    expect(outbounds.length, 1103); // all nodes + hop + resolving download dialer
    expect(outbounds.where((dynamic out) => out['lazy'] == true).length, 1101);
    expect(outbounds.firstWhere((dynamic out) => out['tag'] == 'chain-hop')['lazy'], isNull);
    expect(config['experimental']['monitoring']['keep_top'], <String, dynamic>{'count': 8, 'batch': 4, 'quick': true});
    expect(config['experimental']['cache_file']['enabled'], true);
    expect(config['experimental']['clash_api']['external_ui'], isNull);
    expect(config['log']['output'], isNull);
  });
  test('IP upload plus domain download gets a resolving dialer, preserving wire identities', () {
    final Map<String, dynamic> config = fixture();
    RuntimeConfig.finalize(config, profileTags: <String>{'profile'});
    final dynamic download = (config['outbounds'] as List<dynamic>).firstWhere((dynamic out) => out['tag'] == 'profile')['transport']['download'];
    final dynamic resolver = (config['outbounds'] as List<dynamic>).first;
    expect(download['detour'], resolver['tag']);
    expect(resolver['type'], 'direct');
    expect(resolver['bind_interface'], 'Ethernet');
    expect(download['server'], 'DoWnLoAd.invalid');
    expect(download['host'], 'virtual.invalid');
    expect(download['path'], '/unchanged');
    expect(download['tls']['server_name'], 'certificate.invalid');
  });
  test('never bypass explicit download detour or unblocker; domain upload already resolves', () {
    for (final Map<String, dynamic> config in <Map<String, dynamic>>[
      fixture(detour: 'chain-hop'), fixture(downloadDetour: 'custom'), fixture(upload: 'upload.invalid'),
    ]) {
      RuntimeConfig.finalize(config, profileTags: <String>{'profile'});
      expect((config['outbounds'] as List<dynamic>).length, 2);
    }
  });
  test('cancellation stays latched and automatic mode cannot restart a pool per node', () {
    final String source = File('lib/vpn/vpn_controller.dart').readAsStringSync();
    final String finish = source.split('void _finishCancel()').last.split('Future<ConnectOutcome> connect').first;
    expect(finish, contains('if (!_connectInFlight) _cancelRequested = false;'));
    expect(source, contains('? _candidates(node, selection.reason) : <VpnNode>[node]'));
    expect(source, contains('await process.exitCode.timeout'));
    expect(source, contains('if (pending != null) return pending;'));
    expect(source, contains('generation != _cancelGeneration'));
    expect(source, contains('if (_connectInFlight) { await cancel(); return; }'));
  });
}
