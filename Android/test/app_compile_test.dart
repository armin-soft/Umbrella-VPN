import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/app.dart';
import 'package:umbrella_vpn/main.dart' as app;

void main() {
  test('the actual Android app entrypoint and shared UI compile', () {
    expect(UmbrellaApp, isNotNull);
    expect(app.main, isNotNull);
  });
}
