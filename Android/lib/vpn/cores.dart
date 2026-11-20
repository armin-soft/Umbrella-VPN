import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/utils.dart';
import '../models/models.dart';
import '../platform/services.dart';

/// مدیریت فهرست و پوشه داده موتور اتصال آمبرلا در اندروید.
///
/// کتابخانه بومی هسته (`libhiddify-core.so`) همراه خود بسته رسمی APK نصب می شود
/// و هیچ فایل اجرایی در زمان اجرا از اینترنت دانلود نمی شود.
class CoreProvisioner {
  static List<CoreInfo> _catalog = <CoreInfo>[];
  String _dataDir = '';

  List<CoreInfo> get catalog => _catalog;

  String get dataDir => _dataDir;

  String get appDir => _dataDir;

  String get bundledDir =>
      _dataDir.isEmpty ? 'libs' : '$_dataDir${Platform.pathSeparator}cores';

  String get binDir => '$bundledDir${Platform.pathSeparator}bin';

  Future<void> init() async {
    try {
      final Directory dir = await getApplicationSupportDirectory();
      _dataDir = '${dir.path}${Platform.pathSeparator}Umbrella';
      await Directory('$_dataDir${Platform.pathSeparator}run').create(
        recursive: true,
      );
    } on Exception {
      _dataDir = Directory.systemTemp.path;
    }
    if (_catalog.isEmpty) {
      _catalog = await _loadCatalog();
    }
  }

  Future<List<CoreInfo>> _loadCatalog() async {
    try {
      final String raw =
          await rootBundle.loadString('assets/cores/manifest.json');
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

  /// در اندروید هسته به صورت کتابخانه بومی داخل APK بسته بندی شده است.
  Future<String?> locateBinary(String binary) async {
    if (Platform.isAndroid) {
      return 'umbrella-core';
    }
    final List<String> candidates = <String>[
      '$appDir${Platform.pathSeparator}$binary',
      '$bundledDir${Platform.pathSeparator}$binary',
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
    if (Platform.isAndroid) {
      return true;
    }
    return (await locateBinary(core.binary)) != null;
  }

  Future<List<CoreInfo>> missingRequired() async {
    if (Platform.isAndroid) {
      return const <CoreInfo>[];
    }
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

  Future<bool> provision(CoreInfo core) async {
    final String? found = await locateBinary(core.binary);
    if (found != null) {
      return true;
    }
    AppLogger.instance.add(
      'هسته ${core.binary} در بسته نصب پیدا نشد؛ برنامه را از منبع رسمی نصب کنید.',
      level: 'error',
    );
    return false;
  }
}
