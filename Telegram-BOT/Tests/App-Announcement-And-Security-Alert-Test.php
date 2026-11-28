<?php
declare(strict_types=1);

// Behavioral tests for:
// 1. BotConfig app announcement defaults, validation, scheduling & republish version
// 2. AdminFlow app announcement screens & Dispatcher routing
// 3. AppSchema App_Security_Alerts & AppGateway::securityAlert non-spam deduplication

require_once dirname(__DIR__) . '/Bot/Menu.php';
if (!function_exists('mb_strlen')) {
function mb_strlen(string $S): int { return count(preg_split('//u', $S, -1, PREG_SPLIT_NO_EMPTY) ?: []); }
}
if (!function_exists('mb_substr')) {
function mb_substr(string $S, int $Start, ?int $Length = null): string { return implode('', array_slice(preg_split('//u', $S, -1, PREG_SPLIT_NO_EMPTY) ?: [], $Start, $Length)); }
}
if (!function_exists('mb_strtolower')) {
function mb_strtolower(string $S): string { return strtolower($S); }
}

final class Environment {
public static function get(string $Key): string { return ''; }
public static function getRobotVersion(): string { return '1.0.0'; }
public static function showEmergencyConfig(): bool { return false; }
public static function getEmergencyConfigUrl(): string { return ''; }
public static function showNowruzMenu(): bool { return false; }
public static function getCustomDayRate(): float { return 1000; }
public static function getCustomMinDays(): int { return 1; }
public static function getCustomMaxDays(): int { return 365; }
public static function getCustomMinGB(): float { return 1; }
public static function getCustomMaxGB(): float { return 500; }
public static function getSupportUrl(): string { return 'https://t.me/UmbrellaSupport'; }
public static function getChannelUrl(): string { return 'https://t.me/UmbrellaVPN_Channel'; }
public static function getTelegramChannelId(): string { return ''; }
public static function getAdminUserId(): int { return 99; }
public static function getAppGatewaySecret(): string { return 'test-secret-0123456789abcdef'; }
public static function getChannelGraceSeconds(): int { return 3600; }
}

final class Context {
public int $UserId = 99;
public int $ChatId = 99;
public ?int $MessageId = 42;
public ?string $CallbackId = 'cb-1';
public bool $IsCallback = true;
public ?string $CallbackData = '';
public ?string $Photo = null;
public ?string $Caption = null;
public array $Raw = [];
public function __construct(private bool $Admin = true) {}
public function isAdmin(): bool { return $this->Admin; }
public function profileName(): string { return 'مدیر'; }
}

final class Helper {
public static function stripZwnj(string $T): string { return str_replace("\u{200C}", '', $T); }
public static function repairMojibake(string $T): string { return $T; }
public static function digitsToPersian(string $T): string { return $T; }
public static function toPersian(int|float|string $V): string { return (string)$V; }
public static function toEnglish(string $T): string {
return strtr($T, ['۰'=>'0','۱'=>'1','۲'=>'2','۳'=>'3','۴'=>'4','۵'=>'5','۶'=>'6','۷'=>'7','۸'=>'8','۹'=>'9','٠'=>'0','١'=>'1','٢'=>'2','٣'=>'3','٤'=>'4','٥'=>'5','٦'=>'6','٧'=>'7','٨'=>'8','٩'=>'9']);
}
public static function gregorianToJalali(string $G): string { return '۱ دی ۱۴۰۵'; }
public static function formatDateTimeText(string $T): string { return $T; }
public static function formatPersianDate(int $Ts, bool $WithTime = false): string { return gmdate('Y-m-d H:i', $Ts); }
public static function formatPlatform(string $P): string { return $P !== '' ? $P : 'نامشخص'; }
public static function adminGreeting(Context $C, string $Title): string { return "🛡 {$Title}\n"; }
public static function userGreeting(Context $C, string $Title): string { return "{$Title}\n"; }
public static function adminFooter(): string { return ''; }
public static function userFooter(): string { return ''; }
public static function frame(string $A, string $B, string $C, int $Id): string { return "[{$C}]"; }
public static function formatCurrency(float $N): string { return (string)$N; }
public static function formatGB(float $V): string { return (string)$V . ' GB'; }
public static function normalizePhone(string $P): string { return trim($P); }
public static function validatePhone(string $P): bool { return str_starts_with($P, '09'); }
public static function remainingDuration(int $S): string { return (string)$S; }
public static function ticketCategoryLabel(string $V): string { return $V; }
public static function ticketPriorityLabel(string $V): string { return $V; }
public static function formatBytes(int $B): string { return $B . ' B'; }
}

