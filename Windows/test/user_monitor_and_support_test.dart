import 'dart:convert';

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
import 'package:umbrella_vpn/state/toast_controller.dart';
import 'package:umbrella_vpn/ui/pages/logs_page.dart';
import 'package:umbrella_vpn/vpn/clash_api.dart';
import 'package:umbrella_vpn/vpn/runtime_config.dart';

class _TestNative implements NativeBridge {
  @override
  Future<DeviceProfile> deviceInfo() async => const DeviceProfile(
        hostname: 'Ali-Laptop',
        os: 'Windows 11',
        osEdition: 'Pro',
        osDisplayVersion: '24H2',
        cpu: 'Intel Core i7',
        cpuCores: 8,
        ramTotalMb: 16384,
        ramUsedMb: 6144,
        diskTotalMb: 512000,
        diskFreeMb: 128000,
        localIp: '192.168.1.25',
        adapterName: 'Wi-Fi',
        elevated: true,
        machineId: 'win-test-machine-1',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.instance.init();
  });

  setUp(() {
    AppLogger.instance.clear();
    ActivityMonitorBuffer.instance.clear();
  });

  tearDown(() {
    AppLogger.instance.clear();
    ActivityMonitorBuffer.instance.clear();
  });

  test('ClashApi.parseConnections و ActivityMonitorBuffer سایت و برنامه و صفحه را تجمیع می کنند', () {
    final List<CoreActivitySample> samples = ClashApi.parseConnections(<String, dynamic>{
      'connections': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'conn-1',
          'download': 2048,
          'upload': 512,
          'metadata': <String, dynamic>{
            'host': 'YouTube.com',
            'processPath': r'C:\Program Files\Google\Chrome\Application\chrome.exe',
          },
        },
        <String, dynamic>{
          'id': 'conn-2',
          'download': 1024,
          'upload': 256,
          'metadata': <String, dynamic>{
            'sniffHost': '127.0.0.1',
            'processPath': r'C:\Umbrella\sing-box.exe',
          },
        },
        <String, dynamic>{
          'id': 'conn-3',
          'download': 4096,
          'upload': 1024,
          'metadata': <String, dynamic>{
            'host': 'github.com',
            'process': 'Telegram.exe',
          },
        },
      ],
    });

    expect(samples.length, 2);
    expect(samples[0].host, 'youtube.com');
    expect(samples[0].process, 'chrome.exe');
    expect(samples[1].host, 'github.com');
    expect(samples[1].process, 'Telegram.exe');

    final ActivityMonitorBuffer buf = ActivityMonitorBuffer();
    buf.recordScreen('اتصال');
    buf.recordConnections(samples);
    // Repeated poll of same connection only adds byte delta without inflating hits.
    buf.recordConnections(<CoreActivitySample>[
      const CoreActivitySample(
        id: 'conn-1',
        host: 'youtube.com',
        process: 'chrome.exe',
        downBytes: 3048,
        upBytes: 712,
      ),
    ]);

    final List<Map<String, dynamic>> payload = buf.snapshotPayload();
    final Map<String, dynamic> yt = payload.firstWhere(
      (Map<String, dynamic> e) => e['category'] == 'site' && e['target'] == 'youtube.com',
    );
    expect(yt['hits'], 1);
    expect(yt['down'], 3048);
    expect(yt['up'], 712);
    expect(
      payload.any((Map<String, dynamic> e) => e['category'] == 'screen' && e['target'] == 'اتصال'),
      isTrue,
    );

    buf.confirmSent(payload);
    expect(buf.snapshotPayload(), isEmpty);
  });

  test('RuntimeConfig.finalize زمانی که clash_api فعال است find_process را روشن می کند', () {
    final Map<String, dynamic> config = <String, dynamic>{
      'route': <String, dynamic>{
        'find_process': false,
        'rules': <Map<String, dynamic>>[
          <String, dynamic>{'action': 'sniff'},
        ],
      },
      'outbounds': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'direct', 'tag': 'direct §hide§'},
      ],
      'experimental': <String, dynamic>{
        'monitoring': <String, dynamic>{},
        'clash_api': <String, dynamic>{'external_controller': '127.0.0.1:16756'},
      },
    };
    RuntimeConfig.finalize(config, profileTags: const <String>{});
    expect((config['route'] as Map<String, dynamic>)['find_process'], isTrue);
  });

  test('GatewayClient.heartbeat و sendSupportReport داده های رصد و پشتیبانی را دقیق می فرستند', () async {
    final List<(String, Map<String, dynamic>)> requests = <(String, Map<String, dynamic>)>[];
    final MockClient mockHttp = MockClient((http.Request req) async {
      final String route = req.url.queryParameters['AppApi'] ?? req.url.path;
      final Map<String, dynamic> decoded =
          jsonDecode(req.body) as Map<String, dynamic>;
      requests.add((route, decoded));
      if (route.endsWith('app/support-report')) {
        return http.Response.bytes(
          utf8.encode(jsonEncode(<String, dynamic>{
            'ok': true,
            'sent': true,
            'message': 'گزارش برای پشتیبانی ارسال شد',
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
          'seen_at': '2026-11-22T00:00:00Z',
          'activity_stored': 2,
        })),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });
    final GatewayClient gateway = GatewayClient(client: mockHttp);
    addTearDown(gateway.close);

    await gateway.heartbeat(
      token: 'tok-123',
      deviceId: 'dev-win-1',
      deviceName: 'Ali-PC',
      platform: 'Windows',
      appVersion: '1.0.5',
      currentScreen: 'گزارش ها',
      activity: <Map<String, dynamic>>[
        <String, dynamic>{'category': 'site', 'target': 'github.com', 'hits': 2, 'down': 1024, 'up': 256},
      ],
    );
    expect(requests.last.$1, contains('auth/device'));
    expect(requests.last.$2['current_screen'], 'گزارش ها');
    expect((requests.last.$2['activity'] as List<dynamic>).length, 1);

    final String msg = await gateway.sendSupportReport(
      deviceId: 'dev-win-1',
      note: 'اتصال قطع شد',
      platform: 'Windows',
      appVersion: '1.0.5',
      device: <String, dynamic>{'device_name': 'Ali-PC'},
      vpnState: <String, dynamic>{'status': 'قطع'},
      errors: <Map<String, dynamic>>[
        <String, dynamic>{'level': 'error', 'message': 'timeout'},
      ],
      recentLogs: 'log line 1',
    );
    expect(msg, contains('پشتیبانی'));
    expect(requests.last.$1, contains('app/support-report'));
    expect(requests.last.$2['note'], 'اتصال قطع شد');
    expect((requests.last.$2['errors'] as List<dynamic>).length, 1);
  });

  test('LogsPage.buildSupportPayload خطاها، مشخصات دستگاه و پنهان سازی لینک ها را می سازد', () {
    AppLogger.instance.add('رویداد عادی');
    AppLogger.instance.add(
      'خطای اتصال به سرور vless://secret@example.com:443?type=ws',
      level: 'error',
    );
    final payload = LogsPage.buildSupportPayload(
      profile: const DeviceProfile(
        hostname: 'Studio-PC',
        os: 'Windows 11',
        cpuCores: 12,
        ramTotalMb: 32768,
        localIp: '192.168.1.10',
      ),
    );
    expect(payload.device['device_name'], 'Studio-PC');
    expect(payload.errors.length, 1);
    expect(payload.errors.first['level'], 'error');
    expect('${payload.errors.first['message']}', isNot(contains('vless://')));
    expect(payload.recentLogs, isNot(contains('vless://')));
  });

  testWidgets('دکمه ارسال به پشتیبانی در LogsPage دیالوگ را باز کرده و با یادداشت خالی هم فوری ارسال می کند',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 820));
    addTearDown(() async => await tester.binding.setSurfaceSize(null));

    Map<String, dynamic>? capturedSupport;
    final MockClient mockHttp = MockClient((http.Request req) async {
      final String route = req.url.queryParameters['AppApi'] ?? req.url.path;
      if (route.endsWith('app/support-report')) {
        capturedSupport = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response.bytes(
          utf8.encode(jsonEncode(<String, dynamic>{
            'ok': true,
            'sent': true,
            'message': 'تحویل داده شد',
          })),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }
      return http.Response.bytes(
        utf8.encode(jsonEncode(<String, dynamic>{'ok': true})),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });

    final GatewayClient gateway = GatewayClient(client: mockHttp);
    final _TestNative native = _TestNative();
    final AuthController auth = AuthController(
      native: native,
      gateway: gateway,
      store: LocalStore.instance,
    );
    final ToastController toasts = ToastController();
    addTearDown(AppLogger.instance.clear);

    AppLogger.instance.add('نمونه خطای تست پشتیبانی', level: 'error');

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

    final Finder sendChip =
        find.byKey(const ValueKey<String>('logs-send-support-button'));
    expect(sendChip, findsOneWidget);
    await tester.ensureVisible(sendChip);
    await tester.tap(sendChip);
    await tester.pumpAndSettle();

    final Finder confirmBtn =
        find.byKey(const ValueKey<String>('support-report-confirm-button'));
    expect(confirmBtn, findsOneWidget);
    await tester.ensureVisible(confirmBtn);
    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();

    expect(capturedSupport, isNotNull);
    expect((capturedSupport!['device'] as Map<String, dynamic>)['device_name'], 'Ali-Laptop');
    expect((capturedSupport!['errors'] as List<dynamic>).length, 1);
    expect(toasts.items.isNotEmpty, isTrue);

    toasts.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
    auth.dispose();
    gateway.close();
    toasts.dispose();
  });
}
