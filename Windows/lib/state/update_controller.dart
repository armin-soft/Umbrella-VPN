import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../core/persian.dart';
import '../core/storage.dart';
import '../models/models.dart';
import '../platform/native.dart';
import '../platform/services.dart';

/// به روز رسانی درون برنامه ای در دو کانال اصلی (پایدار) و بتا (آزمایشی):
/// بررسی انتشار، دانلود جریانی با سرعت و امکان لغو، تایید SHA-256 و نصب خودکار.
class UpdateController extends ChangeNotifier {
  UpdateController(this._native, {UpdateService? service})
      : _service = service ?? UpdateService();

  final NativeBridge _native;
  final UpdateService _service;
  final AppLogger _log = AppLogger.instance;

  /// پس از اجرای نصب کننده صدا زده می شود تا هسته، پنجره CLI و برنامه تمیز
  /// بسته شوند و نسخه تازه بی وقفه جایگزین و اجرا شود.
  Future<void> Function()? onExitForInstall;

  UpdateChannel _channel = UpdateChannel.stable;
  UpdateChannel get channel => _channel;

  UpdateInfo? _available;
  UpdateInfo? get available => _available;

  List<UpdateInfo> _releases = const <UpdateInfo>[];
  List<UpdateInfo> get releases => _releases;

  DateTime? _lastCheckedAt;
  DateTime? get lastCheckedAt => _lastCheckedAt;

  bool _checking = false;
  bool get checking => _checking;

  bool _downloading = false;
  bool get downloading => _downloading;

  bool _cancelRequested = false;

  double _progress = 0;
  double get progress => _progress;

  int _received = 0;
  int get received => _received;

  int _total = 0;
  int get total => _total;

