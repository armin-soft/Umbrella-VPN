<?php
declare(strict_types=1);

/**
 * Behavioral regression suite for:
 *  1. App/desktop signup Full_Name persistence & display across bot screens
 *  2. Exact timestamp (Y-m-d H:i:s) writes on App_Devices / App_Sessions + legacy fallback
 *  3. Strict separation of websites (`site`), desktop software (`software`), and mobile apps (`mobile`)
 *  4. Self-contained RTL HTML export from user monitoring (all users & single user)
 */

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
public ?int $MessageId = 77;
public ?string $CallbackId = 'cb-split';
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
public static function formatDateTimeText(string $T): string {
$Raw = trim($T);
if ($Raw === '' || $Raw === '0' || str_starts_with($Raw, '0000-00-00')) return 'ثبت نشده';
if (ctype_digit($Raw)) return ((int)$Raw) > 0 ? 'J-' . gmdate('Y-m-d H:i', (int)$Raw) : 'ثبت نشده';
return 'J-' . $Raw;
}
public static function parseServerTime(string $Raw): int {
$Dt = DateTimeImmutable::createFromFormat('Y-m-d H:i:s', trim($Raw), new DateTimeZone('Asia/Tehran'));
return $Dt === false ? 0 : $Dt->getTimestamp();
}
public static function formatPersianDate(int $Ts, bool $WithTime = false): string { return '1405/09/05 12:00'; }
public static function formatBytes(int $B): string { return (string)round($B / 1024, 1) . ' KB'; }
public static function formatPlatform(string $P): string { return $P !== '' ? $P : 'نامشخص'; }
public static function formatPhoneDisplay(string $P): string { return $P; }
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
public static function findUserByPhone(string $P, int $Exclude = 0): ?array {
foreach (self::$Users as $U) {
if ((int)($U['Telegram_ID'] ?? 0) !== $Exclude && (string)($U['Phone'] ?? '') === $P) return $U;
}
return null;
}
public static function findUserByIdentifier(string $Id): ?array { return null; }
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
public static array $SignIns = [];
public static array $Queries = [];
public static function getInstance(): self { return new self(); }
public function scalar(string $Q, array $P = [], mixed $Default = 0): mixed {
if (str_contains($Q, 'COUNT(*)') && str_contains($Q, 'FROM `App_Devices`')) {
return count(array_filter(self::$Devices, static fn(array $D): bool => (int)($D['Is_Trusted'] ?? 0) === 1));
}
return $Default;
}
public function fetch(string $Q, array $P = []): ?array {
if (str_contains($Q, 'FROM `App_Devices`') && str_contains($Q, '`ID` = ?')) {
foreach (self::$Devices as $D) if ((int)($D['ID'] ?? 0) === (int)($P[0] ?? 0)) return $D;
}
if (str_contains($Q, 'FROM `App_Devices`') && str_contains($Q, '`Device_ID` = ?')) {
foreach (self::$Devices as $D) if (($D['Device_ID'] ?? '') === ($P[0] ?? '')) return $D;
}
return null;
}
public function fetchAll(string $Q, array $P = []): array {
if (str_contains($Q, 'FROM `App_SignIn_Requests`')) return self::$SignIns;
if (str_contains($Q, 'FROM `App_Devices` AS `D`')) {
$Out = array_map(static function (array $D): array {
$Tg = (int)($D['Telegram_ID'] ?? 0);
$U = $Tg > 0 ? (Repository::$Users[$Tg] ?? []) : [];
$Owner = trim((string)($U['Full_Name'] ?? ''));
if ($Owner === '') $Owner = trim((string)($D['Full_Name'] ?? ''));
if ($Owner === '') {
foreach (self::$SignIns as $S) {
if (($S['Device_ID'] ?? '') === ($D['Device_ID'] ?? '') || ($D['Phone'] !== '' && ($S['Phone'] ?? '') === $D['Phone'])) {
if (trim((string)($S['Full_Name'] ?? '')) !== '') {
$Owner = trim((string)$S['Full_Name']);
break;
}
}
}
}
return $D + [
'Device_Full_Name' => $D['Full_Name'] ?? null,
'Owner_Name' => $Owner !== '' ? $Owner : null,
'Owner_Phone' => $U['Phone'] ?? null,
'Matched_Tg_ID' => $Tg > 0 ? $Tg : null,
'Owner_Telegram_ID' => $Tg > 0 ? $Tg : null,
];
}, self::$Devices);
if (str_contains($Q, 'LIMIT ? OFFSET ?') && count($P) >= 2) {
return array_slice($Out, (int)$P[1], (int)$P[0]);
}
return $Out;
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
if ($P === []) return self::$Activities;
return array_values(array_filter(self::$Activities, static function (array $A) use ($P): bool {
foreach ($P as $Param) {
if ($Param === ($A['Device_ID'] ?? '') || $Param === (int)($A['Telegram_ID'] ?? -1) || $Param === ($A['User_UUID'] ?? '')) return true;
}
return false;
}));
}
return [];
}
public function execute(string $Q, array $P = []): object {
self::$Queries[] = [$Q, $P];
if (str_contains($Q, 'INSERT INTO `App_Devices`')) {
[$DevId, $DevName, $FullName, $Platform, $Version, $Phone, $LastSeen, $Ip] = $P;
foreach (self::$Devices as &$Row) {
if ($Row['Device_ID'] === $DevId) {
$Row['Device_Name'] = $DevName;
if ($FullName !== '' && empty($Row['Full_Name'])) $Row['Full_Name'] = $FullName;
$Row['Platform'] = $Platform;
$Row['App_Version'] = $Version;
$Row['Phone'] = $Phone;
$Row['Last_Seen_At'] = $LastSeen;
$Row['Last_IP'] = $Ip;
return new class { public function rowCount(): int { return 1; } };
}
}
self::$Devices[] = [
'ID' => count(self::$Devices) + 1,
'Device_ID' => $DevId, 'Device_Name' => $DevName, 'Full_Name' => $FullName,
'Platform' => $Platform, 'App_Version' => $Version, 'Phone' => $Phone,
'Telegram_ID' => 0, 'User_UUID' => '', 'Is_Trusted' => 1,
'First_Seen_At' => $LastSeen, 'Last_Seen_At' => $LastSeen, 'Last_IP' => $Ip,
];
} elseif (str_contains($Q, 'INSERT INTO `App_Sessions`')) {
self::$Sessions[] = ['Token_Hash' => $P[0], 'User_UUID' => $P[1], 'Device_ID' => $P[2], 'Telegram_ID' => $P[3], 'Last_Used_At' => $P[4], 'Revoked_At' => null];
}
return new class { public function rowCount(): int { return 1; } };
}
}

