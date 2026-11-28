<?php
declare(strict_types=1);

require_once __DIR__ . '/Context.php';
require_once __DIR__ . '/Channel-Membership.php';
require_once __DIR__ . '/Ticket-Media.php';
require_once __DIR__ . '/Common.php';
require_once __DIR__ . '/../Core/Telegram/Telegram.php';
require_once __DIR__ . '/../Core/Server/Umbrella-Server.php';
require_once __DIR__ . '/../Core/Server/Umbrella-Panel.php';
require_once __DIR__ . '/../Core/App/Release-Catalog.php';
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
if (class_exists('ChannelMembership') && method_exists('ChannelMembership', 'markPendingJoin')) {
ChannelMembership::markPendingJoin($Context->UserId, $Context->ChatId);
}
TelegramClient::sendMessage($Context->ChatId, "{$Greeting}⚠️در حال حاضر امکان استعلام خودکار عضویت در کانال وجود ندارد.\n\n✨پس از عضویت در کانال، ربات به صورت خودکار عضویت شما را بررسی و دسترسی را فعال می کند." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '📢عضویت در کانال', 'url' => $Channel_Url]],
]));
return;
}

if ($Status === 'member') {
if (class_exists('ChannelMembership') && method_exists('ChannelMembership', 'clearPendingJoin')) {
ChannelMembership::clearPendingJoin($Context->UserId);
}
self::registerNewUserFeedback($Context);
$Welcome_Text = $Greeting . "🎉به ربات فیلترشکن آمبرلا خوش آمدید.\n👇برای دیدن خدمات ربات، دکمه زیر را بزنید:" . Helper::userFooter();
TelegramClient::sendMessage($Context->ChatId, $Welcome_Text, TelegramClient::inlineKeyboard([
[['text' => '🤖📋منوی خدمات ربات', 'callback_data' => 'منوی خدمات ربات']],
]));
if (!class_exists('AppBotLink')) {
$AppLinkPath = __DIR__ . '/../Core/App/App-Bot-Link.php';
if (is_file($AppLinkPath)) require_once $AppLinkPath;
}
if (class_exists('AppBotLink') && method_exists('AppBotLink', 'resumePendingIfAny')) {
AppBotLink::resumePendingIfAny($Context);
}
}

else {
if (class_exists('ChannelMembership') && method_exists('ChannelMembership', 'markPendingJoin')) {
ChannelMembership::markPendingJoin($Context->UserId, $Context->ChatId);
}
TelegramClient::sendMessage($Context->ChatId, "{$Greeting}🔒برای استفاده از امکانات ربات باید عضو کانال شوید.\n\n✨پس از عضویت در کانال، نیازی به زدن دکمه بررسی نیست؛ ربات خودش به صورت خودکار دسترسی شما را فعال می کند." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '📢عضویت در کانال', 'url' => $Channel_Url]],
]));
}
}

public static function recheckChannelMembership(Context $Context): void {
if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🔄در حال بررسی عضویت...', false);
}

$Greeting = Common::greet($Context, 'عضویت در کانال');
$Channel_Url = BotConfig::getChannelUrl();
$Status = self::membershipStatus($Context->UserId);
$Is_Member = $Status === 'member';

if (in_array($Status, ['unknown', 'unknown_participant'], true)) {
if (class_exists('ChannelMembership') && method_exists('ChannelMembership', 'markPendingJoin')) {
ChannelMembership::markPendingJoin($Context->UserId, $Context->ChatId);
}
TelegramClient::sendMessage($Context->ChatId, "{$Greeting}⚠️در حال حاضر امکان استعلام خودکار عضویت در کانال وجود ندارد.\n\n✨پس از عضویت در کانال، ربات به صورت خودکار عضویت شما را بررسی و دسترسی را فعال می کند." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '📢عضویت در کانال', 'url' => $Channel_Url]],
]));
return;
}

if ($Is_Member) {
if (class_exists('ChannelMembership') && method_exists('ChannelMembership', 'clearPendingJoin')) {
ChannelMembership::clearPendingJoin($Context->UserId);
}
$Result = ChannelMembership::restore($Context->UserId);
$Notice = match ($Result) {
'restored' => '✅عضویت تأیید و کلاینت دوباره فعال شد.',
'pending' => '⚠️عضویت تأیید شد، اما فعال سازی هنوز موفق نشده؛ بررسی خودکار تکرار می شود.',
'ineligible' => '✅عضویت تأیید شد؛ اشتراک منقضی یا محدودیت دیگری مانع فعال سازی خودکار است. با پشتیبانی تماس بگیرید.',
default => '✅عضویت شما در کانال تأیید گردید.',
};
TelegramClient::sendMessage($Context->ChatId, $Greeting . $Notice . Helper::userFooter(), TelegramClient::inlineKeyboard([Menu::userHome()]));
if (!class_exists('AppBotLink')) {
$AppLinkPath = __DIR__ . '/../Core/App/App-Bot-Link.php';
if (is_file($AppLinkPath)) require_once $AppLinkPath;
}
if (class_exists('AppBotLink') && method_exists('AppBotLink', 'resumePendingIfAny')) {
AppBotLink::resumePendingIfAny($Context);
}
return;
}

if (class_exists('ChannelMembership') && method_exists('ChannelMembership', 'markPendingJoin')) {
ChannelMembership::markPendingJoin($Context->UserId, $Context->ChatId);
}
TelegramClient::sendMessage($Context->ChatId, "{$Greeting}⚠️شما هنوز عضو کانال اطلاع رسانی نیستید.\n\n🔒پس از عضویت در کانال، ربات به صورت خودکار دسترسی شما را فعال می کند." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '📢عضویت در کانال', 'url' => $Channel_Url]],
]));
}

