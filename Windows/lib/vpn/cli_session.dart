import 'dart:convert';
import 'dart:io';

import '../core/app_config.dart';
import '../core/storage.dart';
import '../core/utils.dart';
import '../models/models.dart';
import 'hiddify_core.dart';

/// پنجره خط فرمان هسته: `UmbrellaCli run -c ...`
///
/// چرا پنجره دیده می شود؟ فایل `UmbrellaCli.exe` همان `HiddifyCli.exe` است و
/// آن یک برنامه کنسولی است (زیرسیستم console). هیدیفای هم برای همین یک پنجره
/// سیاه کنار برنامه دارد: هسته ای که در آن اجرا می شود خودش یک برنامه خط فرمان
/// است، نه بخشی از پنجره گرافیکی. تفاوت این نسخه با هیدیفای فقط نام فایل هاست.
///
/// همان هسته دو راه برای اجرا دارد و مستنداتش هر دو را توضیح می دهد:
///
/// * `run -c <links> -d <settings> [--tun|--system-proxy]` — کاربر لینک،
///   اشتراک، فایل کلش، ایکس ری یا وایرگارد می دهد و هسته خودش پیکربندی، دی ان
///   اس و مسیرها را می سازد. آمبرلا همین را اجرا می کند.
/// * `core --base-dir ... --listen 127.0.0.1:17078 --owner-pid <pid>` — حالت
///   خود هسته برای «فرایند جدا از رابط کاربری»؛ یک خط
///   `HIDDIFY_CORE_READY <cert>` روی خروجی می دهد و با رفتن برنامه می ایستد.
///
/// حالت اول برای ما کافی و روشن تر است: یک پنجره، یک هسته، گزارش زنده جلوی
/// چشم کاربر.
class CliSession {
  CliSession._();

  static final CliSession instance = CliSession._();

  Process? _process;

  /// آیا پنجره خط فرمان باز است؟
  bool get running => _process != null;

  /// ثبت فرایندی که خودمان باز کرده ایم تا هنگام قطع بسته شود.
  void adopt(Process process) {
    _process = process;
    process.exitCode.whenComplete(() {
      _process = null;
    });
  }

  Future<void> close() async {
    final Process? process = _process;
    _process = null;
    if (process == null) {
      return;
    }
    try {
      process.kill();
    } on ProcessException {
      // فرایند از قبل بسته شده است.
    }
  }

  /// فایل اجرایی پنجره. همان `UmbrellaCli.exe` که نصب کننده کنار برنامه
  /// می گذارد.
  static String executable() {
    final String exe = Platform.resolvedExecutable;
    final String dir =
        exe.substring(0, exe.lastIndexOf(Platform.pathSeparator));
    final String cli = '$dir${Platform.pathSeparator}${HiddifyCore.cliBinary}';
    return File(cli).existsSync() ? cli : exe;
  }

  /// باز کردن پنجره ترمینال با آرگومان های داده شده.
  ///
  /// ویندوز: `start` یک پنجره کنسول تازه برای همان فایل کنسولی باز می کند.
  static Future<bool> open(List<String> args) async {
    final String exe = executable();
    try {
      if (Platform.isWindows) {
        final Process process = await Process.start(
          'cmd.exe',
          <String>['/c', 'start', '"${UmbrellaCli.title}"', '"$exe"', ...args],
          mode: ProcessStartMode.detached,
        );
        instance.adopt(process);
        return true;
      }
      final Process process =
          await Process.start(exe, args, mode: ProcessStartMode.detached);
      instance.adopt(process);
      return true;
    } on ProcessException {
      return false;
    }
  }

  /// نوشتن فایل جلسه در پوشه اجرا و برگرداندن مسیر آن.
  ///
  /// چرا فایل؟ اگر مسیر نصب یا نام سرور فارسی و بلند باشد، گذاشتن همه چیز در
  /// خط فرمان ویندوز شکننده است. هسته هم همین کار را می کند: تنظیمات را از
  /// یک فایل JSON می خواند.
  static Future<String> writeSession(
    CliSessionFile file,
    String runDir,
  ) async {
    await Directory(runDir).create(recursive: true);
    final String path =
        '$runDir${Platform.pathSeparator}umbrella-cli.json';
    await File(path)
        .writeAsString(jsonEncode(file.toJson()), flush: true);
    return path;
  }

