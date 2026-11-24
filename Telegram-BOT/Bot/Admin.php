<?php
declare(strict_types=1);

require_once __DIR__ . '/Context.php';
require_once __DIR__ . '/../Core/App/Device-Deletion.php';
require_once __DIR__ . '/../Core/App/Account-Revocation.php';
require_once __DIR__ . '/../Core/App/App-Filter.php';
require_once __DIR__ . '/Ticket-Media.php';
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
'Plan_Price_1' => ['label' => 'قیمت پلن ۱ ماهه', 'type' => 'price', 'screen' => 'pricing', 'hint' => 'عدد به تومان، مثلا ۴۰۰۰۰۰'],
'Plan_Price_2' => ['label' => 'قیمت پلن ۲ ماهه', 'type' => 'price', 'screen' => 'pricing', 'hint' => 'عدد به تومان، مثلا ۷۰۰۰۰۰'],
'Plan_Price_3' => ['label' => 'قیمت پلن ۳ ماهه', 'type' => 'price', 'screen' => 'pricing', 'hint' => 'عدد به تومان، مثلا ۱۰۰۰۰۰۰'],
'Plan_Price_6' => ['label' => 'قیمت پلن ۶ ماهه', 'type' => 'price', 'screen' => 'pricing', 'hint' => 'عدد به تومان، مثلا ۱۸۰۰۰۰۰'],
'Plan_Price_12' => ['label' => 'قیمت پلن ۱۲ ماهه', 'type' => 'price', 'screen' => 'pricing', 'hint' => 'عدد به تومان، مثلا ۳۰۰۰۰۰۰'],
'Custom_Min_Days' => ['label' => 'حداقل روز پلن دلخواه', 'type' => 'days', 'screen' => 'pricing', 'hint' => 'عدد صحیح روز، حداقل ۱'],
'Custom_Max_Days' => ['label' => 'حداکثر روز پلن دلخواه', 'type' => 'days', 'screen' => 'pricing', 'hint' => 'عدد صحیح روز، مثلا ۳۶۵'],
'Custom_Min_GB' => ['label' => 'حداقل حجم پلن دلخواه', 'type' => 'gb', 'screen' => 'pricing', 'hint' => 'عدد به گیگابایت، حداقل ۰.۱'],
'Custom_Max_GB' => ['label' => 'حداکثر حجم پلن دلخواه', 'type' => 'gb', 'screen' => 'pricing', 'hint' => 'عدد به گیگابایت، مثلا ۱۰۰۰'],
'Support_Url' => ['label' => 'لینک پشتیبانی', 'type' => 'link', 'screen' => 'links', 'hint' => 'آدرس کامل https://t.me/... یا نام کاربری با @'],
'Channel_Url' => ['label' => 'نام کاربری کانال تلگرام', 'type' => 'link', 'screen' => 'links', 'hint' => 'نام کاربری عمومی کانال، مانند @UmbrellaVPN_Channel یا https://t.me/UmbrellaVPN_Channel؛ شناسه عددی خودکار دریافت می شود'],
'Telegram_Channel_ID' => ['label' => 'شناسه کانال تلگرام', 'type' => 'channel', 'screen' => 'links', 'hint' => 'شناسه عددی و معمولا منفی، مثال: -۱۰۰۱۸۳۳۵۱۴۸۳۳'],
];

private function __construct() {
}

/** منوی اصلی مدیریت تک ستونه؛ هر دسته یا میانبر در یک ردیف مستقل. */
public static function menu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Temp_UID' => null, 'Broadcast_Mode' => null]);
$Robot_On = Common::isRobotOn();
// شمارش ها نباید منوی مدیریت را بشکنند: اگر دیتابیس پاسخ نداد، صفر نشان داده می شود.
try {
$Waiting_Tickets = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Tickets` WHERE `Status` IN ('open','pending')", [], 0);
$Active_Users = (int)Database::getInstance()->scalar('SELECT COUNT(*) FROM `Users` WHERE `Is_Blocked` = 0', [], 0);
$Blocked_Users = (int)Database::getInstance()->scalar('SELECT COUNT(*) FROM `Users` WHERE `Is_Blocked` = 1', [], 0);
}

catch (Throwable) {
$Waiting_Tickets = 0;
$Active_Users = 0;
$Blocked_Users = 0;
}
$Text = Helper::adminGreeting($Context, 'منوی مدیریت')
. Menu::section('📊', 'وضعیت کلی', [
'🚦وضعیت ربات: *' . ($Robot_On ? '🟢روشن' : '🔴خاموش') . '*',
'👥کاربران فعال: *' . Helper::toPersian((string)$Active_Users) . '*',
'🚫کاربران مسدود: *' . Helper::toPersian((string)$Blocked_Users) . '*',
'🎫تیکت در انتظار پاسخ: *' . Helper::toPersian((string)$Waiting_Tickets) . '*',
])
. '📌*امکان مورد نظر را انتخاب کنید:*' . Helper::adminFooter();
$Markup = Menu::rows([
[['💳مدیریت اعتبار', 'اعتبار حساب کاربری']],
[['🔒مسدود سازی کاربران', 'جرایم']],
[['📱مدیریت دستگاه ها', 'admin_devices_menu']],
[['🛡کنترل محتوا', 'admin_content_filter']],
[['👤مدیریت حساب کاربری', 'admin_accounts_menu']],
[['🖥مدیریت کلاینت', 'عملیات کلاینت سرور']],
[['🖥مدیریت سرور', 'پیکربندی سرور']],
[['📊آمار و گزارشات', 'منوی گزارش']],
[['📨پیام رسانی و اطلاع رسانی', 'منوی پیامک']],
[['🎫تیکت ها', 'مدیریت تیکت ها']],
[['💰مدیریت تعرفه و اشتراک', 'admin_subscriptions_menu']],
[['🗄مدیریت دیتابیس', 'منوی سیستم']],
[['🔄بروزرسانی نسخه', 'بروز رسانی']],
]);
array_unshift($Markup, [Menu::button($Robot_On ? '🔴خاموش کردن ربات' : '🟢روشن کردن ربات', $Robot_On ? 'خاموش کردن ربات' : 'روشن کردن ربات')]);

self::logMenuProblems('menu', $Markup);

if ($Context->IsCallback && $Context->MessageId !== null) {
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Markup));
}

else {
TelegramClient::sendMessage($Context->ChatId, $Text, TelegramClient::inlineKeyboard($Markup));
}
}

/** نمایش دسته و لغو حالت دریافت ورودی قبلی هنگام بازگشت. */
private static function categoryMenu(Context $Context, string $Title, array $Rows, string $Parent): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Temp_UID' => null, 'Broadcast_Mode' => null]);
$Rows = array_merge($Rows, Menu::adminNav('منوی قبلی', $Parent));
self::logMenuProblems($Title, $Rows);
$Text = Helper::adminGreeting($Context, $Title)
. "\n📌*بخش مورد نظر را انتخاب کنید:*" . Helper::adminFooter();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Rows));
}

public static function devicesMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Rows = Menu::rows([
[['👁رصد کاربران', 'admin_user_monitor']],
[['📲دستگاه های برنامه', 'admin_devices']],
[['🔐سقف دستگاه حساب', 'device_limit_menu']],
[['🗑حذف همه دستگاه ها', 'admin_devices_delete_all_menu']],
]);
self::categoryMenu($Context, 'مدیریت دستگاه ها', $Rows, 'مدیریت');
}

/** رصد کاربران: فهرست کاربران حاضر در نرم افزار/اپلیکیشن به ترتیب آخرین فعالیت. */
public static function userMonitorList(Context $Context, int $Page = 0): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
self::ensureAppSchemaReady();
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Temp_UID' => null, 'Broadcast_Mode' => null]);

$Db = Database::getInstance();
$Devices = [];
try {
$Devices = $Db->fetchAll(
'SELECT `D`.`ID`, `D`.`Device_ID`, `D`.`Device_Name`, `D`.`Platform`, `D`.`Phone`, `D`.`Telegram_ID`, `D`.`User_UUID`, `D`.`Is_Trusted`, `D`.`Last_Seen_At`, `D`.`Last_IP`, `D`.`App_Version`, '
. '`U`.`Full_Name` AS `Owner_Name`, `U`.`Phone` AS `Owner_Phone`, `U`.`Telegram_ID` AS `Matched_Tg_ID` '
. 'FROM `App_Devices` AS `D` '
. 'LEFT JOIN `Users` AS `U` ON `U`.`ID` = ('
. 'SELECT MIN(`O`.`ID`) FROM `Users` AS `O` WHERE '
. '(`D`.`Telegram_ID` > 0 AND `O`.`Telegram_ID` = `D`.`Telegram_ID`) OR '
. '(`D`.`User_UUID` IS NOT NULL AND `D`.`User_UUID` != \'\' AND `O`.`Client_ID` = `D`.`User_UUID`) OR '
. '(COALESCE(`D`.`Telegram_ID`, 0) <= 0 AND `D`.`Phone` IS NOT NULL AND LENGTH(`D`.`Phone`) > 0 AND `O`.`Phone` = `D`.`Phone`)'
. ') '
. 'ORDER BY `D`.`Last_Seen_At` DESC, `D`.`ID` DESC',
[]
);
} catch (Throwable $Error) {
error_log('[Umbrella-Bot][MonitorList] devices: ' . $Error->getMessage());
}

$ActivityStats = [];
try {
$StatRows = $Db->fetchAll(
'SELECT `Device_ID`, `Category`, COUNT(*) AS `Cnt`, COALESCE(MAX(`Last_Seen_At`), 0) AS `Last_At` '
. 'FROM `App_User_Activity` GROUP BY `Device_ID`, `Category`',
[]
);
foreach ($StatRows as $Stat) {
$DevId = (string)($Stat['Device_ID'] ?? '');
if ($DevId === '') continue;
if (!isset($ActivityStats[$DevId])) {
$ActivityStats[$DevId] = ['site' => 0, 'app' => 0, 'screen' => 0, 'last' => 0];
}
$Cat = (string)($Stat['Category'] ?? '');
if (isset($ActivityStats[$DevId][$Cat])) {
$ActivityStats[$DevId][$Cat] += (int)($Stat['Cnt'] ?? 0);
}
$ActivityStats[$DevId]['last'] = max($ActivityStats[$DevId]['last'], (int)($Stat['Last_At'] ?? 0));
}
} catch (Throwable) {}

$Groups = [];
foreach ($Devices as $Dev) {
$TgId = (int)($Dev['Telegram_ID'] ?? 0);
if ($TgId <= 0) $TgId = (int)($Dev['Matched_Tg_ID'] ?? 0);
$Uuid = trim((string)($Dev['User_UUID'] ?? ''));
$Phone = trim((string)($Dev['Owner_Phone'] ?? ($Dev['Phone'] ?? '')));
if ($TgId > 0) {
$GroupKey = 't:' . $TgId;
} elseif ($Uuid !== '' && $Uuid !== '_') {
$GroupKey = 'u:' . $Uuid;
} elseif ($Phone !== '') {
$GroupKey = 'p:' . $Phone;
} else {
$GroupKey = 'd:' . (int)($Dev['ID'] ?? 0);
}

if (!isset($Groups[$GroupKey])) {
$Groups[$GroupKey] = [
'selector' => $TgId > 0 ? ('t:' . $TgId) : ('d:' . (int)($Dev['ID'] ?? 0)),
'tg_id' => $TgId,
'name' => trim((string)($Dev['Owner_Name'] ?? '')) ?: trim((string)($Dev['Device_Name'] ?? '')) ?: 'کاربر برنامه',
'phone' => $Phone,
'devices' => 0,
'trusted' => 0,
'sites' => 0,
'apps' => 0,
'screens' => 0,
'last_seen' => 0,
];
}
$Groups[$GroupKey]['devices']++;
if ((int)($Dev['Is_Trusted'] ?? 0) === 1) $Groups[$GroupKey]['trusted']++;
$DevId = (string)($Dev['Device_ID'] ?? '');
$LastDev = self::monitorTimestamp($Dev['Last_Seen_At'] ?? 0);
$Stat = $ActivityStats[$DevId] ?? ['site' => 0, 'app' => 0, 'screen' => 0, 'last' => 0];
$Groups[$GroupKey]['sites'] += (int)$Stat['site'];
$Groups[$GroupKey]['apps'] += (int)$Stat['app'];
$Groups[$GroupKey]['screens'] += (int)$Stat['screen'];
$Groups[$GroupKey]['last_seen'] = max($Groups[$GroupKey]['last_seen'], $LastDev, (int)$Stat['last']);
}

$GroupList = array_values($Groups);
usort($GroupList, static fn(array $A, array $B): int => $B['last_seen'] <=> $A['last_seen']);

$PageSize = 5;
$Total = count($GroupList);
$PageCount = max(1, (int)ceil($Total / $PageSize));
$Page = max(0, min($Page, $PageCount - 1));
$Slice = array_slice($GroupList, $Page * $PageSize, $PageSize);

$Text = Helper::adminGreeting($Context, 'رصد کاربران')
. Menu::section('👁', 'پایش لحظه ای کاربران در اپلیکیشن آمبرلا', [
'👥تعداد کاربران ثبت شده: ' . Helper::toPersian((string)$Total) . ' کاربر',
'📄صفحه ' . Helper::toPersian((string)($Page + 1)) . ' از ' . Helper::toPersian((string)$PageCount),
'ℹ️روی نام هر کاربر کلیک کنید تا دستگاه ها، سایت ها و برنامه های باز شده او را ببینید.',
]);

$Buttons = [];
if ($Slice === []) {
$Text .= "\n📭هنوز کاربری در اپلیکیشن ثبت یا فعال نشده است.\n";
}

foreach ($Slice as $Index => $Group) {
$Num = Helper::toPersian((string)($Page * $PageSize + $Index + 1));
$NameSafe = self::listText((string)$Group['name']);
$TgId = (int)$Group['tg_id'];
$NameLink = $TgId > 0 ? '<a href="tg://user?id=' . $TgId . '">' . $NameSafe . '</a>' : $NameSafe;
$LastText = $Group['last_seen'] > 0
? Helper::formatDateTimeText((string)$Group['last_seen'])
: 'ثبت نشده';

$Text .= "\n{$Num}. 👤 " . $NameLink . "\n"
. ($TgId > 0 ? '🆔شناسه تلگرام: <code>' . Helper::toPersian((string)$TgId) . "</code>\n" : '')
. ($Group['phone'] !== '' ? '📞شماره: <code>' . self::listText(Helper::toPersian((string)$Group['phone'])) . "</code>\n" : '')
. '📱دستگاه ها: ' . Helper::toPersian((string)$Group['trusted']) . ' مجاز از ' . Helper::toPersian((string)$Group['devices']) . "\n"
. '📊رصد ثبت شده: 🌐 ' . Helper::toPersian((string)$Group['sites']) . ' سایت | 💻 ' . Helper::toPersian((string)$Group['apps']) . ' برنامه | 📱 ' . Helper::toPersian((string)$Group['screens']) . " بخش\n"
. '🕓آخرین فعالیت: ' . self::listText($LastText) . "\n➖➖➖➖➖➖➖➖➖\n";

$BtnTitle = $Num . '. 👁 ' . mb_substr((string)$Group['name'], 0, 26)
. ' (' . Helper::toPersian((string)$Group['sites']) . '🌐 ' . Helper::toPersian((string)$Group['apps']) . '💻)';
$Buttons[] = [Menu::button($BtnTitle, 'admin_monitor_view:' . $Group['selector'] . ':' . $Page . ':all:0')];
}

$Buttons = array_merge(
$Buttons,
Menu::pages($Page, $PageCount, 'admin_user_monitor_page:'),
[
[Menu::button('🔄بروزرسانی فهرست', 'admin_user_monitor_page:' . $Page)],
Menu::back('منوی قبلی', 'admin_devices_menu'),
Menu::adminHome(),
]
);
self::logMenuProblems('user-monitor-list', $Buttons);
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text . Helper::adminFooter(), TelegramClient::inlineKeyboard($Buttons));
}

/** جزئیات رصد یک کاربر: دستگاه ها + سایت ها + نرم افزارها + صفحات برنامه. */
public static function userMonitorView(Context $Context, string $TargetKey, int $ListPage = 0, string $Category = 'all', int $InnerPage = 0): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
self::ensureAppSchemaReady();

$Category = in_array($Category, ['all', 'site', 'app', 'screen'], true) ? $Category : 'all';
$ListPage = max(0, $ListPage);
$InnerPage = max(0, $InnerPage);
$Db = Database::getInstance();

$OwnerTgId = 0;
$SeedDeviceId = 0;
if (str_starts_with($TargetKey, 't:')) {
$OwnerTgId = (int)substr($TargetKey, 2);
} elseif (str_starts_with($TargetKey, 'd:')) {
$SeedDeviceId = (int)substr($TargetKey, 2);
}

$UserRow = $OwnerTgId > 0 ? Repository::getUser($OwnerTgId) : [];
$UserUuid = trim((string)($UserRow['Client_ID'] ?? ''));
$UserPhone = trim((string)($UserRow['Phone'] ?? ''));

if ($SeedDeviceId > 0) {
$Seed = $Db->fetch('SELECT * FROM `App_Devices` WHERE `ID` = ? LIMIT 1', [$SeedDeviceId]);
if (is_array($Seed)) {
$OwnerTgId = (int)($Seed['Telegram_ID'] ?? 0);
if ($UserUuid === '' || $UserUuid === '_') $UserUuid = trim((string)($Seed['User_UUID'] ?? ''));
if ($UserPhone === '') $UserPhone = trim((string)($Seed['Phone'] ?? ''));
if ($OwnerTgId > 0 && $UserRow === []) $UserRow = Repository::getUser($OwnerTgId);
}
}

$Conds = [];
$Params = [];
if ($OwnerTgId > 0) {
$Conds[] = '`Telegram_ID` = ?';
$Params[] = $OwnerTgId;
}
if ($UserUuid !== '' && $UserUuid !== '_') {
$Conds[] = '`User_UUID` = ?';
$Params[] = $UserUuid;
}
if ($UserPhone !== '') {
$Variants = self::phoneCandidates($UserPhone);
if ($Variants !== []) {
$Conds[] = '`Phone` IN (' . implode(',', array_fill(0, count($Variants), '?')) . ')';
$Params = array_merge($Params, $Variants);
}
}
if ($SeedDeviceId > 0) {
$Conds[] = '`ID` = ?';
$Params[] = $SeedDeviceId;
}

$DeviceRows = $Conds !== []
? $Db->fetchAll('SELECT * FROM `App_Devices` WHERE (' . implode(' OR ', $Conds) . ') ORDER BY `Last_Seen_At` DESC, `ID` DESC', $Params)
: [];

if ($DeviceRows === [] && $UserRow === []) {
if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, 'اطلاعاتی برای این کاربر پیدا نشد.', true);
}
self::userMonitorList($Context, $ListPage);
return;
}

$DeviceIds = array_values(array_unique(array_filter(array_map(
static fn(array $D): string => trim((string)($D['Device_ID'] ?? '')),
$DeviceRows
))));

$DisplayName = trim((string)($UserRow['Full_Name'] ?? ''))
?: trim((string)($DeviceRows[0]['Device_Name'] ?? ''))
?: 'کاربر برنامه';
$DisplayPhone = $UserPhone !== '' ? $UserPhone : trim((string)($DeviceRows[0]['Phone'] ?? ''));

$ActConds = [];
$ActParams = [];
if ($DeviceIds !== []) {
$ActConds[] = '`Device_ID` IN (' . implode(',', array_fill(0, count($DeviceIds), '?')) . ')';
$ActParams = array_merge($ActParams, $DeviceIds);
}
if ($OwnerTgId > 0) {
$ActConds[] = '`Telegram_ID` = ?';
$ActParams[] = $OwnerTgId;
}
if ($UserUuid !== '' && $UserUuid !== '_') {
$ActConds[] = '`User_UUID` = ?';
$ActParams[] = $UserUuid;
}

$AllActivities = [];
if ($ActConds !== []) {
try {
$AllActivities = $Db->fetchAll(
'SELECT `Device_ID`, `Category`, `Target`, `Hits`, `Bytes_Down`, `Bytes_Up`, `Last_Seen_At` '
. 'FROM `App_User_Activity` WHERE (' . implode(' OR ', $ActConds) . ') ORDER BY `Last_Seen_At` DESC, `Hits` DESC',
$ActParams
);
} catch (Throwable) {}
}

$Counts = ['site' => 0, 'app' => 0, 'screen' => 0];
foreach ($AllActivities as $Act) {
$Cat = (string)($Act['Category'] ?? '');
if (isset($Counts[$Cat])) $Counts[$Cat]++;
}

$Filtered = $Category === 'all'
? $AllActivities
: array_values(array_filter($AllActivities, static fn(array $A): bool => ($A['Category'] ?? '') === $Category));

$PerPage = 10;
$TotalFiltered = count($Filtered);
$InnerPages = max(1, (int)ceil($TotalFiltered / $PerPage));
$InnerPage = max(0, min($InnerPage, $InnerPages - 1));
$Visible = array_slice($Filtered, $InnerPage * $PerPage, $PerPage);

$DeviceMap = [];
foreach ($DeviceRows as $D) {
$DeviceMap[(string)$D['Device_ID']] = trim((string)($D['Device_Name'] ?? '')) ?: 'دستگاه';
}

$TitleLink = $OwnerTgId > 0
? '<a href="tg://user?id=' . $OwnerTgId . '">' . self::listText($DisplayName) . '</a>'
: self::listText($DisplayName);

$Text = Helper::adminGreeting($Context, 'رصد فعالیت کاربر')
. '👤کاربر: ' . $TitleLink . "\n"
. ($OwnerTgId > 0 ? '🆔شناسه تلگرام: <code>' . Helper::toPersian((string)$OwnerTgId) . "</code>\n" : '')
. ($DisplayPhone !== '' ? '📞شماره موبایل: <code>' . self::listText(Helper::toPersian($DisplayPhone)) . "</code>\n" : '')
. '📊آمار کل رصد: 🌐 ' . Helper::toPersian((string)$Counts['site']) . ' سایت | 💻 ' . Helper::toPersian((string)$Counts['app']) . ' نرم افزار/اپ | 📱 ' . Helper::toPersian((string)$Counts['screen']) . " صفحه برنامه\n"
. "➖➖➖➖➖➖➖➖➖\n"
. '📱<b>دستگاه های کاربر (' . Helper::toPersian((string)count($DeviceRows)) . "):</b>\n";

foreach (array_slice($DeviceRows, 0, 5) as $Idx => $Dev) {
$Plat = method_exists('Helper', 'formatPlatform') ? Helper::formatPlatform((string)($Dev['Platform'] ?? '')) : (string)($Dev['Platform'] ?? '');
$LastDevTs = self::monitorTimestamp($Dev['Last_Seen_At'] ?? 0);
$LastDev = $LastDevTs > 0 ? Helper::formatDateTimeText((string)$LastDevTs) : 'ثبت نشده';
$TrustIcon = (int)($Dev['Is_Trusted'] ?? 0) === 1 ? '✅' : '⛔️';
$Text .= Helper::toPersian((string)($Idx + 1)) . '. ' . $TrustIcon . ' '
. self::listText((string)($Dev['Device_Name'] ?? 'دستگاه'))
. ($Plat !== '' ? ' (' . self::listText($Plat) . ')' : '')
. (!empty($Dev['App_Version']) ? ' | نسخه ' . self::listText(Helper::toPersian((string)$Dev['App_Version'])) : '')
. "\n   🌐 آی پی: <code>" . self::listText(Helper::toPersian((string)($Dev['Last_IP'] ?? ''))) . '</code> | 🕓 ' . self::listText($LastDev) . "\n";
}

$CatLabel = match ($Category) {
'site' => '🌐 سایت های باز شده',
'app' => '💻 نرم افزارها و اپلیکیشن ها',
'screen' => '📱 بخش های باز شده در برنامه',
default => '👁 همه فعالیت های رصد شده',
};
$Text .= "\n➖➖➖➖➖➖➖➖➖\n<b>{$CatLabel}</b> (صفحه " . Helper::toPersian((string)($InnerPage + 1)) . ' از ' . Helper::toPersian((string)$InnerPages) . "):\n\n";

if ($Visible === []) {
$Text .= "📭هنوز موردی در این بخش ثبت نشده است.\n<i>(هنگام اتصال VPN و استفاده کاربر از سایت ها و برنامه ها، اطلاعات خودکار ثبت می شود.)</i>\n";
}

foreach ($Visible as $Item) {
$Cat = (string)($Item['Category'] ?? '');
$Icon = match ($Cat) { 'site' => '🌐', 'app' => '💻', default => '📱' };
$TargetLabel = self::listText((string)($Item['Target'] ?? ''));
$Hits = (int)($Item['Hits'] ?? 1);
$Bytes = (int)($Item['Bytes_Down'] ?? 0) + (int)($Item['Bytes_Up'] ?? 0);
$DevName = $DeviceMap[(string)($Item['Device_ID'] ?? '')] ?? '';
$WhenTs = (int)($Item['Last_Seen_At'] ?? 0);
$WhenText = $WhenTs > 0 ? Helper::formatDateTimeText((string)$WhenTs) : '';

$Line = "{$Icon} <code>{$TargetLabel}</code> — " . Helper::toPersian((string)$Hits) . ' بار';
if ($Bytes > 0) {
$Line .= ' | ' . Helper::formatBytes($Bytes);
}
if ($DevName !== '' && count($DeviceRows) > 1) {
$Line .= ' | ' . self::listText($DevName);
}
if ($WhenText !== '') {
$Line .= "\n   🕒 " . self::listText($WhenText);
}
$Text .= $Line . "\n";
}

$FilterButtons = [
[
Menu::button(($Category === 'all' ? '✅' : '') . '👁همه (' . Helper::toPersian((string)array_sum($Counts)) . ')', 'admin_monitor_view:' . $TargetKey . ':' . $ListPage . ':all:0'),
Menu::button(($Category === 'site' ? '✅' : '') . '🌐سایت ها (' . Helper::toPersian((string)$Counts['site']) . ')', 'admin_monitor_view:' . $TargetKey . ':' . $ListPage . ':site:0'),
],
[
Menu::button(($Category === 'app' ? '✅' : '') . '💻نرم افزار/اپ (' . Helper::toPersian((string)$Counts['app']) . ')', 'admin_monitor_view:' . $TargetKey . ':' . $ListPage . ':app:0'),
Menu::button(($Category === 'screen' ? '✅' : '') . '📱صفحات (' . Helper::toPersian((string)$Counts['screen']) . ')', 'admin_monitor_view:' . $TargetKey . ':' . $ListPage . ':screen:0'),
],
];

$Buttons = array_merge(
$FilterButtons,
Menu::pages($InnerPage, $InnerPages, 'admin_monitor_view:' . $TargetKey . ':' . $ListPage . ':' . $Category . ':'),
[
[Menu::button('🔄بروزرسانی رصد', 'admin_monitor_view:' . $TargetKey . ':' . $ListPage . ':' . $Category . ':' . $InnerPage)],
Menu::back('بازگشت به فهرست رصد', 'admin_user_monitor_page:' . $ListPage),
Menu::back('مدیریت دستگاه ها', 'admin_devices_menu'),
Menu::adminHome(),
]
);

TelegramClient::sendReadableMessage($Context->ChatId, $Context->MessageId, $Text . Helper::adminFooter(), TelegramClient::inlineKeyboard($Buttons));
}

private static function monitorTimestamp(mixed $Raw): int {
if (is_int($Raw) || (is_string($Raw) && ctype_digit(trim($Raw)))) {
return (int)$Raw;
}
$Str = trim((string)$Raw);
if ($Str === '' || $Str === '0000-00-00 00:00:00') return 0;
$Parsed = strtotime($Str);
return $Parsed === false ? 0 : $Parsed;
}

public static function accountsMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Rows = Menu::rows([
[['👥لیست کاربران', 'admin_users']],
[['🗑حذف کاربر', 'حذف کاربر اول']],
[['⌛️منقضی کردن اشتراک', 'منقضی اشتراک اول']],
]);
self::categoryMenu($Context, 'مدیریت حساب کاربری', $Rows, 'مدیریت');
}

/** Global content policy editor for every app account. */
public static function globalContentFilterMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Temp_UID' => null, 'Broadcast_Mode' => null]);
$Settings = AppFilter::loadGlobal();
$Rows = [];
$Pair = [];
foreach (AppFilter::BOT_CATEGORIES as $Key => $Label) {
$Pair[] = [
'text' => (in_array($Key, $Settings['categories'], true) ? '✅ ' : '⚪️ ') . $Label,
'callback_data' => 'admin_gfilter_toggle:' . $Key,
];
if (count($Pair) === 2) { $Rows[] = $Pair; $Pair = []; }
}
if ($Pair !== []) $Rows[] = $Pair;
$Domain_Count = count($Settings['custom_domains']);
$Rows[] = [[
'text' => $Domain_Count > 0 ? '🌐دامنه های سراسری (' . Helper::toPersian((string)$Domain_Count) . ')' : '🌐دامنه های سراسری',
'callback_data' => 'admin_gfilter_domains',
]];
$Has_Rules = $Settings['categories'] !== [] || $Settings['custom_domains'] !== [];
$Rows[] = [[
'text' => !empty($Settings['enabled']) ? '🔴خاموش کردن کنترل محتوا برای همه' : '🟢روشن کردن کنترل محتوا برای همه',
'callback_data' => 'admin_gfilter_toggle:enabled',
]];
$Rows = array_merge($Rows, Menu::adminNav('منوی قبلی', 'مدیریت'));
$Text = Helper::adminGreeting($Context, 'کنترل محتوا')
. AppFilter::summary($Settings)
. "\n➖➖➖➖➖➖➖➖➖\n"
. ($Has_Rules
? '🌐 با روشن بودن کلید سراسری، دسته ها و دامنه های انتخاب شده روی اتصال همه کاربران برنامه اعمال می شود.'
: 'ℹ️ ابتدا یک دسته یا دامنه اضافه کنید؛ سپس کنترل محتوا را برای همه روشن کنید.')
. Helper::adminFooter();
self::logMenuProblems('global_content_filter', $Rows);
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Rows));
}

/** Toggle the global master switch or one globally enforced category. */
public static function globalContentFilterToggle(Context $Context, string $Key): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Current = AppFilter::loadGlobal();
if ($Key === 'enabled') {
$Has_Rules = $Current['categories'] !== [] || $Current['custom_domains'] !== [];
if (empty($Current['enabled']) && !$Has_Rules) {
if ($Context->CallbackId !== null) TelegramClient::answerCallbackQuery($Context->CallbackId, 'ابتدا یک دسته یا دامنه اضافه کنید.', true);
self::globalContentFilterMenu($Context);
return;
}
$Saved = AppFilter::saveGlobal([
'enabled' => empty($Current['enabled']),
'categories' => $Current['categories'],
'custom_domains' => $Current['custom_domains'],
]);
}
elseif (isset(AppFilter::BOT_CATEGORIES[$Key])) {
$Saved = AppFilter::toggleGlobalCategory($Key);
}
else {
self::globalContentFilterMenu($Context);
return;
}
try { Repository::logAdminAction($Context->UserId, 'global_content_filter_update', null, 'enabled=' . (int)!empty($Saved['enabled'])); } catch (Throwable) {}
if ($Context->CallbackId !== null) TelegramClient::answerCallbackQuery($Context->CallbackId, 'تنظیم سراسری ذخیره شد ✅');
self::globalContentFilterMenu($Context);
}

/** Paginated list of administrator-wide blocked domains. */
public static function globalContentFilterDomainsMenu(Context $Context, int $Page = 0, string $Notice = ''): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$Settings = AppFilter::loadGlobal();
$Domains = array_values($Settings['custom_domains']);
$Total = count($Domains);
$Page_Size = AppFilter::DOMAINS_PER_PAGE;
$Page_Count = max(1, (int)ceil($Total / $Page_Size));
$Page = max(0, min($Page, $Page_Count - 1));
$Slice = array_slice($Domains, $Page * $Page_Size, $Page_Size);
$Text = Helper::adminGreeting($Context, 'دامنه های کنترل محتوای سراسری')
. Menu::pageLabel($Page, $Page_Count);
if ($Notice !== '') $Text .= $Notice . "\n➖➖➖➖➖➖➖➖➖\n";
$Text .= '📊تعداد دامنه ها: ' . Helper::toPersian((string)$Total) . ' از ' . Helper::toPersian((string)AppFilter::MAX_CUSTOM_DOMAINS) . "\n";
foreach ($Slice as $Index => $Domain) {
$Text .= Helper::toPersian((string)($Page * $Page_Size + $Index + 1)) . '. ' . self::listText($Domain, 100) . "\n";
}
if ($Slice === []) $Text .= '📭هنوز دامنه سراسری ثبت نشده است.' . "\n";
$Text .= "\nℹ️ این دامنه ها هنگام فعال بودن سیاست سراسری برای همه کاربران برنامه اعمال می شوند." . Helper::adminFooter();
$Rows = [[['text' => '➕افزودن دامنه سراسری', 'callback_data' => 'admin_gfilter_add']]];
foreach ($Slice as $Domain) {
$Label = strlen($Domain) > 32 ? substr($Domain, 0, 29) . '...' : $Domain;
$Rows[] = [[
'text' => '🗑حذف ' . $Label,
'callback_data' => 'admin_gfilter_del:' . AppFilter::domainToken($Domain) . ':' . $Page,
]];
}
if ($Page_Count > 1) $Rows = array_merge($Rows, Menu::pages($Page, $Page_Count, 'admin_gfilter_page:'));
if ($Total > 0) $Rows[] = [[ 'text' => '🧹حذف همه دامنه ها', 'callback_data' => 'admin_gfilter_clear' ]];
$Rows = array_merge($Rows, Menu::adminNav('کنترل محتوا', 'admin_content_filter'));
self::logMenuProblems('global_content_filter_domains', $Rows);
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Rows));
}

public static function globalContentFilterDomainsStart(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Settings = AppFilter::loadGlobal();
if (count($Settings['custom_domains']) >= AppFilter::MAX_CUSTOM_DOMAINS) {
if ($Context->CallbackId !== null) TelegramClient::answerCallbackQuery($Context->CallbackId, 'ظرفیت دامنه های سراسری پر شده است.', true);
self::globalContentFilterDomainsMenu($Context);
return;
}
Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:global_filter_domains']);
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'دامنه های کنترل محتوای سراسری')
. "🌐 دامنه یا نشانی سایت را بفرستید؛ می توانید چند مورد را با فاصله یا خط جدید جدا کنید.\n"
. "برای حذف موردی پیش از دامنه - بگذارید (مانند -example.com).\n"
. 'این فهرست فقط هنگام روشن بودن کنترل محتوای سراسری روی همه کاربران اعمال می شود.' . Helper::adminFooter(),
TelegramClient::inlineKeyboard([Menu::back('انصراف', 'admin_gfilter_domains'), Menu::adminHome()]));
}

private static function globalContentFilterDomainsInput(Context $Context, string $Text): void {
$Trimmed = trim($Text);
if (in_array($Trimmed, ['لغو', 'انصراف', '/cancel'], true)) {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
self::globalContentFilterDomainsMenu($Context);
return;
}
$Parsed = AppFilter::parseDomainsInput($Trimmed);
if ($Parsed['add'] === [] && $Parsed['remove'] === []) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'دامنه نامعتبر')
. '⚠️دامنه معتبری پیدا نشد؛ نمونه درست: example.com' . Helper::adminFooter(),
TelegramClient::inlineKeyboard(Menu::adminNav('دامنه های سراسری', 'admin_gfilter_domains')));
return;
}
$Result = AppFilter::applyGlobalDomainChanges($Parsed['add'], $Parsed['remove']);
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$Lines = [];
if ($Result['added'] !== []) $Lines[] = '✅' . Helper::toPersian((string)count($Result['added'])) . ' دامنه اضافه شد.';
if ($Result['removed'] !== []) $Lines[] = '🗑' . Helper::toPersian((string)count($Result['removed'])) . ' دامنه حذف شد.';
if ($Result['duplicates'] !== []) $Lines[] = 'ℹ️' . Helper::toPersian((string)count($Result['duplicates'])) . ' مورد از قبل ثبت بود.';
if ($Result['skipped_limit'] !== []) $Lines[] = '⚠️به سقف دامنه های سراسری رسیدید؛ موارد مازاد نادیده گرفته شد.';
if ($Parsed['invalid'] !== []) $Lines[] = '⚠️' . Helper::toPersian((string)count($Parsed['invalid'])) . ' مورد نامعتبر نادیده گرفته شد.';
self::globalContentFilterDomainsMenu($Context, 0, implode("\n", $Lines));
}

public static function globalContentFilterDomainDelete(Context $Context, string $Token, int $Page = 0): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Result = AppFilter::removeGlobalDomainByToken($Token);
if ($Context->CallbackId !== null) TelegramClient::answerCallbackQuery($Context->CallbackId, $Result['removed'] !== null ? 'دامنه سراسری حذف شد ✅' : 'این دامنه قبلا حذف شده است.');
self::globalContentFilterDomainsMenu($Context, max(0, $Page));
}

public static function globalContentFilterClearAsk(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Count = count(AppFilter::loadGlobal()['custom_domains']);
if ($Count === 0) { self::globalContentFilterDomainsMenu($Context); return; }
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId,
self::header($Context, 'تأیید حذف دامنه های سراسری') . '⚠️آیا تمام ' . Helper::toPersian((string)$Count) . ' دامنه سراسری حذف شوند؟' . Helper::adminFooter(),
TelegramClient::inlineKeyboard([
[['text' => '🧹تأیید حذف همه', 'callback_data' => 'admin_gfilter_clear_ok']],
Menu::back('انصراف', 'admin_gfilter_domains'), Menu::adminHome(),
]));
}

public static function globalContentFilterClearConfirm(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
AppFilter::clearGlobalDomains();
if ($Context->CallbackId !== null) TelegramClient::answerCallbackQuery($Context->CallbackId, 'دامنه های سراسری پاک شدند ✅');
self::globalContentFilterDomainsMenu($Context, 0, '🧹تمام دامنه های سراسری پاک شدند.');
}

/** سازگاری با دکمه قدیمی پشتیبانی؛ بدون صفحه واسطه به تیکت ها می رود. */
public static function supportMenu(Context $Context): void {
self::ticketAdminMenu($Context);
}

public static function subscriptionsMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Rows = Menu::rows([
[['💰تعرفه و پلن ها', 'cfg_pricing']],
[['🔗لینک ها و کانال', 'cfg_links']],
]);
self::categoryMenu($Context, 'مدیریت تعرفه و اشتراک', $Rows, 'مدیریت');
}

/** بررسی سلامت کیبورد و ثبت خطاها در لاگ؛ چیزی به کاربر نشان داده نمی شود. */
private static function logMenuProblems(string $Screen, array $Rows): void {
$Problems = Menu::problems($Rows);

if ($Problems !== []) {
error_log('[Umbrella-Bot][Menu-' . $Screen . '] ' . implode(' | ', $Problems));
}
}

/** دسته مدیریت یا مسیر سازگار با دکمه های قدیمی. */
public static function usersMenu(Context $Context): void {
self::menu($Context);
}

/** مدیریت یکپارچه فهرست دستگاه ها و مجوز ورود برنامه. */
public static function appDevicesMenu(Context $Context, int $Page = 0): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Database = Database::getInstance();
// سه دستگاه در هر صفحه: اطلاعات کامل و نام های بلند در محدودیت پیام تلگرام جا می شوند.
$Page_Size = 3;
$Total = (int)$Database->scalar('SELECT COUNT(*) FROM `App_Devices`', [], 0);
$Page_Count = max(1, (int)ceil($Total / $Page_Size));
$Page = max(0, min($Page, $Page_Count - 1));
// نام و منشن از یک رکورد واحد می آیند. شناسه تلگرام اولویت دارد؛
// شماره فقط وقتی شناسه نداریم و دقیقاً یک کاربر منطبق است استفاده می شود.
$Rows = $Database->fetchAll(
'SELECT `D`.`ID`, `D`.`Device_ID`, `D`.`Device_Name`, `D`.`Platform`, `D`.`Phone`, `D`.`Telegram_ID`, `D`.`Is_Trusted`, `D`.`Last_Seen_At`, `D`.`Last_IP`, `D`.`App_Version`, '
. '`U`.`Full_Name` AS `Owner_Name`, '
. 'CASE WHEN `D`.`Telegram_ID` > 0 THEN `D`.`Telegram_ID` ELSE `U`.`Telegram_ID` END AS `Owner_Telegram_ID` '
. 'FROM `App_Devices` AS `D` LEFT JOIN `Users` AS `U` ON `U`.`ID` = ('
. 'SELECT MIN(`O`.`ID`) FROM `Users` AS `O` WHERE '
. '(`D`.`Telegram_ID` > 0 AND `O`.`Telegram_ID` = `D`.`Telegram_ID`) OR '
. '(COALESCE(`D`.`Telegram_ID`, 0) <= 0 AND `D`.`Phone` IS NOT NULL AND LENGTH(`D`.`Phone`) > 0 AND `O`.`Phone` = `D`.`Phone`) '
. 'HAVING COUNT(*) = 1) '
. 'ORDER BY `D`.`Last_Seen_At` DESC, `D`.`ID` DESC LIMIT ? OFFSET ?',
[$Page_Size, $Page * $Page_Size]
);
$Text = Helper::adminGreeting($Context, 'مدیریت دستگاه های برنامه')
. Menu::section('📲', 'فهرست دستگاه های ثبت شده', [
'📊تعداد کل: ' . Helper::toPersian((string)$Total) . ' دستگاه',
'📄صفحه ' . Helper::toPersian((string)($Page + 1)) . ' از ' . Helper::toPersian((string)$Page_Count),
'🔐دکمه شماره دار هر دستگاه، مجوز ورود همان دستگاه را تغییر می دهد.',
'ℹ️مجاز بودن دستگاه به معنی آنلاین بودن آن نیست؛ زمان آخرین فعالیت، زمان ثبت شده سرور است.',
]);
// داده های دریافتی از دستگاه نباید قالب پیام یا لینک های آن را تغییر دهند.
$Plain = static function (string $Value, int $Limit = 64): string {
$Value = trim((string)preg_replace('/[\s\p{C}]+/u', ' ', $Value));
$Value = mb_substr($Value, 0, $Limit);
$Value = str_replace(['*', '`', '[', ']'], ['＊', '｀', '［', '］'], $Value);
return htmlspecialchars($Value !== '' ? $Value : 'ثبت نشده', ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
};
$Buttons = [];
if ($Rows === []) {
$Text .= "\n📭هنوز دستگاهی در برنامه ثبت نشده است.\n";
}
foreach ($Rows as $Index => $Row) {
$Number = Helper::toPersian((string)($Page * $Page_Size + $Index + 1));
$Trusted = (int)($Row['Is_Trusted'] ?? 0) === 1;
$Device_Name = trim((string)($Row['Device_Name'] ?? '')) ?: 'دستگاه بی نام';
$Owner = trim((string)($Row['Owner_Name'] ?? '')) ?: 'نام کامل ثبت نشده';
$Owner_Id = (int)($Row['Owner_Telegram_ID'] ?? 0);
$Owner_Label = $Plain($Owner, 190);
if ($Owner_Id > 0) {
$Owner_Label = '<a href="tg://user?id=' . $Owner_Id . '">' . $Owner_Label . '</a>';
}
$When_Raw = trim((string)($Row['Last_Seen_At'] ?? ''));
$When_Label = method_exists('Helper', 'formatDateTimeText') ? Helper::formatDateTimeText($When_Raw) : ($When_Raw !== '' && $When_Raw !== '0000-00-00 00:00:00' ? $When_Raw : 'ثبت نشده');
$Platform_Raw = (string)($Row['Platform'] ?? '');
$Platform_Label = method_exists('Helper', 'formatPlatform') ? Helper::formatPlatform($Platform_Raw) : $Platform_Raw;
$Text .= "\n📱دستگاه شماره {$Number}\n"
. '👤نام کامل کاربر: ' . $Owner_Label . "\n"
. '🆔شناسه تلگرام: ' . ($Owner_Id > 0 ? '<code>' . Helper::toPersian((string)$Owner_Id) . '</code>' : 'ثبت نشده؛ منشن در دسترس نیست') . "\n"
. '💻نام دستگاه: ' . $Plain($Device_Name, 64) . "\n"
. '🖥سیستم عامل: ' . $Plain($Platform_Label, 40) . "\n"
. '🏷نسخه برنامه: ' . $Plain(Helper::toPersian((string)($Row['App_Version'] ?? '')), 40) . "\n"
. '📞شماره ثبت شده دستگاه: ' . $Plain(Helper::toPersian((string)($Row['Phone'] ?? '')), 20) . "\n"
. '🌐آخرین آی پی: ' . $Plain(Helper::toPersian((string)($Row['Last_IP'] ?? '')), 45) . "\n"
. '🕓آخرین فعالیت: ' . $Plain($When_Label, 30) . "\n"
. '🔐مجوز ورود: ' . ($Trusted ? '✅مجاز' : '⛔️غیرمجاز') . "\n➖➖➖➖➖➖➖➖➖\n";
$Prefix = substr((string)$Row['Device_ID'], 0, 32);
$Buttons[] = [[
'text' => ($Trusted ? '⛔️لغو مجوز دستگاه ' : '✅صدور مجوز دستگاه ') . $Number,
'callback_data' => 'admin_device_toggle:' . $Prefix . ':' . $Page,
]];
$Buttons[] = [Menu::button('🗑حذف دستگاه ' . $Number, 'admin_device_delete:' . (int)$Row['ID'] . ':' . $Page)];
}
$Buttons = array_merge($Buttons, Menu::pages($Page, $Page_Count, 'admin_devices_page:'));
$Buttons[] = Menu::back('منوی قبلی', 'admin_devices_menu');
$Buttons[] = Menu::adminHome();
self::logMenuProblems('app-devices', $Buttons);
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text . Helper::adminFooter(), TelegramClient::inlineKeyboard($Buttons));
}

