<?php
declare(strict_types=1);

$Checks = 0;
function check(bool $Condition, string $Name): void {
global $Checks;
$Checks++;
if (!$Condition) throw new RuntimeException("FAIL: {$Name}");
}

function loadProduction(string $Path): void {
$Code = (string)file_get_contents(__DIR__ . '/../' . $Path);
$Code = (string)preg_replace('/^require_once .*;\s*$/m', '', $Code);
$Code = (string)preg_replace('/^<\?php\s*declare\(strict_types=1\);/', '', $Code);
$Code = (string)preg_replace('/\?>\s*$/', '', $Code);
eval($Code);
}

final class FakeStmt {
public function __construct(private int $Rows) {}
public function rowCount(): int { return $this->Rows; }
}

final class Database {
private static ?self $Instance = null;
public static function getInstance(): self { return self::$Instance ??= new self(); }
public function execute(string $Sql, array $Args = []): FakeStmt {
if (str_contains($Sql, 'INSERT IGNORE INTO `Settings`')) {
$Key = (string)$Args[0];
if (array_key_exists($Key, Repository::$Settings)) return new FakeStmt(0);
Repository::$Settings[$Key] = (string)$Args[1];
return new FakeStmt(1);
}
return new FakeStmt(1);
}
public function fetchAll(string $Sql, array $Args = []): array {
if (str_contains($Sql, 'Auto_Renew_Plan')) {
$Threshold = (int)$Args[0];
$Now = (int)$Args[1];
$Out = [];
foreach (Repository::$Users as $U) {
$Plan = (string)($U['Auto_Renew_Plan'] ?? '');
$Exp = (int)($U['Expiration_Time_Stamp'] ?? 0);
if ($Plan !== '' && (int)($U['Is_Blocked'] ?? 0) === 0 && $Exp <= $Threshold && $Exp > $Now) {
$Out[] = $U;
}
}
return $Out;
}
if (str_contains($Sql, 'Expiration_Time_Stamp` > ?')) {
$Lo = (int)$Args[0];
$Hi = (int)$Args[1];
$Out = [];
foreach (Repository::$Users as $Id => $U) {
$Exp = (int)($U['Expiration_Time_Stamp'] ?? 0);
$Sub = trim((string)($U['Subscription'] ?? ''));
if ((int)($U['Is_Blocked'] ?? 0) === 0 && $Sub !== '' && $Exp > $Lo && $Exp <= $Hi) {
$Out[] = ['Telegram_ID' => $Id];
}
}
return $Out;
}
return array_values(Repository::$Users);
}
public function fetch(string $Sql, array $Args = []): ?array {
return ['c' => count(Repository::$Users), 's' => 0];
}
}

final class Environment {
public static function getSmsApiKey(): string { return 'key'; }
public static function getSmsSender(): string { return '3000'; }
public static function getSmsUrl(): string { return 'https://example.invalid/sms'; }
public static function getAdminUserId(): int { return 999; }
public static function getAdminFullName(): string { return 'Admin'; }
}

final class BotConfig {
public static array $Prices = [];
public static function getPlanPrice(string $Plan): int { return self::$Prices[$Plan] ?? 0; }
public static function getSupportUrl(): string { return 'https://t.me/support'; }
}

final class Helper {
public static function validatePhone(string $Phone): bool { return $Phone === '09123456789'; }
public static function toE164(string $Phone): string { return '+989123456789'; }
public static function __callStatic(string $Name, array $Args): string { return 'test'; }
}

final class Common {
public static function mainButton(): array { return []; }
public static function greet(object $Ctx, string $Section): string { return ''; }
}

final class Context {
public function __construct(mixed ...$Args) {}
}

final class HttpClient {
public static int $SmsCalls = 0;
public static function post(mixed ...$Args): array {
self::$SmsCalls++;
return ['StatusCode' => 200, 'Json' => ['meta' => ['status' => true]], 'Body' => 'ok'];
}
}

