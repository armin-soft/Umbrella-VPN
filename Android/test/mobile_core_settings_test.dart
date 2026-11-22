import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/vpn/mobile_core_settings.dart';
import 'package:umbrella_vpn/vpn/umbrella_mobile_backend.dart';

void main() {
  test('each mobile session uses a secret control API to enable multi-URL monitoring', () {
    final base = <String, dynamic>{
      'enable-tun': true, 'enable-clash-api': false, 'enable-mixed-port': true,
      'web-secret': 'public-desktop-secret', 'log-level': 'debug',
      'log-level-until': 'x', 'log-level-after': 'trace',
      'connection-test-urls': <String>['http://one/', 'https://two/'],
    };
    final one = mobileCoreSettings(base);
    final two = mobileCoreSettings(base);
    expect(one['enable-clash-api'], isTrue);
    expect(one['enable-mixed-port'], isFalse);
    expect(one['connection-test-urls'], hasLength(2));
    expect(one['log-level'], 'warn');
    expect(one.containsKey('log-level-until'), isFalse);
    expect(one.containsKey('log-level-after'), isFalse);
    final secret = one['web-secret'] as String;
    expect(base64Url.decode(base64Url.normalize(secret)), hasLength(32));
    expect(secret, isNot('public-desktop-secret'));
    expect(secret, isNot(two['web-secret']));
    expect(base['enable-clash-api'], isFalse);
  });

  test('Android tries the upstream Apple endpoint first without losing fallbacks', () {
    const apple = 'http://captive.apple.com/hotspot-detect.html';
    final base = <String, dynamic>{
      'connection-test-url': 'http://first/',
      'connection-test-urls': <String>['http://first/', apple, 'http://third/'],
    };
    final mobile = mobileCoreSettings(base);
    expect(mobile['connection-test-url'], apple);
    expect(mobile['connection-test-urls'], [apple, 'http://first/', 'http://third/']);
    expect(base['connection-test-urls'], ['http://first/', apple, 'http://third/']);
  });

  test('runtime monitor must use the configured URLs and a private listener', () {
    final settings = mobileCoreSettings(<String, dynamic>{
      'clash-api-port': 16756,
      'connection-test-urls': <String>['http://one/', 'https://two/'],
    });
    final runtime = <String, dynamic>{'experimental': <String, dynamic>{
      'clash_api': <String, dynamic>{'secret': settings['web-secret'], 'external_controller': '127.0.0.1:16756'},
      'monitoring': <String, dynamic>{'urls': settings['connection-test-urls']},
    }};
    bool valid() => mobileRuntimeMonitoringMatches(jsonEncode(runtime), jsonEncode(settings));
    expect(valid(), isTrue);
    final api = (runtime['experimental'] as Map)['clash_api'] as Map;
    api['external_controller'] = '0.0.0.0:16756';
    expect(valid(), isFalse);
    api['external_controller'] = '127.0.0.1:16756';
    api['secret'] = 'wrong';
    expect(valid(), isFalse);
    api['secret'] = settings['web-secret'];
    ((runtime['experimental'] as Map)['monitoring'] as Map)['urls'] = ['https://www.gstatic.com/generate_204'];
    expect(valid(), isFalse);
    expect(mobileRuntimeMonitoringMatches('not json', jsonEncode(settings)), isFalse);
  });

  test('only fixed categories, never raw secret-bearing engine logs', () {
    expect(classifyMonitorFailure('MONITORING result private-host: failed: lookup example: no such host'), 'DNS');
    expect(classifyMonitorFailure('MONITORING result private-host: failed: x509 certificate invalid'), 'CERTIFICATE');
    expect(classifyMonitorFailure('MONITORING result private-host: failed: tls handshake failed'), 'TLS');
    expect(classifyMonitorFailure('MONITORING result private-host: failed: context deadline exceeded'), 'TIMEOUT');
    expect(classifyMonitorFailure('MONITORING result private-host: failed: connection refused'), 'REFUSED');
    expect(classifyMonitorFailure('unrelated log with tls secret'), isNull);
    expect(classifyMonitorFailure('outbound private URL test did not return in 5s'), 'TIMEOUT');
    expect(classifyMonitorFailure('MONITORING result private-host: failed: private-secret'), 'OTHER');
  });
}
