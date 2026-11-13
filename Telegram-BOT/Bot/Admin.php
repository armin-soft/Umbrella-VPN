<?php
declare(strict_types=1);

require_once __DIR__ . '/Context.php';
require_once __DIR__ . '/Common.php';
require_once __DIR__ . '/../Core/Telegram/Telegram.php';
require_once __DIR__ . '/../Core/Server/Umbrella-Server.php';
require_once __DIR__ . '/../Core/SMS/IPPanel.php';
require_once __DIR__ . '/../Core/Support/Helper.php';
require_once __DIR__ . '/../Core/Support/Bot-Config.php';
require_once __DIR__ . '/../Core/Telegram/Bot-Identity.php';
require_once __DIR__ . '/../Core/Storage/Repository.php';
require_once __DIR__ . '/../Core/Database/Database.php';
require_once __DIR__ . '/../Config/Environment.php';
require_once __DIR__ . '/Scheduler.php';
require_once __DIR__ . '/../Core/App/App-Device-Limit.php';

final class AdminFlow {
/**
 * The values that used to live only in `.env` and are now owned by the admin
 * panel, one entry per text flow. `hint` is what the prompt shows, `screen` is
 * where the «بازگشت» button leads, and `type` picks the validation.
 */
private const CFG_KEYS = [
'Plan_Price_1' => ['label' => 'قیمت پلن ۱ ماهه', 'type' => 'price', 'screen' => 'pricing', 'hint' => 'عدد به تومان، مثلاً 400000'],
'Plan_Price_2' => ['label' => 'قیمت پلن ۲ ماهه', 'type' => 'price', 'screen' => 'pricing', 'hint' => 'عدد به تومان، مثلاً 700000'],
'Plan_Price_3' => ['label' => 'قیمت پلن ۳ ماهه', 'type' => 'price', 'screen' => 'pricing', 'hint' => 'عدد به تومان، مثلاً 1000000'],
'Plan_Price_6' => ['label' => 'قیمت پلن ۶ ماهه', 'type' => 'price', 'screen' => 'pricing', 'hint' => 'عدد به تومان، مثلاً 1800000'],
'Plan_Price_12' => ['label' => 'قیمت پلن ۱۲ ماهه', 'type' => 'price', 'screen' => 'pricing', 'hint' => 'عدد به تومان، مثلاً 3000000'],
'Custom_Min_Days' => ['label' => 'حداقل روز پلن دلخواه', 'type' => 'days', 'screen' => 'pricing', 'hint' => 'عدد صحیح روز، حداقل ۱'],
'Custom_Max_Days' => ['label' => 'حداکثر روز پلن دلخواه', 'type' => 'days', 'screen' => 'pricing', 'hint' => 'عدد صحیح روز، مثلاً 365'],
'Custom_Min_GB' => ['label' => 'حداقل حجم پلن دلخواه', 'type' => 'gb', 'screen' => 'pricing', 'hint' => 'عدد به گیگابایت، حداقل ۰.۱'],
'Custom_Max_GB' => ['label' => 'حداکثر حجم پلن دلخواه', 'type' => 'gb', 'screen' => 'pricing', 'hint' => 'عدد به گیگابایت، مثلاً 1000'],
'Support_Url' => ['label' => 'لینک پشتیبانی', 'type' => 'link', 'screen' => 'links', 'hint' => 'آدرس کامل https://t.me/... یا نام کاربری با @'],
'Channel_Url' => ['label' => 'لینک کانال تلگرام', 'type' => 'link', 'screen' => 'links', 'hint' => 'آدرس کامل https://t.me/... یا نام کاربری با @'],
'Telegram_Channel_ID' => ['label' => 'آی دی کانال تلگرام', 'type' => 'channel', 'screen' => 'links', 'hint' => 'آی دی عددی و معمولاً منفی، مثال: -1001833514833'],
];

private function __construct() {
}

/**
 * منوی اصلی مدیریت.
 *
 * دکمه ها در گروه های موضوعی چیده شده اند تا ادمین به جای خواندن یک فهرست
 * دوازده ردیفی، بخش مورد نظرش را پیدا کند. وضعیت ربات و تعداد تیکت های در
 * انتظار هم بالای پیام آمده تا بدون باز کردن هیچ بخشی معلوم باشد.
 */
public static function menu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Temp_UID' => null, 'Broadcast_Mode' => null]);
$Robot_On = Common::isRobotOn();
// شمارش ها نباید منوی مدیریت را بشکنند: اگر دیتابیس پاسخ نداد، صفر نشان داده می شود.
try {
$Waiting_Tickets = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Tickets` WHERE `Status` IN ('open','pending')", [], 0);
$Active_Users = (int)Database::getInstance()->scalar('SELECT COUNT(*) FROM `Users` WHERE `Is_Blocked` = 0', [], 0);
}

catch (Throwable) {
$Waiting_Tickets = 0;
$Active_Users = 0;
}
$Text = Helper::adminGreeting($Context, 'منوی مدیریت')
. Menu::section('📊', 'وضعیت کلی', [
'🚦وضعیت ربات: *' . ($Robot_On ? '🟢روشن' : '🔴خاموش') . '*',
'👥کاربران فعال: *' . Helper::toPersian((string)$Active_Users) . '*',
'🎫تیکت در انتظار پاسخ: *' . Helper::toPersian((string)$Waiting_Tickets) . '*',
])
. Menu::section('🗂', 'گروه های منو', [
'👥کاربران: اعتبار، مسدودیت، مجوز دستگاه، تیکت ها',
'⚙️سرور: پیکربندی، تعرفه و پلن ها، لینک ها',
'📊گزارش: آمار، گزارش مالی، رتبه بندی، پیامک',
'🧰سیستم: بروزرسانی، دیتابیس، تنظیمات ربات',
])
. '📌*بخش مورد نظر را انتخاب کنید:*' . Helper::adminFooter();
$Markup = [];

// وضعیت ربات، تنها دکمه ای که خود ربات را خاموش و روشن می کند.
$Markup[] = [Menu::button($Robot_On ? '🔴خاموش کردن ربات' : '🟢روشن کردن ربات', $Robot_On ? 'خاموش کردن ربات' : 'روشن کردن ربات')];

// گروه ۱: کاربران
$Markup = array_merge($Markup, Menu::rows([
[['👥کاربران و اعتبار', 'اعتبار حساب کاربری'], ['🚨مسدودیت کاربران', 'جرایم']],
[['📱مجوز دستگاه', 'device_limit_menu'], ['🎫مدیریت تیکت ها', 'مدیریت تیکت ها']],
]));

// گروه ۲: سرور و تعرفه
$Markup = array_merge($Markup, Menu::rows([
[['⚙️پیکربندی سرور', 'پیکربندی سرور'], ['💰تعرفه و پلن ها', 'cfg_pricing']],
[['🔗لینک ها و کانال', 'cfg_links']],
]));

// گروه ۳: گزارش و مالی
$Markup = array_merge($Markup, Menu::rows([
[['📊گزارش ها و آمار', 'منوی گزارش'], ['💰گزارش مالی', 'گزارش مالی']],
[['🏆رتبه بندی کاربران', 'رتبه بندی'], ['📨پیامک و اطلاع رسانی', 'منوی پیامک']],
]));

// گروه ۴: سیستم
$Markup = array_merge($Markup, Menu::rows([
[['🔄بروزرسانی نسخه', 'بروز رسانی'], ['🗄️دیتابیس', 'دیتابیس']],
[['⚙️تنظیمات ربات', 'تنظیمات ربات']],
]));

self::logMenuProblems('menu', $Markup);

if ($Context->IsCallback && $Context->MessageId !== null) {
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Markup));
}

else {
TelegramClient::sendMessage($Context->ChatId, $Text, TelegramClient::inlineKeyboard($Markup));
}
}

/** بررسی سلامت کیبورد و ثبت خطاها در لاگ؛ چیزی به کاربر نشان داده نمی شود. */
private static function logMenuProblems(string $Screen, array $Rows): void {
$Problems = Menu::problems($Rows);

if ($Problems !== []) {
error_log('[Umbrella-Bot][Menu-' . $Screen . '] ' . implode(' | ', $Problems));
}
}

public static function globalStats(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '📊در حال بارگذاری آمار...', false);
}

try {
Scheduler::refreshUsagesNow();
}

catch (Throwable) {}

$Stats = Repository::globalStatistics();
$SMS_Stats = Repository::smsStatistics();
$Client_Status = Repository::clientStatusDistribution();
$Operator_Dist = Repository::operatorDistribution();
$Subscription_Dist = Repository::subscriptionDistribution();
$Balance_Buckets = Repository::balanceBuckets();
$Operator_Text = '';

foreach ($Operator_Dist as $Op => $Count) {
$Operator_Text .= "├─📶{$Op}: *" . Helper::toPersian((string)$Count) . "* نفر\n";
}

if ($Operator_Text === '') {
$Operator_Text = "└─❌داده ای موجود نیست\n";
}

$Subscription_Text = '';

foreach ($Subscription_Dist as $Sub => $Count) {
$Subscription_Text .= "├─💎{$Sub}: *" . Helper::toPersian((string)$Count) . "* نفر\n";
}

if ($Subscription_Text === '') {
$Subscription_Text = "└─❌اشتراک فعالی ثبت نشده\n";
}

$Balance_Text = '';
foreach ($Balance_Buckets as $Bucket => $Count) {
$Balance_Text .= "├─💰{$Bucket}: *" . Helper::toPersian((string)$Count) . "* نفر\n";
}

$Usage_Percent = Helper::formatPercent(
$Stats['total_quota'] > 0 ? round(($Stats['total_used'] / $Stats['total_quota']) * 100, 1) : 0
);

$Text = Helper::adminGreeting($Context, 'آمار کلی') . "\n➖➖➖➖➖➖➖➖➖\n\n"
. "📊*آمار کلی ربات آمبرلا:*\n\n"
. "👥*کاربران:*\n"
. "├─🌍کل کاربران ثبت نام شده: *" . Helper::toPersian((string)$Stats['total_users']) . "* نفر\n"
. "├─🆕عضو امروز: *" . Helper::toPersian((string)$Stats['new_today']) . "* نفر\n"
. "├─📅عضو ۷ روز اخیر: *" . Helper::toPersian((string)$Stats['new_week']) . "* نفر\n"
. "├─📆عضو ۳۰ روز اخیر: *" . Helper::toPersian((string)$Stats['new_month']) . "* نفر\n"
. "├─✅پروفایل تکمیل شده: *" . Helper::toPersian((string)$Stats['has_profile']) . "* نفر\n"
. "├─📱شماره ثبت شده: *" . Helper::toPersian((string)$Stats['has_phone']) . "* نفر\n"
. "├─🆔دارای کلاینت سرور: *" . Helper::toPersian((string)$Stats['has_client']) . "* نفر\n"
. "├─🚫مسدودشده: *" . Helper::toPersian((string)$Stats['blocked_users']) . "* نفر\n"
. "└─🎁اشتراک رایگان استفاده شده: *" . Helper::toPersian((string)$Stats['free_claimed']) . "* نفر\n\n"
. "🚦*وضعیت کلاینت ها:*\n"
. "├─✅فعال: *" . Helper::toPersian((string)$Client_Status['active']) . "* نفر\n"
. "├─🚫غیرفعال: *" . Helper::toPersian((string)$Client_Status['inactive']) . "* نفر\n"
. "└─⏰ منقضی: *" . Helper::toPersian((string)$Stats['expired_users']) . "* نفر\n\n"
. "📶*توزیع اپراتور:*\n"
. $Operator_Text . "\n"
. "💎*توزیع اشتراک:*\n"
. $Subscription_Text . "\n"
. "💰*توزیع موجودی کیف پول:*\n"
. $Balance_Text . "\n"
. "💳*کیف پول:*\n"
. "├─💵مجموع موجودی: *" . Helper::formatCurrency($Stats['total_balance']) . "*\n"
. "└─📊میانگین موجودی: *" . Helper::formatCurrency($Stats['avg_balance']) . "*\n\n"
. "📊*مصرف کل:*\n"
. "├─📦حجم کل تخصیص یافته: *" . Helper::formatGB((float)$Stats['total_quota']) . "*\n"
. "├─📥مصرف شده: *" . Helper::formatGB((float)$Stats['total_used']) . "*\n"
. "└─📈درصد مصرف: *{$Usage_Percent}٪*\n\n"
. "💸*پرداخت و درآمد (تومان):*\n"
. "├─📅درآمد امروز: *" . Helper::formatCurrency($Stats['revenue_today']) . "*\n"
. "├─🗓درآمد ۷ روز اخیر: *" . Helper::formatCurrency($Stats['revenue_week']) . "*\n"
. "├─📆درآمد ۳۰ روز اخیر: *" . Helper::formatCurrency($Stats['revenue_month']) . "*\n"
. "└─💎درآمد کل: *" . Helper::formatCurrency($Stats['revenue_total']) . "*\n\n"
. "🧾*تراکنش ها:*\n"
. "├─📊کل تراکنش ها: *" . Helper::toPersian((string)$Stats['total_transactions']) . "*\n"
. "├─💳تراکنش درآمد امروز: *" . Helper::toPersian((string)$Stats['revenue_today_count']) . "*\n"
. "└─📋کل سوابق اشتراک: *" . Helper::toPersian((string)$Stats['total_subscription_logs']) . "*\n\n"
. "🌐*کاربران واقعی سرور:*\n"
. "├─👥تعداد: *" . Helper::toPersian((string)$Stats['server_clients']) . "* نفر\n"
. "├─🟢فعال: *" . Helper::toPersian((string)$Stats['server_clients_active']) . "*\n"
. "├─🔴غیرفعال: *" . Helper::toPersian((string)$Stats['server_clients_disabled']) . "*\n"
. "├─⏰منقضی: *" . Helper::toPersian((string)$Stats['server_clients_expired']) . "*\n"
. "├─💎اشتراک فعال: *" . Helper::toPersian((string)$Stats['active_subscriptions']) . "*\n"
. "├─⏳انقضای امروز: *" . Helper::toPersian((string)$Stats['expiring_today']) . "* |📅تا ۳ روز: *" . Helper::toPersian((string)$Stats['expiring_3days']) . "*\n"
. "└─🧮میانگین مصرف هر کاربر: *" . Helper::formatGB((float)$Stats['server_avg_used']) . "*\n\n"
. "📩*پیامک (آی پی پنل):*\n"
. "├─✅موفق: *" . Helper::toPersian((string)$Stats['sms_success']) . "*\n"
. "├─❌ناموفق: *" . Helper::toPersian((string)$Stats['sms_failed']) . "*\n"
. "└─📊کل: *" . Helper::toPersian((string)$Stats['total_sms']) . "*"
. Helper::adminFooter() . "";

TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard([
[['text' => '🔁بروزرسانی آمار', 'callback_data' => 'آمار کلی']],
[['text' => '📅گزارش روزانه دقیق', 'callback_data' => 'گزارش روزانه']],
[['text' => '🔙بازگشت', 'callback_data' => 'منوی گزارش']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

private static function denyAccess(Context $Context): void {
TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'منوی مدیریت') . "⛔️با عرض پوزش شما دسترسی به این بخش را ندارید." . Helper::userFooter(), TelegramClient::inlineKeyboard([Menu::userHome()]));
}

private static function header(Context $Context, string $Section = ''): string {
if ($Section === '') {
$Section = self::detectSection($Context);
}

return Helper::adminGreeting($Context, $Section);
}

private static function detectSection(Context $Context): string {
$Flow = (string)(Repository::getUserSession($Context->UserId)['Flow'] ?? '');
$Flow = str_starts_with($Flow, 'admin:') ? substr($Flow, 6) : $Flow;
$Map = [
'credit_add' => 'شارژ اعتبار کاربران',
'credit_add_amount' => 'شارژ اعتبار کاربران',
'credit_sub' => 'کسر اعتبار کاربران',
'credit_sub_amount' => 'کسر اعتبار کاربران',
'view_uid' => 'مشاهده اعتبار کاربر',
'block_uid' => 'مسدود کردن کاربر',
'unblock_uid' => 'رفع مسدودیت کاربر',
'activate_uid' => 'فعالسازی کلاینت',
'deactivate_uid' => 'غیرفعالسازی کلاینت',
'deactivate_msg' => 'غیرفعالسازی کلاینت',
'delete_uid' => 'حذف کاربر از سرور',
'expire_uid' => 'منقضی کردن اشتراک',
'sms_single_mode' => 'ارسال پیامک تکی',
'sms_single_uid' => 'ارسال پیامک تکی',
'sms_single_text' => 'ارسال پیامک تکی',
'notify_mode' => 'اطلاع رسانی به کاربر',
'notify_uid' => 'اطلاع رسانی به کاربر',
'notify_text' => 'اطلاع رسانی به کاربر',
'notify_broadcast_text' => 'اطلاع رسانی همگانی',
'notify_all_text' => 'اطلاع به تلگرام و برنامه',
'device_limit_target' => 'مجوز دستگاه کاربران',
'device_limit_pick' => 'مجوز دستگاه کاربران',
'update_uid' => 'بروز رسانی داده کاربران',
'version_number' => 'بروز رسانی نسخه',
'version_changes' => 'بروز رسانی نسخه',
'emergency_url' => 'تنظیمات ربات',
'ticket_reply_text' => 'مدیریت تیکت ها',
];

if (str_starts_with($Flow, 'cfg:')) return 'تنظیمات ربات';

return $Map[$Flow] ?? 'منوی مدیریت';
}

public static function settings(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
self::menu($Context);
}

/**
 * The three values that used to live only in `.env`: robot version, whether the
 * emergency config link is shown, and the link. The panel wins; `.env` is shown
 * as the fallback so an admin can see what would happen if a key is never set.
 */
public static function configMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '⚙️تنظیمات ربات در حال بارگذاری...', false);
}

$Version = BotConfig::robotVersion();
$Version_Label = $Version !== '' ? Helper::toPersian($Version) : 'ثبت نشده';
$Version_Source = BotConfig::source(BotConfig::KEY_VERSION) === 'panel' ? '📝از پنل' : '🌱از فایل تنظیمات';
$Show = BotConfig::showEmergency();
$Url = BotConfig::emergencyUrl();
$Url_Source = BotConfig::source(BotConfig::KEY_EMERGENCY_URL) === 'panel' ? '📝از پنل' : '🌱از فایل تنظیمات';
$Text = Helper::adminGreeting($Context, 'تنظیمات ربات')
. Menu::section('⚙️', 'وضعیت تنظیمات', [
'🔄نسخه ربات: `' . $Version_Label . '` (' . $Version_Source . ')',
'💰تعرفه اشتراک: قیمت پلن ها و محدوده پلن دلخواه',
'📣لینک ها: پشتیبانی، کانال و آی دی کانال',
])
. Menu::section('🚱', 'کانفیگ اضطراری', [
'وضعیت نمایش: *' . ($Show ? '🟢روشن' : '🔴خاموش') . '* (' . $Url_Source . ')',
'آدرس: <code>' . $Url . '</code>',
])
. ($Show
? "ℹ️خط «اضطراری موقت» در پیام کانفیگ کاربران نمایش داده می شود.\n"
: "ℹ️خط «اضطراری موقت» در پیام کانفیگ کاربران نمایش داده نمی شود.\n")
. Helper::adminFooter();
$Markup = array_merge(
Menu::rows([
[['💰تعرفه و محدوده پلن', 'cfg_pricing'], ['📣لینک ها و کانال', 'cfg_links']],
[['🔄تغییر نسخه ربات', 'بروز رسانی']],
]),
Menu::rows([
[['🚱روشن / خاموش کانفیگ اضطراری', 'emergency_toggle']],
[['🔗آدرس کانفیگ اضطراری', 'emergency_url_start']],
]),
[Menu::adminHome()]
);
self::logMenuProblems('settings', $Markup);

if ($Context->IsCallback && $Context->MessageId !== null) {
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Markup));
return;
}

TelegramClient::sendMessage($Context->ChatId, $Text, TelegramClient::inlineKeyboard($Markup));
}

public static function toggleEmergencyConfig(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Next = !BotConfig::showEmergency();
BotConfig::setShowEmergency($Next);

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, $Next ? '✅کانفیگ اضطراری روشن شد.' : '⛔️کانفیگ اضطراری خاموش شد.', false);
}

self::configMenu($Context);
}

public static function emergencyUrlStart(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
self::startInput(
$Context,
'admin:emergency_url',
"🔗آدرس کامل کانفیگ اضطراری را بفرستید (یک آدرس وب).\n"
. "🚱آدرس فعلی: <code>" . BotConfig::emergencyUrl() . "</code>\n\n"
. "👌برای پاک کردن آن و برگشت به مقدار پیش فرض، کلمه «حذف» را بفرستید.\n\n"
);
}

private static function emergencyUrlSave(Context $Context, string $Text): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$Value = trim($Text);

if (in_array(mb_strtolower($Value), ['حذف', 'پاک', 'delete', 'clear', '-'], true)) {
BotConfig::setEmergencyUrl('');
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "✅آدرس کانفیگ اضطراری پاک شد؛ مقدار پیش‌فرض (تنظیمات سرور یا آدرس داخلی) دوباره استفاده می‌شود." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[Common::backTo('🔙بازگشت', 'تنظیمات ربات')],
[Menu::adminHome()],
]));
return;
}

if (!preg_match('#^https?://[^\s<>]+$#i', $Value)) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "⚠️آدرس نامعتبر است.\n➖➖➖➖➖➖➖➖➖\n🔗آدرس باید کامل باشد و با `https://` شروع شود.\n👌مثال: `https://example.com/emergency.txt`" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[Common::backTo('🔗تلاش دوباره', 'emergency_url_start')],
[Common::backTo('🔙بازگشت', 'تنظیمات ربات')],
]));
return;
}

BotConfig::setEmergencyUrl($Value);
Repository::logAdminAction($Context->UserId, 'emergency_config_url', null, 'url=' . $Value, '');
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "✅آدرس کانفیگ اضطراری ثبت شد:\n<code>{$Value}</code>" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[Common::backTo('🔙بازگشت', 'تنظیمات ربات')],
[Menu::adminHome()],
]));
}

/** Subscription prices and the limits of the custom plan. */
public static function pricingMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '💰تعرفه ها در حال بارگذاری...', false);
}

$Rows_Text = '';

foreach (BotConfig::PLAN_MONTHS as $Months => $Label) {
$Price = BotConfig::getPlanPrice($Months);
$Price_Label = $Price > 0 ? Helper::formatCurrency($Price) : 'ثبت نشده';
$Rows_Text .= "💎{$Label}: *{$Price_Label}* تومان\n";
}

