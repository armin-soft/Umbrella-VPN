import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart' show IconData, Icons;

import '../core/persian.dart';

/// حالت سرویس ورودی هسته؛ هم راستا با سه حالت سریع صفحه اتصال و بخش ورودی.
enum InboundServiceMode { proxy, systemProxy, vpn }

extension InboundServiceModeX on InboundServiceMode {
  String get shortLabel => switch (this) {
        InboundServiceMode.proxy => 'پروکسی',
        InboundServiceMode.systemProxy => 'پروکسی سیستم',
        InboundServiceMode.vpn => 'تونل کامل',
      };

  String get fullLabel => switch (this) {
        InboundServiceMode.proxy => 'فقط سرویس پروکسی',
        InboundServiceMode.systemProxy => 'تنظیم پروکسی سیستم',
        InboundServiceMode.vpn => 'تونل کامل',
      };

  String get description => switch (this) {
        InboundServiceMode.proxy =>
          'فقط پورت محلی ساکس ۵ و وب باز می شود و تنظیمات ویندوز تغییر نمی کند',
        InboundServiceMode.systemProxy =>
          'پروکسی ویندوز روی پورت محلی تنظیم می شود (بدون نیاز به کارت شبکه تونل)',
        InboundServiceMode.vpn =>
          'عبور تمام برنامه ها و بازی ها از کارت شبکه امن مجازی',
      };

  IconData get icon => switch (this) {
        InboundServiceMode.proxy => Icons.hub_rounded,
        InboundServiceMode.systemProxy => Icons.desktop_windows_rounded,
        InboundServiceMode.vpn => Icons.shield_rounded,
      };

  bool get enablesTun => this == InboundServiceMode.vpn;
  bool get enablesSystemProxy => this == InboundServiceMode.systemProxy;
}

/// استراتژی حل دامنه در دی ان اس اصلی و مستقیم هسته.
enum DnsDomainStrategy { asIs, preferIpv6, preferIpv4, ipv4Only, ipv6Only }

extension DnsDomainStrategyX on DnsDomainStrategy {
  String get coreValue => switch (this) {
        DnsDomainStrategy.asIs => 'as_is',
        DnsDomainStrategy.preferIpv6 => 'prefer_ipv6',
        DnsDomainStrategy.preferIpv4 => 'prefer_ipv4',
        DnsDomainStrategy.ipv4Only => 'ipv4_only',
        DnsDomainStrategy.ipv6Only => 'ipv6_only',
      };

  String get label => switch (this) {
        DnsDomainStrategy.asIs => 'خودکار',
        DnsDomainStrategy.preferIpv6 => 'ترجیح آی پی نسخه ۶',
        DnsDomainStrategy.preferIpv4 => 'ترجیح آی پی نسخه ۴',
        DnsDomainStrategy.ipv4Only => 'فقط آی پی نسخه ۴',
        DnsDomainStrategy.ipv6Only => 'فقط آی پی نسخه ۶',
      };

  IconData get icon => switch (this) {
        DnsDomainStrategy.asIs => Icons.hdr_auto_rounded,
        DnsDomainStrategy.preferIpv6 => Icons.filter_6_rounded,
        DnsDomainStrategy.preferIpv4 => Icons.filter_4_rounded,
        DnsDomainStrategy.ipv4Only => Icons.looks_4_rounded,
        DnsDomainStrategy.ipv6Only => Icons.looks_6_rounded,
      };
}

/// حالت مسیریابی آی پی نسخه ۶ در هسته.
enum Ipv6RouteMode { ipv4Only, preferIpv4, preferIpv6 }

extension Ipv6RouteModeX on Ipv6RouteMode {
  String get coreValue => switch (this) {
        Ipv6RouteMode.ipv4Only => 'ipv4_only',
        Ipv6RouteMode.preferIpv4 => 'prefer_ipv4',
        Ipv6RouteMode.preferIpv6 => 'prefer_ipv6',
      };

  String get label => switch (this) {
        Ipv6RouteMode.ipv4Only => 'خاموش (فقط نسخه ۴)',
        Ipv6RouteMode.preferIpv4 => 'روشن، اول نسخه ۴',
        Ipv6RouteMode.preferIpv6 => 'روشن، اول نسخه ۶',
      };

  IconData get icon => switch (this) {
        Ipv6RouteMode.ipv4Only => Icons.looks_4_rounded,
        Ipv6RouteMode.preferIpv4 => Icons.filter_4_rounded,
        Ipv6RouteMode.preferIpv6 => Icons.filter_6_rounded,
      };

  String get description => switch (this) {
        Ipv6RouteMode.ipv4Only =>
          'برنامه ها فقط آی پی نسخه ۴ به کار می برند و از نشت یا مکث نسخه ۶ جلوگیری می شود',
        Ipv6RouteMode.preferIpv4 =>
          'اول آی پی نسخه ۴ و در صورت پشتیبانی سرور فعال، نسخه ۶ نیز عبور داده می شود',
        Ipv6RouteMode.preferIpv6 =>
          'اولویت با آی پی نسخه ۶ روی سرورهایی که پشتیبانی از آن تایید شده است',
      };
}

