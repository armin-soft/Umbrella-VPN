<?php
declare(strict_types=1);

require_once __DIR__ . '/Context.php';
require_once __DIR__ . '/Common.php';
require_once __DIR__ . '/../Core/Telegram/Telegram.php';
require_once __DIR__ . '/../Core/Server/Umbrella-Server.php';
require_once __DIR__ . '/../Core/Server/Umbrella-Panel.php';
require_once __DIR__ . '/../Core/Support/Helper.php';
require_once __DIR__ . '/../Core/Support/Bot-Config.php';
require_once __DIR__ . '/../Core/Support/Http.php';
require_once __DIR__ . '/../Core/Storage/Repository.php';
require_once __DIR__ . '/../Core/Subscription/Auto-Renew.php';
require_once __DIR__ . '/../Config/Environment.php';

final class UserFlow {
private const AUTO_RENEW_PLANS = [
'1' => '۱ ماهه',
'2' => '۲ ماهه',
'3' => '۳ ماهه',
'6' => '۶ ماهه',
'12' => '۱ ساله',

];

private function __construct() {
}

private static function liveUsageBoard(): array {
try {
return ServerClient::liveUsers();
}

catch (Throwable) {
return [];
}
}

public static function start(Context $Context): void {
TelegramClient::sendChatAction($Context->ChatId);
$Context->saveUser();
$Greeting = Common::greet($Context, 'منوی خدمات ربات');

if (!Common::isRobotOn()) {
Common::robotOff($Context);
return;
}

$Channel_Url = BotConfig::getChannelUrl();
$Status = self::membershipStatus($Context->UserId);

if (in_array($Status, ['unknown', 'unknown_participant'], true)) {
TelegramClient::sendMessage($Context->ChatId, "{$Greeting}⚠️در حال حاضر امکان بررسی عضویت در کانال وجود ندارد. لطفاً چند لحظه دیگر دوباره بررسی کنید." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '✅بررسی مجدد عضویت', 'callback_data' => 'بررسی عضویت کانال']],
]));
return;
}

if ($Status === 'member') {
self::registerNewUserFeedback($Context);
$Welcome_Text = $Greeting . "🎉به ربات فیلترشکن آمبرلا خوش آمدید." . Helper::userFooter();
TelegramClient::sendMessage($Context->ChatId, $Welcome_Text, TelegramClient::inlineKeyboard([
[['text' => '🤖📋منوی خدمات ربات', 'callback_data' => 'منوی خدمات ربات']],
]));
}

else {
TelegramClient::sendMessage($Context->ChatId, "{$Greeting}جهت استفاده از امکانات ربات باید عضو کانال شوید." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '📢عضویت در کانال', 'url' => $Channel_Url]],
[['text' => '📢🔍بررسی عضویت در کانال', 'callback_data' => 'start']],
]));
}
}

public static function recheckChannelMembership(Context $Context): void {
if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🔄در حال بررسی عضویت...', false);
}

$Greeting = Common::greet($Context, 'بررسی عضویت کانال');
$Channel_Url = BotConfig::getChannelUrl();
$Status = self::membershipStatus($Context->UserId);
$Is_Member = $Status === 'member';

if (in_array($Status, ['unknown', 'unknown_participant'], true)) {
TelegramClient::sendMessage($Context->ChatId, "{$Greeting}⚠️در حال حاضر امکان بررسی عضویت در کانال وجود ندارد. لطفاً چند لحظه دیگر دوباره بررسی کنید." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '✅بررسی مجدد عضویت', 'callback_data' => 'بررسی عضویت کانال']],
]));
return;
}

if ($Is_Member) {
$User = Repository::getUser($Context->UserId);
$Was_Disabled = ($User['Channel_Client_Disabled_At'] ?? null) !== null;
Repository::updateUser($Context->UserId, ['Channel_Grace_Started_At' => null, 'Channel_Client_Disabled_At' => null, 'Channel_Member_Check_At' => time()]);

if ($Was_Disabled) {
$Client_ID = (string)($User['Client_ID'] ?? '');

if ($Client_ID !== '' && $Client_ID !== '_') {
$Update_Response = ServerClient::updateUser($Client_ID, ['is_active' => true, 'enable' => true]);

if (($Update_Response['StatusCode'] ?? 0) >= 300) {
AdminFlow::notifyAdminServerError('فعالسازی کلاینت (کانال)', $Context->UserId, $Context->profileName(), $Update_Response['StatusCode'] ?? 0, (string)($Update_Response['Body'] ?? ''));
}
}

Repository::updateUser($Context->UserId, ['Client_Status' => 'فعال']);
TelegramClient::sendMessage($Context->ChatId, "{$Greeting}🎉عضویت شما در کانال مجددا تایید گردید و کلاینت شما فعال شد." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '💎اشتراک من', 'callback_data' => 'اشتراک من']],
Common::mainButton(),
]));
}

else {
TelegramClient::sendMessage($Context->ChatId, "{$Greeting}✅عضویت شما در کانال تایید گردید." . Helper::userFooter(), TelegramClient::inlineKeyboard([
Common::mainButton(),
]));
}

return;
}

$Minutes = (int)ceil(Environment::getChannelGraceSeconds() / 60);
TelegramClient::sendMessage($Context->ChatId, "{$Greeting}⚠️شما عضو کانال اطلاع رسانی نیستید.\n\nبرای استفاده از امکانات ربات باید عضو کانال شوید." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '📢عضویت در کانال', 'url' => $Channel_Url]],
[['text' => '✅بررسی مجدد عضویت', 'callback_data' => 'بررسی عضویت کانال']],
]));
}

private static function membershipStatus(int $UserId): string {
$Channel_Link = BotConfig::getChannelUrl();
$Channel_Name = self::extractChannelName($Channel_Link);
$Channel_ID = BotConfig::getTelegramChannelId();

if ($Channel_Name === '' && $Channel_ID === '') return 'member';
return \TelegramClient::channelMemberStatus($UserId, $Channel_Name, $Channel_ID);
}

public static function checkChannelMembershipCached(int $UserId): bool {
$User = Repository::getUser($UserId);
$Client_ID = trim((string)($User['Client_ID'] ?? ''));
$Has_Client = $Client_ID !== '' && $Client_ID !== '_';

if (!$Has_Client) return true;
$Last_Check = (int)($User['Channel_Member_Check_At'] ?? 0);
$Grace_Started_At = (int)($User['Channel_Grace_Started_At'] ?? 0);
$Is_Disabled = (int)($User['Channel_Client_Disabled_At'] ?? 0) > 0;
$TTL = 1800;
$Should_Call = $Last_Check <= 0 || (time() - $Last_Check) >= $TTL || ($Grace_Started_At > 0 && !$Is_Disabled);

if (!$Should_Call) return true;
$Status = self::membershipStatus($UserId);

if (in_array($Status, ['unknown', 'unknown_participant'], true)) {
Repository::updateUser($UserId, ['Channel_Member_Check_At' => time()]);
return true;
}

if ($Status === 'not_member') {
$Grace_Started_At = (int)($User['Channel_Grace_Started_At'] ?? 0);

if ($Grace_Started_At <= 0) {
Repository::updateUser($UserId, ['Channel_Grace_Started_At' => time()]);
}

return false;
}

Repository::updateUser($UserId, ['Channel_Member_Check_At' => time()]);
return true;
}

private static function extractChannelName(string $Link): string {
$Link = trim($Link, "/ \t\n\r\0\x0B");
$Link = preg_replace('#^https?://#i', '', $Link) ?? $Link;
$Link = preg_replace('#^(?:t\.me|telegram\.me)/#i', '', $Link) ?? $Link;
$Link = preg_replace('~[?#].*$~', '', $Link) ?? $Link;
$Link = preg_replace('/^@/', '', $Link) ?? $Link;
$Name = explode('/', $Link)[0] ?? '';
return preg_match('/^[A-Za-z0-9_]{3,32}$/', $Name) === 1 ? $Name : '';
}

/**
 * First contact from a person: stamps the join date, links the panel account
 * and tells the admins.
 *
 * The panel link is the part that matters. A sign-in from the desktop app is
 * confirmed through Telegram, so the app's code can only be answered once the
 * panel account carries a Telegram id. A customer created from the app has
 * none, and without this step their first sign-in would stall on
 * «یک بار ربات را باز کنید» forever.
 */
