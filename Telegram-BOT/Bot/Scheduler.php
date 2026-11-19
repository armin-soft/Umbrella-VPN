<?php
declare(strict_types=1);

require_once __DIR__ . '/Context.php';
require_once __DIR__ . '/Channel-Membership.php';
require_once __DIR__ . '/Common.php';
require_once __DIR__ . '/../Core/Telegram/Telegram.php';
require_once __DIR__ . '/../Core/Server/Umbrella-Server.php';
require_once __DIR__ . '/../Core/SMS/IPPanel.php';
require_once __DIR__ . '/../Core/Support/Helper.php';
require_once __DIR__ . '/../Core/Support/Bot-Config.php';
require_once __DIR__ . '/../Core/Storage/Repository.php';
require_once __DIR__ . '/../Core/Database/Database.php';
require_once __DIR__ . '/../Config/Environment.php';
require_once __DIR__ . '/../Core/Subscription/Auto-Renew.php';
require_once __DIR__ . '/../Core/Payment/ZarinPal.php';

final class Scheduler {
private const REPORT_TIME = '00:00';
private function __construct() {
}
public static function diagnoseNightly(): array {
$Now = new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran'));
$Today = $Now->format('Y-m-d');
$Out = [];
$Enabled = strtolower(trim((string)Repository::getSetting('Daily_Report_Enabled', '1')));
$Out[] = 'Daily_Report_Enabled = ' . ($Enabled === '' ? '(empty)' : $Enabled);
$Report_Time = self::reportTime();
$Out[] = 'ReportTime = ' . $Report_Time . ' | TehranNow = ' . $Now->format('H:i')
. ' | IsDue = ' . var_export($Now->format('H:i') >= $Report_Time, true);
$Out[] = 'Today (Tehran) = ' . $Today;
$Out[] = 'Last_Daily_Report = ' . ((string)Repository::getSetting('Last_Daily_Report', '') ?: '(never)');
$Out[] = 'Last_User_Usage_Report = ' . ((string)Repository::getSetting('Last_User_Usage_Report', '') ?: '(never)');
$Out[] = 'Last_Scheduler_Run = ' . ((string)Repository::getSetting('Last_Scheduler_Run', '') ?: '(never)');
$Out[] = 'Administrator = ' . (string)Repository::getSetting('Administrator', (string)Environment::getAdminUserId());
$Out[] = 'CronLock user_usage_report held = ' . var_export(Repository::isCronLockHeld('user_usage_report'), true);
$Out[] = 'CronLock daily_report held = ' . var_export(Repository::isCronLockHeld('daily_report'), true);

try {
$Live = ServerClient::liveUsers();
$Out[] = 'Server liveUsers = ' . count($Live);
}
catch (Throwable $E) {
$Out[] = 'Server liveUsers FAILED = ' . $E->getMessage();
error_log('[Umbrella-Bot][Nightly-DIAG] Server liveUsers failed: ' . $E->getMessage());
}

try {
$Rows = Database::getInstance()->fetchAll(
"SELECT `Telegram_ID` FROM `Users`
WHERE `Is_Blocked` = 0 AND `Chat_ID` > 0
AND `Subscription` IS NOT NULL AND `Subscription` != ''
AND `Expiration_Time_Stamp` IS NOT NULL AND `Expiration_Time_Stamp` > ?
AND " . Repository::CLIENT_CONDITION, [time()]);
$Out[] = 'Eligible active subscribers = ' . (is_array($Rows) ? count($Rows) : 'query-failed');
}
catch (Throwable $E) {
$Out[] = 'Eligible query FAILED = ' . $E->getMessage();
error_log('[Umbrella-Bot][Nightly-DIAG] Eligible query failed: ' . $E->getMessage());
}

return $Out;
}

public static function run(string $Mode = 'all'): void {
$Mode = strtolower(trim($Mode));
if ($Mode === '') $Mode = 'all';

try {
Repository::setSetting('Last_Scheduler_Run', (new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran')))->format('Y-m-d H:i:s'));
}
catch (Throwable) {}

if (in_array($Mode, ['daily', 'reports'], true)) {
self::sendDailyReportIfDue();
self::sendUserUsageReportsIfDue();
return;
}

if ($Mode === 'membership') {
self::checkChannelMemberships(true);
return;
}

if ($Mode === 'operations') {
self::runOperations();
return;
}

self::runOperations();

if ($Mode !== 'all') return;
self::purgeStaleCronLocks();
self::purgeOldDailyNoticesIfDue();
self::checkChannelMemberships();
self::sendExpiryWarnings();
self::sendDailyReportIfDue();
self::sendUserUsageReportsIfDue();
self::sendNowruzWishesIfDue();
}

/**
 * اجرای خودکار کارهای زمان بندی شده، بدون cron و بدون کلید.
 *
 * از مسیر وبهوک (و بازدیدهای ساده از آدرس ربات) صدا زده می شود و با قفل اتمی
 * از اجرای هم زمان چند درخواست جلوگیری می کند (حداکثر یک بار در هر دقیقه).
 */
public static function tick(int $MinInterval = 60): void {
$Now = time();

try {
$Last = (int)Repository::getSetting('Last_Scheduler_Tick', 0);
}
catch (Throwable) {
return;
}

if ($Last > 0 && ($Now - $Last) < max(10, $MinInterval)) {
return;
}

if (!Repository::tryCronLock('scheduler_tick', 600)) {
return;
}

try {
$Fresh_Last = (int)Repository::getSetting('Last_Scheduler_Tick', 0);

if ($Fresh_Last > 0 && ($Now - $Fresh_Last) < max(10, $MinInterval)) {
return;
}

Repository::setSetting('Last_Scheduler_Tick', $Now);
self::run('all');
}
catch (Throwable $Error) {
error_log('[Umbrella-Bot][Scheduler] automatic tick failed: ' . $Error->getMessage());
}
finally {
Repository::releaseCronLock('scheduler_tick');
}
}

/** Manual diagnostics are returned to the caller, never mixed into error_log. */
public static function debugDailyReport(): array {
return self::diagnoseNightly();
}

private static function tehranDay(): string {
if (method_exists(Repository::class, 'tehranToday')) {
return Repository::tehranToday();
}
return (new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran')))->format('Y-m-d');
}

/**
 * قفل اتمی حداکثر یک بار در روز برای هر اعلان خودکار (تلگرام، برنامه و پیامک).
 */
private static function claimDaily(string $Category, int|string $Target, ?string $Day = null): bool {
if (method_exists(Repository::class, 'claimDailyNotice')) {
return Repository::claimDailyNotice($Category, $Target, $Day);
}
$Category = trim($Category);
$Target_Key = trim((string)$Target);
if ($Category === '' || $Target_Key === '') return false;
$Day_Key = ($Day !== null && preg_match('/^\d{4}-\d{2}-\d{2}$/', trim($Day)) === 1)
? trim($Day)
: self::tehranDay();
$Key = 'DailyNotice_' . $Day_Key . '_' . hash('sha256', $Category . ':' . $Target_Key);
if (method_exists(Repository::class, 'getSetting') && (string)Repository::getSetting($Key, '') !== '') {
return false;
}
try {
$Stmt = Database::getInstance()->execute(
'INSERT IGNORE INTO `Settings` (`Key`, `Value`) VALUES (?, ?)',
[$Key, '1']
);
return is_object($Stmt) && method_exists($Stmt, 'rowCount') ? $Stmt->rowCount() === 1 : true;
}
catch (Throwable $Error) {
error_log('[Umbrella-Bot][Daily-Once] ' . $Error->getMessage());
return false;
}
}

private static function claimOnce(string $Key, string $Value = '1'): bool {
if (method_exists(Repository::class, 'claimOnceNotice')) {
return Repository::claimOnceNotice($Key, $Value);
}
$Key = trim($Key);
if ($Key === '') return false;
if (method_exists(Repository::class, 'getSetting') && (string)Repository::getSetting($Key, '') !== '') {
return false;
}
try {
$Stmt = Database::getInstance()->execute(
'INSERT IGNORE INTO `Settings` (`Key`, `Value`) VALUES (?, ?)',
[$Key, $Value]
);
return is_object($Stmt) && method_exists($Stmt, 'rowCount') ? $Stmt->rowCount() === 1 : true;
}
catch (Throwable $Error) {
error_log('[Umbrella-Bot][Once-Notice] ' . $Error->getMessage());
return false;
}
}

private static function hasSetting(string $Key): bool {
if (!method_exists(Repository::class, 'getSetting')) return false;
try {
return (string)Repository::getSetting($Key, '') !== '';
}
catch (Throwable) {
return false;
}
}

private static function purgeOldDailyNoticesIfDue(): void {
if (!method_exists(Repository::class, 'purgeOldDailyNotices')) return;
$Today = self::tehranDay();
if ((string)Repository::getSetting('Last_Daily_Notice_Purge', '') === $Today) return;
try {
Repository::purgeOldDailyNotices(14);
Repository::setSetting('Last_Daily_Notice_Purge', $Today);
}
catch (Throwable) {}
}

private static function purgeStaleCronLocks(): void {
try {
Database::getInstance()->execute('DELETE FROM `Cron_Lock` WHERE `Locked_At` < DATE_SUB(NOW(), INTERVAL 120 MINUTE)');
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Scheduler] purgeStaleCronLocks failed: ' . $Error->getMessage());
}
}

private static function runOperations(): void {
foreach (Repository::pendingSchedules() as $Job) {
$Command = (string)$Job['Command'];
$User_ID = (int)$Job['User_ID'];

try {
if ($Command === 'منقضی اشتراک') {
self::expireSubscription($User_ID);
}
}

catch (Throwable $E) {
error_log("[Umbrella-Bot][Scheduler] Job failed | ID={$Job['ID']} Cmd={$Command} User={$User_ID} Error=" . $E->getMessage());
}

Repository::removeSchedule((int)$Job['ID']);
}

self::catchExpiredSubscriptions();
self::autoRefreshUsages();
self::processAutoRenewals();
self::processPaymentQueue();
}

private static function sendExpiryWarnings(): void {
if (!Repository::tryCronLock('expiry_warnings', 3600)) return;

try {
$Today = self::tehranDay();
$Warn_3 = (string)Repository::getSetting('Expiry_Warning_3Days', '1') === '1';
$Warn_2 = (string)Repository::getSetting('Expiry_Warning_2Days', '1') === '1';
$Warn_1 = (string)Repository::getSetting('Expiry_Warning_1Day', '1') === '1';
$Boundaries = [];

if ($Warn_1) $Boundaries[] = 1;
if ($Warn_2) $Boundaries[] = 2;
if ($Warn_3) $Boundaries[] = 3;

foreach ($Boundaries as $Days) {
$Now = time();
$Lower = $Days * 86400;
$Upper = ($Days + 1) * 86400;
$Rows = Database::getInstance()->fetchAll(
"SELECT `Telegram_ID` FROM `Users`
WHERE `Is_Blocked` = 0
AND `Subscription` IS NOT NULL AND `Subscription` != ''
AND `Expiration_Time_Stamp` IS NOT NULL
AND `Expiration_Time_Stamp` > ?
AND `Expiration_Time_Stamp` <= ?",
[$Now + $Lower, $Now + $Upper]
);

if (!is_array($Rows) || $Rows === []) continue;

$Code = "expire_warn_{$Days}";
$Template = Repository::getSmsTemplate($Code);

foreach ($Rows as $Row) {
$User_ID = (int)($Row['Telegram_ID'] ?? 0);

if ($User_ID <= 0) continue;
$User = Repository::getUser($User_ID);
if ((int)($User['Is_Blocked'] ?? 0) !== 0) continue;
if (trim((string)($User['Deactivation_Message'] ?? '')) !== '') continue;
$Status = (string)($User['Client_Status'] ?? '');
if ($Status !== '' && str_contains($Status, 'غیر')) continue;

$Chat_ID = (int)($User['Chat_ID'] ?? 0);
$Phone = (string)($User['Phone'] ?? '');
$Full_Name = (string)($User['Full_Name'] ?? 'کاربر');
$Subscription = trim((string)($User['Subscription'] ?? ''));
$Exp_Stamp = (int)($User['Expiration_Time_Stamp'] ?? 0);
if ($Subscription === '' || $Exp_Stamp <= $Now) continue;

$Remaining_Label = Helper::remainingDuration($Exp_Stamp);
$Event = implode(':', [$User_ID, $Exp_Stamp, $Days]);

// هر مرز انقضا برای هر اشتراک فقط یک بار و برای هر کاربر در کل روز حداکثر
// یک بار ارسال می شود (حتی اگر مرز روز تغییر کند، تمدید خودکار فعال باشد یا
// زمان انقضا از سرور همگام سازی شود).
$App_Key = 'ExpiryNotice_' . hash('sha256', $Event . ':app');
if (!self::hasSetting($App_Key) && self::claimDaily('renewal_app', $User_ID, $Today)) {
if (self::claimOnce($App_Key, '1')) {
SystemNotifications::queue($User_ID, 'یادآور تمدید اشتراک', '⚠️اشتراک ' . $Subscription . ' شما ' . Helper::toPersian((string)$Days) . ' روز دیگر به اتمام می رسد. زمان باقی مانده: ' . $Remaining_Label, 'expiry-warning:' . $Event, 'warning');
}
}

if ($Chat_ID > 0) {
$Telegram_Key = 'ExpiryNotice_' . hash('sha256', $Event . ':telegram');
if (!self::hasSetting($Telegram_Key) && self::claimDaily('renewal_tg', $User_ID, $Today)) {
if (self::claimOnce($Telegram_Key, '1')) {
Repository::setSetting($Telegram_Key, '1');
$Message = "⚠️اشتراک {$Subscription} شما " . Helper::toPersian((string)$Days)
. " روز دیگر به اتمام می رسد.\n⏳زمان باقیمانده: *{$Remaining_Label}*\n\n⏳برای جلوگیری از قطع، همین الان تمدید کنید.";
$Result = TelegramClient::sendMessage(
$Chat_ID,
Helper::frame('کاربر', $Full_Name, 'تمدید اشتراک', $User_ID) . "📨{$Message}" . Helper::userFooter(),
TelegramClient::inlineKeyboard([
[['text' => '💎تمدید اشتراک', 'callback_data' => 'اشتراک من']],
Common::mainButton(),
])
);
if (($Result['ok'] ?? false) !== true) {
error_log('[Umbrella-Bot][Scheduler] expiry Telegram warning failed | User=' . $User_ID . ' Days=' . $Days);
}
}
}
}

if (Helper::validatePhone($Phone) && $Template !== null) {
$Sms_Key = 'ExpiryNotice_' . hash('sha256', $Event . ':sms');
if (!self::hasSetting($Sms_Key) && self::claimDaily('renewal_sms', $User_ID, $Today)) {
if (self::claimOnce($Sms_Key, '1')) {
Repository::setSetting($Sms_Key, '1');
$Sms_Text = strtr($Template, [
'{full_name}' => $Full_Name,
'{days}' => Helper::toPersian((string)$Days),
'{plan}' => Helper::smsPlan($Subscription),
'{remaining}' => $Remaining_Label,
]);
IppanelClient::sendOnce($User_ID, $Phone, $Sms_Text, 'expiry-warning:' . $Event);
}
}
}
}
}
}

finally {
Repository::releaseCronLock('expiry_warnings');
}
}

private static function processAutoRenewals(): void {
if (!Repository::tryCronLock('auto_renewals', 3600)) return;

try {
AutoRenew::processDue(3);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][AutoRenew] ' . $Error->getMessage());
}

finally {
Repository::releaseCronLock('auto_renewals');
}
}

/**
 * سفارش های درگاهی که کاربر پول را پرداخت کرده ولی به ربات برنگشته است.
 * پیش از این فقط جدول Payment_Queue خوانده می شد که هیچ نویسنده ای نداشت و
 * فراخوانی تایید پرداخت هم با امضای اشتباه انجام می شد.
 */
private static function processPaymentQueue(): void {
if (!Repository::tryCronLock('payment_queue', 900)) return;

try {
if (!class_exists('SubscriptionFlow')) {
require_once __DIR__ . '/Subscription.php';
}

foreach (Repository::sessionsAwaitingPayment(15) as $Row) {
$User_ID = (int)($Row['Telegram_ID'] ?? 0);

if ($User_ID <= 0) continue;

try {
SubscriptionFlow::recoverPendingPayment($User_ID);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Payment-Recovery] User=' . $User_ID . ' | ' . $Error->getMessage());
}
}
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Payment-Recovery] job failed: ' . $Error->getMessage());
}

finally {
Repository::releaseCronLock('payment_queue');
}
}

const SEPARATOR = "➖➖➖➖➖➖➖➖➖\n";

private static function reportTime(): string {
$Configured = trim((string)Repository::getSetting('Daily_Report_Time', self::REPORT_TIME));
$Parts = preg_split('/:/', $Configured) ?: [];
$Hour = isset($Parts[0]) ? (int)$Parts[0] : 0;
$Minute = isset($Parts[1]) ? (int)$Parts[1] : 0;

if (count($Parts) !== 2 || $Hour < 0 || $Hour > 23 || $Minute < 0 || $Minute > 59) {
return self::REPORT_TIME;
}

return sprintf('%02d:%02d', $Hour, $Minute);
}

private static function isReportDue(DateTimeImmutable $Now): bool {
return $Now->format('H:i') >= self::reportTime();
}

public static function buildDailyReportText(bool $For_Yesterday = true): string {
$Tehran = new DateTimeZone('Asia/Tehran');
$Now = new DateTimeImmutable('now', $Tehran);
$Report_Date = $For_Yesterday ? $Now->modify('-1 day')->format('Y-m-d') : $Now->format('Y-m-d');
$Yesterday = $Now->modify('-1 day')->format('Y-m-d');
$Stats = Repository::globalStatistics();

try { $Live_Users = ServerClient::liveUsers(); $Live_Stats = ServerClient::liveServerStats($Live_Users); }
catch (Throwable) { $Live_Users = []; $Live_Stats = []; }

if ($Live_Users !== []) {
$Live_Quota = 0.0; $Live_Remaining = 0.0;

foreach ($Live_Users as $Live_Row) { $Live_Quota += (float)($Live_Row['Total_Usage_GB'] ?? 0); $Live_Remaining += (float)($Live_Row['Remaining_Usage_GB'] ?? 0); }
$Stats['server_clients'] = (int)$Live_Stats['total'];
$Stats['server_clients_active'] = (int)$Live_Stats['active'];
$Stats['server_clients_disabled'] = max(0, (int)$Live_Stats['disabled'] - (int)($Stats['server_clients_expired'] ?? 0));
$Stats['server_quota'] = $Live_Quota;
$Stats['server_used'] = (float)$Live_Stats['total_used'];
$Stats['server_remaining'] = $Live_Remaining;
$Stats['server_avg_used'] = (float)$Live_Stats['avg_used'];
}

$Day_Usage = Repository::usageSnapshotTotals($Report_Date);
$Yesterday_Usage = Repository::usageSnapshotTotals($Yesterday);
$Day_Top = Repository::topUsageGainers($Report_Date, 5);
$Usage_Percent = ((float)$Stats['server_quota']) > 0 ? ((float)$Stats['server_used'] / (float)$Stats['server_quota']) * 100.0 : 0.0;
$Text = "📊*گزارش روزانه سرور آمبرلا*\n" . self::SEPARATOR;
$Text .= "🗓بازه گزارش: *" . Helper::gregorianToJalali($Report_Date) . "*\n";
$Text .= "👥کل اعضای ربات: *" . Helper::toPersian((string)$Stats['total_users']) . "* نفر\n";
$Text .= "🌐کاربران واقعی سرور: *" . Helper::toPersian((string)$Stats['server_clients']) . "* نفر\n";
$Text .= "├─🟢فعال: *" . Helper::toPersian((string)$Stats['server_clients_active']) . "*\n";
$Text .= "├─🔴غیرفعال: *" . Helper::toPersian((string)$Stats['server_clients_disabled']) . "*\n";
$Text .= "└─⏰منقضی شده: *" . Helper::toPersian((string)$Stats['server_clients_expired']) . "*\n";
$Text .= "💎اشتراک های فعال: *" . Helper::toPersian((string)$Stats['active_subscriptions']) . "*\n";
$Text .= "⏳انقضای امروز: *" . Helper::toPersian((string)$Stats['expiring_today']) . "* |📅تا ۳ روز: *" . Helper::toPersian((string)$Stats['expiring_3days']) . "* |🗓تا ۷ روز: *" . Helper::toPersian((string)$Stats['expiring_7days']) . "*\n";
$Text .= "🆕ثبت نام (امروز/هفته/ماه): *" . Helper::toPersian((string)$Stats['new_today']) . "*/*" . Helper::toPersian((string)$Stats['new_week']) . "*/*" . Helper::toPersian((string)$Stats['new_month']) . "*\n";
$Text .= self::SEPARATOR;
$Text .= "📈*مصرف شبکه:*\n";
$Text .= $Day_Usage['available']
? "├─📊مصرف روز گزارش: *" . Helper::formatGB((float)$Day_Usage['used']) . "*\n"
: "├─📊مصرف روز گزارش: *نامشخص (رصد از امروز آغاز شد)*\n";

if ($For_Yesterday === false && $Yesterday_Usage['available'] && $Yesterday !== $Report_Date) {
$Text .= "├─📅مصرف دیروز: *" . Helper::formatGB((float)$Yesterday_Usage['used']) . "*\n";
}

$Text .= "├─📦سهمیه کل کاربران: *" . Helper::formatGB((float)$Stats['server_quota']) . "*\n";
$Text .= "├─📥مصرف کل: *" . Helper::formatGB((float)$Stats['server_used']) . "*\n";
$Text .= "├─📤باقیمانده کل: *" . Helper::formatGB((float)$Stats['server_remaining']) . "*\n";
$Text .= "├─📈درصد مصرف شبکه: *" . Helper::formatPercent($Usage_Percent) . "٪*\n";
$Text .= "└─🧮میانگین مصرف هر کاربر: *" . Helper::formatGB((float)$Stats['server_avg_used']) . "*\n";

if ($Day_Top !== []) {
$Text .= "🏆*پرمصرف ترین های روز:*\n";
$Index = 0;

$Day_Top_Max = 0.0;

foreach ($Day_Top as $Row) {
$Day_Top_Max = max($Day_Top_Max, (float)($Row['Gain'] ?? 0));
}

foreach ($Day_Top as $Row) {
$Index++;
$Name = trim((string)($Row['Full_Name'] ?? ''));

if ($Name === '') $Name = trim((string)($Row['First_Name'] ?? '')) ?: 'کاربر';
$Name_Link = Helper::mention($Name, (int)($Row['User_ID'] ?? 0));
$Gain = (float)($Row['Gain'] ?? 0);
$Gain_Bar = $Day_Top_Max > 0 ? min(100.0, ($Gain / $Day_Top_Max) * 100.0) : 0.0;
$Gain_Marks = $Index === 1 ? '👑' : '';

if ($Gain >= 100.0) $Gain_Marks .= '💎';

$Text .= "├─" . Helper::rankLine($Index, $Name_Link, Helper::formatGB($Gain), -1.0, $Gain_Bar, $Gain_Marks) . "\n";
}
}

else {
$Text .= "🏆پرمصرف ترین های روز: *" . ($For_Yesterday ? 'داده ای ثبت نشده' : 'رصد از امروز آغاز شد، فردا گزارش کامل نمایش داده می شود') . "*\n";
}

$Text .= self::SEPARATOR;
$Text .= "💰*درآمد (تومان):*\n";
$Text .= "├─📅امروز: *" . Helper::formatCurrency($Stats['revenue_today']) . "* (" . Helper::toPersian((string)$Stats['revenue_today_count']) . " تراکنش)\n";
$Text .= "├─🗓۷ روز اخیر: *" . Helper::formatCurrency($Stats['revenue_week']) . "*\n";
$Text .= "├─📆۳۰ روز اخیر: *" . Helper::formatCurrency($Stats['revenue_month']) . "* (" . Helper::toPersian((string)$Stats['revenue_month_count']) . " تراکنش)\n";
$Text .= "└─💎کل درآمد: *" . Helper::formatCurrency($Stats['revenue_total']) . "*\n";
$Text .= "🧾مجموع شارژ کاربران: *" . Helper::formatCurrency($Stats['total_recharge']) . "*\n";
$Text .= "💸مجموع خرید اشتراک: *" . Helper::formatCurrency($Stats['total_spent']) . "*\n";
$Text .= "👛مجموع موجودی کیف پول: *" . Helper::formatCurrency($Stats['total_balance']) . "*\n";
$Text .= self::SEPARATOR;
$Text .= "📩*پیامک:*\n";
$Text .= "├─✅امروز موفق: *" . Helper::toPersian((string)$Stats['sms_today_success']) . "*\n";
$Text .= "├─❌امروز ناموفق: *" . Helper::toPersian((string)$Stats['sms_today_failed']) . "*\n";
$Text .= "└─📊کل: *" . Helper::toPersian((string)$Stats['total_sms']) . "* (✅" . Helper::toPersian((string)$Stats['sms_success']) . " |❌" . Helper::toPersian((string)$Stats['sms_failed']) . ")\n";
$Text .= "🎫تیکت های باز: *" . Helper::toPersian((string)$Stats['open_tickets']) . "* |🚫مسدود: *" . Helper::toPersian((string)$Stats['blocked_users']) . "* |👥دارای پروفایل: *" . Helper::toPersian((string)$Stats['has_profile']) . "*";
return $Text;
}

private static function sendDailyReportIfDue(): void {
$Enabled = strtolower(trim((string)Repository::getSetting('Daily_Report_Enabled', '1')));

if (in_array($Enabled, ['0', 'false', 'off', 'no', 'disabled'], true)) return;
$Now = new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran'));

if (!self::isReportDue($Now)) return;
if (!Repository::tryCronLock('daily_report', 3600)) return;

try {
$Today = $Now->format('Y-m-d');

if ((string)Repository::getSetting('Last_Daily_Report', '') === $Today) return;
$Admin = (int)Repository::getSetting('Administrator', (string)Environment::getAdminUserId());

if ($Admin <= 0) {
error_log('[Umbrella-Bot][Daily-Report] شناسه مدیر تنظیم نشده است (Administrator خالی است).');
return;
}

try {
$Text = Helper::adminGreetingNamed((string)(Repository::getSetting('Admin_Full_Name') ?: Environment::getAdminFullName()), 'گزارش روزانه', $Admin)
. self::buildDailyReportText(true)
. Helper::adminFooter();
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Daily-Report] ساخت متن گزارش ناموفق بود: ' . $Error->getMessage());
return;
}

if (!self::claimDaily('admin_daily_report', $Admin, $Today)) {
Repository::setSetting('Last_Daily_Report', $Today);
return;
}

Repository::setSetting('Last_Daily_Report', $Today);
$Result = TelegramClient::sendSystemMessage($Admin, $Text);

if (is_array($Result) && ($Result['ok'] ?? false) !== true) {
error_log('[Umbrella-Bot][Daily-Report] ارسال گزارش روزانه ناموفق بود: ' . json_encode($Result, JSON_UNESCAPED_UNICODE));
}
}

finally {
Repository::releaseCronLock('daily_report');
}
}

