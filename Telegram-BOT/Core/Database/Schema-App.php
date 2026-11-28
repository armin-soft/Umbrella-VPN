<?php
declare(strict_types=1);

require_once __DIR__ . '/Database.php';

/**
 * Tables the desktop app needs, kept apart from the bot's own schema so the
 * existing installation is only ever added to — never altered.
 *
 *  App_Devices         one row per trusted install (the device the bot shows)
 *  App_SignIn_Requests one row per sign-in attempt waiting for confirmation
 *  App_Sessions        the token a confirmed install keeps using
 *  App_Notifications   messages pushed from the bot to a device
 *  App_Filter_Settings the content-filter choices, editable from bot and app
 *  App_Device_Limits  per-account cap on how many trusted devices may sign in
 *  App_User_Activity   per-device sites, apps, and screens observed during use
 *  App_Security_Alerts security threats and blocked VPN apps observed on devices
 *  App_Promo_Media     binary image blobs uploaded for in-app promotional banners
 */
final class AppSchema {
private function __construct() {
}

public static function ensureInstalled(): void {
$Database = Database::getInstance();

foreach (self::statements() as $Name => $Sql) {
try {
$Database->connection()->exec($Sql);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][AppSchema] ' . $Name . ': ' . $Error->getMessage());
}
}
try {
$Exists = $Database->scalar("SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = 'App_Notifications' AND column_name = 'Event_Key'");
if (!(int)$Exists) $Database->connection()->exec('ALTER TABLE `App_Notifications` ADD COLUMN `Event_Key` CHAR(64) NULL UNIQUE');
} catch (Throwable $Error) { error_log('[Umbrella-Bot][AppSchema] notification event key: ' . $Error->getMessage()); }

try {
$HasFullName = (int)$Database->scalar("SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = 'App_Devices' AND column_name = 'Full_Name'");
if ($HasFullName === 0) {
$Database->connection()->exec('ALTER TABLE `App_Devices` ADD COLUMN `Full_Name` VARCHAR(190) NULL AFTER `Device_Name`');
}
$Backfilled = '';
try {
$Backfilled = (string)$Database->scalar("SELECT `Value` FROM `Settings` WHERE `Key` = 'App_Devices_Backfill_V1' LIMIT 1", [], '');
} catch (Throwable) {
$Backfilled = '';
}
if ($HasFullName === 0 || $Backfilled !== '1') {
self::backfillDeviceIdentityAndSeen($Database);
try {
$Database->execute(
'INSERT INTO `Settings` (`Key`, `Value`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `Value` = VALUES(`Value`)',
['App_Devices_Backfill_V1', '1']
);
} catch (Throwable) {}
}
} catch (Throwable $Error) { error_log('[Umbrella-Bot][AppSchema] devices full name: ' . $Error->getMessage()); }

try {
$LastDedup = 0;
try {
$LastDedup = (int)$Database->scalar("SELECT `Value` FROM `Settings` WHERE `Key` = 'App_Devices_Dedup_Last_At' LIMIT 1", [], 0);
} catch (Throwable) {
$LastDedup = 0;
}
$NowTs = time();
if ($NowTs - $LastDedup >= 60) {
self::deduplicateTrustedDevices($Database);
try {
$Database->execute(
'INSERT INTO `Settings` (`Key`, `Value`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `Value` = VALUES(`Value`)',
['App_Devices_Dedup_Last_At', (string)$NowTs]
);
} catch (Throwable) {}
}
} catch (Throwable $Error) { error_log('[Umbrella-Bot][AppSchema] devices dedup: ' . $Error->getMessage()); }
}

/**
 * Merges and removes duplicate trusted device rows belonging to the same user
 * on the same physical device (for example after updating from v1.0.1 to a newer
 * release where a fresh Device_ID or different platform/name casing was registered).
 */
