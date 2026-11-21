<?php
declare(strict_types=1);

final class Repository {
    public static array $Settings = [];
    public static function getSetting(string $key, mixed $default = ''): mixed {
        return self::$Settings[$key] ?? $default;
    }
    public static function setSetting(string $key, string $value): void {
        self::$Settings[$key] = $value;
    }
}

final class HttpClient {
    public static array $Urls = [];
    public static array $Payload = [];
    public static function get(string $url, array $headers = [], int $timeout = 10): array {
        self::$Urls[] = $url;
        return ['StatusCode' => 200, 'Json' => self::$Payload];
    }
}

$source = (string)file_get_contents(dirname(__DIR__) . '/Core/App/Release-Catalog.php');
$source = preg_replace('/^require_once .*;\s*$/m', '', $source) ?? $source;
$source = preg_replace('/^<\?php\s*declare\(strict_types=1\);/', '', $source) ?? $source;
$source = preg_replace('/\?>\s*$/', '', $source) ?? $source;
eval($source);

function checkReleaseCatalog(bool $ok, string $message): void {
    if (!$ok) throw new RuntimeException($message);
}

HttpClient::$Payload = [
    [
        'tag_name' => 'v2.0.0-windows', 'name' => 'Umbrella VPN 2.0.0',
        'draft' => false, 'prerelease' => false,
        'published_at' => '2026-11-01T10:00:00Z',
        'html_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/tag/v2.0.0-windows',
        'assets' => [[
            'name' => 'UmbrellaVPN-Setup-2.0.0-x64.exe', 'size' => 42000000,
            'browser_download_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/v2.0.0-windows/UmbrellaVPN-Setup-2.0.0-x64.exe',
        ]],
    ],
    [
        'tag_name' => 'v2.1.0-beta.1-windows', 'name' => 'Umbrella VPN Beta',
        'draft' => false, 'prerelease' => true,
        'published_at' => '2026-11-10T10:00:00Z',
        'html_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/tag/v2.1.0-beta.1-windows',
        'assets' => [[
            'name' => 'UmbrellaVPN-Setup-2.1.0-beta.1-x64.exe', 'size' => 43000000,
            'browser_download_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/v2.1.0-beta.1-windows/UmbrellaVPN-Setup-2.1.0-beta.1-x64.exe',
        ]],
    ],
    [
        'tag_name' => 'v9.9.9-windows', 'name' => 'Private draft',
        'draft' => true, 'prerelease' => false,
        'published_at' => '2026-11-16T10:00:00Z',
        'html_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/tag/v9.9.9-windows',
        'assets' => [],
    ],
];

$releases = ReleaseCatalog::forPlatform('windows');
checkReleaseCatalog(count(HttpClient::$Urls) === 1
    && str_contains(HttpClient::$Urls[0], 'repos/armin-soft/Umbrella-VPN-Releases/releases'), 'catalog reads the dedicated public release repository');
checkReleaseCatalog(($releases['stable']['tag'] ?? '') === 'v2.0.0-windows', 'published stable release is selected');
checkReleaseCatalog(($releases['beta']['tag'] ?? '') === 'v2.1.0-beta.1-windows', 'published beta release is selected separately');
checkReleaseCatalog(count($releases['stable']['assets'] ?? []) === 1
    && str_ends_with($releases['stable']['assets'][0]['url'], '.exe'), 'public installer asset is available for download');
checkReleaseCatalog(($releases['stable']['tag'] ?? '') !== 'v9.9.9-windows', 'private GitHub Drafts are never listed');
checkReleaseCatalog(ReleaseCatalog::forPlatform('android') === ['stable' => null, 'beta' => null], 'unsupported platform remains empty');

echo "OK public release catalog\n";
