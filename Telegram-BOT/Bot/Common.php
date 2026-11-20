<?php
declare(strict_types=1);

require_once __DIR__ . '/Context.php';
require_once __DIR__ . '/Menu.php';
require_once __DIR__ . '/../Core/Telegram/Telegram.php';
require_once __DIR__ . '/../Core/Server/Umbrella-Server.php';
require_once __DIR__ . '/../Core/Support/Helper.php';
require_once __DIR__ . '/../Core/Support/Bot-Config.php';
require_once __DIR__ . '/../Core/Storage/Repository.php';
require_once __DIR__ . '/../Core/SMS/IPPanel.php';
require_once __DIR__ . '/../Config/Environment.php';

final class Common {
private function __construct() {
}

private static ?array $Live_Server_Cache = null;

public static function liveUser(array $User): array {
if (self::$Live_Server_Cache === null) {
self::$Live_Server_Cache = ['tid' => [], 'uuid' => []];

try {
$Response = ServerClient::listUsers();
$Rows = $Response['Json'] ?? null;

if (is_array($Rows) && ($Response['StatusCode'] ?? 0) < 300) {
foreach ($Rows as $Row) {
if (!is_array($Row)) continue;
$Tid = (int)($Row['telegram_id'] ?? 0);
$Uuid = trim((string)($Row['uuid'] ?? ''));

if ($Tid > 0) self::$Live_Server_Cache['tid'][$Tid] = $Row;
if ($Uuid !== '') self::$Live_Server_Cache['uuid'][$Uuid] = $Row;
}
}
}

catch (Throwable) {
self::$Live_Server_Cache = ['tid' => [], 'uuid' => []];
}
}

$Tid = (int)($User['Telegram_ID'] ?? 0);
$Uuid = trim((string)($User['Client_ID'] ?? ''));
$Row = self::$Live_Server_Cache['tid'][$Tid] ?? (self::$Live_Server_Cache['uuid'][$Uuid] ?? null);

if ($Row === null) return $User;
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

$User['Server_Is_Active'] = !empty($Row['is_active']) ? 1 : 0;
$User['Server_Enable'] = !empty($Row['enable']) ? 1 : 0;
$User['Client_Status'] = !empty($Row['is_active']) ? '✅فعال' : '🚫غیرفعال';
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

/** Fetch the current panel record and persist its subscription dates before rendering. */
public static function syncSubscriptionFromServer(array $User, ?array $Server_Row = null): array {
$Client = trim((string)($User['Client_ID'] ?? ''));
if ($Client === '' || $Client === '_') return $User;

if ($Server_Row === null) {
try {
$Response = ServerClient::getUser($Client);
$Status = (int)($Response['StatusCode'] ?? 0);
$Server_Row = $Response['Json'] ?? null;
if ($Status < 200 || $Status >= 300 || !is_array($Server_Row)) return $User;
}
catch (Throwable $Error) {
error_log('[Umbrella-Bot][Subscription-Sync] ' . $Error->getMessage());
return $User;
}
}

$Server_UUID = trim((string)($Server_Row['uuid'] ?? ''));
if ($Server_UUID !== '' && $Server_UUID !== $Client) return $User;
$Fields = self::subscriptionFieldsFromServer($Server_Row);
if ($Fields === []) return $User;
if (trim((string)($User['Subscription'] ?? '')) === '') {
$Fields['Subscription'] = Helper::durationLabel((int)$Fields['Package_Duration']);
}
$User_ID = (int)($User['Telegram_ID'] ?? 0);
if ($User_ID <= 0) return $User;
$Changed = [];
foreach ($Fields as $Key => $Value) {
if (!array_key_exists($Key, $User) || $User[$Key] != $Value) $Changed[$Key] = $Value;
}
if ($Changed !== []) Repository::updateUser($User_ID, $Changed);
return array_merge($User, $Fields);
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
