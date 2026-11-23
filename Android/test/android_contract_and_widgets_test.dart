import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbrella_vpn/core/storage.dart';
import 'package:umbrella_vpn/core/theme.dart';
import 'package:umbrella_vpn/core/ui_formatters.dart';
import 'package:umbrella_vpn/core/utils.dart';
import 'package:umbrella_vpn/data/gateway_client.dart';
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
import 'package:umbrella_vpn/ui/pages/device_page.dart';
import 'package:umbrella_vpn/ui/pages/exit_page.dart';
import 'package:umbrella_vpn/ui/pages/landing_page.dart';
import 'package:umbrella_vpn/ui/pages/login_page.dart';
import 'package:umbrella_vpn/ui/pages/logs_page.dart';
import 'package:umbrella_vpn/ui/pages/connect_page.dart';
import 'package:umbrella_vpn/ui/pages/settings_page.dart';
import 'package:umbrella_vpn/ui/pages/updates_page.dart';
import 'package:umbrella_vpn/ui/shell/app_shell.dart';
import 'package:umbrella_vpn/ui/widgets/quick_connection_panel.dart';
import 'package:umbrella_vpn/ui/widgets/shell_widgets.dart';
import 'package:umbrella_vpn/vpn/core_runtime.dart';
import 'package:umbrella_vpn/vpn/cores.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

class _FakeNative implements NativeBridge {
  int batteryIgnoreCalls = 0;
  int vpnSettingsCalls = 0;
  bool batteryOptimized = true;
  bool canInstall = true;
  bool notificationGranted = true;

  @override
  bool get available => true;

  @override
  Future<bool> isElevated() async => true;

  @override
  Future<bool> requestIgnoreBatteryOptimization() async {
    batteryIgnoreCalls++;
    return true;
  }

  @override
  Future<bool> openVpnSystemSettings() async {
    vpnSettingsCalls++;
    return true;
  }

  @override
  Future<bool> setAutostart(bool enabled) async => true;

  @override
  Future<bool> setPerAppProxy({
    required String mode,
    List<String>? includePackages,
    List<String>? excludePackages,
  }) async =>
      true;

  @override
  Future<List<InstalledAppInfo>> getInstalledApps() async =>
      const <InstalledAppInfo>[
        InstalledAppInfo(
          packageName: 'org.telegram.messenger',
          name: 'Telegram',
        ),
      ];

