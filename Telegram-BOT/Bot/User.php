<?php
declare(strict_types=1);

require_once __DIR__ . '/Context.php';
require_once __DIR__ . '/Channel-Membership.php';
require_once __DIR__ . '/Ticket-Media.php';
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
$Welcome_Text = $Greeting . "🎉به ربات فیلترشکن آمبرلا خوش آمدید.\n👇برای دیدن خدمات ربات، دکمه زیر را بزنید:";
TelegramClient::sendMessage($Context->ChatId, $Welcome_Text, TelegramClient::inlineKeyboard([
[['text' => '🤖📋منوی خدمات ربات', 'callback_data' => 'منوی خدمات ربات']],
]));
}

else {
TelegramClient::sendMessage($Context->ChatId, "{$Greeting}🔒برای استفاده از امکانات ربات باید ابتدا عضو کانال شوید." . Helper::userFooter(), TelegramClient::inlineKeyboard([
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
$Result = ChannelMembership::restore($Context->UserId);
$Notice = match ($Result) {
'restored' => '✅عضویت تأیید و کلاینت دوباره فعال شد.',
'pending' => '⚠️عضویت تأیید شد، اما فعال سازی هنوز موفق نشده؛ دوباره تلاش کنید. بررسی خودکار نیز تکرار می شود.',
'ineligible' => '✅عضویت تأیید شد؛ اشتراک منقضی یا محدودیت دیگری مانع فعال سازی خودکار است. با پشتیبانی تماس بگیرید.',
default => '✅عضویت شما در کانال تأیید گردید.',
};
TelegramClient::sendMessage($Context->ChatId, $Greeting . $Notice . Helper::userFooter(), TelegramClient::inlineKeyboard([Menu::userHome()]));
return;
}

$Minutes = (int)ceil(Environment::getChannelGraceSeconds() / 60);
TelegramClient::sendMessage($Context->ChatId, "{$Greeting}⚠️شما عضو کانال اطلاع رسانی نیستید.\n\n🔒برای استفاده از امکانات ربات باید عضو کانال شوید." . Helper::userFooter(), TelegramClient::inlineKeyboard([
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
$Should_Call = $Last_Check <= 0 || (time() - $Last_Check) >= $TTL || $Grace_Started_At > 0 || $Is_Disabled;

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

ChannelMembership::restore($UserId);
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

Repository::touchUserTime($Context->UserId, 'Registered_At');
self::linkPanelAccount($Context);
$Admin = (int)Repository::getSetting('Administrator', (string)Environment::getAdminUserId());

if ($Admin <= 0) return;

try {
TelegramClient::sendSystemMessage(
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
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
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

$Text = Common::greet($Context, 'منوی خدمات ربات') . "\n📌*بخش مورد نظر را انتخاب کنید:*" . Helper::userFooter();
$Menu_Rows = Menu::rows([
[['💎مدیریت اشتراک', 'user_subscriptions_menu']],
[['💰کیف پول و مالی', 'user_wallet_menu']],
[['👤حساب کاربری', 'user_account_menu']],
[['📱دستگاه من', 'user_device_menu']],
[['📊سوابق و آمار', 'user_stats_menu']],
[['🎫پشتیبانی', 'منوی پشتیبانی']],
[['🔄تغییرات نسخه', 'تغییرات نسخه']],
]);
$Keyboard = TelegramClient::inlineKeyboard($Menu_Rows);

if ($Context->IsCallback && $Context->MessageId !== null) {
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, $Keyboard);
}

else {
TelegramClient::sendMessage($Context->ChatId, $Text, $Keyboard);
}
}

/** هر دسته ورودی قبلی را لغو می کند، بدون دست زدن به اطلاعات پرداخت. */
private static function categoryMenu(Context $Context, string $Title, array $Rows): void {
if (!Common::isRobotOn()) { self::serviceMenu($Context); return; }
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🔄در حال بارگذاری...', false);
}
$Rows[] = Menu::userHome();
$Text = Common::greet($Context, $Title) . "\n📌*بخش مورد نظر را انتخاب کنید:*" . Helper::userFooter();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Rows));
}

/** Menu eligibility uses the current subscription, not merely a leftover UUID. */
private static function subscriptionMenuState(int $UserId): array {
$User = Repository::getUser($UserId) ?? [];
$Live = null;
$Client = trim((string)($User['Client_ID'] ?? ''));
if ($Client !== '' && $Client !== '_' && trim((string)($User['Subscription'] ?? '')) !== '') {
try {
$Response = ServerClient::getUser($Client);
$Code = (int)($Response['StatusCode'] ?? 0);
$Data = $Response['Json'] ?? null;
if ($Code >= 200 && $Code < 300 && is_array($Data)
&& (!isset($Data['uuid']) || (string)$Data['uuid'] === $Client)) $Live = $Data;
} catch (Throwable $Error) { error_log('[Umbrella-Bot][Menu-Subscription] ' . $Error->getMessage()); }
}
return [$User, $Live];
}

private static function hasMenuSubscription(array $User): bool {
$Client = trim((string)($User['Client_ID'] ?? ''));
return $Client !== '' && $Client !== '_' && trim((string)($User['Subscription'] ?? '')) !== ''
&& (int)($User['Is_Blocked'] ?? 0) === 0
&& trim((string)($User['Deactivation_Message'] ?? '')) === ''
&& (int)($User['Channel_Client_Disabled_At'] ?? 0) <= 0;
}

private static function nightlyMenuVisible(array $User, ?array $Live): bool {
if (!self::hasMenuSubscription($User) || (int)($User['Expiration_Time_Stamp'] ?? 0) <= time()
|| !in_array((string)($User['Client_Status'] ?? ''), ['فعال', '✅فعال'], true)
|| $Live === null || (int)($Live['is_active'] ?? 0) !== 1 || (int)($Live['enable'] ?? 0) !== 1) return false;
$Limit = (float)($Live['usage_limit_GB'] ?? 0);
return $Limit <= 0 || (isset($Live['current_usage_GB']) && (float)$Live['current_usage_GB'] < $Limit);
}

private static function autoRenewMenuVisible(array $User, ?array $Live): bool {
if (!self::hasMenuSubscription($User)) return false;
$Expires = (int)($User['Expiration_Time_Stamp'] ?? 0);
// Exact inclusive 72-hour boundary; unknown/zero dates are not "due".
$Due = $Expires > 0 && $Expires <= time() + 3 * 86400;
$Limit = (float)($Live['usage_limit_GB'] ?? 0);
$Exhausted = $Live !== null && $Limit > 0 && isset($Live['current_usage_GB'])
&& (float)$Live['current_usage_GB'] >= $Limit;
return $Due || $Exhausted;
}

private static function guardAutoRenewMenu(Context $Context): bool {
[$User, $Live] = self::subscriptionMenuState($Context->UserId);
if (self::autoRenewMenuVisible($User, $Live)) return true;
self::subscriptionsMenu($Context);
return false;
}

public static function subscriptionsMenu(Context $Context): void {
if (!Common::isRobotOn()) { self::serviceMenu($Context); return; }
[$User, $Live] = self::subscriptionMenuState($Context->UserId);
$Subscription = trim((string)($User['Subscription'] ?? ''));
$Expires_At = (int)($User['Expiration_Time_Stamp'] ?? 0);
// توقف کلاینت، مالکیت اشتراک را از بین نمی برد. تاریخ نامشخص نیز
// نباید باعث نمایش خرید مجدد برای اشتراک ثبت شده شود.
$Has_Subscription = $Subscription !== '' && ($Expires_At <= 0 || $Expires_At > time());
$Rows = Menu::rows([
[['💎اشتراک من', 'اشتراک من']],
]);
if (!$Has_Subscription) {
$Rows = array_merge($Rows, Menu::rows([
[['💎اشتراک های آماده', 'اشتراک آماده'], ['🛠اشتراک دلخواه', 'اشتراک دلخواه']],
]));
if ((int)($User['Free_Plan_Claimed'] ?? 0) !== 1) {
$Rows[] = [Menu::button('🎁اشتراک رایگان', 'اشتراک رایگان اول')];
}
$Client_Uuid = (string)($User['Client_ID'] ?? '');
if (class_exists('BotConfig')
&& method_exists(BotConfig::class, 'isNowruzMenuEnabled')
&& BotConfig::isNowruzMenuEnabled()
&& !BotConfig::hasClaimedNowruz($Context->UserId, $Client_Uuid)) {
$Rows[] = [Menu::button('🌷اشتراک نوروزی', 'اشتراک نوروزی اول')];
}
}
if (self::autoRenewMenuVisible($User, $Live)) {
$Rows[] = [Menu::button('🔄تمدید خودکار', 'منوی تمدید خودکار')];
}
self::categoryMenu($Context, 'مدیریت اشتراک', $Rows);
}

public static function walletMenu(Context $Context): void {
$Rows = Menu::rows([
[['💰شارژ کیف پول', 'شارژ اعتبار حساب کاربری']],
[['📋سابقه تراکنش', 'سابقه تراکنش']],
]);
self::categoryMenu($Context, 'کیف پول و مالی', $Rows);
}

public static function accountMenu(Context $Context): void {
$Rows = Menu::rows([
[['👤پروفایل کاربری', 'پروفایل کاربری']],
[['✏️ویرایش پروفایل', 'ویرایش پروفایل']],
]);
[$User, $Live] = self::subscriptionMenuState($Context->UserId);
if (self::nightlyMenuVisible($User, $Live)) {
$On = Repository::nightlyReportEnabled($Context->UserId);
$Rows[] = [Menu::button($On ? '🔔گزارش شبانه: روشن — خاموش کردن' : '🔕گزارش شبانه: خاموش — روشن کردن', $On ? 'nightly_report_off' : 'nightly_report_on')];
}
self::categoryMenu($Context, 'حساب کاربری', $Rows);
}

public static function deviceMenu(Context $Context): void {
self::categoryMenu($Context, 'دستگاه من', Menu::rows([
[['🛡کنترل محتوا', 'app_filter']],
[['🔐تأیید دومرحله ای', 'app_2fa']],
[['📱دستگاه های من', 'app_devices']],
]));
}

public static function setNightlyReport(Context $Context, bool $Enabled): void {
[$User, $Live] = self::subscriptionMenuState($Context->UserId);
if (self::nightlyMenuVisible($User, $Live)) Repository::setNightlyReportEnabled($Context->UserId, $Enabled);
self::accountMenu($Context);
}

public static function statsMenu(Context $Context): void {
$Rows = Menu::rows([
[['📋سابقه اشتراک', 'سابقه اشتراک'], ['📊گزارش مصرف', 'گزارش مصرف']],
[['🏆رتبه بندی کاربران', 'رتبه بندی کاربران']],
]);
self::categoryMenu($Context, 'سوابق و آمار', $Rows);
}

/** دسته پشتیبانی و تیکت ها. */
public static function supportMenu(Context $Context): void {
$Rows = Menu::rows([
[['🎫تیکت های من', 'لیست تیکت های من']],
[['➕ایجاد تیکت جدید', 'تیکت جدید']],
]);
self::categoryMenu($Context, 'پشتیبانی', $Rows);
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
Menu::back('منوی قبلی', 'user_account_menu'), Menu::userHome()
]));

return;
}

