import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../core/utils.dart';

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

  /// پرچم کشور این سرور از نام یا میزبان آن استخراج می شود؛ اگر پیدا نشد،
  /// رشته خالی برمی گردد و برنامه پرچم نشان نمی دهد.
  String get flagCode {
    final String fromParams =
        JsonX.text(params['countryCode'] ?? params['flag'] ?? params['cc'])
            .toLowerCase();
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
    return '';
  }

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
    this.lastOnline,
    this.mode = '',
    this.subscriptionUrl = '',
    this.accountBase = '',
  });

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
  final DateTime? lastOnline;
  final String mode;
  final String subscriptionUrl;
  final String accountBase;

  Account copyWith({
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
    DateTime? lastOnline,
    String? mode,
    String? subscriptionUrl,
    String? accountBase,
  }) {
    return Account(
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
      expiryDate: expiryDate ?? this.expiryDate,
      lastOnline: lastOnline ?? this.lastOnline,
      mode: mode ?? this.mode,
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

  int get daysLeft {
    if (expiryDate == null) {
      return 0;
    }
    final int days = expiryDate!.difference(DateTime.now()).inHours ~/ 24;
    return days < 0 ? 0 : days;
  }

  bool get expired => expiryDate != null && expiryDate!.isBefore(DateTime.now());

  String get displayName => name.isNotEmpty ? name : (comment.isNotEmpty ? comment : 'کاربر آمبرلا');

  /// نوع سرویس بر اساس اطلاعات پنل: بسته زمانی یا حجمی.
  String get planLabel {
    if (comment.isNotEmpty) {
      return comment;
    }
    if (packageDays > 0) {
      return 'بسته ${Fa.num(packageDays)} روزه';
    }
    if (usageLimitGb > 0) {
      return 'بسته حجمی';
    }
    return 'نامشخص';
  }

  /// نشان می دهد حساب سالم است: فعال، منقضی نشده و غیرفعال نشده.
  bool get healthy => enable && !expired;

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
        'start_date': startDate?.toIso8601String(),
        'expiry_date': expiryDate?.toIso8601String(),
        'last_online': lastOnline?.toIso8601String(),
        'mode': mode,
        'subscription_url': subscriptionUrl,
        'account_base': accountBase,
      };

  factory Account.fromJson(Map<String, dynamic> json) {
    final Object? expiry = json['expiry_date'] ?? json['end_date'];
    return Account(
      uuid: JsonX.text(json['uuid']),
      name: JsonX.text(json['name']),
      phone: JsonX.text(json['phone']),
      telegramId: JsonX.text(json['telegram_id']),
      comment: JsonX.text(json['comment']),
      enable: JsonX.boolean(json['enable'], fallback: true),
      isActive: JsonX.boolean(json['is_active']),
      usageLimitGb: JsonX.number(json['usage_limit_GB']),
      currentUsageGb: JsonX.number(json['current_usage_GB']),
      packageDays: JsonX.integer(json['package_days']),
      startDate: JsonX.dateTime(json['start_date']),
      expiryDate: JsonX.dateTime(expiry),
      lastOnline: JsonX.dateTime(json['last_online']),
      mode: JsonX.text(json['mode']),
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

  static const Map<String, String> categoryLabels = <String, String>{
    'adult': 'محتوای بزرگسال',
    'social': 'شبکه های اجتماعی',
    'gambling': 'شرط بندی',
    'ads': 'تبلیغات',
    'streaming': 'ویدیو و پخش',
    'dating': 'دوستیابی',
    'violence': 'محتوای خشن',
    'messaging': 'پیام رسان ها',
  };

  FilterSettings copyWith({
    bool? enabled,
    List<String>? categories,
    List<String>? customDomains,
  }) {
    return FilterSettings(
      enabled: enabled ?? this.enabled,
      categories: categories ?? this.categories,
      customDomains: customDomains ?? this.customDomains,
      updatedBy: updatedBy,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'enabled': enabled,
        'categories': categories,
        'custom_domains': customDomains,
      };

  factory FilterSettings.fromJson(Map<String, dynamic> json) {
    return FilterSettings(
      enabled: JsonX.boolean(json['enabled']),
      categories: JsonX.asList(json['categories'])
          .map((Object? item) => item.toString())
          .toList(),
      customDomains: JsonX.asList(json['custom_domains'])
          .map((Object? item) => item.toString())
          .toList(),
      updatedBy: JsonX.text(json['updated_by'], 'app'),
      updatedAt: JsonX.text(json['updated_at']),
    );
  }

  static const FilterSettings empty = FilterSettings();
}

class SessionData {
  const SessionData({
    required this.token,
    required this.uuid,
    required this.deviceId,
    required this.account,
    required this.filter,
    this.signedInAt,
  });

  final String token;
  final String uuid;
  final String deviceId;
  final Account account;
  final FilterSettings filter;
  final DateTime? signedInAt;

  SessionData copyWith({Account? account, FilterSettings? filter}) {
    return SessionData(
      token: token,
      uuid: uuid,
      deviceId: deviceId,
      account: account ?? this.account,
      filter: filter ?? this.filter,
      signedInAt: signedInAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'token': token,
        'uuid': uuid,
        'device_id': deviceId,
        'account': account.toJson(),
        'filter': filter.toJson(),
        'signed_in_at': signedInAt?.toIso8601String(),
      };

  factory SessionData.fromJson(Map<String, dynamic> json) {
    return SessionData(
      token: JsonX.text(json['token']),
      uuid: JsonX.text(json['uuid']),
      deviceId: JsonX.text(json['device_id']),
      account: Account.fromJson(JsonX.asMap(json['account'])),
      filter: FilterSettings.fromJson(JsonX.asMap(json['filter'])),
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
  });

  final int id;
  final String title;
  final String body;
  final String level;
  final DateTime? sentAt;
  final bool read;

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        title: title,
        body: body,
        level: level,
        sentAt: sentAt,
        read: read ?? this.read,
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
    return AppNotification(
      id: JsonX.integer(json['id']),
      title: JsonX.text(json['title']),
      body: JsonX.text(json['body']),
      level: JsonX.text(json['level'], 'info'),
      sentAt: JsonX.dateTime(json['sent_at']),
      read: JsonX.boolean(json['read']),
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

enum TunStack { mixed, gvisor, system }

extension TunStackX on TunStack {
  String get label {
    switch (this) {
      case TunStack.mixed:
        return 'ترکیبی (سریع ترین)';
      case TunStack.gvisor:
        return 'کاربرفضا';
      case TunStack.system:
        return 'سیستم';
    }
  }
}

class AppSettings {
  const AppSettings({
    this.theme = ThemePreference.dark,
    this.autoConnect = false,
    this.killSwitch = false,
    this.tunMode = true,
    this.startWithWindows = false,
    this.minimizeToTray = true,
    this.closeToTray = true,
    this.soundEnabled = true,
    this.notificationsEnabled = true,
    this.selectionMode = SelectionMode.auto,
    this.corePreference = CorePreference.auto,
    this.autoFailover = true,
    this.stickyMinutes = 30,
    this.tunStack = TunStack.mixed,
    this.mtu = 9000,
    this.blockIpv6 = true,
    this.strictRoute = true,
    this.dnsOverTunnel = true,
    this.showSpeedInTray = true,
    this.occasionEffects = true,
    this.checkUpdatesOnStart = true,
    this.firstName = '',
    this.lastName = '',
    this.phone = '',
    this.lastNodeId = '',
    this.gatewayBase = '',
    this.pingIntervalSeconds = 120,
    this.turboMode = false,
    this.logLevel = 'info',
    this.modeChoiceExplicit = false,
    this.showCli = true,
  });

  final ThemePreference theme;
  final bool autoConnect;
  final bool killSwitch;

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
  final bool autoFailover;
  final int stickyMinutes;
  final TunStack tunStack;
  final int mtu;
  final bool blockIpv6;
  final bool strictRoute;
  final bool dnsOverTunnel;
  final bool showSpeedInTray;
  final bool occasionEffects;
  final bool checkUpdatesOnStart;
  final String firstName;
  final String lastName;
  final String phone;
  final String lastNodeId;
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
    bool? tunMode,
    bool? startWithWindows,
    bool? minimizeToTray,
    bool? closeToTray,
    bool? soundEnabled,
    bool? notificationsEnabled,
    SelectionMode? selectionMode,
    CorePreference? corePreference,
    bool? autoFailover,
    int? stickyMinutes,
    TunStack? tunStack,
    int? mtu,
    bool? blockIpv6,
    bool? strictRoute,
    bool? dnsOverTunnel,
    bool? showSpeedInTray,
    bool? occasionEffects,
    bool? checkUpdatesOnStart,
    String? firstName,
    String? lastName,
    String? phone,
    String? lastNodeId,
    String? gatewayBase,
    int? pingIntervalSeconds,
    bool? turboMode,
    String? logLevel,
    bool? modeChoiceExplicit,
    bool? showCli,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      autoConnect: autoConnect ?? this.autoConnect,
      killSwitch: killSwitch ?? this.killSwitch,
      tunMode: tunMode ?? this.tunMode,
      startWithWindows: startWithWindows ?? this.startWithWindows,
      minimizeToTray: minimizeToTray ?? this.minimizeToTray,
      closeToTray: closeToTray ?? this.closeToTray,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      selectionMode: selectionMode ?? this.selectionMode,
      corePreference: corePreference ?? this.corePreference,
      autoFailover: autoFailover ?? this.autoFailover,
      stickyMinutes: stickyMinutes ?? this.stickyMinutes,
      tunStack: tunStack ?? this.tunStack,
      mtu: mtu ?? this.mtu,
      blockIpv6: blockIpv6 ?? this.blockIpv6,
      strictRoute: strictRoute ?? this.strictRoute,
      dnsOverTunnel: dnsOverTunnel ?? this.dnsOverTunnel,
      showSpeedInTray: showSpeedInTray ?? this.showSpeedInTray,
      occasionEffects: occasionEffects ?? this.occasionEffects,
      checkUpdatesOnStart: checkUpdatesOnStart ?? this.checkUpdatesOnStart,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      lastNodeId: lastNodeId ?? this.lastNodeId,
      gatewayBase: gatewayBase ?? this.gatewayBase,
      pingIntervalSeconds: pingIntervalSeconds ?? this.pingIntervalSeconds,
      turboMode: turboMode ?? this.turboMode,
      logLevel: logLevel ?? this.logLevel,
      modeChoiceExplicit: modeChoiceExplicit ?? this.modeChoiceExplicit,
      showCli: showCli ?? this.showCli,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'theme': theme.name,
        'autoConnect': autoConnect,
        'killSwitch': killSwitch,
        'tunMode': tunMode,
        'startWithWindows': startWithWindows,
        'minimizeToTray': minimizeToTray,
        'closeToTray': closeToTray,
        'soundEnabled': soundEnabled,
        'notificationsEnabled': notificationsEnabled,
        'selectionMode': selectionMode.name,
        'corePreference': corePreference.name,
        'autoFailover': autoFailover,
        'stickyMinutes': stickyMinutes,
        'tunStack': tunStack.name,
        'mtu': mtu,
        'blockIpv6': blockIpv6,
        'strictRoute': strictRoute,
        'dnsOverTunnel': dnsOverTunnel,
        'showSpeedInTray': showSpeedInTray,
        'occasionEffects': occasionEffects,
        'checkUpdatesOnStart': checkUpdatesOnStart,
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'lastNodeId': lastNodeId,
        'gatewayBase': gatewayBase,
        'pingIntervalSeconds': pingIntervalSeconds,
        'turboMode': turboMode,
        'logLevel': logLevel,
        'modeChoiceExplicit': modeChoiceExplicit,
        'showCli': showCli,
      };

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

    return AppSettings(
      theme: pick(ThemePreference.values, json['theme'], ThemePreference.dark),
      autoConnect: JsonX.boolean(json['autoConnect']),
      killSwitch: JsonX.boolean(json['killSwitch'], fallback: false),
      tunMode: JsonX.boolean(json['tunMode'], fallback: true),
      startWithWindows: JsonX.boolean(json['startWithWindows']),
      minimizeToTray: JsonX.boolean(json['minimizeToTray'], fallback: true),
      closeToTray: JsonX.boolean(json['closeToTray'], fallback: true),
      soundEnabled: JsonX.boolean(json['soundEnabled'], fallback: true),
      notificationsEnabled:
          JsonX.boolean(json['notificationsEnabled'], fallback: true),
      selectionMode:
          pick(SelectionMode.values, json['selectionMode'], SelectionMode.auto),
      corePreference:
          pick(CorePreference.values, json['corePreference'], CorePreference.auto),
      autoFailover: JsonX.boolean(json['autoFailover'], fallback: true),
      stickyMinutes: JsonX.integer(json['stickyMinutes'], 30),
      tunStack: pick(TunStack.values, json['tunStack'], TunStack.mixed),
      mtu: JsonX.integer(json['mtu'], 9000),
      blockIpv6: JsonX.boolean(json['blockIpv6'], fallback: true),
      strictRoute: JsonX.boolean(json['strictRoute'], fallback: true),
      dnsOverTunnel: JsonX.boolean(json['dnsOverTunnel'], fallback: true),
      showSpeedInTray: JsonX.boolean(json['showSpeedInTray'], fallback: true),
      occasionEffects: JsonX.boolean(json['occasionEffects'], fallback: true),
      checkUpdatesOnStart:
          JsonX.boolean(json['checkUpdatesOnStart'], fallback: true),
      firstName: JsonX.text(json['firstName']),
      lastName: JsonX.text(json['lastName']),
      phone: JsonX.text(json['phone']),
      lastNodeId: JsonX.text(json['lastNodeId']),
      gatewayBase: JsonX.text(json['gatewayBase']),
      pingIntervalSeconds: JsonX.integer(json['pingIntervalSeconds'], 120),
      turboMode: JsonX.boolean(json['turboMode']),
      logLevel: JsonX.text(json['logLevel'], 'info'),
      modeChoiceExplicit: JsonX.boolean(json['modeChoiceExplicit']),
      showCli: JsonX.boolean(json['showCli']),
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
    this.arch = 'x64',
    this.machineId = '',
    this.cpu = '',
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
  final String arch;
  final String machineId;
  final String cpu;
  final String localIp;
  final String mac;
  final bool elevated;
  final String ip;
  final String city;
  final String country;

  String get deviceName => hostname.isNotEmpty ? hostname : 'کامپیوتر ویندوز';

  String get platformLabel {
    final String system = os.isNotEmpty ? os : 'Windows';
    return '$system | $arch';
  }

  String get summary {
    final StringBuffer buffer = StringBuffer();
    buffer.write('دستگاه: $deviceName');
    if (username.isNotEmpty) {
      buffer.write(' | کاربر: $username');
    }
    if (os.isNotEmpty) {
      buffer.write(' | $os');
    }
    if (localIp.isNotEmpty) {
      buffer.write(' | IP داخلی: ${Fa.num(localIp)}');
    }
    if (city.isNotEmpty || country.isNotEmpty) {
      buffer.write(' | موقعیت: ${Fa.num(country)} ${Fa.num(city)}');
    }
    return buffer.toString();
  }

  DeviceProfile copyWith({String? ip, String? city, String? country, bool? elevated}) {
    return DeviceProfile(
      hostname: hostname,
      username: username,
      os: os,
      arch: arch,
      machineId: machineId,
      cpu: cpu,
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
      arch: JsonX.text(json['arch'], 'x64'),
      machineId: JsonX.text(json['machineId']),
      cpu: JsonX.text(json['cpu']),
      localIp: JsonX.text(json['localIp']),
      mac: JsonX.text(json['mac']),
      elevated: JsonX.boolean(json['elevated']),
    );
  }

  static const DeviceProfile empty = DeviceProfile();
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
  });

  final String version;
  final String url;
  final String sha256;
  final String notes;
  final bool mandatory;
  final int sizeBytes;
  final DateTime? publishedAt;

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: JsonX.text(json['version']),
      url: JsonX.text(json['url']),
      sha256: JsonX.text(json['sha256']),
      notes: JsonX.text(json['notes']),
      mandatory: JsonX.boolean(json['mandatory']),
      sizeBytes: JsonX.integer(json['size']),
      publishedAt: JsonX.dateTime(json['published_at']),
    );
  }

  bool get isNewer {
    final List<int> remote = _parts(version);
    final List<int> local = _parts(AppConfig.version);
    for (int i = 0; i < 3; i++) {
      final int r = i < remote.length ? remote[i] : 0;
      final int l = i < local.length ? local[i] : 0;
      if (r != l) {
        return r > l;
      }
    }
    return false;
  }

  static List<int> _parts(String value) => value
      .split(RegExp(r'[^0-9]'))
      .where((String item) => item.isNotEmpty)
      .map(int.parse)
      .toList();
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
