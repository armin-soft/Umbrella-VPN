<?php
declare(strict_types=1);

/**
 * آزمون قاعده «جمله پایانی فقط وقتی که منو دارد».
 *
 * قاعده: پیامی که کیبورد ندارد یا کیبوردش فقط خانه/بازگشت/انصراف است نباید
 * جمله «👌جهت استفاده از امکانات …» و خط جداکننده بالای آن را داشته باشد.
 * این فایل بدون شبکه، دیتابیس و mbstring اجرا می شود.
 */

require_once dirname(__DIR__) . '/Bot/Menu.php';

const TEST_SEPARATOR = '➖➖➖➖➖➖➖➖➖';

function test_admin_footer(): string {
return "\n" . TEST_SEPARATOR . "\n👌جهت استفاده از امکانات مدیریت بر روی منوی مورد نظر کلیک کنید.";
}

function test_user_footer(): string {
return "\n" . TEST_SEPARATOR . "\n👌جهت استفاده از امکانات ربات بر روی منوی مورد نظر کلیک کنید.";
}

function test_keyboard(array $Rows): array {
$Clean = [];

foreach ($Rows as $Row) {
if (is_array($Row) && $Row !== []) $Clean[] = $Row;
}

return ['inline_keyboard' => $Clean];
}

final class MenuFooterTest {
private int $Passed = 0;
private array $Failures = [];

public function run(): void {
$this->test_footer_is_dropped_without_keyboard();
$this->test_footer_is_kept_with_real_menu();
$this->test_footer_is_dropped_for_navigation_only_keyboard();
$this->test_footer_is_kept_for_link_buttons();
$this->test_separator_length_is_uniform();

if ($this->Failures !== []) {
fwrite(STDERR, "FAILURES (menu footer)\n");

foreach ($this->Failures as $Failure) {
fwrite(STDERR, ' - ' . $Failure . "\n");
}

fwrite(STDERR, count($this->Failures) . " failed, {$this->Passed} passed\n");
exit(1);
}

echo "OK menu footer tests ({$this->Passed} assertions)\n";
}

private function check(bool $Condition, string $Message): void {
if ($Condition) {
$this->Passed++;
return;
}

$this->Failures[] = $Message;
}

/**
 * همان قاعده ای که TelegramClient پیش از ارسال اعمال می کند: بی کیبورد یا
 * کیبورد فقط-ناوبری ⇒ جمله پایانی و خط جداکننده اش می روند.
 */
private function trim(string $Text, array $Markup): string {
if ($Text === '') return $Text;
if ($Markup !== [] && !Menu::isNavigationOnly($Markup)) return $Text;

return Menu::stripFooter($Text);
}

/** صفحه ای بدون کیبورد اصلاً نباید جمله پایانی داشته باشد. */
private function test_footer_is_dropped_without_keyboard(): void {
$Text = "🌹مدیریت گرامی آرمین اسکندری به بخش مجوز دستگاه کاربران خوش آمدید.\n📱چند دستگاه؟" . test_admin_footer();
$Out = $this->trim($Text, []);

$this->check(!str_contains($Out, 'جهت استفاده از امکانات'), 'footer removed when there is no keyboard');
$this->check(!str_contains($Out, TEST_SEPARATOR), 'separator removed together with the footer');
$this->check(str_contains($Out, 'چند دستگاه؟'), 'body content is untouched');
}

/** منویی که واقعاً چند گزینه دارد، جمله پایانی را نگه می دارد. */
private function test_footer_is_kept_with_real_menu(): void {
$Text = "🌹مدیریت گرامی … خوش آمدید.\n🗂گروه های منو" . test_admin_footer();
$Markup = test_keyboard(Menu::rows([
[['👥کاربران و اعتبار', 'اعتبار حساب کاربری'], ['🚫مسدودیت کاربران', 'جرایم']],
]));

$Out = $this->trim($Text, $Markup);

$this->check(str_contains($Out, 'جهت استفاده از امکانات مدیریت'), 'footer kept when the keyboard has real options');
}

/** صفحه «شناسه کاربر را بفرستید» فقط خانه/بازگشت دارد ⇒ جمله حذف. */
private function test_footer_is_dropped_for_navigation_only_keyboard(): void {
$Text = "🌹مدیریت گرامی … خوش آمدید.\n👌شناسه عددی یا شماره موبایل را بفرستید." . test_admin_footer();
$Home_Only = test_keyboard([Menu::adminHome()]);
$Back_And_Home = test_keyboard([
Menu::back('گزارش ها', 'منوی گزارش'),
Menu::adminHome(),
]);

foreach (['home only' => $Home_Only, 'back and home' => $Back_And_Home] as $Name => $Markup) {
$Out = $this->trim($Text, $Markup);
$this->check(!str_contains($Out, 'جهت استفاده از امکانات'), $Name . ': footer dropped');
$this->check(!str_contains($Out, TEST_SEPARATOR), $Name . ': separator dropped');
$this->check(str_contains($Out, 'شناسه عددی'), $Name . ': body kept');
}
}

/** دکمه لینک هم «امکان» است و جمله را نگه می دارد. */
private function test_footer_is_kept_for_link_buttons(): void {
$Text = "🌹کاربر گرامی … خوش آمدید.\n📣کانال ما" . test_user_footer();
$Markup = test_keyboard([
Menu::link('📣کانال تلگرام', 'https://t.me/umbrella'),
Menu::userHome()[0],
]);

$this->check(str_contains($this->trim($Text, $Markup), 'جهت استفاده از امکانات ربات'), 'link-only keyboard keeps the footer');
}

/** همه خطهای جداکننده دقیقاً یک شکل باشند تا پایین صفحه ها یکسان دیده شود. */
private function test_separator_length_is_uniform(): void {
$Files = glob(dirname(__DIR__) . '/Bot/*.php') ?: [];
$Files[] = dirname(__DIR__) . '/Core/Support/Helper.php';

foreach ($Files as $File) {
$Source = (string)file_get_contents($File);

if (preg_match('/➖{10,}/u', $Source) === 1) {
$this->check(false, basename($File) . ': a separator longer than nine dashes is left');
}
}

$this->check(substr_count(test_admin_footer(), '➖') === 9, 'admin footer uses the nine-dash separator');
}
}

(new MenuFooterTest())->run();
