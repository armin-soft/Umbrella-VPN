<?php
declare(strict_types=1);

error_reporting(E_ALL);
set_error_handler(static function (int $Severity, string $Message, string $File, int $Line): never {
    throw new ErrorException($Message, 0, $Severity, $File, $Line);
});

$Root = dirname(__DIR__);
$Passed = 0;
$Check = static function (bool $Ok, string $Why) use (&$Passed): void {
    if (!$Ok) {
        fwrite(STDERR, "FAIL: {$Why}\n");
        exit(1);
    }
    $Passed++;
};

// 1. Zero ZWNJ across all modified PHP files.
$Targets = [
    'Core/Server/Umbrella-Panel.php',
    'Core/Database/Schema-App.php',
    'Core/App/App-Bot-Link.php',
    'Core/App/App-Device-Limit.php',
    'Core/App/App-Gateway.php',
    'Bot/User.php',
    'Bot/Channel-Membership.php',
    'Bot/Admin.php',
    'Bot/App-Link.php',
    'Bot/Scheduler.php',
];
foreach ($Targets as $Rel) {
    $Src = (string)file_get_contents($Root . '/' . $Rel);
    $Check($Src !== '', "readable {$Rel}");
    $Check(!str_contains($Src, "\u{200C}"), "{$Rel} must contain zero ZWNJ");
}

// 2. Test PanelClient::update & PanelClient::linkTelegramId with 204/no-uuid PATCH + GET verify.
final class Helper {
    public static function normalizePhone(string $Phone): string { return $Phone; }
}
final class Environment {
    public static function getUmbrellaBaseUrl(): string { return 'https://panel.example.test/api/v2/admin/user'; }
}
final class ServerClient {
    public static function postHeaders(): array { return ['Content-Type: application/json']; }
    public static function listUsers(): array { return ['StatusCode' => 200, 'Json' => []]; }
}
final class HttpClient {
    public static int $PatchCount = 0;
    public static array $LastPatchPayload = [];
    public static int $StoredTelegramId = 0;
    public static bool $PatchReturnsEmptyBody = true;

    public static function get(string $Url, array $Headers = [], int $Timeout = 15): array {
        return [
            'StatusCode' => 200,
            'Body' => json_encode(['uuid' => 'uuid-test-1', 'name' => 'آرمین', 'comment' => '09358983854', 'telegram_id' => self::$StoredTelegramId]),
            'Json' => [
                'uuid' => 'uuid-test-1',
                'name' => 'آرمین',
                'comment' => '09358983854',
                'telegram_id' => self::$StoredTelegramId,
            ],
            'Error' => '',
        ];
    }

    public static function patch(string $Url, array $Payload, array $Headers = [], int $Timeout = 15): array {
        self::$PatchCount++;
        self::$LastPatchPayload = $Payload;
        if (isset($Payload['telegram_id'])) {
            self::$StoredTelegramId = (int)$Payload['telegram_id'];
        }
        if (self::$PatchReturnsEmptyBody) {
            return ['StatusCode' => 204, 'Body' => '', 'Json' => null, 'Error' => ''];
        }
        return [
            'StatusCode' => 200,
            'Body' => json_encode(['uuid' => 'uuid-test-1', 'telegram_id' => self::$StoredTelegramId]),
            'Json' => ['uuid' => 'uuid-test-1', 'telegram_id' => self::$StoredTelegramId],
            'Error' => '',
        ];
    }

    public static function post(string $Url, array $Payload, array $Headers = [], int $Timeout = 15): array {
        return ['StatusCode' => 200, 'Body' => '{}', 'Json' => [], 'Error' => ''];
    }
}

$PanelSrc = (string)file_get_contents($Root . '/Core/Server/Umbrella-Panel.php');
$PanelClass = substr($PanelSrc, (int)strpos($PanelSrc, 'final class PanelClient {'));
eval((string)preg_replace('/\?>\s*$/', '', $PanelClass));

