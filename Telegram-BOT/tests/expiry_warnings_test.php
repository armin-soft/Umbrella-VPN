<?php
declare(strict_types=1);

$Scheduler = (string)file_get_contents(__DIR__ . '/../Bot/Scheduler.php');
$Schema = (string)file_get_contents(__DIR__ . '/../Core/Database/Schema.php');
$SqlSchema = (string)file_get_contents(__DIR__ . '/../Database/Schema.SQL');

$Checks = [
    'the only expiry boundaries are three, two, and one days' =>
        str_contains($Scheduler, 'if ($Warn_3) $Boundaries[] = 3;') &&
        str_contains($Scheduler, 'if ($Warn_2) $Boundaries[] = 2;') &&
        str_contains($Scheduler, 'if ($Warn_1) $Boundaries[] = 1;') &&
        !str_contains($Scheduler, 'if ($Warn_0) $Boundaries[] = 0;'),
    'Telegram and SMS sends each have an idempotency key for the expiry event' =>
        str_contains($Scheduler, "\$Event . ':telegram'") &&
        str_contains($Scheduler, "\$Event . ':sms'") &&
        str_contains($Scheduler, "Repository::setSetting(\$Telegram_Key, '1')") &&
        str_contains($Scheduler, "Repository::setSetting(\$Sms_Key, '1')"),
    'the two-day SMS template is seeded for existing and fresh databases' =>
        str_contains($Schema, "'expire_warn_2'") &&
        str_contains($Schema, "['Expiry_Warning_2Days', '1']") &&
        str_contains($SqlSchema, "('Expiry_Warning_2Days', '1')"),
];

$Failed = false;
foreach ($Checks as $Name => $Passed) {
    echo ($Passed ? 'PASS' : 'FAIL') . " — {$Name}\n";
    $Failed = $Failed || !$Passed;
}

exit($Failed ? 1 : 0);
