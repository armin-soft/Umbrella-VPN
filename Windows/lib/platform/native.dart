import 'dart:async';

import 'package:flutter/services.dart';

import '../core/utils.dart';
import '../models/models.dart';

/// پل ارتباط با لایه بومی ویندوز (پلاگین umbrella_native).
///
/// هر متد در صورت نبود پلاگین مقدار امن برمی گرداند تا رابط کاربری هرگز
/// از کار نیفتد؛ مثلا در حالت اجرای آزمایشی روی ماشین بدون دسترسی مدیر.
class NativeBridge {
  NativeBridge();

  static const MethodChannel _channel = MethodChannel('ir.umbrella.app/native');
  static const EventChannel _trayChannel = EventChannel('ir.umbrella.app/tray');

  bool _available = true;
  bool get available => _available;

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    if (!_available) {
      return null;
    }
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      _available = false;
      return null;
    } on PlatformException {
      return null;
    }
  }

  Stream<String> get trayEvents {
    if (!_available) {
      return const Stream<String>.empty();
    }
    return _trayChannel
        .receiveBroadcastStream()
        .map((Object? event) => event?.toString() ?? '')
        .handleError((Object error) => '');
  }

  Future<bool> isElevated() async => await _invoke<bool>('isElevated') ?? false;

  Future<bool> relaunchElevated() async =>
      await _invoke<bool>('relaunchElevated') ?? false;

  Future<bool> runElevated(String exe, {String args = ''}) async =>
      await _invoke<bool>('runElevated', <String, dynamic>{
        'exe': exe,
        'args': args,
      }) ??
      false;

  Future<DeviceProfile> deviceInfo() async {
    final Map<Object?, Object?>? raw =
        await _invoke<Map<Object?, Object?>>('deviceInfo');
    if (raw == null || raw.isEmpty) {
      return DeviceProfile.empty;
    }
    return DeviceProfile.fromNative(Map<String, dynamic>.from(raw));
  }

  Future<String> localIp() async => await _invoke<String>('localIp') ?? '';

  Future<String> adapterName() async =>
      await _invoke<String>('adapterName') ?? '';

  Future<int> ping(String host, {int timeoutMs = 1500}) async =>
      await _invoke<int>('ping', <String, dynamic>{
        'host': host,
        'timeoutMs': timeoutMs,
      }) ??
      -1;

  Future<int> tcpPing(String host, int port, {int timeoutMs = 1500}) async =>
      await _invoke<int>('tcpPing', <String, dynamic>{
        'host': host,
        'port': port,
        'timeoutMs': timeoutMs,
      }) ??
      -1;

  Future<int> spawn({
    required String exe,
    String args = '',
    String workDir = '',
    bool hidden = true,
  }) async =>
      await _invoke<int>('spawn', <String, dynamic>{
        'exe': exe,
        'args': args,
        'workDir': workDir,
        'hidden': hidden,
      }) ??
      -1;

  Future<bool> killPid(int pid) async =>
      await _invoke<bool>('killPid', <String, dynamic>{'pid': pid}) ?? false;

  Future<int> killByName(String name) async =>
      await _invoke<int>('killByName', <String, dynamic>{'name': name}) ?? 0;

  Future<bool> isRunning(String name) async =>
      await _invoke<bool>('isRunning', <String, dynamic>{'name': name}) ?? false;

  Future<List<String>> runningCores() async {
    final List<Object?>? raw =
        await _invoke<List<Object?>>('runningCores');
    return (raw ?? <Object?>[]).map((Object? item) => item.toString()).toList();
  }

  Future<bool> disableSystemProxy() async =>
      await _invoke<bool>('disableSystemProxy') ?? false;

  Future<bool> systemProxyEnabled() async =>
      await _invoke<bool>('systemProxyEnabled') ?? false;

  Future<bool> enableKillSwitch({
    required List<String> allowedExes,
    String appName = 'Umbrella',
  }) async =>
      await _invoke<bool>('killSwitchOn', <String, dynamic>{
        'allowed': allowedExes,
        'appName': appName,
      }) ??
      false;

  Future<bool> disableKillSwitch({String appName = 'Umbrella'}) async =>
      await _invoke<bool>('killSwitchOff', <String, dynamic>{
        'appName': appName,
      }) ??
      false;

  Future<bool> killSwitchActive({String appName = 'Umbrella'}) async =>
      await _invoke<bool>('killSwitchActive', <String, dynamic>{
        'appName': appName,
      }) ??
      false;

  Future<bool> flushDns() async => await _invoke<bool>('flushDns') ?? false;

  Future<TunnelStats> tunnelStats({String hint = 'sing-box'}) async {
    final Map<Object?, Object?>? raw = await _invoke<Map<Object?, Object?>>(
      'tunnelStats',
      <String, dynamic>{'hint': hint},
    );
    if (raw == null) {
      return TunnelStats.empty;
    }
    final Map<String, dynamic> map = Map<String, dynamic>.from(raw);
    return TunnelStats(
      rx: JsonX.integer(map['rx']),
      tx: JsonX.integer(map['tx']),
      available: JsonX.boolean(map['available']),
      adapter: JsonX.text(map['adapter']),
    );
  }

  Future<bool> setAutostart(bool enabled, {String appName = 'UmbrellaVPN'}) async =>
      await _invoke<bool>('autostart', <String, dynamic>{
        'enabled': enabled,
        'appName': appName,
      }) ??
      false;

  Future<bool> autostartEnabled({String appName = 'UmbrellaVPN'}) async =>
      await _invoke<bool>('autostartEnabled', <String, dynamic>{
        'appName': appName,
      }) ??
      false;

  Future<String> exePath() async => await _invoke<String>('exePath') ?? '';

  Future<String> dataDir() async => await _invoke<String>('dataDir') ?? '';

  Future<bool> openPath(String path) async =>
      await _invoke<bool>('openPath', <String, dynamic>{'path': path}) ?? false;

  Future<bool> restoreNetworkDefaults() async =>
      await _invoke<bool>('restoreNetworkDefaults', <String, dynamic>{
        'appName': 'Umbrella',
      }) ??
      false;

  Future<bool> trayInit() async => await _invoke<bool>('trayInit') ?? false;

  Future<bool> trayIcon(String path) async =>
      await _invoke<bool>('trayIcon', <String, dynamic>{'path': path}) ?? false;

  Future<bool> trayTooltip(String text) async =>
      await _invoke<bool>('trayTooltip', <String, dynamic>{'text': text}) ??
      false;

  Future<bool> trayMenu({
    required String connectLabel,
    required String disconnectLabel,
    required bool connected,
  }) async =>
      await _invoke<bool>('trayMenu', <String, dynamic>{
        'connectLabel': connectLabel,
        'disconnectLabel': disconnectLabel,
        'connected': connected,
      }) ??
      false;

  Future<bool> trayBalloon({
    required String title,
    required String body,
    bool warning = false,
  }) async =>
      await _invoke<bool>('trayBalloon', <String, dynamic>{
        'title': title,
        'body': body,
        'warning': warning,
      }) ??
      false;

  Future<bool> trayDestroy() async => await _invoke<bool>('trayDestroy') ?? false;
}