final class TelegramClient {
public static array $AllByChat = [];
public static bool $ReturnFailure = false;
public static function inlineKeyboard(array $Rows): array { return $Rows; }
public static function sendMessage(int $ChatId, string $Text, mixed $Markup = null): array {
self::$AllByChat[$ChatId][] = $Text;
return ['ok' => !self::$ReturnFailure];
}
public static function sendSystemMessage(int $ChatId, string $Text, mixed $Markup = null): array {
self::$AllByChat[$ChatId][] = $Text;
return ['ok' => !self::$ReturnFailure];
}
}

final class SystemNotifications {
public static array $Queued = [];
public static function queue(int $UserId, string $Title, string $Body, string $EventKey = '', string $Level = 'info'): int {
self::$Queued[$UserId][] = [$Title, $EventKey];
return 1;
}
}

final class ServerClient {
public static array $Live = [];
public static int $UpdateStatus = 200;
public static function liveUsers(): array { return self::$Live; }
public static function getUser(string $Uuid): array {
return ['StatusCode' => 200, 'Json' => ['uuid' => $Uuid, 'is_active' => true, 'enable' => true, 'current_usage_GB' => 5.0, 'usage_limit_GB' => 50.0]];
}
public static function updateUser(string $Uuid, array $Payload): array {
return ['StatusCode' => self::$UpdateStatus, 'Body' => 'err', 'Json' => self::$UpdateStatus === 200 ? ['uuid' => $Uuid] : null];
}
}

final class AdminFlow {
public static int $Errors = 0;
public static function notifyAdminServerError(mixed ...$Args): void { self::$Errors++; }
}

final class Repository {
public const CLIENT_CONDITION = '1=1';
public static string $Day = '2026-11-17';
public static array $Settings = [];
public static array $Users = [];
public static array $Locks = [];
public static array $Templates = [
'expire_warn_3' => '{full_name} {plan} {days} {remaining}',
'expire_warn_2' => '{full_name} {plan} {days} {remaining}',
'expire_warn_1' => '{full_name} {plan} {days} {remaining}',
'expired' => '{full_name} {plan} expired',
'channel_warning' => '{full_name} {minutes} {channel}',
'channel_disabled' => '{full_name} {channel}',
];
public static function tehranToday(): string { return self::$Day; }
public static function claimDailyNotice(string $Category, int|string $Target, ?string $Day = null): bool {
$D = $Day ?? self::$Day;
$Key = 'DailyNotice_' . $D . '_' . hash('sha256', trim($Category) . ':' . trim((string)$Target));
return Database::getInstance()->execute('INSERT IGNORE INTO `Settings` (`Key`, `Value`) VALUES (?, ?)', [$Key, '1'])->rowCount() === 1;
}
public static function claimOnceNotice(string $Key, string $Value = '1'): bool {
return Database::getInstance()->execute('INSERT IGNORE INTO `Settings` (`Key`, `Value`) VALUES (?, ?)', [$Key, $Value])->rowCount() === 1;
}
public static function purgeOldDailyNotices(int $KeepDays = 14): void {}
public static function getSetting(string $Key, mixed $Default = null): mixed { return self::$Settings[$Key] ?? $Default; }
public static function setSetting(string $Key, mixed $Value): void { self::$Settings[$Key] = (string)$Value; }
public static function deleteSetting(string $Key): void { unset(self::$Settings[$Key]); }
public static function logSms(mixed ...$Args): void {}
public static function getSmsTemplate(string $Code): ?string { return self::$Templates[$Code] ?? null; }
public static function tryCronLock(string $Name, int $Ttl = 300): bool {
if (isset(self::$Locks[$Name])) return false;
self::$Locks[$Name] = true;
return true;
}
public static function releaseCronLock(string $Name): void { unset(self::$Locks[$Name]); }
public static function getUser(int $Id): array { return self::$Users[$Id] ?? []; }
public static function updateUser(int $Id, array $Fields): void { self::$Users[$Id] = array_replace(self::$Users[$Id] ?? [], $Fields); }
public static function allUserIds(): array { return array_keys(self::$Users); }
public static function nightlyReportEnabled(int $Id): bool { return true; }
public static function addSubscriptionLog(mixed ...$Args): void {}
public static function removeMoney(int $Id, float $Amount, string $Desc, string $By): bool {
$Bal = (float)(self::$Users[$Id]['Balance'] ?? 0);
if ($Bal < $Amount) return false;
self::$Users[$Id]['Balance'] = $Bal - $Amount;
return true;
}
public static function addMoney(int $Id, float $Amount, string $Desc, string $By): void {
self::$Users[$Id]['Balance'] = (float)(self::$Users[$Id]['Balance'] ?? 0) + $Amount;
}
}

