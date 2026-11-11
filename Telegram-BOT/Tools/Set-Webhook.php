<?php
declare(strict_types=1);

/**
 * Register / inspect / delete the Telegram webhook for the bot.
 *
 * This tool works both from the CLI and from the browser:
 *
 *   CLI     php Tools/set-webhook.php info
 *   CLI     php Tools/set-webhook.php https://your-host/index.php
 *   CLI     php Tools/set-webhook.php delete
 *
 *   URL     https://your-host/Tools/set-webhook.php?Key=<KEY>&Action=info
 *   URL     https://your-host/Tools/set-webhook.php?Key=<KEY>&Action=set
 *   URL     https://your-host/Tools/set-webhook.php?Key=<KEY>&Action=set&DropPending=1
 *   URL     https://your-host/Tools/set-webhook.php?Key=<KEY>&Action=delete&Confirm=1
 *
 * <KEY> is WEBHOOK_TOOL_KEY from .env when set, otherwise SCHEDULER_KEY — the
 * same secret the cron URLs (?RunScheduler) use. The tool refuses to do
 * anything without it: this endpoint re-registers the bot's webhook, so an
 * open door would let anyone redirect every message users send to the bot to
 * their own server.
 *
 * «set» without a Url parameter registers the webhook to this installation's
 * own index.php. TELEGRAM_WEBHOOK_SECRET must be set in .env, exactly like
 * index.php expects; after «set», Telegram signs every update and index.php
 * accepts it.
 *
 * Never echoes the secret or the bot token.
 */

require_once dirname(__DIR__) . '/Config/Environment.php';

$Cli = PHP_SAPI === 'cli';
$Telegram_Api = static function (string $Method, array $Payload = []): array {
$Token = \Environment::getBotToken();

if ($Token === '') {
return ['ok' => false, 'description' => 'BOT_TOKEN is missing in .env'];
}

$Ch = curl_init('https://api.telegram.org/bot' . $Token . '/' . $Method);

if ($Payload !== []) {
curl_setopt_array($Ch, [
CURLOPT_POST => true,
CURLOPT_POSTFIELDS => json_encode($Payload, JSON_UNESCAPED_UNICODE),
CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
]);
}

curl_setopt_array($Ch, [CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 30]);
$Raw = curl_exec($Ch);
$Decoded = json_decode((string)$Raw, true);
unset($Ch);

return is_array($Decoded) ? $Decoded : ['ok' => false, 'description' => (string)$Raw];
};

/** The webhook URL for this installation: absolute https URL of index.php. */
$Derive_Webhook_Url = static function (): string {
if (PHP_SAPI === 'cli') {
return '';
}

$Scheme = 'https';
$Host = (string)($_SERVER['HTTP_HOST'] ?? '');

if ($Host === '') {
return '';
}

$Script = (string)($_SERVER['SCRIPT_NAME'] ?? '');
$Path = preg_replace('#/Tools/set-webhook\.php$#', '/index.php', $Script) ?? '';

if ($Path === $Script) {
// The tool lives somewhere unexpected: fall back to the parent of Tools/.
$Path = preg_replace('#/Tools/[^/]*\.php$#', '/index.php', $Script) ?? '';
}

if ($Path === '') {
return '';
}

return $Scheme . '://' . $Host . $Path;
};

/** Validate an https webhook URL; '' cert/port kept, everything else rejected. */
$Valid_Webhook_Url = static function (string $Url): bool {
$Url = trim($Url);

if ($Url === '' || strlen($Url) > 512) {
return false;
}

$Parts = parse_url($Url);

if (!is_array($Parts)) {
return false;
}

if (strtolower((string)($Parts['scheme'] ?? '')) !== 'https') {
return false;
}

if (trim((string)($Parts['host'] ?? '')) === '') {
return false;
}

return true;
};

// ── CLI arguments (kept backwards compatible) ───────────────────────────────
$Cli_Action = 'info';
$Cli_Url = '';
$Cli_Drop_Pending = false;

if ($Cli) {
$Arg = trim((string)($_SERVER['argv'][1] ?? ''));

// Optional second argument «drop»: discard pending updates when (re)registering.
if ((string)($_SERVER['argv'][2] ?? '') === 'drop') {
$Cli_Drop_Pending = true;
}

if ($Arg === 'info' || $Arg === '') {
$Cli_Action = 'info';
}
elseif ($Arg === 'delete') {
$Cli_Action = 'delete';
}
elseif (filter_var($Arg, FILTER_VALIDATE_URL) !== false) {
$Cli_Action = 'set';
$Cli_Url = $Arg;
}
else {
fwrite(STDERR, "Usage: php Tools/set-webhook.php [info|delete|https://host/index.php] [drop]\n");
exit(1);
}
}