$Updated = PanelClient::update('uuid-test-1', ['telegram_id' => '592526230']);
$Check(
    is_array($Updated) && (int)($Updated['telegram_id'] ?? 0) === 592526230 && is_int(HttpClient::$LastPatchPayload['telegram_id'] ?? null),
    'PanelClient::update normalizes telegram_id to int and recovers full record when PATCH returns HTTP 204/empty body'
);

HttpClient::$StoredTelegramId = 0;
HttpClient::$PatchCount = 0;
$Linked = PanelClient::linkTelegramId('uuid-test-1', 592526230);
$Check(
    is_array($Linked) && (int)($Linked['telegram_id'] ?? 0) === 592526230 && HttpClient::$PatchCount === 1,
    'PanelClient::linkTelegramId writes and verifies numeric telegram_id on the panel'
);

// 3. Test AppSchema::deduplicateTrustedDevices coalesces old v1.0.1 duplicates across Windows & Android while keeping distinct devices.
final class Database {
    private static ?self $Inst = null;
    public array $Devices = [];
    public array $Users = [];
    public array $DeletedDeviceRowIds = [];
    public array $RevokedSessionsFor = [];

    public static function getInstance(): self {
        return self::$Inst ??= new self();
    }

    public function transaction(callable $Fn): mixed {
        return $Fn($this);
    }

    public function fetchAll(string $Sql, array $Params = []): array {
        if (str_contains($Sql, 'FROM `App_Devices`')) {
            $Out = [];
            foreach ($this->Devices as $Row) {
                if ((int)($Row['Is_Trusted'] ?? 0) === 1) {
                    $Out[] = $Row;
                }
            }
            return $Out;
        }
        if (str_contains($Sql, 'FROM `Users`')) {
            return $this->Users;
        }
        return [];
    }

    public function execute(string $Sql, array $Params = []): object {
        if (str_starts_with($Sql, 'UPDATE `App_Devices` SET')) {
            $Id = (int)end($Params);
            foreach ($this->Devices as &$Row) {
                if ((int)$Row['ID'] === $Id) {
                    if (($Params[0] ?? '') !== '') $Row['User_UUID'] = $Params[0];
                    if (($Params[1] ?? '') !== '') $Row['Client_ID'] = $Params[1];
                    if ((int)($Params[2] ?? 0) > 0) $Row['Telegram_ID'] = (int)$Params[2];
                    if (($Params[4] ?? '') !== '') $Row['Phone'] = $Params[4];
                    if (($Params[5] ?? '') !== '') $Row['Full_Name'] = $Params[5];
                    if (($Params[6] ?? '') !== '') $Row['Device_Name'] = $Params[6];
                    if (($Params[7] ?? '') !== '') $Row['Platform'] = $Params[7];
                    if (($Params[8] ?? '') !== '') $Row['Last_IP'] = $Params[8];
                }
            }
        } elseif (str_starts_with($Sql, 'UPDATE `App_Sessions` SET `Revoked_At`')) {
            $this->RevokedSessionsFor[] = (string)$Params[0];
        } elseif (str_starts_with($Sql, 'DELETE FROM `App_Devices` WHERE `ID` = ?')) {
            $DelId = (int)$Params[0];
            $this->DeletedDeviceRowIds[] = $DelId;
            $this->Devices = array_values(array_filter($this->Devices, static fn(array $R): bool => (int)$R['ID'] !== $DelId));
        }
        return new stdClass();
    }
}

$SchemaSrc = (string)file_get_contents($Root . '/Core/Database/Schema-App.php');
$SchemaClass = substr($SchemaSrc, (int)strpos($SchemaSrc, 'final class AppSchema {'));
eval((string)preg_replace('/\?>\s*$/', '', $SchemaClass));

