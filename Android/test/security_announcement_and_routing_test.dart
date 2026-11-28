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
import 'package:umbrella_vpn/core/persian.dart';
import 'package:umbrella_vpn/core/safe_url_launcher.dart';
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
import 'package:umbrella_vpn/vpn/https_ad_filter_proxy.dart';
import 'package:umbrella_vpn/vpn/runtime_config.dart';
import 'package:umbrella_vpn/vpn/umbrella_core.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

class _FakeNative implements NativeBridge {
  SecurityScanResult scanResult = const SecurityScanResult();
  List<InstalledAppInfo> apps = const <InstalledAppInfo>[];
  final List<String> remediatedKeys = <String>[];
  int closeConflictingCalls = 0;
  int closedOnNextCall = 0;

  @override
  bool get available => true;

  @override
  Future<int> closeConflictingVpns() async {
    closeConflictingCalls++;
    return closedOnNextCall;
  }

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
  Future<bool> startSecurityFileWatcher() async => true;

  @override
  Future<bool> stopSecurityFileWatcher() async => true;

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

  final List<({String title, String body, String actionUrl, Uint8List? imageBytes})>
      promoBalloons =
      <({String title, String body, String actionUrl, Uint8List? imageBytes})>[];

  @override
  Future<void> showTrayBalloon({
    required String title,
    required String body,
    bool warning = false,
  }) async {}

  @override
  Future<bool> showPromoBalloon({
    required String title,
    required String body,
    String actionUrl = '',
    Uint8List? imageBytes,
  }) async {
    promoBalloons.add((
      title: title,
      body: body,
      actionUrl: actionUrl,
      imageBytes: imageBytes,
    ));
    return true;
  }

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
  bool get httpsCaTrusted => false;

  @override
  bool get httpsCaStatusChecked => true;

  @override
  String get httpsCaCertPath => '';

  @override
  HttpsFilterStats get httpsFilterStats => const HttpsFilterStats();

  @override
  bool get isHttpsFilterProxyActive => false;

  @override
  Future<bool> refreshHttpsCaStatus({bool notify = true}) async => false;

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
    await LocalStore.instance.remove(StoreKeys.promoAnnouncementState);
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
    test('Manifest از الگوی رعایت سپر امنیتی گوگل پلی تبعیت می کند و لایه Kotlin و UI قراردادها را رعایت می کنند', () {
      final String manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, isNot(contains('android.permission.REQUEST_DELETE_PACKAGES')));
      expect(manifest, isNot(contains('android.permission.KILL_BACKGROUND_PROCESSES')));
      expect(manifest, isNot(contains('android.permission.READ_SMS')));
      expect(manifest, isNot(contains('android.permission.RECEIVE_SMS')));
      expect(manifest, isNot(contains('android.permission.BIND_ACCESSIBILITY_SERVICE')));
      expect(manifest, isNot(contains('android.permission.BIND_NOTIFICATION_LISTENER_SERVICE')));
      expect(manifest, contains('android.permission.READ_MEDIA_IMAGES'));
      expect(manifest, contains('android.permission.READ_MEDIA_VIDEO'));
      expect(manifest, contains('android.permission.READ_MEDIA_AUDIO'));
      expect(manifest, contains('android.permission.MANAGE_EXTERNAL_STORAGE'));
      expect(manifest, contains('android.permission.READ_EXTERNAL_STORAGE'));
      expect(manifest, contains('android.permission.WRITE_EXTERNAL_STORAGE'));
      expect(manifest, contains('android:maxSdkVersion="29"'));
      expect(manifest, contains('android:requestLegacyExternalStorage="true"'));
      expect(manifest, contains('android.permission.QUERY_ALL_PACKAGES'));

      final String scannerKt = File(
        'android/app/src/main/kotlin/ir/umbrella/vpn/UmbrellaSecurityScanner.kt',
      ).readAsStringSync();
      expect(scannerKt, contains('ACTION_APPLICATION_DETAILS_SETTINGS'));
      expect(scannerKt, contains('ACTION_VPN_SETTINGS'));
      expect(scannerKt, contains('ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION'));
      expect(scannerKt, contains('ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION'));
      expect(scannerKt, contains('isExternalStorageManager'));
      expect(scannerKt, contains('ACTION_OPEN_DOCUMENT_TREE'));
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
      expect(kt.contains('inspectSafDocument'), isTrue);
      expect(kt.contains('hasPeHeaderAt'), isTrue);
      expect(kt.contains('hasRloOrDoubleExtension'), isTrue);
      expect(kt.contains('hasStorageScanAccess'), isTrue);
      expect(kt.contains('requestStorageScanAccess'), isTrue);
      expect(kt.contains('DocumentsContract'), isTrue);

      final String manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest.contains('READ_MEDIA_IMAGES'), isTrue);
      expect(manifest.contains('READ_MEDIA_VIDEO'), isTrue);
      expect(manifest.contains('READ_MEDIA_AUDIO'), isTrue);
      expect(manifest.contains('MANAGE_EXTERNAL_STORAGE'), isTrue);
      expect(manifest.contains('REQUEST_INSTALL_PACKAGES'), isTrue);
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
      expect(
        MaliciousLinkGuard.inspectUrl(
          'http://127.0.0.1:49201/blocked?domain=grabify.link&category=security',
        ),
        isNull,
      );
      expect(
        MaliciousLinkGuard.inspectUrl('http://192.168.1.1/login'),
        isNull,
      );
      expect(
        MaliciousLinkGuard.inspectUrl('https://cdn.unknown-site.com/invoice.hta'),
        isNotNull,
      );

