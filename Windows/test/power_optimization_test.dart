import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/state/power_controller.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const battery = BatteryPowerState(hasBattery: true, onBattery: true, energySaver: false);
  const plugged = BatteryPowerState(hasBattery: true, onBattery: false, energySaver: false);
  const saver = BatteryPowerState(hasBattery: true, onBattery: false, energySaver: true);
  const desktop = BatteryPowerState(hasBattery: false, onBattery: true, energySaver: true);

  test('battery setting defaults on and survives JSON and copy', () {
    expect(AppSettings.fromJson(<String, dynamic>{}).batteryOptimization, true);
    final settings = const AppSettings().copyWith(batteryOptimization: false);
    expect(AppSettings.fromJson(settings.toJson()).batteryOptimization, false);
  });

  test('battery, plugged, energy saver and no battery policy', () {
    expect(battery.shouldOptimize, true);
    expect(plugged.shouldOptimize, false);
    expect(saver.shouldOptimize, true);
    expect(desktop.shouldOptimize, false);
  });

  test('power changes, unknown and user choice update without restarting', () async {
    BatteryPowerState? state = battery;
    final controller = PowerController(readStatus: () async => state);
    var changes = 0;
    controller.addListener(() => changes++);
    await controller.refresh();
    expect(controller.active, true);
    state = plugged;
    await controller.refresh();
    expect(controller.active, false);
    state = battery;
    await controller.refresh();
    state = null;
    await controller.refresh();
    expect(controller.active, false);
    state = battery;
    await controller.refresh();
    controller.setEnabled(false);
    expect(controller.active, false);
    await controller.refresh();
    expect(controller.active, false);
    controller.setEnabled(true);
    await Future<void>.delayed(Duration.zero);
    expect(controller.active, true);
    expect(changes, 7);
    controller.dispose();
  });

  test('late power result cannot re-enable a disabled or disposed controller', () async {
    final result = Completer<BatteryPowerState?>();
    final controller = PowerController(readStatus: () => result.future);
    final refresh = controller.refresh();
    controller.setEnabled(false);
    result.complete(battery);
    await refresh;
    expect(controller.active, false);
    controller.dispose();
  });

  test('speed uses actual elapsed time and handles reset or zero duration', () {
    expect(trafficBytesPerSecond(5000, const Duration(seconds: 5)), 1000);
    expect(trafficBytesPerSecond(1500, const Duration(milliseconds: 1500)), 1000);
    expect(trafficBytesPerSecond(-1, const Duration(seconds: 1)), 0);
    expect(trafficBytesPerSecond(100, Duration.zero), 0);
  });

  test('native unknown and unsupported methods do not disable bridge', () async {
    const channel = MethodChannel('ir.umbrella.app/native');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'powerStatus') return <String, Object>{'known': false};
      throw MissingPluginException();
    });
    final native = NativeBridge();
    expect(await native.powerStatus(), isNull);
    messenger.setMockMethodCallHandler(channel, (call) async => throw MissingPluginException());
    expect(await native.powerStatus(), isNull);
    expect(native.available, true);
    messenger.setMockMethodCallHandler(channel, null);
  });
}
