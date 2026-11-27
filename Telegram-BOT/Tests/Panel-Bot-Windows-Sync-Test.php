<?php
declare(strict_types=1);

error_reporting(E_ALL);
set_error_handler(static function (int $Severity, string $Message, string $File, int $Line): never {
    throw new ErrorException($Message, 0, $Severity, $File, $Line);
});

require_once dirname(__DIR__) . '/Bot/Menu.php';

final class Context {
    public int $UserId = 1;
    public int $ChatId = 1;
}

final class BotConfig {
    public static function getChannelUrl(): string { return 'https://t.me/test'; }
}

final class TelegramClient {
    public static function inlineKeyboard(array $Rows): array { return ['inline_keyboard' => $Rows]; }
    public static function sendMessage(int $ChatId, string $Text, array $Markup = []): void {}
}

final class Helper {
    public static function userGreeting(Context $C, string $S): string { return $S; }
    public static function userFooter(): string { return ''; }
    public static function gregorianToJalali(string $Date): string { return 'J:' . $Date; }
    public static function durationLabel(int $Days): string { return $Days . ' روز'; }
    public static function toEnglish(string $Value): string {
        return strtr($Value, ['۰'=>'0','۱'=>'1','۲'=>'2','۳'=>'3','۴'=>'4','۵'=>'5','۶'=>'6','۷'=>'7','۸'=>'8','۹'=>'9']);
    }
    public static function stripZwnj(string $Text): string { return str_replace("\u{200C}", '', $Text); }
    public static function normalizePhone(string $Phone): string {
        $Digits = preg_replace('/[^0-9]/', '', self::toEnglish($Phone)) ?? '';
        if (str_starts_with($Digits, '98') && strlen($Digits) === 12) $Digits = '0' . substr($Digits, 2);
        return $Digits;
    }
    public static function validatePhone(string $Phone): bool { return preg_match('/^09[0-9]{9}$/', $Phone) === 1; }
    public static function detectOperator(string $Phone): string { return str_starts_with($Phone, '0912') ? 'همراه اول' : 'ایرانسل'; }
    public static function repairMojibake(string $Text): string { return $Text; }
}

final class Repository {
    public static array $Users = [];
    public static array $Settings = [];
    public static array $Updates = [];

    public static function getUser(int $Id): array { return self::$Users[$Id] ?? []; }
    public static function getUserByClientId(string $Client): array {
        foreach (self::$Users as $User) {
            if (($User['Client_ID'] ?? '') === $Client) return $User;
        }
        return [];
    }
    public static function findUserByPhone(string $Phone, int $ExcludeId = 0): array {
        foreach (self::$Users as $Id => $User) {
            if ((int)$Id !== $ExcludeId && ($User['Phone'] ?? '') === $Phone) return $User;
        }
        return [];
    }
    public static function updateUser(int $Id, array $Fields): void {
        self::$Updates[] = [$Id, $Fields];
        self::$Users[$Id] = array_merge(self::$Users[$Id] ?? ['Telegram_ID' => $Id], $Fields);
    }
    public static function getSetting(string $Key, mixed $Default = ''): mixed { return self::$Settings[$Key] ?? $Default; }
    public static function setSetting(string $Key, string $Value): void { self::$Settings[$Key] = $Value; }
}

final class ServerClient {
    public static array $GetResponse = ['StatusCode' => 200, 'Json' => null];
    public static array $ListResponse = ['StatusCode' => 200, 'Json' => []];
    public static array $UpdateCalls = [];

    public static function getUser(string $Client): array { return self::$GetResponse; }
    public static function listUsers(): array { return self::$ListResponse; }
    public static function updateUser(string $Client, array $Fields): array {
        self::$UpdateCalls[] = [$Client, $Fields];
        return ['StatusCode' => 200, 'Json' => array_merge(['uuid' => $Client], $Fields)];
    }
}

final class PanelClient {
    public static ?array $ByTg = null;
    public static ?array $ByPhone = null;
    public static function findByTelegramId(int $Id): ?array { return self::$ByTg; }
    public static function findByPhone(string $Phone): ?array { return self::$ByPhone; }
}

final class AppAccountRevocation {
    public static array $Revoked = [];
    public static function revoke(string $Client): bool {
        self::$Revoked[] = $Client;
        return true;
    }
}

$CommonSource = (string)file_get_contents(dirname(__DIR__) . '/Bot/Common.php');
$CommonClass = substr($CommonSource, (int)strpos($CommonSource, 'final class Common {'));
eval((string)preg_replace('/\?>\s*$/', '', $CommonClass));

$Passed = 0;
function assertSync(bool $Ok, string $Message): void {
    global $Passed;
    if (!$Ok) {
        fwrite(STDERR, "FAIL: {$Message}\n");
        exit(1);
    }
    $Passed++;
}

