<?php
declare(strict_types=1);
require_once __DIR__ . '/../Core/Storage/Repository.php';
require_once __DIR__ . '/../Core/Database/Schema-App.php';
require_once __DIR__ . '/../Core/Payment/ZarinPal.php';
$db = Database::getInstance();
if (($argv[1] ?? '') === 'worker') {
    Repository::settleCancelledPayment(1, 'A' . str_repeat('1', 35), '123456');
    exit;
}
function check(bool $ok, string $message): void { if (!$ok) throw new RuntimeException($message); }
$pdo = $db->connection();
$pdo->exec('CREATE TABLE `Users` (`Telegram_ID` BIGINT PRIMARY KEY, `Balance` DECIMAL(18,0) NOT NULL DEFAULT 0, `Total_Recharge` DECIMAL(18,0) NOT NULL DEFAULT 0, `Total_Spent` DECIMAL(18,0) NOT NULL DEFAULT 0) ENGINE=InnoDB');
$pdo->exec('CREATE TABLE `User_Sessions` (`Telegram_ID` BIGINT PRIMARY KEY, `Pending_Payment` VARCHAR(255) NULL, `Pending_Topup` DECIMAL(18,0) NULL, `Pending_Plan` VARCHAR(255) NULL, `Pending_Custom_Plan` TEXT NULL) ENGINE=InnoDB');
$pdo->exec('CREATE TABLE `Transactions` (`ID` BIGINT AUTO_INCREMENT PRIMARY KEY, `User_ID` BIGINT, `Type` VARCHAR(30), `Amount` DECIMAL(18,0), `Balance_Before` DECIMAL(18,0), `Balance_After` DECIMAL(18,0), `Description` TEXT, `Source` VARCHAR(30)) ENGINE=InnoDB');
AppSchema::ensureInstalled();
$authority = 'A' . str_repeat('1', 35);
$pending = 'topup|100|'.$authority;
$db->execute('INSERT INTO `Users` (`Telegram_ID`) VALUES (1)');
$db->execute('INSERT INTO `User_Sessions` (`Telegram_ID`, `Pending_Payment`, `Pending_Topup`, `Pending_Plan`) VALUES (?,?,?,?)', [1,$pending,90,'paid|1|90']);
try { Repository::archivePendingPayment(1, str_repeat('a',64)); throw new RuntimeException('stale cancellation accepted'); } catch (RuntimeException $e) { check($e->getMessage()==='payment_changed', 'stale hash rejected'); }
check(Repository::archivePendingPayment(1, hash('sha256',$pending)), 'order archived');
$row = Repository::cancelledPayment(1,$authority);
check($row !== null && $row['Pending_Plan']==='paid|1|90' && (float)$row['Credit']===90.0, 'snapshot saved');
check((string)$db->scalar('SELECT `Pending_Payment` FROM `User_Sessions` WHERE `Telegram_ID`=1') === '', 'pending order cleared');
$new = 'topup|200|A'.str_repeat('2',35);
$db->execute('UPDATE `User_Sessions` SET `Pending_Payment`=?,`Pending_Topup`=190 WHERE `Telegram_ID`=1',[$new]);
$workers = [];
for ($i=0;$i<2;$i++) {
    $proc = proc_open([PHP_BINARY, __FILE__, 'worker'], [0=>['pipe','r'],1=>['pipe','w'],2=>['pipe','w']], $pipes);
    fclose($pipes[0]); $workers[] = [$proc,$pipes];
}
foreach ($workers as [$proc,$pipes]) { $out=stream_get_contents($pipes[1]); $err=stream_get_contents($pipes[2]); fclose($pipes[1]); fclose($pipes[2]); check(proc_close($proc)===0, 'worker: '.$out.$err); }
check(Repository::getBalance(1)===90.0, 'concurrent recovery credits exactly once');
check((int)$db->scalar('SELECT COUNT(*) FROM `Transactions`')===2, 'one receipt and one credit');
check($db->scalar('SELECT `Pending_Payment` FROM `User_Sessions` WHERE `Telegram_ID`=1')===$new, 'new order untouched');
check(!Repository::settleCancelledPayment(1,$authority,'123456'), 'replay is harmless');
$db->execute('UPDATE `User_Sessions` SET `Pending_Topup`=NULL WHERE `Telegram_ID`=1');
try { Repository::archivePendingPayment(1,hash('sha256',$new)); throw new RuntimeException('unknown credit accepted'); } catch (RuntimeException $e) { check($e->getMessage()==='payment_cannot_cancel_safely','unknown credit rejected'); }
check($db->scalar('SELECT `Pending_Payment` FROM `User_Sessions` WHERE `Telegram_ID`=1')===$new, 'unsafe order remains recoverable');
echo "cancelled_payment_mysql_integration: passed\n";
