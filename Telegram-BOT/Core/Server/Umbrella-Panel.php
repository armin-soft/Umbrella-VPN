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
private static int $Last_Get_Status = 0;
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

/** One customer record by uuid, with automatic retry on transient errors. */
public static function get(string $UUID): ?array {
self::$Last_Get_Status = 0;
$UUID = trim($UUID);

if ($UUID === '') return null;

$Url = self::usersUrl() . rawurlencode($UUID) . '/';

for ($Try = 1; $Try <= 2; $Try++) {
$Response = HttpClient::get($Url, ServerClient::headers(), 15);
$Status = (int)($Response['StatusCode'] ?? 0);
self::$Last_Get_Status = $Status;
$Json = $Response['Json'] ?? null;

if ($Status >= 200 && $Status < 300 && is_array($Json)) {
$Record = self::extractRecord($Json);

if ($Record !== null) return $Record;
}

if ($Status === 404 || ($Status >= 400 && $Status < 500 && $Status !== 408 && $Status !== 429)) {
return null;
}

if ($Try < 2) {
usleep(250000);
}
}

return null;
}

/** HTTP status of the most recent get() call (0 on transport error). */
public static function lastGetStatus(): int {
return self::$Last_Get_Status;
}

/**
 * Creates a customer for an app sign-up using the exact Hiddify v2 admin user
 * schema proven in ServerClient::createUser(), with transient error retries.
 */