public static function onAutoChannelJoinedById(int $UserId, int $ChatId = 0, string $FullName = ''): void {
if ($UserId <= 0) return;
try {
$User = Repository::getUser($UserId);
if (($User['Registered_At'] ?? null) === null) {
if (method_exists(Repository::class, 'touchUserTime')) {
Repository::touchUserTime($UserId, 'Registered_At');
}
$UUID = trim((string)($User['Client_ID'] ?? ''));
if ($UUID === '' || $UUID === '_') {
$UUID = '';
$Phone = method_exists('Helper', 'normalizePhone')
? Helper::normalizePhone((string)($User['Phone'] ?? ''))
: trim((string)($User['Phone'] ?? ''));
if ($Phone !== '' && class_exists('PanelClient') && method_exists('PanelClient', 'findByPhone')) {
try {
$Account = PanelClient::findByPhone($Phone);
$UUID = trim((string)($Account['uuid'] ?? ''));
if ($UUID !== '' && $UUID !== '_') {
Repository::updateUser($UserId, ['Client_ID' => $UUID]);
}
} catch (Throwable) {}
}
if (($UUID === '' || $UUID === '_') && class_exists('Database')) {
try {
$DevRow = Database::getInstance()->fetch(
'SELECT `User_UUID`, `Phone` FROM `App_Devices` WHERE `Telegram_ID` = ? AND `User_UUID` IS NOT NULL AND `User_UUID` <> \'\' AND `User_UUID` <> \'_\' ORDER BY `Is_Trusted` DESC, `ID` DESC LIMIT 1',
[$UserId]
);
$CandidateUuid = trim((string)($DevRow['User_UUID'] ?? ''));
if ($CandidateUuid !== '' && $CandidateUuid !== '_') {
$UUID = $CandidateUuid;
$Upd = ['Client_ID' => $UUID];
$DevPhone = trim((string)($DevRow['Phone'] ?? ''));
if ($DevPhone !== '' && trim((string)($User['Phone'] ?? '')) === '') {
$Upd['Phone'] = $DevPhone;
}
Repository::updateUser($UserId, $Upd);
}
} catch (Throwable) {}
}
}
if ($UUID !== '' && $UUID !== '_' && class_exists('PanelClient')) {
try {
$Current = PanelClient::get($UUID);
if (is_array($Current) && (int)($Current['telegram_id'] ?? 0) !== $UserId) {
if (method_exists('PanelClient', 'linkTelegramId')) {
PanelClient::linkTelegramId($UUID, $UserId, $Current);
} else {
PanelClient::update($UUID, ['telegram_id' => $UserId]);
}
}
} catch (Throwable) {}
}
$Admin = (int)Repository::getSetting('Administrator', (string)Environment::getAdminUserId());
if ($Admin > 0) {
$Display = trim($FullName) !== '' ? $FullName : (trim((string)($User['Full_Name'] ?? ($User['First_Name'] ?? 'کاربر'))) ?: 'کاربر');
try {
TelegramClient::sendSystemMessage(
$Admin,
Helper::adminGreetingNamed(
(string)(Repository::getSetting('Admin_Full_Name') ?: Environment::getAdminFullName()),
'کاربران جدید',
$Admin
) . "✅لحظاتی پیش کاربر جدیدی عضو ربات گردید.\n\n👤نام: "
. "[" . $Display . "](tg://user?id=" . $UserId . ")\n🆔آیدی عددی: `"
. Helper::toPersian((int)$UserId) . "`"
. Helper::adminFooter()
);
} catch (Throwable) {}
}
}
if (!class_exists('AppBotLink')) {
$AppLinkPath = __DIR__ . '/../Core/App/App-Bot-Link.php';
if (is_file($AppLinkPath)) require_once $AppLinkPath;
}
if (class_exists('AppBotLink') && method_exists('AppBotLink', 'resumePendingById')) {
AppBotLink::resumePendingById($UserId, $ChatId > 0 ? $ChatId : $UserId, $FullName);
}
} catch (Throwable $Error) {
error_log('[Umbrella-Bot][AutoJoin] ' . $Error->getMessage());
}
}

public static function membershipStatus(int $UserId): string {
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
$Has_Pending = class_exists('ChannelMembership') && method_exists('ChannelMembership', 'isPendingJoin')
&& ChannelMembership::isPendingJoin($UserId);

if (!$Has_Client && !$Has_Pending) return true;
$Last_Check = (int)($User['Channel_Member_Check_At'] ?? 0);
$Grace_Started_At = (int)($User['Channel_Grace_Started_At'] ?? 0);
$Is_Disabled = (int)($User['Channel_Client_Disabled_At'] ?? 0) > 0;
$TTL = 1800;
$Should_Call = $Last_Check <= 0 || (time() - $Last_Check) >= $TTL || $Grace_Started_At > 0 || $Is_Disabled || $Has_Pending;

if (!$Should_Call) return true;
$Status = self::membershipStatus($UserId);

if (in_array($Status, ['unknown', 'unknown_participant'], true)) {
Repository::updateUser($UserId, ['Channel_Member_Check_At' => time()]);
return true;
}

if ($Status === 'not_member') {
if ($Has_Client) {
$Grace_Started_At = (int)($User['Channel_Grace_Started_At'] ?? 0);

if ($Grace_Started_At <= 0) {
Repository::updateUser($UserId, ['Channel_Grace_Started_At' => time()]);
}
}

return false;
}

if (class_exists('ChannelMembership') && method_exists('ChannelMembership', 'clearPendingJoin')) {
ChannelMembership::clearPendingJoin($UserId);
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

if ($UUID === '' || $UUID === '_') {
$UUID = '';
$Phone = \Helper::normalizePhone((string)($User['Phone'] ?? ''));

if ($Phone !== '') {
try {
$Account = PanelClient::findByPhone($Phone);
$UUID = trim((string)($Account['uuid'] ?? ''));
} catch (Throwable $Error) {
error_log('[Umbrella-Bot][Panel-Link] lookup failed: ' . $Error->getMessage());
}
}

if (($UUID === '' || $UUID === '_') && class_exists('Database')) {
try {
$DevRow = Database::getInstance()->fetch(
'SELECT `User_UUID`, `Phone` FROM `App_Devices` WHERE `Telegram_ID` = ? AND `User_UUID` IS NOT NULL AND `User_UUID` <> \'\' AND `User_UUID` <> \'_\' ORDER BY `Is_Trusted` DESC, `ID` DESC LIMIT 1',
[$Context->UserId]
);
$Candidate = trim((string)($DevRow['User_UUID'] ?? ''));
if ($Candidate !== '' && $Candidate !== '_') {
$UUID = $Candidate;
$DevPhone = trim((string)($DevRow['Phone'] ?? ''));
if ($DevPhone !== '' && trim((string)($User['Phone'] ?? '')) === '') {
Repository::updateUser($Context->UserId, ['Phone' => $DevPhone]);
}
}
} catch (Throwable) {}
}

if ($UUID === '' || $UUID === '_') return;

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

if (is_array($Current) && (int)($Current['telegram_id'] ?? 0) === $Context->UserId) {
return;
}

try {
if (method_exists('PanelClient', 'linkTelegramId')) {
PanelClient::linkTelegramId($UUID, $Context->UserId, is_array($Current) ? $Current : null);
} else {
PanelClient::update($UUID, ['telegram_id' => $Context->UserId]);
}
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

$User = Repository::getUser($Context->UserId) ?? [];
$Has_Active_Sub = self::hasActiveMenuSubscription($User);
$Shield_Info = self::securityShieldServiceInfo($Context->UserId, $User);
$Text = Common::greet($Context, 'منوی خدمات ربات')
. ($Shield_Info !== null ? ("\n" . $Shield_Info['summary'] . "\n") : '')
. "\n📌*بخش مورد نظر را انتخاب کنید:*" . Helper::userFooter();
$Raw_Rows = [];
if (!$Has_Active_Sub) {
$Raw_Rows[] = [['💎مدیریت اشتراک', 'user_subscriptions_menu']];
}
$Raw_Rows[] = [['👤حساب کاربری', 'user_account_menu']];
if ($Has_Active_Sub) {
$Raw_Rows[] = [['📱دستگاه من', 'user_device_menu']];
}
if ($Shield_Info !== null) {
$Raw_Rows[] = [$Shield_Info['button']];
}
$Raw_Rows = array_merge($Raw_Rows, [
[['💰کیف پول و مالی', 'user_wallet_menu']],
[['📊سوابق و آمار', 'user_stats_menu']],
[['🖥️نرم افزار/اپلیکیشن', 'app_download_menu']],
[['🎫پشتیبانی', 'منوی پشتیبانی']],
[['🔄تغییرات نسخه', 'تغییرات نسخه']],
]);
$Menu_Rows = Menu::rows($Raw_Rows);
$Keyboard = TelegramClient::inlineKeyboard($Menu_Rows);

if ($Context->IsCallback && $Context->MessageId !== null) {
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, $Keyboard);
}

else {
TelegramClient::sendMessage($Context->ChatId, $Text, $Keyboard);
}

$ClientId = trim((string)($User['Client_ID'] ?? ''));
if (($ClientId === '' || $ClientId === '_') && class_exists('AppBotLink', false) && method_exists('AppBotLink', 'remindPendingIfAny')) {
try {
AppBotLink::remindPendingIfAny($Context);
} catch (Throwable) {}
}
}

public static function appDownloadMenu(Context $Context): void {
$Text = Common::greet($Context, 'نرم افزار/اپلیکیشن')
. "📦فایل های نصبی ویندوز و اندروید در انتشار رسمی نسخه قرار می گیرند.\n"
. "برای مشاهده نسخه های هر سیستم عامل و پیوند دانلود، گزینه زیر را انتخاب کنید." . Helper::userFooter();
$Rows = Menu::rows([
[['🪟ویندوز', 'app_download_windows']],
[['🤖اندروید', 'app_download_android']],
]);
$Rows[] = Menu::userHome();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Rows));
}

