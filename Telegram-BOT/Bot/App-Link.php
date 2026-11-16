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
self::reply($Context, $Text, TelegramClient::inlineKeyboard([Menu::back('منوی قبلی', 'user_account_menu'), Menu::userHome()]));
return;
}

$Filter = AppFilter::load((string)$Account['uuid']);
$Summary = AppFilter::summary($Filter);
$Name = trim((string)($Account['name'] ?? '')) ?: 'کاربر آمبرلا';
$Usage = \Helper::formatGB((float)($Account['current_usage_GB'] ?? 0));
$Limit = \Helper::formatGB((float)($Account['usage_limit_GB'] ?? 0));
$Active = (bool)($Account['is_active'] ?? false);

$Text = \Helper::userGreeting($Context, 'حساب آمبرلا')
. Menu::section('👤', 'حساب کاربری', [
'🧑نام: ' . $Name,
'📞شماره: ' . \Helper::toPersian((string)($Account['phone'] ?? '')),
'📊مصرف: ' . $Usage . ' از ' . $Limit,
'🚦وضعیت: ' . ($Active ? 'فعال ✅' : 'غیرفعال ⛔️'),
])
. $Summary
. \Helper::userFooter();
self::reply($Context, $Text, TelegramClient::inlineKeyboard([Menu::back('منوی قبلی', 'user_account_menu'), Menu::userHome()]));
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

$Rows[] = [['text' => $Settings['enabled'] ? '🔴خاموش کردن کنترل محتوا' : '🟢روشن کردن کنترل محتوا', 'callback_data' => 'app_filter_toggle:enabled']];
$Rows[] = Menu::back('منوی قبلی', 'user_account_menu');
$Rows[] = Menu::userHome();

$Text = \Helper::userGreeting($Context, 'کنترل محتوا')
. AppFilter::summary($Settings)
. "\n➖➖➖➖➖➖➖➖➖\n"
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
. "\n➖➖➖➖➖➖➖➖➖\n"
. ($Existing !== '' ? "📄فهرست فعلی:\n<code>{$Existing}</code>\n" : '')
. "📥لینک یا دامنه ها را بفرستید؛ هر خط یک مورد.\n🧹برای پاک کردن همه، فقط «-» بفرستید."
. \Helper::userFooter(),
TelegramClient::inlineKeyboard([
Menu::back('منوی قبلی', 'user_account_menu'), Menu::userHome(),
])
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
self::reply($Context, \Helper::userGreeting($Context, 'دامنه‌های دلخواه')
. '✅دامنه‌های دلخواه ذخیره شدند.'
. AppFilter::summary(AppFilter::load((string)$Account['uuid']))
. \Helper::userFooter(), TelegramClient::inlineKeyboard([Menu::back('منوی قبلی', 'user_account_menu'), Menu::userHome()]));
}

/** The devices that ever signed in, with trust state and paging. */
public static function devices(Context $Context, int $Page = 0): void {
$Account = self::accountOrPrompt($Context, 'user_security_menu');

if ($Account === null) return;

$Database = \Database::getInstance();
$Parameters = [(string)$Account['uuid'], $Context->UserId];
$Total = (int)$Database->scalar(
'SELECT COUNT(*) FROM `App_Devices` WHERE `User_UUID` = ? OR `Telegram_ID` = ?',
$Parameters,
0
);

if ($Total <= 0) {
self::reply(
$Context,
\Helper::userGreeting($Context, 'دستگاه‌های من')
. '📱هنوز دستگاهی ثبت نشده است.' . \Helper::userFooter(),
TelegramClient::inlineKeyboard([Menu::back('منوی قبلی', 'user_security_menu'), Menu::userHome()])
);
return;
}

$PageSize = 5;
$PageCount = max(1, (int)ceil($Total / $PageSize));
$Page = max(0, min($Page, $PageCount - 1));
$Offset = $Page * $PageSize;
$Rows = $Database->fetchAll(
'SELECT * FROM `App_Devices`
WHERE `User_UUID` = ? OR `Telegram_ID` = ?
ORDER BY `Last_Seen_At` DESC LIMIT ? OFFSET ?',
[...$Parameters, $PageSize, $Offset]
);

$Text = \Helper::userGreeting($Context, 'دستگاه‌های من');
if ($PageCount > 1) {
$Text .= '📄صفحه ' . \Helper::toPersian((string)($Page + 1))
. ' از ' . \Helper::toPersian((string)$PageCount) . "\n➖➖➖➖➖➖➖➖➖\n";
}

foreach ($Rows as $Index => $Row) {
$Trusted = (int)($Row['Is_Trusted'] ?? 0) === 1;
$Text .= (\Helper::toPersian((string)($Offset + $Index + 1))) . ') '
. '📱 ' . (string)($Row['Device_Name'] ?? 'دستگاه')
. "\n   🖥 " . (string)($Row['Platform'] ?? '')
. "\n   🌐 " . (string)($Row['Last_IP'] ?? '')
. "\n   " . ($Trusted ? '✅ تأییدشده' : '⚪️ تأییدنشده')
. "\n➖➖➖➖➖➖➖➖➖\n";
}

$Text .= 'ℹ️ برای لغو اعتماد یک دستگاه، دکمه آن را بزنید.' . \Helper::userFooter();
$Buttons = [];

foreach ($Rows as $Row) {
$Id = (string)$Row['Device_ID'];
$Buttons[] = [[
'text' => '⛔️ لغو اعتماد ' . mb_substr((string)($Row['Device_Name'] ?? $Id), 0, 20),
'callback_data' => 'app_device_revoke:' . substr($Id, 0, 24) . ':' . $Page,
]];
}

if ($PageCount > 1) {
$Navigation = [];
if ($Page > 0) {
$Navigation[] = ['text' => '⬅️ قبلی', 'callback_data' => 'app_devices_page:' . ($Page - 1)];
}
if ($Page + 1 < $PageCount) {
$Navigation[] = ['text' => 'بعدی ➡️', 'callback_data' => 'app_devices_page:' . ($Page + 1)];
}
$Buttons[] = $Navigation;
}

$Buttons[] = Menu::back('منوی قبلی', 'user_security_menu');
$Buttons[] = Menu::userHome();

self::reply($Context, $Text, TelegramClient::inlineKeyboard($Buttons));
}

