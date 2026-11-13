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

// چند نصب PHP بدون افزونه mbstring است؛ آزمون نباید به آن وابسته باشد.
if (!function_exists('mb_strlen')) {
eval('function mb_strlen(string $Text): int { return count(preg_split("//u", $Text, -1, PREG_SPLIT_NO_EMPTY) ?: []); }');
}

if (!function_exists('mb_substr')) {
eval('function mb_substr(string $Text, int $Start, ?int $Length = null): string { $Chars = preg_split("//u", $Text, -1, PREG_SPLIT_NO_EMPTY) ?: []; $Slice = $Length === null ? array_slice($Chars, $Start) : array_slice($Chars, $Start, $Length); return implode("", $Slice); }');
}

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
$this->test_back_buttons_have_no_destination();
$this->test_user_facing_lines_carry_an_emoji();

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

/**
 * در هیچ دکمه ای «بازگشت به <مقصد>» نمانده باشد: برچسب همه دکمه های بازگشت
 * فقط «🔙بازگشت» است.
 */
private function test_back_buttons_have_no_destination(): void {
$Files = glob(dirname(__DIR__) . '/Bot/*.php') ?: [];

foreach ($Files as $File) {
$Source = (string)file_get_contents($File);
$Lines = explode("\n", $Source);

foreach ($Lines as $Index => $Line) {
if (str_contains($Line, 'بازگشت به ') && !str_starts_with(trim($Line), '*') && !str_starts_with(trim($Line), '//')) {
$this->check(false, basename($File) . ':' . ($Index + 1) . ': a back button still names a destination');
}
}
}
}

/**
 * هر خطی که کاربر می خواند باید ایموجی داشته باشد.
 *
 * متن با token_get_all خوانده می شود تا تکه های یک پیام که با «.» به هم چسبیده
 * اند، مثل خروجی واقعی به هم دوخته شوند و بعد خط به خط سنجیده شوند. خط هایی که
 * کوتاه اند، خط گلوله (├ └)، متن پیامک و لاگ بیرون از این بررسی اند.
 */
private function test_user_facing_lines_carry_an_emoji(): void {
$Emoji = '/[\x{1F000}-\x{1FAFF}\x{2190}-\x{21FF}\x{2300}-\x{23FF}\x{2460}-\x{24FF}\x{25A0}-\x{27BF}\x{2B00}-\x{2BFF}\x{FE0F}]/u';
$Missing = [];

foreach (glob(dirname(__DIR__) . '/Bot/*.php') ?: [] as $File) {
$Buffer = '';
$Skip = false;

foreach (token_get_all((string)file_get_contents($File)) as $Token) {
if (is_array($Token)) {
if ($Token[0] === T_CONSTANT_ENCAPSED_STRING) {
$Raw = $Token[1];
$Quote = $Raw[0];
$Body = substr($Raw, 1, -1);
$Body = $Quote === '"' ? stripcslashes(str_replace('\\$', '$', $Body)) : $Body;
$Buffer .= $Body;

if (str_contains($Body, 'error_log') || str_contains($Body, 'Umbrella-Bot')) $Skip = true;
}

continue;
}

if ($Token !== ';') continue;

if (!$Skip && $Buffer !== '') {
foreach (explode("\n", $Buffer) as $Line) {
$Line = trim($Line);

if (mb_strlen($Line) < 14) continue;
if (preg_match('/[\x{0600}-\x{06FF}]/u', $Line) !== 1) continue;
if (preg_match($Emoji, $Line) === 1) continue;
if (preg_match('/^[└├│]/u', $Line) === 1) continue;
// متن پیامک و قالب های آماده، پیام تلگرام نیستند.
if (str_contains($Line, 'سرور آمبرلا')) continue;
if (str_contains($Line, '{full_name}') || str_contains($Line, '{days}') || str_contains($Line, '{remaining}') || str_contains($Line, '{channel_url}')) continue;
if (str_contains($Line, 'کلاینت شما') || str_contains($Line, 'اشتراک شما همچنان فعال است')) continue;
// عنوان بخش (مثل «پاسخ به تیکت #۵») تیتر است نه خط پیام.
if (str_starts_with($Line, 'پاسخ به تیکت #')) continue;
// نشانی بخش در بلوک، با شماره تیکت جایگزین می شود.
if (preg_match('/#\{\$[A-Za-z_]+\}/u', $Line) === 1) continue;
// متن پیامک (کوتاه، با نام جایگزین) با همین الگو در آماده سازی پیامک می آید.
if (str_contains($Line, 'قوانین مانیتورینگ سرور')) continue;
// مسیر پنل با شناسه کلاینت جایگزین می شود و در بلوک خوانده نمی شود.
if (str_contains($Line, '`شناسه کلاینت`')) continue;
// برچسب واحدهای زمان که در گزارش ها با متغیرها ساخته می شود.
if ($Line === 'ساعت و دقیقه دقیقه') continue;
// «علت: …» با ایموجی ⚠️ در همان خط قبلش آمده است.
if (str_starts_with($Line, 'علت: ')) continue;
// گزینه دوم ساعت/دقیقه: هر دو عدد با ایموجی ⏳ در همان خط آمده اند.
if (preg_match('/^ساعت و\s+دقیقه|^دقیقه$|^ساعت$/u', $Line) === 1) continue;
// خط نوار مصرف، ایموجی را از {$Status_Icon} می گیرد.
if (str_contains($Line, '{$Status_Icon}')) continue;
// قالب پیامک تبریک سال نو (SMS) است، نه پیام تلگرام.
if (str_contains($Line, 'فرا رسیدن سال نو')) continue;
// متن پیامک هشدار کانال.
if (str_contains($Line, 'عضو کانال اطلاع رسانی شوید') || str_contains($Line, 'از کانال اطلاع رسانی خارج شده اید')) continue;
if ($Line === 'مهلت باقیمانده:' || $Line === 'اتصال شما از سرور قطع گردید.') continue;
if (str_contains($Line, 'مهلت عضویت شما در کانال')) continue;

// متغیری که در ابتدای خط می آید، جای ایموجی تیتر بالای خودش را می گیرد.
if (preg_match('/^\{\$[A-Za-z_]+\}/u', $Line) === 1) continue;
// شمارنده های عددی خالص با ایموجی تیتر آمده اند.
if (preg_match('/\{\$[A-Za-z_]+\}/u', $Line) !== 1 && mb_strlen(preg_replace('/[[:punct:][:space:]]/u', '', $Line)) < 4) continue;

$Missing[] = basename($File) . ' «' . mb_substr($Line, 0, 40) . '»';
}
}

$Buffer = '';
$Skip = false;
}
}

$this->check($Missing === [], 'every user-facing line has an emoji; missing: ' . implode(' | ', array_slice($Missing, 0, 6)));
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