$Min_Days = BotConfig::getCustomMinDays();
$Max_Days = BotConfig::getCustomMaxDays();
$Min_GB = BotConfig::getCustomMinGB();
$Max_GB = BotConfig::getCustomMaxGB();
$Day_Rate = BotConfig::getCustomDayRate();
$Text = Helper::adminGreeting($Context, 'تعرفه اشتراک')
. "💰*تعرفه اشتراک و محدوده پلن*\n➖➖➖➖➖➖➖➖➖\n"
. "💎*پلن های ثابت:*\n" . $Rows_Text . "\n"
. "📐*پلن دلخواه:*\n"
. "📆حداقل روز: *" . Helper::toPersian((string)$Min_Days) . "*\n"
. "📆حداکثر روز: *" . Helper::toPersian((string)$Max_Days) . "*\n"
. "📦حداقل حجم: *" . Helper::formatGB($Min_GB) . "*\n"
. "📦حداکثر حجم: *" . Helper::formatGB($Max_GB) . "*\n"
. "💰قیمت هر روز: *" . Helper::formatCurrency($Day_Rate) . "*\n\n"
. "ℹ️قیمت هر روز پلن دلخواه از قیمت پلن ۱ ماهه تقسیم بر ۳۰ محاسبه می شود.\n"
. Helper::adminFooter();
$Markup = array_merge(
Menu::rows([
[['✏️قیمت ۱ ماهه', 'cfg_set:Plan_Price_1'], ['✏️قیمت ۲ ماهه', 'cfg_set:Plan_Price_2']],
[['✏️قیمت ۳ ماهه', 'cfg_set:Plan_Price_3'], ['✏️قیمت ۶ ماهه', 'cfg_set:Plan_Price_6']],
[['✏️قیمت ۱۲ ماهه', 'cfg_set:Plan_Price_12']],
]),
Menu::rows([
[['✏️حداقل روز', 'cfg_set:Custom_Min_Days'], ['✏️حداکثر روز', 'cfg_set:Custom_Max_Days']],
[['✏️حداقل حجم', 'cfg_set:Custom_Min_GB'], ['✏️حداکثر حجم', 'cfg_set:Custom_Max_GB']],
]),
[Menu::button('🔙بازگشت', 'تنظیمات ربات')],
[Menu::adminHome()]
);
self::logMenuProblems('pricing', $Markup);
self::renderCfgScreen($Context, $Text, $Markup);
}

/** Support link, channel link and channel id. */
public static function linksMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '📣لینک ها در حال بارگذاری...', false);
}

$Support = BotConfig::getSupportUrl() ?: 'ثبت نشده';
$Channel = BotConfig::getChannelUrl() ?: 'ثبت نشده';
$Channel_Id = BotConfig::getTelegramChannelId() ?: 'ثبت نشده';
$Source_Label = static fn (string $Key): string => BotConfig::source($Key) === 'panel' ? '📝پنل' : '🌱فایل تنظیمات';
$Text = Helper::adminGreeting($Context, 'لینک ها و کانال')
. "📣*لینک پشتیبانی و کانال*\n➖➖➖➖➖➖➖➖➖\n"
. "🧑‍💻لینک پشتیبانی ({$Source_Label('Support_Url')}):\n<code>{$Support}</code>\n\n"
. "📣لینک کانال ({$Source_Label('Channel_Url')}):\n<code>{$Channel}</code>\n\n"
. "🆔آی دی کانال ({$Source_Label('Telegram_Channel_ID')}):\n<code>{$Channel_Id}</code>\n\n"
. "ℹ️لینک پشتیبانی در دکمه های «ارتباط با پشتیبانی» و لینک کانال در دکمه عضویت کانال استفاده می شود.\n"
. Helper::adminFooter();
$Markup = array_merge(
Menu::rows([
[['✏️لینک پشتیبانی', 'cfg_set:Support_Url']],
[['✏️لینک کانال', 'cfg_set:Channel_Url']],
[['✏️آی دی کانال', 'cfg_set:Telegram_Channel_ID']],
]),
[Menu::button('🔙بازگشت', 'تنظیمات ربات')],
[Menu::adminHome()]
);
self::logMenuProblems('links', $Markup);
self::renderCfgScreen($Context, $Text, $Markup);
}

/** Asks for the new value of one CFG_KEYS entry. */
public static function cfgStart(Context $Context, string $Key): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Key = trim($Key);

if (!isset(self::CFG_KEYS[$Key])) {
self::unknownAdminInput($Context);
return;
}

$Meta = self::CFG_KEYS[$Key];
self::startInput(
$Context,
'admin:cfg:' . $Key,
"✏️مقدار جدید «{$Meta['label']}» را بفرستید.\n"
. "🧾مقدار فعلی: <code>" . self::cfgCurrent($Key) . "</code>\n"
. "💡{$Meta['hint']}\n\n"
. "👌برای برگشت بدون تغییر، از دکمه پایین استفاده کنید.\n\n"
);
}

private static function cfgSave(Context $Context, string $Key, string $Text): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$Key = trim($Key);

if (!isset(self::CFG_KEYS[$Key])) {
self::unknownAdminInput($Context);
return;
}

$Meta = self::CFG_KEYS[$Key];
$Value = trim(Helper::toEnglish($Text));
$Value = str_replace([',', '،', ' ', '٬'], '', $Value);
$Error = '';
$Stored = '';

switch ($Meta['type']) {
case 'price':
if (!preg_match('/^\d{1,12}$/', $Value) || (int)$Value <= 0) {
$Error = '💰قیمت باید یک عدد مثبت به تومان باشد.';
break;
}

$Months = (int)substr($Key, strlen('Plan_Price_'));
BotConfig::setPlanPrice($Months, (float)$Value);
$Stored = Helper::formatCurrency((float)$Value);
break;
case 'days':
if (!preg_match('/^\d{1,4}$/', $Value) || (int)$Value < 1) {
$Error = '📅تعداد روز باید عدد صحیح و حداقل ۱ باشد.';
break;
}

$Days = (int)$Value;

if ($Key === 'Custom_Min_Days' && $Days >= BotConfig::getCustomMaxDays()) {
$Error = '📅حداقل روز باید کمتر از حداکثر روز (' . BotConfig::getCustomMaxDays() . ') باشد.';
break;
}

if ($Key === 'Custom_Max_Days' && $Days <= BotConfig::getCustomMinDays()) {
$Error = '📅حداکثر روز باید بیشتر از حداقل روز (' . BotConfig::getCustomMinDays() . ') باشد.';
break;
}

if ($Key === 'Custom_Min_Days') { BotConfig::setCustomMinDays($Days); }
else { BotConfig::setCustomMaxDays($Days); }
$Stored = Helper::toPersian((string)$Days) . ' روز';
break;
case 'gb':
if (!preg_match('/^\d{1,6}(\.\d{1,2})?$/', $Value) || (float)$Value <= 0) {
$Error = '📦حجم باید یک عدد مثبت به گیگابایت باشد (مثلاً ۱ یا ۰.۵).';
break;
}

$GB = (float)$Value;

if ($Key === 'Custom_Min_GB' && $GB >= BotConfig::getCustomMaxGB()) {
$Error = '📦حداقل حجم باید کمتر از حداکثر حجم (' . Helper::formatGB(BotConfig::getCustomMaxGB()) . ') باشد.';
break;
}

if ($Key === 'Custom_Max_GB' && $GB <= BotConfig::getCustomMinGB()) {
$Error = '📦حداکثر حجم باید بیشتر از حداقل حجم (' . Helper::formatGB(BotConfig::getCustomMinGB()) . ') باشد.';
break;
}

if ($Key === 'Custom_Min_GB') { BotConfig::setCustomMinGB($GB); }
else { BotConfig::setCustomMaxGB($GB); }
$Stored = Helper::formatGB($GB);
break;
case 'link':
if ($Value !== '' && str_starts_with($Value, '@')) {
$Value = 'https://t.me/' . substr($Value, 1);
}

if (!preg_match('#^https?://[^\s<>]+$#i', $Value)) {
$Error = '🔗آدرس باید کامل باشد و با `https://` شروع شود، یا نام کاربری با @ باشد.';
break;
}

if ($Key === 'Support_Url') { BotConfig::setSupportUrl($Value); }
else { BotConfig::setChannelUrl($Value); }
$Stored = $Value;
break;
case 'channel':
$Value = ltrim($Value, '+');

if (!preg_match('/^-?\d{5,20}$/', $Value)) {
$Error = '🆔آی دی کانال باید عددی باشد (معمولاً منفی و با ۱۰۰- شروع می شود).';
break;
}

BotConfig::setTelegramChannelId($Value);
$Stored = $Value;
break;
default:
$Error = '❓نوع مقدار ناشناخته است.';
}

if ($Error !== '') {
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "⚠️{$Error}\n➖➖➖➖➖➖➖➖➖\n🔁لطفاً مقدار درست را دوباره بفرستید." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[Common::backTo('✏️تلاش دوباره', 'cfg_set:' . $Key)],
[Common::backTo('🔙بازگشت', 'تنظیمات ربات')],
]));
return;
}

Repository::logAdminAction($Context->UserId, 'cfg_' . $Key, null, 'value=' . mb_substr($Stored, 0, 190), '');
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "✅«{$Meta['label']}» ثبت شد:\n<code>{$Stored}</code>" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[Common::backTo('🔁مشاهده مقادیر', $Meta['screen'] === 'pricing' ? 'cfg_pricing' : 'cfg_links')],
[Common::backTo('🔙بازگشت', 'تنظیمات ربات')],
[Menu::adminHome()],
]));
}

/** The value in use for one CFG_KEYS entry, formatted for a prompt. */
private static function cfgCurrent(string $Key): string {
switch ($Key) {
case 'Plan_Price_1': case 'Plan_Price_2': case 'Plan_Price_3': case 'Plan_Price_6': case 'Plan_Price_12':
$Price = BotConfig::getPlanPrice((int)substr($Key, strlen('Plan_Price_')));
return $Price > 0 ? Helper::formatCurrency($Price) : 'ثبت نشده';
case 'Custom_Min_Days': return Helper::toPersian((string)BotConfig::getCustomMinDays()) . ' روز';
case 'Custom_Max_Days': return Helper::toPersian((string)BotConfig::getCustomMaxDays()) . ' روز';
case 'Custom_Min_GB': return Helper::formatGB(BotConfig::getCustomMinGB());
case 'Custom_Max_GB': return Helper::formatGB(BotConfig::getCustomMaxGB());
case 'Support_Url': return BotConfig::getSupportUrl() ?: 'ثبت نشده';
case 'Channel_Url': return BotConfig::getChannelUrl() ?: 'ثبت نشده';
case 'Telegram_Channel_ID': return BotConfig::getTelegramChannelId() ?: 'ثبت نشده';
default: return '—';
}
}

/** Edits the current message when a callback came from it, else sends a new one. */
private static function renderCfgScreen(Context $Context, string $Text, array $Markup): void {
$Markup = TelegramClient::inlineKeyboard($Markup);

if ($Context->IsCallback && $Context->MessageId !== null) {
$Result = TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Text, $Markup);

if (is_array($Result) && ($Result['ok'] ?? false) === true) {
return;
}
}

TelegramClient::sendMessage($Context->ChatId, $Text, $Markup);
}

public static function reportMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Text = Helper::adminGreeting($Context, 'گزارش ها و آمار')
. Menu::section('📊', 'انواع گزارش', [
'📊آمار کلی: کاربران، مصرف، درآمد و پیامک',
'📅گزارش روزانه: عملکرد امروز به تفکیک بخش ها',
'💰گزارش مالی: درآمد، کیف پول و خریدها',
'🏆رتبه بندی: پر مصرف ترین کاربران',
])
. '📌*نوع گزارش را انتخاب کنید:*' . Helper::adminFooter();
$Markup = array_merge(
Menu::rows([
[['📊آمار کلی', 'آمار کلی'], ['📅گزارش روزانه', 'گزارش روزانه']],
[['💰گزارش مالی', 'گزارش مالی'], ['🏆رتبه بندی', 'رتبه بندی']],
]),
[Menu::adminHome()]
);
self::logMenuProblems('reports', $Markup);
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Markup));
}

public static function dailyReport(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '📅در حال تهیه گزارش روزانه دقیق...', false);
}

try {
Scheduler::refreshUsagesNow();
}

catch (Throwable) {}

try {
$Text = Scheduler::buildDailyReportText(false);
}

catch (Throwable $E) {
error_log('[Umbrella-Bot][Daily-Report][Admin] ' . $E->getMessage());
TelegramClient::sendMessage($Context->ChatId, Helper::adminGreeting($Context, 'گزارش روزانه') . "❌خطا در تهیه گزارش روزانه.\n⚠️علت: " . mb_substr($E->getMessage(), 0, 200) . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'منوی گزارش']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}

$Text = Helper::adminGreeting($Context, 'گزارش روزانه') . $Text . Helper::adminFooter();
$Markup = TelegramClient::inlineKeyboard([
[['text' => '🔁بروزرسانی گزارش', 'callback_data' => 'گزارش روزانه']],
[['text' => '🏆رتبه بندی کاربران', 'callback_data' => 'رتبه بندی']],
[['text' => '🔙بازگشت', 'callback_data' => 'منوی گزارش']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]);

$Chunks = self::splitMessage($Text);

if ($Context->MessageId !== null) {
try {
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Chunks[0], count($Chunks) > 1 ? [] : $Markup);
}

catch (Throwable) {
TelegramClient::sendMessage($Context->ChatId, $Chunks[0], count($Chunks) > 1 ? [] : $Markup);
}
}

else {
TelegramClient::sendMessage($Context->ChatId, $Chunks[0], count($Chunks) > 1 ? [] : $Markup);
}

for ($Index = 1; $Index < count($Chunks); $Index++) {
TelegramClient::sendMessage($Context->ChatId, $Chunks[$Index], $Index === count($Chunks) - 1 ? $Markup : []);
}
}

private static function splitMessage(string $Text, int $Limit = 3800): array {
$Text = trim($Text);

if ($Text === '') return [''];
if (mb_strlen($Text) <= $Limit) return [$Text];
$Chunks = [];
$Lines = explode("\n", $Text);
$Buffer = '';

foreach ($Lines as $Line) {
$Candidate = $Buffer === '' ? $Line : ($Buffer . "\n" . $Line);

if (mb_strlen($Candidate) > $Limit) {
if ($Buffer !== '') $Chunks[] = $Buffer;
$Buffer = $Line;
}

else {
$Buffer = $Candidate;
}
}

if ($Buffer !== '') $Chunks[] = $Buffer;
return $Chunks === [] ? [$Text] : $Chunks;
}

public static function smsMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Temp_UID' => null, 'Broadcast_Mode' => null]);

$Text = Helper::adminGreeting($Context, 'پیامک و اطلاع رسانی')
. Menu::section('📨', 'روش ارسال', [
'📨پیامک تکی: ارسال پیامک به یک کاربر مشخص',
'📢پیامک همگانی: ارسال پیامک به همه کاربران',
'🗣اطلاع رسانی: پیام تلگرام، پیامک یا هر دو',
])
. '📌*روش ارسال را انتخاب کنید:*' . Helper::adminFooter();
$Markup = array_merge(
Menu::rows([
[['📨پیامک تکی', 'ارسال پیامک تکی اول'], ['📢پیامک همگانی', 'ارسال پیامک همگانی اول']],
[['🗣اطلاع رسانی به کاربر', 'اطلاع رسانی اول']],
]),
[Menu::adminHome()]
);
self::logMenuProblems('sms', $Markup);
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Markup));
}

public static function serverServices(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🔌در حال دریافت سرویس های سرور...', false);
}

$Response = ServerClient::allConfigs();
$Json = $Response['Json'] ?? null;

if (($Response['StatusCode'] ?? 0) >= 300 || !is_array($Json['chconfigs'][0] ?? null)) {
self::notifyAdminServerError('دریافت سرویس های سرور', $Context->UserId, (string)$Context->profileName(), $Response['StatusCode'] ?? 0, (string)($Response['Body'] ?? ''));
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, Helper::adminGreeting($Context, 'سرویس های سرور') . "❌خطا: دریافت سرویس های سرور ناموفق بود." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔄بروزرسانی', 'callback_data' => 'سرویس های سرور']],
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}

$Config = $Json['chconfigs'][0] ?? [];
$Services = [
['tls_ports', '🔐رمزنگاری تی ال اس', 'tcp', null],
['http_ports', '🌐وب ساده', 'tcp', null],
['special_port', '⭐پورت ویژه', 'tcp', null],
['ssh_server_port', '🧑‍💻پروتکل اس اس اچ', 'tcp', 'ssh_server_enable'],
['shadowsocks2022_port', '🖤شادوساکس ۲۰۲۲', 'tcp', 'shadowsocks2022_enable'],
['anytls_port', '🔒انی تی ال اس', 'tcp', 'anytls_enable'],
['shadowtls_port', '🕶شادوتی ال اس', 'tcp', 'shadowtls_enable'],
['snell_port', '🟡پروتکل اسنل', 'tcp', 'snell_enable'],
['naive_port', '🟢نایو', 'tcp', 'naive_enable'],
['mieru_port', '🔵میرو', 'tcp', 'mieru_enable'],
['mieru_tcp_ports', '🔵میرو (تی‌سی‌پی)', 'tcp', 'mieru_enable'],
['wireguard_port', '🟣وایرگارد', 'udp', 'wireguard_enable'],
['amnezia_port', '🟠امنزیا وی جی', 'udp', 'amnezia_enable'],
['tuic_port', '🔴تیویک', 'udp', 'tuic_enable'],
['hysteria_port', '🟠هیستریا ۲', 'udp', 'hysteria_enable'],
['kcp_ports', '🟣کی سی پی', 'udp', 'kcp_enable'],
['mieru_udp_ports', '🔵میرو (یو‌دی‌پی)', 'udp', 'mieru_enable'],
];

$Groups = ['tcp' => [], 'udp' => []];

foreach ($Services as [$Field, $Label, $Group, $Flag]) {
if ($Flag !== null && array_key_exists($Flag, $Config) && !$Config[$Flag]) continue;
$Ports = preg_split('/[,\s]+/', trim((string)($Config[$Field] ?? '')), -1, PREG_SPLIT_NO_EMPTY) ?: [];

foreach ($Ports as $Port) {
$Port = trim((string)$Port);

if ($Port === '' || $Port === '0') continue;
$Groups[$Group][] = $Label . ' — `' . Helper::toPersian($Port) . '`';
}
}

$Lines = [];

foreach (['tcp' => '🔌پورت‌های تی‌سی‌پی', 'udp' => '🛰پورت‌های یو‌دی‌پی'] as $Kind => $Title) {
$Items = $Groups[$Kind];
$Lines[] = "{$Title} (" . Helper::toPersian((string)count($Items)) . "):";

if ($Items === []) {
$Lines[] = "├─⭕️هیچ پورتی ثبت نشده است.";
}

else {
foreach ($Items as $Item) {
$Lines[] = "├─" . $Item;
}
}

$Lines[] = "";
}

$Text = Helper::adminGreeting($Context, 'سرویس های سرور')
. "🔌*پورت های عمومی فعال سرور:*\n\n"
. implode("\n", $Lines) . "\n\n"
. "📌مجموع پورت ها: *" . Helper::toPersian((string)(count($Groups['tcp']) + count($Groups['udp']))) . "*"
. Helper::adminFooter();

TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard([
[['text' => '🔄بروزرسانی', 'callback_data' => 'سرویس های سرور']],
[['text' => '📊وضعیت سرور', 'callback_data' => 'وضعیت سرور']],
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

public static function serverConfig(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

$Text = Helper::adminGreeting($Context, 'پیکربندی سرور')
. Menu::section('⚙️', 'دسته بندی عملیات', [
'📊وضعیت سرور و 🔌سرویس ها: سلامت و پورت های باز',
'🔁بروزرسانی مصرف: همگام سازی مصرف کاربران با سرور',
'🔄بروزرسانی داده کاربران: دریافت دوباره مشخصات کلاینت ها',
'✅فعال و 🚫غیرفعال سازی کلاینت کاربر',
'🗑حذف کاربر و ⌛️منقضی کردن اشتراک',
'🗣اطلاع رسانی: پیام گروهی به کاربران سرور',
])
. '📌*عملیات مورد نظر را انتخاب کنید:*' . Helper::adminFooter();
$Markup = array_merge(
Menu::rows([
[['📊وضعیت سرور', 'وضعیت سرور'], ['🔌سرویس های سرور', 'سرویس های سرور']],
]),
Menu::rows([
[['🔁بروزرسانی مصرف', 'بروز رسانی میزان استفاده اول']],
[['🔄بروزرسانی داده کاربران', 'بروز رسانی داده های کاربران اول']],
]),
Menu::rows([
[['✅فعالسازی کلاینت', 'فعالسازی کلاینت اول'], ['🚫غیرفعالسازی کلاینت', 'غیر فعالسازی کلاینت اول']],
[['🗑حذف کاربر', 'حذف کاربر اول'], ['⌛️منقضی کردن اشتراک', 'منقضی اشتراک اول']],
[['🗣اطلاع رسانی به کاربران', 'اطلاع رسانی']],
]),
[Menu::adminHome()]
);
self::logMenuProblems('server', $Markup);
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Markup));
}

public static function databaseMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

$Menu_Text = Helper::adminGreeting($Context, 'مدیریت دیتابیس')
. Menu::section('🗄️', 'عملیات دیتابیس', [
'💾پشتیبان گیری: دریافت فایل پشتیبان از دیتابیس',
'🔄تنظیم مجدد: بازسازی جدول ها',
])
. "⚠️توجه: عملیات تنظیم مجدد غیرقابل بازگشت است.\n"
. '📌*عملیات مورد نظر را انتخاب کنید:*' . Helper::adminFooter();
$Menu_Rows = array_merge(
Menu::rows([
[['💾پشتیبان گیری', 'پشتیبان گیری دیتابیس'], ['🔄تنظیم مجدد', 'تنظیم مجدد دیتابیس']],
]),
[Menu::adminHome()]
);
self::logMenuProblems('database', $Menu_Rows);
$Menu_Markup = TelegramClient::inlineKeyboard($Menu_Rows);

if ($Context->IsCallback && $Context->MessageId !== null) {
try {
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Menu_Text, $Menu_Markup);
return;
}

catch (Throwable) {
try { TelegramClient::deleteMessage($Context->ChatId, $Context->MessageId); } catch (Throwable) {}
}
}

TelegramClient::sendMessage($Context->ChatId, $Menu_Text, $Menu_Markup);
}

public static function databaseBackup(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '💾در حال تهیه نسخه پشتیبان...', false);
}

