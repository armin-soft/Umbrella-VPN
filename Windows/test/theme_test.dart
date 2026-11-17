import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:umbrella_vpn/core/theme.dart';
import 'package:umbrella_vpn/ui/widgets/common.dart';

double contrast(Color a, Color b) {
  final double x = a.computeLuminance();
  final double y = b.computeLuminance();
  return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05);
}

void main() {
  for (final Brightness brightness in Brightness.values) {
    final ThemeData theme = brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light();
    final UmbrellaColors colors = theme.extension<UmbrellaColors>()!;
    test('$brightness text contrast and Material surfaces', () {
      for (final Color background in <Color>[colors.background, colors.surface, colors.surfaceHigh]) {
        for (final Color foreground in <Color>[colors.textPrimary, colors.textSecondary]) {
          expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
        }
      }
      expect(theme.colorScheme.surfaceContainer, colors.surface);
      expect(theme.dialogTheme.backgroundColor, colors.surface);
      expect(theme.colorScheme.onSurfaceVariant, colors.textSecondary);
      expect(theme.popupMenuTheme.color, colors.surface);
    });

    testWidgets('$brightness button stays readable and fits large RTL text', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: Center(child: SizedBox(
              width: 230,
              child: GradientButton(label: 'آزمایش یک عنوان بسیار طولانی برای دکمه', tone: colors.primarySoft, icon: Icons.check, onPressed: () {}),
            ))),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final Text label = tester.widget<Text>(find.text('آزمایش یک عنوان بسیار طولانی برای دکمه'));
      expect(contrast(label.style!.color!, colors.primarySoft), greaterThanOrEqualTo(4.5));
    });
  }

  testWidgets('system brightness changes update palette and open dialog', (WidgetTester tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(), darkTheme: AppTheme.dark(), themeMode: ThemeMode.system,
      home: Builder(builder: (BuildContext context) => Scaffold(
        body: TextButton(onPressed: () => showDialog<void>(context: context, builder: (BuildContext context) => const AlertDialog(title: Text('dialog'))), child: const Text('open')),
      )),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('dialog'))).brightness, Brightness.light);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('dialog'))).brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('palette fallback respects light host theme', (WidgetTester tester) async {
    late UmbrellaColors palette;
    await tester.pumpWidget(MaterialApp(theme: ThemeData.light(), home: Builder(builder: (BuildContext context) {
      palette = context.colors;
      return const SizedBox();
    })));
    expect(palette, UmbrellaColors.light);
  });
}
