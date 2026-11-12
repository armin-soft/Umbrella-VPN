<?php
declare(strict_types=1);

require_once __DIR__ . '/../../Config/Environment.php';
require_once __DIR__ . '/Http.php';

final class Helper {
private const PERSIAN_DIGITS = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
private const ARABIC_DIGITS = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
private const SEPARATOR = '➖➖➖➖➖➖➖➖➖';
private const OPERATORS = [
'0910' => 'همراه اول', '0911' => 'همراه اول', '0912' => 'همراه اول', '0913' => 'همراه اول',
'0914' => 'همراه اول', '0915' => 'همراه اول', '0916' => 'همراه اول', '0917' => 'همراه اول',
'0918' => 'همراه اول', '0919' => 'همراه اول', '0990' => 'همراه اول', '0991' => 'همراه اول',
'0992' => 'همراه اول', '0993' => 'همراه اول', '0994' => 'همراه اول',
'0900' => 'ایرانسل', '0901' => 'ایرانسل', '0902' => 'ایرانسل', '0903' => 'ایرانسل',
'0904' => 'ایرانسل', '0905' => 'ایرانسل', '0930' => 'ایرانسل', '0931' => 'ایرانسل',
'0932' => 'ایرانسل', '0933' => 'ایرانسل', '0934' => 'ایرانسل', '0935' => 'ایرانسل',
'0936' => 'ایرانسل', '0937' => 'ایرانسل', '0938' => 'ایرانسل', '0939' => 'ایرانسل',
'0941' => 'ایرانسل',
'0920' => 'رایتل', '0921' => 'رایتل', '0922' => 'رایتل', '0923' => 'رایتل',
'0924' => 'رایتل', '0925' => 'رایتل', '0926' => 'رایتل', '0927' => 'رایتل',
'0928' => 'رایتل', '0929' => 'رایتل',
];

private function __construct() {
}

/**
 * Turns every Latin digit in a message into a Persian one, except inside the
 * parts that are meant to be copied: code spans, code/pre blocks, links,
 * e-mail addresses, @usernames and bare URLs. Those keep Latin digits or the
 * copied value would be wrong (a UUID, a subscription link, a payment ref).
 *
 * Message texts pass through this once in TelegramClient, so a screen that
 * forgets Helper::toPersian() still renders Persian numbers.
 */
public static function digitsToPersian(string $Text): string {
if ($Text === '' || preg_match('/[0-9]/', $Text) !== 1) {
return $Text;
}

$Hold = [];
$Keep = static function (string $Value) use (&$Hold): string {
$Key = "\x01" . str_repeat("\x02", count($Hold) + 1) . "\x01";
$Hold[$Key] = $Value;

return $Key;
};
// Inline code first (`...`), then <code>/<pre> blocks: whatever is inside is
// literal data, not prose.
$Text = (string)preg_replace_callback('/`[^`\n]*`/u', static fn (array $M): string => $Keep($M[0]), $Text);
$Text = (string)preg_replace_callback('#<(code|pre)(?:\s[^>]*)?>.*?</\1>#isu', static fn (array $M): string => $Keep($M[0]), $Text);
// Link targets: markdown ](...), HTML href="..." and any bare URL.
$Text = (string)preg_replace_callback('/\]\([^)\n]*\)/u', static fn (array $M): string => $Keep($M[0]), $Text);
$Text = (string)preg_replace_callback('/href="[^"]*"/iu', static fn (array $M): string => $Keep($M[0]), $Text);
$Text = (string)preg_replace_callback('#(?:https?|tg)://[^\s<>"`]+#iu', static fn (array $M): string => $Keep($M[0]), $Text);
$Text = (string)preg_replace_callback('/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/u', static fn (array $M): string => $Keep($M[0]), $Text);
$Text = (string)preg_replace_callback('/(?<![\w\x01])@[A-Za-z][A-Za-z0-9_]{2,}/u', static fn (array $M): string => $Keep($M[0]), $Text);
$Text = strtr($Text, array_combine(['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'], self::PERSIAN_DIGITS));

return $Hold === [] ? $Text : strtr($Text, $Hold);
}

public static function toPersian(int|float|string $Number): string {
return strtr((string)$Number, array_combine(
['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'],
self::PERSIAN_DIGITS
));
}

public static function toEnglish(string $Text): string {
return strtr($Text, array_merge(
array_combine(self::PERSIAN_DIGITS, ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']),
array_combine(self::ARABIC_DIGITS, ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'])
));
}

private static function trimZeros(string $Number): string {
if (!str_contains($Number, '.')) return $Number;
$Number = rtrim(rtrim($Number, '0'), '.');

return ($Number === '' || $Number === '-') ? '0' : $Number;
}

public static function smsPlan(string $Plan): string {
$Plan = trim((string)(preg_replace('/^اشتراک\s*/u', '', trim($Plan)) ?? trim($Plan)));
return $Plan !== '' ? $Plan : 'فعال';
}

public static function normalizeText(string $Text): string {
$Text = trim($Text);
$Text = preg_replace('/\s+/u', ' ', $Text) ?? $Text;
$Text = str_replace(['‍', ' ', 'ـ', '‬', '‎'], '', $Text);
$Text = str_replace(['ي', 'ك', 'ة', 'أ', 'إ', 'آ', 'ؤ', 'ئ'], ['ی', 'ک', 'ه', 'ا', 'ا', 'ا', 'و', 'ی'], $Text);
$Text = preg_replace('/[۰-۹0-9]/u', '', $Text);
return mb_strtolower($Text, 'UTF-8');
}

public const DATE_TIME_ERROR_TEXT = '⚠️خطا: دریافت اطلاعات تاریخ و زمان رخ داد';
private const DATE_TIME_FALLBACK = "📆تاریخ شمسی:*نامعلوم*\n🕌تاریخ قمری:*نامعلوم*\n🌍تاریخ میلادی:*نامعلوم*\n\n🌎فصل:*❓نامعلوم*\n🕰زمان:*--:--:--*";
private const DATE_TIME_CACHE_TTL = 120;
private static array $Date_Time_Cache = [];
private static bool $Date_Time_Tried = false;

private static function getDateTimeData(int $Next = 0): array {
$Cache_Key = (string)$Next;
$Cached = self::$Date_Time_Cache[$Cache_Key] ?? null;

if (is_array($Cached) && (time() - (int)$Cached['at']) < self::DATE_TIME_CACHE_TTL) {
return $Cached['data'];
}

$Base = rtrim(Environment::getDateTimeApiUrl(), '/');
$License = trim(Environment::getDateTimeApiLicense());
$Params = [];

if ($License !== '') $Params[] = 'License=' . rawurlencode($License);
if ($Next > 0) $Params[] = 'Next=' . $Next;
$Url = $Base . '/' . ($Params !== [] ? '?' . implode('&', $Params) : '');
$Last_Error = '';

// One network attempt per request at most: a slow or down date service must not
// hold up every message the bot sends.
if (self::$Date_Time_Tried) {
throw new RuntimeException('وب سرویس تاریخ و زمان در این درخواست قبلاً امتحان شده است.');
}

self::$Date_Time_Tried = true;

for ($Attempt = 1; $Attempt <= 2; $Attempt++) {
if ($Attempt > 1) usleep(250000);

try {
$Response = HttpClient::get($Url, ['Accept' => 'application/json', 'User-Agent' => 'ArminSoft-Helper/1.0'], 8);
}

catch (Throwable $Error) {
$Last_Error = 'ارتباط با وب سرویس تاریخ و زمان برقرار نشد: ' . $Error->getMessage();
continue;
}

$Body = trim((string)($Response['Body'] ?? ''));

if ($Body === '') {
$Last_Error = 'پاسخ وب سرویس تاریخ و زمان خالی بود (HTTP ' . (int)($Response['StatusCode'] ?? 0) . ')';
continue;
}

$Json = $Response['Json'] ?? null;

if (!is_array($Json)) $Json = json_decode($Body, true);

if (!is_array($Json)) {
$Last_Error = 'پاسخ وب سرویس تاریخ و زمان JSON معتبر نبود (HTTP ' . (int)($Response['StatusCode'] ?? 0) . ')';
continue;
}

$Data = $Json['Data'] ?? null;

if (!is_array($Data) || $Data === []) {
$Last_Error = 'وب سرویس تاریخ و زمان داده ای برنگرداند (کد ' . (int)($Json['Status']['Code'] ?? ($Response['StatusCode'] ?? 0)) . ')';
continue;
}

self::$Date_Time_Cache[$Cache_Key] = ['at' => time(), 'data' => $Data];

if ($Next === 0) static::rememberDateTimeSnapshot($Data);

return $Data;
}

error_log('[Umbrella-Bot][Date-Time] ' . $Last_Error . ' | URL=' . $Url);
throw new RuntimeException($Last_Error !== '' ? $Last_Error : 'دریافت تاریخ و زمان از وب سرویس ناموفق بود.');
}

/** Keeps the last good answer so the header survives a short outage. */
private static function rememberDateTimeSnapshot(array $Data): void {
if (!class_exists('Repository')) return;

try {
Repository::setSetting('Date_Time_Snapshot', (string)json_encode(['at' => time(), 'data' => $Data], JSON_UNESCAPED_UNICODE));
}

catch (Throwable) {
}
}

/** Last good answer, only when it is recent enough to still be today's. */
private static function dateTimeSnapshot(int $Max_Age = 1800): ?array {
if (!class_exists('Repository')) return null;

try {
$Raw = (string)(Repository::getSetting('Date_Time_Snapshot', '') ?? '');
}

catch (Throwable) {
return null;
}

if ($Raw === '') return null;
$Snapshot = json_decode($Raw, true);

if (!is_array($Snapshot) || !is_array($Snapshot['data'] ?? null)) return null;
if ((time() - (int)($Snapshot['at'] ?? 0)) > $Max_Age) return null;

return $Snapshot['data'];
}

public static function currentDateTimeLabel(?int $Time_Stamp = null): string {
$Stamp = ($Time_Stamp !== null && $Time_Stamp > 0) ? $Time_Stamp : time();

try {
$Date = (new DateTimeImmutable('@' . $Stamp))->setTimezone(new DateTimeZone('Asia/Tehran'));
}

catch (Throwable) {
return static::DATE_TIME_ERROR_TEXT;
}

$Hijri = '';
$Season = '';
$Season_Emoji = '';
$Part = '';
$Part_Emoji = '';
$Service_Data = null;
$Offset = static::daysFromToday($Stamp);

if ($Offset === 0) {
// A snapshot younger than ten minutes is still today's date, and it keeps the
// header instant even when the date service is slow or unreachable.
$Service_Data = static::dateTimeSnapshot(600);
}

if (!is_array($Service_Data)) {
try {
$Service_Data = static::getDateTimeData($Offset > 0 ? $Offset : 0);
}

catch (Throwable) {
$Service_Data = static::dateTimeSnapshot();
}
}

if (is_array($Service_Data)) {
$Hijri = trim((string)($Service_Data['Hijri_Date'] ?? ''));
$Season = trim((string)($Service_Data['Season'] ?? ''));
$Season_Emoji = trim((string)($Service_Data['Season_Emoji'] ?? ''));
$Part = trim((string)($Service_Data['Time_Based'] ?? ''));
$Part_Emoji = trim((string)($Service_Data['Time_Based_Emoji'] ?? ''));
}

if ($Season === '') [$Season_Emoji, $Season] = static::seasonLabel((int)$Date->format('n'));
if ($Part === '') [$Part_Emoji, $Part] = static::dayPartLabel((int)$Date->format('G'));

$Text = "📆تاریخ شمسی:*" . static::gregorianToJalali($Date->format('Y-m-d')) . "*\n";

if ($Hijri !== '') {
$Text .= "🕌تاریخ قمری:*{$Hijri}*\n";
}

$Text .= "🌍تاریخ میلادی:*" . static::toPersian($Date->format('Y-m-d')) . "*\n\n";
$Text .= "🌎فصل:*{$Season_Emoji}{$Season}*\n";
$Text .= "🕰زمان:*" . static::toPersian($Date->format('H:i:s')) . " {$Part_Emoji}{$Part}*";
return $Text;
}

/** Shamsi date of a unix timestamp, computed locally in Tehran time. */
public static function jalaliFromTimestamp(int $Time_Stamp, bool $Include_Time = false): string {
if ($Time_Stamp <= 0) return 'نامشخص';

try {
$Date = (new DateTimeImmutable('@' . $Time_Stamp))->setTimezone(new DateTimeZone('Asia/Tehran'));
}

catch (Throwable) {
return 'نامشخص';
}

$Label = static::gregorianToJalali($Date->format('Y-m-d'));

if ($Include_Time) {
$Label .= ' ' . static::toPersian($Date->format('H:i'));
}

return $Label;
}

/** Whole calendar days between a timestamp and today (Tehran); negative when past. */
public static function daysFromToday(int $Time_Stamp): int {
if ($Time_Stamp <= 0) return 0;
$Tehran = new DateTimeZone('Asia/Tehran');

try {
$Today = new DateTimeImmutable('today', $Tehran);
$Target = (new DateTimeImmutable('@' . $Time_Stamp))->setTimezone($Tehran)->setTime(0, 0);
}

catch (Throwable) {
return 0;
}

return (int)round(($Target->getTimestamp() - $Today->getTimestamp()) / 86400);
}

/** Time-of-day label used by the expiry block (local, never fails). */
private static function dayPartLabel(int $Hour): array {
if ($Hour >= 5 && $Hour < 12) return ['🌅', 'صبح'];
if ($Hour >= 12 && $Hour < 16) return ['☀️', 'ظهر'];
if ($Hour >= 16 && $Hour < 20) return ['🌇', 'عصر'];
if ($Hour >= 20) return ['🌙', 'شب'];
return ['🌌', 'بامداد'];
}

/** Season of a Gregorian month, used when the date web service is unreachable. */
private static function seasonLabel(int $Month): array {
if ($Month >= 3 && $Month <= 5) return ['🌸', 'بهار'];
if ($Month >= 6 && $Month <= 8) return ['☀️', 'تابستان'];
if ($Month >= 9 && $Month <= 11) return ['🍂', 'پاییز'];
return ['❄️', 'زمستان'];
}


public static function formatPersianDate(int $Time_Stamp, bool $Include_Time = false): string {
if ($Time_Stamp > 0) {
return static::jalaliFromTimestamp($Time_Stamp, $Include_Time);
}

try {
$Data = static::getDateTimeData();
}

catch (Throwable) {
return $Include_Time ? 'نامعلوم --:--' : 'نامعلوم';
}

$Result = (string)($Data['Shamsi_Date'] ?? '');

if ($Include_Time) {
$Result .= ' ' . (string)($Data['Time'] ?? '');
}

return $Result;
}

public static function formatExpiration(int $Time_Stamp): string {
if ($Time_Stamp <= 0) return 'نامشخص';

try {
$Date = (new DateTimeImmutable('@' . $Time_Stamp))->setTimezone(new DateTimeZone('Asia/Tehran'));
}

catch (Throwable) {
return 'نامشخص';
}

$Shamsi = static::gregorianToJalali($Date->format('Y-m-d'));
$Gregorian = static::toPersian($Date->format('Y-m-d'));
$Clock = static::toPersian($Date->format('H:i'));
[$Part_Emoji, $Part] = static::dayPartLabel((int)$Date->format('G'));
[$Season_Emoji, $Season] = static::seasonLabel((int)$Date->format('n'));
$Hijri = '';

try {
$Data = static::getDateTimeData(static::daysFromToday($Time_Stamp));

if (($Data['Hijri_Date'] ?? '') !== '') $Hijri = (string)$Data['Hijri_Date'];
if (($Data['Season'] ?? '') !== '') $Season = (string)$Data['Season'];
if (($Data['Season_Emoji'] ?? '') !== '') $Season_Emoji = (string)$Data['Season_Emoji'];
if (($Data['Time_Based'] ?? '') !== '') $Part = (string)$Data['Time_Based'];
if (($Data['Time_Based_Emoji'] ?? '') !== '') $Part_Emoji = (string)$Data['Time_Based_Emoji'];
}

catch (Throwable) {
}

$Text = "📆تاریخ شمسی:*{$Shamsi}*\n";
if ($Hijri !== '') $Text .= "🕌تاریخ قمری:*{$Hijri}*\n";
$Text .= "🌍تاریخ میلادی:*{$Gregorian}*\n\n";
$Text .= "🌎فصل:*{$Season_Emoji}{$Season}*\n";
$Text .= "🕰زمان:*{$Clock} {$Part_Emoji}{$Part}*";
return $Text;
}

public static function formatExpirationShort(int $Time_Stamp): string {
if ($Time_Stamp <= 0) return 'نامشخص';

try {
$Date = (new DateTimeImmutable('@' . $Time_Stamp))->setTimezone(new DateTimeZone('Asia/Tehran'));
}

catch (Throwable) {
return 'نامشخص';
}

return static::gregorianToJalali($Date->format('Y-m-d'));
}



public static function gregorianToJalali(string $GregorianDate): string {
[$gy, $gm, $gd] = array_map('intval', explode('-', $GregorianDate));
$Gy_Original = $gy;

if ($gy <= 1600) {
$jy = 0;
$gy -= 621;
}

else {
$jy = 979;
$gy -= 1600;
}

$gy2 = ($gm > 2) ? ($gy + 1) : $gy;
$days = (365 * $gy) + (int)(($gy2 + 3) / 4) - (int)(($gy2 + 99) / 100) + (int)(($gy2 + 399) / 400) - 80 + $gd + [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334][$gm - 1];
$jy += 33 * (int)($days / 12053);
$days %= 12053;
$jy += 4 * (int)($days / 1461);
$days %= 1461;
$jy += (int)(($days - 1) / 365);

if ($days > 365) $days = ($days - 1) % 365;
// شش ماه نخست ۳۱ روزه و شش ماه دوم ۳۰ روزه است؛ ضلع دوم از ماه هفتم شروع می شود.
if ($days < 186) {
$jm = 1 + (int)($days / 31);
$jd = 1 + ($days % 31);
}

else {
$jm = 7 + (int)(($days - 186) / 30);
$jd = 1 + (($days - 186) % 30);
}
$jalali_months = ['فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور', 'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'];
$jalali_days = ['دوشنبه', 'سه شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', 'یکشنبه'];
$day_of_week = (int)(new DateTimeImmutable(sprintf('%04d-%02d-%02d', $Gy_Original, $gm, $gd), new DateTimeZone('UTC')))->format('N');
$day_name = $jalali_days[($day_of_week + 6) % 7];
$month_name = $jalali_months[$jm - 1];
$jd_persian = static::toPersian((string)$jd);
$jy_persian = static::toPersian((string)$jy);
return $day_name . ' ' . $jd_persian . ' ' . $month_name . ' ' . $jy_persian;
}

public static function formatCurrency(float $Number): string {
$Formatted = number_format((int)round($Number), 0, '.', "\u{066C}");
return static::toPersian($Formatted) . ' تومان';
}

public static function formatTime(string $Time): string {
$Time = trim($Time);

if ($Time === '') return '';
$Parts = explode(':', $Time);
$Out = [];

foreach ($Parts as $Index => $P) {
$P = trim($P);
if ($P === '') continue;

if ($Index === 0) {
$Out[] = static::toPersian(ltrim($P, '0') !== '' ? ltrim($P, '0') : '0');
continue;
}

$Digits = static::toPersian($P);

if (strlen($P) < 2) $Digits = static::toPersian('0') . $Digits;
$Out[] = $Digits;
}

return implode(':', $Out);
}

public static function translateStatus(string $Status): string {
$Lower = strtolower(trim($Status));
return match (true) {
str_contains($Lower, 'active') && !str_contains($Lower, 'inactive') => '✅فعال',
str_contains($Lower, 'inactive') || str_contains($Lower, 'deactive') || str_contains($Lower, 'disabled') => '🚫غیرفعال',
str_contains($Lower, 'enable') => '✅فعال',
str_contains($Lower, 'disable') => '🚫غیرفعال',
str_contains($Lower, 'expired') => '⏰منقضی',
default => $Status,
};
}

public static function formatGB(float $Value, bool $Persian = true): string {
$Abs = abs($Value);

if ($Abs <= 0.0) {
$Number = '0';
$Unit = 'گیگابایت';
}

elseif ($Abs < 0.1) {
$Mb = $Abs * 1024;

if ($Mb < 0.5) {
return 'کمتر از ' . static::toPersian('1') . ' مگابایت';
}

$Number = static::trimZeros(number_format($Mb, 0, '.', ''));
$Unit = 'مگابایت';
}

elseif ($Abs >= 1000.0) {
$Number = static::trimZeros(number_format($Value / 1000, 2, '.', ''));
$Unit = 'ترابایت';
}

else {
$Number = static::trimZeros(number_format($Value, 2, '.', ''));
$Unit = 'گیگابایت';
}

$Text = $Number . ' ' . $Unit;
return $Persian ? static::toPersian($Text) : $Text;
}

public static function formatPercent(int|float $Value, int $Precision = 1): string {
$Text = number_format((float)$Value, $Precision, '.', '');
$Text = rtrim(rtrim($Text, '0'), '.');

if ($Text === '' || $Text === '-') $Text = '0';
return static::toPersian($Text);
}

public static function humanDuration(int $Seconds, int $Max_Parts = 7): string {
if ($Seconds <= 0) return 'هم اکنون';
if ($Seconds < 0) return 'زمان نامعتبر';

$Seconds = (int)abs($Seconds);
$Total_Days = (int)floor($Seconds / 86400);
$Years = intdiv($Total_Days, 365);
$Days_Rem = $Total_Days % 365;
$Months = intdiv($Days_Rem, 30);
$Days_After_Months = $Days_Rem % 30;
$Weeks = intdiv($Days_After_Months, 7);
$Days = $Days_After_Months % 7;
$Remainder = $Seconds % 86400;
$Hours = intdiv($Remainder, 3600);
$Minutes = intdiv($Remainder % 3600, 60);
$Remaining_Seconds = $Remainder % 60;
$Parts = [];
$Units = [
['سال', $Years],
['ماه', $Months],
['هفته', $Weeks],
['روز', $Days],
['ساعت', $Hours],
['دقیقه', $Minutes],
['ثانیه', $Remaining_Seconds],
];

foreach ($Units as [$Label, $Count]) {
if ($Count <= 0) continue;
$Parts[] = static::toPersian((string)$Count) . ' ' . $Label;
if (count($Parts) >= max(1, $Max_Parts)) break;
}

return $Parts === [] ? 'کمتر از یک ثانیه' : implode(' و ', $Parts);
}

public static function idleEquivalent(int $Seconds): string {
if ($Seconds <= 0) return 'کمتر از یک روز';
$Total_Days = (int)floor($Seconds / 86400);

if ($Total_Days < 1) {
$Hours = (int)floor($Seconds / 3600);
$Minutes = (int)floor(($Seconds % 3600) / 60);
$Parts = [];

if ($Hours > 0) $Parts[] = static::toPersian((string)$Hours) . ' ساعت';
if ($Minutes > 0 && $Hours > 0) $Parts[] = static::toPersian((string)$Minutes) . ' دقیقه';
return $Parts === [] ? 'کمتر از یک ساعت' : implode(' و ', $Parts);
}

$Years = intdiv($Total_Days, 365);
$Remainder = $Total_Days % 365;
$Months = intdiv($Remainder, 30);
$Month_Remainder = $Remainder % 30;
$Weeks = intdiv($Month_Remainder, 7);
$Days = $Month_Remainder % 7;
$Parts = [];

if ($Years > 0) $Parts[] = static::toPersian((string)$Years) . ' سال';
if ($Months > 0) $Parts[] = static::toPersian((string)$Months) . ' ماه';
if ($Weeks > 0) $Parts[] = static::toPersian((string)$Weeks) . ' هفته';
if ($Days > 0) $Parts[] = static::toPersian((string)$Days) . ' روز';
return $Parts === [] ? 'کمتر از یک روز' : implode(' و ', $Parts);
}

public static function remainingDuration(int $Expiration_Time_Stamp, int $Max_Parts = 7): string {
if ($Expiration_Time_Stamp <= 0) return 'نامشخص';
$Diff = $Expiration_Time_Stamp - time();

if ($Diff <= 0) return 'منقضی شده';
return static::humanDuration($Diff, $Max_Parts);
}

public static function durationLabel(int $Days): string {
$Days = (int)$Days;

if ($Days <= 0) return 'نامشخص';
$Years = intdiv($Days, 365);
$Remainder = $Days % 365;
$Months = intdiv($Remainder, 30);
$Days_Left = $Remainder % 30;
$Parts = [];

if ($Years > 0) $Parts[] = static::toPersian((string)$Years) . ' سال';
if ($Months > 0) $Parts[] = static::toPersian((string)$Months) . ' ماه';
if ($Days_Left > 0) $Parts[] = static::toPersian((string)$Days_Left) . ' روز';
return $Parts === [] ? 'نامشخص' : implode(' و ', $Parts);
}

public static function usageBar(float $Percent, int $Length = 12): string {
$Length = max(4, $Length);
$Filled = (int)round(max(0.0, min(100.0, $Percent)) / 100.0 * $Length);
return str_repeat('▰', $Filled) . str_repeat('▱', $Length - $Filled);
}

public static function percentShare(float $Part, float $Total, int $Precision = 1): string {
if ($Total <= 0) return static::toPersian('0') . '٪';
return static::formatPercent(($Part / $Total) * 100.0, $Precision) . '٪';
}

public static function durationLabelFromLabel(?string $Label): string {
$Label = trim((string)$Label);

if ($Label === '') return 'نامشخص';
$Days = null;

if (preg_match('/([0-9۰-۹]+)\s*روز/u', $Label, $M) === 1) {
$Days = (int)static::toEnglish($M[1]);
}

elseif (preg_match('/([0-9۰-۹]+)\s*ماه/u', $Label, $M) === 1) {
$Days = (int)static::toEnglish($M[1]) * 30;
}

elseif (preg_match('/([0-9۰-۹]+)\s*سال/u', $Label, $M) === 1) {
$Days = (int)static::toEnglish($M[1]) * 365;
}

if ($Days === null || $Days <= 0) return $Label;
return static::durationLabel($Days);
}

public static function formatBytes(int $Bytes, int $Precision = 2): string {
if ($Bytes <= 0) return self::unitConvert(static::toPersian('0'), 'بایت');
if ($Bytes < 1024) return self::unitConvert(static::toPersian(number_format($Bytes, 0, '.', '')), 'بایت');
$Units = ['بایت', 'کیلوبایت', 'مگابایت', 'گیگابایت', 'ترابایت', 'پتابایت'];
$Power = (int)floor(log($Bytes, 1024));
$Power = max(0, min($Power, count($Units) - 1));
$Value = $Bytes / (1024 ** $Power);
$Number = static::trimZeros(number_format($Value, $Precision, '.', ''));
return self::unitConvert(static::toPersian($Number), $Units[$Power]);
}

public static function containsProfanity(string $Text): bool {
$Dict = self::profanityDictionary();

if ($Dict === []) return false;
$Normalize = static function (string $S): string {
$S = mb_strtolower(trim($S));
$S = strtr($S, ['ي' => 'ی', 'ك' => 'ک', 'ؤ' => 'و', 'أ' => 'ا', 'إ' => 'ا', 'آ' => 'ا', 'ة' => 'ه']);
return preg_replace('/[\x{200B}-\x{200F}\x{064B}-\x{065F}\x{0670}\x{0640}]/u', '', $S) ?? $S;
};

$Normalized = $Normalize($Text);
$Compact = preg_replace('/[\\x{0020}\\x{200C}\\x{200D}]+/u', '', $Normalized) ?? $Normalized;
$Long_Roots = [];
$Short_Words = [];

foreach ($Dict as $Word) {
$W = $Normalize((string)$Word);
$W_Compact = preg_replace('/[\\x{0020}\\x{200C}\\x{200D}]+/u', '', $W) ?? $W;

if ($W_Compact === '') continue;
if (mb_strlen($W_Compact, 'UTF-8') >= 5) $Long_Roots[] = $W_Compact;
else $Short_Words[] = $W;
}

foreach ($Long_Roots as $Bad) {
if (mb_stripos($Normalized, $Bad, 0, 'UTF-8') !== false) return true;
if (mb_stripos($Compact, $Bad, 0, 'UTF-8') !== false) return true;
}

$Tokens = preg_split('/[\x{0020}\x{200C}\x{200D}]+/u', $Normalized) ?: [];
$All_Single = $Tokens !== [] && $Tokens !== [''];
$Joined = '';

foreach ($Tokens as $Token) {
if ($Token === '') continue;
if (in_array($Token, $Short_Words, true)) return true;
if (mb_strlen($Token, 'UTF-8') > 4) {
foreach ($Long_Roots as $Bad) {
if (mb_stripos($Token, $Bad, 0, 'UTF-8') !== false) return true;
}
}

if (mb_strlen($Token, 'UTF-8') !== 1) $All_Single = false;
$Joined .= $Token;
}

if ($All_Single && $Joined !== '') {
if (in_array($Joined, $Short_Words, true)) return true;
foreach ($Long_Roots as $Bad) {
if (mb_stripos($Joined, $Bad, 0, 'UTF-8') !== false) return true;
}
}

return false;
}

private static function profanityDictionary(): array {
static $Cache = null;

if ($Cache !== null) return $Cache;
$File = dirname(__DIR__, 2) . '/Resources/Forbidden-Word.json';

if (!is_file($File)) {
error_log('[Umbrella-Bot][Profanity] Forbidden-Word.json not found; profanity filter is inactive.');
$Cache = [];
return $Cache;
}

$Decoded = json_decode((string)file_get_contents($File), true);

if (!is_array($Decoded) || $Decoded === []) {
error_log('[Umbrella-Bot][Profanity] Forbidden-Word.json is empty or invalid JSON; profanity filter is inactive.');
$Cache = [];
return $Cache;
}

$Words = [];

foreach ($Decoded as $Word) {
if (is_string($Word) && trim($Word) !== '') {
$Words[] = trim($Word);
}
}

$Cache = array_values(array_unique($Words));
return $Cache;
}

private static function unitConvert(string $Number, string $Unit): string {
return $Number . ' ' . $Unit;
}

public static function normalizePhone(string $Phone): string {
$Phone = static::toEnglish(trim($Phone));
$Phone = (string)preg_replace('/[^\d+]/', '', $Phone);

if (str_starts_with($Phone, '+98')) $Phone = '0' . substr($Phone, 3);
elseif (str_starts_with($Phone, '0098')) $Phone = '0' . substr($Phone, 4);
elseif (str_starts_with($Phone, '98') && strlen($Phone) === 12) $Phone = '0' . substr($Phone, 2);
elseif (str_starts_with($Phone, '9') && strlen($Phone) === 10) $Phone = '0' . $Phone;
return (string)preg_replace('/\D/', '', $Phone);
}

public static function validatePhone(string $Phone): bool {
return (bool)preg_match('/^09\d{9}$/', static::normalizePhone($Phone));
}

public static function detectOperator(string $Phone): string {
$Phone = static::normalizePhone($Phone);

if (!static::validatePhone($Phone)) return 'نامعتبر';
$Prefix4 = substr($Phone, 0, 4);

return self::OPERATORS[$Prefix4] ?? 'نامعتبر';
}

public static function toE164(string $Phone): string {
$Phone = static::normalizePhone($Phone);
return '+98' . ltrim($Phone, '0');
}

public static function validateFullName(string $FullName): bool {
$Trimmed = trim($FullName);

if (mb_strlen($Trimmed, 'UTF-8') < 2) {
return false;
}

if (!preg_match('/^[\x{0600}-\x{06FF}]+(?:\s+[\x{0600}-\x{06FF}]+)+$/u', $Trimmed)) {
return false;
}

$Normalized = static::normalizeText($Trimmed);

if (static::containsProfanity($Trimmed)) {
return false;
}

return true;
}



public static function greetingFrame(string $Type, string $Name, string $Section, ?int $User_ID = null): string {
$Name = trim($Name) !== '' ? trim($Name) : $Type;
$Name = self::mention($Name, $User_ID);

try {
$Date_Time_Block = static::currentDateTimeLabel();
}

catch (Throwable) {
$Date_Time_Block = static::DATE_TIME_ERROR_TEXT;
}

return "🌹" . $Type . " گرامی " . $Name . " به بخش " . $Section . " خوش آمدید.\n"
. self::SEPARATOR . "\n"
. $Date_Time_Block . "\n"
. self::SEPARATOR;
}

public static function mention(string $Name, ?int $User_ID = null, string $Username = ''): string {
$Safe_Name = trim(str_replace(['[', ']', "\r", "\n"], '', $Name));
if ($Safe_Name === '') $Safe_Name = trim($Name) !== '' ? trim($Name) : 'کاربر';
$Username = ltrim(trim($Username), '@');

if ($Username !== '' && preg_match('/^[A-Za-z][A-Za-z0-9_]{3,63}$/', $Username) === 1) {
return '[' . $Safe_Name . '](https://t.me/' . $Username . ')';
}

if ($User_ID === null || $User_ID <= 0) {
return $Safe_Name;
}

return '[' . $Safe_Name . '](tg://user?id=' . $User_ID . ')';
}

public static function adminGreeting(Context $Context, string $Section): string {
return static::greetingFrame('مدیریت', $Context->profileName(), $Section, $Context->UserId);
}

public static function frame(string $Type, string $Name, string $Section, ?int $User_ID = null): string {
$Name = trim($Name) !== '' ? trim($Name) : $Type;
return static::greetingFrame($Type, $Name, $Section, $User_ID);
}

public static function adminGreetingNamed(string $Name, string $Section, ?int $User_ID = null): string {
$Name = trim($Name) !== '' ? trim($Name) : 'مدیریت';
return static::greetingFrame('مدیریت', $Name, $Section, $User_ID);
}

public static function userGreeting(Context $Context, string $Section): string {
return static::greetingFrame('کاربر', $Context->profileName(), $Section, $Context->UserId);
}

public static function noticeBlock(string $Icon_Title, string $Body, string $Note = ''): string {
$Lines = $Icon_Title . "\n" . self::SEPARATOR . "\n" . $Body;

if (trim($Note) !== '') {
$Lines .= "\n" . $Note;
}

return $Lines . "\n";
}

public static function adminFooter(): string {
return "\n➖➖➖➖➖➖➖➖➖\n👌جهت استفاده از امکانات مدیریت بر روی منوی مورد نظر کلیک کنید.";
}

public static function userFooter(): string {
return "\n" . self::SEPARATOR . "\n👌جهت استفاده از امکانات ربات بر روی منوی مورد نظر کلیک کنید.";
}

public static function ticketCategories(): array {
return [
'financial' => '💰مالی و شارژ',
'technical' => '🔧فنی و اتصال',
'sales' => '💬فروش و مشاوره',
'account' => '👤حساب کاربری',
'other' => '📦سایر',
];
}

public static function ticketPriorities(): array {
return [
'low' => '🟢کم',
'medium' => '🟡متوسط',
'high' => '🟠زیاد',
'urgent' => '🔴فوری',
];
}

public static function ticketCategoryLabel(string $Category): string {
$Map = static::ticketCategories();
return $Map[strtolower(trim($Category))] ?? '📦سایر';
}

public static function ticketPriorityLabel(string $Priority): string {
$Map = static::ticketPriorities();
return $Map[strtolower(trim($Priority))] ?? '🟡متوسط';
}

public static function isTicketCategory(string $Category): bool {
return array_key_exists(strtolower(trim($Category)), static::ticketCategories());
}

public static function isTicketPriority(string $Priority): bool {
return array_key_exists(strtolower(trim($Priority)), static::ticketPriorities());
}

public static function sourceLabel(string $Source, string $Type = ''): string {
$Key = strtolower(trim($Source));

return match (true) {
$Key === 'gateway', $Key === 'payment', $Key === 'zarinpal' => '🌐درگاه پرداخت اینترنتی',
$Key === 'card', $Key === 'card_to_card', $Key === 'offline' => '💳کارت به کارت',
$Key === 'wallet', $Key === 'balance' => '👛کیف پول',
$Key === 'admin', $Key === 'manager' => '🛠️مدیریت',
$Key === 'auto_renew', $Key === 'autorenew' => '🔄تمدید خودکار',
$Key === 'scheduler', $Key === 'cron', $Key === 'system' => '⚙️سیستم (زمان بند)',
$Key === 'channel', $Key === 'channel_check' => '📢قانون کانال',
$Key === 'server', $Key === 'api' => '🖥️سرور',
$Key === 'user', $Key === 'self' => '👤خود کاربر',
$Key === 'refund' => '↩️بازگشت وجه',
default => $Key !== '' ? ('🧾' . $Key) : '🧾نامشخص',
};
}

public static function actionLabel(string $Action): string {
return match (strtolower(trim($Action))) {
'activate' => '✅فعالسازی اشتراک',
'renew' => '🔄تمدید اشتراک',
'expire' => '⏰انقضای اشتراک',
'deactivate' => '🚫غیرفعال سازی کلاینت',
'admin_update' => '🛠️بروزرسانی توسط مدیریت',
'link' => '🔗اتصال به سرور',
'payment_success' => '💳پرداخت موفق درگاه',
'topup' => '💵شارژ کیف پول',
'credit_add' => '➕افزایش اعتبار',
'credit_sub' => '➖کسر اعتبار',
'wallet_topup' => '👛شارژ کیف پول',
'purchase' => '🛒خرید اشتراک',
'refund' => '↩️بازگشت وجه',
default => '🧾' . $Action,
};
}

public static function rankMedal(int $Rank): string {
if ($Rank <= 0) return '🔹';
$Medals = [
1 => '🥇', 2 => '🥈', 3 => '🥉',
4 => '🏅', 5 => '🎖️', 6 => '🌟', 7 => '⭐️', 8 => '✨', 9 => '💫', 10 => '🔥',
11 => '⚡️', 12 => '💎', 13 => '🚀', 14 => '🎯', 15 => '🏆', 16 => '🎗️', 17 => '🎀', 18 => '🧿', 19 => '🌈', 20 => '☄️',
21 => '🪐', 22 => '🌠', 23 => '🔮', 24 => '🛡️', 25 => '🧩', 26 => '🪄', 27 => '🎐', 28 => '📌', 29 => '🔖', 30 => '🌱',
];

if (isset($Medals[$Rank])) return $Medals[$Rank];
$Cycle = ['🔹', '🔷', '🔸', '🔶', '💠', '🌀', '🌊', '🌙', '🌿', '🍀'];
return $Cycle[($Rank - 31) % count($Cycle)];
}

/** Medal plus the matching title, e.g. "🥇 قهرمان مصرف". */
public static function rankBadge(int $Rank): string {
if ($Rank <= 0) return '🔹 ' . static::rankTitle(0);
return static::rankMedal($Rank) . ' ' . static::rankTitle($Rank);
}

/** One ranking row: number, medal, name, usage, share and an optional bar. */
public static function rankLine(int $Rank, string $Name, string $Usage, float $Share, float $Bar_Percent = -1.0, string $Marks = '', string $Extra = ''): string {
$Bar = $Bar_Percent >= 0.0 ? ' ' . static::usageBar($Bar_Percent, 8) : '';
$Share_Text = $Share >= 0.0 ? ' | ' . static::formatPercent($Share) . '٪' : '';
$Text = static::toPersian((string)$Rank) . '. ' . static::rankMedal($Rank) . $Marks . ' ' . $Name
. ' — ' . $Usage . $Share_Text . $Bar;

if ($Extra !== '') $Text .= ' ' . $Extra;
return $Text;
}

public static function rankTitle(int $Rank): string {
if ($Rank <= 0) return 'بدون رتبه';
if ($Rank === 1) return 'قهرمان مصرف';
if ($Rank === 2) return 'نایب قهرمان';
if ($Rank === 3) return 'رتبه سوم';

return match (true) {
$Rank <= 5 => 'برترین',
$Rank <= 7 => 'نخبه',
$Rank <= 9 => 'درخشان',
$Rank <= 12 => 'برجسته',
$Rank <= 15 => 'ممتاز',
$Rank <= 18 => 'کوشا',
$Rank <= 22 => 'فعال',
$Rank <= 27 => 'پایدار',
$Rank <= 33 => 'رایج',
default => 'عادی',
};
}

public static function rankEmoji(int $Rank): string {
if ($Rank <= 0) return '🔹';
return static::rankMedal($Rank);
}

public static function parseServerTime(string $Raw): int {
$Raw = trim($Raw);

if ($Raw === '' || str_starts_with($Raw, '0001-01-01')) return 0;

if (!preg_match('/^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?/', $Raw, $M)) return 0;

try {
$Stamp = DateTimeImmutable::createFromFormat(
'Y-m-d H:i:s',
$M[1] . '-' . $M[2] . '-' . $M[3] . ' ' . $M[4] . ':' . $M[5] . ':' . ($M[6] ?? '00'),
new DateTimeZone('Asia/Tehran')
);
}
catch (Throwable) {
return 0;
}

return $Stamp === false ? 0 : $Stamp->getTimestamp();
}

public static function parseServerTimeSafe(string $Raw): int {
$Stamp = static::parseServerTime($Raw);
return $Stamp > 0 ? $Stamp : 0;
}

public static function rankStatusIcon(float $Percent): string {
if ($Percent >= 95) return '🚨';
if ($Percent >= 85) return '🔴';
if ($Percent >= 60) return '🟠';
if ($Percent > 0) return '🟢';
return '⚪️';
}

public static function rankStatusLabel(float $Percent): string {
if ($Percent >= 95) return 'مصرف بحرانی';
if ($Percent >= 85) return 'مصرف بسیار بالا';
if ($Percent >= 60) return 'مصرف بالا';
if ($Percent > 0) return 'مصرف عادی';
return 'بدون مصرف';
}

public static function humanAgo(int $Time_Stamp): string {
$Diff = time() - $Time_Stamp;

if ($Time_Stamp <= 0) return 'نامشخص';

if ($Diff < 0) {
$Lead = abs($Diff);

if ($Lead < 60) return 'همین حالا';

if ($Lead < 3600) return static::toPersian((string)intdiv($Lead, 60)) . ' دقیقه دیگر';

return static::toPersian((string)intdiv($Lead, 3600)) . ' ساعت دیگر';
}

if ($Diff < 60) return 'همین حالا';
$Years = intdiv($Diff, 31536000);
$Remainder = $Diff % 31536000;
$Months = intdiv($Remainder, 2592000);
$Remainder %= 2592000;
$Days = intdiv($Remainder, 86400);
$Remainder %= 86400;
$Hours = intdiv($Remainder, 3600);
$Minutes = intdiv($Remainder % 3600, 60);
$Parts = [];

if ($Years > 0) $Parts[] = self::toPersian((string)$Years) . ' سال';
if ($Months > 0) $Parts[] = self::toPersian((string)$Months) . ' ماه';
if ($Days > 0) $Parts[] = self::toPersian((string)$Days) . ' روز';
if ($Hours > 0 && $Years === 0 && $Months === 0) $Parts[] = self::toPersian((string)$Hours) . ' ساعت';
if ($Minutes > 0 && $Years === 0 && $Months === 0 && $Days === 0) $Parts[] = self::toPersian((string)$Minutes) . ' دقیقه';
if ($Parts === []) return 'کمتر از یک دقیقه';
return implode(' و ', array_slice($Parts, 0, 3));
}
}
?>