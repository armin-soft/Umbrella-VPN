import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/app_config.dart';
import 'core/malicious_link_guard.dart';
import 'core/safe_url_launcher.dart';
import 'core/storage.dart';
import 'core/utils.dart';
import 'models/models.dart';
import 'platform/app_crash_store.dart';
import 'platform/native.dart';
import 'platform/services.dart';
import 'state/auth_controller.dart';
import 'state/motion_controller.dart';
import 'state/power_controller.dart';
import 'state/security_controller.dart';
import 'state/settings_controller.dart';
import 'state/subscription_controller.dart';
import 'state/toast_controller.dart';
import 'state/update_controller.dart';
import 'vpn/clash_api.dart';
import 'vpn/cores.dart';
import 'vpn/vpn_controller.dart';

/// نقطه شروع نسخه اندروید: آماده سازی انبار داده، هسته بومی، سرویس ها و کنترلرها.
Future<void> main(List<String> arguments) async {
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      AppCrashStore.record(
        error: details.exception,
        stack: details.stack,
        source: 'flutter',
      );
      AppLogger.instance.add(
        'خطای رابط کاربری: ${details.exceptionAsString()}',
        level: 'error',
      );
    };
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      AppCrashStore.record(
        error: error,
        stack: stack,
        source: 'dispatcher',
      );
      AppLogger.instance.add(
        'خطای پیش بینی نشده: $error',
        level: 'error',
      );
      return true;
    };

    await LocalStore.instance.init();
    try {
      final Directory supportDir = await getApplicationSupportDirectory();
      final List<String> previousCrashes =
          await AppCrashStore.openAndPrune(supportDir);
      if (previousCrashes.isNotEmpty) {
        AppLogger.instance.attachPreviousCrashes(previousCrashes);
        AppLogger.instance.add(
          'گزارش خطای نشست قبلی یافت شد (${Fa.num(previousCrashes.length)} مورد) و در گزارش ها پیوست شده است.',
          level: 'warning',
          details: <LogDetail>[
            LogDetail(
              title: 'گزارش خطای نشست قبلی',
              text: previousCrashes.join('\n\n---\n\n'),
            ),
          ],
        );
      }
    } on Object {
      // ادامه اجرا حتی در صورت محدودیت دسترسی به پوشه گزارش های سقوط.
    }

    final NativeBridge native = NativeBridge();
    final SoundService sound = SoundService();
    final WindowService window = WindowService(native);

    final SettingsController settings = SettingsController(
      native: native,
      sound: sound,
      window: window,
    );
    await settings.load();
    await settings.migrateConnectionMode();
    await window.init(
      initialBrightness: settings.resolveBrightness(
        PlatformDispatcher.instance.platformBrightness,
      ),
    );

    final MotionController motion = MotionController(native: native);
    window.onVisibilityChanged = () => motion.setAppVisible(window.isVisible);
    motion.setAppVisible(window.isVisible);
    motion.pulseAmbient();

    final IpService ipService = IpService();
    final TrayService tray = TrayService(native)
      ..notificationsEnabled = settings.settings.notificationsEnabled
      ..showSpeedInTray = settings.settings.showSpeedInTray;
    await tray.init();
    final AuthController auth = AuthController(
      native: native,
      sound: sound,
      tray: tray,
    );
    auth
      ..soundEnabled = settings.settings.soundEnabled
      ..notificationsEnabled = settings.settings.notificationsEnabled;

    final CoreProvisioner provisioner = CoreProvisioner();
    await provisioner.init(native);

    final List<String> nativeCrashes =
        await native.consumeRecentNativeCrashes();
    if (nativeCrashes.isNotEmpty) {
      AppLogger.instance.add(
        'گزارش خطای بومی نشست قبلی یافت شد (${Fa.num(nativeCrashes.length)} مورد).',
        level: 'warning',
        details: <LogDetail>[
          LogDetail(
            title: 'خطای بومی اندروید',
            text: nativeCrashes.join('\n\n---\n\n'),
          ),
        ],
      );
    }

    AppLogger.instance.add(
      '${AppConfig.appName} ${Fa.num(AppConfig.version)} راه اندازی شد',
    );

    final Map<String, dynamic> platformInfo = await native.getPlatformInfo();
    final String deviceAbi = JsonX.text(platformInfo['abi'], 'arm64-v8a');
    if (native.available) {
      AppLogger.instance.add(
        'سرویس بومی اندروید آماده است | معماری: $deviceAbi',
      );
    }

    final ToastController toasts = ToastController(sound: sound);

    late final VpnController vpn;
    final SecurityScannerController security = SecurityScannerController(
      native: native,
      auth: auth,
      isVpnActive: () => vpn.status.active,
    );
    auth.securityStateProvider = security.buildSecurityStatePayload;

    vpn = VpnController(
      native: native,
      ipService: ipService,
      sound: sound,
      tray: tray,
      provisioner: provisioner,
      settings: settings.settings,
      onSettingsChanged: (AppSettings next) => settings.update(next),
      onRequireElevation: () {
        toasts.warning(
          'مجوز اتصال لازم است',
          'برای ایجاد تونل امن، درخواست مجوز اتصال سیستم را تایید کنید.',
        );
      },
      onRequireCores: () {
        toasts.warning(
          'هسته پیدا نشد',
          'نسخه نصب هسته ها را همراه ندارد؛ برنامه را با نسخه رسمی دوباره نصب کنید.',
        );
      },
      accessGuard: () => auth.account.canConnect ? '' : auth.account.accessReason,
      securityGuard: () async {
        if (settings.settings.tunMode && native.available) {
          await native.closeConflictingVpns();
        }
        final SecurityScanResult scan = await security.ensureCleanBeforeConnect();
        final List<SecurityThreat> blocking = settings.settings.tunMode
            ? scan.threats
                .where((SecurityThreat t) => t.key != 'vpn:active_other_tunnel')
                .toList()
            : scan.threats;
        if (blocking.isEmpty) {
          return '';
        }
        final String names = blocking
            .take(3)
            .map((SecurityThreat t) => t.name)
            .join('، ');
        return 'تهدید یا برنامه ناسازگار شناسایی شد ($names). ابتدا از بخش سپر امنیتی آن را حذف یا متوقف کنید.';
      },
      canAutoConnect: () =>
          settings.landingSeen &&
          auth.signedIn &&
          auth.account.canConnect &&
          !security.threats.any(
            (SecurityThreat t) => t.key != 'vpn:active_other_tunnel',
          ),
    );
    security.onThreatBlockedWhileConnected = (List<SecurityThreat> threats) {
      final String names =
          threats.take(2).map((SecurityThreat t) => t.name).join('، ');
      final String msg =
          'برنامه ناسازگار یا مخرب ($names) شناسایی شد و اتصال برای امنیت شما متوقف گردید.';
      unawaited(vpn.disconnect());
      auth.recordLocalNotification(
        title: 'هشدار سپر امنیتی آمبرلا',
        body: msg,
        level: 'warning',
      );
      toasts.error('هشدار سپر امنیتی', msg);
    };
    security.onThreatNeutralized = (NeutralizedSecurityEvent event) {
      auth.recordLocalNotification(
        title: 'سپر امنیتی: ${event.actionLabelFa}',
        body: '${event.name} (${event.target})',
        level: 'warning',
      );
      toasts.warning(
        'سپر امنیتی: ${event.actionLabelFa}',
        event.name,
      );
    };
    SafeUrlLauncher.activeFilterProvider = () => auth.filter;
    SafeUrlLauncher.onThreatBlocked = (MaliciousLinkMatch hit) {
      unawaited(security.recordBlockedExternalUrl(hit));
      toasts.error(hit.title, hit.detail);
    };
    SafeUrlLauncher.onContentBlocked = (MaliciousLinkMatch hit) {
      toasts.warning(hit.title, hit.detail);
    };
    vpn.onNetworkConnectionsObserved = (List<CoreActivitySample> samples) =>
        security.inspectLiveConnections(
          samples,
          closeConnection: ClashApi.closeConnection,
        );
    vpn.onBlockedMaliciousHost = (String host, String category) =>
        security.handleObservedMaliciousHost(host);
    vpn.onTunnelConnected = () {
      motion.pulseAmbient();
      unawaited(motion.checkConnectCpuBudget());
      unawaited(security.scanNow(silent: true));
    };
    vpn.updateSettings(settings.settings);

    final PowerController power = PowerController(
      readStatus: native.powerStatus,
      enabled: settings.settings.batteryOptimization,
    );
    power.addListener(() {
      vpn.setBatterySaving(power.active);
      motion.setPowerSaving(power.lowOrSaving);
      security.setBatterySaving(power.lowOrSaving);
      auth.setBatterySaving(power.lowOrSaving);
    });
    power.start();

    settings.onDebugLogExpired = vpn.scheduleLiveReload;
    settings.addListener(() {
      vpn.updateSettings(settings.settings);
      power.setEnabled(settings.settings.batteryOptimization);
      tray
        ..notificationsEnabled = settings.settings.notificationsEnabled
        ..showSpeedInTray = settings.settings.showSpeedInTray;
      auth
        ..soundEnabled = settings.settings.soundEnabled
        ..notificationsEnabled = settings.settings.notificationsEnabled;
    });

    window.onBeforeQuit = () async {
      security.dispose();
      power.dispose();
      motion.dispose();
      await vpn.shutdownForExit();
    };

    auth.onFilterChanged = vpn.updateContentFilter;
    auth.onAccessRevoked = (String reason) {
      if (vpn.status.active) {
        unawaited(vpn.disconnect());
      }
      final String title = auth.account.channelDisabled
          ? 'عضویت در کانال تلگرام'
          : 'اشتراک متوقف شد';
      auth.recordLocalNotification(
        title: title,
        body: reason,
        level: 'warning',
      );
      toasts.error(title, reason);
    };
    auth.onSessionRevoked = (String reason) async {
      security.resetReportedCache();
      toasts.error('مجوز استفاده از این دستگاه لغو شد', reason);
      if (vpn.status.active) {
        await vpn.disconnect();
      }
    };
    await auth.restore();

    final SubscriptionController subscriptions = SubscriptionController(
      vpn: vpn,
      auth: auth,
      provisioner: provisioner,
    );
    auth.onSubscriptionClaimed = () async {
      await subscriptions.syncPersonal();
    };
    VpnStatus prevVpnStatus = vpn.status;
    vpn.addListener(() {
      final VpnStatus next = vpn.status;
      if (next == prevVpnStatus) return;
      final VpnStatus prev = prevVpnStatus;
      prevVpnStatus = next;
      if (auth.signedIn &&
          (next == VpnStatus.connected ||
              (prev == VpnStatus.connected && next == VpnStatus.disconnected))) {
        unawaited(auth.refreshAccount(silent: true));
      }
    });
    final UpdateController updates = UpdateController(
      native,
      service: UpdateService(preferredAbi: deviceAbi),
    );
    await OccasionService.instance.load();

    runApp(
      MultiProvider(
        providers: [
          Provider<NativeBridge>.value(value: native),
          Provider<WindowService>.value(value: window),
          Provider<SoundService>.value(value: sound),
          Provider<IpService>.value(value: ipService),
          Provider<TrayService>.value(value: tray),
          Provider<CoreProvisioner>.value(value: provisioner),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<PowerController>.value(value: power),
          ChangeNotifierProvider<MotionController>.value(value: motion),
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<SecurityScannerController>.value(
            value: security,
          ),
          ChangeNotifierProvider<ToastController>.value(value: toasts),
          ChangeNotifierProvider<VpnController>.value(value: vpn),
          ChangeNotifierProvider<SubscriptionController>.value(
            value: subscriptions,
          ),
          ChangeNotifierProvider<UpdateController>.value(value: updates),
        ],
        child: UmbrellaApp(windowService: window),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await tray.init();
      await subscriptions.loadCached();
      await updates.loadSkipped();
      security.startMonitoring();
      if (settings.settings.checkUpdatesOnStart) {
        unawaited(updates.checkIfDue(silent: true));
      }
      Timer.periodic(const Duration(minutes: 60), (_) {
        if (settings.settings.checkUpdatesOnStart) {
          unawaited(updates.checkIfDue(silent: true));
        }
      });
      bool syncing = false;
      int bgSyncCounter = 0;
      Timer.periodic(const Duration(minutes: 5), (_) {
        if (!auth.signedIn || syncing) {
          return;
        }
        bgSyncCounter++;
        if (!motion.appVisible && power.lowOrSaving && (bgSyncCounter % 3 != 0)) {
          return;
        }
        syncing = true;
        unawaited(() async {
          try {
            await auth.refreshAccount(silent: true);
            await subscriptions.syncPersonal();
          } finally {
            syncing = false;
          }
        }());
      });
      if (auth.signedIn) {
        unawaited(auth.fetchNotifications(includeHistory: true));
        unawaited(auth.refreshAccount(silent: true).then<void>((_) {}));
        unawaited(subscriptions.syncPersonal());
      }
    });
  }, (Object error, StackTrace stack) {
    AppCrashStore.record(
      error: error,
      stack: stack,
      source: 'zone',
    );
    AppLogger.instance.add(
      'خطای پیش بینی نشده: $error',
      level: 'error',
    );
  });
}
