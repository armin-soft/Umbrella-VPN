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
import 'package:umbrella_vpn/ui/shell/app_shell.dart';
import 'package:umbrella_vpn/ui/widgets/common.dart';
import 'package:umbrella_vpn/ui/widgets/gateway_dialog.dart';
import 'package:umbrella_vpn/ui/widgets/advanced_network_settings.dart';
import 'package:umbrella_vpn/ui/widgets/lan_sharing_dialog.dart';
import 'package:umbrella_vpn/ui/widgets/telegram_channel_dialog.dart';
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

/// Visit intermediate and end positions so lazily built content gets laid out.
Future<void> inspectVerticalScrolls(WidgetTester tester) async {
  for (var pass = 0; pass < 2; pass++) {
    final scrolls = tester.stateList<ScrollableState>(find.byType(Scrollable)).toList();
    for (final scroll in scrolls) {
      if (!scroll.mounted || scroll.position.axis != Axis.vertical || !scroll.position.hasContentDimensions) continue;
      final position = scroll.position;
      if (!position.maxScrollExtent.isFinite || position.maxScrollExtent <= 0) continue;
      for (final fraction in [0.25, 0.5, 0.75, 1.0, 0.0]) {
        if (!scroll.mounted || !position.hasPixels) break;
        position.jumpTo(position.maxScrollExtent * fraction);
        await tester.pump(const Duration(milliseconds: 80));
      }
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.instance.init();
    await TelegramChannelPrompt.markShown();
  });

  for (final size in <Size>[const Size(320, 568), const Size(360, 640), const Size(412, 915), const Size(640, 360), const Size(800, 1280)]) {
    for (final textScale in <double>[1.0, 1.3]) {
      testWidgets('Android screens at $size, text $textScale', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final bool splitDisplay =
            false;
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
          for (final section in SettingsCategory.navigationItems)
            SettingsPage(key: ValueKey(section.name), initialSection: section),
          const LogsPage(), const AboutPage(), const UpdatesPage(),
          AppShell(windowService: window),
        ];
        final problems = <String>[];
        var currentPage = '';
        final previousOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          problems.add('$currentPage at $size / $textScale: ${details.exception}');
          print("LAYOUT_DIAGNOSTIC: ${details.toString()}");
        };
        addTearDown(() { FlutterError.onError = previousOnError; });
        for (final page in pages) {
          // Each screen gets its own navigator; a sheet from the previous
          // screen must not block pointer events on the next one.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          currentPage = page is SettingsPage ? 'SettingsPage.${page.initialSection?.name ?? "menu"}' : page.runtimeType.toString();
          final errorsBefore = problems.length;
          final bool fullWindow = page is LandingPage || page is LoginPage || page is AppShell;
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
          if (page is AppShell && size.width < 700) {
            for (final label in ['اتصال', 'دستگاه من', 'حساب من', 'تنظیمات', 'گزارش ها', 'درباره', 'به روز رسانی']) {
              currentPage = 'AppShell.$label';
              try {
              await tester.tap(find.byTooltip('منو'));
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 350));
              final item = find.descendant(of: find.byType(Drawer), matching: find.text(label));
              await tester.ensureVisible(item);
              await tester.tap(item);
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 350));
              } catch (error) {
                print('Error: navigation $label: $error');
                rethrow;
              }
            }
          }
          if (page is DevicePage || page is AccountPage) {
            final tabKey = page is DevicePage ? 'device-section-tabs' : 'account-section-tabs';
            final tab = find.byKey(ValueKey<String>(tabKey));
            final controller = DefaultTabController.of(tester.element(tab));
            for (var i = 0; i < controller.length; i++) {
              currentPage = '${page.runtimeType}.tab$i';
              controller.index = i;
              await tester.pump(const Duration(milliseconds: 350));
              await inspectVerticalScrolls(tester);
            }
          } else if (page is! AppShell) {
            await inspectVerticalScrolls(tester);
          }
          if (page is LoginPage || (page is SettingsPage &&
              (page.initialSection == SettingsCategory.routing || page.initialSection == SettingsCategory.inbound))) {
            final context = tester.element(find.byWidget(page));
            currentPage = '${page.runtimeType}.dialog';
            if (page is LoginPage) {
              showGatewayDialog(context);
            } else if ((page as SettingsPage).initialSection == SettingsCategory.routing) {
              showDialog<void>(context: context, builder: (_) => const AppRouteDialog());
            } else {
              LanSharingDialog.show(context);
            }
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            expect(find.byType(Dialog), findsWidgets);
            await inspectVerticalScrolls(tester);
            Navigator.of(context).pop();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
          }
          final problem = tester.takeException();
          if (problem != null) {
            final stack = problem is Error ? problem.stackTrace : null;
            problems.add('${page.runtimeType} at $size / $textScale: $problem\n$stack');
          }
          if (page is ConnectPage && problem == null && problems.length == errorsBefore) {
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
            await tester.pump(const Duration(milliseconds: 500));
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
            await tester.pump(const Duration(milliseconds: 500));
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
