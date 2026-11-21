import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/umbrella_core/client_identity.dart';
import 'package:umbrella_vpn/umbrella_core/mtls_credentials.dart';

void main() {
  test('creates and reuses a private core identity', () async {
    final dir = await Directory.systemTemp.createTemp('umbrella-identity-');
    addTearDown(() => dir.delete(recursive: true));
    final values = await Future.wait([
      CoreClientIdentity.loadOrCreate(dir),
      CoreClientIdentity.loadOrCreate(dir),
    ]);
    expect(values[0].certificate, values[1].certificate);
    expect(await File('${dir.path}/grpc/client.crt').readAsString(), values[0].certificate);
    expect(await File('${dir.path}/grpc/client.key').readAsString(), values[0].privateKey);
    final loaded = await CoreClientIdentity.loadOrCreate(dir);
    expect(loaded.certificate, values[0].certificate);
    final credentials = CoreMtlsCredentials(
      serverCertificatePem: loaded.certificate,
      clientCertificatePem: loaded.certificate,
      clientPrivateKeyPem: loaded.privateKey,
    );
    expect(credentials.isSecure, isTrue);
  });

  test('replaces a mismatched but valid private key', () async {
    final dir = await Directory.systemTemp.createTemp('umbrella-identity-');
    final otherDir = await Directory.systemTemp.createTemp('umbrella-identity-other-');
    addTearDown(() => dir.delete(recursive: true));
    addTearDown(() => otherDir.delete(recursive: true));
    final original = await CoreClientIdentity.loadOrCreate(dir);
    final other = await CoreClientIdentity.loadOrCreate(otherDir);
    await File('${dir.path}/grpc/client.key').writeAsString(other.privateKey);
    final recovered = await CoreClientIdentity.loadOrCreate(dir);
    expect(recovered.certificate, isNot(original.certificate));
    expect(recovered.privateKey, isNot(other.privateKey));
  });

  test('replaces a corrupted key before using the identity', () async {
    final dir = await Directory.systemTemp.createTemp('umbrella-identity-');
    addTearDown(() => dir.delete(recursive: true));
    final original = await CoreClientIdentity.loadOrCreate(dir);
    await File('${dir.path}/grpc/client.key').writeAsString('invalid');
    final recovered = await CoreClientIdentity.loadOrCreate(dir);
    expect(recovered.certificate, isNot(original.certificate));
    expect(recovered.privateKey, contains('PRIVATE KEY'));
  });
}
