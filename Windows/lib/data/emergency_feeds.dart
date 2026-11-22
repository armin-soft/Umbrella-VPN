import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/parsers.dart';
import '../models/models.dart';
import '../vpn/umbrella_core.dart';

/// Untrusted, public feeds are kept separate from the subscriber's own nodes.
/// They never receive the account token or subscription address.
class EmergencyFeeds {
  const EmergencyFeeds._();

  static const String _upstream = UmbrellaCore.id;
  static const List<String> urls = <String>[
    'https://raw.githubusercontent.com/$_upstream/$_upstream-app/refs/heads/main/test.configs/warp',
    'https://raw.githubusercontent.com/patterniha/Free-Configs/refs/heads/main/configs.txt',
    'https://raw.githubusercontent.com/4n0nymou3/multi-proxy-config-fetcher/refs/heads/main/configs/proxy_configs.txt',
    'https://raw.githubusercontent.com/mahsanet/MahsaFreeConfig/refs/heads/main/mtn/sub_1.txt',
    'https://raw.githubusercontent.com/mahsanet/MahsaFreeConfig/refs/heads/main/mci/sub_1.txt',
    'https://raw.githubusercontent.com/4n0nymou3/multi-proxy-config-fetcher/refs/heads/main/configs/$_upstream/Anonymous_Serverless.jsonc',
  ];
  static const int maxBytes = 512 * 1024;
  static const Duration timeout = Duration(seconds: 15);

  /// Only share-link protocols represented faithfully by the existing parser.
  /// WARP/Psiphon and serverless JSONC are not silently presented as working.
  static const Set<String> supported = <String>{
    'vless', 'vmess', 'trojan', 'ss', 'hysteria2', 'hy2', 'tuic', 'anytls',
  };

  static Future<EmergencyFeedResult> fetch(http.Client client, int index) async {
    if (index < 0 || index >= urls.length) {
      throw RangeError.index(index, urls);
    }
    try {
      final request = http.Request('GET', Uri.parse(urls[index]))
        ..followRedirects = false
        ..headers['Accept'] = 'text/plain, application/json';
      final response = await client.send(request).timeout(timeout);
      if (response.statusCode != 200 ||
          (response.contentLength != null && response.contentLength! > maxBytes)) {
        return const EmergencyFeedResult(error: 'دریافت منبع اضطراری ناموفق بود.');
      }
      final List<int> bytes = <int>[];
      await for (final List<int> chunk in response.stream.timeout(timeout)) {
        if (bytes.length + chunk.length > maxBytes) {
          return const EmergencyFeedResult(error: 'حجم منبع اضطراری بیش از حد مجاز است.');
        }
        bytes.addAll(chunk);
      }
      return parse(utf8.decode(bytes, allowMalformed: true), index);
    } on Object {
      return const EmergencyFeedResult(error: 'منبع اضطراری در دسترس نیست.');
    }
  }

  static EmergencyFeedResult parse(String body, int index) {
    if (body.length > maxBytes || body.trim().isEmpty || SubscriptionParser.looksLikeHtml(body)) {
      return const EmergencyFeedResult(error: 'پاسخ منبع اضطراری معتبر نیست.');
    }
    final ParseReport report = SubscriptionParser.parseAuto(body, 'emergency-$index');
    final nodes = report.nodes.where((VpnNode node) {
      final raw = node.raw.trim();
      final scheme = raw.split('://').first.toLowerCase();
      return supported.contains(scheme) && _publicHost(node.host) &&
          node.port > 0 && node.port <= 65535;
    }).take(1000).toList(growable: false);
    return EmergencyFeedResult(
      nodes: nodes,
      error: nodes.isEmpty ? 'این منبع مسیر پیوندی سازگار ندارد.' : '',
    );
  }

  static bool _publicHost(String host) {
    final String value = host.trim().toLowerCase();
    if (value.isEmpty || value == 'localhost' || value.endsWith('.localhost') ||
        value.endsWith('.local') || value.endsWith('.internal') || value.endsWith('.lan')) return false;
    final InternetAddress? ip = InternetAddress.tryParse(value);
    if (ip == null) return value.contains('.') && !value.contains(' ');
    if (ip.isLoopback || ip.isLinkLocal || ip.isMulticast) return false;
    final List<int> b = ip.rawAddress;
    if (ip.type == InternetAddressType.IPv4) {
      return b[0] != 0 && b[0] != 10 && b[0] != 127 && b[0] < 224 &&
          !(b[0] == 192 && b[1] == 168) &&
          !(b[0] == 172 && b[1] >= 16 && b[1] <= 31) &&
          !(b[0] == 100 && b[1] >= 64 && b[1] <= 127) &&
          !(b[0] == 169 && b[1] == 254);
    }
    // Reject unspecified, local unique and IPv4-mapped addresses.
    return value != '::' && (b[0] & 0xfe) != 0xfc &&
        !(b.take(10).every((int x) => x == 0) && b[10] == 0xff && b[11] == 0xff);
  }
}

class EmergencyFeedResult {
  const EmergencyFeedResult({this.nodes = const <VpnNode>[], this.error = ''});
  final List<VpnNode> nodes;
  final String error;
}
