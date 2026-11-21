<?php
declare(strict_types=1);

require_once __DIR__ . '/Context.php';
require_once __DIR__ . '/Common.php';
require_once __DIR__ . '/../Core/Telegram/Telegram.php';
require_once __DIR__ . '/../Core/Server/Umbrella-Server.php';
require_once __DIR__ . '/../Core/SMS/IPPanel.php';
require_once __DIR__ . '/../Core/Support/Helper.php';
require_once __DIR__ . '/../Core/Support/Bot-Config.php';
require_once __DIR__ . '/Admin.php';
require_once __DIR__ . '/User.php';
require_once __DIR__ . '/../Core/Payment/ZarinPal.php';
require_once __DIR__ . '/../Core/Storage/Repository.php';
require_once __DIR__ . '/../Config/Environment.php';

final class SubscriptionFlow {
private const PLANS = [
'1' => ['۱ ماهه', 30, 1000],
'2' => ['۲ ماهه', 60, 1000],
'3' => ['۳ ماهه', 90, 1000],
'6' => ['۶ ماهه', 180, 1000],
'12' => ['۱ ساله', 360, 1000],
];

public const EXPIRY_COLUMNS = [
'Package_Duration', 'Package_Start_Date', 'Total_Usage_GB', 'Used_Usage_GB',
'Remaining_Usage_GB', 'Percent_Usage', 'Subscription', 'Expiration_Date',
'Expiration_Time_Stamp',
];

private const UNLIMITED_GB = 9999;
private const MIN_TOPUP = 80000;
private function __construct() {
}

private static function buyMenu(Context $Context, ?\Closure $Send = null): void {
$Money = Helper::formatCurrency(Repository::getBalance($Context->UserId));
$Rows = [
[['text' => "🔄💳به روزرسانی اعتبار حساب", 'callback_data' => "user_wallet_menu"]],
Menu::back('منوی قبلی', 'user_subscriptions_menu'), Menu::userHome(),
];

$Text = Common::greet($Context, 'مدیریت اشتراک') . "➖➖➖➖➖➖➖➖➖\n🌏ارز کنونی:🇮🇷ایران - تومان\n💳اعتبار کنونی: *{$Money}*\n\n💎وضعیت اشتراک:*❌ندارید*\n\nℹ️برای تهیه اشتراک، از بخش مدیریت اشتراک یکی از گزینه های «💎اشتراک های آماده»، «🛠اشتراک دلخواه» یا «🎁اشتراک رایگان» را انتخاب کنید.\n\n⚠️نکته:همه اشتراک ها ۱ کاربره و با حجم نامحدود می باشد." . Helper::userFooter();

if ($Send !== null) { $Send($Text, TelegramClient::inlineKeyboard($Rows)); return; }
if ($Context->IsCallback && $Context->MessageId !== null) {
try { TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Rows)); return; } catch (Throwable) {}
}

TelegramClient::sendMessage($Context->ChatId, $Text, TelegramClient::inlineKeyboard($Rows));
}

public static function readyPlansMenu(Context $Context): void {
$Money = Helper::formatCurrency(Repository::getBalance($Context->UserId));
$Rows = [];

foreach (self::PLANS as $Month_Key => $Plan_Data) {
$Plan_Name = $Plan_Data[0];
$Plan_Price = BotConfig::getPlanPrice((int)$Month_Key);

// پلنی که در پنل قیمت نخورده است نمایش داده نمی شود تا کسی اشتراک رایگان نگیرد.
if ($Plan_Price <= 0) continue;

$Price_Label = Helper::formatCurrency($Plan_Price);
$Rows[] = [['text' => "💎{$Plan_Name} — {$Price_Label}", 'callback_data' => "خرید اشتراک {$Month_Key}"]];
}

if ($Rows === []) {
error_log('[Umbrella-Bot][Pricing] no plan has a price; the ready-plans menu is empty. Set them in ⚙️تنظیمات ربات ← 💰تعرفه اشتراک.');
$Support_Url = BotConfig::getSupportUrl();
$Empty_Buttons = [];
if ($Support_Url !== '') $Empty_Buttons[] = [['text' => '🎧پشتیبانی', 'url' => $Support_Url]];
$Empty_Buttons[] = Menu::back('منوی قبلی', 'user_subscriptions_menu');
$Empty_Buttons[] = Menu::userHome();
TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'اشتراک های آماده') . "⚠️در حال حاضر هیچ اشتراکی برای فروش تعریف نشده است.\n➖➖➖➖➖➖➖➖➖\n👌لطفاً بعداً مراجعه کنید یا با پشتیبانی در تماس باشید." . Helper::userFooter() . "*", TelegramClient::inlineKeyboard($Empty_Buttons));
return;
}

$Rows[] = Menu::back('منوی قبلی', 'user_subscriptions_menu');
$Rows[] = Menu::userHome();
$Text = Common::greet($Context, 'اشتراک های آماده') . "📌همه اشتراک های آماده با حجم *نامحدود* ارائه می شوند.\n\n💳اعتبار کنونی: *{$Money}*\n\n👇پلن مورد نظر را انتخاب کنید:" . Helper::userFooter() . "*";

if ($Context->IsCallback && $Context->MessageId !== null) {
try { TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Rows)); return; } catch (Throwable) {}
}

TelegramClient::sendMessage($Context->ChatId, $Text, TelegramClient::inlineKeyboard($Rows));
}

public static function customPlansMenu(Context $Context): void {
$Day_Rate = BotConfig::getCustomDayRate();
$Min = BotConfig::getCustomMinDays();
$Max = BotConfig::getCustomMaxDays();
$Min_GB = BotConfig::getCustomMinGB();
$Max_GB = BotConfig::getCustomMaxGB();
$Day_Label = Helper::formatCurrency($Day_Rate);
$Min_Label = Helper::toPersian((string)$Min);
$Max_Label = Helper::toPersian((string)$Max);
$Min_GB_Label = Helper::formatGB($Min_GB);
$Max_GB_Label = Helper::formatGB($Max_GB);
Repository::updateUserSession($Context->UserId, ['Flow' => 'custom_plan_days']);
$Text = Common::greet($Context, 'اشتراک دلخواه') . ""
. "📌در این بخش می توانید *تعداد روز* و *حجم* اشتراک را خودتان انتخاب کنید.\n\n"
. "💰*نرخ هر روز: {$Day_Label}* تومان\n"
. "🧮محاسبه بر اساس پلن ۱ ماهه: *" . Helper::formatCurrency((float)Environment::get('PLAN_PRICE_1')) . "* تومان ÷ ۳۰\n"
. "📦*حجم:* بین {$Min_GB_Label} تا {$Max_GB_Label} — *هزینه ای جداگانه ندارد* و فقط سهمیه شماست.\n\n"
. "📏*محدوده مجاز:* *{$Min_Label}* تا *{$Max_Label}* روز\n\n"
. "👇مرحله ۱ از ۲ — *تعداد روز* اشتراک را به عدد وارد کنید:" . Helper::userFooter() . "*";

$Keyboard = TelegramClient::inlineKeyboard([
Menu::back('منوی قبلی', 'user_subscriptions_menu'), Menu::userHome(),
]);

if ($Context->IsCallback && $Context->MessageId !== null) {
try { TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Text, $Keyboard); return; } catch (Throwable) {}
}

TelegramClient::sendMessage($Context->ChatId, $Text, $Keyboard);
}

/** سازگاری با دکمه های قدیمی: هدایت مستقیم به گام اول اشتراک دلخواه. */
public static function startCustomPlan(Context $Context): void {
self::customPlansMenu($Context);
}

public static function startCustomPlanGB(Context $Context): void {
$Min_GB = BotConfig::getCustomMinGB();
$Max_GB = BotConfig::getCustomMaxGB();
$Min_GB_Label = Helper::formatGB($Min_GB);
$Max_GB_Label = Helper::formatGB($Max_GB);
$Days = (int)(Repository::getUserSession($Context->UserId)['Custom_Days'] ?? 0);
$Days_Label = Helper::toPersian((string)max(1, $Days));
Repository::updateUserSession($Context->UserId, ['Flow' => 'custom_plan_gb']);
$Text = Common::greet($Context, 'اشتراک دلخواه') . ""
. "👇مرحله ۲ از ۲ — *حجم* اشتراک را به گیگابایت وارد کنید:\n\n"
. "📅مدت انتخاب شده: *{$Days_Label} روز*\n"
. "📦محدوده مجاز حجم: *{$Min_GB_Label}* تا *{$Max_GB_Label}*\n\n"
. "ℹ️فقط عدد را تایپ و ارسال کنید؛ مثال: ۵۰\n"
. "⚠️جهت انصراف «لغو» را ارسال کنید."
. Helper::userFooter() . "*";
$Keyboard = TelegramClient::inlineKeyboard([
Menu::back('اشتراک دلخواه', 'اشتراک دلخواه'),
Menu::userHome(),
]);

if ($Context->IsCallback && $Context->MessageId !== null) {
try { TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Text, $Keyboard); return; } catch (Throwable) {}
}

TelegramClient::sendMessage($Context->ChatId, $Text, $Keyboard);
}

public static function customPlanGBCallback(Context $Context, string $Raw_GB): void {
$Session = Repository::getUserSession($Context->UserId);
$Days = (int)($Session['Custom_Days'] ?? 0);

if ($Days <= 0) {
self::startCustomPlan($Context);
return;
}

self::saveCustomPlanGB($Context, $Days, $Raw_GB);
}

private static function saveCustomPlanGB(Context $Context, int $Days, string $Raw_GB): void {
$Min_GB = BotConfig::getCustomMinGB();
$Max_GB = BotConfig::getCustomMaxGB();
$GB = (float)Helper::toEnglish(str_replace([' ', ',', '٬', '٫'], ['', '', '', '.'], trim($Raw_GB)));

if ($GB < $Min_GB || $GB > $Max_GB) {
TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'اشتراک دلخواه') . "❌خطا: حجم وارد شده معتبر نیست.\n➖➖➖➖➖➖➖➖➖\n⚠️لطفاً عددی بین *" . Helper::formatGB($Min_GB) . "* تا *" . Helper::formatGB($Max_GB) . "* وارد کنید." . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
Menu::back('اشتراک دلخواه', 'اشتراک دلخواه'),
Menu::userHome(),
]));
return;
}

Repository::updateUserSession($Context->UserId, ['Custom_GB' => $GB, 'Flow' => null]);
self::confirmCustomPlan($Context, $Days, $GB);
}

public static function handleCustomPlanInput(Context $Context, string $Text): void {
$Session = Repository::getUserSession($Context->UserId);
$Flow = (string)($Session['Flow'] ?? '');

if ($Flow === 'custom_plan_gb') {
$Days = (int)($Session['Custom_Days'] ?? 0);

if ($Days <= 0) {
self::startCustomPlan($Context);
return;
}

self::saveCustomPlanGB($Context, $Days, $Text);
return;
}

if ($Flow !== 'custom_plan_days') {
return;
}

$Min = BotConfig::getCustomMinDays();
$Max = BotConfig::getCustomMaxDays();
$Days = (int)Helper::toEnglish(trim($Text));

if ($Days < $Min || $Days > $Max) {
TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'اشتراک دلخواه') . "❌خطا: تعداد روز وارد شده معتبر نیست.\n➖➖➖➖➖➖➖➖➖\n⚠️لطفاً عددی بین *" . Helper::toPersian((string)$Min) . "* تا *" . Helper::toPersian((string)$Max) . "* وارد کنید." . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
Menu::back('اشتراک دلخواه', 'اشتراک دلخواه'),
Menu::userHome(),
]));
return;
}

Repository::updateUserSession($Context->UserId, ['Custom_Days' => $Days, 'Custom_GB' => null, 'Flow' => 'custom_plan_gb']);
self::startCustomPlanGB($Context);
}

private static function withPurchaseLock(Context $Context, callable $Operation): void {
$Lock = 'subscription_purchase_' . $Context->UserId;
if (!Repository::tryCronLock($Lock, 180)) {
TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'پرداخت') . 'درخواست خرید دیگری در حال پردازش است؛ کمی بعد دوباره تلاش کنید.' . Helper::userFooter());
return;
}
try {
if (trim((string)(Repository::getUserSession($Context->UserId)['Pending_Payment'] ?? '')) !== '') {
TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'پرداخت') . 'یک پرداخت قبلی در حال بررسی است؛ ابتدا همان سفارش را تکمیل یا پیگیری کنید.' . Helper::userFooter());
return;
}
$Operation();
} finally {
Repository::releaseCronLock($Lock);
}
}

private static function confirmCustomPlan(Context $Context, int $Days, float $GB = 0.0): void {
self::withPurchaseLock($Context, static function () use ($Context, $Days, $GB): void {
self::confirmCustomPlanUnlocked($Context, $Days, $GB);
});
}