public static function deduplicateTrustedDevices(
?Database $Database = null,
string $KeepDeviceId = '',
string $ScopeUuid = '',
int $ScopeTelegramId = 0,
string $ScopePhone = ''
): int {
$Db = $Database ?? Database::getInstance();
if (!method_exists($Db, 'fetchAll') || !method_exists($Db, 'execute')) {
return 0;
}

$KeepDeviceId = trim($KeepDeviceId);
$ScopeUuid = trim($ScopeUuid);
$ScopePhoneNorm = self::normalizePhoneForDedup($ScopePhone);

try {
$Rows = $Db->fetchAll(
'SELECT `ID`, `Device_ID`, `User_UUID`, `Client_ID`, `Telegram_ID`, `Device_Name`, `Full_Name`, '
. '`Platform`, `App_Version`, `Phone`, `Push_Enabled`, `Last_IP`, '
. 'UNIX_TIMESTAMP(`First_Seen_At`) AS `First_Ts`, UNIX_TIMESTAMP(`Last_Seen_At`) AS `Last_Ts` '
. 'FROM `App_Devices` WHERE `Is_Trusted` = 1 ORDER BY `ID` ASC',
[]
);
if (count($Rows) < 2) {
return 0;
}

$UserUuidToTg = [];
$UserTgToUuid = [];
$UserPhoneToKeys = [];
try {
$UserRows = $Db->fetchAll('SELECT `Telegram_ID`, `Client_ID`, `Phone` FROM `Users`', []);
foreach ($UserRows as $URow) {
$UTg = (int)($URow['Telegram_ID'] ?? 0);
$UUuid = trim((string)($URow['Client_ID'] ?? ''));
if ($UUuid === '_') $UUuid = '';
$UPhone = self::normalizePhoneForDedup((string)($URow['Phone'] ?? ''));
if ($UTg > 0 && $UUuid !== '') {
$UserUuidToTg[$UUuid] = $UTg;
$UserTgToUuid[$UTg] = $UUuid;
}
if ($UPhone !== '') {
if (!isset($UserPhoneToKeys[$UPhone])) $UserPhoneToKeys[$UPhone] = [];
if ($UTg > 0) $UserPhoneToKeys[$UPhone][] = 'tg:' . $UTg;
if ($UUuid !== '') $UserPhoneToKeys[$UPhone][] = 'uuid:' . $UUuid;
}
}
} catch (Throwable) {}

$N = count($Rows);
$Parent = range(0, $N - 1);
$Find = static function (int $X) use (&$Parent): int {
while ($Parent[$X] !== $X) {
$Parent[$X] = $Parent[$Parent[$X]];
$X = $Parent[$X];
}
return $X;
};
$Union = static function (int $A, int $B) use (&$Parent, $Find): void {
$Ra = $Find($A);
$Rb = $Find($B);
if ($Ra !== $Rb) {
$Parent[$Rb] = $Ra;
}
};

$KeyOwner = [];
foreach ($Rows as $Idx => $Row) {
$Keys = [];
$Uuid = trim((string)($Row['User_UUID'] ?? ''));
if ($Uuid === '_') $Uuid = '';
$Cid = trim((string)($Row['Client_ID'] ?? ''));
if ($Cid === '_') $Cid = '';
$Tg = (int)($Row['Telegram_ID'] ?? 0);
$Phone = self::normalizePhoneForDedup((string)($Row['Phone'] ?? ''));

if ($Uuid !== '') {
$Keys[] = 'uuid:' . $Uuid;
if (isset($UserUuidToTg[$Uuid])) {
$Keys[] = 'tg:' . $UserUuidToTg[$Uuid];
}
}
if ($Cid !== '') {
$Keys[] = 'uuid:' . $Cid;
if (isset($UserUuidToTg[$Cid])) {
$Keys[] = 'tg:' . $UserUuidToTg[$Cid];
}
}
if ($Tg > 0) {
$Keys[] = 'tg:' . $Tg;
if (isset($UserTgToUuid[$Tg])) {
$Keys[] = 'uuid:' . $UserTgToUuid[$Tg];
}
}
if ($Phone !== '') {
$Keys[] = 'phone:' . $Phone;
foreach ($UserPhoneToKeys[$Phone] ?? [] as $ExtraKey) {
$Keys[] = $ExtraKey;
}
}

foreach (array_unique($Keys) as $Key) {
if (isset($KeyOwner[$Key])) {
$Union($Idx, $KeyOwner[$Key]);
} else {
$KeyOwner[$Key] = $Idx;
}
}
}

$OwnerGroups = [];
foreach ($Rows as $Idx => $Row) {
$Root = $Find($Idx);
$OwnerGroups[$Root][] = $Row;
}

$ScopeActive = ($ScopeUuid !== '' && $ScopeUuid !== '_') || $ScopeTelegramId > 0 || $ScopePhoneNorm !== '';
$Removed = 0;

foreach ($OwnerGroups as $GroupRows) {
if (count($GroupRows) < 2) {
continue;
}
if ($ScopeActive && $KeepDeviceId === '') {
$MatchesScope = false;
foreach ($GroupRows as $GRow) {
$GUuid = trim((string)($GRow['User_UUID'] ?? ''));
$GCid = trim((string)($GRow['Client_ID'] ?? ''));
$GTg = (int)($GRow['Telegram_ID'] ?? 0);
$GPhone = self::normalizePhoneForDedup((string)($GRow['Phone'] ?? ''));
if (($ScopeUuid !== '' && $ScopeUuid !== '_' && ($GUuid === $ScopeUuid || $GCid === $ScopeUuid))
|| ($ScopeTelegramId > 0 && $GTg === $ScopeTelegramId)
|| ($ScopePhoneNorm !== '' && $GPhone === $ScopePhoneNorm)) {
$MatchesScope = true;
break;
}
}
if (!$MatchesScope) {
continue;
}
}

$M = count($GroupRows);
$Dsu = range(0, $M - 1);
$FindDev = static function (int $X) use (&$Dsu): int {
while ($Dsu[$X] !== $X) {
$Dsu[$X] = $Dsu[$Dsu[$X]];
$X = $Dsu[$X];
}
return $X;
};
$UnionDev = static function (int $A, int $B) use (&$Dsu, $FindDev): void {
$Ra = $FindDev($A);
$Rb = $FindDev($B);
if ($Ra !== $Rb) {
$Dsu[$Rb] = $Ra;
}
};

for ($I = 0; $I < $M; $I++) {
for ($J = $I + 1; $J < $M; $J++) {
if (self::isSamePhysicalDeviceRow($GroupRows[$I], $GroupRows[$J])) {
$UnionDev($I, $J);
}
}
}

$DeviceClusters = [];
foreach ($GroupRows as $Idx => $GRow) {
$DeviceClusters[$FindDev($Idx)][] = $GRow;
}

foreach ($DeviceClusters as $Cluster) {
if (count($Cluster) < 2) {
continue;
}

usort($Cluster, static function (array $A, array $B) use ($KeepDeviceId): int {
$AKeep = $KeepDeviceId !== '' && trim((string)($A['Device_ID'] ?? '')) === $KeepDeviceId ? 1 : 0;
$BKeep = $KeepDeviceId !== '' && trim((string)($B['Device_ID'] ?? '')) === $KeepDeviceId ? 1 : 0;
if ($AKeep !== $BKeep) {
return $BKeep <=> $AKeep;
}

$ASeen = max((int)($A['Last_Ts'] ?? 0), (int)($A['First_Ts'] ?? 0));
$BSeen = max((int)($B['Last_Ts'] ?? 0), (int)($B['First_Ts'] ?? 0));
if ($ASeen !== $BSeen) {
return $BSeen <=> $ASeen;
}

$AVer = self::normalizeVersionForDedup((string)($A['App_Version'] ?? ''));
$BVer = self::normalizeVersionForDedup((string)($B['App_Version'] ?? ''));
if ($AVer !== '' && $BVer !== '') {
$VerCmp = version_compare($BVer, $AVer);
if ($VerCmp !== 0) {
return $VerCmp;
}
} elseif ($AVer !== $BVer) {
return ($BVer !== '' ? 1 : 0) <=> ($AVer !== '' ? 1 : 0);
}

return (int)($B['ID'] ?? 0) <=> (int)($A['ID'] ?? 0);
});

$Winner = $Cluster[0];
$Losers = array_slice($Cluster, 1);

$WinId = (int)($Winner['ID'] ?? 0);
$WinDevId = trim((string)($Winner['Device_ID'] ?? ''));
if ($WinId <= 0 || $WinDevId === '') {
continue;
}

$MergedUuid = trim((string)($Winner['User_UUID'] ?? ''));
if ($MergedUuid === '_') $MergedUuid = '';
$MergedCid = trim((string)($Winner['Client_ID'] ?? ''));
if ($MergedCid === '_') $MergedCid = '';
$MergedTg = (int)($Winner['Telegram_ID'] ?? 0);
$MergedPhone = trim((string)($Winner['Phone'] ?? ''));
$MergedFullName = trim((string)($Winner['Full_Name'] ?? ''));
$MergedDevName = trim((string)($Winner['Device_Name'] ?? ''));
$MergedPlatform = trim((string)($Winner['Platform'] ?? ''));
$MergedIp = trim((string)($Winner['Last_IP'] ?? ''));

foreach ($Losers as $Loser) {
$LUuid = trim((string)($Loser['User_UUID'] ?? ''));
if ($LUuid === '_') $LUuid = '';
$LCid = trim((string)($Loser['Client_ID'] ?? ''));
if ($LCid === '_') $LCid = '';
$LTg = (int)($Loser['Telegram_ID'] ?? 0);
$LPhone = trim((string)($Loser['Phone'] ?? ''));
$LFullName = trim((string)($Loser['Full_Name'] ?? ''));
$LDevName = trim((string)($Loser['Device_Name'] ?? ''));
$LPlatform = trim((string)($Loser['Platform'] ?? ''));
$LIp = trim((string)($Loser['Last_IP'] ?? ''));

if ($MergedUuid === '' && $LUuid !== '') $MergedUuid = $LUuid;
if ($MergedCid === '' && $LCid !== '') $MergedCid = $LCid;
if ($MergedTg <= 0 && $LTg > 0) $MergedTg = $LTg;
if ($MergedPhone === '' && $LPhone !== '') $MergedPhone = $LPhone;
if ($MergedFullName === '' && $LFullName !== '' && $LFullName !== '_') $MergedFullName = $LFullName;
if ((self::isGenericDeviceName(self::normalizeDeviceNameForDedup($MergedDevName))) && !self::isGenericDeviceName(self::normalizeDeviceNameForDedup($LDevName))) {
$MergedDevName = $LDevName;
}
if ($MergedPlatform === '' && $LPlatform !== '') $MergedPlatform = $LPlatform;
if ($MergedIp === '' && $LIp !== '') $MergedIp = $LIp;
}
if ($MergedCid === '' && $MergedUuid !== '') $MergedCid = $MergedUuid;
if ($MergedUuid === '' && $MergedCid !== '') $MergedUuid = $MergedCid;

$MergeFn = static function () use (
$Db,
$WinId,
$WinDevId,
$MergedUuid,
$MergedCid,
$MergedTg,
$MergedPhone,
$MergedFullName,
$MergedDevName,
$MergedPlatform,
$MergedIp,
$Losers,
&$Removed
): void {
$Db->execute(
'UPDATE `App_Devices` SET `User_UUID` = COALESCE(NULLIF(?, \'\'), `User_UUID`), '
. '`Client_ID` = COALESCE(NULLIF(?, \'\'), `Client_ID`), '
. '`Telegram_ID` = CASE WHEN ? > 0 THEN ? ELSE `Telegram_ID` END, '
. '`Phone` = COALESCE(NULLIF(?, \'\'), `Phone`), '
. '`Full_Name` = COALESCE(NULLIF(?, \'\'), `Full_Name`), '
. '`Device_Name` = COALESCE(NULLIF(?, \'\'), `Device_Name`), '
. '`Platform` = COALESCE(NULLIF(?, \'\'), `Platform`), '
. '`Last_IP` = COALESCE(NULLIF(?, \'\'), `Last_IP`) '
. 'WHERE `ID` = ?',
[$MergedUuid, $MergedCid, $MergedTg, $MergedTg, $MergedPhone, $MergedFullName, $MergedDevName, $MergedPlatform, $MergedIp, $WinId]
);

foreach ($Losers as $Loser) {
$LoserId = (int)($Loser['ID'] ?? 0);
$LoserDevId = trim((string)($Loser['Device_ID'] ?? ''));
if ($LoserId <= 0 || $LoserDevId === '' || $LoserId === $WinId) {
continue;
}

try {
$Db->execute(
'UPDATE `App_Sessions` SET `Revoked_At` = CURRENT_TIMESTAMP WHERE `Device_ID` = ? AND `Revoked_At` IS NULL',
[$LoserDevId]
);
} catch (Throwable) {}
try { $Db->execute('DELETE FROM `App_SignIn_Requests` WHERE `Device_ID` = ?', [$LoserDevId]); } catch (Throwable) {}
try { $Db->execute('DELETE FROM `App_Notifications` WHERE `Device_ID` = ?', [$LoserDevId]); } catch (Throwable) {}
try {
$Db->execute('UPDATE IGNORE `App_Security_Alerts` SET `Device_ID` = ? WHERE `Device_ID` = ?', [$WinDevId, $LoserDevId]);
$Db->execute('DELETE FROM `App_Security_Alerts` WHERE `Device_ID` = ?', [$LoserDevId]);
} catch (Throwable) {}
try {
$Db->execute('UPDATE IGNORE `App_User_Activity` SET `Device_ID` = ? WHERE `Device_ID` = ?', [$WinDevId, $LoserDevId]);
$Db->execute('DELETE FROM `App_User_Activity` WHERE `Device_ID` = ?', [$LoserDevId]);
} catch (Throwable) {}

$Db->execute('DELETE FROM `App_Devices` WHERE `ID` = ?', [$LoserId]);
$Removed++;
}
};

if (method_exists($Db, 'transaction')) {
$Db->transaction($MergeFn);
} else {
$MergeFn();
}
}
}

return $Removed;
} catch (Throwable $Error) {
error_log('[Umbrella-Bot][AppSchema] deduplicateTrustedDevices: ' . $Error->getMessage());
return 0;
}
}

