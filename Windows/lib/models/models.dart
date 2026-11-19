import 'dart:io';

import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../core/utils.dart';
import 'advanced_network.dart';
export 'advanced_network.dart';

enum SubscriptionFormat { xray, clash, wireguard, amnezia, mieru }

extension SubscriptionFormatX on SubscriptionFormat {
  String get label {
    switch (this) {
      case SubscriptionFormat.xray:
        return 'ایکس ری';
      case SubscriptionFormat.clash:
        return 'کلش متا';
      case SubscriptionFormat.wireguard:
        return 'وایرگارد';
      case SubscriptionFormat.amnezia:
        return 'آمنزیا';
      case SubscriptionFormat.mieru:
        return 'میرو';
    }
  }
}

class SubscriptionSource {
  const SubscriptionSource({
    required this.id,
    required this.title,
    required this.url,
    required this.format,
    required this.icon,
    this.personal = false,
  });

  final String id;
  final String title;
  final String url;
  final SubscriptionFormat format;
  final String icon;

  /// اشتراک شخصی کاربر که سرور می دهد؛ هیچ نشانی از کاربر گرفته نمی شود.
  final bool personal;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'url': url,
        'format': format.name,
        'icon': icon,
        'personal': personal,
      };

  factory SubscriptionSource.fromJson(Map<String, dynamic> json) {
    return SubscriptionSource(
      id: JsonX.text(json['id']),
      title: JsonX.text(json['title']),
      url: JsonX.text(json['url']),
      format: SubscriptionFormat.values.firstWhere(
        (SubscriptionFormat item) => item.name == JsonX.text(json['format']),
        orElse: () => SubscriptionFormat.xray,
      ),
      icon: JsonX.text(json['icon'], 'bolt'),
      personal: JsonX.boolean(json['personal']),
    );
  }
}

enum NodeProtocol {
  vless,
  vmess,
  trojan,
  shadowsocks,
  ssh,
  naive,
  anytls,
  wireguard,
  amnezia,
  mieru,
  hysteria2,
  tuic,
  socks,
  clash,
}

extension NodeProtocolX on NodeProtocol {
  String get label {
    switch (this) {
      case NodeProtocol.vless:
        return 'وی لس';
      case NodeProtocol.vmess:
        return 'وی مس';
      case NodeProtocol.trojan:
        return 'تروجان';
      case NodeProtocol.shadowsocks:
        return 'شادوساکس';
      case NodeProtocol.ssh:
        return 'اس اس اچ';
      case NodeProtocol.naive:
        return 'نایو پروکسی';
      case NodeProtocol.anytls:
        return 'انی تی ال اس';
      case NodeProtocol.wireguard:
        return 'وایرگارد';
      case NodeProtocol.amnezia:
        return 'آمنزیا';
      case NodeProtocol.mieru:
        return 'میرو';
      case NodeProtocol.hysteria2:
        return 'هیستریا';
      case NodeProtocol.tuic:
        return 'توئیک';
      case NodeProtocol.socks:
        return 'سوکس';
      case NodeProtocol.clash:
        return 'کلش';
    }
  }

  String get coreId {
    switch (this) {
      case NodeProtocol.vless:
      case NodeProtocol.vmess:
      case NodeProtocol.trojan:
      case NodeProtocol.shadowsocks:
        return 'xray';
      case NodeProtocol.wireguard:
        return 'wireguard';
      case NodeProtocol.amnezia:
        return 'amnezia';
      case NodeProtocol.mieru:
        return 'mieru';
      case NodeProtocol.ssh:
      case NodeProtocol.naive:
      case NodeProtocol.anytls:
      case NodeProtocol.hysteria2:
      case NodeProtocol.tuic:
      case NodeProtocol.socks:
      case NodeProtocol.clash:
        return 'singbox';
    }
  }

  bool get isObfuscated => this == NodeProtocol.amnezia;
}

/// یک گره اتصال (سرور) که از یکی از اشتراک ها خوانده شده است.
/// نام کشور به کد پرچم؛ برای استخراج پرچم از نام سرور.
const Map<String, String> countryAliases = <String, String>{
  'canada': 'ca',
  'montreal': 'ca',
  'toronto': 'ca',
  'germany': 'de',
  'frankfurt': 'de',
  'netherlands': 'nl',
  'amsterdam': 'nl',
  'turkey': 'tr',
  'istanbul': 'tr',
  'emirates': 'ae',
  'dubai': 'ae',
  'united states': 'us',
  'america': 'us',
  'finland': 'fi',
  'helsinki': 'fi',
  'france': 'fr',
  'paris': 'fr',
  'britain': 'gb',
  'london': 'gb',
  'sweden': 'se',
  'stockholm': 'se',
  'iran': 'ir',
  'tehran': 'ir',
  'ژاپن': 'jp',
  'آلمان': 'de',
  'هلند': 'nl',
  'ترکیه': 'tr',
  'امارات': 'ae',
  'آمریکا': 'us',
  'فنلاند': 'fi',
  'فرانسه': 'fr',
  'سوئد': 'se',
  'ایران': 'ir',
  'کانادا': 'ca',
  // نام هایی که در اشتراک های فارسی واقعا دیده می شوند. نام سرور در گزارش
  // های کاربر «سرور آمبرلا (خودکار) tls_h2 grpc CDN vless» بود؛ هیچ کدام از
  // این واژه ها کشور نیست، پس پرچم هم پیدا نمی شد و کاربر می پرسید «چرا
  // پرچم کشورها را نمایش نمی دهد».
  'انگلیس': 'gb',
  'بریتانیا': 'gb',
  'فرانکفورت': 'de',
  'آمستردام': 'nl',
  'استانبول': 'tr',
  'دبی': 'ae',
  'قطر': 'qa',
  'عمان': 'om',
  'عربستان': 'sa',
  'روسیه': 'ru',
  'مسکو': 'ru',
  'اوکراین': 'ua',
  'لهستان': 'pl',
  'وارسو': 'pl',
  'اتریش': 'at',
  'سوئیس': 'ch',
  'بلژیک': 'be',
  'دانمارک': 'dk',
  'نروژ': 'no',
  'اسپانیا': 'es',
  'پرتغال': 'pt',
  'ایتالیا': 'it',
  'میلان': 'it',
  'رومانی': 'ro',
  'بلغارستان': 'bg',
  'مجارستان': 'hu',
  'جمهوری چک': 'cz',
  'پراگ': 'cz',
  'یونان': 'gr',
  'قبرس': 'cy',
  'ارمنستان': 'am',
  'گرجستان': 'ge',
  'آذربایجان': 'az',
  'قزاقستان': 'kz',
  'هند': 'in',
  'بمبئی': 'in',
  'سنگاپور': 'sg',
  'اندونزی': 'id',
  'مالزی': 'my',
  'تایلند': 'th',
  'ویتنام': 'vn',
  'فیلیپین': 'ph',
  'توکیو': 'jp',
  'کره': 'kr',
  'سئول': 'kr',
  'چین': 'cn',
  'هنگ کنگ': 'hk',
  'تایوان': 'tw',
  'استرالیا': 'au',
  'سیدنی': 'au',
  'نیوزیلند': 'nz',
  'برزیل': 'br',
  'آرژانتین': 'ar',
  'شیلی': 'cl',
  'مکزیک': 'mx',
  'مصر': 'eg',
  'مراکش': 'ma',
  'الجزایر': 'dz',
  'تونس': 'tn',
  'آفریقای جنوبی': 'za',
  'نیجریه': 'ng',
  'کنیا': 'ke',
  'اسرائیل': 'il',
  'پاکستان': 'pk',
  'بنگلادش': 'bd',
  'سریلانکا': 'lk',
  'نپال': 'np',
  // نام های انگلیسی رایج در نام سرور.
  'united kingdom': 'gb',
  'england': 'gb',
  'switzerland': 'ch',
  'zurich': 'ch',
  'austria': 'at',
  'vienna': 'at',
  'belgium': 'be',
  'denmark': 'dk',
  'norway': 'no',
  'oslo': 'no',
  'spain': 'es',
  'madrid': 'es',
  'italy': 'it',
  'milan': 'it',
  'romania': 'ro',
  'bulgaria': 'bg',
  'hungary': 'hu',
  'budapest': 'hu',
  'czech': 'cz',
  'prague': 'cz',
  'greece': 'gr',
  'cyprus': 'cy',
  'armenia': 'am',
  'yerevan': 'am',
  'georgia': 'ge',
  'tbilisi': 'ge',
  'azerbaijan': 'az',
  'baku': 'az',
  'kazakhstan': 'kz',
  'india': 'in',
  'mumbai': 'in',
  'singapore': 'sg',
  'indonesia': 'id',
  'malaysia': 'my',
  'thailand': 'th',
  'vietnam': 'vn',
  'philippines': 'ph',
  'japan': 'jp',
  'tokyo': 'jp',
  'korea': 'kr',
  'seoul': 'kr',
  'china': 'cn',
  'hong kong': 'hk',
  'taiwan': 'tw',
  'australia': 'au',
  'sydney': 'au',
  'new zealand': 'nz',
  'brazil': 'br',
  'argentina': 'ar',
  'chile': 'cl',
  'mexico': 'mx',
  'egypt': 'eg',
  'morocco': 'ma',
  'algeria': 'dz',
  'tunisia': 'tn',
  'south africa': 'za',
  'nigeria': 'ng',
  'kenya': 'ke',
  'israel': 'il',
  'pakistan': 'pk',
  'bangladesh': 'bd',
  'sri lanka': 'lk',
  'nepal': 'np',
  'russia': 'ru',
  'moscow': 'ru',
  'ukraine': 'ua',
  'poland': 'pl',
  'warsaw': 'pl',
  'ireland': 'ie',
  'dublin': 'ie',
  'iceland': 'is',
  'luxembourg': 'lu',
  'moldova': 'md',
  'serbia': 'rs',
  'croatia': 'hr',
  'slovakia': 'sk',
  'slovenia': 'si',
  'lithuania': 'lt',
  'latvia': 'lv',
  'estonia': 'ee',
  'belarus': 'by',
  'qatar': 'qa',
  'oman': 'om',
  'saudi': 'sa',
  'kuwait': 'kw',
  'bahrain': 'bh',
  'jordan': 'jo',
  'lebanon': 'lb',
  'iraq': 'iq',
};

class VpnNode {
  const VpnNode({
    required this.id,
    required this.name,
    required this.protocol,
    required this.host,
    required this.port,
    required this.sourceId,
    required this.params,
    this.pingMs = 0,
    this.jitterMs = 0,
    this.stability = 0,
    this.favorite = false,
    this.disabled = false,
    this.checkedAt,
    this.raw = '',
  });

  final String id;
  final String name;
  final NodeProtocol protocol;
  final String host;
  final int port;
  final String sourceId;
  final Map<String, dynamic> params;
  final int pingMs;
  final int jitterMs;
  final double stability;
  final bool favorite;
  final bool disabled;
  final DateTime? checkedAt;
  final String raw;

  bool get hasPing => pingMs > 0;

  /// پرچم کشور این سرور از پارامترها، نام یا منطقه زمانی آن استخراج می شود؛
  /// اگر پیدا نشد، رشته خالی برمی گردد و برنامه پرچم نشان نمی دهد.
  ///
  /// **گزارش ۱٫۰۱۸:** نام سرورهای اشتراک «سرور آمبرلا (خودکار) tls_h2 grpc
  /// CDN vless» است؛ هیچ نام کشوری در آن نیست، پس پرچم هم پیدا نمی شد. حالا
  /// پس از پارامترها و نام، منطقه زمانی گره (`timezone` مثل `Europe/Berlin`)
  /// هم خوانده می شود که در بیشتر اشتراک ها هست.
  String get flagCode {
    final String fromParams = JsonX.text(
      params['countryCode'] ??
          params['country_code'] ??
          params['flag'] ??
          params['cc'],
    ).toLowerCase();
    if (fromParams.length == 2) {
      return fromParams;
    }
    final String text = name.toLowerCase();
    for (final MapEntry<String, String> entry
        in countryAliases.entries) {
      if (text.contains(entry.key)) {
        return entry.value;
      }
    }
    // میزبان سرور: `de1.example.com` یا `germany.example.com`.
    final String hostText = host.toLowerCase();
    for (final MapEntry<String, String> entry
        in countryAliases.entries) {
      if (entry.key.length >= 4 && hostText.contains(entry.key)) {
        return entry.value;
      }
    }
    // منطقه زمانی گره، مثل `Europe/Berlin` یا `Asia/Tehran`.
    final String zone = JsonX.text(
      params['timezone'] ?? params['time_zone'] ?? params['tz'],
    ).toLowerCase();
    if (zone.isNotEmpty) {
      final String city = zone.split('/').last;
      for (final MapEntry<String, String> entry
          in countryAliases.entries) {
        if (city.contains(entry.key)) {
          return entry.value;
        }
      }
      for (final MapEntry<String, String> zoneEntry
          in _timezoneCities.entries) {
        if (city.contains(zoneEntry.key)) {
          return zoneEntry.value;
        }
      }
    }
    return '';
  }

  /// شهرهای رایج در منطقه زمانی که نامشان در [countryAliases] نیست.
  static const Map<String, String> _timezoneCities = <String, String>{
  'berlin': 'de',
  'amsterdam': 'nl',
  'frankfurt': 'de',
  'paris': 'fr',
  'london': 'gb',
  'stockholm': 'se',
  'helsinki': 'fi',
  'istanbul': 'tr',
  'dubai': 'ae',
  'tehran': 'ir',
  'warsaw': 'pl',
  'vienna': 'at',
  'zurich': 'ch',
  'madrid': 'es',
  'rome': 'it',
  'milan': 'it',
  'moscow': 'ru',
  'kyiv': 'ua',
  'kiev': 'ua',
  'tokyo': 'jp',
  'seoul': 'kr',
  'singapore': 'sg',
  'hongkong': 'hk',
  'shanghai': 'cn',
  'taipei': 'tw',
  'sydney': 'au',
  'auckland': 'nz',
  'toronto': 'ca',
  'vancouver': 'ca',
  'newyork': 'us',
  'chicago': 'us',
  'denver': 'us',
  'losangeles': 'us',
  'saopaulo': 'br',
  'buenosaires': 'ar',
  'santiago': 'cl',
  'mexicocity': 'mx',
  'cairo': 'eg',
  'johannesburg': 'za',
  'telaviv': 'il',
  'jerusalem': 'il',
  'riyadh': 'sa',
  'doha': 'qa',
  'kuwait': 'kw',
  'manama': 'bh',
  'muscat': 'om',
  'beirut': 'lb',
  'amman': 'jo',
  'baghdad': 'iq',
  'karachi': 'pk',
  'mumbai': 'in',
  'delhi': 'in',
  'dhaka': 'bd',
  'bangkok': 'th',
  'jakarta': 'id',
  'kualalumpur': 'my',
  'manila': 'ph',
  'hanoi': 'vn',
  'yerevan': 'am',
  'tbilisi': 'ge',
  'baku': 'az',
  'almaty': 'kz',
  'minsk': 'by',
  'chisinau': 'md',
  'bucharest': 'ro',
  'sofia': 'bg',
  'budapest': 'hu',
  'prague': 'cz',
  'athens': 'gr',
  'nicosia': 'cy',
  'riga': 'lv',
  'vilnius': 'lt',
  'tallinn': 'ee',
  'zagreb': 'hr',
  'bratislava': 'sk',
  'ljubljana': 'si',
  'belgrade': 'rs',
  'reykjavik': 'is',
  'luxembourg': 'lu',
  'dublin': 'ie',
};

