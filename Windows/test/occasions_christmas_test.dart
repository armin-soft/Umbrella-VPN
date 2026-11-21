import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/platform/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Christmas has a fixed Gregorian date and traditional festive palette',
      () async {
    final Map<String, dynamic> data = jsonDecode(
      await rootBundle.loadString('assets/data/occasions.json'),
    ) as Map<String, dynamic>;
    final List<dynamic> items = data['items'] as List<dynamic>;
    final Map<String, dynamic> christmas = items
        .cast<Map<String, dynamic>>()
        .singleWhere((Map<String, dynamic> item) => item['id'] == 'christmas');

    expect(christmas['calendar'], 'gregorian');
    expect(christmas['start'], '12-24');
    expect(christmas['end'], '12-25');
    expect(christmas['icon'], 'christmas_tree');
    expect(christmas['tint'], '#1B5E20');
    expect(christmas['secondary_tint'], '#B71C1C');
    expect(christmas['accent_tint'], '#F9A825');

    final Occasion parsed = Occasion.fromJson(christmas);
    expect(parsed.gregorian, isTrue);
    expect(parsed.secondaryTint, 0xFFB71C1C);
    expect(parsed.accentTint, 0xFFF9A825);
  });

  test('Christmas banner activates on December 24 and 25 only', () async {
    final OccasionService service = OccasionService.instance;
    await service.load();

    expect(service.activeAt(DateTime(2026, 12, 23))?.id, isNot('christmas'));
    expect(service.activeAt(DateTime(2026, 12, 24))?.id, 'christmas');
    expect(service.activeAt(DateTime(2026, 12, 25))?.id, 'christmas');
    expect(service.activeAt(DateTime(2026, 12, 26))?.id, isNot('christmas'));
  });
}