final class Repository {
public static array $Settings = [];
public static array $Users = [];
public static array $Session = [];
public static array $Logs = [];
public static function getSetting(string $K, ?string $Default = ''): ?string {
return array_key_exists($K, self::$Settings) ? (string)self::$Settings[$K] : $Default;
}
public static function setSetting(string $K, string $V): void { self::$Settings[$K] = $V; }
public static function getUser(int $Id): array { return self::$Users[$Id] ?? []; }
public static function getUserSession(int $Id): array { return self::$Session; }
public static function updateUserSession(int $Id, array $V): void { self::$Session = array_replace(self::$Session, $V); }
public static function logAdminAction(int $Admin, string $Action, ?int $Target = null, ?string $Meta = null): void {
self::$Logs[] = [$Admin, $Action, $Target, $Meta];
}
public static function nightlyReportEnabled(int $Id): bool { return true; }
public static function getBlockedUsers(): array { return []; }
public static function openTickets(int $L = 100, int $O = 0): array { return []; }
public static function userTickets(int $Id): array { return []; }
public static function getTicket(int $Id): ?array { return null; }
public static function getTicketMessages(int $Id): array { return []; }
}

final class TelegramClient {
public static array $SentReadable = [];
public static array $SentMessages = [];
public static array $SentPhotos = [];
public static array $LastMarkup = [];
public static string $LastText = '';
public static bool $FailNextReadable = false;
public static ?array $NextDownloadedFile = null;
public static function call(string $Method, array $Args): array { return ['ok' => false]; }
public static function inlineKeyboard(array $Rows): array { return ['inline_keyboard' => $Rows]; }
public static function answerCallbackQuery(?string $Id, string $Text = '', bool $Alert = false): void {}
public static function downloadFile(string $FileId, int $MaxBytes = 4194304): ?array { return self::$NextDownloadedFile; }
public static function sendPhoto(int $ChatId, string $Photo, string $Caption = '', array $Markup = []): array {
self::$SentPhotos[] = [$ChatId, $Photo, $Caption, $Markup];
return ['ok' => true];
}
public static function sendMessage(int $ChatId, string $Text, array $Markup = []): array {
self::$SentMessages[] = [$ChatId, $Text, $Markup];
self::$LastMarkup = $Markup;
self::$LastText = $Text;
return ['ok' => true];
}
public static function editMessageText(int $ChatId, int $MessageId, string $Text, array $Markup = []): array {
self::$LastMarkup = $Markup;
self::$LastText = $Text;
return ['ok' => true];
}
public static function editOrSendMessage(int $ChatId, ?int $MessageId, string $Text, array $Markup = []): array {
self::$LastMarkup = $Markup;
self::$LastText = $Text;
return ['ok' => true];
}
public static function sendReadableMessage(int $ChatId, ?int $MessageId, string $Text, array $Markup = []): bool {
if (self::$FailNextReadable) {
self::$FailNextReadable = false;
return false;
}
self::$SentReadable[] = [$ChatId, $Text, $Markup];
self::$LastMarkup = $Markup;
self::$LastText = $Text;
return true;
}
}

