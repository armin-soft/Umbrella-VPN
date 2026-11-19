import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:umbrella_vpn/core/app_config.dart';
import 'package:umbrella_vpn/core/storage.dart';
import 'package:umbrella_vpn/data/gateway_client.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/platform/services.dart';
import 'package:umbrella_vpn/state/auth_controller.dart';
import 'package:umbrella_vpn/state/subscription_controller.dart';
import 'package:umbrella_vpn/vpn/core_provisioner.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

class _TestHarness {
  _TestHarness._({
    required this.auth,
    required this.vpn,
  });

  final AuthController auth;
  final VpnController vpn;

  static Future<_TestHarness> create({
    required String token,
    required Account account,
    GatewayClient? gateway,
    List<VpnNode> cachedNodes = const <VpnNode>[],
  }) async {
    final Map<String, Object> initialPrefs = <String, Object>{};
    if (token.isNotEmpty) {
      initialPrefs[StoreKeys.session] = jsonEncode(
        SessionData(
          token: token,
          uuid: account.uuid,
          deviceId: 'win64-test-device',
          account: account,
          filter: FilterSettings.empty,
        ).toJson(),
      );
      initialPrefs[StoreKeys.deviceId] = 'win64-test-device';
    }
    SharedPreferences.setMockInitialValues(initialPrefs);
    final LocalStore store = LocalStore.instance;
    await store.init();
    await store.remove(StoreKeys.session);
    if (token.isNotEmpty) {
      await store.writeJson(
        StoreKeys.session,
        SessionData(
          token: token,
          uuid: account.uuid,
          deviceId: 'win64-test-device',
          account: account,
          filter: FilterSettings.empty,
        ).toJson(),
      );
      await store.write(StoreKeys.deviceId, 'win64-test-device');
    }
    if (cachedNodes.isNotEmpty) {
      await store.writeFile(
        StoreKeys.nodesCache,
        jsonEncode(cachedNodes.map((VpnNode n) => n.toJson()).toList()),
      );
    } else {
      await store.deleteFile(StoreKeys.nodesCache);
    }

    final NativeBridge native = NativeBridge();
    final SoundService sound = SoundService();
    final TrayService tray = TrayService(native);
    final VpnController vpn = VpnController(
      native: native,
      ipService: IpService(),
      sound: sound,
      tray: tray,
      provisioner: CoreProvisioner(),
      settings: const AppSettings(),
      onSettingsChanged: (AppSettings _) {},
      onRequireElevation: () {},
      onRequireCores: () {},
    );
    final AuthController auth = AuthController(
      native: native,
      store: store,
      gateway: gateway,
    );
    await auth.restore();
    return _TestHarness._(auth: auth, vpn: vpn);
  }

  Future<void> dispose(SubscriptionController subs) async {
    subs.dispose();
    await subs.close();
    auth.dispose();
    vpn.dispose();
    await LocalStore.instance.deleteFile(StoreKeys.nodesCache);
  }
}

class _SwitchableClient extends http.BaseClient {
  int calls = 0;
  bool shouldFail = true;
  String payload = '';
  int statusCode = 200;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    if (shouldFail) {
      throw const SocketException('unreachable');
    }
    final List<int> bytes = utf8.encode(payload);
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      statusCode,
      headers: <String, String>{'content-type': 'text/plain; charset=utf-8'},
      request: request,
    );
  }
}

class _GatewayRelayClient extends http.BaseClient {
  _GatewayRelayClient({
    required this.subscriptionBody,
    required this.subscriptionUrl,
  });

