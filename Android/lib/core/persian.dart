import 'dart:io';

/// ابزارهای فارسی سازی: ارقام، تاریخ شمسی، حجم، سرعت و مدت زمان.
///
/// همه متن های برنامه فارسی و بدون نیم فاصله هستند و همه ارقام با این فایل
/// به شکل فارسی نمایش داده می شوند، جز مقدارهای فنی که باید دقیق بمانند.
/// نام دیگر نوع عدد، چون متد ایستای [Fa.num] نام نوع num را در بدنه کلاس
/// پنهان می کند و در امضای متدها قابل استفاده نیست.
typedef NumericValue = num;

class Fa {
  const Fa._();

  static const List<String> digits = <String>[
    '۰',
    '۱',
    '۲',
    '۳',
    '۴',
    '۵',
    '۶',
    '۷',
    '۸',
    '۹',
  ];

  static const List<String> months = <String>[
    'فروردین',
    'اردیبهشت',
    'خرداد',
    'تیر',
    'مرداد',
    'شهریور',
    'مهر',
    'آبان',
    'آذر',
    'دی',
    'بهمن',
    'اسفند',
  ];

  static const List<String> weekDays = <String>[
    'دوشنبه',
    'سه شنبه',
    'چهارشنبه',
    'پنجشنبه',
    'جمعه',
    'شنبه',
    'یکشنبه',
  ];

  static final List<RegExp> _preIpv6Patterns = <RegExp>[
    // پیوندهای Markdown و صفت href در HTML باید با ارقام انگلیسی دست نخورده بمانند.
    RegExp(r'\]\([^)\n\uE000-\uF8FF]*\)'),
    RegExp(r'''href=(?:"[^"\uE000-\uF8FF]*"|'[^'\uE000-\uF8FF]*')''', caseSensitive: false),
    // تمام نشانی های دارای پروتکل (وب، تلگرام، پروکسی ها، ایمیل و لینک های سیستمی)
    RegExp(
      r'(?<![A-Za-z0-9+.-])(?:[A-Za-z][A-Za-z0-9+.-]*://|mailto:|tel:|magnet:)[^\s<>"`\uE000-\uF8FF]+',
      caseSensitive: false,
    ),
    RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'),
    RegExp(r'@[A-Za-z][A-Za-z0-9_]{2,}\b'),
    // نشانی ها و دامنه های دارای پورت یا مسیر بدون پروتکل (مانند t.me/c/123 و site.ir:8443/sub)
    RegExp(
      r'\b(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}(?::\d{1,5})?(?:[/?#][^\s<>"`\uE000-\uF8FF]*)?',
    ),
    // مسیرهای فایل ویندوز و اندروید / یونیکس
    RegExp(r'(?<![A-Za-z0-9])[A-Za-z]:\\[^\s<>"`\uE000-\uF8FF]+'),
    RegExp(
      r'(?<![A-Za-z0-9/])/(?:sdcard|storage|data|system|vendor|product|apex|mnt|usr|etc|var|opt|home|root|tmp|downloads?|app)/[^\s<>"`\uE000-\uF8FF]+',
      caseSensitive: false,
    ),
  ];

  static final List<RegExp> _postIpv6Patterns = <RegExp>[
    RegExp(r'\b[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\b'),
    RegExp(r'\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b'),
    RegExp(
      r'\b\d{1,3}(?:\.\d{1,3}){3}(?::\d{1,5})?(?:/\d{1,2})?\b(?:[/?#][^\s<>"`\uE000-\uF8FF]*)?',
    ),
    RegExp(r'\b0x[0-9A-Fa-f]+\b', caseSensitive: false),
    RegExp(
      r'\b(?:IPv[46]|(?:TLS|SSL|HTTP|SOCKS|TCP|UDP|QUIC)\s*v?\d+(?:\.\d+)*|(?:TCP|UDP|HTTP|HTTPS|TLS|SSL|SOCKS|QUIC)[/:]\d{1,5}(?:\.\d+)*)\b',
      caseSensitive: false,
    ),
    RegExp(r'(?:پورت|port)\s*[:=]?\s*\d{1,5}\b', caseSensitive: false),
    RegExp(
      r'(?:شناسه(?:\s+(?:عدد(?:ی)?|فنی|یکتا|یکتای|حساب|کاربری|تلگرام|دستگاه|پردازش|سیستم)){0,3}|(?:process|thread)\s*(?:id|pid)|pid)\s*[:=#]?\s*(?:0x[0-9a-f]+|\d+)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:کد\s+خطا(?:ی)?(?:\s+ویندوز)?|کد\s+خروج|کد\s+(?:وضعیت|پاسخ)|(?:error|exit)\s*code)\s*[:=]?\s*(?:0x[0-9a-f]+|\d+)\b',
      caseSensitive: false,
    ),
  ];