$Config = Database::getConfig();
$Host = (string)($Config['host'] ?? 'localhost');
$Dbname = (string)($Config['database'] ?? '');
$User = (string)($Config['user'] ?? '');
$Pass = (string)($Config['password'] ?? '');
// Temporary directory outside the web root so a dump can never be downloaded.
$Backup_Dir = sys_get_temp_dir() . '/umbrella_backups';

if (!is_dir($Backup_Dir)) {
@mkdir($Backup_Dir, 0700, true);
}

$Filename = 'backup_' . $Dbname . '_' . date('Y-m-d_H-i-s') . '.sql';
$Filepath = $Backup_Dir . '/' . $Filename;
$Command = sprintf(
"mysqldump --host=%s --user=%s --password=%s --single-transaction --routines --triggers %s > %s 2>&1",
escapeshellarg($Host),
escapeshellarg($User),
escapeshellarg($Pass),
escapeshellarg($Dbname),
escapeshellarg($Filepath)
);

$Output = [];
$Return_Var = 0;
exec($Command, $Output, $Return_Var);

if ($Return_Var !== 0 || !file_exists($Filepath) || filesize($Filepath) === 0) {
$Error_Msg = implode("\n", array_slice($Output, 0, 5));
TelegramClient::sendMessage($Context->ChatId, Helper::adminGreeting($Context, 'مدیریت دیتابیس') . "❌خطا: تهیه نسخه پشتیبان ناموفق بود.\n⚠️علت: ابزار پشتیبان‌گیری دیتابیس با خطا مواجه شد.\n💬جزئیات: " . mb_substr($Error_Msg, 0, 200) . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'دیتابیس']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}

$Size = filesize($Filepath);
$Size_Label = $Size > 1048576 ? round($Size / 1048576, 2) . ' MB' : round($Size / 1024, 2) . ' KB';
$Backup_Caption = Helper::adminGreeting($Context, 'مدیریت دیتابیس')
. "✅نسخه پشتیبان با موفقیت تهیه گردید.\n📄نام فایل: `{$Filename}`\n💾حجم: {$Size_Label}"
. Helper::adminFooter();

$Backup_Markup = TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'دیتابیس']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]);

$Send_Result = TelegramClient::sendDocument($Context->ChatId, $Filepath, $Backup_Caption, $Backup_Markup);

if (is_array($Send_Result) && ($Send_Result['ok'] ?? false) === true) {
@unlink($Filepath);
}

else {
TelegramClient::sendMessage($Context->ChatId, $Backup_Caption . "\n⚠️توجه: ارسال فایل در تلگرام ناموفق بود اما فایل روی سرور موجود است.", $Backup_Markup);
}
}

public static function databaseReset(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, Helper::adminGreeting($Context, 'تنظیم مجدد دیتابیس') . "⚠️هشدار: تنظیم مجدد دیتابیس\n\n⛔️این عملیات تمام جداول را حذف و مجدداً ایجاد می کند.\n🚨تمام اطلاعات کاربران، اشتراک ها، تراکنش ها و... از بین خواهند رفت.\n\n⚠️آیا از انجام این عملیات اطمینان دارید؟" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '✅بله، تنظیم مجدد انجام شود', 'callback_data' => 'تایید تنظیم مجدد دیتابیس']],
[['text' => '❌انصراف', 'callback_data' => 'دیتابیس']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

public static function databaseResetConfirm(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🔄در حال تنظیم مجدد دیتابیس...', false);
}

$Schema_File = __DIR__ . '/../Database/Schema.SQL';

if (!file_exists($Schema_File)) {
TelegramClient::sendMessage($Context->ChatId, Helper::adminGreeting($Context, 'مدیریت دیتابیس') . '❌خطا: فایل ساختار دیتابیس یافت نشد.' . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'دیتابیس']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}

$Schema_SQL = file_get_contents($Schema_File);

try {
$PDO = Database::getInstance()->connection();

if (!$PDO instanceof PDO) throw new RuntimeException('❌اتصال به دیتابیس ناموفق بود.');
$PDO->exec('SET FOREIGN_KEY_CHECKS = 0');
$Dropped_Tables = 0;
$Tables = $PDO->query('SHOW TABLES')->fetchAll(PDO::FETCH_COLUMN);

foreach ($Tables as $Table) {
$PDO->exec('DROP TABLE IF EXISTS `' . $Table . '`');
$Dropped_Tables++;
}

$Statements = array_filter(array_map('trim', explode(';', $Schema_SQL)));
$Count = 0;

foreach ($Statements as $Statement) {
if ($Statement === '' || strpos($Statement, '--') === 0) continue;
$PDO->exec($Statement);
$Count++;
}

$PDO->exec('SET FOREIGN_KEY_CHECKS = 1');

TelegramClient::sendMessage($Context->ChatId, Helper::adminGreeting($Context, 'مدیریت دیتابیس') . "🗑تنظیم مجدد دیتابیس با موفقیت انجام گردید.\n📄تعداد جداول حذف شده: " . Helper::toPersian((string)$Dropped_Tables) . "\n📄تعداد جداول ایجاد شده: " . Helper::toPersian((string)$Count) . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'دیتابیس']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

catch (Throwable $e) {
TelegramClient::sendMessage($Context->ChatId, Helper::adminGreeting($Context, 'مدیریت دیتابیس') . "❌خطا: تنظیم مجدد دیتابیس ناموفق بود.\n⚠️علت: " . mb_substr($e->getMessage(), 0, 200) . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'دیتابیس']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}
}

public static function userRanking(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🏆در حال نمایش رتبه بندی...', false);
}

try { $Live_Users = ServerClient::liveUsers(); }
catch (Throwable) { $Live_Users = []; }
$Top_Users = $Live_Users;
$Stats = ServerClient::liveServerStats($Top_Users);
$Rank_Total = (float)$Stats['total_used'];
$Rank_Number = 0;
$Shown = 0;
$No_Mention = 0;
$Top_Usage = 0.0;

foreach ($Top_Users as $Max_Row) {
$Top_Usage = max($Top_Usage, (float)($Max_Row['Value'] ?? 0));
}

$Ranking_Text = Helper::adminGreeting($Context, 'رتبه بندی کاربران');
$Ranking_Text .= "🏆👑*رتبه بندی کاربران واقعی سرور بر اساس مصرف:*\n";
$Ranking_Text .= "👥تعداد کل: *" . Helper::toPersian((string)$Stats['total']) . "* |🟢فعال: *" . Helper::toPersian((string)$Stats['active']) . "*\n";
$Ranking_Text .= "📥مجموع مصرف: *" . Helper::formatGB($Rank_Total) . "* |🧮میانگین هر کاربر: *" . Helper::formatGB((float)$Stats['avg_used']) . "*\n";
$Ranking_Text .= "🥇جایگاه اول |🥈دوم |🥉سوم |🏅چهارم |🎖️پنجم |🔥سهم بیش از ۲۵٪ |💎بیش از ۱۰۰ گیگ\n";
$Ranking_Text .= "📊درصد = سهم هر کاربر از مصرف کل | نوار = مصرف نسبت به پرمصرف ترین کاربر\n";
$Ranking_Text .= "➖➖➖➖➖➖➖➖➖\n";

foreach ($Top_Users as $User) {
$Rank_Number++;
$FullName = trim((string)($User['Full_Name'] ?? ''));

if ($FullName === '') {
$FullName = trim((string)($User['First_Name'] ?? '')) ?: 'بدون نام';
}

$Usage = (float)($User['Value'] ?? 0);
$Share = $Rank_Total > 0 ? ($Usage / $Rank_Total) * 100.0 : 0.0;
$User_ID_Link = (int)($User['Telegram_ID'] ?? 0);
$Username_Link = trim((string)($User['Username'] ?? ''));
$Name_Link = Helper::mention($FullName, $User_ID_Link, $Username_Link);

if (stripos($Name_Link, '](') === false) {
$No_Mention++;
}

$Usage_Short = str_replace(['ترابایت', 'گیگابایت', 'مگابایت'], ['ترا', 'گیگ', 'مگ'], Helper::formatGB($Usage));
$Marks = '';

if ($Rank_Number === 1) $Marks .= '👑';
if ($Share >= 25.0) $Marks .= '🔥';
if ($Usage >= 100.0) $Marks .= '💎';

$Bar_Percent = $Top_Usage > 0 ? min(100.0, ($Usage / $Top_Usage) * 100.0) : 0.0;
$Line = Helper::rankLine($Rank_Number, $Name_Link, $Usage_Short, $Share, $Bar_Percent, $Marks);
$Ranking_Text .= $Line . "\n";
$Shown++;

if (mb_strlen($Ranking_Text) > 3600) {
$Remaining = max(0, count($Top_Users) - $Rank_Number);
$Ranking_Text .= "ℹ️و " . Helper::toPersian((string)$Remaining) . " کاربر دیگر در پیام بعدی ارسال می شود.\n";
break;
}
}

if (empty($Top_Users)) {
$Ranking_Text .= "❌هیچ کاربری روی سرور ثبت نشده است.\n";
}

$Ranking_Text .= "➖➖➖➖➖➖➖➖➖\n";
$Ranking_Text .= "📊نمایش داده شده: *" . Helper::toPersian((string)$Shown) . "* از *" . Helper::toPersian((string)count($Top_Users)) . "* کاربر سرور\n";

if ($Stats['top_user'] !== []) {
$Top_Name = trim((string)($Stats['top_user']['Full_Name'] ?? ''));

if ($Top_Name === '') $Top_Name = trim((string)($Stats['top_user']['First_Name'] ?? '')) ?: 'کاربر';
$Ranking_Text .= "👑🥇قهرمان مصرف سرور: *{$Top_Name}* با *" . Helper::formatGB((float)($Stats['top_user']['Value'] ?? 0)) . "*\n";
$Ranking_Text .= "🏅📊میانگین مصرف هر کاربر سرور: *" . Helper::formatGB((float)$Stats['avg_used']) . "*\n";
}

$Ranking_Text .= "🔵ℹ️اعضای ربات که روی سرور کاربر فعال ندارند در این رتبه بندی نمایش داده نمی شوند.\n";

if ($No_Mention > 0) {
$Ranking_Text .= "🔹👥" . Helper::toPersian((string)$No_Mention) . " کاربر بدون منشن نمایش داده شده اند (هنوز ربات را استارت نکرده یا نام کاربری تلگرام ندارند).";
}

$Ranking_Text .= Helper::adminFooter();
$Ranking_Markup = TelegramClient::inlineKeyboard([
[['text' => '🔁بروزرسانی رتبه بندی', 'callback_data' => 'رتبه بندی']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]);

$Chunks = self::splitMessage($Ranking_Text, 3400);
$First_Chunk = $Chunks[0];
$Single_Message = count($Chunks) === 1;

if ($Context->IsCallback && $Context->MessageId !== null) {
try {
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $First_Chunk, $Single_Message ? $Ranking_Markup : []);
}

catch (Throwable) {
try { TelegramClient::deleteMessage($Context->ChatId, $Context->MessageId); } catch (Throwable) {}
TelegramClient::sendMessage($Context->ChatId, $First_Chunk, $Single_Message ? $Ranking_Markup : []);
}
}

else {
TelegramClient::sendMessage($Context->ChatId, $First_Chunk, $Single_Message ? $Ranking_Markup : []);
}

for ($Index = 1; $Index < count($Chunks); $Index++) {
$Is_Last = $Index === count($Chunks) - 1;
TelegramClient::sendMessage($Context->ChatId, "🔽ادامه رتبه بندی:\n" . $Chunks[$Index], $Is_Last ? $Ranking_Markup : []);
}
}

public static function serverNotifyMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

$Text = Helper::adminGreeting($Context, 'اطلاع رسانی سرور')
. Menu::section('🗣', 'روش اطلاع رسانی', [
'✏️سفارشی: متن آزاد برای کاربران',
'📱برنامه ها: اعلان در برنامه کاربران',
'📣تلگرام و برنامه: ارسال همزمان',
'🚫عدم استفاده: یادآوری به کاربران بی مصرف',
])
. '📌*روش اطلاع رسانی را انتخاب کنید:*' . Helper::adminFooter();
$Markup = array_merge(
Menu::rows([
[['✏️سفارشی', 'اطلاع رسانی سفارشی اول'], ['📱برنامه ها', 'app_push_start']],
[['📣تلگرام و برنامه', 'notify_all_start'], ['🚫عدم استفاده', 'اطلاع رسانی عدم استفاده']],
]),
[Menu::back('پیکربندی سرور', 'پیکربندی سرور')],
[Menu::adminHome()]
);
self::logMenuProblems('notify', $Markup);
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Markup));
}

public static function serverNotifyCustomStart(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '✏️در حال آماده سازی اطلاع رسانی سفارشی...', false);
}

Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:notify_broadcast_text', 'Broadcast_Mode' => 'both']);
$Text = Helper::adminGreeting($Context, 'اطلاع رسانی سفارشی')
. "✏️*اطلاع رسانی سفارشی آماده ارسال است.*\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "👌متن دلخواه خود را در یک پیام بفرستید.\n"
. "📤این متن برای تمام کاربران از طریق تلگرام و پیامک ارسال می شود.\n"
. "ℹ️فقط متن را ارسال کنید؛ هیچ دکمه ای را نزنید." . Helper::adminFooter();

if ($Context->MessageId !== null) {
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard([
Menu::back('اطلاع رسانی سرور', 'اطلاع رسانی سرور'),
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

else {
TelegramClient::sendMessage($Context->ChatId, $Text, TelegramClient::inlineKeyboard([
Menu::back('اطلاع رسانی سرور', 'اطلاع رسانی سرور'),
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}
}

public static function serverNotifyIdle(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🔄در حال بررسی کاربران غیرفعال...', false);
}

$Threshold_Days = 3;
$Now_Ts = time();
$Rows = Database::getInstance()->fetchAll(
"SELECT `Telegram_ID`, `Chat_ID`, `Phone`, `Client_ID`, `Full_Name`
FROM `Users`
WHERE `Client_ID` IS NOT NULL
AND `Client_ID` != ''
AND `Client_ID` != '_'
AND `Expiration_Time_Stamp` IS NOT NULL
AND `Expiration_Time_Stamp` > ?",
[$Now_Ts]
);

$Users_List = [];

foreach ($Rows as $Row) {
$Client_ID = trim((string)($Row['Client_ID'] ?? ''));

if ($Client_ID === '' || $Client_ID === '_') continue;
$Server_Response = ServerClient::getUser($Client_ID);
$Json = $Server_Response['Json'] ?? [];
$Last_Online = '';

if (is_array($Json)) {
$Last_Online = (string)($Json['last_online'] ?? '');

if ($Last_Online === '' && isset($Json['online_at'])) {
$Last_Online = (string)$Json['online_at'];
}
}

if ($Last_Online === '') continue;
$Last_Ts = Helper::parseServerTimeSafe($Last_Online);

if ($Last_Ts <= 0) continue;
$Diff_Seconds = time() - $Last_Ts;

if ($Diff_Seconds < 0) continue;
if ($Diff_Seconds < ($Threshold_Days * 86400)) continue;
$Users_List[] = [
'User_ID' => (int)($Row['Telegram_ID'] ?? 0),
'Chat_ID' => (int)($Row['Chat_ID'] ?? 0),
'Phone' => trim((string)($Row['Phone'] ?? '')),
'Full_Name' => trim((string)($Row['Full_Name'] ?? '')),
'Last_Online' => $Last_Online,
'Days' => (int)floor($Diff_Seconds / 86400),
'Seconds' => $Diff_Seconds,
'Duration' => Helper::humanDuration($Diff_Seconds),
'Long_Duration' => Helper::idleEquivalent($Diff_Seconds),
];
}

if (empty($Users_List)) {
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, Helper::adminGreeting($Context, 'عدم استفاده از سرور') . "⭕️هیچ کاربر فعالی وجود ندارد که بیش از " . Helper::toPersian((string)$Threshold_Days) . " روز از آخرین اتصالش گذشته باشد." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}

Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Idle_Notify_Users' => json_encode($Users_List, JSON_UNESCAPED_UNICODE)]);

$Preview = "🚫<b>اطلاع رسانی به کاربران غیرفعال</b>\n➖➖➖➖➖➖➖➖➖\n";
$Preview .= "👥<b>تعداد کاربران شناسایی شده:</b> " . Helper::toPersian(count($Users_List)) . " نفر\n\n";
$Preview .= "<b>📋پیش نمایش ۱۰ کاربر اول:</b>\n";
$Count = 0;

foreach ($Users_List as $U) {
$Count++;

if ($Count > 10) break;
$Preview .= "├─" . Helper::toPersian((string)$Count) . ". " . ($U['Full_Name'] !== '' ? $U['Full_Name'] : 'بدون نام') . " - ⏳ " . ((string)($U['Duration'] ?? '') !== '' ? $U['Duration'] : 'نامشخص') . "\n";
}

$Preview .= "\n⚠️<b>پس از تایید، پیام به تمام این کاربران (هم تلگرام و هم پیامک) ارسال خواهد شد.</b>" . Helper::adminFooter();
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, Helper::adminGreeting($Context, 'پیش نمایش اطلاع رسانی') . $Preview, TelegramClient::inlineKeyboard([
[['text' => '✅بله، ارسال شود', 'callback_data' => 'تایید اطلاع رسانی غیرفعال']],
[['text' => '❌انصراف', 'callback_data' => 'اطلاع رسانی']],
]));
}

public static function serverNotifyIdleSend(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '📨در حال ارسال...', false);
}

$Session = Repository::getUserSession($Context->UserId);
$Users_Json = (string)($Session['Idle_Notify_Users'] ?? '');
$Users_List = json_decode($Users_Json, true);

if (!is_array($Users_List) || empty($Users_List)) {
TelegramClient::sendMessage($Context->ChatId, Helper::adminGreeting($Context, 'اطلاع رسانی به کاربران غیرفعال') . '❌خطا: لیست کاربران منقضی شده است. لطفاً مجدد اقدام کنید.' . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'اطلاع رسانی']],
]));
return;
}

Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Idle_Notify_Users' => null]);
$Sms_Template = Repository::getSmsTemplate('idle_notify');

if ($Sms_Template === null || trim($Sms_Template) === '') {
$Sms_Template = "{full_name} گرامی از آخرین اتصال شما به سرور بیش از {days} روز گذشته است.\nاشتراک شما همچنان فعال است.\n\nسرور آمبرلا";
}

$Sent_Tg = 0;
$Sent_Sms = 0;
$Failed_Sms = 0;

foreach ($Users_List as $U) {
$User_ID = (int)($U['User_ID'] ?? 0);
$Chat_ID = (int)($U['Chat_ID'] ?? 0);
$Phone = trim((string)($U['Phone'] ?? ''));
$Name = trim((string)($U['Full_Name'] ?? ''));

if ($Name === '') {
$Name = trim((string)(Repository::getUser($User_ID)['First_Name'] ?? ''));
}

if ($Name === '') $Name = 'کاربر';
$Duration = trim((string)($U['Duration'] ?? ''));

if ($Duration === '') {
$Duration = Helper::humanDuration((int)($U['Seconds'] ?? 0));
}

$Last_Online = trim((string)($U['Last_Online'] ?? ''));
$Last_Online_Label = 'نامشخص';

if ($Last_Online !== '' && $Last_Online !== '0001-01-01 00:00:00') {
try {
$Last_Online_Label = Helper::gregorianToJalali(substr($Last_Online, 0, 10)) . ' - ' . Helper::formatTime(substr($Last_Online, 11, 8));
}

catch (Throwable) { $Last_Online_Label = $Last_Online; }
}

$Idle_Days = (int)($U['Days'] ?? 0);
$Idle_Days_Label = Helper::toPersian((string)$Idle_Days) . ' روز';
$Idle_Days_Number_Label = Helper::toPersian((string)$Idle_Days);
$Idle_Weeks_Label = trim((string)($U['Long_Duration'] ?? ''));
$Idle_Weeks_Label = $Idle_Weeks_Label !== '' ? $Idle_Weeks_Label : $Idle_Days_Label;
$Sms_Text = self::renderIdleSms($Sms_Template, $Name, $Duration, $Last_Online_Label, $Idle_Days_Number_Label);
$Tg_Text = "🔔<b>اطلاع رسانی سرور آمبرلا</b>\n" . Helper::frame('کاربر', $Name, 'گزارش عدم استفاده', $User_ID) . "\n"
. "⏳<b>مدت عدم استفاده شما از سرور:</b> <b>{$Duration}</b>\n"
. "📅<b>معادل این مدت:</b> <b>{$Idle_Weeks_Label}</b>\n"
. "🕓<b>آخرین اتصال شما:</b> <b>{$Last_Online_Label}</b>\n"
. "🆔<b>شناسه حساب:</b> <code>" . Helper::toPersian((string)$User_ID) . "</code>\n\n"
. "<blockquote>✅<b>اشتراک شما همچنان فعال است</b>\n"
. "✅هیچ محدودیتی روی حساب شما اعمال نشده است؛ فقط کافیست یک بار اپلیکیشن را باز کنید و به سرور وصل شوید.</blockquote>\n\n"
. "💡<b>نیاز به راهنمایی دارید؟</b> از بخش «🎫تیکت ها و پشتیبانی» درخواست خود را ثبت کنید.\n"
. "📶<b>لینک اتصال:</b> از بخش «💎اشتراک من» دریافت کنید.\n"
. "🎁با تشکر از همراهی شما — <b>سرور آمبرلا</b>" . Helper::userFooter();

if ($Chat_ID > 0) {
$Result = TelegramClient::sendMessage($Chat_ID, $Tg_Text, TelegramClient::inlineKeyboard([
[['text' => '💎اشتراک من', 'callback_data' => 'اشتراک من']],
[['text' => '🎫تیکت ها و پشتیبانی', 'callback_data' => 'تیکت های من']],
Menu::userHome(),
]));

if (($Result['ok'] ?? false) === true) $Sent_Tg++;
}

if ($Phone !== '' && strlen($Phone) >= 10) {
$Sms_Ok = IppanelClient::send($User_ID, $Phone, $Sms_Text);

if ($Sms_Ok === true) {
$Sent_Sms++;
}

else {
$Failed_Sms++;
}
}
}

$Summary = "✅تعداد موفق تلگرام: " . Helper::toPersian($Sent_Tg) . " نفر\n";
$Summary .= "✅تعداد موفق پیامک: " . Helper::toPersian($Sent_Sms) . " پیامک\n";
$Summary .= "⛔️تعداد ناموفق پیامک: " . Helper::toPersian($Failed_Sms) . " پیامک";

