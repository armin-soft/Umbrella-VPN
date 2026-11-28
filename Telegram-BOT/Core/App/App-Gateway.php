<?php
declare(strict_types=1);

require_once __DIR__ . '/../Database/Database.php';
require_once __DIR__ . '/../Database/Schema-App.php';
require_once __DIR__ . '/../Server/Umbrella-Panel.php';
require_once __DIR__ . '/App-Device-Limit.php';
require_once __DIR__ . '/Account-Revocation.php';
require_once __DIR__ . '/App-Two-Step.php';
require_once __DIR__ . '/App-Secret.php';
require_once __DIR__ . '/App-Bot-Link.php';
require_once __DIR__ . '/../Telegram/Bot-Identity.php';
require_once __DIR__ . '/../SMS/IPPanel.php';
require_once __DIR__ . '/../Telegram/Telegram.php';
require_once __DIR__ . '/../Storage/Repository.php';
require_once __DIR__ . '/../Support/Bot-Config.php';
require_once __DIR__ . '/../Support/Helper.php';
require_once __DIR__ . '/../../Bot/Context.php';
require_once __DIR__ . '/../../Bot/Channel-Membership.php';
require_once __DIR__ . '/../../Bot/Subscription.php';
require_once __DIR__ . '/../Payment/ZarinPal.php';
require_once __DIR__ . '/App-Filter.php';
require_once __DIR__ . '/App-Bypass.php';
require_once __DIR__ . '/System-Notifications.php';
require_once dirname(__DIR__, 2) . '/Config/Environment.php';

/**
 * HTTPS gateway the desktop app signs in through.
 *
 * The app never sees the bot token, the IPPanel key or the panel key for this
 * path; it only gets a challenge id. Everything sensitive — the SMS, the
 * Telegram confirmation, the panel account — happens here.
 *
 * Routes, relative to this file's URL:
 *   POST auth/start    {phone,device_id,device_name,platform,app_version[,first_name,last_name]}
 *                      without names the answer is `stage: needs_profile` when the
 *                      number has no account yet; with names it registers and texts the code
 *   POST auth/verify   {challenge,code}
 *   GET  auth/status   ?challenge=
 *   GET  auth/session  ?challenge=
 *   POST auth/resend   {challenge}
 *   POST auth/signout  {challenge}
 *   GET  account/refresh?token=   the profile + usage from the panel
 *   POST filter/get    {token}
 *   POST filter/save   {token,settings}
 *   GET  app/notifications?token=
 *   POST auth/device    {token}     keeps the device row fresh
 *   GET  app/ping
 */
final class AppGateway {
private const JSON_FLAGS = JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE;
private const FREE_PLAN_GB = 3;
private const FREE_PLAN_DAYS = 1;
private function __construct() {
}

public static function handle(string $Path): void {
header('Content-Type: application/json; charset=UTF-8');
header('Cache-Control: no-store');

try {
AppSchema::ensureInstalled();
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Gateway-Schema] ' . $Error->getMessage());
}

$Route = trim($Path, '/');

// A deployment whose database is unreachable answers one clear code everywhere,
// instead of per-route 500s: «db_unavailable». app/diag is exempt so it can
// report WHY the database is down.
if ($Route !== 'app/diag') {
try {
Database::getInstance()->fetch('SELECT 1 AS ok');
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Gateway] database: ' . $Error->getMessage());
self::fail(503, 'db_unavailable', 'مشکل پایگاه دادهٔ سرور؛ کمی بعد دوباره تلاش کنید.');
}
}

try {
if ($Route === 'auth/start') { self::start(self::body()); return; }
if ($Route === 'auth/verify') { self::verify(self::body()); return; }
if ($Route === 'auth/status') { self::status(); return; }
if ($Route === 'auth/cancel') { self::cancelSignIn(self::body()); return; }
if ($Route === 'auth/session') { self::session(); return; }
if ($Route === 'auth/resend') { self::resend(self::body()); return; }
if ($Route === 'auth/signout') { self::signOut(self::body()); return; }
if ($Route === 'auth/device') { self::heartbeat(self::body()); return; }
if ($Route === 'account/refresh') { self::refreshAccount(); return; }
if ($Route === 'account/bot-link') { self::botMembershipLink(self::body()); return; }
if ($Route === 'account/bot-link-status') { self::botMembershipStatus(); return; }
if ($Route === 'filter/save') { self::saveFilter(self::body()); return; }
if ($Route === 'filter/get') { self::getFilter(self::body()); return; }
if ($Route === 'bypass/save') { self::saveBypass(self::body()); return; }
if ($Route === 'subscription/offers') { self::subscriptionOffers(); return; }
if ($Route === 'subscription/claim') { self::claimSubscription(self::body()); return; }
if ($Route === 'subscription/fetch') { self::fetchSubscription(self::body()); return; }
if ($Route === 'subscription/plans') { self::subscriptionPlans(); return; }
if ($Route === 'subscription/purchase') { self::purchaseSubscription(self::body()); return; }
if ($Route === 'wallet/status') { self::walletStatus(); return; }
if ($Route === 'wallet/topup') { self::walletTopup(self::body()); return; }
if ($Route === 'wallet/verify') { self::walletVerify(self::body()); return; }
if ($Route === 'wallet/cancel') { self::walletCancel(self::body()); return; }
if ($Route === 'app/notifications') { self::notifications(); return; }
if ($Route === 'app/activity') { self::recordActivityRoute(self::body()); return; }
if ($Route === 'app/support-report') { self::supportReport(self::body()); return; }
if ($Route === 'app/announcement') { self::announcement(); return; }
if ($Route === 'app/promo-image') { self::promoImage(); return; }
if ($Route === 'app/security-alert') { self::securityAlert(self::body()); return; }
if ($Route === 'app/ping') { self::ping(); return; }
if ($Route === 'app/diag') { self::diag(); return; }

self::fail(404, 'not_found', 'unknown route: ' . $Route);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Gateway] ' . $Route . ': ' . $Error->getMessage()
. ' @ ' . basename($Error->getFile()) . ':' . $Error->getLine());
self::fail(500, 'gateway_error', 'internal error');
}
}

// ── sign-in ────────────────────────────────────────────────────────────────

private static function start(array $Body): void {
$Phone = \Helper::normalizePhone((string)($Body['phone'] ?? ''));
$First = trim((string)(preg_replace('/\s+/u', ' ', \Helper::stripZwnj((string)($Body['first_name'] ?? ''))) ?? ''));
$Last = trim((string)(preg_replace('/\s+/u', ' ', \Helper::stripZwnj((string)($Body['last_name'] ?? ''))) ?? ''));
$Device_Id = self::safeDeviceId((string)($Body['device_id'] ?? ''));

if (!\Helper::validatePhone($Phone)) {
self::fail(422, 'invalid_phone', 'شماره موبایل معتبر نیست.');
}

if ($Device_Id === '') {
self::fail(422, 'invalid_device', 'شناسه دستگاه ارسال نشد.');
}

// One trusted device per account by default — the admin raises it per user
// from the bot's «📱مجوز دستگاه کاربران» panel. Checked before any SMS is
// spent, and checked again at verify() (belt and braces).
$Device_Limit = AppDeviceLimit::check($Phone, $Device_Id);

if (!$Device_Limit['allowed']) {
error_log('[Umbrella-Bot][App-Auth] device limit reached | phone-masked-' . substr(md5($Phone), 0, 8) . ' | used=' . $Device_Limit['used'] . '/limit=' . $Device_Limit['limit']);
self::notifyFailedLogin($Phone, 'device_limit', $Body);
self::fail(403, 'device_limit', 'این حساب قبلاً روی دستگاه دیگری فعال است. برای استفاده از دستگاه دوم، از بخش مدیریت ربات مجوز بگیرید.');
}

// Account creation is deferred to verify() — until the person proves they own
// the phone by answering the SMS code, we must not mint panel accounts for
// every number an attacker types in. Here we only look the number up — in
// the bot's own database first (it remembers the panel uuid it issued), then
// in the panel itself.
[$Known, $Lookup_Source] = self::findCustomerAccount($Phone);
$Exists = $Known !== null;
$List_Error = $Exists ? null : PanelClient::lastListError();

// If all local tables (Users, App_Devices, App_SignIn_Requests) have no UUID
// for this phone and the remote panel list endpoint had a temporary hiccup, do
// not lock brand-new users out at the phone screen: let them continue through
// name + SMS verification, and resolveAccount() will re-check the panel with
// retries before creating an account.
if (!$Exists && $List_Error !== null) {
error_log('[Umbrella-Bot][App-Auth] panel list unavailable during start (' . $Lookup_Source . '), proceeding with new-user flow: ' . $List_Error);
}

/*
 * ورود دو مرحله ای است: اول فقط شماره گرفته می شود. اگر این شماره حساب
 * نداشته باشد، بانک نامه بدون فرستادن پیامک پاسخ «needs_profile» می دهد و
 * برنامه سراغ مرحله «نام و نام خانوادگی» می رود؛ ثبت نام با همان شماره و
 * همین درخواست کامل می شود. شماره ای که حساب دارد، مستقیم کد می گیرد.
 */
if (!$Exists && ($First === '' || $Last === '')) {
self::ok([
'stage' => 'needs_profile',
'account_exists' => false,
]);
}

if (!$Exists && (mb_strlen($First) > 60 || mb_strlen($Last) > 60)) {
self::fail(422, 'invalid_name', 'نام یا نام خانوادگی بیش از حد طولانی است.');
}

$Cooldown_Key = 'app_otp_cooldown_' . md5($Phone);
$Last_Sent = (int)Repository::getSetting($Cooldown_Key, 0);
$Cooldown = Environment::getOtpCooldown();

if ($Last_Sent > 0 && time() - $Last_Sent < $Cooldown) {
self::fail(429, 'rate_limited', 'کمی بعد دوباره تلاش کنید.', [
'retry_after' => $Cooldown - (time() - $Last_Sent),
]);
}

// A global ceiling on SMS spend: without it, the (cheap) per-number cooldown
// is the only limit, so one attacker can drain the IPPanel credit by using
// many numbers. Checked before anything is written.
if (self::otpGlobalCapReached()) {
error_log('[Umbrella-Bot][Gateway] global hourly OTP cap (' . Environment::getAppOtpMaxHourly() . ') reached');
self::fail(429, 'service_busy', 'سرویس ورود موقتاً شلوغ است؛ کمی بعد دوباره تلاش کنید.');
}
$Full_Name = trim($First . ' ' . $Last);

if ($Exists) {
// For a returning customer the panel's name wins over the (empty) form field.
if ($Full_Name === '') {
$Full_Name = self::resolveBestUserName(
trim((string)($Known['name'] ?? $Known['Name'] ?? '')),
$Phone,
(string)($Known['uuid'] ?? ''),
$Device_Id,
(int)($Known['telegram_id'] ?? 0)
);
}

$UUID = trim((string)($Known['uuid'] ?? ''));
// The bot needs somebody to ask for confirmation, so the panel account is
// tied to a Telegram id as soon as one is known.
$Telegram_Id = (int)($Known['telegram_id'] ?? 0);

if ($Telegram_Id <= 0) {
$Linked = Repository::findUserByPhone($Phone);
$Telegram_Id = (int)($Linked['Telegram_ID'] ?? 0);

if ($Telegram_Id > 0 && $UUID !== '') {
try { PanelClient::update($UUID, ['telegram_id' => $Telegram_Id]); }
catch (Throwable $Error) { error_log('[Umbrella-Bot][Gateway] telegram link failed: ' . $Error->getMessage()); }
}
}
}
else {
$UUID = '';
$Telegram_Id = (int)(Repository::findUserByPhone($Phone)['Telegram_ID'] ?? 0);
}

$Challenge = bin2hex(random_bytes(16));
$Code = (string)random_int(100000, 999999);
$Now = time();
$Ttl = Environment::getSignInTtl();

Database::getInstance()->execute(
'INSERT INTO `App_SignIn_Requests`
(`Challenge`, `Device_ID`, `Device_Name`, `Platform`, `App_Version`, `IP`, `Phone`, `Full_Name`,
`User_UUID`, `Telegram_ID`, `Otp_Hash`, `Otp_Sent_At`, `Stage`, `Expires_At`)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
[
$Challenge,
$Device_Id,
mb_substr((string)($Body['device_name'] ?? ''), 0, 190),
mb_substr((string)($Body['platform'] ?? ''), 0, 190),
mb_substr((string)($Body['app_version'] ?? ''), 0, 40),
self::clientIp(),
$Phone,
$Full_Name,
$UUID,
$Telegram_Id,
hash_hmac('sha256', $Code, self::secret()),
$Now,
'code_sent',
$Now + $Ttl,
]
);

// The code is the only thing that has to arrive; a failure is reported plainly
// so the user is not left waiting for an SMS that never left.
if (!IppanelClient::sendPattern($Phone, $Code)) {
Database::getInstance()->execute(
'UPDATE `App_SignIn_Requests` SET `Stage` = ? WHERE `Challenge` = ?',
['sms_failed', $Challenge]
);
self::fail(503, 'sms_failed', 'ارسال پیامک ناموفق بود؛ دوباره تلاش کنید.');
}

self::otpGlobalCapIncrement();
Repository::setSetting($Cooldown_Key, (string)$Now);
self::trackDevice($Device_Id, $Body, $Phone, self::isMeaningfulName($Full_Name) ? $Full_Name : '');

self::ok([
'challenge' => $Challenge,
'stage' => 'code_sent',
'account_exists' => $Exists,
'expires_at' => gmdate('c', $Now + $Ttl),
'resend_after' => $Cooldown,
]);
}

private static function verify(array $Body): void {
$Challenge = preg_replace('/[^a-f0-9]/', '', (string)($Body['challenge'] ?? '')) ?? '';
$Code = \Helper::toEnglish(trim((string)($Body['code'] ?? '')));
$Row = self::request($Challenge);

if ($Row === null) {
self::fail(404, 'unknown_challenge', 'این درخواست ورود پیدا نشد.');
}

if ((int)$Row['Expires_At'] < time()) {
self::fail(410, 'expired', 'زمان تأیید به پایان رسید.');
}

if ((string)$Row['Stage'] !== 'code_sent') {
self::fail(409, 'wrong_stage', 'این کد قبلاً استفاده شده است.');
}

if ((int)$Row['Otp_Attempts'] >= 5) {
self::notifyFailedLogin((string)$Row['Phone'], 'too_many_attempts', $Row, (int)$Row['Telegram_ID']);
self::fail(429, 'too_many_attempts', 'تعداد تلاش ها زیاد شد؛ کد جدید بگیرید.');
}

$Device_Limit = AppDeviceLimit::check((string)$Row['Phone'], (string)$Row['Device_ID']);

if (!$Device_Limit['allowed']) {
error_log('[Umbrella-Bot][App-Auth] device limit reached at verify | used=' . $Device_Limit['used'] . '/limit=' . $Device_Limit['limit']);
self::notifyFailedLogin((string)$Row['Phone'], 'device_limit', $Row, (int)$Row['Telegram_ID']);
self::fail(403, 'device_limit', 'این حساب قبلاً روی دستگاه دیگری فعال است. برای استفاده از دستگاه دوم، از بخش مدیریت ربات مجوز بگیرید.');
}

if (!hash_equals((string)$Row['Otp_Hash'], hash_hmac('sha256', $Code, self::secret()))) {
$Attempts = (int)$Row['Otp_Attempts'] + 1;
Database::getInstance()->execute(
'UPDATE `App_SignIn_Requests` SET `Otp_Attempts` = `Otp_Attempts` + 1 WHERE `Challenge` = ?',
[$Challenge]
);
// One typo is normal, three in a row is worth telling the owner about.
if ($Attempts >= 3) {
self::notifyFailedLogin((string)$Row['Phone'], 'code_invalid', $Row, (int)$Row['Telegram_ID']);
}
self::fail(409, 'code_invalid', 'کد وارد شده درست نیست.');
}

$Phone = (string)$Row['Phone'];
$UUID = trim((string)($Row['User_UUID'] ?? ''));
$Telegram_Id = (int)$Row['Telegram_ID'];

// The panel account for a brand-new number was intentionally not created at
// start() — only now, after the code has proven the phone, do we mint it.
// If the panel is down the stage stays code_sent, so the person can retry
// with the same code until it expires.
if ($UUID === '') {
$Linked_Telegram = (int)($Row['Telegram_ID'] ?? 0);
if ($Linked_Telegram <= 0) {
$Linked_Telegram = (int)(Repository::findUserByPhone($Phone)['Telegram_ID'] ?? 0);
}
$Device_Meta = [
'device_id' => trim((string)($Row['Device_ID'] ?? '')),
'device_name' => trim((string)($Row['Device_Name'] ?? '')),
'platform' => trim((string)($Row['Platform'] ?? '')),
'app_version' => trim((string)($Row['App_Version'] ?? '')),
'ip' => trim((string)($Row['IP'] ?? self::clientIp())),
];
$Account = self::resolveAccount($Phone, trim((string)($Row['Full_Name'] ?? '')), $Linked_Telegram, $Device_Meta);
$UUID = trim((string)($Account['uuid'] ?? ''));

if ($UUID === '') {
error_log('[Umbrella-Bot][App-Auth] verify: panel account creation failed for challenge ' . $Challenge);
self::fail(502, 'panel_unavailable', 'ساخت حساب در پنل ناموفق بود؛ کمی بعد دوباره تلاش کنید.');
}

$Telegram_Id = (int)($Account['telegram_id'] ?? 0);

if ($Telegram_Id <= 0) {
$Telegram_Id = (int)(Repository::findUserByPhone($Phone)['Telegram_ID'] ?? 0);

if ($Telegram_Id > 0) {
try { PanelClient::update($UUID, ['telegram_id' => $Telegram_Id]); }
catch (Throwable $Error) { error_log('[Umbrella-Bot][Gateway] telegram link failed: ' . $Error->getMessage()); }
}
}

Database::getInstance()->execute(
'UPDATE `App_SignIn_Requests` SET `User_UUID` = ?, `Telegram_ID` = ? WHERE `Challenge` = ?',
[$UUID, $Telegram_Id, $Challenge]
);
$Row['User_UUID'] = $UUID;
$Row['Telegram_ID'] = $Telegram_Id;
}

$Resolved_Name = self::resolveBestUserName(
trim((string)($Row['Full_Name'] ?? '')),
$Phone,
$UUID,
(string)($Row['Device_ID'] ?? ''),
$Telegram_Id
);
if ($Resolved_Name !== '') {
$Row['Full_Name'] = $Resolved_Name;
try {
Database::getInstance()->execute(
'UPDATE `App_SignIn_Requests` SET `Full_Name` = COALESCE(NULLIF(TRIM(`Full_Name`), \'\'), ?) WHERE `Challenge` = ?',
[$Resolved_Name, $Challenge]
);
} catch (Throwable) {}
}
self::touchDeviceSeen((string)($Row['Device_ID'] ?? ''), $UUID, $Telegram_Id, $Resolved_Name);
if ($Telegram_Id > 0 && $Resolved_Name !== '') {
try {
Database::getInstance()->execute(
"UPDATE `Users` SET `Full_Name` = CASE WHEN `Full_Name` IS NULL OR `Full_Name` = '' THEN ? ELSE `Full_Name` END, `Phone` = CASE WHEN `Phone` IS NULL OR `Phone` = '' THEN ? ELSE `Phone` END WHERE `Telegram_ID` = ?",
[$Resolved_Name, $Phone, $Telegram_Id]
);
} catch (Throwable) {}
}

// If no Telegram account exists, phone ownership has already been verified by
// SMS. Confirm against the live panel and bot DB before allowing SMS-only
// sign-in; linked accounts still use their existing Telegram two-step policy.
if ($Telegram_Id <= 0) {
$LiveAccount = PanelClient::get($UUID);
if (!$LiveAccount) self::fail(502, 'panel_unavailable', 'برای بررسی اتصال تلگرام، پنل در دسترس نیست؛ دوباره تلاش کنید.');
$BotUser = self::resolveBotUser($UUID, 0);
$Telegram_Id = (int)($LiveAccount['telegram_id'] ?? 0);
if ($Telegram_Id <= 0) $Telegram_Id = (int)($BotUser['Telegram_ID'] ?? 0);
if ($Telegram_Id <= 0) $Telegram_Id = (int)(Repository::findUserByPhone($Phone)['Telegram_ID'] ?? 0);
if ($Telegram_Id > 0) {
Database::getInstance()->execute('UPDATE `App_SignIn_Requests` SET `Telegram_ID` = ? WHERE `Challenge` = ? AND `Stage` = ?', [$Telegram_Id, $Challenge, 'code_sent']);
$Row['Telegram_ID'] = $Telegram_Id;
} else {
if (!self::decide($Challenge, true, 0)) self::fail(503, 'sign_in_failed', 'تأیید دستگاه انجام نشد؛ دوباره تلاش کنید.');
self::ok([
'verified' => true, 'challenge' => $Challenge, 'stage' => 'approved',
'expires_at' => gmdate('c', (int)$Row['Expires_At']),
'message' => 'ورود با تأیید پیامک انجام شد؛ اتصال ربات را از حساب من تکمیل کنید.',
]);
}
}

// With two-step switched off in the bot the SMS code is the only factor: the
// device is trusted right away and Telegram gets a notice afterwards instead
// of a question, so the app never sits on the waiting screen.
// When the flip fails the request simply falls through to the question below,
// so a bookkeeping problem can never turn into «cannot sign in».
if (!AppTwoStep::enabled($Telegram_Id) && self::decide($Challenge, true, $Telegram_Id)) {
try {
$Buttons = [
[['text' => '📱منوی دستگاه', 'callback_data' => 'user_device_menu']],
[['text' => '📱دستگاه های من', 'callback_data' => 'app_devices']],
];
if (!method_exists('AppTwoStep', 'globalEnabled') || AppTwoStep::globalEnabled()) {
$Buttons[] = [['text' => '🔐تأیید دومرحله ای', 'callback_data' => 'app_2fa']];
}
TelegramClient::sendSystemMessage($Telegram_Id, self::signedInMessage($Row), TelegramClient::inlineKeyboard($Buttons));
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Gateway] signed-in notice failed for ' . $Challenge . ': ' . $Error->getMessage());
}

self::ok([
'verified' => true,
'challenge' => $Challenge,
'stage' => 'approved',
'expires_at' => gmdate('c', (int)$Row['Expires_At']),
'message' => 'ورود انجام شد.',
]);
}

