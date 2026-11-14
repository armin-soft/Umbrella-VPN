import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/storage.dart';
import '../models/models.dart';
import '../platform/native.dart';
import '../platform/services.dart';

/// به روز رسانی برنامه: بررسی نسخه، دانلود با درصد پیشرفت و نصب.
class UpdateController extends ChangeNotifier {
  UpdateController(this._native, {UpdateService? service})
      : _service = service ?? UpdateService();

  final NativeBridge _native;
  final UpdateService _service;
  final AppLogger _log = AppLogger.instance;

  UpdateInfo? _available;
  UpdateInfo? get available => _available;

  bool _checking = false;
  bool get checking => _checking;

  bool _downloading = false;
  bool get downloading => _downloading;

  double _progress = 0;
  double get progress => _progress;

  int _received = 0;
  int get received => _received;

  int _total = 0;
  int get total => _total;

  String _phase = '';
  String get phase => _phase;

  String _error = '';
  String get error => _error;

  bool _installing = false;
  bool get installing => _installing;

  String _skippedVersion = '';
  String get skippedVersion => _skippedVersion;

  Future<void> loadSkipped() async {
    _skippedVersion = LocalStore.instance.read(StoreKeys.updateSkipped) ?? '';
    notifyListeners();
  }

  Future<bool> check({bool silent = false}) async {
    if (_checking) {
      return false;
    }
    _checking = true;
    _error = '';
    if (!silent) {
      _phase = 'در حال بررسی نسخه جدید...';
    }
    notifyListeners();
    final UpdateInfo? info = await _service.check();
    _checking = false;
    if (info == null) {
      _available = null;
      _phase = '';
      notifyListeners();
      return false;
    }
    if (info.version == _skippedVersion) {
      _available = null;
      notifyListeners();
      return false;
    }
    _available = info;
    _phase = '';
    notifyListeners();
    return true;
  }

  Future<void> skipCurrent() async {
    final UpdateInfo? info = _available;
    if (info == null) {
      return;
    }
    _skippedVersion = info.version;
    await LocalStore.instance.write(StoreKeys.updateSkipped, info.version);
    _available = null;
    notifyListeners();
  }

  Future<bool> downloadAndInstall() async {
    final UpdateInfo? info = _available;
    if (info == null || _downloading) {
      return false;
    }
    _downloading = true;
    _progress = 0;
    _error = '';
    _phase = 'شروع دانلود...';
    notifyListeners();
    try {
      final File? file = await _service.download(
        info,
        onProgress: (double progress, int received, int total) {
          _progress = progress;
          _received = received;
          _total = total;
          _phase = 'دریافت بسته به روز رسانی';
          notifyListeners();
        },
      );
      if (file == null) {
        _error = 'دانلود ناموفق بود یا فایل سالم نبود.';
        _log.add(_error, level: 'error');
        _downloading = false;
        notifyListeners();
        return false;
      }
      _installing = true;
      _phase = 'اجرای نصب کننده...';
      notifyListeners();
      final bool ok = await _service.install(file, _native);
      _installing = false;
      _downloading = false;
      if (!ok) {
        _error = 'اجرای نصب کننده ناموفق بود.';
        _log.add(_error, level: 'error');
        notifyListeners();
        return false;
      }
      _phase = 'نصب کننده اجرا شد؛ برنامه بسته می شود.';
      notifyListeners();
      return true;
    } on Exception catch (error) {
      _error = 'خطا در به روز رسانی: $error';
      _log.add(_error, level: 'error');
      _downloading = false;
      _installing = false;
      notifyListeners();
      return false;
    }
  }

  void openDownloadPage() {
    _log.add('درخواست باز کردن صفحه دانلود.');
  }
}