/// منطقه مسیریابی برای عبور مستقیم ترافیک داخلی منطقه انتخاب شده.
enum RoutingRegion { other, ir, tr, ru, cn, af, id, br }

extension RoutingRegionX on RoutingRegion {
  String get coreValue => name;

  String get label => switch (this) {
        RoutingRegion.other => 'سایر (همه از تونل)',
        RoutingRegion.ir => 'ایران (سایت های داخلی مستقیم)',
        RoutingRegion.tr => 'ترکیه',
        RoutingRegion.ru => 'روسیه',
        RoutingRegion.cn => 'چین',
        RoutingRegion.af => 'افغانستان',
        RoutingRegion.id => 'اندونزی',
        RoutingRegion.br => 'برزیل',
      };

  String get shortLabel => switch (this) {
        RoutingRegion.other => 'سایر',
        RoutingRegion.ir => 'ایران',
        RoutingRegion.tr => 'ترکیه',
        RoutingRegion.ru => 'روسیه',
        RoutingRegion.cn => 'چین',
        RoutingRegion.af => 'افغانستان',
        RoutingRegion.id => 'اندونزی',
        RoutingRegion.br => 'برزیل',
      };

  IconData get icon => switch (this) {
        RoutingRegion.other => Icons.public_rounded,
        RoutingRegion.ir => Icons.place_rounded,
        RoutingRegion.tr ||
        RoutingRegion.ru ||
        RoutingRegion.cn ||
        RoutingRegion.af ||
        RoutingRegion.id ||
        RoutingRegion.br =>
          Icons.flag_rounded,
      };
}

/// These are auxiliary hops around an authorized Umbrella profile, never
/// standalone profiles, imported subscriptions or an alternate access path.
enum ChainPosition { off, extraSecurity, unblocker }

enum ChainTransport { automatic, wireguard, awg, masque, psiphon }

enum WarpEndpoint { assigned, scan, custom }

extension ChainPositionX on ChainPosition {
  String get coreValue => switch (this) {
        ChainPosition.off => 'off',
        ChainPosition.extraSecurity => 'extra_security',
        ChainPosition.unblocker => 'unblocker',
      };

  String get label => switch (this) {
        ChainPosition.off => 'خاموش',
        ChainPosition.extraSecurity => 'امنیت بیشتر',
        ChainPosition.unblocker => 'رفع فیلتر پروکسی',
      };

  IconData get icon => switch (this) {
        ChainPosition.off => Icons.power_settings_new_rounded,
        ChainPosition.extraSecurity => Icons.verified_user_rounded,
        ChainPosition.unblocker => Icons.account_tree_rounded,
      };
}

extension ChainTransportX on ChainTransport {
  String get coreValue => switch (this) {
        ChainTransport.automatic => 'warp_auto',
        ChainTransport.wireguard => 'warp',
        ChainTransport.awg => 'warp_awg',
        ChainTransport.masque => 'warp_masque',
        ChainTransport.psiphon => 'psiphon',
      };

  String get label => switch (this) {
        ChainTransport.automatic => 'وارپ (خودکار)',
        ChainTransport.wireguard => 'وارپ — وایرگارد',
        ChainTransport.awg => 'وارپ — آمنزیا',
        ChainTransport.masque => 'وارپ — ماسک',
        ChainTransport.psiphon => 'سایفون',
      };

  String get tunnelLabel => switch (this) {
        ChainTransport.automatic => 'خودکار',
        ChainTransport.wireguard => 'وایرگارد',
        ChainTransport.awg => 'آمنزیا',
        ChainTransport.masque => 'ماسک',
        ChainTransport.psiphon => 'سایفون',
      };

  String get quickLabel =>
      this == ChainTransport.psiphon ? 'سایفون' : 'وارپ';

  IconData get icon => switch (this) {
        ChainTransport.automatic => Icons.auto_awesome_rounded,
        ChainTransport.wireguard => Icons.vpn_lock_rounded,
        ChainTransport.awg => Icons.enhanced_encryption_rounded,
        ChainTransport.masque => Icons.rocket_launch_rounded,
        ChainTransport.psiphon => Icons.language_rounded,
      };

  IconData get quickIcon => this == ChainTransport.psiphon
      ? Icons.language_rounded
      : Icons.cloud_done_rounded;

  bool get isWarp => this != ChainTransport.psiphon;
}

extension WarpEndpointX on WarpEndpoint {
  String get coreValue => switch (this) {
        WarpEndpoint.assigned => 'profile',
        WarpEndpoint.scan => 'scan',
        WarpEndpoint.custom => 'custom',
      };

  String get label => switch (this) {
        WarpEndpoint.assigned => 'تعیین شده توسط کلادفلر',
        WarpEndpoint.scan => 'جست وجو',
        WarpEndpoint.custom => 'دستی',
      };