public static function appDownloadWindows(Context $Context): void {
self::appDownloadPlatform($Context, 'windows');
}

public static function appDownloadAndroid(Context $Context): void {
self::appDownloadPlatform($Context, 'android');
}

public static function appDownloadPlatform(Context $Context, string $Platform): void {
$Platform = strtolower(trim($Platform));
$Platform_Names = ['windows' => 'ویندوز', 'android' => 'اندروید'];
if (!isset($Platform_Names[$Platform])) { self::appDownloadMenu($Context); return; }

$Catalog = ReleaseCatalog::forPlatform($Platform);
$Greeting = Common::greet($Context, 'نرم افزار/اپلیکیشن');
$Text = $Greeting . "📱نسخه های {$Platform_Names[$Platform]} آمبرلا\n"
. "اطلاعات مستقیماً از آخرین انتشار رسمی و بتای منتشرشده خوانده شده است.\n";
$Rows = [];

foreach (['stable' => '✅نسخه رسمی', 'beta' => '🧪نسخه بتا'] as $Channel => $Channel_Label) {
$Release = $Catalog[$Channel] ?? null;
$Text .= "\n➖➖➖➖➖➖➖➖➖\n{$Channel_Label}\n";
if (!is_array($Release)) {
$Text .= "⏳برای این کانال هنوز فایل نصبی برای این سیستم عامل منتشر نشده است.\n";
continue;
}

$Text .= "📦نام: " . (string)$Release['name'] . "\n"
. "🏷نسخه: `" . (string)$Release['tag'] . "`\n"
. "📅زمان انتشار: " . self::releaseDateLabel((string)($Release['published_at'] ?? '')) . "\n"
. "📝توضیحات و آخرین تغییرات:\n";
$Notes = trim((string)($Release['notes'] ?? ''));
$Text .= $Notes !== '' ? mb_substr($Notes, 0, 1800) . "\n" : "توضیحی برای این انتشار ثبت نشده است.\n";

$Assets = self::downloadableReleaseAssets($Release, $Platform);
if ($Assets === []) {
$Text .= "⚠️فایل نصب در این انتشار بارگذاری نشده است.\n";
}
else {
$Text .= "📁فایل های نصب:\n";
foreach ($Assets as $Asset) {
$Size = (int)($Asset['size'] ?? 0);
$Size_Label = $Size > 0 ? ' — ' . Helper::formatBytes($Size) : '';
$Text .= '• ' . (string)$Asset['name'] . $Size_Label . "\n";
$Rows[] = [['text' => self::downloadButtonLabel($Platform, $Channel, (string)$Asset['name']), 'url' => (string)$Asset['url']]];
}
if ($Platform === 'android' && count($Assets) > 1) {
$Text .= "💡برای بیشتر گوشی ها، نسخه universal یا arm64-v8a مناسب است.\n";
}
}

if ((string)($Release['url'] ?? '') !== '') {
$Rows[] = [['text' => '🌐جزئیات کامل انتشار ' . ($Channel === 'beta' ? 'بتا' : 'رسمی'), 'url' => (string)$Release['url']]];
}
}

$Text .= "\nℹ️نسخه بتا آزمایشی است؛ برای استفاده معمول، نسخه رسمی را نصب کنید.";
$Text .= Helper::userFooter();
$Rows[] = Menu::back('انتخاب سیستم عامل', 'app_download_menu');
$Rows[] = Menu::userHome();
$Markup = TelegramClient::inlineKeyboard($Rows);
$Plain_Length = mb_strlen(html_entity_decode(strip_tags(TelegramClient::md($Text)), ENT_QUOTES | ENT_HTML5, 'UTF-8'));
$Message_Id = $Context->MessageId;
if ($Plain_Length > 3000 && $Message_Id !== null) {
TelegramClient::deleteMessage($Context->ChatId, $Message_Id);
$Message_Id = null;
}
TelegramClient::sendReadableMessage($Context->ChatId, $Message_Id, $Text, $Markup);
}

private static function releaseDateLabel(string $Raw): string {
$Timestamp = $Raw !== '' ? strtotime($Raw) : false;
if ($Timestamp === false) return 'نامشخص';
$Date = new DateTimeImmutable('@' . $Timestamp);
$Date = $Date->setTimezone(new DateTimeZone('Asia/Tehran'));
return Helper::gregorianToJalali($Date->format('Y-m-d')) . ' — ' . Helper::formatTime($Date->format('H:i:s'));
}

private static function downloadableReleaseAssets(array $Release, string $Platform): array {
$Extensions = [
'windows' => ['.exe'],
'android' => ['.apk'],
];
$Assets = array_values(array_filter($Release['assets'] ?? [], static function (array $Asset) use ($Extensions, $Platform): bool {
$Name = strtolower((string)($Asset['name'] ?? ''));
$Url = trim((string)($Asset['url'] ?? ''));
if ($Url === '' || !isset($Extensions[$Platform])) return false;
foreach ($Extensions[$Platform] as $Extension) {
if (str_ends_with($Name, $Extension)) return true;
}
return false;
}));

return $Assets;
}

