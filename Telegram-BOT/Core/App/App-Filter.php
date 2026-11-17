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
/** دسته‌های قابل تنظیم در ربات؛ تنظیمات دیگر برنامه بدون حذف داده حفظ می‌شوند. */
public const BOT_CATEGORIES = [
'adult' => 'محتوای بزرگسال',
'gambling' => 'شرط‌بندی',
'ads' => 'تبلیغات',
'dating' => 'دوست‌یابی',
];

public const CATEGORIES = [
'adult' => 'محتوای بزرگسال',
'social' => 'شبکه‌های اجتماعی',
'gambling' => 'شرط‌بندی',
'ads' => 'تبلیغات',
'streaming' => 'ویدیو و پخش',
'dating' => 'دوستیابی',
'violence' => 'محتوای خشن',
'messaging' => 'پیام‌رسان‌ها',
];

/** Column per category, in the order of self::CATEGORIES. */
private const COLUMNS = [
'adult' => 'Adult',
'social' => 'Social',
'gambling' => 'Gambling',
'ads' => 'Ads',
'streaming' => 'Streaming',
'dating' => 'Dating',
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

private static function splitDomains(string $Raw): array {
$Out = [];

foreach (preg_split('/[\s,;]+/', $Raw) ?: [] as $Line) {
$Value = strtolower(trim($Line));
$Value = preg_replace('#^https?://#', '', $Value) ?? $Value;
$Value = preg_replace('#^www\.#', '', $Value) ?? $Value;
$Slash = strpos($Value, '/');

if ($Slash !== false) {
$Value = substr($Value, 0, $Slash);
}

if ($Value !== '' && preg_match('/^[a-z0-9.\-_]+$/', $Value) === 1) {
$Out[] = $Value;
}
}

return array_values(array_unique($Out));
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

return self::save($UUID, [
'enabled' => true,
'categories' => $Categories,
'custom_domains' => implode("\n", $Current['custom_domains']),
], $Source);
}

/** A compact Persian summary for the bot's screens. */
public static function summary(array $Settings): string {
if (empty($Settings['enabled'])) {
return '⚪️ کنترل محتوا خاموش است.';
}

$Labels = [];

foreach ($Settings['categories'] as $Key) {
if (isset(self::BOT_CATEGORIES[$Key])) $Labels[] = self::BOT_CATEGORIES[$Key];
}

$Text = '🟢 کنترل محتوا روشن است.';

if ($Labels !== []) {
$Text .= "\n📂 دسته‌ها: " . implode('، ', $Labels);
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
