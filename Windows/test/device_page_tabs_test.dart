import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:umbrella_vpn/core/theme.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/state/toast_controller.dart';
import 'package:umbrella_vpn/ui/pages/device_page.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

class _Native extends NativeBridge {
  _Native({this.deviceInfoResult});

  final Future<DeviceProfile>? deviceInfoResult;

  @override
  Future<DeviceProfile> deviceInfo() =>
      deviceInfoResult ?? Future<DeviceProfile>.value(DeviceProfile.empty);
}

class _Vpn extends ChangeNotifier implements VpnController {
  @override
  DeviceProfile get device => const DeviceProfile(
        hostname: 'test-pc',
        machineId: '12345678',
        localIp: '192.168.1.20',
      );

  @override
  String get realIp => '';

  @override
  VpnStatus get status => VpnStatus.disconnected;

  @override
  Future<void> refreshIp() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'device information is grouped into responsive top tabs',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(980, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final Completer<DeviceProfile> pendingDeviceInfo =
          Completer<DeviceProfile>();
      final _Native native =
          _Native(deviceInfoResult: pendingDeviceInfo.future);
      final _Vpn vpn = _Vpn();
      final ToastController toasts = ToastController();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        vpn.dispose();
        toasts.dispose();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<NativeBridge>.value(value: native),
            ChangeNotifierProvider<VpnController>.value(value: vpn),
            ChangeNotifierProvider<ToastController>.value(value: toasts),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(body: DevicePage()),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('device-refresh-indicator')),
        findsNothing,
      );
      pendingDeviceInfo.complete(DeviceProfile.empty);
      await tester.pumpAndSettle();

      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byType(TabBarView), findsOneWidget);
      expect(
        find.byKey(
          const PageStorageKey<String>('device-section-content-overview'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('device-network-card')),
        findsNothing,
      );
      expect(
        tester
            .widget<TabBar>(
              find.byKey(const ValueKey<String>('device-section-tabs')),
            )
            .isScrollable,
        isFalse,
      );
      expect(
        tester.getTopLeft(
          find.byKey(const ValueKey<String>('device-section-tab-card')),
        ).dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(
                  const PageStorageKey<String>(
                    'device-section-content-overview',
                  ),
                ),
              )
              .dy,
        ),
      );

      Future<void> selectTab(int index) async {
        final BuildContext tabContext = tester.element(find.byType(TabBar));
        DefaultTabController.of(tabContext).animateTo(index);
        await tester.pumpAndSettle();
      }

      await selectTab(1);
      expect(
        find.byKey(
          const PageStorageKey<String>('device-section-content-hardware'),
        ),
        findsOneWidget,
      );
      expect(find.text('حافظه رم و فضای ذخیره سازی'), findsOneWidget);
      expect(find.text('سخت افزار، نمایشگر و سیستم عامل'), findsOneWidget);
      await selectTab(2);
      expect(
        find.byKey(const ValueKey<String>('device-network-card')),
        findsOneWidget,
      );
      expect(find.text('نوع کارت شبکه فعال'), findsOneWidget);
      await selectTab(3);
      expect(
        find.byKey(const ValueKey<String>('device-identity-card')),
        findsOneWidget,
      );
      expect(find.text('شناسه یکتای سخت افزاری'), findsOneWidget);
      expect(find.text('کپی مشخصات فنی این دستگاه'), findsOneWidget);

      await tester.binding.setSurfaceSize(const Size(700, 820));
      await tester.pumpAndSettle();
      expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isFalse);
      await tester.binding.setSurfaceSize(const Size(520, 820));
      await tester.pumpAndSettle();
      expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
