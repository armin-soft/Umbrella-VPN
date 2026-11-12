<?php
declare(strict_types=1);

require_once __DIR__ . '/../Database/Database.php';
require_once __DIR__ . '/../Database/Schema-App.php';
require_once __DIR__ . '/../Server/Umbrella-Panel.php';
require_once __DIR__ . '/App-Device-Limit.php';
require_once __DIR__ . '/App-Two-Step.php';
require_once __DIR__ . '/App-Secret.php';
require_once __DIR__ . '/../Telegram/Bot-Identity.php';
require_once __DIR__ . '/../SMS/IPPanel.php';
require_once __DIR__ . '/../Telegram/Telegram.php';
require_once __DIR__ . '/../Storage/Repository.php';
require_once __DIR__ . '/App-Filter.php';
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
private const JSON_FLAGS = JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES;
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
if ($Route === 'auth/session') { self::session(); return; }
if ($Route === 'auth/resend') { self::resend(self::body()); return; }
if ($Route === 'auth/signout') { self::signOut(self::body()); return; }
if ($Route === 'auth/device') { self::heartbeat(self::body()); return; }
if ($Route === 'account/refresh') { self::refreshAccount(); return; }
if ($Route === 'filter/save') { self::saveFilter(self::body()); return; }
if ($Route === 'filter/get') { self::getFilter(self::body()); return; }
if ($Route === 'app/notifications') { self::notifications(); return; }
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
$First = trim((string)($Body['first_name'] ?? ''));
$Last = trim((string)($Body['last_name'] ?? ''));
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

error_log('[Umbrella-Bot][App-Auth] start | phone=' . $Phone . ' | exists=' . ($Exists ? '1' : '0') . ' | source=' . $Lookup_Source . ' | panel_rows=' . PanelClient::lastListCount());

// When the panel cannot even be listed we must not conclude «account does
// not exist» — that would mint duplicate accounts and lock existing ones
// out of the app. Say the server is down instead.
if (!$Exists && $List_Error !== null) {
error_log('[Umbrella-Bot][App-Auth] refusing needs-profile while panel list is failing: ' . $List_Error);
self::fail(503, 'panel_unavailable', 'در حال حاضر ارتباط با سرور برقرار نیست؛ کمی بعد دوباره تلاش کنید.');
}

