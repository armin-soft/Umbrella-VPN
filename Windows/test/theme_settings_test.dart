import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:umbrella_vpn/core/theme.dart';
import 'package:umbrella_vpn/ui/widgets/network_settings.dart';
import 'package:umbrella_vpn/ui/widgets/advanced_network_settings.dart';

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
  test('network setters persist without changing account/source fields', () async {
    final SettingsController controller = create();
    addTearDown(controller.dispose);
    await controller.update(const AppSettings(gatewayBase: 'https://account.example', phone: '09120000000'));
    await controller.setMtu(1400);
    await controller.setTunStack(TunStack.system);
    await controller.setStrictRoute(false);
    await controller.setBlockIpv6(false);
    await controller.setRemoteDns('https://9.9.9.9/dns-query');
    await controller.setDirectDns('8.8.8.8');
    await expectLater(controller.setRemoteDns('https://unknown.invalid'), throwsArgumentError);
    final SettingsController reloaded = create();
    addTearDown(reloaded.dispose);
    await reloaded.load();
    expect(reloaded.settings.mtu, 1400);
    expect(reloaded.settings.tunStack, TunStack.system);
    expect(reloaded.settings.strictRoute, false);
    expect(reloaded.settings.blockIpv6, false);
    expect(reloaded.settings.remoteDns, 'https://9.9.9.9/dns-query');
    expect(reloaded.settings.directDns, '8.8.8.8');
    expect(reloaded.settings.gatewayBase, 'https://account.example');
    expect(reloaded.settings.phone, '09120000000');
  });
  for (final Brightness brightness in Brightness.values) {
    testWidgets('network controls work in RTL $brightness', (WidgetTester tester) async {
      final SettingsController controller = create();
      addTearDown(controller.dispose);
      await tester.pumpWidget(ChangeNotifierProvider<SettingsController>.value(
        value: controller,
        child: MaterialApp(
          theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
          home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(
            body: Center(child: SizedBox(width: 420, child: SingleChildScrollView(child: NetworkSettings()))),
          )),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final Finder mtu = find.byType(TextFormField);
      await tester.enterText(mtu, '1279');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(controller.settings.mtu, 9000);
      expect(find.text('عددی بین ۱۲۸۰ و ۹۰۰۰ وارد کنید'), findsOneWidget);
      await tester.enterText(mtu, '1400');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(controller.settings.mtu, 1400);
      expect(tester.takeException(), isNull);
    });
  }

  test('chain and ordered application routes persist without altering account data', () async {
    final SettingsController controller = create();
    addTearDown(controller.dispose);
    await controller.update(const AppSettings(phone: '09120000000', gatewayBase: 'https://account.example'));
    await controller.setChain(const ChainSettings(position: ChainPosition.unblocker, transport: ChainTransport.awg));
    await controller.setAppRoutes(const <AppRouteRule>[
      AppRouteRule(process: 'browser.exe', action: AppRouteAction.direct),
      AppRouteRule(process: 'game.exe', action: AppRouteAction.block),
    ]);
    await expectLater(controller.setAppRoutes(const <AppRouteRule>[
      AppRouteRule(process: 'browser.exe'), AppRouteRule(process: 'BROWSER.EXE'),
    ]), throwsFormatException);
    await expectLater(controller.setChain(const ChainSettings(position: ChainPosition.unblocker, mtu: -1)), throwsFormatException);
    final SettingsController reloaded = create();
    addTearDown(reloaded.dispose);
    await reloaded.load();
    expect(reloaded.settings.chain.position, ChainPosition.unblocker);
    expect(reloaded.settings.chain.transport, ChainTransport.awg);
    expect(reloaded.settings.appRoutes.map((AppRouteRule rule) => rule.process), <String>['browser.exe', 'game.exe']);
    expect(reloaded.settings.appRoutes.last.action, AppRouteAction.block);
    expect(reloaded.settings.phone, '09120000000');
    expect(reloaded.settings.gatewayBase, 'https://account.example');
  });
  for (final Brightness brightness in Brightness.values) {
    testWidgets('chain and route dialogs validate in RTL $brightness', (WidgetTester tester) async {
      final ThemeData theme = brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light();
      await tester.pumpWidget(MaterialApp(theme: theme, home: const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: ChainSettingsDialog(initial: ChainSettings(position: ChainPosition.unblocker))),
      )));
      await tester.pumpAndSettle();
      expect(find.text('WARP و زنجیره اتصال'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(MaterialApp(theme: theme, home: const Directionality(
        textDirection: TextDirection.rtl, child: Scaffold(body: AppRouteDialog()),
      )));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '*.exe');
      await tester.tap(find.text('ذخیره قانون'));
      await tester.pumpAndSettle();
      expect(find.text('نام فایل exe یا مسیر کامل ویندوز را وارد کنید'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

}