  @override
  Future<DeviceProfile> deviceInfo() async => DeviceProfile(
        hostname: 'Umbrella Phone',
        username: 'Pixel 8',
        os: 'اندروید ۱۵ (API 35)',
        osDisplayVersion: '15',
        osBuild: 35,
        arch: 'arm64-v8a',
        cpuCores: 8,
        ramTotalMb: 8192,
        ramUsedMb: 4096,
        ramLoadPercent: 50,
        diskTotalMb: 122880,
        diskFreeMb: 61440,
        hasBattery: true,
        batteryPercent: 80,
        powerPlugged: false,
        uptimeSeconds: 1800,
        localIp: '192.168.1.50',
        elevated: true,
        batteryOptimized: batteryOptimized,
        canRequestInstallPackages: canInstall,
        notificationGranted: notificationGranted,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSound implements SoundService {
  @override
  bool enabled = true;

  @override
  Future<void> play(String name) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWindow implements WindowService {
  @override
  bool closeToTray = true;

  @override
  bool notificationsEnabled = true;

  bool hideCalled = false;

  @override
  bool get isVisible => true;

  @override
  bool get isHiddenToTray => false;

  @override
  void setLifecycleVisible(bool visible) {}

  @override
  Future<void> hide() async {
    hideCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVpn extends ChangeNotifier implements VpnController {
  VpnStatus current = VpnStatus.disconnected;
  DeviceProfile currentDevice = const DeviceProfile(
    hostname: 'Umbrella Phone',
    username: 'Pixel 8',
    osDisplayVersion: '15',
    osBuild: 35,
    arch: 'arm64-v8a',
    cpuCores: 8,
    ramTotalMb: 8192,
    ramUsedMb: 4096,
    ramLoadPercent: 50,
    diskTotalMb: 122880,
    diskFreeMb: 61440,
    hasBattery: true,
    batteryPercent: 80,
    powerPlugged: false,
    uptimeSeconds: 1800,
    localIp: '192.168.1.50',
    batteryOptimized: true,
    canRequestInstallPackages: false,
    notificationGranted: false,
  );
  int reloads = 0;
  bool shutdownCalled = false;

  @override
  VpnStatus get status => current;

  @override
  DeviceProfile get device => currentDevice;

  @override
  GeoInfo get geo => const GeoInfo();

  @override
  VpnNode? get activeNode => null;

  @override
  int get activePingMs => 0;

  @override
  String get message => 'آماده برای اتصال';

  @override
  bool get measuring => false;

  @override
  List<VpnNode> get nodes => const <VpnNode>[];

  @override
  bool get emergencySession => false;

  @override
  TunnelStats get stats => const TunnelStats();

  @override
  String get realIp => '';

  @override
  String get exitIp => '';

  @override
  void scheduleLiveReload() {
    reloads++;
  }

  @override
  Future<void> refreshIp() async {}

  @override
  Future<void> refreshPings({bool all = true, bool tunnelProbe = true}) async {}

  @override
  Future<void> shutdownForExit() async {
    shutdownCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.instance.init();
  });

  group('Android native & manifest contracts', () {
    test('MethodHandler.kt covers every NativeBridge channel method', () {
      final String nativeDart =
          File('lib/platform/native.dart').readAsStringSync();
      final String methodHandlerKt = File(
        'android/app/src/main/kotlin/ir/umbrella/vpn/MethodHandler.kt',
      ).readAsStringSync();

      final RegExp invokePattern = RegExp(
        r"(?:_invoke|_channel\.invokeMethod)(?:<[^>]+>)?\(\s*'([^']+)'",
      );
      final Set<String> invokedMethods = invokePattern
          .allMatches(nativeDart)
          .map((RegExpMatch m) => m.group(1)!)
          .toSet();

      expect(invokedMethods, isNotEmpty);
      for (final String method in invokedMethods) {
        expect(
          methodHandlerKt,
          contains('"$method" ->'),
          reason: 'MethodHandler.kt is missing "$method"',
        );
      }
    });

    test('AndroidManifest.xml and core manifest expose required capabilities', () {
      final String manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android.permission.BIND_VPN_SERVICE'));
      expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
      expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
      expect(
        manifest,
        contains('android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS'),
      );
      expect(manifest, contains('.bg.VPNService'));
      expect(manifest, contains('.bg.ProxyService'));
      expect(manifest, contains('.bg.TileService'));
      expect(manifest, contains('.bg.BootReceiver'));
      expect(manifest, contains('androidx.core.content.FileProvider'));

      final Map<String, dynamic> coreManifest = jsonDecode(
        File('assets/cores/manifest.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(coreManifest['platform'], 'android');
      final List<dynamic> cores = coreManifest['cores'] as List<dynamic>;
      expect(cores, hasLength(1));
      final Map<String, dynamic> core = cores.first as Map<String, dynamic>;
      expect(core['binary'], 'hiddify-core.aar');
      expect(core['version'], '5.9.15');
      expect(
        RegExp(r'^[0-9a-f]{64}$').hasMatch(core['sha256'] as String),
        isTrue,
      );
    });

    test('NativeBridge.performHttpRequest sends UTF-8 JSON bodies without truncating Persian chars',
        () async {
      const MethodChannel channel = MethodChannel('ir.umbrella.app/native');
      Uint8List? capturedBodyBytes;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'httpRequest') {
          final Map<Object?, Object?> args =
              call.arguments as Map<Object?, Object?>;
          capturedBodyBytes = args['bodyBytes'] as Uint8List?;
          return <String, Object?>{
            'statusCode': 200,
            'headers': <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
            'bodyBytes': Uint8List.fromList(utf8.encode('{"ok":true}')),
          };
        }
        return null;
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final String requestBody = jsonEncode(<String, dynamic>{
        'phone': '09123456789',
        'device_id': '0123456789abcdef0123456789abcdef',
        'device_name': 'دستگاه اندروید',
        'platform': 'اندروید ۱۵ • سطح API ۳۵ • آرم ۶۴ بیتی',
        'first_name': 'آرمین',
      });

      final NativeHttpResponse? resp = await NativeBridge.performHttpRequest(
        method: 'POST',
        url: 'https://example.test/index.php?AppApi=auth/start',
        headers: const <String, String>{
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: requestBody,
      );

      expect(resp, isNotNull);
      expect(resp!.ok, isTrue);
      expect(capturedBodyBytes, isNotNull);
      expect(capturedBodyBytes, equals(Uint8List.fromList(utf8.encode(requestBody))));

      final Map<String, dynamic> decoded =
          jsonDecode(utf8.decode(capturedBodyBytes!)) as Map<String, dynamic>;
      expect(decoded['phone'], '09123456789');
      expect(decoded['platform'], 'اندروید ۱۵ • سطح API ۳۵ • آرم ۶۴ بیتی');
      expect(decoded['first_name'], 'آرمین');
    });

    test('GatewayClient.start over Android native transport delivers valid UTF-8 JSON with phone',
        () async {
      const MethodChannel channel = MethodChannel('ir.umbrella.app/native');
      Map<String, dynamic>? receivedJson;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'httpRequest') {
          final Map<Object?, Object?> args =
              call.arguments as Map<Object?, Object?>;
          final Uint8List bytes = args['bodyBytes'] as Uint8List;
          receivedJson =
              jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
          return <String, Object?>{
            'statusCode': 200,
            'headers': <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
            'bodyBytes': Uint8List.fromList(utf8.encode(jsonEncode(<String, dynamic>{
              'ok': true,
              'challenge': '0123456789abcdef0123456789abcdef',
              'stage': 'code_sent',
              'account_exists': true,
              'resend_after': 60,
            }))),
          };
        }
        return null;
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final GatewayClient client = GatewayClient(
        baseUrl: 'https://example.test/index.php?AppApi=',
        enableNativeTransport: true,
      );
      addTearDown(client.close);

      const DeviceProfile profile = DeviceProfile(
        hostname: 'گوشی کاربر',
        osDisplayVersion: '15',
        osBuild: 35,
        arch: 'arm64-v8a',
      );
      final SignInStart res = await client.start(
        phone: '09123456789',
        deviceId: 'device-1234567890abcdef',
        deviceName: profile.deviceName,
        platform: profile.platformLabel,
      );

      expect(res.stage, SignInStage.codeSent);
      expect(receivedJson, isNotNull);
      expect(receivedJson!['phone'], '09123456789');
      expect(receivedJson!['device_name'], 'گوشی کاربر');
      expect(receivedJson!['platform'], profile.platformLabel);
    });
  });

  group('Android widget smoke tests', () {
    testWidgets('LandingPage renders and fires onStart', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      bool started = false;
      final SettingsController settings = SettingsController(
        native: _FakeNative(),
        sound: _FakeSound(),
        window: _FakeWindow(),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsController>.value(
          value: settings,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: LandingPage(onStart: () => started = true),
            ),
          ),
        ),
      );
      await tester.pump();

      final Finder startBtn = find.text('شروع');
      expect(startBtn, findsOneWidget);
      await tester.ensureVisible(startBtn);
      await tester.tap(startBtn);
      await tester.pump();
      expect(started, isTrue);

      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    });

    testWidgets('DevicePage shows Android permissions and invokes NativeBridge actions',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final _FakeNative native = _FakeNative();
      final _FakeVpn vpn = _FakeVpn();
      final ToastController toasts = ToastController();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NativeBridge>.value(value: native),
            ChangeNotifierProvider<VpnController>.value(value: vpn),
            ChangeNotifierProvider<ToastController>.value(value: toasts),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(body: DevicePage()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder identityTab =
          find.byKey(const ValueKey<String>('device-tab-identity'));
      expect(identityTab, findsOneWidget);
      await tester.tap(identityTab);
      await tester.pumpAndSettle();

      expect(find.textContaining('بهینه سازی باتری'), findsWidgets);
      final Finder batteryAction = find.text('لغو محدودیت باتری');
      expect(batteryAction, findsOneWidget);
      await tester.ensureVisible(batteryAction);
      await tester.tap(batteryAction);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(native.batteryIgnoreCalls, 1);

      final Finder vpnSettingsAction = find.text('تنظیمات اتصال همیشگی');
      expect(vpnSettingsAction, findsOneWidget);
      await tester.ensureVisible(vpnSettingsAction);
      await tester.tap(vpnSettingsAction);
      await tester.pump();
      expect(native.vpnSettingsCalls, 1);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('ExitPage supports cancel, background keep, and clean shutdown',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final _FakeVpn vpn = _FakeVpn()..current = VpnStatus.connected;
      final _FakeWindow window = _FakeWindow();
      int cancelCount = 0;
      int exitCount = 0;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<WindowService>.value(value: window),
            ChangeNotifierProvider<VpnController>.value(value: vpn),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: ExitPage(
                  onCancelTap: () => cancelCount++,
                  onExit: () async => exitCount++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('نه، بمان'));
      await tester.pump();
      expect(cancelCount, 1);

      await tester.tap(find.text('انتقال به پس زمینه (اتصال بماند)'));
      await tester.pump();
      expect(cancelCount, 2);
      expect(window.hideCalled, isTrue);

      await tester.tap(find.text('بله، خارج شو'));
      await tester.pumpAndSettle();
      expect(vpn.shutdownCalled, isTrue);
      expect(exitCount, 1);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('SettingsPage renders battery section and split tunneling on Android',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final _FakeNative native = _FakeNative();
      final SettingsController settings = SettingsController(
        native: native,
        sound: _FakeSound(),
        window: _FakeWindow(),
      );
      final AuthController auth = AuthController(
        native: native,
        sound: _FakeSound(),
        tray: TrayService(native),
      );
      final PowerController power = PowerController(
        readStatus: () async => const BatteryPowerState(
          hasBattery: true,
          onBattery: true,
          energySaver: true,
          ignoringBatteryOptimizations: false,
        ),
      );
      final _FakeVpn vpn = _FakeVpn();
      final ToastController toasts = ToastController();
      await power.refresh();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NativeBridge>.value(value: native),
            ChangeNotifierProvider<SettingsController>.value(value: settings),
            ChangeNotifierProvider<AuthController>.value(value: auth),
            ChangeNotifierProvider<PowerController>.value(value: power),
            ChangeNotifierProvider<VpnController>.value(value: vpn),
            ChangeNotifierProvider<ToastController>.value(value: toasts),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(body: SettingsPage()),
            ),
          ),
        ),
      );
      await tester.pump();

      final Finder batteryMenu =
          find.byKey(const ValueKey<String>('settings-category-battery'));
      expect(batteryMenu, findsOneWidget);

      final Finder routingMenu =
          find.byKey(const ValueKey<String>('settings-category-routing'));
      await tester.ensureVisible(routingMenu);
      await tester.tap(routingMenu);
      await tester.pumpAndSettle();
      expect(find.text('مسیریابی برنامه های دستگاه'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('settings-back-button')));
      await tester.pumpAndSettle();

      final Finder inboundMenu =
          find.byKey(const ValueKey<String>('settings-category-inbound'));
      await tester.ensureVisible(inboundMenu);
      await tester.tap(inboundMenu);
      await tester.pumpAndSettle();
      expect(find.text('تونل کامل'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
      settings.dispose();
      auth.dispose();
      power.dispose();
    });

    testWidgets('QuickConnectionPanel exposes only Proxy and VPN modes on Android',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final SettingsController settings = SettingsController(
        native: _FakeNative(),
        sound: _FakeSound(),
        window: _FakeWindow(),
      );
      final _FakeVpn vpn = _FakeVpn();
      final ToastController toasts = ToastController();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsController>.value(value: settings),
            ChangeNotifierProvider<VpnController>.value(value: vpn),
            ChangeNotifierProvider<ToastController>.value(value: toasts),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: QuickConnectionPanel(enabled: true),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('پروکسی'), findsOneWidget);
      expect(find.text('تونل کامل'), findsWidgets);
      expect(find.text('پروکسی سیستم'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    });

    test('PersianDigitsFormatter preserves cursor when editing in the middle', () {
      const PersianDigitsFormatter formatter = PersianDigitsFormatter();
      const TextEditingValue oldVal = TextEditingValue(
        text: '۰۹۱۲۳۴۵۶۷۸',
        selection: TextSelection.collapsed(offset: 4),
      );
      const TextEditingValue newVal = TextEditingValue(
        text: '۰۹۱۲0۳۴۵۶۷۸',
        selection: TextSelection.collapsed(offset: 5),
      );
      final TextEditingValue result = formatter.formatEditUpdate(oldVal, newVal);
      expect(result.text, '۰۹۱۲۰۳۴۵۶۷۸');
      expect(result.selection, const TextSelection.collapsed(offset: 5));
    });

    testWidgets('LoginPage accepts +98, Arabic-Indic, and Persian mobile numbers cleanly',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await LocalStore.instance.remove(StoreKeys.lastPhone);

      final List<Map<String, dynamic>> sentStarts = <Map<String, dynamic>>[];
      final MockClient mockClient = MockClient((http.Request request) async {
        final Map<String, dynamic> payload =
            jsonDecode(request.body) as Map<String, dynamic>;
        sentStarts.add(payload);
        return http.Response.bytes(
          utf8.encode(jsonEncode(<String, dynamic>{
            'ok': true,
            'stage': 'needs_profile',
            'account_exists': false,
          })),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });

      final _FakeNative native = _FakeNative();
      final SettingsController settings = SettingsController(
        native: native,
        sound: _FakeSound(),
        window: _FakeWindow(),
      );
      final GatewayClient gateway = GatewayClient(
        baseUrl: 'https://example.test/index.php?AppApi=',
        client: mockClient,
        enableNativeTransport: false,
      );
      final AuthController auth = AuthController(
        native: native,
        gateway: gateway,
        sound: _FakeSound(),
        tray: TrayService(native),
      );
      await auth.restore();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsController>.value(value: settings),
            ChangeNotifierProvider<AuthController>.value(value: auth),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: LoginPage(),
            ),
          ),
        ),
      );
      await tester.pump();

      final Finder phoneField = find.byType(TextField).first;

      // Arabic-Indic digits from mobile keyboards must convert cleanly.
      await tester.enterText(phoneField, '٠٩٣٥١٢٣٤٥٦٧');
      await tester.pump();
      expect(find.text('۰۹۳۵۱۲۳۴۵۶۷'), findsOneWidget);
      expect(find.text('ایرانسل'), findsOneWidget);

      // +98 formatted mobile numbers from Android clipboard/autofill (>14 chars) must not truncate.
      await tester.enterText(phoneField, '+98 912 345 6789');
      await tester.pump();
      expect(find.text('+۹۸ ۹۱۲ ۳۴۵ ۶۷۸۹'), findsOneWidget);
      expect(find.text('همراه اول'), findsOneWidget);

      final Finder submitBtn = find.text('دریافت کد تایید');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(sentStarts, hasLength(1));
      expect(sentStarts.first['phone'], '09123456789');
      expect(sentStarts.first['platform'], contains('اندروید'));
      expect(sentStarts.first['platform'], contains('آرم'));
      expect(auth.error, isEmpty);
      expect(auth.phase, AuthPhase.profile);

      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      settings.dispose();
    });

