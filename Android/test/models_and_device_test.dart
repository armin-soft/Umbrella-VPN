import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbrella_vpn/core/app_config.dart';
import 'package:umbrella_vpn/core/storage.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/platform/services.dart';
import 'package:umbrella_vpn/state/update_controller.dart';

void main() {
  group('DeviceProfile.fromNative', () {
    test('parses Android native telemetry, permissions, and memory fields', () {
      final DeviceProfile profile = DeviceProfile.fromNative(<String, dynamic>{
        'hostname': 'Pixel 8',
        'username': 'Google Pixel 8',
        'os': 'اندروید ۱۵ (سطح ۳۵)',
        'osDisplayVersion': '15',
        'osBuild': 35,
        'arch': 'arm64-v8a',
        'cpuCores': 8,
        'ramTotalMb': 8192,
        'ramUsedMb': 4096,
        'ramLoadPercent': 50,
        'diskTotalMb': 122880,
        'diskFreeMb': 61440,
        'hasBattery': true,
        'batteryPercent': 78,
        'powerPlugged': false,
        'uptimeSeconds': 3600,
        'localIp': '192.168.1.44',
        'elevated': true,
        'batteryOptimized': true,
        'canRequestInstallPackages': false,
        'notificationGranted': false,
      });

      expect(profile.deviceName, 'Pixel 8');
      expect(profile.osBuild, 35);
      expect(profile.archLabelFa, 'آرم ۶۴ بیتی');
      expect(profile.ramTotalGb, closeTo(8.0, 0.01));
      expect(profile.ramPercent, closeTo(50.0, 0.01));
      expect(profile.diskPercent, closeTo(50.0, 0.01));
      expect(profile.batteryPercent, 78);
      expect(profile.powerPlugged, isFalse);
      expect(profile.batteryOptimized, isTrue);
      expect(profile.canRequestInstallPackages, isFalse);
      expect(profile.notificationGranted, isFalse);

      final DeviceProfile updated = profile.copyWith(
        ip: '203.0.113.5',
        batteryOptimized: false,
      );
      expect(updated.ip, '203.0.113.5');
      expect(updated.batteryOptimized, isFalse);
      expect(updated.canRequestInstallPackages, isFalse);
      expect(updated.notificationGranted, isFalse);
    });

    test('maps ARM32 and x86_64 Android ABIs cleanly', () {
      final DeviceProfile arm32 = DeviceProfile.fromNative(<String, dynamic>{
        'arch': 'armeabi-v7a',
      });
      final DeviceProfile x64 = DeviceProfile.fromNative(<String, dynamic>{
        'arch': 'x86_64',
      });
      expect(arm32.archLabelFa, 'آرم ۳۲ بیتی');
      expect(x64.archLabelFa, '۶۴ بیتی');
    });
  });

  group('AppSettings Android persistence', () {
    test('defaults and round-trips Per-App Proxy and boot flags', () {
      const AppSettings settings = AppSettings(
        startWithWindows: true,
        serviceMode: InboundServiceMode.vpn,
        perAppProxyMode: 'exclude',
        perAppIncludePackages: <String>['org.telegram.messenger'],
        perAppExcludePackages: <String>['ir.bank.app', 'com.android.chrome'],
      );
      final AppSettings reloaded = AppSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
      );

      expect(reloaded.startOnBoot, isTrue);
      expect(reloaded.serviceMode, InboundServiceMode.vpn);
      expect(reloaded.perAppProxyMode, 'exclude');
      expect(reloaded.perAppIncludePackages, <String>['org.telegram.messenger']);
      expect(
        reloaded.perAppExcludePackages,
        <String>['ir.bank.app', 'com.android.chrome'],
      );
    });
  });

  group('UpdateService Android APK resolution', () {
    test('selects matching ABI APK and verifies SHA256SUMS parsing', () async {
      const String arm64Hash =
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      const String universalHash =
          'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

      final MockClient client = MockClient((http.Request req) async {
        if (req.url.toString() == AppConfig.releasesListApiUrl) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<Map<String, dynamic>>[
                <String, dynamic>{
                  'tag_name': '9.9.9',
                  'prerelease': false,
                  'draft': false,
                  'published_at': '2026-11-22T12:00:00Z',
                  'body': 'نسخه تازه اندروید',
                  'assets': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'name': 'UmbrellaVPN-9.9.9-armeabi-v7a.apk',
                      'browser_download_url':
                          'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/9.9.9/UmbrellaVPN-9.9.9-armeabi-v7a.apk',
                      'size': 20000000,
                    },
                    <String, dynamic>{
                      'name': 'UmbrellaVPN-9.9.9-arm64-v8a.apk',
                      'browser_download_url':
                          'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/9.9.9/UmbrellaVPN-9.9.9-arm64-v8a.apk',
                      'size': 22000000,
                    },
                    <String, dynamic>{
                      'name': 'UmbrellaVPN-9.9.9-universal.apk',
                      'browser_download_url':
                          'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/9.9.9/UmbrellaVPN-9.9.9-universal.apk',
                      'size': 40000000,
                    },
                  ],
                },
              ]),
            ),
            200,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }
        if (req.url.path.endsWith('/SHA256SUMS.txt')) {
          return http.Response(
            '$arm64Hash  UmbrellaVPN-9.9.9-arm64-v8a.apk\n'
            '$universalHash  UmbrellaVPN-9.9.9-universal.apk\n',
            200,
          );
        }
        return http.Response('', 404);
      });

      final UpdateService armService = UpdateService(
        client: client,
        preferredAbi: 'arm64-v8a',
      );
      final ({UpdateInfo? available, List<UpdateInfo> releases}) armCatalog =
          await armService.fetchCatalog(channel: UpdateChannel.stable);
      expect(armCatalog.available, isNotNull);
      expect(armCatalog.available!.assetName, 'UmbrellaVPN-9.9.9-arm64-v8a.apk');
      expect(armCatalog.available!.sha256, arm64Hash);

      final UpdateService fallbackService = UpdateService(
        client: client,
        preferredAbi: 'mips64',
      );
      final ({UpdateInfo? available, List<UpdateInfo> releases}) fallback =
          await fallbackService.fetchCatalog(channel: UpdateChannel.stable);
      expect(fallback.available, isNotNull);
      expect(fallback.available!.assetName, 'UmbrellaVPN-9.9.9-universal.apk');
      expect(fallback.available!.sha256, universalHash);
    });

    test('BatteryPowerState reflects mobile battery & exemption state', () {
      const BatteryPowerState optimized = BatteryPowerState(
        hasBattery: true,
        onBattery: true,
        energySaver: true,
        batteryPercent: 4,
        ignoringBatteryOptimizations: false,
      );
      expect(optimized.isLaptop, isTrue);
      expect(optimized.shouldOptimize, isTrue);
      expect(optimized.isCriticallyLowBattery, isTrue);
    });

    test('does not match x86 onto x86_64 APK asset', () async {
      const String x86_64Hash =
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      const String universalHash =
          'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

      final MockClient client = MockClient((http.Request req) async {
        if (req.url.toString() == AppConfig.releasesListApiUrl) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<Map<String, dynamic>>[
                <String, dynamic>{
                  'tag_name': '9.9.9',
                  'prerelease': false,
                  'draft': false,
                  'published_at': '2026-11-22T12:00:00Z',
                  'assets': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'name': 'UmbrellaVPN-9.9.9-x86_64.apk',
                      'browser_download_url':
                          'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/9.9.9/UmbrellaVPN-9.9.9-x86_64.apk',
                      'digest': 'sha256:$x86_64Hash',
                    },
                    <String, dynamic>{
                      'name': 'UmbrellaVPN-9.9.9-universal.apk',
                      'browser_download_url':
                          'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/9.9.9/UmbrellaVPN-9.9.9-universal.apk',
                      'digest': 'sha256:$universalHash',
                    },
                  ],
                },
              ]),
            ),
            200,
          );
        }
        return http.Response('', 404);
      });

      final UpdateService x86Service = UpdateService(
        client: client,
        preferredAbi: 'x86',
      );
      final ({UpdateInfo? available, List<UpdateInfo> releases}) cat =
          await x86Service.fetchCatalog(channel: UpdateChannel.stable);
      expect(cat.available?.assetName, 'UmbrellaVPN-9.9.9-universal.apk');
      client.close();
    });

    test('in-app APK update installs directly, handles permission resume, and reports archive errors', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await LocalStore.instance.init();

      final Directory tempDir = await Directory.systemTemp.createTemp('umb_upd_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final List<int> apkBytes = utf8.encode('PK-fake-apk-binary-payload-9.9.9');
      final String apkSha = sha256.convert(apkBytes).toString();
      final MockClient client = MockClient((http.Request req) async {
        if (req.url.toString() == AppConfig.releasesListApiUrl) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<Map<String, dynamic>>[
                <String, dynamic>{
                  'tag_name': '9.9.9',
                  'prerelease': false,
                  'draft': false,
                  'published_at': '2026-11-25T12:00:00Z',
                  'assets': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'name': 'UmbrellaVPN-9.9.9-arm64-v8a.apk',
                      'browser_download_url':
                          'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/9.9.9/UmbrellaVPN-9.9.9-arm64-v8a.apk',
                      'size': apkBytes.length,
                      'digest': 'sha256:$apkSha',
                    },
                  ],
                },
              ]),
            ),
            200,
          );
        }
        return http.Response.bytes(apkBytes, 200);
      });

      final _InstallFakeNative native = _InstallFakeNative();
      final UpdateController ctrl = UpdateController(
        native,
        service: _TestDirUpdateService(
          defaultDir: tempDir,
          client: client,
          preferredAbi: 'arm64-v8a',
        ),
      );
      addTearDown(() {
        ctrl.dispose();
        client.close();
      });

      await ctrl.check(silent: false);
      expect(ctrl.available, isNotNull);

      // 1. Permission required first -> stays in-app, saves pending file, resumes on grant.
      native.nextInstallResult = (ok: false, reason: 'install_permission_required');
      native.canRequestInstall = false;
      expect(await ctrl.downloadAndInstall(), isFalse);
      expect(ctrl.awaitingInstallPermission, isTrue);
      expect(ctrl.error, contains('اجازه از این منبع'));
      expect(native.installedPaths, hasLength(1));

      // Resuming before granting permission must NOT trigger another install loop.
      expect(await ctrl.resumePendingInstallIfPermitted(), isFalse);
      expect(native.installedPaths, hasLength(1));

      // Once permission is enabled, resuming automatically launches Android installer!
      native.canRequestInstall = true;
      native.nextInstallResult = (ok: true, reason: '');
      expect(await ctrl.resumePendingInstallIfPermitted(), isTrue);
      expect(ctrl.awaitingInstallPermission, isFalse);
      expect(ctrl.error, isEmpty);
      expect(native.installedPaths, hasLength(2));

      // 2. Signature mismatch surfaces exact error without opening external browser.
      native.nextInstallResult = (ok: false, reason: 'signature_mismatch');
      expect(await ctrl.downloadAndInstall(), isFalse);
      expect(ctrl.error, contains('امضای دیجیتال'));

      // 3. Invalid archive deletes bad file and shows exact error.
      native.nextInstallResult = (ok: false, reason: 'invalid_apk_archive');
      expect(await ctrl.downloadAndInstall(), isFalse);
      expect(ctrl.error, contains('معتبر یا کامل نیست'));
      expect(File(native.installedPaths.last).existsSync(), isFalse);
    });
  });
}

class _InstallFakeNative implements NativeBridge {
  ({bool ok, String reason}) nextInstallResult = (ok: true, reason: '');
  bool canRequestInstall = true;
  final List<String> installedPaths = <String>[];

  @override
  Future<({bool ok, String reason})> installApk(String path) async {
    installedPaths.add(path);
    return nextInstallResult;
  }

  @override
  Future<Map<String, dynamic>> getPlatformInfo() async =>
      <String, dynamic>{'canRequestInstallPackages': canRequestInstall};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestDirUpdateService extends UpdateService {
  _TestDirUpdateService({
    required this.defaultDir,
    super.client,
    super.preferredAbi,
  });

  final Directory defaultDir;

  @override
  Future<File?> download(
    UpdateInfo info, {
    required void Function(double progress, int received, int total) onProgress,
    bool Function()? isCancelled,
    Directory? targetDir,
  }) {
    return super.download(
      info,
      onProgress: onProgress,
      isCancelled: isCancelled,
      targetDir: targetDir ?? defaultDir,
    );
  }
}
