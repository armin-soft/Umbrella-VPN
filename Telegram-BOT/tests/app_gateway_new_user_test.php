<?php
declare(strict_types=1);

/**
 * Regression suite for new-user sign-in reliability across Windows x64 clients:
 * - Form-encoded `_json` fallback & BOM handling in AppGateway::body()
 * - Resilient new-user flow when panel list has a transient hiccup
 * - Multi-table local UUID deduplication (Users, App_Devices, App_SignIn_Requests)
 * - Exact Hiddify v2 admin schema & retry handling in PanelClient::create()
 * - Multi-envelope list parsing in PanelClient::fullClientList()
 */

$Gateway_Path = dirname(__DIR__) . '/Core/App/App-Gateway.php';
$Panel_Path = dirname(__DIR__) . '/Core/Server/Umbrella-Panel.php';
$Server_Path = dirname(__DIR__) . '/Core/Server/Umbrella-Server.php';

$Gateway_Code = (string)file_get_contents($Gateway_Path);
$Panel_Code = (string)file_get_contents($Panel_Path);
$Server_Code = (string)file_get_contents($Server_Path);

$Assert = static function (bool $Condition, string $Message): void {
if (!$Condition) {
fwrite(STDERR, "FAIL: {$Message}\n");
exit(1);
}
};

// 1. Zero ZWNJ in all modified gateway/panel files.
foreach ([
'App-Gateway.php' => $Gateway_Code,
'Umbrella-Panel.php' => $Panel_Code,
'Umbrella-Server.php' => $Server_Code,
] as $Name => $Contents) {
$Assert(!str_contains($Contents, "\u{200C}"), "{$Name} must not contain ZWNJ (U+200C)");
}

// 2. AppGateway::body() unwraps form-encoded `_json` and strips UTF-8 BOM.
$Assert(str_contains($Gateway_Code, "\$_POST['_json']"), 'AppGateway::body() must accept form-encoded _json fallback');
$Assert(str_contains($Gateway_Code, '"\xEF\xBB\xBF"'), 'AppGateway::body() must strip UTF-8 BOM');

// 3. New users are not hard-blocked with 503 panel_unavailable at start().
$Assert(
!str_contains($Gateway_Code, 'refusing needs-profile while panel list is failing'),
'start() must not refuse new users when panel list temporarily fails'
);
$Assert(
str_contains($Gateway_Code, 'proceeding with new-user flow'),
'start() must log and continue new-user sign-in when panel list degrades'
);

// 4. Local DB deduplication checks Users, App_Devices, and App_SignIn_Requests,
//    and preserves known UUIDs on transient non-404 panel get errors.
$Assert(str_contains($Gateway_Code, 'FROM `App_Devices`'), 'findCustomerAccount() must check App_Devices');
$Assert(str_contains($Gateway_Code, 'FROM `App_SignIn_Requests`'), 'findCustomerAccount() must check App_SignIn_Requests');
$Assert(str_contains($Gateway_Code, 'PanelClient::lastGetStatus() !== 404'), 'findCustomerAccount() must preserve local UUID on non-404 panel errors');
$Assert(str_contains($Gateway_Code, 'syncBotUserClientId'), 'AppGateway must sync newly minted UUID back to Users.Client_ID');

// 5. PanelClient::create() matches Hiddify v2 admin schema (no bogus `phone`
//    default field, includes start_date, added_by_uuid, current_usage_GB,
//    telegram_id, and retries transient failures).
$Assert(str_contains($Panel_Code, "unset(\$Payload['phone'])"), 'PanelClient::create() must not send unsupported phone key');
$Assert(str_contains($Panel_Code, "'start_date' => \$Today"), 'PanelClient::create() must include start_date');
$Assert(str_contains($Panel_Code, "'added_by_uuid' => Environment::getUmbrellaApiKey()"), 'PanelClient::create() must include added_by_uuid');
$Assert(str_contains($Panel_Code, "'current_usage_GB' => 0"), 'PanelClient::create() must include current_usage_GB');
$Assert(str_contains($Panel_Code, "'results'"), 'PanelClient::fullClientList() must support results wrapper');
$Assert(str_contains($Panel_Code, "'records'"), 'PanelClient::fullClientList() must support records wrapper');

// 6. ServerClient::listUsers() retries transient failures.
$Assert(str_contains($Server_Code, 'public static function listUsers(int $Attempts = 2'), 'ServerClient::listUsers() must retry transient failures');

// 7. Behavioral test of AppGateway::body() via Reflection on form-encoded _json.
require_once dirname(__DIR__) . '/Core/Support/Helper.php';
require_once $Gateway_Path;

$Body_Method = new ReflectionMethod(AppGateway::class, 'body');

$_GET = ['AppApi' => 'auth/start'];
$_POST = [
'_json' => json_encode([
'phone' => '09123456789',
'device_id' => 'win64-device-01',
'first_name' => 'امیر حسین',
'last_name' => 'رضایی',
], JSON_UNESCAPED_UNICODE),
];

$Parsed = $Body_Method->invoke(null);
$Assert(is_array($Parsed) && ($Parsed['phone'] ?? '') === '09123456789', 'body() must decode _json phone');
$Assert(($Parsed['device_id'] ?? '') === 'win64-device-01', 'body() must decode _json device_id');
$Assert(($Parsed['first_name'] ?? '') === 'امیر حسین', 'body() must decode UTF-8 Persian first_name');

$_GET = [];
$_POST = [];

echo "app_gateway_new_user_test: OK\n";
