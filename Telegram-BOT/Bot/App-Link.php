<?php
declare(strict_types=1);

require_once __DIR__ . '/Context.php';
require_once __DIR__ . '/../Core/App/System-Notifications.php';
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
self::reply($Context, $Text, TelegramClient::inlineKeyboard([Menu::back('منوی قبلی', 'user_device_menu'), Menu::userHome()]));
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
self::reply($Context, $Text, TelegramClient::inlineKeyboard([Menu::back('منوی قبلی', 'user_device_menu'), Menu::userHome()]));
}

/** The filter menu: categories, custom-domain manager, and master switch. */
public static function filterMenu(Context $Context): void {
$Account = self::accountOrPrompt($Context);

if ($Account === null) return;

self::clearFilterDomainFlow($Context);

$Settings = AppFilter::load((string)$Account['uuid']);
$Rows = [];
$Row = [];

foreach (AppFilter::BOT_CATEGORIES as $Key => $Label) {
$On = in_array($Key, $Settings['categories'], true);
$Row[] = ['text' => ($On ? '✅ ' : '⚪️ ') . $Label, 'callback_data' => 'app_filter_toggle:' . $Key];

if (count($Row) === 2) {
$Rows[] = $Row;
$Row = [];
}
}

if ($Row !== []) $Rows[] = $Row;

$Domain_Count = count($Settings['custom_domains']);
$Domain_Button = $Domain_Count > 0
? '🌐 دامنه‌های سفارشی (' . $Domain_Count . ')'
: '🌐 دامنه‌های سفارشی';
$Rows[] = [['text' => $Domain_Button, 'callback_data' => 'app_filter_domains']];

$Has_Rules = $Settings['categories'] !== [] || $Domain_Count > 0;
$Active = !empty($Settings['enabled']) && $Has_Rules;
$Rows[] = [[
'text' => $Active ? '🔴خاموش کردن کنترل محتوا' : '🟢روشن کردن کنترل محتوا',
'callback_data' => 'app_filter_toggle:enabled',
]];
$Rows[] = Menu::back('منوی قبلی', 'user_device_menu');
$Rows[] = Menu::userHome();

$Text = \Helper::userGreeting($Context, 'کنترل محتوا')
. AppFilter::summary($Settings)
. "\n➖➖➖➖➖➖➖➖➖\n"
. "ℹ️ با زدن هر دسته یا مدیریت دامنه‌های سفارشی، قوانین بلافاصله ذخیره شده و روی اتصال برنامه اعمال می‌شوند."
. \Helper::userFooter();

self::reply($Context, $Text, TelegramClient::inlineKeyboard($Rows));
}