public static function isSamePhysicalDeviceRow(array $A, array $B, bool $AllowGenericMatch = true): bool {
$PlatA = self::normalizePlatformForDedup((string)($A['Platform'] ?? ''));
$PlatB = self::normalizePlatformForDedup((string)($B['Platform'] ?? ''));
$NameA = self::normalizeDeviceNameForDedup((string)($A['Device_Name'] ?? ''));
$NameB = self::normalizeDeviceNameForDedup((string)($B['Device_Name'] ?? ''));

if ($PlatA !== '' && $PlatB !== '' && $PlatA !== $PlatB) {
return false;
}

$GenericA = self::isGenericDeviceName($NameA);
$GenericB = self::isGenericDeviceName($NameB);

if ($PlatA !== '' && $PlatA === $PlatB) {
if (($GenericA || $GenericB) && $AllowGenericMatch) {
return true;
}
if (!$GenericA && !$GenericB && $NameA === $NameB) {
return true;
}
if ($GenericA && $GenericB && $AllowGenericMatch) {
return true;
}

if (!$GenericA && !$GenericB) {
$CompactA = (string)(preg_replace('/[\s\-_]+/u', '', $NameA) ?? $NameA);
$CompactB = (string)(preg_replace('/[\s\-_]+/u', '', $NameB) ?? $NameB);
if ($CompactA !== '' && $CompactA === $CompactB) {
return true;
}

$Short = mb_strlen($NameA, 'UTF-8') <= mb_strlen($NameB, 'UTF-8') ? $NameA : $NameB;
$Long = $Short === $NameA ? $NameB : $NameA;
if (mb_strlen($Short, 'UTF-8') >= 4 && str_contains($Long, $Short)) {
$Remainder = trim(str_replace($Short, '', $Long), " \t\n\r\0\x0B-_()");
if ($Remainder !== '' && preg_match('/\d/', $Remainder) !== 1) {
if (preg_match('/^(samsung|xiaomi|redmi|poco|google|huawei|honor|realme|oppo|vivo|nokia|sony|motorola|oneplus|asus|lenovo|hp|dell|acer|msi|apple|desktop|laptop|pc|android|windows)$/i', $Remainder) === 1) {
return true;
}
}
}
}
return false;
}

if (($PlatA === '' || $PlatB === '') && !$GenericA && !$GenericB && $NameA === $NameB) {
return true;
}

return false;
}

