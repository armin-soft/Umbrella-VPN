<?php
declare(strict_types=1);
$MediaSource = (string)file_get_contents(dirname(__DIR__) . '/Bot/Ticket-Media.php');
eval(substr($MediaSource, strpos($MediaSource, 'final class TicketMedia {')));


// Exercise production menu and routing methods with in-memory dependencies only.
require_once dirname(__DIR__) . '/Bot/Menu.php';
if (!function_exists('mb_strlen')) {
function mb_strlen(string $Text): int { return count(preg_split('//u', $Text, -1, PREG_SPLIT_NO_EMPTY) ?: []); }
}
if (!function_exists('mb_substr')) {
function mb_substr(string $Text, int $Start, ?int $Length = null): string { return implode('', array_slice(preg_split('//u', $Text, -1, PREG_SPLIT_NO_EMPTY) ?: [], $Start, $Length)); }
}
final class Context {
public int $UserId = 1;
public int $ChatId = 1;
public ?int $MessageId = 10;
public ?string $CallbackId = 'test';
public bool $IsCallback = true;
public ?string $CallbackData = '';
public function __construct(private bool $Admin = true) {}
public function isAdmin(): bool { return $this->Admin; }
}
final class Repository {
public static array $Session = [];
public static array $Settings = [];
public static function nightlyReportEnabled(int $Id): bool { return (self::$Settings['nightly_' . $Id] ?? '1') !== '0'; }
public static function setNightlyReportEnabled(int $Id, bool $On): void { self::$Settings['nightly_' . $Id] = $On ? '1' : '0'; }
public static array $User = [];
public static array $Updates = [];
public static function updateUser(int $Id, array $Fields): void { self::$Updates[] = $Fields; self::$User = array_replace(self::$User, $Fields); }
public static function getBalance(int $Id): float { return 1000000; }
public static array $Tickets = [];
public static function getTicket(int $Id): ?array { return $Id === 42 ? ['ID' => 42, 'User_ID' => 1, 'Subject' => 'subject', 'Status' => 'open', 'Category' => 'other', 'Priority' => 'medium'] : null; }
public static function getTicketMessages(int $Id): array { return [['Sender_Type' => 'user', 'Message' => str_repeat('متن ', 1500), 'Photo_File_ID' => null]]; }
public static function userTickets(int $Id): array { return self::$Tickets; }
public static function openTickets(int $Limit = 100, int $Offset = 0): array { return array_slice(self::$Tickets, $Offset, $Limit); }
public static function getBlockedUsers(): array { return []; }
public static function getUser(int $Id): array { return self::$User; }
public static function updateUserSession(int $Id, array $Values): void { self::$Session = array_replace(self::$Session, $Values); }
public static function getUserSession(int $Id): array { return self::$Session; }
public static function setSetting(string $Key, string $Value): void { self::$Settings[$Key] = $Value; }
public static function getSetting(string $Key, string $Default = ''): string { return (string)(self::$Settings[$Key] ?? $Default); }
}
final class ServerClient {
public static ?array $Response = null;
public static function getUser(string $Id): array { return self::$Response ?? ['StatusCode' => 200, 'Json' => ['uuid' => $Id, 'is_active' => true, 'enable' => true, 'usage_limit_GB' => 10, 'current_usage_GB' => 1]]; }
}
final class Common {
public static function greet(Context $Context, string $Section): string { return $Section; }
public static function isRobotOn(): bool { return (Repository::$Settings['Robot_Status'] ?? '🟢روشن') === '🟢روشن'; }
public static function syncSubscriptionFromServer(array $User, ?array $Live = null): array { return $User; }
}
final class Database {
public static function getInstance(): self { return new self(); }
public static array $Devices = [];
public static string $LastQuery = '';
public static array $LastParams = [];
public function scalar(string $Query, array $Params = [], int $Default = 0): int {
if (str_contains($Query, 'Tickets')) return str_contains($Query, "'answered'") || str_contains($Query, "'closed'") ? 0 : count(Repository::$Tickets);
if (str_contains($Query, 'App_Devices')) {
$Devices = str_contains($Query, '`Is_Trusted` = 1')
? array_values(array_filter(self::$Devices, static fn(array $D): bool => (int)($D['Is_Trusted'] ?? 0) === 1))
: self::$Devices;
return count($Devices);
}
return 0;
}
public function fetch(string $Query, array $Params = []): ?array {
return null;
}
public function fetchAll(string $Query, array $Params = []): array {
self::$LastQuery = $Query;
self::$LastParams = $Params;
if (str_contains($Query, 'App_User_Activity')) return [];
$Devices = str_contains($Query, '`Is_Trusted` = 1')
? array_values(array_filter(self::$Devices, static fn(array $D): bool => (int)($D['Is_Trusted'] ?? 0) === 1))
: self::$Devices;
if (count($Params) < 2) return $Devices;
return array_slice($Devices, $Params[1], $Params[0]);
}
}
final class BotConfig {
public const KEY_EMERGENCY_URL = 'Emergency_Url';
public static function getPlanPrice(int|string $Key): float { return 1000; }
public static function showEmergency(): bool { return (Repository::$Settings['Emergency_Show'] ?? '0') === '1'; }
public static function setShowEmergency(bool $Show): void { Repository::$Settings['Emergency_Show'] = $Show ? '1' : '0'; }
public static function emergencyUrl(): string { return 'https://example.invalid/emg'; }
public static function source(string $Key): string { return 'env'; }
public static function isNowruzMenuConfigured(): bool { return (Repository::$Settings['Nowruz_Menu_Enabled'] ?? '0') === '1'; }
public static function isNowruzSeasonActive(): bool { return true; }
public static function isNowruzMenuEnabled(): bool { return self::isNowruzMenuConfigured() && self::isNowruzSeasonActive(); }
public static function setNowruzMenuEnabled(bool $Show): void { Repository::$Settings['Nowruz_Menu_Enabled'] = $Show ? '1' : '0'; }
public static function hasClaimedNowruz(int $UserId = 0, string $Uuid = '', ?string $Season = null): bool {
return (Repository::$Settings['Nowruz_Claimed_' . $UserId] ?? '0') === '1';
}
}
final class AppFilter {
public const MAX_CUSTOM_DOMAINS = 200;
public const DOMAINS_PER_PAGE = 8;
public const BOT_CATEGORIES = [
'adult' => 'محتوای بزرگسال',
'gambling' => 'شرط بندی',
'ads' => 'تبلیغات',
];
public static function loadGlobal(): array {
return ['enabled' => false, 'categories' => ['adult'], 'custom_domains' => ['example.com']];
}
public static function summary(array $Settings): string { return 'خلاصه'; }
public static function domainToken(string $Domain): string { return substr(sha1($Domain), 0, 12); }
}
final class Helper {
public static function formatCurrency(float $Value): string { return (string)$Value; }
public static function remainingDuration(int $Stamp): string { return (string)$Stamp; }
public static function ticketCategoryLabel(string $Value): string { return $Value; }
public static function ticketPriorityLabel(string $Value): string { return $Value; }
public static function userGreeting(Context $Context, string $Section): string { return $Section; }
public static function adminGreeting(Context $Context, string $Section): string { return $Section; }
public static function adminFooter(): string { return ''; }
public static function userFooter(): string { return ''; }
public static function toPersian(string $Value): string { return $Value; }
public static function normalizePhone(string $Value): string { return $Value; }
public static function formatDateTimeText(string $Value): string { return $Value; }
public static function formatBytes(int $Bytes): string { return $Bytes . ' B'; }
}
final class TelegramClient {
public static array $Last = [];
public static string $Text = "";
public static function inlineKeyboard(array $Rows): array { return ['inline_keyboard' => $Rows]; }
public static function sendMessage(int $ChatId, string $Text, array $Markup = []): void { self::$Last = $Markup; self::$Text = $Text; }
public static function editOrSendMessage(int $ChatId, ?int $MessageId, string $Text, array $Markup = []): void { self::$Last = $Markup; self::$Text = $Text; }
public static function editMessageText(int $ChatId, int $MessageId, string $Text, array $Markup = []): void { self::$Last = $Markup; self::$Text = $Text; }
public static function sendReadableMessage(int $ChatId, ?int $MessageId, string $Text, array $Markup = []): bool { self::$Last = $Markup; self::$Text = $Text; return true; }
public static function sendChatAction(int $ChatId): void {}
public static function answerCallbackQuery(?string $Id, string $Text, bool $Alert = false): void {}
}
// Skip production require_once side effects, but evaluate the entire original
// class declarations unchanged. Any unmocked dependency fails rather than doing I/O.
foreach (['AdminFlow' => 'Admin.php', 'UserFlow' => 'User.php', 'Dispatcher' => 'Dispatcher.php'] as $Class => $File) {
$Source = (string)file_get_contents(dirname(__DIR__) . '/Bot/' . $File);
$Start = strpos($Source, 'final class ' . $Class . ' {');
if ($Start === false) throw new RuntimeException('Missing class ' . $Class);
eval(preg_replace('/\?>\s*$/', '', substr($Source, $Start)));
}
$Passed = 0;
function check(bool $Ok, string $Name): void {
global $Passed;
if (!$Ok) throw new RuntimeException($Name);
$Passed++;
}
function calls(): array {
$Rows = TelegramClient::$Last['inline_keyboard'] ?? [];
check(Menu::problems($Rows) === [], 'valid rendered keyboard');
foreach ($Rows as $Row) {
check(count($Row) >= 1 && count($Row) <= 2, 'at most two buttons per row');
foreach ($Row as $Button) {
if (in_array($Button['text'], [Menu::BACK_LABEL, Menu::HOME_LABEL, Menu::ADMIN_HOME_LABEL], true)) check(count($Row) === 1, 'navigation stays on its own row');
}
}
return $Rows === [] ? [] : array_column(array_merge(...$Rows), 'callback_data');
}
$Menus = [
'menu' => ['مدیریت', null, ['خاموش کردن ربات', 'اعتبار حساب کاربری', 'جرایم', 'admin_devices_menu', 'admin_content_filter', 'admin_accounts_menu', 'عملیات کلاینت سرور', 'پیکربندی سرور', 'منوی گزارش', 'منوی پیامک', 'مدیریت تیکت ها', 'admin_subscriptions_menu', 'منوی سیستم', 'بروز رسانی']],
'creditMenu' => ['اعتبار حساب کاربری', 'مدیریت', ['افزایش اعتبار اول', 'کسر اعتبار اول', 'مشاهده اعتبار اول']],
'crimes' => ['جرایم', 'مدیریت', ['مسدودیت اول', 'رفع مسدودیت اول', 'مشاهده مسدودی ها']],
'devicesMenu' => ['admin_devices_menu', 'مدیریت', ['admin_user_monitor', 'admin_devices', 'device_limit_menu', 'admin_devices_delete_all_menu']],
'accountsMenu' => ['admin_accounts_menu', 'مدیریت', ['admin_users', 'حذف کاربر اول', 'منقضی اشتراک اول']],
'serverClientsMenu' => ['عملیات کلاینت سرور', 'مدیریت', ['فعالسازی کلاینت اول', 'غیر فعالسازی کلاینت اول', 'بروز رسانی داده های کاربران اول']],
'serverConfig' => ['پیکربندی سرور', 'مدیریت', ['وضعیت سرور', 'سرویس های سرور', 'بروز رسانی میزان استفاده اول', 'تنظیمات ربات']],
'reportMenu' => ['منوی گزارش', 'مدیریت', ['آمار کلی', 'گزارش روزانه', 'گزارش مالی', 'رتبه بندی']],
'smsMenu' => ['منوی پیامک', 'مدیریت', ['ارسال پیامک تکی اول', 'ارسال پیامک همگانی اول', 'اطلاع رسانی اول', 'اطلاع رسانی سفارشی اول', 'اطلاع رسانی عدم استفاده', 'admin_app_announcement']],
'supportMenu' => ['admin_support_menu', 'مدیریت', []],
'ticketAdminMenu' => ['مدیریت تیکت ها', 'مدیریت', []],
'subscriptionsMenu' => ['admin_subscriptions_menu', 'مدیریت', ['cfg_pricing', 'cfg_links']],
'systemMenu' => ['منوی سیستم', 'مدیریت', ['پشتیبان گیری دیتابیس', 'تنظیم مجدد دیتابیس']],
];
$AdminWidths = [
'menu' => array_fill(0, 14, 1),
'creditMenu' => [2, 1, 1], 'crimes' => [2, 1, 1],
'devicesMenu' => [1, 1, 1, 1, 1], 'accountsMenu' => [1, 1, 1, 1],
'serverClientsMenu' => [2, 1, 1], 'serverConfig' => [2, 1, 1, 1],
'reportMenu' => [1, 1, 1, 1, 1], 'smsMenu' => [2, 2, 2, 1],
'supportMenu' => [1], 'ticketAdminMenu' => [1], 'subscriptionsMenu' => [1, 1, 1], 'systemMenu' => [1, 1, 1],
];
$Context = new Context();
$Route = new ReflectionMethod(Dispatcher::class, 'routeCallbackInner');
foreach ($Menus as $Method => [$Call, $Parent, $Actions]) {
$Expected = $Actions;
if ($Parent !== null && $Parent !== 'مدیریت') $Expected[] = $Parent;
if ($Parent !== null) $Expected[] = 'مدیریت';
foreach ([true, false] as $Callback) {
$Context->IsCallback = $Callback;
Repository::$Session = ['Flow' => 'admin:credit_add_uid', 'Temp_UID' => 123, 'Broadcast_Mode' => 'sms'];
AdminFlow::$Method($Context);
check(calls() === $Expected, $Method . ': exact actions and parent navigation');
check(array_map('count', TelegramClient::$Last['inline_keyboard']) === $AdminWidths[$Method], $Method . ': exact row grouping');
if ($Method === 'menu') {
$Buttons = array_merge(...TelegramClient::$Last['inline_keyboard']);
$Labels = array_column($Buttons, 'text', 'callback_data');
check(($Labels['admin_content_filter'] ?? null) === '🛡کنترل محتوا', 'content-filter menu uses the concise label');
}
check(Repository::$Session === ['Flow' => null, 'Temp_UID' => null, 'Broadcast_Mode' => null], $Method . ': cancels stale input');
check(Repository::$Settings === [], $Method . ': opening menu does not mutate settings');
}
$Context->IsCallback = true;
$Context->CallbackData = $Call;
$Route->invoke(null, $Context);
check(calls() === $Expected, $Method . ': dispatcher reaches correct category');
Repository::$Session = ['Flow' => 'untouched'];
TelegramClient::$Last = [];
$Guest = new Context(false);
$Guest->CallbackData = $Call;
$Route->invoke(null, $Guest);
check(calls() === ['منوی خدمات ربات'], $Method . ': non-admin only gets user home');
check(Repository::$Session === ['Flow' => 'untouched'], $Method . ': unauthorized access cannot clear session');
}
foreach (['usersMenu' => 'menu', 'databaseMenu' => 'systemMenu', 'serverHealthMenu' => 'serverConfig', 'serverSyncMenu' => 'serverConfig', 'serverNotifyMenu' => 'smsMenu'] as $Alias => $Target) {
AdminFlow::$Target($Context);
$Expected = TelegramClient::$Last;
AdminFlow::$Alias($Context);
check(TelegramClient::$Last === $Expected, $Alias . ': legacy alias leads to category');
}
foreach (['credit_add_uid' => 'اعتبار حساب کاربری', 'credit_sub_uid' => 'اعتبار حساب کاربری', 'view_uid' => 'اعتبار حساب کاربری', 'block_uid' => 'جرایم', 'unblock_uid' => 'جرایم', 'activate_uid' => 'عملیات کلاینت سرور', 'deactivate_uid' => 'عملیات کلاینت سرور', 'delete_uid' => 'admin_accounts_menu', 'expire_uid' => 'admin_accounts_menu'] as $Flow => $Parent) {
AdminFlow::startInput($Context, 'admin:' . $Flow, 'prompt');
check(calls() === [$Parent, 'مدیریت'], $Flow . ': input returns to correct submenu');
check(Repository::$Session['Flow'] === 'admin:' . $Flow, $Flow . ': input state preserved');
}
foreach ([false, true] as $On) {
AdminFlow::toggleRobot($Context, $On);
check(Common::isRobotOn() === $On, 'robot toggle sets intended state');
$Expected = $Menus['menu'][2];
$Expected[0] = $On ? 'خاموش کردن ربات' : 'روشن کردن ربات';
check(calls() === $Expected, 'toggle stays on main admin menu');
}
// Direct home entry and legacy support button open the same ticket list.
$Context->CallbackData = 'مدیریت تیکت ها';
$Route->invoke(null, $Context);
$DirectTickets = TelegramClient::$Last;
$DirectText = TelegramClient::$Text;
$Context->CallbackData = 'admin_support_menu';
$Route->invoke(null, $Context);
check(TelegramClient::$Last === $DirectTickets && TelegramClient::$Text === $DirectText, 'legacy support skips removed category');
check(!str_contains($DirectText, 'پشتیبانی و تیکت ها'), 'removed support category is not rendered');
check(TelegramClient::$Last['inline_keyboard'][0][0]['text'] === Menu::ADMIN_HOME_LABEL, 'ticket list retains correct admin home label');
// Reset is still a confirmation screen; merely opening it must not reset anything.
$Context->CallbackData = 'تنظیم مجدد دیتابیس';
$Route->invoke(null, $Context);
check(calls() === ['تایید تنظیم مجدد دیتابیس', 'منوی سیستم', 'مدیریت'], 'database reset confirmation is preserved');

