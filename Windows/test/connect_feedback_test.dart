import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbrella_vpn/core/app_config.dart';
import 'package:umbrella_vpn/core/storage.dart';
import 'package:umbrella_vpn/core/theme.dart';
import 'package:umbrella_vpn/data/gateway_client.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/platform/services.dart';
import 'package:umbrella_vpn/state/auth_controller.dart';
import 'package:umbrella_vpn/state/settings_controller.dart';
import 'package:umbrella_vpn/state/subscription_controller.dart';
import 'package:umbrella_vpn/state/toast_controller.dart';
import 'package:umbrella_vpn/state/update_controller.dart';
import 'package:umbrella_vpn/ui/pages/connect_page.dart';
import 'package:umbrella_vpn/ui/pages/updates_page.dart';
import 'package:umbrella_vpn/ui/widgets/common.dart';
import 'package:umbrella_vpn/ui/widgets/share_app_dialog.dart';
import 'package:umbrella_vpn/ui/widgets/shell_widgets.dart';
import 'package:umbrella_vpn/vpn/cores.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

class _ConnectNative extends NativeBridge {
  @override
  bool get available => false;

  @override
  Future<DeviceProfile> deviceInfo() async => const DeviceProfile(
        hostname: 'Umbrella-PC',
        username: 'Tester',
        os: 'Windows 11',
        localIp: '192.168.1.50',
        elevated: true,
      );

  @override
  Future<int> shutdownCores({bool skipIfClean = false}) async => 0;

  @override
  Future<bool> disableSystemProxy() async => true;
}

class _ConnectSound implements SoundService {
  @override
  bool enabled = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ConnectIpService extends IpService {
  @override
  Future<GeoInfo> fetch({
    bool force = false,
    String proxy = '',
    String proxyUser = '',
    String proxyPassword = '',
  }) async =>
      GeoInfo.empty;
}

class _ConnectProvisioner extends CoreProvisioner {
  _ConnectProvisioner(this._root);

  final String _root;

  @override
  String get dataDir => _root;

  @override
  Future<void> init() async {}

  @override
  Future<List<CoreInfo>> missingRequired() async => const <CoreInfo>[];

  @override
  Future<bool> provision(CoreInfo core) async => true;
}

class _SignedConnectAuth extends AuthController {
  _SignedConnectAuth({
    required super.native,
    required super.gateway,
    required super.store,
  });

  @override
  bool get signedIn => true;

  @override
  Account get account => const Account(
        name: 'کاربر ویندوز',
        enable: true,
        isActive: true,
      );

  @override
  SessionData? get session => const SessionData(
        token: 'tok-win-connect-1',
        uuid: '44444444-4444-4444-8444-444444444444',
        deviceId: 'dev-win-connect-1',
        account: Account(
          name: 'کاربر ویندوز',
          enable: true,
          isActive: true,
        ),
        filter: FilterSettings.empty,
      );
}

class _DelayedWinSubs extends SubscriptionController {
  _DelayedWinSubs({
    required super.vpn,
    required super.auth,
    required super.client,
    required this.onSync,
  }) : super(enableNativeTransport: false);

  final Future<void> Function() onSync;