public static function revokeDevice(Context $Context, string $Device_Prefix, int $Page = 0): void {
$Account = self::accountOrPrompt($Context);

if ($Account === null) return;

$Prefix = preg_replace('/[^A-Za-z0-9_-]/', '', $Device_Prefix) ?? '';

if ($Prefix === '') {
if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, 'شناسه دستگاه معتبر نیست', true);
}
return;
}

if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, 'برای لغو دسترسی، تأیید نهایی لازم است.');
}

self::reply(
$Context,
\Helper::userGreeting($Context, 'تأیید لغو دستگاه')
. "⚠️آیا مطمئن هستید دسترسی این دستگاه را لغو کنید؟\n"
. "با تأیید، برنامه از حساب خارج می‌شود و برای استفاده دوباره باید مجدداً وارد شوید."
. \Helper::userFooter(),
TelegramClient::inlineKeyboard([[
['text' => '⛔️ بله، لغو دسترسی', 'callback_data' => 'app_device_revoke_confirm:' . $Prefix . ':' . $Page],
['text' => 'انصراف', 'callback_data' => 'app_devices_page:' . $Page],
], Menu::userHome()])
);
}

/** Executes a device revocation only after the explicit confirmation step. */
public static function confirmRevokeDevice(Context $Context, string $Device_Prefix, int $Page = 0): void {
$Account = self::accountOrPrompt($Context);

if ($Account === null) return;

$Prefix = preg_replace('/[^A-Za-z0-9_-]/', '', $Device_Prefix) ?? '';

if ($Prefix === '') {
if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, 'شناسه دستگاه معتبر نیست', true);
}
return;
}

$Database = \Database::getInstance();
$Devices = $Database->fetchAll(
'SELECT `Device_ID`, `User_UUID` FROM `App_Devices`
WHERE `Device_ID` LIKE ? AND `Is_Trusted` = 1 AND (`User_UUID` = ? OR `Telegram_ID` = ?)',
[$Prefix . '%', (string)$Account['uuid'], $Context->UserId]
);

if ($Devices === []) {
if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, 'دستگاه مجاز پیدا نشد یا قبلاً لغو شده است', true);
}
self::devices($Context, $Page);
return;
}

$Title = 'مجوز این دستگاه لغو شد';
$Body = 'به درخواست شما از تلگرام، دسترسی این دستگاه به نرم افزار آمبرلا لغو شد. از حساب خارج می شوید؛ برای استفاده دوباره باید با شماره موبایل و تایید تلگرام وارد شوید.';

