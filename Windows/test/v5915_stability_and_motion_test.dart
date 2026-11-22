import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:umbrella_vpn/core/app_config.dart';
import 'package:umbrella_vpn/core/storage.dart';
import 'package:umbrella_vpn/core/theme.dart';
import 'package:umbrella_vpn/data/download_problem.dart';
import 'package:umbrella_vpn/data/parsers.dart';
import 'package:umbrella_vpn/platform/app_crash_store.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/platform/services.dart';
import 'package:umbrella_vpn/state/motion_controller.dart';
import 'package:umbrella_vpn/state/power_controller.dart';
import 'package:umbrella_vpn/state/settings_controller.dart';
import 'package:umbrella_vpn/state/toast_controller.dart';
import 'package:umbrella_vpn/ui/pages/logs_page.dart';
import 'package:umbrella_vpn/ui/widgets/common.dart';
import 'package:umbrella_vpn/vpn/core_fetch.dart';
import 'package:umbrella_vpn/vpn/umbrella_core.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';
import 'package:umbrella_vpn/vpn/windows_crash.dart';

class _MockWindow implements WindowService {
  @override
  bool closeToTray = true;
  @override
  bool notificationsEnabled = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockSound implements SoundService {
  @override
  bool enabled = false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubNative extends NativeBridge {
  _StubNative({this.cpuSamples = const <int?>[]});

  final List<int?> cpuSamples;
  int _idx = 0;

  @override
  Future<bool> isElevated() async => false;

  @override
  Future<bool> setAutostart(bool enabled, {String appName = 'UmbrellaVPN'}) async =>
      true;

  @override
  Future<int?> processCpuTimeMicros() async {
    if (_idx >= cpuSamples.length) return null;
    return cpuSamples[_idx++];
  }
}

class _FakeVpn extends ChangeNotifier implements VpnController {
  int reloads = 0;
  @override
  void scheduleLiveReload() => reloads++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.instance.init();
  });

  group('AppCrashStore — ذخیره امن و پاک سازی گزارش خطای نشست قبلی', () {
    test('پاک سازی نسخه های قدیمی، خطاهای بیش از ۲۴ ساعت و حفظ حداکثر ۱۰ گزارش با سانسور', () async {
      final Directory tmp = await Directory.systemTemp.createTemp('umbrella_crash_');
      try {
        final Directory crashDir =
            Directory('${tmp.path}${Platform.pathSeparator}app_crashes');
        await crashDir.create(recursive: true);

        // فایل نسخه قدیمی باید پاک شود
        final File oldVersion = File('${crashDir.path}${Platform.pathSeparator}old-dart.txt');
        await oldVersion.writeAsString(
          'Umbrella-Version: 0.9.0\nError: old',
        );

        // فایل قدیمی تر از ۲۴ ساعت باید پاک شود
        final File expired = File('${crashDir.path}${Platform.pathSeparator}expired-dart.txt');
        await expired.writeAsString(
          'Umbrella-Version: ${AppConfig.version}\nError: expired',
        );
        await expired.setLastModified(
          DateTime.now().subtract(const Duration(hours: 25)),
        );

        // ۱۲ گزارش جدید؛ حداکثر ۱۰ تا باقی بمانند
        for (int i = 0; i < 12; i++) {
          final File f = File('${crashDir.path}${Platform.pathSeparator}r$i-dart.txt');
          await f.writeAsString(
            'Umbrella-Version: ${AppConfig.version}\nError: item $i',
          );
          await f.setLastModified(
            DateTime.now().subtract(Duration(minutes: 20 - i)),
          );
        }

        final List<String> kept = await AppCrashStore.openAndPrune(tmp);
        expect(kept, hasLength(AppCrashStore.maxReportsOnDisk));
        expect(oldVersion.existsSync(), isFalse);
        expect(expired.existsSync(), isFalse);

        // ثبت خطا با اطلاعات محرمانه باید سانسور شود
        AppCrashStore.record(
          error: 'failed https://panel.example.com/abc123/sub/ and 11111111-2222-3333-4444-555555555555',
          stack: StackTrace.current,
          source: 'flutter',
        );
        final List<String> afterRecord = await AppCrashStore.openAndPrune(tmp);
        final String joined = afterRecord.join('\n');
        expect(joined, isNot(contains('panel.example.com')));
        expect(joined, isNot(contains('11111111-2222-3333-4444-555555555555')));

        AppLogger.instance.clear();
        AppLogger.instance.attachPreviousCrashes(afterRecord);
        expect(AppLogger.instance.exportText(), contains('گزارش خطای نشست قبلی'));
      } finally {
        AppLogger.instance.clear();
        if (tmp.existsSync()) {
          await tmp.delete(recursive: true);
        }
      }
    });
  });

