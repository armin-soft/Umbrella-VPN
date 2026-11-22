import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:umbrella_vpn/core/theme.dart';
import 'package:umbrella_vpn/platform/services.dart';
import 'package:umbrella_vpn/state/toast_controller.dart';
import 'package:umbrella_vpn/ui/widgets/common.dart';

class FakeSound implements SoundService {
  @override
  bool enabled = true;
  final List<String> played = <String>[];
  @override
  Future<void> play(String name) async { played.add(name); }
  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('enabled controls play feedback without blocking actions, muted and disabled do not', (tester) async {
    final sound = FakeSound();
    var actions = 0;
    var toggled = false;
    await tester.pumpWidget(Provider<SoundService>.value(
      value: sound,
      child: MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: Column(children: [
        GradientButton(label: 'active', onPressed: () => actions++),
        GradientButton(label: 'disabled', enabled: false, onPressed: () => actions++),
        ToggleRow(icon: Icons.settings, title: 'toggle', value: false, onChanged: (_) => toggled = true),
      ]))),
    ));
    await tester.tap(find.text('active'));
    await tester.tap(find.text('toggle'));
    expect(actions, 1);
    expect(toggled, isTrue);
    expect(sound.played, ['click', 'click']);
    await tester.tap(find.text('disabled'));
    expect(sound.played, ['click', 'click']);
    sound.enabled = false;
    await tester.tap(find.text('active'));
    expect(actions, 2);
    expect(sound.played, ['click', 'click']);
  });

  test('alerts play appropriate feedback and respect mute', () {
    final sound = FakeSound();
    final toast = ToastController(sound: sound);
    addTearDown(toast.dispose);
    toast.success('done');
    toast.warning('warning');
    toast.error('error');
    toast.info('info');
    expect(sound.played, ['notify', 'notify', 'error']);
    sound.enabled = false;
    toast.error('muted');
    expect(sound.played.length, 3);
  });
}