$Subscription = $User['Subscription'] ?? null;
$Client_ID = (string)($User['Client_ID'] ?? '');
$Client_Status = (string)($User['Client_Status'] ?? 'نامشخص');
$Last_Online = (string)($User['Last_Online'] ?? '');
$Operator = Helper::detectOperator((string)$Phone);

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
. "└─🆔شناسه کلاینت: `{$Client_ID}`\n"
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
}

else {
$Auto_Renew_Label = '*🔴غیرفعال*';
}

$Profile_Text = "👤نام و نام خانوادگی: *" . Helper::mention((string)$FullName, $Context->UserId) . "*\n"
. "📞شماره موبایل: " . Helper::toPersian((string)$Phone) . " (*اپراتور پایه: {$Operator}*)\n"
. "💳اعتبار حساب: *{$Balance_Formatted}*\n"
. "🆔شناسه تلگرام: `" . Helper::toPersian((string)$Context->UserId) . "`\n"
. $Rank_Line
. ($Auto_Renew_Visible ? "🔄تمدید خودکار: {$Auto_Renew_Label}\n" : '')
. "📅تاریخ عضویت: *{$Created_At_Label}*\n"
. "🕰آخرین بروزرسانی پروفایل: *{$Profile_Updated_Label}*\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "💎*اشتراک:*\n"
. "{$Subscription_Text}";

