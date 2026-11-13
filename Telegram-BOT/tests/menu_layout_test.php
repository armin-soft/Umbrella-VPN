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
$this->test_back_label_names_the_target();
$this->test_nav_rows_have_home();
$this->test_nav_in_place_skips_duplicate_home();
$this->test_bullets_last_item_marker();
$this->test_section_layout();
$this->test_problems_accepts_clean_keyboard();
$this->test_problems_reports_long_callback();
$this->test_problems_reports_duplicate_button();
$this->test_problems_reports_blank_row();
$this->test_shared_keyboards_are_healthy();
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

private function test_back_label_names_the_target(): void {
$Row = Menu::back('گزارش ها', 'منوی گزارش');
$this->check(count($Row) === 1, 'back(): one button');
$this->check($Row[0]['text'] === '🔙بازگشت به گزارش ها', 'back(): label names the destination');
$this->check($Row[0]['callback_data'] === 'منوی گزارش', 'back(): callback is untouched');
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

/**
 * «کیبورد فقط-ناوبری» همان حالتی است که جمله پایانی «بر روی منوی مورد نظر
 * کلیک کنید» در آن حذف می شود: صفحه ای که فقط دکمه بازگشت و خانه دارد.
 */
private function test_navigation_only_keyboard_is_detected(): void {
$Nav_Only = [
'only-home' => [Menu::adminHome()],
'home-and-back' => [Menu::back('گزارش ها', 'منوی گزارش'), Menu::userHome()],
'with-cancel' => [Menu::back('اشتراک من', 'اشتراک من'), Menu::userHome()],
];

foreach ($Nav_Only as $Name => $Rows) {
$Markup = test_keyboard($Rows);
$this->check(Menu::isNavigationOnly($Markup), $Name . ': a navigation-only keyboard is detected');
}

$With_Choice = test_keyboard(array_merge(
Menu::rows([['➕افزایش اعتبار', 'افزایش اعتبار اول'], ['➖کسر اعتبار', 'کسر اعتبار اول']]),
[Menu::adminHome()]
));

$this->check(!Menu::isNavigationOnly($With_Choice), 'a keyboard with a real action is not navigation-only');
$this->check(!Menu::isNavigationOnly(test_keyboard([Menu::link('🎧پشتیبانی', 'https://t.me/x')])), 'a link button counts as an action');
$this->check(!Menu::isNavigationOnly([]), 'an empty keyboard is not navigation-only');
}

/**
 * کیبوردهایی که مستقیم در این فایل ساخته می شوند و نماینده چیدمان منوهای
 * واقعی اند. اگر کسی ردیفی سه دکمه ای یا شناسه تکراری اضافه کند، اینجا
 * شکست می خورد.
 */
private function test_shared_keyboards_are_healthy(): void {
$Keys = [
'user-home' => array_merge(
Menu::rows([
[['👤پروفایل کاربری', 'پروفایل کاربری'], ['💎اشتراک من', 'اشتراک من']],
[['📊گزارش مصرف', 'گزارش مصرف'], ['🎫تیکت ها و پشتیبانی', 'منوی پشتیبانی']],
]),
Menu::rows([
[['📱حساب و تنظیمات برنامه', 'app_menu']],
[['🔄تغییرات نسخه', 'تغییرات نسخه']],
])
),
'admin-home' => array_merge(
[[Menu::button('🔴خاموش کردن ربات', 'خاموش کردن ربات')]],
Menu::rows([
[['👥کاربران و اعتبار', 'اعتبار حساب کاربری'], ['🚨مسدودیت کاربران', 'جرایم']],
[['📱مجوز دستگاه', 'device_limit_menu'], ['🎫مدیریت تیکت ها', 'مدیریت تیکت ها']],
]),
Menu::rows([
[['⚙️پیکربندی سرور', 'پیکربندی سرور'], ['💰تعرفه و پلن ها', 'cfg_pricing']],
[['🔗لینک ها و کانال', 'cfg_links']],
]),
Menu::rows([
[['📊گزارش ها و آمار', 'منوی گزارش'], ['💰گزارش مالی', 'گزارش مالی']],
[['🏆رتبه بندی کاربران', 'رتبه بندی'], ['📨پیامک و اطلاع رسانی', 'منوی پیامک']],
]),
Menu::rows([
[['🔄بروزرسانی نسخه', 'بروز رسانی'], ['🗄️دیتابیس', 'دیتابیس']],
[['⚙️تنظیمات ربات', 'تنظیمات ربات']],
])
),
'reports' => array_merge(
Menu::rows([
[['📊آمار کلی', 'آمار کلی'], ['📅گزارش روزانه', 'گزارش روزانه']],
[['💰گزارش مالی', 'گزارش مالی'], ['🏆رتبه بندی', 'رتبه بندی']],
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
