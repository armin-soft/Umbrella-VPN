import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbrella_vpn/core/storage.dart';
import 'package:umbrella_vpn/core/theme.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/platform/services.dart';
import 'package:umbrella_vpn/state/auth_controller.dart';
import 'package:umbrella_vpn/state/settings_controller.dart';
import 'package:umbrella_vpn/state/toast_controller.dart';
import 'package:umbrella_vpn/ui/widgets/content_control.dart';
import 'package:umbrella_vpn/vpn/runtime_config.dart';
import 'package:umbrella_vpn/vpn/speed_test.dart';
import 'package:umbrella_vpn/vpn/umbrella_core.dart';
import 'package:umbrella_vpn/vpn/verified_probe.dart';

class _SilentSound implements SoundService {
  @override
  bool enabled = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeWindow implements WindowService {
  @override
  bool closeToTray = true;

  @override
  bool notificationsEnabled = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeAuthController extends AuthController {
  _FakeAuthController({required FilterSettings initialFilter})
      : _currentFilter = initialFilter,
        super(native: NativeBridge());

  FilterSettings _currentFilter;
  int saveCalls = 0;

  @override
  bool get signedIn => true;

  @override
  FilterSettings get filter => _currentFilter;

  @override
  bool get savingFilter => false;

  @override
  String get error => '';

  @override
  Future<bool> syncFilter({bool silent = true}) async => true;

  @override
  Future<bool> saveFilter(FilterSettings next) async {
    saveCalls++;
    _currentFilter = next;
    notifyListeners();
    return true;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.instance.init();
  });

  group('FilterSettings — نرمال سازی و مدیریت دامنه های سفارشی', () {
    test('دامنه، نشانی کامل، پورت، مسیر، www و وایلدکارد به دامنه خالص تبدیل می شوند', () {
      expect(FilterSettings.normalizeDomainSuffix('Example.COM'), 'example.com');
      expect(
        FilterSettings.normalizeDomainSuffix('https://www.Bad-Site.org:8443/path?x=1#top'),
        'bad-site.org',
      );
      expect(FilterSettings.normalizeDomainSuffix('*.Sub.Tracker.NET.'), 'sub.tracker.net');
      expect(FilterSettings.normalizeDomainSuffix('.casino99.io'), 'casino99.io');
      expect(FilterSettings.normalizeDomainSuffix('http://user:pw@bet123.com/login'), 'bet123.com');
      expect(FilterSettings.normalizeDomainSuffix('site۱۲۳.com'), 'site123.com');
    });

    test('ورودی های نامعتبر، آی پی، لوکال هاست و درگاه های آمبرلا رد می شوند', () {
      for (final String bad in <String>[
        '',
        '   ',
        'localhost',
        'sub.localhost',
        'router.local',
        'printer.lan',
        '192.168.1.1',
        '1.1.1.1',
        '2001:db8::1',
        'com',
        '-bad.com',
        'bad-.com',
        'bad_host.com',
        'bad..com',
        'bad.123',
        '*',
        'armin-soft.ir',
        'api.armin-soft.ir',
        'soft98.site',
        'gw.soft98.site',
      ]) {
        expect(
          FilterSettings.normalizeDomainSuffix(bad),
          isNull,
          reason: 'Expected "$bad" to be rejected',
        );
      }
    });

    test('پارس گروهی، افزودن، حذف، پاک کردن همه و سقف ۲۰۰ دامنه دقیق کار می کند', () {
      final ({List<String> valid, List<String> invalid}) parsed =
          FilterSettings.parseDomainInputs(
        'https://www.Foo.com/a, bar.org\n*.baz.net، 192.168.1.1; foo.com; armin-soft.ir',
      );
      expect(parsed.valid, <String>['foo.com', 'bar.org', 'baz.net']);
      expect(parsed.invalid, hasLength(2));

      FilterSettings state = FilterSettings.empty;
      final addRes = state.addCustomDomains(parsed.valid);
      state = addRes.settings;
      expect(state.enabled, isTrue);
      expect(state.hasActiveRules, isTrue);
      expect(addRes.added, <String>['foo.com', 'bar.org', 'baz.net']);

      final dupRes = state.addCustomDomains(<String>['WWW.FOO.COM', 'qux.io']);
      state = dupRes.settings;
      expect(dupRes.added, <String>['qux.io']);
      expect(dupRes.duplicates, <String>['foo.com']);

      state = state.removeCustomDomain('https://bar.org/');
      expect(state.normalizedCustomDomains, <String>['foo.com', 'baz.net', 'qux.io']);
      expect(state.enabled, isTrue);

      // حذف همه دامنه ها در نبود دسته فعال، کنترل محتوا را خودکار خاموش می کند.
      final FilterSettings cleared = state.clearCustomDomains();
      expect(cleared.normalizedCustomDomains, isEmpty);
      expect(cleared.enabled, isFalse);

      // حذف همه دامنه ها در حضور دسته فعال، دسته را روشن نگه می دارد.
      final FilterSettings withCat = state.toggleCategory('adult').clearCustomDomains();
      expect(withCat.enabled, isTrue);
      expect(withCat.activeBotCategories, <String>['adult']);
      expect(withCat.normalizedCustomDomains, isEmpty);

      // سقف ۲۰۰ دامنه
      final List<String> many = List<String>.generate(215, (int i) => 'site-$i.example');
      final capRes = FilterSettings.empty.addCustomDomains(many);
      expect(capRes.added, hasLength(FilterSettings.maxCustomDomains));
      expect(capRes.skippedLimit, hasLength(15));
    });

    test('تغییر دامنه سفارشی یا دسته امضای اثرگذاری (effectSignature) را تغییر می دهد', () {
      const FilterSettings a = FilterSettings(
        enabled: true,
        categories: <String>['adult'],
        customDomains: <String>['one.test'],
      );
      const FilterSettings aSame = FilterSettings(
        enabled: true,
        categories: <String>['adult'],
        customDomains: <String>['https://www.ONE.test/'],
      );
      const FilterSettings b = FilterSettings(
        enabled: true,
        categories: <String>['adult'],
        customDomains: <String>['one.test', 'two.test'],
      );
      expect(a.effectSignature, aSame.effectSignature);
      expect(a.effectSignature, isNot(b.effectSignature));
    });
  });

  group('UmbrellaCore — کنترل محتوای دولایه و هماهنگی با مسیریابی', () {
    test('مسدودسازی فوری بزرگسالان، قمار، تبلیغات، دوستیابی و دامنه سفارشی بدون خطای مثبت کاذب', () {
      const FilterSettings all = FilterSettings(
        enabled: true,
        categories: <String>['adult', 'gambling', 'ads', 'dating'],
        customDomains: <String>['custom-blocked.org'],
      );

      for (final String blocked in <String>[
        'pornhub.com',
        'cdn.xvideos.com',
        'onlyfans.com',
        'chaturbate.com',
        'sexvid.example',
        'hentaihaven.example',
        '1xbet.com',
        'mirror.bet365.com',
        'stake.com',
        'takbet.com',
        'hazarat.com',
        'vip-casino.example',
        'shartbandi-vip.example',
        'doubleclick.net',
        'pagead2.googlesyndication.com',
        'yektanet.com',
        'tapsell.ir',
        'ads.yahoo.com',
        'adserver.example.net',
        'tinder.com',
        'api.bumble.com',
        'badoo.com',
        'grindr.com',
        'custom-blocked.org',
        'deep.sub.custom-blocked.org',
      ]) {
        expect(
          UmbrellaCore.matchesContentFilter(all, blocked),
          isTrue,
          reason: 'Expected "$blocked" to be blocked',
        );
      }

      // سایت های سالم و پرکاربرد هرگز نباید به اشتباه مسدود شوند (صفر مثبت کاذب).
      for (final String safe in <String>[
        'google.com',
        'www.google.com',
        'github.com',
        'cloudflare.com',
        'telegram.org',
        'wikipedia.org',
        'microsoft.com',
        'update.microsoft.com',
        'alphabet.com',
        'bethesda.net',
        'adsbexchange.com',
        'uploads.github.com',
        'downloads.sourceforge.net',
        'scunthorpe.gov.uk',
        'sussex.ac.uk',
        'essex.gov.uk',
        'armin-soft.ir',
        'digikala.com',
        'aparat.com',
        'shaparak.ir',
      ]) {
        expect(
          UmbrellaCore.matchesContentFilter(all, safe),
          isFalse,
          reason: 'Expected "$safe" NOT to be blocked (false positive)',
        );
      }
    });

    test('مجموعه قوانین رسمی geosite همراه با blockAds و routingRegion حفظ و بدون تکرار تولید می شوند', () {
      final Map<String, dynamic> out = UmbrellaCore.settingsJson(
        tun: true,
        systemProxy: false,
        port: 12334,
        logFile: 'core.log',
        networkSettings: const AppSettings(
          blockAds: true,
          routingRegion: RoutingRegion.ir,
          appRoutes: <AppRouteRule>[
            AppRouteRule(process: 'game.exe', action: AppRouteAction.direct),
          ],
        ),
        contentFilter: const FilterSettings(
          enabled: true,
          categories: <String>['adult', 'gambling'],
          customDomains: <String>['blocked-user.site'],
        ),
      );

      final List<Map<String, dynamic>> rules =
          ((out['route-rule'] as Map<String, dynamic>)['rules'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
      // adult + gambling + customDomains + game.exe + blockAds + region(ir) = 6
      expect(rules, hasLength(6));
      expect(rules[0]['rule_set'], contains(contains('geosite-category-porn.srs')));
      expect(rules[1]['rule_set'], contains(contains('geosite-category-betting-ru.srs')));
      expect(rules[2]['domain_suffix'], <String>['blocked-user.site']);
      expect(rules[3]['process_name'], <String>['game.exe']);
      expect(rules[3]['outbound'], 'direct');
      expect(rules[4]['outbound'], 'block');
      expect(rules[4]['rule_set'], contains(contains('geosite-category-ads-all.srs')));
      expect(rules[5]['outbound'], 'direct');
      expect(rules[5]['rule_set'], contains(contains('geosite-ir.srs')));
      expect(rules[5]['rule_set'], contains(contains('geoip-ir.srs')));

      // وقتی دسته ads در کنترل محتوا روشن است، blockAds دوباره تکرار نمی شود.
      final Map<String, dynamic> dedup = UmbrellaCore.settingsJson(
        tun: true,
        systemProxy: false,
        port: 12334,
        logFile: 'core.log',
        networkSettings: const AppSettings(blockAds: true),
        contentFilter: const FilterSettings(
          enabled: true,
          categories: <String>['ads'],
        ),
      );
      final List<dynamic> dedupRules =
          (dedup['route-rule'] as Map<String, dynamic>)['rules'] as List<dynamic>;
      expect(dedupRules, hasLength(1));
    });
  });

  group('RuntimeConfig.finalize — تکمیل تمام تنظیمات واقعی در پیکربندی sing-box', () {
    Map<String, dynamic> sampleCompiled() => <String, dynamic>{
          'route': <String, dynamic>{
            'find_process': false,
            'rules': <Map<String, dynamic>>[
              <String, dynamic>{'action': 'sniff'},
              <String, dynamic>{'protocol': 'dns', 'action': 'hijack-dns'},
              <String, dynamic>{
                'domain_suffix': <String>['blocked.test'],
                'action': 'reject',
              },
              <String, dynamic>{
                'process_name': <String>['chrome.exe'],
                'outbound': 'direct §hide§',
              },
            ],
          },
          'outbounds': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'selector',
              'tag': 'select',
              'outbounds': <String>['lowest', 'balance', 'plain-tls', 'ws-tls', 'reality-node'],
              'default': 'balance',
            },
            <String, dynamic>{
              'type': 'balancer',
              'tag': 'balance',
              'outbounds': <String>['plain-tls', 'ws-tls', 'reality-node'],
              'strategy': 'sticky-sessions',
            },
            <String, dynamic>{
              'type': 'vless',
              'tag': 'plain-tls',
              'server': '198.51.100.1',
              'server_port': 443,
              'tls': <String, dynamic>{
                'enabled': true,
                'server_name': 'plain.example.com',
                'utls': <String, dynamic>{'enabled': true, 'fingerprint': 'randomized'},
              },
            },
            <String, dynamic>{
              'type': 'trojan',
              'tag': 'ws-tls',
              'server': '198.51.100.2',
              'server_port': 443,
              'transport': <String, dynamic>{'type': 'ws', 'path': '/ws'},
              'tls': <String, dynamic>{
                'enabled': true,
                'server_name': 'ws.example.com',
                'utls': <String, dynamic>{'enabled': true, 'fingerprint': 'firefox'},
              },
            },
            <String, dynamic>{
              'type': 'vless',
              'tag': 'reality-node',
              'server': '198.51.100.3',
              'server_port': 443,
              'tls': <String, dynamic>{
                'enabled': true,
                'server_name': 'www.microsoft.com',
                'reality': <String, dynamic>{'enabled': true, 'public_key': 'abc'},
                'utls': <String, dynamic>{'enabled': true, 'fingerprint': 'chrome'},
              },
            },
            <String, dynamic>{'type': 'direct', 'tag': 'direct §hide§'},
          ],
          'experimental': <String, dynamic>{
            'monitoring': <String, dynamic>{
              'workers': 4,
            },
            'clash_api': <String, dynamic>{
              'external_controller': '127.0.0.1:16756',
              'secret': 'abc',
            },
          },
        };

    test('find_process، bypass-lan، resolve-destination، TLS tricks و sticky TTL همگی اعمال می شوند', () {
      final Map<String, dynamic> coreSettings = UmbrellaCore.settingsJson(
        tun: true,
        systemProxy: false,
        port: 12334,
        logFile: 'core.log',
        networkSettings: const AppSettings(
          bypassLan: true,
          resolveDestination: true,
          blockIpv6: true,
          selectionMode: SelectionMode.stickySession,
          stickyMinutes: 30,
          appRoutes: <AppRouteRule>[
            AppRouteRule(process: 'chrome.exe', action: AppRouteAction.direct),
          ],
          tlsTricks: TlsTricksSettings(
            enableFragment: true,
            fragmentSize: '12-28',
            fragmentSleep: '2-6',
            mixedSniCase: true,
            enablePadding: true,
            paddingSize: '1200-1500',
          ),
        ),
        contentFilter: const FilterSettings(
          enabled: true,
          customDomains: <String>['blocked.test'],
        ),
      );

      final Map<String, dynamic> patched = sampleCompiled();
      RuntimeConfig.finalize(
        patched,
        profileTags: const <String>{'plain-tls', 'ws-tls', 'reality-node'},
        coreSettings: coreSettings,
        stickyMinutes: 30,
      );

      final Map<String, dynamic> route = patched['route'] as Map<String, dynamic>;
      expect(route['find_process'], isTrue);

      final List<Map<String, dynamic>> rules =
          (route['rules'] as List<dynamic>).cast<Map<String, dynamic>>();
      final int hijackIdx = rules.indexWhere((Map<String, dynamic> r) => r['action'] == 'hijack-dns');
      final int lanIdx = rules.indexWhere((Map<String, dynamic> r) => r['ip_is_private'] == true);
      final int resolveIdx = rules.indexWhere((Map<String, dynamic> r) => r['action'] == 'resolve');
      final int blockIdx = rules.indexWhere((Map<String, dynamic> r) => r['action'] == 'reject');
      // ترتیب دقیق در مسیر route:
      // sniff -> hijack-dns -> resolve (برای فعال شدن قوانین IP و شبکه محلی)
      // -> قوانین مسدودسازی و برنامه ها -> bypass-lan (ip_is_private -> direct)
      expect(resolveIdx, greaterThan(hijackIdx));
      expect(lanIdx, greaterThan(hijackIdx));
      expect(blockIdx, greaterThan(hijackIdx));
      expect(lanIdx, greaterThan(resolveIdx));
      expect(rules[lanIdx]['outbound'], 'direct §hide§');
      expect(rules[resolveIdx]['strategy'], 'ipv4_only');

      final List<Map<String, dynamic>> outbounds =
          (patched['outbounds'] as List<dynamic>).cast<Map<String, dynamic>>();
      final Map<String, dynamic> balancer =
          outbounds.firstWhere((Map<String, dynamic> o) => o['tag'] == 'balance');
      expect(balancer['ttl'], '30m');

      final Map<String, dynamic> plain =
          outbounds.firstWhere((Map<String, dynamic> o) => o['tag'] == 'plain-tls');
      expect(plain['tls_fragment'], <String, dynamic>{
        'enabled': true,
        'size': '12-28',
        'sleep': '2-6',
      });
      expect(plain['tcp_fast_open'], isFalse);
      final Map<String, dynamic> plainTls = plain['tls'] as Map<String, dynamic>;
      expect(plainTls['tls_tricks'], <String, dynamic>{
        'mixedcase_sni': true,
        'padding_mode': 'random',
        'padding_size': '1200-1500',
      });
      expect((plainTls['utls'] as Map<String, dynamic>)['fingerprint'], 'chrome');

      final Map<String, dynamic> ws =
          outbounds.firstWhere((Map<String, dynamic> o) => o['tag'] == 'ws-tls');
      final Map<String, dynamic> wsTls = ws['tls'] as Map<String, dynamic>;
      expect((wsTls['tls_tricks'] as Map<String, dynamic>)['padding_mode'], 'random');
      expect((wsTls['utls'] as Map<String, dynamic>)['fingerprint'], 'firefox');

      // Reality و direct هرگز دست کاری نمی شوند.
      final Map<String, dynamic> reality =
          outbounds.firstWhere((Map<String, dynamic> o) => o['tag'] == 'reality-node');
      expect(reality.containsKey('tls_fragment'), isFalse);
      expect((reality['tls'] as Map<String, dynamic>).containsKey('tls_tricks'), isFalse);
    });

    test('وقتی bypass-lan خاموش است قانون شبکه محلی تزریق نمی شود و سقف padding تا ۱۶۰۰۰ معتبر است', () {
      final Map<String, dynamic> coreSettings = UmbrellaCore.settingsJson(
        tun: true,
        systemProxy: false,
        port: 12334,
        logFile: 'core.log',
        networkSettings: const AppSettings(
          bypassLan: false,
          resolveDestination: false,
          tlsTricks: TlsTricksSettings(
            enablePadding: true,
            paddingSize: '20000-30000',
          ),
        ),
        contentFilter: const FilterSettings(
          enabled: true,
          customDomains: <String>['blocked.test'],
        ),
      );
      expect(
        (coreSettings['tls-tricks'] as Map<String, dynamic>)['padding-size'],
        '1200-1500',
      );
      expect(
        TlsTricksSettings.isValidRange(
          '۱۵۰۰-۱۶۰۰۰',
          min: 1,
          max: TlsTricksSettings.maxPaddingSize,
        ),
        isTrue,
      );
      expect(
        TlsTricksSettings.isValidRange(
          '1500-16001',
          min: 1,
          max: TlsTricksSettings.maxPaddingSize,
        ),
        isFalse,
      );

      final Map<String, dynamic> patched = sampleCompiled();
      RuntimeConfig.finalize(
        patched,
        profileTags: const <String>{'plain-tls', 'ws-tls', 'reality-node'},
        coreSettings: coreSettings,
      );
      final List<Map<String, dynamic>> rules =
          ((patched['route'] as Map<String, dynamic>)['rules'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
      expect(rules.any((Map<String, dynamic> r) => r['ip_is_private'] == true), isFalse);
      expect(rules.any((Map<String, dynamic> r) => r['action'] == 'resolve'), isFalse);
    });
  });

  group('پروب ها و تست سرعت — احراز هویت پروکسی محلی و حالت تونل بدون پروکسی', () {
    test('VerifiedProbe هدر احراز هویت پروکسی محلی را ارسال می کند', () async {
      final HttpOverrides? previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      final HttpServer proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final String expectedAuth =
          'Basic ${base64Encode(utf8.encode('hiddify:Secret-123'))}';
      int authedRequests = 0;
      proxy.listen((HttpRequest req) async {
        final String? header =
            req.headers.value(HttpHeaders.proxyAuthorizationHeader);
        if (header != expectedAuth) {
          req.response.statusCode = HttpStatus.proxyAuthenticationRequired;
          req.response.headers
              .set(HttpHeaders.proxyAuthenticateHeader, 'Basic realm="umbrella"');
          await req.response.close();
          return;
        }
        authedRequests++;
        req.response.statusCode = HttpStatus.noContent;
        await req.response.close();
      });

      try {
        final Map<String, String> targets = <String, String>{
          'http://127.0.0.1:${proxy.port}/generate_204': '',
        };
        // بدون رمز باید رد شود.
        expect(
          await VerifiedProbe.check(
            proxyPort: proxy.port,
            targets: targets,
            timeout: const Duration(seconds: 2),
          ),
          isFalse,
        );
        // با رمز صحیح باید موفق شود.
        expect(
          await VerifiedProbe.check(
            proxyPort: proxy.port,
            proxyUser: 'hiddify',
            proxyPassword: 'Secret-123',
            targets: targets,
            timeout: const Duration(seconds: 2),
          ),
          isTrue,
        );
        expect(authedRequests, 1);
      } finally {
        await proxy.close(force: true);
        HttpOverrides.global = previousOverrides;
      }
    });

    test('SpeedTestRunner بدون پروکسی محلی فقط با allowDirectTunnel صریح اجرا می شود', () async {
      final HttpOverrides? previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      final SpeedTestRunner denied = SpeedTestRunner();
      await expectLater(
        () => denied.run(proxyPort: 0),
        throwsA(isA<ArgumentError>()),
      );

      final HttpServer server =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest req) async {
        if (req.uri.path == '/down') {
          req.response.statusCode = HttpStatus.ok;
          req.response.add(List<int>.filled(4096, 65));
          await req.response.close();
          return;
        }
        await req.drain<void>();
        req.response.statusCode = HttpStatus.ok;
        await req.response.close();
      });
      try {
        final SpeedTestResult ok = await SpeedTestRunner().run(
          proxyPort: 0,
          allowDirectTunnel: true,
          downloadEndpoint: Uri.parse('http://127.0.0.1:${server.port}/down'),
          uploadEndpoint: Uri.parse('http://127.0.0.1:${server.port}/up'),
          downloadLimit: 4096,
          uploadLimit: 2048,
          timeout: const Duration(seconds: 4),
        );
        expect(ok.download.bytes, 4096);
        expect(ok.upload.bytes, 2048);
      } finally {
        await server.close(force: true);
        HttpOverrides.global = previousOverrides;
      }
    });
  });

  group('SettingsController — بازگشت خودکار لاگ debug پس از ۱۰ دقیقه', () {
    test('انتخاب سطح debug به warn برمی گردد و اعلان ها روی پنجره همگام می شود', () async {
      final _FakeWindow window = _FakeWindow();
      final SettingsController ctrl = SettingsController(
        native: NativeBridge(),
        sound: _SilentSound(),
        window: window,
      );
      try {
        await ctrl.setLogLevel('debug');
        expect(ctrl.settings.logLevel, 'debug');
        await ctrl.setLogLevel('warn');
        expect(ctrl.settings.logLevel, 'warn');
        await ctrl.setNotifications(false);
        expect(window.notificationsEnabled, isFalse);
        await ctrl.setNotifications(true);
        expect(window.notificationsEnabled, isTrue);
      } finally {
        ctrl.dispose();
      }
    });
  });

  group('ContentControlCard — ویجت افزودن، حذف و همگام سازی دامنه سفارشی', () {
    testWidgets('افزودن دامنه و نشانی کامل، نمایش خطای نامعتبر، حذف تکی و حذف همه', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final _FakeAuthController auth = _FakeAuthController(
        initialFilter: const FilterSettings(
          enabled: true,
          categories: <String>['adult'],
        ),
      );
      final ToastController toasts = ToastController();

      await tester.pumpWidget(
        MultiProvider(
          providers: <ChangeNotifierProvider<dynamic>>[
            ChangeNotifierProvider<AuthController>.value(value: auth),
            ChangeNotifierProvider<ToastController>.value(value: toasts),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: ContentControlCard(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('کنترل محتوا'), findsOneWidget);
      expect(find.text('دامنه های سفارشی مسدودشده'), findsOneWidget);

      // ورودی نامعتبر باید پیام خطای فارسی نمایش دهد و ذخیره نشود.
      await tester.enterText(
        find.byKey(const ValueKey<String>('content-filter-domain-input')),
        '192.168.1.1',
      );
      await tester.tap(find.byKey(const ValueKey<String>('content-filter-add-domain')));
      await tester.pump();
      expect(auth.saveCalls, 0);
      expect(find.textContaining('دامنه معتبر نیست'), findsOneWidget);

      // افزودن هم زمان دو دامنه (یکی با پروتکل و مسیر)
      await tester.enterText(
        find.byKey(const ValueKey<String>('content-filter-domain-input')),
        'https://www.Example-Bad.com/ads, second-bad.org',
      );
      await tester.tap(find.byKey(const ValueKey<String>('content-filter-add-domain')));
      await tester.pump();
      expect(auth.filter.normalizedCustomDomains, <String>[
        'example-bad.com',
        'second-bad.org',
      ]);
      expect(find.byKey(const ValueKey<String>('custom-domain-example-bad.com')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('custom-domain-second-bad.org')), findsOneWidget);

      // حذف تکی دامنه اول
      await tester.tap(find.byKey(const ValueKey<String>('delete-domain-example-bad.com')));
      await tester.pump();
      expect(auth.filter.normalizedCustomDomains, <String>['second-bad.org']);

      // افزودن دامنه دیگر و حذف همه با دیالوگ تایید
      await tester.enterText(
        find.byKey(const ValueKey<String>('content-filter-domain-input')),
        'third-bad.net',
      );
      await tester.tap(find.byKey(const ValueKey<String>('content-filter-add-domain')));
      await tester.pump();
      expect(auth.filter.normalizedCustomDomains, hasLength(2));

      await tester.tap(find.byKey(const ValueKey<String>('content-filter-clear-domains')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'حذف همه'));
      await tester.pumpAndSettle();
      expect(auth.filter.normalizedCustomDomains, isEmpty);
      expect(auth.filter.activeBotCategories, <String>['adult']);
      expect(auth.filter.enabled, isTrue);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      toasts.dispose();
    });
  });

  test('هیچ کاراکتر نیم فاصله (ZWNJ) در کدهای برنامه ویندوز وجود ندارد', () {
    final Directory dir = Directory('lib');
    for (final FileSystemEntity entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final String content = entity.readAsStringSync();
      expect(
        content.contains('\u200C'),
        isFalse,
        reason: 'Found forbidden ZWNJ in ${entity.path}',
      );
    }
  });
}
