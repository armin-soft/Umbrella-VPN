import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    FlutterError.onError = (FlutterErrorDetails d) => errors.add(d);
    addTearDown(() => FlutterError.onError = prevError);

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
}
