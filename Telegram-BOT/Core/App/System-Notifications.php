<?php
declare(strict_types=1);
require_once __DIR__ . '/../Storage/Repository.php';
require_once __DIR__ . '/../Telegram/Telegram.php';

/** System events only. Manual messaging keeps its explicitly chosen transports. */
final class SystemNotifications {
public static function queue(int $UserId, string $Title, string $Body, string $Event = '', string $Level = 'info'): int {
if ($UserId <= 0 || trim($Body) === '') return 0;
try {
$Db = Database::getInstance();
$User = Repository::getUser($UserId);
$Uuid = trim((string)($User['Client_ID'] ?? ''));
if ($Uuid === '_') $Uuid = '';
$Rows = $Db->fetchAll('SELECT `Device_ID` FROM `App_Devices` WHERE `Is_Trusted` = 1 AND (`Telegram_ID` = ? OR ((`Telegram_ID` IS NULL OR `Telegram_ID` = 0) AND `User_UUID` = ? AND ? != \'\'))', [$UserId, $Uuid, $Uuid]);
$Body = html_entity_decode(strip_tags(TelegramClient::md($Body)), ENT_QUOTES | ENT_HTML5, 'UTF-8');
$Body = self::compact($Body);
$Title = mb_substr(trim(strip_tags($Title)), 0, 90);
if ($Body === '') return 0;
if ($Event === '') $Event = hash('sha256', $Body) . ':' . intdiv(time(), 300);
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
$Plain = html_entity_decode(strip_tags(TelegramClient::md($Text)), ENT_QUOTES | ENT_HTML5, 'UTF-8');
self::queue((int)$Rows[0]['Telegram_ID'], self::inferTitle($Plain), $Plain, '', self::inferLevel($Plain));
} catch (Throwable $Error) { error_log('[Umbrella-Bot][System-App-Notice] recipient lookup failed: ' . $Error->getMessage()); }
}

/** Condenses multi-line Telegram messages into crisp, informative app alerts. */
public static function compact(string $Text, int $Max = 180): string {
$Raw = str_replace(["\r\n", "\r", '*'], ["\n", "\n", ''], trim($Text));
if ($Raw === '') return '';
if (!str_contains($Raw, "\n") && mb_strlen($Raw) <= $Max) {
return preg_replace('/\s{2,}/u', ' ', $Raw) ?? $Raw;
}

$Lines = [];
foreach (explode("\n", $Raw) as $Line) {
$Clean = preg_replace('/^[├└│─━═➖•·\s]+/u', '', trim($Line)) ?? trim($Line);
$Clean = preg_replace('/\s{2,}/u', ' ', trim($Clean)) ?? trim($Clean);
if ($Clean === '') continue;
if (preg_match('/^[➖─━═_]{3,}$/u', $Clean)) continue;
if (preg_match('/^(?:👋|🌹|🌺)?\s*(?:سلام|درود)\b.*(?:گرامی|عزیز)/u', $Clean)) continue;
if (preg_match('/^(?:👤|🆔|📌\s*بخش|📅\s*تاریخ|🕰\s*ساعت|🌐\s*سرور آمبرلا|سرور آمبرلا$|☂️|آرمین سافت|💡\s*نکته:|👇|👌برای|🔄لطفا چند لحظه|📞در صورت ادامه|⚠️در صورت ادامه)/u', $Clean)) continue;
$Lines[] = $Clean;
}

$Joined = $Lines !== [] ? implode(' · ', array_slice($Lines, 0, 3)) : (preg_replace('/\s+/u', ' ', $Raw) ?? $Raw);
if (mb_strlen($Joined) > $Max) {
$Joined = rtrim(mb_substr($Joined, 0, $Max - 1)) . '…';
}
return $Joined;
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
