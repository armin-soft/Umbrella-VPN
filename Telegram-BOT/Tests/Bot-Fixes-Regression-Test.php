<?php
declare(strict_types=1);

$Passed = 0;
function check(bool $Ok, string $Message): void {
global $Passed;
if (!$Ok) {
throw new RuntimeException('FAIL: ' . $Message);
}
$Passed++;
}

require_once dirname(__DIR__) . '/Bot/Menu.php';

function loadProd(string $Rel, bool $TrapExit = false): void {
$Code = (string)file_get_contents(dirname(__DIR__) . '/' . $Rel);
$Code = preg_replace('/^require_once .*;\s*$/m', '', $Code);
$Code = preg_replace('/^<\?php\s*declare\(strict_types=1\);/u', '', $Code);
$Code = preg_replace('/\?>\s*$/', '', $Code);
if ($TrapExit) {
$Code = str_replace("exit;\n", "throw new RuntimeException('__GATEWAY_STOP__');\n", $Code);
}
eval($Code);
}

final class Context {
public int $UserId = 1;
public int $ChatId = 1;
public ?int $MessageId = 10;
public ?string $CallbackId = 'cb-1';
public bool $IsCallback = true;
public ?string $CallbackData = '';
public function __construct(private bool $Admin = true) {}
public function isAdmin(): bool { return $this->Admin; }
public function profileName(): string { return 'کاربر آزمایشی'; }
}

final class Environment {
public static string $OtpSender = '';
public static string $SmsSender = '3000505';
public static string $OtpPattern = 'x7fhdaesmlj7vfi';
public static function get(string $Key, string $Default = ''): string {
if ($Key === 'IPPANEL_OTP_SENDER') return self::$OtpSender;
return $Default;
}
public static function getOtpPatternCode(): string { return self::$OtpPattern; }
public static function getOtpSender(): string { return self::$OtpSender !== '' ? self::$OtpSender : self::$SmsSender; }
public static function getSmsApiKey(): string { return 'test-api-key'; }
public static function getSmsSender(): string { return self::$SmsSender; }
public static function getSmsUrl(): string { return 'https://edge.ippanel.com/v1/api/send'; }
public static function getAdminUserId(): int { return 999; }
public static function getAdminFullName(): string { return 'مدیر'; }
public static function getAppGatewaySecret(): string { return 'secret-key-0123456789abcdef'; }
public static function getUmbrellaBaseUrl(): string { return ''; }
public static function getDateTimeApiUrl(): string { return ''; }
public static function getDateTimeApiLicense(): string { return ''; }
public static function getChannelUrl(): string { return 'https://t.me/UmbrellaVPN_Channel'; }
public static function getSupportUrl(): string { return 'https://t.me/UmbrellaSupport'; }
public static function getTelegramChannelId(): string { return '-1001'; }
public static function getRobotVersion(): string { return '1.0.2'; }
public static function showEmergencyConfig(): bool { return false; }
public static function getEmergencyConfigUrl(): string { return ''; }
public static function showNowruzMenu(): bool { return false; }
public static function getCustomDayRate(): float { return 1000; }
public static function getCustomMinDays(): int { return 1; }
public static function getCustomMaxDays(): int { return 365; }
public static function getCustomMinGB(): float { return 1; }
public static function getCustomMaxGB(): float { return 500; }
public static function getSignInTtl(): int { return 300; }
public static function getOtpCooldown(): int { return 120; }
public static function getAppOtpMaxHourly(): int { return 500; }
}

