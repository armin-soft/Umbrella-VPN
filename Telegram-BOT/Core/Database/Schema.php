<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/Database/Database.php';
require_once __DIR__ . '/Schema-App.php';
require_once dirname(__DIR__, 2) . '/Config/Environment.php';

final class Schema {
public static function ensureInstalled(): void {
try {
$Database = Database::getInstance();
$Count = (int)$Database->scalar(
"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'Users'"
);

if ($Count === 0) {
self::install();
self::migrate();
return;
}

self::migrate();
}

catch (Throwable) {
try { self::install(); } catch (Throwable) {}
}
}

public static function install(): void {
self::ensureDatabase();
$Database = Database::getInstance();
$Schema_File = dirname(__DIR__, 2) . '/Database/Schema.SQL';
$SQL = (string)file_get_contents($Schema_File);
$Clean = preg_replace('/^\s*--.*$/m', '', $SQL) ?? $SQL;
$Statements = array_filter(
array_map('trim', preg_split('/;\s*[\r\n]+/', $Clean) ?: []),
static fn(string $Block): bool => $Block !== ''
);

foreach ($Statements as $Statement) {
try {
$Database->connection()->exec($Statement);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Schema-Install] Statement skipped: ' . $Error->getMessage());
}
}
}

public static function migrate(): void {
$Database = Database::getInstance();

$Migrations = [
['table' => 'Users', 'column' => 'Channel_Member_Check_At', 'definition' => 'INT UNSIGNED NULL'],
['table' => 'User_Sessions', 'column' => 'Pending_Custom_Plan', 'definition' => 'TEXT NULL'],
['table' => 'User_Sessions', 'column' => 'Pending_Topup', 'definition' => 'DECIMAL(18,0) NULL'],
['table' => 'User_Sessions', 'column' => 'Broadcast_Mode', 'definition' => 'VARCHAR(20) NULL'],
['table' => 'User_Sessions', 'column' => 'Idle_Notify_Users', 'definition' => 'TEXT NULL'],
['table' => 'User_Sessions', 'column' => 'Temp_Ticket_ID', 'definition' => 'BIGINT NULL'],
['table' => 'User_Sessions', 'column' => 'Ticket_Subject', 'definition' => 'VARCHAR(255) NULL'],
['table' => 'User_Sessions', 'column' => 'Ticket_Description', 'definition' => 'TEXT NULL'],
['table' => 'User_Sessions', 'column' => 'Ticket_Category', 'definition' => "VARCHAR(20) NULL DEFAULT 'other'"],
['table' => 'User_Sessions', 'column' => 'Ticket_Priority', 'definition' => "VARCHAR(20) NULL DEFAULT 'medium'"],
['table' => 'User_Sessions', 'column' => 'Custom_Days', 'definition' => 'INT NULL'],
['table' => 'User_Sessions', 'column' => 'Custom_GB', 'definition' => 'DECIMAL(12,2) NULL'],
['table' => 'User_Sessions', 'column' => 'Template_Code', 'definition' => 'VARCHAR(50) NULL'],
['table' => 'Users', 'column' => 'Tags', 'definition' => 'VARCHAR(255) NULL'],
['table' => 'Users', 'column' => 'Total_Recharge', 'definition' => 'DECIMAL(18,0) NOT NULL DEFAULT 0'],
['table' => 'Users', 'column' => 'Total_Spent', 'definition' => 'DECIMAL(18,0) NOT NULL DEFAULT 0'],
['table' => 'Users', 'column' => 'Last_Login_At', 'definition' => 'TIMESTAMP NULL'],
['table' => 'Users', 'column' => 'Auto_Renew_Plan', 'definition' => 'VARCHAR(50) NULL'],
['table' => 'Users', 'column' => 'Blocked_At', 'definition' => 'DATETIME NULL'],
['table' => 'Users', 'column' => 'Username', 'definition' => 'VARCHAR(64) NULL'],
['table' => 'Users', 'column' => 'Rank_Title', 'definition' => 'VARCHAR(50) NULL'],
['table' => 'Transactions', 'column' => 'Source', 'definition' => "VARCHAR(30) NOT NULL DEFAULT 'admin'"],
['table' => 'Subscription_Logs', 'column' => 'Source', 'definition' => "VARCHAR(30) NOT NULL DEFAULT 'admin'"],
['table' => 'Subscription_Logs', 'column' => 'Actor_ID', 'definition' => 'BIGINT NULL'],
];

foreach ($Migrations as $Migration) {
$Table = $Migration['table'];
$Column = $Migration['column'];
$Definition = $Migration['definition'];
$Exists = (int)$Database->scalar(
"SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?",
[$Table, $Column]
);

if ($Exists === 0) {
try {
$Database->connection()->exec("ALTER TABLE `{$Table}` ADD COLUMN `{$Column}` {$Definition}");
}

catch (Throwable $Error) {
error_log("[Umbrella-Bot][Schema-Migration] Failed to add column {$Table}.{$Column}: " . $Error->getMessage());
}
}
}

self::upgradeSmsTemplates();
// The desktop app's tables: additive only, so an existing install is safe.
AppSchema::ensureInstalled();
self::migrateTicketCategoryEnum();
self::migrateSessionTicketColumns();
self::migrateLegacyRevenue();
self::migrateHistorySources();
self::ensureTables();
}

