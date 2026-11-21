import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:umbrella_vpn/app.dart';
import 'package:umbrella_vpn/core/app_config.dart';
import 'package:umbrella_vpn/core/persian.dart';
import 'package:umbrella_vpn/core/storage.dart';
import 'package:umbrella_vpn/data/gateway_client.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/platform/services.dart';
import 'package:umbrella_vpn/state/auth_controller.dart';
import 'package:umbrella_vpn/state/settings_controller.dart';
import 'package:umbrella_vpn/state/subscription_controller.dart';
import 'package:umbrella_vpn/state/toast_controller.dart';
import 'package:umbrella_vpn/state/update_controller.dart';
import 'package:umbrella_vpn/ui/widgets/shell_widgets.dart';
import 'package:umbrella_vpn/vpn/cores.dart';
import 'package:umbrella_vpn/vpn/umbrella_core.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

class _SilentSound implements SoundService {
  @override
  bool enabled = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _OfflineIpService extends IpService {
  @override
  Future<GeoInfo> fetch({
    bool force = false,
    String proxy = '',
    String proxyUser = '',
    String proxyPassword = '',
  }) async =>
      const GeoInfo(
        ip: '5.160.12.34',
        country: 'ایران',
        countryCode: 'IR',
        city: 'تهران',
      );
}

void _installMockNativeChannel(WidgetTester tester) {
  const MethodChannel pathChannel =
      MethodChannel('plugins.flutter.io/path_provider');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    pathChannel,
    (MethodCall call) async => Directory.systemTemp.path,
  );
  const MethodChannel channel = MethodChannel('ir.umbrella.app/native');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    (MethodCall call) async {
      switch (call.method) {
        case 'isElevated':
        case 'hasVpnPermission':
        case 'coreInstalled':
        case 'isIgnoringBatteryOptimizations':
          return true;
        case 'deviceInfo':
          return <String, Object>{
            'hostname': 'Samsung SM-S938B',
            'username': 'Samsung',
            'os': 'Android 16 (SDK 36)',
            'osEdition': '2026-10-01',
            'osDisplayVersion': '16',
            'osBuild': 36,
            'arch': 'arm64-v8a',
            'cpu': 'Qualcomm Snapdragon 8 Elite',
            'cpuCores': 8,
            'ramTotalMb': 12288,
            'ramUsedMb': 5120,
            'ramLoadPercent': 42,
            'diskTotalMb': 262144,
            'diskFreeMb': 180224,
            'screenWidth': 1080,
            'screenHeight': 2340,
            'uptimeSeconds': 86400,
            'localIp': '192.168.1.24',
            'adapterName': 'شبکه وای فای',
            'machineId': 'a1b2c3d4e5f60718',
            'elevated': true,
            'hasBattery': true,
            'batteryPercent': 84,
            'powerPlugged': false,
          };
        case 'installedApps':
          return <Map<String, Object>>[
            <String, Object>{
              'packageName': 'org.telegram.messenger',
              'appName': 'تلگرام',
              'isSystem': false,
            },
            <String, Object>{
              'packageName': 'ir.divar',
              'appName': 'دیوار',
              'isSystem': false,
            },
          ];
        case 'tunnelStats':
          return <String, Object>{
            'rx': 0,
            'tx': 0,
            'available': false,
            'adapter': '',
          };
        case 'autostartEnabled':
        case 'isRunning':
        case 'systemProxyEnabled':
          return false;
        case 'stopCore':
        case 'shutdownCores':
          return 0;
        case 'runningCores':
          return <String>[];
        case 'localIp':
        case 'adapterName':
        case 'exePath':
        case 'dataDir':
          return '';
        case 'coreStatus':
          return <String, Object>{
            'state': 'stopped',
            'error': '',
            'startedAtMs': 0,
            'rx': 0,
            'tx': 0,
          };
        default:
          return true;
      }
    },
  );
  tester.binding.defaultBinaryMessenger.setMockStreamHandler(
    const EventChannel('ir.umbrella.app/tray'),
    MockStreamHandler.inline(
      onListen: (Object? args, MockStreamHandlerEventSink events) {},
    ),
  );
}

class _HarnessBundle {
  const _HarnessBundle({
    required this.widget,
    required this.disposeAsync,
  });

