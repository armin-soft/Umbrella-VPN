<?php
declare(strict_types=1);

/**
 * آزمون جامع سلامت کدگذاری UTF-8 و بازگردانی متن های به هم ریخته (Mojibake)
 * در تمام فایل های Telegram-BOT، اسکیمای دیتابیس، مهاجرت خودکار و خروجی ربات.
 */

$Root = dirname(__DIR__);
require_once $Root . '/Core/Support/Helper.php';
require_once $Root . '/Core/Telegram/Telegram.php';
require_once $Root . '/Core/Database/Schema.php';

$Failures = [];
function check(bool $Condition, string $Label): void {
global $Failures;
if (!$Condition) {
$Failures[] = $Label;
}
}

/** شبیه ساز دقیق خرابی UTF-8 در کدگذاری Windows-1252 / latin1 مای اس کیو ال */
function toCp1252Mojibake(string $Utf8): string {
$Ext = [
0x80 => "\u{20AC}", 0x82 => "\u{201A}", 0x83 => "\u{0192}", 0x84 => "\u{201E}",
0x85 => "\u{2026}", 0x86 => "\u{2020}", 0x87 => "\u{2021}", 0x88 => "\u{02C6}",
0x89 => "\u{2030}", 0x8A => "\u{0160}", 0x8B => "\u{2039}", 0x8C => "\u{0152}",
0x8E => "\u{017D}", 0x91 => "\u{2018}", 0x92 => "\u{2019}", 0x93 => "\u{201C}",
0x94 => "\u{201D}", 0x95 => "\u{2022}", 0x96 => "\u{2013}", 0x97 => "\u{2014}",
0x98 => "\u{02DC}", 0x99 => "\u{2122}", 0x9A => "\u{0161}", 0x9B => "\u{203A}",
0x9C => "\u{0153}", 0x9E => "\u{017E}", 0x9F => "\u{0178}",
];
$Out = '';
$Len = strlen($Utf8);

for ($I = 0; $I < $Len; $I++) {
$B = ord($Utf8[$I]);

if ($B < 0x80) {
$Out .= chr($B);
} elseif (isset($Ext[$B])) {
$Out .= $Ext[$B];
} else {
$Out .= chr(0xC0 | ($B >> 6)) . chr(0x80 | ($B & 0x3F));
}
}

return $Out;
}

/** شبیه ساز دقیق خرابی UTF-8 در ISO-8859-1 خالص */
function toLatin1Mojibake(string $Utf8): string {
$Out = '';
$Len = strlen($Utf8);

for ($I = 0; $I < $Len; $I++) {
$B = ord($Utf8[$I]);
$Out .= $B < 0x80 ? chr($B) : (chr(0xC0 | ($B >> 6)) . chr(0x80 | ($B & 0x3F)));
}

return $Out;
}

// ۱) اسکن کامل تمام فایل های متنی پوشه Telegram-BOT
$Scanned = 0;
$Iterator = new RecursiveIteratorIterator(
new RecursiveDirectoryIterator($Root, FilesystemIterator::SKIP_DOTS)
);

foreach ($Iterator as $Info) {
if (!$Info->isFile()) continue;
$Path = $Info->getPathname();
$Ext = strtolower($Info->getExtension());

if (!in_array($Ext, ['php', 'sql', 'json'], true)) continue;
$Scanned++;
$Rel = substr($Path, strlen($Root) + 1);
$Bytes = (string)file_get_contents($Path);

check(!str_starts_with($Bytes, "\xEF\xBB\xBF"), "no UTF-8 BOM in {$Rel}");
check(!str_starts_with($Bytes, "\xFF\xFE") && !str_starts_with($Bytes, "\xFE\xFF"), "no UTF-16 BOM in {$Rel}");
check(preg_match('//u', $Bytes) === 1, "valid UTF-8 in {$Rel}");
check(!str_contains($Bytes, "\xEF\xBF\xBD"), "no U+FFFD replacement char in {$Rel}");
check(preg_match('/\xC2[\x80-\x9F]/', $Bytes) !== 1, "no C1 control chars in {$Rel}");
check(Helper::repairMojibake($Bytes) === $Bytes, "zero mojibake in {$Rel}");

if ($Ext === 'json') {
$Decoded = json_decode($Bytes, true);
check(is_array($Decoded) && json_last_error() === JSON_ERROR_NONE, "valid UTF-8 JSON in {$Rel}");
}
}

