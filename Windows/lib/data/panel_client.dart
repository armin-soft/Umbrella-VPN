import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../core/app_config.dart';
import '../core/utils.dart';
import '../models/models.dart';

/// خواندن اطلاعات دقیق حساب از پنل وب سرویس (نسخه ۲).
///
/// داده های زنده حساب (شناسه، مصرف، سقف حجم، مدت بسته، تاریخ شروع، آخرین
/// بازنشانی، آخرین فعالیت آنلاین، وضعیت مجوز و نشانی های اختصاصی تونل) را با
/// کلید `Watashi-API-Key` دریافت می کند؛ هیچ کلید خصوصی ذخیره یا برگردانده
/// نمی شود.
class PanelUserApi {
  PanelUserApi({http.Client? client}) : _injectedClient = client;

  final http.Client? _injectedClient;

  static const Duration _timeout = Duration(seconds: 15);

  static http.Client _directClient() {
    final HttpClient inner = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    inner.findProxy = (Uri _) => 'DIRECT';
    return IOClient(inner);
  }

  String get _base {
    final String base = AppConfig.panelBase.trim();
    if (base.isEmpty) {
      return '';
    }
    return base.endsWith('/') ? base : '$base/';
  }

  Map<String, String> _headers(String key) => <String, String>{
        'Watashi-API-Key': key,
        'Accept': 'application/json',
        'User-Agent': 'Umbrella-Windows/${AppConfig.version}',
      };

  Future<Account?> _requestWith(
    http.Client client,
    Uri uri,
    String key,
  ) async {
    final http.Response response =
        await client.get(uri, headers: _headers(key)).timeout(_timeout);
    if (response.statusCode != 200) {
      return null;
    }
    final Object? decoded = jsonDecode(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    // بعضی نسخه های پنل پاسخ را داخل کلید data می گذارند.
    final Map<String, dynamic> body =
        decoded['data'] is Map ? JsonX.asMap(decoded['data']) : decoded;
    if (body.isEmpty) {
      return null;
    }
    return _parse(body);
  }

  /// اطلاعات کاربر با شناسه داده شده؛ اگر پنل جواب ندهد `null`.
  Future<Account?> user(String uuid) async {
    final String cleanUuid = uuid.trim();
    final String key = AppConfig.panelApiKey.trim();
    if (cleanUuid.isEmpty || key.isEmpty || _base.isEmpty) {
      return null;
    }
    final Uri uri = Uri.parse('${_base}api/v2/admin/user/$cleanUuid/');
    final http.Client? injected = _injectedClient;
    if (injected != null) {
      try {
        return await _requestWith(injected, uri, key);
      } on Exception {
        return null;
      }
    }

    // ابتدا از مسیر پیش فرض سیستم (تونل فعال یا اینترنت عادی) تلاش می شود و
    // در صورت خطای پروکسی یا شبکه، یک بار هم مستقیم (بدون پروکسی سیستمی)
    // خوانده می شود تا پروکسی بازمانده مانع دریافت اطلاعات نشود.
    final http.Client primary = http.Client();
    try {
      final Account? result = await _requestWith(primary, uri, key);
      if (result != null) {
        return result;
      }
    } on Exception {
      // مسیر پشتیبان مستقیم در ادامه بررسی می شود.
    } finally {
      primary.close();
    }

    final http.Client direct = _directClient();
    try {
      return await _requestWith(direct, uri, key);
    } on Exception {
      return null;
    } finally {
      direct.close();
    }
  }

  Account _parse(Map<String, dynamic> json) {
    final String rawTelegram = JsonX.text(json['telegram_id']);
    return Account(
      panelId: JsonX.integer(json['id']),
      uuid: JsonX.text(json['uuid']),
      name: JsonX.text(json['name']),
      phone: JsonX.text(json['phone']),
      telegramId: rawTelegram == '0' ? '' : rawTelegram,
      comment: JsonX.text(json['comment']),
      enable: JsonX.boolean(
        json['enable'] ?? json['is_active'],
        fallback: true,
      ),
      isActive: JsonX.boolean(
        json['is_active'] ?? json['enable'],
        fallback: true,
      ),
      usageLimitGb: JsonX.number(
        json['usage_limit_GB'] ??
            json['usage_limit_gb'] ??
            json['usageLimit'] ??
            json['usage_limit'],
      ),
      currentUsageGb: JsonX.number(
        json['current_usage_GB'] ??
            json['current_usage_gb'] ??
            json['currentUsage'] ??
            json['current_usage'],
      ),
      packageDays: JsonX.integer(json['package_days'] ?? json['packageDays']),
      startDate: Fa.parseServerDateTime(json['start_date'] ?? json['created_at']),
      expiryDate: Fa.parseServerDateTime(
        json['expire_date'] ?? json['expiry_date'] ?? json['end_date'],
      ),
      lastResetTime: Fa.parseServerDateTime(json['last_reset_time']),
      lastOnline: Fa.parseServerDateTime(json['last_online']),
      mode: JsonX.text(json['mode']),
      lang: JsonX.text(json['lang'], 'fa'),
      wgIpv4: JsonX.text(json['wg_ipv4']),
      wgIpv6: JsonX.text(json['wg_ipv6']),
      awgIpv4: JsonX.text(json['awg_ipv4']),
      awgIpv6: JsonX.text(json['awg_ipv6']),
    );
  }
}
