import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/utils.dart';
import '../models/models.dart';
import '../platform/native.dart';
import '../platform/services.dart';

/// محل نگاه داشتن هسته ها و ابزار یافتن و آماده کردن آن ها.
///
/// هسته ها همراه خود نسخه نصب می شوند (پوشه cores کنار فایل اجرایی) و برنامه
/// هیچ چیزی را از اینترنت دانلود نمی کند. اگر هسته ای در نسخه نصب نباشد، همان
/// پیام روشن فارسی نمایش داده می شود و کاربر باید برنامه را دوباره نصب کند.
class CoreProvisioner {
  CoreProvisioner({required NativeBridge native}) : _native = native;

  final NativeBridge _native;

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

  String get bundledDir => '$appDir${Platform.pathSeparator}cores';

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

  /// مسیر هسته در صورت وجود: اول کنار برنامه (همان جایی که نصب کننده می ریزد)،
  /// بعد پوشه داده.
  Future<String?> locateBinary(String binary) async {
    final List<String> candidates = <String>[
      '${bundledDir}${Platform.pathSeparator}bin${Platform.pathSeparator}$binary',
      '${bundledDir}${Platform.pathSeparator}$binary',
      '${appDir}${Platform.pathSeparator}$binary',
      '$binDir${Platform.pathSeparator}$binary',
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

  /// هسته را از پوشه همراه نسخه برمی دارد و اگر کنار برنامه باشد، یک نسخه
  /// قابل نوشتن در پوشه داده می سازد. هیچ درخواست شبکه ای انجام نمی شود.
  Future<bool> provision(CoreInfo core) async {
    if (await locateBinary(core.binary) != null) {
      return true;
    }
    final String bundled = bundledDir;
    final Directory source = Directory(bundled);
    if (!await source.exists()) {
      AppLogger.instance.add(
        'پوشه هسته ها کنار برنامه پیدا نشد: $bundled',
        level: 'error',
      );
      return false;
    }
    final File? found = await _findFile(source, core.binary);
    if (found == null) {
      AppLogger.instance.add(
        'هسته ${core.binary} در پوشه $bundled نیست؛ نسخه نصب باید آن را همراه داشته باشد.',
        level: 'error',
      );
      return false;
    }
    try {
      await Directory(binDir).create(recursive: true);
      final String destination = '$binDir${Platform.pathSeparator}${core.binary}';
      await found.copy(destination);
      if (core.binary.toLowerCase().endsWith('.exe')) {
        final File? wintun = await _findFile(source, 'wintun.dll');
        if (wintun != null) {
          await wintun.copy('$binDir${Platform.pathSeparator}wintun.dll');
        }
      }
      AppLogger.instance.add('هسته ${core.title} از نسخه نصب آماده شد: $destination');
      return true;
    } on FileSystemException catch (error) {
      AppLogger.instance.add('آماده سازی ${core.title} ناموفق: $error', level: 'error');
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
}
