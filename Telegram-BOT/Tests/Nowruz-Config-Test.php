<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/Config/Environment.php';
require_once dirname(__DIR__) . '/Core/Support/Helper.php';

final class Repository {
    public static array $Settings = [];
    public static function getSetting(string $key, mixed $default = null): mixed {
        return self::$Settings[$key] ?? $default;
    }
    public static function setSetting(string $key, string $value): void {
        self::$Settings[$key] = $value;
    }
}

$source = (string)file_get_contents(dirname(__DIR__) . '/Core/Support/Bot-Config.php');
$source = preg_replace('/^require_once .*;\s*$/m', '', $source) ?? $source;
$source = preg_replace('/^<\?php\s*declare\(strict_types=1\);/', '', $source) ?? $source;
eval($source);

function checkNowruz(bool $ok, string $message): void {
    if (!$ok) throw new RuntimeException($message);
}

$tehran = new DateTimeZone('Asia/Tehran');
$first = new DateTimeImmutable('2025-03-21 12:00:00', $tehran);
$last = new DateTimeImmutable('2025-04-02 12:00:00', $tehran);
$before = new DateTimeImmutable('2025-03-20 12:00:00', $tehran);
$after = new DateTimeImmutable('2025-04-03 12:00:00', $tehran);
Repository::$Settings[BotConfig::KEY_NOWRUZ_MENU] = '1';
checkNowruz(BotConfig::isNowruzMenuEnabled($first), 'the Nowruz menu starts on 1 Farvardin');
checkNowruz(BotConfig::isNowruzMenuEnabled($last), 'the Nowruz menu includes 13 Farvardin');
checkNowruz(!BotConfig::isNowruzMenuEnabled($before), 'the Nowruz menu is hidden before Farvardin 1');
checkNowruz(!BotConfig::isNowruzMenuEnabled($after), 'the Nowruz menu is hidden after Farvardin 13');
checkNowruz(BotConfig::isNowruzFirstDay($first), 'the first Farvardin day is detected for the annual notice');
checkNowruz(!BotConfig::isNowruzFirstDay($last), 'the annual notice is limited to the first Farvardin day');
checkNowruz(BotConfig::nowruzSeasonKey($first) === '1404', 'the gift claim key uses the Solar Hijri year');
Repository::$Settings[BotConfig::KEY_NOWRUZ_MENU] = '0';
checkNowruz(!BotConfig::isNowruzMenuEnabled($first), 'the admin can keep the seasonal menu disabled');

echo "OK Nowruz Solar Hijri window\n";
