import 'dart:convert';
import 'dart:math' as math;

/// نتیجه شناسایی یک نشانی، دامنه یا فایل پیوند مخرب پیش از باز شدن.
class MaliciousLinkMatch {
  const MaliciousLinkMatch({
    required this.key,
    required this.host,
    required this.target,
    required this.title,
    required this.detail,
    required this.severity,
    this.riskScore = 0,
  });

  final String key;
  final String host;
  final String target;
  final String title;
  final String detail;
  final String severity;
  final int riskScore;
}

/// سپر هوشمند بازرسی نشانی ها و دامنه ها (الگوهای امنیتی ۲۰۲۶):
///
/// پیش از باز شدن هر لینک در مرورگر یا ثبت ارتباط شبکه ای:
/// ۱. پروتکل های مخرب و ClickFix / Fileless (`javascript:`, `mshta:`, `data:`, `blob:`, ...)
/// ۲. جعل پسوند با RLO و فریب `@` Userinfo Spoofing
/// ۳. دیکدر واقعی Punycode (RFC 3492) + تشخیص هموگراف سیریلیک/یونانی و Mixed-Script
/// ۴. تشخیص آی پی مبهم (Decimal / Hex / Octal / Mapped IPv6) و پورت های C2/RAT
/// ۵. جعل برند در ساب دامین، Combosquatting و Typosquatting (فاصله ویرایشی Damerau-Levenshtein)
/// ۶. بازرسی بازگشتی پارامترهای Open-Redirect و Payload های Base64 پنهان در Query/Fragment
/// ۷. امتیازدهی ریسک ساختاریافته (آنتروپی شانون DGA، چگالی عدد، TLD پرریسک و دامنه های مخرب)
class MaliciousLinkGuard {
  const MaliciousLinkGuard._();

  /// دامین های تله آی پی، ردیابی پنهان، تله لینک و فیشینگ شناخته شده.
  static const List<String> knownMaliciousDomains = <String>[
    'grabify.link',
    'iplogger.org',
    '2no.co',
    'yip.su',
    'blasze.tk',
    'blasze.com',
    'ps3cfw.com',
    'bmwforum.co',
    'bucks.as',
    'stopify.co',
    'leancoding.co',
    'spottyfly.com',
    'youshouldclick.us',
    'yoütu.be',
    'iplogger.com',
    'iplogger.ru',
    'iplogger.co',
    'ezstat.ru',
    'lovebird.guru',
    'trulove.guru',
    'dateing.club',
    'otherhalf.life',
    'shrekis.life',
    'datasig.io',
    'datauth.io',
    'headshot.monster',
    'gaming-at-my.best',
    'progaming.monster',
    'yourmy.monster',
    'screenshare.host',
    'imageshare.best',
    'screenshot.best',
    'gamingfun.me',
    'catsnthing.com',
    'mypic.icu',
    'curiouscat.club',
    'joinmy.site',
    'fortnitechat.site',
    'fortnight.space',
    'freegiftcards.co',
    'canarytokens.com',
    'webhook.site',
    'requestbin.com',
    'oastify.com',
    'interactsh.com',
    'burpcollaborator.net',
  ];

  /// کوتاه کننده های پرکاربرد که باید قبل از بازشدن، مسیر تغییرجهتشان بازرسی شود.
  static const Set<String> shortenerDomains = <String>{
    'bit.ly',
    'tinyurl.com',
    't.co',
    'is.gd',
    'v.gd',
    'cutt.ly',
    'rb.gy',
    'shorturl.at',
    'rebrand.ly',
    'ow.ly',
    'goo.gl',
    'tiny.cc',
    'shrtco.de',
    'clck.ru',
    'yun.ir',
    'b2n.ir',
    'zil.ink',
    'u.nu',
    't2m.io',
  };

  /// پسوندهای دامنه پرخطر با سوءاستفاده بالا در کمپین های فیشینگ و بدافزار ۲۰۲۶.
  static const Set<String> _highRiskTlds = <String>{
    'tk',
    'ml',
    'ga',
    'cf',
    'gq',
    'top',
    'xyz',
    'click',
    'loan',
    'zip',
    'mov',
    'icu',
    'work',
    'buzz',
    'rest',
    'cfd',
    'sbs',
    'lat',
    'cam',
    'quest',
    'monster',
    'cyou',
    'cfd',
    'beauty',
    'skin',
  };

  /// دامین های رسمی تاییدشده برای جلوگیری از خطای مثبت (False Positive).
  static const List<String> _trustedHostSuffixes = <String>[
    'armin-soft.ir',
    'umbrellavpn.ir',
    'umbrella-vpn.example',
    'github.com',
    'githubusercontent.com',
    'github.io',
    'telegram.org',
    't.me',
    'telegra.ph',
    'telesco.pe',
    'tdesktop.com',
    'whatsapp.com',
    'wa.me',
    'whatsapp.net',
    'instagram.com',
    'ig.me',
    'google.com',
    'googleapis.com',
    'googleusercontent.com',
    'googlevideo.com',
    'youtube.com',
    'youtu.be',
    'gmail.com',
    'apple.com',
    'icloud.com',
    'microsoft.com',
    'live.com',
    'outlook.com',
    'office.com',
    'microsoftonline.com',
    'azure.com',
    'paypal.com',
    'paypal.me',
    'binance.com',
    'bnbstatic.com',
    'nobitex.ir',
    'nobitex.net',
    'shaparak.ir',
    'bankmellat.ir',
    'bsi.ir',
    'bmi.ir',
    'bpi.ir',
    'pep.co.ir',
    'tejaratbank.ir',
    'refah-bank.ir',
    'digikala.com',
    'snapp.ir',
    'snapp.market',
    'divar.ir',
    'cloudflare.com',
    'speedtest.net',
  ];

