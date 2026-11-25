<?php
declare(strict_types=1);
require_once __DIR__ . '/../Storage/Repository.php';

/** One-use, admin/chat-bound deletion of the exact device rows previewed. */
final class DeviceDeletion {
public static function prepare(int $Admin, int $Chat, array $Ids, int $Page): string {
$Ids = array_values(array_unique(array_filter(array_map('intval', $Ids), static fn(int $Id): bool => $Id > 0)));
if ($Ids === [] || count($Ids) > 3) throw new InvalidArgumentException('Invalid device selection');
$Token = bin2hex(random_bytes(12));
Repository::setSetting('DeviceDelete_' . $Admin, json_encode([
 'token' => $Token, 'chat' => $Chat, 'expires' => time() + 600, 'ids' => $Ids, 'page' => max(0, $Page),
], JSON_THROW_ON_ERROR));
return $Token;
}

/** Snapshot a monotonic row-ID watermark. Devices registered afterwards survive. */
public static function prepareAll(int $Admin, int $Chat, int $LastId): string {
if ($LastId <= 0) throw new InvalidArgumentException('Empty device selection');
$Token = bin2hex(random_bytes(12));
Repository::setSetting('DeviceDelete_' . $Admin, json_encode([
 'token' => $Token, 'chat' => $Chat, 'expires' => time() + 600,
 'through' => $LastId, 'page' => 0,
], JSON_THROW_ON_ERROR));
return $Token;
}

public static function confirm(int $Admin, int $Chat, string $Token, bool $Cancel = false): array {
if (!preg_match('/^[a-f0-9]{24}$/D', $Token)) return ['valid' => false];
return Database::getInstance()->transaction(static function (Database $Db) use ($Admin, $Chat, $Token, $Cancel): array {
$Key = 'DeviceDelete_' . $Admin;
$Record = $Db->fetch('SELECT `Value` FROM `Settings` WHERE `Key` = ? FOR UPDATE', [$Key]);
$Pending = json_decode((string)($Record['Value'] ?? ''), true);
if (!is_array($Pending) || !hash_equals((string)($Pending['token'] ?? ''), $Token)
|| (int)($Pending['chat'] ?? 0) !== $Chat || (int)($Pending['expires'] ?? 0) < time()) return ['valid' => false];
if ($Cancel) {
$Db->execute('DELETE FROM `Settings` WHERE `Key` = ?', [$Key]);
return ['valid' => true, 'count' => 0, 'page' => (int)$Pending['page']];
}
$Through = (int)($Pending['through'] ?? 0);
if ($Through > 0) {
$Rows = $Db->fetchAll('SELECT `ID`, `Device_ID`, `Telegram_ID`, `User_UUID` FROM `App_Devices` WHERE `ID` <= ? FOR UPDATE', [$Through]);
} else {
$Ids = array_values(array_unique(array_filter(array_map('intval', $Pending['ids'] ?? []), static fn(int $Id): bool => $Id > 0)));
if ($Ids === [] || count($Ids) > 3) return ['valid' => false];
$Marks = implode(',', array_fill(0, count($Ids), '?'));
$Rows = $Db->fetchAll('SELECT `ID`, `Device_ID`, `Telegram_ID`, `User_UUID` FROM `App_Devices` WHERE `ID` IN (' . $Marks . ') FOR UPDATE', $Ids);
}
foreach ($Rows as $Row) {
$Device = (string)$Row['Device_ID'];
// A previously confirmed/pending challenge must not recreate this install.
$Db->execute('DELETE FROM `App_SignIn_Requests` WHERE `Device_ID` = ?', [$Device]);
$Db->execute('UPDATE `App_Sessions` SET `Revoked_At` = CURRENT_TIMESTAMP WHERE `Device_ID` = ? AND `Revoked_At` IS NULL', [$Device]);
$Db->execute('DELETE FROM `App_Notifications` WHERE `Device_ID` = ?', [$Device]);
$Db->execute('DELETE FROM `App_Devices` WHERE `ID` = ? AND `Device_ID` = ?', [(int)$Row['ID'], $Device]);
}
$Db->execute('DELETE FROM `Settings` WHERE `Key` = ?', [$Key]);
return ['valid' => true, 'count' => count($Rows), 'page' => (int)$Pending['page']];
});
}
}
