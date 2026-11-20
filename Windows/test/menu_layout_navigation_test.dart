import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbrella_vpn/core/storage.dart';
import 'package:umbrella_vpn/core/theme.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/platform/services.dart';
import 'package:umbrella_vpn/state/auth_controller.dart';
import 'package:umbrella_vpn/state/power_controller.dart';
import 'package:umbrella_vpn/state/settings_controller.dart';
import 'package:umbrella_vpn/state/toast_controller.dart';
import 'package:umbrella_vpn/ui/pages/settings_page.dart';
import 'package:umbrella_vpn/ui/widgets/common.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

class _Native implements NativeBridge {
  @override
  Future<bool> isElevated() async => false;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
class _Sound implements SoundService {
  @override
  bool enabled = true;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
class _Window implements WindowService {
  @override
  bool closeToTray = true;
  @override
  bool notificationsEnabled = true;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
class _Vpn extends ChangeNotifier implements VpnController {
  @override
  VpnStatus get status => VpnStatus.disconnected;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
class _Auth extends ChangeNotifier implements AuthController {
  @override
  bool get signedIn => false;
  @override
  FilterSettings get filter => FilterSettings.empty;
  @override
  bool get savingFilter => false;
  @override
  String get error => '';
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.instance.init();
  });

  for (final brightness in Brightness.values) {
    testWidgets('every settings submenu has a reachable pinned back control ($brightness)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(950, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final settings = SettingsController(native: _Native(), sound: _Sound(), window: _Window());
      final power = PowerController(readStatus: () async => const BatteryPowerState(
        isLaptop: true, hasBattery: true, onBattery: true, energySaver: false));
      await power.refresh();
      final vpn = _Vpn();
      final auth = _Auth();
      final toasts = ToastController();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<PowerController>.value(value: power),
          ChangeNotifierProvider<VpnController>.value(value: vpn),
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<ToastController>.value(value: toasts),
        ],
        child: MaterialApp(
          theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
          home: const Directionality(textDirection: TextDirection.rtl,
            child: Scaffold(body: SettingsPage())),
        ),
      ));
      await tester.pump();
      for (final category in SettingsCategory.values) {
        final menu = find.byKey(ValueKey<String>('settings-category-${category.name}'));
        await tester.ensureVisible(menu);
        await tester.pump();
        await tester.tap(menu);
        await tester.pump();
        final back = find.byKey(const ValueKey<String>('settings-back-button'));
        expect(back, findsOneWidget, reason: category.name);
        final top = tester.getTopLeft(back).dy;
        final detail = find.byKey(ValueKey<String>('settings-detail-${category.name}'));
        expect(detail, findsOneWidget);
        await tester.drag(detail, const Offset(0, -700));
        await tester.pump();
        expect(tester.getTopLeft(back).dy, top, reason: category.name);
        expect(tester.takeException(), isNull, reason: category.name);
        await tester.tap(back);
        await tester.pump();
        expect(find.byKey(const PageStorageKey<String>('settings-root-scroll')), findsOneWidget);
      }
      final menu = find.byKey(const ValueKey<String>('settings-category-general'));
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(const PageStorageKey<String>('settings-root-scroll')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
      power.dispose();
      vpn.dispose();
      auth.dispose();
      toasts.dispose();
    });
  }

  for (final width in <double>[360, 620, 950]) {
    testWidgets('shared page header adapts at width $width and large text', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 700), textScaler: const TextScaler.linear(1.3)),
          child: Directionality(textDirection: TextDirection.rtl,
            child: Scaffold(body: Padding(
              padding: AppMetrics.pagePadding,
              child: PageHeader(title: 'تنظیمات شبکه',
                subtitle: 'تنظیمات شبکه و ورودی برای دستگاه',
                icon: Icons.settings_rounded,
                actions: [OutlinedButton.icon(onPressed: () {},
                  icon: const Icon(Icons.arrow_back_rounded), label: const Text('بازگشت به تنظیمات'))]),
            )),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(OutlinedButton)).height, greaterThanOrEqualTo(AppMetrics.controlHeightSmall));
    });
  }
}