TelegramClient::sendMessage($Context->ChatId, Helper::adminGreeting($Context, 'اطلاع رسانی به کاربران غیرفعال') . '✅اطلاع رسانی با موفقیت انجام شد.' . "\n{$Summary}" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

private static function renderIdleSms(string $Template, string $Name, string $Duration, string $Last_Online_Label = 'نامشخص', string $Days_Label = ''): string {
$Template = preg_replace('/\{DURATION\}\s*روز/u', '{days}', $Template) ?? $Template;
$Template = preg_replace('/بیش\s*از\s*\{DURATION\}/u', 'بیش از {days}', $Template) ?? $Template;
$Template = str_replace('{DURATION}', '{days} روز', $Template);

$Text = str_replace(
['{full_name}', '{last_online}', '{days}'],
[$Name, $Last_Online_Label, $Days_Label !== '' ? $Days_Label : $Duration],
$Template
);

$Days = $Days_Label !== '' ? $Days_Label : $Duration;
$Text = preg_replace('/بیش\s*از\s*(?:۳|3|سه)\s*روز/u', 'بیش از ' . $Days . ' روز', $Text) ?? $Text;

if (!str_contains($Template, '{days}')) {
$Text = preg_replace('/(?:۳|3|سه)\s*روز/u', $Days . ' روز', $Text) ?? $Text;
}

$Text = trim($Text);
return $Text !== '' ? $Text : "{$Name} گرامی از آخرین اتصال شما به سرور بیش از {$Days} روز گذشته است.\n✅اشتراک شما همچنان فعال است.\n\nسرور آمبرلا";
}

public static function serverStatus(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🔄در حال بارگذاری وضعیت سرور...', false);
}

$Response = ServerClient::serverStatus();
$Json = $Response['Json'] ?? null;

if (!is_array($Json) || ($Response['StatusCode'] ?? 0) >= 300) {
self::notifyAdminServerError('دریافت وضعیت سرور', $Context->UserId, (string)$Context->profileName(), $Response['StatusCode'] ?? 0, (string)($Response['Body'] ?? ''));
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, Helper::adminGreeting($Context, 'پیکربندی سرور') . '❌خطا: دریافت وضعیت سرور ناموفق بود.' . "\n➖➖➖➖➖➖➖➖➖\n⚠️پاسخ سرور: " . mb_substr((string)($Response['Body'] ?? ''), 0, 200) . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}

$System = $Json['stats']['system'] ?? [];
$History = $Json['usage_history'] ?? [];
$Top5_Cpu = $Json['stats']['top5']['cpu'] ?? [];
$Bytes_Recv = (float)($System['bytes_recv'] ?? 0);
$Bytes_Sent = (float)($System['bytes_sent'] ?? 0);
$Cpu_Percent = (float)($System['cpu_percent'] ?? 0);
$Disk_Total = (float)($System['disk_total'] ?? 0);
$Disk_Used = (float)($System['disk_used'] ?? 0);
$Ram_Total = (float)($System['ram_total'] ?? 0);
$Ram_Used = (float)($System['ram_used'] ?? 0);
$Num_Cpus = (int)($System['num_cpus'] ?? 0);
$Total_Connections = (int)($System['total_connections'] ?? 0);
$Unique_Ips = (int)($System['total_unique_ips'] ?? 0);
$Load_1 = (float)($System['load_avg_1min'] ?? 0);
$Load_5 = (float)($System['load_avg_5min'] ?? 0);
$Load_15 = (float)($System['load_avg_15min'] ?? 0);
$Disk_Percent = $Disk_Total > 0 ? round(($Disk_Used / $Disk_Total) * 100, 1) : 0;
$Ram_Percent = $Ram_Total > 0 ? round(($Ram_Used / $Ram_Total) * 100, 1) : 0;
$Today_Online = (int)($History['today']['online'] ?? 0);
$Today_Usage = (float)($History['today']['usage'] ?? 0);
$Yesterday_Online = (int)($History['yesterday']['online'] ?? 0);
$Yesterday_Usage = (float)($History['yesterday']['usage'] ?? 0);
$M5_Online = (int)($History['m5']['online'] ?? 0);
$H24_Online = (int)($History['h24']['online'] ?? 0);
$Total_Online = (int)($History['total']['online'] ?? 0);
$Total_Usage = (float)($History['total']['usage'] ?? 0);
$Total_Users = (int)($History['total']['users'] ?? 0);
$Disk_Used_Human = Helper::formatBytes((int)($Disk_Used * 1024 * 1024 * 1024));
$Disk_Total_Human = Helper::formatBytes((int)($Disk_Total * 1024 * 1024 * 1024));
$Ram_Used_Human = Helper::formatBytes((int)($Ram_Used * 1024 * 1024 * 1024));
$Ram_Total_Human = Helper::formatBytes((int)($Ram_Total * 1024 * 1024 * 1024));
$Load_1_Human = number_format($Load_1, 2);
$Load_5_Human = number_format($Load_5, 2);
$Load_15_Human = number_format($Load_15, 2);
$Recv_Human = Helper::formatBytes((int)$Bytes_Recv);
$Sent_Human = Helper::formatBytes((int)$Bytes_Sent);
$Today_Usage_Human = Helper::formatBytes((int)$Today_Usage);
$Yesterday_Usage_Human = Helper::formatBytes((int)$Yesterday_Usage);
$Total_Usage_Human = Helper::formatBytes((int)$Total_Usage);
$Last_30_Online = (int)($History['last_30_days']['online'] ?? 0);
$Last_30_Usage = (float)($History['last_30_days']['usage'] ?? 0);
$Panel_Used_Gb = (float)($System['panel_used_GB'] ?? ($System['hiddify_used'] ?? 0));
$Net_Sent_Total = (float)($System['net_sent_cumulative_GB'] ?? 0);
$Net_Total_GB = (float)($System['net_total_cumulative_GB'] ?? 0);
$Recv_Cumulative = (float)($System['bytes_recv_cumulative'] ?? 0);
$Sent_Cumulative = (float)($System['bytes_sent_cumulative'] ?? 0);
$Last_30_Usage_Human = Helper::formatBytes((int)$Last_30_Usage);
$Recv_Cumulative_Human = Helper::formatBytes((int)$Recv_Cumulative);
$Sent_Cumulative_Human = Helper::formatBytes((int)$Sent_Cumulative);
$Net_Total_Human = Helper::toPersian(number_format($Net_Total_GB, 2, '.', '')) . ' گیگابایت';
$Net_Sent_Total_Human = Helper::toPersian(number_format($Net_Sent_Total, 2, '.', '')) . ' گیگابایت';
$Umbrella_Used_Human = Helper::toPersian(number_format($Panel_Used_Gb, 2, '.', '')) . ' گیگابایت';
$Last_30_Online_Label = Helper::toPersian((string)$Last_30_Online);

$Text = Helper::adminGreeting($Context, 'وضعیت سرور') . ""
. "📊وضعیت سرور آمبرلا:\n\n"
. "🖥️*منابع سیستم:*\n"
. "├─🔋پردازنده: `" . Helper::toPersian((string)$Cpu_Percent) . "`٪\n"
. "├─📦تعداد هسته: `" . Helper::toPersian((string)$Num_Cpus) . "`\n"
. "├─🧮رم: `" . $Ram_Used_Human . "` از `" . $Ram_Total_Human . "` (`" . Helper::toPersian((string)$Ram_Percent) . "`٪)\n"
. "├─💾دیسک: `" . $Disk_Used_Human . "` از `" . $Disk_Total_Human . "` (`" . Helper::toPersian((string)$Disk_Percent) . "`٪)\n"
. "├─📈میانگین بار ۱ دقیقه: `" . Helper::toPersian($Load_1_Human) . "`\n"
. "├─📉میانگین بار ۵ دقیقه: `" . Helper::toPersian($Load_5_Human) . "`\n"
. "└─📊میانگین بار ۱۵ دقیقه: `" . Helper::toPersian($Load_15_Human) . "`\n\n"
. "🌐*وضعیت شبکه:*\n"
. "├─⬇️ترافیک ورودی: `" . $Recv_Human . "`\n"
. "├─⬆️ترافیک خروجی: `" . $Sent_Human . "`\n"
. "├─🔗کل اتصال ها: `" . Helper::toPersian((string)$Total_Connections) . "`\n"
. "└─👤نشانی آی پی یکتا: `" . Helper::toPersian((string)$Unique_Ips) . "`\n\n"
. "📚*آمار تجمعی:*\n"
. "├─⬇️کل دریافتی: `" . $Recv_Cumulative_Human . "`\n"
. "├─⬆️کل ارسالی: `" . $Sent_Cumulative_Human . "`\n"
. "├─🌐کل ترافیک: `" . $Net_Total_Human . "`\n"
. "├─📤ارسالی کل: `" . $Net_Sent_Total_Human . "`\n"
. "└─🧩مصرف آمبرلا: `" . $Umbrella_Used_Human . "`\n\n"
. "👥*کاربران و ترافیک:*\n"
. "├─👤کل کاربران: `" . Helper::toPersian((string)$Total_Users) . "`\n"
. "├─🟢آنلاین کل: `" . Helper::toPersian((string)$Total_Online) . "`\n"
. "├─⚡️آنلاین ۵ دقیقه: `" . Helper::toPersian((string)$M5_Online) . "`\n"
. "├─🗓️آنلاین ۲۴ ساعت: `" . Helper::toPersian((string)$H24_Online) . "`\n"
. "├─📅آنلاین امروز: `" . Helper::toPersian((string)$Today_Online) . "`\n"
. "├─📆آنلاین دیروز: `" . Helper::toPersian((string)$Yesterday_Online) . "`\n"
. "├─🗓️آنلاین ۳۰ روز: `" . $Last_30_Online_Label . "`\n"
. "├─📊ترافیک امروز: `" . $Today_Usage_Human . "`\n"
. "├─📊ترافیک دیروز: `" . $Yesterday_Usage_Human . "`\n"
. "├─📊ترافیک ۳۰ روز: `" . $Last_30_Usage_Human . "`\n"
. "└─📚ترافیک کل: `" . $Total_Usage_Human . "`"
. Helper::adminFooter();

TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard([
[['text' => '🔄بروز رسانی', 'callback_data' => 'وضعیت سرور']],
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

public static function creditMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

$Text = Helper::adminGreeting($Context, 'کاربران و اعتبار')
. Menu::section('👥', 'عملیات اعتبار', [
'➕افزایش اعتبار کیف پول کاربر',
'➖کسر اعتبار کیف پول کاربر',
'👁مشاهده موجودی و مشخصات کاربر',
])
. '📌*عملیات مورد نظر را انتخاب کنید:*' . Helper::adminFooter();
$Markup = array_merge(
Menu::rows([
[['➕افزایش اعتبار', 'افزایش اعتبار اول'], ['➖کسر اعتبار', 'کسر اعتبار اول']],
[['👁مشاهده اعتبار', 'مشاهده اعتبار اول']],
]),
[Menu::adminHome()]
);
self::logMenuProblems('credit', $Markup);
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Markup));
}

public static function crimes(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

$Blocked_Count = count(Repository::getBlockedUsers(1000));
$Text = Helper::adminGreeting($Context, 'مسدودیت کاربران')
. Menu::section('🚨', 'عملیات مسدودیت', [
'🚫🔒مسدود کردن کاربر متخلف',
'✅🔓رفع مسدودیت کاربر',
'👁مشاهده فهرست مسدود شده ها',
'📊تعداد مسدود شده: *' . Helper::toPersian((string)$Blocked_Count) . '* نفر',
])
. '📌*عملیات مورد نظر را انتخاب کنید:*' . Helper::adminFooter();
$Markup = array_merge(
Menu::rows([
[['🚫🔒مسدود کردن', 'مسدودیت اول'], ['✅🔓رفع مسدودیت', 'رفع مسدودیت اول']],
[['👁مشاهده مسدودی ها', 'مشاهده مسدودی ها']],
]),
[Menu::adminHome()]
);
self::logMenuProblems('crimes', $Markup);
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Markup));
}

public static function blockedList(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

$Blocked_Users = Repository::getBlockedUsers();
$Text = Helper::adminGreeting($Context, 'مشاهده مسدودی ها') . '🚫🔒*لیست کاربران مسدود شده:*' . "\n➖➖➖➖➖➖➖➖➖\n";

if (empty($Blocked_Users)) {
$Text .= '✅هیچ کاربری مسدود نشده است.';
}

else {
$Rank = 0;

foreach ($Blocked_Users as $Row) {
$Rank++;
$Full_Name = trim((string)($Row['Full_Name'] ?? ''));
$Display = $Full_Name !== '' ? $Full_Name : ((trim((string)($Row['First_Name'] ?? '')) !== '') ? trim((string)($Row['First_Name'] ?? '')) : 'بدون نام');
$UID = (int)($Row['Telegram_ID'] ?? 0);
$Safe_Name = str_replace(['[', ']', "\r", "\n"], '', $Display);
$Name_Mention = ($UID > 0 && $Safe_Name !== '') ? ('[' . $Safe_Name . '](tg://user?id=' . $UID . ')') : $Display;
$Text .= Helper::toPersian((string)$Rank) . ".🔴{$Name_Mention} —🆔" . Helper::toPersian((string)$UID) . "\n";
}

$Text .= "\n📊تعداد کل مسدود شده ها: *" . Helper::toPersian((string)count($Blocked_Users)) . "* نفر";
}

$Text .= Helper::adminFooter();

TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'جرایم']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

public static function updateMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

$Current_Version = BotConfig::robotVersion();
$Current_Changes = (string)Repository::getSetting('Robot_Changes', '');
$Text = Helper::adminGreeting($Context, 'بروز رسانی') . '🔁نسخه فعلی: `' . Helper::toPersian($Current_Version) . '`' . "\n\n";

if ($Current_Changes !== '') {
$Text .= "📝تغییرات اخیر:\n" . $Current_Changes . "\n\n";
}

$Text .= Helper::adminFooter();

TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard(array_merge(
Menu::rows([
[['🔄افزودن نسخه جدید', 'افزودن نسخه جدید اول']],
]),
[Menu::adminHome()]
)));
}


public static function startInput(Context $Context, string $State, string $Prompt): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
Repository::updateUserSession($Context->UserId, ['Flow' => $State]);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . $Prompt . Helper::adminFooter(), TelegramClient::inlineKeyboard([
Menu::adminHome(),
]));
}

public static function startInputBroadcast(Context $Context, string $Mode, string $Prompt): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:notify_broadcast_text', 'Broadcast_Mode' => $Mode]);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . $Prompt . Helper::adminFooter(), TelegramClient::inlineKeyboard([
Menu::adminHome(),
]));
}



public static function toggleRobot(Context $Context, bool $On): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
Repository::setSetting('Robot_Status', $On ? '🟢روشن' : '🔴خاموش');

if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, $On ? '🤖ربات روشن شد' : '🤖ربات خاموش شد', false);
}

self::menu($Context);
}

public static function handleInput(Context $Context, string $Flow, string $Text): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Session = Repository::getUserSession($Context->UserId);
match(true) {
str_starts_with($Flow, 'admin:credit_add') => self::creditStep($Context, $Flow, $Text, true),
str_starts_with($Flow, 'admin:credit_sub') => self::creditStep($Context, $Flow, $Text, false),
$Flow === 'admin:view_uid' => self::showCredit($Context, trim($Text)),
$Flow === 'admin:block_uid' => self::blockUser($Context, trim($Text), true),
$Flow === 'admin:unblock_uid' => self::blockUser($Context, trim($Text), false),
$Flow === 'admin:deactivate_uid' => self::clientStatusStep($Context, trim($Text), false),
$Flow === 'admin:deactivate_msg' => self::clientDeactivateMessage($Context, trim($Text)),
$Flow === 'admin:activate_uid' => self::clientStatusStep($Context, trim($Text), true),
$Flow === 'admin:update_uid' => self::refreshUserData($Context, $Text),
$Flow === 'admin:delete_uid' => self::deleteUser($Context, trim($Text)),
$Flow === 'admin:sms_single_uid' => self::singleSmsStep($Context, trim($Text)),
$Flow === 'admin:sms_single_mode' => self::singleSmsModeRetry($Context),
$Flow === 'admin:sms_single_text' => self::singleSmsSend($Context, trim($Text)),
$Flow === 'admin:notify_uid' => self::notifyUidStep($Context, trim($Text)),
$Flow === 'admin:notify_mode' => self::notifyModeRetry($Context),
$Flow === 'admin:notify_text' => self::notifyUser($Context, trim($Text)),
$Flow === 'admin:notify_broadcast_text' => self::broadcastNotify($Context, trim($Text), (string)($Session['Broadcast_Mode'] ?? 'telegram')),
$Flow === 'admin:device_limit_target' => self::deviceLimitTarget($Context, trim($Text)),
$Flow === 'admin:device_limit_pick' => self::deviceLimitPickInput($Context, trim($Text)),
$Flow === 'admin:notify_all_text' => self::broadcastTelegramAndApp($Context, $Text),
$Flow === 'admin:app_push_target' => self::appPushTarget($Context, trim($Text)),
$Flow === 'admin:app_push_text' => self::appPushText($Context, $Text),
$Flow === 'admin:expire_uid' => self::manualExpire($Context, trim($Text)),
$Flow === 'admin:version_number' => self::versionNumber($Context, trim($Text)),
$Flow === 'admin:version_changes' => self::versionChanges($Context, $Text),
$Flow === 'admin:emergency_url' => self::emergencyUrlSave($Context, $Text),
str_starts_with($Flow, 'admin:cfg:') => self::cfgSave($Context, substr($Flow, strlen('admin:cfg:')), $Text),
$Flow === 'admin:ticket_reply_text' => self::ticketAdminReplySend($Context, trim($Text)),
default => self::unknownAdminInput($Context),
};
}

private static function unknownAdminInput(Context $Context): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "⚠️ورودی شما با هیچ عملیات در انتظاری مطابقت نداشت و نادیده گرفته شد.\n👌لطفاً برای ادامه از دکمه‌های منو استفاده کنید یا دستور `/panel` را ارسال نمایید." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[Menu::adminHome()],
]));
}

/**
 * پیدا کردن کاربر از شناسه یا شماره موبایل.
 *
 * `$BackTo` مقصد دکمه بازگشت است. `$Back_Label` فقط برای سازگاری با فراخوانی
 * های قدیمی نگه داشته شده و دیگر استفاده نمی شود؛ برچسب همه دکمه های بازگشت
 * «🔙بازگشت» است.
 */
private static function resolveTarget(Context $Context, string $Target_Input, string $BackTo = 'مدیریت', string $Back_Label = 'منوی مدیریت'): ?array {
unset($Back_Label);
$Target_Input = trim($Target_Input);

if ($Target_Input === '') {
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *❌خطا: شناسه کاربر خالی است.\n➖➖➖➖➖➖➖➖➖\n⚠️لطفا شناسه عددی کاربر یا شماره موبایل را وارد کنید." . Helper::adminFooter(), TelegramClient::inlineKeyboard([Common::backTo(Menu::BACK_LABEL, $BackTo)]));
return null;
}

$User = Repository::findUserByIdentifier($Target_Input);

if ($User === null) {
$User = self::findUserOnServer($Target_Input);
}

if ($User === null) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *❌خطا: کاربری با شناسه `" . Helper::toPersian($Target_Input) . "` در سیستم یافت نشد.\n➖➖➖➖➖➖➖➖➖\n⚠️دلایل ممکن: کاربر ربات را استارت نکرده، شناسه اشتباه وارد شده یا شماره موبایل در پروفایل یا کلاینت سرور ثبت نشده است." . Helper::adminFooter(), TelegramClient::inlineKeyboard([Common::backTo(Menu::BACK_LABEL, $BackTo)]));
return null;
}

return $User;
}

private static function findUserOnServer(string $Identifier): ?array {
$Identifier = trim($Identifier);

if ($Identifier === '' || trim(Environment::getUmbrellaBaseUrl()) === '') {
return null;
}

try {
$Response = ServerClient::listUsers();
}

catch (Throwable) {
return null;
}

$Rows = $Response['Json'] ?? null;

if (!is_array($Rows) || ($Response['StatusCode'] ?? 0) >= 300) {
return null;
}

$Matched = Repository::findUserInServerRows($Rows, $Identifier);

if ($Matched === null) {
return null;
}

try {
return Repository::linkServerRowToUser($Matched);
}

catch (Throwable) {
return null;
}
}

public static function versionNumber(Context $Context, string $Version): void {
$Version = trim($Version);

if (!preg_match('/^\d+\.\d+\.\d+$/', $Version)) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "❌فرمت نسخه نامعتبر است.\n➖➖➖➖➖➖➖➖➖\n⚠️مثال صحیح: `1.0.0`\n🔁لطفاً شماره نسخه را با فرمت درست وارد کنید:\n👇مثلاً `1.0.1`" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'بروز رسانی']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}

BotConfig::setRobotVersion($Version);
Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:version_changes']);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "✅نسخه `" . Helper::toPersian($Version) . "` ثبت شد.\n\n👌حالا تغییرات این نسخه را وارد کنید." . Helper::adminFooter());
}

private static function versionChanges(Context $Context, string $Changes): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
Repository::setSetting('Robot_Changes', $Changes);
$Version = BotConfig::robotVersion();

TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *✅ربات با موفقیت به نسخه `" . Helper::toPersian($Version) . "` بروزرسانی گردید." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'بروز رسانی']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));

$Channell_ID = (string)BotConfig::getTelegramChannelId();

if ($Channell_ID === '') return;
$Channell_ID_Int = (int)$Channell_ID;

if ($Channell_ID_Int === 0) return;
$Message = Helper::adminGreetingNamed((string)(Repository::getSetting('Admin_Full_Name') ?: Environment::getAdminFullName()), 'بروز رسانی نسخه') . "✅سلام کاربران گرامی ربات با موفقیت بروز رسانی گردید.\n" . "" . "\n➖➖➖➖➖➖➖➖➖\n🔰اطلاعات بروز رسانی جدید بدین شرح است:\n\n🔄نسخه جدید ربات: " . Helper::toPersian($Version) . "\n\n" . $Changes . "*";

$Markup = TelegramClient::inlineKeyboard([
[['text' => '🤖ورود به ربات (فیلترشکن آمبرلا)', 'url' => BotIdentity::link()]],
[['text' => '🧑‍💻پشتیبانی از ما (آرمین سافت)', 'url' => BotConfig::getSupportUrl() ?: 'https://t.me/ARMIN_SOFT']],
]);

if (mb_strlen($Message) <= 1000) {
$Logo = dirname(__DIR__) . DIRECTORY_SEPARATOR . 'Logo.png';
$Photo = $Logo;
TelegramClient::sendPhoto($Channell_ID_Int, $Photo, $Message, $Markup);
}

elseif (mb_strlen($Message) <= 4000) {
TelegramClient::sendMessage($Channell_ID_Int, $Message, $Markup);
}

