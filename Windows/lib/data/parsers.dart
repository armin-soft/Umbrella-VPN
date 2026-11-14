import 'dart:convert';

import 'package:yaml/yaml.dart';

import '../core/utils.dart';
import '../models/models.dart';

/// نتیجه خواندن یک اشتراک.
class ParseReport {
  ParseReport({
    List<VpnNode>? nodes,
    List<String>? problems,
    this.sourceId = '',
  })  : nodes = nodes ?? <VpnNode>[],
        problems = problems ?? <String>[];

  final String sourceId;
  final List<VpnNode> nodes;
  final List<String> problems;

  int get count => nodes.length;

  void merge(ParseReport other) {
    nodes.addAll(other.nodes);
    problems.addAll(other.problems);
  }
}

/// خواندن همه قالب های اشتراک: ایکس ری (لینک های استاندارد)، کلش متا (YAML)،
/// وایرگارد (INI)، آمنزیا و میرو (JSON).
class SubscriptionParser {
  const SubscriptionParser._();

  static ParseReport parse(String body, SubscriptionSource source) {
    final String trimmed = body.trim();
    if (trimmed.isEmpty) {
      return ParseReport(
        sourceId: source.id,
        problems: <String>['پاسخ خالی بود.'],
      );
    }
    switch (source.format) {
      case SubscriptionFormat.xray:
        return _parseXray(trimmed, source.id);
      case SubscriptionFormat.clash:
        // فایل کلش YAML است و full-singbox.json / mihomo هم JSON؛ هر سه با
        // یک تشخیص خوانده می شوند.
        if (trimmed.startsWith('{')) {
          final ParseReport singbox = parseSingBox(trimmed, source.id);
          if (singbox.nodes.isNotEmpty) {
            return singbox;
          }
        }
        return _parseClash(trimmed, source.id);
      case SubscriptionFormat.wireguard:
        return _parseWireguard(trimmed, source.id);
      case SubscriptionFormat.amnezia:
        return _parseAmnezia(trimmed, source.id);
      case SubscriptionFormat.mieru:
        return _parseMieru(trimmed, source.id);
    }
  }

  /// خواندن اشتراکی که سرور می دهد. قالب از روی خود پاسخ تشخیص داده می شود
  /// (لینک های استاندارد، کلش متا، وایرگارد، آمنزیا یا میرو) تا کاربر هیچ
  /// انتخابی نکند و هیچ نشانی دستی وارد نشود.
  static ParseReport parseAuto(String body, String sourceId) {
    final String trimmed = body.trim();
    if (trimmed.isEmpty) {
      return ParseReport(
        sourceId: sourceId,
        problems: <String>['پاسخ سرور خالی بود.'],
      );
    }
    final List<ParseReport> attempts = <ParseReport>[
      _parseXray(trimmed, sourceId),
      parseSingBox(trimmed, sourceId),
      _parseClash(trimmed, sourceId),
      _parseWireguard(trimmed, sourceId),
      _parseMieru(trimmed, sourceId),
      _parseAmnezia(trimmed, sourceId),
    ];
    final ParseReport merged = ParseReport(sourceId: sourceId);
    for (final ParseReport attempt in attempts) {
      for (final VpnNode node in attempt.nodes) {
        if (merged.nodes.any((VpnNode item) => item.id == node.id)) {
          continue;
        }
        merged.nodes.add(node);
      }
    }
    if (merged.nodes.isEmpty) {
      for (final ParseReport attempt in attempts) {
        for (final String problem in attempt.problems) {
          if (!merged.problems.contains(problem)) {
            merged.problems.add(problem);
          }
        }
        if (merged.problems.length >= 3) {
          break;
        }
      }
      if (merged.problems.isEmpty) {
        merged.problems.add('هیچ سروری در اشتراک پیدا نشد.');
      }
    }
    return merged;
  }

  // ── ایکس ری / وی۲ری ─────────────────────────────────────────────────

  static ParseReport _parseXray(String body, String sourceId) {
    final ParseReport report = ParseReport(sourceId: sourceId);
    String text = body;
    if (!text.contains('://')) {
      final String? decoded = B64.tryDecode(text);
      if (decoded != null && decoded.contains('://')) {
        text = decoded;
      }
    }

    // بعضی سرورها JSON هم برمی گردانند.
    if (text.trimLeft().startsWith('{') || text.trimLeft().startsWith('[')) {
      final Object? json = _tryJson(text);
      final List<String> uris = <String>[];
      _collectUris(json, uris);
      if (uris.isNotEmpty) {
        text = uris.join('\n');
      }
    }

    int index = 0;
    for (final String line in const LineSplitter().convert(text)) {
      final String uri = line.trim();
      if (uri.isEmpty || !uri.contains('://')) {
        continue;
      }
      index++;
      final VpnNode? node = parseUri(uri, sourceId, index);
      if (node == null) {
        report.problems.add('لینک شماره ${Fa.num(index)} خوانده نشد.');
        continue;
      }
      report.nodes.add(node);
    }
    if (report.nodes.isEmpty && report.problems.isEmpty) {
      report.problems.add('هیچ سروری در این اشتراک پیدا نشد.');
    }
    return report;
  }