  IconData get icon => switch (this) {
        WarpEndpoint.assigned => Icons.cloud_done_rounded,
        WarpEndpoint.scan => Icons.radar_rounded,
        WarpEndpoint.custom => Icons.edit_location_alt_rounded,
      };
}

T _pick<T extends Enum>(List<T> values, dynamic value, T fallback) =>
    values.where((T item) => item.name == value).firstOrNull ?? fallback;

int _number(dynamic value, int fallback) => value is int ? value : fallback;

bool _validOptionalRange(String raw, {int min = 0, int max = 65535}) {
  final String text = Fa.toEn(raw.trim());
  if (text.isEmpty) {
    return true;
  }
  final RegExpMatch? match =
      RegExp(r'^(\d{1,5})(?:-(\d{1,5}))?$').firstMatch(text);
  if (match == null) {
    return false;
  }
  final int a = int.parse(match.group(1)!);
  final int b = match.group(2) == null ? a : int.parse(match.group(2)!);
  return a >= min && b <= max && a <= b;
}

class ChainSettings {
  const ChainSettings({
    this.position = ChainPosition.off,
    this.transport = ChainTransport.automatic,
    this.endpoint = WarpEndpoint.assigned,
    this.address = '',
    this.port = 2408,
    this.mtu = 0,
    this.scanCount = 64,
    this.scanConcurrency = 8,
    this.scanTimeout = 2000,
    this.scanMaxRtt = 1000,
    this.searchNoise = true,
    this.masqueProtocol = 'auto',
    this.licenseKey = '',
    this.psiphonRegion = 'AUTO',
    this.noiseMode = '',
    this.noiseCount = '',
    this.noiseSize = '',
    this.noiseDelay = '',
    this.configurationInvalid = false,
  });

  final ChainPosition position;
  final ChainTransport transport;
  final WarpEndpoint endpoint;
  final String address;
  final int port;
  final int mtu;
  final int scanCount;
  final int scanConcurrency;
  final int scanTimeout;
  final int scanMaxRtt;
  final bool searchNoise;
  final bool configurationInvalid;
  final String masqueProtocol;
  final String licenseKey;
  final String psiphonRegion;
  final String noiseMode;
  final String noiseCount;
  final String noiseSize;
  final String noiseDelay;

  bool get enabled => position != ChainPosition.off || configurationInvalid;

  static const Map<String, String> regionLabels = <String, String>{
    'AUTO': 'خودکار',
    'AT': 'اتریش',
    'AU': 'استرالیا',
    'BE': 'بلژیک',
    'BG': 'بلغارستان',
    'CA': 'کانادا',
    'CH': 'سوئیس',
    'CZ': 'جمهوری چک',
    'DE': 'آلمان',
    'DK': 'دانمارک',
    'EE': 'استونی',
    'ES': 'اسپانیا',
    'FI': 'فنلاند',
    'FR': 'فرانسه',
    'GB': 'بریتانیا',
    'HR': 'کرواسی',
    'HU': 'مجارستان',
    'IE': 'ایرلند',
    'IN': 'هند',
    'IT': 'ایتالیا',
    'JP': 'ژاپن',
    'LV': 'لتونی',
    'NL': 'هلند',
    'NO': 'نروژ',
    'PL': 'لهستان',
    'PT': 'پرتغال',
    'RO': 'رومانی',
    'RS': 'صربستان',
    'SE': 'سوئد',
    'SG': 'سنگاپور',
    'SK': 'اسلواکی',
    'US': 'ایالات متحده',
  };

  static IconData regionIcon(String code) =>
      code == 'AUTO' ? Icons.auto_awesome_rounded : Icons.public_rounded;

  static IconData noiseIcon(String mode) => switch (mode) {
        '' => Icons.do_not_disturb_on_outlined,
        'none' => Icons.radio_button_unchecked_rounded,
        'quic' => Icons.bolt_rounded,
        'random' => Icons.shuffle_rounded,
        'tls' => Icons.lock_rounded,
        'dns' => Icons.dns_rounded,
        't_mobile' => Icons.cell_tower_rounded,
        _ => Icons.blur_on_rounded,
      };

  static const List<String> regions = <String>[
    'AUTO',
    'AT',
    'AU',
    'BE',
    'BG',
    'CA',
    'CH',
    'CZ',
    'DE',
    'DK',
    'EE',
    'ES',
    'FI',
    'FR',
    'GB',
    'HR',
    'HU',
    'IE',
    'IN',
    'IT',
    'JP',
    'LV',
    'NL',
    'NO',
    'PL',
    'PT',
    'RO',
    'RS',
    'SE',
    'SG',
    'SK',
    'US',
  ];

  static const Map<String, String> noiseModes = <String, String>{
    '': 'خودکار',
    'quic': 'کوئیک (وب امن)',
    'dns': 'دی ان اس',
    'stun': 'تماس تصویری',
    'sip': 'تماس اینترنتی',
    'm4': 'استاندارد چهارم',
    'm6': 'تصادفی ششم',
  };

  static String regionLabel(String code) =>
      regionLabels[code.toUpperCase()] ?? code;

