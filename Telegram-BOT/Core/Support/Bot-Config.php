<?php
declare(strict_types=1);

require_once __DIR__ . '/../Storage/Repository.php';
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

/** The plans the bot sells, keyed by months, exactly as in `PLAN_PRICE_<M>`. */
public const PLAN_MONTHS = [1 => '۱ ماهه', 3 => '۳ ماهه', 6 => '۶ ماهه', 12 => '۱۲ ماهه'];

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

/** Public channel link; the panel's `Channel_Url` wins over `CHANNEL_URL`. */
public static function getChannelUrl(): string {
$Stored = trim((string)Repository::getSetting('Channel_Url', ''));

return $Stored !== '' ? $Stored : Environment::getChannelUrl();
}

public static function setChannelUrl(string $Url): void {
Repository::setSetting('Channel_Url', trim($Url));
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
