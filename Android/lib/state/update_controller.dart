import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../core/persian.dart';
import '../core/safe_url_launcher.dart';
import '../core/storage.dart';
import '../models/models.dart';
import '../platform/native.dart';
import '../platform/services.dart';

/// به روز رسانی درون برنامه ای در دو کانال اصلی (پایدار) و بتا (آزمایشی):
/// بررسی انتشار، دانلود جریانی با سرعت و امکان لغو، تایید SHA-256 و نصب خودکار.
class UpdateController extends ChangeNotifier {
  static const Duration autoCheckInterval = Duration(minutes: 5);

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

  DateTime? _lastCheckAttemptAt;
  DateTime? get lastCheckAttemptAt => _lastCheckAttemptAt;

  bool get autoCheckDue {
    final DateTime? lastAttempt = _lastCheckAttemptAt;
    return lastAttempt == null ||
        DateTime.now().difference(lastAttempt) >= autoCheckInterval;
  }

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
  bool _checkFailureLogged = false;
  String get error => _error;

  bool _installing = false;
  bool get installing => _installing;

  bool _awaitingInstallPermission = false;
  bool get awaitingInstallPermission => _awaitingInstallPermission;

  File? _pendingInstallFile;
  String _pendingInstallSha256 = '';
  String _pendingInstallVersion = '';

  String _skippedVersion = '';
  String get skippedVersion => _skippedVersion;

  String _dismissedBannerVersion = '';
  String _activeDownloadVersion = '';
  String get activeDownloadVersion => _activeDownloadVersion;

  bool _disposed = false;

  /// نمایش بنر اعلان نسخه جدید در صفحه اتصال؛ بستن موقت فقط در همین اجرا
  /// بنر را پنهان می کند تا پس از بستن و باز کردن دوباره برنامه یا انتشار
  /// نسخه جدیدتر دوباره نمایش داده شود و بخش «به روز رسانی» همیشه گزینه
  /// دانلود و نصب را حفظ کند.
  bool get showBanner =>
      _available != null &&
      (_available!.mandatory || _dismissedBannerVersion != _available!.version);

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> loadSkipped() async {
    if (!LocalStore.instance.isReady) {
      return;
    }
    _skippedVersion = '';
    final String? legacySkipped = LocalStore.instance.read(StoreKeys.updateSkipped);
    if (legacySkipped != null && legacySkipped.isNotEmpty) {
      await LocalStore.instance.remove(StoreKeys.updateSkipped);
    }
    _channel = UpdateChannelX.fromStorage(
      LocalStore.instance.read(StoreKeys.updateChannel),
    );
    _safeNotify();
  }

  /// تغییر کانال بین اصلی (پایدار) و بتا (آزمایشی) و بررسی فوری نسخه های آن کانال.
  Future<void> setChannel(UpdateChannel next) async {
    if (_channel == next || _downloading || _installing) {
      return;
    }
    _channel = next;
    _available = null;
    _dismissedBannerVersion = '';
    _error = '';
    _phase = '';
    if (LocalStore.instance.isReady) {
      await LocalStore.instance.write(StoreKeys.updateChannel, next.storageValue);
    }
    _log.add('کانال به روز رسانی: ${next.label}');
    _safeNotify();
    await check(silent: false, ignoreSkipped: true);
  }

  Future<bool> checkIfDue({bool silent = true}) {
    if (!autoCheckDue || _checking || _downloading || _installing) {
      return Future<bool>.value(false);
    }
    return check(silent: silent);
  }

  Future<bool> check({bool silent = false, bool ignoreSkipped = false}) async {
    if (_checking || _downloading || _installing) {
      return false;
    }
    _lastCheckAttemptAt = DateTime.now();
    _checking = true;
    _error = '';
    if (!silent) {
      _phase = 'بررسی کانال ${_channel.label}...';
    }
    _safeNotify();
    try {
      final ({UpdateInfo? available, List<UpdateInfo> releases}) catalog =
          await _service.fetchCatalog(channel: _channel);
      _checking = false;
      _checkFailureLogged = false;
      _lastCheckedAt = DateTime.now();
      _releases = List<UpdateInfo>.unmodifiable(catalog.releases);
      final UpdateInfo? info = catalog.available;
      if (info == null) {
        _available = null;
        _phase = '';
        _safeNotify();
        return false;
      }
      _available = info;
      _phase = '';
      _safeNotify();
      return true;
    } catch (_) {
      _checking = false;
      _phase = '';
      if (!_checkFailureLogged) {
        _log.add('بررسی به روز رسانی ناموفق بود؛ ارتباط با مخزن انتشار را بررسی کنید.', level: 'warning');
        _checkFailureLogged = true;
      }
      if (!silent) {
        _error = 'ارتباط با مخزن انتشار برقرار نشد؛ کمی بعد دوباره تلاش کنید.';
      }
      _safeNotify();
      return false;
    }
  }