  final String subscriptionBody;
  final String subscriptionUrl;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final String route = request.url.queryParameters['AppApi'] ?? '';
    Map<String, dynamic> payload;
    if (route == 'subscription/fetch') {
      payload = <String, dynamic>{
        'ok': true,
        'subscription_url': subscriptionUrl,
        'account_base': AppConfig.subscriptionBaseUrl,
        'content': subscriptionBody,
      };
    } else if (route == 'auth/session') {
      payload = <String, dynamic>{
        'ok': true,
        'account': <String, dynamic>{
          'uuid': 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
          'name': 'کاربر آزمایشی',
          'phone': '09123456789',
          'subscription_url': subscriptionUrl,
          'account_base': AppConfig.subscriptionBaseUrl,
          'usage_limit_GB': 50,
          'current_usage_GB': 2,
          'package_days': 30,
          'enable': true,
          'is_active': true,
        },
      };
    } else {
      payload = <String, dynamic>{'ok': true};
    }
    final List<int> bytes = utf8.encode(jsonEncode(payload));
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      200,
      headers: <String, String>{'content-type': 'application/json'},
      request: request,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel nativeChannel = MethodChannel('umbrella/native');
  const String userUuid = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
  const String sampleSub =
      'vless://aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee@nl1.example.com:443?encryption=none&security=tls&sni=nl1.example.com#NL-01\n'
      'vless://aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee@de1.example.com:443?encryption=none&security=tls&sni=de1.example.com#DE-01\n';

