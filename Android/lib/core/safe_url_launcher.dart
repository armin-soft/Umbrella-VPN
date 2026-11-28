import 'dart:async';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import '../platform/services.dart';
import 'malicious_link_guard.dart';

/// بازکننده ایمن نشانی های بیرونی (سپر لینک ۲۰۲۶):
/// هر لینک را پیش از ارسال به مرورگر از لایه های بازرسی `MaliciousLinkGuard`
/// عبور می دهد و برای پیوندهای کوتاه شده (bit.ly، tinyurl، yun.ir و ...) مسیر
/// تغییرجهت را پیش از باز شدن با درخواست HEAD بدون دنبال کردن خودکار بازرسی می کند
/// تا نشانی های فیشینگ، تروجانی یا تغییرجهت مخرب هرگز باز نشوند.
class SafeUrlLauncher {
  const SafeUrlLauncher._();

  static const int _maxRedirectHops = 4;

  /// قلاب سراسری برای ثبت رویداد مسدودی در سپر امنیتی و نمایش هشدار فوری.
  static void Function(MaliciousLinkMatch match)? onThreatBlocked;

  /// بازرسی کامل یک نشانی پیش از باز کردن آن (شامل بررسی ساختار + ردیابی امن کوتاه کننده ها).
  static Future<MaliciousLinkMatch?> inspectBeforeOpen(
    Uri uri, {
    Future<Uri?> Function(Uri current)? redirectResolver,
    bool inspectShortenerRedirects = true,
  }) async {
    final MaliciousLinkMatch? immediate =
        MaliciousLinkGuard.inspectUrl(uri.toString());
    if (immediate != null) {
      return immediate;
    }

    if (!inspectShortenerRedirects) {
      return null;
    }
    final String scheme = uri.scheme.toLowerCase();
    if ((scheme == 'http' || scheme == 'https') &&
        MaliciousLinkGuard.isShortenerHost(uri.host)) {
      return _inspectRedirectChain(
        uri,
        redirectResolver: redirectResolver,
      );
    }
    return null;
  }

  static Future<MaliciousLinkMatch?> _inspectRedirectChain(
    Uri startUri, {
    Future<Uri?> Function(Uri current)? redirectResolver,
  }) async {
    Uri current = startUri;
    final Set<String> visited = <String>{startUri.toString()};

    for (int hop = 0; hop < _maxRedirectHops; hop++) {
      final Uri? next = redirectResolver != null
          ? await redirectResolver(current)
          : await _peekNextLocationHead(current);
      if (next == null) {
        return null;
      }

      final MaliciousLinkMatch? nextHit =
          MaliciousLinkGuard.inspectUrl(next.toString());
      if (nextHit != null) {
        return MaliciousLinkMatch(
          key: 'link:shortener_redirect:${nextHit.key}',
          host: nextHit.host,
          target: startUri.toString(),
          title: 'لینک کوتاه شده منتهی به نشانی مخرب (${nextHit.host})',
          detail:
              'پیوند کوتاه شده کاربر را به «${nextHit.title}» هدایت می کرد و پیش از باز شدن مسدود شد.',
          severity: 'critical',
          riskScore: nextHit.riskScore < 92 ? 92 : nextHit.riskScore,
        );
      }

      final String nextStr = next.toString();
      if (!visited.add(nextStr)) {
        return null;
      }
      current = next;
      if (!MaliciousLinkGuard.isShortenerHost(current.host)) {
        return null;
      }
    }
    return null;
  }

  static Future<Uri?> _peekNextLocationHead(Uri uri) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 1400);
    try {
      for (final String method in const <String>['HEAD', 'GET']) {
        final HttpClientRequest req = await client
            .openUrl(method, uri)
            .timeout(const Duration(milliseconds: 1600));
        req.followRedirects = false;
        req.headers.set(
          HttpHeaders.userAgentHeader,
          'Mozilla/5.0 UmbrellaLinkGuard',
        );
        if (method == 'GET') {
          req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
        }
        final HttpClientResponse res =
            await req.close().timeout(const Duration(milliseconds: 1600));
        await res.drain<void>().catchError((_) {});

        if (res.statusCode >= 300 && res.statusCode < 400) {
          final String? loc = res.headers.value(HttpHeaders.locationHeader);
          if (loc != null && loc.trim().isNotEmpty) {
            final Uri? resolved = Uri.tryParse(loc.trim());
            if (resolved != null) {
              return resolved.hasScheme ? resolved : uri.resolveUri(resolved);
            }
          }
        }
        if (method == 'HEAD' &&
            res.statusCode != HttpStatus.methodNotAllowed &&
            res.statusCode != HttpStatus.notImplemented &&
            res.statusCode != HttpStatus.forbidden) {
          break;
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static void _notifyBlocked(MaliciousLinkMatch hit) {
    AppLogger.instance.add(
      'سپر امنیتی باز شدن لینک مشکوک را مسدود کرد: ${hit.target} (${hit.title})',
      level: 'warning',
    );
    try {
      onThreatBlocked?.call(hit);
    } catch (_) {}
  }

  static Future<bool> open(
    Uri uri, {
    LaunchMode mode = LaunchMode.externalApplication,
    Future<bool> Function(Uri uri, LaunchMode mode)? launcher,
    Future<Uri?> Function(Uri current)? redirectResolver,
    bool inspectShortenerRedirects = true,
  }) async {
    final MaliciousLinkMatch? hit = await inspectBeforeOpen(
      uri,
      redirectResolver: redirectResolver,
      inspectShortenerRedirects: inspectShortenerRedirects,
    );
    if (hit != null) {
      _notifyBlocked(hit);
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
    Future<Uri?> Function(Uri current)? redirectResolver,
    bool inspectShortenerRedirects = true,
  }) async {
    final MaliciousLinkMatch? rawHit = MaliciousLinkGuard.inspectUrl(rawUrl);
    if (rawHit != null) {
      _notifyBlocked(rawHit);
      return false;
    }
    final Uri? uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasScheme) {
      return false;
    }
    return open(
      uri,
      mode: mode,
      launcher: launcher,
      redirectResolver: redirectResolver,
      inspectShortenerRedirects: inspectShortenerRedirects,
    );
  }
}