function resetAll(): void {
Repository::$Day = (new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran')))->format('Y-m-d');
Repository::$Settings = [
'Administrator' => '999',
'Daily_Report_Time' => '00:00',
'User_Usage_Report_Enabled' => '1',
];
Repository::$Users = [];
Repository::$Locks = [];
BotConfig::$Prices = [];
TelegramClient::$AllByChat = [];
TelegramClient::$ReturnFailure = false;
SystemNotifications::$Queued = [];
HttpClient::$SmsCalls = 0;
ServerClient::$Live = [];
ServerClient::$UpdateStatus = 200;
AdminFlow::$Errors = 0;
}

loadProduction('Core/SMS/IPPanel.php');
loadProduction('Core/Subscription/Auto-Renew.php');
loadProduction('Bot/Channel-Membership.php');
loadProduction('Bot/Scheduler.php');

$SendExpiry = new ReflectionMethod(Scheduler::class, 'sendExpiryWarnings');
$SendNightly = new ReflectionMethod(Scheduler::class, 'sendUserUsageReportsIfDue');
$SendLeave = new ReflectionMethod(Scheduler::class, 'sendLeaveWarning');
$Expire = new ReflectionMethod(Scheduler::class, 'expireSubscription');
$AlertSync = new ReflectionMethod(Scheduler::class, 'alertUsageSyncFailure');

// 1) Renewal warnings: 15 runs across 3d -> 2d -> 1d boundaries + server drift + ambiguous Telegram response + auto-renew low balance => STRICTLY 1/day!
resetAll();
Repository::$Day = '2026-11-17';
$Now = time();
Repository::$Users[10] = [
'Telegram_ID' => 10,
'Chat_ID' => 10,
'Full_Name' => 'علی',
'Phone' => '09123456789',
'Client_ID' => 'uuid-1',
'Client_Status' => 'فعال',
'Subscription' => 'اشتراک یک ماهه',
'Expiration_Time_Stamp' => $Now + (3 * 86400) + 600,
'Is_Blocked' => 0,
'Deactivation_Message' => '',
'Auto_Renew_Plan' => '1',
'Balance' => 1000,
];
Repository::$Users[11] = array_replace(Repository::$Users[10], ['Telegram_ID' => 11, 'Chat_ID' => 11, 'Is_Blocked' => 1]);
Repository::$Users[12] = array_replace(Repository::$Users[10], ['Telegram_ID' => 12, 'Chat_ID' => 12, 'Client_Status' => '🚫غیر فعال']);
BotConfig::$Prices = ['1' => 500000];

TelegramClient::$ReturnFailure = true;
for ($I = 0; $I < 5; $I++) {
$SendExpiry->invoke(null);
AutoRenew::processDue(3);
}
TelegramClient::$ReturnFailure = false;
Repository::$Users[10]['Expiration_Time_Stamp'] = $Now + (2 * 86400) + 600;
for ($I = 0; $I < 5; $I++) {
$SendExpiry->invoke(null);
AutoRenew::processDue(3);
}
Repository::$Users[10]['Expiration_Time_Stamp'] = $Now + (1 * 86400) + 600;
for ($I = 0; $I < 5; $I++) {
$SendExpiry->invoke(null);
AutoRenew::processDue(3);
}
check(count(TelegramClient::$AllByChat[10] ?? []) === 1, 'renewal Telegram strictly 1/day across all boundaries, drift, and auto-renew');
check(count(SystemNotifications::$Queued[10] ?? []) === 1, 'renewal app notice strictly 1/day across all boundaries');
check(HttpClient::$SmsCalls === 1, 'renewal SMS strictly 1/day across all boundaries');
check(count(TelegramClient::$AllByChat[11] ?? []) === 0, 'blocked user receives zero renewal notices');
check(count(TelegramClient::$AllByChat[12] ?? []) === 0, 'disabled user receives zero renewal notices');

// Next Tehran day: entering 1-day boundary sends strictly 1 more and zero repeats.
Repository::$Day = '2026-11-18';
for ($I = 0; $I < 5; $I++) {
$SendExpiry->invoke(null);
AutoRenew::processDue(3);
}
check(count(TelegramClient::$AllByChat[10] ?? []) === 2, 'next day sends strictly 1 renewal Telegram');
check(count(SystemNotifications::$Queued[10] ?? []) === 2, 'next day sends strictly 1 renewal app notice');
check(HttpClient::$SmsCalls === 2, 'next day sends strictly 1 renewal SMS');

// 2) Auto-renew low balance runs BEFORE sendExpiryWarnings => still strictly 1 total/day!
resetAll();
Repository::$Day = '2026-11-17';
Repository::$Users[20] = [
'Telegram_ID' => 20,
'Chat_ID' => 20,
'Full_Name' => 'مریم',
'Phone' => '09123456789',
'Client_ID' => 'uuid-1',
'Client_Status' => 'فعال',
'Subscription' => 'اشتراک یک ماهه',
'Expiration_Time_Stamp' => time() + 86400 + 300,
'Is_Blocked' => 0,
'Auto_Renew_Plan' => '1',
'Balance' => 0,
];
BotConfig::$Prices = ['1' => 250000];
for ($I = 0; $I < 5; $I++) {
AutoRenew::processDue(3);
$SendExpiry->invoke(null);
}
check(count(TelegramClient::$AllByChat[20] ?? []) === 1, 'auto-renew low balance + expiry warning share single daily cap');

BotConfig::$Prices = [];
for ($I = 0; $I < 5; $I++) {
AutoRenew::processDue(3);
}
check(count(TelegramClient::$AllByChat[999] ?? []) === 1, 'missing plan price alerts admin strictly once per day');

// 3) Nightly report: 5 runs even when Last_User_Usage_Report is lost mid-batch => strictly 1/day!
resetAll();
Repository::$Users[30] = [
'Telegram_ID' => 30,
'Chat_ID' => 30,
'First_Name' => 'سارا',
'Full_Name' => 'سارا',
'Client_ID' => 'uuid-1',
'Client_Status' => 'فعال',
'Subscription' => 'اشتراک یک ماهه',
'Expiration_Time_Stamp' => time() + 86400 * 10,
'Total_Usage_GB' => 50,
'Used_Usage_GB' => 5,
'Remaining_Usage_GB' => 45,
'Percent_Usage' => 10,
'Is_Blocked' => 0,
'Deactivation_Message' => '',
];
ServerClient::$Live = [[
'Telegram_ID' => 30,
'Client_ID' => 'uuid-1',
'Server_Is_Active' => 1,
'Server_Enable' => 1,
'Total_Usage_GB' => 50,
'Used_Usage_GB' => 5,
'Value' => 5,
]];
for ($I = 0; $I < 5; $I++) {
unset(Repository::$Settings['Last_User_Usage_Report']);
$SendNightly->invoke(null);
}
check(count(TelegramClient::$AllByChat[30] ?? []) === 1, 'nightly Telegram strictly 1/day even after mid-batch crash');
check(count(SystemNotifications::$Queued[30] ?? []) === 1, 'nightly app notice strictly 1/day even after mid-batch crash');

// 4) Channel leave/rejoin cycle repeated 5 times on same day => strictly 1/day!
resetAll();
for ($I = 0; $I < 5; $I++) {
Repository::$Users[40] = [
'Telegram_ID' => 40,
'Chat_ID' => 40,
'Full_Name' => 'رضا',
'Phone' => '09123456789',
'Client_ID' => 'uuid-1',
'Client_Status' => ChannelMembership::REASON,
'Channel_Grace_Started_At' => time() - ($I * 600) - 60,
'Channel_Client_Disabled_At' => time() - 30 - $I,
'Subscription' => 'اشتراک یک ماهه',
'Expiration_Time_Stamp' => time() + 86400 * 5,
'Is_Blocked' => 0,
'Deactivation_Message' => '',
];
$SendLeave->invoke(null, 40, 40, 'رضا', 'https://t.me/channel', 10, true);
$SendLeave->invoke(null, 40, 40, 'رضا', 'https://t.me/channel', 5, false);
ChannelMembership::restore(40);
}
check(count(TelegramClient::$AllByChat[40] ?? []) === 2, 'strictly 1 channel warning + 1 channel restore Telegram per day');
check(count(SystemNotifications::$Queued[40] ?? []) === 2, 'strictly 1 channel warning + 1 channel restore app notice per day');
check(HttpClient::$SmsCalls === 1, 'strictly 1 channel warning SMS per day');

// 5) Expiry notices + server failure repeated 5 times on same day => strictly 1/day!
resetAll();
ServerClient::$UpdateStatus = 500;
for ($I = 0; $I < 5; $I++) {
Repository::$Users[50] = [
'Telegram_ID' => 50,
'Chat_ID' => 50,
'Full_Name' => 'امیر',
'Phone' => '09123456789',
'Client_ID' => 'uuid-1',
'Client_Status' => 'فعال',
'Subscription' => 'اشتراک یک ماهه',
'Expiration_Time_Stamp' => time() - 10 - $I,
'Is_Blocked' => 0,
];
$Expire->invoke(null, 50);
}
check(count(TelegramClient::$AllByChat[50] ?? []) === 1, 'expiry Telegram strictly 1/day');
check(count(SystemNotifications::$Queued[50] ?? []) === 1, 'expiry app notice strictly 1/day');
check(HttpClient::$SmsCalls === 1, 'expiry SMS strictly 1/day');
check(AdminFlow::$Errors === 1, 'expiry server error admin alert strictly 1/day per user');

// 6) Usage sync failure alert repeated 5 times => strictly 1/day!
resetAll();
for ($I = 0; $I < 5; $I++) {
$AlertSync->invoke(null, 502, 'bad gateway');
}
check(count(TelegramClient::$AllByChat[999] ?? []) === 1, 'usage sync failure alerts admin strictly 1/day');

// 7) Static structural contracts.
$Root = dirname(__DIR__);
$RepoSource = (string)file_get_contents($Root . '/Core/Storage/Repository.php');
$SchedSource = (string)file_get_contents($Root . '/Bot/Scheduler.php');
$SchemaSql = (string)file_get_contents($Root . '/Database/Schema.SQL');
check(str_contains($RepoSource, 'function claimDailyNotice') && str_contains($RepoSource, 'INSERT IGNORE INTO `Settings`'), 'atomic daily notice claim in Repository');
check(str_contains($RepoSource, 'DELETE FROM `Cron_Lock` WHERE `Job_Name` = ? AND `Locked_At`'), 'cron lock cleanup scoped per job');
check(str_contains($SchedSource, "tryCronLock('scheduler_tick'"), 'scheduler tick serialized with atomic lock');
check(!str_contains($SchedSource, '% 240 < 60'), '4-minute channel repeat loop removed');
check(str_contains($SchemaSql, "DEFAULT 'ناموفق'") && str_contains($SchemaSql, "'🟢روشن'"), 'Schema.SQL Persian defaults clean');

echo "OK: {$Checks} daily-once notification checks passed\n";
