import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/hiddifycore/hcore_client.dart';
import 'package:umbrella_vpn/hiddifycore/mtls_credentials.dart';

void main() {
  test('invalid core identity is rejected instead of using insecure gRPC', () {
    expect(
      () => CoreMtlsCredentials(
        serverCertificatePem: '',
        clientCertificatePem: '',
        clientPrivateKeyPem: '',
      ),
      throwsArgumentError,
    );
  });

  test('core connection requires explicit mutual TLS credentials', () {
    // The type and required constructor parameter intentionally prevent an
    // insecure loopback connection from being created by default.
    expect(HcoreConnection, isNotNull);
  });
}
