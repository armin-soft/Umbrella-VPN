import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/hiddifycore/client_identity.dart';
import 'package:umbrella_vpn/hiddifycore/mtls_credentials.dart';

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