private static function nightlyRecipientEligible(array $User, ?array $Live): bool {
$Client = trim((string)($User['Client_ID'] ?? ''));
if ((int)($User['Is_Blocked'] ?? 1) !== 0
|| trim((string)($User['Subscription'] ?? '')) === ''
|| (int)($User['Expiration_Time_Stamp'] ?? 0) <= time()
|| !in_array((string)($User['Client_Status'] ?? ''), ['فعال', '✅فعال'], true)
|| trim((string)($User['Deactivation_Message'] ?? '')) !== ''
|| (int)($User['Channel_Client_Disabled_At'] ?? 0) > 0
|| $Client === '' || $Client === '_' || $Live === null) return false;
if ((string)($Live['Client_ID'] ?? '') !== $Client
|| (int)($Live['Server_Is_Active'] ?? 0) !== 1
|| (int)($Live['Server_Enable'] ?? 0) !== 1) return false;
$Limit = (float)($Live['Total_Usage_GB'] ?? 0);
return $Limit <= 0 || (float)($Live['Used_Usage_GB'] ?? 0) < $Limit;
}

private static function sendUserUsageReportsIfDue(): void {
$Now = new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran'));
if (!self::isReportDue($Now)) return;

if (!Repository::tryCronLock('user_usage_report', 3600)) return;

try {
$Today = $Now->format('Y-m-d');

if ((string)Repository::getSetting('Last_User_Usage_Report', '') === $Today) return;
try { $Live_Users = ServerClient::liveUsers(); }
catch (Throwable $Error) { error_log('[Umbrella-Bot][Nightly] live status unavailable: ' . $Error->getMessage()); $Live_Users = []; }
// Without confirmed live state, skip delivery and allow a later scheduler retry.
if ($Live_Users === []) return;
$Board = $Live_Users;
$Rank_Map = [];
$Live_Map = [];
$Board_Total = 0.0;

foreach ($Board as $Idx => $Row) {
$Telegram_ID = (int)($Row['Telegram_ID'] ?? 0);
$Rank_Map[$Telegram_ID] = $Idx + 1;
$Live_Map[$Telegram_ID] = $Row;
$Board_Total += (float)($Row['Value'] ?? 0);
}

$Board_Count = count($Board);
$Rows = Database::getInstance()->fetchAll(
"SELECT `Telegram_ID`, `Chat_ID`, `First_Name`, `Full_Name`, `Subscription`, `Client_Status`,
`Total_Usage_GB`, `Used_Usage_GB`, `Remaining_Usage_GB`, `Percent_Usage`,
`Expiration_Time_Stamp`
FROM `Users`
WHERE `Is_Blocked` = 0
AND `Client_Status` IN ('فعال', '✅فعال')
AND (`Deactivation_Message` IS NULL OR `Deactivation_Message` = '')
AND (`Channel_Client_Disabled_At` IS NULL OR `Channel_Client_Disabled_At` = 0)
AND `Subscription` IS NOT NULL AND `Subscription` != ''
AND `Expiration_Time_Stamp` IS NOT NULL AND `Expiration_Time_Stamp` > ?
AND " . Repository::CLIENT_CONDITION,
[time()]
);

if (!is_array($Rows) || $Rows === []) return;
$Sent = 0;
$Dead_Chats = [];
$Failed_Transient = 0;

$Now_Stamp = time();
$Skipped_No_Subscription = 0;

foreach ($Rows as $U) {
$User_ID = (int)($U['Telegram_ID'] ?? 0);
$Chat_ID = (int)($U['Chat_ID'] ?? 0);

if ($User_ID <= 0) continue;
if (!Repository::nightlyReportEnabled($User_ID)) continue;
$U = Repository::getUser($User_ID) ?? [];
$Live = $Live_Map[$User_ID] ?? null;
if (!self::nightlyRecipientEligible($U, $Live)) continue;
$Chat_ID = (int)($U['Chat_ID'] ?? 0);
$Has_Subscription = trim((string)($U['Subscription'] ?? '')) !== '';
$Expiry_Stamp = (int)($U['Expiration_Time_Stamp'] ?? 0);

if (!$Has_Subscription || $Expiry_Stamp <= $Now_Stamp) {
$Skipped_No_Subscription++;
continue;
}

$Name = trim((string)($U['Full_Name'] ?? '')) !== '' ? (string)$U['Full_Name'] : (string)($U['First_Name'] ?? 'کاربر');
$Live = $Live_Map[$User_ID] ?? null;
$Total = $Live !== null ? (float)($Live['Total_Usage_GB'] ?? 0) : (float)($U['Total_Usage_GB'] ?? 0);
$Used = $Live !== null ? (float)($Live['Used_Usage_GB'] ?? 0) : (float)($U['Used_Usage_GB'] ?? 0);
$Remaining = $Live !== null ? (float)($Live['Remaining_Usage_GB'] ?? 0) : (float)($U['Remaining_Usage_GB'] ?? 0);

if ($Remaining <= 0 && $Total > 0) $Remaining = max(0.0, $Total - $Used);
$Percent = $Total > 0 ? min(100.0, ($Used / $Total) * 100.0) : 0.0;
$Bar = Helper::usageBar($Percent, 12);
$My_Rank = (int)($Rank_Map[$User_ID] ?? 0);
$Rank_Line = $My_Rank > 0
? "🏆رتبه شما در مصرف: " . Helper::rankEmoji($My_Rank) . " " . Helper::rankTitle($My_Rank) . "\n"
. "📊سهم شما از مصرف شبکه: *" . Helper::percentShare($Used, $Board_Total) . "*\n"
: '';
$Status_Icon = Helper::rankStatusIcon($Percent);
$Status_Label = Helper::rankStatusLabel($Percent);
$Exp_Stamp = (int)($U['Expiration_Time_Stamp'] ?? 0);
$Expire_Line = "⏳زمان باقیمانده اشتراک: *" . Helper::remainingDuration($Exp_Stamp) . "*\n";

if ($Exp_Stamp > 0) {
$Expire_Line .= "📅تاریخ انقضا: *" . Helper::formatExpirationShort($Exp_Stamp) . "*\n";
}

$Last_Online_Line = "📡آخرین اتصال: *" . ($Live === null ? 'نامشخص (دادهٔ زنده در دسترس نیست)' : 'نامشخص') . "*\n";
$Last_Online = $Live !== null ? (string)($Live['Last_Online'] ?? '') : '';

if ($Last_Online !== '' && $Last_Online !== '0001-01-01 00:00:00') {
try {
$Last_Stamp = \Helper::parseServerTimeSafe($Last_Online);

if ($Last_Stamp > 0) {
$Age_Seconds = time() - $Last_Stamp;
$Last_Online_Line = $Age_Seconds >= 0
? "📡آخرین اتصال: *" . Helper::humanAgo($Last_Stamp) . " پیش*\n"
: "📡آخرین اتصال: *" . Helper::humanAgo($Last_Stamp) . "*\n";
}
}

catch (Throwable) {}
}

$Text = Helper::frame('کاربر', $Name, 'گزارش شبانه مصرف', $User_ID)
. "📈<b>گزارش شبانه مصرف شما</b>\n"
. self::SEPARATOR . "\n"
. $Rank_Line
. "📊<b>وضعیت مصرف:</b>\n"
. "`{$Bar}` " . Helper::formatPercent($Percent) . "٪ " . "{$Status_Icon} {$Status_Label}\n"
. "├─📦<b>سهمیه کل:</b> <b>" . Helper::formatGB($Total) . "</b>\n"
. "├─📥<b>مصرف شده:</b> <b>" . Helper::formatGB($Used) . "</b>\n"
. "└─📤<b>باقیمانده:</b> <b>" . Helper::formatGB($Remaining) . "</b>\n"
. $Expire_Line
. $Last_Online_Line
. self::SEPARATOR
. "\n💡<b>نکته:</b> با مدیریت هوشمند مصرف، اتصال پایدارتری خواهید داشت."
. Helper::userFooter();

// Recheck local holds/preferences and enforce strict per-user once-per-day cap
// immediately before either transport so even an interrupted batch never resends.
if (!Repository::nightlyReportEnabled($User_ID)
|| !self::nightlyRecipientEligible(Repository::getUser($User_ID) ?? [], $Live)) continue;
if (!self::claimDaily('nightly_report', $User_ID, $Today)) continue;
SystemNotifications::queue($User_ID, 'گزارش شبانه مصرف', $Text, 'nightly:' . $Today);
if ($Chat_ID <= 0) continue;
$Result = TelegramClient::sendMessage($Chat_ID, $Text, TelegramClient::inlineKeyboard([
[['text' => '💎اشتراک من', 'callback_data' => 'اشتراک من'], ['text' => '📊گزارش مصرف', 'callback_data' => 'گزارش مصرف']],
Common::mainButton(),
]));

if (is_array($Result) && ($Result['ok'] ?? false) !== true) {
$Error_Code = (int)($Result['error_code'] ?? 0);
$Error_Desc = (string)($Result['description'] ?? '');
$Is_Dead_Chat = in_array($Error_Code, [400, 401, 403], true)
&& (str_contains($Error_Desc, 'chat not found')
|| str_contains($Error_Desc, 'bot was blocked')
|| str_contains($Error_Desc, 'bot was kicked')
|| str_contains($Error_Desc, 'user is deactivated')
|| str_contains($Error_Desc, 'bot can\'t initiate')
|| str_contains($Error_Desc, 'bot can\'t send'));

if ($Is_Dead_Chat) {
$Dead_Chats[] = $Chat_ID;
continue;
}

error_log('[Umbrella-Bot][Daily-Report] ارسال به Chat ' . $Chat_ID . ' ناموفق بود: ' . json_encode($Result, JSON_UNESCAPED_UNICODE));
$Failed_Transient++;
continue;
}

$Sent++;
}

$Failed_Count = $Failed_Transient ?? 0;

if ($Failed_Count > 0) {
error_log('[Umbrella-Bot][Daily-Report] خطای موقت در ارسال: ' . $Failed_Count . ' مورد.');
}

Repository::setSetting('Last_User_Usage_Report', $Today);
}

finally {
Repository::releaseCronLock('user_usage_report');
}
}