/** Separate destructive action; confirmation is bound to a snapshot watermark. */
public static function deleteAllDevicesMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Db = Database::getInstance();
$LastId = (int)$Db->scalar('SELECT COALESCE(MAX(`ID`), 0) FROM `App_Devices`', [], 0);
$Count = (int)$Db->scalar('SELECT COUNT(*) FROM `App_Devices` WHERE `ID` <= ?', [$LastId], 0);
if ($LastId <= 0 || $Count <= 0) {
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId,
Helper::adminGreeting($Context, 'حذف همه دستگاه ها') . 'هیچ دستگاهی ثبت نشده است.' . Helper::adminFooter(),
TelegramClient::inlineKeyboard([Menu::back('منوی قبلی', 'admin_devices_menu'), Menu::adminHome()]));
return;
}
$Token = DeviceDeletion::prepareAll($Context->UserId, $Context->ChatId, $LastId);
$Text = Helper::adminGreeting($Context, 'حذف همه دستگاه ها')
. '⚠️ ' . Helper::toPersian((string)$Count) . " دستگاه ثبت شده حذف می شود. نشست ها و درخواست های ورود آن ها باطل می شود؛ اشتراک ها حذف نمی شوند. دستگاه هایی با شناسه بالاتر از محدوده فعلی حذف نمی شوند.\n"
. 'این عملیات تنها پس از تأیید نهایی انجام می شود.' . Helper::adminFooter();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard([
[Menu::button('🗑تأیید حذف همه دستگاه ها', 'admin_devices_delete_confirm:' . $Token)],
Menu::back('انصراف', 'admin_devices_delete_cancel:' . $Token), Menu::adminHome(),
]));
}

/** Preview either one row or this page's bounded batch; never delete on first tap. */
public static function deleteDevicesPrompt(Context $Context, int $Id = 0, int $Page = 0): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Page = max(0, $Page);
$Db = Database::getInstance();
if ($Id <= 0) $Page = min($Page, max(0, (int)ceil((int)$Db->scalar('SELECT COUNT(*) FROM `App_Devices`', [], 0) / 3) - 1));
$Rows = $Id > 0
? $Db->fetchAll('SELECT `ID`, `Device_Name` FROM `App_Devices` WHERE `ID` = ? LIMIT 1', [$Id])
: $Db->fetchAll('SELECT `ID`, `Device_Name` FROM `App_Devices` ORDER BY `Last_Seen_At` DESC, `ID` DESC LIMIT 3 OFFSET ?', [$Page * 3]);
if ($Rows === []) { self::appDevicesMenu($Context, $Page); return; }
$Token = DeviceDeletion::prepare($Context->UserId, $Context->ChatId, array_column($Rows, 'ID'), $Page);
$Text = Helper::adminGreeting($Context, 'تأیید حذف دستگاه')
. '⚠️حذف ' . Helper::toPersian((string)count($Rows)) . " دستگاه زیر از فهرست مدیر و کاربر:
";
foreach ($Rows as $Row) $Text .= '• ' . self::listText((string)($Row['Device_Name'] ?? 'دستگاه')) . "
";
$Text .= "
نشست ها و درخواست های ورود این دستگاه ها باطل می شوند. برای استفاده دوباره، ورود و تأیید مجدد لازم است. اشتراک کاربر حذف نمی شود.";
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[Menu::button('🗑تأیید حذف', 'admin_devices_delete_confirm:' . $Token)],
Menu::back('انصراف', 'admin_devices_delete_cancel:' . $Token), Menu::adminHome(),
]));
}

