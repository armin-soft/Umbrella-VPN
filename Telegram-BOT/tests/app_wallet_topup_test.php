<?php
declare(strict_types=1);
// Behavioral test of the production wallet checkout against isolated dependencies.
final class BotConfig {}
final class Repository {
public static array $session = []; public static bool $locked = false; public static float $balance = 1250.5;
public static function tryCronLock(string $name, int $ttl): bool { if (self::$locked) return false; self::$locked=true; return true; }
public static function releaseCronLock(string $name): void { self::$locked=false; }
public static function getUserSession(int $id): array { return self::$session; }
public static function getUser(int $id): array { return ['Phone'=>'09123456789']; }
public static function getBalance(int $id): float { return self::$balance; }
public static function updateUserSession(int $id,array $fields): void { self::$session=array_merge(self::$session,$fields); }
}
final class Environment {
public static float $min=1000; public static function getMinimumPaymentAmount(): float { return self::$min; }
public static function getPaymentCallbackUrl(): string { return 'https://example.test/index.php'; }
}
final class Helper { public static function normalizePhone(string $p): string { return $p; } }
final class Zarinpal {
public static bool $configured=true; public static bool $fail=false; public static int $calls=0;
public static function isConfigured(): bool { return self::$configured; }
public static function request(float $amount,string $callback,string $description,string $phone): ?array {
self::$calls++; if (self::$fail) return null;
return ['Authority'=>'A'.str_repeat('1',35), 'RedirectUrl'=>'https://pay.example.test', 'Amount'=>$amount+100.5,'Fee'=>100.5, 'Original_Amount'=>$amount];
}
public static function validAuthority(string $x): bool { return preg_match('/^A[0-9]{35}$/D',$x)===1; }
public static function bridgeUrl(string $x,int $id=0): string { return 'https://example.test/Pay.php?a='.$x.'&u='.$id; }
public static function startPayUrl(string $x): string { return 'https://pay.example.test/'.$x; }
public static function payLink(array $p): string { return $p['BridgeUrl'] ?? $p['RedirectUrl'] ?? ''; }
}
$code=file_get_contents(__DIR__.'/../Bot/Subscription.php'); eval(substr($code,strpos($code,'final class SubscriptionFlow {')));
$gateway=file_get_contents(__DIR__.'/../Core/App/App-Gateway.php'); eval(substr($gateway,strpos($gateway,'final class AppGateway {')));
$n=0; function check(bool $ok,string $why): void { global $n; $n++; if (!$ok) throw new RuntimeException($why); }
function fails(callable $fn,string $expected): void { try { $fn(); } catch (Throwable $e) { check($e->getMessage()===$expected, 'expected '.$expected.' got '.$e->getMessage()); return; } throw new RuntimeException('expected '.$expected); }
$terms=SubscriptionFlow::appWalletTerms();
check($terms['min_topup']===80000 && $terms['max_topup']===100000000,'minimum equals Telegram wallet minimum');
Environment::$min=90000; fails(fn()=>SubscriptionFlow::startAppWalletTopup(1,80000),'invalid_topup'); Environment::$min=1000;
foreach ([0,-1,79999,100000001] as $x) fails(fn()=>SubscriptionFlow::startAppWalletTopup(1,$x),'invalid_topup');
check(Zarinpal::$calls===0,'invalid input never creates order');
Repository::$locked=true; fails(fn()=>SubscriptionFlow::startAppWalletTopup(1,80000),'purchase_busy'); Repository::$locked=false;
Repository::$session=['Pending_Payment'=>'another']; fails(fn()=>SubscriptionFlow::startAppWalletTopup(1,80000),'payment_pending');
check(Repository::$session['Pending_Payment']==='another' && Zarinpal::$calls===0,'existing order is never replaced');
Repository::$session=[]; Zarinpal::$configured=false; fails(fn()=>SubscriptionFlow::startAppWalletTopup(1,80000),'gateway_unavailable'); Zarinpal::$configured=true;
Zarinpal::$fail=true; fails(fn()=>SubscriptionFlow::startAppWalletTopup(1,80000),'gateway_request_failed');
check(Repository::$session===[] && !Repository::$locked,'failed gateway leaves no pending order and releases lock'); Zarinpal::$fail=false;
$payment=SubscriptionFlow::startAppWalletTopup(1,80000);
check($payment['Amount']===80100.5 && $payment['Fee']===100.5,'exact quoted gateway fee and amount preserved');
check(Repository::$session['Pending_Topup']==='80000' && Repository::$session['Pending_Plan']===null && Repository::$session['Pending_Custom_Plan']===null,'only original amount is wallet credit');
check(Repository::$session['Pending_Payment']==='topup|80100.5|A'.str_repeat('1',35),'gross amount and authority persisted');
check(Repository::$balance===1250.5 && !Repository::$locked,'wallet is never credited before provider verification');
fails(fn()=>SubscriptionFlow::startAppWalletTopup(1,80000),'payment_pending');
$payload=(new ReflectionMethod(AppGateway::class,'walletPayload'))->invoke(null,1);
check($payload['balance']===1250.5 && $payload['pending_wallet_topup'] && $payload['payment_pending'], 'status reads shared wallet and pending topup');
check($payload['pending_amount']===80100.5 && $payload['pending_credit']===80000.0 && str_contains($payload['checkout_url'],'u=1'), 'status offers same order with exact amounts');
Repository::$session['Pending_Plan']='paid|1';
$payload=(new ReflectionMethod(AppGateway::class,'walletPayload'))->invoke(null,1);
check($payload['payment_pending'] && !$payload['pending_wallet_topup'] && $payload['checkout_url']==='', 'subscription order is not exposed as wallet topup');
Repository::$session['Pending_Plan']=null; Repository::$session['Pending_Payment']='topup|80100.5|bad';
$payload=(new ReflectionMethod(AppGateway::class,'walletPayload'))->invoke(null,1);
check($payload['payment_pending'] && $payload['checkout_url']==='', 'malformed authority cannot be surfaced as a payment link');
check(str_contains($gateway,"if (\$Route === 'wallet/topup')") && str_contains($gateway,"SubscriptionFlow::recoverPendingPayment(\$UserId)"), 'wallet uses authenticated routes and existing server verification');
echo "app_wallet_topup_test: $n checks passed\n";
