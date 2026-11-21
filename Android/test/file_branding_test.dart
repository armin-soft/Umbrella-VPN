import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('project-owned source and documentation paths use Umbrella naming', () {
    for (final root in ['lib', 'licenses', '../Windows/lib', '../Windows/docs', '../Windows/licenses']) {
      for (final entry in Directory(root).listSync(recursive: true, followLinks: false)) {
        final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last.toLowerCase();
        expect(name, isNot(contains('hiddify')), reason: entry.path);
        expect(name, isNot(contains('hcore')), reason: entry.path);
      }
    }
  });
}