public static function deleteDevicesConfirm(Context $Context, string $Token, bool $Cancel = false): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
try {
$Result = DeviceDeletion::confirm($Context->UserId, $Context->ChatId, $Token, $Cancel);
} catch (Throwable $Error) {
error_log('[Umbrella-Bot][Device-Delete] ' . $Error->getMessage());
if ($Context->CallbackId !== null) TelegramClient::answerCallbackQuery($Context->CallbackId, '❌حذف انجام نشد؛ دوباره تلاش کنید.', true);
return;
}
if (!($Result['valid'] ?? false)) {
if ($Context->CallbackId !== null) TelegramClient::answerCallbackQuery($Context->CallbackId, '⚠️تأیید منقضی یا قبلاً استفاده شده؛ دوباره از فهرست انتخاب کنید.', true);
return;
}
if (!$Cancel) Repository::logAdminAction($Context->UserId, 'app_devices_delete', null, 'count=' . (int)$Result['count']);
if ($Context->CallbackId !== null) TelegramClient::answerCallbackQuery($Context->CallbackId, $Cancel ? 'حذف لغو شد.' : '✅تعداد دستگاه حذف شده: ' . Helper::toPersian((string)$Result['count']));
self::appDevicesMenu($Context, (int)$Result['page']);
}

private static function listText(string $Text): string {
$Text = mb_substr(trim((string)preg_replace('/[\s\p{C}]+/u', ' ', $Text)), 0, 100);
return htmlspecialchars(str_replace(['*', '`', '[', ']'], ['＊', '｀', '［', '］'], $Text !== '' ? $Text : 'ثبت نشده'), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

public static function accountUsers(Context $Context, int $Page = 0): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Db = Database::getInstance();
$Total = (int)$Db->scalar('SELECT COUNT(*) FROM `Users`', [], 0);
$Count = max(1, (int)ceil($Total / 5));
$Page = max(0, min($Page, $Count - 1));
$Users = $Db->fetchAll('SELECT `Telegram_ID`, `Full_Name`, `First_Name`, `Username`, `Is_Blocked` FROM `Users` ORDER BY `ID` DESC LIMIT ? OFFSET ?', [5, $Page * 5]);
$Text = Helper::adminGreeting($Context, 'لیست کاربران') . Menu::pageLabel($Page, $Count);
$Buttons = [];
if ($Users === []) $Text .= '📭کاربری ثبت نشده است.';
foreach ($Users as $Index => $User) {
$Id = (int)$User['Telegram_ID'];
$Name = trim((string)($User['Full_Name'] ?? '')) ?: (string)($User['First_Name'] ?? 'کاربر');
$Username = ltrim(trim((string)($User['Username'] ?? '')), '@');
$Number = Helper::toPersian((string)($Page * 5 + $Index + 1));
$Text .= "
{$Number}. " . '<a href="tg://user?id=' . $Id . '">' . self::listText($Name) . '</a>'
. "
نام کاربری: " . ($Username !== '' ? '@' . self::listText($Username) : 'ثبت نشده')
. "
شناسه: <code>" . Helper::toPersian((string)$Id) . '</code> | ' . ((int)($User['Is_Blocked'] ?? 0) === 1 ? '🚫مسدود' : '✅غیرمسدود') . "
";
$Buttons[] = [Menu::button($Number . '. ' . mb_substr((string)preg_replace('/[\s\p{C}]+/u', ' ', $Name), 0, 40), 'admin_user_view:' . $Id . ':' . $Page)];
}
$Buttons = array_merge($Buttons, Menu::pages($Page, $Count, 'admin_users_page:'), [Menu::back('حساب کاربری', 'admin_accounts_menu'), Menu::adminHome()]);
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text . Helper::adminFooter(), TelegramClient::inlineKeyboard($Buttons));
}

public static function accountUserView(Context $Context, int $Id, int $Page = 0): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$User = $Id > 0 ? Repository::getUser($Id) : null;
if (!$User) { self::accountUsers($Context, $Page); return; }
$Text = Helper::adminGreeting($Context, 'اطلاعات کاربر')
. '👤نام کامل: ' . self::listText((string)($User['Full_Name'] ?? $User['First_Name'] ?? ''))
. "
نام کاربری: " . self::listText((string)($User['Username'] ?? ''))
. "
شناسه: <code>" . Helper::toPersian((string)$Id) . '</code>'
. "
📞شماره: " . self::listText(Helper::toPersian((string)($User['Phone'] ?? '')))
. "
💎اشتراک: " . self::listText((string)($User['Subscription'] ?? ''))
. "
وضعیت کلاینت: " . self::listText((string)($User['Client_Status'] ?? ''))
. "
" . ((int)($User['Is_Blocked'] ?? 0) === 1 ? '🚫حساب مسدود است' : '✅حساب مسدود نیست');
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '👤پروفایل تلگرام', 'url' => 'tg://user?id=' . $Id]],
Menu::back('لیست کاربران', 'admin_users_page:' . max(0, $Page)), Menu::adminHome(),
]));
}

/** تغییر مجوز یک دستگاه؛ شناسه کامل به کاربر نمایش داده نمی شود. */
public static function toggleAppDevice(Context $Context, string $Device_Prefix, int $Page = 0): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Prefix = preg_replace('/[^A-Za-z0-9_-]/', '', $Device_Prefix) ?? '';
$Database = Database::getInstance();
$Matches = $Database->fetchAll(
'SELECT `Device_ID`, `User_UUID`, `Telegram_ID`, `Phone`, `Is_Trusted` FROM `App_Devices` WHERE `Device_ID` LIKE ? LIMIT 2',
[$Prefix . '%']
);
if ($Prefix === '' || count($Matches) !== 1) {
if ($Context->CallbackId !== null) TelegramClient::answerCallbackQuery($Context->CallbackId, 'دستگاه پیدا نشد؛ فهرست را تازه سازی کنید.', true);
self::appDevicesMenu($Context, $Page);
return;
}
$Device = $Matches[0];
$Device_Id = (string)$Device['Device_ID'];
$Grant = (int)$Device['Is_Trusted'] !== 1;
if ($Grant) {
$Database->execute('UPDATE `App_Devices` SET `Is_Trusted` = 1 WHERE `Device_ID` = ?', [$Device_Id]);
$Action = 'app_device_grant';
$Notice = 'مجوز دستگاه صادر شد';
}
else {
$Title = 'مجوز دستگاه لغو شد';
$Body = 'دسترسی این دستگاه به درخواست مدیر سامانه لغو شد.';
$Admin_Ids = self::administratorTelegramIds((int)$Context->UserId);
$Admin_Uuids = self::administratorClientUuids($Admin_Ids);
$Notify_Device = !self::isAdministratorDevice($Device, $Admin_Ids, $Admin_Uuids);
$Database->transaction(static function (Database $Database) use ($Device, $Device_Id, $Title, $Body, $Notify_Device): void {
if ($Notify_Device) {
$Database->execute('INSERT INTO `App_Notifications` (`User_UUID`, `Device_ID`, `Title`, `Body`, `Level`) VALUES (?, ?, ?, ?, ?)', [trim((string)($Device['User_UUID'] ?? '')) ?: null, $Device_Id, $Title, $Body, 'warning']);
}
$Database->execute('UPDATE `App_Devices` SET `Is_Trusted` = 0 WHERE `Device_ID` = ?', [$Device_Id]);
$Database->execute('UPDATE `App_Sessions` SET `Revoked_At` = CURRENT_TIMESTAMP WHERE `Device_ID` = ? AND `Revoked_At` IS NULL', [$Device_Id]);
});
$Action = 'app_device_revoke';
$Notice = 'مجوز لغو شد؛ نشست دستگاه نیز باطل شد.';
}
Repository::logAdminAction((int)$Context->UserId, $Action, (int)($Device['Telegram_ID'] ?? 0) ?: null, 'device=' . substr(hash('sha256', $Device_Id), 0, 16));
if ($Context->CallbackId !== null) TelegramClient::answerCallbackQuery($Context->CallbackId, $Notice);
self::appDevicesMenu($Context, $Page);
}

/** دسته مدیریت یا مسیر سازگار با دکمه های قدیمی. */
public static function systemMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Rows = Menu::rows([
[['💾پشتیبان گیری دیتابیس', 'پشتیبان گیری دیتابیس']],
[['🔄تنظیم مجدد دیتابیس', 'تنظیم مجدد دیتابیس']],
]);
self::categoryMenu($Context, 'مدیریت دیتابیس', $Rows, 'مدیریت');
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
. "📶*توزیع اپراتور پایه (پیش شماره، نه استعلام ترابرد):*\n"
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
Menu::back('منوی قبلی', 'منوی گزارش'), Menu::adminHome(),
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
'app_push_target' => 'اطلاع رسانی به برنامه',
'app_push_text' => 'اطلاع رسانی به برنامه',
'device_limit_target' => 'مجوز دستگاه کاربران',
'device_limit_pick' => 'مجوز دستگاه کاربران',
'update_uid' => 'بروز رسانی داده کاربران',
'version_number' => 'بروز رسانی نسخه',
'version_changes' => 'بروز رسانی نسخه',
'emergency_url' => 'تنظیمات ربات',
'ticket_reply_text' => 'مدیریت تیکت ها',
'global_filter_domains' => 'کنترل محتوا',
];

if (str_starts_with($Flow, 'cfg:')) {
$Key = substr($Flow, 4);
return (self::CFG_KEYS[$Key]['screen'] ?? '') === 'pricing' ? 'تعرفه اشتراک' : 'لینک ها و کانال';
}

return $Map[$Flow] ?? 'منوی مدیریت';
}

public static function settings(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
self::menu($Context);
}

/**
 * تنظیمات کانفیگ اضطراری که از پنل مدیریت می شوند. مقادیر فایل تنظیمات
 * همچنان به عنوان مقدار پیش فرض حفظ می شوند.
 */
public static function configMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '⚙️تنظیمات ربات در حال بارگذاری...', false);
}

$Show = BotConfig::showEmergency();
$Nowruz_Configured = BotConfig::isNowruzMenuConfigured();
$Nowruz_Show = BotConfig::isNowruzMenuEnabled();
$Text = Helper::adminGreeting($Context, 'تنظیمات ربات')
. Menu::section('🚱', 'کانفیگ اضطراری', [
'وضعیت: *' . ($Show ? '🟢روشن' : '🔴خاموش') . '*',
])
. Menu::section('🌷', 'اشتراک نوروزی', [
'تنظیم دستی: *' . ($Nowruz_Configured ? '🟢روشن' : '🔴خاموش') . '*',
'وضعیت منو اکنون: *' . ($Nowruz_Show ? '🟢نمایش داده می شود' : '🔴نمایش داده نمی شود') . '*',
'بازه نمایش: *۱ تا ۱۳ فروردین (تقویم شمسی)*',
])
. ($Show
? "ℹ️تنظیم حالت اضطراری روشن است.\n"
: "ℹ️تنظیم حالت اضطراری خاموش است.\n")
. '📌*تنظیم مورد نظر را انتخاب کنید:*' . Helper::adminFooter();
$Markup = array_merge(Menu::rows([
[['🚱روشن / خاموش کانفیگ اضطراری', 'emergency_toggle']],
[['🌷روشن / خاموش اشتراک نوروزی', 'nowruz_menu_toggle']],
]), [Menu::back('منوی قبلی', 'پیکربندی سرور'), Menu::adminHome()]);
self::logMenuProblems('settings', $Markup);

if ($Context->IsCallback && $Context->MessageId !== null) {
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Markup));
return;
}
TelegramClient::sendMessage($Context->ChatId, $Text, TelegramClient::inlineKeyboard($Markup));
}

public static function toggleNowruzMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Next = !BotConfig::isNowruzMenuConfigured();
BotConfig::setNowruzMenuEnabled($Next);

if ($Context->IsCallback && $Context->CallbackId !== null) {
$Message = !$Next
? '⛔️تنظیم منوی اشتراک نوروزی خاموش شد.'
: (BotConfig::isNowruzSeasonActive()
    ? '✅منوی اشتراک نوروزی روشن شد.'
    : '✅تنظیم روشن شد؛ منو در بازه ۱ تا ۱۳ فروردین نمایش داده می شود.');
TelegramClient::answerCallbackQuery($Context->CallbackId, $Message, false);
}

self::configMenu($Context);
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

/** Retire an input flow already open in an older bot message. */
private static function retireEmergencyUrlInput(Context $Context): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
self::configMenu($Context);
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
[Menu::back('منوی قبلی', 'admin_subscriptions_menu'), Menu::adminHome()]
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
$ChannelNotice = '';
try { BotConfig::configureChannel(BotConfig::getChannelUrl(), false); }
catch (Throwable $Error) { $ChannelNotice = '⚠️دریافت خودکار شناسه کانال انجام نشد؛ نام کاربری و دسترسی ربات را بررسی کنید.' . "\n"; }
$Channel = BotConfig::getChannelUrl() ?: 'ثبت نشده';
$Channel_Id = BotConfig::getTelegramChannelId() ?: 'ثبت نشده';
$Channel_Id_Label = Helper::toPersian($Channel_Id);
$Source_Label = static fn (string $Key): string => BotConfig::source($Key) === 'panel' ? '📝پنل' : '🌱فایل تنظیمات';
$Text = Helper::adminGreeting($Context, 'لینک ها و کانال')
. "📣*لینک پشتیبانی و کانال*\n➖➖➖➖➖➖➖➖➖\n"
. "🧑‍💻لینک پشتیبانی ({$Source_Label('Support_Url')}):\n<code>{$Support}</code>\n\n"
. "📣لینک کانال ({$Source_Label('Channel_Url')}):\n<code>{$Channel}</code>\n\n"
. "🆔شناسه کانال ({$Source_Label('Telegram_Channel_ID')}):\n<code>{$Channel_Id_Label}</code>\n\n"
. $ChannelNotice
. "ℹ️لینک پشتیبانی در دکمه های «ارتباط با پشتیبانی» و لینک کانال در دکمه عضویت کانال استفاده می شود.\n"
. Helper::adminFooter();
$Markup = array_merge(
Menu::rows([
[['✏️لینک پشتیبانی', 'cfg_set:Support_Url']],
[['✏️نام کاربری کانال', 'cfg_set:Channel_Url']],
]),
[Menu::back('منوی قبلی', 'admin_subscriptions_menu'), Menu::adminHome()]
);
self::logMenuProblems('links', $Markup);
self::renderCfgScreen($Context, $Text, $Markup);
}

/** Asks for the new value of one CFG_KEYS entry. */
public static function cfgStart(Context $Context, string $Key): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Key = trim($Key);
if ($Key === 'Telegram_Channel_ID') $Key = 'Channel_Url';

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
if ($Key === 'Telegram_Channel_ID') $Key = 'Channel_Url';

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
if ($Key === 'Channel_Url') {
try { $Id = BotConfig::configureChannel(trim($Text)); $Stored = BotConfig::getChannelUrl() . "\n🆔" . $Id; }
catch (Throwable $Exception) { $Error = 'نام کاربری کانال معتبر نیست یا دریافت شناسه از تلگرام ممکن نشد؛ تنظیمات قبلی تغییر نکرد.'; }
break;
}
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
$Stored = Helper::toPersian($Value);
break;
default:
$Error = '❓نوع مقدار ناشناخته است.';
}

if ($Error !== '') {
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "⚠️{$Error}\n➖➖➖➖➖➖➖➖➖\n🔁لطفاً مقدار درست را دوباره بفرستید." . Helper::adminFooter(), TelegramClient::inlineKeyboard(array_merge([
Common::backTo('✏️تلاش دوباره', 'cfg_set:' . $Key),
], Menu::adminNav('تنظیمات', $Meta['screen'] === 'pricing' ? 'cfg_pricing' : 'cfg_links'))));
return;
}

Repository::logAdminAction($Context->UserId, 'cfg_' . $Key, null, 'value=' . mb_substr($Stored, 0, 190), '');
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "✅«{$Meta['label']}» ثبت شد:\n<code>{$Stored}</code>" . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('تنظیمات', $Meta['screen'] === 'pricing' ? 'cfg_pricing' : 'cfg_links')));
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
case 'Telegram_Channel_ID':
$Current_Channel_Id = BotConfig::getTelegramChannelId();
return $Current_Channel_Id !== '' ? Helper::toPersian($Current_Channel_Id) : 'ثبت نشده';
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

/** دسته مدیریت یا مسیر سازگار با دکمه های قدیمی. */
public static function reportMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Rows = Menu::rows([
[['📊آمار کلی', 'آمار کلی']],
[['📅گزارش روزانه', 'گزارش روزانه']],
[['💰گزارش مالی', 'گزارش مالی']],
[['🏆رتبه بندی', 'رتبه بندی']],
]);
self::categoryMenu($Context, 'آمار و گزارشات', $Rows, 'مدیریت');
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
[['text' => '🔁تلاش مجدد', 'callback_data' => 'گزارش روزانه']],
Menu::back('منوی قبلی', 'منوی گزارش'), Menu::adminHome(),
]));
return;
}

$Text = Helper::adminGreeting($Context, 'گزارش روزانه') . $Text . Helper::adminFooter();
$Markup = TelegramClient::inlineKeyboard([
[['text' => '🔁بروزرسانی گزارش', 'callback_data' => 'گزارش روزانه']],
[['text' => '🏆رتبه بندی کاربران', 'callback_data' => 'رتبه بندی']],
Menu::back('منوی قبلی', 'منوی گزارش'), Menu::adminHome(),
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

/** دسته مدیریت یا مسیر سازگار با دکمه های قدیمی. */
public static function smsMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Rows = Menu::rows([
[['📨پیامک تکی', 'ارسال پیامک تکی اول'], ['📢پیامک همگانی', 'ارسال پیامک همگانی اول']],
[['🗣اطلاع رسانی به کاربر', 'اطلاع رسانی اول'], ['✏️اطلاع رسانی سفارشی', 'اطلاع رسانی سفارشی اول']],
[['🚫اطلاع رسانی عدم استفاده', 'اطلاع رسانی عدم استفاده']],
]);
self::categoryMenu($Context, 'پیام رسانی و اطلاع رسانی', $Rows, 'مدیریت');
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
Menu::back('منوی قبلی', 'پیکربندی سرور'), Menu::adminHome(),
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
['mieru_tcp_ports', '🔵میرو (تی سی پی)', 'tcp', 'mieru_enable'],
['wireguard_port', '🟣وایرگارد', 'udp', 'wireguard_enable'],
['amnezia_port', '🟠امنزیا وی جی', 'udp', 'amnezia_enable'],
['tuic_port', '🔴تیویک', 'udp', 'tuic_enable'],
['hysteria_port', '🟠هیستریا ۲', 'udp', 'hysteria_enable'],
['kcp_ports', '🟣کی سی پی', 'udp', 'kcp_enable'],
['mieru_udp_ports', '🔵میرو (یو دی پی)', 'udp', 'mieru_enable'],
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

foreach (['tcp' => '🔌پورت های تی سی پی', 'udp' => '🛰پورت های یو دی پی'] as $Kind => $Title) {
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
Menu::back('منوی قبلی', 'پیکربندی سرور'), Menu::adminHome(),
]));
}

/** دسته مدیریت یا مسیر سازگار با دکمه های قدیمی. */
public static function serverConfig(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Rows = Menu::rows([
[['📊وضعیت سرور', 'وضعیت سرور'], ['🔌سرویس های سرور', 'سرویس های سرور']],
[['📊بروزرسانی مصرف', 'بروز رسانی میزان استفاده اول']],
[['🚱کانفیگ اضطراری', 'تنظیمات ربات']],
]);
self::categoryMenu($Context, 'مدیریت سرور', $Rows, 'مدیریت');
}

/** دسته مدیریت یا مسیر سازگار با دکمه های قدیمی. */
public static function serverHealthMenu(Context $Context): void {
self::serverConfig($Context);
}

/** دسته مدیریت یا مسیر سازگار با دکمه های قدیمی. */
public static function serverSyncMenu(Context $Context): void {
self::serverConfig($Context);
}

/** دسته مدیریت یا مسیر سازگار با دکمه های قدیمی. */
public static function serverClientsMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Rows = Menu::rows([
[['🟢فعال سازی کلاینت', 'فعالسازی کلاینت اول'], ['🔴غیرفعال سازی کلاینت', 'غیر فعالسازی کلاینت اول']],
[['🧾بروزرسانی داده کاربران', 'بروز رسانی داده های کاربران اول']],
]);
self::categoryMenu($Context, 'مدیریت کلاینت', $Rows, 'مدیریت');
}

/** دسته مدیریت یا مسیر سازگار با دکمه های قدیمی. */
public static function databaseMenu(Context $Context): void {
self::systemMenu($Context);
}

public static function databaseBackup(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '💾در حال تهیه نسخه پشتیبان...', false);
}

$Config = Database::getConfig();
$Host = (string)($Config['host'] ?? 'localhost');
$Port = (int)($Config['port'] ?? 3306);
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
"mysqldump --default-character-set=utf8mb4 --host=%s --port=%d --user=%s --password=%s --single-transaction --routines --triggers %s > %s 2>&1",
escapeshellarg($Host),
$Port > 0 ? $Port : 3306,
escapeshellarg($User),
escapeshellarg($Pass),
escapeshellarg($Dbname),
escapeshellarg($Filepath)
);

$Output = [];
$Return_Var = 0;
exec($Command, $Output, $Return_Var);

if ($Return_Var !== 0 || !file_exists($Filepath) || filesize($Filepath) === 0) {
$Error_Raw = $Output !== [] ? implode("\n", array_slice($Output, 0, 5)) : (is_file($Filepath) ? (string)file_get_contents($Filepath, false, null, 0, 500) : '');
if (is_file($Filepath)) {
@unlink($Filepath);
}
$Error_Msg = trim($Error_Raw);
TelegramClient::sendMessage($Context->ChatId, Helper::adminGreeting($Context, 'مدیریت دیتابیس') . "❌خطا: تهیه نسخه پشتیبان ناموفق بود.\n⚠️علت: ابزار پشتیبان گیری دیتابیس با خطا مواجه شد.\n💬جزئیات: " . mb_substr($Error_Msg, 0, 200) . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔁تلاش مجدد', 'callback_data' => 'پشتیبان گیری دیتابیس']],
Menu::back('منوی قبلی', 'منوی سیستم'), Menu::adminHome(),
]));
return;
}

$Size = filesize($Filepath);
$Size_Label = Helper::formatBytes((int)$Size);
$Backup_Caption = Helper::adminGreeting($Context, 'مدیریت دیتابیس')
. "✅نسخه پشتیبان با موفقیت تهیه گردید.\n📄نام فایل: `{$Filename}`\n💾حجم: {$Size_Label}"
. Helper::adminFooter();

$Backup_Markup = TelegramClient::inlineKeyboard([
Menu::back('منوی قبلی', 'منوی سیستم'), Menu::adminHome(),
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

TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, Helper::adminGreeting($Context, 'تنظیم مجدد دیتابیس') . "⚠️هشدار: تنظیم مجدد دیتابیس\n\n⛔️این عملیات تمام جداول را حذف و مجدداً ایجاد می کند.\n🚨تمام اطلاعات کاربران، اشتراک ها، تراکنش ها و... از بین خواهند رفت.\n\n⚠️آیا از انجام این عملیات اطمینان دارید؟" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '✅بله، تنظیم مجدد انجام شود', 'callback_data' => 'تایید تنظیم مجدد دیتابیس']],
Menu::back('منوی قبلی', 'منوی سیستم'), Menu::adminHome(),
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
Menu::back('منوی قبلی', 'منوی سیستم'), Menu::adminHome(),
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
Menu::back('منوی قبلی', 'منوی سیستم'), Menu::adminHome(),
]));
}

catch (Throwable $e) {
TelegramClient::sendMessage($Context->ChatId, Helper::adminGreeting($Context, 'مدیریت دیتابیس') . "❌خطا: تنظیم مجدد دیتابیس ناموفق بود.\n⚠️علت: " . mb_substr($e->getMessage(), 0, 200) . Helper::adminFooter(), TelegramClient::inlineKeyboard([
Menu::back('منوی قبلی', 'منوی سیستم'), Menu::adminHome(),
]));
}
}

public static function userRanking(Context $Context, int $Page = 0): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🏆در حال نمایش رتبه بندی...', false);
}

try { $Live_Users = ServerClient::liveUsers(); }
catch (Throwable) { $Live_Users = []; }
$Top_Users = $Live_Users;
$Stats = ServerClient::liveServerStats($Top_Users);
$Rank_Total = (float)$Stats['total_used'];
$PageCount = max(1, (int)ceil(count($Top_Users) / 5));
$Page = max(0, min($Page, $PageCount - 1));
$Rank_Number = $Page * 5;
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