public static function create(array $Payload): ?array {
$Today = (new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran')))->format('Y-m-d');
$Phone = trim((string)($Payload['phone'] ?? ''));
unset($Payload['phone']);

$Comment = trim((string)($Payload['comment'] ?? ''));
if ($Comment === '') {
$Comment = $Phone !== '' ? $Phone : 'Umbrella VPN';
}

$Body = array_merge([
'name' => '',
'usage_limit_GB' => 3,
'package_days' => 1,
'comment' => $Comment,
'telegram_id' => 0,
'start_date' => $Today,
'mode' => 'no_reset',
'lang' => 'fa',
'current_usage_GB' => 0,
'is_active' => true,
'enable' => true,
'added_by_uuid' => Environment::getUmbrellaApiKey(),
'uuid' => null,
'last_online' => null,
'last_reset_time' => null,
], $Payload);
$Body['comment'] = $Comment;
$Body['usage_limit_GB'] = (int)$Body['usage_limit_GB'];
$Body['package_days'] = (int)$Body['package_days'];
$Body['telegram_id'] = (int)$Body['telegram_id'];

$Response = ['StatusCode' => 0, 'Body' => '', 'Json' => null, 'Error' => ''];

for ($Try = 1; $Try <= 3; $Try++) {
$Response = HttpClient::post(self::usersUrl(), $Body, ServerClient::postHeaders(), 20);
$Status = (int)($Response['StatusCode'] ?? 0);
$Json = $Response['Json'] ?? null;

if ($Status >= 200 && $Status < 300 && is_array($Json)) {
$Record = self::extractRecord($Json);

if ($Record !== null) return $Record;
}

if ($Status >= 400 && $Status < 500 && $Status !== 408 && $Status !== 429) {
break;
}

if ($Try < 3) {
usleep(350000);
}
}

error_log(
'[Umbrella-Bot][Panel-API] create failed | HTTP=' . (int)($Response['StatusCode'] ?? 0)
. ' | curl=' . (string)($Response['Error'] ?? '')
. ' | body=' . mb_substr((string)($Response['Body'] ?? ''), 0, 300)
);
return null;
}

private static function extractRecord(array $Json): ?array {
if (isset($Json['uuid']) && trim((string)$Json['uuid']) !== '') {
return $Json;
}

foreach (['data', 'user', 'item', 'result'] as $Key) {
if (isset($Json[$Key]) && is_array($Json[$Key]) && trim((string)($Json[$Key]['uuid'] ?? '')) !== '') {
return $Json[$Key];
}
}

return null;
}

/** PATCH the fields the bot is allowed to change. */
public static function update(string $UUID, array $Payload): ?array {
$UUID = trim($UUID);
if ($UUID === '' || $Payload === []) return null;

if (array_key_exists('telegram_id', $Payload)) {
$Payload['telegram_id'] = max(0, (int)$Payload['telegram_id']);
}

$Url = self::usersUrl() . rawurlencode($UUID) . '/';
$Response = ['StatusCode' => 0, 'Body' => '', 'Json' => null, 'Error' => ''];

for ($Try = 1; $Try <= 2; $Try++) {
$Response = HttpClient::patch($Url, $Payload, ServerClient::postHeaders(), 20);
$Status = (int)($Response['StatusCode'] ?? 0);
$Json = $Response['Json'] ?? null;

if ($Status >= 200 && $Status < 300) {
if (is_array($Json) && self::extractRecord($Json) !== null) {
return self::extractRecord($Json);
}
$Verified = self::get($UUID);
if ($Verified !== null) {
return $Verified;
}
return array_merge(['uuid' => $UUID], $Payload);
}

if (is_array($Json) && $Status === 0 && self::extractRecord($Json) !== null) {
return self::extractRecord($Json);
}

if ($Status >= 400 && $Status < 500 && $Status !== 408 && $Status !== 429) {
break;
}

if ($Try < 2) {
usleep(250000);
}
}

error_log(
'[Umbrella-Bot][Panel-API] update failed for uuid=' . $UUID
. ' | HTTP=' . (int)($Response['StatusCode'] ?? 0)
. ' | curl=' . (string)($Response['Error'] ?? '')
. ' | body=' . mb_substr((string)($Response['Body'] ?? ''), 0, 250)
);
return null;
}

/**
 * Ensures the numeric Telegram id is written to the panel account and read
 * back cleanly so bot, server, and apps stay synchronized.
 */
public static function linkTelegramId(string $UUID, int $Telegram_Id, ?array $Current_Panel = null): ?array {
$UUID = trim($UUID);
if ($UUID === '' || $UUID === '_' || $Telegram_Id <= 0) {
return null;
}

$Current = is_array($Current_Panel) && $Current_Panel !== [] ? $Current_Panel : self::get($UUID);
if (is_array($Current) && (int)($Current['telegram_id'] ?? 0) === $Telegram_Id) {
return $Current;
}

self::update($UUID, ['telegram_id' => $Telegram_Id]);
$Fresh = self::get($UUID);
if (is_array($Fresh) && (int)($Fresh['telegram_id'] ?? 0) === $Telegram_Id) {
return $Fresh;
}

$Base = is_array($Fresh) && $Fresh !== [] ? $Fresh : (is_array($Current) ? $Current : []);
$Fallback_Payload = ['telegram_id' => $Telegram_Id];
if (isset($Base['name']) && trim((string)$Base['name']) !== '') {
$Fallback_Payload['name'] = (string)$Base['name'];
}
if (array_key_exists('comment', $Base)) {
$Fallback_Payload['comment'] = (string)($Base['comment'] ?? '');
}
if (isset($Base['usage_limit_GB']) && is_numeric($Base['usage_limit_GB'])) {
$Fallback_Payload['usage_limit_GB'] = (float)$Base['usage_limit_GB'];
}
if (isset($Base['package_days']) && is_numeric($Base['package_days'])) {
$Fallback_Payload['package_days'] = (int)$Base['package_days'];
}
if (array_key_exists('is_active', $Base)) {
$Fallback_Payload['is_active'] = (bool)$Base['is_active'];
}
if (array_key_exists('enable', $Base)) {
$Fallback_Payload['enable'] = (bool)$Base['enable'];
}

$Url = self::usersUrl() . rawurlencode($UUID) . '/';
$Fallback_Res = HttpClient::patch($Url, $Fallback_Payload, ServerClient::postHeaders(), 20);
$Verified = self::get($UUID);
if (is_array($Verified) && (int)($Verified['telegram_id'] ?? 0) === $Telegram_Id) {
return $Verified;
}

error_log(
'[Umbrella-Bot][Panel-API] linkTelegramId verification failed for uuid=' . $UUID
. ' tg=' . $Telegram_Id
. ' | HTTP=' . (int)($Fallback_Res['StatusCode'] ?? 0)
. ' | body=' . mb_substr((string)($Fallback_Res['Body'] ?? ''), 0, 250)
);
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
elseif (isset($Json['results']) && is_array($Json['results'])) $Rows = $Json['results'];
elseif (isset($Json['records']) && is_array($Json['records'])) $Rows = $Json['records'];

// A bare list is also valid.
if ($Rows === null && array_is_list($Json)) $Rows = $Json;

if ($Rows === null) {
return $Fail('response JSON has no rows (keys: ' . implode(',', array_keys($Json)) . ')');
}

self::$Last_List_Count = count($Rows);
return $Rows;
}

/** Configured subscription base URL including the panel's secret path slug. */
public static function subscriptionLinkBase(): string {
$Configured = '';

if (class_exists('Repository', false) && method_exists('Repository', 'getSetting')) {
try {
$Configured = trim((string)(Repository::getSetting('Subscription_Link_Base') ?? ''));
} catch (Throwable) {
$Configured = '';
}
}

if ($Configured === '' && method_exists('Environment', 'getSubscriptionLinkBase')) {
$Configured = trim(Environment::getSubscriptionLinkBase());
}

if ($Configured !== '' && str_starts_with($Configured, 'http')) {
$Clean = (string)preg_replace(
'#/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(?:/.*)?$#',
'',
rtrim($Configured, '/')
);
return rtrim($Clean, '/') . '/';
}

return '';
}

/** The share-link base (before `<uuid>/sub/`) for a personal account. */
public static function accountBase(array $Row): string {
$Configured = self::subscriptionLinkBase();

if ($Configured !== '') {
return $Configured;
}

$Candidates = ['account_base', 'sub_base', 'subscription_base', 'sub_domain'];

foreach ($Candidates as $Key) {
$Value = trim((string)($Row[$Key] ?? ''));

if ($Value !== '' && str_starts_with($Value, 'http')) {
$Clean = (string)preg_replace(
'#/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(?:/.*)?$#',
'',
rtrim($Value, '/')
);
return rtrim($Clean, '/') . '/';
}
}

$Base = rtrim(Environment::getUmbrellaBaseUrl(), '/');
$Parts = parse_url($Base);
$Host = is_array($Parts) && !empty($Parts['host'])
? (($Parts['scheme'] ?? 'https') . '://' . $Parts['host'])
: '';

return $Host === '' ? '' : $Host . '/';
}
}
?>
