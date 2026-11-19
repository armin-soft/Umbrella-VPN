import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbrella_vpn/core/app_config.dart';
import 'package:umbrella_vpn/core/storage.dart';
import 'package:umbrella_vpn/core/theme.dart';
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
    testWidgets('در هر دو تم روشن و تاریک با چیدمان راست به چپ، آیدی چپ به راست و انیمیشن نرم رندر می شود', (WidgetTester tester) async {
      for (final ThemeMode mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
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

        // بررسی جهت چپ به راست نشان آیدی کانال.
        final Text handleText = tester.widget<Text>(
          find.text('@UmbrellaVPN_Channel'),
        );
        expect(handleText.textDirection, TextDirection.ltr);

        // در چیدمان راست به چپ، آیکون تلگرام داخل دکمه در سمت راست متن قرار دارد.
        final Finder joinBtn = find.byKey(
          const Key('telegram_channel_join_button'),
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
}