final class Helper {
public static function validatePhone(string $Phone): bool { return preg_match('/^09[0-9]{9}$/', $Phone) === 1; }
public static function toE164(string $Phone): string { return '+98' . substr($Phone, 1); }
public static function normalizePhone(string $Phone): string { return trim($Phone); }
public static function toPersian(string $Text): string { return $Text; }
public static function toEnglish(string $Text): string { return $Text; }
public static function userGreeting(Context $Context, string $Section): string { return $Section . "\n"; }
public static function adminGreeting(Context $Context, string $Section): string { return $Section . "\n"; }
public static function userFooter(): string { return ''; }
public static function adminFooter(): string { return ''; }
public static function formatDateTimeText(string $Value): string { return $Value; }
public static function formatBytes(int $Bytes): string { return $Bytes . ' B'; }
public static function formatCurrency(float $Value): string { return (string)$Value; }
public static function formatGB(float $Value): string { return $Value . ' GB'; }
public static function formatPercent(float $Value): string { return (string)$Value; }
public static function usageBar(float $Percent, int $Width = 12): string { return str_repeat('#', $Width); }
public static function rankEmoji(int $Rank): string { return '#'; }
public static function rankTitle(int $Rank): string { return 'rank'; }
public static function percentShare(float $Used, float $Total): string { return '10%'; }
public static function rankStatusIcon(float $Percent): string { return '🟢'; }
public static function rankStatusLabel(float $Percent): string { return 'عالی'; }
public static function remainingDuration(int $Stamp): string { return '10d'; }
public static function formatExpirationShort(int $Stamp): string { return '2026-12-10'; }
public static function parseServerTimeSafe(string $Value): int { return 0; }
public static function humanAgo(int $Stamp): string { return '1m'; }
public static function frame(string $Role, string $Name, string $Section, ?int $Id = null): string { return $Section . "\n"; }
public static function repairMojibake(string $Text): string { return $Text; }
public static function stripZwnj(string $Text): string { return $Text; }
public static function digitsToPersian(string $Text): string { return $Text; }
public static function formatPlatform(string $Value): string { return $Value; }
public static function formatPhoneDisplay(string $Value): string { return $Value; }
public static function __callStatic(string $Name, array $Args): string { return (string)($Args[0] ?? ''); }
}

final class Repository {
public const CLIENT_CONDITION = '1=1';
public static array $Settings = [];
public static array $Users = [];
public static array $Session = [];
public static array $SmsLogs = [];
public static array $Locks = [];
public static function getSetting(string $Key, mixed $Default = null): mixed {
return self::$Settings[$Key] ?? ($Key === 'Daily_Report_Time' ? '00:00' : $Default);
}
public static function setSetting(string $Key, mixed $Value): void { self::$Settings[$Key] = (string)$Value; }
public static function getUser(int $Id): ?array { return self::$Users[$Id] ?? null; }
public static function getUserSession(int $Id): array { return self::$Session; }
public static function updateUserSession(int $Id, array $Values): void { self::$Session = array_replace(self::$Session, $Values); }
public static function logSms(int $User_ID, string $Phone, string $Message, bool $Ok): void {
self::$SmsLogs[] = ['user_id' => $User_ID, 'phone' => $Phone, 'message' => $Message, 'ok' => $Ok];
}
public static function nightlyReportEnabled(int $Id): bool { return (self::$Settings['nightly_' . $Id] ?? '1') !== '0'; }
public static function claimDailyNotice(string $Category, string $Target, ?string $Day = null): bool {
$Key = 'DailyNotice_' . ($Day ?? '2026-11-26') . '_' . hash('sha256', $Category . ':' . $Target);
if ((string)self::getSetting($Key, '') !== '') return false;
self::$Settings[$Key] = (string)time();
return true;
}
public static function tryCronLock(string $Name, int $Ttl): bool {
if (isset(self::$Locks[$Name])) return false;
self::$Locks[$Name] = true;
return true;
}
public static function releaseCronLock(string $Name): void { unset(self::$Locks[$Name]); }
public static function findUserByPhone(string $Phone): ?array {
foreach (self::$Users as $U) {
if ((string)($U['Phone'] ?? '') === $Phone) return $U;
}
return null;
}
public static function updateUser(int $Id, array $Fields): void { self::$Users[$Id] = array_replace(self::$Users[$Id] ?? [], $Fields); }
public static function addSubscriptionLog(...$Args): void {}
public static function getSmsTemplate(string $Name): ?string { return null; }
public static function getBalance(int $Id): float { return 0; }
public static function userTickets(int $Id): array { return []; }
public static function openTickets(int $L = 100, int $O = 0): array { return []; }
public static function getBlockedUsers(): array { return []; }
}

