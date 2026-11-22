import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Consume sing-box warnings from the authenticated, loopback-only Clash API.
/// Raw entries (which can contain credentials and server addresses) are never
/// returned to callers; only fixed categories are emitted.
String? classifyMonitorFailure(String message) {
  final lower = message.toLowerCase();
  final marker = lower.indexOf(': failed:');
  if (!lower.contains('monitoring result ') || marker < 0) {
    return lower.contains('url test did not return') ? 'TIMEOUT' : null;
  }
  final error = lower.substring(marker + ': failed:'.length);
  if (error.contains('certificate') || error.contains('x509')) return 'CERTIFICATE';
  if (error.contains('tls') || error.contains('handshake')) return 'TLS';
  if (error.contains('no such host') || error.contains('dns') || error.contains('lookup ')) return 'DNS';
  if (error.contains('timeout') || error.contains('deadline exceeded')) return 'TIMEOUT';
  if (error.contains('connection refused')) return 'REFUSED';
  if (error.contains('connection reset')) return 'RESET';
  if (error.contains('network is unreachable') || error.contains('no route to host')) return 'UNREACHABLE';
  return 'OTHER';
}

class MobileMonitorLogs {
  MobileMonitorLogs({required this.port, required this.secret, required this.onCategory, required this.onStatus});
  final int port;
  final String secret;
  final void Function(String) onCategory;
  final void Function(String) onStatus;
  HttpClient? _client;
  WebSocket? _socket;
  bool _closed = false;

  Future<void> start() async {
    if (_closed || _client != null || port < 1 || port > 65535 || secret.length < 43) return;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    client.findProxy = (_) => 'DIRECT';
    _client = client;
    try {
      final socket = await WebSocket.connect(
        'ws://127.0.0.1:$port/logs?level=warning',
        headers: {HttpHeaders.authorizationHeader: 'Bearer $secret'},
        customClient: client,
      ).timeout(const Duration(seconds: 5));
      if (_closed) { socket.close(); return; }
      _socket = socket;
      onStatus('connected');
      socket.listen((event) {
        if (_closed || event is! String || event.length > 65536) return;
        try {
          final decoded = jsonDecode(event);
          if (decoded is! Map || decoded['payload'] is! String) return;
          final category = classifyMonitorFailure(decoded['payload'] as String);
          if (category != null) onCategory(category);
        } on FormatException {
          // Never report the raw payload.
        }
      }, onError: (Object _) { if (!_closed) onStatus('failed'); },
          onDone: () { if (!_closed) onStatus('closed'); });
    } catch (_) {
      if (!_closed) onStatus('unavailable');
      client.close(force: true);
    }
  }

  void close() {
    _closed = true;
    _socket?.close();
    _socket = null;
    _client?.close(force: true);
    _client = null;
  }
}