  String get quality {
    if (!hasPing) {
      return 'سنجیده نشده';
    }
    if (pingMs < 120) {
      return 'عالی';
    }
    if (pingMs < 250) {
      return 'خوب';
    }
    if (pingMs < 450) {
      return 'متوسط';
    }
    return 'ضعیف';
  }

  VpnNode copyWith({
    String? name,
    int? pingMs,
    int? jitterMs,
    double? stability,
    bool? favorite,
    bool? disabled,
    DateTime? checkedAt,
  }) {
    return VpnNode(
      id: id,
      name: name ?? this.name,
      protocol: protocol,
      host: host,
      port: port,
      sourceId: sourceId,
      params: params,
      pingMs: pingMs ?? this.pingMs,
      jitterMs: jitterMs ?? this.jitterMs,
      stability: stability ?? this.stability,
      favorite: favorite ?? this.favorite,
      disabled: disabled ?? this.disabled,
      checkedAt: checkedAt ?? this.checkedAt,
      raw: raw,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'protocol': protocol.name,
        'host': host,
        'port': port,
        'sourceId': sourceId,
        'params': params,
        'pingMs': pingMs,
        'jitterMs': jitterMs,
        'stability': stability,
        'favorite': favorite,
        'disabled': disabled,
        'checkedAt': checkedAt?.toIso8601String(),
        'raw': raw,
      };

  factory VpnNode.fromJson(Map<String, dynamic> json) {
    return VpnNode(
      id: JsonX.text(json['id']),
      name: JsonX.text(json['name'], 'سرور بی نام'),
      protocol: NodeProtocol.values.firstWhere(
        (NodeProtocol item) => item.name == JsonX.text(json['protocol']),
        orElse: () => NodeProtocol.vless,
      ),
      host: JsonX.text(json['host']),
      port: JsonX.integer(json['port']),
      sourceId: JsonX.text(json['sourceId']),
      params: JsonX.asMap(json['params']),
      pingMs: JsonX.integer(json['pingMs']),
      jitterMs: JsonX.integer(json['jitterMs']),
      stability: JsonX.number(json['stability']),
      favorite: JsonX.boolean(json['favorite']),
      disabled: JsonX.boolean(json['disabled']),
      checkedAt: JsonX.dateTime(json['checkedAt']),
      raw: JsonX.text(json['raw']),
    );
  }
}

/// پروفایل و مصرف کاربر، همان شکلی که پنل برمی گرداند.
class Account {
  const Account({
    this.panelId = 0,
    this.uuid = '',
    this.name = '',
    this.phone = '',
    this.telegramId = '',
    this.comment = '',
    this.enable = true,
    this.isActive = false,
    this.usageLimitGb = 0,
    this.currentUsageGb = 0,
    this.packageDays = 0,
    this.startDate,
    this.expiryDate,
    this.lastResetTime,
    this.lastOnline,
    this.mode = '',
    this.lang = 'fa',
    this.wgIpv4 = '',
    this.wgIpv6 = '',
    this.awgIpv4 = '',
    this.awgIpv6 = '',
    this.subscriptionUrl = '',
    this.accountBase = '',
  });

  final int panelId;
  final String uuid;
  final String name;
  final String phone;
  final String telegramId;
  final String comment;
  final bool enable;
  final bool isActive;
  final double usageLimitGb;
  final double currentUsageGb;
  final int packageDays;
  final DateTime? startDate;
  final DateTime? expiryDate;
  final DateTime? lastResetTime;
  final DateTime? lastOnline;
  final String mode;
  final String lang;
  final String wgIpv4;
  final String wgIpv6;
  final String awgIpv4;
  final String awgIpv6;
  final String subscriptionUrl;
  final String accountBase;

  Account copyWith({
    int? panelId,
    String? uuid,
    String? name,
    String? phone,
    String? telegramId,
    String? comment,
    bool? enable,
    bool? isActive,
    double? usageLimitGb,
    double? currentUsageGb,
    int? packageDays,
    DateTime? startDate,
    DateTime? expiryDate,
    bool clearExpiryDate = false,
    DateTime? lastResetTime,
    DateTime? lastOnline,
    String? mode,
    String? lang,
    String? wgIpv4,
    String? wgIpv6,
    String? awgIpv4,
    String? awgIpv6,
    String? subscriptionUrl,
    String? accountBase,
  }) {
    return Account(
      panelId: panelId ?? this.panelId,
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      telegramId: telegramId ?? this.telegramId,
      comment: comment ?? this.comment,
      enable: enable ?? this.enable,
      isActive: isActive ?? this.isActive,
      usageLimitGb: usageLimitGb ?? this.usageLimitGb,
      currentUsageGb: currentUsageGb ?? this.currentUsageGb,
      packageDays: packageDays ?? this.packageDays,
      startDate: startDate ?? this.startDate,
      expiryDate: clearExpiryDate ? null : (expiryDate ?? this.expiryDate),
      lastResetTime: lastResetTime ?? this.lastResetTime,
      lastOnline: lastOnline ?? this.lastOnline,
      mode: mode ?? this.mode,
      lang: lang ?? this.lang,
      wgIpv4: wgIpv4 ?? this.wgIpv4,
      wgIpv6: wgIpv6 ?? this.wgIpv6,
      awgIpv4: awgIpv4 ?? this.awgIpv4,
      awgIpv6: awgIpv6 ?? this.awgIpv6,
      subscriptionUrl: subscriptionUrl ?? this.subscriptionUrl,
      accountBase: accountBase ?? this.accountBase,
    );
  }

  /// سقف حجم بسته به گیگابایت (همان عدد پنل).
  double get totalGb => usageLimitGb;

  /// بسته بدون سقف حجم.
  bool get unlimited => usageLimitGb <= 0;

  /// مصرف از سقف گذشته است.
  bool get overLimit => usageLimitGb > 0 && currentUsageGb > usageLimitGb;

  double get remainingGb {
    final double remaining = usageLimitGb - currentUsageGb;
    return remaining < 0 ? 0 : remaining;
  }

  double get usagePercent {
    if (usageLimitGb <= 0) {
      return 0;
    }
    return ((currentUsageGb / usageLimitGb) * 100).clamp(0, 100);
  }

  double get remainingPercent {
    if (usageLimitGb <= 0) {
      return 100;
    }
    return (100 - usagePercent).clamp(0, 100);
  }

  /// تاریخ انقضای موثر: اگر سرور تاریخ صریح نداده باشد، دقیقاً از
  /// `start_date + package_days` در تقویم رسمی تهران محاسبه می شود.
  DateTime? get effectiveExpiryDate {
    if (expiryDate != null) {
      return expiryDate;
    }
    if (startDate != null && packageDays > 0) {
      final DateTime s = Fa.toTehran(startDate!);
      return DateTime.utc(
        s.year,
        s.month,
        s.day + packageDays,
        s.hour,
        s.minute,
        s.second,
      ).subtract(Fa.tehranOffset);
    }
    return null;
  }

  /// زمان دقیق باقی مانده تا پایان اعتبار اشتراک.
  Duration remainingDuration([DateTime? now]) {
    final DateTime? end = effectiveExpiryDate;
    if (end == null) {
      return Duration.zero;
    }
    final Duration diff = end.toUtc().difference((now ?? DateTime.now()).toUtc());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// زمان دقیق سپری شده از تاریخ شروع اشتراک.
  Duration elapsedDuration([DateTime? now]) {
    if (startDate == null) {
      return Duration.zero;
    }
    final Duration diff =
        (now ?? DateTime.now()).toUtc().difference(startDate!.toUtc());
    return diff.isNegative ? Duration.zero : diff;
  }

  int daysLeftAt([DateTime? now]) {
    final DateTime? end = effectiveExpiryDate;
    if (end == null) {
      return 0;
    }
    final Duration rem = remainingDuration(now);
    if (rem <= Duration.zero) {
      return 0;
    }
    return rem.inHours ~/ 24;
  }

  int get daysLeft => daysLeftAt();

  int daysElapsedAt([DateTime? now]) => elapsedDuration(now).inDays;

  /// درصد زمان سپری شده از کل دوره بسته (۰ تا ۱۰۰).
  double timeElapsedPercent([DateTime? now]) {
    final DateTime? end = effectiveExpiryDate;
    if (startDate == null || end == null) {
      return 0;
    }
    final int totalSeconds =
        end.toUtc().difference(startDate!.toUtc()).inSeconds;
    if (totalSeconds <= 0) {
      return 100;
    }
    final int usedSeconds = elapsedDuration(now).inSeconds;
    return ((usedSeconds / totalSeconds) * 100).clamp(0, 100);
  }

  /// درصد اعتبار زمانی باقی مانده از کل دوره بسته (۰ تا ۱۰۰).
  double timeRemainingPercent([DateTime? now]) {
    if (effectiveExpiryDate == null) {
      return 100;
    }
    if (startDate == null) {
      return isExpiredAt(now) ? 0 : 100;
    }
    return (100 - timeElapsedPercent(now)).clamp(0, 100);
  }

  /// میانگین مصرف روزانه بر حسب گیگابایت از تاریخ شروع بسته.
  double dailyAverageGb([DateTime? now]) {
    if (currentUsageGb <= 0 || startDate == null) {
      return 0;
    }
    final double days = elapsedDuration(now).inSeconds / 86400.0;
    if (days < 1) {
      return currentUsageGb;
    }
    return currentUsageGb / days;
  }

  bool isExpiredAt([DateTime? now]) {
    final DateTime? end = effectiveExpiryDate;
    if (end == null) {
      return false;
    }
    return end.toUtc().isBefore((now ?? DateTime.now()).toUtc());
  }

  bool get expired => isExpiredAt();

  /// آیا حساب طی ۵ دقیقه اخیر در پنل آنلاین گزارش شده است؟
  bool isOnlineRecently([DateTime? now]) {
    if (lastOnline == null) {
      return false;
    }
    final int diff =
        (now ?? DateTime.now()).toUtc().difference(lastOnline!.toUtc()).inSeconds;
    return diff >= -300 && diff <= 300;
  }

  static bool _looksLikePhone(String text) {
    final String digits = Fa.toEn(text).replaceAll(RegExp(r'[\s\-()]'), '').trim();
    return RegExp(r'^(?:\+?98|0)?9\d{9}$').hasMatch(digits);
  }

  /// شماره همراه موثر کاربر (از فیلد phone یا comment پنل).
  String get effectivePhone {
    if (phone.trim().isNotEmpty) {
      return phone.trim();
    }
    if (_looksLikePhone(comment)) {
      return comment.trim();
    }
    return '';
  }

  String get displayName {
    if (name.trim().isNotEmpty) {
      return Fa.num(name.trim());
    }
    if (comment.trim().isNotEmpty && !_looksLikePhone(comment)) {
      return Fa.num(comment.trim());
    }
    return 'کاربر آمبرلا';
  }

  /// نوع سرویس بر اساس اطلاعات پنل، کاملاً فارسی.
  String get planLabel {
    if (comment.trim().isNotEmpty && !_looksLikePhone(comment)) {
      return Fa.num(comment.trim());
    }
    if (packageDays > 0) {
      return 'بسته ${Fa.num(packageDays)} روزه';
    }
    if (usageLimitGb > 0) {
      return 'بسته حجمی';
    }
    return 'اشتراک استاندارد';
  }

  /// عنوان کامل فارسی مدت بسته (مثلاً «یک ساله (۳۶۵ روز)»).
  String get packageDurationLabel => Fa.packageTitleFa(packageDays);

  /// برچسب کاملاً فارسی حالت بازنشانی حجم در پنل.
  String get modeLabelFa {
    switch (mode.trim().toLowerCase()) {
      case 'no_reset':
        return 'بدون بازنشانی دوره ای';
      case 'monthly':
        return 'بازنشانی ماهانه';
      case 'weekly':
        return 'بازنشانی هفتگی';
      case 'daily':
        return 'بازنشانی روزانه';
      case 'on_first_use':
        return 'شروع با اولین اتصال';
      case '':
        return 'استاندارد';
      default:
        return 'اختصاصی';
    }
  }

  /// برچسب کاملاً فارسی زبان حساب کاربری در پنل.
  String get langLabelFa {
    switch (lang.trim().toLowerCase()) {
      case 'fa':
      case '':
        return 'فارسی';
      case 'en':
        return 'انگلیسی';
      case 'ar':
        return 'عربی';
      case 'tr':
        return 'ترکی';
      case 'ru':
        return 'روسی';
      case 'zh':
        return 'چینی';
      default:
        return 'فارسی';
    }
  }

  /// وضعیت خلاصه و کاملاً فارسی اشتراک.
  String get statusLabelFa {
    if (!enable) {
      return 'مسدود شده';
    }
    if (expired) {
      return 'منقضی شده';
    }
    if (quotaFinished) {
      return 'اتمام حجم';
    }
    if (!isActive) {
      return 'غیرفعال';
    }
    return 'فعال و مجاز';
  }

  /// نشان می دهد حساب سالم است: فعال، منقضی نشده و غیرفعال نشده.
  bool get healthy => enable && !expired && !quotaFinished;

  /// حجم بسته تمام شده است.
  bool get quotaFinished => usageLimitGb > 0 && currentUsageGb >= usageLimitGb;

  /// اجازه اتصال به سرورها. اگر حساب منقضی، غیرفعال، مسدود یا حجمش تمام شده
  /// باشد، اتصال ممنوع است و برنامه باید همین را به کاربر بگوید.
  bool get canConnect => enable && isActive && !expired && !quotaFinished;

  /// دلیل بسته بودن دسترسی، به فارسی؛ اگر دسترسی باز باشد رشته خالی است.
  String get accessReason {
    final List<String> reasons = <String>[];
    if (!enable) {
      reasons.add('حساب شما مسدود شده است');
    }
    if (!isActive) {
      reasons.add('اشتراک شما فعال نیست');
    }
    if (expired) {
      reasons.add('اشتراک شما منقضی شده است');
    }
    if (quotaFinished) {
      reasons.add('حجم اشتراک شما تمام شده است');
    }
    if (reasons.isEmpty) {
      return '';
    }
    return '${reasons.join(' و ')}؛ برای ادامه باید اشتراک را تمدید کنید.';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': panelId,
        'uuid': uuid,
        'name': name,
        'phone': phone,
        'telegram_id': telegramId,
        'comment': comment,
        'enable': enable,
        'is_active': isActive,
        'usage_limit_GB': usageLimitGb,
        'current_usage_GB': currentUsageGb,
        'package_days': packageDays,
        'start_date': startDate?.toUtc().toIso8601String(),
        'expiry_date': expiryDate?.toUtc().toIso8601String(),
        'last_reset_time': lastResetTime?.toUtc().toIso8601String(),
        'last_online': lastOnline?.toUtc().toIso8601String(),
        'mode': mode,
        'lang': lang,
        'wg_ipv4': wgIpv4,
        'wg_ipv6': wgIpv6,
        'awg_ipv4': awgIpv4,
        'awg_ipv6': awgIpv6,
        'subscription_url': subscriptionUrl,
        'account_base': accountBase,
      };

  factory Account.fromJson(Map<String, dynamic> json) {
    final Object? expiry =
        json['expiry_date'] ?? json['expire_date'] ?? json['end_date'];
    final String rawTelegram = JsonX.text(json['telegram_id']);
    return Account(
      panelId: JsonX.integer(json['id']),
      uuid: JsonX.text(json['uuid']),
      name: JsonX.text(json['name']),
      phone: JsonX.text(json['phone']),
      telegramId: rawTelegram == '0' ? '' : rawTelegram,
      comment: JsonX.text(json['comment']),
      enable: JsonX.boolean(json['enable'], fallback: true),
      isActive: JsonX.boolean(json['is_active']),
      usageLimitGb: JsonX.number(json['usage_limit_GB']),
      currentUsageGb: JsonX.number(json['current_usage_GB']),
      packageDays: JsonX.integer(json['package_days']),
      startDate: Fa.parseServerDateTime(json['start_date']),
      expiryDate: Fa.parseServerDateTime(expiry),
      lastResetTime: Fa.parseServerDateTime(json['last_reset_time']),
      lastOnline: Fa.parseServerDateTime(json['last_online']),
      mode: JsonX.text(json['mode']),
      lang: JsonX.text(json['lang'], 'fa'),
      wgIpv4: JsonX.text(json['wg_ipv4']),
      wgIpv6: JsonX.text(json['wg_ipv6']),
      awgIpv4: JsonX.text(json['awg_ipv4']),
      awgIpv6: JsonX.text(json['awg_ipv6']),
      subscriptionUrl: JsonX.text(
        json['subscription_url'] ?? json['sub_link'],
      ),
      accountBase: JsonX.text(json['account_base']),
    );
  }

  static const Account empty = Account();
}

class FilterSettings {
  const FilterSettings({
    this.enabled = false,
    this.categories = const <String>[],
    this.customDomains = const <String>[],
    this.updatedBy = 'app',
    this.updatedAt = '',
  });

