import 'dart:io';

import '../core/app_config.dart';
import 'services.dart';

/// نگهداری کوتاه مدت گزارش خطاهای پیش بینی نشده برنامه برای تشخیص سریع پس از
/// بسته شدن ناگهانی، همراه با پاک سازی خودکار گزارش های قدیمی تر از یک روز یا
/// مربوط به نسخه های پیشین برنامه.
class AppCrashStore {
  AppCrashStore._();

  static const Duration retention = Duration(days: 1);
  static const int maxReportsOnDisk = 10;
  static const int maxReportsPerRun = 20;
  static const String _fileSuffix = '-dart.txt';

  static Directory? _directory;
  static int _writtenThisRun = 0;

  static Future<List<String>> openAndPrune(
    Directory supportDirectory, {
    String? appVersion,
    DateTime? now,
  }) async {
    final Directory dir = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}app_crashes',
    );
    _directory = dir;
    _writtenThisRun = 0;
    try {
      await dir.create(recursive: true);
    } on FileSystemException {
      return const <String>[];
    }

    final String expectedVersion = appVersion ?? AppConfig.version;
    final DateTime clock = now ?? DateTime.now();
    final List<(DateTime, File, String)> kept = <(DateTime, File, String)>[];

    try {
      await for (final FileSystemEntity entity in dir.list()) {
        if (entity is! File) continue;
        final String name = entity.uri.pathSegments.isEmpty
            ? entity.path
            : entity.uri.pathSegments.last;
        if (!name.endsWith(_fileSuffix)) {
          await _deleteQuiet(entity);
          continue;
        }
        String text = '';
        DateTime stamp;
        try {
          text = await entity.readAsString();
          stamp = await entity.lastModified();
        } on FileSystemException {
          await _deleteQuiet(entity);
          continue;
        }
        final String fileVersion = _extractHeader(text, 'Umbrella-Version:');
        final bool sameVersion =
            fileVersion.isNotEmpty && fileVersion == expectedVersion;
        final bool fresh = clock.difference(stamp) <= retention;
        if (!sameVersion || !fresh) {
          await _deleteQuiet(entity);
          continue;
        }
        kept.add((stamp, entity, text));
      }
    } on FileSystemException {
      return const <String>[];
    }

    kept.sort((a, b) => b.$1.compareTo(a.$1));
    for (int i = maxReportsOnDisk; i < kept.length; i++) {
      await _deleteQuiet(kept[i].$2);
    }

    return kept
        .take(maxReportsOnDisk)
        .map(((DateTime, File, String) entry) => entry.$3.trim())
        .where((String text) => text.isNotEmpty)
        .toList(growable: false);
  }

  static void record({
    required Object error,
    StackTrace? stack,
    String source = 'dart',
    String? appVersion,
    DateTime? now,
  }) {
    final Directory? dir = _directory;
    if (dir == null || _writtenThisRun >= maxReportsPerRun) {
      return;
    }
    _writtenThisRun++;
    final DateTime clock = (now ?? DateTime.now()).toUtc();
    final String stamp = clock.toIso8601String().replaceAll(':', '-');
    final String safeMessage = AppLogger.redact('$error').trim();
    final String safeStack = _formatStack(stack);
    final String payload = <String>[
      'Umbrella-Version: ${appVersion ?? AppConfig.version}',
      'Recorded-At: ${clock.toIso8601String()}',
      'Source: $source',
      'Error: ${safeMessage.isEmpty ? 'unknown' : safeMessage}',
      if (safeStack.isNotEmpty) 'Stack:\n$safeStack',
    ].join('\n');

    try {
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final File target = File(
        '${dir.path}${Platform.pathSeparator}$stamp-$_writtenThisRun$_fileSuffix',
      );
      target.writeAsStringSync(payload, flush: true);
    } on FileSystemException {
      // Crash persistence must never re-enter error handlers.
    }
  }

  static String _formatStack(StackTrace? stack) {
    if (stack == null) return '';
    final List<String> lines = AppLogger.redact('$stack')
        .split('\n')
        .map((String line) => line.trimRight())
        .where((String line) => line.isNotEmpty)
        .take(18)
        .toList(growable: false);
    return lines.join('\n');
  }

  static String _extractHeader(String content, String prefix) {
    for (final String line in content.split('\n')) {
      final String trimmed = line.trim();
      if (trimmed.startsWith(prefix)) {
        return trimmed.substring(prefix.length).trim();
      }
    }
    return '';
  }

  static Future<void> _deleteQuiet(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // Ignore cleanup failure.
    }
  }
}
