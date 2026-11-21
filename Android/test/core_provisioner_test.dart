import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/vpn/cores.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('mobile engine manifest uses the Windows engine version and pinned archive', () {
    final mobile = jsonDecode(File('assets/cores/manifest.json').readAsStringSync()) as Map<String, dynamic>;
    final windows = jsonDecode(File('../Windows/assets/cores/manifest.json').readAsStringSync()) as Map<String, dynamic>;
    final entry = (mobile['cores'] as List).single as Map<String, dynamic>;
    final windowsEntry = (windows['cores'] as List).single as Map<String, dynamic>;
    expect(entry['version'], windowsEntry['version']);
    expect(entry['sha256'], '853e897ee2dcbde30801314eb30346e0a4fc61c38f6b4fc4ee901a18fabec3a9');
    expect(CoreInfo.fromJson(entry).requiredCore, isTrue);
  });

  test('a missing manifest or packaged library is not represented as an executable', () async {
    final provisioner = CoreProvisioner();
    expect(await provisioner.locateBinary('umbrella-core.aar'), isNull);
    await expectLater(provisioner.missingRequired(), throwsStateError);
    expect(await provisioner.hasCore('unknown'), isFalse);
  });
}
