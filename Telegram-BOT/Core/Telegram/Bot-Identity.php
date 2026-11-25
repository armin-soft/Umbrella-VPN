<?php
declare(strict_types=1);

require_once __DIR__ . '/../Database/Database.php';
require_once __DIR__ . '/../Storage/Repository.php';
require_once __DIR__ . '/Telegram.php';
require_once dirname(__DIR__, 2) . '/Config/Environment.php';

/**
 * The bot's own @username, read from Telegram instead of `.env`.
 *
 * Every place that needs the bot link (the payment callback, the plain visit to
 * `index.php`, the app's «open the bot» button, the channel notice) asks here.
 * The first request that needs it calls `getMe`, stores the answer in
 * `Settings` (`Bot_Username` + `Bot_Username_At`) and every later request reads
 * that row, so the deploy needs nothing but `BOT_TOKEN`.
 *
 * `BOT_USERNAME` in `.env` is still honoured as a fallback for the case where
 * Telegram is unreachable, and a failed lookup is retried at most every ten
 * minutes so a wrong token cannot turn every page load into an API call.
 */
final class BotIdentity {
private const KEY_USERNAME = 'Bot_Username';
private const KEY_AT = 'Bot_Username_At';
private const KEY_FAILED_AT = 'Bot_Username_Fail_At';

/** A username is re-read weekly: usernames do change, but rarely. */
private const MAX_AGE = 604800;
private const RETRY_AFTER_FAILURE = 600;

private static ?string $Cached = null;

private function __construct() {
}

/** The bot username without `@`, or `''` when it cannot be determined. */
public static function username(): string {
if (self::$Cached !== null) {
return self::$Cached;
}

try {
$Stored = self::stored();

if ($Stored !== '') {
$At = (int)Repository::getSetting(self::KEY_AT, 0);

if (time() - $At > self::MAX_AGE) {
$Fresh = self::fetch();

if ($Fresh !== '') {
$Stored = $Fresh;
}
}

return self::$Cached = $Stored;
}

if (self::mayRetry()) {
$Fresh = self::fetch();

if ($Fresh !== '') {
return self::$Cached = $Fresh;
}
}
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Bot-Identity] lookup failed: ' . $Error->getMessage());
}

return self::$Cached = ltrim(Environment::getBotUsername(), '@');
}

/** `https://t.me/<username>`, or the bare `https://t.me/` when unknown. */
public static function link(): string {
$Username = self::username();

return $Username !== '' ? 'https://t.me/' . $Username : 'https://t.me/';
}

/** Whether the username is already stored in `Settings`. */
public static function stored(): string {
try {
$Value = Repository::getSetting(self::KEY_USERNAME, '');
}

catch (Throwable) {
return '';
}

return is_string($Value) ? ltrim(trim($Value), '@') : '';
}

/** Asks Telegram once and remembers the answer (or the failure). */
private static function fetch(): string {
try {
$Response = TelegramClient::call('getMe');
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Bot-Identity] getMe threw: ' . $Error->getMessage());
self::markFailed();

return '';
}

$Username = '';

if (($Response['ok'] ?? false) === true) {
$Username = ltrim(trim((string)($Response['result']['username'] ?? '')), '@');
}

if ($Username === '') {
error_log('[Umbrella-Bot][Bot-Identity] getMe returned no username');
self::markFailed();

return '';
}

try {
Repository::setSetting(self::KEY_USERNAME, $Username);
Repository::setSetting(self::KEY_AT, time());
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Bot-Identity] storing the username failed: ' . $Error->getMessage());
}

return $Username;
}

private static function markFailed(): void {
try {
Repository::setSetting(self::KEY_FAILED_AT, time());
}

catch (Throwable) {
}
}

private static function mayRetry(): bool {
try {
$Failed_At = (int)Repository::getSetting(self::KEY_FAILED_AT, 0);
}

catch (Throwable) {
return false;
}

return $Failed_At <= 0 || (time() - $Failed_At) > self::RETRY_AFTER_FAILURE;
}
}
?>