if (!self::sendConfirmation($Row, $Telegram_Id, 'code_sent')) {
self::fail(503, 'telegram_failed', 'ارسال پیام تأیید در تلگرام ناموفق بود.');
}

self::ok([
'verified' => true,
'challenge' => $Challenge,
'stage' => 'awaiting_telegram',
'expires_at' => gmdate('c', (int)$Row['Expires_At']),
'message' => 'جزئیات ورود به تلگرام شما ارسال شد.',
]);
}

/* The random challenge is the sign-in capability. Cancel only a pending
 * request; the conditional update races atomically with Telegram approval. */
private static function cancelSignIn(array $Body): void {
$Challenge = (string)($Body['challenge'] ?? '');
if (preg_match('/^[a-f0-9]{32}$/D', $Challenge) !== 1) self::fail(422, 'invalid_challenge', 'درخواست ورود معتبر نیست.');
$Changed = Database::getInstance()->execute(
'UPDATE `App_SignIn_Requests` SET `Stage` = ?, `Decided_At` = ? WHERE `Challenge` = ? AND `Stage` IN (?, ?)',
['cancelled', time(), $Challenge, 'needs_telegram', 'awaiting_telegram']
)->rowCount();
if ($Changed === 0) {
$Row = self::request($Challenge);
if ($Row === null) self::fail(404, 'unknown_challenge', 'درخواست ورود پیدا نشد.');
if ((string)$Row['Stage'] !== 'cancelled') self::fail(409, 'already_decided', 'این درخواست قبلاً تعیین تکلیف شده است؛ وضعیت ورود را بررسی کنید.');
}
self::ok(['stage' => 'cancelled']);
}

private static function status(): void {
$Row = self::requestFromQuery();

if ($Row === null) {
self::fail(404, 'unknown_challenge', 'این درخواست ورود پیدا نشد.');
}

$Stage = (string)$Row['Stage'];

if ((int)$Row['Expires_At'] < time() && in_array($Stage, ['code_sent', 'awaiting_telegram'], true)) {
$Stage = 'expired';
}

// Late link: the number had no Telegram id at verify time; if it has been
// linked since (e.g. the person completed the bot's profile step), promote
// the request on this poll and send the confirmation then.
if ($Stage === 'needs_telegram' && (int)$Row['Expires_At'] >= time()) {
$Linked = (int)(Repository::findUserByPhone((string)$Row['Phone'])['Telegram_ID'] ?? 0);

if ($Linked > 0) {
$Claimed = Database::getInstance()->execute(
'UPDATE `App_SignIn_Requests` SET `Stage` = ?, `Telegram_ID` = ? WHERE `Challenge` = ? AND `Stage` = ?',
['awaiting_telegram', $Linked, (string)$Row['Challenge'], 'needs_telegram']
)->rowCount();

if ($Claimed > 0) {
$Row['Telegram_ID'] = $Linked;
$Linked_UUID = trim((string)($Row['User_UUID'] ?? ''));

if ($Linked_UUID !== '') {
try { PanelClient::update($Linked_UUID, ['telegram_id' => $Linked]); } catch (Throwable) {}
self::syncBotUserClientId($Linked, $Linked_UUID);
}

if (self::sendConfirmation($Row, $Linked, 'needs_telegram')) {
$Stage = 'awaiting_telegram';
}
}
}
}

self::ok([
'challenge' => (string)$Row['Challenge'],
'stage' => $Stage,
'device_name' => (string)($Row['Device_Name'] ?? ''),
'ip' => (string)($Row['IP'] ?? ''),
'expires_at' => gmdate('c', (int)$Row['Expires_At']),
'seconds_left' => max(0, (int)$Row['Expires_At'] - time()),
]);
}

private static function session(): void {
$Row = self::requestFromQuery();

if ($Row === null) {
self::fail(404, 'unknown_challenge', 'این درخواست ورود پیدا نشد.');
}

if ((string)$Row['Stage'] !== 'approved') {
self::fail(409, 'not_approved', 'این ورود هنوز تأیید نشده است.');
}

$UUID = trim((string)($Row['User_UUID'] ?? ''));

if ($UUID === '' || $UUID === '_') {
self::fail(409, 'no_account', 'حسابی به این شماره وصل نیست.');
}

$Account = PanelClient::get($UUID);

if ($Account === null || $Account === []) {
if (PanelClient::lastGetStatus() === 404) {
AppAccountRevocation::revoke($UUID);
self::fail(403, 'device_revoked', 'حساب پنلی این نشست حذف شده است؛ اتصال فیلترشکن قطع و نشست برنامه بسته می شود.');
}
error_log('[Umbrella-Bot][Gateway] session profile unavailable for uuid=' . $UUID . ' status=' . PanelClient::lastGetStatus());
// Unknown panel state is never an active account. Do not issue or reuse a
// session token until a real account record has been read successfully.
self::fail(502, 'panel_unavailable', 'بررسی حساب در پنل انجام نشد؛ کمی بعد دوباره تلاش کنید.');
}

$Token = (string)($Row['Token'] ?? '');

if ($Token === '') {
$Token = self::issueToken($Row);
Database::getInstance()->execute(
'UPDATE `App_SignIn_Requests` SET `Token` = ? WHERE `Challenge` = ?',
[$Token, (string)$Row['Challenge']]
);
}

$LinkedTg = self::syncLinkedBotUserFromPanel($UUID, (int)($Row['Telegram_ID'] ?? 0), $Account);
$Profile = self::accountPayloadWithExtras($Account, $UUID, $LinkedTg);
$ResolvedName = self::resolveBestUserName(
trim((string)($Profile['name'] ?? ($Row['Full_Name'] ?? ''))),
trim((string)($Profile['phone'] ?? ($Row['Phone'] ?? ''))),
$UUID,
(string)$Row['Device_ID'],
$LinkedTg
);
self::touchDeviceSeen((string)$Row['Device_ID'], $UUID, $LinkedTg, $ResolvedName);
if ($ResolvedName !== '' && (!isset($Profile['name']) || !self::isMeaningfulName((string)$Profile['name']))) {
$Profile['name'] = $ResolvedName;
}

self::ok([
'uuid' => $UUID,
'token' => $Token,
'device_id' => (string)$Row['Device_ID'],
'sign_in_at' => gmdate('c'),
'account' => $Profile,
'filter' => self::filterPayload($UUID),
'offers' => self::offersPayload($UUID, $LinkedTg, $Account),
'announcement' => self::announcementPayload(),
'promo_announcement' => self::promoAnnouncementPayload(),
]);
}

private static function resend(array $Body): void {
$Challenge = preg_replace('/[^a-f0-9]/', '', (string)($Body['challenge'] ?? '')) ?? '';
$Row = self::request($Challenge);

if ($Row === null) {
self::fail(404, 'unknown_challenge', 'این درخواست ورود پیدا نشد.');
}

// Only a challenge still waiting for its code may be resent — never one that
// has already been decided (this used to regress an approved device back to
// code_sent, stranding the app).
$Stage = (string)$Row['Stage'];

if (!in_array($Stage, ['code_sent', 'sms_failed'], true)) {
self::fail(409, 'wrong_stage', 'این درخواست قبلاً تأیید شده است.');
}

if (self::otpGlobalCapReached()) {
error_log('[Umbrella-Bot][Gateway] global hourly OTP cap (' . Environment::getAppOtpMaxHourly() . ') reached');
self::fail(429, 'service_busy', 'سرویس ورود موقتاً شلوغ است؛ کمی بعد دوباره تلاش کنید.');
}

$Cooldown_Key = 'app_otp_cooldown_' . md5((string)$Row['Phone']);
$Last_Sent = (int)Repository::getSetting($Cooldown_Key, 0);
$Cooldown = Environment::getOtpCooldown();

if ($Last_Sent > 0 && time() - $Last_Sent < $Cooldown) {
self::fail(429, 'rate_limited', 'کمی بعد دوباره تلاش کنید.', [
'retry_after' => $Cooldown - (time() - $Last_Sent),
]);
}

$Code = (string)random_int(100000, 999999);
$Now = time();

Database::getInstance()->execute(
'UPDATE `App_SignIn_Requests`
SET `Otp_Hash` = ?, `Otp_Sent_At` = ?, `Otp_Attempts` = 0, `Stage` = ?, `Expires_At` = ?
WHERE `Challenge` = ?',
[hash_hmac('sha256', $Code, self::secret()), $Now, 'code_sent', $Now + Environment::getSignInTtl(), $Challenge]
);

if (!IppanelClient::sendPattern((string)$Row['Phone'], $Code)) {
self::fail(503, 'sms_failed', 'ارسال پیامک ناموفق بود.');
}

self::otpGlobalCapIncrement();
Repository::setSetting($Cooldown_Key, (string)$Now);
self::ok(['challenge' => $Challenge, 'stage' => 'code_sent']);
}

private static function signOut(array $Body): void {
$Token = trim((string)($Body['token'] ?? ''));
$Challenge = preg_replace('/[^a-f0-9]/', '', (string)($Body['challenge'] ?? '')) ?? '';
$Database = Database::getInstance();
$Now = self::tehranNow();
$Device_Ids = [];

if ($Token !== '') {
$Token_Hash = hash('sha256', $Token);
$Session_Row = $Database->fetch(
'SELECT `Device_ID` FROM `App_Sessions` WHERE `Token_Hash` = ? LIMIT 1',
[$Token_Hash]
);
$Session_Device = is_array($Session_Row) ? trim((string)($Session_Row['Device_ID'] ?? '')) : '';
if ($Session_Device !== '') {
$Device_Ids[] = $Session_Device;
}
$Database->execute(
'UPDATE `App_Sessions` SET `Revoked_At` = ? WHERE `Token_Hash` = ? AND `Revoked_At` IS NULL',
[$Now, $Token_Hash]
);
}

if ($Challenge !== '') {
$Request_Row = $Database->fetch(
'SELECT `Device_ID` FROM `App_SignIn_Requests` WHERE `Challenge` = ? LIMIT 1',
[$Challenge]
);
$Request_Device = is_array($Request_Row) ? trim((string)($Request_Row['Device_ID'] ?? '')) : '';
if ($Request_Device !== '') {
$Device_Ids[] = $Request_Device;
}
if ($Device_Ids === []) {
$Database->execute(
'UPDATE `App_Devices` SET `Is_Trusted` = 0
WHERE `Device_ID` = (SELECT `Device_ID` FROM `App_SignIn_Requests` WHERE `Challenge` = ? LIMIT 1)',
[$Challenge]
);
}
}

foreach (array_values(array_unique($Device_Ids)) as $Device_Id) {
$Database->execute(
'UPDATE `App_Devices` SET `Is_Trusted` = 0 WHERE `Device_ID` = ?',
[$Device_Id]
);
$Database->execute(
'UPDATE `App_Sessions` SET `Revoked_At` = ? WHERE `Device_ID` = ? AND `Revoked_At` IS NULL',
[$Now, $Device_Id]
);
}

self::ok([]);
}

/**
 * Writes the answer from the bot's buttons. A callback can be pressed from a
 * different device, so the decision is stored on the challenge row and the app
 * picks it up on its next poll.
 */
public static function decide(string $Challenge, bool $Approved, int $Telegram_Id): bool {
$Row = self::request($Challenge);

if ($Row === null) return false;

$Stage = (string)$Row['Stage'];

if ($Stage === 'approved' || $Stage === 'denied') {
return $Approved === ($Stage === 'approved');
}

// A different Telegram account may not answer a challenge it was not shown
// to; this is what stops a leaked button from approving a sign-in.
if ((int)$Row['Telegram_ID'] !== $Telegram_Id) {
error_log('[Umbrella-Bot][Gateway] decision from unexpected telegram id for ' . $Challenge . ': expected=' . (int)$Row['Telegram_ID'] . ' got=' . $Telegram_Id);
return false;
}

$Next = $Approved ? 'approved' : 'denied';
$Token = '';

// The client polls Stage. Commit device trust and the approved stage together,
// so a fast poll can never obtain a session while Is_Trusted is still false.
try {
$Committed = Database::getInstance()->transaction(static function (Database $Database) use ($Approved, $Next, $Row, $Challenge, $Telegram_Id, &$Token): bool {
$Current = $Database->fetch(
'SELECT `Stage`, `Telegram_ID`, `Expires_At` FROM `App_SignIn_Requests` WHERE `Challenge` = ? FOR UPDATE',
[$Challenge]
);
if ($Current === null ||
    (int)$Current['Telegram_ID'] !== $Telegram_Id ||
    !in_array((string)$Current['Stage'], ['code_sent', 'awaiting_telegram'], true) ||
    (int)($Current['Expires_At'] ?? 0) < time()) {
return false;
}

if ($Approved) {
$Device = $Database->fetch(
'SELECT `Device_ID` FROM `App_Devices` WHERE `Device_ID` = ? FOR UPDATE',
[(string)$Row['Device_ID']]
);
if ($Device === null) {
throw new RuntimeException('The approved sign-in device is not registered.');
}
$NowStr = self::tehranNow();
$DeviceFullName = self::isMeaningfulName((string)($Row['Full_Name'] ?? ''))
? trim((string)$Row['Full_Name'])
: '';
$Database->execute(
'UPDATE `App_Devices`
SET `Is_Trusted` = 1, `Last_Seen_At` = ?,
`Telegram_ID` = COALESCE(NULLIF(`Telegram_ID`, 0), ?),
`User_UUID` = CASE WHEN `User_UUID` IS NULL OR LENGTH(`User_UUID`) = 0 THEN ? ELSE `User_UUID` END,
`Full_Name` = CASE WHEN (`Full_Name` IS NULL OR LENGTH(TRIM(`Full_Name`)) = 0) AND ? <> \'\' THEN ? ELSE `Full_Name` END
WHERE `Device_ID` = ?',
[$NowStr, $Telegram_Id > 0 ? $Telegram_Id : null, (string)$Row['User_UUID'], $DeviceFullName, $DeviceFullName, (string)$Row['Device_ID']]
);
}

$Changed = $Database->execute(
'UPDATE `App_SignIn_Requests` SET `Stage` = ?, `Decided_At` = ? WHERE `Challenge` = ?',
[$Next, time(), $Challenge]
)->rowCount();
if ($Changed < 1) {
throw new RuntimeException('The sign-in decision could not be stored.');
}

if ($Approved) {
$Token = self::issueToken($Row);
$Database->execute(
'UPDATE `App_SignIn_Requests` SET `Token` = ? WHERE `Challenge` = ?',
[$Token, $Challenge]
);
}
return true;
});
if (!$Committed) return false;
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Gateway] decision transaction failed for ' . $Challenge . ': ' . $Error->getMessage());
return false;
}

if ($Approved) {
try {
Repository::addNotification(
$Telegram_Id,
'app_signin',
'ورود به برنامه تأیید شد',
'دستگاه: ' . (string)$Row['Device_Name']
);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Gateway] approval notification failed for ' . $Challenge . ': ' . $Error->getMessage());
}
}

return true;
}

// ── device side ────────────────────────────────────────────────────────────

private static function botMembershipStatus(): void {
$Session = self::sessionRow(self::bearer());
if ($Session === null) self::fail(401, 'invalid_token', 'نشست منقضی شده است.');
$UUID = trim((string)($Session['User_UUID'] ?? ''));
$User = ($UUID === '' || $UUID === '_')
? null
: Database::getInstance()->fetch('SELECT `Telegram_ID` FROM `Users` WHERE `Client_ID` = ? LIMIT 1', [$UUID]);
$Linked = (int)($User['Telegram_ID'] ?? 0);
if ($Linked <= 0) self::ok(['linked' => false]);
$Panel = PanelClient::get($UUID);
if (!$Panel) self::fail(502, 'panel_unavailable', 'بررسی اتصال در پنل انجام نشد؛ دوباره تلاش کنید.');
self::ok(['linked' => (int)($Panel['telegram_id'] ?? 0) === $Linked]);
}

/** Issue a one-use join link only to an authenticated, trusted device. */
private static function botMembershipLink(array $Body): void {
$Session = self::sessionRow((string)($Body['token'] ?? self::bearer()));
if ($Session === null) self::fail(401, 'invalid_token', 'نشست منقضی شده است.');
try { self::ok(AppBotLink::issue($Session)); }
catch (Throwable $Error) {
if ($Error->getMessage() === 'panel_unavailable') self::fail(502, 'panel_unavailable', 'بررسی اتصال در پنل انجام نشد؛ دوباره تلاش کنید.');
if ($Error->getMessage() === 'bot_unavailable') self::fail(503, 'bot_unavailable', 'نشانی ربات در حال حاضر در دسترس نیست.');
if ($Error->getMessage() === 'invalid_account') self::fail(409, 'invalid_account', 'حساب یا شماره تاییدشده دستگاه برای اتصال در دسترس نیست.');
throw $Error;
}
}

/**
 * The account as the panel reports it right now: expiry, usage and the share
 * link. The app asks here rather than calling the panel itself, so the
 * deployment key never has to be inside the app.
 */
private static function refreshAccount(): void {
$Session = self::sessionRow(self::bearer());

if ($Session === null) {
self::fail(401, 'invalid_token', 'نشست منقضی شده است.');
}

$UUID = trim((string)$Session['User_UUID']);

if ($UUID === '' || $UUID === '_') {
self::fail(409, 'no_account', 'حسابی به این نشست وصل نیست.');
}

$Account = PanelClient::get($UUID);

if ($Account === null || $Account === []) {
if (PanelClient::lastGetStatus() === 404) {
AppAccountRevocation::revoke($UUID);
self::fail(403, 'device_revoked', 'حساب پنلی این نشست حذف شده است؛ اتصال فیلترشکن قطع و نشست برنامه بسته می شود.');
}
self::fail(502, 'panel_unavailable', 'دریافت اطلاعات حساب ناموفق بود.');
}

$LinkedTg = self::autoLinkTelegramOwner(
(string)$Session['Device_ID'],
$UUID,
(int)($Session['Telegram_ID'] ?? 0)
);
$LinkedTg = self::syncLinkedBotUserFromPanel($UUID, $LinkedTg, $Account);
$ChannelState = self::syncChannelState($LinkedTg, $UUID, $Account);
$Profile = self::accountPayloadWithExtras($Account, $UUID, $LinkedTg, $ChannelState);
self::touchDeviceSeen((string)$Session['Device_ID'], $UUID, $LinkedTg, trim((string)($Profile['name'] ?? '')), (string)($Session['Token_Hash'] ?? ''));

self::ok([
'account' => $Profile,
'filter' => self::filterPayload($UUID),
'offers' => self::offersPayload($UUID, $LinkedTg, $Account),
'channel_url' => BotConfig::getChannelUrl(),
'announcement' => self::announcementPayload(),
'promo_announcement' => self::promoAnnouncementPayload(),
'checked_at' => gmdate('c'),
]);
}

/**
 * Keeps the device row fresh, automatically links Telegram ownership when the
 * same UUID exists in `Users`, and delivers live filter + subscription offer
 * toggles so everything stays synchronized with zero manual sync controls.
 */