final class Database {
public static array $Devices = [];
public static array $Sessions = [];
public static array $Alerts = [];
public static array $PromoMedia = [];
public static function getInstance(): self { return new self(); }
public function transaction(callable $Fn): mixed { return $Fn($this); }
public function scalar(string $Q, array $P = [], mixed $Default = 0): mixed { return $Default; }
public function fetch(string $Q, array $P = []): ?array {
if (str_contains($Q, 'FROM `App_Promo_Media`')) {
$Key = (string)($P[0] ?? '');
return self::$PromoMedia[$Key] ?? null;
}
if (str_contains($Q, 'FROM `App_Sessions`')) {
foreach (self::$Sessions as $S) {
if (($S['Token_Hash'] ?? '') === ($P[0] ?? '')) return $S;
}
return null;
}
if (str_contains($Q, 'FROM `App_Devices`')) {
foreach (self::$Devices as $D) {
if (($D['Device_ID'] ?? '') === ($P[0] ?? '')) return $D;
}
return null;
}
if (str_contains($Q, 'FROM `App_Security_Alerts`')) {
$Key = ($P[0] ?? '') . '|' . ($P[1] ?? '');
return self::$Alerts[$Key] ?? null;
}
return null;
}
public function fetchAll(string $Q, array $P = []): array { return []; }
public function execute(string $Q, array $P = []): void {
if (str_contains($Q, 'UPDATE `App_Security_Alerts` SET `Resolved` = 1')) {
$Dev = (string)($P[0] ?? '');
if (str_contains($Q, 'Threat_Key` NOT IN')) {
$Keep = array_slice($P, 1);
foreach (self::$Alerts as &$Row) {
if ($Row['Device_ID'] === $Dev && !in_array($Row['Threat_Key'], $Keep, true)) {
$Row['Resolved'] = 1;
}
}
} elseif (str_contains($Q, 'Threat_Key` IN')) {
$Targets = array_slice($P, 1);
foreach (self::$Alerts as &$Row) {
if ($Row['Device_ID'] === $Dev && in_array($Row['Threat_Key'], $Targets, true)) {
$Row['Resolved'] = 1;
}
}
} else {
foreach (self::$Alerts as &$Row) {
if ($Row['Device_ID'] === $Dev) {
$Row['Resolved'] = 1;
}
}
}
return;
}
if (str_contains($Q, 'INSERT INTO `App_Security_Alerts`')) {
[$Dev, $Uuid, $Tg, $Key, $Name, $Cat, $Sev, $Target, $FirstAt, $LastAt] = $P;
$Composite = $Dev . '|' . $Key;
if (!isset(self::$Alerts[$Composite])) {
self::$Alerts[$Composite] = [
'ID' => count(self::$Alerts) + 1,
'Device_ID' => $Dev,
'User_UUID' => $Uuid,
'Telegram_ID' => $Tg,
'Threat_Key' => $Key,
'Threat_Name' => $Name,
'Category' => $Cat,
'Severity' => $Sev,
'Target' => $Target,
'First_Detected_At' => $FirstAt,
'Last_Detected_At' => $LastAt,
'Last_Notified_At' => 0,
'Hit_Count' => 1,
'Resolved' => 0,
];
} else {
self::$Alerts[$Composite]['Threat_Name'] = $Name;
self::$Alerts[$Composite]['Category'] = $Cat;
self::$Alerts[$Composite]['Severity'] = $Sev;
self::$Alerts[$Composite]['Target'] = $Target;
self::$Alerts[$Composite]['Last_Detected_At'] = $LastAt;
self::$Alerts[$Composite]['Hit_Count']++;
self::$Alerts[$Composite]['Resolved'] = 0;
}
return;
}
if (str_contains($Q, 'INSERT INTO `App_Promo_Media`')) {
[$Key, $Mime, $Bytes, $Updated] = $P;
self::$PromoMedia[$Key] = ['Media_Key' => $Key, 'Mime_Type' => $Mime, 'Image_Blob' => $Bytes, 'Updated_At' => $Updated];
return;
}
if (str_contains($Q, 'DELETE FROM `App_Promo_Media`')) {
if ($P === []) {
self::$PromoMedia = [];
} else {
$Keep = (string)$P[0];
foreach (array_keys(self::$PromoMedia) as $K) {
if ($K !== $Keep) unset(self::$PromoMedia[$K]);
}
}
return;
}
if (str_contains($Q, 'UPDATE `App_Security_Alerts` SET `Last_Notified_At` = ?')) {
$Ts = (int)$P[0];
$Dev = (string)$P[1];
$Keys = array_slice($P, 2);
foreach ($Keys as $K) {
$Composite = $Dev . '|' . $K;
if (isset(self::$Alerts[$Composite])) {
self::$Alerts[$Composite]['Last_Notified_At'] = $Ts;
}
}
}
}
}