check($Scanned >= 58, "scanned all Telegram-BOT text files (got {$Scanned})");

// ۲) بررسی دقیق Database/Schema.SQL
$Schema_Sql = (string)file_get_contents($Root . '/Database/Schema.SQL');
check(
str_starts_with(ltrim($Schema_Sql), 'SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;'),
'Schema.SQL enforces SET NAMES utf8mb4 at top'
);
check(str_contains($Schema_Sql, "`Status` VARCHAR(20) NOT NULL DEFAULT 'ناموفق'"), 'Schema.SQL SMS_Logs default is clean Persian');
check(str_contains($Schema_Sql, "('Robot_Status', '🟢روشن')"), 'Schema.SQL Robot_Status seed is clean Persian+emoji');
$Create_Count = preg_match_all('/CREATE TABLE IF NOT EXISTS/i', $Schema_Sql);
$Charset_Count = preg_match_all('/DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci/i', $Schema_Sql);
check($Create_Count > 0 && $Create_Count === $Charset_Count, 'every table in Schema.SQL uses utf8mb4_unicode_ci');

// ۳) آزمون دقیق بازگردانی رشته های خراب واقعی (از جمله مقدار دقیق گزارش شده)
$Exact_Robot_On_Mojibake = "\u{00F0}\u{0178}\u{0178}\u{00A2}\u{00D8}\u{00B1}\u{00D9}\u{02C6}\u{00D8}\u{00B4}\u{00D9}\u{2020}";
$Exact_Robot_Off_Mojibake = toCp1252Mojibake('🔴خاموش');
$Exact_Sms_Failed_Mojibake = "\u{00D9}\u{2020}\u{00D8}\u{00A7}\u{00D9}\u{2026}\u{00D9}\u{02C6}\u{00D9}\u{0081}\u{00D9}\u{201A}";
$Exact_Sms_Ok_Mojibake = toCp1252Mojibake('موفق');

check($Exact_Robot_On_Mojibake === toCp1252Mojibake('🟢روشن'), 'exact Robot_Status mojibake vector verified');
check($Exact_Sms_Failed_Mojibake === toCp1252Mojibake('ناموفق'), 'exact SMS_Logs.Status mojibake vector verified');
check(Helper::repairMojibake($Exact_Robot_On_Mojibake) === '🟢روشن', 'repairs Robot_Status ON mojibake to 🟢روشن');
check(Helper::repairMojibake($Exact_Robot_Off_Mojibake) === '🔴خاموش', 'repairs Robot_Status OFF mojibake to 🔴خاموش');
check(Helper::repairMojibake($Exact_Sms_Failed_Mojibake) === 'ناموفق', 'repairs SMS_Logs failed mojibake to ناموفق');
check(Helper::repairMojibake($Exact_Sms_Ok_Mojibake) === 'موفق', 'repairs SMS_Logs success mojibake to موفق');
check(Helper::repairMojibake("\xEF\xBB\xBF🟢روشن") === '🟢روشن', 'strips leading UTF-8 BOM');
check(Helper::repairMojibake(toCp1252Mojibake("\xEF\xBB\xBF🟢روشن")) === '🟢روشن', 'strips mojibake-encoded UTF-8 BOM');

$Roundtrip_Samples = [
'🟢روشن',
'🔴خاموش',
'ناموفق',
'موفق',
'✅فعال',
'🚫غیر فعال',
'🚫قطع به دلیل عدم عضویت',
'فیلترشکن آمبرلا',
'🔐تأیید دومرحله ای روشن شد.',
'📲دستگاه های برنامه — صفحه ۱ از ۳',
'💳شارژ اعتبار از طریق درگاه پرداخت زرین پال (۱۵۰,۰۰۰ تومان)',
"{full_name} گرامی اشتراک {plan} شما با موفقیت فعال گردید.\n⏳مدت اعتبار: {remaining}\n\nسرور آمبرلا",
'User: آرمین سافت (ID: 12345) | Status: 🟢روشن',
];