// 1. Two-way sync of profile, keys, status, dates, quota, and free marker.
Repository::$Users = [
    101 => [
        'Telegram_ID' => 101,
        'Client_ID' => 'uuid-101',
        'Full_Name' => 'کاربر آمبرلا',
        'Phone' => '',
        'Subscription' => '۱ روزه',
        'Package_Duration' => '۱',
        'Client_Status' => '🚫غیر فعال',
        'Deactivation_Message' => 'مسدود موقت',
        'Channel_Client_Disabled_At' => 123456,
        'Free_Plan_Claimed' => 0,
    ],
];
Repository::$Settings = ['App_Free_Claimed_uuid-101' => '1'];
ServerClient::$UpdateCalls = [];
ServerClient::$GetResponse = [
    'StatusCode' => 200,
    'Json' => [
        'uuid' => 'uuid-101',
        'name' => 'سارا رضایی',
        'comment' => '09121112233',
        'telegram_id' => 0,
        'start_date' => '2026-11-20',
        'package_days' => 30,
        'usage_limit_GB' => 60,
        'current_usage_GB' => 12.5,
        'last_online' => '2026-11-22 10:15:00',
        'is_active' => true,
        'enable' => true,
        'ed25519_private_key' => 'ed-priv',
        'ed25519_public_key' => 'ed-pub',
        'wg_pk' => 'wg-priv',
        'wg_pub' => 'wg-pub',
        'wg_psk' => 'wg-psk',
    ],
];

$Synced = Common::syncSubscriptionFromServer(Repository::$Users[101]);
assertSync(($Synced['Full_Name'] ?? '') === 'سارا رضایی', 'syncs non-placeholder full name from panel');
assertSync(($Synced['Phone'] ?? '') === '09121112233', 'syncs valid phone from server comment');
assertSync(($Synced['Operator'] ?? '') === 'همراه اول', 'detects operator from synced phone');
assertSync(($Synced['Subscription'] ?? '') === '30 روز', 'updates subscription label when package_days changes');
assertSync((int)($Synced['Package_Duration'] ?? 0) === 30, 'updates Package_Duration from panel');
assertSync(($Synced['Package_Start_Date'] ?? '') === 'J:2026-11-20', 'formats start date');
assertSync(($Synced['Expiration_Date'] ?? '') === 'J:2026-12-20', 'computes expiration date in Tehran timezone');
assertSync((float)($Synced['Total_Usage_GB'] ?? 0) === 60.0 && (float)($Synced['Remaining_Usage_GB'] ?? 0) === 47.5, 'syncs quota and remaining GB');
assertSync(($Synced['WireGuard_PSK'] ?? '') === 'wg-psk' && ($Synced['ED_25519_Public_Key'] ?? '') === 'ed-pub', 'syncs all connection keys');
assertSync(($Synced['Client_Status'] ?? '') === '✅فعال' && (int)($Synced['Server_Is_Active'] ?? 0) === 1 && (int)($Synced['Server_Enable'] ?? 0) === 1, 'marks active/enabled client active');
assertSync(array_key_exists('Deactivation_Message', $Synced) && $Synced['Deactivation_Message'] === null && array_key_exists('Channel_Client_Disabled_At', $Synced) && $Synced['Channel_Client_Disabled_At'] === null, 'clears stale deactivation markers on reactivation');
assertSync((int)($Synced['Free_Plan_Claimed'] ?? 0) === 1, 'propagates App_Free_Claimed marker to bot user');
assertSync(count(ServerClient::$UpdateCalls) === 1 && (ServerClient::$UpdateCalls[0][1]['telegram_id'] ?? 0) === 101, 'pushes missing telegram_id back to panel');

// 2. Placeholder panel name does not clobber real bot profile; instead bot profile is pushed to panel.
Repository::$Users[202] = [
    'Telegram_ID' => 202,
    'Client_ID' => 'uuid-202',
    'Full_Name' => 'امیر کریمی',
    'Phone' => '09129998877',
    'Free_Plan_Claimed' => 1,
];
ServerClient::$UpdateCalls = [];
ServerClient::$GetResponse = [
    'StatusCode' => 200,
    'Json' => [
        'uuid' => 'uuid-202',
        'name' => 'user-202',
        'comment' => '',
        'telegram_id' => 0,
        'is_active' => true,
        'enable' => false,
    ],
];
$Synced2 = Common::syncSubscriptionFromServer(Repository::$Users[202]);
assertSync(($Synced2['Full_Name'] ?? '') === 'امیر کریمی', 'placeholder panel name does not overwrite real bot name');
assertSync(($Synced2['Client_Status'] ?? '') === '🚫غیر فعال' && (int)($Synced2['Server_Enable'] ?? 1) === 0, 'enable=false forces inactive client status');
assertSync(Repository::getSetting('App_Free_Claimed_uuid-202') === '1', 'bot Free_Plan_Claimed flag mirrors to App_Free_Claimed setting');
assertSync(
    count(ServerClient::$UpdateCalls) === 1
    && (ServerClient::$UpdateCalls[0][1]['name'] ?? '') === 'امیر کریمی'
    && (ServerClient::$UpdateCalls[0][1]['comment'] ?? '') === '09129998877'
    && (ServerClient::$UpdateCalls[0][1]['telegram_id'] ?? 0) === 202,
    'pushes missing name, comment, and telegram_id from bot to panel'
);

