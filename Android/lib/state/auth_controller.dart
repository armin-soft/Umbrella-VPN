import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/persian.dart';
import '../core/storage.dart';
import '../core/utils.dart';
import '../data/gateway_client.dart';
import '../models/models.dart';
import '../platform/native.dart';
import '../platform/services.dart';
import '../vpn/clash_api.dart';

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

  /// گزارش لحظه ای وضعیت سپر امنیتی دستگاه برای ارسال در heartbeat.
  Map<String, dynamic> Function()? securityStateProvider;

  Future<void> _syncNativeBackgroundSecurityAuth() async {
    final SessionData? s = _session;
    await NativeBridge.syncBackgroundSecurityAuth(
      _native,
      gatewayBase: _gateway.baseUrl,
      token: s?.token ?? '',
      deviceId: _deviceId,
      appVersion: AppConfig.version,
    );
  }

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

  GatewayClient get gateway => _gateway;

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

  List<SubscriptionPlan> _subscriptionPlans = <SubscriptionPlan>[];
  List<SubscriptionPlan> get subscriptionPlans =>
      List<SubscriptionPlan>.unmodifiable(_subscriptionPlans);
  int _walletBalance = 0;
  int get walletBalance => _walletBalance;
  CustomSubscriptionTerms? _customSubscriptionTerms;
  CustomSubscriptionTerms? get customSubscriptionTerms => _customSubscriptionTerms;
  bool? _botLinked;
  bool? get botLinked => _botLinked;
  bool _linkingBot = false;
  bool get linkingBot => _linkingBot;

  Future<void> refreshBotLinkStatus() async {
    final session = _session;
    if (session == null) return;
    try {
      final linked = await _gateway.botMembershipStatus(session.token);
      if (_session?.token != session.token) return;
      _botLinked = linked;
      notifyListeners();
    } on ApiError catch (error) {
      if (error.code == 'device_revoked') await _handleDeviceRevoked(error.message);
    }
  }

  Future<String?> createBotMembershipLink() async {
    final session = _session;
    if (session == null || _linkingBot) return null;
    _linkingBot = true;
    _error = '';
    notifyListeners();
    try {
      final result = await _gateway.createBotMembershipLink(session.token);
      if (_session?.token != session.token) return null;
      if (JsonX.boolean(result['linked'])) {
        _botLinked = true;
        await refreshAccount(silent: true);
        return '';
      }
      return JsonX.text(result['url']);
    } on ApiError catch (error) {
      if (error.code == 'device_revoked') {
        await _handleDeviceRevoked(error.message);
      } else {
        _error = error.message;
      }
      return null;
    } finally {
      _linkingBot = false;
      notifyListeners();
    }
  }

  bool _walletLoaded = false;
  bool get walletLoaded => _walletLoaded;
  bool _walletBusy = false;
  bool get walletBusy => _walletBusy;
  double _walletExactBalance = 0;
  double get walletExactBalance => _walletExactBalance;
  int _walletMinTopup = 0;
  int get walletMinTopup => _walletMinTopup;
  int _walletMaxTopup = 0;
  int get walletMaxTopup => _walletMaxTopup;
  bool _walletPaymentPending = false;
  bool get walletPaymentPending => _walletPaymentPending;
  bool _walletTopupPending = false;
  bool get walletTopupPending => _walletTopupPending;
  double _walletPendingCredit = 0;
  double get walletPendingCredit => _walletPendingCredit;
  double _walletPendingAmount = 0;
  double get walletPendingAmount => _walletPendingAmount;
  String _walletPendingId = '';
  String get walletPendingId => _walletPendingId;
  String _walletCheckoutUrl = '';
  String get walletCheckoutUrl => _walletCheckoutUrl;

  void _applyWallet(Map<String, dynamic> value) {
    _walletLoaded = true;
    _walletExactBalance = JsonX.number(value['balance']);
    _walletBalance = _walletExactBalance.round();
    _walletMinTopup = JsonX.integer(value['min_topup']);
    _walletMaxTopup = JsonX.integer(value['max_topup']);
    _walletPaymentPending = JsonX.boolean(value['payment_pending']);
    _walletPendingId = JsonX.text(value['pending_id']);
    _walletTopupPending = JsonX.boolean(value['pending_wallet_topup']);
    _walletPendingCredit = JsonX.number(value['pending_credit']);
    _walletPendingAmount = JsonX.number(value['pending_amount']);
    _walletCheckoutUrl = JsonX.text(value['checkout_url']);
  }

  Future<bool> refreshWallet({bool verify = false, bool silent = false}) async {
    final session = _session;
    if (session == null || _walletBusy) return false;
    _walletBusy = true;
    if (!silent) _error = '';
    notifyListeners();
    try {
      final value = verify
          ? await _gateway.verifyWalletTopup(session.token)
          : await _gateway.walletStatus(session.token);
      if (_session?.token != session.token) return false;
      _applyWallet(value);
      return true;
    } on ApiError catch (error) {
      if (_session?.token != session.token) return false;
      if (error.code == 'account_not_linked') _walletLoaded = false;
      if (error.code == 'device_revoked') {
        await _handleDeviceRevoked(error.message);
      } else if (error.needsLogin) {
        await signOut(callServer: false);
        _error = 'نشست منقضی شد؛ دوباره وارد شوید.';
      } else if (!silent) {
        _error = error.message;
      }
      return false;
    } finally {
      _walletBusy = false;
      notifyListeners();
    }
  }

  Future<bool> cancelWalletPayment({String? expectedPendingId}) async {
    final session = _session;
    if (session == null || _walletBusy) return false;
    if (_walletPendingId.isEmpty) {
      _error = 'شناسه امن سفارش دریافت نشد؛ وضعیت کیف پول را تازه کنید. اگر مشکل ادامه داشت، سرویس پرداخت سرور نیاز به به روزرسانی دارد.';
      notifyListeners();
      return false;
    }
    if (expectedPendingId != null && expectedPendingId != _walletPendingId) {
      _error = 'سفارش تغییر کرده است؛ وضعیت جدید را بررسی و دوباره تأیید کنید.';
      notifyListeners();
      return false;
    }
    final String pendingId = _walletPendingId;
    _walletBusy = true;
    _error = '';
    notifyListeners();
    try {
      final result = await _gateway.cancelWalletPayment(session.token, pendingId);
      if (_session?.token != session.token) return false;
      if (result['payment_pending'] is! bool) {
        _error = 'پاسخ لغو از سرور قابل تأیید نیست؛ کیف پول را تازه کنید و در صورت نیاز با پشتیبانی تماس بگیرید.';
        return false;
      }
      _applyWallet(result);
      if (_walletPaymentPending) {
        _error = 'سفارش هنوز در انتظار است یا سفارش دیگری جایگزین شده؛ وضعیت کیف پول را بررسی کنید.';
        return false;
      }
      return true;
    } on ApiError catch (error) {
      if (_session?.token != session.token) return false;
      if (error.code == 'device_revoked') {
        await _handleDeviceRevoked(error.message);
      } else if (error.needsLogin) {
        await signOut(callServer: false);
        _error = 'نشست منقضی شد؛ دوباره وارد شوید.';
      } else if (error.status == 404 || error.code == 'route_not_found') {
        _error = 'سرویس لغو سفارش روی سرور در دسترس نیست؛ به روزرسانی سرور پرداخت لازم است.';
      } else {
        _error = error.message;
      }
      return false;
    } finally {
      _walletBusy = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> startWalletTopup(int amount) async {
    final session = _session;
    if (session == null || _walletBusy) return null;
    _walletBusy = true;
    _error = '';
    notifyListeners();
    try {
      final result = await _gateway.startWalletTopup(token: session.token, amount: amount);
      if (_session?.token != session.token) return null;
      // Pending state is retained even if opening the external browser fails.
      _walletPaymentPending = true;
      _walletPendingId = JsonX.text(result['pending_id']);
      _walletTopupPending = true;
      _walletPendingCredit = JsonX.number(result['credit']);
      _walletPendingAmount = JsonX.number(result['gateway_amount']);
      _walletCheckoutUrl = JsonX.text(result['checkout_url']);
      return result;
    } on ApiError catch (error) {
      if (_session?.token != session.token) return null;
      if (error.code == 'device_revoked') {
        await _handleDeviceRevoked(error.message);
      } else if (error.needsLogin) {
        await signOut(callServer: false);
        _error = 'نشست منقضی شد؛ دوباره وارد شوید.';
      } else {
        _error = error.message;
      }
      return null;
    } finally {
      _walletBusy = false;
      notifyListeners();
    }
  }

  bool _loadingSubscriptionPlans = false;
  bool get loadingSubscriptionPlans => _loadingSubscriptionPlans;
  bool _purchasingSubscription = false;
  bool get purchasingSubscription => _purchasingSubscription;


  /// وقتی کنترل محتوا تغییر کند (از برنامه یا مستقیم از ربات تلگرام) صدا زده
  /// می شود تا هسته اتصال قوانین جدید را بلافاصله اعمال کند.
  void Function(FilterSettings filter)? onFilterChanged;

  /// پس از فعال سازی موفق اشتراک رایگان یا نوروزی صدا زده می شود تا سرورهای
  /// شخصی کاربر بی درنگ دریافت شوند.
  Future<void> Function()? onSubscriptionClaimed;

  /// وقتی تنظیمات اعلان داخل برنامه از سرور دریافت یا به روزرسانی شد صدا زده می شود.
  void Function(AppAnnouncement announcement)? onAnnouncementUpdated;

  /// وقتی اعلان تبلیغاتی از سرور دریافت یا به روزرسانی شد صدا زده می شود.
  void Function(PromoAnnouncement promo)? onPromoAnnouncementUpdated;

  AppAnnouncement _announcement = AppAnnouncement.fallback();
  AppAnnouncement get announcement => _announcement;

  PromoAnnouncement _promoAnnouncement = PromoAnnouncement.empty;
  PromoAnnouncement get promoAnnouncement => _promoAnnouncement;

  Uint8List? _promoImageBytes;
  Uint8List? get promoImageBytes => _promoImageBytes;
  String _promoImageUrlLoaded = '';
  Future<Uint8List?>? _promoImageFetch;

  bool _cancellingSignIn = false;
  Timer? _pollTimer;
  Timer? _clockTimer;
  Timer? _heartbeatTimer;
  bool _restored = false;
  bool _checkingDeviceAccess = false;
  bool _revokingSession = false;
  bool _batterySaving = false;
  bool _appVisible = true;
  DateTime? _lastHeartbeatAt;

  Duration get _effectiveHeartbeatInterval {
    if (_session?.account.channelStatus == 'grace') {
      return const Duration(seconds: 30);
    }
    if (!_appVisible && _batterySaving) {
      return const Duration(seconds: 150);
    }
    if (_batterySaving || !_appVisible) {
      return const Duration(seconds: 90);
    }
    return const Duration(seconds: 30);
  }

  void setBatterySaving(bool value) {
    if (_batterySaving == value) return;
    _batterySaving = value;
    if (_heartbeatTimer != null && _session != null) {
      _rescheduleHeartbeat();
    }
  }

  void setAppVisible(bool visible) {
    if (_appVisible == visible) return;
    _appVisible = visible;
    if (_heartbeatTimer != null && _session != null) {
      _rescheduleHeartbeat();
      if (visible) {
        final DateTime? last = _lastHeartbeatAt;
        if (last == null ||
            DateTime.now().difference(last) >= const Duration(seconds: 25)) {
          unawaited(_checkDeviceAccess());
        }
      }
    }
  }

  Future<void> restore() async {
    if (_restored) {
      return;
    }
    _restored = true;
    _device = await _native.deviceInfo();
    // Keep the phone field filled after an update or an expired server session.
    // The sign-in token is restored separately below; never save an OTP.
    _phone = _store.read(StoreKeys.lastPhone) ?? '';
    _deviceId = (_store.read(StoreKeys.deviceId) ?? '').trim();
    if (_deviceId.isEmpty) {
      try {
        final String backedUp = (_store.readFileSync('device_id.txt') ?? '').trim();
        if (RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(backedUp)) {
          _deviceId = backedUp;
          await _store.write(StoreKeys.deviceId, _deviceId);
        }
      } catch (_) {}
    }
    if (_deviceId.isEmpty) {
      _deviceId = _generateDeviceId();
      await _store.write(StoreKeys.deviceId, _deviceId);
    }
    try {
      final String? existingBackup = _store.readFileSync('device_id.txt');
      if (existingBackup == null || existingBackup.trim() != _deviceId) {
        _store.writeFileSync('device_id.txt', _deviceId);
      }
    } catch (_) {}
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
    final Map<String, dynamic> annState =
        _store.readJson(StoreKeys.appAnnouncementState);
    final Map<String, dynamic> cachedAnn = JsonX.asMap(annState['cached']);
    if (cachedAnn.isNotEmpty) {
      _announcement = AppAnnouncement.fromJson(cachedAnn);
    }
    final Map<String, dynamic> promoState =
        _store.readJson(StoreKeys.promoAnnouncementState);
    final Map<String, dynamic> cachedPromo = JsonX.asMap(promoState['cached']);
    if (cachedPromo.isNotEmpty) {
      _promoAnnouncement = PromoAnnouncement.fromJson(cachedPromo);
    }
    final Map<String, dynamic> json = _store.readJson(StoreKeys.session);
    if (json.isNotEmpty) {
      _session = SessionData.fromJson(json);
      if (_session!.token.isEmpty) {
        _session = null;
      } else {
        if (_session!.announcement != null) {
          await _applyAnnouncement(_session!.announcement, notify: false);
        }
        if (_session!.promoAnnouncement != null) {
          await _applyPromoAnnouncement(
            _session!.promoAnnouncement,
            notify: false,
            triggerSystemBar: false,
          );
        }
        _phase = AuthPhase.done;
        _phone = _session!.account.phone;
        await _syncNotificationOwner(_session!.ownerKey);
        onFilterChanged?.call(filter);
        _startHeartbeat();
        unawaited(_syncNativeBackgroundSecurityAuth());
        unawaited(refreshAccount(silent: true).then<void>((_) {}));
      }
    }
    unawaited(syncAnnouncement());
    notifyListeners();
  }

  Future<void> _applyAnnouncement(
    AppAnnouncement? incoming, {
    bool notify = true,
  }) async {
    if (incoming == null) return;
    final bool changed = !_announcement.sameContentAs(incoming);
    _announcement = incoming;
    final Map<String, dynamic> state = Map<String, dynamic>.from(
      _store.readJson(StoreKeys.appAnnouncementState),
    );
    state['cached'] = incoming.toJson();
    await _store.writeJson(StoreKeys.appAnnouncementState, state);
    if (changed) {
      onAnnouncementUpdated?.call(incoming);
      if (notify) {
        notifyListeners();
      }
    }
  }

  Future<void> syncAnnouncement() async {
    try {
      final ({
        AppAnnouncement? announcement,
        PromoAnnouncement? promoAnnouncement,
      }) latest = await _gateway.fetchAnnouncements();
      if (latest.announcement != null) {
        await _applyAnnouncement(latest.announcement);
      }
      if (latest.promoAnnouncement != null) {
        await _applyPromoAnnouncement(latest.promoAnnouncement);
      }
    } catch (_) {
      // دریافت اعلان در پس زمینه بی صدا است.
    }
  }

  Future<void> _applyPromoAnnouncement(
    PromoAnnouncement? incoming, {
    bool notify = true,
    bool triggerSystemBar = true,
  }) async {
    if (incoming == null) return;
    final bool changed = !_promoAnnouncement.sameContentAs(incoming);
    if (incoming.imageUrl.trim() != _promoImageUrlLoaded) {
      _promoImageBytes = null;
      _promoImageUrlLoaded = '';
      _promoImageFetch = null;
    }
    _promoAnnouncement = incoming;
    final Map<String, dynamic> state = Map<String, dynamic>.from(
      _store.readJson(StoreKeys.promoAnnouncementState),
    );
    state['cached'] = incoming.toJson();
    await _store.writeJson(StoreKeys.promoAnnouncementState, state);
    if (incoming.isActive && incoming.hasImage) {
      unawaited(loadPromoImageBytes());
    }
    if (changed) {
      onPromoAnnouncementUpdated?.call(incoming);
      if (notify) {
        notifyListeners();
      }
    }
    if (triggerSystemBar && incoming.isActive) {
      unawaited(_notifyPromoSystemBarIfDue());
    }
  }

  Future<Uint8List?> loadPromoImageBytes({bool force = false}) async {
    final String url = _promoAnnouncement.imageUrl.trim();
    if (url.isEmpty) {
      _promoImageBytes = null;
      _promoImageUrlLoaded = '';
      return null;
    }
    if (!force && _promoImageBytes != null && _promoImageUrlLoaded == url) {
      return _promoImageBytes;
    }
    if (_promoImageFetch != null && !force && _promoImageUrlLoaded == url) {
      return _promoImageFetch!;
    }
    _promoImageUrlLoaded = url;
    final Future<Uint8List?> task = _gateway.fetchPromoImage(url);
    _promoImageFetch = task;
    try {
      final Uint8List? bytes = await task;
      if (_promoAnnouncement.imageUrl.trim() == url && bytes != null) {
        _promoImageBytes = bytes;
        notifyListeners();
      }
      return bytes;
    } finally {
      if (identical(_promoImageFetch, task)) {
        _promoImageFetch = null;
      }
    }
  }

  /// بررسی نمایش نوار بار تبلیغاتی داخل صفحه (با رعایت زمان بندی تکرار و نسخه).
  bool shouldShowPromoBanner({DateTime? now}) {
    final PromoAnnouncement promo = _promoAnnouncement;
    if (!promo.isActive) {
      return false;
    }
    final DateTime current = (now ?? DateTime.now()).toUtc();
    if (promo.isScheduledInFutureAt(current)) {
      return false;
    }
    final Map<String, dynamic> state =
        _store.readJson(StoreKeys.promoAnnouncementState);
    final int dismissedVersion = JsonX.integer(state['banner_dismissed_version']);
    final int dismissedAtMs = JsonX.integer(state['banner_dismissed_at_ms']);
    if (dismissedAtMs <= 0 || dismissedVersion != promo.version) {
      return true;
    }
    if (dismissedAtMs > current.millisecondsSinceEpoch) {
      return true;
    }
    if (promo.intervalHours <= 0) {
      return false;
    }
    final int requiredMs = promo.intervalHours * 3600 * 1000;
    return (current.millisecondsSinceEpoch - dismissedAtMs) >= requiredMs;
  }

  Future<void> dismissPromoBanner({DateTime? now}) async {
    final Map<String, dynamic> state = Map<String, dynamic>.from(
      _store.readJson(StoreKeys.promoAnnouncementState),
    );
    state['banner_dismissed_version'] = _promoAnnouncement.version;
    state['banner_dismissed_at_ms'] =
        (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    await _store.writeJson(StoreKeys.promoAnnouncementState, state);
    notifyListeners();
  }

  Future<bool> shouldNotifyPromoSystemBar({DateTime? now}) async {
    final PromoAnnouncement promo = _promoAnnouncement;
    if (!promo.isActive) {
      return false;
    }
    final DateTime current = (now ?? DateTime.now()).toUtc();
    if (promo.isScheduledInFutureAt(current)) {
      return false;
    }
    final Map<String, dynamic> state =
        _store.readJson(StoreKeys.promoAnnouncementState);
    final int notifiedVersion = JsonX.integer(state['bar_notified_version']);
    final int notifiedAtMs = JsonX.integer(state['bar_notified_at_ms']);
    if (notifiedAtMs <= 0 || notifiedVersion != promo.version) {
      return true;
    }
    if (notifiedAtMs > current.millisecondsSinceEpoch) {
      return false;
    }
    if (promo.intervalHours <= 0) {
      return false;
    }
    final int requiredMs = promo.intervalHours * 3600 * 1000;
    return (current.millisecondsSinceEpoch - notifiedAtMs) >= requiredMs;
  }

  Future<void> _notifyPromoSystemBarIfDue({DateTime? now}) async {
    try {
      final TrayService? tray = _tray;
      if (!notificationsEnabled || tray == null) {
        return;
      }
      if (!await shouldNotifyPromoSystemBar(now: now)) {
        return;
      }
      final PromoAnnouncement promo = _promoAnnouncement;
      final Map<String, dynamic> state = Map<String, dynamic>.from(
        _store.readJson(StoreKeys.promoAnnouncementState),
      );
      state['bar_notified_version'] = promo.version;
      state['bar_notified_at_ms'] =
          (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
      await _store.writeJson(StoreKeys.promoAnnouncementState, state);

      Uint8List? imageBytes;
      if (promo.hasImage) {
        try {
          imageBytes = await loadPromoImageBytes()
              .timeout(const Duration(seconds: 4));
        } catch (_) {
          imageBytes = null;
        }
      }
      await tray.promoBalloon(
        title: promo.title,
        body: promo.body,
        actionUrl: promo.buttonUrl,
        imageBytes: imageBytes,
      );
    } catch (_) {
      // خطای نوار اعلان سیستم نباید همگام سازی را متوقف کند.
    }
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
    final String cleaned = Fa.toEn(base.trim());
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
        final String challenge = _challenge;
        final SignInStatus status = await _gateway.status(challenge);
        if (_challenge != challenge || _cancellingSignIn) return;
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
      if (session.announcement != null) {
        await _applyAnnouncement(session.announcement, notify: false);
      }
      if (session.promoAnnouncement != null) {
        await _applyPromoAnnouncement(
          session.promoAnnouncement,
          notify: false,
        );
      }
      await _store.writeJson(StoreKeys.session, session.toJson());
      await _store.writeJson(StoreKeys.filter, session.filter.toJson());
      onFilterChanged?.call(session.filter);
      _startHeartbeat();
      unawaited(_syncNativeBackgroundSecurityAuth());
      _log.add('ورود موفق؛ خوش آمدید ${session.account.displayName}.');
      notifyListeners();
      // نشست فقط خلاصه حساب را دارد؛ پروفایل کامل و نشانی اشتراک از همین
      // مسیر از سرور گرفته می شود.
      unawaited(refreshAccount(silent: true).then<void>((_) {}));
    } on ApiError catch (error) {
      _error = error.message;
      _logError(error.message);
      notifyListeners();
    }
  }

  Future<void> cancelPendingSignIn() async {
    if (_challenge.isEmpty || _busy || _cancellingSignIn) return;
    final String challenge = _challenge;
    _cancellingSignIn = true;
    _busy = true;
    _error = '';
    notifyListeners();
    try {
      await _gateway.cancelSignIn(challenge);
      if (_challenge == challenge) resetToPhoneStep();
    } on ApiError catch (error) {
      _error = error.message;
      _logError(error.message);
    } finally {
      _cancellingSignIn = false;
      _busy = false;
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
      final String challenge = _challenge;
      final SignInStatus status = await _gateway.status(challenge);
      if (_challenge != challenge || _cancellingSignIn) return;
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

  void _rescheduleHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_effectiveHeartbeatInterval, (_) {
      unawaited(_checkDeviceAccess());
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    unawaited(_checkDeviceAccess());
    _rescheduleHeartbeat();
  }

  /// وضعیت مجوز دستگاه از درگاه بررسی می شود. خطای شبکه نشست را باطل نمی کند؛
  /// اما لغو دسترسی از تلگرام، اعلان را نشان می دهد و سپس کاربر را خارج می کند.
  Future<void> _checkDeviceAccess() async {
    if (_checkingDeviceAccess || _revokingSession) return;
    final SessionData? session = _session;
    if (session == null) return;

    _checkingDeviceAccess = true;
    _lastHeartbeatAt = DateTime.now();
    try {
      final List<Map<String, dynamic>> pendingActivity =
          ActivityMonitorBuffer.instance.snapshotPayload();
      final Map<String, dynamic>? secState = securityStateProvider?.call();
      final ({
        Account? account,
        FilterSettings? filter,
        SubscriptionOffers? offers,
        bool? emergencyEnabled,
        bool? botLinked,
        AppAnnouncement? announcement,
        PromoAnnouncement? promoAnnouncement,
      }) beat = await _gateway.heartbeat(
        token: session.token,
        deviceId: _deviceId,
        activity: pendingActivity,
        deviceName: _device.deviceName,
        platform: _device.platformLabel.isNotEmpty
            ? _device.platformLabel
            : (defaultTargetPlatform == TargetPlatform.android
                ? 'Android'
                : 'Windows'),
        appVersion: AppConfig.version,
        securityStatus: secState?['security_status'] as String?,
        scannedAtMs: secState?['scanned_at_ms'] as int?,
        scannedFiles: secState?['scanned_files'] as int?,
        scannedApps: secState?['scanned_apps'] as int?,
        scannedProcesses: secState?['scanned_processes'] as int?,
      );
      if (pendingActivity.isNotEmpty) {
        ActivityMonitorBuffer.instance.confirmSent(pendingActivity);
      }
      if (beat.announcement != null) {
        await _applyAnnouncement(beat.announcement);
      }
      if (beat.promoAnnouncement != null) {
        await _applyPromoAnnouncement(beat.promoAnnouncement);
      }
      await _applyLiveServerState(
        account: beat.account,
        filter: beat.filter,
        offers: beat.offers,
        emergencyEnabled: beat.emergencyEnabled,
        botLinked: beat.botLinked,
      );
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

  static Account _mergeAccount(
    Account prev,
    Account next, {
    bool? emergencyEnabledOverride,
  }) {
    return next.copyWith(
      panelId: next.panelId > 0 ? next.panelId : prev.panelId,
      lastResetTime: next.lastResetTime ?? prev.lastResetTime,
      wgIpv4: next.wgIpv4.isNotEmpty ? next.wgIpv4 : prev.wgIpv4,
      wgIpv6: next.wgIpv6.isNotEmpty ? next.wgIpv6 : prev.wgIpv6,
      awgIpv4: next.awgIpv4.isNotEmpty ? next.awgIpv4 : prev.awgIpv4,
      awgIpv6: next.awgIpv6.isNotEmpty ? next.awgIpv6 : prev.awgIpv6,
      subscriptionUrl: next.subscriptionUrl.isNotEmpty
          ? next.subscriptionUrl
          : prev.subscriptionUrl,
      accountBase: next.accountBase.isNotEmpty
          ? next.accountBase
          : prev.accountBase,
      emergencyEnabled: emergencyEnabledOverride ?? next.emergencyEnabled,
    );
  }

  static bool _sameAccount(Account a, Account b) {
    return a.panelId == b.panelId &&
        a.uuid == b.uuid &&
        a.name == b.name &&
        a.phone == b.phone &&
        a.telegramId == b.telegramId &&
        a.comment == b.comment &&
        a.enable == b.enable &&
        a.isActive == b.isActive &&
        a.usageLimitGb == b.usageLimitGb &&
        a.currentUsageGb == b.currentUsageGb &&
        a.packageDays == b.packageDays &&
        a.startDate == b.startDate &&
        a.expiryDate == b.expiryDate &&
        a.lastResetTime == b.lastResetTime &&
        a.lastOnline == b.lastOnline &&
        a.mode == b.mode &&
        a.lang == b.lang &&
        a.wgIpv4 == b.wgIpv4 &&
        a.wgIpv6 == b.wgIpv6 &&
        a.awgIpv4 == b.awgIpv4 &&
        a.awgIpv6 == b.awgIpv6 &&
        a.subscriptionUrl == b.subscriptionUrl &&
        a.accountBase == b.accountBase &&
        a.emergencyEnabled == b.emergencyEnabled &&
        a.channelStatus == b.channelStatus &&
        a.channelGraceRemainingSeconds == b.channelGraceRemainingSeconds &&
        a.channelDisabled == b.channelDisabled;
  }

  static bool _subscriptionNeedsResync(Account prev, Account next) {
    if (!prev.canConnect && next.canConnect) {
      return true;
    }
    if (next.subscriptionUrl.isNotEmpty &&
        next.subscriptionUrl != prev.subscriptionUrl) {
      return true;
    }
    return next.packageDays != prev.packageDays ||
        next.usageLimitGb != prev.usageLimitGb ||
        next.effectiveExpiryDate != prev.effectiveExpiryDate;
  }

  /// دریافت اعداد زندهٔ حساب فقط از درگاه احراز هویت شده سرور؛ هیچ درخواست
  /// مستقیمی از برنامه به پنل مدیریتی ارسال نمی شود.
  Future<bool> refreshAccount({bool silent = false}) async {
    final SessionData? session = _session;
    if (session == null) {
      return false;
    }
    try {
      final SessionData fresh = await _gateway.refresh(session.token);
      if (_session?.token != session.token) {
        return false;
      }
      final Account prev = session.account;
      final Account preserved = _mergeAccount(prev, fresh.account);
      final FilterSettings previousFilter = session.filter;
      final bool needsSubResync =
          preserved.canConnect && _subscriptionNeedsResync(prev, preserved);
      _session = session.copyWith(
        account: preserved,
        filter: fresh.filter,
        offers: fresh.offers,
        announcement: fresh.announcement,
        promoAnnouncement: fresh.promoAnnouncement,
      );
      if (fresh.announcement != null) {
        await _applyAnnouncement(fresh.announcement, notify: false);
      }
      if (fresh.promoAnnouncement != null) {
        await _applyPromoAnnouncement(
          fresh.promoAnnouncement,
          notify: false,
        );
      }
      await _syncNotificationOwner(_session!.ownerKey);
      await _store.writeJson(StoreKeys.session, _session!.toJson());
      await _store.writeJson(StoreKeys.filter, fresh.filter.toJson());
      if (!previousFilter.sameEffectAs(fresh.filter)) {
        onFilterChanged?.call(fresh.filter);
      }
      if ((prev.canConnect || !silent) && !preserved.canConnect) {
        onAccessRevoked?.call(preserved.accessReason);
      }
      if (needsSubResync && onSubscriptionClaimed != null) {
        unawaited(onSubscriptionClaimed!());
      }
      notifyListeners();
      return true;
    } on ApiError catch (error) {
      if (error.code == 'device_revoked') {
        await _handleDeviceRevoked(error.message);
      } else if (error.needsLogin) {
        await signOut(callServer: false);
        _error = 'نشست منقضی شد؛ دوباره وارد شوید.';
        notifyListeners();
      }
      return false;
    }
  }

  /// اعمال خودکار تغییرات دریافتی از ربات تلگرام و پنل سرور (وضعیت حساب،
  /// مصرف، کنترل محتوا و وضعیت منوی اشتراک رایگان / نوروزی) بدون بستن یا
  /// ورود مجدد.
  Future<void> _applyLiveServerState({
    Account? account,
    FilterSettings? filter,
    SubscriptionOffers? offers,
    bool? emergencyEnabled,
    bool? botLinked,
  }) async {
    final SessionData? current = _session;
    if (current == null) {
      return;
    }

    Account nextAccount = current.account;
    if (account != null) {
      nextAccount = _mergeAccount(
        current.account,
        account,
        emergencyEnabledOverride: emergencyEnabled,
      );
    } else if (emergencyEnabled != null &&
        current.account.emergencyEnabled != emergencyEnabled) {
      nextAccount = current.account.copyWith(
        emergencyEnabled: emergencyEnabled,
      );
    }
    final bool accountChanged = !_sameAccount(current.account, nextAccount);
    final bool accessLost =
        current.account.canConnect && !nextAccount.canConnect;
    final bool needsSubResync = nextAccount.canConnect &&
        _subscriptionNeedsResync(current.account, nextAccount);

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

    bool botLinkedChanged = false;
    if (botLinked != null && _botLinked != botLinked) {
      _botLinked = botLinked;
      botLinkedChanged = true;
    }

    if (!accountChanged &&
        !filterChanged &&
        !offersChanged &&
        !botLinkedChanged) {
      return;
    }

    if (accountChanged || filterChanged || offersChanged) {
      _session = current.copyWith(
        account: nextAccount,
        filter: nextFilter,
        offers: nextOffers,
      );
      if (accountChanged) {
        await _syncNotificationOwner(_session!.ownerKey);
      }
      await _store.writeJson(StoreKeys.session, _session!.toJson());
      if (filterChanged) {
        await _store.writeJson(StoreKeys.filter, nextFilter.toJson());
      }
    }
    if (filterEffectChanged) {
      onFilterChanged?.call(nextFilter);
    }
    if (accessLost) {
      onAccessRevoked?.call(nextAccount.accessReason);
    }
    if (needsSubResync && onSubscriptionClaimed != null) {
      unawaited(onSubscriptionClaimed!());
    }
    notifyListeners();
  }

  /// همگام سازی کاملاً خودکار پس زمینه (کنترل محتوا، هدیه ها، حساب و اعلان ها).
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

  Future<bool> saveBypass(FilterSettings settings) async {
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
          await _gateway.saveBypass(session.token, settings);
      if (_session?.token != session.token) return false;
      final SessionData nextSession = _session!.copyWith(filter: saved);
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

  Future<bool> loadSubscriptionPlans({bool silent = true}) async {
    final SessionData? session = _session;
    if (session == null || _loadingSubscriptionPlans) return false;
    _loadingSubscriptionPlans = true;
    try {
      final ({List<SubscriptionPlan> plans, int balance, CustomSubscriptionTerms? custom}) result =
          await _gateway.subscriptionPlans(session.token);
      if (_session?.token != session.token) return false;
      _subscriptionPlans = result.plans;
      _customSubscriptionTerms = result.custom;
      _walletBalance = result.balance;
      return true;
    } on ApiError catch (error) {
      if (!silent) {
        _error = error.message;
        _logError(error.message);
      }
      return false;
    } finally {
      _loadingSubscriptionPlans = false;
      notifyListeners();
    }
  }

  /// خرید یا تمدید از همان تعرفه/کیف پول ربات؛ checkout URL فقط پس از ساخت
  /// سفارش سرورمحور برمی گردد و نتیجه پرداخت در callback زرین پال تایید می شود.
  Future<({String status, String checkoutUrl, String message})?>
      purchaseSubscriptionPlan(String month, {int? days, double? gb, int? quotedPrice}) async {
    final SessionData? session = _session;
    if (session == null || _purchasingSubscription) return null;
    _purchasingSubscription = true;
    _error = '';
    notifyListeners();
    try {
      final Map<String, dynamic> result = days != null && gb != null
          ? await _gateway.purchaseCustomSubscription(token: session.token, days: days, gb: gb, quotedPrice: quotedPrice)
          : await _gateway.purchaseSubscription(token: session.token, month: month, quotedPrice: quotedPrice);
      if (_session?.token != session.token) return null;
      final String status = JsonX.text(result['status']);
      String message = JsonX.text(result['message']);
      final String checkoutUrl = JsonX.text(result['checkout_url']);
      if (status == 'payment_required') {
        // Show the pending order immediately, then fetch its server-issued
        // cancellation token. Never manufacture a token from checkout data.
        _walletPaymentPending = true;
        _walletPendingId = '';
        _walletTopupPending = false;
        _walletCheckoutUrl = '';
        unawaited(refreshWallet(silent: true));
        final int gatewayAmount = JsonX.integer(result['gateway_amount']);
        final int fee = JsonX.integer(result['fee']);
        message = 'قابل پرداخت از درگاه ${Fa.num(gatewayAmount)} تومان'
            '${fee > 0 ? '، شامل ${Fa.num(fee)} تومان کارمزد' : ''} است.';
      }
      if (status == 'activated') {
        await refreshAccount(silent: true);
        await loadSubscriptionPlans();
        if (onSubscriptionClaimed != null) {
          unawaited(onSubscriptionClaimed!());
        }
      }
      return (status: status, checkoutUrl: checkoutUrl, message: message);
    } on ApiError catch (error) {
      if (error.code == 'device_revoked') {
        await _handleDeviceRevoked(error.message);
      } else {
        _error = error.message;
        _logError(error.message);
      }
      return null;
    } finally {
      _purchasingSubscription = false;
      notifyListeners();
    }
  }

  /// فعال سازی اشتراک رایگان (۳ گیگ / ۱ روز) یا نوروزی (۵ گیگ / ۱۳ روز) همگام با ربات.
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
        unawaited(refreshAccount(silent: true).then<void>((_) {}));
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
    _subscriptionPlans = <SubscriptionPlan>[];
    _customSubscriptionTerms = null;
    _botLinked = null;
    _walletBalance = 0;
    _walletLoaded = false;
    _walletExactBalance = 0;
    _walletMinTopup = 0;
    _walletMaxTopup = 0;
    _walletPaymentPending = false;
    _walletPendingId = '';
    _walletTopupPending = false;
    _walletPendingCredit = 0;
    _walletPendingAmount = 0;
    _walletCheckoutUrl = '';
    onFilterChanged?.call(FilterSettings.empty);
    _phase = AuthPhase.phone;
    _stage = SignInStage.unknown;
    final String challenge = _challenge;
    _challenge = '';
    _error = '';
    _info = '';
    await _store.remove(StoreKeys.session);
    unawaited(_syncNativeBackgroundSecurityAuth());
    notifyListeners();
    if (callServer && session != null) {
      try {
        await _gateway.signOut(token: session.token, challenge: challenge);
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
