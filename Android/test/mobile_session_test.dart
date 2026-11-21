import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/vpn/mobile_session.dart';

class FakeBackend implements MobileVpnBackend {
  bool permission = true;
  bool verified = true;
  bool failStop = false;
  int starts = 0;
  int stops = 0;
  Completer<void>? configuring;
  bool failConfiguration = false;

  @override
  Future<bool> requestPermission() async => permission;
  @override
  Future<void> startService() async { starts++; }
  @override
  Future<void> configureAndStart() async {
    await configuring?.future;
    if (failConfiguration) throw const MobileVpnFailure('پردازش تنظیمات سرور ناموفق بود.');
  }
  @override
  Future<bool> verifyTraffic() async => verified;
  @override
  Future<void> stopService() async {
    stops++;
    if (failStop) throw StateError('stop failed');
  }
}

void main() {
  test('a session is connected only after traffic verification', () async {
    final backend = FakeBackend()..verified = false;
    final session = MobileVpnSession(backend);
    expect(await session.connect(), isFalse);
    expect(session.state, MobileSessionState.failed);
    expect(session.error, contains('ترافیک'));
    expect(backend.stops, 1);
  });

  test('reports a safe stage-specific failure and cleans up', () async {
    final backend = FakeBackend()..failConfiguration = true;
    final session = MobileVpnSession(backend);
    expect(await session.connect(), isFalse);
    expect(session.error, 'پردازش تنظیمات سرور ناموفق بود.');
    expect(backend.stops, 1);
  });

  test('permission denial does not start the service', () async {
    final backend = FakeBackend()..permission = false;
    final session = MobileVpnSession(backend);
    expect(await session.connect(), isFalse);
    expect(backend.starts, 0);
    expect(backend.stops, 0);
  });

  test('disconnect cancels an in-flight start and cleans up', () async {
    final backend = FakeBackend()..configuring = Completer<void>();
    final session = MobileVpnSession(backend);
    final connecting = session.connect();
    await Future<void>.delayed(Duration.zero);
    final disconnecting = session.disconnect();
    backend.configuring!.complete();
    expect(await connecting, isFalse);
    await disconnecting;
    expect(session.state, MobileSessionState.disconnected);
    expect(backend.stops, 1);
  });

  test('failed cleanup is not reported as disconnected', () async {
    final backend = FakeBackend()
      ..configuring = Completer<void>()
      ..failStop = true;
    final session = MobileVpnSession(backend);
    final connecting = session.connect();
    await Future<void>.delayed(Duration.zero);
    final disconnecting = session.disconnect();
    backend.configuring!.complete();
    expect(await connecting, isFalse);
    await disconnecting;
    expect(session.state, MobileSessionState.failed);
    expect(await session.connect(), isFalse);
    expect(backend.starts, 1);
    backend.failStop = false;
    await session.disconnect();
    expect(session.state, MobileSessionState.disconnected);
    expect(await session.connect(), isTrue);
  });
}
