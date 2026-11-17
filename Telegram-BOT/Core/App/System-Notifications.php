<?php
declare(strict_types=1);
require_once __DIR__ . '/../Storage/Repository.php';
require_once __DIR__ . '/../Telegram/Telegram.php';

/** System events only. Manual messaging keeps its explicitly chosen transports. */
final class SystemNotifications {
public static function queue(int $UserId, string $Title, string $Body, string $Event = '', string $Level = 'info'): int {
if ($UserId <= 0 || trim($Body) === '') return 0;
try {
$Db = Database::getInstance();
$User = Repository::getUser($UserId);
$Uuid = trim((string)($User['Client_ID'] ?? ''));
if ($Uuid === '_') $Uuid = '';
$Rows = $Db->fetchAll('SELECT `Device_ID` FROM `App_Devices` WHERE `Is_Trusted` = 1 AND (`Telegram_ID` = ? OR ((`Telegram_ID` IS NULL OR `Telegram_ID` = 0) AND `User_UUID` = ? AND ? != \'\'))', [$UserId, $Uuid, $Uuid]);
$Body = html_entity_decode(strip_tags(TelegramClient::md($Body)), ENT_QUOTES | ENT_HTML5, 'UTF-8');
$Title = mb_substr(trim(strip_tags($Title)), 0, 190);
$Body = mb_substr($Body, 0, 12000);
if ($Event === '') $Event = hash('sha256', $Body) . ':' . intdiv(time(), 300);
$Targets = [];
foreach ($Rows as $Row) {
$Device = trim((string)($Row['Device_ID'] ?? ''));
if ($Device !== '') $Targets[$Device] = $Device;
}
if ($Targets === []) return 0; // Never NULL/NULL or broadcast.
$Db->transaction(static function (Database $Db) use ($Targets, $Uuid, $Title, $Body, $Level, $Event, $UserId): void {
foreach ($Targets as $Device) {
$Key = hash('sha256', $UserId . ':' . $Event . ':' . $Device);
$Db->execute('INSERT INTO `App_Notifications` (`User_UUID`, `Device_ID`, `Title`, `Body`, `Level`, `Event_Key`) VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE `ID` = `ID`', [$Uuid !== '' ? $Uuid : null, $Device, $Title, $Body, $Level, $Key]);
}
});
return max(1, count($Targets));
} catch (Throwable $Error) {
error_log('[Umbrella-Bot][System-App-Notice] queue failed: ' . $Error->getMessage());
return 0;
}
}

public static function mirrorChat(int $ChatId, string $Text): void {
if ($ChatId <= 0) return;
try {
$Rows = Database::getInstance()->fetchAll('SELECT `Telegram_ID` FROM `Users` WHERE `Chat_ID` = ? OR `Telegram_ID` = ? LIMIT 2', [$ChatId, $ChatId]);
if (count($Rows) !== 1) return;
self::queue((int)$Rows[0]['Telegram_ID'], 'اعلان سیستمی آمبرلا', $Text);
} catch (Throwable $Error) { error_log('[Umbrella-Bot][System-App-Notice] recipient lookup failed: ' . $Error->getMessage()); }
}
}
