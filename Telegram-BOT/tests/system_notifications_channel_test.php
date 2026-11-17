<?php
declare(strict_types=1);
// Offline behavioral tests: execute production classes with transport/storage fakes.
$Count = 0;
function check(bool $Ok, string $Message): void { global $Count; $Count++; if (!$Ok) throw new RuntimeException($Message); }
function loadClass(string $Path): void {
$Source = file_get_contents(__DIR__ . '/../' . $Path);
$Source = preg_replace('/^require_once .*;\s*$/m', '', $Source);
$Source = preg_replace('/^<\?php\s*declare\(strict_types=1\);/', '', $Source);
eval($Source);
}
final class Repository {
public static array $User = []; public static bool $Locked = false;
public static function getUser(int $Id): array { return self::$User; }
public static function updateUser(int $Id, array $Fields): void { self::$User = array_replace(self::$User, $Fields); }
public static function tryCronLock(...$Args): bool { if (self::$Locked) return false; return self::$Locked = true; }
public static function releaseCronLock(...$Args): void { self::$Locked = false; }
}
final class Database {
public static array $Devices = []; public static array $Notices = []; public static bool $Fail = false;
public static function getInstance(): self { return new self(); }
public function fetchAll(string $Sql, array $Args): array {
if (self::$Fail) throw new RuntimeException('simulated database failure');
if (str_contains($Sql, 'FROM `Users`')) return [['Telegram_ID' => 7]];
check(str_contains($Sql, '`Is_Trusted` = 1'), 'only trusted installs selected');
check(str_contains($Sql, '`Telegram_ID` IS NULL OR `Telegram_ID` = 0'), 'UUID match cannot override another explicit owner');
return self::$Devices;
}
public function execute(string $Sql, array $Args): void {
check(str_contains($Sql, 'ON DUPLICATE KEY'), 'atomic database deduplication');
self::$Notices[$Args[5]] = $Args;
}
public function transaction(callable $Callback): void { $Callback($this); }
}
final class TelegramClient {
public static bool $Fail = false; public static array $Messages = [];
public static string $MemberStatus = 'member'; public static int $Checks = 0;
public static function channelMemberStatus(...$Args): string { self::$Checks++; return self::$MemberStatus; }
public static function md(string $Text): string { return $Text; }
public static function sendMessage(int $Id, string $Text, array $Markup = []): array {
self::$Messages[] = [$Id, $Text]; if (self::$Fail) throw new RuntimeException('simulated Telegram outage'); return ['ok' => true];
}
}
final class ServerClient {
public static int $Code = 200; public static ?int $UpdateCode = null; public static bool $Exhausted = false; public static bool $Active = true; public static bool $Throw = false; public static array $Calls = [];
public static function getUser(string $Id): array { return ['StatusCode' => self::$Code, 'Json' => ['is_active' => self::$Active, 'enable' => self::$Active, 'usage_limit_GB' => 10, 'current_usage_GB' => self::$Exhausted ? 10 : 1]]; }
public static function updateUser(string $Id, array $Fields): array {
self::$Calls[] = [$Id, $Fields]; if (self::$Throw) throw new RuntimeException('simulated server outage'); return ['StatusCode' => self::$UpdateCode ?? self::$Code];
}
}
final class BotConfig {
public static function getTelegramChannelId(): string { return '-100123'; }
public static function getChannelUrl(): string { return 'https://t.me/example'; }
}
final class Environment { public static function getChannelGraceSeconds(): int { return 3600; } }
final class Helper {
public static function humanDuration(int $Seconds): string { return (string)$Seconds; }
public static function toPersian(string $Text): string { return $Text; }
}
loadClass('Core/App/System-Notifications.php');
loadClass('Bot/Channel-Membership.php');
loadClass('Bot/Scheduler.php');
function resetState(): void {
Repository::$User = ['Telegram_ID' => 7, 'Chat_ID' => 7, 'Client_ID' => 'account-7', 'Client_Status' => 'فعال', 'Subscription' => 'monthly', 'Expiration_Time_Stamp' => time() + 86400, 'Channel_Grace_Started_At' => time() - 7200];
Repository::$Locked = false; Database::$Devices = [['Device_ID' => 'first'], ['Device_ID' => 'second']]; Database::$Notices = []; Database::$Fail = false;
ServerClient::$Code = 200; ServerClient::$UpdateCode = null; ServerClient::$Exhausted = false; ServerClient::$Active = true; ServerClient::$Throw = false; ServerClient::$Calls = []; TelegramClient::$Messages = []; TelegramClient::$Fail = false;
}
resetState();
check(SystemNotifications::queue(7, 'notice', '<b>hello</b> &amp; world', 'event-1') === 2, 'all trusted devices queued');
$Rows = array_values(Database::$Notices);
check(array_column($Rows, 1) === ['first', 'second'], 'separate device delivery rows');
check($Rows[0][3] === 'hello & world' && $Rows[0][0] === 'account-7', 'plain text and account scoping');
SystemNotifications::queue(7, 'notice', 'same', 'event-1');
check(count(Database::$Notices) === 2, 'event replay does not duplicate');
SystemNotifications::queue(7, 'notice', 'new', 'event-2');
check(count(Database::$Notices) === 4, 'new event is not suppressed');
Database::$Devices = [];
check(SystemNotifications::queue(7, 'notice', 'hello', 'event-3') === 0 && count(Database::$Notices) === 4, 'no UUID or broadcast fallback without trusted devices');
check(SystemNotifications::queue(0, 'notice', 'hello') === 0, 'invalid user rejected');
Database::$Fail = true;
check(SystemNotifications::queue(7, 'notice', 'hello') === 0, 'queue outage is contained');
// Exercise the real wrapper, replacing only its dependency include and class name.
$Source = file_get_contents(__DIR__ . '/../Core/Telegram/Telegram.php');
$Start = strpos($Source, 'public static function sendSystemMessage(');
$End = strpos($Source, 'public static function sendMessage(', $Start);
$Method = preg_replace('/^require_once .*;\s*$/m', '', substr($Source, $Start, $End - $Start));
eval('class SystemTransport { ' . $Method . 'public static function sendMessage(int $Id, string $Text, array $Markup): array { return TelegramClient::sendMessage($Id, $Text, $Markup); }}');
resetState(); TelegramClient::$Fail = true;
try { SystemTransport::sendSystemMessage(7, 'system event'); } catch (RuntimeException) {}
check(count(Database::$Notices) === 2, 'Telegram failure cannot prevent app delivery');
resetState(); Database::$Fail = true; SystemTransport::sendSystemMessage(7, 'system event');
check(count(TelegramClient::$Messages) === 1, 'app failure cannot prevent Telegram delivery');
foreach ([0, 199, 300, 500] as $Code) {
resetState(); ServerClient::$Code = $Code;
check(!ChannelMembership::suspend(7), 'failed suspend returns false ' . $Code);
check(!isset(Repository::$User['Channel_Client_Disabled_At']), 'failed suspend does not claim ownership');
}
resetState(); ServerClient::$Active = false;
check(!ChannelMembership::suspend(7) && ServerClient::$Calls === [], 'already disabled server client not claimed');
resetState(); check(ChannelMembership::suspend(7), 'active client can be channel suspended');
$Suspended = Repository::$User;
check($Suspended['Channel_Client_Disabled_At'] > 0 && $Suspended['Server_Enable'] === 0, 'successful suspension recorded');
foreach ([0, 199, 300, 500] as $Code) {
Repository::$User = $Suspended; ServerClient::$Code = $Code;
check(ChannelMembership::restore(7) === 'pending', 'failed activation stays pending ' . $Code);
check(Repository::$User['Channel_Client_Disabled_At'] === $Suspended['Channel_Client_Disabled_At'], 'retry marker survives server error');
check(!Repository::$Locked, 'lock always released');
}
ServerClient::$Code = 200;
foreach ([0, 500] as $Code) {
Repository::$User = $Suspended; ServerClient::$UpdateCode = $Code;
check(ChannelMembership::restore(7) === 'pending' && Repository::$User['Channel_Client_Disabled_At'] > 0, 'GET succeeds but activation PUT fails, keep retry');
}
ServerClient::$UpdateCode = null; ServerClient::$Exhausted = true;
check(ChannelMembership::restore(7) === 'ineligible', 'exhausted quota cannot auto-reactivate');
ServerClient::$Exhausted = false; ServerClient::$Throw = true;
check(ChannelMembership::restore(7) === 'pending' && !Repository::$Locked, 'exception preserves retry and releases lock');
ServerClient::$Throw = false;
foreach ([['Is_Blocked' => 1], ['Deactivation_Message' => 'admin hold'], ['Client_Status' => '🚫غیر فعال'], ['Expiration_Time_Stamp' => time() - 1], ['Subscription' => ''], ['Client_ID' => '_']] as $Override) {
Repository::$User = array_replace($Suspended, $Override); ServerClient::$Calls = [];
check(ChannelMembership::restore(7) === 'ineligible' && ServerClient::$Calls === [], 'unrelated restrictions cannot be overridden');
}
Repository::$User = $Suspended; TelegramClient::$Fail = true;
check(ChannelMembership::restore(7) === 'restored', 'successful activation independent of Telegram');
check(Repository::$User['Channel_Client_Disabled_At'] === null && Repository::$User['Client_Status'] === 'فعال', 'clear flag only after success');
check(count(Database::$Notices) === 2, 'restoration reaches both devices');
$Before = count(ServerClient::$Calls);
check(ChannelMembership::restore(7) === 'member' && count(ServerClient::$Calls) === $Before, 'repeat membership does not reactivate twice');
Repository::$Locked = true;
check(ChannelMembership::restore(7) === 'pending', 'concurrent restore waits');
resetState();
$Warning = new ReflectionMethod(Scheduler::class, 'sendLeaveWarning');
$Warning->invoke(null, 0, 7, 'user', 'https://t.me/example', 10, false);
check(count(Database::$Notices) === 2, 'channel warning reaches all devices even without Telegram chat');
$Warning->invoke(null, 0, 7, 'user', 'https://t.me/example', 9, false);
check(count(Database::$Notices) === 2, 'reminder event is idempotent even as remaining time changes');
resetState(); ChannelMembership::suspend(7); Repository::$User['Chat_ID'] = 0;
$Event = ['chat_member' => ['chat' => ['id' => '-100999'], 'new_chat_member' => ['user' => ['id' => 7]]]];
$Before = TelegramClient::$Checks;
Scheduler::channelMembershipChanged($Event);
check(TelegramClient::$Checks === $Before, 'unrelated channel event ignored');
$Event['chat_member']['chat']['id'] = '-100123'; TelegramClient::$MemberStatus = 'unknown';
Scheduler::channelMembershipChanged($Event);
check(Repository::$User['Channel_Client_Disabled_At'] > 0, 'unknown Telegram membership never activates');
TelegramClient::$MemberStatus = 'member'; Scheduler::channelMembershipChanged($Event);
check(Repository::$User['Channel_Client_Disabled_At'] === null && count(Database::$Notices) === 2, 'real scheduler webhook path restores and notifies without Telegram chat');
$Dispatcher = file_get_contents(__DIR__ . '/../Bot/Dispatcher.php');
$Scheduler = file_get_contents(__DIR__ . '/../Bot/Scheduler.php');
$User = file_get_contents(__DIR__ . '/../Bot/User.php');
check(strpos($Dispatcher, "isset(\$Context->Raw['chat_member'])") < strpos($Dispatcher, '$Context->UserId <= 0'), 'membership updates processed before message-only guard');
check(str_contains($Scheduler, 'ChannelMembership::restore($User_ID)') && str_contains($User, 'ChannelMembership::restore($UserId)') && str_contains($User, 'ChannelMembership::restore($Context->UserId)'), 'scheduled, cached and manual checks share restoration policy');
$Admin = file_get_contents(__DIR__ . '/../Bot/Admin.php');
$Start = strpos($Admin, 'private static function deliver');
// The manual-send implementation has separate transport selection, no blanket Telegram interception.
check(str_contains($Admin, "TelegramClient::sendMessage((int)\$User['Chat_ID']"), 'manual delivery keeps normal Telegram transport');
check(!str_contains(substr($Source, strpos($Source, 'public static function sendMessage('), 800), 'SystemNotifications::'), 'ordinary Telegram sends are not mirrored');
check(str_contains($Scheduler, 'LIMIT 200') && str_contains($Scheduler, 'time() - 60'), 'pending membership checks bounded and retried independently of full scan interval');
echo "OK system notices/channel restoration ($Count assertions)\n";