  final bool enabled;
  final List<String> categories;
  final List<String> customDomains;
  final String updatedBy;
  final String updatedAt;

  /// حداکثر تعداد دامنه های سفارشی برای هر حساب (همگام با ربات تلگرام).
  static const int maxCustomDomains = 200;

  /// دسته های رسمی کنترل محتوا؛ دقیقاً یکسان با ربات تلگرام (`BOT_CATEGORIES`).
  static const Map<String, String> categoryLabels = <String, String>{
    'adult': 'محتوای بزرگسال',
    'gambling': 'شرط بندی',
    'ads': 'تبلیغات',
    'dating': 'دوستیابی',
  };

  static const Map<String, String> categorySubtitles = <String, String>{
    'adult': 'مسدودسازی دامنه ها و سایت های بزرگسال',
    'gambling': 'مسدودسازی سایت های قمار و شرط بندی',
    'ads': 'حذف تبلیغات مزاحم و ردیاب ها',
    'dating': 'مسدودسازی شبکه ها و سایت های دوستیابی',
  };

  /// دامنه های زیرساخت خود آمبرلا که مسدودسازی آن ها همگام سازی فیلتر را قفل می کند.
  static Set<String> get _protectedSuffixes {
    final Set<String> out = <String>{'umbrella-vpn.ir'};
    final String? gwHost = Uri.tryParse(AppConfig.gatewayBase)?.host.toLowerCase();
    if (gwHost != null && gwHost.isNotEmpty) {
      out.add(gwHost.startsWith('www.') ? gwHost.substring(4) : gwHost);
    }
    return out;
  }

  /// دسته های فعال مطابق با چهار دسته ربات تلگرام.
  List<String> get activeBotCategories =>
      categoryLabels.keys.where(categories.contains).toList(growable: false);

  /// نرمال سازی دامنه یا پسوند دامنه (مانند `example.com`، `https://www.site.org/a`، `*.ads.net` یا پونی کد).
  static String? normalizeDomainSuffix(String input) {
    String value = Fa.toEn(input).trim();
    if (value.isEmpty) {
      return null;
    }
    value = value.replaceAll(
      RegExp(r'[\u200B-\u200F\u202A-\u202E\u2060\uFEFF]'),
      '',
    );
    value = value.replaceAll(RegExp('^["\'`<>()\\[\\]{}+\\s]+|["\'`<>()\\[\\]{}\\s]+\$'), '');
    if (value.isEmpty) {
      return null;
    }
    value = value.toLowerCase();
    value = value.replaceFirst(RegExp(r'^[a-z][a-z0-9+.-]*://'), '');
    while (value.startsWith('/')) {
      value = value.substring(1);
    }
    for (final String delimiter in const <String>['/', '?', '#', '\\']) {
      final int idx = value.indexOf(delimiter);
      if (idx >= 0) {
        value = value.substring(0, idx);
      }
    }
    final int at = value.lastIndexOf('@');
    if (at >= 0) {
      value = value.substring(at + 1);
    }
    if (value.startsWith('[') || value.contains(':')) {
      final RegExpMatch? portMatch =
          RegExp(r'^([^:]+):(\d{1,5})$').firstMatch(value);
      if (portMatch == null) {
        return null;
      }
      value = portMatch.group(1)!;
    }
    while (value.startsWith('.') || value.startsWith('*')) {
      value = value.substring(1);
    }
    while (value.endsWith('.')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.startsWith('www.') && value.indexOf('.', 4) > 4) {
      value = value.substring(4);
    }
    if (value.length < 4 ||
        value.length > 253 ||
        value.contains(' ') ||
        value.contains('..')) {
      return null;
    }
    if (InternetAddress.tryParse(value) != null ||
        RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(value)) {
      return null;
    }
    if (value == 'localhost' ||
        value.endsWith('.localhost') ||
        value.endsWith('.local') ||
        value.endsWith('.internal') ||
        value.endsWith('.home.arpa') ||
        value.endsWith('.lan')) {
      return null;
    }
    final List<String> labels = value.split('.');
    if (labels.length < 2) {
      return null;
    }
    final RegExp labelRule =
        RegExp(r'^(?:xn--)?[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');
    for (final String label in labels) {
      if (label.isEmpty || label.length > 63 || !labelRule.hasMatch(label)) {
        return null;
      }
    }
    final String tld = labels.last;
    if (RegExp(r'^\d+$').hasMatch(tld) || tld.length < 2) {
      return null;
    }
    for (final String protected in _protectedSuffixes) {
      if (value == protected || value.endsWith('.$protected')) {
        return null;
      }
    }
    return value;
  }

  /// تجزیه یک یا چند دامنه/لینک جداشده با فاصله، خط جدید یا ویرگول فارسی/لاتین.
  static ({List<String> valid, List<String> invalid}) parseDomainInputs(
    String raw,
  ) {
    final String cleaned =
        raw.replaceAll('،', ',').replaceAll('؛', ';').replaceAll('\r', '\n');
    final List<String> valid = <String>[];
    final List<String> invalid = <String>[];
    for (final String piece in cleaned.split(RegExp(r'[\s,;]+'))) {
      final String token = piece.trim();
      if (token.isEmpty) {
        continue;
      }
      final String? domain = normalizeDomainSuffix(token);
      if (domain == null) {
        if (!invalid.contains(token)) {
          invalid.add(token);
        }
      } else if (!valid.contains(domain)) {
        valid.add(domain);
      }
    }
    return (valid: valid, invalid: invalid);
  }

  List<String> get normalizedCustomDomains {
    final Set<String> seen = <String>{};
    for (final String item in customDomains) {
      final String? normalized = normalizeDomainSuffix(item);
      if (normalized != null) {
        seen.add(normalized);
        if (seen.length >= maxCustomDomains) {
          break;
        }
      }
    }
    return seen.toList(growable: false);
  }

  bool get hasConfiguredRules =>
      activeBotCategories.isNotEmpty || normalizedCustomDomains.isNotEmpty;

  bool get hasActiveRules => enabled && hasConfiguredRules;

  /// افزودن یک یا چند دامنه سفارشی و روشن کردن خودکار کنترل محتوا.
  ({
    FilterSettings settings,
    List<String> added,
    List<String> duplicates,
    List<String> skippedLimit,
  }) addCustomDomains(Iterable<String> domains) {
    final List<String> next = normalizedCustomDomains.toList();
    final List<String> added = <String>[];
    final List<String> duplicates = <String>[];
    final List<String> skippedLimit = <String>[];
    for (final String raw in domains) {
      final String? clean = normalizeDomainSuffix(raw);
      if (clean == null) {
        continue;
      }
      if (next.contains(clean)) {
        if (!duplicates.contains(clean)) {
          duplicates.add(clean);
        }
        continue;
      }
      if (next.length >= maxCustomDomains) {
        skippedLimit.add(clean);
        continue;
      }
      next.add(clean);
      added.add(clean);
    }
    if (added.isEmpty) {
      return (
        settings: this,
        added: added,
        duplicates: duplicates,
        skippedLimit: skippedLimit,
      );
    }
    return (
      settings: copyWith(enabled: true, customDomains: next),
      added: added,
      duplicates: duplicates,
      skippedLimit: skippedLimit,
    );
  }

  /// حذف یک دامنه سفارشی؛ اگر هیچ دسته و دامنه ای باقی نماند فیلتر خاموش می شود.
  FilterSettings removeCustomDomain(String domain) {
    final String target = normalizeDomainSuffix(domain) ?? domain.trim().toLowerCase();
    final List<String> next = normalizedCustomDomains
        .where((String item) => item != target)
        .toList(growable: false);
    if (next.length == normalizedCustomDomains.length) {
      return this;
    }
    return copyWith(
      enabled: enabled && (activeBotCategories.isNotEmpty || next.isNotEmpty),
      customDomains: next,
    );
  }

  /// حذف یکجای همه دامنه های سفارشی با حفظ وضعیت دسته های فعال.
  FilterSettings clearCustomDomains() {
    if (normalizedCustomDomains.isEmpty) {
      return this;
    }
    return copyWith(
      enabled: enabled && activeBotCategories.isNotEmpty,
      customDomains: const <String>[],
    );
  }

  String get sourceLabel => switch (updatedBy.trim().toLowerCase()) {
        'bot' || 'telegram' => 'ربات تلگرام',
        'app' || 'windows' => 'برنامه ویندوز',
        _ => 'همگام با ربات',
      };

  String get effectSignature {
    if (!enabled) {
      return 'off';
    }
    final List<String> cats = activeBotCategories.toList()..sort();
    final List<String> doms = normalizedCustomDomains.toList()..sort();
    return 'on|${cats.join(',')}|${doms.join(',')}';
  }

  bool sameEffectAs(FilterSettings other) =>
      effectSignature == other.effectSignature;

  bool sameAs(FilterSettings other) =>
      sameEffectAs(other) &&
      updatedBy == other.updatedBy &&
      updatedAt == other.updatedAt;

  /// تغییر وضعیت یک دسته دقیقاً مشابه دکمه های کنترل محتوا در ربات تلگرام.
  FilterSettings toggleCategory(String key) {
    if (!categoryLabels.containsKey(key)) {
      return this;
    }
    final List<String> next = activeBotCategories.toList();
    if (next.contains(key)) {
      next.remove(key);
    } else {
      next.add(key);
    }
    return copyWith(
      enabled: next.isNotEmpty || normalizedCustomDomains.isNotEmpty,
      categories: next,
    );
  }

  FilterSettings copyWith({
    bool? enabled,
    List<String>? categories,
    List<String>? customDomains,
    String? updatedBy,
    String? updatedAt,
  }) {
    final List<String> rawCategories = categories ?? this.categories;
    final List<String> cleanCategories =
        categoryLabels.keys.where(rawCategories.contains).toList();
    return FilterSettings(
      enabled: enabled ?? this.enabled,
      categories: cleanCategories,
      customDomains: customDomains ?? this.customDomains,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'enabled': enabled,
        'categories': activeBotCategories,
        'custom_domains': normalizedCustomDomains,
        if (updatedBy.isNotEmpty) 'updated_by': updatedBy,
        if (updatedAt.isNotEmpty) 'updated_at': updatedAt,
      };

  factory FilterSettings.fromJson(Map<String, dynamic> json) {
    final Set<String> incoming = JsonX.asList(json['categories'])
        .map((Object? item) => item.toString().trim().toLowerCase())
        .toSet();
    final List<String> botMatched =
        categoryLabels.keys.where(incoming.contains).toList();
    final List<String> domains = <String>[];
    for (final Object? item in JsonX.asList(json['custom_domains'])) {
      final String? clean = normalizeDomainSuffix(item.toString());
      if (clean != null && !domains.contains(clean)) {
        domains.add(clean);
      }
    }
    return FilterSettings(
      enabled: JsonX.boolean(json['enabled']),
      categories: botMatched,
      customDomains: domains,
      updatedBy: JsonX.text(json['updated_by'], 'app'),
      updatedAt: JsonX.text(json['updated_at']),
    );
  }

  static const FilterSettings empty = FilterSettings();
}

/// وضعیت اشتراک رایگان خوش آمدگویی و اشتراک نوروزی (همگام با ربات تلگرام).
class SubscriptionOffers {
  const SubscriptionOffers({
    this.freeAvailable = false,
    this.freeClaimed = false,
    this.freeGb = 1,
    this.freeDays = 1,
    this.nowruzMenuEnabled = false,
    this.nowruzAvailable = false,
    this.nowruzClaimed = false,
    this.nowruzGb = 5,
    this.nowruzDays = 13,
  });

  final bool freeAvailable;
  final bool freeClaimed;
  final int freeGb;
  final int freeDays;
  final bool nowruzMenuEnabled;
  final bool nowruzAvailable;
  final bool nowruzClaimed;
  final int nowruzGb;
  final int nowruzDays;

  bool get showFree => freeAvailable && !freeClaimed;
  bool get showNowruz => nowruzMenuEnabled && nowruzAvailable && !nowruzClaimed;
  bool get hasVisibleOffer => showFree || showNowruz;

