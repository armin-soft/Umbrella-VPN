import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/vpn/speed_test.dart';
import 'package:umbrella_vpn/vpn/verified_probe.dart';

void main() {
  test('probe accepts only expected successful responses, never redirects or captive pages', () {
    expect(VerifiedProbe.matches(204, '', ''), true);
    expect(VerifiedProbe.matches(200, 'Microsoft Connect Test', 'Microsoft Connect Test'), true);
    for (final int status in <int>[200, 301, 302, 403, 500]) {
      expect(VerifiedProbe.matches(status, 'portal', ''), false);
    }
    expect(VerifiedProbe.matches(200, 'different', 'Microsoft Connect Test'), false);
  });

  test('verified probes enforce body, independent successes and whole-request timeout', () async {
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((HttpRequest request) async {
      try {
        if (request.uri.path == '/ok') {
          request.response.statusCode = 204;
        } else if (request.uri.path == '/text') {
          request.response.write('expected');
        } else if (request.uri.path == '/redirect') {
          request.response.statusCode = 302;
          request.response.headers.set('location', '/ok');
        } else if (request.uri.path == '/large') {
          request.response.write('x' * 2048);
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          request.response.statusCode = 204;
        }
        await request.response.close();
      } on Exception { /* client timed out */ }
    });
    final String base = 'http://127.0.0.1:${server.port}';
    expect(await VerifiedProbe.check(proxyPort: 0, minimumSuccesses: 2,
      targets: <String, String>{'$base/ok': '', '$base/text': 'expected', '$base/redirect': ''}), true);
    expect(await VerifiedProbe.check(proxyPort: 0, targets: <String, String>{'$base/redirect': ''}), false);
    expect(await VerifiedProbe.check(proxyPort: 0, targets: <String, String>{'$base/large': ''}), false);
    expect(await VerifiedProbe.check(proxyPort: 0, targets: <String, String>{'$base/slow': ''}, timeout: const Duration(milliseconds: 40)), false);
    expect(await VerifiedProbe.check(proxyPort: 0, targets: <String, String>{'http://not-encrypted.invalid/': ''}), false);
  });

  test('speed runner uses the proxy and accounts for download and synthetic upload', () async {
    final HttpServer proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => proxy.close(force: true));
    int uploaded = 0;
    final List<String> methods = <String>[];
    proxy.listen((HttpRequest request) async {
      methods.add(request.method);
      if (request.method == 'GET') {
        request.response.contentLength = 32768;
        request.response.add(List<int>.filled(32768, 123));
      } else {
        expect(request.headers.contentType?.mimeType, 'application/octet-stream');
        expect(request.contentLength, 16384);
        await for (final List<int> chunk in request) { uploaded += chunk.length; }
        request.response.write('ok');
      }
      await request.response.close();
    });
    final List<String> phases = <String>[];
    final SpeedTestResult result = await SpeedTestRunner().run(proxyPort: proxy.port,
      downloadEndpoint: Uri.parse('http://unresolvable.invalid/down'),
      uploadEndpoint: Uri.parse('http://unresolvable.invalid/up'),
      downloadLimit: 32768, uploadLimit: 16384, onPhase: phases.add);
    expect(result.download.bytes, 32768);
    expect(result.upload.bytes, uploaded);
    expect(uploaded, 16384);
    expect(result.download.bytesPerSecond, greaterThan(0));
    expect(result.upload.megabitsPerSecond, greaterThan(0));
    expect(methods, <String>['GET', 'POST']);
    expect(phases, <String>['download', 'upload']);
  });

  for (final int status in <int>[302, 403, 500]) {
    test('speed runner rejects HTTP $status rather than publishing a rate', () async {
      final HttpServer proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => proxy.close(force: true));
      proxy.listen((HttpRequest request) async {
        request.response.statusCode = status;
        request.response.headers.set('location', 'http://external.invalid/');
        await request.response.close();
      });
      await expectLater(SpeedTestRunner().run(proxyPort: proxy.port,
        downloadEndpoint: Uri.parse('http://test.invalid/')), throwsA(isA<HttpException>()));
    });
  }

  test('partial or excessive downloads cannot become a successful sample', () async {
    final HttpServer proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => proxy.close(force: true));
    proxy.listen((HttpRequest request) async {
      request.response.write('small');
      await request.response.close();
    });
    await expectLater(SpeedTestRunner().run(proxyPort: proxy.port, downloadLimit: 16,
      downloadEndpoint: Uri.parse('http://test.invalid/')), throwsA(isA<HttpException>()));
    await expectLater(SpeedTestRunner().run(proxyPort: proxy.port, downloadLimit: 2,
      downloadEndpoint: Uri.parse('http://test.invalid/')), throwsA(isA<HttpException>()));
  });

  test('cancel and timeout close requests and do not fall back to direct access', () async {
    final HttpServer proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => proxy.close(force: true));
    final Completer<void> requested = Completer<void>();
    proxy.listen((HttpRequest request) { if (!requested.isCompleted) requested.complete(); });
    final SpeedTestRunner runner = SpeedTestRunner();
    final Future<SpeedTestResult> result = runner.run(proxyPort: proxy.port, downloadEndpoint: Uri.parse('http://test.invalid/'));
    final Future<void> expected = expectLater(result, throwsA(isA<SpeedTestCancelled>()));
    await requested.future;
    runner.cancel();
    await expected;
    await expectLater(SpeedTestRunner().run(proxyPort: proxy.port,
      downloadEndpoint: Uri.parse('http://test.invalid/'), timeout: const Duration(milliseconds: 50)), throwsA(isA<TimeoutException>()));
    await expectLater(SpeedTestRunner().run(proxyPort: 0), throwsArgumentError);
  });

  test('units are explicit bytes/s and decimal Mbps', () {
    const SpeedSample sample = SpeedSample(bytes: 1000000, elapsed: Duration(seconds: 1));
    expect(sample.bytesPerSecond, 1000000);
    expect(sample.megabitsPerSecond, 8);
  });
}
