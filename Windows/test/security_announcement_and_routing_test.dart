import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbrella_vpn/core/malicious_link_guard.dart';
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
import 'package:umbrella_vpn/vpn/runtime_config.dart';
import 'package:umbrella_vpn/vpn/umbrella_core.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

class _FakeNative implements NativeBridge {
  SecurityScanResult scanResult = const SecurityScanResult();
  List<InstalledAppInfo> apps = const <InstalledAppInfo>[];
  String? pickedExe;
  final List<String> remediatedKeys = <String>[];
  int portLookupCalls = 0;
  int closeConflictingCalls = 0;
  int closedOnNextCall = 0;

  @override
  bool get available => true;

  @override
  Future<int> closeConflictingVpns({
    List<String> excludeDirs = const <String>[],
    List<int> excludePids = const <int>[],
  }) async {
    closeConflictingCalls++;
    return closedOnNextCall;
  }

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
  Future<int> shutdownCores({bool skipIfClean = false}) async => 0;

  @override
  Future<List<int>> pidsHoldingPort(int port) async {
    portLookupCalls++;
    return const <int>[];
  }

  @override
  Future<String> processNameOf(int pid) async => '';

  @override
  Future<String> processPathOf(int pid) async => '';

  @override
  Future<List<String>> runningCores() async => const <String>[];

  @override
  Future<bool> systemProxyEnabled() async => false;

  @override
  Future<bool> isRunning(String name) async => false;

  @override
  Future<bool> killPid(int pid) async => true;

  @override
  Future<int> killByName(String name) async => 0;

  @override
  Future<bool> disableSystemProxy() async => true;

  @override
  Future<bool> restoreNetworkDefaults() async => true;

  @override
  Future<bool> trayInit() async => true;

  @override
  Future<bool> trayIcon(String path) async => true;

  @override
  Future<bool> trayTooltip(String text) async => true;

  @override
  Future<bool> trayMenu({
    required String connectLabel,
    required String disconnectLabel,
    required bool connected,
  }) async =>
      true;

  final List<({String title, String body, bool warning})> trayBalloons =
      <({String title, String body, bool warning})>[];

  @override
  Future<bool> trayBalloon({
    required String title,
    required String body,
    bool warning = false,
  }) async {
    trayBalloons.add((title: title, body: body, warning: warning));
    return true;
  }

  @override
  Future<bool> trayDestroy() async => true;

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
    await LocalStore.instance.remove(StoreKeys.promoAnnouncementState);
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
      // ۱. دیکدر Punycode (RFC 3492) و هموگراف سیریلیک (pаypal.com = xn--pypal-4ve.com)
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
        url: 'https://example.invalid/setup.exe',
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