  /// نگاشت برندهای هدف فیشینگ به دامین های رسمی خودشان برای بررسی دقیق.
  static const Map<String, List<String>> _brandOfficialDomains =
      <String, List<String>>{
    'telegram': <String>['telegram.org', 't.me', 'telegra.ph', 'telesco.pe', 'tdesktop.com'],
    'whatsapp': <String>['whatsapp.com', 'wa.me', 'whatsapp.net'],
    'instagram': <String>['instagram.com', 'ig.me'],
    'google': <String>['google.com', 'googleapis.com', 'googleusercontent.com', 'googlevideo.com', 'gmail.com', 'youtube.com'],
    'apple': <String>['apple.com', 'icloud.com'],
    'microsoft': <String>['microsoft.com', 'live.com', 'outlook.com', 'office.com', 'microsoftonline.com', 'azure.com', 'github.com'],
    'paypal': <String>['paypal.com', 'paypal.me'],
    'binance': <String>['binance.com', 'bnbstatic.com'],
    'nobitex': <String>['nobitex.ir', 'nobitex.net'],
    'shaparak': <String>['shaparak.ir'],
    'mellat': <String>['bankmellat.ir', 'mellat.ir', 'shaparak.ir'],
    'saderat': <String>['bsi.ir'],
    'pasargad': <String>['bpi.ir', 'pep.co.ir'],
    'tejarat': <String>['tejaratbank.ir'],
    'digikala': <String>['digikala.com'],
    'snapp': <String>['snapp.ir', 'snapp.market'],
    'divar': <String>['divar.ir'],
    'umbrella': <String>['armin-soft.ir', 'umbrellavpn.ir', 'umbrella-vpn.example'],
  };

  /// برندهای با طول حداقل ۶ حرف که برای تشخیص typosquatting فاصله ویرایشی ۱ بررسی می شوند.
  static const List<String> _typoTargetBrands = <String>[
    'telegram',
    'whatsapp',
    'instagram',
    'google',
    'microsoft',
    'paypal',
    'binance',
    'nobitex',
    'shaparak',
    'mellat',
    'pasargad',
    'digikala',
    'umbrella',
  ];

  /// واژگان مجاز لغوی که نباید به اشتباه با برندهای مشابه به عنوان typosquatting برچسب بخورند.
  static const Set<String> _benignDictionaryWords = <String>{
    'goggle',
    'goggles',
    'snappy',
    'apple',
    'apples',
    'diver',
    'divar',
    'melat',
  };

  static const List<String> _phishingPrefixes = <String>[
    'telegram-verify',
    'telegram-support',
    'telegram-login',
    'telegram-gift',
    'telegram-stars',
    't-me-verify',
    'shaparak-pay',
    'mellat-ebank',
    'saderat-online',
    'umbrella-verify',
    'umbrella-gift',
    'umbrella-crack',
    'free-telegram-premium',
    'claim-ton',
    'airdrop-ton',
    'wallet-verify',
    'wallet-connect-fix',
  ];

  /// عبارات فریبنده که در کنار نام یک برند معتبر در دامنه غیررسمی نشانه فیشینگ هستند.
  static const List<String> _phishingIntentTokens = <String>[
    'login',
    'signin',
    'verify',
    'confirm',
    'auth',
    'account',
    'wallet',
    'recover',
    'unlock',
    'security',
    'alert',
    'update',
    'support',
    'gift',
    'stars',
    'premium',
    'airdrop',
    'claim',
    'bonus',
    'ebank',
    'ebanking',
    'payment',
    'gateway',
    'portal',
    'panel',
    'secure',
    'official',
    'captcha',
    'token',
    'crack',
    'mod',
  ];

  static const List<String> _credentialPathKeywords = <String>[
    'login',
    'signin',
    'verify',
    'password',
    'passwd',
    'otp',
    'cvv2',
    'pin2',
    'wallet',
    'seed',
    'mnemonic',
    'phrase',
    'claim',
    'airdrop',
    'webmail',
    'banking',
    'auth',
  ];

  /// درگاه های نامتعارف C2/RAT که روی IP یا دامنه پرخطر مشکوک محسوب می شوند.
  static const Set<int> _suspiciousC2Ports = <int>{
    1337,
    2222,
    3333,
    4444,
    4445,
    5555,
    6666,
    7777,
    8081,
    8282,
    8444,
    9001,
    9999,
    12345,
    31337,
  };

  /// کلیدهای پارامتر Query که غالباً برای حمله Open Redirect یا تغییرجهت پنهان استفاده می شوند.
  static const Set<String> _redirectParamKeys = <String>{
    'url',
    'u',
    'redirect',
    'redirect_url',
    'redirect_uri',
    'redir',
    'next',
    'target',
    'dest',
    'destination',
    'continue',
    'return',
    'return_to',
    'returnto',
    'callback',
    'goto',
    'out',
    'q',
    'to',
  };

  /// در دسترس برای همگام سازی قوانین هسته.
  static List<String> get phishingPhrases => _phishingPrefixes;

  static const List<String> _dangerExeExts = <String>[
    '.apk',
    '.exe',
    '.scr',
    '.pif',
    '.com',
    '.bat',
    '.cmd',
    '.vbs',
    '.vbe',
    '.js',
    '.jse',
    '.wsf',
    '.wsh',
    '.ps1',
    '.hta',
    '.msi',
  ];

  static const List<String> _decoyExts = <String>[
    '.jpg.',
    '.jpeg.',
    '.png.',
    '.gif.',
    '.webp.',
    '.pdf.',
    '.doc.',
    '.docx.',
    '.xls.',
    '.xlsx.',
    '.mp3.',
    '.mp4.',
    '.txt.',
  ];

