import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'local_ca.dart';

/// آمار لحظه ای موتور فیلتر عمیق HTTPS (مشابه آمارهای AdGuard).
class HttpsFilterStats {
  const HttpsFilterStats({
    this.interceptedConnections = 0,
    this.bypassedConnections = 0,
    this.blockedRequests = 0,
    this.prunedJsonResponses = 0,
    this.injectedHtmlPages = 0,
  });

  final int interceptedConnections;
  final int bypassedConnections;
  final int blockedRequests;
  final int prunedJsonResponses;
  final int injectedHtmlPages;
}

/// موتور جراحی JSON یوتیوب (معادل `$replace=` و `json-prune` / `trusted-rpfr`
/// در uBlock Origin و Brave Shields).
class YouTubeJsonPruner {
  const YouTubeJsonPruner._();

  /// کلیدهایی که وجودشان مستقیماً به تبلیغات پیش/حین/پس از ویدیو یا بنرهای
  /// تبلیغاتی یوتیوب مربوط است و باید در هر عمقی از ساختار حذف شوند.
  static const Set<String> adObjectKeys = <String>{
    'adPlacements',
    'playerAds',
    'adSlots',
    'adBreakHeartbeatParams',
    'adBreakParams',
    'adParams',
    'instreamAdBreakRenderer',
    'linearAdSequenceRenderer',
    'playerLegacyDesktopWatchAdsRenderer',
    'adSlotRenderer',
    'promotedSparklesWebRenderer',
    'promotedSparklesTextSearchRenderer',
    'promotedVideoRenderer',
    'displayAdRenderer',
    'bannerPromoRenderer',
    'statementBannerRenderer',
    'mealbarPromoRenderer',
    'inFeedAdLayoutRenderer',
    'feedAdMetadataViewModel',
    'mastheadAdRenderer',
    'companionAdRenderer',
    'actionCompanionAdRenderer',
    'engagementPanelAdRenderer',
    'searchPyvRenderer',
    'videoMastheadAdRenderer',
    'primetimePromoRenderer',
    'brandVideoSingletonRenderer',
    'adInfoRenderer',
    'adsEngagementPanelContentRenderer',
    'adPlacementRenderer',
    'playerAdParams',
    'adVideoId',
    'adPlaybackContext',
  };

  /// کلیدهایی که یک کارت کامل فید/جستجو/ستون کناری را فقط در صورتی تبلیغ
  /// معرفی می کنند که درون ساختار کارت حضور داشته باشند.
  static const Set<String> adCardMarkerKeys = <String>{
    'adSlotRenderer',
    'promotedSparklesWebRenderer',
    'promotedSparklesTextSearchRenderer',
    'promotedVideoRenderer',
    'displayAdRenderer',
    'bannerPromoRenderer',
    'statementBannerRenderer',
    'mealbarPromoRenderer',
    'inFeedAdLayoutRenderer',
    'mastheadAdRenderer',
    'searchPyvRenderer',
    'videoMastheadAdRenderer',
    'primetimePromoRenderer',
    'brandVideoSingletonRenderer',
  };

  /// بررسی و پاکسازی یک متن JSON؛ اگر تغییری اعمال شده باشد رشته JSON
  /// پاکسازی شده را برمی گرداند و در غیر این صورت `null`.
  static String? pruneJsonString(String rawJson) {
    final String trimmed = rawJson.trimLeft();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(rawJson);
      final bool changed = pruneInPlace(decoded);
      if (!changed) {
        return null;
      }
      return jsonEncode(decoded);
    } catch (_) {
      return null;
    }
  }

  /// پاکسازی درجا و بازگشتی آبجکت دیکدشده یوتیوب. خروجی `true` نشان دهنده
  /// اعمال حداقل یک حذف تبلیغاتی است.
  static bool pruneInPlace(Object? node) {
    bool changed = false;
    if (node is Map) {
      final List<dynamic> keysToRemove = <dynamic>[];
      for (final dynamic key in node.keys) {
        final String keyStr = '$key';
        if (adObjectKeys.contains(keyStr)) {
          keysToRemove.add(key);
        }
      }
      if (keysToRemove.isNotEmpty) {
        for (final dynamic k in keysToRemove) {
          node.remove(k);
        }
        changed = true;
      }
      for (final dynamic value in node.values) {
        if (pruneInPlace(value)) {
          changed = true;
        }
      }
    } else if (node is List) {
      for (int i = node.length - 1; i >= 0; i--) {
        final dynamic item = node[i];
        if (_isPureAdCard(item)) {
          node.removeAt(i);
          changed = true;
          continue;
        }
        if (pruneInPlace(item)) {
          changed = true;
        }
      }
    }
    return changed;
  }

  static bool _isPureAdCard(Object? item, {int depth = 0}) {
    if (depth > 4 || item is! Map) {
      return false;
    }
    for (final dynamic rawKey in item.keys) {
      if (adCardMarkerKeys.contains('$rawKey')) {
        return true;
      }
    }
    // کارت های richItemRenderer / itemSectionRenderer در فید ۲۰۲۶ یوتیوب
    for (final String wrapper in const <String>[
      'richItemRenderer',
      'content',
      'itemSectionRenderer',
    ]) {
      final Object? nested = item[wrapper];
      if (nested != null && _isPureAdCard(nested, depth: depth + 1)) {
        return true;
      }
    }
    if (item['contents'] is List) {
      final List<dynamic> inner = item['contents'] as List<dynamic>;
      if (inner.length == 1 && _isPureAdCard(inner.first, depth: depth + 1)) {
        return true;
      }
    }
    return false;
  }
}

/// موتور پاکسازی HTML، Cosmetic CSS و Scriptlet Injection (الهام گرفته از
/// Brave `adblock-resources`، `uAssets` و `MasterKia/PersianBlocker`).
class HtmlAdFilterEngine {
  const HtmlAdFilterEngine._();

  static bool isYouTubePageHost(String host) {
    final String h = host.toLowerCase();
    return h == 'youtube.com' ||
        h.endsWith('.youtube.com') ||
        h == 'youtube-nocookie.com' ||
        h.endsWith('.youtube-nocookie.com');
  }

  static bool isYouTubeApiHost(String host) {
    final String h = host.toLowerCase();
    return isYouTubePageHost(h) || h == 'youtubei.googleapis.com';
  }

  /// قوانین URL مسیرمحور (Path-based) که در سطح شبکه (DNS/SNI) قابل تشخیص
  /// نیستند ولی روی تونل HTTPS به سادگی خنثی می شوند.
  static ({int statusCode, String contentType, String body})? matchBlockedPath(
    String rawHost,
    String pathAndQuery,
  ) {
    final String host = rawHost.toLowerCase();
    final String pq = pathAndQuery.toLowerCase();

    if (isYouTubeApiHost(host)) {
      if (pq.startsWith('/pagead/') ||
          pq.startsWith('/api/stats/ads') ||
          pq.startsWith('/api/stats/atr') ||
          pq.startsWith('/ptracking') ||
          pq.startsWith('/get_midroll_info') ||
          pq.startsWith('/pcs/activeview') ||
          pq.startsWith('/ad_data_sync')) {
        return (statusCode: 204, contentType: '', body: '');
      }
      if (pq.startsWith('/youtubei/v1/log_event') &&
          (pq.contains('ad_') || pq.contains('ads') || pq.contains('att'))) {
        return (statusCode: 200, contentType: 'application/json', body: '{}');
      }
    }

    // اسکریپت ها و مسیرهای تبلیغاتی First-Party / CNAME Cloaking در وب ایران و جهان
    if (pq.contains('yektanet.js') ||
        pq.contains('/yektanet/') ||
        pq.contains('yn-banner') ||
        pq.contains('/sabavision/') ||
        pq.contains('/tapsell/') ||
        pq.contains('/mediaad/') ||
        pq.contains('/kaprila/') ||
        pq.contains('/raykaad/') ||
        pq.contains('/adivery/') ||
        pq.contains('adsbygoogle.js') ||
        pq.contains('/pagead/js/') ||
        pq.contains('/gpt/pubads_impl') ||
        pq.contains('popunder')) {
      if (pq.contains('.js')) {
        return (
          statusCode: 200,
          contentType: 'application/javascript; charset=utf-8',
          body: '/* umbrella-ad-surrogate */',
        );
      }
      return (statusCode: 204, contentType: '', body: '');
    }

    return null;
  }

