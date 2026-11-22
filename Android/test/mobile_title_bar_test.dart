import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/core/theme.dart';
import 'package:umbrella_vpn/ui/widgets/shell_widgets.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

void main() {
  for (final width in <double>[320, 360, 480, 800]) {
    testWidgets('mobile title bar fits width $width without desktop controls', (tester) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = false;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: TitleBar(
            status: VpnStatus.connected,
            onDragStart: () {}, onMinimize: () {}, onMaximize: () {}, onClose: () {},
            onNotifications: () {}, onToggleTheme: () {},
            onOpenNavigation: () { opened = true; },
          )),
        ),
      ));
      expect(find.text('فیلترشکن آمبرلا'), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      expect(find.byIcon(Icons.crop_square_rounded), findsNothing);
      expect(find.byIcon(Icons.remove_rounded), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.menu_rounded));
      expect(opened, isTrue);
    });
  }
}