private static function registerNewUserFeedback(Context $Context): void {
$User = Repository::getUser($Context->UserId);

if (($User['Registered_At'] ?? null) !== null) return;

Repository::updateUser($Context->UserId, ['Registered_At' => date('Y-m-d H:i:s')]);
self::linkPanelAccount($Context);
$Admin = (int)Repository::getSetting('Administrator', (string)Environment::getAdminUserId());

if ($Admin <= 0) return;

try {
TelegramClient::sendMessage(
$Admin,
Helper::adminGreetingNamed(
(string)(Repository::getSetting('Admin_Full_Name') ?: Environment::getAdminFullName()),
'کاربران جدید',
$Admin
) . "✅لحظاتی پیش کاربر جدیدی عضو ربات گردید.\n\n👤نام: "
. "[" . $Context->profileName() . "](tg://user?id=" . $Context->UserId . ")\n🆔آیدی عددی: `"
. Helper::toPersian((int)$Context->UserId) . "`"
. Helper::adminFooter()
);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][NewUser-Admin-Notice] ' . $Error->getMessage());
}
}

/**
 * Puts the Telegram id on the customer's panel account, so a sign-in from the
 * app has somebody to ask for confirmation.
 *
 * Best-effort and never blocking: a panel that is down must not stop the bot
 * from answering «start».
 */
private static function linkPanelAccount(Context $Context): void {
$User = Repository::getUser($Context->UserId);
$UUID = trim((string)($User['Client_ID'] ?? ''));

if ($UUID === '') {
$Phone = \Helper::normalizePhone((string)($User['Phone'] ?? ''));

if ($Phone === '') return;

try {
$Account = PanelClient::findByPhone($Phone);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Panel-Link] lookup failed: ' . $Error->getMessage());
return;
}

$UUID = trim((string)($Account['uuid'] ?? ''));

if ($UUID === '') return;

// Remembered locally, so the next launch does not have to search again.
Repository::updateUser($Context->UserId, ['Client_ID' => $UUID]);
}

$Current = null;

try {
$Current = PanelClient::get($UUID);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Panel-Link] read failed: ' . $Error->getMessage());
}

if (is_array($Current) && (string)($Current['telegram_id'] ?? '') === (string)$Context->UserId) {
return;
}

try {
PanelClient::update($UUID, ['telegram_id' => (string)$Context->UserId]);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Panel-Link] write failed: ' . $Error->getMessage());
}
}

public static function serviceMenu(Context $Context): void {
TelegramClient::sendChatAction($Context->ChatId);

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🔄منوی خدمات ربات در حال بارگذاری...', false);
}

if (!Common::isRobotOn()) {
if ($Context->IsCallback && $Context->MessageId !== null) {
$Edit_Result = TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, Common::offlineText($Context, 'منوی خدمات ربات'));

if (is_array($Edit_Result) && ($Edit_Result['ok'] ?? false) !== true) {
try { TelegramClient::deleteMessage($Context->ChatId, $Context->MessageId); } catch (Throwable) {}
TelegramClient::sendMessage($Context->ChatId, Common::offlineText($Context, 'منوی خدمات ربات'));
}
}

else {
Common::robotOff($Context, 'منوی خدمات ربات');
}

return;
}

$Text = Common::greet($Context, 'منوی خدمات ربات') . "\n➖➖➖➖➖➖➖➖➖\n📌لطفاً یکی از بخش های زیر را انتخاب کنید:" . Helper::userFooter();
$User = Repository::getUser($Context->UserId);
$Client_ID = (string)($User['Client_ID'] ?? '');
$Has_Client = $Client_ID !== '' && $Client_ID !== '_';
$Menu_Rows = [
[['text' => '👤پروفایل کاربری', 'callback_data' => 'پروفایل کاربری']],
[['text' => '💎اشتراک من', 'callback_data' => 'اشتراک من']],
[['text' => '🎫تیکت ها و پشتیبانی', 'callback_data' => 'منوی پشتیبانی']],
];

$Menu_Rows[] = [['text' => '🔄📄تغییرات نسخه', 'callback_data' => 'تغییرات نسخه']];
$Keyboard = TelegramClient::inlineKeyboard($Menu_Rows);

if ($Context->IsCallback && $Context->MessageId !== null) {
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, $Keyboard);
}

else {
TelegramClient::sendMessage($Context->ChatId, $Text, $Keyboard);
}
}

public static function supportMenu(Context $Context): void {
TelegramClient::sendChatAction($Context->ChatId);

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🔄منوی تیکت در حال بارگذاری...', false);
}

$Text = Common::greet($Context, 'تیکت ها و پشتیبانی') . "\n➖➖➖➖➖➖➖➖➖\n📌لطفاً یکی از بخش های تیکت را انتخاب کنید:" . Helper::userFooter();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard([
[['text' => '➕ایجاد تیکت جدید', 'callback_data' => 'تیکت جدید']],
[['text' => '🎫تیکت های من', 'callback_data' => 'لیست تیکت های من']],
[['text' => '🔙بازگشت به منوی قبل', 'callback_data' => 'منوی خدمات ربات']],
]));
}

public static function profile(Context $Context, bool $Answer_Callback = true): void {
TelegramClient::sendChatAction($Context->ChatId);

if ($Answer_Callback && $Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🔄پروفایل کاربری در حال بارگذاری...', false);
}

$Greeting = Common::greet($Context, 'پروفایل کاربری');
$User = Common::liveUser(Repository::getUser($Context->UserId));
$Auto_Renew_Plan_On = trim((string)($User['Auto_Renew_Plan'] ?? '')) !== '';
$Phone = $User['Phone'] ?? null;
$FullName = $User['Full_Name'] ?? null;
$Balance = Repository::getBalance($Context->UserId);
$Balance_Formatted = Helper::formatCurrency($Balance);

if (!is_string($Phone) || $Phone === '') {
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Greeting . "⛔️بدلیل عدم ثبت پروفایل کاربری مجاز به ورود به این بخش نیستید." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '📝👤ثبت اطلاعات پروفایل کاربری', 'callback_data' => 'ویرایش و ثبت پروفایل']],
Common::mainButton()
]));

return;
}

$Subscription = $User['Subscription'] ?? null;
$Client_ID = (string)($User['Client_ID'] ?? '');
$Client_Status = (string)($User['Client_Status'] ?? 'نامشخص');
$Last_Online = (string)($User['Last_Online'] ?? '');
$Operator = (string)($User['Operator'] ?? '');

if ($Operator === '') {
$Operator = Helper::detectOperator((string)$Phone);
}

$Expiration_Time_Stamp = (int)($User['Expiration_Time_Stamp'] ?? 0);
$Package_Start_Date = (string)($User['Package_Start_Date'] ?? '');
$Package_Duration = (int)($User['Package_Duration'] ?? 0);
$Total_Usage = (string)($User['Total_Usage_GB'] ?? '');
$Used_Usage = (string)($User['Used_Usage_GB'] ?? '');
$Remaining_Usage = (string)($User['Remaining_Usage_GB'] ?? '');
$Percent_Usage = (string)($User['Percent_Usage'] ?? '');
$Free_Plan_Claimed = (int)($User['Free_Plan_Claimed'] ?? 0);
$Profile_Updated_At = (string)($User['Profile_Updated_At'] ?? '');
$Created_At = (string)($User['Created_At'] ?? '');
$Expiration_Date = 'نامشخص';

if ($Expiration_Time_Stamp > 0) {
$Expiration_Date = Helper::formatExpirationShort($Expiration_Time_Stamp);
}

elseif (isset($User['Expiration_Date']) && $User['Expiration_Date'] !== '' && $User['Expiration_Date'] !== null) {
$Expiration_Date = (string)$User['Expiration_Date'];
}

$Has_Expiry = $Expiration_Time_Stamp > 0;
$Days_Remaining = 0;

if ($Has_Expiry) {
$Diff = $Expiration_Time_Stamp - time();
$Days_Remaining = $Diff > 0 ? (int)ceil($Diff / 86400) : 0;
}