  static const String _persianAndGeneralCosmeticCss = '''
ins.adsbygoogle,
[id*="yektanet"], [class*="yektanet"], [data-yektanet],
.yn-bnr, .yn-widget, .yn-container,
[id*="sabavision"], [class*="sabavision"],
[id*="tapsell"], [class*="tapsell"],
[id*="mediaad"], [class*="mediaad"],
[id*="kaprila"], [class*="kaprila"],
[id*="raykaad"], [class*="raykaad"],
[id*="adnegah"], [class*="adnegah"],
[id*="adivery"], [class*="adivery"],
[id*="deema-ad"], [class*="deema-ad"],
iframe[src*="yektanet"], iframe[src*="sabavision"],
iframe[src*="tapsell"], iframe[src*="mediaad"],
iframe[src*="kaprila"], iframe[src*="doubleclick"],
iframe[src*="googlesyndication"],
a[href*="click.yektanet"], a[href*="tapsell.ir"],
a[href*="sabavision"], a[href*="adivery.com"],
div:has(> iframe[src*="yektanet"]),
div:has(> iframe[src*="sabavision"]),
div:has(> iframe[src*="tapsell"]),
div:has(> a[href*="click.yektanet"]),
div:has(> ins.adsbygoogle),
[data-ad-slot], [data-google-query-id],
.google-auto-placed, .ad-slot-wrapper, .banner-ads {
  display: none !important;
  visibility: hidden !important;
  height: 0 !important;
  min-height: 0 !important;
  max-height: 0 !important;
  margin: 0 !important;
  padding: 0 !important;
  border: 0 !important;
  overflow: hidden !important;
  pointer-events: none !important;
}
''';

  static const String _youtubeCosmeticCss = '''
#player-ads,
#masthead-ad,
#merchandise-shelf,
.ytd-banner-promo-renderer,
.video-ads.ytp-ad-module,
.ytp-ad-module,
.ytp-ad-overlay-container,
.ytp-ad-player-overlay,
.ytp-ad-player-overlay-layout,
ytd-ad-slot-renderer,
ytd-promoted-sparkles-web-renderer,
ytd-promoted-sparkles-text-search-renderer,
ytd-promoted-video-renderer,
ytd-display-ad-renderer,
ytd-in-feed-ad-layout-renderer,
ytd-banner-promo-renderer,
ytd-statement-banner-renderer,
ytd-mealbar-promo-renderer,
ytd-enforcement-message-view-model,
tp-yt-paper-dialog:has(ytd-enforcement-message-view-model),
ytd-rich-item-renderer:has(ytd-ad-slot-renderer),
ytd-rich-section-renderer:has(ytd-statement-banner-renderer),
ytd-rich-section-renderer:has(ytd-banner-promo-renderer),
ytm-promoted-sparkles-web-renderer,
ytm-companion-slot-renderer,
ad-slot-renderer {
  display: none !important;
  visibility: hidden !important;
  height: 0 !important;
  min-height: 0 !important;
  overflow: hidden !important;
  pointer-events: none !important;
}
''';

  /// اسکریپت لت دفاعی یوتیوب (پاکسازی آبجکت های SPA، قلاب `fetch` و `XHR`
  /// روی `/youtubei/v1/` و عبور سریع از هر فریم باقیمانده تبلیغ).
  static const String _youtubeScriptlet = r'''
(function(){
  if (window.__umbrellaYtGuard) return;
  window.__umbrellaYtGuard = true;
  var AD_KEYS = {
    adPlacements:1, playerAds:1, adSlots:1, adBreakHeartbeatParams:1,
    adBreakParams:1, adParams:1, instreamAdBreakRenderer:1,
    linearAdSequenceRenderer:1, playerLegacyDesktopWatchAdsRenderer:1,
    adSlotRenderer:1, promotedSparklesWebRenderer:1, promotedVideoRenderer:1,
    displayAdRenderer:1, bannerPromoRenderer:1, statementBannerRenderer:1,
    mealbarPromoRenderer:1, inFeedAdLayoutRenderer:1, mastheadAdRenderer:1,
    companionAdRenderer:1, searchPyvRenderer:1, adInfoRenderer:1
  };
  var CARD_KEYS = {
    adSlotRenderer:1, promotedSparklesWebRenderer:1, promotedVideoRenderer:1,
    displayAdRenderer:1, bannerPromoRenderer:1, statementBannerRenderer:1,
    mealbarPromoRenderer:1, inFeedAdLayoutRenderer:1, searchPyvRenderer:1
  };
  function isAdCard(obj, depth){
    if (!obj || typeof obj !== 'object' || depth > 3) return false;
    for (var k in CARD_KEYS) { if (Object.prototype.hasOwnProperty.call(obj, k)) return true; }
    if (obj.richItemRenderer && isAdCard(obj.richItemRenderer, depth + 1)) return true;
    if (obj.content && isAdCard(obj.content, depth + 1)) return true;
    return false;
  }
  function prune(node, depth){
    if (!node || typeof node !== 'object' || depth > 24) return node;
    if (Array.isArray(node)) {
      for (var i = node.length - 1; i >= 0; i--) {
        if (isAdCard(node[i], 0)) { node.splice(i, 1); }
        else { prune(node[i], depth + 1); }
      }
      return node;
    }
    for (var key in AD_KEYS) {
      if (Object.prototype.hasOwnProperty.call(node, key)) {
        try { delete node[key]; } catch(_){}
      }
    }
    var keys = Object.keys(node);
    for (var j = 0; j < keys.length; j++) {
      var val = node[keys[j]];
      if (val && typeof val === 'object') prune(val, depth + 1);
    }
    return node;
  }
  try {
    if (window.ytInitialPlayerResponse) prune(window.ytInitialPlayerResponse, 0);
    if (window.ytInitialData) prune(window.ytInitialData, 0);
  } catch(_){}

  if (typeof window.fetch === 'function') {
    var origFetch = window.fetch;
    window.fetch = function(input, init){
      var url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
      var resPromise = origFetch.apply(this, arguments);
      if (url.indexOf('/youtubei/v1/') === -1) return resPromise;
      return resPromise.then(function(resp){
        try {
          var ct = resp.headers ? (resp.headers.get('content-type') || '') : '';
          if (ct.indexOf('json') === -1) return resp;
          return resp.clone().text().then(function(txt){
            try {
              var parsed = JSON.parse(txt);
              prune(parsed, 0);
              var clean = JSON.stringify(parsed);
              var hdrs = new Headers(resp.headers);
              hdrs.delete('content-length');
              return new Response(clean, { status: resp.status, statusText: resp.statusText, headers: hdrs });
            } catch(_) { return resp; }
          });
        } catch(_) { return resp; }
      });
    };
  }

  function skipResidualPlayerAd(){
    try {
      var player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
      if (!player) return;
      var adShowing = player.classList.contains('ad-showing') || player.classList.contains('ad-interrupting');
      if (adShowing) {
        var v = player.querySelector('video');
        if (v && isFinite(v.duration) && v.duration > 0) {
          v.muted = true;
          if (v.currentTime < v.duration - 0.1) v.currentTime = v.duration;
        }
        var btn = player.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern');
        if (btn && typeof btn.click === 'function') btn.click();
      }
    } catch(_){}
  }
  setInterval(skipResidualPlayerAd, 250);
  if (typeof MutationObserver === 'function' && document.documentElement) {
    new MutationObserver(skipResidualPlayerAd).observe(document.documentElement, {
      subtree: true, attributes: true, attributeFilter: ['class']
    });
  }
})();
''';

  /// اعمال تمام تغییرات HTML (پاکسازی JSON تعبیه شده یوتیوب + تزریق CSS/Scriptlet)
  /// به همراه همگام سازی خودکار CSP nonce.
  static ({String html, String? nonceToAllow}) filterHtml({
    required String host,
    required String rawHtml,
    String? existingCsp,
  }) {
    if (!RegExp(r'<(?:!doctype|html|head|body|div)\b', caseSensitive: false)
        .hasMatch(rawHtml)) {
      return (html: rawHtml, nonceToAllow: null);
    }
    String html = rawHtml;
    bool modified = false;

    final bool yt = isYouTubePageHost(host);
    if (yt) {
      for (final String symbol in const <String>[
        'ytInitialPlayerResponse',
        'ytInitialData',
      ]) {
        final String? updated = _pruneEmbeddedJsonVar(html, symbol);
        if (updated != null) {
          html = updated;
          modified = true;
        }
      }
    }

    final String css = yt
        ? '$_youtubeCosmeticCss\n$_persianAndGeneralCosmeticCss'
        : _persianAndGeneralCosmeticCss;
    final String nonce = _extractOrGenerateNonce(existingCsp);
    final String nonceAttr = ' nonce="${_escapeAttr(nonce)}"';
    final StringBuffer injection = StringBuffer()
      ..write('<style id="umbrella-cosmetic-filter"$nonceAttr>')
      ..write(css)
      ..write('</style>');
    if (yt) {
      injection
        ..write('<script id="umbrella-yt-scriptlet"$nonceAttr>')
        ..write(_youtubeScriptlet)
        ..write('</script>');
    }

    final String injectedHtml = _injectIntoHead(html, injection.toString());
    if (injectedHtml != html) {
      html = injectedHtml;
      modified = true;
    }

    return (
      html: html,
      nonceToAllow: modified ? nonce : null,
    );
  }

