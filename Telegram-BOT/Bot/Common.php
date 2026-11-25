<?php
declare(strict_types=1);

require_once __DIR__ . '/Context.php';
require_once __DIR__ . '/Menu.php';
require_once __DIR__ . '/../Core/Telegram/Telegram.php';
require_once __DIR__ . '/../Core/Server/Umbrella-Server.php';
require_once __DIR__ . '/../Core/Server/Umbrella-Panel.php';
require_once __DIR__ . '/../Core/App/Account-Revocation.php';
require_once __DIR__ . '/../Core/Support/Helper.php';
require_once __DIR__ . '/../Core/Support/Bot-Config.php';
require_once __DIR__ . '/../Core/Storage/Repository.php';
require_once __DIR__ . '/../Core/SMS/IPPanel.php';
require_once __DIR__ . '/../Config/Environment.php';

final class Common {
private function __construct() {
}

private static ?array $Live_Server_Cache = null;

private static function unwrapListRows(mixed $Json): array {
if (!is_array($Json)) return [];
foreach (['items', 'users', 'data', 'results', 'records'] as $Key) {
if (isset($Json[$Key]) && is_array($Json[$Key])) return $Json[$Key];
}
return array_is_list($Json) ? $Json : [];
}

private static function isPlaceholderName(string $Name, int $User_ID = 0): bool {
$Trimmed = trim($Name);
if ($Trimmed === '' || $Trimmed === '_' || $Trimmed === 'کاربر' || $Trimmed === 'کاربر آمبرلا') {
return true;
}
if ($User_ID > 0 && $Trimmed === 'user-' . $User_ID) {
return true;
}
return preg_match('/^user-[0-9]+$/', $Trimmed) === 1;
}

private static function fieldChanged(mixed $Current, mixed $Next): bool {
if ($Current === null || $Next === null) {
return $Current !== $Next;
}
if (is_int($Next) || is_float($Next)) {
if (!is_numeric($Current)) return true;
return abs((float)$Current - (float)$Next) > 0.0005;
}
return (string)$Current !== (string)$Next;
}

private static function discoverPanelRow(array $User): ?array {
$User_ID = (int)($User['Telegram_ID'] ?? 0);
if (!class_exists('PanelClient')) return null;

$Candidates = [];
if ($User_ID > 0 && method_exists('PanelClient', 'findByTelegramId')) {
$By_Tg = PanelClient::findByTelegramId($User_ID);
if (is_array($By_Tg) && $By_Tg !== []) $Candidates[] = $By_Tg;
}
$Phone = trim((string)($User['Phone'] ?? ''));
if ($Phone !== '' && method_exists('PanelClient', 'findByPhone')) {
$By_Phone = PanelClient::findByPhone($Phone);
if (is_array($By_Phone) && $By_Phone !== []) $Candidates[] = $By_Phone;
}

foreach ($Candidates as $Row) {
$Candidate_UUID = trim((string)($Row['uuid'] ?? ''));
if ($Candidate_UUID === '' || $Candidate_UUID === '_') continue;
$Panel_Tg = (int)($Row['telegram_id'] ?? 0);
if ($User_ID > 0 && $Panel_Tg > 0 && $Panel_Tg !== $User_ID) continue;
if (method_exists('Repository', 'getUserByClientId')) {
$Owner = Repository::getUserByClientId($Candidate_UUID);
$Owner_ID = (int)($Owner['Telegram_ID'] ?? 0);
if ($Owner_ID > 0 && $User_ID > 0 && $Owner_ID !== $User_ID) continue;
}
return $Row;
}

return null;
}

public static function liveUser(array $User): array {
if (self::$Live_Server_Cache === null) {
self::$Live_Server_Cache = ['tid' => [], 'uuid' => [], 'phone' => []];

try {
$Response = ServerClient::listUsers();
$Rows = self::unwrapListRows($Response['Json'] ?? null);

if ($Rows !== [] && ($Response['StatusCode'] ?? 0) < 300) {
foreach ($Rows as $Row) {
if (!is_array($Row)) continue;
$Tid = (int)($Row['telegram_id'] ?? 0);
$Uuid = trim((string)($Row['uuid'] ?? ''));

if ($Tid > 0) self::$Live_Server_Cache['tid'][$Tid] = $Row;
if ($Uuid !== '') self::$Live_Server_Cache['uuid'][$Uuid] = $Row;
if (method_exists('Helper', 'normalizePhone')) {
foreach (['phone', 'Phone', 'comment', 'Comment'] as $Key) {
$Norm = Helper::normalizePhone((string)($Row[$Key] ?? ''));
if ($Norm !== '') {
self::$Live_Server_Cache['phone'][$Norm] = $Row;
break;
}
}
}
}
}
}

catch (Throwable) {
self::$Live_Server_Cache = ['tid' => [], 'uuid' => [], 'phone' => []];
}
}

$Tid = (int)($User['Telegram_ID'] ?? 0);
$Uuid = trim((string)($User['Client_ID'] ?? ''));
$Phone_Norm = method_exists('Helper', 'normalizePhone') ? Helper::normalizePhone((string)($User['Phone'] ?? '')) : '';
$Row = self::$Live_Server_Cache['tid'][$Tid]
?? (self::$Live_Server_Cache['uuid'][$Uuid]
?? ($Phone_Norm !== '' ? (self::$Live_Server_Cache['phone'][$Phone_Norm] ?? null) : null));

if ($Row === null) return $User;

if ($Tid > 0) {
$Row_Uuid = trim((string)($Row['uuid'] ?? ''));
if ($Row_Uuid !== '' && ($Uuid === '' || $Uuid === '_' || $Uuid === $Row_Uuid)) {
if ($Uuid === '' || $Uuid === '_') {
$User['Client_ID'] = $Row_Uuid;
}
return self::syncSubscriptionFromServer($User, $Row);
}
}

$Used = (float)($Row['current_usage_GB'] ?? 0);
$Limit = (float)($Row['usage_limit_GB'] ?? 0);

if ($Limit <= 0) $Limit = (float)($User['Total_Usage_GB'] ?? 0);
$User['Used_Usage_GB'] = round($Used, 3);
$User['Remaining_Usage_GB'] = round(max(0.0, $Limit - $Used), 3);
$User['Percent_Usage'] = $Limit > 0 ? round(($Used / $Limit) * 100, 1) : 0.0;

if ($Limit > 0) $User['Total_Usage_GB'] = $Limit;
$Last_Online = (string)($Row['last_online'] ?? '');

if ($Last_Online !== '' && $Last_Online !== '0001-01-01 00:00:00') {
$User['Last_Online'] = $Last_Online;
}

$Is_Active = !empty($Row['is_active']);
$Is_Enabled = array_key_exists('enable', $Row) ? !empty($Row['enable']) : true;
$User['Server_Is_Active'] = $Is_Active ? 1 : 0;
$User['Server_Enable'] = $Is_Enabled ? 1 : 0;
$User['Client_Status'] = ($Is_Active && $Is_Enabled)
? '✅فعال'
: (((int)($User['Channel_Client_Disabled_At'] ?? 0) > 0) ? '🚫قطع به دلیل عدم عضویت' : '🚫غیر فعال');
return $User;
}

/** Convert the panel's start date and package length into the authoritative expiry fields. */
public static function subscriptionFieldsFromServer(array $Row): array {
$Start_Raw = trim((string)($Row['start_date'] ?? ''));
$Start_Date = substr($Start_Raw, 0, 10);
$Days = (int)($Row['package_days'] ?? 0);
if ($Start_Raw === '' || preg_match('/^\d{4}-\d{2}-\d{2}$/', $Start_Date) !== 1 || $Days <= 0) return [];

try {
$Zone = new DateTimeZone('Asia/Tehran');
$Start = DateTimeImmutable::createFromFormat('!Y-m-d', $Start_Date, $Zone);
$Date_Errors = DateTimeImmutable::getLastErrors();
if (!$Start instanceof DateTimeImmutable || (is_array($Date_Errors) && ($Date_Errors['warning_count'] > 0 || $Date_Errors['error_count'] > 0))) return [];
$End = $Start->modify('+' . $Days . ' days');
if (!$End instanceof DateTimeImmutable) return [];
return [
'Package_Duration' => $Days,
'Package_Start_Date' => Helper::gregorianToJalali($Start->format('Y-m-d')),
'Expiration_Date' => Helper::gregorianToJalali($End->format('Y-m-d')),
'Expiration_Time_Stamp' => $End->getTimestamp(),
];
}
catch (Throwable $Error) {
error_log('[Umbrella-Bot][Subscription-Sync] ' . $Error->getMessage());
return [];
}
}

/** Fetch the current panel record and synchronize profile, status, quota, keys, and dates. */
public static function syncSubscriptionFromServer(array $User, ?array $Server_Row = null): array {
$User_ID = (int)($User['Telegram_ID'] ?? 0);
$Client = trim((string)($User['Client_ID'] ?? ''));
$Discovered = false;

if ($Server_Row === null && ($Client === '' || $Client === '_')) {
$Found_Row = self::discoverPanelRow($User);
if (is_array($Found_Row) && trim((string)($Found_Row['uuid'] ?? '')) !== '') {
$Client = trim((string)$Found_Row['uuid']);
$Server_Row = $Found_Row;
$Discovered = true;
}
}

if ($Client === '' || $Client === '_') return $User;

if ($Server_Row === null) {
try {
$Response = ServerClient::getUser($Client);
$Status = (int)($Response['StatusCode'] ?? 0);
if ($Status === 404) {
$Replacement = self::discoverPanelRow($User);
$Replacement_UUID = is_array($Replacement) ? trim((string)($Replacement['uuid'] ?? '')) : '';
if ($Replacement_UUID !== '' && $Replacement_UUID !== $Client) {
if (class_exists('AppAccountRevocation') && method_exists('AppAccountRevocation', 'revoke')) {
try { AppAccountRevocation::revoke($Client); } catch (Throwable) {}
}
$Client = $Replacement_UUID;
$Server_Row = $Replacement;
$Discovered = true;
} else {
if (class_exists('AppAccountRevocation') && method_exists('AppAccountRevocation', 'revoke')) {
try { AppAccountRevocation::revoke($Client); } catch (Throwable) {}
}
$Clear_Fields = [
'Client_ID' => null,
'Subscription' => null,
'Package_Duration' => null,
'Package_Start_Date' => null,
'Expiration_Date' => null,
'Expiration_Time_Stamp' => null,
'Total_Usage_GB' => null,
'Used_Usage_GB' => null,
'Remaining_Usage_GB' => null,
'Percent_Usage' => null,
'Client_Status' => '🚫حذف شده',
'Server_Is_Active' => 0,
'Server_Enable' => 0,
'Deactivation_Message' => null,
'Channel_Client_Disabled_At' => null,
'Last_Online' => null,
'Server_Comment' => null,
'ED_25519_Private_Key' => null,
'ED_25519_Public_Key' => null,
'WireGuard_Private_Key' => null,
'WireGuard_Public_Key' => null,
'WireGuard_PSK' => null,
];
if ($User_ID > 0) {
$Clear_Changed = [];
foreach ($Clear_Fields as $Key => $Value) {
if (self::fieldChanged($User[$Key] ?? null, $Value)) {
$Clear_Changed[$Key] = $Value;
}
}
if ($Clear_Changed !== []) Repository::updateUser($User_ID, $Clear_Changed);
}
return array_merge($User, $Clear_Fields);
}
} else {
$Server_Row = $Response['Json'] ?? null;
if ($Status < 200 || $Status >= 300 || !is_array($Server_Row)) return $User;
}
}
catch (Throwable $Error) {
error_log('[Umbrella-Bot][Subscription-Sync] ' . $Error->getMessage());
return $User;
}
}

$Server_UUID = trim((string)($Server_Row['uuid'] ?? ''));
if ($Server_UUID !== '' && $Server_UUID !== $Client) return $User;
if ($User_ID <= 0) return $User;

$Fields = [];
if ($Discovered || trim((string)($User['Client_ID'] ?? '')) !== $Client) {
$Fields['Client_ID'] = $Client;
}

$Date_Fields = self::subscriptionFieldsFromServer($Server_Row);
if ($Date_Fields !== []) {
$Fields = array_merge($Fields, $Date_Fields);
}

$Server_Days = (int)($Date_Fields['Package_Duration'] ?? ($Server_Row['package_days'] ?? 0));
if ($Server_Days > 0) {
$Fields['Package_Duration'] = $Server_Days;
$Current_Sub = trim((string)($User['Subscription'] ?? ''));
$Raw_Prev_Days = (string)($User['Package_Duration'] ?? '');
$Norm_Prev_Days = method_exists('Helper', 'toEnglish')
? Helper::toEnglish($Raw_Prev_Days)
: strtr($Raw_Prev_Days, ['۰' => '0', '۱' => '1', '۲' => '2', '۳' => '3', '۴' => '4', '۵' => '5', '۶' => '6', '۷' => '7', '۸' => '8', '۹' => '9']);
$Prev_Days = (int)preg_replace('/[^0-9]/', '', $Norm_Prev_Days);

if ($Current_Sub === '' || ($Prev_Days > 0 && $Prev_Days !== $Server_Days)) {
if (!($Server_Days === 13 && $Current_Sub === 'نوروزی')) {
$Fields['Subscription'] = method_exists('Helper', 'durationLabel')
? Helper::durationLabel($Server_Days)
: ($Server_Days . ' روز');
}
}
}

if (array_key_exists('usage_limit_GB', $Server_Row) || array_key_exists('current_usage_GB', $Server_Row)) {
$Limit = array_key_exists('usage_limit_GB', $Server_Row)
? max(0.0, (float)$Server_Row['usage_limit_GB'])
: max(0.0, (float)($User['Total_Usage_GB'] ?? 0));
$Used = array_key_exists('current_usage_GB', $Server_Row)
? max(0.0, (float)$Server_Row['current_usage_GB'])
: max(0.0, (float)($User['Used_Usage_GB'] ?? 0));
if ($Limit <= 0 && !array_key_exists('usage_limit_GB', $Server_Row)) {
$Limit = (float)($User['Total_Usage_GB'] ?? 0);
}
$Fields['Total_Usage_GB'] = $Limit;
$Fields['Used_Usage_GB'] = round($Used, 3);
$Fields['Remaining_Usage_GB'] = round(max(0.0, $Limit - $Used), 3);
$Fields['Percent_Usage'] = $Limit > 0 ? round(min(100.0, ($Used / $Limit) * 100), 1) : 0.0;
}

if (isset($Server_Row['last_online'])) {
$Last_Online = trim((string)$Server_Row['last_online']);
if ($Last_Online !== '' && $Last_Online !== '0001-01-01 00:00:00') {
$Fields['Last_Online'] = $Last_Online;
}
}

if (array_key_exists('is_active', $Server_Row) || array_key_exists('enable', $Server_Row)) {
$Server_Is_Active = array_key_exists('is_active', $Server_Row)
? (!empty($Server_Row['is_active']) ? 1 : 0)
: (int)($User['Server_Is_Active'] ?? 1);
$Server_Enable = array_key_exists('enable', $Server_Row)
? (!empty($Server_Row['enable']) ? 1 : 0)
: (int)($User['Server_Enable'] ?? 1);
$Fields['Server_Is_Active'] = $Server_Is_Active;
$Fields['Server_Enable'] = $Server_Enable;
if ($Server_Is_Active === 1 && $Server_Enable === 1) {
$Fields['Client_Status'] = '✅فعال';
if (trim((string)($User['Deactivation_Message'] ?? '')) !== '') {
$Fields['Deactivation_Message'] = null;
}
if ((int)($User['Channel_Client_Disabled_At'] ?? 0) > 0) {
$Fields['Channel_Client_Disabled_At'] = null;
}
} else {
$Fields['Client_Status'] = ((int)($User['Channel_Client_Disabled_At'] ?? 0) > 0)
? '🚫قطع به دلیل عدم عضویت'
: '🚫غیر فعال';
}
}

foreach ([
'ed25519_private_key' => 'ED_25519_Private_Key',
'ed25519_public_key' => 'ED_25519_Public_Key',
'wg_pk' => 'WireGuard_Private_Key',
'wg_pub' => 'WireGuard_Public_Key',
'wg_psk' => 'WireGuard_PSK',
] as $Api_Key => $Db_Key) {
if (isset($Server_Row[$Api_Key]) && trim((string)$Server_Row[$Api_Key]) !== '') {
$Fields[$Db_Key] = trim((string)$Server_Row[$Api_Key]);
}
}

$Server_Name_Raw = trim((string)($Server_Row['name'] ?? ''));
if ($Server_Name_Raw !== '' && !self::isPlaceholderName($Server_Name_Raw, $User_ID)) {
$Clean_Name = method_exists('Helper', 'stripZwnj')
? trim((string)(preg_replace('/\s+/u', ' ', Helper::stripZwnj($Server_Name_Raw)) ?? $Server_Name_Raw))
: $Server_Name_Raw;
if ($Clean_Name !== '' && !self::isPlaceholderName($Clean_Name, $User_ID)) {
$Fields['Full_Name'] = $Clean_Name;
}
}

if (array_key_exists('comment', $Server_Row)) {
$Fields['Server_Comment'] = trim((string)$Server_Row['comment']);
}

if (method_exists('Helper', 'normalizePhone') && method_exists('Helper', 'validatePhone')) {
$Phone_Candidate = Helper::normalizePhone(trim((string)($Server_Row['phone'] ?? '')));
if ($Phone_Candidate === '' || !Helper::validatePhone($Phone_Candidate)) {
$Phone_Candidate = Helper::normalizePhone(trim((string)($Server_Row['comment'] ?? '')));
}
if ($Phone_Candidate !== '' && Helper::validatePhone($Phone_Candidate)) {
$Current_Phone = Helper::normalizePhone((string)($User['Phone'] ?? ''));
if ($Current_Phone !== $Phone_Candidate) {
$Phone_Conflict = method_exists('Repository', 'findUserByPhone')
? Repository::findUserByPhone($Phone_Candidate, $User_ID)
: [];
if (empty($Phone_Conflict)) {
$Fields['Phone'] = $Phone_Candidate;
if (method_exists('Helper', 'detectOperator')) {
$Fields['Operator'] = Helper::detectOperator($Phone_Candidate);
}
}
}
}
}

if (method_exists('Repository', 'getSetting') && trim((string)Repository::getSetting('App_Free_Claimed_' . $Client, '')) === '1') {
$Fields['Free_Plan_Claimed'] = 1;
} elseif ((int)($User['Free_Plan_Claimed'] ?? 0) === 1 && method_exists('Repository', 'setSetting')) {
try { Repository::setSetting('App_Free_Claimed_' . $Client, '1'); } catch (Throwable) {}
}

$Changed = [];
foreach ($Fields as $Key => $Value) {
if (self::fieldChanged($User[$Key] ?? null, $Value)) $Changed[$Key] = $Value;
}
if ($Changed !== []) Repository::updateUser($User_ID, $Changed);

$Merged = array_merge($User, $Fields);
if (method_exists('ServerClient', 'updateUser')) {
$Push = [];
if (self::isPlaceholderName($Server_Name_Raw, $User_ID) && trim((string)($Merged['Full_Name'] ?? '')) !== '') {
$Push['name'] = trim((string)$Merged['Full_Name']);
}
if (trim((string)($Server_Row['comment'] ?? '')) === '' && trim((string)($Merged['Phone'] ?? '')) !== '') {
$Push['comment'] = trim((string)$Merged['Phone']);
}
if ((int)($Server_Row['telegram_id'] ?? 0) === 0 && $User_ID > 0 && trim((string)($Merged['Client_ID'] ?? '')) === $Client) {
$Push['telegram_id'] = $User_ID;
}
if ($Push !== []) {
try { ServerClient::updateUser($Client, $Push); } catch (Throwable) {}
}
}

return $Merged;
}

public static function greet(Context $Context, string $Section = 'منوی خدمات ربات'): string {
return Helper::userGreeting($Context, $Section);
}


public static function robotOff(Context $Context, string $Section = 'منوی خدمات ربات'): void {
$Channel_Url = BotConfig::getChannelUrl();

TelegramClient::sendMessage($Context->ChatId, Helper::userGreeting($Context, $Section) . "🪫📴با عرض پوزش ربات در دسترس نمی باشد.\n⚠️علت: 🤖🔴ربات جهت بروز رسانی خاموش می باشد" . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '📢👁مشاهده کانال اطلاع رسانی', 'url' => $Channel_Url]],
]));
}

