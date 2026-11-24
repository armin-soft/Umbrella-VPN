import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

class _FakeNative implements NativeBridge {
  SecurityScanResult scanResult = const SecurityScanResult();
  List<InstalledAppInfo> apps = const <InstalledAppInfo>[];
  String? pickedExe;
  final List<String> remediatedKeys = <String>[];

  @override
  bool get available => true;

  @override
  Future<bool> isElevated() async => true;

  @override
  Future<List<InstalledAppInfo>> installedApps() async => apps;

  @override
  Future<String?> pickExecutableFile() async => pickedExe;

  @override
  Future<SecurityScanResult> scanDeviceSecurity() async => scanResult;

  @override
  Future<RemediationResult> remediateSecurityThreat(SecurityThreat threat) async {
    remediatedKeys.add(threat.key);
    scanResult = const SecurityScanResult(
      clean: true,
      scannedProcesses: 42,
      scannedApps: 18,
      scannedFiles: 12,
    );
    return const RemediationResult(
      ok: true,
      actionTaken: true,
      stillPresent: false,
      message: 'تهدید با موفقیت متوقف و پاکسازی شد.',
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
  String get deviceId => 'dev-win-sec-1';

  @override
  SessionData? get session => const SessionData(
        token: 'tok-sec-1',
        uuid: '11111111-1111-4111-8111-111111111111',
        deviceId: 'dev-win-sec-1',
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

  group('اعلان پویای داخل برنامه (مدیریت شده در ربات)', () {
    test('زمان بندی نسخه، شروع آینده، غیرفعال بودن، یک بار مصرف و انتشار مجدد دقیق کار می کنند', () async {
      final DateTime now = DateTime.utc(2026, 11, 22, 12, 0, 0);

      final AppAnnouncement disabled = AppAnnouncement.fallback().toJson().let(
        (Map<String, dynamic> j) => AppAnnouncement.fromJson(<String, dynamic>{
          ...j,
          'enabled': false,
        }),
      );
      expect(
        await TelegramChannelPrompt.isAnnouncementDue(disabled, now: now),
        isFalse,
      );

      final AppAnnouncement futureStart = AppAnnouncement.fromJson(<String, dynamic>{
        'enabled': true,
        'version': 2,
        'title': 'آپدیت جدید',
        'body': 'نسخه تازه منتشر شد',
        'button_text': 'مشاهده',
        'button_url': 'https://armin-soft.ir/update',
        'interval_hours': 24,
        'starts_at': now.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000,
      });
      expect(
        await TelegramChannelPrompt.isAnnouncementDue(futureStart, now: now),
        isFalse,
      );

      final AppAnnouncement once = AppAnnouncement.fromJson(<String, dynamic>{
        'enabled': true,
        'version': 3,
        'title': 'اطلاعیه یک بار',
        'body': 'متن اطلاعیه',
        'button_text': 'باز کردن',
        'button_url': 'https://t.me/UmbrellaSupport',
        'interval_hours': 0,
        'starts_at': 0,
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
          now: now.add(const Duration(days: 30)),
        ),
        isFalse,
      );

      // با افزایش نسخه (انتشار مجدد برای همه)، بلافاصله دوباره نمایش داده می شود
      final AppAnnouncement republished = AppAnnouncement.fromJson(<String, dynamic>{
        'enabled': true,
        'version': 4,
        'title': 'اطلاعیه جدید',
        'body': 'متن جدید',
        'button_text': 'تایید',
        'button_url': 'https://armin-soft.ir',
        'interval_hours': 72,
      });
      expect(
        await TelegramChannelPrompt.isAnnouncementDue(republished, now: now),
        isTrue,
      );
    });

    testWidgets('TelegramChannelDialog متن، تیتر و دکمه پویای ربات را رندر می کند', (WidgetTester tester) async {
      final AppAnnouncement custom = AppAnnouncement.fromJson(<String, dynamic>{
        'enabled': true,
        'version': 5,
        'title': 'تخفیف ویژه پاییزی آمبرلا',
        'body': 'امکان خرید بسته های سه ماهه با تخفیف فعال شد.',
        'button_text': 'مشاهده صفحه',
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

      expect(find.text('تخفیف ویژه پاییزی آمبرلا'), findsOneWidget);
      expect(find.text('امکان خرید بسته های سه ماهه با تخفیف فعال شد.'), findsOneWidget);
      expect(find.text('مشاهده صفحه'), findsOneWidget);
      expect(find.text('armin-soft.ir'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('سپر امنیتی همیشه فعال ویندوز و ارتباط با تلگرام', () {
    test('JumpJump و Psiphon شناسایی، به سرور گزارش و با دستور پاکسازی متوقف می شوند', () async {
      final List<(String, Map<String, dynamic>)> sent = <(String, Map<String, dynamic>)>[];
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
          scannedProcesses: 48,
          scannedApps: 22,
          scannedFiles: 14,
          threats: <SecurityThreat>[
            SecurityThreat(
              key: 'malware:jumpjump',
              name: 'JumpJump VPN (بدافزار / ابزار مخرب)',
              category: 'malware',
              severity: 'critical',
              target: r'C:\Users\Test\Downloads\JumpJump.exe',
              detail: 'برنامه مخرب JumpJump شناسایی شد.',
              processName: 'JumpJump.exe',
              active: true,
            ),
            SecurityThreat(
              key: 'vpn:psiphon',
              name: 'Psiphon (فیلترشکن ناسازگار)',
              category: 'conflicting_vpn',
              severity: 'high',
              target: 'psiphon3.exe',
              detail: 'فیلترشکن Psiphon در حال اجرا است.',
              processName: 'psiphon3.exe',
              active: true,
            ),
          ],
        );

      final GatewayClient gw = GatewayClient(client: mockHttp);
      final _SignedAuth auth = _SignedAuth(
        native: native,
        gateway: gw,
        store: LocalStore.instance,
      );
      final _FakeVpn vpn = _FakeVpn()..current = VpnStatus.connected;
      int blockedCallbacks = 0;

      final SecurityScannerController sec = SecurityScannerController(
        native: native,
        auth: auth,
        isVpnActive: () => vpn.status.active,
      )..onThreatBlockedWhileConnected = (_) {
          blockedCallbacks++;
          vpn.disconnect();
        };

      final SecurityScanResult before = await sec.ensureCleanBeforeConnect();
      expect(before.hasThreats, isTrue);
      expect(sec.threats, hasLength(2));
      expect(blockedCallbacks, 1);
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

    testWidgets('SecurityStatusBadge و SecurityShieldDialog وضعیت خطر را نمایش می دهند', (WidgetTester tester) async {
      final _FakeNative native = _FakeNative()
        ..scanResult = const SecurityScanResult(
          clean: false,
          scannedProcesses: 30,
          threats: <SecurityThreat>[
            SecurityThreat(
              key: 'vpn:psiphon',
              name: 'Psiphon (فیلترشکن ناسازگار)',
              category: 'conflicting_vpn',
              severity: 'high',
              target: 'psiphon3.exe',
              detail: 'فیلترشکن ناسازگار در حال اجراست.',
              processName: 'psiphon3.exe',
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
                body: Center(child: SecurityStatusBadge()),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey<String>('security-status-badge')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('security-status-badge')));
      await tester.pumpAndSettle();

      expect(find.text('سپر امنیتی همیشه فعال آمبرلا'), findsOneWidget);
      expect(find.text('Psiphon (فیلترشکن ناسازگار)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('security-remediate-all-button')));
      await tester.pumpAndSettle();

      expect(find.text('هیچ بدافزار یا وی پی ان ناسازگاری یافت نشد'), findsOneWidget);
      expect(sec.isClean, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
      sec.dispose();
      toasts.dispose();
    });
  });

  group('انتقال کنترل محتوا به تنظیمات اتصال و انتخاب گر برنامه در مسیریابی', () {
    test('SettingsPage کنترل محتوا ندارد و QuickConnectionPanel آن را رندر می کند و ConnectPage نشان امنیتی دارد', () {
      final String settingsSrc = File('lib/ui/pages/settings_page.dart').readAsStringSync();
      expect(settingsSrc.contains('ContentControlCard'), isFalse);
      expect(settingsSrc.contains('SecurityStatusBadge'), isTrue);
      final String quickSrc = File('lib/ui/widgets/quick_connection_panel.dart').readAsStringSync();
      expect(quickSrc.contains('ContentControlCard'), isTrue);
      final String connectSrc = File('lib/ui/pages/connect_page.dart').readAsStringSync();
      expect(connectSrc.contains('SecurityStatusBadge'), isTrue);
      expect(connectSrc.contains('needsSecurityCleanup'), isTrue);
      expect(connectSrc.contains('SecurityShieldDialog.show'), isTrue);
    });

    testWidgets('QuickConnectionPanel با وجود AuthController کارت کنترل محتوا را نمایش می دهد', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final _FakeNative native = _FakeNative();
      final GatewayClient gw = GatewayClient(
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

      auth.dispose();
      gw.close();
      settings.dispose();
      vpn.dispose();
      toasts.dispose();
    });

    testWidgets('AppRouteDialog لیست برنامه های نصب شده و انتخاب فایل را پشتیبانی می کند', (WidgetTester tester) async {
      final _FakeNative native = _FakeNative()
        ..apps = const <InstalledAppInfo>[
          InstalledAppInfo(
            name: 'Google Chrome',
            processName: 'chrome.exe',
            path: r'C:\Program Files\Google\Chrome\Application\chrome.exe',
            publisher: 'Google LLC',
            running: true,
          ),
          InstalledAppInfo(
            name: 'Telegram Desktop',
            processName: 'Telegram.exe',
            path: r'C:\Users\User\AppData\Roaming\Telegram Desktop\Telegram.exe',
            publisher: 'Telegram FZ-LLC',
          ),
        ]
        ..pickedExe = r'C:\Games\Launcher.exe';

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

      expect(find.text('Google Chrome'), findsOneWidget);
      expect(find.text('Telegram Desktop'), findsOneWidget);
      await tester.tap(find.text('Google Chrome'));
      await tester.pumpAndSettle();

      expect(find.text('chrome.exe'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('app-route-browse-exe')));
      await tester.pumpAndSettle();
      expect(find.text(r'C:\Games\Launcher.exe'), findsOneWidget);

      await tester.tap(find.text('ذخیره قانون'));
      await tester.pumpAndSettle();
      expect(saved?.process, r'C:\Games\Launcher.exe');
    });
  });

  group('شناسایی Hiddify و لوگوی سپر امنیتی آمبرلا', () {
    test('اسکنر ویندوز Hiddify را شناسایی می کند اما فایل های آمبرلا را استثنا می کند', () {
      final String cpp = File('packages/umbrella_native/windows/security_scanner.cpp').readAsStringSync();
      expect(cpp.contains('vpn:hiddify'), isTrue);
      expect(cpp.contains('hiddify'), isTrue);
      expect(cpp.contains('CurrentProcessDirLower'), isTrue);
      expect(cpp.contains('IsUmbrellaSafeBinary'), isTrue);

      expect(BrandAssets.all.contains(BrandAssets.securityShield), isTrue);
      expect(BrandAssets.all.contains(BrandAssets.securityAlert), isTrue);

      final String connectSrc = File('lib/ui/pages/connect_page.dart').readAsStringSync();
      expect(connectSrc.contains('SecurityShieldLogo'), isTrue);
    });

    test('تشخیص Hiddify پیش از اتصال اتصال را متوقف و پاکسازی می کند', () async {
      final _FakeNative native = _FakeNative()
        ..scanResult = const SecurityScanResult(
          clean: false,
          scannedProcesses: 22,
          threats: <SecurityThreat>[
            SecurityThreat(
              key: 'vpn:hiddify',
              name: 'Hiddify / Hiddify Next (فیلترشکن ناسازگار)',
              category: 'conflicting_vpn',
              severity: 'high',
              target: r'C:\Program Files\Hiddify\Hiddify.exe',
              detail: 'نرم افزار Hiddify روی سیستم یافت شد.',
              processName: 'Hiddify.exe',
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

    testWidgets('SecurityShieldLogo در وضعیت ایمن و هشدار از تصاویر برند استفاده می کند', (WidgetTester tester) async {
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

  group('پایش دانلود و تصاویر آلوده، لینک تروجانی و اعلان تلگرام در ویندوز', () {
    test('اسکنر C++ قواعد تصاویر polyglot، RLO، lnk/url و AMSI را دارد', () {
      final String cpp = File(
        'packages/umbrella_native/windows/security_scanner.cpp',
      ).readAsStringSync();
      expect(cpp.contains('malicious_download'), isTrue);
      expect(cpp.contains('HasPeHeaderAt'), isTrue);
      expect(cpp.contains('HasRloSpoofCharW'), isTrue);
      expect(cpp.contains('HasDoubleMasqueradeExtension'), isTrue);
      expect(cpp.contains('InspectShortcutThreat'), isTrue);
      expect(cpp.contains('ContainsDangerousUrlOrPayload'), isTrue);
      expect(cpp.contains('CandidateScanDirectories'), isTrue);
      expect(cpp.contains('amsi.ScanFile'), isTrue);
    });

    test('MaliciousLinkGuard لینک های تروجانی، هموگراف و پسوند دوگانه را شناسایی می کند', () {
      expect(
        MaliciousLinkGuard.inspectUrl('https://grabify.link/track123'),
        isNotNull,
      );
      expect(
        MaliciousLinkGuard.inspectUrl('https://xn--telegram-9va.com/login'),
        isNotNull,
      );
      expect(
        MaliciousLinkGuard.inspectUrl('https://cdn.evil.test/photo.png.exe'),
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
    });

    test('فایل دانلودی یا تصویر آلوده خودکار حذف شده و اعلان به تلگرام ارسال می شود', () async {
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
          scannedProcesses: 40,
          scannedApps: 12,
          scannedFiles: 19,
          threats: <SecurityThreat>[
            SecurityThreat(
              key: 'file:polyglot:img1',
              name: 'تصویر دانلودشده آلوده به بدافزار',
              category: 'malicious_download',
              severity: 'critical',
              target: r'C:\Users\Test\Downloads\invoice_scan.jpg',
              detail: 'درون تصویر دانلودشده کد اجرایی مخرب شناسایی شد.',
              path: r'C:\Users\Test\Downloads\invoice_scan.jpg',
              remediationKind: 'file',
              active: true,
            ),
          ],
        );

      final GatewayClient gw = GatewayClient(client: mockHttp);
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

    test('ترافیک زنده با لینک تروجانی بلافاصله بسته شده و به تلگرام گزارش می شود', () async {
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
      final GatewayClient gw = GatewayClient(client: mockHttp);
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
            id: 'conn-99',
            host: 'grabify.link',
            process: 'chrome.exe',
          ),
        ],
        closeConnection: (String id) async {
          closedIds.add(id);
          return true;
        },
      );

      expect(closedIds, <String>['conn-99']);
      expect(sec.neutralizedEvents, hasLength(1));
      expect(sec.neutralizedEvents.single.action, 'blocked_connection');
      expect(sent.any((e) => e.$1.contains('app/security-alert')), isTrue);

      sec.dispose();
      auth.dispose();
      gw.close();
    });

    testWidgets('SecurityShieldDialog در ویندوز لینک تروجانی را بررسی و بدون سرریز رندر می شود', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final _FakeNative native = _FakeNative()
        ..scanResult = const SecurityScanResult(
          clean: true,
          scannedProcesses: 20,
          scannedApps: 10,
          scannedFiles: 15,
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

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('security-link-input')),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('security-link-input')),
        'https://grabify.link/payload.exe',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('security-check-link-button')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('security-check-link-button')));
      await tester.pump();

      expect(sec.neutralizedEvents, hasLength(1));
      expect(find.textContaining('مسدودسازی اتصال'), findsOneWidget);
      expect(tester.takeException(), isNull);
      sec.dispose();
    });
  });
}

extension<T> on T {
  R let<R>(R Function(T value) block) => block(this);
}
