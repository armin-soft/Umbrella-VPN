import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/utils.dart';
import '../models/models.dart';
import '../platform/native.dart';
import '../platform/services.dart';
import 'auth_controller.dart';

/// سپر امنیتی همیشه فعال آمبرلا:
/// پروسه ها، برنامه های نصب شده، رجیستری و فایل های پرخطر را می پاید؛
/// بدافزارها (مانند JumpJump) و فیلترشکن های ناسازگار (مانند Psiphon) را مسدود و پاکسازی می کند
/// و رخدادها را برای مدیر در ربات تلگرام ارسال می نماید.
class SecurityScannerController extends ChangeNotifier {
  SecurityScannerController({
    required NativeBridge native,
    AuthController? auth,
    this.isVpnActive,
  })  : _native = native,
        _auth = auth;

  final NativeBridge _native;
  final AuthController? _auth;

  /// تابعی برای بررسی فعال بودن تونل VPN (برای قطع فوری هنگام تشخیص تهدید).
  bool Function()? isVpnActive;

  /// وقتی هنگام فعال بودن اتصال VPN تهدید جدی پیدا شود فراخوانی می شود.
  void Function(List<SecurityThreat> threats)? onThreatBlockedWhileConnected;

  static const Duration scanInterval = Duration(seconds: 45);

  Timer? _timer;
  Future<SecurityScanResult>? _inflightScan;
  SecurityScanResult _lastResult = const SecurityScanResult();
  bool _scanning = false;
  bool _remediating = false;
  String _lastMessage = '';
  DateTime? _lastScannedAt;

  /// کلیدهایی که اخیراً به سرور گزارش شده اند تا پیش از تغییر وضعیت تکرار نشوند.
  Set<String> _reportedActiveKeys = <String>{};
  bool _hasCompletedInitialScan = false;

  bool get alwaysActive => true;
  bool get scanning => _scanning;
  bool get remediating => _remediating;
  SecurityScanResult get lastResult => _lastResult;
  List<SecurityThreat> get threats => _lastResult.threats;
  bool get hasThreats => _lastResult.hasThreats;
  bool get isClean => !_lastResult.hasThreats;
  bool get hasCompletedInitialScan => _hasCompletedInitialScan;
  DateTime? get lastScannedAt => _lastScannedAt;
  String get lastMessage => _lastMessage;

  String get shortBadgeLabel {
    if (_scanning && !_hasCompletedInitialScan) {
      return 'در حال پایش امنیتی';
    }
    if (hasThreats) {
      return 'هشدار امنیتی (${Fa.num(threats.length)})';
    }
    return 'دستگاه ایمن است';
  }

  void startMonitoring() {
    if (_timer != null) return;
    unawaited(scanNow(silent: true));
    _timer = Timer.periodic(scanInterval, (_) {
      unawaited(scanNow(silent: true));
    });
  }

  void stopMonitoring() {
    _timer?.cancel();
    _timer = null;
  }

  Future<SecurityScanResult> scanNow({bool silent = false}) {
    final Future<SecurityScanResult>? running = _inflightScan;
    if (running != null) {
      return running;
    }
    final Future<SecurityScanResult> task = _performScan(silent: silent);
    _inflightScan = task;
    task.whenComplete(() {
      if (identical(_inflightScan, task)) {
        _inflightScan = null;
      }
    });
    return task;
  }

