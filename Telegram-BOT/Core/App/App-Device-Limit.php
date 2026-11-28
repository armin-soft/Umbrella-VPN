<?php
declare(strict_types=1);

require_once __DIR__ . '/../Database/Database.php';
require_once __DIR__ . '/../Storage/Repository.php';
require_once __DIR__ . '/../Support/Helper.php';

/**
 * How many *trusted* devices may sign in for one account (default 1).
 *
 * The cap is per Telegram account and is raised per user by an admin from the
 * bot's admin panel («📱مجوز دستگاه کاربران»). Enforcement happens in the
 * app-gateway sign-in path: a device that is not already trusted and would
 * exceed the cap never gets beyond auth/start.
 */
final class AppDeviceLimit {
private function __construct() {
}

/** The per-user cap. Returns 1 when nothing is configured. */
public static function maxDevices(int $Telegram_Id): int {
if ($Telegram_Id <= 0) return 1;

$Row = Database::getInstance()->fetch(
'SELECT `Max_Devices` FROM `App_Device_Limits` WHERE `Telegram_ID` = ? LIMIT 1',
[$Telegram_Id]
);
$Max = (int)($Row['Max_Devices'] ?? 1);

if ($Max < 1) $Max = 1;
if ($Max > 99) $Max = 99;

return $Max;
}

/** Admin action: persist the cap (clamped to 1..99). */
public static function setMaxDevices(int $Telegram_Id, int $Max): int {
$Max = max(1, min(99, $Max));

Database::getInstance()->execute(
'INSERT INTO `App_Device_Limits` (`Telegram_ID`, `Max_Devices`) VALUES (?, ?)
ON DUPLICATE KEY UPDATE `Max_Devices` = VALUES(`Max_Devices`), `Updated_At` = CURRENT_TIMESTAMP',
[$Telegram_Id, $Max]
);

return $Max;
}

/**
 * Distinct trusted devices for this account. Matching happens on the phone
 * (every install records it) and on the Telegram id when the panel account is
 * linked, so unlinked accounts are covered too.
 */
public static function trustedDevices(string $Phone, int $Telegram_Id = 0): array {
$Phone = \Helper::normalizePhone($Phone);
$Db = Database::getInstance();

if (class_exists('AppSchema') && method_exists('AppSchema', 'deduplicateTrustedDevices')) {
try {
AppSchema::deduplicateTrustedDevices($Db, '', '', $Telegram_Id, $Phone);
} catch (Throwable) {}
}

if ($Telegram_Id > 0 && $Phone !== '') {
$Rows = $Db->fetchAll(
'SELECT `Device_ID`, `Device_Name`, `Platform`, `App_Version`, `Last_Seen_At`
FROM `App_Devices`
WHERE `Is_Trusted` = 1 AND ((`Phone` = ? AND `Phone` IS NOT NULL AND `Phone` <> \'\') OR `Telegram_ID` = ?)
ORDER BY `Last_Seen_At` DESC',
[$Phone, $Telegram_Id]
);
} elseif ($Telegram_Id > 0) {
$Rows = $Db->fetchAll(
'SELECT `Device_ID`, `Device_Name`, `Platform`, `App_Version`, `Last_Seen_At`
FROM `App_Devices`
WHERE `Is_Trusted` = 1 AND `Telegram_ID` = ?
ORDER BY `Last_Seen_At` DESC',
[$Telegram_Id]
);
} else {
$Rows = $Db->fetchAll(
'SELECT `Device_ID`, `Device_Name`, `Platform`, `App_Version`, `Last_Seen_At`
FROM `App_Devices`
WHERE `Is_Trusted` = 1 AND `Phone` = ? AND `Phone` IS NOT NULL AND `Phone` <> \'\'
ORDER BY `Last_Seen_At` DESC',
[$Phone]
);
}

if (count($Rows) > 1 && class_exists('AppSchema') && method_exists('AppSchema', 'isSamePhysicalDeviceRow')) {
$Unique = [];
foreach ($Rows as $Row) {
$Dup = false;
foreach ($Unique as $Existing) {
if (AppSchema::isSamePhysicalDeviceRow($Existing, $Row, true)) {
$Dup = true;
break;
}
}
if (!$Dup) {
$Unique[] = $Row;
}
}
return $Unique;
}

return $Rows;
}

/**
 * The verdict for one device trying to sign in.
 *
 * @return array{allowed: bool, limit: int, used: int, device_known: bool, telegram_id: int}
 */
public static function check(string $Phone, string $Device_Id, string $Device_Name = '', string $Platform = ''): array {
$Device_Id = trim($Device_Id);
$User = Repository::findUserByPhone($Phone);
$Telegram_Id = (int)($User['Telegram_ID'] ?? 0);
$Limit = self::maxDevices($Telegram_Id);
$Devices = self::trustedDevices($Phone, $Telegram_Id);

$Known = false;
$Same_Device_Reinstall = false;
$Incoming = [
'Device_Name' => trim($Device_Name),
'Platform' => trim($Platform),
];

foreach ($Devices as $Row) {
if ((string)$Row['Device_ID'] === $Device_Id) {
$Known = true;
break;
}
if (($Incoming['Device_Name'] !== '' || $Incoming['Platform'] !== '')
&& class_exists('AppSchema')
&& method_exists('AppSchema', 'isSamePhysicalDeviceRow')
&& AppSchema::isSamePhysicalDeviceRow($Row, $Incoming, false)) {
$Same_Device_Reinstall = true;
}
}

return [
'allowed' => $Known || $Same_Device_Reinstall || count($Devices) < $Limit,
'limit' => $Limit,
'used' => count($Devices),
'device_known' => $Known || $Same_Device_Reinstall,
'telegram_id' => $Telegram_Id,
];
}
}
