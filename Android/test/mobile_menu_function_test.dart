import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbrella_vpn/core/storage.dart';
import 'package:umbrella_vpn/core/theme.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/platform/services.dart';
import 'package:umbrella_vpn/state/settings_controller.dart';
import 'package:umbrella_vpn/state/toast_controller.dart';
import 'package:umbrella_vpn/ui/widgets/quick_connection_panel.dart';
import 'package:umbrella_vpn/vpn/cores.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

class _Sound implements SoundService {
  @override
  bool enabled = false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('quick menu rejects unsupported modes and LAN but permits recovery', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.instance.init();
    final native = NativeBridge();
    final sound = _Sound();
    final settings = SettingsController(native: native, sound: sound, window: WindowService(native));
    final toasts = ToastController();
    final vpn = VpnController(native: native, ipService: IpService(), sound: sound,
        tray: TrayService(native), provisioner: CoreProvisioner(), settings: const AppSettings());
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<VpnController>.value(value: vpn),
        ChangeNotifierProvider<ToastController>.value(value: toasts),
      ],
      child: MaterialApp(theme: AppTheme.dark(), home: const Scaffold(
        body: SingleChildScrollView(child: QuickConnectionPanel(enabled: true)),
      )),
    ));
    final segmented = tester.widget<SegmentedButton<InboundServiceMode>>(
        find.byType(SegmentedButton<InboundServiceMode>));
    segmented.onSelectionChanged!({InboundServiceMode.proxy});
    await tester.pump();
    expect(settings.settings.serviceMode, InboundServiceMode.vpn);
    expect(toasts.items.last.title, contains('پشتیبانی'));

    final row = find.byKey(const ValueKey<String>('quick-lan-row'));
    final switchFinder = find.descendant(of: row, matching: find.byType(Switch));
    tester.widget<Switch>(switchFinder).onChanged!(true);
    await tester.pump();
    expect(settings.settings.allowConnectionFromLan, isFalse);
    expect(toasts.items.last.title, contains('پشتیبانی'));

    // A legacy unsupported configuration can still be turned off by the user.
    await settings.setAllowConnectionFromLan(true);
    await tester.pump();
    tester.widget<Switch>(switchFinder).onChanged!(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(settings.settings.allowConnectionFromLan, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    toasts.dispose();
    settings.dispose();
    vpn.dispose();
  });
}
