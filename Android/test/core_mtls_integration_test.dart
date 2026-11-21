import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:umbrella_vpn/umbrella_core/client_identity.dart';
import 'package:umbrella_vpn/umbrella_core/core_client.dart';
import 'package:umbrella_vpn/umbrella_core/core_messages.dart';
import 'package:umbrella_vpn/umbrella_core/mtls_credentials.dart';

class _TestTls extends ServerCredentials {
  _TestTls(this.cert, this.key, this.trustedClient);
  final String cert;
  final String key;
  final String trustedClient;
  @override
  SecurityContext get securityContext {
    final context = SecurityContext(withTrustedRoots: false);
    context.setAlpnProtocols(supportedAlpnProtocols, true);
    context.useCertificateChainBytes(utf8.encode(cert));
    context.usePrivateKeyBytes(utf8.encode(key));
    context.setTrustedCertificatesBytes(utf8.encode(trustedClient));
    return context;
  }
}

class _TestCore extends Service {
  _TestCore() {
    $addMethod(ServiceMethod<HEmpty, SystemInfo>(
      'GetSystemInfo', _get, false, false,
      (bytes) => HEmpty.fromBuffer(bytes),
      (response) => response.writeToBuffer(),
    ));
  }
  @override
  String get $name => 'hcore.Core';
  Future<SystemInfo> _get(ServiceCall call, Future<HEmpty> request) async {
    await request;
    return SystemInfo(goroutines: 7);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('local RPC requires the pinned server and the trusted client identity', () async {
    final dir = await Directory.systemTemp.createTemp('umbrella-mtls-integration-');
    addTearDown(() => dir.delete(recursive: true));
    final key = '${dir.path}/server.key';
    final cert = '${dir.path}/server.crt';
    final generated = await Process.run('openssl', [
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
      '-keyout', key, '-out', cert, '-subj', '/CN=UmbrellaTest',
      '-addext', 'subjectAltName=IP:127.0.0.1',
      '-addext', 'extendedKeyUsage=serverAuth',
    ]);
    expect(generated.exitCode, 0, reason: generated.stderr.toString());
    final serverCert = await File(cert).readAsString();
    final serverKey = await File(key).readAsString();
    final client = await CoreClientIdentity.loadOrCreate(Directory('${dir.path}/client'));
    final stranger = await CoreClientIdentity.loadOrCreate(Directory('${dir.path}/stranger'));
    final server = Server.create(services: [_TestCore()]);
    await server.serve(address: InternetAddress.loopbackIPv4, port: 0,
        security: _TestTls(serverCert, serverKey, client.certificate),
        requestClientCertificate: true, requireClientCertificate: true);
    addTearDown(() => server.shutdown());

    UmbrellaCoreConnection connection(CoreClientIdentity identity, String trustedServer) =>
        UmbrellaCoreConnection(port: server.port!, credentials: CoreMtlsCredentials(
          serverCertificatePem: trustedServer,
          clientCertificatePem: identity.certificate,
          clientPrivateKeyPem: identity.privateKey,
        ));
    final good = connection(client, serverCert);
    final untrustedClient = connection(stranger, serverCert);
    final wrongServer = connection(client, stranger.certificate);
    addTearDown(good.shutdown);
    addTearDown(untrustedClient.shutdown);
    addTearDown(wrongServer.shutdown);
    expect((await good.client.getSystemInfo().timeout(const Duration(seconds: 8))).goroutines, 7);
    await expectLater(untrustedClient.client.getSystemInfo().timeout(const Duration(seconds: 8)), throwsA(isA<Exception>()));
    await expectLater(wrongServer.client.getSystemInfo().timeout(const Duration(seconds: 8)), throwsA(isA<Exception>()));
  });
}