    testWidgets(
      'ConnectPage renders cleanly on portrait phone, landscape phone, and tablet without overflow',
      (WidgetTester tester) async {
        void setViewport(Size size) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
        }

        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final _FakeNative native = _FakeNative();
        final _FakeVpn vpn = _FakeVpn();
        final SettingsController settings = SettingsController(
          native: native,
          sound: _FakeSound(),
          window: _FakeWindow(),
        );
        final AuthController auth = AuthController(
          native: native,
          sound: _FakeSound(),
          tray: TrayService(native),
        );
        final MockClient emptyClient = MockClient(
          (http.Request _) async => http.Response('[]', 200),
        );
        final SubscriptionController subs = SubscriptionController(
          vpn: vpn,
          auth: auth,
          client: emptyClient,
          enableNativeTransport: false,
        );
        final ToastController toasts = ToastController();

        Future<void> pumpViewport(Size size) async {
          setViewport(size);
          final List<String> errors = <String>[];
          final void Function(FlutterErrorDetails)? prev = FlutterError.onError;
          FlutterError.onError = (FlutterErrorDetails d) => errors.add(d.toString());
          try {
            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  Provider<NativeBridge>.value(value: native),
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
          } finally {
            FlutterError.onError = prev;
          }
          expect(errors, isEmpty, reason: 'ConnectPage $size:\n${errors.join('\n---\n')}');
          expect(tester.takeException(), isNull);
          expect(find.text('اتصال'), findsWidgets);
          expect(find.text('تنظیمات اتصال'), findsOneWidget);
        }

        await pumpViewport(const Size(360, 640));
        await pumpViewport(const Size(844, 390));
        await pumpViewport(const Size(1024, 768));

        await tester.pumpWidget(const SizedBox());
        subs.dispose();
        auth.dispose();
        settings.dispose();
      },
    );

    testWidgets(
      'AppShell adapts navigation between NavigationBar and SideNav across viewports without overflow',
      (WidgetTester tester) async {
        void setViewport(Size size) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
        }

        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await LocalStore.instance.write(
          StoreKeys.telegramChannelPromptAt,
          DateTime.now().toUtc().millisecondsSinceEpoch.toString(),
        );

        final _FakeNative native = _FakeNative();
        final _FakeWindow window = _FakeWindow();
        final _FakeVpn vpn = _FakeVpn();
        final SettingsController settings = SettingsController(
          native: native,
          sound: _FakeSound(),
          window: window,
        );
        final AuthController auth = AuthController(
          native: native,
          sound: _FakeSound(),
          tray: TrayService(native),
        );
        final MockClient emptyClient = MockClient(
          (http.Request _) async => http.Response('[]', 200),
        );
        final SubscriptionController subs = SubscriptionController(
          vpn: vpn,
          auth: auth,
          client: emptyClient,
          enableNativeTransport: false,
        );
        final UpdateController updates = UpdateController(
          native,
          service: UpdateService(client: emptyClient, preferredAbi: 'arm64-v8a'),
        );
        final ToastController toasts = ToastController();

        Widget buildShell() {
          return MultiProvider(
            providers: [
              Provider<NativeBridge>.value(value: native),
              Provider<WindowService>.value(value: window),
              ChangeNotifierProvider<SettingsController>.value(value: settings),
              ChangeNotifierProvider<AuthController>.value(value: auth),
              ChangeNotifierProvider<SubscriptionController>.value(value: subs),
              ChangeNotifierProvider<VpnController>.value(value: vpn),
              ChangeNotifierProvider<UpdateController>.value(value: updates),
              ChangeNotifierProvider<ToastController>.value(value: toasts),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: AppShell(windowService: window),
              ),
            ),
          );
        }

        final List<String> shellErrors360 = <String>[];
        final void Function(FlutterErrorDetails)? prevHandler = FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails details) {
          shellErrors360.add(details.toString());
        };
        try {
          setViewport(const Size(360, 640));
          await tester.pumpWidget(buildShell());
          await tester.pump();
        } finally {
          FlutterError.onError = prevHandler;
        }
        expect(shellErrors360, isEmpty, reason: shellErrors360.join('\n---\n'));
        expect(tester.takeException(), isNull);
        final BuildContext shellCtx360 = tester.element(find.byType(AppShell));
        expect(
          find.byType(NavigationBar),
          findsOneWidget,
          reason:
              'size=${MediaQuery.sizeOf(shellCtx360)} '
              'viewSize=${tester.view.physicalSize}/${tester.view.devicePixelRatio} '
              'sideNav=${find.byType(SideNav).evaluate().length} '
              'navTheme=${find.byType(NavigationBarTheme).evaluate().length} '
              'navDest=${find.byType(NavigationDestination).evaluate().length}',
        );
        expect(find.byType(SideNav), findsNothing);

        await tester.tap(find.text('بیشتر'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(tester.takeException(), isNull);
        expect(find.text('درباره'), findsOneWidget);
        expect(find.text('خروج'), findsOneWidget);
        Navigator.of(tester.element(find.text('درباره'))).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        setViewport(const Size(844, 390));
        await tester.pumpWidget(buildShell());
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(SideNav), findsOneWidget);

        setViewport(const Size(1024, 768));
        await tester.pumpWidget(buildShell());
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(SideNav), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        subs.dispose();
        updates.dispose();
        auth.dispose();
        settings.dispose();
      },
    );

    testWidgets(
      'SettingsPage, DevicePage, LogsPage, AccountPage, AboutPage, and UpdatesPage fit narrow 360x640 portrait phones without overflow',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        addTearDown(AppLogger.instance.clear);

        final _FakeNative native = _FakeNative();
        final _FakeVpn vpn = _FakeVpn();
        final SettingsController settings = SettingsController(
          native: native,
          sound: _FakeSound(),
          window: _FakeWindow(),
        );
        final AuthController auth = AuthController(
          native: native,
          sound: _FakeSound(),
          tray: TrayService(native),
        );
        final MockClient emptyClient = MockClient(
          (http.Request _) async => http.Response('[]', 200),
        );
        final SubscriptionController subs = SubscriptionController(
          vpn: vpn,
          auth: auth,
          client: emptyClient,
          enableNativeTransport: false,
        );
        final UpdateController updates = UpdateController(
          native,
          service: UpdateService(client: emptyClient, preferredAbi: 'arm64-v8a'),
        );
        final PowerController power = PowerController(
          readStatus: () async => const BatteryPowerState(
            hasBattery: true,
            onBattery: false,
            energySaver: false,
            ignoringBatteryOptimizations: true,
          ),
        );
        final ToastController toasts = ToastController();
        await power.refresh();

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<NativeBridge>.value(value: native),
              ChangeNotifierProvider<SettingsController>.value(value: settings),
              ChangeNotifierProvider<AuthController>.value(value: auth),
              ChangeNotifierProvider<PowerController>.value(value: power),
              ChangeNotifierProvider<VpnController>.value(value: vpn),
              ChangeNotifierProvider<ToastController>.value(value: toasts),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(body: SettingsPage()),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<NativeBridge>.value(value: native),
              ChangeNotifierProvider<VpnController>.value(value: vpn),
              ChangeNotifierProvider<ToastController>.value(value: toasts),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(body: DevicePage()),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        AppLogger.instance.add('نمونه خط گزارش برای بررسی ریسپانسیو گوشی باریک');
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsController>.value(value: settings),
              ChangeNotifierProvider<VpnController>.value(value: vpn),
              ChangeNotifierProvider<ToastController>.value(value: toasts),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(body: LogsPage()),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthController>.value(value: auth),
              ChangeNotifierProvider<SubscriptionController>.value(value: subs),
              ChangeNotifierProvider<ToastController>.value(value: toasts),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(body: AccountPage()),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(body: AboutPage()),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        final List<String> updatesErrors = <String>[];
        final void Function(FlutterErrorDetails)? prevUpdatesHandler = FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails details) {
          updatesErrors.add(details.toString());
        };
        try {
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
          await tester.pump(const Duration(milliseconds: 50));
        } finally {
          FlutterError.onError = prevUpdatesHandler;
        }
        expect(updatesErrors, isEmpty, reason: updatesErrors.join('\n---\n'));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        subs.dispose();
        updates.dispose();
        power.dispose();
        auth.dispose();
        settings.dispose();
      },
    );

    test('CoreRuntime.compile returns parsed.json for Android and fails closed', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp('umbrella_compile_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final File linksFile = File('${tempDir.path}${Platform.pathSeparator}prepared-links.txt');
      final List<String> autoLinks = List<String>.generate(
        84,
        (int i) =>
            'vless://11111111-1111-1111-1111-1111111111${i.toString().padLeft(2, '0')}@example.com:${443 + i}#Auto$i',
      );
      await linksFile.writeAsString('${autoLinks.join('\n')}\n', flush: true);
      final File settingsFile = File('${tempDir.path}${Platform.pathSeparator}settings.json');
      await settingsFile.writeAsString('{}', flush: true);

      final _TestCoreNative okNative = _TestCoreNative(
        parseResult: (
          ok: true,
          content: '{"outbounds":[{"type":"vless","tag":"Auto0"}]}',
          message: '',
        ),
      );
      final File compiled = await CoreRuntime.compile(
        runDir: tempDir.path,
        linksPath: linksFile.path,
        settingsPath: settingsFile.path,
        native: okNative,
        cancelled: () => false,
        forceAndroidPlatform: true,
      );
      expect(compiled.path, endsWith('${Platform.pathSeparator}parsed.json'));
      expect(await compiled.readAsString(), contains('"outbounds"'));

      final _TestCoreNative failNative = _TestCoreNative(
        parseResult: (ok: false, content: '', message: ''),
      );
      await expectLater(
        () => CoreRuntime.compile(
          runDir: tempDir.path,
          linksPath: linksFile.path,
          settingsPath: settingsFile.path,
          native: failNative,
          cancelled: () => false,
          forceAndroidPlatform: true,
        ),
        throwsA(isA<FormatException>()),
      );

      final _TestCoreNative emptyNative = _TestCoreNative(
        parseResult: (ok: true, content: '', message: ''),
      );
      await expectLater(
        () => CoreRuntime.compile(
          runDir: tempDir.path,
          linksPath: linksFile.path,
          settingsPath: settingsFile.path,
          native: emptyNative,
          cancelled: () => false,
          forceAndroidPlatform: true,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('VpnController resets stale core log and reports early native stop alert', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await LocalStore.instance.init();

      final Directory tempDir = await Directory.systemTemp.createTemp('umbrella_vpn_ctrl_');
      addTearDown(() async {
        AppLogger.instance.clear();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final String runDirPath = '${tempDir.path}${Platform.pathSeparator}run';
      await Directory(runDirPath).create(recursive: true);
      final File staleLog = File('$runDirPath${Platform.pathSeparator}umbrella-tun-core.log');
      await staleLog.writeAsString(
        'FATAL endpoint/awg[umbrella-direct-profile]: stale wireguard error\n',
        flush: true,
      );

      final _TestCoreNative native = _TestCoreNative(
        parseResult: (
          ok: true,
          content: '{"outbounds":[{"type":"vless","tag":"Node1"}]}',
          message: '',
        ),
      );
      final _TestProvisioner provisioner = _TestProvisioner(tempDir.path);
      await provisioner.init(native);
      final VpnController controller = VpnController(
        native: native,
        ipService: _FakeIpService(),
        sound: _FakeSound(),
        tray: TrayService(native),
        provisioner: provisioner,
        settings: const AppSettings(
          corePreference: CorePreference.tun,
          selectionMode: SelectionMode.auto,
          autoFailover: true,
        ),
      );
      addTearDown(() async {
        controller.dispose();
        await native.closeEvents();
      });

      const VpnNode vlessNode = VpnNode(
        id: 'n1',
        name: 'Auto Node 1',
        protocol: NodeProtocol.vless,
        host: '1.1.1.1',
        port: 443,
        sourceId: 'sub1',
        raw: 'vless://11111111-1111-1111-1111-111111111111@1.1.1.1:443#Auto1',
        params: <String, dynamic>{'uuid': '11111111-1111-1111-1111-111111111111'},
      );
      await controller.applyNodes(<VpnNode>[vlessNode], measure: false);

      native.onStartEmit = () {
        native.coreStatus = <String, dynamic>{
          'status': 'Stopped',
          'active': false,
          'starting': false,
          'stopping': false,
          'lastError': 'start service failed: invalid inbound',
        };
        native.emitServiceEvent(
          const AndroidServiceEvent(
            type: 'alert',
            status: '',
            message: 'start service failed: invalid inbound',
          ),
        );
        native.emitServiceEvent(
          const AndroidServiceEvent(
            type: 'status',
            status: 'Stopped',
            message: 'start service failed: invalid inbound',
          ),
        );
      };

      final ConnectOutcome outcome = await controller.connect();
      expect(outcome.ok, isFalse);
      expect(native.startedConfigPaths, hasLength(1));
      expect(await staleLog.readAsString(), isEmpty);

      final String allLogs =
          AppLogger.instance.lines.map((LogLine e) => e.message).join('\n');
      expect(allLogs, contains('پیش از آماده شدن تونل متوقف شد'));
      expect(allLogs, contains('invalid inbound'));
      expect(allLogs, isNot(contains('آماده نشد')));
      expect(allLogs, isNot(contains('umbrella-direct-profile')));
    });

    test('Android native VPN lifecycle contracts prevent Start() race and stale iterators', () {
      final String vpnControllerSrc = File(
        '${Directory.current.path}/lib/vpn/vpn_controller.dart',
      ).readAsStringSync();
      expect(vpnControllerSrc, contains('configPath: compiledConfig.path'));
      expect(vpnControllerSrc, isNot(contains('configPath: sessionLinks.path')));

      final String boxService = File(
        '${Directory.current.path}/android/app/src/main/kotlin/ir/umbrella/vpn/bg/BoxService.kt',
      ).readAsStringSync();
      expect(boxService, contains('client.StartService().execute('));
      expect(boxService, isNot(contains('client.Start().execute(')));
      expect(boxService, contains('if (status.value != Status.Started) return'));
      expect(boxService, contains('var activePlatformInterface'));
      expect(boxService, contains('var lastStartError'));
      expect(boxService, contains('mobileLock'));

      final String methodHandler = File(
        '${Directory.current.path}/android/app/src/main/kotlin/ir/umbrella/vpn/MethodHandler.kt',
      ).readAsStringSync();
      expect(methodHandler, contains('awaitServiceStopped('));
      expect(methodHandler, contains('ensureUtilityPortReady()'));
      expect(methodHandler, contains('activity.reconnectServiceObserver('));
      expect(
        methodHandler.indexOf('BoxService.start(') <
            methodHandler.indexOf('activity.reconnectServiceObserver('),
        isTrue,
      );

      final String vpnService = File(
        '${Directory.current.path}/android/app/src/main/kotlin/ir/umbrella/vpn/bg/VPNService.kt',
      ).readAsStringSync();
      expect(vpnService, contains('var hasInet4 = false'));
      expect(vpnService, contains('var hasInet6 = false'));
      expect(vpnService, contains('else if (hasInet4)'));
      expect(vpnService, contains('else if (hasInet6)'));

      final String grpcClientProvider = File(
        '${Directory.current.path}/android/app/src/main/kotlin/ir/umbrella/vpn/utils/GrpcClientProvider.kt',
      ).readAsStringSync();
      expect(grpcClientProvider, contains('.callTimeout(callTimeoutSeconds, TimeUnit.SECONDS)'));
    });
  });
}

class _TestCoreNative extends _FakeNative {
  _TestCoreNative({required this.parseResult});

  final ({bool ok, String content, String message}) parseResult;
  final StreamController<AndroidServiceEvent> _events =
      StreamController<AndroidServiceEvent>.broadcast();
  final List<String> startedConfigPaths = <String>[];
  Map<String, dynamic> coreStatus = <String, dynamic>{
    'status': 'Stopped',
    'active': false,
    'starting': false,
    'stopping': false,
  };
  VoidCallback? onStartEmit;

  void emitServiceEvent(AndroidServiceEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  Future<void> closeEvents() async {
    if (!_events.isClosed) {
      await _events.close();
    }
  }

  @override
  Stream<AndroidServiceEvent> serviceEvents() => _events.stream;

  @override
  Future<({bool ok, String content, String message})> parseConfig({
    String content = '',
    String configPath = '',
    String tempPath = '',
    bool debug = false,
  }) async =>
      parseResult;

  @override
  Future<Map<String, dynamic>> startCore({
    required String configPath,
    required String settingsJson,
    required String profileName,
    String serviceMode = 'vpn',
  }) async {
    startedConfigPaths.add(configPath);
    coreStatus = <String, dynamic>{
      'status': 'Starting',
      'active': false,
      'starting': true,
      'stopping': false,
    };
    scheduleMicrotask(() => onStartEmit?.call());
    return <String, dynamic>{'ok': true, 'serviceMode': serviceMode};
  }

  @override
  Future<bool> stopCore() async {
    coreStatus = <String, dynamic>{
      'status': 'Stopped',
      'active': false,
      'starting': false,
      'stopping': false,
    };
    return true;
  }

  @override
  Future<Map<String, dynamic>> getCoreStatus() async => coreStatus;

  @override
  Future<int> tcpPing(String host, int port, {int timeoutMs = 1500}) async => -1;

  @override
  Future<bool> flushDns() async => true;

  @override
  Future<Map<String, dynamic>> setupDirectories({
    String? baseDir,
    String? workingDir,
    String? tempDir,
    int? grpcServicePort,
    int? grpcUtilityPort,
    bool? debug,
  }) async =>
      <String, dynamic>{'ok': true};
}

class _TestProvisioner extends CoreProvisioner {
  _TestProvisioner(this._root);

  final String _root;

  @override
  String get dataDir => _root;

  @override
  Future<void> init([NativeBridge? native]) async {}

  @override
  Future<String?> locateBinary(String binary) async => 'android://$binary';

  @override
  Future<List<CoreInfo>> missingRequired() async => const <CoreInfo>[];

  @override
  Future<bool> provision(CoreInfo core) async => true;
}

class _FakeIpService extends IpService {
  _FakeIpService();

  @override
  Future<GeoInfo> fetch({
    bool force = false,
    String proxy = '',
    String proxyUser = '',
    String proxyPassword = '',
  }) async =>
      GeoInfo.empty;
}