private static function heartbeat(array $Body): void {
$Session = self::sessionRow((string)($Body['token'] ?? self::bearer()));

if ($Session === null) {
self::fail(401, 'invalid_token', 'نشست منقضی شده است.');
}

$DeviceId = (string)$Session['Device_ID'];
$UUID = trim((string)($Session['User_UUID'] ?? ''));
$PanelAccount = null;
if ($UUID !== '' && $UUID !== '_') {
$PanelAccount = PanelClient::get($UUID);
if (($PanelAccount === null || $PanelAccount === []) && PanelClient::lastGetStatus() === 404) {
AppAccountRevocation::revoke($UUID);
self::fail(403, 'device_revoked', 'حساب پنلی این نشست حذف شده است؛ اتصال فیلترشکن قطع و نشست برنامه بسته می شود.');
}
if ($PanelAccount === null || $PanelAccount === []) {
self::fail(502, 'panel_unavailable', 'بررسی حساب پنل ناموفق بود؛ اتصال اینترنت را بررسی و دوباره تلاش کنید.');
}
}
$DeviceName = trim((string)($Body['device_name'] ?? ''));
$Platform = trim((string)($Body['platform'] ?? ''));
$AppVersion = trim((string)($Body['app_version'] ?? ''));
$ClientIp = self::clientIp();
$NowStr = self::tehranNow();
$PanelFullName = is_array($PanelAccount) ? trim((string)($PanelAccount['name'] ?? '')) : '';
if (!self::isMeaningfulName($PanelFullName)) {
$PanelFullName = '';
}
Database::getInstance()->execute(
'UPDATE `App_Devices` SET `Last_Seen_At` = ?,
`Device_Name` = COALESCE(NULLIF(?, \'\'), `Device_Name`),
`Full_Name` = CASE WHEN (`Full_Name` IS NULL OR LENGTH(TRIM(`Full_Name`)) = 0) AND ? <> \'\' THEN ? ELSE `Full_Name` END,
`Platform` = COALESCE(NULLIF(?, \'\'), `Platform`),
`App_Version` = COALESCE(NULLIF(?, \'\'), `App_Version`),
`Last_IP` = COALESCE(NULLIF(?, \'\'), `Last_IP`)
WHERE `Device_ID` = ?',
[$NowStr, substr($DeviceName, 0, 120), $PanelFullName, $PanelFullName, substr($Platform, 0, 60), substr($AppVersion, 0, 32), substr($ClientIp, 0, 64), $DeviceId]
);
try {
$TokenHash = trim((string)($Session['Token_Hash'] ?? ''));
if ($TokenHash !== '') {
Database::getInstance()->execute('UPDATE `App_Sessions` SET `Last_Used_At` = ? WHERE `Token_Hash` = ?', [$NowStr, $TokenHash]);
}
} catch (Throwable) {}

$Payload = [
'seen_at' => gmdate('c'),
'emergency_enabled' => BotConfig::showEmergency(),
'channel_url' => BotConfig::getChannelUrl(),
'announcement' => self::announcementPayload(),
'promo_announcement' => self::promoAnnouncementPayload(),
];
$LinkedTg = (int)($Session['Telegram_ID'] ?? 0);
if ($UUID !== '' && $UUID !== '_') {
$LinkedTg = self::autoLinkTelegramOwner(
$DeviceId,
$UUID,
$LinkedTg
);
$LinkedTg = self::syncLinkedBotUserFromPanel($UUID, $LinkedTg, $PanelAccount);
$ChannelState = self::syncChannelState($LinkedTg, $UUID, $PanelAccount);
$Payload['account'] = self::accountPayloadWithExtras($PanelAccount, $UUID, $LinkedTg, $ChannelState);
$Payload['bot_linked'] = $LinkedTg > 0 && (int)($PanelAccount['telegram_id'] ?? 0) === $LinkedTg;
$Payload['filter'] = self::filterPayload($UUID);
$Payload['offers'] = self::offersPayload($UUID, $LinkedTg, $PanelAccount);
}
if (isset($Body['activity'])) {
$Payload['activity_stored'] = self::storeActivity($DeviceId, $UUID, $LinkedTg, $Body);
}
self::storeSecurityDeviceState($DeviceId, $Body);
self::ok($Payload);
}

/** Automatically links a device row to its Telegram owner when unlinked. */
private static function autoLinkTelegramOwner(string $DeviceId, string $UUID, int $TelegramId): int {
if ($TelegramId > 0) {
return $TelegramId;
}
if ($UUID === '' || $UUID === '_') {
return 0;
}
$User = self::resolveBotUser($UUID, 0);
$Found = (int)($User['Telegram_ID'] ?? 0);
if ($Found > 0 && $DeviceId !== '') {
try {
Database::getInstance()->execute(
'UPDATE `App_Devices` SET `Telegram_ID` = ? WHERE `Device_ID` = ? AND (`Telegram_ID` IS NULL OR `Telegram_ID` = 0)',
[$Found, $DeviceId]
);
} catch (Throwable) {}
}
return $Found;
}

private static function administratorTelegramIds(): array {
$Ids = [];
$Env_Admin = (int)Environment::getAdminUserId();
if ($Env_Admin > 0) $Ids[] = $Env_Admin;
try {
$Configured = (int)Repository::getSetting('Administrator', (string)$Env_Admin);
if ($Configured > 0) $Ids[] = $Configured;
} catch (Throwable) {}
return array_values(array_unique($Ids));
}

private static function administratorClientUuids(array $Admin_Ids): array {
$Uuids = [];
foreach ($Admin_Ids as $Id) {
$User = Repository::getUser((int)$Id);
$Uuid = trim((string)($User['Client_ID'] ?? ''));
if ($Uuid !== '' && $Uuid !== '_') $Uuids[] = $Uuid;
}
return array_values(array_unique($Uuids));
}

/** Also blocks already-queued notices and sessions with an unbackfilled device owner. */
private static function isAdministratorSession(array $Session): bool {
$Admin_Ids = self::administratorTelegramIds();
$Session_Telegram = (int)($Session['Telegram_ID'] ?? 0);
if ($Session_Telegram > 0 && in_array($Session_Telegram, $Admin_Ids, true)) return true;
$Admin_Uuids = self::administratorClientUuids($Admin_Ids);
$Uuid = trim((string)($Session['User_UUID'] ?? ''));
if ($Uuid !== '' && in_array($Uuid, $Admin_Uuids, true)) return true;

$Device = Database::getInstance()->fetch(
'SELECT `Telegram_ID`, `User_UUID` FROM `App_Devices` WHERE `Device_ID` = ? LIMIT 1',
[(string)($Session['Device_ID'] ?? '')]
);
if ($Device !== null) {
$Device_Telegram = (int)($Device['Telegram_ID'] ?? 0);
$Device_Uuid = trim((string)($Device['User_UUID'] ?? ''));
if (($Device_Telegram > 0 && in_array($Device_Telegram, $Admin_Ids, true))
|| ($Device_Uuid !== '' && in_array($Device_Uuid, $Admin_Uuids, true))) return true;
}
return false;
}

private static function notifications(): void {
$Session = self::sessionRow(self::bearer());

if ($Session === null) {
self::fail(401, 'invalid_token', 'نشست منقضی شده است.');
}
// Automated system notices and broadcasts stay suppressed on administrator
// devices, while direct manual admin sends (`Level = manual`) still deliver.
$AdminOnlyManual = self::isAdministratorSession($Session);
$LevelCondition = $AdminOnlyManual ? " AND `Level` = 'manual'" : '';

$IncludeHistory = ((string)($_GET['history'] ?? '')) === '1';
$Scope = '((`Device_ID` = ? AND (`User_UUID` IS NULL OR `User_UUID` = ?)) OR (`Device_ID` IS NULL AND `User_UUID` = ?))' . $LevelCondition;
$Sql = $IncludeHistory
? 'SELECT `ID`, `Title`, `Body`, `Level`, `Sent_At`, `Delivered_At` FROM `App_Notifications`
WHERE ' . $Scope . '
ORDER BY (`Delivered_At` IS NULL) DESC, `ID` DESC LIMIT 50'
: 'SELECT `ID`, `Title`, `Body`, `Level`, `Sent_At`, `Delivered_At` FROM `App_Notifications`
WHERE `Delivered_At` IS NULL
AND ' . $Scope . '
ORDER BY `ID` ASC LIMIT 20';

$Rows = Database::getInstance()->fetchAll(
$Sql,
[(string)$Session['Device_ID'], (string)$Session['User_UUID'], (string)$Session['User_UUID']]
);

$VisibleRows = [];
foreach ($Rows as $Row) {
$WasDelivered = ($Row['Delivered_At'] ?? null) !== null;
if (!$WasDelivered) {
Database::getInstance()->execute(
'UPDATE `App_Notifications` SET `Delivered_At` = ? WHERE `ID` = ?',
[time(), (int)$Row['ID']]
);
}
$Notice = (string)$Row['Title'] . "\n" . (string)($Row['Body'] ?? '');
// The current session is trusted; a queued revoke warning is stale after re-approval.
if (str_contains($Notice, 'مجوز این دستگاه لغو شد') ||
    str_contains($Notice, 'دسترسی این دستگاه به نرم افزار آمبرلا لغو شد')) {
continue;
}
$Row['_delivered'] = $WasDelivered;
$VisibleRows[] = $Row;
}

self::ok([
'items' => array_map(static function (array $Row): array {
$Formatted = SystemNotifications::formatForWindowsApp(
(string)$Row['Title'],
(string)($Row['Body'] ?? ''),
(string)$Row['Level']
);
return [
'id' => (int)$Row['ID'],
'title' => $Formatted['title'],
'body' => $Formatted['body'],
'level' => $Formatted['level'],
'sent_at' => (string)$Row['Sent_At'],
'delivered' => (bool)$Row['_delivered'],
];
}, $VisibleRows),
]);
}

private static function saveFilter(array $Body): void {
$Session = self::sessionRow((string)($Body['token'] ?? self::bearer()));

if ($Session === null) {
self::fail(401, 'invalid_token', 'نشست منقضی شده است.');
}

$Settings = $Body['settings'] ?? [];

if (!is_array($Settings)) {
self::fail(422, 'invalid_settings', 'تنظیمات ارسال نشد.');
}

$UUID = (string)$Session['User_UUID'];
AppFilter::saveFromApp($UUID, $Settings);
self::ok(['settings' => self::filterPayload($UUID)]);
}

private static function getFilter(array $Body): void {
$Session = self::sessionRow((string)($Body['token'] ?? self::bearer()));

if ($Session === null) {
self::fail(401, 'invalid_token', 'نشست منقضی شده است.');
}

self::ok(['settings' => self::filterPayload((string)$Session['User_UUID'])]);
}

private static function filterPayload(string $UUID): array {
$filter = AppFilter::loadEffective($UUID);
$filter['bypass'] = AppBypass::load($UUID);
return $filter;
}

private static function saveBypass(array $Body): void {
$Session = self::sessionRow((string)($Body['token'] ?? self::bearer()));
if ($Session === null) self::fail(401, 'invalid_token', 'نشست منقضی شده است.');
$settings = $Body['settings'] ?? null;
if (!is_array($settings)) self::fail(422, 'invalid_settings', 'تنظیمات ارسال نشد.');
$UUID = (string)$Session['User_UUID'];
AppBypass::save($UUID, $settings);
self::ok(['settings' => self::filterPayload($UUID)]);
}

/** Looks up the linked bot `Users` row by Telegram ID or panel UUID. */
private static function resolveBotUser(string $UUID, int $TelegramId = 0): ?array {
$Database = Database::getInstance();

if ($TelegramId > 0) {
$ByTg = $Database->fetch('SELECT * FROM `Users` WHERE `Telegram_ID` = ? LIMIT 1', [$TelegramId]);
if ($ByTg !== null) return $ByTg;
}

if ($UUID !== '' && $UUID !== '_') {
$ByUuid = $Database->fetch('SELECT * FROM `Users` WHERE `Client_ID` = ? LIMIT 1', [$UUID]);
if ($ByUuid !== null) return $ByUuid;
}

return null;
}

private static function syncChannelState(int $LinkedTg, string $UUID, ?array &$Account): ?array {
if ($LinkedTg <= 0 || !class_exists('ChannelMembership') || !method_exists('ChannelMembership', 'syncForApp')) {
return null;
}
try {
$State = ChannelMembership::syncForApp($LinkedTg, 30);
if (!empty($State['changed']) && $UUID !== '' && $UUID !== '_') {
$Fresh = PanelClient::get($UUID);
if (is_array($Fresh) && $Fresh !== []) {
$Account = $Fresh;
}
}
return $State;
} catch (Throwable $Error) {
error_log('[Umbrella-Bot][App-Gateway][Channel] ' . $Error->getMessage());
return null;
}
}

private static function accountPayloadWithExtras(array $Account, string $UUID, int $LinkedTg = 0, ?array $ChannelState = null): array {
$Profile = AppFilter::accountPayload($Account);
if (trim((string)($Profile['telegram_id'] ?? '')) === '' && $LinkedTg > 0) {
$Profile['telegram_id'] = (string)$LinkedTg;
}
$BotUser = self::resolveBotUser($UUID, $LinkedTg);
if ($BotUser !== null) {
$RawName = trim((string)($Profile['name'] ?? ''));
$BotName = trim((string)($BotUser['Full_Name'] ?? ''));
if ($BotName !== '' && ($RawName === '' || $RawName === '_' || $RawName === 'کاربر' || $RawName === 'کاربر آمبرلا' || preg_match('/^user-[0-9]+$/', $RawName) === 1)) {
$Profile['name'] = $BotName;
}
if (trim((string)($Profile['phone'] ?? '')) === '' && trim((string)($BotUser['Phone'] ?? '')) !== '') {
$Profile['phone'] = trim((string)$BotUser['Phone']);
}
}
if (!self::isMeaningfulName((string)($Profile['name'] ?? ''))) {
$Best = self::resolveBestUserName(
(string)($Profile['name'] ?? ''),
trim((string)($Profile['phone'] ?? '')),
$UUID,
'',
$LinkedTg
);
if ($Best !== '') {
$Profile['name'] = $Best;
}
}
$ChannelStatus = 'member';
$ChannelGraceRemaining = 0;
$ChannelDisabled = false;
if (is_array($ChannelState)) {
$ChannelStatus = (string)($ChannelState['status'] ?? 'member');
$ChannelGraceRemaining = max(0, (int)($ChannelState['grace_remaining_seconds'] ?? 0));
$ChannelDisabled = !empty($ChannelState['disabled']);
} elseif ($BotUser !== null) {
$DisabledAt = (int)($BotUser['Channel_Client_Disabled_At'] ?? 0);
$GraceStartedAt = (int)($BotUser['Channel_Grace_Started_At'] ?? 0);
$ClientStatus = (string)($BotUser['Client_Status'] ?? '');
if ($DisabledAt > 0 || str_contains($ClientStatus, 'عدم عضویت')) {
$ChannelStatus = 'disabled';
$ChannelDisabled = true;
} elseif ($GraceStartedAt > 0) {
$GraceSeconds = Environment::getChannelGraceSeconds();
$ChannelStatus = 'grace';
$ChannelGraceRemaining = max(0, $GraceSeconds - max(0, time() - $GraceStartedAt));
}
}
$Profile['channel_status'] = $ChannelStatus;
$Profile['channel_grace_remaining_seconds'] = $ChannelGraceRemaining;
$Profile['channel_disabled'] = $ChannelDisabled;
$Base = PanelClient::accountBase($Account);
$Profile['account_base'] = $Base;
$Profile['subscription_url'] = self::subscriptionUrl($Account, $Base, $UUID);
$Profile['emergency_enabled'] = BotConfig::showEmergency();
return $Profile;
}

private static function syncLinkedBotUserFromPanel(string $UUID, int $LinkedTg, ?array &$Account): int {
if ($UUID === '' || $UUID === '_' || !is_array($Account) || $Account === []) {
return $LinkedTg;
}
$BotUser = self::resolveBotUser($UUID, $LinkedTg);
if ($BotUser === null) {
$CandidatePhone = \Helper::normalizePhone(trim((string)($Account['phone'] ?? '')) ?: trim((string)($Account['comment'] ?? '')));
if ($CandidatePhone !== '' && \Helper::validatePhone($CandidatePhone)) {
$ByPhone = Repository::findUserByPhone($CandidatePhone, 0);
$ExistingClient = trim((string)($ByPhone['Client_ID'] ?? ''));
if (!empty($ByPhone) && ($ExistingClient === '' || $ExistingClient === '_' || $ExistingClient === $UUID)) {
$BotUser = $ByPhone;
$FoundUid = (int)($ByPhone['Telegram_ID'] ?? 0);
if ($FoundUid > 0) {
try {
Database::getInstance()->execute(
'UPDATE `App_Devices` SET `Telegram_ID` = ? WHERE `User_UUID` = ? AND (`Telegram_ID` IS NULL OR `Telegram_ID` = 0)',
[$FoundUid, $UUID]
);
Database::getInstance()->execute(
'UPDATE `App_Sessions` SET `Telegram_ID` = ? WHERE `User_UUID` = ? AND (`Telegram_ID` IS NULL OR `Telegram_ID` = 0)',
[$FoundUid, $UUID]
);
} catch (Throwable) {}
}
}
}
}

if ($BotUser === null) {
return $LinkedTg;
}

$Uid = (int)($BotUser['Telegram_ID'] ?? 0);
if ($Uid > 0 && trim((string)($BotUser['Full_Name'] ?? '')) === '') {
$ResolvedBotName = self::resolveBestUserName(
trim((string)($Account['name'] ?? '')),
trim((string)($BotUser['Phone'] ?? '')),
$UUID,
'',
$Uid
);
if ($ResolvedBotName !== '') {
$BotUser['Full_Name'] = $ResolvedBotName;
try {
Database::getInstance()->execute(
'UPDATE `Users` SET `Full_Name` = ? WHERE `Telegram_ID` = ? AND (`Full_Name` IS NULL OR `Full_Name` = \'\')',
[$ResolvedBotName, $Uid]
);
} catch (Throwable) {}
}
}
$FullDeviceSyncName = trim((string)($BotUser['Full_Name'] ?? ''));
if (!self::isMeaningfulName($FullDeviceSyncName)) {
$FullDeviceSyncName = trim((string)($Account['name'] ?? ''));
}
if (self::isMeaningfulName($FullDeviceSyncName)) {
try {
Database::getInstance()->execute(
'UPDATE `App_Devices` SET `Full_Name` = ? WHERE `User_UUID` = ? AND (`Full_Name` IS NULL OR LENGTH(TRIM(`Full_Name`)) = 0)',
[$FullDeviceSyncName, $UUID]
);
} catch (Throwable) {}
}

if ($Uid > 0 && class_exists('Common') && method_exists('Common', 'syncSubscriptionFromServer')) {
try { Common::syncSubscriptionFromServer($BotUser, $Account); } catch (Throwable) {}
}

if ($Uid > 0 && (int)($Account['telegram_id'] ?? 0) === 0 && trim((string)($BotUser['Client_ID'] ?? '')) === $UUID) {
try {
$Updated = PanelClient::update($UUID, ['telegram_id' => $Uid]);
if (is_array($Updated) && (int)($Updated['telegram_id'] ?? 0) === $Uid) {
$Account['telegram_id'] = $Uid;
}
} catch (Throwable) {}
}

return $Uid > 0 ? $Uid : $LinkedTg;
}

/** True when the user already holds an active, non-expired subscription. */
private static function userHasActivePlan(?array $User, ?array $PanelAccount): bool {
if (is_array($PanelAccount) && $PanelAccount !== []) {
$Profile = AppFilter::accountPayload($PanelAccount);
$Active = !empty($Profile['is_active']) && !empty($Profile['enable']);
$Limit = (float)($Profile['usage_limit_GB'] ?? 0);
$Used = (float)($Profile['current_usage_GB'] ?? 0);
$HasQuota = $Limit <= 0 || $Used < $Limit;

$Expired = false;
$HasTerm = false;
$ExpiryRaw = trim((string)($Profile['expiry_date'] ?? ''));
$StartRaw = trim((string)($Profile['start_date'] ?? ''));
$Days = (int)($Profile['package_days'] ?? 0);

if ($ExpiryRaw !== '') {
$ExpTs = strtotime($ExpiryRaw);
if ($ExpTs !== false) {
$HasTerm = true;
$Expired = $ExpTs <= time();
}
} elseif ($StartRaw !== '' && $Days > 0) {
$StartDate = substr($StartRaw, 0, 10);
try {
$Zone = new DateTimeZone('Asia/Tehran');
$Start = DateTimeImmutable::createFromFormat('!Y-m-d', $StartDate, $Zone);
if ($Start instanceof DateTimeImmutable) {
$End = $Start->modify('+' . $Days . ' days');
if ($End instanceof DateTimeImmutable) {
$HasTerm = true;
$Expired = $End->getTimestamp() <= time();
}
}
} catch (Throwable) {}
} elseif ($Days > 0) {
$HasTerm = true;
}

if ($Active && $HasTerm && !$Expired && $HasQuota) {
return true;
}
if ($HasTerm && ($Expired || !$HasQuota)) {
return false;
}
if (!$Active && $HasTerm && !$Expired && $HasQuota && $User !== null && trim((string)($User['Subscription'] ?? '')) !== '') {
return true;
}
return false;
}

if ($User !== null) {
$Sub = trim((string)($User['Subscription'] ?? ''));
$Exp = (int)($User['Expiration_Time_Stamp'] ?? 0);
if ($Sub !== '' && ($Exp <= 0 || $Exp > time())) {
return true;
}
}

return false;
}

/**
 * Computes eligibility for the welcome free trial (3 GB / 1 day, strictly once)
 * and the seasonal Nowruz gift (5 GB / 13 days, gated by the bot's Nowruz menu).
 */
private static function offersPayload(string $UUID, int $TelegramId = 0, ?array $PanelAccount = null): array {
$UUID = trim($UUID);
$Has_UUID = $UUID !== '' && $UUID !== '_';
$User = self::resolveBotUser($UUID, $TelegramId);
$Uid = (int)($User['Telegram_ID'] ?? $TelegramId);
$Blocked = (int)($User['Is_Blocked'] ?? 0) === 1;
$HasActive = self::userHasActivePlan($User, $PanelAccount);

$FreeKey = 'App_Free_Claimed_' . $UUID;
$FreeClaimed = ((int)($User['Free_Plan_Claimed'] ?? 0) === 1)
|| ($Has_UUID && trim((string)Repository::getSetting($FreeKey, '')) === '1');
$FreeAvailable = $Has_UUID && !$Blocked && !$HasActive && !$FreeClaimed;

$NowruzEnabled = BotConfig::isNowruzMenuEnabled();
$NowruzClaimed = $Has_UUID && BotConfig::hasClaimedNowruz($Uid, $UUID);
$NowruzAvailable = $Has_UUID && $NowruzEnabled && !$Blocked && !$HasActive && !$NowruzClaimed;

return [
'free_available' => $FreeAvailable,
'free_claimed' => $FreeClaimed,
'free_gb' => self::FREE_PLAN_GB,
'free_days' => self::FREE_PLAN_DAYS,
'nowruz_menu_enabled' => $NowruzEnabled,
'nowruz_available' => $NowruzAvailable,
'nowruz_claimed' => $NowruzClaimed,
'nowruz_gb' => 5,
'nowruz_days' => 13,
];
}

/** Resolve only the bot wallet belonging to this authenticated panel account. */
private static function walletUser(string $Token): array {
$Session = self::sessionRow($Token);
if ($Session === null) self::fail(401, 'invalid_token', 'نشست منقضی شده است.');
$UUID = trim((string)($Session['User_UUID'] ?? ''));
if ($UUID === '' || $UUID === '_') self::fail(409, 'account_not_linked', 'برای استفاده از کیف پول، ابتدا حساب را از بخش عضویت به ربات متصل کنید.');
$SessionTg = (int)($Session['Telegram_ID'] ?? 0);
$User = self::resolveBotUser($UUID, $SessionTg);
if ($User === null || (string)($User['Client_ID'] ?? '') !== $UUID) {
$PanelAccount = PanelClient::get($UUID);
self::syncLinkedBotUserFromPanel($UUID, $SessionTg, $PanelAccount);
$User = self::resolveBotUser($UUID, $SessionTg);
}
if ($User === null || (string)($User['Client_ID'] ?? '') !== $UUID || (int)($User['Telegram_ID'] ?? 0) <= 0) {
self::fail(409, 'account_not_linked', 'برای استفاده از کیف پول، ابتدا حساب را از بخش عضویت به ربات متصل کنید.');
}
if ((int)($User['Is_Blocked'] ?? 0) === 1) self::fail(403, 'account_blocked', 'حساب کاربری شما غیرفعال است.');
return $User;
}

private static function walletPayload(int $UserId): array {
$Session = Repository::getUserSession($UserId);
$Pending = trim((string)($Session['Pending_Payment'] ?? ''));
$Parts = array_pad(explode('|', $Pending, 3), 3, '');
$PureTopup = $Pending !== '' && $Parts[0] === 'topup'
&& trim((string)($Session['Pending_Plan'] ?? '')) === ''
&& trim((string)($Session['Pending_Custom_Plan'] ?? '')) === ''
&& (float)($Session['Pending_Topup'] ?? 0) > 0;
$Url = '';
if ($PureTopup && Zarinpal::validAuthority($Parts[2])) {
$Url = Zarinpal::payLink(['BridgeUrl' => Zarinpal::bridgeUrl($Parts[2], $UserId), 'RedirectUrl' => Zarinpal::startPayUrl($Parts[2])]);
}
return [
'balance' => Repository::getBalance($UserId),
'min_topup' => SubscriptionFlow::appWalletTerms()['min_topup'],
'max_topup' => SubscriptionFlow::appWalletTerms()['max_topup'],
'payment_pending' => $Pending !== '',
'pending_id' => $Pending !== '' ? hash('sha256', $Pending) : '',
'pending_wallet_topup' => $PureTopup,
'pending_credit' => $PureTopup ? (float)$Session['Pending_Topup'] : 0,
'pending_amount' => $PureTopup ? (float)$Parts[1] : 0,
'checkout_url' => $Url,
];
}

/** Notification delivery must not turn a committed purchase into an error. */
private static function appPaymentNotice(int $TelegramId, string $Text): void {
try {
$User = class_exists('Repository') && method_exists('Repository', 'getUser') ? Repository::getUser($TelegramId) : [];
$UserName = trim((string)($User['Full_Name'] ?? ($User['First_Name'] ?? '')));
$Frame = method_exists('Helper', 'frame')
? Helper::frame('کاربر', $UserName !== '' ? $UserName : 'کاربر', 'پرداخت زرین پال', $TelegramId)
: '';
$Footer = method_exists('Helper', 'userFooter') ? Helper::userFooter() : '';
TelegramClient::sendMessage($TelegramId, $Frame . '💳 ' . $Text . $Footer, TelegramClient::inlineKeyboard([
[['text' => '✅بررسی پرداخت', 'callback_data' => 'بررسی پرداخت']],
[['text' => '💳خرید و تمدید اشتراک', 'callback_data' => 'user_subscriptions_menu']],
]));
} catch (Throwable $Error) {
error_log('[Umbrella-Bot][App-Payment-Notice] delivery failed: ' . $Error->getMessage());
}
}

private static function walletStatus(): void {
$User = self::walletUser(self::bearer());
self::ok(self::walletPayload((int)$User['Telegram_ID']));
}

private static function walletTopup(array $Body): void {
$User = self::walletUser((string)($Body['token'] ?? self::bearer()));
$Raw = $Body['amount'] ?? null;
$Terms = SubscriptionFlow::appWalletTerms();
if (!(is_int($Raw) || (is_string($Raw) && preg_match('/^[0-9]{1,9}$/D', $Raw) === 1))) self::fail(422, 'invalid_topup', 'مبلغ شارژ باید عدد صحیح به تومان باشد.');
$Amount = (int)$Raw;
if ($Amount < $Terms['min_topup'] || $Amount > $Terms['max_topup']) self::fail(422, 'invalid_topup', 'مبلغ شارژ خارج از محدوده مجاز است.');
try { $Payment = SubscriptionFlow::startAppWalletTopup((int)$User['Telegram_ID'], $Amount); }
catch (Throwable $Error) {
$Code = $Error->getMessage();
if ($Code === 'payment_pending') self::fail(409, $Code, 'پرداخت قبلی در حال بررسی است؛ ابتدا همان پرداخت را تکمیل یا پیگیری کنید.');
if ($Code === 'purchase_busy') self::fail(409, $Code, 'درخواست دیگری در حال پردازش است؛ کمی بعد تلاش کنید.');
if ($Code === 'invalid_topup') self::fail(422, $Code, 'مبلغ شارژ خارج از محدوده مجاز است.');
if ($Code === 'gateway_unavailable') self::fail(503, $Code, 'درگاه پرداخت یا نشانی بازگشت تنظیم نشده است.');
error_log('[Umbrella-Bot][App-Wallet] order failed: ' . $Code);
self::fail(502, 'gateway_request_failed', 'ساخت درخواست پرداخت ناموفق بود؛ دوباره تلاش کنید.');
}
self::appPaymentNotice((int)$User['Telegram_ID'], 'درخواست شارژ کیف پول از برنامه ساخته شد. پس از تأیید درگاه، نتیجه در همین ربات اعلام می شود.');
self::ok(['status' => 'payment_required', 'pending_id' => self::walletPayload((int)$User['Telegram_ID'])['pending_id'], 'credit' => $Amount,
'gateway_amount' => (float)$Payment['Amount'], 'fee' => (float)($Payment['Fee'] ?? 0),
'checkout_url' => Zarinpal::payLink($Payment)]);
}

private static function walletCancel(array $Body): void {
$User = self::walletUser((string)($Body['token'] ?? self::bearer()));
$UserId = (int)$User['Telegram_ID'];
$Expected = (string)($Body['pending_id'] ?? '');
if (preg_match('/^[a-f0-9]{64}$/D', $Expected) !== 1) self::fail(422, 'invalid_payment', 'ابتدا وضعیت پرداخت را تازه سازی کنید.');
try { $Archived = SubscriptionFlow::cancelAppPayment($UserId, $Expected); }
catch (Throwable $Error) {
$Code = $Error->getMessage();
if ($Code === 'payment_cannot_cancel_safely') self::fail(409, $Code, 'این سفارش قدیمی اطلاعات کافی برای لغو امن ندارد؛ از پشتیبانی پیگیری کنید.');
if ($Code === 'purchase_busy' || $Code === 'payment_changed') self::fail(409, $Code, 'وضعیت سفارش تغییر کرده است؛ کیف پول را تازه سازی کنید.');
error_log('[Umbrella-Bot][Payment-Cancel] ' . $Code);
self::fail(503, 'cancel_failed', 'لغو ایمن انجام نشد؛ دوباره تلاش کنید.');
}
if ($Archived) self::appPaymentNotice($UserId, 'سفارش پرداخت در برنامه لغو شد. درگاه ممکن است همچنان باز باشد؛ پرداخت دیرهنگام پس از تأیید به کیف پول اضافه می شود.');
self::ok(self::walletPayload($UserId));
}

private static function walletVerify(array $Body): void {
$User = self::walletUser((string)($Body['token'] ?? self::bearer()));
$UserId = (int)$User['Telegram_ID'];
$Before = self::walletPayload($UserId);
if (!empty($Before['payment_pending'])) SubscriptionFlow::recoverPendingPayment($UserId);
self::ok(self::walletPayload($UserId));
}

/** Return the bot's currently priced plans and the linked wallet balance. */
private static function subscriptionPlans(): void {
$Session = self::sessionRow(self::bearer());
if ($Session === null) self::fail(401, 'invalid_token', 'نشست منقضی شده است.');
$UUID = trim((string)($Session['User_UUID'] ?? ''));
if ($UUID === '' || $UUID === '_') self::fail(409, 'account_not_linked', 'حساب تلگرام و اشتراک این کاربر همگام نیست؛ ابتدا از ربات تلگرام وارد شوید.');
$SessionTg = (int)($Session['Telegram_ID'] ?? 0);
$User = self::resolveBotUser($UUID, $SessionTg);
if ($User === null || (string)($User['Client_ID'] ?? '') !== $UUID) {
$PanelAccount = PanelClient::get($UUID);
self::syncLinkedBotUserFromPanel($UUID, $SessionTg, $PanelAccount);
$User = self::resolveBotUser($UUID, $SessionTg);
}
if ($User === null || (string)($User['Client_ID'] ?? '') !== $UUID) {
self::fail(409, 'account_not_linked', 'حساب تلگرام و اشتراک این کاربر همگام نیست؛ ابتدا از ربات تلگرام وارد شوید.');
}
if ((int)($User['Is_Blocked'] ?? 0) === 1) self::fail(403, 'account_blocked', 'حساب کاربری شما غیرفعال است.');
self::ok([
'plans' => \SubscriptionFlow::appPlanCatalog(),
'custom' => \SubscriptionFlow::appCustomPlanTerms(),
'balance' => (int)round(\Repository::getBalance((int)$User['Telegram_ID'])),
]);
}

/**
 * Creates a checkout using the bot's own tariff, wallet and pending-order fields.
 * ZarinPal callbacks are still verified and settled only by SubscriptionFlow's
 * existing callback/settlement path; the app never submits a paid status.
 */
private static function purchaseSubscription(array $Body): void {
$Session = self::sessionRow((string)($Body['token'] ?? self::bearer()));
if ($Session === null) self::fail(401, 'invalid_token', 'نشست منقضی شده است.');
$UUID = trim((string)($Session['User_UUID'] ?? ''));
if ($UUID === '' || $UUID === '_') self::fail(409, 'account_not_linked', 'حساب تلگرام و اشتراک این کاربر همگام نیست؛ ابتدا از ربات تلگرام وارد شوید.');
$SessionTg = (int)($Session['Telegram_ID'] ?? 0);
$User = self::resolveBotUser($UUID, $SessionTg);
if ($User === null || (string)($User['Client_ID'] ?? '') !== $UUID) {
$PanelAccount = PanelClient::get($UUID);
self::syncLinkedBotUserFromPanel($UUID, $SessionTg, $PanelAccount);
$User = self::resolveBotUser($UUID, $SessionTg);
}
if ($User === null || (string)($User['Client_ID'] ?? '') !== $UUID) {
self::fail(409, 'account_not_linked', 'حساب تلگرام و اشتراک این کاربر همگام نیست؛ ابتدا از ربات تلگرام وارد شوید.');
}
$UserId = (int)($User['Telegram_ID'] ?? 0);
if ($UserId <= 0 || (int)($User['Is_Blocked'] ?? 0) === 1) self::fail(403, 'account_blocked', 'حساب کاربری شما غیرفعال است.');
$Type = strtolower(trim((string)($Body['type'] ?? 'ready')));
if (!in_array($Type, ['ready', 'custom'], true)) self::fail(422, 'invalid_plan', 'نوع پلن انتخابی معتبر نیست.');
if (trim((string)(Repository::getUserSession($UserId)['Pending_Payment'] ?? '')) !== '') self::fail(409, 'payment_pending', 'یک پرداخت دیگر در حال بررسی است؛ ابتدا همان پرداخت را تکمیل یا از ربات پیگیری کنید.');
$Phone = trim((string)($User['Phone'] ?? ''));
$FullName = trim((string)($User['Full_Name'] ?? ''));
if ($Phone === '' || $FullName === '') self::fail(409, 'profile_required', 'برای خرید، نام و شماره همراه را در پروفایل ربات ثبت کنید.');

$Month = '';
$Days = 0;
$GB = 0.0;
if ($Type === 'custom') {
$DaysRaw = $Body['days'] ?? null;
$GbRaw = $Body['gb'] ?? null;
if (!(is_int($DaysRaw) || (is_string($DaysRaw) && preg_match('/^[0-9]+$/D', trim($DaysRaw)) === 1))
|| !(is_int($GbRaw) || is_float($GbRaw) || (is_string($GbRaw) && is_numeric(trim($GbRaw))))) {
self::fail(422, 'invalid_custom_plan', 'مدت یا حجم پلن دلخواه معتبر نیست.');
}
$Days = (int)$DaysRaw;
$GB = (float)$GbRaw;
$Terms = \SubscriptionFlow::appCustomPlanTerms();
if (!is_finite($GB) || $Days < (int)$Terms['min_days'] || $Days > (int)$Terms['max_days']
|| $GB < (float)$Terms['min_gb'] || $GB > (float)$Terms['max_gb']) {
self::fail(422, 'invalid_custom_plan', 'مدت یا حجم پلن دلخواه خارج از محدوده مجاز است.');
}
$Price = (int)round($Days * (float)$Terms['day_rate']);
if ($Price <= 0) self::fail(422, 'custom_plan_unavailable', 'تعرفه پلن دلخواه در حال حاضر قابل محاسبه نیست.');
$Plan = [
'type' => 'custom',
'name' => 'اشتراک ' . \Helper::toPersian((string)$Days) . ' روزه - ' . \Helper::formatGB($GB),
'days' => $Days, 'gb' => $GB, 'price' => $Price];
} else {
$Month = trim((string)($Body['month'] ?? ''));
$Plans = array_column(\SubscriptionFlow::appPlanCatalog(), null, 'month');
if (!isset($Plans[$Month])) self::fail(422, 'invalid_plan', 'پلن انتخابی معتبر یا قابل فروش نیست.');
$Plan = $Plans[$Month];
$Price = (int)$Plan['price'];
}

// The client quote is only compared, never used to set the amount charged.
$Quote = $Body['quoted_price'] ?? null;
if ($Quote !== null && !(is_int($Quote) && $Quote > 0)) self::fail(422, 'invalid_quote', 'قیمت انتخابی معتبر نیست؛ تعرفه را تازه سازی کنید.');
if ($Quote !== null && $Quote !== $Price) self::fail(409, 'price_changed', 'تعرفه تغییر کرده است؛ پلن ها را تازه سازی و دوباره تأیید کنید.');

$Balance = \Repository::getBalance($UserId);
if ($Balance >= $Price) {
try {
$Result = $Type === 'custom'
? \SubscriptionFlow::purchaseCustomFromAppWallet($UserId, $Days, $GB, $Quote)
: \SubscriptionFlow::purchaseFromAppWallet($UserId, $Month, $Quote);
self::appPaymentNotice($UserId, 'خرید اشتراک از برنامه با موجودی کیف پول انجام و اشتراک فعال شد.');
self::ok(['status' => 'activated', 'balance' => (int)round($Result['balance']), 'expires_at' => $Result['expires_at'], 'message' => 'اشتراک با موجودی کیف پول مشترک فعال شد.']);
} catch (Throwable $Error) {
$Code = $Error->getMessage();
if ($Code === 'price_changed') self::fail(409, 'price_changed', 'تعرفه تغییر کرده است؛ پلن ها را تازه سازی و دوباره تأیید کنید.');
if ($Code === 'invalid_custom_plan' || $Code === 'custom_plan_unavailable') self::fail(422, $Code, 'تعرفه یا محدوده پلن دلخواه تغییر کرده است؛ پلن ها را تازه سازی کنید.');
if ($Code === 'payment_pending') self::fail(409, 'payment_pending', 'یک پرداخت دیگر در حال بررسی است؛ ابتدا همان پرداخت را تکمیل یا از ربات پیگیری کنید.');
if ($Code === 'wallet_changed') self::fail(409, 'wallet_changed', 'موجودی کیف پول هم زمان تغییر کرده است؛ کیف پول را تازه سازی کنید.');
if ($Code === 'purchase_busy') self::fail(409, 'busy', 'درخواست خرید دیگری در حال پردازش است؛ چند ثانیه صبر کنید.');
error_log('[Umbrella-Bot][App-Purchase] wallet activation failed for user ' . $UserId . ': ' . $Code);
self::fail(502, 'activation_failed', 'فعال سازی از کیف پول تأیید نشد؛ موجودی و اشتراک را تازه سازی کنید.');
}
}

try {
$Payment = $Type === 'custom'
? \SubscriptionFlow::startAppCustomCheckout($UserId, $Days, $GB, $Quote)
: \SubscriptionFlow::startAppCheckout($UserId, $Month, $Quote);
} catch (Throwable $Error) {
$Code = $Error->getMessage();
if ($Code === 'price_changed') self::fail(409, 'price_changed', 'تعرفه تغییر کرده است؛ پلن ها را تازه سازی و دوباره تأیید کنید.');
if ($Code === 'invalid_custom_plan' || $Code === 'custom_plan_unavailable') self::fail(422, $Code, 'تعرفه یا محدوده پلن دلخواه تغییر کرده است؛ پلن ها را تازه سازی کنید.');
if ($Code === 'payment_pending') self::fail(409, 'payment_pending', 'یک پرداخت دیگر در حال بررسی است؛ ابتدا همان پرداخت را تکمیل یا از ربات پیگیری کنید.');
if ($Code === 'purchase_busy') self::fail(409, 'busy', 'درخواست خرید دیگری در حال پردازش است؛ چند ثانیه صبر کنید.');
if ($Code === 'wallet_changed') self::fail(409, 'wallet_changed', 'موجودی یا قیمت پلن هم زمان تغییر کرده است؛ تعرفه و کیف پول را تازه سازی کنید.');
if ($Code === 'below_gateway_minimum') self::fail(422, 'below_gateway_minimum', 'مبلغ کسری از حداقل پرداخت درگاه کمتر است؛ کیف پول را از ربات شارژ کنید یا پلن دیگری برگزینید.');
if ($Code === 'gateway_unavailable') self::fail(503, 'gateway_unavailable', 'درگاه پرداخت یا نشانی بازگشت تنظیم نشده است.');
if ($Code === 'invalid_custom_plan') self::fail(422, 'invalid_custom_plan', 'مدت یا حجم پلن دلخواه خارج از محدوده مجاز است.');
error_log('[Umbrella-Bot][App-Purchase] gateway order creation failed for user ' . $UserId . ': ' . $Code);
self::fail(502, 'gateway_request_failed', 'ساخت درخواست پرداخت انجام نشد؛ دوباره تلاش کنید.');
}
$FinalAmount = (float)($Payment['Amount'] ?? ($Price - $Balance));
self::appPaymentNotice($UserId, 'درخواست پرداخت اشتراک از برنامه ساخته شد. پس از تأیید درگاه، نتیجه در همین ربات اعلام می شود.');
self::ok([
'status' => 'payment_required',
'checkout_url' => \Zarinpal::payLink($Payment),
'price' => (int)($Payment['Plan_Price'] ?? $Price),
'balance' => (int)($Payment['Wallet_Balance'] ?? $Balance),
'gateway_amount' => (int)round($FinalAmount),
'fee' => (int)round((float)($Payment['Fee'] ?? 0)),
'plan' => $Plan,
]);
}

private static function subscriptionOffers(): void {
$Session = self::sessionRow(self::bearer());

if ($Session === null) {
self::fail(401, 'invalid_token', 'نشست منقضی شده است.');
}

$UUID = trim((string)($Session['User_UUID'] ?? ''));

if ($UUID === '' || $UUID === '_') {
self::fail(409, 'no_account', 'حسابی به این نشست وصل نیست.');
}

$Account = PanelClient::get($UUID);
self::ok([
'offers' => self::offersPayload($UUID, (int)($Session['Telegram_ID'] ?? 0), $Account),
]);
}

private static function claimSubscription(array $Body): void {
$Session = self::sessionRow((string)($Body['token'] ?? self::bearer()));

if ($Session === null) {
self::fail(401, 'invalid_token', 'نشست منقضی شده است.');
}

$UUID = trim((string)($Session['User_UUID'] ?? ''));

if ($UUID === '' || $UUID === '_') {
self::fail(409, 'no_account', 'حسابی به این نشست وصل نیست.');
}

$Type = strtolower(trim((string)($Body['type'] ?? '')));

if ($Type !== 'free' && $Type !== 'nowruz') {
self::fail(422, 'invalid_plan', 'نوع اشتراک درخواستی معتبر نیست.');
}

$LockKey = 'app_claim_' . $Type . '_' . md5($UUID);

if (!Repository::tryCronLock($LockKey, 30)) {
self::fail(409, 'busy', 'درخواست قبلی در حال پردازش است؛ چند ثانیه صبر کنید.');
}

try {
$CurrentAccount = PanelClient::get($UUID);
$User = self::resolveBotUser($UUID, (int)($Session['Telegram_ID'] ?? 0));
$Uid = (int)($User['Telegram_ID'] ?? ($Session['Telegram_ID'] ?? 0));

if ((int)($User['Is_Blocked'] ?? 0) === 1) {
self::fail(403, 'account_blocked', 'حساب کاربری شما غیرفعال است.');
}

if (self::userHasActivePlan($User, $CurrentAccount)) {
self::fail(409, 'active_subscription', 'شما در حال حاضر اشتراک فعال دارید.');
}

if ($Type === 'free') {
$FreeKey = 'App_Free_Claimed_' . $UUID;
if ((int)($User['Free_Plan_Claimed'] ?? 0) === 1
|| trim((string)Repository::getSetting($FreeKey, '')) === '1') {
self::fail(409, 'already_claimed', 'اشتراک رایگان قبلاً برای این حساب فعال شده است.');
}
$Name = '۱ روزه';
$Gb = self::FREE_PLAN_GB;
$Days = self::FREE_PLAN_DAYS;
} else {
if (!BotConfig::isNowruzMenuEnabled()) {
self::fail(403, 'nowruz_disabled', 'اشتراک نوروزی در حال حاضر فعال نیست.');
}
if (BotConfig::hasClaimedNowruz($Uid, $UUID)) {
self::fail(409, 'already_claimed', 'اشتراک نوروزی قبلاً برای این حساب فعال شده است.');
}
$Name = 'نوروزی';
$Gb = 5;
$Days = 13;
}

$Tehran = new DateTimeZone('Asia/Tehran');
$NowTehran = new DateTimeImmutable('now', $Tehran);
$Today = $NowTehran->format('Y-m-d');
$ExpireStamp = $NowTehran->modify('+' . $Days . ' days')->getTimestamp();

$Updated = PanelClient::update($UUID, [
'start_date' => $Today,
'package_days' => $Days,
'usage_limit_GB' => $Gb,
'current_usage_GB' => 0,
'is_active' => true,
'enable' => true,
'last_reset_time' => $Today,
]);

if ($Updated === null || $Updated === []) {
self::fail(502, 'panel_unavailable', 'فعال سازی در سرور ناموفق بود؛ کمی بعد دوباره تلاش کنید.');
}

if ($Type === 'free') {
Repository::setSetting('App_Free_Claimed_' . $UUID, '1');
} else {
BotConfig::markNowruzClaimed($Uid, $UUID);
}

$UsageLimit = (float)max($Gb, (float)($Updated['usage_limit_GB'] ?? $Gb));
$Fresh = PanelClient::get($UUID) ?? $Updated;

if ($Uid > 0 && $User !== null) {
$Fields = [
'Client_ID' => $UUID,
'Subscription' => $Name,
'Package_Duration' => \Helper::durationLabel($Days),
'Package_Start_Date' => \Helper::formatPersianDate($NowTehran->getTimestamp()),
'Expiration_Date' => \Helper::formatExpiration($ExpireStamp),
'Expiration_Time_Stamp' => $ExpireStamp,
'Total_Usage_GB' => $UsageLimit,
'Used_Usage_GB' => 0.0,
'Remaining_Usage_GB' => $UsageLimit,
'Percent_Usage' => 0.0,
'Client_Status' => '✅فعال',
'Server_Is_Active' => 1,
'Server_Enable' => 1,
'Channel_Client_Disabled_At' => null,
'Deactivation_Message' => null,
];
if (isset($Fresh['comment'])) {
$Fields['Server_Comment'] = trim((string)$Fresh['comment']);
}
foreach ([
'ed25519_private_key' => 'ED_25519_Private_Key',
'ed25519_public_key' => 'ED_25519_Public_Key',
'wg_pk' => 'WireGuard_Private_Key',
'wg_pub' => 'WireGuard_Public_Key',
'wg_psk' => 'WireGuard_PSK',
] as $ApiKey => $DbKey) {
if (isset($Fresh[$ApiKey]) && trim((string)$Fresh[$ApiKey]) !== '') {
$Fields[$DbKey] = trim((string)$Fresh[$ApiKey]);
}
}
if ($Type === 'free') {
$Fields['Free_Plan_Claimed'] = 1;
}
Repository::updateUser($Uid, $Fields);
Repository::addSubscriptionLog($Uid, 'activate_' . $Type, $Name, $Days, $UsageLimit, $UUID, 'app', $Uid);
Repository::schedule('منقضی اشتراک', $Uid, $ExpireStamp);
SystemNotifications::queue(
$Uid,
$Type === 'free' ? 'اشتراک رایگان فعال شد' : 'اشتراک نوروزی فعال شد',
\Helper::toPersian((string)$Gb) . ' گیگابایت · ' . \Helper::toPersian((string)$Days) . ' روز اعتبار',
'claim-' . $Type . ':' . $ExpireStamp,
'success'
);
}

$Profile = self::accountPayloadWithExtras($Fresh, $UUID, $Uid);

self::ok([
'message' => $Type === 'free'
? 'اشتراک رایگان (۳ گیگابایت، ۱ روز) فعال شد.'
: 'اشتراک نوروزی (۵ گیگابایت، ۱۳ روز) فعال شد.',
'account' => $Profile,
'filter' => self::filterPayload($UUID),
'offers' => self::offersPayload($UUID, $Uid, $Fresh),
]);
} finally {
Repository::releaseCronLock($LockKey);
}
}

private static function fetchSubscription(array $Body): void {
$Session = self::sessionRow((string)($Body['token'] ?? self::bearer()));

if ($Session === null) {
self::fail(401, 'invalid_token', 'نشست منقضی شده است.');
}

$UUID = trim((string)($Session['User_UUID'] ?? ''));

if ($UUID === '' || $UUID === '_') {
self::fail(409, 'no_account', 'حسابی به این نشست وصل نیست.');
}

$Account = PanelClient::get($UUID) ?? [];
$Base = PanelClient::accountBase($Account);
$Sub_Url = self::subscriptionUrl($Account, $Base, $UUID);

// Only allow fetching the user's own `/sub/` link when the full secret prefix
// is present; prevent calling a bare `https://host/<uuid>/sub/` that 404s.
$Parsed = $Sub_Url !== '' ? parse_url($Sub_Url) : false;
$Segments = is_array($Parsed) && isset($Parsed['path'])
? array_values(array_filter(explode('/', (string)$Parsed['path']), static fn(string $S): bool => $S !== ''))
: [];

if ($Sub_Url === '' || count($Segments) < 3) {
self::fail(409, 'no_subscription_url', 'نشانی اشتراک اختصاصی در سرور تنظیم نشده است.');
}

$User_Agents = ['Umbrella-Windows/1.0.1', 'SingBox/1.10.0'];
$Last_Status = 0;
$Last_Error = '';

foreach ($User_Agents as $Agent) {
$Response = HttpClient::get($Sub_Url, [
'Accept' => 'text/plain, application/json, */*',
'User-Agent' => $Agent,
], 18);
$Last_Status = (int)($Response['StatusCode'] ?? 0);
$Last_Error = trim((string)($Response['Error'] ?? ''));
$Content = trim((string)($Response['Body'] ?? ''));

if ($Last_Status >= 200 && $Last_Status < 300 && $Content !== '') {
$Lower_Head = strtolower(substr(ltrim($Content), 0, 64));

if (str_starts_with($Lower_Head, '<!doctype html') || str_starts_with($Lower_Head, '<html')) {
continue;
}

self::ok([
'uuid' => $UUID,
'account_base' => $Base,
'subscription_url' => $Sub_Url,
'content' => $Content,
'checked_at' => gmdate('c'),
]);
}

if ($Last_Status === 401 || $Last_Status === 403 || $Last_Status === 404) {
break;
}
}

error_log('[Umbrella-Bot][Gateway] subscription/fetch failed | uuid=' . substr($UUID, 0, 8) . ' | HTTP=' . $Last_Status . ($Last_Error !== '' ? ' | curl=' . $Last_Error : ''));
self::fail(
$Last_Status >= 400 && $Last_Status < 500 ? $Last_Status : 502,
'subscription_unavailable',
'دریافت اشتراک اختصاصی از سرور ناموفق بود.'
);
}

private static function recordActivityRoute(array $Body): void {
$Session = self::sessionRow((string)($Body['token'] ?? self::bearer()));

if ($Session === null) {
self::fail(401, 'invalid_token', 'نشست منقضی شده است.');
}

$DeviceId = (string)$Session['Device_ID'];
$UUID = trim((string)($Session['User_UUID'] ?? ''));
$LinkedTg = self::autoLinkTelegramOwner($DeviceId, $UUID, (int)($Session['Telegram_ID'] ?? 0));
self::touchDeviceSeen($DeviceId, $UUID, $LinkedTg, '', (string)($Session['Token_Hash'] ?? ''));
$Stored = self::storeActivity($DeviceId, $UUID, $LinkedTg, $Body);
self::ok(['stored' => $Stored]);
}

private static function resetActivityIfDue(): void {
if (class_exists('Scheduler') && method_exists('Scheduler', 'purgeUserActivityIfDue')) {
Scheduler::purgeUserActivityIfDue();
return;
}
$Now = time();
$Last = (int)Repository::getSetting('Last_User_Activity_Reset_At', 0);
$Db = Database::getInstance();
try {
if ($Last <= 0) {
$Db->execute('DELETE FROM `App_User_Activity` WHERE `Last_Seen_At` < ? OR `Category` = ?', [$Now - 86400, 'screen']);
Repository::setSetting('Last_User_Activity_Reset_At', (string)$Now);
return;
}
if (($Now - $Last) >= 86400) {
$Db->execute('DELETE FROM `App_User_Activity`', []);
Repository::setSetting('Last_User_Activity_Reset_At', (string)$Now);
}
} catch (Throwable) {}
}

private static function storeActivity(string $DeviceId, string $UUID, int $TelegramId, array $Body): int {
$DeviceId = trim($DeviceId);
if ($DeviceId === '') return 0;

self::resetActivityIfDue();

$Items = is_array($Body['activity'] ?? null) ? $Body['activity'] : [];
if ($Items === []) return 0;

$Now = time();
$Count = 0;
$Db = Database::getInstance();

foreach (array_slice($Items, 0, 60) as $Raw) {
if (!is_array($Raw)) continue;
$Category = strtolower(trim((string)($Raw['category'] ?? '')));
if (!in_array($Category, ['site', 'app', 'software', 'mobile'], true)) continue;

$Target = self::normalizeActivityTarget($Category, (string)($Raw['target'] ?? ''));
if ($Target === '') continue;

$Hits = max(1, min(10000, (int)($Raw['hits'] ?? 1)));
$Down = max(0, (int)($Raw['down'] ?? 0));
$Up = max(0, (int)($Raw['up'] ?? 0));

try {
$Db->execute(
'INSERT INTO `App_User_Activity` (`Device_ID`, `User_UUID`, `Telegram_ID`, `Category`, `Target`, `Hits`, `Bytes_Down`, `Bytes_Up`, `Last_Seen_At`)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
ON DUPLICATE KEY UPDATE
`User_UUID` = COALESCE(NULLIF(VALUES(`User_UUID`), \'\'), `User_UUID`),
`Telegram_ID` = COALESCE(NULLIF(VALUES(`Telegram_ID`), 0), `Telegram_ID`),
`Hits` = LEAST(4294967295, `Hits` + VALUES(`Hits`)),
`Bytes_Down` = `Bytes_Down` + VALUES(`Bytes_Down`),
`Bytes_Up` = `Bytes_Up` + VALUES(`Bytes_Up`),
`Last_Seen_At` = VALUES(`Last_Seen_At`)',
[$DeviceId, $UUID !== '' && $UUID !== '_' ? $UUID : null, $TelegramId > 0 ? $TelegramId : null, $Category, $Target, $Hits, $Down, $Up, $Now]
);
$Count++;
} catch (Throwable $Error) {
error_log('[Umbrella-Bot][Activity] ' . $Error->getMessage());
}
}

if ($Count > 0) {
try {
$Total = (int)($Db->scalar('SELECT COUNT(*) FROM `App_User_Activity` WHERE `Device_ID` = ?', [$DeviceId]) ?? 0);
if ($Total > 300) {
$Excess = $Total - 250;
$Db->execute('DELETE FROM `App_User_Activity` WHERE `Device_ID` = ? ORDER BY `Last_Seen_At` ASC LIMIT ' . $Excess, [$DeviceId]);
}
} catch (Throwable) {}
}

return $Count;
}

private static function normalizeActivityTarget(string $Category, string $RawTarget): string {
$Clean = trim((string)preg_replace('/[\x00-\x1F\x7F]+/u', '', $RawTarget));
if ($Clean === '') return '';

if ($Category === 'site') {
$Host = strtolower($Clean);
if (str_contains($Host, '://')) {
$Parsed = parse_url($Host, PHP_URL_HOST);
$Host = is_string($Parsed) ? strtolower($Parsed) : $Host;
} else {
$SlashPos = strpos($Host, '/');
if ($SlashPos !== false) $Host = substr($Host, 0, $SlashPos);
}
if (str_starts_with($Host, '[') && str_contains($Host, ']')) {
$Host = substr($Host, 1, (int)strpos($Host, ']') - 1);
} else {
$Host = preg_replace('/:\d+$/', '', $Host) ?? $Host;
}
$Host = trim($Host, " \t\n\r\0\x0B.");
if (str_starts_with($Host, 'www.') && strlen($Host) > 5) {
$Host = substr($Host, 4);
}
if ($Host === '' || $Host === 'localhost' || str_ends_with($Host, '.local') || str_ends_with($Host, '.arpa') || str_ends_with($Host, '.internal') || str_ends_with($Host, '.lan')) {
return '';
}
if (in_array($Host, ['connectivitycheck.gstatic.com', 'captive.apple.com', 'msftconnecttest.com', 'msftncsi.com', 'detectportal.firefox.com', 'dns.google', 'one.one.one.one'], true)) {
return '';
}
if (filter_var($Host, FILTER_VALIDATE_IP) !== false) {
return '';
}
if (preg_match('/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,24}$/', $Host) !== 1) {
return '';
}
return substr($Host, 0, 180);
}

if ($Category === 'app' || $Category === 'software' || $Category === 'mobile') {
return self::normalizeAppDisplayName($Clean);
}

return '';
}

public static function normalizeAppDisplayName(string $Raw): string {
$Normalized = trim(str_replace('\\', '/', $Raw));
if ($Normalized === '') return '';
if (str_contains($Normalized, '/')) {
$Normalized = trim(basename($Normalized));
}
if ($Normalized === '' || ctype_digit($Normalized)) return '';
$TrimmedIp = trim($Normalized, '[]');
if (filter_var($TrimmedIp, FILTER_VALIDATE_IP) !== false) return '';

$Lower = strtolower($Normalized);
foreach (['sing-box', 'hiddify', 'umbrella_vpn', 'umbrella-vpn', 'umbrella.exe', 'umbrellacore', 'ir.umbrella.vpn', 'clash', 'mihomo', 'xray'] as $Ignored) {
if ($Lower === $Ignored || str_starts_with($Lower, $Ignored . '.')) {
return '';
}
}
if (in_array($Lower, [
'root', 'system', 'nobody', 'shell', 'radio', 'media', 'graphics', 'bluetooth', 'nfc', 'wifi',
'svchost.exe', 'svchost', 'lsass.exe', 'services.exe', 'csrss.exe', 'smss.exe', 'wininit.exe',
'spoolsv.exe', 'dwm.exe', 'fontdrvhost.exe', 'audiodg.exe', 'runtimebroker.exe', 'searchhost.exe',
'taskhostw.exe', 'backgroundtaskhost.exe', 'conhost.exe', 'compattelrunner.exe', 'sihost.exe',
'ctfmon.exe', 'wmiprvse.exe', 'trustedinstaller.exe', 'tiworker.exe', 'msiexec.exe', 'smartscreen.exe',
'winlogon.exe', 'dashost.exe', 'dllhost.exe', 'werfault.exe', 'taskmgr.exe', 'com.android.systemui',
], true)) {
return '';
}

static $Known = [
'chrome.exe' => 'Google Chrome',
'msedge.exe' => 'Microsoft Edge',
'firefox.exe' => 'Mozilla Firefox',
'brave.exe' => 'Brave',
'opera.exe' => 'Opera',
'vivaldi.exe' => 'Vivaldi',
'telegram.exe' => 'Telegram',
'ayugram.exe' => 'AyuGram',
'kotatogram.exe' => 'Kotatogram',
'discord.exe' => 'Discord',
'whatsapp.exe' => 'WhatsApp',
'whatsapp.root.exe' => 'WhatsApp',
'code.exe' => 'Visual Studio Code',
'cursor.exe' => 'Cursor',
'spotify.exe' => 'Spotify',
'idman.exe' => 'Internet Download Manager',
'steam.exe' => 'Steam',
'steamwebhelper.exe' => 'Steam',
'epicgameslauncher.exe' => 'Epic Games',
'winrar.exe' => 'WinRAR',
'7zfm.exe' => '7-Zip',
'vlc.exe' => 'VLC Media Player',
'obs64.exe' => 'OBS Studio',
'anydesk.exe' => 'AnyDesk',
'rustdesk.exe' => 'RustDesk',
'slack.exe' => 'Slack',
'zoom.exe' => 'Zoom',
'notion.exe' => 'Notion',
'postman.exe' => 'Postman',
'thunderbird.exe' => 'Mozilla Thunderbird',
'qbittorrent.exe' => 'qBittorrent',
'utorrent.exe' => 'uTorrent',
'winscp.exe' => 'WinSCP',
'putty.exe' => 'PuTTY',
'filezilla.exe' => 'FileZilla',
'photoshop.exe' => 'Adobe Photoshop',
'illustrator.exe' => 'Adobe Illustrator',
'afterfx.exe' => 'Adobe After Effects',
'adobe premiere pro.exe' => 'Adobe Premiere Pro',
'windowsterminal.exe' => 'Windows Terminal',
'wt.exe' => 'Windows Terminal',
'powershell.exe' => 'PowerShell',
'pwsh.exe' => 'PowerShell',
'explorer.exe' => 'Windows Explorer',
'com.instagram.android' => 'Instagram',
'com.instagram.lite' => 'Instagram Lite',
'org.telegram.messenger' => 'Telegram',
'org.telegram.messenger.web' => 'Telegram',
'org.thunderdog.challegram' => 'Telegram X',
'com.whatsapp' => 'WhatsApp',
'com.whatsapp.w4b' => 'WhatsApp Business',
'com.android.chrome' => 'Google Chrome',
'org.mozilla.firefox' => 'Mozilla Firefox',
'com.brave.browser' => 'Brave',
'com.opera.browser' => 'Opera',
'com.microsoft.emmx' => 'Microsoft Edge',
'com.google.android.youtube' => 'YouTube',
'com.google.android.apps.youtube.music' => 'YouTube Music',
'com.spotify.music' => 'Spotify',
'com.zhiliaoapp.musically' => 'TikTok',
'com.ss.android.ugc.trill' => 'TikTok',
'com.discord' => 'Discord',
'com.linkedin.android' => 'LinkedIn',
'com.twitter.android' => 'X',
'com.reddit.frontpage' => 'Reddit',
'com.pinterest' => 'Pinterest',
'com.snapchat.android' => 'Snapchat',
'com.google.android.gm' => 'Gmail',
'com.openai.chatgpt' => 'ChatGPT',
'com.android.vending' => 'Google Play',
'ir.eitaa.messenger' => 'ایتا',
'ir.nasim' => 'بله',
'app.rbmain.a' => 'روبیکا',
'com.rubika.android' => 'روبیکا',
'ir.soroush.messenger' => 'سروش پلاس',
'ir.resaneh1.iptv' => 'تلوبیون',
'cab.snapp.passenger' => 'اسنپ',
'ir.divar' => 'دیوار',
'com.digikala' => 'دیجی کالا',
];
if (isset($Known[$Lower])) {
return $Known[$Lower];
}
if (str_ends_with($Lower, '.exe') && strlen($Normalized) > 4) {
$Base = trim(substr($Normalized, 0, -4));
if ($Base === '' || ctype_digit($Base)) return '';
$Spaced = str_replace(['_', '-'], ' ', $Base);
$Titled = ucwords($Spaced);
return function_exists('mb_substr') ? mb_substr($Titled, 0, 120, 'UTF-8') : substr($Titled, 0, 120);
}
if (preg_match('/^(?:com|org|net|ir|io|app|me)\.[a-z0-9_]+(?:\.[a-z0-9_]+)+$/', $Lower) === 1) {
$Parts = array_values(array_filter(explode('.', $Lower), static fn(string $P): bool => !in_array($P, ['com', 'org', 'net', 'ir', 'io', 'app', 'me', 'android', 'mobile', 'messenger', 'client', 'apps', 'google'], true)));
if ($Parts !== []) {
$Label = ucwords(str_replace('_', ' ', implode(' ', array_slice($Parts, 0, 2))));
return function_exists('mb_substr') ? mb_substr($Label, 0, 120, 'UTF-8') : substr($Label, 0, 120);
}
}
$Cleaned = trim(preg_replace('/\s+/u', ' ', $Normalized) ?? $Normalized);
return function_exists('mb_substr') ? mb_substr($Cleaned, 0, 120, 'UTF-8') : substr($Cleaned, 0, 120);
}

private static function supportReport(array $Body): void {
$Token = trim((string)($Body['token'] ?? self::bearer()));
$DeviceId = trim((string)($Body['device_id'] ?? ''));
$Phone = trim((string)($Body['phone'] ?? ''));
$Note = trim((string)($Body['note'] ?? ''));
$Platform = trim((string)($Body['platform'] ?? ''));
$AppVersion = trim((string)($Body['app_version'] ?? ''));
$Device = is_array($Body['device'] ?? null) ? $Body['device'] : [];
$VpnState = $Body['vpn_state'] ?? [];
$Errors = is_array($Body['errors'] ?? null) ? $Body['errors'] : [];
$RecentLogs = $Body['recent_logs'] ?? '';
if (is_array($RecentLogs)) {
$RecentLogs = implode("\n", array_map(static fn($Line): string => (string)$Line, $RecentLogs));
}
$RecentLogsText = trim((string)$RecentLogs);

if ($Note === '' && $Errors === [] && $RecentLogsText === '' && $Device === []) {
self::fail(422, 'empty_report', 'اطلاعات گزارش پشتیبانی خالی است.');
}

$Sender = self::resolveSupportSender($Token, $DeviceId, $Phone);
$EffectiveDeviceId = $DeviceId !== '' ? $DeviceId : (string)($Sender['device_id'] ?? '');
$RateKey = 'app_support_cd_' . md5(($EffectiveDeviceId !== '' ? $EffectiveDeviceId : 'ip') . '|' . self::clientIp());
$LastSent = (int)Repository::getSetting($RateKey, '0');
$Now = time();
if ($LastSent > 0 && ($Now - $LastSent) < 20) {
$Wait = 20 - ($Now - $LastSent);
self::fail(429, 'rate_limited', 'گزارش پشتیبانی شما لحظاتی پیش ارسال شد؛ ' . Helper::toPersian((string)$Wait) . ' ثانیه دیگر می توانید دوباره ارسال کنید.');
}

$Admins = self::administratorTelegramIds();
if ($Admins === []) {
self::fail(503, 'admin_unavailable', 'حساب مدیریت در ربات تلگرام تنظیم نشده است.');
}

$UserRow = $Sender['user'] ?? null;
$DeviceRow = $Sender['device_row'] ?? null;
$TgId = (int)($Sender['telegram_id'] ?? 0);
$Uuid = trim((string)($Sender['user_uuid'] ?? ''));
$UserName = trim((string)($UserRow['Full_Name'] ?? ($UserRow['First_Name'] ?? '')));
if ($UserName === '' && is_array($DeviceRow)) {
$UserName = trim((string)($DeviceRow['Full_Name'] ?? ''));
}
$UserPhone = trim((string)($UserRow['Phone'] ?? ($DeviceRow['Phone'] ?? $Phone)));
$SubPlan = trim((string)($UserRow['Subscription'] ?? ''));
$SubStatus = trim((string)($UserRow['Client_Status'] ?? ''));

$DeviceName = trim((string)($Device['device_name'] ?? ($Device['hostname'] ?? ($DeviceRow['Device_Name'] ?? ''))));
$OsText = trim((string)($Device['os'] ?? ($Platform !== '' ? $Platform : ($DeviceRow['Platform'] ?? ''))));
$CpuText = trim((string)($Device['cpu'] ?? ''));
$CpuCores = (int)($Device['cpu_cores'] ?? 0);
$RamTotal = (int)($Device['ram_total_mb'] ?? 0);
$RamUsed = (int)($Device['ram_used_mb'] ?? 0);
$DiskFree = (int)($Device['disk_free_mb'] ?? 0);
$DiskTotal = (int)($Device['disk_total_mb'] ?? 0);
$LocalIp = trim((string)($Device['local_ip'] ?? ''));
$Adapter = trim((string)($Device['adapter'] ?? ''));
$Elevated = !empty($Device['elevated']);
$ClientIp = self::clientIp();
$SentDate = Helper::formatPersianDate($Now, true);

$Lines = [];
$Lines[] = '🆘 <b>گزارش فوری پشتیبانی از برنامه آمبرلا</b>';
$Lines[] = '🕒 زمان ثبت: <b>' . self::supportEsc($SentDate) . '</b>';
$Lines[] = '';

$Lines[] = '👤 <b>مشخصات کاربر:</b>';
if ($UserName !== '') {
$Lines[] = '• نام: ' . ($TgId > 0 ? '<a href="tg://user?id=' . $TgId . '">' . self::supportEsc($UserName) . '</a>' : '<b>' . self::supportEsc($UserName) . '</b>');
} else {
$Lines[] = '• نام: <i>کاربر مهمان / پیش از ورود</i>';
}
if ($UserPhone !== '') {
$UserPhoneLabel = method_exists('Helper', 'formatPhoneDisplay') ? Helper::formatPhoneDisplay($UserPhone) : $UserPhone;
$Lines[] = '• موبایل: <code>' . self::supportEsc($UserPhoneLabel) . '</code>';
}
if ($TgId > 0) $Lines[] = '• آیدی تلگرام: <code>' . $TgId . '</code>';
if ($Uuid !== '' && $Uuid !== '_') $Lines[] = '• شناسه سرویس: <code>' . self::supportEsc($Uuid) . '</code>';
if ($SubPlan !== '' || $SubStatus !== '') {
$Lines[] = '• وضعیت اشتراک: ' . self::supportEsc(trim($SubPlan . ' (' . $SubStatus . ')', ' ()'));
}

$Lines[] = '';
$Lines[] = '💻 <b>مشخصات دقیق دستگاه:</b>';
if ($DeviceName !== '') $Lines[] = '• نام دستگاه: <b>' . self::supportEsc($DeviceName) . '</b>';
if ($OsText !== '') $Lines[] = '• سیستم عامل: ' . self::supportEsc($OsText);
if ($AppVersion !== '') $Lines[] = '• نسخه آمبرلا: <code>' . self::supportEsc($AppVersion) . '</code>';
if ($EffectiveDeviceId !== '') $Lines[] = '• شناسه دستگاه: <code>' . self::supportEsc(substr($EffectiveDeviceId, 0, 24)) . '</code>';
if ($CpuText !== '') $Lines[] = '• پردازنده: ' . self::supportEsc($CpuText . ($CpuCores > 0 ? " ({$CpuCores} هسته)" : ''));
if ($RamTotal > 0) $Lines[] = '• حافظه رم: ' . $RamUsed . ' / ' . $RamTotal . ' MB';
if ($DiskTotal > 0) $Lines[] = '• فضای دیسک: ' . $DiskFree . ' MB آزاد از ' . $DiskTotal . ' MB';
if ($LocalIp !== '') $Lines[] = '• آی پی محلی: <code>' . self::supportEsc($LocalIp) . '</code>';
if ($ClientIp !== '') $Lines[] = '• آی پی ارسال کننده: <code>' . self::supportEsc($ClientIp) . '</code>';
if ($Adapter !== '') $Lines[] = '• رابط شبکه: ' . self::supportEsc($Adapter);
if (isset($Device['elevated'])) $Lines[] = '• سطح دسترسی: ' . ($Elevated ? 'مدیر سیستم / روت' : 'کاربر عادی');

if (is_array($VpnState) && $VpnState !== []) {
$VpnSummary = [];
if (!empty($VpnState['status'])) $VpnSummary[] = 'وضعیت: ' . (string)$VpnState['status'];
if (!empty($VpnState['mode'])) $VpnSummary[] = 'حالت: ' . (string)$VpnState['mode'];
if (!empty($VpnState['server'])) $VpnSummary[] = 'سرور: ' . (string)$VpnState['server'];
if (!empty($VpnState['error'])) $VpnSummary[] = 'خطای اتصال: ' . (string)$VpnState['error'];
if ($VpnSummary !== []) {
$Lines[] = '';
$Lines[] = '🔌 <b>وضعیت اتصال سرویس:</b>';
foreach ($VpnSummary as $SummaryItem) {
$Lines[] = '• ' . self::supportEsc($SummaryItem);
}
}
} elseif (is_string($VpnState) && trim($VpnState) !== '') {
$Lines[] = '';
$Lines[] = '🔌 <b>وضعیت اتصال:</b> ' . self::supportEsc(trim($VpnState));
}

if ($Note !== '') {
$CleanNote = function_exists('mb_substr') ? mb_substr($Note, 0, 1000, 'UTF-8') : substr($Note, 0, 1000);
$Lines[] = '';
$Lines[] = '📝 <b>توضیح کاربر:</b>';
$Lines[] = '<blockquote>' . self::supportEsc($CleanNote) . '</blockquote>';
}

if ($Errors !== []) {
$Lines[] = '';
$Lines[] = '❌ <b>خطاها و هشدارهای ثبت شده (' . count($Errors) . '):</b>';
$SlicedErrors = array_slice($Errors, -25);
$ErrorBlock = [];
foreach ($SlicedErrors as $Err) {
$ErrStr = is_array($Err)
? trim(((string)($Err['time'] ?? '')) . ' [' . strtoupper((string)($Err['level'] ?? 'ERROR')) . '] ' . ((string)($Err['message'] ?? '')))
: trim((string)$Err);
if ($ErrStr !== '') $ErrorBlock[] = $ErrStr;
}
if ($ErrorBlock !== []) {
$JoinedErrors = implode("\n", $ErrorBlock);
if (function_exists('mb_strlen') && mb_strlen($JoinedErrors, 'UTF-8') > 2500) {
$JoinedErrors = '...' . "\n" . mb_substr($JoinedErrors, -2500, null, 'UTF-8');
}
$Lines[] = '<pre>' . self::supportEsc($JoinedErrors) . '</pre>';
}
}

if ($RecentLogsText !== '') {
if (function_exists('mb_strlen') && mb_strlen($RecentLogsText, 'UTF-8') > 2600) {
$RecentLogsText = '...' . "\n" . mb_substr($RecentLogsText, -2600, null, 'UTF-8');
}
$Lines[] = '';
$Lines[] = '📋 <b>آخرین گزارش های برنامه:</b>';
$Lines[] = '<pre>' . self::supportEsc($RecentLogsText) . '</pre>';
}

$KeyboardRows = [];
$DeviceRowId = (int)($DeviceRow['ID'] ?? 0);
if ($TgId > 0) {
$KeyboardRows[] = [
['text' => '👁رصد این کاربر', 'callback_data' => 'admin_monitor_view:t:' . $TgId . ':0:all:0'],
['text' => '👤مشاهده کاربر', 'callback_data' => 'admin_user_view:' . $TgId . ':0'],
];
} elseif ($DeviceRowId > 0) {
$KeyboardRows[] = [
['text' => '👁رصد این دستگاه', 'callback_data' => 'admin_monitor_view:d:' . $DeviceRowId . ':0:all:0'],
];
}
$KeyboardRows[] = [['text' => '🏠مدیریت', 'callback_data' => 'admin_home']];

$Message = implode("\n", $Lines);
$Delivered = false;
foreach ($Admins as $AdminId) {
if ($AdminId <= 0) continue;
try {
if (TelegramClient::sendReadableMessage($AdminId, null, $Message, ['inline_keyboard' => $KeyboardRows])) {
$Delivered = true;
}
} catch (Throwable $Error) {
error_log('[Umbrella-Bot][SupportReport] send failed: ' . $Error->getMessage());
}
}

if (!$Delivered) {
self::fail(502, 'telegram_failed', 'ارسال گزارش به ربات تلگرام ناموفق بود؛ کمی بعد دوباره تلاش کنید.');
}

Repository::setSetting($RateKey, (string)$Now);
self::ok([
'sent' => true,
'message' => 'مشخصات دستگاه و گزارش خطاها بلافاصله برای پشتیبانی ارسال شد.',
]);
}

private static function resolveSupportSender(string $Token, string $DeviceId, string $Phone): array {
$Db = Database::getInstance();
$SessionRow = null;
$DeviceRow = null;
$UserRow = null;
$TelegramId = 0;
$Uuid = '';

if ($Token !== '') {
try {
$SessionRow = $Db->fetch(
'SELECT `User_UUID`, `Device_ID`, `Telegram_ID` FROM `App_Sessions` WHERE `Token_Hash` = ? LIMIT 1',
[hash('sha256', $Token)]
);
} catch (Throwable) {}
if (is_array($SessionRow)) {
$DeviceId = trim((string)($SessionRow['Device_ID'] ?? $DeviceId));
$Uuid = trim((string)($SessionRow['User_UUID'] ?? ''));
$TelegramId = (int)($SessionRow['Telegram_ID'] ?? 0);
}
}

if ($DeviceId !== '') {
try {
$DeviceRow = $Db->fetch(
'SELECT * FROM `App_Devices` WHERE `Device_ID` = ? LIMIT 1',
[$DeviceId]
);
} catch (Throwable) {}
if (is_array($DeviceRow)) {
if ($Uuid === '' || $Uuid === '_') $Uuid = trim((string)($DeviceRow['User_UUID'] ?? ''));
if ($TelegramId <= 0) $TelegramId = (int)($DeviceRow['Telegram_ID'] ?? 0);
if ($Phone === '') $Phone = trim((string)($DeviceRow['Phone'] ?? ''));
}
}

if ($TelegramId > 0) {
$UserRow = Repository::getUser($TelegramId);
}
if (($UserRow === null || $UserRow === []) && $Uuid !== '' && $Uuid !== '_') {
$UserRow = self::resolveBotUser($Uuid, 0);
if (is_array($UserRow) && !empty($UserRow['Telegram_ID'])) {
$TelegramId = (int)$UserRow['Telegram_ID'];
}
}
if (($UserRow === null || $UserRow === []) && $Phone !== '') {
$FoundByPhone = Repository::findUserByIdentifier($Phone);
if (is_array($FoundByPhone) && $FoundByPhone !== []) {
$UserRow = $FoundByPhone;
$TelegramId = (int)($FoundByPhone['Telegram_ID'] ?? $TelegramId);
if ($Uuid === '' || $Uuid === '_') $Uuid = trim((string)($FoundByPhone['Client_ID'] ?? ''));
}
}

return [
'device_id' => $DeviceId,
'user_uuid' => $Uuid,
'telegram_id' => $TelegramId,
'device_row' => $DeviceRow,
'user' => $UserRow,
];
}

private static function supportEsc(string $Text): string {
$Clean = Helper::stripZwnj(Helper::repairMojibake($Text));
return htmlspecialchars($Clean, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

private static function ping(): void {
self::ok([
'time' => gmdate('c'),
'version' => '4',
'features' => ['signin', 'device_confirm', 'notifications', 'filter', 'offers', 'subscription_fetch', 'paid_plans', 'subscription_purchase', 'activity_monitor', 'support_report', 'app_announcement', 'promo_announcement', 'security_alert'],
'announcement' => self::announcementPayload(),
'promo_announcement' => self::promoAnnouncementPayload(),
]);
}

private static function announcementPayload(): array {
if (class_exists('BotConfig') && method_exists('BotConfig', 'getAppAnnouncement')) {
return BotConfig::getAppAnnouncement();
}
$Channel = (class_exists('BotConfig') && method_exists('BotConfig', 'getChannelUrl'))
? BotConfig::getChannelUrl()
: 'https://t.me/UmbrellaVPN_Channel';
return [
'enabled' => true,
'version' => 1,
'title' => 'به کانال رسمی آمبرلا بپیوندید',
'body' => '☂️ فیلترشکن آمبرلا؛ برای دریافت به روز رسانی ها و اخبار، عضو کانال رسمی تلگرام شوید.',
'button_text' => 'عضویت در کانال رسمی',
'button_url' => $Channel,
'interval_hours' => 168,
'starts_at' => 0,
'updated_at' => 0,
];
}

private static function promoAnnouncementPayload(): array {
if (class_exists('BotConfig') && method_exists('BotConfig', 'getPromoAnnouncement')) {
$Promo = BotConfig::getPromoAnnouncement();
unset($Promo['image_file_id']);
return $Promo;
}
return [
'enabled' => false,
'version' => 1,
'title' => 'پیشنهاد ویژه آمبرلا',
'body' => '',
'image_url' => '',
'button_text' => 'مشاهده جزئیات',
'button_url' => '',
'interval_hours' => 24,
'starts_at' => 0,
'updated_at' => 0,
];
}

private static function announcement(): void {
$Channel = (class_exists('BotConfig') && method_exists('BotConfig', 'getChannelUrl'))
? BotConfig::getChannelUrl()
: 'https://t.me/UmbrellaVPN_Channel';
self::ok([
'announcement' => self::announcementPayload(),
'promo_announcement' => self::promoAnnouncementPayload(),
'channel_url' => $Channel,
'checked_at' => gmdate('c'),
]);
}

private static function promoImage(): void {
$Key = strtolower(trim((string)($_GET['k'] ?? '')));
$Media = (class_exists('BotConfig') && method_exists('BotConfig', 'getPromoImageMedia'))
? BotConfig::getPromoImageMedia($Key)
: null;
if ($Media === null || ($Media['bytes'] ?? '') === '') {
http_response_code(404);
header('Content-Type: application/json; charset=UTF-8');
echo json_encode(['ok' => false, 'error' => 'image_not_found'], self::JSON_FLAGS);
return;
}
if (function_exists('header_remove')) {
@header_remove('Cache-Control');
}
header('Content-Type: ' . (string)$Media['mime']);
header('Cache-Control: public, max-age=86400');
header('X-Content-Type-Options: nosniff');
header('Content-Length: ' . strlen((string)$Media['bytes']));
echo (string)$Media['bytes'];
}

private static function securityAlert(array $Body): void {
self::ok(self::processSecurityAlert($Body));
}

private static function processSecurityAlert(array $Body): array {
$Token = trim((string)($Body['token'] ?? self::bearer()));
$RawDeviceId = trim((string)($Body['device_id'] ?? ''));
$DeviceName = trim((string)($Body['device_name'] ?? ''));
$Platform = trim((string)($Body['platform'] ?? ''));
$RawThreats = is_array($Body['threats'] ?? null) ? $Body['threats'] : [];
$RawNeutralized = is_array($Body['neutralized'] ?? null) ? $Body['neutralized'] : [];
$RawResolved = is_array($Body['resolved_keys'] ?? null) ? $Body['resolved_keys'] : [];

$Db = Database::getInstance();
$Session = $Token !== '' ? self::sessionRow($Token) : null;
$EffectiveDeviceId = $Session !== null
? (string)($Session['Device_ID'] ?? '')
: self::safeDeviceId($RawDeviceId);

if ($EffectiveDeviceId === '') {
self::fail(422, 'invalid_device', 'شناسه دستگاه ارسال نشد.');
}

$UUID = trim((string)($Session['User_UUID'] ?? ''));
$TelegramId = (int)($Session['Telegram_ID'] ?? 0);
$DeviceRow = $Db->fetch(
'SELECT `ID`, `Device_ID`, `User_UUID`, `Telegram_ID`, `Device_Name`, `Platform`, `Is_Trusted` FROM `App_Devices` WHERE `Device_ID` = ? LIMIT 1',
[$EffectiveDeviceId]
);

if ($Session === null) {
if ($DeviceRow === null || (int)($DeviceRow['Is_Trusted'] ?? 0) !== 1) {
return [
'stored' => 0,
'notified' => false,
'new_threats' => 0,
'neutralized_count' => 0,
'reason' => 'unlinked_device',
];
}
if ($UUID === '') {
$UUID = trim((string)($DeviceRow['User_UUID'] ?? ''));
}
if ($TelegramId <= 0) {
$TelegramId = (int)($DeviceRow['Telegram_ID'] ?? 0);
}
}

if ($TelegramId <= 0 && $UUID !== '' && $UUID !== '_') {
$TelegramId = self::autoLinkTelegramOwner($EffectiveDeviceId, $UUID, 0);
if ($TelegramId <= 0) {
$LinkedUser = self::resolveBotUser($UUID, 0);
$TelegramId = (int)($LinkedUser['Telegram_ID'] ?? 0);
}
}

if ($DeviceName === '' && $DeviceRow !== null) {
$DeviceName = trim((string)($DeviceRow['Device_Name'] ?? ''));
}
if ($Platform === '' && $DeviceRow !== null) {
$Platform = trim((string)($DeviceRow['Platform'] ?? ''));
}
self::storeSecurityDeviceState($EffectiveDeviceId, $Body);

$Now = time();
$Cooldown = 86400; // 24 hours per active threat key per device to prevent spam
$NeutralizedCooldown = 300; // 5 minutes for auto-deleted/blocked download or link alerts
$AllowedCategories = [
'malware',
'conflicting_vpn',
'adware',
'suspicious',
'malicious_download',
'malicious_link',
];

$ResolvedKeys = [];
foreach ($RawResolved as $RK) {
$CleanKey = mb_substr(trim((string)$RK), 0, 180);
if ($CleanKey !== '') {
$ResolvedKeys[] = $CleanKey;
}
}
if ($ResolvedKeys !== []) {
$Marks = implode(',', array_fill(0, count($ResolvedKeys), '?'));
$Db->execute(
"UPDATE `App_Security_Alerts` SET `Resolved` = 1 WHERE `Device_ID` = ? AND `Threat_Key` IN ({$Marks})",
array_merge([$EffectiveDeviceId], $ResolvedKeys)
);
}

$NormalizedThreats = [];
$SeenKeys = [];
foreach ($RawThreats as $Item) {
if (!is_array($Item)) {
continue;
}
$Key = mb_substr(trim((string)($Item['key'] ?? '')), 0, 180);
$Name = mb_substr(trim(Helper::stripZwnj((string)($Item['name'] ?? ''))), 0, 180);
if ($Key === '' || $Name === '' || isset($SeenKeys[$Key])) {
continue;
}
$SeenKeys[$Key] = true;
$Category = strtolower(trim((string)($Item['category'] ?? 'malware')));
if (!in_array($Category, $AllowedCategories, true)) {
$Category = 'malware';
}
$Severity = strtolower(trim((string)($Item['severity'] ?? 'high')));
if (!in_array($Severity, ['critical', 'high', 'medium', 'low'], true)) {
$Severity = 'high';
}
$Target = mb_substr(trim((string)($Item['target'] ?? '')), 0, 240);
$Detail = mb_substr(trim(Helper::stripZwnj((string)($Item['detail'] ?? ''))), 0, 240);
$NormalizedThreats[] = [
'key' => $Key,
'name' => $Name,
'category' => $Category,
'severity' => $Severity,
'target' => $Target,
'detail' => $Detail,
];
}

$NormalizedNeutralized = [];
$SeenNeutralized = [];
foreach ($RawNeutralized as $Item) {
if (!is_array($Item)) {
continue;
}
$Key = mb_substr(trim((string)($Item['key'] ?? '')), 0, 180);
$Name = mb_substr(trim(Helper::stripZwnj((string)($Item['name'] ?? ''))), 0, 180);
if ($Key === '' || $Name === '' || isset($SeenNeutralized[$Key])) {
continue;
}
$SeenNeutralized[$Key] = true;
$Category = strtolower(trim((string)($Item['category'] ?? 'malicious_download')));
if (!in_array($Category, $AllowedCategories, true)) {
$Category = 'malicious_download';
}
$Severity = strtolower(trim((string)($Item['severity'] ?? 'high')));
if (!in_array($Severity, ['critical', 'high', 'medium', 'low'], true)) {
$Severity = 'high';
}
$Action = strtolower(trim((string)($Item['action'] ?? 'deleted')));
if (!in_array($Action, ['deleted', 'blocked_connection', 'blocked_url', 'quarantined'], true)) {
$Action = 'deleted';
}
$Target = mb_substr(trim((string)($Item['target'] ?? '')), 0, 240);
$Detail = mb_substr(trim(Helper::stripZwnj((string)($Item['detail'] ?? ''))), 0, 240);
$NormalizedNeutralized[] = [
'key' => $Key,
'name' => $Name,
'category' => $Category,
'severity' => $Severity,
'action' => $Action,
'target' => $Target,
'detail' => $Detail,
];
}

if (!empty($Body['sync_all'])) {
if ($NormalizedThreats === []) {
$Db->execute('UPDATE `App_Security_Alerts` SET `Resolved` = 1 WHERE `Device_ID` = ?', [$EffectiveDeviceId]);
} else {
$ActiveKeys = array_column($NormalizedThreats, 'key');
$Marks = implode(',', array_fill(0, count($ActiveKeys), '?'));
$Db->execute(
"UPDATE `App_Security_Alerts` SET `Resolved` = 1 WHERE `Device_ID` = ? AND `Threat_Key` NOT IN ({$Marks})",
array_merge([$EffectiveDeviceId], $ActiveKeys)
);
}
}

$ToNotify = [];
$ToNotifyNeutralized = [];
$StoredCount = 0;
foreach ($NormalizedThreats as $Threat) {
$Existing = $Db->fetch(
'SELECT `ID`, `Last_Notified_At`, `Resolved` FROM `App_Security_Alerts` WHERE `Device_ID` = ? AND `Threat_Key` = ? LIMIT 1',
[$EffectiveDeviceId, $Threat['key']]
);
$ShouldNotify = $Existing === null
|| (int)($Existing['Resolved'] ?? 0) === 1
|| (int)($Existing['Last_Notified_At'] ?? 0) <= 0
|| ($Now - (int)($Existing['Last_Notified_At'] ?? 0)) >= $Cooldown;

$Db->execute(
'INSERT INTO `App_Security_Alerts`
(`Device_ID`, `User_UUID`, `Telegram_ID`, `Threat_Key`, `Threat_Name`, `Category`, `Severity`, `Target`, `First_Detected_At`, `Last_Detected_At`, `Last_Notified_At`, `Hit_Count`, `Resolved`)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 1, 0)
ON DUPLICATE KEY UPDATE
`User_UUID` = COALESCE(NULLIF(VALUES(`User_UUID`), \'\'), `User_UUID`),
`Telegram_ID` = COALESCE(NULLIF(VALUES(`Telegram_ID`), 0), `Telegram_ID`),
`Threat_Name` = VALUES(`Threat_Name`),
`Category` = VALUES(`Category`),
`Severity` = VALUES(`Severity`),
`Target` = VALUES(`Target`),
`Last_Detected_At` = VALUES(`Last_Detected_At`),
`Hit_Count` = `Hit_Count` + 1,
`Resolved` = 0',
[
$EffectiveDeviceId,
$UUID !== '' ? $UUID : null,
$TelegramId > 0 ? $TelegramId : null,
$Threat['key'],
$Threat['name'],
$Threat['category'],
$Threat['severity'],
$Threat['target'],
$Now,
$Now,
]
);
$StoredCount++;
if ($ShouldNotify) {
$ToNotify[] = $Threat;
}
}

foreach ($NormalizedNeutralized as $Item) {
if (isset($SeenKeys[$Item['key']])) {
continue;
}
$Existing = $Db->fetch(
'SELECT `ID`, `Last_Notified_At`, `Resolved` FROM `App_Security_Alerts` WHERE `Device_ID` = ? AND `Threat_Key` = ? LIMIT 1',
[$EffectiveDeviceId, $Item['key']]
);
$ShouldNotify = $Existing === null
|| (int)($Existing['Last_Notified_At'] ?? 0) <= 0
|| ($Now - (int)($Existing['Last_Notified_At'] ?? 0)) >= $NeutralizedCooldown;

$Db->execute(
'INSERT INTO `App_Security_Alerts`
(`Device_ID`, `User_UUID`, `Telegram_ID`, `Threat_Key`, `Threat_Name`, `Category`, `Severity`, `Target`, `First_Detected_At`, `Last_Detected_At`, `Last_Notified_At`, `Hit_Count`, `Resolved`)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 1, 0)
ON DUPLICATE KEY UPDATE
`User_UUID` = COALESCE(NULLIF(VALUES(`User_UUID`), \'\'), `User_UUID`),
`Telegram_ID` = COALESCE(NULLIF(VALUES(`Telegram_ID`), 0), `Telegram_ID`),
`Threat_Name` = VALUES(`Threat_Name`),
`Category` = VALUES(`Category`),
`Severity` = VALUES(`Severity`),
`Target` = VALUES(`Target`),
`Last_Detected_At` = VALUES(`Last_Detected_At`),
`Hit_Count` = `Hit_Count` + 1,
`Resolved` = 1',
[
$EffectiveDeviceId,
$UUID !== '' ? $UUID : null,
$TelegramId > 0 ? $TelegramId : null,
$Item['key'],
$Item['name'],
$Item['category'],
$Item['severity'],
$Item['target'],
$Now,
$Now,
]
);
$StoredCount++;
if ($ShouldNotify) {
$ToNotifyNeutralized[] = $Item;
}
}

if ($NormalizedNeutralized !== []) {
$NeutralizedKeys = array_column($NormalizedNeutralized, 'key');
$Marks = implode(',', array_fill(0, count($NeutralizedKeys), '?'));
$Db->execute(
"UPDATE `App_Security_Alerts` SET `Resolved` = 1 WHERE `Device_ID` = ? AND `Threat_Key` IN ({$Marks})",
array_merge([$EffectiveDeviceId], $NeutralizedKeys)
);
}

$Notified = false;
if (($ToNotify !== [] || $ToNotifyNeutralized !== []) && $TelegramId > 0) {
$User = Repository::getUser($TelegramId);
$ChatId = (int)($User['Chat_ID'] ?? 0);
if ($ChatId <= 0) {
$ChatId = $TelegramId;
}
$UserName = trim((string)($User['Full_Name'] ?? ($User['First_Name'] ?? 'کاربر')));
if ($UserName === '') {
$UserName = 'کاربر';
}
$PlatLabel = method_exists('Helper', 'formatPlatform') ? Helper::formatPlatform($Platform) : ($Platform !== '' ? $Platform : 'دستگاه');
$DevLabel = $DeviceName !== '' ? $DeviceName . ' (' . $PlatLabel . ')' : $PlatLabel;
$TimeLabel = method_exists('Helper', 'formatPersianDate') ? Helper::formatPersianDate($Now, true) : gmdate('Y-m-d H:i', $Now);

$MsgLines = [
Helper::frame('کاربر', $UserName, 'هشدار امنیتی دستگاه', $TelegramId),
'🛡 <b>گزارش فوری سپر امنیتی آمبرلا</b>',
'💻 دستگاه: <b>' . self::supportEsc($DevLabel) . '</b>',
'🕒 زمان: <b>' . self::supportEsc($TimeLabel) . '</b>',
];

if ($ToNotifyNeutralized !== []) {
$MsgLines[] = '';
$MsgLines[] = '✅ <b>موارد خطرناک زیر شناسایی و فوراً حذف / مسدود شدند:</b>';
foreach (array_slice($ToNotifyNeutralized, 0, 8) as $Item) {
$ActionPrefix = match($Item['action']) {
'blocked_connection', 'blocked_url' => '🚫 مسدودسازی لینک / دامنه تروجانی',
'quarantined' => '🛡 قرنطینه امنیتی فایل',
default => '🗑 حذف خودکار فایل / بدافزار آلوده',
};
$MsgLines[] = '• <b>' . $ActionPrefix . ':</b> ' . self::supportEsc($Item['name']);
if ($Item['target'] !== '') {
$MsgLines[] = '  مسیر/نشانی: <code>' . self::supportEsc(mb_substr($Item['target'], 0, 120)) . '</code>';
}
if ($Item['detail'] !== '') {
$MsgLines[] = '  توضیح: ' . self::supportEsc(mb_substr($Item['detail'], 0, 140));
}
}
if (count($ToNotifyNeutralized) > 8) {
$MsgLines[] = '… و ' . Helper::toPersian((string)(count($ToNotifyNeutralized) - 8)) . ' مورد دیگر';
}
}

if ($ToNotify !== []) {
$MsgLines[] = '';
$MsgLines[] = '⚠️ <b>موارد مخرب یا ناسازگار نیازمند پاکسازی روی دستگاه:</b>';
foreach (array_slice($ToNotify, 0, 8) as $Item) {
$CatText = match($Item['category']) {
'conflicting_vpn' => 'فیلترشکن ناسازگار / رقیب',
'adware' => 'تبلیغ افزار مزاحم',
'suspicious' => 'فایل یا سرویس مشکوک',
'malicious_download' => 'فایل دانلودی آلوده',
'malicious_link' => 'لینک تروجانی / فیشینگ',
default => 'بدافزار / ابزار مخرب',
};
$MsgLines[] = '• <b>' . self::supportEsc($Item['name']) . '</b> (' . $CatText . ')';
if ($Item['target'] !== '') {
$MsgLines[] = '  مسیر/شناسه: <code>' . self::supportEsc(mb_substr($Item['target'], 0, 120)) . '</code>';
}
}
if (count($ToNotify) > 8) {
$MsgLines[] = '… و ' . Helper::toPersian((string)(count($ToNotify) - 8)) . ' مورد دیگر';
}
$MsgLines[] = '';
$MsgLines[] = '🔒 برای محافظت از امنیت حساب و جلوگیری از تداخل شبکه، اتصال آمبرلا تا پاکسازی موارد فعال بالا مسدود است. از بخش <b>سپر امنیتی</b> داخل برنامه آمبرلا نسبت به حذف اقدام کنید.';
}

$Message = implode("\n", $MsgLines);
try {
if (TelegramClient::sendReadableMessage($ChatId, null, $Message, TelegramClient::inlineKeyboard([
[['text' => '🛡گزارش کامل سپر امنیتی', 'callback_data' => 'user_security_shield']],
Menu::userHome(),
]))) {
$Notified = true;
}
} catch (Throwable $Error) {
error_log('[Umbrella-Bot][SecurityAlert] telegram send failed: ' . $Error->getMessage());
}

if ($Notified) {
$NotifiedKeys = array_values(array_unique(array_merge(
array_column($ToNotify, 'key'),
array_column($ToNotifyNeutralized, 'key')
)));
if ($NotifiedKeys !== []) {
$Marks = implode(',', array_fill(0, count($NotifiedKeys), '?'));
$Db->execute(
"UPDATE `App_Security_Alerts` SET `Last_Notified_At` = ? WHERE `Device_ID` = ? AND `Threat_Key` IN ({$Marks})",
array_merge([$Now, $EffectiveDeviceId], $NotifiedKeys)
);
}
}
}

return [
'stored' => $StoredCount,
'new_threats' => count($ToNotify),
'neutralized_count' => count($ToNotifyNeutralized),
'notified' => $Notified,
];
}

/*
 * Deployment health check, safe to expose: booleans and statuses only, never
 * values, paths or SQL text. The signing key is generated automatically now,
 * so it cannot be used as a password here; only an operator who put
 * APP_GATEWAY_SECRET in .env gets the extra ?key= gate, and a server whose
 * .env never uploaded stays diagnosable (which is the whole point).
 */
private static function diag(): void {
$Env_Secret = Environment::getAppGatewaySecret();

if ($Env_Secret !== '') {
$Key = (string)($_GET['key'] ?? '');

if (!hash_equals($Env_Secret, $Key)) {
self::fail(403, 'diag_locked', 'ask the admin for the diag key');
}
}

$Env_File = dirname(__DIR__, 2) . '/.env';

$Out = [
'php' => PHP_VERSION_ID,
'pdo_mysql' => extension_loaded('pdo_mysql'),
'env_file' => is_file($Env_File),
'db_host_set' => Environment::getDatabaseHost() !== '',
'db_name_set' => Environment::getDatabaseName() !== '',
'db_user_set' => Environment::getDatabaseUser() !== '',
'app_secret_set' => AppSecret::get() !== '',
'app_secret_from_env' => AppSecret::fromEnvironment(),
'app_secret_stored' => AppSecret::stored() !== '',
];

try {
Database::getInstance()->fetch('SELECT 1 AS ok');
$Out['db'] = 'ok';
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Gateway-Diag] connect: ' . $Error->getMessage());
$Out['db'] = 'error';
}

try {
$Probe = \ServerClient::listUsers();
$Probe_Status = (int)($Probe['StatusCode'] ?? 0);
$Out['panel'] = ($Probe_Status > 0 && $Probe_Status < 300 && is_array($Probe['Json'] ?? null)) ? 'ok' : 'http_' . $Probe_Status;
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Gateway-Diag] panel probe: ' . $Error->getMessage());
$Out['panel'] = 'error';
}

if ($Out['db'] === 'ok') {
try {
$Row = Database::getInstance()->fetch("SHOW TABLES LIKE 'App_SignIn_Requests'");
$Out['signin_table'] = $Row ? 'ok' : 'missing';
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Gateway-Diag] table: ' . $Error->getMessage());
$Out['signin_table'] = 'error';
}
}

self::ok($Out);
}

// ── helpers ────────────────────────────────────────────────────────────────

/** Global ceiling on OTP SMS sends per hour — see start(). */
private static function otpGlobalCapReached(): bool {
$Max = Environment::getAppOtpMaxHourly();

if ($Max <= 0) return false;
$Bucket = 'app_otp_hour_' . date('YmdH');
return (int)Repository::getSetting($Bucket, 0) >= $Max;
}

private static function otpGlobalCapIncrement(): void {
$Max = Environment::getAppOtpMaxHourly();

if ($Max <= 0) return;
$Bucket = 'app_otp_hour_' . date('YmdH');
Repository::setSetting($Bucket, (string)((int)Repository::getSetting($Bucket, 0) + 1));
}

/**
 * Flips the request to awaiting_telegram and asks the person, in the bot, to
 * confirm the device. On Telegram delivery failure the stage is rolled back
 * to $Rollback_Stage so the app is never stranded on a message that never
 * arrived. Returns true when the confirmation was delivered.
 */
private static function sendConfirmation(array $Row, int $Telegram_Id, string $Rollback_Stage): bool {
$Challenge = (string)$Row['Challenge'];

try {
// Never revive a request cancelled while this message was being prepared.
$Changed = Database::getInstance()->execute(
'UPDATE `App_SignIn_Requests` SET `Stage` = ?, `Confirmed_At` = ? WHERE `Challenge` = ? AND `Stage` = ?',
['awaiting_telegram', time(), $Challenge, $Rollback_Stage === 'needs_telegram' ? 'awaiting_telegram' : $Rollback_Stage]
)->rowCount();
if ($Changed === 0) return false;
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Gateway] stage flip failed for ' . $Challenge . ': ' . $Error->getMessage());
return false;
}

try {
TelegramClient::sendSystemMessage(
$Telegram_Id,
self::deviceMessage($Row),
TelegramClient::inlineKeyboard([[
['text' => '✅ خودم بودم', 'callback_data' => 'app_approve:' . $Challenge],
['text' => '⛔️ نبودم', 'callback_data' => 'app_deny:' . $Challenge],
]])
);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Gateway] confirmation message failed: ' . $Error->getMessage());

try {
Database::getInstance()->execute(
'UPDATE `App_SignIn_Requests` SET `Stage` = ? WHERE `Challenge` = ? AND `Stage` = ?',
[$Rollback_Stage, $Challenge, 'awaiting_telegram']
);
}

catch (Throwable) {
}

return false;
}

Repository::logAdminAction(
0,
'app_signin_pending',
null,
'device=' . $Row['Device_ID'] . ' phone=' . $Row['Phone'],
self::clientIp()
);

return true;
}

/** Finds the panel account for a phone, creating one when the person is new. */
private static function resolveAccount(string $Phone, string $Full_Name, int $Telegram_Id = 0, array $Device_Meta = []): array {
[$Account] = self::findCustomerAccount($Phone);

if (is_array($Account) && $Account !== []) {
$Existing_UUID = trim((string)($Account['uuid'] ?? ''));
if ($Existing_UUID !== '' && !self::isMeaningfulName((string)($Account['name'] ?? '')) && self::isMeaningfulName($Full_Name)) {
try {
$UpdatedName = PanelClient::update($Existing_UUID, ['name' => $Full_Name]);
if (is_array($UpdatedName) && !empty($UpdatedName['name'])) {
$Account['name'] = $UpdatedName['name'];
} else {
$Account['name'] = $Full_Name;
}
} catch (Throwable) {}
}
if ($Existing_UUID !== '' && $Telegram_Id > 0) {
self::syncBotUserClientId($Telegram_Id, $Existing_UUID);
self::syncLinkedBotUserFromPanel($Existing_UUID, $Telegram_Id, $Account);
}
return $Account;
}

if (PanelClient::lastListError() !== null) {
error_log('[Umbrella-Bot][Gateway] panel list degraded during resolveAccount; no local UUID found for masked-' . substr(md5($Phone), 0, 8) . ', attempting create: ' . PanelClient::lastListError());
}

// This panel has no `phone` field — it stores the mobile in `comment` and the
// numeric Telegram id in `telegram_id`.
$Created = PanelClient::create([
'name' => $Full_Name !== '' ? $Full_Name : 'کاربر آمبرلا',
'comment' => $Phone,
'telegram_id' => max(0, $Telegram_Id),
'usage_limit_GB' => self::FREE_PLAN_GB,
'package_days' => self::FREE_PLAN_DAYS,
'is_active' => true,
'enable' => true,
]);

if ($Created === null) {
error_log('[Umbrella-Bot][Gateway] account creation failed for ' . $Phone);
return [];
}

$New_UUID = trim((string)($Created['uuid'] ?? ''));

if ($New_UUID !== '') {
try {
Repository::setSetting('App_Free_Claimed_' . $New_UUID, '1');
}
catch (Throwable $Error) {
error_log('[Umbrella-Bot][Gateway] automatic free plan marker failed for masked-' . substr(md5($Phone), 0, 8) . ': ' . $Error->getMessage());
}
}

if ($Telegram_Id > 0 && $New_UUID !== '') {
self::syncBotUserClientId($Telegram_Id, $New_UUID);
try { Repository::updateUser($Telegram_Id, ['Free_Plan_Claimed' => 1]); }
catch (Throwable $Error) { error_log('[Umbrella-Bot][Gateway] automatic free plan user flag failed: ' . $Error->getMessage()); }
if ((int)($Created['telegram_id'] ?? 0) !== $Telegram_Id) {
try { PanelClient::update($New_UUID, ['telegram_id' => $Telegram_Id]); }
catch (Throwable $Error) { error_log('[Umbrella-Bot][Gateway] telegram_id link after create failed for ' . $Phone . ': ' . $Error->getMessage()); }
}
self::syncLinkedBotUserFromPanel($New_UUID, $Telegram_Id, $Created);
}

Repository::addNotification(null, 'app_signup', 'حساب جدید ساخته شد', $Phone . ' - ' . $Full_Name);
self::notifyAdminNewAppSignup($Created, $Phone, $Full_Name, $Telegram_Id, $Device_Meta);
return $Created;
}

/** Keeps Users.Client_ID linked when an app-created account joins the bot. */
private static function syncBotUserClientId(int $Telegram_Id, string $UUID): void {
if ($Telegram_Id <= 0 || $UUID === '') return;

try {
Database::getInstance()->execute(
"UPDATE `Users` SET `Client_ID` = ? WHERE `Telegram_ID` = ? AND (`Client_ID` IS NULL OR `Client_ID` = '' OR `Client_ID` = '_')",
[$UUID, $Telegram_Id]
);
}
catch (Throwable $Error) {
error_log('[Umbrella-Bot][Gateway] Users.Client_ID sync failed: ' . $Error->getMessage());
}
}

/**
 * Notifies bot administrator(s) immediately when a brand-new customer signs up
 * through the Windows or Android app and receives the automatic 1-time free plan.
 */
private static function notifyAdminNewAppSignup(
array $Account,
string $Phone,
string $Full_Name,
int $Telegram_Id = 0,
array $Device_Meta = []
): void {
try {
$Admin_Ids = self::administratorTelegramIds();
if ($Admin_Ids === []) return;

$Display_Name = self::isMeaningfulName($Full_Name)
? $Full_Name
: trim((string)($Account['name'] ?? ''));
if (!self::isMeaningfulName($Display_Name)) {
$Display_Name = 'کاربر جدید آمبرلا';
}
$UUID = trim((string)($Account['uuid'] ?? ''));
$Platform_Raw = trim((string)($Device_Meta['platform'] ?? ''));
$Platform_Fa = $Platform_Raw !== ''
? (method_exists('Helper', 'formatPlatform') ? Helper::formatPlatform($Platform_Raw) : $Platform_Raw)
: 'اپلیکیشن آمبرلا';
$Device_Name = trim((string)($Device_Meta['device_name'] ?? ''));
$App_Version = trim((string)($Device_Meta['app_version'] ?? ''));
$Ip = trim((string)($Device_Meta['ip'] ?? self::clientIp()));
$Usage_GB = (float)($Account['usage_limit_GB'] ?? self::FREE_PLAN_GB);
$Days = (int)($Account['package_days'] ?? self::FREE_PLAN_DAYS);
$Gb_Fa = Helper::toPersian(rtrim(rtrim(number_format($Usage_GB, 2, '.', ''), '0'), '.'));
$Days_Fa = Helper::toPersian((string)$Days);
$Now_Label = method_exists('Helper', 'formatPersianDate')
? Helper::formatPersianDate(time(), true)
: Helper::toPersian(gmdate('Y-m-d H:i'));
$Tg_Label = $Telegram_Id > 0
? ('متصل (<code>' . Helper::toPersian((string)$Telegram_Id) . '</code>)')
: 'در انتظار اولین اتصال ربات';
$Admin_Name = (string)(Repository::getSetting('Admin_Full_Name') ?: Environment::getAdminFullName());

foreach ($Admin_Ids as $Admin_Id) {
$Lines = [
Helper::adminGreetingNamed($Admin_Name, 'ثبت نام کاربر جدید (اپلیکیشن)', (int)$Admin_Id),
'🎉 <b>اشتراک رایگان کاربر فعال شد</b>',
'🆕 <b>ثبت نام کاربر جدید از طریق برنامه آمبرلا</b>',
'➖➖➖➖➖➖➖➖➖',
'👤 <b>نام و نام خانوادگی:</b> ' . self::supportEsc($Display_Name),
'📱 <b>شماره موبایل:</b> <code>' . self::supportEsc($Phone) . '</code>',
'📲 <b>پلتفرم / نسخه:</b> ' . self::supportEsc($Platform_Fa . ($App_Version !== '' ? ' · نسخه ' . Helper::toPersian($App_Version) : '')),
];
if ($Device_Name !== '') {
$Lines[] = '💻 <b>دستگاه:</b> ' . self::supportEsc($Device_Name);
}
if ($Ip !== '') {
$Lines[] = '🌐 <b>آی پی:</b> <code>' . self::supportEsc($Ip) . '</code>';
}
$Lines[] = "🎁 <b>اشتراک فعال شده:</b> اشتراک رایگان ({$Gb_Fa} گیگابایت · {$Days_Fa} روز)";
$Lines[] = '🤖 <b>حساب تلگرام:</b> ' . $Tg_Label;
if ($UUID !== '') {
$Lines[] = '🆔 <b>شناسه کلاینت:</b> <code>' . self::supportEsc($UUID) . '</code>';
}
$Lines[] = '🕒 <b>زمان ثبت نام:</b> ' . self::supportEsc($Now_Label);
$Lines[] = Helper::adminFooter();

$Markup = class_exists('Menu') && method_exists('Menu', 'adminHome')
? TelegramClient::inlineKeyboard([Menu::adminHome()])
: null;
TelegramClient::sendReadableMessage((int)$Admin_Id, null, implode("\n", $Lines), $Markup);
}
} catch (Throwable $Error) {
error_log('[Umbrella-Bot][Gateway] notifyAdminNewAppSignup failed: ' . $Error->getMessage());
}
}

private static function storeSecurityDeviceState(string $Device_Id, array $Payload): void {
if ($Device_Id === '' || !class_exists('Repository') || !method_exists('Repository', 'setSetting')) return;
$Has_Shield = isset($Payload['security_status'])
|| isset($Payload['scanned_at_ms'])
|| isset($Payload['scanned_files'])
|| isset($Payload['scanned_apps'])
|| isset($Payload['scanned_processes']);
if (!$Has_Shield) return;
try {
$State = [
'status' => trim((string)($Payload['security_status'] ?? 'safe')),
'scanned_at_ms' => (int)($Payload['scanned_at_ms'] ?? (int)($Payload['timestamp'] ?? (time() * 1000))),
'scanned_files' => max(0, (int)($Payload['scanned_files'] ?? 0)),
'scanned_apps' => max(0, (int)($Payload['scanned_apps'] ?? 0)),
'scanned_processes' => max(0, (int)($Payload['scanned_processes'] ?? 0)),
'updated_at' => time(),
];
Repository::setSetting('App_Security_State_' . sha1($Device_Id), json_encode($State, JSON_UNESCAPED_UNICODE));
} catch (Throwable) {}
}

/**
 * Finds the customer for a phone: checks local DB tables first (`Users`,
 * `App_Devices`, `App_SignIn_Requests` — fast and independent of panel list
 * availability), then scans the panel itself (`comment` / `phone`).
 *
 * @return array{0: ?array, 1: string}
 */
private static function findCustomerAccount(string $Phone): array {
$Linked = Repository::findUserByPhone($Phone);
$Client_Id = trim((string)($Linked['Client_ID'] ?? ''));
$Linked_Telegram = (int)($Linked['Telegram_ID'] ?? 0);
$Linked_Name = trim((string)($Linked['Full_Name'] ?? ($Linked['First_Name'] ?? '')));

if ($Client_Id !== '' && $Client_Id !== '_') {
$Account = PanelClient::get($Client_Id);

if (is_array($Account) && $Account !== []) {
return [$Account, 'bot_db'];
}

// If the panel returned anything other than 404 (e.g. transient timeout/5xx),
// keep the known UUID so we never treat an existing customer as brand-new.
if (PanelClient::lastGetStatus() !== 404) {
error_log('[Umbrella-Bot][App-Auth] panel get transient failure for known bot Client_ID; preserving local UUID');
return [[
'uuid' => $Client_Id,
'name' => $Linked_Name,
'telegram_id' => $Linked_Telegram,
], 'bot_db_cached'];
}

error_log('[Umbrella-Bot][App-Auth] Client_ID stored in the bot DB no longer exists (404); falling back to phone scan');
}

// Check previously linked app devices and verified sign-in requests as well,
// covering app-registered users who have not yet opened the Telegram bot.
$Prior_Device = Database::getInstance()->fetch(
"SELECT `User_UUID`, `Telegram_ID` FROM `App_Devices`
WHERE `Phone` = ? AND `User_UUID` IS NOT NULL AND `User_UUID` != ''
ORDER BY `ID` DESC LIMIT 1",
[$Phone]
);
$Prior_Request = $Prior_Device === null ? Database::getInstance()->fetch(
"SELECT `User_UUID`, `Telegram_ID`, `Full_Name` FROM `App_SignIn_Requests`
WHERE `Phone` = ? AND `User_UUID` IS NOT NULL AND `User_UUID` != ''
ORDER BY `ID` DESC LIMIT 1",
[$Phone]
) : null;

$Cached_Row = $Prior_Device ?? $Prior_Request;
$Cached_UUID = trim((string)($Cached_Row['User_UUID'] ?? ''));

if ($Cached_UUID !== '') {
$Account = PanelClient::get($Cached_UUID);

if (is_array($Account) && $Account !== []) {
return [$Account, 'app_db'];
}

if (PanelClient::lastGetStatus() !== 404) {
return [[
'uuid' => $Cached_UUID,
'name' => trim((string)($Cached_Row['Full_Name'] ?? $Linked_Name)),
'telegram_id' => (int)($Cached_Row['Telegram_ID'] ?? $Linked_Telegram),
], 'app_db_cached'];
}
}

$Account = PanelClient::findByPhone($Phone);

if (is_array($Account) && $Account !== []) {
return [$Account, 'panel'];
}

return [null, 'none'];
}

private static function request(string $Challenge): ?array {
if ($Challenge === '') return null;

$Row = Database::getInstance()->fetch(
'SELECT * FROM `App_SignIn_Requests` WHERE `Challenge` = ? LIMIT 1',
[$Challenge]
);

return $Row;
}

private static function requestFromQuery(): ?array {
return self::request(
preg_replace('/[^a-f0-9]/', '', (string)($_GET['challenge'] ?? '')) ?? ''
);
}

private static function sessionRow(string $Token): ?array {
if ($Token === '') return null;

$Row = Database::getInstance()->fetch(
'SELECT `S`.*, `D`.`Is_Trusted` AS `Device_Trusted`
FROM `App_Sessions` AS `S`
LEFT JOIN `App_Devices` AS `D` ON `D`.`Device_ID` = `S`.`Device_ID`
WHERE `S`.`Token_Hash` = ?
LIMIT 1',
[hash('sha256', $Token)]
);

if ($Row === null) return null;

// نشست دستگاهی که از تلگرام لغو شده، روی همه مسیرهای API ممنوع است.
// ابتدا اعتماد دستگاه بررسی می شود تا کد مشخص device_revoked به کلاینت برسد،
// حتی اگر نشست همان لحظه در جدول نشست ها هم باطل شده باشد.
if ((int)($Row['Device_Trusted'] ?? 0) !== 1) {
self::fail(403, 'device_revoked', 'مجوز این دستگاه لغو شده یا حساب پنلی حذف شده است. اتصال فیلترشکن قطع و از حساب خارج می شوید؛ برای استفاده دوباره وارد شوید.');
}

if (($Row['Revoked_At'] ?? null) !== null) return null;
return $Row;
}

private static function issueToken(array $Row): string {
$Token = bin2hex(random_bytes(32));

Database::getInstance()->execute(
'INSERT INTO `App_Sessions` (`Token_Hash`, `User_UUID`, `Device_ID`, `Telegram_ID`, `Last_Used_At`)
VALUES (?, ?, ?, ?, ?)',
[hash('sha256', $Token), (string)$Row['User_UUID'], (string)$Row['Device_ID'], (int)$Row['Telegram_ID'], self::tehranNow()]
);

return $Token;
}

/** The confirmation message: everything needed to judge the request. */
private static function deviceMessage(array $Row): string {
$Name = trim((string)($Row['Full_Name'] ?? ''));
$Device = trim((string)($Row['Device_Name'] ?? 'دستگاه ناشناس'));
$Platform = trim((string)($Row['Platform'] ?? ''));
$IP = trim((string)($Row['IP'] ?? ''));
$Version = trim((string)($Row['App_Version'] ?? ''));
$At = \Helper::formatPersianDate(time(), true);
$Telegram_Id = (int)($Row['Telegram_ID'] ?? 0);

return \Helper::frame('کاربر', $Name, 'فیلترشکن آمبرلا', $Telegram_Id > 0 ? $Telegram_Id : null)
. "🔐 درخواست ورود به فیلترشکن آمبرلا\n"
. "👤 نام: " . ($Name !== '' ? $Name : '—') . "\n"
. "📱 دستگاه: {$Device}\n"
. ($Platform !== '' ? "🖥 سیستم عامل: " . (method_exists('Helper', 'formatPlatform') ? \Helper::formatPlatform($Platform) : $Platform) . "\n" : '')
. ($Version !== '' ? "🏷 نسخه برنامه: " . \Helper::toPersian($Version) . "\n" : '')
. ($IP !== '' ? "🌐 آی پی: " . \Helper::toPersian($IP) . "\n" : '')
. "🕐 زمان: {$At}\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "اگر این درخواست از طرف خودتان است «خودم بودم» را بزنید؛ در غیر این صورت «نبودم» را بزنید تا ورود مسدود شود."
. \Helper::userFooter();
}

/** The notice sent right after a sign-in that did not need a tap. */
private static function signedInMessage(array $Row): string {
$Name = trim((string)($Row['Full_Name'] ?? ''));
$Device = trim((string)($Row['Device_Name'] ?? ''));
$Platform = trim((string)($Row['Platform'] ?? ''));
$IP = trim((string)($Row['IP'] ?? ''));
$Version = trim((string)($Row['App_Version'] ?? ''));
$Telegram_Id = (int)($Row['Telegram_ID'] ?? 0);

return \Helper::frame('کاربر', $Name, 'فیلترشکن آمبرلا', $Telegram_Id > 0 ? $Telegram_Id : null)
. "✅ ورود به فیلترشکن آمبرلا انجام شد\n"
. "👤 نام: " . ($Name !== '' ? $Name : '—') . "\n"
. "📱 دستگاه: " . ($Device !== '' ? $Device : 'دستگاه ناشناس') . "\n"
. ($Platform !== '' ? "🖥 سیستم عامل: " . (method_exists('Helper', 'formatPlatform') ? \Helper::formatPlatform($Platform) : $Platform) . "\n" : '')
. ($Version !== '' ? "🏷 نسخه برنامه: " . \Helper::toPersian($Version) . "\n" : '')
. ($IP !== '' ? "🌐 آی پی: " . \Helper::toPersian($IP) . "\n" : '')
. "🕐 زمان: " . \Helper::formatPersianDate(time(), true) . "\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "تأیید دومرحله ای خاموش است، بنابراین دستگاه بدون پرسش تأیید شد. اگر این ورود از طرف شما نبود، همین حالا از «📱دستگاه من» در منوی خدمات ربات آن دستگاه را حذف کنید و تأیید دومرحله ای را روشن کنید."
. \Helper::userFooter();
}

/**
 * Tells the owner of a number that somebody failed at their door: a wrong code,
 * too many tries, or one device too many. Best-effort and rate-limited — the
 * caller is on its way to fail(), which exits, so nothing here may throw.
 */
private static function notifyFailedLogin(string $Phone, string $Reason, array $Source = [], int $Telegram_Id = 0): void {
try {
if ($Telegram_Id <= 0) {
$Telegram_Id = (int)(Repository::findUserByPhone($Phone)['Telegram_ID'] ?? 0);
}

if ($Telegram_Id <= 0) {
return;
}

// حداکثر یک اعلان خودکار ورود ناموفق در شبانه روز برای هر کاربر.
if (!Repository::claimDailyNotice('app_failed_login', $Telegram_Id)) {
return;
}

$Labels = [
'code_invalid' => 'کد تأیید اشتباه',
'too_many_attempts' => 'تلاش بیش از حد با کد تأیید',
'device_limit' => 'محدودیت تعداد دستگاه',
'expired' => 'پایان زمان تأیید',
];
$Device = trim((string)($Source['Device_Name'] ?? $Source['device_name'] ?? ''));
$Platform = trim((string)($Source['Platform'] ?? $Source['platform'] ?? ''));
$Version = trim((string)($Source['App_Version'] ?? $Source['app_version'] ?? ''));
$Name = trim((string)($Source['Full_Name'] ?? ''));
$IP = trim((string)($Source['IP'] ?? ''));

if ($IP === '') {
$IP = self::clientIp();
}

TelegramClient::sendSystemMessage(
$Telegram_Id,
\Helper::frame('کاربر', $Name, 'فیلترشکن آمبرلا', $Telegram_Id)
. "⚠️ ورود ناموفق به فیلترشکن آمبرلا\n"
. "📱 دستگاه: " . ($Device !== '' ? $Device : 'دستگاه ناشناس') . "\n"
. ($Platform !== '' ? "🖥 سیستم عامل: " . (method_exists('Helper', 'formatPlatform') ? \Helper::formatPlatform($Platform) : $Platform) . "\n" : '')
. ($Version !== '' ? "🏷 نسخه برنامه: " . \Helper::toPersian($Version) . "\n" : '')
. "🌐 آی پی: " . \Helper::toPersian($IP) . "\n"
. "🕐 زمان: " . \Helper::formatPersianDate(time(), true) . "\n"
. "🔎 دلیل: " . ($Labels[$Reason] ?? $Reason) . "\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "**اگر این تلاش از طرف شما نبود، کد تأیید را برای کسی نفرستید و از «📱دستگاه من» در منوی خدمات ربات، دستگاه های ناشناس را حذف کنید.**"
. \Helper::userFooter(),
TelegramClient::inlineKeyboard([[
['text' => '📱 دستگاه من', 'callback_data' => 'app_devices'],
]])
);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Gateway] failed-login notice failed: ' . $Error->getMessage());
}
}

private static function trackDevice(string $Device_Id, array $Body, string $Phone, string $Full_Name = ''): void {
$CleanName = self::isMeaningfulName($Full_Name) ? mb_substr(trim($Full_Name), 0, 190) : '';
Database::getInstance()->execute(
'INSERT INTO `App_Devices`
(`Device_ID`, `Device_Name`, `Full_Name`, `Platform`, `App_Version`, `Phone`, `Last_Seen_At`, `Last_IP`)
VALUES (?, ?, NULLIF(?, \'\'), ?, ?, ?, ?, ?)
ON DUPLICATE KEY UPDATE
`Device_Name` = VALUES(`Device_Name`),
`Full_Name` = COALESCE(NULLIF(`Full_Name`, \'\'), VALUES(`Full_Name`)),
`Platform` = VALUES(`Platform`),
`App_Version` = VALUES(`App_Version`), `Phone` = VALUES(`Phone`),
`Last_Seen_At` = VALUES(`Last_Seen_At`), `Last_IP` = VALUES(`Last_IP`)',
[
$Device_Id,
mb_substr((string)($Body['device_name'] ?? ''), 0, 190),
$CleanName,
mb_substr((string)($Body['platform'] ?? ''), 0, 190),
mb_substr((string)($Body['app_version'] ?? ''), 0, 40),
$Phone,
self::tehranNow(),
self::clientIp(),
]
);
}

private static function tehranNow(): string {
try {
return (new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran')))->format('Y-m-d H:i:s');
} catch (Throwable) {
return gmdate('Y-m-d H:i:s');
}
}

private static function isMeaningfulName(string $Name): bool {
$Stripped = method_exists('Helper', 'stripZwnj') ? \Helper::stripZwnj($Name) : str_replace("\u{200C}", '', $Name);
$Clean = trim(preg_replace('/\s+/u', ' ', $Stripped) ?? $Name);
if ($Clean === '' || $Clean === '_' || $Clean === 'کاربر' || $Clean === 'کاربر آمبرلا') {
return false;
}
return preg_match('/^user-[0-9]+$/i', $Clean) !== 1;
}

private static function resolveBestUserName(string $Candidate = '', string $Phone = '', string $UUID = '', string $DeviceId = '', int $TelegramId = 0): string {
$Stripped = method_exists('Helper', 'stripZwnj') ? \Helper::stripZwnj($Candidate) : str_replace("\u{200C}", '', $Candidate);
$Candidate = trim(preg_replace('/\s+/u', ' ', $Stripped) ?? $Candidate);
if (self::isMeaningfulName($Candidate)) {
return mb_substr($Candidate, 0, 190);
}
try {
$Db = Database::getInstance();
if ($TelegramId > 0) {
$User = Repository::getUser($TelegramId);
$Name = trim((string)($User['Full_Name'] ?? ''));
if (self::isMeaningfulName($Name)) return mb_substr($Name, 0, 190);
}
if ($Phone !== '') {
$User = Repository::findUserByPhone($Phone);
$Name = trim((string)($User['Full_Name'] ?? ''));
if (self::isMeaningfulName($Name)) return mb_substr($Name, 0, 190);
}
if ($UUID !== '' && $UUID !== '_') {
$User = $Db->fetch('SELECT `Full_Name` FROM `Users` WHERE `Client_ID` = ? LIMIT 1', [$UUID]);
$Name = trim((string)($User['Full_Name'] ?? ''));
if (self::isMeaningfulName($Name)) return mb_substr($Name, 0, 190);
}
$DevConds = [];
$DevParams = [];
if ($DeviceId !== '') { $DevConds[] = '`Device_ID` = ?'; $DevParams[] = $DeviceId; }
if ($UUID !== '' && $UUID !== '_') { $DevConds[] = '`User_UUID` = ?'; $DevParams[] = $UUID; }
if ($Phone !== '') { $DevConds[] = '`Phone` = ?'; $DevParams[] = $Phone; }
if ($DevConds !== []) {
$Dev = $Db->fetch(
'SELECT `Full_Name` FROM `App_Devices` WHERE (' . implode(' OR ', $DevConds) . ') AND `Full_Name` IS NOT NULL AND LENGTH(TRIM(`Full_Name`)) > 0 ORDER BY `ID` DESC LIMIT 1',
$DevParams
);
$Name = trim((string)($Dev['Full_Name'] ?? ''));
if (self::isMeaningfulName($Name)) return mb_substr($Name, 0, 190);

$Req = $Db->fetch(
'SELECT `Full_Name` FROM `App_SignIn_Requests` WHERE (' . implode(' OR ', $DevConds) . ') AND `Full_Name` IS NOT NULL AND LENGTH(TRIM(`Full_Name`)) > 0 ORDER BY `ID` DESC LIMIT 1',
$DevParams
);
$Name = trim((string)($Req['Full_Name'] ?? ''));
if (self::isMeaningfulName($Name)) return mb_substr($Name, 0, 190);
}
} catch (Throwable) {}
return '';
}

private static function touchDeviceSeen(string $DeviceId, string $UUID = '', int $TelegramId = 0, string $FullName = '', string $TokenHash = ''): void {
$DeviceId = trim($DeviceId);
if ($DeviceId === '') return;
$NowStr = self::tehranNow();
$CleanName = self::isMeaningfulName($FullName) ? mb_substr(trim($FullName), 0, 190) : '';
$ClientIp = self::clientIp();
try {
Database::getInstance()->execute(
'UPDATE `App_Devices` SET `Last_Seen_At` = ?, '
. '`Last_IP` = COALESCE(NULLIF(?, \'\'), `Last_IP`), '
. '`User_UUID` = CASE WHEN (`User_UUID` IS NULL OR LENGTH(TRIM(`User_UUID`)) = 0) AND ? <> \'\' THEN ? ELSE `User_UUID` END, '
. '`Telegram_ID` = CASE WHEN COALESCE(`Telegram_ID`, 0) <= 0 AND ? > 0 THEN ? ELSE `Telegram_ID` END, '
. '`Full_Name` = CASE WHEN (`Full_Name` IS NULL OR LENGTH(TRIM(`Full_Name`)) = 0) AND ? <> \'\' THEN ? ELSE `Full_Name` END '
. 'WHERE `Device_ID` = ?',
[$NowStr, substr($ClientIp, 0, 45), $UUID, $UUID, $TelegramId, $TelegramId, $CleanName, $CleanName, $DeviceId]
);
} catch (Throwable) {}
if ($TokenHash !== '') {
try {
Database::getInstance()->execute('UPDATE `App_Sessions` SET `Last_Used_At` = ? WHERE `Token_Hash` = ?', [$NowStr, $TokenHash]);
} catch (Throwable) {}
}
}

private static function safeDeviceId(string $Raw): string {
return preg_replace('/[^A-Za-z0-9_-]/', '', $Raw) ?? '';
}

private static function secret(): string {
return AppSecret::get();
}

private static function clientIp(): string {
foreach (['HTTP_CF_CONNECTING_IP', 'HTTP_X_FORWARDED_FOR', 'REMOTE_ADDR'] as $Key) {
$Value = trim((string)($_SERVER[$Key] ?? ''));

if ($Value !== '') {
return mb_substr(explode(',', $Value)[0], 0, 45);
}
}

return '';
}

private static function bearer(): string {
$Header = (string)($_SERVER['HTTP_AUTHORIZATION'] ?? '');

if (str_starts_with($Header, 'Bearer ')) {
return trim(substr($Header, 7));
}

return trim((string)($_GET['token'] ?? ''));
}

private static function botLink(): string {
return BotIdentity::link();
}

/**
 * Personal customer `/sub/` share link — built from the same configured
 * `Subscription_Link_Base` + `<uuid>/sub/` formula as the bot's own subscription
 * menu, never duplicating the UUID and never falling back to public sources.
 */
private static function subscriptionUrl(array $Account, string $Base, string $UUID): string {
$UUID = trim($UUID);
$Direct = trim((string)($Account['subscription_url'] ?? ($Account['sub_link'] ?? '')));

if ($Direct !== '' && str_starts_with($Direct, 'http')) {
if (preg_match('#^(https?://[^/]+)(/.*?)?/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})(?:/.*)?$#', $Direct, $Match) === 1) {
$Prefix = trim((string)($Match[2] ?? ''), '/');
$Target_Uuid = $UUID !== '' ? $UUID : $Match[3];
if ($Prefix !== '' && strtolower($Prefix) !== strtolower($Target_Uuid)) {
return $Match[1] . '/' . $Prefix . '/' . $Target_Uuid . '/sub/';
}
$Base_Path = $Base !== '' ? trim((string)(parse_url($Base, PHP_URL_PATH) ?? ''), '/') : '';
if ($Base_Path !== '' && strtolower($Base_Path) !== strtolower($Target_Uuid)) {
return rtrim($Base, '/') . '/' . $Target_Uuid . '/sub/';
}
return $Match[1] . '/' . $Target_Uuid . '/sub/';
}
return $Direct;
}

if ($Base === '' || $UUID === '') return '';

$Clean_Base = rtrim($Base, '/');
if (str_ends_with(strtolower($Clean_Base), '/' . strtolower($UUID))) {
return $Clean_Base . '/sub/';
}

return $Clean_Base . '/' . $UUID . '/sub/';
}

private static function body(): array {
$Raw = file_get_contents('php://input') ?: '';
if (str_starts_with($Raw, "\xEF\xBB\xBF")) {
$Raw = substr($Raw, 3);
}
$Json = json_decode($Raw, true);

if (is_array($Json)) return $Json;

// Fallback for client networks / WAF rules that block application/json POSTs
// and re-send the JSON envelope inside a standard form-encoded `_json` field.
$Wrapped = $_POST['_json'] ?? ($_GET['_json'] ?? null);
if (is_string($Wrapped) && $Wrapped !== '') {
$Decoded = json_decode($Wrapped, true);
if (is_array($Decoded)) return $Decoded;
}

return array_merge($_GET, $_POST);
}

private static function ok(array $Payload): void {
http_response_code(200);
echo json_encode(self::sanitizePayload($Payload) + ['ok' => true], self::JSON_FLAGS);
exit;
}

private static function fail(int $Status, string $Code, string $Message, array $Extra = []): void {
http_response_code($Status);
$Clean_Message = method_exists('Helper', 'repairMojibake') ? Helper::repairMojibake($Message) : $Message;
if (method_exists('Helper', 'stripZwnj')) $Clean_Message = Helper::stripZwnj($Clean_Message);
if (method_exists('Helper', 'digitsToPersian')) $Clean_Message = Helper::digitsToPersian($Clean_Message);
echo json_encode(
array_merge(['ok' => false, 'error' => $Code, 'message' => $Clean_Message], self::sanitizePayload($Extra)),
self::JSON_FLAGS
);
exit;
}

private static function sanitizePayload(array $Data): array {
if (!method_exists('Helper', 'repairMojibake')) {
return $Data;
}

$Opaque_Keys = [
'token' => true, 'secret' => true, 'challenge' => true, 'device_id' => true,
'uuid' => true, 'sub_url' => true, 'subscription_url' => true, 'account_base' => true,
'content' => true, 'url' => true, 'button_url' => true,
'emergency_url' => true, 'channel_url' => true, 'support_url' => true,
];
$Persian_Prose_Keys = [
'message' => true, 'title' => true, 'body' => true, 'label' => true,
];

foreach ($Data as $Key => $Value) {
if (is_string($Key) && isset($Opaque_Keys[$Key])) continue;

if (is_string($Value)) {
$Clean = Helper::repairMojibake($Value);
if (method_exists('Helper', 'stripZwnj')) $Clean = Helper::stripZwnj($Clean);
if (is_string($Key) && isset($Persian_Prose_Keys[$Key]) && method_exists('Helper', 'digitsToPersian')) {
$Clean = Helper::digitsToPersian($Clean);
}
$Data[$Key] = $Clean;
}

elseif (is_array($Value)) {
$Data[$Key] = self::sanitizePayload($Value);
}
}

return $Data;
}
}
?>
