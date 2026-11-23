import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbrella_vpn/core/storage.dart';
import 'package:umbrella_vpn/data/gateway_client.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/state/auth_controller.dart';

class _TestNative implements NativeBridge {
  @override
  Future<DeviceProfile> deviceInfo() async => const DeviceProfile(
        hostname: 'TEST-PC',
        os: 'Windows 11',
        arch: 'x64',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<AuthController> _createRestoredAuth({
  required Account initialAccount,
  required MockClient client,
  String token = 'tok-sync-test',
}) async {
  final Map<String, Object> initialPrefs = <String, Object>{
    StoreKeys.deviceId: 'win64-sync-device',
    StoreKeys.session: jsonEncode(
      SessionData(
        token: token,
        uuid: initialAccount.uuid,
        deviceId: 'win64-sync-device',
        account: initialAccount,
        filter: FilterSettings.empty,
      ).toJson(),
    ),
  };
  SharedPreferences.setMockInitialValues(initialPrefs);
  final LocalStore store = LocalStore.instance;
  await store.init();
  await store.write(StoreKeys.deviceId, 'win64-sync-device');
  await store.writeJson(
    StoreKeys.session,
    SessionData(
      token: token,
      uuid: initialAccount.uuid,
      deviceId: 'win64-sync-device',
      account: initialAccount,
      filter: FilterSettings.empty,
    ).toJson(),
  );

  final AuthController auth = AuthController(
    native: _TestNative(),
    store: store,
    gateway: GatewayClient(
      baseUrl: 'https://gateway.example.test',
      enableNativeTransport: false,
      client: client,
    ),
  );
  await auth.restore();
  // Wait for the microtask/future refresh fired by restore() to settle.
  await Future<void>.delayed(const Duration(milliseconds: 10));
  return auth;
}

http.Response _jsonResponse(Map<String, dynamic> body, {int status = 200}) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: const <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String uuid = '11111111-2222-4333-8444-555555555555';

  test('emergency chip uses emergency_rounded and drops legacy emergency list link', () {
    final String connect =
        File('lib/ui/pages/connect_page.dart').readAsStringSync();
    expect(connect, contains("ValueKey<String>('connection-profile-emergency')"));
    expect(connect, contains('Icons.emergency_rounded'));
    expect(connect, contains("const Text('اضطراری')"));
    expect(
      connect,
      contains('مسیرهای عمومی اضطراری متعلق به اشخاص ثالث هستند'),
    );
    expect(connect, isNot(contains('emergency_list.dart')));
    expect(connect, isNot(contains('showEmergencyList')));
    expect(connect, isNot(contains('e911_emergency')));
  });

  test('heartbeat and autoSync propagate live account, bot link, filter, and subscription resync', () async {
    bool upgraded = false;
    int subResyncs = 0;

    final Account initial = Account(
      uuid: uuid,
      name: 'کاربر آزمایشی',
      phone: '09120000000',
      usageLimitGb: 1,
      currentUsageGb: 0.2,
      packageDays: 1,
      expiryDate: DateTime.now().toUtc().add(const Duration(hours: 12)),
      enable: true,
      isActive: true,
    );

    Map<String, dynamic> currentAccountPayload() => upgraded
        ? <String, dynamic>{
            'uuid': uuid,
            'name': 'آرمین محمدی',
            'phone': '09120000000',
            'telegram_id': '778899',
            'usage_limit_GB': 60,
            'current_usage_GB': 4.5,
            'package_days': 30,
            'expire_date':
                DateTime.now().toUtc().add(const Duration(days: 30)).toIso8601String(),
            'enable': true,
            'is_active': true,
            'emergency_enabled': true,
            'subscription_url': 'https://sub.example.test/secret/$uuid/sub/',
            'account_base': 'https://sub.example.test/secret/',
          }
        : <String, dynamic>{
            'uuid': uuid,
            'name': 'کاربر آزمایشی',
            'phone': '09120000000',
            'usage_limit_GB': 1,
            'current_usage_GB': 0.2,
            'package_days': 1,
            'expire_date':
                DateTime.now().toUtc().add(const Duration(hours: 12)).toIso8601String(),
            'enable': true,
            'is_active': true,
            'emergency_enabled': false,
          };

    final MockClient client = MockClient((http.Request request) async {
      final String path = request.url.path;
      if (path.endsWith('/auth/device')) {
        return _jsonResponse(<String, dynamic>{
          'ok': true,
          'emergency_enabled': upgraded,
          'bot_linked': upgraded,
          'account': currentAccountPayload(),
          'filter': <String, dynamic>{
            'enabled': upgraded,
            'categories': upgraded ? <String>['ads'] : <String>[],
          },
          'offers': <String, dynamic>{
            'free_available': false,
            'free_claimed': true,
            'nowruz_menu_enabled': false,
          },
        });
      }
      if (path.endsWith('/account/refresh')) {
        return _jsonResponse(<String, dynamic>{
          'ok': true,
          'account': currentAccountPayload(),
          'filter': <String, dynamic>{
            'enabled': upgraded,
            'categories': upgraded ? <String>['ads'] : <String>[],
          },
          'offers': <String, dynamic>{
            'free_available': false,
            'free_claimed': true,
            'nowruz_menu_enabled': false,
          },
        });
      }
      if (path.endsWith('/app/notifications')) {
        return _jsonResponse(<String, dynamic>{'ok': true, 'items': <Object>[]});
      }
      return _jsonResponse(<String, dynamic>{'ok': true});
    });

    final AuthController auth = await _createRestoredAuth(
      initialAccount: initial,
      client: client,
    );
    addTearDown(auth.dispose);

    auth.onSubscriptionClaimed = () async {
      subResyncs++;
    };

    upgraded = true;
    await auth.autoSync(includeAccount: false);

    expect(auth.botLinked, isTrue);
    expect(auth.account.name, 'آرمین محمدی');
    expect(auth.account.usageLimitGb, 60);
    expect(auth.account.currentUsageGb, 4.5);
    expect(auth.account.packageDays, 30);
    expect(auth.account.emergencyEnabled, isTrue);
    expect(auth.filter.enabled, isTrue);
    expect(auth.filter.categories, <String>['ads']);
    expect(subResyncs, 1);
  });

  test('refreshAccount updates usage/profile even when quota cap unchanged and triggers onAccessRevoked on disable', () async {
    bool activeOnServer = true;
    String accessRevokedReason = '';

    final Account initial = Account(
      uuid: uuid,
      name: 'قدیمی',
      phone: '09120000000',
      usageLimitGb: 50,
      currentUsageGb: 1,
      packageDays: 30,
      expiryDate: DateTime.now().toUtc().add(const Duration(days: 20)),
      enable: true,
      isActive: true,
    );

    final MockClient client = MockClient((http.Request request) async {
      if (request.url.path.endsWith('/account/refresh')) {
        return _jsonResponse(<String, dynamic>{
          'ok': true,
          'account': <String, dynamic>{
            'uuid': uuid,
            'name': 'جدید',
            'phone': '09120000000',
            'usage_limit_GB': 50,
            'current_usage_GB': 12.75,
            'package_days': 30,
            'expire_date':
                DateTime.now().toUtc().add(const Duration(days: 20)).toIso8601String(),
            'enable': activeOnServer,
            'is_active': activeOnServer,
          },
          'filter': <String, dynamic>{'enabled': false},
          'offers': <String, dynamic>{},
        });
      }
      return _jsonResponse(<String, dynamic>{'ok': true, 'items': <Object>[]});
    });

    final AuthController auth = await _createRestoredAuth(
      initialAccount: initial,
      client: client,
    );
    addTearDown(auth.dispose);

    expect(auth.account.name, 'جدید');
    expect(auth.account.currentUsageGb, 12.75);
    expect(auth.account.canConnect, isTrue);

    auth.onAccessRevoked = (String reason) {
      accessRevokedReason = reason;
    };

    activeOnServer = false;
    final bool ok = await auth.refreshAccount(silent: true);
    expect(ok, isTrue);
    expect(auth.account.canConnect, isFalse);
    expect(accessRevokedReason, isNotEmpty);
  });

  test('heartbeat 403 device_revoked clears session and triggers onSessionRevoked', () async {
    String revokedMessage = '';

    final Account initial = Account(
      uuid: uuid,
      name: 'کاربر',
      phone: '09120000000',
      usageLimitGb: 30,
      packageDays: 30,
      expiryDate: DateTime.now().toUtc().add(const Duration(days: 20)),
      enable: true,
      isActive: true,
    );

    final MockClient client = MockClient((http.Request request) async {
      if (request.url.path.endsWith('/auth/device')) {
        return _jsonResponse(
          <String, dynamic>{
            'ok': false,
            'error': 'device_revoked',
            'message': 'این دستگاه از پنل یا ربات حذف شده است.',
          },
          status: 403,
        );
      }
      if (request.url.path.endsWith('/account/refresh')) {
        return _jsonResponse(<String, dynamic>{
          'ok': true,
          'account': <String, dynamic>{
            'uuid': uuid,
            'name': 'کاربر',
            'phone': '09120000000',
            'usage_limit_GB': 30,
            'package_days': 30,
            'expire_date':
                DateTime.now().toUtc().add(const Duration(days: 20)).toIso8601String(),
            'enable': true,
            'is_active': true,
          },
          'filter': <String, dynamic>{},
          'offers': <String, dynamic>{},
        });
      }
      return _jsonResponse(<String, dynamic>{'ok': true, 'items': <Object>[]});
    });

    final AuthController auth = await _createRestoredAuth(
      initialAccount: initial,
      client: client,
    );
    addTearDown(auth.dispose);

    auth.onSessionRevoked = (String reason) async {
      revokedMessage = reason;
    };

    await auth.autoSync(includeAccount: false);

    expect(revokedMessage, contains('حذف'));
    expect(auth.signedIn, isFalse);
    expect(auth.session, isNull);
  });
}
