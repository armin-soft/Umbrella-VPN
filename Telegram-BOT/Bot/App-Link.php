<?php
declare(strict_types=1);

require_once __DIR__ . '/Context.php';
require_once __DIR__ . '/Common.php';
require_once __DIR__ . '/../Core/App/App-Filter.php';
require_once __DIR__ . '/../Core/App/App-Two-Step.php';
require_once __DIR__ . '/../Core/Database/Database.php';
require_once __DIR__ . '/../Core/Server/Umbrella-Panel.php';
require_once __DIR__ . '/../Core/Storage/Repository.php';
require_once __DIR__ . '/../Core/Telegram/Telegram.php';
require_once dirname(__DIR__) . '/Config/Environment.php';

/**
 * Everything the bot shows for the desktop app: the account panel, the content
 * filter menu, and the device list with the confirmation buttons.
 *
 * The confirmation itself is handled by AppGateway::decide(), because the
 * challenge lives in the app's tables; this class only renders and replies.
 */
final class AppFlow {
private function __construct() {
}

/** /app — the hub: profile, filter, devices, notifications. */
public static function menu(Context $Context): void {
$Account = self::account($Context);

if ($Account === null) {
$Text = \Helper::userGreeting($Context, 'فیلترشکن آمبرلا')
. \Helper::noticeBlock(
'📱 اتصال برنامه به تلگرام',
'برای دیدن اطلاعات حساب و تنظیمات فیلتر، ابتدا در برنامه با همین شماره وارد شوید و ربات را باز کنید.',
'ℹ️ بعد از ورود اول، همه‌چیز به‌صورت خودکار اینجا نمایش داده می‌شود.'
) . \Helper::userFooter();
self::reply($Context, $Text, TelegramClient::inlineKeyboard([
[['text' => '🏠 منوی اصلی', 'callback_data' => 'منوی خدمات ربات']],
]));
return;
}

$Filter = AppFilter::load((string)$Account['uuid']);
$Summary = AppFilter::summary($Filter);
$Name = trim((string)($Account['name'] ?? '')) ?: 'کاربر آمبرلا';
$Usage = \Helper::formatGB((float)($Account['current_usage_GB'] ?? 0));
$Limit = \Helper::formatGB((float)($Account['usage_limit_GB'] ?? 0));
$Active = (bool)($Account['is_active'] ?? false);

$Text = \Helper::userGreeting($Context, 'حساب آمبرلا')
. "👤 نام: {$Name}\n"
. '📞 شماره: ' . \Helper::toPersian((string)($Account['phone'] ?? '')) . "\n"
. '📊 مصرف: ' . $Usage . ' از ' . $Limit . "\n"
. '🔋 وضعیت: ' . ($Active ? 'فعال ✅' : 'غیرفعال ⛔️') . "\n"
. "➖➖➖➖➖➖➖➖➖➖\n"
. $Summary
. \Helper::userFooter();

self::reply($Context, $Text, TelegramClient::inlineKeyboard([
[['text' => '🛡 کنترل محتوا', 'callback_data' => 'app_filter']],
[['text' => '📱 دستگاه‌های من', 'callback_data' => 'app_devices']],
[['text' => '🔔 اعلان‌های برنامه', 'callback_data' => 'app_notifications']],
[['text' => '🔐 تأیید دومرحله‌ای ورود', 'callback_data' => 'app_2fa']],
[['text' => '🏠 منوی اصلی', 'callback_data' => 'منوی خدمات ربات']],
]));
}

/** The filter menu: one button per category, toggling on press. */
public static function filterMenu(Context $Context): void {
$Account = self::accountOrPrompt($Context);

if ($Account === null) return;

$Settings = AppFilter::load((string)$Account['uuid']);
$Rows = [];
$Row = [];

foreach (AppFilter::CATEGORIES as $Key => $Label) {
$On = in_array($Key, $Settings['categories'], true);
$Row[] = ['text' => ($On ? '✅ ' : '⚪️ ') . $Label, 'callback_data' => 'app_filter_toggle:' . $Key];

if (count($Row) === 2) {
$Rows[] = $Row;
$Row = [];
}
}

if ($Row !== []) $Rows[] = $Row;

$Rows[] = [['text' => $Settings['enabled'] ? '🔴 خاموش کردن کنترل محتوا' : '🟢 روشن کردن کنترل محتوا', 'callback_data' => 'app_filter_toggle:enabled']];
$Rows[] = [['text' => '🔗 افزودن دامنه دلخواه', 'callback_data' => 'app_filter_domains']];
$Rows[] = [['text' => '🏠 بازگشت', 'callback_data' => 'app_menu']];

$Text = \Helper::userGreeting($Context, 'کنترل محتوا')
. AppFilter::summary($Settings)
. "\n➖➖➖➖➖➖➖➖➖➖\n"
. 'ℹ️ با زدن هر دسته، وضعیت آن تغییر می‌کند و در برنامه هم اعمال می‌شود.'
. \Helper::userFooter();

self::reply($Context, $Text, TelegramClient::inlineKeyboard($Rows));
}

/** Toggles a category (or the master switch) and re-renders the menu. */
public static function filterToggle(Context $Context, string $Category): void {
$Account = self::accountOrPrompt($Context);

if ($Account === null) return;

$UUID = (string)$Account['uuid'];

if ($Category === 'enabled') {
$Current = AppFilter::load($UUID);
AppFilter::save($UUID, [
'enabled' => empty($Current['enabled']),
'categories' => $Current['categories'],
'custom_domains' => implode("\n", $Current['custom_domains']),
], 'bot');
}

else {
AppFilter::toggle($UUID, $Category, 'bot');
}

if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, 'ذخیره شد ✅');
}

