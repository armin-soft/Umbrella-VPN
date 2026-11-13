<?php
declare(strict_types=1);

/**
 * چیدمان مشترک منوهای ربات.
 *
 * هر منو در ربات از سه بخش ساخته می شود: «متن» که بخش فعلی و محتوای آن را نشان
 * می دهد، «دکمه ها» که در ردیف های حداکثر دو تایی چیده می شوند و «ناوبری» که
 * همیشه یک دکمه بازگشت به منوی قبل و یک دکمه بازگشت به منوی اصلی دارد.
 *
 * این کلاس همه این ها را در یک جا نگه می دارد تا متن دکمه های «بازگشت» در کل
 * ربات یکسان بماند و دیگر لازم نباشد هر صفحه متن و callback خودش را از نو
 * بسازد.
 */
final class Menu {
/** تنها برچسب دکمه بازگشت در کل ربات. */
public const BACK_LABEL = '🔙بازگشت';

private function __construct() {
}

/** منوی اصلی مدیریت؛ همه دکمه های بازگشت ادمین به اینجا ختم می شوند. */
public const ADMIN_HOME_CALL = 'مدیریت';

/** منوی اصلی کاربر. */
public const USER_HOME_CALL = 'منوی خدمات ربات';

/** بیشتر از این تعداد دکمه در یک ردیف، در موبایل بریده می شود. */
public const ROW_LIMIT = 2;

/**
 * یک دکمه.
 *
 * @param string $Label متن دکمه، بدون فاصله اضافی.
 * @param string $Call  مقدار callback_data که باید در Dispatcher مسیر داشته باشد.
 */
public static function button(string $Label, string $Call): array {
return ['text' => trim($Label), 'callback_data' => trim($Call)];
}

/** دکمه لینک؛ همیشه تنها در ردیف خودش می آید. */
public static function link(string $Label, string $Url): array {
return ['text' => trim($Label), 'url' => trim($Url)];
}

/**
 * ساخت ردیف ها از جفت های [برچسب، فراخوان].
 *
 * هر عضو آرایه یک ردیف است و هر ردیف می تواند یک یا دو جفت داشته باشد:
 *
 *     Menu::rows([['👤پروفایل', 'پروفایل کاربری'], ['💎اشتراک من', 'اشتراک من']])
 *
 * ردیف های سه دکمه ای یا بیشتر پذیرفته نمی شوند تا چیدمان به هم نریزد.
 */
public static function rows(array $Rows): array {
$Out = [];

foreach ($Rows as $Row) {
if (!is_array($Row)) {
continue;
}

$Buttons = [];

foreach ($Row as $Pair) {
if (!is_array($Pair) || count($Pair) < 2) {
continue;
}

$Label = trim((string)$Pair[0]);
$Call = trim((string)$Pair[1]);

if ($Label === '' || $Call === '') {
continue;
}

$Buttons[] = self::button($Label, $Call);

if (count($Buttons) >= self::ROW_LIMIT) {
break;
}
}

if ($Buttons !== []) {
$Out[] = $Buttons;
}
}

return $Out;
}

/**
 * دکمه بازگشت به منوی قبل.
 *
 * برچسب همه دکمه های بازگشت در کل ربات یکی است: «🔙بازگشت». نام مقصد روی دکمه
 * نمی آید تا دکمه کوتاه بماند و در موبایل بریده نشود؛ خود مقصد با صفحه ای که
 * باز می شود و دکمه خانه مشخص است. `$Title` فقط برای سازگاری با فراخوانی های
 * موجود نگه داشته شده و استفاده نمی شود.
 */
public static function back(string $Title, string $Call): array {
unset($Title);

return [self::button(self::BACK_LABEL, $Call)];
}

/** دکمه خانه ادمین. */
public static function adminHome(): array {
return [self::button('🏠منوی مدیریت', self::ADMIN_HOME_CALL)];
}

/** دکمه خانه کاربر. */
public static function userHome(): array {
return [self::button('🏠منوی اصلی', self::USER_HOME_CALL)];
}

/**
 * ردیف های پایانی صفحه های مدیریت: بازگشت به منوی قبل و خانه.
 *
 * اگر صفحه مستقیماً زیر منوی مدیریت باشد، دو دکمه به یک مقصد می رسند و تکرار
 * دکمه هم معنا ندارد؛ در آن حالت فقط خانه نمایش داده می شود.
 */
public static function adminNav(string $Back_Title, string $Back_Call): array {
if (trim($Back_Call) === self::ADMIN_HOME_CALL) {
return [self::adminHome()];
}

return [self::back($Back_Title, $Back_Call), self::adminHome()];
}

/** ردیف های پایانی صفحه های کاربر؛ با همان قاعده تکرار نشدن خانه. */
public static function userNav(string $Back_Title, string $Back_Call): array {
if (trim($Back_Call) === self::USER_HOME_CALL) {
return [self::userHome()];
}

return [self::back($Back_Title, $Back_Call), self::userHome()];
}

/**
 * فهرست گلوله ای برای متن پیام: همه خط ها با «├─» و خط آخر با «└─».
 *
 * @param string[] $Items
 */
public static function bullets(array $Items): string {
$Items = array_values(array_filter(array_map(static fn ($Item): string => trim((string)$Item), $Items), static fn (string $Item): bool => $Item !== ''));
$Last = count($Items) - 1;
$Out = '';

foreach ($Items as $Index => $Item) {
$Out .= ($Index === $Last ? '└─' : '├─') . $Item . "\n";
}

return $Out;
}

/**
 * یک بخش از پیام: عنوان و خط های زیر آن.
 *
 * @param string[] $Items
 */
public static function section(string $Icon, string $Title, array $Items = []): string {
$Text = "\n" . trim($Icon . ' ' . $Title) . "\n";

if ($Items !== []) {
$Text .= self::bullets($Items);
}

return $Text;
}

/**
 * آیا این کیبورد فقط دکمه های ناوبری دارد؟
 *
 * کیبورد را به شکلی که TelegramClient::inlineKeyboard می سازد
 * (`['inline_keyboard' => [[...]]]`) یا به شکل خام ردیف ها می پذیرد. دکمه های
 * «بازگشت»، «منوی اصلی/مدیریت»، «انصراف»، «لغو» و دکمه های با ایموجی 🏠 ناوبری اند؛
 * هر دکمه دیگر یعنی صفحه چیزی برای انتخاب دارد. در صفحه ای که فقط ناوبری است،
 * جمله «بر روی منوی مورد نظر کلیک کنید» باید حذف شود.
 */
public static function isNavigationOnly(array $Markup): bool {
$Rows = $Markup['inline_keyboard'] ?? $Markup;

if (!is_array($Rows) || $Rows === []) return false;
$Seen = 0;

foreach ($Rows as $Row) {
if (!is_array($Row)) continue;

foreach ($Row as $Button) {
if (!is_array($Button)) continue;
$Text = trim((string)($Button['text'] ?? ''));
$Call = trim((string)($Button['callback_data'] ?? ''));

if ($Text === '') continue;
$Seen++;

if (isset($Button['url']) || isset($Button['web_app'])) return false;
if (str_contains($Text, '🏠')) continue;
if (str_contains($Text, 'بازگشت')) continue;
if (str_contains($Text, 'انصراف')) continue;
if (str_contains($Text, 'لغو')) continue;
if (in_array($Call, [self::ADMIN_HOME_CALL, self::USER_HOME_CALL], true)) continue;

return false;
}
}

return $Seen > 0;
}

/**
 * حذف جمله پایانی «👌جهت استفاده از امکانات …» همراه با خط جداکننده بالای آن.
 *
 * همان قاعده ای که TelegramClient پیش از ارسال اجرا می کند؛ اینجا گذاشته شده تا
 * آزمون ها بدون نیاز به کلاینت تلگرام همان رفتار را بسنجند.
 */
public static function stripFooter(string $Text): string {
$Stripped = (string)preg_replace('/\n*[➖—\-]{3,}\s*\n+\s*👌\s*جهت استفاده از امکانات[^\n]*/u', '', $Text);
$Stripped = (string)preg_replace('/\n*(?:[➖—\-]{3,}\s*)+$/u', '', $Stripped);
$Stripped = rtrim($Stripped, " \t\n*");

return $Stripped === '' ? $Text : $Stripped;
}

/**
 * بررسی سلامت یک کیبورد پیش از ارسال.
 *
 * هر خطا یک رشته فارسی است؛ آرایه خالی یعنی دکمه ها سالم اند. متن خالی، متن
 * بلندتر از ۶۴ نویسه، callback_data بلندتر از ۶۴ بایت و دکمه تکراری رد می شوند
 * چون تلگرام در این حالت ها یا دکمه را نمی پذیرد یا کل پیام را نامعتبر می داند.
 *
 * @return string[]
 */
public static function problems(array $Rows): array {
$Problems = [];
$Seen = [];

foreach ($Rows as $Row_Index => $Row) {
if (!is_array($Row) || $Row === []) {
$Problems[] = 'ردیف ' . ($Row_Index + 1) . ' خالی است.';
continue;
}

foreach ($Row as $Button) {
if (!is_array($Button)) {
$Problems[] = 'ردیف ' . ($Row_Index + 1) . ' دکمه نامعتبر دارد.';
continue;
}

$Text = trim((string)($Button['text'] ?? ''));
$Data = trim((string)($Button['callback_data'] ?? ''));

if ($Text === '') {
$Problems[] = 'ردیف ' . ($Row_Index + 1) . ' دکمه بدون متن دارد.';
continue;
}

if (mb_strlen($Text) > 64) {
$Problems[] = 'متن دکمه «' . mb_substr($Text, 0, 20) . '…» بیش از ۶۴ نویسه است.';
}

if ($Data === '') {
continue;
}

if (strlen($Data) > 64) {
$Problems[] = 'callback_data دکمه «' . $Text . '» بیش از ۶۴ بایت است.';
}

if (isset($Seen[$Data])) {
$Problems[] = 'دکمه تکراری در همین صفحه: ' . $Data;
}

$Seen[$Data] = true;
}
}

return $Problems;
}
}