  bool sameAs(SubscriptionOffers other) =>
      freeAvailable == other.freeAvailable &&
      freeClaimed == other.freeClaimed &&
      freeGb == other.freeGb &&
      freeDays == other.freeDays &&
      nowruzMenuEnabled == other.nowruzMenuEnabled &&
      nowruzAvailable == other.nowruzAvailable &&
      nowruzClaimed == other.nowruzClaimed &&
      nowruzGb == other.nowruzGb &&
      nowruzDays == other.nowruzDays;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'free_available': freeAvailable,
        'free_claimed': freeClaimed,
        'free_gb': freeGb,
        'free_days': freeDays,
        'nowruz_menu_enabled': nowruzMenuEnabled,
        'nowruz_available': nowruzAvailable,
        'nowruz_claimed': nowruzClaimed,
        'nowruz_gb': nowruzGb,
        'nowruz_days': nowruzDays,
      };

  factory SubscriptionOffers.fromJson(Map<String, dynamic> json) {
    if (json.isEmpty) {
      return empty;
    }
    return SubscriptionOffers(
      freeAvailable: JsonX.boolean(json['free_available']),
      freeClaimed: JsonX.boolean(json['free_claimed']),
      freeGb: JsonX.integer(json['free_gb'], 1),
      freeDays: JsonX.integer(json['free_days'], 1),
      nowruzMenuEnabled: JsonX.boolean(json['nowruz_menu_enabled']),
      nowruzAvailable: JsonX.boolean(json['nowruz_available']),
      nowruzClaimed: JsonX.boolean(json['nowruz_claimed']),
      nowruzGb: JsonX.integer(json['nowruz_gb'], 5),
      nowruzDays: JsonX.integer(json['nowruz_days'], 13),
    );
  }

  static const SubscriptionOffers empty = SubscriptionOffers();
}

class SessionData {
  const SessionData({
    required this.token,
    required this.uuid,
    required this.deviceId,
    required this.account,
    required this.filter,
    this.offers = SubscriptionOffers.empty,
    this.signedInAt,
  });

  final String token;
  final String uuid;
  final String deviceId;
  final Account account;
  final FilterSettings filter;
  final SubscriptionOffers offers;
  final DateTime? signedInAt;

  /// کلید پایدار مالک نشست برای تفکیک تاریخچه اعلان ها بین حساب های متفاوت.
  String get ownerKey {
    final String acc = account.uuid.trim();
    if (acc.isNotEmpty) {
      return acc;
    }
    return uuid.trim();
  }

  SessionData copyWith({
    Account? account,
    FilterSettings? filter,
    SubscriptionOffers? offers,
  }) {
    return SessionData(
      token: token,
      uuid: uuid,
      deviceId: deviceId,
      account: account ?? this.account,
      filter: filter ?? this.filter,
      offers: offers ?? this.offers,
      signedInAt: signedInAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'token': token,
        'uuid': uuid,
        'device_id': deviceId,
        'account': account.toJson(),
        'filter': filter.toJson(),
        'offers': offers.toJson(),
        'signed_in_at': signedInAt?.toIso8601String(),
      };

  factory SessionData.fromJson(Map<String, dynamic> json) {
    return SessionData(
      token: JsonX.text(json['token']),
      uuid: JsonX.text(json['uuid']),
      deviceId: JsonX.text(json['device_id']),
      account: Account.fromJson(JsonX.asMap(json['account'])),
      filter: FilterSettings.fromJson(JsonX.asMap(json['filter'])),
      offers: SubscriptionOffers.fromJson(JsonX.asMap(json['offers'])),
      signedInAt: JsonX.dateTime(json['signed_in_at']),
    );
  }
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.level,
    required this.sentAt,
    this.read = false,
    this.delivered,
  });

  final int id;
  final String title;
  final String body;
  final String level;
  final DateTime? sentAt;
  final bool read;

  /// وضعیت تحویل قبلی در سرور؛ وقتی `true` است یعنی اعلان مربوط به گذشته بوده
  /// و برای نمایش تاریخچه برگردانده شده است (نباید دوباره صدا یا بالون بدهد).
  final bool? delivered;

  /// عنوان کوتاه و تمیز برای نمایش در لیست و اعلان ویندوز.
  String get compactTitle => summarizeTitle(title, body);

  /// متن کوتاه، مفید و بدون شلوغی (از جمله خلاصه سازی گزارش شبانه).
  String get compactBody => summarizeBody(body, title: title, maxChars: 160);

  /// متن فشرده ویژه بالون اعلان ویندوز.
  String get balloonBody => summarizeBody(body, title: title, maxChars: 105);

  static String summarizeTitle(String rawTitle, [String rawBody = '']) {
    String clean = rawTitle
        .replaceAll('\u200c', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.contains('گزارش شبانه')) {
      return 'گزارش شبانه';
    }
    if (clean == 'اعلان سیستمی آمبرلا' || clean.isEmpty) {
      if (rawBody.contains('گزارش شبانه')) return 'گزارش شبانه';
      if (rawBody.contains('تمدید گردید') || rawBody.contains('تمدید شد')) {
        return 'اشتراک تمدید شد';
      }
      if (rawBody.contains('فعال گردید') || rawBody.contains('فعال شد')) {
        return 'اشتراک فعال شد';
      }
      if (rawBody.contains('کیف پول')) return 'کیف پول';
      return 'اعلان سیستم';
    }
    if (clean == 'یادآور تمدید اشتراک') return 'تمدید اشتراک';
    if (clean == 'فعالسازی پس از عضویت کانال') return 'اشتراک فعال شد';
    if (clean == 'قطع به دلیل عضویت کانال') return 'توقف اشتراک';
    if (clean == 'هشدار عضویت کانال') return 'عضویت کانال';
    if (clean.length > 48) {
      clean = '${clean.substring(0, 47).trimRight()}…';
    }
    return clean;
  }

  static String summarizeBody(
    String rawBody, {
    String title = '',
    int maxChars = 160,
  }) {
    final String normalized = rawBody
        .replaceAll('\u200c', ' ')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('*', '')
        .replaceAll('`', '')
        .trim();
    if (normalized.isEmpty) {
      return '';
    }

    // خلاصه سازی دقیق گزارش های شبانه کامل تلگرام به یک خط کوتاه ویژه ویندوز.
    if (title.contains('گزارش شبانه') || normalized.contains('گزارش شبانه')) {
      final String? total =
          _extractField(normalized, r'سهمیه\s*کل:\s*([^\n]+)');
      final String? used = _extractField(
        normalized,
        r'(?:مصرف\s*شده|مصرف\s*کل(?:\s*تا\s*امشب)?):\s*([^\n]+)',
      );
      final String? rem =
          _extractField(normalized, r'باقی\s*مانده:\s*([^\n]+)') ??
              _extractField(normalized, r'باقیمانده:\s*([^\n]+)');
      final String? exp = _extractField(
        normalized,
        r'(?:زمان\s*باقی\s*مانده(?:\s*اشتراک)?|زمان\s*باقیمانده(?:\s*اشتراک)?|اعتبار|تاریخ\s*انقضا):\s*([^\n(]+)',
      );
      final String? pct = _extractField(
        normalized,
        r'([۰-۹0-9]+(?:[٫.][۰-۹0-9]+)?)\s*٪',
      );
      if (used != null || rem != null || total != null) {
        final List<String> parts = <String>[];
        if (used != null && total != null) {
          parts.add(
            pct != null
                ? 'مصرف $used از $total ($pct٪)'
                : 'مصرف $used از $total',
          );
        } else if (used != null) {
          parts.add('مصرف $used');
        }
        if (rem != null) {
          parts.add('مانده $rem');
        }
        if (exp != null && exp.isNotEmpty) {
          parts.add('اعتبار $exp');
        }
        return _clip(parts.join(' · '), maxChars);
      }
    }

    if (!normalized.contains('\n') && normalized.length <= maxChars) {
      return _stripUrls(normalized.replaceAll(RegExp(r'\s{2,}'), ' ').trim());
    }

    final List<String> kept = <String>[];
    for (final String rawLine in normalized.split('\n')) {
      String line = rawLine
          .replaceFirst(RegExp(r'^[├└│─━═➖•·\s]+'), '')
          .replaceAll(RegExp(r'[█▓▒░]{3,}'), '')
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();
      line = _stripUrls(line);
      if (line.isEmpty) continue;
      if (RegExp(r'^[➖─━═_]{3,}$').hasMatch(line)) continue;
      if (RegExp(r'^(?:👋|🌹|🌺)?\s*(?:سلام|درود)\b.*(?:گرامی|عزیز)')
          .hasMatch(line)) {
        continue;
      }
      if (RegExp(
        r'^(?:👤|🆔|📌\s*بخش|📅\s*تاریخ|🕰\s*ساعت|🌐\s*سرور آمبرلا|سرور آمبرلا$|☂|آرمین سافت|💡\s*نکته|📊\s*وضعیت مصرف:$|📈\s*گزارش شبانه|👇|👌برای|🔄لطفا چند لحظه|📞در صورت ادامه|⚠\uFE0F?\s*در صورت ادامه)',
      ).hasMatch(line)) {
        continue;
      }
      kept.add(line);
      if (kept.length == 3) break;
    }

    final String joined = kept.isNotEmpty
        ? kept.join(' · ')
        : _stripUrls(normalized.replaceAll(RegExp(r'\s+'), ' '));
    return _clip(joined, maxChars);
  }

  static String? _extractField(String text, String pattern) {
    final RegExpMatch? match = RegExp(pattern).firstMatch(text);
    final String value = (match?.group(1) ?? '').trim();
    return value.isEmpty ? null : value;
  }

  static String _stripUrls(String text) => text
      .replaceAll(RegExp(r'\s*[—–-]?\s*https?://\S+'), '')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();

  static String _clip(String text, int maxChars) {
    final String clean = text.trim();
    if (clean.length <= maxChars) {
      return clean;
    }
    return '${clean.substring(0, maxChars - 1).trimRight()}…';
  }

  String get identityKey {
    if (id != 0) {
      return 'id:$id';
    }
    return 'msg:${sentAt?.toUtc().toIso8601String() ?? ''}|$title|$body';
  }

  AppNotification copyWith({
    String? title,
    String? body,
    String? level,
    DateTime? sentAt,
    bool? read,
    bool clearDelivered = false,
  }) =>
      AppNotification(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        level: level ?? this.level,
        sentAt: sentAt ?? this.sentAt,
        read: read ?? this.read,
        delivered: clearDelivered ? null : delivered,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'body': body,
        'level': level,
        'sent_at': sentAt?.toIso8601String(),
        'read': read,
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final bool hasDelivered =
        json.containsKey('delivered') && json['delivered'] != null;
    return AppNotification(
      id: JsonX.integer(json['id']),
      title: JsonX.text(json['title']),
      body: JsonX.text(json['body']),
      level: JsonX.text(json['level'], 'info'),
      sentAt: JsonX.dateTime(json['sent_at']),
      read: JsonX.boolean(json['read']),
      delivered: hasDelivered ? JsonX.boolean(json['delivered']) : null,
    );
  }
}

class GeoInfo {
  const GeoInfo({
    this.ip = '',
    this.city = '',
    this.country = '',
    this.countryCode = '',
    this.region = '',
    this.isp = '',
    this.timezone = '',
    this.latitude = 0,
    this.longitude = 0,
  });

  final String ip;
  final String city;
  final String country;
  final String countryCode;
  final String region;
  final String isp;
  final String timezone;
  final double latitude;
  final double longitude;

  bool get isEmpty => ip.isEmpty;

  String get cityLabel => city.isEmpty ? 'نامشخص' : city;

  String get countryLabel {
    if (country.isNotEmpty) {
      return country;
    }
    return switch (countryCode.toUpperCase()) {
      'IR' => 'ایران',
      'DE' => 'آلمان',
      'NL' => 'هلند',
      'TR' => 'ترکیه',
      'AE' => 'امارات',
      'US' => 'آمریکا',
      'FI' => 'فنلاند',
      'FR' => 'فرانسه',
      'GB' => 'بریتانیا',
      'SE' => 'سوئد',
      'CA' => 'کانادا',
      'CH' => 'سوئیس',
      'AT' => 'اتریش',
      'PL' => 'لهستان',
      'SG' => 'سنگاپور',
      'JP' => 'ژاپن',
      // کشور ناشناخته رشته خالی می دهد، نه «نامشخص»؛ وگرنه خط تاریخ و موقعیت
      // در صفحه اتصال به «نامشخص، نامشخص» تبدیل می شد.
      _ => '',
    };
  }

  /// برچسب موقعیت برای نمایش؛ اگر هیچ کدام معلوم نباشد یک رشته خالی.
  String get flagEmojiFreeLabel {
    final List<String> parts = <String>[
      if (countryLabel.isNotEmpty) countryLabel,
      if (city.isNotEmpty) city,
    ];
    return parts.join('، ');
  }