// ── browser access control ──────────────────────────────────────────────────
if (!$Cli) {
$Provided = trim((string)($_GET['Key'] ?? ''));
$Key = \Environment::get('WEBHOOK_TOOL_KEY');

if ($Key === '') {
$Key = \Environment::getSchedulerKey();
}

if ($Key === '' || !hash_equals($Key, $Provided)) {
error_log('[Umbrella-Bot][SetWebhook] rejected (' . ($Key === '' ? 'WEBHOOK_TOOL_KEY/SCHEDULER_KEY is not set in .env' : 'wrong key') . ') from ' . ($_SERVER['REMOTE_ADDR'] ?? '-'));
http_response_code(403);
header('Content-Type: text/html; charset=UTF-8');
echo '<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8"><title>Webhook — Forbidden</title></head>'
. '<body style="font-family:Tahoma,sans-serif;max-width:640px;margin:70px auto;line-height:2.1">'
. '<h2>⛔️ دسترسی به این ابزار لازم است کلید معتبر داشته باشد</h2>'
. '<p>این آدرس وبهوک تلگرام را دوباره ثبت یا حذف می‌کند، بنابراین بدون کلید پاسخ نمی‌دهد.</p>'
. '<p>کلید را به‌صورت پارامتر <code>&amp;Key=</code> در URL بفرستید — همان کلیدی که در کرون (<code>?RunScheduler&amp;Key=…</code>) استفاده می‌کنید؛ مقدار <code>WEBHOOK_TOOL_KEY</code> یا (در نبود آن) <code>SCHEDULER_KEY</code> داخل <code>.env</code>.</p>'
. '<pre dir="ltr" style="background:#16191f;color:#e8e8e8;padding:12px 14px;border-radius:8px">Tools/set-webhook.php?Key=CHANGE_ME&amp;Action=info</pre>'
. '</body></html>';
exit;
}
}

// ── resolve the requested action ────────────────────────────────────────────
$Action = $Cli ? $Cli_Action : strtolower(trim((string)($_GET['Action'] ?? 'info')));
$Drop_Pending = $Cli ? $Cli_Drop_Pending : (($_GET['DropPending'] ?? '') === '1');
$Secret = \Environment::get('TELEGRAM_WEBHOOK_SECRET');

// ── run the action ──────────────────────────────────────────────────────────
$Result = null;
$Error = '';

if ($Action === 'info') {
$Result = $Telegram_Api('getWebhookInfo');
}
elseif ($Action === 'set') {
if ($Secret === '') {
$Error = 'TELEGRAM_WEBHOOK_SECRET is missing in .env — the webhook would be registered without a secret again and every update would be rejected. Run: openssl rand -hex 32, set it in .env, then try again.';
}
else {
$Url = $Cli ? $Cli_Url : trim((string)($_GET['Url'] ?? ''));

if ($Url === '' && !$Cli) {
$Url = $Derive_Webhook_Url();
}

if (!$Valid_Webhook_Url($Url)) {
$Error = 'The webhook URL is not a valid https URL: ' . $Url;
}
else {
$Result = $Telegram_Api('setWebhook', [
'url' => $Url,
'secret_token' => $Secret,
'drop_pending_updates' => $Drop_Pending,
'max_connections' => 40,
]);
}
}
}
elseif ($Action === 'delete') {
$Confirmed = $Cli || (($_GET['Confirm'] ?? '') === '1');

if (!$Confirmed) {
$Error = 'Deleting the webhook stops all bot messages from reaching this server. Call again with &Confirm=1 (or &Action=set to re-register).';
}
else {
$Result = $Telegram_Api('deleteWebhook', ['drop_pending_updates' => $Drop_Pending]);
}
}
else {
$Error = 'Unknown action: ' . $Action;
}

// ── output ──────────────────────────────────────────────────────────────────
if ($Cli) {
if ($Error !== '') {
fwrite(STDERR, $Error . "\n");
exit(1);
}
echo json_encode($Result, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE), "\n";
exit((($Result['ok'] ?? false) === true) ? 0 : 1);
}

$Escape = static fn(string $Text): string => htmlspecialchars($Text, ENT_QUOTES, 'UTF-8');
$Key_Query = 'Key=' . rawurlencode($Provided);
$Info = $Action === 'info' && is_array($Result['result'] ?? null) ? $Result['result'] : null;

