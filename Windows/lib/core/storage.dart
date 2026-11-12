import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// انبار محلی: تنظیمات سبک در SharedPreferences و داده های بزرگ تر (فهرست
/// گره ها و گزارش ها) در پرونده JSON کنار داده های برنامه.
class LocalStore {
  LocalStore._();

  static final LocalStore instance = LocalStore._();
  late SharedPreferences _prefs;
  Directory? _directory;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) {
      return;
    }
    _prefs = await SharedPreferences.getInstance();
    try {
      _directory = await getApplicationSupportDirectory();
    } on Exception {
      _directory = Directory.systemTemp;
    }
    _ready = true;
  }

  String? read(String key) => _prefs.getString(key);

  Future<void> write(String key, String? value) async {
    if (value == null) {
      await _prefs.remove(key);
      return;
    }
    await _prefs.setString(key, value);
  }

  bool readBool(String key, {bool fallback = false}) =>
      _prefs.getBool(key) ?? fallback;

  Future<void> writeBool(String key, bool value) => _prefs.setBool(key, value);

  int readInt(String key, {int fallback = 0}) => _prefs.getInt(key) ?? fallback;

  Future<void> writeInt(String key, int value) => _prefs.setInt(key, value);

  Map<String, dynamic> readJson(String key) {
    final String? raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map<String, dynamic>(
          (Object? k, Object? v) => MapEntry<String, dynamic>(k.toString(), v),
        );
      }
    } on FormatException {
      return <String, dynamic>{};
    }
    return <String, dynamic>{};
  }

  Future<void> writeJson(String key, Map<String, dynamic> value) =>
      write(key, jsonEncode(value));

  List<dynamic> readJsonList(String key) {
    final String? raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return <dynamic>[];
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List<dynamic>) {
        return decoded;
      }
    } on FormatException {
      return <dynamic>[];
    }
    return <dynamic>[];
  }

  Future<void> writeJsonList(String key, List<dynamic> value) =>
      write(key, jsonEncode(value));

  Future<void> remove(String key) => _prefs.remove(key);

  Directory get directory => _directory ?? Directory.systemTemp;

  Future<File> file(String name) async {
    final Directory dir = Directory('${directory.path}${Platform.pathSeparator}umbrella');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  Future<String?> readFile(String name) async {
    try {
      final File target = await file(name);
      if (!await target.exists()) {
        return null;
      }
      final String content = await target.readAsString();
      return content;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> writeFile(String name, String content) async {
    try {
      final File target = await file(name);
      await target.writeAsString(content, flush: true);
    } on FileSystemException {
      // نوشتن فایل اختیاری است؛ نبود آن نباید برنامه را متوقف کند.
    }
  }
}

/// کلیدهای ذخیره سازی در یک جا، تا غلط تایپی کلیدها پیش نیاید.
class StoreKeys {
  const StoreKeys._();

  static const String session = 'session.v1';
  static const String settings = 'settings.v1';
  static const String nodes = 'nodes.v1';
  static const String notifications = 'notifications.v1';
  static const String landingSeen = 'landing.seen';
  static const String lastPhone = 'auth.lastPhone';
  static const String lastNode = 'vpn.lastNode';
  static const String filter = 'filter.v1';
  static const String deviceId = 'device.id';
  static const String deviceTrusted = 'device.trusted';
  static const String updateSkipped = 'update.skipped';
  static const String nodesCache = 'nodes-cache.json';
}
