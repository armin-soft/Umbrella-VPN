import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/core/core_display.dart';

void main() {
  test('own engine diagnostics use the Umbrella display name', () {
    const original = 'hiddify-core.dll failed; HiddifyCli.exe exited';
    final displayed = displayOwnCoreOutput(original, engineId: 'hiddify');
    expect(displayed, 'UmbrellaCore failed; UmbrellaCore exited');
    expect(original, 'hiddify-core.dll failed; HiddifyCli.exe exited');
  });

  test('unrelated names and diagnostics are unchanged', () {
    const other = 'HiddifyVPN is another program; port 17078 is busy';
    expect(displayOwnCoreOutput(other, engineId: 'hiddify'), other);
    expect(displayOwnCoreOutput('details', engineId: ''), 'details');
  });
}
