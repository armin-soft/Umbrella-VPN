<?php
declare(strict_types=1);

$Root = dirname(__DIR__);
$AppLink = (string)file_get_contents($Root . '/Bot/App-Link.php');
$Dispatcher = (string)file_get_contents($Root . '/Bot/Dispatcher.php');

$Checks = [
    'device rows are counted and loaded by a bounded page and offset' =>
        str_contains($AppLink, 'SELECT COUNT(*) FROM `App_Devices`') &&
        str_contains($AppLink, '$PageSize = 5;') &&
        str_contains($AppLink, 'LIMIT ? OFFSET ?'),
    'previous and next page callbacks are rendered only for multiple pages' =>
        str_contains($AppLink, "'app_devices_page:' . (\$Page - 1)") &&
        str_contains($AppLink, "'app_devices_page:' . (\$Page + 1)") &&
        str_contains($AppLink, '$PageCount > 1'),
    'the dispatcher routes pagination callbacks back to the requested page' =>
        str_contains($Dispatcher, "str_starts_with(\$Data, 'app_devices_page:')") &&
        str_contains($Dispatcher, "AppFlow::devices(\$Context, (int)substr(\$Data, strlen('app_devices_page:')))") ,
    'revocation confirmation preserves the current page' =>
        str_contains($AppLink, "'app_device_revoke_confirm:' . \$Prefix . ':' . \$Page") &&
        str_contains($AppLink, 'self::devices($Context, $Page);'),
];

$Failed = false;
foreach ($Checks as $Name => $Passed) {
    echo ($Passed ? 'PASS' : 'FAIL') . " — {$Name}\n";
    $Failed = $Failed || !$Passed;
}

exit($Failed ? 1 : 0);