  /// نگاشت هموگراف های سیریلیک، یونانی و کاراکترهای شبه همسان به معادل لاتین.
  static const Map<int, String> _homoglyphMap = <int, String>{
    // Cyrillic lowercase & uppercase
    0x0430: 'a', 0x0410: 'a', // а / А
    0x0432: 'b', 0x0412: 'b', // в / В
    0x0435: 'e', 0x0415: 'e', // е / Е
    0x0451: 'e', 0x0401: 'e', // ё / Ё
    0x0454: 'e', 0x0404: 'e', // є / Є
    0x043A: 'k', 0x041A: 'k', // к / К
    0x043C: 'm', 0x041C: 'm', // м / М
    0x043D: 'h', 0x041D: 'h', // н / Н
    0x043E: 'o', 0x041E: 'o', // о / О
    0x0440: 'p', 0x0420: 'p', // р / Р
    0x0441: 'c', 0x0421: 'c', // с / С
    0x0442: 't', 0x0422: 't', // т / Т
    0x0443: 'y', 0x0423: 'y', // у / У
    0x0445: 'x', 0x0425: 'x', // х / Х
    0x0456: 'i', 0x0406: 'i', // і / І
    0x0457: 'i', 0x0407: 'i', // ї / Ї
    0x0458: 'j', 0x0408: 'j', // ј / Ј
    0x0455: 's', 0x0405: 's', // ѕ / Ѕ
    0x04C0: 'l', 0x04CF: 'l', // Ӏ / ӏ
    0x0501: 'd', 0x0500: 'd', // ԁ / Ԁ
    0x051B: 'q', 0x051A: 'q', // ԛ / Ԛ
    0x051D: 'w', 0x051C: 'w', // ԝ / Ԝ
    0x04E9: 'o', 0x04E8: 'o', // ө / Ө
    // Greek lookalikes
    0x03B1: 'a', 0x0391: 'a', // α / Α
    0x03B2: 'b', 0x0392: 'b', // β / Β
    0x03B5: 'e', 0x0395: 'e', // ε / Ε
    0x03B6: 'z', 0x0396: 'z', // ζ / Ζ
    0x03B7: 'n', 0x0397: 'h', // η / Η
    0x03B9: 'i', 0x0399: 'i', // ι / Ι
    0x03BA: 'k', 0x039A: 'k', // κ / Κ
    0x03BC: 'm', 0x039C: 'm', // μ / Μ
    0x03BD: 'v', 0x039D: 'n', // ν / Ν
    0x03BF: 'o', 0x039F: 'o', // ο / Ο
    0x03C1: 'p', 0x03A1: 'p', // ρ / Ρ
    0x03C2: 'c', 0x03C3: 'o', // ς / σ
    0x03C4: 't', 0x03A4: 't', // τ / Τ
    0x03C5: 'u', 0x03A5: 'y', // υ / Υ
    0x03C7: 'x', 0x03A7: 'x', // χ / Χ
    // Turkish & Latin extended confusables
    0x0131: 'i', // ı
    0x0130: 'i', // İ
    0x00E0: 'a', 0x00E1: 'a', 0x00E2: 'a', 0x00E3: 'a', 0x00E4: 'a', 0x00E5: 'a',
    0x00E7: 'c',
    0x00E8: 'e', 0x00E9: 'e', 0x00EA: 'e', 0x00EB: 'e',
    0x00EC: 'i', 0x00ED: 'i', 0x00EE: 'i', 0x00EF: 'i',
    0x00F1: 'n',
    0x00F2: 'o', 0x00F3: 'o', 0x00F4: 'o', 0x00F5: 'o', 0x00F6: 'o',
    0x00F9: 'u', 0x00FA: 'u', 0x00FB: 'u', 0x00FC: 'u',
    0x00FD: 'y', 0x00FF: 'y',
    0x011F: 'g', 0x015F: 's',
  };

  static bool _isTrustedHost(String host) {
    final String h = host.toLowerCase();
    for (final String trusted in _trustedHostSuffixes) {
      if (h == trusted || h.endsWith('.$trusted')) {
        return true;
      }
    }
    return false;
  }

  static bool _isLoopbackHost(String host) {
    final String h = host.toLowerCase().replaceAll('[', '').replaceAll(']', '');
    return h == '127.0.0.1' || h == 'localhost' || h == '::1';
  }

  /// بررسی می کند آیا هاست یک سرویس کوتاه کننده لینک است یا نه.
  static bool isShortenerHost(String rawHost) {
    final String host = _normalizeHost(rawHost);
    if (host.isEmpty) {
      return false;
    }
    for (final String s in shortenerDomains) {
      if (host == s || host.endsWith('.$s')) {
        return true;
      }
    }
    return false;
  }

  static String _normalizeHost(String rawHost) {
    String h = rawHost.trim().toLowerCase();
    if (h.startsWith('[') && h.contains(']')) {
      final int end = h.indexOf(']');
      return h.substring(0, end + 1);
    }
    if (h.contains(':')) {
      h = h.split(':').first;
    }
    while (h.endsWith('.')) {
      h = h.substring(0, h.length - 1);
    }
    return h;
  }

  /// دیکدر استاندارد RFC 3492 (Punycode) برای برچسب های `xn--...`.
  static String? _decodePunycodeLabel(String label) {
    final String lower = label.toLowerCase();
    if (!lower.startsWith('xn--')) {
      return lower;
    }
    final String input = lower.substring(4);
    if (input.isEmpty) {
      return null;
    }
    const int base = 36;
    const int tMin = 1;
    const int tMax = 26;
    const int skew = 38;
    const int damp = 700;
    const int initialBias = 72;
    const int initialN = 128;

    final List<int> output = <int>[];
    final int basicEnd = input.lastIndexOf('-');
    int pos = 0;
    if (basicEnd >= 0) {
      for (int j = 0; j < basicEnd; j++) {
        final int cp = input.codeUnitAt(j);
        if (cp >= 0x80) {
          return null;
        }
        output.add(cp);
      }
      pos = basicEnd + 1;
    }

    int n = initialN;
    int bias = initialBias;
    int i = 0;

    while (pos < input.length) {
      final int oldi = i;
      int w = 1;
      int k = base;
      while (true) {
        if (pos >= input.length) {
          return null;
        }
        final int cu = input.codeUnitAt(pos++);
        int digit;
        if (cu >= 0x30 && cu <= 0x39) {
          digit = cu - 0x30 + 26;
        } else if (cu >= 0x61 && cu <= 0x7A) {
          digit = cu - 0x61;
        } else {
          return null;
        }
        i += digit * w;
        if (i > 0x7FFFFFFF) {
          return null;
        }
        final int t = k <= bias
            ? tMin
            : (k >= bias + tMax ? tMax : k - bias);
        if (digit < t) {
          break;
        }
        w *= base - t;
        k += base;
      }

      final int outLen = output.length + 1;
      int delta = oldi == 0 ? (i - oldi) ~/ damp : (i - oldi) >> 1;
      delta += delta ~/ outLen;
      int kk = 0;
      while (delta > ((base - tMin) * tMax) ~/ 2) {
        delta ~/= base - tMin;
        kk += base;
      }
      bias = kk + (((base - tMin + 1) * delta) ~/ (delta + skew));

      n += i ~/ outLen;
      i %= outLen;
      if (n < 0 || n > 0x10FFFF) {
        return null;
      }
      output.insert(i, n);
      i++;
    }
    return String.fromCharCodes(output);
  }

  /// بررسی ترکیب الفبای لاتین با سیریلیک/یونانی درون یک برچسب واحد دامنه (قطعی هموگراف).
  static bool _hasMixedConfusableScript(String decodedLabel) {
    bool hasAsciiAlpha = false;
    bool hasCyrillicOrGreek = false;
    for (final int cp in decodedLabel.runes) {
      if ((cp >= 0x61 && cp <= 0x7A) || (cp >= 0x41 && cp <= 0x5A)) {
        hasAsciiAlpha = true;
      } else if ((cp >= 0x0400 && cp <= 0x052F) ||
          (cp >= 0x0370 && cp <= 0x03FF)) {
        hasCyrillicOrGreek = true;
      }
      if (hasAsciiAlpha && hasCyrillicOrGreek) {
        return true;
      }
    }
    return false;
  }