else {
$Chunks = preg_split('/(.{4000})/us', $Message, -1, PREG_SPLIT_DELIM_CAPTURE | PREG_SPLIT_NO_EMPTY);

foreach ($Chunks as $Index => $Chunk) {
if ($Index === 0) {
TelegramClient::sendMessage($Channell_ID_Int, $Chunk, $Markup);
}

else {
TelegramClient::sendMessage($Channell_ID_Int, $Chunk);
}
}
}
}

private static function targetDisplayName(int $Target, array $User): string {
$Full_Name = (string)($User['Full_Name'] ?? '');
$First_Name = (string)($User['First_Name'] ?? '');

if ($Full_Name !== '') {
return $Full_Name . " (`" . Helper::toPersian($Target) . "`)";
}

if ($First_Name !== '') {
return $First_Name . " (`" . Helper::toPersian($Target) . "`)";
}

return "`" . Helper::toPersian($Target) . "`";
}

public static function notifyAdminServerError(string $Operation, int $User_ID, string $Name, int $Status_Code, string $Error): void {
$Admin = (int)Repository::getSetting('Administrator', (string)Environment::getAdminUserId());
$Status_Text = $Status_Code > 0 ? 'HTTP ' . $Status_Code : 'خطا در ارتباط';
TelegramClient::sendMessage($Admin, Helper::adminGreetingNamed((string)(Repository::getSetting('Admin_Full_Name') ?: Environment::getAdminFullName()), 'خطای سرور', $Admin) . "❌خطای سرور در عملیات: {$Operation}\n\n"
. "👤کاربر: {$Name}\n"
. "🆔آیدی: `" . Helper::toPersian($User_ID) . "`\n"
. "📡وضعیت: {$Status_Text}\n"
. "⚠️پاسخ: " . mb_substr($Error, 0, 500) . "\n"
. "➖➖➖➖➖➖➖➖➖\n"
. Helper::adminFooter());
}

private static function creditStep(Context $Context, string $Flow, string $Text, bool $Add): void {
if (str_ends_with($Flow, '_uid')) {
$User = self::resolveTarget($Context, $Text, 'اعتبار حساب کاربری', 'کاربران و اعتبار');

if ($User === null) {
return;
}

$Target = (int)($User['Telegram_ID'] ?? 0);
Repository::updateUserSession($Context->UserId, ['Temp_UID' => $Target]);
Repository::updateUserSession($Context->UserId, ['Flow' => $Add ? 'admin:credit_add_amount' : 'admin:credit_sub_amount']);
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "👌مبلغ اعتبار به تومان برای کاربر {$Name} را وارد کنید." . Helper::adminFooter());
return;
}

$Amount = (float)Helper::toEnglish(preg_replace('/[^0-9.]/', '', $Text) ?? '0');
$Target = (int)(Repository::getUserSession($Context->UserId)['Temp_UID'] ?? 0);
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
Repository::updateUserSession($Context->UserId, ['Temp_UID' => null]);

if ($Target <= 0 || $Amount <= 0) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "❌خطا: مبلغ وارد شده معتبر نمی باشد.\n➖➖➖➖➖➖➖➖➖\n⚠️لطفا یک مبلغ صحیح به تومان وارد کنید." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'اعتبار حساب کاربری']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}

$Amount_Persian = Helper::formatCurrency($Amount);
$User = Repository::getUser($Target);
$Name = self::targetDisplayName($Target, $User);

if ($Add) {
Repository::addMoney($Target, $Amount);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *💰مبلغ {$Amount_Persian} اعتبار حساب کاربری کاربر {$Name} با موفقیت شارژ گردید.\n➖➖➖➖➖➖➖➖➖\n💳اعتبار کنونی: " . Helper::formatCurrency(Repository::getBalance($Target)) . "*" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'اعتبار حساب کاربری']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));

$User_Notify = TelegramClient::sendMessage($Target, Helper::frame('کاربر', $Name, 'اعتبار حساب کاربری', $Target) . "💳لحظاتی پیش مبلغ {$Amount_Persian} اعتبار حساب کاربری شما توسط مدیریت شارژ گردید.\n\n➖➖➖➖➖➖➖➖➖\n🌎ارز کنونی:🇮🇷ایران - تومان\n💳اعتبار کنونی:" . Helper::formatCurrency(Repository::getBalance($Target)) . Helper::userFooter(), TelegramClient::inlineKeyboard([Menu::userHome()]));

if (!($User_Notify['ok'] ?? false)) {
error_log("[Umbrella-Bot][CreditNotify] User {$Target} notification failed: " . json_encode($User_Notify));
}

return;
}

if (!Repository::removeMoney($Target, $Amount)) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *❌خطا: اعتبار حساب کاربری کاربر {$Name} برای کسر این مبلغ کافی نمی باشد.\n\n🌏ارز کنونی کاربر:🇮🇷ایران - تومان\n💳اعتبار کنونی کاربر:" . Helper::formatCurrency(Repository::getBalance($Target)) . "*" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'اعتبار حساب کاربری']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}

TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *💳مبلغ {$Amount_Persian} اعتبار حساب کاربری کاربر {$Name} با موفقیت کسر گردید. ✅" . "*" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'اعتبار حساب کاربری']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
$User_Notify = TelegramClient::sendMessage($Target, Helper::frame('کاربر', $Name, 'اعتبار حساب کاربری', $Target) . "💳لحظاتی پیش مبلغ {$Amount_Persian} اعتبار حساب کاربری شما توسط مدیریت کسر گردید.\n\n➖➖➖➖➖➖➖➖➖\n🌎ارز کنونی:🇮🇷ایران - تومان\n💳اعتبار کنونی:" . Helper::formatCurrency(Repository::getBalance($Target)) . Helper::userFooter(), TelegramClient::inlineKeyboard([Menu::userHome()]));

if (!($User_Notify['ok'] ?? false)) {
error_log("[Umbrella-Bot][CreditNotify] User {$Target} notification failed: " . json_encode($User_Notify));
}
}

private static function showCredit(Context $Context, string $Target_Input): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$User = self::resolveTarget($Context, $Target_Input);

if ($User === null) {
return;
}

$Target = (int)($User['Telegram_ID'] ?? 0);
$Balance = Helper::formatCurrency(Repository::getBalance($Target));
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *💳اعتبار حساب کاربر {$Name} بدین شرح است.\n\n🌏ارز کنونی:🇮🇷ایران - تومان\n💳اعتبار کنونی:{$Balance}" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'اعتبار حساب کاربری']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

private static function blockUser(Context $Context, string $Target_Input, bool $Block): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$User = self::resolveTarget($Context, $Target_Input, 'جرایم', 'مسدودیت کاربران');

if ($User === null) {
return;
}

$Target = (int)($User['Telegram_ID'] ?? 0);
$Is_Blocked = (bool)($User['Is_Blocked'] ?? false);

if ($Block && $Is_Blocked) {
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "⛔️*کاربر {$Name} در حال حاضر مسدود است.*\n⏳تا زمان رفع مسدودی، امکان فعالسازی کلاینت و خرید اشتراک وجود ندارد." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'جرایم']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}

if (!$Block && !$Is_Blocked) {
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "✅*کاربر {$Name} در حال حاضر مسدود نیست.*\nℹ️برای مسدود کردن او، از بخش «مسدود کردن کاربر» استفاده کنید." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'جرایم']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}

Repository::setBlocked($Target, $Block);
$Action = $Block ? 'مسدود' : 'آزاد';
$Name = self::targetDisplayName($Target, $User);
$Action_Mark = $Block ? '⛔️' : '🔓';
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *{$Action_Mark}کاربر {$Name} با موفقیت {$Action} گردید." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'جرایم']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));

TelegramClient::sendMessage($Target, Helper::frame('کاربر', $Name, 'وضعیت حساب کاربری', $Target) . ($Block ? "⛔️با عرض پوزش شما به طور دائمی مسدود شده اید.\n\n➖➖➖➖➖➖➖➖➖\n⚠️نکته:اگر فکر می کنید اشتباهی رخ داده است به پشتیبانی مراجعه کنید." . Helper::userFooter() . "*" : "✅🔓مسدودیت شما رفع گردید. خوش آمدید!") . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '📞🧑‍💻ارتباط با پشتیبانی (آرمین سافت)', 'url' => BotConfig::getSupportUrl()]],
[['text' => '🏠منوی اصلی', 'callback_data' => 'منوی خدمات ربات']],
]));
}

private static function clientIsActive(string $Client_ID, array $User): bool {
$Server_State = null;

try {
$Response = ServerClient::getUser($Client_ID);
$Json = $Response['Json'] ?? [];

if (is_array($Json) && array_key_exists('is_active', $Json)) {
$Server_State = (bool)$Json['is_active'];
}
}

catch (Throwable) {}

if ($Server_State !== null) {
return $Server_State;
}

return str_contains((string)($User['Client_Status'] ?? ''), 'فعال')
&& !str_contains((string)($User['Client_Status'] ?? ''), 'غیر');
}

private static function clientStatusStep(Context $Context, string $Target_Input, bool $Activate): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$User = self::resolveTarget($Context, $Target_Input, 'پیکربندی سرور', 'پیکربندی سرور');

if ($User === null) {
return;
}

$Target = (int)($User['Telegram_ID'] ?? 0);
Repository::updateUserSession($Context->UserId, ['Temp_UID' => $Target]);
$Client_ID = (string)($User['Client_ID'] ?? '');

if ($Client_ID === '' || $Client_ID === '_') {
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *❌خطا: شناسه کلاینت برای کاربر {$Name} ثبت نشده است.\n➖➖➖➖➖➖➖➖➖\n⚠️دلیل: این کاربر هنوز اشتراک فعالی ندارد یا کلاینت سرور برای او ایجاد نشده است." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}

$Is_Currently_Active = self::clientIsActive($Client_ID, $User);

if ($Activate && $Is_Currently_Active) {
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *⚠️کلاینت کاربر {$Name} از قبل در سرور فعال است.\n➖➖➖➖➖➖➖➖➖\nℹ️نیازی به فعالسازی مجدد نیست." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}

if (!$Activate && !$Is_Currently_Active) {
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *⚠️کلاینت کاربر {$Name} از قبل در سرور غیرفعال است.\n➖➖➖➖➖➖➖➖➖\nℹ️نیازی به غیرفعالسازی مجدد نیست." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}

$Payload = ['is_active' => $Activate, 'enable' => $Activate];
$Response = ServerClient::updateUser($Client_ID, $Payload);

if (($Response['StatusCode'] ?? 0) >= 300) {
$Error = $Response['Body'] ?? 'خطا در ارتباط با سرور';
$Name = self::targetDisplayName($Target, $User);
self::notifyAdminServerError($Activate ? 'فعالسازی کلاینت' : 'غیرفعالسازی کلاینت', $Target, $Name, $Response['StatusCode'] ?? 0, $Error);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *❌خطا: به روزرسانی کلاینت کاربر {$Name} روی سرور ناموفق بود.\n➖➖➖➖➖➖➖➖➖\n⚠️پاسخ سرور: " . mb_substr($Error, 0, 200) . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}

if ($Activate) {
Repository::updateUser($Target, ['Client_Status' => '✅فعال']);
Repository::updateUser($Target, ['Deactivation_Message' => null]);
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *✅کلاینت کاربر {$Name} در سرور فعال گردید." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));

$Full_Name = (string)($User['Full_Name'] ?? 'کاربر');
TelegramClient::sendMessage($Target, Helper::frame('کاربر', $Full_Name, 'فعالسازی کلاینت', $Target) . "✅🔓کلاینت شما در سرور فعال گردید.\n\n➖➖➖➖➖➖➖➖➖\n📋نکته: قوانین مانیتورینگ سرور را رعایت فرمایید." . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
[['text' => '💎اشتراک من', 'callback_data' => 'اشتراک من']],
Menu::userHome()
]));

$Phone = (string)(Repository::getUser($Target)['Phone'] ?? '');

if (Helper::validatePhone($Phone)) {
IppanelClient::send($Target, $Phone, "{$Full_Name} گرامی کلاینت شما در سرور فعال گردید.\nنکته:قوانین مانیتورینگ سرور را رعایت فرمایید.\n\nسرور آمبرلا");
}

return;
}

Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:deactivate_msg']);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "👌متن غیرفعالسازی کلاینت را وارد کنید." . Helper::adminFooter());
}

private static function clientDeactivateMessage(Context $Context, string $Message): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$Target = (int)(Repository::getUserSession($Context->UserId)['Temp_UID'] ?? 0);
Repository::updateUserSession($Context->UserId, ['Temp_UID' => null]);

if ($Target <= 0) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'غیرفعالسازی کلاینت') . '❌شناسه کاربر معتبر نیست؛ دوباره تلاش کنید.' . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[Menu::back('پیکربندی سرور', 'پیکربندی سرور')],
]));
return;
}

$Client_ID = (string)(Repository::getUser($Target)['Client_ID'] ?? '');

if ($Client_ID !== '' && $Client_ID !== '_') {
$Response = ServerClient::updateUser($Client_ID, ['is_active' => false, 'enable' => false]);

if (($Response['StatusCode'] ?? 0) >= 300) {
$Name = self::targetDisplayName($Target, Repository::getUser($Target));
self::notifyAdminServerError('غیرفعالسازی کلاینت', $Target, $Name, $Response['StatusCode'] ?? 0, (string)($Response['Body'] ?? ''));
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *❌خطا: غیرفعالسازی کلاینت در سرور ناموفق بود.\n➖➖➖➖➖➖➖➖➖\n⚠️پاسخ سرور: " . mb_substr((string)($Response['Body'] ?? ''), 0, 200) . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}
}

Repository::updateUser($Target, ['Client_Status' => '🚫غیر فعال']);
Repository::addSubscriptionLog($Target, 'deactivate', null, null, null, $Message, 'admin', $Context->UserId);
Repository::updateUser($Target, ['Deactivation_Message' => $Message]);
$User = Repository::getUser($Target);
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *🚫کلاینت کاربر {$Name} در سرور غیرفعال گردید." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));

$Full_Name = (string)($User['Full_Name'] ?? 'کاربر');
TelegramClient::sendMessage($Target, Helper::frame('کاربر', $Full_Name, 'غیرفعالسازی کلاینت', $Target) . "🚫کلاینت شما در سرور غیرفعال گردید.\n\n➖➖➖➖➖➖➖➖➖\n⚠️علت: {$Message}" . Helper::userFooter(), TelegramClient::inlineKeyboard([Common::backTo('💎اشتراک من', 'اشتراک من')]));
$Phone = (string)($User['Phone'] ?? '');

if (Helper::validatePhone($Phone)) {
IppanelClient::send($Target, $Phone, "{$Full_Name} گرامی کلاینت شما در سرور غیرفعال گردید.\nعلت: {$Message}\n\nسرور آمبرلا");
}
}

public static function deleteUserConfirm(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🗑در حال حذف کاربر...', false);
}

$Target = (int)(Repository::getUserSession($Context->UserId)['Temp_UID'] ?? 0);

if ($Target <= 0) {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "❌خطا: کاربری برای حذف انتخاب نشده است.\n➖➖➖➖➖➖➖➖➖\n⚠️ابتدا از بخش «حذف کاربر از سرور» شناسه عددی یا شماره موبایل کاربر را وارد کنید." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}

self::deleteUser($Context, (string)$Target);
}

private static function deleteUser(Context $Context, string $Target_Input): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$User = self::resolveTarget($Context, $Target_Input, 'پیکربندی سرور', 'پیکربندی سرور');

if ($User === null) {
return;
}

$Target = (int)($User['Telegram_ID'] ?? 0);
$Client_ID = (string)($User['Client_ID'] ?? '');
$Full_Name = (string)($User['Full_Name'] ?? '');
$Phone = (string)($User['Phone'] ?? '');
$Subscription = (string)($User['Subscription'] ?? '');

if ($Client_ID === '' || $Client_ID === '_') {
if ($Full_Name === '' && $Phone === '' && $Subscription === '') {
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, Helper::adminGreeting($Context, 'حذف کاربر از سرور') . "❌خطا: کاربر {$Name} قبلاً حذف شده است.\n➖➖➖➖➖➖➖➖➖\n⚠️این کاربر در سیستم ثبت نشده است." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}

$Name = self::targetDisplayName($Target, $User);
Repository::updateUser($Target, [
'Full_Name' => null, 'Operator' => null, 'Phone' => null, 'Client_ID' => '_',
'Package_Duration' => null, 'Package_Start_Date' => null, 'Total_Usage_GB' => null,
'Used_Usage_GB' => null, 'Remaining_Usage_GB' => null, 'Percent_Usage' => null,
'Subscription' => null, 'Expiration_Date' => null, 'Expiration_Time_Stamp' => null,
'ED_25519_Private_Key' => null, 'ED_25519_Public_Key' => null,
'WireGuard_Private_Key' => null, 'WireGuard_Public_Key' => null,
]);

TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *✅اطلاعات ربات برای کاربر {$Name} پاک شد.\n➖➖➖➖➖➖➖➖➖\n⚠️توجه: کاربر می تواند دوباره اشتراک جدید خریداری کند*" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));

$User_Notify = TelegramClient::sendMessage($Target, Helper::frame('کاربر', $Name, 'حذف اطلاعات کاربری', $Target) . "✅اطلاعات حساب کاربری شما توسط مدیریت پاک شد.\n➖➖➖➖➖➖➖➖➖\n⚠️در صورت تمایل می توانید دوباره اشتراک خریداری کنید." . Helper::userFooter(), TelegramClient::inlineKeyboard([Menu::userHome()]));

if (!($User_Notify['ok'] ?? false)) {
error_log("[Umbrella-Bot][ClearNotify] User {$Target} notification failed: " . json_encode($User_Notify));
}

return;
}

$Delete_Response = ServerClient::deleteUser($Client_ID);

if (($Delete_Response['StatusCode'] ?? 0) >= 300) {
$Delete_Error = $Delete_Response['Body'] ?? 'خطا در ارتباط با سرور';
$Name = self::targetDisplayName($Target, $User);
self::notifyAdminServerError('حذف کاربر', $Target, $Name, $Delete_Response['StatusCode'] ?? 0, $Delete_Error);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "❌خطا: حذف کاربر {$Name} از سرور ناموفق بود.\n➖➖➖➖➖➖➖➖➖\n⚠️پاسخ سرور: " . mb_substr($Delete_Error, 0, 200) . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}

Repository::updateUser($Target, [
'Full_Name' => null, 'Operator' => null, 'Phone' => null, 'Client_ID' => null,
'Package_Duration' => null, 'Package_Start_Date' => null, 'Total_Usage_GB' => null,
'Used_Usage_GB' => null, 'Remaining_Usage_GB' => null, 'Percent_Usage' => null,
'Subscription' => null, 'Expiration_Date' => null, 'Expiration_Time_Stamp' => null,
'ED_25519_Private_Key' => null, 'ED_25519_Public_Key' => null,
'WireGuard_Private_Key' => null, 'WireGuard_Public_Key' => null,
]);

$Name = self::targetDisplayName($Target, $User);
$Target_Chat_ID = (int)($User['Chat_ID'] ?? $User['Telegram_ID'] ?? 0);

if ($Target_Chat_ID > 0) {
TelegramClient::sendMessage($Target_Chat_ID,
Helper::frame('کاربر', $Name, 'حذف اشتراک', $Target) . "🚫اشتراک شما توسط مدیریت حذف گردید.\n" .
"➖➖➖➖➖➖➖➖➖\n" .
"⚠️در صورت نیاز می توانید مجدداً از طریق ربات اقدام به خرید اشتراک نمایید.\n" .
Helper::userFooter(),
TelegramClient::inlineKeyboard([
[['text' => '🏠منوی اصلی', 'callback_data' => 'منوی خدمات ربات']],
])
);
}

TelegramClient::sendMessage($Context->ChatId,
self::header($Context) .
"👤کاربر {$Name} با شناسه کلاینت {$Client_ID} با موفقیت حذف گردید." .
Helper::adminFooter(),
TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
])
);
}

private static function notifyUidStep(Context $Context, string $UidText): void {
$User = self::resolveTarget($Context, $UidText, 'منوی پیامک', 'پیامک و اطلاع رسانی');

if ($User === null) {
return;
}

$Target = (int)($User['Telegram_ID'] ?? 0);
$Session = Repository::getUserSession($Context->UserId);
$Mode = (string)($Session['Broadcast_Mode'] ?? 'both');

if (!in_array($Mode, ['telegram', 'sms', 'both'], true)) {
$Mode = 'both';
}

$Mode_Label = match ($Mode) {
'telegram' => 'تلگرام',
'both' => 'تلگرام + پیامک',
default => 'پیامک',
};

Repository::updateUserSession($Context->UserId, ['Temp_UID' => $Target, 'Flow' => 'admin:notify_text', 'Broadcast_Mode' => $Mode]);
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'اطلاع رسانی به کاربر') . "👌متن اطلاع رسانی ({$Mode_Label}) برای کاربر {$Name} را وارد کنید.\n🎯شناسه: `" . Helper::toPersian((string)$Target) . "`" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[Menu::back('اطلاع رسانی', 'اطلاع رسانی اول')],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

private static function notifyUser(Context $Context, string $Message): void {
$Session = Repository::getUserSession($Context->UserId);
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$Target = (int)($Session['Temp_UID'] ?? 0);
$Mode = (string)($Session['Broadcast_Mode'] ?? 'both');
Repository::updateUserSession($Context->UserId, ['Temp_UID' => null, 'Broadcast_Mode' => null]);

if ($Target <= 0) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'اطلاع رسانی به کاربر') . '❌شناسه کاربر معتبر نیست؛ دوباره تلاش کنید.' . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[Menu::back('اطلاع رسانی', 'اطلاع رسانی اول')],
[Menu::adminHome()],
]));
return;
}

$Full_Name = (string)(Repository::getUser($Target)['Full_Name'] ?: 'کاربر گرامی');
$Chat_ID = (int)(Repository::getUser($Target)['Chat_ID'] ?? 0);
$Phone = (string)(Repository::getUser($Target)['Phone'] ?? '');
$Sent_Tg = false;
$Sent_Sms = false;

if ($Mode === 'telegram' || $Mode === 'both') {
if ($Chat_ID > 0) {
$Result = TelegramClient::sendMessage($Chat_ID, Helper::frame('کاربر', $Full_Name, 'اطلاع رسانی', $Target) . "📣یک اطلاعیه برای شما ارسال شده است.\n\n" . "\n➖➖➖➖➖➖➖➖➖\n🔔اطلاع رسانی: {$Message}" . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '🏠منوی اصلی', 'callback_data' => 'منوی خدمات ربات']],
]));
if (($Result['ok'] ?? false) === true) $Sent_Tg = true;
}
}

