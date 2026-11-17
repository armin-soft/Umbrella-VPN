<?php
declare(strict_types=1);

/**
 * آزمون چیدمان منوهای ربات.
 *
 * ربات تست خودکار ندارد و تنها راه اطمینان، بررسی خود کیبوردهاست. این فایل
 * بدون اتصال به شبکه یا دیتابیس اجرا می شود: هر منو یک کلاس جعلی «Menu» می بیند
 * (همان فایل واقعی) و برای هر منو فقط ساختار دکمه ها سنجیده می شود:
 *
 *   - متن دکمه خالی نباشد و از ۶۴ نویسه بیشتر نشود.
 *   - callback_data از ۶۴ بایت بیشتر نشود (تلگرام رد می کند).
 *   - در یک صفحه دو دکمه با callback یکسان نباشد.
 *   - هر ردیف حداکثر دو دکمه داشته باشد تا در موبایل بریده نشود.
 *   - هر صفحه پایانی برای بازگشت داشته باشد.
 *
 * اجرا:  php Telegram-BOT/tests/menu_layout_test.php
 * کد خروج صفر یعنی همه صفحه ها سالم اند.
 */

// چند تابع mb_* در بعضی نصب های PHP بدون افزونه mbstring نیستند؛ برای این که
// آزمون منوها به همان نصب وابسته نباشد، نسخه ساده آن ها اینجا تعریف می شود.
if (!function_exists('mb_strlen')) {
// PHP 8 اجازه می دهد تابع شرطی تعریف شود؛ اگر mbstring نصب باشد این بلوک اجرا نمی شود.
eval('function mb_strlen(string $Text): int { return count(preg_split("//u", $Text, -1, PREG_SPLIT_NO_EMPTY) ?: []); }');
}

if (!function_exists('mb_substr')) {
eval('function mb_substr(string $Text, int $Start, ?int $Length = null): string { $Chars = preg_split("//u", $Text, -1, PREG_SPLIT_NO_EMPTY) ?: []; $Slice = $Length === null ? array_slice($Chars, $Start) : array_slice($Chars, $Start, $Length); return implode("", $Slice); }');
}

require_once dirname(__DIR__) . '/Bot/Menu.php';

/**
 * همان کاری که TelegramClient::inlineKeyboard می کند، بدون بارگذاری کلاینت
 * تلگرام در این آزمون: ردیف های خالی حذف و کیبورد در پوشش استاندارد پیچیده
 * می شود.
 */
function test_keyboard(array $Rows): array {
$Clean = [];

foreach ($Rows as $Row) {
if (is_array($Row) && $Row !== []) $Clean[] = $Row;
}

return ['inline_keyboard' => $Clean];
}