private static function confirmCustomPlanUnlocked(Context $Context, int $Days, float $GB = 0.0): void {
$Day_Rate = BotConfig::getCustomDayRate();
$Total = (int)round($Days * $Day_Rate);
$Days_Label = Helper::toPersian((string)$Days);
$GB_Label = Helper::formatGB($GB);
$Day_Price_Label = Helper::formatCurrency($Day_Rate);
$Total_Label = Helper::formatCurrency($Total);
$Name = "💎اشتراک {$Days_Label} روزه - {$GB_Label}";
$Balance = Repository::getBalance($Context->UserId);
$Balance_Label = Helper::formatCurrency($Balance);
$Phone = (string)(Repository::getUser($Context->UserId)['Phone'] ?? '');

if ($Balance >= $Total) {
if ($Context->IsCallback && $Context->MessageId !== null) {
try { TelegramClient::deleteMessage($Context->ChatId, $Context->MessageId); } catch (Throwable) {}
}

self::purchaseCustom($Context, $Name, $Days, $Total, $GB);
return;
}

$Need = $Total - $Balance;
$Need_Label = Helper::formatCurrency($Need);
$Direct_Url = '';

if (Zarinpal::isConfigured() && $Phone !== '') {
$Call_Back_Base = Environment::getPaymentCallbackUrl();
$Call_Back_Url = $Call_Back_Base . (str_contains($Call_Back_Base, '?') ? '&' : '?') . 'Uid=' . $Context->UserId;
$Pre = self::preflightGateway($Context, $Need, $Call_Back_Url, 'خرید ' . $Name . ' - سرور آمبرلا', Helper::normalizePhone($Phone));

if (is_array($Pre) && isset($Pre['Authority'], $Pre['RedirectUrl'])) {
$Direct_Url = Zarinpal::payLink($Pre);
$Final_Amount = (float)($Pre['Amount'] ?? $Need);
Repository::updateUserSession($Context->UserId, [
'Pending_Custom_Plan' => $Days . '|' . $Total . '|' . $GB,
'Pending_Topup' => (string)$Need,
'Pending_Plan' => null,
'Pending_Payment' => 'topup|' . $Final_Amount . '|' . $Pre['Authority'],
]);
}
}

if ($Direct_Url === '') {
Repository::updateUserSession($Context->UserId, [
'Pending_Custom_Plan' => $Days . '|' . $Total . '|' . $GB,
'Pending_Topup' => (string)$Need,
'Pending_Plan' => null,
]);
}

$Min_Payment = Environment::getMinimumPaymentAmount();

if ($Need < $Min_Payment) {
$Shortage = $Min_Payment - $Need;
$Shortage_Label = Helper::formatCurrency($Shortage);
$Min_Label = Helper::formatCurrency($Min_Payment);
$Extra_Days = (int)ceil($Shortage / max(1.0, BotConfig::getCustomDayRate()));
$Extra_Days_Label = Helper::toPersian((string)$Extra_Days);
$Text = Common::greet($Context, 'اشتراک دلخواه') . "❌مبلغ قابل پرداخت از درگاه کمتر از حد مجاز است.\n➖➖➖➖➖➖➖➖➖\n⚠️حداقل مبلغ پرداخت از درگاه: *{$Min_Label}*\n💵کسری شما: *{$Shortage_Label}*\n\n👌پیشنهاد می شود حداقل {$Extra_Days_Label} روز دیگر اضافه کنید تا بتوانید پرداخت را تکمیل کنید." . Helper::userFooter() . "*";
$Rows = [
[['text' => '➕افزایش روز', 'callback_data' => 'اشتراک دلخواه']],
Menu::userHome(),
];

$Is_Callback = $Context->IsCallback && $Context->MessageId !== null;

if ($Is_Callback) {
try { TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Rows)); return; } catch (Throwable) {}
}

TelegramClient::sendMessage($Context->ChatId, $Text, TelegramClient::inlineKeyboard($Rows));
return;
}

$Final_Amount = 0.0;
$Fee_Label = '';
$Pre = null;

if (Zarinpal::isConfigured() && $Phone !== '') {
$Call_Back_Base = Environment::getPaymentCallbackUrl();
$Call_Back_Url = $Call_Back_Base . (str_contains($Call_Back_Base, '?') ? '&' : '?') . 'Uid=' . $Context->UserId;
$Pre = self::preflightGateway($Context, $Need, $Call_Back_Url, 'خرید ' . $Name . ' - سرور آمبرلا', Helper::normalizePhone($Phone));

if (is_array($Pre) && isset($Pre['Authority'], $Pre['RedirectUrl'])) {
$Direct_Url = Zarinpal::payLink($Pre);
$Final_Amount = (float)($Pre['Amount'] ?? $Need);
$Fee_Label = self::paymentAmount((float)($Pre['Fee'] ?? ($Final_Amount - $Need)));
Repository::updateUserSession($Context->UserId, [
'Pending_Custom_Plan' => $Days . '|' . $Total . '|' . $GB,
'Pending_Topup' => (string)$Need,
'Pending_Plan' => null,
'Pending_Payment' => 'topup|' . $Final_Amount . '|' . $Pre['Authority'],
]);
}
}

$Final_Amount_Label = $Final_Amount > 0 ? self::paymentAmount($Final_Amount) : $Need_Label;
$Pay_Button = $Direct_Url !== ''
? [['text' => '💳پرداخت ' . $Final_Amount_Label . ' از درگاه', 'url' => $Direct_Url]]
: [['text' => '💳پرداخت ' . $Need_Label . ' از درگاه', 'callback_data' => 'پرداخت کسری کیف پول']];
$Fee_Line = $Fee_Label !== '' ? "├─💸کارمزد: *{$Fee_Label}*\n" : '';
$Text = Common::greet($Context, 'اشتراک دلخواه') . "⚠️موجودی کیف پول شما برای خرید کافی نیست.\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "💎*جزئیات اشتراک سفارشی:*\n"
. "├─🪪اشتراک: *{$Name}*\n"
. "├─🕰تعداد روز: *" . Helper::toPersian((string)$Days) . "* روز\n"
. "├─📦حجم (سهمیه): *{$GB_Label}*\n"
. "├─💵نرخ هر روز: *{$Day_Price_Label}*\n"
. "├─💰مبلغ کل: *{$Total_Label}*\n"
. "├─💳موجودی کیف پول: *{$Balance_Label}*\n"
. $Fee_Line
. "└─🏦مبلغ قابل پرداخت از درگاه: *{$Final_Amount_Label}* (شامل کارمزد خریدار)\n\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "🔄*مراحل تکمیل خرید:*\n"
. "۱. پرداخت از طریق درگاه امن زرین پال\n"
. "۲. شارژ خودکار کیف پول به مبلغ {$Need_Label}\n"
. "۳. فعالسازی خودکار اشتراک {$Name}" . Helper::userFooter() . "*";

$Rows = [$Pay_Button, Common::backTo('🔙انصراف', 'اشتراک دلخواه'), Menu::userHome()];
$Is_Callback = $Context->IsCallback && $Context->MessageId !== null;

if ($Is_Callback) {
try {
$Res = TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Rows));

if (($Res['ok'] ?? false) === true) return;
}

catch (Throwable) {}
}

TelegramClient::sendMessage($Context->ChatId, $Text, TelegramClient::inlineKeyboard($Rows));
}

public static function confirmCustomPlanCallback(Context $Context): void {
self::withPurchaseLock($Context, static function () use ($Context): void {
self::confirmCustomPlanCallbackUnlocked($Context);
});
}

private static function confirmCustomPlanCallbackUnlocked(Context $Context): void {
$Session = Repository::getUserSession($Context->UserId);
$Days = (int)($Session['Custom_Days'] ?? 0);

if ($Days <= 0) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '⛔️جلسه منقضی شده.', true);
self::customPlansMenu($Context);
return;
}

$Day_Rate = BotConfig::getCustomDayRate();
$Total = (int)round($Days * $Day_Rate);
$Days_Label = Helper::toPersian((string)$Days);
$Name = "💎اشتراک {$Days_Label} روزه";
self::purchaseCustom($Context, $Name, $Days, $Total);
}

private static function purchaseCustom(Context $Context, string $Name, int $Days, int $Amount, float $GB = 0.0): void {
$Greeting = Common::greet($Context, 'اشتراک دلخواه');
$User = Repository::getUser($Context->UserId);
$Phone = (string)($User['Phone'] ?? '');
$Full_Name_Stored = trim((string)($User['Full_Name'] ?? ''));

if ($Phone === '' || $Full_Name_Stored === '') {
if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '⛔️پروفایل را تکمیل کنید.', true);
}

TelegramClient::sendMessage($Context->ChatId, $Greeting . " *⛔️برای فعال سازی اشتراک ابتدا پروفایل کاربری خود را تکمیل کنید." . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
[['text' => '👤ویرایش و ثبت پروفایل', 'callback_data' => 'ویرایش و ثبت پروفایل']],
Menu::userHome(),
]));
return;
}

$Balance = Repository::getBalance($Context->UserId);
$Total_Label = Helper::formatCurrency($Amount);

if ($Balance >= $Amount) {
if (!Repository::removeMoney($Context->UserId, $Amount, 'خرید اشتراک - پرداخت از کیف پول', 'bot')) {
TelegramClient::sendMessage($Context->ChatId, $Greeting . " *❌خطا: کسر اعتبار ناموفق بود." . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
Menu::back('مدیریت اشتراک', 'user_subscriptions_menu'),
Menu::userHome(),
]));
return;
}

self::activateCustom($Context, $Name, $Days, $GB);
return;
}

$Need_Gateway_Amount = $Amount - $Balance;
$Balance_Label = Helper::formatCurrency($Balance);
$Need_Label = Helper::formatCurrency($Need_Gateway_Amount);
$Min_Payment = Environment::getMinimumPaymentAmount();

if ($Need_Gateway_Amount < $Min_Payment) {
$Shortage = $Min_Payment - $Need_Gateway_Amount;
$Shortage_Label = Helper::formatCurrency($Shortage);
$Min_Label = Helper::formatCurrency($Min_Payment);
$Days_Label_Fix = Helper::toPersian((string)$Days);
$Extra_Days = (int)ceil($Shortage / max(1.0, BotConfig::getCustomDayRate()));
$Extra_Days_Label = Helper::toPersian((string)$Extra_Days);
TelegramClient::sendMessage($Context->ChatId, $Greeting . " *❌مبلغ قابل پرداخت از درگاه کمتر از حد مجاز است.\n➖➖➖➖➖➖➖➖➖\n⚠️حداقل مبلغ پرداخت از درگاه: *{$Min_Label}*\n💵کسری شما: *{$Shortage_Label}*\n\n👌پیشنهاد می شود حداقل {$Extra_Days_Label} روز دیگر اضافه کنید تا بتوانید پرداخت را تکمیل کنید." . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
[['text' => '➕افزایش روز', 'callback_data' => 'اشتراک دلخواه']],
Menu::userHome()
]));
return;
}

$Final_Amount = 0.0;
$Fee_Label = '';

if (Zarinpal::isConfigured()) {
$Call_Back_Base = Environment::getPaymentCallbackUrl();
$Call_Back_Url = $Call_Back_Base . (str_contains($Call_Back_Base, '?') ? '&' : '?') . 'Uid=' . $Context->UserId;
$Pre = self::preflightGateway($Context, $Need_Gateway_Amount, $Call_Back_Url, 'خرید ' . $Name . ' - سرور آمبرلا', Helper::normalizePhone($Phone));

if (is_array($Pre) && isset($Pre['Authority'], $Pre['RedirectUrl'])) {
$Direct_Url = Zarinpal::payLink($Pre);
$Final_Amount = (float)($Pre['Amount'] ?? $Need_Gateway_Amount);
$Fee_Label = self::paymentAmount((float)($Pre['Fee'] ?? ($Final_Amount - $Need_Gateway_Amount)));
Repository::updateUserSession($Context->UserId, [
'Pending_Custom_Plan' => $Days . '|' . $Amount . '|' . $GB,
'Pending_Topup' => (string)$Need_Gateway_Amount,
'Pending_Plan' => null,
'Pending_Payment' => 'topup|' . $Final_Amount . '|' . $Pre['Authority'],
]);
}
}

if ($Direct_Url === '') {
Repository::updateUserSession($Context->UserId, [
'Pending_Custom_Plan' => $Days . '|' . $Amount . '|' . $GB,
'Pending_Topup' => (string)$Need_Gateway_Amount,
'Pending_Plan' => null,
]);
}

$Final_Amount_Label = $Final_Amount > 0 ? self::paymentAmount($Final_Amount) : $Need_Label;
$Pay_Button = $Direct_Url !== ''
? [['text' => '💳پرداخت ' . $Final_Amount_Label . ' از درگاه', 'url' => $Direct_Url]]
: [['text' => '💳پرداخت ' . $Need_Label . ' از درگاه', 'callback_data' => 'پرداخت کسری کیف پول']];
$Fee_Line = $Fee_Label !== '' ? "├─💸کارمزد: *{$Fee_Label}*\n" : '';
$Text = $Greeting . "⚠️موجودی کیف پول برای خرید کافی نیست.\n\n"
. "💎*جزئیات پرداخت:*\n"
. "├─🪪اشتراک: *{$Name}*\n"
. "├─💰مبلغ کل: *{$Total_Label}*\n"
. "├─💳موجودی: *{$Balance_Label}*\n"
. "├─📉کسری: *{$Need_Label}*\n"
. $Fee_Line
. "└─🏦قابل پرداخت از درگاه: *{$Final_Amount_Label}* (شامل کارمزد خریدار)\n\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "🔄*مراحل تکمیل خرید:*\n"
. "۱. پرداخت از طریق درگاه امن زرین پال\n"
. "۲. شارژ خودکار کیف پول به مبلغ {$Need_Label}\n"
. "۳. فعالسازی خودکار اشتراک {$Name}" . Helper::userFooter() . "*";
$Rows = [$Pay_Button, Common::backTo('🔙انصراف', 'اشتراک دلخواه'), Menu::userHome()];

if ($Context->IsCallback && $Context->MessageId !== null) {
try { TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Rows)); return; } catch (Throwable) {}
}

TelegramClient::sendMessage($Context->ChatId, $Text, TelegramClient::inlineKeyboard($Rows));
}

private static function activateCustom(Context $Context, string $Name, int $Days, float $GB = 0.0): void {
$User_ID = $Context->UserId;
$User = Repository::getUser($User_ID);
$Client_ID = (string)($User['Client_ID'] ?? '');
$Phone_For_Comment = (string)($User['Phone'] ?? '');
$Full_Name_User = trim((string)($User['Full_Name'] ?? ''));
$Server_Name = $Full_Name_User !== '' ? $Full_Name_User : ('user-' . $User_ID);
$Usage_Limit = $GB > 0 ? max(1, (int)round($GB)) : self::UNLIMITED_GB;

if ($Client_ID !== '' && $Client_ID !== '_') {
self::renewSubscription($Context, $Name, $Usage_Limit, $Days, $Client_ID);
return;
}

$Response = ServerClient::createUser($Server_Name, (string)$Usage_Limit, $Days, $Phone_For_Comment, $User_ID);
$Data = $Response['Json'] ?? null;

if (is_array($Data) && ($Response['StatusCode'] ?? 0) < 300 && isset($Data['uuid'])) {
$Actual_Gb = max($Usage_Limit, (int)round((float)($Data['usage_limit_GB'] ?? 0)));
self::activateSubscription($Context, $Data, $Name, $Actual_Gb, $Days);
return;
}

$Api_Error = '';

if (is_array($Data) && isset($Data['detail'])) {
$Api_Error = json_encode($Data['detail'], JSON_UNESCAPED_UNICODE);
}

elseif (!empty($Response['Body'])) {
$Api_Error = mb_substr((string)$Response['Body'], 0, 300);
}

AdminFlow::notifyAdminServerError('ایجاد اشتراک سفارشی', $User_ID, $Name, $Response['StatusCode'] ?? 0, $Api_Error);
TelegramClient::sendSystemMessage($Context->ChatId, Common::greet($Context, 'اشتراک دلخواه') . "❌اشتراک {$Name} شما فعال نشد." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔄تلاش مجدد', 'callback_data' => 'تایید اشتراک دلخواه']],
Menu::userHome(),
]));
}

