import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbrella_vpn/core/malicious_link_guard.dart';
import 'package:umbrella_vpn/core/storage.dart';
import 'package:umbrella_vpn/core/theme.dart';
import 'package:umbrella_vpn/data/gateway_client.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/platform/services.dart';
import 'package:umbrella_vpn/state/auth_controller.dart';
import 'package:umbrella_vpn/state/security_controller.dart';
import 'package:umbrella_vpn/state/settings_controller.dart';
import 'package:umbrella_vpn/state/toast_controller.dart';
import 'package:umbrella_vpn/ui/widgets/advanced_network_settings.dart';
import 'package:umbrella_vpn/ui/widgets/content_control.dart';
import 'package:umbrella_vpn/ui/widgets/quick_connection_panel.dart';
import 'package:umbrella_vpn/ui/widgets/security_shield_dialog.dart';
import 'package:umbrella_vpn/ui/widgets/telegram_channel_dialog.dart';
import 'package:umbrella_vpn/vpn/clash_api.dart';
import 'package:umbrella_vpn/vpn/content_block_server.dart';
import 'package:umbrella_vpn/vpn/cores.dart';
import 'package:umbrella_vpn/vpn/runtime_config.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

class _FakeNative implements NativeBridge {
  SecurityScanResult scanResult = const SecurityScanResult();
  List<InstalledAppInfo> apps = const <InstalledAppInfo>[];
  final List<String> remediatedKeys = <String>[];

  @override
  bool get available => true;

  @override
  Future<bool> isElevated() async => true;

  @override
  Future<List<InstalledAppInfo>> getInstalledApps() async => apps;

  @override
  Future<SecurityScanResult> scanDeviceSecurity() async => scanResult;

  @override
  Future<RemediationResult> remediateSecurityThreat(
    SecurityThreat threat,
  ) async {
    remediatedKeys.add(threat.key);
    scanResult = const SecurityScanResult(
      clean: true,
      scannedApps: 34,
      scannedFiles: 6,
    );
    return const RemediationResult(
      ok: true,
      actionTaken: true,
      stillPresent: false,
      message: 'تهدید با موفقیت متوقف و حذف شد.',
    );
  }

