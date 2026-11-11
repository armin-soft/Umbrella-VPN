<?php
declare(strict_types=1);

require_once dirname(__DIR__, 2) . '/Config/Environment.php';

final class Database {
private const DATABASE_CHARSET = 'utf8mb4';
private const CONNECTION_TIMEOUT = 30;
private static ?Database $Instance = null;
private static ?PDO $Connection = null;
private function __construct() {
}

private function __clone() {
}

public static function getInstance(): Database {
return self::$Instance ??= new Database();
}

public function connection(): PDO {
if (self::$Connection instanceof PDO) {
return self::$Connection;
}

$DSN = sprintf(
'mysql:host=%s;port=%d;dbname=%s;charset=%s',
Environment::getDatabaseHost(),
Environment::getDatabasePort(),
Environment::getDatabaseName(),
self::DATABASE_CHARSET
);

$Options = [
PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
PDO::ATTR_EMULATE_PREPARES => false,
PDO::ATTR_TIMEOUT => self::CONNECTION_TIMEOUT,
PDO::ATTR_PERSISTENT => false,
PDO::ATTR_STRINGIFY_FETCHES => false,
];

self::$Connection = new PDO($DSN, Environment::getDatabaseUser(), Environment::getDatabasePassword(), $Options);
return self::$Connection;
}

public function execute(string $Query, array $Parameters = []): PDOStatement {
$Statement = $this->connection()->prepare($Query);

foreach ($Parameters as $Index => $Value) {
$Type = match(true) {
$Value === null => PDO::PARAM_NULL,
$Value === true || $Value === false => PDO::PARAM_BOOL,
is_int($Value) => PDO::PARAM_INT,
default => PDO::PARAM_STR
};

$Statement->bindValue(is_int($Index) ? $Index + 1 : $Index, $Value, $Type);
}

$Statement->execute();
return $Statement;
}

public function fetch(string $SQL, array $Parameters = []): ?array {
$Row = $this->execute($SQL, $Parameters)->fetch();

return $Row === false ? null : $Row;
}

public function fetchAll(string $SQL, array $Parameters = []): array {
return $this->execute($SQL, $Parameters)->fetchAll();
}

public function fetchOne(string $SQL, array $Parameters = []): ?array {
$Row = $this->execute($SQL, $Parameters)->fetch();

return $Row === false ? null : $Row;
}

public function insert(string $Table, array $Data): int {
if (empty($Data)) return 0;
$Columns = array_keys($Data);
$Placeholders = array_map(static fn(string $C): string => ':' . $C, $Columns);
$SQL = sprintf(
'INSERT INTO `%s` (`%s`) VALUES (%s)',
$Table,
implode('`, `', $Columns),
implode(', ', $Placeholders)
);

$Parameters = [];

foreach ($Data as $Key => $Value) {
$Parameters[':' . $Key] = $Value;
}

$this->execute($SQL, $Parameters);
return (int)$this->connection()->lastInsertId();
}

public function scalar(string $SQL, array $Parameters = [], mixed $Default = null): mixed {
$Value = $this->execute($SQL, $Parameters)->fetchColumn();

return $Value === false ? $Default : $Value;
}

public static function getConfig(): array {
return [
'host' => Environment::getDatabaseHost(),
'port' => Environment::getDatabasePort(),
'database' => Environment::getDatabaseName(),
'user' => Environment::getDatabaseUser(),
'password' => Environment::getDatabasePassword(),
];
}

public function transaction(callable $Callback): mixed {
$Connection = $this->connection();
$Connection->beginTransaction();

try {
$Result = $Callback($this);
$Connection->commit();
return $Result;
}

catch (Throwable $Error) {
if ($Connection->inTransaction()) {
$Connection->rollBack();
}

throw $Error;
}
}
}
?>