$Client_Raw = trim((string)($User['Client_ID'] ?? ''));
$Has_Subscription = (trim((string)($User['Subscription'] ?? '')) !== '')
|| ($Has_Expiry && $Days_Remaining > 0)
|| ($Client_Raw !== '' && $Client_Raw !== '_');
$Auto_Renew_Visible = $Has_Subscription;
$ED_Private = (string)($User['ED_25519_Private_Key'] ?? '');
$ED_Public = (string)($User['ED_25519_Public_Key'] ?? '');
$WG_Private = (string)($User['WireGuard_Private_Key'] ?? '');
$WG_Public = (string)($User['WireGuard_Public_Key'] ?? '');
$WG_PSK = (string)($User['WireGuard_PSK'] ?? '');
$Has_Keys = $ED_Private !== '' || $ED_Public !== '' || $WG_Private !== '' || $WG_Public !== '' || $WG_PSK !== '';
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

$Profile_Updated_Label = 'ثبت نشده';

if ($Profile_Updated_At !== '' && $Profile_Updated_At !== '0000-00-00 00:00:00') {
try {
$Pu_Date = substr($Profile_Updated_At, 0, 10);
$Pu_Time = substr($Profile_Updated_At, 11, 8);
$Profile_Updated_Label = Helper::gregorianToJalali($Pu_Date) . ' - ' . Helper::formatTime($Pu_Time);
}

catch (Throwable) { $Profile_Updated_Label = $Profile_Updated_At; }
}

$Created_At_Label = 'نامشخص';

if ($Created_At !== '' && $Created_At !== '0000-00-00 00:00:00') {
try {
$Ca_Date = substr($Created_At, 0, 10);
$Created_At_Label = Helper::gregorianToJalali($Ca_Date);
}

catch (Throwable) { $Created_At_Label = $Created_At; }
}

$Subscription_Text = is_string($Subscription) && $Subscription !== ''
? "├─🪪نوع اشتراک: *{$Subscription}*\n"
. "├─🚦وضعیت کلاینت: *" . Helper::translateStatus($Client_Status) . "*\n"
. "├─📡آخرین اتصال: *{$Last_Online_Label}*\n"
. "├─📅تاریخ شروع: *" . ($Package_Start_Date !== '' ? $Package_Start_Date : 'نامشخص') . "*\n"
. "├─⏳ تاریخ انقضا: *{$Expiration_Date}*\n"
. "├─📦مدت بسته: *" . ($Package_Duration > 0 ? Helper::toPersian((string)$Package_Duration) . " روز" : 'نامشخص') . "*\n"
. "├─📊حجم کل: *" . ($Total_Usage !== '' ? Helper::formatGB((float)$Total_Usage) : 'نامشخص') . "*\n"
. "├─📥حجم مصرف شده: *" . ($Used_Usage !== '' ? Helper::formatGB((float)$Used_Usage) : 'نامشخص') . "*\n"
. "├─📤حجم باقی مانده: *" . ($Remaining_Usage !== '' ? Helper::formatGB((float)$Remaining_Usage) : 'نامشخص') . "*\n"
. "├─📈درصد مصرف: *" . ($Percent_Usage !== '' && $Percent_Usage !== null ? Helper::formatPercent((float)$Percent_Usage) . '٪' : 'نامشخص') . "*\n"
. "├─🎁اشتراک رایگان: *" . ($Free_Plan_Claimed === 1 ? '✅استفاده شده' : '❌استفاده نشده') . "*\n"
. "└─🆔UUID: `{$Client_ID}`\n"
. ($Has_Keys
? "\n🔑*کلیدهای اتصال شما:*\n\n"
. "🔸<b>کلید خصوصی ادی۲۵۵۱۹</b>\n<pre>{$ED_Private}</pre>\n"
. "🔹<b>کلید عمومی ادی۲۵۵۱۹</b>\n<pre>{$ED_Public}</pre>\n"
. "🔸<b>کلید خصوصی وایرگارد</b>\n<pre>{$WG_Private}</pre>\n"
. "🔹<b>کلید عمومی وایرگارد</b>\n<pre>{$WG_Public}</pre>\n"
. "🔸<b>کلید از پیش اشتراکی وایرگارد</b>\n<pre>{$WG_PSK}</pre>"
: '')
: '└─❌اشتراک فعالی ندارید.';

$Rank_Line = '';
$Used_Val = (float)($Used_Usage !== '' && $Used_Usage !== null ? $Used_Usage : 0);

if ($Used_Val > 0) {
$Board = self::liveUsageBoard();
$My_Rank = 0;

foreach ($Board as $Idx => $Row) {
if ((int)($Row['Telegram_ID'] ?? 0) === $Context->UserId) { $My_Rank = $Idx + 1; break; }
}

if ($My_Rank > 0) {
$Rank_Line = "🏆رتبه در رتبه بندی مصرف: " . Helper::rankEmoji($My_Rank) . " " . Helper::rankTitle($My_Rank) . "\n";
}
}

$Auto_Renew_Plan = trim((string)($User['Auto_Renew_Plan'] ?? ''));
$Ar_Price = 0;
$Ar_Balance = Repository::getBalance($Context->UserId);
$Ar_Has_Balance = true;
$Auto_Renew_Button = '✅فعال کردن تمدید خودکار';

if ($Auto_Renew_Plan !== '') {
$Ar_Plan_Name = AutoRenew::planName($Auto_Renew_Plan);

if ($Ar_Plan_Name === '') $Ar_Plan_Name = 'پلن فعلی';
$Ar_Price = BotConfig::getPlanPrice($Auto_Renew_Plan);
$Ar_Has_Balance = ($Ar_Price <= 0) || ($Ar_Balance >= $Ar_Price);
$Ar_Balance_Label = Helper::formatCurrency($Ar_Balance);
$Ar_Price_Label = Helper::formatCurrency($Ar_Price);
$Ar_Suffix = ($Ar_Price > 0 && $Ar_Has_Balance)
? "\n├─💳موجودی کیف پول: *{$Ar_Balance_Label}* از *{$Ar_Price_Label}* (✅کافی)"
: "\n├─💳موجودی کیف پول: *{$Ar_Balance_Label}* از *{$Ar_Price_Label}* (⚠️ناکافی)";
$Auto_Renew_Label = $Ar_Has_Balance
? '*🟢فعال (' . $Ar_Plan_Name . ')*' . $Ar_Suffix
: '*🟠فعال (' . $Ar_Plan_Name . ') — در انتظار شارژ*' . $Ar_Suffix
. "\n└─⚠️به دلیل کمبود موجودی، تمدید خودکار انجام نمی شود.";
$Auto_Renew_Button = '⛔️غیرفعال کردن تمدید خودکار';
}

else {
$Auto_Renew_Label = '*🔴غیرفعال*';
$Auto_Renew_Button = '✅فعال کردن تمدید خودکار';
}

$Profile_Text = "👤نام و نام خانوادگی: *{$FullName}*\n"
. "📞شماره موبایل: " . Helper::toPersian((string)$Phone) . " (*{$Operator}*)\n"
. "💳اعتبار حساب: *{$Balance_Formatted}*\n"
. "🆔شناسه تلگرام: `" . Helper::toPersian((string)$Context->UserId) . "`\n"
. $Rank_Line
. ($Auto_Renew_Visible ? "🔄تمدید خودکار: {$Auto_Renew_Label}\n" : '')
. "📅تاریخ عضویت: *{$Created_At_Label}*\n"
. "🕰آخرین بروزرسانی پروفایل: *{$Profile_Updated_Label}*\n"
. "➖➖➖➖➖➖➖➖➖➖\n"
. "💎*اشتراک:*\n"
. "{$Subscription_Text}";
$Profile_Buttons = [];

if ($Has_Subscription) {
$Profile_Buttons[] = [['text' => $Auto_Renew_Button, 'callback_data' => 'toggle_auto_renew']];

if ($Auto_Renew_Plan !== '' && !$Ar_Has_Balance) {
$Profile_Buttons[] = [['text' => '💰شارژ اعتبار برای تمدید خودکار', 'callback_data' => 'شارژ اعتبار حساب کاربری']];
}
}

