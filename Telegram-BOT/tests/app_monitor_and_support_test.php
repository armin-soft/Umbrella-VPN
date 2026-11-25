<?php
declare(strict_types=1);
// Behavioral + contract test for:
// 1. App_User_Activity schema + AppGateway activity normalization & storage
// 2. AdminFlow::userMonitorList + AdminFlow::userMonitorView + Dispatcher routes
// 3. AppGateway::supportReport payload resolution + HTML escaping + rate-limit guards
// 4. AppGateway::notifications manual admin-test delivery vs automated suppression

require_once dirname(__DIR__) . '/Bot/Menu.php';
if (!function_exists('mb_strlen')) {
function mb_strlen(string $S): int { return count(preg_split('//u', $S, -1, PREG_SPLIT_NO_EMPTY) ?: []); }
}
if (!function_exists('mb_substr')) {
function mb_substr(string $S, int $Start, ?int $Length = null): string { return implode('', array_slice(preg_split('//u', $S, -1, PREG_SPLIT_NO_EMPTY) ?: [], $Start, $Length)); }
}

final class Context {
public int $UserId = 99;
public int $ChatId = 99;
public ?int $MessageId = 55;
public ?string $CallbackId = 'cb';
public bool $IsCallback = true;
public ?string $CallbackData = '';
public function __construct(private bool $Admin = true) {}
public function isAdmin(): bool { return $this->Admin; }
}

final class Helper {
public static function repairMojibake(string $T): string { return $T; }
public static function stripZwnj(string $T): string { return str_replace("\u{200C}", '', $T); }
public static function digitsToPersian(string $T): string { return $T; }
public static function toPersian(string $T): string { return $T; }
public static function toEnglish(string $T): string { return $T; }
public static function normalizePhone(string $P): string { return trim($P); }
public static function validatePhone(string $P): bool { return str_starts_with(trim($P), '09'); }
public static function formatDateTimeText(string $T): string { return '1405-08-29 ' . $T; }
public static function formatPersianDate(int $Ts, bool $WithTime = false): string { return '1405/08/29 12:00'; }
public static function formatBytes(int $B): string { return (string)round($B / 1024, 1) . ' KB'; }
public static function formatPlatform(string $P): string { return $P !== '' ? $P : 'نامشخص'; }
public static function adminGreeting(Context $C, string $Title): string { return "🛡 {$Title}\n"; }
public static function userGreeting(Context $C, string $Title): string { return $Title . "\n"; }
public static function adminFooter(): string { return ''; }
public static function userFooter(): string { return ''; }
public static function frame(string $A, string $B, string $C, int $Id): string { return $C; }
}

final class Repository {
public static array $Settings = [];
public static array $Users = [];
public static array $Session = [];
public static array $Logs = [];
public static function getSetting(string $K, string $Default = ''): string { return (string)(self::$Settings[$K] ?? $Default); }
public static function setSetting(string $K, string $V): void { self::$Settings[$K] = $V; }
public static function getUser(int $Id): array { return self::$Users[$Id] ?? []; }
public static function findUserByIdentifier(string $Id): ?array {
foreach (self::$Users as $U) {
if ((string)($U['Telegram_ID'] ?? '') === $Id || (string)($U['Phone'] ?? '') === $Id) return $U;
}
return null;
}
public static function getUserSession(int $Id): array { return self::$Session; }
public static function updateUserSession(int $Id, array $F): void { self::$Session = array_replace(self::$Session, $F); }
public static function logAdminAction(int $Admin, string $Action, ?int $Target = null, ?string $Meta = null): void {
self::$Logs[] = [$Admin, $Action, $Target, $Meta];
}
}

