import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../core/storage.dart';
import '../models/models.dart';
import '../platform/native.dart';
import '../platform/services.dart';

/// تنظیمات برنامه: بارگذاری، ذخیره و اعمال فوری روی ویندوز و ظاهر.
class SettingsController extends ChangeNotifier {
  SettingsController({
    required NativeBridge native,
    required SoundService sound,
    required WindowService window,
  })  : _native = native,
        _sound = sound,
        _window = window;

  final NativeBridge _native;
  final SoundService _sound;
  final WindowService _window;

  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

  bool _landingSeen = false;
  bool get landingSeen => _landingSeen;

  bool _elevated = false;
  bool get elevated => _elevated;

  ThemeMode get themeMode {
    switch (_settings.theme) {
      case ThemePreference.dark:
        return ThemeMode.dark;
      case ThemePreference.light:
        return ThemeMode.light;
      case ThemePreference.system:
        return ThemeMode.system;
    }
  }

  Future<void> load() async {
    final Map<String, dynamic> json =
        LocalStore.instance.readJson(StoreKeys.settings);
    if (json.isNotEmpty) {
      _settings = AppSettings.fromJson(json);
    }
    _landingSeen = LocalStore.instance.readBool(StoreKeys.landingSeen);
    _elevated = await _native.isElevated();
    _sound.enabled = _settings.soundEnabled;
    _window.closeToTray = _settings.closeToTray;
    notifyListeners();
  }

  Future<void> markLandingSeen() async {
    _landingSeen = true;
    await LocalStore.instance.writeBool(StoreKeys.landingSeen, true);
    notifyListeners();
  }

  Future<void> update(AppSettings next, {bool applyNative = true}) async {
    final AppSettings previous = _settings;
    _settings = next;
    await LocalStore.instance.writeJson(StoreKeys.settings, next.toJson());
    _sound.enabled = next.soundEnabled;
    _window.closeToTray = next.closeToTray;
    notifyListeners();
    if (!applyNative) {
      return;
    }
    if (previous.startWithWindows != next.startWithWindows) {
      await _native.setAutostart(
        next.startWithWindows,
        appName: AppConfig.autostartName,
      );
    }
  }

  Future<void> setTheme(ThemePreference theme) async {
    await update(_settings.copyWith(theme: theme));
  }

  Future<void> toggleTheme() async {
    final ThemePreference next = _settings.theme == ThemePreference.dark
        ? ThemePreference.light
        : ThemePreference.dark;
    await setTheme(next);
  }

  Future<void> setAutoConnect(bool value) async {
    await update(_settings.copyWith(autoConnect: value));
  }

  Future<void> setKillSwitch(bool value) async {
    await update(_settings.copyWith(killSwitch: value));
  }

  Future<void> setTunMode(bool value) async {
    await update(_settings.copyWith(tunMode: value));
  }

  Future<void> setCorePreference(CorePreference value) async {
    await update(_settings.copyWith(corePreference: value));
  }

  Future<void> setSound(bool value) async {
    await update(_settings.copyWith(soundEnabled: value));
  }

  Future<void> setNotifications(bool value) async {
    await update(_settings.copyWith(notificationsEnabled: value));
  }

  Future<void> setMinimizeToTray(bool value) async {
    await update(_settings.copyWith(minimizeToTray: value));
  }

  Future<void> setCloseToTray(bool value) async {
    await update(_settings.copyWith(closeToTray: value));
  }

  Future<void> setStartWithWindows(bool value) async {
    await update(_settings.copyWith(startWithWindows: value));
  }

  Future<void> setSelectionMode(SelectionMode mode) async {
    await update(_settings.copyWith(selectionMode: mode));
  }

  Future<void> setStickyMinutes(int minutes) async {
    await update(_settings.copyWith(stickyMinutes: minutes));
  }

  Future<void> setAutoFailover(bool value) async {
    await update(_settings.copyWith(autoFailover: value));
  }

  Future<void> setTunStack(TunStack stack) async {
    await update(_settings.copyWith(tunStack: stack));
  }

  Future<void> setMtu(int mtu) async {
    await update(_settings.copyWith(mtu: mtu.clamp(1280, 9000)));
  }

  Future<void> setBlockIpv6(bool value) async {
    await update(_settings.copyWith(blockIpv6: value));
  }

  Future<void> setStrictRoute(bool value) async {
    await update(_settings.copyWith(strictRoute: value));
  }

  Future<void> setDnsOverTunnel(bool value) async {
    await update(_settings.copyWith(dnsOverTunnel: value));
  }

  Future<void> setOccasionEffects(bool value) async {
    await update(_settings.copyWith(occasionEffects: value));
  }

  Future<void> setCheckUpdates(bool value) async {
    await update(_settings.copyWith(checkUpdatesOnStart: value));
  }

  Future<void> setTurboMode(bool value) async {
    await update(_settings.copyWith(turboMode: value));
  }

  Future<void> setShowSpeedInTray(bool value) async {
    await update(_settings.copyWith(showSpeedInTray: value));
  }

  Future<void> setPingInterval(int seconds) async {
    await update(_settings.copyWith(pingIntervalSeconds: seconds.clamp(30, 900)));
  }

  Future<void> rememberProfile({
    String? firstName,
    String? lastName,
    String? phone,
  }) async {
    await update(
      _settings.copyWith(
        firstName: firstName ?? _settings.firstName,
        lastName: lastName ?? _settings.lastName,
        phone: phone ?? _settings.phone,
      ),
      applyNative: false,
    );
  }

  Future<void> rememberNode(String nodeId) async {
    await update(_settings.copyWith(lastNodeId: nodeId), applyNative: false);
  }

  Future<bool> requestElevation() async {
    final bool ok = await _native.relaunchElevated();
    return ok;
  }
}
