import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared screen sources and text match the Windows version', () {
    final windows = Directory('../Windows/lib/ui');
    expect(windows.existsSync(), isTrue,
        reason: 'Run this repository test from the Android directory.');
    for (final file in windows.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final relative = file.path.substring(windows.path.length + 1);
      final android = File('lib/ui/$relative');
      expect(android.existsSync(), isTrue, reason: 'Missing $relative');
      expect(android.readAsStringSync(), file.readAsStringSync(),
          reason: 'The Windows screen $relative was changed.');
    }
    expect(File('lib/app.dart').readAsStringSync(),
        File('../Windows/lib/app.dart').readAsStringSync());
  });
}