public static function mySubscriptionActive(Context $Context, ?\Closure $Send = null): void {
$Send ??= static function (string $Text, array $Markup) use ($Context): void {
TelegramClient::sendReadableMessage($Context->ChatId, $Context->IsCallback ? $Context->MessageId : null, $Text, $Markup);
};
$Greeting = Common::greet($Context, 'اشتراک من');
$User = Repository::getUser($Context->UserId);
$Client_ID = (string)($User['Client_ID'] ?? '');
$Full_Name = $Context->profileName();
$Subscription = (string)($User['Subscription'] ?? '');
$Client_Status = (string)($User['Client_Status'] ?? 'فعال');
$Total_Usage_GB = (float)($User['Total_Usage_GB'] ?? 0);
$Used_Usage_GB = (float)($User['Used_Usage_GB'] ?? 0);
$Remaining_GB = (float)($User['Remaining_Usage_GB'] ?? 0);
$Percent_Val = (float)($User['Percent_Usage'] ?? 0);
$Package_Start = (string)($User['Package_Start_Date'] ?? '');
$Package_Duration = (string)($User['Package_Duration'] ?? '');
$Package_Days = (int)Helper::toEnglish(preg_replace('/[^0-9۰-۹]/u', '', $Package_Duration));
$Expiration_Time_Stamp = (int)($User['Expiration_Time_Stamp'] ?? 0);
$Expiration = $Expiration_Time_Stamp > 0 ? Helper::formatExpirationShort($Expiration_Time_Stamp) : (string)($User['Expiration_Date'] ?? '');
$Last_Online = (string)($User['Last_Online'] ?? '');
$ED_Private = (string)($User['ED_25519_Private_Key'] ?? '');
$ED_Public = (string)($User['ED_25519_Public_Key'] ?? '');
$WG_Private = (string)($User['WireGuard_Private_Key'] ?? '');
$WG_Public = (string)($User['WireGuard_Public_Key'] ?? '');
$WG_PSK = (string)($User['WireGuard_PSK'] ?? '');
$Server_Comment = (string)($User['Server_Comment'] ?? '');
try { $Response = ServerClient::getUser($Client_ID); }
catch (Throwable) { $Response = ['StatusCode' => 503]; }
$Data = $Response['Json'] ?? null;
if (!is_array($Data) || ($Response['StatusCode'] ?? 0) >= 300) $Greeting .= "⚠️سرور در دسترس نیست؛ اطلاعات ذخیره شده نمایش داده می شود.\n";

if (is_array($Data) && ($Response['StatusCode'] ?? 0) < 300) {
$Usage_Limit = (float)($Data['usage_limit_GB'] ?? 0);
$Used_GB = (float)($Data['current_usage_GB'] ?? 0);
$Remaining_GB = max(0, $Usage_Limit - $Used_GB);
$Percent_Val = $Usage_Limit > 0 ? round(($Used_GB / $Usage_Limit) * 100, 1) : 0;
$Total_Usage_GB = $Usage_Limit;
$Used_Usage_GB = $Used_GB;
$Remaining_GB = $Remaining_GB;
$Last_Online = (string)($Data['last_online'] ?? $Last_Online);
$ED_Private = (string)($Data['ed25519_private_key'] ?? $ED_Private);
$ED_Public = (string)($Data['ed25519_public_key'] ?? $ED_Public);
$WG_Private = (string)($Data['wg_pk'] ?? $WG_Private);
$WG_Public = (string)($Data['wg_pub'] ?? $WG_Public);
$WG_PSK = (string)($Data['wg_psk'] ?? $WG_PSK);
$Server_Comment = (string)($Data['comment'] ?? $Server_Comment);
$Updates = [
'Total_Usage_GB' => $Total_Usage_GB,
'Used_Usage_GB' => $Used_Usage_GB,
'Remaining_Usage_GB' => $Remaining_GB,
'Percent_Usage' => $Percent_Val,
'Last_Online' => $Last_Online,
'ED_25519_Private_Key' => $ED_Private,
'ED_25519_Public_Key' => $ED_Public,
'WireGuard_Private_Key' => $WG_Private,
'WireGuard_Public_Key' => $WG_Public,
'WireGuard_PSK' => $WG_PSK,
'Server_Comment' => $Server_Comment,
];

$Server_Active = (bool)($Data['is_active'] ?? true);
$Server_Enabled = (bool)($Data['enable'] ?? true);

if (!$Server_Active || !$Server_Enabled) {
$Client_Status = (int)($User['Channel_Client_Disabled_At'] ?? 0) > 0 ? '🚫قطع به دلیل عدم عضویت' : '🚫غیر فعال';
$Updates['Client_Status'] = $Client_Status;
}

Repository::updateUser($Context->UserId, $Updates);
}

if (str_contains($Client_Status, 'غیر') || (int)($User['Server_Is_Active'] ?? 1) === 0 || (int)($User['Server_Enable'] ?? 1) === 0) {
$Reason = (string)($User['Deactivation_Message'] ?? 'از سرور');

if (trim($Reason) === '') $Reason = 'کلاینت شما در سرور غیرفعال است';
$Text = $Greeting . Helper::noticeBlock(
'⛔️کلاینت شما در سرور غیرفعال است.',
'⚠️علت:🔌غیرفعال سازی کلاینت در سرور — ' . $Reason,
'ℹ️تا زمانی که کلاینت شما فعال نشود، امکان استفاده از سرویس وجود ندارد.'
) . Helper::userFooter();
$Send($Text, TelegramClient::inlineKeyboard([
[['text' => '🔄بررسی مجدد', 'callback_data' => 'اشتراک من']],
[['text' => '🎫تیکت ها و پشتیبانی', 'callback_data' => 'تیکت های من']],
[['text' => '👨‍💻ارتباط با توسعه دهنده (آرمین سافت)', 'url' => BotConfig::getSupportUrl()]],
Menu::back('منوی قبلی', 'user_subscriptions_menu'), Menu::userHome()
]));
return;
}

$Last_Online_Label = 'نامشخص';

if ($Last_Online !== '' && $Last_Online !== '0001-01-01 00:00:00') {
try {
$Lo_Date = substr($Last_Online, 0, 10);
$Lo_Time = substr($Last_Online, 11, 8);
$Last_Online_Label = Helper::gregorianToJalali($Lo_Date) . ' - ' . Helper::formatTime($Lo_Time);
$Lo_Stamp = \Helper::parseServerTimeSafe($Last_Online);
if ($Lo_Stamp !== false && (time() - $Lo_Stamp) <= 300) { $Last_Online_Label = '🟢آنلاین'; }
}

catch (Throwable) { $Last_Online_Label = $Last_Online; }
}

$Client_Status_Label = Helper::translateStatus($Client_Status);
$Base_Link = (string)(Repository::getSetting('Subscription_Link_Base') ?: Environment::getSubscriptionLinkBase());
$Text = $Greeting . "➖➖➖➖➖➖➖➖➖\n";
$Text .= "💎<b>اطلاعات اشتراک:</b>\n";
$Text .= "├─🪪<b>نوع اشتراک:</b> <b>{$Subscription}</b>\n";
$Duration_Days = $Package_Days > 0 ? Helper::toPersian((string)$Package_Days) : Helper::durationLabelFromLabel($Package_Duration);
$Duration_Label = $Package_Days > 0 ? Helper::humanDuration($Package_Days * 86400) : Helper::durationLabelFromLabel($Package_Duration);
$Text .= "├─📆<b>مدت دقیق اشتراک:</b> <b>{$Duration_Days}</b> <b>({$Duration_Label})</b>\n";
$Text .= "├─⏱️<b>تاریخ شروع:</b> <b>{$Package_Start}</b>\n";
$Text .= "├─⏳<b>تاریخ انقضا:</b> <b>{$Expiration}</b>\n";
$Text .= "├─🕒<b>زمان باقیمانده:</b> <b>" . Helper::remainingDuration($Expiration_Time_Stamp) . "</b>\n";
$Text .= "├─🚦<b>وضعیت کلاینت:</b> <b>{$Client_Status_Label}</b>\n";
$Text .= "└─📡<b>آخرین اتصال:</b> <b>{$Last_Online_Label}</b>\n\n";
$Text .= "📊<b>مصرف:</b>\n";
$Text .= "├─📊<b>حجم کل:</b> <b>" . Helper::formatGB($Total_Usage_GB) . "</b>\n";
$Text .= "├─📥<b>مصرف شده:</b> <b>" . Helper::formatGB($Used_Usage_GB) . "</b>\n";
$Text .= "├─📤<b>باقیمانده:</b> <b>" . Helper::formatGB($Remaining_GB) . "</b>\n";
$Text .= "└─📈<b>درصد مصرف:</b> <b>" . Helper::formatPercent($Percent_Val) . "٪</b>\n\n";
$Key_Esc = static fn(string $Value): string => htmlspecialchars(trim($Value), ENT_QUOTES, 'UTF-8');
$Client_ID_Label = $Key_Esc($Client_ID);
$ED_Private_Label = $Key_Esc($ED_Private);
$ED_Public_Label = $Key_Esc($ED_Public);
$WG_Private_Label = $Key_Esc($WG_Private);
$WG_Public_Label = $Key_Esc($WG_Public);
$WG_PSK_Label = $Key_Esc($WG_PSK);
$Text .= "🔑<b>کلیدهای اتصال</b>\n\n";
$Text .= "🆔<b>شناسه کلاینت</b>\n<pre>{$Client_ID_Label}</pre>\n";
$Text .= "🔸<b>کلید خصوصی ادی۲۵۵۱۹</b>\n<pre>{$ED_Private_Label}</pre>\n";
$Text .= "🔹<b>کلید عمومی ادی۲۵۵۱۹</b>\n<pre>{$ED_Public_Label}</pre>\n";
$Text .= "🔸<b>کلید خصوصی وایرگارد</b>\n<pre>{$WG_Private_Label}</pre>\n";
$Text .= "🔹<b>کلید عمومی وایرگارد</b>\n<pre>{$WG_Public_Label}</pre>\n";
$Text .= "🔸<b>کلید پیش اشتراکی وایرگارد</b>\n<pre>{$WG_PSK_Label}</pre>\n";
$Text .= self::configLinks($Base_Link, $Client_ID) . "\n\n";
$Text .= Helper::userFooter();

$Markup = TelegramClient::inlineKeyboard([
Common::backTo('🔄💎بروزرسانی اشتراک من', 'اشتراک من'),
[['text' => '👨‍💻ارتباط با توسعه دهنده (آرمین سافت)', 'url' => BotConfig::getSupportUrl()]],
Menu::back('منوی قبلی', 'user_subscriptions_menu'), Menu::userHome()
]);

if ($Send !== null) { $Send($Text, $Markup); return; }
TelegramClient::sendMessage($Context->ChatId, $Text, $Markup);
}

private static function configLinks(string $Base, string $Client_ID): string {
$Http_Base = preg_replace('#^https:#', 'http:', $Base);
$Items = [
['🚀خودکار', "{$Base}/{$Client_ID}/sub/"],
['☄️ایکس ری', "{$Base}/{$Client_ID}/all.txt"],
['🧿سینگ باکس', "{$Base}/{$Client_ID}/full-singbox.json"],
['⚡️کلش متا', "{$Base}/{$Client_ID}/clash/meta/all.yml"],
['🌐وایرگارد', "{$Base}/{$Client_ID}/wireguard/?asn=unknown"],
['🛡️آمنزیا دبلیو جی', "{$Http_Base}/{$Client_ID}/amnezia/?asn=unknown"],
['🔵میرو', "{$Http_Base}/{$Client_ID}/mieru/?asn=unknown"],
];

$Text = "⚡️<b>مشخصات اتصال شما به شرح زیر است</b>\n";

if (BotConfig::showEmergency()) {
$Emergency = BotConfig::emergencyUrl();
$Text .= "<blockquote>🚱<b>اضطراری موقت:</b>\n<code>{$Emergency}</code></blockquote>\n";
}

foreach ($Items as [$Label, $Url]) {
$Text .= "\n{$Label}\n<code>{$Url}</code>\n";
}

return rtrim($Text);
}

public static function freePlan(Context $Context): void {
if (self::hasAlreadyFree($Context) || self::hasActiveSubscriptionNow($Context)) return;
self::purchase($Context, 'free');
}

public static function nowruzPlan(Context $Context): void {
if (!BotConfig::isNowruzMenuEnabled()) {
if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '⛔️اشتراک نوروزی در حال حاضر فعال نیست.', true);
}
return;
}

$User = Repository::getUser($Context->UserId);
$Uuid = (string)($User['Client_ID'] ?? '');

if (BotConfig::hasClaimedNowruz($Context->UserId, $Uuid)) {
if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '❌اشتراک نوروزی را قبلاً دریافت کرده اید.', true);
}
return;
}

if (self::hasActiveSubscriptionNow($Context)) return;
self::purchase($Context, 'nowruz');
}

private static function hasActiveSubscriptionNow(Context $Context): bool {
$User = Repository::getUser($Context->UserId);
$Subscription = trim((string)($User['Subscription'] ?? ''));
$Expires_At = (int)($User['Expiration_Time_Stamp'] ?? 0);

if ($Subscription !== '' && ($Expires_At <= 0 || $Expires_At > time())) {
if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '⚠️شما در حال حاضر اشتراک فعال دارید.', true);
}
return true;
}

return false;
}

/** Paid plans exposed to the authenticated Windows app; prices are the bot's live tariff. */
public static function appPlanCatalog(): array {
$Plans = [];
foreach (self::PLANS as $Month => [$Name, $Days, $Gb]) {
$Price = BotConfig::getPlanPrice($Month);
if ($Price <= 0) continue;
$Plans[] = ['month' => (string)$Month, 'name' => $Name, 'days' => $Days, 'gb' => $Gb, 'price' => (int)round($Price)];
}
return $Plans;
}

