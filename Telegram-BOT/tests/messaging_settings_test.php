<?php
declare(strict_types=1);
require_once dirname(__DIR__) . '/Bot/Menu.php';
if (!function_exists('mb_strlen')) { function mb_strlen(string $S): int { return count(preg_split('//u', $S, -1, PREG_SPLIT_NO_EMPTY) ?: []); } }
if (!function_exists('mb_substr')) { function mb_substr(string $S, int $Start, ?int $Length = null): string { return implode('', array_slice(preg_split('//u', $S, -1, PREG_SPLIT_NO_EMPTY) ?: [], $Start, $Length)); } }
final class Context { public int $UserId = 1; public int $ChatId = 1; public ?int $MessageId = 1; public ?string $CallbackId = 'test'; public bool $IsCallback = true; public function isAdmin(): bool { return true; } }
final class Helper {
public static function validatePhone(string $Phone): bool { return $Phone === '09123456789'; }
public static function frame(string $Type, string $Name, string $Section, int $Id): string { return $Section; }
public static function userFooter(): string { return ''; }
public static function adminFooter(): string { return ''; }
public static function userGreeting(Context $C, string $S): string { return $S; }
public static function adminGreeting(Context $C, string $S): string { return $S; }
public static function toPersian(string $S): string { return $S; }
public static function normalizePhone(string $S): string { return $S; }
}
final class SystemNotifications { public static function queue(...$Args): int { return 0; } }
final class PanelClient { public static function findByTelegramId(int $Id): array { return ['uuid' => 'owner']; } public static function findByPhone(string $Phone): array { return ['uuid' => 'owner']; } }
final class TelegramClient {
public static array $Response = []; public static array $ApiCalls = []; public static array $Sent = []; public static bool $FailSend = false; public static array $Rows = []; public static string $Text = '';
public static function call(string $Method, array $Args): array { self::$ApiCalls[] = [$Method, $Args]; return self::$Response; }
public static function inlineKeyboard(array $Rows): array { return ['inline_keyboard' => $Rows]; }
public static function sendMessage(int $Chat, string $Text, array $Markup): array { self::$Sent[] = $Chat; if (self::$FailSend) throw new RuntimeException('simulated Telegram failure'); return ['ok' => true]; }
public static function editMessageText(int $Chat, ?int $Id, string $Text, array $Markup): array { self::$Text = $Text; self::$Rows = $Markup['inline_keyboard']; return ['ok' => true]; }
public static function editOrSendMessage(int $Chat, ?int $Id, string $Text, array $Markup): array { self::$Text = $Text; self::$Rows = $Markup['inline_keyboard']; return ['ok' => true]; }
public static function answerCallbackQuery(?string $Id, string $Text, bool $Alert = false): void {}
}
final class IppanelClient { public static array $Sent = []; public static bool $Fail = false; public static function send(int $Id, string $Phone, string $Text): bool { self::$Sent[] = $Id; return !self::$Fail; } }
final class Database {
public static array $Settings = []; public static array $Devices = []; public static array $Queued = []; public static array $Users = []; public static array $Revoked = []; public static bool $FailWrite = false;
public static function getInstance(): self { return new self(); }
public function transaction(callable $Fn): mixed { $Before = self::$Settings; try { return $Fn($this); } catch (Throwable $E) { self::$Settings = $Before; throw $E; } }
public function scalar(string $Q, array $P = [], mixed $Default = null): mixed {
if (str_contains($Q, '`Settings`')) return self::$Settings[$P[0]] ?? null;
if (str_contains($Q, '`Is_Trusted` = 1')) return count(array_filter(self::$Devices, fn($D) => ($D['Is_Trusted'] ?? 0) === 1));
return count(self::$Devices);
}
public function fetch(string $Q, array $P): ?array { return self::$Users[$P[0]] ?? null; }
public function fetchAll(string $Q, array $P = []): array {
if (str_contains($Q, 'Device_ID` LIKE')) {
$Matches = array_values(array_filter(self::$Devices, fn($D) => str_starts_with($D['Device_ID'], rtrim($P[0], '%'))));
if (count($P) === 1) return array_slice($Matches, 0, 2);
$WantTrusted = str_contains($Q, '`Is_Trusted` = 0') ? 0 : 1;
return array_values(array_filter($Matches, fn($D) => ($D['Is_Trusted'] ?? 0) === $WantTrusted && ($D['User_UUID'] === $P[1] || $D['Telegram_ID'] === $P[2])));
}
if (str_contains($Q, 'LIMIT ? OFFSET ?')) {
$Source = str_contains($Q, '`Is_Trusted` = 1') ? array_values(array_filter(self::$Devices, fn($D) => ($D['Is_Trusted'] ?? 0) === 1)) : self::$Devices;
return count($P) >= 4 ? array_slice($Source, $P[3], $P[2]) : array_slice($Source, $P[1] ?? 0, $P[0] ?? 0);
}
if (str_contains($Q, 'FROM `App_Devices` AS `D`')) return array_slice(self::$Devices, $P[1] ?? 0, $P[0] ?? count(self::$Devices));
if (str_contains($Q, 'FROM `App_Devices` WHERE `Is_Trusted` = 1')) return array_values(array_filter(self::$Devices, fn($D) => $D['Is_Trusted'] === 1));
if (str_contains($Q, 'WHERE `Phone` IN')) return array_values(array_filter(self::$Devices, fn($D) => in_array((string)($D['Phone'] ?? ''), $P, true) && $D['Is_Trusted'] === 1));
if (str_contains($Q, 'WHERE `Device_ID` = ?')) return array_values(array_filter(self::$Devices, fn($D) => ($D['Device_ID'] ?? '') === $P[0] && $D['Is_Trusted'] === 1));
if (str_contains($Q, 'WHERE `User_UUID` = ?')) return array_values(array_filter(self::$Devices, fn($D) => ($D['User_UUID'] ?? '') === $P[0] && $D['Is_Trusted'] === 1));
return array_values(array_filter(self::$Devices, fn($D) => ($D['Telegram_ID'] ?? null) === $P[0] && $D['Is_Trusted'] === 1));
}
public function execute(string $Q, array $P): void {
if (str_contains($Q, 'INSERT INTO `Settings`')) { if (self::$FailWrite && $P[0] === 'Telegram_Channel_ID') throw new RuntimeException('write failure'); self::$Settings[$P[0]] = $P[1]; }
if (str_contains($Q, 'INSERT INTO `App_Notifications`')) self::$Queued[] = [$Q, $P];
if (str_contains($Q, 'UPDATE `App_Devices`')) foreach (self::$Devices as &$D) { if ($D['Device_ID'] === $P[0]) $D['Is_Trusted'] = 0; }
if (str_contains($Q, 'DELETE FROM `App_Devices`')) self::$Devices = array_values(array_filter(self::$Devices, fn($D) => !(($D['Device_ID'] ?? '') === $P[0] && ($D['Is_Trusted'] ?? 0) === 0)));
if (str_contains($Q, 'UPDATE `App_Sessions`')) self::$Revoked[] = $P[0];
}
}
foreach (['Core/Storage/Repository.php' => 'Repository', 'Core/Support/Bot-Config.php' => 'BotConfig', 'Bot/Admin.php' => 'AdminFlow', 'Bot/App-Link.php' => 'AppFlow'] as $File => $Class) {
$S = (string)file_get_contents(dirname(__DIR__) . '/' . $File);
eval(preg_replace('/\?>\s*$/', '', substr($S, strpos($S, 'final class ' . $Class . ' {'))));
}
$N = 0;
function check(bool $Ok, string $Message): void { global $N; if (!$Ok) throw new RuntimeException($Message); $N++; }
check(BotConfig::getChannelUrl() === 'https://t.me/UmbrellaVPN_Channel', 'default channel url is UmbrellaVPN_Channel');
foreach (['@UmbrellaVPN_Channel', 'UmbrellaVPN_Channel', 'https://t.me/UmbrellaVPN_Channel', 't.me/UmbrellaVPN_Channel/'] as $Input) check(BotConfig::channelUsername($Input) === 'UmbrellaVPN_Channel', 'UmbrellaVPN_Channel normalization');
foreach (['@sample_channel', 'sample_channel', 'https://t.me/sample_channel', 't.me/sample_channel/'] as $Input) check(BotConfig::channelUsername($Input) === 'sample_channel', 'username normalization');
foreach (['https://evil.test/sample_channel', 'https://t.me/+private', 'https://t.me/channel/12', '-1001234'] as $Input) { try { BotConfig::channelUsername($Input); check(false, 'invalid channel accepted'); } catch (InvalidArgumentException) { check(true, 'invalid channel refused'); } }
TelegramClient::$Response = ['ok' => true, 'result' => ['id' => -1001234567890, 'type' => 'channel', 'username' => 'sample_channel']];
check(BotConfig::configureChannel('@sample_channel') === '-1001234567890', 'ID taken from Telegram');
check(Database::$Settings['Channel_Url'] === 'https://t.me/sample_channel' && Database::$Settings['Telegram_Channel_ID'] === '-1001234567890', 'channel link and numeric ID saved together');
check(TelegramClient::$ApiCalls[0] === ['getChat', ['chat_id' => '@sample_channel']], 'getChat uses username');
$Calls = count(TelegramClient::$ApiCalls); BotConfig::configureChannel('sample_channel', false);
check(count(TelegramClient::$ApiCalls) === $Calls, 'unchanged mapped channel does not repeatedly call Telegram');
$Before = Database::$Settings;
foreach ([['ok' => false], ['ok' => true, 'result' => ['id' => 123, 'type' => 'private', 'username' => 'person']], ['ok' => true, 'result' => ['id' => -100123, 'type' => 'channel', 'username' => 'wrong']]] as $Response) {
TelegramClient::$Response = $Response;
try { BotConfig::configureChannel('new_channel'); check(false, 'invalid response accepted'); } catch (RuntimeException) { check(Database::$Settings === $Before, 'bad response preserves old config'); }
}
TelegramClient::$Response = ['ok' => true, 'result' => ['id' => -100999, 'type' => 'channel', 'username' => 'new_channel']]; Database::$FailWrite = true;
try { BotConfig::configureChannel('new_channel'); check(false, 'failed write accepted'); } catch (RuntimeException) { check(Database::$Settings === $Before, 'failed transaction preserves both values'); }
Database::$FailWrite = false;
check(Repository::nightlyReportEnabled(1), 'nightly defaults on for existing users');
Repository::setNightlyReportEnabled(1, false);
check(!Repository::nightlyReportEnabled(1) && Repository::nightlyReportEnabled(2), 'nightly preference isolated per user');
Repository::setNightlyReportEnabled(1, true); check(Repository::nightlyReportEnabled(1), 'nightly re-enabled');
$User = ['Telegram_ID' => 1, 'Chat_ID' => 123, 'Full_Name' => 'نام کامل', 'Phone' => '09123456789', 'Client_ID' => 'owner'];
Database::$Users[1] = $User;
Database::$Devices = [['Device_ID' => 'device-one', 'User_UUID' => 'owner', 'Telegram_ID' => 1, 'Is_Trusted' => 1, 'Device_Name' => 'phone', 'Platform' => 'Android']];
$Send = new ReflectionMethod(AdminFlow::class, 'deliverMessage');
foreach (['telegram' => ['telegram'], 'sms' => ['sms'], 'app' => ['app'], 'all' => ['telegram', 'sms', 'app'], 'both' => ['telegram', 'sms']] as $Mode => $Channels) {
TelegramClient::$Sent = []; IppanelClient::$Sent = []; Database::$Queued = [];
$Result = $Send->invoke(null, $User, 'message', $Mode, 99);
check(array_keys($Result) === $Channels && !in_array(false, $Result, true), $Mode . ': exact transport set succeeds');
check(count(TelegramClient::$Sent) === (int)in_array('telegram', $Channels, true), $Mode . ': Telegram only when selected');
check(count(IppanelClient::$Sent) === (int)in_array('sms', $Channels, true), $Mode . ': SMS only when selected');
check(count(Database::$Queued) === (int)in_array('app', $Channels, true), $Mode . ': app only when selected');
}
TelegramClient::$FailSend = true; IppanelClient::$Fail = true;
$Result = $Send->invoke(null, $User, 'message', 'all', 99);
check($Result === ['telegram' => false, 'sms' => false, 'app' => true], 'failed providers do not prevent app queuing');
TelegramClient::$FailSend = false; IppanelClient::$Fail = false;
Database::$Devices = []; Database::$Queued = [];
check(AdminFlow::queueAppPush(1, 'private', 99) === 1, 'offline known account gets deferred notification');
check(Database::$Queued[0][1][0] === 'owner', 'deferred notification bound to correct account');
Database::$Users[99] = ['Telegram_ID' => 99, 'Client_ID' => 'admin-owner'];
Database::$Devices = [
['Device_ID' => 'device-one', 'User_UUID' => 'owner', 'Telegram_ID' => 1, 'Is_Trusted' => 1],
['Device_ID' => 'admin-device', 'User_UUID' => 'admin-owner', 'Telegram_ID' => 99, 'Is_Trusted' => 1],
['Device_ID' => 'admin-unlinked-device', 'User_UUID' => 'admin-owner', 'Telegram_ID' => null, 'Is_Trusted' => 1],
];
Database::$Queued = [];
check(AdminFlow::queueAppPush(99, 'admin private', 99) === 0 && Database::$Queued === [], 'targeted app push skips the administrator account');
check(AdminFlow::queueAppPush(0, 'broadcast', 99) === 1, 'app broadcast still reaches normal users');
check(Database::$Queued[0][1][0] === 'device-one', 'app broadcast excludes admin devices by Telegram ID and UUID');
Database::$Users = []; Database::$Queued = []; Database::$Devices = [];
check(AdminFlow::queueAppPush(1, 'private', 99) === 0 && Database::$Queued === [], 'no private-message broadcast fallback');
Database::$Users[2] = ['Telegram_ID' => 2, 'Client_ID' => '_'];
check(AdminFlow::queueAppPush(2, 'cleared user', 99) === 0 && Database::$Queued === [], 'cleared user with underscore Client_ID does not queue invalid row');
Database::$Users[3] = ['Telegram_ID' => 3, 'Client_ID' => 'uuid-only-owner'];
Database::$Devices = [['Device_ID' => 'device-uuid-only', 'User_UUID' => 'uuid-only-owner', 'Telegram_ID' => null, 'Is_Trusted' => 1]];
check(AdminFlow::queueAppPush(3, 'hello uuid device', 99) === 1, 'targeted app push resolves device matched by User_UUID when Telegram_ID is null');
check(Database::$Queued[0][1][0] === 'device-uuid-only', 'notification binds to matched Device_ID');
$FailureReason = new ReflectionMethod(AdminFlow::class, 'appDeliveryFailureReason');
check(str_contains((string)$FailureReason->invoke(null, 99, 99), 'مدیریت'), 'admin target gets clear management exclusion reason');
check(str_contains((string)$FailureReason->invoke(null, 2, 99), 'اشتراک فعالی هم ندارد'), 'user without devices or active subscription gets clear reason');
Database::$Users = []; Database::$Queued = []; Database::$Devices = [];
$Context = new Context();
Database::$Devices = [
['Device_ID' => 'device-one', 'User_UUID' => 'owner', 'Telegram_ID' => 1, 'Is_Trusted' => 1, 'Device_Name' => 'phone', 'Platform' => 'Android'],
['Device_ID' => 'device-revoked', 'User_UUID' => 'owner', 'Telegram_ID' => 1, 'Is_Trusted' => 0, 'Device_Name' => 'Nokia 5.4', 'Platform' => 'Android'],
];
AppFlow::devices($Context);
check(str_contains(TelegramClient::$Rows[0][0]['text'], '⛔️ لغو اعتماد'), 'trusted device has revoke action');
check(!str_contains(TelegramClient::$Text, 'Nokia 5.4') && !str_contains(TelegramClient::$Text, 'تایید نشده'), 'untrusted devices are excluded from my-devices list');
check(count(TelegramClient::$Rows) === 3 && !str_contains(json_encode(TelegramClient::$Rows, JSON_UNESCAPED_UNICODE), 'اعتماد لغو شده'), 'revoked button is not shown in my-devices list');
AppFlow::removeRevokedDevice($Context, 'device-one');
check(count(Database::$Devices) === 2, 'removeRevokedDevice refuses to delete a trusted device');
AppFlow::removeRevokedDevice($Context, 'device-revoked');
check(count(Database::$Devices) === 1 && Database::$Devices[0]['Device_ID'] === 'device-one', 'tapping legacy revoked status button deletes untrusted device');
Database::$Revoked = [];
AppFlow::confirmRevokeDevice($Context, 'device-one');
check(Database::$Devices[0]['Is_Trusted'] === 0 && Database::$Revoked === ['device-one'], 'revocation clears trust and invalidates sessions');
check(Database::$Queued === [], 'administrator-session revocation does not enqueue an app notification');
check(!str_contains(TelegramClient::$Text, 'phone') && !str_contains(json_encode(TelegramClient::$Rows, JSON_UNESCAPED_UNICODE), 'اعتماد لغو شده'), 'revoked device disappears from my-devices list immediately');
check(count(TelegramClient::$Rows) === 2 && TelegramClient::$Rows[0][0]['callback_data'] === 'user_device_menu', 'empty my-devices screen retains only navigation buttons after revoking last trusted device');
$Queued = count(Database::$Queued); AppFlow::confirmRevokeDevice($Context, 'device-one');
check(count(Database::$Queued) === $Queued, 'repeat revoke does not queue duplicate notice');
$AdminContext = new Context(); $AdminContext->UserId = 99; $AdminContext->ChatId = 99;
Database::$Users[99] = ['Telegram_ID' => 99, 'Client_ID' => 'admin-owner'];
Database::$Devices = [['ID' => 3, 'Device_ID' => 'admin-device', 'User_UUID' => 'admin-owner', 'Telegram_ID' => 99, 'Phone' => '09123456789', 'Is_Trusted' => 1, 'Device_Name' => 'admin laptop', 'Platform' => 'Windows']];
Database::$Queued = [];
AdminFlow::toggleAppDevice($AdminContext, 'admin-device');
check(Database::$Devices[0]['Is_Trusted'] === 0 && in_array('admin-device', Database::$Revoked, true), 'admin can revoke their device and invalidate its session');
check(Database::$Queued === [], 'admin device permission revocation does not enqueue a direct app notification');
$Scheduler = (string)file_get_contents(dirname(__DIR__) . '/Bot/Scheduler.php');
check(str_contains($Scheduler, 'if (!Repository::nightlyReportEnabled($User_ID)) continue;'), 'nightly scheduler observes persisted preference');