final class Common {
public static function greet(Context $C, string $S): string { return $S; }
public static function isRobotOn(): bool { return true; }
}
final class ServerClient { public static function getUser(string $Id): array { return ['StatusCode' => 200, 'Json' => []]; } }
final class PanelClient { public static int $LastStatus = 200; public static function get(string $Id): ?array { return null; } public static function lastGetStatus(): int { return self::$LastStatus; } }
final class AppSchema { public static function ensureInstalled(): void {} }
final class AppAccountRevocation { public static function revoke(string $U): void {} }
final class AppDeviceLimit {}
final class AppTwoStep {}
final class AppSecret {}
final class AppBotLink {}
final class BotIdentity {}
final class IppanelClient {}
final class SubscriptionFlow {}
final class Zarinpal {}
final class AppFilter { public const MAX_CUSTOM_DOMAINS = 200; public const DOMAINS_PER_PAGE = 8; public const BOT_CATEGORIES = []; public static function loadGlobal(): array { return []; } public static function summary(array $S): string { return ''; } public static function domainToken(string $D): string { return $D; } }
final class AppBypass {}
final class SystemNotifications { public static function formatForWindowsApp(string $T, string $B, string $L): array { return ['title' => $T, 'body' => $B, 'level' => $L]; } }
final class UserFlow {
public static function serviceMenu(Context $C): void {}
public static function checkChannelMembershipCached(int $Id): bool { return true; }
}
final class ProfileFlow {}
final class AppFlow {}

foreach ([
'Core/Support/Bot-Config.php' => 'BotConfig',
'Bot/Admin.php' => 'AdminFlow',
'Bot/Dispatcher.php' => 'Dispatcher',
'Core/App/App-Gateway.php' => 'AppGateway',
] as $File => $Class) {
$Source = (string)file_get_contents(dirname(__DIR__) . '/' . $File);
$Start = strpos($Source, 'final class ' . $Class . ' {');
if ($Start === false) {
throw new RuntimeException('Missing class ' . $Class);
}
eval(preg_replace('/\?>\s*$/', '', substr($Source, $Start)));
}

$Passed = 0;
function check(bool $Ok, string $Message): void {
global $Passed;
if (!$Ok) {
throw new RuntimeException($Message);
}
$Passed++;
}

// 1. Schema DDL checks
$SchemaApp = (string)file_get_contents(dirname(__DIR__) . '/Core/Database/Schema-App.php');
$SchemaSql = (string)file_get_contents(dirname(__DIR__) . '/Database/Schema.SQL');
check(str_contains($SchemaApp, "'App_Security_Alerts'") && str_contains($SchemaSql, 'CREATE TABLE IF NOT EXISTS `App_Security_Alerts`'), 'App_Security_Alerts exists in Schema-App.php and Schema.SQL');
check(str_contains($SchemaApp, "'App_Promo_Media'") && str_contains($SchemaSql, 'CREATE TABLE IF NOT EXISTS `App_Promo_Media`'), 'App_Promo_Media exists in Schema-App.php and Schema.SQL');

// 2. BotConfig announcement defaults, setters, validation & schedule parsing
$DefaultAnn = BotConfig::getAppAnnouncement();
check($DefaultAnn['enabled'] === true && $DefaultAnn['version'] === 1, 'announcement defaults enabled=true, version=1');
check($DefaultAnn['interval_hours'] === 168 && $DefaultAnn['button_url'] === 'https://t.me/UmbrellaVPN_Channel', 'default interval is 168h and url falls back to channel url');

check(BotConfig::validateAnnouncementUrl('@my_test_chan') === 'https://t.me/my_test_chan', 'normalizes @handle url');
check(BotConfig::validateAnnouncementUrl('t.me/umbrellavpn') === 'https://t.me/umbrellavpn', 'normalizes t.me url');
$UrlFailed = false;
try { BotConfig::validateAnnouncementUrl('not a valid link'); } catch (InvalidArgumentException) { $UrlFailed = true; }
check($UrlFailed, 'rejects invalid announcement url');

check(BotConfig::parseAnnouncementIntervalHours('فقط یک بار') === 0, 'parses once interval as 0');
check(BotConfig::parseAnnouncementIntervalHours('۱۲ ساعت') === 12, 'parses Persian digits hours');
check(BotConfig::parseAnnouncementIntervalHours('3 روز') === 72, 'parses days into hours');
check(BotConfig::parseAnnouncementIntervalHours('2 هفته') === 336, 'parses weeks into hours');

