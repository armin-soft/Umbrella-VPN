import 'dart:io';
import 'dart:isolate';

import 'package:basic_utils/basic_utils.dart';

/// App-private identity for the mobile core's mutual TLS endpoint.
/// The certificate must exist under basePath/grpc/client.crt before core setup.
class CoreClientIdentity {
  const CoreClientIdentity({required this.certificate, required this.privateKey});

  final String certificate;
  final String privateKey;

  static final Map<String, Future<CoreClientIdentity>> _inFlight = {};

  /// [basePath] must be an app-private directory, not external/shared storage.
  static Future<CoreClientIdentity> loadOrCreate(Directory basePath) {
    final path = basePath.absolute.path;
    final existing = _inFlight[path];
    if (existing != null) return existing;
    final future = _loadOrCreate(Directory(path));
    _inFlight[path] = future;
    future.then<void>((_) => _inFlight.remove(path),
        onError: (Object _, StackTrace __) { _inFlight.remove(path); });
    return future;
  }

  static Future<CoreClientIdentity> _loadOrCreate(Directory basePath) async {
    final folder = Directory('${basePath.path}/grpc');
    final cert = File('${folder.path}/client.crt');
    final key = File('${folder.path}/client.key');
    try {
      if (await cert.exists() && await key.exists()) {
        final identity = CoreClientIdentity(
          certificate: await cert.readAsString(),
          privateKey: await key.readAsString(),
        );
        if (identity._valid()) return identity;
      }
    } on FileSystemException {
      // Regenerate if a previous write was interrupted or inaccessible.
    }
    final identity = await Isolate.run(_generate);
    await folder.create(recursive: true);
    // Write the key first. If interrupted, the pair fails validation next time.
    await _replace(key, identity.privateKey);
    await _replace(cert, identity.certificate);
    return identity;
  }

  static CoreClientIdentity _generate() {
    final pair = CryptoUtils.generateRSAKeyPair();
    final privateKey = pair.privateKey as RSAPrivateKey;
    final publicKey = pair.publicKey as RSAPublicKey;
    final csr = X509Utils.generateRsaCsrPem(
      {'CN': 'UmbrellaCoreClient'}, privateKey, publicKey,
    );
    return CoreClientIdentity(
      certificate: X509Utils.generateSelfSignedCertificate(
        privateKey, csr, 3650, extKeyUsage: [ExtendedKeyUsage.CLIENT_AUTH],
      ),
      privateKey: CryptoUtils.encodeRSAPrivateKeyToPem(privateKey),
    );
  }

  bool _valid() {
    try {
      final parsed = X509Utils.x509CertificateFromPem(certificate);
      final expiry = parsed.tbsCertificate?.validity.notAfter;
      if (expiry == null || !expiry.isAfter(DateTime.now().add(const Duration(days: 30)))) {
        return false;
      }
      // Check that both PEMs parse and that the certificate matches the key.
      final context = SecurityContext(withTrustedRoots: false);
      context.useCertificateChainBytes(certificate.codeUnits);
      context.usePrivateKeyBytes(privateKey.codeUnits);
      return true;
    } on Object {
      return false;
    }
  }

  static Future<void> _replace(File file, String content) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(content, flush: true);
    await temporary.rename(file.path);
  }
}