$Profile_Buttons = [Menu::back('منوی قبلی', 'user_account_menu'), Menu::userHome()];
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Greeting . "🔰اطلاعات پروفایل شما به شرح زیر است:\n\n" . $Profile_Text . Helper::userFooter(), TelegramClient::inlineKeyboard($Profile_Buttons));
}

public static function autoRenewMenu(Context $Context): void {
if (!self::guardAutoRenewMenu($Context)) return;
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
. Menu::section('🔄', 'تمدید خودکار اشتراک', [
'📌وضعیت فعلی: *' . $Status . '*',
'💳موجودی کیف پول: *' . Helper::formatCurrency($Balance) . '*',
'⏳زمان باقیمانده اشتراک: *' . Helper::remainingDuration($Exp_Stamp) . '*',
])
. 'ℹ️در صورت فعال بودن، ' . Helper::toPersian('3') . " روز قبل از انقضا، ⏳اشتراک شما به صورت خودکار از موجودی کیف پول تمدید می شود.\n"
. '📌*برای فعال کردن، پلن مورد نظر را انتخاب کنید:*';
$Rows = [];

foreach (self::AUTO_RENEW_PLANS as $Key => $Label) {
$Price = BotConfig::getPlanPrice((int)$Key);
$Price_Label = $Price > 0 ? Helper::formatCurrency($Price) : 'قیمت ثبت نشده';
$Mark = $Current === $Key ? '✅' : '🟢';
$Rows[] = [['text' => "{$Mark}فعال: {$Label} - {$Price_Label}", 'callback_data' => 'auto_renew_on_' . $Key]];
}

$Rows = array_merge($Rows, Menu::rows([
[['⛔️غیرفعال کردن تمدید خودکار', 'auto_renew_off']],
]));
$Rows[] = Menu::back('منوی قبلی', 'user_subscriptions_menu');
$Rows[] = Menu::userHome();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text . Helper::userFooter(), TelegramClient::inlineKeyboard($Rows));
}