private static function migrateSessionTicketColumns(): void {
$Changes = [
'Ticket_Category' => "VARCHAR(20) NULL DEFAULT 'other'",
'Ticket_Priority' => "VARCHAR(20) NULL DEFAULT 'medium'",
];

try {
$Database = Database::getInstance();

foreach ($Changes as $Column => $Definition) {
$Nullable = (string)$Database->scalar(
"SELECT IS_NULLABLE FROM information_schema.columns
WHERE table_schema = DATABASE() AND table_name = 'User_Sessions' AND column_name = ?",
[$Column]
);

if ($Nullable === 'NO') {
$Database->connection()->exec("ALTER TABLE `User_Sessions` MODIFY COLUMN `{$Column}` {$Definition}");
}
}
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Schema-Migration] Session ticket columns migration failed: ' . $Error->getMessage());
}
}

private static function migrateTicketCategoryEnum(): void {
if ((string)self::safeSetting('Ticket_Category_Enum_v1') === '1') return;

try {
$Database = Database::getInstance();
$Current = (string)$Database->scalar(
"SELECT COLUMN_TYPE FROM information_schema.columns
WHERE table_schema = DATABASE() AND table_name = 'Tickets' AND column_name = 'Category'"
);

if ($Current !== '' && !str_contains($Current, "'account'")) {
$Database->connection()->exec(
"ALTER TABLE `Tickets` MODIFY COLUMN `Category` ENUM('financial','technical','sales','account','other') NOT NULL DEFAULT 'other'"
);
}

$Database->execute('INSERT INTO `Settings` (`Key`, `Value`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `Value` = VALUES(`Value`)',
['Ticket_Category_Enum_v1', '1']);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Schema-Migration] Ticket category enum migration failed: ' . $Error->getMessage());
}
}

