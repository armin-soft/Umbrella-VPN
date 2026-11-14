import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import 'persian.dart';

export 'persian.dart';

/// خطای لایه شبکه با پیام فارسی آماده نمایش.
class ApiError implements Exception {
  const ApiError(this.code, this.message, {this.retryAfter, this.status});

  final String code;
  final String message;
  final int? retryAfter;
  final int? status;

  bool get isNetwork => code == 'network' || code == 'timeout';

  bool get needsLogin =>
      code == 'invalid_token' || code == 'unauthorized' || code == 'session_expired';

  @override
  String toString() => '$code: $message';
}

class LogLine {
  LogLine(this.message, {this.level = 'info', DateTime? time})
    : time = time ?? DateTime.now();

  final String message;
  final String level;
  final DateTime time;

  /// چند بار همین پیام پشت سر هم آمده است (۱ یعنی یک بار).
  int repeat = 1;
}

/// تشخیص اپراتور از پیش شماره تلفن همراه.
enum MobileOperator { mci, irancell, rightel, unknown }

extension MobileOperatorX on MobileOperator {
  String get label {
    switch (this) {
      case MobileOperator.mci:
        return 'همراه اول';
      case MobileOperator.irancell:
        return 'ایرانسل';
      case MobileOperator.rightel:
        return 'رایتل';
      case MobileOperator.unknown:
        return 'نامشخص';
    }
  }

  String get latin {
    switch (this) {
      case MobileOperator.mci:
        return 'MCI';
      case MobileOperator.irancell:
        return 'MTN';
      case MobileOperator.rightel:
        return 'RTL';
      case MobileOperator.unknown:
        return 'IR';
    }
  }

  Color get color {
    switch (this) {
      case MobileOperator.mci:
        return const Color(0xFF0072BC);
      case MobileOperator.irancell:
        return const Color(0xFFFFCB05);
      case MobileOperator.rightel:
        return const Color(0xFF7B2D8B);
      case MobileOperator.unknown:
        return const Color(0xFF64748B);
    }
  }

  String get assetName {
    switch (this) {
      case MobileOperator.mci:
        return 'mci';
      case MobileOperator.irancell:
        return 'irancell';
      case MobileOperator.rightel:
        return 'rightel';
      case MobileOperator.unknown:
        return 'unknown';
    }
  }

  /// لوگوی رسمی اپراتور که همراه برنامه نصب می شود.
  String get logoAsset => 'assets/icons/operators/$assetName.png';

  bool get hasLogo => this != MobileOperator.unknown;

  /// رنگ زمینه لوگو؛ لوگوی همراه اول و رایتل تیره است و روی زمینه روشن
  /// خوانده می شود، ایرانسل زرد و روی زمینه تیره.
  Color get chipColor {
    switch (this) {
      case MobileOperator.mci:
        return Colors.white;
      case MobileOperator.irancell:
        return Colors.black;
      case MobileOperator.rightel:
        return Colors.white;
      case MobileOperator.unknown:
        return const Color(0xFF1B2030);
    }
  }
}

class IranPhone {
  const IranPhone._();

  static const Map<String, MobileOperator> _prefixes = <String, MobileOperator>{
    '0910': MobileOperator.mci,
    '0911': MobileOperator.mci,
    '0912': MobileOperator.mci,
    '0913': MobileOperator.mci,
    '0914': MobileOperator.mci,
    '0915': MobileOperator.mci,
    '0916': MobileOperator.mci,
    '0917': MobileOperator.mci,
    '0918': MobileOperator.mci,
    '0919': MobileOperator.mci,
    '0990': MobileOperator.mci,
    '0991': MobileOperator.mci,
    '0992': MobileOperator.mci,
    '0993': MobileOperator.mci,
    '0994': MobileOperator.mci,
    '0900': MobileOperator.irancell,
    '0901': MobileOperator.irancell,
    '0902': MobileOperator.irancell,
    '0903': MobileOperator.irancell,
    '0904': MobileOperator.irancell,
    '0905': MobileOperator.irancell,
    '0930': MobileOperator.irancell,
    '0931': MobileOperator.irancell,
    '0932': MobileOperator.irancell,
    '0933': MobileOperator.irancell,
    '0934': MobileOperator.irancell,
    '0935': MobileOperator.irancell,
    '0936': MobileOperator.irancell,
    '0937': MobileOperator.irancell,
    '0938': MobileOperator.irancell,
    '0939': MobileOperator.irancell,
    '0941': MobileOperator.irancell,
    '0920': MobileOperator.rightel,
    '0921': MobileOperator.rightel,
    '0922': MobileOperator.rightel,
    '0923': MobileOperator.rightel,
    '0924': MobileOperator.rightel,
    '0925': MobileOperator.rightel,
    '0926': MobileOperator.rightel,
    '0927': MobileOperator.rightel,
    '0928': MobileOperator.rightel,
    '0929': MobileOperator.rightel,
  };