else {
$Profile_Buttons[] = [['text' => '💎خرید اشتراک', 'callback_data' => 'اشتراک من']];
}

$Profile_Buttons[] = [['text' => '✏️ویرایش پروفایل', 'callback_data' => 'ویرایش پروفایل']];

if ($Has_Subscription) {
$Profile_Buttons[] = [['text' => '📊گزارش مصرف', 'callback_data' => 'گزارش مصرف']];
}

$Profile_Buttons[] = [['text' => '💰شارژ اعتبار حساب کاربری', 'callback_data' => 'شارژ اعتبار حساب کاربری']];
$Profile_Buttons[] = [['text' => '📋سابقه تراکنش', 'callback_data' => 'سابقه تراکنش'], ['text' => '📋سابقه اشتراک', 'callback_data' => 'سابقه اشتراک']];
$Profile_Buttons[] = [['text' => '🛡کنترل محتوا', 'callback_data' => 'app_filter'], ['text' => '📱دستگاه من', 'callback_data' => 'app_devices']];
$Profile_Buttons[] = [['text' => '🔔اعلانات', 'callback_data' => 'app_notifications'], ['text' => '🔐ورود دو مرحله‌ای', 'callback_data' => 'app_2fa']];
$Profile_Buttons[] = Common::mainButton();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Greeting . "🔰اطلاعات پروفایل شما به شرح زیر است:\n\n" . $Profile_Text . Helper::userFooter(), TelegramClient::inlineKeyboard($Profile_Buttons));
}

public static function autoRenewMenu(Context $Context): void {
TelegramClient::sendChatAction($Context->ChatId);

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🔄در حال بارگذاری تمدید خودکار...', false);
}

$User = Repository::getUser($Context->UserId);
$Current = trim((string)($User['Auto_Renew_Plan'] ?? ''));
$Balance = Repository::getBalance($Context->UserId);
$Exp_Stamp = (int)($User['Expiration_Time_Stamp'] ?? 0);
$Current_Name = $Current !== '' ? (self::AUTO_RENEW_PLANS[$Current] ?? AutoRenew::planName($Current)) : '';
$Status = $Current !== '' ? "🟢فعال ({$Current_Name})" : '🔴غیرفعال';
$Text = Common::greet($Context, 'تمدید خودکار اشتراک')
. "🔄*تمدید خودکار اشتراک*\n➖➖➖➖➖➖➖➖➖\n"
. "📌وضعیت فعلی: *{$Status}*\n"
. "💳موجودی کیف پول: *" . Helper::formatCurrency($Balance) . "*\n"
. "⏳زمان باقیمانده اشتراک: *" . Helper::remainingDuration($Exp_Stamp) . "*\n\n"
. "ℹ️در صورت فعال بودن، " . Helper::toPersian('3') . " روز قبل از انقضا، اشتراک شما به صورت خودکار از موجودی کیف پول تمدید می شود.\n\n"
. "👇برای فعال کردن، پلن مورد نظر را انتخاب کنید:";
$Rows = [];

foreach (self::AUTO_RENEW_PLANS as $Key => $Label) {
$Price = BotConfig::getPlanPrice((int)$Key);
$Price_Label = $Price > 0 ? Helper::formatCurrency($Price) : 'قیمت ثبت نشده';
$Mark = $Current === $Key ? '✅' : '🟢';
$Rows[] = [['text' => "{$Mark}فعال: {$Label} - {$Price_Label}", 'callback_data' => 'auto_renew_on_' . $Key]];
}

$Rows[] = [['text' => '⛔️غیرفعال کردن تمدید خودکار', 'callback_data' => 'auto_renew_off']];
$Rows[] = Common::backTo('🔙بازگشت به پروفایل', 'پروفایل کاربری');
$Rows[] = Common::mainButton();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text . Helper::userFooter(), TelegramClient::inlineKeyboard($Rows));
}

public static function enableAutoRenew(Context $Context): void {
$Plan = str_replace('auto_renew_on_', '', trim((string)($Context->CallbackData ?? '')));
$Plan_Name = self::AUTO_RENEW_PLANS[$Plan] ?? '';

if ($Plan_Name === '') {
if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '⛔️پلن انتخابی معتبر نیست.', true);
}

self::autoRenewMenu($Context);
return;
}

$Price = BotConfig::getPlanPrice((int)$Plan);
$Balance = Repository::getBalance($Context->UserId);
Repository::updateUser($Context->UserId, ['Auto_Renew_Plan' => $Plan]);

if ($Context->CallbackId !== null) {
$Toast = "✅تمدید خودکار {$Plan_Name} فعال شد.";

if ($Price <= 0) {
$Toast .= ' |⚠️قیمت این پلن در تنظیمات ثبت نشده است';
}

elseif ($Balance < $Price) {
$Toast .= ' |⚠️موجودی ناکافی: ' . Helper::formatCurrency($Balance) . ' از ' . Helper::formatCurrency($Price);
}

else {
$Toast .= ' |✅موجودی کافی';
}

TelegramClient::answerCallbackQuery($Context->CallbackId, $Toast, false);
}

self::autoRenewMenu($Context);
}

public static function disableAutoRenew(Context $Context): void {
Repository::updateUser($Context->UserId, ['Auto_Renew_Plan' => null]);

if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '⛔️تمدید خودکار غیرفعال شد.', false);
}

self::autoRenewMenu($Context);
}

public static function toggleAutoRenew(Context $Context): void {
$User = Repository::getUser($Context->UserId);
$Current = trim((string)($User['Auto_Renew_Plan'] ?? ''));

if ($Current !== '') {
Repository::updateUser($Context->UserId, ['Auto_Renew_Plan' => null]);

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '⛔️تمدید خودکار غیرفعال شد.', false);
}

self::profile($Context, false);
return;
}

$Duration = (int)($User['Package_Duration'] ?? 0);
$Has_Subscription = $Duration > 0 || trim((string)($User['Client_ID'] ?? '')) !== '';

if (!$Has_Subscription) {
if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '⚠️اشتراک فعالی ندارید؛ ابتدا اشتراک بخرید.', true);
}

return;
}

$Plan = self::currentAutoRenewPlanKey($Duration);
$Plan_Name = self::AUTO_RENEW_PLANS[$Plan] ?? AutoRenew::planName($Plan);

if ($Plan_Name === '') $Plan_Name = 'پلن فعلی';
$Plan_Price = BotConfig::getPlanPrice($Plan);
$Wallet_Balance = Repository::getBalance($Context->UserId);
$Wallet_Short = ($Plan_Price > 0 && $Wallet_Balance < $Plan_Price);

if ($Plan_Price <= 0) {
if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '⚠️قیمت این پلن تنظیم نشده است.', true);
}

TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'تمدید خودکار')
. Helper::noticeBlock(
'❌تمدید خودکار فعال نشد.',
'⚠️علت:🚫قیمت پلن «' . $Plan_Name . '» در تنظیمات سرور ثبت نشده است.',
'ℹ️لطفاً با پشتیبانی تماس بگیرید.'
) . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '📞🧑‍💻ارتباط با پشتیبانی (آرمین سافت)', 'url' => BotConfig::getSupportUrl()]],
]));
return;
}

if ($Wallet_Short) {
if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '❌تمدید خودکار فعال نشد؛ موجودی کافی نیست.', true);
}

TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'تمدید خودکار')
. Helper::noticeBlock(
'❌تمدید خودکار فعال نشد.',
'⚠️علت:💳موجودی کیف پول شما کمتر از مبلغ لازم است.',
"📦پلن: *{$Plan_Name}*\n"
. "💰مبلغ لازم: *" . Helper::formatCurrency($Plan_Price) . "*\n"
. "💳موجودی کیف پول: *" . Helper::formatCurrency($Wallet_Balance) . "*\n"
. "💵کسری شما: *" . Helper::formatCurrency($Plan_Price - $Wallet_Balance) . "*\n"
. 'ℹ️برای فعال سازی تمدید خودکار ابتدا کیف پول خود را شارژ کنید.'
) . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '💰شارژ اعتبار حساب کاربری', 'callback_data' => 'شارژ اعتبار حساب کاربری']],
[['text' => '🔙بازگشت به منوی قبل', 'callback_data' => 'پروفایل کاربری']],
]));
return;
}

