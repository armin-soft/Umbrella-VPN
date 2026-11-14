import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/vpn/cli_session.dart';
import 'package:umbrella_vpn/vpn/hiddify_core.dart';

/// آزمون «پنجره CLI» و راه اندازی هسته.
///
/// کاربر پرسیده بود چرا هیدیفای هنگام اتصال یک پنجره ترمینال باز می کند. پاسخ
/// در [HiddifyCore] و [CliSession] مستند شده است: موتور همان برنامه خط فرمان
/// (`HiddifyCli.exe` با نام `UmbrellaCli.exe`) است و ویندوز برای آن پنجره
/// کنسول می سازد. این آزمون ها همان قرارداد را قفل می کنند.
void main() {
  group('هسته هیدیفای', () {
    test('نام فایل ها همان نام های هیدیفای با برند آمبرلاست', () {
      expect(HiddifyCore.cliBinary, 'UmbrellaCli.exe');
      expect(HiddifyCore.engineBinary, 'UmbrellaCoreEngine.exe');
      expect(HiddifyCore.id, 'hiddify');
    });

    test('نام های قدیمی هیچ جا نمی مانند', () {
      expect(HiddifyCore.cliBinary.contains('Hiddify'), isFalse);
      expect(HiddifyCore.engineBinary.contains('Hiddify'), isFalse);
    });

    test('پورت پروکسی محلی همان پورت پیش فرض هسته است', () {
      expect(HiddifyCore.port, 12334);
    });

    test('فایل های همراه هسته هم نام برند دارند', () {
      // ویندوز کتابخانه را کنار خود فایل اجرایی می جوید، پس هر سه باید در
      // cores\hiddify باشند و هیچ کدام نام قدیمی نداشته باشد.
      expect(HiddifyCore.coreDll, 'UmbrellaCore.dll');
      expect(HiddifyCore.cronetDll, 'libcronet.dll');
      expect(HiddifyCore.coreDll.contains('hiddify'), isFalse);
    });

    test('نبود یکی از فایل های هسته نصب را ناقص اعلام می کند', () {
      // پوشه ای که وجود ندارد هم «نصب نیست» است، بدون استثنا.
      expect(HiddifyCore.installed(r'C:\NoSuchFolder\Umbrella'), isFalse);
    });

    test('پوشه هسته در نسخه نصب', () {
      expect(
        HiddifyCore.directoryOf(r'C:\Program Files\Umbrella'),
        endsWith(r'cores\hiddify'),
      );
      // پوشه cores هم پذیرفته می شود و یک بار بیشتر تودرتو نمی شود.
      expect(
        HiddifyCore.directoryOf(r'C:\Program Files\Umbrella\cores'),
        r'C:\Program Files\Umbrella\cores\hiddify',
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
        workDir: r'C:\Program Files\Umbrella\cores\hiddify',
        coreName: 'UmbrellaCli.exe',
        logPath: r'C:\Users\a\AppData\Roaming\Umbrella\run\hiddify-core.log',
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