  /// همان قاعده سرور: ارقام لاتین، تبدیل +۹۸ و ۰۰۹۸ به ۰۹.
  static String normalize(String input) {
    String phone = Fa.toEn(input.trim());
    phone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (phone.startsWith('+98')) {
      phone = '0${phone.substring(3)}';
    } else if (phone.startsWith('0098')) {
      phone = '0${phone.substring(4)}';
    } else if (phone.startsWith('98') && phone.length == 12) {
      phone = '0${phone.substring(2)}';
    } else if (phone.startsWith('9') && phone.length == 10) {
      phone = '0$phone';
    }
    return phone.replaceAll(RegExp(r'\D'), '');
  }

  static bool isValid(String input) =>
      RegExp(r'^09\d{9}$').hasMatch(normalize(input));

  static MobileOperator operator(String input) {
    final String phone = normalize(input);
    if (!isValid(phone)) {
      return MobileOperator.unknown;
    }
    return _prefixes[phone.substring(0, 4)] ?? MobileOperator.unknown;
  }

  static String display(String input) {
    final String phone = normalize(input);
    if (phone.length != 11) {
      return Fa.num(phone);
    }
    return Fa.num(
      '${phone.substring(0, 4)} ${phone.substring(4, 7)} ${phone.substring(7)}',
    );
  }

  static bool validName(String value) {
    final String trimmed = value.trim();
    if (trimmed.length < 2) {
      return false;
    }
    return RegExp(r'^[\u0600-\u06FF\s]{2,60}$').hasMatch(trimmed);
  }
}

class JsonX {
  const JsonX._();

  static Map<String, dynamic> asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map<String, dynamic>(
        (Object? key, Object? item) => MapEntry<String, dynamic>(key.toString(), item),
      );
    }
    if (value is String && value.trim().isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(value);
        return asMap(decoded);
      } on FormatException {
        return <String, dynamic>{};
      }
    }
    return <String, dynamic>{};
  }

  static List<dynamic> asList(Object? value) {
    if (value is List<dynamic>) {
      return value;
    }
    if (value is String && value.trim().isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(value);
        return asList(decoded);
      } on FormatException {
        return <dynamic>[];
      }
    }
    return <dynamic>[];
  }

  static String text(Object? value, [String fallback = '']) {
    if (value == null) {
      return fallback;
    }
    if (value is String) {
      return value;
    }
    return value.toString();
  }

  static double number(Object? value, [double fallback = 0]) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final String cleaned = Fa.toEn(value).replaceAll(',', '.').trim();
      return double.tryParse(cleaned) ?? fallback;
    }
    return fallback;
  }

  static int integer(Object? value, [int fallback = 0]) =>
      number(value, fallback.toDouble()).round();

  static bool boolean(Object? value, {bool fallback = false}) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final String text = value.trim().toLowerCase();
      if (<String>['true', '1', 'yes', 'on'].contains(text)) {
        return true;
      }
      if (<String>['false', '0', 'no', 'off', ''].contains(text)) {
        return false;
      }
    }
    return fallback;
  }

  static DateTime? dateTime(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      final int seconds = value > 2000000000000 ? value ~/ 1000 : value;
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    }
    if (value is double) {
      return dateTime(value.round());
    }
    final String text = value.toString().trim();
    if (text.isEmpty) {
      return null;
    }
    final int? numeric = int.tryParse(text);
    if (numeric != null && numeric > 0) {
      return dateTime(numeric);
    }
    return DateTime.tryParse(text.replaceFirst(' ', 'T'));
  }
}

/// شناسه پایدار برای هر گره بر اساس متن اشتراک.
String stableId(String seed) {
  final List<int> bytes = utf8.encode(seed);
  return sha1.convert(bytes).toString().substring(0, 16);
}