Repository::updateUser($Context->UserId, ['Auto_Renew_Plan' => $Plan]);

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, "✅تمدید خودکار ({$Plan_Name}) فعال شد.", true);
}

self::profile($Context, false);
}

private static function currentAutoRenewPlanKey(int $Days): string {
if ($Days <= 45) return '1';
if ($Days <= 75) return '2';
if ($Days <= 105) return '3';
if ($Days <= 200) return '6';
return '12';
}

public static function transactionHistory(Context $Context): void {
$User = Repository::getUser($Context->UserId);
$Raw = (string)($Context->CallbackData ?? '');
$Page = 1;

if (str_contains($Raw, '|')) {
$Parts = explode('|', $Raw, 2);
$Page = (int)($Parts[1] ?? 1);
}

if ($Page <= 0) $Page = 1;
$Transactions = Repository::getTransactions($Context->UserId, $Page, 5);
$Total = Repository::countTransactions($Context->UserId);
$Total_Pages = max(1, (int)ceil($Total / 5));
$Text = Helper::userGreeting($Context, 'سابقه تراکنش های اعتبار');

if (empty($Transactions)) {
$Text .= "⚠️هنوز تراکنشی انجام نداده اید." . Helper::userFooter();
}

else {
foreach ($Transactions as $Index => $Tx) {
$Date = Helper::gregorianToJalali(substr($Tx['Created_At'], 0, 10));
$Time = Helper::formatTime(substr($Tx['Created_At'], 11, 5));
$Amount = Helper::formatCurrency((float)$Tx['Amount']);
$Desc = $Tx['Description'] !== '' ? $Tx['Description'] : 'تراکنش';
$Source_Label = Helper::sourceLabel((string)($Tx['Source'] ?? ''), (string)($Tx['Type'] ?? ''));
$Type_Label = Helper::actionLabel((string)($Tx['Type'] ?? ''));
$Sign_Icon = (float)$Tx['Amount'] >= 0 ? '➕' : '➖';
$Balance_After = Helper::formatCurrency((float)($Tx['Balance_After'] ?? 0));
$Text .= "📋تراکنش #" . Helper::toPersian((string)($Index + 1)) . ":\n";
$Text .= "🔸{$Type_Label}\n";
$Text .= "🏷️انجام شده توسط: <b>{$Source_Label}</b>\n";
$Text .= "📝{$Desc}\n";
$Text .= "📆{$Date}🕰{$Time}\n";
$Text .= "{$Sign_Icon}مبلغ: <b>{$Amount}</b>\n";
$Text .= "👛موجودی پس از تراکنش: <b>{$Balance_After}</b>\n";
$Text .= "➖➖➖➖➖➖➖➖➖➖\n";
}

$Text .= "📄صفحه " . Helper::toPersian((string)$Page) . " از " . Helper::toPersian((string)$Total_Pages) . Helper::userFooter() . "*";
}

$Buttons = [];
$Buttons[] = [['text' => '🔙بازگشت به منوی قبل', 'callback_data' => 'پروفایل کاربری']];
$Buttons[] = [['text' => '🏠بازگشت به منوی اصلی', 'callback_data' => 'منوی خدمات ربات']];

if ($Page < $Total_Pages) {
$Buttons[] = [['text' => '📄صفحه بعد', 'callback_data' => 'سابقه تراکنش|' . ($Page + 1)]];
}

TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Buttons));
}

public static function subscriptionHistory(Context $Context): void {
$User = Repository::getUser($Context->UserId);
$Raw = (string)($Context->CallbackData ?? '');
$Page = 1;

if (str_contains($Raw, '|')) {
$Parts = explode('|', $Raw, 2);
$Page = (int)($Parts[1] ?? 1);
}

if ($Page <= 0) $Page = 1;
$Logs = Repository::getSubscriptionLogs($Context->UserId, $Page, 5);
$Total = Repository::countSubscriptionLogs($Context->UserId);
$Total_Pages = max(1, (int)ceil($Total / 5));
$Text = Helper::userGreeting($Context, 'سابقه اشتراک ها');

if (empty($Logs)) {
$Text .= "⚠️هنوز اشتراکی ثبت نشده است." . Helper::userFooter();
}

else {
foreach ($Logs as $Index => $Log) {
$Date = Helper::gregorianToJalali(substr($Log['Created_At'], 0, 10));
$Time = Helper::formatTime(substr($Log['Created_At'], 11, 5));
$Action = Helper::actionLabel((string)$Log['Action']);
$Source_Label = Helper::sourceLabel((string)($Log['Source'] ?? ''), (string)($Log['Action'] ?? ''));
$Actor = (int)($Log['Actor_ID'] ?? 0);
$Days = ($Log['Days'] ?? null) !== null ? (int)$Log['Days'] : 0;

$Plan = $Log['Plan_Name'] !== '' ? $Log['Plan_Name'] : 'اشتراک';
$Usage = $Log['Usage_GB'] !== null ? Helper::formatGB((float)$Log['Usage_GB']) : '';
$Text .= "📋سابقه #" . Helper::toPersian((string)($Index + 1)) . ":\n";
$Text .= "🔸{$Action}: {$Plan}\n";
$Text .= "🏷️انجام شده توسط: <b>{$Source_Label}</b>\n";

if ($Actor > 0 && $Actor !== $Context->UserId) {
$Text .= "👤شناسه مدیر: `" . Helper::toPersian((string)$Actor) . "`\n";
}

if ($Days > 0) {
$Text .= "📆مدت: <b>" . Helper::durationLabel($Days) . "</b>\n";
}

$Text .= "🕓زمان: {$Date} - {$Time}\n";

if ($Usage !== '') $Text .= "📊حجم: {$Usage}\n";
$Text .= "➖➖➖➖➖➖➖➖➖\n";
}

$Text .= "📄صفحه " . Helper::toPersian((string)$Page) . " از " . Helper::toPersian((string)$Total_Pages) . Helper::userFooter() . "*";
}

$Buttons = [];
$Buttons[] = [['text' => '🔙بازگشت به منوی قبل', 'callback_data' => 'پروفایل کاربری']];
$Buttons[] = [['text' => '🏠بازگشت به منوی اصلی', 'callback_data' => 'منوی خدمات ربات']];

if ($Page < $Total_Pages) {
$Buttons[] = [['text' => '📄صفحه بعد', 'callback_data' => 'سابقه اشتراک|' . ($Page + 1)]];
}

TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Buttons));
}

public static function changes(Context $Context): void {
TelegramClient::sendChatAction($Context->ChatId);

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🔄تغییرات نسخه در حال بار گذاری می باشد...', false);
}

$Greeting = Common::greet($Context, 'تغییرات نسخه');
$Version = BotConfig::robotVersion();
$Version_P = Helper::toPersian($Version);
$Changes = (string)Repository::getSetting('Robot_Changes', '');
$Changes_Text = $Changes !== '' ? $Changes : '⚠️تغییراتی جهت برای نمایش وجود ندارد';
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Greeting . "🔰اطلاعات بروز رسانی جدید بدین شرح است:\n\n🔄نسخه جدید ربات: {$Version_P}\n\n{$Changes_Text}" . Helper::userFooter(), TelegramClient::inlineKeyboard([Common::mainButton()]));
}

public static function ticketMenu(Context $Context): void {
TelegramClient::sendChatAction($Context->ChatId);

$User = Repository::getUser($Context->UserId);
$Tickets = Repository::userTickets($Context->UserId);
$Open_Count = 0;
foreach ($Tickets as $T) {
if (in_array($T['Status'], ['open', 'pending', 'answered'], true)) $Open_Count++;
}

TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, Helper::userGreeting($Context, 'تیکت های من') . "📊تیکت های باز: *" . Helper::toPersian((string)$Open_Count) . "*\n📋کل: *" . Helper::toPersian((string)count($Tickets)) . "*" . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '➕ایجاد تیکت جدید', 'callback_data' => 'تیکت جدید']],
[['text' => '📋تیکت های من', 'callback_data' => 'لیست تیکت های من']],
Common::mainButton(),
]));
}

