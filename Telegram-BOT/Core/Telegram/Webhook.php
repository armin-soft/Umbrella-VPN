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
 *   • آدرس وبهوک از همان درخواستی که به این فایل می رسد ساخته می شود، پس با
 *     تغییر دامنه هم خودکار به روز می شود.
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
error_log('[Umbrella-Bot][Webhook] generated a new webhook secret.');
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
 * آدرس این فایل روی همین دامنه. مقدار BOT_WEBHOOK_URL در .env (اختیاری) بر
 * تشخیص خودکار اولویت دارد.
 */
public static function expectedUrl(): string {
$Override = trim((string)Environment::get('BOT_WEBHOOK_URL'));

if ($Override !== '') {
return $Override;
}

if (empty($_SERVER['HTTP_HOST'])) {
return '';
}

$Https = (!empty($_SERVER['HTTPS']) && strtolower((string)$_SERVER['HTTPS']) !== 'off')
|| strtolower((string)($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '')) === 'https';

$Path = parse_url((string)($_SERVER['REQUEST_URI'] ?? '/index.php'), PHP_URL_PATH);
$Path = is_string($Path) && $Path !== '' ? $Path : '/index.php';

if (str_ends_with($Path, '/')) {
$Path .= 'index.php';
}

elseif (!str_ends_with(strtolower($Path), '.php')) {
$Path .= '/index.php';
}

return ($Https ? 'https' : 'http') . '://' . (string)$_SERVER['HTTP_HOST'] . $Path;
}

/**
 * ثبت یا به روزرسانی وبهوک در تلگرام.
 *
 * @param bool $AllowUrlChange فقط بازدید مرورگری اجازه دارد آدرس ثبت شده را
 *        عوض کند؛ درخواست های برنامه و API هرگز وبهوک را جابه جا نمی کنند.
 */
public static function ensureRegistered(bool $AllowUrlChange = false): void {
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

$Fingerprint = hash('sha256', $Url . '|' . $Secret);
$Now = time();
$State = self::readState();
$Known_Url = (string)($State['url'] ?? '');

if (!$AllowUrlChange && $Known_Url !== '' && $Known_Url !== $Url) {
// آدرس ثبت شده را فقط یک بازدید واقعی از دامنه می تواند عوض کند.
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
]);

if (($Result['ok'] ?? false) === true) {
self::writeState($Fingerprint, $Url);
error_log('[Umbrella-Bot][Webhook] registered: ' . $Url);
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