/** The app and Telegram use the same wallet minimum and pending-order ledger. */
public static function appWalletTerms(): array {
return ['min_topup' => max(self::MIN_TOPUP, (int)ceil(Environment::getMinimumPaymentAmount())),
'max_topup' => 100000000];
}

/** Start a pure wallet top-up under the shared purchase lock; no client can mark it paid. */
public static function startAppWalletTopup(int $User_ID, int $Amount): array {
$Terms = self::appWalletTerms();
if ($Amount < $Terms['min_topup'] || $Amount > $Terms['max_topup']) throw new InvalidArgumentException('invalid_topup');
$Lock = 'subscription_purchase_' . $User_ID;
if (!Repository::tryCronLock($Lock, 180)) throw new RuntimeException('purchase_busy');
try {
$Session = Repository::getUserSession($User_ID);
if (trim((string)($Session['Pending_Payment'] ?? '')) !== '') throw new RuntimeException('payment_pending');
$Base = Environment::getPaymentCallbackUrl();
if (!Zarinpal::isConfigured() || $Base === '') throw new RuntimeException('gateway_unavailable');
$User = Repository::getUser($User_ID);
if ($User === []) throw new RuntimeException('account_not_linked');
$Callback = $Base . (str_contains($Base, '?') ? '&' : '?') . 'Uid=' . $User_ID;
$Payment = Zarinpal::request((float)$Amount, $Callback, 'شارژ اعتبار کیف پول - سرور آمبرلا', Helper::normalizePhone((string)($User['Phone'] ?? '')));
if (!is_array($Payment) || !isset($Payment['Authority'], $Payment['RedirectUrl'])) throw new RuntimeException('gateway_request_failed');
$Final = (float)($Payment['Amount'] ?? $Amount);
Repository::updateUserSession($User_ID, [
'Pending_Payment' => 'topup|' . $Final . '|' . (string)$Payment['Authority'],
'Pending_Topup' => (string)$Amount,
'Pending_Plan' => null,
'Pending_Custom_Plan' => null,
]);
return $Payment;
} finally {
Repository::releaseCronLock($Lock);
}
}

/** Custom-plan constraints/rates are sourced from the same live bot settings. */
public static function appCustomPlanTerms(): array {
return [
'day_rate' => BotConfig::getCustomDayRate(),
'min_days' => BotConfig::getCustomMinDays(),
'max_days' => BotConfig::getCustomMaxDays(),
'min_gb' => BotConfig::getCustomMinGB(),
'max_gb' => BotConfig::getCustomMaxGB(),
];
}

/** Validate custom days and volume against the exact live bot constraints. */
private static function validateAppCustomPlan(int $Days, float $GB): array {
$Terms = self::appCustomPlanTerms();
if ($Days < $Terms['min_days'] || $Days > $Terms['max_days'] || !is_finite($GB)
|| $GB < $Terms['min_gb'] || $GB > $Terms['max_gb']) {
throw new InvalidArgumentException('invalid_custom_plan');
}
$Price = (int)round($Days * (float)$Terms['day_rate']);
if ($Price <= 0) throw new RuntimeException('custom_plan_unavailable');
return [$Price, $Terms];
}

/** Apply wallet-funded custom plan with the same ledger and activation pipeline as Telegram. */
public static function purchaseCustomFromAppWallet(int $User_ID, int $Days, float $GB, ?int $Quoted_Price = null): array {
$Lock = 'subscription_purchase_' . $User_ID;
if (!Repository::tryCronLock($Lock, 180)) throw new RuntimeException('purchase_busy');
try {
[$Price] = self::validateAppCustomPlan($Days, $GB);
if ($Quoted_Price !== null && $Quoted_Price !== $Price) throw new RuntimeException('price_changed');
if (trim((string)(Repository::getUserSession($User_ID)['Pending_Payment'] ?? '')) !== '') throw new RuntimeException('payment_pending');
$Balance = Repository::getBalance($User_ID);
if ($Balance < $Price) throw new RuntimeException('wallet_changed');
$User = Repository::getUser($User_ID);
if ($User === []) throw new RuntimeException('Linked bot account not found');
$Before_Expiry = (int)($User['Expiration_Time_Stamp'] ?? 0);
$Chat_ID = (int)(($User['Chat_ID'] ?? 0) ?: $User_ID);
$Context = new Context([], $User_ID, $Chat_ID, (string)(($User['First_Name'] ?? '') ?: 'کاربر'), false, null, null, null, null);
if (!Repository::removeMoney($User_ID, $Price, 'خرید اشتراک دلخواه - پرداخت از کیف پول', 'app')) throw new RuntimeException('wallet_changed');
try {
$Name = 'اشتراک ' . Helper::toPersian((string)$Days) . ' روزه - ' . Helper::formatGB($GB);
self::activateCustom($Context, $Name, $Days, $GB);
} catch (Throwable $Error) {
if (Repository::getBalance($User_ID) <= $Balance - $Price) Repository::addMoney($User_ID, $Price, 'بازگشت وجه اشتراک دلخواه (خطا در فعالسازی)', 'app');
throw $Error;
}
$After = Repository::getUser($User_ID);
$After_Expiry = (int)($After['Expiration_Time_Stamp'] ?? 0);
$After_Balance = Repository::getBalance($User_ID);
if ($After_Expiry <= $Before_Expiry) {
if ($After_Balance <= $Balance - $Price) Repository::addMoney($User_ID, $Price, 'بازگشت وجه اشتراک دلخواه (فعال سازی تأیید نشد)', 'app');
throw new RuntimeException('activation_failed');
}
if ($After_Balance > $Balance - $Price) throw new RuntimeException('wallet_debit_not_confirmed');
return ['expires_at' => $After_Expiry, 'balance' => $After_Balance, 'price' => $Price];
} finally {
Repository::releaseCronLock($Lock);
}
}

/** Create a custom-plan ZarinPal order in the same pending-payment ledger used by Telegram. */
public static function startAppCustomCheckout(int $User_ID, int $Days, float $GB, ?int $Quoted_Price = null): array {
$Lock = 'subscription_purchase_' . $User_ID;
if (!Repository::tryCronLock($Lock, 180)) throw new RuntimeException('purchase_busy');
try {
[$Price] = self::validateAppCustomPlan($Days, $GB);
if ($Quoted_Price !== null && $Quoted_Price !== $Price) throw new RuntimeException('price_changed');
$Current = Repository::getUserSession($User_ID);
if (trim((string)($Current['Pending_Payment'] ?? '')) !== '') throw new RuntimeException('payment_pending');
$Balance = Repository::getBalance($User_ID);
if ($Balance >= $Price) throw new RuntimeException('wallet_changed');
$Shortage = $Price - $Balance;
if ($Shortage < Environment::getMinimumPaymentAmount()) throw new RuntimeException('below_gateway_minimum');
if (!Zarinpal::isConfigured()) throw new RuntimeException('gateway_unavailable');
$Base = Environment::getPaymentCallbackUrl();
if ($Base === '') throw new RuntimeException('gateway_unavailable');
$User = Repository::getUser($User_ID);
$Callback = $Base . (str_contains($Base, '?') ? '&' : '?') . 'Uid=' . $User_ID;
$Name = 'اشتراک ' . Helper::toPersian((string)$Days) . ' روزه - ' . Helper::formatGB($GB);
$Payment = Zarinpal::request($Shortage, $Callback, 'خرید ' . $Name . ' - سرور آمبرلا', Helper::normalizePhone((string)($User['Phone'] ?? '')));
if (!is_array($Payment) || !isset($Payment['Authority'], $Payment['RedirectUrl'])) throw new RuntimeException('gateway_request_failed');
$Final = (float)($Payment['Amount'] ?? $Shortage);
Repository::updateUserSession($User_ID, [
'Pending_Plan' => null,
'Pending_Custom_Plan' => $Days . '|' . $Price . '|' . $GB,
'Pending_Topup' => (string)$Shortage,
'Pending_Payment' => 'topup|' . $Final . '|' . (string)$Payment['Authority'],
]);
$Payment['Plan_Price'] = $Price;
$Payment['Wallet_Balance'] = (int)round($Balance);
$Payment['Custom_Days'] = $Days;
$Payment['Custom_GB'] = $GB;
return $Payment;
} finally {
Repository::releaseCronLock($Lock);
}
}

/** Create an app checkout under the same per-user purchase lock used by bot purchases. */
public static function startAppCheckout(int $User_ID, string $Month_Key, ?int $Quoted_Price = null): array {
if (!isset(self::PLANS[$Month_Key])) throw new InvalidArgumentException('Invalid checkout');
$Lock = 'subscription_purchase_' . $User_ID;
if (!Repository::tryCronLock($Lock, 180)) throw new RuntimeException('purchase_busy');
try {
$Current = Repository::getUserSession($User_ID);
if (trim((string)($Current['Pending_Payment'] ?? '')) !== '') throw new RuntimeException('payment_pending');
$Price = BotConfig::getPlanPrice($Month_Key);
if ($Quoted_Price !== null && $Quoted_Price !== (int)round($Price)) throw new RuntimeException('price_changed');
$Balance = Repository::getBalance($User_ID);
if ($Price <= 0 || $Balance >= $Price) throw new RuntimeException('wallet_changed');
$Shortage = $Price - $Balance;
if ($Shortage < Environment::getMinimumPaymentAmount()) throw new RuntimeException('below_gateway_minimum');
if (!Zarinpal::isConfigured()) throw new RuntimeException('gateway_unavailable');
$Base = Environment::getPaymentCallbackUrl();
if ($Base === '') throw new RuntimeException('gateway_unavailable');
$User = Repository::getUser($User_ID);
$Callback = $Base . (str_contains($Base, '?') ? '&' : '?') . 'Uid=' . $User_ID;
[$Name] = self::PLANS[$Month_Key];
$Payment = Zarinpal::request($Shortage, $Callback, 'خرید اشتراک ' . $Name . ' - سرور آمبرلا', Helper::normalizePhone((string)($User['Phone'] ?? '')));
if (!is_array($Payment) || !isset($Payment['Authority'], $Payment['RedirectUrl'])) throw new RuntimeException('gateway_request_failed');
$Final = (float)($Payment['Amount'] ?? $Shortage);
Repository::updateUserSession($User_ID, [
'Pending_Plan' => 'paid|' . $Month_Key . '|' . (int)round($Price),
'Pending_Topup' => (string)$Shortage,
'Pending_Custom_Plan' => null,
'Pending_Payment' => $Month_Key . '|' . $Final . '|' . (string)$Payment['Authority'],
]);
$Payment['Plan_Price'] = (int)round($Price);
$Payment['Wallet_Balance'] = (int)round($Balance);
return $Payment;
} finally {
Repository::releaseCronLock($Lock);
}
}

/** Apply a wallet-funded app purchase through the same activation path used by the bot. */
public static function purchaseFromAppWallet(int $User_ID, string $Month_Key, ?int $Quoted_Price = null): array {
if (!isset(self::PLANS[$Month_Key])) throw new InvalidArgumentException('Invalid subscription plan');
$Lock = 'subscription_purchase_' . $User_ID;
if (!Repository::tryCronLock($Lock, 180)) throw new RuntimeException('purchase_busy');
try {
$Price = BotConfig::getPlanPrice($Month_Key);
if ($Quoted_Price !== null && $Quoted_Price !== (int)round($Price)) throw new RuntimeException('price_changed');
$Balance = Repository::getBalance($User_ID);
if ($Price <= 0 || $Balance < $Price) throw new RuntimeException('wallet_changed');
$Pending = trim((string)(Repository::getUserSession($User_ID)['Pending_Payment'] ?? ''));
if ($Pending !== '') throw new RuntimeException('payment_pending');
$User = Repository::getUser($User_ID);
if ($User === []) throw new RuntimeException('Linked bot account not found');
$Before_Expiry = (int)($User['Expiration_Time_Stamp'] ?? 0);
$Chat_ID = (int)(($User['Chat_ID'] ?? 0) ?: $User_ID);
$Context = new Context([], $User_ID, $Chat_ID, (string)(($User['First_Name'] ?? '') ?: 'کاربر'), false, null, null, null, null);
if (!Repository::removeMoney($User_ID, $Price, 'خرید اشتراک - پرداخت از کیف پول', 'app')) throw new RuntimeException('wallet_changed');
try {
self::purchaseUnlocked($Context, 'paid', $Month_Key, true);
} catch (Throwable $Error) {
if (Repository::getBalance($User_ID) <= $Balance - $Price) Repository::addMoney($User_ID, $Price, 'بازگشت وجه اشتراک (خطا در فعالسازی)', 'app');
throw $Error;
}
$After = Repository::getUser($User_ID);
$After_Expiry = (int)($After['Expiration_Time_Stamp'] ?? 0);
$After_Balance = Repository::getBalance($User_ID);
if ($After_Expiry <= $Before_Expiry) {
if ($After_Balance <= $Balance - $Price) Repository::addMoney($User_ID, $Price, 'بازگشت وجه اشتراک (فعال سازی تأیید نشد)', 'app');
throw new RuntimeException('Subscription activation was not confirmed');
}
if ($After_Balance > $Balance - $Price) throw new RuntimeException('Wallet debit was not confirmed');
return ['expires_at' => $After_Expiry, 'balance' => $After_Balance];
} finally {
Repository::releaseCronLock($Lock);
}
}

public static function payPlan(Context $Context): void {
$Month_Key = self::detectPlanKey($Context->CallbackData ?? '');

if ($Month_Key === '') return;
self::purchase($Context, 'paid', $Month_Key);
}

private static function detectPlanKey(string $Data): string {
$Normalized = Helper::toEnglish($Data);
$Keys = array_keys(self::PLANS);
usort($Keys, static fn (string $A, string $B): int => strlen($B) - strlen($A));

foreach ($Keys as $Month) {
if (str_contains($Normalized, (string)$Month)) return (string)$Month;
}

return '';
}

