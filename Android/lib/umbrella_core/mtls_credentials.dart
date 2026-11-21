import 'dart:convert';
import 'dart:io';

import 'package:grpc/grpc.dart';

/// Mutual TLS for the local core. Only the provided core certificate is trusted;
/// the private key never leaves the app process. Native setup must register the
/// matching client certificate with the core before this channel is used.
class CoreMtlsCredentials extends ChannelCredentials {
  CoreMtlsCredentials._(this._context)
      : super.secure(authority: '127.0.0.1');

  factory CoreMtlsCredentials({
    required String serverCertificatePem,
    required String clientCertificatePem,
    required String clientPrivateKeyPem,
  }) {
    if (!serverCertificatePem.contains('-----BEGIN CERTIFICATE-----') ||
        !clientCertificatePem.contains('-----BEGIN CERTIFICATE-----') ||
        !clientPrivateKeyPem.contains('PRIVATE KEY-----')) {
      throw ArgumentError('Core mTLS credentials must be PEM-encoded.');
    }
    final context = SecurityContext(withTrustedRoots: false);
    context.setAlpnProtocols(supportedAlpnProtocols, false);
    context.setTrustedCertificatesBytes(utf8.encode(serverCertificatePem));
    context.useCertificateChainBytes(utf8.encode(clientCertificatePem));
    context.usePrivateKeyBytes(utf8.encode(clientPrivateKeyPem));
    return CoreMtlsCredentials._(context);
  }

  final SecurityContext _context;

  @override
  SecurityContext get securityContext => _context;

  @override
  String? get authority => '127.0.0.1';

  @override
  bool get isSecure => true;
}
