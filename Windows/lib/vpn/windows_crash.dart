import 'dart:io';

import '../core/persian.dart';
import '../platform/services.dart';
import 'umbrella_core.dart';

/// استخراج دلیل سقوط بومی هسته از گزارش رویداد ویندوز (رویداد شماره ۱۰۰۰) و
/// خروجی خطای زمان اجرا، بدون افشای نشانی سرور یا کلیدهای کاربر.
class WindowsCrash {
  const WindowsCrash._();

  static final RegExp _eventPattern = RegExp(r'<Event\b.*?</Event>', dotAll: true);
  static final RegExp _dataPattern = RegExp(r'<Data>(.*?)</Data>', dotAll: true);

  /// استخراج خلاصه سقوط از خروجی متنی هسته (پانیک Go یا خطای زمان اجرا).
  static String goCrashHeadline(String output) {
    if (output.trim().isEmpty) return '';
    final List<String> lines = AppLogger.redact(output)
        .split(RegExp(r'\r?\n'))
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList();
    for (final String line in lines) {
      final String lower = line.toLowerCase();
      if (lower.startsWith('panic:') ||
          lower.startsWith('fatal error:') ||
          lower.startsWith('runtime:') ||
          lower.startsWith('[signal ') ||
          RegExp(r'^sig[a-z]+:', caseSensitive: false).hasMatch(line)) {
        return line.length > 220 ? '${line.substring(0, 219)}…' : line;
      }
    }
    return '';
  }

  /// استخراج خطای رویداد شماره ۱۰۰۰ ویندوز برای شناسه فرایند [pid] از XML.
  ///
  /// چیدمان استاندارد EventData برای Application Error:
  /// `[0]` نام برنامه، `[3]` ماژول معیوب، `[6]` کد استثنا، `[7]` آفست،
  /// `[8]` شناسه فرایند به مبنای شانزده (مثل `0x1a34`).
  static String applicationErrorFor(String xml, int pid) {
    if (xml.isEmpty || pid <= 0) return '';
    final String expectedHex = '0x${pid.toRadixString(16)}';
    for (final RegExpMatch eventMatch in _eventPattern.allMatches(xml)) {
      final String block = eventMatch.group(0)!;
      final List<String> data = _dataPattern
          .allMatches(block)
          .map((RegExpMatch m) => m.group(1)!.trim())
          .toList();
      if (data.length <= 8) continue;
      final String eventPid = data[8].toLowerCase();
      if (eventPid != expectedHex && eventPid != '$pid') {
        continue;
      }
      final String module = _safeModuleName(data[3]);
      final String codeText = data[6];
      final int? parsedCode = int.tryParse(
        codeText.replaceFirst(RegExp(r'^0x', caseSensitive: false), ''),
        radix: 16,
      );
      final String decoded = parsedCode == null
          ? ''
          : UmbrellaCore.describeWindowsExitCode(parsedCode);
      if (decoded.isNotEmpty) {
        return module.isEmpty ? decoded : '$decoded (بخش: $module)';
      }
      return module.isEmpty
          ? 'هسته به دلیل خطای سیستمی ویندوز متوقف شد (کد ${Fa.num(codeText)}).'
          : 'هسته در بخش $module با خطای سیستمی متوقف شد (کد ${Fa.num(codeText)}).';
    }
    return '';
  }

  static String _safeModuleName(String raw) {
    final String clean = raw.trim().split(RegExp(r'[/\\]')).last;
    if (clean.isEmpty) return '';
    final String lower = clean.toLowerCase();
    if (lower == 'libcronet.dll') return 'کتابخانه کرونت';
    if (lower == 'wintun.dll') return 'درایور تونل ویندوز';
    if (lower == 'umbrellacore.dll' || lower == 'core.dll') return 'هسته آمبرلا';
    if (lower == 'ntdll.dll' || lower == 'kernelbase.dll' || lower == 'kernel32.dll') {
      return 'کتابخانه سیستم عامل';
    }
    return '';
  }

  /// خواندن غیرمسدودکننده گزارش خطای ویندوز وقتی هسته بی صدا متوقف شده است.
  static Future<String> lookupApplicationError(
    int pid, {
    Duration retryBudget = const Duration(milliseconds: 1200),
  }) async {
    if (!Platform.isWindows || pid <= 0) return '';
    final DateTime deadline = DateTime.now().add(retryBudget);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final ProcessResult result = await Process.run(
          'wevtutil',
          <String>[
            'qe',
            'Application',
            '/q:*[System[EventID=1000]]',
            '/f:RenderedXml',
            '/c:25',
            '/rd:true',
          ],
          runInShell: false,
        ).timeout(const Duration(seconds: 2));
        if (result.exitCode == 0) {
          final String found =
              applicationErrorFor('${result.stdout}', pid);
          if (found.isNotEmpty) {
            return found;
          }
        }
      } on Object {
        return '';
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return '';
  }
}
