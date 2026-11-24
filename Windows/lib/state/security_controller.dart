import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/malicious_link_guard.dart';
import '../core/utils.dart';
import '../models/models.dart';
import '../platform/native.dart';
import '../platform/services.dart';
import '../vpn/clash_api.dart';
import 'auth_controller.dart';

/// سپر امنیتی همیشه فعال آمبرلا:
/// پروسه ها، برنامه های نصب شده، رجیستری، فایل های دانلودی/تصاویر و لینک های باز شده را می پاید؛
/// فایل های بدافزار دانلودی و لینک های تروجانی را در لحظه حذف یا مسدود می کند
/// و اعلان فوری تلگرام برای کاربر ارسال می نماید.
class SecurityScannerController extends ChangeNotifier {
  SecurityScannerController({
    required NativeBridge native,
    AuthController? auth,
    this.isVpnActive,
    this.autoDeleteMaliciousDownloads = true,
  })  : _native = native,
        _auth = auth;

  final NativeBridge _native;
  final AuthController? _auth;

  /// حذف خودکار فایل های بدافزار و تصاویر آلوده هنگام کشف در پوشه دانلودها.
  final bool autoDeleteMaliciousDownloads;

  /// تابعی برای بررسی فعال بودن تونل VPN (برای قطع فوری هنگام تشخیص تهدید).
  bool Function()? isVpnActive;

  /// وقتی هنگام فعال بودن اتصال VPN تهدید جدی پیدا شود فراخوانی می شود.
  void Function(List<SecurityThreat> threats)? onThreatBlockedWhileConnected;

  /// وقتی یک فایل بدافزار یا لینک تروجانی به صورت خودکار حذف یا مسدود شود فراخوانی می شود.
  void Function(NeutralizedSecurityEvent event)? onThreatNeutralized;

  static const Duration scanInterval = Duration(seconds: 45);
  static const Duration _linkCooldown = Duration(seconds: 60);

  Timer? _timer;
  Timer? _watchDebounce;
  final List<StreamSubscription<FileSystemEvent>> _dirWatchers =
      <StreamSubscription<FileSystemEvent>>[];
  Future<SecurityScanResult>? _inflightScan;
  SecurityScanResult _lastResult = const SecurityScanResult();
  bool _scanning = false;
  bool _remediating = false;
  String _lastMessage = '';
  DateTime? _lastScannedAt;

  final List<NeutralizedSecurityEvent> _neutralizedEvents =
      <NeutralizedSecurityEvent>[];
  final List<NeutralizedSecurityEvent> _pendingNeutralizedForTelegram =
      <NeutralizedSecurityEvent>[];
  final Map<String, DateTime> _recentBlockedLinks = <String, DateTime>{};

  /// کلیدهایی که اخیراً به سرور گزارش شده اند تا پیش از تغییر وضعیت تکرار نشوند.
  Set<String> _reportedActiveKeys = <String>{};
  bool _hasCompletedInitialScan = false;

  bool get alwaysActive => true;
  bool get scanning => _scanning;
  bool get remediating => _remediating;
  SecurityScanResult get lastResult => _lastResult;
  List<SecurityThreat> get threats => _lastResult.threats;
  List<NeutralizedSecurityEvent> get neutralizedEvents =>
      List<NeutralizedSecurityEvent>.unmodifiable(_neutralizedEvents);
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

  void startMonitoring({bool watchDownloadFolders = true}) {
    if (_timer != null) return;
    unawaited(scanNow(silent: true));
    _timer = Timer.periodic(scanInterval, (_) {
      unawaited(scanNow(silent: true));
    });
    if (watchDownloadFolders) {
      _attachDownloadWatchers();
    }
  }

  void _attachDownloadWatchers() {
    if (_dirWatchers.isNotEmpty) return;
    final List<String> candidates = <String>[];
    final String? profile = Platform.environment['USERPROFILE'];
    if (profile != null && profile.isNotEmpty) {
      candidates.add('$profile\\Downloads');
      candidates.add('$profile\\Downloads\\Telegram Desktop');
      candidates.add('$profile\\Desktop');
      candidates.add('$profile\\Pictures');
    }
    for (final String path in candidates) {
      try {
        final Directory dir = Directory(path);
        if (!dir.existsSync()) continue;
        final StreamSubscription<FileSystemEvent> sub = dir
            .watch(events: FileSystemEvent.create | FileSystemEvent.modify)
            .listen(
          (FileSystemEvent event) {
            final String lower = event.path.toLowerCase();
            if (lower.contains('umbrella') ||
                lower.endsWith('.tmp') ||
                lower.endsWith('.crdownload') ||
                lower.endsWith('.part')) {
              return;
            }
            _watchDebounce?.cancel();
            _watchDebounce = Timer(const Duration(milliseconds: 800), () {
              unawaited(scanNow(silent: true));
            });
          },
          onError: (_) {},
        );
        _dirWatchers.add(sub);
      } catch (_) {}
    }
  }