private static function hasAlreadyFree(Context $Context): bool {
$User = Repository::getUser($Context->UserId);
$Client_ID = trim((string)($User['Client_ID'] ?? ''));
$Free_Claimed = (int)($User['Free_Plan_Claimed'] ?? 0) === 1;
$App_Free_Claimed = $Client_ID !== '' && $Client_ID !== '_'
&& trim((string)Repository::getSetting('App_Free_Claimed_' . $Client_ID, '')) === '1';

if ($Free_Claimed || $App_Free_Claimed) {
if (!$Free_Claimed) {
try { Repository::updateUser($Context->UserId, ['Free_Plan_Claimed' => 1]); }
catch (Throwable $Error) { error_log('[Umbrella-Bot][Subscription] app free plan flag sync failed: ' . $Error->getMessage()); }
}
if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '❌اشتراک رایگان را دریافت کرده اید.', true);
}

return true;
}

return false;
}

private static function purchase(Context $Context, string $Type, string $Month_Key = '', bool $Direct_Charge = false): void {
$Lock = 'subscription_purchase_' . $Context->UserId;
if (!Repository::tryCronLock($Lock, 180)) {
if ($Context->CallbackId !== null) TelegramClient::answerCallbackQuery($Context->CallbackId, 'درخواست خرید دیگری در حال پردازش است؛ کمی بعد دوباره تلاش کنید.', true);
return;
}
try {
if ($Type === 'paid' && !$Direct_Charge
&& trim((string)(Repository::getUserSession($Context->UserId)['Pending_Payment'] ?? '')) !== '') {
if ($Context->CallbackId !== null) TelegramClient::answerCallbackQuery($Context->CallbackId, 'یک پرداخت قبلی در حال بررسی است؛ ابتدا همان سفارش را تکمیل کنید.', true);
return;
}
self::purchaseUnlocked($Context, $Type, $Month_Key, $Direct_Charge);
} finally {
Repository::releaseCronLock($Lock);
}
}

private static function purchaseUnlocked(Context $Context, string $Type, string $Month_Key = '', bool $Direct_Charge = false): void {
$Greeting = Common::greet($Context, 'خرید اشتراک');
$Full_Name = $Context->profileName();
$User = Repository::getUser($Context->UserId);
$Phone = (string)($User['Phone'] ?? '');
$Full_Name_Stored = trim((string)($User['Full_Name'] ?? ''));
$Amount = 0;

if ($Phone === '' || $Full_Name_Stored === '') {
if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '⛔️ابتدا پروفایل کاربری را تکمیل کنید.', true);
}

if ($Context->IsCallback && $Context->MessageId !== null) {
TelegramClient::deleteMessage($Context->ChatId, $Context->MessageId);
}

TelegramClient::sendMessage($Context->ChatId, $Greeting . "⛔️برای فعالسازی اشتراک ابتدا باید پروفایل کاربری خود را تکمیل کنید.\n➖➖➖➖➖➖➖➖➖\n⚠️نکته:وارد کردن نام و شماره موبایل معتبر الزامی می باشد.\n👇از دکمه زیر استفاده کنید:" . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
[['text' => '👤ویرایش و ثبت پروفایل', 'callback_data' => 'ویرایش و ثبت پروفایل']],
Menu::userHome(),
]));
return;
}

if ($Type === 'free') {
$Name = '۱ روزه'; $Gb = 1; $Days = 1;
}

elseif ($Type === 'nowruz') {
$Name = 'نوروزی'; $Gb = 5; $Days = 13;
}

else {
[$Name, $Days, $Gb] = self::PLANS[$Month_Key];
$Amount = BotConfig::getPlanPrice($Month_Key);

// A verified/directly charged order must still activate if the tariff was later disabled.
// Unpaid orders must never create a free subscription.
if ($Amount <= 0 && !$Direct_Charge) {
TelegramClient::sendMessage($Context->ChatId, $Greeting . "⚠️این اشتراک هنوز قیمت گذاری نشده است و قابل خرید نیست.\n➖➖➖➖➖➖➖➖➖\n👌لطفاً یکی از اشتراک های دیگر را انتخاب کنید یا با پشتیبانی در تماس باشید." . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
[['text' => '💎خرید اشتراک', 'callback_data' => 'اشتراک آماده']],
Menu::userHome(),
]));
return;
}
}

if ($Type === 'paid' && !$Direct_Charge) {
$Balance = Repository::getBalance($Context->UserId);

if ($Balance >= $Amount) {
if (!Repository::removeMoney($Context->UserId, $Amount, 'خرید اشتراک - پرداخت از کیف پول', 'bot')) {
TelegramClient::sendMessage($Context->ChatId, $Greeting . " *❌خطا: کسر اعتبار از کیف پول ناموفق بود.\n➖➖➖➖➖➖➖➖➖\n⚠️لطفا چند لحظه دیگر با دکمه «تلاش مجدد» اقدام فرمایید." . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
Menu::back('اشتراک آماده', 'اشتراک آماده'),
Menu::userHome()
]));
return;
}

$Direct_Charge = true;
$Need_Gateway_Amount = 0.0;
}

else {
$Need_Gateway_Amount = $Amount - $Balance;
}
}

elseif ($Type !== 'paid') {
Repository::updateUser($Context->UserId, ['Free_Plan_Claimed' => 1]);
}

if ($Type === 'paid' && !$Direct_Charge && $Need_Gateway_Amount > 0) {
$Balance = Repository::getBalance($Context->UserId);
$Balance_Label = Helper::formatCurrency($Balance);
$Min_Payment = Environment::getMinimumPaymentAmount();

if ($Need_Gateway_Amount < $Min_Payment) {
$Shortage = $Min_Payment - $Need_Gateway_Amount;
$Shortage_Label = Helper::formatCurrency($Shortage);
$Min_Label = Helper::formatCurrency($Min_Payment);
TelegramClient::sendMessage($Context->ChatId, $Greeting . " *❌مبلغ قابل پرداخت از درگاه کمتر از حد مجاز است.\n➖➖➖➖➖➖➖➖➖\n⚠️حداقل مبلغ پرداخت از درگاه: *{$Min_Label}*\n💵کسری شما: *{$Shortage_Label}*\n\n👌پیشنهاد می شود اشتراکی با مدت بیشتر انتخاب کنید یا ابتدا کیف پول خود را شارژ کنید." . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
Menu::back('اشتراک آماده', 'اشتراک آماده'),
Menu::userHome()
]));
return;
}

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '⚠️موجودی کیف پول کافی نیست.', true);
}

if ($Context->IsCallback && $Context->MessageId !== null) {
TelegramClient::deleteMessage($Context->ChatId, $Context->MessageId);
}

if (!Zarinpal::isConfigured()) {
$Text = $Greeting . " *🙏با عرض پوزش اعتبار شما کافی نیست.\n➖➖➖➖➖➖➖➖➖\n⚠️برای اشتراک " . Helper::formatCurrency($Amount) . " نیاز دارید.\n\n👛اعتبار کنونی: " . Helper::formatCurrency($Balance) . "*" . Helper::userFooter();
TelegramClient::sendMessage($Context->ChatId, $Text, TelegramClient::inlineKeyboard([
Menu::back('اشتراک آماده', 'اشتراک آماده'),
Menu::userHome()
]));
return;
}

Repository::updateUserSession($Context->UserId, [
'Pending_Plan' => 'paid|' . $Month_Key,
'Pending_Topup' => (string)$Need_Gateway_Amount,
]);

$Direct_Url = '';
$Pre_Payment = null;
$Fee_Label = '';

if (Zarinpal::isConfigured()) {
$Call_Back_Base = Environment::getPaymentCallbackUrl();

if ($Call_Back_Base !== '') {
$Call_Back_Url = $Call_Back_Base . (str_contains($Call_Back_Base, '?') ? '&' : '?') . 'Uid=' . $Context->UserId;
$Pre_Payment = self::preflightGateway($Context, (float)$Need_Gateway_Amount, $Call_Back_Url, 'خرید اشتراک ' . $Name . ' - سرور آمبرلا', Helper::normalizePhone((string)($User['Phone'] ?? '')));

if (is_array($Pre_Payment) && isset($Pre_Payment['Authority'], $Pre_Payment['RedirectUrl'])) {
$Direct_Url = Zarinpal::payLink($Pre_Payment);
$Final_Amount = (float)($Pre_Payment['Amount'] ?? (float)$Need_Gateway_Amount);
$Fee_Label = self::paymentAmount((float)($Pre_Payment['Fee'] ?? ($Final_Amount - (float)$Need_Gateway_Amount)));
Repository::updateUserSession($Context->UserId, ['Pending_Payment' => $Month_Key . '|' . $Final_Amount . '|' . $Pre_Payment['Authority']]);
}
}
}

$Final_Amount_Label = $Final_Amount > 0 ? self::paymentAmount($Final_Amount) : Helper::formatCurrency($Need_Gateway_Amount);
$Pay_Button = $Direct_Url !== ''
? [['text' => '💳پرداخت ' . $Final_Amount_Label . ' از درگاه', 'url' => $Direct_Url]]
: [['text' => '💳پرداخت ' . $Final_Amount_Label . ' از درگاه', 'callback_data' => 'پرداخت کسری کیف پول']];
$Fee_Line = $Fee_Label !== '' ? "├─💸کارمزد: *{$Fee_Label}*\n" : '';
TelegramClient::sendMessage($Context->ChatId, $Greeting . " *⚠️موجودی کیف پول شما برای خرید کافی نیست.*\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "💎*جزئیات پرداخت:*\n"
. "├─🪪اشتراک انتخابی: *{$Name}*\n"
. "├─💰مبلغ کل اشتراک: *" . Helper::formatCurrency($Amount) . "*\n"
. "├─💳موجودی کیف پول: *{$Balance_Label}*\n"
. "├─📉کسری از کیف پول: *" . Helper::formatCurrency($Need_Gateway_Amount) . "*\n"
. $Fee_Line
. "└─🏦مبلغ قابل پرداخت از درگاه: *{$Final_Amount_Label}* (شامل کارمزد خریدار)\n\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "🔄*مراحل تکمیل خرید:*\n"
. "۱. پرداخت از طریق درگاه امن زرین پال\n"
. "۲. شارژ خودکار کیف پول به مبلغ " . Helper::formatCurrency($Need_Gateway_Amount) . "\n"
. "۳. فعالسازی خودکار اشتراک {$Name}\n\n"
. ($Direct_Url !== ''
? "👌برای ورود مستقیم به درگاه پرداخت، روی دکمه زیر کلیک کنید."
: "⚠️نکته: پس از پرداخت موفق، کیف پول شما شارژ و اشتراک {$Name} به صورت خودکار فعال می گردد.") . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
$Pay_Button,
Common::backTo('🔙انصراف', 'اشتراک آماده'),
Menu::userHome()
]));
return;
}

if ($Context->IsCallback) {
TelegramClient::deleteMessage($Context->ChatId, $Context->MessageId);
}

$Client_ID = (string)($User['Client_ID'] ?? '');
$Phone_For_Comment = (string)($User['Phone'] ?? '');
$Full_Name_User = trim((string)($User['Full_Name'] ?? ''));
$Server_Name = $Full_Name_User !== '' ? $Full_Name_User : ('user-' . $Context->UserId);

if ($Client_ID !== '' && $Client_ID !== '_') {
self::renewSubscription($Context, $Name, $Gb, $Days, $Client_ID, $Type);
return;
}

$Response = ServerClient::createUser($Server_Name, (string)$Gb, $Days, $Phone_For_Comment, $Context->UserId);
$Data = $Response['Json'] ?? null;

if (is_array($Data) && ($Response['StatusCode'] ?? 0) < 300 && isset($Data['uuid'])) {
$Gb = max($Gb, (int)round((float)($Data['usage_limit_GB'] ?? 0)));
if ($Type === 'free') {
Repository::updateUser($Context->UserId, ['Free_Plan_Claimed' => 1]);
} elseif ($Type === 'nowruz') {
BotConfig::markNowruzClaimed($Context->UserId, (string)$Data['uuid']);
}
self::activateSubscription($Context, $Data, $Name, $Gb, $Days);
return;
}

if ($Type === 'free') {
Repository::updateUser($Context->UserId, ['Free_Plan_Claimed' => 0]);
}

if ($Type === 'paid') Repository::addMoney($Context->UserId, $Amount, 'بازگشت وجه اشتراک (خطا در فعالسازی)', 'bot');
$Api_Error = '';

if (is_array($Data) && isset($Data['detail'])) {
$Api_Error = json_encode($Data['detail'], JSON_UNESCAPED_UNICODE);
}

elseif ($Response['Body'] !== '' && $Response['Body'] !== null) {
$Api_Error = mb_substr((string)$Response['Body'], 0, 300);
}

AdminFlow::notifyAdminServerError('ایجاد اشتراک', $Context->UserId, $Name, $Response['StatusCode'] ?? 0, $Api_Error);
TelegramClient::sendSystemMessage($Context->ChatId, $Greeting . " *❌اشتراک {$Name} شما فعال نشد.\n\n🔄لطفا چند لحظه دیگر با دکمه «تلاش مجدد» اقدام فرمایید.\n⚠️در صورت ادامه مشکل با پشتیبانی در تماس باشید." . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
[['text' => '📞🧑‍💻ارتباط با پشتیبانی', 'url' => BotConfig::getSupportUrl()]],
[['text' => '🔄تلاش مجدد', 'callback_data' => 'ایجاد کلاینت']],
Menu::userHome()
]));

Repository::updateUserSession($Context->UserId, ['Pending_Plan' => $Type . '|' . $Month_Key]);
}

public static function retryCreation(Context $Context): void {
$Pending = (string)(Repository::getUserSession($Context->UserId)['Pending_Plan'] ?? '');

if ($Pending === '') {
UserFlow::subscriptionsMenu($Context);
return;
}

[$Type, $Month_Key] = array_pad(explode('|', $Pending, 2), 2, '');
Repository::updateUserSession($Context->UserId, ['Pending_Plan' => null]);

if ($Context->IsCallback && $Context->MessageId !== null) {
TelegramClient::deleteMessage($Context->ChatId, $Context->MessageId);
}

if ($Type === 'paid' && $Month_Key !== '') {
self::purchase($Context, 'paid', $Month_Key);
return;
}

self::purchase($Context, $Type === '' ? 'free' : $Type);
}

private static function paymentAmount(float $Toman): string {
$Rial = (int)round($Toman * 10);
return Helper::toPersian(number_format($Rial / 10, $Rial % 10 === 0 ? 0 : 1, '.', '٬')) . ' تومان';
}