    testWidgets(
      'SecurityShieldDialog در ویندوز بدون بخش بررسی دستی لینک و بدون سرریز رندر می شود',
      (WidgetTester tester) async {
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
        process: 'chrome.exe',
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
      'ContentBlockServer serves modern Umbrella browser UI and handles HTTP/HTTPS proxy blocks',
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

        expect(server.isRunning, isTrue);
        expect(server.uiPort, greaterThan(0));
        expect(server.proxyPort, greaterThan(0));

        Future<({int statusCode, String body, List<int> rawBytes})> rawHttpGet(
          Uri uri,
        ) async {
          final Socket s =
              await Socket.connect(InternetAddress.loopbackIPv4, uri.port);
          final String pathAndQuery = uri.hasQuery
              ? '${uri.path}?${uri.query}'
              : uri.path;
          s.write('GET $pathAndQuery HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n');
          await s.flush();
          final List<int> bytes = await s.fold<List<int>>(
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
            body: utf8.decode(bodyBytes, allowMalformed: true),
            rawBytes: bodyBytes,
          );
        }

        final ({int statusCode, String body, List<int> rawBytes}) uiRes =
            await rawHttpGet(
          server.buildBlockedPageUri('<script>alert(1)</script>.pornhub.com'),
        );
        final String uiHtml = uiRes.body;
        expect(uiRes.statusCode, HttpStatus.ok);
        expect(uiHtml, contains('dir="rtl"'));
        expect(uiHtml, contains('فیلترشکن آمبرلا'));
        expect(uiHtml, isNot(contains('Umbrella VPN')));
        expect(uiHtml, contains('@font-face'));
        expect(uiHtml, contains('Vazirmatn-Regular.ttf'));
        expect(uiHtml, contains('#E11D2E'));
        expect(uiHtml, contains('#07080B'));
        expect(uiHtml, contains('سپر کنترل محتوای آمبرلا فعال است'));
        expect(uiHtml, isNot(contains('<script>alert(1)</script>')));
        expect(uiHtml, contains('&lt;script&gt;'));

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

        for (final String assetPath in const <String>[
          '/assets/logo.png',
          '/assets/shield.png',
          '/assets/alert.png',
          '/assets/fonts/Vazirmatn-Regular.ttf',
          '/assets/fonts/Vazirmatn-Bold.ttf',
        ]) {
          final ({int statusCode, String body, List<int> rawBytes}) assetRes =
              await rawHttpGet(
            Uri.parse('http://127.0.0.1:${server.uiPort}$assetPath'),
          );
          expect(assetRes.statusCode, HttpStatus.ok, reason: assetPath);
          expect(assetRes.rawBytes, isNotEmpty, reason: assetPath);
        }

        final Socket httpTunnel =
            await Socket.connect(InternetAddress.loopbackIPv4, server.proxyPort);
        httpTunnel.write(
          'CONNECT pornhub.com:80 HTTP/1.1\r\nHost: pornhub.com:80\r\n\r\n',
        );
        await httpTunnel.flush();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        httpTunnel.write('GET / HTTP/1.1\r\nHost: pornhub.com\r\n\r\n');
        await httpTunnel.flush();
        final String httpTunnelResp = utf8.decode(
          await httpTunnel.fold<List<int>>(
            <int>[],
            (List<int> acc, List<int> chunk) => acc..addAll(chunk),
          ),
        );
        expect(httpTunnelResp, contains('200 Connection Established'));
        expect(httpTunnelResp, contains('403 Forbidden'));
        expect(httpTunnelResp, contains('فیلترشکن آمبرلا'));
        expect(httpTunnelResp, contains('data:font/ttf;base64,'));
        expect(httpTunnelResp, isNot(contains('Umbrella VPN')));
        expect(httpTunnelResp, contains('pornhub.com'));
        expect(
          events.any((InterceptedBlockEvent e) =>
              e.details.domain == 'pornhub.com' &&
              e.details.category == 'adult' &&
              !e.needsBrowserLaunch),
          isTrue,
        );

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

        final Socket trojanReq =
            await Socket.connect(InternetAddress.loopbackIPv4, server.proxyPort);
        trojanReq.write(
          'GET http://grabify.link/evil HTTP/1.1\r\nHost: grabify.link\r\n\r\n',
        );
        await trojanReq.flush();
        final String trojanResp = utf8.decode(
          await trojanReq.fold<List<int>>(
            <int>[],
            (List<int> acc, List<int> chunk) => acc..addAll(chunk),
          ),
        );
        expect(trojanResp, contains('403 Forbidden'));
        expect(trojanResp, contains('سپر امنیتی آمبرلا: تهدید مخرب مسدود شد'));
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
                'process_name': <String>['blocked-app.exe'],
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
              '${r['process_name']}'.contains('blocked-app.exe'),
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
      'RuntimeConfig.finalize injects bundled local filter-*.srs rule sets offline when omitted during core parse',
      () {
        final Map<String, dynamic> coreSettings = UmbrellaCore.settingsJson(
          tun: true,
          systemProxy: false,
          port: 12334,
          includeFilterRuleSets: true,
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
            'filter-adult.srs': 'data/filter-adult.srs',
            'filter-gambling.srs': 'data/filter-gambling.srs',
            'filter-ads.srs': 'data/filter-ads.srs',
            'filter-youtube-ads.srs': 'data/filter-youtube-ads.srs',
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
              rs['path'] == 'data/filter-adult.srs'),
          isTrue,
        );
        expect(
          ruleSets.any((Map<String, dynamic> rs) =>
              rs['tag'] == 'filter-gambling' &&
              rs['type'] == 'local' &&
              rs['path'] == 'data/filter-gambling.srs'),
          isTrue,
        );
        expect(
          ruleSets.any((Map<String, dynamic> rs) =>
              rs['tag'] == 'filter-ads' &&
              rs['type'] == 'local' &&
              rs['path'] == 'data/filter-ads.srs'),
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

    test('ClashApi.parseCoreLogLine extracts blocked hosts and DNS rejections', () {
      final CoreLogEntry? conn = ClashApi.parseCoreLogLine(
        jsonEncode(<String, String>{
          'type': 'info',
          'payload': '[7741 0ms] inbound/tun[tun-in]: connection to pornhub.com:443',
        }),
      );
      expect(conn, isNotNull);
      expect(conn!.connectionTag, '7741');
      expect(conn.host, 'pornhub.com');
      expect(conn.port, 443);
      expect(conn.isBlockedEvent, isFalse);

      final CoreLogEntry? rej = ClashApi.parseCoreLogLine(
        jsonEncode(<String, String>{
          'type': 'info',
          'payload': '[7741 1ms] router: match[1] rule[umbrella-filter-adult] -> reject',
        }),
      );
      expect(rej, isNotNull);
      expect(rej!.connectionTag, '7741');
      expect(rej.isBlockedEvent, isTrue);
      expect(rej.matchedRuleHint, 'adult');

      final CoreLogEntry? dns = ClashApi.parseCoreLogLine(
        jsonEncode(<String, String>{
          'type': 'debug',
          'payload': '[99 0ms] dns: rejected A xvideos.com.',
        }),
      );
      expect(dns, isNotNull);
      expect(dns!.isDnsRejection, isTrue);
      expect(dns.isBlockedEvent, isTrue);
      expect(dns.host, 'xvideos.com');
    });

    test(
      'VpnController.openBlockedPreviewPage launches local Umbrella browser block URL cleanly',
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
            categories: <String>['adult'],
          ),
        );
        Uri? launchedUri;
        String launchedTitle = '';
        vpn.onLaunchBlockedPage = (
          Uri uri, {
          required String title,
          required String body,
        }) async {
          launchedUri = uri;
          launchedTitle = title;
          return true;
        };

        final bool ok = await vpn.openBlockedPreviewPage();
        expect(ok, isTrue);
        expect(launchedUri, isNotNull);
        expect(launchedUri!.host, '127.0.0.1');
        expect(launchedUri!.path, '/blocked');
        expect(launchedTitle, contains('سپر کنترل محتوای آمبرلا'));
        expect(vpn.contentBlockUiPort, greaterThan(0));

        // درخواست favicon نباید HTML صفحه مسدودی را دوباره رندر کند و font-display باید block باشد.
        Future<({int statusCode, String head, String body})> rawLoopbackGet(
          Uri uri,
        ) async {
          final Socket sock =
              await Socket.connect(InternetAddress.loopbackIPv4, uri.port);
          try {
            final String pq =
                uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
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
          } finally {
            await sock.close();
          }
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

        // موج هم زمان HTTPS CONNECT + زیردامنه ها + لاگ Clash + DNS reject
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

        // رویداد مستقیم HTTP 403 (پورت 80) نباید پس از لاگ DNS/Clash تب جدید باز کند.
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
      'بهینه سازی سرعت اتصال و اسکن امنیتی ویندوز و رشته پس زمینه بومی رعایت شده است',
      () async {
        final String scannerH = File(
          'packages/umbrella_native/windows/security_scanner.h',
        ).readAsStringSync();
        expect(scannerH, contains('ScanDeviceSecurity(bool quick = false)'));

        final String scannerCpp = File(
          'packages/umbrella_native/windows/security_scanner.cpp',
        ).readAsStringSync();
        expect(scannerCpp, contains('g_clean_file_cache'));
        expect(scannerCpp, contains('g_proc_version_cache'));
        expect(scannerCpp, contains('ReadFileHeadAndTailBytes'));
        expect(scannerCpp, contains('HasValidImageMagic'));
        expect(scannerCpp, contains('InvalidateCleanFileCache'));
        expect(scannerCpp, contains('CandidateScanDirectories(bool quick)'));
        expect(scannerCpp, contains('amsi.ScanFile'));

        final String sysOpsCpp = File(
          'packages/umbrella_native/windows/system_ops.cpp',
        ).readAsStringSync();
        expect(sysOpsCpp, contains('ListRunningCores'));

        final String pluginCpp = File(
          'packages/umbrella_native/windows/umbrella_native_plugin.cpp',
        ).readAsStringSync();
        expect(pluginCpp, contains('RunOffUiThread'));
        expect(pluginCpp, contains('"quick"'));

        final String nativeDart = File('lib/platform/native.dart').readAsStringSync();
        expect(nativeDart, contains('quickScanDeviceSecurity'));
        expect(nativeDart, contains('if (raw != null) {'));

        final String vpnCtrl = File('lib/vpn/vpn_controller.dart').readAsStringSync();
        expect(vpnCtrl, contains('_prewarmProcesses'));
        expect(vpnCtrl, contains('Future<void> _terminateForeignCores()'));
        expect(vpnCtrl, contains('} on Object {'));

        final String corePing = File('lib/vpn/core_ping.dart').readAsStringSync();
        expect(corePing, contains('Future.wait('));

        // quickScanDeviceSecurity safely yields null for mock/subclassed NativeBridge instances.
        final _FakeNative mockNative = _FakeNative();
        expect(await NativeBridge.quickScanDeviceSecurity(mockNative), isNull);

        // Concurrent idle VpnController disposals must not race on reserved ports or probe native port holders.
        final VpnController idleA = VpnController(
          native: mockNative,
          ipService: IpService(),
          sound: _FakeSound(),
          tray: TrayService(mockNative),
          provisioner: CoreProvisioner(),
          settings: const AppSettings(),
        );
        final VpnController idleB = VpnController(
          native: mockNative,
          ipService: IpService(),
          sound: _FakeSound(),
          tray: TrayService(mockNative),
          provisioner: CoreProvisioner(),
          settings: const AppSettings(),
        );
        idleA.dispose();
        idleB.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(mockNative.portLookupCalls, 0);
      },
    );

    test(
      'auto-close conflicting VPNs runs before securityGuard on Windows connect and wires native RAS/service/process termination contracts',
      () async {
        final String sysOpsH = File(
          'packages/umbrella_native/windows/system_ops.h',
        ).readAsStringSync();
        expect(sysOpsH, contains('TerminateForeignVpns'));

        final String sysOpsCpp = File(
          'packages/umbrella_native/windows/system_ops.cpp',
        ).readAsStringSync();
        expect(sysOpsCpp, contains('int SystemOps::TerminateForeignVpns('));
        expect(sysOpsCpp, contains('RasEnumConnectionsW'));
        expect(sysOpsCpp, contains('RasHangUpW'));
        expect(sysOpsCpp, contains('SERVICE_CONTROL_STOP'));
        expect(sysOpsCpp, contains('CollectUmbrellaExcludeDirsLower'));

        final String pluginCpp = File(
          'packages/umbrella_native/windows/umbrella_native_plugin.cpp',
        ).readAsStringSync();
        expect(pluginCpp, contains('"terminateForeignVpns"'));

        final String mainDart = File('lib/main.dart').readAsStringSync();
        expect(mainDart, contains('await native.closeConflictingVpns('));
        expect(mainDart, contains("t.key != 'vpn:active_other_tunnel'"));
        expect(mainDart, contains('unawaited(security.scanNow(silent: true));'));

        final _FakeNative native = _FakeNative()..closedOnNextCall = 3;
        native.scanResult = const SecurityScanResult(
          clean: false,
          scannedProcesses: 42,
          threats: <SecurityThreat>[
            SecurityThreat(
              key: 'vpn:active_other_tunnel',
              name: 'تونل وی پی ان فعال دیگر در سیستم',
              category: 'conflicting_vpn',
              severity: 'high',
              target: 'Windows VPN Tunnel',
              detail: 'یک فیلترشکن دیگر فعال است',
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
          scannedProcesses: 42,
          threats: <SecurityThreat>[
            SecurityThreat(
              key: 'vpn:psiphon',
              name: 'Psiphon (فیلترشکن ناسازگار)',
              category: 'conflicting_vpn',
              severity: 'high',
              target: 'psiphon3.exe',
              detail: 'Psiphon فعال است.',
              processName: 'psiphon3.exe',
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
      'always-on AdBlock, native filename hardening, and live security-state sync work end-to-end',
      () async {
        final String scannerCpp = File(
          'packages/umbrella_native/windows/security_scanner.cpp',
        ).readAsStringSync();
        expect(
          scannerCpp,
          isNot(contains('if (IsUmbrellaSafeBinary(full) || lower_fn.find("umbrella") != std::string::npos)')),
        );
        expect(
          scannerCpp,
          isNot(contains('if (lower_name.find("umbrella") != std::string::npos) return false;')),
        );

        final String settingsUi = File(
          'lib/ui/pages/settings_page.dart',
        ).readAsStringSync();
        expect(settingsUi, isNot(contains('settings.setBlockAds(')));
        expect(settingsUi, contains('همیشه فعال'));

        final Map<String, dynamic> coreNoFilter = UmbrellaCore.settingsJson(
          tun: false,
          systemProxy: true,
          port: 12334,
          networkSettings: const AppSettings(blockAds: false),
          contentFilter: FilterSettings.empty,
        );
        expect(coreNoFilter['block-ads'], isTrue);

        final Map<String, dynamic> runtimeNoBlockPage = <String, dynamic>{
          'route': <String, dynamic>{
            'rules': <dynamic>[
              <String, dynamic>{'action': 'sniff'},
            ],
          },
          'dns': <String, dynamic>{'rules': <dynamic>[]},
        };
        RuntimeConfig.finalize(
          runtimeNoBlockPage,
          profileTags: const <String>{},
          coreSettings: coreNoFilter,
          blockPagePort: 0,
        );
        expect(
          jsonEncode(runtimeNoBlockPage['route']),
          allOf(contains('grabify.link'), contains('"reject"')),
        );

        final List<Map<String, dynamic>> alertPayloads =
            <Map<String, dynamic>>[];
        final List<Map<String, dynamic>> heartbeatPayloads =
            <Map<String, dynamic>>[];
        final _FakeNative native = _FakeNative();
        native.scanResult = const SecurityScanResult(
          clean: true,
          scannedProcesses: 51,
          scannedApps: 22,
          scannedFiles: 340,
          scannedAtMs: 1760000123456,
        );
        final GatewayClient gateway = GatewayClient(
          client: MockClient((http.Request req) async {
            final Map<String, dynamic> body =
                jsonDecode(req.body) as Map<String, dynamic>;
            if (req.url.path.endsWith('/app/security-alert')) {
              alertPayloads.add(body);
            } else if (req.url.path.endsWith('/auth/device')) {
              heartbeatPayloads.add(body);
            }
            return http.Response('{"ok":true}', 200);
          }),
        );
        final _SignedAuth auth = _SignedAuth(
          native: native,
          gateway: gateway,
          store: LocalStore.instance,
        );
        final SecurityScannerController sec = SecurityScannerController(
          native: native,
          auth: auth,
        );
        auth.securityStateProvider = sec.buildSecurityStatePayload;
        addTearDown(() {
          sec.dispose();
          auth.dispose();
        });

        await sec.scanNow(silent: true);
        expect(alertPayloads, hasLength(1));
        expect(alertPayloads.single['security_status'], 'safe');
        expect(alertPayloads.single['scanned_files'], 340);
        expect(alertPayloads.single['scanned_apps'], 22);
        expect(alertPayloads.single['scanned_processes'], 51);
        expect(alertPayloads.single['scanned_at_ms'], 1760000123456);

        await gateway.heartbeat(
          token: 'tok-sec-1',
          deviceId: 'dev-win-sec-1',
          securityStatus: sec.buildSecurityStatePayload()['security_status']
              as String?,
          scannedAtMs:
              sec.buildSecurityStatePayload()['scanned_at_ms'] as int?,
          scannedFiles:
              sec.buildSecurityStatePayload()['scanned_files'] as int?,
          scannedApps: sec.buildSecurityStatePayload()['scanned_apps'] as int?,
          scannedProcesses:
              sec.buildSecurityStatePayload()['scanned_processes'] as int?,
        );
        expect(heartbeatPayloads, hasLength(1));
        expect(heartbeatPayloads.single['security_status'], 'safe');
        expect(heartbeatPayloads.single['scanned_files'], 340);

        final String cpp = File(
          'packages/umbrella_native/windows/security_scanner.cpp',
        ).readAsStringSync();
        expect(cpp, contains('InspectImagePolyglotW'));
        expect(cpp, contains('HasSafeMotionPhotoTrailer'));
        expect(cpp, contains('InspectPdfPayload'));
        expect(cpp, contains('ComputeShannonEntropy'));
        expect(cpp, contains('ReadRemoteProcessCommandLine'));
        expect(cpp, contains('IsSuspiciousLolbinCommandLine'));
        expect(cpp, contains('RunMRU'));
        expect(cpp, contains('xworm'));
        expect(cpp, contains('lummastealer'));
        expect(cpp, contains('utf16_view'));
        expect(cpp, contains('NormalizeObfuscatedScript'));
        expect(cpp, contains('dl:webp_eof:'));
        expect(cpp, contains('bool deterministic = false;'));
        expect(cpp, contains('FOLDERID_RoamingAppData'));
        expect(cpp, isNot(contains('lower.find("umbrella") != std::string::npos')));
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
            ContentBlockServer.classifyBlockedHost(h, filter: filter),
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
            ContentBlockServer.classifyBlockedHost(h, filter: filter),
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
          logFile: 'core.log',
          contentFilter: filter,
          networkSettings: const AppSettings(blockAds: true),
        );
        final Map<String, dynamic> compiled = <String, dynamic>{
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

  group('اعلان تبلیغاتی و اشتراک رایگان ۳ گیگابایتی ویندوز', () {
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
        baseUrl: 'https://armin-soft.ir/Umbrella-Vpn/',
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

    test('زمان بندی نوار تبلیغاتی، ارسال بالون سینی ویندوز و ذخیره وضعیت بسته شدن', () async {
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
        baseUrl: 'https://armin-soft.ir/Umbrella-Vpn/',
        client: mockHttp,
        enableNativeTransport: false,
      );
      final TrayService tray = TrayService(native);
      await tray.init();
      native.trayBalloons.clear();
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
      expect(native.trayBalloons, hasLength(1));
      expect(native.trayBalloons.single.title, 'کمپین ویژه بهار');
      expect(tray.consumeRecentPromoActionUrl(), 'https://armin-soft.ir/spring');
      expect(tray.consumeRecentPromoActionUrl(), isNull);

      await auth.syncAnnouncement();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(native.trayBalloons, hasLength(1));

      final DateTime now = DateTime.now().toUtc();
      await auth.dismissPromoBanner(now: now);
      expect(auth.shouldShowPromoBanner(now: now), isFalse);
      expect(
        auth.shouldShowPromoBanner(now: now.add(const Duration(hours: 25))),
        isTrue,
      );
    });

    testWidgets('PromoBannerBar و PromoAnnouncementDialog روی دسکتاپ ویندوز بی نقص رندر می شوند', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 720));
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
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: <Widget>[
                    PromoBannerBar(
                      promo: promo,
                      imageBytes: validPng,
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
}

extension<T> on T {
  R let<R>(R Function(T value) block) => block(this);
}