  ChainSettings copyWith({
    ChainPosition? position,
    ChainTransport? transport,
    WarpEndpoint? endpoint,
    String? address,
    int? port,
    int? mtu,
    int? scanCount,
    int? scanConcurrency,
    int? scanTimeout,
    int? scanMaxRtt,
    bool? searchNoise,
    String? masqueProtocol,
    String? licenseKey,
    String? psiphonRegion,
    String? noiseMode,
    String? noiseCount,
    String? noiseSize,
    String? noiseDelay,
    bool? configurationInvalid,
  }) {
    return ChainSettings(
      position: position ?? this.position,
      transport: transport ?? this.transport,
      endpoint: endpoint ?? this.endpoint,
      address: address ?? this.address,
      port: port ?? this.port,
      mtu: mtu ?? this.mtu,
      scanCount: scanCount ?? this.scanCount,
      scanConcurrency: scanConcurrency ?? this.scanConcurrency,
      scanTimeout: scanTimeout ?? this.scanTimeout,
      scanMaxRtt: scanMaxRtt ?? this.scanMaxRtt,
      searchNoise: searchNoise ?? this.searchNoise,
      masqueProtocol: masqueProtocol ?? this.masqueProtocol,
      licenseKey: licenseKey ?? this.licenseKey,
      psiphonRegion: psiphonRegion ?? this.psiphonRegion,
      noiseMode: noiseMode ?? this.noiseMode,
      noiseCount: noiseCount ?? this.noiseCount,
      noiseSize: noiseSize ?? this.noiseSize,
      noiseDelay: noiseDelay ?? this.noiseDelay,
      configurationInvalid: configurationInvalid ?? this.configurationInvalid,
    );
  }

  /// فعال سازی سریع «امنیت بیشتر» با تنظیم امن نقطه اتصال.
  ChainSettings activateExtraSecurity(ChainTransport mode) {
    final ChainTransport resolved = mode == ChainTransport.psiphon
        ? ChainTransport.psiphon
        : (transport.isWarp && mode == ChainTransport.automatic
            ? transport
            : mode);
    WarpEndpoint safeEndpoint = endpoint;
    if (safeEndpoint == WarpEndpoint.scan) {
      safeEndpoint = WarpEndpoint.assigned;
    }
    if (safeEndpoint == WarpEndpoint.custom &&
        (resolved == ChainTransport.masque ||
            InternetAddress.tryParse(address.trim()) == null)) {
      safeEndpoint = WarpEndpoint.assigned;
    }
    return copyWith(
      position: ChainPosition.extraSecurity,
      transport: resolved,
      endpoint: safeEndpoint,
      configurationInvalid: false,
    );
  }

  /// فعال سازی سریع «رفع فیلتر پروکسی» با اسکن خودکار نقطه اتصال تمیز WARP.
  ChainSettings activateUnblocker(ChainTransport mode) {
    final ChainTransport resolved = mode == ChainTransport.psiphon
        ? ChainTransport.psiphon
        : (transport.isWarp && mode == ChainTransport.automatic
            ? transport
            : mode);
    WarpEndpoint nextEndpoint = endpoint;
    if (resolved != ChainTransport.psiphon) {
      if (nextEndpoint == WarpEndpoint.assigned) {
        nextEndpoint = WarpEndpoint.scan;
      } else if (nextEndpoint == WarpEndpoint.custom &&
          (resolved == ChainTransport.masque ||
              InternetAddress.tryParse(address.trim()) == null)) {
        nextEndpoint = WarpEndpoint.scan;
      }
    }
    return copyWith(
      position: ChainPosition.unblocker,
      transport: resolved,
      endpoint: nextEndpoint,
      configurationInvalid: false,
    );
  }

  ChainSettings deactivate() => copyWith(
        position: ChainPosition.off,
        configurationInvalid: false,
      );