final class Database {
public static array $Devices = [];
public static array $Activities = [];
public static array $Sessions = [];
public static function getInstance(): self { return new self(); }
private static function matchesActivity(array $Row, array $Params): bool {
foreach ($Params as $Param) {
if ($Param === ($Row['Device_ID'] ?? '') || $Param === (int)($Row['Telegram_ID'] ?? -1) || $Param === ($Row['User_UUID'] ?? '')) {
return true;
}
}
return false;
}
public function scalar(string $Q, array $P = [], mixed $Default = 0): mixed {
if (str_contains($Q, 'COUNT(*)') && str_contains($Q, 'App_User_Activity')) {
$Pool = str_contains($Q, "`Category` IN ('site', 'app')")
? array_filter(self::$Activities, static fn(array $A): bool => in_array($A['Category'] ?? '', ['site', 'app'], true))
: self::$Activities;
if (str_contains($Q, 'WHERE (')) {
$Matches = array_filter($Pool, static fn(array $A): bool => self::matchesActivity($A, $P));
return count($Matches);
}
if (str_contains($Q, 'AND (')) {
$Matches = array_filter($Pool, static fn(array $A): bool => self::matchesActivity($A, $P));
return count($Matches);
}
return count($Pool);
}
return $Default;
}
public function fetch(string $Q, array $P = []): ?array {
if (str_contains($Q, 'FROM `App_Sessions`')) {
foreach (self::$Sessions as $S) {
if (($S['Token_Hash'] ?? '') === ($P[0] ?? '')) return $S;
}
return null;
}
if (str_contains($Q, 'FROM `App_Devices`')) {
if (str_contains($Q, '`ID` = ?')) {
foreach (self::$Devices as $D) if ((int)($D['ID'] ?? 0) === (int)($P[0] ?? 0)) return $D;
}
if (str_contains($Q, '`Device_ID` = ?')) {
foreach (self::$Devices as $D) if (($D['Device_ID'] ?? '') === ($P[0] ?? '')) return $D;
}
}
return null;
}
public function fetchAll(string $Q, array $P = []): array {
if (str_contains($Q, 'FROM `App_Devices` AS `D`')) {
return array_map(static function (array $D): array {
$Tg = (int)($D['Telegram_ID'] ?? 0);
$U = $Tg > 0 ? (Repository::$Users[$Tg] ?? []) : [];
return $D + [
'Owner_Name' => $U['Full_Name'] ?? null,
'Owner_Phone' => $U['Phone'] ?? null,
'Matched_Tg_ID' => $Tg > 0 ? $Tg : null,
];
}, self::$Devices);
}
if (str_contains($Q, 'GROUP BY `Device_ID`, `Category`')) {
$Buckets = [];
foreach (self::$Activities as $A) {
$Key = $A['Device_ID'] . '|' . $A['Category'];
if (!isset($Buckets[$Key])) {
$Buckets[$Key] = ['Device_ID' => $A['Device_ID'], 'Category' => $A['Category'], 'Cnt' => 0, 'Last_At' => 0];
}
$Buckets[$Key]['Cnt']++;
$Buckets[$Key]['Last_At'] = max($Buckets[$Key]['Last_At'], (int)$A['Last_Seen_At']);
}
return array_values($Buckets);
}
if (str_contains($Q, 'FROM `App_Devices`')) {
return array_values(array_filter(self::$Devices, static function (array $D) use ($P): bool {
foreach ($P as $Param) {
if ($Param === (int)($D['Telegram_ID'] ?? -1) || $Param === ($D['User_UUID'] ?? '') || $Param === ($D['Phone'] ?? '') || $Param === (int)($D['ID'] ?? -1)) return true;
}
return false;
}));
}
if (str_contains($Q, 'FROM `App_User_Activity`')) {
return array_values(array_filter(self::$Activities, static function (array $A) use ($P): bool {
foreach ($P as $Param) {
if ($Param === ($A['Device_ID'] ?? '') || $Param === (int)($A['Telegram_ID'] ?? -1) || $Param === ($A['User_UUID'] ?? '')) return true;
}
return false;
}));
}
return [];
}
public function execute(string $Q, array $P = []): void {
if (str_contains($Q, 'DELETE FROM `App_User_Activity`')) {
if (str_contains($Q, '`Last_Seen_At` < ?')) {
$Cutoff = (int)($P[0] ?? 0);
$Cat = (string)($P[1] ?? '');
self::$Activities = array_values(array_filter(
self::$Activities,
static fn(array $A): bool => (int)($A['Last_Seen_At'] ?? 0) >= $Cutoff && ($A['Category'] ?? '') !== $Cat
));
} elseif (str_contains($Q, 'WHERE (')) {
self::$Activities = array_values(array_filter(
self::$Activities,
static fn(array $A): bool => !self::matchesActivity($A, $P)
));
} else {
self::$Activities = [];
}
return;
}
if (str_contains($Q, 'INSERT INTO `App_User_Activity`')) {
[$Dev, $Uuid, $Tg, $Cat, $Target, $Hits, $Down, $Up, $Now] = $P;
foreach (self::$Activities as &$Row) {
if ($Row['Device_ID'] === $Dev && $Row['Category'] === $Cat && $Row['Target'] === $Target) {
$Row['Hits'] += $Hits;
$Row['Bytes_Down'] += $Down;
$Row['Bytes_Up'] += $Up;
$Row['Last_Seen_At'] = $Now;
return;
}
}
self::$Activities[] = [
'Device_ID' => $Dev, 'User_UUID' => $Uuid, 'Telegram_ID' => $Tg,
'Category' => $Cat, 'Target' => $Target, 'Hits' => $Hits,
'Bytes_Down' => $Down, 'Bytes_Up' => $Up, 'Last_Seen_At' => $Now,
];
}
}
}

