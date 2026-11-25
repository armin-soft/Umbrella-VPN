import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/malicious_link_guard.dart';
import '../core/persian.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'umbrella_core.dart';

/// جزئیات صفحه یا دامنه مسدودشده برای نمایش در مرورگر و ثبت رویداد.
class BlockedHostDetails {
  const BlockedHostDetails({
    required this.domain,
    required this.category,
    required this.categoryLabel,
    required this.reason,
    required this.isSecurityThreat,
  });

  final String domain;
  final String category;
  final String categoryLabel;
  final String reason;
  final bool isSecurityThreat;
}

/// رویداد لحظه ای رهگیری یک اتصال مسدودشده توسط هسته یا سرور محلی آمبرلا.
class InterceptedBlockEvent {
  const InterceptedBlockEvent({
    required this.details,
    required this.port,
    required this.needsBrowserLaunch,
    required this.source,
  });

  final BlockedHostDetails details;
  final int port;
  final bool needsBrowserLaunch;
  final String source;
}

/// سرور محلی صفحه مسدودی و سپر کنترل محتوای آمبرلا.
///
/// دو نقش هم زمان دارد:
/// ۱. سرویس وب لوکال (`uiPort`) برای سرو صفحه هشدار آمبرلا، قلم وزیرمتن و لوگوهای
///    برند به مرورگر کاربر؛
/// ۲. خروجی پروکسی محلی (`proxyPort`) که هسته می تواند ترافیک مسدودشده را به آن
///    هدایت کند تا در HTTP مستقیماً کد 403 با صفحه آمبرلا برگردانده شود و در HTTPS
///    بلافاصله اتصال قطع و تب صفحه مسدودی آمبرلا باز شود.
class ContentBlockServer {
  ContentBlockServer({
    this.filterProvider,
    this.onIntercepted,
  });

  static const Map<int, ({String route, String asset})> _fontVariants =
      <int, ({String route, String asset})>{
    400: (
      route: '/assets/fonts/Vazirmatn-Regular.ttf',
      asset: 'assets/fonts/Vazirmatn-Regular.ttf',
    ),
    500: (
      route: '/assets/fonts/Vazirmatn-Medium.ttf',
      asset: 'assets/fonts/Vazirmatn-Medium.ttf',
    ),
    600: (
      route: '/assets/fonts/Vazirmatn-SemiBold.ttf',
      asset: 'assets/fonts/Vazirmatn-SemiBold.ttf',
    ),
    700: (
      route: '/assets/fonts/Vazirmatn-Bold.ttf',
      asset: 'assets/fonts/Vazirmatn-Bold.ttf',
    ),
    800: (
      route: '/assets/fonts/Vazirmatn-ExtraBold.ttf',
      asset: 'assets/fonts/Vazirmatn-ExtraBold.ttf',
    ),
    900: (
      route: '/assets/fonts/Vazirmatn-Black.ttf',
      asset: 'assets/fonts/Vazirmatn-Black.ttf',
    ),
  };

  final FilterSettings? Function()? filterProvider;
  final void Function(InterceptedBlockEvent event)? onIntercepted;

  HttpServer? _uiServer;
  ServerSocket? _proxyServer;
  Future<void>? _startInFlight;
  bool _stopped = false;

  Uint8List? _logoPng;
  Uint8List? _shieldPng;
  Uint8List? _alertPng;
  final Map<int, Uint8List> _fontBytes = <int, Uint8List>{};

  int get uiPort => _uiServer?.port ?? 0;
  int get proxyPort => _proxyServer?.port ?? 0;
  bool get isRunning => _uiServer != null && _proxyServer != null && !_stopped;

  /// شروع ایمن و Idempotent سرور محلی روی `127.0.0.1`.
  Future<void> start({int uiPort = 0, int proxyPort = 0}) {
    if (isRunning) {
      return Future<void>.value();
    }
    return _startInFlight ??= _startInternal(
      uiPort: uiPort,
      proxyPort: proxyPort,
    );
  }