      // فناوری های تشخیص لینک ۲۰۲۶:
      // ۱. دیکدر Punycode (RFC 3492) و هموگراف سیریلیک (مثلاً pаypal.com = xn--pypal-4ve.com)
      expect(
        MaliciousLinkGuard.inspectUrl('https://xn--pypal-4ve.com/signin'),
        isNotNull,
      );
      // ۲. ترکیب الفبای لاتین و سیریلیک (Mixed-Script Homoglyph)
      expect(
        MaliciousLinkGuard.inspectUrl('https://te\u0406egram.org/login'),
        isNotNull,
      );
      // ۳. آی پی مبهم (Decimal / Hex / Octal)
      expect(
        MaliciousLinkGuard.inspectUrl('http://3232235826/login'),
        isNotNull,
      );
      expect(
        MaliciousLinkGuard.inspectUrl('http://0x7f000001/payload'),
        isNotNull,
      );
      expect(
        MaliciousLinkGuard.inspectUrl('http://0177.0.0.1/gate'),
        isNotNull,
      );
      // ۴. فریب @ Userinfo
      expect(
        MaliciousLinkGuard.inspectUrl('https://telegram.org@evil.com/auth'),
        isNotNull,
      );
      // ۵. جعل برند در زیردامنه، Combosquatting و Typosquatting
      expect(
        MaliciousLinkGuard.inspectUrl('https://telegram.org.verify-gift.xyz/claim'),
        isNotNull,
      );
      expect(
        MaliciousLinkGuard.inspectUrl('https://shaparak-pay.top/portal'),
        isNotNull,
      );
      expect(
        MaliciousLinkGuard.inspectUrl('https://telegrma.com/login'),
        isNotNull,
      );
      // ۶. بازرسی بازگشتی Open Redirect و Base64 Payload
      expect(
        MaliciousLinkGuard.inspectUrl(
          'https://www.google.com/url?q=https://grabify.link/track',
        ),
        isNotNull,
      );
      expect(
        MaliciousLinkGuard.inspectUrl(
          'https://middle.example/go?next=aHR0cHM6Ly9ncmFiaWZ5LmxpbmsveHl6',
        ),
        isNotNull,
      );
    });

    test('SafeUrlLauncher ریدایرکت کوتاه کننده لینک را پیش از باز شدن مسدود می کند', () async {
      MaliciousLinkMatch? blocked;
      final void Function(MaliciousLinkMatch)? prev =
          SafeUrlLauncher.onThreatBlocked;
      SafeUrlLauncher.onThreatBlocked = (MaliciousLinkMatch m) => blocked = m;
      addTearDown(() => SafeUrlLauncher.onThreatBlocked = prev);

      bool opened = false;
      final bool allowed = await SafeUrlLauncher.open(
        Uri.parse('https://bit.ly/3phish2026'),
        redirectResolver: (Uri u) async =>
            Uri.parse('https://telegram.org.verify-account.xyz/auth'),
        launcher: (_, __) async {
          opened = true;
          return true;
        },
      );
      expect(allowed, isFalse);
      expect(opened, isFalse);
      expect(blocked, isNotNull);
    });

    test('تاریخچه نسخه ها در UpdatesPage موارد تغییرات را زیر هم تفکیک می کند', () {
      const UpdateInfo rel = UpdateInfo(
        version: '1.0.3',
        url: 'https://example.invalid/app.apk',
        notes:
            '🇮🇷 فیلترشکن آمبرلا نسخه 1.0.3 • طرح رایگان ۳ گیگابایتی • مسدودسازی عمیق تبلیغات HTTPS',
      );
      expect(rel.changelogItems, <String>[
        '🇮🇷 فیلترشکن آمبرلا نسخه 1.0.3',
        'طرح رایگان ۳ گیگابایتی',
        'مسدودسازی عمیق تبلیغات HTTPS',
      ]);

      final String updatesUi = File(
        'lib/ui/pages/updates_page.dart',
      ).readAsStringSync();
      expect(updatesUi, isNot(contains("join(' · ')")));
      expect(updatesUi, contains('noteItems:'));
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
      expect(find.text('مجوز دسترسی کامل مدیریت فایل'), findsOneWidget);
      expect(find.text('دسترسی کامل مدیریت فایل'), findsOneWidget);
      expect(find.text('انتخاب پوشه دانلودها برای اسکن'), findsNothing);
      expect(find.textContaining('سپر امنیتی گوگل پلی'), findsOneWidget);
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

      native.scanResult = const SecurityScanResult(
        clean: true,
        scannedApps: 12,
        scannedFiles: 25,
        storageAccessGranted: true,
      );
      await sec.scanNow(silent: false);
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('security-storage-access-button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('security-storage-access-active-card')),
        findsOneWidget,
      );
      expect(find.text('دسترسی کامل مدیریت فایل فعال است'), findsOneWidget);
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
            categories: <String>['adult', 'gambling'],
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
        expect(pornRule.containsKey('rule_set'), isFalse);

        final Map<String, dynamic> pornRuleSet = routeRules.firstWhere(
          (Map<String, dynamic> r) =>
              '${r['rule_set']}'.contains('geosite-category-porn'),
        );
        expect(pornRuleSet['action'], 'route');
        expect(pornRuleSet['outbound'], RuntimeConfig.blockPageOutboundTag);
        expect(pornRuleSet.containsKey('domain_suffix'), isFalse);

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
        expect(adsRule.containsKey('rule_set'), isFalse);

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

    test(
      'Android RuntimeConfig.finalize injects bundled local filter-*.srs rule sets offline when omitted during StartService',
      () {
        final Map<String, dynamic> coreSettings = UmbrellaCore.settingsJson(
          tun: true,
          systemProxy: false,
          port: 12334,
          includeFilterRuleSets: false,
          contentFilter: const FilterSettings(
            enabled: true,
            categories: <String>['adult', 'gambling'],
            customDomains: <String>['custom-blocked.example'],
          ),
        );
        final Map<String, dynamic> runtime = <String, dynamic>{
          'experimental': <String, dynamic>{
            'monitoring': <String, dynamic>{},
          },
          'outbounds': <dynamic>[
            <String, dynamic>{'tag': 'direct', 'type': 'direct'},
            <String, dynamic>{'tag': 'select', 'type': 'selector'},
          ],
          'dns': <String, dynamic>{
            'rules': <dynamic>[],
          },
          'route': <String, dynamic>{
            'rule_set': <dynamic>[],
            'rules': <dynamic>[
              <String, dynamic>{'action': 'sniff'},
            ],
          },
        };
        RuntimeConfig.finalize(
          runtime,
          profileTags: const <String>{},
          coreSettings: coreSettings,
          blockPagePort: 45124,
          localRuleSetPaths: const <String, String>{
            'filter-adult.srs': '/data/user/0/ir.umbrella.vpn/files/data/filter-adult.srs',
            'filter-gambling.srs': '/data/user/0/ir.umbrella.vpn/files/data/filter-gambling.srs',
            'filter-ads.srs': '/data/user/0/ir.umbrella.vpn/files/data/filter-ads.srs',
          },
        );
        final List<Map<String, dynamic>> ruleSets =
            ((runtime['route'] as Map<String, dynamic>)['rule_set']
                    as List<dynamic>)
                .cast<Map<String, dynamic>>();
        expect(
          ruleSets.any((Map<String, dynamic> rs) =>
              rs['tag'] == 'filter-adult' &&
              rs['type'] == 'local' &&
              rs['path'] == '/data/user/0/ir.umbrella.vpn/files/data/filter-adult.srs'),
          isTrue,
        );
        expect(
          ruleSets.any((Map<String, dynamic> rs) =>
              rs['tag'] == 'filter-gambling' &&
              rs['type'] == 'local' &&
              rs['path'] == '/data/user/0/ir.umbrella.vpn/files/data/filter-gambling.srs'),
          isTrue,
        );
        expect(
          ruleSets.any((Map<String, dynamic> rs) =>
              rs['tag'] == 'filter-ads' &&
              rs['type'] == 'local' &&
              rs['path'] == '/data/user/0/ir.umbrella.vpn/files/data/filter-ads.srs'),
          isTrue,
        );
        final List<Map<String, dynamic>> routeRules =
            ((runtime['route'] as Map<String, dynamic>)['rules']
                    as List<dynamic>)
                .cast<Map<String, dynamic>>();
        expect(
          routeRules.any((Map<String, dynamic> r) =>
              '${r['rule_set']}'.contains('filter-adult') &&
              r['outbound'] == RuntimeConfig.blockPageOutboundTag),
          isTrue,
        );
        expect(
          routeRules.any((Map<String, dynamic> r) =>
              '${r['rule_set']}'.contains('filter-ads') &&
              r['action'] == 'reject'),
          isTrue,
        );
        final List<dynamic> dnsRules =
            (runtime['dns'] as Map<String, dynamic>)['rules'] as List<dynamic>;
        expect(
          dnsRules.any((dynamic r) => '$r'.contains('filter-ads')),
          isTrue,
        );
        expect(
          dnsRules.any((dynamic r) => '$r'.contains('filter-adult')),
          isFalse,
        );
      },
    );

    test(
      'auto-close conflicting VPNs runs before securityGuard on Android connect and wires native kill/handover contracts',
      () async {
        final String manifest = File(
          'android/app/src/main/AndroidManifest.xml',
        ).readAsStringSync();
        expect(manifest, isNot(contains('android.permission.KILL_BACKGROUND_PROCESSES')));
        expect(manifest, contains('android.permission.BIND_VPN_SERVICE'));

        final String scannerKt = File(
          'android/app/src/main/kotlin/ir/umbrella/vpn/UmbrellaSecurityScanner.kt',
        ).readAsStringSync();
        expect(scannerKt, contains('fun closeConflictingVpns('));
        expect(scannerKt, contains('BIND_VPN_SERVICE'));
        expect(scannerKt, isNot(contains('killBackgroundProcesses')));
        expect(scannerKt, contains('hasActiveOtherVpnTransport'));

        final String handlerKt = File(
          'android/app/src/main/kotlin/ir/umbrella/vpn/MethodHandler.kt',
        ).readAsStringSync();
        expect(handlerKt, contains('"closeConflictingVpns"'));
        expect(handlerKt, contains('UmbrellaSecurityScanner.closeConflictingVpns'));

        final String mainDart = File('lib/main.dart').readAsStringSync();
        expect(mainDart, contains('await native.closeConflictingVpns()'));
        expect(mainDart, contains("t.key != 'vpn:active_other_tunnel'"));
        expect(mainDart, contains('unawaited(security.scanNow(silent: true));'));

        final _FakeNative native = _FakeNative()..closedOnNextCall = 2;
        native.scanResult = const SecurityScanResult(
          clean: false,
          scannedApps: 12,
          threats: <SecurityThreat>[
            SecurityThreat(
              key: 'vpn:active_other_tunnel',
              name: 'تونل وی پی ان فعال دیگر در سیستم',
              category: 'conflicting_vpn',
              severity: 'high',
              target: 'Android VPN Service',
              detail: 'تونل دیگر فعال است',
              remediationKind: 'vpn_settings',
              active: true,
            ),
          ],
        );
        final SecurityScannerController sec = SecurityScannerController(
          native: native,
          auth: _SignedAuth(
            native: native,
            gateway: GatewayClient(
              client: MockClient((_) async => http.Response('{}', 200)),
              enableNativeTransport: false,
            ),
            store: LocalStore.instance,
          ),
        );
        int closedAtGuardTime = 0;
        final VpnController vpn = VpnController(
          native: native,
          ipService: IpService(),
          sound: _FakeSound(),
          tray: TrayService(native),
          provisioner: CoreProvisioner(),
          settings: const AppSettings(corePreference: CorePreference.tun),
          securityGuard: () async {
            closedAtGuardTime = native.closeConflictingCalls;
            final SecurityScanResult scan = await sec.ensureCleanBeforeConnect();
            final List<SecurityThreat> blocking = scan.threats
                .where((SecurityThreat t) => t.key != 'vpn:active_other_tunnel')
                .toList();
            return blocking.isEmpty ? '' : blocking.first.name;
          },
        );
        addTearDown(() {
          sec.dispose();
          vpn.dispose();
        });

        final ConnectOutcome outcome = await vpn.connect();
        expect(closedAtGuardTime, 1);
        expect(native.closeConflictingCalls, 1);
        expect(outcome.message, isNot(contains('تونل وی پی ان فعال دیگر')));

        native.scanResult = const SecurityScanResult(
          clean: false,
          scannedApps: 12,
          threats: <SecurityThreat>[
            SecurityThreat(
              key: 'vpn:psiphon',
              name: 'Psiphon (فیلترشکن ناسازگار)',
              category: 'conflicting_vpn',
              severity: 'high',
              target: 'com.psiphon3',
              detail: 'Psiphon فعال است.',
              packageName: 'com.psiphon3',
              remediationKind: 'uninstall',
              active: true,
            ),
          ],
        );
        final ConnectOutcome blocked = await vpn.connect();
        expect(blocked.ok, isFalse);
        expect(blocked.message, contains('Psiphon'));
        expect(native.closeConflictingCalls, 2);
      },
    );

    test(
      'Android end-to-end: always-on AdBlock, 2-category filter UI, Trojan reject fallback, background scanner hardening, and telemetry',
      () async {
        expect(FilterSettings.categoryLabels.keys.toList(), <String>['adult', 'gambling']);
        expect(FilterSettings.categoryLabels.containsKey('ads'), isFalse);

        final Map<String, dynamic> fullAlwaysAd = UmbrellaCore.settingsJson(
          tun: true,
          systemProxy: false,
          port: 12334,
          networkSettings: const AppSettings(blockAds: false),
          contentFilter: const FilterSettings(enabled: false),
          includeFilterRuleSets: true,
        );
        expect(fullAlwaysAd['block-ads'], isTrue);

        final Map<String, dynamic> fastStart = UmbrellaCore.settingsJson(
          tun: true,
          systemProxy: false,
          port: 12334,
          networkSettings: const AppSettings(blockAds: false),
          contentFilter: const FilterSettings(enabled: false),
          includeFilterRuleSets: false,
        );
        expect(fastStart['block-ads'], isFalse);

        final Map<String, dynamic> runtimeNoBlockPage = <String, dynamic>{
          'experimental': <String, dynamic>{'monitoring': <String, dynamic>{}},
          'outbounds': <dynamic>[
            <String, dynamic>{'tag': 'direct', 'type': 'direct'},
            <String, dynamic>{'tag': 'select', 'type': 'selector'},
          ],
          'dns': <String, dynamic>{'rules': <dynamic>[]},
          'route': <String, dynamic>{
            'rule_set': <dynamic>[],
            'rules': <dynamic>[
              <String, dynamic>{'action': 'sniff'},
            ],
          },
        };
        RuntimeConfig.finalize(
          runtimeNoBlockPage,
          profileTags: const <String>{},
          coreSettings: fullAlwaysAd,
          blockPagePort: 0,
          localRuleSetPaths: const <String, String>{
            'filter-ads.srs': '/data/user/0/ir.umbrella.vpn/files/data/filter-ads.srs',
          },
        );
        final List<dynamic> routeRules =
            (runtimeNoBlockPage['route'] as Map<String, dynamic>)['rules']
                as List<dynamic>;
        final List<dynamic> dnsRules =
            (runtimeNoBlockPage['dns'] as Map<String, dynamic>)['rules']
                as List<dynamic>;
        expect(
          routeRules.any((dynamic r) =>
              r is Map && r['action'] == 'reject' && '$r'.contains('grabify.link')),
          isTrue,
        );
        expect(
          dnsRules.any((dynamic r) =>
              r is Map && r['action'] == 'reject' && '$r'.contains('grabify.link')),
          isTrue,
        );
        expect(
          routeRules.any((dynamic r) =>
              r is Map && r['action'] == 'reject' && '$r'.contains('filter-ads')),
          isTrue,
        );

        final String manifest = File(
          'android/app/src/main/AndroidManifest.xml',
        ).readAsStringSync();
        expect(manifest, contains('READ_MEDIA_IMAGES'));
        expect(manifest, contains('READ_MEDIA_VIDEO'));
        expect(manifest, contains('UmbrellaSecurityJobService'));

        final String bgMonitorKt = File(
          'android/app/src/main/kotlin/ir/umbrella/vpn/bg/UmbrellaBackgroundMonitor.kt',
        ).readAsStringSync();
        expect(bgMonitorKt, contains('class UmbrellaSecurityJobService : JobService()'));
        expect(bgMonitorKt, contains('deleteTargetInBackground'));
        expect(bgMonitorKt, contains('AppApi'));
        expect(bgMonitorKt, contains('app/security-alert'));

        final String scannerKt = File(
          'android/app/src/main/kotlin/ir/umbrella/vpn/UmbrellaSecurityScanner.kt',
        ).readAsStringSync();
        expect(scannerKt, isNot(contains('if (lower.contains("umbrella")) return null')));
        expect(scannerKt, isNot(contains('lowerEntry.contains("umbrella")')));
        expect(scannerKt, contains('deleteTargetInBackground'));
        expect(scannerKt, contains('inspectImagePolyglotFile'));
        expect(scannerKt, contains('isSafeMotionPhotoTrailer'));
        expect(scannerKt, contains('inspectPdfPayload'));
        expect(scannerKt, contains('shannonEntropy'));
        expect(scannerKt, contains('inspectDownloadedApk'));
        expect(scannerKt, contains('inspectInstalledAppBehavioralRisk'));
        expect(scannerKt, contains('hasHiddenPayloadEntriesInApk'));
        expect(scannerKt, contains('craxsrat'));
        expect(scannerKt, contains('spynote'));
        expect(scannerKt, contains('dl:webp_eof:'));
        expect(scannerKt, contains('containsIdentifierToken(combined, "brata")'));
        expect(scannerKt, contains('containsIdentifierToken(combined, "godfather")'));

        final String handlerKt = File(
          'android/app/src/main/kotlin/ir/umbrella/vpn/MethodHandler.kt',
        ).readAsStringSync();
        expect(handlerKt, contains('"syncBackgroundSecurityAuth"'));
        expect(handlerKt, contains('"consumePendingBackgroundSecurityEvents"'));

        final String appKt = File(
          'android/app/src/main/kotlin/ir/umbrella/vpn/UmbrellaApplication.kt',
        ).readAsStringSync();
        expect(appKt, contains('UmbrellaBackgroundMonitor.initialize'));

        final String settingsPageDart = File(
          'lib/ui/pages/settings_page.dart',
        ).readAsStringSync();
        expect(settingsPageDart, contains('همیشه فعال'));

        final Map<String, dynamic> capturedHeartbeat = <String, dynamic>{};
        final Map<String, dynamic> capturedAlert = <String, dynamic>{};
        final GatewayClient gateway = GatewayClient(
          baseUrl: 'https://example.invalid/index.php?AppApi=',
          enableNativeTransport: false,
          client: MockClient((http.Request req) async {
            final Map<String, dynamic> body =
                jsonDecode(req.body) as Map<String, dynamic>;
            if (req.url.queryParameters['AppApi'] == 'auth/device') {
              capturedHeartbeat.addAll(body);
              return http.Response(
                jsonEncode(<String, dynamic>{
                  'ok': true,
                  'subscription_url': '',
                }),
                200,
              );
            }
            if (req.url.queryParameters['AppApi'] == 'app/security-alert') {
              capturedAlert.addAll(body);
              return http.Response(jsonEncode(<String, dynamic>{'ok': true}), 200);
            }
            return http.Response('{}', 200);
          }),
        );
        await gateway.heartbeat(
          token: 'tok-android',
          deviceId: 'dev-android',
          securityStatus: 'safe',
          scannedAtMs: 1763800000000,
          scannedFiles: 42,
          scannedApps: 19,
          scannedProcesses: 19,
        );
        expect(capturedHeartbeat['security_status'], 'safe');
        expect(capturedHeartbeat['scanned_files'], 42);

        await gateway.reportSecurityAlert(
          token: 'tok-android',
          deviceId: 'dev-android',
          platform: 'Android',
          appVersion: '1.0.3',
          threats: const <SecurityThreat>[],
          neutralized: const <NeutralizedSecurityEvent>[
            NeutralizedSecurityEvent(
              key: 'dl:poly_img:umbrella_decoy',
              name: 'تصویر آلوده',
              category: 'malicious_download',
              severity: 'critical',
              action: 'deleted',
              target: '/sdcard/Download/umbrella_photo.jpg',
              detail: 'تصویر آلوده در بررسی پس زمینه پاکسازی شد.',
              timestampMs: 1763800005000,
            ),
          ],
          securityStatus: 'safe',
          scannedAtMs: 1763800005000,
          scannedFiles: 43,
          scannedApps: 19,
          scannedProcesses: 19,
        );
        expect(capturedAlert['security_status'], 'safe');
        expect(capturedAlert['scanned_files'], 43);
        expect((capturedAlert['neutralized'] as List<dynamic>).length, 1);
      },
    );

    test(
      'ارتقای ۲۰۲۶ کنترل محتوا (بزرگسالان و شرط بندی ایرانی/خارجی)، ضدتبلیغات و SafeUrlLauncher با پوشش regex و مسدودی DoH canary کار می کند',
      () async {
        const FilterSettings filter = FilterSettings(
          enabled: true,
          categories: <String>['adult', 'gambling'],
        );

        // ۱. بزرگسالان ایرانی و بین المللی بدون false-positive
        for (final String h in const <String>[
          'shahvani.com',
          'shahvani.online',
          'shahvani2026.xyz',
          'takporn.com',
          'looti.net',
          'loti.ir',
          'koskade.com',
          'pornhub.com',
          'xhamster43.desi',
        ]) {
          expect(
            UmbrellaCore.matchesContentFilterCategory(filter, h),
            'adult',
            reason: 'Expected adult block for $h',
          );
          expect(
            ContentBlockServer.classifyBlockedHost(h, filter: filter).category,
            'adult',
          );
        }
        for (final String clean in const <String>[
          'lotion.com',
          'plotin.org',
          'essex.ac.uk',
          'kosher.org',
        ]) {
          expect(
            UmbrellaCore.matchesContentFilterCategory(filter, clean),
            isNull,
            reason: 'Unexpected adult false positive for $clean',
          );
        }

        // ۲. شرط بندی ایرانی و آینه ها/فورواردهای ۲۰۲۶ بدون false-positive
        for (final String h in const <String>[
          'takbet.com',
          'takbetaddress.com',
          'takbet405.xyz',
          'betforward.com',
          'betfoorward.com',
          'betfoward.com',
          'betforwardbet.com',
          'bet90forward.com',
          'betforward.mobi',
          'hazaratbetwin.com',
          'jetbet90.info',
          '1win.pro',
          'bc.game',
        ]) {
          expect(
            UmbrellaCore.matchesContentFilterCategory(filter, h),
            'gambling',
            reason: 'Expected gambling block for $h',
          );
          expect(
            ContentBlockServer.classifyBlockedHost(h, filter: filter).category,
            'gambling',
          );
        }
        for (final String clean in const <String>[
          'better.com',
          'pishbini-hava.ir',
          'enfejar-noor.ir',
          'youtube.com',
          'youtubei.googleapis.com',
        ]) {
          expect(
            UmbrellaCore.matchesContentFilterCategory(filter, clean),
            isNull,
            reason: 'Unexpected gambling false positive for $clean',
          );
        }

        // ۳. ضدتبلیغات یوتیوب و ایرانی ۲۰۲۶ بدون مسدودی دامنه های اصلی پخش ویدیو
        for (final String adHost in const <String>[
          'ads.youtube.com',
          'adservice.google.de',
          'ep1.adtrafficquality.google',
          'pagead2.googlesyndication.com',
          'raykaad.com',
          'adnegah.com',
          'api.yektanet.com',
          'cdn.tapsell.ir',
        ]) {
          expect(
            UmbrellaCore.isAlwaysBlockedAdHost(adHost),
            isTrue,
            reason: 'Expected ad block for $adHost',
          );
        }
        for (final String ytCore in const <String>[
          'youtube.com',
          'www.youtube.com',
          'youtubei.googleapis.com',
          'i.ytimg.com',
        ]) {
          expect(UmbrellaCore.isAlwaysBlockedAdHost(ytCore), isFalse);
        }

        // ۴. تزریق domain_regex و مسدودی Mozilla DoH canary در RuntimeConfig.finalize
        final Map<String, dynamic> settings = UmbrellaCore.settingsJson(
          tun: true,
          systemProxy: false,
          port: 12334,
          contentFilter: filter,
          networkSettings: const AppSettings(blockAds: true),
        );
        final Map<String, dynamic> compiled = <String, dynamic>{
          'experimental': <String, dynamic>{
            'monitoring': <String, dynamic>{},
          },
          'outbounds': <dynamic>[
            <String, dynamic>{'tag': 'direct §hide§', 'type': 'direct'},
            <String, dynamic>{'tag': 'select', 'type': 'selector'},
          ],
          'dns': <String, dynamic>{
            'rules': <dynamic>[
              <String, dynamic>{'server': 'dns-remote-group'},
            ],
          },
          'route': <String, dynamic>{
            'rule_set': <dynamic>[],
            'rules': <dynamic>[
              <String, dynamic>{'action': 'sniff'},
            ],
          },
        };
        RuntimeConfig.finalize(
          compiled,
          profileTags: const <String>{},
          coreSettings: settings,
          blockPagePort: 18080,
        );
        final List<dynamic> routeRules =
            (compiled['route'] as Map<String, dynamic>)['rules']
                as List<dynamic>;
        final List<dynamic> dnsRules =
            (compiled['dns'] as Map<String, dynamic>)['rules']
                as List<dynamic>;
        expect(
          routeRules.any((dynamic r) =>
              r is Map &&
              r['outbound'] == RuntimeConfig.blockPageOutboundTag &&
              '${r['domain_regex']}'.contains('shahvani') &&
              '${r['domain_regex']}'.contains('loti')),
          isTrue,
        );
        expect(
          routeRules.any((dynamic r) =>
              r is Map &&
              r['outbound'] == RuntimeConfig.blockPageOutboundTag &&
              '${r['domain_regex']}'.contains('tak-?bet')),
          isTrue,
        );
        expect(
          dnsRules.any((dynamic r) =>
              r is Map &&
              r['action'] == 'reject' &&
              '${r['domain']}'.contains('use-application-dns.net')),
          isTrue,
        );
        expect(
          dnsRules.any((dynamic r) =>
              r is Map &&
              r['action'] == 'reject' &&
              '${r['domain_regex']}'.contains('adservice')),
          isTrue,
        );
        // adult/gambling DNS reject باید در حالت صفحه مسدودی فعال برداشته شود تا صفحه مسدودی باز شود.
        expect(
          dnsRules.any((dynamic r) =>
              r is Map &&
              r['action'] == 'reject' &&
              '${r['domain_regex']}'.contains('shahvani')),
          isFalse,
        );

        // ۵. مسدودی پیش از باز شدن پیوندهای کوتاه شده ایرانی منتهی به سایت شرط بندی بدون ثبت بدافزار
        int threatEvents = 0;
        int contentEvents = 0;
        final void Function(MaliciousLinkMatch)? prevThreat =
            SafeUrlLauncher.onThreatBlocked;
        final void Function(MaliciousLinkMatch)? prevContent =
            SafeUrlLauncher.onContentBlocked;
        SafeUrlLauncher.onThreatBlocked = (_) => threatEvents++;
        SafeUrlLauncher.onContentBlocked = (_) => contentEvents++;
        addTearDown(() {
          SafeUrlLauncher.onThreatBlocked = prevThreat;
          SafeUrlLauncher.onContentBlocked = prevContent;
        });

        bool launched = false;
        final bool allowed = await SafeUrlLauncher.open(
          Uri.parse('https://gir.ink/betfoward'),
          contentFilter: filter,
          redirectResolver: (_) async => Uri.parse('https://betfoorward.com/'),
          launcher: (_, __) async {
            launched = true;
            return true;
          },
        );
        expect(allowed, isFalse);
        expect(launched, isFalse);
        expect(contentEvents, 1);
        expect(threatEvents, 0);
      },
    );
  });

  group('اعلان تبلیغاتی و اشتراک رایگان ۳ گیگابایتی اندروید', () {
    final Uint8List validPng = Uint8List.fromList(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
      0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99,
      0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
      0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);

    test('پیش فرض حجم اشتراک رایگان ۳ گیگابایت است', () {
      const SubscriptionOffers defaults = SubscriptionOffers();
      expect(defaults.freeGb, 3);
      expect(defaults.freeDays, 1);
      final SubscriptionOffers parsed =
          SubscriptionOffers.fromJson(const <String, dynamic>{});
      expect(parsed.freeGb, 3);
    });

    test('دریافت اعلان تبلیغاتی و کش ایمن تصویر با رد پاسخ نامعتبر HTML', () async {
      int imageFetches = 0;
      final MockClient mockHttp = MockClient((http.Request req) async {
        final String api = req.url.queryParameters['AppApi'] ?? req.url.path;
        if (api.contains('app/announcement')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<String, dynamic>{
                'ok': true,
                'announcement': AppAnnouncement.fallback().toJson(),
                'promo_announcement': <String, dynamic>{
                  'enabled': true,
                  'version': 7,
                  'title': 'جشنواره ویژه آمبرلا',
                  'body': 'تخفیف ویژه اشتراک های یک ساله با سرعت بالا',
                  'image_url': 'app/promo-image?k=abc123def456',
                  'button_text': 'خرید اشتراک',
                  'button_url': 'https://t.me/UmbrellaSupport',
                  'interval_hours': 24,
                  'starts_at': 0,
                },
              }),
            ),
            200,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }
        if (api.contains('app/promo-image')) {
          imageFetches++;
          if (req.url.queryParameters['k'] == 'bad') {
            return http.Response('<html>error</html>', 200);
          }
          return http.Response.bytes(
            validPng,
            200,
            headers: const <String, String>{'content-type': 'image/png'},
          );
        }
        return http.Response('not found', 404);
      });

      final GatewayClient gw = GatewayClient(
        baseUrl: 'https://armin-soft.ir/Umbrella-Vpn/index.php?AppApi=',
        client: mockHttp,
        enableNativeTransport: false,
      );
      addTearDown(gw.close);

      final resolved = gw.resolveMediaUri('app/promo-image?k=abc123def456');
      expect(resolved, isNotNull);
      expect(resolved!.queryParameters['AppApi'], 'app/promo-image');
      expect(resolved.queryParameters['k'], 'abc123def456');

      final both = await gw.fetchAnnouncements();
      expect(both.promoAnnouncement, isNotNull);
      expect(both.promoAnnouncement!.isActive, isTrue);
      expect(both.promoAnnouncement!.version, 7);

      final Uint8List? img1 = await gw.fetchPromoImage('app/promo-image?k=abc123def456');
      expect(img1, isNotNull);
      expect(img1, equals(validPng));

      final Uint8List? imgCached = await gw.fetchPromoImage('app/promo-image?k=abc123def456');
      expect(imgCached, equals(validPng));
      expect(imageFetches, 1);

      final Uint8List? rejectedHtml = await gw.fetchPromoImage('app/promo-image?k=bad');
      expect(rejectedHtml, isNull);
    });

    test('زمان بندی بستن نوار تبلیغاتی، ارسال نوتیفیکیشن سیستم و پیش نمایش بایت تصویر', () async {
      final MockClient mockHttp = MockClient((http.Request req) async {
        final String api = req.url.queryParameters['AppApi'] ?? req.url.path;
        if (api.contains('app/announcement')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<String, dynamic>{
                'ok': true,
                'announcement': AppAnnouncement.fallback().toJson(),
                'promo_announcement': <String, dynamic>{
                  'enabled': true,
                  'version': 9,
                  'title': 'کمپین ویژه بهار',
                  'body': '۲۵ درصد حجم هدیه روی تمام بسته ها',
                  'image_url': 'app/promo-image?k=spring9',
                  'button_text': 'مشاهده پیشنهاد',
                  'button_url': 'https://armin-soft.ir/spring',
                  'interval_hours': 24,
                  'starts_at': 0,
                },
              }),
            ),
            200,
          );
        }
        if (api.contains('app/promo-image')) {
          return http.Response.bytes(validPng, 200);
        }
        return http.Response('{}', 200);
      });

      final _FakeNative native = _FakeNative();
      final GatewayClient gw = GatewayClient(
        baseUrl: 'https://armin-soft.ir/Umbrella-Vpn/index.php?AppApi=',
        client: mockHttp,
        enableNativeTransport: false,
      );
      final TrayService tray = TrayService(native);
      final AuthController auth = AuthController(
        native: native,
        gateway: gw,
        store: LocalStore.instance,
        tray: tray,
      );
      addTearDown(() {
        auth.dispose();
        gw.close();
      });

      await auth.syncAnnouncement();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(auth.promoAnnouncement.isActive, isTrue);
      expect(auth.promoAnnouncement.version, 9);
      expect(auth.shouldShowPromoBanner(), isTrue);
      expect(native.promoBalloons, hasLength(1));
      expect(native.promoBalloons.single.title, 'کمپین ویژه بهار');
      expect(native.promoBalloons.single.actionUrl, 'https://armin-soft.ir/spring');
      expect(native.promoBalloons.single.imageBytes, equals(validPng));

      // همگام سازی تکراری نباید دوباره نوتیفیکیشن سیستم را ارسال کند.
      await auth.syncAnnouncement();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(native.promoBalloons, hasLength(1));

      final DateTime now = DateTime.now().toUtc();
      await auth.dismissPromoBanner(now: now);
      expect(auth.shouldShowPromoBanner(now: now), isFalse);
      expect(
        auth.shouldShowPromoBanner(now: now.add(const Duration(hours: 25))),
        isTrue,
      );
    });

    testWidgets('PromoBannerBar و PromoAnnouncementDialog بدون سرریز در موبایل رندر می شوند', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      bool opened = false;
      bool dismissed = false;
      bool acted = false;
      const PromoAnnouncement promo = PromoAnnouncement(
        enabled: true,
        version: 11,
        title: 'فروش ویژه تابستانه آمبرلا با پهنای باند نامحدود',
        body: 'اشتراک های پرسرعت با تخفیف استثنایی همین حالا در دسترس است.',
        imageUrl: 'app/promo-image?k=sum11',
        buttonText: 'فعال سازی',
        buttonUrl: 'https://t.me/UmbrellaSupport',
        intervalHours: 24,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: <Widget>[
                    PromoBannerBar(
                      promo: promo,
                      imageBytes: validPng,
                      dense: true,
                      onOpen: () => opened = true,
                      onAction: () => acted = true,
                      onDismiss: () => dismissed = true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('promo_banner_bar')), findsOneWidget);
      await tester.tap(find.byKey(const Key('promo_banner_action_button')));
      await tester.pump();
      expect(acted, isTrue);

      await tester.tap(find.byKey(const Key('promo_banner_dismiss_button')));
      await tester.pump();
      expect(dismissed, isTrue);

      await tester.tap(find.byKey(const Key('promo_banner_bar')));
      await tester.pump();
      expect(opened, isTrue);

      bool launchedFromDialog = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: PromoAnnouncementDialog(
                promo: promo,
                initialImageBytes: validPng,
                onActionLaunch: () async {
                  launchedFromDialog = true;
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('promo_announcement_dialog')), findsOneWidget);
      expect(find.byKey(const Key('promo_dialog_image')), findsOneWidget);
      await tester.tap(find.byKey(const Key('promo_dialog_action_button')));
      await tester.pumpAndSettle();
      expect(launchedFromDialog, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('معافیت فایل های سیستمی غیرقابل حذف و استاندارد نگارش فارسی', () {
    test('اسکنر اندروید فایل ها و برنامه های سیستمی غیرقابل حذف و امضای پلتفرم را معاف می کند', () {
      final String scannerKt = File(
        'android/app/src/main/kotlin/ir/umbrella/vpn/UmbrellaSecurityScanner.kt',
      ).readAsStringSync();
      final String methodKt = File(
        'android/app/src/main/kotlin/ir/umbrella/vpn/MethodHandler.kt',
      ).readAsStringSync();
      final String guardDart = File(
        'lib/core/malicious_link_guard.dart',
      ).readAsStringSync();
      final String dialogDart = File(
        'lib/ui/widgets/security_shield_dialog.dart',
      ).readAsStringSync();
      final String controllerDart = File(
        'lib/state/security_controller.dart',
      ).readAsStringSync();

      expect(scannerKt, contains('containsIdentifierToken'));
      expect(scannerKt, contains('isProtectedSystemPath'));
      expect(scannerKt, contains('isProtectedSystemApp'));
      expect(scannerKt, contains('isPlatformSignedArchive'));
      expect(scannerKt, contains('FLAG_SUPPORTS_DELETE'));
      expect(scannerKt, contains('/system/'));
      expect(scannerKt, contains('/vendor/'));
      expect(scannerKt, contains('/product/'));
      expect(scannerKt, contains('/apex/'));
      final Iterable<String> persianLiterals = RegExp(
        r'"[^"\n]*[\u0600-\u06FF][^"\n]*"',
      ).allMatches(scannerKt).map((RegExpMatch m) => m.group(0)!);
      expect(persianLiterals, isNotEmpty);
      for (final String lit in persianLiterals) {
        expect(lit, isNot(contains('(RAT)')));
        expect(lit, isNot(contains('PNG')));
        expect(lit, isNot(contains('JPEG')));
        expect(lit, isNot(contains('PDF')));
        expect(lit, isNot(contains('SVG')));
      }

      for (final String src in <String>[
        scannerKt,
        methodKt,
        guardDart,
        dialogDart,
        controllerDart,
      ]) {
        expect(src.contains('\u200C'), isFalse);
      }
      expect(dialogDart, isNot(contains('(JumpJump)')));
    });

    test('پایشگر لینک مخرب پیام های خالص فارسی بدون واژگان فنی انگلیسی تولید می کند', () {
      final List<MaliciousLinkMatch?> samples = <MaliciousLinkMatch?>[
        MaliciousLinkGuard.inspectUrl('data:text/html,<script>alert(1)</script>'),
        MaliciousLinkGuard.inspectUrl('https://example.com/\u202Egpj.exe'),
        MaliciousLinkGuard.inspectUrl('https://example.com/?q=powershell%20-enc%20AAAA'),
        MaliciousLinkGuard.inspectUrl('https://185.10.20.30:4444/connect'),
        MaliciousLinkGuard.inspectUrl('https://example.com/?u=TVqQAAMAAAA'),
        MaliciousLinkGuard.inspectUrl('https://example.com/#https://grabify.link/x'),
      ];
      for (final MaliciousLinkMatch? hit in samples) {
        expect(hit, isNotNull);
        final String combined = '${hit!.title} ${hit.detail}';
        expect(combined.contains('\u200C'), isFalse);
        expect(combined, isNot(contains('Punycode')));
        expect(combined, isNot(contains('DGA')));
        expect(combined, isNot(contains('Data URI')));
        expect(combined, isNot(contains('RLO')));
        expect(combined, isNot(contains('ClickFix')));
        expect(combined, isNot(contains('Base64')));
        expect(combined, isNot(contains('Fragment')));
        expect(combined, isNot(contains('RAT')));
      }
      final MaliciousLinkMatch? c2Hit = MaliciousLinkGuard.inspectUrl(
        'https://185.10.20.30:4444/connect',
      );
      expect(c2Hit, isNotNull);
      expect(c2Hit!.title, contains('۴۴۴۴'));
      expect(c2Hit.detail, contains('۴۴۴۴'));
    });

    testWidgets('SecurityShieldDialog ارقام فارسی نمایش می دهد و متن وضعیت امن را تمیز رندر می کند', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final _FakeNative native = _FakeNative()
        ..scanResult = const SecurityScanResult(
          clean: false,
          scannedApps: 12,
          scannedFiles: 45,
          threats: <SecurityThreat>[
            SecurityThreat(
              key: 'dl:sample_2026',
              name: 'فایل مشکوک 2026',
              category: 'malicious_download',
              severity: 'critical',
              target: '/sdcard/Download/sample.exe',
              detail: 'کد خطای امنیتی 99 در بررسی فایل ثبت شد.',
              path: '/sdcard/Download/sample.exe',
              remediationKind: 'file',
              active: false,
            ),
          ],
        );
      final SecurityScannerController sec = SecurityScannerController(
        native: native,
        autoDeleteMaliciousDownloads: false,
      );
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
              child: Scaffold(body: SecurityShieldDialog()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('فایل مشکوک ۲۰۲۶'), findsOneWidget);
      expect(find.text('کد خطای امنیتی ۹۹ در بررسی فایل ثبت شد.'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey<String>('security-remediate-all-button')));
      await tester.pumpAndSettle();

      expect(
        find.text('دستگاه در برابر بدافزارها، فایل های آلوده و فیلترشکن های ناسازگار ایمن است.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
      sec.dispose();
      toasts.dispose();
    });

    test('حفظ اعداد انگلیسی در لینک ها، مسیرهای فایل و کدهای فنی داخل Fa.num و درگاه', () {
      expect(
        Fa.num('لینک کانال t.me/UmbrellaVPN_Channel/123 و ساب site.ir:8443/sub/99?x=2 و نسخه 1.0.3'),
        'لینک کانال t.me/UmbrellaVPN_Channel/123 و ساب site.ir:8443/sub/99?x=2 و نسخه ۱.۰.۳',
      );
      expect(
        Fa.num('پروکسی hy2://pw9@185.10.20.30:8443?sni=a1.ir#Srv1 و socks5://user1:pass2@127.0.0.1:10808'),
        'پروکسی hy2://pw9@185.10.20.30:8443?sni=a1.ir#Srv1 و socks5://user1:pass2@127.0.0.1:10808',
      );
      expect(
        Fa.num(r'مسیر C:\Users\Ali123\Downloads\bad2.exe و /sdcard/Download/2026/app1.apk'),
        r'مسیر C:\Users\Ali123\Downloads\bad2.exe و /sdcard/Download/2026/app1.apk',
      );
      expect(
        Fa.num('[مشاهده 2](https://site.ir/v1/23) و [https://site.ir/12](https://site.ir/12)'),
        '[مشاهده ۲](https://site.ir/v1/23) و [https://site.ir/12](https://site.ir/12)',
      );
      expect(
        Fa.num("<a href='https://t.me/c/123/4'>پست 5</a>"),
        "<a href='https://t.me/c/123/4'>پست ۵</a>",
      );
      expect(
        Fa.num('ابزار 3x-ui و فایل Umbrella-VPN-1.0.3-universal.apk و کلید wg-key-99'),
        'ابزار 3x-ui و فایل Umbrella-VPN-1.0.3-universal.apk و کلید wg-key-99',
      );

      final String authSrc = File('lib/state/auth_controller.dart').readAsStringSync();
      final String parsersSrc = File('lib/data/parsers.dart').readAsStringSync();
      expect(authSrc.contains('Fa.toEn(base.trim())'), isTrue);
      expect(parsersSrc.contains(r'Fa.num(host)'), isFalse);
    });

    test('پشتیبان گیری و بازیابی شناسه دستگاه و ارسال نام و پلتفرم یکسان بدون نیم فاصله', () async {
      final String authSrc = File('lib/state/auth_controller.dart').readAsStringSync();
      expect(authSrc.contains('\u200C'), isFalse);
      expect(authSrc.contains("readFileSync('device_id.txt')"), isTrue);
      expect(authSrc.contains("writeFileSync('device_id.txt', _deviceId)"), isTrue);
      expect(authSrc.contains('platform: _device.platformLabel'), isFalse);
      expect(authSrc.contains('deviceName: _device.deviceName'), isTrue);

      await LocalStore.instance.init();
      const String savedId = '11223344556677889900aabbccddeeff';
      LocalStore.instance.writeFileSync('device_id.txt', savedId);
      await LocalStore.instance.remove(StoreKeys.deviceId);
      addTearDown(() async {
        final File f = LocalStore.instance.fileSync('device_id.txt');
        if (f.existsSync()) {
          f.deleteSync();
        }
        await LocalStore.instance.remove(StoreKeys.deviceId);
      });

      final AuthController auth = AuthController(
        native: _FakeNative(),
        gateway: GatewayClient(
          baseUrl: 'https://example.invalid/index.php?AppApi=',
          enableNativeTransport: false,
          client: MockClient((http.Request _) async => http.Response('{"ok":true}', 200)),
        ),
        store: LocalStore.instance,
      );
      addTearDown(auth.dispose);
      await auth.restore();
      expect(auth.deviceId, savedId);
      expect(LocalStore.instance.read(StoreKeys.deviceId), savedId);
    });
  });
}
