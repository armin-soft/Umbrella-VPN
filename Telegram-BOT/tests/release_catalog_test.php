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
        'tag_name' => 'v0.9.9-windows', 'name' => 'Legacy Windows release',
        'draft' => false, 'prerelease' => false,
        'published_at' => '2026-10-31T10:00:00Z',
        'html_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/tag/v0.9.9-windows',
        'assets' => [[
            'name' => 'UmbrellaVPN-Setup-0.9.9-x64.exe', 'size' => 41000000,
            'browser_download_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/v0.9.9-windows/UmbrellaVPN-Setup-0.9.9-x64.exe',
        ]],
    ],
    [
        'tag_name' => '1.0.0', 'name' => 'Umbrella VPN 1.0.0',
        'draft' => false, 'prerelease' => false,
        'published_at' => '2026-11-21T14:49:32Z',
        'html_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/tag/1.0.0',
        'assets' => [
            [
                'name' => 'Umbrella.VPN-Setup-1.0.0-x64.exe', 'size' => 49821563,
                'browser_download_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/1.0.0/Umbrella.VPN-Setup-1.0.0-x64.exe',
            ],
            [
                'name' => 'UmbrellaVPN-1.0.0-universal.apk', 'size' => 22000000,
                'browser_download_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/1.0.0/UmbrellaVPN-1.0.0-universal.apk',
            ],
            [
                'name' => 'UmbrellaVPN-1.0.0-macos.dmg', 'size' => 28000000,
                'browser_download_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/1.0.0/UmbrellaVPN-1.0.0-macos.dmg',
            ],
            [
                'name' => 'SHA256SUMS.txt', 'size' => 300,
                'browser_download_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/1.0.0/SHA256SUMS.txt',
            ],
        ],
    ],
    [
        'tag_name' => '1.0.1-beta.1', 'name' => 'Umbrella VPN 1.0.1 Beta 1',
        'draft' => false, 'prerelease' => true,
        'published_at' => '2026-11-22T10:00:00Z',
        'html_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/tag/1.0.1-beta.1',
        'assets' => [
            [
                'name' => 'UmbrellaVPN-Setup-1.0.1-beta.1-x64.exe', 'size' => 43000000,
                'browser_download_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/1.0.1-beta.1/UmbrellaVPN-Setup-1.0.1-beta.1-x64.exe',
            ],
            [
                'name' => 'UmbrellaVPN-1.0.1-beta.1.apk', 'size' => 23000000,
                'browser_download_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/1.0.1-beta.1/UmbrellaVPN-1.0.1-beta.1.apk',
            ],
            [
                'name' => 'UmbrellaVPN-1.0.1-beta.1.pkg', 'size' => 29000000,
                'browser_download_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/1.0.1-beta.1/UmbrellaVPN-1.0.1-beta.1.pkg',
            ],
        ],
    ],
    [
        'tag_name' => 'Windows', 'name' => 'Malformed tag must be ignored',
        'draft' => false, 'prerelease' => false,
        'published_at' => '2026-11-23T10:00:00Z',
        'html_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/tag/Windows',
        'assets' => [[
            'name' => 'UmbrellaVPN-Setup-x64.exe', 'size' => 42000000,
            'browser_download_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/Windows/UmbrellaVPN-Setup-x64.exe',
        ]],
    ],
    [
        'tag_name' => '9.9.9', 'name' => 'Private draft',
        'draft' => true, 'prerelease' => false,
        'published_at' => '2026-11-24T10:00:00Z',
        'html_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/tag/9.9.9',
        'assets' => [],
    ],
];

$windows = ReleaseCatalog::forPlatform('windows');
$android = ReleaseCatalog::forPlatform('android');
$macos = ReleaseCatalog::forPlatform('macos');
$Tag_Validator = new ReflectionMethod(ReleaseCatalog::class, 'isSupportedVersionTag');
$Platform_Resolver = new ReflectionMethod(ReleaseCatalog::class, 'platformsForRelease');
checkReleaseCatalog($Tag_Validator->invoke(null, '1.0.0') === true
    && $Tag_Validator->invoke(null, 'v0.9.9-windows') === true
    && $Tag_Validator->invoke(null, 'v1.0.1-beta.1-windows') === true,
    'simple tags and legacy platform-suffixed tags remain supported');
checkReleaseCatalog($Platform_Resolver->invoke(null, 'v0.9.9-windows', []) === ['windows'],
    'legacy Windows tag still identifies its platform without asset extensions');
checkReleaseCatalog(count(HttpClient::$Urls) === 1
    && str_contains(HttpClient::$Urls[0], 'repos/armin-soft/Umbrella-VPN-Releases/releases'), 'catalog reads the dedicated public release repository');
checkReleaseCatalog(($windows['stable']['tag'] ?? '') === '1.0.0', 'plain semantic version tag is selected for Windows stable');
checkReleaseCatalog(($windows['beta']['tag'] ?? '') === '1.0.1-beta.1', 'plain semantic version beta tag is selected');
checkReleaseCatalog(count($windows['stable']['assets'] ?? []) === 1
    && str_ends_with($windows['stable']['assets'][0]['name'], '.exe'), 'Windows catalog keeps only the exe from a multi-platform release');
checkReleaseCatalog(($android['stable']['tag'] ?? '') === '1.0.0'
    && count($android['stable']['assets'] ?? []) === 1
    && str_ends_with($android['stable']['assets'][0]['name'], '.apk'), 'Android catalog selects the apk from the same release');
checkReleaseCatalog(($macos['stable']['tag'] ?? '') === '1.0.0'
    && count($macos['stable']['assets'] ?? []) === 1
    && str_ends_with($macos['stable']['assets'][0]['name'], '.dmg'), 'macOS catalog selects the dmg from the same release');
checkReleaseCatalog(($android['beta']['tag'] ?? '') === '1.0.1-beta.1'
    && str_ends_with($android['beta']['assets'][0]['name'], '.apk'), 'Android beta uses the same plain version tag pattern');
checkReleaseCatalog(($macos['beta']['tag'] ?? '') === '1.0.1-beta.1'
    && str_ends_with($macos['beta']['assets'][0]['name'], '.pkg'), 'macOS pkg beta uses the same plain version tag pattern');
checkReleaseCatalog(ReleaseCatalog::forPlatform('linux') === ['stable' => null, 'beta' => null], 'unsupported platform remains empty');

$User_Source = (string)file_get_contents(dirname(__DIR__) . '/Bot/User.php');
$Dispatcher_Source = (string)file_get_contents(dirname(__DIR__) . '/Bot/Dispatcher.php');
checkReleaseCatalog(str_contains($User_Source, "'android' => ['.apk']")
    && str_contains($User_Source, "'macos' => ['.dmg', '.pkg']"), 'bot download menu filters platform-specific installable files');
checkReleaseCatalog(str_contains($User_Source, "'app_download_android'")
    && str_contains($User_Source, "'app_download_macos'"), 'bot menu exposes Android and macOS selections');
checkReleaseCatalog(str_contains($Dispatcher_Source, "'app_download_android'")
    && str_contains($Dispatcher_Source, "'app_download_macos'"), 'bot routes Android and macOS download menus');

echo "OK public multi-platform release catalog and plain version tags\n";
