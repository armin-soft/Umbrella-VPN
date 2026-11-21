import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/vpn/tunnel_probe.dart';

void main() {
  test('proxy response split across chunks and reused without polling', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    Socket? peer;
    var requests = 0;
    server.listen((socket) {
      peer = socket;
      socket.listen((_) async {
        requests++;
        socket.add(ascii.encode('HTTP/1.1 204 No Content\r\nX: y\r\n\r'));
        await socket.flush();
        await Future<void>.delayed(const Duration(milliseconds: 15));
        socket.add(ascii.encode('\n'));
        await socket.flush();
      });
    });
    final link = await TunnelProbe.openLink(server.port);
    expect(link, isNotNull);
    try {
      expect(await link!.fetch('http://example.test/a'), greaterThan(0));
      expect(await link.fetch('http://example.test/b'), greaterThan(0));
      expect(requests, 2);
    } finally {
      link?.close();
      peer?.destroy();
      await server.close();
    }
  });

  test('peer close immediately finishes an outstanding probe', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) => socket.listen((_) => socket.destroy()));
    final link = await TunnelProbe.openLink(server.port);
    try {
      expect(await link!.fetch('http://example.test/').timeout(const Duration(seconds: 2)), -1);
      expect(link.alive, false);
    } finally {
      link?.close();
      await server.close();
    }
  });
}
