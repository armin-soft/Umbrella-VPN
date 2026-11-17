import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Positive evidence requires a TLS-verified response with the expected body.
/// Redirects, captive portal pages, open sockets and log messages are not proof.
class VerifiedProbe {
  const VerifiedProbe._();
  static const Map<String, String> endpoints = <String, String>{
    'https://cp.cloudflare.com/generate_204': '',
    'https://www.gstatic.com/generate_204': '',
    'https://clients3.google.com/generate_204': '',
    'https://detectportal.firefox.com/success.txt': 'success\n',
  };

  static bool matches(int status, String body, String expected) =>
      expected.isEmpty ? status == 204 && body.isEmpty : status == 200 && body == expected;

  static Future<bool> check({
    required int proxyPort,
    int minimumSuccesses = 1,
    Duration timeout = const Duration(seconds: 8),
    Map<String, String> targets = endpoints,
  }) async {
    if (minimumSuccesses < 1 || targets.length < minimumSuccesses || proxyPort < 0 || proxyPort > 65535) return false;
    final List<HttpClient> clients = <HttpClient>[];
    final Completer<bool> done = Completer<bool>();
    int pending = targets.length;
    int successes = 0;
    Future<void> probe(String url, String expected) async {
      final Uri? uri = Uri.tryParse(url);
      // Plain HTTP is permitted only for local automated test servers.
      if (uri == null || (uri.scheme != 'https' && !(uri.scheme == 'http' && InternetAddress.tryParse(uri.host)?.isLoopback == true))) {
        pending--;
        if (pending == 0 && !done.isCompleted) done.complete(false);
        return;
      }
      final HttpClient client = HttpClient()..connectionTimeout = timeout;
      clients.add(client);
      client.findProxy = (Uri _) => proxyPort > 0 ? 'PROXY 127.0.0.1:$proxyPort' : 'DIRECT';
      try {
        final HttpClientRequest request = await client.getUrl(uri);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        final HttpClientResponse response = await request.close();
        final List<int> body = <int>[];
        await for (final List<int> chunk in response) {
          body.addAll(chunk);
          if (body.length > 1024) return;
        }
        if (matches(response.statusCode, utf8.decode(body, allowMalformed: true), expected)) successes++;
        if (successes >= minimumSuccesses && !done.isCompleted) done.complete(true);
      } on Exception {
        // The other independent endpoints may still answer.
      } finally {
        client.close(force: true);
        pending--;
        if (pending == 0 && !done.isCompleted) done.complete(false);
      }
    }
    for (final MapEntry<String, String> endpoint in targets.entries) { unawaited(probe(endpoint.key, endpoint.value)); }
    try { return await done.future.timeout(timeout, onTimeout: () => false); }
    finally { for (final HttpClient client in clients) { client.close(force: true); } }
  }
}