  /// تنظیم خودکار `Content-Security-Policy` به گونه ای که nonce تزریقی مجاز شود
  /// بدون اینکه امنیت کلی CSP سایت ضعیف گردد.
  static String? patchCspHeader(String? csp, String nonce) {
    if (csp == null || csp.trim().isEmpty) {
      return null;
    }
    final String token = "'nonce-$nonce'";
    if (csp.contains(token)) {
      return csp;
    }
    final List<String> directives = csp.split(';');
    final bool hasDedicatedScript = directives.any((String raw) {
      final String l = raw.trimLeft().toLowerCase();
      return l.startsWith('script-src ') ||
          l == 'script-src' ||
          l.startsWith('script-src-elem ') ||
          l == 'script-src-elem';
    });
    final bool hasDedicatedStyle = directives.any((String raw) {
      final String l = raw.trimLeft().toLowerCase();
      return l.startsWith('style-src ') ||
          l == 'style-src' ||
          l.startsWith('style-src-elem ') ||
          l == 'style-src-elem';
    });
    final List<String> out = <String>[];
    for (final String rawDir in directives) {
      final String d = rawDir.trim();
      if (d.isEmpty) continue;
      final String lower = d.toLowerCase();
      if (lower.startsWith('script-src ') ||
          lower == 'script-src' ||
          lower.startsWith('script-src-elem ') ||
          lower == 'script-src-elem' ||
          lower.startsWith('style-src ') ||
          lower == 'style-src' ||
          lower.startsWith('style-src-elem ') ||
          lower == 'style-src-elem') {
        out.add('$d $token');
      } else if ((lower.startsWith('default-src ') || lower == 'default-src') &&
          (!hasDedicatedScript || !hasDedicatedStyle)) {
        out.add('$d $token');
      } else {
        out.add(d);
      }
    }
    return out.join('; ');
  }

  static String _extractOrGenerateNonce(String? csp) {
    if (csp != null && csp.isNotEmpty) {
      final RegExpMatch? m =
          RegExp(r"'nonce-([A-Za-z0-9+/=_-]+)'").firstMatch(csp);
      if (m != null && m.group(1) != null && m.group(1)!.isNotEmpty) {
        return m.group(1)!;
      }
    }
    final Random rng = Random.secure();
    final Uint8List raw = Uint8List(12);
    for (int i = 0; i < raw.length; i++) {
      raw[i] = rng.nextInt(256);
    }
    return base64UrlEncode(raw).replaceAll('=', '');
  }

  static String _escapeAttr(String s) =>
      s.replaceAll('"', '').replaceAll('<', '').replaceAll('>', '');

  static String _injectIntoHead(String html, String fragment) {
    final RegExp headClose = RegExp(r'</head\s*>', caseSensitive: false);
    final RegExpMatch? mClose = headClose.firstMatch(html);
    if (mClose != null) {
      return '${html.substring(0, mClose.start)}$fragment${html.substring(mClose.start)}';
    }
    final RegExp headOpen = RegExp(r'<head\b[^>]*>', caseSensitive: false);
    final RegExpMatch? mOpen = headOpen.firstMatch(html);
    if (mOpen != null) {
      return '${html.substring(0, mOpen.end)}$fragment${html.substring(mOpen.end)}';
    }
    final RegExp bodyOpen = RegExp(r'<body\b[^>]*>', caseSensitive: false);
    final RegExpMatch? mBody = bodyOpen.firstMatch(html);
    if (mBody != null) {
      return '${html.substring(0, mBody.start)}$fragment${html.substring(mBody.start)}';
    }
    return '$fragment$html';
  }

  /// اسکنر متوازن براکت برای استخراج و پاکسازی ایمن JSON تعبیه شده یوتیوب
  /// مانند `var ytInitialPlayerResponse = {...};` درون صفحات HTML.
  static String? _pruneEmbeddedJsonVar(String html, String symbol) {
    final RegExp pattern = RegExp(
      '(?:var\\s+|let\\s+|const\\s+|window\\[[\'"]|window\\.)'
      '${RegExp.escape(symbol)}'
      '(?:[\'"]\\])?\\s*=\\s*\\{',
    );
    final RegExpMatch? match = pattern.firstMatch(html);
    if (match == null) return null;

    final int objStart = match.end - 1;
    final int? objEnd = _scanBalancedJsonObjectEnd(html, objStart);
    if (objEnd == null || objEnd <= objStart) return null;

    final String rawObj = html.substring(objStart, objEnd);
    final String? pruned = YouTubeJsonPruner.pruneJsonString(rawObj);
    if (pruned == null) return null;

    // جلوگیری از بسته شدن تگ `<script>` هنگام حضور `</script>` در متن JSON.
    final String scriptSafe = pruned.replaceAll('</', r'<\/');
    return '${html.substring(0, objStart)}$scriptSafe${html.substring(objEnd)}';
  }

  static int? _scanBalancedJsonObjectEnd(String text, int start) {
    if (start < 0 || start >= text.length || text[start] != '{') return null;
    int depth = 0;
    bool inString = false;
    bool escaped = false;
    for (int i = start; i < text.length; i++) {
      final int cu = text.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (cu == 0x5C /* \ */) {
          escaped = true;
        } else if (cu == 0x22 /* " */) {
          inString = false;
        }
        continue;
      }
      if (cu == 0x22 /* " */) {
        inString = true;
      } else if (cu == 0x7B /* { */) {
        depth++;
      } else if (cu == 0x7D /* } */) {
        depth--;
        if (depth == 0) {
          return i + 1;
        }
      }
    }
    return null;
  }
}

/// پراکسی محلی فیلترینگ عمیق HTTPS (سبک AdGuard Desktop/Android).
///
/// این سرور با دریافت درخواست های `CONNECT host:443` از `sing-box`، فقط برای
/// دامنه های مجاز و غیرامنیتی (به جز بانک ها، درگاه ها و اپ های دارای
/// Certificate Pinning) یک تونل TLS محلی با گواهی امضاشده توسط [LocalCaManager]
/// ایجاد می کند، محتوای HTTP/1.1 بالادست را از مسیر اختصاصی `egressPort` (برای
/// جلوگیری کامل از حلقه مسیریابی) دریافت و در لحظه جراحی می نماید.
class HttpsAdFilterProxy {
  HttpsAdFilterProxy({
    required this.caManager,
    this.broadMode = false,
    this.egressPort = 0,
    this.egressUsername = 'umbrella',
    this.egressSecret = '',
    this.onStatsChanged,
    this.onLog,
    @visibleForTesting this.upstreamSecurityContext,
  });

  final LocalCaManager caManager;
  bool broadMode;
  int egressPort;
  String egressUsername;
  String egressSecret;
  final void Function(HttpsFilterStats stats)? onStatsChanged;
  final void Function(String message, {String level})? onLog;

  @visibleForTesting
  final SecurityContext? upstreamSecurityContext;

  /// دامنه های پیش فرض در حالت «هوشمند» (یوتیوب و وب سایت های پرتبلیغ).
  static const List<String> smartTargetDomains = <String>[
    // یوتیوب (صفحات HTML و متادیتای API؛ استریم خام googlevideo مستثنی است)
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'music.youtube.com',
    'youtube-nocookie.com',
    'youtubei.googleapis.com',
    // وب سایت های فارسی و بین المللی نیازمند حذف کادر خالی و Cosmetic CSS
    'varzesh3.com',
    'tarafdari.com',
    'zoomit.ir',
    'digiato.com',
    'khabaronline.ir',
    'asriran.com',
    'tabnak.ir',
    'aparat.com',
    'telewebion.com',
    'namnak.com',
    'beytoote.com',
    'yjc.ir',
    'isna.ir',
    'mehrnews.com',
    'tasnimnews.com',
    'farsnews.ir',
    'entekhab.ir',
    'hamshahrionline.ir',
    'donya-e-eqtesad.com',
    'mashreghnews.ir',
    'eghtesadnews.com',
    'soft98.ir',
    'yasdl.com',
    'downloadha.com',
    'imdb.com',
    'fandom.com',
    'forbes.com',
    'cnn.com',
    'bbc.com',
    'speedtest.net',
    'gsmarena.com',
    'wikihow.com',
  ];

  /// دامنه هایی که به علت امنیت بانکی، احراز هویت یا Certificate Pinning
  /// هرگز نباید تحت بازگشایی TLS قرار گیرند (حتی در حالت Broad Mode).
  static const List<String> neverInterceptSuffixes = <String>[
    // بانک ها، شاپرک، درگاه های پرداخت و سامانه های حاکمیتی ایران
    'shaparak.ir',
    'bmi.ir',
    'bankmellat.ir',
    'mellatbank.ir',
    'bsi.ir',
    'tejaratbank.ir',
    'banksepah.ir',
    'sepahbank.ir',
    'parsian-bank.ir',
    'bpi.ir',
    'sb24.ir',
    'sb24.com',
    'enbank.ir',
    'sinabank.ir',
    'refah-bank.ir',
    'postbank.ir',
    'bank-maskan.ir',
    'keshavarzi.ir',
    'izbank.ir',
    'day24.ir',
    'karafarinbank.ir',
    'resalat.ir',
    'mebank.ir',
    'shahr-bank.ir',
    'gardeshgari.ir',
    'blubank.com',
    'blu.bank',
    'wepod.ir',
    'zarinpal.com',
    'zibal.ir',
    'idpay.ir',
    'payping.ir',
    'pay.ir',
    'my.gov.ir',
    // استریم ویدیوی یوتیوب (بدون تبلیغ متنی، برای حداکثر سرعت 4K دست نخورده)
    'googlevideo.com',
    'ytimg.com',
    'ggpht.com',
    // پیام رسان ها و سرویس های دارای Certificate Pinning
    'accounts.google.com',
    'play.googleapis.com',
    'android.clients.google.com',
    'telegram.org',
    't.me',
    'whatsapp.com',
    'whatsapp.net',
    'instagram.com',
    'cdninstagram.com',
    'apple.com',
    'icloud.com',
    'microsoftonline.com',
    'windowsupdate.com',
    'github.com',
    'api.github.com',
    'umbrella.ir',
    'sentry.io',
  ];

