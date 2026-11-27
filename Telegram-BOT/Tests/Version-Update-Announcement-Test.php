<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/Bot/Menu.php';

if (!function_exists('mb_strlen')) {
function mb_strlen(string $S): int {
return count(preg_split('//u', $S, -1, PREG_SPLIT_NO_EMPTY) ?: []);
}
}
if (!function_exists('mb_substr')) {
function mb_substr(string $S, int $Start, ?int $Length = null): string {
return implode('', array_slice(preg_split('//u', $S, -1, PREG_SPLIT_NO_EMPTY) ?: [], $Start, $Length));
}
}
if (!function_exists('mb_strtolower')) {
function mb_strtolower(string $S): string {
return strtolower($S);
}
}
if (!function_exists('mb_strrpos')) {
function mb_strrpos(string $Haystack, string $Needle): int|false {
$Chars = preg_split('//u', $Haystack, -1, PREG_SPLIT_NO_EMPTY) ?: [];
$NeedleChars = preg_split('//u', $Needle, -1, PREG_SPLIT_NO_EMPTY) ?: [];
$NLen = count($NeedleChars);
for ($I = count($Chars) - $NLen; $I >= 0; $I--) {
if (array_slice($Chars, $I, $NLen) === $NeedleChars) return $I;
}
return false;
}
}
if (!class_exists('CURLFile', false)) {
final class CURLFile {
public function __construct(public string $filename) {}
}
}

final class Environment {
public static function get(string $Key, mixed $Default = null): mixed { return $Default ?? ''; }
public static function getBotToken(): string { return 'test-token'; }
public static function getRobotVersion(): string { return '1.0.0'; }
public static function getDateTimeApiUrl(): string { return 'https://date.test/'; }
public static function getDateTimeApiLicense(): string { return 'test-lic'; }
public static function getTelegramChannelId(): string { return '-1001234567890'; }
public static function getSupportUrl(): string { return 'https://t.me/UmbrellaSupport'; }
public static function getChannelUrl(): string { return 'https://t.me/UmbrellaVPN_Channel'; }
public static function getAdminFullName(): string { return 'آرمین اسکندری'; }
public static function getAdminUserId(): int { return 99; }
public static function getSubscriptionLinkBase(): string { return 'https://sub.test/'; }
public static function showEmergencyConfig(): bool { return false; }
public static function getEmergencyConfigUrl(): string { return ''; }
public static function showNowruzMenu(): bool { return false; }
}

final class Context {
public int $UserId = 99;
public int $ChatId = 99;
public ?int $MessageId = 10;
public ?string $CallbackId = null;
public bool $IsCallback = false;
public function isAdmin(): bool { return true; }
public function profileName(): string { return 'آرمین اسکندری'; }
}

final class HttpClient {
public static array $Calls = [];
public static array $PostReplies = [];
public static array $MultipartReplies = [];
public static ?array $DateResponse = null;

public static function get(string $Url, array $Headers = [], int $Timeout = 8): array {
if (self::$DateResponse !== null) return self::$DateResponse;
throw new RuntimeException('offline date service');
}

public static function post(string $Url, array $Payload = []): array {
self::$Calls[] = [basename($Url), $Payload];
$Reply = array_shift(self::$PostReplies);
return ['Json' => $Reply ?? ['ok' => true]];
}

public static function postMultipart(string $Url, array $Fields = []): array {
self::$Calls[] = [basename($Url), $Fields];
$Reply = array_shift(self::$MultipartReplies);
return ['Json' => $Reply ?? ['ok' => true]];
}
}

final class Repository {
public static array $Settings = [];
public static array $Session = [];
public static function getSetting(string $Key, ?string $Default = ''): ?string {
return array_key_exists($Key, self::$Settings) ? (string)self::$Settings[$Key] : $Default;
}
public static function setSetting(string $Key, string $Value): void {
self::$Settings[$Key] = $Value;
}
public static function getUserSession(int $Id): array {
return self::$Session;
}
public static function updateUserSession(int $Id, array $Data): void {
self::$Session = array_replace(self::$Session, $Data);
}
}