$RefTime = 1795300000;
check(BotConfig::parseAnnouncementStartTime('الان', $RefTime) === 0, 'parses immediate start as 0');
check(BotConfig::parseAnnouncementStartTime('+2 ساعت', $RefTime) === $RefTime + 7200, 'parses +2 hours start offset');
$JalaliTs = BotConfig::parseAnnouncementStartTime('1405/09/15 18:30', $RefTime);
check($JalaliTs > 1790000000, 'parses Jalali date & time to valid Unix timestamp');

$V2 = BotConfig::republishAppAnnouncement();
check($V2 === 2, 'republish increments version');

// 3. AdminFlow screens & Dispatcher routing
$AdminCtx = new Context(true);
$Route = new ReflectionMethod(Dispatcher::class, 'routeCallbackInner');
$AdminCtx->CallbackData = 'admin_app_announcement';
$Route->invoke(null, $AdminCtx);
check(str_contains(TelegramClient::$LastText, 'پنجره اطلاع رسانی در اپلیکیشن'), 'dispatcher opens app announcement menu');
$Btns = array_column(array_merge(...(TelegramClient::$LastMarkup['inline_keyboard'] ?? [[]])), 'callback_data');
check(in_array('admin_ann_toggle', $Btns, true) && in_array('admin_ann_republish', $Btns, true) && in_array('admin_ann_schedule', $Btns, true) && in_array('admin_promo_announcement', $Btns, true), 'announcement menu exposes toggle, republish, schedule, and promotional announcement button');

// 3b. Promotional announcement workflow (image, text, link, repeat schedule, preview, gateway payload)
$DefaultPromo = BotConfig::getPromoAnnouncement();
check($DefaultPromo['enabled'] === false && $DefaultPromo['version'] === 1, 'promo announcement starts disabled at v1');

$AdminCtx->CallbackData = 'admin_promo_announcement';
$Route->invoke(null, $AdminCtx);
check(str_contains(TelegramClient::$LastText, 'اعلان تبلیغاتی'), 'dispatcher opens promo announcement menu');

$AdminCtx->CallbackData = 'admin_promo_toggle';
$Route->invoke(null, $AdminCtx);
check(BotConfig::getPromoAnnouncement()['enabled'] === false, 'empty promo cannot be enabled before setting text or image');

$AdminCtx->CallbackData = 'admin_promo_edit:image';
$Route->invoke(null, $AdminCtx);
check((Repository::$Session['Flow'] ?? '') === 'admin:promo_image', 'edit promo image opens promo_image flow');

TelegramClient::$NextDownloadedFile = ['bytes' => 'FAKEPNGDATA', 'mime' => 'image/png'];
$AdminCtx->IsCallback = false;
$AdminCtx->Photo = 'tg-photo-123';
$AdminCtx->Caption = 'تخفیف ۵۰ درصدی اشتراک ها';
AdminFlow::handleInput($AdminCtx, 'admin:promo_image', '');
$PromoAfterPhoto = BotConfig::getPromoAnnouncement();
check(str_starts_with($PromoAfterPhoto['image_url'], 'app/promo-image?k=') && $PromoAfterPhoto['body'] === 'تخفیف ۵۰ درصدی اشتراک ها', 'promo image upload stores DB media and sets caption when body empty');
$AdminCtx->Photo = null;
$AdminCtx->Caption = null;
$AdminCtx->IsCallback = true;

$AdminCtx->CallbackData = 'admin_promo_edit:btn_url';
$Route->invoke(null, $AdminCtx);
AdminFlow::handleInput($AdminCtx, 'admin:promo_btn_url', '@UmbrellaPromo');
check(BotConfig::getPromoAnnouncement()['button_url'] === 'https://t.me/UmbrellaPromo', 'promo url normalizes @handle');

$AdminCtx->CallbackData = 'admin_promo_interval:12';
$Route->invoke(null, $AdminCtx);
check(BotConfig::getPromoAnnouncement()['interval_hours'] === 12, 'promo quick interval sets 12h');

$AdminCtx->CallbackData = 'admin_promo_toggle';
$Route->invoke(null, $AdminCtx);
check(BotConfig::getPromoAnnouncement()['enabled'] === true, 'promo announcement enables after content is set');

$AdminCtx->CallbackData = 'admin_promo_republish';
$Route->invoke(null, $AdminCtx);
check(BotConfig::getPromoAnnouncement()['version'] === 2, 'promo republish increments version');