  ServerSocket? _proxyServer;
  ServerSocket? _tlsBridgeServer;
  Future<void>? _startInFlight;
  bool _stopped = false;

  final Map<int, Completer<Socket>> _pendingBridgeAccepts =
      <int, Completer<Socket>>{};
  final Map<int, Socket> _earlyBridgeAccepts = <int, Socket>{};

  /// یادگیری خودکار هاست هایی که در حالت Broad دچار شکست Pinning شدند تا از
  /// درخواست بعدی مستقیماً به صورت شفاف pass-through شوند.
  final Set<String> _autoPinBypassHosts = <String>{};

  int _interceptedConnections = 0;
  int _bypassedConnections = 0;
  int _blockedRequests = 0;
  int _prunedJsonResponses = 0;
  int _injectedHtmlPages = 0;

  int get proxyPort => _proxyServer?.port ?? 0;
  bool get isRunning =>
      _proxyServer != null && _tlsBridgeServer != null && !_stopped;

  HttpsFilterStats get stats => HttpsFilterStats(
        interceptedConnections: _interceptedConnections,
        bypassedConnections: _bypassedConnections,
        blockedRequests: _blockedRequests,
        prunedJsonResponses: _prunedJsonResponses,
        injectedHtmlPages: _injectedHtmlPages,
      );

  static bool isNeverInterceptHost(String rawHost) {
    final String h = LocalCaManager.normalizeHost(rawHost);
    if (h.isEmpty) return true;
    for (final String suffix in neverInterceptSuffixes) {
      if (h == suffix || h.endsWith('.$suffix')) {
        return true;
      }
    }
    return false;
  }

  static bool isSmartTargetHost(String rawHost) {
    final String h = LocalCaManager.normalizeHost(rawHost);
    if (h.isEmpty) return false;
    for (final String suffix in smartTargetDomains) {
      if (h == suffix || h.endsWith('.$suffix')) {
        return true;
      }
    }
    return false;
  }

  bool shouldInterceptTls(String rawHost, int port) {
    if (port != 443) return false;
    final String h = LocalCaManager.normalizeHost(rawHost);
    if (h.isEmpty || isNeverInterceptHost(h)) {
      return false;
    }
    if (InternetAddress.tryParse(h) != null) {
      return false;
    }
    if (_autoPinBypassHosts.contains(h)) {
      return false;
    }
    if (broadMode) {
      return true;
    }
    return isSmartTargetHost(h);
  }

  void updateRoutingConfig({
    bool? broadMode,
    int? egressPort,
    String? egressUsername,
    String? egressSecret,
  }) {
    if (broadMode != null) this.broadMode = broadMode;
    if (egressPort != null) this.egressPort = egressPort;
    if (egressUsername != null) this.egressUsername = egressUsername;
    if (egressSecret != null) this.egressSecret = egressSecret;
  }

  Future<void> start({int port = 0}) {
    if (isRunning) {
      return Future<void>.value();
    }
    return _startInFlight ??= _startInternal(port: port);
  }

  Future<void> _startInternal({required int port}) async {
    _stopped = false;
    await caManager.ensureInitialized();
    try {
      final ServerSocket bridge =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final ServerSocket proxy =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      if (_stopped) {
        await bridge.close();
        await proxy.close();
        return;
      }
      _tlsBridgeServer = bridge;
      _proxyServer = proxy;
      bridge.listen(_onBridgeSocketAccepted, onError: (_) {});
      proxy.listen(
        (Socket client) => unawaited(_handleClientConnection(client)),
        onError: (_) {},
      );
    } catch (_) {
      await stop();
      rethrow;
    } finally {
      _startInFlight = null;
    }
  }

  Future<void> stop() async {
    _stopped = true;
    _startInFlight = null;
    final ServerSocket? proxy = _proxyServer;
    final ServerSocket? bridge = _tlsBridgeServer;
    _proxyServer = null;
    _tlsBridgeServer = null;
    for (final Completer<Socket> pending in _pendingBridgeAccepts.values) {
      if (!pending.isCompleted) {
        pending.completeError(const SocketException('Proxy stopped'));
      }
    }
    _pendingBridgeAccepts.clear();
    for (final Socket s in _earlyBridgeAccepts.values) {
      s.destroy();
    }
    _earlyBridgeAccepts.clear();
    if (proxy != null) {
      try {
        await proxy.close();
      } catch (_) {}
    }
    if (bridge != null) {
      try {
        await bridge.close();
      } catch (_) {}
    }
  }

  void _onBridgeSocketAccepted(Socket serverSide) {
    final int rp = serverSide.remotePort;
    final Completer<Socket>? pending = _pendingBridgeAccepts.remove(rp);
    if (pending != null && !pending.isCompleted) {
      pending.complete(serverSide);
    } else {
      _earlyBridgeAccepts[rp] = serverSide;
      Timer(const Duration(seconds: 5), () {
        final Socket? stale = _earlyBridgeAccepts.remove(rp);
        stale?.destroy();
      });
    }
  }

  Future<({Socket tunnelSide, Socket tlsServerSide})> _createBridgePair() async {
    final ServerSocket? bridge = _tlsBridgeServer;
    if (bridge == null) {
      throw const SocketException('TLS bridge server not running');
    }
    final Socket tunnelSide =
        await Socket.connect(InternetAddress.loopbackIPv4, bridge.port);
    final int lp = tunnelSide.port;
    final Socket? early = _earlyBridgeAccepts.remove(lp);
    if (early != null) {
      return (tunnelSide: tunnelSide, tlsServerSide: early);
    }
    final Completer<Socket> c = Completer<Socket>();
    _pendingBridgeAccepts[lp] = c;
    try {
      final Socket serverSide =
          await c.future.timeout(const Duration(seconds: 5));
      return (tunnelSide: tunnelSide, tlsServerSide: serverSide);
    } catch (_) {
      _pendingBridgeAccepts.remove(lp);
      tunnelSide.destroy();
      rethrow;
    }
  }

  Future<void> _handleClientConnection(Socket clientSocket) async {
    final _HttpStreamReader clientRawReader = _HttpStreamReader(clientSocket);
    try {
      final _ParsedHttpHead? connectHead = await clientRawReader
          .readHeaders(maxBytes: 16384)
          .timeout(const Duration(seconds: 8));
      if (connectHead == null) {
        await clientRawReader.close();
        clientSocket.destroy();
        return;
      }

      final List<String> parts = connectHead.startLine.split(RegExp(r'\s+'));
      final String method = parts.isNotEmpty ? parts[0].toUpperCase() : '';
      final String target = parts.length > 1 ? parts[1] : '';
      if (method != 'CONNECT' || target.isEmpty) {
        clientSocket.add(utf8.encode(
          'HTTP/1.1 405 Method Not Allowed\r\nConnection: close\r\n\r\n',
        ));
        await clientSocket.flush().catchError((_) {});
        await clientRawReader.close();
        clientSocket.destroy();
        return;
      }

      final ({String host, int port}) parsedTarget =
          _parseHostPort(target, defaultPort: 443);
      final String host = LocalCaManager.normalizeHost(parsedTarget.host);
      final int port = parsedTarget.port;
      if (host.isEmpty || port <= 0 || port > 65535) {
        await clientRawReader.close();
        clientSocket.destroy();
        return;
      }

      // در صورت Bypass بودن دامنه (بانکی/پین شده/غیر۴۴۳): عبور مستقیم بدون بازگشایی TLS
      if (!shouldInterceptTls(host, port)) {
        _bypassedConnections++;
        _notifyStats();
        Socket? rawUp;
        try {
          rawUp = await _dialUpstreamTcp(host, port);
        } catch (_) {
          clientSocket.add(utf8.encode(
            'HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n',
          ));
          await clientSocket.flush().catchError((_) {});
          await clientRawReader.close();
          clientSocket.destroy();
          return;
        }
        clientSocket.add(
          utf8.encode('HTTP/1.1 200 Connection Established\r\n\r\n'),
        );
        final Uint8List leftover = clientRawReader.takeLeftover();
        if (leftover.isNotEmpty) {
          rawUp.add(leftover);
        }
        await _pumpBidirectional(
          clientReader: clientRawReader,
          clientSink: clientSocket,
          upstreamSocket: rawUp,
        );
        return;
      }

      // بازگشایی TLS MITM با گواهی پویای صادرشده از CA محلی
      _interceptedConnections++;
      _notifyStats();

      final SecurityContext leafCtx =
          await caManager.securityContextForHost(host);
      final ({Socket tunnelSide, Socket tlsServerSide}) pair =
          await _createBridgePair();

      clientSocket.add(
        utf8.encode('HTTP/1.1 200 Connection Established\r\n\r\n'),
      );
      final Uint8List earlyTlsBytes = clientRawReader.takeLeftover();
      if (earlyTlsBytes.isNotEmpty) {
        pair.tunnelSide.add(earlyTlsBytes);
      }

      // اتصال دوطرفه بین کلاینت و سر خام پل TLS
      bool bridgeClosed = false;
      void closeBridge() {
        if (bridgeClosed) return;
        bridgeClosed = true;
        unawaited(clientRawReader.close());
        clientSocket.destroy();
        pair.tunnelSide.destroy();
      }

      final StreamSubscription<Uint8List> tlsOutToClient =
          pair.tunnelSide.listen(
        (Uint8List chunk) {
          try {
            clientSocket.add(chunk);
          } catch (_) {
            closeBridge();
          }
        },
        onError: (_) => closeBridge(),
        onDone: closeBridge,
      );

      unawaited(() async {
        try {
          await for (final Uint8List chunk in clientRawReader.remainingStream()) {
            if (bridgeClosed) break;
            pair.tunnelSide.add(chunk);
          }
        } catch (_) {
        } finally {
          closeBridge();
        }
      }());

      SecureSocket? tlsClient;
      try {
        tlsClient = await SecureSocket.secureServer(
          pair.tlsServerSide,
          leafCtx,
          supportedProtocols: const <String>['http/1.1'],
        ).timeout(const Duration(seconds: 10));
      } catch (_) {
        if (broadMode && _autoPinBypassHosts.add(host)) {
          onLog?.call(
            'دامنه $host گواهی پین شده داشت و خودکار در فهرست عبور مستقیم قرار گرفت.',
          );
        }
        await tlsOutToClient.cancel();
        pair.tlsServerSide.destroy();
        closeBridge();
        return;
      }

      await _handleInterceptedTlsSession(
        tlsClient: tlsClient,
        host: host,
        port: port,
      );
      await tlsOutToClient.cancel();
      closeBridge();
    } catch (_) {
      await clientRawReader.close();
      clientSocket.destroy();
    }
  }