private static function downloadButtonLabel(string $Platform, string $Channel, string $Asset_Name): string {
$Platform_Names = ['windows' => 'ویندوز', 'android' => 'اندروید'];
$Platform_Label = $Platform_Names[$Platform] ?? 'نرم افزار';
$Channel_Label = $Channel === 'beta' ? 'بتا' : 'رسمی';
$Asset_Label = pathinfo($Asset_Name, PATHINFO_FILENAME);
return mb_substr("⬇️دانلود {$Platform_Label} {$Channel_Label} · {$Asset_Label}", 0, 64);
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
private static function subscriptionMenuState(int $UserId, bool $Discover_Missing = false): array {
$User = Repository::getUser($UserId) ?? [];
$Live = null;
$Client = trim((string)($User['Client_ID'] ?? ''));
if ($Client !== '' && $Client !== '_') {
try {
$Response = ServerClient::getUser($Client);
$Code = (int)($Response['StatusCode'] ?? 0);
$Data = $Response['Json'] ?? null;
if ($Code >= 200 && $Code < 300 && is_array($Data)
&& (!isset($Data['uuid']) || (string)$Data['uuid'] === $Client)) {
$Live = $Data;
} elseif ($Code === 404 && method_exists(Common::class, 'syncSubscriptionFromServer')) {
$User = Common::syncSubscriptionFromServer($User);
$New_Client = trim((string)($User['Client_ID'] ?? ''));
if ($New_Client !== '' && $New_Client !== '_' && $New_Client !== $Client) {
$Retry = ServerClient::getUser($New_Client);
if ((int)($Retry['StatusCode'] ?? 0) >= 200 && (int)($Retry['StatusCode'] ?? 0) < 300 && is_array($Retry['Json'] ?? null)) {
$Live = $Retry['Json'];
}
}
}
} catch (Throwable $Error) { error_log('[Umbrella-Bot][Menu-Subscription] ' . $Error->getMessage()); }
} elseif ($Discover_Missing && method_exists(Common::class, 'syncSubscriptionFromServer')) {
$User = Common::syncSubscriptionFromServer($User);
$Found_Client = trim((string)($User['Client_ID'] ?? ''));
if ($Found_Client !== '' && $Found_Client !== '_') {
try {
$Retry = ServerClient::getUser($Found_Client);
if ((int)($Retry['StatusCode'] ?? 0) >= 200 && (int)($Retry['StatusCode'] ?? 0) < 300 && is_array($Retry['Json'] ?? null)) {
$Live = $Retry['Json'];
}
} catch (Throwable) {}
}
}
if ($Live !== null) $User = Common::syncSubscriptionFromServer($User, $Live);
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

// A paused client still owns its plan; an explicitly expired plan can be renewed.
private static function ownsCurrentSubscription(array $User): bool {
$Subscription = trim((string)($User['Subscription'] ?? ''));
$Expires_At = (int)($User['Expiration_Time_Stamp'] ?? 0);
return $Subscription !== '' && ($Expires_At <= 0 || $Expires_At > time());
}

/** کاربرانی که اشتراک فعال دارند، نیازی به منوی خرید و مدیریت اشتراک ندارند. */
public static function hasActiveMenuSubscription(array $User, ?array $Live = null): bool {
if (!self::hasMenuSubscription($User) || !self::ownsCurrentSubscription($User)) {
return false;
}
$Status = trim((string)($User['Client_Status'] ?? ''));
if (in_array($Status, ['غیرفعال', '❌غیرفعال', '🚫غیرفعال', 'منقضی', 'پایان یافته', 'تمام شده'], true)) {
return false;
}
if (isset($User['Server_Enable']) && (int)$User['Server_Enable'] === 0) {
return false;
}
if (isset($User['Server_Is_Active']) && (int)$User['Server_Is_Active'] === 0) {
return false;
}
$Client_ID = trim((string)($User['Client_ID'] ?? ''));
if ($Live !== null && $Live !== []) {
$Live_UUID = trim((string)($Live['uuid'] ?? ''));
if ($Live_UUID !== '' && $Client_ID !== '' && $Live_UUID !== $Client_ID) {
return false;
}
if (array_key_exists('enable', $Live) && (int)$Live['enable'] === 0) {
return false;
}
if (array_key_exists('is_active', $Live) && (int)$Live['is_active'] === 0) {
return false;
}
if (array_key_exists('usage_limit_GB', $Live)) {
$Live_Limit = (float)$Live['usage_limit_GB'];
if ($Live_Limit > 0 && $Live_Limit < 9999 && isset($Live['current_usage_GB']) && (float)$Live['current_usage_GB'] >= $Live_Limit) {
return false;
}
return true;
}
}
$Total_GB = (float)($User['Total_Usage_GB'] ?? 0);
$Used_GB = (float)($User['Used_Usage_GB'] ?? 0);
if ($Total_GB > 0 && $Total_GB < 9999 && $Used_GB >= $Total_GB) {
return false;
}
return true;
}

public static function subscriptionsMenu(Context $Context): void {
if (!Common::isRobotOn()) { self::serviceMenu($Context); return; }
[$User, $Live] = self::subscriptionMenuState($Context->UserId, true);
if (self::hasActiveMenuSubscription($User, $Live)) {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$Text = Common::greet($Context, 'مدیریت اشتراک')
. "✅شما هم اکنون اشتراک فعال دارید و منوی مدیریت اشتراک برای شما غیرفعال است.\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "ℹ️برای مشاهده زمان باقیمانده و حجم مصرف شده، وارد بخش *👤پروفایل کاربری* شوید."
. Helper::userFooter();
$Rows = [
[Menu::button('👤مشاهده پروفایل کاربری', 'پروفایل کاربری')],
Menu::userHome(),
];
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Rows));
return;
}
$Rows = Menu::rows([
[['💎اشتراک های آماده', 'اشتراک آماده'], ['🛠اشتراک دلخواه', 'اشتراک دلخواه']],
]);
if (!self::ownsCurrentSubscription($User)) {
$Client_Uuid = trim((string)($User['Client_ID'] ?? ''));
$Free_Claimed = (int)($User['Free_Plan_Claimed'] ?? 0) === 1
|| ($Client_Uuid !== '' && $Client_Uuid !== '_'
&& trim((string)Repository::getSetting('App_Free_Claimed_' . $Client_Uuid, '')) === '1');
if (!$Free_Claimed) {
$Rows[] = [Menu::button('🎁اشتراک رایگان', 'اشتراک رایگان اول')];
}
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

private static function hasUserProfile(array $User): bool {
$Full_Name = trim((string)($User['Full_Name'] ?? ''));
$Phone = trim((string)($User['Phone'] ?? ''));
return $Full_Name !== '' && $Phone !== '';
}

public static function accountMenu(Context $Context): void {
[$User, $Live] = self::subscriptionMenuState($Context->UserId, true);
$Rows = Menu::rows([
[['👤پروفایل کاربری', 'پروفایل کاربری']],
]);
if (self::hasUserProfile($User)) {
$Rows[] = [Menu::button('✏️ویرایش پروفایل', 'ویرایش پروفایل')];
}
if (self::nightlyMenuVisible($User, $Live)) {
$On = Repository::nightlyReportEnabled($Context->UserId);
$Rows[] = [Menu::button($On ? '🔔گزارش شبانه: روشن — خاموش کردن' : '🔕گزارش شبانه: خاموش — روشن کردن', $On ? 'nightly_report_off' : 'nightly_report_on')];
}
self::categoryMenu($Context, 'حساب کاربری', $Rows);
}

public static function deviceMenu(Context $Context): void {
self::categoryMenu($Context, 'دستگاه من', Menu::rows([
[['🛡کنترل محتوا', 'app_filter']],
[['🌐عبور مستقیم سایت ها', 'app_bypass']],
[['🔐تأیید دومرحله ای', 'app_2fa']],
[['📱دستگاه های من', 'app_devices']],
]));
}

public static function setNightlyReport(Context $Context, bool $Enabled): void {
[$User, $Live] = self::subscriptionMenuState($Context->UserId, true);
if (self::nightlyMenuVisible($User, $Live)) Repository::setNightlyReportEnabled($Context->UserId, $Enabled);
self::accountMenu($Context);
}

public static function statsMenu(Context $Context): void {
$Rows = Menu::rows([
[['📋سابقه اشتراک', 'سابقه اشتراک'], ['📊گزارش مصرف', 'گزارش مصرف']],
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
$User = Repository::getUser($Context->UserId);
$Phone = $User['Phone'] ?? null;
$FullName = $User['Full_Name'] ?? null;

if (!is_string($Phone) || $Phone === '') {
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Greeting . "⛔️بدلیل عدم ثبت پروفایل کاربری مجاز به ورود به این بخش نیستید." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '📝👤ثبت اطلاعات پروفایل کاربری', 'callback_data' => 'ویرایش و ثبت پروفایل']],
Menu::back('منوی قبلی', 'user_account_menu'), Menu::userHome()
]));

return;
}

