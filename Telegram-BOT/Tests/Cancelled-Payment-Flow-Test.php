<?php
declare(strict_types=1);
final class Zarinpal {
public static bool $paid = false;
public static int $calls = 0;
public static function validAuthority(string $a): bool { return preg_match('/^A[0-9]{35}$/D', $a) === 1; }
public static function isConfigured(): bool { return true; }
public static function verify(float $amount, string $authority): array { self::$calls++; return ['Ok'=>self::$paid, 'RefId'=>self::$paid ? '12345' : '']; }
}
final class TelegramClient { public static array $messages=[]; public static function sendSystemMessage(int $id,string $text): void { self::$messages[]=$text; } }
final class Repository {
public static array $session=[];
public static array $archived=[];
public static float $balance=0;
public static bool $locked=false;
public static function tryCronLock(string $name,int $ttl): bool { if (self::$locked) return false; self::$locked=true; return true; }
public static function releaseCronLock(string $name): void { self::$locked=false; }
public static function archivePendingPayment(int $id,string $hash): bool {
$p=self::$session['Pending_Payment'] ?? ''; if ($p==='') return false;
if (!hash_equals(hash('sha256',$p),$hash)) throw new RuntimeException('payment_changed');
[$type,$amount,$authority]=explode('|',$p); $credit=(float)(self::$session['Pending_Topup'] ?? 0);
if ($credit<=0 || $credit>(float)$amount) throw new RuntimeException('payment_cannot_cancel_safely');
self::$archived[$authority]=['Status'=>'pending','Amount'=>$amount,'Credit'=>$credit]; self::$session=[]; return true;
}
public static function getUserSession(int $id): array { return self::$session; }
public static function cancelledPayment(int $id,string $a): ?array { return $id===1 ? (self::$archived[$a] ?? null) : null; }
public static function touchCancelledPayment(int $id,string $a): void {}
public static function settleCancelledPayment(int $id,string $a,string $ref): bool { if (self::$archived[$a]['Status'] !== 'pending') return false; self::$archived[$a]['Status']='settled'; self::$balance+=(float)self::$archived[$a]['Credit']; return true; }
}
$src=file_get_contents(__DIR__.'/../Bot/Subscription.php'); eval(substr($src,strpos($src,'final class SubscriptionFlow {')));
function check(bool $ok,string $message): void { if (!$ok) throw new RuntimeException($message); }
$a='A'.str_repeat('1',35); $b='A'.str_repeat('2',35); $p='topup|100|'.$a;
Repository::$session=['Pending_Payment'=>$p,'Pending_Topup'=>'90'];
try { SubscriptionFlow::cancelAppPayment(1,str_repeat('a',64)); throw new RuntimeException('stale accepted'); } catch (RuntimeException $e) { check($e->getMessage()==='payment_changed','stale request'); }
check(!Repository::$locked, 'lock released after error');
check(SubscriptionFlow::cancelAppPayment(1,hash('sha256',$p)), 'cancel archived');
Repository::$session=['Pending_Payment'=>'topup|200|'.$b,'Pending_Topup'=>'190'];
SubscriptionFlow::handleGatewayCallback(1,'OK',$a);
check(Repository::$balance===0.0 && Repository::$archived[$a]['Status']==='pending', 'unpaid order stays recoverable');
check(!SubscriptionFlow::recoverCancelledPayment(2,$a), 'foreign account rejected');
Zarinpal::$paid=true;
SubscriptionFlow::handleGatewayCallback(1,'OK',$a);
check(Repository::$balance===90.0 && count(TelegramClient::$messages)===1, 'verified late payment credits net amount and notifies');
check(Repository::$session['Pending_Payment']==='topup|200|'.$b, 'new order unchanged');
SubscriptionFlow::handleGatewayCallback(1,'OK',$a);
check(Repository::$balance===90.0 && count(TelegramClient::$messages)===1, 'duplicate callback harmless');
echo "cancelled_payment_flow_test: passed\n";