  String? get validationError {
    if (configurationInvalid) {
      return 'تنظیمات زنجیره ذخیره شده نامعتبر است؛ دوباره ذخیره کنید';
    }
    if (port < 1 || port > 65535) {
      return 'پورت باید بین ۱ و ۶۵۵۳۵ باشد';
    }
    if (mtu != 0 && (mtu < 1280 || mtu > 1500)) {
      return 'اندازه بسته زنجیره باید صفر (خودکار) یا بین ۱۲۸۰ تا ۱۵۰۰ باشد';
    }
    if (scanCount < 1 ||
        scanCount > 256 ||
        scanConcurrency < 1 ||
        scanConcurrency > 32 ||
        scanConcurrency > scanCount) {
      return 'تعداد اسکن بین ۱ تا ۲۵۶ و هم زمانی بین ۱ تا ۳۲ و حداکثر برابر تعداد است';
    }
    if (scanTimeout < 250 ||
        scanTimeout > 10000 ||
        scanMaxRtt < 100 ||
        scanMaxRtt > scanTimeout) {
      return 'مهلت اسکن بین ۲۵۰ تا ۱۰۰۰۰ و تاخیر مجاز بین ۱۰۰ تا مهلت است';
    }
    if (!<String>['auto', 'h2', 'h3'].contains(masqueProtocol)) {
      return 'نسخه انتقال ماسک نامعتبر است';
    }
    if (!regions.contains(psiphonRegion)) {
      return 'منطقه سایفون نامعتبر است';
    }
    if (licenseKey.length > 128 || licenseKey.contains(RegExp(r'\s'))) {
      return 'کلید اشتراک وارپ نامعتبر است';
    }
    if (!noiseModes.containsKey(noiseMode)) {
      return 'حالت نویز نامعتبر است';
    }
    if (!_validOptionalRange(noiseCount, min: 1, max: 200) ||
        !_validOptionalRange(noiseSize, min: 1, max: 1500) ||
        !_validOptionalRange(noiseDelay, min: 1, max: 10000)) {
      return 'بازه نویز نامعتبر است (مانند ۵ تا ۱۰)';
    }
    if (transport != ChainTransport.psiphon &&
        endpoint == WarpEndpoint.custom) {
      final InternetAddress? ip = InternetAddress.tryParse(address.trim());
      if (ip == null ||
          ip.isLoopback ||
          ip.isLinkLocal ||
          ip.isMulticast ||
          ip.address == '0.0.0.0' ||
          ip.address == '::') {
        return 'نشانی آی پی معتبر نقطه اتصال را وارد کنید';
      }
      if (transport == ChainTransport.masque) {
        return 'در حالت ماسک فقط نقطه اتصال اختصاص یافته کلادفلر پشتیبانی می شود';
      }
    }
    if (enabled &&
        endpoint == WarpEndpoint.scan &&
        position == ChainPosition.extraSecurity &&
        transport != ChainTransport.psiphon) {
      return 'اسکن فقط در حالت رفع مسدودیت ممکن است؛ برای امنیت بیشتر حالت کلادفلر را انتخاب کنید';
    }
    return null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'configurationInvalid': configurationInvalid,
        'position': position.name,
        'transport': transport.name,
        'endpoint': endpoint.name,
        'address': address.trim(),
        'port': port,
        'mtu': mtu,
        'scanCount': scanCount,
        'scanConcurrency': scanConcurrency,
        'scanTimeout': scanTimeout,
        'scanMaxRtt': scanMaxRtt,
        'searchNoise': searchNoise,
        'masqueProtocol': masqueProtocol,
        'licenseKey': licenseKey,
        'psiphonRegion': psiphonRegion,
        if (noiseMode.isNotEmpty) 'noiseMode': noiseMode,
        if (noiseCount.trim().isNotEmpty) 'noiseCount': noiseCount.trim(),
        if (noiseSize.trim().isNotEmpty) 'noiseSize': noiseSize.trim(),
        if (noiseDelay.trim().isNotEmpty) 'noiseDelay': noiseDelay.trim(),
      };

  factory ChainSettings.fromJson(Map<String, dynamic> json) {
    final String rawNoise =
        json['noiseMode'] is String ? (json['noiseMode'] as String).trim() : '';
    final String rawRegion = json['psiphonRegion'] is String
        ? (json['psiphonRegion'] as String).trim().toUpperCase()
        : 'AUTO';
    return ChainSettings(
      configurationInvalid: json['configurationInvalid'] == true ||
          (json['position'] != null &&
              !ChainPosition.values
                  .any((ChainPosition item) => item.name == json['position'])) ||
          (json['transport'] != null &&
              !ChainTransport.values.any(
                  (ChainTransport item) => item.name == json['transport'])) ||
          (json['endpoint'] != null &&
              !WarpEndpoint.values
                  .any((WarpEndpoint item) => item.name == json['endpoint'])),
      position: _pick(ChainPosition.values, json['position'], ChainPosition.off),
      transport: _pick(
        ChainTransport.values,
        json['transport'],
        ChainTransport.automatic,
      ),
      endpoint:
          _pick(WarpEndpoint.values, json['endpoint'], WarpEndpoint.assigned),
      address: json['address'] is String ? json['address'] as String : '',
      port: _number(json['port'], 2408),
      mtu: _number(json['mtu'], 0),
      scanCount: _number(json['scanCount'], 64),
      scanConcurrency: _number(json['scanConcurrency'], 8),
      scanTimeout: _number(json['scanTimeout'], 2000),
      scanMaxRtt: _number(json['scanMaxRtt'], 1000),
      searchNoise: json['searchNoise'] != false,
      masqueProtocol: json['masqueProtocol'] is String
          ? json['masqueProtocol'] as String
          : 'auto',
      licenseKey:
          json['licenseKey'] is String ? json['licenseKey'] as String : '',
      psiphonRegion: regions.contains(rawRegion) ? rawRegion : 'AUTO',
      noiseMode: noiseModes.containsKey(rawNoise) ? rawNoise : '',
      noiseCount:
          json['noiseCount'] is String ? json['noiseCount'] as String : '',
      noiseSize: json['noiseSize'] is String ? json['noiseSize'] as String : '',
      noiseDelay:
          json['noiseDelay'] is String ? json['noiseDelay'] as String : '',
    );
  }