if ($Mode === 'sms' || $Mode === 'both') {
if (Helper::validatePhone($Phone)) {
if (IppanelClient::send($Target, $Phone, $Message) === true) {
$Sent_Sms = true;
}
}
}

if (!$Sent_Tg && !$Sent_Sms) {
$Reasons = self::deliveryFailureReasons($Mode, $Phone, $Chat_ID, $Sent_Sms);
$Reason_Text = $Reasons === []
? '⚠️دلیل نامشخص است؛ لطفاً تنظیمات پنل پیامک و اطلاعات کاربر را بررسی کنید.'
: "⚠️دلایل:\n- " . implode("\n- ", $Reasons);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "❌اطلاع رسانی ارسال نشد.\n{$Reason_Text}" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[Menu::back('پیامک و اطلاع رسانی', 'منوی پیامک')],
]));
return;
}

$Summary = '';

if ($Sent_Tg) $Summary .= "📨تلگرام: ارسال موفق\n";
if ($Sent_Sms) $Summary .= "📱پیامک: ارسال موفق\n";

TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *✅اطلاع رسانی به کاربر {$Full_Name} ارسال گردید.*\n{$Summary}" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[Menu::back('پیامک و اطلاع رسانی', 'منوی پیامک')],
]));
}

public static function singleSmsMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Temp_UID' => null, 'Broadcast_Mode' => null]);

$Text = self::header($Context, 'ارسال پیامک تکی')
. Menu::section('📨', 'روش ارسال', [
'📨تلگرام: ارسال پیام در تلگرام کاربر',
'📱پیامک: ارسال پیامک به شماره کاربر',
'📨📱هر دو: ارسال همزمان',
])
. '📌*روش ارسال را انتخاب کنید:*' . Helper::adminFooter();
$Markup = array_merge(
Menu::rows([
[['📨تلگرام', 'ارسال پیامک تکی تلگران اول'], ['📱پیامک', 'ارسال پیامک تکی پیامک اول']],
[['📨📱هر دو', 'ارسال پیامک تکی هر دو اول']],
]),
Menu::adminNav('پیامک و اطلاع رسانی', 'منوی پیامک')
);
self::logMenuProblems('single-sms', $Markup);
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Markup));
}

/**
 * Pushes a message to the desktop app of one user, or to every device.
 *
 * The app polls `app/notifications` with its device token, so a row in
 * `App_Notifications` is what makes the message appear — the bot never has to
 * reach the device directly.
 */
public static function appPushStart(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:app_push_target', 'Temp_UID' => null]);
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, self::header($Context, 'اطلاع رسانی به برنامه')
. "👌شناسه عددی کاربر، شماره موبایل یا کلمه «همه» را بفرستید.\n"
. 'ℹ️ پیام در برنامه آمبرلا به دستگاه همان کاربر نمایش داده می‌شود.' . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[Menu::back('اطلاع رسانی سرور', 'اطلاع رسانی سرور')],
[Menu::adminHome()],
]));
}

/** Second step: the admin sends the actual text. */
public static function appPushTarget(Context $Context, string $Input): void {
if (!$Context->isAdmin()) { return; }

$Input = trim($Input);

if ($Input === 'همه' || mb_strtolower($Input) === 'all') {
Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:app_push_text', 'Temp_UID' => 0]);
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'اطلاع رسانی به برنامه')
. '📝 حالا متن پیام را بفرستید؛ برای همه دستگاه‌ها ارسال می‌شود.' . Helper::adminFooter());
return;
}

$User = Repository::findUserByIdentifier($Input);

if ($User === null) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'اطلاع رسانی به برنامه') . "❌ کاربری با این شناسه پیدا نشد." . Helper::adminFooter());
return;
}

Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:app_push_text', 'Temp_UID' => (int)$User['Telegram_ID']]);
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'اطلاع رسانی به برنامه')
. '📝 حالا متن پیام را بفرستید؛ برای دستگاه‌های کاربر ' . Helper::toPersian((string)$User['Telegram_ID']) . ' ارسال می‌شود.' . Helper::adminFooter());
}

/** Third step: stores (and queues) the message. */
public static function appPushText(Context $Context, string $Text): void {
if (!$Context->isAdmin()) { return; }

$Text = trim($Text);

if ($Text === '') return;

$Session = Repository::getUserSession($Context->UserId);
$Target = (int)($Session['Temp_UID'] ?? 0);
$Count = self::queueAppPush($Target, $Text, (int)$Context->UserId);

Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Temp_UID' => null]);
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'اطلاع رسانی به برنامه')
. '✅ پیام ثبت شد و تا ' . Helper::toPersian((string)$Count) . ' دستگاه تحویل داده می‌شود.' . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

/**
 * Writes the notification rows and returns how many devices it targets.
 *
 * Rows are always per device: `Delivered_At` is stamped when a device picks
 * its own message up, so a shared row (Device_ID NULL) would vanish for every
 * later device after the first one polled it.
 */
public static function queueAppPush(int $Target_Telegram_ID, string $Text, int $Admin_ID): int {
$Database = \Database::getInstance();
$Title = mb_substr($Text, 0, 60);
$Body = $Text;

if ($Target_Telegram_ID > 0) {
$Rows = $Database->fetchAll('SELECT `Device_ID` FROM `App_Devices` WHERE `Telegram_ID` = ? AND `Is_Trusted` = 1', [$Target_Telegram_ID]);

if ($Rows === []) {
// The user has no app device yet: park the message against their panel
// account uuid — it is delivered as soon as one appears, instead of a
// NULL/NULL row nobody can match.
$Client_Row = $Database->fetch('SELECT `Client_ID` FROM `Users` WHERE `Telegram_ID` = ? LIMIT 1', [$Target_Telegram_ID]);
$Client_ID = trim((string)($Client_Row['Client_ID'] ?? ''));

if ($Client_ID !== '') {
$Database->execute('INSERT INTO `App_Notifications` (`User_UUID`, `Device_ID`, `Title`, `Body`, `Level`) VALUES (?, NULL, ?, ?, ?)', [$Client_ID, $Title, $Body, 'info']);
Repository::logAdminAction($Admin_ID, 'app_push_user_deferred', $Target_Telegram_ID, null);
return 1;
}

// Unknown uuid: broadcast to the installed base rather than drop it.
$Database->execute('INSERT INTO `App_Notifications` (`Device_ID`, `Title`, `Body`, `Level`) SELECT `Device_ID`, ?, ?, \'info\' FROM `App_Devices` WHERE `Is_Trusted` = 1', [$Title, $Body]);
Repository::logAdminAction($Admin_ID, 'app_push_broadcast_fallback', $Target_Telegram_ID, null);
return (int)$Database->scalar('SELECT COUNT(*) FROM `App_Devices` WHERE `Is_Trusted` = 1');
}

foreach ($Rows as $Row) {
$Database->execute('INSERT INTO `App_Notifications` (`User_UUID`, `Device_ID`, `Title`, `Body`, `Level`) VALUES (NULL, ?, ?, ?, ?)', [(string)$Row['Device_ID'], $Title, $Body, 'info']);
}

Repository::logAdminAction($Admin_ID, 'app_push_user', $Target_Telegram_ID, mb_substr($Text, 0, 120));
return count($Rows);
}

$Database->execute('INSERT INTO `App_Notifications` (`Device_ID`, `Title`, `Body`, `Level`) SELECT `Device_ID`, ?, ?, \'notice\' FROM `App_Devices` WHERE `Is_Trusted` = 1', [$Title, $Body]);
Repository::logAdminAction($Admin_ID, 'app_push_all_devices', null, mb_substr($Text, 0, 120));
return (int)$Database->scalar('SELECT COUNT(*) FROM `App_Devices` WHERE `Is_Trusted` = 1');
}

/** «📣تلگرام + برنامه همزمان» — one text, Telegram and the app. */
public static function notifyAllStart(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:notify_all_text', 'Temp_UID' => null]);

TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, self::header($Context, 'اطلاع به تلگرام و برنامه')
. "📣*پیام همزمان آماده ارسال است.*\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "👌متن دلخواه خود را در یک پیام بفرستید.\n"
. "📤این متن برای همهٔ کاربران ربات (تلگرام) و همهٔ دستگاه‌های برنامهٔ «آمبرلا» به‌عنوان اعلان برنامه ارسال می‌شود." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[Menu::back('اطلاع رسانی سرور', 'اطلاع رسانی سرور')],
[Menu::adminHome()],
]));
}

/** Sends one message to every Telegram user and every trusted app device. */
public static function broadcastTelegramAndApp(Context $Context, string $Text): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$Text = trim($Text);

if ($Text === '') {
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'اطلاع به تلگرام و برنامه') . "❌متن ارسالی خالی است؛ لطفاً متنی وارد کنید." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔄تلاش دوباره', 'callback_data' => 'notify_all_start']],
[Menu::back('اطلاع رسانی سرور', 'اطلاع رسانی سرور')],
]));
return;
}

$Sent_Tg = 0;
$Failed_Tg = 0;
$Rows = Database::getInstance()->fetchAll("SELECT `Telegram_ID`, `Chat_ID`, `Phone`, `Full_Name` FROM `Users` WHERE `Is_Blocked` = 0 ORDER BY `Telegram_ID` ASC");

if (!is_array($Rows)) $Rows = [];

foreach ($Rows as $Row) {
$User_ID = (int)($Row['Telegram_ID'] ?? 0);
$Chat_ID = (int)($Row['Chat_ID'] ?? 0);
$Name = trim((string)($Row['Full_Name'] ?? ''));

if ($Name === '') $Name = 'کاربر';
if ($User_ID <= 0) continue;
if ($Chat_ID > 0) {
try {
$Result = TelegramClient::sendMessage($Chat_ID, Helper::frame('کاربر', $Name, 'اطلاع رسانی', $User_ID) . "📣پیام اطلاع‌رسانی سرور آمبرلا:\n\n{$Text}" . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '🏠منوی اصلی', 'callback_data' => 'منوی خدمات ربات']],
]));

if (($Result['ok'] ?? false) === true) {
$Sent_Tg++;
}
else {
$Failed_Tg++;
}
}

catch (Throwable) {
$Failed_Tg++;
}
}
}

$Devices = self::queueAppPush(0, $Text, (int)$Context->UserId);
$Summary = "✅ارسال موفق تلگرام: " . Helper::toPersian($Sent_Tg) . " نفر\n"
. "⛔️ارسال ناموفق تلگرام: " . Helper::toPersian($Failed_Tg) . " نفر\n"
. "📱دستگاه‌های برنامه که این اعلان را دریافت می‌کنند: " . Helper::toPersian($Devices) . " دستگاه\n"
. "👥تعداد کل مخاطبین تلگرام: " . Helper::toPersian((string)count($Rows)) . " نفر";

$Markup = array_merge(
Menu::rows([
[['🔄ارسال پیام دیگر', 'notify_all_start']],
]),
Menu::adminNav('اطلاع رسانی سرور', 'اطلاع رسانی سرور')
);
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'اطلاع به تلگرام و برنامه') . "📣ارسال همزمان انجام شد.\n{$Summary}" . Helper::adminFooter(), TelegramClient::inlineKeyboard($Markup));
}

/** «📱مجوز دستگاه کاربران» — ask which account. */
public static function deviceLimitMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:device_limit_target', 'Temp_UID' => null]);

$Text = self::header($Context, 'مجوز دستگاه کاربران')
. Menu::section('📱', 'چند دستگاه برای هر کاربر مجاز باشد؟', [
'👌شناسه عددی تلگرام یا شماره موبایل کاربر را بفرستید.',
'ℹ️به صورت پیش فرض هر کاربر فقط روی یک دستگاه فعال است.',
])
. '👇شناسه را همین حالا بفرستید:' . Helper::adminFooter();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard(Menu::adminNav('منوی مدیریت', Menu::ADMIN_HOME_CALL)));
}

/** Second step: show the current state and let the admin pick the new cap. */
public static function deviceLimitTarget(Context $Context, string $Input): void {
if (!$Context->isAdmin()) { return; }

$User = Repository::findUserByIdentifier($Input);

if ($User === null) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'مجوز دستگاه کاربران') . "❌ کاربری با این شناسه پیدا نشد." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[Menu::back('مجوز دستگاه', 'device_limit_menu')],
[Menu::adminHome()],
]));
return;
}

$Telegram_Id = (int)$User['Telegram_ID'];
$Phone = trim((string)$User['Phone']);
$Limit = AppDeviceLimit::maxDevices($Telegram_Id);
$Devices = AppDeviceLimit::trustedDevices($Phone, $Telegram_Id);
$Device_Lines = '';
$Index = 0;

foreach ($Devices as $Row) {
$Index++;
$Name = trim((string)($Row['Device_Name'] ?? '')) ?: 'دستگاه نامشخص';
$Seen = (int)($Row['Last_Seen_At'] ?? 0);
$When = $Seen > 0 ? gmdate('Y-m-d H:i', $Seen) : '—';
$Device_Lines .= "├─📱" . Helper::toPersian((string)$Index) . ". {$Name} · 🕓آخرین استفاده: {$When}\n";
}

if ($Device_Lines === '') {
$Device_Lines = "└─⭕️در حال حاضر دستگاه فعالی ثبت نشده است.\n";
}

$Name = trim((string)($User['Full_Name'] ?? '')) ?: '—';
$Text = self::header($Context, 'مجوز دستگاه کاربران')
. Menu::section('📱', 'کاربر انتخاب شده', [
'👤نام: ' . $Name,
'🆔شناسه: ' . Helper::toPersian((string)$Telegram_Id),
'📞شماره: ' . $Phone,
'🔐مجوز فعلی: ' . Helper::toPersian((string)$Limit) . ' دستگاه',
])
. "\n📲*دستگاه های فعال:*\n" . $Device_Lines
. "👇چند دستگاه برای این حساب مجاز باشد؟";

Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:device_limit_pick', 'Temp_UID' => $Telegram_Id]);

TelegramClient::sendMessage($Context->ChatId, $Text . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[
['text' => '1️⃣یک دستگاه', 'callback_data' => 'device_limit_set_1'],
['text' => '2️⃣دو دستگاه', 'callback_data' => 'device_limit_set_2'],
],
[
['text' => '3️⃣سه دستگاه', 'callback_data' => 'device_limit_set_3'],
['text' => '5️⃣پنج دستگاه', 'callback_data' => 'device_limit_set_5'],
],
[
['text' => '🔟ده دستگاه', 'callback_data' => 'device_limit_set_10'],
],
[Menu::back('مجوز دستگاه', 'device_limit_menu')],
]));
}

/** دومین گام، وقتی مدیر تعداد را تایپ می کند (به جای انتخاب از دکمه ها). */
private static function deviceLimitPickInput(Context $Context, string $Text): void {
$Session = Repository::getUserSession($Context->UserId);
$Telegram_Id = (int)($Session['Temp_UID'] ?? 0);
$Number = trim(Helper::toEnglish($Text));

if ($Telegram_Id <= 0) {
self::deviceLimitMenu($Context);
return;
}

// «لغو» و هر ورودی نامعتبر: همان صفحه با دکمه ها دوباره نمایش داده می شود.
if (!preg_match('/^\d{1,2}$/', $Number) || (int)$Number < 1) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'مجوز دستگاه کاربران') . "⚠️فقط یک عدد بین ۱ تا ۹۹ مجاز است؛ یکی از دکمه های زیر را انتخاب کنید یا عدد را دوباره بفرستید." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[
['text' => '1️⃣یک دستگاه', 'callback_data' => 'device_limit_set_1'],
['text' => '2️⃣دو دستگاه', 'callback_data' => 'device_limit_set_2'],
],
[
['text' => '3️⃣سه دستگاه', 'callback_data' => 'device_limit_set_3'],
['text' => '5️⃣پنج دستگاه', 'callback_data' => 'device_limit_set_5'],
],
[
['text' => '🔟ده دستگاه', 'callback_data' => 'device_limit_set_10'],
],
[Menu::back('مجوز دستگاه', 'device_limit_menu'), Menu::userHome()[0]],
]));
return;
}

self::deviceLimitSet($Context, min(99, (int)$Number));
}

/** Third step: persist the choice. */
public static function deviceLimitSet(Context $Context, int $Max): void {
if (!$Context->isAdmin()) { return; }

if ($Context->CallbackId !== null) {
try { TelegramClient::answerCallbackQuery($Context->CallbackId); } catch (Throwable) {}
}

$Session = Repository::getUserSession($Context->UserId);
$Telegram_Id = (int)($Session['Temp_UID'] ?? 0);

if ($Telegram_Id <= 0) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'مجوز دستگاه کاربران') . "⌛️این عملیات منقضی شده است؛ دوباره از منو شروع کنید." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '📱مجوز دستگاه کاربران', 'callback_data' => 'device_limit_menu']],
]));
return;
}

$Max = AppDeviceLimit::setMaxDevices($Telegram_Id, $Max);
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Temp_UID' => null]);
Repository::logAdminAction((int)$Context->UserId, 'device_limit_set', $Telegram_Id, 'max=' . $Max);

TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'مجوز دستگاه کاربران')
. "✅*انجام شد.*\n📱از این به بعد کاربر " . Helper::toPersian((string)$Telegram_Id) . " می‌تواند روی *" . Helper::toPersian((string)$Max) . " دستگاه* به‌طور همزمان فعال باشد." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '📱مجوز دیگری', 'callback_data' => 'device_limit_menu']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

public static function notifySingleMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Temp_UID' => null, 'Broadcast_Mode' => null]);

TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, self::header($Context, 'اطلاع رسانی به کاربر') . '📨لطفاً روش ارسال را انتخاب کنید:*' . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '📨ارسال از تلگرام', 'callback_data' => 'اطلاع رسانی تلگران اول']],
[['text' => '📱ارسال از پیامک', 'callback_data' => 'اطلاع رسانی پیامک اول']],
[['text' => '📨📱ارسال از هر دو', 'callback_data' => 'اطلاع رسانی هر دو اول']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

public static function startInputSingleSmsUid(Context $Context, string $Mode): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:sms_single_uid', 'Broadcast_Mode' => $Mode, 'Temp_UID' => null]);
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, self::header($Context, 'ارسال پیامک تکی') . '👌شناسه عددی یا شماره موبایل کاربر مورد نظر را وارد کنید.' . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[Menu::back('پیامک تکی', 'ارسال پیامک تکی اول')],
[Menu::adminHome()],
]));
}

public static function startInputNotifyUid(Context $Context, string $Mode): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:notify_uid', 'Broadcast_Mode' => $Mode, 'Temp_UID' => null]);
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, self::header($Context, 'اطلاع رسانی به کاربر') . '👌شناسه عددی یا شماره موبایل کاربر مورد نظر را وارد کنید.' . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[Menu::back('اطلاع رسانی', 'اطلاع رسانی اول')],
[Menu::adminHome()],
]));
}

public static function broadcastMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Temp_UID' => null, 'Broadcast_Mode' => null]);
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, Helper::adminGreeting($Context, 'ارسال پیامک همگانی') . '📨لطفاً روش ارسال را انتخاب کنید:*' . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '📨ارسال از تلگرام', 'callback_data' => 'ارسال پیامک همگانی تلگرام اول']],
[['text' => '📱ارسال از پیامک', 'callback_data' => 'ارسال پیامک همگانی پیامک اول']],
[['text' => '📨📱ارسال از هر دو', 'callback_data' => 'ارسال پیامک همگانی هر دو اول']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

private static function broadcastNotify(Context $Context, string $Message, string $Mode = 'telegram'): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$Message = trim($Message);

if ($Message === '') {
TelegramClient::sendMessage($Context->ChatId, Helper::adminGreeting($Context, 'اطلاع رسانی همگانی') . "❌متن ارسالی خالی است؛ لطفاً متنی وارد کنید." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔄تلاش دوباره', 'callback_data' => 'اطلاع رسانی سفارشی اول']],
[['text' => '🔙بازگشت', 'callback_data' => 'منوی پیامک']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}

if (!in_array($Mode, ['telegram', 'sms', 'both'], true)) {
$Mode = 'both';
}

$Sent_Tg = 0;
$Sent_Sms = 0;
$Failed_Sms = 0;
$Failed_Tg = 0;
$Rows = Database::getInstance()->fetchAll("SELECT `Telegram_ID`, `Chat_ID`, `Phone`, `Full_Name` FROM `Users` WHERE `Is_Blocked` = 0 ORDER BY `Telegram_ID` ASC");

if (!is_array($Rows)) $Rows = [];

foreach ($Rows as $Row) {
$User_ID = (int)($Row['Telegram_ID'] ?? 0);
$Chat_ID = (int)($Row['Chat_ID'] ?? 0);
$Phone = trim((string)($Row['Phone'] ?? ''));
$Name = trim((string)($Row['Full_Name'] ?? ''));

if ($Name === '') $Name = 'کاربر';
if ($User_ID <= 0) continue;
if ($Mode === 'telegram' || $Mode === 'both') {
if ($Chat_ID > 0) {
try {
$Result = TelegramClient::sendMessage($Chat_ID, Helper::frame('کاربر', $Name, 'اطلاع رسانی همگانی', $User_ID) . "📨پیام همگانی سرور آمبرلا:\n\n{$Message}" . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '🏠منوی اصلی', 'callback_data' => 'منوی خدمات ربات']],
]));

if (($Result['ok'] ?? false) === true) {
$Sent_Tg++;
}
else {
$Failed_Tg++;
}
}

catch (Throwable) {
$Failed_Tg++;
}
}
}

if ($Mode === 'sms' || $Mode === 'both') {
if (Helper::validatePhone($Phone)) {
try {
if (IppanelClient::send($User_ID, $Phone, $Message) === true) {
$Sent_Sms++;
}

else {
$Failed_Sms++;
}
}

catch (Throwable) {
$Failed_Sms++;
}
}

else {
$Failed_Sms++;
}
}
}

$Summary = '';

if ($Mode === 'telegram') {
$Summary = "✅ارسال موفق تلگرام: " . Helper::toPersian($Sent_Tg) . " نفر\n⛔️ارسال ناموفق تلگرام: " . Helper::toPersian($Failed_Tg) . " نفر";
}

elseif ($Mode === 'sms') {
$Summary = "✅ارسال موفق پیامک: " . Helper::toPersian($Sent_Sms) . " پیامک\n⛔️ارسال ناموفق پیامک: " . Helper::toPersian($Failed_Sms) . " پیامک";
}

else {
$Summary = "✅ارسال موفق تلگرام: " . Helper::toPersian($Sent_Tg) . " نفر\n"
. "⛔️ارسال ناموفق تلگرام: " . Helper::toPersian($Failed_Tg) . " نفر\n"
. "✅ارسال موفق پیامک: " . Helper::toPersian($Sent_Sms) . " پیامک\n"
. "⛔️ارسال ناموفق پیامک: " . Helper::toPersian($Failed_Sms) . " پیامک";
}