final class Database {
public static array $Sessions = [];
public static array $Devices = [];
public static array $SignInRequests = [];
public static function getInstance(): self { return new self(); }
public function execute(string $Sql, array $Args = []): object {
$Rows = 0;
if (str_contains($Sql, 'INSERT IGNORE INTO `Settings`')) {
$Rows = isset(Repository::$Settings[$Args[0]]) ? 0 : 1;
if ($Rows) Repository::$Settings[$Args[0]] = $Args[1];
} elseif (str_contains($Sql, 'UPDATE `App_Sessions` SET `Revoked_At` = ? WHERE `Token_Hash` = ?')) {
foreach (self::$Sessions as &$S) {
if ($S['Token_Hash'] === $Args[1] && $S['Revoked_At'] === null) {
$S['Revoked_At'] = $Args[0];
$Rows++;
}
}
} elseif (str_contains($Sql, 'UPDATE `App_Sessions` SET `Revoked_At` = ? WHERE `Device_ID` = ?')) {
foreach (self::$Sessions as &$S) {
if ($S['Device_ID'] === $Args[1] && $S['Revoked_At'] === null) {
$S['Revoked_At'] = $Args[0];
$Rows++;
}
}
} elseif (str_contains($Sql, 'UPDATE `App_Devices` SET `Is_Trusted` = 0 WHERE `Device_ID` = ?')) {
foreach (self::$Devices as &$D) {
if ($D['Device_ID'] === $Args[0]) {
$D['Is_Trusted'] = 0;
$Rows++;
}
}
}
return new class($Rows) { public function __construct(private int $N) {} public function rowCount(): int { return $this->N; } };
}
public function fetch(string $Sql, array $Args = []): ?array {
if (str_contains($Sql, 'FROM `App_Sessions` WHERE `Token_Hash` = ?')) {
foreach (self::$Sessions as $S) {
if ($S['Token_Hash'] === ($Args[0] ?? '')) return $S;
}
} elseif (str_contains($Sql, 'FROM `App_SignIn_Requests` WHERE `Challenge` = ?')) {
foreach (self::$SignInRequests as $R) {
if ($R['Challenge'] === ($Args[0] ?? '')) return $R;
}
}
return null;
}
public function fetchOne(string $Sql, array $Args = []): ?array { return $this->fetch($Sql, $Args); }
public function fetchAll(string $Sql, array $Args = []): array {
if (str_contains($Sql, 'FROM `Users`')) return array_values(Repository::$Users);
return [];
}
public function scalar(string $Sql, array $Args = [], mixed $Default = 0): mixed { return $Default; }
}

final class HttpClient {
public static array $Calls = [];
public static array $Queue = [];
public static function post(string $Url, array $Payload, array $Headers = []): array {
self::$Calls[] = ['url' => $Url, 'payload' => $Payload];
$Next = array_shift(self::$Queue);
return $Next ?? ['StatusCode' => 200, 'Json' => ['meta' => ['status' => true]], 'Body' => '{"meta":{"status":true}}'];
}
}

final class TelegramClient {
public static array $LastMarkup = [];
public static string $LastText = '';
public static string $LastAlert = '';
public static array $SentChats = [];
public static function inlineKeyboard(array $Rows): array { return ['inline_keyboard' => $Rows]; }
public static function sendMessage(int $ChatId, string $Text, array $Markup = []): array {
self::$SentChats[] = $ChatId;
self::$LastText = $Text;
self::$LastMarkup = $Markup;
return ['ok' => true];
}
public static function editOrSendMessage(int $ChatId, ?int $MsgId, string $Text, array $Markup = []): void {
self::$LastText = $Text;
self::$LastMarkup = $Markup;
}
public static function editMessageText(int $ChatId, int $MsgId, string $Text, array $Markup = []): void {
self::$LastText = $Text;
self::$LastMarkup = $Markup;
}
public static function sendReadableMessage(int $ChatId, ?int $MsgId, string $Text, array $Markup = []): bool {
self::$LastText = $Text;
self::$LastMarkup = $Markup;
return true;
}
public static function sendSystemMessage(int $ChatId, string $Text, array $Markup = []): void {
self::$SentChats[] = $ChatId;
self::$LastText = $Text;
self::$LastMarkup = $Markup;
}
public static function answerCallbackQuery(?string $Id, string $Text = '', bool $Alert = false): void { self::$LastAlert = $Text; }
public static function sendChatAction(int $ChatId): void {}
}