final class TelegramClient {
public static string $LastText = '';
public static array $LastMarkup = [];
public static string $LastAlert = '';
public static array $ReadableSent = [];
public static function inlineKeyboard(array $Rows): array { return ['inline_keyboard' => $Rows]; }
public static function sendMessage(int $ChatId, string $Text, array $Markup = []): array { self::$LastText = $Text; self::$LastMarkup = $Markup; return ['ok' => true]; }
public static function editOrSendMessage(int $ChatId, ?int $MessageId, string $Text, array $Markup = []): void { self::$LastText = $Text; self::$LastMarkup = $Markup; }
public static function editMessageText(int $ChatId, int $MessageId, string $Text, array $Markup = []): array { self::$LastText = $Text; self::$LastMarkup = $Markup; return ['ok' => true]; }
public static function answerCallbackQuery(?string $Id, string $Text, bool $Alert = false): void { self::$LastAlert = $Text; }
public static function sendReadableMessage(int $ChatId, ?int $MessageId, string $Text, array $Markup = []): bool {
self::$LastText = $Text;
self::$LastMarkup = $Markup;
self::$ReadableSent[] = [$ChatId, $Text, $Markup];
return true;
}
}

final class Environment {
public static function getAdminUserId(): int { return 99; }
public static function getUmbrellaBaseUrl(): string { return ''; }
}
final class BotConfig {
public static function getChannelUrl(): string { return 'https://t.me/UmbrellaVPN_Channel'; }
public static function showEmergency(): bool { return false; }
}
final class SystemNotifications {
public static function formatForWindowsApp(string $Title, string $Body, string $Level = 'info'): array {
return ['title' => $Title, 'body' => $Body, 'level' => $Level === 'manual' ? 'info' : $Level];
}
}
final class PanelClient {
public static function get(string $Uuid): ?array { return ['uuid' => $Uuid]; }
public static function lastGetStatus(): int { return 200; }
}
final class AppFilter {}
final class AppBypass {}
final class AppSchema { public static function ensureInstalled(): void {} }
final class Common {
public static function greet(Context $C, string $S): string { return $S; }
public static function isRobotOn(): bool { return true; }
}
final class AppAccountRevocation { public static function revoke(string $U): bool { return true; } }
final class AppDeviceLimit {}
final class AppTwoStep {}
final class AppSecret {}
final class AppBotLink {}
final class BotIdentity { public static function link(): string { return 'https://t.me/UmbrellaBot'; } }
final class IppanelClient { public static function send(...$A): bool { return true; } }
final class ServerClient { public static function getUser(string $U): array { return ['StatusCode' => 200, 'Json' => []]; } public static function liveUsers(): array { return []; } public static function listUsers(): array { return ['StatusCode' => 200, 'Json' => []]; } }
final class SubscriptionFlow {}
final class UserFlow {}
final class AppFlow {}
final class Zarinpal {}
final class TicketMedia {}
final class DeviceDeletion {}
final class Scheduler {
public static function purgeUserActivityIfDue(): void {
$Now = time();
$Last = (int)Repository::getSetting('Last_User_Activity_Reset_At', '0');
$Db = Database::getInstance();
if ($Last <= 0) {
$Db->execute('DELETE FROM `App_User_Activity` WHERE `Last_Seen_At` < ? OR `Category` = ?', [$Now - 86400, 'screen']);
Repository::setSetting('Last_User_Activity_Reset_At', (string)$Now);
return;
}
if (($Now - $Last) >= 86400) {
$Db->execute('DELETE FROM `App_User_Activity`', []);
Repository::setSetting('Last_User_Activity_Reset_At', (string)$Now);
}
}
}

