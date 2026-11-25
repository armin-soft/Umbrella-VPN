import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../core/app_config.dart';
import '../core/utils.dart';
import '../models/models.dart';
import '../platform/native.dart';
import '../platform/services.dart';

/// مسیرهای انتقال درخواست به درگاه آمبرلا برای سازگاری با اندروید و شرایط شبکه مختلف.
enum _GatewayTransport {
  /// کلاینت بومی OkHttp اندروید مستقیم.
  nativeDirect,

  /// کلاینت دارت مستقیم.
  dartDirect,

  /// کلاینت بومی اندروید با پروکسی محلی در صورت فعال بودن.
  nativeProxy,

  /// کلاینت دارت با پروکسی محیطی.
  dartProxy,
}

/// کلاینت درگاه برنامه روی سرور آمبرلا.
class GatewayClient {
  GatewayClient({
    String? baseUrl,
    http.Client? client,
    bool? enableNativeTransport,
  })  : _baseUrl = baseUrl ?? AppConfig.gatewayBase,
        _injectedClient = client != null,
        _enableNativeTransport =
            enableNativeTransport ?? (client == null && Platform.isAndroid),
        _client = client ?? _createIoClient(direct: true),
        _proxyClient = client == null ? _createIoClient(direct: false) : null;

  static http.Client _createIoClient({required bool direct}) {
    final HttpClient inner = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..idleTimeout = const Duration(seconds: 15);
    inner.findProxy =
        direct ? (Uri _) => 'DIRECT' : HttpClient.findProxyFromEnvironment;
    return IOClient(inner);
  }

  final String _baseUrl;
  final bool _injectedClient;
  final bool _enableNativeTransport;
  final http.Client _client;
  final http.Client? _proxyClient;

  static _GatewayTransport? _stickyTransport;
  static const Duration _timeout = Duration(seconds: 18);
  static const Set<int> _wafRetryStatuses = <int>{403, 406, 415};

  String _lastDiagnostic = '';

  String get lastDiagnostic => _lastDiagnostic;

  String get baseUrl => _baseUrl;

  String get hostName => Uri.tryParse(_baseUrl)?.host ?? _baseUrl;