$Db = Database::getInstance();
$Db->Users = [
    ['Telegram_ID' => 592526230, 'Client_ID' => 'uuid-armin', 'Phone' => '09358983854'],
    ['Telegram_ID' => 1215191646, 'Client_ID' => 'uuid-ali', 'Phone' => '09184774930'],
];
$Db->Devices = [
    // Armin old v1.0.1 Windows entry (Persian platform label, phone only, older Last_Ts)
    [
        'ID' => 10, 'Device_ID' => 'dev-win-old-101', 'User_UUID' => 'uuid-armin', 'Client_ID' => 'uuid-armin',
        'Telegram_ID' => 0, 'Device_Name' => 'DESKTOP-ARMIN', 'Full_Name' => 'آرمین اسکندری',
        'Platform' => 'ویندوز ۱۱ • ۶۴ بیتی', 'App_Version' => '1.0.1', 'Phone' => '09358983854',
        'Push_Enabled' => 1, 'Last_IP' => '1.1.1.1', 'Is_Trusted' => 1, 'First_Ts' => 1700000000, 'Last_Ts' => 1700001000,
    ],
    // Armin new v1.0.3 Windows entry (English 'Windows' platform, newer timestamp)
    [
        'ID' => 25, 'Device_ID' => 'dev-win-new-103', 'User_UUID' => 'uuid-armin', 'Client_ID' => '',
        'Telegram_ID' => 592526230, 'Device_Name' => 'DESKTOP-ARMIN', 'Full_Name' => '',
        'Platform' => 'Windows', 'App_Version' => '1.0.3', 'Phone' => '',
        'Push_Enabled' => 1, 'Last_IP' => '2.2.2.2', 'Is_Trusted' => 1, 'First_Ts' => 1700500000, 'Last_Ts' => 1700600000,
    ],
    // Armin distinct Android phone (must NOT merge with Windows)
    [
        'ID' => 30, 'Device_ID' => 'dev-android-1', 'User_UUID' => 'uuid-armin', 'Client_ID' => 'uuid-armin',
        'Telegram_ID' => 592526230, 'Device_Name' => 'SM-A525F', 'Full_Name' => 'آرمین اسکندری',
        'Platform' => 'اندروید ۱۴ • آرم ۶۴ بیتی', 'App_Version' => '1.0.1', 'Phone' => '09358983854',
        'Push_Enabled' => 1, 'Last_IP' => '3.3.3.3', 'Is_Trusted' => 1, 'First_Ts' => 1700000000, 'Last_Ts' => 1700002000,
    ],
    // Armin duplicate Android entry on v1.0.3 with brand prefix 'Samsung SM-A525F'
    [
        'ID' => 35, 'Device_ID' => 'dev-android-2', 'User_UUID' => 'uuid-armin', 'Client_ID' => 'uuid-armin',
        'Telegram_ID' => 592526230, 'Device_Name' => 'Samsung SM-A525F', 'Full_Name' => 'آرمین اسکندری',
        'Platform' => 'Android', 'App_Version' => '1.0.3', 'Phone' => '09358983854',
        'Push_Enabled' => 1, 'Last_IP' => '4.4.4.4', 'Is_Trusted' => 1, 'First_Ts' => 1700500000, 'Last_Ts' => 1700650000,
    ],
    // Distinct Windows PC for another user (must NEVER merge across different device names or different users)
    [
        'ID' => 40, 'Device_ID' => 'dev-ali-home', 'User_UUID' => 'uuid-ali', 'Client_ID' => 'uuid-ali',
        'Telegram_ID' => 1215191646, 'Device_Name' => 'HOME-PC', 'Full_Name' => 'علیرضا',
        'Platform' => 'Windows', 'App_Version' => '1.0.3', 'Phone' => '09184774930',
        'Push_Enabled' => 1, 'Last_IP' => '5.5.5.5', 'Is_Trusted' => 1, 'First_Ts' => 1700600000, 'Last_Ts' => 1700700000,
    ],
    [
        'ID' => 41, 'Device_ID' => 'dev-ali-work', 'User_UUID' => 'uuid-ali', 'Client_ID' => 'uuid-ali',
        'Telegram_ID' => 1215191646, 'Device_Name' => 'WORK-LAPTOP', 'Full_Name' => 'علیرضا',
        'Platform' => 'Windows', 'App_Version' => '1.0.3', 'Phone' => '09184774930',
        'Push_Enabled' => 1, 'Last_IP' => '6.6.6.6', 'Is_Trusted' => 1, 'First_Ts' => 1700600000, 'Last_Ts' => 1700700500,
    ],
];

