import 'package:flutter/material.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';

/// پرچم کشورها به صورت تصویر واقعی (assets/flags/<code>.png) با نام فارسی.
class FlagView extends StatelessWidget {
  const FlagView({
    super.key,
    required this.code,
    this.width = 34,
    this.radius = 6,
  });

  final String code;
  final double width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final String normalized = code.trim().toLowerCase();
    if (normalized.length != 2) {
      return SizedBox(width: width, height: width * 0.72);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: width,
        height: width * 0.72,
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Image.asset(
          'assets/flags/$normalized.png',
          fit: BoxFit.cover,
          errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
              Center(
            child: Text(
              normalized.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
      ),
    );
  }
}

/// پرچم به همراه نام کشور به فارسی.
class FlagLabel extends StatelessWidget {
  const FlagLabel({
    super.key,
    required this.code,
    this.showName = true,
    this.width = 30,
  });

  final String code;
  final bool showName;
  final double width;

  @override
  Widget build(BuildContext context) {
    final String name = CountryNames.fa(code);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        FlagView(code: code, width: width),
        if (showName && name.isNotEmpty) ...<Widget>[
          const SizedBox(width: 8),
          Text(
            Fa.num(name),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

/// نام فارسی کشورها برای نمایش کنار پرچم.
class CountryNames {
  const CountryNames._();

  static String fa(String code) {
    final String key = code.trim().toLowerCase();
    return _names[key] ?? (key.isEmpty ? '' : key.toUpperCase());
  }

  static const Map<String, String> _names = <String, String>{
    'ad': 'آندورا',
    'ae': 'امارات',
    'af': 'افغانستان',
    'al': 'آلبانی',
    'am': 'ارمنستان',
    'ar': 'آرژانتین',
    'at': 'اتریش',
    'au': 'استرالیا',
    'az': 'آذربایجان',
    'ba': 'بوسنی',
    'bd': 'بنگلادش',
    'be': 'بلژیک',
    'bg': 'بلغارستان',
    'bh': 'بحرین',
    'bn': 'برونئی',
    'br': 'برزیل',
    'by': 'بلاروس',
    'ca': 'کانادا',
    'ch': 'سوئیس',
    'cl': 'شیلی',
    'cn': 'چین',
    'cy': 'قبرس',
    'cz': 'چک',
    'de': 'آلمان',
    'dk': 'دانمارک',
    'dz': 'الجزایر',
    'ee': 'استونی',
    'eg': 'مصر',
    'es': 'اسپانیا',
    'fi': 'فنلاند',
    'fr': 'فرانسه',
    'gb': 'بریتانیا',
    'ge': 'گرجستان',
    'gr': 'یونان',
    'hk': 'هنگ کنگ',
    'hr': 'کرواسی',
    'hu': 'مجارستان',
    'id': 'اندونزی',
    'ie': 'ایرلند',
    'il': 'اسرائیل',
    'in': 'هند',
    'iq': 'عراق',
    'ir': 'ایران',
    'is': 'ایسلند',
    'it': 'ایتالیا',
    'jo': 'اردن',
    'jp': 'ژاپن',
    'ke': 'کنیا',
    'kg': 'قرقیزستان',
    'kh': 'کامبوج',
    'kr': 'کره جنوبی',
    'kw': 'کویت',
    'kz': 'قزاقستان',
    'la': 'لائوس',
    'lb': 'لبنان',
    'lk': 'سریلانکا',
    'lt': 'لیتوانی',
    'lu': 'لوکزامبورگ',
    'lv': 'لتونی',
    'ma': 'مراکش',
    'md': 'مولداوی',
    'me': 'مونته نگرو',
    'mk': 'مقدونیه',
    'mm': 'میانمار',
    'mn': 'مغولستان',
    'mx': 'مکزیک',
    'my': 'مالزی',
    'ng': 'نیجریه',
    'nl': 'هلند',
    'no': 'نروژ',
    'np': 'نپال',
    'nz': 'زلاندنو',
    'om': 'عمان',
    'ph': 'فیلیپین',
    'pk': 'پاکستان',
    'pl': 'لهستان',
    'pt': 'پرتغال',
    'qa': 'قطر',
    'ro': 'رومانی',
    'rs': 'صربستان',
    'ru': 'روسیه',
    'sa': 'عربستان',
    'se': 'سوئد',
    'sg': 'سنگاپور',
    'si': 'اسلوونی',
    'sk': 'اسلواکی',
    'th': 'تایلند',
    'tj': 'تاجیکستان',
    'tm': 'ترکمنستان',
    'tr': 'ترکیه',
    'tw': 'تایوان',
    'tz': 'تانزانیا',
    'ua': 'اوکراین',
    'us': 'آمریکا',
    'uy': 'اروگوئه',
    'uz': 'ازبکستان',
    'vn': 'ویتنام',
    'xk': 'کوزوو',
    'za': 'آفریقای جنوبی',
  };
}
