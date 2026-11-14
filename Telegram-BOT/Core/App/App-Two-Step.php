<?php
declare(strict_types=1);

require_once __DIR__ . '/../Storage/Repository.php';

/**
 * Whether a sign-in from the desktop app also needs the Telegram confirmation.
 *
 * The SMS code is always required; this only decides whether the device has to
 * be approved with a tap in the bot as well. It is on by default — a code can
 * be read over someone's shoulder or forwarded — and it can be switched off
 * per Telegram account from the bot's profile section, so the person who finds
 * the extra tap annoying in practice at least keeps a working second step.
 *
 * Stored in the shared `Settings` table because both sides need it: the bot
 * writes it, the gateway reads it on every verify().
 */
final class AppTwoStep {
private const PREFIX = 'AppTwoStep_';

private function __construct() {
}

/** Two-step is on unless that Telegram account explicitly turned it off. */
public static function enabled(int $Telegram_Id): bool {
if ($Telegram_Id <= 0) {
return true;
}

$Value = Repository::getSetting(self::key($Telegram_Id), null);

if ($Value === null) {
return true;
}

return (string)$Value !== '0';
}

public static function set(int $Telegram_Id, bool $Enabled): void {
if ($Telegram_Id <= 0) {
return;
}

Repository::setSetting(self::key($Telegram_Id), $Enabled ? '1' : '0');
}

private static function key(int $Telegram_Id): string {
return self::PREFIX . $Telegram_Id;
}
}
?>
