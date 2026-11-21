<?php
declare(strict_types=1);

require_once __DIR__ . '/../Support/Http.php';
require_once __DIR__ . '/../Support/Helper.php';
require_once __DIR__ . '/../Storage/Repository.php';

/** Public, cached catalog of published app releases grouped by platform. */
final class ReleaseCatalog {
private const CACHE_KEY = 'App_Release_Catalog_Token';
private const CACHE_TTL = 900;
// Installers for every supported platform are uploaded to this public release repository.
private const SOURCES = ['armin-soft/Umbrella-VPN-Releases'];
private const PLATFORM_EXTENSIONS = [
'windows' => ['.exe'],
'android' => ['.apk'],
'macos' => ['.dmg', '.pkg'],
];
private const PLATFORMS = ['windows', 'android', 'macos'];
private static ?array $Catalog = null;

private function __construct() {
}

public static function forPlatform(string $Platform): array {
$Platform = strtolower(trim($Platform));
if (!in_array($Platform, self::PLATFORMS, true)) return ['stable' => null, 'beta' => null];
$Catalog = self::catalog();
return $Catalog[$Platform] ?? ['stable' => null, 'beta' => null];
}

private static function catalog(): array {
if (self::$Catalog !== null) return self::$Catalog;
$Cached = self::cachedCatalog();

if (is_array($Cached) && (time() - (int)($Cached['fetched_at'] ?? 0)) < self::CACHE_TTL) {
self::$Catalog = $Cached['releases'];
return self::$Catalog;
}

$Fresh = self::fetchCatalog();
if ($Fresh !== null) {
self::$Catalog = $Fresh;
Repository::setSetting(self::CACHE_KEY, json_encode([
'fetched_at' => time(),
'releases' => $Fresh,
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE));
return self::$Catalog;
}

// Keep serving the last known public catalog through a temporary GitHub outage.
self::$Catalog = is_array($Cached) ? $Cached['releases'] : self::emptyCatalog();
return self::$Catalog;
}

private static function cachedCatalog(): ?array {
$Raw = Repository::getSetting(self::CACHE_KEY, '');
if (!is_string($Raw) || $Raw === '') return null;
$Decoded = json_decode($Raw, true);
if (!is_array($Decoded) || !is_array($Decoded['releases'] ?? null)) return null;
return [
'fetched_at' => (int)($Decoded['fetched_at'] ?? 0),
'releases' => self::normalizeCatalog($Decoded['releases']),
];
}

private static function fetchCatalog(): ?array {
$Headers = [
'Accept' => 'application/vnd.github+json',
'X-GitHub-Api-Version' => '2022-11-28',
'User-Agent' => 'Umbrella-VPN-Telegram-Bot',
];
$Rows = [];
$Successful_Sources = 0;

foreach (self::SOURCES as $Source) {
try {
$Response = HttpClient::get('https://api.github.com/repos/' . $Source . '/releases?per_page=100', $Headers, 10);
if ((int)($Response['StatusCode'] ?? 0) !== 200 || !is_array($Response['Json'] ?? null)) continue;
$Successful_Sources++;
foreach ($Response['Json'] as $Release) {
if (is_array($Release)) $Rows[] = $Release;
}
}
catch (Throwable $Error) {
error_log('[Umbrella-Bot][Release-Catalog] ' . $Error->getMessage());
}
}

if ($Successful_Sources === 0) return null;
$Catalog = self::emptyCatalog();

foreach ($Rows as $Release) {
if (!empty($Release['draft'])) continue;
$Tag = trim((string)($Release['tag_name'] ?? ''));
if ($Tag === '' || !self::isSupportedVersionTag($Tag)) continue;
$Assets = self::normalizeAssets($Release['assets'] ?? []);
$Platforms = self::platformsForRelease($Tag, $Assets);
if ($Platforms === []) continue;
$Is_Beta = !empty($Release['prerelease'])
|| preg_match('/(?:^|[-.])(?:alpha|beta|rc|pre|preview|dev|nightly|canary)(?:[.-]|$)/i', $Tag) === 1;
$Channel = $Is_Beta ? 'beta' : 'stable';
$Published = trim((string)($Release['published_at'] ?? $Release['created_at'] ?? ''));
$Timestamp = $Published !== '' ? (strtotime($Published) ?: 0) : 0;

foreach ($Platforms as $Platform) {
$Entry = [
'platform' => $Platform,
'channel' => $Channel,
'tag' => $Tag,
'name' => trim((string)($Release['name'] ?? '')) ?: $Tag,
'url' => self::safeGitHubUrl((string)($Release['html_url'] ?? '')),
'published_at' => $Published,
'timestamp' => $Timestamp,
'notes' => trim((string)($Release['body'] ?? '')),
'assets' => self::assetsForPlatform($Assets, $Platform),
];
$Current = $Catalog[$Platform][$Channel];
if ($Current === null || $Timestamp > (int)($Current['timestamp'] ?? 0)) {
$Catalog[$Platform][$Channel] = $Entry;
}
}
}

return $Catalog;
}

private static function isSupportedVersionTag(string $Tag): bool {
$Version = preg_replace('/^v/i', '', trim($Tag)) ?? trim($Tag);
$Version = preg_replace('/-(?:windows|android|macos)$/i', '', $Version) ?? $Version;
return preg_match('/^\d+\.\d+\.\d+(?:[-.](?:alpha|beta|rc|pre|preview|dev|nightly|canary)(?:[.-]?\d+)?)?$/i', $Version) === 1;
}

private static function platformsForRelease(string $Tag, array $Assets): array {
$Platforms = [];
foreach (self::PLATFORM_EXTENSIONS as $Platform => $_Extensions) {
if (self::assetsForPlatform($Assets, $Platform) !== []) $Platforms[] = $Platform;
}

if (preg_match('/-(windows|android|macos)$/i', $Tag, $Match) === 1) {
$Tag_Platform = strtolower($Match[1]);
if (!in_array($Tag_Platform, $Platforms, true)) $Platforms[] = $Tag_Platform;
}

return $Platforms;
}

private static function assetsForPlatform(array $Assets, string $Platform): array {
$Extensions = self::PLATFORM_EXTENSIONS[$Platform] ?? [];
if ($Extensions === []) return [];

return array_values(array_filter($Assets, static function (array $Asset) use ($Extensions): bool {
$Name = strtolower(trim((string)($Asset['name'] ?? '')));
foreach ($Extensions as $Extension) {
if (str_ends_with($Name, $Extension)) return true;
}
return false;
}));
}

private static function emptyCatalog(): array {
$Catalog = [];
foreach (self::PLATFORMS as $Platform) $Catalog[$Platform] = ['stable' => null, 'beta' => null];
return $Catalog;
}

private static function normalizeCatalog(array $Catalog): array {
$Normalized = self::emptyCatalog();
foreach (self::PLATFORMS as $Platform) {
foreach (['stable', 'beta'] as $Channel) {
$Entry = $Catalog[$Platform][$Channel] ?? null;
if (!is_array($Entry)) continue;
$Normalized[$Platform][$Channel] = [
'platform' => $Platform,
'channel' => $Channel,
'tag' => trim((string)($Entry['tag'] ?? '')),
'name' => trim((string)($Entry['name'] ?? '')),
'url' => self::safeGitHubUrl((string)($Entry['url'] ?? '')),
'published_at' => trim((string)($Entry['published_at'] ?? '')),
'timestamp' => (int)($Entry['timestamp'] ?? 0),
'notes' => (string)($Entry['notes'] ?? ''),
'assets' => self::normalizeAssets($Entry['assets'] ?? []),
];
}
}
return $Normalized;
}

private static function normalizeAssets(mixed $Assets): array {
if (!is_array($Assets)) return [];
$Normalized = [];
foreach ($Assets as $Asset) {
if (!is_array($Asset)) continue;
$Name = trim((string)($Asset['name'] ?? ''));
$Url = self::safeGitHubUrl((string)($Asset['browser_download_url'] ?? ''));
if ($Name === '' || $Url === '') continue;
$Normalized[] = [
'name' => $Name,
'url' => $Url,
'size' => max(0, (int)($Asset['size'] ?? 0)),
];
}
return $Normalized;
}

private static function safeGitHubUrl(string $Url): string {
$Parts = parse_url(trim($Url));
if (!is_array($Parts) || strtolower((string)($Parts['scheme'] ?? '')) !== 'https'
|| strtolower((string)($Parts['host'] ?? '')) !== 'github.com') return '';
return $Url;
}
}
?>