foreach (array_slice($Top_Users, $Page * 5, 5) as $User) {
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

$Ranking_Text .= Menu::pageLabel($Page, $PageCount) . Helper::adminFooter();
$Ranking_Markup = TelegramClient::inlineKeyboard(array_merge(Menu::pages($Page, $PageCount, 'admin_ranking_page:'), [
[['text' => '🔁بروزرسانی رتبه بندی', 'callback_data' => 'رتبه بندی']],
Menu::back('منوی قبلی', 'منوی گزارش'), Menu::adminHome(),
]));

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

/** دسته مدیریت یا مسیر سازگار با دکمه های قدیمی. */
public static function serverNotifyMenu(Context $Context): void {
self::smsMenu($Context);
}

public static function serverNotifyCustomStart(Context $Context): void {
self::deliveryMenu($Context, 'custom', 'اطلاع رسانی سفارشی');
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
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, Helper::adminGreeting($Context, 'عدم استفاده از سرور') . "🚫⭕️هیچ کاربر فعالی وجود ندارد که بیش از " . Helper::toPersian((string)$Threshold_Days) . " روز از آخرین اتصالش گذشته باشد." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
Menu::back('منوی قبلی', 'منوی پیامک'), Menu::adminHome(),
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
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, Helper::adminGreeting($Context, 'پیش نمایش اطلاع رسانی') . $Preview, TelegramClient::inlineKeyboard([
[['text' => '✅بله، ارسال شود', 'callback_data' => 'تایید اطلاع رسانی غیرفعال']],
Menu::back('منوی قبلی', 'منوی پیامک'), Menu::adminHome(),
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
TelegramClient::sendMessage($Context->ChatId, Helper::adminGreeting($Context, 'اطلاع رسانی به کاربران غیرفعال') . '❌خطا: لیست کاربران منقضی شده است. لطفاً مجدد اقدام کنید.' . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('اطلاع رسانی عدم استفاده', 'اطلاع رسانی عدم استفاده')));
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
. "📶<b>برای اتصال، اپلیکیشن آمبرلا را باز کنید و وارد حساب کاربری شوید.</b>\n"
. "🎁با تشکر از همراهی شما — <b>سرور آمبرلا</b>" . Helper::userFooter();

if ($Chat_ID > 0) {
$Result = TelegramClient::sendMessage($Chat_ID, $Tg_Text, TelegramClient::inlineKeyboard([
[['text' => '👤پروفایل کاربری', 'callback_data' => 'پروفایل کاربری']],
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

TelegramClient::sendMessage($Context->ChatId, Helper::adminGreeting($Context, 'اطلاع رسانی به کاربران غیرفعال') . '✅اطلاع رسانی با موفقیت انجام شد.' . "\n{$Summary}" . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('اطلاع رسانی عدم استفاده', 'اطلاع رسانی عدم استفاده')));
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
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, Helper::adminGreeting($Context, 'اطلاعات سرور') . '❌خطا: دریافت وضعیت سرور ناموفق بود.' . "\n➖➖➖➖➖➖➖➖➖\n⚠️پاسخ سرور: " . mb_substr((string)($Response['Body'] ?? ''), 0, 200) . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🔄بروز رسانی', 'callback_data' => 'وضعیت سرور']],
Menu::back('منوی قبلی', 'پیکربندی سرور'), Menu::adminHome(),
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

TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard([
[['text' => '🔄بروز رسانی', 'callback_data' => 'وضعیت سرور']],
Menu::back('منوی قبلی', 'پیکربندی سرور'), Menu::adminHome(),
]));
}

/** دسته مدیریت یا مسیر سازگار با دکمه های قدیمی. */
public static function creditMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Rows = Menu::rows([
[['➕افزایش اعتبار', 'افزایش اعتبار اول'], ['➖کسر اعتبار', 'کسر اعتبار اول']],
[['👁مشاهده اعتبار', 'مشاهده اعتبار اول']],
]);
self::categoryMenu($Context, 'مدیریت اعتبار', $Rows, 'مدیریت');
}

/** دسته مدیریت یا مسیر سازگار با دکمه های قدیمی. */
public static function crimes(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Rows = Menu::rows([
[['🚫🔒مسدود کردن کاربر', 'مسدودیت اول'], ['✅🔓رفع مسدودیت', 'رفع مسدودیت اول']],
[['👁مشاهده مسدودی ها', 'مشاهده مسدودی ها']],
]);
self::categoryMenu($Context, 'مسدودسازی کاربران', $Rows, 'مدیریت');
}

public static function blockedList(Context $Context, int $Page = 0): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

$Blocked_Users = Repository::getBlockedUsers();
$PageCount = max(1, (int)ceil(count($Blocked_Users) / 10));
$Page = max(0, min($Page, $PageCount - 1));
$Text = Helper::adminGreeting($Context, 'مشاهده مسدودی ها') . '🚫🔒*لیست کاربران مسدود شده:*' . "\n➖➖➖➖➖➖➖➖➖\n";

if (empty($Blocked_Users)) {
$Text .= '✅هیچ کاربری مسدود نشده است.';
}

else {
$Rank = $Page * 10;

foreach (array_slice($Blocked_Users, $Page * 10, 10) as $Row) {
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

$Text .= Menu::pageLabel($Page, $PageCount) . Helper::adminFooter();

TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard(array_merge(Menu::pages($Page, $PageCount, 'admin_blocked_page:'), [
Menu::back('منوی قبلی', 'جرایم'), Menu::adminHome(),
])));
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
$Flow = str_starts_with($State, 'admin:') ? substr($State, 6) : $State;
$Back_Call = match (true) {
str_starts_with($Flow, 'cfg:') => (self::CFG_KEYS[substr($Flow, 4)]['screen'] ?? '') === 'pricing' ? 'cfg_pricing' : 'cfg_links',
in_array($Flow, ['version_number', 'version_changes'], true) => 'بروز رسانی',
$Flow === 'emergency_url' => 'تنظیمات ربات',
in_array($Flow, ['credit_add_uid', 'credit_sub_uid', 'view_uid'], true) => 'اعتبار حساب کاربری',
in_array($Flow, ['block_uid', 'unblock_uid'], true) => 'جرایم',
in_array($Flow, ['activate_uid', 'deactivate_uid'], true) => 'عملیات کلاینت سرور',
in_array($Flow, ['delete_uid', 'expire_uid'], true) => 'admin_accounts_menu',
default => 'مدیریت',
};
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . $Prompt . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('منوی قبلی', $Back_Call)));
}

public static function startInputBroadcast(Context $Context, string $Mode, string $Prompt): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:notify_broadcast_text', 'Broadcast_Mode' => $Mode]);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . $Prompt . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('پیامک همگانی', 'ارسال پیامک همگانی اول')));
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
$Flow === 'admin:global_filter_domains' => self::globalContentFilterDomainsInput($Context, $Text),
$Flow === 'admin:app_push_target' => self::appPushTarget($Context, trim($Text)),
$Flow === 'admin:app_push_text' => self::appPushText($Context, $Text),
$Flow === 'admin:expire_uid' => self::manualExpire($Context, trim($Text)),
$Flow === 'admin:version_number' => self::versionNumber($Context, trim($Text)),
$Flow === 'admin:version_changes' => self::versionChanges($Context, $Text),
// Old conversations are safely retired without saving a URL.
$Flow === 'admin:emergency_url' => self::retireEmergencyUrlInput($Context),
str_starts_with($Flow, 'admin:cfg:') => self::cfgSave($Context, substr($Flow, strlen('admin:cfg:')), $Text),
$Flow === 'admin:ticket_reply_text' => self::ticketAdminReplySend($Context, trim($Text)),
default => self::unknownAdminInput($Context),
};
}

private static function unknownAdminInput(Context $Context): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "⚠️ورودی شما با هیچ عملیات در انتظاری مطابقت نداشت و نادیده گرفته شد.\n👌لطفا برای ادامه از دکمه های منو استفاده کنید." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
Menu::adminHome(),
]));
}

/**
 * پیدا کردن کاربر از شناسه یا شماره موبایل.
 *
 * `$BackTo` مقصد دکمه بازگشت به منوی قبل است. `$Back_Label` فقط برای سازگاری با
 * فراخوانی های قدیمی نگه داشته شده و دیگر استفاده نمی شود.
 */
private static function resolveTarget(Context $Context, string $Target_Input, string $BackTo = 'مدیریت', string $Back_Label = 'منوی مدیریت'): ?array {
unset($Back_Label);
$Target_Input = trim($Target_Input);

if ($Target_Input === '') {
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *❌خطا: شناسه کاربر خالی است.\n➖➖➖➖➖➖➖➖➖\n⚠️لطفا شناسه عددی کاربر یا شماره موبایل را وارد کنید." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('منوی قبلی', $BackTo)));
return null;
}

$User = Repository::findUserByIdentifier($Target_Input);

if ($User === null) {
$User = self::findUserOnServer($Target_Input);
}

if ($User === null) {
$User = self::findUserInAppDevices($Target_Input);
}

if ($User === null) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *❌خطا: کاربری با شناسه `" . Helper::toPersian($Target_Input) . "` در سیستم یافت نشد.\n➖➖➖➖➖➖➖➖➖\n⚠️دلایل ممکن: کاربر ربات را استارت نکرده، شناسه اشتباه وارد شده یا شماره موبایل در پروفایل یا کلاینت سرور ثبت نشده است." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('منوی قبلی', $BackTo)));
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

private static function phoneCandidates(string $Phone): array {
$Phone = trim($Phone);
if ($Phone === '') return [];
$Normalized = Helper::normalizePhone($Phone);
$Candidates = [$Phone];
if ($Normalized !== '') {
$Candidates[] = $Normalized;
if (str_starts_with($Normalized, '09') && strlen($Normalized) === 11) {
$WithoutZero = substr($Normalized, 1);
$Candidates[] = $WithoutZero;
$Candidates[] = '98' . $WithoutZero;
$Candidates[] = '+98' . $WithoutZero;
$Candidates[] = '0098' . $WithoutZero;
}
}
return array_values(array_unique(array_filter(array_map('trim', $Candidates), static fn(string $V): bool => $V !== '')));
}

private static function findUserInAppDevices(string $Identifier): ?array {
$Identifier = trim($Identifier);
if ($Identifier === '') return null;
try {
$Database = \Database::getInstance();
$English = Helper::toEnglish($Identifier);
$Row = null;
if (ctype_digit($English) && !str_starts_with($English, '09')) {
$Tid = (int)$English;
if ($Tid > 0) {
$Row = $Database->fetch('SELECT `ID`, `Device_ID`, `Telegram_ID`, `User_UUID`, `Phone`, `Device_Name` FROM `App_Devices` WHERE `Telegram_ID` = ? AND `Is_Trusted` = 1 ORDER BY `ID` DESC LIMIT 1', [$Tid]);
if (!is_array($Row)) {
$Row = $Database->fetch('SELECT `ID`, `Device_ID`, `Telegram_ID`, `User_UUID`, `Phone`, `Device_Name` FROM `App_Devices` WHERE `Telegram_ID` = ? ORDER BY `ID` DESC LIMIT 1', [$Tid]);
}
}
} else {
$Variants = self::phoneCandidates($English);
if ($Variants !== []) {
$Marks = implode(',', array_fill(0, count($Variants), '?'));
$Row = $Database->fetch("SELECT `ID`, `Device_ID`, `Telegram_ID`, `User_UUID`, `Phone`, `Device_Name` FROM `App_Devices` WHERE `Phone` IN ({$Marks}) AND `Is_Trusted` = 1 ORDER BY `ID` DESC LIMIT 1", $Variants);
if (!is_array($Row)) {
$Row = $Database->fetch("SELECT `ID`, `Device_ID`, `Telegram_ID`, `User_UUID`, `Phone`, `Device_Name` FROM `App_Devices` WHERE `Phone` IN ({$Marks}) ORDER BY `ID` DESC LIMIT 1", $Variants);
}
}
if (!is_array($Row)) {
$Row = $Database->fetch('SELECT `ID`, `Device_ID`, `Telegram_ID`, `User_UUID`, `Phone`, `Device_Name` FROM `App_Devices` WHERE `User_UUID` = ? OR `Device_ID` = ? ORDER BY `Is_Trusted` DESC, `ID` DESC LIMIT 1', [$English, $English]);
}
}
if (!is_array($Row)) return null;
$Tid = (int)($Row['Telegram_ID'] ?? 0);
if ($Tid > 0) {
$Existing = Repository::getUser($Tid);
if ($Existing !== []) {
if (empty($Existing['Client_ID']) || $Existing['Client_ID'] === '_') {
$Existing['Client_ID'] = (string)($Row['User_UUID'] ?? '');
}
if (empty($Existing['Phone']) && !empty($Row['Phone'])) {
$Existing['Phone'] = (string)$Row['Phone'];
}
return $Existing;
}
}
return [
'Telegram_ID' => $Tid,
'Chat_ID' => $Tid,
'Full_Name' => trim((string)($Row['Device_Name'] ?? '')) ?: 'کاربر برنامه',
'Phone' => (string)($Row['Phone'] ?? ''),
'Client_ID' => (string)($Row['User_UUID'] ?? ''),
'Device_ID' => (string)($Row['Device_ID'] ?? ''),
'App_Device_Row_ID' => (int)($Row['ID'] ?? 0),
];
} catch (Throwable) {
return null;
}
}

public static function versionNumber(Context $Context, string $Version): void {
$Version = str_replace('٫', '.', trim(Helper::toEnglish($Version)));

if (!preg_match('/^\d+\.\d+\.\d+$/', $Version)) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "❌فرمت نسخه نامعتبر است.\n➖➖➖➖➖➖➖➖➖\n⚠️مثال صحیح: `۱.۰.۰`\n🔁لطفا شماره نسخه را با فرمت درست وارد کنید.\n👇مثلا `۱.۰.۱`" . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('بروز رسانی', 'بروز رسانی')));
return;
}

BotConfig::setRobotVersion($Version);
Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:version_changes']);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "✅نسخه `" . Helper::toPersian($Version) . "` ثبت شد.\n\n👌حالا تغییرات این نسخه را وارد کنید." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('بروز رسانی', 'بروز رسانی')));
}

private static function versionChanges(Context $Context, string $Changes): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
Repository::setSetting('Robot_Changes', $Changes);
$Version = BotConfig::robotVersion();

TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *✅ربات با موفقیت به نسخه `" . Helper::toPersian($Version) . "` بروزرسانی گردید." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('بروز رسانی', 'بروز رسانی')));

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
$Status_Text = $Status_Code > 0 ? 'کد وضعیت ' . Helper::toPersian((string)$Status_Code) : 'خطا در ارتباط';
TelegramClient::sendSystemMessage($Admin, Helper::adminGreetingNamed((string)(Repository::getSetting('Admin_Full_Name') ?: Environment::getAdminFullName()), 'خطای سرور', $Admin) . "❌خطای سرور در عملیات: {$Operation}\n\n"
. "👤کاربر: {$Name}\n"
. "🆔آیدی: `" . Helper::toPersian($User_ID) . "`\n"
. "📡وضعیت: {$Status_Text}\n"
. "⚠️پاسخ: " . mb_substr($Error, 0, 500) . "\n"
. "➖➖➖➖➖➖➖➖➖\n"
. Helper::adminFooter());
}

private static function creditStep(Context $Context, string $Flow, string $Text, bool $Add): void {
$Start_Call = $Add ? 'افزایش اعتبار اول' : 'کسر اعتبار اول';

if (str_ends_with($Flow, '_uid')) {
$User = self::resolveTarget($Context, $Text, $Start_Call, 'کاربران و اعتبار');

if ($User === null) {
return;
}

$Target = (int)($User['Telegram_ID'] ?? 0);
Repository::updateUserSession($Context->UserId, ['Temp_UID' => $Target]);
Repository::updateUserSession($Context->UserId, ['Flow' => $Add ? 'admin:credit_add_amount' : 'admin:credit_sub_amount']);
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "👌مبلغ اعتبار به تومان برای کاربر {$Name} را وارد کنید." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('اعتبار کاربر', $Start_Call)));
return;
}

$Amount = (float)(preg_replace('/[^0-9.]/', '', str_replace('٫', '.', Helper::toEnglish($Text))) ?? '0');
$Target = (int)(Repository::getUserSession($Context->UserId)['Temp_UID'] ?? 0);
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
Repository::updateUserSession($Context->UserId, ['Temp_UID' => null]);

if ($Target <= 0 || $Amount <= 0) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "❌خطا: مبلغ وارد شده معتبر نمی باشد.\n➖➖➖➖➖➖➖➖➖\n⚠️لطفا یک مبلغ صحیح به تومان وارد کنید." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('اعتبار کاربر', $Start_Call)));
return;
}

$Amount_Persian = Helper::formatCurrency($Amount);
$User = Repository::getUser($Target);
$Name = self::targetDisplayName($Target, $User);

if ($Add) {
Repository::addMoney($Target, $Amount);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *💰مبلغ {$Amount_Persian} اعتبار حساب کاربری کاربر {$Name} با موفقیت شارژ گردید.\n➖➖➖➖➖➖➖➖➖\n💳اعتبار کنونی: " . Helper::formatCurrency(Repository::getBalance($Target)) . "*" . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('اعتبار کاربر', $Start_Call)));

$User_Notify = TelegramClient::sendSystemMessage($Target, Helper::frame('کاربر', $Name, 'اعتبار حساب کاربری', $Target) . "💳لحظاتی پیش مبلغ {$Amount_Persian} اعتبار حساب کاربری شما توسط مدیریت شارژ گردید.\n\n➖➖➖➖➖➖➖➖➖\n🌎ارز کنونی:🇮🇷ایران - تومان\n💳اعتبار کنونی:" . Helper::formatCurrency(Repository::getBalance($Target)) . Helper::userFooter(), TelegramClient::inlineKeyboard([Menu::userHome()]));

if (!($User_Notify['ok'] ?? false)) {
error_log("[Umbrella-Bot][CreditNotify] User {$Target} notification failed: " . json_encode($User_Notify));
}

return;
}

if (!Repository::removeMoney($Target, $Amount)) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *❌خطا: اعتبار حساب کاربری کاربر {$Name} برای کسر این مبلغ کافی نمی باشد.\n\n🌏ارز کنونی کاربر:🇮🇷ایران - تومان\n💳اعتبار کنونی کاربر:" . Helper::formatCurrency(Repository::getBalance($Target)) . "*" . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('اعتبار کاربر', $Start_Call)));
return;
}

TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *💳مبلغ {$Amount_Persian} اعتبار حساب کاربری کاربر {$Name} با موفقیت کسر گردید. ✅" . "*" . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('اعتبار کاربر', $Start_Call)));
$User_Notify = TelegramClient::sendSystemMessage($Target, Helper::frame('کاربر', $Name, 'اعتبار حساب کاربری', $Target) . "💳لحظاتی پیش مبلغ {$Amount_Persian} اعتبار حساب کاربری شما توسط مدیریت کسر گردید.\n\n➖➖➖➖➖➖➖➖➖\n🌎ارز کنونی:🇮🇷ایران - تومان\n💳اعتبار کنونی:" . Helper::formatCurrency(Repository::getBalance($Target)) . Helper::userFooter(), TelegramClient::inlineKeyboard([Menu::userHome()]));

if (!($User_Notify['ok'] ?? false)) {
error_log("[Umbrella-Bot][CreditNotify] User {$Target} notification failed: " . json_encode($User_Notify));
}
}

private static function showCredit(Context $Context, string $Target_Input): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$User = self::resolveTarget($Context, $Target_Input, 'مشاهده اعتبار اول');

if ($User === null) {
return;
}

$Target = (int)($User['Telegram_ID'] ?? 0);
$Balance = Helper::formatCurrency(Repository::getBalance($Target));
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *💳اعتبار حساب کاربر {$Name} بدین شرح است.\n\n🌏ارز کنونی:🇮🇷ایران - تومان\n💳اعتبار کنونی:{$Balance}" . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('مشاهده اعتبار', 'مشاهده اعتبار اول')));
}

private static function blockUser(Context $Context, string $Target_Input, bool $Block): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$Start_Call = $Block ? 'مسدودیت اول' : 'رفع مسدودیت اول';
$User = self::resolveTarget($Context, $Target_Input, $Start_Call, 'مسدودیت کاربران');

if ($User === null) {
return;
}

$Target = (int)($User['Telegram_ID'] ?? 0);
$Is_Blocked = (bool)($User['Is_Blocked'] ?? false);

if ($Block && $Is_Blocked) {
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "⛔️*کاربر {$Name} در حال حاضر مسدود است.*\n⏳تا زمان رفع مسدودی، امکان فعالسازی کلاینت و خرید اشتراک وجود ندارد." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('مسدودیت کاربر', $Start_Call)));
return;
}

if (!$Block && !$Is_Blocked) {
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "✅*کاربر {$Name} در حال حاضر مسدود نیست.*\nℹ️برای مسدود کردن او، از بخش «مسدود کردن کاربر» استفاده کنید." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('رفع مسدودیت', $Start_Call)));
return;
}

Repository::setBlocked($Target, $Block);
$Action = $Block ? 'مسدود' : 'آزاد';
$Name = self::targetDisplayName($Target, $User);
$Action_Mark = $Block ? '⛔️' : '🔓';
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *{$Action_Mark}کاربر {$Name} با موفقیت {$Action} گردید." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('مسدودیت کاربران', $Start_Call)));

TelegramClient::sendSystemMessage($Target, Helper::frame('کاربر', $Name, 'وضعیت حساب کاربری', $Target) . ($Block ? "⛔️با عرض پوزش شما به طور دائمی مسدود شده اید.\n\n➖➖➖➖➖➖➖➖➖\n⚠️نکته:اگر فکر می کنید اشتباهی رخ داده است به پشتیبانی مراجعه کنید." . Helper::userFooter() . "*" : "✅🔓مسدودیت شما رفع گردید. خوش آمدید!") . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '📞🧑‍💻ارتباط با پشتیبانی (آرمین سافت)', 'url' => BotConfig::getSupportUrl()]],
Menu::userHome(),
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
$Start_Call = $Activate ? 'فعالسازی کلاینت اول' : 'غیر فعالسازی کلاینت اول';
$User = self::resolveTarget($Context, $Target_Input, $Start_Call, 'عملیات کلاینت سرور');

if ($User === null) {
return;
}

$Target = (int)($User['Telegram_ID'] ?? 0);
Repository::updateUserSession($Context->UserId, ['Temp_UID' => $Target]);
$Client_ID = (string)($User['Client_ID'] ?? '');

if ($Client_ID === '' || $Client_ID === '_') {
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *❌خطا: شناسه کلاینت برای کاربر {$Name} ثبت نشده است.\n➖➖➖➖➖➖➖➖➖\n⚠️دلیل: این کاربر هنوز اشتراک فعالی ندارد یا کلاینت سرور برای او ایجاد نشده است." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('کلاینت سرور', $Start_Call)));
return;
}

$Is_Currently_Active = self::clientIsActive($Client_ID, $User);

if ($Activate && $Is_Currently_Active) {
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *⚠️کلاینت کاربر {$Name} از قبل در سرور فعال است.\n➖➖➖➖➖➖➖➖➖\nℹ️نیازی به فعالسازی مجدد نیست." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('کلاینت سرور', $Start_Call)));
return;
}

if (!$Activate && !$Is_Currently_Active) {
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *⚠️کلاینت کاربر {$Name} از قبل در سرور غیرفعال است.\n➖➖➖➖➖➖➖➖➖\nℹ️نیازی به غیرفعالسازی مجدد نیست." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('کلاینت سرور', $Start_Call)));
return;
}

$Payload = ['is_active' => $Activate, 'enable' => $Activate];
$Response = ServerClient::updateUser($Client_ID, $Payload);

if (($Response['StatusCode'] ?? 0) >= 300) {
$Error = $Response['Body'] ?? 'خطا در ارتباط با سرور';
$Name = self::targetDisplayName($Target, $User);
self::notifyAdminServerError($Activate ? 'فعالسازی کلاینت' : 'غیرفعالسازی کلاینت', $Target, $Name, $Response['StatusCode'] ?? 0, $Error);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *❌خطا: به روزرسانی کلاینت کاربر {$Name} روی سرور ناموفق بود.\n➖➖➖➖➖➖➖➖➖\n⚠️پاسخ سرور: " . mb_substr($Error, 0, 200) . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('کلاینت سرور', $Start_Call)));
return;
}

if ($Activate) {
Repository::updateUser($Target, [
'Client_Status' => '✅فعال',
'Server_Is_Active' => 1,
'Server_Enable' => 1,
'Deactivation_Message' => null,
'Channel_Client_Disabled_At' => null,
]);
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *✅کلاینت کاربر {$Name} در سرور فعال گردید." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('فعالسازی کلاینت', 'فعالسازی کلاینت اول')));

$Full_Name = (string)($User['Full_Name'] ?? 'کاربر');
TelegramClient::sendSystemMessage($Target, Helper::frame('کاربر', $Full_Name, 'فعالسازی کلاینت', $Target) . "✅🔓کلاینت شما در سرور فعال گردید.\n\n➖➖➖➖➖➖➖➖➖\n⚠️📋نکته: قوانین مانیتورینگ سرور را رعایت فرمایید." . Helper::userFooter() . "*", TelegramClient::inlineKeyboard([
[['text' => '👤پروفایل کاربری', 'callback_data' => 'پروفایل کاربری']],
Menu::userHome()
]));

$Phone = (string)(Repository::getUser($Target)['Phone'] ?? '');

if (Helper::validatePhone($Phone)) {
IppanelClient::send($Target, $Phone, "{$Full_Name} گرامی کلاینت شما در سرور فعال گردید.\nنکته:قوانین مانیتورینگ سرور را رعایت فرمایید.\n\nسرور آمبرلا");
}

return;
}

Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:deactivate_msg']);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "👌متن غیرفعالسازی کلاینت را وارد کنید." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('غیرفعالسازی کلاینت', 'غیر فعالسازی کلاینت اول')));
}

