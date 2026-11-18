import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbrella_vpn/core/app_config.dart';
import 'package:umbrella_vpn/core/storage.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/platform/services.dart';
import 'package:umbrella_vpn/vpn/core_runtime.dart';
import 'package:umbrella_vpn/vpn/umbrella_core.dart';

class _StreamingMockClient extends http.BaseClient {
  _StreamingMockClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);
}

void main() {
  group('v1.0.39 — پایان کامل CLI و هسته هنگام خروج', () {
    test('متغیر مالکیت پروسه برای نگهبان لانچر تزریق می شود', () {
      final Map<String, String> env = UmbrellaCore.ownerEnvironment();
      expect(env['UMBRELLA_OWNER_PID'], '$pid');
    });

    test('زنجیره خاموشی در لانچر بومی، افزونه ویندوز، پنجره و پوسته قفل است', () {
      final String launcher =
          File('native/umbrella_launcher.c').readAsStringSync();
      final String systemOps =
          File('packages/umbrella_native/windows/system_ops.cpp')
              .readAsStringSync();
      final String flutterWindow =
          File('windows/runner/flutter_window.cpp').readAsStringSync();
      final String mainDart = File('lib/main.dart').readAsStringSync();
      final String appShell =
          File('lib/ui/shell/app_shell.dart').readAsStringSync();
      final String exitPage =
          File('lib/ui/pages/exit_page.dart').readAsStringSync();
      final String vpn =
          File('lib/vpn/vpn_controller.dart').readAsStringSync();
      final String cli = File('lib/vpn/cli_session.dart').readAsStringSync();

      expect(launcher, contains('UMBRELLA_OWNER_PID'));
      expect(launcher, contains('owner_watchdog_thread'));
      expect(launcher, contains('clear_stale_loopback_proxy'));
      expect(systemOps, contains('JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE'));
      expect(systemOps, contains('ShutdownOwnedCores'));
      expect(systemOps, contains('AttachPidToCoreJob'));
      expect(flutterWindow, contains('WM_QUERYENDSESSION'));
      expect(flutterWindow, contains('WM_ENDSESSION'));
      expect(flutterWindow, contains('ir.umbrella.app/session'));
      expect(vpn, contains('Future<void> shutdownForExit()'));
      expect(vpn, contains('attachCoreJob'));
      expect(cli, contains("'/T'"));
      expect(mainDart, contains('vpn.shutdownForExit'));
      expect(appShell, contains('vpn.shutdownForExit()'));
      expect(exitPage, contains('vpn.shutdownForExit()'));
    });
  });

  group('v1.0.39 — همگام سازی کامل کنترل محتوا با ربات تلگرام', () {
    test('دقیقاً چهار دسته رسمی ربات تلگرام پشتیبانی و همگام می شوند', () {
      expect(
        FilterSettings.categoryLabels.keys.toList(),
        <String>['adult', 'gambling', 'ads', 'dating'],
      );

      final FilterSettings parsed = FilterSettings.fromJson(<String, dynamic>{
        'enabled': true,
        'categories': <String>['adult', 'social', 'ads', 'unknown', 'dating'],
        'custom_domains': <String>[
          'https://WWW.Example.com/path',
          '*.tracker.net.',
          '192.168.1.1',
          'invalid',
        ],
        'updated_at': '2026-11-17T00:00:00Z',
        'updated_by': 'telegram',
      });
      expect(parsed.enabled, isTrue);
      expect(parsed.categories, <String>['adult', 'ads', 'dating']);
      expect(
        parsed.normalizedCustomDomains,
        <String>['example.com', 'tracker.net'],
      );
      expect(parsed.sourceLabel, 'ربات تلگرام');

      const FilterSettings empty = FilterSettings();
      final FilterSettings one = empty.toggleCategory('gambling');
      expect(one.enabled, isTrue);
      expect(one.categories, <String>['gambling']);
      final FilterSettings backToOff = one.toggleCategory('gambling');
      expect(backToOff.enabled, isFalse);
      expect(backToOff.categories, isEmpty);
    });

    test('نرمال سازی پسوند دامنه ورودی های معتبر و نامعتبر را درست تفکیک می کند', () {
      expect(
        FilterSettings.normalizeDomainSuffix(
          'HTTPS://www.Sub.Example.COM:443/a?b=1',
        ),
        'sub.example.com',
      );
      expect(
        FilterSettings.normalizeDomainSuffix('.ads.example.org.'),
        'ads.example.org',
      );
      expect(
        FilterSettings.normalizeDomainSuffix('*.bet-site.io'),
        'bet-site.io',
      );
      expect(
        FilterSettings.normalizeDomainSuffix('xn--mgbh0fb.xn--kgbechtv'),
        'xn--mgbh0fb.xn--kgbechtv',
      );
      expect(FilterSettings.normalizeDomainSuffix('localhost'), isNull);
      expect(FilterSettings.normalizeDomainSuffix('1.1.1.1'), isNull);
      expect(FilterSettings.normalizeDomainSuffix('bad_domain.com'), isNull);
      expect(FilterSettings.normalizeDomainSuffix(''), isNull);
    });

    test('قوانین مسدودسازی کنترل محتوا وارد تنظیمات هسته می شوند', () {
      final Map<String, dynamic> settings = UmbrellaCore.settingsJson(
        tun: false,
        systemProxy: true,
        port: 12334,
        logFile: 'core.log',
        contentFilter: const FilterSettings(
          enabled: true,
          categories: <String>['adult', 'gambling', 'ads', 'dating'],
          customDomains: <String>['custom-block.test'],
        ),
      );
      final Map<String, dynamic> routeRule =
          settings['route-rule'] as Map<String, dynamic>;
      final List<Map<String, dynamic>> rules =
          (routeRule['rules'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(rules, hasLength(5));
      expect(
        rules.every((Map<String, dynamic> item) => item['outbound'] == 'block'),
        isTrue,
      );
      expect(rules.last['domain_suffix'], contains('custom-block.test'));

      final Map<String, dynamic> disabled = UmbrellaCore.settingsJson(
        tun: false,
        systemProxy: true,
        port: 12334,
        logFile: 'core.log',
        contentFilter: const FilterSettings(
          enabled: false,
          categories: <String>['adult', 'ads'],
        ),
      );
      expect(disabled.containsKey('route-rule'), isFalse);
    });
  });

  group('v1.0.39 — فشرده سازی گزارش شبانه و اعلان ها', () {
    test('گزارش شبانه طولانی قدیمی به یک خط کوتاه، دقیق و خوانا تبدیل می شود', () {
      const String legacyNightly = '''
🌙 گزارش شبانه آمبرلا

سلام کاربر عزیز، امیدواریم شب آرامی داشته باشید.
━━━━━━━━━━━━━━
📊 مصرف کل تا امشب: ۱۲٫۵ گیگابایت
📦 ترافیک باقی مانده: ۳۷٫۵ گیگابایت
⏳ زمان باقی مانده: ۱۸ روز
📈 درصد مصرف: ۲۵٪
━━━━━━━━━━━━━━
برای مدیریت اشتراک به ربات @UmbrellaVPN_BOT مراجعه کنید.
پشتیبانی شبانه روزی آمبرلا
''';
      final AppNotification item = AppNotification(
        id: 1,
        title: '🌙 گزارش شبانه مصرف اشتراک آمبرلا شما',
        body: legacyNightly,
        level: 'info',
        sentAt: DateTime.utc(2026, 11, 17),
      );
      expect(item.compactTitle, contains('گزارش شبانه'));
      expect(item.compactBody.contains('━━━━'), isFalse);
      expect(item.compactBody.contains('امیدواریم'), isFalse);
      expect(item.compactBody.length, lessThanOrEqualTo(150));
      expect(item.balloonBody.length, lessThanOrEqualTo(115));
    });

    test('اعلان های کوتاه بدون تخریب و بدون حاشیه اضافی نمایش داده می شوند', () {
      final AppNotification item = AppNotification(
        id: 2,
        title: 'یادآور تمدید',
        body: '۲ روز تا پایان اعتبار · مانده ۴٫۲ گیگابایت',
        level: 'warning',
        sentAt: DateTime.utc(2026, 11, 17),
      );
      expect(item.compactTitle, 'یادآور تمدید');
      expect(item.compactBody, '۲ روز تا پایان اعتبار · مانده ۴٫۲ گیگابایت');
    });
  });

  group('v1.0.39 — اشتراک رایگان یک بار مصرف و اشتراک نوروزی شرطی', () {
    test('اشتراک رایگان فقط پیش از دریافت و اشتراک نوروزی فقط هنگام فعال بودن منو نمایش داده می شود', () {
      const SubscriptionOffers initial = SubscriptionOffers(
        freeAvailable: true,
        freeClaimed: false,
        nowruzMenuEnabled: false,
        nowruzAvailable: false,
        nowruzClaimed: false,
      );
      expect(initial.showFree, isTrue);
      expect(initial.showNowruz, isFalse);
      expect(initial.hasVisibleOffer, isTrue);

      const SubscriptionOffers afterFreeClaim = SubscriptionOffers(
        freeAvailable: true,
        freeClaimed: true,
        nowruzMenuEnabled: false,
        nowruzAvailable: false,
        nowruzClaimed: false,
      );
      expect(afterFreeClaim.showFree, isFalse);
      expect(afterFreeClaim.showNowruz, isFalse);
      expect(afterFreeClaim.hasVisibleOffer, isFalse);

      const SubscriptionOffers nowruzActive = SubscriptionOffers(
        freeAvailable: false,
        freeClaimed: true,
        nowruzMenuEnabled: true,
        nowruzAvailable: true,
        nowruzClaimed: false,
      );
      expect(nowruzActive.showFree, isFalse);
      expect(nowruzActive.showNowruz, isTrue);
      expect(nowruzActive.nowruzGb, 5);
      expect(nowruzActive.nowruzDays, 13);

      const SubscriptionOffers nowruzClaimed = SubscriptionOffers(
        freeAvailable: false,
        freeClaimed: true,
        nowruzMenuEnabled: true,
        nowruzAvailable: true,
        nowruzClaimed: true,
      );
      expect(nowruzClaimed.showNowruz, isFalse);
      expect(nowruzClaimed.hasVisibleOffer, isFalse);
    });
  });

  group('v1.0.39 — کانال اصلی/بتا و به روز رسانی کاملاً درون برنامه ای', () {
    test('مقایسه نسخه ها پایدار و پیش انتشار بتا را دقیق مرتب می کند', () {
      expect(UpdateInfo.compareVersions('1.0.39', '1.0.39'), 0);
      expect(UpdateInfo.compareVersions('1.0.40', '1.0.39'), greaterThan(0));
      expect(
        UpdateInfo.compareVersions('1.0.40-beta.1', '1.0.39'),
        greaterThan(0),
      );
      expect(
        UpdateInfo.compareVersions('1.0.40', '1.0.40-beta.2'),
        greaterThan(0),
      );
      expect(
        UpdateInfo.compareVersions('1.0.40-beta.2', '1.0.40-beta.1'),
        greaterThan(0),
      );
      expect(
        UpdateInfo.compareVersions('1.0.40-rc.1', '1.0.40-beta.9'),
        greaterThan(0),
      );
      expect(UpdateInfo.compareVersions('1.0.39-windows', '1.0.39'), 0);
    });

    test('پارس انتشار گیت هاب نسخه پایدار، بتا، پیش نویس و چک سام را تفکیک می کند', () {
      const String sampleDigest =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final Map<String, dynamic> stablePayload = <String, dynamic>{
        'tag_name': 'v1.0.40-windows',
        'draft': false,
        'prerelease': false,
        'published_at': '2026-11-17T10:00:00Z',
        'body': '- ارتقای هسته به 5.9.11\n- رفع کامل ماندن CLI پس از خروج',
        'assets': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'UmbrellaVPN-Setup-1.0.40.exe',
            'browser_download_url':
                'https://github.com/armin-soft/Umbrella-VPN/releases/download/v1.0.40-windows/UmbrellaVPN-Setup-1.0.40.exe',
            'size': 25165824,
            'digest': 'sha256:$sampleDigest',
          },
        ],
      };
      final UpdateInfo? stable = UpdateService.parseGithubRelease(
        stablePayload,
        includePreReleases: false,
      );
      expect(stable, isNotNull);
      expect(stable!.version, '1.0.40');
      expect(stable.preRelease, isFalse);
      expect(stable.sha256, sampleDigest);
      expect(stable.changelogItems, hasLength(2));

      final Map<String, dynamic> betaPayload = <String, dynamic>{
        'tag_name': 'v1.0.41-beta.1-windows',
        'draft': false,
        'prerelease': true,
        'body': '* کانال بتا آزمایشی',
        'assets': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'UmbrellaVPN-Setup-1.0.41-beta.1.exe',
            'browser_download_url':
                'https://github.com/armin-soft/Umbrella-VPN/releases/download/v1.0.41-beta.1/UmbrellaVPN-Setup-1.0.41-beta.1.exe',
            'size': 26000000,
          },
        ],
      };
      // در کانال پایدار نسخه بتا نادیده گرفته می شود، اما در کانال بتا پذیرفته می شود.
      expect(
        UpdateService.parseGithubRelease(
          betaPayload,
          includePreReleases: false,
        ),
        isNull,
      );
      final UpdateInfo? beta = UpdateService.parseGithubRelease(
        betaPayload,
        includePreReleases: true,
      );
      expect(beta, isNotNull);
      expect(beta!.version, '1.0.41-beta.1');
      expect(beta.preRelease, isTrue);

      final UpdateInfo? draft = UpdateService.parseGithubRelease(
        <String, dynamic>{
          'tag_name': 'v1.0.42-windows',
          'draft': true,
          'prerelease': false,
          'assets': <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'UmbrellaVPN-Setup-1.0.42.exe',
              'browser_download_url': 'https://example.com/a.exe',
            },
          ],
        },
        includePreReleases: true,
      );
      expect(draft, isNull);
    });

    test('کانال به روز رسانی ذخیره می شود و دانلود جریانی چک سام و لغو را رعایت می کند', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final AppStorage storage = await AppStorage.create();
      expect(storage.updateChannel, UpdateChannel.stable);
      await storage.setUpdateChannel(UpdateChannel.beta);
      expect(storage.updateChannel, UpdateChannel.beta);

      final Directory tempDir =
          await Directory.systemTemp.createTemp('umbrella-upd-test-');
      try {
        final List<int> payload =
            List<int>.generate(65536, (int i) => i % 251);
        final String validSha = sha256.convert(payload).toString();

        final UpdateService okService = UpdateService(
          client: _StreamingMockClient((_) async {
            return http.StreamedResponse(
              Stream<List<int>>.fromIterable(<List<int>>[
                payload.sublist(0, 30000),
                payload.sublist(30000),
              ]),
              200,
              contentLength: payload.length,
            );
          }),
        );
        int lastReceived = 0;
        final File? okFile = await okService.download(
          UpdateInfo(
            version: '1.0.40',
            url:
                'https://github.com/armin-soft/Umbrella-VPN/releases/download/v1.0.40/UmbrellaVPN-Setup-1.0.40.exe',
            sha256: validSha,
            sizeBytes: payload.length,
          ),
          targetDir: tempDir,
          onProgress: (double _, int received, int __) =>
              lastReceived = received,
        );
        expect(okFile, isNotNull);
        expect(await okFile!.length(), payload.length);
        expect(lastReceived, payload.length);
        await okFile.delete();

        // چک سام نامعتبر باید رد و فایل پاک شود.
        final File? badFile = await okService.download(
          UpdateInfo(
            version: '1.0.40',
            url:
                'https://github.com/armin-soft/Umbrella-VPN/releases/download/v1.0.40/UmbrellaVPN-Setup-1.0.40.exe',
            sha256: '0' * 64,
            sizeBytes: payload.length,
          ),
          targetDir: tempDir,
          onProgress: (_, __, ___) {},
        );
        expect(badFile, isNull);

        // لغو دانلود جریانی باید فوری عمل کند.
        bool cancelFlag = false;
        final UpdateService cancelService = UpdateService(
          client: _StreamingMockClient((_) async {
            Stream<List<int>> chunks() async* {
              yield payload.sublist(0, 8192);
              cancelFlag = true;
              yield payload.sublist(8192, 16384);
            }

            return http.StreamedResponse(
              chunks(),
              200,
              contentLength: payload.length,
            );
          }),
        );
        final File? cancelled = await cancelService.download(
          const UpdateInfo(
            version: '1.0.40',
            url:
                'https://github.com/armin-soft/Umbrella-VPN/releases/download/v1.0.40/UmbrellaVPN-Setup-1.0.40.exe',
          ),
          targetDir: tempDir,
          onProgress: (_, __, ___) {},
          isCancelled: () => cancelFlag,
        );
        expect(cancelled, isNull);
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }

      final String updatesPage =
          File('lib/ui/pages/updates_page.dart').readAsStringSync();
      expect(updatesPage.contains('openDownloadPage'), isFalse);
      expect(updatesPage, contains('UpdateChannel.stable'));
      expect(updatesPage, contains('UpdateChannel.beta'));
      expect(updatesPage, contains('downloadAndInstall'));
    });
  });

  group('v1.0.39 — ارتقای هسته به 5.9.11 و قابلیت های هم راستا', () {
    test('مانیفست هسته به 5.9.11 با چک سام رسمی ارتقا یافته و نسخه برنامه 1.0.39 است', () {
      expect(AppConfig.version, '1.0.39');
      expect(CoreRuntime.cacheSchemaVersion, 'umbrella-runtime-v3');
      final Map<String, dynamic> manifest =
          jsonDecode(File('assets/cores/manifest.json').readAsStringSync())
              as Map<String, dynamic>;
      final List<dynamic> cores = manifest['cores'] as List<dynamic>;
      final Map<String, dynamic> core =
          cores.first as Map<String, dynamic>;
      expect(core['version'], '5.9.11');
      expect(
        core['sha256'],
        '871232b29816574579c436ee110ceed95fced7181364d1ad5e62b922e32b15da',
      );
    });

    test('بازگشت خودکار ۱۰ دقیقه ای لاگ عیب یابی و ترجمه کدهای NTSTATUS کار می کند', () {
      final Map<String, dynamic> debugSettings = UmbrellaCore.settingsJson(
        tun: false,
        systemProxy: false,
        port: 12334,
        logFile: 'core.log',
        logLevel: 'debug',
      );
      expect(debugSettings['log-level'], 'debug');
      expect(debugSettings['log-level-after'], 'warn');
      expect(
        DateTime.tryParse('${debugSettings['log-level-until']}'),
        isNotNull,
      );

      final Map<String, dynamic> warnSettings = UmbrellaCore.settingsJson(
        tun: false,
        systemProxy: false,
        port: 12334,
        logFile: 'core.log',
        logLevel: 'warn',
      );
      expect(warnSettings.containsKey('log-level-until'), isFalse);
      expect(warnSettings.containsKey('log-level-after'), isFalse);

      expect(
        UmbrellaCore.describeWindowsExitCode(-1073741819),
        contains('0xC0000005'),
      );
      expect(
        UmbrellaCore.describeWindowsExitCode(-1073741515),
        contains('0xC0000135'),
      );
      expect(
        UmbrellaCore.describeWindowsExitCode(-1073740791),
        contains('0xC0000409'),
      );
      expect(UmbrellaCore.describeWindowsExitCode(1), isNull);

      expect(
        NetworkDns.presets.keys,
        contains('https://sky.rethinkdns.com/dns-query'),
      );
    });
  });
}
