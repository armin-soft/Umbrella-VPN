<?php
declare(strict_types=1);
require_once __DIR__ . '/App-Filter.php';
require_once __DIR__ . '/../Database/Database.php';

/** Per-account split routing. Domains are direct, never used to bypass blocks. */
final class AppBypass {
public const MAX_DOMAINS = 200;
private function __construct() {}

public static function clean(array $Input): array {
$raw = $Input['domains'] ?? [];
if (!is_array($raw)) $raw = preg_split('/[\s,;،؛]+/u', (string)$raw) ?: [];
$domains = [];
foreach ($raw as $value) {
if (!is_string($value)) continue;
$domain = AppFilter::normalizeDomain($value);
if ($domain !== null && !in_array($domain, $domains, true)) $domains[] = $domain;
if (count($domains) >= self::MAX_DOMAINS) break;
}
return ['iran' => filter_var($Input['iran'] ?? false, FILTER_VALIDATE_BOOLEAN), 'domains' => $domains];
}

public static function load(string $UUID): array {
if ($UUID === '' || $UUID === '_') return self::clean([]);
$row = Database::getInstance()->fetch('SELECT `Iran`, `Domains` FROM `App_Bypass_Settings` WHERE `User_UUID` = ? LIMIT 1', [$UUID]);
return self::clean(['iran' => (int)($row['Iran'] ?? 0) === 1,
'domains' => json_decode((string)($row['Domains'] ?? '[]'), true) ?: []]);
}

public static function save(string $UUID, array $Input): array {
if ($UUID === '' || $UUID === '_') throw new InvalidArgumentException('Invalid account');
$settings = self::clean($Input);
Database::getInstance()->execute('INSERT INTO `App_Bypass_Settings` (`User_UUID`, `Iran`, `Domains`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `Iran` = VALUES(`Iran`), `Domains` = VALUES(`Domains`)',
[$UUID, $settings['iran'] ? 1 : 0, json_encode($settings['domains'], JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE)]);
return $settings;
}
}