header('Content-Type: text/html; charset=UTF-8');
echo '<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8">'
. '<meta name="viewport" content="width=device-width, initial-scale=1">'
. '<title>وبهوک ربات آمبرلا</title>'
. '<style>body{font-family:Tahoma,sans-serif;background:#0d1017;color:#e8ecf4;max-width:680px;margin:36px auto;padding:0 18px;line-height:2.1}code{background:#16191f;padding:2px 8px;border-radius:6px;direction:ltr;unicode-bidi:embed}'
. '.card{background:#14171f;border:1px solid #262b38;border-radius:14px;padding:18px 22px;margin:16px 0}.ok{color:#34d399}.bad{color:#fb7185}.btn{display:inline-block;background:#c11127;color:#fff;text-decoration:none;padding:10px 22px;border-radius:10px;margin:6px 0 6px 8px;font-weight:700}.btn.grey{background:#2a2f3d}table{border-collapse:collapse;width:100%}td{padding:6px 4px;border-bottom:1px solid #222836;vertical-align:top}td:first-child{color:#8b93a7;width:44%}'
. '</style></head><body>'
. '<h1>🔗 وبهوک ربات آمبرلا</h1>';

if ($Error !== '') {
echo '<div class="card"><p class="bad">⚠️ ' . $Escape($Error) . '</p></div>';
}

if (is_array($Result)) {
$Ok = ($Result['ok'] ?? false) === true;
echo '<div class="card"><p>' . ($Ok ? '<span class="ok">✅ انجام شد.</span>' : '<span class="bad">❌ خطا از سمت تلگرام.</span>') . '</p>';

if (!$Ok && isset($Result['description'])) {
echo '<p dir="ltr" style="text-align:left;color:#fb7185">' . $Escape((string)$Result['description']) . '</p>';
}

echo '</div>';
}

if ($Info !== null) {
$Url = (string)($Info['url'] ?? '');
$Pending = (int)($Info['pending_update_count'] ?? 0);
$Max_Connections = (string)($Info['max_connections'] ?? '—');
$Last_Error_Date = (int)($Info['last_error_date'] ?? 0);
$Last_Error_Message = (string)($Info['last_error_message'] ?? '');
$Ip = (string)($Info['ip_address'] ?? '');

echo '<div class="card"><table>'
. '<tr><td>آدرس ثبت‌شده</td><td dir="ltr" style="text-align:left">' . $Escape($Url === '' ? '— (وبهوک ثبت نشده است)' : $Url) . '</td></tr>'
. '<tr><td>پیام‌های در انتظار</td><td dir="ltr" style="text-align:left">' . $Escape((string)$Pending) . '</td></tr>'
. '<tr><td>بیشینه اتصالات</td><td dir="ltr" style="text-align:left">' . $Escape($Max_Connections) . '</td></tr>'
. ($Ip !== '' ? '<tr><td>IP مقصد</td><td dir="ltr" style="text-align:left">' . $Escape($Ip) . '</td></tr>' : '')
. ($Last_Error_Date > 0 ? '<tr><td>آخرین خطای تلگرام</td><td dir="ltr" style="text-align:left">' . $Escape(gmdate('Y-m-d H:i:s', $Last_Error_Date) . ' UTC — ' . $Last_Error_Message) . '</td></tr>' : '')
. '</table></div>';
}

$Derived = $Derive_Webhook_Url();
echo '<div class="card"><p><strong>عملیات:</strong></p>'
. '<a class="btn" href="?' . $Escape($Key_Query) . '&amp;Action=set">✅ ثبت/اصلاح وبهوک' . ($Derived !== '' ? ' (روی این سرور)' : '') . '</a>'
. '<a class="btn grey" href="?' . $Escape($Key_Query) . '&amp;Action=set&amp;DropPending=1">🧹 ثبت + حذف پیام‌های در انتظار</a>'
. '<a class="btn grey" href="?' . $Escape($Key_Query) . '&amp;Action=info">🔄 تازه‌سازی وضعیت</a>'
. '<a class="btn grey" href="?' . $Escape($Key_Query) . '&amp;Action=delete&amp;Confirm=1" onclick="return confirm(\'وبهوک حذف شود؟ همه‌ی پیام‌ها از ربات به این سرور نمی‌رسند.\')">🗑 حذف وبهوک</a>'
. ($Derived !== '' ? '<p style="color:#8b93a7">آدرس پیش‌فرض ثبت: <code dir="ltr">' . $Escape($Derived) . '</code></p>' : '')
. '</div>'
. '</body></html>';
exit;