$Summary .= "\n👥تعداد کل مخاطبین: " . Helper::toPersian((string)count($Rows)) . " نفر";

if (($Mode === 'sms' || $Mode === 'both') && trim((string)Environment::getSmsApiKey()) === '') {
$Summary .= "\n⚠️کلید سرویس پیامک در تنظیمات ثبت نشده است؛ پیامک‌ها ارسال نشدند.";
}

TelegramClient::sendMessage($Context->ChatId, Helper::adminGreeting($Context, 'اطلاع رسانی سفارشی') . "📨ارسال انجام شد.\n{$Summary}" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔄ارسال پیام دیگر', 'callback_data' => 'اطلاع رسانی سفارشی اول']],
[['text' => '🔙بازگشت', 'callback_data' => 'منوی پیامک']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

private static function singleSmsStep(Context $Context, string $UidText): void {
$User = self::resolveTarget($Context, $UidText, 'ارسال پیامک تکی اول', 'پیامک تکی');

if ($User === null) {
return;
}

$Target = (int)($User['Telegram_ID'] ?? 0);
$Session = Repository::getUserSession($Context->UserId);
$Mode = (string)($Session['Broadcast_Mode'] ?? 'sms');

if (!in_array($Mode, ['telegram', 'sms', 'both'], true)) {
$Mode = 'sms';
}

$Mode_Label = match ($Mode) {
'telegram' => 'تلگرام',
'both' => 'تلگرام + پیامک',
default => 'پیامک',
};

Repository::updateUserSession($Context->UserId, ['Temp_UID' => $Target, 'Flow' => 'admin:sms_single_text', 'Broadcast_Mode' => $Mode]);
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'ارسال پیامک تکی') . "👌متن پیامک تکی ({$Mode_Label}) برای کاربر {$Name} را وارد کنید.\n🎯شناسه: `" . Helper::toPersian((string)$Target) . "`" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[Menu::back('پیامک تکی', 'ارسال پیامک تکی اول')],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

private static function singleSmsModeRetry(Context $Context): void {
$Session = Repository::getUserSession($Context->UserId);
$Target = (int)($Session['Temp_UID'] ?? 0);

if ($Target <= 0) {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "⚠️ابتدا شناسه عددی یا شماره موبایل کاربر را وارد کنید." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '📨ارسال پیامک تکی', 'callback_data' => 'ارسال پیامک تکی اول']],
[Menu::back('پیامک و اطلاع رسانی', 'منوی پیامک')],
[Menu::adminHome()],
]));
return;
}

$Name = self::targetDisplayName($Target, Repository::getUser($Target));
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "⚠️لطفاً حالت ارسال را از دکمه های زیر انتخاب کنید (متن به صورت پیام ارسال نشود).\n👤کاربر: {$Name}" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '📨از تلگرام', 'callback_data' => 'ارسال پیامک تکی تلگران اول'], ['text' => '📱از پیامک', 'callback_data' => 'ارسال پیامک تکی پیامک اول']],
[['text' => '📨📱از هر دو', 'callback_data' => 'ارسال پیامک تکی هر دو اول']],
[Menu::back('پیامک و اطلاع رسانی', 'منوی پیامک')],
]));
}

private static function notifyModeRetry(Context $Context): void {
$Session = Repository::getUserSession($Context->UserId);
$Target = (int)($Session['Temp_UID'] ?? 0);

if ($Target <= 0) {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "⚠️ابتدا شناسه عددی یا شماره موبایل کاربر را وارد کنید." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🗣اطلاع رسانی به کاربر', 'callback_data' => 'اطلاع رسانی اول']],
[Menu::back('پیامک و اطلاع رسانی', 'منوی پیامک')],
[Menu::adminHome()],
]));
return;
}

$Name = self::targetDisplayName($Target, Repository::getUser($Target));
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "⚠️لطفاً حالت اطلاع رسانی را از دکمه های زیر انتخاب کنید (متن به صورت پیام ارسال نشود).\n👤کاربر: {$Name}" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '📨از تلگرام', 'callback_data' => 'اطلاع رسانی تلگران اول'], ['text' => '📱از پیامک', 'callback_data' => 'اطلاع رسانی پیامک اول']],
[['text' => '📨📱از هر دو', 'callback_data' => 'اطلاع رسانی هر دو اول']],
[Menu::back('پیامک و اطلاع رسانی', 'منوی پیامک')],
]));
}

private static function deliveryFailureReasons(string $Mode, string $Phone, int $Chat_ID, bool $Sent_Sms): array {
$Reasons = [];

if (($Mode === 'telegram' || $Mode === 'both') && $Chat_ID <= 0) {
$Reasons[] = '📨تلگرام: کاربر ربات را استارت نکرده است.';
}

if ($Mode === 'sms' || $Mode === 'both') {
if (!Helper::validatePhone($Phone)) {
$Reasons[] = '📱پیامک: شماره موبایل کاربر در پروفایل ثبت نشده یا نامعتبر است.';
}

elseif (trim((string)Environment::getSmsApiKey()) === '') {
$Reasons[] = '📱پیامک: کلید سرویس پیامک در تنظیمات ثبت نشده است.';
}

elseif (trim((string)Environment::getSmsSender()) === '') {
$Reasons[] = '📱پیامک: شماره فرستنده پیامک در تنظیمات ثبت نشده است.';
}

elseif (!$Sent_Sms) {
$Reasons[] = '📱پیامک: درگاه پیامک ارسال را نپذیرفت (اعتبار پنل و شماره فرستنده را بررسی کنید).';
}
}

return $Reasons;
}

private static function singleSmsSend(Context $Context, string $Message): void {
$Session = Repository::getUserSession($Context->UserId);
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$Target = (int)($Session['Temp_UID'] ?? 0);
$Mode = (string)($Session['Broadcast_Mode'] ?? 'sms');
Repository::updateUserSession($Context->UserId, ['Temp_UID' => null, 'Broadcast_Mode' => null]);

if ($Target <= 0) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'ارسال پیامک تکی') . '❌شناسه کاربر معتبر نیست؛ دوباره تلاش کنید.' . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[Menu::back('پیامک تکی', 'ارسال پیامک تکی اول')],
[Menu::adminHome()],
]));
return;
}

$User = Repository::getUser($Target);
$Phone = (string)($User['Phone'] ?? '');
$Chat_ID = (int)($User['Chat_ID'] ?? 0);
$Full_Name = trim((string)($User['Full_Name'] ?? ''));
$Display_Name = $Full_Name !== '' ? $Full_Name : 'کاربر';
$Sent_Tg = false;
$Sent_Sms = false;

if ($Mode === 'telegram' || $Mode === 'both') {
if ($Chat_ID > 0) {
$Result = TelegramClient::sendMessage($Chat_ID, Helper::frame('کاربر', $Display_Name, 'اطلاع رسانی', $Target) . "📨یک پیامک ارسال شده است.\n\n" . "\n➖➖➖➖➖➖➖➖➖\n🔔پیامک: {$Message}" . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '🏠منوی اصلی', 'callback_data' => 'منوی خدمات ربات']],
]));

if (($Result['ok'] ?? false) === true) $Sent_Tg = true;
}
}

if ($Mode === 'sms' || $Mode === 'both') {
if (Helper::validatePhone($Phone)) {
if (IppanelClient::send($Target, $Phone, $Message) === true) {
$Sent_Sms = true;
}
}
}

if (!$Sent_Tg && !$Sent_Sms) {
$Reasons = self::deliveryFailureReasons($Mode, $Phone, $Chat_ID, $Sent_Sms);
$Reason_Text = $Reasons === []
? '⚠️دلیل نامشخص است؛ لطفاً تنظیمات پنل پیامک و اطلاعات کاربر را بررسی کنید.'
: "⚠️دلایل:\n- " . implode("\n- ", $Reasons);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "❌ارسال انجام نشد.\n{$Reason_Text}" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[Menu::back('پیامک و اطلاع رسانی', 'منوی پیامک')],
]));
return;
}

$Summary = '';

if ($Sent_Tg) $Summary .= "📨تلگرام: ارسال موفق\n";
if ($Sent_Sms) $Summary .= "📱پیامک: ارسال موفق\n";

TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *✅پیامک تکی برای کاربر {$Display_Name} ارسال گردید.*\n{$Summary}" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[Menu::back('پیامک و اطلاع رسانی', 'منوی پیامک')],
]));
}

private static function manualExpire(Context $Context, string $Target_Input): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$User = self::resolveTarget($Context, $Target_Input, 'پیکربندی سرور', 'پیکربندی سرور');

if ($User === null) {
return;
}

$Target = (int)($User['Telegram_ID'] ?? 0);
$Subscription = (string)($User['Subscription'] ?? '');

if ($Subscription === '') {
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *❌خطا: اشتراک فعالی برای کاربر {$Name} ثبت نشده است.\n➖➖➖➖➖➖➖➖➖\n⚠️دلیل: این کاربر در حال حاضر اشتراک فعالی ندارد." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}

$Client_ID = (string)(Repository::getUser($Target)['Client_ID'] ?? '');

if ($Client_ID !== '' && $Client_ID !== '_') {
$Response = ServerClient::updateUser($Client_ID, ['is_active' => false, 'enable' => false]);

if (($Response['StatusCode'] ?? 0) >= 300) {
$Name = self::targetDisplayName($Target, Repository::getUser($Target));
self::notifyAdminServerError('غیرفعالسازی کلاینت', $Target, $Name, $Response['StatusCode'] ?? 0, (string)($Response['Body'] ?? ''));
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *❌خطا: غیرفعالسازی کلاینت در سرور ناموفق بود.\n➖➖➖➖➖➖➖➖➖\n⚠️پاسخ سرور: " . mb_substr((string)($Response['Body'] ?? ''), 0, 200) . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}
}

Repository::updateUser($Target, ['Client_Status' => '🚫غیر فعال']);
Repository::updateUser($Target, [
'Package_Duration' => null, 'Package_Start_Date' => null, 'Total_Usage_GB' => null,
'Used_Usage_GB' => null, 'Remaining_Usage_GB' => null, 'Percent_Usage' => null,
'Subscription' => null, 'Expiration_Date' => null, 'Expiration_Time_Stamp' => null,
]);

Repository::addSubscriptionLog($Target, 'expire', $Subscription, null, null, 'انقضای دستی توسط مدیریت', 'admin', $Context->UserId);

$User = Repository::getUser($Target);
$Phone = (string)($User['Phone'] ?? '');
$Full_Name = (string)($User['Full_Name'] ?? 'کاربر');
$Chat_ID = (int)($User['Chat_ID'] ?? 0);

if ($Chat_ID > 0) {
TelegramClient::sendMessage($Chat_ID, Helper::frame('کاربر', $Full_Name, 'انقضای اشتراک', $Target) . "🌹اشتراک {$Subscription} شما منقضی گردید.\n\n⚠️اتصال شما از سرور قطع گردید." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '💎تمدید اشتراک', 'callback_data' => 'اشتراک من']],
Menu::userHome(),
]));
}

if (Helper::validatePhone($Phone)) {
$Plan = Helper::smsPlan((string)($Subscription ?? ''));
$Template = Repository::getSmsTemplate('expired');
$Sms_Text = $Template !== null
? strtr($Template, ['{full_name}' => $Full_Name, '{plan}' => $Plan])
: "{$Full_Name} گرامی ⏰اشتراک {$Plan} شما به اتمام رسید.\n🔌اتصال شما از سرور قطع گردید.\n\nسرور آمبرلا";
IppanelClient::send($Target, $Phone, $Sms_Text);
}

$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *⏰اشتراک کاربر {$Name} منقضی گردید.\n➖➖➖➖➖➖➖➖➖\n⚠️وضعیت: کلاینت در سرور غیرفعال شد و اطلاعات کاربری محفوظ ماند." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

public static function updateAllUsages(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🔄بروز رسانی میزان استفاده کاربران در حال بار گذاری می باشد...', false);
}

$Update_Response = ServerClient::updateUserUsage();
$Update_Json = $Update_Response['Json'] ?? null;
$Synced = 0;