  group('WindowsCrash و کدهای خروج ویندوز', () {
    test('کدهای جدید NTSTATUS بدون حرف لاتین، رقم لاتین و نیم فاصله برگردانده می شوند', () {
      for (final int code in <int>[
        0x40010004,
        -1073741670, // 0xC000009A
        -1073741676, // 0xC0000094
        -529697949, // 0xE06D7363
      ]) {
        final String msg = UmbrellaCore.describeWindowsExitCode(code);
        expect(msg, isNotEmpty);
        expect(msg, isNot(contains(RegExp(r'[A-Za-z0-9\u200C]'))));
      }
      expect(UmbrellaCore.describeWindowsExitCode(0), isEmpty);
    });

    test('خطای رویداد شماره ۱۰۰۰ ویندوز و خط سقوط Go با سانسور استخراج می شوند', () {
      const String sampleXml = '''
<Events>
  <Event>
    <EventData>
      <Data>UmbrellaCoreEngine.exe</Data>
      <Data>1.0.0</Data>
      <Data>00000000</Data>
      <Data>libcronet.dll</Data>
      <Data>1.0.0</Data>
      <Data>00000000</Data>
      <Data>c0000005</Data>
      <Data>00012340</Data>
      <Data>0x1a34</Data>
    </EventData>
  </Event>
</Events>''';
      final String crashText = WindowsCrash.applicationErrorFor(sampleXml, 0x1a34);
      expect(crashText, contains('دسترسی حافظه'));
      expect(crashText, contains('کتابخانه کرونت'));
      expect(WindowsCrash.applicationErrorFor(sampleXml, 9999), isEmpty);

      final String headline = WindowsCrash.goCrashHeadline(
        'info line\npanic: dial vless://11111111-2222-3333-4444-555555555555@srv.example.com:443 failed\nstack',
      );
      expect(headline, startsWith('panic:'));
      expect(headline, isNot(contains('srv.example.com')));
      expect(headline, isNot(contains('11111111-2222-3333-4444-555555555555')));
    });
  });

