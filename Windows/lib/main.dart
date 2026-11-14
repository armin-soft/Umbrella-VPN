import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/app_config.dart';
import 'core/storage.dart';
import 'models/models.dart';
import 'platform/native.dart';
import 'platform/services.dart';
import 'state/auth_controller.dart';
import 'state/settings_controller.dart';
import 'state/subscription_controller.dart';
import 'state/toast_controller.dart';
import 'state/update_controller.dart';
import 'vpn/cores.dart';
import 'vpn/hiddify_core.dart';
import 'vpn/vpn_controller.dart';

/// نقطه شروع برنامه: آماده سازی انبار داده، پنجره، سرویس ها و کنترلرها.
Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalStore.instance.init();

  final NativeBridge native = NativeBridge();
  // یک فراخوانی سبک تا مشخص شود پل بومی ویندوز واقعا بارگذاری شده است.
  final bool elevatedNow = await native.isElevated();
  final SoundService sound = SoundService();
  final WindowService window = WindowService(native);
  await window.init();

  final SettingsController settings = SettingsController(
    native: native,
    sound: sound,
    window: window,
  );
  await settings.load();
  await settings.migrateConnectionMode();

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
  await auth.restore();
  final CoreProvisioner provisioner = CoreProvisioner();
  // فهرست هسته ها و پوشه داده پیش از ساخت رابط خوانده می شود تا وضعیت هسته ها
  // از همان ابتدا درست نمایش داده شود.
  await provisioner.init();
  AppLogger.instance.add(
    '${AppConfig.appName} ${AppConfig.version} راه اندازی شد | '
    'پوشه نصب: ${provisioner.appDir}',
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
  // تنها هسته نسخه: هسته هیدیفای که با نام UmbrellaCli.exe نصب می شود.
  final String? corePath =
      await provisioner.locateBinary(HiddifyCore.cliBinary);
  if (corePath == null) {
    AppLogger.instance.add(
      'هسته ${HiddifyCore.cliBinary} در پوشه نصب پیدا نشد '
      '(${provisioner.bundledDir}); برنامه بدون هسته کار نمی کند.',
      level: 'error',
    );
  } else {
    AppLogger.instance.add('هسته هیدیفای آماده است: $corePath');
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
  );
  vpn.updateSettings(settings.settings);
  settings.addListener(() {
    vpn.updateSettings(settings.settings);
    // خاموش کردن صدا یا اعلان در تنظیمات، همان لحظه روی اعلان ها اثر می گذارد.
    auth
      ..soundEnabled = settings.settings.soundEnabled
      ..notificationsEnabled = settings.settings.notificationsEnabled;
  });
  // اگر حساب در میانه کار منقضی یا مسدود شد، اتصال همان لحظه بسته می شود.
  auth.onAccessRevoked = (String reason) {
    if (vpn.status.active) {
      unawaited(vpn.disconnect());
    }
    toasts.error('دسترسی اشتراک قطع شد', reason);
  };

  final SubscriptionController subscriptions =
      SubscriptionController(vpn: vpn, auth: auth);
  final UpdateController updates = UpdateController(native);
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
    unawaited(updates.loadSkipped());
    if (settings.settings.checkUpdatesOnStart) {
      unawaited(updates.check(silent: true));
    }
    // به روز رسانی خودکار پروفایل و اشتراک هر نیم ساعت؛ کاربر کاری نمی کند.
    Timer.periodic(const Duration(minutes: 30), (_) {
      if (!auth.signedIn) {
        return;
      }
      unawaited(() async {
        await auth.refreshAccount(silent: true);
        await subscriptions.syncPersonal();
      }());
    });
    if (auth.signedIn) {
      unawaited(auth.fetchNotifications());
      // اشتراک شخصی از سرور خوانده می شود؛ فقط اگر سرور چیزی نداد منابع عمومی
      // به عنوان پشتیبان بارگذاری می شوند.
      unawaited(() async {
        await subscriptions.syncPersonal();
        if (vpn.nodes.isEmpty) {
          await subscriptions.fetchAll();
        }
      }());
    }
  });
}