  /// تبدیل برچسب یونی کد به اسکلت لاتین برای کشف جعل هموگراف و لییت اسپیک.
  static String _toHomoglyphSkeleton(
    String input, {
    bool includeLeetspeak = false,
  }) {
    final StringBuffer sb = StringBuffer();
    for (final int cp in input.runes) {
      final String? mapped = _homoglyphMap[cp];
      if (mapped != null) {
        sb.write(mapped);
        continue;
      }
      if (cp >= 0x41 && cp <= 0x5A) {
        sb.writeCharCode(cp + 32);
      } else if (cp >= 0x61 && cp <= 0x7A) {
        sb.writeCharCode(cp);
      } else if (cp >= 0x30 && cp <= 0x39) {
        if (includeLeetspeak) {
          switch (cp) {
            case 0x30:
              sb.write('o');
              break;
            case 0x31:
              sb.write('l');
              break;
            case 0x33:
              sb.write('e');
              break;
            case 0x34:
              sb.write('a');
              break;
            case 0x35:
              sb.write('s');
              break;
            case 0x37:
              sb.write('t');
              break;
            case 0x38:
              sb.write('b');
              break;
            default:
              sb.writeCharCode(cp);
          }
        } else {
          sb.writeCharCode(cp);
        }
      } else if (cp == 0x2D) {
        sb.write('-');
      }
    }
    return sb.toString();
  }

  /// تشخیص آی پی مبهم (Decimal تک عددی، Hex یا Octal) که برای فریب استفاده می شود.
  static String? _detectObfuscatedIp(String host) {
    if (_isLoopbackHost(host)) {
      return null;
    }
    if (RegExp(r'^0x[0-9a-f]+$', caseSensitive: false).hasMatch(host)) {
      return 'آی پی هگزادسیمال مبهم';
    }
    if (RegExp(r'^\d{6,12}$').hasMatch(host)) {
      final int? val = int.tryParse(host);
      if (val != null && val > 65535 && val <= 0xFFFFFFFF) {
        return 'آی پی دسیمال یکپارچه مبهم';
      }
    }
    if (host.contains('.')) {
      final List<String> parts = host.split('.');
      if (parts.length <= 4 &&
          parts.every((String p) =>
              RegExp(r'^(0x[0-9a-f]+|0[0-7]+|\d+)$', caseSensitive: false)
                  .hasMatch(p))) {
        final bool hasHex = parts.any(
          (String p) => p.toLowerCase().startsWith('0x'),
        );
        final bool hasOctal = parts.any(
          (String p) => p.length > 1 && p.startsWith('0') && !p.startsWith('0x'),
        );
        if (hasHex || hasOctal) {
          return 'آی پی هگز/اکتال مبهم';
        }
      }
    }
    return null;
  }

  /// استخراج دامنه ثبتی و برچسب اصلی (SLD) با پشتیبانی از پسوندهای دوگانه رایج.
  static ({String registrable, String sld, String tld}) _splitDomainParts(
    String host,
  ) {
    final List<String> labels =
        host.split('.').where((String l) => l.isNotEmpty).toList();
    if (labels.length < 2) {
      return (registrable: host, sld: host, tld: '');
    }
    final String tld = labels.last;
    int sldIdx = labels.length - 2;
    if (labels.length >= 3 &&
        tld.length == 2 &&
        const <String>{'co', 'ac', 'org', 'gov', 'net', 'edu', 'com', 'sch'}
            .contains(labels[labels.length - 2])) {
      sldIdx = labels.length - 3;
    }
    final String sld = labels[sldIdx];
    final String registrable = labels.sublist(sldIdx).join('.');
    return (registrable: registrable, sld: sld, tld: tld);
  }

  /// فاصله ویرایشی Damerau-Levenshtein برای تشخیص Typosquatting دقیق.
  static int _damerauLevenshtein(String a, String b) {
    final int n = a.length;
    final int m = b.length;
    if ((n - m).abs() > 2) {
      return 3;
    }
    final List<List<int>> d = List<List<int>>.generate(
      n + 1,
      (_) => List<int>.filled(m + 1, 0),
    );
    for (int i = 0; i <= n; i++) {
      d[i][0] = i;
    }
    for (int j = 0; j <= m; j++) {
      d[0][j] = j;
    }
    for (int i = 1; i <= n; i++) {
      for (int j = 1; j <= m; j++) {
        final int cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        int best = math.min(
          math.min(d[i - 1][j] + 1, d[i][j - 1] + 1),
          d[i - 1][j - 1] + cost,
        );
        if (i > 1 &&
            j > 1 &&
            a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
            a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
          best = math.min(best, d[i - 2][j - 2] + cost);
        }
        d[i][j] = best;
      }
    }
    return d[n][m];
  }

  /// محاسبه آنتروپی شانون یک رشته برای تشخیص دامنه های الگوریتمی (DGA).
  static double _shannonEntropy(String s) {
    if (s.isEmpty) {
      return 0.0;
    }
    final Map<int, int> counts = <int, int>{};
    for (final int cu in s.codeUnits) {
      counts[cu] = (counts[cu] ?? 0) + 1;
    }
    final double len = s.length.toDouble();
    double entropy = 0.0;
    for (final int count in counts.values) {
      final double p = count / len;
      entropy -= p * (math.log(p) / math.ln2);
    }
    return entropy;
  }

  /// بررسی اینکه آیا هاست برای یک برند خاص جزو دامین های رسمی آن برند هست یا نه.
  static bool _isOfficialForBrand(String host, String brand) {
    final List<String>? official = _brandOfficialDomains[brand];
    if (official == null) {
      return false;
    }
    for (final String d in official) {
      if (host == d || host.endsWith('.$d')) {
        return true;
      }
    }
    return false;
  }

