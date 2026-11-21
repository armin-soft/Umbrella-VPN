import 'dart:async';

import 'package:flutter/material.dart';

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
