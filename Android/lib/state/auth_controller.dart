import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/storage.dart';
import '../core/utils.dart';
import '../data/panel_client.dart';
import '../data/gateway_client.dart';
import '../models/models.dart';
import '../platform/native.dart';
import '../platform/services.dart';

enum AuthPhase { phone, profile, code, telegram, done }

/// ورود دو مرحله ای: شماره موبایل، سپس کد پیامکی، سپس تایید دستگاه در تلگرام.
///
/// اگر شماره در سرویس یا ربات نباشد، پیش از ارسال کد نام و نام خانوادگی
/// خواسته می شود. همه تصمیم ها (خودم بودم / نبودم) در سرور و تلگرام انجام
/// می شود و برنامه فقط وضعیت را می پرسد.
class AuthController extends ChangeNotifier {
  AuthController({
    required NativeBridge native,
    GatewayClient? gateway,
    String? gatewayBase,
    LocalStore? store,
    SoundService? sound,
    TrayService? tray,
  })  : _native = native,
        _injectedGateway = gateway != null,
        _sound = sound,
        _tray = tray,
        _store = store ?? LocalStore.instance {
    // نشانی ذخیره شده در تنظیمات بر پیش فرض برنامه اولویت دارد.
    final String stored = _store.read(AppConfig.gatewayStoreKey) ?? '';
    _gateway = gateway ??
        GatewayClient(
          baseUrl: stored.isNotEmpty ? stored : gatewayBase,
        );
  }

  final NativeBridge _native;
  final bool _injectedGateway;
  late GatewayClient _gateway;
  final LocalStore _store;
  final AppLogger _log = AppLogger.instance;

  /// پخش صدای اعلان و بالون سینی سیستم؛ اگر ساخته نشده باشند بی صدا رد می شوند.
  final SoundService? _sound;
  final TrayService? _tray;

  /// آیا اعلان ها با صدا و بالون ویندوز اعلام شوند؟ از تنظیمات کاربر.
  bool notificationsEnabled = true;
  bool soundEnabled = true;

  /// شناسه اعلان هایی که یک بار اعلام شده اند تا با هر به روز رسانی حساب،
  /// صدا و بالون تکرار نشود.
  final Set<String> _announced = <String>{};

  SessionData? _session;
  SessionData? get session => _session;
  bool get signedIn => _session != null;
  Account get account => _session?.account ?? Account.empty;
  FilterSettings get filter => _session?.filter ?? FilterSettings.empty;

  AuthPhase _phase = AuthPhase.phone;
  AuthPhase get phase => _phase;

  SignInStage _stage = SignInStage.unknown;
  SignInStage get stage => _stage;

  String _phone = '';
  String get phone => _phone;

  String _firstName = '';
  String _lastName = '';
  String get firstName => _firstName;
  String get lastName => _lastName;

  String _challenge = '';
  String get challenge => _challenge;

  bool _busy = false;
  bool get busy => _busy;

  String _error = '';
  String get error => _error;

  String _info = '';
  String get info => _info;

  String _botUrl = 'https://t.me/${AppConfig.botUsername}';
  String get botUrl => _botUrl;

  int _secondsLeft = 0;
  int get secondsLeft => _secondsLeft;

  int _resendIn = 0;
  int get resendIn => _resendIn;

  String _deviceId = '';
  String get deviceId => _deviceId;

  DeviceProfile _device = DeviceProfile.empty;
  DeviceProfile get device => _device;

  static const int maxStoredNotifications = 100;

  List<AppNotification> _notifications = <AppNotification>[];
  List<AppNotification> get notifications => List<AppNotification>.unmodifiable(_notifications);
  int get unreadCount =>
      _notifications.where((AppNotification item) => !item.read).length;

  bool _loadingNotifications = false;
  bool get loadingNotifications => _loadingNotifications;
  Future<void>? _notificationsFetch;
  bool _historySynced = false;

  bool _syncingFilter = false;
  bool get syncingFilter => _syncingFilter;
  bool _savingFilter = false;
  bool get savingFilter => _savingFilter;

  bool _claimingOffer = false;
  bool get claimingOffer => _claimingOffer;
  String _claimingPlanType = '';
  String get claimingPlanType => _claimingPlanType;

  SubscriptionOffers get offers => _session?.offers ?? SubscriptionOffers.empty;

  /// وقتی کنترل محتوا تغییر کند (از برنامه یا مستقیم از ربات تلگرام) صدا زده
  /// می شود تا هسته اتصال قوانین جدید را بلافاصله اعمال کند.
  void Function(FilterSettings filter)? onFilterChanged;

  /// پس از فعال سازی موفق اشتراک رایگان یا نوروزی صدا زده می شود تا سرورهای
  /// شخصی کاربر بی درنگ دریافت شوند.
  Future<void> Function()? onSubscriptionClaimed;

  Timer? _pollTimer;
  Timer? _clockTimer;
  Timer? _heartbeatTimer;
  bool _restored = false;
  bool _checkingDeviceAccess = false;
  bool _revokingSession = false;

