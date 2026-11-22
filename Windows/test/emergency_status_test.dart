import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/models/models.dart';

void main() {
  test('emergency flag defaults off and survives account serialization', () {
    expect(Account.fromJson(<String, dynamic>{}).emergencyEnabled, isFalse);
    final Account enabled = Account.fromJson(<String, dynamic>{'emergency_enabled': true});
    expect(enabled.emergencyEnabled, isTrue);
    expect(Account.fromJson(enabled.toJson()).emergencyEnabled, isTrue);
    expect(enabled.copyWith(emergencyEnabled: false).emergencyEnabled, isFalse);
  });
}
