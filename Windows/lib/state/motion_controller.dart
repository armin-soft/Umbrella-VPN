import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../platform/native.dart';

/// مدیریت هوشمند پویانمایی های تزئینی رابط کاربری:
/// پویانمایی تنها در پنجره قابل رویت، روی برق شهری یا پس از تغییر وضعیت برای
/// مدت محدود فعال می ماند و در مصرف بالای پردازنده یا باتری ضعیف متوقف می شود.
class MotionController extends ChangeNotifier {
  MotionController({
    NativeBridge? native,
    int? processorCount,
    Duration ambientDuration = const Duration(seconds: 10),
    Duration cpuSampleDelay = const Duration(seconds: 10),
  })  : _native = native,
        _processorCount = processorCount ?? Platform.numberOfProcessors,
        _ambientDuration = ambientDuration,
        _cpuSampleDelay = cpuSampleDelay;

  final NativeBridge? _native;
  final int _processorCount;
  final Duration _ambientDuration;
  final Duration _cpuSampleDelay;

  Timer? _ambientTimer;
  Timer? _cpuTimer;
  bool _disposed = false;

  bool _appVisible = true;
  bool _ambientActive = true;
  bool _powerSaving = false;
  bool _cpuThrottled = false;

  bool get appVisible => _appVisible;
  bool get ambientActive => _ambientActive;
  bool get powerSaving => _powerSaving;
  bool get cpuThrottled => _cpuThrottled;

  /// آیا اجرای پویانمایی تزئینی در لحظه مجاز و به صرفه است؟
  bool get shouldAnimateAmbient =>
      _appVisible && _ambientActive && !_powerSaving && !_cpuThrottled;

  /// دسترسی اختیاری تا تست هایی که کنترلر را تزریق نکرده اند بدون خطا کار کنند.
  static MotionController? maybeWatch(BuildContext context) {
    try {
      return Provider.of<MotionController>(context);
    } on ProviderNotFoundException {
      return null;
    }
  }

  void setAppVisible(bool visible) {
    if (_disposed || _appVisible == visible) return;
    _appVisible = visible;
    notifyListeners();
  }

  void setPowerSaving(bool saving) {
    if (_disposed || _powerSaving == saving) return;
    _powerSaving = saving;
    if (saving) {
      _ambientTimer?.cancel();
      _ambientActive = false;
    }
    notifyListeners();
  }

  /// فعال سازی موقت موج آرام وضعیت هنگام راه اندازی یا اتصال تازه، سپس آرام شدن.
  void pulseAmbient() {
    if (_disposed) return;
    _ambientTimer?.cancel();
    if (_powerSaving || _cpuThrottled) {
      if (_ambientActive) {
        _ambientActive = false;
        notifyListeners();
      }
      return;
    }
    final bool changed = !_ambientActive;
    _ambientActive = true;
    _ambientTimer = Timer(_ambientDuration, () {
      if (_disposed || !_ambientActive) return;
      _ambientActive = false;
      notifyListeners();
    });
    if (changed) notifyListeners();
  }

  /// سنجش مصرف پردازنده در ۱۰ ثانیه اول پس از اتصال؛ اگر بالای ۱۰٪ بود،
  /// پویانمایی های تزئینی به صورت خودکار خاموش می شوند تا باتری و پردازنده هدر نرود.
  Future<void> checkConnectCpuBudget() async {
    final NativeBridge? native = _native;
    if (_disposed || _cpuThrottled || native == null) return;
    final int? startUs = await native.processCpuTimeMicros();
    if (startUs == null || _disposed) return;
    final Stopwatch wall = Stopwatch()..start();
    _cpuTimer?.cancel();
    _cpuTimer = Timer(_cpuSampleDelay, () async {
      if (_disposed || _cpuThrottled) return;
      final int? endUs = await native.processCpuTimeMicros();
      wall.stop();
      if (endUs == null || _disposed) return;
      final int cpuDeltaUs = endUs - startUs;
      final int wallUs = wall.elapsedMicroseconds;
      final int cores = _processorCount > 0 ? _processorCount : 1;
      if (cpuDeltaUs > 0 && wallUs > 0) {
        final double utilization = cpuDeltaUs / (wallUs * cores);
        if (utilization > 0.10) {
          _cpuThrottled = true;
          _ambientTimer?.cancel();
          _ambientActive = false;
          notifyListeners();
        }
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _ambientTimer?.cancel();
    _cpuTimer?.cancel();
    super.dispose();
  }
}