  /// بستن موقت اعلان به روز رسانی فقط در نشست فعلی؛ با بستن و باز کردن
  /// دوباره برنامه یا برای نسخه جدیدتر باز هم نمایش داده می شود.
  void dismissBanner() {
    final UpdateInfo? info = _available;
    if (info == null || info.mandatory || _downloading || _installing) {
      return;
    }
    _dismissedBannerVersion = info.version;
    _safeNotify();
  }

  /// بازگردانی امکان نمایش اعلان به روز رسانی پس از بستن موقت پنجره یا خروج از برنامه.
  void resetBannerDismissal() {
    if (_dismissedBannerVersion.isEmpty) {
      return;
    }
    _dismissedBannerVersion = '';
    _safeNotify();
  }

  Future<void> skipCurrent() async {
    dismissBanner();
  }

  void cancelDownload() {
    if (!_downloading || _installing) {
      return;
    }
    _cancelRequested = true;
    _phase = 'در حال لغو دانلود...';
    _safeNotify();
  }

  Future<bool> downloadAndInstall({UpdateInfo? release}) async {
    final UpdateInfo? info = release ?? _available;
    if (info == null || _downloading || _installing) {
      return false;
    }
    if (!UpdateService.hasValidSha256(info.sha256)) {
      _error = 'برای امنیت، نصب این نسخه بدون SHA-256 معتبر متوقف شد.';
      _log.add(_error, level: 'error');
      _safeNotify();
      return false;
    }
    _downloading = true;
    _activeDownloadVersion = info.version;
    _cancelRequested = false;
    _progress = 0;
    _received = 0;
    _total = info.sizeBytes;
    _speedBytesPerSec = 0;
    _error = '';
    _phase = Fa.num('آماده سازی دانلود نسخه ${info.version}...');
    _safeNotify();

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
            _safeNotify();
          }
        },
      );
      if (_cancelRequested) {
        _downloading = false;
        _activeDownloadVersion = '';
        _cancelRequested = false;
        _speedBytesPerSec = 0;
        _progress = 0;
        _received = 0;
        _phase = '';
        _safeNotify();
        return false;
      }
      if (file == null) {
        _error = info.sha256.isNotEmpty
            ? 'دانلود کامل نشد یا اصالت فایل تایید نشد. دوباره تلاش کنید.'
            : 'دانلود بسته به روز رسانی ناموفق بود. دوباره تلاش کنید.';
        _log.add(_error, level: 'error');
        _downloading = false;
        _activeDownloadVersion = '';
        _speedBytesPerSec = 0;
        _phase = '';
        _safeNotify();
        return false;
      }

      _installing = true;
      _speedBytesPerSec = 0;
      _awaitingInstallPermission = false;
      _pendingInstallFile = null;
      _pendingInstallSha256 = '';
      _pendingInstallVersion = '';
      _phase = Fa.num('در حال نصب خودکار نسخه ${info.version}...');
      _safeNotify();

      final ({bool ok, String reason}) installRes =
          await _service.installDetailed(
        file,
        _native,
        expectedSha256: info.sha256,
      );
      if (!installRes.ok) {
        _activeDownloadVersion = '';
        return _handleInstallFailure(
          reason: installRes.reason,
          file: file,
          expectedSha256: info.sha256,
          version: info.version,
        );
      }

      _phase = 'صفحه نصب نسخه جدید باز شد؛ گزینه «به روز رسانی» را تایید کنید.';
      _log.add(Fa.num('نصب نسخه ${info.version} به اندروید سپرده شد.'));
      _installing = false;
      _downloading = false;
      _activeDownloadVersion = '';
      _safeNotify();

      final Future<void> Function()? exitHook = onExitForInstall;
      if (exitHook != null) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await exitHook();
      }
      return true;
    } on Exception {
      _error = 'خطا در دریافت یا نصب نسخه جدید؛ دوباره تلاش کنید.';
      _log.add(_error, level: 'error');
      _downloading = false;
      _installing = false;
      _activeDownloadVersion = '';
      _speedBytesPerSec = 0;
      _phase = '';
      _safeNotify();
      return false;
    }
  }

  /// پس از بازگشت کاربر از تنظیمات «اجازه نصب از این منبع»، فایل تاییدشدهٔ قبلی
  /// بدون دانلود دوباره بلافاصله نصب می شود.
  Future<bool> resumePendingInstallIfPermitted() async {
    final File? file = _pendingInstallFile;
    if (!_awaitingInstallPermission ||
        file == null ||
        _downloading ||
        _installing) {
      return false;
    }
    final Map<String, dynamic> info = await _native.getPlatformInfo();
    if (info['canRequestInstallPackages'] != true) {
      return false;
    }
    _awaitingInstallPermission = false;
    _installing = true;
    _error = '';
    _phase = Fa.num('در حال اجرای نصب نسخه $_pendingInstallVersion...');
    _safeNotify();

    final ({bool ok, String reason}) installRes =
        await _service.installDetailed(
      file,
      _native,
      expectedSha256: _pendingInstallSha256,
    );
    if (!installRes.ok) {
      return _handleInstallFailure(
        reason: installRes.reason,
        file: file,
        expectedSha256: _pendingInstallSha256,
        version: _pendingInstallVersion,
      );
    }

    _pendingInstallFile = null;
    _pendingInstallSha256 = '';
    _pendingInstallVersion = '';
    _phase = 'صفحه نصب نسخه جدید باز شد؛ گزینه «به روز رسانی» را تایید کنید.';
    _log.add('نصب خودکار نسخه جدید پس از تایید دسترسی آغاز شد.');
    _installing = false;
    _safeNotify();
    return true;
  }

  Future<bool> _handleInstallFailure({
    required String reason,
    required File file,
    required String expectedSha256,
    required String version,
  }) async {
    _installing = false;
    _downloading = false;
    _phase = '';
    switch (reason) {
      case 'install_permission_required':
        _awaitingInstallPermission = true;
        _pendingInstallFile = file;
        _pendingInstallSha256 = expectedSha256;
        _pendingInstallVersion = version;
        _error = 'دسترسی نصب برای آمبرلا هنوز فعال نیست؛ در صفحه تنظیمات بازشده '
            'گزینه «اجازه از این منبع» را روشن کنید و به برنامه برگردید.';
        break;
      case 'invalid_apk_archive':
      case 'sha256_mismatch':
        try {
          if (await file.exists()) {
            await file.delete();
          }
        } on Exception {
          // نادیده گرفته می شود.
        }
        _pendingInstallFile = null;
        _error = 'بسته نصب دریافت شده معتبر یا کامل نیست؛ دوباره روی دانلود و نصب بزنید.';
        break;
      case 'signature_mismatch':
        _pendingInstallFile = null;
        _error = 'امضای دیجیتال این نسخه با نسخه فعلی هم خوانی ندارد؛ '
            'ابتدا نسخه فعلی را حذف و سپس نسخه جدید را نصب کنید.';
        break;
      case 'package_mismatch':
        _pendingInstallFile = null;
        _error = 'شناسه بسته دریافت شده با برنامه آمبرلا مطابقت ندارد.';
        break;
      default:
        _pendingInstallFile = file;
        _pendingInstallSha256 = expectedSha256;
        _pendingInstallVersion = version;
        _error = 'باز کردن نصب کننده سیستم انجام نشد؛ دسترسی نصب برنامه ها را '
            'بررسی کرده و دوباره تلاش کنید.';
        break;
    }
    _log.add(_error, level: 'warning');
    _safeNotify();
    return false;
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
    return SafeUrlLauncher.open(uri, mode: LaunchMode.externalApplication);
  }
}
