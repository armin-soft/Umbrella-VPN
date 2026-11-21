import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/platform/native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ir.umbrella.app/android');
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
