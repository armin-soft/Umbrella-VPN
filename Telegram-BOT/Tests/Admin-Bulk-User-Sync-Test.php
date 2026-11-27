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
    public static array $DeletesExecuted = [];
    public static bool $FailNextInsert = false;
    public static bool $RolledBack = false;
    private static array $Snapshot = [];

    public static function getInstance(): self {
        return self::$Inst ??= new self();
    }

    public static function resetMock(): void {
        self::$Tables = [
            'Users' => [
                [
                    'Telegram_ID' => 999999,
                    'Chat_ID' => 999999,
                    'Client_ID' => 'other-uuid',
                    'Full_Name' => 'کاربر قدیمی',
                    'First_Name' => 'کاربر قدیمی',
                    'Balance' => 50000,
                    'Is_Blocked' => 0,
                    'Free_Plan_Claimed' => 0,
                ],
                [
                    'Telegram_ID' => 592526230,
                    'Chat_ID' => 592526230,
                    'Client_ID' => '9b9d9f5d-9841-45bf-a6b9-0479de273c11',
                    'Full_Name' => 'آرمین قدیمی',
                    'First_Name' => 'آرمین',
                    'Phone' => '09358983854',
                    'Balance' => 250000,
                    'Is_Blocked' => 0,
                    'Free_Plan_Claimed' => 1,
                    'Registered_At' => '2025-01-01 00:00:00',
                    'Used_Usage_GB' => 10.0,
                ],
            ],
            'Transactions' => [
                ['ID' => 1, 'User_ID' => 592526230, 'Amount' => 250000],
            ],
            'Tickets' => [['ID' => 1, 'User_ID' => 999999]],
            'App_Devices' => [
                ['Device_ID' => 'dev-1', 'User_UUID' => '9b9d9f5d-9841-45bf-a6b9-0479de273c11', 'Telegram_ID' => 0],
            ],
            'App_Sessions' => [
                ['Token_Hash' => 'tok-1', 'User_UUID' => '9b9d9f5d-9841-45bf-a6b9-0479de273c11', 'Telegram_ID' => null],
            ],
            'User_Sessions' => [
                ['Telegram_ID' => 592526230, 'Flow' => 'admin:test'],
                ['Telegram_ID' => 888888, 'Flow' => 'user:ticket'],
            ],
            'Settings' => [
                ['Key' => 'Robot_Status', 'Value' => '🟢روشن'],
                ['Key' => 'App_Gateway_Secret', 'Value' => 'keep-secret'],
            ],
        ];
        self::$DeletesExecuted = [];
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
        if (stripos(ltrim($Sql), 'DELETE') === 0) {
            self::$DeletesExecuted[] = $Sql;
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
            return new stdClass();
        }
        if (str_starts_with($Sql, 'UPDATE `App_Devices` SET `Telegram_ID` = ?')) {
            $Tid = (int)($Params[0] ?? 0);
            $Uuid = (string)($Params[1] ?? '');
            foreach (self::$Tables['App_Devices'] as &$Row) {
                if ((string)($Row['User_UUID'] ?? '') === $Uuid && (int)($Row['Telegram_ID'] ?? 0) === 0) {
                    $Row['Telegram_ID'] = $Tid;
                }
            }
            return new stdClass();
        }
        if (str_starts_with($Sql, 'UPDATE `App_Sessions` SET `Telegram_ID` = ?')) {
            $Tid = (int)($Params[0] ?? 0);
            $Uuid = (string)($Params[1] ?? '');
            foreach (self::$Tables['App_Sessions'] as &$Row) {
                if ((string)($Row['User_UUID'] ?? '') === $Uuid && (int)($Row['Telegram_ID'] ?? 0) === 0) {
                    $Row['Telegram_ID'] = $Tid;
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

    public static function findUserByPhone(string $Phone, int $Exclude = 0): array {
        $Norm = Helper::normalizePhone($Phone);
        foreach (Database::$Tables['Users'] ?? [] as $Row) {
            if ((int)($Row['Telegram_ID'] ?? 0) !== $Exclude && $Norm !== '' && Helper::normalizePhone((string)($Row['Phone'] ?? '')) === $Norm) {
                return $Row;
            }
        }
        return [];
    }

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
ok(ServerClient::$ListCalls === 0 && count(Database::$Tables['Users']) === 2, 'non-admin rejected before API or DB touch');

// 3. Panel API failure or empty list preserves DB untouched.
ServerClient::$ListResponse = ['StatusCode' => 502, 'Json' => null, 'Body' => 'Bad Gateway'];
AdminFlow::autoUpdateAllUsers($Admin);
ok(count(Database::$Tables['Users']) === 2 && count(Database::$Tables['Transactions']) === 1, 'HTTP 502 preserves existing DB untouched');

ServerClient::$ListResponse = ['StatusCode' => 200, 'Json' => []];
AdminFlow::autoUpdateAllUsers($Admin);
ok(count(Database::$Tables['Users']) === 2 && count(Database::$Tables['Transactions']) === 1, 'empty API response preserves existing DB untouched');

// 4. Non-destructive bulk update & add with real panel output format.
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

// 4a. Transaction rollback preserves DB when insert fails mid-sync.
ServerClient::$ListResponse = ['StatusCode' => 200, 'Json' => $Sample_Payload];
Database::$FailNextInsert = true;
AdminFlow::autoUpdateAllUsers($Admin);
ok(Database::$RolledBack === true && count(Database::$Tables['Users']) === 2 && (float)Repository::getUser(592526230)['Used_Usage_GB'] === 10.0, 'mid-sync failure rolls back atomically');
Database::$FailNextInsert = false;

// 4b. Non-destructive upsert succeeds: zero deletes, old users/tables kept, existing updated, new added.
TelegramClient::$Messages = [];
AdminFlow::autoUpdateAllUsers($Admin);
ok(Database::$DeletesExecuted === [], 'zero DELETE queries executed during autoUpdateAllUsers');
ok(count(Database::$Tables['Users']) === 4, 'existing non-panel user 999999 preserved, existing 592526230 updated, and 2 new users added');
ok(count(Database::$Tables['Transactions']) === 1 && count(Database::$Tables['Tickets']) === 1 && count(Database::$Tables['User_Sessions']) === 2, 'transactions, tickets, and user sessions completely preserved');

$ExistingOld = Repository::getUser(999999);
ok((int)($ExistingOld['Balance'] ?? 0) === 50000 && ($ExistingOld['Full_Name'] ?? '') === 'کاربر قدیمی', 'pre-existing user not on server retains balance and data');

$Armin = Repository::getUser(592526230);
ok(($Armin['Full_Name'] ?? '') === 'آرمین اسکندری' && ($Armin['WireGuard_PSK'] ?? '') === 'WG-PSK-1' && (float)($Armin['Used_Usage_GB'] ?? 0) === 436.64, 'existing user server fields updated');
ok((int)($Armin['Balance'] ?? 0) === 250000 && (int)($Armin['Free_Plan_Claimed'] ?? 0) === 1 && ($Armin['Registered_At'] ?? '') === '2025-01-01 00:00:00', 'existing user wallet balance, free-plan flag, and registered timestamp preserved');

ok((int)(Database::$Tables['App_Devices'][0]['Telegram_ID'] ?? 0) === 592526230 && (int)(Database::$Tables['App_Sessions'][0]['Telegram_ID'] ?? 0) === 592526230, 'app devices and sessions Telegram_ID backfilled without deleting rows');

$Alireza = Repository::getUser(1215191646);
ok(($Alireza['Subscription'] ?? '') === '۱ سال و ۲ روز', 'new user added with accurate 367-day duration label');
$Reyhaneh = Repository::getUser(5788643519);
ok((int)($Reyhaneh['Server_Enable'] ?? 1) === 0 && (int)($Reyhaneh['Server_Is_Active'] ?? 1) === 0 && ($Reyhaneh['Client_Status'] ?? '') === '🚫غیر فعال', 'disabled new user stored inactive');

$AllTexts = implode("\n", array_column(TelegramClient::$Messages, 'text'));
ok(str_contains($AllTexts, 'c72f32c4-cc61-4ed9-b879-3e3eb567e818') && str_contains($AllTexts, 'مراد اسکندری'), 'missing telegram_id user reported with UUID for later single-user entry');

// 5. Single-user manual entry rejects bulk pairs, and accepts single telegram_id + uuid for missing user.
TelegramClient::$Messages = [];
AdminFlow::handleInput($Admin, 'admin:update_uid', "592526230\n9b9d9f5d-9841-45bf-a6b9-0479de273c11\n1215191646\n5a855841-5027-42c9-84cb-881e9d728618");
$LastMsg = end(TelegramClient::$Messages)['text'] ?? '';
ok(str_contains($LastMsg, 'ورود گروهی غیرفعال شده است') && count(Database::$Tables['Users']) === 4, 'single-user manual mode rejects bulk input');

// Phone-only input for an unlinked user must not turn phone number into Telegram_ID.
TelegramClient::$Messages = [];
ServerClient::$GetResponse = ['StatusCode' => 200, 'Json' => $Sample_Payload[3]];
AdminFlow::handleInput($Admin, 'admin:update_uid', "09128916456\nc72f32c4-cc61-4ed9-b879-3e3eb567e818");
ok(count(Database::$Tables['Users']) === 4 && Repository::getUser(9128916456) === [], 'unlinked phone does not create bogus numeric Telegram_ID');

// Entering numeric Telegram_ID + UUID for مراد اسکندری registers user and pushes telegram_id to panel.
ServerClient::$UpdateCalls = [];
AdminFlow::handleInput($Admin, 'admin:update_uid', "777888999\nc72f32c4-cc61-4ed9-b879-3e3eb567e818");
$Morad = Repository::getUser(777888999);
ok(($Morad['Client_ID'] ?? '') === 'c72f32c4-cc61-4ed9-b879-3e3eb567e818' && ($Morad['Full_Name'] ?? '') === 'مراد اسکندری', 'single-user manual mode adds user with numeric Telegram_ID');
ok(count(ServerClient::$UpdateCalls) === 1 && (int)(ServerClient::$UpdateCalls[0]['payload']['telegram_id'] ?? 0) === 777888999, 'single-user manual mode pushes telegram_id back to panel');

// Subsequent bulk sync recognizes linked Client_ID even while panel response still has telegram_id: null.
TelegramClient::$Messages = [];
AdminFlow::autoUpdateAllUsers($Admin);
$AllTexts2 = implode("\n", array_column(TelegramClient::$Messages, 'text'));
ok(!str_contains($AllTexts2, 'کاربران فاقد آیدی عددی'), 'already-linked Client_ID updates cleanly without missing-ID warning');

// 6. Static header, non-destructive guarantee, & routing checks.
$ServerPhp = (string)file_get_contents(dirname(__DIR__) . '/Core/Server/Umbrella-Server.php');
$AdminPhp = (string)file_get_contents(dirname(__DIR__) . '/Bot/Admin.php');
$DispatchPhp = (string)file_get_contents(dirname(__DIR__) . '/Bot/Dispatcher.php');
$BulkStart = strpos($AdminPhp, 'public static function autoUpdateAllUsers(');
$BulkEnd = strpos($AdminPhp, 'private static function unwrapServerUserRows(', (int)$BulkStart);
$BulkBody = $BulkStart !== false && $BulkEnd !== false ? substr($AdminPhp, $BulkStart, $BulkEnd - $BulkStart) : '';
ok($BulkBody !== '' && !str_contains(strtoupper($BulkBody), 'DELETE FROM'), 'autoUpdateAllUsers contains zero DELETE FROM statements');
ok(str_contains($ServerPhp, "'Watashi-API-Key'") && str_contains($ServerPhp, "'Hiddify-API-Key'"), 'ServerClient sends Watashi-API-Key and Hiddify-API-Key');
ok(!str_contains($ServerPhp, "\u{200C}") && !str_contains($AdminPhp, "\u{200C}"), 'no ZWNJ in Umbrella-Server.php or Admin.php');
ok(str_contains($DispatchPhp, "'admin_users_auto_sync'") && str_contains($DispatchPhp, "'admin_users_single_sync'"), 'Dispatcher routes both auto and single user sync callbacks');

echo "admin_bulk_user_sync_test: {$Passed} checks passed\n";