  /// بازرسی یک هاست (دامنه یا IP) بر اساس شاخص های ۲۰۲۶ بدون نیاز به ارسال شبکه ای.
  static MaliciousLinkMatch? inspectHost(String rawHost) {
    final String host = _normalizeHost(rawHost);
    if (host.isEmpty || _isLoopbackHost(host)) {
      return null;
    }
    if (_isTrustedHost(host)) {
      return null;
    }

    for (final String bad in knownMaliciousDomains) {
      if (host == bad || host.endsWith('.$bad')) {
        return MaliciousLinkMatch(
          key: 'link:domain:$bad',
          host: host,
          target: host,
          title: 'دامنه تله آی پی / تروجانی ($host)',
          detail:
              'این دامنه در فهرست پایگاه های سرقت نشانی آی پی، ردیابی پنهان یا دانلود بدافزار قرار دارد.',
          severity: 'critical',
          riskScore: 100,
        );
      }
    }

    // 1. تشخیص آی پی مبهم (Decimal / Hex / Octal)
    final String? obfuscatedIpReason = _detectObfuscatedIp(host);
    if (obfuscatedIpReason != null) {
      return MaliciousLinkMatch(
        key: 'link:obfuscated_ip:$host',
        host: host,
        target: host,
        title: 'نشانی آی پی مبهم و فریبنده ($host)',
        detail:
            'این پیوند با استفاده از $obfuscatedIpReason سعی در مخفی کردن سرور مقصد دارد.',
        severity: 'critical',
        riskScore: 95,
      );
    }

    // 2. دیکد Punycode + تشخیص هموگراف سیریلیک/یونانی و Mixed-Script
    final List<String> labels = host.split('.');
    for (final String label in labels) {
      final bool isPunycode = label.startsWith('xn--');
      final String? decoded = isPunycode ? _decodePunycodeLabel(label) : label;
      final bool hasNonAscii = decoded != null &&
          decoded.runes.any((int cp) => cp > 0x7F);

      if (decoded != null && hasNonAscii && _hasMixedConfusableScript(decoded)) {
        return MaliciousLinkMatch(
          key: 'link:homoglyph_mixed:$host',
          host: host,
          target: host,
          title: 'حمله هموگراف الفبای ترکیبی ($host)',
          detail:
              'دامنه با ترکیب هم زمان حروف لاتین و سیریلیک/یونانی برای جعل هویت بصری ساخته شده است.',
          severity: 'critical',
          riskScore: 98,
        );
      }

      if (isPunycode || hasNonAscii) {
        final String skeleton = _toHomoglyphSkeleton(
          decoded ?? label,
          includeLeetspeak: true,
        );
        final String plainLower = (decoded ?? label).toLowerCase();
        final List<String> labelTokens = skeleton
            .split('-')
            .where((String t) => t.isNotEmpty)
            .toList();
        for (final String brand in _brandOfficialDomains.keys) {
          if (_isOfficialForBrand(host, brand)) {
            continue;
          }
          final bool rawPunyLiteral = isPunycode && label.contains(brand);
          final bool nearHomoglyph = hasNonAscii &&
              brand.length >= 6 &&
              labelTokens.any(
                (String tok) => _damerauLevenshtein(tok, brand) <= 1,
              );
          if (skeleton.contains(brand) ||
              plainLower.contains(brand) ||
              rawPunyLiteral ||
              nearHomoglyph) {
            return MaliciousLinkMatch(
              key: 'link:homoglyph:$host',
              host: host,
              target: host,
              title: 'دامنه جعلی هموگراف / فیشینگ ($host)',
              detail:
                  'نشانی از کدگذاری جعلی Punycode یا کاراکترهای شبه همسان برای شبیه سازی «$brand» استفاده می کند.',
              severity: 'critical',
              riskScore: 96,
            );
          }
        }
      }
    }

    // 3. کلیدواژه های مستقیم فیشینگ و کلاهبرداری
    for (final String phrase in _phishingPrefixes) {
      if (host.contains(phrase)) {
        return MaliciousLinkMatch(
          key: 'link:phishing:$host',
          host: host,
          target: host,
          title: 'دامنه مشکوک فیشینگ ($host)',
          detail:
              'الگوی دامنه به عنوان نشانی جعلی ورود، احراز هویت یا هدیه تلگرامی/بانکی شناسایی شد.',
          severity: 'high',
          riskScore: 90,
        );
      }
    }

    // 4. بررسی جعل برند در زیردامنه، Combosquatting و Typosquatting
    final ({String registrable, String sld, String tld}) parts =
        _splitDomainParts(host);
    final String subdomainPart = host.length > parts.registrable.length
        ? host.substring(0, host.length - parts.registrable.length - 1)
        : '';

    for (final MapEntry<String, List<String>> entry
        in _brandOfficialDomains.entries) {
      final String brand = entry.key;
      if (_isOfficialForBrand(host, brand)) {
        continue;
      }

      // الف) قرار دادن دامنه کامل برند در زیردامنه: مثلا telegram.org.login-check.xyz
      for (final String officialDomain in entry.value) {
        if (subdomainPart == officialDomain ||
            subdomainPart.startsWith('$officialDomain.') ||
            subdomainPart.contains('.$officialDomain')) {
          return MaliciousLinkMatch(
            key: 'link:brand_subdomain:$host',
            host: host,
            target: host,
            title: 'فیشینگ جعل برند در زیردامنه ($host)',
            detail:
                'دامنه با قراردادن «$officialDomain» در بخش زیردامنه قصد فریب کاربر برای اعتماد کاذب دارد.',
            severity: 'critical',
            riskScore: 95,
          );
        }
      }

      // ب) Combosquatting: نام برند (یا اسکلت لیتی) + واژه فریبنده یا TLD پرخطر
      final String hostSkeleton = _toHomoglyphSkeleton(
        host,
        includeLeetspeak: true,
      );
      if (host.contains(brand) || hostSkeleton.contains(brand)) {
        final bool hasIntent = _phishingIntentTokens.any(
          (String tok) =>
              host.contains('-$tok') ||
              host.contains('${tok}-') ||
              host.contains('.$tok.') ||
              host.startsWith('$tok.'),
        );
        if (hasIntent || _highRiskTlds.contains(parts.tld)) {
          return MaliciousLinkMatch(
            key: 'link:brand_combo:$host',
            host: host,
            target: host,
            title: 'دامنه جعلی شبیه سازی برند «$brand» ($host)',
            detail:
                'این دامنه نام «$brand» را با پسوند یا عبارت های ورود/تایید برای فیشینگ ترکیب کرده است.',
            severity: 'high',
            riskScore: 88,
          );
        }
      }
    }

    // ج) Typosquatting فاصله ویرایشی ۱ روی برچسب اصلی دامنه (SLD)
    final String sldClean = parts.sld.replaceAll('-', '');
    final String sldLeet = _toHomoglyphSkeleton(
      sldClean,
      includeLeetspeak: true,
    );
    if (sldClean.length >= 6 &&
        !_benignDictionaryWords.contains(sldClean)) {
      for (final String brand in _typoTargetBrands) {
        if (sldClean == brand || _isOfficialForBrand(host, brand)) {
          continue;
        }
        if (sldLeet == brand ||
            _damerauLevenshtein(sldClean, brand) == 1 ||
            _damerauLevenshtein(sldLeet, brand) == 1) {
          return MaliciousLinkMatch(
            key: 'link:typosquat:$host',
            host: host,
            target: host,
            title: 'دامنه تایپواسکواتینگ شبیه «$brand» ($host)',
            detail:
                'املای این دامنه با تغییر جزئی در نام «$brand» برای فریب بصری و سرقت اطلاعات طراحی شده است.',
            severity: 'high',
            riskScore: 85,
          );
        }
      }
    }

    // 5. بررسی آنتروپی شانون بسیار بالا + TLD پرریسک یا تراکم عدد (DGA)
    final double sldEntropy = _shannonEntropy(sldClean);
    int digits = 0;
    for (final int cu in sldClean.codeUnits) {
      if (cu >= 0x30 && cu <= 0x39) {
        digits++;
      }
    }
    final double digitRatio =
        sldClean.isEmpty ? 0.0 : digits / sldClean.length;
    if (_highRiskTlds.contains(parts.tld) &&
        sldClean.length >= 14 &&
        sldEntropy >= 3.85 &&
        (digitRatio >= 0.20 || labels.length >= 4)) {
      return MaliciousLinkMatch(
        key: 'link:dga:$host',
        host: host,
        target: host,
        title: 'دامنه تصادفی و مشکوک DGA ($host)',
        detail:
            'این دامنه دارای الگوی نام تصادفی با آنتروپی بالا روی پسوند پرخطر (.${parts.tld}) است.',
        severity: 'high',
        riskScore: 80,
      );
    }

    return null;
  }

