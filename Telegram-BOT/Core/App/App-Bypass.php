<?php
declare(strict_types=1);
require_once __DIR__ . '/App-Filter.php';
require_once __DIR__ . '/../Database/Database.php';

/** Per-account split routing. Domains are direct, never used to bypass blocks. */
final class AppBypass {
public const MAX_DOMAINS = 200;
private function __construct() {}

/**
 * هر هدف مسیر مستقیم را به صورت دامنه استاندارد یا آدرس IP/CIDR عمومی برمی گرداند.
 * آدرس های محلی/خصوصی، دامنه زیرساخت آمبرلا و مقادیر نامعتبر رد می شوند.
 */
public static function normalizeTarget(string $Raw): ?string {
$Value = trim($Raw);
if ($Value === '') return null;
$Value = strtr($Value, [
'۰' => '0', '۱' => '1', '۲' => '2', '۳' => '3', '۴' => '4',
'۵' => '5', '۶' => '6', '۷' => '7', '۸' => '8', '۹' => '9',
'٠' => '0', '١' => '1', '٢' => '2', '٣' => '3', '٤' => '4',
'٥' => '5', '٦' => '6', '٧' => '7', '٨' => '8', '٩' => '9',
]);
$Value = preg_replace('/[\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2060}\x{FEFF}]/u', '', $Value) ?? $Value;
$Value = trim($Value, " \t\n\r\0\x0B\"'`<>()[]{}");
$Value = preg_replace('#^[a-z][a-z0-9+.\-]*://#i', '', $Value) ?? $Value;

if (str_contains($Value, '/')) {
$Parts = explode('/', $Value, 2);
$Ip = trim($Parts[0], '[]');
$PrefixRaw = preg_split('/[?#\s]/', trim($Parts[1]), 2)[0] ?? '';
if ($PrefixRaw !== '' && ctype_digit($PrefixRaw)) {
$Prefix = (int)$PrefixRaw;
if (filter_var($Ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) !== false && $Prefix >= 0 && $Prefix <= 32) {
if (filter_var($Ip, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE) === false) {
return null;
}
return $Ip . '/' . $Prefix;
}
if (filter_var($Ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV6) !== false && $Prefix >= 0 && $Prefix <= 128) {
if (filter_var($Ip, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE) === false) {
return null;
}
return strtolower($Ip) . '/' . $Prefix;
}
}
}

$MaybeIp = trim(strcspn($Value, '/?#\\') > 0 ? substr($Value, 0, strcspn($Value, '/?#\\')) : $Value, '[]');
if (filter_var($MaybeIp, FILTER_VALIDATE_IP) !== false) {
if (filter_var($MaybeIp, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE) === false) {
return null;
}
return strtolower($MaybeIp);
}

return AppFilter::normalizeDomain($Raw);
}

/** @return array{add: string[], remove: string[], invalid: string[]} */
public static function parseTargetsInput(string $Raw): array {
$Normalized = str_replace(['،', '؛', "\r"], [',', ';', "\n"], $Raw);
$Add = [];
$Remove = [];
$Invalid = [];
foreach (preg_split('/[\s,;]+/u', $Normalized) ?: [] as $Part) {
$Token = trim($Part);
if ($Token === '') continue;
$IsRemove = str_starts_with($Token, '-');
$CleanToken = $IsRemove ? trim(substr($Token, 1)) : $Token;
$Target = self::normalizeTarget($CleanToken);
if ($Target === null) {
$Invalid[] = $Token;
continue;
}
if ($IsRemove) {
if (!in_array($Target, $Remove, true)) $Remove[] = $Target;
} else {
if (!in_array($Target, $Add, true)) $Add[] = $Target;
}
}
return ['add' => $Add, 'remove' => $Remove, 'invalid' => $Invalid];
}

public static function clean(array $Input): array {
$raw = $Input['domains'] ?? [];
if (!is_array($raw)) $raw = preg_split('/[\s,;،؛]+/u', (string)$raw) ?: [];
$domains = [];
foreach ($raw as $value) {
if (!is_string($value)) continue;
$target = self::normalizeTarget($value);
if ($target !== null && !in_array($target, $domains, true)) $domains[] = $target;
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