  Future<void> _handleInterceptedTlsSession({
    required SecureSocket tlsClient,
    required String host,
    required int port,
  }) async {
    final _HttpStreamReader clientReader = _HttpStreamReader(tlsClient);
    SecureSocket? upstreamTls;
    _HttpStreamReader? upstreamReader;
    bool handledAnyHttp = false;

    Future<void> closeUpstream() async {
      await upstreamReader?.close();
      upstreamTls?.destroy();
      upstreamReader = null;
      upstreamTls = null;
    }

    try {
      while (!_stopped) {
        final _ParsedHttpHead? reqHead = await clientReader
            .readHeaders(maxBytes: 65536)
            .timeout(const Duration(seconds: 30), onTimeout: () => null);
        if (reqHead == null) {
          if (!handledAnyHttp && broadMode) {
            _autoPinBypassHosts.add(host);
          }
          break;
        }
        handledAnyHttp = true;

        final List<String> reqParts = reqHead.startLine.split(RegExp(r'\s+'));
        final String method =
            reqParts.isNotEmpty ? reqParts[0].toUpperCase() : 'GET';
        final String target = reqParts.length > 1 ? reqParts[1] : '/';
        final String httpVersion =
            reqParts.length > 2 ? reqParts[2] : 'HTTP/1.1';
        final String effectiveHost =
            LocalCaManager.normalizeHost(reqHead.firstHeader('host') ?? host);

        final ({int statusCode, String contentType, String body})? blockedPath =
            HtmlAdFilterEngine.matchBlockedPath(effectiveHost, target);
        if (blockedPath != null) {
          _blockedRequests++;
          _notifyStats();
          final Uint8List? reqBody = await _readRequestBodyIfAny(
            clientReader,
            reqHead,
          );
          if (reqBody == null && _requestHasBody(reqHead)) {
            break;
          }
          _writeSyntheticResponse(
            tlsClient,
            statusCode: blockedPath.statusCode,
            contentType: blockedPath.contentType,
            body: blockedPath.body,
            closeAfter: _wantsConnectionClose(reqHead),
          );
          await tlsClient.flush().catchError((_) {});
          if (_wantsConnectionClose(reqHead)) break;
          continue;
        }

        // اگر WebSocket یا Upgrade است، اتصال خام را دوطرفه تونل می کنیم.
        final bool isUpgrade =
            reqHead.firstHeader('upgrade')?.isNotEmpty == true;
        final bool canFilterContent = !isUpgrade && method != 'HEAD';
        final List<MapEntry<String, String>> outReqHeaders =
            <MapEntry<String, String>>[];
        bool sawAcceptEncoding = false;
        for (final MapEntry<String, String> h in reqHead.headers) {
          final String lk = h.key.toLowerCase();
          if (lk == 'proxy-connection') continue;
          if (canFilterContent && lk == 'accept-encoding') {
            sawAcceptEncoding = true;
            // محدود کردن به gzip/deflate تا جراحی متن بدون نیاز به brotli همیشه کار کند.
            outReqHeaders.add(
              const MapEntry<String, String>('Accept-Encoding', 'gzip, deflate'),
            );
            continue;
          }
          outReqHeaders.add(h);
        }
        if (canFilterContent && !sawAcceptEncoding) {
          outReqHeaders.add(
            const MapEntry<String, String>('Accept-Encoding', 'gzip, deflate'),
          );
        }

        final StringBuffer reqWire = StringBuffer()
          ..write('$method $target $httpVersion\r\n');
        for (final MapEntry<String, String> h in outReqHeaders) {
          reqWire.write('${h.key}: ${h.value}\r\n');
        }
        reqWire.write('\r\n');
        final Uint8List wireBytes = Uint8List.fromList(utf8.encode(reqWire.toString()));

        final bool reqHasBody = _requestHasBody(reqHead);
        Uint8List? bufferedReqBody;
        if (reqHasBody && !isUpgrade) {
          bufferedReqBody = await _readRequestBodyIfAny(clientReader, reqHead);
        }

        _ParsedHttpHead? resHead;
        for (int attempt = 0; attempt < 2; attempt++) {
          final bool reused = upstreamTls != null;
          if (upstreamTls == null) {
            final Socket rawUp = await _dialUpstreamTcp(host, port);
            upstreamTls = await SecureSocket.secure(
              rawUp,
              host: host,
              context: upstreamSecurityContext,
              supportedProtocols: const <String>['http/1.1'],
            ).timeout(const Duration(seconds: 12));
            upstreamReader = _HttpStreamReader(upstreamTls);
          }
          final SecureSocket activeUpstream = upstreamTls;

          try {
            activeUpstream.add(wireBytes);
            if (bufferedReqBody != null) {
              if (bufferedReqBody.isNotEmpty) {
                activeUpstream.add(bufferedReqBody);
              }
            } else if (reqHasBody) {
              await _forwardRequestBody(clientReader, reqHead, activeUpstream);
            }
            await activeUpstream.flush();
          } catch (_) {
            await closeUpstream();
            if (attempt == 0 && reused && (!reqHasBody || bufferedReqBody != null)) {
              continue;
            }
            rethrow;
          }

          if (isUpgrade) {
            await _pumpTwoWayReaders(
              aReader: clientReader,
              aSink: tlsClient,
              bReader: upstreamReader!,
              bSink: activeUpstream,
            );
            return;
          }

          // خواندن پاسخ بالادست (با رد کردن احتمالی پاسخ های 1xx مثل 100 Continue)
          while (true) {
            resHead = await upstreamReader!
                .readHeaders(maxBytes: 65536)
                .timeout(const Duration(seconds: 30), onTimeout: () => null);
            if (resHead == null) break;
            final int code = _parseStatusCode(resHead.startLine);
            if (code >= 100 && code < 200 && code != 101) {
              tlsClient.add(resHead.rawHeaderBytes);
              await tlsClient.flush().catchError((_) {});
              continue;
            }
            break;
          }
          if (resHead == null &&
              attempt == 0 &&
              reused &&
              (!reqHasBody || bufferedReqBody != null)) {
            await closeUpstream();
            continue;
          }
          break;
        }
        if (resHead == null) {
          break;
        }

        final int statusCode = _parseStatusCode(resHead.startLine);
        if (statusCode == 101) {
          tlsClient.add(resHead.rawHeaderBytes);
          await tlsClient.flush().catchError((_) {});
          await _pumpTwoWayReaders(
            aReader: clientReader,
            aSink: tlsClient,
            bReader: upstreamReader!,
            bSink: upstreamTls!,
          );
          break;
        }

        final bool noBody = method == 'HEAD' ||
            statusCode == 204 ||
            statusCode == 304 ||
            (statusCode >= 100 && statusCode < 200);
        if (noBody) {
          tlsClient.add(resHead.rawHeaderBytes);
          await tlsClient.flush().catchError((_) {});
          if (_wantsConnectionClose(resHead) || _wantsConnectionClose(reqHead)) {
            break;
          }
          continue;
        }

        final String contentType =
            (resHead.firstHeader('content-type') ?? '').toLowerCase();
        final String contentEncoding =
            (resHead.firstHeader('content-encoding') ?? '').toLowerCase().trim();
        final bool supportedEncoding = contentEncoding.isEmpty ||
            contentEncoding == 'identity' ||
            contentEncoding == 'gzip' ||
            contentEncoding == 'x-gzip' ||
            contentEncoding == 'deflate';
        final bool isHtml = contentType.contains('text/html');
        final bool isYouTubeJson = contentType.contains('application/json') &&
            HtmlAdFilterEngine.isYouTubeApiHost(effectiveHost) &&
            (target.contains('/youtubei/v1/') ||
                target.contains('/watch') ||
                target.contains('/playlist'));

        final bool shouldInspectBody =
            supportedEncoding && (isHtml || isYouTubeJson);

        if (!shouldInspectBody) {
          tlsClient.add(resHead.rawHeaderBytes);
          await _streamResponseBody(
            upstreamReader!,
            resHead,
            tlsClient,
          );
          await tlsClient.flush().catchError((_) {});
          if (_wantsConnectionClose(resHead) || _wantsConnectionClose(reqHead)) {
            break;
          }
          continue;
        }

        // بافر کردن بدنه با سقف امن ۱۶ مگابایت برای جراحی HTML/JSON
        final ({Uint8List bytes, bool complete, bool wasChunked, bool readToEof})
            buffered = await _readBufferedBody(
          upstreamReader!,
          resHead,
          maxBytes: 16 * 1024 * 1024,
        );
        if (!buffered.complete) {
          // اگر پاسخ از سقف حافظه بزرگ تر یا ناقص بود، بدون تغییر ارسال یا بسته می شود.
          tlsClient.add(resHead.rawHeaderBytes);
          if (buffered.bytes.isNotEmpty) {
            tlsClient.add(buffered.bytes);
          }
          await tlsClient.flush().catchError((_) {});
          break;
        }

        final ({Uint8List bytes, String? cspNonce})? processed =
            _processInspectableBody(
          host: effectiveHost,
          rawBodyBytes: buffered.bytes,
          contentEncoding: contentEncoding,
          isHtml: isHtml,
          isYouTubeJson: isYouTubeJson,
          resHead: resHead,
        );

        if (processed == null) {
          // بدون تغییر (دقیقاً همان بایت های اصلی)
          _writeUnmodifiedResponse(
            tlsClient,
            resHead,
            buffered.bytes,
          );
          await tlsClient.flush().catchError((_) {});
        } else {
          final Uint8List headerBytes = _rebuildResponseHeaders(
            resHead,
            newBodyLength: processed.bytes.length,
            cspNonce: processed.cspNonce,
          );
          tlsClient.add(headerBytes);
          if (processed.bytes.isNotEmpty) {
            tlsClient.add(processed.bytes);
          }
          await tlsClient.flush().catchError((_) {});
        }

        if (buffered.readToEof ||
            _wantsConnectionClose(resHead) ||
            _wantsConnectionClose(reqHead)) {
          break;
        }
      }
    } catch (_) {
      // خطاهای قطع شدن اتصال از سمت کلاینت/بالادست بی سر و صدا بسته می شوند.
    } finally {
      await closeUpstream();
      await clientReader.close();
      tlsClient.destroy();
    }
  }

