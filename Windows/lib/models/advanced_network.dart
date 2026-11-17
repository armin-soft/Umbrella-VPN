import 'dart:io';

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
    ChainPosition.extraSecurity => 'آمبرلا سپس WARP / Psiphon',
    ChainPosition.unblocker => 'WARP / Psiphon سپس آمبرلا',
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
    ChainTransport.automatic => 'WARP خودکار (WG / AWG / MASQUE)',
    ChainTransport.wireguard => 'WARP — WireGuard',
    ChainTransport.awg => 'WARP — AmneziaWG',
    ChainTransport.masque => 'WARP — MASQUE',
    ChainTransport.psiphon => 'Psiphon',
  };
}

T _pick<T extends Enum>(List<T> values, dynamic value, T fallback) =>
    values.where((T item) => item.name == value).firstOrNull ?? fallback;
int _number(dynamic value, int fallback) => value is int ? value : fallback;

class ChainSettings {
  const ChainSettings({
    this.position = ChainPosition.off,
    this.transport = ChainTransport.automatic,
    this.endpoint = WarpEndpoint.assigned,
    this.address = '', this.port = 2408, this.mtu = 0,
    this.scanCount = 64, this.scanConcurrency = 8,
    this.scanTimeout = 2000, this.scanMaxRtt = 1000,
    this.searchNoise = true, this.masqueProtocol = 'auto',
    this.licenseKey = '', this.psiphonRegion = 'AUTO', this.configurationInvalid = false,
  });
  final ChainPosition position;
  final ChainTransport transport;
  final WarpEndpoint endpoint;
  final String address;
  final int port, mtu, scanCount, scanConcurrency, scanTimeout, scanMaxRtt;
  final bool searchNoise, configurationInvalid;
  final String masqueProtocol, licenseKey, psiphonRegion;
  bool get enabled => position != ChainPosition.off || configurationInvalid;
  static const List<String> regions = <String>['AUTO', 'US', 'GB', 'DE', 'NL', 'FR', 'CA', 'JP', 'SG'];

  String? get validationError {
    if (configurationInvalid) return 'تنظیمات زنجیره ذخیره‌شده نامعتبر است؛ دوباره ذخیره کنید';
    if (port < 1 || port > 65535) return 'پورت باید بین ۱ و ۶۵۵۳۵ باشد';
    if (mtu != 0 && (mtu < 1280 || mtu > 1500)) return 'MTU زنجیره: صفر (خودکار) یا ۱۲۸۰ تا ۱۵۰۰';
    if (scanCount < 1 || scanCount > 256 || scanConcurrency < 1 || scanConcurrency > 32 || scanConcurrency > scanCount) return 'تعداد اسکن ۱..۲۵۶ و همزمانی ۱..۳۲ و حداکثر برابر تعداد';
    if (scanTimeout < 250 || scanTimeout > 10000 || scanMaxRtt < 100 || scanMaxRtt > scanTimeout) return 'مهلت اسکن ۲۵۰..۱۰۰۰۰ و RTT بین ۱۰۰ و مهلت';
    if (!<String>['auto', 'h2', 'h3'].contains(masqueProtocol)) return 'نسخه MASQUE نامعتبر است';
    if (!regions.contains(psiphonRegion)) return 'منطقه Psiphon نامعتبر است';
    if (licenseKey.length > 128 || licenseKey.contains(RegExp(r'\s'))) return 'کلید WARP نامعتبر است';
    if (transport != ChainTransport.psiphon && endpoint == WarpEndpoint.custom) {
      final InternetAddress? ip = InternetAddress.tryParse(address.trim());
      if (ip == null || ip.isLoopback || ip.isLinkLocal || ip.isMulticast || ip.address == '0.0.0.0' || ip.address == '::') return 'آدرس IP معتبر endpoint را وارد کنید';
      if (transport == ChainTransport.masque) return 'هسته برای MASQUE از endpoint اختصاص‌یافته استفاده می‌کند';
    }
    if (enabled && endpoint == WarpEndpoint.scan && position == ChainPosition.extraSecurity && transport != ChainTransport.psiphon) return 'اسکن فقط قبل از سرور آمبرلا ممکن است؛ پس از آن endpoint اختصاص‌یافته را انتخاب کنید';
    return null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'configurationInvalid': configurationInvalid,
    'position': position.name, 'transport': transport.name, 'endpoint': endpoint.name,
    'address': address.trim(), 'port': port, 'mtu': mtu,
    'scanCount': scanCount, 'scanConcurrency': scanConcurrency,
    'scanTimeout': scanTimeout, 'scanMaxRtt': scanMaxRtt, 'searchNoise': searchNoise,
    'masqueProtocol': masqueProtocol, 'licenseKey': licenseKey, 'psiphonRegion': psiphonRegion,
  };
  factory ChainSettings.fromJson(Map<String, dynamic> json) => ChainSettings(
    configurationInvalid: json['configurationInvalid'] == true ||
      (json['position'] != null && !ChainPosition.values.any((ChainPosition item) => item.name == json['position'])) ||
      (json['transport'] != null && !ChainTransport.values.any((ChainTransport item) => item.name == json['transport'])) ||
      (json['endpoint'] != null && !WarpEndpoint.values.any((WarpEndpoint item) => item.name == json['endpoint'])),
    position: _pick(ChainPosition.values, json['position'], ChainPosition.off),
    transport: _pick(ChainTransport.values, json['transport'], ChainTransport.automatic),
    endpoint: _pick(WarpEndpoint.values, json['endpoint'], WarpEndpoint.assigned),
    address: json['address'] is String ? json['address'] as String : '',
    port: _number(json['port'], 2408), mtu: _number(json['mtu'], 0),
    scanCount: _number(json['scanCount'], 64), scanConcurrency: _number(json['scanConcurrency'], 8),
    scanTimeout: _number(json['scanTimeout'], 2000), scanMaxRtt: _number(json['scanMaxRtt'], 1000),
    searchNoise: json['searchNoise'] != false,
    masqueProtocol: json['masqueProtocol'] is String ? json['masqueProtocol'] as String : 'auto',
    licenseKey: json['licenseKey'] is String ? json['licenseKey'] as String : '',
    psiphonRegion: json['psiphonRegion'] is String ? json['psiphonRegion'] as String : 'AUTO',
  );

