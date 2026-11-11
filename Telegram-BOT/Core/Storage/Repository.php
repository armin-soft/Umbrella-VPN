<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/Database/Database.php';
require_once dirname(__DIR__) . '/Support/Helper.php';

final class Repository {
private function __construct() {
}

private function __clone() {
}

private const USER_COLUMNS = [
'First_Name', 'Chat_ID', 'Balance', 'Is_Blocked', 'Full_Name', 'Phone', 'Operator',
'Client_ID', 'Client_Status', 'Subscription', 'Free_Plan_Claimed',
'Package_Duration', 'Package_Start_Date', 'Expiration_Date', 'Expiration_Time_Stamp',
'Total_Usage_GB', 'Used_Usage_GB', 'Remaining_Usage_GB', 'Percent_Usage',
'ED_25519_Private_Key', 'ED_25519_Public_Key', 'WireGuard_Private_Key', 'WireGuard_Public_Key', 'WireGuard_PSK',
'Last_Online', 'Server_Comment', 'Server_Enable', 'Server_Is_Active',
'Deactivation_Message', 'Registered_At', 'Channel_Grace_Started_At', 'Channel_Client_Disabled_At',
'Profile_Updated_At', 'Channel_Member_Check_At',
'Tags', 'Total_Recharge', 'Total_Spent',
'Last_Login_At', 'Auto_Renew_Plan', 'Username',
];

private const SESSION_COLUMNS = ['Flow', 'Temp_UID', 'Temp_Ticket_ID', 'Ticket_Subject', 'Ticket_Description', 'Ticket_Category', 'Ticket_Priority', 'Custom_Days', 'Custom_GB', 'Template_Code', 'Pending_Plan', 'Pending_Payment', 'Pending_Custom_Plan', 'Pending_Topup', 'Broadcast_Mode', 'Idle_Notify_Users', 'Is_In_Support'];
public const CLIENT_CONDITION = "`Client_ID` IS NOT NULL AND `Client_ID` != '' AND `Client_ID` != '_'";

public static function createUserIfMissing(int $User_Id): void {
Database::getInstance()->execute(
'INSERT IGNORE INTO `Users` (`Telegram_ID`) VALUES (?)',
[$User_Id]
);
}

public static function getUser(int $User_ID): array {
$Row = Database::getInstance()->fetch(
'SELECT * FROM `Users` WHERE `Telegram_ID` = ? LIMIT 1',
[$User_ID]
);

return $Row === null ? [] : $Row;
}

public static function findUserByPhone(string $Phone, int $Exclude_User_ID = 0): array {
$Phone = trim($Phone);

if ($Phone === '') return [];
$Candidates = self::phoneVariants($Phone);

if ($Candidates === []) return [];
$Placeholders = implode(',', array_fill(0, count($Candidates), '?'));
$Row = Database::getInstance()->fetch(
'SELECT `Telegram_ID`, `Full_Name`, `Phone` FROM `Users` WHERE `Phone` IN (' . $Placeholders . ') AND `Telegram_ID` <> ? LIMIT 1',
[...$Candidates, $Exclude_User_ID]
);

return $Row === null ? [] : $Row;
}

/**
 * The stored form of a number is not guaranteed — rows may hold the national
 * (`09…`), international (`+98…`/`0098…`) or bare form, with any separators —
 * so every common spelling is matched in one query.
 */
private static function phoneVariants(string $Phone): array {
$Local = \Helper::normalizePhone($Phone);

if ($Local === '') return [];
$Mobile = substr($Local, 1);

$Variants = [
$Phone,
$Local,
'+98' . $Mobile,
'0098' . $Mobile,
'98' . $Mobile,
$Mobile,
];

return array_values(array_unique(array_filter(array_map('trim', $Variants), static fn(string $Value): bool => $Value !== '')));
}

public static function findUserByIdentifier(string $Identifier): ?array {
$Raw = trim(self::latinDigits($Identifier));

if ($Raw === '') {
return null;
}

$Phone = self::localPhoneDigits($Raw);

if ($Phone !== '') {
goto PHONE_SEARCH;
}

if (ctype_digit($Raw) && strlen($Raw) >= 5) {
$By_Id = self::getUser((int)$Raw);

return !empty($By_Id) ? $By_Id : null;
}

if (!ctype_digit($Raw)) {
$Username = ltrim($Raw, '@');

if ($Username !== '') {
$By_Username = Database::getInstance()->fetch(
'SELECT * FROM `Users` WHERE `Username` = ? ORDER BY `Telegram_ID` ASC LIMIT 1',
[$Username]
);

if ($By_Username !== null) {
return $By_Username;
}
}
}

return null;

PHONE_SEARCH:
$Without_Zero = substr($Phone, 1);
$Variants = array_values(array_unique([$Phone, $Without_Zero, '98' . $Without_Zero, '+98' . $Without_Zero, '0098' . $Without_Zero]));
$Holders = implode(', ', array_fill(0, count($Variants), '?'));
$Row = Database::getInstance()->fetch(
"SELECT * FROM `Users` WHERE `Phone` IN ({$Holders}) OR `Server_Comment` IN ({$Holders}) ORDER BY `Telegram_ID` ASC LIMIT 1",
array_merge($Variants, $Variants)
);

if ($Row !== null) {
return $Row;
}

$Rows = Database::getInstance()->fetchAll(
"SELECT * FROM `Users` WHERE `Phone` IS NOT NULL OR `Server_Comment` IS NOT NULL ORDER BY `Telegram_ID` ASC"
);

foreach ($Rows as $Candidate) {
$Stored_Phone = self::nationalDigits((string)($Candidate['Phone'] ?? ''));
$Stored_Comment = self::nationalDigits((string)($Candidate['Server_Comment'] ?? ''));

if (($Stored_Phone !== '' && $Stored_Phone === $Phone) || ($Stored_Comment !== '' && $Stored_Comment === $Phone)) {
return $Candidate;
}
}

return null;
}

public static function nationalDigits(string $Text): string {
$Digits = (string)preg_replace('/[^0-9]/', '', self::latinDigits($Text));

if ($Digits === '') {
return '';
}

return strlen($Digits) > 10 ? substr($Digits, -10) : $Digits;
}

public static function findUserInServerRows(array $Rows, string $Identifier): ?array {
$Raw = trim(self::latinDigits($Identifier));

if ($Raw === '') {
return null;
}

$Needle = self::nationalDigits($Raw);
$Is_Numeric = ctype_digit($Raw) && strlen($Raw) >= 5;

foreach ($Rows as $Row) {
if (!is_array($Row)) {
continue;
}

if ($Is_Numeric && (int)($Row['telegram_id'] ?? 0) === (int)$Raw) {
return $Row;
}

$Candidate = self::nationalDigits((string)($Row['comment'] ?? ''));

if ($Needle !== '' && $Candidate !== '' && $Candidate === $Needle) {
return $Row;
}

$Name_Digits = self::nationalDigits((string)($Row['name'] ?? ''));

if ($Needle !== '' && $Name_Digits !== '' && $Name_Digits === $Needle) {
return $Row;
}
}

return null;
}

public static function linkServerRowToUser(array $Row): ?array {
$Telegram_ID = (int)($Row['telegram_id'] ?? 0);
$Uuid = trim((string)($Row['uuid'] ?? ''));
$User = [];

if ($Telegram_ID > 0) {
$User = self::getUser($Telegram_ID);
}

if (empty($User) && $Uuid !== '') {
$User = self::getUserByClientId($Uuid);
}

if (empty($User)) {
return null;
}

$User_ID = (int)($User['Telegram_ID'] ?? 0);

if ($User_ID <= 0) {
return null;
}

$Comment = trim((string)($Row['comment'] ?? ''));
$Fields = ['Server_Comment' => $Comment];
$Current_Client = trim((string)($User['Client_ID'] ?? ''));

if ($Uuid !== '' && ($Current_Client === '' || $Current_Client === '_')) {
$Fields['Client_ID'] = $Uuid;
}

$Current_Phone = trim((string)($User['Phone'] ?? ''));
$Comment_Phone = self::localPhoneDigits($Comment);

if ($Current_Phone === '' && $Comment_Phone !== '') {
$Fields['Phone'] = $Comment_Phone;
}

try {
self::updateUser($User_ID, $Fields);
}

catch (Throwable) {
return $User;
}

return self::getUser($User_ID);
}

private static function latinDigits(string $Text): string {
return strtr($Text, array_merge(
array_combine(['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'], ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']),
array_combine(['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'], ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'])
));
}

private static function localPhoneDigits(string $Text): string {
$Digits = (string)preg_replace('/[^0-9]/', '', $Text);

if ($Digits === '') {
return '';
}

if (str_starts_with($Digits, '0098')) {
$Digits = substr($Digits, 4);
}

elseif (str_starts_with($Digits, '98') && strlen($Digits) === 12) {
$Digits = substr($Digits, 2);
}

if (str_starts_with($Digits, '9') && strlen($Digits) === 10) {
$Digits = '0' . $Digits;
}

return (bool)preg_match('/^09\d{9}$/', $Digits) ? $Digits : '';
}


public static function updateUser(int $User_ID, array $Fields): void {
$Set = [];
$Params = [];

foreach ($Fields as $Column => $Value) {
if (!in_array($Column, self::USER_COLUMNS, true)) {
continue;
}

$Set[] = "`$Column` = ?";
$Params[] = $Value;
}

if ($Set === []) {
return;
}

$Params[] = $User_ID;

Database::getInstance()->execute(
'UPDATE `Users` SET ' . implode(', ', $Set) . ' WHERE `Telegram_ID` = ?',
$Params
);
}

public static function setBlocked(int $User_ID, bool $Blocked): void {
try {
$Now = $Blocked ? date('Y-m-d H:i:s') : null;
Database::getInstance()->execute(
'UPDATE `Users` SET `Is_Blocked` = ?, `Blocked_At` = ? WHERE `Telegram_ID` = ?',
[(int)$Blocked, $Now, $User_ID]
);
return;
}

catch (Throwable $Block_Error) {
if (stripos($Block_Error->getMessage(), 'Blocked_At') === false) throw $Block_Error;
}

Database::getInstance()->execute(
'UPDATE `Users` SET `Is_Blocked` = ? WHERE `Telegram_ID` = ?',
[$Blocked ? 1 : 0, $User_ID]
);
}

public static function getBlockedUsers(int $Limit = 50, int $Offset = 0): array {
$Limit = max(1, min(1000, (int)$Limit));
$Offset = max(0, (int)$Offset);

try {
$Rows = Database::getInstance()->fetchAll(
'SELECT `Telegram_ID`, `Full_Name`, `First_Name`, `Phone`, `Blocked_At` FROM `Users`
WHERE `Is_Blocked` = 1 ORDER BY `Telegram_ID` ASC
LIMIT ' . $Limit . ' OFFSET ' . $Offset
);

return $Rows === null ? [] : $Rows;
}

catch (Throwable) {
$Rows = Database::getInstance()->fetchAll(
'SELECT `Telegram_ID`, `Full_Name`, `First_Name`, `Phone` FROM `Users`
WHERE `Is_Blocked` = 1 ORDER BY `Telegram_ID` ASC
LIMIT ' . $Limit . ' OFFSET ' . $Offset
);

return $Rows === null ? [] : $Rows;
}
}

public static function getUserByClientId(string $Client_ID): array {
if (trim($Client_ID) === '') return [];
$Row = Database::getInstance()->fetch(
'SELECT * FROM `Users` WHERE `Client_ID` = ? LIMIT 1',
[trim($Client_ID)]
);

return $Row === null ? [] : $Row;
}

public static function getUserSession(int $User_ID): array {
$Row = Database::getInstance()->fetch(
'SELECT * FROM `User_Sessions` WHERE `Telegram_ID` = ? LIMIT 1',
[$User_ID]
);

return $Row === null ? [] : $Row;
}

public static function updateUserSession(int $User_ID, array $Fields): void {
$Cols = ['`Telegram_ID`'];
$Places = ['?'];
$Params = [$User_ID];
$Updates = [];

foreach ($Fields as $Column => $Value) {
if (!in_array($Column, self::SESSION_COLUMNS, true)) {
continue;
}

$Cols[] = "`$Column`";
$Places[] = '?';
$Params[] = $Value;
$Updates[] = "`$Column` = VALUES(`$Column`)";
}

if ($Updates === []) {
Database::getInstance()->execute('INSERT IGNORE INTO `User_Sessions` (`Telegram_ID`) VALUES (?)', [$User_ID]);
return;
}

Database::getInstance()->execute(
'INSERT INTO `User_Sessions` (' . implode(', ', $Cols) . ') VALUES ('
. implode(', ', $Places) . ') ON DUPLICATE KEY UPDATE ' . implode(', ', $Updates),
$Params
);
}


public static function getBalance(int $User_ID): float {
return (float)(Database::getInstance()->scalar(
'SELECT `Balance` FROM `Users` WHERE `Telegram_ID` = ? LIMIT 1',
[$User_ID]
) ?? 0.0);
}

public static function addMoney(int $User_ID, float $Amount, string $Description = 'شارژ اعتبار توسط مدیریت', string $Source = 'admin'): void {
$Before = self::getBalance($User_ID);
Database::getInstance()->execute(
'UPDATE `Users` SET `Balance` = `Balance` + ? WHERE `Telegram_ID` = ?',
[$Amount, $User_ID]
);

$After = self::getBalance($User_ID);
self::addTransaction($User_ID, 'credit_add', (string)$Amount, (string)$Before, (string)$After, $Description, $Source);

if (!str_contains($Description, 'بازگشت')) {
self::addUserTotals($User_ID, $Amount, 0.0);
}
}

public static function addSpent(int $User_ID, float $Amount): void {
self::addUserTotals($User_ID, 0.0, $Amount);
}

public static function recordGatewayPayment(int $User_ID, float $Amount, string $Reference = '', ?string $Description = null): void {
if ($User_ID <= 0 || $Amount <= 0) return;
$Balance = self::getBalance($User_ID);
$Note = ($Description !== null && trim($Description) !== '') ? trim($Description) : 'پرداخت موفق درگاه زرین پال';

if ($Reference !== '') $Note .= ' | رهگیری: ' . $Reference;
self::addTransaction($User_ID, 'payment_success', (string)$Amount, (string)$Balance, (string)$Balance, $Note, 'gateway');
}

public static function removeMoney(int $User_ID, float $Amount): bool {
$Before = self::getBalance($User_ID);
$Affected = Database::getInstance()->execute(
'UPDATE `Users` SET `Balance` = `Balance` - ?
WHERE `Telegram_ID` = ? AND `Balance` >= ?',
[$Amount, $User_ID, $Amount]
)->rowCount();

if ($Affected > 0) {
$After = self::getBalance($User_ID);
self::addTransaction($User_ID, 'credit_sub', (string)$Amount, (string)$Before, (string)$After, 'کسر اعتبار توسط مدیریت', 'admin');
self::addUserTotals($User_ID, 0.0, $Amount);
}

return $Affected > 0;
}

public static function isBlocked(int $User_ID): bool {
return (int)(Database::getInstance()->scalar(
'SELECT `Is_Blocked` FROM `Users` WHERE `Telegram_ID` = ? LIMIT 1',
[$User_ID]
) ?? 0) === 1;
}

public static function allUserIds(): array {
return array_column(Database::getInstance()->fetchAll('SELECT `Telegram_ID` FROM `Users`'), 'Telegram_ID');
}


public static function totalUsers(): int {
return (int)Database::getInstance()->scalar('SELECT COUNT(*) FROM `Users`');
}

public static function getSetting(string $Key, mixed $Default = null): mixed {
$Value = Database::getInstance()->scalar(
'SELECT `Value` FROM `Settings` WHERE `Key` = ? LIMIT 1',
[$Key]
);

return $Value === null ? $Default : $Value;
}

public static function setSetting(string $Key, mixed $Value): void {
Database::getInstance()->execute(
'INSERT INTO `Settings` (`Key`, `Value`) VALUES (?, ?)
ON DUPLICATE KEY UPDATE `Value` = VALUES(`Value`)',
[$Key, (string)$Value]
);
}


public static function schedule(string $Command, int $User_ID, int $Run_After_Time_Stamp): void {
Database::getInstance()->execute(
'INSERT INTO `Scheduled_Jobs` (`Command`, `User_ID`, `Run_At`, `Created_At`)
VALUES (?, ?, FROM_UNIXTIME(?), NOW())',
[$Command, $User_ID, $Run_After_Time_Stamp]
);
}

public static function pendingSchedules(): array {
return Database::getInstance()->fetchAll(
'SELECT * FROM `Scheduled_Jobs` WHERE `Run_At` <= NOW() ORDER BY `Run_At` ASC'
);
}

public static function removeSchedule(int $Job_ID): void {
Database::getInstance()->execute('DELETE FROM `Scheduled_Jobs` WHERE `ID` = ?', [$Job_ID]);
}

public static function logSms(int $User_ID, string $Phone_Number, string $Message, bool $Status): void {
Database::getInstance()->execute(
'INSERT INTO `SMS_Logs` (`User_ID`, `Phone_Number`, `Message`, `Status`, `Created_At`)
VALUES (?, ?, ?, ?, NOW())',
[$User_ID, $Phone_Number, $Message, $Status ? 'موفق' : 'ناموفق']
);
}



public static function operatorDistribution(): array {
$Rows = Database::getInstance()->fetchAll(
"SELECT `Operator` AS `Operator`, COUNT(*) AS `Count` FROM `Users` WHERE `Operator` IS NOT NULL AND `Operator` != '' GROUP BY `Operator`"
);

$Result = [];

foreach ($Rows as $Row) {
$Result[(string)($Row['Operator'] ?? 'ناشناخته')] = (int)$Row['Count'];
}

return $Result;
}




public static function subscriptionDistribution(): array {
$Rows = Database::getInstance()->fetchAll(
"SELECT `Subscription` AS `Subscription`, COUNT(*) AS `Count` FROM `Users` WHERE `Subscription` IS NOT NULL AND `Subscription` != '' GROUP BY `Subscription`"
);

$Result = [];

foreach ($Rows as $Row) {
$Result[(string)($Row['Subscription'] ?? 'Unknown')] = (int)$Row['Count'];
}

return $Result;
}

public static function smsStatistics(): array {
$Success = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `SMS_Logs` WHERE `Status` = 'موفق'");
$Failed = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `SMS_Logs` WHERE `Status` = 'ناموفق'");

return [
'success' => $Success,
'failed' => $Failed,
];
}

public static function clientStatusDistribution(): array {
$Active = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Users` WHERE `Client_Status` = 'فعال' OR `Client_Status` = '✅فعال'");
$Inactive = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Users` WHERE `Client_Status` LIKE '%غیر فعال%' OR `Client_Status` LIKE '%غیرفعال%'");

return [
'active' => $Active,
'inactive' => $Inactive,
];
}

public static function balanceBuckets(): array {
$Zero = (int)Database::getInstance()->scalar('SELECT COUNT(*) FROM `Users` WHERE `Balance` = 0');
$Low = (int)Database::getInstance()->scalar('SELECT COUNT(*) FROM `Users` WHERE `Balance` > 0 AND `Balance` < 50000');
$Medium = (int)Database::getInstance()->scalar('SELECT COUNT(*) FROM `Users` WHERE `Balance` >= 50000 AND `Balance` < 200000');
$High = (int)Database::getInstance()->scalar('SELECT COUNT(*) FROM `Users` WHERE `Balance` >= 200000 AND `Balance` < 1000000');
$VeryHigh = (int)Database::getInstance()->scalar('SELECT COUNT(*) FROM `Users` WHERE `Balance` >= 1000000');

return [
'صفر' => $Zero,
'کمتر از ۵۰ هزار' => $Low,
'۵۰ تا ۲۰۰ هزار' => $Medium,
'۲۰۰ هزار تا ۱ میلیون' => $High,
'بیش از ۱ میلیون' => $VeryHigh,
];
}



public static function addTransaction(int $User_ID, string $Type, string $Amount, string $Balance_Before, string $Balance_After, ?string $Description = null, string $Source = 'admin'): void {
Database::getInstance()->execute(
'INSERT INTO `Transactions` (`User_ID`, `Type`, `Amount`, `Balance_Before`, `Balance_After`, `Description`, `Source`) VALUES (?, ?, ?, ?, ?, ?, ?)',
[$User_ID, $Type, $Amount, $Balance_Before, $Balance_After, $Description, $Source]
);
}

public static function getTransactions(int $User_ID, int $Page = 1, int $Limit = 5): array {
$Offset = ($Page - 1) * $Limit;
$Rows = Database::getInstance()->fetchAll(
"SELECT `Type`, `Amount`, `Balance_Before`, `Balance_After`, `Description`, `Source`, `Created_At`
FROM `Transactions`
WHERE `User_ID` = ?
ORDER BY `ID` DESC
LIMIT {$Limit} OFFSET {$Offset}",
[$User_ID]
);

return array_map(static function (array $Row): array {
return [
'Type' => (string)($Row['Type'] ?? ''),
'Amount' => (string)($Row['Amount'] ?? '0'),
'Balance_Before' => (string)($Row['Balance_Before'] ?? '0'),
'Balance_After' => (string)($Row['Balance_After'] ?? '0'),
'Description' => (string)($Row['Description'] ?? ''),
'Source' => (string)($Row['Source'] ?? 'admin'),
'Created_At' => (string)($Row['Created_At'] ?? ''),
];
}, $Rows);
}

public static function countTransactions(int $User_ID): int {
return (int)Database::getInstance()->scalar('SELECT COUNT(*) FROM `Transactions` WHERE `User_ID` = ?', [$User_ID]);
}

public static function addSubscriptionLog(int $User_ID, string $Action, ?string $Plan_Name, ?int $Days, ?float $Usage_GB, ?string $Server_Response = null, string $Source = 'user', ?int $Actor_ID = null): void {
Database::getInstance()->execute(
'INSERT INTO `Subscription_Logs` (`User_ID`, `Action`, `Plan_Name`, `Days`, `Usage_GB`, `Server_Response`, `Source`, `Actor_ID`) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
[$User_ID, $Action, $Plan_Name, $Days, $Usage_GB, $Server_Response, $Source, $Actor_ID]
);
}

public static function getSubscriptionLogs(int $User_ID, int $Page = 1, int $Limit = 5): array {
$Offset = ($Page - 1) * $Limit;
$Rows = Database::getInstance()->fetchAll(
"SELECT `Action`, `Plan_Name`, `Days`, `Usage_GB`, `Server_Response`, `Source`, `Actor_ID`, `Created_At`
FROM `Subscription_Logs`
WHERE `User_ID` = ?
ORDER BY `ID` DESC
LIMIT {$Limit} OFFSET {$Offset}",
[$User_ID]
);

return array_map(static function (array $Row): array {
return [
'Action' => (string)($Row['Action'] ?? ''),
'Plan_Name' => (string)($Row['Plan_Name'] ?? ''),
'Days' => isset($Row['Days']) ? (int)$Row['Days'] : null,
'Usage_GB' => isset($Row['Usage_GB']) ? (float)$Row['Usage_GB'] : null,
'Server_Response' => (string)($Row['Server_Response'] ?? ''),
'Source' => (string)($Row['Source'] ?? 'admin'),
'Actor_ID' => isset($Row['Actor_ID']) && (int)$Row['Actor_ID'] > 0 ? (int)$Row['Actor_ID'] : null,
'Created_At' => (string)($Row['Created_At'] ?? ''),
];
}, $Rows);
}

public static function countSubscriptionLogs(int $User_ID): int {
return (int)Database::getInstance()->scalar('SELECT COUNT(*) FROM `Subscription_Logs` WHERE `User_ID` = ?', [$User_ID]);
}



public static function globalStatistics(): array {
$Total_Users = self::totalUsers();
$Active_Users = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Users` WHERE `Client_Status` IN ('فعال', '✅فعال')");
$Expired_Users = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Users` WHERE `Client_Status` LIKE '%منقضی%'");
$Blocked_Users = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Users` WHERE `Is_Blocked` = 1");
$Has_Phone = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Users` WHERE `Phone` IS NOT NULL AND `Phone` != ''");
$Has_Profile = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Users` WHERE `Full_Name` IS NOT NULL AND `Full_Name` != ''");
$Has_Client = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Users` WHERE `Client_ID` IS NOT NULL AND `Client_ID` != '' AND `Client_ID` != '_'");
$Free_Claimed = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Users` WHERE `Free_Plan_Claimed` = 1");
$Total_Balance = (float)Database::getInstance()->scalar("SELECT COALESCE(SUM(`Balance`), 0) FROM `Users`");
$Avg_Balance = (float)Database::getInstance()->scalar("SELECT COALESCE(AVG(`Balance`), 0) FROM `Users`");
$Users_With_Balance = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Users` WHERE `Balance` > 0");
$Total_Transactions = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Transactions`");
$Total_Subscription_Logs = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Subscription_Logs`");
$Total_SMS = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `SMS_Logs`");
$Total_SMS_Success = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `SMS_Logs` WHERE `Status` = 'موفق'");
$Total_SMS_Failed = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `SMS_Logs` WHERE `Status` = 'ناموفق'");
$New_Today = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Users` WHERE DATE(COALESCE(NULLIF(CAST(`Registered_At` AS CHAR), '0000-00-00 00:00:00'), CAST(`Created_At` AS CHAR))) = CURDATE()");
$New_Week = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Users` WHERE COALESCE(NULLIF(CAST(`Registered_At` AS CHAR), '0000-00-00 00:00:00'), CAST(`Created_At` AS CHAR)) >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)");
$New_Month = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Users` WHERE COALESCE(NULLIF(CAST(`Registered_At` AS CHAR), '0000-00-00 00:00:00'), CAST(`Created_At` AS CHAR)) >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)");
$Revenue_Condition = self::revenueCondition();
$Revenue_Today = (float)Database::getInstance()->scalar("SELECT COALESCE(SUM(ABS(`Amount`)), 0) FROM `Transactions` WHERE {$Revenue_Condition} AND DATE(`Created_At`) = CURDATE()");
$Revenue_Week = (float)Database::getInstance()->scalar("SELECT COALESCE(SUM(ABS(`Amount`)), 0) FROM `Transactions` WHERE {$Revenue_Condition} AND `Created_At` >= DATE_SUB(NOW(), INTERVAL 7 DAY)");
$Revenue_Month = (float)Database::getInstance()->scalar("SELECT COALESCE(SUM(ABS(`Amount`)), 0) FROM `Transactions` WHERE {$Revenue_Condition} AND `Created_At` >= DATE_SUB(NOW(), INTERVAL 30 DAY)");
$Revenue_Total = (float)Database::getInstance()->scalar("SELECT COALESCE(SUM(ABS(`Amount`)), 0) FROM `Transactions` WHERE {$Revenue_Condition}");
$Revenue_Today_Count = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Transactions` WHERE {$Revenue_Condition} AND DATE(`Created_At`) = CURDATE()");
$Revenue_Month_Count = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Transactions` WHERE {$Revenue_Condition} AND `Created_At` >= DATE_SUB(NOW(), INTERVAL 30 DAY)");
$Total_Recharge_All = (float)Database::getInstance()->scalar('SELECT COALESCE(SUM(`Total_Recharge`), 0) FROM `Users`');
$Total_Spent_All = (float)Database::getInstance()->scalar('SELECT COALESCE(SUM(`Total_Spent`), 0) FROM `Users`');
$Now_Stamp = time();
$Clients_Cond = self::CLIENT_CONDITION;
$Active_Subscriptions = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Users` WHERE `Subscription` IS NOT NULL AND `Subscription` != '' AND `Expiration_Time_Stamp` IS NOT NULL AND `Expiration_Time_Stamp` > {$Now_Stamp}");
$Expiring_Today_Count = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Users` WHERE {$Clients_Cond} AND `Expiration_Time_Stamp` > {$Now_Stamp} AND `Expiration_Time_Stamp` <= " . ($Now_Stamp + 86400));
$Expiring_3_Count = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Users` WHERE {$Clients_Cond} AND `Expiration_Time_Stamp` > {$Now_Stamp} AND `Expiration_Time_Stamp` <= " . ($Now_Stamp + 259200));
$Expiring_7_Count = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Users` WHERE {$Clients_Cond} AND `Expiration_Time_Stamp` > {$Now_Stamp} AND `Expiration_Time_Stamp` <= " . ($Now_Stamp + 604800));
$SMS_Today_Total = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `SMS_Logs` WHERE DATE(`Created_At`) = CURDATE()");
$SMS_Today_Success = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `SMS_Logs` WHERE `Status` = 'موفق' AND DATE(`Created_At`) = CURDATE()");
$SMS_Today_Failed = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `SMS_Logs` WHERE `Status` = 'ناموفق' AND DATE(`Created_At`) = CURDATE()");
$Open_Tickets_Count = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Tickets` WHERE `Status` IN ('open','pending')");
$Server_Stats = self::serverClientsStats();
$Total_Used = (float)Database::getInstance()->scalar("SELECT COALESCE(SUM(`Used_Usage_GB`), 0) FROM `Users` WHERE `Used_Usage_GB` IS NOT NULL");
$Total_Quota = (float)Database::getInstance()->scalar("SELECT COALESCE(SUM(`Total_Usage_GB`), 0) FROM `Users` WHERE `Total_Usage_GB` IS NOT NULL");

return [
'total_users' => $Total_Users,
'active_users' => $Active_Users,
'expired_users' => $Expired_Users,
'blocked_users' => $Blocked_Users,
'has_phone' => $Has_Phone,
'has_profile' => $Has_Profile,
'has_client' => $Has_Client,
'free_claimed' => $Free_Claimed,
'total_balance' => $Total_Balance,
'avg_balance' => $Avg_Balance,
'users_with_balance' => $Users_With_Balance,
'total_transactions' => $Total_Transactions,
'total_subscription_logs' => $Total_Subscription_Logs,
'total_sms' => $Total_SMS,
'sms_success' => $Total_SMS_Success,
'sms_failed' => $Total_SMS_Failed,
'new_today' => $New_Today,
'new_week' => $New_Week,
'new_month' => $New_Month,
'revenue_today' => $Revenue_Today,
'revenue_week' => $Revenue_Week,
'revenue_month' => $Revenue_Month,
'revenue_total' => $Revenue_Total,
'revenue_today_count' => $Revenue_Today_Count,
'revenue_month_count' => $Revenue_Month_Count,
'total_recharge' => $Total_Recharge_All,
'total_spent' => $Total_Spent_All,
'active_subscriptions' => $Active_Subscriptions,
'expiring_today' => $Expiring_Today_Count,
'expiring_3days' => $Expiring_3_Count,
'expiring_7days' => $Expiring_7_Count,
'sms_today_total' => $SMS_Today_Total,
'sms_today_success' => $SMS_Today_Success,
'sms_today_failed' => $SMS_Today_Failed,
'open_tickets' => $Open_Tickets_Count,
'server_clients' => $Server_Stats['total'],
'server_clients_active' => $Server_Stats['active'],
'server_clients_disabled' => $Server_Stats['disabled'],
'server_clients_expired' => $Server_Stats['expired'],
'server_clients_with_usage' => $Server_Stats['with_usage'],
'server_quota' => $Server_Stats['total_quota'],
'server_used' => $Server_Stats['total_used'],
'server_remaining' => $Server_Stats['total_remaining'],
'server_avg_used' => $Server_Stats['avg_used'],
'top_consumer' => $Server_Stats['top_user'],
'total_used' => $Total_Used,
'total_quota' => $Total_Quota,
];
}

public static function logAdminAction(int $Admin_ID, string $Action, ?int $Target_User_ID, ?string $Details, ?string $IP = null): void {
Database::getInstance()->execute(
'INSERT INTO `Admin_Logs` (`Admin_ID`, `Action`, `Target_User_ID`, `Details`, `IP_Address`) VALUES (?, ?, ?, ?, ?)',
[$Admin_ID, $Action, $Target_User_ID, $Details, $IP]
);
}


public static function createTicket(int $User_ID, string $Subject, string $Category, string $Priority = 'medium'): int {
Database::getInstance()->execute(
'INSERT INTO `Tickets` (`User_ID`, `Subject`, `Category`, `Priority`) VALUES (?, ?, ?, ?)',
[$User_ID, $Subject, $Category, $Priority]
);
$ID = (int)Database::getInstance()->scalar('SELECT LAST_INSERT_ID()');
self::addTicketMessage($ID, $User_ID, 'user', $Subject, null);
return $ID;
}

public static function addTicketMessage(int $Ticket_ID, int $Sender_ID, string $Sender_Type, ?string $Message, ?string $Photo_File_ID = null): void {
Database::getInstance()->execute(
'INSERT INTO `Ticket_Messages` (`Ticket_ID`, `Sender_ID`, `Sender_Type`, `Message`, `Photo_File_ID`) VALUES (?, ?, ?, ?, ?)',
[$Ticket_ID, $Sender_ID, $Sender_Type, $Message, $Photo_File_ID]
);
Database::getInstance()->execute(
'UPDATE `Tickets` SET `Last_Reply_At` = NOW(), `Last_Reply_By` = ?, `Status` = ? WHERE `ID` = ?',
[$Sender_Type, $Sender_Type === 'admin' ? 'answered' : 'pending', $Ticket_ID]
);
}

public static function getTicket(int $ID): ?array {
$Row = Database::getInstance()->fetch('SELECT * FROM `Tickets` WHERE `ID` = ? LIMIT 1', [$ID]);
return $Row === null ? null : $Row;
}

public static function getTicketMessages(int $Ticket_ID): array {
return Database::getInstance()->fetchAll(
'SELECT * FROM `Ticket_Messages` WHERE `Ticket_ID` = ? ORDER BY `ID` ASC',
[$Ticket_ID]
);
}

public static function userTickets(int $User_ID): array {
return Database::getInstance()->fetchAll(
'SELECT * FROM `Tickets` WHERE `User_ID` = ? ORDER BY `ID` DESC',
[$User_ID]
);
}

public static function openTickets(int $Limit = 100): array {
return Database::getInstance()->fetchAll(
'SELECT * FROM `Tickets` WHERE `Status` IN (\'open\',\'pending\',\'answered\') ORDER BY `Priority` DESC, `ID` DESC LIMIT ' . max(1, $Limit)
);
}

public static function closeTicket(int $ID): void {
Database::getInstance()->execute(
'UPDATE `Tickets` SET `Status` = \'closed\', `Closed_At` = NOW() WHERE `ID` = ?',
[$ID]
);
}




public static function pendingPayments(int $Limit = 50): array {
return Database::getInstance()->fetchAll(
'SELECT * FROM `Payment_Queue` WHERE `Status` = \'pending\' ORDER BY `ID` ASC LIMIT ' . max(1, $Limit)
);
}

public static function markPaymentStatus(string $Authority, string $Status): void {
Database::getInstance()->execute(
'UPDATE `Payment_Queue` SET `Status` = ?, `Verified_At` = NOW() WHERE `Authority` = ?',
[$Status, $Authority]
);
}

public static function getSmsTemplate(string $Code): ?string {
$Row = Database::getInstance()->fetch(
'SELECT `Template` FROM `SMS_Templates` WHERE `Code` = ? AND `Is_Active` = 1 LIMIT 1',
[$Code]
);

return $Row === null ? null : (string)($Row['Template'] ?? null);
}



public static function addNotification(?int $User_ID, string $Type, string $Title, ?string $Message = null): void {
Database::getInstance()->execute(
'INSERT INTO `Notifications` (`User_ID`, `Type`, `Title`, `Message`) VALUES (?, ?, ?, ?)',
[$User_ID, $Type, $Title, $Message]
);
}




public static function tryCronLock(string $Job_Name, int $Ttl_Seconds = 3600): bool {
try {
$Database = Database::getInstance();
$Database->execute(
'DELETE FROM `Cron_Lock` WHERE `Locked_At` < DATE_SUB(NOW(), INTERVAL ' . max(60, $Ttl_Seconds) . ' SECOND)'
);
$Affected = $Database->execute('INSERT IGNORE INTO `Cron_Lock` (`Job_Name`) VALUES (?)', [$Job_Name])->rowCount();
return $Affected > 0;
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Cron-Lock] acquire failed for "' . $Job_Name . '": ' . $Error->getMessage());
return false;
}
}

public static function isCronLockHeld(string $Job_Name): bool {
try {
$Value = Database::getInstance()->scalar(
'SELECT `Locked_At` FROM `Cron_Lock` WHERE `Job_Name` = ? LIMIT 1',
[$Job_Name]
);
return $Value !== null;
}
catch (Throwable) {
return false;
}
}

public static function releaseCronLock(string $Job_Name): void {
try {
Database::getInstance()->execute('DELETE FROM `Cron_Lock` WHERE `Job_Name` = ?', [$Job_Name]);
}

catch (Throwable) {
}
}

public static function getLeaderboard(string $Type, int $Limit = 0): array {
$Sql_Limit = ($Limit > 0) ? (' LIMIT ' . $Limit) : '';

if ($Type === 'usage') {
return Database::getInstance()->fetchAll(
'SELECT `Telegram_ID`, `First_Name`, `Full_Name`, `Username`, `Client_ID`, `Subscription`, `Client_Status`,
`Used_Usage_GB` AS `Value`, `Total_Usage_GB`, `Remaining_Usage_GB`, `Percent_Usage`,
`Expiration_Time_Stamp`, `Last_Online`
FROM `Users`
WHERE ' . self::CLIENT_CONDITION . '
ORDER BY `Used_Usage_GB` DESC, `Total_Usage_GB` DESC' . $Sql_Limit
);
}

if ($Type === 'recharge') {
return Database::getInstance()->fetchAll(
'SELECT `Telegram_ID`, `First_Name`, `Full_Name`, `Total_Recharge` AS `Value` FROM `Users` WHERE `Total_Recharge` > 0 ORDER BY `Total_Recharge` DESC' . $Sql_Limit
);
}

if ($Type === 'duration') {
return Database::getInstance()->fetchAll(
'SELECT `Telegram_ID`, `First_Name`, `Full_Name`, `Registered_At` AS `Value` FROM `Users` WHERE `Registered_At` IS NOT NULL ORDER BY `Registered_At` ASC' . $Sql_Limit
);
}

return [];
}

public static function serverClientsStats(): array {
$Clients = self::CLIENT_CONDITION;
$Now = time();
$Total = (int)Database::getInstance()->scalar('SELECT COUNT(*) FROM `Users` WHERE ' . $Clients);
$Active = (int)Database::getInstance()->scalar("SELECT COUNT(*) FROM `Users` WHERE " . $Clients . " AND (`Server_Is_Active` = 1 OR `Client_Status` = 'فعال' OR `Client_Status` = '✅فعال')");
$Expired = (int)Database::getInstance()->scalar('SELECT COUNT(*) FROM `Users` WHERE ' . $Clients . ' AND `Expiration_Time_Stamp` IS NOT NULL AND `Expiration_Time_Stamp` > 0 AND `Expiration_Time_Stamp` <= ' . $Now);
$With_Usage = (int)Database::getInstance()->scalar('SELECT COUNT(*) FROM `Users` WHERE ' . $Clients . ' AND COALESCE(`Used_Usage_GB`, 0) > 0');
$Total_Quota = (float)Database::getInstance()->scalar('SELECT COALESCE(SUM(`Total_Usage_GB`), 0) FROM `Users` WHERE ' . $Clients);
$Total_Used = (float)Database::getInstance()->scalar('SELECT COALESCE(SUM(`Used_Usage_GB`), 0) FROM `Users` WHERE ' . $Clients);
$Total_Remaining = (float)Database::getInstance()->scalar('SELECT COALESCE(SUM(`Remaining_Usage_GB`), 0) FROM `Users` WHERE ' . $Clients);
$Expiring_Today = (int)Database::getInstance()->scalar('SELECT COUNT(*) FROM `Users` WHERE ' . $Clients . ' AND `Expiration_Time_Stamp` > ' . $Now . ' AND `Expiration_Time_Stamp` <= ' . ($Now + 86400));
$Expiring_3 = (int)Database::getInstance()->scalar('SELECT COUNT(*) FROM `Users` WHERE ' . $Clients . ' AND `Expiration_Time_Stamp` > ' . $Now . ' AND `Expiration_Time_Stamp` <= ' . ($Now + 259200));
$Expiring_7 = (int)Database::getInstance()->scalar('SELECT COUNT(*) FROM `Users` WHERE ' . $Clients . ' AND `Expiration_Time_Stamp` > ' . $Now . ' AND `Expiration_Time_Stamp` <= ' . ($Now + 604800));
$Top = Database::getInstance()->fetch(
'SELECT `Telegram_ID`, `Full_Name`, `First_Name`, `Used_Usage_GB` AS `Value`, `Total_Usage_GB` FROM `Users` WHERE ' . $Clients . ' ORDER BY `Used_Usage_GB` DESC LIMIT 1'
);

return [
'total' => $Total,
'active' => $Active,
'disabled' => max(0, $Total - $Active),
'expired' => $Expired,
'with_usage' => $With_Usage,
'total_quota' => max(0.0, $Total_Quota),
'total_used' => max(0.0, $Total_Used),
'total_remaining' => max(0.0, $Total_Remaining),
'avg_used' => $Total > 0 ? max(0.0, $Total_Used) / $Total : 0.0,
'expiring_today' => $Expiring_Today,
'expiring_3' => $Expiring_3,
'expiring_7' => $Expiring_7,
'top_user' => is_array($Top) ? $Top : [],
];
}

public static function revenueCondition(): string {
return "`Type` IN ('payment_success', 'topup')";
}


public static function addUserTotals(int $User_ID, float $Recharge = 0.0, float $Spent = 0.0): void {
if ($User_ID <= 0 || ($Recharge === 0.0 && $Spent === 0.0)) return;

Database::getInstance()->execute(
'UPDATE `Users` SET `Total_Recharge` = `Total_Recharge` + ?, `Total_Spent` = `Total_Spent` + ? WHERE `Telegram_ID` = ?',
[$Recharge, $Spent, $User_ID]
);
}

public static function rotateUsageSnapshots(): void {
$Today = (new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran')))->format('Y-m-d');

if ((string)self::getSetting('Usage_Snapshot_Date', '') === $Today) return;

try {
$Rows = Database::getInstance()->fetchAll(
'SELECT `Telegram_ID`, `Used_Usage_GB`, `Total_Usage_GB` FROM `Users` WHERE ' . self::CLIENT_CONDITION
);

foreach ($Rows as $Row) {
$Used = (float)($Row['Used_Usage_GB'] ?? 0);
Database::getInstance()->execute(
'INSERT INTO `Usage_Snapshots` (`Snapshot_Date`, `User_ID`, `Start_Used_GB`, `Last_Used_GB`, `Total_GB`)
VALUES (?, ?, ?, ?, ?)
ON DUPLICATE KEY UPDATE `User_ID` = VALUES(`User_ID`)',
[$Today, (int)($Row['Telegram_ID'] ?? 0), $Used, $Used, (float)($Row['Total_Usage_GB'] ?? 0)]
);
}

self::setSetting('Usage_Snapshot_Date', $Today);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Usage-Snapshot] rotate failed: ' . $Error->getMessage());
}
}

public static function updateUsageSnapshotValues(): int {
try {
return Database::getInstance()->execute(
'UPDATE `Usage_Snapshots` AS S
INNER JOIN `Users` AS U ON U.`Telegram_ID` = S.`User_ID`
SET S.`Last_Used_GB` = COALESCE(U.`Used_Usage_GB`, 0),
S.`Total_GB` = COALESCE(U.`Total_Usage_GB`, 0)
WHERE S.`Snapshot_Date` >= DATE_SUB(CURDATE(), INTERVAL 1 DAY)'
)->rowCount();
}

catch (Throwable) {
return 0;
}
}

public static function usageSnapshotTotals(string $Date = ''): array {
if ($Date === '') {
$Date = (new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran')))->format('Y-m-d');
}

try {
$Row = Database::getInstance()->fetch(
'SELECT COUNT(*) AS `Users`, COALESCE(SUM(`Start_Used_GB`), 0) AS `Start`, COALESCE(SUM(`Last_Used_GB`), 0) AS `Last`
FROM `Usage_Snapshots` WHERE `Snapshot_Date` = ?',
[$Date]
);
}

catch (Throwable) {
$Row = null;
}

$Users = (int)($Row['Users'] ?? 0);
$Start = (float)($Row['Start'] ?? 0);
$Last = (float)($Row['Last'] ?? 0);

return [
'date' => $Date,
'users' => $Users,
'start' => $Start,
'last' => $Last,
'used' => max(0.0, $Last - $Start),
'available' => $Users > 0,
];
}

public static function topUsageGainers(string $Date = '', int $Limit = 5): array {
if ($Date === '') {
$Date = (new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran')))->format('Y-m-d');
}

try {
$Rows = Database::getInstance()->fetchAll(
'SELECT S.`User_ID` AS `User_ID`, COALESCE(NULLIF(U.`Full_Name`, ""), NULLIF(U.`First_Name`, ""), "کاربر") AS `Full_Name`, (S.`Last_Used_GB` - S.`Start_Used_GB`) AS `Gain`
FROM `Usage_Snapshots` AS S
INNER JOIN `Users` AS U ON U.`Telegram_ID` = S.`User_ID`
WHERE S.`Snapshot_Date` = ? AND (S.`Last_Used_GB` - S.`Start_Used_GB`) > 0
ORDER BY `Gain` DESC, S.`User_ID` ASC
LIMIT ' . max(1, $Limit),
[$Date]
);
}

catch (Throwable) {
return [];
}

$Clean = [];

foreach ((is_array($Rows) ? $Rows : []) as $Row) {
$Gain = (float)($Row['Gain'] ?? 0);

if ($Gain <= 0) {
continue;
}

$Clean[] = [
'User_ID' => (int)($Row['User_ID'] ?? 0),
'Full_Name' => trim((string)($Row['Full_Name'] ?? '')) ?: 'کاربر',
'First_Name' => '',
'Gain' => round($Gain, 3),
];
}

return $Clean;
}

public static function userUsageGain(int $User_ID, string $Date = ''): ?float {
if ($Date === '') {
$Date = (new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran')))->format('Y-m-d');
}

try {
$Value = Database::getInstance()->scalar(
'SELECT (COALESCE(`Last_Used_GB`, 0) - COALESCE(`Start_Used_GB`, 0)) FROM `Usage_Snapshots` WHERE `Snapshot_Date` = ? AND `User_ID` = ? LIMIT 1',
[$Date, $User_ID]
);
}

catch (Throwable) {
return null;
}

return $Value === null ? null : (float)$Value;
}

public static function userUsageHistory(int $User_ID, int $Days = 7): array {
$Days = max(1, min(60, $Days));

try {
$Rows = Database::getInstance()->fetchAll(
'SELECT `Snapshot_Date` AS `Day`, (COALESCE(`Last_Used_GB`, 0) - COALESCE(`Start_Used_GB`, 0)) AS `Used`
FROM `Usage_Snapshots`
WHERE `User_ID` = ? AND `Snapshot_Date` >= DATE_SUB(CURDATE(), INTERVAL ' . max(0, $Days - 1) . ' DAY)
ORDER BY `Snapshot_Date` ASC',
[$User_ID]
);
}

catch (Throwable) {
return [];
}

$Result = [];

foreach ($Rows as $Row) {
$Result[(string)$Row['Day']] = (float)$Row['Used'];
}

return $Result;
}


}
?>