  int _speedBytesPerSec = 0;
  int get speedBytesPerSec => _speedBytesPerSec;

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
    _channel = UpdateChannelX.fromStorage(
      LocalStore.instance.read(StoreKeys.updateChannel),
    );
    notifyListeners();
  }

  /// تغییر کانال بین اصلی (پایدار) و بتا (آزمایشی) و بررسی فوری نسخه های آن کانال.
  Future<void> setChannel(UpdateChannel next) async {
    if (_channel == next || _downloading || _installing) {
      return;
    }
    _channel = next;
    _available = null;
    _error = '';
    _phase = '';
    await LocalStore.instance.write(StoreKeys.updateChannel, next.storageValue);
    _log.add('کانال به روز رسانی: ${next.label}');
    notifyListeners();
    await check(silent: false, ignoreSkipped: true);
  }

  Future<bool> check({bool silent = false, bool ignoreSkipped = false}) async {
    if (_checking || _downloading || _installing) {
      return false;
    }
    _checking = true;
    _error = '';
    if (!silent) {
      _phase = 'بررسی کانال ${_channel.label}...';
    }
    notifyListeners();
    try {
      final ({UpdateInfo? available, List<UpdateInfo> releases}) catalog =
          await _service.fetchCatalog(channel: _channel);
      _checking = false;
      _lastCheckedAt = DateTime.now();
      _releases = List<UpdateInfo>.unmodifiable(catalog.releases);
      final UpdateInfo? info = catalog.available;
      if (info == null) {
        _available = null;
        _phase = '';
        notifyListeners();
        return false;
      }
      if (!ignoreSkipped &&
          !info.mandatory &&
          info.version == _skippedVersion) {
        _available = null;
        _phase = '';
        notifyListeners();
        return false;
      }
      _available = info;
      _phase = '';
      notifyListeners();
      return true;
    } catch (_) {
      _checking = false;
      _phase = '';
      if (!silent) {
        _error = 'ارتباط با مخزن انتشار برقرار نشد؛ کمی بعد دوباره تلاش کنید.';
      }
      notifyListeners();
      return false;
    }
  }

  Future<void> skipCurrent() async {
    final UpdateInfo? info = _available;
    if (info == null || _downloading || _installing) {
      return;
    }
    _skippedVersion = info.version;
    await LocalStore.instance.write(StoreKeys.updateSkipped, info.version);
    _available = null;
    notifyListeners();
  }

  void cancelDownload() {
    if (!_downloading || _installing) {
      return;
    }
    _cancelRequested = true;
    _phase = 'در حال لغو دانلود...';
    notifyListeners();
  }

  Future<bool> downloadAndInstall() async {
    final UpdateInfo? info = _available;
    if (info == null || _downloading || _installing) {
      return false;
    }
    _downloading = true;
    _cancelRequested = false;
    _progress = 0;
    _received = 0;
    _total = info.sizeBytes;
    _speedBytesPerSec = 0;
    _error = '';
    _phase = Fa.num('آماده سازی دانلود نسخه ${info.version}...');
    notifyListeners();

    final Stopwatch clock = Stopwatch()..start();
    int sampleBytes = 0;
    int sampleMs = 0;
    int lastNotifyMs = 0;

    try {
      final File? file = await _service.download(
        info,
        isCancelled: () => _cancelRequested,
        onProgress: (double progress, int received, int total) {
          _progress = progress;
          _received = received;
          _total = total;
          final int nowMs = clock.elapsedMilliseconds;
          final int deltaMs = nowMs - sampleMs;
          if (deltaMs >= 450) {
            final int deltaBytes = received - sampleBytes;
            if (deltaBytes >= 0) {
              _speedBytesPerSec = ((deltaBytes * 1000) / deltaMs).round();
            }
            sampleBytes = received;
            sampleMs = nowMs;
          }
          _phase = progress >= 1.0 && info.sha256.isNotEmpty
              ? 'بررسی سلامت و اصالت فایل...'
              : 'در حال دانلود بسته نصب در برنامه...';
          if (nowMs - lastNotifyMs >= 100 || progress >= 1.0) {
            lastNotifyMs = nowMs;
            notifyListeners();
          }
        },
      );
      if (_cancelRequested) {
        _downloading = false;
        _cancelRequested = false;
        _speedBytesPerSec = 0;
        _progress = 0;
        _received = 0;
        _phase = '';
        notifyListeners();
        return false;
      }
      if (file == null) {
        _error = info.sha256.isNotEmpty
            ? 'دانلود کامل نشد یا اصالت فایل تایید نشد. دوباره تلاش کنید.'
            : 'دانلود بسته به روز رسانی ناموفق بود. دوباره تلاش کنید.';
        _log.add(_error, level: 'error');
        _downloading = false;
        _speedBytesPerSec = 0;
        _phase = '';
        notifyListeners();
        return false;
      }

      _installing = true;
      _speedBytesPerSec = 0;
      _phase = Fa.num('در حال نصب خودکار نسخه ${info.version}...');
      notifyListeners();

      final bool ok = await _service.install(
        file,
        _native,
        silentRelaunch: true,
      );
      if (!ok) {
        _installing = false;
        _downloading = false;
        _phase = '';
        _error = 'نصب لغو شد یا دسترسی مدیر تایید نشد. برای نصب دوباره کلیک کنید.';
        _log.add(_error, level: 'warning');
        notifyListeners();
        return false;
      }

      _phase = 'بسته نصب اجرا شد؛ برنامه به روز و دوباره باز می شود...';
      _log.add(Fa.num('نصب درون برنامه ای نسخه ${info.version} آغاز شد.'));
      notifyListeners();

      final Future<void> Function()? exitHook = onExitForInstall;
      if (exitHook != null) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await exitHook();
      } else {
        _installing = false;
        _downloading = false;
        notifyListeners();
      }
      return true;
    } on Exception {
      _error = 'خطا در دریافت یا نصب نسخه جدید؛ دوباره تلاش کنید.';
      _log.add(_error, level: 'error');
      _downloading = false;
      _installing = false;
      _speedBytesPerSec = 0;
      _phase = '';
      notifyListeners();
      return false;
    }
  }

  /// پشتیبان باز کردن صفحه انتشار رسمی (کانال پایدار یا بتا).
  Future<bool> openDownloadPage() async {
    final String target = _channel == UpdateChannel.beta
        ? AppConfig.allReleasesPageUrl
        : AppConfig.releasesPageUrl;
    final Uri? uri = Uri.tryParse(target);
    if (uri == null) {
      return false;
    }
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Exception {
      return false;
    }
  }
}