  static final RegExp _ipv6Candidate = RegExp(
    r'(?<![A-Za-z0-9])(?:\[[0-9A-Fa-f:.]+(?:%[A-Za-z0-9_.-]+)?\](?::\d{1,5})?(?:[/?#][^\s<>"`\uE000-\uF8FF]*)?|[0-9A-Fa-f:.]*:[0-9A-Fa-f:.]*(?:%[A-Za-z0-9_.-]+)?)(?![A-Za-z0-9])',
  );
  static final RegExp _technicalCodePattern = RegExp(
    r'\b(?=[A-Za-z0-9._/-]*[A-Za-z])(?=[A-Za-z0-9._/-]*\d)[A-Za-z0-9][A-Za-z0-9._/-]*\b',
  );
  static final RegExp _needsPersianNormalization =
      RegExp(r'[0-9\u0660-\u0669\u200C]');

  /// تبدیل ارقام لاتین و عربی به فارسی، بدون تغییر مقدارهای فنی قابل کپی.
  static String num(Object? value) {
    String text = (value ?? '').toString();
    if (!_needsPersianNormalization.hasMatch(text)) return text;
    final Map<String, String> preserved = <String, String>{};
    int tokenIndex = 0;

    String hold(String value) {
      String token;
      do {
        token = String.fromCharCode(0xE000 + (tokenIndex++));
      } while (text.contains(token));
      preserved[token] = value;
      return token;
    }

    String keep(Match match) => hold(match[0]!);

    // حفظ URIها، پیوندها، مسیر فایل ها و دامنه ها پیش از تشخیص IPv6 تا نشانی های کامل یکپارچه بمانند.
    for (final RegExp pattern in _preIpv6Patterns) {
      text = text.replaceAllMapped(pattern, keep);
    }
    text = text.replaceAllMapped(_ipv6Candidate, (Match match) {
      final String candidate = match[0]!;
      final bool bracketed = candidate.startsWith('[');
      final int closeBracket = candidate.indexOf(']');
      final String address = bracketed
          ? candidate.substring(1, closeBracket)
          : candidate.replaceFirst(RegExp(r'[.,;!?]+$'), '');
      final String addressWithoutZone = address.replaceFirst(
        RegExp(r'%[A-Za-z0-9_.-]+$'),
        '',
      );
      bool isIpv6 = false;
      try {
        isIpv6 = InternetAddress.tryParse(addressWithoutZone)?.type ==
            InternetAddressType.IPv6;
      } on FormatException {
        // Invalid colon-separated values such as a time are ordinary text.
      }
      if (isIpv6) return keep(match);
      return candidate;
    });
    // سپس UUID، MAC، IPv4، کدها و مقدارهای دارای برچسب حفظ می شوند.
    for (final RegExp pattern in _postIpv6Patterns) {
      text = text.replaceAllMapped(pattern, keep);
    }
    text = text.replaceAllMapped(_technicalCodePattern, keep);

    final StringBuffer buffer = StringBuffer();
    for (final int rune in text.runes) {
      if (rune >= 48 && rune <= 57) {
        buffer.write(digits[rune - 48]);
      } else if (rune >= 0x0660 && rune <= 0x0669) {
        buffer.write(digits[rune - 0x0660]);
      } else if (rune == 0x200C) {
        buffer.write(' ');
      } else {
        buffer.writeCharCode(rune);
      }
    }
    String result = buffer.toString();
    for (final MapEntry<String, String> entry in preserved.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }

  /// تبدیل ارقام فارسی و عربی یک متن به لاتین، برای ارسال به سرور.
  static String toEn(String input) {
    const String fa = '۰۱۲۳۴۵۶۷۸۹';
    const String ar = '٠١٢٣٤٥٦٧٨٩';
    final StringBuffer buffer = StringBuffer();
    for (final int rune in input.runes) {
      final String ch = String.fromCharCode(rune);
      final int faIndex = fa.indexOf(ch);
      final int arIndex = ar.indexOf(ch);
      if (faIndex >= 0) {
        buffer.write(faIndex);
      } else if (arIndex >= 0) {
        buffer.write(arIndex);
      } else {
        buffer.write(ch);
      }
    }
    return buffer.toString();
  }

  /// حذف کامل اموجی ها و نمادهای گرافیکی از متن اعلان ها با حفظ حروف فارسی و اعداد.
  static String stripEmojis(String text) {
    if (text.isEmpty) return '';
    final StringBuffer buffer = StringBuffer();
    for (final int rune in text.runes) {
      final bool isEmoji = (rune >= 0x1F000 && rune <= 0x1FAFF) ||
          (rune >= 0x2300 && rune <= 0x23FF) ||
          (rune >= 0x2600 && rune <= 0x27BF) ||
          (rune >= 0x2B00 && rune <= 0x2BFF) ||
          (rune >= 0xFE00 && rune <= 0xFE0F) ||
          rune == 0x200D;
      if (!isEmoji) {
        buffer.writeCharCode(rune);
      }
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();
  }

  /// جداکننده هزارگان با ارقام فارسی.
  static String grouped(NumericValue value) {
    final String raw = value.round().abs().toString();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < raw.length; i++) {
      if (i > 0 && (raw.length - i) % 3 == 0) {
        buffer.write('٬');
      }
      buffer.write(raw[i]);
    }
    final String sign = value < 0 ? 'منفی ' : '';
    return sign + num(buffer.toString());
  }

  static String decimal(NumericValue value, {int fraction = 1}) {
    final String text = value.toStringAsFixed(fraction);
    return num(text).replaceAll('.', '٫');
  }

  static String percent(double value) =>
      '${decimal(value.clamp(0, 100), fraction: value >= 100 ? 0 : 1)} درصد';

  static String bytes(int value) {
    if (value <= 0) {
      return '۰ بایت';
    }
    const List<String> units = <String>[
      'بایت',
      'کیلوبایت',
      'مگابایت',
      'گیگابایت',
      'ترابایت',
    ];
    double size = value.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${decimal(size, fraction: size >= 100 ? 0 : 1)} ${units[unit]}';
  }

  static String gb(double value) => '${decimal(value, fraction: 2)} گیگابایت';

  static String speed(double bytesPerSecond) {
    if (bytesPerSecond <= 0) {
      return '۰ کیلوبایت بر ثانیه';
    }
    if (bytesPerSecond < 1024) {
      return '${num(bytesPerSecond.round())} بایت بر ثانیه';
    }
    if (bytesPerSecond < 1024 * 1024) {
      return '${decimal(bytesPerSecond / 1024)} کیلوبایت بر ثانیه';
    }
    return '${decimal(bytesPerSecond / (1024 * 1024))} مگابایت بر ثانیه';
  }

  static String ms(int milliseconds) {
    if (milliseconds <= 0) {
      return 'نامشخص';
    }
    return '${num(milliseconds)} میلی ثانیه';
  }

  static String clock(DateTime time) {
    final String hour = time.hour.toString().padLeft(2, '0');
    final String minute = time.minute.toString().padLeft(2, '0');
    final String second = time.second.toString().padLeft(2, '0');
    return num('$hour:$minute:$second');
  }

  static String duration(Duration value) {
    final int hours = value.inHours;
    final int minutes = value.inMinutes.remainder(60);
    final int seconds = value.inSeconds.remainder(60);
    final String text = hours > 0
        ? '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
        : '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    return num(text);
  }

  static String countdown(Duration value) {
    final int minutes = value.inMinutes;
    final int seconds = value.inSeconds.remainder(60);
    return num('${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}');
  }

  static String days(int count) {
    if (count <= 0) {
      return 'بدون اعتبار';
    }
    if (count == 1) {
      return 'یک روز';
    }
    return '${num(count)} روز';
  }

  /// تاریخ شمسی به شکل ۱۴۰۴/۰۸/۲۰.
  static String date(DateTime? time) {
    if (time == null) {
      return 'نامشخص';
    }
    final JalaliDate jalali = JalaliDate.fromDateTime(time);
    final String month = jalali.month.toString().padLeft(2, '0');
    final String day = jalali.day.toString().padLeft(2, '0');
    return num('${jalali.year}/$month/$day');
  }

  /// تاریخ شمسی خوانا: ۲۰ آبان ۱۴۰۴.
  static String longDate(DateTime? time) {
    if (time == null) {
      return 'نامشخص';
    }
    final JalaliDate jalali = JalaliDate.fromDateTime(time);
    return '${num(jalali.day)} ${months[jalali.month - 1]} ${num(jalali.year)}';
  }

  static String dateTime(DateTime? time) {
    if (time == null) {
      return 'نامشخص';
    }
    return '${date(time)} ساعت ${num('${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}')}';
  }

  /// اختلاف زمانی رسمی ایران (تهران: مثبت ۳ ساعت و ۳۰ دقیقه، بدون تغییر ساعت تابستانی).
  static const Duration tehranOffset = Duration(hours: 3, minutes: 30);

  /// تبدیل هر لحظه زمانی به ساعت و تاریخ رسمی تهران.
  static DateTime toTehran(DateTime time) => time.toUtc().add(tehranOffset);

  /// لحظه فعلی به وقت رسمی تهران.
  static DateTime nowTehran() => DateTime.now().toUtc().add(tehranOffset);

  /// خواندن دقیق تاریخ و زمان سرور یا پنل با رعایت منطقه زمانی رسمی تهران.
  static DateTime? parseServerDateTime(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value.year < 2000 ? null : value;
    }
    if (value is NumericValue) {
      if (value <= 0) {
        return null;
      }
      final int ms =
          value > 2000000000000 ? value.round() : (value * 1000).round();
      final DateTime dt = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
      return dt.year < 2000 ? null : dt;
    }
    final String raw = toEn(value.toString()).trim();
    if (raw.isEmpty ||
        raw.startsWith('0000') ||
        raw.startsWith('0001') ||
        raw.toLowerCase() == 'null' ||
        raw.toLowerCase() == 'none') {
      return null;
    }
    final int? epoch = int.tryParse(raw);
    if (epoch != null) {
      return parseServerDateTime(epoch);
    }
    final RegExpMatch? dateOnly =
        RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
    if (dateOnly != null) {
      final int y = int.parse(dateOnly.group(1)!);
      if (y < 2000) {
        return null;
      }
      final int m = int.parse(dateOnly.group(2)!);
      final int d = int.parse(dateOnly.group(3)!);
      return DateTime.utc(y, m, d).subtract(tehranOffset);
    }
    final RegExpMatch? naive = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,6}))?)?$',
    ).firstMatch(raw);
    if (naive != null) {
      final int y = int.parse(naive.group(1)!);
      if (y < 2000) {
        return null;
      }
      final int m = int.parse(naive.group(2)!);
      final int d = int.parse(naive.group(3)!);
      final int hh = int.parse(naive.group(4)!);
      final int mm = int.parse(naive.group(5)!);
      final int ss = int.parse(naive.group(6) ?? '0');
      final String frac = naive.group(7) ?? '';
      final int us =
          frac.isEmpty ? 0 : int.parse(frac.padRight(6, '0').substring(0, 6));
      return DateTime.utc(y, m, d, hh, mm, ss, 0, us).subtract(tehranOffset);
    }
    final DateTime? parsed = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    if (parsed == null || parsed.year < 2000) {
      return null;
    }
    return parsed.toUtc();
  }

  /// تاریخ شمسی به وقت رسمی تهران: ۱۴۰۵/۰۸/۲۶.
  static String tehranDate(DateTime? time) {
    if (time == null) {
      return 'ثبت نشده';
    }
    return date(toTehran(time));
  }

  /// تاریخ کامل شمسی با روز هفته به وقت تهران: سه شنبه ۲۶ آبان ۱۴۰۵.
  static String tehranFullDate(DateTime? time) {
    if (time == null) {
      return 'ثبت نشده';
    }
    return fullDate(toTehran(time));
  }

  /// ساعت دقیق به وقت تهران با ارقام فارسی: ۲۱:۲۰:۳۱ یا ۲۱:۲۰.
  static String tehranClock(DateTime? time, {bool seconds = true}) {
    if (time == null) {
      return 'ثبت نشده';
    }
    final DateTime t = toTehran(time);
    final String h = t.hour.toString().padLeft(2, '0');
    final String m = t.minute.toString().padLeft(2, '0');
    if (!seconds) {
      return num('$h:$m');
    }
    final String s = t.second.toString().padLeft(2, '0');
    return num('$h:$m:$s');
  }

  /// تاریخ کامل شمسی و ساعت دقیق به وقت تهران: سه شنبه ۲۶ آبان ۱۴۰۵ • ساعت ۲۱:۲۰:۳۱.
  static String tehranFullDateTime(DateTime? time, {bool seconds = true}) {
    if (time == null) {
      return 'ثبت نشده';
    }
    final DateTime t = toTehran(time);
    return '${fullDate(t)} • ساعت ${tehranClock(time, seconds: seconds)}';
  }

  /// تاریخ شمسی فشرده و ساعت به وقت تهران: ۱۴۰۵/۰۸/۲۶ • ساعت ۲۱:۲۰.
  static String tehranCompactDateTime(DateTime? time, {bool seconds = false}) {
    if (time == null) {
      return 'ثبت نشده';
    }
    final DateTime t = toTehran(time);
    return '${date(t)} • ساعت ${tehranClock(time, seconds: seconds)}';
  }

  /// بازه زمانی خوانا و کاملاً فارسی: «۲۵۸ روز و ۲ ساعت و ۳۹ دقیقه».
  static String spanFa(
    Duration value, {
    bool includeMinutes = true,
    bool includeSeconds = false,
  }) {
    if (value.isNegative || value.inSeconds <= 0) {
      return 'پایان یافته';
    }
    if (value.inSeconds < 60 && !includeSeconds) {
      return 'کمتر از یک دقیقه';
    }
    final int d = value.inDays;
    final int h = value.inHours.remainder(24);
    final int m = value.inMinutes.remainder(60);
    final int s = value.inSeconds.remainder(60);
    final List<String> parts = <String>[];
    if (d > 0) {
      parts.add('${grouped(d)} روز');
    }
    if (h > 0) {
      parts.add('${num(h)} ساعت');
    }
    if (includeMinutes && m > 0 && parts.length < 3) {
      parts.add('${num(m)} دقیقه');
    }
    if (includeSeconds && d == 0 && h == 0 && s > 0) {
      parts.add('${num(s)} ثانیه');
    }
    if (parts.isEmpty) {
      return 'کمتر از یک دقیقه';
    }
    return parts.join(' و ');
  }

  /// عنوان خوانای مدت بسته به فارسی.
  static String packageTitleFa(int packageDays) {
    if (packageDays <= 0) {
      return 'نامحدود زمانی';
    }
    if (packageDays == 365 || packageDays == 366) {
      return 'یک ساله (${grouped(packageDays)} روز)';
    }
    if (packageDays == 180) {
      return 'شش ماهه (${num(180)} روز)';
    }
    if (packageDays == 90) {
      return 'سه ماهه (${num(90)} روز)';
    }
    if (packageDays == 60) {
      return 'دو ماهه (${num(60)} روز)';
    }
    if (packageDays == 30 || packageDays == 31) {
      return 'یک ماهه (${num(packageDays)} روز)';
    }
    if (packageDays == 7) {
      return 'هفتگی (${num(7)} روز)';
    }
    return 'بسته ${grouped(packageDays)} روزه';
  }

  /// نمایش خوش خوان شماره همراه با ارقام فارسی.
  static String phoneFa(String raw) {
    final String clean =
        toEn(raw).replaceAll(RegExp(r'[^0-9+]'), '').trim();
    if (clean.isEmpty) {
      return 'ثبت نشده';
    }
    String normalized = clean;
    if (normalized.startsWith('+98') && normalized.length == 13) {
      normalized = '0${normalized.substring(3)}';
    } else if (normalized.startsWith('0098') && normalized.length == 14) {
      normalized = '0${normalized.substring(4)}';
    } else if (normalized.startsWith('98') && normalized.length == 12) {
      normalized = '0${normalized.substring(2)}';
    } else if (normalized.startsWith('9') && normalized.length == 10) {
      normalized = '0$normalized';
    }
    if (normalized.length == 11 && normalized.startsWith('09')) {
      return num(
        '${normalized.substring(0, 4)}-'
        '${normalized.substring(4, 7)}-'
        '${normalized.substring(7)}',
      );
    }
    return num(clean);
  }

  static String relative(DateTime? time, {DateTime? now}) {
    if (time == null) {
      return 'ثبت نشده';
    }
    final DateTime ref = (now ?? DateTime.now()).toUtc();
    final Duration diff = ref.difference(time.toUtc());
    if (diff.inSeconds < 60) {
      return 'همین حالا';
    }
    if (diff.inMinutes < 60) {
      return '${num(diff.inMinutes)} دقیقه پیش';
    }
    if (diff.inHours < 24) {
      final int hours = diff.inHours;
      final int mins = diff.inMinutes.remainder(60);
      if (mins == 0) {
        return '${num(hours)} ساعت پیش';
      }
      return '${num(hours)} ساعت و ${num(mins)} دقیقه پیش';
    }
    if (diff.inDays < 31) {
      return '${num(diff.inDays)} روز پیش';
    }
    if (diff.inDays < 365) {
      final int monthsAgo = diff.inDays ~/ 30;
      return '${num(monthsAgo)} ماه پیش';
    }
    return tehranDate(time);
  }

  /// تاریخ شمسی امروز به شکل رشته ۱۴۰۴/۰۸/۲۰.
  static String today() => date(DateTime.now());

  /// روز هفته شمسی: «یکشنبه».
  ///
  /// `DateTime.weekday` دوشنبه را ۱ و یکشنبه را ۷ می دهد، و فهرست [weekDays]
  /// هم از دوشنبه شروع می شود، پس اندیس همان `weekday - 1` است.
  static String weekDay(DateTime time) => weekDays[(time.weekday - 1) % 7];

  /// تاریخ کامل با روز هفته: «یکشنبه ۲۴ آذر ۱۴۰۵».
  static String fullDate(DateTime time) =>
      '${weekDay(time)} ${longDate(time)}';

  /// یک خط کامل تاریخ و ساعت زنده: «یکشنبه ۲۴ آذر ۱۴۰۵ — ۱۲:۳۶:۰۱».
  static String fullDateTime(DateTime time) =>
      '${fullDate(time)} — ${clock(time)}';

  /// سلام مناسب ساعت روز.
  ///
  /// پیش از این همیشه «سلام» نوشته می شد؛ کاربر خواست صبح بخیر، ظهر بخیر و
  /// شب بخیر با همان سلام اول باشد.
  static String greeting([DateTime? now]) {
    final int hour = (now ?? DateTime.now()).hour;
    if (hour >= 5 && hour < 12) {
      return 'صبح بخیر';
    }
    if (hour >= 12 && hour < 15) {
      return 'ظهر بخیر';
    }
    if (hour >= 15 && hour < 19) {
      return 'عصر بخیر';
    }
    return 'شب بخیر';
  }

  /// آیکون مناسب همان سلام، تا متن و آیکون با هم بخوانند.
  static String greetingKey([DateTime? now]) {
    final int hour = (now ?? DateTime.now()).hour;
    if (hour >= 5 && hour < 12) {
      return 'morning';
    }
    if (hour >= 12 && hour < 15) {
      return 'noon';
    }
    if (hour >= 15 && hour < 19) {
      return 'evening';
    }
    return 'night';
  }

  static JalaliDate jalali(DateTime time) => JalaliDate.fromDateTime(time);
}

