<?php
declare(strict_types=1);

if (PHP_VERSION_ID < 80200) {
error_log('[Umbrella-Bot][PHP-Version] PHP >= 8.2 is required but the server runs PHP ' . PHP_VERSION . ' in ' . basename(__FILE__) . '. Set the domain PHP version to 8.2 or newer (cPanel MultiPHP Manager).');
http_response_code(503);
header('Content-Type: text/plain; charset=UTF-8');
echo 'PHP 8.2+ is required.';
exit;
}

require_once __DIR__ . '/Bot/Dispatcher.php';
require_once __DIR__ . '/Core/Database/Schema.php';
require_once __DIR__ . '/Config/Environment.php';

header('Content-Type: text/plain; charset=UTF-8');

// Cron endpoints spend real money (auto-renew wallet charges, IPPanel SMS),
// so they must never be reachable without a key. Fail closed: when
// SCHEDULER_KEY is not set in .env, they refuse to run at all — set it and
// add &Key=<value> to the cron URL.
$Scheduler_Guard = static function (): void {
$Key = \Environment::getSchedulerKey();
$Provided = trim((string)($_GET['Key'] ?? ''));

if ($Key !== '' && hash_equals($Key, $Provided)) {
return;
}

http_response_code(403);
header('Content-Type: text/plain; charset=UTF-8');
error_log('[Umbrella-Bot][Scheduler] rejected (' . ($Key === '' ? 'SCHEDULER_KEY is not set in .env' : 'wrong SCHEDULER_KEY') . ') from ' . ($_SERVER['REMOTE_ADDR'] ?? '-'));
echo $Key === ''
? "Forbidden: SCHEDULER_KEY is not configured. Set SCHEDULER_KEY in .env, then add &Key=<value> to the cron URL."
: "Forbidden: invalid Key.";
exit;
};

try {
\Schema::ensureInstalled();
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Schema-AutoInstall] ' . $Error->getMessage());
}

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'GET' && isset($_GET['NightlyDiag'])) {
$Scheduler_Guard();
require_once __DIR__ . '/Bot/Scheduler.php';
header('Content-Type: text/plain; charset=UTF-8');

try {
\Scheduler::diagnoseNightly();
echo "DIAG DONE - see error log for [Nightly-DIAG] lines";
}

catch (Throwable $E) {
error_log('[Umbrella-Bot][Nightly-DIAG] FAILED: ' . $E->getMessage());
echo 'ERR: ' . $E->getMessage();
}

exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'GET' && isset($_GET['RunScheduler'])) {
$Scheduler_Guard();
require_once __DIR__ . '/Bot/Scheduler.php';
$Scheduler_Mode = trim((string)($_GET['RunScheduler'] ?? 'all'));
$Verbose = isset($_GET['Verbose']);

if ($Verbose) {
error_log('[Umbrella-Bot][Scheduler] START mode=' . $Scheduler_Mode . ' phpTimezone=' . date_default_timezone_get()
. ' now=' . (new DateTimeImmutable('now', new DateTimeZone('Asia/Tehran')))->format('Y-m-d H:i'));
}

try {
if ($Verbose && $Scheduler_Mode === 'daily') {
\Scheduler::debugDailyReport();
}

\Scheduler::run($Scheduler_Mode === '' ? 'all' : $Scheduler_Mode);

if ($Verbose) error_log('[Umbrella-Bot][Scheduler] DONE mode=' . $Scheduler_Mode);
echo 'OK';
}

catch (Throwable $E) {
error_log('[Umbrella-Bot][Scheduler] ' . $E->getMessage());
echo 'ERR';
}

exit;
}

require_once __DIR__ . '/Config/Environment.php';
require_once __DIR__ . '/Core/Database/Database.php';
require_once __DIR__ . '/Core/Storage/Repository.php';
require_once __DIR__ . '/Core/Database/Schema-App.php';

// ── The desktop app's API ────────────────────────────────────────────────
// Reached as <this file>/app/<route>, written by the app's login screen and its
// settings page. Handled before anything the bot does, and it never touches the
// webhook path, so the two cannot interfere.
$App_Path = '';

if (isset($_GET['AppApi'])) {
$App_Path = (string)$_GET['AppApi'];
}

elseif (isset($_SERVER['PATH_INFO']) && is_string($_SERVER['PATH_INFO'])) {
$App_Path = trim((string)$_SERVER['PATH_INFO'], '/');

if (str_starts_with($App_Path, 'app/')) {
$App_Path = substr($App_Path, 4);
}
}

if ($App_Path !== '') {
require_once __DIR__ . '/Core/App/App-Gateway.php';

try {
AppSchema::ensureInstalled();
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][App-Schema] ' . $Error->getMessage());
}

\AppGateway::handle($App_Path);
exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'GET' && isset($_GET['Authority'])) {
$Status = strtoupper((string)($_GET['Status'] ?? 'NOK'));
$User_ID = (int)($_GET['Uid'] ?? 0);

try {
\SubscriptionFlow::handleGatewayCallback($User_ID, $Status);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Zarinpal-Callback] ' . $Error->getMessage());
}

$Bot_Username = \Environment::getBotUsername();
$Bot_Link = $Bot_Username !== '' ? 'https://t.me/' . $Bot_Username : 'https://t.me/';
header('Location: ' . $Bot_Link, true, 302);
header('Content-Type: text/html; charset=UTF-8');
exit;
}

// ── Webhook authentication ────────────────────────────────────────────────
// Telegram signs every update it delivers with the secret_token that was set
// via setWebhook (Tools/set-webhook.php). Without it anyone who learns this
// endpoint's URL can forge updates — including messages that look like the
// admin pressing an admin button. Enforced fail-closed once the secret is
// configured; until then the bot keeps working but logs a loud reminder.
$Webhook_Secret = \Environment::get('TELEGRAM_WEBHOOK_SECRET');

if ($Webhook_Secret !== '') {
$Header_Secret = (string)($_SERVER['HTTP_X_TELEGRAM_BOT_API_SECRET_TOKEN'] ?? '');

if (!hash_equals($Webhook_Secret, $Header_Secret)) {
http_response_code(403);
header('Content-Type: text/plain; charset=UTF-8');
error_log('[Umbrella-Bot][Webhook] rejected: missing/invalid X-Telegram-Bot-Api-Secret-Token from ' . ($_SERVER['REMOTE_ADDR'] ?? '-'));
echo 'Forbidden';
exit;
}
}
else {
error_log('[Umbrella-Bot][Webhook] TELEGRAM_WEBHOOK_SECRET is not set — the endpoint is open to forged updates. Set it and run Tools/set-webhook.php to re-register the webhook.');
}

$Raw_Input = file_get_contents('php://input') ?: '';
$Update = json_decode($Raw_Input, true);

if (!is_array($Update)) {
http_response_code(200);
echo 'OK';
exit;
}

try {
\Dispatcher::dispatch(\Context::fromUpdate($Update));
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot] ' . $Error->getMessage());
}

echo 'OK';
?>