  /// کد دوحرفی کشور برای نمایش پرچم (کوچک، مثلا ca).
  String get flagCode {
    final String code = countryCode.trim().toLowerCase();
    if (code.length == 2) {
      return code;
    }
    switch (country.trim().toLowerCase()) {
      case 'canada':
        return 'ca';
      case 'irán':
      case 'iran':
        return 'ir';
      case 'germany':
        return 'de';
      case 'netherlands':
        return 'nl';
      case 'turkey':
      case 'türkiye':
        return 'tr';
      case 'united arab emirates':
        return 'ae';
      case 'united states':
        return 'us';
      case 'finland':
        return 'fi';
      case 'france':
        return 'fr';
      case 'united kingdom':
        return 'gb';
      case 'sweden':
        return 'se';
      default:
        return '';
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'ip': ip,
        'city': city,
        'country': country,
        'countryCode': countryCode,
        'region': region,
        'isp': isp,
        'timezone': timezone,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory GeoInfo.fromJson(Map<String, dynamic> json) {
    return GeoInfo(
      ip: JsonX.text(json['ip'] ?? json['query']),
      city: JsonX.text(json['city']),
      country: JsonX.text(json['country'] ?? json['country_name']),
      countryCode: JsonX.text(json['countryCode'] ?? json['country_code']),
      region: JsonX.text(json['region'] ?? json['region_name']),
      isp: JsonX.text(json['isp'] ?? json['org'] ?? json['asn_org']),
      timezone: JsonX.text(json['timezone']),
      latitude: JsonX.number(json['latitude'] ?? json['lat']),
      longitude: JsonX.number(json['longitude'] ?? json['lon']),
    );
  }

  static const GeoInfo empty = GeoInfo();
}

/// حالت اتصال که کاربر انتخاب می کند.
///
/// هسته یکی است (موتور هسته)؛ انتخاب کاربر فقط تعیین می کند ترافیک چطور از
/// هسته رد شود. حالت «خودکار» اول تونل کامل را امتحان می کند و اگر نشد پروکسی
/// سیستمی.
enum CorePreference { auto, tun, systemProxy }

extension CorePreferenceX on CorePreference {
  String get faName {
    switch (this) {
      case CorePreference.auto:
        return 'خودکار';
      case CorePreference.tun:
        return 'تونل کامل';
      case CorePreference.systemProxy:
        return 'پروکسی سیستمی';
    }
  }

  String get description {
    switch (this) {
      case CorePreference.auto:
        return 'اول تونل کامل، اگر نشد پروکسی سیستمی';
      case CorePreference.tun:
        return 'تمام ترافیک ویندوز از کارت شبکه مجازی هسته رد می شود';
      case CorePreference.systemProxy:
        return 'پروکسی ویندوز روی پورت محلی هسته تنظیم می شود';
    }
  }

  /// آیکون ساده حالت؛ در رابط کاربری به جای تصویر لوگو استفاده می شود.
  IconData get icon {
    switch (this) {
      case CorePreference.auto:
        return Icons.auto_awesome_rounded;
      case CorePreference.tun:
        return Icons.shield_rounded;
      case CorePreference.systemProxy:
        return Icons.lan_rounded;
    }
  }

  /// همه حالت ها با همین نسخه کار می کنند.
  bool get available => true;

  /// تونل کامل به دسترسی مدیر نیاز دارد؛ بدون آن پروکسی سیستمی می آید.
  bool get prefersTun => this == CorePreference.tun || this == CorePreference.auto;
}

enum SelectionMode { auto, roundRobin, consistentHash, stickySession, manual }

/// حالت هایی که در منوی برنامه نشان داده می شوند.
///
/// `manual` عمدا اینجا نیست: کاربر خواست «انتخاب دستی» از رابط حذف شود،
/// چون فهرست بلند سرورها در صفحه اتصال جای درستی ندارد و انتخاب خودکار
/// بهترین گره را می گیرد. مقدار `manual` در مدل می ماند تا تنظیم ذخیره شده
/// کاربران قبلی بی خطا خوانده شود؛ فقط در منو دیده نمی شود و اگر کسی از
/// نسخه قبل آن را داشته باشد، به `auto` برمی گردد.
extension SelectionModeList on SelectionMode {
  static const List<SelectionMode> visible = <SelectionMode>[
    SelectionMode.auto,
    SelectionMode.roundRobin,
    SelectionMode.consistentHash,
    SelectionMode.stickySession,
  ];
}

extension SelectionModeX on SelectionMode {
  String get label {
    switch (this) {
      case SelectionMode.auto:
        return 'خودکار (کمترین پینگ)';
      case SelectionMode.roundRobin:
        return 'گردشی';
      case SelectionMode.consistentHash:
        return 'هش پایدار';
      case SelectionMode.stickySession:
        return 'نشست چسبنده';
      case SelectionMode.manual:
        return 'انتخاب دستی';
    }
  }

  String get description {
    switch (this) {
      case SelectionMode.auto:
        return 'در هر اتصال پایدارترین سرور با کمترین پینگ انتخاب می شود.';
      case SelectionMode.roundRobin:
        return 'سرورها به نوبت استفاده می شوند تا بار پخش شود.';
      case SelectionMode.consistentHash:
        return 'سرور بر اساس هش پایدار دستگاه انتخاب می شود و تغییر نمی کند.';
      case SelectionMode.stickySession:
        return 'یک سرور برای مدت مشخص نگه داشته می شود تا اتصال ثابت بماند.';
      case SelectionMode.manual:
        return 'سرور دلخواه خودتان را از فهرست انتخاب کنید.';
    }
  }

  IconData get icon {
    switch (this) {
      case SelectionMode.auto:
        return Icons.auto_mode_rounded;
      case SelectionMode.roundRobin:
        return Icons.sync_alt_rounded;
      case SelectionMode.consistentHash:
        return Icons.fingerprint_rounded;
      case SelectionMode.stickySession:
        return Icons.push_pin_rounded;
      case SelectionMode.manual:
        return Icons.touch_app_rounded;
    }
  }

  String get faName {
    switch (this) {
      case SelectionMode.auto:
        return 'خودکار';
      case SelectionMode.roundRobin:
        return 'گردشی';
      case SelectionMode.consistentHash:
        return 'هش پایدار';
      case SelectionMode.stickySession:
        return 'نشست چسبنده';
      case SelectionMode.manual:
        return 'دستی';
    }
  }
}

enum ThemePreference { system, dark, light }

extension ThemePreferenceX on ThemePreference {
  String get label {
    switch (this) {
      case ThemePreference.system:
        return 'هماهنگ با ویندوز';
      case ThemePreference.dark:
        return 'تاریک';
      case ThemePreference.light:
        return 'روشن';
    }
  }
}

enum TunStack { auto, mixed, gvisor, system }

extension TunStackX on TunStack {
  String get label {
    switch (this) {
      case TunStack.auto:
        return 'پیش فرض هسته';
      case TunStack.mixed:
        return 'ترکیبی';
      case TunStack.gvisor:
        return 'کاربرفضا';
      case TunStack.system:
        return 'سیستم';
    }
  }

  IconData get icon {
    switch (this) {
      case TunStack.auto:
        return Icons.auto_awesome_rounded;
      case TunStack.mixed:
        return Icons.merge_type_rounded;
      case TunStack.gvisor:
        return Icons.memory_rounded;
      case TunStack.system:
        return Icons.dns_rounded;
    }
  }
}

/// Values accepted by the pinned core log parser.
class CoreLogLevel {
  const CoreLogLevel._();
  /// پیش فرض هم راستا با Hiddify (`warn`) تا تولید صدها خط لاگ پایش هنگام
  /// شروع اتصال سربار اضافه ایجاد نکند.
  static const String defaultLevel = 'warn';
  static const List<String> values = <String>['trace', 'debug', 'info', 'warn', 'error', 'fatal', 'panic'];
  static String normalize(String value) => values.contains(value) ? value : defaultLevel;
}

/// Resolver presets only; these are DNS endpoints, never subscription sources.
class NetworkDns {
  const NetworkDns._();
  /// پیش فرض دی ان اس راه دور هم راستا با Hiddify (`tcp://8.8.8.8`): روی
  /// پروکسی های CDN/HTTPUpgrade/XHTTP بسته UDP معطل تایم اوت می شود ولی TCP
  /// بی درنگ پاسخ می دهد و گروه دی ان اس هسته خودش UDP/TLS پشتیبان را هم دارد.
  static const String defaultRemote = 'tcp://8.8.8.8';
  /// پیش فرض دی ان اس مستقیم هم راستا با Hiddify (`1.1.1.1` / `udp://1.1.1.1`).
  static const String defaultDirect = '1.1.1.1';
  static const String fallback = defaultDirect;
  static const Map<String, String> presets = <String, String>{
    'tcp://8.8.8.8': 'گوگل — پایدار',
    'tcp://1.1.1.1': 'کلادفلر — پایدار',
    '1.1.1.1': 'کلادفلر — سریع',
    '8.8.8.8': 'گوگل — سریع',
    '9.9.9.9': 'کوآد ۹ — سریع',
    'https://1.1.1.1/dns-query': 'کلادفلر — رمزنگاری شده',
    'https://8.8.8.8/dns-query': 'گوگل — رمزنگاری شده',
    'https://9.9.9.9/dns-query': 'کوآد ۹ — رمزنگاری شده',
    'https://sky.rethinkdns.com/dns-query': 'ریتینک — رمزنگاری شده',
  };

  static String subtitleFa(String key) {
    switch (key) {
      case 'tcp://8.8.8.8':
        return 'نشانی ۸.۸.۸.۸ (اتصال پایدار)';
      case 'tcp://1.1.1.1':
        return 'نشانی ۱.۱.۱.۱ (اتصال پایدار)';
      case '1.1.1.1':
        return 'نشانی ۱.۱.۱.۱ (پاسخ فوری)';
      case '8.8.8.8':
        return 'نشانی ۸.۸.۸.۸ (پاسخ فوری)';
      case '9.9.9.9':
        return 'نشانی ۹.۹.۹.۹ (پاسخ فوری)';
      case 'https://1.1.1.1/dns-query':
        return 'نشانی ۱.۱.۱.۱ (بر بستر وب امن)';
      case 'https://8.8.8.8/dns-query':
        return 'نشانی ۸.۸.۸.۸ (بر بستر وب امن)';
      case 'https://9.9.9.9/dns-query':
        return 'نشانی ۹.۹.۹.۹ (بر بستر وب امن)';
      case 'https://sky.rethinkdns.com/dns-query':
        return 'سرور امن ریتینک (بر بستر وب امن)';
      default:
        return Fa.num(key);
    }
  }

  /// آیکون دقیق هر سرور دی ان اس بر اساس شیوه اتصال (رمزنگاری، سریع یا پایدار).
  static IconData iconFor(String key) {
    final String lower = key.trim().toLowerCase();
    if (lower.startsWith('https://')) {
      return Icons.https_rounded;
    }
    if (lower.startsWith('udp://')) {
      return Icons.bolt_rounded;
    }
    return Icons.verified_user_rounded;
  }
  static String normalize(String value, {String defaultValue = fallback}) {
    final String clean = value.trim();
    if (clean == 'udp://1.1.1.1') return '1.1.1.1';
    if (clean == 'udp://8.8.8.8') return '8.8.8.8';
    if (clean == 'udp://9.9.9.9') return '9.9.9.9';
    return presets.containsKey(clean) ? clean : defaultValue;
  }

  static String normalizeRemote(String value) =>
      normalize(value, defaultValue: defaultRemote);

  static String normalizeDirect(String value) =>
      normalize(value, defaultValue: defaultDirect);
}

class AppSettings {
  const AppSettings({
    this.theme = ThemePreference.dark,
    this.autoConnect = false,
    this.killSwitch = false,
    this.freeCorePorts = true,
    this.tunMode = true,
    this.startWithWindows = false,
    this.minimizeToTray = true,
    this.closeToTray = true,
    this.soundEnabled = true,
    this.notificationsEnabled = true,
    this.selectionMode = SelectionMode.auto,
    this.corePreference = CorePreference.auto,
    this.serviceMode = InboundServiceMode.vpn,
    this.autoFailover = true,
    this.stickyMinutes = 30,
    this.tunStack = TunStack.auto,
    this.mtu = 9000,
    this.blockIpv6 = true,
    this.ipv6RouteMode = Ipv6RouteMode.ipv4Only,
    this.strictRoute = true,
    this.mixedPort = AppConfig.httpPortUmbrella,
    this.localProxyInVpn = true,
    this.localProxyAuth = false,
    this.allowConnectionFromLan = false,
    this.lanSharingPort = LanSharing.defaultLanPort,
    this.lanSharingPassword = '',
    this.dnsOverTunnel = true,
    this.remoteDns = NetworkDns.defaultRemote,
    this.directDns = NetworkDns.defaultDirect,
    this.remoteDnsStrategy = DnsDomainStrategy.asIs,
    this.directDnsStrategy = DnsDomainStrategy.asIs,
    this.enableFakeDns = false,
    this.routingRegion = RoutingRegion.other,
    this.bypassLan = false,
    this.blockAds = false,
    this.resolveDestination = false,
    this.blockQuic = false,
    this.tlsTricks = const TlsTricksSettings(),
    this.chain = const ChainSettings(),
    this.appRoutes = const <AppRouteRule>[],
    this.showSpeedInTray = true,
    this.occasionEffects = true,
    this.checkUpdatesOnStart = true,
    this.firstName = '',
    this.lastName = '',
    this.phone = '',
    this.lastNodeId = '',
    this.serverRegionCode = 'all',
    this.gatewayBase = '',
    this.pingIntervalSeconds = 120,
    this.turboMode = false,
    this.logLevel = CoreLogLevel.defaultLevel,
    this.modeChoiceExplicit = false,
    this.showCli = false,
  });

  final ThemePreference theme;
  final bool autoConnect;
  final bool killSwitch;

  /// آزادسازی خودکار پورت های ثابت هسته (۱۷۰۷۸ و ۱۶۷۵۶) پیش از اتصال.
  ///
  /// اگر برنامه دیگری — مثل نسخه دیگری از همین هسته — این پورت ها را گرفته
  /// باشد، هسته اصلا بالا نمی آید و هیچ اتصالی ممکن نیست. با روشن بودن این
  /// تنظیم، آمبرلا خودش همان برنامه را می بندد. فقط هسته های شناخته شده
  /// فیلترشکن بسته می شوند، نه هر برنامه ای.
  final bool freeCorePorts;

  /// تونل کامل با کارت شبکه مجازی به جای پروکسی سیستمی.
  final bool tunMode;
  final bool startWithWindows;
  final bool minimizeToTray;
  final bool closeToTray;
  final bool soundEnabled;
  final bool notificationsEnabled;
  final SelectionMode selectionMode;

  /// هسته انتخابی کاربر؛ خودکار یعنی زنجیره پیش فرض.
  final CorePreference corePreference;

  /// حالت سرویس ورودی هسته (`پروکسی` / `پروکسی سیستم` / `VPN`).
  final InboundServiceMode serviceMode;
  final bool autoFailover;
  final int stickyMinutes;
  final TunStack tunStack;
  final int mtu;
  final bool blockIpv6;
  final Ipv6RouteMode ipv6RouteMode;
  final bool strictRoute;
  final int mixedPort;
  final bool localProxyInVpn;
  final bool localProxyAuth;
  final bool allowConnectionFromLan;
  final int lanSharingPort;
  final String lanSharingPassword;
  // Legacy persisted value. The pinned core always routes remote DNS through
  // the selected proxy; it exposes no boolean for changing that behavior.
  final bool dnsOverTunnel;
  final String remoteDns;
  final String directDns;
  final DnsDomainStrategy remoteDnsStrategy;
  final DnsDomainStrategy directDnsStrategy;
  final bool enableFakeDns;
  final RoutingRegion routingRegion;
  final bool bypassLan;
  final bool blockAds;
  final bool resolveDestination;
  final bool blockQuic;
  final TlsTricksSettings tlsTricks;
  final ChainSettings chain;
  final List<AppRouteRule> appRoutes;
  final bool showSpeedInTray;
  final bool occasionEffects;
  final bool checkUpdatesOnStart;
  final String firstName;
  final String lastName;
  final String phone;
  final String lastNodeId;
  /// فیلتر منطقه ای اتصال؛ all یعنی همه کشورها و unknown یعنی بدون کشور مشخص.
  final String serverRegionCode;
  final String gatewayBase;
  final int pingIntervalSeconds;
  final bool turboMode;
  final String logLevel;

  /// کاربر خودش حالت اتصال (تونل یا پروکسی) را انتخاب کرده است؟ تا وقتی
  /// انتخاب نکرده، پیش فرض برنامه (تونل کامل) اعمال می شود.
  final bool modeChoiceExplicit;

  /// پنجره Umbrella CLI هنگام اتصال باز شود.
  final bool showCli;

  AppSettings copyWith({
    ThemePreference? theme,
    bool? autoConnect,
    bool? killSwitch,
    bool? freeCorePorts,
    bool? tunMode,
    bool? startWithWindows,
    bool? minimizeToTray,
    bool? closeToTray,
    bool? soundEnabled,
    bool? notificationsEnabled,
    SelectionMode? selectionMode,
    CorePreference? corePreference,
    InboundServiceMode? serviceMode,
    bool? autoFailover,
    int? stickyMinutes,
    TunStack? tunStack,
    int? mtu,
    bool? blockIpv6,
    Ipv6RouteMode? ipv6RouteMode,
    bool? strictRoute,
    int? mixedPort,
    bool? localProxyInVpn,
    bool? localProxyAuth,
    bool? allowConnectionFromLan,
    int? lanSharingPort,
    String? lanSharingPassword,
    bool? dnsOverTunnel,
    String? remoteDns,
    String? directDns,
    DnsDomainStrategy? remoteDnsStrategy,
    DnsDomainStrategy? directDnsStrategy,
    bool? enableFakeDns,
    RoutingRegion? routingRegion,
    bool? bypassLan,
    bool? blockAds,
    bool? resolveDestination,
    bool? blockQuic,
    TlsTricksSettings? tlsTricks,
    ChainSettings? chain,
    List<AppRouteRule>? appRoutes,
    bool? showSpeedInTray,
    bool? occasionEffects,
    bool? checkUpdatesOnStart,
    String? firstName,
    String? lastName,
    String? phone,
    String? lastNodeId,
    String? serverRegionCode,
    String? gatewayBase,
    int? pingIntervalSeconds,
    bool? turboMode,
    String? logLevel,
    bool? modeChoiceExplicit,
    bool? showCli,
  }) {
    final Ipv6RouteMode nextIpv6Mode = ipv6RouteMode ??
        (blockIpv6 != null
            ? (blockIpv6 ? Ipv6RouteMode.ipv4Only : Ipv6RouteMode.preferIpv4)
            : this.ipv6RouteMode);
    final bool nextBlockIpv6 = ipv6RouteMode != null
        ? ipv6RouteMode == Ipv6RouteMode.ipv4Only
        : (blockIpv6 ?? this.blockIpv6);
    return AppSettings(
      theme: theme ?? this.theme,
      autoConnect: autoConnect ?? this.autoConnect,
      killSwitch: killSwitch ?? this.killSwitch,
      freeCorePorts: freeCorePorts ?? this.freeCorePorts,
      tunMode: tunMode ?? this.tunMode,
      startWithWindows: startWithWindows ?? this.startWithWindows,
      minimizeToTray: minimizeToTray ?? this.minimizeToTray,
      closeToTray: closeToTray ?? this.closeToTray,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      selectionMode: selectionMode ?? this.selectionMode,
      corePreference: corePreference ?? this.corePreference,
      serviceMode: serviceMode ?? this.serviceMode,
      autoFailover: autoFailover ?? this.autoFailover,
      stickyMinutes: stickyMinutes ?? this.stickyMinutes,
      tunStack: tunStack ?? this.tunStack,
      mtu: mtu ?? this.mtu,
      blockIpv6: nextBlockIpv6,
      ipv6RouteMode: nextIpv6Mode,
      strictRoute: strictRoute ?? this.strictRoute,
      mixedPort: mixedPort ?? this.mixedPort,
      localProxyInVpn: localProxyInVpn ?? this.localProxyInVpn,
      localProxyAuth: localProxyAuth ?? this.localProxyAuth,
      allowConnectionFromLan:
          allowConnectionFromLan ?? this.allowConnectionFromLan,
      lanSharingPort: lanSharingPort ?? this.lanSharingPort,
      lanSharingPassword: lanSharingPassword ?? this.lanSharingPassword,
      dnsOverTunnel: dnsOverTunnel ?? this.dnsOverTunnel,
      remoteDns: remoteDns ?? this.remoteDns,
      directDns: directDns ?? this.directDns,
      remoteDnsStrategy: remoteDnsStrategy ?? this.remoteDnsStrategy,
      directDnsStrategy: directDnsStrategy ?? this.directDnsStrategy,
      enableFakeDns: enableFakeDns ?? this.enableFakeDns,
      routingRegion: routingRegion ?? this.routingRegion,
      bypassLan: bypassLan ?? this.bypassLan,
      blockAds: blockAds ?? this.blockAds,
      resolveDestination: resolveDestination ?? this.resolveDestination,
      blockQuic: blockQuic ?? this.blockQuic,
      tlsTricks: tlsTricks ?? this.tlsTricks,
      chain: chain ?? this.chain,
      appRoutes: appRoutes == null ? this.appRoutes : List<AppRouteRule>.unmodifiable(appRoutes),
      showSpeedInTray: showSpeedInTray ?? this.showSpeedInTray,
      occasionEffects: occasionEffects ?? this.occasionEffects,
      checkUpdatesOnStart: checkUpdatesOnStart ?? this.checkUpdatesOnStart,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      lastNodeId: lastNodeId ?? this.lastNodeId,
      serverRegionCode: serverRegionCode ?? this.serverRegionCode,
      gatewayBase: gatewayBase ?? this.gatewayBase,
      pingIntervalSeconds: pingIntervalSeconds ?? this.pingIntervalSeconds,
      turboMode: turboMode ?? this.turboMode,
      logLevel: logLevel ?? this.logLevel,
      modeChoiceExplicit: modeChoiceExplicit ?? this.modeChoiceExplicit,
      showCli: showCli ?? this.showCli,
    );
  }

  static const int currentCoreDefaultsVersion = 1;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'theme': theme.name,
        'autoConnect': autoConnect,
        'killSwitch': killSwitch,
        'freeCorePorts': freeCorePorts,
        'tunMode': tunMode,
        'startWithWindows': startWithWindows,
        'minimizeToTray': minimizeToTray,
        'closeToTray': closeToTray,
        'soundEnabled': soundEnabled,
        'notificationsEnabled': notificationsEnabled,
        'selectionMode': selectionMode.name,
        'corePreference': corePreference.name,
        'serviceMode': serviceMode.name,
        'autoFailover': autoFailover,
        'stickyMinutes': stickyMinutes,
        'tunStack': tunStack.name,
        'mtu': mtu,
        'blockIpv6': blockIpv6,
        'ipv6RouteMode': ipv6RouteMode.name,
        'strictRoute': strictRoute,
        'mixedPort': mixedPort,
        'localProxyInVpn': localProxyInVpn,
        'localProxyAuth': localProxyAuth,
        'allowConnectionFromLan': allowConnectionFromLan,
        'lanSharingPort': lanSharingPort,
        'lanSharingPassword': lanSharingPassword,
        'dnsOverTunnel': dnsOverTunnel,
        'remoteDns': remoteDns,
        'directDns': directDns,
        'remoteDnsStrategy': remoteDnsStrategy.name,
        'directDnsStrategy': directDnsStrategy.name,
        'enableFakeDns': enableFakeDns,
        'routingRegion': routingRegion.name,
        'bypassLan': bypassLan,
        'blockAds': blockAds,
        'resolveDestination': resolveDestination,
        'blockQuic': blockQuic,
        'tlsTricks': tlsTricks.toJson(),
        'chain': chain.toJson(),
        'appRoutes': appRoutes.map((AppRouteRule rule) => rule.toJson()).toList(),
        'showSpeedInTray': showSpeedInTray,
        'occasionEffects': occasionEffects,
        'checkUpdatesOnStart': checkUpdatesOnStart,
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'lastNodeId': lastNodeId,
        'serverRegionCode': serverRegionCode,
        'gatewayBase': gatewayBase,
        'pingIntervalSeconds': pingIntervalSeconds,
        'turboMode': turboMode,
        'logLevel': logLevel,
        'modeChoiceExplicit': modeChoiceExplicit,
        'showCli': showCli,
        'cliPreferenceVersion': 1,
        'coreDefaultsVersion': currentCoreDefaultsVersion,
      };

  /// اگر تنظیم ذخیره شده `manual` باشد، به `auto` برمی گردد.
  ///
  /// حالت دستی از منو حذف شده، پس نگه داشتن آن یعنی کاربر گزینه ای می دید
  /// که دیگر نمی تواند عوضش کند.
  static SelectionMode _withoutManual(SelectionMode mode) =>
      SelectionModeList.visible.contains(mode) ? mode : SelectionMode.auto;

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    T pick<T extends Enum>(List<T> values, Object? raw, T fallback) {
      final String name = JsonX.text(raw);
      for (final T item in values) {
        if (item.name == name) {
          return item;
        }
      }
      return fallback;
    }

    final CorePreference parsedCorePref =
        pick(CorePreference.values, json['corePreference'], CorePreference.auto);
    final bool parsedTunMode = JsonX.boolean(json['tunMode'], fallback: true);
    final InboundServiceMode fallbackServiceMode =
        parsedCorePref == CorePreference.systemProxy || !parsedTunMode
            ? InboundServiceMode.systemProxy
            : InboundServiceMode.vpn;
    final InboundServiceMode parsedServiceMode = pick(
      InboundServiceMode.values,
      json['serviceMode'],
      fallbackServiceMode,
    );
    final bool parsedBlockIpv6 =
        JsonX.boolean(json['blockIpv6'], fallback: true);
    final Ipv6RouteMode parsedIpv6Mode = json['ipv6RouteMode'] != null
        ? pick(Ipv6RouteMode.values, json['ipv6RouteMode'], Ipv6RouteMode.ipv4Only)
        : (parsedBlockIpv6 ? Ipv6RouteMode.ipv4Only : Ipv6RouteMode.preferIpv4);
    final int rawMixedPort =
        JsonX.integer(json['mixedPort'], AppConfig.httpPortUmbrella);
    final int validMixedPort = LanSharing.isValidPort(rawMixedPort)
        ? rawMixedPort
        : AppConfig.httpPortUmbrella;
    final int rawLanPort =
        JsonX.integer(json['lanSharingPort'], LanSharing.defaultLanPort);
    final int validLanPort =
        LanSharing.isValidPort(rawLanPort, forbiddenPort: validMixedPort)
            ? rawLanPort
            : (validMixedPort == LanSharing.defaultLanPort
                ? LanSharing.defaultLanPort + 1
                : LanSharing.defaultLanPort);
    final String rawSecret = JsonX.text(json['lanSharingPassword']).trim();
    final String validSecret =
        LanSharing.isValidPassword(rawSecret) ? rawSecret : '';

    return AppSettings(
      theme: pick(ThemePreference.values, json['theme'], ThemePreference.dark),
      autoConnect: JsonX.boolean(json['autoConnect']),
      killSwitch: JsonX.boolean(json['killSwitch'], fallback: false),
      freeCorePorts: JsonX.boolean(json['freeCorePorts'], fallback: true),
      tunMode: parsedTunMode,
      startWithWindows: JsonX.boolean(json['startWithWindows']),
      minimizeToTray: JsonX.boolean(json['minimizeToTray'], fallback: true),
      closeToTray: JsonX.boolean(json['closeToTray'], fallback: true),
      soundEnabled: JsonX.boolean(json['soundEnabled'], fallback: true),
      notificationsEnabled:
          JsonX.boolean(json['notificationsEnabled'], fallback: true),
      selectionMode:
          // `manual` دیگر در رابط نیست؛ اگر در تنظیمات قدیمی مانده باشد،
          // به خودکار برمی گردد تا کاربر گزینه ای نبیند که نمی تواند
          // عوضش کند.
          _withoutManual(
            pick(SelectionMode.values, json['selectionMode'], SelectionMode.auto),
          ),
      corePreference: parsedCorePref,
      serviceMode: parsedServiceMode,
      autoFailover: JsonX.boolean(json['autoFailover'], fallback: true),
      stickyMinutes: JsonX.integer(json['stickyMinutes'], 30),
      tunStack: pick(TunStack.values, json['tunStack'], TunStack.auto),
      mtu: JsonX.integer(json['mtu'], 9000).clamp(1280, 9000),
      blockIpv6: parsedIpv6Mode == Ipv6RouteMode.ipv4Only,
      ipv6RouteMode: parsedIpv6Mode,
      strictRoute: JsonX.boolean(json['strictRoute'], fallback: true),
      mixedPort: validMixedPort,
      localProxyInVpn: JsonX.boolean(json['localProxyInVpn'], fallback: true),
      localProxyAuth: JsonX.boolean(json['localProxyAuth']),
      allowConnectionFromLan: JsonX.boolean(json['allowConnectionFromLan']),
      lanSharingPort: validLanPort,
      lanSharingPassword: validSecret,
      dnsOverTunnel: JsonX.boolean(json['dnsOverTunnel'], fallback: true),
      remoteDns: json['coreDefaultsVersion'] != currentCoreDefaultsVersion &&
              const <String>{
                '1.1.1.1',
                'https://1.1.1.1/dns-query',
              }.contains(JsonX.text(json['remoteDns']).trim())
          ? NetworkDns.defaultRemote
          : NetworkDns.normalizeRemote(JsonX.text(json['remoteDns'])),
      directDns: NetworkDns.normalizeDirect(JsonX.text(json['directDns'])),
      remoteDnsStrategy: pick(
        DnsDomainStrategy.values,
        json['remoteDnsStrategy'],
        DnsDomainStrategy.asIs,
      ),
      directDnsStrategy: pick(
        DnsDomainStrategy.values,
        json['directDnsStrategy'],
        DnsDomainStrategy.asIs,
      ),
      enableFakeDns: JsonX.boolean(json['enableFakeDns']),
      routingRegion: pick(
        RoutingRegion.values,
        json['routingRegion'],
        RoutingRegion.other,
      ),
      bypassLan: JsonX.boolean(json['bypassLan']),
      blockAds: JsonX.boolean(json['blockAds']),
      resolveDestination: JsonX.boolean(json['resolveDestination']),
      blockQuic: JsonX.boolean(json['blockQuic']),
      tlsTricks: TlsTricksSettings.fromJson(JsonX.asMap(json['tlsTricks'])),
      chain: ChainSettings.fromJson(JsonX.asMap(json['chain'])),
      appRoutes: List<AppRouteRule>.unmodifiable(json['appRoutes'] is List
          ? (json['appRoutes'] as List).map((dynamic value) => AppRouteRule.fromJson(JsonX.asMap(value)))
          : <AppRouteRule>[]),
      showSpeedInTray: JsonX.boolean(json['showSpeedInTray'], fallback: true),
      occasionEffects: JsonX.boolean(json['occasionEffects'], fallback: true),
      checkUpdatesOnStart:
          JsonX.boolean(json['checkUpdatesOnStart'], fallback: true),
      firstName: JsonX.text(json['firstName']),
      lastName: JsonX.text(json['lastName']),
      phone: JsonX.text(json['phone']),
      lastNodeId: JsonX.text(json['lastNodeId']),
      serverRegionCode: JsonX.text(json['serverRegionCode'], 'all'),
      gatewayBase: JsonX.text(json['gatewayBase']),
      pingIntervalSeconds: JsonX.integer(json['pingIntervalSeconds'], 120),
      turboMode: JsonX.boolean(json['turboMode']),
      logLevel: json['coreDefaultsVersion'] != currentCoreDefaultsVersion &&
              JsonX.text(json['logLevel'], CoreLogLevel.defaultLevel).trim() == 'info'
          ? CoreLogLevel.defaultLevel
          : CoreLogLevel.normalize(
              JsonX.text(json['logLevel'], CoreLogLevel.defaultLevel),
            ),
      modeChoiceExplicit: JsonX.boolean(json['modeChoiceExplicit']),
      // Reset the old default-on console once. New explicit choices persist.
      showCli: json['cliPreferenceVersion'] == 1 && JsonX.boolean(json['showCli']),
    );
  }