// Parent navigation on the existing leaf screens (whose live data is not mocked).
$AdminSource = (string)file_get_contents(dirname(__DIR__) . '/Bot/Admin.php');
$LeafParents = [
'appDevicesMenu' => 'admin_devices_menu', 'deviceLimitMenu' => 'admin_devices_menu',
'blockedList' => 'جرایم', 'askUpdateUserData' => 'عملیات کلاینت سرور',
'globalStats' => 'منوی گزارش', 'dailyReport' => 'منوی گزارش',
'financialReport' => 'منوی گزارش', 'userRanking' => 'منوی گزارش',
'serverStatus' => 'پیکربندی سرور', 'serverServices' => 'پیکربندی سرور',
'updateAllUsages' => 'پیکربندی سرور', 'configMenu' => 'پیکربندی سرور',
'pricingMenu' => 'admin_subscriptions_menu', 'linksMenu' => 'admin_subscriptions_menu',
'databaseBackup' => 'منوی سیستم', 'databaseReset' => 'منوی سیستم',
'serverNotifyIdle' => 'منوی پیامک', 'appPushStart' => 'منوی پیامک', 'notifyAllStart' => 'منوی پیامک',
];
foreach ($LeafParents as $Method => $Parent) {
$Start = strpos($AdminSource, 'public static function ' . $Method . '(');
$Remaining = substr($AdminSource, $Start + 1);
preg_match('/(?:public|private) static function /', $Remaining, $Match, PREG_OFFSET_CAPTURE);
$Body = substr($Remaining, 0, $Match[0][1]);
check(str_contains($Body, "Menu::back('منوی قبلی', '{$Parent}')"), $Method . ': leaf returns to its category');
check(str_contains($Body, 'Menu::adminHome()'), $Method . ': leaf keeps main menu');
}
$UserMenus = [
'serviceMenu' => ['منوی خدمات ربات', ['user_subscriptions_menu', 'user_account_menu', 'user_device_menu', 'user_wallet_menu', 'user_stats_menu', 'app_download_menu', 'منوی پشتیبانی', 'تغییرات نسخه']],
'subscriptionsMenu' => ['user_subscriptions_menu', ['اشتراک آماده', 'اشتراک دلخواه', 'اشتراک رایگان اول']],
'walletMenu' => ['user_wallet_menu', ['شارژ اعتبار حساب کاربری', 'سابقه تراکنش']],
'accountMenu' => ['user_account_menu', ['پروفایل کاربری', 'ویرایش پروفایل']],
'deviceMenu' => ['user_device_menu', ['app_filter', 'app_bypass', 'app_2fa', 'app_devices']],
'statsMenu' => ['user_stats_menu', ['سابقه اشتراک', 'گزارش مصرف']],
'supportMenu' => ['منوی پشتیبانی', ['لیست تیکت های من', 'تیکت جدید']],
];
$UserWidths = [
'serviceMenu' => [1, 1, 1, 1, 1, 1, 1, 1],
'subscriptionsMenu' => [2, 1, 1], 'walletMenu' => [1, 1, 1],
'accountMenu' => [1, 1, 1], 'deviceMenu' => [1, 1, 1, 1, 1], 'statsMenu' => [2, 1], 'supportMenu' => [1, 1, 1],
];
foreach ($UserMenus as $Method => [$Call, $Actions]) {
$Expected = $Method === 'serviceMenu' ? $Actions : array_merge($Actions, ['منوی خدمات ربات']);
foreach ([true, false] as $Callback) {
$UserContext = new Context(false);
$UserContext->IsCallback = $Callback;
Repository::$Session = ['Flow' => 'custom_plan_days', 'Pending_Payment' => 'preserved'];
UserFlow::$Method($UserContext);
check(calls() === $Expected, 'user ' . $Method . ': correct ordered menu');
check(array_map('count', TelegramClient::$Last['inline_keyboard']) === $UserWidths[$Method], $Method . ': exact user row grouping');
check(Repository::$Session === ['Flow' => null, 'Pending_Payment' => 'preserved'], 'user category cancels input but preserves payment');
}
$UserContext->IsCallback = true;
$UserContext->CallbackData = $Call;
$Route->invoke(null, $UserContext);
check(calls() === $Expected, 'user ' . $Method . ': dispatcher routes category');
}
foreach (['singleSmsMenu' => 'single', 'notifySingleMenu' => 'notify', 'broadcastMenu' => 'broadcast', 'serverNotifyCustomStart' => 'custom'] as $Method => $Scope) {
AdminFlow::$Method($Context);
check(calls() === ['delivery_mode:' . $Scope . ':telegram', 'delivery_mode:' . $Scope . ':sms', 'delivery_mode:' . $Scope . ':app', 'delivery_mode:' . $Scope . ':all', 'منوی پیامک', 'مدیریت'], $Scope . ': four delivery channels and navigation');
foreach (['telegram', 'sms', 'app', 'all'] as $Mode) {
$Context->CallbackData = 'delivery_mode:' . $Scope . ':' . $Mode;
$Route->invoke(null, $Context);
check(Repository::$Session['Broadcast_Mode'] === $Mode, $Scope . ': selected channel preserved');
check(Repository::$Session['Flow'] === match ($Scope) { 'single' => 'admin:sms_single_uid', 'notify' => 'admin:notify_uid', default => 'admin:notify_broadcast_text' }, $Scope . ': correct next step');
}
$Guest = new Context(false);
Repository::$Session = ['Flow' => 'untouched'];
AdminFlow::selectDeliveryMode($Guest, $Scope, 'all');
check(Repository::$Session === ['Flow' => 'untouched'], 'delivery selection admin-only');
}
Repository::$User = ['Client_ID' => 'test', 'Subscription' => 'monthly', 'Client_Status' => 'فعال', 'Expiration_Time_Stamp' => time() + 86400];
$UserContext->CallbackData = 'nightly_report_off';
$Route->invoke(null, $UserContext);
check(!Repository::nightlyReportEnabled($UserContext->UserId), 'nightly preference saved off');
check(in_array('nightly_report_on', calls(), true), 'off state offers enable');
$Route->invoke(null, $UserContext);
check(!Repository::nightlyReportEnabled($UserContext->UserId), 'repeated off callback is idempotent');
$UserContext->CallbackData = 'nightly_report_on';
$Route->invoke(null, $UserContext);
check(Repository::nightlyReportEnabled($UserContext->UserId) && in_array('nightly_report_off', calls(), true), 'nightly preference saved on');
Repository::$User = [];
// Old security callbacks now open account settings, never a separate category.
$UserContext->CallbackData = 'user_security_menu';
$Route->invoke(null, $UserContext);
check(calls() === array_merge($UserMenus['accountMenu'][1], ['منوی خدمات ربات']), 'legacy security callback redirects to account');
$Now = time();
foreach ([
'active' => [['Subscription' => '۱ ماهه', 'Expiration_Time_Stamp' => $Now + 86400], true, true],
'no subscription' => [[], false, false],
'expired' => [['Subscription' => '۱ ماهه', 'Expiration_Time_Stamp' => $Now - 1], false, false],
'expiry boundary' => [['Subscription' => '۱ ماهه', 'Expiration_Time_Stamp' => $Now], false, false],
'unknown expiry' => [['Subscription' => '۱ ماهه'], true, true],
'blank subscription' => [['Subscription' => '  ', 'Expiration_Time_Stamp' => $Now + 86400], false, false],
'paused client' => [['Subscription' => '۱ ماهه', 'Expiration_Time_Stamp' => $Now + 86400, 'Server_Enable' => 0], true, false],
] as $Label => [$User, $HasSubscription, $ActiveForMenu]) {
Repository::$User = $User + ['Client_ID' => 'test'];
$RenewVisible = trim((string)($User['Subscription'] ?? '')) !== '' && (int)($User['Expiration_Time_Stamp'] ?? 0) > 0 && (int)$User['Expiration_Time_Stamp'] <= time() + 3 * 86400;
foreach ([true, false] as $Callback) {
$UserContext->IsCallback = $Callback;
Repository::$Session = ['Flow' => 'custom_plan_days', 'Pending_Payment' => 'preserved'];
UserFlow::subscriptionsMenu($UserContext);
if ($ActiveForMenu) {
check(calls() === ['پروفایل کاربری', 'منوی خدمات ربات'], $Label . ': active subscription directs to profile');
check(array_map('count', TelegramClient::$Last['inline_keyboard']) === [1, 1], $Label . ': active subscription row grouping');
} else {
$Expected = $HasSubscription ? ['اشتراک آماده', 'اشتراک دلخواه'] : $UserMenus['subscriptionsMenu'][1];
if ($RenewVisible) $Expected[] = 'منوی تمدید خودکار';
$Expected[] = 'منوی خدمات ربات';
check(calls() === $Expected, $Label . ': correct subscription actions');
$Expected_Widths = array_merge([2], $HasSubscription ? [] : [1], $RenewVisible ? [1] : [], [1]);
check(array_map('count', TelegramClient::$Last['inline_keyboard']) === $Expected_Widths, $Label . ': subscription row grouping');
}
check(Repository::$Session === ['Flow' => null, 'Pending_Payment' => 'preserved'], $Label . ': navigation preserves payment');
}
}
Repository::$User = [];
$UserContext->IsCallback = true;
$SubscriptionSource = (string)file_get_contents(dirname(__DIR__) . '/Bot/Subscription.php');
$DispatcherSource = (string)file_get_contents(dirname(__DIR__) . '/Bot/Dispatcher.php');
check(!str_contains($SubscriptionSource, 'public static function mySubscription(')
&& !str_contains($SubscriptionSource, 'public static function mySubscriptionActive(')
&& str_contains($DispatcherSource, "'اشتراک من' => [UserFlow::class, 'subscriptionsMenu']"), 'my-subscription view is removed and legacy callback opens subscription purchase menu');
check(str_contains($SubscriptionSource, 'پروفایل کاربری') && str_contains($SubscriptionSource, "'اشتراک آماده'"), 'renewal flow keeps profile action and purchase flow');
$UserLeafParents = [
'User.php' => ['profile' => 'user_account_menu', 'autoRenewMenu' => 'user_subscriptions_menu', 'transactionHistory' => 'user_wallet_menu', 'subscriptionHistory' => 'user_stats_menu', 'usageAnalytics' => 'user_stats_menu', 'ticketNewStart' => 'منوی پشتیبانی', 'ticketUserList' => 'منوی پشتیبانی'],
'App-Link.php' => ['filterMenu' => 'user_device_menu', 'notifications' => 'user_device_menu', 'devices' => 'user_device_menu', 'renderTwoStep' => 'user_device_menu'],
'Subscription.php' => ['buyMenu' => 'user_subscriptions_menu', 'readyPlansMenu' => 'user_subscriptions_menu', 'customPlansMenu' => 'user_subscriptions_menu', 'walletTopupStart' => 'user_wallet_menu'],
'Profile.php' => ['begin' => 'user_account_menu', 'askName' => 'user_account_menu'],
];
foreach ($UserLeafParents as $File => $Methods) {
$Source = (string)file_get_contents(dirname(__DIR__) . '/Bot/' . $File);
foreach ($Methods as $Method => $Parent) {
preg_match('/(?:public|private) static function ' . $Method . '\b.*?(?=(?:public|private) static function |\z)/s', $Source, $Match);
$Body = $Match[0] ?? '';
check(str_contains($Body, "Menu::back('منوی قبلی', '{$Parent}')"), $Method . ': correct user category parent');
check(str_contains($Body, 'Menu::userHome()'), $Method . ': keeps user home');
}
}
// Device cards: owner links, safe display, stable numbering and bounded pagination.
AdminFlow::devicesMenu($Context);
check(TelegramClient::$Text === "مدیریت دستگاه ها\n📌*بخش مورد نظر را انتخاب کنید:*", 'device category uses plain greeting section and separate prompt');
check(calls() === ['admin_user_monitor', 'admin_devices', 'device_limit_menu', 'admin_devices_delete_all_menu', 'مدیریت'], 'device limit and user monitor live in device management');
for ($Index = 0; $Index < 7; $Index++) {
Database::$Devices[] = [
'ID' => $Index + 1, 'Device_ID' => str_pad((string)$Index, 64, 'a'),
'Device_Name' => 'Same device <b>name</b>', 'Platform' => 'Android',
'App_Version' => '1.2.3', 'Phone' => '09123456789',
'Owner_Name' => 'علی رضایی', 'Owner_Telegram_ID' => 123456789,
'Last_Seen_At' => '2026-11-16 12:30:00', 'Last_IP' => '192.0.2.1',
'Is_Trusted' => 1,
];
}
// Inactive / untrusted devices must remain excluded from admin appDevicesMenu.
Database::$Devices[] = [
'ID' => 98, 'Device_ID' => str_repeat('x', 64),
'Device_Name' => 'Inactive Hidden Device A', 'Platform' => 'Windows',
'App_Version' => '1.0.0', 'Phone' => '09120000001',
'Owner_Name' => 'کاربر غیرفعال', 'Owner_Telegram_ID' => 987654321,
'Last_Seen_At' => '2026-11-16 13:00:00', 'Last_IP' => '198.51.100.10',
'Is_Trusted' => 0,
];
Database::$Devices[] = [
'ID' => 99, 'Device_ID' => str_repeat('y', 64),
'Device_Name' => 'Inactive Hidden Device B', 'Platform' => 'Android',
'App_Version' => '1.0.0', 'Phone' => '09120000002',
'Owner_Name' => 'کاربر غیرفعال دو', 'Owner_Telegram_ID' => 987654322,
'Last_Seen_At' => '2026-11-16 13:05:00', 'Last_IP' => '198.51.100.11',
'Is_Trusted' => 0,
];
Database::$Devices[1]['Owner_Telegram_ID'] = null;
Database::$Devices[1]['Owner_Name'] = null;
Database::$Devices[1]['Last_Seen_At'] = null;
AdminFlow::appDevicesMenu($Context, -1);
$DeviceCalls = calls();
check(Database::$LastParams === [3, 0], 'negative device page clamps to first');
check(str_contains(TelegramClient::$Text, '<a href="tg://user?id=123456789">علی رضایی</a>'), 'full owner name opens correct Telegram profile');
check(!str_contains(TelegramClient::$Text, 'tg://user?id=0'), 'unknown owner is not linked to invented ID');
check(str_contains(TelegramClient::$Text, 'نام کامل ثبت نشده') && str_contains(TelegramClient::$Text, 'منشن در دسترس نیست'), 'missing identity is explicit');
check(str_contains(TelegramClient::$Text, 'آخرین فعالیت: ثبت نشده'), 'missing activity is not invented');
check(str_contains(TelegramClient::$Text, '&lt;b&gt;name&lt;/b&gt;'), 'device markup is escaped');
check(substr_count(TelegramClient::$Text, '📱دستگاه شماره') === 3, 'three clearly separated device cards');
check(!str_contains(TelegramClient::$Text, 'Inactive Hidden Device') && !str_contains(TelegramClient::$Text, 'غیرمجاز'), 'inactive devices are omitted from first page');
check(!in_array('device_limit_menu', $DeviceCalls, true), 'no duplicate device limit shortcut in list');
check(in_array('admin_devices_page:1', $DeviceCalls, true), 'first page has next page');
check(!in_array('admin_devices_page:-1', $DeviceCalls, true), 'first page has no previous page');
check(str_contains(Database::$LastQuery, 'HAVING COUNT(*) = 1') && str_contains(Database::$LastQuery, 'COALESCE(`D`.`Telegram_ID`, 0) <= 0') && str_contains(Database::$LastQuery, '`D`.`Is_Trusted` = 1'), 'owner fallback is unique, cannot override Telegram identity, and filters active devices only');
AdminFlow::appDevicesMenu($Context, 999);
check(Database::$LastParams === [3, 6], 'oversized device page clamps to last');
$DeviceCalls = calls();
check(str_contains(TelegramClient::$Text, '📱دستگاه شماره 7'), 'numbering continues across pages');
check(!str_contains(TelegramClient::$Text, 'Inactive Hidden Device') && !str_contains(TelegramClient::$Text, 'غیرمجاز'), 'inactive devices are omitted from last page');
check(in_array('admin_devices_page:1', $DeviceCalls, true) && !in_array('admin_devices_page:3', $DeviceCalls, true), 'last page has previous only');
check(str_ends_with($DeviceCalls[0], ':2'), 'toggle preserves page');
Database::$Devices = [
['ID' => 100, 'Device_ID' => str_repeat('z', 64), 'Device_Name' => 'Inactive Only', 'Platform' => 'Android', 'App_Version' => '1.0.0', 'Phone' => '09120000003', 'Is_Trusted' => 0],
];
AdminFlow::appDevicesMenu($Context, 0);
check(calls() === ['admin_devices_menu', 'مدیریت'], 'inactive-only device table renders empty active list');
check(str_contains(TelegramClient::$Text, 'هنوز دستگاهی') && !str_contains(TelegramClient::$Text, 'Inactive Only'), 'inactive-only device table excludes inactive cards');
Database::$Devices = [];
AdminFlow::appDevicesMenu($Context, 4);
check(calls() === ['admin_devices_menu', 'مدیریت'], 'empty device list retains only parent and home');
check(str_contains(TelegramClient::$Text, 'هنوز دستگاهی'), 'empty device message');
// Both ticket panels must expose every ticket, including beyond old hard limits.
for ($Id = 1; $Id <= 25; $Id++) Repository::$Tickets[] = ['ID' => $Id, 'Subject' => 'test', 'Status' => 'open', 'Priority' => 'medium'];
foreach ([['UserFlow', 'ticketUserList', 'user_tickets_page:', 'ticket_user_view:'], ['AdminFlow', 'ticketAdminMenu', 'admin_tickets_page:', 'ticket_view:']] as [$Class, $Method, $Prefix, $View]) {
foreach ([-1 => 0, 1 => 1, 99 => 3] as $Requested => $Page) {
$Class::$Method($Context, $Requested);
$Calls = calls();
check(in_array($View . ($Page * 8 + 1), $Calls, true), $Method . ': correct first row on page');
check(in_array($Prefix . ($Page - 1), $Calls, true) === ($Page > 0), $Method . ': previous boundary');
check(in_array($Prefix . ($Page + 1), $Calls, true) === ($Page < 3), $Method . ': next boundary');
}
}
Repository::$Tickets = [];
AdminFlow::ticketAdminMenu($Context, 99);
check(calls() === ['مدیریت'], 'direct admin ticket list returns only to admin home');
UserFlow::ticketUserList($UserContext, 99);
check(calls() === ['منوی پشتیبانی', 'منوی خدمات ربات'], 'empty user ticket list only parent and home');
AdminFlow::blockedList($Context, 99);
check(calls() === ['جرایم', 'مدیریت'], 'empty blocked list has no false next page');
foreach ([['UserFlow', 'ticketUserView', 'user_ticket_messages:'], ['AdminFlow', 'ticketAdminView', 'admin_ticket_messages:']] as [$Class, $Method, $Prefix]) {
$Class::$Method($Context, 42, 0);
check(in_array($Prefix . '42:1', calls(), true), $Method . ': long conversation has next');
$Class::$Method($Context, 42, 999);
check(in_array($Prefix . '42:2', calls(), true) && !in_array($Prefix . '42:4', calls(), true), $Method . ': final conversation page clamps');
}
$OtherUser = new Context(false);
$OtherUser->UserId = 2;
TelegramClient::$Text = 'unchanged';
UserFlow::ticketUserView($OtherUser, 42, 1);
check(TelegramClient::$Text === 'unchanged', 'ticket pagination cannot expose another user conversation');
TelegramClient::$Text = 'unchanged';
AdminFlow::ticketAdminView($OtherUser, 42, 1);
check(!str_contains(TelegramClient::$Text, 'متن متن'), 'admin thread pagination denies non-admin access');
// Visibility and old-callback authorization share the same policy.
$Base = ['Client_ID' => 'test', 'Subscription' => 'monthly', 'Is_Blocked' => 0,
'Client_Status' => 'فعال', 'Expiration_Time_Stamp' => time() + 10 * 86400];
$Live = ['uuid' => 'test', 'is_active' => true, 'enable' => true, 'usage_limit_GB' => 10, 'current_usage_GB' => 1];
$Cases = [
'healthy long subscription' => [$Base, $Live, true, false],
'exactly three days' => [array_replace($Base, ['Expiration_Time_Stamp' => time() + 3 * 86400]), $Live, true, true],
'over three days' => [array_replace($Base, ['Expiration_Time_Stamp' => time() + 3 * 86400 + 60]), $Live, true, false],
'under three days' => [array_replace($Base, ['Expiration_Time_Stamp' => time() + 1]), $Live, true, true],
'elapsed retained subscription' => [array_replace($Base, ['Expiration_Time_Stamp' => time() - 1]), $Live, false, true],
'no subscription' => [array_replace($Base, ['Subscription' => null]), $Live, false, false],
'unknown expiry' => [array_replace($Base, ['Expiration_Time_Stamp' => null]), $Live, false, false],
'blocked' => [array_replace($Base, ['Is_Blocked' => 1]), $Live, false, false],
'admin hold' => [array_replace($Base, ['Deactivation_Message' => 'hold']), $Live, false, false],
'channel suspension' => [array_replace($Base, ['Channel_Client_Disabled_At' => time()]), $Live, false, false],
'local disabled' => [array_replace($Base, ['Client_Status' => 'غیرفعال']), $Live, false, false],
'server disabled' => [$Base, array_replace($Live, ['enable' => false]), false, false],
'exhausted long plan' => [$Base, array_replace($Live, ['current_usage_GB' => 10, 'is_active' => false]), false, true],
'over quota' => [$Base, array_replace($Live, ['current_usage_GB' => 11]), false, true],
'zero quota not proof of exhaustion' => [$Base, array_replace($Live, ['usage_limit_GB' => 0, 'current_usage_GB' => 0]), true, false],
'unknown usage' => [$Base, array_diff_key($Live, ['current_usage_GB' => 1]), false, false],
'stale local zero remaining' => [array_replace($Base, ['Remaining_Usage_GB' => 0, 'Used_Usage_GB' => 10, 'Total_Usage_GB' => 10]), $Live, true, false],
'no live data' => [$Base, null, false, false],
'near expiry with unavailable live data' => [array_replace($Base, ['Expiration_Time_Stamp' => time() + 86400]), null, false, true],
'wrong UUID' => [$Base, array_replace($Live, ['uuid' => 'someone-else']), false, false],
];
$AutoRenewPolicy = new ReflectionMethod(UserFlow::class, 'autoRenewMenuVisible');
foreach ($Cases as $Name => [$Account, $LiveRow, $Nightly, $Renew]) {
Repository::$User = $Account;
ServerClient::$Response = ['StatusCode' => $LiveRow === null ? 503 : 200, 'Json' => $LiveRow];
$ExpectedActive = UserFlow::hasActiveMenuSubscription($Account, $LiveRow);
foreach ([true, false] as $Callback) {
$UserContext->IsCallback = $Callback;
UserFlow::accountMenu($UserContext);
check(in_array('nightly_report_off', calls(), true) === $Nightly, $Name . ': nightly control visibility');
UserFlow::subscriptionsMenu($UserContext);
if ($ExpectedActive) {
check(calls() === ['پروفایل کاربری', 'منوی خدمات ربات'], $Name . ': active subscription blocks subscription menu');
check((bool)$AutoRenewPolicy->invoke(null, $Account, $LiveRow) === $Renew, $Name . ': auto-renew policy eligibility preserved');
} else {
check(in_array('منوی تمدید خودکار', calls(), true) === $Renew, $Name . ': auto-renew visibility');
}
}
}
Repository::$User = $Base;
ServerClient::$Response = ['StatusCode' => 200, 'Json' => $Live];
foreach (['اشتراک آماده', 'اشتراک دلخواه', 'خرید اشتراک 1'] as $ProtectedCall) {
$UserContext->IsCallback = true;
$UserContext->CallbackData = $ProtectedCall;
$Route->invoke(null, $UserContext);
check(calls() === ['پروفایل کاربری', 'منوی خدمات ربات'], $ProtectedCall . ': active subscriber blocked at dispatcher level');
}
$UserContext->IsCallback = true;
Repository::$User = [];
Repository::$Settings['nightly_1'] = '1';
UserFlow::setNightlyReport($UserContext, false);
check(Repository::nightlyReportEnabled(1), 'old nightly callback cannot change preference without active subscription');
Repository::$User = $Base; ServerClient::$Response = ['StatusCode' => 200, 'Json' => $Live];
Repository::$Updates = [];
$UserContext->CallbackData = 'auto_renew_on_1';
UserFlow::enableAutoRenew($UserContext);
check(Repository::$Updates === [] && !in_array('auto_renew_on_1', calls(), true), 'old enable callback denied outside renewal window');
UserFlow::toggleAutoRenew($UserContext);
check(Repository::$Updates === [], 'legacy toggle cannot enable outside window');
UserFlow::autoRenewMenu($UserContext);
check(!in_array('auto_renew_on_1', calls(), true), 'direct old menu callback cannot reveal hidden controls');
Repository::$User = array_replace($Base, ['Expiration_Time_Stamp' => time() + 86400]);
UserFlow::autoRenewMenu($UserContext);
check(in_array('auto_renew_on_1', calls(), true), 'eligible menu renders plan controls');
UserFlow::enableAutoRenew($UserContext);
check((string)Repository::$User['Auto_Renew_Plan'] === '1', 'eligible enable still works');
Repository::$User['Expiration_Time_Stamp'] = time() + 10 * 86400;
UserFlow::subscriptionsMenu($UserContext);
check(!in_array('منوی تمدید خودکار', calls(), true) && (string)Repository::$User['Auto_Renew_Plan'] === '1', 'hiding menu preserves existing renewal setting');
UserFlow::disableAutoRenew($UserContext);
check(Repository::$User['Auto_Renew_Plan'] === null, 'cancellation remains available through old callback outside window');
// Verify one-time free claim & admin-controlled Nowruz menu synchronization.
Repository::$User = ['Free_Plan_Claimed' => 1, 'Client_ID' => 'account-1'];
Repository::$Settings['Nowruz_Menu_Enabled'] = '0';
Repository::$Settings['Nowruz_Claimed_1'] = '0';
UserFlow::subscriptionsMenu($UserContext);
check(!in_array('اشتراک رایگان اول', calls(), true), 'claimed free plan hides free menu button');
check(!in_array('اشتراک نوروزی اول', calls(), true), 'disabled Nowruz setting hides Nowruz button');
Repository::$Settings['Nowruz_Menu_Enabled'] = '1';
UserFlow::subscriptionsMenu($UserContext);
check(in_array('اشتراک نوروزی اول', calls(), true), 'enabled Nowruz setting reveals Nowruz button for unclaimed user');
Repository::$Settings['Nowruz_Claimed_1'] = '1';
UserFlow::subscriptionsMenu($UserContext);
check(!in_array('اشتراک نوروزی اول', calls(), true), 'claimed Nowruz plan hides Nowruz button even while menu enabled');
AdminFlow::toggleNowruzMenu($Context);
check(Repository::getSetting('Nowruz_Menu_Enabled') === '0', 'admin toggle turns Nowruz menu off');
check(in_array('emergency_toggle', calls(), true), 'emergency has a switch');
check(!in_array('emergency_url_start', calls(), true), 'emergency URL editor removed');
check(!str_contains(TelegramClient::$Text, 'https://example.invalid/emg'), 'emergency URL not shown');
AdminFlow::toggleEmergencyConfig($Context);
check(BotConfig::showEmergency(), 'emergency switch enables flag');
AdminFlow::toggleEmergencyConfig($Context);
check(!BotConfig::showEmergency(), 'emergency switch disables flag');

