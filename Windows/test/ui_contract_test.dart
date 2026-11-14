import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// آزمون «قرارداد رابط کاربری»: قواعدی که کاربر صریحا خواسته و نباید بی صدا
/// برگردند. این آزمون کد را می خواند نه صفحه را، پس سریع است و در CI همیشه
/// جلوی بازگشت آن رفتارها را می گیرد.
void main() {
  String read(String path) => File(path).readAsStringSync();

  group('دکمه لغو اتصال', () {
    test('صفحه اتصال دکمه «لغو اتصال» دارد', () {
      final String page = read('lib/ui/pages/connect_page.dart');
      expect(page.contains('لغو اتصال'), isTrue);
      expect(page.contains('_cancelConnection'), isTrue);
    });

    test('کنترلر اتصال متد لغو دارد و حلقه تلاش را می شکند', () {
      final String controller = read('lib/vpn/vpn_controller.dart');
      expect(controller.contains('Future<void> cancel()'), isTrue);
      expect(controller.contains('_cancelRequested'), isTrue);
      expect(controller.contains('cancelled'), isTrue);
    });
  });

  group('صفحه اتصال', () {
    test('بخش پایین که نام سرور را نشان می داد حذف شده است', () {
      final String page = read('lib/ui/pages/connect_page.dart');
      expect(page.contains('_ActiveServerBar'), isFalse);
      expect(page.contains('_MiniStat'), isFalse);
    });

    test('آی پی دستگاه هرگز نامشخص نیست', () {
      final String page = read('lib/ui/pages/connect_page.dart');
      expect(page.contains('_deviceIp'), isTrue);
      // آی پی هیچ وقت خط تیره نمی شود.
      expect(page.contains("'—'"), isFalse);
    });
  });

  group('منوی کناری', () {
    test('نام سازنده در پایین منو نمایش داده نمی شود', () {
      final String nav = read('lib/ui/widgets/shell_widgets.dart');
      expect(nav.contains('AppConfig.developer'), isFalse);
      expect(nav.contains('آرمین سافت'), isFalse);
    });
  });

  group('دستگاه من', () {
    test('فقط اطلاعات دستگاه را نشان می دهد', () {
      // فقط خطوط کد بررسی می شوند؛ توضیح بالای فایل می تواند این واژه ها را
      // برای توضیح جابه جایی داشته باشد.
      final List<String> code = read('lib/ui/pages/device_page.dart')
          .split('\n')
          .where((String line) => !line.trimLeft().startsWith('//'))
          .toList();
      for (final String moved in <String>[
        'هسته انتخابی',
        'مدت اتصال',
        'حالت اتصال',
        'نوع سرویس',
        'سرور فعال',
        'تایید عبور ترافیک',
      ]) {
        expect(
          code.any((String line) => line.contains(moved)),
          isFalse,
          reason: '$moved باید در صفحه دیگری باشد',
        );
      }
    });

    test('اطلاعات اتصال جای مخصوص خودش را دارد', () {
      final String page = read('lib/ui/pages/connection_page.dart');
      expect(page.contains('وضعیت اتصال'), isTrue);
      expect(page.contains('هسته انتخابی'), isTrue);
      // فراموش شدن این واردات، ساخت ویندوز را با «VpnController isn't a type»
      // می شکست؛ حالا آزمون هم جلوی آن را می گیرد.
      expect(page.contains("import '../../vpn/vpn_controller.dart';"), isTrue);
    });
  });

  group('اعلان ها', () {
    test('اعلان تازه با صدا اعلام می شود', () {
      final String auth = read('lib/state/auth_controller.dart');
      expect(auth.contains("_sound?.play('notify')"), isTrue);
      expect(auth.contains('_announce('), isTrue);
    });

    test('صدای اعلان در دارایی های برنامه هست', () {
      expect(File('assets/sounds/notify.wav').existsSync(), isTrue);
      final String pubspec = read('pubspec.yaml');
      expect(pubspec.contains('assets/sounds/'), isTrue);
    });
  });

  group('هسته ها', () {
    test('کلیدهای حذف شده سینگ باکس هیچ جا نوشته نمی شوند', () {
      final String builders = read('lib/vpn/config_builders.dart');
      expect(builders.contains("'gso_max_size'"), isFalse);
      expect(builders.contains("'gso':"), isFalse);
    });

    test('انتقال xhttp فقط در ایکس ری ساخته می شود', () {
      // سینگ باکس انتقال xhttp ندارد؛ پیکربندی آن هسته برای این سرورها باید
      // کنار گذاشته شود و ایکس ری (که xhttp دارد) اجرا شود.
      final String builders = read('lib/vpn/config_builders.dart');
      expect(builders.contains("case 'xhttp':"), isTrue);
      expect(builders.contains("'xhttpSettings'"), isTrue);
      expect(
        builders.contains("case 'xhttp':\n      case 'splithttp':\n        return null;"),
        isTrue,
      );
    });

    test('پیکربندی خود پنل با کلش متا اجرا می شود', () {
      final String controller = read('lib/vpn/vpn_controller.dart');
      expect(controller.contains('_buildClashPlan'), isTrue);
      expect(controller.contains('applyClashProfile'), isTrue);
      final String clash = read('lib/vpn/clash_config.dart');
      expect(clash.contains('clash-meta.yaml'), isTrue);
    });
  });

  group('اشتراک', () {
    test('مسیر مرده mihomo جایی ساخته نمی شود', () {
      for (final String path in <String>[
        'lib/core/app_config.dart',
        'lib/data/subscription_endpoints.dart',
      ]) {
        final String text = read(path);
        expect(text.contains("'mihomo/all.yml'"), isFalse, reason: path);
      }
    });

    test('مسیر درست کلش متا در فهرست است', () {
      final String endpoints = read('lib/data/subscription_endpoints.dart');
      expect(endpoints.contains("'clash/meta/all.yml'"), isTrue);
    });
  });
}