self::filterMenu($Context);
}

/** Asks for a domain list, handled by AppFlow::filterDomainsInput(). */
public static function filterDomainsStart(Context $Context): void {
$Account = self::accountOrPrompt($Context);

if ($Account === null) return;

Repository::updateUserSession($Context->UserId, ['Flow' => 'app:filter_domains']);
$Current = AppFilter::load((string)$Account['uuid']);
$Existing = implode('\n', $Current['custom_domains']);

self::reply(
$Context,
\Helper::userGreeting($Context, 'دامنه‌های دلخواه')
. AppFilter::summary($Current)
. "\n➖➖➖➖➖➖➖➖➖➖\n"
. ($Existing !== '' ? "📄 فهرست فعلی:\n<code>{$Existing}</code>\n➖➖➖➖➖➖➖➖➖➖\n" : '')
. 'لینک یا دامنه‌ها را بفرستید؛ هر خط یک مورد. برای پاک کردن، «-» بفرستید.'
. \Helper::userFooter(),
TelegramClient::inlineKeyboard([[['text' => 'لغو', 'callback_data' => 'app_filter']]])
);
}

public static function filterDomainsInput(Context $Context, string $Text): void {
$Account = self::accountOrPrompt($Context);

if ($Account === null) return;

$Text = trim($Text);
$Domains = $Text === '-' ? [] : preg_split('/[\s,;]+/', $Text);
$Current = AppFilter::load((string)$Account['uuid']);

AppFilter::save((string)$Account['uuid'], [
'enabled' => true,
'categories' => $Current['categories'],
'custom_domains' => implode('\n', is_array($Domains) ? $Domains : []),
], 'bot');

Repository::updateUserSession($Context->UserId, ['Flow' => null]);
self::filterMenu($Context);
}

