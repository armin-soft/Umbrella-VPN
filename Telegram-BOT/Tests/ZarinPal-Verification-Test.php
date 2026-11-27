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
public static bool $Sandbox = true;
public static function isZarinpalSandbox(): bool { return self::$Sandbox; }
public static function getZarinpalMerchantId(): string { return 'test'; }
public static function getPaymentCallbackUrl(): string { return 'https://example.invalid/bot/index.php'; }
public static function getAdminUserId(): int { return 0; }
public static function getAdminFullName(): string { return 'admin'; }
}
final class HttpClient {
public static string $Url = ""; public static array $Queue = []; public static bool $Throw = false; public static bool $MutatePlan = false;
public static array $Response = []; public static int $Calls = 0; public static array $Payload = []; public static bool $Replace = false;
public static function post(string $Url, array $Payload, array $Headers): array {
self::$Calls++; self::$Payload = $Payload; self::$Url = $Url;
if (self::$Throw) throw new RuntimeException("network");
if (self::$MutatePlan) Repository::$Session["Pending_Topup"]="95";
if (self::$Replace) Repository::$Session = ['Pending_Payment' => 'topup|200|S33333333333333333333333333333333333', 'Pending_Topup' => '190'];
return self::$Queue !== [] ? array_shift(self::$Queue) : self::$Response;
}
}
final class Context {
public function __construct(public array $Raw, public int $UserId, public int $ChatId, public string $FirstName, public bool $IsCallback, public ?string $CallbackData, public ?string $CallbackId, public ?int $MessageId, public ?string $Text) {}
public function profileName(): string { return 'test user'; }
}
final class Repository {
public static array $Session = []; public static int $Claims = 0; public static int $Records = 0; public static float $Balance = 0;
public static bool $FailSettlement = false; public static float $LastDebit = 0;
public static function settleGatewayFunds(int $Id, array $Snapshot, float $Amount, string $Ref, float $Credit): bool {
if (self::$FailSettlement) throw new RuntimeException('simulated database failure');
if (self::$Session !== $Snapshot || !self::claimPendingPayment($Id, $Snapshot['Pending_Payment'])) return false;
self::recordGatewayPayment(); self::addMoney($Id, $Credit); return true;
}
public static function cancelledPayment(int $Id, string $Authority): ?array { return null; }
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
public static function removeMoney(...$Args): bool { self::$LastDebit = (float)$Args[1]; return false; }
public static function recordGatewayPayment(...$Args): void { self::$Records++; }
public static function addMoney(int $Id, float $Amount, ...$Args): void { self::$Balance += $Amount; }
}
final class BotConfig { public static function getPlanPrice(string $Key): float { return 100.0; } }
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
Repository::$Session = ['Pending_Payment'=>'topup|100|S11111111111111111111111111111111111','Pending_Topup'=>'90','Pending_Plan'=>'','Pending_Custom_Plan'=>''];
Repository::$FailSettlement=false; Repository::$Balance=0; Repository::$Claims=0; Repository::$Records=0;
HttpClient::$Calls=0; HttpClient::$Replace=false; HttpClient::$Throw=false; HttpClient::$MutatePlan=false; HttpClient::$Queue=[]; Environment::$Sandbox=true;
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
check(str_contains(TelegramClient::$Rows[0][0]['url'],'S11111111111111111111111111111111111'), 'continue payment bound to same authority');
resetCase(-50); SubscriptionFlow::verifyPayment($Context);
check(Repository::$Claims===0 && Repository::$Session['Pending_Payment']!==null, 'amount mismatch never settles or discards order');
check(str_contains(end(TelegramClient::$Messages),'مطابقت ندارد'), 'amount mismatch has correct explanation');
check(str_contains(file_get_contents($Log),'code -50'), 'real API errors still logged');
resetCase(-51,500); Zarinpal::verify(100,'S11111111111111111111111111111111111');
check(str_contains(file_get_contents($Log),'code -51'), 'HTTP server failure still logged even with -51');
foreach ([100,101] as $Code) {
resetCase($Code); check(SubscriptionFlow::recoverPendingPayment(1), 'accepted payment recovery completes');
check(HttpClient::$Calls === 1, 'recovery reuses same confirmation without second verify');
check(HttpClient::$Payload['amount']===1000 && HttpClient::$Payload['authority']==='S11111111111111111111111111111111111', 'verify uses stored final amount in rial and original authority');
check(Repository::$Balance===90.0 && Repository::$Claims===1 && Repository::$Records===1, 'accepted payment credited exactly once');
check(!SubscriptionFlow::recoverPendingPayment(1) && Repository::$Balance===90.0, 'repeated recovery cannot credit again');
SubscriptionFlow::handleGatewayCallback(1,'OK','S11111111111111111111111111111111111');
check(HttpClient::$Calls===1 && Repository::$Balance===90.0, 'callback after recovery is harmless replay');
}
foreach ([0,500] as $Http) {
resetCase(100,$Http); check(!SubscriptionFlow::recoverPendingPayment(1) && Repository::$Claims===0, 'non-success HTTP cannot authorize credit');
}
resetCase(100); unset(HttpClient::$Response['Json']['data']['ref_id']);
check(!SubscriptionFlow::recoverPendingPayment(1) && Repository::$Balance===0.0, 'success code without receipt cannot authorize credit');
resetCase(100); HttpClient::$Replace=true;
check(!SubscriptionFlow::recoverPendingPayment(1) && Repository::$Claims===0, 'verified old order cannot settle replacement order');
check(Repository::$Session['Pending_Payment']==='topup|200|S33333333333333333333333333333333333', 'replacement order untouched');
resetCase(100); SubscriptionFlow::handleGatewayCallback(1,'OK','S22222222222222222222222222222222222');
check(HttpClient::$Calls===0 && Repository::$Claims===0 && TelegramClient::$Messages===[], 'foreign callback rejected before verify/messages');
SubscriptionFlow::handleGatewayCallback(0,'OK','S11111111111111111111111111111111111');
check(HttpClient::$Calls===0, 'invalid callback user rejected');
resetCase(-51); SubscriptionFlow::handleGatewayCallback(1,'OK','S11111111111111111111111111111111111');
check(HttpClient::$Calls===1 && Repository::$Claims===0, 'Status OK alone never authorizes payment');
resetCase(100); SubscriptionFlow::handleGatewayCallback(1,'NOK','S11111111111111111111111111111111111');
check(HttpClient::$Calls===0 && Repository::$Claims===0, 'cancel callback cannot credit or verify');
$Repo = file_get_contents(__DIR__.'/../Core/Storage/Repository.php');
check(str_contains($Repo, '`Pending_Custom_Plan` = NULL WHERE `Telegram_ID` = ? AND `Pending_Payment` = ?'), 'production atomic claim clears only matched order fields');
$Index = file_get_contents(__DIR__.'/../index.php');
check(str_contains($Index, "handleGatewayCallback(\$User_ID, \$Status, (string)\$_GET['Authority'])"), 'real callback passes authority for matching');
// Every code published in the gateway error-list table has an explicit mapping.
$Codes = [-9,-10,-11,-12,-13,-14,-15,-16,-17,-18,-19,-40,-41,-50,-51,-52,-53,-54,-55,-60,-61,-62,-63];
$Authority = 'S' . str_repeat('1',35);
foreach ($Codes as $Code) {
resetCase($Code, 422);
$V = Zarinpal::verify(100, $Authority);
check(!$V['Ok'] && $V['Code'] === $Code && $V['Kind'] === 'api', "exact signed provider code $Code");
check(!str_contains(Zarinpal::errorMessage($Code), 'شناخته نشده'), "documented code $Code has message");
$P = Zarinpal::request(100,'https://example.invalid/callback','test');
check($P === null && Zarinpal::lastRequestError()['Code'] === $Code, "request error $Code surfaced");
check(HttpClient::$Calls === 2, 'business errors are not retried');
}
foreach ([-30,-33,52,53,54,55,-987] as $Unknown) check(str_contains(Zarinpal::errorMessage($Unknown),'شناخته نشده'), 'unsupported codes never assigned invented explanations');
check(str_contains(Zarinpal::errorMessage(-10),'آی پی') && str_contains(Zarinpal::errorMessage(-11),'فعال نیست'), 'correct terminal codes');
check(str_contains(Zarinpal::errorMessage(-12),'تعداد') && str_contains(Zarinpal::errorMessage(-41),'۱۰۰ میلیون'), 'correct limit codes');
check(str_contains(Zarinpal::errorMessage(-53),'مرچنت') && str_contains(Zarinpal::errorMessage(-54),'شناسه مرجع پرداخت') && str_contains(Zarinpal::errorMessage(-55),'یافت نشد'), 'negative verify codes mapped correctly');
function quoteResponse(int $Original=100000, int $Suggested=104329, string $Type='Merchant', int $Fee=4200): array {
return ['StatusCode'=>200,'Error'=>'','Json'=>['data'=>['code'=>100,'amount'=>$Original,'suggested_amount'=>$Suggested,'fee'=>$Fee,'fee_type'=>$Type],'errors'=>[]]];
}
function requestResponse(string $Authority,int $Fee=4329,string $Type='Merchant'): array {
return ['StatusCode'=>200,'Error'=>'','Json'=>['data'=>['code'=>100,'authority'=>$Authority,'fee'=>$Fee,'fee_type'=>$Type],'errors'=>[]]];
}
foreach ([true,false] as $Sandbox) {
resetCase(100); Environment::$Sandbox=$Sandbox;
$A=($Sandbox?'S':'A').str_repeat('1',35);
HttpClient::$Queue=[quoteResponse(),requestResponse($A)];
$P=Zarinpal::request(10000,'https://example.invalid/callback?Uid=1','test','09121234567');
check($P !== null && $P['Amount']===10432.9 && $P['Fee']===432.9 && $P['Original_Amount']==10000, 'official suggested amount used, surcharge on gross not naive original fee');
check(HttpClient::$Payload['amount']===104329 && HttpClient::$Payload['currency']==='IRR', 'request exact integer rial gross amount');
check(HttpClient::$Payload['metadata']['mobile']==='09121234567', 'optional mobile metadata');
check(str_contains(HttpClient::$Url, $Sandbox?'sandbox.zarinpal.com':'payment.zarinpal.com') && str_contains($P['RedirectUrl'],$A), 'correct environment URL');
HttpClient::$Response['Json']=['data'=>['code'=>100,'ref_id'=>123456],'errors'=>[]];
check(Zarinpal::verify($P['Amount'],$A)['Ok'] && HttpClient::$Payload['amount']===104329, 'verify reuses exact final gross amount, no repeated fee');
}
resetCase(100); HttpClient::$Queue=[quoteResponse(100000,104329,'Payer')];
check(Zarinpal::request(10000,'https://example.invalid/cb','test')===null && HttpClient::$Calls===1 && Zarinpal::lastRequestError()['Code']===-1003,'payer terminal rejected before creating order to prevent double fee');
foreach (['Payer','',null] as $Type) {
resetCase(100); $Request=requestResponse($Authority); $Request['Json']['data']['fee_type']=$Type;
HttpClient::$Queue=[quoteResponse(),$Request];
check(Zarinpal::request(10000,'https://example.invalid/cb','test')===null && Zarinpal::lastRequestError()['Code']===-1003,'terminal mode rechecked on actual request');
}
foreach ([4328,4330,-1,'4329garbage',null,[]] as $Fee) {
resetCase(100); $Request=requestResponse($Authority); $Request['Json']['data']['fee']=$Fee;
HttpClient::$Queue=[quoteResponse(),$Request];
check(Zarinpal::request(10000,'https://example.invalid/cb','test')===null && Zarinpal::lastRequestError()['Code']===-1004,'changed or invalid final fee never offers a payment link');
}
foreach ([['amount',100001],['suggested_amount',99999],['suggested_amount',null],['suggested_amount',1000000001],['fee',-1],['fee',5000]] as [$Key,$Value]) {
resetCase(100); $Q=quoteResponse(); $Q['Json']['data'][$Key]=$Value; HttpClient::$Queue=[$Q];
check(Zarinpal::request(10000,'https://example.invalid/cb','test')===null && HttpClient::$Calls===1,'invalid quote rejected without guessing fallback');
}
resetCase(100); HttpClient::$Queue=[quoteResponse(100000,100000,'Merchant',0), requestResponse($Authority,0)];
$P=Zarinpal::request(10000,'https://example.invalid/cb','test');
check($P!==null && $P['Fee']==0 && $P['Amount']==10000,'legitimate free promotional fee supported');
resetCase(100); $Q=quoteResponse(); foreach (['amount','fee','suggested_amount'] as $Key) $Q['Json']['data'][$Key]=(string)$Q['Json']['data'][$Key];
HttpClient::$Queue=[$Q,requestResponse($Authority)];
check(Zarinpal::request(10000,'https://example.invalid/cb','test')['Amount']===10432.9,'documented string suggested_amount supported');
$Formatter=new ReflectionMethod(SubscriptionFlow::class,'paymentAmount');
check(str_contains($Formatter->invoke(null,10432.9),'.9'),'payment display does not round away rial fractions');
resetCase();
foreach ([0.0,-1.0,NAN,INF,100000001.0] as $Amount) {
check(Zarinpal::request($Amount,'https://example.invalid/callback','test')===null, 'invalid amount rejected');
check(!Zarinpal::verify($Amount,$Authority)['Ok'], 'invalid verify amount rejected');
}
check(HttpClient::$Calls===0, 'invalid amount never contacts provider');
foreach (['', 'javascript:alert(1)', 'https://example.invalid/cb#fragment'] as $Callback) check(Zarinpal::request(100,$Callback,'test')===null,'invalid callback rejected');
check(Zarinpal::request(100,'https://example.invalid/cb',str_repeat('x',501))===null,'oversized description rejected');
foreach (['', 'AuthorityA', $Authority.'/', str_repeat('S',37)] as $A) check(!Zarinpal::verify(100,$A)['Ok'] && Zarinpal::bridgeUrl($A)==='', 'malformed authority not rewritten');
$BadResponses = [
['data'=>['code'=>100,'ref_id'=>0]],
['data'=>['code'=>100,'ref_id'=>-2]],
['data'=>['code'=>100,'ref_id'=>[]]],
['data'=>['code'=>true,'ref_id'=>123]],
['data'=>['code'=>'100garbage','ref_id'=>123]],
['data'=>['code'=>100,'ref_id'=>123,'card_pan'=>[]]],
['data'=>['code'=>100,'ref_id'=>123],'errors'=>'bad'],
['data'=>['code'=>100,'ref_id'=>123],'errors'=>['code'=>100]],
['data'=>'bad'], [], null,
];
foreach ($BadResponses as $Json) {
resetCase(100); HttpClient::$Response['Json']=$Json;
$V=Zarinpal::verify(100,$Authority);
check(!$V['Ok'] && $V['Code']===-1001 && $V['RefId']==='', 'malformed response never accepted');
}
foreach ([302,401,429,500,0] as $Http) {
resetCase(100,$Http);
$V=Zarinpal::verify(100,$Authority);
check(!$V['Ok'] && $V['Kind']==='transport', 'HTTP failure cannot be disguised as success');
if ($Http===429) check(HttpClient::$Calls===1,'rate limit not immediately retried');
}
resetCase(100); HttpClient::$Queue=[['StatusCode'=>0,'Error'=>'timeout'],HttpClient::$Response];
check(Zarinpal::verify(100,$Authority)['Ok'] && HttpClient::$Calls===2,'temporary verify failure safely retried');
resetCase(100); HttpClient::$Throw=true;
check(Zarinpal::request(100,'https://example.invalid/cb','test')===null && HttpClient::$Calls===1,'request exception caught, no duplicate automatic request');
resetCase(100); HttpClient::$Queue=[quoteResponse(1000,1000,'Merchant',0),requestResponse($Authority,0)];
check(Zarinpal::request(100,'https://example.invalid/cb','test')!==null && Zarinpal::lastRequestError()===null,'successful request resets old error');
foreach ([['code'=>101,'authority'=>$Authority],['code'=>100,'authority'=>'bad'],['code'=>100,'authority'=>'A'.str_repeat('1',35)]] as $Data) {
HttpClient::$Response['Json']=['data'=>$Data,'errors'=>[]];
HttpClient::$Queue=[quoteResponse(1000,1000,'Merchant',0),HttpClient::$Response];
check(Zarinpal::request(100,'https://example.invalid/cb','test')===null, 'request requires code100 and valid matching environment authority');
}
resetCase(100); Repository::$FailSettlement=true; $Original=Repository::$Session;
check(!SubscriptionFlow::recoverPendingPayment(1) && Repository::$Session===$Original && Repository::$Balance===0.0,'database failure preserves retryable order');
check(str_contains(end(TelegramClient::$Messages),'دوباره پرداخت نکنید'),'confirmed but unrecorded payment not called unpaid');
Repository::$FailSettlement=false;
check(SubscriptionFlow::recoverPendingPayment(1) && Repository::$Balance===90.0,'database failure can be recovered');
resetCase(100); SubscriptionFlow::handleGatewayCallback(1,'invalid',$Authority);
check(HttpClient::$Calls===0 && TelegramClient::$Messages===[], 'unknown callback status ignored');
resetCase(100); HttpClient::$MutatePlan=true;
check(!SubscriptionFlow::recoverPendingPayment(1) && Repository::$Claims===0 && Repository::$Balance===0.0,'same authority with altered payment fields cannot reuse verification snapshot');
resetCase(100); Repository::$Session['Pending_Plan']='paid|1';
check(!SubscriptionFlow::recoverPendingPayment(1), 'failed wallet debit stops purchase');
check(Repository::$Balance===90.0 && Repository::$Records===1,'gateway credit retained when wallet cannot cover plan');
check(str_contains(end(TelegramClient::$Messages),'اشتراک فعال نشد'), 'failed wallet debit clearly reported without activating subscription');
resetCase(100); Repository::$Session['Pending_Plan']='paid|1|125';
check(!SubscriptionFlow::recoverPendingPayment(1) && Repository::$LastDebit===125.0, 'app order uses stored original tariff instead of changed live tariff');
@unlink($Log);
echo "OK Zarinpal protocol/fees/error codes/recovery/callback safety ($N assertions)\n";