private static function sendNowruzWishesIfDue(): void {
$Nowruz_Already_Sent = (string)Repository::getSetting('Nowruz_Last_Sent', '');
$Current_Year = (new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran')))->format('Y');
$Today_Month_Day = (new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran')))->format('m-d');

if ($Today_Month_Day !== '03-20' || $Nowruz_Already_Sent === $Current_Year) return;
if (!Repository::tryCronLock('nowruz', 86400)) return;

try {
$Template = Repository::getSmsTemplate('nowruz') ?? "سرور آمبرلا\n\nفرا رسیدن سال نو را تبریک می گوییم.";

foreach (Repository::allUserIds() as $User_ID) {
$Uid = (int)$User_ID;
if ($Uid <= 0) continue;
$User = Repository::getUser($Uid);
if ((int)($User['Is_Blocked'] ?? 0) !== 0) continue;
if (!self::claimOnce('NowruzNotice_' . $Current_Year . '_' . $Uid, '1')) continue;
if (!self::claimDaily('nowruz', $Uid)) continue;
$Full_Name = (string)($User['Full_Name'] ?? 'کاربر');
$Chat_ID = (int)($User['Chat_ID'] ?? 0);
$Phone = (string)($User['Phone'] ?? '');
$Message = strtr($Template, ['{full_name}' => $Full_Name]);
SystemNotifications::queue($Uid, 'تبریک سال نو', $Message, 'nowruz:' . $Current_Year);

if ($Chat_ID > 0) {
TelegramClient::sendMessage($Chat_ID, Helper::frame('کاربر', $Full_Name, 'تبریک سال نو', $Uid) . "🌷{$Message}" . Helper::userFooter());
}

if (Helper::validatePhone($Phone)) {
IppanelClient::sendOnce($Uid, $Phone, $Message, 'nowruz:' . $Current_Year);
}
}

Repository::setSetting('Nowruz_Last_Sent', $Current_Year);
}

finally {
Repository::releaseCronLock('nowruz');
}
}

private static function catchExpiredSubscriptions(): void {
$Rows = Database::getInstance()->fetchAll(
"SELECT `Telegram_ID` FROM `Users`
WHERE `Subscription` IS NOT NULL AND `Subscription` != ''
AND `Expiration_Time_Stamp` IS NOT NULL AND `Expiration_Time_Stamp` > 0
AND `Expiration_Time_Stamp` <= ?",
[time()]
);

if (!is_array($Rows)) return;
foreach ($Rows as $Row) {
$User_ID = (int)($Row['Telegram_ID'] ?? 0);

if ($User_ID <= 0) continue;
self::expireSubscription($User_ID);
}
}

private static function checkChannelMemberships(bool $Force = false): void {

$Interval_Hours = (int)Repository::getSetting('Channel_Check_Interval_Hours', '12');
$Interval = max(1, $Interval_Hours > 0 ? $Interval_Hours : 12) * 3600;
$Last_Check = (int)Repository::getSetting('Last_Channel_Check_At', 0);

$Full_Check = $Force || $Last_Check <= 0 || (time() - $Last_Check) >= $Interval;
if (!Repository::tryCronLock('channel_membership', 3600)) return;

try {
$Channel_Url = BotConfig::getChannelUrl();
$Channel_Name = self::extractChannelName($Channel_Url);
$Channel_ID = BotConfig::getTelegramChannelId();

if ($Channel_Name === '' && $Channel_ID === '') return;
if ($Full_Check) Repository::setSetting('Last_Channel_Check_At', (string)time());
$Grace_Seconds = Environment::getChannelGraceSeconds();
$Ids = $Full_Check ? Repository::allUserIds() : array_column(Database::getInstance()->fetchAll(
'SELECT `Telegram_ID` FROM `Users` WHERE (`Channel_Grace_Started_At` > 0 OR `Channel_Client_Disabled_At` > 0) AND (`Channel_Member_Check_At` IS NULL OR `Channel_Member_Check_At` < ?) ORDER BY `Channel_Member_Check_At` ASC LIMIT 200', [time() - 60]
), 'Telegram_ID');
foreach ($Ids as $User_ID) {
$User_ID = (int)$User_ID;

if ($User_ID <= 0) continue;
self::checkMembership($User_ID, $Channel_Name, $Channel_ID, $Grace_Seconds);
}
}

finally {
Repository::releaseCronLock('channel_membership');
}
}

public static function channelMembershipChanged(array $Update): void {
$Channel = (string)BotConfig::getTelegramChannelId();
$Member = $Update['chat_member'] ?? [];
if ($Channel === '' || (string)($Member['chat']['id'] ?? '') !== $Channel) return;
$UserId = (int)($Member['new_chat_member']['user']['id'] ?? 0);
if ($UserId <= 0) return;
// Recheck through Telegram; do not trust a callback or a different channel.
self::checkMembership($UserId, self::extractChannelName(BotConfig::getChannelUrl()), $Channel, Environment::getChannelGraceSeconds());
}

private static function checkMembership(int $User_ID, string $Channel_Name, string $Channel_ID, int $Grace_Seconds): void {
$User = Repository::getUser($User_ID);
$Chat_ID = (int)($User['Chat_ID'] ?? 0);
$Client_ID = (string)($User['Client_ID'] ?? '');
$Full_Name = (string)($User['Full_Name'] ?? 'کاربر');
$Has_Client = $Client_ID !== '' && $Client_ID !== '_';

$Status = ($Channel_Name === '' && $Channel_ID === '')
? 'unknown'
: TelegramClient::channelMemberStatus($User_ID, $Channel_Name, $Channel_ID);
$Grace_Started_At = (int)($User['Channel_Grace_Started_At'] ?? 0);
$Disabled_At = (int)($User['Channel_Client_Disabled_At'] ?? 0);
$Channel_Url = BotConfig::getChannelUrl();
$Minutes = (int)ceil($Grace_Seconds / 60);

if ($Status === 'unknown_participant') {
Repository::updateUser($User_ID, ['Channel_Member_Check_At' => time()]);
return;
}

if ($Status === 'unknown') {
return;
}

Repository::updateUser($User_ID, ['Channel_Member_Check_At' => time()]);
$Is_Member = $Status === 'member';

if ($Is_Member) {
ChannelMembership::restore($User_ID);
return;
}

if ($Grace_Started_At <= 0) {
Repository::updateUser($User_ID, ['Channel_Grace_Started_At' => time()]);

if ($Has_Client) {
self::sendLeaveWarning($Chat_ID, $User_ID, $Full_Name, $Channel_Url, $Minutes, true);
}

return;
}

if (!$Has_Client) return;
if ($Disabled_At > 0) return;
if (time() - $Grace_Started_At < $Grace_Seconds) {
// در طول مهلت عضویت، اعلان تکراری ارسال نمی شود (حداکثر یک هشدار در روز).
return;
}

if (!ChannelMembership::suspend($User_ID)) return;
if (!method_exists(Repository::class, 'claimDailyNotice') || Repository::claimDailyNotice('channel_disabled_app', $User_ID)) {
SystemNotifications::queue($User_ID, 'قطع به دلیل عضویت کانال', '⛔️مهلت عضویت تمام شد؛ کلاینت به دلیل عدم عضویت قطع شد. برای اتصال دوباره عضو شوید: ' . $Channel_Url, 'channel-disabled:' . $Grace_Started_At, 'warning');
}

$Phone = (string)($User['Phone'] ?? '');
if (Helper::validatePhone($Phone) && self::claimDaily('channel_disabled_sms', $User_ID)) {
self::sendChannelDisabledSms($User_ID, $Phone, $Channel_Url);
}

if ($Chat_ID > 0 && self::claimDaily('channel_disabled_tg', $User_ID)) {
$Greeting = Common::greet(new Context([], $User_ID, $Chat_ID, $Full_Name, false, null, null, null, null), 'عضویت در کانال');
TelegramClient::sendMessage($Chat_ID, "{$Greeting}⛔️مهلت عضویت شما به اتمام رسید.\n\n⚠️کلاینت شما به دلیل عدم عضویت در کانال اطلاع رسانی قطع گردید.\n👌جهت اتصال مجدد باید عضو کانال شوید." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '📢عضویت در کانال', 'url' => $Channel_Url]],
[['text' => '✅بررسی مجدد عضویت', 'callback_data' => 'بررسی عضویت کانال']],
Common::mainButton(),
]));
}
}

