<?php
declare(strict_types=1);

error_reporting(E_ALL);

if (!function_exists('mb_strlen')) {
    function mb_strlen(string $Text): int {
        return count(preg_split('//u', $Text, -1, PREG_SPLIT_NO_EMPTY) ?: []);
    }
}
if (!function_exists('mb_substr')) {
    function mb_substr(string $Text, int $Start, ?int $Length = null): string {
        $Chars = preg_split('//u', $Text, -1, PREG_SPLIT_NO_EMPTY) ?: [];
        return implode('', $Length === null ? array_slice($Chars, $Start) : array_slice($Chars, $Start, $Length));
    }
}

require_once dirname(__DIR__) . '/Bot/Menu.php';
require_once dirname(__DIR__) . '/Core/Support/Helper.php';

final class Context {
    public function __construct(
        public array $Raw = [],
        public int $UserId = 592526230,
        public int $ChatId = 592526230,
        public string $FirstName = 'آرمین',
        public bool $IsCallback = true,
        public ?string $CallbackData = null,
        public ?string $CallbackId = 'cb-1',
        public ?int $MessageId = 100,
        public ?string $Text = null,
        private bool $Admin = true,
    ) {}

    public function isAdmin(): bool {
        return $this->Admin;
    }

    public function profileName(): string {
        return $this->FirstName !== '' ? $this->FirstName : 'مدیریت';
    }
}

final class BotConfig {
    public static function getChannelUrl(): string {
        return 'https://t.me/UmbrellaVPN_Channel';
    }
    public static function robotVersion(): string {
        return '1.0.0';
    }
}

final class ServerClient {
    public static array $ListResponse = ['StatusCode' => 200, 'Json' => []];
    public static ?array $GetResponse = null;
    public static array $UpdateCalls = [];
    public static int $ListCalls = 0;

    public static function listUsers(int $Attempts = 2, int $Time_Out = 15): array {
        self::$ListCalls++;
        return self::$ListResponse;
    }

    public static function getUser(string $Client_ID): array {
        if (self::$GetResponse !== null) return self::$GetResponse;
        return ['StatusCode' => 404, 'Json' => null, 'Body' => 'not found'];
    }

    public static function updateUser(string $Client_ID, array $Payload): array {
        self::$UpdateCalls[] = ['uuid' => $Client_ID, 'payload' => $Payload];
        return ['StatusCode' => 200, 'Json' => ['uuid' => $Client_ID] + $Payload];
    }
}

final class PanelClient {
    public static function findByTelegramId(int $Id): ?array { return null; }
    public static function findByPhone(string $Phone): ?array { return null; }
}

final class AppAccountRevocation {
    public static function revoke(string $Uuid): bool { return true; }
}

final class Database {
    private static ?self $Inst = null;
    public static array $Tables = [];
    public static array $DeletedTables = [];
    public static bool $FailNextInsert = false;
    public static bool $RolledBack = false;
    private static array $Snapshot = [];

    public static function getInstance(): self {
        return self::$Inst ??= new self();
    }

