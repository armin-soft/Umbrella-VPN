<?php
declare(strict_types=1);
// Executes the production repository against a transactional SQL double.
// It validates rollback/control flow, not MySQL isolation or crash durability.
$N=0;
function check(bool $Ok,string $Why): void { global $N; $N++; if (!$Ok) throw new RuntimeException($Why); }
final class Result { public function __construct(private int $Count) {} public function rowCount(): int { return $this->Count; } }
final class Database {
public static ?self $Instance=null;
public array $Session=[]; public ?array $User=['Balance'=>10.0,'Total_Recharge'=>0.0]; public array $Transactions=[];
public bool $InTransaction=false; public int $Writes=0; public int $FailAt=0; public array $Locks=[];
public static function getInstance(): self { return self::$Instance ??= new self(); }
public function transaction(callable $Callback): mixed {
check(!$this->InTransaction,'no nested transaction'); $this->InTransaction=true;
$Before=[$this->Session,$this->User,$this->Transactions];
try { $Result=$Callback($this); $this->InTransaction=false; return $Result; }
catch (Throwable $E) { [$this->Session,$this->User,$this->Transactions]=$Before; $this->InTransaction=false; throw $E; }
}
public function fetch(string $Sql,array $Args): ?array {
check($this->InTransaction && str_contains($Sql,'FOR UPDATE'),'production settlement reads under row locks');
$this->Locks[]=$Sql;
if (str_contains($Sql,'`User_Sessions`')) return $this->Session;
if (str_contains($Sql,'`Users`')) return $this->User;
throw new RuntimeException('Unhandled read: '.$Sql);
}
public function scalar(string $Sql,array $Args): mixed {
check($this->InTransaction,'balance read inside transaction');
return $this->User['Balance'] ?? null;
}
public function execute(string $Sql,array $Args): Result {
check($this->InTransaction,'all financial writes inside transaction');
$this->Writes++;
if ($this->FailAt===$this->Writes) throw new RuntimeException('injected SQL failure');
if (str_contains($Sql,'UPDATE `User_Sessions`')) {
check(str_contains($Sql,'AND `Pending_Payment` = ?'),'conditional order claim');
if (($this->Session['Pending_Payment'] ?? '')!==$Args[1]) return new Result(0);
foreach (['Pending_Payment','Pending_Topup','Pending_Plan','Pending_Custom_Plan'] as $Key) $this->Session[$Key]=null;
} elseif (str_contains($Sql,'INSERT INTO `Transactions`')) $this->Transactions[]=$Args;
elseif (str_contains($Sql,'`Balance` = `Balance` +')) $this->User['Balance']+=$Args[0];
elseif (str_contains($Sql,'`Total_Recharge`')) $this->User['Total_Recharge']+=$Args[0];
else throw new RuntimeException('Unhandled write: '.$Sql);
return new Result(1);
}
}
$Source=file_get_contents(__DIR__.'/../Core/Storage/Repository.php');
eval(preg_replace('/\?>\s*$/','',substr($Source,strpos($Source,'final class Repository {'))));
function resetDb(): array {
$Db=Database::$Instance=new Database();
$Db->Session=['Pending_Payment'=>'topup|100|S'.str_repeat('1',35),'Pending_Topup'=>'90','Pending_Plan'=>'','Pending_Custom_Plan'=>''];
return $Db->Session;
}
$Snapshot=resetDb(); $Db=Database::getInstance();
check(Repository::settleGatewayFunds(1,$Snapshot,100,'12345',90),'settlement committed');
check($Db->User['Balance']===100.0 && $Db->User['Total_Recharge']===90.0,'credited original value, not gateway fee');
check(count($Db->Transactions)===2 && $Db->Transactions[0][1]==='payment_success' && $Db->Transactions[1][1]==='credit_add','receipt and credit history both recorded');
check($Db->Session['Pending_Payment']===null && $Db->Session['Pending_Topup']===null,'order consumed on commit');
check(!Repository::settleGatewayFunds(1,$Snapshot,100,'12345',90),'replayed settlement not credited');
check($Db->User['Balance']===100.0 && count($Db->Transactions)===2,'no duplicate accounting');
foreach (range(1,5) as $FailAt) {
$Snapshot=resetDb(); $Db=Database::getInstance(); $Db->FailAt=$FailAt;
$Before=[$Db->Session,$Db->User,$Db->Transactions]; $Failed=false;
try { Repository::settleGatewayFunds(1,$Snapshot,100,'12345',90); } catch (RuntimeException $E) { $Failed=$E->getMessage()==='injected SQL failure'; }
check($Failed,'failure reaches caller, not swallowed');
check([$Db->Session,$Db->User,$Db->Transactions]===$Before,'claim/receipt/credit/totals fully rolled back');
$Db->FailAt=0;
check(Repository::settleGatewayFunds(1,$Snapshot,100,'12345',90),'retry after rollback succeeds');
check($Db->User['Balance']===100.0 && count($Db->Transactions)===2,'retry credits once');
}
foreach (['Pending_Payment','Pending_Topup','Pending_Plan','Pending_Custom_Plan'] as $Key) {
$Snapshot=resetDb(); $Db=Database::getInstance(); $Db->Session[$Key]='replacement';
check(!Repository::settleGatewayFunds(1,$Snapshot,100,'12345',90),'changed snapshot rejected: '.$Key);
check($Db->Writes===0 && $Db->User['Balance']===10.0,'no writes against replacement order');
}
$Snapshot=resetDb(); $Db=Database::getInstance(); $Db->User=null;
try { Repository::settleGatewayFunds(1,$Snapshot,100,'12345',90); check(false,'missing user should fail'); }
catch (RuntimeException $E) { check($Db->Session===$Snapshot && $Db->Writes===0,'missing user cannot consume order'); }
foreach ([[-1,100,'12345',90],[1,NAN,'12345',90],[1,100,'',90],[1,100,'12345',101],[1,100,'12345',-1],[1,100,'12345',INF]] as [$Id,$Amount,$Ref,$Credit]) {
$Snapshot=resetDb();
try { Repository::settleGatewayFunds($Id,$Snapshot,$Amount,$Ref,$Credit); check(false,'invalid settlement should fail'); }
catch (InvalidArgumentException) { check(Database::getInstance()->Writes===0,'invalid settlement fails before SQL'); }
}
echo "OK gateway atomic funds and rollback ($N assertions)\n";