private static function extractChannelName(string $Link): string {
$Link = trim($Link, "/ \t\n\r\0\x0B");
$Link = preg_replace('#^https?://#i', '', $Link) ?? $Link;
$Link = preg_replace('#^(?:t\.me|telegram\.me)/#i', '', $Link) ?? $Link;
$Link = preg_replace('~[?#].*$~', '', $Link) ?? $Link;
$Link = preg_replace('/^@/', '', $Link) ?? $Link;
$Name = explode('/', $Link)[0] ?? '';

return preg_match('/^[A-Za-z0-9_]{3,32}$/', $Name) === 1 ? $Name : '';
}

private static function graceLabel(int $Seconds): string {
$Seconds = max(0, $Seconds);
$Days = intdiv($Seconds, 86400);
$Hours = intdiv($Seconds % 86400, 3600);
$Minutes = intdiv($Seconds % 3600, 60);
$Parts = [];

if ($Days > 0) $Parts[] = Helper::toPersian((string)$Days) . ' روز';
if ($Hours > 0) $Parts[] = Helper::toPersian((string)$Hours) . ' ساعت';
if ($Minutes > 0) $Parts[] = Helper::toPersian((string)$Minutes) . ' دقیقه';

return $Parts === [] ? 'کمتر از یک دقیقه' : implode(' و ', $Parts);
}