private static function clientDeactivateMessage(Context $Context, string $Message): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$Target = (int)(Repository::getUserSession($Context->UserId)['Temp_UID'] ?? 0);
Repository::updateUserSession($Context->UserId, ['Temp_UID' => null]);

if ($Target <= 0) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'غیرفعالسازی کلاینت') . '❌شناسه کاربر معتبر نیست؛ دوباره تلاش کنید.' . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('غیرفعالسازی کلاینت', 'غیر فعالسازی کلاینت اول')));
return;
}

$Client_ID = (string)(Repository::getUser($Target)['Client_ID'] ?? '');

if ($Client_ID !== '' && $Client_ID !== '_') {
$Response = ServerClient::updateUser($Client_ID, ['is_active' => false, 'enable' => false]);

if (($Response['StatusCode'] ?? 0) >= 300) {
$Name = self::targetDisplayName($Target, Repository::getUser($Target));
self::notifyAdminServerError('غیرفعالسازی کلاینت', $Target, $Name, $Response['StatusCode'] ?? 0, (string)($Response['Body'] ?? ''));
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *❌خطا: غیرفعالسازی کلاینت در سرور ناموفق بود.\n➖➖➖➖➖➖➖➖➖\n⚠️پاسخ سرور: " . mb_substr((string)($Response['Body'] ?? ''), 0, 200) . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('غیرفعالسازی کلاینت', 'غیر فعالسازی کلاینت اول')));
return;
}
}

Repository::updateUser($Target, [
'Client_Status' => '🚫غیر فعال',
'Server_Is_Active' => 0,
'Server_Enable' => 0,
'Deactivation_Message' => $Message,
'Channel_Client_Disabled_At' => null,
]);
Repository::addSubscriptionLog($Target, 'deactivate', null, null, null, $Message, 'admin', $Context->UserId);
$User = Repository::getUser($Target);
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *🚫کلاینت کاربر {$Name} در سرور غیرفعال گردید." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('غیرفعالسازی کلاینت', 'غیر فعالسازی کلاینت اول')));

$Full_Name = (string)($User['Full_Name'] ?? 'کاربر');
TelegramClient::sendSystemMessage($Target, Helper::frame('کاربر', $Full_Name, 'غیرفعالسازی کلاینت', $Target) . "🚫کلاینت شما در سرور غیرفعال گردید.\n\n➖➖➖➖➖➖➖➖➖\n⚠️علت: {$Message}" . Helper::userFooter(), TelegramClient::inlineKeyboard([
Common::backTo('👤پروفایل کاربری', 'پروفایل کاربری'),
Menu::userHome(),
]));
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
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "❌خطا: کاربری برای حذف انتخاب نشده است.\n➖➖➖➖➖➖➖➖➖\n⚠️ابتدا از بخش «حذف کاربر از سرور» شناسه عددی یا شماره موبایل کاربر را وارد کنید." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('حذف کاربر', 'حذف کاربر اول')));
return;
}

self::deleteUser($Context, (string)$Target);
}

private static function deleteUser(Context $Context, string $Target_Input): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$User = self::resolveTarget($Context, $Target_Input, 'حذف کاربر اول', 'عملیات کلاینت سرور');

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
TelegramClient::sendMessage($Context->ChatId, Helper::adminGreeting($Context, 'حذف کاربر از سرور') . "❌خطا: کاربر {$Name} قبلاً حذف شده است.\n➖➖➖➖➖➖➖➖➖\n⚠️این کاربر در سیستم ثبت نشده است." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('حذف کاربر', 'حذف کاربر اول')));
return;
}

$Name = self::targetDisplayName($Target, $User);
Repository::updateUser($Target, [
'Full_Name' => null, 'Operator' => null, 'Phone' => null, 'Client_ID' => '_',
'Client_Status' => null, 'Server_Is_Active' => 0, 'Server_Enable' => 0,
'Deactivation_Message' => null, 'Channel_Client_Disabled_At' => null,
'Last_Online' => null, 'Server_Comment' => null, 'Profile_Updated_At' => null,
'Package_Duration' => null, 'Package_Start_Date' => null, 'Total_Usage_GB' => null,
'Used_Usage_GB' => null, 'Remaining_Usage_GB' => null, 'Percent_Usage' => null,
'Subscription' => null, 'Expiration_Date' => null, 'Expiration_Time_Stamp' => null,
'ED_25519_Private_Key' => null, 'ED_25519_Public_Key' => null,
'WireGuard_Private_Key' => null, 'WireGuard_Public_Key' => null, 'WireGuard_PSK' => null,
]);

TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *✅اطلاعات ربات برای کاربر {$Name} پاک شد.\n➖➖➖➖➖➖➖➖➖\n⚠️توجه: کاربر می تواند دوباره اشتراک جدید خریداری کند*" . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('حذف کاربر', 'حذف کاربر اول')));

$User_Notify = TelegramClient::sendSystemMessage($Target, Helper::frame('کاربر', $Name, 'حذف اطلاعات کاربری', $Target) . "✅اطلاعات حساب کاربری شما توسط مدیریت پاک شد.\n➖➖➖➖➖➖➖➖➖\n⚠️در صورت تمایل می توانید دوباره اشتراک خریداری کنید." . Helper::userFooter(), TelegramClient::inlineKeyboard([Menu::userHome()]));

if (!($User_Notify['ok'] ?? false)) {
error_log("[Umbrella-Bot][ClearNotify] User {$Target} notification failed: " . json_encode($User_Notify));
}

return;
}

$Delete_Response = ServerClient::deleteUser($Client_ID);
$Delete_Status = (int)($Delete_Response['StatusCode'] ?? 0);
$Panel_Already_Missing = $Delete_Status === 404;

// A 404 is an idempotent delete: the remote account is already absent, so
// still clear its local bot profile and revoke any app sessions. Other
// non-2xx responses (including transport failures with status 0) must not
// discard local data while the panel's state is uncertain.
if (!$Panel_Already_Missing && ($Delete_Status < 200 || $Delete_Status >= 300)) {
$Delete_Error = trim((string)($Delete_Response['Body'] ?? ''));
if ($Delete_Error === '') $Delete_Error = trim((string)($Delete_Response['Error'] ?? ''));
if ($Delete_Error === '') $Delete_Error = 'خطا در ارتباط با سرور';
$Name = self::targetDisplayName($Target, $User);
self::notifyAdminServerError('حذف کاربر', $Target, $Name, $Delete_Status, $Delete_Error);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . "❌خطا: حذف کاربر {$Name} از سرور ناموفق بود.\n➖➖➖➖➖➖➖➖➖\n⚠️پاسخ سرور: " . mb_substr($Delete_Error, 0, 200) . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('حذف کاربر', 'حذف کاربر اول')));
return;
}

if (!AppAccountRevocation::revoke($Client_ID)) {
error_log('[Umbrella-Bot][App-Account-Revocation] failed after deleting panel user ' . $Target);
}

Repository::updateUser($Target, [
'Full_Name' => null, 'Operator' => null, 'Phone' => null, 'Client_ID' => null,
'Client_Status' => '🚫حذف شده', 'Server_Is_Active' => 0, 'Server_Enable' => 0,
'Deactivation_Message' => null, 'Channel_Client_Disabled_At' => null,
'Last_Online' => null, 'Server_Comment' => null, 'Profile_Updated_At' => null,
'Package_Duration' => null, 'Package_Start_Date' => null, 'Total_Usage_GB' => null,
'Used_Usage_GB' => null, 'Remaining_Usage_GB' => null, 'Percent_Usage' => null,
'Subscription' => null, 'Expiration_Date' => null, 'Expiration_Time_Stamp' => null,
'ED_25519_Private_Key' => null, 'ED_25519_Public_Key' => null,
'WireGuard_Private_Key' => null, 'WireGuard_Public_Key' => null, 'WireGuard_PSK' => null,
]);

$Name = self::targetDisplayName($Target, $User);
$Target_Chat_ID = (int)($User['Chat_ID'] ?? $User['Telegram_ID'] ?? 0);

if ($Target_Chat_ID > 0) {
TelegramClient::sendSystemMessage($Target_Chat_ID,
Helper::frame('کاربر', $Name, 'حذف اشتراک', $Target) . "🚫اشتراک شما توسط مدیریت حذف گردید.\n" .
"➖➖➖➖➖➖➖➖➖\n" .
"⚠️در صورت نیاز می توانید مجدداً از طریق ربات اقدام به خرید اشتراک نمایید.\n" .
Helper::userFooter(),
TelegramClient::inlineKeyboard([
Menu::userHome(),
])
);
}

$Delete_Summary = $Panel_Already_Missing
? "ℹ️کاربر {$Name} در پنل سرور وجود نداشت؛ اطلاعات حساب از دیتابیس ربات پاک شد."
: "👤کاربر {$Name} با شناسه کلاینت {$Client_ID} با موفقیت از پنل سرور و دیتابیس ربات حذف گردید.";

TelegramClient::sendMessage($Context->ChatId,
self::header($Context) . $Delete_Summary .
Helper::adminFooter(),
TelegramClient::inlineKeyboard(Menu::adminNav('حذف کاربر', 'حذف کاربر اول'))
);
}

private static function notifyUidStep(Context $Context, string $UidText): void {
$User = self::resolveTarget($Context, $UidText, 'اطلاع رسانی اول', 'اطلاع رسانی به کاربر');

if ($User === null) {
return;
}

$Session = Repository::getUserSession($Context->UserId);
$Mode = (string)($Session['Broadcast_Mode'] ?? 'both');

if (!in_array($Mode, ['telegram', 'sms', 'app', 'all', 'both'], true)) {
$Mode = 'both';
}

$Target = (int)($User['Telegram_ID'] ?? 0);
$DeviceRowId = (int)($User['App_Device_Row_ID'] ?? 0);
$HasPhone = Helper::validatePhone((string)($User['Phone'] ?? ''));
$HasAppTarget = $DeviceRowId > 0
|| (trim((string)($User['Client_ID'] ?? '')) !== '' && trim((string)($User['Client_ID'] ?? '')) !== '_')
|| $HasPhone;

if ($Target <= 0) {
if ($Mode === 'telegram' || !$HasAppTarget) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'اطلاع رسانی به کاربر') . "❌خطا: شناسه تلگرام معتبر برای این کاربر ثبت نشده است." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('اطلاع رسانی', 'اطلاع رسانی اول')));
return;
}
if ($DeviceRowId <= 0) {
$FoundDev = self::findUserInAppDevices((string)($User['Phone'] ?? ($User['Client_ID'] ?? '')));
$DeviceRowId = (int)($FoundDev['App_Device_Row_ID'] ?? 0);
}
if ($DeviceRowId <= 0) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'اطلاع رسانی به کاربر') . "❌خطا: شناسه یا دستگاه معتبری برای این کاربر یافت نشد." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('اطلاع رسانی', 'اطلاع رسانی اول')));
return;
}
$Target = -$DeviceRowId;
}

$Mode_Label = self::deliveryModeLabel($Mode);

Repository::updateUserSession($Context->UserId, ['Temp_UID' => $Target, 'Flow' => 'admin:notify_text', 'Broadcast_Mode' => $Mode]);
$Name = $Target > 0 ? self::targetDisplayName($Target, $User) : trim((string)($User['Full_Name'] ?? 'کاربر برنامه'));
$TargetTag = $Target > 0 ? Helper::toPersian((string)$Target) : Helper::toPersian((string)($User['Phone'] ?? 'کاربر برنامه'));
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'اطلاع رسانی به کاربر') . "👌متن اطلاع رسانی ({$Mode_Label}) برای کاربر {$Name} را وارد کنید.\n🎯شناسه: `" . $TargetTag . "`" . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('اطلاع رسانی', 'اطلاع رسانی اول')));
}

private static function notifyUser(Context $Context, string $Message): void {
self::sendSingleMessage($Context, $Message, 'اطلاع رسانی اول');
}

/** چهار روش مشترک برای پیام تکی، همگانی و اطلاع رسانی. */
private static function deliveryMenu(Context $Context, string $Scope, string $Title): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Temp_UID' => null, 'Broadcast_Mode' => null]);
$Rows = [];
foreach (['telegram' => '📨تلگرام', 'sms' => '📱پیامک', 'app' => '💻نرم افزار/ اپلیکیشن', 'all' => '📣همه موارد'] as $Mode => $Label) {
$Rows[] = [Menu::button($Label, 'delivery_mode:' . $Scope . ':' . $Mode)];
}
$Rows[] = Menu::back('منوی قبلی', 'منوی پیامک');
$Rows[] = Menu::adminHome();
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, self::header($Context, $Title) . '📨روش ارسال را انتخاب کنید:' . Helper::adminFooter(), TelegramClient::inlineKeyboard($Rows));
}

public static function selectDeliveryMode(Context $Context, string $Scope, string $Mode): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
if (!in_array($Mode, ['telegram', 'sms', 'app', 'all'], true)) return;
if ($Scope === 'single') { self::startInputSingleSmsUid($Context, $Mode); return; }
if ($Scope === 'notify') { self::startInputNotifyUid($Context, $Mode); return; }
if (!in_array($Scope, ['broadcast', 'custom'], true)) return;
Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:notify_broadcast_text', 'Broadcast_Mode' => $Mode, 'Temp_UID' => null]);
$Parent = $Scope === 'custom' ? 'اطلاع رسانی سفارشی اول' : 'ارسال پیامک همگانی اول';
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, self::header($Context, 'ارسال پیام') . '📝متن پیام (' . self::deliveryModeLabel($Mode) . ') را بفرستید.' . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('روش ارسال', $Parent)));
}

private static function deliveryModeLabel(string $Mode): string {
return match ($Mode) { 'telegram' => 'تلگرام', 'sms' => 'پیامک', 'app' => 'نرم افزار/ اپلیکیشن', 'all' => 'همه موارد', 'both' => 'تلگرام و پیامک', default => 'نامعتبر' };
}

/** شکست یک روش، ارسال روش های دیگر را متوقف نمی کند. برنامه فقط صف می شود. */
private static function deliverMessage(array $User, string $Message, string $Mode, int $AdminId): array {
$Result = [];
$UserId = (int)($User['Telegram_ID'] ?? 0);
$Phone = (string)($User['Phone'] ?? '');
$ClientId = trim((string)($User['Client_ID'] ?? ''));
$DeviceId = trim((string)($User['Device_ID'] ?? ''));
$HasTarget = $UserId > 0
|| Helper::validatePhone($Phone)
|| ($ClientId !== '' && $ClientId !== '_')
|| $DeviceId !== '';
if (!$HasTarget) return $Result;
foreach (['telegram', 'sms', 'app'] as $Channel) {
$Selected = $Mode === $Channel || $Mode === 'all' || ($Mode === 'both' && $Channel !== 'app');
if (!$Selected) continue;
$Ok = false;
try {
if ($Channel === 'telegram' && (int)($User['Chat_ID'] ?? 0) > 0) {
$Response = TelegramClient::sendMessage((int)$User['Chat_ID'], Helper::frame('کاربر', (string)($User['Full_Name'] ?? 'کاربر'), 'اطلاع رسانی', $UserId) . "\n📨" . $Message . Helper::userFooter(), TelegramClient::inlineKeyboard([Menu::userHome()]));
$Ok = ($Response['ok'] ?? false) === true;
} elseif ($Channel === 'sms' && Helper::validatePhone($Phone)) {
$Ok = IppanelClient::send($UserId > 0 ? $UserId : max(0, (int)($User['App_Device_Row_ID'] ?? 0)), $Phone, $Message) === true;
} elseif ($Channel === 'app') {
$Ok = self::queueAppPush($UserId, $Message, $AdminId, true, $User) > 0;
}
} catch (Throwable $Error) {
error_log('[Umbrella-Bot][Delivery-' . $Channel . '] user=' . $UserId . ' ' . $Error->getMessage());
}
$Result[$Channel] = $Ok;
}
return $Result;
}

private static function sendSingleMessage(Context $Context, string $Message, string $Parent): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Session = Repository::getUserSession($Context->UserId);
$Mode = (string)($Session['Broadcast_Mode'] ?? 'telegram');
$Target = (int)($Session['Temp_UID'] ?? 0);
if (trim($Message) === '') {
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . '⚠️متن پیام خالی است؛ دوباره بفرستید.', TelegramClient::inlineKeyboard(Menu::adminNav('روش ارسال', $Parent)));
return;
}
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Temp_UID' => null, 'Broadcast_Mode' => null]);
$User = [];
if ($Target > 0) {
$User = Repository::getUser($Target);
if ($User === []) {
$User = self::findUserInAppDevices((string)$Target) ?? [];
}
} elseif ($Target < 0) {
$User = self::appDeviceUserByRowId(-$Target) ?? [];
}
$Results = self::deliverMessage($User, $Message, $Mode, $Context->UserId);
$Summary = $Results === [] ? '❌کاربر در سیستم یافت نشد یا روش ارسال معتبر نیست.' : '📋نتیجه ارسال:';
foreach ($Results as $Channel => $Ok) {
if ($Ok) {
$Summary .= "\n✅" . self::deliveryModeLabel($Channel) . ': ' . ($Channel === 'app' ? 'در صف دریافت برنامه ثبت شد' : 'ارسال موفق');
} elseif ($Channel === 'app') {
$Summary .= "\n❌" . self::deliveryModeLabel($Channel) . ': ' . self::appDeliveryFailureReason((int)($User['Telegram_ID'] ?? max(0, $Target)), $Context->UserId, $User);
} else {
$Summary .= "\n❌" . self::deliveryModeLabel($Channel) . ': ارسال نشد؛ مشخصات مخاطب و تنظیمات سرویس را بررسی کنید';
}
}
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'نتیجه ارسال') . $Summary . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('روش ارسال', $Parent)));
}

private static function appDeviceUserByRowId(int $RowId): ?array {
if ($RowId <= 0) return null;
try {
$Row = \Database::getInstance()->fetch(
'SELECT `ID`, `Device_ID`, `Telegram_ID`, `User_UUID`, `Phone`, `Device_Name` FROM `App_Devices` WHERE `ID` = ? LIMIT 1',
[$RowId]
);
if (!is_array($Row)) return null;
$Tid = (int)($Row['Telegram_ID'] ?? 0);
return [
'Telegram_ID' => $Tid,
'Chat_ID' => $Tid,
'Full_Name' => trim((string)($Row['Device_Name'] ?? '')) ?: 'کاربر برنامه',
'Phone' => (string)($Row['Phone'] ?? ''),
'Client_ID' => (string)($Row['User_UUID'] ?? ''),
'Device_ID' => (string)($Row['Device_ID'] ?? ''),
'App_Device_Row_ID' => (int)($Row['ID'] ?? $RowId),
];
} catch (Throwable) {
return null;
}
}

private static function appDeliveryFailureReason(int $Target_Telegram_ID, int $Admin_ID, ?array $User_Context = null, bool $Allow_Admin = false): string {
$User = $Target_Telegram_ID > 0 ? Repository::getUser($Target_Telegram_ID) : ($User_Context ?? []);
if ($User === [] && is_array($User_Context)) $User = $User_Context;

$Client_ID = trim((string)($User['Client_ID'] ?? ($User_Context['Client_ID'] ?? '')));
$Phone = trim((string)($User['Phone'] ?? ($User_Context['Phone'] ?? '')));
$Device_ID = trim((string)($User['Device_ID'] ?? ($User_Context['Device_ID'] ?? '')));

if ($Target_Telegram_ID <= 0 && $Client_ID === '' && $Phone === '' && $Device_ID === '') {
return 'شناسه کاربر نامعتبر است';
}
if (!$Allow_Admin && $Target_Telegram_ID > 0) {
$Admin_Ids = self::administratorTelegramIds($Admin_ID);
if (in_array($Target_Telegram_ID, $Admin_Ids, true)) {
return 'برای حساب مدیریت ارسال نمی شود (حساب مدیر اعلان برنامه دریافت نمی کند؛ برای آزمایش شناسه یک کاربر عادی را وارد کنید)';
}
$Admin_Uuids = self::administratorClientUuids($Admin_Ids);
if ($Client_ID !== '' && in_array($Client_ID, $Admin_Uuids, true)) {
return 'شناسه سرویس این کاربر متعلق به حساب مدیریت است';
}
}
try {
$Database = \Database::getInstance();
$Count = $Target_Telegram_ID > 0
? count($Database->fetchAll('SELECT `Device_ID`, `Telegram_ID`, `User_UUID` FROM `App_Devices` WHERE `Telegram_ID` = ? AND `Is_Trusted` = 1', [$Target_Telegram_ID]))
: 0;
if ($Count === 0 && $Client_ID !== '' && $Client_ID !== '_') {
$Count = count($Database->fetchAll('SELECT `Device_ID`, `Telegram_ID`, `User_UUID` FROM `App_Devices` WHERE `User_UUID` = ? AND `Is_Trusted` = 1', [$Client_ID]));
}
if ($Count === 0 && $Phone !== '') {
$Variants = self::phoneCandidates($Phone);
if ($Variants !== []) {
$Marks = implode(',', array_fill(0, count($Variants), '?'));
$Count = count($Database->fetchAll("SELECT `Device_ID`, `Telegram_ID`, `User_UUID` FROM `App_Devices` WHERE `Phone` IN ({$Marks}) AND `Is_Trusted` = 1", $Variants));
}
}
if ($Count === 0 && ($Client_ID === '' || $Client_ID === '_')) {
return 'کاربر هنوز با نرم افزار وارد نشده و اشتراک فعالی هم ندارد';
}
} catch (Throwable) {
return 'خطا در دسترسی به جدول دستگاه ها؛ وضعیت پایگاه داده را بررسی کنید';
}
return 'ثبت اعلان در صف برنامه با خطا مواجه شد';
}

public static function singleSmsMenu(Context $Context): void {
self::deliveryMenu($Context, 'single', 'ارسال پیامک تکی');
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
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, self::header($Context, 'اطلاع رسانی به برنامه')
. "👌شناسه عددی کاربر، شماره موبایل یا کلمه «همه» را بفرستید.\n"
. 'ℹ️ پیام در برنامه آمبرلا به دستگاه همان کاربر نمایش داده می شود.' . Helper::adminFooter(), TelegramClient::inlineKeyboard([
Menu::back('منوی قبلی', 'منوی پیامک'), Menu::adminHome(),
]));
}

/** Second step: the admin sends the actual text. */
public static function appPushTarget(Context $Context, string $Input): void {
if (!$Context->isAdmin()) { return; }

$Input = trim($Input);

if ($Input === 'همه' || mb_strtolower($Input) === 'all') {
Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:app_push_text', 'Temp_UID' => 0]);
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'اطلاع رسانی به برنامه')
. '📝 حالا متن پیام را بفرستید؛ برای همه دستگاه ها ارسال می شود.' . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('اعلان برنامه', 'app_push_start')));
return;
}

$User = Repository::findUserByIdentifier($Input);
if ($User === null) {
$User = self::findUserInAppDevices($Input);
}

if ($User === null) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'اطلاع رسانی به برنامه') . "❌ کاربری با این شناسه پیدا نشد." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('اعلان برنامه', 'app_push_start')));
return;
}

$TargetUid = (int)($User['Telegram_ID'] ?? 0);
if ($TargetUid <= 0) {
$DevRowId = (int)($User['App_Device_Row_ID'] ?? 0);
if ($DevRowId <= 0) {
$DevMatch = self::findUserInAppDevices((string)($User['Phone'] ?? ($User['Client_ID'] ?? $Input)));
$DevRowId = (int)($DevMatch['App_Device_Row_ID'] ?? 0);
}
if ($DevRowId <= 0) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'اطلاع رسانی به برنامه') . "❌ دستگاه فعالی برای این کاربر ثبت نشده است." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('اعلان برنامه', 'app_push_start')));
return;
}
$TargetUid = -$DevRowId;
}

Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:app_push_text', 'Temp_UID' => $TargetUid]);
$Label = $TargetUid > 0 ? Helper::toPersian((string)$TargetUid) : Helper::toPersian((string)($User['Phone'] ?? 'دستگاه کاربر'));
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'اطلاع رسانی به برنامه')
. '📝 حالا متن پیام را بفرستید؛ برای دستگاه های کاربر ' . $Label . ' ارسال می شود.' . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('اعلان برنامه', 'app_push_start')));
}