    public static function resetMock(): void {
        self::$Tables = [
            'Users' => [
                ['Telegram_ID' => 999999, 'Client_ID' => 'stale-uuid', 'Full_Name' => 'کاربر قدیمی', 'Balance' => 50000],
            ],
            'Transactions' => [
                ['ID' => 1, 'User_ID' => 999999, 'Amount' => 50000],
            ],
            'Tickets' => [['ID' => 1, 'User_ID' => 999999]],
            'Ticket_Messages' => [['ID' => 1, 'Ticket_ID' => 1]],
            'Subscription_Logs' => [['ID' => 1, 'User_ID' => 999999]],
            'Usage_Snapshots' => [['Snapshot_Date' => '2026-11-22', 'User_ID' => 999999]],
            'SMS_Logs' => [['ID' => 1, 'User_ID' => 999999]],
            'Notifications' => [['ID' => 1, 'User_ID' => 999999]],
            'Scheduled_Jobs' => [['ID' => 1, 'User_ID' => 999999]],
            'Payment_Queue' => [['ID' => 1, 'User_ID' => 999999]],
            'Ratings' => [['ID' => 1, 'User_ID' => 999999]],
            'App_Devices' => [['Device_ID' => 'dev-1', 'User_UUID' => 'stale-uuid', 'Telegram_ID' => 999999]],
            'App_Sessions' => [['Token_Hash' => 'tok-1', 'User_UUID' => 'stale-uuid', 'Telegram_ID' => 999999]],
            'App_SignIn_Requests' => [['Challenge' => 'c1']],
            'App_Bot_Link_Requests' => [['Token_Hash' => 'l1']],
            'App_Notifications' => [['ID' => 1]],
            'App_Device_Limits' => [['Telegram_ID' => 999999]],
            'App_Bypass_Settings' => [['User_UUID' => 'stale-uuid']],
            'App_Filter_Settings' => [['User_UUID' => 'stale-uuid']],
            'App_Cancelled_Payments' => [['Authority' => 'a1']],
            'User_Sessions' => [
                ['Telegram_ID' => 592526230, 'Flow' => 'stale:flow'],
                ['Telegram_ID' => 888888, 'Flow' => 'user:ticket'],
            ],
            'Settings' => [
                ['Key' => 'Robot_Status', 'Value' => '🟢روشن'],
                ['Key' => 'Plan_Price_1', 'Value' => '150000'],
                ['Key' => 'App_Gateway_Secret', 'Value' => 'keep-secret'],
                ['Key' => 'App_Free_Claimed_stale-uuid', 'Value' => '1'],
                ['Key' => 'app_otp_cooldown_abc', 'Value' => '12345'],
                ['Key' => 'DailyNotice_999', 'Value' => '1'],
                ['Key' => 'Nowruz_Claimed_2026_u_999', 'Value' => '1'],
            ],
        ];
        self::$DeletedTables = [];
        self::$FailNextInsert = false;
        self::$RolledBack = false;
    }

    public function transaction(callable $Callback): mixed {
        self::$Snapshot = self::$Tables;
        self::$RolledBack = false;
        try {
            return $Callback($this);
        } catch (Throwable $E) {
            self::$Tables = self::$Snapshot;
            self::$RolledBack = true;
            throw $E;
        }
    }

    public function fetchAll(string $Sql, array $Params = []): array {
        if (str_contains($Sql, 'information_schema.tables')) {
            $Out = [];
            foreach (array_keys(self::$Tables) as $Name) {
                $Out[] = ['t' => $Name];
            }
            return $Out;
        }
        return [];
    }

    public function fetchOne(string $Sql, array $Params = []): ?array {
        if (str_contains($Sql, 'FROM `Users` WHERE `Client_ID` = ?')) {
            $Cid = (string)($Params[0] ?? '');
            foreach (self::$Tables['Users'] ?? [] as $Row) {
                if ((string)($Row['Client_ID'] ?? '') === $Cid) return $Row;
            }
        }
        return null;
    }

    public function execute(string $Sql, array $Params = []): object {
        if (preg_match('/^DELETE FROM `([^`]+)`$/i', trim($Sql), $M) === 1) {
            $Table = $M[1];
            self::$Tables[$Table] = [];
            self::$DeletedTables[] = $Table;
            return new stdClass();
        }
        if (str_starts_with($Sql, 'DELETE FROM `User_Sessions` WHERE `Telegram_ID` <> ?')) {
            $Keep = (int)($Params[0] ?? 0);
            self::$Tables['User_Sessions'] = array_values(array_filter(
                self::$Tables['User_Sessions'] ?? [],
                static fn(array $R): bool => (int)($R['Telegram_ID'] ?? 0) === $Keep
            ));
            return new stdClass();
        }
        if (str_starts_with($Sql, 'UPDATE `User_Sessions` SET')) {
            $Keep = (int)end($Params);
            foreach (self::$Tables['User_Sessions'] as &$Row) {
                if ((int)($Row['Telegram_ID'] ?? 0) === $Keep) {
                    $Row['Flow'] = null;
                }
            }
            return new stdClass();
        }
        if (str_starts_with($Sql, 'DELETE FROM `Settings` WHERE')) {
            self::$Tables['Settings'] = array_values(array_filter(
                self::$Tables['Settings'] ?? [],
                static function (array $Row): bool {
                    $K = (string)($Row['Key'] ?? '');
                    return !str_starts_with($K, 'App_Free_Claimed_')
                        && !str_starts_with($K, 'app_otp_cooldown_')
                        && !str_starts_with($K, 'DailyNotice_')
                        && !str_starts_with($K, 'Nowruz_Claimed_');
                }
            ));
            return new stdClass();
        }
        if (str_starts_with($Sql, 'UPDATE `Users` SET `Client_ID` = NULL')) {
            $Cid = (string)($Params[0] ?? '');
            $Keep = (int)($Params[1] ?? 0);
            foreach (self::$Tables['Users'] as &$Row) {
                if ((string)($Row['Client_ID'] ?? '') === $Cid && (int)($Row['Telegram_ID'] ?? 0) !== $Keep) {
                    $Row['Client_ID'] = null;
                }
            }
        }
        return new stdClass();
    }