/** Toggles a category (or the master switch) and re-renders the menu. */
public static function filterToggle(Context $Context, string $Category): void {
$Account = self::accountOrPrompt($Context);

if ($Account === null) return;

$UUID = (string)$Account['uuid'];
if ($Category !== 'enabled' && !isset(AppFilter::BOT_CATEGORIES[$Category])) {
self::filterMenu($Context);
return;
}

if ($Category === 'enabled') {
$Current = AppFilter::load($UUID);
$Has_Rules = $Current['categories'] !== [] || $Current['custom_domains'] !== [];
$Want_Enable = empty($Current['enabled']) || !$Has_Rules;

if ($Want_Enable && !$Has_Rules) {
if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery(
$Context->CallbackId,
'ابتدا یک دسته را انتخاب کنید یا دامنه سفارشی اضافه کنید.',
true
);
}
self::filterMenu($Context);
return;
}

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

/** صفحه مدیریت دامنه‌های سفارشی (نمایش صفحه‌بندی‌شده، افزودن، حذف تکی و حذف همه). */
public static function filterDomainsMenu(Context $Context, int $Page = 0, string $Notice = ''): void {
$Account = self::accountOrPrompt($Context, 'app_filter');

if ($Account === null) return;

self::clearFilterDomainFlow($Context);

$Settings = AppFilter::load((string)$Account['uuid']);
$Domains = array_values($Settings['custom_domains']);
$Total = count($Domains);
$Per_Page = AppFilter::DOMAINS_PER_PAGE;
$Page_Count = max(1, (int)ceil($Total / $Per_Page));
$Page = max(0, min($Page, $Page_Count - 1));
$Slice = array_slice($Domains, $Page * $Per_Page, $Per_Page);

$Text = \Helper::userGreeting($Context, 'دامنه‌های سفارشی کنترل محتوا')
. Menu::pageLabel($Page, $Page_Count);

if ($Notice !== '') {
$Text .= $Notice . "\n➖➖➖➖➖➖➖➖➖\n";
}

$Status_Line = !empty($Settings['enabled']) ? '🟢فعال روی اتصال' : '⚪️ذخیره‌شده (کنترل محتوا خاموش)';
$Text .= "🚦وضعیت: {$Status_Line}\n"
. "🔢تعداد ثبت‌شده: {$Total} از " . AppFilter::MAX_CUSTOM_DOMAINS . " دامنه\n"
. "➖➖➖➖➖➖➖➖➖\n";

if ($Slice === []) {
$Text .= "📭هنوز دامنه سفارشی ثبت نشده است.\n"
. "با زدن «➕ افزودن دامنه»، هر سایت دلخواه را همراه با تمام زیردامنه‌هایش مسدود کنید.\n";
} else {
$Start_Index = $Page * $Per_Page;
foreach ($Slice as $Offset => $Domain) {
$Safe_Domain = self::safeDomainLabel($Domain);
$Text .= ($Start_Index + $Offset + 1) . ". {$Safe_Domain}\n";
}
$Text .= "\nℹ️ برای حذف هر دامنه، دکمه 🗑 همان دامنه را بزنید.\n";
}

$Text .= \Helper::userFooter();

$Rows = [];
$Rows[] = [['text' => '➕ افزودن دامنه جدید', 'callback_data' => 'app_fdom_add']];

foreach ($Slice as $Domain) {
$Token = AppFilter::domainToken($Domain);
$Label = strlen($Domain) > 34 ? substr($Domain, 0, 31) . '...' : $Domain;
$Rows[] = [[
'text' => '🗑 حذف ' . $Label,
'callback_data' => 'app_fdom_del:' . $Token . ':' . $Page,
]];
}

if ($Page_Count > 1) {
$Rows = array_merge($Rows, Menu::pages($Page, $Page_Count, 'app_fdom_page:'));
}

if ($Total > 0) {
$Rows[] = [['text' => '🧹 حذف همه دامنه‌ها', 'callback_data' => 'app_fdom_clear']];
}

$Rows[] = Menu::back('منوی قبلی', 'app_filter');
$Rows[] = Menu::userHome();

self::reply($Context, $Text, TelegramClient::inlineKeyboard($Rows));
}

/** آغاز دریافت دامنه سفارشی جدید (تکی یا چندتایی) از کاربر در ربات. */
public static function filterDomainsStart(Context $Context): void {
$Account = self::accountOrPrompt($Context, 'app_filter');

if ($Account === null) return;

$Settings = AppFilter::load((string)$Account['uuid']);
if (count($Settings['custom_domains']) >= AppFilter::MAX_CUSTOM_DOMAINS) {
if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery(
$Context->CallbackId,
'ظرفیت دامنه‌های سفارشی پر شده است؛ ابتدا چند مورد را حذف کنید.',
true
);
}
self::filterDomainsMenu($Context);
return;
}

Repository::updateUserSession($Context->UserId, ['Flow' => 'app:filter_domains', 'Step' => 1]);

if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, 'دامنه مورد نظر را ارسال کنید');
}

$Text = \Helper::userGreeting($Context, 'افزودن دامنه سفارشی')
. "🌐 دامنه یا نشانی سایتی که می‌خواهید در اتصال مسدود شود را ارسال کنید:\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "• نمونه تکی: example.com\n"
. "• نمونه چندتایی: هر دامنه در یک خط یا جداشده با ویرگول\n"
. "• برای حذف سریع با متن، پیش از دامنه علامت - بگذارید (مانند -example.com)\n"
. "• هر دامنه همراه با تمام زیردامنه‌های آن مسدود و با برنامه ویندوز همگام می‌شود."
. \Helper::userFooter();

self::reply(
$Context,
$Text,
TelegramClient::inlineKeyboard([
Menu::back('انصراف و بازگشت', 'app_filter_domains'),
Menu::userHome(),
])
);
}

