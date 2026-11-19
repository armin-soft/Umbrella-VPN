import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbrella_vpn/core/app_config.dart';
import 'package:umbrella_vpn/core/storage.dart';
import 'package:umbrella_vpn/core/theme.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/platform/services.dart';
import 'package:umbrella_vpn/state/settings_controller.dart';
import 'package:umbrella_vpn/ui/pages/landing_page.dart';
import 'package:umbrella_vpn/ui/widgets/telegram_channel_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

Widget _hostApp({
  required Widget child,
  ThemeMode themeMode = ThemeMode.light,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: themeMode,
    builder: (BuildContext context, Widget? inner) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: inner ?? const SizedBox.shrink(),
      );
    },
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.instance.init();
  });

  setUp(() async {
    await LocalStore.instance.remove(StoreKeys.telegramChannelPromptAt);
  });

  group('نام کاربری یکپارچه کانال تلگرام (@UmbrellaVPN_Channel)', () {
    test('ثابت های برنامه، صفحه درباره، پوسته و ربات تلگرام همگی روی @UmbrellaVPN_Channel تنظیم شده اند', () {
      expect(AppConfig.channelUsername, 'UmbrellaVPN_Channel');
      expect(AppConfig.channelHandle, '@UmbrellaVPN_Channel');
      expect(AppConfig.channelUrl, 'https://t.me/UmbrellaVPN_Channel');
      expect(AppConfig.channelAppUrl, 'tg://resolve?domain=UmbrellaVPN_Channel');
      expect(TelegramChannelPrompt.repeatInterval, const Duration(days: 7));

      final String about = File('lib/ui/pages/about_page.dart').readAsStringSync();
      expect(about, contains('AppConfig.channelHandle'));
      expect(about, contains('TelegramChannelPrompt.openChannel()'));
      expect(about, contains('ltr: true'));

      final String shell = File('lib/ui/shell/app_shell.dart').readAsStringSync();
      expect(shell, contains('TelegramChannelPrompt.showIfDue(context)'));
      expect(shell, contains('_telegramInitTimer?.cancel()'));
      expect(shell, contains('_telegramPeriodicTimer?.cancel()'));
      expect(shell, contains('widget.windowService.isHiddenToTray'));

      final String botConfig =
          File('../Telegram-BOT/Core/Support/Bot-Config.php').readAsStringSync();
      expect(botConfig, contains("DEFAULT_CHANNEL_USERNAME = 'UmbrellaVPN_Channel'"));
      expect(
        botConfig,
        contains("DEFAULT_CHANNEL_URL = 'https://t.me/UmbrellaVPN_Channel'"),
      );

      final String botEnv =
          File('../Telegram-BOT/Config/Environment.php').readAsStringSync();
      expect(botEnv, contains("'https://t.me/UmbrellaVPN_Channel'"));

      final String gateway =
          File('../Telegram-BOT/Core/App/App-Gateway.php').readAsStringSync();
      expect(gateway, contains("'channel_url' => BotConfig::getChannelUrl()"));
    });
  });

  group('زمان بندی اولین نمایش و تکرار دقیق هر ۷ روز یک بار', () {
    test('در اولین اجرا بلافاصله نمایش داده می شود و سپس فقط پس از ۷ روز کامل تکرار می شود', () async {
      final DateTime t0 = DateTime.utc(2026, 11, 17, 12, 0, 0);

      // نخستین اجرا: هیچ سابقه ای ذخیره نشده -> باید نمایش داده شود.
      expect(TelegramChannelPrompt.readLastShown(), isNull);
      expect(
        TelegramChannelPrompt.isDue(lastShownAt: null, now: t0),
        isTrue,
      );

      // ثبت اولین نمایش.
      await TelegramChannelPrompt.markShown(at: t0);
      final DateTime? saved = TelegramChannelPrompt.readLastShown();
      expect(saved, t0);

      // پیش از ۷ روز کامل: نباید نمایش داده شود.
      for (final Duration delta in <Duration>[
        Duration.zero,
        const Duration(minutes: 5),
        const Duration(hours: 12),
        const Duration(days: 1),
        const Duration(days: 3),
        const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
      ]) {
        expect(
          TelegramChannelPrompt.isDue(lastShownAt: saved, now: t0.add(delta)),
          isFalse,
          reason: 'نباید پیش از ۷ روز نمایش داده شود: $delta',
        );
      }

      // راس ۷ روز و پس از آن: باید نمایش داده شود.
      final DateTime t1 = t0.add(const Duration(days: 7));
      expect(
        TelegramChannelPrompt.isDue(lastShownAt: saved, now: t1),
        isTrue,
      );
      expect(
        TelegramChannelPrompt.isDue(
          lastShownAt: saved,
          now: t0.add(const Duration(days: 10)),
        ),
        isTrue,
      );

      // ثبت نمایش دوم و بررسی چرخه ۷ روزه بعدی.
      await TelegramChannelPrompt.markShown(at: t1);
      final DateTime? saved2 = TelegramChannelPrompt.readLastShown();
      expect(
        TelegramChannelPrompt.isDue(
          lastShownAt: saved2,
          now: t1.add(const Duration(days: 6, hours: 23)),
        ),
        isFalse,
      );
      expect(
        TelegramChannelPrompt.isDue(
          lastShownAt: saved2,
          now: t1.add(const Duration(days: 7)),
        ),
        isTrue,
      );
    });

    test('عقب کشیده شدن ساعت ویندوز و مقدار نامعتبر باعث قفل شدن چرخه نمی شود', () async {
      final DateTime now = DateTime.utc(2026, 11, 17, 10, 0, 0);
      final DateTime future = now.add(const Duration(days: 180));

      await TelegramChannelPrompt.markShown(at: future);
      final DateTime? normalized =
          await TelegramChannelPrompt.normalizeClockSkewIfNeeded(now: now);
      expect(normalized, now);
      expect(TelegramChannelPrompt.readLastShown(), now);
      expect(
        TelegramChannelPrompt.isDue(
          lastShownAt: normalized,
          now: now.add(const Duration(days: 7)),
        ),
        isTrue,
      );

      // مقدار خراب در انبار محلی مثل اولین اجرا رفتار می کند.
      await LocalStore.instance.write(
        StoreKeys.telegramChannelPromptAt,
        'corrupted',
      );
      expect(TelegramChannelPrompt.readLastShown(), isNull);
      expect(
        TelegramChannelPrompt.isDue(
          lastShownAt: TelegramChannelPrompt.readLastShown(),
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('باز کردن هوشمند کانال تلگرام در دسکتاپ و وب', () {
    test('در صورت نصب بودن تلگرام دسکتاپ مستقیم با پروتکل tg باز می شود', () async {
      final List<(Uri, LaunchMode)> launched = <(Uri, LaunchMode)>[];
      final bool ok = await TelegramChannelPrompt.openChannel(
        canLaunch: (Uri uri) async => uri.scheme == 'tg',
        launch: (Uri uri, LaunchMode mode) async {
          launched.add((uri, mode));
          return true;
        },
      );
      expect(ok, isTrue);
      expect(launched, hasLength(1));
      expect(launched.single.$1.toString(), 'tg://resolve?domain=UmbrellaVPN_Channel');
      expect(launched.single.$2, LaunchMode.externalNonBrowserApplication);
    });

    test('در صورت نبود تلگرام دسکتاپ یا خطا، لینک رسمی https://t.me/UmbrellaVPN_Channel باز می شود', () async {
      final List<(Uri, LaunchMode)> launched = <(Uri, LaunchMode)>[];
      final bool ok = await TelegramChannelPrompt.openChannel(
        canLaunch: (Uri uri) async => false,
        launch: (Uri uri, LaunchMode mode) async {
          launched.add((uri, mode));
          return true;
        },
      );
      expect(ok, isTrue);
      expect(launched, hasLength(1));
      expect(launched.single.$1.toString(), 'https://t.me/UmbrellaVPN_Channel');
      expect(launched.single.$2, LaunchMode.externalApplication);
    });
  });

  group('رابط کاربری و تجربه کاربری گفت و گوی عضویت در کانال تلگرام', () {
    testWidgets('در هر دو تم روشن و تاریک با رنگ اختصاصی آمبرلا (نه آبی تلگرام)، چیدمان راست به چپ و انیمیشن نرم رندر می شود', (WidgetTester tester) async {
      final String dialogSrc =
          File('lib/ui/widgets/telegram_channel_dialog.dart').readAsStringSync();
      expect(dialogSrc, isNot(contains('0xFF229ED9')));
      expect(dialogSrc, isNot(contains('0xFF37BBFE')));
      expect(dialogSrc, isNot(contains('0xFF1A7FC1')));

      for (final ThemeMode mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
        final UmbrellaColors expectedColors =
            mode == ThemeMode.dark ? UmbrellaColors.dark : UmbrellaColors.light;
        final Brightness expectedBrightness =
            mode == ThemeMode.dark ? Brightness.dark : Brightness.light;

        await tester.pumpWidget(
          _hostApp(
            themeMode: mode,
            child: const TelegramChannelDialog(animate: true),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 1200));

        expect(find.text('@UmbrellaVPN_Channel'), findsOneWidget);
        expect(find.text('به تلگرام آمبرلا بپیوندید'), findsOneWidget);
        expect(
          find.text(
            'کانال رسمی آمبرلا را برای اخبار، نسخه های جدید و ترفندهای متصل ماندن دنبال کنید.',
          ),
          findsOneWidget,
        );
        expect(find.text('عضویت در کانال'), findsOneWidget);
        expect(find.text('بعداً'), findsOneWidget);
        expect(find.byIcon(Icons.telegram), findsNWidgets(2));
        expect(find.byIcon(Icons.auto_awesome), findsNWidgets(4));

        // بررسی تطابق کامل رنگ کارت، کادر، سربرگ، نشان و دکمه با پالت آمبرلا.
        final Dialog dialog = tester.widget<Dialog>(find.byType(Dialog));
        expect(dialog.backgroundColor, expectedColors.surface);
        expect(dialog.shadowColor, expectedColors.shadow);
        final RoundedRectangleBorder border =
            dialog.shape! as RoundedRectangleBorder;
        expect(border.side.color, expectedColors.border);

        final DecoratedBox header = tester.widget<DecoratedBox>(
          find.byKey(const Key('telegram_channel_header')),
        );
        final BoxDecoration headerDecoration =
            header.decoration as BoxDecoration;
        final LinearGradient headerGradient =
            headerDecoration.gradient! as LinearGradient;
        expect(
          headerGradient.colors,
          TelegramChannelDialog.headerGradientFor(
            expectedColors,
            expectedBrightness,
          ),
        );
        expect(headerGradient.colors[1], expectedColors.primary);
        expect(headerGradient.colors[2], expectedColors.primaryDeep);

        final Container avatar = tester.widget<Container>(
          find.byKey(const Key('telegram_channel_avatar')),
        );
        final BoxDecoration avatarDecoration =
            avatar.decoration! as BoxDecoration;
        expect(avatarDecoration.color, expectedColors.onPrimary);
        final Icon avatarIcon = tester.widget<Icon>(
          find.descendant(
            of: find.byKey(const Key('telegram_channel_avatar')),
            matching: find.byIcon(Icons.telegram),
          ),
        );
        expect(avatarIcon.color, expectedColors.primary);

        final Text titleText = tester.widget<Text>(
          find.text('به تلگرام آمبرلا بپیوندید'),
        );
        expect(titleText.style?.color, expectedColors.textPrimary);

        // بررسی جهت چپ به راست نشان آیدی کانال.
        final Text handleText = tester.widget<Text>(
          find.text('@UmbrellaVPN_Channel'),
        );
        expect(handleText.textDirection, TextDirection.ltr);
        expect(handleText.style?.color, expectedColors.onPrimary);

        // دکمه اصلی از رنگ برند آمبرلا استفاده می کند و در چیدمان راست به چپ
        // آیکون تلگرام در سمت راست متن قرار دارد.
        final Finder joinBtn = find.byKey(
          const Key('telegram_channel_join_button'),
        );
        final ButtonStyle joinStyle =
            tester.widget<ButtonStyleButton>(joinBtn).style!;
        expect(
          joinStyle.backgroundColor?.resolve(<WidgetState>{}),
          expectedColors.primary,
        );
        expect(
          joinStyle.foregroundColor?.resolve(<WidgetState>{}),
          expectedColors.onPrimary,
        );
        final Finder btnIcon = find.descendant(
          of: joinBtn,
          matching: find.byIcon(Icons.telegram),
        );
        final Finder btnLabel = find.text('عضویت در کانال');
        expect(
          tester.getCenter(btnIcon).dx,
          greaterThan(tester.getCenter(btnLabel).dx),
        );
        expect(tester.takeException(), isNull);
      }

      // آزادسازی کامل کنترلر انیمیشن بدون هیچ تیکر بازمانده.
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });

    testWidgets('دکمه عضویت و دکمه بعداً هر دو گفت و گو را می بندند و چرخه ۷ روزه را رعایت می کنند', (WidgetTester tester) async {
      const Key hostKey = Key('telegram_prompt_host');
      final DateTime day0 = DateTime.utc(2026, 11, 17, 9, 0, 0);
      int joinCalls = 0;

      await tester.pumpWidget(
        _hostApp(
          child: const SizedBox.shrink(key: hostKey),
        ),
      );

      // ۱. اولین نمایش: باز می شود و با زدن «بعداً» بسته می شود بدون باز کردن لینک.
      final Future<bool> firstShow = TelegramChannelPrompt.showIfDue(
        tester.element(find.byKey(hostKey)),
        now: day0,
        animate: false,
        onJoinLaunch: () async {
          joinCalls++;
          return true;
        },
      );
      await tester.pumpAndSettle();
      expect(find.byType(TelegramChannelDialog), findsOneWidget);

      await tester.tap(find.byKey(const Key('telegram_channel_later_button')));
      await tester.pumpAndSettle();
      expect(await firstShow, isTrue);
      expect(find.byType(TelegramChannelDialog), findsNothing);
      expect(joinCalls, 0);

      // ۲. سه روز بعد: نباید دوباره نمایش داده شود.
      final bool day3Shown = await TelegramChannelPrompt.showIfDue(
        tester.element(find.byKey(hostKey)),
        now: day0.add(const Duration(days: 3)),
        animate: false,
        onJoinLaunch: () async {
          joinCalls++;
          return true;
        },
      );
      await tester.pumpAndSettle();
      expect(day3Shown, isFalse);
      expect(find.byType(TelegramChannelDialog), findsNothing);

      // ۳. هفت روز بعد: دوباره نمایش داده می شود و با زدن «عضویت در کانال» لینک را باز می کند.
      final DateTime day7 = day0.add(const Duration(days: 7));
      final Future<bool> day7Show = TelegramChannelPrompt.showIfDue(
        tester.element(find.byKey(hostKey)),
        now: day7,
        animate: false,
        onJoinLaunch: () async {
          joinCalls++;
          return true;
        },
      );
      await tester.pumpAndSettle();
      expect(find.byType(TelegramChannelDialog), findsOneWidget);

      await tester.tap(find.byKey(const Key('telegram_channel_join_button')));
      await tester.pumpAndSettle();
      expect(await day7Show, isTrue);
      expect(find.byType(TelegramChannelDialog), findsNothing);
      expect(joinCalls, 1);

      // ۴. تا ۷ روز پس از نمایش دوم دوباره باز نمی شود؛ در روز چهاردهم باز می شود.
      final bool day13Shown = await TelegramChannelPrompt.showIfDue(
        tester.element(find.byKey(hostKey)),
        now: day7.add(const Duration(days: 6, hours: 23)),
        animate: false,
      );
      expect(day13Shown, isFalse);

      unawaited(
        TelegramChannelPrompt.showIfDue(
          tester.element(find.byKey(hostKey)),
          now: day7.add(const Duration(days: 7)),
          animate: false,
          onJoinLaunch: () async {
            joinCalls++;
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TelegramChannelDialog), findsOneWidget);

      // کلیک روی نشان @UmbrellaVPN_Channel نیز کانال را باز می کند.
      await tester.tap(find.byKey(const Key('telegram_channel_handle_badge')));
      await tester.pumpAndSettle();
      expect(find.byType(TelegramChannelDialog), findsNothing);
      expect(joinCalls, 2);
    });
  });

  group('پشتیبانی کامل تم روشن و تاریک در سراسر برنامه', () {
    test('تمام صفحات اصلی و صفحه معرفی کلید تغییر تم دارند و رنگ ثابت غیرتمی ندارند', () {
      for (final String path in <String>[
        'lib/ui/pages/landing_page.dart',
        'lib/ui/pages/login_page.dart',
        'lib/ui/shell/app_shell.dart',
      ]) {
        final String content = File(path).readAsStringSync();
        expect(content, contains('onToggleTheme:'), reason: path);
        expect(content, contains('darkTheme:'), reason: path);
      }

      // هیچ فایل صفحه ای در lib/ui/pages نباید Color(0x...) ثابت داشته باشد.
      final Directory pagesDir = Directory('lib/ui/pages');
      for (final FileSystemEntity entity in pagesDir.listSync()) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final String src = entity.readAsStringSync();
        expect(
          src.contains('Color(0x'),
          isFalse,
          reason: '${entity.path} must use UmbrellaColors for light/dark parity',
        );
      }

      // همگام سازی قاب بومی ویندوز با تم روشن، تاریک و هماهنگ با سیستم.
      expect(
        File('lib/app.dart').readAsStringSync(),
        contains('windowService.syncBrightness'),
      );
      expect(
        File('lib/platform/services.dart').readAsStringSync(),
        contains('setBrightness'),
      );
      expect(
        File('windows/runner/win32_window.cpp').readAsStringSync(),
        contains('AppsUseLightTheme'),
      );
    });

    testWidgets('صفحه معرفی در هر دو تم روشن و تاریک بدون خطا رندر می شود و کلید تم کار می کند', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final NativeBridge native = NativeBridge();
      final SettingsController settings = SettingsController(
        native: native,
        sound: SoundService(),
        window: WindowService(native),
      );
      addTearDown(settings.dispose);
      await settings.load();
      expect(settings.resolveBrightness(Brightness.light), Brightness.dark);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<WindowService>.value(value: WindowService(native)),
            ChangeNotifierProvider<SettingsController>.value(value: settings),
          ],
          child: Consumer<SettingsController>(
            builder: (BuildContext context, SettingsController s, _) {
              return MaterialApp(
                theme: AppTheme.light(),
                darkTheme: AppTheme.dark(),
                themeMode: s.themeMode,
                themeAnimationDuration: Duration.zero,
                builder: (BuildContext context, Widget? inner) => Directionality(
                  textDirection: TextDirection.rtl,
                  child: inner ?? const SizedBox.shrink(),
                ),
                home: LandingPage(onStart: () {}),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // شروع در حالت تاریک و تغییر فوری به حالت روشن با دکمه نوار بالا.
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        UmbrellaColors.dark.background,
      );
      await tester.tap(find.byIcon(Icons.light_mode_rounded));
      await tester.pumpAndSettle();
      expect(settings.settings.theme, ThemePreference.light);
      expect(settings.resolveBrightness(Brightness.dark), Brightness.light);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        UmbrellaColors.light.background,
      );

      // بازگشت فوری به حالت تاریک و بررسی حالت هماهنگ با ویندوز.
      await tester.tap(find.byIcon(Icons.dark_mode_rounded));
      await tester.pumpAndSettle();
      expect(settings.settings.theme, ThemePreference.dark);
      await settings.setTheme(ThemePreference.system);
      expect(settings.resolveBrightness(Brightness.light), Brightness.light);
      expect(settings.resolveBrightness(Brightness.dark), Brightness.dark);
      expect(tester.takeException(), isNull);
    });
  });

  group('اتصال خودکار در شروع برنامه (پیش فرض خاموش و بازنشانی امن)', () {
    test('پیش فرض خاموش است، مقدار قدیمی ذخیره شده را یک بار خاموش می کند و انتخاب تازه کاربر را نگه می دارد', () async {
      // ۱. پیش فرض نصب تازه: خاموش.
      expect(const AppSettings().autoConnect, isFalse);

      // ۲. تنظیمات قدیمی ذخیره شده در ویندوز بدون نسخه ترجیح: به خاموش بازمی گردد.
      final AppSettings migratedLegacy = AppSettings.fromJson(<String, dynamic>{
        'autoConnect': true,
      });
      expect(migratedLegacy.autoConnect, isFalse);

      // ۳. انتخاب صریح کاربر در نسخه ۱.۰.۰ به درستی ذخیره و بازیابی می شود.
      final NativeBridge native = NativeBridge();
      final SettingsController controller = SettingsController(
        native: native,
        sound: SoundService(),
        window: WindowService(native),
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.settings.autoConnect, isFalse);

      await controller.setAutoConnect(true);
      final SettingsController reloadedOn = SettingsController(
        native: native,
        sound: SoundService(),
        window: WindowService(native),
      );
      addTearDown(reloadedOn.dispose);
      await reloadedOn.load();
      expect(reloadedOn.settings.autoConnect, isTrue);

      await reloadedOn.setAutoConnect(false);
      final SettingsController reloadedOff = SettingsController(
        native: native,
        sound: SoundService(),
        window: WindowService(native),
      );
      addTearDown(reloadedOff.dispose);
      await reloadedOff.load();
      expect(reloadedOff.settings.autoConnect, isFalse);

      // ۴. نگهبان canAutoConnect و لغو تایمر تلاش مجدد در کنترلر اتصال وجود دارد.
      final String vpnSrc =
          File('lib/vpn/vpn_controller.dart').readAsStringSync();
      expect(vpnSrc, contains('canAutoConnect'));
      expect(vpnSrc, contains('_mayAutoConnectNow'));
      expect(
        File('lib/main.dart').readAsStringSync(),
        contains('canAutoConnect:'),
      );
    });
  });
}
