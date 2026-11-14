import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/utils.dart';
import '../models/models.dart';
import '../platform/services.dart';

/// محل نگاه داشتن هسته و ابزار یافتن و آماده کردن آن.
///
/// تنها هسته این نسخه هسته هیدیفای است و همراه خود نسخه نصب می شود (پوشه
/// `cores\hiddify` کنار فایل اجرایی)؛ برنامه هیچ چیزی را از اینترنت دانلود
/// نمی کند. اگر هسته در نسخه نصب نباشد، همان پیام روشن فارسی نمایش داده می شود
/// و کاربر باید برنامه را دوباره نصب کند.
class CoreProvisioner {

  static List<CoreInfo> _catalog = <CoreInfo>[];
  String _dataDir = '';

  List<CoreInfo> get catalog => _catalog;

  String get dataDir => _dataDir;

  /// پوشه هسته ها در محل نصب برنامه.
  String get binDir => '$bundledDir${Platform.pathSeparator}bin';

  String get appDir {
    final String exe = Platform.resolvedExecutable;
    return exe.substring(0, exe.lastIndexOf(Platform.pathSeparator));
  }

  String get bundledDir => '$appDir${Platform.pathSeparator}cores';

  Future<void> init() async {
    // پوشه داده برنامه: %APPDATA%\Umbrella (بدون تودرتویی و بدون نام فارسی).
    final String appData = Platform.environment['APPDATA'] ?? '';
    if (appData.isNotEmpty) {
      _dataDir = '$appData${Platform.pathSeparator}Umbrella';
    } else {
      final Directory dir = await getApplicationSupportDirectory();
      _dataDir = '${dir.path}${Platform.pathSeparator}Umbrella';
    }
    try {
      await Directory('$_dataDir${Platform.pathSeparator}run').create(
        recursive: true,
      );
    } on FileSystemException {
      // پوشه داده از قبل ساخته شده یا دسترسی نیست؛ اجرای برنامه ادامه می یابد.
    }
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

  /// مسیر هسته در صورت وجود. هسته ها همراه نسخه نصب می شوند و از همان پوشه
  /// نصب اجرا می شوند؛ هیچ کپی یا نصبی لازم نیست.
  Future<String?> locateBinary(String binary) async {
    // هسته هیدیفای همه فایل هایش را کنار هم دارد (cores\\hiddify)؛ هسته هایی
    // که یک فایل بودند در cores\\bin و کنار برنامه اند.
    final List<String> candidates = <String>[
      '${bundledDir}${Platform.pathSeparator}hiddify${Platform.pathSeparator}$binary',
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

  /// هسته از همان پوشه نصب استفاده می شود؛ اگر نبود پیام روشن ثبت می شود.
  Future<bool> provision(CoreInfo core) async {
    final String? found = await locateBinary(core.binary);
    if (found != null) {
      return true;
    }
    AppLogger.instance.add(
      'هسته ${core.binary} در پوشه نصب پیدا نشد (${bundledDir}); '
      'باید همراه نسخه نصب شده باشد.',
      level: 'error',
    );
    return false;
  }

}
