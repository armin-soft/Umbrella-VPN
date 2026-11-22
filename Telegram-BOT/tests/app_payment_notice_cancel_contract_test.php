<?php
declare(strict_types=1);
$gateway = file_get_contents(__DIR__ . '/../Core/App/App-Gateway.php');
$checks = [
    'cancel endpoint uses a conditional transition for pending challenges only' => str_contains($gateway, "if (\$Route === 'auth/cancel')") && str_contains($gateway, "['cancelled', time(), \$Challenge, 'needs_telegram', 'awaiting_telegram']"),
    'cancel cannot overwrite approval' => str_contains($gateway, "if ((string)\$Row['Stage'] !== 'cancelled') self::fail(409, 'already_decided'"),
    'confirmation and rollback respect concurrent cancellation' => str_contains($gateway, "\$Rollback_Stage === 'needs_telegram' ? 'awaiting_telegram' : \$Rollback_Stage") && str_contains($gateway, "[\$Rollback_Stage, \$Challenge, 'awaiting_telegram']"),
    'automatic sign-in notice links to device management' => str_contains($gateway, "'callback_data' => 'user_device_menu'") && str_contains($gateway, "'callback_data' => 'app_devices'"),
    'payment notifications occur for app topups and both purchase paths' => substr_count($gateway, 'self::appPaymentNotice(') === 3,
    'notification failure does not invalidate committed purchase' => str_contains($gateway, '[Umbrella-Bot][App-Payment-Notice] delivery failed'),
];
foreach ($checks as $name => $ok) {
    if (!$ok) throw new RuntimeException($name);
}
echo 'app_payment_notice_cancel_contract_test: ' . count($checks) . " checks passed\n";
