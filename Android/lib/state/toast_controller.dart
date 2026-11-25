import 'dart:async';

import 'package:flutter/material.dart';

import '../platform/services.dart';

enum ToastKind { info, success, warning, error }

class ToastMessage {
  const ToastMessage({
    required this.id,
    required this.title,
    required this.message,
    required this.kind,
    this.icon,
    this.duration = const Duration(seconds: 4),
  });

  final int id;
  final String title;
  final String message;
  final ToastKind kind;
  final IconData? icon;
  final Duration duration;
}

/// اعلان های شناور بالای وسط صفحه: رنگ، آیکون و متن مناسب هر پیام.
class ToastController extends ChangeNotifier {
  ToastController({this.sound});
  final SoundService? sound;
  final List<ToastMessage> _items = <ToastMessage>[];
  final Map<int, Timer> _timers = <int, Timer>{};
  int _nextId = 1;

  List<ToastMessage> get items => List<ToastMessage>.unmodifiable(_items);

  void show({
    required String title,
    String message = '',
    ToastKind kind = ToastKind.info,
    IconData? icon,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (kind == ToastKind.error || kind == ToastKind.warning) {
      // The message may contain server responses, user input or payment data.
      // Classify the visible action without recording its arbitrary content.
      final String area = title.contains('پرداخت') || title.contains('کیف پول') || title.contains('خرید') || title.contains('سفارش')
          ? 'پرداخت و کیف پول'
          : title.contains('تنظیم') || title.contains('محتوا') || title.contains('مسیر مستقیم')
              ? 'تنظیمات'
              : title.contains('اشتراک') || title.contains('پروفایل')
                  ? 'اشتراک'
                  : title.contains('ورود') || title.contains('حساب') || title.contains('دستگاه')
                      ? 'حساب و دستگاه'
                      : title.contains('اتصال') || title.contains('سرور')
                          ? 'اتصال' : 'عملیات برنامه';
      AppLogger.instance.add('اعلان ${kind == ToastKind.error ? 'خطا' : 'هشدار'} در بخش $area',
          level: kind == ToastKind.error ? 'error' : 'warning');
    }
    final SoundService? audio = sound;
    if (audio != null && audio.enabled && kind != ToastKind.info) {
      unawaited(audio.play(kind == ToastKind.error ? 'error' : 'notify')
          .catchError((Object _) {}));
    }
    final ToastMessage toast = ToastMessage(
      id: _nextId++,
      title: title,
      message: message,
      kind: kind,
      icon: icon,
      duration: duration,
    );
    _items.add(toast);
    while (_items.length > 4) {
      final ToastMessage removed = _items.removeAt(0);
      _timers.remove(removed.id)?.cancel();
    }
    _timers[toast.id] = Timer(duration, () => dismiss(toast.id));
    notifyListeners();
  }

  void success(String title, [String message = '']) =>
      show(title: title, message: message, kind: ToastKind.success);

  void warning(String title, [String message = '']) =>
      show(title: title, message: message, kind: ToastKind.warning);

  void error(String title, [String message = '']) =>
      show(
        title: title,
        message: message,
        kind: ToastKind.error,
        duration: const Duration(seconds: 6),
      );

  void info(String title, [String message = '']) =>
      show(title: title, message: message, kind: ToastKind.info);

  void dismiss(int id) {
    _timers.remove(id)?.cancel();
    _items.removeWhere((ToastMessage item) => item.id == id);
    notifyListeners();
  }

  void clear() {
    for (final Timer timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _items.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final Timer timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}
