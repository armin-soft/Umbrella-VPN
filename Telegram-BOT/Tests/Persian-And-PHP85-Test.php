<?php
declare(strict_types=1);

$Assertions = 0;
function assertOk(bool $Condition, string $Message): void {
global $Assertions;
$Assertions++;
if (!$Condition) {
throw new RuntimeException('FAILED: ' . $Message);
}
}

// Strict PHP 8.5 deprecation / warning / notice trap.
$CapturedErrors = [];
set_error_handler(static function (int $Severity, string $Message, string $File, int $Line) use (&$CapturedErrors): bool {
if ((error_reporting() & $Severity) === 0) {
return false;
}
$CapturedErrors[] = sprintf('[%d] %s in %s:%d', $Severity, $Message, basename($File), $Line);
return true;
});
error_reporting(E_ALL);

$Root = dirname(__DIR__);

// 1. PHP 8.5 PDO MySQL init-command attribute must never emit E_DEPRECATED.
require_once $Root . '/Core/Database/Database.php';
$Attr = Database::mysqlInitCommandAttribute();
assertOk($CapturedErrors === [], 'Database::mysqlInitCommandAttribute emitted zero warnings/deprecations: ' . implode(' | ', $CapturedErrors));

if (PHP_VERSION_ID >= 80400 && class_exists(\Pdo\Mysql::class, false)) {
assertOk($Attr === \Pdo\Mysql::ATTR_INIT_COMMAND && is_int($Attr), 'PHP 8.4+/8.5 uses Pdo\\Mysql::ATTR_INIT_COMMAND');
} elseif (extension_loaded('pdo_mysql')) {
assertOk(is_int($Attr) && $Attr > 0, 'PHP 8.2/8.3 resolves legacy MySQL init command constant cleanly');
} else {
assertOk($Attr === null, 'Returns null cleanly when pdo_mysql extension is absent');
}

// Verify zero direct PDO::MYSQL_ATTR_* evaluation and zero setAccessible() across all files.
$Iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($Root, FilesystemIterator::SKIP_DOTS));
$ForbiddenInvisible = [
"\u{200C}" => 'ZWNJ',
"\u{200B}" => 'ZWSP',
"\u{200E}" => 'LRM',
"\u{200F}" => 'RLM',
"\u{202A}" => 'LRE',
"\u{202B}" => 'RLE',
"\u{202C}" => 'PDF',
"\u{202D}" => 'LRO',
"\u{202E}" => 'RLO',
"\u{2066}" => 'LRI',
"\u{2067}" => 'RLI',
"\u{2068}" => 'FSI',
"\u{2069}" => 'PDI',
"\u{FEFF}" => 'BOM',
];

foreach ($Iterator as $Info) {
if (!$Info->isFile()) continue;
$Path = $Info->getPathname();
$Rel = ltrim(str_replace('\\', '/', substr($Path, strlen($Root))), '/');
$Ext = strtolower($Info->getExtension());
if (!in_array($Ext, ['php', 'sql', 'json'], true)) continue;
$Content = (string)file_get_contents($Path);
$IsTest = str_starts_with($Rel, 'Tests/');

if ($Ext === 'php' && $Rel !== 'Tests/Persian-And-PHP85-Test.php') {
$CodeOnly = '';
foreach (token_get_all($Content) as $Tok) {
if (is_array($Tok) && in_array($Tok[0], [T_COMMENT, T_DOC_COMMENT, T_CONSTANT_ENCAPSED_STRING], true)) continue;
$CodeOnly .= is_array($Tok) ? $Tok[1] : $Tok;
}
assertOk(
preg_match('/\bPDO\s*::\s*(?:MYSQL|PGSQL|SQLITE|ODBC|FB)_ATTR_[A-Z0-9_]+/', $CodeOnly) !== 1,
'No direct deprecated PDO driver constant in ' . $Rel
);
assertOk(!str_contains($CodeOnly, '->setAccessible('), 'No deprecated Reflection::setAccessible in ' . $Rel);
assertOk(preg_match('/\b(?:curl_close|curl_share_close|imagedestroy|xml_parser_free|finfo_close)\s*\(/', $CodeOnly) !== 1, 'No PHP 8.5 deprecated close() in ' . $Rel);
}

if (!$IsTest) {
foreach ($ForbiddenInvisible as $Char => $Label) {
assertOk(!str_contains($Content, $Char), "No {$Label} character in {$Rel}");
}
assertOk(!str_contains($Content, "\u{20E3}") && !str_contains($Content, '🔟'), 'No Latin keycap digit emoji in ' . $Rel);
assertOk(!str_contains($Content, 'PHP 8.2+ is required'), 'No English PHP version error in ' . $Rel);
assertOk(!str_contains($Content, 'UUID:'), 'No English UUID label in ' . $Rel);
assertOk(!str_contains($Content, 'expire_in'), 'No English expire_in in ' . $Rel);
assertOk(!str_contains($Content, '(Authority)') && !str_contains($Content, '(Merchant)'), 'No English gateway terms in ' . $Rel);
assertOk(!str_contains($Content, 'callback_data دکمه'), 'No English callback_data prose in ' . $Rel);
}
}