/// تبدیل دقیق دوطرفه تاریخ میلادی و هجری شمسی با پشتیبانی کامل سال های کبیسه.
class JalaliDate {
  const JalaliDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  /// تشخیص دقیق سال کبیسه هجری شمسی (چرخه ۳۳ ساله استاندارد).
  static bool isLeap(int jy) {
    final int a = jy + 1595;
    final int next = a + 1;
    final int d1 = (a ~/ 33) * 8 + (((a % 33) + 3) ~/ 4);
    final int d2 = (next ~/ 33) * 8 + (((next % 33) + 3) ~/ 4);
    return d2 > d1;
  }

  bool get isLeapYear => isLeap(year);

  /// فصل سال هجری شمسی به فارسی.
  String get seasonFa {
    if (month <= 3) {
      return 'بهار';
    }
    if (month <= 6) {
      return 'تابستان';
    }
    if (month <= 9) {
      return 'پاییز';
    }
    return 'زمستان';
  }

  /// شماره روز در سال هجری شمسی (۱ تا ۳۶۵ یا ۳۶۶ در سال کبیسه).
  int get dayOfYear =>
      (month <= 6 ? (month - 1) * 31 : 186 + (month - 7) * 30) + day;

  /// تعداد کل روزهای این سال هجری شمسی (۳۶۶ در کبیسه، ۳۶۵ در سال عادی).
  int get yearLength => isLeapYear ? 366 : 365;

