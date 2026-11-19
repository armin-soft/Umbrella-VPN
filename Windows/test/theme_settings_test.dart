import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:umbrella_vpn/core/theme.dart';
import 'package:umbrella_vpn/state/auth_controller.dart';
import 'package:umbrella_vpn/ui/widgets/common.dart';
import 'package:umbrella_vpn/ui/widgets/network_settings.dart';
import 'package:umbrella_vpn/ui/widgets/shell_widgets.dart';
import 'package:umbrella_vpn/ui/widgets/advanced_network_settings.dart';

import 'package:umbrella_vpn/core/storage.dart';
import 'package:umbrella_vpn/core/utils.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/platform/services.dart';
import 'package:umbrella_vpn/state/settings_controller.dart';

class _Native implements NativeBridge {
  @override
  Future<bool> isElevated() async => false;
  @override
  Future<bool> autostartEnabled() async => false;
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
      expect(find.text('وارپ و زنجیره اتصال'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(MaterialApp(theme: theme, home: const Directionality(
        textDirection: TextDirection.rtl, child: Scaffold(body: AppRouteDialog()),
      )));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '*.exe');
      await tester.tap(find.text('ذخیره قانون'));
      await tester.pumpAndSettle();
      expect(
        find.text('نام فایل اجرایی برنامه یا مسیر کامل ویندوز را وارد کنید'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('connect mode and server selection dropdowns open anchored in RTL $brightness', (WidgetTester tester) async {
      final ThemeData theme = brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light();
      CorePreference pickedConnection = CorePreference.auto;
      SelectionMode pickedSelection = SelectionMode.auto;
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) => Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: AppMetrics.pagePadding,
                  child: SizedBox(
                    width: AppMetrics.breakpointCompact,
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: AnchoredSelectField<CorePreference>(
                            key: const ValueKey<String>('test-conn'),
                            label: 'حالت اتصال',
                            value: pickedConnection,
                            options: <SelectOption<CorePreference>>[
                              for (final CorePreference p in CorePreference.values)
                                SelectOption<CorePreference>(
                                  value: p,
                                  label: p.faName,
                                  subtitle: p.description,
                                  icon: p.icon,
                                ),
                            ],
                            onChanged: (CorePreference next) =>
                                setState(() => pickedConnection = next),
                          ),
                        ),
                        const SizedBox(width: AppMetrics.space3),
                        Expanded(
                          child: AnchoredSelectField<SelectionMode>(
                            key: const ValueKey<String>('test-sel'),
                            label: 'حالت انتخاب سرور',
                            value: pickedSelection,
                            options: <SelectOption<SelectionMode>>[
                              for (final SelectionMode m in SelectionModeList.visible)
                                SelectOption<SelectionMode>(
                                  value: m,
                                  label: m.label,
                                  subtitle: m.description,
                                  icon: m.icon,
                                ),
                            ],
                            onChanged: (SelectionMode next) =>
                                setState(() => pickedSelection = next),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Open connection mode dropdown: must open anchored right below field, never as a Dialog.
      await tester.tap(find.text('خودکار'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      final Rect fieldRect = tester.getRect(find.byKey(const ValueKey<String>('test-conn')));
      final Rect optionRect = tester.getRect(find.text('تونل کامل'));
      expect((optionRect.right - fieldRect.right).abs(), lessThan(60));
      expect(optionRect.top, greaterThanOrEqualTo(fieldRect.bottom - 4));
      expect(optionRect.top, lessThan(fieldRect.bottom + 140));
      await tester.tap(find.text('تونل کامل'));
      await tester.pumpAndSettle();
      expect(pickedConnection, CorePreference.tun);
      expect(tester.takeException(), isNull);

      // Open server selection dropdown and select round-robin cleanly.
      await tester.tap(find.text('خودکار (کمترین پینگ)'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(find.text('گردشی'));
      await tester.pumpAndSettle();
      expect(pickedSelection, SelectionMode.roundRobin);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('title bar theme toggle flips dark and light in a single frame without lag', (WidgetTester tester) async {
    expect(identical(AppTheme.dark(), AppTheme.dark()), isTrue);
    expect(identical(AppTheme.light(), AppTheme.light()), isTrue);

    final SettingsController controller = create();
    await controller.load();
    await controller.setTheme(ThemePreference.system);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsController>.value(
        value: controller,
        child: Builder(
          builder: (BuildContext context) {
            final ThemeMode mode = context.select<SettingsController, ThemeMode>(
              (SettingsController s) => s.themeMode,
            );
            return MaterialApp(
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: mode,
              themeAnimationDuration: Duration.zero,
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: Builder(
                  builder: (BuildContext inner) {
                    final bool isDark =
                        Theme.of(inner).brightness == Brightness.dark;
                    return Scaffold(
                      backgroundColor: inner.colors.background,
                      body: Column(
                        children: <Widget>[
                          TitleBar(
                            onDragStart: () {},
                            onMinimize: () {},
                            onMaximize: () {},
                            onClose: () {},
                            darkTheme: isDark,
                            onToggleTheme: () => controller.toggleTheme(
                              effectiveBrightness: Theme.of(inner).brightness,
                            ),
                          ),
                          const GlassCard(child: Text('آزمایش تم')),
                        ],
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    Brightness currentBrightness() =>
        Theme.of(tester.element(find.text('آزمایش تم'))).brightness;

    // Rapid consecutive taps: every single tap must flip brightness on the very next frame.
    for (int i = 0; i < 4; i++) {
      final Brightness before = currentBrightness();
      final IconData expectedIcon = before == Brightness.dark
          ? Icons.light_mode_rounded
          : Icons.dark_mode_rounded;
      await tester.tap(find.byIcon(expectedIcon));
      await tester.pump();
      expect(
        currentBrightness(),
        before == Brightness.dark ? Brightness.light : Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    }
  });

  test('notification history keeps previous items on empty polls and recovers server history silently', () {
    final Set<String> announced = <String>{};
    final AppNotification n1 = AppNotification(
      id: 10,
      title: 'تمدید اشتراک',
      body: 'اشتراک شما با موفقیت تمدید شد.',
      level: 'success',
      sentAt: DateTime.utc(2026, 11, 15, 10),
    );
    final AppNotification n2 = AppNotification(
      id: 11,
      title: 'اطلاعیه سرور',
      body: 'سرور جدید اضافه شد.',
      level: 'info',
      sentAt: DateTime.utc(2026, 11, 16, 12),
    );

    // 1. Initial delivery brings n1 & n2 sorted newest-first.
    final step1 = AuthController.mergeNotificationHistory(
      existing: const <AppNotification>[],
      incoming: <AppNotification>[n1, n2],
      announced: announced,
    );
    expect(step1.merged.map((AppNotification e) => e.id).toList(), <int>[11, 10]);
    expect(step1.fresh.length, 2);
    for (final AppNotification item in step1.fresh) {
      announced.add(item.identityKey);
    }

    // 2. Subsequent poll (or opening the bell dialog) returns [] — previous items MUST remain.
    final step2 = AuthController.mergeNotificationHistory(
      existing: step1.merged,
      incoming: const <AppNotification>[],
      announced: announced,
    );
    expect(step2.merged.map((AppNotification e) => e.id).toList(), <int>[11, 10]);
    expect(step2.fresh, isEmpty);

    // 3. Mark n2 as read, then receive brand-new n3 + historical delivered n0 + stale revoke notice.
    final List<AppNotification> afterRead = <AppNotification>[
      step2.merged[0].copyWith(read: true),
      step2.merged[1],
    ];
    final AppNotification n0Old = AppNotification(
      id: 5,
      title: 'خوش آمدید',
      body: 'ورود اولیه ثبت شد.',
      level: 'info',
      sentAt: DateTime.utc(2026, 11, 10, 8),
      delivered: true,
    );
    final AppNotification n3New = AppNotification(
      id: 12,
      title: 'هشدار حجم',
      body: 'کمتر از ۱۰ درصد حجم باقی مانده است.',
      level: 'warning',
      sentAt: DateTime.utc(2026, 11, 17, 9),
      delivered: false,
    );
    final AppNotification staleRevoke = AppNotification(
      id: 13,
      title: 'مجوز این دستگاه لغو شد',
      body: 'دسترسی این دستگاه به نرم افزار آمبرلا لغو شد.',
      level: 'warning',
      sentAt: DateTime.utc(2026, 11, 17, 9, 5),
    );
    final step3 = AuthController.mergeNotificationHistory(
      existing: afterRead,
      incoming: <AppNotification>[
        n3New,
        n2.copyWith(),
        n1.copyWith(),
        n0Old,
        staleRevoke,
      ],
      announced: announced,
    );
    expect(
      step3.merged.map((AppNotification e) => e.id).toList(),
      <int>[12, 11, 10, 5],
    );
    // Only brand-new n3 triggers sound/balloon; recovered n0Old is marked read silently.
    expect(step3.fresh.map((AppNotification e) => e.id).toList(), <int>[12]);
    expect(step3.merged.firstWhere((AppNotification e) => e.id == 12).read, isFalse);
    expect(step3.merged.firstWhere((AppNotification e) => e.id == 11).read, isTrue);
    expect(step3.merged.firstWhere((AppNotification e) => e.id == 10).read, isFalse);
    expect(step3.merged.firstWhere((AppNotification e) => e.id == 5).read, isTrue);
  });

  testWidgets('short and tall menu pages start at identical top and right offsets with zero top gap', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Widget shellFrame(Widget page) {
      return MaterialApp(
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Column(
              children: <Widget>[
                const SizedBox(height: AppMetrics.titleBarHeight),
                Expanded(
                  child: Row(
                    children: <Widget>[
                      const SizedBox(width: AppMetrics.navWidthWide),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: AppMetrics.maxContentWidth,
                            ),
                            child: SizedBox.expand(child: page),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 1. Short scrollable page (like DevicePage / AboutPage).
    await tester.pumpWidget(shellFrame(
      SingleChildScrollView(
        padding: AppMetrics.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            PageHeader(
              key: const ValueKey<String>('hdr'),
              title: 'دستگاه من',
              subtitle: 'مشخصات سیستم، شناسه و شبکه فعال این کامپیوتر',
              icon: Icons.computer_rounded,
              actions: <Widget>[
                OutlinedButton(onPressed: () {}, child: const Text('به روز رسانی')),
              ],
            ),
            const SizedBox(height: AppMetrics.space4),
            const PageBanner(
              key: ValueKey<String>('bnr'),
              leading: IconSquare(icon: Icons.computer_rounded, color: Colors.red),
              title: 'DESKTOP',
              subtitle: 'Windows 11',
            ),
          ],
        ),
      ),
    ));
    await tester.pump();
    final Rect shortHeader = tester.getRect(find.byKey(const ValueKey<String>('hdr')));
    final Rect shortBanner = tester.getRect(find.byKey(const ValueKey<String>('bnr')));

    // 2. Tall scrollable page without header actions (like SettingsPage).
    await tester.pumpWidget(shellFrame(
      const SingleChildScrollView(
        padding: AppMetrics.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            PageHeader(
              key: ValueKey<String>('hdr'),
              title: 'تنظیمات',
              subtitle: 'مدیریت اتصال، شبکه، ظاهر برنامه و رفتار ویندوز',
              icon: Icons.settings_rounded,
            ),
            SizedBox(height: AppMetrics.space4),
            PageBanner(
              key: ValueKey<String>('bnr'),
              leading: IconSquare(icon: Icons.settings_rounded, color: Colors.red),
              title: 'مرکز تنظیمات آمبرلا',
              subtitle: 'تمام تغییرات بلافاصله ذخیره می شوند',
            ),
            SizedBox(height: 1600),
          ],
        ),
      ),
    ));
    await tester.pump();
    final Rect tallHeader = tester.getRect(find.byKey(const ValueKey<String>('hdr')));
    final Rect tallBanner = tester.getRect(find.byKey(const ValueKey<String>('bnr')));

    // 3. Fixed full-height page (like LogsPage).
    await tester.pumpWidget(shellFrame(
      const Padding(
        padding: AppMetrics.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            PageHeader(
              key: ValueKey<String>('hdr'),
              title: 'گزارش ها',
              subtitle: 'همه رویدادها',
              icon: Icons.receipt_long_rounded,
            ),
            Expanded(child: SizedBox.shrink()),
          ],
        ),
      ),
    ));
    await tester.pump();
    final Rect fixedHeader = tester.getRect(find.byKey(const ValueKey<String>('hdr')));

    const double expectedTop = AppMetrics.titleBarHeight + AppMetrics.space6;
    expect(shortHeader.top, expectedTop);
    expect(tallHeader.top, expectedTop);
    expect(fixedHeader.top, expectedTop);
    expect(shortHeader.right, tallHeader.right);
    expect(shortHeader.right, fixedHeader.right);
    expect(shortHeader.left, tallHeader.left);
    expect(shortBanner.top, tallBanner.top);
  });

  testWidgets('network controls render spacious 2-column grid on desktop width', (WidgetTester tester) async {
    final SettingsController controller = create();
    addTearDown(controller.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<SettingsController>.value(
      value: controller,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 960,
                child: SingleChildScrollView(child: NetworkSettings()),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('پشته کارت شبکه تونل'), findsOneWidget);
    expect(find.text('اندازه بسته تونل'), findsOneWidget);
    expect(find.text('دی ان اس ترافیک تونل'), findsOneWidget);
    expect(find.text('وارپ و اتصال زنجیره ای'), findsOneWidget);
    expect(find.text('مسیریابی برنامه های ویندوز'), findsOneWidget);
  });

  test('AppLogger.redact strips server hosts, ports, protocols, IPs and subscription URLs', () {
    // 1. Exact server disclosure line reported by user (mixed case + Persian port).
    final String serverLine = AppLogger.redact(
      'اتصال به سرور آمبرلا (خودکار) tls httpupgrade CDN vmess (proXY.UMBReLla-serVER.IR:۴۴۳)',
    );
    expect(serverLine.toLowerCase(), isNot(contains('umbrella-server')));
    expect(serverLine.toLowerCase(), isNot(contains('proxy.')));
    expect(serverLine, isNot(contains('۴۴۳')));
    expect(serverLine, isNot(contains('443')));
    expect(serverLine.toLowerCase(), isNot(contains('vmess')));
    expect(serverLine.toLowerCase(), isNot(contains('httpupgrade')));
    expect(serverLine.toLowerCase(), isNot(contains('tls')));
    expect(serverLine.toLowerCase(), isNot(contains('cdn')));

    // 2. Full subscription URL and ClientException leaking /sub/ token + UUID.
    final String subError = AppLogger.redact(
      'ClientException: Failed host lookup: user.umbrella-server.ir, '
      'uri=https://user.umbrella-server.ir/D6qnVQXRwa/9b9d9f5d-9841-45bf-a6b9-0479de273c11/sub/',
    );
    expect(subError, isNot(contains('https://')));
    expect(subError, isNot(contains('umbrella-server')));
    expect(subError, isNot(contains('D6qnVQXRwa')));
    expect(subError, isNot(contains('9b9d9f5d')));
    expect(subError, isNot(contains('/sub/')));

    // 3. Raw proxy links and core outbound logs with server domain and IP.
    AppLogger.instance.clear();
    AppLogger.instance.add(
      'vless://9b9d9f5d-9841-45bf-a6b9-0479de273c11@edge.example.ir:2053?type=ws&security=tls#Node1',
      level: 'error',
      details: const <LogDetail>[
        LogDetail(
          title: 'خروجی کامل هسته',
          text: 'INFO outbound/vmess[auto-1]: outbound connection to proXY.UMBReLla-serVER.IR:443\n'
              'WARN dial tcp 185.143.233.12:8443: i/o timeout\n'
              'INFO inbound/mixed: listening at 127.0.0.1:12334',
        ),
      ],
    );
    final String exported = AppLogger.instance.exportText();
    expect(exported.toLowerCase(), isNot(contains('vless://')));
    expect(exported.toLowerCase(), isNot(contains('example.ir')));
    expect(exported.toLowerCase(), isNot(contains('umbrella-server')));
    expect(exported, isNot(contains('185.143.233.12')));
    expect(exported, isNot(contains('8443')));
    expect(exported, isNot(contains('2053')));
    expect(exported, isNot(contains('9b9d9f5d')));
    // Local loopback & harmless binary/status lines stay intact.
    expect(exported, contains('127.0.0.1:12334'));
    final String localReady = AppLogger.redact(
      r'هسته آمبرلا آماده است: C:\Program Files\Umbrella\UmbrellaCoreEngine.exe',
    );
    expect(localReady, contains('هسته آمبرلا آماده است'));
    expect(localReady, contains('UmbrellaCoreEngine.exe'));
    AppLogger.instance.clear();
  });

}