final class BotIdentity {
public static function link(): string { return 'https://t.me/UmbrellaVPN_BOT'; }
}

final class Common {
public static function greet(Context $C, string $S): string { return $S . "\n"; }
public static function isRobotOn(): bool { return true; }
}
final class Database {}
final class ServerClient {}
final class PanelClient {}
final class AppSchema {}
final class AppAccountRevocation {}
final class AppDeviceLimit {}
final class AppTwoStep {}
final class AppSecret {}
final class AppBotLink {}
final class IppanelClient {}
final class SubscriptionFlow {}
final class Zarinpal {}
final class AppFilter {}
final class AppBypass {}
final class SystemNotifications {}
final class UserFlow {}
final class ProfileFlow {}
final class AppFlow {}

foreach ([
'Core/Support/Helper.php' => 'Helper',
'Core/Telegram/Telegram.php' => 'TelegramClient',
'Core/Support/Bot-Config.php' => 'BotConfig',
'Bot/Admin.php' => 'AdminFlow',
] as $File => $Class) {
$Source = (string)file_get_contents(dirname(__DIR__) . '/' . $File);
$Start = strpos($Source, 'final class ' . $Class . ' {');
if ($Start === false) {
throw new RuntimeException('Missing class ' . $Class);
}
eval(preg_replace('/\?>\s*$/', '', substr($Source, $Start)));
}

$Assertions = 0;
function check(bool $Condition, string $Message): void {
global $Assertions;
if (!$Condition) {
throw new RuntimeException('FAILED: ' . $Message);
}
$Assertions++;
}

$Context = new Context();

// 1. Offline date fallback via Helper::dateTimeBlock() works without throwing.
$FallbackDate = Helper::dateTimeBlock(1795537283);
check(str_contains($FallbackDate, '📆تاریخ شمسی:') && str_contains($FallbackDate, '🕰زمان:'), 'dateTimeBlock local fallback includes Shamsi and clock');

// 2. Live snapshot/API date payload produces Shamsi + Hijri + Gregorian + Season + Time.
Repository::$Settings = [
'Telegram_Channel_ID' => '-1001234567890',
'Date_Time_Snapshot' => (string)json_encode([
'at' => time(),
'data' => [
'Hijri_Date' => 'سه شنبه ۱۳ جمادی الثانی ۱۴۴۸',
'Season' => 'پاییز',
'Season_Emoji' => '🍂',
'Time_Based' => 'اوایل شب',
'Time_Based_Emoji' => '🌉',
],
], JSON_UNESCAPED_UNICODE),
];

$Changes = "🎉انتشار یکپارچه ویندوز، اندروید و ربات تلگرام فیلترشکن آمبرلا\n\n"
. "🤖ربات تلگرام:\n"
. "💎خرید اشتراک آماده و دلخواه، تمدید خودکار و کیف پول امن زرین پال\n"
. "📦دانلود مستقیم نسخه های رسمی و بتای ویندوز و اندروید\n"
. "🔗اتصال حساب برنامه به ربات، مدیریت دستگاه ها و تیکت با پیوست\n\n"
. "🖥نرم افزار ویندوز:\n"
. "🚀اتصال پرسرعت با حالت خودکار، وایرگارد، آمنزیا، میرو و حالت اضطراری\n"
. "🛡سپر امنیتی همیشه فعال و مسدودسازی خودکار لینک های مخرب\n"
. "🚫کنترل محتوای هوشمند، اشتراک گذاری شبکه با کد QR و بروزرسانی خودکار\n\n"
. "📱اپلیکیشن اندروید:\n"
. "⚡️طراحی هماهنگ با ویندوز، ورود خودکار پیامکی و تونل امن سیستمی\n"
. "🔐پشتیبانی از سپر امنیتی، کنترل محتوا، تفکیک برنامه ها و کیف پول";

Repository::$Session = ['Flow' => 'admin:version_number'];
AdminFlow::versionNumber($Context, '2.0.0');
HttpClient::$Calls = [];
HttpClient::$PostReplies = [['ok' => true]];
HttpClient::$MultipartReplies = [['ok' => true]];
AdminFlow::handleInput($Context, 'admin:version_changes', $Changes . "\n");