private static function normalizePhoneForDedup(string $Phone): string {
$Digits = strtr(trim($Phone), [
'۰' => '0', '۱' => '1', '۲' => '2', '۳' => '3', '۴' => '4',
'۵' => '5', '۶' => '6', '۷' => '7', '۸' => '8', '۹' => '9',
'٠' => '0', '١' => '1', '٢' => '2', '٣' => '3', '٤' => '4',
'٥' => '5', '٦' => '6', '٧' => '7', '٨' => '8', '٩' => '9',
]);
$Digits = (string)(preg_replace('/\D+/', '', $Digits) ?? '');
if ($Digits === '') return '';
if (str_starts_with($Digits, '0098') && strlen($Digits) >= 13) {
$Digits = '0' . substr($Digits, 4);
} elseif (str_starts_with($Digits, '98') && strlen($Digits) === 12) {
$Digits = '0' . substr($Digits, 2);
} elseif (strlen($Digits) === 10 && str_starts_with($Digits, '9')) {
$Digits = '0' . $Digits;
}
return $Digits;
}

private static function normalizePlatformForDedup(string $Platform): string {
$Lower = mb_strtolower(trim($Platform), 'UTF-8');
if ($Lower === '') return '';
if (str_contains($Lower, 'win') || str_contains($Lower, 'ویندوز')) return 'windows';
if (str_contains($Lower, 'android') || str_contains($Lower, 'اندروید')) return 'android';
if (str_contains($Lower, 'ios') || str_contains($Lower, 'iphone') || str_contains($Lower, 'ipad') || str_contains($Lower, 'آیفون') || str_contains($Lower, 'آیپد')) return 'ios';
if (str_contains($Lower, 'mac') || str_contains($Lower, 'darwin') || str_contains($Lower, 'مک')) return 'macos';
if (str_contains($Lower, 'linux') || str_contains($Lower, 'لینوکس')) return 'linux';
return $Lower;
}

