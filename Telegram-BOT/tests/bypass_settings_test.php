<?php
declare(strict_types=1);
final class AppFilter {
public static function normalizeDomain(string $raw): ?string {
$value = strtolower(trim($raw));
return preg_match('/^[a-z]+\.example$/', $value) ? $value : null;
}
}
final class Database {
public static array $Rows = [];
public static function getInstance(): self { return new self(); }
public function fetch(string $sql, array $args): ?array { return self::$Rows[$args[0]] ?? null; }
public function execute(string $sql, array $args): void { self::$Rows[$args[0]] = ['Iran' => $args[1], 'Domains' => $args[2]]; }
}
$src = (string)file_get_contents(__DIR__ . '/../Core/App/App-Bypass.php');
eval(substr($src, strpos($src, 'final class AppBypass {')));
function check(bool $ok, string $message): void { if (!$ok) throw new RuntimeException($message); }
check(AppBypass::load('account-a') === ['iran' => false, 'domains' => []], 'default off');
AppBypass::save('account-a', ['iran' => true, 'domains' => ['one.example', 'ONE.EXAMPLE', 'bad']]);
check(AppBypass::load('account-a') === ['iran' => true, 'domains' => ['one.example']], 'normalized stored domains');
check(AppBypass::load('account-b') === ['iran' => false, 'domains' => []], 'accounts isolated');
check(!AppBypass::clean(['iran' => 'false'])['iran'], 'false string is false');
echo "OK bypass preferences\n";