final class TelegramClient {
public static string $LastText = '';
public static array $LastMarkup = [];
public static string $LastAlert = '';
public static array $LastDocument = [];
public static function inlineKeyboard(array $Rows): array { return ['inline_keyboard' => $Rows]; }
public static function sendMessage(int $ChatId, string $Text, array $Markup = []): array { self::$LastText = $Text; self::$LastMarkup = $Markup; return ['ok' => true]; }
public static function editOrSendMessage(int $ChatId, ?int $MessageId, string $Text, array $Markup = []): void { self::$LastText = $Text; self::$LastMarkup = $Markup; }
public static function answerCallbackQuery(?string $Id, string $Text, bool $Alert = false): void { self::$LastAlert = $Text; }
public static function sendReadableMessage(int $ChatId, ?int $MessageId, string $Text, array $Markup = []): bool {
self::$LastText = $Text; self::$LastMarkup = $Markup;
return true;
}
public static function sendDocument(int $ChatId, string $Path, string $Caption = '', array $Markup = []): array {
self::$LastDocument = ['chat_id' => $ChatId, 'path' => $Path, 'caption' => $Caption, 'content' => is_file($Path) ? (string)file_get_contents($Path) : ''];
return ['ok' => true];
}
}

final class Environment { public static function getAdminUserId(): int { return 99; } public static function getUmbrellaBaseUrl(): string { return ''; } }
final class BotConfig { public static function getChannelUrl(): string { return 'https://t.me/UmbrellaVPN_Channel'; } public static function showEmergency(): bool { return false; } }
final class SystemNotifications {}
final class PanelClient { public static function get(string $U): ?array { return ['uuid' => $U]; } public static function lastGetStatus(): int { return 200; } }
final class AppFilter {}
final class AppBypass {}
final class AppSchema { public static function ensureInstalled(): void {} }
final class Common { public static function greet(Context $C, string $S): string { return $S; } public static function isRobotOn(): bool { return true; } }
final class AppAccountRevocation {}
final class AppDeviceLimit {}
final class AppTwoStep {}
final class AppSecret {}
final class AppBotLink {}
final class BotIdentity { public static function link(): string { return 'https://t.me/UmbrellaBot'; } }
final class IppanelClient {}
final class ServerClient { public static function getUser(string $U): array { return ['StatusCode' => 200, 'Json' => []]; } public static function liveUsers(): array { return []; } }
final class SubscriptionFlow {}
final class UserFlow {}
final class AppFlow {}
final class Zarinpal {}
final class TicketMedia {}
final class DeviceDeletion {}
final class Scheduler { public static function purgeUserActivityIfDue(): void {} }

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

