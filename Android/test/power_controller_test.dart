import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/state/power_controller.dart';

void main() {
  test('Android power state does not activate desktop laptop policy', () async {
    final native = NativeBridge();
    final controller = PowerController(readStatus: native.powerStatus);
    await controller.refresh();
    expect(controller.active, isFalse);
    expect(controller.isLaptop, isFalse);
    controller.dispose();
  });
}