  static void _collectUris(Object? value, List<String> out) {
    if (value is String) {
      if (value.contains('://')) {
        out.add(value);
      }
      return;
    }
    if (value is Map) {
      for (final Object? item in value.values) {
        _collectUris(item, out);
      }
      return;
    }
    if (value is List) {
      for (final Object? item in value) {
        _collectUris(item, out);
      }
    }
  }

  static VpnNode? parseUri(String uri, String sourceId, [int index = 0]) {
    try {
      final String scheme = uri.split('://').first.toLowerCase();
      final String payload = uri.substring(scheme.length + 3);
      final String fragment = _fragment(payload);
      final String withoutFragment =
          fragment.isEmpty ? payload : payload.substring(0, payload.lastIndexOf('#'));
      final String name = fragment.isEmpty ? '' : _decode(fragment).trim();

      switch (scheme) {
        case 'vless':
        case 'trojan':
        case 'hysteria2':
        case 'hy2':
        case 'tuic':
        case 'socks':
        case 'ss':
          return _parseStandard(scheme, withoutFragment, name, sourceId, index);
        case 'vmess':
          return _parseVmess(withoutFragment, name, sourceId, index);
        default:
          return null;
      }
    } on Object {
      return null;
    }
  }

  static String _decode(String value) {
    try {
      return Uri.decodeComponent(value);
    } on ArgumentError {
      return value;
    } on FormatException {
      return value;
    }
  }

  static String _fragment(String payload) {
    final int hash = payload.indexOf('#');
    return hash < 0 ? '' : payload.substring(hash + 1);
  }

  static VpnNode? _parseStandard(
    String scheme,
    String payload,
    String name,
    String sourceId,
    int index,
  ) {
    final String? decoded = scheme == 'ss' ? _decodeSs(payload) ?? payload : payload;
    final Uri? parsed = Uri.tryParse('$scheme://$decoded');
    if (parsed == null) {
      return null;
    }
    final String host = parsed.host;
    final int port = parsed.hasPort ? parsed.port : _defaultPort(scheme);
    if (host.isEmpty || port <= 0) {
      return null;
    }
    final Map<String, String> query = parsed.queryParameters;
    final String user = parsed.userInfo;
    final Map<String, dynamic> params = <String, dynamic>{...query};

    NodeProtocol protocol;
    String titlePrefix;
    switch (scheme) {
      case 'vless':
        protocol = NodeProtocol.vless;
        titlePrefix = 'وی لس';
        params['id'] = _decode(user);
        break;
      case 'trojan':
        protocol = NodeProtocol.trojan;
        titlePrefix = 'تروجان';
        params['password'] = _decode(user);
        break;
      case 'hysteria2':
      case 'hy2':
        protocol = NodeProtocol.hysteria2;
        titlePrefix = 'هیستریا';
        params['password'] = _decode(user);
        break;
      case 'tuic':
        protocol = NodeProtocol.tuic;
        titlePrefix = 'توئیک';
        final List<String> parts = user.split(':');
        params['uuid'] = parts.isNotEmpty ? parts.first : '';
        params['password'] = parts.length > 1 ? parts.sublist(1).join(':') : '';
        break;
      case 'socks':
        protocol = NodeProtocol.socks;
        titlePrefix = 'سوکس';
        final List<String> parts = user.split(':');
        params['username'] = parts.isNotEmpty ? parts.first : '';
        params['password'] = parts.length > 1 ? parts.sublist(1).join(':') : '';
        break;
      case 'ss':
      default:
        protocol = NodeProtocol.shadowsocks;
        titlePrefix = 'شادوساکس';
        if (user.contains(':')) {
          final int split = user.indexOf(':');
          params['method'] = user.substring(0, split);
          params['password'] = user.substring(split + 1);
        } else if (user.isNotEmpty) {
          final String? basic = B64.tryDecode(user);
          if (basic != null && basic.contains(':')) {
            final int split = basic.indexOf(':');
            params['method'] = basic.substring(0, split);
            params['password'] = basic.substring(split + 1);
          }
        }
        break;
    }

    if (params['sni'] == null && query['serverName'] != null) {
      params['sni'] = query['serverName'];
    }
    if (params['sni'] == null && query['peer'] != null) {
      params['sni'] = query['peer'];
    }
    _normalizeSecurity(params);

    final String label = name.isNotEmpty
        ? name
        : '$titlePrefix ${Fa.num(host)}';
    return VpnNode(
      id: stableId('$sourceId|$scheme|$payload'),
      name: label,
      protocol: protocol,
      host: host,
      port: port,
      sourceId: sourceId,
      params: params,
      raw: '$scheme://$payload',
    );
  }