// 1. trackDevice + issueToken write valid Tehran datetime strings (not integer time()) & save Full_Name
$Track = new ReflectionMethod(AppGateway::class, 'trackDevice');
$_SERVER['REMOTE_ADDR'] = '5.117.159.18';
$Track->invoke(null, 'dev-hediye', ['device_name' => 'Hediye', 'platform' => 'Android', 'app_version' => '1.0.2'], '09351978719', 'هدیه مرادی');
$Track->invoke(null, 'dev-win', ['device_name' => 'Ali-PC', 'platform' => 'Windows', 'app_version' => '1.0.2'], '09351978719', 'هدیه مرادی');

check(count(Database::$Devices) === 2, 'both Android and Windows devices registered');
check(preg_match('/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/', (string)Database::$Devices[0]['Last_Seen_At']) === 1, 'App_Devices.Last_Seen_At receives datetime string compatible with MySQL TIMESTAMP');
check(Database::$Devices[0]['Full_Name'] === 'هدیه مرادی', 'App_Devices stores Full_Name from app signup');

$Issue = new ReflectionMethod(AppGateway::class, 'issueToken');
$Issue->invoke(null, ['User_UUID' => 'uuid-hediye', 'Device_ID' => 'dev-hediye', 'Telegram_ID' => 0]);
check(preg_match('/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/', (string)Database::$Sessions[0]['Last_Used_At']) === 1, 'App_Sessions.Last_Used_At receives valid datetime string');

// Simulate legacy broken TIMESTAMP ('0000-00-00 00:00:00') with valid First_Seen_At and unlinked Telegram
Database::$Devices[0]['User_UUID'] = 'uuid-hediye';
Database::$Devices[1]['User_UUID'] = 'uuid-hediye';
Database::$Devices[0]['Last_Seen_At'] = '0000-00-00 00:00:00';
$AdminCtx = new Context(true);
AdminFlow::appDevicesMenu($AdminCtx, 0);
check(str_contains(TelegramClient::$LastText, 'هدیه مرادی') && !str_contains(TelegramClient::$LastText, 'نام کامل ثبت نشده'), 'appDevicesMenu shows Full_Name for app-registered user without Telegram');
check(!str_contains(TelegramClient::$LastText, 'آخرین فعالیت: ثبت نشده'), 'appDevicesMenu recovers First_Seen_At when legacy Last_Seen_At is zeroed');

