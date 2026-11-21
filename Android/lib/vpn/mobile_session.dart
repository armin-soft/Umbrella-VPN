import 'dart:async';

/// Platform and core operations needed to establish a VPN session.
/// Implementations must not report [verifyTraffic] true unless traffic has
/// actually passed through the VPN; starting a process alone is insufficient.
abstract class MobileVpnBackend {
  Future<bool> requestPermission();
  Future<void> startService();
  Future<void> configureAndStart();
  Future<bool> verifyTraffic();
  Future<void> stopService();
}

/// Safe, user-facing stage only; never include profile links or credentials.
class MobileVpnFailure implements Exception {
  const MobileVpnFailure(this.message);
  final String message;
}

enum MobileSessionState { disconnected, connecting, connected, disconnecting, failed }

/// Serializes start/stop and ensures that cancellation cannot publish a stale
/// successful connection. The native service must also close its TUN on stop.
class MobileVpnSession {
  MobileVpnSession(this._backend);
  final MobileVpnBackend _backend;

  MobileSessionState _state = MobileSessionState.disconnected;
  MobileSessionState get state => _state;
  String _error = '';
  String get error => _error;
  int _generation = 0;
  Future<void>? _start;
  Future<void>? _stop;
  bool _cleanupFailed = false;

  Future<bool> connect() async {
    if (_state == MobileSessionState.connected) return true;
    // Never start a second core while cleanup of the previous one is uncertain.
    // A successful disconnect must clear this condition first.
    if (_start != null || _stop != null || _cleanupFailed) return false;
    final int generation = ++_generation;
    _state = MobileSessionState.connecting;
    _error = '';
    _cleanupFailed = false;
    final Completer<void> completed = Completer<void>();
    _start = completed.future;
    bool serviceStarted = false;
    var failureMessage = 'درخواست مجوز VPN ناموفق بود.';
    try {
      if (!await _backend.requestPermission()) {
        if (generation == _generation) {
          _error = 'مجوز VPN داده نشد.';
          _state = MobileSessionState.failed;
        }
        return false;
      }
      if (generation != _generation) return false;
      // startService can partially succeed before throwing: cleanup is required.
      serviceStarted = true;
      failureMessage = 'راه‌اندازی سرویس VPN ناموفق بود.';
      await _backend.startService();
      if (generation != _generation) return false;
      failureMessage = 'آماده‌سازی هسته یا تنظیمات سرور ناموفق بود.';
      await _backend.configureAndStart();
      if (generation != _generation) return false;
      failureMessage = 'عبور ترافیک از تونل تأیید نشد؛ سرور و شبکه را بررسی کنید.';
      if (!await _backend.verifyTraffic()) {
        throw StateError('VPN traffic verification failed');
      }
      if (generation != _generation) return false;
      _state = MobileSessionState.connected;
      return true;
    } catch (error) {
      if (generation == _generation) {
        _error = error is MobileVpnFailure ? error.message : failureMessage;
        _state = MobileSessionState.failed;
      }
      return false;
    } finally {
      if (serviceStarted && _state != MobileSessionState.connected) {
        try {
          await _backend.stopService();
        } catch (_) {
          _cleanupFailed = true;
          if (generation == _generation) {
            _error = 'توقف سرویس VPN ناموفق بود.';
            _state = MobileSessionState.failed;
          }
        }
      }
      _start = null;
      completed.complete();
    }
  }

  Future<void> disconnect() {
    final Future<void>? stopping = _stop;
    if (stopping != null) return stopping;
    ++_generation;
    final Future<void>? starting = _start;
    final Completer<void> completed = Completer<void>();
    _stop = completed.future;
    _state = MobileSessionState.disconnecting;
    () async {
      try {
        if (starting != null) {
          // The in-flight connect performs its own cleanup in finally.
          await starting;
          if (_cleanupFailed) throw StateError('VPN cleanup failed');
        } else {
          await _backend.stopService();
        }
        _cleanupFailed = false;
        _state = MobileSessionState.disconnected;
        _error = '';
      } catch (_) {
        _cleanupFailed = true;
        _state = MobileSessionState.failed;
        _error = 'توقف سرویس VPN ناموفق بود.';
      } finally {
        _stop = null;
        completed.complete();
      }
    }();
    return completed.future;
  }
}