// اعلان و لغو نشست در یک تراکنش انجام می شوند؛ کلاینت در ضربان بعدی
// پیام device_revoked را دریافت می کند، اعلان را نشان می دهد و سپس خارج می شود.
$Database->transaction(static function (\Database $Database) use ($Devices, $Title, $Body): void {
foreach ($Devices as $Device) {
$Device_Id = (string)$Device['Device_ID'];
$User_UUID = (string)($Device['User_UUID'] ?? '');
$Database->execute(
'INSERT INTO `App_Notifications` (`User_UUID`, `Device_ID`, `Title`, `Body`, `Level`)
VALUES (?, ?, ?, ?, ?)',
[$User_UUID !== '' ? $User_UUID : null, $Device_Id, $Title, $Body, 'warning']
);
$Database->execute(
'UPDATE `App_Devices` SET `Is_Trusted` = 0 WHERE `Device_ID` = ? AND `Is_Trusted` = 1',
[$Device_Id]
);
$Database->execute(
'UPDATE `App_Sessions` SET `Revoked_At` = CURRENT_TIMESTAMP
WHERE `Device_ID` = ? AND `Revoked_At` IS NULL',
[$Device_Id]
);
}
});

if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, 'مجوز لغو شد؛ برنامه از حساب خارج خواهد شد.');
}

self::devices($Context, $Page);
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
$Text .= '🔔اعلانی برای برنامه شما ثبت نشده است.';
}

foreach ($Rows as $Row) {
$Icon = match((string)$Row['Level']) { 'warning' => '⚠️', 'error' => '⛔️', 'success' => '✅', default => '🔔' };
$Text .= "{$Icon} " . (string)$Row['Title'] . "\n" . (string)($Row['Body'] ?? '') . "\n🕐 " . (string)$Row['Sent_At'] . "\n➖➖➖➖➖➖➖➖➖\n";
}

self::reply($Context, $Text . \Helper::userFooter(), TelegramClient::inlineKeyboard([Menu::back('منوی قبلی', 'user_account_menu'), Menu::userHome()]));
}

/** The switch that decides whether a sign-in also needs a tap here. */
public static function twoStepMenu(Context $Context): void {
if (self::accountOrPrompt($Context, 'user_security_menu') === null) {
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
: 'ℹ️وضعیت تغییری نکرد.';
TelegramClient::answerCallbackQuery($Context->CallbackId, $Message, false);
}

self::renderTwoStep($Context);
}

private static function renderTwoStep(Context $Context): void {
$On = AppTwoStep::enabled($Context->UserId);
$Text = \Helper::userGreeting($Context, 'تأیید دومرحله‌ای ورود')
. "🔐 *تأیید دومرحله‌ای ورود به برنامه*\n"
. '🚦وضعیت: ' . ($On ? '🟢فعال' : '🔴غیرفعال') . "\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "🟢 فعال: بعد از کد پیامکی، جزئیات دستگاه (نام، سیستم‌عامل، آی‌پی و زمان) همین‌جا به تلگرام شما می‌آید و ورود فقط با زدن «✅خودم بودم» کامل می‌شود.\n\n"
. "🔴 غیرفعال: فقط کد پیامکی کافی است و دستگاه بلافاصله تأیید می‌شود؛ بعد از هر ورود، نتیجه به تلگرام شما اطلاع داده می‌شود.\n\n"
. ($On
? 'ℹ️ پیشنهاد می‌شود این گزینه روشن بماند.'
: '⚠️ با خاموش بودن این گزینه، هر کسی که کد پیامکی را ببیند می‌تواند وارد حساب شود.')
. \Helper::userFooter();

$Rows = $On
? [[['text' => '⛔️غیرفعال کردن تأیید دومرحله‌ای', 'callback_data' => 'app_2fa_off']]]
: [[['text' => '✅فعال کردن تأیید دومرحله‌ای', 'callback_data' => 'app_2fa_on']]];
$Rows[] = Menu::back('منوی قبلی', 'user_security_menu');
$Rows[] = Menu::userHome();
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

private static function accountOrPrompt(Context $Context, string $Parent = 'user_account_menu'): ?array {
$Account = self::account($Context);

if ($Account === null) {
self::reply(
$Context,
\Helper::userGreeting($Context, 'حساب آمبرلا')
. \Helper::noticeBlock(
'📱 حسابی پیدا نشد',
'برای دیدن این بخش، شماره موبایل شما باید در برنامه یا پنل ثبت شده باشد.'
) . \Helper::userFooter(),
TelegramClient::inlineKeyboard(Menu::userNav('منوی قبلی', $Parent))
);
}

return $Account;
}

/** Renders into the message a callback came from, or sends a new one. */
private static function reply(Context $Context, string $Text, array $Markup = []): void {
if ($Context->IsCallback && $Context->MessageId !== null) {
try {
// Telegram keeps an old inline keyboard when `reply_markup` is omitted;
// explicitly clear it when rendering a destination with no buttons.
$EditMarkup = $Markup === [] ? ['inline_keyboard' => []] : $Markup;
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Text, $EditMarkup);
return;
}

catch (Throwable) {
}
}

TelegramClient::sendMessage($Context->ChatId, $Text, $Markup);
}
}
?>