    public function insert(string $Table, array $Data): int {
        if (self::$FailNextInsert) {
            throw new RuntimeException('simulated insert failure');
        }
        self::$Tables[$Table][] = $Data;
        return count(self::$Tables[$Table]);
    }
}

final class Repository {
    public static array $Session = [];
    public static array $Settings = [];
    public static array $AdminLogs = [];
    public static array $SubLogs = [];

    public static function getUser(int $Id): array {
        foreach (Database::$Tables['Users'] ?? [] as $Row) {
            if ((int)($Row['Telegram_ID'] ?? 0) === $Id) return $Row;
        }
        return [];
    }

    public static function updateUser(int $Id, array $Fields): void {
        foreach (Database::$Tables['Users'] as &$Row) {
            if ((int)($Row['Telegram_ID'] ?? 0) === $Id) {
                $Row = array_replace($Row, $Fields);
                return;
            }
        }
    }

    public static function findUserByIdentifier(string $Identifier): ?array {
        $Norm = Helper::normalizePhone($Identifier);
        if (ctype_digit($Identifier)) {
            $U = self::getUser((int)$Identifier);
            return $U !== [] ? $U : null;
        }
        foreach (Database::$Tables['Users'] ?? [] as $Row) {
            if ($Norm !== '' && Helper::normalizePhone((string)($Row['Phone'] ?? '')) === $Norm) {
                return $Row;
            }
        }
        return null;
    }

    public static function findUserByPhone(string $Phone, int $Exclude = 0): array { return []; }
    public static function getUserByClientId(string $Uuid): array { return []; }
    public static function updateUserSession(int $Id, array $Values): void { self::$Session = array_replace(self::$Session, $Values); }
    public static function getUserSession(int $Id): array { return self::$Session; }
    public static function getSetting(string $Key, mixed $Default = ''): mixed { return self::$Settings[$Key] ?? $Default; }
    public static function setSetting(string $Key, mixed $Value): void { self::$Settings[$Key] = (string)$Value; }
    public static function updateUsageSnapshotValues(): void {}
    public static function logAdminAction(int $AdminId, string $Action, ?int $Target, string $Details): void {
        self::$AdminLogs[] = ['admin' => $AdminId, 'action' => $Action, 'details' => $Details];
    }
    public static function addSubscriptionLog(int $Uid, string $Action, string $Plan, int $Days, float $Gb, string $Resp, string $Source, int $Actor): void {
        self::$SubLogs[] = ['uid' => $Uid, 'action' => $Action, 'days' => $Days];
    }
}

final class TelegramClient {
    public static array $Messages = [];
    public static array $LastMarkup = [];

    public static function inlineKeyboard(array $Rows): array { return ['inline_keyboard' => $Rows]; }
    public static function answerCallbackQuery(?string $Id, string $Text, bool $Alert = false): void {}
    public static function sendChatAction(int $ChatId): void {}
    public static function sendMessage(int $ChatId, string $Text, array $Markup = []): void {
        self::$Messages[] = ['chat' => $ChatId, 'text' => $Text, 'markup' => $Markup];
        if ($Markup !== []) self::$LastMarkup = $Markup;
    }
    public static function editOrSendMessage(int $ChatId, ?int $MsgId, string $Text, array $Markup = []): void {
        self::sendMessage($ChatId, $Text, $Markup);
    }
    public static function editMessageText(int $ChatId, int $MsgId, string $Text, array $Markup = []): void {
        self::sendMessage($ChatId, $Text, $Markup);
    }
    public static function sendSystemMessage(int $ChatId, string $Text, array $Markup = []): array {
        self::$Messages[] = ['chat' => $ChatId, 'text' => $Text, 'markup' => $Markup, 'system' => true];
        return ['ok' => true];
    }
}