private static function paymentSummary(array $Payment): string {
return "💰مبلغ اصلی: " . self::paymentAmount((float)$Payment['Original_Amount'])
. "\n💸کارمزد پرداختی خریدار: " . self::paymentAmount((float)$Payment['Fee'])
. "\n💳جمع پرداخت: " . self::paymentAmount((float)$Payment['Amount'])
. "\nℹ️کارمزد در همین جمع لحاظ شده و نباید در صفحه درگاه دوباره اضافه شود.\n";
}

private static function preflightGateway(Context $Context, float $Amount, string $Callback, string $Description, string $Phone): ?array {
$Payment = Zarinpal::request($Amount, $Callback, $Description, $Phone);
if ($Payment === null) {
TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'پرداخت زرین پال')
. '⚠️ساخت درخواست پرداخت انجام نشد: ' . Zarinpal::requestErrorMessage() . Helper::userFooter());
} else {
TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'پرداخت زرین پال') . self::paymentSummary($Payment) . Helper::userFooter());
}
return $Payment;
}

private static function startGatewayPayment(Context $Context, string $Month_Key, string $Name, float $Amount): void {
$Call_Back_Base = Environment::getPaymentCallbackUrl();

if ($Call_Back_Base === '') {
TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'مدیریت اشتراک') . "⚠️درگاه پرداخت هنوز پیکربندی نشده است. لطفا بعدا تلاش کنید." . Helper::userFooter(), TelegramClient::inlineKeyboard([Menu::userHome()]));
return;
}

if ($Context->IsCallback && $Context->MessageId !== null) {
try { TelegramClient::deleteMessage($Context->ChatId, $Context->MessageId); } catch (Throwable) {}
}

$User = Repository::getUser($Context->UserId);
$Phone = (string)($User['Phone'] ?? '');
$Call_Back_Url = $Call_Back_Base . (str_contains($Call_Back_Base, '?') ? '&' : '?') . 'Uid=' . $Context->UserId;
$Payment = Zarinpal::request($Amount, $Call_Back_Url, 'خرید اشتراک ' . $Name . ' - سرور آمبرلا', Helper::normalizePhone($Phone));

if ($Payment === null) {
TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'مدیریت اشتراک') . "❌خطا: اتصال به درگاه پرداخت ناموفق بود.\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "⚠️علت: " . Zarinpal::requestErrorMessage() . "\n"
. "🔄لطفا چند لحظه دیگر با دکمه «تلاش مجدد» اقدام فرمایید.\n"
. "📞در صورت ادامه مشکل با پشتیبانی تماس بگیرید." . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
[['text' => '🔄تلاش مجدد', 'callback_data' => 'پرداخت کسری کیف پول']],
Menu::back('مدیریت اشتراک', 'user_subscriptions_menu'),
Menu::userHome(),
]));
return;
}

$Final_Amount = (float)($Payment['Amount'] ?? $Amount);
Repository::updateUserSession($Context->UserId, ['Pending_Payment' => $Month_Key . '|' . $Final_Amount . '|' . $Payment['Authority']]);
TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'پرداخت زرین پال') . "➖➖➖➖➖➖➖➖➖\n💎اشتراک انتخابی: {$Name}\n" . self::paymentSummary($Payment) . "\n➖➖➖➖➖➖➖➖➖\n👌برای تکمیل خرید بر روی دکمه پرداخت کلیک کنید.\n⚠️نکته:پس از بازگشت از درگاه،اشتراک شما به صورت خودکار فعال می گردد." . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
[['text' => '💳پرداخت امن', 'url' => Zarinpal::payLink($Payment)]],
[['text' => '✅بررسی پرداخت', 'callback_data' => 'بررسی پرداخت']],
Menu::userHome(),
]));
}

/**
 * تسویه خودکار سفارش درگاه برای کاربری که از ربات برنگشته است.
 * اگر پرداخت هنوز انجام نشده باشد هیچ پیامی برای کاربر نمی فرستد.
 */
public static function recoverPendingPayment(int $User_ID): bool {
if ($User_ID <= 0) return false;

try {
$Session = Repository::getUserSession($User_ID);
}

catch (Throwable) {
return false;
}

$Pending_Payment = (string)($Session['Pending_Payment'] ?? '');

if ($Pending_Payment === '') return false;

$Parts = array_pad(explode('|', $Pending_Payment, 3), 3, '');
$Amount = (float)$Parts[1];
$Authority = $Parts[2];

if ($Amount <= 0 || $Authority === '' || !Zarinpal::isConfigured()) return false;

try {
$Verify = Zarinpal::verify($Amount, $Authority);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Payment-Recovery] verify failed | User=' . $User_ID . ' | ' . $Error->getMessage());
return false;
}

// تا وقتی درگاه تایید نکند هیچ اتفاقی نمی افتد (بدون پیام برای کاربر).
if (empty($Verify['Ok'])) return false;

$User = Repository::getUser($User_ID);
$Chat_ID = (int)($User['Chat_ID'] ?? $User_ID);
$First_Name = (string)(($User['First_Name'] ?? '') ?: 'کاربر');
$Context = new Context([], $User_ID, $Chat_ID ?: $User_ID, $First_Name, false, null, null, null, null);

return self::settleGatewayPayment($Context, $Pending_Payment, $Verify, $Session);
}

private static function settleGatewayPayment(Context $Context, ?string $Expected_Payment = null, ?array $Verified = null, ?array $Expected_Session = null): bool {
$Session = Repository::getUserSession($Context->UserId);
$Pending_Payment = (string)($Session['Pending_Payment'] ?? '');
// A new order may have replaced this one while verify was in flight.
if ($Expected_Payment !== null && $Expected_Payment !== $Pending_Payment) return false;
if ($Expected_Session !== null) {
foreach (['Pending_Topup', 'Pending_Plan', 'Pending_Custom_Plan'] as $Key) {
if ((string)($Expected_Session[$Key] ?? '') !== (string)($Session[$Key] ?? '')) return false;
}
}
$Pending_Plan = (string)($Session['Pending_Plan'] ?? '');
$Pending_Custom = (string)($Session['Pending_Custom_Plan'] ?? '');
$Pending_Topup = (string)($Session['Pending_Topup'] ?? '');

if ($Pending_Payment === '') {
TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'بررسی پرداخت') . "❌خطا: سفارش پرداخت فعالی یافت نشد.\n➖➖➖➖➖➖➖➖➖\nℹ️ممکن است سفارش قبلاً پردازش شده باشد؛ موجودی و اشتراک خود را بررسی کنید." . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
[['text' => '💳خرید و تمدید اشتراک', 'callback_data' => 'user_subscriptions_menu']],
Menu::userHome(),
]));
return false;
}

$Parts = array_pad(explode('|', $Pending_Payment, 3), 3, '');
$Payment_Type = $Parts[0];
$Amount = (float)$Parts[1];
$Authority = $Parts[2];

if (!Zarinpal::isConfigured() || $Authority === '' || $Amount <= 0) {
return false;
}

$Verify = $Verified ?? Zarinpal::verify($Amount, $Authority);

if (!$Verify['Ok']) {
$Code = (int)($Verify['Code'] ?? 0);
$Reason = self::zarinpalErrorMessage($Code);
if ($Code === Zarinpal::CODE_NOT_PAID) {
TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'بررسی پرداخت')
. "⏳پرداخت این سفارش هنوز توسط درگاه تأیید نشده است.
"
. "اگر پرداخت را انجام نداده اید از دکمه پرداخت استفاده کنید. اگر مبلغ کسر شده، دوباره پرداخت نکنید؛ کمی بعد بررسی مجدد را بزنید و در صورت ادامه مشکل با پشتیبانی تماس بگیرید."
. Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '💳ادامه پرداخت', 'url' => Zarinpal::payLink(['BridgeUrl' => Zarinpal::bridgeUrl($Authority, $Context->UserId), 'RedirectUrl' => Zarinpal::startPayUrl($Authority)])]],
[['text' => '✅بررسی مجدد پرداخت', 'callback_data' => 'بررسی پرداخت']],
Menu::userHome(),
]));
return false;
}

TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'بررسی پرداخت') . "⚠️تأیید پرداخت انجام نشد.\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "⚠️علت: {$Reason}\n"
. "⚠️اگر مبلغ کسر شده، دوباره پرداخت نکنید؛ بررسی مجدد یا پیگیری از پشتیبانی لازم است.\n"
. "🧾کد خطا: `" . Helper::toPersian((string)$Code) . "`" . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
[['text' => '✅بررسی مجدد پرداخت', 'callback_data' => 'بررسی پرداخت']],
Menu::back('مدیریت اشتراک', 'user_subscriptions_menu'),
Menu::userHome(),
]));
return false;
}

$Topup_Amount = $Pending_Topup !== '' ? (float)$Pending_Topup : 0.0;

try {
if (!Repository::settleGatewayFunds($Context->UserId, $Session, $Amount, (string)($Verify['RefId'] ?? ''), $Topup_Amount)) return false;
} catch (Throwable $Error) {
error_log('[Umbrella-Bot][Payment-Settlement] User=' . $Context->UserId . ' | ' . $Error->getMessage());
TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'بررسی پرداخت')
. '⚠️درگاه پرداخت را تأیید کرده اما ثبت داخلی کامل نشد. دوباره پرداخت نکنید؛ بررسی مجدد پرداخت را بزنید یا با پشتیبانی تماس بگیرید.'
. Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '✅بررسی مجدد پرداخت', 'callback_data' => 'بررسی پرداخت']], Menu::userHome(),
]));
return false;
}
$Success_Notes = [];
if ($Topup_Amount > 0) $Success_Notes[] = "💳شارژ کیف پول: " . Helper::formatCurrency($Topup_Amount);

$Plan_Name = 'اشتراک';
$Is_Custom = false;
$Custom_Days = 0;
$Custom_GB = 0.0;
$Force_Custom = ($Payment_Type === 'custom');

if ($Force_Custom) {
$Is_Custom = true;

if ($Pending_Custom !== '') {
$CParts = array_pad(explode('|', $Pending_Custom, 3), 3, '0');
$Custom_Days = (int)$CParts[0];
$Custom_GB = (float)$CParts[2];
}

if ($Custom_Days <= 0) {
$Custom_Days = (int)round(((float)$Amount) / max(1.0, BotConfig::getCustomDayRate()));
}

$Plan_Name = "اشتراک " . Helper::toPersian((string)$Custom_Days) . " روزه";

if ($Custom_GB > 0) {
$Plan_Name .= " - " . Helper::formatGB($Custom_GB);
}
}

elseif ($Pending_Custom !== '') {
$CParts = array_pad(explode('|', $Pending_Custom, 3), 3, '0');
$Custom_Days = (int)$CParts[0];
$Custom_GB = (float)$CParts[2];
$Plan_Name = "اشتراک " . Helper::toPersian((string)$Custom_Days) . " روزه";

if ($Custom_GB > 0) {
$Plan_Name .= " - " . Helper::formatGB($Custom_GB);
}

$Is_Custom = true;
}

elseif ($Pending_Plan !== '' && str_starts_with($Pending_Plan, 'paid|')) {
[, $Plan_Month] = explode('|', $Pending_Plan, 3);

if (isset(self::PLANS[$Plan_Month])) {
$Plan_Name = self::PLANS[$Plan_Month][0];
}
}

$Wallet_Balance = (float)(Repository::getUser($Context->UserId)['Balance'] ?? 0);
$Is_Pure_Topup = ($Topup_Amount > 0 && !$Is_Custom && $Pending_Plan === '');
// The gateway is only asked for the shortfall (price - wallet balance), so the
// rest of the price is still owed by the wallet. Without this charge the user
// would keep the balance the plan was supposed to consume.
$Wallet_Share = 0.0;

if ($Is_Custom && $Pending_Custom !== '') {
$Wallet_Parts = array_pad(explode('|', $Pending_Custom, 3), 3, '0');
$Wallet_Share = max(0.0, (float)$Wallet_Parts[1]);
}

elseif ($Pending_Plan !== '' && str_starts_with($Pending_Plan, 'paid|')) {
[, $Wallet_Month, $Order_Price] = array_pad(explode('|', $Pending_Plan, 3), 3, '');
// New app orders retain their original server tariff; legacy bot orders fall back to the current tariff.
$Wallet_Share = $Order_Price !== '' ? max(0.0, (float)$Order_Price) : max(0.0, (float)BotConfig::getPlanPrice($Wallet_Month));
}

$Wallet_Charged = 0.0;

if (!$Is_Pure_Topup) {
$Charge_From_Wallet = ($Topup_Amount > 0 && $Wallet_Share > 0);

if ($Charge_From_Wallet) {
$Charged = false;

try {
$Charged = Repository::removeMoney($Context->UserId, $Wallet_Share, 'خرید اشتراک - تسویه با کیف پول', 'bot');
}

catch (Throwable $Charge_Error) {
error_log('[Umbrella-Bot][Payment-Wallet] خطا در کسر سهم کیف پول: ' . $Charge_Error->getMessage());
}

if ($Charged) {
$Wallet_Charged = $Wallet_Share;
$Wallet_Balance = max(0.0, $Wallet_Balance - $Wallet_Share);
}

else {
error_log('[Umbrella-Bot][Payment-Wallet] کسر ' . $Wallet_Share . ' تومان از کیف پول کاربر ' . $Context->UserId . ' انجام نشد؛ بررسی دستی لازم است.');
TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'بررسی پرداخت')
. '⚠️پرداخت درگاه ثبت شد، اما کسر هزینه اشتراک از کیف پول انجام نشد؛ اشتراک فعال نشد. دوباره از درگاه پرداخت نکنید و موجودی را بررسی یا با پشتیبانی پیگیری کنید.'
. Helper::userFooter(), TelegramClient::inlineKeyboard([Menu::userHome()]));
return false;
}
}

else {
try {
Repository::addSpent($Context->UserId, (float)$Amount);
}

catch (Throwable) {}
}
}