// Manual targeted app sends allow admin test accounts (tagged as Level=manual)
// and resolve phone-only or app-only users even without Users.Client_ID or Telegram_ID.
Database::$Users = [
99 => ['Telegram_ID' => 99, 'Chat_ID' => 99, 'Full_Name' => 'مدیر', 'Phone' => '09123456789', 'Client_ID' => 'admin-owner'],
4 => ['Telegram_ID' => 4, 'Chat_ID' => 4, 'Full_Name' => 'کاربر موبایلی', 'Phone' => '09127776655', 'Client_ID' => '_'],
];
Database::$Devices = [
['ID' => 10, 'Device_ID' => 'admin-device-manual', 'User_UUID' => 'admin-owner', 'Telegram_ID' => 99, 'Phone' => '09123456789', 'Is_Trusted' => 1],
['ID' => 11, 'Device_ID' => 'phone-matched-device', 'User_UUID' => 'app-phone-uuid', 'Telegram_ID' => null, 'Phone' => '09127776655', 'Is_Trusted' => 1],
['ID' => 12, 'Device_ID' => 'app-only-no-tg', 'User_UUID' => 'only-app-uuid', 'Telegram_ID' => 0, 'Phone' => '09129998877', 'Is_Trusted' => 1],
];
Database::$Queued = [];
$AdminManual = $Send->invoke(null, Database::$Users[99], 'تست دستی مدیر', 'app', 99);
check($AdminManual === ['app' => true], 'manual app send succeeds for admin test account');
check(count(Database::$Queued) === 1 && Database::$Queued[0][1][0] === 'admin-device-manual' && Database::$Queued[0][1][3] === 'manual', 'admin manual app message queued with Level=manual');

Database::$Queued = [];
$PhoneFallback = $Send->invoke(null, Database::$Users[4], 'تست تطبیق شماره', 'app', 99);
check($PhoneFallback === ['app' => true], 'manual app send matches device via phone when Client_ID is cleared and Telegram_ID is null');
check(count(Database::$Queued) === 1 && Database::$Queued[0][1][0] === 'phone-matched-device', 'phone-fallback device receives queued app notification');

Database::$Queued = [];
$AppOnlyUser = ['Telegram_ID' => 0, 'Chat_ID' => 0, 'Full_Name' => 'کاربر فقط اپ', 'Phone' => '09129998877', 'Client_ID' => 'only-app-uuid', 'Device_ID' => 'app-only-no-tg'];
$AppOnlyResult = $Send->invoke(null, $AppOnlyUser, 'پیام بدون تلگرام', 'app', 99);
check($AppOnlyResult === ['app' => true], 'app-only user without Telegram_ID receives targeted app push');
check(Database::$Queued[0][1][0] === 'app-only-no-tg', 'app-only notification targets exact Device_ID');
Database::$Queued = [];

echo "OK messaging/settings tests ({$N} assertions)\n";