  static String? _decodeSs(String payload) {
    final int at = payload.indexOf('@');
    if (at > 0) {
      final String head = payload.substring(0, at);
      if (head.contains(':')) {
        return payload;
      }
      final String? decoded = B64.tryDecode(head);
      if (decoded != null && decoded.contains(':')) {
        return '$decoded${payload.substring(at)}';
      }
      return payload;
    }
    // ss://base64(method:password@host:port)
    final int queryStart = payload.indexOf('?');
    final String body = queryStart >= 0 ? payload.substring(0, queryStart) : payload;
    final String query = queryStart >= 0 ? payload.substring(queryStart) : '';
    final String? decoded = B64.tryDecode(body);
    if (decoded == null || !decoded.contains('@')) {
      return null;
    }
    return '$decoded$query';
  }

  static VpnNode? _parseVmess(
    String payload,
    String name,
    String sourceId,
    int index,
  ) {
    final String? decoded = B64.tryDecode(payload);
    if (decoded == null) {
      return null;
    }
    final Object? json = _tryJson(decoded);
    if (json is! Map) {
      return null;
    }
    final Map<String, dynamic> data = JsonX.asMap(json);
    final String host = JsonX.text(data['add'] ?? data['address']);
    final int port = JsonX.integer(data['port']);
    if (host.isEmpty || port <= 0) {
      return null;
    }
    final Map<String, dynamic> params = <String, dynamic>{
      'id': JsonX.text(data['id']),
      'alterId': JsonX.integer(data['aid'] ?? data['alterId']),
      'security': JsonX.text(data['scy'] ?? data['security'], 'auto'),
      'network': JsonX.text(data['net'] ?? data['network'], 'tcp'),
      'tls': JsonX.text(data['tls']),
      'sni': JsonX.text(data['sni'] ?? data['host']),
      'host': JsonX.text(data['host']),
      'path': JsonX.text(data['path']),
      'serviceName': JsonX.text(data['path']),
      'allowInsecure': JsonX.boolean(data['allowInsecure'] ?? data['verify_cert']),
    };
    final String label = name.isNotEmpty
        ? name
        : JsonX.text(data['ps'], 'وی مس ${Fa.num(host)}');
    return VpnNode(
      id: stableId('$sourceId|vmess|$payload'),
      name: label,
      protocol: NodeProtocol.vmess,
      host: host,
      port: port,
      sourceId: sourceId,
      params: params,
      raw: 'vmess://$payload',
    );
  }

  static int _defaultPort(String scheme) {
    switch (scheme) {
      case 'trojan':
      case 'hysteria2':
      case 'hy2':
        return 443;
      case 'tuic':
        return 443;
      case 'socks':
        return 1080;
      default:
        return 443;
    }
  }

  static void _normalizeSecurity(Map<String, dynamic> params) {
    final String security = JsonX.text(params['security'] ?? params['tls']).toLowerCase();
    if (security.isNotEmpty) {
      params['security'] = security;
    }
    if (params['allowInsecure'] == null) {
      final String insecure = JsonX.text(params['insecure'] ?? params['allow_insecure']);
      params['allowInsecure'] = insecure == '1' || insecure.toLowerCase() == 'true';
    }
  }

  // ── کلش متا ────────────────────────────────────────────────────────

