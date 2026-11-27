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
    /** @var callable|null */
    public static $Resolver = null;
    public static function get(string $url, array $headers = [], int $timeout = 10): array {
        self::$Urls[] = $url;
        if (is_callable(self::$Resolver)) {
            return (self::$Resolver)($url);
        }
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

$PrimaryPayload = [
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
                'name' => 'UmbrellaVPN-1.0.0-arm64-v8a.apk', 'size' => 63683069,
                'browser_download_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/1.0.0/UmbrellaVPN-1.0.0-arm64-v8a.apk',
            ],
            [
                'name' => 'UmbrellaVPN-1.0.0-universal.apk', 'size' => 167265670,
                'browser_download_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/1.0.0/UmbrellaVPN-1.0.0-universal.apk',
            ],
            [
                'name' => 'UmbrellaVPN-1.0.0-armeabi-v7a.apk', 'size' => 61730271,
                'browser_download_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/1.0.0/UmbrellaVPN-1.0.0-armeabi-v7a.apk',
            ],
            [
                'name' => 'UmbrellaVPN-1.0.0-x86_64.apk', 'size' => 66519742,
                'browser_download_url' => 'https://github.com/armin-soft/Umbrella-VPN-Releases/releases/download/1.0.0/UmbrellaVPN-1.0.0-x86_64.apk',
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

HttpClient::$Payload = $PrimaryPayload;
$windows = ReleaseCatalog::forPlatform('windows');
$android = ReleaseCatalog::forPlatform('android');
$macos = ReleaseCatalog::forPlatform('macos');
$Tag_Validator = new ReflectionMethod(ReleaseCatalog::class, 'isSupportedVersionTag');
$Platform_Resolver = new ReflectionMethod(ReleaseCatalog::class, 'platformsForRelease');
checkReleaseCatalog($Tag_Validator->invoke(null, '1.0.0') === true
    && $Tag_Validator->invoke(null, 'v0.9.9-windows') === true
    && $Tag_Validator->invoke(null, 'v1.0.0-android') === true
    && $Tag_Validator->invoke(null, 'v1.0.1-beta.1-android') === true,
    'simple tags and platform-suffixed tags remain supported');
checkReleaseCatalog($Platform_Resolver->invoke(null, 'v0.9.9-windows', []) === ['windows']
    && $Platform_Resolver->invoke(null, 'v1.0.0-android', []) === ['android'],
    'platform-suffixed tags still identify their platforms without asset extensions');
checkReleaseCatalog(count(HttpClient::$Urls) === 1
    && str_contains(HttpClient::$Urls[0], 'repos/armin-soft/Umbrella-VPN-Releases/releases'),
    'catalog reads the dedicated public release repository first when both platforms are present');
checkReleaseCatalog(($windows['stable']['tag'] ?? '') === '1.0.0', 'plain semantic version tag is selected for Windows stable');
checkReleaseCatalog(($windows['beta']['tag'] ?? '') === '1.0.1-beta.1', 'plain semantic version beta tag is selected for Windows');
checkReleaseCatalog(count($windows['stable']['assets'] ?? []) === 1
    && str_ends_with($windows['stable']['assets'][0]['name'], '.exe'), 'Windows catalog keeps only the exe from a multi-platform release');
checkReleaseCatalog(($android['stable']['tag'] ?? '') === '1.0.0', 'plain semantic version tag is selected for Android stable');
checkReleaseCatalog(($android['beta']['tag'] ?? '') === '1.0.1-beta.1', 'plain semantic version beta tag is selected for Android');
checkReleaseCatalog(count($android['stable']['assets'] ?? []) === 4
    && ($android['stable']['assets'][0]['name'] ?? '') === 'UmbrellaVPN-1.0.0-universal.apk'
    && ($android['stable']['assets'][1]['name'] ?? '') === 'UmbrellaVPN-1.0.0-arm64-v8a.apk',
    'Android catalog keeps only apk files and prioritizes universal then arm64-v8a');
checkReleaseCatalog($macos === ['stable' => null, 'beta' => null], 'unsupported desktop platforms remain unavailable');
checkReleaseCatalog(ReleaseCatalog::forPlatform('linux') === ['stable' => null, 'beta' => null], 'unsupported platform remains empty');

// Scenario 2: Fallback to armin-soft/Umbrella-VPN when Umbrella-VPN-Releases is empty.
$CatalogProp = new ReflectionProperty(ReleaseCatalog::class, 'Catalog');
$CatalogProp->setValue(null, null);
Repository::$Settings = [];
HttpClient::$Urls = [];
HttpClient::$Resolver = static function (string $url): array {
    if (str_contains($url, 'repos/armin-soft/Umbrella-VPN-Releases/releases')) {
        return ['StatusCode' => 200, 'Json' => []];
    }
    return ['StatusCode' => 200, 'Json' => [[
        'tag_name' => '1.0.0', 'name' => 'Umbrella VPN 1.0.0',
        'draft' => false, 'prerelease' => false,
        'published_at' => '2026-11-23T17:45:34Z',
        'html_url' => 'https://github.com/armin-soft/Umbrella-VPN/releases/tag/1.0.0',
        'assets' => [
            [
                'name' => 'UmbrellaVPN-Setup-1.0.0-x64.exe', 'size' => 50469188,
                'browser_download_url' => 'https://github.com/armin-soft/Umbrella-VPN/releases/download/1.0.0/UmbrellaVPN-Setup-1.0.0-x64.exe',
            ],
            [
                'name' => 'UmbrellaVPN-1.0.0-universal.apk', 'size' => 167265670,
                'browser_download_url' => 'https://github.com/armin-soft/Umbrella-VPN/releases/download/1.0.0/UmbrellaVPN-1.0.0-universal.apk',
            ],
        ],
    ]]];
};
$fbWindows = ReleaseCatalog::forPlatform('windows');
$fbAndroid = ReleaseCatalog::forPlatform('android');
checkReleaseCatalog(count(HttpClient::$Urls) === 2
    && str_contains(HttpClient::$Urls[0], 'repos/armin-soft/Umbrella-VPN-Releases/releases')
    && str_contains(HttpClient::$Urls[1], 'repos/armin-soft/Umbrella-VPN/releases'),
    'catalog falls back to armin-soft/Umbrella-VPN when Umbrella-VPN-Releases has no platform release');
checkReleaseCatalog(($fbWindows['stable']['assets'][0]['name'] ?? '') === 'UmbrellaVPN-Setup-1.0.0-x64.exe'
    && ($fbAndroid['stable']['assets'][0]['name'] ?? '') === 'UmbrellaVPN-1.0.0-universal.apk',
    'fallback fills both Windows and Android installers cleanly');

// Scenario 3: Reloading from Repository cache preserves asset URLs.
$CatalogProp->setValue(null, null);
HttpClient::$Urls = [];
$cachedAndroid = ReleaseCatalog::forPlatform('android');
checkReleaseCatalog(HttpClient::$Urls === []
    && ($cachedAndroid['stable']['assets'][0]['url'] ?? '') === 'https://github.com/armin-soft/Umbrella-VPN/releases/download/1.0.0/UmbrellaVPN-1.0.0-universal.apk',
    'cached catalog preserves installer download URLs across requests');

$User_Source = (string)file_get_contents(dirname(__DIR__) . '/Bot/User.php');
$Dispatcher_Source = (string)file_get_contents(dirname(__DIR__) . '/Bot/Dispatcher.php');
checkReleaseCatalog(str_contains($User_Source, "'windows' => ['.exe']")
    && str_contains($User_Source, "'android' => ['.apk']")
    && str_contains($User_Source, "'app_download_windows'")
    && str_contains($User_Source, "'app_download_android'")
    && str_contains($User_Source, 'public static function appDownloadAndroid(')
    && !str_contains($User_Source, "'app_download_macos'"), 'Windows and Android downloads are offered');
checkReleaseCatalog(str_contains($Dispatcher_Source, "'app_download_windows' => [UserFlow::class, 'appDownloadWindows']")
    && str_contains($Dispatcher_Source, "'app_download_android' => [UserFlow::class, 'appDownloadAndroid']")
    && str_contains($Dispatcher_Source, "'app_download_macos' => [UserFlow::class, 'appDownloadMenu']"), 'Dispatcher routes Windows and Android download buttons');

echo "OK Windows and Android release catalog and fallback routing\n";
