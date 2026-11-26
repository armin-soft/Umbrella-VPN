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
import 'package:umbrella_vpn/ui/widgets/common.dart';
import 'package:umbrella_vpn/ui/widgets/content_control.dart';
import 'package:umbrella_vpn/ui/widgets/quick_connection_panel.dart';
import 'package:umbrella_vpn/ui/widgets/shell_widgets.dart';
import 'package:umbrella_vpn/vpn/balancer.dart';
import 'package:umbrella_vpn/vpn/clash_api.dart';
import 'package:umbrella_vpn/vpn/core_runtime.dart';
import 'package:umbrella_vpn/vpn/cores.dart';
import 'package:umbrella_vpn/vpn/runtime_config.dart';
import 'package:umbrella_vpn/vpn/umbrella_core.dart';
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
  Future<bool> startSmsUserConsent() async => false;

  @override
  Future<void> stopSmsUserConsent() async {}

  @override
  Future<void> setNotificationsEnabled(bool enabled) async {}

  @override
  Future<void> updateConnectedNotification({
    required String title,
    required String body,
    bool alert = false,
  }) async {}

  @override
  Future<void> showTrayBalloon({
    required String title,
    required String body,
    bool warning = false,
  }) async {}

  @override
  Stream<String> smsCodeEvents() => const Stream<String>.empty();

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
        os: 'اندروید ۱۵ (سطح ۳۵)',
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
  Future<bool> requestStorageScanAccess() async => true;

  @override
  Future<int> closeConflictingVpns() async => 0;

  @override
  Future<bool> openExternalUrl(
    String url, {
    String title = '',
    String body = '',
  }) async =>
      true;

  @override
  Future<bool> stopCore() async => true;

  @override
  Future<bool> shutdownCores() async => true;

  @override
  Future<Map<String, dynamic>> getCoreStatus() async =>
      const <String, dynamic>{};

  @override
  Stream<AndroidServiceEvent> serviceEvents() =>
      const Stream<AndroidServiceEvent>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSound implements SoundService {
  @override
  bool enabled = true;

  final List<String> played = <String>[];

  @override
  Future<void> play(String name) async {
    if (enabled) {
      played.add(name);
    }
  }

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
  bool get autoSession => false;

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
  void setBatterySaving(bool value) {}

  @override
  void setAppVisible(bool visible) {}

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
      expect(manifest, contains('android.permission.REQUEST_INSTALL_PACKAGES'));
      expect(manifest, isNot(contains('installPackagesPermission')));
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

      final String methodHandler = File(
        'android/app/src/main/kotlin/ir/umbrella/vpn/MethodHandler.kt',
      ).readAsStringSync();
      expect(methodHandler, contains('getPackageArchiveInfo'));
      expect(methodHandler, contains('ClipData.newRawUri'));
      expect(methodHandler, contains('signature_mismatch'));
      expect(methodHandler, contains('invalid_apk_archive'));
      expect(methodHandler, contains('install_permission_required'));

      final String updateCtrl =
          File('lib/state/update_controller.dart').readAsStringSync();
      expect(updateCtrl, contains('resumePendingInstallIfPermitted'));
      expect(updateCtrl, contains('installDetailed'));
      final int dlInstallAt = updateCtrl.indexOf('Future<bool> downloadAndInstall()');
      final String dlInstallBody = updateCtrl.substring(
        dlInstallAt,
        updateCtrl.indexOf('Future<bool> openDownloadPage()', dlInstallAt),
      );
      expect(dlInstallBody, isNot(contains('SafeUrlLauncher.open')));

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
          expect(find.textContaining('اشخاص ثالث'), findsNothing);
          expect(find.textContaining('سلب مسئولیت'), findsNothing);

          expect(
            find.byKey(const ValueKey<String>('connection-profile-user-sub')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey<String>('connection-profile-user-wireguard')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey<String>('connection-profile-user-amnezia')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey<String>('connection-profile-user-mieru')),
            findsNothing,
          );
          expect(
            find.descendant(
              of: find.byType(ConnectPage),
              matching: find.byType(SingleChildScrollView),
            ),
            findsNothing,
          );
          if (size.width <= size.height) {
            final double minOrbSize =
                size == const Size(360, 640) ? 124.0 : 145.0;
            final double minRenderedOrb =
                size == const Size(360, 640) ? 105.0 : 145.0;
            final StatusOrb orbWidget = tester.widget<StatusOrb>(
              find.byType(StatusOrb),
            );
            expect(orbWidget.size, greaterThanOrEqualTo(minOrbSize));
            expect(
              tester.getSize(find.byType(StatusOrb)).height,
              greaterThanOrEqualTo(minRenderedOrb),
            );
            if (size != const Size(360, 640)) {
              expect(
                tester.getSize(find.byType(StatusOrb)).height,
                closeTo(orbWidget.size, 0.5),
              );
            }
          }
        }

        await pumpViewport(const Size(360, 640));
        await pumpViewport(const Size(390, 844));
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
        expect(find.text('دستگاه من'), findsOneWidget);
        expect(find.text('به روز رسانی'), findsOneWidget);
        expect(find.text('درباره'), findsOneWidget);
        expect(find.text('خروج'), findsNothing);
        Navigator.of(tester.element(find.text('درباره'))).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        final String shellSource = File('lib/ui/shell/app_shell.dart').readAsStringSync();
        expect(shellSource, isNot(contains("title: 'خروج'")));
        expect(shellSource, isNot(contains('ExitPage(')));

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
      expect(okNative.parseCalls, 1);

      // Second call with identical links reuses parsed.json via SHA-256 cache.
      final File cached = await CoreRuntime.compile(
        runDir: tempDir.path,
        linksPath: linksFile.path,
        settingsPath: settingsFile.path,
        native: okNative,
        cancelled: () => false,
        forceAndroidPlatform: true,
      );
      expect(cached.path, compiled.path);
      expect(okNative.parseCalls, 1);

      // Modified links invalidate parsed.cache.sha256 and re-invoke parseConfig.
      await linksFile.writeAsString('${autoLinks.take(4).join('\n')}\n', flush: true);
      await CoreRuntime.compile(
        runDir: tempDir.path,
        linksPath: linksFile.path,
        settingsPath: settingsFile.path,
        native: okNative,
        cancelled: () => false,
        forceAndroidPlatform: true,
      );
      expect(okNative.parseCalls, 2);

      // Verify Android fast StartService settings omit remote .srs URLs & auto-rules,
      // while RuntimeConfig.finalize injects bundled filter-ads + geoip-ir/geosite-ir offline.
      const AppSettings adAndIrSettings = AppSettings(
        blockAds: true,
        routingRegion: RoutingRegion.ir,
      );
      final Map<String, dynamic> fastStartSettings = UmbrellaCore.settingsJson(
        tun: true,
        systemProxy: false,
        port: 12334,
        networkSettings: adAndIrSettings,
        contentFilter: const FilterSettings(bypassIran: true),
        includeFilterRuleSets: false,
      );
      expect(fastStartSettings['region'], 'other');
      expect(fastStartSettings['block-ads'], isFalse);
      expect(jsonEncode(fastStartSettings), isNot(contains('.srs')));

      final Map<String, dynamic> fullHotReloadSettings = UmbrellaCore.settingsJson(
        tun: true,
        systemProxy: false,
        port: 12334,
        networkSettings: adAndIrSettings,
        contentFilter: const FilterSettings(bypassIran: true),
        includeFilterRuleSets: true,
      );
      expect(fullHotReloadSettings['region'], 'ir');
      expect(fullHotReloadSettings['block-ads'], isTrue);

      final Map<String, dynamic> offlineRuntime = <String, dynamic>{
        'experimental': <String, dynamic>{'monitoring': <String, dynamic>{}},
        'outbounds': <dynamic>[
          <String, dynamic>{'tag': 'direct', 'type': 'direct'},
          <String, dynamic>{'tag': 'select', 'type': 'selector'},
        ],
        'dns': <String, dynamic>{'rules': <dynamic>[]},
        'route': <String, dynamic>{
          'rule_set': <dynamic>[],
          'rules': <dynamic>[
            <String, dynamic>{'action': 'sniff'},
          ],
        },
      };
      RuntimeConfig.finalize(
        offlineRuntime,
        profileTags: const <String>{},
        coreSettings: fullHotReloadSettings,
        localRuleSetPaths: const <String, String>{
          'filter-ads.srs': '/data/user/0/ir.umbrella.vpn/files/data/filter-ads.srs',
          'geoip-ir.srs': '/data/user/0/ir.umbrella.vpn/files/data/geoip-ir.srs',
          'geosite-ir.srs': '/data/user/0/ir.umbrella.vpn/files/data/geosite-ir.srs',
        },
      );
      final List<Map<String, dynamic>> resolvedSets =
          ((offlineRuntime['route'] as Map<String, dynamic>)['rule_set']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>();
      expect(
        resolvedSets.any(
          (Map<String, dynamic> r) =>
              r['tag'] == 'filter-ads' && r['type'] == 'local',
        ),
        isTrue,
      );
      expect(
        resolvedSets.any(
          (Map<String, dynamic> r) =>
              r['tag'] == 'geosite-ir' && r['type'] == 'local',
        ),
        isTrue,
      );

      final String scannerKt = File(
        '${Directory.current.path}/android/app/src/main/kotlin/ir/umbrella/vpn/UmbrellaSecurityScanner.kt',
      ).readAsStringSync();
      expect(scannerKt, contains('quick: Boolean = false'));
      expect(scannerKt, contains('cleanFileCache'));
      expect(scannerKt, contains('appLabelCache'));
      expect(scannerKt, contains('readHeadAndTailBytes'));
      expect(scannerKt, contains('invalidateCleanFileCache'));

      final String methodHandlerKt = File(
        '${Directory.current.path}/android/app/src/main/kotlin/ir/umbrella/vpn/MethodHandler.kt',
      ).readAsStringSync();
      expect(methodHandlerKt, contains('call.argument<Boolean>("quick")'));

      // NativeBridge.quickScanDeviceSecurity returns null for test subclasses.
      expect(await NativeBridge.quickScanDeviceSecurity(okNative), isNull);

      final _TestCoreNative failNative = _TestCoreNative(
        parseResult: (ok: false, content: '', message: ''),
      );
      await expectLater(
        () => CoreRuntime.compile(
          runDir: tempDir.path,
          linksPath: linksFile.path,
          settingsPath: settingsFile.path,
          native: failNative,
          useCache: false,
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
          useCache: false,
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

    test('NativeBridge.extractSmsVerificationCode parses Persian, Arabic-Indic, and Latin OTPs', () {
      expect(
        NativeBridge.extractSmsVerificationCode('کد تایید شما در آمبرلا: ۴۸۲۹۱۰'),
        '482910',
      );
      expect(
        NativeBridge.extractSmsVerificationCode('رمز یکبار مصرف شما ٤٨٢٩١٠ می باشد'),
        '482910',
      );
      expect(
        NativeBridge.extractSmsVerificationCode('Umbrella OTP in 1405: 903158'),
        '903158',
      );
      expect(
        NativeBridge.extractSmsVerificationCode('Code: 73915'),
        '73915',
      );
      expect(
        NativeBridge.extractSmsVerificationCode('پیامک اطلاع رسانی بدون کد'),
        isEmpty,
      );
    });

    testWidgets(
      'LoginPage reads SMS User Consent OTP automatically, normalizes Persian digits, and cleans up listener',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await LocalStore.instance.remove(StoreKeys.lastPhone);

        final List<Map<String, dynamic>> verifyPayloads = <Map<String, dynamic>>[];
        final MockClient mockClient = MockClient((http.Request request) async {
          final String route = request.url.queryParameters['AppApi'] ?? request.url.path;
          final Map<String, dynamic> payload =
              jsonDecode(request.body) as Map<String, dynamic>;
          if (route.contains('auth/verify')) {
            verifyPayloads.add(payload);
            return http.Response.bytes(
              utf8.encode(jsonEncode(<String, dynamic>{
                'ok': true,
                'verified': true,
                'challenge': 'ch-sms-1',
                'stage': 'awaiting_telegram',
                'bot': 'https://t.me/UmbrellaVpnBot',
                'message': 'در انتظار تایید در تلگرام',
              })),
              200,
              headers: const <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          return http.Response.bytes(
            utf8.encode(jsonEncode(<String, dynamic>{
              'ok': true,
              'challenge': 'ch-sms-1',
              'stage': 'code_sent',
              'account_exists': true,
              'resend_after': 120,
            })),
            200,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        });

        final _SmsTestNative smsNative = _SmsTestNative();
        final _FakeSound sound = _FakeSound();
        final SettingsController settings = SettingsController(
          native: smsNative,
          sound: sound,
          window: _FakeWindow(),
        );
        final GatewayClient gateway = GatewayClient(
          baseUrl: 'https://example.test/index.php?AppApi=',
          client: mockClient,
          enableNativeTransport: false,
        );
        final AuthController auth = AuthController(
          native: smsNative,
          gateway: gateway,
          sound: sound,
          tray: TrayService(smsNative),
        );
        addTearDown(() async {
          await smsNative.closeSms();
        });
        await auth.restore();

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<NativeBridge>.value(value: smsNative),
              Provider<SoundService>.value(value: sound),
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

        await tester.enterText(find.byType(TextField).first, '09123456789');
        await tester.pump();
        final Finder submitBtn = find.text('دریافت کد تایید');
        await tester.ensureVisible(submitBtn);
        await tester.tap(submitBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(auth.phase, AuthPhase.code);
        expect(smsNative.smsStartCalls, 1);
        expect(find.textContaining('خواندن خودکار کد'), findsOneWidget);
        expect(find.text('جای گذاری کد'), findsOneWidget);
        expect(sound.played, contains('click'));

        smsNative.emitSmsMessage('کد ورود شما به آمبرلا: ۴۸۲۹۱۰');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(verifyPayloads, hasLength(1));
        expect(verifyPayloads.first['challenge'], 'ch-sms-1');
        expect(verifyPayloads.first['code'], '482910');
        expect(auth.phase, AuthPhase.telegram);
        expect(smsNative.smsStopCalls, greaterThanOrEqualTo(1));

        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        auth.dispose();
        settings.dispose();
        await smsNative.closeSms();
      },
    );

    testWidgets(
      'Android UI controls and navigation emit click sounds and avoid silent text clipping',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await LocalStore.instance.write(
          StoreKeys.telegramChannelPromptAt,
          DateTime.now().toUtc().millisecondsSinceEpoch.toString(),
        );

        final _FakeSound sound = _FakeSound();
        int clicks = 0;
        String selectVal = 'one';

        await tester.pumpWidget(
          Provider<SoundService>.value(
            value: sound,
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Column(
                      children: <Widget>[
                        GradientButton(
                          label: 'دکمه اصلی',
                          onPressed: () => clicks++,
                        ),
                        IconAction(
                          icon: Icons.refresh_rounded,
                          tooltip: 'تازه سازی',
                          onTap: () => clicks++,
                        ),
                        ToggleRow(
                          icon: Icons.volume_up_rounded,
                          title: 'صدای برنامه',
                          value: true,
                          onChanged: (_) => clicks++,
                        ),
                        GlassCard(
                          onTap: () => clicks++,
                          child: const Text('کارت شیشه ای'),
                        ),
                        SelectionCard(
                          icon: Icons.bolt_rounded,
                          title: 'حالت انتخاب',
                          description: 'توضیح کوتاه',
                          selected: false,
                          onTap: () => clicks++,
                        ),
                        InfoRow(
                          icon: Icons.info_outline_rounded,
                          label: 'وضعیت',
                          value: 'جزئیات کامل',
                          onTap: () => clicks++,
                        ),
                        AnchoredSelectField<String>(
                          label: 'انتخابگر',
                          value: selectVal,
                          options: const <SelectOption<String>>[
                            SelectOption<String>(value: 'one', label: 'مورد اول'),
                            SelectOption<String>(value: 'two', label: 'مورد دوم'),
                          ],
                          onChanged: (String next) {
                            selectVal = next;
                            clicks++;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        for (final Finder target in <Finder>[
          find.text('دکمه اصلی'),
          find.byIcon(Icons.refresh_rounded),
          find.text('صدای برنامه'),
          find.text('کارت شیشه ای'),
          find.text('حالت انتخاب'),
          find.text('جزئیات کامل'),
          find.text('مورد اول'),
        ]) {
          await tester.ensureVisible(target);
          await tester.tap(target);
        }
        await tester.pumpAndSettle();
        await tester.tap(find.text('مورد دوم').last);
        await tester.pumpAndSettle();

        expect(clicks, 7);
        expect(selectVal, 'two');
        expect(sound.played, everyElement('click'));
        expect(sound.played.length, greaterThanOrEqualTo(7));

        sound.enabled = false;
        final int mutedCount = sound.played.length;
        await tester.ensureVisible(find.text('دکمه اصلی'));
        await tester.tap(find.text('دکمه اصلی'));
        expect(clicks, 8);
        expect(sound.played.length, mutedCount);

        // Verify AppShell bottom NavigationBar tab changes also play click sound.
        sound.enabled = true;
        sound.played.clear();
        final _FakeNative native = _FakeNative();
        final _FakeWindow window = _FakeWindow();
        final _FakeVpn vpn = _FakeVpn();
        final SettingsController settings = SettingsController(
          native: native,
          sound: sound,
          window: window,
        );
        final AuthController auth = AuthController(
          native: native,
          sound: sound,
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

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<NativeBridge>.value(value: native),
              Provider<WindowService>.value(value: window),
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
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: AppShell(windowService: window),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('گزارش ها'));
        await tester.pump();
        expect(sound.played, contains('click'));
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        subs.dispose();
        updates.dispose();
        auth.dispose();
        settings.dispose();
      },
    );

    test('Android UI omits TextOverflow truncation and enforces SMS Consent & SoundService contracts', () {
      final List<File> uiFiles = Directory('${Directory.current.path}/lib/ui')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList();
      expect(uiFiles, isNotEmpty);
      for (final File file in uiFiles) {
        final String src = file.readAsStringSync();
        expect(
          src.contains('TextOverflow'),
          isFalse,
          reason: '${file.path} should wrap or scale text instead of clipping with TextOverflow',
        );
        expect(
          RegExp(r'\boverflow\s*:').hasMatch(src),
          isFalse,
          reason: '${file.path} should not clip text using overflow:',
        );
      }

      final String servicesSrc = File(
        '${Directory.current.path}/lib/platform/services.dart',
      ).readAsStringSync();
      expect(servicesSrc, contains('_clickPlayer'));
      expect(servicesSrc, contains('PlayerMode.lowLatency'));
      expect(servicesSrc, contains('AndroidAudioFocus.none'));
      expect(servicesSrc, contains('Duration(milliseconds: 40)'));

      final String gradleSrc = File(
        '${Directory.current.path}/android/app/build.gradle',
      ).readAsStringSync();
      expect(gradleSrc, contains('play-services-auth-api-phone'));

      final String mainActivitySrc = File(
        '${Directory.current.path}/android/app/src/main/kotlin/ir/umbrella/vpn/MainActivity.kt',
      ).readAsStringSync();
      expect(mainActivitySrc, contains('startSmsUserConsent'));
      expect(mainActivitySrc, contains('REQ_SMS_USER_CONSENT'));
      expect(mainActivitySrc, contains('SmsRetriever.SEND_PERMISSION'));

      final String manifestSrc = File(
        '${Directory.current.path}/android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifestSrc, isNot(contains('android.permission.READ_SMS')));
      expect(manifestSrc, isNot(contains('android.permission.RECEIVE_SMS')));
    });

    test('Android connected notification matches Windows logo/copy and Persian formatting', () async {
      final String root = Directory.current.path;

      // ۱. وجود تصاویر لوگوی نوتیفیکیشن استخراج شده از آیکون های ویندوز
      for (final String name in <String>[
        'ic_notif_connected.png',
        'ic_notif_connecting.png',
        'ic_notif_failed.png',
        'ic_notif_umbrella.png',
      ]) {
        final File icon = File(
          '$root/android/app/src/main/res/drawable-nodpi/$name',
        );
        expect(icon.existsSync(), isTrue, reason: '$name باید در drawable-nodpi موجود باشد');
        expect(icon.lengthSync(), greaterThan(1000));
      }

      // ۲. بررسی ساختار نوتیفیکیشن بومی اندروید (هماهنگ با بالون ویندوز و بدون افشای سرور یا سرعت انگلیسی)
      final String notifKt = File(
        '$root/android/app/src/main/kotlin/ir/umbrella/vpn/bg/ServiceNotification.kt',
      ).readAsStringSync();
      expect(notifKt, contains('ic_notif_connected'));
      expect(notifKt, contains('ic_notif_connecting'));
      expect(notifKt, contains('ic_notif_failed'));
      expect(notifKt, contains('updateConnectedNotification'));
      expect(notifKt, contains('showStandaloneBalloon'));
      expect(notifKt, contains('sanitizePersian'));
      expect(notifKt, contains('IMPORTANCE_HIGH'));
      expect(notifKt, isNot(contains('current_profile')));
      expect(notifKt, isNot(contains('current_outbound')));
      expect(notifKt, isNot(contains('KB/s')));

      final String stringsXml = File(
        '$root/android/app/src/main/res/values/strings.xml',
      ).readAsStringSync();
      expect(stringsXml, contains('<string name="status_connected_title">به آمبرلا متصل شد</string>'));
      expect(stringsXml, contains('<string name="status_started">اتصال امن برقرار است</string>'));
      expect(stringsXml, isNot(contains('\u200c')));
      expect(stringsXml, isNot(contains('VPN')));

      final String vpnServiceKt = File(
        '$root/android/app/src/main/kotlin/ir/umbrella/vpn/bg/VPNService.kt',
      ).readAsStringSync();
      expect(vpnServiceKt, contains('.setSession("فیلترشکن آمبرلا")'));

      final String vpnDart = File(
        '$root/lib/vpn/vpn_controller.dart',
      ).readAsStringSync();
      expect(vpnDart, contains('profileName: AppConfig.appName'));
      expect(vpnDart, isNot(contains('profileName: _activeNode?.name')));
      expect(vpnDart, contains('_syncConnectedNotificationPing'));

      // ۳. بررسی ارسال صحیح بالون و آپدیت زنده پینگ به کانال بومی
      const MethodChannel channel = MethodChannel('ir.umbrella.app/native');
      final List<MethodCall> calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        calls.add(call);
        return true;
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final TrayService tray = TrayService(NativeBridge());
      await tray.init();
      await tray.balloon('به آمبرلا متصل شد', 'پینگ 145 میلی ثانیه');
      await tray.syncConnectedNotification(body: 'پینگ 98 میلی ثانیه');

      tray.notificationsEnabled = false;
      await tray.balloon('تغییر مسیر اتصال', 'مسیر جایگزین فعال شد');

      final MethodCall balloonCall = calls.firstWhere(
        (MethodCall c) => c.method == 'showTrayBalloon',
      );
      final Map<Object?, Object?> balloonArgs =
          balloonCall.arguments as Map<Object?, Object?>;
      expect(balloonArgs['title'], 'به آمبرلا متصل شد');
      expect(balloonArgs['body'], 'پینگ ۱۴۵ میلی ثانیه');
      expect(balloonArgs['warning'], isFalse);

      final MethodCall updateCall = calls.firstWhere(
        (MethodCall c) => c.method == 'updateConnectedNotification',
      );
      final Map<Object?, Object?> updateArgs =
          updateCall.arguments as Map<Object?, Object?>;
      expect(updateArgs['title'], 'به آمبرلا متصل شد');
      expect(updateArgs['body'], 'پینگ ۹۸ میلی ثانیه');
      expect(updateArgs['alert'], isFalse);

      expect(
        calls.where((MethodCall c) => c.method == 'showTrayBalloon').length,
        1,
      );

      // ۴. نبود نیم فاصله و نبود سلب مسئولیت اشخاص ثالث در رابط کاربری و مدل ها
      final String connectDart = File(
        '$root/lib/ui/pages/connect_page.dart',
      ).readAsStringSync();
      final String emergencyDart = File(
        '$root/lib/ui/widgets/emergency_list.dart',
      ).readAsStringSync();
      expect(connectDart, isNot(contains('اشخاص ثالث')));
      expect(connectDart, isNot(contains('سلب مسئولیت')));
      expect(connectDart, isNot(contains('denseChips')));
      expect(connectDart, isNot(contains('MaterialTapTargetSize.shrinkWrap')));
      expect(emergencyDart, isNot(contains('اشخاص ثالث')));

      for (final Directory dir in <Directory>[
        Directory('$root/lib/ui'),
        Directory('$root/lib/vpn'),
        Directory('$root/lib/state'),
      ]) {
        for (final File f in dir.listSync(recursive: true).whereType<File>()) {
          if (!f.path.endsWith('.dart')) continue;
          final String text = f.readAsStringSync();
          expect(
            text.contains('\u200c'),
            isFalse,
            reason: '${f.path} نباید نیم فاصله داشته باشد',
          );
        }
      }

      expect(
        AppNotification.summarizeTitle('گزارش شبانه 1405/09/01'),
        'گزارش شبانه',
      );
      expect(
        AppNotification.summarizeBody('حجم مصرفی شما 12.5 گیگابایت است'),
        contains('۱۲.۵'),
      );
    });

    test('رصد فعالیت اندروید، ارسال گزارش پشتیبانی و عدم سرریز صفحه گزارش ها در عرض ۳۶۰', () async {
      AppLogger.instance.clear();
      ActivityMonitorBuffer.instance.clear();
      addTearDown(() {
        AppLogger.instance.clear();
        ActivityMonitorBuffer.instance.clear();
      });

      final List<CoreActivitySample> samples = ClashApi.parseConnections(<String, dynamic>{
        'connections': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'andr-1',
            'download': 4096,
            'upload': 512,
            'metadata': <String, dynamic>{
              'host': 'instagram.com',
              'processPath': 'com.instagram.android',
            },
          },
          <String, dynamic>{
            'id': 'andr-2',
            'download': 1024,
            'upload': 256,
            'metadata': <String, dynamic>{
              'sniffHost': 'localhost',
              'processPath': 'ir.umbrella.vpn',
            },
          },
        ],
      });
      expect(samples.length, 1);
      expect(samples.first.host, 'instagram.com');
      expect(samples.first.process, 'com.instagram.android');

      final ActivityMonitorBuffer buf = ActivityMonitorBuffer();
      buf.recordConnections(samples);
      final List<Map<String, dynamic>> snapshot = buf.snapshotPayload();
      expect(snapshot.any((Map<String, dynamic> e) => e['category'] == 'app' && e['target'] == 'Instagram'), isTrue);
      expect(snapshot.any((Map<String, dynamic> e) => e['category'] == 'site' && e['target'] == 'instagram.com'), isTrue);
      expect(snapshot.any((Map<String, dynamic> e) => e['category'] == 'screen'), isFalse);
      buf.confirmSent(snapshot);
      expect(buf.snapshotPayload(), isEmpty);

      final Map<String, dynamic> cfg = <String, dynamic>{
        'inbounds': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'tun', 'tag': 'tun-in'},
        ],
        'route': <String, dynamic>{'find_process': false, 'rules': <Map<String, dynamic>>[]},
        'outbounds': <Map<String, dynamic>>[<String, dynamic>{'type': 'direct', 'tag': 'direct §hide§'}],
        'experimental': <String, dynamic>{
          'monitoring': <String, dynamic>{},
          'clash_api': <String, dynamic>{'external_controller': '127.0.0.1:16756'},
        },
      };
      RuntimeConfig.finalize(
        cfg,
        profileTags: const <String>{},
        blockPagePort: 18080,
        preserveLogOutput: true,
      );
      expect((cfg['route'] as Map<String, dynamic>)['find_process'], isTrue);
      expect(
        (cfg['outbounds'] as List<dynamic>).any(
          (dynamic o) => o is Map && o['tag'] == RuntimeConfig.blockPageOutboundTag,
        ),
        isTrue,
      );
      expect((cfg['inbounds'] as List<dynamic>).single['tag'], 'tun-in');
      expect(const AppSettings().autoFailover, isTrue);

      final String pfWrapper = File('${Directory.current.path}/android/app/src/main/kotlin/ir/umbrella/vpn/bg/PlatformInterfaceWrapper.kt').readAsStringSync();
      expect(pfWrapper, contains('findConnectionOwner'));
      final String serviceNotifKt = File('${Directory.current.path}/android/app/src/main/kotlin/ir/umbrella/vpn/bg/ServiceNotification.kt').readAsStringSync();
      expect(serviceNotifKt, contains('tunnelConfirmed'));
      final String boxServiceKt = File('${Directory.current.path}/android/app/src/main/kotlin/ir/umbrella/vpn/bg/BoxService.kt').readAsStringSync();
      expect(boxServiceKt, isNot(contains('notification.showConnected()')));
    });

    testWidgets('ارسال به پشتیبانی در صفحه گزارش ها بدون سرریز روی موبایل ۳۶۰x۶۴۰ کار می کند', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() async => await tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await LocalStore.instance.init();
      AppLogger.instance.clear();
      AppLogger.instance.add('خطای نمونه موبایل', level: 'error');

      Map<String, dynamic>? sentBody;
      final MockClient mockHttp = MockClient((http.Request req) async {
        final String route = req.url.queryParameters['AppApi'] ?? req.url.path;
        if (route.endsWith('app/support-report')) {
          sentBody = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response.bytes(
            utf8.encode(jsonEncode(<String, dynamic>{'ok': true, 'sent': true, 'message': 'ارسال شد'})),
            200,
            headers: const <String, String>{'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response.bytes(
          utf8.encode(jsonEncode(<String, dynamic>{'ok': true})),
          200,
          headers: const <String, String>{'content-type': 'application/json; charset=utf-8'},
        );
      });
      final GatewayClient gateway = GatewayClient(client: mockHttp);
      final _FakeNative native = _FakeNative();
      final AuthController auth = AuthController(native: native, gateway: gateway, store: LocalStore.instance);
      final ToastController toasts = ToastController();
      addTearDown(AppLogger.instance.clear);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NativeBridge>.value(value: native),
            ChangeNotifierProvider<AuthController>.value(value: auth),
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

      final Finder btn = find.byKey(const ValueKey<String>('logs-send-support-button'));
      expect(btn, findsOneWidget);
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey<String>('support-report-note-field')), 'تست سریع موبایل');
      final Finder confirmBtn = find.byKey(const ValueKey<String>('support-report-confirm-button'));
      await tester.ensureVisible(confirmBtn);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(sentBody, isNotNull);
      expect(sentBody!['note'], 'تست سریع موبایل');
      expect((sentBody!['errors'] as List<dynamic>).length, 1);

      toasts.clear();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
      auth.dispose();
      gateway.close();
      toasts.dispose();
    });

    testWidgets('بخش پیش نمایش صفحه مسدودی مرورگر در ContentControlCard موبایل نمایش داده نمی شود', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() async => await tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await LocalStore.instance.init();

      final _FakeNative native = _FakeNative();
      final GatewayClient gateway = GatewayClient(
        client: MockClient((http.Request _) async => http.Response('{"ok":true}', 200)),
      );
      final AuthController auth = AuthController(
        native: native,
        gateway: gateway,
        store: LocalStore.instance,
      );
      final ToastController toasts = ToastController();
      final _FakeSound sound = _FakeSound();
      final VpnController vpn = VpnController(
        native: native,
        ipService: _FakeIpService(),
        sound: sound,
        tray: TrayService(native),
        provisioner: CoreProvisioner(),
        settings: const AppSettings(),
      );
      vpn.updateContentFilter(
        const FilterSettings(enabled: true, categories: <String>['adult']),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NativeBridge>.value(value: native),
            Provider<SoundService>.value(value: sound),
            Provider<WindowService>.value(value: _FakeWindow()),
            ChangeNotifierProvider<AuthController>.value(value: auth),
            ChangeNotifierProvider<ToastController>.value(value: toasts),
            ChangeNotifierProvider<VpnController>.value(value: vpn),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: ContentControlCard(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      expect(find.byKey(const ValueKey<String>('content-control-browser-banner')), findsNothing);
      expect(find.byKey(const ValueKey<String>('content-control-preview-button')), findsNothing);
      expect(find.text('صفحه مسدودسازی در مرورگر'), findsNothing);
      expect(find.text('پیش نمایش صفحه'), findsNothing);
      expect(find.textContaining('صفحه اختصاصی'), findsNothing);

      vpn.dispose();
      auth.dispose();
      gateway.close();
      toasts.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    test('RuntimeConfig.finalize با hotReloadCompat فیلدهای غیرقابل hot-reload را تغییر نمی دهد', () async {
      final Directory tempData =
          await Directory.systemTemp.createTemp('umbrella_hr_');
      addTearDown(() async {
        if (await tempData.exists()) {
          await tempData.delete(recursive: true);
        }
      });
      final File adultSrs = File(
        '${tempData.path}${Platform.pathSeparator}filter-adult.srs',
      );
      await adultSrs.writeAsBytes(List<int>.filled(64, 1));
      final File irSiteSrs = File(
        '${tempData.path}${Platform.pathSeparator}geosite-ir.srs',
      );
      await irSiteSrs.writeAsBytes(List<int>.filled(64, 2));

      final Map<String, dynamic> cfg = <String, dynamic>{
        'log': <String, dynamic>{'level': 'warn', 'output': 'box.log'},
        'inbounds': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'tun', 'tag': 'tun-in'},
        ],
        'dns': <String, dynamic>{
          'independent_cache': true,
          'servers': <Map<String, dynamic>>[
            <String, dynamic>{'tag': 'dns-direct-group', 'type': 'local'},
            <String, dynamic>{'tag': 'dns-remote-group', 'type': 'udp'},
          ],
          'rules': <Map<String, dynamic>>[],
        },
        'route': <String, dynamic>{
          'find_process': false,
          'rules': <Map<String, dynamic>>[
            <String, dynamic>{'action': 'sniff'},
          ],
          'rule_set': <Map<String, dynamic>>[],
        },
        'outbounds': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'direct', 'tag': 'direct §hide§'},
          for (int i = 0; i < 130; i++)
            <String, dynamic>{'type': 'vless', 'tag': 'node-$i'},
        ],
        'experimental': <String, dynamic>{
          'cache_file': <String, dynamic>{
            'enabled': true,
            'store_rdrc': true,
          },
          'monitoring': <String, dynamic>{
            'workers': 8,
            'debounce_window': '500ms',
            'url_test_timeout': '5s',
          },
          'clash_api': <String, dynamic>{
            'external_controller': '127.0.0.1:16756',
            'external_ui': 'ui',
          },
        },
      };

      RuntimeConfig.finalize(
        cfg,
        profileTags: <String>{for (int i = 0; i < 130; i++) 'node-$i'},
        coreSettings: <String, dynamic>{
          'region': 'ir',
          'bypass-lan': true,
          'resolve-destination': true,
          'route-rule': <String, dynamic>{
            'rules': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'umbrella-filter-adult',
                'enabled': true,
              },
            ],
          },
        },
        blockPagePort: 18080,
        preserveLogOutput: true,
        hotReloadCompat: true,
        localDataDir: tempData.path,
      );

      final Map<String, dynamic> monitoring =
          (cfg['experimental'] as Map<String, dynamic>)['monitoring']
              as Map<String, dynamic>;
      expect(monitoring['workers'], 8);
      expect(monitoring['debounce_window'], '500ms');
      expect(monitoring['url_test_timeout'], '5s');
      expect(monitoring['keep_top'], isA<Map<String, dynamic>>());

      final Map<String, dynamic> clash =
          (cfg['experimental'] as Map<String, dynamic>)['clash_api']
              as Map<String, dynamic>;
      expect(clash['external_ui'], 'ui');

      final Map<String, dynamic> cacheFile =
          (cfg['experimental'] as Map<String, dynamic>)['cache_file']
              as Map<String, dynamic>;
      expect(cacheFile['store_rdrc'], isTrue);
      expect((cfg['dns'] as Map<String, dynamic>)['independent_cache'], isTrue);
      expect((cfg['route'] as Map<String, dynamic>)['find_process'], isFalse);

      expect(
        (cfg['outbounds'] as List<dynamic>).any(
          (dynamic o) =>
              o is Map && o['tag'] == RuntimeConfig.blockPageOutboundTag,
        ),
        isTrue,
      );
      expect(
        (cfg['outbounds'] as List<dynamic>).where(
          (dynamic o) => o is Map && o['lazy'] == true,
        ).length,
        130,
      );
      expect(
        ((cfg['route'] as Map<String, dynamic>)['rule_set'] as List<dynamic>)
            .any((dynamic rs) => rs is Map && rs['tag'] == 'filter-adult'),
        isTrue,
      );

      final String vpnControllerSrc = File(
        '${Directory.current.path}/lib/vpn/vpn_controller.dart',
      ).readAsStringSync();
      expect(vpnControllerSrc, contains('hotReloadCompat: true'));
    });

    test('VpnController.connect بلافاصله وضعیت را روی در حال اتصال می گذارد', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await LocalStore.instance.init();
      final Directory tempDir =
          await Directory.systemTemp.createTemp('umbrella_android_imm_');
      addTearDown(() async {
        AppLogger.instance.clear();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final _ImmediateConnectNative native = _ImmediateConnectNative();
      final _TestProvisioner provisioner = _TestProvisioner(tempDir.path);
      await provisioner.init(native);
      final Completer<String> scanGate = Completer<String>();
      final List<VpnStatus> seenStatuses = <VpnStatus>[];

      final VpnController controller = VpnController(
        native: native,
        ipService: _FakeIpService(),
        sound: _FakeSound(),
        tray: TrayService(native),
        provisioner: provisioner,
        settings: const AppSettings(corePreference: CorePreference.tun),
        securityGuard: () => scanGate.future,
      );
      controller.addListener(() {
        if (seenStatuses.isEmpty || seenStatuses.last != controller.status) {
          seenStatuses.add(controller.status);
        }
      });
      addTearDown(controller.dispose);

      // Even before `securityGuard` finishes, `connect()` synchronously enters
      // `VpnStatus.connecting` («در حال اتصال») so the UI shows immediate feedback.
      final Future<ConnectOutcome> pending = controller.connect();
      expect(controller.status, VpnStatus.connecting);
      expect(controller.status.label, 'در حال اتصال');
      expect(seenStatuses, contains(VpnStatus.connecting));
      expect(seenStatuses, isNot(contains(VpnStatus.preparing)));

      scanGate.complete('');
      final ConnectOutcome outcome = await pending;
      expect(outcome.ok, isFalse);
      expect(controller.status, VpnStatus.failed);

      // Cancellation while `securityGuard` is still running resets cleanly to disconnected.
      final Completer<String> slowScan = Completer<String>();
      final VpnController cancellable = VpnController(
        native: native,
        ipService: _FakeIpService(),
        sound: _FakeSound(),
        tray: TrayService(native),
        provisioner: provisioner,
        settings: const AppSettings(corePreference: CorePreference.tun),
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

    testWidgets('ConnectPage بلافاصله پس از لمس دکمه اتصال عبارت در حال اتصال را نمایش می دهد', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 860));
      addTearDown(() async => await tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        await LocalStore.instance.init();
      });
      addTearDown(AppLogger.instance.clear);

      final _ImmediateConnectNative native = _ImmediateConnectNative();
      final _TestProvisioner provisioner = _TestProvisioner('/tmp/umbrella_android_page_imm');
      await provisioner.init(native);
      final _FakeSound sound = _FakeSound();
      final Completer<String> scanGate = Completer<String>();

      final VpnController vpn = VpnController(
        native: native,
        ipService: _FakeIpService(),
        sound: sound,
        tray: TrayService(native),
        provisioner: provisioner,
        settings: const AppSettings(
          corePreference: CorePreference.tun,
          selectionMode: SelectionMode.manual,
        ),
        securityGuard: () => scanGate.future,
      );
      final SettingsController settings = SettingsController(
        native: native,
        sound: sound,
        window: _FakeWindow(),
      );
      final GatewayClient gateway = GatewayClient(
        client: MockClient((http.Request _) async => http.Response('{"ok":false}', 200)),
        enableNativeTransport: false,
      );
      final _ConnectSignedAuth auth = _ConnectSignedAuth(
        native: native,
        gateway: gateway,
        store: LocalStore.instance,
      );
      final Completer<void> syncGate = Completer<void>();
      final _DelayedConnectSubs subs = _DelayedConnectSubs(
        vpn: vpn,
        auth: auth,
        client: MockClient((http.Request _) async => http.Response('[]', 200)),
        onSync: () => syncGate.future,
      );
      final ToastController toasts = ToastController();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NativeBridge>.value(value: native),
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

      // Phase 1: even when nodes are empty and `syncPersonal()` is pending,
      // tapping Connect immediately displays `در حال اتصال` and `لغو اتصال`,
      // and tapping Cancel resets immediately without waiting for network I/O.
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

      // Phase 2: when nodes are already loaded, tapping Connect calls `vpn.connect()`
      // which synchronously switches status to `VpnStatus.connecting` (`در حال اتصال`)
      // before `securityGuard` (`scanGate`) finishes.
      await tester.runAsync(() => vpn.applyNodes(const <VpnNode>[
            VpnNode(
              id: 'n1',
              name: 'Node 1',
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

    testWidgets('ConnectPage بنر اعلان نسخه جدید را در موبایل عمودی، افقی و تبلت بدون سرریز نشان می دهد', (WidgetTester tester) async {
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        await LocalStore.instance.init();
      });
      addTearDown(AppLogger.instance.clear);

      const String sampleHash =
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      final MockClient updateHttp = MockClient((http.Request req) async {
        return http.Response.bytes(
          utf8.encode(jsonEncode(<Map<String, dynamic>>[
            <String, dynamic>{
              'tag_name': '9.9.9',
              'prerelease': false,
              'draft': false,
              'published_at': '2026-11-25T12:00:00Z',
              'body': '- بهبود اتصال و نصب درون برنامه ای',
              'assets': <Map<String, dynamic>>[
                <String, dynamic>{
                  'name': 'UmbrellaVPN-9.9.9-arm64-v8a.apk',
                  'browser_download_url':
                      'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/9.9.9/UmbrellaVPN-9.9.9-arm64-v8a.apk',
                  'size': 22000000,
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

      final _ImmediateConnectNative native = _ImmediateConnectNative();
      final _TestProvisioner provisioner = _TestProvisioner('/tmp/umbrella_android_upd_banner');
      await provisioner.init(native);
      final _FakeSound sound = _FakeSound();
      final VpnController vpn = VpnController(
        native: native,
        ipService: _FakeIpService(),
        sound: sound,
        tray: TrayService(native),
        provisioner: provisioner,
        settings: const AppSettings(),
      );
      final SettingsController settings = SettingsController(
        native: native,
        sound: sound,
        window: _FakeWindow(),
      );
      final GatewayClient gateway = GatewayClient(
        client: MockClient((http.Request _) async => http.Response('{"ok":false}', 200)),
        enableNativeTransport: false,
      );
      final _ConnectSignedAuth auth = _ConnectSignedAuth(
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
        service: UpdateService(client: updateHttp, preferredAbi: 'arm64-v8a'),
      );
      await tester.runAsync(() => updates.check(silent: false));
      expect(updates.available, isNotNull);

      final ToastController toasts = ToastController();
      final List<FlutterErrorDetails> errors = <FlutterErrorDetails>[];
      final FlutterExceptionHandler? prevError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails d) => errors.add(d);
      addTearDown(() => FlutterError.onError = prevError);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final Size size in const <Size>[
        Size(320, 568),
        Size(667, 375),
        Size(1024, 768),
      ]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<NativeBridge>.value(value: native),
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
          reason: 'Expected update banner at $size',
        );
        expect(find.textContaining('نسخه جدید'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('connect-update-action-button')),
          findsOneWidget,
        );
      }
      expect(errors, isEmpty, reason: errors.map((e) => e.exceptionAsString()).join('\n'));

      final Finder dismissBtn =
          find.byKey(const ValueKey<String>('connect-update-dismiss-button'));
      await tester.ensureVisible(dismissBtn);
      await tester.tap(dismissBtn);
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('connect-update-banner')), findsNothing);

      toasts.clear();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
      updates.dispose();
      updateHttp.close();
      subs.dispose();
      vpn.dispose();
      settings.dispose();
      auth.dispose();
      gateway.close();
      toasts.dispose();
    });

    test('CoreRuntime.loadCachedRuntime کش runtime-android را برای بوت مستقیم enableRawConfig می سازد و پورت/لاگ را بدون باطل شدن کش به روز می کند', () async {
      final Directory tempDir =
          await Directory.systemTemp.createTemp('umbrella_android_raw_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final String sep = Platform.pathSeparator;
      final File ruleFile = File('${tempDir.path}${sep}geosite-ir.srs');
      await ruleFile.writeAsBytes(List<int>.filled(64, 7), flush: true);

      final Map<String, dynamic> fullSettings = <String, dynamic>{
        'region': 'ir',
        'log-file': '${tempDir.path}${sep}old.log',
        'block-ads': true,
      };
      final List<String> links = <String>[
        'vless://11111111-1111-1111-1111-111111111111@192.0.2.1:443#Fast',
        'vless://22222222-2222-2222-2222-222222222222@192.0.2.2:443#Backup',
      ];
      final String key = CoreRuntime.runtimeCacheKey(
        preparedLinks: links,
        fullSettings: fullSettings,
        stickyMinutes: 15,
        serviceMode: 'vpn',
        hasBlockPage: true,
        localRuleSetPaths: <String, String>{'geosite-ir': ruleFile.path},
      );

      final Map<String, dynamic> rawRuntime = <String, dynamic>{
        'log': <String, dynamic>{'output': '${tempDir.path}${sep}old.log'},
        'inbounds': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'tun', 'tag': 'tun-in'},
        ],
        'route': <String, dynamic>{
          'rule_set': <Map<String, dynamic>>[
            <String, dynamic>{
              'tag': 'geosite-ir',
              'type': 'local',
              'format': 'binary',
              'path': ruleFile.path,
            },
          ],
        },
        'outbounds': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'vless', 'tag': 'Fast'},
          <String, dynamic>{
            'type': 'http',
            'tag': RuntimeConfig.blockPageOutboundTag,
            'server': '127.0.0.1',
            'server_port': 18080,
          },
        ],
        'experimental': <String, dynamic>{
          'monitoring': <String, dynamic>{
            'workers': RuntimeConfig.monitoringWorkers,
            'debounce_window': '200ms',
            'url_test_timeout': '4s',
          },
        },
      };

      await CoreRuntime.saveRuntimeCache(
        runDir: tempDir.path,
        runtimeKey: key,
        config: rawRuntime,
      );

      // Matching key patches new blockPagePort and coreLogPath in place.
      final File? loaded = await CoreRuntime.loadCachedRuntime(
        runDir: tempDir.path,
        runtimeKey: key,
        blockPagePort: 19091,
        coreLogPath: '${tempDir.path}${sep}new-core.log',
        hasBlockPage: true,
      );
      expect(loaded, isNotNull);
      expect(loaded!.path, endsWith('${sep}runtime-android.json'));
      final Map<String, dynamic> updated =
          jsonDecode(await loaded.readAsString()) as Map<String, dynamic>;
      expect((updated['log'] as Map<String, dynamic>)['output'], '${tempDir.path}${sep}new-core.log');
      final Map<String, dynamic> blockOutbound =
          (updated['outbounds'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .firstWhere((Map<String, dynamic> o) => o['tag'] == RuntimeConfig.blockPageOutboundTag);
      expect(blockOutbound['server_port'], 19091);

      // Missing local .srs file invalidates cleanly.
      await ruleFile.delete();
      expect(
        await CoreRuntime.loadCachedRuntime(
          runDir: tempDir.path,
          runtimeKey: key,
          blockPagePort: 19091,
          coreLogPath: '${tempDir.path}${sep}new-core.log',
          hasBlockPage: true,
        ),
        isNull,
      );
      await ruleFile.writeAsBytes(List<int>.filled(64, 7), flush: true);

      // Changed link invalidates key.
      final String changedKey = CoreRuntime.runtimeCacheKey(
        preparedLinks: <String>[links.first],
        fullSettings: fullSettings,
        stickyMinutes: 15,
        serviceMode: 'vpn',
        hasBlockPage: true,
        localRuleSetPaths: <String, String>{'geosite-ir': ruleFile.path},
      );
      expect(changedKey, isNot(key));
      expect(
        await CoreRuntime.loadCachedRuntime(
          runDir: tempDir.path,
          runtimeKey: changedKey,
          blockPagePort: 19091,
          hasBlockPage: true,
        ),
        isNull,
      );

      // Kotlin native wiring contract for enableRawConfig, notification close, and revoke.
      final String methodHandlerKt = File(
        '${Directory.current.path}/android/app/src/main/kotlin/ir/umbrella/vpn/MethodHandler.kt',
      ).readAsStringSync();
      final String settingsKt = File(
        '${Directory.current.path}/android/app/src/main/kotlin/ir/umbrella/vpn/Settings.kt',
      ).readAsStringSync();
      final String boxServiceKt = File(
        '${Directory.current.path}/android/app/src/main/kotlin/ir/umbrella/vpn/bg/BoxService.kt',
      ).readAsStringSync();
      final String notifKt = File(
        '${Directory.current.path}/android/app/src/main/kotlin/ir/umbrella/vpn/bg/ServiceNotification.kt',
      ).readAsStringSync();
      expect(methodHandlerKt, contains('call.argument<Boolean>("enableRawConfig")'));
      expect(settingsKt, contains('activeEnableRawConfig'));
      expect(boxServiceKt, contains('enable_raw_config = Settings.activeEnableRawConfig'));
      expect(boxServiceKt, contains('"vpn_revoked"'));
      expect(boxServiceKt, contains('"user_stopped"'));
      expect(notifKt, contains('Action.SERVICE_USER_CLOSE'));
    });

    test('VpnController.buildAutoCandidates پس از شکست مسیرهای اشتراک، WireGuard/AWG/Mieru را بلافاصله جلو می آورد', () {
      VpnNode makeNode(String id, NodeProtocol proto, {int ping = 0}) {
        return VpnNode(
          id: id,
          name: id,
          protocol: proto,
          host: 'example.com',
          port: 443,
          sourceId: 'src',
          pingMs: ping,
          stability: 0.9,
          checkedAt: ping > 0 ? DateTime.now() : null,
          raw: proto == NodeProtocol.mieru ? '{"port":443}' : '',
          params: const <String, dynamic>{},
        );
      }

      final VpnNode v1 = makeNode('v1', NodeProtocol.vless, ping: 80);
      final VpnNode wg1 = makeNode('wg1', NodeProtocol.wireguard, ping: 110);
      final NodeBalancer balancer = NodeBalancer();

      // Normal order keeps pool ahead of direct.
      expect(
        VpnController.buildAutoCandidates(
          personalNodes: <VpnNode>[v1, wg1],
          emergencyNodes: const <VpnNode>[],
          balancer: balancer,
          mode: SelectionMode.auto,
          deviceSeed: 'seed-a',
          preferredNodeId: '',
          stickyMinutes: 15,
          allowFailover: true,
          emergencyOnly: false,
          accepts: (_) => true,
        ).map((VpnNode n) => n.id).toList(),
        <String>['v1', 'wg1'],
      );

      // Once all pool nodes fail, direct WG promotes ahead of the failed pool.
      balancer.markFailed('v1');
      expect(
        VpnController.buildAutoCandidates(
          personalNodes: <VpnNode>[v1, wg1],
          emergencyNodes: const <VpnNode>[],
          balancer: balancer,
          mode: SelectionMode.auto,
          deviceSeed: 'seed-a',
          preferredNodeId: '',
          stickyMinutes: 15,
          allowFailover: true,
          emergencyOnly: false,
          accepts: (_) => true,
        ).map((VpnNode n) => n.id).toList(),
        <String>['wg1', 'v1'],
      );
    });

    test('توقف غیرمنتظره سرویس اندروید با پیام خالی بازاتصال را با enableRawConfig فعال می کند و user_stopped/vpn_revoked بدون لوپ قطع می شوند', () async {
      final HttpOverrides? previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      await LocalStore.instance.init();
      final Directory tempDir =
          await Directory.systemTemp.createTemp('umbrella_android_e2e_');
      HttpServer? clashStub;
      try {
        clashStub = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          AppConfig.coreClashPort,
        );
      } on SocketException {
        clashStub = null;
      }
      addTearDown(() async {
        AppLogger.instance.clear();
        await clashStub?.close(force: true);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      if (clashStub == null) {
        return;
      }

      clashStub.listen((HttpRequest req) async {
        if (req.uri.path == '/logs') {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
          return;
        }
        req.response.headers.contentType = ContentType.json;
        if (req.uri.path == '/proxies') {
          final String nowUtc = DateTime.now().toUtc().toIso8601String();
          req.response.write(jsonEncode(<String, dynamic>{
            'proxies': <String, dynamic>{
              'select': <String, dynamic>{
                'type': 'Selector',
                'now': 'lowest',
                'all': <String>['lowest'],
              },
              'lowest': <String, dynamic>{
                'type': 'URLTest',
                'now': 'Node0',
                'all': <String>['Node0'],
              },
              'Node0': <String, dynamic>{
                'type': 'VLESS',
                'history': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'time': nowUtc,
                    'delay': 55,
                    'from_cache': false,
                  },
                ],
              },
            },
          }));
        } else if (req.uri.path == '/connections') {
          req.response.write('{"downloadTotal":0,"uploadTotal":0,"connections":[]}');
        } else {
          req.response.write('{}');
        }
        await req.response.close();
      });

      final _RecoveryCoreNative native = _RecoveryCoreNative(tempDir.path);
      final _TestProvisioner provisioner = _TestProvisioner(tempDir.path);
      await provisioner.init(native);
      final _FakeSound sound = _FakeSound();

      final VpnController controller = VpnController(
        native: native,
        ipService: _FakeIpService(),
        sound: sound,
        tray: TrayService(native),
        provisioner: provisioner,
        settings: const AppSettings(
          corePreference: CorePreference.systemProxy,
          serviceMode: InboundServiceMode.proxy,
          tunMode: false,
          mixedPort: 12334,
          autoFailover: true,
        ),
      );
      addTearDown(() async {
        controller.dispose();
        await native.closeEvents();
      });

      await controller.applyNodes(<VpnNode>[
        const VpnNode(
          id: 'n1',
          name: 'FastNode',
          protocol: NodeProtocol.vless,
          host: '198.51.100.10',
          port: 443,
          sourceId: 'sub-1',
          params: <String, dynamic>{'uuid': '11111111-1111-1111-1111-111111111111'},
          raw: 'vless://11111111-1111-1111-1111-111111111111@198.51.100.10:443#FastNode',
        ),
      ], measure: false);

      // 1) Cold connect builds runtime-android.json via current-config.json.
      final ConnectOutcome initial = await controller.connect();
      expect(initial.ok, isTrue);
      expect(controller.status, VpnStatus.connected);
      expect(native.startCalls.length, 1);
      expect(native.startCalls.first.enableRawConfig, isFalse);

      // 2) Unexpected stop with EMPTY status message still triggers _reconnect(),
      //    and the recovery boot uses 1-shot cached runtime-android.json with enableRawConfig: true and 0 hotReloads.
      native.coreStatus = <String, dynamic>{
        'status': 'Stopped',
        'active': false,
        'starting': false,
        'stopping': false,
        'lastError': '',
      };
      native.emitServiceEvent(
        const AndroidServiceEvent(type: 'status', status: 'Stopped', message: ''),
      );

      final DateTime deadline = DateTime.now().add(const Duration(seconds: 6));
      while (DateTime.now().isBefore(deadline) && native.startCalls.length < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      while (DateTime.now().isBefore(deadline) &&
          controller.status != VpnStatus.connected) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      expect(controller.status, VpnStatus.connected);
      expect(native.startCalls.length, 2);
      expect(native.startCalls[1].enableRawConfig, isTrue);
      expect(native.startCalls[1].configPath, endsWith('runtime-android.json'));
      expect(native.hotReloadCallsOnRaw, 0);

      // 3) Notification user_stopped disconnects cleanly without looping back into reconnect.
      native.coreStatus = <String, dynamic>{
        'status': 'Stopped',
        'active': false,
        'starting': false,
        'stopping': false,
        'lastError': '',
      };
      native.emitServiceEvent(
        const AndroidServiceEvent(
          type: 'alert',
          alert: 'StartService',
          message: 'user_stopped',
        ),
      );
      native.emitServiceEvent(
        const AndroidServiceEvent(type: 'status', status: 'Stopped', message: ''),
      );
      final DateTime stopDeadline = DateTime.now().add(const Duration(seconds: 2));
      while (DateTime.now().isBefore(stopDeadline) &&
          controller.status != VpnStatus.disconnected) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(controller.status, VpnStatus.disconnected);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(native.startCalls.length, 2);

      // 4) Re-connect warm (still 1-shot enableRawConfig: true) then simulate OS vpn_revoked.
      final ConnectOutcome warm = await controller.connect();
      expect(warm.ok, isTrue);
      expect(native.startCalls.length, 3);
      expect(native.startCalls[2].enableRawConfig, isTrue);

      native.coreStatus = <String, dynamic>{
        'status': 'Stopped',
        'active': false,
        'starting': false,
        'stopping': false,
        'lastError': '',
      };
      native.emitServiceEvent(
        const AndroidServiceEvent(
          type: 'alert',
          alert: 'RequestVPNPermission',
          message: 'vpn_revoked',
        ),
      );
      native.emitServiceEvent(
        const AndroidServiceEvent(type: 'status', status: 'Stopped', message: ''),
      );
      final DateTime revokeDeadline = DateTime.now().add(const Duration(seconds: 2));
      while (DateTime.now().isBefore(revokeDeadline) &&
          controller.status != VpnStatus.failed) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(controller.status, VpnStatus.failed);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(native.startCalls.length, 3);
    });
  });
}

class _ImmediateConnectNative extends _TestCoreNative {
  _ImmediateConnectNative()
      : super(
          parseResult: (ok: true, content: '{"outbounds":[]}', message: ''),
        );

  @override
  Future<bool> restoreNetworkDefaults() async => true;

  @override
  Future<String> localIp() async => '192.168.1.50';

  @override
  Future<({bool online, String fingerprint})?> networkState() async =>
      (online: true, fingerprint: 'wifi');

  @override
  Future<bool> ensureVpnPermission() async => true;
}

class _RecoveryCoreNative extends _ImmediateConnectNative {
  _RecoveryCoreNative(this._dataRoot);

  final String _dataRoot;
  final List<({String configPath, bool enableRawConfig})> startCalls =
      <({String configPath, bool enableRawConfig})>[];
  int hotReloadCallsOnRaw = 0;

  @override
  Future<Map<String, dynamic>> startCore({
    required String configPath,
    required String settingsJson,
    required String profileName,
    String serviceMode = 'vpn',
    bool enableRawConfig = false,
  }) async {
    startCalls.add((configPath: configPath, enableRawConfig: enableRawConfig));
    final String sep = Platform.pathSeparator;
    final File currentConfig =
        File('$_dataRoot${sep}work${sep}data${sep}current-config.json');
    await currentConfig.parent.create(recursive: true);
    if (!enableRawConfig) {
      await currentConfig.writeAsString(
        jsonEncode(<String, dynamic>{
          'log': <String, dynamic>{'level': 'warn', 'output': ''},
          'inbounds': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'mixed',
              'tag': 'mixed-in',
              'listen': '127.0.0.1',
              'listen_port': 12334,
            },
          ],
          'dns': <String, dynamic>{'rules': <dynamic>[]},
          'route': <String, dynamic>{
            'rule_set': <dynamic>[],
            'rules': <Map<String, dynamic>>[
              <String, dynamic>{'action': 'sniff'},
            ],
          },
          'outbounds': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'direct', 'tag': 'direct §hide§'},
            <String, dynamic>{'type': 'vless', 'tag': 'Node0'},
          ],
          'experimental': <String, dynamic>{
            'monitoring': <String, dynamic>{
              'workers': 10,
              'debounce_window': '500ms',
              'url_test_timeout': '5s',
            },
          },
        }),
        flush: true,
      );
    }
    coreStatus = <String, dynamic>{
      'status': 'Started',
      'active': true,
      'starting': false,
      'stopping': false,
      'lastError': '',
    };
    scheduleMicrotask(() {
      emitServiceEvent(
        const AndroidServiceEvent(type: 'status', status: 'Started'),
      );
    });
    return <String, dynamic>{'ok': true, 'serviceMode': serviceMode};
  }

  @override
  Future<int> tcpPing(String host, int port, {int timeoutMs = 1500}) async =>
      coreStatus['active'] == true ? 4 : -1;

  @override
  Future<({bool ok, String message})> hotReloadConfig({
    required String configPath,
    String profileName = 'Umbrella VPN',
  }) async {
    if (startCalls.isNotEmpty && startCalls.last.enableRawConfig) {
      hotReloadCallsOnRaw++;
    }
    return (ok: true, message: '');
  }

  @override
  Future<bool> restoreNetworkDefaults() async => true;
}

class _ConnectSignedAuth extends AuthController {
  _ConnectSignedAuth({
    required super.native,
    required super.gateway,
    required super.store,
  });

  @override
  bool get signedIn => true;

  @override
  Account get account => const Account(
        name: 'کاربر تست',
        enable: true,
        isActive: true,
      );

  @override
  SessionData? get session => const SessionData(
        token: 'tok-connect-1',
        uuid: '33333333-3333-4333-8333-333333333333',
        deviceId: 'dev-connect-1',
        account: Account(
          name: 'کاربر تست',
          enable: true,
          isActive: true,
        ),
        filter: FilterSettings.empty,
      );
}

class _DelayedConnectSubs extends SubscriptionController {
  _DelayedConnectSubs({
    required super.vpn,
    required super.auth,
    required super.client,
    required this.onSync,
  }) : super(enableNativeTransport: false);

  final Future<void> Function() onSync;

  @override
  Future<void> syncPersonal() => onSync();
}

class _SmsTestNative extends _FakeNative {
  final StreamController<AndroidServiceEvent> _smsEvents =
      StreamController<AndroidServiceEvent>.broadcast();
  int smsStartCalls = 0;
  int smsStopCalls = 0;

  void emitSmsMessage(String rawMessage) {
    if (!_smsEvents.isClosed) {
      final String code = NativeBridge.extractSmsVerificationCode(rawMessage);
      _smsEvents.add(
        AndroidServiceEvent(
          type: 'smsCode',
          code: code,
          message: rawMessage,
        ),
      );
    }
  }

  Future<void> closeSms() async {
    if (!_smsEvents.isClosed) {
      await _smsEvents.close();
    }
  }

  @override
  Future<bool> startSmsUserConsent() async {
    smsStartCalls++;
    return true;
  }

  @override
  Future<void> stopSmsUserConsent() async {
    smsStopCalls++;
  }

  @override
  Stream<AndroidServiceEvent> serviceEvents() => _smsEvents.stream;

  @override
  Stream<String> smsCodeEvents() {
    return serviceEvents()
        .where((AndroidServiceEvent event) => event.type == 'smsCode')
        .map((AndroidServiceEvent event) {
          final String direct = NativeBridge.extractSmsVerificationCode(event.code);
          if (direct.isNotEmpty) return direct;
          return NativeBridge.extractSmsVerificationCode(event.message);
        })
        .where((String code) => code.isNotEmpty);
  }
}

class _TestCoreNative extends _FakeNative {
  _TestCoreNative({required this.parseResult});

  final ({bool ok, String content, String message}) parseResult;
  int parseCalls = 0;
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
  }) async {
    parseCalls++;
    return parseResult;
  }

  @override
  Future<Map<String, dynamic>> startCore({
    required String configPath,
    required String settingsJson,
    required String profileName,
    String serviceMode = 'vpn',
    bool enableRawConfig = false,
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
