/// ابزارهای فارسی سازی: ارقام، تاریخ شمسی، حجم، سرعت و مدت زمان.
///
/// همه متن های برنامه فارسی و بدون نیم فاصله هستند و همه ارقام با این فایل
/// به شکل فارسی نمایش داده می شوند.
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

  /// تبدیل ارقام لاتین یک متن به فارسی.
  static String num(Object? value) {
    final String text = (value ?? '').toString();
    final StringBuffer buffer = StringBuffer();
    for (final int rune in text.runes) {
      if (rune >= 48 && rune <= 57) {
        buffer.write(digits[rune - 48]);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
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

  static String relative(DateTime? time) {
    if (time == null) {
      return 'نامشخص';
    }
    final Duration diff = DateTime.now().difference(time);
    if (diff.inSeconds < 45) {
      return 'همین حالا';
    }
    if (diff.inMinutes < 60) {
      return '${num(diff.inMinutes)} دقیقه پیش';
    }
    if (diff.inHours < 24) {
      return '${num(diff.inHours)} ساعت پیش';
    }
    if (diff.inDays < 31) {
      return '${num(diff.inDays)} روز پیش';
    }
    return date(time);
  }

  /// تاریخ شمسی امروز به شکل رشته ۱۴۰۴/۰۸/۲۰.
  static String today() => date(DateTime.now());

  static JalaliDate jalali(DateTime time) => JalaliDate.fromDateTime(time);
}

/// تبدیل تاریخ میلادی به شمسی (الگوریتم استاندارد، بدون کتابخانه بیرونی).
class JalaliDate {
  const JalaliDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  factory JalaliDate.fromDateTime(DateTime time) {
    final int gy = time.year;
    final int gm = time.month;
    final int gd = time.day;
    const List<int> gDaysInMonth = <int>[
      31,
      28,
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
    const List<int> jDaysInMonth = <int>[
      31,
      31,
      31,
      31,
      31,
      31,
      30,
      30,
      30,
      30,
      30,
      29,
    ];
    int gy2 = (gm > 2) ? (gy + 1) : gy;
    int days = 355666 +
        (365 * gy) +
        ((gy2 + 3) ~/ 4) -
        ((gy2 + 99) ~/ 100) +
        ((gy2 + 399) ~/ 400) +
        gd +
        _sum(gDaysInMonth, gm - 1);
    int jy = -1595 + (33 * (days ~/ 12053));
    days %= 12053;
    jy += 4 * (days ~/ 1461);
    days %= 1461;
    if (days > 365) {
      jy += (days - 1) ~/ 365;
      days = (days - 1) % 365;
    }
    int jm;
    int jd;
    if (days < 186) {
      jm = 1 + (days ~/ 31);
      jd = 1 + (days % 31);
    } else {
      jm = 7 + ((days - 186) ~/ 30);
      jd = 1 + ((days - 186) % 30);
    }
    // clamp against the actual month lengths (leap years)
    if (jm >= 1 && jm <= 12 && jd > jDaysInMonth[jm - 1]) {
      jd = jDaysInMonth[jm - 1];
    }
    return JalaliDate(jy, jm, jd);
  }

  static int _sum(List<int> values, int count) {
    int total = 0;
    for (int i = 0; i < count && i < values.length; i++) {
      total += values[i];
    }
    return total;
  }

  @override
  String toString() => '$year/$month/$day';
}