  /// باز کردن پنجره ترمینال برای فایل جلسه.
  ///
  /// فرمان: `cmd /c start "<title>" /D <workDir> "<exe>" <args...>`. ویندوز
  /// همان را در یک کنسول تازه اجرا می کند و کاربر گزارش زنده هسته را می بیند.
  static Future<bool> openWindow({
    required String session,
    required String title,
  }) async {
    final CliSessionFile? file = CliSessionFile.parse(
      await File(session).readAsString(),
    );
    if (file == null || file.exe.isEmpty) {
      return false;
    }
    // نقل قول هر آرگومان جدا انجام می شود تا مسیرهای دارای فاصله سالم بمانند.
    final String command = '"${file.exe}" '
        '${file.args.map(_quote).join(' ')}';
    try {
      final Process shell = await Process.start(
        'cmd.exe',
        <String>[
          '/c',
          'start',
          '"${title.isEmpty ? UmbrellaCli.title : title}"',
          if (file.workDir.isNotEmpty) ...<String>['/D', file.workDir],
          command,
        ],
        mode: ProcessStartMode.detached,
      );
      instance.adopt(shell);
      return true;
    } on ProcessException {
      return false;
    }
  }

  /// نقل قول یک آرگومان برای خط فرمان ویندوز.
  static String _quote(String arg) =>
      arg.contains(' ') ? '"$arg"' : arg;

  /// عنوان پنجره.
  static String titleFor(VpnNode node, AppSettings settings) {
    final String mode =
        settings.tunMode ? 'تونل کامل' : 'پروکسی سیستمی';
    return 'Umbrella CLI — ${node.name} — $mode';
  }

  /// پورت نشانی gRPC که پنجره هسته روی آن گوش می دهد.
  static int get listenPort => AppConfig.coreGrpcPort;

  /// پوشه داده هسته.
  static String baseDirOf(String dataDir) =>
      '$dataDir${Platform.pathSeparator}core';

  /// آیا کاربر پنجره خط فرمان را خواسته است؟ پیش فرض بله، مثل خود هیدیفای.
  static bool wanted(AppSettings settings) => settings.showCli;

  /// کلید ذخیره سازی انتخاب کاربر.
  static const String storeKey = StoreKeys.showCli;
}

/// نوشتن فایل جلسه برای پنجره ترمینال.
///
/// همه مسیرها در یک فایل JSON می آیند تا خط فرمان کوتاه بماند و مسیرهای فارسی
/// یا طولانی مشکلی نسازند.
class CliSessionFile {
  const CliSessionFile({
    required this.exe,
    required this.args,
    required this.workDir,
    required this.coreName,
    required this.logPath,
    required this.title,
    this.env = const <String, String>{},
  });

  final String exe;
  final List<String> args;
  final String workDir;
  final String coreName;
  final String logPath;
  final String title;
  final Map<String, String> env;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'exe': exe,
        'args': args,
        'workDir': workDir,
        'core': coreName,
        'log': logPath,
        'title': title,
        'env': env,
      };

  static CliSessionFile fromJson(Map<String, dynamic> json) {
    return CliSessionFile(
      exe: JsonX.text(json['exe']),
      args: JsonX.asList(json['args'])
          .map((Object? item) => item.toString())
          .toList(),
      workDir: JsonX.text(json['workDir']),
      coreName: JsonX.text(json['core']),
      logPath: JsonX.text(json['log']),
      title: JsonX.text(json['title'], UmbrellaCli.title),
      env: JsonX.asMap(json['env']).map<String, String>(
        (String key, Object? value) => MapEntry<String, String>(key, '$value'),
      ),
    );
  }

  static CliSessionFile? parse(String raw) {
    if (raw.trim().isEmpty) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final CliSessionFile file = CliSessionFile.fromJson(JsonX.asMap(decoded));
      if (file.exe.isEmpty) {
        return null;
      }
      return file;
    } on FormatException {
      return null;
    }
  }
}

/// ثابت های نام پنجره.
class UmbrellaCli {
  const UmbrellaCli._();

  /// عنوان پنجره در نوار وظیفه ویندوز.
  static const String title = 'Umbrella CLI';

  /// پیشوند خط آمادگی هسته. هسته خودش `HIDDIFY_CORE_READY` را چاپ می کند؛
  /// این نام برای جایی است که خودمان خط وضعیت می نویسیم.
  static const String readyPrefix = 'UMBRELLA_CORE_READY ';

  /// پیشوند خط خطا.
  static const String errorPrefix = 'UMBRELLA_CORE_ERROR ';

  /// نام متغیر محیطی رمز راه اندازی هسته.
  static const String secretEnv = 'HIDDIFY_CORE_SECRET';
}
