<?php
declare(strict_types=1);
$Checks = 0;
function check(bool $Ok, string $Name): void { global $Checks; $Checks++; if (!$Ok) throw new RuntimeException($Name); }
function loadProduction(string $Path): void {
$Code = file_get_contents(__DIR__ . '/../' . $Path);
$Code = preg_replace('/^require_once .*;\s*$/m', '', $Code);
$Code = preg_replace('/^<\?php\s*declare\(strict_types=1\);/', '', $Code);
$Code = preg_replace('/\?>\s*$/', '', $Code);
eval($Code);
}
final class Environment {
public static bool $Configured = true;
public static function getSmsApiKey(): string { return self::$Configured ? 'test' : ''; }
public static function getSmsSender(): string { return '3000'; }
public static function getSmsUrl(): string { return 'https://example.invalid/api/send'; }
}
final class Helper {
public static function validatePhone(string $Phone): bool { return $Phone === '09123456789'; }
public static function toE164(string $Phone): string { return '+989123456789'; }
public static function __callStatic(string $Name, array $Args): string { return 'test'; }
}
final class Repository {
public const CLIENT_CONDITION = '1=1';
public static array $Settings = []; public static array $Users = []; public static array $Off = [];
public static array $Reads = []; public static bool $LateBlock = false; public static bool $FailFinish = false;
public static array $Locks = []; public static bool $FailCleanup = false;
public static function updateUser(int $Id, array $Fields): void {
if (self::$FailCleanup && array_key_exists('Subscription', $Fields)) throw new RuntimeException('crash before expiry cleanup');
self::$Users[$Id] = array_replace(self::$Users[$Id], $Fields);
}
public static function addSubscriptionLog(...$Args): void {}
public static function getSmsTemplate(string $Name): ?string { return null; }
public static function getUser(int $Id): array {
self::$Reads[$Id] = (self::$Reads[$Id] ?? 0) + 1;
$U = self::$Users[$Id] ?? [];
if (self::$LateBlock && self::$Reads[$Id] >= 2) $U['Is_Blocked'] = 1;
return $U;
}
public static function getSetting(string $Key, mixed $Default = null): mixed { return self::$Settings[$Key] ?? ($Key === 'Daily_Report_Time' ? '00:00' : $Default); }
public static function setSetting(string $Key, mixed $Value): void { if (self::$FailFinish) throw new RuntimeException('state write failure'); self::$Settings[$Key] = $Value; }
public static function logSms(...$Args): void {}
public static function nightlyReportEnabled(int $Id): bool { return !in_array($Id, self::$Off, true); }
public static function tryCronLock(string $Key, int $Ttl): bool { if (isset(self::$Locks[$Key])) return false; self::$Locks[$Key] = true; return true; }
public static function releaseCronLock(string $Key): void { unset(self::$Locks[$Key]); }
}
final class Database {
public static bool $Fail = false;
public static function getInstance(): self { return new self(); }
public function execute(string $Sql, array $Args): object {
if (self::$Fail) throw new RuntimeException('claim DB unavailable');
check(str_contains($Sql, 'INSERT IGNORE'), 'claim uses atomic unique insert');
$Rows = isset(Repository::$Settings[$Args[0]]) ? 0 : 1;
if ($Rows) Repository::$Settings[$Args[0]] = $Args[1];
return new class($Rows) { public function __construct(private int $N) {} public function rowCount(): int { return $this->N; } };
}
// Return even ineligible rows: the runtime guard must protect both transports.
public function fetchAll(string $Sql, array $Args = []): array { return array_values(Repository::$Users); }
}
final class HttpClient {
public static int $Calls = 0; public static int $Code = 200; public static bool $Accepted = true; public static bool $Throw = false; public static bool $Reenter = false;
public static function post(...$Args): array {
self::$Calls++;
if (self::$Reenter) { self::$Reenter = false; IppanelClient::sendOnce(1, '09123456789', 'changed', 'concurrent'); }
if (self::$Throw) throw new RuntimeException('timeout after provider may have accepted');
return ['StatusCode' => self::$Code, 'Json' => ['meta' => ['status' => self::$Accepted]], 'Body' => 'test'];
}
}
final class ServerClient {
public static array $Live = []; public static int $Updates = 0;
public static function liveUsers(): array { return self::$Live; }
public static function updateUser(...$Args): array { self::$Updates++; return ['StatusCode' => 200]; }
}
final class SystemNotifications {
public static array $Sent = [];
public static function queue(int $Id, ...$Args): int { self::$Sent[] = $Id; return 1; }
}
final class TelegramClient {
public static array $Sent = [];
public static function inlineKeyboard(array $Rows): array { return $Rows; }
public static function sendMessage(int $Id, ...$Args): array { self::$Sent[] = $Id; return ['ok' => true]; }
}
final class Common { public static function mainButton(): array { return []; } }
loadProduction('Core/SMS/IPPanel.php');
loadProduction('Bot/Scheduler.php');
$Phone = '09123456789';
check(IppanelClient::sendOnce(1, $Phone, 'expiry', 'expired:old'), 'first event accepted');
for ($I = 0; $I < 4; $I++) check(IppanelClient::sendOnce(1, $Phone, 'changed text', 'expired:old'), 'repeat returns recorded acceptance');
check(HttpClient::$Calls === 1, 'repeat event sends once, not based on text');
IppanelClient::sendOnce(1, $Phone, 'expiry', 'expired:new');
IppanelClient::sendOnce(2, $Phone, 'expiry', 'expired:new');
check(HttpClient::$Calls === 3, 'new subscription and different user have independent events');
HttpClient::$Reenter = true;
IppanelClient::sendOnce(1, $Phone, 'event', 'concurrent');
check(HttpClient::$Calls === 4, 'simultaneous/reentrant worker cannot resend claimed event');
HttpClient::$Throw = true;
check(!IppanelClient::sendOnce(1, $Phone, 'event', 'timeout'), 'ambiguous transport failure reported');
HttpClient::$Throw = false;
check(!IppanelClient::sendOnce(1, $Phone, 'event', 'timeout') && HttpClient::$Calls === 5, 'timeout not retried automatically');
HttpClient::$Code = 429; HttpClient::$Accepted = false;
check(!IppanelClient::sendOnce(1, $Phone, 'event', 'rate-limit'), '429 is not success');
IppanelClient::sendOnce(1, $Phone, 'event', 'rate-limit');
check(HttpClient::$Calls === 6, 'failed event not repeatedly charged');
HttpClient::$Code = 200; HttpClient::$Accepted = true; Repository::$FailFinish = true;
check(!IppanelClient::sendOnce(1, $Phone, 'event', 'write-failure'), 'post-send DB failure is not false success');
Repository::$FailFinish = false;
IppanelClient::sendOnce(1, $Phone, 'event', 'write-failure');
check(HttpClient::$Calls === 7, 'post-send state failure retains claim');
Database::$Fail = true;
check(!IppanelClient::sendOnce(1, $Phone, 'event', 'db-down') && HttpClient::$Calls === 7, 'no send without durable claim');
Database::$Fail = false; Environment::$Configured = false;
IppanelClient::sendOnce(1, $Phone, 'event', 'configuration'); Environment::$Configured = true;
check(IppanelClient::sendOnce(1, $Phone, 'event', 'configuration'), 'configuration can be fixed before first network attempt');
check(!IppanelClient::sendOnce(1, 'invalid', 'event', 'bad-phone'), 'invalid phone rejected before claim');
$Base = ['Telegram_ID' => 1, 'Chat_ID' => 1, 'Is_Blocked' => 0, 'Client_ID' => 'client', 'Subscription' => 'monthly', 'Client_Status' => 'فعال', 'Expiration_Time_Stamp' => time() + 86400, 'Full_Name' => 'test'];
$Live = ['Telegram_ID' => 1, 'Client_ID' => 'client', 'Server_Is_Active' => 1, 'Server_Enable' => 1, 'Total_Usage_GB' => 10, 'Used_Usage_GB' => 1];
$Event = IppanelClient::subscriptionEvent('expired', $Base);
check($Event === IppanelClient::subscriptionEvent('expired', $Base + ['Phone' => 'other']), 'phone/text changes do not create a new expiration event');
check($Event === IppanelClient::subscriptionEvent('expired', array_replace($Base, ['Subscription' => 'renamed plan', 'Package_Start_Date' => 'updated display'])), 'plan/display edits cannot duplicate same subscription expiry');
check($Event !== IppanelClient::subscriptionEvent('expired', array_replace($Base, ['Expiration_Time_Stamp' => time() + 172800])), 'renewal changes expiration event');
$Eligible = new ReflectionMethod(Scheduler::class, 'nightlyRecipientEligible');
check($Eligible->invoke(null, $Base, $Live), 'active local and live subscription eligible');
$Overrides = [['Is_Blocked' => 1], ['Client_Status' => '🚫غیر فعال'], ['Client_Status' => 'غیرفعال'], ['Subscription' => ''], ['Expiration_Time_Stamp' => time() - 1], ['Client_ID' => '_'], ['Channel_Client_Disabled_At' => time()], ['Deactivation_Message' => 'admin hold']];
foreach ($Overrides as $Override) check(!$Eligible->invoke(null, array_replace($Base, $Override), $Live), 'inactive local state excluded: ' . json_encode($Override));
foreach ([null, array_replace($Live, ['Server_Is_Active' => 0]), array_replace($Live, ['Server_Enable' => 0]), array_replace($Live, ['Client_ID' => 'other']), array_replace($Live, ['Used_Usage_GB' => 10])] as $BadLive) check(!$Eligible->invoke(null, $Base, $BadLive), 'inactive/missing/mismatched/exhausted live state excluded');
Repository::$Users = [1 => $Base]; ServerClient::$Live = [$Live];
foreach ($Overrides as $Index => $Override) {
$Id = $Index + 2;
Repository::$Users[$Id] = array_replace($Base, $Override, ['Telegram_ID' => $Id, 'Chat_ID' => $Id]);
ServerClient::$Live[] = array_replace($Live, ['Telegram_ID' => $Id]);
}
Repository::$Users[20] = array_replace($Base, ['Telegram_ID' => 20, 'Chat_ID' => 20]);
ServerClient::$Live[] = array_replace($Live, ['Telegram_ID' => 20, 'Server_Enable' => 0]);
Repository::$Users[21] = array_replace($Base, ['Telegram_ID' => 21, 'Chat_ID' => 21]);
ServerClient::$Live[] = array_replace($Live, ['Telegram_ID' => 21]); Repository::$Off = [21];
$Report = new ReflectionMethod(Scheduler::class, 'sendUserUsageReportsIfDue');
$Report->invoke(null);
check(TelegramClient::$Sent === [1] && SystemNotifications::$Sent === [1], 'actual report pipeline sends ONLY eligible user on both transports');
$Report->invoke(null);
check(TelegramClient::$Sent === [1], 'daily repeat suppressed');
unset(Repository::$Settings['Last_User_Usage_Report']); Repository::$Reads = []; Repository::$LateBlock = true;
$Report->invoke(null);
check(TelegramClient::$Sent === [1] && SystemNotifications::$Sent === [1], 'block during formatting checked before either transport');
Repository::$LateBlock = false; unset(Repository::$Settings['Last_User_Usage_Report']); ServerClient::$Live = [];
$Report->invoke(null);
check(TelegramClient::$Sent === [1], 'no local-only fallback when live state unavailable');
$Expire = new ReflectionMethod(Scheduler::class, 'expireSubscription');
$Expire->invoke(null, 1);
check(ServerClient::$Updates === 0 && Repository::$Locks === [], 'stale expiry job cannot disable renewed subscription, lock released');
Repository::$Users[1] = array_replace($Base, ['Expiration_Time_Stamp' => time() - 1, 'Phone' => $Phone]);
$ExpiredSnapshot = Repository::$Users[1]; $Before = HttpClient::$Calls; Repository::$FailCleanup = true;
try { $Expire->invoke(null, 1); } catch (RuntimeException $Error) { check(str_contains($Error->getMessage(), 'cleanup'), 'simulated crash after SMS'); }
Repository::$FailCleanup = false; $Expire->invoke(null, 1); $Expire->invoke(null, 1);
check(HttpClient::$Calls === $Before + 1, 'actual expiry re-execution after crash sends only one SMS');
check(Repository::$Locks === [] && Repository::$Users[1]['Subscription'] === null, 'expiry cleanup and lock release complete');
IppanelClient::sendOnce(1, $Phone, 'manual expiration text', IppanelClient::subscriptionEvent('expired', $ExpiredSnapshot));
check(HttpClient::$Calls === $Before + 1, 'manual expiration racing same scheduler event cannot resend');
$Scheduler = file_get_contents(__DIR__ . '/../Bot/Scheduler.php');
check(!str_contains($Scheduler, 'IppanelClient::send('), 'all scheduler SMS use durable event deduplication');
$Admin = file_get_contents(__DIR__ . '/../Bot/Admin.php');
check(str_contains($Admin, "subscriptionEvent('expired', \$User)") && str_contains($Scheduler, "subscriptionEvent('expired', \$Row)"), 'manual and automatic expiration share event identity');
echo "OK once-only SMS and active-only nightly reports ($Checks assertions)\n";
