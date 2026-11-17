import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// آزمون «قرارداد رابط کاربری»: قواعدی که کاربر صریحا خواسته و نباید بی صدا
/// برگردند. این آزمون کد را می خواند نه صفحه را، پس سریع است و در CI همیشه
/// جلوی بازگشت آن رفتارها را می گیرد.
void main() {
  String read(String path) => File(path).readAsStringSync();

  group('لغو مجوز دستگاه از تلگرام', () {
    test('درگاه دسترسی نشست را با اعتماد دستگاه می سنجد', () {
      final String gateway = read('../Telegram-BOT/Core/App/App-Gateway.php');
      expect(gateway.contains('Device_Trusted'), isTrue);
      expect(gateway.contains("'device_revoked'"), isTrue);
      expect(gateway.contains('`D`.`Is_Trusted`'), isTrue);
    });

    test('لغو دستگاه، اعلان می سازد و نشست های همان دستگاه را می بندد', () {
      final String bot = read('../Telegram-BOT/Bot/App-Link.php');
      expect(bot.contains('INSERT INTO `App_Notifications`'), isTrue);
      expect(bot.contains("'warning'"), isTrue);
      expect(bot.contains('UPDATE `App_Sessions` SET `Revoked_At` = CURRENT_TIMESTAMP'), isTrue);
      expect(bot.contains('مجوز لغو شد؛ برنامه از حساب خارج خواهد شد'), isTrue);
    });

    test('برنامه مجوز را دوره ای می سنجد، قطع اتصال را اعلام و سپس خارج می شود', () {
      final String auth = read('lib/state/auth_controller.dart');
      expect(auth.contains('Duration(seconds: 30)'), isTrue);
      expect(auth.contains('_handleDeviceRevoked(error.message)'), isTrue);
      expect(auth.contains("_tray?.balloon('مجوز این دستگاه لغو شد'"), isTrue);
      expect(auth.contains('_isStaleDeviceRevocation(item)'), isTrue);
      expect(auth.contains('مجوز این دستگاه لغو شد'), isTrue);
      expect(auth.contains('await signOut(callServer: false);'), isTrue);
      final String app = read('lib/main.dart');
      expect(app.contains('onSessionRevoked'), isTrue);
      expect(app.contains('مجوز استفاده از این دستگاه لغو شد'), isTrue);
    });
  });

  group('دکمه لغو اتصال', () {
    test('صفحه اتصال دکمه «لغو اتصال» دارد', () {
      final String page = read('lib/ui/pages/connect_page.dart');
      expect(page.contains('لغو اتصال'), isTrue);
      expect(page.contains('_cancelConnection'), isTrue);
    });

    test('کنترلر اتصال متد لغو دارد و حلقه تلاش را می شکند', () {
      final String controller = read('lib/vpn/vpn_controller.dart');
      expect(controller.contains('Future<void> cancel()'), isTrue);
      expect(controller.contains('_cancelRequested'), isTrue);
      expect(controller.contains('cancelled'), isTrue);
    });
  });

  group('تنظیمات هسته', () {
    test('فایل تنظیمات کامل است و پرچم های تکراری فرستاده نمی شوند', () {
      final String core = read('lib/vpn/umbrella_core.dart');
      // با `-d` هسته پیش فرض هایش را کنار می گذارد؛ اگر دی ان اس در فایل
      // نباشد، خالی می شود و هسته با «نشانی سرور نامعتبر» می بندد.
      expect(core.contains("'remote-dns-address'"), isTrue);
      expect(core.contains("'direct-dns-address'"), isTrue);
      expect(core.contains("'mtu'"), isTrue);
      expect(core.contains("'tun-implementation'"), isTrue);
      expect(core.contains('settingsPath.isEmpty'), isTrue);
      // تنظیمات جلسه هم باید همان فایل کامل را بنویسد.
      final String controller = read('lib/vpn/vpn_controller.dart');
      expect(controller.contains('UmbrellaCore.settingsJson('), isTrue);
      expect(controller.contains("'-d',"), isTrue);
    });

    test('آمادگی تونل با نشانی درست کارت شبکه سنجیده می شود', () {
      // هسته به تونلش 172.19.0.1/28 می دهد (v2/config/builder.go). ماسک
      // اشتباه /30 باعث می شد کارت شبکه هرگز پیدا نشود و اتصال سالم هم رد
      // شود («کارت شبکه تونل در ۲۵ ثانیه آماده نشد» در گزارش ۱٫۰۶).
      final String config = read('lib/core/app_config.dart');
      expect(config.contains("172.19.0.1/28"), isTrue);
      expect(config.contains("172.19.0.1/30"), isFalse);
      final String native = read('packages/umbrella_native/windows/system_ops.cpp');
      // تطبیق با بازه 172.19.0.0/28 و با نشانی آی پی وی ۶ تونل.
      expect(native.contains('0xAC130000u'), isTrue);
      expect(native.contains('ERROR_BUFFER_OVERFLOW'), isTrue);
    });

    test('سنجش تونل سریال است و هر نمونه فایل تنظیمات خودش را دارد', () {
      // هر نمونه دو پورت ثابت هسته را می خواهد؛ چند نمونه همزمان، همدیگر را
      // می کشتند و سنجش «۰ سرور» می داد.
      final String ping = read('lib/vpn/core_ping.dart');
      expect(ping.contains('int concurrency = 1'), isTrue);
      expect(ping.contains('settingsPath: settingsFile.path'), isTrue);
      expect(ping.contains('networkSettings: settings'), isTrue);
    });

    test('سنجش پینگ هیچ وقت هسته یتیم روی پورت ها نمی گذارد', () {
      // گزارش ۱٫۰۷: پیام «پورت ۱۷۰۷۸ در اختیار برنامه دیگری است» چهار بار
      // آمد، در حالی که مقصر خود برنامه بود. `Future.timeout` سنجش را رها
      // می کرد ولی نمونه هایش زنده می ماندند و پورت را گرفته نگه می داشتند.
      final String ping = read('lib/vpn/core_ping.dart');
      expect(ping.contains('final List<Process> _running'), isTrue);
      expect(ping.contains('Future<void> stopAll()'), isTrue);
      expect(ping.contains('_running.add(process)'), isTrue);
      expect(ping.contains('_running.remove(process)'), isTrue);
      // `Future.timeout` دیگر نباید دور سنجش باشد.
      final String controller = read('lib/vpn/vpn_controller.dart');
      expect(controller.contains('_corePing.stopAll()'), isTrue);
      expect(controller.contains('_stopProbes'), isTrue);
      // اتصال، پیش از هر کاری، سنجش در جریان را می بندد.
      final int connectAt = controller.indexOf('Future<ConnectOutcome> connect(');
      expect(connectAt, greaterThan(0));
      final String inConnect = controller.substring(
        connectAt,
        controller.indexOf('Future<_AttemptResult> _attempt('),
      );
      // و پیش از هر کار دیگری، نه بعد از آماده سازی.
      expect(
        inConnect.indexOf('_stopProbes'),
        lessThan(inConnect.indexOf('accessGuard?.call()')),
      );
    });

    test('سنجش و اتصال هیچ وقت همزمان پورت های هسته را نمی خواهند', () {
      final String controller = read('lib/vpn/vpn_controller.dart');
      // سنجش در حین اتصال آغاز نمی شود.
      expect(controller.contains('if (_status.busy) {'), isTrue);
      // و تایمر دوره ای در حین اتصال کاری نمی کند.
      expect(controller.contains('if (_status.active) {'), isTrue);
    });

    test('پیام «تاخیر تونل نتیجه نداد» هر بار تکرار نمی شود', () {
      final String controller = read('lib/vpn/vpn_controller.dart');
      expect(controller.contains('_tunnelFailureReported'), isTrue);
      // گزارش دوره ای «تاخیر تونل برای ۰ سرور» نباید سطح هشدار بگیرد وقتی
      // پینگ شبکه هست.
      final int warn = controller.indexOf('سنجش تاخیر تونل نتیجه نداد');
      expect(warn, greaterThan(0));
      final String before = controller.substring(warn - 900, warn);
      expect(before.contains('_tunnelFailureReported'), isTrue);
    });

    test('اگر پورت دست برنامه دیگری باشد، صاحبش در گزارش می آید', () {
      final String core = read('lib/vpn/umbrella_core.dart');
      expect(core.contains('Get-NetTCPConnection'), isTrue);
      // نام خام ویندوز (`17078=Hiddify`) نباید در گزارش بیاید؛ طبق قرارمان
      // در متن نمایش داده شده فقط نام «آمبرلا» می آید و هسته های رقیب
      // «یک هسته فیلترشکن دیگر» نامیده می شوند.
      final String controller = read('lib/vpn/vpn_controller.dart');
      expect(controller.contains('UmbrellaCore.portHolders(held)'), isFalse);
      expect(controller.contains('UmbrellaCore.holders(held, native: _native)'),
          isTrue);
      // بدون صبر، نمونه ای که تازه بسته شده «برنامه دیگری» حساب می شد.
      expect(controller.contains('const Duration(seconds: 5)'), isTrue);
    });

    test('هنگام سبز شدن، تونل سالم با یک سنجش تنها کشته نمی شود', () {
      // در ۱٫۰۱۲ سنجش وب تنها معیار بود و اتصال سالم را کشت، هم در
      // _verifyTunnel (خواندن آی پی خالی) و هم در _tickHealth.
      final String controller = read('lib/vpn/vpn_controller.dart');
      // خواندن آی پی که خالی برگردد دیگر باعث اتصال دوباره نمی شود.
      expect(controller.contains('اگر آی پی خوانده نشد، این هیچ چیزی را'), isTrue);
      // بررسی سلامت هم سه مدرک را می بیند، نه فقط سنجش وب.
      expect(controller.contains('_tunnelFlowsNow'), isTrue);
    });

    test('دو اتصال همزمان روی پورت ثابت هسته با هم نمی جنگند', () {
      final String controller = read('lib/vpn/vpn_controller.dart');
      expect(controller.contains('_connectInFlight'), isTrue);
      expect(controller.contains('یک اتصال در حال انجام است'), isTrue);
    });

    test('ریلیتی با موتور TLS ویندوز کشته نمی شود', () {
      // هسته برای گره بدون اثر انگشت، TLS ویندوز را انتخاب می کند و ریلیتی
      // را از انتخاب موتور کنار می گذارد؛ حاصل دست دادن پیش فرض Go و رد
      // شدن از طرف سرور است.
      final String core = read('lib/vpn/umbrella_core.dart');
      expect(core.contains("'use-system-tls-engine': false"), isTrue);
    });

    test('HTTP verification cannot be bypassed by stale core statistics', () {
      final String controller = read('lib/vpn/vpn_controller.dart');
      expect(controller.contains('final bool proxyFlows = await VerifiedProbe.check'), isTrue);
      expect(controller.contains('final bool flows = proxyFlows && (!plan.tun ||'), isTrue);
      expect(controller.contains('_coreReportsWorkingTunnel'), isFalse);
      expect(controller.contains('_clashTunnelVerdict'), isFalse);
    });

    test('نشانی سنجش سلامت گره، سنجش سرعت نیست', () {
      // تا ۱٫۰۱۴ کلید `connection-test-url` روی `speed.cloudflare.com` بود؛
      // همان دامنه از داخل ایران ۳۰۱ می دهد و هسته گره سالم را «no answer»
      // می خواند. سنجش سلامت باید یک نشانی سبک و همه جا باز باشد.
      final String config = read('lib/core/app_config.dart');
      expect(config.contains('connectionTestUrls'), isTrue);
      expect(config.contains('generate_204'), isTrue);

      final String core = read('lib/vpn/umbrella_core.dart');
      expect(
        core.contains("'connection-test-url': AppConfig.connectionTestUrls"),
        isTrue,
      );
      expect(
        core.contains("'connection-test-url': AppConfig.speedTestUrl"),
        isFalse,
      );
    });

    test('همه سرورهای سازگار به هسته داده می شوند، نه فقط یکی', () {
      // شکایت کاربر ۱٫۰٫۱۵: «کلی سرور هست ولی فقط یکی وصل می شود». علتش
      // این بود که فایل لینک هسته فقط یک خط داشت، پس خود هسته هم فقط
      // می توانست همان یک گره را بشناسد.
      final String controller = read('lib/vpn/vpn_controller.dart');
      expect(controller.contains('_linkPool'), isTrue);
      expect(controller.contains('_maxPoolLinks'), isTrue);
      // گره انتخاب شده اول فهرست است تا اولویت کاربر حفظ شود.
      expect(controller.contains('add(chosen);'), isTrue);
    });

    test('explicit server selection and disabled failover isolate the runtime pool', () {
      final String controller = read('lib/vpn/vpn_controller.dart');
      expect(controller.contains('_singleNodeSession = requested != null ||'), isTrue);
      expect(controller.contains('if (_singleNodeSession) return pool;'), isTrue);
      expect(controller.contains('? umbrellaCliBinary : UmbrellaCore.engineBinary'), isTrue);
      expect(controller.contains('preparationEpoch != _connectionEpoch'), isTrue);
      expect(read('lib/vpn/umbrella_core.dart').contains("'keep-top-batch': 4"), isTrue);
    });

    test('کل اشتراک امتحان می شود، نه چهار سرور اول', () {
      // شکایت کاربر ۱٫۰٫۱۹: رابط «تلاش ۱ از ۴» می نویشت و از ۳۳۱ سروری که
      // اشتراک خوانده بود فقط چهار تای اول امتحان می شد؛ هدیفای همه لینک
      // های داخل اشتراک را یک جا می سنجد. پس حلقه تلاش نباید روی چهار تای
      // اول بسته شود و فایل لینک هسته هم نباید روی ۳۰ لینک بسته شود.
      final String controller = read('lib/vpn/vpn_controller.dart');
      expect(controller.contains('list.length >= 4'), isFalse);
      expect(controller.contains('list..addAll(pinned)..addAll(ordinary)'), isTrue);
      expect(controller.contains('_maxPoolLinks = 30'), isFalse);
      expect(controller.contains('_maxPoolLinks = 1000'), isTrue);
      // بودجه زمانی برای وقتی هیچ سروری جواب نمی دهد، تا حلقه برای همیشه
      // روی «تلاش N از M» نماند.
      expect(controller.contains('_connectBudget'), isTrue);
    });

    test('هسته چند گره زنده نگه می دارد تا بتواند سوییچ کند', () {
      // با `keep-top: 3` اگر دو گره اول کند بودند جایگزینی نمی ماند. ۸
      // گره یعنی همیشه جای سوییچ هست.
      final String core = read('lib/vpn/umbrella_core.dart');
      expect(core.contains("'keep-top': 8"), isTrue);
      // `lowest` یعنی گروه انتخاب روی بالانسر کم ترین تاخیر می رود، پس
      // خود هسته سریع ترین را برمی دارد و هنگام افتادن سوییچ می کند.
      expect(core.contains("'default-proxy': 'lowest'"), isTrue);
    });

    test('پورت هسته فقط از هسته ای غیر از خودمان پس گرفته می شود', () {
      // در گزارش ۱٫۰۱۵ هسته ای که خودمان اجرا کردیم (شناسه ۱۱۳۵۲) فورا
      // بسته شد ولی صاحب پورت فرزندش بود (شناسه ۱۳۶۰۰). چون آن را
      // «بیگانه» دیدیم، سه دور صرف بستن فرزند شد و هر بار هسته تازه دوباره
      // همان پورت را گرفت.
      final String core = read('lib/vpn/umbrella_core.dart');
      expect(core.contains('holdsPortAgainstUs'), isTrue);
      final String controller = read('lib/vpn/vpn_controller.dart');
      expect(controller.contains('holder.holdsPortAgainstUs'), isTrue);
    });

    test('سلام ساعت روز، تاریخ کامل و ساعت زنده دارد', () {
      // کاربر خواست بالای صفحه «سلام آرمین ... صبح بخیر» با آیکون مناسب و
      // زیرش تاریخ شمسی با روز هفته و ساعت زنده باشد.
      final String persian = read('lib/core/persian.dart');
      expect(persian.contains('static String greeting('), isTrue);
      expect(persian.contains('صبح بخیر'), isTrue);
      expect(persian.contains('static String weekDay('), isTrue);
      // اندیس روز هفته باید (weekday - 1) باشد؛ با `% 7` یکشنبه «دوشنبه»
      // می شد.
      expect(persian.contains('weekDays[(time.weekday - 1) % 7]'), isTrue);

      final String clock = read('lib/ui/widgets/live_clock.dart');
      expect(clock.contains('Timer.periodic'), isTrue);
      expect(clock.contains('Fa.fullDateTime'), isTrue);

      final String page = read('lib/ui/pages/connect_page.dart');
      expect(page.contains('Fa.greeting()'), isTrue);
      expect(page.contains('LiveDateTimeLine'), isTrue);
    });

    test('پس از اتصال نام سرور نمایش داده نمی شود، فقط «به آمبرلا متصل شد»', () {
      // کاربر خواست هیچ جا نام سرور دیده نشود؛ فقط در گزارش ها بماند.
      final String page = read('lib/ui/pages/connect_page.dart');
      expect(page.contains('به آمبرلا متصل شد'), isTrue);
      expect(page.contains('activeNode?.name'), isFalse);

      // اعلان ویندوز و تولتیپ سینی هم نام سرور را نمی گویند.
      final String controller = read('lib/vpn/vpn_controller.dart');
      expect(controller.contains('متصل به \${node.name}'), isFalse);
      expect(controller.contains('\${node.name} | \${Fa.ms(node.pingMs)}'), isFalse);
      // ولی در گزارش، سرور و مشخصاتش هست.
      expect(controller.contains('اتصال به \${node.name}'), isTrue);
    });

    test('پینگ سرور متصل زیر وضعیت اتصال نشان داده می شود', () {
      final String page = read('lib/ui/pages/connect_page.dart');
      expect(page.contains('_PingLine'), isTrue);
      expect(page.contains('vpn.activePingMs'), isTrue);
    });

    test('نسخه در نوار کناری به شکل ساده 1.0.16 است', () {
      final String config = read('lib/core/app_config.dart');
      expect(config.contains('static String get versionLabel => version;'), isTrue);
      // پیشوند «نسخه» فقط در متن های جمله ای می آید، نه زیر منو.
      expect(config.contains('versionPhrase'), isTrue);
      final String nav = read('lib/ui/widgets/shell_widgets.dart');
      expect(nav.contains('AppConfig.versionLabel'), isTrue);
    });

    test('نوار بالا وضعیت را وسط و اعلان و تم را چپ می گذارد', () {
      final String shell = read('lib/ui/widgets/shell_widgets.dart');
      // وضعیت داخل Expanded و Center می آید (وسط)، اعلان و تم بعد از آن
      // یعنی سمت چپ در چیدمان راست چین.
      expect(shell.contains('_HeaderIconButton'), isTrue);
      expect(shell.contains('onNotifications'), isTrue);
      final String bar =
          shell.substring(shell.indexOf('class TitleBar'), shell.indexOf('class _HeaderIconButton'));
      expect(bar.contains('Center('), isTrue);
    });

    test('منوی خروج کامل برنامه از پوسته و نوار کناری حذف شده است', () {
      final String appShell = read('lib/ui/shell/app_shell.dart');
      expect(appShell.contains('ExitPage('), isFalse);
      expect(appShell.contains("label: 'خروج'"), isFalse);
      final String nav = read('lib/ui/widgets/shell_widgets.dart');
      expect(nav.contains('exitIndex'), isFalse);
      expect(nav.contains("label: 'خروج'"), isFalse);
    });

    test('اعلان ویندوز آیکون خود برنامه را دارد و آیکون سینی را پاک نمی کند', () {
      // ۱٫۰۱۸ با NIIF_INFO منتشر شد: حباب، آیکون «i» ویندوز را نشان می داد و
      // آیکون برنامه هیچ وقت دیده نمی شد. حالا NIIF_USER با یک HICON واقعی
      // ۳۲×۳۲ می آید، و اگر فایل آیکون نبود، آیکون خود exe استخراج می شود.
      final String tray = read('packages/umbrella_native/windows/tray_icon.cpp');
      expect(tray.contains('NIIF_USER | NIIF_LARGE_ICON'), isTrue);
      expect(tray.contains('data_.hBalloonIcon'), isTrue);
      expect(tray.contains('balloon_icon_'), isTrue);
      expect(tray.contains('ExtractIconExW'), isTrue);
      // به روز رسانی اعلان نباید آیکون و تولتیپ را صفر کند.
      expect(tray.contains('NIF_INFO | NIF_ICON | NIF_TIP'), isTrue);
      expect(tray.contains('NIF_TIP | NIF_ICON'), isTrue);
    });

    test('به روز رسانی از صفحه انتشار گیت هاب خوانده می شود، نه سرور پنل', () {
      final String config = read('lib/core/app_config.dart');
      expect(config.contains('releaseApiUrl'), isTrue);
      expect(config.contains('releasesPageUrl'), isTrue);
      // نشانی فهرست بهروزرسانی دیگر روی سرور پنل نیست.
      expect(config.contains('api/windows/update.json'), isFalse);

      final String services = read('lib/platform/services.dart');
      expect(services.contains('_checkGithubRelease'), isTrue);
      expect(services.contains('SHA256SUMS.txt'), isTrue);
      // دکمه دانلود باید واقعا مرورگر را باز کند، نه فقط گزارش بنویسد.
      final String updates = read('lib/state/update_controller.dart');
      expect(updates.contains('launchUrl'), isTrue);
    });

    test('چیدمان ویندوز ریسپانسیو است', () {
      final String nav = read('lib/ui/widgets/shell_widgets.dart');
      // نوار کناری بر اساس عرض پنجره باریک می شود و در حالت باریک فقط
      // آیکون با Tooltip نشان می دهد.
      expect(nav.contains('LayoutBuilder'), isTrue);
      expect(nav.contains('compact'), isTrue);
      expect(nav.contains('Tooltip'), isTrue);
    });

    test('حساب من: اشتراک من و بررسی نشانی حذف شده، سینک تلگرام اضافه شده', () {
      final String account = read('lib/ui/pages/account_page.dart');
      expect(account.contains('اشتراک من'), isFalse);
      expect(account.contains('بررسی نشانی های اشتراک'), isFalse);
      expect(account.contains('خواندن دوباره از پنل'), isFalse);
      expect(account.contains('_TelegramSyncButton'), isTrue);
      // سینک با شناسه حساب به ربات می رود، نه فقط صفحه ربات.
      expect(account.contains('https://t.me/UmbrellaVPN_BOT'), isTrue);
      expect(account.contains('_openTelegramBot'), isTrue);
    });

    test('بخش ابزار برنامه: تنظیمات، گزارش ها و دستگاه ریسپانسیو هستند', () {
      final String common2 = read('lib/ui/widgets/common.dart');
      expect(common2.contains('class ResponsiveColumns'), isTrue);
      final String device = read('lib/ui/pages/device_page.dart');
      expect(device.contains('ResponsiveColumns'), isTrue);
      final String about = read('lib/ui/pages/about_page.dart');
      expect(about.contains('LayoutBuilder'), isTrue);
    });

    test('درباره: بخش های فنی حذف شدند و لوگوی توسعه دهنده هست', () {
      final String about = read('lib/ui/pages/about_page.dart');
      expect(about.contains('اجزای فنی'), isFalse);
      expect(about.contains('سرویس های متصل'), isFalse);
      // لوگوی توسعه دهنده با همان تصویر برند.
      expect(about.contains('BrandAssets.logo'), isTrue);
      // بررسی اتصال جای مشخص خودش را دارد.
      expect(about.contains('_AccessCheckCard'), isTrue);
    });

    test('آزادسازی پورت هسته چند بار تلاش می کند، نه یک بار', () {
      // در گزارش ۱٫۰۱۴ سه شناسه پشت سر هم بسته شد (۱۱۸۶۰، ۵۲۳۶، ۵۲۴۴) و هر
      // سه بار بعدش `port 17078 is already in use` آمد: شناسه ای که بستیم
      // صاحب واقعی پورت نبود، یا بلافاصله پردازش تازه ای همان پورت را گرفت.
      final String controller = read('lib/vpn/vpn_controller.dart');
      expect(controller.contains('دوباره بررسی و آزادسازی می شود'), isTrue);
    });

    test('پورت های ثابت هسته پیش از اجرا آزاد می شوند', () {
      // دستور `run` هسته پورت ۱۷۰۷۸ و ۱۶۷۵۶ را همیشه می گیرد و پرچمی برای
      // عوض کردنشان ندارد؛ در ۱٫۰٫۵ فرستادن `--listen` هسته را با «unknown
      // flag» کشت. پس راه درست، آزاد کردن همان پورت ها است.
      final String core = read('lib/vpn/umbrella_core.dart');
      expect(core.contains('reservedPorts'), isTrue);
      expect(core.contains('releasePorts'), isTrue);
      expect(core.contains("'--listen'"), isFalse);
      final String controller = read('lib/vpn/vpn_controller.dart');
      expect(controller.contains('_freeCorePorts'), isTrue);
      // دلیل بسته شدن هسته به زبان کاربر هم گفته می شود.
      expect(controller.contains('_explainCoreExit'), isTrue);
    });
  });

  group('آزادسازی خودکار پورت', () {
    test('صاحب پورت پیدا می شود و می تواند بسته شود', () {
      // گزارش ۱٫۰٫۹: صاحب پورت ۱۷۰۷۸ یک نسخه دیگر از هسته بود که خودش را
      // Hiddify معرفی می کرد و کاربر باید دستی می بستش. حالا برنامه خودش
      // پیدایش می کند و می بندد.
      final String core = read('lib/vpn/umbrella_core.dart');
      expect(core.contains('static Future<List<PortHolder>> holders('), isTrue);
      expect(core.contains('static Future<bool> killPid('), isTrue);
      expect(core.contains('class PortHolder'), isTrue);

      // پیدا کردن صاحب پورت باید راه بومی و راه جایگزین داشته باشد.
      final String native = read('lib/platform/native.dart');
      expect(native.contains('pidsHoldingPort'), isTrue);
      expect(native.contains('processNameOf'), isTrue);
      expect(native.contains('processPathOf'), isTrue);
      expect(native.contains("'netstat'"), isTrue);

      // و در لایه بومی ویندوز هم واقعا پیاده شده باشد.
      final String ops = read('packages/umbrella_native/windows/system_ops.cpp');
      expect(ops.contains('SystemOps::PidsHoldingPort'), isTrue);
      expect(ops.contains('GetExtendedTcpTable'), isTrue);
      expect(ops.contains('QueryFullProcessImageNameW'), isTrue);
      final String plugin =
          read('packages/umbrella_native/windows/umbrella_native_plugin.cpp');
      expect(plugin.contains('"pidsHoldingPort"'), isTrue);
    });

    test('فقط هسته های شناخته شده بسته می شوند، نه هر برنامه ای', () {
      final String core = read('lib/vpn/umbrella_core.dart');
      expect(core.contains('bool get isForeignCore'), isTrue);
      // نام های شناخته شده هسته ها در فهرست سفید هستند
      expect(core.contains("'hiddify'"), isTrue);
      expect(core.contains("'sing-box'"), isTrue);
      expect(core.contains("'xray'"), isTrue);
      // نام تجاری هسته های دیگر هیچ وقت نمایش داده نمی شود؛ قاعده «فقط
      // آمبرلا» حتی در گزارش خطا.
      expect(core.contains('یک هسته فیلترشکن دیگر'), isTrue);
      // و این کار به اجازه کاربر بسته است
      final String controller = read('lib/vpn/vpn_controller.dart');
      expect(controller.contains('_settings.freeCorePorts'), isTrue);
      expect(read('lib/models/models.dart').contains('this.freeCorePorts = true'),
          isTrue);
      // تنظیم در صفحه تنظیمات هم هست
      expect(read('lib/ui/pages/settings_page.dart').contains('freeCorePorts'),
          isTrue);
    });

    test('همه پورت ها بررسی می شوند، نه فقط دو پورت ثابت', () {
      final String core = read('lib/vpn/umbrella_core.dart');
      expect(core.contains('static const List<int> appPorts'), isTrue);
      expect(core.contains('static const List<int> allPorts'), isTrue);
      final String controller = read('lib/vpn/vpn_controller.dart');
      expect(controller.contains('_heldPorts(UmbrellaCore.appPorts)'), isTrue);
      expect(controller.contains('_killOwnCores'), isTrue);
    });

    test('اگر پورت آزاد نشد، دلیلش دقیق گفته می شود', () {
      final String controller = read('lib/vpn/vpn_controller.dart');
      expect(controller.contains('چرا خودکار بسته نشد'), isTrue);
      expect(controller.contains('برنامه های صاحب پورت'), isTrue);
      // و هیچ وقت ادعا نمی کند که پورت آزاد شد در حالی که نشده
      expect(controller.contains('پورت \$ports آزاد نشد'), isTrue);
    });
  });

  group('گزارش ها و خطاها', () {
    test('هر خطا می تواند جزئیات کامل داشته باشد', () {
      final String utils = read('lib/core/utils.dart');
      expect(utils.contains('class LogDetail'), isTrue);
      expect(utils.contains('final List<LogDetail> details'), isTrue);
      expect(utils.contains('bool get hasDetails'), isTrue);
    });

    test('گزارش هسته کامل نگه داشته می شود، نه ۶۰۰ نویسه آخر', () {
      final String controller = read('lib/vpn/vpn_controller.dart');
      // جزئیات باید خروجی کامل هسته را بیاورد.
      expect(controller.contains('_coreDiagnostics'), isTrue);
      expect(controller.contains('خروجی کامل هسته'), isTrue);
      // فرمان، مسیرها، سرور و وضعیت پورت ها هم بخشی از جزئیات اند.
      expect(controller.contains('فرمان اجرا و مسیرها'), isTrue);
      expect(controller.contains('سروری که با آن تلاش شد'), isTrue);
      expect(controller.contains('پورت های هسته در همین لحظه'), isTrue);
      // خلاصه دیگر نباید متن چسبیده ۶۰۰ نویسه ای باشد.
      expect(controller.contains('maxChars = 300'), isTrue);
      expect(controller.contains('maxChars = 600'), isFalse);
    });

    test('خطاهای مهم جزئیات دارند', () {
      final String controller = read('lib/vpn/vpn_controller.dart');
      // بلافاصله بسته شدن هسته
      expect(controller.contains('details: await _coreDiagnostics'), isTrue);
      // پورت در اختیار برنامه دیگر (حالا خودکار بسته می شود)
      expect(controller.contains('چرا خودکار بسته نشد'), isTrue);
      // سروری برای اجرا نبود
      expect(controller.contains('_whyNoUsableServer'), isTrue);
      expect(controller.contains('_protocolBreakdown'), isTrue);
      // هسته در نصب نبود
      expect(controller.contains('کجای نصب را بگردید'), isTrue);
    });

    test('صفحه گزارش ها جزئیات را باز می کند و کپی می کند', () {
      final String page = read('lib/ui/pages/logs_page.dart');
      expect(page.contains('_DetailPanel'), isTrue);
      expect(page.contains('جزئیات کامل'), isTrue);
      expect(page.contains('کپی جزئیات'), isTrue);
      // باز کردن همه خطاها با یک کلیک
      expect(page.contains('باز کردن جزئیات همه خطاها'), isTrue);
      // متن خام هسته باید کامل و قابل انتخاب باشد
      expect(page.contains('SelectableText'), isTrue);
    });

    test('فایل گزارش جزئیات و اطلاعات محیط را هم دارد', () {
      final String services = read('lib/platform/services.dart');
      expect(services.contains('environmentText'), isTrue);
      expect(services.contains('lineDetailText'), isTrue);
      // جزئیات با تورفتگی زیر همان خط در فایل می آید
      expect(services.contains('── \${detail.title} ──'), isTrue);
      // فایل ذخیره شده اطلاعات محیط را هم بالای خود دارد
      expect(services.contains('await environmentText()'), isTrue);
    });
  });

  group('نسخه', () {
    test('نسخه در همه فایل ها یکی است و هیچ جا دستی تکرار نمی شود', () {
      // در ۱٫۰٫۸ اسکریپت ساخت نصب کننده نسخه ۱٫۰٫۷ را دستی نگه داشته بود؛
      // نصب کننده تازه ساخته می شد ولی اسکریپت دنبال فایل نسخه قبلی می گشت و
      // CI را می شکست. حالا نسخه فقط در app_config.dart است.
      final String config = read('lib/core/app_config.dart');
      final RegExpMatch? match =
          RegExp(r"static const String version = '([0-9.]+)'").firstMatch(config);
      expect(match, isNotNull);
      final String version = match!.group(1)!;
      expect(read('pubspec.yaml').contains('version: $version+'), isTrue);
      expect(
        read('installer/umbrella.iss').contains('#define AppVersion "$version"'),
        isTrue,
      );
      // برچسب نمایشی نسخه از همان عدد ساخته می شود؛ در ۱٫۰٫۸ اینجا هنوز
      // «نسخه ۱٫۰٫۰» نوشته بود و کاربر نسخه غلط می دید.
      expect(config.contains('static String get versionLabel'), isTrue);
      expect(config.contains('نسخه ۱٫۰٫۰'), isFalse);


    });
  });

  group('صفحه اتصال', () {
    test('بخش پایین که نام سرور را نشان می داد حذف شده است', () {
      final String page = read('lib/ui/pages/connect_page.dart');
      expect(page.contains('_ActiveServerBar'), isFalse);
      expect(page.contains('_MiniStat'), isFalse);
    });

    test('آی پی دستگاه هرگز نامشخص نیست', () {
      final String page = read('lib/ui/pages/connect_page.dart');
      expect(page.contains('_deviceIp'), isTrue);
      // آی پی fallbackهای محلی دارد؛ فقط خود helper نباید dash پیش فرض داشته باشد.
      final String helper = page.substring(
        page.indexOf('String _deviceIp('),
        page.indexOf('static String _flagForIp'),
      );
      expect(helper.contains("'—'"), isFalse);
    });
  });

  group('منوی کناری', () {
    test('نام سازنده در پایین منو نمایش داده نمی شود', () {
      final String nav = read('lib/ui/widgets/shell_widgets.dart');
      expect(nav.contains('AppConfig.developer'), isFalse);
      expect(nav.contains('آرمین سافت'), isFalse);
    });
  });

  group('دستگاه من', () {
    test('فقط اطلاعات دستگاه را نشان می دهد', () {
      // فقط خطوط کد بررسی می شوند؛ توضیح بالای فایل می تواند این واژه ها را
      // برای توضیح جابه جایی داشته باشد.
      final List<String> code = read('lib/ui/pages/device_page.dart')
          .split('\n')
          .where((String line) => !line.trimLeft().startsWith('//'))
          .toList();
      for (final String moved in <String>[
        'هسته اتصال',
        'مدت اتصال',
        'حالت اتصال',
        'سرور فعال',
        'تایید عبور ترافیک',
      ]) {
        expect(
          code.any((String line) => line.contains(moved)),
          isFalse,
          reason: '$moved باید در صفحه دیگری باشد',
        );
      }
    });

    test('آمار اتصال در صفحه اتصال اصلی است و صفحه منوی جداگانه ندارد', () {
      final String page = read('lib/ui/pages/connect_page.dart');
      expect(page.contains('_ConnectionStats'), isTrue);
      expect(page.contains('مدت اتصال'), isTrue);
      expect(page.contains('دریافتی'), isTrue);
      expect(page.contains('ارسالی'), isTrue);
      final String shell = read('lib/ui/shell/app_shell.dart');
      expect(shell.contains('ConnectionPage('), isFalse);
      expect(shell.contains("label: 'وضعیت اتصال'"), isFalse);
    });
  });

  group('اعلان ها', () {
    test('اعلان تازه با صدا اعلام می شود', () {
      final String auth = read('lib/state/auth_controller.dart');
      expect(auth.contains("_sound?.play('notify')"), isTrue);
      expect(auth.contains('_announce('), isTrue);
    });

    test('صدای اعلان در دارایی های برنامه هست', () {
      expect(File('assets/sounds/notify.wav').existsSync(), isTrue);
      final String pubspec = read('pubspec.yaml');
      expect(pubspec.contains('assets/sounds/'), isTrue);
    });
  });

  group('هسته', () {
    test('تنها هسته همراه نسخه، موتور هسته است', () {
      final String manifest = read('assets/cores/manifest.json');
      final Map<String, dynamic> json =
          jsonDecode(manifest) as Map<String, dynamic>;
      final List<dynamic> cores = json['cores'] as List<dynamic>;
      expect(cores.length, 1);
      final Map<String, dynamic> core = cores.first as Map<String, dynamic>;
      expect(core['id'], 'hiddify');
      expect(core['cli_prefix'], 'umbrella');
      expect(core['binary'], 'UmbrellaCli.exe');
      expect(core['inside'], 'UmbrellaCore.dll');
      final String text = manifest.toLowerCase();
      for (final String gone in <String>[
        'sing-box',
        'xray',
        'mihomo',
        'clash-meta',
        'mieru',
        'wireguard-go',
        'amneziawg',
      ]) {
        expect(text.contains(gone), isFalse, reason: gone);
      }
    });

    test('هسته با خط فرمان خودش اجرا می شود', () {
      final String core = read('lib/vpn/umbrella_core.dart');
      expect(core.contains("'run'"), isTrue);
      expect(core.contains("'-c'"), isTrue);
      expect(core.contains("'--in-proxy-port'"), isTrue);
      expect(core.contains("'--tun'"), isTrue);
      expect(core.contains("'--system-proxy'"), isTrue);
      // لانچرهای آمبرلا، با همان آرگومان های خط فرمان موتور.
      expect(core.contains('UmbrellaCli.exe'), isTrue);
      expect(core.contains('UmbrellaCoreEngine.exe'), isTrue);
    });

    test('هیچ هسته دستی دیگری اجرا نمی شود', () {
      for (final String path in <String>[
        'lib/vpn/vpn_controller.dart',
        'lib/vpn/core_ping.dart',
        'lib/vpn/cores.dart',
      ]) {
        final String text = read(path);
        for (final String gone in <String>[
          'sing-box.exe',
          'xray.exe',
          'mihomo.exe',
          'mieru.exe',
          'amneziawg.exe',
        ]) {
          expect(text.contains(gone), isFalse, reason: '$path → $gone');
        }
      }
    });

    test('نام سرور در گزارش ها دوبار «سرور» نمی گیرد', () {
      final String controller = read('lib/vpn/vpn_controller.dart');
      expect(controller.contains('سرور سرور'), isFalse);
      expect(controller.contains('_nodeLabel'), isTrue);
    });
  });

  group('فایل های اجرایی هسته', () {
    test('لانچر کتابخانه را از مسیر بار می کند، نه با پیوند نام', () {
      // اگر نام کتابخانه در جدول واردات فایل اجرایی باشد، ویندوز آن را با
      // 0xC0000135 می بندد (همان خطای ۱٫۰٫۲). لانچر باید خودش بارش کند.
      final String launcher = read('native/umbrella_launcher.c');
      expect(launcher.contains('LoadLibraryExW'), isTrue);
      expect(launcher.contains('GetProcAddress'), isTrue);
      expect(launcher.contains('"parseCli"'), isTrue);
      expect(launcher.contains('SetDllDirectoryW'), isTrue);
      expect(launcher.contains('CommandLineToArgvW'), isTrue);
      // هیچ جا امضای dllimport ندارد.
      expect(launcher.contains('__declspec(dllimport) parseCli'), isFalse);
    });

    test('هر سه فایل اجرایی از همان منبع و با آیکون آمبرلا ساخته می شوند', () {
      final String cmake = read('windows/CMakeLists.txt');
      for (final String exe in <String>[
        'UmbrellaCli',
        'UmbrellaAdmin',
        'UmbrellaCoreEngine',
      ]) {
        expect(cmake.contains('OUTPUT_NAME "$exe"'), isTrue, reason: exe);
      }
      final String res = read('native/umbrella_launcher.rc');
      expect(res.contains('app_icon.ico'), isTrue);
      expect(res.contains('فیلترشکن آمبرلا'), isTrue);
      // آیکون با شناسه 1، همان چیزی که Explorer و پنجره UAC می خوانند.
      expect(res.contains('1 ICON'), isTrue);
      // مانیفست مدیر با گزینه پیوند دهنده اضافه می شود.
      expect(cmake.contains('requireAdministrator'), isTrue);
    });

    test('هیچ متن نمایشی در برنامه نام هیدیفای ندارد', () {
      // خطوط توضیحی (کامنت) می توانند برای سازنده از هیدیفای حرف بزنند؛ آنچه
      // ممنوع است، متن هایی است که به کاربر نشان داده می شود.
      final List<File> files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File file) => file.path.endsWith('.dart'))
          .toList();
      expect(files, isNotEmpty);
      // تنها مورد عمدی که مجاز است: شناسه هسته در فهرست همراه نسخه (داخلی،
      // هیچ جا نمایش داده نمی شود). نام کتابخانه روی دیسک دیگر استثنا نیست؛
      // کاربر آن را در Explorer می بیند و باید آمبرلا باشد.
      const List<String> allowed = <String>[
        "static const String id = 'hiddify';",
        "static const String tunAdapterHint = 'hiddify';",
        // فهرست داخلی هسته هایی که پورت را می توانند گرفته باشند. این نام
        // هیچ وقت نمایش داده نمی شود: PortHolder.label برای هسته های
        // شناخته شده «یک هسته فیلترشکن دیگر» برمی گرداند.
        "'hiddify',",
      ];
      for (final File file in files) {
        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final String line = lines[i].trimLeft();
          if (line.startsWith('//')) {
            continue;
          }
          if (allowed.any((String ok) => line.contains(ok))) {
            continue;
          }
          final String lower = line.toLowerCase();
          expect(lower.contains('هیدیفای'), isFalse,
              reason: '${file.path}:${i + 1} → $line');
          expect(lower.contains('hiddify'), isFalse,
              reason: '${file.path}:${i + 1} → $line');
        }
      }
      expect(read('lib/main.dart').contains('هسته آمبرلا آماده است'), isTrue);
    });
  });

  group('اشتراک', () {
    test('مسیر مرده mihomo جایی ساخته نمی شود', () {
      for (final String path in <String>[
        'lib/core/app_config.dart',
        'lib/data/subscription_endpoints.dart',
      ]) {
        final String text = read(path);
        expect(text.contains("'mihomo/all.yml'"), isFalse, reason: path);
      }
    });

    test('مسیر درست کلش متا در فهرست است', () {
      final String endpoints = read('lib/data/subscription_endpoints.dart');
      expect(endpoints.contains("'clash/meta/all.yml'"), isTrue);
    });
  });

  group('دور ۳۲ — اتصال واقعی، پرچم و آیکون', () {
    test('پاسخ ۴xx هرگز مدرک عبور ترافیک نیست', () {
      // کلادفلر برای درخواست ۲۰۴ از ایران ۴۰۳ می داد و ما آن را «موفق»
      // می شمردیم؛ همین «وصل شدن الکی» را ساخت.
      final String probe = read('lib/vpn/tunnel_probe.dart');
      expect(probe.contains('code >= 200 && code < 400'), isTrue);
      final String text = read('lib/vpn/vpn_controller.dart');
      expect(text.contains('minimumSuccesses: 2'), isTrue);
      final String verified = read('lib/vpn/verified_probe.dart');
      expect(verified.contains('status == 204 && body.isEmpty'), isTrue);
      expect(verified.contains('request.followRedirects = false'), isTrue);
    });

    test('تغییر آی پی به تنهایی اتصال را تایید نمی کند', () {
      final String text = read('lib/vpn/vpn_controller.dart');
      expect(text.contains('final bool ipChanged'), isTrue);
      expect(text.contains('_tunnelVerified = ipChanged && passes;'), isTrue);
    });

    test('آی پی کش شده از مسیر تونل برنمی گردد', () {
      final String services = read('lib/platform/services.dart');
      // کش قدیمی آی پی واقعی کاربر بود و اتصال بی ترافیک را تایید می کرد.
      // حالا وقتی درخواست از مسیر پروکسی/تونل رفته، کش برنمی گردد و
      // «ناشناخته» ناشناخته می ماند.
      expect(services.contains('GeoInfo.empty'), isTrue);
      expect(services.contains('if (proxy.isNotEmpty)'), isTrue);
    });

    test('پورت هسته با تلاش دوباره آزاد می شود، نه یک بار', () {
      final String text = read('lib/vpn/vpn_controller.dart');
      expect(text.contains('Future<bool> _freeCorePortsWithRetry()'), isTrue);
      expect(text.contains('_freeCorePortsWithRetry()'), isTrue);
      expect(text.contains('_sweepOrphanChildren'), isTrue);
    });

    test('اعلان ویندوز آیکون خود برنامه را می آورَد', () {
      final String tray =
          read('packages/umbrella_native/windows/tray_icon.cpp');
      expect(tray.contains('NIIF_USER'), isTrue);
      expect(tray.contains('NIIF_LARGE_ICON'), isTrue);
      expect(tray.contains('balloon_icon_'), isTrue);
      expect(tray.contains('ExtractIconExW'), isTrue);
      final String runner = read('windows/runner/main.cpp');
      expect(runner.contains('SetCurrentProcessExplicitAppUserModelID'), isTrue);
      final String iss = read('installer/umbrella.iss');
      expect(iss.contains('AppUserModelID: "Umbrella.VPN.Desktop"'), isTrue);
    });

    test('همه صفحه ها هدر یکسان دارند', () {
      for (final String page in <String>[
        'device_page',
        'account_page',
        'logs_page',
        'updates_page',
        'settings_page',
        'about_page',
      ]) {
        expect(
          read('lib/ui/pages/$page.dart').contains('PageHeader('),
          isTrue,
          reason: page,
        );
      }
    });

    test('متن محیط گزارش، فارسی و با ارقام فارسی است', () {
      final String services = read('lib/platform/services.dart');
      expect(services.contains('_systemLabel()'), isTrue);
      expect(
        services.contains('Platform.operatingSystemVersion}'),
        isFalse,
        reason: 'رشته خام ویندوز نباید در گزارش بیاید',
      );
    });
  });

  group('دور ۳۱ — تایید واقعی تونل', () {
    String controller() => read('lib/vpn/vpn_controller.dart');

    test('byte counters and log messages cannot mark a connection verified', () {
      final String text = controller();
      expect(text.contains('grownRx >= grownTx'), isFalse);
      expect(text.contains('return _coreReportsWorkingTunnel'), isFalse);
      expect(text.contains('Future<bool> _trafficReturns('), isTrue);
      expect(text.contains('VerifiedProbe.check'), isTrue);
    });

    test('verification uses HTTPS and an explicit proxy, without redirects', () {
      final String text = read('lib/vpn/verified_probe.dart');
      expect(text.contains('https://cp.cloudflare.com/generate_204'), isTrue);
      expect(text.contains('https://www.gstatic.com/generate_204'), isTrue);
      expect(text.contains('findProxy'), isTrue);
      expect(text.contains('request.followRedirects = false'), isTrue);
      expect(text.contains('badCertificateCallback'), isFalse);
    });
  });

  group('دور ۳۱ — منو و ظاهر', () {
    test('حالت انتخاب سرور دستی جایی در رابط کاربری نیست', () {
      for (final String path in <String>[
        'lib/ui/pages/connect_page.dart',
        'lib/ui/pages/settings_page.dart',
        'lib/ui/shell/app_shell.dart',
      ]) {
        final String text = read(path);
        expect(text.contains('انتخاب دستی'), isFalse, reason: path);
        expect(text.contains('SelectionMode.manual'), isFalse, reason: path);
      }
      // لیست قابل نمایش، حالت دستی را ندارد.
      final String models = read('lib/models/models.dart');
      expect(models.contains('SelectionModeList.visible'), isTrue);
      final int visibleAt =
          models.indexOf('static const List<SelectionMode> visible');
      final int visibleEnd = models.indexOf('];', visibleAt);
      final String visibleBody =
          models.substring(visibleAt, visibleEnd);
      expect(visibleBody.contains('SelectionMode.manual'), isFalse);
      // و در بارگذاری تنظیمات، دستی به خودکار تبدیل می شود.
      expect(models.contains('_withoutManual'), isTrue);
    });

    test('منوی خروج برنامه نمایش داده نمی شود', () {
      final String shell = read('lib/ui/widgets/shell_widgets.dart');
      final String appShell = read('lib/ui/shell/app_shell.dart');
      expect(shell.contains("label: 'خروج'"), isFalse);
      expect(appShell.contains("label: 'خروج'"), isFalse);
      expect(appShell.contains('ExitPage('), isFalse);
    });

    test('صفحه های اصلی پوسته مدرن و ریسپانسیو هستند', () {
      for (final String path in <String>[
        'lib/ui/pages/device_page.dart',
        'lib/ui/pages/account_page.dart',
      ]) {
        final String text = read(path);
        expect(text.contains('GlassCard'), isTrue, reason: path);
        expect(text.contains('SectionHeader'), isTrue, reason: path);
        expect(text.contains('LayoutBuilder'), isTrue, reason: path);
      }
      final String device = read('lib/ui/pages/device_page.dart');
      expect(device.contains('LiveDateTimeLine'), isFalse);
      final String connect = read('lib/ui/pages/connect_page.dart');
      expect(connect.contains('GlassCard'), isTrue);
      expect(connect.contains('LayoutBuilder'), isTrue);
      expect(connect.contains('LiveDateTimeLine'), isTrue);
    });
  });

  group('حذف نرم افزار', () {
    test('پوشه نصب کاملا برداشته می شود، نه فقط فایل های نصب شده', () {
      // شکایت کاربر: بعد از «حذف برنامه» پوشه D:\Umbrella VPN باقی می ماند.
      // Inno نمی تواند پوشه ای را که فایل اجرایی خودش (unins000.exe) در آن
      // است حذف کند، پس یک فرایند جدا صبر می کند تا حذف کننده بسته شود و
      // بعد کل پوشه را با همه چیز پاک می کند.
      final String iss = read('installer/umbrella.iss');
      expect(iss.contains('RemoveInstallFolder'), isTrue);
      expect(iss.contains('Wait-Process'), isTrue);
      expect(iss.contains('Remove-Item -LiteralPath'), isTrue);
      // پوشه کاری عوض می شود تا برداشتن پوشه نصب به «دسترسی رد شد» نخورد.
      expect(iss.contains('Set-Location'), isTrue);
      // پوشه داده برنامه هم پاک می شود تا هیچ چیزی باقی نماند.
      expect(iss.contains('GetFolderPath'), isTrue);
      // مسیرها با علامت نقل قول تکی امن می شوند.
      expect(iss.contains('PsQuote'), isTrue);
    });
  });

  group('یکدستی اندازه های رابط کاربری', () {
    test('مقیاس اندازه ها در یک کلاس واحد تعریف شده', () {
      // شکایت کاربر: «منوها و بخش ها با اندازه های متفاوت و غریبه». پیش از این
      // فاصله های ۱۰/۱۲/۱۴، گوشه های ۱۱/۱۴/۱۵ و دکمه های ۴۸/۵۲/۵۴ در همه جا
      // پخش شده بود. حالا همه اندازه ها از AppMetrics می آیند.
      final String theme = read('lib/core/theme.dart');
      expect(theme.contains('class AppMetrics'), isTrue);
      for (final String token in <String>[
        'space1',
        'space2',
        'space3',
        'space4',
        'space5',
        'space6',
        'radiusSm',
        'radiusMd',
        'radiusLg',
        'radiusXl',
        'radiusXxl',
        'controlHeight',
        'controlHeightSmall',
        'controlHeightLarge',
        'iconButton',
        'navItemHeight',
        'titleBarHeight',
        'windowButtonWidth',
        'breakpointNav',
        'breakpointNavWide',
        'breakpointColumns',
        'maxContentWidth',
      ]) {
        expect(theme.contains('static const double $token'), isTrue,
            reason: 'AppMetrics.$token باید تعریف شود');
      }
      // دکمه های اصلی ۵۲، کوچک ۴۴ و دکمه اتصال ۵۶ پیکسل: روی ویندوز بلندتر از
      // حداقل لمسی ۴۴ پیکسل است.
      expect(
        RegExp('static const double controlHeight = 52').hasMatch(theme),
        isTrue,
      );
      expect(
        RegExp('static const double controlHeightSmall = 44').hasMatch(theme),
        isTrue,
      );
      expect(
        RegExp('static const double controlHeightLarge = 56').hasMatch(theme),
        isTrue,
      );
      // نوار بالای پنجره ۵۴ و دکمه های پنجره ۴۸ در ۵۴ پیکسل.
      expect(
        RegExp('static const double titleBarHeight = 54').hasMatch(theme),
        isTrue,
      );
      expect(
        RegExp('static const double windowButtonWidth = 48').hasMatch(theme),
        isTrue,
      );
      // فاصله همه صفحه ها با فاصله همه کارت ها یک مقیاس است: ۲۴ و ۲۰.
      expect(
        RegExp('static const EdgeInsets pagePadding = EdgeInsets.all\\(space6\\)')
            .hasMatch(theme),
        isTrue,
      );
      expect(
        RegExp('static const EdgeInsets cardPadding = EdgeInsets.all\\(space5\\)')
            .hasMatch(theme),
        isTrue,
      );
    });

    test('همه صفحه ها و ویجت های رابط از مقیاس اندازه استفاده می کنند', () {
      final List<String> files = Directory('lib/ui')
          .listSync(recursive: true)
          .whereType<File>()
          .map((File f) => f.path)
          .where((String path) => path.endsWith('.dart'))
          .toList();
      expect(files, isNotEmpty);
      for (final String path in files) {
        expect(read(path).contains('AppMetrics.'), isTrue,
            reason: '$path باید از AppMetrics استفاده کند');
      }
    });

    test('عدد اندازه خام در رابط کاربری نمانده است', () {
      // استثنا ها: بلندی خط متن (height: 1.7)، ضخامت خط (width: 1.5) و
      // نسبت های لوگو/گنبد (size * 0.66) که اندازه نیستند. ارجاع های
      // `AppMetrics.` اول کنار می مانند تا عدد داخل نام آن ها اشتباهی گزارش
      // نشود.
      final RegExp raw = RegExp(
        r'(SizedBox\(\s*(width|height):\s*[0-9.]+|'
        r'EdgeInsets\.(all|only|fromLTRB|symmetric)\([^)]*[0-9]|'
        r'BorderRadius\.circular\([0-9.]+\)|'
        r'fontSize:\s*[0-9.]+)',
      );
      final RegExp tokens = RegExp(r'AppMetrics\.\w+');
      final List<String> files = Directory('lib/ui')
          .listSync(recursive: true)
          .whereType<File>()
          .map((File f) => f.path)
          .where((String path) => path.endsWith('.dart'))
          .toList();
      for (final String path in files) {
        final String text = read(path).replaceAll(tokens, 'AppMetrics');
        final Iterable<RegExpMatch> matches = raw.allMatches(text);
        expect(
          matches.length,
          0,
          reason: '$path: '
              '${matches.map((RegExpMatch m) => m.group(0)).join(' | ')}',
        );
      }
    });

    test('نوار کناری واقعا ریسپانسیو است، نه فقط ادعا', () {
      // کمینه اندازه پنجره ۱۱۲۰ است. اگر مرز نوار کناری زیر آن باشد، حالت
      // باریک هیچ وقت دیده نمی شود — همان اشکالی که مرزهای ۸۲۰/۱۰۶۰ داشتند.
      final String theme = read('lib/core/theme.dart');
      final int minWindow = int.parse(
        RegExp(r'minimumSize: const Size\((\d+),')
            .firstMatch(read('lib/platform/services.dart'))!
            .group(1)!,
      );
      final int navBreak = int.parse(
        RegExp('static const double breakpointNav = (\\d+)')
            .firstMatch(theme)!
            .group(1)!,
      );
      final int navWideBreak = int.parse(
        RegExp('static const double breakpointNavWide = (\\d+)')
            .firstMatch(theme)!
            .group(1)!,
      );
      expect(navBreak, greaterThan(minWindow),
          reason: 'مرز نوار کناری باید بالای کمینه پنجره باشد');
      expect(navWideBreak, greaterThan(navBreak));
      // هر سه حالت نوار کناری هم در کد هستند.
      final String nav = read('lib/ui/widgets/shell_widgets.dart');
      expect(nav.contains('navWidthCompact'), isTrue);
      expect(nav.contains('navWidthMedium'), isTrue);
      expect(nav.contains('navWidthWide'), isTrue);
    });

    test('محتوا در پنجره های پهن زیر حداکثر پهنا می ماند', () {
      // روی مانیتور بزرگ خط متن بی اندازه بلند می شد و منو ها پراکنده می شدند.
      final String shell = read('lib/ui/shell/app_shell.dart');
      expect(shell.contains('maxContentWidth'), isTrue);
      expect(shell.contains('Center('), isTrue);
    });

    test('نسخه در همه صفحه ها از یک عدد خوانده می شود', () {
      for (final String path in <String>[
        'lib/ui/pages/landing_page.dart',
        'lib/ui/pages/login_page.dart',
        'lib/ui/widgets/shell_widgets.dart',
      ]) {
        final String text = read(path);
        expect(text.contains('نسخه ۱٫۰٫۰'), isFalse, reason: path);
        expect(text.contains('AppConfig.versionLabel'), isTrue, reason: path);
      }
    });
  });

  group('درخواست های ۱۸گانه رابط ورود و منوها', () {
    test('۱. صفحه ورود از تم روشن و تاریک پوسته پیروی می کند', () {
      final String login = read('lib/ui/pages/login_page.dart');
      expect(login.contains('Theme.of(context)'), isTrue);
      expect(login.contains('AppTheme'), isTrue);
      expect(login.contains('darkTheme: Theme.of(context).brightness == Brightness.dark'), isTrue);
      expect(read('lib/ui/shell/app_shell.dart').contains('darkTheme: Theme.of(context).brightness == Brightness.dark'), isTrue);
    });

    test('۲. فوتر حقوق محفوظ از صفحات ورود و معرفی حذف شده است', () {
      expect(read('lib/ui/pages/landing_page.dart').contains('حقوق محفوظ'), isFalse);
      expect(read('lib/ui/pages/about_page.dart').contains('حقوق محفوظ'), isFalse);
    });

    test('۳. کد ورود پس از تکمیل شش رقم خودکار تایید می شود', () {
      final String login = read('lib/ui/pages/login_page.dart');
      expect(login.contains('_onCodeChanged'), isTrue);
      expect(login.contains('value.length != 6'), isTrue);
      expect(login.contains('await auth.verifyCode(value)'), isTrue);
    });

    test('۴. ورود ناموفق پیام امنیتی دقیق و دکمه دستگاه من دارد', () {
      final String gateway = read('../Telegram-BOT/Core/App/App-Gateway.php');
      expect(gateway.contains('اگر این تلاش از طرف شما نبود، کد تأیید را برای کسی نفرستید و از «📱دستگاه من» در منوی خدمات ربات، دستگاه‌های ناشناس را حذف کنید.'), isTrue);
      expect(gateway.contains("'text' => '📱 دستگاه من'"), isTrue);
    });

    test('۵. IP در پیام های ورود تلگرام فارسی سازی می شود', () {
      final String gateway = read('../Telegram-BOT/Core/App/App-Gateway.php');
      expect(gateway.contains('آی‌پی:'), isTrue);
      expect(gateway.contains('Helper::toPersian(\$IP)'), isTrue);
    });

    test('۶. تایید دستگاه و فیلتر اعلان لغو مجوز کهنه اتمیک است', () {
      final String gateway = read('../Telegram-BOT/Core/App/App-Gateway.php');
      expect(gateway.contains('Database::getInstance()->transaction'), isTrue);
      expect(gateway.contains('FOR UPDATE'), isTrue);
      expect(gateway.contains('queued revoke warning is stale after re-approval'), isTrue);
    });

    test('۷. زیر پیام حساب آمبرلا منوی اصلی ناخواسته قرار نمی گیرد', () {
      final String link = read('../Telegram-BOT/Bot/App-Link.php');
      expect(link.contains("Menu::section('👤', 'حساب کاربری'"), isTrue);
      expect(link.contains("TelegramClient::inlineKeyboard(\$Rows)"), isTrue);
      expect(link.contains('main_menu'), isFalse);
      expect(link.contains("['inline_keyboard' => []]"), isTrue);
    });

    test('۸. کارت اتصال دست کم به اندازه تمام فضای صفحه است', () {
      final String page = read('lib/ui/pages/connect_page.dart');
      expect(page.contains('minHeight: constraints.maxHeight - 42'), isTrue);
      expect(page.contains('LayoutBuilder('), isTrue);
    });

    test('۹. نام آمبرلا در سمت چپ نوار عنوان قرار گرفته است', () {
      final String shell = read('lib/ui/widgets/shell_widgets.dart');
      final String bar = shell.substring(shell.indexOf('class TitleBar'), shell.indexOf('class _HeaderIconButton'));
      expect(bar.indexOf('Text(Fa.num(AppConfig.appName)'), greaterThan(bar.indexOf('onToggleTheme')));
    });

    test('۱۰. اجرای CLI مسیر اجرایی و آرگومان ها را جدا و امن می فرستد', () {
      final String cli = read('lib/vpn/cli_session.dart');
      expect(cli.contains('title,'), isTrue);
      expect(cli.contains('...file.args,'), isTrue);
      expect(cli.contains('file.exe,'), isTrue);
      expect(cli.contains('File(file.exe).existsSync()'), isTrue);
      expect(cli.contains('_quote('), isFalse);
      expect(cli.contains('final String command ='), isFalse);
    });

    test('پس از نصب به روزرسانی شماره موبایل در فرم ورود باقی می ماند', () {
      final String auth = read('lib/state/auth_controller.dart');
      expect(auth.contains("_phone = _store.read(StoreKeys.lastPhone) ?? ''"), isTrue);
      expect(auth.contains('await _store.write(StoreKeys.lastPhone, phone);'), isTrue);
    });

    test('۱۱. پرچم و نام کشور از کد یکسان در کنار IP نمایش داده می شوند', () {
      final String page = read('lib/ui/pages/connect_page.dart');
      expect(page.contains('FlagView(code: flagCode'), isTrue);
      expect(page.contains('vpn.geo.ip == ip'), isTrue);
      expect(page.contains('CountryNames.fa(flagCode)'), isTrue);
    });

    test('۱۲. تاریخ و ساعت از صفحه دستگاه من حذف شده است', () {
      expect(read('lib/ui/pages/device_page.dart').contains('LiveDateTimeLine'), isFalse);
    });

    test('۱۳. منوی وضعیت اتصال حذف و آمار به صفحه اتصال منتقل شده است', () {
      final String shell = read('lib/ui/shell/app_shell.dart');
      final String page = read('lib/ui/pages/connect_page.dart');
      expect(shell.contains('ConnectionPage('), isFalse);
      expect(shell.contains("label: 'وضعیت اتصال'"), isFalse);
      for (final String label in <String>['پینگ', 'مدت اتصال', 'دریافتی', 'ارسالی']) {
        expect(page.contains(label), isTrue, reason: label);
      }
    });

    test('۱۴. حساب لینک ربات رسمی دارد و دکمه خروج حساب ندارد', () {
      final String account = read('lib/ui/pages/account_page.dart');
      expect(account.contains('https://t.me/UmbrellaVPN_BOT'), isTrue);
      expect(account.contains('signOut('), isFalse);
    });

    test('۱۵. تنظیمات مدرن است و ارجاع درباره در آن نیست', () {
      final String settings = read('lib/ui/pages/settings_page.dart');
      expect(settings.contains('class _Section'), isTrue);
      expect(settings.contains('GlassCard'), isTrue);
      expect(settings.contains('درباره'), isFalse);
    });

    test('۱۶. منوی به روزرسانی آخر است و نوار درصد دارد', () {
      final String shell = read('lib/ui/shell/app_shell.dart');
      expect(shell.indexOf("label: 'به روز رسانی'"), greaterThan(shell.indexOf("label: 'درباره'")));
      expect(read('lib/ui/pages/updates_page.dart').contains('ProgressLine('), isTrue);
      expect(read('lib/ui/widgets/common.dart').contains('Fa.percent(value * 100)'), isTrue);
    });

    test('۱۷. صفحه درباره از کارت های مدرن استفاده می کند', () {
      final String about = read('lib/ui/pages/about_page.dart');
      expect(about.contains('GlassCard'), isTrue);
      expect(about.contains('LayoutBuilder'), isTrue);
    });

    test('۱۸. منوی خروج کل برنامه از پوسته حذف شده است', () {
      final String shell = read('lib/ui/shell/app_shell.dart');
      final String nav = read('lib/ui/widgets/shell_widgets.dart');
      expect(shell.contains("label: 'خروج'"), isFalse);
      expect(shell.contains('ExitPage('), isFalse);
      expect(nav.contains('exitIndex'), isFalse);
    });
  });
}
