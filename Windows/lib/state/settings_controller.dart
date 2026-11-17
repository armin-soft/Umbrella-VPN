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

  Future<void> _pendingSave = Future<void>.value();
  int _saveSeq = 0;
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
    _sound.enabled = next.soundEnabled;
    _window.closeToTray = next.closeToTray;
    // Apply appearance immediately; serialize and coalesce disk writes so rapid
    // back-to-back theme clicks neither block rendering nor persist stale state.
    notifyListeners();
    final int seq = ++_saveSeq;
    final Future<void> save = _pendingSave.then((_) async {
      if (seq != _saveSeq) {
        return;
      }
      await LocalStore.instance.writeJson(
        StoreKeys.settings,
        _settings.toJson(),
      );
    });
    _pendingSave = save.catchError((Object error) {
      AppLogger.instance.add('ذخیره تنظیمات ناموفق بود: $error', level: 'error');
    });
    await save;
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
    if (_settings.theme == theme) {
      return;
    }
    await update(_settings.copyWith(theme: theme), applyNative: false);
  }

  Future<void> toggleTheme({Brightness? effectiveBrightness}) async {
    final bool isDark;
    if (_settings.theme == ThemePreference.dark) {
      isDark = true;
    } else if (_settings.theme == ThemePreference.light) {
      isDark = false;
    } else {
      final Brightness current = effectiveBrightness ??
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
      isDark = current == Brightness.dark;
    }
    final ThemePreference next =
        isDark ? ThemePreference.light : ThemePreference.dark;
    await setTheme(next);
  }

  Future<void> setAutoConnect(bool value) async {
    await update(_settings.copyWith(autoConnect: value));
  }

  /// آزادسازی خودکار پورت های ثابت هسته پیش از اتصال.
  Future<void> setFreeCorePorts(bool value) async {
    await update(_settings.copyWith(freeCorePorts: value));
  }

  Future<void> setKillSwitch(bool value) async {
    await update(_settings.copyWith(killSwitch: value));
  }

  Future<void> setTunMode(bool value) async {
    // انتخاب کاربر ثبت می شود تا مایگریشن پیش فرض دیگر رویش ننویسد.
    await update(
      _settings.copyWith(tunMode: value, modeChoiceExplicit: true),
    );
  }

  /// مایگریشن تنظیمات نسخه های پیشین: پیش فرض اتصال روی تونل کامل است و هر
  /// فیلتر منطقه قدیمی (از منوی حذف شده «منطقه و سرورها») به «همه» برمی گردد
  /// تا تمام سرورهای اشتراک `/sub/` کاربر فعال باشند.
  Future<void> migrateConnectionMode() async {
    final bool needsTun = !_settings.modeChoiceExplicit && !_settings.tunMode;
    final bool needsRegionReset = _settings.serverRegionCode != 'all';
    if (!needsTun && !needsRegionReset) {
      return;
    }
    await update(
      _settings.copyWith(
        tunMode: needsTun ? true : _settings.tunMode,
        serverRegionCode: 'all',
      ),
    );
  }

  /// ثبت حالت اتصال. `tunMode` هم به روز می شود تا این دو هیچ وقت ناهماهنگ
  /// نباشند: «تونل کامل» یعنی تونل روشن، «پروکسی سیستمی» یعنی خاموش، و
  /// «خودکار» یعنی اول تونل و اگر نشد پروکسی.
  Future<void> setCorePreference(CorePreference value) async {
    await update(
      _settings.copyWith(
        corePreference: value,
        tunMode: value.prefersTun,
        modeChoiceExplicit: true,
      ),
    );
  }

  /// پنجره CLI هسته هنگام اتصال باز شود یا نه.
  ///
  /// پیش فرض خاموش است؛ فقط برای عیب‌یابی با انتخاب کاربر باز می‌شود.
  Future<void> setShowCli(bool value) async {
    await update(_settings.copyWith(showCli: value));
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

  Future<void> setServerRegion(String countryCode) async {
    await update(_settings.copyWith(serverRegionCode: countryCode));
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

  Future<void> setRemoteDns(String value) async {
    if (!NetworkDns.presets.containsKey(value)) throw ArgumentError.value(value, 'remoteDns');
    await update(_settings.copyWith(remoteDns: value));
  }

  Future<void> setDirectDns(String value) async {
    if (!NetworkDns.presets.containsKey(value)) throw ArgumentError.value(value, 'directDns');
    await update(_settings.copyWith(directDns: value));
  }

  Future<void> setChain(ChainSettings chain) async {
    if (chain.enabled && chain.validationError != null) throw FormatException(chain.validationError!);
    await update(_settings.copyWith(chain: chain));
  }

  Future<void> setAppRoutes(List<AppRouteRule> rules) async {
    if (rules.length > 64) throw const FormatException('حداکثر ۶۴ قانون');
    final Set<String> seen = <String>{};
    for (final AppRouteRule rule in rules) {
      if (rule.validationError != null) throw FormatException(rule.validationError!);
      if (!seen.add(rule.process.trim().toLowerCase())) throw const FormatException('قانون تکراری برای برنامه');
    }
    await update(_settings.copyWith(appRoutes: rules));
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
