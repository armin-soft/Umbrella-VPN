import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/platform/encrypted_report.dart';

void main() {
  test('encrypted report round trips, randomizes and authenticates data', () async {
    const password = 'correct horse battery staple';
    const text = 'گزارش خصوصی\nsecret token';
    final a = await EncryptedReport.encrypt(text, password);
    final b = await EncryptedReport.encrypt(text, password);
    expect(a, isNot(b));
    expect(a, isNot(contains(text)));
    expect(a, isNot(contains(password)));
    expect(await EncryptedReport.decrypt(a, password), text);
    await expectLater(EncryptedReport.decrypt(a, 'incorrect password here'), throwsA(anything));
    final parsed = jsonDecode(a) as Map<String, dynamic>;
    final cipher = base64Decode(parsed['ciphertext'] as String);
    cipher[0] ^= 1;
    parsed['ciphertext'] = base64Encode(cipher);
    await expectLater(EncryptedReport.decrypt(jsonEncode(parsed), password), throwsA(anything));
    parsed['iterations'] = 1;
    await expectLater(EncryptedReport.decrypt(jsonEncode(parsed), password), throwsA(isA<FormatException>()));
  }, timeout: const Timeout(Duration(seconds: 90)));
  test('weak passwords and excessive reports are rejected', () async {
    await expectLater(EncryptedReport.encrypt('test', 'short'), throwsA(isA<FormatException>()));
    await expectLater(EncryptedReport.encrypt('x' * (EncryptedReport.maxBytes + 1), 'long enough password'), throwsA(isA<FormatException>()));
  });
}