  @override
  Future<void> syncPersonal() => onSync();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.instance.init();
  });

  test('VpnController.connect بلافاصله به وضعیت در حال اتصال می رود', () async {
    final Directory tempDir =
        await Directory.systemTemp.createTemp('umbrella_win_imm_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final _ConnectNative native = _ConnectNative();
    final _ConnectProvisioner provisioner = _ConnectProvisioner(tempDir.path);
    await provisioner.init();
    final Completer<String> scanGate = Completer<String>();
    final List<VpnStatus> seenStatuses = <VpnStatus>[];

    final VpnController vpn = VpnController(
      native: native,
      ipService: _ConnectIpService(),
      sound: _ConnectSound(),
      tray: TrayService(native),
      provisioner: provisioner,
      settings: const AppSettings(),
      securityGuard: () => scanGate.future,
    );
    vpn.addListener(() {
      if (seenStatuses.isEmpty || seenStatuses.last != vpn.status) {
        seenStatuses.add(vpn.status);
      }
    });
    addTearDown(vpn.dispose);

    final Future<ConnectOutcome> pending = vpn.connect();
    expect(vpn.status, VpnStatus.connecting);
    expect(vpn.status.label, 'در حال اتصال');
    expect(seenStatuses, contains(VpnStatus.connecting));
    expect(seenStatuses, isNot(contains(VpnStatus.preparing)));

    scanGate.complete('');
    final ConnectOutcome outcome = await pending;
    expect(outcome.ok, isFalse);
    expect(vpn.status, VpnStatus.failed);

    final Completer<String> slowScan = Completer<String>();
    final VpnController cancellable = VpnController(
      native: native,
      ipService: _ConnectIpService(),
      sound: _ConnectSound(),
      tray: TrayService(native),
      provisioner: provisioner,
      settings: const AppSettings(),
      securityGuard: () => slowScan.future,
    );
    addTearDown(cancellable.dispose);

    final Future<ConnectOutcome> pendingCancel = cancellable.connect();
    expect(cancellable.status, VpnStatus.connecting);
    await cancellable.cancel();
    slowScan.complete('');
    final ConnectOutcome cancelOutcome = await pendingCancel;
    expect(cancelOutcome.cancelled, isTrue);
    expect(cancellable.status, VpnStatus.disconnected);
  });

  testWidgets('ConnectPage در ویندوز بلافاصله با زدن اتصال عبارت در حال اتصال را نمایش می دهد', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1120, 900));
    addTearDown(() async => await tester.binding.setSurfaceSize(null));

    final _ConnectNative native = _ConnectNative();
    final _ConnectProvisioner provisioner = _ConnectProvisioner('/tmp/umbrella_win_page_imm');
    await provisioner.init();
    final _ConnectSound sound = _ConnectSound();
    final Completer<String> scanGate = Completer<String>();

    final VpnController vpn = VpnController(
      native: native,
      ipService: _ConnectIpService(),
      sound: sound,
      tray: TrayService(native),
      provisioner: provisioner,
      settings: const AppSettings(selectionMode: SelectionMode.manual),
      securityGuard: () => scanGate.future,
    );
    final SettingsController settings = SettingsController(
      native: native,
      sound: sound,
      window: WindowService(native),
    );
    final GatewayClient gateway = GatewayClient(
      client: MockClient((http.Request _) async => http.Response('{"ok":false}', 200)),
      enableNativeTransport: false,
    );
    final _SignedConnectAuth auth = _SignedConnectAuth(
      native: native,
      gateway: gateway,
      store: LocalStore.instance,
    );
    final Completer<void> syncGate = Completer<void>();
    final _DelayedWinSubs subs = _DelayedWinSubs(
      vpn: vpn,
      auth: auth,
      client: MockClient((http.Request _) async => http.Response('[]', 200)),
      onSync: () => syncGate.future,
    );
    final ToastController toasts = ToastController();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SoundService>.value(value: sound),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<SubscriptionController>.value(value: subs),
          ChangeNotifierProvider<VpnController>.value(value: vpn),
          ChangeNotifierProvider<ToastController>.value(value: toasts),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: ConnectPage()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('اتصال'), findsOneWidget);

    final Finder connectBtn = find.text('اتصال');
    await tester.ensureVisible(connectBtn);
    await tester.tap(connectBtn);
    await tester.pump();
    expect(find.text('در حال اتصال'), findsOneWidget);
    expect(find.text('لغو اتصال'), findsOneWidget);

    final Finder preCancelBtn = find.text('لغو اتصال');
    await tester.ensureVisible(preCancelBtn);
    await tester.tap(preCancelBtn);
    await tester.pump();
    expect(find.text('اتصال'), findsOneWidget);

    await tester.runAsync(() => vpn.applyNodes(const <VpnNode>[
          VpnNode(
            id: 'w1',
            name: 'Win Node 1',
            protocol: NodeProtocol.vless,
            host: '1.1.1.1',
            port: 443,
            sourceId: 'user-sub',
            pingMs: 120,
            disabled: true,
            params: <String, dynamic>{},
          ),
        ], measure: false));
    syncGate.complete();
    await tester.pump();

    final Finder connectBtn2 = find.text('اتصال');
    await tester.ensureVisible(connectBtn2);
    await tester.tap(connectBtn2);
    await tester.pump();
    expect(vpn.status, VpnStatus.connecting);
    expect(find.text('در حال اتصال'), findsOneWidget);
    expect(find.text('لغو اتصال'), findsOneWidget);

    scanGate.complete('');
    await tester.pump();
    await tester.pump();
    expect(vpn.status, VpnStatus.failed);

    toasts.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
    subs.dispose();
    vpn.dispose();
    settings.dispose();
    auth.dispose();
    gateway.close();
    toasts.dispose();
  });

  testWidgets('ConnectPage در ویندوز بنر اعلان نسخه جدید را نمایش می دهد و امکان بستن دارد', (WidgetTester tester) async {
    addTearDown(() async => await tester.binding.setSurfaceSize(null));

    const String sampleHash =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    final MockClient updateHttp = MockClient((http.Request _) async {
      return http.Response.bytes(
        utf8.encode(jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{
            'tag_name': 'v9.9.9-windows',
            'prerelease': false,
            'draft': false,
            'published_at': '2026-11-25T12:00:00Z',
            'body': '- نصب خودکار به روز رسانی بدون خطای خروج',
            'assets': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'UmbrellaVPN-Setup-9.9.9-x64.exe',
                'browser_download_url':
                    'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/v9.9.9-windows/UmbrellaVPN-Setup-9.9.9-x64.exe',
                'size': 40000000,
                'digest': 'sha256:$sampleHash',
              },
            ],
          },
        ])),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });

    final _ConnectNative native = _ConnectNative();
    final _ConnectProvisioner provisioner = _ConnectProvisioner('/tmp/umbrella_win_upd_banner');
    await provisioner.init();
    final _ConnectSound sound = _ConnectSound();
    final VpnController vpn = VpnController(
      native: native,
      ipService: _ConnectIpService(),
      sound: sound,
      tray: TrayService(native),
      provisioner: provisioner,
      settings: const AppSettings(),
    );
    final SettingsController settings = SettingsController(
      native: native,
      sound: sound,
      window: WindowService(native),
    );
    final GatewayClient gateway = GatewayClient(
      client: MockClient((http.Request _) async => http.Response('{"ok":false}', 200)),
      enableNativeTransport: false,
    );
    final _SignedConnectAuth auth = _SignedConnectAuth(
      native: native,
      gateway: gateway,
      store: LocalStore.instance,
    );
    final SubscriptionController subs = SubscriptionController(
      vpn: vpn,
      auth: auth,
      client: MockClient((http.Request _) async => http.Response('[]', 200)),
    );
    final UpdateController updates = UpdateController(
      native,
      service: UpdateService(client: updateHttp),
    );
    await tester.runAsync(() => updates.check(silent: false));
    expect(updates.available, isNotNull);

    final ToastController toasts = ToastController();
    final List<FlutterErrorDetails> errors = <FlutterErrorDetails>[];
    final FlutterExceptionHandler? prevError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = prevError);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    FlutterError.onError = (FlutterErrorDetails d) => errors.add(d);
    try {
      for (final Size size in const <Size>[Size(800, 600), Size(1120, 900)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<SoundService>.value(value: sound),
              ChangeNotifierProvider<SettingsController>.value(value: settings),
              ChangeNotifierProvider<AuthController>.value(value: auth),
              ChangeNotifierProvider<SubscriptionController>.value(value: subs),
              ChangeNotifierProvider<VpnController>.value(value: vpn),
              ChangeNotifierProvider<UpdateController>.value(value: updates),
              ChangeNotifierProvider<ToastController>.value(value: toasts),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(body: ConnectPage()),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey<String>('connect-update-banner')),
          findsOneWidget,
        );
        expect(find.textContaining('نسخه جدید'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('connect-update-action-button')),
          findsOneWidget,
        );
      }
    } finally {
      FlutterError.onError = prevError;
    }
    expect(errors, isEmpty, reason: errors.map((e) => e.exceptionAsString()).join('\n'));

    final Finder dismissBtn =
        find.byKey(const ValueKey<String>('connect-update-dismiss-button'));
    await tester.ensureVisible(dismissBtn);
    await tester.tap(dismissBtn);
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('connect-update-banner')), findsNothing);
    expect(updates.available, isNotNull);
    expect(updates.showBanner, isFalse);
    expect(LocalStore.instance.read(StoreKeys.updateSkipped), isNull);

    // حتی پس از بستن بنر صفحه اتصال، منوی به روز رسانی همچنان گزینه دانلود و نصب را دارد.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UpdateController>.value(value: updates),
          ChangeNotifierProvider<ToastController>.value(value: toasts),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: UpdatesPage()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('updates-page-download-card')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('updates-page-download-action-button')), findsOneWidget);
    expect(find.text('دانلود و بروز رسانی'), findsOneWidget);
    expect(find.text('بروز رسانی'), findsOneWidget);
    expect(find.textContaining('نصب مجدد'), findsNothing);

    // با بازگشت از سینی یا بستن و باز کردن مجدد برنامه (حتی با کلید قدیمی updateSkipped)،
    // اعلان به روز رسانی دوباره روی صفحه اتصال ظاهر می شود.
    updates.resetBannerDismissal();
    expect(updates.showBanner, isTrue);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SoundService>.value(value: sound),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<SubscriptionController>.value(value: subs),
          ChangeNotifierProvider<VpnController>.value(value: vpn),
          ChangeNotifierProvider<UpdateController>.value(value: updates),
          ChangeNotifierProvider<ToastController>.value(value: toasts),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: ConnectPage()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('connect-update-banner')), findsOneWidget);

    await tester.runAsync(() => LocalStore.instance.write(StoreKeys.updateSkipped, '9.9.9'));
    final UpdateController relaunched = UpdateController(
      native,
      service: UpdateService(client: updateHttp),
    );
    await tester.runAsync(() async {
      await relaunched.loadSkipped();
      await relaunched.check(silent: false);
    });
    expect(LocalStore.instance.read(StoreKeys.updateSkipped), isNull);
    expect(relaunched.available, isNotNull);
    expect(relaunched.showBanner, isTrue);
    relaunched.dispose();

    // وقتی آخرین نسخه بروز است، نیازی به دکمه دانلود و نصب مجدد نیست و حذف شده است.
    final MockClient idleHttp = MockClient(
      (http.Request _) async => http.Response.bytes(
        utf8.encode(jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{
            'tag_name': AppConfig.version,
            'prerelease': false,
            'draft': false,
            'published_at': '2026-11-25T12:00:00Z',
            'body': '- آخرین نسخه رسمی منتشرشده',
            'assets': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'UmbrellaVPN-Setup-${AppConfig.version}-x64.exe',
                'browser_download_url':
                    'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/${AppConfig.version}/UmbrellaVPN-Setup-${AppConfig.version}-x64.exe',
                'size': 40000000,
                'digest': 'sha256:$sampleHash',
              },
            ],
          },
        ])),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      ),
    );
    final UpdateController idleUpdates = UpdateController(
      native,
      service: UpdateService(client: idleHttp),
    );
    await tester.runAsync(() => idleUpdates.check(silent: false));
    expect(idleUpdates.available, isNull);
    expect(idleUpdates.releases, isNotEmpty);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UpdateController>.value(value: idleUpdates),
          ChangeNotifierProvider<ToastController>.value(value: toasts),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: UpdatesPage()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('updates-page-up-to-date-card')), findsOneWidget);
    expect(find.text('برنامه به روز است'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('updates-page-download-action-button')), findsNothing);
    expect(find.text('بروز رسانی'), findsNothing);
    expect(find.textContaining('نصب مجدد'), findsNothing);

    toasts.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
    idleUpdates.dispose();
    idleHttp.close();
    updates.dispose();
    updateHttp.close();
    subs.dispose();
    vpn.dispose();
    settings.dispose();
    auth.dispose();
    gateway.close();
    toasts.dispose();
  });

  testWidgets('نوار عنوان و نوار کنار ویندوز دکمه اشتراک گذاری دارند و بارکد و لینک مستقیم را باز می کنند', (WidgetTester tester) async {
    addTearDown(() async => await tester.binding.setSurfaceSize(null));

    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        final Map<dynamic, dynamic>? args = call.arguments as Map<dynamic, dynamic>?;
        copiedText = args?['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final _ConnectNative native = _ConnectNative();
    final MockClient emptyHttp = MockClient(
      (http.Request _) async => http.Response('[]', 200),
    );
    final UpdateController updates = UpdateController(
      native,
      service: UpdateService(client: emptyHttp),
    );
    final ToastController toasts = ToastController();
    final _ConnectSound sound = _ConnectSound();

    const List<NavDestination> destinations = <NavDestination>[
      NavDestination(label: 'اتصال', icon: Icons.shield_outlined, activeIcon: Icons.shield_rounded),
      NavDestination(label: 'درباره', icon: Icons.info_outline_rounded, activeIcon: Icons.info_rounded),
      NavDestination(label: 'به روز رسانی', icon: Icons.system_update_outlined, activeIcon: Icons.system_update_rounded),
    ];

    await tester.binding.setSurfaceSize(const Size(1280, 760));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SoundService>.value(value: sound),
          ChangeNotifierProvider<UpdateController>.value(value: updates),
          ChangeNotifierProvider<ToastController>.value(value: toasts),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Builder(
              builder: (BuildContext ctx) {
                void openShare() => ShareAppDialog.show(
                      ctx,
                      initialPlatform: ShareTargetPlatform.windows,
                    );
                return Scaffold(
                  body: Column(
                    children: <Widget>[
                      TitleBar(
                        status: VpnStatus.disconnected,
                        onDragStart: () {},
                        onMinimize: () {},
                        onMaximize: () {},
                        onClose: () {},
                        onShare: openShare,
                      ),
                      Expanded(
                        child: Row(
                          children: <Widget>[
                            SideNav(
                              destinations: destinations,
                              index: 0,
                              onSelect: (_) {},
                              status: VpnStatus.disconnected,
                              onShare: openShare,
                            ),
                            const Expanded(child: SizedBox.expand()),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey<String>('titlebar-share-button')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('sidenav-share-button')), findsOneWidget);
    expect(find.text('اشتراک گذاری'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('sidenav-share-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    expect(find.text('اشتراک گذاری برنامه'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('share-app-qr-box')), findsOneWidget);
    expect(find.text(AppConfig.directWindowsDownloadUrl()), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('share-platform-android')));
    await tester.pump();
    expect(find.text(AppConfig.directAndroidDownloadUrl()), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey<String>('share-app-copy-button')));
    await tester.tap(find.byKey(const ValueKey<String>('share-app-copy-button')));
    await tester.pump();
    expect(copiedText, AppConfig.directAndroidDownloadUrl());
    expect(find.text('کپی شد'), findsOneWidget);

    await tester.ensureVisible(find.text('بستن'));
    await tester.tap(find.text('بستن'));
    await tester.pump();

    // همچنین در کوچک ترین پنجره دسکتاپ (800x480) دیالوگ اشتراک گذاری بدون سرریز رندر می شود.
    await tester.binding.setSurfaceSize(const Size(800, 480));
    await tester.tap(find.byKey(const ValueKey<String>('titlebar-share-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey<String>('share-app-qr-box')), findsOneWidget);
    expect(find.text(AppConfig.directWindowsDownloadUrl()), findsOneWidget);

    toasts.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
    updates.dispose();
    emptyHttp.close();
    toasts.dispose();
  });
}
