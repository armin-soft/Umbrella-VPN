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

  group('انتخاب هسته', () {
    test('هر هسته آیکون و نام خودش را دارد', () {
      final Set<IconData> icons =
          CorePreference.values.map((CorePreference item) => item.icon).toSet();
      final Set<String> names =
          CorePreference.values.map((CorePreference item) => item.faName).toSet();
      expect(icons.length, CorePreference.values.length);
      expect(names.length, CorePreference.values.length);
    });

    test('آمنزیا در این نسخه در دسترس نیست و بقیه در دسترس اند', () {
      expect(CorePreference.amnezia.available, isFalse);
      expect(CorePreference.auto.available, isTrue);
      expect(CorePreference.xray.available, isTrue);
      expect(CorePreference.clash.available, isTrue);
      expect(CorePreference.wireguard.available, isTrue);
      expect(CorePreference.mieru.available, isTrue);
    });

    test('نام فارسی هر هسته خالی نیست', () {
      for (final CorePreference item in CorePreference.values) {
        expect(item.faName.trim(), isNotEmpty);
      }
    });
  });

  group('تنظیمات هسته', () {
    test('پیش فرض خودکار است و در JSON ذخیره و خوانده می شود', () {
      const AppSettings settings = AppSettings();
      expect(settings.corePreference, CorePreference.auto);
      final AppSettings saved =
          settings.copyWith(corePreference: CorePreference.mieru);
      final AppSettings restored = AppSettings.fromJson(saved.toJson());
      expect(restored.corePreference, CorePreference.mieru);
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
    test('خلاصه دستگاه اطلاعات کلیدی را دارد', () {
      const DeviceProfile device = DeviceProfile(
        hostname: 'PC',
        os: 'Windows 11',
        localIp: '192.168.1.5',
      );
      expect(device.deviceName, 'PC');
      expect(device.platformLabel, 'Windows 11 | x64');
      expect(device.summary.contains('PC'), isTrue);
    });
  });
}
