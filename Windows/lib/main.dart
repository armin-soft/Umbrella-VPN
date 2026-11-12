import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
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
import 'vpn/vpn_controller.dart';

/// نقطه شروع برنامه: آماده سازی انبار داده، پنجره، سرویس ها و کنترلرها.
Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalStore.instance.init();

  final NativeBridge native = NativeBridge();
  final SoundService sound = SoundService();
  final WindowService window = WindowService(native);
  await window.init();

  final SettingsController settings = SettingsController(
    native: native,
    sound: sound,
    window: window,
  );
  await settings.load();

  final AuthController auth = AuthController(native: native);
  await auth.restore();

  final IpService ipService = IpService();
  final TrayService tray = TrayService(native);
  final CoreProvisioner provisioner = CoreProvisioner(native: native);
  // فهرست هسته ها و پوشه داده پیش از ساخت رابط خوانده می شود تا وضعیت هسته ها
  // از همان ابتدا درست نمایش داده شود.
  await provisioner.init();
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
  );
  vpn.updateSettings(settings.settings);
  settings.addListener(() => vpn.updateSettings(settings.settings));

  final SubscriptionController subscriptions =
      SubscriptionController(vpn: vpn);
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
    if (arguments.contains('--minimized') && settings.settings.minimizeToTray) {
      await window.hide();
    }
    await subscriptions.loadCached();
    unawaited(updates.loadSkipped());
    if (settings.settings.checkUpdatesOnStart) {
      unawaited(updates.check(silent: true));
    }
    if (auth.signedIn) {
      unawaited(auth.fetchNotifications());
      unawaited(subscriptions.fetchAll());
    }
  });
}