  Uri _uri(String route, [Map<String, String>? query]) {
    final String base = _baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.contains('?')) {
      final Uri parsed = Uri.parse(base);
      final Map<String, String> params = <String, String>{
        ...parsed.queryParameters,
        'AppApi': route,
      };
      if (query != null) {
        params.addAll(query);
      }
      return parsed.replace(queryParameters: params);
    }
    return Uri.parse('$base/$route').replace(queryParameters: query);
  }

  Map<String, String> _buildHeaders({
    required bool jsonBody,
    bool formBody = false,
  }) {
    return <String, String>{
      'Accept': 'application/json, text/plain, */*',
      if (jsonBody) 'Content-Type': 'application/json; charset=utf-8',
      if (formBody)
        'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
      'Cache-Control': 'no-cache',
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14) UmbrellaVPN/${AppConfig.version}',
      'X-Umbrella-Client': 'Android/${AppConfig.version}',
    };
  }

  List<_GatewayTransport> _transportOrder() {
    final List<_GatewayTransport> base = <_GatewayTransport>[
      if (_enableNativeTransport) _GatewayTransport.nativeDirect,
      _GatewayTransport.dartDirect,
      if (_enableNativeTransport) _GatewayTransport.nativeProxy,
      if (_proxyClient != null) _GatewayTransport.dartProxy,
    ];
    final _GatewayTransport? sticky = _stickyTransport;
    if (sticky != null && base.contains(sticky)) {
      return <_GatewayTransport>[
        sticky,
        for (final _GatewayTransport item in base)
          if (item != sticky) item,
      ];
    }
    return base;
  }

  Future<http.Response?> _sendOnTransport({
    required _GatewayTransport transport,
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required String body,
    required List<String> diagnostics,
  }) async {
    switch (transport) {
      case _GatewayTransport.nativeDirect:
      case _GatewayTransport.nativeProxy:
        final bool useProxy = transport == _GatewayTransport.nativeProxy;
        final NativeHttpResponse? native =
            await NativeBridge.performHttpRequest(
          method: method,
          url: uri.toString(),
          headers: headers,
          body: body,
          timeoutMs: _timeout.inMilliseconds,
          proxyHost: useProxy ? '127.0.0.1' : null,
          proxyPort: useProxy ? AppConfig.httpPortUmbrella : 0,
        );
        if (native == null) {
          return null;
        }
        if (!native.ok || native.statusCode <= 0) {
          diagnostics.add(
            '${transport.name}:${native.error.isEmpty ? 'http_error' : native.error}',
          );
          return null;
        }
        return http.Response.bytes(
          native.bodyBytes,
          native.statusCode,
          headers: native.contentType.isEmpty
              ? const <String, String>{}
              : <String, String>{'content-type': native.contentType},
        );

      case _GatewayTransport.dartDirect:
      case _GatewayTransport.dartProxy:
        final http.Client client = transport == _GatewayTransport.dartProxy
            ? (_proxyClient ?? _client)
            : _client;
        try {
          if (method == 'POST') {
            return await client
                .post(uri, headers: headers, body: body)
                .timeout(_timeout);
          }
          return await client.get(uri, headers: headers).timeout(_timeout);
        } on TimeoutException {
          diagnostics.add('${transport.name}:timeout');
          return null;
        } on HandshakeException catch (error) {
          diagnostics.add('${transport.name}:tls_handshake(${error.message})');
          return null;
        } on CertificateException catch (error) {
          diagnostics.add('${transport.name}:tls_cert(${error.message})');
          return null;
        } on TlsException catch (error) {
          diagnostics.add('${transport.name}:tls(${error.message})');
          return null;
        } on SocketException catch (error) {
          diagnostics.add('${transport.name}:socket(${error.message})');
          return null;
        } on HttpException catch (error) {
          diagnostics.add('${transport.name}:http(${error.message})');
          return null;
        } on http.ClientException catch (error) {
          diagnostics.add('${transport.name}:client(${error.message})');
          return null;
        } on OSError catch (error) {
          diagnostics.add('${transport.name}:os(${error.errorCode})');
          return null;
        }
    }
  }

  bool _looksLikeWafBlock(http.Response response) {
    if (!_wafRetryStatuses.contains(response.statusCode)) {
      return false;
    }
    final String body = utf8.decode(response.bodyBytes, allowMalformed: true);
    return _tryDecodeJsonMap(body).isEmpty;
  }

  Future<http.Response> _dispatch({
    required String method,
    required Uri uri,
    Map<String, dynamic>? jsonPayload,
  }) async {
    _lastDiagnostic = '';
    final String encodedJson =
        jsonPayload == null ? '' : jsonEncode(jsonPayload);
    final Map<String, String> headers = _buildHeaders(
      jsonBody: method == 'POST',
    );

    if (_injectedClient) {
      if (method == 'POST') {
        final http.Response first = await _client
            .post(uri, headers: headers, body: encodedJson)
            .timeout(_timeout);
        if (_looksLikeWafBlock(first)) {
          final String formBody =
              '_json=${Uri.encodeQueryComponent(encodedJson)}';
          return _client
              .post(
                uri,
                headers: _buildHeaders(jsonBody: false, formBody: true),
                body: formBody,
              )
              .timeout(_timeout);
        }
        return first;
      }
      return _client.get(uri, headers: headers).timeout(_timeout);
    }

    final List<String> diagnostics = <String>[];
    http.Response? fallbackHttpError;
    for (final _GatewayTransport transport in _transportOrder()) {
      http.Response? response = await _sendOnTransport(
        transport: transport,
        method: method,
        uri: uri,
        headers: headers,
        body: encodedJson,
        diagnostics: diagnostics,
      );
      if (response == null) {
        continue;
      }
      if (method == 'POST' && _looksLikeWafBlock(response)) {
        final String formBody =
            '_json=${Uri.encodeQueryComponent(encodedJson)}';
        final http.Response? retried = await _sendOnTransport(
          transport: transport,
          method: 'POST',
          uri: uri,
          headers: _buildHeaders(jsonBody: false, formBody: true),
          body: formBody,
          diagnostics: diagnostics,
        );
        if (retried != null) {
          response = retried;
        }
      }
      // اگر مسیر فعلی پاسخ خطای غیر JSON برگرداند (مثلا صفحه مسدودسازی
      // فایروال یا خطای ۵۰۲/۴۰۳/۴۰۰ میزبان میانی)، مسیر بعدی (بدون پروکسی یا
      // با پروکسی) هم آزموده می شود؛ پاسخ JSON واقعی سرور بلافاصله برمی گردد.
      if (response.statusCode >= 400 &&
          _tryDecodeJsonMap(
            utf8.decode(response.bodyBytes, allowMalformed: true),
          ).isEmpty) {
        fallbackHttpError ??= response;
        diagnostics.add('${transport.name}:http_${response.statusCode}');
        continue;
      }
      _stickyTransport = transport;
      return response;
    }

    if (fallbackHttpError != null) {
      _lastDiagnostic = diagnostics.join(' | ');
      return fallbackHttpError;
    }

    _lastDiagnostic = diagnostics.join(' | ');
    final bool allTimeouts = diagnostics.isNotEmpty &&
        diagnostics.every((String item) => item.contains('timeout'));
    final bool tlsIssue = diagnostics.any((String item) => item.contains('tls'));
    if (allTimeouts) {
      throw const ApiError(
        'timeout',
        'پاسخ سرور دیر رسید؛ اتصال اینترنت را بررسی کنید و دوباره تلاش کنید.',
      );
    }
    if (tlsIssue &&
        diagnostics.every((String item) => item.contains('tls'))) {
      throw const ApiError(
        'network',
        'ارتباط امن با سرور برقرار نشد؛ ساعت و تاریخ دستگاه و اتصال اینترنت را بررسی کنید.',
      );
    }
    throw const ApiError(
      'network',
      'ارتباط با سرور برقرار نشد؛ اتصال اینترنت را بررسی کنید.',
    );
  }

  // Only operation and a bounded error category are recorded: never request
  // payloads, server messages, challenge codes, tokens, or account details.
  final Map<String, DateTime> _diagnosticTimes = <String, DateTime>{};

  void _recordGatewayFailure(String route, Object error) {
    final String area = switch (route.split('/').first) {
      'auth' => 'ورود و دستگاه',
      'account' => 'حساب',
      'wallet' => 'کیف پول و پرداخت',
      'subscription' => 'اشتراک',
      'filter' => 'کنترل محتوا',
      'bypass' => 'مسیر مستقیم',
      _ => 'درگاه برنامه',
    };
    final String kind = error is ApiError
        ? (error.isNetwork ? 'ارتباط شبکه' :
           error.needsLogin ? 'نشست یا مجوز' :
           error.code == 'bad_response' ? 'پاسخ نامعتبر سرور' : 'پاسخ خطای سرور')
        : 'خطای پیش بینی نشده';
    // Routes are code constants, but restrict them to known identifiers so no
    // accidental query string or future caller data can enter the log.
    final String operation = RegExp(r'^[a-z_]+/[a-z_-]+$').hasMatch(route)
        ? route : 'unknown';
    final String key = '$operation|$kind';
    final DateTime now = DateTime.now();
    final DateTime? last = _diagnosticTimes[key];
    if (last != null && now.difference(last) < const Duration(minutes: 5)) return;
    if (_diagnosticTimes.length >= 64) _diagnosticTimes.clear();
    _diagnosticTimes[key] = now;
    final int? status = error is ApiError ? error.status : null;
    AppLogger.instance.add(
      'بخش $area: $kind ($operation${status != null && status >= 100 && status <= 599 ? '، HTTP $status' : ''})',
      level: 'error',
    );
  }

  Future<Map<String, dynamic>> _post(String route, Map<String, dynamic> body) async {
    try {
      return await _postImpl(route, body);
    } catch (error) {
      _recordGatewayFailure(route, error);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _get(String route, [Map<String, String>? query]) async {
    try {
      return await _getImpl(route, query);
    } catch (error) {
      _recordGatewayFailure(route, error);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _postImpl(
    String route,
    Map<String, dynamic> body,
  ) async {
    try {
      final http.Response response = await _dispatch(
        method: 'POST',
        uri: _uri(route),
        jsonPayload: body,
      );
      return _decode(response);
    } on ApiError {
      rethrow;
    } on TimeoutException {
      throw const ApiError(
        'timeout',
        'پاسخ سرور دیر رسید؛ اتصال اینترنت را بررسی کنید و دوباره تلاش کنید.',
      );
    } on TlsException {
      throw const ApiError(
        'network',
        'ارتباط امن با سرور برقرار نشد؛ ساعت و تاریخ دستگاه را بررسی کنید.',
      );
    } on SocketException {
      throw const ApiError(
        'network',
        'ارتباط با سرور برقرار نشد؛ اینترنت یا فیلترشکن دیگری را بررسی کنید.',
      );
    } on HttpException {
      throw const ApiError(
        'network',
        'ارتباط با سرور قطع شد؛ دوباره تلاش کنید.',
      );
    } on http.ClientException {
      throw const ApiError(
        'network',
        'ارتباط با سرور قطع شد؛ دوباره تلاش کنید.',
      );
    } on OSError {
      throw const ApiError(
        'network',
        'ارتباط با سرور برقرار نشد؛ اتصال شبکه دستگاه را بررسی کنید.',
      );
    }
  }

  Future<Map<String, dynamic>> _getImpl(
    String route, [
    Map<String, String>? query,
  ]) async {
    try {
      final http.Response response = await _dispatch(
        method: 'GET',
        uri: _uri(route, query),
      );
      return _decode(response);
    } on ApiError {
      rethrow;
    } on TimeoutException {
      throw const ApiError('timeout', 'پاسخ سرور دیر رسید؛ دوباره تلاش کنید.');
    } on TlsException {
      throw const ApiError(
        'network',
        'ارتباط امن با سرور برقرار نشد؛ ساعت و تاریخ دستگاه را بررسی کنید.',
      );
    } on SocketException {
      throw const ApiError('network', 'ارتباط با سرور برقرار نشد.');
    } on HttpException {
      throw const ApiError('network', 'ارتباط با سرور قطع شد.');
    } on http.ClientException {
      throw const ApiError('network', 'ارتباط با سرور قطع شد.');
    } on OSError {
      throw const ApiError('network', 'ارتباط با سرور برقرار نشد.');
    }
  }

  static Map<String, dynamic> _tryDecodeJsonMap(String raw) {
    String cleaned = raw.trim();
    if (cleaned.startsWith('\uFEFF')) {
      cleaned = cleaned.substring(1).trimLeft();
    }
    if (cleaned.isEmpty) {
      return <String, dynamic>{};
    }
    try {
      return JsonX.asMap(jsonDecode(cleaned));
    } on FormatException {
      // اگر میزبان وب یک خط هشدار قبل از بدنه JSON چاپ کرده باشد، شیء JSON
      // پایانی را امن استخراج می کنیم.
      final int start = cleaned.indexOf('{');
      final int end = cleaned.lastIndexOf('}');
      if (start >= 0 && end > start) {
        try {
          return JsonX.asMap(jsonDecode(cleaned.substring(start, end + 1)));
        } on FormatException {
          return <String, dynamic>{};
        }
      }
      return <String, dynamic>{};
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    final String body = utf8.decode(response.bodyBytes, allowMalformed: true);
    final Map<String, dynamic> json = _tryDecodeJsonMap(body);
    if (json.isEmpty) {
      // پاسخ غیر JSON یعنی آدرس اشتباه است (معمولا صفحه ۴۰۴ میزبان) یا سرور
      // خطای PHP داده است. نشانی و کد را در پیام می آوریم تا قابل پیگیری باشد.
      final String hint = response.statusCode == 404
          ? 'چنین مسیری روی سرور نیست'
          : 'ساختار پاسخ سرور معتبر نبود';
      throw ApiError(
        'bad_response',
        Fa.num(
          '$hint (کد ${response.statusCode}) از $hostName؛ '
          'نشانی درگاه را در تنظیمات بررسی کنید.',
        ),
        status: response.statusCode,
      );
    }
    final bool ok = JsonX.boolean(json['ok'], fallback: response.statusCode < 400);
    if (!ok) {
      final String serverMsg =
          JsonX.text(json['message'], 'خطای نامشخص از سرور')
              .replaceAll('\u200c', ' ');
      throw ApiError(
        JsonX.text(json['error'], 'unknown'),
        Fa.num(serverMsg),
        retryAfter: json['retry_after'] == null ? null : JsonX.integer(json['retry_after']),
        status: response.statusCode,
      );
    }
    return json;
  }

  Future<SignInStart> start({
    required String phone,
    required String deviceId,
    required String deviceName,
    required String platform,
    String firstName = '',
    String lastName = '',
  }) async {
    final Map<String, dynamic> json = await _post('auth/start', <String, dynamic>{
      'phone': phone,
      'device_id': deviceId,
      'device_name': deviceName,
      'platform': platform,
      'app_version': AppConfig.version,
      'first_name': firstName,
      'last_name': lastName,
    });
    return SignInStart.fromJson(json);
  }

  Future<SignInVerify> verify({
    required String challenge,
    required String code,
  }) async {
    final Map<String, dynamic> json = await _post('auth/verify', <String, dynamic>{
      'challenge': challenge,
      'code': Fa.toEn(code),
    });
    return SignInVerify.fromJson(json);
  }

  Future<SignInStatus> status(String challenge) async {
    final Map<String, dynamic> json =
        await _get('auth/status', <String, String>{'challenge': challenge});
    return SignInStatus.fromJson(json);
  }

  Future<void> cancelSignIn(String challenge) async {
    await _post('auth/cancel', <String, dynamic>{'challenge': challenge});
  }

  Future<SessionData> session(String challenge) async {
    final Map<String, dynamic> json =
        await _get('auth/session', <String, String>{'challenge': challenge});
    final Map<String, dynamic> annMap = JsonX.asMap(json['announcement']);
    return SessionData.fromJson(<String, dynamic>{
      'token': json['token'],
      'uuid': json['uuid'],
      'device_id': json['device_id'],
      'sign_in_at': json['sign_in_at'],
      'account': json['account'],
      'filter': json['filter'],
      'offers': json['offers'],
      if (annMap.isNotEmpty) 'announcement': annMap,
    });
  }

  Future<void> resend(String challenge) async {
    await _post('auth/resend', <String, dynamic>{'challenge': challenge});
  }

  Future<void> signOut({String token = '', String challenge = ''}) async {
    await _post('auth/signout', <String, dynamic>{
      'token': token,
      'challenge': challenge,
    });
  }

  Future<bool> botMembershipStatus(String token) async {
    final json = await _get('account/bot-link-status', <String, String>{'token': token});
    return JsonX.boolean(json['linked']);
  }

  Future<Map<String, dynamic>> createBotMembershipLink(String token) =>
      _post('account/bot-link', <String, dynamic>{'token': token});

  Future<SessionData> refresh(String token) async {
    final Map<String, dynamic> json =
        await _get('account/refresh', <String, String>{'token': token});
    final Map<String, dynamic> annMap = JsonX.asMap(json['announcement']);
    return SessionData(
      token: token,
      uuid: JsonX.text(JsonX.asMap(json['account'])['uuid']),
      deviceId: '',
      account: Account.fromJson(JsonX.asMap(json['account'])),
      filter: FilterSettings.fromJson(JsonX.asMap(json['filter'])),
      offers: SubscriptionOffers.fromJson(JsonX.asMap(json['offers'])),
      announcement:
          annMap.isNotEmpty ? AppAnnouncement.fromJson(annMap) : null,
    );
  }

  Future<List<AppNotification>> notifications(
    String token, {
    bool includeHistory = false,
  }) async {
    final Map<String, dynamic> json = await _get(
      'app/notifications',
      <String, String>{
        'token': token,
        if (includeHistory) 'history': '1',
      },
    );
    return JsonX.asList(json['items'])
        .map((Object? item) => AppNotification.fromJson(JsonX.asMap(item)))
        .toList();
  }

  Future<AppAnnouncement?> fetchAnnouncement() async {
    try {
      final Map<String, dynamic> json = await _get('app/announcement');
      final Map<String, dynamic> annMap = JsonX.asMap(json['announcement']);
      if (annMap.isEmpty) {
        return null;
      }
      return AppAnnouncement.fromJson(annMap);
    } on ApiError {
      return null;
    }
  }

  Future<Map<String, dynamic>> reportSecurityAlert({
    required String token,
    required String deviceId,
    required String platform,
    required String appVersion,
    required List<SecurityThreat> threats,
    List<NeutralizedSecurityEvent> neutralized =
        const <NeutralizedSecurityEvent>[],
    List<String> resolvedKeys = const <String>[],
    bool syncAll = false,
  }) async {
    return _post('app/security-alert', <String, dynamic>{
      'token': token,
      'device_id': deviceId,
      'platform': platform,
      'app_version': appVersion,
      'threats': threats.map((SecurityThreat t) => t.toAlertPayload()).toList(),
      if (neutralized.isNotEmpty)
        'neutralized': neutralized
            .map((NeutralizedSecurityEvent e) => e.toAlertPayload())
            .toList(),
      if (resolvedKeys.isNotEmpty) 'resolved_keys': resolvedKeys,
      if (syncAll) 'sync_all': true,
    });
  }

  Future<
      ({
        Account? account,
        FilterSettings? filter,
        SubscriptionOffers? offers,
        bool? emergencyEnabled,
        bool? botLinked,
        AppAnnouncement? announcement,
      })> heartbeat({
    required String token,
    required String deviceId,
    List<Map<String, dynamic>> activity = const <Map<String, dynamic>>[],
    String currentScreen = '',
    String deviceName = '',
    String platform = '',
    String appVersion = '',
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'token': token,
      'device_id': deviceId,
      if (deviceName.isNotEmpty) 'device_name': deviceName,
      if (platform.isNotEmpty) 'platform': platform,
      if (appVersion.isNotEmpty) 'app_version': appVersion,
      if (activity.isNotEmpty) 'activity': activity,
    };
    final Map<String, dynamic> json = await _post('auth/device', body);
    final Map<String, dynamic> accountMap = JsonX.asMap(json['account']);
    final Map<String, dynamic> filterMap = JsonX.asMap(json['filter']);
    final Map<String, dynamic> offersMap = JsonX.asMap(json['offers']);
    final Map<String, dynamic> annMap = JsonX.asMap(json['announcement']);
    return (
      account: accountMap.isNotEmpty ? Account.fromJson(accountMap) : null,
      filter: filterMap.isNotEmpty ? FilterSettings.fromJson(filterMap) : null,
      emergencyEnabled: json.containsKey('emergency_enabled')
          ? JsonX.boolean(json['emergency_enabled']) : null,
      offers:
          offersMap.isNotEmpty ? SubscriptionOffers.fromJson(offersMap) : null,
      botLinked: json.containsKey('bot_linked')
          ? JsonX.boolean(json['bot_linked']) : null,
      announcement:
          annMap.isNotEmpty ? AppAnnouncement.fromJson(annMap) : null,
    );
  }

  Future<String> sendSupportReport({
    String token = '',
    required String deviceId,
    String phone = '',
    String note = '',
    required String platform,
    required String appVersion,
    required Map<String, dynamic> device,
    required Map<String, dynamic> vpnState,
    required List<Map<String, dynamic>> errors,
    required String recentLogs,
  }) async {
    final Map<String, dynamic> json = await _post('app/support-report', <String, dynamic>{
      if (token.isNotEmpty) 'token': token,
      'device_id': deviceId,
      if (phone.isNotEmpty) 'phone': phone,
      if (note.isNotEmpty) 'note': note,
      'platform': platform,
      'app_version': appVersion,
      'device': device,
      'vpn_state': vpnState,
      'errors': errors,
      'recent_logs': recentLogs,
    });
    return JsonX.text(
      json['message'],
      'مشخصات دستگاه و گزارش خطاها بلافاصله برای پشتیبانی ارسال شد.',
    );
  }

  Future<FilterSettings> getFilter(String token) async {
    final Map<String, dynamic> json = await _post('filter/get', <String, dynamic>{
      'token': token,
    });
    return FilterSettings.fromJson(JsonX.asMap(json['settings']));
  }

  Future<FilterSettings> saveBypass(String token, FilterSettings settings) async {
    final Map<String, dynamic> json = await _post('bypass/save', <String, dynamic>{
      'token': token,
      'settings': <String, dynamic>{'iran': settings.bypassIran, 'domains': settings.bypassDomains},
    });
    return FilterSettings.fromJson(JsonX.asMap(json['settings']));
  }

  Future<FilterSettings> saveFilter(String token, FilterSettings settings) async {
    final Map<String, dynamic> json = await _post('filter/save', <String, dynamic>{
      'token': token,
      'settings': settings.toJson(),
    });
    return FilterSettings.fromJson(JsonX.asMap(json['settings']));
  }

  Future<({List<SubscriptionPlan> plans, int balance, CustomSubscriptionTerms? custom})>
      subscriptionPlans(String token) async {
    final Map<String, dynamic> json = await _get(
      'subscription/plans',
      <String, String>{'token': token},
    );
    return (
      plans: JsonX.asList(json['plans'])
          .map((Object? item) =>
              SubscriptionPlan.fromJson(JsonX.asMap(item)))
          .where((SubscriptionPlan plan) =>
              plan.month.isNotEmpty && plan.price > 0)
          .toList(),
      balance: JsonX.integer(json['balance']),
      custom: JsonX.asMap(json['custom']).isEmpty ? null :
          CustomSubscriptionTerms.fromJson(JsonX.asMap(json['custom'])),
    );
  }

  Future<Map<String, dynamic>> purchaseSubscription({
    required String token,
    required String month,
    int? quotedPrice,
  }) =>
      _post('subscription/purchase', <String, dynamic>{
        'token': token,
        'month': month,
        if (quotedPrice != null) 'quoted_price': quotedPrice,
      });

  Future<Map<String, dynamic>> purchaseCustomSubscription({
    required String token, required int days, required double gb, int? quotedPrice,
  }) => _post('subscription/purchase', <String, dynamic>{
    'token': token, 'type': 'custom', 'days': days, 'gb': gb,
    if (quotedPrice != null) 'quoted_price': quotedPrice,
  });

  Future<Map<String, dynamic>> walletStatus(String token) =>
      _get('wallet/status', <String, String>{'token': token});

  Future<Map<String, dynamic>> startWalletTopup({required String token, required int amount}) =>
      _post('wallet/topup', <String, dynamic>{'token': token, 'amount': amount});

  Future<Map<String, dynamic>> cancelWalletPayment(String token, String pendingId) =>
      _post('wallet/cancel', <String, dynamic>{'token': token, 'pending_id': pendingId});

  Future<Map<String, dynamic>> verifyWalletTopup(String token) =>
      _post('wallet/verify', <String, dynamic>{'token': token});

  Future<SubscriptionOffers> subscriptionOffers(String token) async {
    final Map<String, dynamic> json =
        await _get('subscription/offers', <String, String>{'token': token});
    return SubscriptionOffers.fromJson(JsonX.asMap(json['offers']));
  }

  Future<
      ({
        String message,
        Account account,
        FilterSettings filter,
        SubscriptionOffers offers,
      })> claimSubscription({
    required String token,
    required String type,
  }) async {
    final Map<String, dynamic> json =
        await _post('subscription/claim', <String, dynamic>{
      'token': token,
      'type': type,
    });
    return (
      message: JsonX.text(json['message']),
      account: Account.fromJson(JsonX.asMap(json['account'])),
      filter: FilterSettings.fromJson(JsonX.asMap(json['filter'])),
      offers: SubscriptionOffers.fromJson(JsonX.asMap(json['offers'])),
    );
  }

  /// دریافت محتوای اشتراک اختصاصی `/sub/` کاربر از طریق درگاه امن ربات؛ برای
  /// شبکه هایی که دسترسی مستقیم به دامنه پنل اشتراک پیش از اتصال محدود است.
  Future<({String content, String subscriptionUrl, String accountBase})?>
      fetchSubscription(String token) async {
    if (token.trim().isEmpty) {
      return null;
    }
    try {
      final Map<String, dynamic> json = await _post(
        'subscription/fetch',
        <String, dynamic>{'token': token},
      );
      final String content = JsonX.text(json['content']).trim();
      if (content.isEmpty) {
        return null;
      }
      return (
        content: content,
        subscriptionUrl: JsonX.text(json['subscription_url']).trim(),
        accountBase: JsonX.text(json['account_base']).trim(),
      );
    } on ApiError catch (error) {
      if (error.code == 'device_revoked' || error.needsLogin) {
        rethrow;
      }
      return null;
    }
  }

  Future<bool> ping() async {
    try {
      final Map<String, dynamic> json = await _get('app/ping');
      return JsonX.boolean(json['ok'], fallback: true);
    } on ApiError {
      return false;
    }
  }

  void close() {
    _client.close();
    _proxyClient?.close();
  }

  /// پاک سازی مسیر ذخیره شده برای آزمون واحد.
  static void resetStickyTransportForTest() {
    _stickyTransport = null;
  }
}
