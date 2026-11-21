<?php
declare(strict_types=1);

$Gateway = (string)file_get_contents(__DIR__ . '/../Core/App/App-Gateway.php');
$Flow = (string)file_get_contents(__DIR__ . '/../Bot/Subscription.php');
$Index = (string)file_get_contents(__DIR__ . '/../index.php');
$Checks = [
    'wallet and paid plans reject empty or placeholder account IDs' => str_contains($Gateway, "if (\$UUID === '' || \$UUID === '_') self::fail(409, 'account_not_linked'"),
    'authenticated paid-plan catalog endpoint' => str_contains($Gateway, 'if ($Route === \'subscription/plans\')') && str_contains($Gateway, 'self::sessionRow(self::bearer())'),
    'purchase endpoint validates the authenticated account and server-side month tariff' => str_contains($Gateway, 'if ($Route === \'subscription/purchase\')') && str_contains($Gateway, '\\SubscriptionFlow::appPlanCatalog()'),
    'wallet purchase delegates to the bot activation flow' => str_contains($Gateway, '\\SubscriptionFlow::purchaseFromAppWallet($UserId, $Month, $Quote)'),
    'checkout creates a ZarinPal order and persists the bot pending-order fields' => str_contains($Flow, 'Zarinpal::request($Shortage') && str_contains($Flow, "'Pending_Plan' => 'paid|' . " . '$Month_Key') && str_contains($Flow, "'Pending_Payment' => " . '$Month_Key'),
    'app and bot purchases share the same per-user lock' => str_contains($Flow, "'subscription_purchase_' . " . '$User_ID') && str_contains($Flow, "'subscription_purchase_' . " . '$Context->UserId'),
    'payment callback still verifies exact user and authority in the existing callback handler' => str_contains($Flow, 'public static function handleGatewayCallback(int $User_ID, string $Status, string $Authority)') && str_contains($Flow, 'hash_equals($Parts[2], $Authority)') && str_contains($Index, 'handleGatewayCallback($User_ID, $Status, (string)$_GET[\'Authority\'])'),
    'app cannot mark a payment verified or activate from a client-supplied success flag' => !str_contains($Gateway, "['paid']") && !str_contains($Gateway, "'Status' => 'verified'"),
    'paid purchase route is advertised to clients' => str_contains($Gateway, "'subscription_purchase'"),
];
foreach ($Checks as $Name => $Ok) {
    if (!$Ok) {
        fwrite(STDERR, "FAIL: {$Name}\n");
        exit(1);
    }
}
echo 'app_paid_purchase_contract_test: ' . count($Checks) . " checks passed\n";
