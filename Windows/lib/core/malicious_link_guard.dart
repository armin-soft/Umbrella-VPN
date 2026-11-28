/// موتور تحلیل هوشمند و مسدودسازی لینک ها و دامنه های تروجانی، فیشینگ و دانلودر بدافزار.
class MaliciousLinkMatch {
  const MaliciousLinkMatch({
    required this.key,
    required this.host,
    required this.target,
    required this.title,
    required this.detail,
    required this.severity,
  });

  final String key;
  final String host;
  final String target;
  final String title;
  final String detail;
  final String severity;
}

class MaliciousLinkGuard {
  const MaliciousLinkGuard._();

  /// دامنه های تایید شده و رسمی که نباید هرگز به عنوان فیشینگ پرچم بخورند.
  static const Set<String> _trustedSuffixes = <String>{
    'armin-soft.ir',
    'telegram.org',
    'telegram.me',
    't.me',
    'whatsapp.com',
    'instagram.com',
    'google.com',
    'googleapis.com',
    'gstatic.com',
    'github.com',
    'githubusercontent.com',
    'apple.com',
    'microsoft.com',
    'shaparak.ir',
    'bmi.ir',
    'bankmellat.ir',
    'bsi.ir',
    'bpi.ir',
    'sb24.ir',
    'tejaratbank.ir',
    'refah-bank.ir',
    'binance.com',
    'nobitex.ir',
  };

  /// دامنه های شناخته شده تروجان، فیشینگ، تله IP و توزیع بدافزار.
  static const Set<String> _knownMaliciousDomains = <String>{
    'grabify.link',
    'iplogger.org',
    'iplogger.com',
    '2no.co',
    'blasze.com',
    'ezstat.ru',
    'yip.su',
    'ps3cfw.com',
    'bmwforum.co',
    'leancoding.co',
    'spottyfly.com',
    'stopify.co',
    'lovebird.guru',
    'trulove.guru',
    'dateing.club',
    'otherhalf.life',
    'shrekis.life',
    'datasig.io',
    'quickmessage.us',
    'screenshare.pics',
    'myprivate.pics',
    'photovault.pics',
    'imagevault.cloud',
    'canarytokens.com',
    'webhook.site',
    'requestbin.net',
    'pipedream.net',
    'ngrok-free.app',
    'trojan-test.umbrella.invalid',
  };

  /// دامنه های شناخته شده تروجان، فیشینگ و تله آی پی برای مسدودسازی خودکار در هسته.
  static Set<String> get knownMaliciousDomains => _knownMaliciousDomains;

  static const Set<String> _highRiskTlds = <String>{
    'tk', 'ml', 'ga', 'cf', 'gq', 'top', 'click', 'loan', 'zip', 'mov', 'icu',
    'work', 'buzz', 'rest',
  };

  static const List<String> _phishingPrefixes = <String>[
    'telegram-verify',
    'telegram-login',
    'telegram-gift',
    'telegram-premium-free',
    'tg-verify',
    'tg-login',
    'shaparak-pay',
    'shaparak-verify',
    'mellat-pay',
    'saderat-online',
    'hamrahbank-update',
    'wallet-verify-tg',
    'free-stars-tg',
    'umbrella-crack',
    'trojan-loader',
  ];

  /// عبارات دامنه فیشینگ و تروجانی برای مسدودسازی خودکار در هسته.
  static List<String> get phishingPhrases => _phishingPrefixes;

  static const List<String> _dangerExeExts = <String>[
    '.apk', '.exe', '.scr', '.pif', '.com', '.bat', '.cmd', '.vbs', '.vbe', '.js',
    '.jse', '.wsf', '.wsh', '.ps1', '.hta', '.msi',
  ];

  static const List<String> _decoyExts = <String>[
    '.jpg.', '.jpeg.', '.png.', '.gif.', '.webp.', '.bmp.', '.pdf.', '.mp4.',
    '.doc.', '.zip.',
  ];

  static bool _isTrustedHost(String host) {
    final String h = host.toLowerCase();
    if (h == 'localhost' ||
        h == '127.0.0.1' ||
        h == '::1' ||
        h.endsWith('.local') ||
        h.startsWith('10.') ||
        h.startsWith('192.168.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(h)) {
      return true;
    }
    for (final String suffix in _trustedSuffixes) {
      if (h == suffix || h.endsWith('.$suffix')) {
        return true;
      }
    }
    return false;
  }

  /// بررسی دامنه/میزبان استخراج شده از اتصالات زنده (`ClashApi`).
  static MaliciousLinkMatch? inspectHost(String rawHost) {
    final String host = rawHost
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r':\d+$'), '')
        .replaceAll(RegExp(r'^\.+|\.+$'), '');
    if (host.isEmpty || !host.contains('.') || _isTrustedHost(host)) {
      return null;
    }

