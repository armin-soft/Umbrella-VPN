import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/utils.dart';
import '../models/models.dart';
import '../platform/native.dart';

/// مدیریت پوشه های کاری و فهرست هسته بومی نسخه اندروید (`hiddify-core.aar`).
class CoreProvisioner {
  static List<CoreInfo> _catalog = <CoreInfo>[];
  String _dataDir = '';

  List<CoreInfo> get catalog => _catalog;
  String get dataDir => _dataDir;
  String get binDir => '$bundledDir${Platform.pathSeparator}bin';
  String get appDir => _dataDir;
  String get bundledDir => '$_dataDir${Platform.pathSeparator}cores';

  Future<void> init([NativeBridge? native]) async {
    final Directory dir = await getApplicationSupportDirectory();
    _dataDir = '${dir.path}${Platform.pathSeparator}Umbrella';
    for (final String sub in const <String>['run', 'work', 'tmp']) {
      try {
        await Directory('$_dataDir${Platform.pathSeparator}$sub')
            .create(recursive: true);
      } on FileSystemException {
        // نادیده گرفته می شود.
      }
    }
    if (native != null && Platform.isAndroid) {
      await native.setupDirectories(
        baseDir: _dataDir,
        workingDir: '$_dataDir${Platform.pathSeparator}work',
        tempDir: '$_dataDir${Platform.pathSeparator}tmp',
      );
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
      if (core.id == id) return core;
    }
    return null;
  }

  Future<String?> locateBinary(String binary) async {
    if (Platform.isAndroid) {
      return 'android://$binary';
    }
    final List<String> candidates = <String>[
      '$_dataDir${Platform.pathSeparator}$binary',
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
    if (core == null) return false;
    return (await locateBinary(core.binary)) != null;
  }

  Future<List<CoreInfo>> missingRequired() async {
    if (Platform.isAndroid) return const <CoreInfo>[];
    final List<CoreInfo> missing = <CoreInfo>[];
    for (final CoreInfo core in _catalog) {
      if (!core.requiredCore) continue;
      if ((await locateBinary(core.binary)) == null) missing.add(core);
    }
    return missing;
  }

  Future<bool> provision(CoreInfo core) async {
    return (await locateBinary(core.binary)) != null;
  }
}