  /// خواندن فایل سینگ باکس (`full-singbox.json`).
  ///
  /// این فایل همان کلیدهای `outbounds` (و گاهی `endpoints`) را دارد؛ هر خروجی
  /// با `server` معتبر به یک سرور تبدیل می شود و بقیه (direct/block/dns)
  /// کنار گذاشته می شوند.
  static ParseReport parseSingBox(String body, String sourceId) {
    final ParseReport report = ParseReport(sourceId: sourceId);
    final Object? root = _tryJson(body.trim());
    if (root is! Map) {
      report.problems.add('فایل سینگ باکس خوانا نبود.');
      return report;
    }
    final List<Object?> entries = <Object?>[
      ...JsonX.asList(root['outbounds']),
      ...JsonX.asList(root['endpoints']),
      ...JsonX.asList(root['proxies']),
    ];
    int index = 0;
    for (final Object? item in entries) {
      if (item is! Map) {
        continue;
      }
      final Map<String, dynamic> raw = JsonX.asMap(item);
      final String type = JsonX.text(raw['type']).toLowerCase();
      final String server = JsonX.text(raw['server'] ?? raw['address']);
      if (server.isEmpty) {
        continue;
      }
      if (type == 'direct' ||
          type == 'block' ||
          type == 'dns' ||
          type == 'selector' ||
          type == 'urltest') {
        continue;
      }
      index++;
      // همان خواننده کلش، چون نام کلیدها یکی است.
      final Map<String, dynamic> proxy = <String, dynamic>{
        ...raw,
        'name': JsonX.text(raw['tag'], 'سینگ باکس ${Fa.num(index)}'),
        'server': server,
        'port': JsonX.integer(raw['server_port'] ?? raw['port']),
        'uuid': JsonX.text(raw['uuid']),
        'password': JsonX.text(raw['password']),
      };
      final ParseReport one =
          _parseProxyMap(proxy, sourceId, index);
      report.merge(one);
    }
    if (report.nodes.isEmpty && report.problems.isEmpty) {
      report.problems.add('هیچ سروری در فایل سینگ باکس نبود.');
    }
    return report;
  }

  /// یک خروجی سینگ باکس را به سرور تبدیل می کند (همان قواعد کلش).
  static ParseReport _parseProxyMap(
    Map<String, dynamic> proxy,
    String sourceId,
    int index,
  ) {
    final ParseReport report = ParseReport(sourceId: sourceId);
    final String type = JsonX.text(proxy['type']).toLowerCase();
    final NodeProtocol? protocol = _protocolFromClash(type);
    if (protocol == null) {
      report.problems.add('نوع ${Fa.num(type)} پشتیبانی نمی شود.');
      return report;
    }
    final String host = JsonX.text(proxy['server']);
    final int port = JsonX.integer(proxy['port']);
    if (host.isEmpty || port <= 0) {
      return report;
    }
    final Map<String, dynamic> params = <String, dynamic>{
      for (final MapEntry<String, dynamic> entry in proxy.entries)
        entry.key: entry.value is Map || entry.value is List
            ? jsonEncode(entry.value)
            : entry.value,
    };
    final String id = JsonX.text(proxy['uuid'] ?? proxy['id']);
    if (id.isNotEmpty) {
      params['id'] = id;
    }
    final String cipher = JsonX.text(proxy['cipher'] ?? proxy['method']);
    if (cipher.isNotEmpty) {
      params['method'] = cipher;
    }
    final String sni =
        JsonX.text(proxy['servername'] ?? proxy['sni'] ?? proxy['server_name']);
    if (sni.isNotEmpty) {
      params['sni'] = sni;
    }
    final String password = JsonX.text(proxy['password']);
    if (password.isNotEmpty) {
      params['password'] = password;
    }
    final String security = JsonX.text(proxy['security']);
    if (security.isNotEmpty) {
      params['security'] = security;
    }
    if (proxy['tls'] is Map) {
      final Map<String, dynamic> tls = JsonX.asMap(proxy['tls']);
      if (JsonX.boolean(tls['enabled'])) {
        params['security'] = params['security'] ?? 'tls';
        final String name = JsonX.text(tls['server_name']);
        if (name.isNotEmpty) {
          params['sni'] = name;
        }
        if (JsonX.boolean(tls['insecure'])) {
          params['allowInsecure'] = true;
        }
      }
    }
    if (proxy['transport'] is Map) {
      final Map<String, dynamic> transport = JsonX.asMap(proxy['transport']);
      params['network'] = JsonX.text(transport['type']);
      final String path = JsonX.text(transport['path']);
      if (path.isNotEmpty) {
        params['path'] = path;
      }
      final String service = JsonX.text(transport['service_name']);
      if (service.isNotEmpty) {
        params['serviceName'] = service;
      }
      if (transport['headers'] is Map) {
        params['host'] =
            JsonX.text(JsonX.asMap(transport['headers'])['Host']);
      }
    }
    report.nodes.add(
      VpnNode(
        id: stableId('$sourceId|singbox|${JsonX.text(proxy['tag'])}|$host|$port'),
        name: JsonX.text(
          proxy['tag'] ?? proxy['name'],
          '${protocol.label} ${Fa.num(index)}',
        ),
        protocol: protocol,
        host: host,
        port: port,
        sourceId: sourceId,
        params: params,
        raw: jsonEncode(proxy),
      ),
    );
    return report;
  }

