import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../core/utils.dart';
import '../models/models.dart';

/// خواندن اطلاعات دقیق حساب از پنل وب سرویس.
///
/// همین داده ای است که پنل نمایش می دهد (مصرف، حجم کل، تاریخ انقضا و وضعیت)؛
/// پس اعداد صفحه «حساب من» با پنل یکی می شود.
class PanelClient {
  PanelClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 18);

  String get _base {
    final String base = AppConfig.panelBase.trim();
    if (base.isEmpty) {
      return '';
    }
    return base.endsWith('/') ? base : '$base/';
  }

  /// اطلاعات کاربر با شناسه داده شده؛ اگر پنل جواب ندهد `null`.
  Future<Account?> user(String uuid) async {
    final String key = AppConfig.panelApiKey.trim();
    if (uuid.isEmpty || key.isEmpty || _base.isEmpty) {
      return null;
    }
    final Uri uri = Uri.parse('${_base}api/v2/admin/user/$uuid/');
    try {
      final http.Response response = await _client.get(
        uri,
        headers: <String, String>{
          'Watashi-API-Key': key,
          'Accept': 'application/json',
          'User-Agent': 'Umbrella-Windows/${AppConfig.version}',
        },
      ).timeout(_timeout);
      if (response.statusCode != 200) {
        return null;
      }
      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return _parse(decoded);
    } on Exception {
      return null;
    }
  }

  Account _parse(Map<String, dynamic> json) {
    return Account(
      uuid: JsonX.text(json['uuid']),
      name: JsonX.text(json['name']),
      phone: JsonX.text(json['phone']),
      telegramId: JsonX.text(json['telegram_id']),
      comment: JsonX.text(json['comment']),
      enable: JsonX.boolean(
        json['enable'] ?? json['is_active'],
        fallback: true,
      ),
      isActive: JsonX.boolean(
        json['is_active'] ?? json['enable'],
        fallback: true,
      ),
      usageLimitGb: JsonX.number(json['usage_limit_GB'] ?? json['usage_limit_gb']),
      currentUsageGb:
          JsonX.number(json['current_usage_GB'] ?? json['current_usage_gb']),
      packageDays: JsonX.integer(json['package_days'] ?? json['packageDays']),
      startDate: _date(json['start_date'] ?? json['created_at']),
      expiryDate: _date(json['expire_date'] ?? json['expiry_date']),
      lastOnline: _date(json['last_online']),
      mode: JsonX.text(json['mode']),
    );
  }

  /// تاریخ پنل یا ثانیه یونیکس است یا رشته تاریخ؛ هر دو خوانده می شوند.
  static DateTime? _date(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      if (value <= 0) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(
        (value * 1000).round(),
        isUtc: true,
      ).toLocal();
    }
    final String text = value.toString().trim();
    if (text.isEmpty) {
      return null;
    }
    final int? epoch = int.tryParse(text);
    if (epoch != null) {
      return _date(epoch);
    }
    final DateTime? parsed = DateTime.tryParse(text.replaceFirst(' ', 'T'));
    if (parsed != null) {
      return parsed.toLocal();
    }
    return null;
  }
}
