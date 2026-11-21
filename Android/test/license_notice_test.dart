import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('engine license and upstream attribution remain available', () {
    final windows = File('../Windows/licenses/umbrella-core-license.md');
    final android = File('licenses/umbrella-core-license.md');
    expect(android.readAsBytesSync(), windows.readAsBytesSync());
    final notice = File('THIRD-PARTY-NOTICES.txt').readAsStringSync();
    expect(notice, contains('https://github.com/hiddify/hiddify-core'));
    expect(notice, contains('licenses/umbrella-core-license.md'));
  });
}