  /// بررسی کامل یک نشانی اینترنتی قبل از باز کردن برای کاربر (فیشینگ، ClickFix، ریدایرکت پنهان، تروجان).
  static MaliciousLinkMatch? inspectUrl(String rawInput, {int depth = 0}) {
    if (depth > 2) {
      return null;
    }
    final String raw = rawInput.trim();
    if (raw.isEmpty) {
      return null;
    }
    final String lower = raw.toLowerCase();

    // 1. اسکیماهای غیرمتعارف مخرب، ClickFix و Fileless Execution
    const List<String> dangerousSchemes = <String>[
      'javascript:',
      'vbscript:',
      'ms-msdt:',
      'search-ms:',
      'mshta:',
      'powershell:',
      'cmd:',
      'wscript:',
      'cscript:',
      'blob:',
    ];
    for (final String scheme in dangerousSchemes) {
      if (lower.startsWith(scheme)) {
        return MaliciousLinkMatch(
          key: 'link:scheme:$scheme',
          host: scheme.replaceAll(':', ''),
          target: raw.length > 180 ? raw.substring(0, 180) : raw,
          title: 'لینک اسکریپتی خطرناک ($scheme)',
          detail: 'پروتکل اجرای مستقیم کد یا فایل سیستمی برای امنیت کاربر مسدود شد.',
          severity: 'critical',
          riskScore: 100,
        );
      }
    }

    if (lower.startsWith('data:')) {
      final bool unsafeData = lower.startsWith('data:text/html') ||
          lower.startsWith('data:image/svg+xml') ||
          lower.startsWith('data:text/javascript') ||
          lower.startsWith('data:application/') ||
          lower.contains('tvqqaam') ||
          lower.contains('uesdb');
      if (unsafeData) {
        return MaliciousLinkMatch(
          key: 'link:data_payload',
          host: 'data-uri',
          target: raw.length > 180 ? raw.substring(0, 180) : raw,
          title: 'پیوند Data URI مخرب یا باینری پنهان',
          detail: 'باز کردن صفحات یا فایل های باینری تعبیه شده در Data URI مسدود شد.',
          severity: 'critical',
          riskScore: 98,
        );
      }
    }

    if (lower.startsWith('file:') &&
        (_dangerExeExts.any(lower.contains) ||
            lower.contains('powershell') ||
            lower.contains('cmd.exe'))) {
      return MaliciousLinkMatch(
        key: 'link:file_exec',
        host: 'local-file',
        target: raw.length > 180 ? raw.substring(0, 180) : raw,
        title: 'فراخوانی فایل اجرایی محلی مسدود شد',
        detail: 'لینک file:// اشاره کننده به فایل اجرایی یا اسکریپت سیستمی مجاز نیست.',
        severity: 'critical',
        riskScore: 95,
      );
    }

    // 2. دستکاری ترتیب نوشتار برای فریب پسوند فایل (Right-to-Left Override / Bidi Controls)
    if (RegExp(r'[\u202A-\u202E\u2066-\u2069]').hasMatch(raw)) {
      return MaliciousLinkMatch(
        key: 'link:rlo:${raw.hashCode}',
        host: 'spoofed-rlo',
        target: raw.length > 180 ? raw.substring(0, 180) : raw,
        title: 'نشانی فریبنده با کاراکتر تغییر جهت مخفی (RLO)',
        detail:
            'این پیوند از کاراکترهای پنهان یونیکد برای تغییر ظاهر پسوند فایل خطرناک استفاده می کند.',
        severity: 'critical',
        riskScore: 98,
      );
    }

    // 3. تشخیص الگوهای ClickFix / فرمان های پنهان پاورشل داخل متن یا پارامتر لینک
    String decodedLower = lower;
    try {
      decodedLower = Uri.decodeFull(raw).toLowerCase();
    } catch (_) {}
    if (decodedLower.contains('powershell -enc') ||
        decodedLower.contains('powershell -e ') ||
        decodedLower.contains('mshta http') ||
        decodedLower.contains('certutil -urlcache') ||
        decodedLower.contains('curl ') && decodedLower.contains('| sh') ||
        decodedLower.contains('wget ') && decodedLower.contains('| bash')) {
      return MaliciousLinkMatch(
        key: 'link:clickfix:${raw.hashCode}',
        host: 'clickfix-command',
        target: raw.length > 180 ? raw.substring(0, 180) : raw,
        title: 'دستور مخرب ClickFix / اجرای از راه دور در پیوند',
        detail: 'نشانی حاوی کد فرمان اجرایی پاورشل یا بارگیری اسکریپت آلوده است.',
        severity: 'critical',
        riskScore: 100,
      );
    }

    final String normalized = lower.contains('://') ? raw : 'https://$raw';
    final Uri? uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) {
      return null;
    }

    final String host = _normalizeHost(uri.host);
    final bool loopback = _isLoopbackHost(host);

