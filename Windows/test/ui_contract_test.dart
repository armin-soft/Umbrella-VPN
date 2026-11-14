import 'dart:convert';
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
        'هسته اتصال',
        'مدت اتصال',
        'حالت اتصال',
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
      expect(page.contains('هسته اتصال'), isTrue);
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

  group('هسته', () {
    test('تنها هسته همراه نسخه، موتور هسته است', () {
      final String manifest = read('assets/cores/manifest.json');
      final Map<String, dynamic> json =
          jsonDecode(manifest) as Map<String, dynamic>;
      final List<dynamic> cores = json['cores'] as List<dynamic>;
      expect(cores.length, 1);
      final Map<String, dynamic> core = cores.first as Map<String, dynamic>;
      expect(core['id'], 'hiddify');
      expect(core['cli_prefix'], 'umbrella');
      expect(core['binary'], 'UmbrellaCli.exe');
      expect(core['inside'], 'hiddify-core.dll');
      final String text = manifest.toLowerCase();
      for (final String gone in <String>[
        'sing-box',
        'xray',
        'mihomo',
        'clash-meta',
        'mieru',
        'wireguard-go',
        'amneziawg',
      ]) {
        expect(text.contains(gone), isFalse, reason: gone);
      }
    });

    test('هسته با خط فرمان خودش اجرا می شود', () {
      final String core = read('lib/vpn/umbrella_core.dart');
      expect(core.contains("'run'"), isTrue);
      expect(core.contains("'-c'"), isTrue);
      expect(core.contains("'--in-proxy-port'"), isTrue);
      expect(core.contains("'--tun'"), isTrue);
      expect(core.contains("'--system-proxy'"), isTrue);
      // لانچرهای آمبرلا، با همان آرگومان های خط فرمان موتور.
      expect(core.contains('UmbrellaCli.exe'), isTrue);
      expect(core.contains('UmbrellaCoreEngine.exe'), isTrue);
    });

    test('هیچ هسته دستی دیگری اجرا نمی شود', () {
      for (final String path in <String>[
        'lib/vpn/vpn_controller.dart',
        'lib/vpn/core_ping.dart',
        'lib/vpn/cores.dart',
      ]) {
        final String text = read(path);
        for (final String gone in <String>[
          'sing-box.exe',
          'xray.exe',
          'mihomo.exe',
          'mieru.exe',
          'amneziawg.exe',
        ]) {
          expect(text.contains(gone), isFalse, reason: '$path → $gone');
        }
      }
    });

    test('نام سرور در گزارش ها دوبار «سرور» نمی گیرد', () {
      final String controller = read('lib/vpn/vpn_controller.dart');
      expect(controller.contains('سرور سرور'), isFalse);
      expect(controller.contains('_nodeLabel'), isTrue);
    });
  });

  group('فایل های اجرایی هسته', () {
    test('لانچر کتابخانه را از مسیر بار می کند، نه با پیوند نام', () {
      // اگر نام کتابخانه در جدول واردات فایل اجرایی باشد، ویندوز آن را با
      // 0xC0000135 می بندد (همان خطای ۱٫۰٫۲). لانچر باید خودش بارش کند.
      final String launcher = read('native/umbrella_launcher.c');
      expect(launcher.contains('LoadLibraryExW'), isTrue);
      expect(launcher.contains('GetProcAddress'), isTrue);
      expect(launcher.contains('"parseCli"'), isTrue);
      expect(launcher.contains('SetDllDirectoryW'), isTrue);
      expect(launcher.contains('CommandLineToArgvW'), isTrue);
      // هیچ جا امضای dllimport ندارد.
      expect(launcher.contains('__declspec(dllimport) parseCli'), isFalse);
    });

    test('هر سه فایل اجرایی از همان منبع و با آیکون آمبرلا ساخته می شوند', () {
      final String cmake = read('windows/CMakeLists.txt');
      for (final String exe in <String>[
        'UmbrellaCli',
        'UmbrellaAdmin',
        'UmbrellaCoreEngine',
      ]) {
        expect(cmake.contains('OUTPUT_NAME "$exe"'), isTrue, reason: exe);
      }
      final String res = read('native/umbrella_launcher.rc');
      expect(res.contains('app_icon.ico'), isTrue);
      expect(res.contains('فیلترشکن آمبرلا'), isTrue);
      // آیکون با شناسه 1، همان چیزی که Explorer و پنجره UAC می خوانند.
      expect(res.contains('1 ICON'), isTrue);
      // مانیفست مدیر با گزینه پیوند دهنده اضافه می شود.
      expect(cmake.contains('requireAdministrator'), isTrue);
    });

    test('هیچ متن نمایشی در برنامه نام هیدیفای ندارد', () {
      // خطوط توضیحی (کامنت) می توانند برای سازنده از هیدیفای حرف بزنند؛ آنچه
      // ممنوع است، متن هایی است که به کاربر نشان داده می شود.
      final List<File> files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File file) => file.path.endsWith('.dart'))
          .toList();
      expect(files, isNotEmpty);
      // چند مورد عمدی است و مجاز: شناسه هسته در فهرست همراه نسخه، نام کتابخانه
      // روی دیسک (نامش ثبت شده و عوض کردنش اتصال را می شکند) و پیشوند نام
      // آداپتور تونل (فقط برای خواندن آمار، هیچ جا نمایش داده نمی شود).
      const List<String> allowed = <String>[
        "static const String id = 'hiddify';",
        "static const String coreDll = 'hiddify-core.dll';",
        "static const String tunAdapterHint = 'hiddify';",
      ];
      for (final File file in files) {
        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final String line = lines[i].trimLeft();
          if (line.startsWith('//')) {
            continue;
          }
          if (allowed.any((String ok) => line.contains(ok))) {
            continue;
          }
          final String lower = line.toLowerCase();
          expect(lower.contains('هیدیفای'), isFalse,
              reason: '${file.path}:${i + 1} → $line');
          expect(lower.contains('hiddify'), isFalse,
              reason: '${file.path}:${i + 1} → $line');
        }
      }
      expect(read('lib/main.dart').contains('هسته آمبرلا آماده است'), isTrue);
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
