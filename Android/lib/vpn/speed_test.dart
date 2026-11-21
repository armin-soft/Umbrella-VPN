import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class SpeedSample {
  const SpeedSample({required this.bytes, required this.elapsed});
  final int bytes;
  final Duration elapsed;
  double get bytesPerSecond => elapsed.inMicroseconds <= 0 ? 0 : bytes * 1000000 / elapsed.inMicroseconds;
  double get megabitsPerSecond => bytesPerSecond * 8 / 1000000;
}
class SpeedTestResult {
  const SpeedTestResult({required this.download, required this.upload, required this.measuredAt});
  final SpeedSample download, upload;
  final DateTime measuredAt;
}
class SpeedTestCancelled implements Exception {
  const SpeedTestCancelled();
}

/// Bounded active measurement, never falls back to a direct connection.
/// Only synthetic bytes are uploaded; certificate validation stays enabled.
class SpeedTestRunner {
  static const int downloadBytes = 4000000;
  static const int uploadBytes = 2000000;
  static final Uri downloadUrl = Uri.parse('https://speed.cloudflare.com/__down?bytes=$downloadBytes');
  static final Uri uploadUrl = Uri.parse('https://speed.cloudflare.com/__up');
  final Set<HttpClient> _clients = <HttpClient>{};
  bool _cancelled = false;
  bool _running = false;

  void cancel() {
    _cancelled = true;
    for (final HttpClient client in _clients.toList()) { client.close(force: true); }
    _clients.clear();
  }
  void _checkCancelled() { if (_cancelled) throw const SpeedTestCancelled(); }

  Future<SpeedTestResult> run({
    required int proxyPort,
    void Function(String phase)? onPhase,
    // Explicit dependency injection for loopback tests; the UI cannot supply URLs.
    Uri? downloadEndpoint, Uri? uploadEndpoint,
    int downloadLimit = downloadBytes, int uploadLimit = uploadBytes,
    Duration timeout = const Duration(seconds: 20),
    String proxyUser = '',
    String proxyPassword = '',
    bool allowDirectTunnel = false,
  }) async {
    if (_running || _cancelled) throw StateError('Runner is active or cancelled');
    final bool useDirect = allowDirectTunnel && proxyPort == 0;
    if ((!useDirect && proxyPort <= 0) || proxyPort < 0 || proxyPort > 65535) {
      throw ArgumentError.value(proxyPort, 'proxyPort');
    }
    if (downloadLimit <= 0 || downloadLimit > downloadBytes || uploadLimit <= 0 || uploadLimit > uploadBytes) throw ArgumentError('Invalid byte budget');
    _running = true;
    _proxyBasic = proxyPort > 0 && proxyUser.isNotEmpty && proxyPassword.isNotEmpty
        ? 'Basic ${base64Encode(utf8.encode('$proxyUser:$proxyPassword'))}'
        : '';
    _proxyUser = proxyUser;
    _proxyPassword = proxyPassword;
    try {
      onPhase?.call('download');
      final SpeedSample down = await _download(downloadEndpoint ?? downloadUrl, proxyPort, downloadLimit, timeout);
      _checkCancelled();
      onPhase?.call('upload');
      final SpeedSample up = await _upload(uploadEndpoint ?? uploadUrl, proxyPort, uploadLimit, timeout);
      _checkCancelled();
      return SpeedTestResult(download: down, upload: up, measuredAt: DateTime.now());
    } finally {
      _running = false;
      _proxyBasic = '';
      _proxyUser = '';
      _proxyPassword = '';
    }
  }

  String _proxyBasic = '';
  String _proxyUser = '';
  String _proxyPassword = '';

  HttpClient _client(int proxyPort, Duration timeout) {
    _checkCancelled();
    final HttpClient client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = timeout
      ..findProxy = (Uri _) =>
          proxyPort > 0 ? 'PROXY 127.0.0.1:$proxyPort' : 'DIRECT';
    if (proxyPort > 0 && _proxyUser.isNotEmpty && _proxyPassword.isNotEmpty) {
      final HttpClientBasicCredentials creds =
          HttpClientBasicCredentials(_proxyUser, _proxyPassword);
      client.addProxyCredentials('127.0.0.1', proxyPort, '', creds);
      client.authenticateProxy =
          (String host, int port, String scheme, String? realm) async {
        client.addProxyCredentials(host, port, realm ?? '', creds);
        return true;
      };
    }
    _clients.add(client);
    return client;
  }
  void _close(HttpClient client) { _clients.remove(client); client.close(force: true); }
  void _headers(HttpClientRequest request) {
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    if (_proxyBasic.isNotEmpty && request.uri.scheme == 'http') {
      request.headers.set('Proxy-Authorization', _proxyBasic);
    }
  }
  void _checkStatus(HttpClientResponse response) {
    if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('Speed endpoint HTTP ${response.statusCode}');
    final String? encoding = response.headers.value(HttpHeaders.contentEncodingHeader);
    if (encoding != null && encoding != 'identity') throw const HttpException('Compressed speed sample rejected');
  }
  Future<SpeedSample> _download(Uri url, int proxyPort, int limit, Duration timeout) async {
    final HttpClient client = _client(proxyPort, timeout);
    try {
      return await (() async {
        final HttpClientRequest request = await client.getUrl(url);
        _headers(request);
        final Stopwatch watch = Stopwatch()..start();
        final HttpClientResponse response = await request.close();
        _checkStatus(response);
        int bytes = 0;
        await for (final List<int> chunk in response) {
          _checkCancelled();
          bytes += chunk.length;
          if (bytes > limit) throw const HttpException('Download exceeds byte budget');
        }
        watch.stop();
        if (bytes != limit) throw const HttpException('Incomplete download sample');
        return SpeedSample(bytes: bytes, elapsed: watch.elapsed);
      })().timeout(timeout);
    } catch (_) { _checkCancelled(); rethrow; }
    finally { _close(client); }
  }
  Future<SpeedSample> _upload(Uri url, int proxyPort, int limit, Duration timeout) async {
    final HttpClient client = _client(proxyPort, timeout);
    try {
      return await (() async {
        final HttpClientRequest request = await client.postUrl(url);
        _headers(request);
        request.headers.contentType = ContentType.binary;
        request.contentLength = limit;
        final Stopwatch watch = Stopwatch()..start();
        final Random random = Random.secure();
        final Uint8List block = Uint8List.fromList(List<int>.generate(16384, (_) => random.nextInt(256)));
        Stream<List<int>> data() async* {
          int sent = 0;
          while (sent < limit) {
            _checkCancelled();
            final int count = min(block.length, limit - sent);
            yield Uint8List.sublistView(block, 0, count);
            sent += count;
          }
        }
        await request.addStream(data());
        final HttpClientResponse response = await request.close();
        _checkStatus(response);
        int received = 0;
        await for (final List<int> chunk in response) {
          _checkCancelled();
          received += chunk.length;
          if (received > 65536) throw const HttpException('Upload acknowledgement exceeds limit');
        }
        watch.stop();
        return SpeedSample(bytes: limit, elapsed: watch.elapsed);
      })().timeout(timeout);
    } catch (_) { _checkCancelled(); rethrow; }
    finally { _close(client); }
  }
}