/*
 * ورود دو مرحله‌ای است: اول فقط شماره گرفته می‌شود. اگر این شماره حساب
 * نداشته باشد، بانک‌نامه بدون فرستادن پیامک پاسخ «needs_profile» می‌دهد و
 * برنامه سراغ مرحله «نام و نام خانوادگی» می‌رود؛ ثبت‌نام با همان شماره و
 * همین درخواست کامل می‌شود. شماره‌ای که حساب دارد، مستقیم کد می‌گیرد.
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
$Full_Name = trim((string)($Known['name'] ?? $Known['Name'] ?? ''));
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
self::trackDevice($Device_Id, $Body, $Phone);

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
self::fail(429, 'too_many_attempts', 'تعداد تلاش‌ها زیاد شد؛ کد جدید بگیرید.');
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
$Account = self::resolveAccount($Phone, trim((string)($Row['Full_Name'] ?? '')), $Linked_Telegram);
$UUID = trim((string)($Account['uuid'] ?? ''));

if ($UUID === '') {
error_log('[Umbrella-Bot][App-Auth] verify: panel account creation failed for challenge ' . $Challenge);
self::fail(502, 'panel_unavailable', 'ساخت حساب در پنل ناموفق بود؛ کمی بعد دوباره تلاش کنید.');
}
error_log('[Umbrella-Bot][App-Auth] verify: panel account created for challenge ' . $Challenge);

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

// Without a Telegram link there is nobody to confirm the device, so the bot
// asks the person to open it once. The app shows that instruction; once the
// number is linked — on any later app poll of auth/status — the request is
// promoted to awaiting_telegram and the confirmation is sent then.
if ($Telegram_Id <= 0) {
Database::getInstance()->execute(
'UPDATE `App_SignIn_Requests` SET `Stage` = ?, `Confirmed_At` = ? WHERE `Challenge` = ?',
['needs_telegram', time(), $Challenge]
);

Repository::logAdminAction(
0,
'app_signin_needs_telegram',
null,
'phone=' . $Phone . ' device=' . (string)$Row['Device_ID'],
self::clientIp()
);

self::ok([
'verified' => true,
'challenge' => $Challenge,
'stage' => 'needs_telegram',
'bot' => self::botLink(),
'message' => 'برای تأیید دستگاه، یک‌بار ربات را باز کنید و Start بزنید؛ سپس این صفحه را تازه کنید.',
]);
}

// With two-step switched off in the bot the SMS code is the only factor: the
// device is trusted right away and Telegram gets a notice afterwards instead
// of a question, so the app never sits on the waiting screen.
// When the flip fails the request simply falls through to the question below,
// so a bookkeeping problem can never turn into «cannot sign in».
if (!AppTwoStep::enabled($Telegram_Id) && self::decide($Challenge, true, $Telegram_Id)) {
try {
TelegramClient::sendMessage($Telegram_Id, self::signedInMessage($Row));
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

if ($UUID === '') {
self::fail(409, 'no_account', 'حسابی به این شماره وصل نیست.');
}

$Account = PanelClient::get($UUID) ?? [];

if ($Account === []) {
self::fail(502, 'panel_unavailable', 'دریافت پروفایل از پنل ناموفق بود.');
}

$Token = (string)($Row['Token'] ?? '');

if ($Token === '') {
$Token = self::issueToken($Row);
Database::getInstance()->execute(
'UPDATE `App_SignIn_Requests` SET `Token` = ? WHERE `Challenge` = ?',
[$Token, (string)$Row['Challenge']]
);
}

$Profile = AppFilter::accountPayload($Account);
$Profile['account_base'] = PanelClient::accountBase($Account);

self::ok([
'uuid' => $UUID,
'token' => $Token,
'device_id' => (string)$Row['Device_ID'],
'sign_in_at' => gmdate('c'),
'account' => $Profile,
'filter' => AppFilter::load($UUID),
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

if ($Token !== '') {
$Database->execute(
'UPDATE `App_Sessions` SET `Revoked_At` = ? WHERE `Token_Hash` = ? AND `Revoked_At` IS NULL',
[time(), hash('sha256', $Token)]
);
}

if ($Challenge !== '') {
$Database->execute(
'UPDATE `App_Devices` SET `Is_Trusted` = 0
WHERE `Device_ID` = (SELECT `Device_ID` FROM `App_SignIn_Requests` WHERE `Challenge` = ? LIMIT 1)',
[$Challenge]
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

if ((int)($Row['Expires_At'] ?? 0) > 0 && (int)$Row['Expires_At'] < time()) {
error_log('[Umbrella-Bot][Gateway] decision on an expired challenge ' . $Challenge);
return false;
}

// The stage flip is the one thing the app waits for, so it goes first and its
// failure is reported plainly; every bookkeeping step after it is best-effort
// and may never strand the app on the waiting screen.
try {
Database::getInstance()->execute(
'UPDATE `App_SignIn_Requests` SET `Stage` = ?, `Decided_At` = ? WHERE `Challenge` = ?',
[$Next, time(), $Challenge]
);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Gateway] decision update failed for ' . $Challenge . ': ' . $Error->getMessage());
return false;
}

if ($Approved) {
try {
$Token = self::issueToken($Row);
Database::getInstance()->execute(
'UPDATE `App_SignIn_Requests` SET `Token` = ? WHERE `Challenge` = ?',
[$Token, $Challenge]
);
}

catch (Throwable $Error) {
// auth/session issues a token on demand, so this can never block the sign-in.
error_log('[Umbrella-Bot][Gateway] token issue failed for ' . $Challenge . ': ' . $Error->getMessage());
}

try {
Database::getInstance()->execute(
'UPDATE `App_Devices`
SET `Is_Trusted` = 1, `Last_Seen_At` = ?,
`Telegram_ID` = COALESCE(`Telegram_ID`, ?),
`User_UUID` = CASE WHEN `User_UUID` IS NULL OR `User_UUID` = \'\' THEN ? ELSE `User_UUID` END
WHERE `Device_ID` = ?',
[time(), $Telegram_Id, (string)$Row['User_UUID'], (string)$Row['Device_ID']]
);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Gateway] device trust update failed for ' . $Challenge . ': ' . $Error->getMessage());
}

error_log('[Umbrella-Bot][Gateway] decision ' . ($Approved ? 'approved' : 'denied') . ' for challenge ' . $Challenge . ' from telegram ' . $Telegram_Id);
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

if ($UUID === '') {
self::fail(409, 'no_account', 'حسابی به این نشست وصل نیست.');
}

$Account = PanelClient::get($UUID);

if ($Account === null || $Account === []) {
self::fail(502, 'panel_unavailable', 'دریافت اطلاعات حساب ناموفق بود.');
}

$Profile = AppFilter::accountPayload($Account);
$Base = PanelClient::accountBase($Account);
$Profile['account_base'] = $Base;
$Profile['subscription_url'] = self::subscriptionUrl($Account, $Base, $UUID);

self::ok([
'account' => $Profile,
'filter' => AppFilter::load($UUID),
'checked_at' => gmdate('c'),
]);
}

/** Keeps the device row fresh so «دستگاه‌های من» is never stale. */
private static function heartbeat(array $Body): void {
$Session = self::sessionRow((string)($Body['token'] ?? self::bearer()));

if ($Session === null) {
self::fail(401, 'invalid_token', 'نشست منقضی شده است.');
}

Database::getInstance()->execute(
'UPDATE `App_Devices` SET `Last_Seen_At` = ? WHERE `Device_ID` = ?',
[time(), (string)$Session['Device_ID']]
);

self::ok(['seen_at' => gmdate('c')]);
}