foreach (['Common' => 'Common.php', 'AdminFlow' => 'Admin.php'] as $Class => $File) {
    $Src = (string)file_get_contents(dirname(__DIR__) . '/Bot/' . $File);
    $Pos = strpos($Src, 'final class ' . $Class . ' {');
    if ($Pos === false) throw new RuntimeException('Missing class ' . $Class);
    eval(preg_replace('/\?>\s*$/', '', substr($Src, $Pos)));
}

$Passed = 0;
function ok(bool $Cond, string $Msg): void {
    global $Passed;
    if (!$Cond) throw new RuntimeException('FAIL: ' . $Msg);
    $Passed++;
}

$Admin = new Context(UserId: 592526230, ChatId: 592526230, FirstName: 'آرمین', Admin: true);
$Guest = new Context(UserId: 123456, ChatId: 123456, FirstName: 'کاربر', Admin: false);

// 1. Two-button menu contract for askUpdateUserData & single-user askSingleUserData.
Database::resetMock();
TelegramClient::$Messages = [];
Repository::$Session = ['Flow' => 'admin:credit_add_uid', 'Temp_UID' => 42, 'Broadcast_Mode' => 'sms'];
AdminFlow::askUpdateUserData($Admin);
ok((Repository::$Session['Flow'] ?? null) === null, 'askUpdateUserData clears stale flow');
$Rows = TelegramClient::$LastMarkup['inline_keyboard'] ?? [];
ok(Menu::problems($Rows) === [], 'askUpdateUserData keyboard has zero layout problems');
$Callbacks = array_column(array_merge(...$Rows), 'callback_data');
ok($Callbacks === ['admin_users_auto_sync', 'admin_users_single_sync', 'عملیات کلاینت سرور', 'مدیریت'], 'askUpdateUserData renders auto and single sync options plus navigation');

TelegramClient::$Messages = [];
AdminFlow::askSingleUserData($Admin);
ok((Repository::$Session['Flow'] ?? '') === 'admin:update_uid', 'askSingleUserData enters single-user flow');
ok(Menu::problems(TelegramClient::$LastMarkup['inline_keyboard'] ?? []) === [], 'askSingleUserData keyboard valid');

// 2. Non-admin cannot execute bulk sync.
ServerClient::$ListCalls = 0;
AdminFlow::autoUpdateAllUsers($Guest);
ok(ServerClient::$ListCalls === 0 && count(Database::$Tables['Users']) === 1, 'non-admin rejected before API or DB touch');

// 3. Panel API failure or empty list must NOT wipe DB.
ServerClient::$ListResponse = ['StatusCode' => 502, 'Json' => null, 'Body' => 'Bad Gateway'];
AdminFlow::autoUpdateAllUsers($Admin);
ok(Database::$Tables['Users'][0]['Telegram_ID'] === 999999 && count(Database::$Tables['Transactions']) === 1, 'HTTP 502 preserves existing DB untouched');

ServerClient::$ListResponse = ['StatusCode' => 200, 'Json' => []];
AdminFlow::autoUpdateAllUsers($Admin);
ok(Database::$Tables['Users'][0]['Telegram_ID'] === 999999 && count(Database::$Tables['Transactions']) === 1, 'empty API response preserves existing DB untouched');

