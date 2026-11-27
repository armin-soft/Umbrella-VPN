<?php
declare(strict_types=1);
function check(bool $ok, string $why): void { if (!$ok) throw new RuntimeException($why); }
final class Database {
public static int $max = 1;
public static function getInstance(): self { return new self(); }
public function fetch(string $sql, array $args): array { return ['Max_Devices' => self::$max]; }
public function execute(string $sql, array $args): void { self::$max = $args[1]; }
}
$source = (string)file_get_contents(__DIR__ . '/../Core/App/App-Device-Limit.php');
eval(substr($source, strpos($source, 'final class AppDeviceLimit {')));
check(AppDeviceLimit::setMaxDevices(42, 37) === 37, 'a typed value above 10 is not clamped');
check(AppDeviceLimit::maxDevices(42) === 37, 'read and enforcement use stored value');
check(AppDeviceLimit::setMaxDevices(42, 999) === 99, 'upper bound is 99');
check(AppDeviceLimit::setMaxDevices(42, 0) === 1, 'lower bound is 1');
check(AppDeviceLimit::maxDevices(0) === 1, 'unlinked accounts remain restricted');
$admin = (string)file_get_contents(__DIR__ . '/../Bot/Admin.php');
$part = substr($admin, strpos($admin, 'public static function deviceLimitTarget'), strpos($admin, '/** Third step: persist', strpos($admin, 'public static function deviceLimitTarget')) - strpos($admin, 'public static function deviceLimitTarget'));
check(!str_contains($part, "'device_limit_set_"), 'numeric input presents no preset buttons');
check(str_contains($part, 'Helper::toEnglish($Text)'), 'Persian digits are normalized');
check(str_contains($part, '(int)$Number > 99'), 'out-of-range input is rejected');
echo "OK numeric device limits\n";