if (method_exists(Common::class, 'syncSubscriptionFromServer')) {
$User = Common::syncSubscriptionFromServer($User);
}
$Client_ID = trim((string)($User['Client_ID'] ?? ''));
if (($Client_ID === '' || $Client_ID === '_') && method_exists(Common::class, 'liveUser')) {
$User = Common::liveUser($User);
$Client_ID = trim((string)($User['Client_ID'] ?? ''));
}
if (!empty($User['Phone'])) $Phone = (string)$User['Phone'];
if (!empty($User['Full_Name'])) $FullName = (string)$User['Full_Name'];

$Balance = Repository::getBalance($Context->UserId);
$Balance_Formatted = Helper::formatCurrency($Balance);
$Operator = Helper::detectOperator((string)$Phone);
$Profile_Updated_At = (string)($User['Profile_Updated_At'] ?? '');
$Created_At = (string)($User['Created_At'] ?? '');

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

$Sub_Name = trim((string)($User['Subscription'] ?? ''));
$Has_Client_ID = $Client_ID !== '' && $Client_ID !== '_';
$Has_Subscription = $Has_Client_ID || $Sub_Name !== '';

if (!$Has_Subscription) {
$Sub_Text = "\n➖➖➖➖➖➖➖➖➖\n💎*اطلاعات اشتراک:*\n"
. "└─📡وضعیت اشتراک: *❌اشتراک فعالی ندارید*";
} else {
$Used_GB = max(0.0, (float)($User['Used_Usage_GB'] ?? 0));
$Total_GB = max(0.0, (float)($User['Total_Usage_GB'] ?? 0));
$Exp_Stamp = (int)($User['Expiration_Time_Stamp'] ?? 0);
$Raw_Status = trim((string)($User['Client_Status'] ?? ''));

$Is_Unlimited = $Total_GB <= 0.0 || $Total_GB >= 9999.0;
$Remaining_GB = $Is_Unlimited ? 0.0 : max(0.0, $Total_GB - $Used_GB);
$Is_Exhausted = !$Is_Unlimited && $Total_GB > 0.0 && $Used_GB >= $Total_GB;
$Is_Expired = $Exp_Stamp > 0 && $Exp_Stamp <= time();
$Is_Inactive = in_array($Raw_Status, ['غیرفعال', '❌غیرفعال', '🚫غیرفعال'], true)
|| (isset($User['Server_Enable']) && (int)$User['Server_Enable'] === 0)
|| (isset($User['Server_Is_Active']) && (int)$User['Server_Is_Active'] === 0);

if ($Is_Expired) {
$Sub_Status_Label = '⏰منقضی شده';
} elseif ($Is_Exhausted) {
$Sub_Status_Label = '⚠️اتمام حجم';
} elseif ($Is_Inactive) {
$Sub_Status_Label = '🚫غیرفعال';
} else {
$Sub_Status_Label = '🟢فعال';
}

$Fmt_GB = static fn(float $Gb): string => method_exists(Helper::class, 'formatGB')
? Helper::formatGB($Gb)
: Helper::toPersian((string)round($Gb, 2)) . ' گیگابایت';
$Remaining_Time = method_exists(Helper::class, 'remainingDuration')
? Helper::remainingDuration($Exp_Stamp)
: ($Exp_Stamp > 0 ? Helper::toPersian((string)$Exp_Stamp) : 'نامشخص');
$Exp_Date_Label = $Exp_Stamp > 0 ? Helper::formatExpirationShort($Exp_Stamp) : 'نامشخص';

$Used_Label = $Fmt_GB($Used_GB);
$Total_Label = $Is_Unlimited ? 'نامحدود' : $Fmt_GB($Total_GB);
$Remaining_GB_Label = $Is_Unlimited ? 'نامحدود' : $Fmt_GB($Remaining_GB);
$Sub_Title = $Sub_Name !== '' ? $Sub_Name : 'فعال';

$Sub_Text = "\n➖➖➖➖➖➖➖➖➖\n💎*اطلاعات اشتراک:*\n"
. "├─🪪نوع اشتراک: *{$Sub_Title}*\n"
. "├─📡وضعیت اشتراک: *{$Sub_Status_Label}*\n"
. "├─⏳زمان باقیمانده: *{$Remaining_Time}*\n"
. "├─📅تاریخ انقضا: *{$Exp_Date_Label}*\n"
. "├─📦حجم کل: *{$Total_Label}*\n"
. "├─📥حجم مصرف شده: *{$Used_Label}*\n";

if (!$Is_Unlimited && $Total_GB > 0.0) {
$Percent = min(100.0, max(0.0, round(($Used_GB / $Total_GB) * 100.0, 1)));
$Percent_Str = method_exists(Helper::class, 'formatPercent')
? Helper::formatPercent($Percent)
: Helper::toPersian((string)$Percent);
$Bar = method_exists(Helper::class, 'usageBar')
? Helper::usageBar($Percent, 12)
: '';
$Sub_Text .= "├─📤حجم باقیمانده: *{$Remaining_GB_Label}*\n"
. "└─📊درصد مصرف: *{$Percent_Str}٪*" . ($Bar !== '' ? "\n`{$Bar}`" : '');
} else {
$Sub_Text .= "└─📤حجم باقیمانده: *{$Remaining_GB_Label}*";
}
}

$PhoneDisplay = method_exists('Helper', 'formatPhoneDisplay')
? Helper::formatPhoneDisplay((string)$Phone)
: Helper::toPersian((string)$Phone);
$Profile_Text = "👤نام و نام خانوادگی: *" . Helper::mention((string)$FullName, $Context->UserId) . "*\n"
. "📞شماره موبایل: {$PhoneDisplay} (*اپراتور پایه: {$Operator}*)\n"
. "💳اعتبار حساب: *{$Balance_Formatted}*\n"
. "🆔شناسه تلگرام: `" . Helper::toPersian((string)$Context->UserId) . "`\n"
. "📅تاریخ عضویت: *{$Created_At_Label}*\n"
. "🕰آخرین بروزرسانی پروفایل: *{$Profile_Updated_Label}*"
. $Sub_Text;

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

$Text .= "📄صفحه " . Helper::toPersian((string)$Page) . " از " . Helper::toPersian((string)$Total_Pages) . Helper::userFooter();
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

$Text .= "📄صفحه " . Helper::toPersian((string)$Page) . " از " . Helper::toPersian((string)$Total_Pages) . Helper::userFooter();
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
if (count($Saved) >= 10) {
TelegramClient::sendMessage($Context->ChatId, Helper::userGreeting($Context, 'تیکت جدید') . '⚠️حداکثر ۱۰ پیوست برای ایجاد تیکت؛ موارد بیشتر را پس از ثبت در پاسخ تیکت بفرستید.' . Helper::userFooter());
return;
}
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