public static function isRobotOn(): bool {
$Status = Repository::getSetting('Robot_Status', '🟢روشن');

if (!is_string($Status)) {
return false;
}

if (method_exists('Helper', 'repairMojibake')) {
$Status = Helper::repairMojibake($Status);
}

$Trimmed = trim($Status);
$Lower = strtolower($Trimmed);

return !str_contains($Trimmed, 'خاموش') && $Lower !== 'off' && $Lower !== '0' && $Lower !== 'false';
}

public static function offlineText(Context $Context, string $Section = 'منوی خدمات ربات'): string {
return Helper::userGreeting($Context, $Section) . "🪫📴با عرض پوزش ربات در دسترس نمی باشد.\n\n⚠️علت:🤖🔴ربات جهت بروز رسانی خاموش می باشد" . Helper::userFooter();
}

/**
 * دکمه خانه کاربر.
 *
 * منوها از Menu::userHome() استفاده می کنند؛ این تابع برای فراخوان های قدیمی
 * باقی مانده و همان دکمه را برمی گرداند.
 */
public static function mainButton(): array {
return Menu::userHome();
}

/** یک دکمه دلخواه؛ برای دکمه هایی که برچسبشان ثابت نیست. */
public static function backTo(string $Label, string $Call): array {
return [Menu::button($Label, $Call)];
}
}
?>