/** پردازش متن ارسالی کاربر برای افزودن یا حذف دامنه سفارشی. */
public static function filterDomainsInput(Context $Context, string $Text): void {
$Account = self::accountOrPrompt($Context, 'app_filter');

if ($Account === null) {
self::clearFilterDomainFlow($Context);
return;
}

$Trimmed = trim($Text);
if ($Trimmed === 'انصراف' || $Trimmed === 'بازگشت' || $Trimmed === '/cancel') {
self::filterDomainsMenu($Context);
return;
}

$Parsed = AppFilter::parseDomainsInput($Trimmed);
if ($Parsed['add'] === [] && $Parsed['remove'] === []) {
$Hint = \Helper::userGreeting($Context, 'دامنه نامعتبر')
. "⚠️ هیچ دامنه معتبری در پیام شما شناسایی نشد.\n"
. "لطفاً نام دامنه را به صورت استاندارد ارسال کنید (مانند example.com یا site.org)."
. \Helper::userFooter();
TelegramClient::sendMessage(
$Context->ChatId,
$Hint,
TelegramClient::inlineKeyboard([
Menu::back('انصراف و بازگشت', 'app_filter_domains'),
Menu::userHome(),
])
);
return;
}

$Result = AppFilter::applyDomainChanges(
(string)$Account['uuid'],
$Parsed['add'],
$Parsed['remove'],
'bot'
);
self::clearFilterDomainFlow($Context);

$Lines = [];
if ($Result['added'] !== []) {
$Lines[] = '✅ ' . count($Result['added']) . ' دامنه اضافه شد: '
. implode('، ', array_map([self::class, 'safeDomainLabel'], array_slice($Result['added'], 0, 5)))
. (count($Result['added']) > 5 ? ' و ...' : '');
}
if ($Result['removed'] !== []) {
$Lines[] = '🗑 ' . count($Result['removed']) . ' دامنه حذف شد: '
. implode('، ', array_map([self::class, 'safeDomainLabel'], array_slice($Result['removed'], 0, 5)))
. (count($Result['removed']) > 5 ? ' و ...' : '');
}
if ($Result['duplicates'] !== []) {
$Lines[] = 'ℹ️ ' . count($Result['duplicates']) . ' مورد از قبل در فهرست وجود داشت.';
}
if ($Result['skipped_limit'] !== []) {
$Lines[] = '⚠️ ' . count($Result['skipped_limit']) . ' مورد به دلیل پر شدن سقف ' . AppFilter::MAX_CUSTOM_DOMAINS . ' دامنه ثبت نشد.';
}
if ($Parsed['invalid'] !== []) {
$Lines[] = '⚠️ ' . count($Parsed['invalid']) . ' مورد نامعتبر نادیده گرفته شد.';
}
if ($Lines === []) {
$Lines[] = 'ℹ️ تغییری در فهرست دامنه‌ها ایجاد نشد (دامنه مورد نظر در فهرست نبود).';
}

self::filterDomainsMenu($Context, 0, implode("\n", $Lines));
}

/** حذف تکی یک دامنه سفارشی از روی دکمه اینلاین. */
public static function filterDomainDelete(Context $Context, string $Token, int $Page = 0): void {
$Account = self::accountOrPrompt($Context, 'app_filter');

if ($Account === null) return;

$Clean_Token = preg_replace('/[^a-f0-9]/', '', strtolower($Token)) ?? '';
$Result = $Clean_Token !== ''
? AppFilter::removeDomainByToken((string)$Account['uuid'], $Clean_Token, 'bot')
: ['removed' => null, 'settings' => AppFilter::load((string)$Account['uuid'])];

$Removed = $Result['removed'];
if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery(
$Context->CallbackId,
$Removed !== null ? "دامنه {$Removed} حذف شد ✅" : 'این دامنه قبلاً حذف شده بود.',
false
);
}

self::filterDomainsMenu($Context, max(0, $Page));
}

/** پرسش تأیید پیش از حذف یک‌جای همه دامنه‌های سفارشی. */
public static function filterDomainsClearAsk(Context $Context): void {
$Account = self::accountOrPrompt($Context, 'app_filter');

if ($Account === null) return;

$Settings = AppFilter::load((string)$Account['uuid']);
$Count = count($Settings['custom_domains']);
if ($Count === 0) {
self::filterDomainsMenu($Context);
return;
}

if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, 'تأیید حذف همه دامنه‌ها');
}