final class SystemNotifications {
public static array $Queued = [];
public static function queue(int $UserId, string $Title, string $Body, string $Event = ''): int {
self::$Queued[] = ['user_id' => $UserId, 'title' => $Title, 'event' => $Event];
return 1;
}
public static function formatForWindowsApp(string $T, string $B, string $L = 'info'): array { return ['title' => $T, 'body' => $B, 'level' => $L]; }
}

final class ServerClient {
public static array $Live = [];
public static function liveUsers(): array { return self::$Live; }
public static function getUser(string $Uuid): array { return ['StatusCode' => 404, 'Json' => null]; }
public static function updateUser(...$Args): array { return ['StatusCode' => 200]; }
}

final class PanelClient {
public static function findByPhone(string $Phone): ?array { return ['uuid' => 'uuid-1', 'name' => 'Ali']; }
public static function findByTelegramId(int $Id): ?array { return ['uuid' => 'uuid-1', 'name' => 'Ali']; }
}

final class Common {
public static function mainButton(): array { return [['text' => '🏠منوی اصلی', 'callback_data' => 'منوی خدمات ربات']]; }
public static function greet(Context $C, string $S): string { return $S; }
public static function isRobotOn(): bool { return true; }
public static function syncSubscriptionFromServer(array $User, ?array $Live = null): array { return $User; }
public static function subscriptionFieldsFromServer(array $Row): array { return []; }
}

final class BotConfig {
public const KEY_EMERGENCY_URL = 'Emergency_Url';
public static function getPlanPrice(int|string $K): float { return 1000; }
public static function showEmergency(): bool { return false; }
public static function isNowruzMenuEnabled(): bool { return false; }
public static function isNowruzSeasonActive(): bool { return false; }
public static function isNowruzMenuConfigured(): bool { return false; }
public static function hasClaimedNowruz(int $U = 0, string $Uid = '', ?string $S = null): bool { return false; }
public static function source(string $K): string { return 'env'; }
public static function emergencyUrl(): string { return ''; }
}

final class AppFilter {
public const MAX_CUSTOM_DOMAINS = 200;
public const DOMAINS_PER_PAGE = 8;
public const BOT_CATEGORIES = [];
}
final class AppBypass {}
final class AppDeviceLimit {
public static function maxDevices(int $Id): int { return 1; }
public static function trustedDevices(string $Phone, int $Id = 0): array {
$Out = [];
foreach (Database::$Devices as $D) {
if ((int)($D['Is_Trusted'] ?? 0) === 1 && ((string)($D['Phone'] ?? '') === $Phone || (int)($D['Telegram_ID'] ?? 0) === $Id)) {
$Out[] = $D;
}
}
return $Out;
}
public static function check(string $Phone, string $DeviceId): array {
$Trusted = self::trustedDevices($Phone, 0);
$Known = false;
foreach ($Trusted as $D) {
if ($D['Device_ID'] === $DeviceId) $Known = true;
}
return ['allowed' => $Known || count($Trusted) < 1, 'limit' => 1, 'used' => count($Trusted), 'device_known' => $Known, 'telegram_id' => 0];
}
}
final class AppSchema { public static function ensureInstalled(): void {} }
final class AppAccountRevocation {}
final class DeviceDeletion {}
final class TicketMedia {}
final class UserFlow { public static function serviceMenu(Context $C): void {} }
final class SubscriptionFlow {}
final class PaymentFlow {}
final class ProfileFlow {}
final class ChannelMembership {}
final class AutoRenew {}

loadProd('Core/App/App-Two-Step.php');
loadProd('Bot/App-Link.php');
loadProd('Bot/Admin.php');
loadProd('Bot/Dispatcher.php');
loadProd('Core/SMS/IPPanel.php');
loadProd('Bot/Scheduler.php');
loadProd('Core/App/App-Gateway.php', true);

