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
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

class _Native implements NativeBridge {
  @override
  Future<bool> isElevated() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sound implements SoundService {
  @override
  bool enabled = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Window implements WindowService {
  @override
  bool closeToTray = true;

  @override
  bool notificationsEnabled = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Vpn extends ChangeNotifier implements VpnController {
  @override
  VpnStatus get status => VpnStatus.disconnected;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.instance.init();
  });

  testWidgets('connection settings stay focused and hide chain controls',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final SettingsController settings = SettingsController(
      native: _Native(),
      sound: _Sound(),
      window: _Window(),
    );
    final _Vpn vpn = _Vpn();
    final ToastController toasts = ToastController();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<VpnController>.value(value: vpn),
          ChangeNotifierProvider<ToastController>.value(value: toasts),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: QuickConnectionPanel(
                  enabled: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('تنظیمات اتصال'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('quick-panel-toggle')), findsNothing);
    expect(find.byKey(const ValueKey<String>('quick-extra-security')), findsNothing);
    expect(find.byKey(const ValueKey<String>('quick-proxy-unblocker')), findsNothing);
    expect(find.byKey(const ValueKey<String>('quick-chain-settings')), findsNothing);
    expect(find.text('امنیت بیشتر'), findsNothing);
    expect(find.text('رفع فیلتر پروکسی'), findsNothing);
    expect(find.byKey(const ValueKey<String>('quick-lan-switch')), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(tester.takeException(), isNull);

    await settings.setChain(
      const ChainSettings(position: ChainPosition.extraSecurity),
    );
    await tester.pump();
    expect(settings.settings.chain.position, ChainPosition.extraSecurity);
    expect(find.text('امنیت بیشتر'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('quick-lan-switch')));
    await tester.pumpAndSettle();
    expect(settings.settings.allowConnectionFromLan, isTrue);
    expect(settings.settings.chain.position, ChainPosition.extraSecurity);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    settings.dispose();
    vpn.dispose();
    toasts.dispose();
  });
}