    // 4. فریب Userinfo (`@`) مانند https://telegram.org@evil.com/login
    if (!loopback && uri.userInfo.isNotEmpty) {
      final String ui = uri.userInfo.toLowerCase();
      final bool looksSpoofed = ui.contains('.') ||
          _brandOfficialDomains.keys.any(ui.contains) ||
          _credentialPathKeywords.any(ui.contains) ||
          ui.length >= 6;
      if (looksSpoofed) {
        return MaliciousLinkMatch(
          key: 'link:userinfo_spoof:$host',
          host: host,
          target: raw.length > 180 ? raw.substring(0, 180) : raw,
          title: 'حمله فریب نشانی با کاراکتر @ ($host)',
          detail:
              'این پیوند با قراردادن عبارت جعلی قبل از @ سعی در پنهان کردن سرور واقعی ($host) دارد.',
          severity: 'critical',
          riskScore: 96,
        );
      }
    }

    // بررسی قوانین میزبان (مگر برای صفحه محلی خود برنامه یا دامین تاییدشده)
    final bool trusted = _isTrustedHost(host);
    if (!trusted && !loopback) {
      final MaliciousLinkMatch? hostHit = inspectHost(host);
      if (hostHit != null) {
        return MaliciousLinkMatch(
          key: hostHit.key,
          host: host,
          target: raw.length > 180 ? raw.substring(0, 180) : raw,
          title: hostHit.title,
          detail: hostHit.detail,
          severity: hostHit.severity,
          riskScore: hostHit.riskScore,
        );
      }
    }

    // 5. بررسی فایل های مخرب با پسوند دوگانه یا دانلود اجرایی روی IP / TLD پرریسک
    final String pathLower = uri.path.toLowerCase();
    final bool hasDoubleExt =
        _dangerExeExts.any(pathLower.endsWith) &&
        _decoyExts.any(pathLower.contains);
    if (hasDoubleExt) {
      return MaliciousLinkMatch(
        key: 'link:double_ext:${host}_${pathLower.hashCode}',
        host: host,
        target: raw.length > 180 ? raw.substring(0, 180) : raw,
        title: 'لینک دانلود فایل تروجانی با پسوند دوگانه ($host)',
        detail:
            'لینک مستقیماً به فایل اجرایی پنهان شده در قالب عکس یا سند اشاره دارد.',
        severity: 'critical',
        riskScore: 98,
      );
    }

