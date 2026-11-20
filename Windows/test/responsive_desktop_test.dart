import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
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
import 'package:umbrella_vpn/state/subscription_controller.dart';
import 'package:umbrella_vpn/state/toast_controller.dart';
import 'package:umbrella_vpn/state/update_controller.dart';
import 'package:umbrella_vpn/ui/pages/about_page.dart';
import 'package:umbrella_vpn/ui/pages/account_page.dart';
import 'package:umbrella_vpn/ui/pages/connect_page.dart';
import 'package:umbrella_vpn/ui/pages/device_page.dart';
import 'package:umbrella_vpn/ui/pages/landing_page.dart';
import 'package:umbrella_vpn/ui/pages/login_page.dart';
import 'package:umbrella_vpn/ui/pages/logs_page.dart';
import 'package:umbrella_vpn/ui/pages/settings_page.dart';
import 'package:umbrella_vpn/ui/pages/updates_page.dart';
import 'package:umbrella_vpn/ui/widgets/common.dart';
import 'package:umbrella_vpn/vpn/cores.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

class _Native extends NativeBridge {
  @override
  Future<DeviceProfile> deviceInfo() async => DeviceProfile.empty;
  @override
  Future<int> shutdownCores({bool skipIfClean = false}) async => 0;
}
class _Sound implements SoundService {
  @override
  bool enabled = false;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
class _Vpn extends VpnController {
  _Vpn(NativeBridge native, SoundService sound)
      : super(native: native, ipService: IpService(), sound: sound,
          tray: TrayService(native), provisioner: CoreProvisioner(),
          settings: const AppSettings());
  @override
  Future<void> refreshIp() async {}
}
class _Updates extends UpdateController {
  _Updates(super.native);
  @override
  Future<void> loadSkipped() async {}
  @override
  Future<bool> check({bool silent = false, bool ignoreSkipped = false}) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.instance.init();
  });

  test('window fits the logical primary work area with and without DPI space', () {
    final small = WindowService.fitWindowToWorkArea(const Size(1280, 820), const Size(853, 480));
    expect(small.initial, const Size(853, 480));
    expect(small.minimum, const Size(800, 480));
    final tiny = WindowService.fitWindowToWorkArea(const Size(1280, 820), const Size(720, 400));
    expect(tiny.initial, const Size(720, 400));
    expect(tiny.minimum, const Size(720, 400));
    final desktop = WindowService.fitWindowToWorkArea(const Size(1280, 820), const Size(1920, 1040));
    expect(desktop.initial, const Size(1280, 820));
    expect(WindowService.fitWindowToWorkArea(const Size(1280, 820), null).initial, const Size(1280, 820));
  });

  for (final size in <Size>[const Size(800, 480), const Size(1120, 720), const Size(1920, 1080)]) {
    for (final textScale in <double>[1.0, 1.25]) {
      testWidgets('desktop screens at $size, text $textScale', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final bool splitDisplay =
            size == const Size(800, 480) && textScale == 1.0;
        final List<DisplayFeature> displayFeatures = splitDisplay
            ? <DisplayFeature>[
                DisplayFeature(
                  bounds: Rect.fromLTRB(
                    size.width / 2 - 10,
                    0,
                    size.width / 2 + 10,
                    size.height,
                  ),
                  type: DisplayFeatureType.hinge,
                  state: DisplayFeatureState.unknown,
                ),
              ]
            : const <DisplayFeature>[];
        final native = _Native();
        final sound = _Sound();
        final window = WindowService(native);
        final settings = SettingsController(native: native, sound: sound, window: window);
        final vpn = _Vpn(native, sound);
        final auth = AuthController(native: native);
        final subs = SubscriptionController(vpn: vpn, auth: auth);
        final updates = _Updates(native);
        final power = PowerController(readStatus: () async => const BatteryPowerState(
            isLaptop: true, hasBattery: true, onBattery: true, energySaver: false));
        final toasts = ToastController();
        await power.refresh();
        final pages = <Widget>[
          LandingPage(onStart: () {}), const LoginPage(), const ConnectPage(),
          const DevicePage(), const AccountPage(), const SettingsPage(),
          const LogsPage(), const AboutPage(), const UpdatesPage(),
        ];
        final problems = <String>[];
        for (final page in pages) {
          final bool fullWindow = page is LandingPage || page is LoginPage;
          await tester.pumpWidget(MultiProvider(
            providers: [
              Provider<NativeBridge>.value(value: native),
              Provider<WindowService>.value(value: window),
              ChangeNotifierProvider<SettingsController>.value(value: settings),
              ChangeNotifierProvider<VpnController>.value(value: vpn),
              ChangeNotifierProvider<AuthController>.value(value: auth),
              ChangeNotifierProvider<SubscriptionController>.value(value: subs),
              ChangeNotifierProvider<UpdateController>.value(value: updates),
              ChangeNotifierProvider<PowerController>.value(value: power),
              ChangeNotifierProvider<ToastController>.value(value: toasts),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              builder: (BuildContext context, Widget? child) => MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(textScale),
                  displayFeatures: displayFeatures,
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: child!,
                ),
              ),
              home: fullWindow
                  ? page
                  : Scaffold(
                      body: Row(
                        children: <Widget>[
                          const SizedBox(width: AppMetrics.navWidthCompact),
                          Expanded(
                            child: TickerMode(
                              enabled: false,
                              child: page is ConnectPage
                                  ? page
                                  : MenuPageBackdrop(child: page),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ));
          await tester.pump();
          if (page is ConnectPage) {
            expect(find.byType(MenuPageBackdrop), findsNothing);
          } else if (!fullWindow) {
            expect(find.byType(MenuPageBackdrop), findsOneWidget);
          }
          final problem = tester.takeException();
          if (problem != null) {
            final stack = problem is Error ? problem.stackTrace : null;
            problems.add('${page.runtimeType} at $size / $textScale: $problem\n$stack');
          }
          if (page is ConnectPage && problem == null) {
            // In RTL, omitting anchorPoint would select this hinge's right pane.
            final Finder settingsButton = find.byKey(
              const ValueKey<String>('connection-settings-button'),
            );
            expect(settingsButton, findsOneWidget);
            expect(
              find.byKey(const ValueKey<String>('connection-settings-sheet')),
              findsNothing,
            );
            await tester.ensureVisible(settingsButton);
            await tester.tap(settingsButton);
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey<String>('connection-settings-sheet')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey<String>('quick-settings-close')),
              findsOneWidget,
            );
            final Rect sheetRect = tester.getRect(
              find.byKey(
                const ValueKey<String>('connection-settings-sheet'),
              ),
            );
            final double expectedCenter = splitDisplay
                ? (size.width / 2 - 10) / 2
                : size.width / 2;
            expect(sheetRect.center.dx, closeTo(expectedCenter, 1));
            final sheetProblem = tester.takeException();
            if (sheetProblem != null) {
              problems.add(
                'Connection settings sheet at $size / $textScale: $sheetProblem',
              );
            }
            await tester.tap(
              find.byKey(const ValueKey<String>('quick-settings-close')),
            );
            await tester.pumpAndSettle();
          }
        }
        await tester.pumpWidget(const SizedBox());
        subs.dispose();
        auth.dispose();
        settings.dispose();
        power.dispose();
        toasts.dispose();
        updates.dispose();
        vpn.dispose();
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
    }
  }
}
