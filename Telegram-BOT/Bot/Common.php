<?php
declare(strict_types=1);

require_once __DIR__ . '/Context.php';
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

public static function greet(Context $Context, string $Section = 'منوی خدمات ربات'): string {
return Helper::userGreeting($Context, $Section);
}


public static function robotOff(Context $Context, string $Section = 'منوی خدمات ربات'): void {
$Channel_Url = BotConfig::getChannelUrl();

TelegramClient::sendMessage($Context->ChatId, Helper::userGreeting($Context, $Section) . "با عرض پوزش ربات در دسترس نمی باشد.\n⚠️علت:🤖🔴ربات جهت بروز رسانی خاموش می باشد" . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '📢👁مشاهده کانال اطلاع رسانی', 'url' => $Channel_Url]],
]));
}

public static function isRobotOn(): bool {
$Status = Repository::getSetting('Robot_Status', '🟢روشن');
return is_string($Status) && !str_contains($Status, 'خاموش');
}

public static function offlineText(Context $Context, string $Section = 'منوی خدمات ربات'): string {
return Helper::userGreeting($Context, $Section) . "🪫📴با عرض پوزش ربات در دسترس نمی باشد.\n\n⚠️علت:🤖🔴ربات جهت بروز رسانی خاموش می باشد" . Helper::userFooter();
}

public static function mainButton(): array {
return [['text' => '🏠بازگشت به منوی اصلی', 'callback_data' => 'منوی خدمات ربات']];
}

public static function backTo(string $Label, string $Call): array {
return [['text' => $Label, 'callback_data' => $Call]];
}
}
?>