<?php
declare(strict_types=1);

require_once __DIR__ . '/Umbrella-Server.php';
require_once dirname(__DIR__) . '/Support/Helper.php';
require_once dirname(__DIR__, 2) . '/Config/Environment.php';

/**
 * Customer lookups against the panel that the bot did not already need.
 *
 * ServerClient covers "my own client" operations; this adds the two calls the
 * new sign-in path needs: find an account by phone number and create one when
 * the person is new. Both use the same key and the same base URL, so a
 * deployment only has to be configured once.
 */
final class PanelClient {
private static ?string $Last_List_Error = null;
private static int $Last_List_Count = 0;
private function __construct() {
}

/** Human-readable reason the last panel list read failed, if it did. */
public static function lastListError(): ?string {
return self::$Last_List_Error;
}

/** How many customer rows the last panel list read returned. */
public static function lastListCount(): int {
return self::$Last_List_Count;
}

/** The v2 admin collection URL, derived from the configured user endpoint. */
private static function usersUrl(): string {
// The bot's env value is already the full `…/api/v2/admin/user/` endpoint.
return rtrim(Environment::getUmbrellaBaseUrl(), '/') . '/';
}

/**
 * Finds a customer by mobile number.
 *
 * Deployments differ in where the number lives: some panels expose a real
 * `phone` field, but this deployment stores the mobile in `comment` and the
 * numeric Telegram id in `telegram_id` — so both are compared, normalised
 * the same way. The `search` parameter is deliberately not used (it misses
 * stored formats); the comparison runs over the full list instead — the same
 * list the usage cron walks.
 */
public static function findByPhone(string $Phone): ?array {
$Phone = \Helper::normalizePhone($Phone);

if ($Phone === '') return null;

foreach (self::fullClientList() as $Row) {
foreach (['phone', 'Phone', 'comment', 'Comment'] as $Key) {
$Row_Phone = \Helper::normalizePhone((string)($Row[$Key] ?? ''));

if ($Row_Phone !== '' && $Row_Phone === $Phone) {
return $Row;
}
}
}

return null;
}

/** Finds a customer by Telegram id, used when the bot already knows the user. */
public static function findByTelegramId(int $Telegram_ID): ?array {
if ($Telegram_ID <= 0) return null;

foreach (self::fullClientList() as $Row) {
if ((int)($Row['telegram_id'] ?? 0) === $Telegram_ID) {
return $Row;
}
}

return null;
}

/** One customer record by uuid. */
public static function get(string $UUID): ?array {
$UUID = trim($UUID);

if ($UUID === '') return null;

$Response = HttpClient::get(self::usersUrl() . rawurlencode($UUID) . '/', ServerClient::headers());
$Json = $Response['Json'] ?? null;

if (!is_array($Json)) return null;
if (isset($Json['uuid'])) return $Json;
if (isset($Json['data']) && is_array($Json['data'])) return $Json['data'];

return null;
}

/**
 * Creates a customer for an app sign-up.
 *
 * `phone` is what the panel matches on and what the bot uses to tie the new
 * account to a Telegram user, so it is always sent normalised.
 */
public static function create(array $Payload): ?array {
$Body = array_merge([
'name' => '',
'phone' => '',
'comment' => 'Umbrella VPN',
'package_days' => 30,
'usage_limit_GB' => 100,
'mode' => 'no_reset',
'lang' => 'fa',
'enable' => true,
'is_active' => true,
], $Payload);

$Response = HttpClient::post(self::usersUrl(), $Body, ServerClient::postHeaders());
$Json = $Response['Json'] ?? null;

if (!is_array($Json)) {
error_log('[Umbrella-Bot][Panel-API] create failed: ' . mb_substr((string)($Response['Body'] ?? ''), 0, 300));
return null;
}

if (isset($Json['uuid'])) return $Json;
if (isset($Json['data']) && is_array($Json['data'])) return $Json['data'];

error_log('[Umbrella-Bot][Panel-API] create returned no uuid: ' . mb_substr((string)($Response['Body'] ?? ''), 0, 300));
return null;
}

/** PATCH the fields the bot is allowed to change. */
public static function update(string $UUID, array $Payload): ?array {
if ($UUID === '' || $Payload === []) return null;

$Response = HttpClient::patch(self::usersUrl() . rawurlencode($UUID) . '/', $Payload, ServerClient::postHeaders());
$Json = $Response['Json'] ?? null;

if (!is_array($Json)) return null;
if (isset($Json['uuid'])) return $Json;
if (isset($Json['data']) && is_array($Json['data'])) return $Json['data'];

return null;
}

/**
 * The full client list, parsed out of whichever shape the panel answers with.
 * No `search` parameter: it silently misses phones depending on how they are
 * stored, and the callers already normalise every row before comparing.
 */
private static function fullClientList(): array {
self::$Last_List_Error = null;
self::$Last_List_Count = 0;
$Response = ServerClient::listUsers();
$Status = (int)($Response['StatusCode'] ?? 0);
$Json = $Response['Json'] ?? null;
$Error = trim((string)($Response['Error'] ?? ''));
$Body = trim((string)($Response['Body'] ?? ''));

$Fail = static function (string $Reason) use ($Status, $Error, $Body): array {
self::$Last_List_Error = 'panel list failed | HTTP=' . $Status . ($Error !== '' ? ' | curl=' . $Error : '') . ' | body=' . mb_substr($Body, 0, 200) . ' | note=' . $Reason;
error_log('[Umbrella-Bot][Panel-API] ' . self::$Last_List_Error);
return [];
};

if (!is_array($Json)) {
return $Fail('response is not JSON');
}

if ($Status >= 300) {
return $Fail('HTTP status ' . $Status);
}

$Rows = null;

if (isset($Json['items']) && is_array($Json['items'])) $Rows = $Json['items'];
elseif (isset($Json['users']) && is_array($Json['users'])) $Rows = $Json['users'];
elseif (isset($Json['data']) && is_array($Json['data'])) $Rows = $Json['data'];

// A bare list is also valid.
if ($Rows === null && array_is_list($Json)) $Rows = $Json;

if ($Rows === null) {
return $Fail('response JSON has no rows (keys: ' . implode(',', array_keys($Json)) . ')');
}

self::$Last_List_Count = count($Rows);
return $Rows;
}

/** The share-link base for an account, when the panel reports it. */
public static function accountBase(array $Row): string {
$Candidates = ['account_base', 'sub_base', 'subscription_base', 'sub_domain'];

foreach ($Candidates as $Key) {
$Value = trim((string)($Row[$Key] ?? ''));

if ($Value !== '' && str_starts_with($Value, 'http')) {
return rtrim($Value, '/') . '/';
}
}

// The panel's own account page is derived from the configured base: the
// per-account slug sits in front of the uuid.
$Base = rtrim(Environment::getUmbrellaBaseUrl(), '/');
$Parts = parse_url($Base);
$Host = ($Parts['scheme'] ?? 'https') . '://' . ($Parts['host'] ?? '');
$UUID = trim((string)($Row['uuid'] ?? ''));

return $UUID === '' ? '' : $Host . '/' . $UUID . '/';
}
}
?>
