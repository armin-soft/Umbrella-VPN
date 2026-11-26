import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbrella_vpn/core/app_config.dart';
import 'package:umbrella_vpn/core/persian.dart';
import 'package:umbrella_vpn/core/storage.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/platform/native.dart';
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
      expect(launcher, contains('clear_loopback_proxy'));
      expect(systemOps, contains('JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE'));
      expect(systemOps, contains('ShutdownOwnedCores'));
      expect(systemOps, contains('AttachCoreJob'));
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
    test('دقیقاً سه دسته رسمی ربات تلگرام پشتیبانی و همگام می شوند', () {
      expect(
        FilterSettings.categoryLabels.keys.toList(),
        <String>['adult', 'gambling', 'ads'],
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
      expect(parsed.categories, <String>['adult', 'ads']);
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
          categories: <String>['adult', 'gambling', 'ads'],
          customDomains: <String>['custom-block.test'],
        ),
      );
      final Map<String, dynamic> routeRule =
          settings['route-rule'] as Map<String, dynamic>;
      final List<Map<String, dynamic>> rules =
          (routeRule['rules'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(rules, hasLength(10));
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
            'name': 'UmbrellaVPN-Setup-1.0.40-x64.exe',
            'browser_download_url':
                'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/v1.0.40-windows/UmbrellaVPN-Setup-1.0.40-x64.exe',
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
        'body': '* کانال بتا آزمایشی\nSHA-256: `$sampleDigest`',
        'assets': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'UmbrellaVPN-Setup-1.0.41-beta.1-x64.exe',
            'browser_download_url':
                'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/v1.0.41-beta.1-windows/UmbrellaVPN-Setup-1.0.41-beta.1-x64.exe',
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
      expect(beta.sha256, sampleDigest);
      expect(beta.changelogItems, <String>['کانال بتا آزمایشی']);
      expect(UpdateInfo.normalizeVersion('v1.0.41-nightly.2-windows'), '1.0.41-nightly.2');

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

      final UpdateInfo? unhashed = UpdateService.parseGithubRelease(
        <String, dynamic>{
          'tag_name': 'v1.0.43-windows',
          'draft': false,
          'prerelease': false,
          'assets': <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'UmbrellaVPN-Setup-1.0.43-x64.exe',
              'browser_download_url': 'https://example.com/setup.exe',
            },
          ],
        },
        includePreReleases: false,
      );
      expect(unhashed, isNotNull);
      expect(unhashed!.sha256, isEmpty);
      expect(UpdateService.hasValidSha256(sampleDigest), isTrue);
      expect(UpdateService.hasValidSha256(''), isFalse);
      expect(UpdateService.hasValidSha256('sha256:$sampleDigest'), isFalse);
    });

    test('برچسب ساده نسخه و انتشار چند فایل پلتفرم های مختلف را تشخیص می دهد', () {
      const String sampleDigest =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      final UpdateInfo? stable = UpdateService.parseGithubRelease(
        <String, dynamic>{
          'tag_name': '1.0.0',
          'draft': false,
          'prerelease': false,
          'body': 'نسخه رسمی\nSHA-256: $sampleDigest',
          'assets': <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'UmbrellaVPN-1.0.0-universal.apk',
              'browser_download_url': 'https://github.com/releases/1.0.0/app.apk',
            },
            <String, dynamic>{
              'name': 'UmbrellaVPN-1.0.0-macos.dmg',
              'browser_download_url': 'https://github.com/releases/1.0.0/app.dmg',
            },
            <String, dynamic>{
              'name': 'Umbrella.VPN-Setup-1.0.0-x64.exe',
              'browser_download_url':
                  'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/1.0.0/Umbrella.VPN-Setup-1.0.0-x64.exe',
              'size': 49821563,
              'digest': 'sha256:$sampleDigest',
            },
          ],
        },
        includePreReleases: false,
      );
      expect(stable, isNotNull);
      expect(stable!.tagName, '1.0.0');
      expect(stable.version, '1.0.0');
      expect(stable.assetName, 'Umbrella.VPN-Setup-1.0.0-x64.exe');
      expect(stable.url, contains('/1.0.0/Umbrella.VPN-Setup-1.0.0-x64.exe'));
      expect(stable.sha256, sampleDigest);
      expect(stable.preRelease, isFalse);
      expect(UpdateInfo.normalizeVersion('1.0.1'), '1.0.1');
      expect(UpdateInfo.normalizeVersion('1.0.1-beta.1'), '1.0.1-beta.1');

      final UpdateInfo? androidAndMacOnly = UpdateService.parseGithubRelease(
        <String, dynamic>{
          'tag_name': '1.0.2',
          'draft': false,
          'prerelease': false,
          'assets': <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'UmbrellaVPN-1.0.2.apk',
              'browser_download_url': 'https://github.com/releases/1.0.2/app.apk',
            },
            <String, dynamic>{
              'name': 'UmbrellaVPN-1.0.2.dmg',
              'browser_download_url': 'https://github.com/releases/1.0.2/app.dmg',
            },
          ],
        },
        includePreReleases: false,
      );
      expect(androidAndMacOnly, isNull,
          reason: 'a shared plain tag without a Windows installer is not a Windows update');

      final UpdateInfo? legacyWithoutAsset = UpdateService.parseGithubRelease(
        <String, dynamic>{
          'tag_name': 'v1.0.44-windows',
          'draft': false,
          'prerelease': false,
          'assets': <Map<String, dynamic>>[],
        },
        includePreReleases: false,
      );
      expect(legacyWithoutAsset, isNotNull,
          reason: 'legacy Windows-tag releases retain their direct-download fallback');
      expect(legacyWithoutAsset!.url, contains('/v1.0.44-windows/'));
    });

    test('کانال به روز رسانی ذخیره می شود و دانلود جریانی چک سام و لغو را رعایت می کند', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final LocalStore storage = LocalStore.instance;
      await storage.init();
      expect(
        UpdateChannelX.fromStorage(storage.read(StoreKeys.updateChannel)),
        UpdateChannel.stable,
      );
      await storage.write(
        StoreKeys.updateChannel,
        UpdateChannel.beta.storageValue,
      );
      expect(
        UpdateChannelX.fromStorage(storage.read(StoreKeys.updateChannel)),
        UpdateChannel.beta,
      );

      final Directory tempDir =
          await Directory.systemTemp.createTemp('umbrella-upd-test-');
      try {
        final List<int> payload =
            List<int>.generate(65536, (int i) => i % 251);
        final String validSha = sha256.convert(payload).toString();

        final List<Uri> catalogRequests = <Uri>[];
        final UpdateService noDigestCatalog = UpdateService(
          client: _StreamingMockClient((http.BaseRequest request) async {
            catalogRequests.add(request.url);
            if (request.url.toString() == AppConfig.releasesListApiUrl) {
              final List<int> json = utf8.encode(jsonEncode(<Map<String, dynamic>>[
                <String, dynamic>{
                  'tag_name': 'v1.0.40-windows',
                  'draft': false,
                  'prerelease': false,
                  'assets': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'name': 'UmbrellaVPN-Setup-1.0.40-x64.exe',
                      'browser_download_url': 'https://example.com/setup.exe',
                      'size': payload.length,
                    },
                  ],
                },
              ]));
              return http.StreamedResponse(
                Stream<List<int>>.value(json),
                200,
                headers: <String, String>{'content-type': 'application/json'},
              );
            }
            return http.StreamedResponse(
              const Stream<List<int>>.empty(),
              404,
            );
          }),
        );
        final ({UpdateInfo? available, List<UpdateInfo> releases}) catalog =
            await noDigestCatalog.fetchCatalog();
        expect(catalog.available, isNull);
        expect(catalog.releases, hasLength(1));
        expect(catalogRequests, hasLength(2)); // metadata and SHA256SUMS only

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
        final File staleExe = File(
          '${tempDir.path}${Platform.pathSeparator}UmbrellaVPN-Setup-1.0.38-x64.exe',
        )..writeAsBytesSync(<int>[1, 2, 3]);
        int lastReceived = 0;
        final File? okFile = await okService.download(
          UpdateInfo(
            version: '1.0.40',
            url:
                'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/v1.0.40-windows/UmbrellaVPN-Setup-1.0.40-x64.exe',
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
        expect(await staleExe.exists(), isFalse);
        await okFile.delete();

        int digestlessRequests = 0;
        final UpdateService digestlessService = UpdateService(
          client: _StreamingMockClient((_) async {
            digestlessRequests++;
            return http.StreamedResponse(
              Stream<List<int>>.value(payload),
              200,
              contentLength: payload.length,
            );
          }),
        );
        final File? digestless = await digestlessService.download(
          UpdateInfo(
            version: '1.0.40',
            url:
                'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/v1.0.40-windows/UmbrellaVPN-Setup-1.0.40-x64.exe',
          ),
          targetDir: tempDir,
          onProgress: (_, __, ___) {},
        );
        expect(digestless, isNull);
        expect(digestlessRequests, 0);
        final File? malformedDigest = await digestlessService.download(
          UpdateInfo(
            version: '1.0.40',
            url:
                'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/v1.0.40-windows/UmbrellaVPN-Setup-1.0.40-x64.exe',
            sha256: 'sha256:$validSha',
          ),
          targetDir: tempDir,
          onProgress: (_, __, ___) {},
        );
        expect(malformedDigest, isNull);
        expect(digestlessRequests, 0);

        // نشانی غیرامن http باید پیش از شبکه رد شود.
        final File? insecure = await okService.download(
          UpdateInfo(
            version: '1.0.40',
            url:
                'http://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/v1.0.40-windows/UmbrellaVPN-Setup-1.0.40-x64.exe',
            sha256: validSha,
          ),
          targetDir: tempDir,
          onProgress: (_, __, ___) {},
        );
        expect(insecure, isNull);

        // چک سام نامعتبر باید رد و فایل پاک شود.
        final File? badFile = await okService.download(
          UpdateInfo(
            version: '1.0.40',
            url:
                'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/v1.0.40-windows/UmbrellaVPN-Setup-1.0.40-x64.exe',
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
          UpdateInfo(
            version: '1.0.40',
            url:
                'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/v1.0.40-windows/UmbrellaVPN-Setup-1.0.40-x64.exe',
            sha256: validSha,
          ),
          targetDir: tempDir,
          onProgress: (_, __, ___) {},
          isCancelled: () => cancelFlag,
        );
        expect(cancelled, isNull);

        final File installCandidate = File(
          '${tempDir.path}${Platform.pathSeparator}UmbrellaVPN-Setup-1.0.40-x64.exe',
        )..writeAsBytesSync(payload);
        final NativeBridge native = NativeBridge();
        expect(
          await okService.install(
            installCandidate,
            native,
            expectedSha256: '',
          ),
          isFalse,
        );
        expect(
          await okService.install(
            installCandidate,
            native,
            expectedSha256: '0' * 64,
          ),
          isFalse,
        );
        expect(native.available, isTrue,
            reason: 'invalid or mismatched installers must not reach elevation');
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

      final String services = File('lib/platform/services.dart').readAsStringSync();
      expect(services, contains('/SILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS'));
      expect(services, contains('/RelaunchAfterUpdate=1'));
    });
  });

  group('نسخه ۱.۰.۲ — هسته ۵.۹.۱۵ و یکپارچگی نسخه در همه فایل ها', () {
    test('مانیفست هسته به 5.9.15 با چک سام رسمی ارتقا یافته و نسخه برنامه در همه جا 1.0.2 است', () {
      expect(AppConfig.version, '1.0.2');
      expect(AppConfig.versionLabel, '1.0.2');
      expect(AppConfig.buildNumber, 3);
      expect(File('pubspec.yaml').readAsStringSync(), contains('version: 1.0.2+3'));
      expect(
        File('installer/umbrella.iss').readAsStringSync(),
        contains('#define AppVersion "1.0.2"'),
      );
      expect(
        File('windows/CMakeLists.txt').readAsStringSync(),
        contains('project(UmbrellaVPN VERSION "1.0.2" LANGUAGES C CXX)'),
      );
      final String workflow =
          File('../.github/workflows/windows-draft.yml').readAsStringSync();
      expect(workflow, contains('name: UmbrellaVPN-Setup-1.0.2-x64'));
      expect(
        File('packages/umbrella_native/windows/winhttp_client.cpp')
            .readAsStringSync(),
        contains('UmbrellaVPN/1.0.2'),
      );
      expect(CoreRuntime.cacheSchemaVersion, 'umbrella-runtime-v9');
      final Map<String, dynamic> manifest =
          jsonDecode(File('assets/cores/manifest.json').readAsStringSync())
              as Map<String, dynamic>;
      final List<dynamic> cores = manifest['cores'] as List<dynamic>;
      final Map<String, dynamic> core =
          cores.first as Map<String, dynamic>;
      expect(core['version'], '5.9.15');
      expect(
        core['sha256'],
        '96736e5c2cdc5c5ad74a0fc57927f5f3461c6b80cf7941527f8a2a6a763fd3e3',
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

      final String msg05 = UmbrellaCore.describeWindowsExitCode(-1073741819);
      final String msg135 = UmbrellaCore.describeWindowsExitCode(-1073741515);
      final String msg409 = UmbrellaCore.describeWindowsExitCode(-1073740791);
      expect(msg05, contains('دسترسی حافظه'));
      expect(msg05, contains(Fa.num(0xC0000005)));
      expect(msg05, isNot(contains(RegExp(r'[A-Za-z0-9\u200C]'))));
      expect(msg135, contains('کتابخانه مورد نیاز هسته'));
      expect(msg135, contains(Fa.num(0xC0000135)));
      expect(msg135, isNot(contains(RegExp(r'[A-Za-z0-9\u200C]'))));
      expect(msg409, contains('سرریز بافر'));
      expect(msg409, contains(Fa.num(0xC0000409)));
      expect(msg409, isNot(contains(RegExp(r'[A-Za-z0-9\u200C]'))));
      expect(UmbrellaCore.describeWindowsExitCode(1), isEmpty);

      expect(
        NetworkDns.presets.keys,
        contains('https://sky.rethinkdns.com/dns-query'),
      );
    });

    test('تمام منوها و دکمه های همگام سازی دستی حذف شده و همگام سازی خودکار است', () {
      final String account =
          File('lib/ui/pages/account_page.dart').readAsStringSync();
      final String content =
          File('lib/ui/widgets/content_control.dart').readAsStringSync();
      final String device =
          File('lib/ui/pages/device_page.dart').readAsStringSync();
      final String shell =
          File('lib/ui/shell/app_shell.dart').readAsStringSync();
      final String updates =
          File('lib/ui/pages/updates_page.dart').readAsStringSync();
      final String connect =
          File('lib/ui/pages/connect_page.dart').readAsStringSync();
      final String auth =
          File('lib/state/auth_controller.dart').readAsStringSync();

      // هیچ منو یا دکمه همگام سازی و بروزرسانی دستی باقی نمانده است.
      expect(account.contains('همگام سازی با تلگرام'), isFalse);
      expect(account.contains('اتصال و سینک حساب'), isFalse);
      expect(account.contains('_refreshFromServer'), isFalse);
      expect(account.contains('Icons.sync_rounded'), isFalse);
      expect(content.contains('همگام سازی با ربات'), isFalse);
      expect(content.contains('_onSyncFromBot'), isFalse);
      expect(content.contains('Icons.sync_rounded'), isFalse);
      expect(content.contains('Icons.refresh_rounded'), isFalse);
      expect(device.contains('بروزرسانی دستگاه'), isFalse);
      expect(device.contains('Icons.refresh_rounded'), isFalse);
      expect(shell.contains('به روز رسانی اعلان ها'), isFalse);
      expect(shell.contains('Icons.refresh_rounded'), isFalse);
      expect(updates.contains('بررسی نسخه جدید'), isFalse);
      expect(updates.contains('Icons.refresh_rounded'), isFalse);
      expect(connect.contains('به روز رسانی آی پی'), isFalse);
      expect(connect.contains('Icons.refresh_rounded'), isFalse);

      // چرخه همگام سازی کاملاً خودکار در تمام بخش ها فعال است.
      expect(auth.contains('Future<void> autoSync('), isTrue);
      expect(shell.contains('_triggerAutoSync'), isTrue);
      expect(account.contains('_autoSyncTimer'), isTrue);
      expect(content.contains('_autoPollTimer'), isTrue);
      expect(device.contains('_autoRefreshTimer'), isTrue);
      expect(updates.contains('_autoCheckTimer'), isTrue);
    });

    test('QuickConnectionPanel، اشتراک گذاری LAN با QR و تنظیمات شش بخشی کامل کار می کنند', () {
      // ۱. ساخت رمز، لینک SOCKS5، لینک تلگرام و داده QR اشتراک گذاری LAN
      final String generated = LanSharing.generateSecret();
      expect(RegExp(r'^[A-Za-z0-9]{4}-[A-Za-z0-9]{4}$').hasMatch(generated), isTrue);
      expect(LanSharing.isValidPassword(''), isTrue);
      expect(LanSharing.isValidPassword('abc'), isFalse);
      expect(LanSharing.isValidPassword(generated), isTrue);
      expect(LanSharing.isValidPort(12338, forbiddenPort: 12334), isTrue);
      expect(LanSharing.isValidPort(12334, forbiddenPort: 12334), isFalse);
      expect(LanSharing.isValidPort(80), isFalse);

      final String openLink = LanSharing.socksLink(host: '192.168.1.42', port: 12338);
      expect(openLink, 'socks://192.168.1.42:12338#Umbrella%20LAN');
      final String qr = LanSharing.qrPayload(
        host: '192.168.1.42',
        port: 12338,
        password: 'MySecret-99',
      );
      expect(qr.startsWith('#profile-title: Umbrella LAN\nsocks://'), isTrue);
      expect(qr.contains(':MySecret-99@192.168.1.42:12338#Umbrella%20LAN'), isTrue);
      final String tg = LanSharing.telegramLink(
        host: '192.168.1.42',
        port: 12338,
        password: 'MySecret-99',
      );
      expect(tg.startsWith('tg://socks?'), isTrue);
      expect(tg.contains('server=192.168.1.42'), isTrue);
      expect(tg.contains('port=12338'), isTrue);
      expect(tg.contains('pass=MySecret-99'), isTrue);

      // ۲. ذخیره، بازیابی و خروجی JSON تمام گزینه های ۶ بخش به موتور 5.9.11
      final AppSettings configured = const AppSettings().copyWith(
        serviceMode: InboundServiceMode.proxy,
        mixedPort: 14080,
        localProxyInVpn: false,
        localProxyAuth: true,
        allowConnectionFromLan: true,
        lanSharingPort: 14088,
        lanSharingPassword: 'SafePass-42',
        remoteDns: 'https://1.1.1.1/dns-query',
        directDns: '8.8.8.8',
        remoteDnsStrategy: DnsDomainStrategy.ipv4Only,
        directDnsStrategy: DnsDomainStrategy.preferIpv4,
        enableFakeDns: true,
        routingRegion: RoutingRegion.ir,
        bypassLan: true,
        blockAds: true,
        resolveDestination: true,
        blockQuic: true,
        ipv6RouteMode: Ipv6RouteMode.preferIpv6,
        tlsTricks: const TlsTricksSettings(
          enableFragment: true,
          fragmentSize: '20-80',
          fragmentSleep: '40-120',
          mixedSniCase: true,
          enablePadding: true,
          paddingSize: '1100-1400',
        ),
        chain: const ChainSettings().activateUnblocker(ChainTransport.automatic).copyWith(
              noiseMode: 'quic',
              noiseCount: '5-10',
              noiseSize: '40-90',
              noiseDelay: '10-25',
            ),
      );
      final AppSettings restored = AppSettings.fromJson(
        jsonDecode(jsonEncode(configured.toJson())) as Map<String, dynamic>,
      );
      expect(restored.serviceMode, InboundServiceMode.proxy);
      expect(restored.mixedPort, 14080);
      expect(restored.allowConnectionFromLan, isTrue);
      expect(restored.lanSharingPort, 14088);
      expect(restored.lanSharingPassword, 'SafePass-42');
      expect(restored.routingRegion, RoutingRegion.ir);
      expect(restored.ipv6RouteMode, Ipv6RouteMode.preferIpv6);
      expect(restored.tlsTricks, configured.tlsTricks);
      expect(restored.chain.position, ChainPosition.unblocker);
      expect(restored.chain.endpoint, WarpEndpoint.scan);
      expect(restored.chain.noiseMode, 'quic');

      final Map<String, dynamic> coreJson = UmbrellaCore.settingsJson(
        tun: false,
        systemProxy: false,
        port: restored.mixedPort,
        networkSettings: restored,
      );
      expect(coreJson['enable-tun'], isFalse);
      expect(coreJson['set-system-proxy'], isFalse);
      expect(coreJson['mixed-port'], 14080);
      expect(coreJson['allow-connection-from-lan'], isTrue);
      expect(coreJson['lan-sharing-port'], 14088);
      expect(coreJson['lan-sharing-password'], 'SafePass-42');
      expect(coreJson['local-proxy-auth'], isTrue);
      expect(coreJson['local-proxy-in-vpn'], isFalse);
      expect(coreJson['remote-dns-domain-strategy'], 'ipv4_only');
      expect(coreJson['direct-dns-domain-strategy'], 'prefer_ipv4');
      expect(coreJson['enable-fake-dns'], isTrue);
      expect(coreJson['region'], 'ir');
      expect(coreJson['bypass-lan'], isTrue);
      expect(coreJson['block-ads'], isTrue);
      expect(coreJson['resolve-destination'], isTrue);
      expect(coreJson['block-quic'], isTrue);
      expect(coreJson['ipv6-mode'], 'prefer_ipv6');
      expect(coreJson['chain-status'], 'unblocker');
      final Map<String, dynamic> tls =
          coreJson['tls-tricks'] as Map<String, dynamic>;
      expect(tls['enable-fragment'], isTrue);
      expect(tls['fragment-size'], '20-80');
      expect(tls['fragment-sleep'], '40-120');
      expect(tls['mixed-sni-case'], isTrue);
      expect(tls['enable-padding'], isTrue);
      expect(tls['padding-size'], '1100-1400');

      // سنجش پینگ ایزوله هرگز پورت اشتراک LAN یا رمز یا FakeDNS را باز نمی کند.
      final Map<String, dynamic> probeJson = UmbrellaCore.settingsJson(
        tun: false,
        systemProxy: false,
        port: 19999,
        networkSettings: restored,
        isolatedProbe: true,
      );
      expect(probeJson['allow-connection-from-lan'], isFalse);
      expect(probeJson.containsKey('lan-sharing-password'), isFalse);
      expect(probeJson['local-proxy-auth'], isFalse);
      expect(probeJson['enable-fake-dns'], isFalse);

      // ۳. امنیت بیشتر و رفع فیلتر پروکسی دوحالته (mutually exclusive) هستند.
      final ChainSettings extra =
          restored.chain.activateExtraSecurity(ChainTransport.psiphon);
      expect(extra.position, ChainPosition.extraSecurity);
      expect(extra.transport, ChainTransport.psiphon);
      expect(extra.validationError, isNull);
      expect(extra.deactivate().position, ChainPosition.off);

      // ۴. بررسی وجود دیالوگ QR و شش دسته صفحه تنظیمات
      final String qrDialog =
          File('lib/ui/widgets/lan_sharing_dialog.dart').readAsStringSync();
      expect(qrDialog.contains('QrImageView('), isTrue);
      expect(qrDialog.contains('BrandAssets.logo'), isTrue);
      expect(qrDialog.contains('رمز تنظیم نشده'), isTrue);
      expect(qrDialog.contains('گذاشتن رمز'), isTrue);
      expect(qrDialog.contains('کپی لینک'), isTrue);
    });

    test('تمامی متون برنامه فارسی، بدون نیم فاصله و با ارقام فارسی هستند', () {
      // ۱. هیچ نویسه نیم فاصله (U+200C) در کل کد برنامه و پلاگین بومی وجود ندارد.
      final List<FileSystemEntity> sourceFiles = <FileSystemEntity>[
        ...Directory('lib').listSync(recursive: true),
        ...Directory('packages/umbrella_native/windows')
            .listSync(recursive: true),
        ...Directory('windows/runner').listSync(recursive: true),
      ];
      for (final FileSystemEntity entity in sourceFiles) {
        if (entity is! File) continue;
        final String path = entity.path.replaceAll('\\', '/');
        if (!path.endsWith('.dart') &&
            !path.endsWith('.cpp') &&
            !path.endsWith('.h')) {
          continue;
        }
        final String text = entity.readAsStringSync();
        expect(
          text.contains('\u200C'),
          isFalse,
          reason: 'نیم فاصله در فایل $path یافت شد',
        );
      }

      // ۲. Fa.num ارقام لاتین و عربی را به فارسی تبدیل و نیم فاصله را حذف می کند.
      expect(Fa.num('1234567890'), '۱۲۳۴۵۶۷۸۹۰');
      expect(Fa.num('٠١٢٣٤٥٦٧٨٩'), '۰۱۲۳۴۵۶۷۸۹');
      expect(Fa.num('می\u200Cشود 2026'), 'می شود ۲۰۲۶');
      expect(Fa.toEn('۱۲۳۳۸'), '12338');
      expect(
        Fa.num('نشانی درگاه: 192.168.10.20:2087'),
        'نشانی درگاه: 192.168.10.20:2087',
      );
      expect(
        Fa.num('نشانی امن: https://node2.example.com/u/123?key=9'),
        'نشانی امن: https://node2.example.com/u/123?key=9',
      );
      expect(
        Fa.num('دامنه فنی: node2.example.com#key/123'),
        'دامنه فنی: node2.example.com#key/123',
      );
      expect(
        Fa.num('نشانی مسیر: 192.0.2.10#route=2026'),
        'نشانی مسیر: 192.0.2.10#route=2026',
      );
      expect(
        Fa.num('شناسه عددی تلگرام: 123456789'),
        'شناسه عددی تلگرام: 123456789',
      );
      expect(
        Fa.num('کلید wg-key-99 و مقدار 2026'),
        'کلید wg-key-99 و مقدار ۲۰۲۶',
      );
      expect(Fa.num('نشانی IPv6: 2001:db8::1'), 'نشانی IPv6: 2001:db8::1');
      expect(
        Fa.num('نشانی IPv6: [2001:db8::1]:8080/api/1'),
        'نشانی IPv6: [2001:db8::1]:8080/api/1',
      );
      expect(Fa.num('نشانی IPv6: 2001:db8::1.'), 'نشانی IPv6: 2001:db8::1.');
      expect(
        Fa.num('نشانی IPv6 نگاشته: [::ffff:192.0.2.1]:443'),
        'نشانی IPv6 نگاشته: [::ffff:192.0.2.1]:443',
      );
      expect(
        Fa.num('نشانی محلی IPv6: [fe80::1%25en0]:5353/path/123.'),
        'نشانی محلی IPv6: [fe80::1%25en0]:5353/path/123.',
      );
      expect(
        Fa.num('شناسه فنی: 970f3fa0-3714-4d9a-a95d-8c4ddd696bfd'),
        'شناسه فنی: 970f3fa0-3714-4d9a-a95d-8c4ddd696bfd',
      );
      expect(
        Fa.num('نشانی سخت افزاری: 00:1A:2B:3C:4D:5E'),
        'نشانی سخت افزاری: 00:1A:2B:3C:4D:5E',
      );
      expect(
        Fa.num('نشانی سخت افزاری: 00-1A-2B-3C-4D-5E'),
        'نشانی سخت افزاری: 00-1A-2B-3C-4D-5E',
      );
      expect(
        Fa.num(
          'پروتکل IPv4 و TLS 1.3 یا TLS/1.3، وضعیت HTTP/404 و نسخه برنامه 1.0.39',
        ),
        'پروتکل IPv4 و TLS 1.3 یا TLS/1.3، وضعیت HTTP/404 و نسخه برنامه ۱.۰.۳۹',
      );
      expect(Fa.num('کد وضعیت 503'), 'کد وضعیت 503');
      expect(AppConfig.versionPhrase, isNot(contains(RegExp(r'[0-9]'))));
      expect(AppConfig.versionPhrase, contains('۱٫۰٫۱'));

      // ۳. تمام برچسب های نمایشی مدل ها فارسی خالص، بدون لاتین، بدون رقم لاتین و بدون نیم فاصله اند.
      final RegExp forbidden = RegExp(r'[A-Za-z0-9\u200C]');
      final List<String> allLabels = <String>[
        for (final InboundServiceMode m in InboundServiceMode.values) ...<String>[
          m.shortLabel,
          m.fullLabel,
          m.description,
        ],
        for (final DnsDomainStrategy s in DnsDomainStrategy.values) s.label,
        for (final Ipv6RouteMode m in Ipv6RouteMode.values) m.label,
        for (final RoutingRegion r in RoutingRegion.values) ...<String>[
          r.label,
          r.shortLabel,
        ],
        for (final ChainPosition p in ChainPosition.values) p.label,
        for (final ChainTransport t in ChainTransport.values) ...<String>[
          t.label,
          t.tunnelLabel,
          t.quickLabel,
        ],
        for (final WarpEndpoint e in WarpEndpoint.values) e.label,
        for (final AppRouteAction a in AppRouteAction.values) a.label,
        for (final TunStack s in TunStack.values) s.label,
        for (final SubscriptionFormat format in SubscriptionFormat.values)
          format.label,
        for (final NodeProtocol protocol in NodeProtocol.values)
          protocol.label,
        for (final UpdateChannel channel in UpdateChannel.values) ...<String>[
          channel.label,
          channel.shortLabel,
          channel.subtitle,
        ],
        for (final CorePreference c in CorePreference.values) ...<String>[
          c.faName,
          c.description,
        ],
        for (final SelectionMode m in SelectionMode.values) ...<String>[
          m.label,
          m.faName,
          m.description,
        ],
        for (final ThemePreference t in ThemePreference.values) t.label,
        ...NetworkDns.presets.values,
        for (final String k in NetworkDns.presets.keys) NetworkDns.subtitleFa(k),
        ...ChainSettings.regionLabels.values,
        ...ChainSettings.noiseModes.values,
      ];
      for (final String label in allLabels) {
        expect(
          forbidden.hasMatch(label),
          isFalse,
          reason: 'برچسب غیرفارسی یا دارای رقم لاتین/نیم فاصله: "$label"',
        );
      }

      // ۴. بازه های عددی با ارقام فارسی اعتبارسنجی می شوند و به هسته ASCII می دهند.
      expect(TlsTricksSettings.isValidRange('۱۰-۱۰۰'), isTrue);
      final Map<String, dynamic> tlsCore = const TlsTricksSettings(
        enableFragment: true,
        fragmentSize: '۲۰-۸۰',
        fragmentSleep: '۳۰-۱۵۰',
        enablePadding: true,
        paddingSize: '۱۱۰۰-۱۴۰۰',
      ).toCoreOptions();
      expect(tlsCore['fragment-size'], '20-80');
      expect(tlsCore['fragment-sleep'], '30-150');
      expect(tlsCore['padding-size'], '1100-1400');

      // ۵. رمز اشتراک LAN فقط از ارقام ساخته می شود تا نمایش فارسی و کپی ASCII داشته باشد.
      final String generated = LanSharing.generateSecret();
      expect(RegExp(r'^\d{4}-\d{4}$').hasMatch(generated), isTrue);
      expect(RegExp(r'^[۰-۹]{4}-[۰-۹]{4}$').hasMatch(Fa.num(generated)), isTrue);

      // ۶. پنجره تنظیمات اتصال فقط حالت سرویس و اشتراک شبکه محلی را نشان می دهد.
      final String quickPanel =
          File('lib/ui/widgets/quick_connection_panel.dart').readAsStringSync();
      expect(quickPanel.contains('_expanded'), isFalse);
      expect(quickPanel.contains('quick-panel-toggle'), isFalse);
      expect(quickPanel.contains('MenuAnchor('), isFalse);
      expect(quickPanel.contains('ChoiceChip('), isFalse);
      expect(quickPanel.contains('quick-extra-security'), isFalse);
      expect(quickPanel.contains('quick-proxy-unblocker'), isFalse);
      expect(quickPanel.contains('quick-chain-settings'), isFalse);
      expect(quickPanel.contains('PopupMenuButton'), isFalse);
      expect(quickPanel.contains('chevron_right_rounded'), isFalse);

      final String settingsPage =
          File('lib/ui/pages/settings_page.dart').readAsStringSync();
      expect(settingsPage.contains('PopupMenuButton'), isFalse);
      expect(settingsPage.contains('chevron_right_rounded'), isFalse);

      final String lanDialog =
          File('lib/ui/widgets/lan_sharing_dialog.dart').readAsStringSync();
      expect(lanDialog.contains('PopupMenuButton'), isFalse);
      expect(lanDialog.contains('MenuAnchor('), isTrue);

      // ۷. همه حالت ها و منوهای شبکه آیکون اختصاصی دارند.
      for (final InboundServiceMode m in InboundServiceMode.values) {
        expect(m.icon.codePoint, greaterThan(0));
      }
      for (final DnsDomainStrategy s in DnsDomainStrategy.values) {
        expect(s.icon.codePoint, greaterThan(0));
      }
      for (final Ipv6RouteMode m in Ipv6RouteMode.values) {
        expect(m.icon.codePoint, greaterThan(0));
      }
      for (final RoutingRegion r in RoutingRegion.values) {
        expect(r.icon.codePoint, greaterThan(0));
      }
      for (final ChainTransport t in ChainTransport.values) {
        expect(t.icon.codePoint, greaterThan(0));
        expect(t.quickIcon.codePoint, greaterThan(0));
      }
      for (final WarpEndpoint e in WarpEndpoint.values) {
        expect(e.icon.codePoint, greaterThan(0));
      }
      for (final AppRouteAction a in AppRouteAction.values) {
        expect(a.icon.codePoint, greaterThan(0));
      }
      for (final TunStack s in TunStack.values) {
        expect(s.icon.codePoint, greaterThan(0));
      }
      for (final String k in NetworkDns.presets.keys) {
        expect(NetworkDns.iconFor(k).codePoint, greaterThan(0));
      }
    });

    test('مخزن رسمی Umbrella-VPN-Releases، آیکون گرد شفاف نصب کننده و هماهنگی نسخه نهایی برقرار است', () {
      expect(
        AppConfig.releaseApiUrl,
        'https://api.github.com/repos/armin-soft/Umbrella-VPN-Releases/releases/latest',
      );
      expect(
        AppConfig.releasesListApiUrl,
        'https://api.github.com/repos/armin-soft/Umbrella-VPN-Releases/releases?per_page=20',
      );
      expect(
        AppConfig.releasesPageUrl,
        'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/latest',
      );
      expect(
        AppConfig.allReleasesPageUrl,
        'https://github.com/armin-soft/Umbrella-VPN-Releases/releases',
      );

      final String iss = File('installer/umbrella.iss').readAsStringSync();
      expect(iss, contains('WizardImageAlphaFormat=defined'));
      expect(
        iss,
        contains(
          'WizardSmallImageFile=wizard-small.bmp,wizard-small-150.bmp,wizard-small-200.bmp,wizard-small-250.bmp',
        ),
      );
      expect(
        iss,
        contains('https://github.com/armin-soft/Umbrella-VPN-Releases/releases'),
      );
      expect(iss, contains('ClearLoopbackProxy'));

      // تمام آیکون های کوچک ویزارد نصب باید ۳۲ بیتی BGRA با گوشه های کاملا شفاف باشند.
      for (final (String file, int expectedSize) in <(String, int)>[
        ('installer/wizard-small.bmp', 55),
        ('installer/wizard-small-150.bmp', 83),
        ('installer/wizard-small-200.bmp', 110),
        ('installer/wizard-small-250.bmp', 138),
      ]) {
        final Uint8List bytes = File(file).readAsBytesSync();
        final ByteData bd = ByteData.sublistView(bytes);
        expect(bytes[0], 0x42); // 'B'
        expect(bytes[1], 0x4D); // 'M'
        final int offset = bd.getUint32(10, Endian.little);
        final int w = bd.getInt32(18, Endian.little);
        final int h = bd.getInt32(22, Endian.little);
        final int bpp = bd.getUint16(28, Endian.little);
        final int comp = bd.getUint32(30, Endian.little);
        expect(w, expectedSize, reason: file);
        expect(h, expectedSize, reason: file);
        expect(bpp, 32, reason: file);
        expect(comp, 0, reason: file);
        int alphaAt(int x, int y) {
          final int row = h - 1 - y;
          return bytes[offset + (row * w + x) * 4 + 3];
        }
        expect(alphaAt(0, 0), 0, reason: '$file top-left corner');
        expect(alphaAt(w - 1, 0), 0, reason: '$file top-right corner');
        expect(alphaAt(0, h - 1), 0, reason: '$file bottom-left corner');
        expect(alphaAt(w - 1, h - 1), 0, reason: '$file bottom-right corner');
        expect(alphaAt(w ~/ 2, h ~/ 2), 255, reason: '$file center');
      }

      // نسخه Runner.rc و THIRD-PARTY-NOTICES و سربرگ اصلی صفحه درباره.
      final String runnerRc =
          File('windows/runner/Runner.rc').readAsStringSync();
      expect(runnerRc, contains('FILEVERSION 1,0,2,0'));
      expect(runnerRc, contains('PRODUCTVERSION 1,0,2,0'));
      expect(runnerRc, contains('VALUE "FileVersion", "1.0.2.0"'));
      expect(runnerRc, contains('VALUE "ProductVersion", "1.0.2.0"'));
      expect(runnerRc, contains('VALUE "CompanyName", "Umbrella"'));

      final String notices = File('THIRD-PARTY-NOTICES.txt').readAsStringSync();
      expect(notices, contains('5.9.15'));

      final String aboutPage =
          File('lib/ui/pages/about_page.dart').readAsStringSync();
      expect(aboutPage, contains("title: 'درباره'"));
      expect(aboutPage, contains('PageHeader('));
      expect(aboutPage, isNot(contains('PageBanner(')));
    });
  });
}
