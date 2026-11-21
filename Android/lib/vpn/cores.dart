import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/utils.dart';
import '../models/models.dart';
import '../platform/native.dart';

/// Android packages the engine as an AAR, not as an executable. Availability
/// is established through the native bridge rather than a pretend file path.
class CoreProvisioner {
  CoreProvisioner({NativeBridge? native}) : _native = native ?? NativeBridge();
  final NativeBridge _native;
  List<CoreInfo> _catalog = <CoreInfo>[];
  String _dataDir = '';

  List<CoreInfo> get catalog => List.unmodifiable(_catalog);
  String get dataDir => _dataDir;
  String get appDir => _dataDir;
  String get bundledDir => '$_dataDir${Platform.pathSeparator}cores';
  String get binDir => '$bundledDir${Platform.pathSeparator}bin';

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    _dataDir = '${dir.path}${Platform.pathSeparator}Umbrella';
    await Directory('$_dataDir${Platform.pathSeparator}run').create(recursive: true);
    final raw = await rootBundle.loadString('assets/cores/manifest.json');
    final json = JsonX.asMap(jsonDecode(raw));
    _catalog = JsonX.asList(json['cores'])
        .map((Object? item) => CoreInfo.fromJson(JsonX.asMap(item)))
        .toList(growable: false);
  }

  CoreInfo? info(String id) {
    for (final item in _catalog) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<bool> hasCore(String id) async => info(id) != null && await _native.coreAvailable();

  Future<List<CoreInfo>> missingRequired() async {
    final required = _catalog.where((core) => core.requiredCore).toList();
    if (required.isEmpty) throw StateError('Required mobile engine manifest is missing');
    if (!await _native.coreAvailable()) return required;
    return const <CoreInfo>[];
  }

  /// A packaged mobile library has no standalone binary to execute.
  Future<String?> locateBinary(String binary) async => null;

  Future<bool> provision(CoreInfo core) => hasCore(core.id);
}
