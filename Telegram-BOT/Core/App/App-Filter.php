<?php
declare(strict_types=1);

require_once __DIR__ . '/../Database/Database.php';

/**
 * Content-filter settings, shared by the desktop app and the bot.
 *
 * The app writes them from its settings screen, the bot writes them from its
 * filter menu, and either side reads the same row, so the two never disagree.
 * The category names match `ContentCategory` in the Flutter code.
 */
final class AppFilter {
/** حداکثر تعداد دامنه های سفارشی مسدودسازی برای هر حساب کاربری. */
public const MAX_CUSTOM_DOMAINS = 200;

/** تعداد دامنه های نمایشی در هر صفحه منوی ربات تلگرام. */
public const DOMAINS_PER_PAGE = 8;

/** دسته های قابل تنظیم در ربات؛ تنظیمات دیگر برنامه بدون حذف داده حفظ می شوند. */
public const BOT_CATEGORIES = [
'adult' => 'محتوای بزرگسال',
'gambling' => 'شرط بندی',
];

public const CATEGORIES = [
'adult' => 'محتوای بزرگسال',
'social' => 'شبکه های اجتماعی',
'gambling' => 'شرط بندی',
'streaming' => 'ویدیو و پخش',
'violence' => 'محتوای خشن',
'messaging' => 'پیام رسان ها',
];

/** Column per category, in the order of self::CATEGORIES. */
private const COLUMNS = [
'adult' => 'Adult',
'social' => 'Social',
'gambling' => 'Gambling',
'streaming' => 'Streaming',
'violence' => 'Violence',
'messaging' => 'Messaging',
];
private function __construct() {
}

private static function defaults(): array {
return [
'enabled' => false,
'categories' => [],
'custom_domains' => [],
'updated_by' => 'app',
'updated_at' => '',
];
}

private static function categoryList(mixed $Raw): array {
if (is_string($Raw)) {
$Raw = preg_split('/[\s,]+/', $Raw) ?: [];
}

if (!is_array($Raw)) return [];

$Out = [];

foreach ($Raw as $Item) {
$Key = strtolower(trim((string)$Item));

if ($Key !== '' && isset(self::CATEGORIES[$Key])) {
$Out[] = $Key;
}
}

return array_values(array_unique($Out));
}

/**
 * یک دامنه یا نشانی وب را به پسوند دامنه استاندارد تبدیل می کند (سازگار با کلاینت ویندوز).
 * مقادیر نامعتبر، آی پی خام، دامنه های محلی و دامنه خود درگاه ربات رد می شوند.
 */
public static function normalizeDomain(string $Raw): ?string {
$Value = trim($Raw);
if ($Value === '') return null;

// تبدیل ارقام فارسی و عربی به لاتین و حذف نویسه های نامرئی و کوتیشن های اطراف.
$Value = strtr($Value, [
'۰' => '0', '۱' => '1', '۲' => '2', '۳' => '3', '۴' => '4',
'۵' => '5', '۶' => '6', '۷' => '7', '۸' => '8', '۹' => '9',
'٠' => '0', '١' => '1', '٢' => '2', '٣' => '3', '٤' => '4',
'٥' => '5', '٦' => '6', '٧' => '7', '٨' => '8', '٩' => '9',
]);
$Value = preg_replace('/[\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2060}\x{FEFF}]/u', '', $Value) ?? $Value;
$Value = trim($Value, " \t\n\r\0\x0B\"'`<>()[]{}");
$Value = ltrim($Value, '+');
$Value = trim($Value);
if ($Value === '') return null;

// حذف پروتکل (https://، http://، socks5://، // و مانند آن).
$Value = preg_replace('#^[a-z][a-z0-9+.\-]*://#i', '', $Value) ?? $Value;
$Value = ltrim($Value, '/');

// حذف مسیر، پارامتر و بخش #fragment پیش از بررسی پورت و نام کاربری.
$Cut = strcspn($Value, '/?#\\');
$Value = substr($Value, 0, $Cut);

// حذف user:pass@ در صورت چسباندن لینک کامل.
$At = strrpos($Value, '@');
if ($At !== false) {
$Value = substr($Value, $At + 1);
}

// آی پی نسخه ۶ داخل کروشه رد می شود.
if (str_starts_with($Value, '[') || str_contains($Value, ':')) {
if (preg_match('/^([^:]+):(\d{1,5})$/', $Value, $Port_Match) === 1) {
$Value = $Port_Match[1];
} else {
return null;
}
}

// حذف الگوی wildcard و نقطه های ابتدا/انتها.
while (str_starts_with($Value, '*.') || str_starts_with($Value, '.')) {
$Value = ltrim(substr($Value, 1), '.');
}
$Value = rtrim($Value, '.');
if ($Value === '') return null;

$Value = function_exists('mb_strtolower') ? mb_strtolower($Value, 'UTF-8') : strtolower($Value);

// پشتیبانی از دامنه های بین المللی و فارسی (IDN -> Punycode).
if (preg_match('/[^\x20-\x7E]/', $Value) === 1) {
if (!function_exists('idn_to_ascii')) {
return null;
}
$Ascii = defined('INTL_IDNA_VARIANT_UTS46')
? @idn_to_ascii($Value, IDNA_DEFAULT, INTL_IDNA_VARIANT_UTS46)
: @idn_to_ascii($Value);
if (!is_string($Ascii) || $Ascii === '') {
return null;
}
$Value = strtolower($Ascii);
}

// حذف پیشوند www. وقتی دامنه ریشه معتبر باقی می ماند (تا هم ریشه و هم همه زیردامنه ها مسدود شوند).
if (str_starts_with($Value, 'www.')) {
$Rest = substr($Value, 4);
if (substr_count($Rest, '.') >= 1) {
$Value = $Rest;
}
}

if (strlen($Value) < 4 || strlen($Value) > 253 || str_contains($Value, '..')) {
return null;
}

// آی پی نسخه ۴ و میزبان های محلی نباید به عنوان پسوند دامنه ثبت شوند.
if (filter_var($Value, FILTER_VALIDATE_IP) !== false) {
return null;
}
if ($Value === 'localhost'
|| str_ends_with($Value, '.localhost')
|| str_ends_with($Value, '.local')
|| str_ends_with($Value, '.internal')
|| str_ends_with($Value, '.home.arpa')
|| str_ends_with($Value, '.lan')) {
return null;
}

$Labels = explode('.', $Value);
if (count($Labels) < 2) {
return null;
}
foreach ($Labels as $Label) {
$Len = strlen($Label);
if ($Len < 1 || $Len > 63) {
return null;
}
if (preg_match('/^(?:xn--)?[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?$/', $Label) !== 1) {
return null;
}
}

$Tld = $Labels[count($Labels) - 1];
if (strlen($Tld) < 2 || ctype_digit($Tld)) {
return null;
}

// محافظت در برابر قفل شدن خود برنامه یا ربات (عدم مسدودسازی دامنه درگاه آمبرلا و تلگرام).
foreach (self::protectedSuffixes() as $Protected) {
if ($Value === $Protected || str_ends_with($Value, '.' . $Protected)) {
return null;
}
}

return $Value;
}

/** دامنه های حیاتی زیرساخت برنامه که مسدودسازی آن ها همگام سازی خود فیلتر را از کار می اندازد. */
private static function protectedSuffixes(): array {
$Protected = ['umbrella-vpn.ir'];
if (class_exists('Environment')) {
foreach (['WEBHOOK_URL', 'APP_GATEWAY_URL', 'BOT_DOMAIN'] as $Key) {
$Raw = trim((string)Environment::get($Key, ''));
if ($Raw === '') continue;
$Host = parse_url(str_contains($Raw, '://') ? $Raw : 'https://' . $Raw, PHP_URL_HOST);
if (is_string($Host) && $Host !== '') {
$Clean = strtolower(trim($Host, '.'));
if (str_starts_with($Clean, 'www.')) $Clean = substr($Clean, 4);
if ($Clean !== '' && !in_array($Clean, $Protected, true)) {
$Protected[] = $Clean;
}
}
}
}
return $Protected;
}

/**
 * تجزیه متن ارسالی کاربر در ربات یا برنامه به دامنه های افزودنی، حذفی (با پیشوند `-`) و نامعتبر.
 *
 * @return array{add: list<string>, remove: list<string>, invalid: list<string>}
 */
public static function parseDomainsInput(string $Raw): array {
$Normalized_Text = str_replace(['،', '؛', "\r"], [',', ';', "\n"], $Raw);
$Tokens = preg_split('/[\s,;]+/u', $Normalized_Text) ?: [];
$Add = [];
$Remove = [];
$Invalid = [];

foreach ($Tokens as $Token) {
$Item = trim($Token);
if ($Item === '') continue;

$Is_Remove = false;
if (str_starts_with($Item, '-') && strlen($Item) > 1) {
$Is_Remove = true;
$Item = ltrim(substr($Item, 1));
}

$Domain = self::normalizeDomain($Item);
if ($Domain === null) {
$Cleaned = trim($Token);
if ($Cleaned !== '' && !in_array($Cleaned, $Invalid, true)) {
$Invalid[] = mb_substr($Cleaned, 0, 80);
}
continue;
}

if ($Is_Remove) {
if (!in_array($Domain, $Remove, true)) $Remove[] = $Domain;
} else {
if (!in_array($Domain, $Add, true)) $Add[] = $Domain;
}
}

return ['add' => $Add, 'remove' => $Remove, 'invalid' => $Invalid];
}

/** شناسه کوتاه و پایدار دامنه برای callback_data تلگرام (زیر ۶۴ بایت و مقاوم در برابر تغییر ترتیب). */
public static function domainToken(string $Domain): string {
return substr(hash('sha256', strtolower(trim($Domain))), 0, 12);
}

private static function splitDomains(string $Raw): array {
$Normalized = str_replace(['،', '؛', "\r"], [',', ';', "\n"], $Raw);
$Out = [];
$Seen = [];

foreach (preg_split('/[\s,;]+/u', $Normalized) ?: [] as $Line) {
$Domain = self::normalizeDomain($Line);
if ($Domain === null || isset($Seen[$Domain])) {
continue;
}
$Seen[$Domain] = true;
$Out[] = $Domain;
if (count($Out) >= self::MAX_CUSTOM_DOMAINS) {
break;
}
}

return $Out;
}

private static function boolOf(mixed $Value): bool {
if (is_bool($Value)) return $Value;

return in_array(strtolower(trim((string)$Value)), ['1', 'true', 'yes', 'on'], true);
}

/** The settings for one account, in the shape the app expects. */
public static function load(string $UUID): array {
$UUID = trim($UUID);

if ($UUID === '') return self::defaults();

$Row = Database::getInstance()->fetch(
'SELECT * FROM `App_Filter_Settings` WHERE `User_UUID` = ? LIMIT 1',
[$UUID]
);

if ($Row === null) return self::defaults();

$Categories = [];

foreach (self::CATEGORIES as $Key => $Label) {
if ((int)($Row[self::COLUMNS[$Key]] ?? 0) === 1) {
$Categories[] = $Key;
}
}

return [
'enabled' => (int)($Row['Enabled'] ?? 0) === 1,
'categories' => $Categories,
'custom_domains' => self::splitDomains((string)($Row['Custom_Domains'] ?? '')),
'updated_by' => (string)($Row['Updated_By'] ?? 'app'),
'updated_at' => (string)($Row['Updated_At'] ?? ''),
];
}

/** Writes settings coming from the app (`categories` list) or the bot. */
public static function save(string $UUID, array $Settings, string $Source = 'app'): array {
$UUID = trim($UUID);

if ($UUID === '') return self::defaults();

$Enabled = self::boolOf($Settings['enabled'] ?? false);
$Categories = self::categoryList($Settings['categories'] ?? ($Settings['category'] ?? []));
$Raw_Domains = $Settings['custom_domains'] ?? '';
$Domains = self::splitDomains(is_array($Raw_Domains) ? implode("\n", array_map('strval', $Raw_Domains)) : (string)$Raw_Domains);

$Values = [
'Enabled' => $Enabled ? 1 : 0,
'Custom_Domains' => implode("\n", $Domains),
'Updated_By' => $Source === 'bot' ? 'bot' : 'app',
];
// Retire the legacy dating flag whenever settings are saved. It is deliberately
// not part of the public categories list, but existing rows may still have it set.
$Values['Dating'] = 0;

foreach (self::CATEGORIES as $Key => $Label) {
$Values[self::COLUMNS[$Key]] = in_array($Key, $Categories, true) ? 1 : 0;
}

$Columns = array_keys($Values);
$Placeholders = implode(', ', array_fill(0, count($Columns), '?'));
$Updates = implode(', ', array_map(static fn(string $Column): string => "`{$Column}` = VALUES(`{$Column}`)", $Columns));

Database::getInstance()->execute(
'INSERT INTO `App_Filter_Settings` (`User_UUID`, `' . implode('`, `', $Columns) . "`)
VALUES (?, {$Placeholders})
ON DUPLICATE KEY UPDATE {$Updates}",
array_merge([$UUID], array_values($Values))
);

return self::load($UUID);
}

/** Flips one category, used by the bot's inline keyboard. */
public static function toggle(string $UUID, string $Category, string $Source = 'bot'): array {
if (!isset(self::CATEGORIES[$Category])) {
return self::load($UUID);
}

$Current = self::load($UUID);
$Categories = $Current['categories'];

if (in_array($Category, $Categories, true)) {
$Categories = array_values(array_filter($Categories, static fn(string $Item): bool => $Item !== $Category));
}
else {
$Categories[] = $Category;
}

$Next_Enabled = $Categories !== [] || $Current['custom_domains'] !== [];

return self::save($UUID, [
'enabled' => $Next_Enabled,
'categories' => $Categories,
'custom_domains' => implode("\n", $Current['custom_domains']),
], $Source);
}

/**
 * اعمال هم زمان افزودن و حذف دامنه های سفارشی روی یک حساب کاربری.
 *
 * @param list<string> $Add_List
 * @param list<string> $Remove_List
 * @return array{
 *   settings: array<string, mixed>,
 *   added: list<string>,
 *   removed: list<string>,
 *   duplicates: list<string>,
 *   skipped_limit: list<string>
 * }
 */
public static function applyDomainChanges(
string $UUID,
array $Add_List,
array $Remove_List = [],
string $Source = 'bot'
): array {
$Current = self::load($UUID);
$Domains = $Current['custom_domains'];
$Added = [];
$Removed = [];
$Duplicates = [];
$Skipped_Limit = [];

foreach ($Remove_List as $Item) {
$Clean = self::normalizeDomain((string)$Item);
if ($Clean === null) continue;
$Index = array_search($Clean, $Domains, true);
if ($Index !== false) {
array_splice($Domains, (int)$Index, 1);
$Removed[] = $Clean;
}
}

foreach ($Add_List as $Item) {
$Clean = self::normalizeDomain((string)$Item);
if ($Clean === null) continue;
if (in_array($Clean, $Domains, true)) {
if (!in_array($Clean, $Duplicates, true)) {
$Duplicates[] = $Clean;
}
continue;
}
if (count($Domains) >= self::MAX_CUSTOM_DOMAINS) {
$Skipped_Limit[] = $Clean;
continue;
}
$Domains[] = $Clean;
$Added[] = $Clean;
}

if ($Added !== [] || $Removed !== []) {
$Has_Any = $Current['categories'] !== [] || $Domains !== [];
$Next_Enabled = $Added !== []
? true
: (!empty($Current['enabled']) && $Has_Any);
$Current = self::save($UUID, [
'enabled' => $Next_Enabled,
'categories' => $Current['categories'],
'custom_domains' => implode("\n", $Domains),
], $Source);
}

return [
'settings' => $Current,
'added' => $Added,
'removed' => $Removed,
'duplicates' => $Duplicates,
'skipped_limit' => $Skipped_Limit,
];
}

/**
 * حذف یک دامنه سفارشی با نام دقیق یا شناسه کوتاه `domainToken`.
 *
 * @return array{removed: ?string, settings: array<string, mixed>}
 */
public static function removeDomainByToken(string $UUID, string $Token_Or_Domain, string $Source = 'bot'): array {
$Current = self::load($UUID);
$Domains = $Current['custom_domains'];
$Removed = null;
$Clean_Direct = self::normalizeDomain($Token_Or_Domain);

foreach ($Domains as $Index => $Domain) {
if (($Clean_Direct !== null && $Domain === $Clean_Direct)
|| hash_equals(self::domainToken($Domain), $Token_Or_Domain)) {
$Removed = $Domain;
array_splice($Domains, (int)$Index, 1);
break;
}
}

if ($Removed === null) {
return ['removed' => null, 'settings' => $Current];
}

$Has_Any = $Current['categories'] !== [] || $Domains !== [];
$Saved = self::save($UUID, [
'enabled' => !empty($Current['enabled']) && $Has_Any,
'categories' => $Current['categories'],
'custom_domains' => implode("\n", $Domains),
], $Source);

return ['removed' => $Removed, 'settings' => $Saved];
}

/** حذف کامل همه دامنه های سفارشی یک حساب کاربری. */
public static function clearDomains(string $UUID, string $Source = 'bot'): array {
$Current = self::load($UUID);
if ($Current['custom_domains'] === []) {
return $Current;
}
return self::save($UUID, [
'enabled' => !empty($Current['enabled']) && $Current['categories'] !== [],
'categories' => $Current['categories'],
'custom_domains' => '',
], $Source);
}

/** A compact Persian summary for the bot's screens. */
public static function summary(array $Settings): string {
$Labels = [];

foreach (($Settings['categories'] ?? []) as $Key) {
if (isset(self::BOT_CATEGORIES[$Key])) $Labels[] = self::BOT_CATEGORIES[$Key];
}

$Domains = is_array($Settings['custom_domains'] ?? null) ? array_values($Settings['custom_domains']) : [];
$Domain_Count = count($Domains);
$Has_Rules = $Labels !== [] || $Domain_Count > 0;

if (empty($Settings['enabled']) || !$Has_Rules) {
$Fa_Num = static fn(int $N): string => strtr((string)$N, ['0' => '۰', '1' => '۱', '2' => '۲', '3' => '۳', '4' => '۴', '5' => '۵', '6' => '۶', '7' => '۷', '8' => '۸', '9' => '۹']);
$Text = '⚪️ کنترل محتوا خاموش است.';
if ($Labels !== [] || $Domain_Count > 0) {
$Saved_Parts = [];
if ($Labels !== []) $Saved_Parts[] = $Fa_Num(count($Labels)) . ' دسته';
if ($Domain_Count > 0) $Saved_Parts[] = $Fa_Num($Domain_Count) . ' دامنه سفارشی';
$Text .= "\n💾 آماده فعال سازی: " . implode(' و ', $Saved_Parts);
}
return $Text;
}

$Fa_Num = static fn(int $N): string => strtr((string)$N, ['0' => '۰', '1' => '۱', '2' => '۲', '3' => '۳', '4' => '۴', '5' => '۵', '6' => '۶', '7' => '۷', '8' => '۸', '9' => '۹']);
$Text = '🟢 کنترل محتوا روشن است.';

if ($Labels !== []) {
$Text .= "\n📂 دسته ها: " . implode('، ', $Labels);
}

if ($Domain_Count > 0) {
$Preview = array_slice($Domains, 0, 3);
$Sample = implode('، ', $Preview) . ($Domain_Count > 3 ? ' و ...' : '');
$Text .= "\n🌐 دامنه های سفارشی: " . $Fa_Num($Domain_Count) . " مورد ({$Sample})";
}

return $Text;
}

/** The subset of the panel account the app stores and shows (never private keys). */
public static function accountPayload(array $Account): array {
$Phone = trim((string)($Account['phone'] ?? ''));
$Comment = trim((string)($Account['comment'] ?? ''));

if ($Phone === '' && preg_match('/^(?:\+?98|0)?9\d{9}$/', $Comment) === 1) {
$Phone = $Comment;
}

return [
'id' => (int)($Account['id'] ?? 0),
'uuid' => (string)($Account['uuid'] ?? ''),
'name' => (string)($Account['name'] ?? ''),
'phone' => $Phone,
'telegram_id' => (string)($Account['telegram_id'] ?? ''),
'comment' => $Comment,
'enable' => (bool)($Account['enable'] ?? true),
'is_active' => (bool)($Account['is_active'] ?? false),
'usage_limit_GB' => (float)($Account['usage_limit_GB'] ?? 0),
'current_usage_GB' => (float)($Account['current_usage_GB'] ?? 0),
'package_days' => (int)($Account['package_days'] ?? 0),
'start_date' => $Account['start_date'] ?? null,
'expiry_date' => $Account['expiry_date'] ?? ($Account['end_date'] ?? null),
'last_reset_time' => $Account['last_reset_time'] ?? null,
'last_online' => (string)($Account['last_online'] ?? ''),
'mode' => (string)($Account['mode'] ?? ''),
'lang' => (string)($Account['lang'] ?? 'fa'),
'wg_ipv4' => (string)($Account['wg_ipv4'] ?? ''),
'wg_ipv6' => (string)($Account['wg_ipv6'] ?? ''),
'awg_ipv4' => (string)($Account['awg_ipv4'] ?? ''),
'awg_ipv6' => (string)($Account['awg_ipv6'] ?? ''),
'subscription_url' => (string)($Account['subscription_url'] ?? ($Account['sub_link'] ?? '')),
];
}

}
?>
