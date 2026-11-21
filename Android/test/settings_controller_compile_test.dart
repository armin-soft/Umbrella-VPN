import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/state/settings_controller.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/platform/services.dart';

void main() {
  test('shared settings and Android window service are available', () {
    expect(SettingsController, isNotNull);
    final window = WindowService(NativeBridge());
    expect(window.isHiddenToTray, isFalse);
    expect(window.closeToTray, isTrue);
  });
}