if (!is_array($Update_Json) || ($Update_Response['StatusCode'] ?? 0) >= 300 || (string)($Update_Json['status'] ?? 'success') !== 'success') {
self::notifyAdminServerError('بروزرسانی مصرف سرور', $Context->UserId, (string)$Context->profileName(), $Update_Response['StatusCode'] ?? 0, (string)($Update_Response['Body'] ?? ''));
$Error_Text = self::header($Context) . " *❌خطا: بروز رسانی میزان استفاده در سرور ناموفق بود.\n➖➖➖➖➖➖➖➖➖\n⚠️پاسخ سرور: " . mb_substr((string)($Update_Response['Body'] ?? ''), 0, 200) . Helper::adminFooter();

if ($Context->MessageId !== null) {
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Error_Text, TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

else {
TelegramClient::sendMessage($Context->ChatId, $Error_Text, TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

return;
}

$Synced = (int)Scheduler::refreshUsagesNow();

if ($Synced <= 0) {
$Sync_Error = self::header($Context) . " *⚠️بروزرسانی مصرف در سرور انجام شد اما دریافت فهرست کاربران از سرور ناموفق بود.\n➖➖➖➖➖➖➖➖➖\n🔄لطفا چند لحظه دیگر دوباره تلاش کنید." . Helper::adminFooter();

if ($Context->MessageId !== null) {
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Sync_Error, TelegramClient::inlineKeyboard([
[['text' => '🔁بروز رسانی مجدد', 'callback_data' => 'بروز رسانی میزان استفاده اول']],
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

else {
TelegramClient::sendMessage($Context->ChatId, $Sync_Error, TelegramClient::inlineKeyboard([
[['text' => '🔁بروز رسانی مجدد', 'callback_data' => 'بروز رسانی میزان استفاده اول']],
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

return;
}

$Total_Usage_GB = (float)Database::getInstance()->scalar('SELECT COALESCE(SUM(`Used_Usage_GB`), 0) FROM `Users` WHERE `Client_ID` IS NOT NULL AND `Client_ID` != ""');
$Total_Usage_Human = Helper::formatBytes((int)($Total_Usage_GB * 1024 * 1024 * 1024));

try {
Repository::updateUsageSnapshotValues();
}

catch (Throwable) {}
$Success_Text = Helper::adminGreeting($Context, 'میزان استفاده کاربران') . '✅بروز رسانی میزان استفاده کاربران از سرور با موفقیت انجام شد.' . "\n👥تعداد بروز رسانی شده: `" . Helper::toPersian((string)$Synced) . "` کاربر\n📊مجموع مصرف: `" . $Total_Usage_Human . "`\n\n" . Helper::adminFooter();

if ($Context->MessageId !== null) {
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Success_Text, TelegramClient::inlineKeyboard([
[['text' => '🔁بروز رسانی مجدد', 'callback_data' => 'بروز رسانی میزان استفاده اول']],
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

else {
TelegramClient::sendMessage($Context->ChatId, $Success_Text, TelegramClient::inlineKeyboard([
[['text' => '🔁بروز رسانی مجدد', 'callback_data' => 'بروز رسانی میزان استفاده اول']],
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}
}

public static function askUpdateUserData(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🔄در حال بارگذاری...', false);
}

Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:update_uid']);
$Text = Helper::adminGreeting($Context, 'بروز رسانی داده های کاربران') . '👌فرمت ورودی (تک یا گروهی — بدون محدودیت):' . "\n\n`شناسه کاربر`\n`شناسه کلاینت`\n\nنمونه تک:\n`6248742705`\n`970f3fa0-3714-4d9a-a95d-8c4ddd696bfd`\n\nنمونه گروهی:\n`شناسه کاربر`\n`شناسه کلاینت`\n`شناسه کاربر`\n`شناسه کلاینت`\n`شناسه کاربر`\n`شناسه کلاینت`\n\n⚠️نکته: هر شناسه کاربر با نزدیک‌ترین شناسه کلاینت جفت می‌شود. ترتیب مهم نیست و تعداد جفت‌ها محدودیتی ندارد.\n📱به جای شناسه کاربر می‌توانید شماره موبایل کاربر را نیز وارد کنید." . Helper::adminFooter();

if ($Context->MessageId !== null) {
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

else {
TelegramClient::sendMessage($Context->ChatId, $Text, TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}
}

private static function refreshUserData(Context $Context, string $Identifier): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$Raw = (string)preg_replace('/\r\n?/', "\n", trim($Identifier));
$Raw = Helper::toEnglish($Raw);
$Lines = array_values(array_filter(array_map('trim', explode("\n", $Raw)), static fn($L) => $L !== ''));
$Uuid_Regex = '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i';
$Pending_Num = null;
$Pending_Uuid = null;
$Pairs = [];

foreach ($Lines as $Line) {
if ((bool)preg_match($Uuid_Regex, $Line)) {
if ($Pending_Num !== null) {
$Pairs[] = [$Pending_Num, strtolower($Line)];
$Pending_Num = null;
}

else {
$Pending_Uuid = strtolower($Line);
}

continue;
}

if ($Pending_Uuid !== null) {
$Pairs[] = [$Line, $Pending_Uuid];
$Pending_Uuid = null;
}

else {
$Pending_Num = $Line;
}
}

if ($Pairs === []) {
$Error_Text = self::header($Context) . " *❌خطا: فرمت وارد شده صحیح نمی باشد.\n➖➖➖➖➖➖➖➖➖\n⚠️لطفا شناسه کاربر و شناسه کلاینت را (تک یا گروهی) وارد کنید:\n\n`شناسه کاربر`\n`شناسه کلاینت`\n\nنمونه گروهی:\n`6248742705`\n`970f3fa0-3714-4d9a-a95d-8c4ddd696bfd`\n`123456789`\n`0d2585be-89a1-4a42-9d5e-2c9a4fcb51aa`" . Helper::adminFooter();
TelegramClient::sendMessage($Context->ChatId, $Error_Text, TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🔄در حال دریافت اطلاعات از سرور...', false);
}

$Loading_Text = self::header($Context) . " *🔄در حال دریافت اطلاعات از سرور آمبرلا (" . Helper::toPersian((string)count($Pairs)) . " کاربر)...\n➖➖➖➖➖➖➖➖➖\n⚠️نکته:این عملیات ممکن است کمی طول بکشد." . Helper::adminFooter();

if ($Context->MessageId !== null) {
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Loading_Text, TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
]));
}

else {
TelegramClient::sendMessage($Context->ChatId, $Loading_Text);
}

$Results = [];

foreach ($Pairs as $Pair) {
$Results[] = self::processUpdatePair($Context, (string)$Pair[0], (string)$Pair[1]);
}

if (count($Pairs) > 1) {
$Summary_Text = Helper::adminGreeting($Context, 'بروز رسانی گروهی کاربران') . "📦نتایج بروز رسانی گروهی (" . Helper::toPersian((string)count($Pairs)) . " کاربر):\n➖➖➖➖➖➖➖➖➖\n" . implode("\n", $Results) . "\n➖➖➖➖➖➖➖➖➖\n✅عملیات گروهی پایان یافت." . Helper::adminFooter();
TelegramClient::sendMessage($Context->ChatId, mb_substr($Summary_Text, 0, 4000), TelegramClient::inlineKeyboard([
[['text' => '🔄بروز رسانی مجدد', 'callback_data' => 'بروز رسانی داده های کاربران اول']],
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}
}

private static function processUpdatePair(Context $Context, string $Provided_User_Ref, string $Provided_Uuid): string {
$Provided_User_Ref = trim($Provided_User_Ref);
$Resolved_User = Repository::findUserByIdentifier($Provided_User_Ref);
$Provided_User_Id = $Resolved_User !== null
? (int)($Resolved_User['Telegram_ID'] ?? 0)
: (int)preg_replace('/[^0-9]/', '', $Provided_User_Ref);

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🔄در حال دریافت اطلاعات از سرور...', false);
}

$Loading_Text = self::header($Context) . " *🔄در حال دریافت اطلاعات از سرور آمبرلا...\n➖➖➖➖➖➖➖➖➖\n⚠️نکته:این عملیات ممکن است کمی طول بکشد." . Helper::adminFooter();

if ($Context->MessageId !== null) {
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Loading_Text, TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
]));
}

else {
TelegramClient::sendMessage($Context->ChatId, $Loading_Text);
}

$Local_User = null;
$Target_Telegram_ID = 0;
$Client_ID = $Provided_Uuid;
$Response = ServerClient::getUser($Client_ID);
$Data = $Response['Json'] ?? null;

if (!is_array($Data) || ($Response['StatusCode'] ?? 0) >= 300 || !isset($Data['uuid'])) {
self::notifyAdminServerError('بروزرسانی داده های کاربر', $Target_Telegram_ID, self::targetDisplayName($Target_Telegram_ID, $Local_User ?? []), $Response['StatusCode'] ?? 0, (string)($Response['Body'] ?? ''));
$Error_Text = self::header($Context) . " *❌خطا: دریافت داده های سرور ناموفق بود.\n➖➖➖➖➖➖➖➖➖\n⚠️پاسخ سرور: " . mb_substr((string)($Response['Body'] ?? ''), 0, 200) . Helper::adminFooter();
TelegramClient::sendMessage($Context->ChatId, $Error_Text, TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return "❌خطا در دریافت از سرور — `{$Client_ID}`";
}

$Server_UUID = (string)($Data['uuid'] ?? '');
$Server_Telegram_ID = (int)($Data['telegram_id'] ?? 0);
$Server_Name = (string)($Data['name'] ?? '');
$Server_Usage_Limit = (float)($Data['usage_limit_GB'] ?? 0);
$Server_Used = (float)($Data['current_usage_GB'] ?? 0);
$Server_Package_Days = (int)($Data['package_days'] ?? 0);
$Server_Start_Date = (string)($Data['start_date'] ?? '');
$Server_Is_Active = (bool)($Data['is_active'] ?? false);
$Server_Enable = (bool)($Data['enable'] ?? true);
$Server_Last_Online = (string)($Data['last_online'] ?? '');
$Server_Comment = (string)($Data['comment'] ?? '');
$Server_ED_Private = (string)($Data['ed25519_private_key'] ?? '');
$Server_ED_Public = (string)($Data['ed25519_public_key'] ?? '');
$Server_WG_Private = (string)($Data['wg_pk'] ?? '');
$Server_WG_Public = (string)($Data['wg_pub'] ?? '');
$Server_WG_PSK = (string)($Data['wg_psk'] ?? '');
$Row = Database::getInstance()->fetchOne('SELECT `Telegram_ID` FROM `Users` WHERE `Client_ID` = ?', [$Client_ID]);
$Local_By_Client = null;
$Local_By_Provided = null;

if (is_array($Row) && isset($Row['Telegram_ID'])) {
$Local_By_Client = Repository::getUser((int)$Row['Telegram_ID']);
}

if ($Provided_User_Id > 0) {
$Local_By_Provided = Repository::getUser($Provided_User_Id);
}

if ($Provided_User_Id > 0) {
$Target_Telegram_ID = $Provided_User_Id;
$Local_User = (!empty($Local_By_Provided) && is_array($Local_By_Provided)) ? $Local_By_Provided : null;
}

elseif (is_array($Local_By_Client) && !empty($Local_By_Client)) {
$Target_Telegram_ID = (int)$Local_By_Client['Telegram_ID'];
$Local_User = $Local_By_Client;
}

elseif ($Server_Telegram_ID > 0) {
$Target_Telegram_ID = $Server_Telegram_ID;
$Local_User = Repository::getUser($Server_Telegram_ID);
}

if ($Target_Telegram_ID > 0 && $Server_Telegram_ID > 0 && $Target_Telegram_ID !== $Server_Telegram_ID) {
$Server_Has_Different = true;
}

$Remaining = max(0, $Server_Usage_Limit - $Server_Used);
$Percent = $Server_Usage_Limit > 0 ? round(($Server_Used / $Server_Usage_Limit) * 100, 1) : 0;
$Start_Date_Persian = '';

if ($Server_Start_Date !== '') {
try {
$Start_Date_Persian = Helper::gregorianToJalali($Server_Start_Date);
}

catch (Throwable) { $Start_Date_Persian = ''; }
}

$End_Date_Persian = '';
$End_Timestamp = 0;

if ($Server_Start_Date !== '' && $Server_Package_Days > 0) {
try {
$End_Timestamp = strtotime($Server_Start_Date . ' +' . $Server_Package_Days . ' days');
$End_Date = (new DateTimeImmutable('@' . $End_Timestamp))->setTimezone(new DateTimeZone('Asia/Tehran'))->format('Y-m-d');
$End_Date_Persian = Helper::gregorianToJalali($End_Date);
}

catch (Throwable) { $End_Date_Persian = ''; }
}

$Remaining_Time_Label = $End_Timestamp > 0
? Helper::remainingDuration($End_Timestamp)
: Helper::remainingDuration((int)($Local_User['Expiration_Time_Stamp'] ?? 0));

$Duration_Label = self::packageLabel($Server_Package_Days);
$Duration_Breakdown = self::packageBreakdown($Server_Package_Days);
$Last_Online_Label = 'نامشخص';

if ($Server_Last_Online !== '' && $Server_Last_Online !== '0001-01-01 00:00:00') {
try {
$Lo_Date = substr($Server_Last_Online, 0, 10);
$Lo_Time = substr($Server_Last_Online, 11, 8);
$Last_Online_Label = Helper::gregorianToJalali($Lo_Date) . ' - ' . Helper::formatTime($Lo_Time);
$Lo_Stamp = strtotime($Server_Last_Online);
if ($Lo_Stamp !== false && (time() - $Lo_Stamp) <= 300) { $Last_Online_Label = '🟢آنلاین'; }
}

catch (Throwable) { $Last_Online_Label = $Server_Last_Online; }
}

$Display_Name = $Server_Name !== '' ? $Server_Name : (string)($Local_User['Full_Name'] ?? 'کاربر');
$Phone = (string)($Local_User['Phone'] ?? '');

if ($Phone === '' && $Server_Comment !== '') {
$Phone = $Server_Comment;
}

$Operator = (string)($Local_User['Operator'] ?? '');

if ($Phone !== '' && Helper::validatePhone($Phone)) {
$Detected = Helper::detectOperator($Phone);

if ($Detected !== 'نامعتبر') {
$Operator = $Detected;
}
}

$Operator_Label = $Operator !== '' ? $Operator : 'نا مشخص';
$Update_Payload = [
'Client_ID' => $Server_UUID,
'Client_Status' => $Server_Is_Active ? '✅فعال' : '🚫غیر فعال',
'Subscription' => $Duration_Label,
'Package_Duration' => $Server_Package_Days,
'Package_Start_Date' => $Start_Date_Persian,
'Expiration_Date' => $End_Date_Persian,
'Expiration_Time_Stamp' => $End_Timestamp,
'Total_Usage_GB' => $Server_Usage_Limit,
'Used_Usage_GB' => $Server_Used,
'Remaining_Usage_GB' => $Remaining,
'Percent_Usage' => $Percent,
'ED_25519_Private_Key' => $Server_ED_Private,
'ED_25519_Public_Key' => $Server_ED_Public,
'WireGuard_Private_Key' => $Server_WG_Private,
'WireGuard_Public_Key' => $Server_WG_Public,
'WireGuard_PSK' => $Server_WG_PSK,
'Last_Online' => $Server_Last_Online,
'Server_Comment' => $Server_Comment,
'Server_Enable' => $Server_Enable ? 1 : 0,
'Server_Is_Active' => $Server_Is_Active ? 1 : 0,
'Full_Name' => $Display_Name,
'Operator' => $Operator,
];

if ($Phone !== '') {
$Update_Payload['Phone'] = $Phone;
}

if ($Target_Telegram_ID > 0) {
if (is_array($Local_User) && !empty($Local_User)) {
Repository::updateUser($Target_Telegram_ID, $Update_Payload);
}

else {
$Insert_Payload = array_merge($Update_Payload, [
'Telegram_ID' => $Target_Telegram_ID,
'Chat_ID' => $Target_Telegram_ID,
'First_Name' => $Display_Name,
'Full_Name' => $Display_Name,
'Is_Blocked' => '0',
'Balance' => 0,
'Free_Plan_Claimed' => '0',
]);
Database::getInstance()->insert('Users', $Insert_Payload);
}

if ($Target_Telegram_ID > 0 && $Server_Telegram_ID !== $Target_Telegram_ID) {
$Link_Response = ServerClient::updateUser($Server_UUID, ['telegram_id' => $Target_Telegram_ID]);

if (($Link_Response['StatusCode'] ?? 0) >= 300) {
self::notifyAdminServerError('لینک کاربر به تلگرام', $Target_Telegram_ID, $Display_Name, $Link_Response['StatusCode'] ?? 0, (string)($Link_Response['Body'] ?? ''));
}
}

try {
Repository::addSubscriptionLog(
$Target_Telegram_ID,
'admin_update',
$Duration_Label,
$Server_Package_Days,
$Server_Usage_Limit,
'بروزرسانی دستی توسط مدیریت (شناسه کلاینت: ' . $Server_UUID . ')',
'admin',
$Context->UserId
);
}

catch (Throwable) {   }
}

$Phone_Label = $Phone !== '' ? Helper::toPersian($Phone) : 'ثبت نشده';
$Usage_Limit_Label = Helper::formatGB($Server_Usage_Limit);
$Used_Label = Helper::formatGB($Server_Used);
$Remaining_Label = Helper::formatGB($Remaining);
$Percent_Label = Helper::formatPercent($Percent);
$Days_Label = Helper::toPersian((string)$Server_Package_Days);

$Detail_Text = Helper::adminGreeting($Context, 'بروز رسانی داده های کاربران') . "📋جزئیات کامل کاربر از سرور آمبرلا\n"
. "➖➖➖➖➖➖➖➖➖\n\n"
. "👤*نام کامل:* " . Helper::mention((string)$Display_Name, (int)$Target_Telegram_ID) . "\n"
. "🆔*شناسه تلگرام:* `" . Helper::toPersian((string)$Target_Telegram_ID) . "`\n"
. "📱*شماره تماس:* {$Phone_Label}\n"
. "📶*اپراتور:* {$Operator_Label}\n"
. "🔑*شناسه کلاینت:* `{$Server_UUID}`\n\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "💎*اطلاعات اشتراک:*\n"
. "├─🪪نوع اشتراک: *{$Duration_Label}*\n"
. "├─📦روزهای بسته: *{$Days_Label} روز*\n"
. "├─📅مدت دقیق: *{$Duration_Breakdown}*\n"
. "├─⏱️تاریخ شروع: *{$Start_Date_Persian}*\n"
. "├─⏳ تاریخ انقضا: *{$End_Date_Persian}*\n"
. "└─🕒زمان باقیمانده: *{$Remaining_Time_Label}*\n\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "📊*اطلاعات مصرف:*\n"
. "├─📊حجم کل: *{$Usage_Limit_Label}*\n"
. "├─📥حجم مصرف شده: *{$Used_Label}*\n"
. "├─📤حجم باقی مانده: *{$Remaining_Label}*\n"
. "├─📈درصد مصرف: *{$Percent_Label}٪*\n"
. "└─📡آخرین اتصال: *{$Last_Online_Label}*\n\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "🔐*کلیدهای کلاینت:*\n"
. "🔸<b>کلید خصوصی ادی۲۵۵۱۹</b>\n<pre>{$Server_ED_Private}</pre>\n"
. "🔹<b>کلید عمومی ادی۲۵۵۱۹</b>\n<pre>{$Server_ED_Public}</pre>\n"
. "🔸<b>کلید خصوصی وایرگارد</b>\n<pre>{$Server_WG_Private}</pre>\n"
. "🔹<b>کلید عمومی وایرگارد</b>\n<pre>{$Server_WG_Public}</pre>\n"
. "🔸<b>کلید از پیش اشتراکی وایرگارد</b>\n<pre>{$Server_WG_PSK}</pre>\n\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "✅*تمام مقادیر در دیتابیس ذخیره شدند.*";

// The 4096-character limit would cut the footer off mid-way, so the body is
// trimmed first and the standard footer is added after it.
$Detail_Text = mb_substr($Detail_Text, 0, 3800) . Helper::adminFooter();
TelegramClient::sendMessage($Context->ChatId, $Detail_Text, TelegramClient::inlineKeyboard([
[['text' => '🔄بروز رسانی مجدد', 'callback_data' => 'بروز رسانی داده های کاربران اول']],
[['text' => '🔙بازگشت', 'callback_data' => 'پیکربندی سرور']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));

if ($Target_Telegram_ID > 0) {
TelegramClient::sendMessage($Target_Telegram_ID, Common::greet(new Context([], $Target_Telegram_ID, $Target_Telegram_ID, $Display_Name, false, null, null, null, null), 'بروز رسانی اشتراک') . "🔄لحظاتی پیش اطلاعات اشتراک شما توسط مدیریت بروزرسانی گردید." . Helper::userFooter(), TelegramClient::inlineKeyboard([Common::backTo('💎مشاهده اشتراک', 'اشتراک من')]));
}

return "✅{$Display_Name} — `{$Server_UUID}`" . ($Target_Telegram_ID > 0 ? ' (ID: ' . Helper::toPersian((string)$Target_Telegram_ID) . ')' : '');
}

private static function packageLabel(int $Days): string {
return match (true) {
$Days <= 1 => '۱ روزه',
$Days <= 7 => '۱ هفته',
$Days <= 30 => '۱ ماهه',
$Days <= 31 => '۱ ماهه',
$Days <= 60 => '۲ ماهه',
$Days <= 90 => '۳ ماهه',
$Days <= 180 => '۶ ماهه',
$Days <= 365 => '۱۲ ماهه',
$Days <= 730 => '۲ ساله',
default => ceil($Days / 30) . ' ماهه',
};
}

private static function packageBreakdown(int $Days): string {
if ($Days <= 0) return 'نامشخص';
$Months = (int)floor($Days / 30);
$Rem = $Days % 30;
$Weeks = (int)floor($Rem / 7);
$Days_R = $Rem % 7;
$Parts = [];

if ($Months > 0) $Parts[] = Helper::toPersian((string)$Months) . ' ماه';
if ($Weeks > 0) $Parts[] = Helper::toPersian((string)$Weeks) . ' هفته';
if ($Days_R > 0) $Parts[] = Helper::toPersian((string)$Days_R) . ' روز';
return empty($Parts) ? Helper::toPersian((string)$Days) . ' روز' : implode(' و ', $Parts);
}

public static function financialReport(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

$Stats = Repository::globalStatistics();
$Top = Database::getInstance()->fetchAll(
"SELECT `Telegram_ID`, `First_Name`, `Full_Name`, `Total_Recharge` FROM `Users` WHERE `Total_Recharge` > 0 ORDER BY `Total_Recharge` DESC LIMIT 5"
);

$Top_Text = '';
$Rank = 0;

$Recharge_Base = max(0.0, (float)$Stats['total_recharge']);

foreach ($Top as $U) {
$Rank++;
$Name = trim((string)($U['Full_Name'] ?? '')) ?: (trim((string)($U['First_Name'] ?? '')) ?: 'کاربر');
$Name_Link = Helper::mention($Name, (int)($U['Telegram_ID'] ?? 0));
$Recharge = (float)$U['Total_Recharge'];
$Share = $Recharge_Base > 0 ? ($Recharge / $Recharge_Base) * 100.0 : 0.0;
$Marks = $Rank === 1 ? '👑' : '';

if ($Share >= 25.0) $Marks .= '🔥';

$Top_Text .= "├─" . Helper::rankLine($Rank, $Name_Link, Helper::formatCurrency($Recharge), $Share, -1.0, $Marks) . "\n";
}

if ($Top_Text === '') $Top_Text = "└─❌داده ای موجود نیست\n";
$Text = Helper::adminGreeting($Context, 'گزارش مالی پیشرفته') . '💰*درآمد (تومان):*' . "\n├─📅امروز: *" . Helper::formatCurrency($Stats['revenue_today']) . "* (" . Helper::toPersian((string)$Stats['revenue_today_count']) . " تراکنش)\n├─🗓هفت روز اخیر: *" . Helper::formatCurrency($Stats['revenue_week']) . "*\n├─📆سی روز اخیر: *" . Helper::formatCurrency($Stats['revenue_month']) . "* (" . Helper::toPersian((string)$Stats['revenue_month_count']) . " تراکنش)\n└─💎کل: *" . Helper::formatCurrency($Stats['revenue_total']) . "*\n\n🏆*۵ کاربر برتر (مجموع شارژ):*\n" . $Top_Text . "\n💳*کیف پول:*\n├─💵مجموع موجودی: *" . Helper::formatCurrency($Stats['total_balance']) . "*\n├─📊میانگین: *" . Helper::formatCurrency($Stats['avg_balance']) . "*\n└─👥دارای موجودی: *" . Helper::toPersian((string)$Stats['users_with_balance']) . "* نفر\n\n🧾*جمع کل مالی:*\n├─📥مجموع شارژ کاربران: *" . Helper::formatCurrency($Stats['total_recharge']) . "*\n├─📤مجموع خرید اشتراک: *" . Helper::formatCurrency($Stats['total_spent']) . "*\n└─🧮کل تراکنش ها: *" . Helper::toPersian((string)$Stats['total_transactions']) . "*\n\n📈*مصرف سرور:*\n├─📦سهمیه کل: *" . Helper::formatGB((float)$Stats['server_quota']) . "*\n├─📥مصرف کل: *" . Helper::formatGB((float)$Stats['server_used']) . "*\n└─💎اشتراک های فعال: *" . Helper::toPersian((string)$Stats['active_subscriptions']) . "*" . Helper::adminFooter();
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard([
[['text' => '🔁بروزرسانی', 'callback_data' => 'گزارش مالی']],
[['text' => '📅گزارش روزانه دقیق', 'callback_data' => 'گزارش روزانه']],
[['text' => '🔙بازگشت', 'callback_data' => 'منوی گزارش']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

public static function ticketAdminMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Waiting_Count = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Tickets` WHERE `Status` IN ('open','pending')");
$Answered_Count = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Tickets` WHERE `Status` = 'answered'");
$Closed_Count = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Tickets` WHERE `Status` = 'closed'");
$Total_Count = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Tickets`");
$Text = Helper::adminGreeting($Context, 'مدیریت تیکت ها')
. Menu::section('🎫', 'آمار تیکت ها', [
'🟡در انتظار پاسخ: *' . Helper::toPersian((string)$Waiting_Count) . '*',
'🟢پاسخ داده شده: *' . Helper::toPersian((string)$Answered_Count) . '*',
'⚫بسته شده: *' . Helper::toPersian((string)$Closed_Count) . '*',
'📋کل تیکت ها: *' . Helper::toPersian((string)$Total_Count) . '*',
])
. '📌*برای دیدن و پاسخ دادن، فهرست تیکت های باز را باز کنید:*' . Helper::adminFooter();
$Markup = array_merge(
Menu::rows([
[['📋تیکت های باز', 'لیست تیکت باز']],
]),
[Menu::adminHome()]
);
self::logMenuProblems('tickets', $Markup);
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Markup));
}

public static function ticketAdminList(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

$Tickets = Repository::openTickets(20);

if (empty($Tickets)) {
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, Helper::adminGreeting($Context, 'مدیریت تیکت ها') . "\n➖➖➖➖➖➖➖➖➖\n❌هیچ تیکت بازی وجود ندارد.*" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'مدیریت تیکت ها']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
return;
}

$Buttons = [];

foreach ($Tickets as $T) {
$Priority_Icon = ['low' => '🟢', 'medium' => '🟡', 'high' => '🟠', 'urgent' => '🔴'][$T['Priority']] ?? '🟡';
$Buttons[] = [['text' => "{$Priority_Icon} #{$T['ID']} - " . mb_substr((string)$T['Subject'], 0, 30), 'callback_data' => 'ticket_view:' . $T['ID']]];
}

$Buttons[] = [['text' => '🔙بازگشت', 'callback_data' => 'مدیریت تیکت ها']];
$Buttons[] = [['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']];

TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, Helper::adminGreeting($Context, 'مدیریت تیکت ها') . "📋لیست تیکت های باز" . Helper::adminFooter(), TelegramClient::inlineKeyboard($Buttons));
}

public static function ticketAdminView(Context $Context, int $Ticket_ID): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Ticket = Repository::getTicket($Ticket_ID);

if ($Ticket === null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, 'تیکت یافت نشد', true);
return;
}

$Messages = Repository::getTicketMessages($Ticket_ID);
$User = Repository::getUser((int)$Ticket['User_ID']);
$User_Name = (string)($User['Full_Name'] ?? $User['First_Name'] ?? 'کاربر');
$Text = Helper::adminGreeting($Context, 'تیکت #' . $Ticket_ID) . '🎫';
$Text .= "👤کاربر: {$User_Name}\n";
$Text .= "📋موضوع: " . $Ticket['Subject'] . "\n";
$Persian_Category = Helper::ticketCategoryLabel((string)($Ticket['Category'] ?? 'other'));
$Persian_Priority = Helper::ticketPriorityLabel((string)($Ticket['Priority'] ?? 'medium'));
$Text .= "📂دسته: *{$Persian_Category}*\n";
$Text .= "🚦اولویت: *{$Persian_Priority}*\n";
$Status_Map = ['open' => '🟡باز', 'pending' => '🟠در انتظار', 'answered' => '🟢پاسخ داده شده', 'closed' => '⚫بسته شده'];
$Persian_Status = $Status_Map[$Ticket['Status']] ?? '🟡باز';
$Text .= "📊وضعیت: *{$Persian_Status}*\n\n";
$Count = 0;

foreach ($Messages as $Msg) {
$Count++;
$Sender = $Msg['Sender_Type'] === 'admin' ? '🛡ادمین' : '👤کاربر';
$Text .= "{$Sender}: " . ($Msg['Message'] ?? '[مدیا]') . "\n";

if ($Msg['Photo_File_ID'] !== null && $Msg['Photo_File_ID'] !== '') {
$Text .= "📎[پیوست تصویری]\n";
}
}

$Text .= Helper::adminFooter();
$Buttons = [
[['text' => '✏️پاسخ', 'callback_data' => 'ticket_reply:' . $Ticket_ID]],
[['text' => '✅بستن تیکت', 'callback_data' => 'ticket_close:' . $Ticket_ID]],
[['text' => '🔙بازگشت', 'callback_data' => 'لیست تیکت باز']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
];

TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Buttons));
}

public static function ticketAdminReplyStart(Context $Context, int $Ticket_ID): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:ticket_reply_text', 'Temp_Ticket_ID' => $Ticket_ID]);
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, Helper::adminGreeting($Context, "پاسخ به تیکت #{$Ticket_ID}") . "\n➖➖➖➖➖➖➖➖➖\n✏️📝پاسخ خود را وارد کنید:" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
Menu::back('مدیریت تیکت ها', 'مدیریت تیکت ها'),
Menu::adminHome(),
]));
}

public static function ticketAdminReplySend(Context $Context, string $Text): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Session = Repository::getUserSession($Context->UserId);
$Ticket_ID = (int)($Session['Temp_Ticket_ID'] ?? 0);

if ($Ticket_ID <= 0) return;
$Ticket = Repository::getTicket($Ticket_ID);

if ($Ticket === null) return;
Repository::addTicketMessage($Ticket_ID, $Context->UserId, 'admin', $Text);
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Temp_Ticket_ID' => null]);
$User = Repository::getUser((int)$Ticket['User_ID']);
$Chat_ID = (int)($User['Chat_ID'] ?? 0);

if ($Chat_ID > 0) {
TelegramClient::sendMessage($Chat_ID, Helper::frame('کاربر', (string)($User['Full_Name'] ?? ''), 'پاسخ تیکت', (int)$Ticket['User_ID']) . "📨پاسخ تیکت #{$Ticket_ID}\n➖➖➖➖➖➖➖➖➖\n{$Text}\n➖➖➖➖➖➖➖➖➖\n👇برای مشاهده و پاسخ به منوی تیکت بروید." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '🎫تیکت های من', 'callback_data' => 'تیکت های من']],
Menu::userHome(),
]));
}

TelegramClient::sendMessage($Context->ChatId, Helper::adminGreeting($Context, "پاسخ به تیکت #{$Ticket_ID}") . "\n➖➖➖➖➖➖➖➖➖\n✅پاسخ شما با موفقیت ارسال شد." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙بازگشت', 'callback_data' => 'لیست تیکت باز']],
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

public static function ticketAdminClose(Context $Context, int $Ticket_ID): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
Repository::closeTicket($Ticket_ID);
TelegramClient::answerCallbackQuery($Context->CallbackId, '✅تیکت بسته شد', false);
self::ticketAdminList($Context);
}

public static function smsTemplateMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, self::header($Context) . " *❌این بخش غیرفعال شده است.*" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

public static function smsTemplateEdit(Context $Context, string $Code): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, self::header($Context) . " *❌این بخش غیرفعال شده است.*" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

public static function smsTemplateUpdate(Context $Context, string $Text): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Template_Code' => null]);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *❌این بخش غیرفعال شده است.*" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}
}
?>