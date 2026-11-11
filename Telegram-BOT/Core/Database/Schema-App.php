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
}

private static function statements(): array {
return [
'App_Devices' => "CREATE TABLE IF NOT EXISTS `App_Devices` (
`ID` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
`Device_ID` VARCHAR(64) NOT NULL,
`User_UUID` VARCHAR(64) NULL,
`Client_ID` VARCHAR(255) NULL,
`Telegram_ID` BIGINT NULL,
`Device_Name` VARCHAR(190) NULL,
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
];
}
}
?>
