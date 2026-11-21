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
}
?>
