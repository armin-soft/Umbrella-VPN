<?php
declare(strict_types=1);
// Execute the production subscription methods against controlled external dependencies.
final class BotConfig {
public static float $rate = 1000;
public static function getCustomDayRate(): float { return self::$rate; }
public static function getCustomMinDays(): int { return 2; }
public static function getCustomMaxDays(): int { return 60; }
public static function getCustomMinGB(): float { return 0.1; }
public static function getCustomMaxGB(): float { return 500; }
}
final class Repository {
public static array $session = []; public static float $balance = 3000; public static bool $locked = false;
public static function tryCronLock(string $name, int $seconds): bool { if (self::$locked) return false; self::$locked=true; return true; }
public static function releaseCronLock(string $name): void { self::$locked=false; }
public static function getUserSession(int $id): array { return self::$session; }
public static function getBalance(int $id): float { return self::$balance; }
public static function getUser(int $id): array { return ['Phone'=>'09123456789']; }
public static function updateUserSession(int $id, array $fields): void { self::$session=array_merge(self::$session, $fields); }
}
final class Environment {
public static function getMinimumPaymentAmount(): int { return 1000; }
public static function getPaymentCallbackUrl(): string { return 'https://example.test/callback'; }
}
final class Helper {
public static function toPersian(string $x): string { return $x; }
public static function formatGB(float $x): string { return $x . ' GB'; }
public static function normalizePhone(string $x): string { return $x; }
}
final class Zarinpal {
public static int $calls=0;
public static function isConfigured(): bool { return true; }
public static function request(float $amount, string $callback, string $description, string $phone): array {
self::$calls++; return ['Authority'=>'authority', 'RedirectUrl'=>'https://pay.example.test', 'Amount'=>$amount+100, 'Fee'=>100];
}
}
$Source = file_get_contents(__DIR__ . '/../Bot/Subscription.php');
eval(substr($Source, strpos($Source, 'final class SubscriptionFlow {')));
$Count=0;
function check(bool $ok, string $message): void { global $Count; $Count++; if (!$ok) throw new RuntimeException($message); }
function fails(callable $fn, string $message): void { try { $fn(); } catch (Throwable $e) { check($e->getMessage()===$message, 'expected '.$message.', got '.$e->getMessage()); return; } throw new RuntimeException('expected '.$message); }
$terms=SubscriptionFlow::appCustomPlanTerms();
check($terms['day_rate']===1000.0 && $terms['min_days']===2 && $terms['min_gb']===0.1, 'live tariff and bounds');
foreach ([[1, 10.0], [61, 10.0], [2, 0.01], [2, 501.0], [2, INF]] as [$days, $gb]) {
fails(fn()=>SubscriptionFlow::startAppCustomCheckout(1, $days, $gb), 'invalid_custom_plan');
}
check(Zarinpal::$calls===0, 'invalid inputs never request payment');
BotConfig::$rate=0; fails(fn()=>SubscriptionFlow::startAppCustomCheckout(1, 10, 5.0), 'custom_plan_unavailable'); BotConfig::$rate=1000;
Repository::$session=['Pending_Payment'=>'existing']; fails(fn()=>SubscriptionFlow::startAppCustomCheckout(1, 10, 5.0), 'payment_pending');
Repository::$session=[]; Repository::$locked=true; fails(fn()=>SubscriptionFlow::startAppCustomCheckout(1, 10, 5.0), 'purchase_busy'); Repository::$locked=false;
Repository::$balance=10000; fails(fn()=>SubscriptionFlow::startAppCustomCheckout(1, 10, 5.0), 'wallet_changed');
Repository::$balance=9500; fails(fn()=>SubscriptionFlow::startAppCustomCheckout(1, 10, 5.0), 'below_gateway_minimum');
Repository::$balance=3000;
fails(fn()=>SubscriptionFlow::startAppCustomCheckout(1, 10, 5.5, 9000), 'price_changed');
check(Zarinpal::$calls===0 && !Repository::$locked, 'stale quote releases lock without charging');
$result=SubscriptionFlow::startAppCustomCheckout(1, 10, 5.5);
check($result['Plan_Price']===10000 && $result['Wallet_Balance']===3000, 'price and balance from server');
check(Repository::$session['Pending_Custom_Plan']==='10|10000|5.5' && Repository::$session['Pending_Topup']==='7000', 'custom plan and shortfall persisted for existing callback');
check(Repository::$session['Pending_Payment']==='topup|7100|authority', 'gateway fee and authority persisted');
check(!Repository::$locked && Zarinpal::$calls===1, 'lock released and order created once');
fails(fn()=>SubscriptionFlow::purchaseCustomFromAppWallet(1, 10, 5.5), 'payment_pending');
fails(fn()=>SubscriptionFlow::startAppCustomCheckout(1, 10, 5.5), 'payment_pending');
echo "app_custom_purchase_test: $Count checks passed\n";