  String get fullName => '$firstName $lastName'.trim();
}

class CoreInfo {
  const CoreInfo({
    required this.id,
    required this.title,
    required this.role,
    required this.binary,
    required this.version,
    required this.url,
    required this.archive,
    required this.inside,
    required this.requiredCore,
    this.sha256 = '',
    this.bundledCore = true,
  });

  final String id;
  final String title;
  final String role;
  final String binary;
  final String version;
  final String url;
  final String archive;
  final String inside;
  final bool requiredCore;

  /// آیا این هسته همراه نسخه نصب عرضه می شود؟ اگر نه، نبودنش خطا نیست.
  final bool bundledCore;
  final String sha256;

  factory CoreInfo.fromJson(Map<String, dynamic> json) {
    return CoreInfo(
      id: JsonX.text(json['id']),
      title: JsonX.text(json['title']),
      role: JsonX.text(json['role']),
      binary: JsonX.text(json['binary']),
      version: JsonX.text(json['version']),
      url: JsonX.text(json['url']),
      archive: JsonX.text(json['archive'], 'zip'),
      inside: JsonX.text(json['inside']),
      requiredCore: JsonX.boolean(json['required']),
      bundledCore: json['bundle'] == null ? true : JsonX.boolean(json['bundle']),
      sha256: JsonX.text(json['sha256']),
    );
  }
}

class TunnelStats {
  const TunnelStats({
    this.rx = 0,
    this.tx = 0,
    this.available = false,
    this.adapter = '',
    this.downSpeed = 0,
    this.upSpeed = 0,
    this.connectedFor = Duration.zero,
  });

