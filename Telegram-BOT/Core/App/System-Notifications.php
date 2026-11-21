<?php
declare(strict_types=1);
require_once __DIR__ . '/../Storage/Repository.php';
require_once __DIR__ . '/../Telegram/Telegram.php';
require_once dirname(__DIR__, 2) . '/Config/Environment.php';

/** System events only. Manual messaging keeps its explicitly chosen transports. */
final class SystemNotifications {
/** Telegram IDs that currently own the administrator account. */
private static function administratorIds(): array {
$Ids = [];
$Env_Admin = 0;
if (class_exists('Environment') && method_exists('Environment', 'getAdminUserId')) {
try { $Env_Admin = (int)Environment::getAdminUserId(); } catch (Throwable) {}
}
if ($Env_Admin > 0) $Ids[] = $Env_Admin;
if (method_exists('Repository', 'getSetting')) {
try {
$Configured = (int)Repository::getSetting('Administrator', (string)$Env_Admin);
if ($Configured > 0) $Ids[] = $Configured;
} catch (Throwable) {}
}
return array_values(array_unique($Ids));
}

public static function queue(int $UserId, string $Title, string $Body, string $Event = '', string $Level = 'info'): int {
if ($UserId <= 0 || trim($Body) === '' || in_array($UserId, self::administratorIds(), true)) return 0;
try {
$Db = Database::getInstance();
$User = Repository::getUser($UserId);
$Uuid = trim((string)($User['Client_ID'] ?? ''));
if ($Uuid === '_') $Uuid = '';
$Rows = $Db->fetchAll('SELECT `Device_ID` FROM `App_Devices` WHERE `Is_Trusted` = 1 AND (`Telegram_ID` = ? OR ((`Telegram_ID` IS NULL OR `Telegram_ID` = 0) AND `User_UUID` = ? AND ? != \'\'))', [$UserId, $Uuid, $Uuid]);
// Store full, un-shortened text so Telegram Bot views (including AppLink::notifications)
// always show the complete message; summarization runs exclusively in formatForWindowsApp().
$Body = html_entity_decode(strip_tags(TelegramClient::md($Body)), ENT_QUOTES | ENT_HTML5, 'UTF-8');
$RawTitle = mb_substr(trim(strip_tags($Title)), 0, 190);
if (method_exists('Helper', 'stripZwnj')) $RawTitle = Helper::stripZwnj($RawTitle);
if (method_exists('Helper', 'digitsToPersian')) $RawTitle = Helper::digitsToPersian($RawTitle);
$Title = $RawTitle;
if (method_exists('Helper', 'stripZwnj')) $Body = Helper::stripZwnj($Body);
if (method_exists('Helper', 'digitsToPersian')) $Body = Helper::digitsToPersian($Body);
$Body = mb_substr($Body, 0, 12000);
if (trim($Body) === '') return 0;
if ($Event === '') {
$Day = (new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran')))->format('Y-m-d');
$Event = hash('sha256', $Body) . ':' . $Day;
}
$Targets = [];
foreach ($Rows as $Row) {
$Device = trim((string)($Row['Device_ID'] ?? ''));
if ($Device !== '') $Targets[$Device] = $Device;
}
if ($Targets === []) return 0; // Never NULL/NULL or broadcast.
$Db->transaction(static function (Database $Db) use ($Targets, $Uuid, $Title, $Body, $Level, $Event, $UserId): void {
foreach ($Targets as $Device) {
$Key = hash('sha256', $UserId . ':' . $Event . ':' . $Device);
$Db->execute('INSERT INTO `App_Notifications` (`User_UUID`, `Device_ID`, `Title`, `Body`, `Level`, `Event_Key`) VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE `ID` = `ID`', [$Uuid !== '' ? $Uuid : null, $Device, $Title, $Body, $Level, $Key]);
}
});
return max(1, count($Targets));
} catch (Throwable $Error) {
error_log('[Umbrella-Bot][System-App-Notice] queue failed: ' . $Error->getMessage());
return 0;
}
}

public static function mirrorChat(int $ChatId, string $Text): void {
if ($ChatId <= 0) return;
try {
$Rows = Database::getInstance()->fetchAll('SELECT `Telegram_ID` FROM `Users` WHERE `Chat_ID` = ? OR `Telegram_ID` = ? LIMIT 2', [$ChatId, $ChatId]);
if (count($Rows) !== 1) return;
self::queue((int)$Rows[0]['Telegram_ID'], 'اعلان سیستمی آمبرلا', $Text);
} catch (Throwable $Error) { error_log('[Umbrella-Bot][System-App-Notice] recipient lookup failed: ' . $Error->getMessage()); }
}

/**
 * Formats a stored full notification exclusively for the Windows client API
 * (`/app/notifications`), keeping Telegram Bot messages and DB rows un-summarized.
 *
 * @return array{title: string, body: string, level: string}
 */
public static function formatForWindowsApp(string $Title, string $Body, string $Level = 'info', int $Max = 160): array {
$CleanTitle = preg_replace('/\s+/u', ' ', str_replace("\u{200C}", ' ', trim($Title))) ?? trim($Title);
$NormalizedBody = str_replace(["\u{200C}", "\r\n", "\r", '*', '`'], [' ', "\n", "\n", '', ''], trim($Body));
if (method_exists('Helper', 'digitsToPersian')) {
$CleanTitle = Helper::digitsToPersian($CleanTitle);
$NormalizedBody = Helper::digitsToPersian($NormalizedBody);
}
$FinalLevel = trim($Level) !== '' ? trim($Level) : 'info';

if (str_contains($CleanTitle, 'گزارش شبانه') || str_contains($NormalizedBody, 'گزارش شبانه مصرف')) {
return [
'title' => 'گزارش شبانه',
'body' => self::compactNightlyReport($NormalizedBody, $Max),
'level' => $FinalLevel,
];
}

if ($CleanTitle === 'اعلان سیستمی آمبرلا' || $CleanTitle === '') {
$CleanTitle = self::inferTitle($NormalizedBody);
if ($FinalLevel === 'info') {
$FinalLevel = self::inferLevel($NormalizedBody);
}
} elseif ($CleanTitle === 'یادآور تمدید اشتراک') {
$CleanTitle = 'تمدید اشتراک';
} elseif ($CleanTitle === 'انقضای اشتراک') {
$CleanTitle = 'پایان اشتراک';
} elseif ($CleanTitle === 'فعالسازی پس از عضویت کانال') {
$CleanTitle = 'اشتراک فعال شد';
} elseif ($CleanTitle === 'قطع به دلیل عضویت کانال') {
$CleanTitle = 'توقف اشتراک';
} elseif ($CleanTitle === 'هشدار عضویت کانال') {
$CleanTitle = 'عضویت کانال';
}

if (mb_strlen($CleanTitle) > 60) {
$CleanTitle = rtrim(mb_substr($CleanTitle, 0, 59)) . '…';
}

return [
'title' => $CleanTitle,
'body' => self::compact($NormalizedBody, $Max),
'level' => $FinalLevel,
];
}

/** Extracts a crisp single-line summary from a full Telegram nightly usage report. */
public static function compactNightlyReport(string $Normalized, int $Max = 160): string {
$Total = self::extractField($Normalized, '/سهمیه\s*کل:\s*([^\n]+)/u');
$Used = self::extractField($Normalized, '/(?:مصرف\s*شده|مصرف\s*کل(?:\s*تا\s*امشب)?):\s*([^\n]+)/u');
$Rem = self::extractField($Normalized, '/(?:باقی\s*مانده|باقیمانده)(?:\s*ترافیک)?:\s*([^\n]+)/u');
$Exp = self::extractField($Normalized, '/(?:زمان\s*باقی\s*مانده(?:\s*اشتراک)?|زمان\s*باقیمانده(?:\s*اشتراک)?|اعتبار):\s*([^\n(]+)/u');
$Pct = self::extractField($Normalized, '/([۰-۹0-9]+(?:[٫.][۰-۹0-9]+)?)\s*٪/u');

$Parts = [];
if ($Used !== null && $Total !== null) {
$UsagePart = 'مصرف ' . $Used . ' از ' . $Total;
if ($Pct !== null) {
$UsagePart .= ' (' . $Pct . '٪)';
}
$Parts[] = $UsagePart;
} elseif ($Used !== null) {
$Parts[] = 'مصرف ' . $Used;
}
if ($Rem !== null) {
$Parts[] = 'مانده ' . $Rem;
}
if ($Exp !== null) {
$Parts[] = 'اعتبار ' . $Exp;
}

if ($Parts !== []) {
$Summary = implode(' · ', $Parts);
return mb_strlen($Summary) > $Max ? rtrim(mb_substr($Summary, 0, $Max - 1)) . '…' : $Summary;
}

return self::compact($Normalized, $Max);
}

/** Condenses multi-line notifications into crisp, informative Windows app alerts. */
public static function compact(string $Text, int $Max = 160): string {
$Raw = str_replace(["\u{200C}", "\r\n", "\r", '*', '`'], [' ', "\n", "\n", '', ''], trim($Text));
if ($Raw === '') return '';
$StripUrl = static fn(string $Value): string => trim(preg_replace('/\s{2,}/u', ' ', preg_replace('/\s*[—–\-]?\s*https?:\/\/\S+/u', '', $Value) ?? $Value) ?? $Value);

if (!str_contains($Raw, "\n") && mb_strlen($Raw) <= $Max) {
return $StripUrl($Raw);
}

$Lines = [];
foreach (explode("\n", $Raw) as $Line) {
$Clean = preg_replace('/^[├└│─━═➖•·\s]+/u', '', trim($Line)) ?? trim($Line);
$Clean = preg_replace('/[█▓▒░]{3,}/u', '', $Clean) ?? $Clean;
$Clean = $StripUrl($Clean);
if ($Clean === '') continue;
if (preg_match('/^[➖─━═_]{3,}$/u', $Clean)) continue;
if (preg_match('/^(?:👋|🌹|🌺)?\s*(?:سلام|درود)\b.*(?:گرامی|عزیز)/u', $Clean)) continue;
if (preg_match('/^(?:👤|🆔|📌\s*بخش|📅\s*تاریخ|🕰\s*ساعت|🌐\s*سرور آمبرلا|سرور آمبرلا$|☂|آرمین سافت|💡\s*نکته:|👇|👌برای|🔄لطفا چند لحظه|📞در صورت ادامه|⚠️?\s*در صورت ادامه)/u', $Clean)) continue;
$Lines[] = $Clean;
if (count($Lines) === 3) break;
}

$Joined = $Lines !== [] ? implode(' · ', $Lines) : $StripUrl(preg_replace('/\s+/u', ' ', $Raw) ?? $Raw);
if (mb_strlen($Joined) > $Max) {
$Joined = rtrim(mb_substr($Joined, 0, $Max - 1)) . '…';
}
return $Joined;
}

private static function extractField(string $Text, string $Pattern): ?string {
if (!preg_match($Pattern, $Text, $Match)) return null;
$Value = trim($Match[1] ?? '');
return $Value !== '' ? $Value : null;
}

private static function inferTitle(string $Plain): string {
if (str_contains($Plain, 'تمدید گردید') || str_contains($Plain, 'تمدید شد')) return 'اشتراک تمدید شد';
if (str_contains($Plain, 'فعال گردید') || str_contains($Plain, 'فعال شد')) return 'اشتراک فعال شد';
if (str_contains($Plain, 'فعال نشد') || str_contains($Plain, 'تمدید نشد')) return 'خطا در فعال سازی';
if (str_contains($Plain, 'کیف پول') && str_contains($Plain, 'شارژ')) return 'شارژ کیف پول';
if (str_contains($Plain, 'کیف پول') && str_contains($Plain, 'کسر')) return 'برداشت از کیف پول';
if (str_contains($Plain, 'تیکت') || str_contains($Plain, 'پشتیبانی')) return 'پشتیبانی';
if (str_contains($Plain, 'مسدود')) return 'وضعیت حساب';
return 'اعلان سیستم';
}

private static function inferLevel(string $Plain): string {
if (str_contains($Plain, '❌') || str_contains($Plain, '⚠️') || str_contains($Plain, '⛔') || str_contains($Plain, 'فعال نشد')) return 'warning';
if (str_contains($Plain, '✅') || str_contains($Plain, 'تمدید گردید') || str_contains($Plain, 'فعال گردید') || str_contains($Plain, 'شارژ شد')) return 'success';
return 'info';
}
}