// 4. Full wipe & replace using real panel output format (active, inactive enable=false, 367d, and telegram_id=null).
$Sample_Payload = [
    [
        'id' => 2,
        'uuid' => '9b9d9f5d-9841-45bf-a6b9-0479de273c11',
        'telegram_id' => 592526230,
        'name' => 'آرمین اسکندری',
        'comment' => '09358983854',
        'current_usage_GB' => 436.639964137226,
        'usage_limit_GB' => 1000,
        'package_days' => 365,
        'start_date' => '2026-08-03',
        'enable' => true,
        'is_active' => true,
        'last_online' => '2026-11-23 10:30:21',
        'ed25519_private_key' => 'ED-PRIV-1',
        'ed25519_public_key' => 'ED-PUB-1',
        'wg_pk' => 'WG-PK-1',
        'wg_pub' => 'WG-PUB-1',
        'wg_psk' => 'WG-PSK-1',
    ],
    [
        'id' => 5,
        'uuid' => '5a855841-5027-42c9-84cb-881e9d728618',
        'telegram_id' => 1215191646,
        'name' => 'علیرضا اسکندری',
        'comment' => '09184774930',
        'current_usage_GB' => 0.328997977077961,
        'usage_limit_GB' => 1000,
        'package_days' => 367,
        'start_date' => '2026-06-02',
        'enable' => true,
        'is_active' => true,
        'last_online' => '2026-07-10 19:26:21',
    ],
    [
        'id' => 7,
        'uuid' => 'a7eec9c4-9f03-490c-894d-18485ff7e9b5',
        'telegram_id' => 5788643519,
        'name' => 'ریحانه سادات طباطبائی',
        'comment' => '09377767048',
        'current_usage_GB' => 51.4844611501321,
        'usage_limit_GB' => 1000,
        'package_days' => 365,
        'start_date' => '2025-11-22',
        'enable' => false,
        'is_active' => false,
        'last_online' => '2026-09-26 13:14:55',
    ],
    [
        'id' => 29,
        'uuid' => 'c72f32c4-cc61-4ed9-b879-3e3eb567e818',
        'telegram_id' => null,
        'name' => 'مراد اسکندری',
        'comment' => '09128916456',
        'current_usage_GB' => 3.76703046169132,
        'usage_limit_GB' => 999,
        'package_days' => 365,
        'start_date' => '2026-10-30',
        'enable' => true,
        'is_active' => true,
        'last_online' => '2026-11-23 09:36:21',
    ],
];

// 4a. Transaction rollback preserves old DB when an insert fails mid-way.
ServerClient::$ListResponse = ['StatusCode' => 200, 'Json' => $Sample_Payload];
Database::$FailNextInsert = true;
AdminFlow::autoUpdateAllUsers($Admin);
ok(Database::$RolledBack === true && Database::$Tables['Users'][0]['Telegram_ID'] === 999999, 'mid-sync failure rolls back entire database atomically');
Database::$FailNextInsert = false;

// 4b. Clean full replace succeeds.
TelegramClient::$Messages = [];
AdminFlow::autoUpdateAllUsers($Admin);
ok(count(Database::$Tables['Users']) === 3, 'Users replaced cleanly with the 3 users having valid telegram_id');
ok(Database::$Tables['Transactions'] === [] && Database::$Tables['Tickets'] === [] && Database::$Tables['App_Devices'] === [] && Database::$Tables['App_Sessions'] === [] && Database::$Tables['Usage_Snapshots'] === [], 'all user-related tables wiped cleanly');
ok(count(Database::$Tables['User_Sessions']) === 1 && Database::$Tables['User_Sessions'][0]['Telegram_ID'] === 592526230 && Database::$Tables['User_Sessions'][0]['Flow'] === null, 'non-admin sessions deleted and current admin session reset');

$SettingKeys = array_column(Database::$Tables['Settings'], 'Key');
ok(in_array('Robot_Status', $SettingKeys, true) && in_array('App_Gateway_Secret', $SettingKeys, true), 'bot Settings preserved');
ok(!in_array('App_Free_Claimed_stale-uuid', $SettingKeys, true) && !in_array('app_otp_cooldown_abc', $SettingKeys, true) && !in_array('DailyNotice_999', $SettingKeys, true) && !in_array('Nowruz_Claimed_2026_u_999', $SettingKeys, true), 'per-user transient Settings cleared');