$User = Repository::getUser($Context->UserId);
if (method_exists(Common::class, 'syncSubscriptionFromServer')) {
$User = Common::syncSubscriptionFromServer($User);
}
$Client_ID = trim((string)($User['Client_ID'] ?? ''));
if (($Client_ID === '' || $Client_ID === '_') && method_exists(Common::class, 'liveUser')) {
$User = Common::liveUser($User);
$Client_ID = trim((string)($User['Client_ID'] ?? ''));
}

if ($Client_ID === '' || $Client_ID === '_') {
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, Common::greet($Context, 'گزارش مصرف') . "❌شما اشتراک فعالی ندارید.\n➖➖➖➖➖➖➖➖➖\n⚠️از بخش مدیریت اشتراک برای خرید اشتراک اقدام کنید." . Helper::userFooter(), TelegramClient::inlineKeyboard([
Menu::back('منوی قبلی', 'user_stats_menu'), Menu::userHome(),
]));
return;
}

$Used_GB = (float)($User['Used_Usage_GB'] ?? 0);
$Total_GB = (float)($User['Total_Usage_GB'] ?? 0);
$Remaining = max(0, $Total_GB - $Used_GB);
$Percent = $Total_GB > 0 ? round(($Used_GB / $Total_GB) * 100, 1) : 0;
$Last_Online = (string)($User['Last_Online'] ?? '');
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

$Today_Gain = Repository::userUsageGain($Context->UserId);
$History = Repository::userUsageHistory($Context->UserId, 7);
$History_Days = count($History);
$Daily_Avg = $History_Days > 0 ? array_sum($History) / $History_Days : null;
$Exp_Stamp = (int)($User['Expiration_Time_Stamp'] ?? 0);
$Subscription = trim((string)($User['Subscription'] ?? '')) ?: 'نامشخص';
$Text = Common::greet($Context, 'گزارش مصرف') . "📊<b>گزارش پیشرفته مصرف</b>\n➖➖➖➖➖➖➖➖➖\n";

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

/**
 * فهرست دستگاه های نصب شده و متصل کاربر در نرم افزار ویندوز یا اپلیکیشن اندروید.
 * در تست های فاقد دیتابیس یا کاربرانی که هنوز اپ را نصب نکرده اند، آرایه خالی برمی گرداند.
 *
 * @return list<array<string, mixed>>
 */
public static function installedAppDevices(int $UserId, ?array $User = null): array {
if ($UserId <= 0 || !class_exists('Database') || !method_exists('Database', 'getInstance')) {
return [];
}
try {
$Db = Database::getInstance();
if (!is_object($Db) || !method_exists($Db, 'fetchAll')) {
return [];
}
$User ??= (Repository::getUser($UserId) ?? []);
$Uuid = trim((string)($User['Client_ID'] ?? ''));
if ($Uuid === '_') $Uuid = '';
$Raw_Phone = (string)($User['Phone'] ?? '');
$Phone = method_exists('Helper', 'normalizePhone')
? Helper::normalizePhone($Raw_Phone)
: trim($Raw_Phone);

$Where = ['`Telegram_ID` = ?'];
$Params = [$UserId];
if ($Uuid !== '') {
$Where[] = '`User_UUID` = ?';
$Params[] = $Uuid;
}
$Rows = $Db->fetchAll(
'SELECT `ID`, `Device_ID`, `Device_Name`, `Platform`, `App_Version`, `User_UUID`, `Telegram_ID`, `Phone`, `Last_Seen_At`, `Is_Trusted`
FROM `App_Devices`
WHERE (' . implode(' OR ', $Where) . ')
ORDER BY `Is_Trusted` DESC, `Last_Seen_At` DESC, `ID` DESC',
$Params
);
if ((!is_array($Rows) || $Rows === []) && $Phone !== '') {
$Rows = $Db->fetchAll(
'SELECT `ID`, `Device_ID`, `Device_Name`, `Platform`, `App_Version`, `User_UUID`, `Telegram_ID`, `Phone`, `Last_Seen_At`, `Is_Trusted`
FROM `App_Devices`
WHERE `Phone` = ? AND (`Telegram_ID` IS NULL OR `Telegram_ID` = 0 OR `Telegram_ID` = ?)
ORDER BY `Is_Trusted` DESC, `Last_Seen_At` DESC, `ID` DESC',
[$Phone, $UserId]
);
}
if (!is_array($Rows) || $Rows === []) {
return [];
}
$Out = [];
$Seen = [];
foreach ($Rows as $Row) {
if (!is_array($Row)) continue;
$Device_Id = trim((string)($Row['Device_ID'] ?? ''));
if ($Device_Id === '' || isset($Seen[$Device_Id])) continue;
$Row_Tg = (int)($Row['Telegram_ID'] ?? 0);
$Row_Uuid = trim((string)($Row['User_UUID'] ?? ''));
$Row_Phone = method_exists('Helper', 'normalizePhone')
? Helper::normalizePhone((string)($Row['Phone'] ?? ''))
: trim((string)($Row['Phone'] ?? ''));
$Owned = ($Row_Tg > 0 && $Row_Tg === $UserId)
|| ($Uuid !== '' && $Row_Uuid !== '' && $Row_Uuid === $Uuid)
|| ($Row_Tg <= 0 && $Phone !== '' && $Row_Phone === $Phone);
if (!$Owned) continue;
$Platform = trim((string)($Row['Platform'] ?? ''));
if ($Platform === '' && trim((string)($Row['Device_Name'] ?? '')) === '') continue;
$Seen[$Device_Id] = true;
$Out[] = $Row;
}
return $Out;
} catch (Throwable) {
return [];
}
}

/** @return ?array{button: array{0: string, 1: string}, summary: string, active_count: int, cleaned_count: int, device_count: int} */
private static function securityShieldServiceInfo(int $UserId, array $User): ?array {
$Devices = self::installedAppDevices($UserId, $User);
if ($Devices === []) return null;

$Device_Ids = array_values(array_filter(array_map(
static fn(array $D): string => trim((string)($D['Device_ID'] ?? '')),
$Devices
)));
$Active = 0;
$Cleaned = 0;
try {
$Db = Database::getInstance();
if ($Device_Ids !== [] && method_exists($Db, 'fetchAll')) {
$Marks = implode(',', array_fill(0, count($Device_Ids), '?'));
$Counts = $Db->fetchAll(
"SELECT `Resolved`, COUNT(*) AS `Cnt` FROM `App_Security_Alerts` WHERE `Device_ID` IN ({$Marks}) GROUP BY `Resolved`",
$Device_Ids
);
if (is_array($Counts)) {
foreach ($Counts as $Row) {
$Count = (int)($Row['Cnt'] ?? 0);
if ((int)($Row['Resolved'] ?? 0) === 0) {
$Active += $Count;
} else {
$Cleaned += $Count;
}
}
}
}
} catch (Throwable) {}

$Dev_Fa = Helper::toPersian((string)count($Devices));
$Act_Fa = Helper::toPersian((string)$Active);
$Clean_Fa = Helper::toPersian((string)$Cleaned);
if ($Active > 0) {
$Button = ["⚠️سپر امنیتی ({$Act_Fa} هشدار)", 'user_security_shield'];
$Summary = "🛡 <b>وضعیت سپر امنیتی:</b> ⚠️ {$Act_Fa} تهدید نیازمند بررسی روی {$Dev_Fa} دستگاه";
} else {
$Button = ['🛡سپر امنیتی دستگاه (🟢ایمن)', 'user_security_shield'];
$Summary = $Cleaned > 0
? "🛡 <b>وضعیت سپر امنیتی:</b> 🟢 ایمن ({$Dev_Fa} دستگاه تحت حفاظت · {$Clean_Fa} مورد پاکسازی شده)"
: "🛡 <b>وضعیت سپر امنیتی:</b> 🟢 ایمن و فعال در پس زمینه ({$Dev_Fa} دستگاه تحت حفاظت)";
}
return [
'button' => $Button,
'summary' => $Summary,
'active_count' => $Active,
'cleaned_count' => $Cleaned,
'device_count' => count($Devices),
];
}

