import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/platform/sms_consent.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ir.umbrella.app/sms_consent');
  test('accepts only six-digit codes and unregisters on dispose', () async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final outgoing = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async { outgoing.add(call.method); return true; });
    final consent = SmsConsent();
    final received = <String>[];
    consent.listen(received.add);
    await consent.start();
    Future<void> deliver(Object value) async {
      await messenger.handlePlatformMessage(channel.name,
          channel.codec.encodeMethodCall(MethodCall('smsCode', value)), (_) {});
    }
    await deliver('123456');
    await deliver('1234567');
    await deliver('password');
    expect(received, ['123456']);
    consent.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(outgoing, containsAll(['start', 'stop']));
    messenger.setMockMethodCallHandler(channel, null);
  });
}