  static ParseReport _parseClash(String body, String sourceId) {
    final ParseReport report = ParseReport(sourceId: sourceId);
    Object? document;
    try {
      document = loadYaml(body);
    } on YamlException catch (error) {
      report.problems.add('فایل کلش خوانده نشد: ${error.message}');
      return report;
    }
    if (document is! Map) {
      report.problems.add('ساختار فایل کلش نامعتبر است.');
      return report;
    }
    final Object? proxies = document['proxies'];
    if (proxies is! List) {
      report.problems.add('فهرست سرورها در فایل کلش نبود.');
      return report;
    }
    for (final Object? raw in proxies) {
      if (raw is! Map) {
        continue;
      }
      final Map<String, dynamic> proxy = JsonX.asMap(raw);
      final String type = JsonX.text(proxy['type']).toLowerCase();
      final NodeProtocol? protocol = _protocolFromClash(type);
      if (protocol == null) {
        report.problems.add('نوع ${Fa.num(type)} پشتیبانی نمی شود.');
        continue;
      }
      final String host = JsonX.text(proxy['server']);
      final int port = JsonX.integer(proxy['port']);
      if (host.isEmpty || port <= 0) {
        continue;
      }
      final Map<String, dynamic> params = <String, dynamic>{
        for (final MapEntry<String, dynamic> entry in proxy.entries)
          entry.key: entry.value is Map || entry.value is List
              ? jsonEncode(entry.value)
              : entry.value,
      };
      // نام فیلدهای کلش با نام فیلدهای لینک استاندارد یکی نیست؛ اینجا یکسان
      // می شوند تا سازنده پیکربندی هسته برای همه منابع یکسان کار کند.
      final String clashUuid = JsonX.text(proxy['uuid'] ?? proxy['id']);
      if (clashUuid.isNotEmpty) {
        params['id'] = clashUuid;
      }
      final String cipher = JsonX.text(proxy['cipher'] ?? proxy['method']);
      if (cipher.isNotEmpty) {
        params['method'] = cipher;
      }
      final String servername =
          JsonX.text(proxy['servername'] ?? proxy['sni'] ?? proxy['server-name']);
      if (servername.isNotEmpty) {
        params['sni'] = servername;
      }
      if (proxy['alterId'] != null || proxy['alter-id'] != null) {
        params['alterId'] =
            JsonX.integer(proxy['alterId'] ?? proxy['alter-id']);
      }
      if (proxy['ws-opts'] is Map) {
        final Map<String, dynamic> ws = JsonX.asMap(proxy['ws-opts']);
        params['path'] = JsonX.text(ws['path'], '/');
        params['host'] = JsonX.text(JsonX.asMap(ws['headers'])['Host']);
        params['network'] = 'ws';
      }
      if (proxy['reality-opts'] is Map) {
        final Map<String, dynamic> reality = JsonX.asMap(proxy['reality-opts']);
        params['pbk'] = JsonX.text(reality['public-key']);
        params['sid'] = JsonX.text(reality['short-id']);
        params['security'] = 'reality';
      }
      if (JsonX.boolean(proxy['tls'])) {
        params['security'] = params['security'] ?? 'tls';
      }
      if (JsonX.boolean(proxy['skip-cert-verify'])) {
        params['allowInsecure'] = true;
      }
      final String name = JsonX.text(proxy['name'], '${protocol.label} ${Fa.num(host)}');
      report.nodes.add(
        VpnNode(
          id: stableId('$sourceId|clash|${JsonX.text(proxy['name'])}|$host|$port'),
          name: name,
          protocol: protocol,
          host: host,
          port: port,
          sourceId: sourceId,
          params: params,
          raw: jsonEncode(proxy),
        ),
      );
    }
    if (report.nodes.isEmpty && report.problems.isEmpty) {
      report.problems.add('هیچ سرور پشتیبانی شده ای در فایل کلش نبود.');
    }
    return report;
  }

  static NodeProtocol? _protocolFromClash(String type) {
    switch (type) {
      case 'vless':
        return NodeProtocol.vless;
      case 'vmess':
        return NodeProtocol.vmess;
      case 'trojan':
        return NodeProtocol.trojan;
      case 'ss':
      case 'shadowsocks':
        return NodeProtocol.shadowsocks;
      case 'wireguard':
        return NodeProtocol.wireguard;
      case 'hysteria2':
      case 'hy2':
        return NodeProtocol.hysteria2;
      case 'tuic':
        return NodeProtocol.tuic;
      case 'socks5':
      case 'socks':
        return NodeProtocol.socks;
      default:
        return null;
    }
  }