private static function notifications(): void {
$Session = self::sessionRow(self::bearer());

if ($Session === null) {
self::fail(401, 'invalid_token', 'نشست منقضی شده است.');
}

$Rows = Database::getInstance()->fetchAll(
'SELECT `ID`, `Title`, `Body`, `Level`, `Sent_At` FROM `App_Notifications`
WHERE `Delivered_At` IS NULL AND (`Device_ID` = ? OR `User_UUID` = ?)
ORDER BY `ID` ASC LIMIT 20',
[(string)$Session['Device_ID'], (string)$Session['User_UUID']]
);

foreach ($Rows as $Row) {
Database::getInstance()->execute(
'UPDATE `App_Notifications` SET `Delivered_At` = ? WHERE `ID` = ?',
[time(), (int)$Row['ID']]
);
}

self::ok([
'items' => array_map(static fn(array $Row): array => [
'id' => (int)$Row['ID'],
'title' => (string)$Row['Title'],
'body' => (string)($Row['Body'] ?? ''),
'level' => (string)$Row['Level'],
'sent_at' => (string)$Row['Sent_At'],
], $Rows),
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

self::ok(['settings' => AppFilter::save((string)$Session['User_UUID'], $Settings, 'app')]);
}

private static function getFilter(array $Body): void {
$Session = self::sessionRow((string)($Body['token'] ?? self::bearer()));

if ($Session === null) {
self::fail(401, 'invalid_token', 'نشست منقضی شده است.');
}

self::ok(['settings' => AppFilter::load((string)$Session['User_UUID'])]);
}

private static function ping(): void {
self::ok([
'time' => gmdate('c'),
'version' => '2',
'features' => ['signin', 'device_confirm', 'notifications', 'filter'],
]);
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
Database::getInstance()->execute(
'UPDATE `App_SignIn_Requests` SET `Stage` = ?, `Confirmed_At` = ? WHERE `Challenge` = ?',
['awaiting_telegram', time(), $Challenge]
);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Gateway] stage flip failed for ' . $Challenge . ': ' . $Error->getMessage());
return false;
}

try {
TelegramClient::sendMessage(
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
'UPDATE `App_SignIn_Requests` SET `Stage` = ? WHERE `Challenge` = ?',
[$Rollback_Stage, $Challenge]
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
private static function resolveAccount(string $Phone, string $Full_Name, int $Telegram_Id = 0): array {
[$Account] = self::findCustomerAccount($Phone);

if ($Account === null && PanelClient::lastListError() !== null) {
// The list read failed — we cannot tell «new customer» from «panel is
// down», so refuse to create a duplicate account.
error_log('[Umbrella-Bot][Gateway] refusing account creation while panel list is failing: ' . PanelClient::lastListError());
return [];
}

if (is_array($Account) && $Account !== []) {
return $Account;
}

// This panel has no `phone` field — it stores the mobile in `comment` and the
// numeric Telegram id in `telegram_id` (linked right after creation).
$Created = PanelClient::create([
'name' => $Full_Name,
'comment' => $Phone,
]);

if ($Created === null) {
error_log('[Umbrella-Bot][Gateway] account creation failed for ' . $Phone);
return [];
}

if ($Telegram_Id > 0) {
$New_UUID = trim((string)($Created['uuid'] ?? ''));

if ($New_UUID !== '') {
try { PanelClient::update($New_UUID, ['telegram_id' => $Telegram_Id]); }
catch (Throwable $Error) { error_log('[Umbrella-Bot][Gateway] telegram_id link after create failed for ' . $Phone . ': ' . $Error->getMessage()); }
}
}

Repository::addNotification(null, 'app_signup', 'حساب جدید ساخته شد', $Phone . ' - ' . $Full_Name);
return $Created;
}

/**
 * Finds the customer for a phone: the bot's Users row first (it remembers the
 * panel uuid the bot issued, so this works even when the panel list is slow),
 * then the panel itself (matching `comment` or `phone`). Returns the account
 * and where it was found ('bot_db' | 'panel' | 'none').
 *
 * @return array{0: ?array, 1: string}
 */
private static function findCustomerAccount(string $Phone): array {
$Linked = Repository::findUserByPhone($Phone);
$Client_Id = trim((string)($Linked['Client_ID'] ?? ''));

if ($Client_Id !== '' && $Client_Id !== '_') {
$Account = PanelClient::get($Client_Id);

if (is_array($Account) && $Account !== []) {
return [$Account, 'bot_db'];
}

error_log('[Umbrella-Bot][App-Auth] Client_ID stored in the bot DB no longer resolves in the panel; falling back to the phone scan');
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
'SELECT * FROM `App_Sessions` WHERE `Token_Hash` = ? AND `Revoked_At` IS NULL LIMIT 1',
[hash('sha256', $Token)]
);

return $Row;
}

private static function issueToken(array $Row): string {
$Token = bin2hex(random_bytes(32));

Database::getInstance()->execute(
'INSERT INTO `App_Sessions` (`Token_Hash`, `User_UUID`, `Device_ID`, `Telegram_ID`, `Last_Used_At`)
VALUES (?, ?, ?, ?, ?)',
[hash('sha256', $Token), (string)$Row['User_UUID'], (string)$Row['Device_ID'], (int)$Row['Telegram_ID'], time()]
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
. ($Platform !== '' ? "🖥 سیستم‌عامل: {$Platform}\n" : '')
. ($Version !== '' ? "🏷 نسخه برنامه: " . \Helper::toPersian($Version) . "\n" : '')
. ($IP !== '' ? "🌐 IP: " . \Helper::toPersian($IP) . "\n" : '')
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
. ($Platform !== '' ? "🖥 سیستم‌عامل: {$Platform}\n" : '')
. ($Version !== '' ? "🏷 نسخه برنامه: " . \Helper::toPersian($Version) . "\n" : '')
. ($IP !== '' ? "🌐 IP: " . \Helper::toPersian($IP) . "\n" : '')
. "🕐 زمان: " . \Helper::formatPersianDate(time(), true) . "\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "تأیید دومرحله‌ای خاموش است، بنابراین دستگاه بدون پرسش تأیید شد. اگر این ورود از طرف شما نبود، همین حالا از «📱دستگاه من» در پروفایل آن دستگاه را حذف کنید و تأیید دومرحله‌ای را روشن کنید."
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

// Three wrong codes in a row are one event, not three; without this the person
// fumbling their own code would fill their chat with alerts.
$Throttle_Key = 'AppFailNotify_' . $Telegram_Id;

if (time() - (int)Repository::getSetting($Throttle_Key, 0) < 60) {
return;
}

Repository::setSetting($Throttle_Key, time());

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

TelegramClient::sendMessage(
$Telegram_Id,
\Helper::frame('کاربر', $Name, 'فیلترشکن آمبرلا', $Telegram_Id)
. "⚠️ ورود ناموفق به فیلترشکن آمبرلا\n"
. "📱 دستگاه: " . ($Device !== '' ? $Device : 'دستگاه ناشناس') . "\n"
. ($Platform !== '' ? "🖥 سیستم‌عامل: {$Platform}\n" : '')
. ($Version !== '' ? "🏷 نسخه برنامه: " . \Helper::toPersian($Version) . "\n" : '')
. "🌐 IP: " . \Helper::toPersian($IP) . "\n"
. "🕐 زمان: " . \Helper::formatPersianDate(time(), true) . "\n"
. "🔎 دلیل: " . ($Labels[$Reason] ?? $Reason) . "\n"
. "➖➖➖➖➖➖➖➖➖\n"
. "اگر این تلاش از طرف شما نبود، کد تأیید را برای کسی نفرستید و از «📱دستگاه من» در پروفایل، دستگاه‌های ناشناس را حذف کنید."
. \Helper::userFooter()
);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Gateway] failed-login notice failed: ' . $Error->getMessage());
}
}

private static function trackDevice(string $Device_Id, array $Body, string $Phone): void {
Database::getInstance()->execute(
'INSERT INTO `App_Devices`
(`Device_ID`, `Device_Name`, `Platform`, `App_Version`, `Phone`, `Last_Seen_At`, `Last_IP`)
VALUES (?, ?, ?, ?, ?, ?, ?)
ON DUPLICATE KEY UPDATE
`Device_Name` = VALUES(`Device_Name`), `Platform` = VALUES(`Platform`),
`App_Version` = VALUES(`App_Version`), `Phone` = VALUES(`Phone`),
`Last_Seen_At` = VALUES(`Last_Seen_At`), `Last_IP` = VALUES(`Last_IP`)',
[
$Device_Id,
mb_substr((string)($Body['device_name'] ?? ''), 0, 190),
mb_substr((string)($Body['platform'] ?? ''), 0, 190),
mb_substr((string)($Body['app_version'] ?? ''), 0, 40),
$Phone,
time(),
self::clientIp(),
]
);
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
 * The customer share link. The panel reports it for most deployments; when it
 * does not, it is built from the account base and the uuid the same way the
 * bot's own subscription menu builds it.
 */
private static function subscriptionUrl(array $Account, string $Base, string $UUID): string {
$Direct = trim((string)($Account['subscription_url'] ?? ($Account['sub_link'] ?? '')));

if ($Direct !== '') return $Direct;

if ($Base === '' || $UUID === '') return '';

return rtrim($Base, '/') . '/' . $UUID . '/sub/';
}

private static function body(): array {
$Raw = file_get_contents('php://input') ?: '';
$Json = json_decode($Raw, true);

if (is_array($Json)) return $Json;

return array_merge($_GET, $_POST);
}

private static function ok(array $Payload): void {
http_response_code(200);
echo json_encode($Payload + ['ok' => true], self::JSON_FLAGS);
exit;
}

private static function fail(int $Status, string $Code, string $Message, array $Extra = []): void {
http_response_code($Status);
echo json_encode(
array_merge(['ok' => false, 'error' => $Code, 'message' => $Message], $Extra),
self::JSON_FLAGS
);
exit;
}
}
?>
