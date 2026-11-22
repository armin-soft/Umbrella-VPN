import 'dart:convert';
import 'dart:math';

/// The pinned engine only propagates the configured monitor URL list when its
/// Clash API is enabled. Without it, its monitor silently tests only gstatic.
/// Android loopback is shared: enable it only with a fresh, unguessable secret,
/// and never log the settings or use the desktop's public fixed secret.
Map<String, dynamic> mobileCoreSettings(Map<String, dynamic> base) {
  final random = Random.secure();
  final secret = base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)))
      .replaceAll('=', '');
  final settings = Map<String, dynamic>.of(base);
  // Upstream uses Apple as its first connectivity target. A monitor cycle
  // waits for every proxy before trying the next URL; keep the other targets
  // as fallbacks, but do not make gstatic a bottleneck for a large pool.
  const apple = 'http://captive.apple.com/hotspot-detect.html';
  final urls = settings['connection-test-urls'];
  if (urls is List && urls.contains(apple)) {
    final ordered = <dynamic>[apple, ...urls.where((url) => url != apple)];
    settings['connection-test-urls'] = ordered;
    settings['connection-test-url'] = apple;
  }
  return settings
    ..['enable-clash-api'] = true
    ..['web-secret'] = secret
    ..['enable-mixed-port'] = false
    // Debug mode makes the core emit its whole configuration, including the
    // control secret and subscription credentials. Do not permit it on mobile.
    ..['log-level'] = 'warn'
    ..remove('log-level-until')
    ..remove('log-level-after');
}

/// Verify what the pinned engine actually built, without exposing its private
/// runtime config. Reject a missing secret, public listener, or absent URL list.
bool mobileRuntimeMonitoringMatches(String runtimeJson, String settingsJson) {
  try {
    final runtime = jsonDecode(runtimeJson);
    final settings = jsonDecode(settingsJson);
    if (runtime is! Map || settings is! Map) return false;
    final experimental = runtime['experimental'];
    if (experimental is! Map) return false;
    final api = experimental['clash_api'];
    final monitor = experimental['monitoring'];
    if (api is! Map || monitor is! Map) return false;
    final secret = settings['web-secret'];
    final port = settings['clash-api-port'];
    final expectedUrls = settings['connection-test-urls'];
    final actualUrls = monitor['urls'];
    if (secret is! String || secret.length < 43 || port is! int ||
        api['external_controller'] != '127.0.0.1:$port' || api['secret'] != secret ||
        expectedUrls is! List || actualUrls is! List || expectedUrls.length < 2 ||
        expectedUrls.length != actualUrls.length) return false;
    for (var i = 0; i < expectedUrls.length; i++) {
      if (expectedUrls[i] != actualUrls[i]) return false;
    }
    return true;
  } on Object {
    return false;
  }
}