// 2. Same user opens sites, Windows software, and Android apps -> exact separation
$Now = time();
Database::$Activities = [
['Device_ID' => 'dev-win', 'User_UUID' => 'uuid-hediye', 'Telegram_ID' => 0, 'Category' => 'site', 'Target' => 'github.com', 'Hits' => 5, 'Bytes_Down' => 2048, 'Bytes_Up' => 512, 'Last_Seen_At' => $Now],
['Device_ID' => 'dev-hediye', 'User_UUID' => 'uuid-hediye', 'Telegram_ID' => 0, 'Category' => 'site', 'Target' => 'youtube.com', 'Hits' => 2, 'Bytes_Down' => 4096, 'Bytes_Up' => 256, 'Last_Seen_At' => $Now - 10],
['Device_ID' => 'dev-win', 'User_UUID' => 'uuid-hediye', 'Telegram_ID' => 0, 'Category' => 'app', 'Target' => 'Visual Studio Code', 'Hits' => 3, 'Bytes_Down' => 1024, 'Bytes_Up' => 128, 'Last_Seen_At' => $Now - 5],
['Device_ID' => 'dev-win', 'User_UUID' => 'uuid-hediye', 'Telegram_ID' => 0, 'Category' => 'app', 'Target' => 'Telegram', 'Hits' => 4, 'Bytes_Down' => 2048, 'Bytes_Up' => 512, 'Last_Seen_At' => $Now - 8],
['Device_ID' => 'dev-hediye', 'User_UUID' => 'uuid-hediye', 'Telegram_ID' => 0, 'Category' => 'app', 'Target' => 'Instagram', 'Hits' => 7, 'Bytes_Down' => 8192, 'Bytes_Up' => 1024, 'Last_Seen_At' => $Now - 2],
['Device_ID' => 'dev-hediye', 'User_UUID' => 'uuid-hediye', 'Telegram_ID' => 0, 'Category' => 'app', 'Target' => 'Telegram', 'Hits' => 6, 'Bytes_Down' => 4096, 'Bytes_Up' => 512, 'Last_Seen_At' => $Now - 3],
];

AdminFlow::userMonitorList($AdminCtx, 0);
check(str_contains(TelegramClient::$LastText, 'هدیه مرادی'), 'userMonitorList renders registered full name for unlinked app/software user');
check(str_contains(TelegramClient::$LastText, '🌐 2 سایت | 💻 2 نرم افزار | 📱 2 اپلیکیشن'), 'userMonitorList displays accurate separate counts for site, software, and mobile apps');

$Route = new ReflectionMethod(Dispatcher::class, 'routeCallbackInner');
$AdminCtx->CallbackData = 'admin_monitor_tab:d:1:0:software';
$Route->invoke(null, $AdminCtx);
check(str_contains(TelegramClient::$LastText, 'Visual Studio Code') && str_contains(TelegramClient::$LastText, 'Telegram') && !str_contains(TelegramClient::$LastText, 'Instagram') && !str_contains(TelegramClient::$LastText, 'github.com'), 'software filter shows Windows software only');

$AdminCtx->CallbackData = 'admin_monitor_tab:d:1:0:mobile';
$Route->invoke(null, $AdminCtx);
check(str_contains(TelegramClient::$LastText, 'Instagram') && str_contains(TelegramClient::$LastText, 'Telegram') && !str_contains(TelegramClient::$LastText, 'Visual Studio Code') && !str_contains(TelegramClient::$LastText, 'youtube.com'), 'mobile filter shows Android apps only');

$AdminCtx->CallbackData = 'admin_monitor_tab:d:1:0:site';
$Route->invoke(null, $AdminCtx);
check(str_contains(TelegramClient::$LastText, 'github.com') && str_contains(TelegramClient::$LastText, 'youtube.com') && !str_contains(TelegramClient::$LastText, 'Instagram') && !str_contains(TelegramClient::$LastText, 'Visual Studio Code'), 'site filter shows websites only');

// 3. Single-user & global HTML export
TelegramClient::$LastDocument = [];
$AdminCtx->CallbackData = 'admin_monitor_html:d:1';
$Route->invoke(null, $AdminCtx);
$Html = (string)(TelegramClient::$LastDocument['content'] ?? '');
check(str_contains($Html, 'هدیه مرادی') && str_contains($Html, 'github.com') && str_contains($Html, 'Visual Studio Code') && str_contains($Html, 'Instagram'), 'per-user HTML export includes identity and all three separated activity tables');
check(str_contains($Html, 'data-cat="site"') && str_contains($Html, 'data-cat="software"') && str_contains($Html, 'data-cat="mobile"'), 'HTML export includes interactive site/software/mobile filter blocks');
check(!is_file(TelegramClient::$LastDocument['path'] ?? ''), 'temporary HTML export file is removed after sendDocument');

echo "OK app_monitor_split_and_html_test ({$Checks} assertions)\n";
