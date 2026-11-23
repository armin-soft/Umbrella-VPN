import 'dart:io';

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

  testWidgets('shared cards, icon actions, info rows, select fields, and wrapped Material buttons emit click sound', (tester) async {
    final sound = FakeSound();
    int clicks = 0;
    String selected = 'a';
    bool chipSelected = false;

    await tester.pumpWidget(
      Provider<SoundService>.value(
        value: sound,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: <Widget>[
                    IconAction(
                      icon: Icons.refresh_rounded,
                      tooltip: 'تازه سازی',
                      onTap: () => clicks++,
                    ),
                    GlassCard(
                      onTap: () => clicks++,
                      child: const Text('کارت شیشه ای'),
                    ),
                    SelectionCard(
                      icon: Icons.bolt_rounded,
                      title: 'انتخابی',
                      description: 'توضیح کوتاه',
                      selected: false,
                      onTap: () => clicks++,
                    ),
                    InfoRow(
                      icon: Icons.link_rounded,
                      label: 'پیوند',
                      value: 'باز کردن',
                      onTap: () => clicks++,
                    ),
                    AnchoredSelectField<String>(
                      label: 'حالت',
                      value: selected,
                      options: const <SelectOption<String>>[
                        SelectOption<String>(value: 'a', label: 'گزینه الف'),
                        SelectOption<String>(value: 'b', label: 'گزینه ب'),
                      ],
                      onChanged: (String next) {
                        selected = next;
                        clicks++;
                      },
                    ),
                    Builder(
                      builder: (BuildContext context) => Row(
                        children: <Widget>[
                          TextButton(
                            onPressed: withUiClick(context, () => clicks++),
                            child: const Text('دکمه متنی'),
                          ),
                          ChoiceChip(
                            label: const Text('چیپ'),
                            selected: chipSelected,
                            onSelected: withUiClickValue(context, (bool next) {
                              chipSelected = next;
                              clicks++;
                            }),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    for (final Finder target in <Finder>[
      find.byIcon(Icons.refresh_rounded),
      find.text('کارت شیشه ای'),
      find.text('انتخابی'),
      find.text('باز کردن'),
      find.text('دکمه متنی'),
      find.text('چیپ'),
      find.text('گزینه الف'),
    ]) {
      await tester.ensureVisible(target);
      await tester.tap(target);
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('گزینه ب').last);
    await tester.pumpAndSettle();

    expect(clicks, 7);
    expect(selected, 'b');
    expect(chipSelected, isTrue);
    expect(sound.played, everyElement('click'));
    expect(sound.played.length, greaterThanOrEqualTo(8));
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

  test('Windows UI avoids TextOverflow truncation and maintains low-latency SoundService pools', () {
    final List<File> uiFiles = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();
    expect(uiFiles, isNotEmpty);
    for (final File file in uiFiles) {
      final String src = file.readAsStringSync();
      expect(
        src.contains('TextOverflow'),
        isFalse,
        reason: '${file.path} should wrap or scale text instead of clipping with TextOverflow',
      );
      expect(
        RegExp(r'\boverflow\s*:').hasMatch(src),
        isFalse,
        reason: '${file.path} should not clip text using overflow:',
      );
    }

    final String servicesSrc = File('lib/platform/services.dart').readAsStringSync();
    expect(servicesSrc, contains('_clickPlayer'));
    expect(servicesSrc, contains('_statePlayer'));
    expect(servicesSrc, contains('_alertPlayer'));
    expect(servicesSrc, contains('Duration(milliseconds: 40)'));
    expect(servicesSrc, contains("name == 'click' ? 0.55 : 0.85"));
  });
}