  Future<SecurityScanResult> _performScan({required bool silent}) async {
    _scanning = true;
    if (!silent) {
      notifyListeners();
    }
    try {
      final SecurityScanResult result = await _native.scanDeviceSecurity();
      final Set<String> prevKeys =
          _lastResult.threats.map((SecurityThreat t) => t.key).toSet();
      final Set<String> nextKeys =
          result.threats.map((SecurityThreat t) => t.key).toSet();

      _lastResult = result;
      _hasCompletedInitialScan = true;
      _lastScannedAt = DateTime.now();

      final bool changed =
          prevKeys.length != nextKeys.length || !prevKeys.containsAll(nextKeys);
      if (changed && result.hasThreats) {
        final String summary =
            result.threats.map((SecurityThreat t) => t.name).join('، ');
        AppLogger.instance.add(
          'سپر امنیتی آمبرلا تهدید شناسایی کرد: $summary',
          level: 'warning',
        );
      }

      if (result.hasThreats && (isVpnActive?.call() ?? false)) {
        onThreatBlockedWhileConnected?.call(result.threats);
      }

      await _syncServerAlertsIfNeeded(result);
      return result;
    } catch (error) {
      AppLogger.instance.add('خطا در پایش امنیتی: $error', level: 'warning');
      return _lastResult;
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  /// پیش از هر بار اتصال بررسی می کند سیستم پاک باشد؛ در غیر این صورت اتصال مسدود می شود.
  Future<SecurityScanResult> ensureCleanBeforeConnect() async {
    final SecurityScanResult result = await scanNow(silent: false);
    if (result.hasThreats) {
      _lastMessage =
          'پیش از برقراری اتصال باید برنامه ها یا تهدیدهای مسدود شده حذف شوند.';
      notifyListeners();
    }
    return result;
  }

  Future<RemediationResult> remediateThreat(SecurityThreat threat) async {
    if (_remediating) {
      return const RemediationResult(
        ok: false,
        stillPresent: true,
        message: 'عملیات پاکسازی قبلی در حال انجام است.',
      );
    }
    _remediating = true;
    _lastMessage = 'در حال پاکسازی ${threat.name}...';
    notifyListeners();
    try {
      final RemediationResult outcome =
          await _native.remediateSecurityThreat(threat);
      _lastMessage = outcome.message;
      AppLogger.instance.add(
        'نتیجه پاکسازی (${threat.name}): ${outcome.message}',
        level: outcome.ok ? 'info' : 'warning',
      );
      await scanNow(silent: true);
      return outcome;
    } finally {
      _remediating = false;
      notifyListeners();
    }
  }

  Future<SecurityScanResult> remediateAll() async {
    if (_remediating || threats.isEmpty) {
      return _lastResult;
    }
    _remediating = true;
    _lastMessage = 'در حال توقف و پاکسازی همه تهدیدهای شناسایی شده...';
    notifyListeners();
    try {
      final List<SecurityThreat> copy = List<SecurityThreat>.from(threats);
      for (final SecurityThreat threat in copy) {
        await _native.remediateSecurityThreat(threat);
      }
      final SecurityScanResult after = await scanNow(silent: true);
      _lastMessage = after.clean
          ? 'تمام تهدیدها و برنامه های ناسازگار با موفقیت پاکسازی شدند.'
          : 'برخی موارد همچنان باقی مانده اند؛ حذف دستی یا دسترسی مدیر لازم است.';
      return after;
    } finally {
      _remediating = false;
      notifyListeners();
    }
  }

  Future<void> _syncServerAlertsIfNeeded(SecurityScanResult result) async {
    final AuthController? auth = _auth;
    if (auth == null || !auth.signedIn) return;
    final SessionData? session = auth.session;
    if (session == null || session.token.isEmpty) return;

    final Set<String> currentKeys =
        result.threats.map((SecurityThreat t) => t.key).toSet();
    final List<String> resolved = _reportedActiveKeys
        .where((String k) => !currentKeys.contains(k))
        .toList();

    final bool hasNew =
        currentKeys.any((String k) => !_reportedActiveKeys.contains(k));
    if (!hasNew && resolved.isEmpty) {
      return;
    }

    try {
      await auth.gateway.reportSecurityAlert(
        token: session.token,
        deviceId: auth.deviceId,
        platform: Platform.isAndroid ? 'Android' : 'Windows',
        appVersion: AppConfig.version,
        threats: result.threats,
        resolvedKeys: resolved,
        syncAll: true,
      );
      _reportedActiveKeys = currentKeys;
    } catch (_) {
      // اگر شبکه موقتاً در دسترس نبود، در اسکن بعدی دوباره همگام می شود.
    }
  }

  void resetReportedCache() {
    _reportedActiveKeys = <String>{};
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}