  void stopMonitoring() {
    _timer?.cancel();
    _timer = null;
    _watchDebounce?.cancel();
    _watchDebounce = null;
    for (final StreamSubscription<FileSystemEvent> sub in _dirWatchers) {
      unawaited(sub.cancel());
    }
    _dirWatchers.clear();
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
      final SecurityScanResult rawResult = await _native.scanDeviceSecurity();
      final List<SecurityThreat> remaining = <SecurityThreat>[];
      final List<NeutralizedSecurityEvent> newlyDeleted =
          <NeutralizedSecurityEvent>[];

      for (final SecurityThreat threat in rawResult.threats) {
        if (autoDeleteMaliciousDownloads && threat.isAutoRemediableFile) {
          final RemediationResult outcome =
              await _native.remediateSecurityThreat(threat);
          if (outcome.ok) {
            final NeutralizedSecurityEvent event = NeutralizedSecurityEvent(
              key: threat.key,
              name: threat.name,
              category: threat.category == 'malicious_link'
                  ? 'malicious_link'
                  : 'malicious_download',
              severity: threat.severity,
              target: threat.target.isNotEmpty ? threat.target : threat.path,
              detail: threat.detail.isNotEmpty
                  ? threat.detail
                  : 'فایل دانلود شده حاوی بدافزار شناسایی و به صورت خودکار حذف شد.',
              action: 'deleted',
              timestampMs: DateTime.now().millisecondsSinceEpoch,
            );
            newlyDeleted.add(event);
            _recordNeutralizedEvent(event, queueTelegram: true);
            AppLogger.instance.add(
              'سپر امنیتی آمبرلا فایل آلوده را خودکار حذف کرد: ${threat.name}',
              level: 'warning',
            );
            continue;
          }
        }
        remaining.add(threat);
      }

      final SecurityScanResult effective = rawResult.copyWith(
        clean: remaining.isEmpty,
        threats: remaining,
      );

      final Set<String> prevKeys =
          _lastResult.threats.map((SecurityThreat t) => t.key).toSet();
      final Set<String> nextKeys =
          effective.threats.map((SecurityThreat t) => t.key).toSet();

      _lastResult = effective;
      _hasCompletedInitialScan = true;
      _lastScannedAt = DateTime.now();

      if (newlyDeleted.isNotEmpty) {
        _lastMessage = newlyDeleted.length == 1
            ? 'فایل بدافزار «${newlyDeleted.first.name}» شناسایی و به صورت خودکار حذف شد.'
            : '${Fa.num(newlyDeleted.length)} فایل آلوده شناسایی و خودکار حذف شدند.';
      }

      final bool changed =
          prevKeys.length != nextKeys.length || !prevKeys.containsAll(nextKeys);
      if (changed && effective.hasThreats) {
        final String summary =
            effective.threats.map((SecurityThreat t) => t.name).join('، ');
        AppLogger.instance.add(
          'سپر امنیتی آمبرلا تهدید شناسایی کرد: $summary',
          level: 'warning',
        );
      }

      if (effective.hasThreats && (isVpnActive?.call() ?? false)) {
        onThreatBlockedWhileConnected?.call(effective.threats);
      }

      await _syncServerAlertsIfNeeded(effective);
      return effective;
    } catch (error) {
      AppLogger.instance.add('خطا در پایش امنیتی: $error', level: 'warning');
      return _lastResult;
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  void _recordNeutralizedEvent(
    NeutralizedSecurityEvent event, {
    required bool queueTelegram,
  }) {
    _neutralizedEvents.insert(0, event);
    if (_neutralizedEvents.length > 24) {
      _neutralizedEvents.removeRange(24, _neutralizedEvents.length);
    }
    if (queueTelegram) {
      _pendingNeutralizedForTelegram.add(event);
    }
    onThreatNeutralized?.call(event);
  }

  /// بررسی اتصالات زنده VPN و قطع فوری لینک ها یا دامنه های تروجانی در لحظه باز شدن.
  Future<int> inspectLiveConnections(
    List<CoreActivitySample> samples, {
    Future<bool> Function(String id)? closeConnection,
  }) async {
    int blockedCount = 0;
    bool addedNotice = false;
    final DateTime now = DateTime.now();

    for (final CoreActivitySample sample in samples) {
      final String host = sample.host.trim();
      if (host.isEmpty) continue;
      final MaliciousLinkMatch? hit = MaliciousLinkGuard.inspectHost(host);
      if (hit == null) continue;

      blockedCount++;
      if (sample.id.isNotEmpty) {
        try {
          final Future<bool> Function(String id) closer =
              closeConnection ?? ClashApi.closeConnection;
          await closer(sample.id);
        } catch (_) {}
      }

      final DateTime? last = _recentBlockedLinks[hit.key];
      if (last != null && now.difference(last) < _linkCooldown) {
        continue;
      }
      _recentBlockedLinks[hit.key] = now;
      final String procNote = sample.process.isNotEmpty
          ? ' (برنامه: ${sample.process})'
          : '';
      final NeutralizedSecurityEvent event = NeutralizedSecurityEvent(
        key: hit.key,
        name: hit.title,
        category: 'malicious_link',
        severity: hit.severity,
        target: hit.target,
        detail: '${hit.detail}$procNote',
        action: 'blocked_connection',
        timestampMs: now.millisecondsSinceEpoch,
      );
      _lastMessage = 'ارتباط با لینک یا دامنه تروجانی ${hit.host} مسدود شد.';
      AppLogger.instance.add(
        'سپر امنیتی لینک تروجانی را مسدود کرد: ${hit.host}$procNote',
        level: 'warning',
      );
      _recordNeutralizedEvent(event, queueTelegram: true);
      addedNotice = true;
    }

    if (addedNotice) {
      notifyListeners();
      await _syncServerAlertsIfNeeded(_lastResult);
    }
    return blockedCount;
  }

  /// بررسی امنیتی دستی یا کلیپ بوردی یک لینک پیش از باز شدن.
  Future<MaliciousLinkMatch?> inspectAndBlockUrl(String rawUrl) async {
    final MaliciousLinkMatch? hit = MaliciousLinkGuard.inspectUrl(rawUrl);
    if (hit == null) {
      _lastMessage = 'بررسی لینک کامل شد؛ مورد تروجانی یا مشکوکی یافت نشد.';
      notifyListeners();
      return null;
    }

    final DateTime now = DateTime.now();
    _recentBlockedLinks[hit.key] = now;
    final NeutralizedSecurityEvent event = NeutralizedSecurityEvent(
      key: hit.key,
      name: hit.title,
      category: 'malicious_link',
      severity: hit.severity,
      target: hit.target,
      detail: hit.detail,
      action: 'blocked_connection',
      timestampMs: now.millisecondsSinceEpoch,
    );
    _lastMessage = '${hit.title}: ${hit.detail}';
    AppLogger.instance.add(
      'لینک تروجانی مسدود شد: ${hit.target}',
      level: 'warning',
    );
    _recordNeutralizedEvent(event, queueTelegram: true);
    notifyListeners();
    await _syncServerAlertsIfNeeded(_lastResult);
    return hit;
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
      if (outcome.ok && threat.remediationKind == 'file') {
        _recordNeutralizedEvent(
          NeutralizedSecurityEvent(
            key: threat.key,
            name: threat.name,
            category: threat.category == 'malicious_link'
                ? 'malicious_link'
                : 'malicious_download',
            severity: threat.severity,
            target: threat.target.isNotEmpty ? threat.target : threat.path,
            detail: threat.detail,
            action: 'deleted',
            timestampMs: DateTime.now().millisecondsSinceEpoch,
          ),
          queueTelegram: true,
        );
      }
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
    final List<NeutralizedSecurityEvent> pendingBatch =
        List<NeutralizedSecurityEvent>.from(_pendingNeutralizedForTelegram);
    if (!hasNew && resolved.isEmpty && pendingBatch.isEmpty) {
      return;
    }

    try {
      await auth.gateway.reportSecurityAlert(
        token: session.token,
        deviceId: auth.deviceId,
        platform: Platform.isAndroid ? 'Android' : 'Windows',
        appVersion: AppConfig.version,
        threats: result.threats,
        neutralized: pendingBatch,
        resolvedKeys: resolved,
        syncAll: true,
      );
      _reportedActiveKeys = currentKeys;
      for (final NeutralizedSecurityEvent sent in pendingBatch) {
        _pendingNeutralizedForTelegram.remove(sent);
      }
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