  Future<void> _startInternal({
    required int uiPort,
    required int proxyPort,
  }) async {
    _stopped = false;
    await _loadBrandAssets();
    try {
      final HttpServer ui =
          await HttpServer.bind(InternetAddress.loopbackIPv4, uiPort);
      final ServerSocket proxy =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, proxyPort);
      if (_stopped) {
        await ui.close(force: true);
        await proxy.close();
        return;
      }
      _uiServer = ui;
      _proxyServer = proxy;
      ui.listen(_handleUiRequest, onError: (_) {});
      proxy.listen(_handleProxySocket, onError: (_) {});
    } catch (_) {
      await stop();
      rethrow;
    } finally {
      _startInFlight = null;
    }
  }

  Future<void> stop() async {
    _stopped = true;
    final HttpServer? ui = _uiServer;
    final ServerSocket? proxy = _proxyServer;
    _uiServer = null;
    _proxyServer = null;
    _startInFlight = null;
    if (ui != null) {
      try {
        await ui.close(force: true);
      } catch (_) {}
    }
    if (proxy != null) {
      try {
        await proxy.close();
      } catch (_) {}
    }
  }

  Future<void> _loadBrandAssets() async {
    Future<Uint8List?> readAsset(String path) async {
      try {
        final ByteData data = await rootBundle.load(path);
        if (data.lengthInBytes > 0) {
          return data.buffer.asUint8List();
        }
      } catch (_) {}
      try {
        final File diskFile = File(path);
        if (await diskFile.exists()) {
          final Uint8List bytes = await diskFile.readAsBytes();
          if (bytes.isNotEmpty) {
            return bytes;
          }
        }
      } catch (_) {}
      return null;
    }

    _logoPng ??= await readAsset(BrandAssets.logo);
    _shieldPng ??= await readAsset(BrandAssets.securityShield);
    _alertPng ??= await readAsset(BrandAssets.securityAlert);
    for (final MapEntry<int, ({String route, String asset})> entry
        in _fontVariants.entries) {
      if (_fontBytes.containsKey(entry.key)) continue;
      final Uint8List? loaded = await readAsset(entry.value.asset);
      if (loaded != null && loaded.isNotEmpty) {
        _fontBytes[entry.key] = loaded;
      }
    }
  }

  /// ساخت نشانی کامل صفحه مسدودی مرورگر روی سرور لوکال.
  Uri buildBlockedPageUri(
    String host, {
    String? categoryHint,
    FilterSettings? filter,
  }) {
    final BlockedHostDetails details = classifyBlockedHost(
      host,
      filter: filter ?? filterProvider?.call(),
      categoryHint: categoryHint,
    );
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: uiPort > 0 ? uiPort : 80,
      path: '/blocked',
      queryParameters: <String, String>{
        if (details.domain.isNotEmpty) 'domain': details.domain,
        'category': details.category,
        'reason': details.reason,
      },
    );
  }

  /// طبقه بندی دقیق دامنه مسدودشده بر اساس سپر امنیتی و تنظیمات کنترل محتوا.
  static BlockedHostDetails classifyBlockedHost(
    String rawHost, {
    FilterSettings? filter,
    String? categoryHint,
  }) {
    final String cleanHost = sanitizeHost(rawHost);
    final MaliciousLinkMatch? threat = MaliciousLinkGuard.inspectHost(cleanHost);
    if (threat != null) {
      return BlockedHostDetails(
        domain: cleanHost.isEmpty ? threat.host : cleanHost,
        category: 'malicious_link',
        categoryLabel: 'لینک مخرب، فیشینگ یا تروجانی',
        reason: threat.detail,
        isSecurityThreat: true,
      );
    }

    String? category = UmbrellaCore.matchesContentFilterCategory(
      filter,
      cleanHost,
    );
    category ??= categoryHint?.trim().toLowerCase();
    if (category == null || category.isEmpty) {
      final List<String> primary = (filter?.activeBotCategories ?? const <String>[])
          .where((String c) => c != 'ads')
          .toList(growable: false);
      if (primary.length == 1) {
        category = primary.first;
      } else if (filter != null &&
          filter.normalizedCustomDomains.isNotEmpty &&
          primary.isEmpty) {
        category = 'custom';
      } else {
        category = 'content_control';
      }
    }

    return switch (category) {
      'malicious_link' => BlockedHostDetails(
          domain: cleanHost,
          category: 'malicious_link',
          categoryLabel: 'لینک مخرب، فیشینگ یا تروجانی',
          reason:
              'دسترسی به این نشانی برای جلوگیری از دانلود بدافزار یا سرقت اطلاعات توسط سپر امنیتی آمبرلا مسدود شد.',
          isSecurityThreat: true,
        ),
      'adult' => BlockedHostDetails(
          domain: cleanHost,
          category: 'adult',
          categoryLabel: 'محتوای بزرگسالان و غیراخلاقی',
          reason:
              'دسترسی به این وب سایت بر اساس فیلتر محتوای بزرگسالان در کنترل محتوای آمبرلا مسدود شده است.',
          isSecurityThreat: false,
        ),
      'gambling' => BlockedHostDetails(
          domain: cleanHost,
          category: 'gambling',
          categoryLabel: 'سایت های شرط بندی و قمار',
          reason:
              'دسترسی به این وب سایت بر اساس فیلتر سایت های شرط بندی و قمار در کنترل محتوای آمبرلا مسدود شده است.',
          isSecurityThreat: false,
        ),
      'custom' => BlockedHostDetails(
          domain: cleanHost,
          category: 'custom',
          categoryLabel: 'فهرست مسدودی سفارشی',
          reason:
              'این دامنه در فهرست دامنه های مسدودشده سفارشی کنترل محتوای آمبرلا قرار دارد.',
          isSecurityThreat: false,
        ),
      'ads' => BlockedHostDetails(
          domain: cleanHost,
          category: 'ads',
          categoryLabel: 'تبلیغات و ردیاب های مزاحم',
          reason:
              'این نشانی توسط فیلتر حذف تبلیغات کنترل محتوای آمبرلا مسدود شده است.',
          isSecurityThreat: false,
        ),
      _ => BlockedHostDetails(
          domain: cleanHost,
          category: 'content_control',
          categoryLabel: 'سپر کنترل محتوای آمبرلا',
          reason:
              'سپر کنترل محتوای فیلترشکن آمبرلا فعال است و دسترسی به این صفحه طبق قوانین فعال مسدود شد.',
          isSecurityThreat: false,
        ),
    };
  }

  /// پاکسازی نام میزبان و حذف کاراکترهای غیرمجاز.
  static String sanitizeHost(String raw) {
    String h = raw.trim().toLowerCase();
    if (h.startsWith('http://')) {
      h = h.substring(7);
    } else if (h.startsWith('https://')) {
      h = h.substring(8);
    }
    final int slash = h.indexOf('/');
    if (slash >= 0) h = h.substring(0, slash);
    final int query = h.indexOf('?');
    if (query >= 0) h = h.substring(0, query);
    if (h.startsWith('[') && h.contains(']')) {
      h = h.substring(1, h.indexOf(']'));
    } else {
      h = h.replaceFirst(RegExp(r':\d+$'), '');
    }
    h = h.replaceAll(RegExp(r'^\.+|\.+$'), '');
    if (h.length > 180) {
      h = h.substring(0, 180);
    }
    return h;
  }

  Future<void> _handleUiRequest(HttpRequest request) async {
    final HttpResponse res = request.response;
    res.headers.set('Access-Control-Allow-Origin', '*');
    res.headers.set('Access-Control-Allow-Private-Network', 'true');
    res.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    res.headers.set('Access-Control-Allow-Headers', '*');
    res.headers.set('X-Content-Type-Options', 'nosniff');

    if (request.method.toUpperCase() == 'OPTIONS') {
      res.statusCode = HttpStatus.noContent;
      await res.close();
      return;
    }

    final String path = request.uri.path;
    if (path == '/health') {
      res.statusCode = HttpStatus.ok;
      res.headers.contentType = ContentType.json;
      res.write('{"ok":true,"uiPort":$uiPort,"proxyPort":$proxyPort}');
      await res.close();
      return;
    }

    for (final MapEntry<int, ({String route, String asset})> entry
        in _fontVariants.entries) {
      if (path == entry.value.route) {
        final Uint8List? bytes = _fontBytes[entry.key];
        if (bytes != null && bytes.isNotEmpty) {
          res.statusCode = HttpStatus.ok;
          res.headers.contentType = ContentType('font', 'ttf');
          res.headers.set(HttpHeaders.cacheControlHeader, 'public, max-age=86400');
          if (request.method.toUpperCase() != 'HEAD') {
            res.add(bytes);
          }
          await res.close();
          return;
        }
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }
    }

    if (path == '/assets/logo.png' || path == '/favicon.ico') {
      await _writeImageOrSvgFallback(res, _logoPng, isAlert: false, isLogo: true);
      return;
    }
    if (path == '/assets/shield.png') {
      await _writeImageOrSvgFallback(res, _shieldPng, isAlert: false);
      return;
    }
    if (path == '/assets/alert.png') {
      await _writeImageOrSvgFallback(res, _alertPng, isAlert: true);
      return;
    }

    final String rawDomain = request.uri.queryParameters['domain'] ?? '';
    final String? rawCategory = request.uri.queryParameters['category'];
    final String? rawReason = request.uri.queryParameters['reason'];

    final BlockedHostDetails base = classifyBlockedHost(
      rawDomain,
      filter: filterProvider?.call(),
      categoryHint: rawCategory,
    );
    final BlockedHostDetails details =
        (rawReason != null && rawReason.trim().isNotEmpty && !base.isSecurityThreat)
            ? BlockedHostDetails(
                domain: base.domain,
                category: base.category,
                categoryLabel: base.categoryLabel,
                reason: rawReason.trim(),
                isSecurityThreat: base.isSecurityThreat,
              )
            : base;

    final String html = renderBlockedPageHtml(
      details: details,
      assetBaseUrl: 'http://127.0.0.1:$uiPort',
    );
    res.statusCode = HttpStatus.ok;
    res.headers.contentType = ContentType.html;
    res.headers.set(HttpHeaders.cacheControlHeader, 'no-store, max-age=0');
    res.headers.set('X-Umbrella-Content-Control', 'blocked');
    res.write(html);
    await res.close();
  }

  Future<void> _writeImageOrSvgFallback(
    HttpResponse res,
    Uint8List? pngBytes, {
    required bool isAlert,
    bool isLogo = false,
  }) async {
    res.statusCode = HttpStatus.ok;
    res.headers.set(HttpHeaders.cacheControlHeader, 'public, max-age=86400');
    if (pngBytes != null && pngBytes.isNotEmpty) {
      res.headers.contentType = ContentType('image', 'png');
      res.add(pngBytes);
      await res.close();
      return;
    }
    res.headers.contentType = ContentType('image', 'svg+xml');
    res.write(_fallbackBrandSvg(isAlert: isAlert, isLogo: isLogo));
    await res.close();
  }

  Future<void> _handleProxySocket(Socket socket) async {
    try {
      final StreamIterator<Uint8List> iterator = StreamIterator<Uint8List>(socket);
      final List<int> buffer = <int>[];
      int headerEnd = -1;

      while (headerEnd < 0 && buffer.length < 16384) {
        final bool hasNext = await iterator.moveNext().timeout(
              const Duration(seconds: 6),
              onTimeout: () => false,
            );
        if (!hasNext) break;
        buffer.addAll(iterator.current);
        headerEnd = _indexOfHeaderEnd(buffer);
      }

      if (buffer.isEmpty) {
        await iterator.cancel();
        socket.destroy();
        return;
      }

      final int endIdx = headerEnd > 0 ? headerEnd : buffer.length;
      final String headerText = utf8.decode(
        buffer.sublist(0, endIdx),
        allowMalformed: true,
      );
      final List<String> lines = headerText.split(RegExp(r'\r?\n'));
      final String requestLine = lines.isNotEmpty ? lines.first.trim() : '';
      final List<String> parts = requestLine.split(RegExp(r'\s+'));
      final String method = parts.isNotEmpty ? parts.first.toUpperCase() : '';
      final String target = parts.length > 1 ? parts[1] : '';

      if (method == 'CONNECT') {
        final ({String host, int port}) parsed = _parseHostPort(target, defaultPort: 443);
        if (parsed.port == 80) {
          socket.add(
            utf8.encode('HTTP/1.1 200 Connection Established\r\n\r\n'),
          );
          await socket.flush().timeout(const Duration(seconds: 3));

          final List<int> innerBuf = <int>[];
          if (headerEnd > 0 && buffer.length > headerEnd) {
            innerBuf.addAll(buffer.sublist(headerEnd));
          }
          int innerEnd = _indexOfHeaderEnd(innerBuf);
          while (innerEnd < 0 && innerBuf.length < 8192) {
            final bool hasInner = await iterator.moveNext().timeout(
                  const Duration(seconds: 3),
                  onTimeout: () => false,
                );
            if (!hasInner) break;
            innerBuf.addAll(iterator.current);
            innerEnd = _indexOfHeaderEnd(innerBuf);
          }

          String effectiveHost = parsed.host;
          if (innerBuf.isNotEmpty) {
            final String innerText = utf8.decode(
              innerBuf.sublist(0, innerEnd > 0 ? innerEnd : innerBuf.length),
              allowMalformed: true,
            );
            final String? hostHeader = _extractHeader(innerText, 'host');
            if (hostHeader != null && hostHeader.isNotEmpty) {
              effectiveHost = sanitizeHost(hostHeader);
            }
          }

          final BlockedHostDetails details = classifyBlockedHost(
            effectiveHost,
            filter: filterProvider?.call(),
          );
          await _writeHttp403Page(socket, details);
          _emitIntercepted(
            details: details,
            port: 80,
            needsBrowserLaunch: false,
            source: 'http-tunnel',
          );
          await iterator.cancel();
          return;
        }

        socket.add(
          utf8.encode(
            'HTTP/1.1 403 Forbidden\r\n'
            'Connection: close\r\n'
            'X-Umbrella-Content-Control: blocked\r\n\r\n',
          ),
        );
        await socket.flush().timeout(const Duration(seconds: 2));
        await socket.close();
        await iterator.cancel();

        final BlockedHostDetails details = classifyBlockedHost(
          parsed.host,
          filter: filterProvider?.call(),
        );
        _emitIntercepted(
          details: details,
          port: parsed.port,
          needsBrowserLaunch: true,
          source: 'https-connect',
        );
        return;
      }

      String host = _extractHeader(headerText, 'host') ?? '';
      if (host.isEmpty && target.isNotEmpty) {
        final Uri? parsedUri = Uri.tryParse(target);
        if (parsedUri != null && parsedUri.host.isNotEmpty) {
          host = parsedUri.host;
        }
      }
      final BlockedHostDetails details = classifyBlockedHost(
        host,
        filter: filterProvider?.call(),
      );
      await _writeHttp403Page(socket, details);
      _emitIntercepted(
        details: details,
        port: 80,
        needsBrowserLaunch: false,
        source: 'http-proxy',
      );
      await iterator.cancel();
    } catch (_) {
      try {
        socket.destroy();
      } catch (_) {}
    }
  }

  void _emitIntercepted({
    required BlockedHostDetails details,
    required int port,
    required bool needsBrowserLaunch,
    required String source,
  }) {
    if (details.domain.isEmpty ||
        details.domain == '127.0.0.1' ||
        details.domain == 'localhost') {
      return;
    }
    onIntercepted?.call(
      InterceptedBlockEvent(
        details: details,
        port: port,
        needsBrowserLaunch: needsBrowserLaunch,
        source: source,
      ),
    );
  }

  Future<void> _writeHttp403Page(
    Socket socket,
    BlockedHostDetails details,
  ) async {
    final String assetBase = uiPort > 0 ? 'http://127.0.0.1:$uiPort' : '';
    final String html = renderBlockedPageHtml(
      details: details,
      assetBaseUrl: assetBase,
      inlineFonts: _fontBytes.isNotEmpty ? _fontBytes : null,
      inlineLogoBytes: _logoPng,
      inlineBadgeBytes: details.isSecurityThreat ? _alertPng : _shieldPng,
    );
    final List<int> bodyBytes = utf8.encode(html);
    final String headers =
        'HTTP/1.1 403 Forbidden\r\n'
        'Content-Type: text/html; charset=utf-8\r\n'
        'Content-Length: ${bodyBytes.length}\r\n'
        'Cache-Control: no-store, max-age=0\r\n'
        'Connection: close\r\n'
        'X-Umbrella-Content-Control: blocked\r\n\r\n';
    socket.add(utf8.encode(headers));
    socket.add(bodyBytes);
    await socket.flush().timeout(const Duration(seconds: 3));
    await socket.close();
  }

  static int _indexOfHeaderEnd(List<int> bytes) {
    for (int i = 0; i <= bytes.length - 4; i++) {
      if (bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        return i + 4;
      }
    }
    for (int i = 0; i <= bytes.length - 2; i++) {
      if (bytes[i] == 10 && bytes[i + 1] == 10) {
        return i + 2;
      }
    }
    return -1;
  }

  static String? _extractHeader(String headersText, String targetName) {
    final String lowerTarget = targetName.toLowerCase();
    for (final String line in headersText.split(RegExp(r'\r?\n'))) {
      final int colon = line.indexOf(':');
      if (colon <= 0) continue;
      final String name = line.substring(0, colon).trim().toLowerCase();
      if (name == lowerTarget) {
        return line.substring(colon + 1).trim();
      }
    }
    return null;
  }

  static ({String host, int port}) _parseHostPort(
    String target, {
    required int defaultPort,
  }) {
    final String clean = target.trim();
    if (clean.startsWith('[')) {
      final int endBracket = clean.indexOf(']');
      if (endBracket > 0) {
        final String host = clean.substring(1, endBracket);
        final int colon = clean.indexOf(':', endBracket);
        final int port = colon > 0
            ? int.tryParse(clean.substring(colon + 1)) ?? defaultPort
            : defaultPort;
        return (host: sanitizeHost(host), port: port);
      }
    }
    final int lastColon = clean.lastIndexOf(':');
    if (lastColon > 0) {
      final int? port = int.tryParse(clean.substring(lastColon + 1));
      if (port != null && port > 0 && port <= 65535) {
        return (
          host: sanitizeHost(clean.substring(0, lastColon)),
          port: port,
        );
      }
    }
    return (host: sanitizeHost(clean), port: defaultPort);
  }

  /// رندر صفحه HTML5/CSS3 آمبرلا با قلم وزیرمتن، لوگو و پالت رنگ رسمی [UmbrellaColors].
  static String renderBlockedPageHtml({
    required BlockedHostDetails details,
    String assetBaseUrl = '',
    DateTime? timestamp,
    Map<int, Uint8List>? inlineFonts,
    Uint8List? inlineLogoBytes,
    Uint8List? inlineBadgeBytes,
  }) {
    const HtmlEscape esc = HtmlEscape(HtmlEscapeMode.element);
    const HtmlEscape escAttr = HtmlEscape(HtmlEscapeMode.attribute);

    final bool alert = details.isSecurityThreat;
    final String accent = _hexColor(
      alert ? UmbrellaColors.dark.danger : UmbrellaColors.dark.primary,
    );
    final String bg = _hexColor(UmbrellaColors.dark.background);
    final String bgAlt = _hexColor(UmbrellaColors.dark.backgroundAlt);
    final String surface = _hexColor(UmbrellaColors.dark.surface);
    final String surfaceHigh = _hexColor(UmbrellaColors.dark.surfaceHigh);
    final String border = _hexColor(UmbrellaColors.dark.border);
    final String textPrimary = _hexColor(UmbrellaColors.dark.textPrimary);
    final String textSecondary = _hexColor(UmbrellaColors.dark.textSecondary);
    final String primary = _hexColor(UmbrellaColors.dark.primary);
    final String primarySoft = _hexColor(UmbrellaColors.dark.primarySoft);
    final String primaryDeep = _hexColor(UmbrellaColors.dark.primaryDeep);
    final String success = _hexColor(UmbrellaColors.dark.success);

    final String safeDomain =
        esc.convert(details.domain.isEmpty ? 'صفحه محدودشده' : details.domain);
    final String safeDomainAttr = escAttr.convert(details.domain);
    final String safeCategory = esc.convert(details.categoryLabel);
    final String safeReason = esc.convert(details.reason);

    final String badgeText = alert
        ? 'سپر امنیتی آمبرلا: تهدید مخرب مسدود شد'
        : 'سپر کنترل محتوای آمبرلا فعال است';
    final String headline = alert
        ? 'دسترسی به لینک مخرب به صورت خودکار مسدود شد'
        : 'دسترسی به این صفحه توسط کنترل محتوای آمبرلا مسدود شد';
    final String subline = alert
        ? 'سیستم حفاظت خودکار فیلترشکن آمبرلا پیش از باز شدن این نشانی، الگوی تروجانی یا فیشینگ را شناسایی و اتصال را در هسته قطع کرد.'
        : 'سپر کنترل محتوای فیلترشکن آمبرلا فعال است و بر اساس قوانین تنظیم شده، اجازه بارگذاری این نشانی را نداد.';

    final DateTime now = (timestamp ?? DateTime.now()).toLocal();
    final String hh = now.hour.toString().padLeft(2, '0');
    final String mm = now.minute.toString().padLeft(2, '0');
    final String ss = now.second.toString().padLeft(2, '0');
    final String timeFormatted = Fa.num('$hh:$mm:$ss');

    final StringBuffer fontFaceCss = StringBuffer();
    if (inlineFonts != null && inlineFonts.isNotEmpty) {
      for (final int weight in _fontVariants.keys) {
        final Uint8List? bytes = inlineFonts[weight];
        if (bytes == null || bytes.isEmpty) continue;
        final String b64 = base64Encode(bytes);
        fontFaceCss.writeln('''
    @font-face {
      font-family: "Vazirmatn";
      src: url("data:font/ttf;base64,$b64") format("truetype");
      font-weight: $weight;
      font-style: normal;
      font-display: block;
    }''');
      }
    } else if (assetBaseUrl.isNotEmpty) {
      for (final MapEntry<int, ({String route, String asset})> entry
          in _fontVariants.entries) {
        final String fontUrl =
            escAttr.convert('$assetBaseUrl${entry.value.route}');
        fontFaceCss.writeln('''
    @font-face {
      font-family: "Vazirmatn";
      src: url("$fontUrl") format("truetype");
      font-weight: ${entry.key};
      font-style: normal;
      font-display: block;
    }''');
      }
    }

    final String logoSrc =
        (inlineLogoBytes != null && inlineLogoBytes.isNotEmpty)
            ? 'data:image/png;base64,${base64Encode(inlineLogoBytes)}'
            : (assetBaseUrl.isNotEmpty
                ? escAttr.convert('$assetBaseUrl/assets/logo.png')
                : '');
    final String shieldSrc =
        (inlineBadgeBytes != null && inlineBadgeBytes.isNotEmpty)
            ? 'data:image/png;base64,${base64Encode(inlineBadgeBytes)}'
            : (assetBaseUrl.isNotEmpty
                ? escAttr.convert(
                    '$assetBaseUrl/assets/${alert ? 'alert.png' : 'shield.png'}',
                  )
                : '');

    final String logoImg = logoSrc.isNotEmpty
        ? '<img class="brand-logo" src="$logoSrc" alt="فیلترشکن آمبرلا" onerror="this.style.display=\'none\';this.nextElementSibling.style.display=\'flex\';">'
        : '';
    final String shieldImg = shieldSrc.isNotEmpty
        ? '<img class="hero-shield" src="$shieldSrc" alt="${alert ? 'هشدار امنیتی آمبرلا' : 'سپر امنیتی آمبرلا'}" onerror="this.style.display=\'none\';this.nextElementSibling.style.display=\'flex\';">'
        : '';

    final String fallbackLogoSvg = _fallbackBrandSvg(isAlert: false, isLogo: true);
    final String fallbackHeroSvg = _fallbackBrandSvg(isAlert: alert, isLogo: false);

    return '''<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="theme-color" content="$bg">
  <title>فیلترشکن آمبرلا — ${esc.convert(badgeText)}</title>
  <style>
${fontFaceCss.toString()}    :root {
      --bg: $bg;
      --bg-alt: $bgAlt;
      --surface: $surface;
      --surface-high: $surfaceHigh;
      --border: $border;
      --text-primary: $textPrimary;
      --text-secondary: $textSecondary;
      --primary: $primary;
      --primary-soft: $primarySoft;
      --primary-deep: $primaryDeep;
      --accent: $accent;
      --success: $success;
    }
    * { box-sizing: border-box; }
    html, body {
      margin: 0;
      padding: 0;
      min-height: 100%;
      background-color: var(--bg);
      color: var(--text-primary);
      font-family: "Vazirmatn", Tahoma, system-ui, -apple-system, sans-serif;
      -webkit-font-smoothing: antialiased;
    }
    body {
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 28px 18px;
      position: relative;
      overflow-x: hidden;
      background-image:
        radial-gradient(circle at 18% 12%, rgba(225, 29, 46, 0.18), transparent 42%),
        radial-gradient(circle at 86% 88%, rgba(142, 14, 27, 0.22), transparent 46%),
        linear-gradient(160deg, var(--bg) 0%, var(--bg-alt) 100%);
    }
    .grid-overlay {
      position: fixed;
      inset: 0;
      pointer-events: none;
      background-image:
        linear-gradient(to right, rgba(255,255,255,0.025) 1px, transparent 1px),
        linear-gradient(to bottom, rgba(255,255,255,0.025) 1px, transparent 1px);
      background-size: 36px 36px;
      mask-image: radial-gradient(circle at center, rgba(0,0,0,0.85), transparent 80%);
    }
    .shell {
      position: relative;
      z-index: 1;
      width: 100%;
      max-width: 720px;
      background: linear-gradient(180deg, rgba(18, 20, 27, 0.94), rgba(12, 14, 19, 0.97));
      border: 1px solid var(--border);
      border-radius: 28px;
      padding: 28px;
      box-shadow:
        0 30px 80px rgba(0, 0, 0, 0.68),
        0 0 0 1px rgba(255, 255, 255, 0.03) inset,
        0 0 60px rgba(225, 29, 46, 0.10);
      backdrop-filter: blur(20px);
    }
    .topbar {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      justify-content: space-between;
      gap: 14px;
      padding-bottom: 20px;
      border-bottom: 1px solid var(--border);
    }
    .brand {
      display: flex;
      align-items: center;
      gap: 12px;
    }
    .brand-mark {
      width: 46px;
      height: 46px;
      border-radius: 14px;
      background: linear-gradient(135deg, var(--primary-soft), var(--surface-high));
      border: 1px solid rgba(225, 29, 46, 0.36);
      display: flex;
      align-items: center;
      justify-content: center;
      overflow: hidden;
      flex-shrink: 0;
    }
    .brand-logo {
      width: 100%;
      height: 100%;
      object-fit: cover;
    }
    .brand-fallback {
      width: 100%;
      height: 100%;
      display: ${logoSrc.isNotEmpty ? 'none' : 'flex'};
      align-items: center;
      justify-content: center;
      padding: 7px;
    }
    .brand-title {
      font-size: 16px;
      font-weight: 800;
      letter-spacing: 0.2px;
      color: var(--text-primary);
    }
    .brand-sub {
      font-size: 12px;
      color: var(--text-secondary);
      margin-top: 2px;
    }
    .status-pill {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 8px 14px;
      border-radius: 999px;
      font-size: 12px;
      font-weight: 700;
      background: ${alert ? 'rgba(255, 107, 107, 0.13)' : 'rgba(225, 29, 46, 0.14)'};
      border: 1px solid ${alert ? 'rgba(255, 107, 107, 0.42)' : 'rgba(225, 29, 46, 0.42)'};
      color: var(--text-primary);
    }
    .pulse-dot {
      width: 9px;
      height: 9px;
      border-radius: 50%;
      background: ${alert ? 'var(--accent)' : 'var(--success)'};
      box-shadow: 0 0 0 0 ${alert ? 'rgba(255, 107, 107, 0.65)' : 'rgba(34, 197, 94, 0.65)'};
      animation: pulse 2.2s infinite;
    }
    @keyframes pulse {
      0% { box-shadow: 0 0 0 0 ${alert ? 'rgba(255, 107, 107, 0.55)' : 'rgba(34, 197, 94, 0.55)'}; }
      70% { box-shadow: 0 0 0 10px rgba(0, 0, 0, 0); }
      100% { box-shadow: 0 0 0 0 rgba(0, 0, 0, 0); }
    }
    .hero {
      display: flex;
      flex-direction: column;
      align-items: center;
      text-align: center;
      padding: 28px 10px 22px;
    }
    .hero-ring {
      position: relative;
      width: 112px;
      height: 112px;
      border-radius: 50%;
      padding: 6px;
      background: radial-gradient(circle, rgba(225, 29, 46, 0.30), rgba(18, 20, 27, 0.9));
      border: 1px solid rgba(225, 29, 46, 0.42);
      box-shadow: 0 12px 34px rgba(225, 29, 46, 0.24);
      display: flex;
      align-items: center;
      justify-content: center;
      margin-bottom: 20px;
      overflow: hidden;
    }
    .hero-shield {
      width: 100%;
      height: 100%;
      border-radius: 50%;
      object-fit: cover;
    }
    .hero-fallback {
      width: 100%;
      height: 100%;
      display: ${shieldSrc.isNotEmpty ? 'none' : 'flex'};
      align-items: center;
      justify-content: center;
      padding: 16px;
    }
    h1 {
      margin: 0 0 10px;
      font-size: 22px;
      line-height: 1.5;
      font-weight: 800;
      color: var(--text-primary);
    }
    .subline {
      margin: 0;
      max-width: 560px;
      font-size: 14px;
      line-height: 1.85;
      color: var(--text-secondary);
    }
    .cards {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 12px;
      margin-top: 22px;
    }
    @media (max-width: 580px) {
      .shell { padding: 20px; border-radius: 22px; }
      .cards { grid-template-columns: 1fr; }
      h1 { font-size: 19px; }
    }
    .card {
      background: var(--surface-high);
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 14px 16px;
    }
    .card-full {
      grid-column: 1 / -1;
    }
    .card-label {
      font-size: 11.5px;
      color: var(--text-secondary);
      margin-bottom: 6px;
      font-weight: 600;
    }
    .card-value {
      font-size: 14px;
      font-weight: 700;
      color: var(--text-primary);
      line-height: 1.65;
      word-break: break-word;
    }
    .domain-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 10px;
      flex-wrap: wrap;
    }
    .domain-chip {
      direction: ltr;
      display: inline-block;
      font-family: ui-monospace, SFMono-Regular, Consolas, monospace;
      font-size: 14px;
      font-weight: 700;
      color: #FFD2D6;
      background: var(--primary-soft);
      border: 1px solid rgba(225, 29, 46, 0.35);
      padding: 5px 11px;
      border-radius: 10px;
      word-break: break-all;
    }
    .actions {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      justify-content: center;
      gap: 12px;
      margin-top: 24px;
    }
    .btn {
      appearance: none;
      border: 0;
      border-radius: 14px;
      padding: 12px 20px;
      font-family: inherit;
      font-size: 13.5px;
      font-weight: 700;
      cursor: pointer;
      transition: transform 0.16s ease, box-shadow 0.16s ease, background 0.16s ease;
    }
    .btn:active { transform: translateY(1px); }
    .btn-primary {
      background: linear-gradient(135deg, var(--primary), var(--primary-deep));
      color: #ffffff;
      box-shadow: 0 10px 24px rgba(225, 29, 46, 0.30);
    }
    .btn-primary:hover {
      box-shadow: 0 14px 28px rgba(225, 29, 46, 0.42);
    }
    .btn-secondary {
      background: var(--surface-high);
      color: var(--text-primary);
      border: 1px solid var(--border);
    }
    .btn-secondary:hover {
      border-color: rgba(225, 29, 46, 0.45);
    }
    .footer-note {
      margin-top: 20px;
      padding-top: 16px;
      border-top: 1px solid var(--border);
      text-align: center;
      font-size: 12px;
      line-height: 1.8;
      color: var(--text-secondary);
    }
  </style>
</head>
<body>
  <div class="grid-overlay"></div>
  <main class="shell">
    <header class="topbar">
      <div class="brand">
        <div class="brand-mark">
          $logoImg
          <div class="brand-fallback">$fallbackLogoSvg</div>
        </div>
        <div>
          <div class="brand-title">فیلترشکن آمبرلا</div>
          <div class="brand-sub">لایه هوشمند حفاظت و کنترل محتوا</div>
        </div>
      </div>
      <div class="status-pill">
        <span class="pulse-dot"></span>
        <span>${esc.convert(badgeText)}</span>
      </div>
    </header>

    <section class="hero">
      <div class="hero-ring">
        $shieldImg
        <div class="hero-fallback">$fallbackHeroSvg</div>
      </div>
      <h1>${esc.convert(headline)}</h1>
      <p class="subline">${esc.convert(subline)}</p>
    </section>

    <section class="cards">
      <div class="card card-full">
        <div class="card-label">نشانی یا دامنه مسدودشده</div>
        <div class="domain-row">
          <span class="domain-chip" id="blocked-domain">$safeDomain</span>
          <button type="button" class="btn btn-secondary" style="padding:7px 12px;font-size:12px;" onclick="copyDomain()">کپی دامنه</button>
        </div>
      </div>
      <div class="card">
        <div class="card-label">دسته و نوع فیلتر</div>
        <div class="card-value">$safeCategory</div>
      </div>
      <div class="card">
        <div class="card-label">وضعیت محافظت و زمان ثبت</div>
        <div class="card-value">مسدودی پیش از بارگذاری | <span dir="ltr">$timeFormatted</span></div>
      </div>
      <div class="card card-full">
        <div class="card-label">توضیح و علت مسدودسازی</div>
        <div class="card-value" style="font-weight:500;color:var(--text-secondary);">$safeReason</div>
      </div>
    </section>

    <div class="actions">
      <button type="button" class="btn btn-primary" onclick="goSafeBack()">بازگشت به صفحه قبل</button>
      <button type="button" class="btn btn-secondary" onclick="window.close()">بستن این برگه</button>
    </div>

    <footer class="footer-note">
      در صورت نیاز می توانید قوانین دسته بندی ها و دامنه های سفارشی را از بخش «کنترل محتوا» داخل برنامه فیلترشکن آمبرلا یا ربات تلگرام مدیریت کنید.
    </footer>
  </main>

  <script>
    function goSafeBack() {
      if (window.history.length > 1) {
        window.history.back();
      } else {
        window.close();
      }
    }
    function copyDomain() {
      var text = "$safeDomainAttr";
      if (!text) return;
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text);
      }
    }
  </script>
</body>
</html>''';
  }

  static String _hexColor(Color color) {
    final int rgb = color.toARGB32() & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  static String _fallbackBrandSvg({
    required bool isAlert,
    required bool isLogo,
  }) {
    final String stroke = isAlert ? '#FF6B6B' : '#E11D2E';
    final String fill = isAlert ? '#3A1017' : '#E11D2E';
    if (isLogo) {
      return '<svg viewBox="0 0 64 64" width="32" height="32" xmlns="http://www.w3.org/2000/svg">'
          '<path d="M32 8C16.5 8 5 19.2 5 33h54C59 19.2 47.5 8 32 8z" fill="$fill"/>'
          '<path d="M32 33v16c0 3.3-2.7 6-6 6s-6-2.7-6-6" fill="none" stroke="#F3F5F9" stroke-width="4.5" stroke-linecap="round"/>'
          '</svg>';
    }
    return '<svg viewBox="0 0 64 64" width="54" height="54" xmlns="http://www.w3.org/2000/svg">'
        '<path d="M32 6L10 15v16c0 14.5 9.4 25.8 22 29 12.6-3.2 22-14.5 22-29V15L32 6z" fill="$fill" fill-opacity="0.22" stroke="$stroke" stroke-width="3"/>'
        '<path d="M32 18c-8.5 0-15 5.8-15 13.2h30C47 23.8 40.5 18 32 18z" fill="$stroke"/>'
        '<path d="M32 31.2V42c0 2-1.6 3.6-3.6 3.6" fill="none" stroke="#F3F5F9" stroke-width="3.2" stroke-linecap="round"/>'
        '</svg>';
  }
}