  final int rx;
  final int tx;
  final bool available;
  final String adapter;
  final double downSpeed;
  final double upSpeed;
  final Duration connectedFor;

  TunnelStats copyWith({
    int? rx,
    int? tx,
    bool? available,
    String? adapter,
    double? downSpeed,
    double? upSpeed,
    Duration? connectedFor,
  }) {
    return TunnelStats(
      rx: rx ?? this.rx,
      tx: tx ?? this.tx,
      available: available ?? this.available,
      adapter: adapter ?? this.adapter,
      downSpeed: downSpeed ?? this.downSpeed,
      upSpeed: upSpeed ?? this.upSpeed,
      connectedFor: connectedFor ?? this.connectedFor,
    );
  }

  static const TunnelStats empty = TunnelStats();
}

class DeviceProfile {
  const DeviceProfile({
    this.hostname = '',
    this.username = '',
    this.os = '',
    this.osEdition = '',
    this.osDisplayVersion = '',
    this.osBuild = 0,
    this.arch = 'x64',
    this.machineId = '',
    this.cpu = '',
    this.cpuCores = 0,
    this.ramTotalMb = 0,
    this.ramUsedMb = 0,
    this.ramLoadPercent = 0,
    this.diskTotalMb = 0,
    this.diskFreeMb = 0,
    this.screenWidth = 0,
    this.screenHeight = 0,
    this.hasBattery = false,
    this.batteryPercent = -1,
    this.powerPlugged = true,
    this.uptimeSeconds = 0,
    this.adapterName = '',
    this.localIp = '',
    this.mac = '',
    this.elevated = false,
    this.ip = '',
    this.city = '',
    this.country = '',
  });

  final String hostname;
  final String username;
  final String os;
  final String osEdition;
  final String osDisplayVersion;
  final int osBuild;
  final String arch;
  final String machineId;
  final String cpu;
  final int cpuCores;
  final int ramTotalMb;
  final int ramUsedMb;
  final int ramLoadPercent;
  final int diskTotalMb;
  final int diskFreeMb;
  final int screenWidth;
  final int screenHeight;
  final bool hasBattery;
  final int batteryPercent;
  final bool powerPlugged;
  final int uptimeSeconds;
  final String adapterName;
  final String localIp;
  final String mac;
  final bool elevated;
  final String ip;
  final String city;
  final String country;

  String get deviceName => hostname.isNotEmpty ? hostname : 'رایانه ویندوز';

  /// معماری پردازنده کاملاً به فارسی.
  String get archLabelFa {
    switch (arch.trim().toLowerCase()) {
      case 'x64':
      case 'amd64':
      case 'x86_64':
        return '۶۴ بیتی';
      case 'arm64':
      case 'aarch64':
        return 'آرم ۶۴ بیتی';
      case 'x86':
      case 'i386':
        return '۳۲ بیتی';
      default:
        return '۶۴ بیتی';
    }
  }

  /// ویرایش ویندوز کاملاً به فارسی.
  String get osEditionLabelFa {
    final String low = '${osEdition.toLowerCase()} ${os.toLowerCase()}';
    if (low.contains('enterprise')) {
      return 'سازمانی';
    }
    if (low.contains('education')) {
      return 'آموزشی';
    }
    if (low.contains('professional') || low.contains(' pro')) {
      return 'حرفه ای';
    }
    if (low.contains('core') || low.contains('home')) {
      return 'خانگی';
    }
    if (low.contains('server')) {
      return 'سرور';
    }
    return '';
  }

  /// شماره ساخت ویندوز استخراج شده از اطلاعات بومی یا متن سیستم عامل.
  int get resolvedOsBuild {
    if (osBuild > 0) {
      return osBuild;
    }
    final RegExpMatch? match =
        RegExp(r'build\s+(\d+)', caseSensitive: false).firstMatch(os);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }
    return 0;
  }

  /// نگارش سالانه ویندوز کاملاً به فارسی (مثلاً 24H2 → نگارش ۲۴ نیمه دوم).
  String get osVersionLabelFa {
    final String raw = osDisplayVersion.trim().toUpperCase();
    if (raw.isEmpty) {
      return '';
    }
    final RegExpMatch? half = RegExp(r'^(\d{2})H([12])$').firstMatch(raw);
    if (half != null) {
      final String year = Fa.num(half.group(1));
      final String part = half.group(2) == '1' ? 'نیمه اول' : 'نیمه دوم';
      return 'نگارش $year $part';
    }
    if (raw == 'DEV') {
      return 'نسخه توسعه';
    }
    if (raw == 'BETA') {
      return 'نسخه پیش نمایش';
    }
    if (raw == 'CANARY') {
      return 'نسخه آزمایشی';
    }
    final String digits = raw.replaceAll(RegExp(r'[^0-9.]'), '');
    if (digits.isEmpty) {
      return '';
    }
    return 'نگارش ${Fa.num(digits)}';
  }

  /// عنوان کوتاه فارسی سیستم عامل و ویرایش (بدون شماره ساخت).
  String get osTitleFa {
    final int build = resolvedOsBuild;
    final String base;
    if (build >= 22000 || os.contains('Windows 11')) {
      base = 'ویندوز ۱۱';
    } else if (build >= 10240 || os.contains('Windows 10')) {
      base = 'ویندوز ۱۰';
    } else {
      base = 'ویندوز';
    }
    final String edition = osEditionLabelFa;
    return edition.isEmpty ? base : '$base $edition';
  }

  /// نام کامل و کاملاً فارسی سیستم عامل ویندوز با شماره ساخت.
  String get osLabelFa {
    final int build = resolvedOsBuild;
    final String title = osTitleFa;
    if (build > 0) {
      return '$title • ساخت ${Fa.grouped(build)}';
    }
    return title;
  }

  /// نوع دستگاه به فارسی (رایانه همراه یا رایانه شخصی).
  String get formFactorFa =>
      hasBattery ? 'رایانه همراه ویندوز' : 'رایانه شخصی ویندوز';

  String get platformLabel => '$osLabelFa • $archLabelFa';

  /// نام و مشخصات پردازنده کاملاً به فارسی با ارقام فارسی.
  String get cpuLabelFa {
    final String raw = cpu.trim();
    if (raw.isEmpty) {
      return cpuCores > 0
          ? 'پردازنده مرکزی (${Fa.num(cpuCores)} هسته)'
          : 'پردازنده مرکزی سیستم';
    }
    final String low = raw.toLowerCase();
    final List<String> parts = <String>[];
    if (low.contains('intel')) {
      final RegExpMatch? ultra =
          RegExp(r'core(?:\(tm\))?\s+ultra\s+(\d+)\s*(\d+[a-z]*)?', caseSensitive: false)
              .firstMatch(raw);
      final RegExpMatch? coreI =
          RegExp(r'i([3579])[-\s]?(\d{3,5})', caseSensitive: false)
              .firstMatch(raw);
      final RegExpMatch? gen =
          RegExp(r'(\d+)(?:th|st|nd|rd)\s+gen', caseSensitive: false)
              .firstMatch(raw);
      if (ultra != null) {
        parts.add('اینتل کور اولترا ${Fa.num(ultra.group(1))}');
        final String modelDigits =
            (ultra.group(2) ?? '').replaceAll(RegExp(r'[^0-9]'), '');
        if (modelDigits.isNotEmpty) {
          parts.add('مدل ${Fa.num(modelDigits)}');
        }
      } else if (coreI != null) {
        parts.add('اینتل کور آی ${Fa.num(coreI.group(1))}');
        if (gen != null) {
          parts.add('نسل ${Fa.num(gen.group(1))}');
        }
        parts.add('مدل ${Fa.num(coreI.group(2))}');
      } else if (low.contains('xeon')) {
        parts.add('اینتل زئون');
      } else if (low.contains('pentium')) {
        parts.add('اینتل پنتیوم');
      } else if (low.contains('celeron')) {
        parts.add('اینتل سلرون');
      } else {
        parts.add('پردازنده اینتل');
      }
    } else if (low.contains('amd')) {
      final RegExpMatch? ryzen =
          RegExp(r'ryzen\s+(\d+)\s*(\d{3,5})?', caseSensitive: false)
              .firstMatch(raw);
      final RegExpMatch? epyc =
          RegExp(r'epyc\s+(\d{3,5})', caseSensitive: false).firstMatch(raw);
      if (ryzen != null) {
        parts.add('ای ام دی رایزن ${Fa.num(ryzen.group(1))}');
        if ((ryzen.group(2) ?? '').isNotEmpty) {
          parts.add('مدل ${Fa.num(ryzen.group(2))}');
        }
      } else if (epyc != null) {
        parts.add('ای ام دی اپیک مدل ${Fa.num(epyc.group(1))}');
      } else if (low.contains('athlon')) {
        parts.add('ای ام دی اتلون');
      } else {
        parts.add('پردازنده ای ام دی');
      }
    } else if (low.contains('snapdragon') || low.contains('qualcomm')) {
      parts.add('پردازنده کوالکام اسنپدراگون');
    } else if (low.contains('apple')) {
      parts.add('پردازنده اپل');
    } else if (low.contains('virtual') || low.contains('kvm') || low.contains('qemu')) {
      parts.add('پردازنده مجازی سیستم');
    } else {
      parts.add('پردازنده مرکزی سیستم');
    }

    final RegExpMatch? ghz =
        RegExp(r'(\d+(?:\.\d+)?)\s*ghz', caseSensitive: false).firstMatch(raw);
    if (ghz != null) {
      final double? freq = double.tryParse(ghz.group(1)!);
      if (freq != null && freq > 0) {
        parts.add('${Fa.decimal(freq, fraction: 2)} گیگاهرتز');
      }
    }
    return parts.join(' • ');
  }

  double get ramTotalGb => ramTotalMb > 0 ? ramTotalMb / 1024.0 : 0;
  double get ramUsedGb => ramUsedMb > 0 ? ramUsedMb / 1024.0 : 0;
  double get ramFreeGb {
    final double free = ramTotalGb - ramUsedGb;
    return free < 0 ? 0 : free;
  }

  double get ramPercent {
    if (ramLoadPercent > 0) {
      return ramLoadPercent.toDouble().clamp(0, 100);
    }
    if (ramTotalMb > 0) {
      return ((ramUsedMb / ramTotalMb) * 100).clamp(0, 100);
    }
    return 0;
  }

  double get diskTotalGb => diskTotalMb > 0 ? diskTotalMb / 1024.0 : 0;
  double get diskFreeGb => diskFreeMb > 0 ? diskFreeMb / 1024.0 : 0;
  double get diskUsedGb {
    final double used = diskTotalGb - diskFreeGb;
    return used < 0 ? 0 : used;
  }

  double get diskPercent {
    if (diskTotalMb <= 0) {
      return 0;
    }
    final int usedMb =
        diskTotalMb > diskFreeMb ? (diskTotalMb - diskFreeMb) : 0;
    return ((usedMb / diskTotalMb) * 100).clamp(0, 100);
  }

  /// وضوح نمایشگر اصلی به فارسی.
  String get screenLabelFa {
    if (screenWidth <= 0 || screenHeight <= 0) {
      return 'شناسایی نشده';
    }
    return '${Fa.grouped(screenWidth)} در ${Fa.grouped(screenHeight)} پیکسل';
  }

  /// وضعیت منبع تغذیه و باتری سیستم به فارسی.
  String get powerLabelFa {
    if (!hasBattery) {
      return 'برق مستقیم شهری';
    }
    if (batteryPercent >= 0 && batteryPercent <= 100) {
      final String state = powerPlugged ? 'متصل به شارژر' : 'در حال استفاده از باتری';
      return '${Fa.num(batteryPercent)} درصد ($state)';
    }
    return powerPlugged ? 'متصل به شارژر' : 'در حال استفاده از باتری';
  }

  Duration get uptimeDuration =>
      uptimeSeconds > 0 ? Duration(seconds: uptimeSeconds) : Duration.zero;

  /// زمان دقیق روشن شدن سیستم بر اساس مدت کارکرد ویندوز.
  DateTime? estimatedBootTime([DateTime? now]) {
    if (uptimeSeconds <= 0) {
      return null;
    }
    return (now ?? DateTime.now()).toUtc().subtract(uptimeDuration);
  }

  /// نوع کارت شبکه فعال سیستم کاملاً به فارسی.
  String get adapterLabelFa {
    final String low = adapterName.trim().toLowerCase();
    if (low.isEmpty) {
      return localIp.isNotEmpty ? 'کارت شبکه اصلی ویندوز' : 'شناسایی نشده';
    }
    if (low.contains('wi-fi') ||
        low.contains('wifi') ||
        low.contains('wireless') ||
        low.contains('wlan') ||
        low.contains('802.11')) {
      return 'کارت شبکه بی سیم';
    }
    if (low.contains('bluetooth')) {
      return 'شبکه بلوتوث';
    }
    if (low.contains('virtual') ||
        low.contains('vethernet') ||
        low.contains('hyper-v') ||
        low.contains('vmware') ||
        low.contains('tap') ||
        low.contains('wintun')) {
      return 'کارت شبکه مجازی';
    }
    if (low.contains('mobile') || low.contains('lte') || low.contains('cellular')) {
      return 'مودم همراه';
    }
    return 'کارت شبکه کابلی';
  }

