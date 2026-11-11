import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../core/storage.dart';
import '../core/utils.dart';
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
  })  : _native = native,
        _gateway = gateway ?? GatewayClient(baseUrl: gatewayBase),
        _store = store ?? LocalStore.instance;

  final NativeBridge _native;
  final GatewayClient _gateway;
  final LocalStore _store;
  final AppLogger _log = AppLogger.instance;

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

  List<AppNotification> _notifications = <AppNotification>[];
  List<AppNotification> get notifications => List<AppNotification>.unmodifiable(_notifications);
  int get unreadCount =>
      _notifications.where((AppNotification item) => !item.read).length;

  Timer? _pollTimer;
  Timer? _clockTimer;
  Timer? _heartbeatTimer;
  bool _restored = false;

  Future<void> restore() async {
    if (_restored) {
      return;
    }
    _restored = true;
    _device = await _native.deviceInfo();
    _deviceId = _store.read(StoreKeys.deviceId) ?? '';
    if (_deviceId.isEmpty) {
      _deviceId = _generateDeviceId();
      await _store.write(StoreKeys.deviceId, _deviceId);
    }
    final Map<String, dynamic> json = _store.readJson(StoreKeys.session);
    if (json.isNotEmpty) {
      _session = SessionData.fromJson(json);
      if (_session!.token.isEmpty) {
        _session = null;
      } else {
        _phase = AuthPhase.done;
        _phone = _session!.account.phone;
        unawaited(refreshAccount(silent: true));
      }
    }
    final List<dynamic> cached = _store.readJsonList(StoreKeys.notifications);
    _notifications =
        cached.map((Object? item) => AppNotification.fromJson(JsonX.asMap(item))).toList();
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

  String get baseUrl => _gateway.baseUrl;

  Future<void> setGatewayBase(String base) async {
    await _store.write('gateway.base', base);
    notifyListeners();
  }

  // ── گام یک: شماره موبایل ─────────────────────────────────────────────

  Future<bool> submitPhone(String rawPhone) async {
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
      final SignInStart start = await _gateway.start(
        phone: phone,
        deviceId: _deviceId,
        deviceName: _device.deviceName,
        platform: _device.platformLabel,
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
    _firstName = first.trim();
    _lastName = last.trim();
    _busy = true;
    notifyListeners();
    try {
      final SignInStart start = await _gateway.start(
        phone: _phone,
        deviceId: _deviceId,
        deviceName: _device.deviceName,
        platform: _device.platformLabel,
        firstName: _firstName,
        lastName: _lastName,
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
      await _store.writeJson(StoreKeys.session, session.toJson());
      await _store.writeJson(StoreKeys.filter, session.filter.toJson());
      _startHeartbeat();
      _log.add('ورود موفق؛ خوش آمدید ${session.account.displayName}.');
      unawaited(fetchNotifications());
      notifyListeners();
    } on ApiError catch (error) {
      _error = error.message;
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
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      final SessionData? session = _session;
      if (session == null) {
        return;
      }
      unawaited(
        _gateway.heartbeat(token: session.token, deviceId: _deviceId),
      );
    });
  }

  Future<void> refreshAccount({bool silent = false}) async {
    final SessionData? session = _session;
    if (session == null) {
      return;
    }
    try {
      final SessionData fresh = await _gateway.refresh(session.token);
      _session = session.copyWith(account: fresh.account, filter: fresh.filter);
      await _store.writeJson(StoreKeys.session, _session!.toJson());
      await _store.writeJson(StoreKeys.filter, fresh.filter.toJson());
      notifyListeners();
    } on ApiError catch (error) {
      if (error.needsLogin) {
        await signOut(callServer: false);
        if (!silent) {
          _error = 'نشست منقضی شد؛ دوباره وارد شوید.';
          notifyListeners();
        }
      }
    }
  }

  Future<bool> saveFilter(FilterSettings settings) async {
    final SessionData? session = _session;
    if (session == null) {
      return false;
    }
    try {
      final FilterSettings saved = await _gateway.saveFilter(session.token, settings);
      _session = session.copyWith(filter: saved);
      await _store.writeJson(StoreKeys.filter, saved.toJson());
      notifyListeners();
      return true;
    } on ApiError catch (error) {
      _error = error.message;
      notifyListeners();
      return false;
    }
  }

  Future<void> fetchNotifications() async {
    final SessionData? session = _session;
    if (session == null) {
      return;
    }
    try {
      final List<AppNotification> items = await _gateway.notifications(session.token);
      _notifications = items;
      await _store.writeJsonList(
        StoreKeys.notifications,
        items.map((AppNotification item) => item.toJson()).toList(),
      );
      notifyListeners();
    } on ApiError {
      return;
    }
  }

  void markNotificationsRead() {
    _notifications = _notifications
        .map((AppNotification item) => item.copyWith(read: true))
        .toList();
    unawaited(
      _store.writeJsonList(
        StoreKeys.notifications,
        _notifications.map((AppNotification item) => item.toJson()).toList(),
      ),
    );
    notifyListeners();
  }

  Future<void> signOut({bool callServer = true}) async {
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    _heartbeatTimer?.cancel();
    final SessionData? session = _session;
    _session = null;
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
