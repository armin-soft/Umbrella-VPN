<?php
declare(strict_types=1);

/**
 * آزمون مسیر دکمه ها.
 *
 * هر callback_data که در دکمه های ربات ساخته می شود باید در Dispatcher.php
 * مسیر داشته باشد؛ در غیر این صورت دکمه به کاربر چیزی نشان نمی دهد. این آزمون
 * فایل ها را به صورت متن می خواند (بدون اجرای ربات) و این موارد را بررسی
 * می کند:
 *
 *   ۱. هیچ دکمه ای بی مسیر نباشد.
 *   ۲. مسیرهای پایه (منوی مدیریت، منوی کاربر و بخش های اصلی) پابرجا باشند.
 *   ۳. هیچ callback_data از ۶۴ بایت بیشتر نباشد.
 *
 * دکمه ها هم به شکل `'callback_data' => '…'` و هم به شکل جفت
 * `['برچسب', 'فراخوان']` داخل Menu::rows / Menu::button ساخته می شوند؛ هر دو
 * خوانده می شوند.
 *
 * اجرا:  php Telegram-BOT/tests/menu_routes_test.php
 */

$Root = dirname(__DIR__);
$Dispatcher = (string)file_get_contents($Root . '/Bot/Dispatcher.php');

/** مسیرهای جدول ROUTES و بلوک match. */
$Routes = [];

preg_match_all("/^\s*'([^']+)'\s*=>\s*\[/mu", $Dispatcher, $Route_Match);

foreach ($Route_Match[1] as $Key) {
$Routes[$Key] = true;
}

preg_match_all("/^\s*'([^']+)'\s*=>\s*[A-Z][A-Za-z]+::/mu", $Dispatcher, $Match_Match);

foreach ($Match_Match[1] as $Key) {
$Routes[$Key] = true;
}

/** مسیرهای پیشوندی مثل cfg_set: و ticket_view: و «خرید اشتراک …». */
preg_match_all("/str_starts_with\(\\\$Data,\s*'([^']+)'\)/u", $Dispatcher, $Prefix_Match);
$Prefixes = $Prefix_Match[1];

/**
 * مقادیری که Dispatcher در ابتدای routeCallbackInner و پیش از جدول مسیرها
 * پاسخ می دهد، مثل «start» و «بررسی عضویت کانال».
 */
$Early = ['start', '/start'];

preg_match_all("/\\$Data === '([^']+)'/u", $Dispatcher, $Early_Match);

foreach ($Early_Match[1] as $Key) {
$Early[] = $Key;
}

$Handled = static function (string $Call) use ($Routes, $Prefixes, $Early): bool {
if (in_array($Call, $Early, true)) return true;
if (isset($Routes[$Call])) return true;

foreach ($Prefixes as $Prefix) {
if ($Prefix !== '' && str_starts_with($Call, $Prefix)) return true;
}

return false;
};

/**
 * استخراج محتوای داخل پرانتزهای یک فراخوان، با شمارش عمق.
 */
$Balanced = static function (string $Source, int $Open_Paren): ?string {
$Depth = 0;
$Length = strlen($Source);

for ($Index = $Open_Paren; $Index < $Length; $Index++) {
$Char = $Source[$Index];

if ($Char === '(') {
$Depth++;
continue;
}

if ($Char === ')') {
$Depth--;

if ($Depth === 0) {
return substr($Source, $Open_Paren + 1, $Index - $Open_Paren - 1);
}
}
}

return null;
};

$Buttons = [];
$Checked = 0;
$Failures = [];

foreach (glob($Root . '/Bot/*.php') ?: [] as $File) {
$Name = basename($File);

if ($Name === 'Dispatcher.php') continue;

$Source = (string)file_get_contents($File);
$Found = [];

// شکل کلاسیک دکمه ها.
preg_match_all("/'callback_data'\s*=>\s*'([^']+)'/u", $Source, $Literal);
$Found = array_merge($Found, $Literal[1]);

// Menu::button / Menu::back با دو رشته ثابت.
preg_match_all("/Menu::(?:button|back)\('([^']*)',\s*'([^']+)'\)/u", $Source, $Named);
$Found = array_merge($Found, $Named[2]);

// جفت های ['برچسب', 'فراخوان'] داخل Menu::rows(...).
$Offset = 0;

while (($Start = strpos($Source, 'Menu::rows(', $Offset)) !== false) {
$Open = $Start + strlen('Menu::rows');
$Block = $Balanced($Source, $Open);
$Offset = $Start + strlen('Menu::rows(');

if ($Block === null) continue;

preg_match_all("/\[\s*'([^']*)'\s*,\s*'([^']+)'\s*\]/u", $Block, $Pairs);
$Found = array_merge($Found, $Pairs[2]);
}

foreach (array_unique($Found) as $Call) {
$Checked++;
$Buttons[$Call][] = $Name;

if (strlen($Call) > 64) {
$Failures[] = $Name . ': callback_data longer than 64 bytes: ' . mb_substr($Call, 0, 40);
}

if (!$Handled($Call)) {
$Failures[] = $Name . ': no handler in Dispatcher for callback «' . $Call . '»';
}
}
}

/** مسیرهای پایه ای که نباید هرگز حذف شوند. */
$Required = [
'مدیریت',
'منوی خدمات ربات',
'منوی پشتیبانی',
'اعتبار حساب کاربری',
'جرایم',
'پیکربندی سرور',
'منوی گزارش',
'منوی پیامک',
'مدیریت تیکت ها',
'device_limit_menu',
'تنظیمات ربات',
'cfg_pricing',
'cfg_links',
'پروفایل کاربری',
'اشتراک من',
];

foreach ($Required as $Call) {
if (!isset($Routes[$Call])) {
$Failures[] = 'Dispatcher: required route is missing: «' . $Call . '»';
}
}

foreach ($Failures as $Failure) {
fwrite(STDERR, 'FAIL ' . $Failure . "\n");
}

echo $Checked . ' distinct button callbacks checked, ' . count($Failures) . " failures\n";
exit($Failures === [] ? 0 : 1);