public static function enableAutoRenew(Context $Context): void {
if (!self::guardAutoRenewMenu($Context)) return;
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

if (!self::guardAutoRenewMenu($Context)) return;

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
) . Helper::userFooter(), TelegramClient::inlineKeyboard(array_merge([
[['text' => '💰شارژ اعتبار حساب کاربری', 'callback_data' => 'شارژ اعتبار حساب کاربری']],
], Menu::userNav('پروفایل کاربری', 'پروفایل کاربری'))));
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
$Total = Repository::countTransactions($Context->UserId);
$Total_Pages = max(1, (int)ceil($Total / 5));
$Page = min($Page, $Total_Pages);
$Transactions = Repository::getTransactions($Context->UserId, $Page, 5);
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
$Text .= "📋تراکنش #" . Helper::toPersian((string)(($Page - 1) * 5 + $Index + 1)) . ":\n";
$Text .= "🔸{$Type_Label}\n";
$Text .= "🏷️انجام شده توسط: <b>{$Source_Label}</b>\n";
$Text .= "📝{$Desc}\n";
$Text .= "📆{$Date}🕰{$Time}\n";
$Text .= "{$Sign_Icon}مبلغ: <b>{$Amount}</b>\n";
$Text .= "👛موجودی پس از تراکنش: <b>{$Balance_After}</b>\n";
$Text .= "➖➖➖➖➖➖➖➖➖\n";
}

$Text .= "📄صفحه " . Helper::toPersian((string)$Page) . " از " . Helper::toPersian((string)$Total_Pages) . Helper::userFooter() . "*";
}

$Buttons = [];
if ($Page > 1) $Buttons[] = [Menu::button('⬅️صفحه قبل', 'سابقه تراکنش|' . ($Page - 1))];

if ($Page < $Total_Pages) {
$Buttons[] = [['text' => 'صفحه بعد➡️', 'callback_data' => 'سابقه تراکنش|' . ($Page + 1)]];
}

$Buttons[] = Menu::back('منوی قبلی', 'user_wallet_menu');
$Buttons[] = Menu::userHome();

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
$Total = Repository::countSubscriptionLogs($Context->UserId);
$Total_Pages = max(1, (int)ceil($Total / 5));
$Page = min($Page, $Total_Pages);
$Logs = Repository::getSubscriptionLogs($Context->UserId, $Page, 5);
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
$Text .= "📋سابقه #" . Helper::toPersian((string)(($Page - 1) * 5 + $Index + 1)) . ":\n";
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
if ($Page > 1) $Buttons[] = [Menu::button('⬅️صفحه قبل', 'سابقه اشتراک|' . ($Page - 1))];

if ($Page < $Total_Pages) {
$Buttons[] = [['text' => 'صفحه بعد➡️', 'callback_data' => 'سابقه اشتراک|' . ($Page + 1)]];
}

$Buttons[] = Menu::back('منوی قبلی', 'user_stats_menu');
$Buttons[] = Menu::userHome();

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
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Greeting . "🔰اطلاعات بروز رسانی جدید بدین شرح است:\n\n🔄نسخه جدید ربات: {$Version_P}\n\n{$Changes_Text}" . Helper::userFooter(), TelegramClient::inlineKeyboard([Menu::userHome()]));
}

/** سازگاری با دکمه های قدیمی: هدایت به صفحه یکپارچه تیکت های من. */
public static function ticketMenu(Context $Context): void {
self::ticketUserList($Context);
}

public static function ticketNewStart(Context $Context): void {
Repository::updateUserSession($Context->UserId, ['Flow' => 'user:ticket_subject', 'Ticket_Media_JSON' => null, 'Ticket_Description' => null]);
$Text = Helper::userGreeting($Context, 'ایجاد تیکت جدید') . "📝موضوع تیکت را وارد کنید:\n➖➖➖➖➖➖➖➖➖\n⚠️جهت انصراف «لغو» را ارسال کنید." . Helper::userFooter();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard([Menu::back('منوی قبلی', 'منوی پشتیبانی'), Menu::userHome()]));
}