  Map<String, dynamic> toCoreOptions() {
    if (!enabled) return <String, dynamic>{'chain-status': 'off'};
    final String? error = validationError;
    // Never silently drop a requested security hop when settings are damaged.
    if (error != null) throw FormatException(error);
    return <String, dynamic>{
      'chain-status': position.coreValue,
      position == ChainPosition.extraSecurity ? 'extra-security' : 'unblocker': <String, dynamic>{
        'mode': transport.coreValue,
        if (transport == ChainTransport.psiphon)
          'psiphon': <String, dynamic>{'region': psiphonRegion}
        else 'warp': <String, dynamic>{
          'endpoint': switch (endpoint) { WarpEndpoint.assigned => 'profile', WarpEndpoint.scan => 'scan', WarpEndpoint.custom => 'custom' },
          if (endpoint == WarpEndpoint.custom) ...<String, dynamic>{'clean-ip': address.trim(), 'clean-port': port},
          if (mtu != 0) 'mtu': mtu,
          if (licenseKey.isNotEmpty) 'license-key': licenseKey,
          if (endpoint == WarpEndpoint.scan) 'scanner': <String, dynamic>{
            'count': scanCount, 'concurrency': scanConcurrency, 'timeout': scanTimeout,
            'max-rtt': scanMaxRtt, 'search-noise': searchNoise,
          },
          if (transport == ChainTransport.automatic || transport == ChainTransport.masque)
            'masque': <String, dynamic>{'vhttp': masqueProtocol, 'tls-insecure': false},
        },
      },
    };
  }
}

enum AppRouteAction { proxy, direct, block }
extension AppRouteActionX on AppRouteAction {
  String get label => switch (this) {
    AppRouteAction.proxy => 'از تونل', AppRouteAction.direct => 'مستقیم (خارج از تونل)', AppRouteAction.block => 'مسدود',
  };
}

class AppRouteRule {
  const AppRouteRule({required this.process, this.action = AppRouteAction.proxy, this.enabled = true});
  final String process;
  final AppRouteAction action;
  final bool enabled;
  bool get isPath => process.contains('\\') || process.contains('/');
  String? get validationError {
    if (process.contains(RegExp(r'[\r\n\x00]'))) return 'نام برنامه نباید نویسه کنترلی داشته باشد';
    final String value = process.trim();
    if (value.isEmpty || value.length > 260 || !value.toLowerCase().endsWith('.exe') || value.contains(RegExp(r'[\r\n\x00*?"<>|]'))) return 'نام فایل exe یا مسیر کامل ویندوز را وارد کنید';
    if (isPath && !RegExp(r'^[a-zA-Z]:\\').hasMatch(value)) return 'مسیر باید کامل باشد، مانند C:\\Apps\\app.exe';
    if (!isPath && value.contains(':')) return 'نام برنامه نامعتبر است';
    final String name = value.replaceAll('/', '\\').split('\\').last.toLowerCase();
    const List<String> corePrefixes = <String>[
      'umbrella',
      'hiddify',
    ];
    if (corePrefixes.any(name.startsWith)) return 'برای پردازش خود آمبرلا و هسته قانون جدا نسازید';
    return null;
  }
  Map<String, dynamic> toJson() => <String, dynamic>{'process': process.trim(), 'action': action.name, 'enabled': enabled};
  factory AppRouteRule.fromJson(Map<String, dynamic> json) => AppRouteRule(
    process: json['process'] is String ? json['process'] as String : '',
    action: _pick(AppRouteAction.values, json['action'], AppRouteAction.proxy), enabled: json['enabled'] != false,
  );
  Map<String, dynamic> toCoreRule(int order) {
    if (validationError != null) throw FormatException(validationError!);
    return <String, dynamic>{
      'list_order': order, 'enabled': enabled, 'name': process.trim(), 'outbound': action.name,
      isPath ? 'process_path' : 'process_name': <String>[process.trim()],
    };
  }
}
