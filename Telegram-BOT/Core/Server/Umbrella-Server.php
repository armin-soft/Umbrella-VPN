<?php
declare(strict_types=1);

require_once __DIR__ . '/../Support/Http.php';
require_once dirname(__DIR__, 2) . '/Config/Environment.php';

final class ServerClient {
private const JSON_HEADERS = ['Accept' => 'application/json'];
private function __construct() {
}

public static function headers(): array {
return self::JSON_HEADERS + ['Hiddify-API-Key' => Environment::getUmbrellaApiKey()];
}

public static function postHeaders(): array {
return self::JSON_HEADERS + ['Content-Type' => 'application/json', 'Hiddify-API-Key' => Environment::getUmbrellaApiKey()];
}

public static function createUser(string $Name, int|string $Usage_Limit_GB, int $Package_Days, string $Comment, int $Telegram_ID): array {
$Today = (new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran')))->format('Y-m-d');
$Payload = [
'name' => $Name,
'usage_limit_GB' => (int)$Usage_Limit_GB,
'package_days' => $Package_Days,
'comment' => $Comment,
'telegram_id' => $Telegram_ID,
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
];

$Response = HttpClient::post(Environment::getUmbrellaBaseUrl(), $Payload, self::postHeaders());
return $Response;
}

public static function getUser(string $Client_ID): array {
return HttpClient::get(Environment::getUmbrellaBaseUrl() . $Client_ID . '/', self::headers());
}

public static function updateUser(string $Client_ID, array $Payload): array {
return HttpClient::patch(Environment::getUmbrellaBaseUrl() . $Client_ID . '/', $Payload, self::postHeaders());
}

public static function deleteUser(string $Client_ID): array {
return HttpClient::delete(Environment::getUmbrellaBaseUrl() . $Client_ID . '/', self::headers());
}

public static function serverStatus(): array {
return self::getWithRetry('/server_status/');
}

public static function allConfigs(): array {
return self::getWithRetry('/all-configs/');
}

private static function getWithRetry(string $Path, int $Attempts = 4): array {
$Url = preg_replace('#/user/?$#', $Path, Environment::getUmbrellaBaseUrl());
$Response = ['StatusCode' => 0, 'Body' => '', 'Json' => null, 'Error' => 'no attempt'];

for ($Try = 1; $Try <= max(1, $Attempts); $Try++) {
$Response = HttpClient::get((string)$Url, self::headers(), 30);

if ((int)($Response['StatusCode'] ?? 0) === 200) {
return $Response;
}

if ($Try < $Attempts) {
usleep(400000);
}
}

return $Response;
}

public static function listUsers(): array {
return HttpClient::get(rtrim(Environment::getUmbrellaBaseUrl(), '/') . '/', self::headers());
}

public static function updateUserUsage(): array {
$Url = preg_replace('#/user/?$#', '/update_user_usage/', Environment::getUmbrellaBaseUrl());
return HttpClient::get($Url, self::headers());
}

public static function liveUsers(): array {
$Response = self::listUsers();
$Rows = $Response['Json'] ?? null;

if (!is_array($Rows) || (int)($Response['StatusCode'] ?? 0) >= 300) {
return [];
}

$Live = [];

foreach ($Rows as $Row) {
if (!is_array($Row)) continue;
$Telegram_ID = (int)($Row['telegram_id'] ?? 0);
$Uuid = trim((string)($Row['uuid'] ?? ''));

if ($Telegram_ID <= 0 || $Uuid === '') continue;
$Used = max(0.0, (float)($Row['current_usage_GB'] ?? 0));
$Limit = max(0.0, (float)($Row['usage_limit_GB'] ?? 0));
$Live[] = [
'Telegram_ID' => $Telegram_ID,
'Client_ID' => $Uuid,
'Full_Name' => trim((string)($Row['name'] ?? '')) ?: 'کاربر',
'First_Name' => trim((string)($Row['name'] ?? '')) ?: 'کاربر',
'Username' => '',
'Value' => $Used,
'Used_Usage_GB' => $Used,
'Total_Usage_GB' => $Limit,
'Remaining_Usage_GB' => max(0.0, $Limit - $Used),
'Percent_Usage' => $Limit > 0 ? round(($Used / $Limit) * 100, 1) : 0.0,
'Server_Is_Active' => !empty($Row['is_active']) ? 1 : 0,
'Server_Enable' => !empty($Row['enable']) ? 1 : 0,
'Client_Status' => !empty($Row['is_active']) ? 'فعال' : 'غیرفعال',
'Last_Online' => (string)($Row['last_online'] ?? ''),
];
}

usort($Live, static fn(array $A, array $B): int => $B['Value'] <=> $A['Value'] ?: strcasecmp((string)$A['Full_Name'], (string)$B['Full_Name']));
return $Live;
}

public static function liveServerStats(array $Rows): array {
$Total = count($Rows);
$Active = 0;
$Used = 0.0;

foreach ($Rows as $Row) {
if ((int)($Row['Server_Is_Active'] ?? 0) === 1) $Active++;
$Used += (float)($Row['Value'] ?? 0);
}

return ['total' => $Total, 'active' => $Active, 'disabled' => $Total - $Active,
'total_used' => $Used, 'avg_used' => $Total > 0 ? $Used / $Total : 0.0,
'top_user' => $Rows[0] ?? []];
}

}
?>