$Payment_Type_Label = $Is_Pure_Topup
? '💳شارژ کیف پول'
: '💎خرید اشتراک (درگاه زرین پال)';
$Ref_Label = Helper::toPersian((string)$Verify['RefId']);
$Card_Label = $Verify['CardPan'] !== '' ? Helper::toPersian((string)$Verify['CardPan']) : '';
TelegramClient::sendSystemMessage($Context->ChatId, Common::greet($Context, 'پرداخت زرین پال') . "✅پرداخت شما با موفقیت انجام شد.\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "🧾نوع تراکنش: {$Payment_Type_Label}\n"
. "🧾کد رهگیری: `{$Ref_Label}`\n"
. ($Card_Label !== '' ? "💳شماره کارت: `{$Card_Label}`\n" : '')
. "💰مبلغ پرداختی: " . Helper::formatCurrency((float)$Amount) . "\n"
. ($Topup_Amount > 0 ? "💳شارژ کیف پول: " . Helper::formatCurrency($Topup_Amount) . "\n" : '')
. ($Topup_Amount > 0 ? "💵موجودی کیف پول: " . Helper::formatCurrency($Wallet_Balance) . "\n" : '')
. ($Wallet_Charged > 0 ? "💳کسر از کیف پول: " . Helper::formatCurrency($Wallet_Charged) . "\n" : '')
. (count($Success_Notes) > 0 ? implode("\n", $Success_Notes) . "\n" : '')
. ($Is_Custom ? "📅مدت اشتراک: " . Helper::toPersian((string)$Custom_Days) . " روز\n" : '')
. ($Is_Pure_Topup ? "✅اعتبار کیف پول شما با موفقیت شارژ شد." : "🔄در حال فعالسازی {$Plan_Name}...") . Helper::userFooter() . "*",
TelegramClient::inlineKeyboard([
Common::backTo('👤پروفایل کاربری', 'پروفایل کاربری'),
Menu::userHome(),
]));

$User_For_Admin = Repository::getUser($Context->UserId);
$Phone_Admin = (string)($User_For_Admin['Phone'] ?? '');
$Phone_Admin_Label = $Phone_Admin !== '' ? Helper::toPersian($Phone_Admin) : '';
$Admin_Text = Helper::adminGreetingNamed((string)(Repository::getSetting('Admin_Full_Name') ?: Environment::getAdminFullName()), 'گزارش پرداخت', (int)Repository::getSetting('Administrator', (string)Environment::getAdminUserId())) . "💳✅پرداخت موفق زرین پال\n\n"
. "👤کاربر: [{$Context->profileName()}](tg://user?id={$Context->UserId})\n"
. "🆔آیدی: `" . Helper::toPersian($Context->UserId) . "`\n"
. ($Phone_Admin_Label !== '' ? "📞موبایل: `{$Phone_Admin_Label}`\n" : '')
. "💎اشتراک: {$Plan_Name}\n"
. "💰مبلغ: " . Helper::formatCurrency((float)$Amount) . "\n"
. "🧾کد رهگیری: `{$Ref_Label}`\n"
. ($Card_Label !== '' ? "💳کارت: `{$Card_Label}`\n" : '')
. ""
. "➖➖➖➖➖➖➖➖➖\n"
. "*🔄اشتراک {$Plan_Name} در حال فعال سازی...*"
. Helper::adminFooter();
$Admin_ID = (int)Repository::getSetting('Administrator', (string)Environment::getAdminUserId());

if ($Admin_ID <= 0) $Admin_ID = Environment::getAdminUserId();
if ($Admin_ID > 0) {
try {
$Admin_Text = Helper::adminGreetingNamed((string)(Repository::getSetting('Admin_Full_Name') ?: Environment::getAdminFullName()), 'گزارش پرداخت', $Admin_ID) . "💳✅پرداخت موفق زرین پال\n\n"
. "👤کاربر: [{$Context->profileName()}](tg://user?id={$Context->UserId})\n"
. "🆔آیدی: `" . Helper::toPersian($Context->UserId) . "`\n"
. ($Phone_Admin_Label !== '' ? "📞موبایل: `{$Phone_Admin_Label}`\n" : '')
. ($Is_Pure_Topup ? "🧾نوع تراکنش:💳شارژ اعتبار کیف پول\n" : "💎اشتراک: {$Plan_Name}\n")
. "💰مبلغ: " . Helper::formatCurrency((float)$Amount) . "\n"
. ($Topup_Amount > 0 ? "💳شارژ کیف پول: " . Helper::formatCurrency($Topup_Amount) . "\n" : '')
. ($Is_Pure_Topup ? "💵موجودی جدید کیف پول: " . Helper::formatCurrency($Wallet_Balance) . "\n" : '')
. "🧾کد رهگیری: `{$Ref_Label}`\n"
. ($Card_Label !== '' ? "💳کارت: `{$Card_Label}`\n" : '')
. "➖➖➖➖➖➖➖➖➖\n"
. ($Is_Pure_Topup ? "*✅اعتبار کیف پول کاربر شارژ شد.*" : "*🔄اشتراک {$Plan_Name} در حال فعال سازی...*")
. Helper::adminFooter();

$Admin_Result = TelegramClient::sendSystemMessage($Admin_ID, $Admin_Text);

if (!is_array($Admin_Result) || ($Admin_Result['ok'] ?? false) !== true) {
error_log('[Umbrella-Bot][Payment-Notify] ارسال گزارش پرداخت موفق به ادمین ناموفق | Admin=' . $Admin_ID . ' Response=' . json_encode($Admin_Result, JSON_UNESCAPED_UNICODE));
}
}

catch (Throwable $E) {
error_log('[Umbrella-Bot][Payment-Notify] خطا در ارسال گزارش پرداخت به ادمین: ' . $E->getMessage());
}
}

if ($Is_Custom) {
self::activateCustom($Context, $Plan_Name, $Custom_Days, (float)($Custom_GB ?? 0));
return true;
}

if ($Pending_Plan !== '' && str_starts_with($Pending_Plan, 'paid|')) {
[, $Plan_Month] = explode('|', $Pending_Plan, 3);
self::purchase($Context, 'paid', $Plan_Month, true);
return true;
}

if ($Pending_Custom !== '') {
$CParts = array_pad(explode('|', $Pending_Custom, 3), 3, '0');
$Custom_Days_FB = (int)$CParts[0];
$Custom_GB_FB = (float)$CParts[2];

if ($Custom_Days_FB > 0) {
$Name_FB = "اشتراک " . Helper::toPersian((string)$Custom_Days_FB) . " روزه";

if ($Custom_GB_FB > 0) {
$Name_FB .= " - " . Helper::formatGB($Custom_GB_FB);
}

self::activateCustom($Context, $Name_FB, $Custom_Days_FB, $Custom_GB_FB);
return true;
}
}

return true;
}

private static function zarinpalErrorMessage(int $Code): string {
return Zarinpal::errorMessage($Code);
}

public static function payTopup(Context $Context): void {
self::withPurchaseLock($Context, static function () use ($Context): void {
self::payTopupUnlocked($Context);
});
}

private static function payTopupUnlocked(Context $Context): void {
$Greeting = Common::greet($Context, 'شارژ کیف پول');
$Session = Repository::getUserSession($Context->UserId);
$Pending_Topup = (string)($Session['Pending_Topup'] ?? '');
$Pending_Plan = (string)($Session['Pending_Plan'] ?? '');
$Pending_Custom = (string)($Session['Pending_Custom_Plan'] ?? '');

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🔄در حال انتقال به درگاه پرداخت...', false);
}

if ($Pending_Topup === '' || ($Pending_Plan === '' && $Pending_Custom === '')) {
if ($Context->IsCallback && $Context->MessageId !== null) {
try { TelegramClient::deleteMessage($Context->ChatId, $Context->MessageId); } catch (Throwable) {}
}

TelegramClient::sendMessage($Context->ChatId, $Greeting . "⛔️جلسه پرداخت منقضی شده است یا نامعتبر است.\n⚠️لطفا دوباره از بخش مدیریت اشتراک پلن خود را انتخاب کنید." . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
[['text' => '💎انتخاب اشتراک', 'callback_data' => 'user_subscriptions_menu']],
Menu::userHome()
]));

return;
}

if ($Pending_Custom !== '') {
$Custom = self::purchaseCustomDirect($Context, $Pending_Custom, (float)$Pending_Topup);

if ($Custom['Url'] !== '') {
if ($Context->IsCallback && $Context->MessageId !== null) {
try { TelegramClient::deleteMessage($Context->ChatId, $Context->MessageId); } catch (Throwable) {}
}

TelegramClient::sendMessage($Context->ChatId, $Greeting . " *برای پرداخت از دکمه زیر استفاده کنید.*" . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
[['text' => '💳پرداخت امن', 'url' => $Custom['Url']]],
[['text' => '✅بررسی پرداخت', 'callback_data' => 'بررسی پرداخت']], Menu::userHome(),
]));
}

return;
}

[, $Month_Key] = explode('|', $Pending_Plan, 3);
self::startGatewayPayment($Context, $Month_Key, self::PLANS[$Month_Key][0] ?? 'اشتراک', (float)$Pending_Topup);
}

private static function purchaseCustomDirect(Context $Context, string $Pending_Custom, float $Topup_Amount): array {
$User = Repository::getUser($Context->UserId);
$Phone = (string)($User['Phone'] ?? '');
$Parts = array_pad(explode('|', $Pending_Custom, 3), 3, '0');
$Days = (int)$Parts[0];
$Amount = (float)$Parts[1];
$GB = (float)$Parts[2];
$Need = $Topup_Amount;

if (!Zarinpal::isConfigured() || $Phone === '' || $Need <= 0) {
return ['Url' => ''];
}

$Call_Back_Base = Environment::getPaymentCallbackUrl();
$Call_Back_Url = $Call_Back_Base . (str_contains($Call_Back_Base, '?') ? '&' : '?') . 'Uid=' . $Context->UserId;
$Pre = self::preflightGateway($Context, $Need, $Call_Back_Url, 'خرید اشتراک دلخواه - سرور آمبرلا', Helper::normalizePhone($Phone));

if (is_array($Pre) && isset($Pre['Authority'], $Pre['RedirectUrl'])) {
$Final_Amount = (float)($Pre['Amount'] ?? $Need);
Repository::updateUserSession($Context->UserId, [
'Pending_Custom_Plan' => $Days . '|' . $Amount . '|' . $GB,
'Pending_Payment' => 'custom|' . $Final_Amount . '|' . $Pre['Authority'],
'Pending_Plan' => null,
]);

return ['Url' => Zarinpal::payLink($Pre)];
}

return ['Url' => ''];
}

public static function walletTopupStart(Context $Context): void {
$User = Repository::getUser($Context->UserId);
$Balance = (float)($User['Balance'] ?? 0);
Repository::updateUserSession($Context->UserId, ['Flow' => 'wallet_topup_amount']);
$Text = Common::greet($Context, 'شارژ اعتبار حساب کاربری')
. "💰موجودی فعلی کیف پول: " . Helper::formatCurrency($Balance) . "\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "👌لطفاً مبلغ شارژ مورد نظر را به *تومان* وارد کرده و ارسال کنید.\n"
. "⚠️حداقل مبلغ شارژ: " . Helper::formatCurrency((float)self::MIN_TOPUP) . "\n"
. "💳پس از ثبت مبلغ، به درگاه امن زرین پال هدایت می شوید.\n"
. "💡نکته: مبلغ وارد شده به عنوان اعتبار کیف پول شما ثبت می گردد و کارمزد دقیق از زرین پال استعلام و پیش از پرداخت به مبلغ اضافه می شود؛ کارمزد به اعتبار کیف پول اضافه نمی شود."
. Helper::userFooter();

TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard([
[['text' => '🔙انصراف از شارژ', 'callback_data' => 'لغو شارژ اعتبار']],
Menu::back('منوی قبلی', 'user_wallet_menu'), Menu::userHome(),
]));
}

public static function handleWalletTopupInput(Context $Context, string $Text): void {
self::withPurchaseLock($Context, static function () use ($Context, $Text): void {
self::handleWalletTopupInputUnlocked($Context, $Text);
});
}

private static function handleWalletTopupInputUnlocked(Context $Context, string $Text): void {
$Digits = Helper::toEnglish($Text);
$Amount = (float)preg_replace('/[^0-9]/', '', $Digits);
$Greeting = Common::greet($Context, 'شارژ اعتبار حساب کاربری');

if ($Amount <= 0) {
TelegramClient::sendMessage($Context->ChatId, $Greeting . "❌خطا: مبلغ وارد شده نامعتبر است.\n➖➖➖➖➖➖➖➖➖\n⚠️علت: فقط عدد به تومان وارد کنید مانند: `۱۰۰۰۰۰`\n👌مجددا مبلغ را ارسال کنید." . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
[['text' => '🔙انصراف از شارژ', 'callback_data' => 'لغو شارژ اعتبار']],
Menu::userHome(),
]));
return;
}

if ($Amount < (float)self::MIN_TOPUP) {
TelegramClient::sendMessage($Context->ChatId, $Greeting . "❌خطا: مبلغ وارد شده کمتر از حد مجاز است.\n➖➖➖➖➖➖➖➖➖\n⚠️حداقل مبلغ شارژ: " . Helper::formatCurrency((float)self::MIN_TOPUP) . "\n📥مبلغ وارد شده: " . Helper::formatCurrency($Amount) . "\n👌مجدداً مبلغ صحیح را ارسال کنید." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔙انصراف از شارژ', 'callback_data' => 'لغو شارژ اعتبار']],
Menu::userHome(),
]));
return;
}

Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Pending_Topup' => (string)$Amount]);
self::startWalletGateway($Context, $Amount);
}

public static function walletTopupCancel(Context $Context): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '❌عملیات شارژ اعتبار لغو شد.', false);
}

UserFlow::walletMenu($Context);
}

private static function startWalletGateway(Context $Context, float $Amount): void {
$Call_Back_Base = Environment::getPaymentCallbackUrl();
$Greeting = Common::greet($Context, 'شارژ اعتبار حساب کاربری');

if ($Call_Back_Base === '') {
TelegramClient::sendMessage($Context->ChatId, $Greeting . "⚠️درگاه پرداخت هنوز پیکربندی نشده است. لطفا بعدا تلاش کنید." . Helper::userFooter(), TelegramClient::inlineKeyboard([Menu::userHome()]));
return;
}

$User = Repository::getUser($Context->UserId);
$Phone = (string)($User['Phone'] ?? '');
$Call_Back_Url = $Call_Back_Base . (str_contains($Call_Back_Base, '?') ? '&' : '?') . 'Uid=' . $Context->UserId;
$Payment = Zarinpal::request($Amount, $Call_Back_Url, 'شارژ اعتبار کیف پول - سرور آمبرلا', Helper::normalizePhone($Phone));

if ($Payment === null) {
TelegramClient::sendMessage($Context->ChatId, $Greeting . "❌خطا: اتصال به درگاه پرداخت ناموفق بود.\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "⚠️علت: " . Zarinpal::requestErrorMessage() . "\n"
. "🔄لطفا چند لحظه دیگر با دکمه «تلاش مجدد» اقدام فرمایید.\n"
. "📞در صورت ادامه مشکل با پشتیبانی تماس بگیرید." . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
[['text' => '🔄تلاش مجدد', 'callback_data' => 'شارژ اعتبار حساب کاربری']],
Menu::userHome(),
]));
return;
}

