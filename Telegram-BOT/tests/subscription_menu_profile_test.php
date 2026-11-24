<?php
declare(strict_types=1);

// Exercise the real UserFlow with isolated Telegram, database and server boundaries.
require_once dirname(__DIR__) . '/Bot/Menu.php';
if (!function_exists('mb_strlen')) {
function mb_strlen(string $text): int { return count(preg_split('//u', $text, -1, PREG_SPLIT_NO_EMPTY) ?: []); }
}
if (!function_exists('mb_substr')) {
function mb_substr(string $text, int $start, ?int $length = null): string { return implode('', array_slice(preg_split('//u', $text, -1, PREG_SPLIT_NO_EMPTY) ?: [], $start, $length)); }
}
set_error_handler(static function (int $severity, string $message, string $file, int $line): never {
throw new ErrorException($message, 0, $severity, $file, $line);
});
final class Context {
public int $UserId = 1, $ChatId = 1;
public ?int $MessageId = 10;
public ?string $CallbackId = 'callback';
public bool $IsCallback = true;
}
final class Repository {
public static array $User = [], $Session = [];
public static function getUser(int $id): array { return self::$User; }
public static function updateUserSession(int $id, array $values): void { self::$Session = array_replace(self::$Session, $values); }
public static function getBalance(int $id): float { return 0; }
}
final class ServerClient {
public static bool $Offline = false;
public static int $Calls = 0;
public static function getUser(string $id): array {
self::$Calls++;
if (self::$Offline) return ['StatusCode' => 503, 'Json' => null];
return ['StatusCode' => 200, 'Json' => ['uuid' => $id, 'is_active' => true, 'enable' => true]];
}
}
final class Common {
public static function greet(Context $context, string $section): string { return $section; }
public static function isRobotOn(): bool { return true; }
public static function liveUser(array $user): array { return $user; }
public static function syncSubscriptionFromServer(array $user, ?array $row = null): array { return $user; }
}
final class Helper {
public static function userFooter(): string { return ''; }
public static function formatCurrency(float $value): string { return (string)$value; }
public static function detectOperator(string $phone): string { return 'test'; }
public static function mention(string $name, ?int $id = null): string { return $name; }
public static function toPersian(string $value): string { return $value; }
public static function translateStatus(string $value): string { return $value; }
public static function formatExpirationShort(int $time): string { return (string)$time; }
}
final class TelegramClient {
public static array $Rows = [];
public static string $Text = '';
public static function inlineKeyboard(array $rows): array { return ['inline_keyboard' => $rows]; }
public static function sendChatAction(int $chat): void {}
public static function answerCallbackQuery(?string $id, string $text, bool $alert = false): void {}
public static function sendMessage(int $chat, string $text, array $markup = []): void { self::$Text = $text; self::$Rows = $markup['inline_keyboard'] ?? []; }
public static function editOrSendMessage(int $chat, ?int $message, string $text, array $markup = []): void { self::sendMessage($chat, $text, $markup); }
}
$source = (string)file_get_contents(dirname(__DIR__) . '/Bot/User.php');
$class = substr($source, strpos($source, 'final class UserFlow {'));
eval((string)preg_replace('/\?>\s*$/', '', $class));
function check(bool $ok, string $message): void { if (!$ok) throw new RuntimeException($message); }
function buttons(): array { return array_column(array_merge(...TelegramClient::$Rows), 'callback_data'); }
$context = new Context();
$now = time();
foreach ([
'no plan' => [],
'no local plan with client ID' => ['Client_ID' => 'client'],
'blank plan' => ['Subscription' => '  '],
'active plan' => ['Client_ID' => 'client', 'Subscription' => 'monthly', 'Expiration_Time_Stamp' => $now + 86400],
'unknown expiry' => ['Client_ID' => 'client', 'Subscription' => 'monthly'],
'paused plan' => ['Client_ID' => 'client', 'Subscription' => 'monthly', 'Expiration_Time_Stamp' => $now + 86400, 'Client_Status' => 'غیرفعال'],
'expired plan' => ['Client_ID' => 'client', 'Subscription' => 'monthly', 'Expiration_Time_Stamp' => $now - 1],
] as $label => $user) {
foreach ([true, false] as $callback) {
foreach ([true, false] as $offline) {
$context->IsCallback = $callback;
ServerClient::$Offline = $offline;
Repository::$User = $user;
ServerClient::$Calls = 0;
Repository::$Session = ['Flow' => 'custom_plan', 'Pending_Payment' => 'keep'];
UserFlow::serviceMenu($context);
$Expected = ['user_subscriptions_menu', 'user_account_menu', 'user_device_menu', 'user_wallet_menu', 'user_stats_menu', 'app_download_menu', 'منوی پشتیبانی', 'تغییرات نسخه'];
check(buttons() === $Expected, $label . ': subscription purchase menu is always available');
check(ServerClient::$Calls === 0, $label . ': service menu performs no extra panel lookup');
check(Menu::problems(TelegramClient::$Rows) === [], $label . ': valid keyboard');
check(Repository::$Session === ['Flow' => null, 'Pending_Payment' => 'keep'], $label . ': payment preserved');
}
}
}
ServerClient::$Offline = false;
foreach ([
['Phone' => '09123456789', 'Full_Name' => 'Test User', 'Subscription' => 'monthly', 'Client_ID' => 'client-123'],
['Phone' => '09123456789', 'Full_Name' => 'Test User', 'Subscription' => 'monthly', 'Client_ID' => '_'],
['Phone' => '09123456789', 'Full_Name' => 'Test User', 'Subscription' => 'monthly', 'Client_ID' => 'client-123', 'ED_25519_Private_Key' => 'key-123+/='],
['Phone' => '09123456789', 'Full_Name' => 'Test User', 'Subscription' => null],
] as $user) {
Repository::$User = $user;
UserFlow::profile($context);
check(TelegramClient::$Text !== '', 'profile rendered without PHP warnings');
check(str_contains(TelegramClient::$Text, 'نام و نام خانوادگی') && str_contains(TelegramClient::$Text, 'شماره موبایل'), 'profile keeps account fields');
check(!str_contains(TelegramClient::$Text, 'شناسه کلاینت') && !str_contains(TelegramClient::$Text, 'client-123'), 'client UUID is not exposed in profile');
check(!str_contains(TelegramClient::$Text, 'کلیدهای اتصال شما'), 'connection keys heading removed from profile');
check(!str_contains(TelegramClient::$Text, 'key-123+/='), 'raw connection keys are omitted from profile');
check(!str_contains(TelegramClient::$Text, 'نوع اشتراک') && !str_contains(TelegramClient::$Text, 'اشتراک فعالی ندارید') && !str_contains(TelegramClient::$Text, '💎*اشتراک:*'), 'my subscription summary block is completely removed from profile');
if (($user['Client_ID'] ?? '') === '_') check(!str_contains(TelegramClient::$Text, '🆔شناسه کلاینت:'), 'missing client ID is not shown in profile');
}
Repository::$User = [
'Phone' => '09123456789', 'Full_Name' => 'Test User', 'Subscription' => 'monthly', 'Client_ID' => 'client-123',
'ED_25519_Private_Key' => '-', 'ED_25519_Public_Key' => '-',
'WireGuard_Private_Key' => '-', 'WireGuard_Public_Key' => '-', 'WireGuard_PSK' => '-',
];
UserFlow::profile($context);
check(!str_contains(TelegramClient::$Text, 'کلیدهای اتصال شما') && !str_contains(TelegramClient::$Text, '💎*اشتراک:*'), 'server placeholder dashes and subscription summary are absent from profile');
Repository::$User = ['Phone' => '09123456789', 'Full_Name' => 'Test User', 'Subscription' => 'monthly', 'Client_ID' => 'client-123', 'WireGuard_Private_Key' => 'private-<key>&'];
UserFlow::profile($context);
check(!str_contains(TelegramClient::$Text, 'کلیدهای اتصال شما') && !str_contains(TelegramClient::$Text, 'private-&lt;key&gt;&amp;') && !str_contains(TelegramClient::$Text, '💎*اشتراک:*'), 'WireGuard keys and subscription summary are omitted from profile');
echo "OK subscription menu and profile\n";
