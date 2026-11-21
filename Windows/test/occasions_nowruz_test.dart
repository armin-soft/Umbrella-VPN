import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Nowruz occasion uses Farvardin 1 through 13', () async {
    final Map<String, dynamic> data = jsonDecode(
      await rootBundle.loadString('assets/data/occasions.json'),
    ) as Map<String, dynamic>;
    final List<dynamic> items = data['items'] as List<dynamic>;
    final Map<String, dynamic> nowruz = items
        .cast<Map<String, dynamic>>()
        .singleWhere((Map<String, dynamic> item) => item['id'] == 'nowruz');

    expect(nowruz['start'], '01-01');
    expect(nowruz['end'], '01-13');
  });
}