$Final_Amount = (float)($Payment['Amount'] ?? $Amount);
Repository::updateUserSession($Context->UserId, [
'Pending_Payment' => 'topup|' . $Final_Amount . '|' . $Payment['Authority'],
'Pending_Topup' => (string)$Amount,
'Pending_Plan' => null,
'Pending_Custom_Plan' => null,
]);

TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'پرداخت زرین پال') . "➖➖➖➖➖➖➖➖➖\n💳شارژ اعتبار کیف پول\n💰مبلغ شارژ: " . Helper::formatCurrency($Amount) . "\n" . self::paymentSummary($Payment) . "\n➖➖➖➖➖➖➖➖➖\n👌برای تکمیل شارژ بر روی دکمه پرداخت کلیک کنید.\n⚠️نکته:پس از بازگشت از درگاه، اعتبار شما به صورت خودکار شارژ می گردد." . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
[['text' => '💳پرداخت امن', 'url' => Zarinpal::payLink($Payment)]],
[['text' => '✅بررسی پرداخت', 'callback_data' => 'بررسی پرداخت']],
Menu::userHome(),
]));
}

public static function verifyPayment(Context $Context): void {
self::settleGatewayPayment($Context);
}

public static function handleGatewayCallback(int $User_ID, string $Status, string $Authority): void {
if ($User_ID <= 0 || !Zarinpal::validAuthority($Authority) || !in_array(strtoupper($Status), ['OK', 'NOK'], true)) return;
$Pending = (string)(Repository::getUserSession($User_ID)['Pending_Payment'] ?? '');
$Parts = array_pad(explode('|', $Pending, 3), 3, '');
// Ignore replayed/foreign callbacks; never verify a different current order.
if ($Pending === '' || !hash_equals($Parts[2], $Authority)) return;
$User = Repository::getUser($User_ID);
$Chat_ID = (int)($User['Chat_ID'] ?? $User_ID);
$First_Name = (string)(($User['First_Name'] ?? '') ?: 'کاربر');
$Full_Name = trim((string)($User['Full_Name'] ?? ''));
$Display_Name = $Full_Name !== '' ? $Full_Name : $First_Name;
$Phone = (string)($User['Phone'] ?? '');
$Admin = (int)Repository::getSetting('Administrator', (string)Environment::getAdminUserId());
$Phone_Label = $Phone !== '' ? Helper::toPersian($Phone) : '';
$User_Label = "👤کاربر: [{$Display_Name}](tg://user?id={$User_ID})\n🆔آیدی: `" . Helper::toPersian($User_ID) . "`" . ($Phone_Label !== '' ? "\n📞موبایل: `{$Phone_Label}`" : '');

if (strtoupper($Status) !== 'OK') {
TelegramClient::sendSystemMessage($Chat_ID, Helper::frame('کاربر', $Display_Name, 'پرداخت زرین پال', $User_ID) . "⚠️بازگشت از درگاه با وضعیت ناموفق یا لغوشده دریافت شد.\n➖➖➖➖➖➖➖➖➖\n⚠️اگر وجه کسر شده، دوباره پرداخت نکنید؛ وضعیت را از درگاه یا پشتیبانی پیگیری کنید." . Helper::userFooter(), TelegramClient::inlineKeyboard([Menu::userHome()]));
$Admin_Text = Helper::adminGreetingNamed((string)(Repository::getSetting('Admin_Full_Name') ?: Environment::getAdminFullName()), 'گزارش پرداخت', $Admin) . "❌پرداخت ناموفق / لغو شده توسط کاربر\n\n"
. "👤کاربر: [{$Display_Name}](tg://user?id={$User_ID})\n"
. "🆔آیدی: `" . Helper::toPersian($User_ID) . "`\n"
. ($Phone_Label !== '' ? "📞موبایل: `{$Phone_Label}`\n" : '')
. "🚦وضعیت: *ناموفق*\n"
. ""
. "➖➖➖➖➖➖➖➖➖\n"
. "⚠️کاربر پرداخت را لغو کرده یا تراکنش ناموفق بوده است."
. Helper::adminFooter();
TelegramClient::sendSystemMessage($Admin, $Admin_Text, TelegramClient::inlineKeyboard([
[['text' => '👁👤مشاهده کاربر', 'url' => 'tg://user?id=' . $User_ID]],
]));
return;
}

$Context = new Context([], $User_ID, $Chat_ID, $First_Name, false, null, null, null, null);
self::settleGatewayPayment($Context, $Pending);
}

private static function activateSubscription(Context $Context, array $Data, string $Name, int $Gb, int $Days): void {
$User_ID = $Context->UserId;
$Tehran = new DateTimeZone('Asia/Tehran');
$Now_Tehran = new DateTimeImmutable('now', $Tehran);
$Expire_DateTime = $Now_Tehran->modify('+' . $Days . ' days');
$Expire_Time_Stamp = $Expire_DateTime->getTimestamp();
$Expiration_Text = Helper::formatExpiration($Expire_Time_Stamp);
$Package_Start = Helper::formatPersianDate($Now_Tehran->getTimestamp());
$Full_Name = $Context->profileName();
$User = Repository::getUser($User_ID);
$Phone = (string)($User['Phone'] ?? '');
$Admin = (int)Repository::getSetting('Administrator', (string)Environment::getAdminUserId());

Repository::updateUser($User_ID, [
'Client_ID'  => (string)($Data['uuid'] ?? ''),
'Subscription'  => $Name,
'Package_Duration'   => self::durationLabel($Days),
'Package_Start_Date'  => $Package_Start,
'Expiration_Date'=> $Expiration_Text,
'Expiration_Time_Stamp'   => $Expire_Time_Stamp,
'Total_Usage_GB'  => (float)$Gb,
'Used_Usage_GB'   => 0.0,
'Remaining_Usage_GB'  => (float)$Gb,
'Percent_Usage'  => 0.0,
'Client_Status'  => 'فعال',
'Channel_Client_Disabled_At' => null,
'ED_25519_Private_Key' => (string)($Data['ed25519_private_key'] ?? '-'),
'ED_25519_Public_Key'  => (string)($Data['ed25519_public_key'] ?? '-'),
'WireGuard_Private_Key'   => (string)($Data['wg_pk'] ?? '-'),
'WireGuard_Public_Key'=> (string)($Data['wg_pub'] ?? '-'),
]);

if ($Full_Name !== '' && $Phone !== '') {
ServerClient::updateUser((string)($Data['uuid'] ?? ''), [
'name' => $Full_Name,
'comment' => $Phone,
]);
}

$Greeting = Common::greet($Context, 'فعالسازی اشتراک');

TelegramClient::sendSystemMessage($Context->ChatId, "🎁{$Greeting} *اشتراک {$Name} شما با موفقیت فعال گردید." . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
[['text' => '👤پروفایل کاربری', 'callback_data' => 'پروفایل کاربری']],
Menu::userHome()
]));

Repository::seedUsageSnapshot($Context->UserId);
Repository::addSubscriptionLog($Context->UserId, 'activate', $Name, $Days, (float)$Gb, isset($Data['uuid']) ? $Data['uuid'] : null, 'user', $Context->UserId);

TelegramClient::sendSystemMessage($Admin, Helper::adminGreetingNamed((string)(Repository::getSetting('Admin_Full_Name') ?: Environment::getAdminFullName()), 'فعالسازی اشتراک', $Admin) . "🎁✅لحظاتی پیش اشتراک {$Name} فعال گردید.\n👤نام: " . Helper::mention((string)$Full_Name, (int)$User_ID) . "\n📞شماره موبایل: {$Phone} (" . Helper::detectOperator($Phone) . ")\n🆔آیدی: `" . Helper::toPersian($User_ID) . "`\n🚀شناسه کلاینت: `" . ($Data['uuid'] ?? '') . "`\n📆تاریخ انقضا:\n{$Expiration_Text}" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '👁👤مشاهده کاربر', 'url' => 'tg://user?id=' . $User_ID]],
]));

if (Helper::validatePhone($Phone)) {
$Plan = Helper::smsPlan($Name);
$Template = Repository::getSmsTemplate('activate');
$Sms_Text = $Template !== null
? strtr($Template, ['{full_name}' => $Full_Name, '{plan}' => $Plan, '{remaining}' => Helper::durationLabel($Days)])
: "{$Full_Name} گرامی 🎉اشتراک {$Plan} شما با موفقیت فعال گردید.\n⏳مدت اعتبار: " . Helper::durationLabel($Days) . "\n\nسرور آمبرلا";
\IppanelClient::sendOnce($User_ID, $Phone, $Sms_Text, IppanelClient::subscriptionEvent('subscription-started', Repository::getUser($User_ID)));
}

Repository::schedule('منقضی اشتراک', $User_ID, $Expire_Time_Stamp);
}

private static function renewSubscription(Context $Context, string $Name, int $Gb, int $Days, string $Client_ID, string $Type = 'paid'): void {
$Greeting = Common::greet($Context, 'تمدید اشتراک');
$User_ID = $Context->UserId;
$Full_Name = $Context->profileName();
$User = Repository::getUser($User_ID);
$Phone = (string)($User['Phone'] ?? '');
$Tehran = new DateTimeZone('Asia/Tehran');
$Now_Tehran = new DateTimeImmutable('now', $Tehran);
$Expire_DateTime = $Now_Tehran->modify('+' . $Days . ' days');
$Expire_Time_Stamp = $Expire_DateTime->getTimestamp();
$Expiration_Text = Helper::formatExpiration($Expire_Time_Stamp);
$Package_Start = Helper::formatPersianDate($Now_Tehran->getTimestamp());
$Today = $Now_Tehran->format('Y-m-d');

$Payload = [
'start_date' => $Today,
'package_days' => $Days,
'usage_limit_GB' => $Gb,
'is_active' => true,
'enable' => true,
'last_reset_time' => $Today,
];

$Response = ServerClient::updateUser($Client_ID, $Payload);
$Data = $Response['Json'] ?? null;

if (!is_array($Data) || ($Response['StatusCode'] ?? 0) >= 300 || !isset($Data['uuid'])) {
$Api_Error = '';

if (is_array($Data) && isset($Data['detail'])) {
$Api_Error = json_encode($Data['detail'], JSON_UNESCAPED_UNICODE);
}

elseif ($Response['Body'] !== '' && $Response['Body'] !== null) {
$Api_Error = mb_substr((string)$Response['Body'], 0, 300);
}

AdminFlow::notifyAdminServerError('تمدید اشتراک', $User_ID, $Full_Name, $Response['StatusCode'] ?? 0, $Api_Error);
TelegramClient::sendSystemMessage($Context->ChatId, "🎁{$Greeting} *❌اشتراک {$Name} شما با موفقیت تمدید نشد.\n\n🔄لطفا چند لحظه دیگر با دکمه «تلاش مجدد» اقدام فرمایید.\n⚠️در صورت ادامه مشکل با پشتیبانی در تماس باشید." . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
[['text' => '📞🧑‍💻ارتباط با پشتیبانی', 'url' => BotConfig::getSupportUrl()]],
[['text' => '🔄تلاش مجدد', 'callback_data' => 'user_subscriptions_menu']],
Menu::userHome()
]));
return;
}

$Usage_Limit = (float)max($Gb, (float)($Data['usage_limit_GB'] ?? $Gb));
$Resolved_Uuid = (string)($Data['uuid'] ?? $Client_ID);
$User_Fields = [
'Client_ID'  => $Resolved_Uuid,
'Subscription'  => $Name,
'Package_Duration'   => self::durationLabel($Days),
'Package_Start_Date'  => $Package_Start,
'Expiration_Date'=> $Expiration_Text,
'Expiration_Time_Stamp'   => $Expire_Time_Stamp,
'Total_Usage_GB'  => $Usage_Limit,
'Used_Usage_GB'   => 0.0,
'Remaining_Usage_GB'  => $Usage_Limit,
'Percent_Usage'  => 0.0,
'Client_Status'  => 'فعال',
'Channel_Client_Disabled_At' => null,
'Deactivation_Message'   => null,
];
if ($Type === 'free') {
$User_Fields['Free_Plan_Claimed'] = 1;
}
Repository::updateUser($User_ID, $User_Fields);
if ($Type === 'nowruz') {
BotConfig::markNowruzClaimed($User_ID, $Resolved_Uuid);
}
Repository::updateUserSession($User_ID, ['Pending_Plan' => null]);

TelegramClient::sendSystemMessage($Context->ChatId, "🎁{$Greeting} *اشتراک {$Name} شما با موفقیت تمدید گردید." . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
[['text' => '👤پروفایل کاربری', 'callback_data' => 'پروفایل کاربری']],
Menu::userHome()
]));

Repository::addSubscriptionLog($User_ID, 'renew', $Name, $Days, $Usage_Limit, isset($Data['uuid']) ? $Data['uuid'] : null, 'user', $User_ID);

if (Helper::validatePhone($Phone)) {
$Plan = Helper::smsPlan($Name);
$Template = Repository::getSmsTemplate('renew');
$Duration_Label = Helper::durationLabel($Days);
$Sms_Text = $Template !== null
? strtr($Template, ['{full_name}' => $Full_Name, '{plan}' => $Plan, '{remaining}' => $Duration_Label])
: "{$Full_Name} گرامی 🎉اشتراک {$Plan} شما با موفقیت تمدید گردید.\n⏳مدت اعتبار: {$Duration_Label}\n\nسرور آمبرلا";
IppanelClient::sendOnce($User_ID, $Phone, $Sms_Text, IppanelClient::subscriptionEvent('subscription-renewed', Repository::getUser($User_ID)));
}

Repository::schedule('منقضی اشتراک', $User_ID, $Expire_Time_Stamp);
}

private static function durationLabel(int $Days): string {
return Helper::durationLabel($Days);
}
}
?>
