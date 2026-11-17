import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:umbrella_vpn/core/storage.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/platform/services.dart';
import 'package:umbrella_vpn/state/settings_controller.dart';

class _Native implements NativeBridge {
  @override
  Future<bool> isElevated() async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Sound implements SoundService {
  @override
  bool enabled = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Window implements WindowService {
  @override
  bool closeToTray = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.instance.init();
  });
  SettingsController create() => SettingsController(native: _Native(), sound: _Sound(), window: _Window());
  for (final Brightness brightness in Brightness.values) {
    test('toggle from system $brightness switches the actual visible appearance', () async {
      binding.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(binding.platformDispatcher.clearPlatformBrightnessTestValue);
      final SettingsController controller = create();
      addTearDown(controller.dispose);
      await controller.setTheme(ThemePreference.system);
      await controller.toggleTheme();
      expect(controller.themeMode, brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
    });
  }
  test('rapid changes notify immediately and persist last choice on reload', () async {
    final SettingsController controller = create();
    addTearDown(controller.dispose);
    int notifications = 0;
    controller.addListener(() => notifications++);
    final Future<void> first = controller.setTheme(ThemePreference.light);
    expect(controller.themeMode, ThemeMode.light);
    expect(notifications, 1);
    final Future<void> second = controller.setTheme(ThemePreference.dark);
    final Future<void> third = controller.setTheme(ThemePreference.system);
    expect(controller.themeMode, ThemeMode.system);
    await Future.wait(<Future<void>>[first, second, third]);
    final SettingsController reloaded = create();
    addTearDown(reloaded.dispose);
    await reloaded.load();
    expect(reloaded.themeMode, ThemeMode.system);
  });
}