public static function ticketNewStart(Context $Context): void {
Repository::updateUserSession($Context->UserId, ['Flow' => 'user:ticket_subject']);
$Text = Helper::userGreeting($Context, 'ایجاد تیکت جدید') . "موضوع تیکت را وارد کنید:\n➖➖➖➖➖➖➖➖➖\n⚠️جهت انصراف «لغو» را ارسال کنید." . Helper::userFooter();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard([
[['text' => '🔙انصراف و بازگشت', 'callback_data' => 'تیکت های من']],
]));
}

public static function ticketCreate(Context $Context, string $Subject): void {
$Subject = mb_substr(trim($Subject), 0, 200);

if ($Subject === '') {
TelegramClient::sendMessage($Context->ChatId, Helper::userGreeting($Context, 'ایجاد تیکت جدید') . "❌موضوع نمی تواند خالی باشد.\n⚠️لطفاً موضوع تیکت را وارد کنید." . Helper::userFooter());
return;
}

Repository::updateUserSession($Context->UserId, ['Ticket_Subject' => $Subject, 'Flow' => 'user:ticket_description']);
$Text = Helper::userGreeting($Context, 'ایجاد تیکت جدید') . "📋موضوع: {$Subject}\n\nتوضیحات تکمیلی را وارد کنید (یا «ندارد» بفرستید):\n➖➖➖➖➖➖➖➖➖\n⚠️جهت انصراف «لغو» را ارسال کنید." . Helper::userFooter();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard([
[['text' => '🔙انصراف و بازگشت', 'callback_data' => 'تیکت های من']],
]));
}

public static function ticketDescriptionInput(Context $Context, string $Text): void {
$Description = mb_substr(trim($Text), 0, 1000);
$Session_Subject = (string)(Repository::getUserSession($Context->UserId)['Ticket_Subject'] ?? '');
Repository::updateUserSession($Context->UserId, ['Ticket_Description' => $Description, 'Flow' => 'user:ticket_category']);
self::ticketCategoryMenu($Context);
}

public static function ticketCategoryMenu(Context $Context): void {
$Session = Repository::getUserSession($Context->UserId);
$Subject = (string)($Session['Ticket_Subject'] ?? '');
$Description = (string)($Session['Ticket_Description'] ?? '');
$Rows = [['text' => '👇دسته تیکت را انتخاب کنید:', 'callback_data' => 'تیکت بدون تغییر']];

foreach (Helper::ticketCategories() as $Key => $Label) {
$Rows[] = [['text' => $Label, 'callback_data' => 'دسته تیکت:' . $Key]];
}

$Rows[] = Common::mainButton();
$Text = Helper::userGreeting($Context, 'ایجاد تیکت جدید')
. "📋موضوع: {$Subject}\n"
. "📝توضیحات: " . ($Description !== '' && $Description !== 'ندارد' ? $Description : 'ندارد') . "\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "📂*مرحله ۱ از ۲ — انتخاب دسته تیکت*" . Helper::userFooter();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Rows));
}

public static function ticketCategoryCallback(Context $Context, string $Category): void {
if (!Helper::isTicketCategory($Category)) {
self::ticketCategoryMenu($Context);
return;
}

$Session = Repository::getUserSession($Context->UserId);

if (trim((string)($Session['Ticket_Subject'] ?? '')) === '') {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
self::ticketNewStart($Context);
return;
}

Repository::updateUserSession($Context->UserId, ['Ticket_Category' => strtolower(trim($Category))]);
self::ticketPriorityMenu($Context);
}

public static function ticketPriorityMenu(Context $Context): void {
$Session = Repository::getUserSession($Context->UserId);
$Subject = (string)($Session['Ticket_Subject'] ?? '');
$Description = (string)($Session['Ticket_Description'] ?? '');
$Category = (string)($Session['Ticket_Category'] ?? 'other');
$Rows = [['text' => '🚦اولویت تیکت را انتخاب کنید:', 'callback_data' => 'اولویت تیکت:medium']];

foreach (Helper::ticketPriorities() as $Key => $Label) {
$Rows[] = [['text' => $Label, 'callback_data' => 'اولویت تیکت:' . $Key]];
}

$Rows[] = Common::backTo('🔙بازگشت به انتخاب دسته', 'انتخاب دسته تیکت');
$Rows[] = Common::mainButton();
$Text = Helper::userGreeting($Context, 'ایجاد تیکت جدید')
. "📋موضوع: {$Subject}\n"
. "📝توضیحات: " . ($Description !== '' && $Description !== 'ندارد' ? $Description : 'ندارد') . "\n"
. "📂دسته: " . Helper::ticketCategoryLabel($Category) . "\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "🚦*مرحله ۲ از ۲ — انتخاب اولویت تیکت*" . Helper::userFooter();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Rows));
}

public static function ticketPriorityCallback(Context $Context, string $Priority): void {
if (!Helper::isTicketPriority($Priority)) {
self::ticketPriorityMenu($Context);
return;
}

$Session = Repository::getUserSession($Context->UserId);
$Subject = (string)($Session['Ticket_Subject'] ?? '');

if (trim($Subject) === '') {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
self::ticketNewStart($Context);
return;
}

$Category = (string)($Session['Ticket_Category'] ?? 'other');

if (!Helper::isTicketCategory($Category)) {
$Category = 'other';
}

Repository::updateUserSession($Context->UserId, ['Ticket_Priority' => strtolower(trim($Priority))]);
self::ticketMediaInput($Context);
}

public static function ticketMediaInput(Context $Context): void {
$Session = Repository::getUserSession($Context->UserId);
$Subject = (string)($Session['Ticket_Subject'] ?? '');
$Description = (string)($Session['Ticket_Description'] ?? '');
$Media_Text = trim((string)($Context->Caption ?? $Context->Text ?? ''));
$Has_Media = $Context->Photo !== null || ($Media_Text !== '' && $Media_Text !== 'ندارد');

if ($Subject === '') {
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Ticket_Subject' => null, 'Ticket_Description' => null]);
TelegramClient::sendMessage($Context->ChatId, Helper::userGreeting($Context, 'ایجاد تیکت جدید') . "❌خطا در ایجاد تیکت.\n⚠️لطفاً دوباره تلاش کنید." . Helper::userFooter());
return;
}

$Category = (string)($Session['Ticket_Category'] ?? 'other');
$Priority = (string)($Session['Ticket_Priority'] ?? 'medium');

if (!Helper::isTicketCategory($Category)) $Category = 'other';

if (!Helper::isTicketPriority($Priority)) $Priority = 'medium';

$Category_Label = Helper::ticketCategoryLabel($Category);
$Priority_Label = Helper::ticketPriorityLabel($Priority);
$Ticket_ID = Repository::createTicket($Context->UserId, $Subject, $Category, $Priority);

if ($Description !== '' && $Description !== 'ندارد') {
Repository::addTicketMessage($Ticket_ID, $Context->UserId, 'user', "📝توضیحات: {$Description}");
}

if ($Has_Media) {
$Photo_File_ID = $Context->Photo !== null ? $Context->Photo : null;
$Caption = $Media_Text !== '' ? "📎پیوست: {$Media_Text}" : '📎پیوست';
Repository::addTicketMessage($Ticket_ID, $Context->UserId, 'user', $Caption, $Photo_File_ID);
}

Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Ticket_Subject' => null, 'Ticket_Description' => null, 'Ticket_Category' => 'other', 'Ticket_Priority' => 'medium']);
Repository::addNotification($Context->UserId, 'ticket', 'تیکت ایجاد شد', "تیکت #{$Ticket_ID}: {$Subject}");

$Admin = (int)Repository::getSetting('Administrator', (string)Environment::getAdminUserId());

if ($Admin > 0) {
$Admin_Text = Helper::adminGreetingNamed((string)(Repository::getSetting('Admin_Full_Name') ?: Environment::getAdminFullName()), 'مدیریت تیکت ها', $Admin) . "🎫تیکت جدید #{$Ticket_ID}\n➖➖➖➖➖➖➖➖➖\n👤کاربر: " . $Context->profileName() . "\n📋موضوع: {$Subject}\n" . "📂دسته: {$Category_Label}\n🚦اولویت: {$Priority_Label}\n";

if ($Description !== '' && $Description !== 'ندارد') {
$Admin_Text .= "📝توضیحات: {$Description}\n";
}

if ($Has_Media) {
$Admin_Text .= "📎دارای پیوست (عکس/فایل)\n";
}

$Admin_Text .= Helper::adminFooter();

if ($Context->Photo !== null) {
TelegramClient::sendPhoto($Admin, $Context->Photo, $Admin_Text, TelegramClient::inlineKeyboard([
[['text' => '🎫مشاهده تیکت', 'callback_data' => 'ticket_view:' . $Ticket_ID]],
[['text' => '✏️پاسخ به تیکت', 'callback_data' => 'ticket_reply:' . $Ticket_ID]],
]));
}

else {
TelegramClient::sendMessage($Admin, $Admin_Text, TelegramClient::inlineKeyboard([
[['text' => '🎫مشاهده تیکت', 'callback_data' => 'ticket_view:' . $Ticket_ID]],
[['text' => '✏️پاسخ به تیکت', 'callback_data' => 'ticket_reply:' . $Ticket_ID]],
]));
}
}

TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'تیکت های من') . "✅تیکت #" . Helper::toPersian((string)$Ticket_ID) . " ایجاد شد.\n➖➖➖➖➖➖➖➖➖\n📋موضوع: {$Subject}\n📂دسته: {$Category_Label}\n🚦اولویت: {$Priority_Label}\n\n⚠️ادمین به زودی پاسخ خواهد داد." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '🎫تیکت های من', 'callback_data' => 'تیکت های من']],
Common::mainButton(),
]));
}

