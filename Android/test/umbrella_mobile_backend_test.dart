import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/umbrella_core/core_messages.dart';
import 'package:umbrella_vpn/vpn/umbrella_mobile_backend.dart';

class FakeNative extends NativeBridge {
  bool allowed = false;
  bool stopped = false;
  @override
  Future<bool> requestVpnPermission() async => allowed;
  @override
  Future<Map<String, String>> coreDirectories() async => {};
  @override
  Future<bool> stopService() async => stopped;
}

void main() {
  test('only a successful parsed JSON profile can reach Start', () {
    expect(validatedParsedProfile(ParseResponse(content: '{"outbounds":[]}')), '{"outbounds":[]}');
    expect(() => validatedParsedProfile(ParseResponse(responseCode: 1, content: '{}')), throwsStateError);
    expect(() => validatedParsedProfile(ParseResponse()), throwsStateError);
    expect(() => validatedParsedProfile(ParseResponse(content: 'vless://example')), throwsFormatException);
    expect(() => validatedParsedProfile(ParseResponse(content: '[]')), throwsFormatException);
  });
  test('never reports permission without Android consent', () async {
    final native = FakeNative();
    final backend = UmbrellaMobileBackend(
      native: native, settingsJson: '{"enable-tun":true}', configContent: '{}',
      verifyTunTraffic: () async => false,
    );
    expect(await backend.requestPermission(), isFalse);
    await expectLater(backend.startService(), throwsStateError);
    // No service was attempted when private directories were unavailable.
    await backend.stopService();
  });

  test('rejects proxy-only and desktop system proxy settings', () async {
    for (final settings in ['{}', '{"enable-tun":true,"set-system-proxy":true}']) {
      final backend = UmbrellaMobileBackend(
        native: FakeNative(), settingsJson: settings, configContent: '{}',
        verifyTunTraffic: () async => false,
      );
      await expectLater(backend.startService(), throwsFormatException);
      await expectLater(backend.configureAndStart(), throwsFormatException);
    }
  });

  test('traffic verification is supplied explicitly and cannot default to success', () async {
    var calls = 0;
    final backend = UmbrellaMobileBackend(
      native: FakeNative(), settingsJson: '{"enable-tun":true}', configContent: '{}',
      verifyTunTraffic: () async { calls++; return false; },
    );
    expect(await backend.verifyTraffic(), isFalse);
    expect(calls, 1);
    await expectLater(backend.configureAndStart(), throwsStateError);
  });
}