/** The devices that ever signed in, with trust state. */
public static function devices(Context $Context): void {
$Account = self::accountOrPrompt($Context);

if ($Account === null) return;

$Rows = \Database::getInstance()->fetchAll(
'SELECT * FROM `App_Devices` WHERE `User_UUID` = ? OR `Telegram_ID` = ? ORDER BY `Last_Seen_At` DESC LIMIT 10',
[(string)$Account['uuid'], $Context->UserId]
);

if ($Rows === []) {
self::reply(
$Context,
\Helper::userGreeting($Context, 'دستگاه‌های من')
. 'هنوز دستگاهی ثبت نشده است.' . \Helper::userFooter(),
TelegramClient::inlineKeyboard([[['text' => '🏠 بازگشت', 'callback_data' => 'app_menu']]])
);
return;
}

$Text = \Helper::userGreeting($Context, 'دستگاه‌های من');

foreach ($Rows as $Index => $Row) {
$Trusted = (int)($Row['Is_Trusted'] ?? 0) === 1;
$Seen = (int)($Row['Last_Seen_At'] ?? 0);
$Text .= (\Helper::toPersian((string)($Index + 1))) . ') '
. '📱 ' . (string)($Row['Device_Name'] ?? 'دستگاه')
. "\n   🖥 " . (string)($Row['Platform'] ?? '')
. "\n   🌐 " . (string)($Row['Last_IP'] ?? '')
. "\n   🕐 " . ($Seen > 0 ? \Helper::formatPersianDate($Seen, true) : '—')
. "\n   " . ($Trusted ? '✅ تأییدشده' : '⚪️ تأییدنشده')
. "\n➖➖➖➖➖➖➖➖➖➖\n";
}

$Text .= 'ℹ️ برای لغو اعتماد یک دستگاه، دکمه آن را بزنید.' . \Helper::userFooter();
$Buttons = [];

foreach (array_slice($Rows, 0, 6) as $Row) {
$Id = (string)$Row['Device_ID'];
$Buttons[] = [[
'text' => '⛔️ لغو اعتماد ' . mb_substr((string)($Row['Device_Name'] ?? $Id), 0, 20),
'callback_data' => 'app_device_revoke:' . substr($Id, 0, 24),
]];
}

$Buttons[] = [['text' => '🏠 بازگشت', 'callback_data' => 'app_menu']];

self::reply($Context, $Text, TelegramClient::inlineKeyboard($Buttons));
}

public static function revokeDevice(Context $Context, string $Device_Prefix): void {
$Account = self::accountOrPrompt($Context);

if ($Account === null) return;

$Prefix = preg_replace('/[^A-Za-z0-9_-]/', '', $Device_Prefix) ?? '';

if ($Prefix !== '') {
\Database::getInstance()->execute(
'UPDATE `App_Devices` SET `Is_Trusted` = 0 WHERE `Device_ID` LIKE ? AND (`User_UUID` = ? OR `Telegram_ID` = ?)',
[$Prefix . '%', (string)$Account['uuid'], $Context->UserId]
);
}

if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, 'اعتماد دستگاه لغو شد');
}

self::devices($Context);
}

/** The messages the app has been sent, newest first. */
public static function notifications(Context $Context): void {
$Rows = \Database::getInstance()->fetchAll(
'SELECT `Title`, `Body`, `Level`, `Sent_At` FROM `App_Notifications`
WHERE `Device_ID` IN (SELECT `Device_ID` FROM `App_Devices` WHERE `Telegram_ID` = ?)
ORDER BY `ID` DESC LIMIT 10',
[$Context->UserId]
);

$Text = \Helper::userGreeting($Context, 'اعلان‌های برنامه');

if ($Rows === []) {
$Text .= 'اعلانی برای برنامه شما ثبت نشده است.';
}

foreach ($Rows as $Row) {
$Icon = match((string)$Row['Level']) { 'warning' => '⚠️', 'error' => '⛔️', 'success' => '✅', default => '🔔' };
$Text .= "{$Icon} " . (string)$Row['Title'] . "\n" . (string)($Row['Body'] ?? '') . "\n🕐 " . (string)$Row['Sent_At'] . "\n➖➖➖➖➖➖➖➖➖➖\n";
}

self::reply($Context, $Text . \Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '🏠 بازگشت', 'callback_data' => 'app_menu']],
]));
}

/** The switch that decides whether a sign-in also needs a tap here. */
public static function twoStepMenu(Context $Context): void {
if (self::accountOrPrompt($Context) === null) {
return;
}

self::renderTwoStep($Context);
}

