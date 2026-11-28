import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbrella_vpn/core/storage.dart';
import 'package:umbrella_vpn/core/theme.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/platform/services.dart';
import 'package:umbrella_vpn/state/power_controller.dart';
import 'package:umbrella_vpn/state/settings_controller.dart';
import 'package:umbrella_vpn/state/toast_controller.dart';
import 'package:umbrella_vpn/ui/pages/settings_page.dart';
import 'package:umbrella_vpn/ui/widgets/common.dart';
import 'package:umbrella_vpn/vpn/https_ad_filter_proxy.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

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
  bool notificationsEnabled = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Vpn extends ChangeNotifier implements VpnController {
  @override
  bool get httpsCaTrusted => false;
  @override
  bool get httpsCaStatusChecked => true;
  @override
  String get httpsCaCertPath => '';
  @override
  HttpsFilterStats get httpsFilterStats => const HttpsFilterStats();
  @override
  bool get isHttpsFilterProxyActive => false;
  @override
  Future<bool> refreshHttpsCaStatus({bool notify = true}) async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.instance.init();
  });

  for (final laptop in <bool?>[true, false, null]) {
    testWidgets('battery menu visibility for laptop=$laptop', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final settings = SettingsController(native: _Native(), sound: _Sound(), window: _Window());
      final power = PowerController(readStatus: () async => BatteryPowerState(
        hasBattery: true, onBattery: true, energySaver: false, isLaptop: laptop));
      final vpn = _Vpn();
      final toasts = ToastController();
      await power.refresh();
      settings.addListener(() => power.setEnabled(settings.settings.batteryOptimization));
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<PowerController>.value(value: power),
          ChangeNotifierProvider<VpnController>.value(value: vpn),
          ChangeNotifierProvider<ToastController>.value(value: toasts),
        ],
        child: MaterialApp(theme: AppTheme.dark(), home: const Directionality(
          textDirection: TextDirection.rtl, child: Scaffold(body: SettingsPage()))),
      ));
      await tester.pump();
      final menu = find.byKey(const ValueKey<String>('settings-category-battery'));
      expect(menu, laptop == true ? findsOneWidget : findsNothing);
      if (laptop == true) {
        await tester.ensureVisible(menu);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        final toggle = find.byKey(const ValueKey<String>('battery-optimization-toggle'));
        expect(toggle, findsOneWidget);
        expect(tester.widget<ToggleRow>(toggle).value, true);
        await tester.tap(find.descendant(of: toggle, matching: find.byType(Switch)));
        await tester.pumpAndSettle();
        expect(settings.settings.batteryOptimization, false);
        expect(power.active, false);
        final reloaded = SettingsController(native: _Native(), sound: _Sound(), window: _Window());
        await reloaded.load();
        expect(reloaded.settings.batteryOptimization, false);
        reloaded.dispose();
      }
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
      power.dispose();
      vpn.dispose();
      toasts.dispose();
      // Avoid leaking the persisted disabled value into another test.
      await LocalStore.instance.remove(StoreKeys.settings);
    });
  }
}