// ---------------------------------------------------------------------------
// 1. Global Admin 2FA control + AppFlow synchronization
// ---------------------------------------------------------------------------
check(AppTwoStep::globalEnabled() === true, 'global 2FA defaults to enabled');
check(AppTwoStep::enabled(10) === true, 'effective 2FA is enabled by default');

$Admin = new Context(true);
$Route = new ReflectionMethod(Dispatcher::class, 'routeCallbackInner');
$Admin->CallbackData = 'admin_2fa_menu';
$Route->invoke(null, $Admin);
check(str_contains(TelegramClient::$LastText, '🟢فعال'), 'admin 2FA menu shows active state');
$AdminBtns = array_column(array_merge(...(TelegramClient::$LastMarkup['inline_keyboard'] ?? [])), 'callback_data');
check(in_array('admin_2fa_off', $AdminBtns, true), 'admin 2FA menu offers disable button when active');
check(Menu::problems(TelegramClient::$LastMarkup['inline_keyboard'] ?? []) === [], 'admin 2FA menu keyboard is valid');

// Non-admin cannot toggle global 2FA
$User = new Context(false);
$User->UserId = 10;
$User->ChatId = 10;
$User->CallbackData = 'admin_2fa_off';
$Route->invoke(null, $User);
check(AppTwoStep::globalEnabled() === true, 'non-admin cannot disable global 2FA');

// Admin turns 2FA globally off
$Admin->CallbackData = 'admin_2fa_off';
$Route->invoke(null, $Admin);
check(AppTwoStep::globalEnabled() === false, 'admin disables global 2FA');
check(AppTwoStep::enabled(10) === false, 'effective 2FA becomes false for all users when globally disabled');
$AdminBtns = array_column(array_merge(...(TelegramClient::$LastMarkup['inline_keyboard'] ?? [])), 'callback_data');
check(in_array('admin_2fa_on', $AdminBtns, true), 'admin 2FA menu offers enable button when disabled');

// User opens app_2fa while globally disabled
Repository::$Users[10] = ['Telegram_ID' => 10, 'Phone' => '09123456789'];
$User->CallbackData = 'app_2fa';
$Route->invoke(null, $User);
check(str_contains(TelegramClient::$LastText, 'تنظیم شده از پنل مدیریت'), 'user 2FA page indicates admin global disable');
$UserBtns = array_column(array_merge(...(TelegramClient::$LastMarkup['inline_keyboard'] ?? [])), 'callback_data');
check(!in_array('app_2fa_on', $UserBtns, true), 'user cannot re-enable 2FA while globally disabled by admin');
$User->CallbackData = 'app_2fa_on';
$Route->invoke(null, $User);
check(AppTwoStep::enabled(10) === false, 'user callback cannot bypass global admin 2FA disable');

// Admin turns 2FA back on: user's per-account preference remains intact
$Admin->CallbackData = 'admin_2fa_on';
$Route->invoke(null, $Admin);
check(AppTwoStep::globalEnabled() === true && AppTwoStep::enabled(10) === true, 'admin re-enabling global 2FA restores effective 2FA');

// ---------------------------------------------------------------------------
// 2. IPPanel formatSender + sendPattern (+983000505 retry & webservice fallback)
// ---------------------------------------------------------------------------
$FormatSender = new ReflectionMethod(IppanelClient::class, 'formatSender');
check($FormatSender->invoke(null, '3000') === '3000', '4-digit bare short mask preserved');
check($FormatSender->invoke(null, '3000505') === '+983000505', '7-digit virtual sender gets +98 E.164 prefix');
check($FormatSender->invoke(null, '50004000') === '+9850004000', '8-digit virtual sender gets +98 E.164 prefix');
check($FormatSender->invoke(null, '+983000505') === '+983000505', 'E.164 sender preserved');