$Removed = AppSchema::deduplicateTrustedDevices($Db);
$Check($Removed === 2, 'exactly 2 duplicate v1.0.1 device rows removed (Windows + Android), distinct devices preserved');
$RemainingIds = array_column($Db->Devices, 'Device_ID');
$Check(
    in_array('dev-win-new-103', $RemainingIds, true)
    && in_array('dev-android-2', $RemainingIds, true)
    && in_array('dev-ali-home', $RemainingIds, true)
    && in_array('dev-ali-work', $RemainingIds, true),
    'newest version rows and distinct devices kept after deduplication'
);
$Check(
    in_array('dev-win-old-101', $Db->RevokedSessionsFor, true) && in_array('dev-android-1', $Db->RevokedSessionsFor, true),
    'old duplicate device sessions are revoked during merge'
);

$MergedWin = null;
foreach ($Db->Devices as $D) {
    if ($D['Device_ID'] === 'dev-win-new-103') $MergedWin = $D;
}
$Check(
    is_array($MergedWin) && $MergedWin['Phone'] === '09358983854' && $MergedWin['Full_Name'] === 'آرمین اسکندری',
    'winner Windows device inherits missing Phone and Full_Name from old v1.0.1 row'
);

// 4. Static contract assertions for bot-link / panel sync / dedup across Bot & Gateway files.
$BotLink = (string)file_get_contents($Root . '/Core/App/App-Bot-Link.php');
$Gateway = (string)file_get_contents($Root . '/Core/App/App-Gateway.php');
$Admin = (string)file_get_contents($Root . '/Bot/Admin.php');
$AppLink = (string)file_get_contents($Root . '/Bot/App-Link.php');
$User = (string)file_get_contents($Root . '/Bot/User.php');
$Scheduler = (string)file_get_contents($Root . '/Bot/Scheduler.php');

$Check(str_contains($BotLink, 'function peekPendingToken(') && str_contains($BotLink, 'function remindPendingIfAny('), 'AppBotLink keeps pending tokens safe until confirmation and supports reminding');
$Check(str_contains($BotLink, '$Context->saveUser()') && str_contains($BotLink, 'Repository::createUserIfMissing($Id)'), 'AppBotLink creates Users row on begin/confirm so pre-channel members do not hit false conflict');
$Check(str_contains($Gateway, 'self::syncBotUserClientId($FoundUid, $UUID)') && str_contains($Gateway, 'PanelClient::linkTelegramId('), 'AppGateway links Users.Client_ID on phone match and pushes verified telegram_id to panel');
$Check(str_contains($Admin, 'AppSchema::deduplicateTrustedDevices($Database)') && str_contains($AppLink, 'AppSchema::deduplicateTrustedDevices($Database'), 'Admin and user device views guard and invoke AppSchema::deduplicateTrustedDevices');
$Check(str_contains($Admin, '$Server_Missing_Tg_Push[$Uuid] = $Telegram_ID;') && str_contains($Admin, "ServerClient::updateUser((string)\$Push_Uuid, ['telegram_id' => (int)\$Push_Tg])"), 'Admin bulk sync pushes missing telegram_id back to server');
$Check(str_contains($User, 'AppBotLink::remindPendingIfAny($Context)') && str_contains($Scheduler, 'Repository::updateUser($User_ID, [\'Client_ID\' => $Uuid])'), 'UserFlow reminds pending app-link and Scheduler persists discovered Client_ID before Common sync');

echo "app_link_sync_and_dedup_test: {$Passed} checks passed\n";
