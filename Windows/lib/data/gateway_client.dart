import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../core/app_config.dart';
import '../core/utils.dart';
import '../models/models.dart';
import '../platform/native.dart';

/// مسیرهای انتقال درخواست به درگاه آمبرلا برای سازگاری با تمام سامانه های
/// ویندوز ۱۰ و ۱۱ شصت و چهار بیتی و شرایط شبکه مختلف.
enum _GatewayTransport {
  /// WinHTTP + Schannel بومی ویندوز، مستقیم (مخزن گواهی کامل ویندوز + دریافت
  /// خودکار گواهی ریشه/میانی + گذار سریع از IPv6 معیوب به IPv4).
  winHttpDirect,

  /// کلاینت دارت بدون پروکسی (پشتیبان مستقل از WinHTTP).
  dartDirect,

  /// WinHTTP + Schannel با پروکسی فعال ویندوز (برای شبکه هایی که فقط از طریق
  /// پروکسی سازمانی یا فیلترشکن فعال به اینترنت دسترسی دارند).
  winHttpProxy,

  /// کلاینت دارت با پروکسی محیطی و سیستمی.
  dartProxy,
}

/// کلاینت درگاه برنامه روی سرور آمبرلا.
///
/// هیچ کلید حساسی در برنامه نیست: پیامک، تایید تلگرام و ساخت حساب همه در
/// سرور انجام می شود و برنامه فقط شناسه چالش و توکن نشست را می بیند.
class GatewayClient {
  GatewayClient({
    String? baseUrl,
    http.Client? client,
    bool? enableNativeTransport,
  })  : _baseUrl = baseUrl ?? AppConfig.gatewayBase,
        _injectedClient = client != null,
        _enableNativeTransport = enableNativeTransport ??
            (client == null && Platform.isWindows),
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

  /// جزییات فنی آخرین خطای شبکه برای ثبت در گزارش برنامه.
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

