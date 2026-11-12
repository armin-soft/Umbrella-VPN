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
require_once __DIR__ . '/Core/Storage/Repository.php';
require_once __DIR__ . '/Core/Telegram/Webhook.php';

header('Content-Type: text/plain; charset=UTF-8');

try {
\Schema::ensureInstalled();
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Schema-AutoInstall] ' . $Error->getMessage());
}

// کارهای نگهداری فقط از ترمینال سرور اجرا می شوند:
//   php index.php RunScheduler [all|daily|operations|membership]
//   php index.php NightlyDiag
if (PHP_SAPI === 'cli') {
$Command = strtolower(trim((string)($argv[1] ?? '')));

if ($Command === 'runscheduler' || $Command === 'nightlydiag') {
require_once __DIR__ . '/Bot/Scheduler.php';
header('Content-Type: text/plain; charset=UTF-8');

if ($Command === 'nightlydiag') {
\Scheduler::diagnoseNightly();
echo "DIAG DONE - see error log for [Nightly-DIAG] lines\n";
}

else {
\Scheduler::run(trim((string)($argv[2] ?? 'all')) ?: 'all');
echo "SCHEDULER DONE\n";
}

exit;
}
}

// وبهوک بدون هیچ ورودی در .env ثبت می شود. این فراخوانی خودش یک ساعت فاصله
// می گذارد و اگر خطا بدهد مسیر اصلی برنامه متوقف نمی شود.
try {
\Webhook::ensureRegistered();
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Webhook] bootstrap failed: ' . $Error->getMessage());
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
// Telegram هر به روزرسانی را با secret_token ای که هنگام setWebhook داده شده
// امضا می کند. ساخت Secret و ثبت وبهوک خودکار انجام می شود (کلاس Webhook)، پس
// هیچ کلیدی در .env لازم نیست.
$Is_Post = ($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST';

if (!$Is_Post) {
// بازدید ساده از آدرس ربات: ثبت وبهوک تازه می شود و بازدیدکننده به ربات می رود.
// کارهای زمان بندی شده بعد از بسته شدن پاسخ اجرا می شوند تا هدایت کند نباشد.
\Webhook::ensureRegistered(true);

register_shutdown_function(static function (): void {
require_once __DIR__ . '/Bot/Scheduler.php';
\Scheduler::tick();
});

$Visitor_Bot_Username = \Environment::getBotUsername();
$Visitor_Bot_Link = $Visitor_Bot_Username !== '' ? 'https://t.me/' . $Visitor_Bot_Username : 'https://t.me/';
header('Location: ' . $Visitor_Bot_Link, true, 302);
exit;
}

$Provided_Secret = (string)($_SERVER['HTTP_X_TELEGRAM_BOT_API_SECRET_TOKEN'] ?? '');

if (!\Webhook::verify($Provided_Secret)) {
// شاید دامنه عوض شده باشد؛ یک بار ثبت وبهوک بررسی و اصلاح می شود.
try {
\Webhook::ensureRegistered();
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][Webhook] re-registration failed: ' . $Error->getMessage());
}
}

if (!\Webhook::verify($Provided_Secret)) {
http_response_code(403);
header('Content-Type: text/plain; charset=UTF-8');
error_log('[Umbrella-Bot][Webhook] rejected: invalid X-Telegram-Bot-Api-Secret-Token from ' . ($_SERVER['REMOTE_ADDR'] ?? '-'));
echo 'Forbidden';
exit;
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

// پاسخ اول تحویل داده می شود تا تلگرام منتظر کارهای زمان بندی شده نماند، بعد
// نوبت اجرای خودکار Scheduler است (حداکثر یک بار در دقیقه).
if (function_exists('fastcgi_finish_request')) {
fastcgi_finish_request();
}

else {
// روی سرورهای بدون FastCGI هم پاسخ را زودتر خالی می کنیم.
while (ob_get_level() > 0) {
@ob_end_flush();
}

@flush();
}

ignore_user_abort(true);
@set_time_limit(0);

require_once __DIR__ . '/Bot/Scheduler.php';
\Scheduler::tick();
?>