// Scenario A: configured sender 50004000 gets 400-2, retry +983000505 succeeds
Environment::$SmsSender = '50004000';
Environment::$OtpSender = '';
HttpClient::$Calls = [];
HttpClient::$Queue = [
['StatusCode' => 400, 'Json' => ['meta' => ['status' => false, 'message' => 'خطایی رخ داده است', 'message_code' => '400-2']], 'Body' => '{"meta":{"status":false,"message_code":"400-2"}}'],
['StatusCode' => 200, 'Json' => ['meta' => ['status' => true]], 'Body' => '{"meta":{"status":true}}'],
];
$RetryLogFile = tempnam(sys_get_temp_dir(), 'ippanel_retry_');
$PrevRetryLog = ini_set('error_log', $RetryLogFile ?: '');
$OkRetry = IppanelClient::sendPattern('09123456789', '654321');
if ($PrevRetryLog !== false) ini_set('error_log', $PrevRetryLog);
if ($RetryLogFile && is_file($RetryLogFile)) @unlink($RetryLogFile);
check($OkRetry === true, 'sendPattern succeeds via +983000505 shared pattern retry after 400-2');
check(count(HttpClient::$Calls) === 2, 'exactly two attempts made (configured sender then +983000505)');
check(HttpClient::$Calls[0]['payload']['from_number'] === '+9850004000', 'first attempt uses E.164 formatted configured sender');
check(HttpClient::$Calls[1]['payload']['from_number'] === '+983000505', 'second attempt retries IPPanel shared pattern sender +983000505');

// Scenario B: both pattern attempts get 400-2 => fallback to webservice without leaking OTP code
$ErrLogFile = tempnam(sys_get_temp_dir(), 'ippanel_err_');
$PrevErrLog = ini_set('error_log', $ErrLogFile ?: '');
Repository::$SmsLogs = [];
HttpClient::$Calls = [];
HttpClient::$Queue = [
['StatusCode' => 400, 'Json' => ['meta' => ['status' => false, 'message' => 'خطایی رخ داده است', 'message_code' => '400-2']], 'Body' => '400-2'],
['StatusCode' => 400, 'Json' => ['meta' => ['status' => false, 'message' => 'خطایی رخ داده است', 'message_code' => '400-2']], 'Body' => '400-2'],
['StatusCode' => 200, 'Json' => ['meta' => ['status' => true]], 'Body' => '{"meta":{"status":true}}'],
];
$SecretOtp = '918273';
$OkFallback = IppanelClient::sendPattern('09123456789', $SecretOtp);
if ($PrevErrLog !== false) ini_set('error_log', $PrevErrLog);
$ErrLogText = ($ErrLogFile && is_file($ErrLogFile)) ? (string)file_get_contents($ErrLogFile) : '';
if ($ErrLogFile && is_file($ErrLogFile)) @unlink($ErrLogFile);
check($OkFallback === true, 'sendPattern falls back to webservice when pattern endpoints return 400-2');
check(count(HttpClient::$Calls) === 3, 'two pattern attempts plus one webservice fallback');
check(HttpClient::$Calls[2]['payload']['sending_type'] === 'webservice', 'third call uses webservice sending_type');
check(!str_contains($ErrLogText, $SecretOtp), 'OTP code never written to PHP error_log');
check(str_contains($ErrLogText, 'Pattern=' . Environment::$OtpPattern) && str_contains($ErrLogText, 'From=+9850004000'), 'diagnostic log includes Pattern and E.164 From');
foreach (Repository::$SmsLogs as $LogEntry) {
check(!str_contains((string)$LogEntry['message'], $SecretOtp), 'OTP code never written to SMS_Logs');
}