// 2. Helper Persian text & digit conversion tests.
require_once $Root . '/Core/Support/Helper.php';
assertOk(Helper::stripZwnj("دستگاه\u{200C}های   ثبت\u{200C}شده") === 'دستگاه های ثبت شده', 'stripZwnj replaces ZWNJ with clean single space');
assertOk(Helper::stripZwnj("خط اول\nمی\u{200C}شود") === "خط اول\nمی شود", 'stripZwnj preserves line breaks');
assertOk(Helper::toPersian('0123456789') === '۰۱۲۳۴۵۶۷۸۹', 'toPersian converts ASCII digits');
assertOk(Helper::toPersian('٠١٢٣٤٥٦٧٨٩') === '۰۱۲۳۴۵۶۷۸۹', 'toPersian converts Arabic-Indic digits');
assertOk(Helper::digitsToPersian('نسخه 1.0.0 و کد ٤٥٦') === 'نسخه ۱.۰.۰ و کد ۴۵۶', 'digitsToPersian converts Latin and Arabic digits');
assertOk(Helper::digitsToPersian('شناسه: <code>6248742705</code> و کانال <code>-1001833514833</code>') === 'شناسه: <code>۶۲۴۸۷۴۲۷۰۵</code> و کانال <code>-۱۰۰۱۸۳۳۵۱۴۸۳۳</code>', 'numeric code blocks become Persian');
assertOk(Helper::digitsToPersian('مثال `100000` و کارت `6037-99**-****-1234`') === 'مثال `۱۰۰۰۰۰` و کارت `۶۰۳۷-۹۹**-****-۱۲۳۴`', 'inline numeric code becomes Persian');
assertOk(str_contains(Helper::digitsToPersian('<pre>key-123+/=</pre>'), '<pre>key-123+/=</pre>'), 'crypto key preserved byte-exact');
assertOk(str_contains(Helper::digitsToPersian('<code>970f3fa0-3714-4d9a-a95d-8c4ddd696bfd</code>'), '970f3fa0-3714-4d9a-a95d-8c4ddd696bfd'), 'UUID preserved byte-exact');
assertOk(str_contains(Helper::digitsToPersian('https://sub1.example.com/u/123?x=9'), 'https://sub1.example.com/u/123?x=9'), 'URL preserved byte-exact');
assertOk(str_contains(Helper::digitsToPersian('[کاربر 12](tg://user?id=987654)'), '[کاربر ۱۲](tg://user?id=987654)'), 'mention link preserved while label digits become Persian');
assertOk(str_contains(Helper::digitsToPersian('کانال @User_123 و دامنه sub2.example.org'), '@User_123') && str_contains(Helper::digitsToPersian('دامنه sub2.example.org'), 'sub2.example.org'), 'username and domain preserved');
assertOk(Helper::digitsToPersian('کانال t.me/UmbrellaVPN_Channel/123 و ساب site.ir:8443/sub/99?a=1 و نسخه 1.0.3') === 'کانال t.me/UmbrellaVPN_Channel/123 و ساب site.ir:8443/sub/99?a=1 و نسخه ۱.۰.۳', 'scheme-less links with path and port keep English digits');
assertOk(Helper::digitsToPersian('کانفیگ hy2://pw9@185.10.20.30:8443?sni=a1.ir#Srv1 و socks5://user1:pass2@127.0.0.1:10808') === 'کانفیگ hy2://pw9@185.10.20.30:8443?sni=a1.ir#Srv1 و socks5://user1:pass2@127.0.0.1:10808', 'all VPN protocol links keep English digits');
assertOk(Helper::digitsToPersian('مسیر: C:\\Users\\Ali123\\Downloads\\bad2.exe و <code>/sdcard/2026/app1.apk</code> و <code>185.10.20.30:4444</code>') === 'مسیر: C:\\Users\\Ali123\\Downloads\\bad2.exe و <code>/sdcard/2026/app1.apk</code> و <code>185.10.20.30:4444</code>', 'file paths and IPv4 inside/outside code blocks keep English digits');
assertOk(Helper::digitsToPersian('<a href="https://site.ir/u/123">لینک 2</a> و <a href=\'https://t.me/c/123/4\'>پست 5</a> و [مشاهده 3](https://site.ir/v1/23) و [https://site.ir/12](https://site.ir/12)') === '<a href="https://site.ir/u/123">لینک ۲</a> و <a href=\'https://t.me/c/123/4\'>پست ۵</a> و [مشاهده ۳](https://site.ir/v1/23) و [https://site.ir/12](https://site.ir/12)', 'HTML href attributes and Markdown URLs keep English digits while labels localize');
assertOk(Helper::digitsToPersian('فایل Umbrella-VPN-1.0.3-setup.exe و ابزار 3x-ui') === 'فایل Umbrella-VPN-1.0.3-setup.exe و ابزار 3x-ui', 'release filenames and digit-leading technical tokens keep English digits');
assertOk(Helper::formatPlatform('windows') === 'ویندوز', 'windows platform localized');
assertOk(Helper::formatPlatform('Windows 11') === 'ویندوز ۱۱', 'Windows 11 localized with Persian digits');
assertOk(Helper::formatPlatform('android') === 'اندروید', 'android localized');
assertOk(Helper::formatPlatform('iOS 18') === 'آی او اس ۱۸', 'iOS localized');
assertOk(Helper::formatPlatform('macOS') === 'مک', 'macOS localized');
assertOk(Helper::formatPlatform('linux') === 'لینوکس', 'linux localized');
assertOk(Helper::formatPlatform('') === 'ثبت نشده', 'empty platform localized');
$FormattedDt = Helper::formatDateTimeText('2026-03-21 14:05:00');
assertOk(preg_match('/[0-9]/', $FormattedDt) !== 1 && str_contains($FormattedDt, '۱۴:۰۵'), 'formatDateTimeText renders Persian Jalali date and time');

