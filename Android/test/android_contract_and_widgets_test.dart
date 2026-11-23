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
import 'package:umbrella_vpn/data/gateway_client.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/platform/services.dart';
import 'package:umbrella_vpn/state/auth_controller.dart';
import 'package:umbrella_vpn/state/power_controller.dart';
import 'package:umbrella_vpn/state/settings_controller.dart';
import 'package:umbrella_vpn/state/toast_controller.dart';
import 'package:umbrella_vpn/ui/pages/device_page.dart';
import 'package:umbrella_vpn/ui/pages/exit_page.dart';
import 'package:umbrella_vpn/ui/pages/landing_page.dart';
import 'package:umbrella_vpn/ui/pages/login_page.dart';
import 'package:umbrella_vpn/ui/pages/settings_page.dart';
import 'package:umbrella_vpn/ui/widgets/quick_connection_panel.dart';
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

      final Finder vpnSettingsAction = find.text('تنظیمات Always-On VPN');
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
      expect(find.text('پروکسی برنامه محور (Split Tunneling)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('settings-back-button')));
      await tester.pumpAndSettle();

      final Finder inboundMenu =
          find.byKey(const ValueKey<String>('settings-category-inbound'));
      await tester.ensureVisible(inboundMenu);
      await tester.tap(inboundMenu);
      await tester.pumpAndSettle();
      expect(find.text('تونل کامل VPN (پیشنهادی)'), findsOneWidget);

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
  });
}