  ({Uint8List bytes, String? cspNonce})? _processInspectableBody({
    required String host,
    required Uint8List rawBodyBytes,
    required String contentEncoding,
    required bool isHtml,
    required bool isYouTubeJson,
    required _ParsedHttpHead resHead,
  }) {
    try {
      List<int> decodedBytes;
      if (contentEncoding == 'gzip' || contentEncoding == 'x-gzip') {
        decodedBytes = gzip.decode(rawBodyBytes);
      } else if (contentEncoding == 'deflate') {
        decodedBytes = zlib.decode(rawBodyBytes);
      } else {
        decodedBytes = rawBodyBytes;
      }

      final String text = utf8.decode(decodedBytes, allowMalformed: true);
      if (isYouTubeJson) {
        final String? cleanedJson = YouTubeJsonPruner.pruneJsonString(text);
        if (cleanedJson == null) {
          return null;
        }
        _prunedJsonResponses++;
        _notifyStats();
        return (
          bytes: Uint8List.fromList(utf8.encode(cleanedJson)),
          cspNonce: null,
        );
      }

      if (isHtml) {
        final String? existingCsp = resHead.joinedHeaders('content-security-policy');
        final ({String html, String? nonceToAllow}) res =
            HtmlAdFilterEngine.filterHtml(
          host: host,
          rawHtml: text,
          existingCsp: existingCsp,
        );
        if (res.nonceToAllow != null) {
          _injectedHtmlPages++;
          _notifyStats();
          return (
            bytes: Uint8List.fromList(utf8.encode(res.html)),
            cspNonce: res.nonceToAllow,
          );
        }
      }
    } catch (_) {
      // در صورت خطای decode هرگز پاسخ کاربر را خراب نمی کنیم و خام می فرستیم.
    }
    return null;
  }

  Uint8List _rebuildResponseHeaders(
    _ParsedHttpHead resHead, {
    required int newBodyLength,
    String? cspNonce,
  }) {
    final StringBuffer sb = StringBuffer()..write('${resHead.startLine}\r\n');
    for (final MapEntry<String, String> h in resHead.headers) {
      final String lk = h.key.toLowerCase();
      if (lk == 'content-length' ||
          lk == 'transfer-encoding' ||
          lk == 'content-encoding') {
        continue;
      }
      if (lk == 'content-security-policy' && cspNonce != null) {
        final String patched =
            HtmlAdFilterEngine.patchCspHeader(h.value, cspNonce) ?? h.value;
        sb.write('Content-Security-Policy: $patched\r\n');
        continue;
      }
      sb.write('${h.key}: ${h.value}\r\n');
    }
    sb.write('Content-Length: $newBodyLength\r\n\r\n');
    return Uint8List.fromList(utf8.encode(sb.toString()));
  }

  void _writeUnmodifiedResponse(
    IOSink sink,
    _ParsedHttpHead resHead,
    Uint8List bodyBytes,
  ) {
    final bool isChunked =
        (resHead.firstHeader('transfer-encoding') ?? '').toLowerCase().contains('chunked');
    if (!isChunked) {
      sink.add(resHead.rawHeaderBytes);
      if (bodyBytes.isNotEmpty) {
        sink.add(bodyBytes);
      }
      return;
    }
    // تبدیل امن پاسخ chunked بافرشده به Content-Length مشخص روی loopback
    final StringBuffer sb = StringBuffer()..write('${resHead.startLine}\r\n');
    for (final MapEntry<String, String> h in resHead.headers) {
      final String lk = h.key.toLowerCase();
      if (lk == 'content-length' || lk == 'transfer-encoding') continue;
      sb.write('${h.key}: ${h.value}\r\n');
    }
    sb.write('Content-Length: ${bodyBytes.length}\r\n\r\n');
    sink.add(utf8.encode(sb.toString()));
    if (bodyBytes.isNotEmpty) {
      sink.add(bodyBytes);
    }
  }

  void _writeSyntheticResponse(
    IOSink sink, {
    required int statusCode,
    required String contentType,
    required String body,
    required bool closeAfter,
  }) {
    final List<int> bodyBytes = body.isEmpty ? const <int>[] : utf8.encode(body);
    final String reason = statusCode == 204 ? 'No Content' : 'OK';
    final StringBuffer sb = StringBuffer()
      ..write('HTTP/1.1 $statusCode $reason\r\n')
      ..write('X-Umbrella-Https-Filter: blocked\r\n')
      ..write('Cache-Control: no-store\r\n');
    if (contentType.isNotEmpty) {
      sb.write('Content-Type: $contentType\r\n');
    }
    if (statusCode != 204) {
      sb.write('Content-Length: ${bodyBytes.length}\r\n');
    }
    if (closeAfter) {
      sb.write('Connection: close\r\n');
    }
    sb.write('\r\n');
    sink.add(utf8.encode(sb.toString()));
    if (bodyBytes.isNotEmpty && statusCode != 204) {
      sink.add(bodyBytes);
    }
  }

  /// اتصال TCP بالادست: از طریق پورت `egressPort` (ورودی اختصاصی SOCKS5 روی
  /// `sing-box` با احراز هویت سشن) تا ترافیک عیناً از تونل VPN عبور کند و
  /// به هیچ وجه وارد حلقه بازگشتی `umbrella-https-filter` نشود.
  Future<Socket> _dialUpstreamTcp(String host, int port) async {
    if (egressPort <= 0) {
      return Socket.connect(host, port).timeout(const Duration(seconds: 12));
    }
    return _dialSocks5ViaBridge(host, port);
  }

