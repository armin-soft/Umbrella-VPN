import 'package:url_launcher/url_launcher.dart';

import '../platform/services.dart';
import 'malicious_link_guard.dart';

/// بازکننده ایمن نشانی های بیرونی: هر لینک را پیش از ارسال به مرورگر از
/// `MaliciousLinkGuard` عبور می دهد تا نشانی های فیشینگ، تروجانی یا تغییرجهت
/// مخرب هرگز باز نشوند.
class SafeUrlLauncher {
  const SafeUrlLauncher._();

  /// قلاب سراسری برای ثبت رویداد مسدودی در سپر امنیتی و نمایش هشدار فوری.
  static void Function(MaliciousLinkMatch match)? onThreatBlocked;

  static Future<bool> open(
    Uri uri, {
    LaunchMode mode = LaunchMode.externalApplication,
    Future<bool> Function(Uri uri, LaunchMode mode)? launcher,
  }) async {
    final MaliciousLinkMatch? hit =
        MaliciousLinkGuard.inspectUrl(uri.toString());
    if (hit != null) {
      AppLogger.instance.add(
        'سپر امنیتی باز شدن لینک مشکوک را مسدود کرد: ${hit.target} (${hit.title})',
        level: 'warning',
      );
      try {
        onThreatBlocked?.call(hit);
      } catch (_) {}
      return false;
    }
    try {
      final Future<bool> Function(Uri, LaunchMode) opener =
          launcher ?? ((Uri u, LaunchMode m) => launchUrl(u, mode: m));
      return await opener(uri, mode);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openString(
    String rawUrl, {
    LaunchMode mode = LaunchMode.externalApplication,
    Future<bool> Function(Uri uri, LaunchMode mode)? launcher,
  }) async {
    final MaliciousLinkMatch? rawHit = MaliciousLinkGuard.inspectUrl(rawUrl);
    if (rawHit != null) {
      AppLogger.instance.add(
        'سپر امنیتی باز شدن لینک مشکوک را مسدود کرد: ${rawHit.target} (${rawHit.title})',
        level: 'warning',
      );
      try {
        onThreatBlocked?.call(rawHit);
      } catch (_) {}
      return false;
    }
    final Uri? uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasScheme) {
      return false;
    }
    return open(uri, mode: mode, launcher: launcher);
  }
}