  // ── وایرگارد ───────────────────────────────────────────────────────

  static ParseReport _parseWireguard(String body, String sourceId) {
    final ParseReport report = ParseReport(sourceId: sourceId);
    final List<String> configs = _extractConfigs(body);
    int index = 0;
    for (final String config in configs) {
      index++;
      final Map<String, String> ini = _parseIni(config);
      if (ini.isEmpty) {
        continue;
      }
      final VpnNode? node = _nodeFromWireguard(ini, sourceId, index);
      if (node == null) {
        report.problems.add('پیکربندی وایرگارد شماره ${Fa.num(index)} ناقص بود.');
        continue;
      }
      report.nodes.add(node);
    }
    if (report.nodes.isEmpty && report.problems.isEmpty) {
      report.problems.add('هیچ پیکربندی وایرگاردی پیدا نشد.');
    }
    return report;
  }

  static List<String> _extractConfigs(String body) {
    final List<String> configs = <String>[];
    final String trimmed = body.trim();
    // پیکربندی وایرگارد خودش با [Interface] شروع می شود؛ این متن INI است و
    // نباید با JSON اشتباه گرفته شود.
    final bool looksIni = trimmed.toLowerCase().startsWith('[interface]');
    if (!looksIni && (trimmed.startsWith('{') || trimmed.startsWith('['))) {
      final Object? json = _tryJson(trimmed);
      if (json is List) {
        for (final Object? item in json) {
          if (item is String) {
            configs.add(item);
          } else if (item is Map) {
            configs.addAll(_configsFromJsonMap(JsonX.asMap(item)));
          }
        }
      } else if (json is Map) {
        configs.addAll(_configsFromJsonMap(JsonX.asMap(json)));
      }
    } else {
      final String? decoded = B64.tryDecode(trimmed);
      final String text = (decoded != null && decoded.contains('[Interface]'))
          ? decoded
          : trimmed;
      final List<String> parts = text.split(RegExp(r'\[Interface\]', caseSensitive: false));
      for (int i = 1; i < parts.length; i++) {
        configs.add('[Interface]${parts[i]}');
      }
      if (configs.isEmpty && text.contains('[Peer]')) {
        configs.add(text);
      }
    }
    return configs;
  }

  static List<String> _configsFromJsonMap(Map<String, dynamic> json) {
    final List<String> configs = <String>[];
    void visit(Object? value) {
      if (value is String) {
        if (value.contains('[Interface]') || value.contains('PrivateKey')) {
          configs.add(value);
        } else if (value.length > 40 && B64.looksLikeBase64(value)) {
          final String? decoded = B64.tryDecode(value);
          if (decoded != null && decoded.contains('[Interface]')) {
            configs.add(decoded);
          }
        }
        return;
      }
      if (value is Map) {
        final Map<String, dynamic> map = JsonX.asMap(value);
        if (map.containsKey('privateKey') && map.containsKey('peerPublicKey')) {
          configs.add(_jsonWireguardToIni(map));
          return;
        }
        for (final Object? item in map.values) {
          visit(item);
        }
        return;
      }
      if (value is List) {
        for (final Object? item in value) {
          visit(item);
        }
      }
    }

    visit(json);
    return configs;
  }

  static String _jsonWireguardToIni(Map<String, dynamic> json) {
    final List<dynamic> addresses = JsonX.asList(json['addresses'] ?? json['address']);
    final Object? peer = json['peer'];
    final Map<String, dynamic> peerMap = peer is Map ? JsonX.asMap(peer) : json;
    final String endpoint = JsonX.text(peerMap['endpoint'] ?? json['endpoint']);
    final StringBuffer buffer = StringBuffer('[Interface]\n');
    buffer.writeln('PrivateKey = ${JsonX.text(json['privateKey'])}');
    buffer.writeln('Address = ${addresses.map((Object? item) => item.toString()).join(', ')}');
    if (json['mtu'] != null) {
      buffer.writeln('MTU = ${JsonX.integer(json['mtu'])}');
    }
    buffer.writeln('[Peer]');
    buffer.writeln('PublicKey = ${JsonX.text(peerMap['publicKey'] ?? json['publicKey'])}');
    if (JsonX.text(peerMap['preSharedKey'] ?? json['preSharedKey']).isNotEmpty) {
      buffer.writeln('PresharedKey = ${JsonX.text(peerMap['preSharedKey'] ?? json['preSharedKey'])}');
    }
    buffer.writeln('Endpoint = $endpoint');
    buffer.writeln('AllowedIPs = 0.0.0.0/0, ::/0');
    buffer.writeln('PersistentKeepalive = ${JsonX.integer(json['persistentKeepalive'], 25)}');
    return buffer.toString();
  }

