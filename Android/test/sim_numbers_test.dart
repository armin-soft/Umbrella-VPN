import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/platform/sim_numbers.dart';
import 'package:umbrella_vpn/core/utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ir.umbrella.app/android');
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  test('returns all active slots and preserves unavailable numbers', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readSimNumbers');
      return {'status': 'ok', 'sims': [
        {'slot': 1, 'number': '+989123456789'}, {'slot': 2, 'number': ''},
      ]};
    });
    final result = await SimNumbers().read();
    expect(result.status, 'ok');
    expect(result.sims.map((sim) => sim.slot), [1, 2]);
    expect(IranPhone.normalize(result.sims.first.number), '09123456789');
    expect(IranPhone.isValid(result.sims.last.number), isFalse);
  });

  test('permission denial and missing plugin preserve manual entry', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => {'status': 'denied', 'sims': []});
    expect((await SimNumbers().read()).status, 'denied');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    expect((await SimNumbers().read()).status, 'unavailable');
  });
}