private static function securityStateForDevice(string $Device_Id): array {
if ($Device_Id === '' || !method_exists(Repository::class, 'getSetting')) return [];
try {
$Raw = trim((string)Repository::getSetting('App_Security_State_' . sha1($Device_Id), ''));
if ($Raw === '') return [];
$Decoded = json_decode($Raw, true);
return is_array($Decoded) ? $Decoded : [];
} catch (Throwable) {
return [];
}
}

private static function formatSecurityTimeLabel(mixed $Raw_Ts): string {
if (is_int($Raw_Ts) || (is_string($Raw_Ts) && ctype_digit($Raw_Ts))) {
$Ts = (int)$Raw_Ts;
if ($Ts > 1000000000000) $Ts = intdiv($Ts, 1000);
if ($Ts > 0) {
if (method_exists('Helper', 'formatPersianDate')) {
return (string)Helper::formatPersianDate($Ts, true);
}
return Helper::toPersian(gmdate('Y-m-d H:i', $Ts));
}
}
$Text = trim((string)$Raw_Ts);
if ($Text !== '') {
return method_exists('Helper', 'formatDateTimeText')
? (string)Helper::formatDateTimeText($Text)
: Helper::toPersian($Text);
}
return 'ثبت نشده';
}

private static function securityCategoryFa(string $Category): string {
return match (strtolower(trim($Category))) {
'conflicting_vpn' => 'فیلترشکن ناسازگار',
'adware' => 'تبلیغ افزار مزاحم',
'suspicious' => 'فایل یا فعالیت مشکوک',
'malicious_download' => 'فایل یا مدیای مخرب',
'malicious_link' => 'لینک تروجانی / فیشینگ',
default => 'ویروس / بدافزار / تروجان',
};
}

/** نمایش صفحه وضعیت سپر امنیتی و گزارش مرتب موارد شناسایی و حذف شده کاربر. */
public static function securityShieldMenu(Context $Context, int $Page = 0): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
TelegramClient::sendChatAction($Context->ChatId);

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🛡در حال دریافت گزارش سپر امنیتی...', false);
}

$Esc = static fn(string $Value): string => htmlspecialchars(
str_replace(['*', '`', '[', ']'], ['＊', '｀', '［', '］'], $Value),
ENT_QUOTES | ENT_SUBSTITUTE,
'UTF-8'
);

$User = Repository::getUser($Context->UserId) ?? [];
$Devices = self::installedAppDevices($Context->UserId, $User);
$Greeting = Common::greet($Context, 'سپر امنیتی دستگاه');

if ($Devices === []) {
$EmptyText = $Greeting
. "🛡 <b>سپر امنیتی آمبرلا</b>\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "ℹ️ هنوز نرم افزار ویندوز یا اپلیکیشن اندرویدی به حساب شما متصل نشده است.\n"
. "پس از نصب و ورود در برنامه آمبرلا، وضعیت سپر امنیتی دستگاه ها و گزارش پاکسازی بدافزارها به صورت خودکار اینجا نمایش داده می شود."
. Helper::userFooter();
TelegramClient::editOrSendMessage(
$Context->ChatId,
$Context->MessageId,
$EmptyText,
TelegramClient::inlineKeyboard([
[['text' => '🖥️دانلود نرم افزار / اپلیکیشن', 'callback_data' => 'app_download_menu']],
Menu::userHome(),
])
);
return;
}

$Device_By_Id = [];
foreach ($Devices as $Dev) {
$Id = trim((string)($Dev['Device_ID'] ?? ''));
if ($Id !== '') $Device_By_Id[$Id] = $Dev;
}
$Device_Ids = array_keys($Device_By_Id);

$All_Alerts = [];
try {
$Db = Database::getInstance();
if ($Device_Ids !== [] && method_exists($Db, 'fetchAll')) {
$Marks = implode(',', array_fill(0, count($Device_Ids), '?'));
$Rows = $Db->fetchAll(
"SELECT `ID`, `Device_ID`, `Threat_Key`, `Threat_Name`, `Category`, `Severity`, `Target`, `First_Detected_At`, `Last_Detected_At`, `Hit_Count`, `Resolved`
FROM `App_Security_Alerts`
WHERE `Device_ID` IN ({$Marks})
ORDER BY `Resolved` ASC, `Last_Detected_At` DESC, `ID` DESC",
$Device_Ids
);
if (is_array($Rows)) $All_Alerts = $Rows;
}
} catch (Throwable) {}

$Active_Alerts = [];
$Resolved_Alerts = [];
$Active_By_Dev = [];
$Cleaned_By_Dev = [];
foreach ($All_Alerts as $Alert) {
if (!is_array($Alert)) continue;
$Dev_Id = trim((string)($Alert['Device_ID'] ?? ''));
if ($Dev_Id === '' || !isset($Device_By_Id[$Dev_Id])) continue;
if ((int)($Alert['Resolved'] ?? 0) === 0) {
$Active_Alerts[] = $Alert;
$Active_By_Dev[$Dev_Id] = ($Active_By_Dev[$Dev_Id] ?? 0) + 1;
} else {
$Resolved_Alerts[] = $Alert;
$Cleaned_By_Dev[$Dev_Id] = ($Cleaned_By_Dev[$Dev_Id] ?? 0) + 1;
}
}

$Total_Active = count($Active_Alerts);
$Total_Cleaned = count($Resolved_Alerts);

$Lines = [
$Greeting . '🛡 <b>وضعیت سپر امنیتی دستگاه ها</b>',
'➖➖➖➖➖➖➖➖➖',
'🚦 <b>وضعیت کلی:</b> ' . ($Total_Active > 0
? ('⚠️ دارای <b>' . Helper::toPersian((string)$Total_Active) . '</b> مورد نیازمند بررسی')
: '🟢 <b>دستگاه ها ایمن هستند</b> (پایش پیوسته پس زمینه فعال)'),
'🧹 <b>کل موارد خنثی و حذف شده:</b> ' . Helper::toPersian((string)$Total_Cleaned) . ' مورد',
'',
'💻 <b>دستگاه های تحت حفاظت:</b>',
];