/** Third step: stores (and queues) the message. */
public static function appPushText(Context $Context, string $Text): void {
if (!$Context->isAdmin()) { return; }

$Text = trim($Text);

if ($Text === '') return;

$Session = Repository::getUserSession($Context->UserId);
$Target = (int)($Session['Temp_UID'] ?? 0);
if ($Target < 0) {
$User = self::appDeviceUserByRowId(-$Target) ?? [];
$Count = self::queueAppPush((int)($User['Telegram_ID'] ?? 0), $Text, (int)$Context->UserId, true, $User);
} elseif ($Target > 0) {
$User = Repository::getUser($Target);
if ($User === []) $User = self::findUserInAppDevices((string)$Target) ?? [];
$Count = self::queueAppPush($Target, $Text, (int)$Context->UserId, true, $User);
} else {
$Count = self::queueAppPush(0, $Text, (int)$Context->UserId);
}

Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Temp_UID' => null]);
$Notice = $Count > 0
? '✅ پیام ثبت شد و تا ' . Helper::toPersian((string)$Count) . ' دستگاه تحویل داده می شود.'
: '❌ پیامی ثبت نشد: ' . ($Target !== 0 ? self::appDeliveryFailureReason(max(0, $Target), (int)$Context->UserId, $Target < 0 ? ($User ?? null) : null, true) : 'هیچ دستگاه فعالی برای دریافت پیام در سیستم ثبت نشده است.');
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'اطلاع رسانی به برنامه')
. $Notice . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('اعلان برنامه', 'app_push_start')));
}

/**
 * Writes the notification rows and returns how many devices it targets.
 *
 * Rows are always per device: `Delivered_At` is stamped when a device picks
 * its own message up, so a shared row (Device_ID NULL) would vanish for every
 * later device after the first one polled it.
 */
private static function ensureAppSchemaReady(): void {
static $Checked = false;
if ($Checked) return;
$Checked = true;
if (class_exists('AppSchema', false)) {
try { AppSchema::ensureInstalled(); } catch (Throwable) {}
}
}

private static function administratorTelegramIds(int $Extra_Admin = 0): array {
$Ids = $Extra_Admin > 0 ? [$Extra_Admin] : [];
$Env_Admin = 0;
if (class_exists('Environment') && method_exists('Environment', 'getAdminUserId')) {
try { $Env_Admin = (int)Environment::getAdminUserId(); } catch (Throwable) {}
}
if ($Env_Admin > 0) $Ids[] = $Env_Admin;
try {
$Configured = (int)Repository::getSetting('Administrator', (string)$Env_Admin);
if ($Configured > 0) $Ids[] = $Configured;
} catch (Throwable) {}
return array_values(array_unique($Ids));
}

/** Panel UUIDs tied to admin Telegram accounts, including devices not yet backfilled. */
private static function administratorClientUuids(array $Admin_Ids): array {
$Uuids = [];
foreach ($Admin_Ids as $Id) {
$User = Repository::getUser((int)$Id);
$Uuid = trim((string)($User['Client_ID'] ?? ''));
if ($Uuid !== '' && $Uuid !== '_') $Uuids[] = $Uuid;
}
return array_values(array_unique($Uuids));
}

private static function isAdministratorDevice(array $Row, array $Admin_Ids, array $Admin_Uuids): bool {
$Telegram_Id = (int)($Row['Telegram_ID'] ?? 0);
$Uuid = trim((string)($Row['User_UUID'] ?? ''));
return ($Telegram_Id > 0 && in_array($Telegram_Id, $Admin_Ids, true))
|| ($Uuid !== '' && in_array($Uuid, $Admin_Uuids, true));
}

public static function queueAppPush(int $Target_Telegram_ID, string $Text, int $Admin_ID, bool $Allow_Admin_Target = false, ?array $User_Context = null): int {
self::ensureAppSchemaReady();
$Database = \Database::getInstance();
$Title = mb_substr($Text, 0, 60);
$Body = $Text;
$Admin_Ids = self::administratorTelegramIds($Admin_ID);
$Admin_Uuids = self::administratorClientUuids($Admin_Ids);

if ($Target_Telegram_ID > 0 || $User_Context !== null) {
if (!$Allow_Admin_Target && $Target_Telegram_ID > 0 && in_array($Target_Telegram_ID, $Admin_Ids, true)) return 0;

$User_Row = $Target_Telegram_ID > 0 ? ($Database->fetch('SELECT `Client_ID`, `Phone` FROM `Users` WHERE `Telegram_ID` = ? LIMIT 1', [$Target_Telegram_ID]) ?? []) : [];
$Client_ID = trim((string)($User_Row['Client_ID'] ?? ($User_Context['Client_ID'] ?? '')));
$Phone = trim((string)($User_Row['Phone'] ?? ($User_Context['Phone'] ?? '')));
$Explicit_Device = trim((string)($User_Context['Device_ID'] ?? ''));

$Rows = [];
if ($Target_Telegram_ID > 0) {
$Rows = $Database->fetchAll('SELECT `Device_ID`, `Telegram_ID`, `User_UUID` FROM `App_Devices` WHERE `Telegram_ID` = ? AND `Is_Trusted` = 1', [$Target_Telegram_ID]);
if (!$Allow_Admin_Target) {
$Rows = array_values(array_filter($Rows, static fn(array $Row): bool => !self::isAdministratorDevice($Row, $Admin_Ids, $Admin_Uuids)));
}
}

if ($Rows === [] && $Client_ID !== '' && $Client_ID !== '_' && ($Allow_Admin_Target || !in_array($Client_ID, $Admin_Uuids, true))) {
$Rows = $Database->fetchAll('SELECT `Device_ID`, `Telegram_ID`, `User_UUID` FROM `App_Devices` WHERE `User_UUID` = ? AND `Is_Trusted` = 1', [$Client_ID]);
if (!$Allow_Admin_Target) {
$Rows = array_values(array_filter($Rows, static fn(array $Row): bool => !self::isAdministratorDevice($Row, $Admin_Ids, $Admin_Uuids)));
}
}

if ($Rows === [] && $Phone !== '') {
$Variants = self::phoneCandidates($Phone);
if ($Variants !== []) {
$Marks = implode(',', array_fill(0, count($Variants), '?'));
$Rows = $Database->fetchAll("SELECT `Device_ID`, `Telegram_ID`, `User_UUID` FROM `App_Devices` WHERE `Phone` IN ({$Marks}) AND `Is_Trusted` = 1", $Variants);
if (!$Allow_Admin_Target) {
$Rows = array_values(array_filter($Rows, static fn(array $Row): bool => !self::isAdministratorDevice($Row, $Admin_Ids, $Admin_Uuids)));
}
if ($Rows !== [] && $Target_Telegram_ID > 0) {
foreach ($Rows as $Matched_Row) {
if ((int)($Matched_Row['Telegram_ID'] ?? 0) <= 0 && !empty($Matched_Row['Device_ID'])) {
try {
$Database->execute('UPDATE `App_Devices` SET `Telegram_ID` = ? WHERE `Device_ID` = ? AND (`Telegram_ID` IS NULL OR `Telegram_ID` = 0)', [$Target_Telegram_ID, (string)$Matched_Row['Device_ID']]);
} catch (Throwable) {}
}
if (($Client_ID === '' || $Client_ID === '_') && !empty($Matched_Row['User_UUID'])) {
$Client_ID = trim((string)$Matched_Row['User_UUID']);
}
}
}
}
}

if ($Rows === [] && $Explicit_Device !== '') {
$Rows = $Database->fetchAll('SELECT `Device_ID`, `Telegram_ID`, `User_UUID` FROM `App_Devices` WHERE `Device_ID` = ? AND `Is_Trusted` = 1', [$Explicit_Device]);
if (!$Allow_Admin_Target) {
$Rows = array_values(array_filter($Rows, static fn(array $Row): bool => !self::isAdministratorDevice($Row, $Admin_Ids, $Admin_Uuids)));
}
}

$Is_Admin_Target = ($Target_Telegram_ID > 0 && in_array($Target_Telegram_ID, $Admin_Ids, true))
|| ($Client_ID !== '' && in_array($Client_ID, $Admin_Uuids, true));
foreach ($Rows as $Check_Row) {
if (self::isAdministratorDevice($Check_Row, $Admin_Ids, $Admin_Uuids)) {
$Is_Admin_Target = true;
break;
}
}
$Level = ($Allow_Admin_Target && $Is_Admin_Target) ? 'manual' : 'info';

if ($Rows === []) {
if ($Client_ID !== '' && $Client_ID !== '_' && ($Allow_Admin_Target || !in_array($Client_ID, $Admin_Uuids, true))) {
$Database->execute('INSERT INTO `App_Notifications` (`User_UUID`, `Device_ID`, `Title`, `Body`, `Level`) VALUES (?, NULL, ?, ?, ?)', [$Client_ID, $Title, $Body, $Level]);
try { Repository::logAdminAction($Admin_ID, 'app_push_user_deferred', $Target_Telegram_ID > 0 ? $Target_Telegram_ID : null, null); } catch (Throwable) {}
return 1;
}
// هیچ مقصدی برای این کاربر وجود ندارد؛ پیام خصوصی نباید همگانی شود.
return 0;
}

foreach ($Rows as $Row) {
$Database->execute('INSERT INTO `App_Notifications` (`User_UUID`, `Device_ID`, `Title`, `Body`, `Level`) VALUES (NULL, ?, ?, ?, ?)', [(string)$Row['Device_ID'], $Title, $Body, $Level]);
}

try { Repository::logAdminAction($Admin_ID, 'app_push_user', $Target_Telegram_ID > 0 ? $Target_Telegram_ID : null, mb_substr($Text, 0, 120)); } catch (Throwable) {}
return count($Rows);
}

$Rows = $Database->fetchAll('SELECT `Device_ID`, `Telegram_ID`, `User_UUID` FROM `App_Devices` WHERE `Is_Trusted` = 1');
$Rows = array_values(array_filter($Rows, static fn(array $Row): bool => !self::isAdministratorDevice($Row, $Admin_Ids, $Admin_Uuids)));
foreach ($Rows as $Row) {
$Database->execute('INSERT INTO `App_Notifications` (`Device_ID`, `Title`, `Body`, `Level`) VALUES (?, ?, ?, \'notice\')', [(string)$Row['Device_ID'], $Title, $Body]);
}
try { Repository::logAdminAction($Admin_ID, 'app_push_all_devices', null, mb_substr($Text, 0, 120)); } catch (Throwable) {}
return count($Rows);
}

/** «📣تلگرام + برنامه همزمان» — one text, Telegram and the app. */
public static function notifyAllStart(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:notify_all_text', 'Temp_UID' => null]);

TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, self::header($Context, 'اطلاع به تلگرام و برنامه')
. "📣*پیام همزمان آماده ارسال است.*\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "👌متن دلخواه خود را در یک پیام بفرستید.\n"
. "📤این متن برای همهٔ کاربران ربات (تلگرام) و همهٔ دستگاه های برنامهٔ «آمبرلا» به عنوان اعلان برنامه ارسال می شود." . Helper::adminFooter(), TelegramClient::inlineKeyboard([
Menu::back('منوی قبلی', 'منوی پیامک'), Menu::adminHome(),
]));
}

/** Sends one message to every Telegram user and every trusted app device. */
public static function broadcastTelegramAndApp(Context $Context, string $Text): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$Text = trim($Text);

if ($Text === '') {
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'اطلاع به تلگرام و برنامه') . "❌متن ارسالی خالی است؛ لطفاً متنی وارد کنید." . Helper::adminFooter(), TelegramClient::inlineKeyboard(array_merge(
[[['text' => '🔄تلاش دوباره', 'callback_data' => 'notify_all_start']]],
Menu::adminNav('تلگرام و برنامه', 'notify_all_start')
)));
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
$Result = TelegramClient::sendMessage($Chat_ID, Helper::frame('کاربر', $Name, 'اطلاع رسانی', $User_ID) . "📣پیام اطلاع رسانی سرور آمبرلا:\n\n{$Text}" . Helper::userFooter(), TelegramClient::inlineKeyboard([
Menu::userHome(),
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
. "📱دستگاه های برنامه که این اعلان را دریافت می کنند: " . Helper::toPersian($Devices) . " دستگاه\n"
. "👥تعداد کل مخاطبین تلگرام: " . Helper::toPersian((string)count($Rows)) . " نفر";

$Markup = array_merge(
Menu::rows([
[['🔄ارسال پیام دیگر', 'notify_all_start']],
]),
Menu::adminNav('تلگرام و برنامه', 'notify_all_start')
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
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard([
Menu::back('منوی قبلی', 'admin_devices_menu'), Menu::adminHome(),
]));
}

/** Second step: show the current state and let the admin pick the new cap. */
public static function deviceLimitTarget(Context $Context, string $Input): void {
if (!$Context->isAdmin()) { return; }

$User = Repository::findUserByIdentifier($Input);

if ($User === null) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'مجوز دستگاه کاربران') . "❌ کاربری با این شناسه پیدا نشد." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('مجوز دستگاه', 'device_limit_menu')));
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
$When_Raw = trim((string)($Row['Last_Seen_At'] ?? ''));
$When = $When_Raw !== '' && $When_Raw !== '0'
? (method_exists('Helper', 'formatDateTimeText') ? Helper::formatDateTimeText($When_Raw) : Helper::toPersian($When_Raw))
: '—';
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
'📞شماره: ' . Helper::toPersian($Phone),
'🔐مجوز فعلی: ' . Helper::toPersian((string)$Limit) . ' دستگاه',
])
. "\n📲*دستگاه های فعال:*\n" . $Device_Lines
. "👇چند دستگاه برای این حساب مجاز باشد؟";

Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:device_limit_pick', 'Temp_UID' => $Telegram_Id]);

TelegramClient::sendMessage($Context->ChatId, $Text . "\n🔢یک عدد از ۱ تا ۹۹ بفرستید." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('مجوز دستگاه', 'device_limit_menu')));
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

// Accept both Persian and ASCII digits; never silently clamp an invalid value.
if (!preg_match('/^[0-9]{1,2}$/D', $Number) || (int)$Number < 1 || (int)$Number > 99) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'مجوز دستگاه کاربران') . "⚠️فقط عددی بین ۱ تا ۹۹ بفرستید." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('مجوز دستگاه', 'device_limit_menu')));
return;
}

self::deviceLimitSet($Context, (int)$Number);
}

/** Third step: persist the choice. */
public static function deviceLimitSet(Context $Context, int $Max): void {
if (!$Context->isAdmin()) { return; }

if ($Context->CallbackId !== null) {
try { TelegramClient::answerCallbackQuery($Context->CallbackId); } catch (Throwable) {}
}

$Session = Repository::getUserSession($Context->UserId);
$Telegram_Id = (int)($Session['Temp_UID'] ?? 0);

if ($Telegram_Id <= 0 || ($Session['Flow'] ?? '') !== 'admin:device_limit_pick') {
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'مجوز دستگاه کاربران') . "⌛️این عملیات منقضی شده است؛ دوباره از منو شروع کنید." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('مجوز دستگاه کاربران', 'device_limit_menu')));
return;
}

$Max = AppDeviceLimit::setMaxDevices($Telegram_Id, $Max);
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Temp_UID' => null]);
Repository::logAdminAction((int)$Context->UserId, 'device_limit_set', $Telegram_Id, 'max=' . $Max);

TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'مجوز دستگاه کاربران')
. "✅*انجام شد.*\n📱از این به بعد کاربر " . Helper::toPersian((string)$Telegram_Id) . " می تواند روی *" . Helper::toPersian((string)$Max) . " دستگاه* به طور همزمان فعال باشد." . Helper::adminFooter(), TelegramClient::inlineKeyboard(array_merge([
[['text' => '📲فهرست دستگاه ها', 'callback_data' => 'admin_devices']],
], Menu::adminNav('مجوز دستگاه', 'device_limit_menu'))));
}

public static function notifySingleMenu(Context $Context): void {
self::deliveryMenu($Context, 'notify', 'اطلاع رسانی به کاربر');
}

public static function startInputSingleSmsUid(Context $Context, string $Mode): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:sms_single_uid', 'Broadcast_Mode' => $Mode, 'Temp_UID' => null]);
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, self::header($Context, 'ارسال پیامک تکی') . '👌شناسه عددی یا شماره موبایل کاربر مورد نظر را وارد کنید.' . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('پیامک تکی', 'ارسال پیامک تکی اول')));
}

public static function startInputNotifyUid(Context $Context, string $Mode): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:notify_uid', 'Broadcast_Mode' => $Mode, 'Temp_UID' => null]);
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, self::header($Context, 'اطلاع رسانی به کاربر') . '👌شناسه عددی یا شماره موبایل کاربر مورد نظر را وارد کنید.' . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('اطلاع رسانی', 'اطلاع رسانی اول')));
}

public static function broadcastMenu(Context $Context): void {
self::deliveryMenu($Context, 'broadcast', 'ارسال پیامک همگانی');
}

private static function broadcastNotify(Context $Context, string $Message, string $Mode = 'telegram'): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
if (trim($Message) === '' || !in_array($Mode, ['telegram', 'sms', 'app', 'all', 'both'], true)) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . '⚠️متن یا روش ارسال معتبر نیست؛ دوباره تلاش کنید.', TelegramClient::inlineKeyboard(Menu::adminNav('روش ارسال', 'ارسال پیامک همگانی اول')));
return;
}
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Temp_UID' => null, 'Broadcast_Mode' => null]);
$Rows = Database::getInstance()->fetchAll('SELECT `Telegram_ID`, `Chat_ID`, `Phone`, `Full_Name` FROM `Users` WHERE `Is_Blocked` = 0 ORDER BY `Telegram_ID` ASC');
$Counts = [];
$User_Mode = $Mode === 'all' ? 'both' : ($Mode === 'app' ? '' : $Mode);
if ($User_Mode !== '') {
foreach ($Rows as $User) {
foreach (self::deliverMessage($User, $Message, $User_Mode, $Context->UserId) as $Channel => $Ok) {
$Counts[$Channel][$Ok ? 'ok' : 'failed'] = ($Counts[$Channel][$Ok ? 'ok' : 'failed'] ?? 0) + 1;
}
}
}
$App_Queued = null;
if ($Mode === 'app' || $Mode === 'all') {
try {
$App_Queued = self::queueAppPush(0, $Message, $Context->UserId);
} catch (Throwable $Error) {
error_log('[Umbrella-Bot][Broadcast-App] ' . $Error->getMessage());
$App_Queued = 0;
}
}
$Summary = '👥تعداد مخاطبان: ' . Helper::toPersian((string)count($Rows));
foreach ($Counts as $Channel => $Count) {
$Summary .= "\n" . self::deliveryModeLabel($Channel) . ': ✅ارسال موفق: ' . Helper::toPersian((string)($Count['ok'] ?? 0)) . ' | ❌ناموفق: ' . Helper::toPersian((string)($Count['failed'] ?? 0));
}
if ($App_Queued !== null) {
$Summary .= "\n" . self::deliveryModeLabel('app') . ': ' . ($App_Queued > 0 ? '✅ثبت در صف دریافت برای ' . Helper::toPersian((string)$App_Queued) . ' دستگاه مجاز' : 'ℹ️هیچ دستگاه فعالی در برنامه ثبت نشده است');
}
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'نتیجه ارسال همگانی') . $Summary . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('پیام رسانی', 'منوی پیامک')));
}

private static function singleSmsStep(Context $Context, string $UidText): void {
$User = self::resolveTarget($Context, $UidText, 'ارسال پیامک تکی اول', 'پیامک تکی');

if ($User === null) {
return;
}

$Session = Repository::getUserSession($Context->UserId);
$Mode = (string)($Session['Broadcast_Mode'] ?? 'sms');

if (!in_array($Mode, ['telegram', 'sms', 'app', 'all', 'both'], true)) {
$Mode = 'sms';
}

$Target = (int)($User['Telegram_ID'] ?? 0);
$DeviceRowId = (int)($User['App_Device_Row_ID'] ?? 0);
$HasPhone = Helper::validatePhone((string)($User['Phone'] ?? ''));
$HasAppTarget = $DeviceRowId > 0
|| (trim((string)($User['Client_ID'] ?? '')) !== '' && trim((string)($User['Client_ID'] ?? '')) !== '_')
|| $HasPhone;

if ($Target <= 0) {
if ($Mode === 'telegram' || !$HasAppTarget) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'ارسال پیامک تکی') . "❌خطا: شناسه تلگرام معتبر برای این کاربر ثبت نشده است." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('پیامک تکی', 'ارسال پیامک تکی اول')));
return;
}
if ($DeviceRowId <= 0) {
$FoundDev = self::findUserInAppDevices((string)($User['Phone'] ?? ($User['Client_ID'] ?? '')));
$DeviceRowId = (int)($FoundDev['App_Device_Row_ID'] ?? 0);
}
if ($DeviceRowId <= 0) {
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'ارسال پیامک تکی') . "❌خطا: شناسه یا دستگاه معتبری برای این کاربر یافت نشد." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('پیامک تکی', 'ارسال پیامک تکی اول')));
return;
}
$Target = -$DeviceRowId;
}

$Mode_Label = self::deliveryModeLabel($Mode);

Repository::updateUserSession($Context->UserId, ['Temp_UID' => $Target, 'Flow' => 'admin:sms_single_text', 'Broadcast_Mode' => $Mode]);
$Name = $Target > 0 ? self::targetDisplayName($Target, $User) : trim((string)($User['Full_Name'] ?? 'کاربر برنامه'));
$TargetTag = $Target > 0 ? Helper::toPersian((string)$Target) : Helper::toPersian((string)($User['Phone'] ?? 'کاربر برنامه'));
TelegramClient::sendMessage($Context->ChatId, self::header($Context, 'ارسال پیامک تکی') . "👌متن پیامک تکی ({$Mode_Label}) برای کاربر {$Name} را وارد کنید.\n🎯شناسه: `" . $TargetTag . "`" . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('پیامک تکی', 'ارسال پیامک تکی اول')));
}

private static function singleSmsModeRetry(Context $Context): void {
self::singleSmsMenu($Context);
}

private static function notifyModeRetry(Context $Context): void {
self::notifySingleMenu($Context);
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
self::sendSingleMessage($Context, $Message, 'ارسال پیامک تکی اول');
}

private static function manualExpire(Context $Context, string $Target_Input): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$User = self::resolveTarget($Context, $Target_Input, 'منقضی اشتراک اول', 'منقضی کردن اشتراک');

if ($User === null) {
return;
}

$Target = (int)($User['Telegram_ID'] ?? 0);
$Subscription = (string)($User['Subscription'] ?? '');
$Sms_Event = IppanelClient::subscriptionEvent('expired', $User);

if ($Subscription === '') {
$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *❌خطا: اشتراک فعالی برای کاربر {$Name} ثبت نشده است.\n➖➖➖➖➖➖➖➖➖\n⚠️دلیل: این کاربر در حال حاضر اشتراک فعالی ندارد." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('منقضی کردن اشتراک', 'منقضی اشتراک اول')));
return;
}

$Client_ID = (string)(Repository::getUser($Target)['Client_ID'] ?? '');

if ($Client_ID !== '' && $Client_ID !== '_') {
$Response = ServerClient::updateUser($Client_ID, ['is_active' => false, 'enable' => false]);

if (($Response['StatusCode'] ?? 0) >= 300) {
$Name = self::targetDisplayName($Target, Repository::getUser($Target));
self::notifyAdminServerError('غیرفعالسازی کلاینت', $Target, $Name, $Response['StatusCode'] ?? 0, (string)($Response['Body'] ?? ''));
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *❌خطا: غیرفعالسازی کلاینت در سرور ناموفق بود.\n➖➖➖➖➖➖➖➖➖\n⚠️پاسخ سرور: " . mb_substr((string)($Response['Body'] ?? ''), 0, 200) . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('منقضی کردن اشتراک', 'منقضی اشتراک اول')));
return;
}
}

Repository::updateUser($Target, [
'Client_Status' => '🚫غیر فعال',
'Server_Is_Active' => 0,
'Server_Enable' => 0,
'Channel_Client_Disabled_At' => null,
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
TelegramClient::sendSystemMessage($Chat_ID, Helper::frame('کاربر', $Full_Name, 'انقضای اشتراک', $Target) . "🌹اشتراک {$Subscription} شما منقضی گردید.\n\n⚠️اتصال شما از سرور قطع گردید." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '💳خرید یا تمدید اشتراک', 'callback_data' => 'user_subscriptions_menu']],
Menu::userHome(),
]));
}

if (Helper::validatePhone($Phone)) {
$Plan = Helper::smsPlan((string)($Subscription ?? ''));
$Template = Repository::getSmsTemplate('expired');
$Sms_Text = $Template !== null
? strtr($Template, ['{full_name}' => $Full_Name, '{plan}' => $Plan])
: "{$Full_Name} گرامی ⏰اشتراک {$Plan} شما به اتمام رسید.\n🔌اتصال شما از سرور قطع گردید.\n\nسرور آمبرلا";
IppanelClient::sendOnce($Target, $Phone, $Sms_Text, $Sms_Event);
}

$Name = self::targetDisplayName($Target, $User);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *⏰اشتراک کاربر {$Name} منقضی گردید.\n➖➖➖➖➖➖➖➖➖\n⚠️وضعیت: کلاینت در سرور غیرفعال شد و اطلاعات کاربری محفوظ ماند." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('منقضی کردن اشتراک', 'منقضی اشتراک اول')));
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

TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Error_Text, TelegramClient::inlineKeyboard([
[['text' => '🔁بروز رسانی مجدد', 'callback_data' => 'بروز رسانی میزان استفاده اول']],
Menu::back('منوی قبلی', 'پیکربندی سرور'), Menu::adminHome(),
]));

return;
}

$Synced = (int)Scheduler::refreshUsagesNow();

if ($Synced <= 0) {
$Sync_Error = self::header($Context) . " *⚠️بروزرسانی مصرف در سرور انجام شد اما دریافت فهرست کاربران از سرور ناموفق بود.\n➖➖➖➖➖➖➖➖➖\n🔄لطفا چند لحظه دیگر دوباره تلاش کنید." . Helper::adminFooter();

TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Sync_Error, TelegramClient::inlineKeyboard([
[['text' => '🔁بروز رسانی مجدد', 'callback_data' => 'بروز رسانی میزان استفاده اول']],
Menu::back('منوی قبلی', 'پیکربندی سرور'), Menu::adminHome(),
]));

return;
}

$Total_Usage_GB = (float)Database::getInstance()->scalar('SELECT COALESCE(SUM(`Used_Usage_GB`), 0) FROM `Users` WHERE `Client_ID` IS NOT NULL AND `Client_ID` != ""');
$Total_Usage_Human = Helper::formatBytes((int)($Total_Usage_GB * 1024 * 1024 * 1024));

try {
Repository::updateUsageSnapshotValues();
}

catch (Throwable) {}
$Success_Text = Helper::adminGreeting($Context, 'میزان استفاده کاربران') . '✅بروز رسانی میزان استفاده کاربران از سرور با موفقیت انجام شد.' . "\n👥تعداد بروز رسانی شده: `" . Helper::toPersian((string)$Synced) . "` کاربر\n📊مجموع مصرف: `" . $Total_Usage_Human . "`\n\n" . Helper::adminFooter();

TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Success_Text, TelegramClient::inlineKeyboard([
[['text' => '🔁بروز رسانی مجدد', 'callback_data' => 'بروز رسانی میزان استفاده اول']],
Menu::back('منوی قبلی', 'پیکربندی سرور'), Menu::adminHome(),
]));
}

public static function askUpdateUserData(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🔄در حال بارگذاری...', false);
}

Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Temp_UID' => null, 'Broadcast_Mode' => null]);
$Text = Helper::adminGreeting($Context, 'بروز رسانی داده های کاربران')
. "🧾*انتخاب روش بروزرسانی داده های کاربران:*\n➖➖➖➖➖➖➖➖➖\n"
. "🔄*بروزرسانی خودکار همه کاربران:*\n"
. "├─دریافت مستقیم تمام کاربران از سرور آمبرلا (`API`)\n"
. "├─بروزرسانی اطلاعات کاربران فعلی و افزودن کاربران جدید\n"
. "└─بدون حذف داده ها، تراکنش ها، دستگاه ها و سوابق دیتابیس\n\n"
. "👤*بروزرسانی تکی (ورود دستی):*\n"
. "└─ثبت یا بروزرسانی یک کاربر با وارد کردن آیدی عددی (یا شماره) و `UUID`"
. Helper::adminFooter();

$Rows = array_merge(
Menu::rows([
[['🔄بروزرسانی خودکار همه کاربران', 'admin_users_auto_sync']],
[['👤بروزرسانی تکی (ورود دستی)', 'admin_users_single_sync']],
]),
[
Menu::back('منوی قبلی', 'عملیات کلاینت سرور'),
Menu::adminHome(),
]
);

TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Rows));
}

public static function askSingleUserData(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '👤در حال آماده سازی ورود تکی...', false);
}

Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:update_uid']);
$Text = Helper::adminGreeting($Context, 'بروزرسانی تکی داده کاربر')
. "👌لطفا آیدی عددی (یا شماره موبایل) و شناسه کلاینت (`UUID`) *یک کاربر* را وارد کنید:\n\n"
. "`شناسه کاربر یا شماره موبایل`\n"
. "`شناسه کلاینت`\n\n"
. "نمونه:\n"
. "`۶۲۴۸۷۴۲۷۰۵`\n"
. "`970f3fa0-3714-4d9a-a95d-8c4ddd696bfd`\n\n"
. "⚠️توجه: این بخش فقط برای ثبت یا بروزرسانی *تکی* است؛ برای بروزرسانی گروهی همه کاربران از دکمه «🔄بروزرسانی خودکار همه کاربران» استفاده کنید."
. Helper::adminFooter();

TelegramClient::editOrSendMessage(
$Context->ChatId,
$Context->MessageId,
$Text,
TelegramClient::inlineKeyboard(Menu::adminNav('منوی قبلی', 'بروز رسانی داده های کاربران اول'))
);
}

public static function autoUpdateAllUsers(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Temp_UID' => null, 'Broadcast_Mode' => null]);

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🔄در حال دریافت کامل کاربران از سرور...', false);
}

$Loading_Text = self::header($Context, 'بروز رسانی داده های کاربران')
. "🔄*در حال دریافت فهرست کاربران از سرور و همگام سازی با دیتابیس...*\n➖➖➖➖➖➖➖➖➖\n"
. "⏳لطفا چند لحظه صبر کنید."
. Helper::adminFooter();

if ($Context->MessageId !== null) {
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Loading_Text, TelegramClient::inlineKeyboard([Menu::adminHome()]));
} else {
TelegramClient::sendMessage($Context->ChatId, $Loading_Text);
}

$Response = ServerClient::listUsers(3, 30);
$Status = (int)($Response['StatusCode'] ?? 0);
$Rows = self::unwrapServerUserRows($Response['Json'] ?? null);

$Retry_Nav = [
[Menu::button('🔁تلاش مجدد خودکار', 'admin_users_auto_sync'), Menu::button('👤بروزرسانی تکی', 'admin_users_single_sync')],
Menu::back('منوی قبلی', 'عملیات کلاینت سرور'),
Menu::adminHome(),
];

if ($Rows === null || $Status < 200 || $Status >= 300) {
$Error_Detail = trim((string)($Response['Body'] ?? ''));
if ($Error_Detail === '') $Error_Detail = trim((string)($Response['Error'] ?? 'خطا در ارتباط با سرور'));
$Admin_Label = method_exists($Context, 'profileName') ? (string)$Context->profileName() : '';
self::notifyAdminServerError('بروزرسانی خودکار کل کاربران', $Context->UserId, $Admin_Label, $Status, $Error_Detail);
$Error_Text = self::header($Context, 'بروز رسانی داده های کاربران')
. "❌*خطا: دریافت فهرست کاربران از سرور ناموفق بود؛ دیتابیس بدون تغییر حفظ شد.*\n➖➖➖➖➖➖➖➖➖\n"
. "📡کد وضعیت: `" . Helper::toPersian((string)$Status) . "`\n"
. "⚠️پاسخ سرور: " . mb_substr($Error_Detail, 0, 250)
. Helper::adminFooter();
TelegramClient::sendMessage($Context->ChatId, $Error_Text, TelegramClient::inlineKeyboard($Retry_Nav));
return;
}

if ($Rows === []) {
$Empty_Text = self::header($Context, 'بروز رسانی داده های کاربران')
. "⚠️*فهرست دریافتی از سرور خالی بود؛ تغییری در دیتابیس اعمال نشد.*"
. Helper::adminFooter();
TelegramClient::sendMessage($Context->ChatId, $Empty_Text, TelegramClient::inlineKeyboard($Retry_Nav));
return;
}

$Db = Database::getInstance();
$Existing_Lookup = [];

try {
if (method_exists($Db, 'fetchAll')) {
$Table_Rows = $Db->fetchAll('SELECT TABLE_NAME AS t FROM information_schema.tables WHERE table_schema = DATABASE()', []);
foreach ($Table_Rows as $T_Row) {
$T_Name = (string)($T_Row['t'] ?? $T_Row['TABLE_NAME'] ?? '');
if ($T_Name !== '') $Existing_Lookup[strtolower($T_Name)] = true;
}
}
} catch (Throwable) {
$Existing_Lookup = [];
}

$Has_Devices_Table = $Existing_Lookup === [] || isset($Existing_Lookup['app_devices']);
$Has_Sessions_Table = $Existing_Lookup === [] || isset($Existing_Lookup['app_sessions']);

$Prepared_Users = [];
$Row_Meta = [];
$Missing_Tg_Rows = [];
$Duplicate_Tg_Rows = [];
$Invalid_Rows = 0;

foreach ($Rows as $Row) {
if (!is_array($Row)) {
$Invalid_Rows++;
continue;
}
$Uuid = trim((string)($Row['uuid'] ?? ''));
if ($Uuid === '' || $Uuid === '_') {
$Invalid_Rows++;
continue;
}

$Telegram_ID = (int)($Row['telegram_id'] ?? 0);
$Raw_Name = trim((string)($Row['name'] ?? ''));
$Comment = trim((string)($Row['comment'] ?? ''));
$Row_Id = (int)($Row['id'] ?? 0);

if ($Telegram_ID <= 0 && method_exists($Db, 'fetchOne')) {
try {
$Linked_Row = $Db->fetchOne('SELECT `Telegram_ID` FROM `Users` WHERE `Client_ID` = ? LIMIT 1', [$Uuid]);
if (is_array($Linked_Row) && (int)($Linked_Row['Telegram_ID'] ?? 0) > 0) {
$Telegram_ID = (int)$Linked_Row['Telegram_ID'];
}
} catch (Throwable) {}
}

if ($Telegram_ID <= 0) {
$Missing_Tg_Rows[] = [
'name' => $Raw_Name !== '' ? $Raw_Name : 'بدون نام',
'comment' => $Comment,
'uuid' => $Uuid,
];
continue;
}

$Built = self::buildBulkUserRow($Row, $Telegram_ID, $Uuid);
$Is_Active = ((int)$Built['Server_Is_Active'] === 1 && (int)$Built['Server_Enable'] === 1);
$Start_Raw = substr(trim((string)($Row['start_date'] ?? '')), 0, 10);

if (isset($Prepared_Users[$Telegram_ID])) {
$Prev_Meta = $Row_Meta[$Telegram_ID];
$Prev_Wins = ($Prev_Meta['active'] && !$Is_Active)
|| ($Prev_Meta['active'] === $Is_Active && ($Prev_Meta['start'] > $Start_Raw || ($Prev_Meta['start'] === $Start_Raw && $Prev_Meta['id'] >= $Row_Id)));

if ($Prev_Wins) {
$Duplicate_Tg_Rows[] = ['telegram_id' => $Telegram_ID, 'name' => (string)$Built['Full_Name'], 'uuid' => $Uuid];
continue;
}

$Duplicate_Tg_Rows[] = ['telegram_id' => $Telegram_ID, 'name' => (string)$Prepared_Users[$Telegram_ID]['Full_Name'], 'uuid' => (string)$Prepared_Users[$Telegram_ID]['Client_ID']];
}

$Prepared_Users[$Telegram_ID] = $Built;
$Row_Meta[$Telegram_ID] = ['active' => $Is_Active, 'start' => $Start_Raw, 'id' => $Row_Id];
}

$Updated_Count = 0;
$Inserted_Count = 0;

$Apply_Upsert = static function (Database $Tx) use ($Prepared_Users, $Has_Devices_Table, $Has_Sessions_Table, &$Updated_Count, &$Inserted_Count): void {
foreach ($Prepared_Users as $Telegram_ID => $User_Row) {
$Uuid = (string)$User_Row['Client_ID'];

if (method_exists($Tx, 'execute')) {
$Tx->execute(
'UPDATE `Users` SET `Client_ID` = NULL WHERE `Client_ID` = ? AND `Telegram_ID` <> ?',
[$Uuid, $Telegram_ID]
);
}

$Existing_User = Repository::getUser((int)$Telegram_ID);
$App_Free_Claimed = method_exists('Repository', 'getSetting')
&& trim((string)Repository::getSetting('App_Free_Claimed_' . $Uuid, '')) === '1';

if (!empty($Existing_User) && is_array($Existing_User)) {
$Update_Fields = $User_Row;
unset(
$Update_Fields['Telegram_ID'],
$Update_Fields['Chat_ID'],
$Update_Fields['Balance'],
$Update_Fields['Is_Blocked'],
$Update_Fields['Free_Plan_Claimed'],
$Update_Fields['Registered_At']
);

$Local_Name = trim((string)($Existing_User['Full_Name'] ?? ''));
$Server_Is_Placeholder = trim((string)$User_Row['Full_Name']) === 'کاربر';
if ($Server_Is_Placeholder && $Local_Name !== '') {
$Update_Fields['Full_Name'] = $Local_Name;
$Update_Fields['First_Name'] = trim((string)($Existing_User['First_Name'] ?? '')) !== ''
? (string)$Existing_User['First_Name']
: $Local_Name;
}

$Is_Active = ((int)$User_Row['Server_Is_Active'] === 1 && (int)$User_Row['Server_Enable'] === 1);
if (!$Is_Active) {
$Update_Fields['Deactivation_Message'] = $Existing_User['Deactivation_Message'] ?? null;
if ((int)($Existing_User['Channel_Client_Disabled_At'] ?? 0) > 0) {
$Update_Fields['Client_Status'] = '🚫قطع به دلیل عدم عضویت';
$Update_Fields['Channel_Client_Disabled_At'] = $Existing_User['Channel_Client_Disabled_At'];
}
}

$New_Phone = trim((string)($User_Row['Phone'] ?? ''));
if ($New_Phone === '') {
unset($Update_Fields['Phone'], $Update_Fields['Operator']);
} elseif (method_exists('Repository', 'findUserByPhone')) {
$Phone_Conflict = Repository::findUserByPhone($New_Phone, (int)$Telegram_ID);
if (!empty($Phone_Conflict)) {
unset($Update_Fields['Phone'], $Update_Fields['Operator']);
}
}

if ($App_Free_Claimed) {
$Update_Fields['Free_Plan_Claimed'] = 1;
}

Repository::updateUser((int)$Telegram_ID, $Update_Fields);
$Updated_Count++;
} else {
if ($App_Free_Claimed) {
$User_Row['Free_Plan_Claimed'] = 1;
}
$Tx->insert('Users', $User_Row);
$Inserted_Count++;
}

if (method_exists($Tx, 'execute')) {
if ($Has_Devices_Table) {
$Tx->execute(
'UPDATE `App_Devices` SET `Telegram_ID` = ? WHERE `User_UUID` = ? AND (`Telegram_ID` IS NULL OR `Telegram_ID` = 0)',
[$Telegram_ID, $Uuid]
);
}
if ($Has_Sessions_Table) {
$Tx->execute(
'UPDATE `App_Sessions` SET `Telegram_ID` = ? WHERE `User_UUID` = ? AND (`Telegram_ID` IS NULL OR `Telegram_ID` = 0)',
[$Telegram_ID, $Uuid]
);
}
}
}
};

try {
if (method_exists($Db, 'transaction')) {
$Db->transaction($Apply_Upsert);
} else {
$Apply_Upsert($Db);
}
} catch (Throwable $Error) {
error_log('[Umbrella-Bot][Bulk-User-Sync] ' . $Error->getMessage());
$Db_Err_Text = self::header($Context, 'بروز رسانی داده های کاربران')
. "❌*خطا در همگام سازی دیتابیس؛ تغییرات بازگردانی (Rollback) شد و داده های قبلی حفظ ماندند.*\n➖➖➖➖➖➖➖➖➖\n"
. "⚠️جزئیات: " . mb_substr($Error->getMessage(), 0, 220)
. Helper::adminFooter();
TelegramClient::sendMessage($Context->ChatId, $Db_Err_Text, TelegramClient::inlineKeyboard($Retry_Nav));
return;
}

try {
$Now_Hour = (new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran')))->format('Y-m-d H');
Repository::setSetting('Last_Usage_Sync', $Now_Hour);
if (method_exists('Repository', 'updateUsageSnapshotValues')) {
Repository::updateUsageSnapshotValues();
}
if (method_exists('Repository', 'logAdminAction')) {
Repository::logAdminAction(
$Context->UserId,
'admin_bulk_user_sync',
null,
'server_rows=' . count($Rows) . ',updated=' . $Updated_Count . ',inserted=' . $Inserted_Count . ',missing_tg=' . count($Missing_Tg_Rows)
);
}
} catch (Throwable) {}

$Active_Count = 0;
$Inactive_Count = 0;
$Total_Used_GB = 0.0;

foreach ($Prepared_Users as $U_Row) {
if ((int)$U_Row['Server_Is_Active'] === 1 && (int)$U_Row['Server_Enable'] === 1) {
$Active_Count++;
} else {
$Inactive_Count++;
}
$Total_Used_GB += (float)$U_Row['Used_Usage_GB'];
}

$Total_Usage_Label = method_exists('Helper', 'formatGB')
? Helper::formatGB($Total_Used_GB)
: Helper::toPersian(number_format($Total_Used_GB, 2)) . ' گیگابایت';

$Summary = Helper::adminGreeting($Context, 'بروز رسانی داده های کاربران')
. "✅*داده های کاربران بدون حذف دیتابیس بروزرسانی و اضافه شد.*\n➖➖➖➖➖➖➖➖➖\n"
. "📡تعداد کل دریافتی از سرور: *" . Helper::toPersian((string)count($Rows)) . "*\n"
. "🔄بروزرسانی کاربران فعلی: *" . Helper::toPersian((string)$Updated_Count) . "*\n"
. "➕افزودن کاربران جدید: *" . Helper::toPersian((string)$Inserted_Count) . "*\n"
. "🟢فعال: *" . Helper::toPersian((string)$Active_Count) . "* | 🔴غیرفعال: *" . Helper::toPersian((string)$Inactive_Count) . "*\n"
. "📊مجموع مصرف ثبت شده: *" . $Total_Usage_Label . "*\n";

if ($Invalid_Rows > 0) {
$Summary .= "⚠️رکورد نامعتبر (فاقد UUID): *" . Helper::toPersian((string)$Invalid_Rows) . "*\n";
}

if ($Prepared_Users !== []) {
$Summary .= "\n📋*نمونه کاربران همگام شده:*\n";
$Shown = 0;
foreach ($Prepared_Users as $Uid => $U_Row) {
$Status_Icon = ((int)$U_Row['Server_Is_Active'] === 1 && (int)$U_Row['Server_Enable'] === 1) ? '🟢' : '🔴';
$Line = $Status_Icon . $U_Row['Full_Name'] . ' — 🆔`' . Helper::toPersian((string)$Uid) . "`\n└─🔑`" . $U_Row['Client_ID'] . "`\n";
if (mb_strlen($Summary . $Line) > 2600 || $Shown >= 10) {
$Remaining_Count = count($Prepared_Users) - $Shown;
if ($Remaining_Count > 0) {
$Summary .= "… و *" . Helper::toPersian((string)$Remaining_Count) . "* کاربر دیگر همگام سازی شدند.\n";
}
break;
}
$Summary .= $Line;
$Shown++;
}
}

$Action_Nav = [
[Menu::button('🔄بروزرسانی مجدد همه', 'admin_users_auto_sync'), Menu::button('👤بروزرسانی تکی', 'admin_users_single_sync')],
Menu::back('منوی قبلی', 'عملیات کلاینت سرور'),
Menu::adminHome(),
];

if ($Missing_Tg_Rows === [] && $Duplicate_Tg_Rows === []) {
TelegramClient::sendMessage($Context->ChatId, mb_substr($Summary, 0, 3200) . Helper::adminFooter(), TelegramClient::inlineKeyboard($Action_Nav));
return;
}

TelegramClient::sendMessage($Context->ChatId, mb_substr($Summary, 0, 3200) . Helper::adminFooter(), TelegramClient::inlineKeyboard($Action_Nav));

if ($Missing_Tg_Rows !== []) {
$Missing_Header = self::header($Context, 'کاربران فاقد آیدی عددی')
. "⚠️*تعداد " . Helper::toPersian((string)count($Missing_Tg_Rows)) . " کاربر روی سرور بدون آیدی عددی (`telegram_id: null`) هستند و در دیتابیس ثبت نشدند:*\n"
. "👌برای ثبت هر کدام، از دکمه «👤بروزرسانی تکی» آیدی عددی و `UUID` را وارد کنید.\n➖➖➖➖➖➖➖➖➖\n";
$Chunk = $Missing_Header;

foreach ($Missing_Tg_Rows as $Index => $Missing) {
$Phone_Note = $Missing['comment'] !== '' ? ' | 📱`' . Helper::toPersian($Missing['comment']) . '`' : '';
$Entry = Helper::toPersian((string)($Index + 1)) . '. 👤*' . $Missing['name'] . '*' . $Phone_Note . "\n└─🔑`" . $Missing['uuid'] . "`\n";
if (mb_strlen($Chunk . $Entry) > 2800) {
TelegramClient::sendMessage($Context->ChatId, $Chunk . Helper::adminFooter(), TelegramClient::inlineKeyboard($Action_Nav));
$Chunk = $Missing_Header;
}
$Chunk .= $Entry;
}

if ($Chunk !== $Missing_Header) {
TelegramClient::sendMessage($Context->ChatId, $Chunk . Helper::adminFooter(), TelegramClient::inlineKeyboard($Action_Nav));
}
}

if ($Duplicate_Tg_Rows !== []) {
$Dup_Text = self::header($Context, 'تضاد آیدی عددی در سرور')
. "⚠️*رکوردهای با `telegram_id` تکراری در پاسخ سرور (نسخه فعال/جدیدتر نگه داشته شد):*\n➖➖➖➖➖➖➖➖➖\n";
foreach (array_slice($Duplicate_Tg_Rows, 0, 15) as $Dup) {
$Dup_Text .= '• ' . $Dup['name'] . ' (`' . Helper::toPersian((string)$Dup['telegram_id']) . '`) — `' . $Dup['uuid'] . "`\n";
}
TelegramClient::sendMessage($Context->ChatId, mb_substr($Dup_Text, 0, 3200) . Helper::adminFooter(), TelegramClient::inlineKeyboard($Action_Nav));
}
}

private static function unwrapServerUserRows(mixed $Json): ?array {
if (!is_array($Json)) return null;
foreach (['items', 'users', 'data', 'results', 'records'] as $Key) {
if (isset($Json[$Key]) && is_array($Json[$Key])) {
return $Json[$Key];
}
}
return array_is_list($Json) ? $Json : null;
}

