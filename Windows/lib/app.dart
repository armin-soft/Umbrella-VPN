import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/app_config.dart';
import 'core/theme.dart';
import 'platform/services.dart';
import 'state/auth_controller.dart';
import 'state/settings_controller.dart';
import 'state/toast_controller.dart';
import 'ui/pages/landing_page.dart';
import 'ui/pages/login_page.dart';
import 'ui/shell/app_shell.dart';
import 'ui/widgets/shell_widgets.dart';

/// ریشه برنامه: تم، زبان فارسی و راست چین، و دروازه ورود.
class UmbrellaApp extends StatelessWidget {
  const UmbrellaApp({super.key, required this.windowService});

  final WindowService windowService;

  @override
  Widget build(BuildContext context) {
    final SettingsController settings = context.watch<SettingsController>();
    final ToastController toasts = context.watch<ToastController>();

    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      locale: const Locale('fa'),
      supportedLocales: const <Locale>[Locale('fa'), Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      scrollBehavior: const _UmbrellaScrollBehavior(),
      builder: (BuildContext context, Widget? child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: Stack(
        children: <Widget>[
          RootGate(windowService: windowService),
          ToastOverlay(controller: toasts),
        ],
      ),
    );
  }
}

/// نمایش صفحه معرف (یک بار)، سپس ورود، سپس برنامه اصلی.
class RootGate extends StatelessWidget {
  const RootGate({super.key, required this.windowService});

  final WindowService windowService;

  @override
  Widget build(BuildContext context) {
    final SettingsController settings = context.watch<SettingsController>();
    final AuthController auth = context.watch<AuthController>();

    if (!settings.landingSeen) {
      return LandingPage(onStart: settings.markLandingSeen);
    }
    if (!auth.signedIn) {
      return const LoginPage();
    }
    return AppShell(windowService: windowService);
  }
}

class _UmbrellaScrollBehavior extends MaterialScrollBehavior {
  const _UmbrellaScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