public static function ticketCreate(Context $Context, string $Subject): void {
$Media = TicketMedia::extract($Context);
if ($Media !== null && trim($Subject) === '') $Subject = 'پشتیبانی با پیوست';
$Subject = mb_substr(trim($Subject), 0, 200);

if ($Subject === '') {
TelegramClient::sendMessage($Context->ChatId, Helper::userGreeting($Context, 'ایجاد تیکت جدید') . "❌موضوع نمی تواند خالی باشد.\n⚠️لطفاً موضوع تیکت را وارد کنید." . Helper::userFooter(), TelegramClient::inlineKeyboard([Menu::userHome()]));
return;
}

Repository::updateUserSession($Context->UserId, ['Ticket_Subject' => $Subject, 'Flow' => 'user:ticket_description']);
if ($Media !== null) { self::ticketDescriptionInput($Context, (string)($Context->Caption ?? '')); return; }
$Text = Helper::userGreeting($Context, 'ایجاد تیکت جدید') . "📋موضوع: {$Subject}\n\n📝توضیحات یا عکس، ویدیو، فایل، صدا یا استیکر را با کپشن یا بدون کپشن بفرستید (یا «ندارد»):\n➖➖➖➖➖➖➖➖➖\n⚠️جهت انصراف «لغو» را ارسال کنید." . Helper::userFooter();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard(Menu::userNav('ویرایش موضوع', 'تیکت جدید')));
}

public static function ticketDescriptionInput(Context $Context, string $Text): void {
$Media = TicketMedia::extract($Context);
$Draft = Repository::getUserSession($Context->UserId);
$Description = mb_substr(trim($Text), 0, 1000);
if ($Media !== null && ($Draft['Flow'] ?? '') === 'user:ticket_category' && !empty($Draft['Ticket_Description'])) $Description = (string)$Draft['Ticket_Description'];
if ($Media !== null) {
$Saved = json_decode((string)($Draft['Ticket_Media_JSON'] ?? ''), true) ?: [];
if (count($Saved) >= 10) { TelegramClient::sendMessage($Context->ChatId, '⚠️حداکثر ۱۰ پیوست برای ایجاد تیکت؛ موارد بیشتر را پس از ثبت در پاسخ تیکت بفرستید.'); return; }
$Saved[] = $Media;
Repository::updateUserSession($Context->UserId, ['Ticket_Media_JSON' => json_encode($Saved, JSON_UNESCAPED_UNICODE)]);
if ($Description === '') $Description = '📎پیوست بدون کپشن';
}
Repository::updateUserSession($Context->UserId, ['Ticket_Description' => $Description, 'Flow' => 'user:ticket_category']);
self::ticketCategoryMenu($Context);
}

public static function ticketCategoryMenu(Context $Context): void {
$Session = Repository::getUserSession($Context->UserId);
$Subject = (string)($Session['Ticket_Subject'] ?? '');
$Description = (string)($Session['Ticket_Description'] ?? '');
$Rows = [];

foreach (Helper::ticketCategories() as $Key => $Label) {
$Rows[] = [['text' => $Label, 'callback_data' => 'دسته تیکت:' . $Key]];
}

$Rows[] = Menu::back('ویرایش توضیحات', 'ویرایش توضیحات تیکت');
$Rows[] = Menu::userHome();
$Text = Helper::userGreeting($Context, 'ایجاد تیکت جدید')
. "📋موضوع: {$Subject}\n"
. "📝توضیحات: " . ($Description !== '' && $Description !== 'ندارد' ? $Description : 'ندارد') . "\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "📂*مرحله ۱ از ۲ — انتخاب دسته تیکت*" . Helper::userFooter();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Rows));
}

public static function ticketDescriptionStart(Context $Context): void {
$Session = Repository::getUserSession($Context->UserId);
$Subject = trim((string)($Session['Ticket_Subject'] ?? ''));
if ($Subject === '') {
self::ticketNewStart($Context);
return;
}
Repository::updateUserSession($Context->UserId, ['Flow' => 'user:ticket_description']);
$Description = trim((string)($Session['Ticket_Description'] ?? ''));
$Text = Helper::userGreeting($Context, 'ایجاد تیکت جدید')
. "📋موضوع: {$Subject}\n\n📝توضیحات یا عکس، ویدیو، فایل، صدا یا استیکر را با کپشن یا بدون کپشن بفرستید (یا «ندارد»):\n"
. ($Description !== '' ? "✏️توضیحات قبلی: {$Description}\n" : '')
. "➖➖➖➖➖➖➖➖➖\n⚠️جهت انصراف «لغو» را ارسال کنید." . Helper::userFooter();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard([
Menu::back('ویرایش موضوع', 'تیکت جدید'),
Menu::userHome(),
]));
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
$Rows = [];

foreach (Helper::ticketPriorities() as $Key => $Label) {
$Rows[] = [['text' => $Label, 'callback_data' => 'اولویت تیکت:' . $Key]];
}