  Account activeAccount() => Account(
        uuid: userUuid,
        name: 'کاربر آزمایشی',
        phone: '09123456789',
        accountBase: AppConfig.subscriptionBaseUrl,
        subscriptionUrl: '${AppConfig.subscriptionBaseUrl}$userUuid/sub/',
        usageLimitGb: 50,
        currentUsageGb: 2,
        packageDays: 30,
        expiryDate: DateTime.now().toUtc().add(const Duration(days: 25)),
        enable: true,
        isActive: true,
      );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, null);
  });

  test('در خطای شبکه هیچ منبع عمومی بارگذاری نمی شود و تلاش بعدی بدون قفل شدن موفق می شود',
      () async {
    final _SwitchableClient subHttp = _SwitchableClient()
      ..shouldFail = true
      ..payload = sampleSub;

    final GatewayClient fakeGateway = GatewayClient(
      enableNativeTransport: false,
      client: _SwitchableClient()..shouldFail = true,
    );

    final _TestHarness h = await _TestHarness.create(
      token: 'tok-test-1',
      account: activeAccount(),
      gateway: fakeGateway,
    );
    final SubscriptionController subs = SubscriptionController(
      vpn: h.vpn,
      auth: h.auth,
      client: subHttp,
      enableNativeTransport: false,
    );

    try {
      // ۱. تلاش اول در قطعی شبکه: هیچ منبع عمومی یا رایگانی بارگذاری نمی شود.
      await subs.syncPersonal();
      expect(h.vpn.nodes, isEmpty);
      expect(subs.sources, hasLength(1));
      expect(subs.sources.single.personal, isTrue);
      expect(
        subs.sources.single.source.url,
        '${AppConfig.subscriptionBaseUrl}$userUuid/sub/',
      );

      // ۲. پس از وصل شدن اینترنت، همان منبع شخصی کاربر بدون گیر کردن در حالت
      // «منابع عمومی» به درستی دریافت و به روز می شود.
      subHttp.shouldFail = false;
      await subs.syncPersonal();
      expect(h.vpn.nodes, hasLength(2));
      expect(
        h.vpn.nodes.every((VpnNode n) => n.sourceId == 'user-sub'),
        isTrue,
      );
    } finally {
      await h.dispose(subs);
    }
  });

  test('WinHTTP بومی ویندوز در ویندوز ۱۰/۱۱ شصت و چهار بیتی با پروکسی و مستقیم کار می کند',
      () async {
    final List<Map<String, dynamic>> nativeCalls = <Map<String, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
      if (call.method != 'httpRequest') {
        return null;
      }
      final Map<String, dynamic> args =
          Map<String, dynamic>.from(call.arguments as Map<Object?, Object?>);
      nativeCalls.add(args);
      final bool useProxy = args['useProxy'] == true;
      if (!useProxy) {
        return <String, Object?>{
          'ok': false,
          'status': 0,
          'winError': 12029,
          'error': 'cannot_connect',
        };
      }
      return <String, Object?>{
        'ok': true,
        'status': 200,
        'body': Uint8List.fromList(
          utf8.encode(base64Encode(utf8.encode(sampleSub))),
        ),
      };
    });

    final GatewayClient fakeGateway = GatewayClient(
      enableNativeTransport: false,
      client: _SwitchableClient()..shouldFail = true,
    );
    final _TestHarness h = await _TestHarness.create(
      token: 'tok-winhttp',
      account: activeAccount(),
      gateway: fakeGateway,
    );
    final SubscriptionController subs = SubscriptionController(
      vpn: h.vpn,
      auth: h.auth,
      enableNativeTransport: true,
    );

    try {
      // چند فراخوانی هم زمان در یک درخواست واحد ادغام می شوند.
      await Future.wait(<Future<void>>[
        subs.syncPersonal(),
        subs.syncPersonal(),
        subs.syncPersonal(),
      ]);
      expect(nativeCalls, hasLength(2));
      expect(nativeCalls[0]['useProxy'], isFalse);
      expect(nativeCalls[1]['useProxy'], isTrue);
      expect(h.vpn.nodes, hasLength(2));
    } finally {
      await h.dispose(subs);
    }
  });

  test('وقتی دامنه پنل اشتراک مسدود است، اشتراک اختصاصی کاربر از درگاه امن دریافت می شود',
      () async {
    final GatewayClient relayGateway = GatewayClient(
      enableNativeTransport: false,
      client: _GatewayRelayClient(
        subscriptionBody: sampleSub,
        subscriptionUrl: '${AppConfig.subscriptionBaseUrl}$userUuid/sub/',
      ),
    );
    final _TestHarness h = await _TestHarness.create(
      token: 'tok-relay',
      account: activeAccount(),
      gateway: relayGateway,
    );
    final SubscriptionController subs = SubscriptionController(
      vpn: h.vpn,
      auth: h.auth,
      client: _SwitchableClient()..shouldFail = true,
      enableNativeTransport: false,
    );

    try {
      await subs.syncPersonal();
      expect(h.vpn.nodes, hasLength(2));
      expect(
        h.vpn.nodes.every((VpnNode n) => n.sourceId == 'user-sub'),
        isTrue,
      );

      // پس از خروج از حساب، تمام سرورها و منابع پاک می شوند.
      await h.auth.signOut(callServer: false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(subs.sources, isEmpty);
      expect(h.vpn.nodes, isEmpty);
    } finally {
      await h.dispose(subs);
    }
  });

  test('گره های کش شده قدیمی از منابع عمومی (`sub`) در نخستین اجرا پاک می شوند',
      () async {
    const VpnNode legacyPublic = VpnNode(
      id: 'legacy-1',
      sourceId: 'sub',
      protocol: NodeProtocol.vless,
      name: 'Old Public',
      host: 'old.example.com',
      port: 443,
      params: <String, dynamic>{},
      raw:
          'vless://9b9d9f5d-9841-45bf-a6b9-0479de273c11@old.example.com:443#Old',
    );
    const VpnNode personalNode = VpnNode(
      id: 'personal-1',
      sourceId: 'user-sub',
      protocol: NodeProtocol.vless,
      name: 'My Server',
      host: 'mine.example.com',
      port: 443,
      params: <String, dynamic>{},
      raw: 'vless://$userUuid@mine.example.com:443#Mine',
    );

    final GatewayClient fakeGateway = GatewayClient(
      enableNativeTransport: false,
      client: _SwitchableClient()..shouldFail = true,
    );
    final _TestHarness h = await _TestHarness.create(
      token: 'tok-cache',
      account: activeAccount(),
      gateway: fakeGateway,
      cachedNodes: const <VpnNode>[legacyPublic, personalNode],
    );
    final SubscriptionController subs = SubscriptionController(
      vpn: h.vpn,
      auth: h.auth,
      client: _SwitchableClient()..shouldFail = true,
      enableNativeTransport: false,
    );

    try {
      await subs.loadCached();
      expect(h.vpn.nodes, hasLength(1));
      expect(h.vpn.nodes.single.sourceId, 'user-sub');
      expect(h.vpn.nodes.single.host, 'mine.example.com');
    } finally {
      await h.dispose(subs);
    }
  });
}
