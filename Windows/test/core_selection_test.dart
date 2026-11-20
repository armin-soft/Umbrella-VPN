import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/models/models.dart';

void main() {
  group('نام کشور و پرچم', () {
    test('کد کشور از داده جغرافیایی خوانده می شود', () {
      const GeoInfo geo = GeoInfo(countryCode: 'CA', country: 'Canada', city: 'Montreal');
      expect(geo.flagCode, 'ca');
      expect(geo.flagEmojiFreeLabel, 'Canada، Montreal');
    });

    test('موقعیت ناشناخته رشته خالی می دهد، نه «نامشخص»', () {
      // خط تاریخ و موقعیت در صفحه اتصال نباید «نامشخص، نامشخص» بنویسد.
      expect(const GeoInfo().countryLabel, isEmpty);
      expect(const GeoInfo().flagEmojiFreeLabel, isEmpty);
      expect(const GeoInfo(city: 'Montreal').flagEmojiFreeLabel, 'Montreal');
    });

    test('اگر کد کشور نبود، از نام کشور استنباط می شود', () {
      expect(const GeoInfo(country: 'Germany').flagCode, 'de');
      expect(const GeoInfo(country: 'Netherlands').flagCode, 'nl');
      expect(const GeoInfo(country: 'نامعلوم').flagCode, '');
    });

    test('پرچم سرور از نام آن پیدا می شود', () {
      const VpnNode node = VpnNode(
        id: 'a',
        name: 'Umbrella | Germany | Frankfurt',
        protocol: NodeProtocol.vless,
        host: 'x',
        port: 443,
        sourceId: 's',
        params: <String, dynamic>{},
      );
      expect(node.flagCode, 'de');
    });

    test('پرچم از منطقه زمانی گره خوانده می شود', () {
      // نام سرورهای اشتراک «tls_h2 grpc CDN vless» است و هیچ نام کشوری در
      // آن نیست؛ گزارش ۱٫۰۱۸ همین را نشان داد («چرا پرچم نمی دهد»).
      const VpnNode node = VpnNode(
        id: 'tz',
        name: 'سرور آمبرلا (خودکار) tls_h2 grpc CDN vless',
        protocol: NodeProtocol.vless,
        host: 'x',
        port: 443,
        sourceId: 's',
        params: <String, dynamic>{'timezone': 'Europe/Berlin'},
      );
      expect(node.flagCode, 'de');
    });

    test('نام فارسی کشور برای اعلان ویندوز', () {
      expect(countryNameFa('de'), 'آلمان');
      expect(countryNameFa('DE'), 'آلمان');
      expect(countryNameFa(''), isEmpty);
      // کد ناشناخته نباید نام جعلی بسازد.
      expect(countryNameFa('zz'), isEmpty);
    });

    test('پرچم از کد کشور داخل پارامترها اولویت دارد', () {
      const VpnNode node = VpnNode(
        id: 'b',
        name: 'سرور بی نام',
        protocol: NodeProtocol.vless,
        host: 'x',
        port: 443,
        sourceId: 's',
        params: <String, dynamic>{'countryCode': 'FR'},
      );
      expect(node.flagCode, 'fr');
    });
  });

  group('حالت اتصال', () {
    test('هسته یکی است؛ انتخاب کاربر حالت عبور ترافیک است', () {
      // هسته هیدیفای تنها هسته نسخه است، پس گزینه «کدام هسته» وجود ندارد.
      expect(CorePreference.values, <CorePreference>[
        CorePreference.auto,
        CorePreference.tun,
        CorePreference.systemProxy,
      ]);
    });

    test('هر حالت آیکون و نام خودش را دارد', () {
      final Set<IconData> icons =
          CorePreference.values.map((CorePreference item) => item.icon).toSet();
      final Set<String> names =
          CorePreference.values.map((CorePreference item) => item.faName).toSet();
      expect(icons.length, CorePreference.values.length);
      expect(names.length, CorePreference.values.length);
    });

    test('همه حالت ها در دسترس اند و نام و توضیح فارسی دارند', () {
      for (final CorePreference item in CorePreference.values) {
        expect(item.available, isTrue);
        expect(item.faName.trim(), isNotEmpty);
        expect(item.description.trim(), isNotEmpty);
      }
    });

    test('حالت خودکار و تونل، تونل کامل را ترجیح می دهند', () {
      expect(CorePreference.auto.prefersTun, isTrue);
      expect(CorePreference.tun.prefersTun, isTrue);
      expect(CorePreference.systemProxy.prefersTun, isFalse);
    });
  });

  group('تنظیمات هسته', () {
    test('پیش فرض خودکار است و در JSON ذخیره و خوانده می شود', () {
      const AppSettings settings = AppSettings();
      expect(settings.corePreference, CorePreference.auto);
      final AppSettings saved =
          settings.copyWith(corePreference: CorePreference.tun);
      final AppSettings restored = AppSettings.fromJson(saved.toJson());
      expect(restored.corePreference, CorePreference.tun);
      final AppSettings regional = settings.copyWith(serverRegionCode: 'ca');
      final AppSettings restoredRegion = AppSettings.fromJson(regional.toJson());
      expect(restoredRegion.serverRegionCode, 'ca');
      expect(const AppSettings().serverRegionCode, 'all');
    });
  });

  group('حالت انتخاب سرور', () {
    test('هر حالت نام و توضیح فارسی و آیکون دارد', () {
      for (final SelectionMode mode in SelectionMode.values) {
        expect(mode.faName.trim(), isNotEmpty);
        expect(mode.description.trim(), isNotEmpty);
      }
    });
  });

  group('دستگاه من', () {
    test('خلاصه و برچسب های دستگاه کاملاً فارسی و با ارقام فارسی هستند', () {
      const DeviceProfile device = DeviceProfile(
        hostname: 'PC',
        os: 'Windows 11 (build 26200)',
        osEdition: 'Professional',
        osDisplayVersion: '24H2',
        osBuild: 26200,
        arch: 'x64',
        cpu: '12th Gen Intel(R) Core(TM) i7-12700H @ 2.30GHz',
        cpuCores: 12,
        ramTotalMb: 16384,
        ramUsedMb: 8192,
        ramLoadPercent: 50,
        diskTotalMb: 524288,
        diskFreeMb: 262144,
        screenWidth: 1920,
        screenHeight: 1080,
        hasBattery: true,
        batteryPercent: 85,
        powerPlugged: true,
        uptimeSeconds: 90060,
        adapterName: 'Wi-Fi',
        localIp: '192.168.1.5',
      );
      expect(device.deviceName, 'PC');
      expect(device.formFactorFa, 'رایانه همراه ویندوز');
      expect(device.osTitleFa, 'ویندوز ۱۱ حرفه ای');
      expect(device.osLabelFa, 'ویندوز ۱۱ حرفه ای • ساخت ۲۶٬۲۰۰');
      expect(device.osVersionLabelFa, 'نگارش ۲۴ نیمه دوم');
      expect(device.archLabelFa, '۶۴ بیتی');
      expect(device.platformLabel, 'ویندوز ۱۱ حرفه ای • ساخت ۲۶٬۲۰۰ • ۶۴ بیتی');
      expect(device.cpuLabelFa, contains('اینتل کور آی ۷'));
      expect(device.cpuLabelFa, contains('نسل ۱۲'));
      expect(device.cpuLabelFa, contains('۲٫۳۰ گیگاهرتز'));
      expect(device.screenLabelFa, '۱٬۹۲۰ در ۱٬۰۸۰ پیکسل');
      expect(device.powerLabelFa, '۸۵ درصد (متصل به شارژر)');
      expect(RegExp(r'[A-Za-z0-9]').hasMatch(device.platformLabel), isFalse);
      expect(RegExp(r'[A-Za-z0-9]').hasMatch(device.cpuLabelFa), isFalse);
      expect(RegExp(r'[A-Za-z0-9]').hasMatch(device.screenLabelFa), isFalse);
      expect(RegExp(r'[A-Za-z0-9]').hasMatch(device.powerLabelFa), isFalse);
      expect(device.adapterLabelFa, 'کارت شبکه بی سیم');
      expect(device.ramTotalGb, closeTo(16.0, 0.01));
      expect(device.ramUsedGb, closeTo(8.0, 0.01));
      expect(device.ramPercent, 50);
      expect(device.diskTotalGb, closeTo(512.0, 0.01));
      expect(device.diskFreeGb, closeTo(256.0, 0.01));
      expect(device.diskPercent, closeTo(50.0, 0.01));
      expect(device.summary.contains('PC'), isTrue);
      expect(device.summary.contains('۱۹۲.۱۶۸.۱.۵'), isTrue);
    });
  });
}