  Future<void> restore() async {
    if (_restored) {
      return;
    }
    _restored = true;
    _device = await _native.deviceInfo();
    // Keep the phone field filled after an update or an expired server session.
    // The sign-in token is restored separately below; never save an OTP.
    _phone = _store.read(StoreKeys.lastPhone) ?? '';
    _deviceId = _store.read(StoreKeys.deviceId) ?? '';
    if (_deviceId.isEmpty) {
      _deviceId = _generateDeviceId();
      await _store.write(StoreKeys.deviceId, _deviceId);
    }
    // اعلان های ذخیره شده پیش از شروع پایش دوره ای بارگذاری می شوند تا هیچ
    // درخواست همزمانی تاریخچه قبلی را جا نیندازد یا دوباره صدا ندهد.
    final List<dynamic> cached = _store.readJsonList(StoreKeys.notifications);
    _notifications = _sortAndTrim(
      cached
          .map((Object? item) => AppNotification.fromJson(JsonX.asMap(item)))
          .where((AppNotification item) => !_isStaleDeviceRevocation(item))
          .toList(),
    );
    for (final AppNotification item in _notifications) {
      _announced.add(_keyOf(item));
    }
    final Map<String, dynamic> json = _store.readJson(StoreKeys.session);
    if (json.isNotEmpty) {
      _session = SessionData.fromJson(json);
      if (_session!.token.isEmpty) {
        _session = null;
      } else {
        _phase = AuthPhase.done;
        _phone = _session!.account.phone;
        await _syncNotificationOwner(_session!.ownerKey);
        onFilterChanged?.call(filter);
        _startHeartbeat();
        unawaited(refreshAccount(silent: true));
      }
    }
    notifyListeners();
  }

  String _generateDeviceId() {
    final Random random = Random.secure();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < 16; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// خطای سرویس فقط یک بار ثبت می شود تا پایش دوره ای گزارش را پر نکند.
  String _lastServiceError = '';

  void _logError(String message) {
    final String detail = _gateway.lastDiagnostic;
    final String full = detail.isEmpty ? message : '$message [$detail]';
    if (full == _lastServiceError) {
      return;
    }
    _lastServiceError = full;
    _log.add('خطای سرویس: $full', level: 'error');
  }

  /// اگر نشانی سفارشی کهنه در تنظیمات ذخیره شده باشد و خطای شبکه یا ۴۰۴ بدهد،
  /// به صورت خودکار نشانی پیش فرض رسمی آمبرلا آزموده و جایگزین می شود.
  Future<T> _callGatewayWithDefaultFallback<T>(
    Future<T> Function(GatewayClient client) call,
  ) async {
    try {
      return await call(_gateway);
    } on ApiError catch (error) {
      final bool retriable = error.code == 'network' ||
          error.code == 'timeout' ||
          error.code == 'bad_response';
      final bool usingCustom = !_injectedGateway &&
          _gateway.baseUrl.trim() != AppConfig.gatewayBase.trim();
      if (!retriable || !usingCustom) {
        rethrow;
      }
      final GatewayClient fallback =
          GatewayClient(baseUrl: AppConfig.gatewayBase);
      try {
        final T result = await call(fallback);
        final GatewayClient previous = _gateway;
        _gateway = fallback;
        previous.close();
        await _store.remove(AppConfig.gatewayStoreKey);
        _log.add('نشانی درگاه به نشانی رسمی پیش فرض بازگردانی شد.');
        return result;
      } on Object {
        fallback.close();
        rethrow;
      }
    }
  }

  String get baseUrl => _gateway.baseUrl;

  /// نشانی درگاهی که همین حالا استفاده می شود.
  String get gatewayBase => _gateway.baseUrl;

  String get gatewayHost => Uri.tryParse(_gateway.baseUrl)?.host ?? '';

  /// نشانی درگاه را عوض می کند و کلاینت را با نشانی تازه می سازد؛ مقدار
  /// خالی یعنی بازگشت به پیش فرض برنامه.
  Future<void> setGatewayBase(String base) async {
    final String cleaned = base.trim();
    if (cleaned.isEmpty) {
      await _store.remove(AppConfig.gatewayStoreKey);
      _gateway.close();
      _gateway = GatewayClient();
      notifyListeners();
      return;
    }
    final Uri? parsed = Uri.tryParse(cleaned);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      _error = 'نشانی درگاه معتبر نیست؛ نشانی کامل درگاه ربات را وارد کنید.';
      notifyListeners();
      return;
    }
    await _store.write(AppConfig.gatewayStoreKey, cleaned);
    _gateway.close();
    _gateway = GatewayClient(baseUrl: cleaned);
    _error = '';
    notifyListeners();
  }

  /// یک درخواست سبک به درگاه می زند تا کاربر مطمئن شود نشانی درست است.
  Future<bool> testGateway() async {
    _busy = true;
    _error = '';
    notifyListeners();
    final bool ok = await _gateway.ping();
    _busy = false;
    if (!ok) {
      _error = 'درگاه $gatewayHost پاسخ نداد؛ نشانی را بررسی کنید.';
    }
    notifyListeners();
    return ok;
  }

  // ── گام یک: شماره موبایل ─────────────────────────────────────────────