check(in_array('nowruz_menu_toggle', calls(), true), 'configMenu exposes Nowruz toggle button');
AdminFlow::toggleNowruzMenu($Context);
check(Repository::getSetting('Nowruz_Menu_Enabled') === '1', 'admin toggle turns Nowruz menu back on');
Repository::$Settings['Nowruz_Menu_Enabled'] = '0';
Repository::$Settings['Nowruz_Claimed_1'] = '0';

AdminFlow::globalContentFilterMenu($Context);
$Filter_Calls = calls();
check(count(array_keys($Filter_Calls, 'مدیریت', true)) === 1, 'global content filter has a single admin home button');
check(end($Filter_Calls) === 'مدیریت', 'global content filter ends with admin home');
AdminFlow::globalContentFilterDomainsMenu($Context);
$Domain_Calls = calls();
check(count(array_keys($Domain_Calls, 'admin_content_filter', true)) === 1 && count(array_keys($Domain_Calls, 'مدیریت', true)) === 1, 'global content filter domains has unique parent and admin home buttons');

AdminFlow::userMonitorList($Context, 0);
$Monitor_Calls = calls();
check(in_array('admin_devices_menu', $Monitor_Calls, true) && in_array('مدیریت', $Monitor_Calls, true), 'user monitor list has device management parent and admin home');

ServerClient::$Response = null;
echo "OK menu structure tests ({$Passed} assertions)\n";