  final Widget widget;
  final Future<void> Function() disposeAsync;
}

Future<_HarnessBundle> _buildTestHarness({
  required WidgetTester tester,
  required bool landingSeen,
  required bool signedIn,
}) async {
  return (await tester.runAsync<_HarnessBundle>(() async {
    const Account sampleAccount = Account(
      uuid: '9f7b5c1a-2233-4455-8899-aabbccddeeff',
      name: 'آرمین',
      phone: '09123456789',
      enable: true,
      isActive: true,
      usageLimitGb: 100,
      currentUsageGb: 18.5,
      packageDays: 30,
      subscriptionUrl:
          'https://user.umbrella-server.ir/D6qnVQXRwa/9f7b5c1a-2233-4455-8899-aabbccddeeff/sub/',
    );

    final String nowEpoch =
        DateTime.now().toUtc().millisecondsSinceEpoch.toString();
    final Map<String, Object> initialPrefs = <String, Object>{
      StoreKeys.landingSeen: landingSeen,
      StoreKeys.telegramChannelPromptAt: nowEpoch,
      if (signedIn) ...<String, Object>{
        StoreKeys.deviceId: 'android-test-device',
        StoreKeys.session: jsonEncode(
          SessionData(
            token: 'tok-android-test-123',
            uuid: sampleAccount.uuid,
            deviceId: 'android-test-device',
            account: sampleAccount,
            filter: FilterSettings.empty,
          ).toJson(),
        ),
      },
    };
    SharedPreferences.setMockInitialValues(initialPrefs);
    final LocalStore store = LocalStore.instance;
    await store.init();
    await store.writeBool(StoreKeys.landingSeen, landingSeen);
    await store.write(StoreKeys.telegramChannelPromptAt, nowEpoch);
    if (signedIn) {
      await store.write(StoreKeys.deviceId, 'android-test-device');
      await store.writeJson(
        StoreKeys.session,
        SessionData(
          token: 'tok-android-test-123',
          uuid: sampleAccount.uuid,
          deviceId: 'android-test-device',
          account: sampleAccount,
          filter: FilterSettings.empty,
        ).toJson(),
      );
    } else {
      await store.remove(StoreKeys.session);
    }

    final MockClient mockHttp = MockClient((http.Request request) async {
      return http.Response(
        jsonEncode(<String, Object>{'ok': false, 'items': <Object>[]}),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final NativeBridge native = NativeBridge();
    final SoundService sound = _SilentSound();
    final WindowService window = WindowService(native);
    final IpService ipService = _OfflineIpService();
    final SettingsController settings = SettingsController(
      native: native,
      sound: sound,
      window: window,
    );
    await settings.load();

    final TrayService tray = TrayService(native);
    final GatewayClient gateway = GatewayClient(
      client: mockHttp,
      enableNativeTransport: false,
    );
    final AuthController auth = AuthController(
      gateway: gateway,
      native: native,
      store: store,
      sound: sound,
      tray: tray,
    );
    await auth.restore();

    final CoreProvisioner provisioner = CoreProvisioner();
    await provisioner.init();
    final ToastController toasts = ToastController();
    final VpnController vpn = VpnController(
      native: native,
      ipService: ipService,
      sound: sound,
      tray: tray,
      provisioner: provisioner,
      settings: settings.settings,
      onSettingsChanged: (AppSettings _) {},
      onRequireElevation: () {},
      onRequireCores: () {},
      canAutoConnect: () => false,
    );
    final SubscriptionController subs = SubscriptionController(
      vpn: vpn,
      auth: auth,
      client: mockHttp,
      enableNativeTransport: false,
    );
    final UpdateController updates = UpdateController(
      native,
      service: UpdateService(client: mockHttp),
    );

    final Widget widget = MultiProvider(
      providers: [
        Provider<NativeBridge>.value(value: native),
        Provider<WindowService>.value(value: window),
        Provider<SoundService>.value(value: sound),
        Provider<IpService>.value(value: ipService),
        Provider<TrayService>.value(value: tray),
        Provider<CoreProvisioner>.value(value: provisioner),
        ChangeNotifierProvider<ToastController>.value(value: toasts),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<AuthController>.value(value: auth),
        ChangeNotifierProvider<SubscriptionController>.value(value: subs),
        ChangeNotifierProvider<VpnController>.value(value: vpn),
        ChangeNotifierProvider<UpdateController>.value(value: updates),
      ],
      child: UmbrellaApp(windowService: window),
    );

    return _HarnessBundle(
      widget: widget,
      disposeAsync: () async {
        updates.dispose();
        subs.dispose();
        await subs.close();
        vpn.dispose();
        auth.dispose();
        settings.dispose();
        toasts.dispose();
      },
    );
  }))!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Persian, branding, and Android source contracts', () {
    test('domain search hint is Persian', () {
      final String source =
          File('lib/ui/widgets/content_control.dart').readAsStringSync();
      expect(source.contains("hintText: 'جست وجوی دامنه...'"), isTrue);
      expect(source.contains('search domain...'), isFalse);
    });

    test('zero invisible Unicode characters across Android app and host files', () {
      final RegExp forbidden = RegExp(
        r'[\u200B\u200C\u200D\u200E\u200F\uFEFF\u202A-\u202E\u2066-\u2069]',
      );
      final List<String> offenders = <String>[];
      for (final String dir in <String>['lib', 'android/app/src']) {
        final Directory root = Directory(dir);
        if (!root.existsSync()) continue;
        for (final FileSystemEntity entity in root.listSync(recursive: true)) {
          if (entity is! File) continue;
          final String path = entity.path.replaceAll('\\', '/');
          if (!(path.endsWith('.dart') ||
              path.endsWith('.kt') ||
              path.endsWith('.xml'))) {
            continue;
          }
          if (forbidden.hasMatch(entity.readAsStringSync())) {
            offenders.add(path);
          }
        }
      }
      expect(offenders, isEmpty);
    });

    test('zero exposed third-party branding, zero window_manager, zero UI Windows labels', () {
      final List<String> brandHits = <String>[];
      final List<String> desktopImports = <String>[];
      final List<String> windowsUiHits = <String>[];
      for (final FileSystemEntity entity
          in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final String rel = entity.path.replaceAll('\\', '/');
        final List<String> lines = entity.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final String raw = lines[i];
          final String trimmed = raw.trim();
          if (trimmed.startsWith('//')) continue;
          final String code = raw.split('//').first;
          final String low = code.toLowerCase();
          if (low.contains('window_manager')) {
            desktopImports.add('$rel:${i + 1}');
          }
          if (low.contains('hiddify') || code.contains('هیدیفای')) {
            final bool allowedCoreId = rel.endsWith('lib/vpn/umbrella_core.dart') &&
                (trimmed == "static const String id = 'hiddify';" ||
                    trimmed == "'hiddify',");
            if (!allowedCoreId) {
              brandHits.add('$rel:${i + 1}: $trimmed');
            }
          }
          if (rel.contains('lib/ui/') && code.contains('ویندوز')) {
            windowsUiHits.add('$rel:${i + 1}: $trimmed');
          }
        }
      }
      expect(desktopImports, isEmpty);
      expect(brandHits, isEmpty);
      expect(windowsUiHits, isEmpty);
    });

    test('zero public, free, or shared fallback subscription sources', () {
      expect(AppConfig.subscriptionSources, isEmpty);
      expect(AppConfig.allowedSubscriptionHosts, <String>[
        'user.umbrella-server.ir',
      ]);
      expect(AppConfig.tunAdapterHint, 'tun0');
    });
  });

  group('Android DeviceProfile, Per-App Routing, and Core Engine Settings', () {
    test('DeviceProfile formats Android OS, SDK, patch, ABI, CPU, and network in Persian', () {
      final DeviceProfile profile = DeviceProfile.fromNative(<String, dynamic>{
        'hostname': 'Samsung SM-S938B',
        'username': 'Samsung',
        'os': 'Android 16 (SDK 36)',
        'osEdition': '2026-10-01',
        'osDisplayVersion': '16',
        'osBuild': 36,
        'arch': 'arm64-v8a',
        'cpu': 'Qualcomm Snapdragon 8 Elite',
        'cpuCores': 8,
        'ramTotalMb': 12288,
        'ramUsedMb': 6144,
        'ramLoadPercent': 50,
        'diskTotalMb': 262144,
        'diskFreeMb': 131072,
        'screenWidth': 1080,
        'screenHeight': 2340,
        'hasBattery': true,
        'batteryPercent': 88,
        'powerPlugged': true,
        'uptimeSeconds': 7200,
        'adapterName': 'شبکه وای فای',
        'localIp': '192.168.1.10',
        'machineId': 'abcdef0123456789',
        'elevated': true,
      });

      expect(profile.osTitleFa, Fa.num('اندروید 16'));
      expect(profile.osLabelFa, contains(Fa.num('36')));
      expect(profile.archLabelFa, 'آرم ۶۴ بیتی');
      expect(profile.osVersionLabelFa, contains('بسته امنیتی'));
      expect(profile.cpuLabelFa, contains('کوالکام اسنپدراگون'));
      expect(profile.adapterLabelFa, 'شبکه وای فای');
      expect(profile.formFactorFa, 'گوشی هوشمند اندروید');
      expect(profile.elevated, isTrue);
    });

    test('AppRouteRule validates Android package IDs and emits package_name rules', () {
      const AppRouteRule bankBypass = AppRouteRule(
        process: 'ir.divar',
        action: AppRouteAction.direct,
      );
      expect(bankBypass.validationError, isNull);
      expect(bankBypass.toCoreRule(0), <String, dynamic>{
        'list_order': 0,
        'enabled': true,
        'name': 'ir.divar',
        'outbound': 'direct',
        'package_name': <String>['ir.divar'],
      });

      const AppRouteRule selfRule = AppRouteRule(process: 'ir.umbrella.vpn');
      expect(selfRule.validationError, isNotNull);

      const AppRouteRule desktopExe = AppRouteRule(process: 'chrome.exe');
      expect(desktopExe.validationError, isNotNull);
    });

    test('UmbrellaCore.settingsJson builds valid Android non-root TUN & routing payload', () {
      final AppSettings settings = const AppSettings().copyWith(
        serviceMode: InboundServiceMode.vpn,
        routingRegion: RoutingRegion.ir,
        blockAds: true,
        allowConnectionFromLan: true,
        appRoutes: const <AppRouteRule>[
          AppRouteRule(process: 'ir.divar', action: AppRouteAction.direct),
          AppRouteRule(
            process: 'org.telegram.messenger',
            action: AppRouteAction.proxy,
          ),
        ],
      );
      final Map<String, dynamic> payload = UmbrellaCore.settingsJson(
        tun: true,
        systemProxy: false,
        port: 12334,
        networkSettings: settings,
      );

      expect(payload['enable-tun'], isTrue);
      expect(payload['enable-tun-service'], isFalse);
      expect(payload['tun-implementation'], 'mixed');
      expect(payload['auto-redirect'], isFalse);
      expect(payload['enable-clash-api'], isTrue);
      expect(payload['clash-api-port'], AppConfig.coreClashPort);
      expect(payload['web-secret'], AppConfig.coreClashSecret);
      expect(payload['allow-connection-from-lan'], isTrue);

      final Map<String, dynamic> routeRule =
          payload['route-rule'] as Map<String, dynamic>;
      final List<dynamic> rules = routeRule['rules'] as List<dynamic>;
      expect(rules.length, greaterThanOrEqualTo(4));
      expect(
        (rules[0] as Map<String, dynamic>)['package_name'],
        <String>['ir.divar'],
      );
      expect(
        (rules[1] as Map<String, dynamic>)['package_name'],
        <String>['org.telegram.messenger'],
      );
    });
  });

  group('Android ABI-Aware APK Update Verification', () {
    final Map<String, dynamic> sampleAndroidRelease = <String, dynamic>{
      'tag_name': 'v1.2.0-android',
      'draft': false,
      'prerelease': false,
      'published_at': '2026-11-17T10:00:00Z',
      'body': 'نسخه جدید اندروید آمبرلا',
      'assets': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'UmbrellaVPN-1.2.0-arm64-v8a.apk',
          'browser_download_url':
              'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/v1.2.0-android/UmbrellaVPN-1.2.0-arm64-v8a.apk',
          'size': 48200000,
          'digest':
              'sha256:1111111111111111111111111111111111111111111111111111111111111111',
        },
        <String, dynamic>{
          'name': 'UmbrellaVPN-1.2.0-armeabi-v7a.apk',
          'browser_download_url':
              'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/v1.2.0-android/UmbrellaVPN-1.2.0-armeabi-v7a.apk',
          'size': 44100000,
          'digest':
              'sha256:2222222222222222222222222222222222222222222222222222222222222222',
        },
        <String, dynamic>{
          'name': 'UmbrellaVPN-1.2.0-x86_64.apk',
          'browser_download_url':
              'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/v1.2.0-android/UmbrellaVPN-1.2.0-x86_64.apk',
          'size': 50300000,
          'digest':
              'sha256:3333333333333333333333333333333333333333333333333333333333333333',
        },
        <String, dynamic>{
          'name': 'UmbrellaVPN-1.2.0-universal.apk',
          'browser_download_url':
              'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/v1.2.0-android/UmbrellaVPN-1.2.0-universal.apk',
          'size': 112000000,
          'digest':
              'sha256:4444444444444444444444444444444444444444444444444444444444444444',
        },
      ],
    };

    test('selects exact ABI APK + SHA-256 and ignores Windows .exe releases', () {
      final UpdateInfo? arm64 = UpdateService.parseGithubRelease(
        sampleAndroidRelease,
        includePreReleases: false,
        preferredAbi: 'arm64-v8a',
      );
      expect(arm64, isNotNull);
      expect(arm64!.version, '1.2.0');
      expect(arm64.preRelease, isFalse);
      expect(arm64.isNewer, isTrue);
      expect(arm64.assetName, 'UmbrellaVPN-1.2.0-arm64-v8a.apk');
      expect(
        arm64.sha256,
        '1111111111111111111111111111111111111111111111111111111111111111',
      );

      final UpdateInfo? armv7 = UpdateService.parseGithubRelease(
        sampleAndroidRelease,
        includePreReleases: false,
        preferredAbi: 'armeabi-v7a',
      );
      expect(armv7!.assetName, 'UmbrellaVPN-1.2.0-armeabi-v7a.apk');

      final UpdateInfo? x64 = UpdateService.parseGithubRelease(
        sampleAndroidRelease,
        includePreReleases: false,
        preferredAbi: 'x86_64',
      );
      expect(x64!.assetName, 'UmbrellaVPN-1.2.0-x86_64.apk');

      final UpdateInfo? winOnly = UpdateService.parseGithubRelease(
        <String, dynamic>{
          'tag_name': 'v1.5.0-windows',
          'draft': false,
          'prerelease': false,
          'assets': <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'UmbrellaVPN-Setup-1.5.0-x64.exe',
              'browser_download_url':
                  'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/v1.5.0-windows/UmbrellaVPN-Setup-1.5.0-x64.exe',
            },
          ],
        },
        includePreReleases: true,
      );
      expect(winOnly, isNull);
    });
  });

  group('Personal Subscription Sync + App-Gateway Relay', () {
    test('downloads only personal subscription and falls back to gateway relay', () async {
      const String vlessSample =
          'vless://11111111-2222-3333-4444-555555555555@de1.umbrella-server.ir:443?encryption=none&security=tls&sni=de1.umbrella-server.ir&type=ws&path=%2Fws#DE-Umbrella-1';
      const Account account = Account(
        uuid: '9f7b5c1a-2233-4455-8899-aabbccddeeff',
        name: 'آرمین',
        enable: true,
        isActive: true,
        subscriptionUrl:
            'https://user.umbrella-server.ir/D6qnVQXRwa/9f7b5c1a-2233-4455-8899-aabbccddeeff/sub/',
      );
      final SessionData relaySession = SessionData(
        token: 'tok-relay-test',
        uuid: account.uuid,
        deviceId: 'android-relay-test',
        account: account,
        filter: FilterSettings.empty,
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        StoreKeys.deviceId: 'android-relay-test',
        StoreKeys.session: jsonEncode(relaySession.toJson()),
      });
      final LocalStore store = LocalStore.instance;
      await store.init();
      await store.write(StoreKeys.deviceId, 'android-relay-test');
      await store.writeJson(StoreKeys.session, relaySession.toJson());
      await store.deleteFile(StoreKeys.nodesCache);

      final MockClient relayClient = MockClient((http.Request req) async {
        if (req.url.host == 'user.umbrella-server.ir') {
          throw const SocketException('direct host blocked');
        }
        final String query = req.url.toString();
        if (query.contains('subscription/fetch') ||
            query.contains('subscription%2Ffetch')) {
          return http.Response(
            jsonEncode(<String, Object>{
              'ok': true,
              'content': base64Encode(utf8.encode('$vlessSample\n')),
              'subscription_url': account.subscriptionUrl,
              'account_base': AppConfig.subscriptionBaseUrl,
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }
        return http.Response(jsonEncode(<String, Object>{'ok': true}), 200);
      });

      final NativeBridge native = NativeBridge();
      final GatewayClient gateway = GatewayClient(
        client: relayClient,
        enableNativeTransport: false,
      );
      final AuthController auth = AuthController(
        native: native,
        store: store,
        gateway: gateway,
      );
      await auth.restore();
      final VpnController vpn = VpnController(
        native: native,
        ipService: _OfflineIpService(),
        sound: _SilentSound(),
        tray: TrayService(native),
        provisioner: CoreProvisioner(),
        settings: const AppSettings(),
        onSettingsChanged: (AppSettings _) {},
        onRequireElevation: () {},
        onRequireCores: () {},
        canAutoConnect: () => false,
      );
      final SubscriptionController subs = SubscriptionController(
        vpn: vpn,
        auth: auth,
        client: relayClient,
        enableNativeTransport: false,
      );
      addTearDown(() async {
        subs.dispose();
        await subs.close();
        vpn.dispose();
        auth.dispose();
        await store.deleteFile(StoreKeys.nodesCache);
      });

      await subs.syncPersonal();
      expect(vpn.nodes.length, 1);
      expect(vpn.nodes.single.host, 'de1.umbrella-server.ir');
      expect(subs.sources.length, 1);
      expect(subs.sources.single.source.id, 'user-sub');
    });
  });

  group('Responsive Flutter Android UI (Phone 360dp & Tablet 1280dp)', () {
    testWidgets('LandingPage and LoginPage render cleanly on 360x780 Android phone',
        (WidgetTester tester) async {
      _installMockNativeChannel(tester);
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final _HarnessBundle bundle = await _buildTestHarness(
        tester: tester,
        landingSeen: false,
        signedIn: false,
      );
      await tester.pumpWidget(bundle.widget);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('آمبرلا'), findsWidgets);
      expect(find.text('شروع'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('شروع'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('شماره موبایل'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(bundle.disposeAsync);
    });

    testWidgets('AppShell renders MobileBottomNav + Drawer + pages on 390x844 phone',
        (WidgetTester tester) async {
      _installMockNativeChannel(tester);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final _HarnessBundle bundle = await _buildTestHarness(
        tester: tester,
        landingSeen: true,
        signedIn: true,
      );
      await tester.pumpWidget(bundle.widget);
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.byType(MobileBottomNav), findsOneWidget);
      expect(find.byType(SideNav), findsNothing);
      expect(tester.takeException(), isNull);

      for (final String tab in <String>['دستگاه من', 'حساب من', 'تنظیمات']) {
        await tester.tap(find.text(tab).last);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      }

      await tester.tap(find.text('بیشتر'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('گزارش ها'), findsOneWidget);
      expect(find.text('درباره'), findsOneWidget);
      expect(find.text('به روز رسانی'), findsOneWidget);

      await tester.tap(find.text('درباره'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.textContaining('اندروید'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(bundle.disposeAsync);
    });

    testWidgets('AppShell renders SideNav layout on 1280x800 Android tablet',
        (WidgetTester tester) async {
      _installMockNativeChannel(tester);
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final _HarnessBundle bundle = await _buildTestHarness(
        tester: tester,
        landingSeen: true,
        signedIn: true,
      );
      await tester.pumpWidget(bundle.widget);
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.byType(SideNav), findsOneWidget);
      expect(find.byType(MobileBottomNav), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(bundle.disposeAsync);
    });
  });
}