    for (final String bad in _knownMaliciousDomains) {
      if (host == bad || host.endsWith('.$bad')) {
        return MaliciousLinkMatch(
          key: 'link:$bad',
          host: host,
          target: host,
          title: 'لینک / دامنه تروجانی یا سرقت اطلاعات ($host)',
          detail: 'ارتباط با دامنه شناخته شده بدافزار و تله آی پی مسدود شد.',
          severity: 'critical',
        );
      }
    }

    if (host.contains('xn--')) {
      const List<String> impersonated = <String>[
        'telegram', 'whatsapp', 'instagram', 'shaparak', 'mellat', 'saderat',
        'pasargad', 'google', 'apple', 'microsoft', 'binance', 'nobitex',
        'umbrella',
      ];
      for (final String brand in impersonated) {
        if (host.contains(brand)) {
          return MaliciousLinkMatch(
            key: 'link:idn:$host',
            host: host,
            target: host,
            title: 'دامنه جعلی هموگراف / فیشینگ ($host)',
            detail: 'دامنه فریبنده با نویسه های جعلی شبیه برند معتبر شناسایی و مسدود شد.',
            severity: 'critical',
          );
        }
      }
    }

    for (final String phrase in _phishingPrefixes) {
      if (host.contains(phrase)) {
        return MaliciousLinkMatch(
          key: 'link:phish:$host',
          host: host,
          target: host,
          title: 'دامنه فیشینگ یا تروجانی ($host)',
          detail: 'الگوی جعل صفحه پرداخت یا ورود غیرمجاز در دامنه شناسایی و مسدود شد.',
          severity: 'high',
        );
      }
    }
    return null;
  }

  /// بررسی کامل یک نشانی اینترنتی یا لینک ارسال شده پیش از باز شدن.
  static MaliciousLinkMatch? inspectUrl(String rawInput) {
    final String raw = rawInput.trim();
    if (raw.isEmpty) return null;
    final String lower = raw.toLowerCase();

    if (lower.startsWith('javascript:') ||
        lower.startsWith('vbscript:') ||
        lower.startsWith('ms-msdt:') ||
        lower.startsWith('search-ms:') ||
        lower.startsWith('data:text/html')) {
      return MaliciousLinkMatch(
        key: 'link:scheme:${lower.split(':').first}',
        host: '',
        target: raw.length > 160 ? raw.substring(0, 160) : raw,
        title: 'لینک اجرای کد مخرب شناسایی شد',
        detail: 'پروتکل خطرناک اجرای مستقیم اسکریپت یا فرمان در لینک شناسایی و مسدود شد.',
        severity: 'critical',
      );
    }

    if (lower.contains('\u202e') || lower.contains('%e2%80%ae')) {
      return MaliciousLinkMatch(
        key: 'link:rlo:${lower.hashCode}',
        host: '',
        target: raw.length > 160 ? raw.substring(0, 160) : raw,
        title: 'لینک فریبنده تروجانی با نویسه تغییر جهت',
        detail: 'لینک دارای کاراکتر مخفی تغییر جهت جهت فریب پسوند فایل است.',
        severity: 'critical',
      );
    }

    final String normalized =
        lower.contains('://') ? raw : 'https://$raw';
    final Uri? uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) return null;
    final String host = uri.host.toLowerCase();
    if (_isTrustedHost(host)) return null;

    final MaliciousLinkMatch? hostHit = inspectHost(host);
    if (hostHit != null) {
      return MaliciousLinkMatch(
        key: hostHit.key,
        host: host,
        target: raw.length > 180 ? raw.substring(0, 180) : raw,
        title: hostHit.title,
        detail: hostHit.detail,
        severity: hostHit.severity,
      );
    }

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
        detail: 'لینک مستقیماً به فایل اجرایی پنهان شده در قالب عکس یا سند اشاره دارد.',
        severity: 'critical',
      );
    }

    final bool isRawIp = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host);
    final String tld = host.contains('.') ? host.split('.').last : '';
    final bool exeDownload =
        _dangerExeExts.any(pathLower.endsWith) || pathLower.endsWith('.apk');
    if (exeDownload && (isRawIp || _highRiskTlds.contains(tld))) {
      return MaliciousLinkMatch(
        key: 'link:payload:$host',
        host: host,
        target: raw.length > 180 ? raw.substring(0, 180) : raw,
        title: 'لینک دانلود پرخطر فایل اجرایی/تروجانی ($host)',
        detail: 'دانلود مستقیم فایل اجرایی یا نصبی از آی پی مستقیم یا دامنه مشکوک مسدود شد.',
        severity: 'high',
      );
    }

    if (lower.contains('eicar-standard-antivirus-test-file') ||
        lower.contains('trojan') && exeDownload) {
      return MaliciousLinkMatch(
        key: 'link:trojan:$host',
        host: host,
        target: raw.length > 180 ? raw.substring(0, 180) : raw,
        title: 'لینک دانلود بدافزار / تروجان ($host)',
        detail: 'نشانی دانلود حاوی امضای فایل تروجانی شناسایی و مسدود شد.',
        severity: 'critical',
      );
    }

    return null;
  }
}