$AdminCtx->CallbackData = 'admin_promo_preview';
$Route->invoke(null, $AdminCtx);
check(count(TelegramClient::$SentPhotos) >= 1, 'promo preview sends photo to admin');

$PromoPayloadMethod = new ReflectionMethod(AppGateway::class, 'promoAnnouncementPayload');
$PromoPayload = $PromoPayloadMethod->invoke(null);
check(($PromoPayload['enabled'] ?? false) === true && ($PromoPayload['version'] ?? 0) === 2 && !array_key_exists('image_file_id', $PromoPayload), 'AppGateway::promoAnnouncementPayload returns live promo without internal file_id');

$AdminCtx->CallbackData = 'admin_promo_clear_image';
$Route->invoke(null, $AdminCtx);
check(BotConfig::getPromoAnnouncement()['image_url'] === '' && Database::$PromoMedia === [], 'promo clear image deletes media');

$AdminCtx->CallbackData = 'admin_promo_edit:image';
$Route->invoke(null, $AdminCtx);
AdminFlow::handleInput($AdminCtx, 'admin:promo_image', 'https://cdn.example.com/sale.jpg');
check(BotConfig::getPromoAnnouncement()['image_url'] === 'https://cdn.example.com/sale.jpg', 'promo image accepts direct HTTPS URL');

// Restore default promo disabled state before remaining guest/alert tests
$GuestCtxPromo = new Context(false);
$GuestCtxPromo->CallbackData = 'admin_promo_republish';
$Route->invoke(null, $GuestCtxPromo);
check(BotConfig::getPromoAnnouncement()['version'] === 2, 'non-admin cannot republish promo');

$AdminCtx->CallbackData = 'admin_ann_toggle';
$Route->invoke(null, $AdminCtx);
check(BotConfig::getAppAnnouncement()['enabled'] === false, 'toggle disables app announcement');
$AdminCtx->CallbackData = 'admin_ann_toggle';
$Route->invoke(null, $AdminCtx);
check(BotConfig::getAppAnnouncement()['enabled'] === true, 'second toggle re-enables app announcement');

$AdminCtx->CallbackData = 'admin_ann_edit:title';
$Route->invoke(null, $AdminCtx);
check((Repository::$Session['Flow'] ?? '') === 'admin:ann_title', 'edit title opens ann_title flow');
AdminFlow::handleInput($AdminCtx, 'admin:ann_title', 'اعلان ویژه آمبرلا');
check(BotConfig::getAppAnnouncement()['title'] === 'اعلان ویژه آمبرلا' && Repository::$Session['Flow'] === null, 'ann_title input updates title and clears flow');

$AdminCtx->CallbackData = 'admin_ann_interval:24';
$Route->invoke(null, $AdminCtx);
check(BotConfig::getAppAnnouncement()['interval_hours'] === 24, 'quick interval callback saves 24 hours');

$GuestCtx = new Context(false);
$GuestCtx->CallbackData = 'admin_ann_republish';
$PrevVer = BotConfig::getAppAnnouncement()['version'];
$Route->invoke(null, $GuestCtx);
check(BotConfig::getAppAnnouncement()['version'] === $PrevVer, 'non-admin cannot trigger republish');

// 4. AppGateway::securityAlert anti-spam & Telegram warning delivery
$DeviceId = str_repeat('a', 32);
$Token = 'tok-security-1';
$TokenHash = hash('sha256', $Token);
Database::$Devices[] = [
'ID' => 10,
'Device_ID' => $DeviceId,
'User_UUID' => 'uuid-sec-1',
'Telegram_ID' => 555,
'Device_Name' => 'Workstation-PC',
'Platform' => 'Windows',
'Is_Trusted' => 1,
];
Database::$Sessions[] = [
'Token_Hash' => $TokenHash,
'Device_ID' => $DeviceId,
'User_UUID' => 'uuid-sec-1',
'Telegram_ID' => 555,
'Device_Trusted' => 1,
'Revoked_At' => null,
];
Repository::$Users[555] = [
'Telegram_ID' => 555,
'Chat_ID' => 555,
'Full_Name' => 'سارا محمدی',
];

$ProcessAlert = new ReflectionMethod(AppGateway::class, 'processSecurityAlert');