  @override
  Future<bool> requestStorageScanAccess() async => true;

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
  Future<bool> openExternalUrl(
    String url, {
    String title = '',
    String body = '',
  }) async =>
      true;

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSound implements SoundService {
  @override
  bool enabled = false;

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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVpn extends ChangeNotifier implements VpnController {
  VpnStatus current = VpnStatus.disconnected;
  int disconnectCalls = 0;
  int reloadCalls = 0;

  @override
  VpnStatus get status => current;

  @override
  Future<void> disconnect({bool silent = false}) async {
    disconnectCalls++;
    current = VpnStatus.disconnected;
    notifyListeners();
  }

  @override
  void scheduleLiveReload() {
    reloadCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SignedAuth extends AuthController {
  _SignedAuth({
    required super.native,
    required super.gateway,
    required super.store,
  });

  @override
  bool get signedIn => true;

  @override
  String get deviceId => 'dev-and-sec-1';

  @override
  SessionData? get session => const SessionData(
        token: 'tok-and-sec-1',
        uuid: '22222222-2222-4222-8222-222222222222',
        deviceId: 'dev-and-sec-1',
        account: Account.empty,
        filter: FilterSettings.empty,
      );

  @override
  FilterSettings get filter => FilterSettings.empty;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.instance.init();
  });

  setUp(() async {
    await LocalStore.instance.remove(StoreKeys.telegramChannelPromptAt);
    await LocalStore.instance.remove(StoreKeys.appAnnouncementState);
  });

  group('اعلان پویای داخل برنامه در اندروید', () {
    test('زمان بندی، انتشار مجدد و شروع آینده طبق تنظیمات ربات کار می کنند', () async {
      final DateTime now = DateTime.utc(2026, 11, 22, 12, 0, 0);

      final AppAnnouncement disabled = AppAnnouncement.fromJson(<String, dynamic>{
        ...AppAnnouncement.fallback().toJson(),
        'enabled': false,
      });
      expect(
        await TelegramChannelPrompt.isAnnouncementDue(disabled, now: now),
        isFalse,
      );

      final AppAnnouncement scheduled = AppAnnouncement.fromJson(<String, dynamic>{
        'enabled': true,
        'version': 2,
        'title': 'آپدیت اندروید',
        'body': 'نسخه جدید منتشر شد',
        'button_text': 'دریافت',
        'button_url': 'https://armin-soft.ir/android',
        'interval_hours': 24,
        'starts_at': now.add(const Duration(hours: 3)).millisecondsSinceEpoch ~/ 1000,
      });
      expect(
        await TelegramChannelPrompt.isAnnouncementDue(scheduled, now: now),
        isFalse,
      );

      final AppAnnouncement once = AppAnnouncement.fromJson(<String, dynamic>{
        'enabled': true,
        'version': 3,
        'title': 'اطلاعیه یک بار',
        'body': 'متن اطلاعیه',
        'button_text': 'مشاهده',
        'button_url': 'https://t.me/UmbrellaSupport',
        'interval_hours': 0,
      });
      expect(
        await TelegramChannelPrompt.isAnnouncementDue(once, now: now),
        isTrue,
      );
      await TelegramChannelPrompt.markShown(
        at: now,
        announcementVersion: once.version,
      );
      expect(
        await TelegramChannelPrompt.isAnnouncementDue(
          once,
          now: now.add(const Duration(days: 10)),
        ),
        isFalse,
      );

      final AppAnnouncement republished = AppAnnouncement.fromJson(<String, dynamic>{
        'enabled': true,
        'version': 4,
        'title': 'نسخه تازه',
        'body': 'بروزرسانی جدید',
        'button_text': 'باز کردن',
        'button_url': 'https://armin-soft.ir',
        'interval_hours': 48,
      });
      expect(
        await TelegramChannelPrompt.isAnnouncementDue(republished, now: now),
        isTrue,
      );
    });

    testWidgets('TelegramChannelDialog در عرض ۳۶۰ گوشی بدون سرریز اعلان پویا را نشان می دهد', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final AppAnnouncement custom = AppAnnouncement.fromJson(<String, dynamic>{
        'enabled': true,
        'version': 5,
        'title': 'پیشنهاد ویژه کاربران آمبرلا',
        'body': 'بسته های پرسرعت ویژه موبایل در دسترس قرار گرفت.',
        'button_text': 'مشاهده جزئیات',
        'button_url': 'https://armin-soft.ir/offers',
        'interval_hours': 24,
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Center(
                child: TelegramChannelDialog(
                  announcement: custom,
                  animate: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('پیشنهاد ویژه کاربران آمبرلا'), findsOneWidget);
      expect(find.text('مشاهده جزئیات'), findsOneWidget);
      expect(find.text('armin-soft.ir'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('سپر امنیتی همیشه فعال اندروید و ارتباط با ربات', () {
    test('شناسایی JumpJump و Psiphon، گزارش به سرور و پاکسازی کامل', () async {
      final List<(String, Map<String, dynamic>)> sent =
          <(String, Map<String, dynamic>)>[];
      final MockClient mockHttp = MockClient((http.Request req) async {
        final String route = req.url.queryParameters['AppApi'] ?? req.url.path;
        sent.add((route, jsonDecode(req.body) as Map<String, dynamic>));
        return http.Response.bytes(
          utf8.encode(jsonEncode(<String, dynamic>{'ok': true, 'notified': 2})),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });

      final _FakeNative native = _FakeNative()
        ..scanResult = const SecurityScanResult(
          clean: false,
          scannedApps: 45,
          scannedFiles: 8,
          threats: <SecurityThreat>[
            SecurityThreat(
              key: 'malware:jumpjump',
              name: 'JumpJump VPN (بدافزار / ابزار مخرب)',
              category: 'malware',
              severity: 'critical',
              target: 'io.jumpjump.vpn (JumpJump)',
              detail: 'برنامه مخرب JumpJump روی دستگاه نصب است.',
              packageName: 'io.jumpjump.vpn',
              remediationKind: 'uninstall',
              active: true,
            ),
            SecurityThreat(
              key: 'vpn:psiphon',
              name: 'Psiphon (فیلترشکن ناسازگار)',
              category: 'conflicting_vpn',
              severity: 'high',
              target: 'com.psiphon3 (Psiphon)',
              detail: 'اپلیکیشن Psiphon روی دستگاه شناسایی شد.',
              packageName: 'com.psiphon3',
              remediationKind: 'uninstall',
              active: true,
            ),
          ],
        );

      final GatewayClient gw = GatewayClient(
        client: mockHttp,
        enableNativeTransport: false,
      );
      final _SignedAuth auth = _SignedAuth(
        native: native,
        gateway: gw,
        store: LocalStore.instance,
      );
      final _FakeVpn vpn = _FakeVpn()..current = VpnStatus.connected;
      int blocked = 0;

      final SecurityScannerController sec = SecurityScannerController(
        native: native,
        auth: auth,
        isVpnActive: () => vpn.status.active,
      )..onThreatBlockedWhileConnected = (_) {
          blocked++;
          vpn.disconnect();
        };

      final SecurityScanResult before = await sec.ensureCleanBeforeConnect();
      expect(before.hasThreats, isTrue);
      expect(sec.threats, hasLength(2));
      expect(blocked, 1);
      expect(vpn.disconnectCalls, 1);
      expect(sent.any((e) => e.$1.contains('app/security-alert')), isTrue);

      final SecurityScanResult after = await sec.remediateAll();
      expect(after.clean, isTrue);
      expect(native.remediatedKeys, <String>['malware:jumpjump', 'vpn:psiphon']);
      expect(sent.last.$2['sync_all'], isTrue);
      expect((sent.last.$2['resolved_keys'] as List<dynamic>), hasLength(2));

      sec.dispose();
      auth.dispose();
      gw.close();
      vpn.dispose();
    });

    testWidgets('SecurityStatusBadge و SecurityShieldDialog در عرض ۳۶۰ موبایل بدون سرریز رندر می شوند', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final _FakeNative native = _FakeNative()
        ..scanResult = const SecurityScanResult(
          clean: false,
          scannedApps: 32,
          threats: <SecurityThreat>[
            SecurityThreat(
              key: 'vpn:psiphon',
              name: 'Psiphon (فیلترشکن ناسازگار)',
              category: 'conflicting_vpn',
              severity: 'high',
              target: 'com.psiphon3 (Psiphon)',
              detail: 'فیلترشکن ناسازگار روی گوشی نصب است.',
              packageName: 'com.psiphon3',
              remediationKind: 'uninstall',
              active: true,
            ),
          ],
        );
      final SecurityScannerController sec = SecurityScannerController(native: native);
      final ToastController toasts = ToastController();
      await sec.scanNow();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SecurityScannerController>.value(value: sec),
            ChangeNotifierProvider<ToastController>.value(value: toasts),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: Center(child: SecurityStatusBadge(dense: true)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey<String>('security-status-badge')));
      await tester.pumpAndSettle();

      expect(find.text('سپر امنیتی همیشه فعال آمبرلا'), findsOneWidget);
      expect(find.text('Psiphon (فیلترشکن ناسازگار)'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey<String>('security-remediate-all-button')));
      await tester.pumpAndSettle();

      expect(find.text('هیچ بدافزار یا وی پی ان ناسازگاری یافت نشد'), findsOneWidget);
      expect(sec.isClean, isTrue);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
      sec.dispose();
      toasts.dispose();
    });
  });

  group('قراردادها، جابجایی کنترل محتوا و انتخاب گر برنامه در اندروید', () {
    test('Manifest مجوز REQUEST_DELETE_PACKAGES دارد و لایه Kotlin و UI قراردادها را رعایت می کنند', () {
      final String manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, contains('android.permission.REQUEST_DELETE_PACKAGES'));
      expect(manifest, contains('android.permission.QUERY_ALL_PACKAGES'));

      final String scannerKt = File(
        'android/app/src/main/kotlin/ir/umbrella/vpn/UmbrellaSecurityScanner.kt',
      ).readAsStringSync();
      expect(scannerKt, contains('ACTION_DELETE'));
      expect(scannerKt, contains('ACTION_VPN_SETTINGS'));
      expect(scannerKt, contains('jumpjump'));
      expect(scannerKt, contains('psiphon'));

      final String methodHandler = File(
        'android/app/src/main/kotlin/ir/umbrella/vpn/MethodHandler.kt',
      ).readAsStringSync();
      expect(methodHandler, contains('"scanDeviceSecurity"'));
      expect(methodHandler, contains('"remediateSecurityThreat"'));

      final String settingsSrc = File(
        'lib/ui/pages/settings_page.dart',
      ).readAsStringSync();
      expect(settingsSrc, isNot(contains('ContentControlCard')));
      expect(settingsSrc, contains('SecurityStatusBadge'));

      final String quickSrc = File(
        'lib/ui/widgets/quick_connection_panel.dart',
      ).readAsStringSync();
      expect(quickSrc, contains('ContentControlCard'));

      final String connectSrc = File(
        'lib/ui/pages/connect_page.dart',
      ).readAsStringSync();
      expect(connectSrc, contains('SecurityStatusBadge'));
      expect(connectSrc, contains('needsSecurityCleanup'));
      expect(connectSrc, contains('SecurityShieldDialog.show'));
    });

    testWidgets('QuickConnectionPanel با وجود AuthController کارت کنترل محتوا را بدون سرریز نمایش می دهد', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final _FakeNative native = _FakeNative();
      final GatewayClient gw = GatewayClient(
        enableNativeTransport: false,
        client: MockClient((http.Request _) async => http.Response.bytes(
              utf8.encode(jsonEncode(<String, dynamic>{'ok': true})),
              200,
              headers: const <String, String>{'content-type': 'application/json'},
            )),
      );
      final _SignedAuth auth = _SignedAuth(
        native: native,
        gateway: gw,
        store: LocalStore.instance,
      );
      final SettingsController settings = SettingsController(
        native: native,
        sound: _FakeSound(),
        window: _FakeWindow(),
      );
      final _FakeVpn vpn = _FakeVpn();
      final ToastController toasts = ToastController();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthController>.value(value: auth),
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

      expect(find.byType(ContentControlCard), findsOneWidget);
      expect(find.text('کنترل محتوا'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      gw.close();
      settings.dispose();
      vpn.dispose();
      toasts.dispose();
    });

    testWidgets('AppRouteDialog در اندروید لیست برنامه های نصب شده را با جستجو انتخاب می کند', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final _FakeNative native = _FakeNative()
        ..apps = const <InstalledAppInfo>[
          InstalledAppInfo(
            packageName: 'org.telegram.messenger',
            name: 'Telegram',
          ),
          InstalledAppInfo(
            packageName: 'com.instagram.android',
            name: 'Instagram',
          ),
          InstalledAppInfo(
            packageName: 'com.android.settings',
            name: 'Settings',
            isSystem: true,
          ),
        ];

      AppRouteRule? saved;
      await tester.pumpWidget(
        Provider<NativeBridge>.value(
          value: native,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: Builder(
                  builder: (BuildContext context) => Center(
                    child: FilledButton(
                      onPressed: () async {
                        saved = await showDialog<AppRouteRule>(
                          context: context,
                          builder: (_) => const AppRouteDialog(),
                        );
                      },
                      child: const Text('باز کردن'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('باز کردن'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('app-route-pick-installed')));
      await tester.pumpAndSettle();

      expect(find.text('Telegram'), findsOneWidget);
      expect(find.text('Instagram'), findsOneWidget);
      // برنامه های سیستمی به طور پیش فرض پنهان اند
      expect(find.text('Settings'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey<String>('installed-apps-search')),
        'insta',
      );
      await tester.pumpAndSettle();
      expect(find.text('Instagram'), findsOneWidget);
      expect(find.text('Telegram'), findsNothing);

      await tester.tap(find.text('Instagram'));
      await tester.pumpAndSettle();

      expect(find.text('com.instagram.android'), findsOneWidget);

      await tester.tap(find.text('ذخیره قانون'));
      await tester.pumpAndSettle();
      expect(saved?.process, 'com.instagram.android');
    });
  });

  group('شناسایی Hiddify و لوگوی سپر امنیتی آمبرلا در اندروید', () {
    test('اسکنر کاتلین Hiddify را شناسایی می کند اما پکیج های آمبرلا را استثنا می کند', () {
      final String kt = File(
        'android/app/src/main/kotlin/ir/umbrella/vpn/UmbrellaSecurityScanner.kt',
      ).readAsStringSync();
      expect(kt.contains('vpn:hiddify'), isTrue);
      expect(kt.contains('hiddify'), isTrue);
      expect(kt.contains('ir.umbrella.'), isTrue);

      expect(BrandAssets.all.contains(BrandAssets.securityShield), isTrue);
      expect(BrandAssets.all.contains(BrandAssets.securityAlert), isTrue);

      final String connectSrc = File('lib/ui/pages/connect_page.dart').readAsStringSync();
      expect(connectSrc.contains('SecurityShieldLogo'), isTrue);
    });

    test('تشخیص Hiddify پیش از اتصال اتصال را مسدود و حذف را ثبت می کند', () async {
      final _FakeNative native = _FakeNative()
        ..scanResult = const SecurityScanResult(
          clean: false,
          scannedApps: 35,
          threats: <SecurityThreat>[
            SecurityThreat(
              key: 'vpn:hiddify',
              name: 'Hiddify (فیلترشکن ناسازگار)',
              category: 'conflicting_vpn',
              severity: 'high',
              target: 'app.hiddify.com (Hiddify)',
              detail: 'اپلیکیشن Hiddify روی دستگاه نصب است.',
              packageName: 'app.hiddify.com',
              remediationKind: 'uninstall',
              active: true,
            ),
          ],
        );

      final SecurityScannerController sec = SecurityScannerController(native: native);
      final SecurityScanResult before = await sec.ensureCleanBeforeConnect();
      expect(before.hasThreats, isTrue);
      expect(sec.threats.single.key, 'vpn:hiddify');

      final SecurityScanResult after = await sec.remediateAll();
      expect(after.clean, isTrue);
      expect(native.remediatedKeys, <String>['vpn:hiddify']);
      sec.dispose();
    });

    testWidgets('لوگوهای سپر امنیتی آمبرلا دیکد می شوند و در SecurityShieldLogo استفاده می شوند', (WidgetTester tester) async {
      await tester.runAsync(() async {
        for (final String asset in <String>[
          BrandAssets.securityShield,
          BrandAssets.securityAlert,
        ]) {
          final ByteData bytes = await rootBundle.load(asset);
          expect(bytes.lengthInBytes, greaterThan(1024), reason: asset);
          final ui.Codec codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
          final ui.FrameInfo frame = await codec.getNextFrame();
          expect(frame.image.width, greaterThanOrEqualTo(256), reason: asset);
          expect(frame.image.height, greaterThanOrEqualTo(256), reason: asset);
          frame.image.dispose();
          codec.dispose();
        }
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: Column(
              children: <Widget>[
                SecurityShieldLogo(danger: false, size: AppMetrics.logoLg),
                SecurityShieldLogo(danger: true, size: AppMetrics.iconBoxLg),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final List<Image> images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images, hasLength(2));
      expect((images[0].image as AssetImage).assetName, BrandAssets.securityShield);
      expect((images[1].image as AssetImage).assetName, BrandAssets.securityAlert);
      expect(images[0].gaplessPlayback, isTrue);
      expect(images[1].gaplessPlayback, isTrue);
    });
  });

  group('پایش دانلود و تصاویر آلوده، لینک تروجانی و اعلان تلگرام در اندروید', () {
    test('اسکنر کاتلین و مانیفست مجوزها و قواعد تصویر Polyglot را رعایت می کنند', () {
      final String kt = File(
        'android/app/src/main/kotlin/ir/umbrella/vpn/UmbrellaSecurityScanner.kt',
      ).readAsStringSync();
      expect(kt.contains('malicious_download'), isTrue);
      expect(kt.contains('inspectDownloadedFile'), isTrue);
      expect(kt.contains('hasPeHeaderAt'), isTrue);
      expect(kt.contains('hasRloOrDoubleExtension'), isTrue);
      expect(kt.contains('hasStorageScanAccess'), isTrue);
      expect(kt.contains('requestStorageScanAccess'), isTrue);

      final String manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest.contains('READ_MEDIA_IMAGES'), isTrue);
      expect(manifest.contains('MANAGE_EXTERNAL_STORAGE'), isTrue);
      expect(manifest.contains('REQUEST_INSTALL_PACKAGES'), isFalse);
      expect(manifest.contains('READ_SMS'), isFalse);
      expect(manifest.contains('RECEIVE_SMS'), isFalse);
    });

    test('MaliciousLinkGuard لینک های تروجانی، هموگراف و پسوند دوگانه را مسدود می کند', () {
      expect(
        MaliciousLinkGuard.inspectUrl('https://grabify.link/track123'),
        isNotNull,
      );
      expect(
        MaliciousLinkGuard.inspectUrl('https://xn--telegram-9va.com/login'),
        isNotNull,
      );
      expect(
        MaliciousLinkGuard.inspectUrl('https://cdn.evil.test/photo.jpg.apk'),
        isNotNull,
      );
      expect(
        MaliciousLinkGuard.inspectUrl('javascript:alert(1)'),
        isNotNull,
      );
      expect(
        MaliciousLinkGuard.inspectUrl('https://armin-soft.ir/app'),
        isNull,
      );
      expect(
        MaliciousLinkGuard.inspectUrl('https://telegram.org'),
        isNull,
      );
    });

    test('تصویر یا فایل دانلودی آلوده خودکار حذف شده و به تلگرام گزارش می شود', () async {
      final List<(String, Map<String, dynamic>)> sent =
          <(String, Map<String, dynamic>)>[];
      final MockClient mockHttp = MockClient((http.Request req) async {
        final String route = req.url.queryParameters['AppApi'] ?? req.url.path;
        sent.add((route, jsonDecode(req.body) as Map<String, dynamic>));
        return http.Response.bytes(
          utf8.encode(jsonEncode(<String, dynamic>{'ok': true, 'notified': 1})),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });

      final _FakeNative native = _FakeNative()
        ..scanResult = const SecurityScanResult(
          clean: false,
          scannedApps: 28,
          scannedFiles: 14,
          storageAccessGranted: true,
          threats: <SecurityThreat>[
            SecurityThreat(
              key: 'file:polyglot:img1',
              name: 'تصویر آلوده به بدافزار (Polyglot)',
              category: 'malicious_download',
              severity: 'critical',
              target: '/storage/emulated/0/Download/photo_payload.jpg',
              detail: 'درون تصویر دانلودشده کد اجرایی مخرب شناسایی شد.',
              path: '/storage/emulated/0/Download/photo_payload.jpg',
              remediationKind: 'file',
              active: true,
            ),
          ],
        );

      final GatewayClient gw = GatewayClient(
        client: mockHttp,
        enableNativeTransport: false,
      );
      final _SignedAuth auth = _SignedAuth(
        native: native,
        gateway: gw,
        store: LocalStore.instance,
      );
      final List<NeutralizedSecurityEvent> notified = <NeutralizedSecurityEvent>[];

      final SecurityScannerController sec = SecurityScannerController(
        native: native,
        auth: auth,
      )..onThreatNeutralized = notified.add;

      final SecurityScanResult res = await sec.scanNow(silent: false);
      expect(res.clean, isTrue);
      expect(native.remediatedKeys, <String>['file:polyglot:img1']);
      expect(sec.neutralizedEvents, hasLength(1));
      expect(notified, hasLength(1));
      expect(notified.single.action, 'deleted');

      final List<(String, Map<String, dynamic>)> alerts = sent
          .where((e) => e.$1.contains('app/security-alert'))
          .toList();
      expect(alerts, isNotEmpty);
      final List<dynamic>? neutralizedBody =
          alerts.last.$2['neutralized'] as List<dynamic>?;
      expect(neutralizedBody, hasLength(1));

      sec.dispose();
      auth.dispose();
      gw.close();
    });

    test('ترافیک زنده با لینک تروجانی بلافاصله بسته شده و گزارش تلگرام می فرستد', () async {
      final List<(String, Map<String, dynamic>)> sent =
          <(String, Map<String, dynamic>)>[];
      final MockClient mockHttp = MockClient((http.Request req) async {
        final String route = req.url.queryParameters['AppApi'] ?? req.url.path;
        sent.add((route, jsonDecode(req.body) as Map<String, dynamic>));
        return http.Response.bytes(
          utf8.encode(jsonEncode(<String, dynamic>{'ok': true, 'notified': 1})),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });

      final _FakeNative native = _FakeNative();
      final GatewayClient gw = GatewayClient(
        client: mockHttp,
        enableNativeTransport: false,
      );
      final _SignedAuth auth = _SignedAuth(
        native: native,
        gateway: gw,
        store: LocalStore.instance,
      );
      final List<String> closedIds = <String>[];
      final SecurityScannerController sec = SecurityScannerController(
        native: native,
        auth: auth,
      );

      await sec.inspectLiveConnections(
        const <CoreActivitySample>[
          CoreActivitySample(
            id: 'conn-42',
            host: 'grabify.link',
            process: 'com.example.browser',
          ),
          CoreActivitySample(
            id: 'conn-ok',
            host: 'armin-soft.ir',
            process: 'ir.umbrella.vpn',
          ),
        ],
        closeConnection: (String id) async {
          closedIds.add(id);
          return true;
        },
      );

      expect(closedIds, <String>['conn-42']);
      expect(sec.neutralizedEvents, hasLength(1));
      expect(sec.neutralizedEvents.single.action, 'blocked_connection');
      expect(sent.any((e) => e.$1.contains('app/security-alert')), isTrue);

      sec.dispose();
      auth.dispose();
      gw.close();
    });

    testWidgets(
      'SecurityShieldDialog بدون بررسی دستی لینک و در عرض ۳۶۰ موبایل بدون سرریز رندر می شود',
      (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final _FakeNative native = _FakeNative()
        ..scanResult = const SecurityScanResult(
          clean: true,
          scannedApps: 12,
          scannedFiles: 9,
          storageAccessGranted: false,
        );
      final SecurityScannerController sec = SecurityScannerController(
        native: native,
      );
      await sec.scanNow(silent: true);

      await tester.pumpWidget(
        ChangeNotifierProvider<SecurityScannerController>.value(
          value: sec,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SecurityShieldDialog(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey<String>('security-storage-access-button')), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('security-link-input')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('security-check-link-button')),
        findsNothing,
      );
      expect(find.text('بررسی امنیتی لینک پیش از باز کردن'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('security-auto-link-protection-card')),
        findsOneWidget,
      );

      final MaliciousLinkMatch? hit = await sec.handleObservedMaliciousHost(
        'grabify.link',
        process: 'com.android.chrome',
      );
      expect(hit, isNotNull);
      await tester.pump();

      expect(sec.neutralizedEvents, hasLength(1));
      expect(sec.neutralizedEvents.single.action, 'blocked_connection');
      expect(find.textContaining('مسدودسازی اتصال'), findsOneWidget);
      expect(tester.takeException(), isNull);
      sec.dispose();
    });

    test(
      'ContentBlockServer renders Umbrella UI page and ClashApi parses Android DNS/route blocks',
      () async {
        final List<InterceptedBlockEvent> events = <InterceptedBlockEvent>[];
        final ContentBlockServer server = ContentBlockServer(
          filterProvider: () => const FilterSettings(
            enabled: true,
            categories: <String>['adult', 'gambling', 'ads'],
            customDomains: <String>['blocked.example.test'],
          ),
          onIntercepted: events.add,
        );
        await server.start();
        addTearDown(() async => server.stop());

        final Uri uiUri = server.buildBlockedPageUri('pornhub.com');
        final Socket s =
            await Socket.connect(InternetAddress.loopbackIPv4, uiUri.port);
        s.write(
          'GET ${uiUri.path}?${uiUri.query} HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n',
        );
        await s.flush();
        final List<int> bytes = await s.fold<List<int>>(
          <int>[],
          (List<int> acc, List<int> chunk) => acc..addAll(chunk),
        );
        final String raw = latin1.decode(bytes);
        final int split = raw.indexOf('\r\n\r\n');
        final String head = split >= 0 ? raw.substring(0, split) : raw;
        final String uiHtml = split >= 0
            ? utf8.decode(bytes.sublist(split + 4), allowMalformed: true)
            : '';
        expect(head, contains(' 200 OK'));
        expect(uiHtml, contains('dir="rtl"'));
        expect(uiHtml, contains('فیلترشکن آمبرلا'));
        expect(uiHtml, isNot(contains('Umbrella VPN')));
        expect(uiHtml, contains('@font-face'));
        expect(uiHtml, contains('Vazirmatn-Regular.ttf'));
        expect(uiHtml, contains('#E11D2E'));
        expect(uiHtml, contains('سپر کنترل محتوای آمبرلا فعال است'));
        expect(uiHtml, contains('pornhub.com'));

        final String timedHtml = ContentBlockServer.renderBlockedPageHtml(
          details: const BlockedHostDetails(
            domain: 'pornhub.com',
            category: 'adult',
            categoryLabel: 'محتوای بزرگسالان و غیراخلاقی',
            reason: 'تست',
            isSecurityThreat: false,
          ),
          assetBaseUrl: 'http://127.0.0.1:${server.uiPort}',
          timestamp: DateTime(2026, 1, 1, 16, 59, 19),
        );
        expect(timedHtml, contains('۱۶:۵۹:۱۹'));
        expect(timedHtml, isNot(contains('16:59:19')));

        final Socket fontSock =
            await Socket.connect(InternetAddress.loopbackIPv4, server.uiPort);
        fontSock.write(
          'GET /assets/fonts/Vazirmatn-Regular.ttf HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n',
        );
        await fontSock.flush();
        final List<int> fontReply = await fontSock.fold<List<int>>(
          <int>[],
          (List<int> acc, List<int> chunk) => acc..addAll(chunk),
        );
        final String fontHead = latin1.decode(fontReply.take(200).toList());
        expect(fontHead, contains(' 200 OK'));
        expect(fontReply.length, greaterThan(50000));

        final Socket httpsTunnel =
            await Socket.connect(InternetAddress.loopbackIPv4, server.proxyPort);
        httpsTunnel.write(
          'CONNECT 1xbet.com:443 HTTP/1.1\r\nHost: 1xbet.com:443\r\n\r\n',
        );
        await httpsTunnel.flush();
        final String httpsResp = utf8.decode(
          await httpsTunnel.fold<List<int>>(
            <int>[],
            (List<int> acc, List<int> chunk) => acc..addAll(chunk),
          ),
        );
        expect(httpsResp, startsWith('HTTP/1.1 403 Forbidden'));
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(
          events.any((InterceptedBlockEvent e) =>
              e.details.domain == '1xbet.com' &&
              e.details.category == 'gambling' &&
              e.needsBrowserLaunch),
          isTrue,
        );

        final CoreLogEntry? dns = ClashApi.parseCoreLogLine(
          jsonEncode(<String, String>{
            'type': 'debug',
            'payload': '[12 0ms] dns: rejected A xvideos.com.',
          }),
        );
        expect(dns, isNotNull);
        expect(dns!.isDnsRejection, isTrue);
        expect(dns.isBlockedEvent, isTrue);
        expect(dns.host, 'xvideos.com');
      },
    );

    test(
      'VpnController.openBlockedPreviewPage launches local Umbrella browser block URL on Android',
      () async {
        final _FakeNative native = _FakeNative();
        final VpnController vpn = VpnController(
          native: native,
          ipService: IpService(),
          sound: _FakeSound(),
          tray: TrayService(native),
          provisioner: CoreProvisioner(),
          settings: const AppSettings(),
        );
        vpn.updateContentFilter(
          const FilterSettings(
            enabled: true,
            categories: <String>['gambling'],
          ),
        );
        Uri? launchedUri;
        vpn.onLaunchBlockedPage = (
          Uri uri, {
          required String title,
          required String body,
        }) async {
          launchedUri = uri;
          return true;
        };

        final bool ok = await vpn.openBlockedPreviewPage();
        expect(ok, isTrue);
        expect(launchedUri, isNotNull);
        expect(launchedUri!.host, '127.0.0.1');
        expect(launchedUri!.path, '/blocked');
        expect(vpn.contentBlockUiPort, greaterThan(0));

        // درخواست favicon نباید HTML صفحه مسدودی را دوباره رندر کند و font-display باید block باشد.
        Future<({int statusCode, String head, String body})> rawLoopbackGet(
          Uri uri,
        ) async {
          final Socket sock =
              await Socket.connect(InternetAddress.loopbackIPv4, uri.port);
          final String pq = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
          sock.write('GET $pq HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n');
          await sock.flush();
          final List<int> bytes = await sock.fold<List<int>>(
            <int>[],
            (List<int> acc, List<int> chunk) => acc..addAll(chunk),
          );
          final String raw = latin1.decode(bytes);
          final int split = raw.indexOf('\r\n\r\n');
          final String head = split >= 0 ? raw.substring(0, split) : raw;
          final int code = int.tryParse(
                RegExp(r'HTTP/1\.[01]\s+(\d+)').firstMatch(head)?.group(1) ??
                    '',
              ) ??
              0;
          final List<int> bodyBytes =
              split >= 0 ? bytes.sublist(split + 4) : const <int>[];
          return (
            statusCode: code,
            head: head.toLowerCase(),
            body: utf8.decode(bodyBytes, allowMalformed: true),
          );
        }

        final ({int statusCode, String head, String body}) favRes =
            await rawLoopbackGet(
          Uri.parse('http://127.0.0.1:${vpn.contentBlockUiPort}/favicon.ico'),
        );
        expect(favRes.statusCode, 200);
        expect(favRes.head, isNot(contains('text/html')));
        final ({int statusCode, String head, String body}) pageRes =
            await rawLoopbackGet(launchedUri!);
        expect(pageRes.statusCode, 200);
        expect(pageRes.body, contains('font-display: block;'));

        vpn.dispose();
        await Future<void>.delayed(Duration.zero);
      },
    );

    test(
      'VpnController فقط یک بار صفحه مسدودی را برای زیردامنه ها و لاگ های تکراری باز می کند',
      () async {
        final _FakeNative native = _FakeNative();
        final VpnController vpn = VpnController(
          native: native,
          ipService: IpService(),
          sound: _FakeSound(),
          tray: TrayService(native),
          provisioner: CoreProvisioner(),
          settings: const AppSettings(),
        );
        vpn.updateContentFilter(
          const FilterSettings(
            enabled: true,
            categories: <String>['adult', 'gambling'],
          ),
        );
        final List<Uri> launches = <Uri>[];
        final Completer<void> launchedOnce = Completer<void>();
        vpn.onLaunchBlockedPage = (
          Uri uri, {
          required String title,
          required String body,
        }) async {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          launches.add(uri);
          if (!launchedOnce.isCompleted) {
            launchedOnce.complete();
          }
          return true;
        };

        vpn.debugHandleInterceptedBlock(
          const InterceptedBlockEvent(
            details: BlockedHostDetails(
              domain: 'www.pornhub.com',
              category: 'adult',
              categoryLabel: 'محتوای غیراخلاقی و بزرگسالان',
              reason: 'مسدودسازی محتوا',
              isSecurityThreat: false,
            ),
            needsBrowserLaunch: true,
            port: 443,
            source: 'https_connect',
          ),
        );
        vpn.debugHandleInterceptedBlock(
          const InterceptedBlockEvent(
            details: BlockedHostDetails(
              domain: 'cdn.pornhub.com',
              category: 'adult',
              categoryLabel: 'محتوای غیراخلاقی و بزرگسالان',
              reason: 'مسدودسازی محتوا',
              isSecurityThreat: false,
            ),
            needsBrowserLaunch: true,
            port: 443,
            source: 'https_connect',
          ),
        );
        vpn.debugHandleInterceptedBlock(
          const InterceptedBlockEvent(
            details: BlockedHostDetails(
              domain: '1xbet.com',
              category: 'gambling',
              categoryLabel: 'شرط بندی و قمار',
              reason: 'مسدودسازی محتوا',
              isSecurityThreat: false,
            ),
            needsBrowserLaunch: true,
            port: 443,
            source: 'https_connect',
          ),
        );
        vpn.debugProcessCoreLogLine(
          jsonEncode(<String, String>{
            'type': 'info',
            'payload': '[7741 0ms] inbound/tun[tun-in]: connection to pornhub.com:443',
          }),
        );
        vpn.debugProcessCoreLogLine(
          jsonEncode(<String, String>{
            'type': 'info',
            'payload': '[7741 1ms] router: match[1] rule[umbrella-filter-adult] -> reject',
          }),
        );
        vpn.debugProcessCoreLogLine(
          jsonEncode(<String, String>{
            'type': 'debug',
            'payload': '[99 0ms] dns: rejected A pornhub.com.',
          }),
        );

        await launchedOnce.future.timeout(const Duration(seconds: 5));
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(launches, hasLength(1));
        expect(launches.single.queryParameters['domain'], 'www.pornhub.com');

        final List<Uri> direct403Launches = <Uri>[];
        final VpnController vpnHttp = VpnController(
          native: native,
          ipService: IpService(),
          sound: _FakeSound(),
          tray: TrayService(native),
          provisioner: CoreProvisioner(),
          settings: const AppSettings(),
        );
        vpnHttp.updateContentFilter(
          const FilterSettings(
            enabled: true,
            categories: <String>['adult'],
          ),
        );
        vpnHttp.onLaunchBlockedPage = (
          Uri uri, {
          required String title,
          required String body,
        }) async {
          direct403Launches.add(uri);
          return true;
        };
        vpnHttp.debugHandleInterceptedBlock(
          const InterceptedBlockEvent(
            details: BlockedHostDetails(
              domain: 'xvideos.com',
              category: 'adult',
              categoryLabel: 'محتوای غیراخلاقی و بزرگسالان',
              reason: 'مسدودسازی محتوا',
              isSecurityThreat: false,
            ),
            needsBrowserLaunch: false,
            port: 80,
            source: 'http_direct_403',
          ),
        );
        vpnHttp.debugProcessCoreLogLine(
          jsonEncode(<String, String>{
            'type': 'debug',
            'payload': '[55 0ms] dns: rejected A www.xvideos.com.',
          }),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(direct403Launches, isEmpty);

        vpnHttp.dispose();
        vpn.dispose();
        await Future<void>.delayed(Duration.zero);
      },
    );

    test(
      'RuntimeConfig.finalize routes primary content control & trojan links to umbrella-block-page',
      () {
        final Map<String, dynamic> runtime = <String, dynamic>{
          'outbounds': <dynamic>[
            <String, dynamic>{'type': 'direct', 'tag': RuntimeConfig.directOutboundTag},
            <String, dynamic>{'type': 'selector', 'tag': 'select'},
          ],
          'experimental': <String, dynamic>{
            'monitoring': <String, dynamic>{},
            'clash_api': <String, dynamic>{'external_controller': '127.0.0.1:16756'},
          },
          'dns': <String, dynamic>{
            'rules': <dynamic>[
              <String, dynamic>{
                'domain_suffix': <String>['pornhub.com'],
                'action': 'reject',
              },
              <String, dynamic>{
                'rule_set': <String>['geosite-category-ads-all'],
                'action': 'reject',
              },
            ],
          },
          'route': <String, dynamic>{
            'rules': <dynamic>[
              <String, dynamic>{'action': 'sniff'},
              <String, dynamic>{
                'domain_suffix': <String>['pornhub.com'],
                'rule_set': <String>['geosite-category-porn'],
                'action': 'reject',
              },
              <String, dynamic>{
                'domain_suffix': <String>['blocked-custom.example'],
                'action': 'reject',
              },
              <String, dynamic>{
                'domain_suffix': <String>['doubleclick.net'],
                'rule_set': <String>['geosite-category-ads-all'],
                'action': 'reject',
              },
              <String, dynamic>{
                'package_name': <String>['com.example.blocked'],
                'action': 'reject',
              },
            ],
          },
        };

        RuntimeConfig.finalize(
          runtime,
          profileTags: const <String>{},
          coreSettings: const <String, dynamic>{
            'bypass-lan': true,
            'resolve-destination': true,
          },
          blockPagePort: 45123,
        );

        final List<dynamic> outbounds = runtime['outbounds'] as List<dynamic>;
        expect(
          outbounds.any((dynamic o) =>
              o is Map &&
              o['tag'] == RuntimeConfig.blockPageOutboundTag &&
              o['type'] == 'http' &&
              o['server_port'] == 45123),
          isTrue,
        );

        final List<Map<String, dynamic>> routeRules =
            ((runtime['route'] as Map<String, dynamic>)['rules'] as List<dynamic>)
                .cast<Map<String, dynamic>>();
        final Map<String, dynamic> pornRule = routeRules.firstWhere(
          (Map<String, dynamic> r) =>
              '${r['domain_suffix']}'.contains('pornhub.com'),
        );
        expect(pornRule['action'], 'route');
        expect(pornRule['outbound'], RuntimeConfig.blockPageOutboundTag);

        final Map<String, dynamic> customRule = routeRules.firstWhere(
          (Map<String, dynamic> r) =>
              '${r['domain_suffix']}'.contains('blocked-custom.example'),
        );
        expect(customRule['outbound'], RuntimeConfig.blockPageOutboundTag);

        final Map<String, dynamic> adsRule = routeRules.firstWhere(
          (Map<String, dynamic> r) =>
              '${r['domain_suffix']}'.contains('doubleclick.net'),
        );
        expect(adsRule['action'], 'reject');

        final Map<String, dynamic> appRule = routeRules.firstWhere(
          (Map<String, dynamic> r) =>
              '${r['package_name']}'.contains('com.example.blocked'),
        );
        expect(appRule['action'], 'reject');

        final int trojanIdx = routeRules.indexWhere(
          (Map<String, dynamic> r) =>
              r['outbound'] == RuntimeConfig.blockPageOutboundTag &&
              '${r['domain_suffix']}'.contains('grabify.link'),
        );
        final int resolveIdx = routeRules.indexWhere(
          (Map<String, dynamic> r) => r['action'] == 'resolve',
        );
        expect(trojanIdx, greaterThan(0));
        expect(resolveIdx, greaterThan(trojanIdx));

        final List<dynamic> dnsRules =
            (runtime['dns'] as Map<String, dynamic>)['rules'] as List<dynamic>;
        expect(dnsRules.any((dynamic r) => '$r'.contains('pornhub.com')), isFalse);
        expect(
          dnsRules.any((dynamic r) => '$r'.contains('geosite-category-ads-all')),
          isTrue,
        );
      },
    );
  });
}