private static function normalizeDeviceNameForDedup(string $Name): string {
$Clean = str_replace(["\xE2\x80\x8C", "\xE2\x80\x8F", "\xE2\x80\x8E"], ' ', trim($Name));
$Clean = (string)(preg_replace('/\s+/u', ' ', $Clean) ?? $Clean);
return mb_strtolower(trim($Clean), 'UTF-8');
}

private static function isGenericDeviceName(string $Normalized): bool {
return in_array($Normalized, [
'',
'_',
'unknown',
'device',
'desktop',
'mobile',
'windows',
'windows pc',
'android',
'android device',
'ios',
'macos',
'linux',
'دستگاه',
'دستگاه بی نام',
'دستگاه نامشخص',
'رایانه ویندوز',
'دستگاه اندروید',
], true);
}

private static function normalizeVersionForDedup(string $Version): string {
$Trimmed = ltrim(trim($Version), 'vV');
if ($Trimmed === '') return '';
if (preg_match('/^(\d+(?:\.\d+){1,3})/', $Trimmed, $Matches) === 1) {
return $Matches[1];
}
return '';
}

private static function backfillDeviceIdentityAndSeen(Database $Database): void {
try {
$Devices = $Database->fetchAll(
'SELECT `ID`, `Device_ID`, `User_UUID`, `Telegram_ID`, `Phone`, `Full_Name`, '
. 'CAST(`First_Seen_At` AS CHAR) AS `First_Char`, CAST(`Last_Seen_At` AS CHAR) AS `Last_Char` '
. 'FROM `App_Devices` ORDER BY `ID` ASC',
[]
);
$Tz = new DateTimeZone('Asia/Tehran');
foreach ($Devices as $Dev) {
$Id = (int)($Dev['ID'] ?? 0);
$DevId = (string)($Dev['Device_ID'] ?? '');
$Uuid = trim((string)($Dev['User_UUID'] ?? ''));
$TgId = (int)($Dev['Telegram_ID'] ?? 0);
$Phone = trim((string)($Dev['Phone'] ?? ''));
if ($Id <= 0 || $DevId === '') continue;

$CurrentName = trim((string)($Dev['Full_Name'] ?? ''));
$ResolvedName = '';
if ($CurrentName === '') {
try {
if ($TgId > 0) {
$U = $Database->fetch('SELECT `Full_Name` FROM `Users` WHERE `Telegram_ID` = ? LIMIT 1', [$TgId]);
$ResolvedName = trim((string)($U['Full_Name'] ?? ''));
}
if ($ResolvedName === '' && $Uuid !== '' && $Uuid !== '_') {
$U = $Database->fetch('SELECT `Full_Name` FROM `Users` WHERE `Client_ID` = ? LIMIT 1', [$Uuid]);
$ResolvedName = trim((string)($U['Full_Name'] ?? ''));
}
if ($ResolvedName === '' && $Phone !== '') {
$U = $Database->fetch('SELECT `Full_Name` FROM `Users` WHERE `Phone` = ? LIMIT 1', [$Phone]);
$ResolvedName = trim((string)($U['Full_Name'] ?? ''));
}
} catch (Throwable) {}
if ($ResolvedName === '') {
try {
$Req = $Database->fetch(
'SELECT `Full_Name` FROM `App_SignIn_Requests` '
. 'WHERE (`Device_ID` = ? OR (`User_UUID` IS NOT NULL AND `User_UUID` <> \'\' AND `User_UUID` = ?) OR (`Phone` IS NOT NULL AND `Phone` <> \'\' AND `Phone` = ?)) '
. 'AND `Full_Name` IS NOT NULL AND LENGTH(TRIM(`Full_Name`)) > 0 '
. 'ORDER BY `ID` DESC LIMIT 1',
[$DevId, $Uuid, $Phone]
);
$ResolvedName = trim((string)($Req['Full_Name'] ?? ''));
} catch (Throwable) {}
}
if (in_array($ResolvedName, ['_', 'کاربر', 'کاربر آمبرلا'], true) || preg_match('/^user-[0-9]+$/i', $ResolvedName) === 1) {
$ResolvedName = '';
}
}

$LastChar = trim((string)($Dev['Last_Char'] ?? ''));
$FirstChar = trim((string)($Dev['First_Char'] ?? ''));
$FixedSeen = '';
if ($LastChar === '' || str_starts_with($LastChar, '0000-00-00')) {
$ActTs = (int)$Database->scalar('SELECT COALESCE(MAX(`Last_Seen_At`), 0) FROM `App_User_Activity` WHERE `Device_ID` = ?', [$DevId], 0);
if ($ActTs > 0) {
$FixedSeen = (new DateTimeImmutable('@' . $ActTs))->setTimezone($Tz)->format('Y-m-d H:i:s');
} elseif ($FirstChar !== '' && !str_starts_with($FirstChar, '0000-00-00')) {
$FixedSeen = $FirstChar;
}
}

if ($ResolvedName !== '' && $FixedSeen !== '') {
$Database->execute('UPDATE `App_Devices` SET `Full_Name` = ?, `Last_Seen_At` = ? WHERE `ID` = ?', [$ResolvedName, $FixedSeen, $Id]);
} elseif ($ResolvedName !== '') {
$Database->execute('UPDATE `App_Devices` SET `Full_Name` = ? WHERE `ID` = ?', [$ResolvedName, $Id]);
} elseif ($FixedSeen !== '') {
$Database->execute('UPDATE `App_Devices` SET `Last_Seen_At` = ? WHERE `ID` = ?', [$FixedSeen, $Id]);
}
}
} catch (Throwable $Error) {
error_log('[Umbrella-Bot][AppSchema] backfill devices: ' . $Error->getMessage());
}
}