$Text = \Helper::userGreeting($Context, 'تأیید حذف همه دامنه‌ها')
. "⚠️ آیا مطمئن هستید تمام {$Count} دامنه سفارشی حذف شوند؟\n"
. "این تغییر بلافاصله با برنامه ویندوز همگام می‌شود."
. \Helper::userFooter();

self::reply(
$Context,
$Text,
TelegramClient::inlineKeyboard([
[
['text' => '🧹 بله، همه حذف شوند', 'callback_data' => 'app_fdom_clear_ok'],
['text' => 'انصراف', 'callback_data' => 'app_filter_domains'],
],
Menu::userHome(),
])
);
}

/** اجرای حذف کامل همه دامنه‌های سفارشی پس از تأیید کاربر. */
public static function filterDomainsClearConfirm(Context $Context): void {
$Account = self::accountOrPrompt($Context, 'app_filter');

if ($Account === null) return;

AppFilter::clearDomains((string)$Account['uuid'], 'bot');
if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, 'تمام دامنه‌های سفارشی حذف شدند ✅');
}
self::filterDomainsMenu($Context, 0, '🧹 تمام دامنه‌های سفارشی حذف شدند.');
}

private static function clearFilterDomainFlow(Context $Context): void {
$User = Repository::getUser($Context->UserId);
if (is_array($User) && (string)($User['Flow'] ?? '') === 'app:filter_domains') {
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Step' => 0]);
}
}

private static function safeDomainLabel(string $Domain): string {
return str_replace(['*', '_', '`', '[', ']'], ['＊', '＿', '｀', '［', '］'], $Domain);
}

/** The devices that ever signed in, with trust state and paging. */
public static function devices(Context $Context, int $Page = 0): void {
$Account = self::accountOrPrompt($Context, 'user_device_menu');

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
TelegramClient::inlineKeyboard([Menu::back('منوی قبلی', 'user_device_menu'), Menu::userHome()])
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
'text' => ((int)($Row['Is_Trusted'] ?? 0) === 1 ? '⛔️ لغو اعتماد ' : '⚪️ اعتماد لغو شده · ') . mb_substr((string)($Row['Device_Name'] ?? $Id), 0, 20),
'callback_data' => (int)($Row['Is_Trusted'] ?? 0) === 1 ? 'app_device_revoke:' . substr($Id, 0, 24) . ':' . $Page : 'app_device_status:' . substr($Id, 0, 24) . ':' . $Page,
]];
}

if ($PageCount > 1) {
$Navigation = [];
if ($Page > 0) {
$Navigation[] = ['text' => '⬅️صفحه قبل', 'callback_data' => 'app_devices_page:' . ($Page - 1)];
}
if ($Page + 1 < $PageCount) {
$Navigation[] = ['text' => 'صفحه بعد➡️', 'callback_data' => 'app_devices_page:' . ($Page + 1)];
}
$Buttons[] = $Navigation;
}

$Buttons[] = Menu::back('منوی قبلی', 'user_device_menu');
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

SystemNotifications::queue($Context->UserId, 'امنیت دستگاه', '⚠️مجوز یکی از دستگاه‌های حساب شما لغو شد. اگر کار شما نبود، حساب را بررسی کنید.');
if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, 'مجوز لغو شد؛ برنامه از حساب خارج خواهد شد.');
}

self::devices($Context, $Page);
}

