import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/hiddifycore/hcore_messages.dart';

void main() {
  test('empty request has no wire fields', () {
    expect(HEmpty.create().writeToBuffer(), isEmpty);
  });

  test('start request uses the core proto field numbers', () {
    final bytes = StartRequest(configPath: 'a', enableRawConfig: true)
        .writeToBuffer();
    expect(bytes, [0x0a, 0x01, 0x61, 0x30, 0x01]);
    final decoded = StartRequest.fromBuffer(bytes);
    expect(decoded.configPath, 'a');
    expect(decoded.enableRawConfig, isTrue);
  });

  test('parse response decodes enum and content from wire', () {
    final response = ParseResponse.fromBuffer([0x08, 0x01, 0x12, 0x02, 0x6f, 0x6b]);
    expect(response.responseCode, ResponseCode.failed);
    expect(response.content, 'ok');
  });

  test('system info preserves 64-bit counters', () {
    final value = Int64.parseInt('4294967296');
    final info = SystemInfo(downlinkTotal: value, trafficAvailable: true);
    final decoded = SystemInfo.fromBuffer(info.writeToBuffer());
    expect(decoded.trafficAvailable, isTrue);
    expect(decoded.downlinkTotal, value);
  });
}
