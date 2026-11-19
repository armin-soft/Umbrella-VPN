import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:umbrella_vpn/core/utils.dart';
import 'package:umbrella_vpn/data/gateway_client.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/platform/native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel nativeChannel = MethodChannel('ir.umbrella.app/native');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, null);
    GatewayClient.resetStickyTransportForTest();
    NativeBridge.resetHttpAvailabilityForTest();
  });

  group('پایداری ورود کاربر جدید روی تمام نسخه های ویندوز ۶۴ بیتی', () {
    test('بازارسالی خودکار فرم هنگام مسدودسازی بدنه JSON توسط فایروال وب', () async {
      final List<http.Request> seen = <http.Request>[];
      final MockClient mock = MockClient((http.Request request) async {
        seen.add(request);
        final String contentType = request.headers['Content-Type'] ?? '';
        if (contentType.contains('application/json')) {
          return http.Response(
            '<html><body>403 Forbidden by ModSecurity</body></html>',
            403,
          );
        }
        expect(
          contentType,
          contains('application/x-www-form-urlencoded'),
        );
        expect(request.bodyFields.containsKey('_json'), isTrue);
        final Map<String, dynamic> decoded =
            jsonDecode(request.bodyFields['_json']!) as Map<String, dynamic>;
        expect(decoded['phone'], '09123456789');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode(<String, dynamic>{
              'ok': true,
              'stage': 'needs_profile',
              'account_exists': false,
            }),
          ),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });

      final GatewayClient client = GatewayClient(
        baseUrl: 'https://armin-soft.ir/Tools/Telegram-BOT/Umbrella-VPN/index.php?AppApi=',
        client: mock,
      );
      addTearDown(client.close);

      final SignInStart start = await client.start(
        phone: '09123456789',
        deviceId: 'win64-test-device',
        deviceName: 'DESKTOP-TEST',
        platform: 'Windows 11 Pro x64',
      );

      expect(seen.length, 2);
      expect(
        seen.first.headers['User-Agent'],
        contains('Windows NT 10.0; Win64; x64'),
      );
      expect(start.stage, SignInStage.needsProfile);
      expect(start.accountExists, isFalse);
    });

    test('استخراج امن JSON حتی در حضور BOM یا خروجی اضافی پیش از پاسخ', () async {
      final MockClient mock = MockClient((http.Request request) async {
        const String noisyBody =
            '\uFEFF\n{"ok":true,"challenge":"aabbcc","stage":"code_sent","account_exists":false,"resend_after":60}';
        return http.Response.bytes(utf8.encode(noisyBody), 200);
      });

      final GatewayClient client = GatewayClient(
        baseUrl: 'https://armin-soft.ir/index.php?AppApi=',
        client: mock,
      );
      addTearDown(client.close);

      final SignInStart start = await client.start(
        phone: '09351234567',
        deviceId: 'win64-test-device-2',
        deviceName: 'PC-2',
        platform: 'Windows 10 Pro x64',
        firstName: 'امیر حسین',
        lastName: 'محمدی',
      );

      expect(start.stage, SignInStage.codeSent);
      expect(start.challenge, 'aabbcc');
      expect(start.resendAfter, 60);
    });

    test('مسیر بومی WinHTTP و پشتیبان خودکار به پروکسی سیستم هنگام خطای شبکه مستقیم', () async {
      if (!Platform.isWindows) {
        return;
      }
      final List<bool> proxyAttempts = <bool>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
        if (call.method == 'httpRequest') {
          final Map<Object?, Object?> args =
              call.arguments as Map<Object?, Object?>;
          final bool useProxy = args['useProxy'] == true;
          proxyAttempts.add(useProxy);
          if (!useProxy) {
            return <String, Object>{
              'ok': false,
              'statusCode': 0,
              'winError': 12175,
              'contentType': '',
              'bodyBytes': Uint8List(0),
              'error': 'send_request (12175: tls_failure)',
            };
          }
          return <String, Object>{
            'ok': true,
            'statusCode': 200,
            'winError': 0,
            'contentType': 'application/json; charset=utf-8',
            'bodyBytes': Uint8List.fromList(
              utf8.encode(
                jsonEncode(<String, dynamic>{
                  'ok': true,
                  'stage': 'needs_profile',
                  'account_exists': false,
                }),
              ),
            ),
            'error': '',
          };
        }
        return null;
      });

      final GatewayClient client = GatewayClient(
        baseUrl: 'http://127.0.0.1:1/index.php?AppApi=',
        enableNativeTransport: true,
      );
      addTearDown(client.close);

      final SignInStart start = await client.start(
        phone: '09121112233',
        deviceId: 'win64-fallback',
        deviceName: 'WIN11-USER',
        platform: 'Windows 11 x64',
      );
      expect(start.stage, SignInStage.needsProfile);
      expect(proxyAttempts, <bool>[false, true]);
    });

    test('پذیرش نام های فارسی کاربر جدید با حروف عربی یا نیم فاصله صفحه کلید', () {
      expect(IranPhone.validName('امیر\u200cحسین'), isTrue);
      expect(IranPhone.normalizeName('امیر\u200cحسین'), 'امیر حسین');
      expect(IranPhone.validName('عليرضا كريمي'), isTrue);
      expect(IranPhone.normalizeName('عليرضا كريمي'), 'علیرضا کریمی');
      expect(IranPhone.validName('فاطمة'), isTrue);
      expect(IranPhone.normalizeName('فاطمة'), 'فاطمه');
      expect(IranPhone.validName('Ali'), isFalse);
      expect(IranPhone.validName('علی۱۲'), isFalse);
      expect(IranPhone.isValid('۰۹۹۸۱۲۳۴۵۶۷'), isTrue);
      expect(IranPhone.isValid('+۹۸ ۹۹۶ ۱۲۳ ۴۵۶۷'), isTrue);
    });

    test('لایه بومی WinHTTP و بسته بندی ۶۴ بیتی کامل است', () {
      final String winhttp =
          File('packages/umbrella_native/windows/winhttp_client.cpp')
              .readAsStringSync();
      final String cmake =
          File('packages/umbrella_native/windows/CMakeLists.txt')
              .readAsStringSync();
      final String plugin =
          File('packages/umbrella_native/windows/umbrella_native_plugin.cpp')
              .readAsStringSync();
      final String iss = File('installer/umbrella.iss').readAsStringSync();

      expect(cmake, contains('winhttp_client.cpp'));
      expect(cmake, contains('winhttp'));
      expect(winhttp, contains('WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2'));
      expect(winhttp, contains('WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_3'));
      expect(winhttp, contains('WINHTTP_OPTION_IPV6_FAST_FALLBACK'));
      expect(winhttp, contains('WinHttpGetIEProxyConfigForCurrentUser'));
      expect(plugin, contains('"httpRequest"'));
      expect(plugin, contains('RunOffUiThread'));
      expect(iss, contains('ArchitecturesAllowed=x64compatible'));
      expect(iss, contains('MinVersion=10.0'));
    });
  });

  group('بسته شدن آنی و بدون مکث برنامه همراه با پاک سازی کامل', () {
    test('وقتی پردازشی باز نیست taskkill اضافی اجرا نمی شود', () async {
      int killCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
        if (call.method == 'killByName') {
          killCalls++;
          return 0;
        }
        if (call.method == 'killPid') {
          killCalls++;
          return false;
        }
        return null;
      });

      final NativeBridge native = NativeBridge();
      final Stopwatch watch = Stopwatch()..start();
      expect(await native.killByName('UmbrellaCli.exe'), 0);
      expect(await native.killPid(999999), isFalse);
      watch.stop();

      expect(killCalls, 2);
      expect(watch.elapsedMilliseconds, lessThan(200));
    });

    test('زنجیره خروج ابتدا پنجره را پنهان می کند و پاک سازی بومی غیرمسدودکننده دارد', () {
      final String services =
          File('lib/platform/services.dart').readAsStringSync();
      final String vpn =
          File('lib/vpn/vpn_controller.dart').readAsStringSync();
      final String ops =
          File('packages/umbrella_native/windows/system_ops.cpp')
              .readAsStringSync();
      final String plugin =
          File('packages/umbrella_native/windows/umbrella_native_plugin.cpp')
              .readAsStringSync();

      final int quitStart = services.indexOf('Future<void> quit()');
      final String quitBody = services.substring(
        quitStart,
        services.indexOf('Future<void> startDragging()', quitStart),
      );
      expect(
        quitBody.indexOf('windowManager.hide()'),
        lessThan(quitBody.indexOf('cleanup()')),
      );
      expect(vpn, contains('_shutdownInFlight ??= _performShutdownForExit()'));
      expect(ops, contains('KillOwnedCoreTreeSinglePass'));
      expect(ops, contains('SendNotifyMessageW'));
      expect(ops, contains('ResetWinHttpProxyFast'));
      expect(ops, isNot(contains('netsh winhttp reset proxy')));
      expect(plugin, contains('ShutdownOwnedCores(/*skip_if_clean=*/true)'));
    });
  });
}