private static function sendLeaveWarning(int $Chat_ID, int $User_ID, string $Full_Name, string $Channel_Url, int $Minutes, bool $First): void {
$User = Repository::getUser($User_ID);
$Phone = (string)($User['Phone'] ?? '');
if (!method_exists(Repository::class, 'claimDailyNotice') || Repository::claimDailyNotice('channel_warn_app', $User_ID)) {
SystemNotifications::queue($User_ID, 'هشدار عضویت کانال', '⚠️شما عضو کانال نیستید. مهلت باقی مانده: ' . self::graceLabel(max(0, $Minutes) * 60) . ' — ' . $Channel_Url, 'channel-warning:' . (int)($User['Channel_Grace_Started_At'] ?? 0) . ':' . ($First ? 'first' : 'reminder'), 'warning');
}

if ($First && Helper::validatePhone($Phone) && self::claimDaily('channel_warn_sms', $User_ID)) {
self::sendChannelWarningSms($User_ID, $Phone, $Channel_Url, $Minutes);
}

if ($Chat_ID <= 0) return;
if (!self::claimDaily('channel_warn_tg', $User_ID)) return;
$Greeting = Common::greet(new Context([], $User_ID, $Chat_ID, $Full_Name, false, null, null, null, null), 'عضویت در کانال');
$Title = $First
? "⚠️شما از کانال اطلاع رسانی خارج شده اید."
: "🔔یادآور: هنوز عضو کانال نشده اید.";
$Body = "⚠️شما از کانال اطلاع رسانی خارج شده اید.\n🕒مهلت باقیمانده: *" . self::graceLabel(max(0, $Minutes) * 60) . "*\n⛔️در غیر این صورت کلاینت شما قطع می گردد.";
TelegramClient::sendMessage($Chat_ID, $Greeting . $Title . "\n" . $Body . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '📢عضویت در کانال', 'url' => $Channel_Url]],
[['text' => '✅بررسی عضویت', 'callback_data' => 'بررسی عضویت کانال']],
Common::mainButton(),
]));
}