    final bool isRawIp = !loopback &&
        RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host);
    final bool isPrivateIp = isRawIp && _isPrivateIpV4(host);
    final bool isPublicRawIp = isRawIp && !isPrivateIp;
    final String tld = host.contains('.') ? host.split('.').last : '';
    final bool exeDownload = _dangerExeExts.any(pathLower.endsWith);
    const List<String> strictDropperExts = <String>[
      '.scr', '.pif', '.hta', '.vbs', '.vbe', '.jse', '.wsf', '.wsh', '.ps1',
      '.bat', '.cmd',
    ];
    final bool strictDropper = strictDropperExts.any(pathLower.endsWith);
    if (!trusted && !loopback && strictDropper) {
      return MaliciousLinkMatch(
        key: 'link:script_dropper:$host',
        host: host,
        target: raw.length > 180 ? raw.substring(0, 180) : raw,
        title: 'لینک مستقیم فایل اسکریپتی/اجرایی خطرناک ($host)',
        detail:
            'لینک بیرونی مستقیماً به فایل اسکریپتی یا تروجانی (.scr/.hta/.vbs/.ps1/.bat) اشاره دارد و برای امنیت مسدود شد.',
        severity: 'critical',
        riskScore: 95,
      );
    }
    if (exeDownload && (isPublicRawIp || _highRiskTlds.contains(tld))) {
      return MaliciousLinkMatch(
        key: 'link:payload:$host',
        host: host,
        target: raw.length > 180 ? raw.substring(0, 180) : raw,
        title: 'لینک دانلود پرخطر فایل اجرایی/نصبی ($host)',
        detail:
            'دانلود مستقیم فایل نصبی یا اجرایی از آی پی عمومی مستقیم یا دامنه پرریسک مسدود شد.',
        severity: 'high',
        riskScore: 90,
      );
    }

    if (lower.contains('eicar-standard-antivirus-test-file') ||
        (lower.contains('trojan') && exeDownload)) {
      return MaliciousLinkMatch(
        key: 'link:trojan:$host',
        host: host,
        target: raw.length > 180 ? raw.substring(0, 180) : raw,
        title: 'لینک دانلود بدافزار / تروجان ($host)',
        detail: 'نشانی دانلود حاوی امضای فایل تروجانی شناسایی و مسدود شد.',
        severity: 'critical',
        riskScore: 98,
      );
    }

    // 6. درگاه های C2/RAT غیرمعمول در پیوند بیرونی
    if (!loopback &&
        !trusted &&
        uri.hasPort &&
        _suspiciousC2Ports.contains(uri.port) &&
        (isPublicRawIp || _highRiskTlds.contains(tld) || exeDownload)) {
      return MaliciousLinkMatch(
        key: 'link:c2_port:$host:${uri.port}',
        host: host,
        target: raw.length > 180 ? raw.substring(0, 180) : raw,
        title: 'ارتباط با درگاه مشکوک کنترل از راه دور (${uri.port})',
        detail:
            'درگاه ${uri.port} روی نشانی مشکوک جزو درگاه های رایج سرورهای RAT/بدافزار است.',
        severity: 'high',
        riskScore: 86,
      );
    }

    // 7. بازرسی بازگشتی پارامترهای Open-Redirect و Base64 Payload در Query (نه برای صفحه محلی مسدودی)
    if (!loopback) {
      final MaliciousLinkMatch? redirectHit = _inspectQueryAndFragment(
        uri,
        parentHost: host,
        rawUrl: raw,
        depth: depth,
      );
      if (redirectHit != null) {
        return redirectHit;
      }
    }

    // 8. بررسی ترکیب چند شاخص قطعی فیشینگ ۲۰۲۶ (آی پی عمومی مستقیم + ورود/پرداخت، یا الگوی DGA + TLD پرریسک؛ آی پی روتر محلی مستثنی است)
    if (!loopback && !trusted && !isPrivateIp) {
      final int score = _computeUrlRiskScore(
        uri: uri,
        host: host,
        tld: tld,
        isRawIp: isPublicRawIp,
        pathLower: pathLower,
        exeDownload: exeDownload,
        rawLength: raw.length,
      );
      if (score >= 70) {
        return MaliciousLinkMatch(
          key: 'link:heuristic:$host:$score',
          host: host,
          target: raw.length > 180 ? raw.substring(0, 180) : raw,
          title: 'پیوند فیشینگ با ساختار پرخطر ($host)',
          detail:
              'این نشانی هم زمان چندین الگوی خطرناک فیشینگ/تخلف (شاخص تطبیق $score از ۱۰۰) را در آدرس و دامنه دارد و مسدود شد.',
          severity: score >= 85 ? 'critical' : 'high',
          riskScore: score,
        );
      }
    }

    return null;
  }

  static bool _isPrivateIpV4(String host) {
    final List<String> segs = host.split('.');
    if (segs.length != 4) {
      return false;
    }
    final int? a = int.tryParse(segs[0]);
    final int? b = int.tryParse(segs[1]);
    if (a == null || b == null) {
      return false;
    }
    return a == 10 ||
        a == 127 ||
        (a == 192 && b == 168) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 169 && b == 254);
  }

  static MaliciousLinkMatch? _inspectQueryAndFragment(
    Uri uri, {
    required String parentHost,
    required String rawUrl,
    required int depth,
  }) {
    final Map<String, String> params = <String, String>{};
    uri.queryParameters.forEach((String k, String v) {
      params[k.toLowerCase()] = v;
    });

    for (final MapEntry<String, String> entry in params.entries) {
      final String val = entry.value.trim();
      if (val.isEmpty) {
        continue;
      }
      final String valLower = val.toLowerCase();
      // نشانه باینری PE/ZIP پنهان شده به صورت Base64 داخل URL
      if (valLower.contains('tvqqaam') || valLower.contains('uesdb')) {
        return MaliciousLinkMatch(
          key: 'link:b64_payload:$parentHost',
          host: parentHost,
          target: rawUrl.length > 180 ? rawUrl.substring(0, 180) : rawUrl,
          title: 'محتوای اجرایی Base64 پنهان در پارامتر پیوند',
          detail:
              'در پارامتر «${entry.key}» این پیوند داده اجرایی رمزنگاری شده شناسایی شد.',
          severity: 'critical',
          riskScore: 95,
        );
      }

      if (!_redirectParamKeys.contains(entry.key)) {
        continue;
      }

      String candidate = val;
      if (!candidate.contains('://') &&
          !candidate.startsWith('javascript:') &&
          !candidate.startsWith('data:') &&
          candidate.length >= 16) {
        final String? b64Decoded = _tryDecodeBase64UrlString(candidate);
        if (b64Decoded != null) {
          candidate = b64Decoded;
        }
      }

      final String candLower = candidate.toLowerCase();
      if (candLower.startsWith('http://') ||
          candLower.startsWith('https://') ||
          candLower.startsWith('javascript:') ||
          candLower.startsWith('vbscript:') ||
          candLower.startsWith('data:') ||
          candLower.startsWith('ms-msdt:')) {
        final MaliciousLinkMatch? nestedHit = inspectUrl(
          candidate,
          depth: depth + 1,
        );
        if (nestedHit != null) {
          return MaliciousLinkMatch(
            key: 'link:open_redirect:${nestedHit.key}',
            host: nestedHit.host,
            target: rawUrl.length > 180 ? rawUrl.substring(0, 180) : rawUrl,
            title: 'تغییرجهت پنهان به نشانی مخرب (${nestedHit.host})',
            detail:
                'پارامتر «${entry.key}» کاربر را به پیوند خطرناک «${nestedHit.title}» هدایت می کرد.',
            severity: 'critical',
            riskScore: math.max(92, nestedHit.riskScore),
          );
        }
      }
    }

    if (uri.fragment.isNotEmpty) {
      final String frag = uri.fragment.trim();
      final String fragLower = frag.toLowerCase();
      if (fragLower.startsWith('http://') ||
          fragLower.startsWith('https://') ||
          fragLower.startsWith('javascript:') ||
          fragLower.startsWith('data:')) {
        final MaliciousLinkMatch? fragHit = inspectUrl(frag, depth: depth + 1);
        if (fragHit != null) {
          return MaliciousLinkMatch(
            key: 'link:frag_redirect:${fragHit.key}',
            host: fragHit.host,
            target: rawUrl.length > 180 ? rawUrl.substring(0, 180) : rawUrl,
            title: 'نشانی مخرب پنهان در بخش Fragment پیوند',
            detail: fragHit.detail,
            severity: 'critical',
            riskScore: math.max(90, fragHit.riskScore),
          );
        }
      }
    }
    return null;
  }

  static String? _tryDecodeBase64UrlString(String input) {
    if (!RegExp(r'^[A-Za-z0-9+/=_-]{16,512}$').hasMatch(input)) {
      return null;
    }
    try {
      String norm = input.replaceAll('-', '+').replaceAll('_', '/');
      while (norm.length % 4 != 0) {
        norm += '=';
      }
      final List<int> bytes = base64.decode(norm);
      final String decoded = utf8.decode(bytes, allowMalformed: false).trim();
      final String lower = decoded.toLowerCase();
      if (lower.startsWith('http://') ||
          lower.startsWith('https://') ||
          lower.startsWith('javascript:') ||
          lower.startsWith('data:') ||
          lower.startsWith('ms-msdt:')) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  static int _computeUrlRiskScore({
    required Uri uri,
    required String host,
    required String tld,
    required bool isRawIp,
    required String pathLower,
    required bool exeDownload,
    required int rawLength,
  }) {
    int score = 0;
    final List<String> labels = host.split('.');
    final ({String registrable, String sld, String tld}) parts =
        _splitDomainParts(host);
    final String sldClean = parts.sld.replaceAll('-', '');

    if (isRawIp) {
      score += 35;
    }
    if (_highRiskTlds.contains(tld)) {
      score += 25;
    }
    if (labels.length >= 4) {
      score += 20;
    }
    if (uri.scheme == 'http' && !isRawIp) {
      score += 10;
    }

    final bool hasCredentialWord = _credentialPathKeywords.any(
      (String kw) =>
          pathLower.contains('/$kw') ||
          pathLower.contains('${kw}.') ||
          uri.query.toLowerCase().contains(kw),
    );
    if (hasCredentialWord) {
      score += (uri.scheme == 'http' || isRawIp || _highRiskTlds.contains(tld))
          ? 35
          : 15;
    }

    if (exeDownload) {
      score += 30;
    }

    final double entropy = _shannonEntropy(sldClean);
    if (sldClean.length >= 12 && entropy >= 3.8) {
      score += 25;
    }

    int digits = 0;
    for (final int cu in sldClean.codeUnits) {
      if (cu >= 0x30 && cu <= 0x39) {
        digits++;
      }
    }
    if (sldClean.length >= 8 && (digits / sldClean.length) >= 0.35) {
      score += 20;
    }

    if (rawLength >= 180) {
      score += 15;
    }
    return score.clamp(0, 100);
  }
}