public static function setTwoStep(Context $Context, bool $Enabled): void {
$Changed = AppTwoStep::enabled($Context->UserId) !== $Enabled;

if ($Changed) {
AppTwoStep::set($Context->UserId, $Enabled);
}

if ($Context->IsCallback && $Context->CallbackId !== null) {
$Message = $Changed
? ($Enabled ? '✅تأیید دومرحله‌ای روشن شد.' : '⛔️تأیید دومرحله‌ای خاموش شد.')
: 'وضعیت تغییری نکرد.';
TelegramClient::answerCallbackQuery($Context->CallbackId, $Message, false);
}

self::renderTwoStep($Context);
}

private static function renderTwoStep(Context $Context): void {
$On = AppTwoStep::enabled($Context->UserId);
$Text = \Helper::userGreeting($Context, 'تأیید دومرحله‌ای ورود')
. "🔐 *تأیید دومرحله‌ای ورود به برنامه*\n"
. 'وضعیت: ' . ($On ? '🟢 فعال' : '🔴 غیرفعال') . "\n"
. "➖➖➖➖➖➖➖➖➖➖\n"
. "🟢 فعال: بعد از کد پیامکی، جزئیات دستگاه (نام، سیستم‌عامل، آی‌پی و زمان) همین‌جا به تلگرام شما می‌آید و ورود فقط با زدن «✅خودم بودم» کامل می‌شود.\n\n"
. "🔴 غیرفعال: فقط کد پیامکی کافی است و دستگاه بلافاصله تأیید می‌شود؛ بعد از هر ورود، نتیجه به تلگرام شما اطلاع داده می‌شود.\n\n"
. ($On
? 'ℹ️ پیشنهاد می‌شود این گزینه روشن بماند.'
: '⚠️ با خاموش بودن این گزینه، هر کسی که کد پیامکی را ببیند می‌تواند وارد حساب شود.')
. \Helper::userFooter();

$Rows = $On
? [[['text' => '⛔️ غیرفعال کردن تأیید دومرحله‌ای', 'callback_data' => 'app_2fa_off']]]
: [[['text' => '✅ فعال کردن تأیید دومرحله‌ای', 'callback_data' => 'app_2fa_on']]];
$Rows[] = [['text' => '📱 دستگاه‌های من', 'callback_data' => 'app_devices']];
$Rows[] = [['text' => '🔔 اعلان‌های برنامه', 'callback_data' => 'app_notifications']];
$Rows[] = [['text' => '🏠 بازگشت', 'callback_data' => 'app_menu']];
self::reply($Context, $Text, TelegramClient::inlineKeyboard($Rows));
}

/** Finds the panel account of the person chatting, if there is one. */
public static function account(Context $Context): ?array {
$User = Repository::getUser($Context->UserId);
$Phone = \Helper::normalizePhone((string)($User['Phone'] ?? ''));

if ($Phone !== '') {
$Found = \PanelClient::findByPhone($Phone);

if ($Found !== null) return $Found;
}

return \PanelClient::findByTelegramId($Context->UserId);
}

private static function accountOrPrompt(Context $Context): ?array {
$Account = self::account($Context);

if ($Account === null) {
self::reply(
$Context,
\Helper::userGreeting($Context, 'حساب آمبرلا')
. \Helper::noticeBlock(
'📱 حسابی پیدا نشد',
'برای دیدن این بخش، شماره موبایل شما باید در برنامه یا پنل ثبت شده باشد.'
) . \Helper::userFooter(),
TelegramClient::inlineKeyboard([[['text' => '🏠 منوی اصلی', 'callback_data' => 'منوی خدمات ربات']]])
);
}

return $Account;
}

/** Renders into the message a callback came from, or sends a new one. */
private static function reply(Context $Context, string $Text, array $Markup): void {
if ($Context->IsCallback && $Context->MessageId !== null) {
try {
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Text, $Markup);
return;
}

catch (Throwable) {
}
}

TelegramClient::sendMessage($Context->ChatId, $Text, $Markup);
}
}
?>