private static function sendChannelWarningSms(int $User_ID, string $Phone, string $Channel_Url, int $Minutes): void {
if (!Helper::validatePhone($Phone)) return;
$Template = Repository::getSmsTemplate('channel_leave_warning');
$Template = $Template !== null ? self::stripChannelUrl($Template) : null;
$Remaining_Label = self::graceLabel(max(0, $Minutes) * 60);
$Sms_Text = $Template !== null
? strtr($Template, [
'{full_name}' => (string)(Repository::getUser($User_ID)['Full_Name'] ?? 'کاربر'),
'{minutes}' => Helper::toPersian((string)$Minutes),
'{remaining}' => $Remaining_Label,
'{channel_url}' => '',
])
: "کاربر گرامی، شما از کانال اطلاع رسانی خارج شده اید.\nمهلت باقیمانده: " . $Remaining_Label . "\nدر غیر این صورت کلاینت شما قطع می گردد.\nلطفا از طریق ربات عضو کانال اطلاع رسانی شوید.\n\nسرور آمبرلا";

if (!IppanelClient::sendOnce($User_ID, $Phone, trim($Sms_Text), 'channel-warning:' . (int)(Repository::getUser($User_ID)['Channel_Grace_Started_At'] ?? 0))) {
error_log("[Umbrella-Bot][Scheduler][ChannelWarning] SMS failed for User={$User_ID} Phone={$Phone}");
}
}