  int get monthLength {
    if (month <= 6) {
      return 31;
    }
    if (month <= 11) {
      return 30;
    }
    return isLeapYear ? 30 : 29;
  }

  factory JalaliDate.fromDateTime(DateTime time) {
    final int gy = time.year;
    final int gm = time.month;
    final int gd = time.day;
    const List<int> gDaysBeforeMonth = <int>[
      0,
      31,
      59,
      90,
      120,
      151,
      181,
      212,
      243,
      273,
      304,
      334,
    ];
    final int gy2 = (gm > 2) ? (gy + 1) : gy;
    int days = 355666 +
        (365 * gy) +
        ((gy2 + 3) ~/ 4) -
        ((gy2 + 99) ~/ 100) +
        ((gy2 + 399) ~/ 400) +
        gd +
        gDaysBeforeMonth[gm - 1];
    int jy = -1595 + (33 * (days ~/ 12053));
    days %= 12053;
    jy += 4 * (days ~/ 1461);
    days %= 1461;
    if (days > 365) {
      jy += (days - 1) ~/ 365;
      days = (days - 1) % 365;
    }
    final int jm;
    final int jd;
    if (days < 186) {
      jm = 1 + (days ~/ 31);
      jd = 1 + (days % 31);
    } else {
      jm = 7 + ((days - 186) ~/ 30);
      jd = 1 + ((days - 186) % 30);
    }
    return JalaliDate(jy, jm, jd);
  }

