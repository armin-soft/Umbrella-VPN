import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../core/app_config.dart';
import '../core/utils.dart';
import '../models/models.dart';

/// کلاینت درگاه برنامه روی سرور آمبرلا.
///
/// هیچ کلید حساسی در برنامه نیست: پیامک، تایید تلگرام و ساخت حساب همه در
/// سرور انجام می شود و برنامه فقط شناسه چالش و توکن نشست را می بیند.
class GatewayClient {
  GatewayClient({String? baseUrl, http.Client? client})
      : _baseUrl = baseUrl ?? AppConfig.gatewayBase,
        _client = client ?? _directClient();

  /// درگاه ایرانی است و باید مستقیم صدا زده شود؛ پروکسی بازمانده یک برنامه
  /// دیگر نباید ورود و پروفایل را بشکند.
  static http.Client _directClient() {
    final HttpClient inner = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    inner.findProxy = (Uri _) => 'DIRECT';
    return IOClient(inner);
  }

  final String _baseUrl;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 25);

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

  Map<String, String> get _headers => <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
        'User-Agent': 'Umbrella-Windows/${AppConfig.version}',
      };

  Future<Map<String, dynamic>> _post(
    String route,
    Map<String, dynamic> body,
  ) async {
    try {
      final http.Response response = await _client
          .post(_uri(route), headers: _headers, body: jsonEncode(body))
          .timeout(_timeout);
      return _decode(response);
    } on TimeoutException {
      throw const ApiError('timeout', 'پاسخ سرور دیر رسید؛ اتصال اینترنت را بررسی کنید و دوباره تلاش کنید.');
    } on SocketException {
      throw const ApiError('network', 'ارتباط با سرور برقرار نشد؛ اینترنت یا فیلترشکن دیگری را بررسی کنید.');
    } on http.ClientException {
      throw const ApiError('network', 'ارتباط با سرور قطع شد؛ دوباره تلاش کنید.');
    } on HandshakeException {
      throw const ApiError('network', 'ارتباط امن با سرور برقرار نشد.');
    }
  }

  Future<Map<String, dynamic>> _get(
    String route, [
    Map<String, String>? query,
  ]) async {
    try {
      final http.Response response = await _client
          .get(_uri(route, query), headers: _headers)
          .timeout(_timeout);
      return _decode(response);
    } on TimeoutException {
      throw const ApiError('timeout', 'پاسخ سرور دیر رسید؛ دوباره تلاش کنید.');
    } on SocketException {
      throw const ApiError('network', 'ارتباط با سرور برقرار نشد.');
    } on http.ClientException {
      throw const ApiError('network', 'ارتباط با سرور قطع شد.');
    } on HandshakeException {
      throw const ApiError('network', 'ارتباط امن با سرور برقرار نشد.');
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    final String body = utf8.decode(response.bodyBytes, allowMalformed: true);
    Map<String, dynamic> json = <String, dynamic>{};
    if (body.trim().isNotEmpty) {
      try {
        json = JsonX.asMap(jsonDecode(body));
      } on FormatException {
        json = <String, dynamic>{};
      }
    }
    if (json.isEmpty) {
      // پاسخ غیر JSON یعنی آدرس اشتباه است (معمولاً صفحه ۴۰۴ میزبان) یا سرور
      // خطای PHP داده است. نشانی و کد را در پیام می آوریم تا قابل پیگیری باشد.
      final String hint = response.statusCode == 404
          ? 'چنین مسیری روی سرور نیست'
          : 'پاسخ سرور JSON نبود';
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
      throw ApiError(
        JsonX.text(json['error'], 'unknown'),
        JsonX.text(json['message'], 'خطای نامشخص از سرور'),
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
    );
  }

  Future<List<AppNotification>> notifications(String token) async {
    final Map<String, dynamic> json =
        await _get('app/notifications', <String, String>{'token': token});
    return JsonX.asList(json['items'])
        .map((Object? item) => AppNotification.fromJson(JsonX.asMap(item)))
        .toList();
  }

  Future<void> heartbeat({required String token, required String deviceId}) async {
    await _post('auth/device', <String, dynamic>{
      'token': token,
      'device_id': deviceId,
    });
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

  Future<bool> ping() async {
    try {
      final Map<String, dynamic> json = await _get('app/ping');
      return JsonX.boolean(json['ok'], fallback: true);
    } on ApiError {
      return false;
    }
  }

  void close() => _client.close();
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