foreach ($Roundtrip_Samples as $Index => $Sample) {
$Cp1252 = toCp1252Mojibake($Sample);
$Latin1 = toLatin1Mojibake($Sample);
$Double = toCp1252Mojibake($Cp1252);
$Triple = toCp1252Mojibake($Double);

check(Helper::repairMojibake($Cp1252) === $Sample, "CP1252 roundtrip #{$Index}");
check(Helper::repairMojibake($Latin1) === $Sample, "Latin-1 roundtrip #{$Index}");
check(Helper::repairMojibake($Double) === $Sample, "double-mojibake roundtrip #{$Index}");
check(Helper::repairMojibake($Triple) === $Sample, "triple-mojibake roundtrip #{$Index}");
}

$Mixed = 'وضعیت فعلی: ' . $Exact_Robot_On_Mojibake . ' | پیامک: ' . toCp1252Mojibake($Exact_Sms_Failed_Mojibake);
check(Helper::repairMojibake($Mixed) === 'وضعیت فعلی: 🟢روشن | پیامک: ناموفق', 'repairs mixed clean + mojibake string');

// ۴) اطمینان از عدم تغییر متن های سالم فارسی، انگلیسی، نمادها و زبان های بین المللی
$Clean_Samples = array_merge($Roundtrip_Samples, [
'',
'Hello, Umbrella VPN!',
'https://t.me/Umbrella_Bot?start=abc_123',
'550e8400-e29b-41d4-a716-446655440000',
'Price: €50 — 100% “guaranteed”',
"caf\u{00E9}", "na\u{00EF}ve", "\u{00FC}ber", "se\u{00F1}or", "\u{00D8}resund", "S\u{00E3}o Paulo",
"fa\u{00E7}ade", "r\u{00E9}sum\u{00E9}", "\u{00C5}ngstr\u{00F6}m", "Fran\u{00E7}ois", "K\u{00F8}benhavn",
'Привет мир', 'مرحبا بالعالم',
]);

foreach ($Clean_Samples as $Index => $Clean) {
check(Helper::repairMojibake($Clean) === $Clean, "clean string untouched #{$Index}");
}

// ۵) آزمون نرمال سازی وضعیت ربات، رندر پیام و دکمه های تلگرام
check(Schema::normalizeRobotStatus($Exact_Robot_On_Mojibake) === '🟢روشن', 'normalizeRobotStatus ON mojibake');
check(Schema::normalizeRobotStatus($Exact_Robot_Off_Mojibake) === '🔴خاموش', 'normalizeRobotStatus OFF mojibake');
check(Schema::normalizeRobotStatus('🟢روشن') === '🟢روشن', 'normalizeRobotStatus clean ON');
check(Schema::normalizeRobotStatus('🔴خاموش') === '🔴خاموش', 'normalizeRobotStatus clean OFF');
check(Schema::normalizeRobotStatus('off') === '🔴خاموش', 'normalizeRobotStatus English off');
check(Schema::normalizeRobotStatus('0') === '🔴خاموش', 'normalizeRobotStatus numeric 0');

$Rendered_Md = TelegramClient::md('🚦وضعیت ربات: *' . $Exact_Robot_On_Mojibake . '*');
check(str_contains($Rendered_Md, '🟢روشن') && !str_contains($Rendered_Md, "\u{00D8}"), 'TelegramClient::md heals mojibake');

$Keyboard = TelegramClient::inlineKeyboard([
[['text' => $Exact_Robot_On_Mojibake, 'callback_data' => 'robot_state']],
]);
check(($Keyboard['inline_keyboard'][0][0]['text'] ?? '') === '🟢روشن', 'TelegramClient::inlineKeyboard heals mojibake button');

// ۶) بررسی نگهبان های اتصال دیتابیس، مهاجرت، پشتیبان گیری، محیط و درگاه وب
$Db_Php = (string)file_get_contents($Root . '/Core/Database/Database.php');
check(str_contains($Db_Php, "DATABASE_CHARSET = 'utf8mb4'"), 'Database.php uses utf8mb4');
check(str_contains($Db_Php, "SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci"), 'Database.php sets MYSQL_ATTR_INIT_COMMAND utf8mb4');