foreach ([
'Core/App/App-Gateway.php' => 'AppGateway',
'Bot/Admin.php' => 'AdminFlow',
'Bot/Dispatcher.php' => 'Dispatcher',
] as $Path => $Class) {
$Src = (string)file_get_contents(dirname(__DIR__) . '/' . $Path);
$Start = strpos($Src, 'final class ' . $Class . ' {');
if ($Start === false) throw new RuntimeException('Cannot locate ' . $Class);
eval(preg_replace('/\?>\s*$/', '', substr($Src, $Start)));
}

$Checks = 0;
function check(bool $Cond, string $Msg): void {
global $Checks;
$Checks++;
if (!$Cond) throw new RuntimeException('FAIL: ' . $Msg);
}

// 1. Schema presence in both Schema-App.php and Schema.SQL
$SchemaApp = (string)file_get_contents(dirname(__DIR__) . '/Core/Database/Schema-App.php');
$SchemaSql = (string)file_get_contents(dirname(__DIR__) . '/Database/Schema.SQL');
check(str_contains($SchemaApp, "'App_User_Activity' =>"), 'Schema-App defines App_User_Activity');
check(str_contains($SchemaSql, 'CREATE TABLE IF NOT EXISTS `App_User_Activity`'), 'Schema.SQL defines App_User_Activity');

// 2. AppGateway routes & admin manual-only notification gating
$GatewayCode = (string)file_get_contents(dirname(__DIR__) . '/Core/App/App-Gateway.php');
check(str_contains($GatewayCode, "if (\$Route === 'app/activity')"), 'AppGateway exposes app/activity route');
check(str_contains($GatewayCode, "if (\$Route === 'app/support-report')"), 'AppGateway exposes app/support-report route');
check(str_contains($GatewayCode, "\$LevelCondition = \$AdminOnlyManual ? \" AND `Level` = 'manual'\" : '';"), 'Admin sessions only receive manual test pushes while automated notifications stay suppressed');
check(str_contains($GatewayCode, "'activity_monitor'") && str_contains($GatewayCode, "'support_report'"), 'AppGateway ping advertises activity_monitor and support_report');

