import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/platform/services.dart';
import 'package:umbrella_vpn/state/update_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const digest = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
  test('APK update requires a valid digest and matches downloaded bytes', () async {
    final dir = await Directory.systemTemp.createTemp('umbrella-update-test-');
    addTearDown(() => dir.delete(recursive: true));
    var requests = 0;
    final service = UpdateService(client: MockClient((request) async {
      requests++;
      return http.Response('abc', 200);
    }));
    Future<File?> fetch(String sha, {String url = 'https://example.test/UmbrellaVPN.apk'}) => service.download(
      UpdateInfo(version: '1.0.1', url: url, sha256: sha),
      targetDir: dir, onProgress: (_, __, ___) {},
    );
    expect(await fetch(''), isNull);
    expect(await fetch('bad'), isNull);
    expect(await fetch(digest, url: 'http://example.test/UmbrellaVPN.apk'), isNull);
    expect(requests, 0);
    final verified = await fetch(digest);
    expect(await verified?.readAsString(), 'abc');
    expect(requests, 1);
    expect(await fetch('0' * 64), isNull);
    expect(UpdateController, isNotNull);
  });
}