foreach ($Devices as $Idx => $Dev) {
$Dev_Id = trim((string)($Dev['Device_ID'] ?? ''));
$Plat_Raw = (string)($Dev['Platform'] ?? '');
$Plat_Label = method_exists('Helper', 'formatPlatform') ? Helper::formatPlatform($Plat_Raw) : ($Plat_Raw !== '' ? $Plat_Raw : 'دستگاه');
$Plat_Icon = str_contains(strtolower($Plat_Raw), 'android') ? '📱' : '💻';
$Name = trim((string)($Dev['Device_Name'] ?? '')) ?: 'دستگاه آمبرلا';
$Ver = trim((string)($Dev['App_Version'] ?? ''));
$Dev_Active = (int)($Active_By_Dev[$Dev_Id] ?? 0);
$Dev_Cleaned = (int)($Cleaned_By_Dev[$Dev_Id] ?? 0);
$State = self::securityStateForDevice($Dev_Id);
$Badge = $Dev_Active > 0
? ('⚠️ ' . Helper::toPersian((string)$Dev_Active) . ' هشدار فعال')
: '🟢 ایمن';

$Lines[] = Helper::toPersian((string)($Idx + 1)) . ') ' . $Plat_Icon . ' <b>' . $Esc($Name) . '</b> (' . $Esc($Plat_Label) . ($Ver !== '' ? ' · نسخه ' . $Esc(Helper::toPersian($Ver)) : '') . ')';
$Lines[] = '   ├─ وضعیت سپر: <b>' . $Badge . '</b> | پاکسازی شده: <b>' . Helper::toPersian((string)$Dev_Cleaned) . '</b>';

$Scan_Ts = $State['scanned_at_ms'] ?? ($Dev['Last_Seen_At'] ?? '');
$Scan_Label = self::formatSecurityTimeLabel($Scan_Ts);
$Scanned_Files = (int)($State['scanned_files'] ?? 0);
$Scanned_Apps = (int)($State['scanned_apps'] ?? 0);
$Scanned_Procs = (int)($State['scanned_processes'] ?? 0);
if ($Scanned_Files > 0 || $Scanned_Apps > 0 || $Scanned_Procs > 0) {
$Stat_Parts = [];
if ($Scanned_Procs > 0) $Stat_Parts[] = Helper::toPersian((string)$Scanned_Procs) . ' پردازش';
if ($Scanned_Apps > 0) $Stat_Parts[] = Helper::toPersian((string)$Scanned_Apps) . ' برنامه';
if ($Scanned_Files > 0) $Stat_Parts[] = Helper::toPersian((string)$Scanned_Files) . ' فایل/مدیا';
$Lines[] = '   ├─ آخرین پایش: ' . $Esc($Scan_Label);
$Lines[] = '   └─ محدوده اسکن شده: ' . implode(' · ', $Stat_Parts);
} else {
$Lines[] = '   └─ آخرین پایش: ' . $Esc($Scan_Label);
}
}

if ($Active_Alerts !== []) {
$Lines[] = '';
$Lines[] = '🚨 <b>تهدیدات فعال نیازمند اقدام:</b>';
foreach (array_slice($Active_Alerts, 0, 5) as $Item) {
$Dev_Name = trim((string)($Device_By_Id[(string)$Item['Device_ID']]['Device_Name'] ?? 'دستگاه'));
$Cat_Fa = self::securityCategoryFa((string)($Item['Category'] ?? 'malware'));
$Target = trim((string)($Item['Target'] ?? ''));
$Lines[] = '• ⚠️ <b>' . $Esc((string)($Item['Threat_Name'] ?? 'تهدید امنیتی')) . '</b>';
$Lines[] = '  ├─ دسته: ' . $Cat_Fa . ' | دستگاه: ' . $Esc($Dev_Name);
$Lines[] = '  ├─ زمان: ' . $Esc(self::formatSecurityTimeLabel($Item['Last_Detected_At'] ?? 0));
if ($Target !== '') {
$Lines[] = '  └─ مسیر: <code>' . $Esc(mb_substr($Target, 0, 110)) . '</code>';
}
}
if (count($Active_Alerts) > 5) {
$Lines[] = '… و ' . Helper::toPersian((string)(count($Active_Alerts) - 5)) . ' مورد فعال دیگر در لیست برنامه.';
}
}

$Lines[] = '';
$Per_Page = 5;
$Page_Count = max(1, (int)ceil($Total_Cleaned / $Per_Page));
$Page = max(0, min($Page, $Page_Count - 1));
$Slice = array_slice($Resolved_Alerts, $Page * $Per_Page, $Per_Page);

$Lines[] = '📋 <b>گزارش موارد شناسایی، مسدود و حذف شده سپر امنیتی:</b>';
if ($Page_Count > 1) {
$Lines[] = '📄 صفحه ' . Helper::toPersian((string)($Page + 1)) . ' از ' . Helper::toPersian((string)$Page_Count);
}

if ($Slice === []) {
$Lines[] = '✅ تاکنون هیچ فایل ویروسی، تروجان، بدافزار یا لینک مخربی روی دستگاه های شما یافت نشده است؛ سپر امنیتی آمبرلا به صورت پیوسته در پس زمینه فعال است.';
} else {
$Offset = $Page * $Per_Page;
foreach ($Slice as $Pos => $Item) {
$Num = Helper::toPersian((string)($Offset + $Pos + 1));
$Cat = strtolower(trim((string)($Item['Category'] ?? 'malware')));
$Cat_Fa = self::securityCategoryFa($Cat);
$Action_Label = match ($Cat) {
'malicious_link' => '🚫 مسدودسازی لینک/اتصال مخرب',
'malicious_download' => '🗑 حذف خودکار فایل/مدیای آلوده',
default => '✅ شناسایی و برطرف سازی تهدید',
};
$Dev_Name = trim((string)($Device_By_Id[(string)$Item['Device_ID']]['Device_Name'] ?? 'دستگاه'));
$Target = trim((string)($Item['Target'] ?? ''));
$Hits = max(1, (int)($Item['Hit_Count'] ?? 1));
$When = self::formatSecurityTimeLabel($Item['Last_Detected_At'] ?? 0);

$Lines[] = $Num . ') <b>' . $Action_Label . '</b>';
$Lines[] = '   ├─ عنوان: ' . $Esc((string)($Item['Threat_Name'] ?? 'تهدید'));
$Lines[] = '   ├─ دسته: ' . $Cat_Fa . ' | دستگاه: ' . $Esc($Dev_Name);
$Lines[] = '   ├─ زمان: ' . $Esc($When) . ' (تعداد رصد: ' . Helper::toPersian((string)$Hits) . ')';
if ($Target !== '') {
$Lines[] = '   └─ مسیر/نشانی: <code>' . $Esc(mb_substr($Target, 0, 120)) . '</code>';
} else {
$Lines[] = '   └─ وضعیت: برطرف شده و ایمن';
}
}
}

$Lines[] = '';
$Lines[] = 'ℹ️ پایش پس زمینه در ویندوز و اندروید به صورت خودکار فعال است و هر فایل یا مدیای دریافتی را پیش از باز شدن بررسی می کند.';

$Text = implode("\n", $Lines) . Helper::userFooter();
$Rows = [];
if ($Page_Count > 1) {
$Rows = array_merge($Rows, Menu::pages($Page, $Page_Count, 'user_security_shield:'));
}
$Rows[] = [['text' => '🔄بروزرسانی وضعیت و گزارش', 'callback_data' => 'user_security_shield:' . $Page]];
$Rows[] = Menu::userHome();

TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Rows));
}


}
?>