$Rows[] = Menu::back('انتخاب دسته تیکت', 'انتخاب دسته تیکت');
$Rows[] = Menu::userHome();
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
$Attachments = json_decode((string)($Session['Ticket_Media_JSON'] ?? ''), true) ?: [];
$NewMedia = TicketMedia::extract($Context);
if ($NewMedia !== null) $Attachments[] = $NewMedia;
$Has_Media = $Attachments !== [];

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

foreach ($Attachments as $Media) {
Repository::addTicketMessage($Ticket_ID, $Context->UserId, 'user', (string)($Media['caption'] ?? '📎پیوست'), null, json_encode($Media, JSON_UNESCAPED_UNICODE));
}

Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Ticket_Subject' => null, 'Ticket_Description' => null, 'Ticket_Media_JSON' => null, 'Ticket_Category' => 'other', 'Ticket_Priority' => 'medium']);
Repository::addNotification($Context->UserId, 'ticket', '🎫تیکت ایجاد شد', "🎫تیکت #{$Ticket_ID}: {$Subject}");

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

TelegramClient::sendReadableMessage($Admin, null, $Admin_Text, TelegramClient::inlineKeyboard([
[['text' => '🎫مشاهده تیکت', 'callback_data' => 'ticket_view:' . $Ticket_ID]],
[['text' => '✏️پاسخ به تیکت', 'callback_data' => 'ticket_reply:' . $Ticket_ID]],
]));
foreach ($Attachments as $Media) {
if (!TicketMedia::send($Admin, $Media)) TelegramClient::sendMessage($Admin, '⚠️ارسال پیوست ناموفق بود؛ از بخش پیوست های تیکت دوباره تلاش کنید.');
}

}

TelegramClient::sendSystemMessage($Context->ChatId, Common::greet($Context, 'تیکت های من') . "✅تیکت #" . Helper::toPersian((string)$Ticket_ID) . " ایجاد شد.\n➖➖➖➖➖➖➖➖➖\n📋موضوع: {$Subject}\n📂دسته: {$Category_Label}\n🚦اولویت: {$Priority_Label}\n\n⚠️ادمین به زودی پاسخ خواهد داد." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '🎫تیکت های من', 'callback_data' => 'لیست تیکت های من']],
Menu::userHome(),
]));
}

public static function ticketUserList(Context $Context, int $Page = 0): void {
TelegramClient::sendChatAction($Context->ChatId);
$Tickets = Repository::userTickets($Context->UserId);
$PageCount = max(1, (int)ceil(count($Tickets) / 8));
$Page = max(0, min($Page, $PageCount - 1));
$Open_Count = 0;

foreach ($Tickets as $T) {
if (in_array($T['Status'], ['open', 'pending', 'answered'], true)) $Open_Count++;
}

$Text = Helper::userGreeting($Context, 'تیکت های من')
. Menu::section('🎫', 'آمار تیکت های شما', [
'📊تیکت های باز: *' . Helper::toPersian((string)$Open_Count) . '*',
'📋کل تیکت ها: *' . Helper::toPersian((string)count($Tickets)) . '*',
]);

if (empty($Tickets)) {
$Text .= "❌*هیچ تیکتی ثبت نکرده اید.*" . Helper::userFooter();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard([
Menu::back('منوی قبلی', 'منوی پشتیبانی'), Menu::userHome(),
]));
return;
}

$Text .= '📌*برای مشاهده جزئیات و پاسخ، تیکت مورد نظر را انتخاب کنید:*' . Helper::userFooter();
$Buttons = [];

foreach (array_slice($Tickets, $Page * 8, 8) as $T) {
$Status_Icon = ['open' => '🟡', 'pending' => '🟠', 'answered' => '🟢', 'closed' => '⚫'][$T['Status']] ?? '🟡';
$Buttons[] = [['text' => "{$Status_Icon} #{$T['ID']} - " . mb_substr((string)$T['Subject'], 0, 30), 'callback_data' => 'ticket_user_view:' . $T['ID']]];
}

$Text .= Menu::pageLabel($Page, $PageCount);
$Buttons = array_merge($Buttons, Menu::pages($Page, $PageCount, 'user_tickets_page:'));
$Buttons[] = Menu::back('منوی قبلی', 'منوی پشتیبانی');
$Buttons[] = Menu::userHome();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Buttons));
}

