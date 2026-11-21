<?php
declare(strict_types=1);

require_once __DIR__ . '/../Database/Database.php';
require_once __DIR__ . '/../Storage/Repository.php';
require_once dirname(__DIR__, 2) . '/Config/Environment.php';

/**
 * The key the app gateway signs OTP hashes and device tokens with.
 *
 * Nobody has to put it in `.env`: the first request that needs it makes one
 * (64 hex characters), stores it in the shared `Settings` table under
 * `App_Gateway_Secret`, and every later request reads the same row, so tokens
 * and pending codes keep working across deploys and restarts.
 *
 * Setting `APP_GATEWAY_SECRET` in `.env` is still honoured for an operator who
 * wants the key outside the database; when it is present it wins and nothing is
 * written to `Settings`.
 */
final class AppSecret {
private const ENV_KEY = 'APP_GATEWAY_SECRET';
private const SETTING_KEY = 'App_Gateway_Secret';
private static ?string $Cached = null;

private function __construct() {
}

/** The secret in use; never empty and never throws. */
public static function get(): string {
if (self::$Cached !== null) {
return self::$Cached;
}

$From_Env = Environment::get(self::ENV_KEY);

if ($From_Env !== '') {
return self::$Cached = $From_Env;
}

try {
$Stored = self::stored();

if ($Stored !== '') {
return self::$Cached = $Stored;
}

// INSERT IGNORE, then read back: if two requests race on the very first
// sign-in, both end up with the row that was written first instead of one
// of them signing a token with a value nobody else knows.
Database::getInstance()->execute(
'INSERT IGNORE INTO `Settings` (`Key`, `Value`) VALUES (?, ?)',
[self::SETTING_KEY, bin2hex(random_bytes(32))]
);
$Stored = self::stored();

if ($Stored !== '') {
return self::$Cached = $Stored;
}
}

catch (Throwable $Error) {
// No database yet (or a locked Settings table): sign with a value derived
// from what the .env does provide, so the process stays deterministic for
// the length of the outage instead of changing keys per request.
error_log('[Umbrella-Bot][App-Secret] falling back to a derived key: ' . $Error->getMessage());
}

return self::$Cached = self::derived();
}

private static function derived(): string {
return hash('sha256', 'umbrella-app-gateway|' . Environment::getBotToken() . '|' . Environment::getDatabaseName());
}

/** Whether the key came from `.env` (an explicit operator choice). */
public static function fromEnvironment(): bool {
return Environment::get(self::ENV_KEY) !== '';
}

/** Whether a key has already been generated and stored in `Settings`. */
public static function stored(): string {
try {
$Value = Repository::getSetting(self::SETTING_KEY, '');
}

catch (Throwable) {
return '';
}

return is_string($Value) ? trim($Value) : '';
}
}
?>