  String get summary {
    final StringBuffer buffer = StringBuffer();
    buffer.write('دستگاه: ${Fa.num(deviceName)}');
    if (username.isNotEmpty) {
      buffer.write(' | کاربر: ${Fa.num(username)}');
    }
    buffer.write(' | $platformLabel');
    if (localIp.isNotEmpty) {
      buffer.write(' | نشانی داخلی: ${Fa.num(localIp)}');
    }
    if (city.isNotEmpty || country.isNotEmpty) {
      buffer.write(' | موقعیت: ${Fa.num(country)} ${Fa.num(city)}');
    }
    return buffer.toString();
  }

  DeviceProfile copyWith({
    String? ip,
    String? city,
    String? country,
    bool? elevated,
  }) {
    return DeviceProfile(
      hostname: hostname,
      username: username,
      os: os,
      osEdition: osEdition,
      osDisplayVersion: osDisplayVersion,
      osBuild: osBuild,
      arch: arch,
      machineId: machineId,
      cpu: cpu,
      cpuCores: cpuCores,
      ramTotalMb: ramTotalMb,
      ramUsedMb: ramUsedMb,
      ramLoadPercent: ramLoadPercent,
      diskTotalMb: diskTotalMb,
      diskFreeMb: diskFreeMb,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
      hasBattery: hasBattery,
      batteryPercent: batteryPercent,
      powerPlugged: powerPlugged,
      uptimeSeconds: uptimeSeconds,
      adapterName: adapterName,
      localIp: localIp,
      mac: mac,
      elevated: elevated ?? this.elevated,
      ip: ip ?? this.ip,
      city: city ?? this.city,
      country: country ?? this.country,
    );
  }

  factory DeviceProfile.fromNative(Map<String, dynamic> json) {
    return DeviceProfile(
      hostname: JsonX.text(json['hostname']),
      username: JsonX.text(json['username']),
      os: JsonX.text(json['os']),
      osEdition: JsonX.text(json['osEdition']),
      osDisplayVersion: JsonX.text(json['osDisplayVersion']),
      osBuild: JsonX.integer(json['osBuild']),
      arch: JsonX.text(json['arch'], 'x64'),
      machineId: JsonX.text(json['machineId']),
      cpu: JsonX.text(json['cpu']),
      cpuCores: JsonX.integer(json['cpuCores']),
      ramTotalMb: JsonX.integer(json['ramTotalMb']),
      ramUsedMb: JsonX.integer(json['ramUsedMb']),
      ramLoadPercent: JsonX.integer(json['ramLoadPercent']),
      diskTotalMb: JsonX.integer(json['diskTotalMb']),
      diskFreeMb: JsonX.integer(json['diskFreeMb']),
      screenWidth: JsonX.integer(json['screenWidth']),
      screenHeight: JsonX.integer(json['screenHeight']),
      hasBattery: JsonX.boolean(json['hasBattery']),
      batteryPercent: JsonX.integer(json['batteryPercent'], -1),
      powerPlugged: JsonX.boolean(json['powerPlugged'], fallback: true),
      uptimeSeconds: JsonX.integer(json['uptimeSeconds']),
      adapterName: JsonX.text(json['adapterName']),
      localIp: JsonX.text(json['localIp']),
      mac: JsonX.text(json['mac']),
      elevated: JsonX.boolean(json['elevated']),
    );
  }

  static const DeviceProfile empty = DeviceProfile();
}

/// کانال دریافت به روز رسانی: نسخه اصلی پایدار یا نسخه بتا (آزمایشی).
enum UpdateChannel { stable, beta }

extension UpdateChannelX on UpdateChannel {
  String get storageValue => switch (this) {
        UpdateChannel.stable => 'stable',
        UpdateChannel.beta => 'beta',
      };

  String get label => switch (this) {
        UpdateChannel.stable => 'اصلی (پایدار)',
        UpdateChannel.beta => 'بتا (آزمایشی)',
      };

  String get shortLabel => switch (this) {
        UpdateChannel.stable => 'پایدار',
        UpdateChannel.beta => 'بتا',
      };

  String get subtitle => switch (this) {
        UpdateChannel.stable =>
          'فقط انتشارهای نهایی و تست شده برای استفاده روزمره',
        UpdateChannel.beta =>
          'دریافت زودتر قابلیت های جدید و بهینه سازی های آزمایشی پیش از انتشار نهایی',
      };

  static UpdateChannel fromStorage(String? raw) =>
      raw?.trim().toLowerCase() == 'beta'
          ? UpdateChannel.beta
          : UpdateChannel.stable;
}

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.url,
    this.sha256 = '',
    this.notes = '',
    this.mandatory = false,
    this.sizeBytes = 0,
    this.publishedAt,
    this.preRelease = false,
    this.tagName = '',
    this.assetName = '',
  });

  final String version;
  final String url;
  final String sha256;
  final String notes;
  final bool mandatory;
  final int sizeBytes;
  final DateTime? publishedAt;
  final bool preRelease;
  final String tagName;
  final String assetName;

  UpdateChannel get channel =>
      preRelease ? UpdateChannel.beta : UpdateChannel.stable;

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final String version = JsonX.text(json['version']);
    final String tag = JsonX.text(json['tag_name'], version);
    return UpdateInfo(
      version: version,
      url: JsonX.text(json['url']),
      sha256: JsonX.text(json['sha256']),
      notes: JsonX.text(json['notes']),
      mandatory: JsonX.boolean(json['mandatory']),
      sizeBytes: JsonX.integer(json['size']),
      publishedAt: JsonX.dateTime(json['published_at']),
      preRelease:
          JsonX.boolean(json['prerelease']) || isPreReleaseTag(tag),
      tagName: tag,
      assetName: JsonX.text(json['asset_name']),
    );
  }

  /// تشخیص برچسب پیش انتشار (مانند `v1.0.40-beta.1`، `v1.0.40-rc.1`، `1.0.40.dev`).
  /// پسوند پلتفرمی `-windows` به تنهایی پیش انتشار محسوب نمی شود.
  static bool isPreReleaseTag(String raw) {
    final String clean = raw
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^v'), '')
        .replaceFirst(RegExp(r'-windows$'), '');
    return RegExp(r'(?:[-.](?:alpha|beta|rc|pre|preview|dev|nightly|canary))')
        .hasMatch(clean);
  }

  /// استخراج نسخه تمیز (با حفظ شناسه بتا در صورت وجود).
  static String normalizeVersion(String raw) {
    final String stripped = raw
        .trim()
        .replaceFirst(RegExp(r'^[vV]'), '')
        .replaceFirst(RegExp(r'-windows$', caseSensitive: false), '');
    final RegExpMatch? match = RegExp(
      r'^(\d+\.\d+\.\d+(?:[-.](?:alpha|beta|rc|pre|preview|dev|nightly|canary)(?:[.-]?\d+)?)?)',
      caseSensitive: false,
    ).firstMatch(stripped);
    return match?.group(1) ?? stripped;
  }

  /// مقایسه کامل نسخه پایدار و بتا (مثلا `1.0.40 > 1.0.40-beta.2 > 1.0.40-beta.1 > 1.0.39`).
  static int compareVersions(String a, String b) {
    final ({List<int> core, String preLabel, int preNum}) pa = _parseSemver(a);
    final ({List<int> core, String preLabel, int preNum}) pb = _parseSemver(b);
    for (int i = 0; i < 3; i++) {
      if (pa.core[i] != pb.core[i]) {
        return pa.core[i].compareTo(pb.core[i]);
      }
    }
    if (pa.preLabel.isEmpty && pb.preLabel.isEmpty) return 0;
    if (pa.preLabel.isEmpty) return 1; // پایدار بالاتر از بتای همان نسخه است.
    if (pb.preLabel.isEmpty) return -1;
    final int rankCmp = _preRank(pa.preLabel).compareTo(_preRank(pb.preLabel));
    if (rankCmp != 0) return rankCmp;
    return pa.preNum.compareTo(pb.preNum);
  }

  static int _preRank(String label) => switch (label) {
        'dev' || 'nightly' || 'canary' => 1,
        'alpha' => 2,
        'beta' || 'pre' || 'preview' => 3,
        'rc' => 4,
        _ => 0,
      };

  static ({List<int> core, String preLabel, int preNum}) _parseSemver(
    String value,
  ) {
    final String clean = normalizeVersion(value).toLowerCase();
    final RegExpMatch? coreMatch =
        RegExp(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(clean);
    final List<int> core = <int>[
      int.tryParse(coreMatch?.group(1) ?? '') ?? 0,
      int.tryParse(coreMatch?.group(2) ?? '') ?? 0,
      int.tryParse(coreMatch?.group(3) ?? '') ?? 0,
    ];
    final RegExpMatch? preMatch = RegExp(
      r'[-.](alpha|beta|rc|pre|preview|dev|nightly|canary)(?:[.-]?(\d+))?',
    ).firstMatch(clean);
    return (
      core: core,
      preLabel: preMatch?.group(1) ?? '',
      preNum: int.tryParse(preMatch?.group(2) ?? '') ?? 0,
    );
  }

  bool get isNewer => compareVersions(version, AppConfig.version) > 0;

  bool get isCurrentVersion =>
      compareVersions(version, AppConfig.version) == 0;

  /// یادداشت های انتشار پاک سازی شده برای نمایش خوانا داخل برنامه.
  List<String> get changelogItems {
    if (notes.trim().isEmpty) {
      return const <String>[];
    }
    final List<String> out = <String>[];
    for (final String raw in notes.replaceAll('\r\n', '\n').split('\n')) {
      String line = raw
          .replaceAll('\u200c', ' ')
          .replaceFirst(RegExp(r'^\s*#{1,6}\s*'), '')
          .replaceFirst(RegExp(r'^\s*[-*•]\s*'), '')
          .replaceAll('**', '')
          .replaceAll('`', '')
          .replaceAll(RegExp(r'https?://\S+'), '')
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();
      if (line.isEmpty || RegExp(r'^[-=_]{3,}$').hasMatch(line)) {
        continue;
      }
      if (line.toLowerCase().startsWith('full changelog')) {
        continue;
      }
      if (RegExp(
        r'^(?:sha[-_ ]?256\s*[:=]\s*)?[0-9a-fA-F]{64}(?:\s+\S+)?$',
        caseSensitive: false,
      ).hasMatch(line)) {
        continue;
      }
      out.add(line);
      if (out.length >= 8) {
        break;
      }
    }
    return out;
  }
}

enum SignInStage {
  needsProfile,
  codeSent,
  needsTelegram,
  awaitingTelegram,
  approved,
  denied,
  expired,
  smsFailed,
  unknown,
}

extension SignInStageX on SignInStage {
  static SignInStage fromString(String value) {
    switch (value) {
      case 'needs_profile':
        return SignInStage.needsProfile;
      case 'code_sent':
        return SignInStage.codeSent;
      case 'needs_telegram':
        return SignInStage.needsTelegram;
      case 'awaiting_telegram':
        return SignInStage.awaitingTelegram;
      case 'approved':
        return SignInStage.approved;
      case 'denied':
        return SignInStage.denied;
      case 'expired':
        return SignInStage.expired;
      case 'sms_failed':
        return SignInStage.smsFailed;
      default:
        return SignInStage.unknown;
    }
  }

  String get label {
    switch (this) {
      case SignInStage.needsProfile:
        return 'نیاز به نام و نام خانوادگی';
      case SignInStage.codeSent:
        return 'کد تایید ارسال شد';
      case SignInStage.needsTelegram:
        return 'نیاز به اتصال تلگرام';
      case SignInStage.awaitingTelegram:
        return 'در انتظار تایید در تلگرام';
      case SignInStage.approved:
        return 'تایید شد';
      case SignInStage.denied:
        return 'رد شد';
      case SignInStage.expired:
        return 'منقضی شد';
      case SignInStage.smsFailed:
        return 'ارسال پیامک ناموفق';
      case SignInStage.unknown:
        return 'نامشخص';
    }
  }
}

class SignInStart {
  const SignInStart({
    this.challenge = '',
    this.stage = SignInStage.unknown,
    this.accountExists = false,
    this.expiresAt,
    this.resendAfter = 120,
  });

  final String challenge;
  final SignInStage stage;
  final bool accountExists;
  final DateTime? expiresAt;
  final int resendAfter;

  factory SignInStart.fromJson(Map<String, dynamic> json) {
    return SignInStart(
      challenge: JsonX.text(json['challenge']),
      stage: SignInStageX.fromString(JsonX.text(json['stage'])),
      accountExists: JsonX.boolean(json['account_exists']),
      expiresAt: JsonX.dateTime(json['expires_at']),
      resendAfter: JsonX.integer(json['resend_after'], 120),
    );
  }
}

class SignInVerify {
  const SignInVerify({
    this.verified = false,
    this.challenge = '',
    this.stage = SignInStage.unknown,
    this.botUrl = '',
    this.message = '',
    this.expiresAt,
  });

  final bool verified;
  final String challenge;
  final SignInStage stage;
  final String botUrl;
  final String message;
  final DateTime? expiresAt;

  factory SignInVerify.fromJson(Map<String, dynamic> json) {
    return SignInVerify(
      verified: JsonX.boolean(json['verified']),
      challenge: JsonX.text(json['challenge']),
      stage: SignInStageX.fromString(JsonX.text(json['stage'])),
      botUrl: JsonX.text(json['bot']),
      message: JsonX.text(json['message']),
      expiresAt: JsonX.dateTime(json['expires_at']),
    );
  }
}

class SignInStatus {
  const SignInStatus({
    this.stage = SignInStage.unknown,
    this.challenge = '',
    this.deviceName = '',
    this.ip = '',
    this.secondsLeft = 0,
  });

  final SignInStage stage;
  final String challenge;
  final String deviceName;
  final String ip;
  final int secondsLeft;

  factory SignInStatus.fromJson(Map<String, dynamic> json) {
    return SignInStatus(
      stage: SignInStageX.fromString(JsonX.text(json['stage'])),
      challenge: JsonX.text(json['challenge']),
      deviceName: JsonX.text(json['device_name']),
      ip: JsonX.text(json['ip']),
      secondsLeft: JsonX.integer(json['seconds_left']),
    );
  }
}

class PingSample {
  const PingSample({
    required this.nodeId,
    required this.pingMs,
    required this.jitterMs,
    required this.ok,
    required this.at,
  });

  final String nodeId;
  final int pingMs;
  final int jitterMs;
  final bool ok;
  final DateTime at;
}

/// نام فارسی کشورها برای نمایش کنار پرچم.
///
/// در `models` است، نه در ویجت ها، چون هم رابط کاربری و هم کنترلر اتصال
/// (برای متن اعلان ویندوز) به آن نیاز دارند.
String countryNameFa(String code) {
  final String key = code.trim().toLowerCase();
  if (key.isEmpty) {
    return '';
  }
  return countryNamesFa[key] ?? '';
}

const Map<String, String> countryNamesFa = <String, String>{
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