final class MenuLayoutTest {
private int $Passed = 0;

/** @var string[] */
private array $Failures = [];

public function run(): int {
$this->test_rows_pair_layout();
$this->test_rows_drops_blank_and_extra_buttons();
$this->test_back_label_is_uniform();
$this->test_nav_rows_have_home();
$this->test_nav_in_place_skips_duplicate_home();
$this->test_bullets_last_item_marker();
$this->test_no_duplicate_back_row();
$this->test_section_layout();
$this->test_problems_accepts_clean_keyboard();
$this->test_problems_reports_long_callback();
$this->test_problems_reports_duplicate_button();
$this->test_problems_reports_blank_row();
$this->test_shared_keyboards_are_healthy();
$this->test_user_service_menu_categories();
$this->test_admin_menu_is_vertical();
$this->test_certificate_bundle_is_preserved();
$this->test_navigation_only_keyboard_is_detected();

foreach ($this->Failures as $Failure) {
fwrite(STDERR, 'FAIL ' . $Failure . "\n");
}

echo $this->Passed . ' assertions passed, ' . count($this->Failures) . " failed\n";
return $this->Failures === [] ? 0 : 1;
}

private function check(bool $Condition, string $Message): void {
if ($Condition) {
$this->Passed++;
return;
}

$this->Failures[] = $Message;
}

private function test_rows_pair_layout(): void {
$Rows = Menu::rows([
[['یک', 'one'], ['دو', 'two']],
[['سه', 'three']],
]);

$this->check(count($Rows) === 2, 'rows(): two input rows must stay two rows');
$this->check(count($Rows[0]) === 2, 'rows(): a pair must produce two buttons');
$this->check(count($Rows[1]) === 1, 'rows(): a single must produce one button');
$this->check($Rows[0][0] === ['text' => 'یک', 'callback_data' => 'one'], 'rows(): first button shape');
}

private function test_rows_drops_blank_and_extra_buttons(): void {
$Rows = Menu::rows([
[['', 'empty-label'], ['ok', 'ok-call']],
[['a', 'a'], ['b', 'b'], ['c', 'c']],
[['x', '']],
]);

$this->check(count($Rows) === 2, 'rows(): a row whose label and call are both blank is dropped');
$this->check(count($Rows[0]) === 1, 'rows(): only the valid button of the first row remains');
$this->check($Rows[0][0]['callback_data'] === 'ok-call', 'rows(): blank label dropped');
$this->check(count($Rows[1]) === Menu::ROW_LIMIT, 'rows(): the third button of a row is dropped');
}

/**
 * برچسب دکمه بازگشت به منوی قبل و منوی اصلی در همه صفحه ها یکدست است:
 * «🔙بازگشت به منوی قبل» و «🏠بازگشت به منوی اصلی».
 */
private function test_back_label_is_uniform(): void {
$Row = Menu::back('گزارش ها', 'منوی گزارش');
$this->check(count($Row) === 1, 'back(): one button');
$this->check($Row[0]['text'] === Menu::BACK_LABEL, 'back(): label is the shared Menu::BACK_LABEL');
$this->check($Row[0]['text'] === '🔙بازگشت به منوی قبل', 'back(): label text is exactly «🔙بازگشت به منوی قبل»');
$this->check($Row[0]['callback_data'] === 'منوی گزارش', 'back(): callback is untouched');

$Other = Menu::back('پیکربندی سرور', 'پیکربندی سرور');
$this->check($Other[0]['text'] === $Row[0]['text'], 'back(): the destination does not change the label');

$Nav = Menu::adminNav('بروز رسانی', 'بروز رسانی');
$this->check($Nav[0][0]['text'] === '🔙بازگشت به منوی قبل', 'adminNav(): the back row uses «🔙بازگشت به منوی قبل»');
$this->check($Nav[1][0]['text'] === '🏠بازگشت به منوی مدیریت', 'adminNav(): the home row uses «🏠بازگشت به منوی مدیریت»');
$this->check(Menu::userHome()[0]['text'] === '🏠بازگشت به منوی اصلی', 'userHome(): uses «🏠بازگشت به منوی اصلی»');
}

private function test_nav_rows_have_home(): void {
$Rows = Menu::adminNav('گزارش ها', 'منوی گزارش');
$this->check(count($Rows) === 2, 'adminNav(): back + home');
$this->check($Rows[1][0]['callback_data'] === Menu::ADMIN_HOME_CALL, 'adminNav(): home goes to the admin menu');

$User_Rows = Menu::userNav('پشتیبانی', 'منوی پشتیبانی');
$this->check(count($User_Rows) === 2, 'userNav(): back + home');
$this->check($User_Rows[1][0]['callback_data'] === Menu::USER_HOME_CALL, 'userNav(): home goes to the user menu');
}

private function test_nav_in_place_skips_duplicate_home(): void {
$Rows = Menu::adminNav('منوی مدیریت', Menu::ADMIN_HOME_CALL);
$this->check(count($Rows) === 1, 'adminNav(): a screen under the admin menu shows home once');
$this->check($Rows[0][0]['callback_data'] === Menu::ADMIN_HOME_CALL, 'adminNav(): the single row is home');
}

private function test_bullets_last_item_marker(): void {
$Text = Menu::bullets(['اول', 'دوم', 'سوم']);
$this->check(str_contains($Text, '├─اول'), 'bullets(): first line uses the branch marker');
$this->check(str_contains($Text, '└─سوم'), 'bullets(): last line uses the end marker');
$this->check(substr_count($Text, "\n") === 3, 'bullets(): one line per item');
$this->check(Menu::bullets([]) === '', 'bullets(): empty input gives empty text');
$this->check(Menu::bullets(['', '  ']) === '', 'bullets(): blank items are dropped');
}

/**
 * دو دکمه با یک برچسب ولی دو مقصد در یک صفحه، کاربر را سرگردان می کند؛ با
 * برچسب یکدست «🔙بازگشت» هم نباید در یک کیبورد دوتا شود.
 */
private function test_no_duplicate_back_row(): void {
$Rows = [
Menu::back('گزارش ها', 'منوی گزارش'),
Menu::back('دیتابیس', 'دیتابیس'),
];

$Labels = [];

foreach ($Rows as $Row) {
$Labels[] = $Row[0]['text'];
}

$this->check(count(array_unique($Labels)) === 1, 'back(): every back button carries the same label');
$this->check(count($Rows) === 2 && $Rows[0][0]['callback_data'] !== $Rows[1][0]['callback_data'], 'back(): destinations stay different when the labels match');
}

private function test_section_layout(): void {
$Text = Menu::section('📊', 'گزارش ها', ['آمار کلی']);
$this->check(str_starts_with($Text, "\n📊 گزارش ها\n"), 'section(): header line with icon');
$this->check(str_contains($Text, '└─آمار کلی'), 'section(): bullets follow the header');
}

private function test_problems_accepts_clean_keyboard(): void {
$Rows = array_merge(
Menu::rows([['پروفایل', 'پروفایل کاربری'], ['اشتراک', 'اشتراک من']]),
[Menu::userHome()]
);

$this->check(Menu::problems($Rows) === [], 'problems(): a clean keyboard has no findings');
}

private function test_problems_reports_long_callback(): void {
$Rows = [[Menu::button('دکمه', str_repeat('x', 65))]];
$this->check(count(Menu::problems($Rows)) === 1, 'problems(): a 65-byte callback is reported');
}

private function test_problems_reports_duplicate_button(): void {
$Rows = [[Menu::button('یکی', 'same')], [Menu::button('دیگری', 'same')]];
$Problems = Menu::problems($Rows);
$this->check(count($Problems) === 1, 'problems(): a duplicated callback is reported once');
$this->check(str_contains((string)($Problems[0] ?? ''), 'same'), 'problems(): the report names the callback');
}

private function test_problems_reports_blank_row(): void {
$Rows = [Menu::userHome(), []];
$Problems = Menu::problems($Rows);
$this->check(count($Problems) === 1, 'problems(): an empty row is reported');
}

/** Validate actual production main menu rows instead of copied fixtures. */
private function test_user_service_menu_categories(): void {
$Source = (string)file_get_contents(dirname(__DIR__) . '/Bot/User.php');
$Start = strpos($Source, 'public static function serviceMenu(');
$End = strpos($Source, 'private static function categoryMenu(', $Start);
$Body = substr($Source, $Start, $End - $Start);
$this->check(str_contains($Body, "['Flow' => null]"), 'user home cancels input');
$this->check_main_rows($Body, 'Menu_Rows', [
'user_subscriptions_menu', 'user_wallet_menu', 'user_account_menu', 'user_device_menu',
'user_stats_menu', 'منوی پشتیبانی', 'تغییرات نسخه',
]);
}

private function test_admin_menu_is_vertical(): void {
$Source = (string)file_get_contents(dirname(__DIR__) . '/Bot/Admin.php');
$Start = strpos($Source, 'public static function menu(');
$End = strpos($Source, 'private static function categoryMenu(', $Start);
$Body = substr($Source, $Start, $End - $Start);
$this->check_main_rows($Body, 'Markup', [
'اعتبار حساب کاربری', 'جرایم', 'admin_devices_menu', 'admin_accounts_menu',
'عملیات کلاینت سرور', 'پیکربندی سرور', 'منوی گزارش', 'منوی پیامک',
'مدیریت تیکت ها', 'admin_subscriptions_menu', 'منوی سیستم', 'بروز رسانی',
]);
$this->check(str_contains($Body, 'array_unshift($Markup, [Menu::button($Robot_On'), 'robot toggle is the first row');
}

private function check_main_rows(string $Body, string $Variable, array $Expected): void {
if (!preg_match('/\$' . $Variable . ' = Menu::rows\((\[.*?\])\);/s', $Body, $Match)) {
$this->check(false, 'production main menu rows must exist');
return;
}
$Rows = Menu::rows(eval('return ' . $Match[1] . ';'));
$this->check(Menu::problems($Rows) === [], 'production keyboard is valid');
$this->check(array_column(array_merge(...$Rows), 'callback_data') === $Expected, 'exact main menu order');
foreach ($Rows as $Row) $this->check(count($Row) === 1, 'main menu is single-column');
}

/** گواهی محلی ربات باید همراه ساختار منو و بسته ربات حفظ شود. */
private function test_certificate_bundle_is_preserved(): void {
$Root = dirname(__DIR__);
$Certificate = $Root . '/Cert/Cacert.Pem';
$Http_Source = (string)file_get_contents($Root . '/Core/Support/Http.php');
$this->check(is_file($Certificate) && filesize($Certificate) > 0, 'Telegram-BOT/Cert/Cacert.Pem exists and is non-empty');
$this->check(str_contains($Http_Source, "'/Cert/Cacert.Pem'"), 'HTTP client still falls back to the bundled certificate');
}

/**
 * «کیبورد فقط-ناوبری» همان حالتی است که جمله پایانی «بر روی منوی مورد نظر
 * کلیک کنید» در آن حذف می شود: صفحه ای که فقط دکمه بازگشت و خانه دارد.
 */
private function test_navigation_only_keyboard_is_detected(): void {
$Nav_Only = [
'only-home' => [Menu::adminHome()],
'home-and-back' => [Menu::back('گزارش ها', 'منوی گزارش'), Menu::userHome()],
'with-cancel' => [[Menu::button('🔙انصراف از شارژ', 'لغو شارژ اعتبار')], Menu::userHome()],
];

foreach ($Nav_Only as $Name => $Rows) {
$Markup = test_keyboard($Rows);
$this->check(Menu::isNavigationOnly($Markup), $Name . ': a navigation-only keyboard is detected');
}

$With_Choice = test_keyboard(array_merge(
Menu::rows([[['➕افزایش اعتبار', 'افزایش اعتبار اول'], ['➖کسر اعتبار', 'کسر اعتبار اول']]]),
[Menu::adminHome()]
));

$this->check(!Menu::isNavigationOnly($With_Choice), 'a keyboard with a real action is not navigation-only');
$this->check(!Menu::isNavigationOnly(test_keyboard([[Menu::link('🎧پشتیبانی', 'https://t.me/x')]])), 'a link button counts as an action');
$this->check(!Menu::isNavigationOnly([]), 'an empty keyboard is not navigation-only');
}

/**
 * کیبوردهایی که مستقیم در این فایل ساخته می شوند و نماینده چیدمان منوهای
 * واقعی اند. اگر کسی ردیفی سه دکمه ای یا شناسه تکراری اضافه کند، اینجا
 * شکست می خورد.
 */
private function test_shared_keyboards_are_healthy(): void {
$Keys = [
'app-account' => Menu::userNav('حساب کاربری', 'user_account_menu'),
'support' => Menu::userNav('پشتیبانی', 'منوی پشتیبانی'),
'app-devices' => array_merge(
Menu::rows([
[['✅صدور مجوز · دستگاه اول', 'admin_device_toggle:device-one:0']],
[['⛔️لغو مجوز · دستگاه دوم', 'admin_device_toggle:device-two:0']],
[['🔐تنظیم سقف دستگاه حساب', 'device_limit_menu']],
]),
[Menu::adminHome()]
),
'settings' => array_merge(
Menu::rows([
[['🚱روشن / خاموش کانفیگ اضطراری', 'emergency_toggle']],
[['🔗آدرس کانفیگ اضطراری', 'emergency_url_start']],
]),
[Menu::adminHome()]
),
];

foreach ($Keys as $Name => $Rows) {
$Problems = Menu::problems($Rows);
$this->check($Problems === [], $Name . ': ' . implode(' | ', $Problems));

foreach ($Rows as $Index => $Row) {
$this->check(count($Row) <= Menu::ROW_LIMIT, $Name . ': row ' . ($Index + 1) . ' has more than ' . Menu::ROW_LIMIT . ' buttons');
}
}
}
}

exit((new MenuLayoutTest())->run());