// 3. Unlinked local user discovers existing panel account by Telegram ID.
Repository::$Users[303] = [
    'Telegram_ID' => 303,
    'Client_ID' => '',
    'Full_Name' => 'کاربر جدید',
];
PanelClient::$ByTg = [
    'uuid' => 'uuid-303',
    'telegram_id' => 303,
    'name' => 'رضا نادری',
    'usage_limit_GB' => 10,
    'current_usage_GB' => 0,
    'is_active' => true,
    'enable' => true,
];
$Discovered = Common::syncSubscriptionFromServer(Repository::$Users[303]);
assertSync(($Discovered['Client_ID'] ?? '') === 'uuid-303' && ($Discovered['Full_Name'] ?? '') === 'رضا نادری', 'discovers panel row by telegram_id when Client_ID is blank');
PanelClient::$ByTg = null;

// 4. Panel HTTP 404 revokes app sessions and wipes stale local subscription fields.
Repository::$Users[404] = [
    'Telegram_ID' => 404,
    'Client_ID' => 'uuid-deleted',
    'Subscription' => '۱ ماهه',
    'WireGuard_PSK' => 'old-psk',
    'Client_Status' => '✅فعال',
    'Server_Is_Active' => 1,
    'Server_Enable' => 1,
];
AppAccountRevocation::$Revoked = [];
ServerClient::$GetResponse = ['StatusCode' => 404, 'Json' => null];
$Deleted = Common::syncSubscriptionFromServer(Repository::$Users[404]);
assertSync(AppAccountRevocation::$Revoked === ['uuid-deleted'], '404 triggers app revocation for deleted UUID');
assertSync(array_key_exists('Client_ID', $Deleted) && $Deleted['Client_ID'] === null && array_key_exists('WireGuard_PSK', $Deleted) && $Deleted['WireGuard_PSK'] === null, '404 wipes Client_ID and keys');
assertSync(($Deleted['Client_Status'] ?? '') === '🚫حذف شده' && (int)($Deleted['Server_Is_Active'] ?? 1) === 0, '404 marks user deleted and inactive');

// 5. Static contracts across PHP sync files.
$Root = dirname(__DIR__);
$Gateway = (string)file_get_contents($Root . '/Core/App/App-Gateway.php');
$Panel = (string)file_get_contents($Root . '/Core/Server/Umbrella-Panel.php');
$Server = (string)file_get_contents($Root . '/Core/Server/Umbrella-Server.php');
$Profile = (string)file_get_contents($Root . '/Bot/Profile.php');
$Admin = (string)file_get_contents($Root . '/Bot/Admin.php');
$Scheduler = (string)file_get_contents($Root . '/Bot/Scheduler.php');
$AutoRenew = (string)file_get_contents($Root . '/Core/Subscription/Auto-Renew.php');
$AppBotLink = (string)file_get_contents($Root . '/Core/App/App-Bot-Link.php');

assertSync(!str_contains($Gateway, "\u{200C}") && !str_contains($Panel, "\u{200C}") && !str_contains($Server, "\u{200C}"), 'no ZWNJ in gateway/panel/server files');
assertSync(str_contains($Panel, 'return self::extractRecord($Json);'), 'PanelClient::update unwraps enveloped panel payloads');
assertSync(str_contains($Gateway, "\$Payload['bot_linked'] = \$LinkedTg > 0") && str_contains($Gateway, 'self::accountPayloadWithExtras($PanelAccount, $UUID, $LinkedTg, $ChannelState)'), 'heartbeat returns live account and bot_linked status');
assertSync(str_contains($Gateway, 'syncLinkedBotUserFromPanel'), 'AppGateway links and syncs bot/panel/device records');
assertSync(str_contains($Profile, "touchUserTime(\$Context->UserId, 'Profile_Updated_At')") && str_contains($Profile, 'UPDATE `App_Sessions` SET `Telegram_ID`'), 'Profile flow updates timestamp and backfills device/session Telegram IDs');
assertSync(str_contains($Admin, '$Server_Active_Effective = $Server_Is_Active && $Server_Enable;'), 'Admin updatePair treats enable=false as inactive');
assertSync(str_contains($Scheduler, 'Common::syncSubscriptionFromServer($User, $Row)') && str_contains($Scheduler, 'Repository::allUserIds()'), 'Scheduler refreshUsagesNow uses full two-way sync and reconciles 404 deletions');
assertSync(str_contains($AutoRenew, "'Server_Is_Active' => 1") && str_contains($AutoRenew, "'WireGuard_PSK'"), 'Auto-Renew writes full status and key columns');
assertSync(str_contains($AppBotLink, "Common::syncSubscriptionFromServer"), 'AppBotLink confirm triggers post-link sync');

echo "panel_bot_windows_sync_test: {$Passed} checks passed\n";
