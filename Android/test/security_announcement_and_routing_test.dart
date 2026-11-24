import 'dart:convert';
import 'dart:io';

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
import 'package:umbrella_vpn/state/security_controller.dart';
import 'package:umbrella_vpn/state/settings_controller.dart';
import 'package:umbrella_vpn/state/toast_controller.dart';
import 'package:umbrella_vpn/ui/widgets/advanced_network_settings.dart';
import 'package:umbrella_vpn/ui/widgets/content_control.dart';
import 'package:umbrella_vpn/ui/widgets/quick_connection_panel.dart';
import 'package:umbrella_vpn/ui/widgets/security_shield_dialog.dart';
import 'package:umbrella_vpn/ui/widgets/telegram_channel_dialog.dart';
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
        deviceId: 'dev-and-and-1',
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
              utf8.encode('{"ok":true}'),
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
}