$Schema_Php = (string)file_get_contents($Root . '/Core/Database/Schema.php');
check(str_contains($Schema_Php, 'migrateUtf8AndMojibake'), 'Schema.php runs live UTF-8 mojibake repair migration');
check(str_contains($Schema_Php, 'Utf8_Mojibake_Migration_v1'), 'Schema.php guards one-time UTF-8 migration');
check(str_contains($Schema_Php, "['Robot_Status', '🟢روشن']"), 'Schema.php seeds clean Robot_Status');
check(str_contains($Schema_Php, "'User_Sessions' => ['pk' => 'Telegram_ID'"), 'Schema.php uses Telegram_ID PK for User_Sessions');

$Admin_Php = (string)file_get_contents($Root . '/Bot/Admin.php');
check(str_contains($Admin_Php, 'mysqldump --default-character-set=utf8mb4'), 'Admin.php mysqldump forces utf8mb4');

$Env_Php = (string)file_get_contents($Root . '/Config/Environment.php');
check(str_contains($Env_Php, '\\xEF\\xBB\\xBF'), 'Environment.php strips UTF-8 BOM from .env');

$Http_Php = (string)file_get_contents($Root . '/Core/Support/Http.php');
check(str_contains($Http_Php, 'JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE'), 'Http.php guards invalid UTF-8 in JSON');
check(str_contains($Http_Php, 'application/json; charset=utf-8'), 'Http.php sends UTF-8 JSON Content-Type');

$Gateway_Php = (string)file_get_contents($Root . '/Core/App/App-Gateway.php');
check(str_contains($Gateway_Php, 'JSON_INVALID_UTF8_SUBSTITUTE'), 'App-Gateway.php guards invalid UTF-8 in JSON');
check(str_contains($Gateway_Php, 'sanitizePayload'), 'App-Gateway.php sanitizes response payloads');

$Common_Php = (string)file_get_contents($Root . '/Bot/Common.php');
check(str_contains($Common_Php, 'repairMojibake'), 'Common::isRobotOn repairs mojibake Robot_Status');

$Repo_Php = (string)file_get_contents($Root . '/Core/Storage/Repository.php');
check(str_contains($Repo_Php, 'repairMojibake'), 'Repository::getSetting/setSetting repair mojibake');

// ۷) آزمون یکپارچه واقعی Common::isRobotOn و مهاجرت خودکار دیتابیس روی داده خراب
$Sub_Script = <<<'PHP'
$Root = $argv[1];
require_once $Root . '/Config/Environment.php';
require_once $Root . '/Core/Support/Helper.php';

function cp1252(string $S): string {
$Ext = [0x80=>"\u{20AC}",0x82=>"\u{201A}",0x83=>"\u{0192}",0x84=>"\u{201E}",0x85=>"\u{2026}",0x86=>"\u{2020}",0x87=>"\u{2021}",0x88=>"\u{02C6}",0x89=>"\u{2030}",0x8A=>"\u{0160}",0x8B=>"\u{2039}",0x8C=>"\u{0152}",0x8E=>"\u{017D}",0x91=>"\u{2018}",0x92=>"\u{2019}",0x93=>"\u{201C}",0x94=>"\u{201D}",0x95=>"\u{2022}",0x96=>"\u{2013}",0x97=>"\u{2014}",0x98=>"\u{02DC}",0x99=>"\u{2122}",0x9A=>"\u{0161}",0x9B=>"\u{203A}",0x9C=>"\u{0153}",0x9E=>"\u{017E}",0x9F=>"\u{0178}"];
$O = '';
for ($I = 0; $I < strlen($S); $I++) { $B = ord($S[$I]); $O .= $B < 0x80 ? chr($B) : ($Ext[$B] ?? (chr(0xC0 | ($B >> 6)) . chr(0x80 | ($B & 0x3F)))); }
return $O;
}

final class FakePdo {
public array $Execs = [];
public function exec(string $Sql): int { $this->Execs[] = $Sql; return 1; }
}

final class FakeStmt {
public function __construct(private int $Count = 1) {}
public function rowCount(): int { return $this->Count; }
}

