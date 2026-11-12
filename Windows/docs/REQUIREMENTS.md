# پوشش نیازمندی ها

جدول زیر هر نیاز را به محل پیاده سازی وصل می کند تا بازبینی و آزمون ساده باشد.

| # | نیاز | وضعیت | محل |
| --- | --- | --- | --- |
| ۱ | فلوتر و کتابخانه های نسل جدید | انجام شده | `pubspec.yaml`، `lib/**` |
| ۲ | پشتیبانی Xray، Clash Meta، WireGuard، Amnezia، Mieru | انجام شده | `lib/vpn/cores.dart`، `lib/vpn/config_builders.dart`، `assets/cores/manifest.json` |
| ۳ و ۴ | اشتراک فقط از سرور و بدون ورود دستی | انجام شده | `lib/state/subscription_controller.dart`، `lib/data/parsers.dart` (`parseAuto`) |
| ۵ و ۶ | رابط حرفه ای با نام فیلترشکن آمبرلا | انجام شده | `lib/ui/**` |
| ۷ | رابط فارسی، نصب کننده انگلیسی | انجام شده | `lib/app.dart` (fa)، `installer/umbrella.iss` |
| ۸ | راست چین، بدون نیم فاصله، اعداد فارسی | انجام شده | `lib/app.dart`، `lib/core/persian.dart`؛ بررسی خودکار: هیچ U+200C در کد نیست |
| ۹ و ۱۰ | آیکون دایره ای و رنگ های لوگو | انجام شده | `assets/icons/icon_round.png`، `lib/core/theme.dart` |
| ۱۱ و ۱۲ | تم تاریک و روشن | انجام شده | `lib/core/theme.dart`، `lib/state/settings_controller.dart` |
| ۱۳ | تصاویر وضعیت با نام فارسی | انجام شده | `assets/images/*`، `lib/ui/widgets/brand_widgets.dart` (`StateGallery`) |
| ۱۴ | نسخه ۱٫۰٫۰ برنامه و پروژه | انجام شده | `pubspec.yaml`، `lib/core/app_config.dart`، `windows/CMakeLists.txt` |
| ۱۵ | انتخاب خودکار سرور با کمترین پینگ پایدار | انجام شده | `lib/vpn/ping.dart`، `lib/vpn/balancer.dart` |
| ۱۶ | فقط ویندوز ۱۰ و ۱۱ x64 | انجام شده | `windows/runner/runner.exe.manifest`، `windows/CMakeLists.txt` (x64) |
| ۱۷ | نوتبار با نمایش وضعیت | انجام شده | `packages/umbrella_native/.../tray_icon.cpp`، `lib/platform/services.dart` |
| ۱۸ | نصب کننده با دسترسی مدیر | انجام شده | `windows/runner/runner.exe.manifest`، `installer/umbrella.iss` |
| ۱۹ | سه حالت اتصال | انجام شده | `lib/models/models.dart` (`SelectionMode`)، `lib/vpn/balancer.dart`، تنظیمات |
| ۲۰ و ۲۱ | VPN کامل TUN و کیل سوییچ | انجام شده | `lib/vpn/config_builders.dart`، `lib/vpn/vpn_controller.dart`، `system_ops.cpp` |
| ۲۲ | سایر قابلیت های ممکن | انجام شده | مسدودسازی IPv6، مسیر سختگیرانه، DNS درون تونل، حالت توربو، MTU، فن آوری TUN، بازگردانی شبکه، صدا، مناسبت ها، لاگ |
| ۲۳ | به روزرسانی درون برنامه با درصد | انجام شده | `lib/platform/services.dart` (`UpdateService`)، `lib/state/update_controller.dart`، صفحه به روزرسانی |
| ۲۴ | بدون ایموجی، فقط آیکون | انجام شده | همه `lib/**`؛ بررسی خودکار بازه های ایموجی |
| ۲۵ | صفحه فرود فقط یک بار | انجام شده | `lib/state/settings_controller.dart` (`landingSeen`)، `lib/app.dart` |
| ۲۶ | پروفایل کامل و مصرف از وب سرویس | انجام شده | `lib/data/gateway_client.dart`، `lib/models/models.dart` (`Account`)، `lib/ui/pages/account_page.dart` |
| ۲۷ | اعلان بالای وسط با رنگ و آیکون | انجام شده | `lib/state/toast_controller.dart`، `lib/ui/widgets/shell_widgets.dart` |
| ۲۸ | منوی درباره و توسعه دهنده | انجام شده | `lib/ui/pages/about_page.dart` |
| ۲۹ | کنترل بستن و کوچک کردن پنجره | انجام شده | `lib/ui/widgets/shell_widgets.dart` (`TitleBar`)، `windows/runner/win32_window.h` |
| ۳۰ | صدا با کلید بی صدا | انجام شده | `lib/platform/services.dart` (`SoundService`)، `assets/sounds/*` |
| ۴۲ | آزمون خودکار خواندن اشتراک و پروفایل | انجام شده | `test/subscription_parsing_test.dart`، `test/account_model_test.dart` |
| ۳۱ | گرفتن کشور و شهر پیش از اتصال | انجام شده | `lib/platform/services.dart` (`IpService`)، `vpn.bootstrap` |
| ۳۲ | بررسی خودکار آی پی اتصال | انجام شده | `IpService`، `VpnController.refreshIp`، `tunnelVerified` |
| ۳۳ | مناسبت ها و جلوه ها | انجام شده | `assets/data/occasions.json`، `lib/platform/services.dart` (`OccasionService`)، `OccasionBanner` |
| ۳۴ | ورود با شماره و تشخیص اپراتور با لوگو | انجام شده | `lib/core/utils.dart` (`IranPhone`)، `lib/ui/pages/login_page.dart`، `OperatorBadge` |
| ۳۵ | پیامک و تایید تلگرام | انجام شده | `lib/state/auth_controller.dart`، `lib/ui/pages/login_page.dart` |
| ۳۶ | تایید دومرحله ای و پروفایل ربات | سمت کلاینت انجام شده، منطق ربات سمت سرور | `AuthController` (مرحله `awaitingTelegram`)، پوشه `Telegram-BOT` |
| ۳۷ | ارسال اطلاعات دستگاه در ورود موفق و ناموفق | سمت کلاینت انجام شده | `AuthController._devicePayload` در هر درخواست ورود |
| ۳۸ | همگام سازی بانک اطلاعاتی ربات و وب سرویس | سمت سرور | `Telegram-BOT/Core/App/App-Gateway.php` |
| ۳۹ | پیامک با پترن آی پی پنل | سمت سرور، کلاینت فقط کد را می فرستد | `Telegram-BOT/Core/SMS/IPPanel.php` |
| ۴۰ | فقط فونت وزیرمتن | انجام شده | `assets/fonts/*`، `pubspec.yaml` |
| ۴۱ | اتصال واقعی، قطع VPN های دیگر، آزمون | انجام شده | `VpnController._terminateForeignCores`، `disableSystemProxy`، تایید تونل با آی پی خروجی |

نکته درباره ردیف های «سمت سرور»: پوشه `Windows` فقط کلاینت است؛ این موارد در
کد موجود سرویس (پوشه `Telegram-BOT`) انجام می شوند و کلاینت تنها داده لازم را
می فرستد و وضعیت را نمایش می دهد.