private static function buildBulkUserRow(array $Row, int $Telegram_ID, string $Uuid): array {
$Raw_Name = trim((string)($Row['name'] ?? ''));
if (method_exists('Helper', 'stripZwnj')) {
$Raw_Name = trim((string)(preg_replace('/\s+/u', ' ', Helper::stripZwnj($Raw_Name)) ?? $Raw_Name));
}
$Is_Placeholder = $Raw_Name === '' || $Raw_Name === '_' || $Raw_Name === 'کاربر' || $Raw_Name === 'کاربر آمبرلا' || preg_match('/^user-[0-9]+$/', $Raw_Name) === 1;
$Display_Name = mb_substr($Is_Placeholder ? 'کاربر' : $Raw_Name, 0, 190);

$Comment = trim((string)($Row['comment'] ?? ''));
$Phone = null;
$Operator = null;
if (method_exists('Helper', 'normalizePhone') && method_exists('Helper', 'validatePhone')) {
$Candidate_Phone = Helper::normalizePhone(trim((string)($Row['phone'] ?? '')));
if ($Candidate_Phone === '' || !Helper::validatePhone($Candidate_Phone)) {
$Candidate_Phone = Helper::normalizePhone($Comment);
}
if ($Candidate_Phone !== '' && Helper::validatePhone($Candidate_Phone)) {
$Phone = $Candidate_Phone;
if (method_exists('Helper', 'detectOperator')) {
$Operator = Helper::detectOperator($Candidate_Phone);
}
}
}

$Package_Days = max(0, (int)($Row['package_days'] ?? 0));
$Subscription_Label = null;
if ($Package_Days > 0) {
$Subscription_Label = (method_exists('Helper', 'durationLabel') && !in_array($Package_Days, [1, 7, 30, 31, 60, 90, 180, 360, 365, 730], true))
? Helper::durationLabel($Package_Days)
: self::packageLabel($Package_Days);
}

$Date_Fields = (class_exists('Common') && method_exists('Common', 'subscriptionFieldsFromServer'))
? Common::subscriptionFieldsFromServer($Row)
: [];
$Start_Raw = substr(trim((string)($Row['start_date'] ?? '')), 0, 10);
$Start_Date_Persian = (string)($Date_Fields['Package_Start_Date'] ?? '');
$End_Date_Persian = (string)($Date_Fields['Expiration_Date'] ?? '');
$End_Timestamp = (int)($Date_Fields['Expiration_Time_Stamp'] ?? 0);

if ($Start_Date_Persian === '' && preg_match('/^\d{4}-\d{2}-\d{2}$/', $Start_Raw) === 1) {
try {
$Start_Date_Persian = Helper::gregorianToJalali($Start_Raw);
} catch (Throwable) { $Start_Date_Persian = ''; }
}
if ($End_Timestamp <= 0 && $Package_Days > 0 && preg_match('/^\d{4}-\d{2}-\d{2}$/', $Start_Raw) === 1) {
try {
$Stamp = strtotime($Start_Raw . ' +' . $Package_Days . ' days');
if ($Stamp !== false && $Stamp > 0) {
$End_Timestamp = $Stamp;
$End_Gregorian = (new DateTimeImmutable('@' . $End_Timestamp))->setTimezone(new DateTimeZone('Asia/Tehran'))->format('Y-m-d');
$End_Date_Persian = Helper::gregorianToJalali($End_Gregorian);
}
} catch (Throwable) {}
}

$Usage_Limit = round(max(0.0, (float)($Row['usage_limit_GB'] ?? 0)), 2);
$Used_Usage = round(max(0.0, (float)($Row['current_usage_GB'] ?? 0)), 2);
$Remaining_Usage = round(max(0.0, $Usage_Limit - $Used_Usage), 2);
$Percent_Usage = $Usage_Limit > 0 ? round(min(100.0, ($Used_Usage / $Usage_Limit) * 100), 2) : 0.0;

$Server_Is_Active = !empty($Row['is_active']) ? 1 : 0;
$Server_Enable = (!array_key_exists('enable', $Row) || !empty($Row['enable'])) ? 1 : 0;
$Last_Online = trim((string)($Row['last_online'] ?? ''));
if ($Last_Online === '' || $Last_Online === '0001-01-01 00:00:00') {
$Last_Online = null;
} else {
$Last_Online = mb_substr($Last_Online, 0, 50);
}

$Now_Tehran = (new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran')))->format('Y-m-d H:i:s');
$Registered_At = $Now_Tehran;
if (preg_match('/^(\d{4})-(\d{2})-(\d{2})$/', $Start_Raw, $D_Match) === 1) {
$Year = (int)$D_Match[1];
if ($Year >= 1971 && $Year <= 2037) {
$Registered_At = $Start_Raw . ' 00:00:00';
}
}

$NonEmptyOrNull = static function (mixed $Value): ?string {
$S = trim((string)$Value);
return $S !== '' ? $S : null;
};

return [
'Telegram_ID' => $Telegram_ID,
'Chat_ID' => $Telegram_ID,
'First_Name' => $Display_Name,
'Full_Name' => $Display_Name,
'Phone' => $Phone,
'Operator' => $Operator,
'Client_ID' => $Uuid,
'Client_Status' => ($Server_Is_Active === 1 && $Server_Enable === 1) ? '✅فعال' : '🚫غیر فعال',
'Subscription' => $Subscription_Label,
'Free_Plan_Claimed' => 0,
'Is_Blocked' => 0,
'Balance' => 0,
'Package_Duration' => $Package_Days > 0 ? (string)$Package_Days : null,
'Package_Start_Date' => $Start_Date_Persian !== '' ? $Start_Date_Persian : null,
'Expiration_Date' => $End_Date_Persian !== '' ? $End_Date_Persian : null,
'Expiration_Time_Stamp' => $End_Timestamp > 0 ? $End_Timestamp : null,
'Total_Usage_GB' => $Usage_Limit,
'Used_Usage_GB' => $Used_Usage,
'Remaining_Usage_GB' => $Remaining_Usage,
'Percent_Usage' => $Percent_Usage,
'ED_25519_Private_Key' => $NonEmptyOrNull($Row['ed25519_private_key'] ?? ''),
'ED_25519_Public_Key' => $NonEmptyOrNull($Row['ed25519_public_key'] ?? ''),
'WireGuard_Private_Key' => $NonEmptyOrNull($Row['wg_pk'] ?? ''),
'WireGuard_Public_Key' => $NonEmptyOrNull($Row['wg_pub'] ?? ''),
'WireGuard_PSK' => $NonEmptyOrNull($Row['wg_psk'] ?? ''),
'Last_Online' => $Last_Online,
'Server_Comment' => $Comment,
'Server_Enable' => $Server_Enable,
'Server_Is_Active' => $Server_Is_Active,
'Deactivation_Message' => null,
'Channel_Client_Disabled_At' => null,
'Registered_At' => $Registered_At,
'Profile_Updated_At' => $Now_Tehran,
];
}

private static function refreshUserData(Context $Context, string $Identifier): void {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
$Raw = (string)preg_replace('/\r\n?/', "\n", trim($Identifier));
$Raw = Helper::toEnglish($Raw);
$Lines = array_values(array_filter(array_map('trim', explode("\n", $Raw)), static fn($L) => $L !== ''));
$Uuid_Regex = '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i';
$Uuids = [];
$Refs = [];

foreach ($Lines as $Line) {
if ((bool)preg_match($Uuid_Regex, $Line)) {
$Uuids[] = strtolower($Line);
} else {
$Refs[] = $Line;
}
}

$Single_Error_Nav = [
[Menu::button('👤بروزرسانی تکی مجدد', 'admin_users_single_sync'), Menu::button('🔄بروزرسانی خودکار همه', 'admin_users_auto_sync')],
Menu::back('منوی قبلی', 'عملیات کلاینت سرور'),
Menu::adminHome(),
];

if (count($Uuids) > 1 || count($Refs) > 1) {
$Bulk_Disabled_Text = self::header($Context, 'بروزرسانی تکی داده کاربر')
. "❌*خطا: ورود گروهی غیرفعال شده است.*\n➖➖➖➖➖➖➖➖➖\n"
. "⚠️در این بخش فقط مشخصات *یک کاربر* (یک آیدی/شماره + یک شناسه `UUID`) قابل ثبت است.\n"
. "👌برای بروزرسانی همه کاربران، روی دکمه «🔄بروزرسانی خودکار همه» بزنید."
. Helper::adminFooter();
TelegramClient::sendMessage($Context->ChatId, $Bulk_Disabled_Text, TelegramClient::inlineKeyboard($Single_Error_Nav));
return;
}

if (count($Uuids) !== 1 || count($Refs) !== 1) {
$Error_Text = self::header($Context, 'بروزرسانی تکی داده کاربر')
. "❌*خطا: فرمت وارد شده صحیح نمی باشد.*\n➖➖➖➖➖➖➖➖➖\n"
. "⚠️لطفا آیدی عددی (یا شماره موبایل) و شناسه کلاینت (`UUID`) یک کاربر را در دو خط وارد کنید:\n\n"
. "`۶۲۴۸۷۴۲۷۰۵`\n"
. "`970f3fa0-3714-4d9a-a95d-8c4ddd696bfd`"
. Helper::adminFooter();
TelegramClient::sendMessage($Context->ChatId, $Error_Text, TelegramClient::inlineKeyboard($Single_Error_Nav));
return;
}

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🔄در حال دریافت اطلاعات از سرور...', false);
}

self::processUpdatePair($Context, (string)$Refs[0], (string)$Uuids[0]);
}

private static function processUpdatePair(Context $Context, string $Provided_User_Ref, string $Provided_Uuid): string {
$Provided_User_Ref = trim($Provided_User_Ref);
$Resolved_User = Repository::findUserByIdentifier($Provided_User_Ref);
$Normalized_Ref_Phone = (method_exists('Helper', 'normalizePhone') && method_exists('Helper', 'validatePhone'))
? Helper::normalizePhone($Provided_User_Ref)
: '';
$Is_Ref_Phone = $Normalized_Ref_Phone !== '' && Helper::validatePhone($Normalized_Ref_Phone);
$Provided_User_Id = $Resolved_User !== null
? (int)($Resolved_User['Telegram_ID'] ?? 0)
: ($Is_Ref_Phone ? 0 : (int)preg_replace('/[^0-9]/', '', $Provided_User_Ref));

$Single_Action_Nav = [
[Menu::button('👤بروزرسانی تکی مجدد', 'admin_users_single_sync'), Menu::button('🔄بروزرسانی خودکار همه', 'admin_users_auto_sync')],
Menu::back('منوی قبلی', 'بروز رسانی داده های کاربران اول'),
Menu::adminHome(),
];

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '🔄در حال دریافت اطلاعات از سرور...', false);
}

$Loading_Text = self::header($Context) . " *🔄در حال دریافت اطلاعات از سرور آمبرلا...\n➖➖➖➖➖➖➖➖➖\n⚠️نکته:این عملیات ممکن است کمی طول بکشد." . Helper::adminFooter();

if ($Context->MessageId !== null) {
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Loading_Text, TelegramClient::inlineKeyboard([
Menu::adminHome(),
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
TelegramClient::sendMessage($Context->ChatId, $Error_Text, TelegramClient::inlineKeyboard($Single_Action_Nav));
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

if ($Target_Telegram_ID <= 0) {
$No_Tg_Text = self::header($Context, 'بروزرسانی تکی داده کاربر')
. "❌*خطا: آیدی عددی تلگرام برای این کاربر مشخص نشد.*\n➖➖➖➖➖➖➖➖➖\n"
. "⚠️کاربر با شماره/شناسه وارد شده هنوز در دیتابیس ثبت نشده و روی سرور هم مقدار `telegram_id` خالی است.\n"
. "👌لطفا *آیدی عددی تلگرام* کاربر را همراه با شناسه کلاینت (`{$Server_UUID}`) وارد کنید."
. Helper::adminFooter();
TelegramClient::sendMessage($Context->ChatId, $No_Tg_Text, TelegramClient::inlineKeyboard($Single_Action_Nav));
return "❌فاقد آیدی عددی — `{$Server_UUID}`";
}

$Remaining = max(0, $Server_Usage_Limit - $Server_Used);
$Percent = $Server_Usage_Limit > 0 ? round(($Server_Used / $Server_Usage_Limit) * 100, 1) : 0;
$Date_Fields = (class_exists('Common') && method_exists('Common', 'subscriptionFieldsFromServer'))
? Common::subscriptionFieldsFromServer($Data)
: [];
$Start_Date_Persian = (string)($Date_Fields['Package_Start_Date'] ?? '');
$End_Date_Persian = (string)($Date_Fields['Expiration_Date'] ?? '');
$End_Timestamp = (int)($Date_Fields['Expiration_Time_Stamp'] ?? 0);

if ($Start_Date_Persian === '' && $Server_Start_Date !== '') {
try {
$Start_Date_Persian = Helper::gregorianToJalali(substr($Server_Start_Date, 0, 10));
}

catch (Throwable) { $Start_Date_Persian = ''; }
}

if ($End_Timestamp <= 0 && $Server_Start_Date !== '' && $Server_Package_Days > 0) {
try {
$End_Timestamp = strtotime(substr($Server_Start_Date, 0, 10) . ' +' . $Server_Package_Days . ' days');
$End_Date = (new DateTimeImmutable('@' . $End_Timestamp))->setTimezone(new DateTimeZone('Asia/Tehran'))->format('Y-m-d');
$End_Date_Persian = Helper::gregorianToJalali($End_Date);
}

catch (Throwable) { $End_Date_Persian = ''; }
}

$Remaining_Time_Label = $End_Timestamp > 0
? Helper::remainingDuration($End_Timestamp)
: Helper::remainingDuration((int)($Local_User['Expiration_Time_Stamp'] ?? 0));

$Duration_Label = (method_exists('Helper', 'durationLabel') && $Server_Package_Days > 0 && !in_array($Server_Package_Days, [1, 7, 30, 31, 60, 90, 180, 360, 365, 730], true))
? Helper::durationLabel($Server_Package_Days)
: self::packageLabel($Server_Package_Days);
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

$Clean_Server_Name = trim($Server_Name);
if (method_exists('Helper', 'stripZwnj')) {
$Clean_Server_Name = trim((string)(preg_replace('/\s+/u', ' ', Helper::stripZwnj($Clean_Server_Name)) ?? $Clean_Server_Name));
}
$Server_Name_Is_Placeholder = $Clean_Server_Name === '' || $Clean_Server_Name === '_' || $Clean_Server_Name === 'کاربر' || $Clean_Server_Name === 'کاربر آمبرلا' || preg_match('/^user-[0-9]+$/', $Clean_Server_Name) === 1;
$Local_Full_Name = trim((string)($Local_User['Full_Name'] ?? ''));
$Display_Name = (!$Server_Name_Is_Placeholder) ? $Clean_Server_Name : ($Local_Full_Name !== '' ? $Local_Full_Name : 'کاربر');
$Phone = (string)($Local_User['Phone'] ?? '');

if ($Phone === '' && $Server_Comment !== '') {
$Phone = $Server_Comment;
}

$Operator = Helper::detectOperator($Phone);

$Operator_Label = $Operator !== '' ? $Operator : 'نا مشخص';
$Server_Active_Effective = $Server_Is_Active && $Server_Enable;
$Update_Payload = [
'Client_ID' => $Server_UUID,
'Channel_Client_Disabled_At' => null,
'Client_Status' => $Server_Active_Effective ? '✅فعال' : '🚫غیر فعال',
'Deactivation_Message' => $Server_Active_Effective ? null : ($Local_User['Deactivation_Message'] ?? null),
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
'Profile_Updated_At' => (new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran')))->format('Y-m-d H:i:s'),
];

if ($Phone !== '') {
$Update_Payload['Phone'] = $Phone;
}

if ($Target_Telegram_ID > 0) {
try {
$Db = Database::getInstance();
if (method_exists($Db, 'execute')) {
$Db->execute(
'UPDATE `Users` SET `Client_ID` = NULL WHERE `Client_ID` = ? AND `Telegram_ID` <> ?',
[$Server_UUID, $Target_Telegram_ID]
);
}
} catch (Throwable) {}

if (is_array($Local_User) && !empty($Local_User)) {
Repository::updateUser($Target_Telegram_ID, $Update_Payload);
}

else {
$Insert_Payload = array_merge($Update_Payload, [
'Telegram_ID' => $Target_Telegram_ID,
'Chat_ID' => $Target_Telegram_ID,
'First_Name' => $Display_Name,
'Full_Name' => $Display_Name,
'Is_Blocked' => 0,
'Balance' => 0,
'Free_Plan_Claimed' => 0,
'Registered_At' => (new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran')))->format('Y-m-d H:i:s'),
]);
Database::getInstance()->insert('Users', $Insert_Payload);
}

$Server_Push = [];
if ($Target_Telegram_ID > 0 && $Server_Telegram_ID !== $Target_Telegram_ID) {
$Server_Push['telegram_id'] = $Target_Telegram_ID;
}
if ($Server_Name_Is_Placeholder && $Local_Full_Name !== '') {
$Server_Push['name'] = $Local_Full_Name;
}
if ($Server_Comment === '' && $Phone !== '') {
$Server_Push['comment'] = $Phone;
}
if ($Server_Push !== []) {
$Link_Response = ServerClient::updateUser($Server_UUID, $Server_Push);

if (($Link_Response['StatusCode'] ?? 0) >= 300) {
self::notifyAdminServerError('لینک کاربر به تلگرام', $Target_Telegram_ID, $Display_Name, $Link_Response['StatusCode'] ?? 0, (string)($Link_Response['Body'] ?? ''));
}
}

if ($Target_Telegram_ID > 0 && $Server_UUID !== '' && class_exists('Database')) {
try {
$Db = Database::getInstance();
if (method_exists($Db, 'execute')) {
$Db->execute(
'UPDATE `App_Devices` SET `Telegram_ID` = ? WHERE `User_UUID` = ? AND (`Telegram_ID` IS NULL OR `Telegram_ID` = 0)',
[$Target_Telegram_ID, $Server_UUID]
);
$Db->execute(
'UPDATE `App_Sessions` SET `Telegram_ID` = ? WHERE `User_UUID` = ? AND (`Telegram_ID` IS NULL OR `Telegram_ID` = 0)',
[$Target_Telegram_ID, $Server_UUID]
);
}
} catch (Throwable) {}
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
. "📶*اپراتور پایه (پیش شماره):* {$Operator_Label}\n"
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
. "✅*تمام مقادیر در دیتابیس ذخیره شدند.*";

// The 4096-character limit would cut the footer off mid-way, so the body is
// trimmed first and the standard footer is added after it.
$Detail_Text = mb_substr($Detail_Text, 0, 3800) . Helper::adminFooter();
TelegramClient::sendMessage($Context->ChatId, $Detail_Text, TelegramClient::inlineKeyboard($Single_Action_Nav));

if ($Target_Telegram_ID > 0) {
TelegramClient::sendSystemMessage($Target_Telegram_ID, Common::greet(new Context([], $Target_Telegram_ID, $Target_Telegram_ID, $Display_Name, false, null, null, null, null), 'بروز رسانی اشتراک') . "🔄لحظاتی پیش اطلاعات اشتراک شما توسط مدیریت بروزرسانی گردید." . Helper::userFooter(), TelegramClient::inlineKeyboard([Common::backTo('👤پروفایل کاربری', 'پروفایل کاربری'), Menu::userHome()]));
}

return "✅{$Display_Name} — `{$Server_UUID}`" . ($Target_Telegram_ID > 0 ? ' (شناسه: ' . Helper::toPersian((string)$Target_Telegram_ID) . ')' : '');
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
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard([
[['text' => '🔁بروزرسانی', 'callback_data' => 'گزارش مالی']],
[['text' => '📅گزارش روزانه دقیق', 'callback_data' => 'گزارش روزانه']],
Menu::back('منوی قبلی', 'منوی گزارش'), Menu::adminHome(),
]));
}

public static function ticketAdminMenu(Context $Context, int $Page = 0): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Temp_UID' => null, 'Broadcast_Mode' => null]);
$Waiting_Count = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Tickets` WHERE `Status` IN ('open','pending')");
$Answered_Count = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Tickets` WHERE `Status` = 'answered'");
$Closed_Count = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Tickets` WHERE `Status` = 'closed'");
$Total_Count = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Tickets`");
$PageCount = max(1, (int)ceil(($Waiting_Count + $Answered_Count) / 8));
$Page = max(0, min($Page, $PageCount - 1));
$Tickets = Repository::openTickets(8, $Page * 8);

$Text = Helper::adminGreeting($Context, 'مدیریت تیکت ها')
. Menu::section('🎫', 'آمار تیکت ها', [
'🟡در انتظار پاسخ: *' . Helper::toPersian((string)$Waiting_Count) . '*',
'🟢پاسخ داده شده: *' . Helper::toPersian((string)$Answered_Count) . '*',
'⚫بسته شده: *' . Helper::toPersian((string)$Closed_Count) . '*',
'📋کل تیکت ها: *' . Helper::toPersian((string)$Total_Count) . '*',
]);

$Buttons = [];

if (empty($Tickets)) {
$Text .= '✅*هیچ تیکت بازی وجود ندارد.*' . Helper::adminFooter();
}

else {
$Text .= '📌*برای مشاهده و پاسخ دادن، تیکت مورد نظر را انتخاب کنید:*' . Helper::adminFooter();

foreach ($Tickets as $T) {
$Priority_Icon = ['low' => '🟢', 'medium' => '🟡', 'high' => '🟠', 'urgent' => '🔴'][$T['Priority']] ?? '🟡';
$Buttons[] = [['text' => "{$Priority_Icon} #{$T['ID']} - " . mb_substr((string)$T['Subject'], 0, 30), 'callback_data' => 'ticket_view:' . $T['ID']]];
}
}

$Text .= Menu::pageLabel($Page, $PageCount);
$Buttons = array_merge($Buttons, Menu::pages($Page, $PageCount, 'admin_tickets_page:'));
$Buttons[] = Menu::adminHome();
self::logMenuProblems('tickets', $Buttons);
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Buttons));
}

/** سازگاری با دکمه های قدیمی: هدایت به صفحه یکپارچه مدیریت تیکت ها. */
public static function ticketAdminList(Context $Context): void {
self::ticketAdminMenu($Context);
}

public static function ticketAdminView(Context $Context, int $Ticket_ID, int $Page = 0): void {
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

$Thread = '';
foreach ($Messages as $Msg) {
$Count++;
$Sender = $Msg['Sender_Type'] === 'admin' ? '🛡ادمین' : '👤کاربر';
$Thread .= "{$Sender}: " . ($Msg['Message'] ?? '[مدیا]') . "\n";

if (TicketMedia::decode($Msg) !== null) {
$Thread .= "📎[پیوست؛ از دکمه پیوست های تیکت باز کنید]\n";
}
}

[$ThreadPage, $Page, $PageCount] = Menu::textPage($Thread, $Page);
$Text .= Menu::pageLabel($Page, $PageCount) . $ThreadPage;

$Text .= Helper::adminFooter();
$Buttons = array_merge(Menu::pages($Page, $PageCount, 'admin_ticket_messages:' . $Ticket_ID . ':'), [
[Menu::button('📎پیوست های تیکت', 'ticket_attachments:' . $Ticket_ID . ':0')],
[['text' => '✏️پاسخ', 'callback_data' => 'ticket_reply:' . $Ticket_ID]],
[['text' => '✅بستن تیکت', 'callback_data' => 'ticket_close:' . $Ticket_ID]],
], Menu::adminNav('مدیریت تیکت ها', 'مدیریت تیکت ها'));

TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, $Text, TelegramClient::inlineKeyboard($Buttons));
}

public static function ticketAdminReplyStart(Context $Context, int $Ticket_ID): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
Repository::updateUserSession($Context->UserId, ['Flow' => 'admin:ticket_reply_text', 'Temp_Ticket_ID' => $Ticket_ID]);
TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, Helper::adminGreeting($Context, "پاسخ به تیکت #{$Ticket_ID}") . "\n➖➖➖➖➖➖➖➖➖\n✏️📝پاسخ خود را وارد کنید:" . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('تیکت', 'ticket_view:' . $Ticket_ID)));
}

public static function ticketAdminReplySend(Context $Context, string $Text): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
$Session = Repository::getUserSession($Context->UserId);
$Ticket_ID = (int)($Session['Temp_Ticket_ID'] ?? 0);

if ($Ticket_ID <= 0) return;
$Ticket = Repository::getTicket($Ticket_ID);

if ($Ticket === null) return;
if ($Ticket['Status'] === 'closed') return;
$Media = TicketMedia::extract($Context);
if (trim($Text) === '' && $Media === null) return;
Repository::addTicketMessage($Ticket_ID, $Context->UserId, 'admin', $Text, null, $Media !== null ? json_encode($Media, JSON_UNESCAPED_UNICODE) : null);
$User = Repository::getUser((int)$Ticket['User_ID']);
$Chat_ID = (int)($User['Chat_ID'] ?? 0);

if ($Chat_ID > 0) {
TelegramClient::sendReadableMessage($Chat_ID, null, Helper::frame('کاربر', (string)($User['Full_Name'] ?? ''), 'پاسخ تیکت', (int)$Ticket['User_ID']) . "📨پاسخ تیکت #{$Ticket_ID}\n➖➖➖➖➖➖➖➖➖\n{$Text}\n➖➖➖➖➖➖➖➖➖\n👇برای مشاهده و پاسخ به منوی تیکت بروید." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '🎫تیکت های من', 'callback_data' => 'تیکت های من']],
Menu::userHome(),
]));
if ($Media !== null && !TicketMedia::send($Chat_ID, $Media)) TelegramClient::sendMessage($Context->ChatId, '⚠️ارسال پیوست به کاربر ناموفق بود؛ پیوست در تیکت ذخیره شده است.');
}

TelegramClient::sendMessage($Context->ChatId, Helper::adminGreeting($Context, "پاسخ به تیکت #{$Ticket_ID}") . "\n➖➖➖➖➖➖➖➖➖\n✅پاسخ در تیکت ثبت شد. برای افزودن پیوست بعدی آن را ارسال کنید؛ برای پایان دکمه بازگشت را بزنید." . Helper::adminFooter(), TelegramClient::inlineKeyboard(Menu::adminNav('مدیریت تیکت ها', 'مدیریت تیکت ها')));
}

public static function ticketAdminClose(Context $Context, int $Ticket_ID): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
Repository::closeTicket($Ticket_ID);
TelegramClient::answerCallbackQuery($Context->CallbackId, '✅تیکت بسته شد', false);
self::ticketAdminMenu($Context);
}

public static function smsTemplateMenu(Context $Context): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, self::header($Context) . " *❌این بخش غیرفعال شده است.*" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
Menu::adminHome(),
]));
}

public static function smsTemplateEdit(Context $Context, string $Code): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }

TelegramClient::editOrSendMessage($Context->ChatId, $Context->MessageId, self::header($Context) . " *❌این بخش غیرفعال شده است.*" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
Menu::adminHome(),
]));
}

public static function smsTemplateUpdate(Context $Context, string $Text): void {
if (!$Context->isAdmin()) { self::denyAccess($Context); return; }
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Template_Code' => null]);
TelegramClient::sendMessage($Context->ChatId, self::header($Context) . " *❌این بخش غیرفعال شده است.*" . Helper::adminFooter(), TelegramClient::inlineKeyboard([
Menu::adminHome(),
]));
}
}
?>