$Armin = Repository::getUser(592526230);
ok(($Armin['Client_ID'] ?? '') === '9b9d9f5d-9841-45bf-a6b9-0479de273c11' && ($Armin['WireGuard_PSK'] ?? '') === 'WG-PSK-1' && ($Armin['Phone'] ?? '') === '09358983854', 'active user fields and keys imported');
$Alireza = Repository::getUser(1215191646);
ok(($Alireza['Subscription'] ?? '') === '۱ سال و ۲ روز', 'non-standard 367-day duration labeled accurately');
$Reyhaneh = Repository::getUser(5788643519);
ok((int)($Reyhaneh['Server_Enable'] ?? 1) === 0 && (int)($Reyhaneh['Server_Is_Active'] ?? 1) === 0 && ($Reyhaneh['Client_Status'] ?? '') === '🚫غیر فعال', 'disabled user stored inactive');

$AllTexts = implode("\n", array_column(TelegramClient::$Messages, 'text'));
ok(str_contains($AllTexts, 'c72f32c4-cc61-4ed9-b879-3e3eb567e818') && str_contains($AllTexts, 'مراد اسکندری'), 'missing telegram_id user reported with UUID for later single-user entry');

// 5. Single-user manual entry rejects bulk pairs, and accepts single telegram_id + uuid for missing user.
TelegramClient::$Messages = [];
AdminFlow::handleInput($Admin, 'admin:update_uid', "592526230\n9b9d9f5d-9841-45bf-a6b9-0479de273c11\n1215191646\n5a855841-5027-42c9-84cb-881e9d728618");
$LastMsg = end(TelegramClient::$Messages)['text'] ?? '';
ok(str_contains($LastMsg, 'ورود گروهی غیرفعال شده است') && count(Database::$Tables['Users']) === 3, 'single-user manual mode rejects bulk input');

// Phone-only input for an unlinked user must not turn phone number into Telegram_ID.
TelegramClient::$Messages = [];
ServerClient::$GetResponse = ['StatusCode' => 200, 'Json' => $Sample_Payload[3]];
AdminFlow::handleInput($Admin, 'admin:update_uid', "09128916456\nc72f32c4-cc61-4ed9-b879-3e3eb567e818");
ok(count(Database::$Tables['Users']) === 3 && Repository::getUser(9128916456) === [], 'unlinked phone does not create bogus numeric Telegram_ID');

// Entering numeric Telegram_ID + UUID for مراد اسکندری registers user and pushes telegram_id to panel.
ServerClient::$UpdateCalls = [];
AdminFlow::handleInput($Admin, 'admin:update_uid', "777888999\nc72f32c4-cc61-4ed9-b879-3e3eb567e818");
$Morad = Repository::getUser(777888999);
ok(($Morad['Client_ID'] ?? '') === 'c72f32c4-cc61-4ed9-b879-3e3eb567e818' && ($Morad['Full_Name'] ?? '') === 'مراد اسکندری', 'single-user manual mode adds user with numeric Telegram_ID');
ok(count(ServerClient::$UpdateCalls) === 1 && (int)(ServerClient::$UpdateCalls[0]['payload']['telegram_id'] ?? 0) === 777888999, 'single-user manual mode pushes telegram_id back to panel');

// 6. Static header & routing checks.
$ServerPhp = (string)file_get_contents(dirname(__DIR__) . '/Core/Server/Umbrella-Server.php');
$AdminPhp = (string)file_get_contents(dirname(__DIR__) . '/Bot/Admin.php');
$DispatchPhp = (string)file_get_contents(dirname(__DIR__) . '/Bot/Dispatcher.php');
ok(str_contains($ServerPhp, "'Watashi-API-Key'") && str_contains($ServerPhp, "'Hiddify-API-Key'"), 'ServerClient sends Watashi-API-Key and Hiddify-API-Key');
ok(!str_contains($ServerPhp, "\u{200C}") && !str_contains($AdminPhp, "\u{200C}"), 'no ZWNJ in Umbrella-Server.php or Admin.php');
ok(str_contains($DispatchPhp, "'admin_users_auto_sync'") && str_contains($DispatchPhp, "'admin_users_single_sync'"), 'Dispatcher routes both auto and single user sync callbacks');

echo "admin_bulk_user_sync_test: {$Passed} checks passed\n";
