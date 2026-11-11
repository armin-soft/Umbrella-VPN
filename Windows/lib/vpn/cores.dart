import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/utils.dart';
import '../models/models.dart';
import '../platform/native.dart';
import '../platform/services.dart';

/// محل نگاه داشتن هسته ها و ابزار یافتن و نصب آن ها.
///
/// هسته ها فایل اجرایی باینری هستند و در مخزن نیستند؛ برنامه آن ها را از
/// نشانی های فهرست هسته ها دانلود می کند یا از پوشه نصب کنار برنامه برمی دارد.
class CoreProvisioner {
  CoreProvisioner({
    required NativeBridge native,
    http.Client? client,
  })  : _native = native,
        _client = client ?? http.Client();

  final NativeBridge _native;
  final http.Client _client;

  static List<CoreInfo> _catalog = <CoreInfo>[];
  String _dataDir = '';

  List<CoreInfo> get catalog => _catalog;

  String get dataDir => _dataDir;

  String get binDir => _dataDir.isEmpty
      ? ''
      : '$_dataDir${Platform.pathSeparator}cores${Platform.pathSeparator}bin';

  String get appDir {
    final String exe = Platform.resolvedExecutable;
    return exe.substring(0, exe.lastIndexOf(Platform.pathSeparator));
  }

  Future<void> init() async {
    _dataDir = await _native.dataDir();
    if (_dataDir.isEmpty) {
      final Directory dir = await getApplicationSupportDirectory();
      _dataDir = '${dir.path}${Platform.pathSeparator}Umbrella';
    }
    await Directory(binDir).create(recursive: true);
    if (_catalog.isEmpty) {
      _catalog = await _loadCatalog();
    }
  }

  Future<List<CoreInfo>> _loadCatalog() async {
    try {
      final String raw = await rootBundle.loadString('assets/cores/manifest.json');
      final Map<String, dynamic> json = JsonX.asMap(jsonDecode(raw));
      return JsonX.asList(json['cores'])
          .map((Object? item) => CoreInfo.fromJson(JsonX.asMap(item)))
          .toList();
    } on Exception {
      return <CoreInfo>[];
    }
  }

  CoreInfo? info(String id) {
    for (final CoreInfo core in _catalog) {
      if (core.id == id) {
        return core;
      }
    }
    return null;
  }

  /// مسیر هسته در صورت وجود: اول کنار برنامه، بعد پوشه داده، بعد PATH.
  Future<String?> locateBinary(String binary) async {
    final List<String> candidates = <String>[
      '$binDir${Platform.pathSeparator}$binary',
      '${appDir}${Platform.pathSeparator}cores${Platform.pathSeparator}bin'
          '${Platform.pathSeparator}$binary',
      '${appDir}${Platform.pathSeparator}$binary',
    ];
    for (final String candidate in candidates) {
      if (await File(candidate).exists()) {
        return candidate;
      }
    }
    return null;
  }

  Future<bool> hasCore(String id) async {
    final CoreInfo? core = info(id);
    if (core == null) {
      return false;
    }
    return (await locateBinary(core.binary)) != null;
  }

  Future<List<CoreInfo>> missingRequired() async {
    final List<CoreInfo> missing = <CoreInfo>[];
    for (final CoreInfo core in _catalog) {
      if (!core.requiredCore) {
        continue;
      }
      if ((await locateBinary(core.binary)) == null) {
        missing.add(core);
      }
    }
    return missing;
  }

  /// دانلود و نصب یک هسته با گزارش درصد پیشرفت.
  Future<bool> install(
    CoreInfo core, {
    void Function(double progress, String phase)? onProgress,
  }) async {
    if (core.url.isEmpty) {
      return false;
    }
    onProgress?.call(0, 'شروع دانلود ${core.title}');
    final Directory temp = await getTemporaryDirectory();
    final String archiveName = core.url.split('/').last.split('?').first;
    final File archive = File('${temp.path}${Platform.pathSeparator}$archiveName');

    try {
      final http.Request request = http.Request('GET', Uri.parse(core.url));
      final http.StreamedResponse response =
          await _client.send(request).timeout(const Duration(seconds: 45));
      if (response.statusCode >= 300) {
        AppLogger.instance.add(
          'دانلود ${core.title} ناموفق بود (کد ${response.statusCode}) - ${core.url}',
          level: 'error',
        );
        return false;
      }
      final int total = response.contentLength ?? 0;
      final IOSink sink = archive.openWrite();
      int received = 0;
      await for (final List<int> chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(
          total > 0 ? (received / total).clamp(0.0, 1.0) : 0,
          'دریافت ${core.title}',
        );
      }
      await sink.flush();
      await sink.close();

      if (core.sha256.isNotEmpty) {
        final String hash =
            sha256.convert(await archive.readAsBytes()).toString().toLowerCase();
        if (hash != core.sha256.toLowerCase()) {
          AppLogger.instance.add(
            'چکسام ${core.title} مطابقت نداشت؛ نصب متوقف شد.',
            level: 'error',
          );
          return false;
        }
      }

      onProgress?.call(0.98, 'استخراج ${core.title}');
      if (core.archive == 'msi') {
        AppLogger.instance.add(
          '${core.title} یک بسته نصب ویندوز است؛ نصب دستی لازم است.',
          level: 'warning',
        );
        return false;
      }

      final String extractDir = '${temp.path}${Platform.pathSeparator}umbrella-core-${core.id}';
      await Directory(extractDir).create(recursive: true);
      final int pid = await _native.spawn(
        exe: 'powershell.exe',
        args:
            '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath \'${archive.path}\' -DestinationPath \'$extractDir\' -Force"',
      );
      if (pid <= 0) {
        return false;
      }
      // صبر کوتاه تا استخراج کامل شود؛ سپس فایل مورد نظر کپی می شود.
      for (int i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        final File? found = await _findFile(Directory(extractDir), core.binary);
        if (found != null) {
          final String destination = '$binDir${Platform.pathSeparator}${core.binary}';
          await found.copy(destination);
          if (core.binary == 'sing-box.exe') {
            final File? wintun = await _findFile(Directory(extractDir), 'wintun.dll');
            if (wintun != null) {
              await wintun.copy('$binDir${Platform.pathSeparator}wintun.dll');
            }
          }
          onProgress?.call(1, '${core.title} آماده شد');
          AppLogger.instance.add('${core.title} نصب شد: $destination');
          return true;
        }
      }
      AppLogger.instance.add(
        'فایل ${core.binary} در بسته ${core.title} پیدا نشد.',
        level: 'error',
      );
      return false;
    } on Exception catch (error) {
      AppLogger.instance.add('نصب ${core.title} ناموفق: $error', level: 'error');
      return false;
    }
  }

  Future<File?> _findFile(Directory dir, String name) async {
    if (!await dir.exists()) {
      return null;
    }
    try {
      await for (final FileSystemEntity entity in dir.list(recursive: true)) {
        if (entity is File &&
            entity.path.split(Platform.pathSeparator).last.toLowerCase() ==
                name.toLowerCase()) {
          return entity;
        }
      }
    } on FileSystemException {
      return null;
    }
    return null;
  }

  Future<void> close() async {
    _client.close();
  }
}
