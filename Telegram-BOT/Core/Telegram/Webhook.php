<?php
declare(strict_types=1);

require_once __DIR__ . '/../../Config/Environment.php';
require_once __DIR__ . '/Telegram.php';
require_once __DIR__ . '/../Storage/Repository.php';

/**
 * ثبت خودکار وبهوک و محافظت از آن، بدون هیچ کلیدی در .env.
 *
 * رویکرد:
 *   • یک secret_token تصادفی (۶۴ کاراکتر هگز) ساخته و در جدول Settings ذخیره
 *     می شود؛ هیچ متغیری در .env لازم نیست.
 *   • نشانی وبهوک از پیکربندی مورداعتماد سرور (یا دامنهٔ canonical) می آید؛
 *     هرگز از Host یا X-Forwarded-Proto درخواست ورودی ساخته نمی شود.
 *   • تا یک ساعت پس از هر ثبت موفق، ثبت دوباره انجام نمی شود و درخواست های
 *     بعدی فقط یک خواندن از جدول Settings دارند.
 *   • Telegram هر به روزرسانی را با هدر X-Telegram-Bot-Api-Secret-Token
 *     امضا می کند و درخواست های بی امضا رد می شوند.
 *
 * کلید و مقدار secret هرگز در لاگ چاپ نمی شوند.
 */
final class Webhook {
private const SECRET_KEY = 'Webhook_Secret';
private const STATE_KEY = 'Webhook_Registration';
private const REFRESH_SECONDS = 3600;
private const DEFAULT_WEBHOOK_URL = 'https://armin-soft.ir/Tools/Telegram-BOT/Umbrella-VPN/index.php';

private static string $Secret = '';
private static bool $Loaded = false;

private function __construct() {
}

/** Secret مشترک با تلگرام؛ اولین بار ساخته و ذخیره می شود. */
public static function secret(): string {
if (self::$Loaded) {
return self::$Secret;
}
self::$Loaded = true;

try {
$Stored = trim((string)Repository::getSetting(self::SECRET_KEY, ''));
}
catch (Throwable $Error) {
$Stored = '';
error_log('[Umbrella-Bot][Webhook] cannot read the stored secret: ' . $Error->getMessage());
}

if (strlen($Stored) < 32) {
try {
$Stored = bin2hex(random_bytes(32));
Repository::setSetting(self::SECRET_KEY, $Stored);
}
catch (Throwable $Error) {
$Stored = '';
error_log('[Umbrella-Bot][Webhook] cannot store the webhook secret: ' . $Error->getMessage());
}
}

self::$Secret = $Stored;
return self::$Secret;
}

/** آیا هدر ارسالی تلگرام با Secret ذخیره شده یکی است؟ */
public static function verify(string $Provided): bool {
$Secret = self::secret();

return $Secret !== '' && $Provided !== '' && hash_equals($Secret, $Provided);
}

/**
 * نشانی وبهوک از پیکربندی مورداعتماد سرور یا دامنهٔ ثابت برنامه.
 * HTTP_HOST و X-Forwarded-Proto ورودی درخواست هستند و نباید مقصد تلگرام را
 * تعیین کنند؛ BOT_WEBHOOK_URL فقط از تنظیمات محیط سرور خوانده می شود.
 */
public static function expectedUrl(): string {
$Url = trim(Environment::get('BOT_WEBHOOK_URL', self::DEFAULT_WEBHOOK_URL));
$Parts = parse_url($Url);

if (!is_array($Parts)
|| strtolower((string)($Parts['scheme'] ?? '')) !== 'https'
|| trim((string)($Parts['host'] ?? '')) === ''
|| isset($Parts['user'])
|| isset($Parts['pass'])
|| isset($Parts['query'])
|| isset($Parts['fragment'])) {
return self::DEFAULT_WEBHOOK_URL;
}

return rtrim($Url, '/');
}

/** ثبت دوره ای وبهوک بدون اجازهٔ تغییر مقصد ذخیره شده. */
public static function ensureRegistered(): void {
self::register(false);
}

/**
 * همگام سازی صریح مقصد وبهوک با پیکربندی سرور؛ فقط از ترمینال سرور مجاز است.
 */
public static function syncFromCli(): void {
if (PHP_SAPI !== 'cli') {
return;
}

self::register(true);
}

/** پیاده سازی داخلی ثبت وبهوک. */
private static function register(bool $AllowUrlChange): void {
$Url = self::expectedUrl();

if ($Url === '') {
return;
}

$Secret = self::secret();

if ($Secret === '') {
return;
}

$Host = (string)parse_url($Url, PHP_URL_HOST);

if ($Host === '' || (filter_var($Host, FILTER_VALIDATE_IP) && !in_array($Host, ['127.0.0.1', '::1'], true))) {
// آدرس مبتنی بر آی پی برای وبهوک تلگرام معتبر نیست.
return;
}

$Fingerprint = hash('sha256', $Url . '|' . $Secret . '|chat-member-v1');
$Now = time();
$State = self::readState();
$Known_Url = (string)($State['url'] ?? '');

if (!$AllowUrlChange && $Known_Url !== '' && $Known_Url !== $Url) {
// درخواست های عادی اجازه تغییر مقصد ثبت شده را ندارند؛ تغییر فقط با CLI صریح است.
return;
}

if (is_array($State)
&& (string)($State['fingerprint'] ?? '') === $Fingerprint
&& ($Now - (int)($State['at'] ?? 0)) < self::REFRESH_SECONDS) {
return;
}

$Info = TelegramClient::call('getWebhookInfo');
$Current = is_array($Info['result'] ?? null) ? $Info['result'] : [];
$Current_Url = (string)($Current['url'] ?? '');

if (is_array($State)
&& (string)($State['fingerprint'] ?? '') === $Fingerprint
&& $Current_Url === $Url) {
self::writeState($Fingerprint, $Url);
return;
}

$Result = TelegramClient::call('setWebhook', [
'url' => $Url,
'secret_token' => $Secret,
'max_connections' => 40,
'drop_pending_updates' => false,
'allowed_updates' => ['message', 'edited_message', 'callback_query', 'chat_member'],
]);

if (($Result['ok'] ?? false) === true) {
self::writeState($Fingerprint, $Url);
return;
}

error_log('[Umbrella-Bot][Webhook] setWebhook failed (' . $Url . '): '
. (string)($Result['description'] ?? 'unknown error'));
}

private static function readState(): array {
try {
$Raw = (string)Repository::getSetting(self::STATE_KEY, '');
}
catch (Throwable) {
return [];
}

if ($Raw === '') {
return [];
}

$State = json_decode($Raw, true);

return is_array($State) ? $State : [];
}

private static function writeState(string $Fingerprint, string $Url): void {
try {
Repository::setSetting(self::STATE_KEY, (string)json_encode([
'fingerprint' => $Fingerprint,
'url' => $Url,
'at' => time(),
]));
}
catch (Throwable $Error) {
error_log('[Umbrella-Bot][Webhook] cannot store the registration state: ' . $Error->getMessage());
}
}
}