public static function ticketUserList(Context $Context): void {
$Tickets = Repository::userTickets($Context->UserId);

if (empty($Tickets)) {
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, Common::greet($Context, 'تیکت های من') . "❌هیچ تیکتی ندارید.\n➖➖➖➖➖➖➖➖➖\n⚠️ابتدا یک تیکت جدید ایجاد کنید." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '➕ایجاد تیکت جدید', 'callback_data' => 'تیکت جدید']],
Common::mainButton(),
]));
return;
}

$Buttons = [];

foreach (array_slice($Tickets, 0, 10) as $T) {
$Status_Icon = ['open' => '🟡', 'pending' => '🟠', 'answered' => '🟢', 'closed' => '⚫'][$T['Status']] ?? '🟡';
$Buttons[] = [['text' => "{$Status_Icon} #{$T['ID']} - " . mb_substr((string)$T['Subject'], 0, 30), 'callback_data' => 'ticket_user_view:' . $T['ID']]];
}

$Buttons[] = [['text' => '🔙بازگشت به منوی قبل', 'callback_data' => 'تیکت های من']];
$Buttons[] = [['text' => '🏠بازگشت به منوی اصلی', 'callback_data' => 'منوی خدمات ربات']];
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, Common::greet($Context, 'تیکت های من') . "📋تیکت های من" . Helper::userFooter(), TelegramClient::inlineKeyboard($Buttons));
}

public static function ticketUserView(Context $Context, int $Ticket_ID): void {
$Ticket = Repository::getTicket($Ticket_ID);

if ($Ticket === null || (int)$Ticket['User_ID'] !== $Context->UserId) {
TelegramClient::answerCallbackQuery($Context->CallbackId, 'تیکت یافت نشد', true);
return;
}

$Messages = Repository::getTicketMessages($Ticket_ID);
$Status_Map = ['open' => '🟡باز', 'pending' => '🟠در انتظار', 'answered' => '🟢پاسخ داده شده', 'closed' => '⚫بسته شده'];
$Persian_Status = $Status_Map[$Ticket['Status']] ?? '🟡باز';
$Persian_Category = Helper::ticketCategoryLabel((string)($Ticket['Category'] ?? 'other'));
$Text = Helper::userGreeting($Context, "تیکت #{$Ticket_ID}");
$Text .= "📋موضوع: " . $Ticket['Subject'] . "\n";
$Text .= "📂دسته: *{$Persian_Category}*\n";
$Text .= "📊وضعیت: *{$Persian_Status}*\n\n";

foreach ($Messages as $Msg) {
$Sender = ($Msg['Sender_Type'] ?? 'user') === 'admin' ? '🛡ادمین' : '👤شما';
$Msg_Text = (string)($Msg['Message'] ?? '');

if ($Msg_Text === '') {
$Msg_Text = ($Msg['Photo_File_ID'] ?? null) !== null ? '[📎تصویر]' : '[💬هیچ متنی]';
}

$Text .= "{$Sender}: {$Msg_Text}\n";

if (!empty($Msg['Photo_File_ID'])) {
$Text .= "📎[پیوست تصویری]\n";
}
}

$Buttons = [];

if ($Ticket['Status'] !== 'closed') {
$Buttons[] = [['text' => '✏️پاسخ', 'callback_data' => 'ticket_user_reply:' . $Ticket_ID]];
}

$Buttons[] = [['text' => '🔙بازگشت به منوی قبل', 'callback_data' => 'لیست تیکت های من']];
$Buttons[] = [['text' => '🏠بازگشت به منوی اصلی', 'callback_data' => 'منوی خدمات ربات']];
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Text . Helper::userFooter(), TelegramClient::inlineKeyboard($Buttons));
}

public static function ticketUserReplyStart(Context $Context, int $Ticket_ID): void {
$Ticket = Repository::getTicket($Ticket_ID);
if ($Ticket === null || (int)$Ticket['User_ID'] !== $Context->UserId) return;
Repository::updateUserSession($Context->UserId, ['Flow' => 'user:ticket_reply_text', 'Temp_Ticket_ID' => $Ticket_ID]);
$Text = Helper::userGreeting($Context, "پاسخ به تیکت #{$Ticket_ID}") . 'پاسخ خود را وارد کنید:' . Helper::userFooter();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard([
[['text' => '🔙انصراف و بازگشت', 'callback_data' => 'لیست تیکت های من']],
]));
}

public static function ticketUserReplySend(Context $Context, string $Text): void {
$Session = Repository::getUserSession($Context->UserId);
$Ticket_ID = (int)($Session['Temp_Ticket_ID'] ?? 0);
$Ticket = Repository::getTicket($Ticket_ID);

if ($Ticket === null || (int)$Ticket['User_ID'] !== $Context->UserId) return;
Repository::addTicketMessage($Ticket_ID, $Context->UserId, 'user', $Text);
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Temp_Ticket_ID' => null]);

$Admin = (int)Repository::getSetting('Administrator', (string)Environment::getAdminUserId());

if ($Admin > 0) {
TelegramClient::sendMessage($Admin, Helper::adminGreetingNamed((string)(Repository::getSetting('Admin_Full_Name') ?: Environment::getAdminFullName()), 'مدیریت تیکت ها', $Admin) . "📨پاسخ جدید به تیکت #{$Ticket_ID}\n➖➖➖➖➖➖➖➖➖\n{$Text}" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🎫مشاهده تیکت', 'callback_data' => 'ticket_view:' . $Ticket_ID]],
]));
}

TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'پاسخ به تیکت') . "✅پاسخ شما ارسال شد." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '🎫تیکت های من', 'callback_data' => 'تیکت های من']],
Common::mainButton(),
]));
}

public static function usageAnalytics(Context $Context): void {
TelegramClient::sendChatAction($Context->ChatId);

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🔄در حال بارگذاری گزارش مصرف...', false);
}

$User = Common::liveUser(Repository::getUser($Context->UserId));
$Client_ID = (string)($User['Client_ID'] ?? '');

if ($Client_ID === '' || $Client_ID === '_') {
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, Common::greet($Context, 'گزارش مصرف') . "❌شما اشتراک فعالی ندارید.\n➖➖➖➖➖➖➖➖➖\n⚠️از بخش اشتراک من اقدام به خرید اشتراک کنید." . Helper::userFooter(), TelegramClient::inlineKeyboard([
Common::mainButton(),
]));
return;
}