final class Database {
public static array $Settings = [];
public static array $SmsLogs = [];
public static array $Users = [];
public static string $SmsDefault = '';
public static FakePdo $Pdo;
private static ?self $Inst = null;
public static function getInstance(): self { self::$Pdo ??= new FakePdo(); return self::$Inst ??= new self(); }
public function connection(): FakePdo { return self::$Pdo; }
public function scalar(string $Sql, array $Params = [], mixed $Default = null): mixed {
if (str_contains($Sql, 'SELECT `Value` FROM `Settings`')) return self::$Settings[$Params[0]] ?? $Default;
if (str_contains($Sql, 'SELECT COLUMN_DEFAULT') && str_contains($Sql, 'SMS_Logs')) return self::$SmsDefault;
return $Default;
}
public function fetchAll(string $Sql, array $Params = []): array {
if (str_contains($Sql, 'information_schema.tables')) return [['t' => 'SMS_Logs']];
if (str_contains($Sql, 'information_schema.columns')) {
$Table = $Params[0] ?? '';
return match ($Table) {
'Settings' => [['c' => 'Key'], ['c' => 'Value']],
'SMS_Logs' => [['c' => 'ID'], ['c' => 'Status'], ['c' => 'Message']],
'Users' => [['c' => 'ID'], ['c' => 'Full_Name'], ['c' => 'Client_Status']],
'User_Sessions' => [['c' => 'Telegram_ID'], ['c' => 'Flow']],
default => [],
};
}
if (str_contains($Sql, 'FROM `Settings`')) {
$Out = [];
foreach (self::$Settings as $K => $V) {
if ($K === 'App_Gateway_Secret' || $K === 'Webhook_State' || str_starts_with($K, 'DailyNotice_')) continue;
$Out[] = ['Key' => $K, 'Value' => $V];
}
return $Out;
}
if (str_contains($Sql, 'FROM `SMS_Logs`')) return array_values(self::$SmsLogs);
if (str_contains($Sql, 'FROM `Users`')) return array_values(self::$Users);
return [];
}
public function execute(string $Sql, array $Params = []): FakeStmt {
if (str_starts_with($Sql, 'UPDATE `Settings` SET `Value` = ? WHERE `Key` = ?')) {
self::$Settings[$Params[1]] = $Params[0];
} elseif (str_starts_with($Sql, 'INSERT INTO `Settings`') || str_starts_with($Sql, 'INSERT IGNORE INTO `Settings`')) {
if (!str_contains($Sql, 'IGNORE') || !array_key_exists($Params[0], self::$Settings)) {
self::$Settings[$Params[0]] = $Params[1];
}
} elseif (str_starts_with($Sql, 'UPDATE `SMS_Logs`')) {
$Id = end($Params);
if (str_contains($Sql, '`Status` = ?') && str_contains($Sql, '`Message` = ?')) {
self::$SmsLogs[$Id]['Status'] = $Params[0];
self::$SmsLogs[$Id]['Message'] = $Params[1];
} elseif (str_contains($Sql, '`Status` = ?')) {
self::$SmsLogs[$Id]['Status'] = $Params[0];
}
} elseif (str_starts_with($Sql, 'UPDATE `Users`')) {
$Id = end($Params);
self::$Users[$Id]['Full_Name'] = $Params[0];
self::$Users[$Id]['Client_Status'] = $Params[1];
}
return new FakeStmt(1);
}
}

function loadWithoutDb(string $Path): void {
$Code = (string)file_get_contents($Path);
$Code = preg_replace('/^\s*<\?php\s*/', '', $Code);
$Code = preg_replace('/^\s*declare\s*\(\s*strict_types\s*=\s*1\s*\)\s*;\s*/m', '', $Code);
$Code = preg_replace('/^\s*require_once[^\n]*;\s*$/m', '', $Code);
$Code = str_replace('__DIR__', var_export(dirname($Path), true), $Code);
$Code = preg_replace('/\?>\s*$/', '', $Code);
eval($Code);
}

loadWithoutDb($Root . '/Core/Storage/Repository.php');
loadWithoutDb($Root . '/Bot/Common.php');
loadWithoutDb($Root . '/Core/Database/Schema.php');

Database::$Settings = [
'Robot_Status' => cp1252('🔴خاموش'),
'Maintenance_Message' => cp1252('ربات جهت بروزرسانی موقتاً خاموش است'),
'App_Gateway_Secret' => cp1252('راز'),
];
if (Common::isRobotOn() !== false) { fwrite(STDERR, "isRobotOn must be false on mojibake OFF\n"); exit(1); }
if (Repository::getSetting('Robot_Status') !== '🔴خاموش') { fwrite(STDERR, "getSetting must decode OFF\n"); exit(1); }

