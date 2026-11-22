import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/vpn/mobile_monitor_logs.dart';

void main() {
  test('authenticated loopback stream emits categories, never raw logs', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    const secret = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG';
    final received = Completer<List<String>>();
    final values = <String>[];
    final statuses = <String>[];
    final handler = server.listen((request) async {
      expect(request.uri.path, '/logs');
      expect(request.uri.queryParameters['level'], 'warning');
      expect(request.headers.value('authorization'), 'Bearer $secret');
      final socket = await WebSocketTransformer.upgrade(request);
      socket.add(jsonEncode({'type': 'warning', 'payload': 'MONITORING result private-token: failed: lookup private-server: no such host'}));
      socket.add(jsonEncode({'payload': 'MONITORING result private-token: failed: x509 invalid'}));
    });
    final logs = MobileMonitorLogs(port: server.port, secret: secret,
      onCategory: (value) { values.add(value); if (values.length == 2) received.complete(values); },
      onStatus: statuses.add);
    await logs.start();
    expect(await received.future.timeout(const Duration(seconds: 3)), ['DNS', 'CERTIFICATE']);
    expect(statuses, contains('connected'));
    logs.close();
    await handler.cancel();
    await server.close(force: true);
  });
}