  Map<String, dynamic> toCoreOptions() {
    if (!enabled) {
      return <String, dynamic>{'chain-status': 'off'};
    }
    final String? error = validationError;
    // Never silently drop a requested security hop when settings are damaged.
    if (error != null) {
      throw FormatException(error);
    }
    return <String, dynamic>{
      'chain-status': position.coreValue,
      position == ChainPosition.extraSecurity ? 'extra-security' : 'unblocker':
          <String, dynamic>{
        'mode': transport.coreValue,
        if (transport == ChainTransport.psiphon)
          'psiphon': <String, dynamic>{'region': psiphonRegion}
        else
          'warp': <String, dynamic>{
            'endpoint': endpoint.coreValue,
            if (endpoint == WarpEndpoint.custom) ...<String, dynamic>{
              'clean-ip': address.trim(),
              'clean-port': port,
            },
            if (mtu != 0) 'mtu': mtu,
            if (licenseKey.isNotEmpty) 'license-key': licenseKey,
            if (noiseMode.isNotEmpty) 'noise-mode': noiseMode,
            if (noiseCount.trim().isNotEmpty)
              'noise': Fa.toEn(noiseCount.trim()),
            if (noiseSize.trim().isNotEmpty)
              'noise-size': Fa.toEn(noiseSize.trim()),
            if (noiseDelay.trim().isNotEmpty)
              'noise-delay': Fa.toEn(noiseDelay.trim()),
            if (endpoint == WarpEndpoint.scan)
              'scanner': <String, dynamic>{
                'count': scanCount,
                'concurrency': scanConcurrency,
                'timeout': scanTimeout,
                'max-rtt': scanMaxRtt,
                'search-noise': searchNoise,
              },
            if (transport == ChainTransport.automatic ||
                transport == ChainTransport.masque)
              'masque': <String, dynamic>{
                'vhttp': masqueProtocol,
                'tls-insecure': false,
              },
          },
      },
    };
  }
}

/// تنظیمات ترفندهای TLS هسته (Fragment، Mixed SNI Case و Padding).
class TlsTricksSettings {
  const TlsTricksSettings({
    this.enableFragment = false,
    this.fragmentSize = defaultFragmentSize,
    this.fragmentSleep = defaultFragmentSleep,
    this.mixedSniCase = false,
    this.enablePadding = false,
    this.paddingSize = defaultPaddingSize,
  });

  static const String defaultFragmentSize = '10-100';
  static const String defaultFragmentSleep = '50-200';
  static const String defaultPaddingSize = '1200-1500';

  final bool enableFragment;
  final String fragmentSize;
  final String fragmentSleep;
  final bool mixedSniCase;
  final bool enablePadding;
  final String paddingSize;

  bool get anyEnabled => enableFragment || mixedSniCase || enablePadding;

  static bool isValidRange(String value, {int min = 1, int max = 65535}) {
    final String trimmed = value.trim();
    return trimmed.isNotEmpty && _validOptionalRange(trimmed, min: min, max: max);
  }

  static String _sanitizeRange(String raw, String fallback, {int min = 1}) {
    final String clean = Fa.toEn(raw.trim());
    return isValidRange(clean, min: min) ? clean : fallback;
  }

  TlsTricksSettings copyWith({
    bool? enableFragment,
    String? fragmentSize,
    String? fragmentSleep,
    bool? mixedSniCase,
    bool? enablePadding,
    String? paddingSize,
  }) {
    return TlsTricksSettings(
      enableFragment: enableFragment ?? this.enableFragment,
      fragmentSize: fragmentSize ?? this.fragmentSize,
      fragmentSleep: fragmentSleep ?? this.fragmentSleep,
      mixedSniCase: mixedSniCase ?? this.mixedSniCase,
      enablePadding: enablePadding ?? this.enablePadding,
      paddingSize: paddingSize ?? this.paddingSize,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'enableFragment': enableFragment,
        'fragmentSize': _sanitizeRange(fragmentSize, defaultFragmentSize),
        'fragmentSleep':
            _sanitizeRange(fragmentSleep, defaultFragmentSleep, min: 0),
        'mixedSniCase': mixedSniCase,
        'enablePadding': enablePadding,
        'paddingSize': _sanitizeRange(paddingSize, defaultPaddingSize),
      };

  factory TlsTricksSettings.fromJson(Map<String, dynamic> json) {
    return TlsTricksSettings(
      enableFragment: json['enableFragment'] == true,
      fragmentSize: _sanitizeRange(
        json['fragmentSize'] is String ? json['fragmentSize'] as String : '',
        defaultFragmentSize,
      ),
      fragmentSleep: _sanitizeRange(
        json['fragmentSleep'] is String ? json['fragmentSleep'] as String : '',
        defaultFragmentSleep,
        min: 0,
      ),
      mixedSniCase: json['mixedSniCase'] == true,
      enablePadding: json['enablePadding'] == true,
      paddingSize: _sanitizeRange(
        json['paddingSize'] is String ? json['paddingSize'] as String : '',
        defaultPaddingSize,
      ),
    );
  }

  Map<String, dynamic> toCoreOptions() => <String, dynamic>{
        'enable-fragment': enableFragment,
        'fragment-size': _sanitizeRange(fragmentSize, defaultFragmentSize),
        'fragment-sleep':
            _sanitizeRange(fragmentSleep, defaultFragmentSleep, min: 0),
        'mixed-sni-case': mixedSniCase,
        'enable-padding': enablePadding,
        'padding-size': _sanitizeRange(paddingSize, defaultPaddingSize),
      };

  @override
  bool operator ==(Object other) {
    return other is TlsTricksSettings &&
        other.enableFragment == enableFragment &&
        other.fragmentSize == fragmentSize &&
        other.fragmentSleep == fragmentSleep &&
        other.mixedSniCase == mixedSniCase &&
        other.enablePadding == enablePadding &&
        other.paddingSize == paddingSize;
  }

  @override
  int get hashCode => Object.hash(
        enableFragment,
        fragmentSize,
        fragmentSleep,
        mixedSniCase,
        enablePadding,
        paddingSize,
      );
}

/// ابزار اشتراک گذاری اتصال در شبکه محلی (ساخت رمز امن، لینک SOCKS5، لینک
/// تلگرام، داده QR و تشخیص نشانی IPv4 شبکه محلی).
class LanSharing {
  const LanSharing._();