private static function sendChannelDisabledSms(int $User_ID, string $Phone, string $Channel_Url): void {
if (!Helper::validatePhone($Phone)) return;
$Template = Repository::getSmsTemplate('channel_disabled');
$Template = $Template !== null ? self::stripChannelUrl($Template) : null;
$Sms_Text = $Template !== null
? strtr($Template, [
'{full_name}' => (string)(Repository::getUser($User_ID)['Full_Name'] ?? 'کاربر'),
'{channel_url}' => '',
])
: "کاربر گرامی، مهلت عضویت شما در کانال به اتمام رسید.\nکلاینت شما به دلیل عدم عضویت قطع گردید.\nبرای اتصال مجدد از طریق ربات عضو کانال اطلاع رسانی شوید.\n\nسرور آمبرلا";

if (!IppanelClient::sendOnce($User_ID, $Phone, trim($Sms_Text), 'channel-disabled:' . (int)(Repository::getUser($User_ID)['Channel_Grace_Started_At'] ?? 0))) {
error_log("[Umbrella-Bot][Scheduler][ChannelDisabled] SMS failed for User={$User_ID} Phone={$Phone}");
}
}

private static function stripChannelUrl(string $Template): string {
$Template = preg_replace('~https?://[^\s"\'<>]+~u', '', $Template) ?? $Template;
$Template = preg_replace('~t\.me/[^\s"\'<>]+~iu', '', $Template) ?? $Template;
$Template = preg_replace('~telegram\.me/[^\s"\'<>]+~iu', '', $Template) ?? $Template;
$Template = str_replace('{channel_url}', '', $Template);
$Template = preg_replace("~\n{3,}~u", "\n\n", $Template) ?? $Template;
return trim($Template);
}

private static function expireSubscription(int $User_ID): void {
$Lock = 'expire_user_' . $User_ID;
if (!Repository::tryCronLock($Lock, 3600)) return;
try {
$Row = Repository::getUser($User_ID);
// Old scheduled jobs must never expire a renewed subscription.
if ((int)($Row['Expiration_Time_Stamp'] ?? 0) > time()) return;
$Subscription = $Row['Subscription'] ?? null;

if (!is_string($Subscription) || $Subscription === '') {
return;
}

$Full_Name = (string)($Row['Full_Name'] ?? 'کاربر');
$Phone = (string)($Row['Phone'] ?? '');
$Chat_ID = (int)($Row['Chat_ID'] ?? 0);
$Client_ID = (string)($Row['Client_ID'] ?? '');
$Keep_For_Auto_Renew = trim((string)($Row["Auto_Renew_Plan"] ?? "")) !== "";
$Server_Disabled = true;

if ($Client_ID !== '' && $Client_ID !== '_') {
$Disable_Response = ServerClient::updateUser($Client_ID, ['is_active' => false, 'enable' => false]);
$Status = (int)($Disable_Response['StatusCode'] ?? 0);

if ($Status < 200 || $Status >= 300) {
$Server_Disabled = false;
if (self::claimDaily('admin_expire_error', $User_ID)) {
AdminFlow::notifyAdminServerError('منقضی اشتراک (خودکار)', $User_ID, $Full_Name, $Status, (string)($Disable_Response['Body'] ?? ''));
}
}
}

if ($Server_Disabled) {
Repository::updateUser($User_ID, ['Client_Status' => '🚫غیر فعال', 'Channel_Client_Disabled_At' => null]);
Repository::addSubscriptionLog($User_ID, 'expire', $Subscription, null, null, 'انقضای خودکار اشتراک (زمان بند خودکار)', 'scheduler');
}

$Expired_Event = IppanelClient::subscriptionEvent('expired', $Row);
$Expire_App_Key = 'ExpireNotice_' . hash('sha256', $User_ID . ':' . $Expired_Event . ':app');
if (!self::hasSetting($Expire_App_Key) && self::claimDaily('expired_app', $User_ID) && self::claimOnce($Expire_App_Key, '1')) {
SystemNotifications::queue($User_ID, 'انقضای اشتراک', '⏳اشتراک ' . $Subscription . ' شما به پایان رسید؛ برای ادامه سرویس تمدید کنید.', 'expired:' . (int)($Row['Expiration_Time_Stamp'] ?? 0), 'warning');
}

if ($Chat_ID > 0) {
$Expire_Tg_Key = 'ExpireNotice_' . hash('sha256', $User_ID . ':' . $Expired_Event . ':telegram');
if (!self::hasSetting($Expire_Tg_Key) && self::claimDaily('expired_tg', $User_ID) && self::claimOnce($Expire_Tg_Key, '1')) {
$Status_Notice = $Server_Disabled ? '⚠️اتصال شما از سرور قطع گردید.' : '⚠️سرور موقتا در دسترس نیست. اشتراک شما به زودی در سرور نیز غیرفعال خواهد شد.';
TelegramClient::sendMessage($Chat_ID, Helper::frame('کاربر', $Full_Name, 'انقضای اشتراک', $User_ID) . "🌹اشتراک {$Subscription} شما به اتمام رسید.\n\n{$Status_Notice}" . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '💎تمدید اشتراک', 'callback_data' => 'اشتراک من']],
Common::mainButton(),
]));
}
}