public static function ticketUserView(Context $Context, int $Ticket_ID, int $Page = 0): void {
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

$Thread = '';
foreach ($Messages as $Msg) {
$Sender = ($Msg['Sender_Type'] ?? 'user') === 'admin' ? '🛡ادمین' : '👤شما';
$Msg_Text = (string)($Msg['Message'] ?? '');

if ($Msg_Text === '') {
$Msg_Text = TicketMedia::decode($Msg) !== null ? '[📎پیوست]' : '[💬هیچ متنی]';
}

$Thread .= "{$Sender}: {$Msg_Text}\n";

if (TicketMedia::decode($Msg) !== null) {
$Thread .= "📎[پیوست؛ از دکمه پیوست های تیکت باز کنید]\n";
}
}

[$ThreadPage, $Page, $PageCount] = Menu::textPage($Thread, $Page);
$Text .= Menu::pageLabel($Page, $PageCount) . $ThreadPage;

$Buttons = Menu::pages($Page, $PageCount, 'user_ticket_messages:' . $Ticket_ID . ':');

if ($Ticket['Status'] !== 'closed') {
$Buttons[] = [['text' => '✏️پاسخ', 'callback_data' => 'ticket_user_reply:' . $Ticket_ID]];
}

$Buttons[] = [Menu::button('📎پیوست های تیکت', 'ticket_attachments:' . $Ticket_ID . ':0')];
$Buttons = array_merge($Buttons, Menu::userNav('لیست تیکت های من', 'لیست تیکت های من'));
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text . Helper::userFooter(), TelegramClient::inlineKeyboard($Buttons));
}

public static function ticketAttachments(Context $Context, int $TicketId, int $Page = 0): void {
$Ticket = Repository::getTicket($TicketId);
if ($Ticket === null || (!$Context->isAdmin() && (int)$Ticket['User_ID'] !== $Context->UserId)) return;
[$Rows, $Page, $Count] = TicketMedia::buttons(Repository::getTicketMessages($TicketId), $Page);
$Empty = $Rows === [];
$Rows = array_merge($Rows, Menu::pages($Page, $Count, 'ticket_attachments:' . $TicketId . ':'));
$Rows[] = Menu::back('تیکت', ($Context->isAdmin() ? 'ticket_view:' : 'ticket_user_view:') . $TicketId);
$Rows[] = $Context->isAdmin() ? Menu::adminHome() : Menu::userHome();
$Text = ($Context->isAdmin() ? Helper::adminGreeting($Context, 'پیوست های تیکت') : Helper::userGreeting($Context, 'پیوست های تیکت')) . Menu::pageLabel($Page, $Count) . ($Empty ? '📭پیوستی ثبت نشده است.' : '📎پیوست مورد نظر را انتخاب کنید.');
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Rows));
}

public static function ticketUserReplyStart(Context $Context, int $Ticket_ID): void {
$Ticket = Repository::getTicket($Ticket_ID);
if ($Ticket === null || (int)$Ticket['User_ID'] !== $Context->UserId) return;
Repository::updateUserSession($Context->UserId, ['Flow' => 'user:ticket_reply_text', 'Temp_Ticket_ID' => $Ticket_ID]);
$Text = Helper::userGreeting($Context, "پاسخ به تیکت #{$Ticket_ID}") . '✏️📝پاسخ یا رسانه را با کپشن یا بدون کپشن بفرستید؛ برای پایان از بازگشت استفاده کنید:' . Helper::userFooter();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard(Menu::userNav('مشاهده تیکت', 'ticket_user_view:' . $Ticket_ID)));
}

public static function ticketUserReplySend(Context $Context, string $Text): void {
$Session = Repository::getUserSession($Context->UserId);
$Ticket_ID = (int)($Session['Temp_Ticket_ID'] ?? 0);
$Ticket = Repository::getTicket($Ticket_ID);

if ($Ticket === null || (int)$Ticket['User_ID'] !== $Context->UserId) return;
if ($Ticket['Status'] === 'closed') return;
$Media = TicketMedia::extract($Context);
if (trim($Text) === '' && $Media === null) return;
Repository::addTicketMessage($Ticket_ID, $Context->UserId, 'user', $Text, null, $Media !== null ? json_encode($Media, JSON_UNESCAPED_UNICODE) : null);
// حالت پاسخ باز می ماند تا فایل های پشت سرهم/آلبوم گم نشوند؛ بازگشت آن را لغو می کند.


$Admin = (int)Repository::getSetting('Administrator', (string)Environment::getAdminUserId());

if ($Admin > 0) {
TelegramClient::sendReadableMessage($Admin, null, Helper::adminGreetingNamed((string)(Repository::getSetting('Admin_Full_Name') ?: Environment::getAdminFullName()), 'مدیریت تیکت ها', $Admin) . "📨پاسخ جدید به تیکت #{$Ticket_ID}\n➖➖➖➖➖➖➖➖➖\n{$Text}" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🎫مشاهده تیکت', 'callback_data' => 'ticket_view:' . $Ticket_ID]],
]));
if ($Media !== null && !TicketMedia::send($Admin, $Media)) TelegramClient::sendMessage($Admin, '⚠️پیوست دریافت نشد؛ از پیوست های تیکت دوباره تلاش کنید.');
}

TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'پاسخ به تیکت') . "✅پاسخ در تیکت ثبت شد. می توانید پیام یا پیوست بعدی را بفرستید؛ برای پایان دکمه بازگشت را بزنید." . Helper::userFooter(), TelegramClient::inlineKeyboard(Menu::userNav('لیست تیکت های من', 'لیست تیکت های من')));
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
Menu::back('منوی قبلی', 'user_stats_menu'), Menu::userHome(),
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
$Markup = array_merge(
Menu::rows([
[['🔄بروزرسانی گزارش', 'گزارش مصرف']],
]),
[Menu::back('منوی قبلی', 'user_stats_menu'), Menu::userHome()]
);
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Markup));
}

public static function usageRanking(Context $Context, int $Page = 0): void {
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

$Board_Count = count($Board);
$Board_Top = 0.0;

foreach ($Board as $Row) {
$Board_Top = max($Board_Top, (float)($Row['Value'] ?? 0));
}

$Board_Avg = $Board_Count > 0 ? $Board_Total / $Board_Count : 0.0;
$Text = Common::greet($Context, 'رتبه بندی کاربران') . "🏆👑*رتبه بندی کاربران سرور بر اساس مصرف:*\n";
$Text .= "👥کاربران سرور: *" . Helper::toPersian((string)$Board_Count) . "* |📥مجموع مصرف: *" . Helper::formatGB($Board_Total) . "* |🧮میانگین: *" . Helper::formatGB($Board_Avg) . "*\n";
$Text .= "🥇جایگاه اول |🥈دوم |🥉سوم |🔥سهم بیش از ۲۵٪ |⭐️ردیف خود شما\n";
$Text .= "➖➖➖➖➖➖➖➖➖\n";
$PageCount = max(1, (int)ceil($Board_Count / 10));
$Page = max(0, min($Page, $PageCount - 1));
$Text .= Menu::pageLabel($Page, $PageCount);
$Shown = $Page * 10;

foreach (array_slice($Board, $Page * 10, 10) as $Row) {
$Shown++;
$Name = trim((string)($Row['Full_Name'] ?? '')) ?: (trim((string)($Row['First_Name'] ?? '')) ?: 'کاربر');
$Name_Link = Helper::mention($Name, (int)($Row['Telegram_ID'] ?? 0), trim((string)($Row['Username'] ?? '')));
$Usage = (float)($Row['Value'] ?? 0);
$Share = $Board_Total > 0 ? ($Usage / $Board_Total) * 100.0 : 0.0;
$Is_Me = (int)($Row['Telegram_ID'] ?? 0) === $Context->UserId;
$Marks = ($Is_Me ? '⭐️' : '') . ($Shown === 1 ? '👑' : '');

if ($Share >= 25.0) $Marks .= '🔥';

$Bar_Percent = $Board_Top > 0 ? min(100.0, ($Usage / $Board_Top) * 100.0) : 0.0;
$Row_Name = $Name_Link . ($Is_Me ? ' (شما)' : '');
$Text .= Helper::rankLine($Shown, $Row_Name, Helper::formatGB($Usage), $Share, $Bar_Percent, $Marks) . "\n";
}

$Text .= "➖➖➖➖➖➖➖➖➖\n";

if ($My_Rank > 0) {
$My_Share = $Board_Total > 0 ? (((float)($My_Row['Value'] ?? 0) / $Board_Total) * 100.0) : 0.0;
$Text .= "📌رتبه شما: " . Helper::rankEmoji($My_Rank) . " *" . Helper::toPersian((string)$My_Rank) . "* از *" . Helper::toPersian((string)$Board_Count) . "* کاربر\n";
$Text .= "🏅عنوان شما: *" . Helper::rankTitle($My_Rank) . "*\n";
$Text .= "📊مصرف شما: *" . Helper::formatGB((float)($My_Row['Value'] ?? 0)) . "* از مجموع *" . Helper::formatGB($Board_Total) . "*\n";
$Text .= "📈سهم شما از مصرف سرور: *" . Helper::formatPercent($My_Share) . "٪* " . Helper::usageBar($My_Share, 10) . "\n";
}

else {
$Text .= "📌رتبه شما: *هنوز مصرفی روی سرور ثبت نشده است.*\n";
}

$Text .= Helper::userFooter();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard(array_merge(Menu::pages($Page, $PageCount, 'user_ranking_page:'), [
[['text' => '🔄بروزرسانی رتبه بندی', 'callback_data' => 'رتبه بندی کاربران']],
Menu::back('منوی قبلی', 'user_stats_menu'), Menu::userHome(),
])));
}
}
?>