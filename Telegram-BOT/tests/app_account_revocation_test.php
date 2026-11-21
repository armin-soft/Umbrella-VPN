<?php
declare(strict_types=1);

final class Database {
    public static ?Database $Instance = null;
    public static array $Queries = [];
    public static bool $Fail = false;

    public static function getInstance(): Database {
        return self::$Instance ??= new Database();
    }

    public function transaction(callable $callback): mixed {
        return $callback($this);
    }

    public function execute(string $query, array $parameters = []): void {
        if (self::$Fail) throw new RuntimeException('simulated database outage');
        self::$Queries[] = [$query, $parameters];
    }
}

$source = (string)file_get_contents(dirname(__DIR__) . '/Core/App/Account-Revocation.php');
$source = preg_replace('/^require_once .*;\s*$/m', '', $source) ?? $source;
$source = preg_replace('/^<\?php\s*declare\(strict_types=1\);/', '', $source) ?? $source;
$source = preg_replace('/\?>\s*$/', '', $source) ?? $source;
eval($source);

function checkAccountRevocation(bool $ok, string $message): void {
    if (!$ok) throw new RuntimeException($message);
}

checkAccountRevocation(!AppAccountRevocation::revoke('') && !AppAccountRevocation::revoke('_')
    && Database::$Queries === [], 'empty and placeholder account IDs are ignored');
checkAccountRevocation(AppAccountRevocation::revoke('panel-user-123'), 'valid account revocation succeeds');
checkAccountRevocation(count(Database::$Queries) === 6, 'sessions, device links, sign-in and bot-link requests, notices and filters are cleaned');
checkAccountRevocation(str_contains(Database::$Queries[0][0], 'UPDATE `App_Sessions`')
    && str_contains(Database::$Queries[0][0], '`Revoked_At` = CURRENT_TIMESTAMP'), 'all live session tokens are revoked');
checkAccountRevocation(str_contains(Database::$Queries[1][0], 'DELETE FROM `App_Bot_Link_Requests`'), 'pending Telegram links are removed');
checkAccountRevocation(str_contains(Database::$Queries[2][0], 'DELETE FROM `App_SignIn_Requests`'), 'pending sign-in approvals are removed');
checkAccountRevocation(str_contains(Database::$Queries[3][0], 'DELETE FROM `App_Notifications`'), 'stale account notifications are removed');
checkAccountRevocation(str_contains(Database::$Queries[4][0], '`Is_Trusted` = 0')
    && str_contains(Database::$Queries[4][0], '`User_UUID` = NULL'), 'all linked devices lose trust and their account link');
checkAccountRevocation(str_contains(Database::$Queries[5][0], 'DELETE FROM `App_Filter_Settings`'), 'account-specific app filter settings are removed');
Database::$Fail = true;
checkAccountRevocation(!AppAccountRevocation::revoke('panel-user-123'), 'database failures are contained and reported');
$adminSource = (string)file_get_contents(dirname(__DIR__) . '/Bot/Admin.php');
checkAccountRevocation(str_contains($adminSource, 'AppAccountRevocation::revoke($Client_ID)'), 'admin panel deletion revokes app sessions immediately');

echo "OK app account revocation\n";