  static Map<String, String> _parseIni(String config) {
    final Map<String, String> values = <String, String>{};
    String section = '';
    for (final String rawLine in const LineSplitter().convert(config)) {
      final String line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1).toLowerCase();
        continue;
      }
      final int equals = line.indexOf('=');
      if (equals <= 0) {
        continue;
      }
      final String key = line.substring(0, equals).trim();
      final String value = line.substring(equals + 1).trim();
      if (key.toLowerCase() == 'address' && section == 'peer') {
        continue;
      }
      values['$section.${key.toLowerCase()}'] = value;
    }
    return values;
  }

  static VpnNode? _nodeFromWireguard(
    Map<String, String> ini,
    String sourceId,
    int index,
  ) {
    final String privateKey = ini['interface.privatekey'] ?? '';
    final String publicKey = ini['peer.publickey'] ?? '';
    final String endpoint = ini['peer.endpoint'] ?? '';
    if (privateKey.isEmpty || publicKey.isEmpty || !endpoint.contains(':')) {
      return null;
    }
    final int colon = endpoint.lastIndexOf(':');
    final String host = endpoint.substring(0, colon).replaceAll(RegExp(r'^\[|\]$'), '');
    final int port = int.tryParse(endpoint.substring(colon + 1)) ?? 51820;
    final List<String> addresses = (ini['interface.address'] ?? '')
        .split(',')
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList();

    final Map<String, dynamic> params = <String, dynamic>{
      'privateKey': privateKey,
      'publicKey': publicKey,
      'presharedKey': ini['peer.presharedkey'] ?? '',
      'address': addresses,
      'mtu': int.tryParse(ini['interface.mtu'] ?? '') ?? 1420,
      'dns': (ini['interface.dns'] ?? '').split(',').map((String e) => e.trim()).where((String e) => e.isNotEmpty).toList(),
      'keepalive': int.tryParse(ini['peer.persistentkeepalive'] ?? '') ?? 25,
      'allowedIps': ini['peer.allowedips'] ?? '0.0.0.0/0, ::/0',
    };

    // پارامترهای مبهم سازی آمنزیا اگر وجود داشته باشند.
    const List<String> obfuscation = <String>[
      'jc',
      'jmin',
      'jmax',
      's1',
      's2',
      's3',
      's4',
      'h1',
      'h2',
      'h3',
      'h4',
      'i1',
      'i2',
      'i3',
    ];
    bool isAmnezia = false;
    for (final String key in obfuscation) {
      final String value = ini['interface.$key'] ?? '';
      if (value.isNotEmpty) {
        params[key] = value;
        isAmnezia = true;
      }
    }

    return VpnNode(
      id: stableId('$sourceId|wg|$endpoint|$publicKey'),
      name: '${isAmnezia ? 'آمنزیا' : 'وایرگارد'} ${Fa.num(index)}',
      protocol: isAmnezia ? NodeProtocol.amnezia : NodeProtocol.wireguard,
      host: host,
      port: port,
      sourceId: sourceId,
      params: params,
      raw: ini.toString(),
    );
  }

  // ── آمنزیا ─────────────────────────────────────────────────────────

  static ParseReport _parseAmnezia(String body, String sourceId) {
    final ParseReport report = ParseReport(sourceId: sourceId);
    final List<String> configs = _extractConfigs(body);
    int index = 0;
    for (final String config in configs) {
      index++;
      final Map<String, String> ini = _parseIni(config);
      final VpnNode? node = _nodeFromWireguard(ini, sourceId, index);
      if (node == null) {
        continue;
      }
      report.nodes.add(
        VpnNode(
          id: node.id,
          name: node.name.replaceFirst('وایرگارد', 'آمنزیا'),
          protocol: NodeProtocol.amnezia,
          host: node.host,
          port: node.port,
          sourceId: sourceId,
          params: node.params,
          raw: node.raw,
        ),
      );
    }
    if (report.nodes.isEmpty) {
      final ParseReport fallback = _parseWireguard(body, sourceId);
      report.merge(fallback);
    }
    if (report.nodes.isEmpty && report.problems.isEmpty) {
      report.problems.add('پیکربندی آمنزیا خوانده نشد.');
    }
    return report;
  }

  // ── میرو ───────────────────────────────────────────────────────────

  static ParseReport _parseMieru(String body, String sourceId) {
    final ParseReport report = ParseReport(sourceId: sourceId);
    String text = body.trim();
    final Object? root = _tryJson(text);
    if (root == null) {
      final String? decoded = B64.tryDecode(text);
      if (decoded != null) {
        text = decoded;
      }
    }
    final Object? json = root ?? _tryJson(text);
    if (json == null) {
      report.problems.add('پاسخ میرو خوانا نبود.');
      return report;
    }

    final List<Map<String, dynamic>> entries = <Map<String, dynamic>>[];
    void visit(Object? value) {
      if (value is Map) {
        final Map<String, dynamic> map = JsonX.asMap(value);
        if (map.containsKey('portBindings') || map.containsKey('end') || map.containsKey('profiles')) {
          entries.add(map);
          return;
        }
        for (final Object? item in map.values) {
          visit(item);
        }
        return;
      }
      if (value is List) {
        for (final Object? item in value) {
          visit(item);
        }
      }
    }

    visit(json);

    int index = 0;
    for (final Map<String, dynamic> entry in entries) {
      index++;
      Map<String, dynamic> profile = entry;
      final List<dynamic> profiles = JsonX.asList(entry['profiles']);
      if (profiles.isNotEmpty) {
        profile = JsonX.asMap(profiles.first);
      }
      final Map<String, dynamic> endpoint = JsonX.asMap(
        profile['serverEndpoint'] ?? profile['end'] ?? profile['endpoint'],
      );
      final String host = JsonX.text(
        endpoint['ipAddress'] ?? endpoint['host'] ?? entry['host'],
      );
      final List<dynamic> bindings = JsonX.asList(
        endpoint['portBindings'] ?? profile['portBindings'],
      );
      int port = 0;
      String transport = 'TCP';
      if (bindings.isNotEmpty) {
        final Map<String, dynamic> binding = JsonX.asMap(bindings.first);
        port = JsonX.integer(binding['port']);
        transport = JsonX.text(binding['protocol'], 'TCP');
      }
      port = port > 0 ? port : JsonX.integer(endpoint['port'] ?? entry['port']);
      if (host.isEmpty || port <= 0) {
        continue;
      }
      final Map<String, dynamic> user = JsonX.asMap(
        profile['user'] ?? entry['user'],
      );
      final String username = JsonX.text(user['name'] ?? entry['username']);
      final String password = JsonX.text(user['password'] ?? entry['password']);
      report.nodes.add(
        VpnNode(
          id: stableId('$sourceId|mieru|$host|$port|$username'),
          name: JsonX.text(
            profile['profileName'] ?? entry['name'],
            'میرو ${Fa.num(index)}',
          ),
          protocol: NodeProtocol.mieru,
          host: host,
          port: port,
          sourceId: sourceId,
          params: <String, dynamic>{
            'username': username,
            'password': password,
            'transport': transport.toUpperCase(),
            'mtu': JsonX.integer(profile['mtu'], 1400),
            'multiplexing': JsonX.text(profile['multiplexing'], 'MULTIPLEXING_OFF'),
          },
          raw: jsonEncode(profile),
        ),
      );
    }

    if (report.nodes.isEmpty && report.problems.isEmpty) {
      report.problems.add('هیچ سرور میرویی در پاسخ نبود.');
    }
    return report;
  }

  static Object? _tryJson(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}

/// ابزار Base64 تحمل پذیر: padding، حالت URL-safe و خروجی UTF-8.
class B64 {
  const B64._();

  static String? tryDecode(String input) {
    String data = input.trim().replaceAll(RegExp(r'\s'), '');
    if (data.isEmpty) {
      return null;
    }
    data = data.replaceAll('-', '+').replaceAll('_', '/');
    final int remainder = data.length % 4;
    if (remainder == 1) {
      return null;
    }
    if (remainder > 0) {
      data = data.padRight(data.length + (4 - remainder), '=');
    }
    try {
      final List<int> bytes = base64.decode(data);
      final String decoded = utf8.decode(bytes, allowMalformed: true);
      return decoded.isEmpty ? null : decoded;
    } on FormatException {
      return null;
    }
  }

  static bool looksLikeBase64(String value) {
    final String trimmed = value.trim();
    if (trimmed.length < 16) {
      return false;
    }
    return RegExp(r'^[A-Za-z0-9+/=_\-\s]+$').hasMatch(trimmed);
  }

  static String encode(String value) => base64Encode(utf8.encode(value));
}