  /// تبدیل معکوس تاریخ شمسی به میلادی (UTC).
  DateTime toUtcDate() {
    final int jy = year + 1595;
    int days = -355668 +
        (365 * jy) +
        ((jy ~/ 33) * 8) +
        (((jy % 33) + 3) ~/ 4) +
        day +
        (month < 7 ? (month - 1) * 31 : ((month - 7) * 30) + 186);
    int gy = 400 * (days ~/ 146097);
    days %= 146097;
    if (days > 36524) {
      days--;
      gy += 100 * (days ~/ 36524);
      days %= 36524;
      if (days >= 365) {
        days++;
      }
    }
    gy += 4 * (days ~/ 1461);
    days %= 1461;
    if (days > 365) {
      gy += (days - 1) ~/ 365;
      days = (days - 1) % 365;
    }
    int gd = days + 1;
    final bool gLeap = (gy % 4 == 0 && gy % 100 != 0) || (gy % 400 == 0);
    final List<int> monthDays = <int>[
      0,
      31,
      gLeap ? 29 : 28,
      31,
      30,
      31,
      30,
      31,
      31,
      30,
      31,
      30,
      31,
    ];
    int gm = 1;
    while (gm <= 12 && gd > monthDays[gm]) {
      gd -= monthDays[gm];
      gm++;
    }
    return DateTime.utc(gy, gm, gd);
  }

  @override
  String toString() => '$year/$month/$day';
}