private static function statements(): array {
return [
'App_Cancelled_Payments' => "CREATE TABLE IF NOT EXISTS `App_Cancelled_Payments` (
`Authority` CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
`Telegram_ID` BIGINT NOT NULL,
`Pending_Payment` VARCHAR(255) NOT NULL,
`Pending_Topup` VARCHAR(100) NOT NULL,
`Pending_Plan` TEXT NULL,
`Pending_Custom_Plan` TEXT NULL,
`Amount` DECIMAL(18,2) NOT NULL,
`Credit` DECIMAL(18,2) NOT NULL,
`Status` VARCHAR(16) NOT NULL DEFAULT 'pending',
`Created_At` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
`Checked_At` TIMESTAMP NULL,
`Settled_At` TIMESTAMP NULL,
PRIMARY KEY (`Authority`),
KEY `IDX_Cancelled_Recovery` (`Status`, `Checked_At`),
KEY `IDX_Cancelled_User` (`Telegram_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",
 'App_Bot_Link_Requests' => "CREATE TABLE IF NOT EXISTS `App_Bot_Link_Requests` (
`Token_Hash` CHAR(64) NOT NULL,
`Session_Hash` CHAR(64) NOT NULL,
`User_UUID` VARCHAR(64) NOT NULL,
`Device_ID` VARCHAR(64) NOT NULL,
`Phone` VARCHAR(20) NOT NULL,
`Telegram_ID` BIGINT NULL,
`Expires_At` INT UNSIGNED NOT NULL,
`Used_At` INT UNSIGNED NULL,
PRIMARY KEY (`Token_Hash`),
KEY `IDX_App_Bot_Link_Expiry` (`Expires_At`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",

'App_Devices' => "CREATE TABLE IF NOT EXISTS `App_Devices` (
`ID` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
`Device_ID` VARCHAR(64) NOT NULL,
`User_UUID` VARCHAR(64) NULL,
`Client_ID` VARCHAR(255) NULL,
`Telegram_ID` BIGINT NULL,
`Device_Name` VARCHAR(190) NULL,
`Full_Name` VARCHAR(190) NULL,
`Platform` VARCHAR(190) NULL,
`App_Version` VARCHAR(40) NULL,
`Phone` VARCHAR(20) NULL,
`Is_Trusted` TINYINT(1) NOT NULL DEFAULT 0,
`First_Seen_At` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
`Last_Seen_At` TIMESTAMP NULL,
`Last_IP` VARCHAR(45) NULL,
`Push_Enabled` TINYINT(1) NOT NULL DEFAULT 1,
PRIMARY KEY (`ID`),
UNIQUE KEY `UQ_App_Devices_Device_ID` (`Device_ID`),
KEY `IDX_App_Devices_User_UUID` (`User_UUID`),
KEY `IDX_App_Devices_Telegram_ID` (`Telegram_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",

'App_SignIn_Requests' => "CREATE TABLE IF NOT EXISTS `App_SignIn_Requests` (
`ID` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
`Challenge` CHAR(32) NOT NULL,
`Device_ID` VARCHAR(64) NOT NULL,
`Device_Name` VARCHAR(190) NULL,
`Platform` VARCHAR(190) NULL,
`App_Version` VARCHAR(40) NULL,
`IP` VARCHAR(45) NULL,
`Phone` VARCHAR(20) NOT NULL,
`Full_Name` VARCHAR(190) NULL,
`User_UUID` VARCHAR(64) NULL,
`Telegram_ID` BIGINT NULL,
`Otp_Hash` CHAR(64) NULL,
`Otp_Sent_At` INT UNSIGNED NULL,
`Otp_Attempts` TINYINT UNSIGNED NOT NULL DEFAULT 0,
`Stage` VARCHAR(24) NOT NULL DEFAULT 'code_sent',
`Token` CHAR(64) NULL,
`Created_At` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
`Expires_At` INT UNSIGNED NULL,
`Confirmed_At` INT UNSIGNED NULL,
`Decided_At` INT UNSIGNED NULL,
`Notified_At` INT UNSIGNED NULL,
PRIMARY KEY (`ID`),
UNIQUE KEY `UQ_App_SignIn_Challenge` (`Challenge`),
KEY `IDX_App_SignIn_Phone` (`Phone`),
KEY `IDX_App_SignIn_Stage` (`Stage`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",

'App_Sessions' => "CREATE TABLE IF NOT EXISTS `App_Sessions` (
`ID` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
`Token_Hash` CHAR(64) NOT NULL,
`User_UUID` VARCHAR(64) NOT NULL,
`Device_ID` VARCHAR(64) NOT NULL,
`Telegram_ID` BIGINT NULL,
`Created_At` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
`Last_Used_At` TIMESTAMP NULL,
`Revoked_At` TIMESTAMP NULL,
PRIMARY KEY (`ID`),
UNIQUE KEY `UQ_App_Sessions_Token` (`Token_Hash`),
KEY `IDX_App_Sessions_Device` (`Device_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",

'App_Notifications' => "CREATE TABLE IF NOT EXISTS `App_Notifications` (
`ID` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
`User_UUID` VARCHAR(64) NULL,
`Device_ID` VARCHAR(64) NULL,
`Title` VARCHAR(190) NOT NULL,
`Body` TEXT NULL,
`Level` VARCHAR(20) NOT NULL DEFAULT 'info',
`Sent_At` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
`Delivered_At` INT UNSIGNED NULL,
`Event_Key` CHAR(64) NULL UNIQUE,
PRIMARY KEY (`ID`),
KEY `IDX_App_Notifications_User` (`User_UUID`),
KEY `IDX_App_Notifications_Device` (`Device_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",

'App_Device_Limits' => "CREATE TABLE IF NOT EXISTS `App_Device_Limits` (
`Telegram_ID` BIGINT NOT NULL,
`Max_Devices` TINYINT UNSIGNED NOT NULL DEFAULT 1,
`Updated_At` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
PRIMARY KEY (`Telegram_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",

'App_Bypass_Settings' => "CREATE TABLE IF NOT EXISTS `App_Bypass_Settings` (
`User_UUID` VARCHAR(64) NOT NULL,
`Iran` TINYINT(1) NOT NULL DEFAULT 0,
`Domains` TEXT NULL,
`Updated_At` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
PRIMARY KEY (`User_UUID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",

'App_Filter_Settings' => "CREATE TABLE IF NOT EXISTS `App_Filter_Settings` (
`User_UUID` VARCHAR(64) NOT NULL,
`Enabled` TINYINT(1) NOT NULL DEFAULT 0,
`Adult` TINYINT(1) NOT NULL DEFAULT 0,
`Social` TINYINT(1) NOT NULL DEFAULT 0,
`Gambling` TINYINT(1) NOT NULL DEFAULT 0,
`Ads` TINYINT(1) NOT NULL DEFAULT 0,
`Streaming` TINYINT(1) NOT NULL DEFAULT 0,
`Dating` TINYINT(1) NOT NULL DEFAULT 0,
`Violence` TINYINT(1) NOT NULL DEFAULT 0,
`Messaging` TINYINT(1) NOT NULL DEFAULT 0,
`Custom_Domains` TEXT NULL,
`Updated_By` VARCHAR(20) NOT NULL DEFAULT 'app',
`Updated_At` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
PRIMARY KEY (`User_UUID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",

'App_User_Activity' => "CREATE TABLE IF NOT EXISTS `App_User_Activity` (
`ID` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
`Device_ID` VARCHAR(64) NOT NULL,
`User_UUID` VARCHAR(64) NULL,
`Telegram_ID` BIGINT NULL,
`Category` VARCHAR(20) NOT NULL,
`Target` VARCHAR(190) NOT NULL,
`Hits` INT UNSIGNED NOT NULL DEFAULT 1,
`Bytes_Down` BIGINT UNSIGNED NOT NULL DEFAULT 0,
`Bytes_Up` BIGINT UNSIGNED NOT NULL DEFAULT 0,
`Last_Seen_At` INT UNSIGNED NOT NULL,
PRIMARY KEY (`ID`),
UNIQUE KEY `UQ_Activity_Dev_Cat_Target` (`Device_ID`, `Category`, `Target`),
KEY `IDX_Activity_User` (`Telegram_ID`, `Last_Seen_At`),
KEY `IDX_Activity_UUID` (`User_UUID`, `Last_Seen_At`),
KEY `IDX_Activity_Seen` (`Last_Seen_At`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",

'App_Security_Alerts' => "CREATE TABLE IF NOT EXISTS `App_Security_Alerts` (
`ID` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
`Device_ID` VARCHAR(64) NOT NULL,
`User_UUID` VARCHAR(64) NULL,
`Telegram_ID` BIGINT NULL,
`Threat_Key` VARCHAR(191) NOT NULL,
`Threat_Name` VARCHAR(191) NOT NULL,
`Category` VARCHAR(32) NOT NULL DEFAULT 'malware',
`Severity` VARCHAR(16) NOT NULL DEFAULT 'high',
`Target` VARCHAR(255) NOT NULL DEFAULT '',
`First_Detected_At` INT UNSIGNED NOT NULL,
`Last_Detected_At` INT UNSIGNED NOT NULL,
`Last_Notified_At` INT UNSIGNED NOT NULL DEFAULT 0,
`Hit_Count` INT UNSIGNED NOT NULL DEFAULT 1,
`Resolved` TINYINT(1) NOT NULL DEFAULT 0,
PRIMARY KEY (`ID`),
UNIQUE KEY `UQ_Security_Device_Threat` (`Device_ID`, `Threat_Key`),
KEY `IDX_Security_Tg` (`Telegram_ID`),
KEY `IDX_Security_Last` (`Last_Detected_At`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",

'App_Promo_Media' => "CREATE TABLE IF NOT EXISTS `App_Promo_Media` (
`Media_Key` VARCHAR(64) NOT NULL,
`Mime_Type` VARCHAR(64) NOT NULL,
`Image_Blob` MEDIUMBLOB NOT NULL,
`Updated_At` INT UNSIGNED NOT NULL,
PRIMARY KEY (`Media_Key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",
];
}
}
?>
