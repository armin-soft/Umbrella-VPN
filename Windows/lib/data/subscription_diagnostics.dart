import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../core/app_config.dart';
import '../core/persian.dart';
import '../models/models.dart';
import 'parsers.dart';
import 'subscription_endpoints.dart';

/// نتیجه بررسی یک نشانی اشتراک.
class EndpointCheck {
  const EndpointCheck({
    required this.title,
    required this.url,
    required this.status,
    required this.nodes,
    this.bytes = 0,
    this.problem = '',
  });

  final String title;
  final String url;
  final int status;
  final int nodes;
  final int bytes;
  final String problem;

  bool get ok => status >= 200 && status < 300 && nodes > 0;

  String get line {
    final String code = status == 0 ? 'بدون پاسخ' : 'کد ${Fa.num(status)}';
    final String size = Fa.bytes(bytes);
    if (ok) {
      return '$title: $code | ${Fa.num(nodes)} سرور | $size';
    }
    return '$title: $code | ${problem.isEmpty ? 'سروری خوانده نشد' : problem}';
  }
}

/// بررسی زنده نشانی اشتراک `/sub/` یک حساب.
class SubscriptionDiagnostics {
  SubscriptionDiagnostics({http.Client? client})
      : _client = client ?? _directClient();

  final http.Client _client;

  /// کلاینت بدون پروکسی.
  ///
  /// اگر پروکسی سیستمی ویندوز به یک پورت مرده اشاره کند (اجرای قبلی یک
  /// فیلترشکن)، هر درخواست با «خطای شبکه» شکست می خورد؛ همان چیزی که باعث
  /// می شد همه نشانی ها در بررسی اشتراک قرمز شوند در حالی که خود پنل سالم
  /// بود. اشتراک باید همیشه مستقیم خوانده شود.
  static http.Client _directClient() {
    final HttpClient inner = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    inner.findProxy = (Uri _) => 'DIRECT';
    return IOClient(inner);
  }

  Future<List<EndpointCheck>> checkAll({
    required String subscriptionUrl,
    required String accountBase,
    required String uuid,
  }) async {
    final List<SubscriptionSource> sources = SubscriptionEndpoints.build(
      subscriptionUrl: subscriptionUrl,
      accountBase: accountBase,
      uuid: uuid,
    );
    final List<EndpointCheck> results = <EndpointCheck>[];
    for (final SubscriptionSource source in sources) {
      results.add(await _check(source));
    }
    return results;
  }

  Future<EndpointCheck> _check(SubscriptionSource source) async {
    try {
      final http.Response response = await _client
          .get(
            Uri.parse(source.url),
            headers: <String, String>{
              'Accept': 'text/plain, */*',
              'User-Agent': 'Umbrella-Windows/${AppConfig.version}',
            },
          )
          .timeout(const Duration(seconds: 20));
      final String body =
          utf8.decode(response.bodyBytes, allowMalformed: true);
      final int status = response.statusCode;
      if (status >= 300) {
        return EndpointCheck(
          title: source.title,
          url: source.url,
          status: status,
          nodes: 0,
          bytes: body.length,
          problem: 'پاسخ ناموفق',
        );
      }
      final ParseReport report = SubscriptionParser.parseAuto(body, source.id);
      return EndpointCheck(
        title: source.title,
        url: source.url,
        status: status,
        nodes: report.count,
        bytes: body.length,
        problem: report.problems.take(1).join(' '),
      );
    } on Exception {
      return EndpointCheck(
        title: source.title,
        url: source.url,
        status: 0,
        nodes: 0,
        problem: 'خطای ارتباط با شبکه',
      );
    }
  }
}