/** اعلان‌ها فقط برای دستگاه‌های خود کاربر، جدیدترین ابتدا. */
public static function notifications(Context $Context, int $Page = 0): void {
$Database = Database::getInstance();
$Where = 'WHERE `Device_ID` IN (SELECT `Device_ID` FROM `App_Devices` WHERE `Telegram_ID` = ?)';
$Total = (int)$Database->scalar('SELECT COUNT(*) FROM `App_Notifications` ' . $Where, [$Context->UserId], 0);
$PageCount = max(1, (int)ceil($Total / 3));
$Page = max(0, min($Page, $PageCount - 1));
$Rows = $Database->fetchAll('SELECT `ID`, `Title`, `Body`, `Level`, `Sent_At` FROM `App_Notifications` ' . $Where . ' ORDER BY `ID` DESC LIMIT ? OFFSET ?', [$Context->UserId, 3, $Page * 3]);
$Text = Helper::userGreeting($Context, 'اعلان‌های برنامه') . Menu::pageLabel($Page, $PageCount);
$Buttons = [];
if ($Rows === []) $Text .= '🔔اعلانی برای برنامه شما ثبت نشده است.';
foreach ($Rows as $Row) {
$Body = (string)($Row['Body'] ?? '');
$Text .= self::notificationText($Row, mb_substr($Body, 0, 650) . (mb_strlen($Body) > 650 ? '…' : ''));
if (mb_strlen($Body) > 650) {
$Buttons[] = [Menu::button('📄متن کامل اعلان #' . $Row['ID'], 'app_notification:' . $Row['ID'] . ':' . $Page . ':0')];
}
}
$Buttons = array_merge($Buttons, Menu::pages($Page, $PageCount, 'app_notifications_page:'));
$Buttons[] = Menu::back('منوی قبلی', 'user_device_menu');
$Buttons[] = Menu::userHome();
self::reply($Context, $Text . Helper::userFooter(), TelegramClient::inlineKeyboard($Buttons));
}

/** متن بلند اعلان بدون حذف محتوا در صفحه‌های جدا خوانده می‌شود. */
public static function notificationView(Context $Context, int $Id, int $ListPage = 0, int $Part = 0): void {
$Row = Database::getInstance()->fetch('SELECT `ID`, `Title`, `Body`, `Level`, `Sent_At` FROM `App_Notifications` WHERE `ID` = ? AND `Device_ID` IN (SELECT `Device_ID` FROM `App_Devices` WHERE `Telegram_ID` = ?) LIMIT 1', [$Id, $Context->UserId]);
if ($Row === null) { self::notifications($Context, $ListPage); return; }
$Body = (string)($Row['Body'] ?? '');
$Count = max(1, (int)ceil(mb_strlen($Body) / 2200));
$Part = max(0, min($Part, $Count - 1));
$ListPage = max(0, $ListPage);
$Text = Helper::userGreeting($Context, 'متن اعلان') . Menu::pageLabel($Part, $Count)
. self::notificationText($Row, mb_substr($Body, $Part * 2200, 2200));
$Buttons = Menu::pages($Part, $Count, 'app_notification:' . $Id . ':' . $ListPage . ':');
$Buttons[] = Menu::back('اعلان‌ها', 'app_notifications_page:' . $ListPage);
$Buttons[] = Menu::userHome();
self::reply($Context, $Text, TelegramClient::inlineKeyboard($Buttons));
}

private static function notificationText(array $Row, string $Body): string {
$Safe = static fn(string $Value): string => htmlspecialchars(str_replace(['*', '`', '[', ']'], ['＊', '｀', '［', '］'], $Value), ENT_NOQUOTES | ENT_SUBSTITUTE, 'UTF-8');
$Icon = match((string)($Row['Level'] ?? '')) { 'warning' => '⚠️', 'error' => '⛔️', 'success' => '✅', default => '🔔' };
return $Icon . ' ' . $Safe(mb_substr((string)($Row['Title'] ?? ''), 0, 190)) . "\n"
. $Safe($Body) . "\n🕐 " . $Safe((string)($Row['Sent_At'] ?? '')) . "\n➖➖➖➖➖➖➖➖➖\n";
}

/** The switch that decides whether a sign-in also needs a tap here. */
public static function twoStepMenu(Context $Context): void {
if (self::accountOrPrompt($Context, 'user_device_menu') === null) {
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
$Rows[] = Menu::back('منوی قبلی', 'user_device_menu');
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

private static function accountOrPrompt(Context $Context, string $Parent = 'user_device_menu'): ?array {
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
$Result = TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Text, $EditMarkup);
if (($Result['ok'] ?? false) === true || str_contains((string)($Result['description'] ?? ''), 'message is not modified')) return;
}

catch (Throwable) {
}
}

TelegramClient::sendMessage($Context->ChatId, $Text, $Markup);
}
}
?>
