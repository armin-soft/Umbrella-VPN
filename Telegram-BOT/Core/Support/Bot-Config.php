<?php
declare(strict_types=1);

require_once __DIR__ . '/../Storage/Repository.php';
require_once __DIR__ . '/Helper.php';
require_once __DIR__ . '/../Telegram/Telegram.php';
require_once dirname(__DIR__, 2) . '/Config/Environment.php';

/**
 * The three settings the admin changes from the bot's «⚙️ تنظیمات ربات» screen:
 * the robot version shown to users, whether the emergency config link is shown,
 * and that link itself.
 *
 * Each value is stored in the shared `Settings` table, and `.env` is only the
 * fallback used before the admin has ever set it. Reading everything through
 * this class keeps the panel the single source of truth: a change applies on
 * the next message, with no redeploy and no edit of `.env`.
 */
final class BotConfig {
public const KEY_VERSION = 'Robot_Version';
public const KEY_EMERGENCY_SHOW = 'Emergency_Show';
public const KEY_EMERGENCY_URL = 'Emergency_URL';
public const KEY_NOWRUZ_MENU = 'Nowruz_Menu_Enabled';

/** The plans the bot sells, keyed by months, exactly as in `PLAN_PRICE_<M>`. */
public const PLAN_MONTHS = [1 => '۱ ماهه', 2 => '۲ ماهه', 3 => '۳ ماهه', 6 => '۶ ماهه', 12 => '۱۲ ماهه'];

private function __construct() {
}

/** Version published to users; `''` when neither the panel nor `.env` has one. */
public static function robotVersion(): string {
$Stored = trim((string)Repository::getSetting(self::KEY_VERSION, ''));

return $Stored !== '' ? $Stored : trim(Environment::getRobotVersion());
}

public static function showEmergency(): bool {
$Stored = Repository::getSetting(self::KEY_EMERGENCY_SHOW, null);

if ($Stored !== null && trim((string)$Stored) !== '') {
return trim((string)$Stored) !== '0';
}

return Environment::showEmergencyConfig();
}

public static function emergencyUrl(): string {
$Stored = trim((string)Repository::getSetting(self::KEY_EMERGENCY_URL, ''));

return $Stored !== '' ? $Stored : Environment::getEmergencyConfigUrl();
}

public static function setRobotVersion(string $Version): void {
Repository::setSetting(self::KEY_VERSION, trim($Version));
}

public static function setShowEmergency(bool $Show): void {
Repository::setSetting(self::KEY_EMERGENCY_SHOW, $Show ? '1' : '0');
}

public static function setEmergencyUrl(string $Url): void {
Repository::setSetting(self::KEY_EMERGENCY_URL, trim($Url));
}

public static function isNowruzMenuConfigured(): bool {
$Stored = Repository::getSetting(self::KEY_NOWRUZ_MENU, null);

if ($Stored !== null && trim((string)$Stored) !== '') {
$Normalized = strtolower(trim((string)$Stored));
return $Normalized === '1' || $Normalized === 'true' || $Normalized === 'on';
}

return method_exists(Environment::class, 'showNowruzMenu') && Environment::showNowruzMenu();
}

/** Menu and gift are available only during the selected Solar Hijri window. */
public static function isNowruzMenuEnabled(?DateTimeImmutable $Now = null): bool {
return self::isNowruzMenuConfigured() && self::isNowruzSeasonActive($Now);
}

public static function isNowruzSeasonActive(?DateTimeImmutable $Now = null): bool {
$Date = self::jalaliDateParts($Now);
return $Date['month'] === 1 && $Date['day'] >= 1 && $Date['day'] <= 13;
}

public static function isNowruzFirstDay(?DateTimeImmutable $Now = null): bool {
$Date = self::jalaliDateParts($Now);
return $Date['month'] === 1 && $Date['day'] === 1;
}

public static function setNowruzMenuEnabled(bool $Show): void {
Repository::setSetting(self::KEY_NOWRUZ_MENU, $Show ? '1' : '0');
}

/** The current Solar Hijri year, used to limit the Nowruz gift to once a year. */
public static function nowruzSeasonKey(?DateTimeImmutable $Now = null): string {
$Date = self::jalaliDateParts($Now);
return (string)$Date['year'];
}

/** @return array{year:int, month:int, day:int} */
private static function jalaliDateParts(?DateTimeImmutable $Now = null): array {
$Zone = new DateTimeZone('Asia/Tehran');
$Date = ($Now ?? new DateTimeImmutable('now', $Zone))->setTimezone($Zone);
$Label = Helper::gregorianToJalali($Date->format('Y-m-d'));
$English = Helper::toEnglish($Label);
$Months = [
'فروردین' => 1, 'اردیبهشت' => 2, 'خرداد' => 3, 'تیر' => 4,
'مرداد' => 5, 'شهریور' => 6, 'مهر' => 7, 'آبان' => 8,
'آذر' => 9, 'دی' => 10, 'بهمن' => 11, 'اسفند' => 12,
];
if (preg_match('/\\s(\\d{1,2})\\s+(فروردین|اردیبهشت|خرداد|تیر|مرداد|شهریور|مهر|آبان|آذر|دی|بهمن|اسفند)\\s+(\\d{4})$/u', $English, $Match) !== 1) {
return ['year' => (int)$Date->format('Y'), 'month' => 0, 'day' => 0];
}
return [
'year' => (int)$Match[3],
'month' => $Months[$Match[2]],
'day' => (int)$Match[1],
];
}

public static function hasClaimedNowruz(int $UserId = 0, string $Uuid = '', ?string $Season = null): bool {
$Year = $Season ?? self::nowruzSeasonKey();

if ($UserId > 0 && trim((string)Repository::getSetting('Nowruz_Claimed_' . $Year . '_u_' . $UserId, '')) === '1') {
return true;
}

$CleanUuid = trim($Uuid);

if ($CleanUuid !== '' && $CleanUuid !== '_' && trim((string)Repository::getSetting('Nowruz_Claimed_' . $Year . '_c_' . $CleanUuid, '')) === '1') {
return true;
}

return false;
}

public static function markNowruzClaimed(int $UserId = 0, string $Uuid = '', ?string $Season = null): void {
$Year = $Season ?? self::nowruzSeasonKey();

if ($UserId > 0) {
Repository::setSetting('Nowruz_Claimed_' . $Year . '_u_' . $UserId, '1');
}

$CleanUuid = trim($Uuid);

if ($CleanUuid !== '' && $CleanUuid !== '_') {
Repository::setSetting('Nowruz_Claimed_' . $Year . '_c_' . $CleanUuid, '1');
}
}

/** Where the value in use came from, for the admin screen. */
public static function source(string $Key): string {
$Stored = trim((string)Repository::getSetting($Key, ''));

return $Stored !== '' ? 'panel' : 'env';
}

// ── subscription prices ────────────────────────────────────────────────────

/** Price of a <months>-month plan; the panel's `Plan_Price_<M>` wins. */
public static function getPlanPrice(int|string $Months): float {
$Stored = trim((string)Repository::getSetting('Plan_Price_' . $Months, ''));
$Price = $Stored !== '' ? (float)$Stored : (float)Environment::get('PLAN_PRICE_' . $Months);

return $Price > 0 ? $Price : 0.0;
}

public static function setPlanPrice(int $Months, float $Price): void {
Repository::setSetting('Plan_Price_' . $Months, (string)max(0, (int)round($Price)));
}

/** Per-day price of the custom plan, derived from the 1-month price. */
public static function getCustomDayRate(): float {
$Month_Price = self::getPlanPrice(1);

return $Month_Price > 0 ? $Month_Price / 30.0 : Environment::getCustomDayRate();
}

// ── custom plan limits ─────────────────────────────────────────────────────

public static function getCustomMinDays(): int {
$Stored = trim((string)Repository::getSetting('Custom_Min_Days', ''));

return $Stored !== '' ? max(1, (int)$Stored) : Environment::getCustomMinDays();
}

public static function getCustomMaxDays(): int {
$Stored = trim((string)Repository::getSetting('Custom_Max_Days', ''));

return $Stored !== '' ? max(1, (int)$Stored) : Environment::getCustomMaxDays();
}

public static function getCustomMinGB(): float {
$Stored = trim((string)Repository::getSetting('Custom_Min_GB', ''));

return $Stored !== '' ? max(0.1, (float)$Stored) : Environment::getCustomMinGB();
}

public static function getCustomMaxGB(): float {
$Stored = trim((string)Repository::getSetting('Custom_Max_GB', ''));

return $Stored !== '' ? max(0.1, (float)$Stored) : Environment::getCustomMaxGB();
}

public static function setCustomMinDays(int $Days): void {
Repository::setSetting('Custom_Min_Days', (string)max(1, $Days));
}

public static function setCustomMaxDays(int $Days): void {
Repository::setSetting('Custom_Max_Days', (string)max(1, $Days));
}

public static function setCustomMinGB(float $GB): void {
Repository::setSetting('Custom_Min_GB', (string)max(0.1, $GB));
}

public static function setCustomMaxGB(float $GB): void {
Repository::setSetting('Custom_Max_GB', (string)max(0.1, $GB));
}

// ── links and channel ─────────────────────────────────────────────────────

/** Support button target; the panel's `Support_Url` wins over `SUPPORT_URL`. */
public static function getSupportUrl(): string {
$Stored = trim((string)Repository::getSetting('Support_Url', ''));

return $Stored !== '' ? $Stored : Environment::getSupportUrl();
}

public static function setSupportUrl(string $Url): void {
Repository::setSetting('Support_Url', trim($Url));
}

public const DEFAULT_CHANNEL_USERNAME = 'UmbrellaVPN_Channel';
public const DEFAULT_CHANNEL_URL = 'https://t.me/UmbrellaVPN_Channel';

/** Public channel link; the panel's `Channel_Url` wins over `CHANNEL_URL`. */
public static function getChannelUrl(): string {
$Stored = trim((string)Repository::getSetting('Channel_Url', ''));
if ($Stored !== '') {
return $Stored;
}
if (class_exists('Environment') && method_exists('Environment', 'getChannelUrl')) {
$Env = trim(Environment::getChannelUrl());
if ($Env !== '') {
return $Env;
}
}
return self::DEFAULT_CHANNEL_URL;
}

public static function setChannelUrl(string $Url): void {
Repository::setSetting('Channel_Url', trim($Url));
}

/** نام کاربری عمومی کانال، نه لینک دعوت یا نام کاربری یک شخص. */
public static function channelUsername(string $Input): string {
$Input = trim($Input);
if (preg_match('~^(?:https?://)?(?:www\.)?t\.me/([A-Za-z][A-Za-z0-9_]{3,31})/?$~i', $Input, $Match)) return $Match[1];
if (preg_match('/^@?([A-Za-z][A-Za-z0-9_]{3,31})$/', $Input, $Match)) return $Match[1];
throw new InvalidArgumentException('نام کاربری عمومی کانال را مانند @UmbrellaVPN_Channel یا https://t.me/UmbrellaVPN_Channel بفرستید.');
}

/** هر دو مقدار فقط پس از پاسخ معتبر getChat و در یک تراکنش ذخیره می شوند. */
public static function configureChannel(string $Input, bool $Force = true): string {
$Username = self::channelUsername($Input);
if (!$Force && strtolower((string)Repository::getSetting('Resolved_Channel_Username', '')) === strtolower($Username)
&& preg_match('/^-100[0-9]+$/', (string)Repository::getSetting('Telegram_Channel_ID', ''))) {
return (string)Repository::getSetting('Telegram_Channel_ID', '');
}
$Response = TelegramClient::call('getChat', ['chat_id' => '@' . $Username]);
$Chat = $Response['result'] ?? [];
$Id = (string)($Chat['id'] ?? '');
if (($Response['ok'] ?? false) !== true || ($Chat['type'] ?? '') !== 'channel'
|| !preg_match('/^-100[0-9]+$/', $Id) || strcasecmp((string)($Chat['username'] ?? ''), $Username) !== 0) {
throw new RuntimeException('شناسه کانال دریافت نشد؛ نام کاربری و دسترسی ربات به کانال را بررسی کنید. تنظیمات قبلی تغییر نکرد.');
}
Database::getInstance()->transaction(static function () use ($Username, $Id): void {
Repository::setSetting('Channel_Url', 'https://t.me/' . $Username);
Repository::setSetting('Telegram_Channel_ID', $Id);
Repository::setSetting('Resolved_Channel_Username', strtolower($Username));
});
return $Id;
}

/** Channel id used for membership checks and notices (numeric, may be negative). */
public static function getTelegramChannelId(): string {
$Stored = trim((string)Repository::getSetting('Telegram_Channel_ID', ''));

return $Stored !== '' ? $Stored : Environment::getTelegramChannelId();
}

public static function setTelegramChannelId(string $Channel_Id): void {
Repository::setSetting('Telegram_Channel_ID', trim($Channel_Id));
}

// ── app inside-dialog announcement ─────────────────────────────────────────

public const KEY_ANN_ENABLED = 'App_Ann_Enabled';
public const KEY_ANN_VERSION = 'App_Ann_Version';
public const KEY_ANN_TITLE = 'App_Ann_Title';
public const KEY_ANN_BODY = 'App_Ann_Body';
public const KEY_ANN_BTN_TEXT = 'App_Ann_Button_Text';
public const KEY_ANN_BTN_URL = 'App_Ann_Button_Url';
public const KEY_ANN_INTERVAL = 'App_Ann_Interval_Hours';
public const KEY_ANN_STARTS_AT = 'App_Ann_Starts_At';
public const KEY_ANN_UPDATED_AT = 'App_Ann_Updated_At';

public const DEFAULT_ANN_TITLE = 'به کانال رسمی آمبرلا بپیوندید';
public const DEFAULT_ANN_BODY = '☂️ فیلترشکن آمبرلا؛ برای دریافت به روز رسانی ها و اخبار، عضو کانال رسمی تلگرام شوید.';
public const DEFAULT_ANN_BTN_TEXT = 'عضویت در کانال رسمی';
public const DEFAULT_ANN_INTERVAL_HOURS = 168;

// ── app promotional announcement (image, text, link, repeat schedule) ───

public const KEY_PROMO_ENABLED = 'App_Promo_Enabled';
public const KEY_PROMO_VERSION = 'App_Promo_Version';
public const KEY_PROMO_TITLE = 'App_Promo_Title';
public const KEY_PROMO_BODY = 'App_Promo_Body';
public const KEY_PROMO_IMAGE_URL = 'App_Promo_Image_Url';
public const KEY_PROMO_IMAGE_FILE_ID = 'App_Promo_Image_File_Id';
public const KEY_PROMO_BTN_TEXT = 'App_Promo_Button_Text';
public const KEY_PROMO_BTN_URL = 'App_Promo_Button_Url';
public const KEY_PROMO_INTERVAL = 'App_Promo_Interval_Hours';
public const KEY_PROMO_STARTS_AT = 'App_Promo_Starts_At';
public const KEY_PROMO_UPDATED_AT = 'App_Promo_Updated_At';

public const DEFAULT_PROMO_TITLE = 'پیشنهاد ویژه آمبرلا';
public const DEFAULT_PROMO_BTN_TEXT = 'مشاهده جزئیات';
public const DEFAULT_PROMO_INTERVAL_HOURS = 24;

/** @return array{enabled:bool,version:int,title:string,body:string,button_text:string,button_url:string,interval_hours:int,starts_at:int,updated_at:int} */
public static function getAppAnnouncement(): array {
$Enabled_Raw = Repository::getSetting(self::KEY_ANN_ENABLED, null);
$Enabled = true;
if ($Enabled_Raw !== null && trim((string)$Enabled_Raw) !== '') {
$Norm = strtolower(trim((string)$Enabled_Raw));
$Enabled = !in_array($Norm, ['0', 'false', 'off', 'no'], true);
}

$Version = max(1, (int)trim((string)Repository::getSetting(self::KEY_ANN_VERSION, '1')));

$Title = trim((string)Repository::getSetting(self::KEY_ANN_TITLE, ''));
if ($Title === '') {
$Title = self::DEFAULT_ANN_TITLE;
}

$Body = trim((string)Repository::getSetting(self::KEY_ANN_BODY, ''));
if ($Body === '') {
$Body = self::DEFAULT_ANN_BODY;
}

$Button_Text = trim((string)Repository::getSetting(self::KEY_ANN_BTN_TEXT, ''));
if ($Button_Text === '') {
$Button_Text = self::DEFAULT_ANN_BTN_TEXT;
}

$Button_Url = trim((string)Repository::getSetting(self::KEY_ANN_BTN_URL, ''));
if ($Button_Url === '') {
$Button_Url = self::getChannelUrl();
}

$Interval_Raw = Repository::getSetting(self::KEY_ANN_INTERVAL, null);
$Interval_Hours = self::DEFAULT_ANN_INTERVAL_HOURS;
if ($Interval_Raw !== null && trim((string)$Interval_Raw) !== '') {
$Interval_Hours = max(0, min(8760, (int)trim((string)$Interval_Raw)));
}

$Starts_At = max(0, (int)trim((string)Repository::getSetting(self::KEY_ANN_STARTS_AT, '0')));
$Updated_At = max(0, (int)trim((string)Repository::getSetting(self::KEY_ANN_UPDATED_AT, '0')));

return [
'enabled' => $Enabled,
'version' => $Version,
'title' => Helper::stripZwnj($Title),
'body' => Helper::stripZwnj($Body),
'button_text' => Helper::stripZwnj($Button_Text),
'button_url' => $Button_Url,
'interval_hours' => $Interval_Hours,
'starts_at' => $Starts_At,
'updated_at' => $Updated_At,
];
}

private static function touchAppAnnouncementUpdatedAt(): void {
Repository::setSetting(self::KEY_ANN_UPDATED_AT, (string)time());
}

public static function setAppAnnouncementEnabled(bool $Enabled): void {
Repository::setSetting(self::KEY_ANN_ENABLED, $Enabled ? '1' : '0');
self::touchAppAnnouncementUpdatedAt();
}

public static function setAppAnnouncementTitle(string $Title): void {
$Clean = mb_substr(trim(Helper::stripZwnj($Title)), 0, 140);
Repository::setSetting(self::KEY_ANN_TITLE, $Clean);
self::touchAppAnnouncementUpdatedAt();
}

public static function setAppAnnouncementBody(string $Body): void {
$Clean = mb_substr(trim(Helper::stripZwnj($Body)), 0, 1200);
Repository::setSetting(self::KEY_ANN_BODY, $Clean);
self::touchAppAnnouncementUpdatedAt();
}

public static function setAppAnnouncementButtonText(string $Text): void {
$Clean = mb_substr(trim(Helper::stripZwnj($Text)), 0, 80);
Repository::setSetting(self::KEY_ANN_BTN_TEXT, $Clean);
self::touchAppAnnouncementUpdatedAt();
}

public static function setAppAnnouncementButtonUrl(string $Url): void {
$Normalized = self::validateAnnouncementUrl($Url);
Repository::setSetting(self::KEY_ANN_BTN_URL, $Normalized);
self::touchAppAnnouncementUpdatedAt();
}

public static function setAppAnnouncementIntervalHours(int $Hours): void {
$Bounded = max(0, min(8760, $Hours));
Repository::setSetting(self::KEY_ANN_INTERVAL, (string)$Bounded);
self::touchAppAnnouncementUpdatedAt();
}

public static function setAppAnnouncementStartsAt(int $Timestamp): void {
Repository::setSetting(self::KEY_ANN_STARTS_AT, (string)max(0, $Timestamp));
self::touchAppAnnouncementUpdatedAt();
}

public static function republishAppAnnouncement(): int {
$Current = max(1, (int)trim((string)Repository::getSetting(self::KEY_ANN_VERSION, '1')));
$Next = $Current + 1;
Repository::setSetting(self::KEY_ANN_VERSION, (string)$Next);
self::touchAppAnnouncementUpdatedAt();
return $Next;
}

public static function resetAppAnnouncementToDefaults(): void {
foreach ([
self::KEY_ANN_TITLE,
self::KEY_ANN_BODY,
self::KEY_ANN_BTN_TEXT,
self::KEY_ANN_BTN_URL,
] as $Key) {
Repository::setSetting($Key, '');
}
Repository::setSetting(self::KEY_ANN_INTERVAL, (string)self::DEFAULT_ANN_INTERVAL_HOURS);
Repository::setSetting(self::KEY_ANN_STARTS_AT, '0');
self::republishAppAnnouncement();
}

/** @return array{enabled:bool,version:int,title:string,body:string,image_url:string,image_file_id:string,button_text:string,button_url:string,interval_hours:int,starts_at:int,updated_at:int} */
public static function getPromoAnnouncement(): array {
$Enabled_Raw = Repository::getSetting(self::KEY_PROMO_ENABLED, null);
$Enabled = false;
if ($Enabled_Raw !== null && trim((string)$Enabled_Raw) !== '') {
$Norm = strtolower(trim((string)$Enabled_Raw));
$Enabled = in_array($Norm, ['1', 'true', 'on', 'yes'], true);
}

$Version = max(1, (int)trim((string)Repository::getSetting(self::KEY_PROMO_VERSION, '1')));

$Title = trim((string)Repository::getSetting(self::KEY_PROMO_TITLE, ''));
if ($Title === '') {
$Title = self::DEFAULT_PROMO_TITLE;
}

$Body = trim((string)Repository::getSetting(self::KEY_PROMO_BODY, ''));
$Image_Url = trim((string)Repository::getSetting(self::KEY_PROMO_IMAGE_URL, ''));
$Image_File_Id = trim((string)Repository::getSetting(self::KEY_PROMO_IMAGE_FILE_ID, ''));

$Button_Text = trim((string)Repository::getSetting(self::KEY_PROMO_BTN_TEXT, ''));
if ($Button_Text === '') {
$Button_Text = self::DEFAULT_PROMO_BTN_TEXT;
}

$Button_Url = trim((string)Repository::getSetting(self::KEY_PROMO_BTN_URL, ''));

$Interval_Raw = Repository::getSetting(self::KEY_PROMO_INTERVAL, null);
$Interval_Hours = self::DEFAULT_PROMO_INTERVAL_HOURS;
if ($Interval_Raw !== null && trim((string)$Interval_Raw) !== '') {
$Interval_Hours = max(0, min(8760, (int)trim((string)$Interval_Raw)));
}

$Starts_At = max(0, (int)trim((string)Repository::getSetting(self::KEY_PROMO_STARTS_AT, '0')));
$Updated_At = max(0, (int)trim((string)Repository::getSetting(self::KEY_PROMO_UPDATED_AT, '0')));

return [
'enabled' => $Enabled,
'version' => $Version,
'title' => Helper::stripZwnj($Title),
'body' => Helper::stripZwnj($Body),
'image_url' => $Image_Url,
'image_file_id' => $Image_File_Id,
'button_text' => Helper::stripZwnj($Button_Text),
'button_url' => $Button_Url,
'interval_hours' => $Interval_Hours,
'starts_at' => $Starts_At,
'updated_at' => $Updated_At,
];
}

private static function touchPromoAnnouncementUpdatedAt(): void {
Repository::setSetting(self::KEY_PROMO_UPDATED_AT, (string)time());
}

public static function setPromoAnnouncementEnabled(bool $Enabled): void {
Repository::setSetting(self::KEY_PROMO_ENABLED, $Enabled ? '1' : '0');
self::touchPromoAnnouncementUpdatedAt();
}

public static function setPromoAnnouncementTitle(string $Title): void {
$Clean = mb_substr(trim(Helper::stripZwnj($Title)), 0, 140);
Repository::setSetting(self::KEY_PROMO_TITLE, $Clean);
self::touchPromoAnnouncementUpdatedAt();
}

public static function setPromoAnnouncementBody(string $Body): void {
$Clean = mb_substr(trim(Helper::stripZwnj($Body)), 0, 1200);
Repository::setSetting(self::KEY_PROMO_BODY, $Clean);
self::touchPromoAnnouncementUpdatedAt();
}

public static function setPromoAnnouncementButtonText(string $Text): void {
$Clean = mb_substr(trim(Helper::stripZwnj($Text)), 0, 80);
Repository::setSetting(self::KEY_PROMO_BTN_TEXT, $Clean);
self::touchPromoAnnouncementUpdatedAt();
}

public static function setPromoAnnouncementButtonUrl(string $Url): void {
$Normalized = self::validateAnnouncementUrl($Url);
Repository::setSetting(self::KEY_PROMO_BTN_URL, $Normalized);
self::touchPromoAnnouncementUpdatedAt();
}

public static function clearPromoAnnouncementButtonUrl(): void {
Repository::setSetting(self::KEY_PROMO_BTN_URL, '');
self::touchPromoAnnouncementUpdatedAt();
}

public static function validatePromoImageUrl(string $Input): string {
$Raw = trim($Input);
if ($Raw === '') {
throw new InvalidArgumentException('لینک عکس تبلیغاتی نمی تواند خالی باشد.');
}
if (!preg_match('~^https?://[^\s<>"]+$~i', $Raw)) {
throw new InvalidArgumentException('لینک عکس باید با https:// یا http:// شروع شود.');
}
$Parts = parse_url($Raw);
$Scheme = strtolower((string)($Parts['scheme'] ?? ''));
$Host = strtolower(trim((string)($Parts['host'] ?? '')));
if (!in_array($Scheme, ['http', 'https'], true) || $Host === '' || !str_contains($Host, '.')) {
throw new InvalidArgumentException('نشانی اینترنتی تصویر معتبر نیست.');
}
if (in_array($Host, ['localhost', '127.0.0.1', '0.0.0.0'], true) || mb_strlen($Raw) > 512) {
throw new InvalidArgumentException('نشانی تصویر معتبر نیست یا بیش از حد طولانی است.');
}
return $Raw;
}

public static function setPromoImageUrl(string $Url, string $FileId = ''): void {
$Normalized = self::validatePromoImageUrl($Url);
Repository::setSetting(self::KEY_PROMO_IMAGE_URL, $Normalized);
Repository::setSetting(self::KEY_PROMO_IMAGE_FILE_ID, trim($FileId));
self::cleanupUnusedPromoMedia('');
self::touchPromoAnnouncementUpdatedAt();
}

public static function savePromoImageBinary(string $Bytes, string $MimeType, string $FileId = ''): string {
$Len = strlen($Bytes);
if ($Len <= 0 || $Len > 4194304) {
throw new InvalidArgumentException('حجم تصویر باید کمتر از ۴ مگابایت باشد.');
}
$CleanMime = strtolower(trim($MimeType));
if (!in_array($CleanMime, ['image/jpeg', 'image/png', 'image/webp', 'image/gif'], true)) {
throw new InvalidArgumentException('فرمت تصویر باید JPG، PNG، WEBP یا GIF باشد.');
}
$MediaKey = bin2hex(random_bytes(12));
$Now = time();
if (class_exists('Database')) {
Database::getInstance()->execute(
'INSERT INTO `App_Promo_Media` (`Media_Key`, `Mime_Type`, `Image_Blob`, `Updated_At`) VALUES (?, ?, ?, ?) '
. 'ON DUPLICATE KEY UPDATE `Mime_Type` = VALUES(`Mime_Type`), `Image_Blob` = VALUES(`Image_Blob`), `Updated_At` = VALUES(`Updated_At`)',
[$MediaKey, $CleanMime, $Bytes, $Now]
);
}
self::cleanupUnusedPromoMedia($MediaKey);
Repository::setSetting(self::KEY_PROMO_IMAGE_URL, 'app/promo-image?k=' . $MediaKey);
Repository::setSetting(self::KEY_PROMO_IMAGE_FILE_ID, trim($FileId));
self::touchPromoAnnouncementUpdatedAt();
return $MediaKey;
}

/** @return array{mime:string,bytes:string,updated_at:int}|null */
public static function getPromoImageMedia(string $MediaKey): ?array {
$CleanKey = strtolower(trim($MediaKey));
if (!preg_match('/^[a-f0-9]{16,64}$/', $CleanKey) || !class_exists('Database')) {
return null;
}
$Row = Database::getInstance()->fetch(
'SELECT `Mime_Type`, `Image_Blob`, `Updated_At` FROM `App_Promo_Media` WHERE `Media_Key` = ? LIMIT 1',
[$CleanKey]
);
if (!is_array($Row) || empty($Row['Image_Blob'])) {
return null;
}
return [
'mime' => (string)($Row['Mime_Type'] ?? 'image/jpeg'),
'bytes' => (string)$Row['Image_Blob'],
'updated_at' => (int)($Row['Updated_At'] ?? 0),
];
}

public static function clearPromoImage(): void {
Repository::setSetting(self::KEY_PROMO_IMAGE_URL, '');
Repository::setSetting(self::KEY_PROMO_IMAGE_FILE_ID, '');
self::cleanupUnusedPromoMedia('');
self::touchPromoAnnouncementUpdatedAt();
}

private static function cleanupUnusedPromoMedia(string $KeepKey): void {
if (!class_exists('Database')) return;
try {
if ($KeepKey !== '') {
Database::getInstance()->execute('DELETE FROM `App_Promo_Media` WHERE `Media_Key` <> ?', [$KeepKey]);
} else {
Database::getInstance()->execute('DELETE FROM `App_Promo_Media`', []);
}
} catch (Throwable) {}
}

public static function setPromoAnnouncementIntervalHours(int $Hours): void {
$Bounded = max(0, min(8760, $Hours));
Repository::setSetting(self::KEY_PROMO_INTERVAL, (string)$Bounded);
self::touchPromoAnnouncementUpdatedAt();
}

public static function setPromoAnnouncementStartsAt(int $Timestamp): void {
Repository::setSetting(self::KEY_PROMO_STARTS_AT, (string)max(0, $Timestamp));
self::touchPromoAnnouncementUpdatedAt();
}

public static function republishPromoAnnouncement(): int {
$Current = max(1, (int)trim((string)Repository::getSetting(self::KEY_PROMO_VERSION, '1')));
$Next = $Current + 1;
Repository::setSetting(self::KEY_PROMO_VERSION, (string)$Next);
self::touchPromoAnnouncementUpdatedAt();
return $Next;
}

public static function resetPromoAnnouncementToDefaults(): void {
foreach ([
self::KEY_PROMO_TITLE,
self::KEY_PROMO_BODY,
self::KEY_PROMO_IMAGE_URL,
self::KEY_PROMO_IMAGE_FILE_ID,
self::KEY_PROMO_BTN_TEXT,
self::KEY_PROMO_BTN_URL,
] as $Key) {
Repository::setSetting($Key, '');
}
self::cleanupUnusedPromoMedia('');
Repository::setSetting(self::KEY_PROMO_ENABLED, '0');
Repository::setSetting(self::KEY_PROMO_INTERVAL, (string)self::DEFAULT_PROMO_INTERVAL_HOURS);
Repository::setSetting(self::KEY_PROMO_STARTS_AT, '0');
self::republishPromoAnnouncement();
}

public static function validateAnnouncementUrl(string $Input): string {
$Raw = trim($Input);
if ($Raw === '') {
throw new InvalidArgumentException('لینک دکمه نمی تواند خالی باشد.');
}
if (str_starts_with($Raw, '@')) {
$Handle = substr($Raw, 1);
if (!preg_match('/^[A-Za-z][A-Za-z0-9_]{3,63}$/', $Handle)) {
throw new InvalidArgumentException('نام کاربری کانال یا ربات معتبر نیست.');
}
return 'https://t.me/' . $Handle;
}
if (preg_match('~^(?:www\.)?t\.me/[^\s<>]+$~i', $Raw)) {
return 'https://' . ltrim($Raw, '/');
}
if (preg_match('#^(?:https?|tg)://[^\s<>]+$#i', $Raw)) {
return $Raw;
}
throw new InvalidArgumentException('لینک باید با https://، @ یا t.me/ شروع شود.');
}

public static function parseAnnouncementIntervalHours(string $Input): int {
$Clean = mb_strtolower(trim(Helper::toEnglish(Helper::stripZwnj($Input))));
$Clean = str_replace(['،', ',', '٬'], ' ', $Clean);
$Clean = (string)preg_replace('/\s+/u', ' ', $Clean);
if ($Clean === '' || in_array($Clean, ['0', 'once', 'یکبار', 'یک بار', 'فقط یکبار', 'فقط یک بار', 'بدون تکرار'], true)) {
return 0;
}
if (preg_match('/^(\d{1,4})\s*(?:ساعت|h|hr|hrs|hour|hours)?$/u', $Clean, $M)) {
$Hours = (int)$M[1];
if ($Hours < 0 || $Hours > 8760) {
throw new InvalidArgumentException('بازه تکرار باید بین ۰ تا ۸۷۶۰ ساعت باشد.');
}
return $Hours;
}
if (preg_match('/^(\d{1,3})\s*(?:روز|d|day|days)$/u', $Clean, $M)) {
$Hours = (int)$M[1] * 24;
if ($Hours < 0 || $Hours > 8760) {
throw new InvalidArgumentException('بازه تکرار باید بین ۰ تا ۳۶۵ روز باشد.');
}
return $Hours;
}
if (preg_match('/^(\d{1,2})\s*(?:هفته|w|week|weeks)$/u', $Clean, $M)) {
$Hours = (int)$M[1] * 168;
if ($Hours < 0 || $Hours > 8760) {
throw new InvalidArgumentException('بازه تکرار باید حداکثر ۵۲ هفته باشد.');
}
return $Hours;
}
throw new InvalidArgumentException('فرمت بازه معتبر نیست؛ مثلاً 0 (فقط یک بار)، 24 (ساعت) یا «3 روز» وارد کنید.');
}

public static function parseAnnouncementStartTime(string $Input, ?int $Now = null): int {
$Ref = $Now ?? time();
$Clean = mb_strtolower(trim(Helper::toEnglish(Helper::stripZwnj($Input))));
$Clean = str_replace(['،', ','], ' ', $Clean);
$Clean = (string)preg_replace('/\s+/u', ' ', $Clean);

if ($Clean === '' || in_array($Clean, ['0', 'now', 'الان', 'فوری', 'هم اکنون', 'همین الان', 'بی درنگ'], true)) {
return 0;
}
if (preg_match('/^\+?\s*(\d{1,4})\s*(?:دقیقه|دقيقه|m|min|mins|minute|minutes)$/u', $Clean, $M)) {
return $Ref + ((int)$M[1] * 60);
}
if (preg_match('/^\+?\s*(\d{1,4})\s*(?:ساعت|h|hr|hrs|hour|hours)$/u', $Clean, $M)) {
return $Ref + ((int)$M[1] * 3600);
}
if (preg_match('/^\+?\s*(\d{1,3})\s*(?:روز|d|day|days)$/u', $Clean, $M)) {
return $Ref + ((int)$M[1] * 86400);
}

$Zone = new DateTimeZone('Asia/Tehran');
if (preg_match('/^(\d{4})[\/\-](\d{1,2})[\/\-](\d{1,2})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$/', $Clean, $M)) {
$Y = (int)$M[1];
$Mo = (int)$M[2];
$D = (int)$M[3];
$H = isset($M[4]) ? (int)$M[4] : 0;
$Mi = isset($M[5]) ? (int)$M[5] : 0;
$S = isset($M[6]) ? (int)$M[6] : 0;
if ($H > 23 || $Mi > 59 || $S > 59 || $Mo < 1 || $Mo > 12 || $D < 1 || $D > 31) {
throw new InvalidArgumentException('تاریخ یا ساعت وارد شده معتبر نیست.');
}
if ($Y >= 1300 && $Y <= 1599) {
[$Y, $Mo, $D] = self::jalaliToGregorian($Y, $Mo, $D);
} elseif (!checkdate($Mo, $D, $Y)) {
throw new InvalidArgumentException('تاریخ میلادی معتبر نیست.');
}
$Dt = (new DateTimeImmutable('now', $Zone))->setDate($Y, $Mo, $D)->setTime($H, $Mi, $S);
return $Dt->getTimestamp();
}

if (preg_match('/^(\d{1,2}):(\d{2})$/', $Clean, $M)) {
$H = (int)$M[1];
$Mi = (int)$M[2];
if ($H > 23 || $Mi > 59) {
throw new InvalidArgumentException('ساعت باید بین 00:00 تا 23:59 باشد.');
}
$Dt = (new DateTimeImmutable('@' . $Ref))->setTimezone($Zone)->setTime($H, $Mi, 0);
if ($Dt->getTimestamp() <= $Ref) {
$Dt = $Dt->modify('+1 day');
}
return $Dt->getTimestamp();
}

throw new InvalidArgumentException('فرمت زمان شروع معتبر نیست؛ مثلاً «الان»، «+2 ساعت»، «18:30» یا «1405/09/15 18:00» بفرستید.');
}

/** @return array{0:int,1:int,2:int} */
private static function jalaliToGregorian(int $Jy, int $Jm, int $Jd): array {
$Jy += 1595;
$Days = -355668 + (365 * $Jy) + (((int)($Jy / 33)) * 8) + ((int)((($Jy % 33) + 3) / 4)) + $Jd
+ (($Jm < 7) ? ($Jm - 1) * 31 : (($Jm - 7) * 30) + 186);
$Gy = 400 * ((int)($Days / 146097));
$Days %= 146097;
if ($Days > 36524) {
$Gy += 100 * ((int)(--$Days / 36524));
$Days %= 36524;
if ($Days >= 365) {
$Days++;
}
}
$Gy += 4 * ((int)($Days / 1461));
$Days %= 1461;
if ($Days > 365) {
$Gy += (int)(($Days - 1) / 365);
$Days = ($Days - 1) % 365;
}
$Gd = $Days + 1;
$SalA = [0, 31, (($Gy % 4 === 0 && $Gy % 100 !== 0) || ($Gy % 400 === 0)) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
$Gm = 0;
while ($Gm < 13 && $Gd > $SalA[$Gm]) {
$Gd -= $SalA[$Gm];
$Gm++;
}
return [$Gy, $Gm, $Gd];
}

public static function formatAnnouncementIntervalLabel(int $Hours): string {
if ($Hours <= 0) {
return 'فقط یک بار (بدون تکرار)';
}
if ($Hours % 168 === 0) {
$Weeks = (int)($Hours / 168);
return 'هر ' . Helper::toPersian((string)$Weeks) . ' هفته';
}
if ($Hours % 24 === 0) {
$Days = (int)($Hours / 24);
return 'هر ' . Helper::toPersian((string)$Days) . ' روز';
}
return 'هر ' . Helper::toPersian((string)$Hours) . ' ساعت';
}
}
?>
