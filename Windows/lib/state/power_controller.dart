import 'dart:async';

import 'package:flutter/foundation.dart';

import '../platform/native.dart';

/// شناسایی لپ تاپ و برنامه ریزی سبک بر اساس برق؛ وضعیت نامشخص ایمن است.
class PowerController extends ChangeNotifier {
  PowerController({required Future<BatteryPowerState?> Function() readStatus,
    bool enabled = true, this.pollInterval = const Duration(seconds: 30)})
      : _readStatus = readStatus, _enabled = enabled;

  final Future<BatteryPowerState?> Function() _readStatus;
  final Duration pollInterval;
  bool _enabled;
  bool _active = false;
  bool? _isLaptop;
  bool _reading = false;
  bool _disposed = false;
  Timer? _timer;
  bool get active => _active;
  bool? get isLaptop => _isLaptop;

  void start() {
    if (_disposed || _timer != null) return;
    unawaited(refresh());
    _timer = Timer.periodic(pollInterval, (_) => unawaited(refresh()));
  }

  void setEnabled(bool enabled) {
    if (_disposed || _enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) _update(active: false);
    // Continue detecting hardware even if the user has disabled optimization.
    unawaited(refresh());
  }

  Future<void> refresh() async {
    if (_disposed || _reading) return;
    _reading = true;
    try {
      final state = await _readStatus();
      if (!_disposed) {
        _update(laptop: state?.isLaptop,
            active: _enabled && (state?.shouldOptimize ?? false));
      }
    } catch (_) {
      if (!_disposed) _update(active: false);
    } finally {
      _reading = false;
    }
  }

  void _update({bool? laptop, required bool active}) {
    if (_disposed) return;
    final bool? nextLaptop = laptop ?? _isLaptop;
    if (_active == active && _isLaptop == nextLaptop) return;
    _active = active;
    _isLaptop = nextLaptop;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