if (Helper::validatePhone($Phone)) {
if (self::claimDaily('expired_sms', $User_ID)) {
$Plan = Helper::smsPlan((string)($Subscription ?? ''));
$Template = Repository::getSmsTemplate('expired');
$Sms_Text = $Template !== null
? strtr($Template, ['{full_name}' => $Full_Name, '{plan}' => $Plan])
: "{$Full_Name} گرامی اشتراک {$Plan} شما به اتمام رسید.\nاتصال شما از سرور قطع گردید.\n\nسرور آمبرلا";
$Sent = IppanelClient::sendOnce($User_ID, $Phone, $Sms_Text, IppanelClient::subscriptionEvent('expired', $Row));

if (!$Sent) {
error_log("[Umbrella-Bot][Scheduler][Expire] SMS failed for User={$User_ID} Phone={$Phone}");
}
}
}

if ($Server_Disabled) {
Repository::updateUser($User_ID, [
'Package_Duration' => null, 'Package_Start_Date' => null, 'Total_Usage_GB' => null,
'Used_Usage_GB' => null, 'Remaining_Usage_GB' => null, 'Percent_Usage' => null,
'Subscription' => null,
'Expiration_Date' => $Keep_For_Auto_Renew ? (string)($Row['Expiration_Date'] ?? '') : null,
'Expiration_Time_Stamp' => $Keep_For_Auto_Renew ? (int)($Row['Expiration_Time_Stamp'] ?? 0) : null,
]);
}

else {
Repository::updateUser($User_ID, [
'Package_Duration' => null, 'Package_Start_Date' => null, 'Total_Usage_GB' => null,
'Used_Usage_GB' => null, 'Remaining_Usage_GB' => null, 'Percent_Usage' => null,
'Subscription' => null,
'Expiration_Date' => $Keep_For_Auto_Renew ? (string)($Row['Expiration_Date'] ?? '') : null,
'Expiration_Time_Stamp' => $Keep_For_Auto_Renew ? (int)($Row['Expiration_Time_Stamp'] ?? 0) : time() - 1,
]);
}
} finally { Repository::releaseCronLock($Lock); }
}

private static function autoRefreshUsages(): void {
$Hour_Key = (new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran')))->format('Y-m-d H');

if ((string)Repository::getSetting('Last_Usage_Sync', '') === $Hour_Key) {
return;
}

self::refreshUsagesNow();
}

private static function alertUsageSyncFailure(int $Status, string $Detail): void {
try {
$Today = self::tehranDay();

if ((string)Repository::getSetting('Usage_Sync_Alert_At', '') === $Today) return;
$Admin = (int)Repository::getSetting('Administrator', (string)Environment::getAdminUserId());
if ($Admin <= 0) return;
if (!self::claimDaily('usage_sync_alert', $Admin, $Today)) return;
Repository::setSetting('Usage_Sync_Alert_At', $Today);

TelegramClient::sendSystemMessage($Admin, Helper::adminGreetingNamed((string)(Repository::getSetting('Admin_Full_Name') ?: Environment::getAdminFullName()), 'خطای سرور', $Admin)
. '❌خطای همگام سازی مصرف کاربران' . "\n\n"
. '📡وضعیت: ' . ($Status > 0 ? 'HTTP ' . $Status : 'خطا در ارتباط') . "\n"
. '⚠️پاسخ: ' . mb_substr($Detail !== '' ? $Detail : 'نامشخص', 0, 500) . "\n"
. '➖➖➖➖➖➖➖➖➖' . "\n"
. Helper::adminFooter());
}
catch (Throwable) {
}
}

public static function refreshUsagesNow(): int {
$Response = ServerClient::listUsers();
$Rows = $Response['Json'] ?? null;
$Status = (int)($Response['StatusCode'] ?? 0);

if (!is_array($Rows) || $Status >= 300) {
$Body = trim((string)($Response['Body'] ?? ''));
$Curl_Error = trim((string)($Response['Error'] ?? ''));
error_log('[Umbrella-Bot][Usage-Sync] Failed: HTTP=' . $Status . ' Body=' . $Body . ($Curl_Error !== '' ? ' Error=' . $Curl_Error : ''));
self::alertUsageSyncFailure($Status, $Body !== '' ? $Body : $Curl_Error);
return 0;
}

try {
Repository::rotateUsageSnapshots();
}

catch (Throwable) {}

$Synced = 0;

foreach ($Rows as $Row) {
if (!is_array($Row)) continue;
$Telegram_ID = (int)($Row['telegram_id'] ?? 0);
$Uuid = trim((string)($Row['uuid'] ?? ''));
$Used_GB = (float)($Row['current_usage_GB'] ?? 0);
$Limit = (float)($Row['usage_limit_GB'] ?? 0);
$Last_Online = (string)($Row['last_online'] ?? '');
$Is_Active = !empty($Row['is_active']);
$Enable = !empty($Row['enable']);
$User = [];

if ($Telegram_ID > 0) $User = Repository::getUser($Telegram_ID);
if (empty($User) && $Uuid !== '') $User = Repository::getUserByClientId($Uuid);
if (empty($User)) continue;

$User_ID = (int)($User['Telegram_ID'] ?? 0);
if ($User_ID <= 0) continue;

if ($Limit <= 0) $Limit = (float)($User['Total_Usage_GB'] ?? 0);
$Remaining = max(0.0, $Limit - $Used_GB);
$Percent = $Limit > 0 ? round(($Used_GB / $Limit) * 100, 1) : 0.0;

$Fields = [
'Used_Usage_GB' => round($Used_GB, 3),
'Remaining_Usage_GB' => round($Remaining, 3),
'Percent_Usage' => $Percent,
'Server_Is_Active' => $Is_Active ? 1 : 0,
'Server_Enable' => $Enable ? 1 : 0,
];

if ($Limit > 0) $Fields['Total_Usage_GB'] = $Limit;

if ($Last_Online !== '' && $Last_Online !== '0001-01-01 00:00:00') {
$Current = (string)($User['Last_Online'] ?? '');
if ($Last_Online > $Current) $Fields['Last_Online'] = $Last_Online;
}

Repository::updateUser($User_ID, $Fields);
$Synced++;
}

Repository::setSetting('Last_Usage_Sync', (new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran')))->format('Y-m-d H'));

try {
Repository::updateUsageSnapshotValues();
}

catch (Throwable) {}

return $Synced;
}
}
?>