Database::$Settings['Robot_Status'] = cp1252('🟢روشن');
if (Common::isRobotOn() !== true) { fwrite(STDERR, "isRobotOn must be true on mojibake ON\n"); exit(1); }
if (Repository::getSetting('Robot_Status') !== '🟢روشن') { fwrite(STDERR, "getSetting must decode ON\n"); exit(1); }

Database::$SmsDefault = cp1252('ناموفق');
Database::$SmsLogs = [
1 => ['ID' => 1, 'Status' => cp1252('ناموفق'), 'Message' => cp1252('ارسال پیامک به کاربر ناموفق بود')],
2 => ['ID' => 2, 'Status' => cp1252('موفق'), 'Message' => 'OTP pattern accepted'],
];
Database::$Users = [
10 => ['ID' => 10, 'Full_Name' => cp1252('آرمین سافت'), 'Client_Status' => cp1252('✅فعال')],
];

$Ref = new ReflectionMethod(Schema::class, 'migrateUtf8AndMojibake');
$Ref->invoke(null);

$Assert = [
'Robot_Status repaired' => Database::$Settings['Robot_Status'] === '🟢روشن',
'Maintenance_Message repaired' => Database::$Settings['Maintenance_Message'] === 'ربات جهت بروزرسانی موقتاً خاموش است',
'App_Gateway_Secret untouched' => Database::$Settings['App_Gateway_Secret'] === cp1252('راز'),
'SMS #1 Status repaired' => Database::$SmsLogs[1]['Status'] === 'ناموفق',
'SMS #1 Message repaired' => Database::$SmsLogs[1]['Message'] === 'ارسال پیامک به کاربر ناموفق بود',
'SMS #2 Status repaired' => Database::$SmsLogs[2]['Status'] === 'موفق',
'SMS #2 ASCII untouched' => Database::$SmsLogs[2]['Message'] === 'OTP pattern accepted',
'User Full_Name repaired' => Database::$Users[10]['Full_Name'] === 'آرمین سافت',
'User Client_Status repaired' => Database::$Users[10]['Client_Status'] === '✅فعال',
'Migration flag recorded' => (Database::$Settings['Utf8_Mojibake_Migration_v1'] ?? '') === '1',
'SMS_Logs default altered' => in_array("ALTER TABLE `SMS_Logs` MODIFY COLUMN `Status` VARCHAR(20) NOT NULL DEFAULT 'ناموفق'", Database::$Pdo->Execs, true),
'Table converted to utf8mb4' => in_array('ALTER TABLE `SMS_Logs` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci', Database::$Pdo->Execs, true),
];
foreach ($Assert as $Name => $Ok) {
if (!$Ok) { fwrite(STDERR, "Migration check failed: {$Name}\n"); exit(1); }
}

// فراخوانی دوم باید بدون هیچ کوئری اضافه پایان یابد (idempotent)
$Exec_Before = count(Database::$Pdo->Execs);
$Ref->invoke(null);
if (count(Database::$Pdo->Execs) !== $Exec_Before) { fwrite(STDERR, "Migration not idempotent\n"); exit(1); }
echo "SUB_OK";
PHP;

$Tmp = tempnam(sys_get_temp_dir(), 'umb_utf8_');
file_put_contents($Tmp, "<?php\ndeclare(strict_types=1);\n" . $Sub_Script);
$Sub_Out = [];
$Sub_Code = 0;
exec(escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($Tmp) . ' ' . escapeshellarg($Root) . ' 2>&1', $Sub_Out, $Sub_Code);
@unlink($Tmp);
check($Sub_Code === 0 && str_contains(implode("\n", $Sub_Out), 'SUB_OK'), 'live DB migration + isRobotOn integration: ' . implode(' | ', $Sub_Out));

if ($Failures !== []) {
fwrite(STDERR, "UTF-8 / Mojibake test failed:\n - " . implode("\n - ", $Failures) . "\n");
exit(1);
}

echo "utf8_mojibake_test: OK ({$Scanned} files scanned)\n";