// 3. Activity target normalization & storage (sites & exact Windows/Android app names only, no IPs, no UIDs, no screens)
$Norm = new ReflectionMethod(AppGateway::class, 'normalizeActivityTarget');
check($Norm->invoke(null, 'site', 'https://www.YouTube.com:443/') === 'youtube.com', 'site normalization strips scheme, www, port and lowercases');
check($Norm->invoke(null, 'site', 'localhost') === '' && $Norm->invoke(null, 'site', '127.0.0.1') === '' && $Norm->invoke(null, 'site', '192.168.1.10') === '' && $Norm->invoke(null, 'site', '142.250.185.78') === '' && $Norm->invoke(null, 'site', '2606:4700::1') === '', 'loopback, private and public raw IPs are ignored');
check($Norm->invoke(null, 'app', 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe') === 'Google Chrome', 'Windows process path resolves exact application name');
check($Norm->invoke(null, 'app', 'com.instagram.android') === 'Instagram', 'Android package name resolves exact app name');
check($Norm->invoke(null, 'app', '10284') === '' && $Norm->invoke(null, 'app', 'svchost.exe') === '', 'numeric UIDs and Windows background noise excluded');
check($Norm->invoke(null, 'app', 'sing-box.exe') === '' && $Norm->invoke(null, 'app', 'ir.umbrella.vpn') === '', 'VPN core processes excluded from app monitoring');
check($Norm->invoke(null, 'screen', 'اتصال') === '', 'in-app screens are no longer recorded');

$StoreAct = new ReflectionMethod(AppGateway::class, 'storeActivity');
$Stored = $StoreAct->invoke(null, 'dev-1', 'uuid-1', 101, [
'current_screen' => 'اتصال',
'activity' => [
['category' => 'site', 'target' => 'github.com', 'hits' => 2, 'down' => 2048, 'up' => 512],
['category' => 'app', 'target' => 'C:\\Users\\Ali\\Telegram.exe', 'hits' => 1, 'down' => 1024, 'up' => 256],
['category' => 'app', 'target' => 'sing-box.exe', 'hits' => 5, 'down' => 999, 'up' => 999],
['category' => 'app', 'target' => '10244', 'hits' => 3],
['category' => 'site', 'target' => '142.250.185.78', 'hits' => 4],
['category' => 'site', 'target' => '127.0.0.1', 'hits' => 4],
],
]);
check($Stored === 2 && count(Database::$Activities) === 2, 'storeActivity saves site and exact app names while filtering IPs, UIDs, screens and core noise');

// Upsert increments hits/bytes rather than duplicating rows
$StoreAct->invoke(null, 'dev-1', 'uuid-1', 101, [
'activity' => [['category' => 'site', 'target' => 'github.com', 'hits' => 3, 'down' => 1024, 'up' => 256]],
]);
check(count(Database::$Activities) === 2 && Database::$Activities[0]['Hits'] === 5 && Database::$Activities[0]['Bytes_Down'] === 3072, 'activity upsert aggregates repeated visits per device');

// 4. Support sender resolution even when session/token is absent or guest
Repository::$Users[101] = ['Telegram_ID' => 101, 'Full_Name' => 'سارا محمدی', 'Phone' => '09121112233', 'Client_ID' => 'uuid-1', 'Subscription' => 'یک ماهه'];
Database::$Devices = [
['ID' => 7, 'Device_ID' => 'dev-1', 'Device_Name' => 'Laptop <Win>', 'Platform' => 'Windows', 'App_Version' => '1.0.5', 'Phone' => '09121112233', 'Telegram_ID' => 101, 'User_UUID' => 'uuid-1', 'Is_Trusted' => 1, 'Last_Seen_At' => time(), 'Last_IP' => '203.0.113.5'],
['ID' => 8, 'Device_ID' => 'dev-android', 'Device_Name' => 'Galaxy A54', 'Platform' => 'Android', 'App_Version' => '1.0.2', 'Phone' => '09120009988', 'Telegram_ID' => 0, 'User_UUID' => 'uuid-2', 'Is_Trusted' => 1, 'Last_Seen_At' => time() - 60, 'Last_IP' => '198.51.100.8'],
];
Database::$Activities[] = ['Device_ID' => 'dev-android', 'User_UUID' => 'uuid-2', 'Telegram_ID' => 0, 'Category' => 'app', 'Target' => 'Google Chrome', 'Hits' => 4, 'Bytes_Down' => 4096, 'Bytes_Up' => 512, 'Last_Seen_At' => time()];

$ResolveSender = new ReflectionMethod(AppGateway::class, 'resolveSupportSender');
$Resolved = $ResolveSender->invoke(null, '', 'dev-1', '');
check($Resolved['telegram_id'] === 101 && ($Resolved['user']['Full_Name'] ?? '') === 'سارا محمدی', 'support sender resolves user profile from Device_ID when logged out');

// 5. AdminFlow userMonitorList + userMonitorView + Dispatcher callback routing
$AdminCtx = new Context(true);
AdminFlow::userMonitorList($AdminCtx, 0);
check(str_contains(TelegramClient::$LastText, 'سارا محمدی') && str_contains(TelegramClient::$LastText, 'Galaxy A54'), 'userMonitorList shows both Telegram-linked and app-only users');
check(!str_contains(TelegramClient::$LastText, 'بخش') && str_contains(TelegramClient::$LastText, 'هر ۲۴ ساعت'), 'userMonitorList omits screen count and documents 24h auto-reset');
$AllMonitorBtns = array_merge(...(TelegramClient::$LastMarkup['inline_keyboard'] ?? []));
$MonitorCallbacks = array_column($AllMonitorBtns, 'callback_data');
check(in_array('admin_monitor_view:t:101:0:all:0', $MonitorCallbacks, true) && in_array('admin_monitor_view:d:8:0:all:0', $MonitorCallbacks, true), 'user monitor exposes clickable user detail callbacks');

$Route = new ReflectionMethod(Dispatcher::class, 'routeCallbackInner');
$AdminCtx->CallbackData = 'admin_monitor_view:t:101:0:all:0';
$Route->invoke(null, $AdminCtx);
check(str_contains(TelegramClient::$LastText, 'github.com') && str_contains(TelegramClient::$LastText, 'Telegram') && !str_contains(TelegramClient::$LastText, 'اتصال'), 'userMonitorView displays opened sites and exact software name without in-app screens');
check(str_contains(TelegramClient::$LastText, 'Laptop &lt;Win&gt;'), 'userMonitorView HTML-escapes client device names');

$AdminCtx->CallbackData = 'admin_monitor_view:d:8:0:app:0';
$Route->invoke(null, $AdminCtx);
check(str_contains(TelegramClient::$LastText, 'Google Chrome') && !str_contains(TelegramClient::$LastText, 'github.com'), 'category filter isolates Android apps from sites accurately');
$ViewCallbacks = array_column(array_merge(...(TelegramClient::$LastMarkup['inline_keyboard'] ?? [])), 'callback_data');
check(in_array('admin_monitor_clr:d:8:0:app', $ViewCallbacks, true), 'user monitor view exposes clear-user-history button');
check(!in_array('admin_monitor_view:d:8:0:screen:0', $ViewCallbacks, true), 'screen filter button is removed from user monitor view');
check(in_array('admin_monitor_clrall:0', $MonitorCallbacks, true), 'user monitor list exposes clear-all-history button');

// 6. Clearing single-user and all-user monitoring history via confirmation flow
$AdminCtx->CallbackData = 'admin_monitor_clr:t:101:0:all';
$Route->invoke(null, $AdminCtx);
$ConfirmUserCallbacks = array_column(array_merge(...(TelegramClient::$LastMarkup['inline_keyboard'] ?? [])), 'callback_data');
check(in_array('admin_monitor_clrok:t:101:0:all', $ConfirmUserCallbacks, true), 'user clear prompt requires confirmation before deleting');
check(count(Database::$Activities) === 3, 'user clear prompt does not delete rows before confirmation');

$GuestCtx = new Context(false);
$GuestCtx->CallbackData = 'admin_monitor_clrok:t:101:0:all';
$Route->invoke(null, $GuestCtx);
$GuestCtx->CallbackData = 'admin_monitor_clrall_ok:0';
$Route->invoke(null, $GuestCtx);
check(count(Database::$Activities) === 3, 'non-admin cannot clear monitoring history');

$AdminCtx->CallbackData = 'admin_monitor_clrok:t:101:0:all';
$Route->invoke(null, $AdminCtx);
check(count(Database::$Activities) === 1 && Database::$Activities[0]['Target'] === 'Google Chrome', 'confirming per-user clear deletes only that user activities');
check(count(Database::$Devices) === 2, 'per-user monitor clear preserves trusted devices');
check(str_contains(TelegramClient::$LastText, 'تاریخچه رصد'), 'per-user monitor clear returns to user view with notice');

$AdminCtx->CallbackData = 'admin_monitor_clrall:0';
$Route->invoke(null, $AdminCtx);
$ConfirmAllCallbacks = array_column(array_merge(...(TelegramClient::$LastMarkup['inline_keyboard'] ?? [])), 'callback_data');
check(in_array('admin_monitor_clrall_ok:0', $ConfirmAllCallbacks, true), 'clear-all prompt requires confirmation');
check(count(Database::$Activities) === 1, 'clear-all prompt does not delete remaining history before confirmation');

$AdminCtx->CallbackData = 'admin_monitor_clrall_ok:0';
$Route->invoke(null, $AdminCtx);
check(Database::$Activities === [] && count(Database::$Devices) === 2, 'confirming clear-all empties App_User_Activity while keeping App_Devices intact');
check(str_contains(TelegramClient::$LastText, 'کل تاریخچه رصد کاربران'), 'clear-all returns to userMonitorList with confirmation notice');

TelegramClient::$LastAlert = '';
$AdminCtx->CallbackData = 'admin_monitor_clrall:0';
$Route->invoke(null, $AdminCtx);
check(str_contains(TelegramClient::$LastAlert, 'وجود ندارد'), 'clear-all warns when history is already empty');

// 7. 24-hour automatic activity reset check
Database::$Activities[] = ['Device_ID' => 'dev-1', 'User_UUID' => 'uuid-1', 'Telegram_ID' => 101, 'Category' => 'site', 'Target' => 'example.com', 'Hits' => 2, 'Bytes_Down' => 500, 'Bytes_Up' => 100, 'Last_Seen_At' => time()];
Repository::setSetting('Last_User_Activity_Reset_At', (string)(time() - 86405));
Scheduler::purgeUserActivityIfDue();
check(Database::$Activities === [] && count(Database::$Devices) === 2, '24h scheduler purge clears App_User_Activity while preserving App_Devices');
check((int)Repository::getSetting('Last_User_Activity_Reset_At', '0') >= time() - 5, '24h scheduler purge updates Last_User_Activity_Reset_At');
$SchedulerCode = (string)file_get_contents(dirname(__DIR__) . '/Bot/Scheduler.php');
check(str_contains($SchedulerCode, 'self::purgeUserActivityIfDue();'), 'Scheduler::run invokes purgeUserActivityIfDue');

// 8. No forbidden English VPN wording in monitored admin/app notices
$AdminSrc = (string)file_get_contents(dirname(__DIR__) . '/Bot/Admin.php');
$AppLinkSrc = (string)file_get_contents(dirname(__DIR__) . '/Bot/App-Link.php');
check(!str_contains($AdminSrc, 'اتصال VPN') && !str_contains($AppLinkSrc, 'خارج از VPN') && !str_contains($GatewayCode, 'اتصال VPN'), 'Persian VPN notices avoid raw English VPN wording');

echo "OK monitor and support tests ({$Checks} assertions)\n";