$Response = ServerClient::getUser($Client_ID);
$Json = $Response['Json'] ?? [];
$Used_GB = (float)($Json['current_usage_GB'] ?? $User['Used_Usage_GB'] ?? 0);
$Total_GB = (float)($Json['usage_limit_GB'] ?? $User['Total_Usage_GB'] ?? 0);
$Remaining = max(0, $Total_GB - $Used_GB);
$Percent = $Total_GB > 0 ? round(($Used_GB / $Total_GB) * 100, 1) : 0;
$Last_Online = (string)($Json['last_online'] ?? '');
$Bar = Helper::usageBar($Percent, 14);
$Status_Icon = Helper::rankStatusIcon($Percent);
$Status_Label = Helper::rankStatusLabel($Percent);
$Last_Online_Label = 'نامشخص';
$Is_Online = false;

if ($Last_Online !== '' && $Last_Online !== '0001-01-01 00:00:00') {
try {
$Last_Stamp = \Helper::parseServerTimeSafe($Last_Online);

if ($Last_Stamp === false) throw new RuntimeException('Invalid last_online');
$Is_Online = (time() - $Last_Stamp) >= 0 && (time() - $Last_Stamp) <= 300;
$Last_Online_Label = Helper::gregorianToJalali(date('Y-m-d', $Last_Stamp)) . ' - ' . Helper::formatTime(date('H:i:s', $Last_Stamp)) . ' (' . Helper::humanAgo($Last_Stamp) . ')';
}

catch (Throwable) {
$Last_Online_Label = 'نامشخص';
$Is_Online = false;
}
}

$Board = self::liveUsageBoard();
$Board_Total = 0.0;
$My_Rank = 0;

foreach ($Board as $Index => $Row) {
$Board_Total += (float)($Row['Value'] ?? 0);

if ((int)($Row['Telegram_ID'] ?? 0) === $Context->UserId) {
$My_Rank = $Index + 1;
}
}

$Board_Count = count($Board);
$Today_Gain = Repository::userUsageGain($Context->UserId);
$History = Repository::userUsageHistory($Context->UserId, 7);
$History_Days = count($History);
$Daily_Avg = $History_Days > 0 ? array_sum($History) / $History_Days : null;
$Exp_Stamp = (int)($User['Expiration_Time_Stamp'] ?? 0);
$Subscription = trim((string)($User['Subscription'] ?? '')) ?: 'نامشخص';
$Text = Common::greet($Context, 'گزارش مصرف') . "📊<b>گزارش پیشرفته مصرف</b>\n➖➖➖➖➖➖➖➖➖\n";

if ($My_Rank > 0) {
$Text .= "🏆<b>رتبه شما در مصرف:</b> " . Helper::rankEmoji($My_Rank) . " <b>" . Helper::rankTitle($My_Rank) . "</b>\n";
$Text .= "📊<b>سهم شما از مصرف سرور:</b> *" . Helper::percentShare($Used_GB, $Board_Total) . "*\n\n";
}

$Text .= "📈<b>میزان مصرف شما:</b>\n`{$Bar}`\n";
$Text .= "{$Status_Icon}وضعیت: <b>{$Status_Label}</b> |📊درصد مصرف: <b>" . Helper::formatPercent($Percent) . "٪</b>\n";
$Text .= "├─📦<b>سهمیه کل:</b> <b>" . Helper::formatGB($Total_GB) . "</b>\n";
$Text .= "├─📥<b>مصرف شده:</b> <b>" . Helper::formatGB($Used_GB) . "</b>\n";
$Text .= "├─📤<b>باقیمانده:</b> <b>" . Helper::formatGB($Remaining) . "</b>\n";
$Text .= $Today_Gain === null
? "├─📅<b>مصرف امروز:</b> <b>نامشخص</b>\n"
: "├─📅<b>مصرف امروز:</b> <b>" . Helper::formatGB($Today_Gain) . "</b>\n";

if ($Daily_Avg !== null) {
$Text .= "├─🧮<b>میانگین مصرف ۷ روز اخیر:</b> <b>" . Helper::formatGB($Daily_Avg) . "</b> بر اساس " . Helper::toPersian((string)$History_Days) . " روز ثبت شده\n";
}

else {
$Text .= "├─🧮<b>میانگین مصرف ۷ روز اخیر:</b> <b>نامشخص (داده کافی ثبت نشده)</b>\n";
}

$Text .= "\n💎<b>وضعیت اشتراک:</b>\n";
$Text .= "├─🪪<b>نوع اشتراک:</b> <b>{$Subscription}</b>\n";
$Text .= "├─⏳<b>زمان باقیمانده:</b> <b>" . Helper::remainingDuration($Exp_Stamp) . "</b>\n";
$Text .= "├─📅<b>تاریخ انقضا:</b> <b>" . ($Exp_Stamp > 0 ? Helper::formatExpirationShort($Exp_Stamp) : 'نامشخص') . "</b>\n";
$Text .= "└─🕓<b>آخرین اتصال:</b> " . ($Is_Online ? "🟢" : "⚪️") . " <b>" . $Last_Online_Label . "</b>\n";

$Text .= Helper::userFooter();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard([
[['text' => '🔄بروزرسانی گزارش', 'callback_data' => 'گزارش مصرف']],
[['text' => '🔙بازگشت به منوی قبل', 'callback_data' => 'پروفایل کاربری']],
Common::mainButton(),
]));
}

public static function usageRanking(Context $Context): void {
TelegramClient::sendChatAction($Context->ChatId);

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🏆در حال بارگذاری رتبه بندی...', false);
}

$Board = self::liveUsageBoard();
$Board_Total = 0.0;

foreach ($Board as $Row) {
$Board_Total += (float)($Row['Value'] ?? 0);
}

$My_Rank = 0;
$My_Row = [];
$Index = 0;

foreach ($Board as $Row) {
$Index++;

if ((int)($Row['Telegram_ID'] ?? 0) === $Context->UserId) {
$My_Rank = $Index;
$My_Row = $Row;
}
}

$Text = Common::greet($Context, 'رتبه بندی کاربران') . "🏆*رتبه بندی کاربران سرور بر اساس مصرف:*\n";
$Text .= "📊مجموع مصرف کاربران سرور: *" . Helper::formatGB($Board_Total) . "*\n";
$Text .= "➖➖➖➖➖➖➖➖➖\n";
$Shown = 0;

foreach ($Board as $Row) {
$Shown++;

if ($Shown > 10) break;
$Name = trim((string)($Row['Full_Name'] ?? '')) ?: (trim((string)($Row['First_Name'] ?? '')) ?: 'کاربر');
$Name_Link = Helper::mention($Name, (int)($Row['Telegram_ID'] ?? 0), trim((string)($Row['Username'] ?? '')));
$Usage = (float)($Row['Value'] ?? 0);
$Share = $Board_Total > 0 ? ($Usage / $Board_Total) * 100.0 : 0.0;
$Text .= Helper::toPersian((string)$Shown) . ". " . Helper::rankMedal($Shown) . " {$Name_Link} — *" . Helper::formatGB($Usage) . "* (" . Helper::formatPercent($Share) . "٪)\n";
}

$Text .= "➖➖➖➖➖➖➖➖➖\n";

if ($My_Rank > 0) {
$Text .= "📌رتبه شما: " . Helper::rankEmoji($My_Rank) . "\n";
$Text .= "📊مصرف شما: *" . Helper::formatGB((float)($My_Row['Value'] ?? 0)) . "* از مجموع *" . Helper::formatGB($Board_Total) . "*\n";
$My_Share = $Board_Total > 0 ? (((float)($My_Row['Value'] ?? 0) / $Board_Total) * 100.0) : 0.0;
$Text .= "📈سهم شما از مصرف سرور: *" . Helper::formatPercent($My_Share) . "٪*\n";
}

else {
$Text .= "📌رتبه شما: *هنوز مصرفی روی سرور ثبت نشده است.*\n";
}

$Text .= Helper::userFooter();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard([
[['text' => '🔄بروزرسانی رتبه بندی', 'callback_data' => 'رتبه بندی کاربران']],
[['text' => '📊گزارش مصرف', 'callback_data' => 'گزارش مصرف']],
Common::mainButton(),
]));
}
}
?>