  /// سرآیندهای استاندارد سازگار با فایروال های وب (ModSecurity / Imunify360 /
  /// Cloudflare) روی ویندوز ۶۴ بیتی.
  Map<String, String> _buildHeaders({required bool jsonBody, bool formBody = false}) {
    return <String, String>{
      'Accept': 'application/json, text/plain, */*',
      if (jsonBody) 'Content-Type': 'application/json; charset=utf-8',
      if (formBody)
        'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
      'Cache-Control': 'no-cache',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) UmbrellaVPN/${AppConfig.version}',
      'X-Umbrella-Client': 'Windows-x64/${AppConfig.version}',
    };
  }

  List<_GatewayTransport> _transportOrder() {
    final List<_GatewayTransport> base = <_GatewayTransport>[
      if (_enableNativeTransport) _GatewayTransport.winHttpDirect,
      _GatewayTransport.dartDirect,
      if (_enableNativeTransport) _GatewayTransport.winHttpProxy,
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
      case _GatewayTransport.winHttpDirect:
      case _GatewayTransport.winHttpProxy:
        final bool useProxy = transport == _GatewayTransport.winHttpProxy;
        final NativeHttpResponse? native =
            await NativeBridge.performHttpRequest(
          method: method,
          url: uri.toString(),
          headers: headers,
          body: body,
          timeoutMs: _timeout.inMilliseconds,
          useProxy: useProxy,
        );
        if (native == null) {
          return null;
        }
        if (!native.ok || native.statusCode <= 0) {
          diagnostics.add(
            '${transport.name}:${native.error.isEmpty ? native.winError : native.error}',
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
        'ارتباط امن با سرور برقرار نشد؛ ساعت و تاریخ ویندوز و اتصال اینترنت را بررسی کنید.',
      );
    }
    throw const ApiError(
      'network',
      'ارتباط با سرور برقرار نشد؛ اتصال اینترنت یا پروکسی فعال سیستم را بررسی کنید.',
    );
  }

  Future<Map<String, dynamic>> _post(
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
        'ارتباط امن با سرور برقرار نشد؛ ساعت و تاریخ ویندوز را بررسی کنید.',
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
        'ارتباط با سرور برقرار نشد؛ اتصال شبکه ویندوز را بررسی کنید.',
      );
    }
  }

  Future<Map<String, dynamic>> _get(
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
        'ارتباط امن با سرور برقرار نشد؛ ساعت و تاریخ ویندوز را بررسی کنید.',
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

  Future<SessionData> session(String challenge) async {
    final Map<String, dynamic> json =
        await _get('auth/session', <String, String>{'challenge': challenge});
    return SessionData.fromJson(<String, dynamic>{
      'token': json['token'],
      'uuid': json['uuid'],
      'device_id': json['device_id'],
      'sign_in_at': json['sign_in_at'],
      'account': json['account'],
      'filter': json['filter'],
      'offers': json['offers'],
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

  Future<SessionData> refresh(String token) async {
    final Map<String, dynamic> json =
        await _get('account/refresh', <String, String>{'token': token});
    return SessionData(
      token: token,
      uuid: JsonX.text(JsonX.asMap(json['account'])['uuid']),
      deviceId: '',
      account: Account.fromJson(JsonX.asMap(json['account'])),
      filter: FilterSettings.fromJson(JsonX.asMap(json['filter'])),
      offers: SubscriptionOffers.fromJson(JsonX.asMap(json['offers'])),
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

  Future<({FilterSettings? filter, SubscriptionOffers? offers})> heartbeat({
    required String token,
    required String deviceId,
  }) async {
    final Map<String, dynamic> json = await _post('auth/device', <String, dynamic>{
      'token': token,
      'device_id': deviceId,
    });
    final Map<String, dynamic> filterMap = JsonX.asMap(json['filter']);
    final Map<String, dynamic> offersMap = JsonX.asMap(json['offers']);
    return (
      filter: filterMap.isNotEmpty ? FilterSettings.fromJson(filterMap) : null,
      offers:
          offersMap.isNotEmpty ? SubscriptionOffers.fromJson(offersMap) : null,
    );
  }

  Future<FilterSettings> getFilter(String token) async {
    final Map<String, dynamic> json = await _post('filter/get', <String, dynamic>{
      'token': token,
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

/// خواندن مستقیم پنل وب سرویس؛ فقط زمانی که درگاه ربات در دسترس نباشد.
class PanelClient {
  PanelClient({String? baseUrl, String? apiKey, http.Client? client})
      : _baseUrl = baseUrl ?? AppConfig.panelBase,
        _apiKey = apiKey ?? AppConfig.panelApiKey,
        _client = client ?? http.Client();

  final String _baseUrl;
  final String _apiKey;
  final http.Client _client;

  Uri _userUri(String uuid) {
    final String base = _baseUrl.replaceAll(RegExp(r'/+$'), '');
    final String path = uuid.isEmpty
        ? '$base/api/v2/admin/user/'
        : '$base/api/v2/admin/user/$uuid/';
    return Uri.parse(path);
  }

  Map<String, String> get _headers => <String, String>{
        'Accept': 'application/json',
        'Watashi-API-Key': _apiKey,
        'X-API-Key': _apiKey,
        'User-Agent': 'Umbrella-Windows/${AppConfig.version}',
      };

  Future<Account?> fetchAccount(String uuid) async {
    try {
      final http.Response response =
          await _client.get(_userUri(uuid), headers: _headers).timeout(
                const Duration(seconds: 20),
              );
      if (response.statusCode >= 300) {
        return null;
      }
      final Map<String, dynamic> json = JsonX.asMap(
        jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true)),
      );
      final Map<String, dynamic> account =
          json['data'] is Map ? JsonX.asMap(json['data']) : json;
      if (account.isEmpty) {
        return null;
      }
      return Account.fromJson(account);
    } on Exception {
      return null;
    }
  }
}