// If Telegram send fails, Last_Notified_At must remain 0 so it retries next time
TelegramClient::$FailNextReadable = true;
$ResFail = $ProcessAlert->invoke(null, [
'token' => $Token,
'device_id' => $DeviceId,
'threats' => [
['key' => 'vpn:psiphon', 'name' => 'Psiphon', 'category' => 'conflicting_vpn', 'severity' => 'high', 'target' => 'psiphon3.exe'],
],
]);
check($ResFail['stored'] === 1 && $ResFail['notified'] === false, 'failed Telegram send does not claim notified=true');
check((int)(Database::$Alerts[$DeviceId . '|vpn:psiphon']['Last_Notified_At'] ?? -1) === 0, 'failed Telegram send leaves Last_Notified_At=0');

// Next call delivers single Telegram alert and updates Last_Notified_At
$Res1 = $ProcessAlert->invoke(null, [
'token' => $Token,
'device_id' => $DeviceId,
'threats' => [
['key' => 'vpn:psiphon', 'name' => 'Psiphon', 'category' => 'conflicting_vpn', 'severity' => 'high', 'target' => 'psiphon3.exe'],
['key' => 'vpn:jumpjump', 'name' => 'JumpJump VPN', 'category' => 'malware', 'severity' => 'critical', 'target' => 'jumpjump.exe'],
],
]);
check($Res1['stored'] === 2 && $Res1['new_threats'] === 2 && $Res1['notified'] === true, 'new threats trigger one consolidated Telegram alert');
check(count(TelegramClient::$SentReadable) === 1, 'exactly one non-spam Telegram message sent');
check(str_contains(TelegramClient::$SentReadable[0][1], 'Psiphon') && str_contains(TelegramClient::$SentReadable[0][1], 'JumpJump VPN'), 'Telegram message includes detected threats');
check((int)Database::$Alerts[$DeviceId . '|vpn:psiphon']['Last_Notified_At'] > 0, 'Last_Notified_At stamped after successful delivery');

// Repeated scan with same active threats must NOT send duplicate Telegram spam
$Res2 = $ProcessAlert->invoke(null, [
'token' => $Token,
'device_id' => $DeviceId,
'threats' => [
['key' => 'vpn:psiphon', 'name' => 'Psiphon', 'category' => 'conflicting_vpn', 'severity' => 'high', 'target' => 'psiphon3.exe'],
['key' => 'vpn:jumpjump', 'name' => 'JumpJump VPN', 'category' => 'malware', 'severity' => 'critical', 'target' => 'jumpjump.exe'],
],
]);
check($Res2['stored'] === 2 && $Res2['new_threats'] === 0 && $Res2['notified'] === false, 'repeated threats do not spam Telegram');
check(count(TelegramClient::$SentReadable) === 1, 'still only one Telegram message sent');
check((int)Database::$Alerts[$DeviceId . '|vpn:psiphon']['Hit_Count'] === 3, 'Hit_Count incremented cleanly');

// Resolve one threat via sync_all omitting it, then re-detect it => triggers fresh alert
$Res3 = $ProcessAlert->invoke(null, [
'token' => $Token,
'device_id' => $DeviceId,
'sync_all' => true,
'threats' => [
['key' => 'vpn:psiphon', 'name' => 'Psiphon', 'category' => 'conflicting_vpn', 'severity' => 'high', 'target' => 'psiphon3.exe'],
],
]);
check((int)Database::$Alerts[$DeviceId . '|vpn:jumpjump']['Resolved'] === 1, 'sync_all marks removed threat resolved');
check(count(TelegramClient::$SentReadable) === 1, 'no new alert sent on resolution');

$Res4 = $ProcessAlert->invoke(null, [
'token' => $Token,
'device_id' => $DeviceId,
'threats' => [
['key' => 'vpn:jumpjump', 'name' => 'JumpJump VPN', 'category' => 'malware', 'severity' => 'critical', 'target' => 'jumpjump.exe'],
],
]);
check($Res4['new_threats'] === 1 && $Res4['notified'] === true && count(TelegramClient::$SentReadable) === 2, 'reappearing resolved threat notifies user again');

