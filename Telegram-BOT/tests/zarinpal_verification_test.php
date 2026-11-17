<?php
declare(strict_types=1);
$N = 0;
function check(bool $Ok, string $Message): void { global $N; $N++; if (!$Ok) throw new RuntimeException($Message); }
function loadClass(string $File, string $Class): void {
$Code = file_get_contents(__DIR__ . '/../' . $File);
eval(preg_replace('/\?>\s*$/', '', substr($Code, strpos($Code, 'final class ' . $Class . ' {'))));
}
require_once __DIR__ . '/../Bot/Menu.php';
$Log = '/tmp/umbrella-zarin-test.log'; @unlink($Log); ini_set('error_log', $Log);
final class Environment {
public static function isZarinpalSandbox(): bool { return true; }
public static function getZarinpalMerchantId(): string { return 'test'; }
public static function getPaymentCallbackUrl(): string { return 'https://example.invalid/bot/index.php'; }
public static function getAdminUserId(): int { return 0; }
public static function getAdminFullName(): string { return 'admin'; }
}
final class HttpClient {
public static array $Response = []; public static int $Calls = 0; public static array $Payload = []; public static bool $Replace = false;
public static function post(string $Url, array $Payload, array $Headers): array {
self::$Calls++; self::$Payload = $Payload;
if (self::$Replace) Repository::$Session = ['Pending_Payment' => 'topup|200|NewAuthority', 'Pending_Topup' => '190'];
return self::$Response;
}
}
final class Context {
public function __construct(public array $Raw, public int $UserId, public int $ChatId, public string $FirstName, public bool $IsCallback, public ?string $CallbackData, public ?string $CallbackId, public ?int $MessageId, public ?string $Text) {}
public function profileName(): string { return 'test user'; }
}
final class Repository {
public static array $Session = []; public static int $Claims = 0; public static int $Records = 0; public static float $Balance = 0;
public static function getUserSession(int $Id): array { return self::$Session; }
public static function getUser(int $Id): array { return ['Chat_ID' => 1, 'First_Name' => 'test', 'Balance' => self::$Balance]; }
public static function getSetting(string $Key, mixed $Default = ''): mixed { return $Default; }
public static function claimPendingPayment(int $Id, string $Pending): bool {
self::$Claims++;
if ((self::$Session['Pending_Payment'] ?? '') !== $Pending) return false;
foreach (['Pending_Payment','Pending_Topup','Pending_Plan','Pending_Custom_Plan'] as $Key) self::$Session[$Key] = null;
return true;
}
public static function updateUserSession(int $Id, array $Fields): void { throw new RuntimeException('Unexpected unconditional order mutation'); }
public static function recordGatewayPayment(...$Args): void { self::$Records++; }
public static function addMoney(int $Id, float $Amount, ...$Args): void { self::$Balance += $Amount; }
}
final class Common {
public static function greet(Context $Context, string $Title): string { return $Title . "\n"; }
public static function backTo(string $Title, string $Call): array { return [Menu::button($Title, $Call)]; }
}
final class Helper { public static function __callStatic(string $Name, array $Args): string { return in_array($Name,['userFooter','adminFooter']) ? '' : (string)($Args[0] ?? ''); } }
final class TelegramClient {
public static array $Messages = []; public static array $Rows = [];
public static function inlineKeyboard(array $Rows): array { return $Rows; }
public static function sendMessage(int $Id, string $Text, array $Rows = []): array { self::$Messages[] = $Text; self::$Rows = $Rows; return ['ok'=>true]; }
public static function sendSystemMessage(int $Id, string $Text, array $Rows = []): array { return self::sendMessage($Id,$Text,$Rows); }
}
loadClass('Core/Payment/ZarinPal.php', 'Zarinpal');
loadClass('Bot/Subscription.php', 'SubscriptionFlow');
function resetCase(int $Code = -51, int $Http = 200): void {
Repository::$Session = ['Pending_Payment'=>'topup|100|AuthorityA','Pending_Topup'=>'90','Pending_Plan'=>'','Pending_Custom_Plan'=>''];
Repository::$Balance=0; Repository::$Claims=0; Repository::$Records=0;
HttpClient::$Calls=0; HttpClient::$Replace=false;
HttpClient::$Response = ['StatusCode'=>$Http,'Json'=>$Code<0 ? ['errors'=>['code'=>$Code,'message'=>'test provider response']] : ['data'=>['code'=>$Code,'ref_id'=>'123456','card_pan'=>'']], 'Error'=>'','Body'=>'test'];
TelegramClient::$Messages=[]; TelegramClient::$Rows=[];
}
$Context = new Context([],1,1,'test',false,null,null,null,null);
resetCase(); $Pending = Repository::$Session;
for ($I=0;$I<3;$I++) check(!SubscriptionFlow::recoverPendingPayment(1), 'unpaid recovery stays pending');
check(Repository::$Session === $Pending && Repository::$Balance === 0.0 && Repository::$Claims === 0, 'background -51 never erases or settles order');
check(TelegramClient::$Messages === [], 'background unpaid recovery does not spam customer');
check(!file_exists($Log) || file_get_contents($Log) === '', 'expected -51 does not flood error log');
SubscriptionFlow::verifyPayment($Context);
check(Repository::$Session === $Pending && Repository::$Claims === 0, 'manual -51 preserves order');
check(str_contains(end(TelegramClient::$Messages), 'هنوز') && !str_contains(end(TelegramClient::$Messages), 'منقضی'), 'manual unpaid state is not falsely called expired');
check(in_array('بررسی پرداخت', array_column(array_merge(...TelegramClient::$Rows), 'callback_data'), true), 'manual unpaid result offers recheck');
check(str_contains(TelegramClient::$Rows[0][0]['url'],'AuthorityA'), 'continue payment bound to same authority');
resetCase(-50); SubscriptionFlow::verifyPayment($Context);
check(Repository::$Claims===0 && Repository::$Session['Pending_Payment']!==null, 'amount mismatch never settles or discards order');
check(str_contains(end(TelegramClient::$Messages),'مطابقت ندارد'), 'amount mismatch has correct explanation');
check(str_contains(file_get_contents($Log),'code -50'), 'real API errors still logged');
resetCase(-51,500); Zarinpal::verify(100,'AuthorityA');
check(str_contains(file_get_contents($Log),'code -51'), 'HTTP server failure still logged even with -51');
foreach ([100,101] as $Code) {
resetCase($Code); check(SubscriptionFlow::recoverPendingPayment(1), 'accepted payment recovery completes');
check(HttpClient::$Calls === 1, 'recovery reuses same confirmation without second verify');
check(HttpClient::$Payload['amount']===1000 && HttpClient::$Payload['authority']==='AuthorityA', 'verify uses stored final amount in rial and original authority');
check(Repository::$Balance===90.0 && Repository::$Claims===1 && Repository::$Records===1, 'accepted payment credited exactly once');
check(!SubscriptionFlow::recoverPendingPayment(1) && Repository::$Balance===90.0, 'repeated recovery cannot credit again');
SubscriptionFlow::handleGatewayCallback(1,'OK','AuthorityA');
check(HttpClient::$Calls===1 && Repository::$Balance===90.0, 'callback after recovery is harmless replay');
}
foreach ([0,500] as $Http) {
resetCase(100,$Http); check(!SubscriptionFlow::recoverPendingPayment(1) && Repository::$Claims===0, 'non-success HTTP cannot authorize credit');
}
resetCase(100); unset(HttpClient::$Response['Json']['data']['ref_id']);
check(!SubscriptionFlow::recoverPendingPayment(1) && Repository::$Balance===0.0, 'success code without receipt cannot authorize credit');
resetCase(100); HttpClient::$Replace=true;
check(!SubscriptionFlow::recoverPendingPayment(1) && Repository::$Claims===0, 'verified old order cannot settle replacement order');
check(Repository::$Session['Pending_Payment']==='topup|200|NewAuthority', 'replacement order untouched');
resetCase(100); SubscriptionFlow::handleGatewayCallback(1,'OK','AnotherAuthority');
check(HttpClient::$Calls===0 && Repository::$Claims===0 && TelegramClient::$Messages===[], 'foreign callback rejected before verify/messages');
SubscriptionFlow::handleGatewayCallback(0,'OK','AuthorityA');
check(HttpClient::$Calls===0, 'invalid callback user rejected');
resetCase(-51); SubscriptionFlow::handleGatewayCallback(1,'OK','AuthorityA');
check(HttpClient::$Calls===1 && Repository::$Claims===0, 'Status OK alone never authorizes payment');
resetCase(100); SubscriptionFlow::handleGatewayCallback(1,'NOK','AuthorityA');
check(HttpClient::$Calls===0 && Repository::$Claims===0, 'cancel callback cannot credit or verify');
$Repo = file_get_contents(__DIR__.'/../Core/Storage/Repository.php');
check(str_contains($Repo, '`Pending_Custom_Plan` = NULL WHERE `Telegram_ID` = ? AND `Pending_Payment` = ?'), 'production atomic claim clears only matched order fields');
$Index = file_get_contents(__DIR__.'/../index.php');
check(str_contains($Index, "handleGatewayCallback(\$User_ID, \$Status, (string)\$_GET['Authority'])"), 'real callback passes authority for matching');
@unlink($Log);
echo "OK Zarinpal unpaid/recovery/callback safety ($N assertions)\n";