  static const int defaultLanPort = 12338;
  static const int minPort = 1024;
  static const int maxPort = 65535;
  static const String lanProfileName = 'Umbrella LAN';
  static const String localProfileName = 'Umbrella Local';

  // ارقام تصادفی امن تا هم در نمایش به ارقام فارسی خوانا باشد و هم هنگام
  // وارد کردن دستی روی گوشی یا دستگاه دیگر خطای حروف کوچک و بزرگ رخ ندهد.
  static const String _secretAlphabet = '0123456789';

  // نام کاربری داخلی ثابت پورت اشتراک گذاری در موتور هسته (v2/config/inbound_ports.go).
  static final String coreAuthUser = String.fromCharCodes(
    const <int>[104, 105, 100, 100, 105, 102, 121],
  );

  static bool isValidPort(int port, {int? forbiddenPort}) {
    if (port < minPort || port > maxPort) {
      return false;
    }
    if (forbiddenPort != null && port == forbiddenPort) {
      return false;
    }
    return true;
  }

  static bool isValidPassword(String raw) {
    final String clean = raw.trim();
    return clean.isEmpty || (clean.length >= 4 && clean.length <= 64);
  }

  /// ساخت رمز تصادفی امن به فرم چهاربخشی (مانند `Kp7x-Q2mZ`).
  static String generateSecret({int length = 8}) {
    final Random random = Random.secure();
    final String chars = List<String>.generate(
      length,
      (_) => _secretAlphabet[random.nextInt(_secretAlphabet.length)],
    ).join();
    return RegExp('.{1,4}')
        .allMatches(chars)
        .map((RegExpMatch m) => m.group(0)!)
        .join('-');
  }

  static String socksLink({
    required String host,
    required int port,
    String password = '',
    String profileName = lanProfileName,
  }) {
    final String secret = password.trim();
    final String auth = secret.isEmpty
        ? ''
        : '$coreAuthUser:${Uri.encodeComponent(secret)}@';
    final String fragment = Uri.encodeComponent(profileName);
    return 'socks://$auth$host:$port#$fragment';
  }

  static String qrPayload({
    required String host,
    required int port,
    String password = '',
    String profileName = lanProfileName,
  }) {
    final String link = socksLink(
      host: host,
      port: port,
      password: password,
      profileName: profileName,
    );
    return '#profile-title: $profileName\n$link';
  }

  static String telegramLink({
    required String host,
    required int port,
    String password = '',
  }) {
    final String secret = password.trim();
    return Uri(
      scheme: 'tg',
      host: 'socks',
      queryParameters: <String, String>{
        'server': host,
        'port': '$port',
        if (secret.isNotEmpty) ...<String, String>{
          'user': coreAuthUser,
          'pass': secret,
        },
      },
    ).toString();
  }

  /// تشخیص نشانی های IPv4 واقعی شبکه محلی دستگاه (با حذف کارت های مجازی تونل).
  static Future<List<String>> detectLanIps({String fallbackIp = ''}) async {
    final List<({String ip, int score})> candidates =
        <({String ip, int score})>[];
    try {
      final List<NetworkInterface> interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final NetworkInterface iface in interfaces) {
        final String name = iface.name.toLowerCase();
        if (_isTunnelInterface(name)) {
          continue;
        }
        for (final InternetAddress addr in iface.addresses) {
          final String ip = addr.address;
          if (addr.isLoopback ||
              addr.isLinkLocal ||
              addr.isMulticast ||
              ip.startsWith('127.') ||
              ip.startsWith('169.254.') ||
              ip.startsWith('172.19.') ||
              ip == '0.0.0.0') {
            continue;
          }
          candidates.add((ip: ip, score: _scoreInterface(name, ip)));
        }
      }
    } catch (_) {
      // در محیط آزمایشی یا خطای سیستم عامل به نشانی پشتیبان برمی گردیم.
    }
    candidates.sort(
      (({String ip, int score}) a, ({String ip, int score}) b) =>
          b.score.compareTo(a.score),
    );
    final List<String> unique = <String>[];
    for (final ({String ip, int score}) item in candidates) {
      if (!unique.contains(item.ip)) {
        unique.add(item.ip);
      }
    }
    final String cleanFallback = fallbackIp.trim();
    if (unique.isEmpty &&
        cleanFallback.isNotEmpty &&
        !cleanFallback.startsWith('127.') &&
        !cleanFallback.startsWith('169.254.')) {
      unique.add(cleanFallback);
    }
    return unique;
  }

