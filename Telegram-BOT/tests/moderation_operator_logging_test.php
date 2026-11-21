<?php
declare(strict_types=1);
require_once dirname(__DIR__) . '/Core/Support/Helper.php';
$N = 0;
function check(bool $Ok, string $Why): void { global $N; if (!$Ok) throw new RuntimeException($Why); $N++; }
$Words = json_decode(file_get_contents(dirname(__DIR__) . '/Resources/Forbidden-Word.json'), true, 512, JSON_THROW_ON_ERROR);
check(count($Words) === count(array_unique($Words)), 'dictionary entries unique');
foreach ($Words as $Word) {
$Compact = str_replace(' ', '', $Word);
$Letters = preg_split('//u', $Compact, -1, PREG_SPLIT_NO_EMPTY);
foreach ([$Word, 'سلام، ' . $Word . '!', implode(' ', $Letters), implode('.', $Letters), implode("\u{200C}", $Letters), implode('ـ', $Letters), strtr($Word, ['ک' => 'ك', 'ی' => 'ي']), implode('', array_map(fn($C) => str_repeat($C, 3), $Letters))] as $Case) {
check(Helper::containsProfanity($Case), 'missed normalized dictionary case: ' . $Case);
}
}
foreach (['کِیر', 'ک1ی2ر', 'بی\شرف', 'بِي شَرَف', 'ﻛﺴﻜﺶ', 'ک ی ی ر', "ک\u{202E}یر", "ک\u{2060}یر", "کس\nکش", 'ک💢ص💢ک💢ش', 'تو ک ی ر هستی'] as $Case) check(Helper::containsProfanity($Case), 'missed bypass: ' . $Case);
$Safe = [
'هیچ کس پاسخ نداده', 'هر کس میتواند عضو شود', 'کسانی که اشتراک دارند', 'کسی هست کمک کند؟',
'من اهل رشت هستم و رشتی هستم', 'گوهری', 'پیمان گوهریان', 'دکل مخابرات خراب است', 'شلوار گشاد است',
'این متن انگلیسی است', 'سکونت من در تهران است', 'لطفا اطلاعات را بررسی کنید', 'اشتراک خریداری کردم',
'چرا خریدن اشتراک سخت است', 'مدارک خریدی که انجام دادم', 'برداشت از بانک', 'اپراتور ایرانسل',
'گاهی اتصال قطع میشود', 'پنجره باید باز باشد', 'سرویس دامپزشکی و حیوانی', 'گوش دراز خرگوش',
'گل های شنگول در باغچه', 'محسن گودرزی', 'محمدعلی کاظمی', 'مریم کیانی', 'نام کاربری من test123 است',
'گوشی خراب است', 'فیلتر محتوای سکس و پورن را فعال کنید', 'دستگاه من فعال نیست', 'مصرف بی رویه نیست',
'به هیچ کس رمز عبور ندهید', 'سرعت اینترنت بسیار کم است', 'کسر اعتبار حساب', 'حجم باقیمانده',
'سلام و تشکر از شما', 'منظورم این است که دستگاه کار نمی کند', 'کسری', 'کاش مشکل حل بشه',
];
foreach ($Safe as $Case) check(!Helper::containsProfanity($Case), 'false positive: ' . $Case);
check(!Helper::containsProfanity('') && !Helper::containsProfanity("\xff"), 'empty/invalid UTF-8 safe');
check(!Helper::containsProfanity(str_repeat('سلام اینترنت مشکل دارد ', 2000)), 'long ordinary input bounded and safe');
check(Helper::validateFullName('مریم گوهری'), 'normal surname containing a short banned word accepted');
check(!Helper::validateFullName('علی کسکش'), 'explicit abusive name rejected');
$Carriers = [
'همراه اول' => ['0910','0911','0912','0913','0914','0915','0916','0917','0918','0919','0990','0991','0992','0993','0994'],
'ایرانسل' => ['0900','0901','0902','0903','0904','0905','0930','0933','0935','0936','0937','0938','0939','0941'],
'رایتل' => ['0920','0921','0922','0923'],
];
foreach ($Carriers as $Name => $Prefixes) foreach ($Prefixes as $Prefix) {
$Phone = $Prefix . '1234567'; $National = substr($Phone, 1);
foreach ([$Phone, $National, '+98'.$National, '0098'.$National, '98'.$National, Helper::toPersian($Phone), strtr($Phone, array_combine(range(0,9), preg_split('//u','٠١٢٣٤٥٦٧٨٩',-1,PREG_SPLIT_NO_EMPTY))), '+98 (' . substr($National,0,3) . ') ' . substr($National,3,3) . '-' . substr($National,6)] as $Input) {
check(Helper::normalizePhone($Input) === $Phone, 'phone normalization ' . $Input);
check(Helper::detectOperator($Input) === $Name, 'carrier allocation ' . $Input);
}
}
foreach (['0931' => 'اسپادان', '0932' => 'تالیا', '0934' => 'کیش'] as $Prefix => $Carrier) check(Helper::detectOperator($Prefix.'1234567') === $Carrier, 'other carrier not falsely IranCell');
foreach (['0924','0925','0926','0927','0928','0929','0906','0998','0999'] as $Prefix) check(Helper::detectOperator($Prefix.'1234567') === 'ناشناخته', 'unverified block not guessed');
foreach (['', '0912123456', '091212345678', '+9891212345678', '+4409121234567', 'abc09121234567', '0912foo1234567', '09+121234567', '++989121234567', '+9809121234567', '09121234567 / 09351234567', '02112345678'] as $Input) check(!Helper::validatePhone($Input) && Helper::detectOperator($Input) === 'نامعتبر', 'invalid phone rejected: ' . $Input);
// Production Repository/Scheduler/Webhook classes with only DB and Telegram stubbed.
final class Database {
public static array $Settings = [], $Groups = [];
public static bool $Fail = false;
public static function getInstance(): self { return new self(); }
public function scalar(string $Q, array $P = []): mixed { return str_contains($Q, '`Settings`') ? (self::$Settings[$P[0]] ?? null) : null; }
public function fetchAll(string $Q, array $P = []): array {
if (str_contains($Q, 'GROUP BY `Phone`')) return self::$Groups;
if (self::$Fail) throw new RuntimeException('database unavailable');
return [['Telegram_ID' => 1]];
}
public function execute(string $Q, array $P): void {
if (str_contains($Q, '`Settings`')) self::$Settings[$P[0]] = $P[1];
}
}
final class ServerClient {
public static bool $Fail = false;
public static function liveUsers(): array { if (self::$Fail) throw new RuntimeException('server unavailable'); return [['uuid' => 'one']]; }
}
final class TelegramClient {
public static bool $Fail = false;
public static array $Calls = [];
public static function call(string $Method, array $Payload = []): array {
self::$Calls[] = $Method;
return self::$Fail && $Method === 'setWebhook' ? ['ok' => false, 'description' => 'test failure'] : ['ok' => true, 'result' => []];
}
}
foreach (['Core/Storage/Repository.php' => 'Repository', 'Bot/Scheduler.php' => 'Scheduler', 'Core/Telegram/Webhook.php' => 'Webhook'] as $File => $Class) {
$Source = file_get_contents(dirname(__DIR__) . '/' . $File);
eval(preg_replace('/\?>\s*$/', '', substr($Source, strpos($Source, 'final class ' . $Class . ' {'))));
}
Database::$Groups = [['Phone' => '09311234567', 'Count' => 2], ['Phone' => '09291234567', 'Count' => 1], ['Phone' => '+989231234567', 'Count' => 3], ['Phone' => '09231234567', 'Count' => 1]];
check(Repository::operatorDistribution() === ['اسپادان' => 2, 'ناشناخته' => 1, 'رایتل' => 4], 'statistics recompute base allocation, not stale stored labels');
$Log = tempnam(sys_get_temp_dir(), 'umbrella-errors-');
$OldLog = ini_get('error_log'); ini_set('error_log', $Log);
try {
$Report = Scheduler::diagnoseNightly();
check(count($Report) >= 10 && str_contains(implode('\n', $Report), 'Eligible active subscribers = 1'), 'manual diagnostics returned to caller');
Scheduler::debugDailyReport();
check(file_get_contents($Log) === '', 'successful diagnostics produce no error log');
$_SERVER['HTTP_HOST'] = 'attacker.example';
$_SERVER['HTTP_X_FORWARDED_PROTO'] = 'http';
$_SERVER['REQUEST_URI'] = '/attacker-controlled/path';
$_SERVER['BOT_WEBHOOK_URL'] = '';
check(
Webhook::expectedUrl() === 'https://armin-soft.ir/Tools/Telegram-BOT/Umbrella-VPN/index.php',
'Host and forwarded-proto headers must never control the Telegram webhook URL'
);
$_SERVER['BOT_WEBHOOK_URL'] = 'https://example.test/index.php';
check(Webhook::expectedUrl() === 'https://example.test/index.php', 'trusted server config may explicitly set the webhook URL');
$_SERVER['BOT_WEBHOOK_URL'] = 'http://attacker.example/index.php';
check(
Webhook::expectedUrl() === 'https://armin-soft.ir/Tools/Telegram-BOT/Umbrella-VPN/index.php',
'non-HTTPS webhook configuration must fall back to the canonical HTTPS URL'
);
$IndexSource = file_get_contents(dirname(__DIR__) . '/index.php');
$WebhookSource = file_get_contents(dirname(__DIR__) . '/Core/Telegram/Webhook.php');
$CliGuard = strpos($IndexSource, "if (PHP_SAPI === 'cli') {");
$SyncCommand = strpos($IndexSource, "if (\$Command === 'syncwebhook') {");
$SyncCall = strpos($IndexSource, '\\Webhook::syncFromCli();');
$CliEnd = $CliGuard === false ? false : strpos($IndexSource, "\n}\n\n// وبهوک", $CliGuard);
check(
$CliGuard !== false && $SyncCommand !== false && $SyncCall !== false && $CliEnd !== false
&& $SyncCommand > $CliGuard && $SyncCall > $SyncCommand && $SyncCall < $CliEnd
&& substr_count($IndexSource, '\\Webhook::syncFromCli();') === 1,
'explicit URL sync is available only as a CLI command'
);
check(
!str_contains($IndexSource, '\\Webhook::ensureRegistered(true)'),
'public request routes cannot authorize webhook URL changes'
);
check(
 preg_match("/public static function syncFromCli\\(\\): void\\s*\\{\\s*if \\(PHP_SAPI !== 'cli'\\)/", $WebhookSource) === 1,
'webhook URL-changing operation rejects non-CLI SAPI'
);
$_SERVER['BOT_WEBHOOK_URL'] = 'https://example.test/index.php';
Webhook::syncFromCli();
check(in_array('setWebhook', TelegramClient::$Calls, true), 'explicit CLI webhook sync path exercised');
check(file_get_contents($Log) === '', 'secret creation and webhook registration successes not logged');
Database::$Settings['Webhook_Registration'] = '';
TelegramClient::$Fail = true; Webhook::syncFromCli();
check(str_contains(file_get_contents($Log), 'setWebhook failed'), 'webhook failure remains logged');
file_put_contents($Log, '');
ServerClient::$Fail = true; Database::$Fail = true;
$Report = Scheduler::diagnoseNightly();
$Logged = file_get_contents($Log);
check(str_contains($Logged, 'Server liveUsers failed') && str_contains($Logged, 'Eligible query failed'), 'both genuine failures remain in error_log');
check(!str_contains($Logged, 'ReportTime') && !str_contains($Logged, 'Administrator'), 'diagnostic details stay out of error_log');
// Simulate a missing dictionary without changing production resource files.
$Source = file_get_contents(dirname(__DIR__) . '/Core/Support/Helper.php');
$Source = substr($Source, strpos($Source, 'final class Helper {'));
$Source = str_replace('final class Helper {', 'final class FallbackHelper {', $Source);
$Source = str_replace("dirname(__DIR__, 2) . '/Resources/Forbidden-Word.json'", "'/missing-dictionary.json'", $Source);
$Source = str_replace("dirname(__DIR__, 2) . '/Resources/Persian-Forms.json'", var_export(dirname(__DIR__) . '/Resources/Persian-Forms.json', true), $Source);
eval(preg_replace('/\?>\s*$/', '', $Source));
check(FallbackHelper::containsProfanity('کسکش') && !FallbackHelper::containsProfanity('سلام'), 'fallback remains conservative and active');
check(str_contains(file_get_contents($Log), 'fallback active'), 'missing dictionary produces actionable error');
} finally { ini_set('error_log', $OldLog); unlink($Log); unset($_SERVER['BOT_WEBHOOK_URL'], $_SERVER['HTTP_HOST'], $_SERVER['HTTP_X_FORWARDED_PROTO'], $_SERVER['REQUEST_URI']); }
$Gateway = file_get_contents(dirname(__DIR__) . '/Core/App/App-Gateway.php');
foreach (['[App-Auth] start |', 'verify: panel account created for challenge', "[Gateway] decision ' . (\$Approved"] as $Success) check(!str_contains($Gateway, $Success), 'normal authentication events not written to error_log');
check(str_contains($Gateway, 'decision transaction failed') && str_contains($Gateway, 'decision from unexpected telegram id'), 'auth failures/security problems still logged');
echo "OK moderation/operators/error logs ({$N} assertions; " . count($Words) . " dictionary entries)\n";