private static function migrateHistorySources(): void {
if ((string)self::safeSetting('History_Source_Migration_v1') === '1') return;

try {
$Database = Database::getInstance();
$Database->execute("UPDATE `Transactions` SET `Source` = 'gateway'
WHERE (`Source` IS NULL OR `Source` = '' OR `Source` = 'admin')
AND (`Type` IN ('payment_success', 'topup')
OR `Description` LIKE '%درگاه پرداخت%'
OR `Description` LIKE '%زرین پال%'
OR `Description` LIKE '%زرینپال%'
OR `Description` LIKE '%پرداخت موفق%')");
$Database->execute("UPDATE `Subscription_Logs` SET `Source` = 'user'
WHERE (`Source` IS NULL OR `Source` = '' OR `Source` = 'admin')
AND `Action` IN ('activate', 'renew')");
$Database->execute("UPDATE `Subscription_Logs` SET `Source` = 'scheduler'
WHERE (`Source` IS NULL OR `Source` = '' OR `Source` = 'admin')
AND `Action` = 'expire'
AND `Server_Response` LIKE '%زمان بند%'");
$Database->execute("UPDATE `Subscription_Logs` SET `Source` = 'admin'
WHERE (`Source` IS NULL OR `Source` = '' OR `Source` = 'admin')
AND `Action` IN ('expire', 'deactivate', 'admin_update')");
$Database->execute('INSERT INTO `Settings` (`Key`, `Value`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `Value` = VALUES(`Value`)',
['History_Source_Migration_v1', '1']);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Schema-Migration] History source migration failed: ' . $Error->getMessage());
}
}

private static function migrateLegacyRevenue(): void {
if ((string)self::safeSetting('Revenue_Migration_v1') === '1') return;

try {
$Database = Database::getInstance();
$Affected = $Database->execute(
"UPDATE `Transactions` SET `Type` = 'payment_success'
WHERE `Type` = 'credit_add'
AND (`Description` LIKE '%درگاه پرداخت%' OR `Description` LIKE '%زرین پال%' OR `Description` LIKE '%زرینپال%')"
)->rowCount();
$Database->execute(
'INSERT INTO `Settings` (`Key`, `Value`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `Value` = VALUES(`Value`)',
['Revenue_Migration_v1', '1']
);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Schema-Migration] Legacy revenue migration failed: ' . $Error->getMessage());
}
}

private static function safeSetting(string $Key): ?string {
try {
$Value = Database::getInstance()->scalar('SELECT `Value` FROM `Settings` WHERE `Key` = ? LIMIT 1', [$Key]);
return $Value === null ? null : (string)$Value;
}

catch (Throwable) {
return null;
}
}

private static function upgradeSmsTemplates(): void {
$Database = Database::getInstance();
$Templates = [
'activate' => "{full_name} گرامی اشتراک {plan} شما با موفقیت فعال گردید.\n⏳مدت اعتبار: {remaining}\n\nسرور آمبرلا",
'renew' => "{full_name} گرامی اشتراک {plan} شما با موفقیت تمدید گردید.\n⏳مدت اعتبار: {remaining}\n\nسرور آمبرلا",
'client_activate' => "{full_name} گرامی کلاینت شما در سرور فعال گردید.\n\nسرور آمبرلا",
'client_deactivate' => "{full_name} گرامی کلاینت شما در سرور غیرفعال گردید.\nعلت: {reason}\n\nسرور آمبرلا",
'channel_leave_warning' => "{full_name} گرامی، شما از کانال اطلاع رسانی خارج شده اید.\n⏳مهلت باقیمانده: {remaining}\nدر غیر این صورت کلاینت شما قطع می گردد.\nلطفا از طریق ربات عضو کانال اطلاع رسانی شوید.\n\nسرور آمبرلا",
'channel_disabled' => "{full_name} گرامی، مهلت عضویت شما در کانال به اتمام رسید.\nکلاینت شما به دلیل عدم عضویت قطع گردید.\nبرای اتصال مجدد از طریق ربات عضو کانال اطلاع رسانی شوید.\n\nسرور آمبرلا",
'expire_warn_3' => "{full_name} گرامی اشتراک {plan} شما {days} روز دیگر به اتمام می رسد.\n⏳زمان باقیمانده: {remaining}\n\nسرور آمبرلا",
'expire_warn_1' => "{full_name} گرامی اشتراک {plan} شما فردا ({remaining} دیگر) به اتمام می رسد.\n\nسرور آمبرلا",
'expire_today' => "{full_name} گرامی اشتراک {plan} شما امروز ({remaining} دیگر) به اتمام می رسد.\n\nسرور آمبرلا",
'expired' => "{full_name} گرامی اشتراک {plan} شما به اتمام رسید.\nاتصال شما از سرور قطع گردید.\n\nسرور آمبرلا",
'topup_success' => "{full_name} گرامی کیف پول شما به مبلغ {amount} تومان شارژ شد.\nموجودی فعلی: {balance} تومان\n\nسرور آمبرلا",
'idle_notify' => "{full_name} گرامی از آخرین اتصال شما به سرور بیش از {days} روز گذشته است.\nاشتراک شما همچنان فعال است.\n\nسرور آمبرلا",
'nowruz' => "{full_name} گرامی سال نو را به شما تبریک می گوییم.\n\nسرور آمبرلا",
];

try {
foreach ($Templates as $Code => $Template) {
$Stored = $Database->scalar('SELECT `Template` FROM `SMS_Templates` WHERE `Code` = ? LIMIT 1', [$Code]);

if (!is_string($Stored) || $Stored === '' || $Stored === $Template) continue;
$Database->execute('UPDATE `SMS_Templates` SET `Template` = ? WHERE `Code` = ?', [$Template, $Code]);
}
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Schema-Migration] SMS template upgrade failed: ' . $Error->getMessage());
}
}

private static function ensureTables(): void {
$Database = Database::getInstance();
$Tables = [
'Admin_Logs' => "CREATE TABLE IF NOT EXISTS `Admin_Logs` (
`ID` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
`Admin_ID` BIGINT NOT NULL,
`Action` VARCHAR(50) NOT NULL,
`Target_User_ID` BIGINT NULL,
`Details` TEXT NULL,
`IP_Address` VARCHAR(45) NULL,
`Created_At` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
PRIMARY KEY (`ID`),
KEY `IDX_Admin_Logs_Admin_ID` (`Admin_ID`),
KEY `IDX_Admin_Logs_Action` (`Action`),
KEY `IDX_Admin_Logs_Created_At` (`Created_At`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",

'Tickets' => "CREATE TABLE IF NOT EXISTS `Tickets` (
`ID` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
`User_ID` BIGINT NOT NULL,
`Subject` VARCHAR(255) NOT NULL,
`Category` ENUM('financial','technical','sales','account','other') NOT NULL DEFAULT 'other',
`Priority` ENUM('low','medium','high','urgent') NOT NULL DEFAULT 'medium',
`Status` ENUM('open','pending','answered','closed') NOT NULL DEFAULT 'open',
`Assigned_Admin` BIGINT NULL,
`Last_Reply_At` TIMESTAMP NULL,
`Last_Reply_By` ENUM('user','admin') NULL,
`Created_At` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
`Updated_At` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
`Closed_At` TIMESTAMP NULL,
PRIMARY KEY (`ID`),
KEY `IDX_Tickets_User_ID` (`User_ID`),
KEY `IDX_Tickets_Status` (`Status`),
KEY `IDX_Tickets_Priority` (`Priority`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",

'Ticket_Messages' => "CREATE TABLE IF NOT EXISTS `Ticket_Messages` (
`ID` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
`Ticket_ID` BIGINT UNSIGNED NOT NULL,
`Sender_ID` BIGINT NOT NULL,
`Sender_Type` ENUM('user','admin') NOT NULL,
`Message` TEXT NULL,
`Photo_File_ID` VARCHAR(255) NULL,
`Created_At` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
PRIMARY KEY (`ID`),
KEY `IDX_Ticket_Messages_Ticket_ID` (`Ticket_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",

'Ratings' => "CREATE TABLE IF NOT EXISTS `Ratings` (
`ID` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
`User_ID` BIGINT NOT NULL,
`Subscription_Log_ID` BIGINT UNSIGNED NULL,
`Stars` TINYINT UNSIGNED NOT NULL,
`Comment` TEXT NULL,
`Created_At` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
PRIMARY KEY (`ID`),
KEY `IDX_Ratings_User_ID` (`User_ID`),
KEY `IDX_Ratings_Stars` (`Stars`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",

'Payment_Queue' => "CREATE TABLE IF NOT EXISTS `Payment_Queue` (
`ID` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
`User_ID` BIGINT NOT NULL,
`Authority` VARCHAR(100) NOT NULL,
`Amount` DECIMAL(18,0) NOT NULL,
`Type` VARCHAR(30) NOT NULL,
`Status` ENUM('pending','verified','failed','expired') NOT NULL DEFAULT 'pending',
`Attempts` TINYINT UNSIGNED NOT NULL DEFAULT 0,
`Last_Attempt_At` TIMESTAMP NULL,
`Verified_At` TIMESTAMP NULL,
`Created_At` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
PRIMARY KEY (`ID`),
UNIQUE KEY `UQ_Payment_Queue_Authority` (`Authority`),
KEY `IDX_Payment_Queue_Status` (`Status`),
KEY `IDX_Payment_Queue_Created_At` (`Created_At`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",

'SMS_Templates' => "CREATE TABLE IF NOT EXISTS `SMS_Templates` (
`ID` INT UNSIGNED NOT NULL AUTO_INCREMENT,
`Code` VARCHAR(50) NOT NULL,
`Name` VARCHAR(100) NOT NULL,
`Template` TEXT NOT NULL,
`Is_Active` TINYINT(1) NOT NULL DEFAULT 1,
`Updated_At` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
PRIMARY KEY (`ID`),
UNIQUE KEY `UQ_SMS_Templates_Code` (`Code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",

'Notifications' => "CREATE TABLE IF NOT EXISTS `Notifications` (
`ID` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
`User_ID` BIGINT NULL,
`Type` VARCHAR(30) NOT NULL,
`Title` VARCHAR(255) NOT NULL,
`Message` TEXT NULL,
`Is_Read` TINYINT(1) NOT NULL DEFAULT 0,
`Created_At` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
PRIMARY KEY (`ID`),
KEY `IDX_Notifications_User_ID` (`User_ID`),
KEY `IDX_Notifications_Is_Read` (`Is_Read`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",

'Cron_Lock' => "CREATE TABLE IF NOT EXISTS `Cron_Lock` (
`Job_Name` VARCHAR(100) NOT NULL,
`Locked_At` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
`Locked_By` VARCHAR(100) NULL,
PRIMARY KEY (`Job_Name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",

'Usage_Snapshots' => "CREATE TABLE IF NOT EXISTS `Usage_Snapshots` (
`Snapshot_Date` DATE NOT NULL,
`User_ID` BIGINT NOT NULL,
`Start_Used_GB` DECIMAL(12,3) NOT NULL DEFAULT 0,
`Last_Used_GB` DECIMAL(12,3) NOT NULL DEFAULT 0,
`Total_GB` DECIMAL(12,3) NOT NULL DEFAULT 0,
`Updated_At` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
PRIMARY KEY (`Snapshot_Date`, `User_ID`),
KEY `IDX_Usage_Snapshots_User_ID` (`User_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",
];

foreach ($Tables as $Table_Name => $Create_SQL) {
$Exists = (int)$Database->scalar(
"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?",
[$Table_Name]
);

if ($Exists === 0) {
try {
$Database->connection()->exec($Create_SQL);
}

catch (Throwable $Error) {
error_log("[Umbrella-Bot][Schema-Migration] Failed to create table {$Table_Name}: " . $Error->getMessage());
}
}
}

self::seedDefaultSmsTemplates();
self::seedSettings();
}

private static function seedDefaultSmsTemplates(): void {
$Database = Database::getInstance();
$Defaults = [
['activate', 'فعال سازی اشتراک', "{full_name} گرامی اشتراک {plan} شما با موفقیت فعال گردید.\n⏳مدت اعتبار: {remaining}\n\nسرور آمبرلا"],
['renew', 'تمدید اشتراک', "{full_name} گرامی اشتراک {plan} شما با موفقیت تمدید گردید.\n⏳مدت اعتبار: {remaining}\n\nسرور آمبرلا"],
['client_activate', 'فعال سازی کلاینت', "{full_name} گرامی کلاینت شما در سرور فعال گردید.\n\nسرور آمبرلا"],
['client_deactivate', 'غیرفعال سازی کلاینت', "{full_name} گرامی کلاینت شما در سرور غیرفعال گردید.\nعلت: {reason}\n\nسرور آمبرلا"],
['channel_leave_warning', 'هشدار خروج از کانال', "{full_name} گرامی، شما از کانال اطلاع رسانی خارج شده اید.\n⏳مهلت باقیمانده: {remaining}\nدر غیر این صورت کلاینت شما قطع می گردد.\nلطفا از طریق ربات عضو کانال اطلاع رسانی شوید.\n\nسرور آمبرلا"],
['channel_disabled', 'قطع کلاینت به دلیل خروج از کانال', "{full_name} گرامی، مهلت عضویت شما در کانال به اتمام رسید.\nکلاینت شما به دلیل عدم عضویت قطع گردید.\nبرای اتصال مجدد از طریق ربات عضو کانال اطلاع رسانی شوید.\n\nسرور آمبرلا"],
['expire_warn_3', 'هشدار ۳ روز قبل از انقضا', "{full_name} گرامی اشتراک {plan} شما {days} روز دیگر به اتمام می رسد.\n⏳زمان باقیمانده: {remaining}\n\nسرور آمبرلا"],
['expire_warn_1', 'هشدار ۱ روز قبل از انقضا', "{full_name} گرامی اشتراک {plan} شما فردا ({remaining} دیگر) به اتمام می رسد.\n\nسرور آمبرلا"],
['expire_today', 'هشدار روز انقضا', "{full_name} گرامی اشتراک {plan} شما امروز ({remaining} دیگر) به اتمام می رسد.\n\nسرور آمبرلا"],
['expired', 'انقضای اشتراک', "{full_name} گرامی اشتراک {plan} شما به اتمام رسید.\nاتصال شما از سرور قطع گردید.\n\nسرور آمبرلا"],
['topup_success', 'شارژ کیف پول', "{full_name} گرامی کیف پول شما به مبلغ {amount} تومان شارژ شد.\nموجودی فعلی: {balance} تومان\n\nسرور آمبرلا"],
['idle_notify', 'عدم استفاده از سرور', "{full_name} گرامی از آخرین اتصال شما به سرور بیش از {days} روز گذشته است.\nاشتراک شما همچنان فعال است.\n\nسرور آمبرلا"],
['nowruz', 'تبریک نوروز', "{full_name} گرامی سال نو را به شما تبریک می گوییم.\n\nسرور آمبرلا"],
];

foreach ($Defaults as $T) {
try {
$Database->execute(
'INSERT IGNORE INTO `SMS_Templates` (`Code`, `Name`, `Template`, `Is_Active`) VALUES (?, ?, ?, 1)',
[$T[0], $T[1], $T[2]]
);
}

catch (Throwable $Error) {
error_log("[Umbrella-Bot][Schema-Seed] SMS template failed: " . $Error->getMessage());
}
}
}

private static function seedSettings(): void {
$Database = Database::getInstance();
$Settings = [
['Daily_Report_Enabled', '1'],
['Daily_Report_Time', '00:00'],
['Expiry_Warning_3Days', '1'],
['Expiry_Warning_1Day', '1'],
['Expiry_Warning_Today', '1'],
['Auto_Ban_Inactive_Days', '180'],
['Bot_Username', ''],
];

foreach ($Settings as $S) {
try {
$Database->execute('INSERT IGNORE INTO `Settings` (`Key`, `Value`) VALUES (?, ?)', $S);
}

catch (Throwable $Error) {
error_log("[Umbrella-Bot][Schema-Seed] Setting failed: " . $Error->getMessage());
}
}
}

private static function ensureDatabase(): void {
$Name = Environment::getDatabaseName();

if ($Name === '') return;
try {
Database::getInstance()->connection();
return;
}

catch (PDOException) {
}

$Server = new PDO(
sprintf('mysql:host=%s;port=%d;charset=utf8mb4', Environment::getDatabaseHost(), Environment::getDatabasePort()),
Environment::getDatabaseUser(),
Environment::getDatabasePassword(),
[PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);

$Safe = str_replace('`', '', $Name);
$Server->exec("CREATE DATABASE IF NOT EXISTS `{$Safe}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
}
}
?>