  static bool _isTunnelInterface(String lowerName) {
    for (final String token in const <String>[
      'wintun',
      'tun',
      'tap',
      'umbrella',
      'sing',
      'wireguard',
      'loopback',
    ]) {
      if (lowerName.contains(token)) {
        return true;
      }
    }
    return false;
  }

  static int _scoreInterface(String lowerName, String ip) {
    int score = 0;
    if (lowerName.contains('wi-fi') ||
        lowerName.contains('wifi') ||
        lowerName.contains('wlan')) {
      score += 40;
    } else if (lowerName.contains('ethernet') || lowerName.contains('eth')) {
      score += 35;
    }
    if (lowerName.contains('vethernet') ||
        lowerName.contains('wsl') ||
        lowerName.contains('vmware') ||
        lowerName.contains('virtualbox') ||
        lowerName.contains('hyper-v') ||
        lowerName.contains('docker')) {
      score -= 25;
    }
    if (ip.startsWith('192.168.')) {
      score += 30;
    } else if (ip.startsWith('10.')) {
      score += 20;
    } else if (_isPrivate172(ip)) {
      score += 15;
    }
    return score;
  }

  static bool _isPrivate172(String ip) {
    final List<String> parts = ip.split('.');
    if (parts.length != 4 || parts[0] != '172') {
      return false;
    }
    final int? second = int.tryParse(parts[1]);
    return second != null && second >= 16 && second <= 31;
  }
}

enum AppRouteAction { proxy, direct, block }

extension AppRouteActionX on AppRouteAction {
  String get label => switch (this) {
        AppRouteAction.proxy => 'از تونل',
        AppRouteAction.direct => 'مستقیم (خارج از تونل)',
        AppRouteAction.block => 'مسدود',
      };

  IconData get icon => switch (this) {
        AppRouteAction.proxy => Icons.shield_rounded,
        AppRouteAction.direct => Icons.call_made_rounded,
        AppRouteAction.block => Icons.block_rounded,
      };
}

class AppRouteRule {
  const AppRouteRule({
    required this.process,
    this.action = AppRouteAction.proxy,
    this.enabled = true,
  });

  final String process;
  final AppRouteAction action;
  final bool enabled;

  bool get isPath => process.contains('\\') || process.contains('/');

  String? get validationError {
    if (process.contains(RegExp(r'[\r\n\x00]'))) {
      return 'نام برنامه نباید نویسه کنترلی داشته باشد';
    }
    final String value = process.trim();
    if (value.isEmpty ||
        value.length > 260 ||
        !value.toLowerCase().endsWith('.exe') ||
        value.contains(RegExp(r'[\r\n\x00*?"<>|]'))) {
      return 'نام فایل اجرایی برنامه یا مسیر کامل ویندوز را وارد کنید';
    }
    if (isPath && !RegExp(r'^[a-zA-Z]:\\').hasMatch(value)) {
      return 'مسیر فایل برنامه در ویندوز باید از ریشه درایو و کامل باشد';
    }
    if (!isPath && value.contains(':')) {
      return 'نام برنامه نامعتبر است';
    }
    final String name = value.replaceAll('/', '\\').split('\\').last.toLowerCase();
    final List<String> corePrefixes = <String>[
      'umbrella',
      LanSharing.coreAuthUser,
    ];
    if (corePrefixes.any(name.startsWith)) {
      return 'برای پردازش خود آمبرلا و هسته قانون جدا نسازید';
    }
    return null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'process': process.trim(),
        'action': action.name,
        'enabled': enabled,
      };

  factory AppRouteRule.fromJson(Map<String, dynamic> json) => AppRouteRule(
        process: json['process'] is String ? json['process'] as String : '',
        action:
            _pick(AppRouteAction.values, json['action'], AppRouteAction.proxy),
        enabled: json['enabled'] != false,
      );

  Map<String, dynamic> toCoreRule(int order) {
    if (validationError != null) {
      throw FormatException(validationError!);
    }
    return <String, dynamic>{
      'list_order': order,
      'enabled': enabled,
      'name': process.trim(),
      'outbound': action.name,
      isPath ? 'process_path' : 'process_name': <String>[process.trim()],
    };
  }
}
