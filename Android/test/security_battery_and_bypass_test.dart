import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbrella_vpn/core/malicious_link_guard.dart';
import 'package:umbrella_vpn/core/persian.dart';
import 'package:umbrella_vpn/core/safe_url_launcher.dart';
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
import 'package:umbrella_vpn/ui/pages/connect_page.dart';
import 'package:umbrella_vpn/vpn/runtime_config.dart';
import 'package:umbrella_vpn/vpn/umbrella_core.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _TestNative implements NativeBridge {
  @override
  bool get available => true;

  @override
  Future<bool> isElevated() async => true;

  @override
  Future<Map<String, dynamic>> getPlatformInfo() async => <String, dynamic>{
        'batteryPercent': 42,
        'powerPlugged': false,
        'isPowerSaveMode': true,
      };

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => false;

  @override
  Future<BatteryPowerState> powerStatus() async {
    final Map<String, dynamic> info = await getPlatformInfo();
    return BatteryPowerState(
      hasBattery: true,
      onBattery: !(info['powerPlugged'] as bool),
      energySaver: info['isPowerSaveMode'] as bool,
      powerKnown: true,
      batteryPercent: info['batteryPercent'] as int,
      ignoringBatteryOptimizations: false,
    );
  }

  @override
  Future<DeviceProfile> deviceInfo() async => const DeviceProfile(
        hostname: 'Android Phone',
        username: 'Pixel',
        batteryPercent: 42,
        powerPlugged: false,
      );

  @override
  Future<bool> startSecurityFileWatcher() async => true;

  @override
  Future<bool> stopSecurityFileWatcher() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestVpn extends ChangeNotifier implements VpnController {
  @override
  VpnStatus get status => VpnStatus.disconnected;

  @override
  DeviceProfile get device => const DeviceProfile(hostname: 'Android Phone');

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
  void setAppVisible(bool visible) {}

  @override
  void setBatterySaving(bool value) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.instance.init();
  });

  test('Android bundles all 6 valid offline Iran SRS v1 rule-sets', () {
    for (final String name in const <String>[
      'geoip-ir.srs',
      'geosite-ir.srs',
      'geoip-arvancloud.srs',
      'geoip-parspack.srs',
      'geoip-derakcloud.srs',
      'geoip-iranserver.srs',
    ]) {
      final File file = File('${Directory.current.path}/assets/data/$name');
      expect(file.existsSync(), isTrue, reason: 'missing $name');
      final List<int> bytes = file.readAsBytesSync();
      expect(bytes.length, greaterThan(16));
      expect(utf8.decode(bytes.sublist(0, 3)), 'SRS');
      expect(bytes[3], 1);
    }
  });

  test('Android powerStatus exposes PowerManager isPowerSaveMode independently', () async {
    final _TestNative native = _TestNative();
    final BatteryPowerState state = await native.powerStatus();
    expect(state.energySaver, isTrue);
    expect(state.onBattery, isTrue);
    expect(state.ignoringBatteryOptimizations, isFalse);
  });

  test('Android SafeUrlLauncher blocks unsafe domains and allows verified links', () async {
    int launched = 0;
    MaliciousLinkMatch? blocked;
    final void Function(Uri, MaliciousLinkMatch)? prev =
        SafeUrlLauncher.onThreatBlocked;
    SafeUrlLauncher.onThreatBlocked = (_, MaliciousLinkMatch m) => blocked = m;
    addTearDown(() => SafeUrlLauncher.onThreatBlocked = prev);

    expect(
      await SafeUrlLauncher.open(
        Uri.parse('https://iplogger.org/trap'),
        launcher: (_, __) async {
          launched++;
          return true;
        },
      ),
      isFalse,
    );
    expect(launched, 0);
    expect(blocked, isNotNull);

    expect(
      await SafeUrlLauncher.open(
        Uri.parse('https://umbrella-vpn.example/help'),
        launcher: (_, __) async {
          launched++;
          return true;
        },
      ),
      isTrue,
    );
    expect(launched, 1);
  });

  test('Android RuntimeConfig.finalize & UmbrellaCore.settingsJson honor IP bypass and battery interval', () {
    final Map<String, dynamic> settings = UmbrellaCore.settingsJson(
      tun: true,
      systemProxy: false,
      port: 12334,
      networkSettings: const AppSettings(),
      contentFilter: const FilterSettings(
        bypassIran: true,
        bypassDomains: <String>['digikala.com', '194.5.175.0/24'],
      ),
      batterySaving: true,
    );
    expect(settings['url-test-interval'], 1800);

    final Map<String, dynamic> runtime = <String, dynamic>{
      'outbounds': <dynamic>[
        <String, dynamic>{'type': 'direct', 'tag': RuntimeConfig.directOutboundTag},
        <String, dynamic>{'type': 'selector', 'tag': 'select'},
      ],
      'dns': <String, dynamic>{
        'servers': <dynamic>[
          <String, dynamic>{'tag': 'dns-remote', 'type': 'udp', 'server': '1.1.1.1'},
          <String, dynamic>{'tag': 'dns-direct', 'type': 'udp', 'server': '8.8.8.8'},
        ],
        'rules': <dynamic>[
          <String, dynamic>{'domain': <String>['example.org'], 'server': 'dns-fake'},
        ],
      },
      'route': <String, dynamic>{
        'rule_set': <dynamic>[],
        'rules': <dynamic>[
          <String, dynamic>{'action': 'resolve'},
        ],
      },
    };
    RuntimeConfig.finalize(
      runtime,
      settings: const AppSettings(),
      filter: const FilterSettings(
        bypassIran: true,
        bypassDomains: <String>['digikala.com', '194.5.175.0/24'],
      ),
      dataDir: '/data/user/0/ir.umbrella.vpn/files/data',
    );
    final List<Map<String, dynamic>> routeRules =
        ((runtime['route'] as Map<String, dynamic>)['rules'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
    final int resolveIdx = routeRules.indexWhere((r) => r['action'] == 'resolve');
    expect(resolveIdx, greaterThan(0));
    expect(
      routeRules.any(
        (r) =>
            r['ip_cidr'] is List &&
            (r['ip_cidr'] as List).contains('194.5.175.0/24'),
      ),
      isTrue,
    );
  });

  testWidgets(
    'Android ConnectPage renders custom vector protocol logo cards & channel-disabled banner without overflow',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final _TestNative native = _TestNative();
      final GatewayClient gw = GatewayClient(
        baseUrl: 'https://gateway.example.test',
        enableNativeTransport: false,
        client: MockClient(
          (http.Request req) async => http.Response('{"ok":true}', 200),
        ),
      );
      final AuthController auth = AuthController(
        native: native,
        gateway: gw,
        store: LocalStore.instance,
      );
      final _TestVpn vpn = _TestVpn();
      final SettingsController settings = SettingsController(
        native: native,
        sound: SoundService(),
        window: WindowService(),
      );
      final SubscriptionController subs = SubscriptionController(
        vpn: vpn,
        auth: auth,
        client: gw,
        enableNativeTransport: false,
      );
      final ToastController toasts = ToastController();

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
      expect(tester.takeException(), isNull);
      for (final String mode in const <String>[
        'user-sub',
        'user-wireguard',
        'user-amnezia',
        'user-mieru',
      ]) {
        final Finder card = find.byKey(ValueKey<String>('connection-profile-$mode'));
        expect(card, findsOneWidget);
        expect(find.descendant(of: card, matching: find.byType(CustomPaint)), findsWidgets);
      }

      await tester.tap(find.byKey(const ValueKey<String>('connection-profile-user-amnezia')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(Fa.stripEmojis('⚠️ هشدار'), 'هشدار');

      await tester.pumpWidget(const SizedBox());
      subs.dispose();
      auth.dispose();
      settings.dispose();
      gw.close();
    },
  );
}