  group('MotionController، وضعیت باتری بحرانی و StatusOrb', () {
    test('باتری کمتر از ۵٪ بحرانی تشخیص داده می شود و مصرف بالای پردازنده پویانمایی را متوقف می کند', () async {
      const BatteryPowerState critical = BatteryPowerState(
        hasBattery: true,
        onBattery: true,
        energySaver: false,
        isLaptop: false,
        powerKnown: true,
        batteryPercent: 3,
      );
      expect(critical.isCriticallyLowBattery, isTrue);

      const BatteryPowerState criticalZero = BatteryPowerState(
        hasBattery: true,
        onBattery: true,
        energySaver: false,
        powerKnown: true,
        batteryPercent: 0,
      );
      expect(criticalZero.isCriticallyLowBattery, isTrue);

      const BatteryPowerState healthy = BatteryPowerState(
        hasBattery: true,
        onBattery: true,
        energySaver: false,
        powerKnown: true,
        batteryPercent: 40,
      );
      expect(healthy.isCriticallyLowBattery, isFalse);

      final PowerController power = PowerController(
        readStatus: () async => critical,
        enabled: false,
      );
      await power.refresh();
      expect(power.active, isFalse);
      expect(power.criticallyLow, isTrue);
      expect(power.lowOrSaving, isTrue);
      power.dispose();

      // شبیه سازی مصرف > ۱۰٪ پردازنده در پنجره کوتاه
      final _StubNative highCpuNative = _StubNative(
        cpuSamples: <int?>[1000000, 1200000],
      );
      final MotionController motion = MotionController(
        native: highCpuNative,
        processorCount: 2,
        ambientDuration: const Duration(milliseconds: 60),
        cpuSampleDelay: const Duration(milliseconds: 20),
      );
      expect(motion.shouldAnimateAmbient, isTrue);
      motion.setAppVisible(false);
      expect(motion.shouldAnimateAmbient, isFalse);
      motion.setAppVisible(true);
      expect(motion.shouldAnimateAmbient, isTrue);

      await motion.checkConnectCpuBudget();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(motion.cpuThrottled, isTrue);
      expect(motion.shouldAnimateAmbient, isFalse);
      motion.dispose();
    });

    testWidgets('StatusOrb تیکر تصویر خود را همیشه فعال نگه می دارد و با disableAnimations کار می کند',
        (WidgetTester tester) async {
      final MotionController motion = MotionController();
      motion.setPowerSaving(true);
      await tester.pumpWidget(
        ChangeNotifierProvider<MotionController>.value(
          value: motion,
          child: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const Scaffold(
                body: Center(
                  child: StatusOrb(
                    image: BrandAssets.connected,
                    color: Color(0xFF22C55E),
                    size: 200,
                    active: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final Image img = tester.widget<Image>(find.byType(Image).first);
      expect(img.gaplessPlayback, isTrue);
      motion.dispose();
    });
  });

  group('SettingsController — جلسه ۱۰ دقیقه ای عیب یابی و صفحه گزارش ها', () {
    test('مدت جلسه عیب یابی در انبار ذخیره و پس از انقضا در load به warn بازمی گردد', () async {
      await LocalStore.instance.writeJson(
        StoreKeys.settings,
        <String, dynamic>{'logLevel': 'debug'},
      );
      await LocalStore.instance.write(
        StoreKeys.debugLogUntil,
        DateTime.now()
            .subtract(const Duration(minutes: 1))
            .toUtc()
            .toIso8601String(),
      );

      final SettingsController expiredCtrl = SettingsController(
        native: _StubNative(),
        sound: _MockSound(),
        window: _MockWindow(),
      );
      await expiredCtrl.load();
      expect(expiredCtrl.settings.logLevel, 'warn');
      expect(expiredCtrl.diagnosticActive, isFalse);
      expiredCtrl.dispose();

      // شروع جلسه تازه، ماندگاری تا load بعدی، و سپس توقف
      final SettingsController activeCtrl = SettingsController(
        native: _StubNative(),
        sound: _MockSound(),
        window: _MockWindow(),
      );
      await activeCtrl.startDiagnosticSession();
      expect(activeCtrl.settings.logLevel, 'debug');
      expect(activeCtrl.diagnosticActive, isTrue);
      expect(activeCtrl.diagnosticRemaining.inMinutes, greaterThanOrEqualTo(9));

      final SettingsController reloadedCtrl = SettingsController(
        native: _StubNative(),
        sound: _MockSound(),
        window: _MockWindow(),
      );
      await reloadedCtrl.load();
      expect(reloadedCtrl.settings.logLevel, 'debug');
      expect(reloadedCtrl.diagnosticActive, isTrue);

      await reloadedCtrl.stopDiagnosticSession();
      expect(reloadedCtrl.settings.logLevel, 'warn');
      expect(reloadedCtrl.diagnosticActive, isFalse);
      activeCtrl.dispose();
      reloadedCtrl.dispose();
    });

    testWidgets('دکمه عیب یابی ۱۰ دقیقه ای در LogsPage کار می کند و خطای لایه ای ندارد',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final SettingsController settings = SettingsController(
        native: _StubNative(),
        sound: _MockSound(),
        window: _MockWindow(),
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
              child: Scaffold(body: LogsPage()),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('logs-diagnostic-session-chip')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('logs-diagnostic-session-chip')));
      await tester.pump();
      expect(settings.diagnosticActive, isTrue);
      expect(vpn.reloads, 1);

      await settings.stopDiagnosticSession();
      settings.dispose();
      vpn.dispose();
    });
  });

  group('SubscriptionHeaders، خطاهای دریافت و CoreFetchClient', () {
    test('خواندن عنوان Base64 بدون padding، RFC 5987 و اطلاعات مصرف مقاوم', () {
      final SubscriptionMetadata meta = SubscriptionHeaders.parse(
        <String, String>{
          'profile-title': 'base64:2KLYqNix2YTYpw', // «آمبرلا» بدون '='
          'subscription-userinfo':
              'upload=1024;; download=2048.4; total=0; expire=1900000000',
        },
      );
      expect(meta.title, 'آمبرلا');
      expect(meta.uploadBytes, 1024);
      expect(meta.downloadBytes, 2048);
      expect(meta.totalBytes, isNull);
      expect(meta.expireAt, isNotNull);

      final SubscriptionMetadata fromRfc5987 = SubscriptionHeaders.parse(
        <String, String>{
          'content-disposition':
              "attachment; filename*=UTF-8''%D8%A7%D8%B4%D8%AA%D8%B1%D8%A7%DA%A9%20%D9%85%D9%86.yaml",
        },
        '#subscription-userinfo: upload=500; download=700; total=5000000',
      );
      expect(fromRfc5987.title, 'اشتراک من.yaml');
      expect(fromRfc5987.uploadBytes, 500);
      expect(fromRfc5987.totalBytes, 5000000);
    });

    test('تشخیص OpenVPN پیام فارسی روشن می دهد و خطاهای دانلود فارسی بدون نشانی هستند', () {
      final ParseReport ovpn = SubscriptionParser.parseAuto(
        'client\ndev tun\nproto udp\nremote vpn.example.com 1194\n<ca>\n...\n</ca>',
        'test-ovpn',
      );
      expect(ovpn.nodes, isEmpty);
      expect(ovpn.problems.first, contains('اوپن وی پی ان'));

      final DownloadProblem reset = DownloadProblem.fromCoreError(4);
      final DownloadProblem cert = DownloadProblem.fromStatusOrSignal(winError: 12038);
      final DownloadProblem rate = DownloadProblem.fromStatusOrSignal(statusCode: 429);
      expect(reset.type, DownloadProblemType.reset);
      expect(cert.type, DownloadProblemType.certificate);
      expect(rate.type, DownloadProblemType.tooManyRequests);
      expect(reset.messageFa, isNot(contains('http')));
    });

    test('CoreFetchClient پیام Protobuf را درست کدگذاری و رمزگشایی و تماس h2c را تمام می کند', () async {
      final Uint8List req = CoreFetchClient.encodeRequest(
        url: 'https://panel.example.com/sub/',
        userAgent: 'Umbrella-Windows/1.0.0',
        timeoutMs: 12000,
      );
      expect(req, isNotEmpty);

      // ساخت دستی FetchUrlResponse با Protobuf
      final BytesBuilder respProto = BytesBuilder();
      // field 1 (status_code=200)
      respProto.add(<int>[0x08, 0xC8, 0x01]);
      // field 3 (body='ok-sub')
      final List<int> bodyBytes = utf8.encode('ok-sub');
      respProto.add(<int>[0x1A, bodyBytes.length, ...bodyBytes]);
      final Uint8List protoPayload = respProto.takeBytes();

      final CoreFetchResult decoded = CoreFetchClient.decodeResponse(protoPayload);
      expect(decoded.statusCode, 200);
      expect(utf8.decode(decoded.bodyBytes), 'ok-sub');
      expect(decoded.hasHttpResponse, isTrue);

      // تست کامل h2c سوکت روی لوپ بک
      final ServerSocket server =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((Socket client) {
        final BytesBuilder incoming = BytesBuilder();
        bool sent = false;
        client.listen((Uint8List data) {
          incoming.add(data);
          final Uint8List buf = incoming.toBytes();
          if (!sent && buf.length > 24 && utf8.decode(buf.sublist(0, 3)) == 'PRI') {
            sent = true;
            // Server empty SETTINGS
            client.add(<int>[0, 0, 0, 0x04, 0x00, 0, 0, 0, 0]);
            // HEADERS (:status 200 indexed = 0x88) with END_HEADERS (0x04)
            client.add(<int>[0, 0, 1, 0x01, 0x04, 0, 0, 0, 1, 0x88]);
            // gRPC 5-byte frame + payload in DATA frame (stream 1)
            final Uint8List grpc = Uint8List(5 + protoPayload.length);
            grpc[0] = 0;
            grpc[4] = protoPayload.length;
            grpc.setRange(5, grpc.length, protoPayload);
            final int len = grpc.length;
            client.add(<int>[
              (len >> 16) & 0xFF,
              (len >> 8) & 0xFF,
              len & 0xFF,
              0x00,
              0x00,
              0,
              0,
              0,
              1,
              ...grpc,
            ]);
            // Trailing HEADERS frame with END_STREAM | END_HEADERS (0x05)
            client.add(<int>[0, 0, 1, 0x01, 0x05, 0, 0, 0, 1, 0x88]);
          }
        });
      });

      final CoreFetchResult? live = await CoreFetchClient.callGrpcFetchUrl(
        host: '127.0.0.1',
        port: server.port,
        uri: Uri.parse('https://example.invalid/sub/'),
      );
      expect(live, isNotNull);
      expect(live!.statusCode, 200);
      expect(utf8.decode(live.bodyBytes), 'ok-sub');
    });
  });
}
