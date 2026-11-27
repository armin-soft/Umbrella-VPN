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
];
}
}
?>
