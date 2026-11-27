<?php
declare(strict_types=1);
// Behavioral tests using SQL/panel/Telegram doubles; MySQL concurrency requires integration tests.
final class Context { public function __construct(public int $UserId,public int $ChatId,public ?string $CallbackId=null) {} }
final class BotIdentity { public static function username(): string { return 'test_bot'; } }
final class Helper { public static function normalizePhone(string $p): string { return $p; } public static function validatePhone(string $p): bool { return preg_match('/^09[0-9]{9}$/', $p)===1; } public static function toPersian(string $p): string { return $p; } }
final class UserFlow { public static string $member='member'; public static function membershipStatus(int $id): string { return self::$member; } public static function start(Context $c): void {} }
final class TelegramClient { public static array $messages=[]; public static function inlineKeyboard(array $a): array { return $a; } public static function sendMessage(int $id,string $text,array $rows=[]): void { self::$messages[]=$text; } public static function answerCallbackQuery(?string $x): void {} }
final class Repository {
public static array $locks=[]; public static bool $conflict=false;
public static function tryCronLock(string $key,int $ttl): bool { if (isset(self::$locks[$key])) return false; self::$locks[$key]=true; return true; }
public static function releaseCronLock(string $key): void { unset(self::$locks[$key]); }
public static function findUserByPhone(string $phone,int $id): array { return self::$conflict ? ['Telegram_ID'=>99] : []; }
}
final class PanelClient { public static int $id=0; public static bool $fail=false; public static function findByTelegramId(int $id): ?array { return null; } public static function lastListError(): ?string { return null; } public static function get(string $uuid): ?array { return self::$fail ? null : ['uuid'=>$uuid,'telegram_id'=>self::$id]; } public static function update(string $uuid,array $v): ?array { self::$id=$v['telegram_id']; return ['uuid'=>$uuid,'telegram_id'=>self::$id]; } }
final class Database {
public static ?self $instance=null; public array $link=[]; public array $user=['Client_ID'=>'','Phone'=>'','Is_Blocked'=>0]; public bool $trusted=true; public bool $revoked=false;
public static function getInstance(): self { return self::$instance ??=new self(); }
public function transaction(callable $fn): mixed { return $fn($this); }
public function execute(string $sql,array $a): object {
if (str_starts_with($sql,'DELETE FROM `App_Bot')) $this->link=[];
elseif (str_starts_with($sql,'INSERT INTO `App_Bot')) $this->link=['Token_Hash'=>$a[0],'Session_Hash'=>$a[1],'User_UUID'=>$a[2],'Device_ID'=>$a[3],'Phone'=>$a[4],'Expires_At'=>$a[5],'Telegram_ID'=>null,'Used_At'=>null];
elseif (str_starts_with($sql,'UPDATE `App_Bot_Link_Requests` SET `Telegram_ID`')) { if ($this->link && $this->link['Token_Hash']===$a[1] && $this->link['Used_At']===null && $this->link['Expires_At'] >= $a[2] && ($this->link['Telegram_ID']===null || $this->link['Telegram_ID']===$a[0])) $this->link['Telegram_ID']=$a[0]; }
elseif (str_starts_with($sql,'UPDATE `App_Bot_Link_Requests` SET `Used_At`')) $this->link['Used_At']=$a[0];
elseif (str_starts_with($sql,'UPDATE `Users`')) { $this->user['Client_ID']=$a[0]; $this->user['Phone']=$a[2]; }
return new stdClass();
}
public function fetch(string $sql,array $a): ?array {
if (str_contains($sql,'FROM `App_Devices` WHERE')) return ['Phone'=>'09123456789','Is_Trusted'=>$this->trusted?1:0,'User_UUID'=>'uuid-1'];
if (str_contains($sql,'FROM `App_Bot_Link_Requests`')) { if (!$this->link || $this->link['Token_Hash']!==$a[0]) return null; if (str_contains($sql,'Used_At` IS NULL') && ($this->link['Used_At']!==null || $this->link['Expires_At']<time())) return null; return $this->link; }
if (str_contains($sql,'FROM `App_Sessions`')) return ['User_UUID'=>'uuid-1','Device_UUID'=>'uuid-1','Revoked_At'=>$this->revoked?'now':null,'Is_Trusted'=>$this->trusted?1:0];
if (str_contains($sql,'FROM `App_SignIn_Requests`')) return ['Full_Name'=>'Test User', 'Phone'=>'09123456789'];
if (str_contains($sql,'FROM `Users` WHERE `Telegram_ID`')) return $this->user;
if (str_contains($sql,'FROM `Users` WHERE `Client_ID`')) return null;
throw new RuntimeException($sql);
}
}
require_once __DIR__.'/../Core/App/App-Bot-Link.php';
$n=0; function check(bool $x,string $why): void { global $n; $n++; if (!$x) throw new RuntimeException($why); }
$session=['User_UUID'=>'uuid-1','Device_ID'=>'device-1','Token_Hash'=>str_repeat('a',64)];
$db=Database::getInstance();
$placeholder=$session; $placeholder['User_UUID']='_'; $placeholderRejected=false;
try { AppBotLink::issue($placeholder); } catch (RuntimeException $Error) { $placeholderRejected=$Error->getMessage()==='invalid_account'; }
check($placeholderRejected,'placeholder panel UUID cannot be linked to a Telegram account');
$issued=AppBotLink::issue($session);
check(preg_match('/^https:\/\/t.me\/test_bot\?start=app_([a-f0-9]{32})$/',$issued['url'],$m)===1,'personal one-time link'); $token=$m[1];
check($db->link['Token_Hash']===hash('sha256',$token) && !in_array($token,$db->link,true),'store hash not token');
check($db->link['Expires_At'] <= time()+600,'short expiry');
AppBotLink::begin(new Context(5,8),$token); check($db->link['Telegram_ID']===null,'group cannot claim');
UserFlow::$member='not_member'; AppBotLink::begin(new Context(5,5),$token); check($db->link['Telegram_ID']===null,'channel membership required'); UserFlow::$member='member';
AppBotLink::begin(new Context(5,5),$token); check($db->link['Telegram_ID']===5,'bind to first telegram user');
AppBotLink::begin(new Context(6,6),$token); check($db->link['Telegram_ID']===5,'another telegram cannot steal claimed request');
AppBotLink::confirm(new Context(6,6),$token); check($db->link['Used_At']===null && PanelClient::$id===0,'foreign confirmation rejected');
$db->revoked=true; AppBotLink::confirm(new Context(5,5),$token); check($db->link['Used_At']===null && PanelClient::$id===0,'revoked session rejected'); $db->revoked=false;
Repository::$conflict=true; AppBotLink::confirm(new Context(5,5),$token); check(PanelClient::$id===0 && $db->link['Used_At']===null,'phone conflict rejected'); Repository::$conflict=false;
PanelClient::$id=8; AppBotLink::confirm(new Context(5,5),$token); check($db->link['Used_At']===null && $db->user['Client_ID']==='','panel conflict rejected'); PanelClient::$id=0;
AppBotLink::confirm(new Context(5,5),$token); check($db->link['Used_At']!==null && PanelClient::$id===5 && $db->user['Client_ID']==='uuid-1','confirmed link syncs panel and bot');
PanelClient::$id=0; AppBotLink::confirm(new Context(5,5),$token); check(PanelClient::$id===0,'replay rejected');
check(Repository::$locks===[],'locks released');
$issued=AppBotLink::issue($session); preg_match('/app_([a-f0-9]{32})/',$issued['url'],$m); $t2=$m[1]; $db->link['Expires_At']=time()-1; AppBotLink::begin(new Context(5,5),$t2); check($db->link['Telegram_ID']===null,'expired link rejected');
$Gateway = file_get_contents(__DIR__.'/../Core/App/App-Gateway.php');
check(str_contains($Gateway, "if (\$Telegram_Id <= 0) {") && str_contains($Gateway, 'PanelClient::get($UUID)') && str_contains($Gateway, 'self::decide($Challenge, true, 0)'), 'unlinked users sign in after SMS and live panel check');
check(str_contains($Gateway, 'AppTwoStep::enabled($Telegram_Id)'), 'existing linked-user two-step retained');
echo "app_bot_link_test: $n checks passed\n";
