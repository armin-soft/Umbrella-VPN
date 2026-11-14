import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/vpn/cli_session.dart';
import 'package:umbrella_vpn/vpn/umbrella_core.dart';

/// آزمون «پنجره CLI» و راه اندازی هسته.
///
/// کاربر پرسیده بود چرا هنگام اتصال یک پنجره ترمینال باز می شود. پاسخ در
/// [UmbrellaCore] و [CliSession] مستند شده است: موتور به شکل یک برنامه خط
/// فرمان (`UmbrellaCli.exe`) اجرا می شود و ویندوز برای آن پنجره کنسول می سازد.
/// این آزمون ها همان قرارداد را قفل می کنند.
void main() {
  group('هسته', () {
    test('نام فایل های اجرایی برند آمبرلاست', () {
      expect(UmbrellaCore.cliBinary, 'UmbrellaCli.exe');
      expect(UmbrellaCore.engineBinary, 'UmbrellaCoreEngine.exe');
      expect(UmbrellaCore.id, 'hiddify');
    });

    test('نام های قدیمی هیچ جا نمی مانند', () {
      expect(UmbrellaCore.cliBinary.contains('Hiddify'), isFalse);
      expect(UmbrellaCore.engineBinary.contains('Hiddify'), isFalse);
    });

    test('پورت پروکسی محلی همان پورت پیش فرض هسته است', () {
      expect(UmbrellaCore.port, 12334);
    });

    test('کتابخانه هسته هم نام آمبرلا دارد', () {
      // تغییر نام فقط چون لانچر ما کتابخانه را با مسیر بار می کند بی خطر است؛
      // با پیوند نام، همین کار خطای 0xC0000135 نسخه ۱٫۰٫۲ را می داد.
      expect(UmbrellaCore.coreDll, 'UmbrellaCore.dll');
      expect(UmbrellaCore.cronetDll, 'libcronet.dll');
    });

    test('هر سه فایل اجرایی نام آمبرلا دارند', () {
      // این ها لانچرهای خود ما هستند و هیچ وقت نام هیدیفای ندارند.
      for (final String name in <String>[
        UmbrellaCore.cliBinary,
        UmbrellaCore.engineBinary,
        UmbrellaCore.adminBinary,
      ]) {
        expect(name.startsWith('Umbrella'), isTrue, reason: name);
        expect(name.toLowerCase().contains('hiddify'), isFalse, reason: name);
        expect(name.endsWith('.exe'), isTrue, reason: name);
      }
    });

    test('نبود یکی از فایل های هسته نصب را ناقص اعلام می کند', () {
      // پوشه ای که وجود ندارد هم «نصب نیست» است، بدون استثنا.
      expect(UmbrellaCore.installed(r'C:\NoSuchFolder\Umbrella'), isFalse);
    });

    test('پوشه برنامه از پوشه هسته جدا می شود', () {
      // لانچرها کنار برنامه اند و کتابخانه در پوشه هسته؛ بررسی نصب باید هر دو
      // جا را بداند.
      expect(
        UmbrellaCore.rootOf(r'C:\App\cores\umbrella'),
        r'C:\App',
      );
      expect(UmbrellaCore.rootOf(r'C:\App\cores'), r'C:\App');
      expect(UmbrellaCore.rootOf(r'C:\App'), r'C:\App');
      expect(
        UmbrellaCore.directoryOf(UmbrellaCore.rootOf(r'C:\App\cores\umbrella')),
        r'C:\App\cores\umbrella',
      );
    });

    test('پوشه هسته در نسخه نصب', () {
      expect(
        UmbrellaCore.directoryOf(r'C:\Program Files\Umbrella'),
        endsWith(r'cores\umbrella'),
      );
      // پوشه cores هم پذیرفته می شود و یک بار بیشتر تودرتو نمی شود.
      expect(
        UmbrellaCore.directoryOf(r'C:\Program Files\Umbrella\cores'),
        r'C:\Program Files\Umbrella\cores\umbrella',
      );
    });
  });

  group('پنجره CLI', () {
    test('تنظیمات پنجره با کلید کاربر کنترل می شود', () {
      expect(CliSession.storeKey, 'cli.show');
    });

    test('فایل جلسه همه چیز لازم را نگه می دارد', () {
      final CliSessionFile file = CliSessionFile(
        exe: r'C:\Program Files\Umbrella\UmbrellaCli.exe',
        args: <String>['run', '-c', r'C:\Users\a\links.txt'],
        workDir: r'C:\Program Files\Umbrella\cores\umbrella',
        coreName: 'UmbrellaCli.exe',
        logPath: r'C:\Users\a\AppData\Roaming\Umbrella\run\umbrella-core.log',
        title: 'Umbrella CLI',
      );
      final CliSessionFile? parsed =
          CliSessionFile.parse(jsonEncode(file.toJson()));
      expect(parsed, isNotNull);
      expect(parsed!.exe, file.exe);
      expect(parsed.args, file.args);
      expect(parsed.workDir, file.workDir);
      expect(parsed.title, 'Umbrella CLI');
      expect(file.args.first, 'run');
      expect(file.exe, contains('UmbrellaCli.exe'));
    });

    test('فایل جلسه خالی رد می شود', () {
      expect(CliSessionFile.parse(''), isNull);
      expect(CliSessionFile.parse('{'), isNull);
    });
  });
}