  Future<Socket> _dialSocks5ViaBridge(String host, int port) async {
    final Socket socks = await Socket.connect(
      InternetAddress.loopbackIPv4,
      egressPort,
    ).timeout(const Duration(seconds: 8));
    final ({Socket tunnelSide, Socket tlsServerSide}) pair =
        await _createBridgePair();

    final _HttpStreamReader socksReader = _HttpStreamReader(socks);
    try {
      final bool useAuth = egressSecret.isNotEmpty;
      socks.add(
        Uint8List.fromList(
          useAuth ? <int>[0x05, 0x01, 0x02] : <int>[0x05, 0x01, 0x00],
        ),
      );
      final Uint8List greet =
          await socksReader.readExact(2).timeout(const Duration(seconds: 6));
      if (greet.length != 2 || greet[0] != 0x05) {
        throw const SocketException('Invalid SOCKS5 greeting');
      }
      if (greet[1] == 0x02) {
        final List<int> uBytes = utf8.encode(egressUsername);
        final List<int> pBytes = utf8.encode(egressSecret);
        socks.add(Uint8List.fromList(<int>[
          0x01,
          uBytes.length,
          ...uBytes,
          pBytes.length,
          ...pBytes,
        ]));
        final Uint8List authRep =
            await socksReader.readExact(2).timeout(const Duration(seconds: 6));
        if (authRep.length != 2 || authRep[1] != 0x00) {
          throw const SocketException('SOCKS5 authentication failed');
        }
      } else if (greet[1] != 0x00) {
        throw SocketException('SOCKS5 method rejected: ${greet[1]}');
      }

      // SOCKS5 CONNECT with domain name (ATYP = 0x03)
      final List<int> hostBytes = utf8.encode(host);
      if (hostBytes.isEmpty || hostBytes.length > 255) {
        throw const FormatException('Invalid SOCKS5 host length');
      }
      socks.add(Uint8List.fromList(<int>[
        0x05,
        0x01,
        0x00,
        0x03,
        hostBytes.length,
        ...hostBytes,
        (port >> 8) & 0xff,
        port & 0xff,
      ]));

      final Uint8List repHead =
          await socksReader.readExact(4).timeout(const Duration(seconds: 10));
      if (repHead.length != 4 || repHead[1] != 0x00) {
        throw SocketException(
          'SOCKS5 upstream connect failed (code ${repHead.length > 1 ? repHead[1] : -1})',
        );
      }
      final int atyp = repHead[3];
      if (atyp == 0x01) {
        await socksReader.readExact(4);
      } else if (atyp == 0x04) {
        await socksReader.readExact(16);
      } else if (atyp == 0x03) {
        final Uint8List lenB = await socksReader.readExact(1);
        if (lenB.isNotEmpty && lenB[0] > 0) {
          await socksReader.readExact(lenB[0]);
        }
      }
      await socksReader.readExact(2); // bound port

      // ارسال هر بایت اضافه (early server data) و وصل به tlsServerSide تازه
      final Uint8List leftover = socksReader.takeLeftover();
      if (leftover.isNotEmpty) {
        pair.tunnelSide.add(leftover);
      }
      _pipeDual(
        aReader: socksReader,
        aSink: socks,
        bSocket: pair.tunnelSide,
      );
      return pair.tlsServerSide;
    } catch (_) {
      await socksReader.close();
      socks.destroy();
      pair.tunnelSide.destroy();
      pair.tlsServerSide.destroy();
      rethrow;
    }
  }

  void _pipeDual({
    required _HttpStreamReader aReader,
    required Socket aSink,
    required Socket bSocket,
  }) {
    bool closed = false;
    void teardown() {
      if (closed) return;
      closed = true;
      unawaited(aReader.close());
      aSink.destroy();
      bSocket.destroy();
    }

    bSocket.listen(
      (Uint8List data) {
        try {
          aSink.add(data);
        } catch (_) {
          teardown();
        }
      },
      onError: (_) => teardown(),
      onDone: teardown,
    );

    unawaited(() async {
      try {
        await for (final Uint8List data in aReader.remainingStream()) {
          bSocket.add(data);
        }
      } catch (_) {
      } finally {
        teardown();
      }
    }());
  }

  Future<void> _pumpBidirectional({
    required _HttpStreamReader clientReader,
    required Socket clientSink,
    required Socket upstreamSocket,
  }) async {
    final Completer<void> done = Completer<void>();
    bool closed = false;
    void finish() {
      if (closed) return;
      closed = true;
      unawaited(clientReader.close());
      clientSink.destroy();
      upstreamSocket.destroy();
      if (!done.isCompleted) done.complete();
    }

    upstreamSocket.listen(
      (Uint8List chunk) {
        try {
          clientSink.add(chunk);
        } catch (_) {
          finish();
        }
      },
      onError: (_) => finish(),
      onDone: finish,
    );

    unawaited(() async {
      try {
        await for (final Uint8List chunk in clientReader.remainingStream()) {
          upstreamSocket.add(chunk);
        }
      } catch (_) {
      } finally {
        finish();
      }
    }());

    await done.future;
  }

  Future<void> _pumpTwoWayReaders({
    required _HttpStreamReader aReader,
    required IOSink aSink,
    required _HttpStreamReader bReader,
    required IOSink bSink,
  }) async {
    await Future.wait<void>(<Future<void>>[
      () async {
        try {
          await for (final Uint8List chunk in aReader.remainingStream()) {
            bSink.add(chunk);
          }
        } catch (_) {}
      }(),
      () async {
        try {
          await for (final Uint8List chunk in bReader.remainingStream()) {
            aSink.add(chunk);
          }
        } catch (_) {}
      }(),
    ]);
  }

  bool _requestHasBody(_ParsedHttpHead head) {
    final String te = (head.firstHeader('transfer-encoding') ?? '').toLowerCase();
    if (te.contains('chunked')) return true;
    final int? len = int.tryParse(head.firstHeader('content-length') ?? '');
    return len != null && len > 0;
  }

  Future<Uint8List?> _readRequestBodyIfAny(
    _HttpStreamReader reader,
    _ParsedHttpHead head,
  ) async {
    final String te = (head.firstHeader('transfer-encoding') ?? '').toLowerCase();
    if (te.contains('chunked')) {
      final ({Uint8List bytes, bool complete}) r =
          await reader.readChunked(maxBytes: 2 * 1024 * 1024);
      return r.complete ? r.bytes : null;
    }
    final int? len = int.tryParse(head.firstHeader('content-length') ?? '');
    if (len != null && len > 0) {
      if (len > 2 * 1024 * 1024) return null;
      return reader.readExact(len);
    }
    return Uint8List(0);
  }

  Future<void> _forwardRequestBody(
    _HttpStreamReader reader,
    _ParsedHttpHead head,
    IOSink sink,
  ) async {
    final String te = (head.firstHeader('transfer-encoding') ?? '').toLowerCase();
    if (te.contains('chunked')) {
      await reader.forwardRawChunked(sink);
      return;
    }
    final int? len = int.tryParse(head.firstHeader('content-length') ?? '');
    if (len != null && len > 0) {
      await reader.forwardExact(len, sink);
    }
  }

  Future<void> _streamResponseBody(
    _HttpStreamReader reader,
    _ParsedHttpHead head,
    IOSink sink,
  ) async {
    final String te = (head.firstHeader('transfer-encoding') ?? '').toLowerCase();
    if (te.contains('chunked')) {
      await reader.forwardRawChunked(sink);
      return;
    }
    final int? len = int.tryParse(head.firstHeader('content-length') ?? '');
    if (len != null) {
      if (len > 0) {
        await reader.forwardExact(len, sink);
      }
      return;
    }
    await for (final Uint8List chunk in reader.remainingStream()) {
      sink.add(chunk);
    }
  }

  Future<({Uint8List bytes, bool complete, bool wasChunked, bool readToEof})>
      _readBufferedBody(
    _HttpStreamReader reader,
    _ParsedHttpHead head, {
    required int maxBytes,
  }) async {
    final String te = (head.firstHeader('transfer-encoding') ?? '').toLowerCase();
    if (te.contains('chunked')) {
      final ({Uint8List bytes, bool complete}) r =
          await reader.readChunked(maxBytes: maxBytes);
      return (
        bytes: r.bytes,
        complete: r.complete,
        wasChunked: true,
        readToEof: false,
      );
    }
    final int? len = int.tryParse(head.firstHeader('content-length') ?? '');
    if (len != null) {
      if (len == 0) {
        return (
          bytes: Uint8List(0),
          complete: true,
          wasChunked: false,
          readToEof: false,
        );
      }
      if (len > maxBytes) {
        return (
          bytes: Uint8List(0),
          complete: false,
          wasChunked: false,
          readToEof: false,
        );
      }
      final Uint8List data = await reader.readExact(len);
      return (
        bytes: data,
        complete: data.length == len,
        wasChunked: false,
        readToEof: false,
      );
    }
    final BytesBuilder bb = BytesBuilder(copy: false);
    await for (final Uint8List chunk in reader.remainingStream()) {
      if (bb.length + chunk.length > maxBytes) {
        return (
          bytes: bb.takeBytes(),
          complete: false,
          wasChunked: false,
          readToEof: true,
        );
      }
      bb.add(chunk);
    }
    return (
      bytes: bb.takeBytes(),
      complete: true,
      wasChunked: false,
      readToEof: true,
    );
  }