// 3. TelegramClient strips ZWNJ and converts all digits in prose and buttons.
require_once $Root . '/Bot/Menu.php';
require_once $Root . '/Core/Telegram/Telegram.php';
$Rendered = TelegramClient::md("دستگاه\u{200C}های فعال: 3 از ٥ — کلید: <code>wg-key-99</code> — شناسه: <code>12345</code>");
assertOk(!str_contains($Rendered, "\u{200C}"), 'TelegramClient::md removes all ZWNJ');
assertOk(str_contains($Rendered, '۳ از ۵') && str_contains($Rendered, '<code>۱۲۳۴۵</code>') && str_contains($Rendered, '<code>wg-key-99</code>'), 'TelegramClient::md renders Persian digits while keeping key intact');
$Kb = TelegramClient::inlineKeyboard([[['text' => "صفحه\u{200C}ی 2 از ٤", 'callback_data' => 'page:2']]]);
$BtnText = $Kb['inline_keyboard'][0][0]['text'] ?? '';
assertOk($BtnText === 'صفحه ی ۲ از ۴' && ($Kb['inline_keyboard'][0][0]['callback_data'] ?? '') === 'page:2', 'inlineKeyboard removes ZWNJ and renders Persian digits without altering callback_data');

// 4. ZarinPal messages are pure Persian, ZWNJ-free, with Persian digits.
require_once $Root . '/Core/Payment/ZarinPal.php';
foreach ([-9, -10, -11, -12, -13, -14, -15, -16, -17, -18, -19, -40, -41, -50, -51, -52, -53, -54, -55, -60, -61, -62, -63, 100, 101, -1000, -1001, -1002, -1003, -1004, -777] as $Code) {
$Msg = Zarinpal::errorMessage($Code);
assertOk(!str_contains($Msg, "\u{200C}"), "Zarinpal error {$Code} has no ZWNJ");
assertOk(preg_match('/[A-Za-z0-9\x{0660}-\x{0669}]/u', $Msg) !== 1, "Zarinpal error {$Code} is pure Persian with Persian digits: {$Msg}");
}

assertOk($CapturedErrors === [], 'Zero PHP warnings/notices/deprecations throughout test: ' . implode(' | ', $CapturedErrors));
echo "OK Persian text, digits, no-ZWNJ & PHP 8.5 compatibility ({$Assertions} assertions)\n";
