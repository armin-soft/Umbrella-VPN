<?php
declare(strict_types=1);
$Count = 0;
function check(bool $Ok, string $Why): void { global $Count; $Count++; if (!$Ok) throw new RuntimeException($Why); }
function loadClass(string $Path, string $Class): void {
$Source = file_get_contents(__DIR__ . '/../' . $Path);
eval(preg_replace('/\?>\s*$/', '', substr($Source, strpos($Source, 'final class ' . $Class . ' {'))));
}
require_once __DIR__ . '/../Bot/Menu.php';
final class Context {
public ?string $CallbackData = ''; public bool $IsCallback = true;
public int $UserId = 99; public int $ChatId = 99; public ?int $MessageId = 1; public ?string $CallbackId = 'cb';
public function __construct(private bool $Admin = true) {} public function isAdmin(): bool { return $this->Admin; }
}
final class Repository {
public static array $Settings = []; public static array $Logs = [];
public static function getUserSession(int $Id): array { return []; }
public static function setSetting(string $Key, string $Value): void { self::$Settings[$Key] = $Value; }
public static function logAdminAction(...$Args): void { self::$Logs[] = $Args; }
public static function getUser(int $Id): ?array { return Database::$Users[$Id] ?? null; }
}
final class Common { public static function greet(Context $Context, string $Title): string { return $Title; } }
final class Helper {
public static function userFooter(): string { return ''; }
public static function toPersian(string $Text): string { return $Text; }
public static function adminGreeting(Context $C, string $Title): string { return $Title . "\n"; }
public static function adminFooter(): string { return ''; }
}
final class TelegramClient {
public static string $Text = ''; public static array $Rows = []; public static array $Answers = [];
public static function sendMessage(int $Id, string $Text, array $Markup = []): void { self::$Text = $Text; self::$Rows = $Markup; }
public static function inlineKeyboard(array $Rows): array { return $Rows; }
public static function editOrSendMessage(int $Chat, ?int $Message, string $Text, array $Rows): void { self::$Text = $Text; self::$Rows = $Rows; }
public static function answerCallbackQuery(?string $Id, string $Text, bool $Alert = false): void { self::$Answers[] = $Text; }
}
final class Database {
public static array $Devices = []; public static array $Users = []; public static array $Sessions = []; public static array $Requests = []; public static array $Notices = [];
public static bool $Fail = false; public static int $Queries = 0; public static array $LastParams = [];
public static function getInstance(): self { return new self(); }
public function scalar(string $Sql, array $Args = [], int $Default = 0): int { self::$Queries++; return str_contains($Sql, '`Users`') ? count(self::$Users) : count(self::$Devices); }
public function fetch(string $Sql, array $Args): ?array {
self::$Queries++;
check(str_contains($Sql, 'FOR UPDATE'), 'confirmation record locked');
return isset(Repository::$Settings[$Args[0]]) ? ['Value' => Repository::$Settings[$Args[0]]] : null;
}
public function fetchAll(string $Sql, array $Args): array {
self::$Queries++; self::$LastParams = $Args;
if (str_contains($Sql, 'FROM `Users`')) return array_slice(array_values(self::$Users), $Args[1], $Args[0]);
if (str_contains($Sql, 'WHERE `ID` IN')) { check(str_contains($Sql, 'FOR UPDATE'), 'selected device rows locked'); return array_values(array_intersect_key(self::$Devices, array_flip($Args))); }
if (str_contains($Sql, 'WHERE `ID` = ?')) return isset(self::$Devices[$Args[0]]) ? [self::$Devices[$Args[0]]] : [];
if (str_contains($Sql, 'LIMIT 3 OFFSET')) return array_slice(array_values(self::$Devices), $Args[0], 3);
return array_slice(array_values(self::$Devices), $Args[1], $Args[0]);
}
public function execute(string $Sql, array $Args): void {
self::$Queries++;
if (str_starts_with($Sql, 'DELETE FROM `App_SignIn_Requests`')) unset(self::$Requests[$Args[0]]);
elseif (str_starts_with($Sql, 'UPDATE `App_Sessions`')) self::$Sessions[$Args[0]] = 'revoked';
elseif (str_starts_with($Sql, 'DELETE FROM `App_Notifications`')) unset(self::$Notices[$Args[0]]);
elseif (str_starts_with($Sql, 'DELETE FROM `App_Devices`')) {
if (self::$Fail) throw new RuntimeException('simulated delete failure');
check((self::$Devices[$Args[0]]['Device_ID'] ?? '') === $Args[1], 'full device id and immutable row id must match');
unset(self::$Devices[$Args[0]]);
} elseif (str_starts_with($Sql, 'DELETE FROM `Settings`')) unset(Repository::$Settings[$Args[0]]);
else throw new RuntimeException('Unexpected SQL: ' . $Sql);
}
public function transaction(callable $Callback): mixed {
$Snapshot = [self::$Devices, self::$Sessions, self::$Requests, self::$Notices, Repository::$Settings];
try { return $Callback($this); } catch (Throwable $Error) {
[self::$Devices, self::$Sessions, self::$Requests, self::$Notices, Repository::$Settings] = $Snapshot;
throw $Error;
}
}
}
loadClass('Core/App/Device-Deletion.php', 'DeviceDeletion');
loadClass('Bot/Admin.php', 'AdminFlow');
loadClass('Bot/Dispatcher.php', 'Dispatcher');
function seed(): void {
Database::$Devices = []; Repository::$Settings = []; Database::$Sessions = []; Database::$Requests = []; Database::$Notices = []; Database::$Fail = false;
for ($Id = 1; $Id <= 7; $Id++) {
$Device = 'same_prefix_' . $Id;
Database::$Devices[$Id] = ['ID' => $Id, 'Device_ID' => $Device, 'Device_Name' => '<b>phone ' . $Id . '</b>', 'Telegram_ID' => $Id, 'User_UUID' => 'account-' . $Id, 'Is_Trusted' => 1];
Database::$Sessions[$Device] = 'active'; Database::$Requests[$Device] = 'approved'; Database::$Notices[$Device] = 'private';
}
}
function calls(): array { return array_column(array_merge([], ...TelegramClient::$Rows), 'callback_data'); }
$Admin = new Context(); seed();
AdminFlow::deleteDevicesPrompt($Admin, 1, 0);
check(count(Database::$Devices) === 7, 'first tap only previews');
check(str_contains(TelegramClient::$Text, '&lt;b&gt;'), 'device names escaped');
$Token = substr(calls()[0], strlen('admin_devices_delete_confirm:'));
check(strlen(calls()[0]) <= 64, 'confirmation callback fits Telegram');
check(!(DeviceDeletion::confirm(100, 99, $Token)['valid'] ?? false), 'other admin cannot confirm');
check(!(DeviceDeletion::confirm(99, 100, $Token)['valid'] ?? false), 'different chat cannot confirm');
AdminFlow::deleteDevicesConfirm($Admin, $Token);
check(!isset(Database::$Devices[1]) && count(Database::$Devices) === 6, 'single delete applied to shared user/admin table');
check(Database::$Sessions['same_prefix_1'] === 'revoked' && !isset(Database::$Requests['same_prefix_1']) && !isset(Database::$Notices['same_prefix_1']), 'sessions, pending/approved challenges and private notifications invalidated');
check(Database::$Sessions['same_prefix_2'] === 'active', 'other devices unchanged');
check(!(DeviceDeletion::confirm(99, 99, $Token)['valid'] ?? false), 'replay cannot delete again');
seed(); AdminFlow::deleteDevicesPrompt($Admin, 0, 1);
$Token = substr(calls()[0], strlen('admin_devices_delete_confirm:'));
// Change sorting/list contents after preview; confirmation must use original IDs 4,5,6.
Database::$Devices[8] = ['ID' => 8, 'Device_ID' => 'new', 'Is_Trusted' => 1];
$Result = DeviceDeletion::confirm(99, 99, $Token);
check($Result['count'] === 3 && $Result['page'] === 1, 'bounded page group has correct count and return page');
check(array_keys(Database::$Devices) === [1,2,3,7,8], 'group deletes exact snapshot, never newly registered or other-page devices');
seed(); $Token = DeviceDeletion::prepare(99, 99, [1], 0);
DeviceDeletion::confirm(99, 99, $Token, true);
check(count(Database::$Devices) === 7 && !DeviceDeletion::confirm(99,99,$Token)['valid'], 'cancel consumes confirmation without deleting');
$Token = DeviceDeletion::prepare(99, 99, [1], 0);
$New = DeviceDeletion::prepare(99, 99, [2], 0);
check(!DeviceDeletion::confirm(99,99,$Token)['valid'], 'new prompt invalidates old confirmation');
$P = json_decode(Repository::$Settings['DeviceDelete_99'], true); $P['expires'] = time() - 1; Repository::$Settings['DeviceDelete_99'] = json_encode($P);
check(!DeviceDeletion::confirm(99,99,$New)['valid'], 'expired confirmation cannot delete');
seed(); $Token = DeviceDeletion::prepare(99,99,[1,2,3],0); Database::$Fail = true;
try { DeviceDeletion::confirm(99,99,$Token); check(false, 'must throw'); } catch (RuntimeException) {}
check(count(Database::$Devices) === 7 && Database::$Sessions['same_prefix_1'] === 'active' && isset(Database::$Requests['same_prefix_1']), 'transaction failure rolls back all related deletion');
Database::$Fail = false; check(DeviceDeletion::confirm(99,99,$Token)['count'] === 3, 'failed transaction can be retried');
seed(); $Token = DeviceDeletion::prepare(99,99,[1],0);
unset(Database::$Devices[1]); Database::$Devices[8] = ['ID'=>8, 'Device_ID'=>'same_prefix_1'];
check(DeviceDeletion::confirm(99,99,$Token)['count'] === 0 && isset(Database::$Devices[8]), 'old confirmation cannot delete re-registered device');
$Guest = new Context(false); $Queries = Database::$Queries;
foreach ([['deleteDevicesPrompt', 1], ['deleteDevicesConfirm', str_repeat('a',24)], ['accountUsers',0], ['accountUserView',1]] as [$Method,$Arg]) AdminFlow::$Method($Guest,$Arg);
check(Database::$Queries === $Queries, 'every new admin endpoint denies nonadmin before DB');
Database::$Users = [];
for ($Id=1; $Id<=12; $Id++) Database::$Users[$Id] = ['Telegram_ID'=>$Id, 'Full_Name'=>'<b>Full name ' . $Id . '</b>', 'Username'=>'user_' . $Id, 'Is_Blocked'=>0];
foreach ([-1=>0,1=>1,999=>2] as $Request=>$Page) {
AdminFlow::accountUsers($Admin,$Request);
check(Database::$LastParams === [5,$Page*5], 'user list page clamps and uses bounded query');
check(in_array('admin_users_page:' . ($Page-1),calls(),true) === ($Page>0), 'previous page boundary');
check(in_array('admin_users_page:' . ($Page+1),calls(),true) === ($Page<2), 'next page boundary');
check(str_contains(TelegramClient::$Text,'@user_') && str_contains(TelegramClient::$Text,'&lt;b&gt;Full name'), 'full names and usernames displayed safely');
check(in_array('admin_accounts_menu',calls(),true), 'list returns to account management');
}
AdminFlow::accountUserView($Admin,6,1);
check(in_array('admin_users_page:1',calls(),true), 'details return to original list page');
check(str_contains(TelegramClient::$Text,'user_6') && str_contains(TelegramClient::$Text,'Full name 6'), 'selected user detail correct');
Database::$Users=[]; AdminFlow::accountUsers($Admin,99);
check(calls() === ['admin_accounts_menu','مدیریت'], 'empty list has navigation only');
// Route actual callbacks, not only copied callback fixtures.
$Route = new ReflectionMethod(Dispatcher::class, 'routeCallbackInner');
seed(); $Admin->CallbackData = 'admin_device_delete:2:0'; $Route->invoke(null, $Admin);
$Confirm = calls()[0]; check(str_starts_with($Confirm, 'admin_devices_delete_confirm:'), 'single delete dispatcher opens confirmation');
$Admin->CallbackData = str_replace('confirm:', 'cancel:', $Confirm); $Route->invoke(null, $Admin);
check(count(Database::$Devices) === 7, 'cancel route leaves device list intact');
$Admin->CallbackData = 'admin_devices_delete_page:1'; $Route->invoke(null, $Admin);
$Admin->CallbackData = calls()[0]; $Route->invoke(null, $Admin);
check(array_keys(Database::$Devices) === [1,2,3,7], 'group confirm route deletes exactly displayed page');
$Admin->CallbackData = 'admin_users'; $Route->invoke(null, $Admin);
check(calls() === ['admin_accounts_menu','مدیریت'], 'user list callback handled');
$Admin->CallbackData = 'admin_users_page:1'; $Route->invoke(null, $Admin);
check(calls() === ['admin_accounts_menu','مدیریت'], 'user list paging callback handled');
Database::$Users[7] = ['Telegram_ID'=>7,'Full_Name'=>'test','Username'=>'sample'];
$Admin->CallbackData = 'admin_user_view:7:2'; $Route->invoke(null, $Admin);
check(in_array('admin_users_page:2', calls(), true), 'detail callback preserves requested list page');
$Gateway=file_get_contents(__DIR__.'/../Core/App/App-Gateway.php');
check(str_contains($Gateway,"(int)(\$Row['Device_Trusted'] ?? 0) !== 1"), 'missing/deleted device still fails session authorization');
$App=file_get_contents(__DIR__.'/../Bot/App-Link.php');
check(str_contains($App,"'⬅️صفحه قبل'") && str_contains($App,"'صفحه بعد➡️'"), 'user device navigation has explicit previous/next labels');
echo "OK admin device deletion and users list ($Count assertions)\n";