  static bool _wantsConnectionClose(_ParsedHttpHead head) {
    final String conn = (head.firstHeader('connection') ?? '').toLowerCase();
    return conn.contains('close') ||
        head.startLine.toUpperCase().startsWith('HTTP/1.0');
  }

  static int _parseStatusCode(String startLine) {
    final List<String> parts = startLine.split(RegExp(r'\s+'));
    if (parts.length < 2) return 0;
    return int.tryParse(parts[1]) ?? 0;
  }

  static ({String host, int port}) _parseHostPort(
    String authority, {
    required int defaultPort,
  }) {
    final String trimmed = authority.trim();
    if (trimmed.startsWith('[')) {
      final int closeBracket = trimmed.indexOf(']');
      if (closeBracket > 0) {
        final String host = trimmed.substring(1, closeBracket);
        final String rest = trimmed.substring(closeBracket + 1);
        if (rest.startsWith(':')) {
          final int? p = int.tryParse(rest.substring(1));
          if (p != null && p > 0 && p <= 65535) {
            return (host: host, port: p);
          }
        }
        return (host: host, port: defaultPort);
      }
    }
    final int colon = trimmed.lastIndexOf(':');
    if (colon > 0) {
      final int? p = int.tryParse(trimmed.substring(colon + 1));
      if (p != null && p > 0 && p <= 65535) {
        return (host: trimmed.substring(0, colon), port: p);
      }
    }
    return (host: trimmed, port: defaultPort);
  }

  void _notifyStats() {
    onStatsChanged?.call(stats);
  }
}

class _ParsedHttpHead {
  const _ParsedHttpHead({
    required this.startLine,
    required this.headers,
    required this.rawHeaderBytes,
  });

  final String startLine;
  final List<MapEntry<String, String>> headers;
  final Uint8List rawHeaderBytes;

  String? firstHeader(String name) {
    final String target = name.toLowerCase();
    for (final MapEntry<String, String> h in headers) {
      if (h.key.toLowerCase() == target) {
        return h.value;
      }
    }
    return null;
  }

  String? joinedHeaders(String name, {String separator = '; '}) {
    final String target = name.toLowerCase();
    final List<String> values = <String>[
      for (final MapEntry<String, String> h in headers)
        if (h.key.toLowerCase() == target && h.value.isNotEmpty) h.value,
    ];
    return values.isEmpty ? null : values.join(separator);
  }
}

class _HttpStreamReader {
  _HttpStreamReader(Stream<Uint8List> stream)
      : _iterator = StreamIterator<Uint8List>(stream);

  final StreamIterator<Uint8List> _iterator;
  final List<int> _buf = <int>[];
  bool _eof = false;

  Future<bool> _pull() async {
    if (_eof) return false;
    final bool ok = await _iterator.moveNext();
    if (!ok) {
      _eof = true;
      return false;
    }
    final Uint8List chunk = _iterator.current;
    if (chunk.isNotEmpty) {
      _buf.addAll(chunk);
    }
    return true;
  }

  Uint8List takeLeftover() {
    if (_buf.isEmpty) return Uint8List(0);
    final Uint8List out = Uint8List.fromList(_buf);
    _buf.clear();
    return out;
  }

  Stream<Uint8List> remainingStream() async* {
    if (_buf.isNotEmpty) {
      yield takeLeftover();
    }
    while (await _pull()) {
      if (_buf.isNotEmpty) {
        yield takeLeftover();
      }
    }
  }

  Future<_ParsedHttpHead?> readHeaders({int maxBytes = 65536}) async {
    while (true) {
      final int endIdx = _findHeaderEnd(_buf);
      if (endIdx > 0) {
        final Uint8List raw = Uint8List.fromList(_buf.sublist(0, endIdx));
        _buf.removeRange(0, endIdx);
        return _parseHead(raw);
      }
      if (_buf.length >= maxBytes) {
        return null;
      }
      if (!await _pull()) {
        return null;
      }
    }
  }

  Future<Uint8List> readExact(int count) async {
    if (count <= 0) return Uint8List(0);
    while (_buf.length < count) {
      if (!await _pull()) {
        break;
      }
    }
    final int take = count <= _buf.length ? count : _buf.length;
    final Uint8List out = Uint8List.fromList(_buf.sublist(0, take));
    _buf.removeRange(0, take);
    return out;
  }

  Future<String?> _readLineCrlf() async {
    while (true) {
      for (int i = 0; i < _buf.length; i++) {
        if (_buf[i] == 0x0A /* \n */) {
          final int lineEnd =
              (i > 0 && _buf[i - 1] == 0x0D /* \r */) ? i - 1 : i;
          final String line =
              utf8.decode(_buf.sublist(0, lineEnd), allowMalformed: true);
          _buf.removeRange(0, i + 1);
          return line;
        }
      }
      if (_buf.length > 8192) return null;
      if (!await _pull()) return null;
    }
  }

  Future<({Uint8List bytes, bool complete})> readChunked({
    required int maxBytes,
  }) async {
    final BytesBuilder out = BytesBuilder(copy: false);
    while (true) {
      final String? sizeLine = await _readLineCrlf();
      if (sizeLine == null) {
        return (bytes: out.takeBytes(), complete: false);
      }
      final String hexPart = sizeLine.split(';').first.trim();
      final int? chunkSize = int.tryParse(hexPart, radix: 16);
      if (chunkSize == null || chunkSize < 0) {
        return (bytes: out.takeBytes(), complete: false);
      }
      if (chunkSize == 0) {
        // خواندن trailerها تا خط خالی
        while (true) {
          final String? tr = await _readLineCrlf();
          if (tr == null || tr.isEmpty) break;
        }
        return (bytes: out.takeBytes(), complete: true);
      }
      if (out.length + chunkSize > maxBytes) {
        return (bytes: out.takeBytes(), complete: false);
      }
      final Uint8List data = await readExact(chunkSize);
      if (data.length != chunkSize) {
        return (bytes: out.takeBytes(), complete: false);
      }
      out.add(data);
      // مصرف CRLF پایان هر chunk
      await _readLineCrlf();
    }
  }

  Future<void> forwardExact(int count, IOSink sink) async {
    int remaining = count;
    while (remaining > 0) {
      if (_buf.isEmpty && !await _pull()) {
        break;
      }
      if (_buf.isNotEmpty) {
        final int take = remaining <= _buf.length ? remaining : _buf.length;
        sink.add(Uint8List.fromList(_buf.sublist(0, take)));
        _buf.removeRange(0, take);
        remaining -= take;
      }
    }
  }

  Future<void> forwardRawChunked(IOSink sink) async {
    while (true) {
      final String? sizeLine = await _readLineCrlf();
      if (sizeLine == null) break;
      final String hexPart = sizeLine.split(';').first.trim();
      final int? chunkSize = int.tryParse(hexPart, radix: 16);
      if (chunkSize == null || chunkSize < 0) break;
      sink.add(utf8.encode('$sizeLine\r\n'));
      if (chunkSize == 0) {
        while (true) {
          final String? tr = await _readLineCrlf();
          if (tr == null) break;
          sink.add(utf8.encode('$tr\r\n'));
          if (tr.isEmpty) break;
        }
        break;
      }
      await forwardExact(chunkSize, sink);
      final String? trail = await _readLineCrlf();
      if (trail != null) {
        sink.add(utf8.encode('$trail\r\n'));
      }
    }
  }

  Future<void> close() async {
    try {
      await _iterator.cancel();
    } catch (_) {}
  }

  static int _findHeaderEnd(List<int> buf) {
    for (int i = 0; i <= buf.length - 4; i++) {
      if (buf[i] == 0x0D &&
          buf[i + 1] == 0x0A &&
          buf[i + 2] == 0x0D &&
          buf[i + 3] == 0x0A) {
        return i + 4;
      }
    }
    for (int i = 0; i <= buf.length - 2; i++) {
      if (buf[i] == 0x0A && buf[i + 1] == 0x0A) {
        return i + 2;
      }
    }
    return -1;
  }

  static _ParsedHttpHead? _parseHead(Uint8List raw) {
    final String text = utf8.decode(raw, allowMalformed: true);
    final List<String> lines = text.split(RegExp(r'\r?\n'));
    if (lines.isEmpty || lines.first.trim().isEmpty) return null;
    final String startLine = lines.first.trimRight();
    final List<MapEntry<String, String>> headers =
        <MapEntry<String, String>>[];
    for (int i = 1; i < lines.length; i++) {
      final String line = lines[i];
      if (line.isEmpty) break;
      final int colon = line.indexOf(':');
      if (colon <= 0) continue;
      headers.add(
        MapEntry<String, String>(
          line.substring(0, colon).trim(),
          line.substring(colon + 1).trim(),
        ),
      );
    }
    return _ParsedHttpHead(
      startLine: startLine,
      headers: headers,
      rawHeaderBytes: raw,
    );
  }
}
