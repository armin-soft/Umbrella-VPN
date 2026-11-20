import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/app_config.dart';
import 'core/persian.dart';
import 'core/storage.dart';
import 'models/models.dart';
import 'platform/native.dart';
import 'platform/services.dart';
import 'state/auth_controller.dart';
import 'state/settings_controller.dart';
import 'state/power_controller.dart';
import 'state/subscription_controller.dart';
import 'state/toast_controller.dart';
import 'state/update_controller.dart';
import 'vpn/cores.dart';
import 'vpn/umbrella_core.dart';
import 'vpn/vpn_controller.dart';

/// نقطه شروع برنامه: آماده سازی انبار داده، پنجره، سرویس ها و کنترلرها.
Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    AppLogger.instance.add(
      'خطای رابط کاربری: ${details.exceptionAsString()}',
      level: 'error',
    );
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppLogger.instance.add(
      'خطای پیش بینی نشده: $error',
      level: 'error',
    );
    return true;
  };
  await LocalStore.instance.init();

  final NativeBridge native = NativeBridge();
  // یک فراخوانی سبک تا مشخص شود پل بومی ویندوز واقعا بارگذاری شده است.
  final bool elevatedNow = await native.isElevated();
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

  final IpService ipService = IpService();
  final TrayService tray = TrayService(native);
  // صدا و بالون سینی به کنترلر حساب داده می شود تا اعلان تازه با صدا اعلام
  // شود (صدا فقط پس از آماده شدن سینی و تنظیمات کار می کند).
  final AuthController auth = AuthController(
    native: native,
    sound: sound,
    tray: tray,
  );
  auth
    ..soundEnabled = settings.settings.soundEnabled
    ..notificationsEnabled = settings.settings.notificationsEnabled;
  final CoreProvisioner provisioner = CoreProvisioner();
  // فهرست هسته ها و پوشه داده پیش از ساخت رابط خوانده می شود تا وضعیت هسته ها
  // از همان ابتدا درست نمایش داده شود.
  await provisioner.init();
  AppLogger.instance.add(
    '${AppConfig.appName} ${Fa.num(AppConfig.version)} راه اندازی شد',
  );
  if (!native.available) {
    AppLogger.instance.add(
      'پل بومی ویندوز بارگذاری نشد (${native.lastError})؛ '
      'کارهای حیاتی با نسخه جایگزین انجام می شود.',
      level: 'warning',
    );
  } else {
    AppLogger.instance.add(
      'پل بومی ویندوز آماده است | دسترسی مدیر: '
      '${elevatedNow ? 'بله' : 'خیر'}',
    );
  }
  // تنها هسته نسخه: موتور هسته که UmbrellaCli.exe (لانچر خود ما) آن را بار
  // می کند؛ کتابخانه هسته و کرونتش باید در پوشه هسته باشند.
  final String? corePath =
      await provisioner.locateBinary(UmbrellaCore.cliBinary);
  if (corePath == null) {
    AppLogger.instance.add(
      'هسته ${UmbrellaCore.cliBinary} در پوشه نصب پیدا نشد '
      '(${provisioner.bundledDir}); برنامه بدون هسته کار نمی کند.',
      level: 'error',
    );
  } else if (!UmbrellaCore.installed(provisioner.bundledDir)) {
    AppLogger.instance.add(
      'هسته پیدا شد ولی فایل های همراه آن کامل نیستند؛ کتابخانه هسته یا '
      'کرونت در پوشه هسته نیست، یا ${UmbrellaCore.cliBinary} کنار برنامه نیست. '
      'برنامه را با نصب کننده رسمی دوباره نصب کنید.',
      level: 'error',
    );
  } else {
    AppLogger.instance.add('هسته آمبرلا آماده است: $corePath');
  }
  final ToastController toasts = ToastController();

  final VpnController vpn = VpnController(
    native: native,
    ipService: ipService,
    sound: sound,
    tray: tray,
    provisioner: provisioner,
    settings: settings.settings,
    onSettingsChanged: (AppSettings next) => settings.update(next),
    onRequireElevation: () {
      toasts.warning(
        'دسترسی مدیر لازم است',
        'برنامه با دسترسی مدیر دوباره باز می شود.',
      );
    },
    onRequireCores: () {
      toasts.warning(
        'هسته اتصال در دسترس نیست',
        'نسخه نصب هسته ها را همراه ندارد؛ برنامه را با نصب کننده رسمی دوباره نصب کنید.',
      );
    },
    // بدون اشتراک سالم، هیچ اتصالی برقرار نمی شود.
    accessGuard: () => auth.account.canConnect ? '' : auth.account.accessReason,
    // اتصال خودکار فقط پس از معرفی، ورود به حساب و سالم بودن اشتراک مجاز است.
    canAutoConnect: () =>
        settings.landingSeen && auth.signedIn && auth.account.canConnect,
  );
  vpn.updateSettings(settings.settings);
  final PowerController power = PowerController(
    readStatus: native.powerStatus,
    enabled: settings.settings.batteryOptimization,
  );
  power.addListener(() => vpn.setBatterySaving(power.active));
  power.start();
  settings.onDebugLogExpired = vpn.scheduleLiveReload;
  settings.addListener(() {
    vpn.updateSettings(settings.settings);
    power.setEnabled(settings.settings.batteryOptimization);
    // خاموش کردن صدا یا اعلان در تنظیمات، همان لحظه روی اعلان ها اثر می گذارد.
    auth
      ..soundEnabled = settings.settings.soundEnabled
      ..notificationsEnabled = settings.settings.notificationsEnabled;
  });
  // هر مسیر خروج برنامه (دکمه بستن، سینی سیستم، خاموشی ویندوز یا نصب آپدیت)
  // پیش از نابود شدن پنجره، هسته و CLI را به طور کامل و قطعی می بندد.
  window.onBeforeQuit = () async {
    power.dispose();
    await vpn.shutdownForExit();
  };
  // همگام سازی زنده کنترل محتوا از ربات تلگرام یا تنظیمات برنامه روی موتور اتصال.
  auth.onFilterChanged = vpn.updateContentFilter;
  // اگر حساب در میانه کار منقضی یا مسدود شد، اتصال همان لحظه بسته می شود.
  auth.onAccessRevoked = (String reason) {
    if (vpn.status.active) {
      unawaited(vpn.disconnect());
    }
    auth.recordLocalNotification(
      title: 'اشتراک متوقف شد',
      body: reason,
      level: 'warning',
    );
    toasts.error('اشتراک متوقف شد', reason);
  };
  auth.onSessionRevoked = (String reason) async {
    toasts.error('مجوز استفاده از این دستگاه لغو شد', reason);
    if (vpn.status.active) {
      await vpn.disconnect();
    }
  };
  // نشست بازیابی شده را پس از نصب callback قطع اتصال بررسی کن تا اگر مجوزش
  // لغو شده بود، قبل از خروج اتصال VPN هم حتماً قطع شود.
  await auth.restore();

  final SubscriptionController subscriptions =
      SubscriptionController(vpn: vpn, auth: auth);
  auth.onSubscriptionClaimed = () async {
    await subscriptions.syncPersonal();
  };
  final UpdateController updates = UpdateController(native)
    ..onExitForInstall = window.quit;
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
        ChangeNotifierProvider<AuthController>.value(value: auth),
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
    // اگر اجرای قبلی ناگهان بسته شده باشد، پروکسی سیستمی بازمانده کاربر را بی
    // اینترنت می کند؛ در شروع اجرا پاک می شود.
    await native.disableSystemProxy();
    if (arguments.contains('--minimized') && settings.settings.minimizeToTray) {
      await window.hide();
    }
    await subscriptions.loadCached();
    await updates.loadSkipped();
    if (settings.settings.checkUpdatesOnStart) {
      unawaited(updates.checkIfDue(silent: true));
    }
    // بررسی خودکار دوره ای نسخه جدید در پس زمینه (کانال فعال کاربر).
    Timer.periodic(const Duration(minutes: 60), (_) {
      if (settings.settings.checkUpdatesOnStart) {
        unawaited(updates.checkIfDue(silent: true));
      }
    });
    // همگام سازی کاملا خودکار حساب، پنل، کنترل محتوا، طرح های هدیه و سرورها.
    bool syncing = false;
    Timer.periodic(const Duration(minutes: 5), (_) {
      if (!auth.signedIn || syncing) {
        return;
      }
      syncing = true;
      unawaited(() async {
        try {
          await auth.refreshAccount(silent: true);
          await auth.refreshFromPanel();
          await subscriptions.syncPersonal();
        } finally {
          syncing = false;
        }
      }());
    });
    if (auth.signedIn) {
      unawaited(auth.fetchNotifications(includeHistory: true));
      unawaited(auth.refreshFromPanel());
      // فقط اشتراک اختصاصی حساب کاربر واردشده دریافت می شود؛ هیچ منبع عمومی
      // یا رایگان وجود ندارد.
      unawaited(subscriptions.syncPersonal());
    }
  });
}
