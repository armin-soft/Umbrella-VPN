import 'dart:async';

import 'package:flutter/foundation.dart';

import '../platform/native.dart';

/// برنامه ریزی سبک بر اساس برق ویندوز؛ در وضعیت نامشخص حالت عادی حفظ می شود.
class PowerController extends ChangeNotifier {
  PowerController({required Future<BatteryPowerState?> Function() readStatus,
    bool enabled = true, this.pollInterval = const Duration(seconds: 30)})
      : _readStatus = readStatus, _enabled = enabled;

  final Future<BatteryPowerState?> Function() _readStatus;
  final Duration pollInterval;
  bool _enabled;
  bool _active = false;
  bool _reading = false;
  bool _disposed = false;
  Timer? _timer;
  bool get active => _active;

  void start() {
    if (_disposed || _timer != null) return;
    unawaited(refresh());
    _timer = Timer.periodic(pollInterval, (_) => unawaited(refresh()));
  }

  void setEnabled(bool enabled) {
    if (_disposed || _enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) {
      _setActive(false);
    } else {
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    if (_disposed || _reading || !_enabled) return;
    _reading = true;
    try {
      final state = await _readStatus();
      if (!_disposed && _enabled) _setActive(state?.shouldOptimize ?? false);
    } catch (_) {
      if (!_disposed && _enabled) _setActive(false);
    } finally {
      _reading = false;
    }
  }

  void _setActive(bool value) {
    if (_active == value || _disposed) return;
    _active = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
