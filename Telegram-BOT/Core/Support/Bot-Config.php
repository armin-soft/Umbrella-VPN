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
}
?>
