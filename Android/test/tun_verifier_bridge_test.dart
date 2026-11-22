import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/platform/native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ir.umbrella.app/android');
  test('app is not unconditionally excluded from its own VPN and core sockets are protected', () {
    final tun = File('android/app/src/main/kotlin/ir/umbrella/app/UmbrellaTun.kt').readAsStringSync();
    final platform = File('android/app/src/main/kotlin/ir/umbrella/app/UmbrellaPlatform.kt').readAsStringSync();
    final verifier = File('android/app/src/main/kotlin/ir/umbrella/app/UmbrellaTunVerifier.kt').readAsStringSync();
    expect(tun, isNot(contains('addApp(builder, service.packageName, allowed = false)')));
    expect(tun, contains('check(service.protect(fd))'));
    expect(platform, contains('autoDetectInterfaceControl(fd: Int) = tun.protectSocket(fd)'));
    expect(verifier, contains('caps.ownerUid == Process.myUid()'));
    expect(verifier, contains('network.socketFactory.createSocket()'));
    expect(verifier, contains('DnsResolver.getInstance().query('));
    expect(verifier, contains('params.endpointIdentificationAlgorithm = "HTTPS"'));
    expect(verifier, contains('signal.cancel()'));
  });
  test('traffic verification does not default to connected', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'verifyTunTraffic');
      return false;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    expect(await NativeBridge().verifyTunTraffic(), isFalse);
  });
}