// ---------------------------------------------------------------------------
// 3. Nightly Report: duplicate Users rows sharing Chat_ID or Client_ID never double-send
// ---------------------------------------------------------------------------
Repository::$Settings = [];
TelegramClient::$SentChats = [];
SystemNotifications::$Queued = [];
$Future = time() + 86400 * 10;
$BaseUser = [
'First_Name' => 'آرمین', 'Full_Name' => 'آرمین', 'Client_ID' => 'uuid-shared',
'Client_Status' => 'فعال', 'Subscription' => 'یک ماهه',
'Expiration_Time_Stamp' => $Future, 'Total_Usage_GB' => 50, 'Used_Usage_GB' => 5,
'Remaining_Usage_GB' => 45, 'Percent_Usage' => 10, 'Is_Blocked' => 0, 'Deactivation_Message' => '',
];
Repository::$Users = [
101 => $BaseUser + ['Telegram_ID' => 101, 'Chat_ID' => 777],
102 => $BaseUser + ['Telegram_ID' => 102, 'Chat_ID' => 777],
103 => $BaseUser + ['Telegram_ID' => 103, 'Chat_ID' => 888, 'Client_ID' => 'uuid-shared'],
];
ServerClient::$Live = [
['Telegram_ID' => 101, 'Client_ID' => 'uuid-shared', 'Server_Is_Active' => 1, 'Server_Enable' => 1, 'Total_Usage_GB' => 50, 'Used_Usage_GB' => 5, 'Value' => 5],
['Telegram_ID' => 102, 'Client_ID' => 'uuid-shared', 'Server_Is_Active' => 1, 'Server_Enable' => 1, 'Total_Usage_GB' => 50, 'Used_Usage_GB' => 5, 'Value' => 5],
['Telegram_ID' => 103, 'Client_ID' => 'uuid-shared', 'Server_Is_Active' => 1, 'Server_Enable' => 1, 'Total_Usage_GB' => 50, 'Used_Usage_GB' => 5, 'Value' => 5],
];
$SendNightly = new ReflectionMethod(Scheduler::class, 'sendUserUsageReportsIfDue');
$SendNightly->invoke(null);
check(count(TelegramClient::$SentChats) === 1, 'duplicate Chat_ID and Client_ID user rows receive strictly 1 nightly Telegram message');
check(count(SystemNotifications::$Queued) === 1, 'duplicate Chat_ID and Client_ID user rows receive strictly 1 nightly app notice');

$RepoSource = (string)file_get_contents(dirname(__DIR__) . '/Core/Storage/Repository.php');
check(str_contains($RepoSource, "if ((string)self::getSetting(\$Key, '') !== '')"), 'Repository::claimDailyNotice pre-checks Settings before INSERT IGNORE');

// ---------------------------------------------------------------------------
// 4. AppGateway::signOut releases device trust via session Token even when challenge is empty
// ---------------------------------------------------------------------------
$Token = 'raw-session-token-abc';
$TokenHash = hash('sha256', $Token);
Database::$Sessions = [
['Token_Hash' => $TokenHash, 'Device_ID' => 'dev-old-phone', 'Telegram_ID' => 101, 'Revoked_At' => null],
];
Database::$Devices = [
['Device_ID' => 'dev-old-phone', 'Phone' => '09123456789', 'Telegram_ID' => 101, 'Is_Trusted' => 1],
];
$SignOut = new ReflectionMethod(AppGateway::class, 'signOut');
ob_start();
try {
$SignOut->invoke(null, ['token' => $Token, 'challenge' => '']);
} catch (RuntimeException $Stop) {
check($Stop->getMessage() === '__GATEWAY_STOP__', 'signOut completed cleanly via AppGateway::ok()');
} finally {
$JsonOut = (string)ob_get_clean();
}
check(str_contains($JsonOut, '"ok":true'), 'signOut returned ok=true JSON payload');
check(Database::$Sessions[0]['Revoked_At'] !== null, 'signOut revokes App_Sessions row');
check(Database::$Devices[0]['Is_Trusted'] === 0, 'signOut untrusts App_Devices row via session token even with empty challenge');
$AfterLimit = AppDeviceLimit::check('09123456789', 'dev-reinstalled-phone');
check($AfterLimit['allowed'] === true && $AfterLimit['used'] === 0, 'reinstalled/new device can sign in after previous device signs out');

// Check Dart auth controllers preserve challenge before clearing state
foreach (['Android/lib/state/auth_controller.dart', 'Windows/lib/state/auth_controller.dart'] as $DartRel) {
$Dart = (string)file_get_contents(dirname(__DIR__, 2) . '/' . $DartRel);
check(str_contains($Dart, 'final String challenge = _challenge;') && str_contains($Dart, 'challenge: challenge'), $DartRel . ' captures challenge before clearing it during signOut');
}

echo "OK bot fixes regression suite ({$Passed} assertions)\n";
