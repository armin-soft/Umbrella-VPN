import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

/// Password-protected export of the current app log only. No raw profile,
/// crash files or other directories are gathered. It is never uploaded.
class EncryptedReport {
  const EncryptedReport._();
  static const int iterations = 210000;
  static const int maxBytes = 4 * 1024 * 1024;
  static const String format = 'umbrella-log-report-v1';
  static final List<int> _aad = utf8.encode(format);

  static void _validatePassword(String password) {
    if (password.runes.length < 12 || password.runes.length > 128) {
      throw const FormatException('رمز باید بین ۱۲ تا ۱۲۸ نویسه باشد.');
    }
  }

  static Future<String> encrypt(String text, String password) async {
    _validatePassword(password);
    if (utf8.encode(text).length > maxBytes) throw const FormatException('حجم گزارش بیش از حد مجاز است.');
    // PBKDF2 runs in a worker isolate so opening or saving a report does not
    // block the UI. The password and plaintext are never written to disk.
    return Isolate.run(() => _encrypt(text, password));
  }

  static Future<String> _encrypt(String text, String password) async {
    final Random random = Random.secure();
    List<int> bytes(int count) => List<int>.generate(count, (_) => random.nextInt(256));
    final salt = bytes(16);
    final nonce = bytes(12);
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
    final key = await kdf.deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    final result = await AesGcm.with256bits().encrypt(utf8.encode(text),
      secretKey: key, nonce: nonce, aad: _aad);
    return jsonEncode(<String, dynamic>{
      'format': format, 'kdf': 'PBKDF2-HMAC-SHA256', 'iterations': iterations,
      'cipher': 'AES-256-GCM', 'salt': base64Encode(salt),
      'nonce': base64Encode(nonce), 'ciphertext': base64Encode(result.cipherText),
      'tag': base64Encode(result.mac.bytes),
    });
  }

  /// Strict version and resource checks before the KDF/decryption.
  static Future<String> decrypt(String document, String password) async {
    _validatePassword(password);
    if (document.length > maxBytes * 2) throw const FormatException('گزارش بیش از حد بزرگ است.');
    return Isolate.run(() async {
      final dynamic parsed = jsonDecode(document);
      if (parsed is! Map || parsed['format'] != format ||
          parsed['kdf'] != 'PBKDF2-HMAC-SHA256' || parsed['iterations'] != iterations ||
          parsed['cipher'] != 'AES-256-GCM') throw const FormatException('قالب گزارش معتبر نیست.');
      List<int> decode(String name) {
        final value = parsed[name];
        if (value is! String) throw const FormatException('قالب گزارش معتبر نیست.');
        return base64Decode(value);
      }
      final salt = decode('salt');
      final nonce = decode('nonce');
      final ciphertext = decode('ciphertext');
      final tag = decode('tag');
      if (salt.length != 16 || nonce.length != 12 || tag.length != 16 || ciphertext.length > maxBytes) {
        throw const FormatException('قالب گزارش معتبر نیست.');
      }
      final key = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
          .deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
      final bytes = await AesGcm.with256bits().decrypt(SecretBox(ciphertext, nonce: nonce, mac: Mac(tag)),
          secretKey: key, aad: _aad);
      return utf8.decode(bytes);
    });
  }

  static Future<String> save(String text, String password) async {
    final encrypted = await encrypt(text, password);
    final dir = Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}logs');
    await dir.create(recursive: true);
    final random = Random.secure();
    final suffix = List<int>.generate(12, (_) => random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    final file = File('${dir.path}${Platform.pathSeparator}umbrella-report-$suffix.umbreport');
    await file.writeAsString(encrypted, flush: true);
    return file.path;
  }
}