check(count(HttpClient::$Calls) === 2, 'admin confirmation and channel photo announcement both sent');

[$AdminMethod, $AdminPayload] = HttpClient::$Calls[0];
check($AdminMethod === 'sendMessage', 'admin confirmation uses sendMessage');
$AdminPlain = html_entity_decode(strip_tags((string)$AdminPayload['text']), ENT_QUOTES | ENT_HTML5, 'UTF-8');
check(str_contains($AdminPlain, '✅ربات با موفقیت به نسخه ۲.۰.۰ بروزرسانی گردید.'), 'admin confirmation uses clean checkmark without stray asterisk');
check(!str_contains($AdminPlain, ' *✅'), 'no stray leading space-asterisk in admin confirmation');

[$ChannelMethod, $ChannelPayload] = HttpClient::$Calls[1];
check($ChannelMethod === 'sendPhoto', 'compact update announcement sends with Logo.png via sendPhoto');
$ChannelHtml = (string)$ChannelPayload['caption'];
$ChannelPlain = html_entity_decode(strip_tags($ChannelHtml), ENT_QUOTES | ENT_HTML5, 'UTF-8');

check(!str_contains($ChannelPlain, 'مدیریت گرامی'), 'channel announcement must not include admin greeting');
check(!str_contains($ChannelPlain, 'خوش آمدید'), 'channel announcement must not include section welcome greeting');
check(!str_contains($ChannelPlain, "\u{200C}"), 'channel announcement must contain zero ZWNJ');
check(!str_ends_with($ChannelPlain, '*'), 'channel announcement must not end with stray asterisk');
check(str_starts_with($ChannelPlain, "✅سلام کاربران گرامی ربات با موفقیت بروز رسانی گردید.\n➖➖➖➖➖➖➖➖➖\n📆تاریخ شمسی:"), 'channel announcement starts with user greeting followed immediately by separator and date block');

$Parts = explode("\n➖➖➖➖➖➖➖➖➖\n", $ChannelPlain);
check(count($Parts) === 3, 'channel announcement has exactly two separators framing the date/time block');
check($Parts[0] === '✅سلام کاربران گرامی ربات با موفقیت بروز رسانی گردید.', 'top line matches exact greeting');
check(
str_contains($Parts[1], '📆تاریخ شمسی:')
&& str_contains($Parts[1], '🕌تاریخ قمری:سه شنبه ۱۳ جمادی الثانی ۱۴۴۸')
&& str_contains($Parts[1], '🌍تاریخ میلادی:')
&& str_contains($Parts[1], "\n\n🌎فصل:🍂پاییز\n🕰زمان:"),
'middle block matches exact Shamsi/Hijri/Gregorian + blank line + Season/Clock layout'
);
check(
str_starts_with($Parts[2], "🔰اطلاعات بروز رسانی جدید بدین شرح است:\n\n🔄نسخه جدید ربات: ۲.۰.۰\n\n🎉انتشار یکپارچه ویندوز، اندروید و ربات تلگرام فیلترشکن آمبرلا"),
'body starts cleanly with update heading, Persian version 2.0.0, and changes'
);

// 3. If sendPhoto fails, channel delivery falls back to sendMessage instead of dropping silently.
Repository::$Session = ['Flow' => 'admin:version_changes'];
HttpClient::$Calls = [];
HttpClient::$PostReplies = [['ok' => true], ['ok' => true]];
HttpClient::$MultipartReplies = [['ok' => false, 'description' => 'Bad Request: MEDIA_CAPTION_TOO_LONG']];
AdminFlow::handleInput($Context, 'admin:version_changes', $Changes);
check(count(HttpClient::$Calls) === 3 && HttpClient::$Calls[2][0] === 'sendMessage', 'failed sendPhoto falls back to sendMessage');
check((int)HttpClient::$Calls[2][1]['chat_id'] === -1001234567890, 'fallback sendMessage targets configured channel');

echo "OK version update announcement tests ({$Assertions} assertions)\n";