  Future<bool> submitPhone(String rawPhone) async {
    _revokingSession = false;
    final String phone = IranPhone.normalize(rawPhone);
    _error = '';
    _info = '';
    if (!IranPhone.isValid(phone)) {
      _error = 'شماره موبایل معتبر نیست؛ نمونه: ۰۹۱۲۳۴۵۶۷۸۹';
      notifyListeners();
      return false;
    }
    _phone = phone;
    _busy = true;
    notifyListeners();
    try {
      final SignInStart start = await _callGatewayWithDefaultFallback(
        (GatewayClient client) => client.start(
          phone: phone,
          deviceId: _deviceId,
          deviceName: _device.deviceName,
          platform: _device.platformLabel,
        ),
      );
      _challenge = start.challenge;
      _stage = start.stage;
      _secondsLeft = start.resendAfter;
      _startClock();
      if (start.stage == SignInStage.needsProfile) {
        _phase = AuthPhase.profile;
        _info = 'این شماره حساب ندارد؛ نام و نام خانوادگی را وارد کنید.';
      } else {
        _phase = AuthPhase.code;
        _info = 'کد تایید برای شماره ${IranPhone.display(phone)} پیامک شد.';
      }
      await _store.write(StoreKeys.lastPhone, phone);
      _log.add('درخواست ورود برای ${IranPhone.display(phone)} ارسال شد.');
      return true;
    } on ApiError catch (error) {
      _error = error.message;
      _logError(error.message);
      if (error.retryAfter != null) {
        _secondsLeft = error.retryAfter!;
        _startClock();
      }
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ── گام دو: نام و نام خانوادگی برای کاربر جدید ───────────────────────

  Future<bool> submitProfile(String first, String last) async {
    _error = '';
    if (!IranPhone.validName(first) || !IranPhone.validName(last)) {
      _error = 'نام و نام خانوادگی را فارسی و بدون عدد وارد کنید.';
      notifyListeners();
      return false;
    }
    _firstName = IranPhone.normalizeName(first);
    _lastName = IranPhone.normalizeName(last);
    _busy = true;
    notifyListeners();
    try {
      final SignInStart start = await _callGatewayWithDefaultFallback(
        (GatewayClient client) => client.start(
          phone: _phone,
          deviceId: _deviceId,
          deviceName: _device.deviceName,
          platform: _device.platformLabel,
          firstName: _firstName,
          lastName: _lastName,
        ),
      );
      _challenge = start.challenge;
      _stage = start.stage;
      _phase = AuthPhase.code;
      _secondsLeft = start.resendAfter;
      _startClock();
      _info = 'حساب شما ساخته شد و کد تایید پیامک شد.';
      return true;
    } on ApiError catch (error) {
      _error = error.message;
      _logError(error.message);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ── گام سه: کد تایید ─────────────────────────────────────────────────

  Future<bool> verifyCode(String code) async {
    _error = '';
    final String clean = Fa.toEn(code).trim();
    if (!RegExp(r'^\d{5,6}$').hasMatch(clean)) {
      _error = 'کد تایید ۵ یا ۶ رقمی است.';
      notifyListeners();
      return false;
    }
    _busy = true;
    notifyListeners();
    try {
      final SignInVerify result =
          await _gateway.verify(challenge: _challenge, code: clean);
      _stage = result.stage;
      if (result.botUrl.isNotEmpty) {
        _botUrl = result.botUrl;
      }
      if (result.stage == SignInStage.awaitingTelegram ||
          result.stage == SignInStage.needsTelegram) {
        _phase = AuthPhase.telegram;
        _info = result.message.isNotEmpty
            ? result.message
            : 'جزئیات دستگاه به تلگرام شما ارسال شد؛ تایید کنید.';
        _startPolling();
      } else if (result.stage == SignInStage.approved) {
        await _finishSignIn();
      } else {
        _error = 'وضعیت ورود نامشخص است؛ دوباره تلاش کنید.';
      }
      return true;
    } on ApiError catch (error) {
      _error = error.message;
      _logError(error.message);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (Timer timer) async {
      if (_challenge.isEmpty) {
        timer.cancel();
        return;
      }
      try {
        final SignInStatus status = await _gateway.status(_challenge);
        _stage = status.stage;
        _secondsLeft = status.secondsLeft;
        if (status.stage == SignInStage.approved) {
          timer.cancel();
          await _finishSignIn();
        } else if (status.stage == SignInStage.denied) {
          timer.cancel();
          _error = 'ورود از طرف تلگرام رد شد.';
          _phase = AuthPhase.phone;
          notifyListeners();
        } else if (status.stage == SignInStage.expired) {
          timer.cancel();
          _error = 'زمان تایید به پایان رسید؛ دوباره تلاش کنید.';
          _phase = AuthPhase.phone;
          notifyListeners();
        } else {
          notifyListeners();
        }
      } on ApiError catch (error) {
        if (error.code == 'unknown_challenge') {
          timer.cancel();
        }
      }
    });
  }

  Future<void> _finishSignIn() async {
    try {
      final SessionData session = await _gateway.session(_challenge);
      _session = session;
      _phase = AuthPhase.done;
      _phone = session.account.phone.isNotEmpty ? session.account.phone : _phone;
      _historySynced = false;
      await _syncNotificationOwner(session.ownerKey);
      await _store.writeJson(StoreKeys.session, session.toJson());
      await _store.writeJson(StoreKeys.filter, session.filter.toJson());
      onFilterChanged?.call(session.filter);
      _startHeartbeat();
      _log.add('ورود موفق؛ خوش آمدید ${session.account.displayName}.');
      notifyListeners();
      // نشست فقط خلاصه حساب را دارد؛ پروفایل کامل و نشانی اشتراک از همین
      // مسیر از سرور گرفته می شود.
      unawaited(refreshAccount(silent: true));
    } on ApiError catch (error) {
      _error = error.message;
      _logError(error.message);
      notifyListeners();
    }
  }

  Future<void> checkNow() async {
    if (_challenge.isEmpty) {
      return;
    }
    _busy = true;
    notifyListeners();
    try {
      final SignInStatus status = await _gateway.status(_challenge);
      _stage = status.stage;
      _secondsLeft = status.secondsLeft;
      if (status.stage == SignInStage.approved) {
        await _finishSignIn();
      }
    } on ApiError catch (error) {
      _error = error.message;
      _logError(error.message);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> resendCode() async {
    if (_resendIn > 0 || _challenge.isEmpty) {
      return;
    }
    _error = '';
    try {
      await _gateway.resend(_challenge);
      _secondsLeft = 120;
      _info = 'کد جدید پیامک شد.';
      _startClock();
    } on ApiError catch (error) {
      _error = error.message;
      _logError(error.message);
    }
    notifyListeners();
  }

  void _startClock() {
    _clockTimer?.cancel();
    _resendIn = _secondsLeft;
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (_secondsLeft > 0) {
        _secondsLeft--;
      }
      if (_resendIn > 0) {
        _resendIn--;
      }
      if (_secondsLeft == 0 && _resendIn == 0) {
        timer.cancel();
      }
      notifyListeners();
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    unawaited(_checkDeviceAccess());
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_checkDeviceAccess());
    });
  }

  /// وضعیت مجوز دستگاه از درگاه بررسی می شود. خطای شبکه نشست را باطل نمی کند؛
  /// اما لغو دسترسی از تلگرام، اعلان را نشان می دهد و سپس کاربر را خارج می کند.
  Future<void> _checkDeviceAccess() async {
    if (_checkingDeviceAccess || _revokingSession) return;
    final SessionData? session = _session;
    if (session == null) return;

    _checkingDeviceAccess = true;
    try {
      final ({FilterSettings? filter, SubscriptionOffers? offers}) beat =
          await _gateway.heartbeat(token: session.token, deviceId: _deviceId);
      await _applyLiveServerState(filter: beat.filter, offers: beat.offers);
      final bool wantHistory = !_historySynced;
      await fetchNotifications(includeHistory: wantHistory);
    } on ApiError catch (error) {
      if (error.code == 'device_revoked') {
        await _handleDeviceRevoked(error.message);
      } else if (error.needsLogin) {
        await signOut(callServer: false);
        _error = 'نشست منقضی شد؛ برای ادامه دوباره وارد شوید.';
        notifyListeners();
      }
    } finally {
      _checkingDeviceAccess = false;
    }
  }

  Future<void> _handleDeviceRevoked(String serverMessage) async {
    if (_revokingSession || _session == null) return;
    _revokingSession = true;
    _heartbeatTimer?.cancel();
    final String message = serverMessage.trim().isEmpty
        ? 'مجوز استفاده از این دستگاه در تلگرام لغو شده است. برای استفاده دوباره، دوباره وارد شوید.'
        : serverMessage;
    _error = message;
    _info = 'پس از نمایش این اعلان از حساب خارج می شوید.';
    notifyListeners();

    // اعلان و قطع تونل پیش از پاک شدن نشست انجام می شود تا کاربر علت خروج را ببیند.
    try {
      await onSessionRevoked?.call(message);
    } catch (_) {
      // خروج محلی باید حتی اگر اعلان یا قطع اتصال خطا داد انجام شود.
    }
    if (notificationsEnabled) {
      try {
        await _tray?.balloon('مجوز این دستگاه لغو شد', message, warning: true);
      } catch (_) {}
    }
    if (soundEnabled) {
      try {
        await _sound?.play('notify');
      } catch (_) {}
    }

    await signOut(callServer: false);
    _error = message;
    _info = 'برای استفاده دوباره از نرم افزار، دوباره وارد شوید و دستگاه را در تلگرام تایید کنید.';
    notifyListeners();
  }

  /// اعلان و قطع اتصال برای سلب مجوز دستگاه (جدا از اتمام اشتراک).
  Future<void> Function(String reason)? onSessionRevoked;

  /// خواندن اعداد دقیق حساب از پنل؛ اگر پنل جواب ندهد همان داده درگاه
  /// استفاده می شود و چیزی خراب نمی شود.
  Future<bool> refreshFromPanel() async {
    final SessionData? session = _session;
    if (session == null) {
      return false;
    }
    final String uuid = session.account.uuid;
    if (uuid.isEmpty) {
      return false;
    }
    final Account? panel = await PanelUserApi().user(uuid);
    if (panel == null) {
      return false;
    }
    final Account merged = session.account.copyWith(
      panelId: panel.panelId > 0 ? panel.panelId : null,
      name: panel.name.isNotEmpty ? panel.name : null,
      phone: panel.effectivePhone.isNotEmpty ? panel.effectivePhone : null,
      telegramId: panel.telegramId.isNotEmpty ? panel.telegramId : null,
      comment: panel.comment.isNotEmpty ? panel.comment : null,
      enable: panel.enable,
      isActive: panel.isActive,
      usageLimitGb: panel.usageLimitGb >= 0 ? panel.usageLimitGb : null,
      currentUsageGb: panel.currentUsageGb,
      packageDays: panel.packageDays > 0 ? panel.packageDays : null,
      startDate: panel.startDate,
      expiryDate: panel.expiryDate,
      clearExpiryDate: panel.expiryDate == null &&
          panel.startDate != null &&
          panel.packageDays > 0,
      lastResetTime: panel.lastResetTime,
      lastOnline: panel.lastOnline,
      mode: panel.mode.isNotEmpty ? panel.mode : null,
      lang: panel.lang.isNotEmpty ? panel.lang : null,
      wgIpv4: panel.wgIpv4.isNotEmpty ? panel.wgIpv4 : null,
      wgIpv6: panel.wgIpv6.isNotEmpty ? panel.wgIpv6 : null,
      awgIpv4: panel.awgIpv4.isNotEmpty ? panel.awgIpv4 : null,
      awgIpv6: panel.awgIpv6.isNotEmpty ? panel.awgIpv6 : null,
    );
    _session = session.copyWith(account: merged, filter: session.filter);
    await _store.writeJson(StoreKeys.session, _session!.toJson());
    // اگر پنل بگوید اشتراک تمام شده، اتصال باید فورا قطع شود.
    if (!merged.canConnect) {
      onAccessRevoked?.call(merged.accessReason);
    }
    notifyListeners();
    return true;
  }

  /// وقتی دسترسی حساب از بین می رود (انقضا، مسدود شدن یا اتمام حجم) صدا زده
  /// می شود تا اتصال فعال قطع شود. در main به VpnController وصل می شود.
  void Function(String reason)? onAccessRevoked;

  /// دریافت اشتراک اختصاصی کاربر از طریق درگاه ربات (مسیر کمکی بدون هیچ منبع
  /// عمومی، فقط برای خود حساب واردشده).
  Future<String?> fetchSubscriptionViaGateway() async {
    final SessionData? session = _session;
    if (session == null || session.token.isEmpty) {
      return null;
    }
    try {
      final ({String content, String subscriptionUrl, String accountBase})?
          fetched = await _gateway.fetchSubscription(session.token);
      if (fetched == null) {
        return null;
      }
      final SessionData? current = _session;
      if (current != null) {
        final String nextSub = fetched.subscriptionUrl.isNotEmpty
            ? fetched.subscriptionUrl
            : current.account.subscriptionUrl;
        final String nextBase = fetched.accountBase.isNotEmpty
            ? fetched.accountBase
            : current.account.accountBase;
        if (nextSub != current.account.subscriptionUrl ||
            nextBase != current.account.accountBase) {
          _session = current.copyWith(
            account: current.account.copyWith(
              subscriptionUrl: nextSub,
              accountBase: nextBase,
            ),
          );
          await _store.writeJson(StoreKeys.session, _session!.toJson());
        }
      }
      return fetched.content;
    } on ApiError catch (error) {
      if (error.code == 'device_revoked') {
        await _handleDeviceRevoked(error.message);
      } else if (error.needsLogin) {
        await signOut(callServer: false);
        _error = 'نشست منقضی شد؛ دوباره وارد شوید.';
        notifyListeners();
      }
      return null;
    }
  }

  Future<void> refreshAccount({bool silent = false}) async {
    final SessionData? session = _session;
    if (session == null) {
      return;
    }
    try {
      final SessionData fresh = await _gateway.refresh(session.token);
      final Account prev = session.account;
      final Account next = fresh.account;
      final Account preserved = next.copyWith(
        panelId: next.panelId > 0 ? next.panelId : prev.panelId,
        lastResetTime: next.lastResetTime ?? prev.lastResetTime,
        wgIpv4: next.wgIpv4.isNotEmpty ? next.wgIpv4 : prev.wgIpv4,
        wgIpv6: next.wgIpv6.isNotEmpty ? next.wgIpv6 : prev.wgIpv6,
        awgIpv4: next.awgIpv4.isNotEmpty ? next.awgIpv4 : prev.awgIpv4,
        awgIpv6: next.awgIpv6.isNotEmpty ? next.awgIpv6 : prev.awgIpv6,
      );
      final FilterSettings previousFilter = session.filter;
      _session = session.copyWith(
        account: preserved,
        filter: fresh.filter,
        offers: fresh.offers,
      );
      await _syncNotificationOwner(_session!.ownerKey);
      await _store.writeJson(StoreKeys.session, _session!.toJson());
      await _store.writeJson(StoreKeys.filter, fresh.filter.toJson());
      if (!previousFilter.sameEffectAs(fresh.filter)) {
        onFilterChanged?.call(fresh.filter);
      }
      notifyListeners();
    } on ApiError catch (error) {
      if (error.code == 'device_revoked') {
        await _handleDeviceRevoked(error.message);
      } else if (error.needsLogin) {
        await signOut(callServer: false);
        _error = 'نشست منقضی شد؛ دوباره وارد شوید.';
        notifyListeners();
      }
    }
  }

  /// اعمال خودکار تغییرات دریافتی از ربات تلگرام (کنترل محتوا و وضعیت منوی
  /// اشتراک رایگان / نوروزی) بدون نیاز به بستن یا ورود مجدد.
  Future<void> _applyLiveServerState({
    FilterSettings? filter,
    SubscriptionOffers? offers,
  }) async {
    final SessionData? current = _session;
    if (current == null) {
      return;
    }
    FilterSettings nextFilter = current.filter;
    bool filterChanged = false;
    bool filterEffectChanged = false;
    if (filter != null && !_savingFilter && !current.filter.sameAs(filter)) {
      filterEffectChanged = !current.filter.sameEffectAs(filter);
      nextFilter = filter;
      filterChanged = true;
    }

    SubscriptionOffers nextOffers = current.offers;
    bool offersChanged = false;
    if (offers != null && !_claimingOffer && !current.offers.sameAs(offers)) {
      nextOffers = offers;
      offersChanged = true;
    }

    if (!filterChanged && !offersChanged) {
      return;
    }
    _session = current.copyWith(filter: nextFilter, offers: nextOffers);
    await _store.writeJson(StoreKeys.session, _session!.toJson());
    if (filterChanged) {
      await _store.writeJson(StoreKeys.filter, nextFilter.toJson());
    }
    if (filterEffectChanged) {
      onFilterChanged?.call(nextFilter);
    }
    notifyListeners();
  }

  /// همگام سازی کاملاً خودکار پس زمینه (کنترل محتوا، هدیه ها، حساب، پنل و اعلان ها).
  DateTime? _lastAutoSyncAt;
  bool _autoSyncInFlight = false;

  Future<void> autoSync({bool includeAccount = true}) async {
    if (!signedIn || _autoSyncInFlight || _revokingSession) {
      return;
    }
    final DateTime now = DateTime.now();
    if (_lastAutoSyncAt != null &&
        now.difference(_lastAutoSyncAt!) < const Duration(seconds: 12)) {
      return;
    }
    _autoSyncInFlight = true;
    _lastAutoSyncAt = now;
    try {
      await _checkDeviceAccess();
      if (includeAccount && signedIn && !_revokingSession) {
        await refreshAccount(silent: true);
        await refreshFromPanel();
      }
    } catch (_) {
      // همگام سازی پس زمینه کاملاً بی صداست و خطای موقت شبکه کاربر را آزار نمی دهد.
    } finally {
      _autoSyncInFlight = false;
    }
  }

  /// همگام سازی خودکار و بی صدای کنترل محتوا با ربات تلگرام.
  Future<bool> syncFilter({bool silent = true}) async {
    final SessionData? session = _session;
    if (session == null || _syncingFilter || _savingFilter) {
      return false;
    }
    _syncingFilter = true;
    if (!silent) {
      notifyListeners();
    }
    try {
      final FilterSettings latest = await _gateway.getFilter(session.token);
      final SessionData? current = _session;
      if (current != null && !_savingFilter && !current.filter.sameAs(latest)) {
        final bool effectChanged = !current.filter.sameEffectAs(latest);
        _session = current.copyWith(filter: latest);
        await _store.writeJson(StoreKeys.session, _session!.toJson());
        await _store.writeJson(StoreKeys.filter, latest.toJson());
        if (effectChanged) {
          onFilterChanged?.call(latest);
        }
        notifyListeners();
      }
      return true;
    } on ApiError catch (error) {
      if (error.code == 'device_revoked') {
        await _handleDeviceRevoked(error.message);
      } else if (error.needsLogin) {
        await signOut(callServer: false);
      } else if (!silent) {
        _error = error.message;
        _logError(error.message);
      }
      return false;
    } finally {
      _syncingFilter = false;
      if (!silent) {
        notifyListeners();
      }
    }
  }

  Future<bool> saveFilter(FilterSettings settings) async {
    final SessionData? session = _session;
    if (session == null || _savingFilter) {
      return false;
    }
    _savingFilter = true;
    _error = '';
    notifyListeners();
    try {
      final FilterSettings previous = session.filter;
      final FilterSettings saved =
          await _gateway.saveFilter(session.token, settings);
      final SessionData nextSession = (_session ?? session).copyWith(
        filter: saved,
      );
      _session = nextSession;
      await _store.writeJson(StoreKeys.session, nextSession.toJson());
      await _store.writeJson(StoreKeys.filter, saved.toJson());
      if (!previous.sameEffectAs(saved)) {
        onFilterChanged?.call(saved);
      }
      return true;
    } on ApiError catch (error) {
      if (error.code == 'device_revoked') {
        await _handleDeviceRevoked(error.message);
      } else {
        _error = error.message;
        _logError(error.message);
      }
      return false;
    } finally {
      _savingFilter = false;
      notifyListeners();
    }
  }

  /// فعال سازی اشتراک رایگان (۱ گیگ / ۱ روز) یا نوروزی (۵ گیگ / ۱۳ روز) همگام با ربات.
  Future<String?> claimSubscriptionOffer(String type) async {
    final SessionData? session = _session;
    if (session == null || _claimingOffer) {
      return null;
    }
    _claimingOffer = true;
    _claimingPlanType = type;
    _error = '';
    notifyListeners();
    try {
      final ({
        String message,
        Account account,
        FilterSettings filter,
        SubscriptionOffers offers,
      }) res = await _gateway.claimSubscription(
        token: session.token,
        type: type,
      );
      final SessionData base = _session ?? session;
      final Account prev = base.account;
      final Account merged = res.account.copyWith(
        panelId: res.account.panelId > 0 ? res.account.panelId : prev.panelId,
        wgIpv4: res.account.wgIpv4.isNotEmpty ? res.account.wgIpv4 : prev.wgIpv4,
        wgIpv6: res.account.wgIpv6.isNotEmpty ? res.account.wgIpv6 : prev.wgIpv6,
        awgIpv4:
            res.account.awgIpv4.isNotEmpty ? res.account.awgIpv4 : prev.awgIpv4,
        awgIpv6:
            res.account.awgIpv6.isNotEmpty ? res.account.awgIpv6 : prev.awgIpv6,
      );
      _session = base.copyWith(
        account: merged,
        filter: res.filter,
        offers: res.offers,
      );
      await _store.writeJson(StoreKeys.session, _session!.toJson());
      await _store.writeJson(StoreKeys.filter, res.filter.toJson());
      notifyListeners();
      if (onSubscriptionClaimed != null) {
        unawaited(onSubscriptionClaimed!());
      }
      return res.message.isNotEmpty
          ? res.message
          : (type == 'nowruz'
              ? 'اشتراک نوروزی با موفقیت فعال شد.'
              : 'اشتراک رایگان با موفقیت فعال شد.');
    } on ApiError catch (error) {
      if (error.code == 'device_revoked') {
        await _handleDeviceRevoked(error.message);
      } else if (error.code == 'already_claimed' ||
          error.code == 'nowruz_disabled' ||
          error.code == 'active_subscription') {
        _error = error.message;
        unawaited(refreshAccount(silent: true));
      } else {
        _error = error.message;
        _logError(error.message);
      }
      return null;
    } finally {
      _claimingOffer = false;
      _claimingPlanType = '';
      notifyListeners();
    }
  }

  Future<void> _syncNotificationOwner(String ownerKey) async {
    if (ownerKey.isEmpty) {
      return;
    }
    final String previousOwner =
        (_store.read(StoreKeys.notificationsOwner) ?? '').trim();
    if (previousOwner.isNotEmpty && previousOwner != ownerKey) {
      _notifications = <AppNotification>[];
      _announced.clear();
      _historySynced = false;
      await _store.writeJsonList(StoreKeys.notifications, const <dynamic>[]);
    }
    if (previousOwner != ownerKey) {
      await _store.write(StoreKeys.notificationsOwner, ownerKey);
    }
  }

  /// ادغام اعلان های دریافتی از درگاه با تاریخچه ذخیره شده محلی.
  ///
  /// درگاه در حالت عادی فقط اعلان های تحویل نشده را برمی گرداند و بلافاصله
  /// `Delivered_At` را پر می کند؛ بنابراین جایگزینی مستقیم لیست باعث پاک شدن
  /// تمام اعلان های قبلی در درخواست بعدی می شد. این متد اعلان های قبلی را حفظ
  /// می کند، وضعیت خوانده شدن هر اعلان را نگه می دارد، و اعلان های تاریخی
  /// بازیابی شده (`delivered == true`) را بدون پخش مجدد صدا در فهرست قرار می دهد.
  static ({List<AppNotification> merged, List<AppNotification> fresh})
      mergeNotificationHistory({
    required List<AppNotification> existing,
    required List<AppNotification> incoming,
    required Set<String> announced,
    int maxItems = maxStoredNotifications,
  }) {
    final Map<String, AppNotification> byKey = <String, AppNotification>{};
    for (final AppNotification item in existing) {
      if (_isStaleDeviceRevocation(item)) {
        continue;
      }
      byKey[_keyOf(item)] = item.copyWith(clearDelivered: true);
    }

    final List<AppNotification> fresh = <AppNotification>[];
    final Set<String> freshKeys = <String>{};

    for (final AppNotification item in incoming) {
      if (_isStaleDeviceRevocation(item)) {
        continue;
      }
      final String key = _keyOf(item);
      final AppNotification? previous = byKey[key];
      if (previous != null) {
        byKey[key] = previous.copyWith(
          title: item.title.isNotEmpty ? item.title : previous.title,
          body: item.body.isNotEmpty ? item.body : previous.body,
          level: item.level.isNotEmpty ? item.level : previous.level,
          sentAt: item.sentAt ?? previous.sentAt,
          read: previous.read,
          clearDelivered: true,
        );
        announced.add(key);
        continue;
      }

      if (item.delivered == true) {
        // اعلان قدیمی بازیابی شده از تاریخچه سرور: نمایش در فهرست بدون هشدار مجدد.
        byKey[key] = item.copyWith(read: true, clearDelivered: true);
        announced.add(key);
      } else {
        final AppNotification normalized = item.copyWith(clearDelivered: true);
        byKey[key] = normalized;
        if (!normalized.read &&
            !announced.contains(key) &&
            freshKeys.add(key)) {
          fresh.add(normalized);
        }
      }
    }

    final List<AppNotification> merged = _sortAndTrim(
      byKey.values.toList(),
      maxItems: maxItems,
    );
    return (merged: merged, fresh: fresh);
  }

  static List<AppNotification> _sortAndTrim(
    List<AppNotification> items, {
    int maxItems = maxStoredNotifications,
  }) {
    items.sort((AppNotification a, AppNotification b) {
      final DateTime? ta = a.sentAt;
      final DateTime? tb = b.sentAt;
      if (ta != null && tb != null) {
        final int byTime = tb.compareTo(ta);
        if (byTime != 0) {
          return byTime;
        }
      } else if (tb != null) {
        return 1;
      } else if (ta != null) {
        return -1;
      }
      return b.id.abs().compareTo(a.id.abs());
    });
    if (items.length > maxItems) {
      return items.sublist(0, maxItems);
    }
    return items;
  }

  static bool _sameNotificationList(
    List<AppNotification> a,
    List<AppNotification> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      final AppNotification x = a[i];
      final AppNotification y = b[i];
      if (x.id != y.id ||
          x.read != y.read ||
          x.title != y.title ||
          x.body != y.body ||
          x.level != y.level ||
          x.sentAt != y.sentAt) {
        return false;
      }
    }
    return true;
  }

  Future<void> fetchNotifications({bool includeHistory = false}) async {
    if (_session == null) {
      return;
    }
    final Future<void>? inFlight = _notificationsFetch;
    if (inFlight != null) {
      await inFlight;
      if (!includeHistory || _session == null) {
        return;
      }
    }
    final Future<void> run =
        _performFetchNotifications(includeHistory: includeHistory);
    _notificationsFetch = run;
    try {
      await run;
    } finally {
      if (identical(_notificationsFetch, run)) {
        _notificationsFetch = null;
      }
    }
  }

  Future<void> _performFetchNotifications({
    required bool includeHistory,
  }) async {
    final SessionData? session = _session;
    if (session == null) {
      return;
    }
    if (includeHistory && !_loadingNotifications) {
      _loadingNotifications = true;
      notifyListeners();
    }
    try {
      final List<AppNotification> items = (await _gateway.notifications(
        session.token,
        includeHistory: includeHistory,
      ))
          // A revoke warning can be queued immediately before this same device
          // is re-approved. The gateway filters it too; keep older deployments
          // and delayed responses from showing that stale warning after approval.
          .where((AppNotification item) => !_isStaleDeviceRevocation(item))
          .toList();
      if (includeHistory) {
        _historySynced = true;
      }
      final ({List<AppNotification> merged, List<AppNotification> fresh})
          result = mergeNotificationHistory(
        existing: _notifications,
        incoming: items,
        announced: _announced,
      );
      final bool changed = !_sameNotificationList(_notifications, result.merged);
      if (changed) {
        _notifications = result.merged;
        await _persistNotifications();
      }
      if (_loadingNotifications) {
        _loadingNotifications = false;
      }
      if (changed || includeHistory) {
        notifyListeners();
      }
      // اعلان تازه باید هم صدا داشته باشد و هم در گوشه ویندوز دیده شود.
      if (result.fresh.isNotEmpty) {
        await _announce(result.fresh);
      }
    } on ApiError catch (error) {
      if (_loadingNotifications) {
        _loadingNotifications = false;
        notifyListeners();
      }
      if (error.code == 'device_revoked') {
        await _handleDeviceRevoked(error.message);
      } else if (error.needsLogin) {
        await signOut(callServer: false);
        _error = 'نشست منقضی شد؛ دوباره وارد شوید.';
        notifyListeners();
      }
    } catch (_) {
      if (_loadingNotifications) {
        _loadingNotifications = false;
        notifyListeners();
      }
    }
  }

  Future<void> _persistNotifications() {
    return _store.writeJsonList(
      StoreKeys.notifications,
      _notifications.map((AppNotification item) => item.toJson()).toList(),
    );
  }

  static bool _isStaleDeviceRevocation(AppNotification item) {
    final String notice = '${item.title}\n${item.body}';
    return notice.contains('مجوز این دستگاه لغو شد') ||
        notice.contains('دسترسی این دستگاه به نرم افزار آمبرلا لغو شد');
  }

  static String _keyOf(AppNotification item) => item.identityKey;

  /// ثبت اعلان مهم محلی (مثل اتمام اشتراک) در مرکز اعلان ها تا بعداً هم قابل
  /// مشاهده باشد.
  void recordLocalNotification({
    required String title,
    String body = '',
    String level = 'info',
  }) {
    final String cleanTitle = title.trim();
    final String cleanBody = body.trim();
    if (cleanTitle.isEmpty) {
      return;
    }
    final DateTime now = DateTime.now();
    // جلوگیری از ثبت تکراری یک اعلان محلی یکسان در بازه کوتاه.
    final bool duplicate = _notifications.any(
      (AppNotification item) =>
          item.id < 0 &&
          item.title == cleanTitle &&
          item.body == cleanBody &&
          item.sentAt != null &&
          now.difference(item.sentAt!).inMinutes.abs() < 10,
    );
    if (duplicate) {
      return;
    }
    final AppNotification entry = AppNotification(
      id: -now.microsecondsSinceEpoch,
      title: cleanTitle,
      body: cleanBody,
      level: level,
      sentAt: now,
    );
    _announced.add(_keyOf(entry));
    _notifications = _sortAndTrim(<AppNotification>[entry, ..._notifications]);
    unawaited(_persistNotifications());
    notifyListeners();
  }

  /// اعلام اعلان تازه: صدا و بالون سینی سیستم.
  ///
  /// چند اعلان همزمان فقط یک صدا می دهد تا گوش کاربر اذیت نشود؛ متن بالون
  /// آخرین اعلان است.
  Future<void> _announce(List<AppNotification> fresh) async {
    for (final AppNotification item in fresh) {
      _announced.add(_keyOf(item));
      final String shortTitle = item.compactTitle;
      final String shortBody = item.balloonBody;
      _log.add('اعلان: $shortTitle${shortBody.isEmpty ? '' : ' | $shortBody'}');
    }
    final AppNotification last = fresh.last;
    if (soundEnabled) {
      await _sound?.play('notify');
    }
    if (notificationsEnabled) {
      await _tray?.balloon(
        last.compactTitle,
        last.balloonBody,
        warning: fresh.any((AppNotification item) => item.level == 'warning'),
      );
    }
  }

  void markNotificationRead(AppNotification target) {
    final String key = _keyOf(target);
    bool changed = false;
    _notifications = _notifications.map((AppNotification item) {
      if (!item.read && _keyOf(item) == key) {
        changed = true;
        return item.copyWith(read: true);
      }
      return item;
    }).toList();
    if (!changed) {
      return;
    }
    unawaited(_persistNotifications());
    notifyListeners();
  }

  void markNotificationsRead() {
    if (_notifications.every((AppNotification item) => item.read)) {
      return;
    }
    _notifications = _notifications
        .map((AppNotification item) => item.copyWith(read: true))
        .toList();
    unawaited(_persistNotifications());
    notifyListeners();
  }

  Future<void> signOut({bool callServer = true}) async {
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    _heartbeatTimer?.cancel();
    final SessionData? session = _session;
    _session = null;
    onFilterChanged?.call(FilterSettings.empty);
    _phase = AuthPhase.phone;
    _stage = SignInStage.unknown;
    _challenge = '';
    _error = '';
    _info = '';
    await _store.remove(StoreKeys.session);
    notifyListeners();
    if (callServer && session != null) {
      try {
        await _gateway.signOut(token: session.token, challenge: _challenge);
      } on ApiError {
        // قطع نشست در سرور اختیاری است؛ خروج محلی در هر حال انجام می شود.
      }
    }
    _log.add('از حساب خارج شدید.');
  }

  void resetToPhoneStep() {
    _phase = AuthPhase.phone;
    _error = '';
    _info = '';
    _stage = SignInStage.unknown;
    _challenge = '';
    _pollTimer?.cancel();
    notifyListeners();
  }

  void backToCodeStep() {
    _phase = AuthPhase.code;
    notifyListeners();
  }

  void clearError() {
    if (_error.isEmpty) {
      return;
    }
    _error = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    _heartbeatTimer?.cancel();
    _gateway.close();
    super.dispose();
  }
}