// Neutralized (auto-deleted download / blocked trojan link) triggers immediate user Telegram alert & stays resolved
$Res5 = $ProcessAlert->invoke(null, [
'token' => $Token,
'device_id' => $DeviceId,
'threats' => [],
'neutralized' => [
[
'key' => 'dl:fake_img_trojan',
'name' => 'تروجان پنهان در تصویر (aks.jpg)',
'category' => 'malicious_download',
'severity' => 'critical',
'action' => 'deleted',
'target' => 'C:\\Users\\Test\\Downloads\\aks.jpg',
'detail' => 'فایل با پسوند تصویر حاوی کد اجرایی مخرب بود و خودکار حذف شد.',
],
[
'key' => 'link:grabify.link',
'name' => 'لینک تروجانی مسدود شد (grabify.link)',
'category' => 'malicious_link',
'severity' => 'high',
'action' => 'blocked_connection',
'target' => 'https://grabify.link/ABCD',
'detail' => 'ارتباط با دامنه تروجانی یا فیشینگ در لحظه قطع شد.',
],
[
'key' => 'link:homoglyph:pаypal',
'name' => 'لینک فیشینگ هموگراف مسدود شد',
'category' => 'malicious_link',
'severity' => 'critical',
'action' => 'blocked_url',
'target' => 'https://xn--pypal-4ve.com/login',
'detail' => 'دامنه جعلی هموگراف پیش از باز شدن در مرورگر مسدود شد.',
],
],
'security_status' => 'safe',
'scanned_at_ms' => 1763800009000,
'scanned_files' => 84,
'scanned_apps' => 25,
'scanned_processes' => 42,
]);
check($Res5['neutralized_count'] === 3 && $Res5['notified'] === true, 'neutralized downloads and links notify Telegram user immediately');
check((int)(Database::$Alerts[$DeviceId . '|dl:fake_img_trojan']['Resolved'] ?? 0) === 1, 'auto-deleted file alert stored with Resolved=1');
check((int)(Database::$Alerts[$DeviceId . '|link:grabify.link']['Resolved'] ?? 0) === 1, 'blocked link alert stored with Resolved=1');
check((int)(Database::$Alerts[$DeviceId . '|link:homoglyph:pаypal']['Resolved'] ?? 0) === 1, 'blocked external URL alert stored with Resolved=1');
$SavedShield = json_decode((string)(Repository::$Settings['App_Security_State_' . sha1($DeviceId)] ?? '{}'), true);
check((int)($SavedShield['scanned_files'] ?? 0) === 84, 'storeSecurityDeviceState receives $Body without undefined $Payload crash');
$LastMsg = TelegramClient::$SentReadable[2][1] ?? '';
check(str_contains($LastMsg, 'aks.jpg') && str_contains($LastMsg, 'grabify.link') && str_contains($LastMsg, 'مسدودسازی لینک') && str_contains($LastMsg, 'حذف خودکار'), 'user Telegram alert includes neutralized file, blocked_url link, and auto-delete status');

// Also inspect announcementPayload directly
$AnnPayloadMethod = new ReflectionMethod(AppGateway::class, 'announcementPayload');
$Payload = $AnnPayloadMethod->invoke(null);
check(($Payload['title'] ?? '') === 'اعلان ویژه آمبرلا' && ($Payload['interval_hours'] ?? 0) === 24, 'AppGateway::announcementPayload reflects updated BotConfig');

// Overflow (>8) neutralized alerts format remaining count using Persian digits
$BulkNeutralized = [];
for ($i = 1; $i <= 10; $i++) {
$BulkNeutralized[] = [
'key' => "dl:bulk_{$i}",
'name' => "فایل آلوده {$i}",
'category' => 'malicious_download',
'severity' => 'critical',
'action' => 'deleted',
'target' => "C:\\Users\\Test\\Downloads\\bad{$i}.exe",
'detail' => 'حذف خودکار فایل مخرب',
];
}
$Res6 = $ProcessAlert->invoke(null, [
'token' => $Token,
'device_id' => $DeviceId,
'threats' => [],
'neutralized' => $BulkNeutralized,
]);
check($Res6['neutralized_count'] === 10 && $Res6['notified'] === true, 'bulk neutralized threats (>8) trigger notification');
$BulkMsg = TelegramClient::$SentReadable[count(TelegramClient::$SentReadable) - 1][1] ?? '';
check(str_contains($BulkMsg, '… و ۲ مورد دیگر'), 'overflow count in Telegram security alert uses Persian digits');

echo "OK app announcement & security alert tests ({$Passed} assertions)\n";
