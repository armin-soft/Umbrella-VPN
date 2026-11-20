<?php
declare(strict_types=1);
// The real formatter/client with a fake HTTP boundary: no Telegram credentials.
require_once dirname(__DIR__) . '/Bot/Menu.php';
final class Environment { public static function getBotToken(): string { return 'offline'; } public static function getSubscriptionLinkBase(): string { return 'https://sub.test'; } }
final class HttpClient {
public static array $Calls = [];
public static array $Replies = [];
public static function post(string $Url, array $Payload): array {
self::$Calls[] = [basename($Url), $Payload];
$Reply = array_shift(self::$Replies) ?? ['ok' => true];
if ($Reply === 'throw') throw new RuntimeException('offline');
return ['Json' => $Reply];
}
}
foreach (['Core/Support/Helper.php' => 'Helper', 'Core/Telegram/Telegram.php' => 'TelegramClient'] as $File => $Class) {
$Source = file_get_contents(dirname(__DIR__) . '/' . $File);
eval(preg_replace('/\?>\s*$/', '', substr($Source, strpos($Source, 'final class ' . $Class . ' {'))));
}
$N = 0;
function check(bool $Ok, string $Message): void { global $N; if (!$Ok) throw new RuntimeException($Message); $N++; }
foreach (['<b>title</b><pre>private-key-123+/=</pre><b>end</b>', '<blockquote>URL: <code>https://host.test/u/123?a=1&amp;b=2</code></blockquote>', 'plain *bold* and <code>123</code>', 'name <unknown> & value'] as $Text) {
$Html = TelegramClient::md($Text);
check(!preg_match('/<b>[^<]*(?:<pre>|<code>)/u', $Html), 'code must not be nested in bold');
$Stack = [];
preg_match_all('/<(\/?)(b|pre|code|blockquote)\b[^>]*>/', $Html, $Tags, PREG_SET_ORDER);
foreach ($Tags as $Tag) {
if ($Tag[1] === '/') { check(array_pop($Stack) === $Tag[2], 'balanced rendering'); }
else { if (in_array($Tag[2], ['pre', 'code'], true)) check(!in_array('b', $Stack, true), 'no overlapping bold-code entities'); $Stack[] = $Tag[2]; }
}
check($Stack === [], 'all tags closed');
}
check(str_contains(TelegramClient::md('<pre>key-123+/=</pre>'), 'key-123+/='), 'keys remain byte-exact');
$Markup = TelegramClient::inlineKeyboard([Menu::userHome()]);
HttpClient::$Replies = [['ok' => false, 'description' => "can't parse entities"], ['ok' => false], ['ok' => true]];
check(TelegramClient::sendReadableMessage(1, 10, '<code>key-123</code>', $Markup), 'failed HTML/edit falls back to plain send');
$Last = end(HttpClient::$Calls);
check($Last[0] === 'sendMessage' && !isset($Last[1]['parse_mode']) && $Last[1]['text'] === 'key-123', 'fallback is literal and keeps Latin key digits');
HttpClient::$Calls = []; HttpClient::$Replies = [['ok' => false, 'description' => 'Bad Request: message is not modified']];
check(TelegramClient::sendReadableMessage(1, 10, 'same', $Markup) && count(HttpClient::$Calls) === 1, 'unchanged edit is success, no duplicate');
HttpClient::$Calls = []; HttpClient::$Replies = [];
$Long = str_repeat('🔐', 4700) . "\n<pre>last-key-987</pre>";
check(TelegramClient::sendReadableMessage(1, 10, $Long, $Markup), 'long Unicode subscription delivered');
$Rebuilt = '';
foreach (HttpClient::$Calls as $I => [$Method, $Payload]) {
check(mb_strlen($Payload['text']) <= 1800, 'safe UTF-16 bound including astral emojis');
check(!isset($Payload['parse_mode']), 'chunks cannot break HTML');
$Rebuilt .= $Payload['text'];
if ($I < count(HttpClient::$Calls) - 1) check($Payload['reply_markup'] === ['inline_keyboard' => []], 'intermediate parts clear keyboard');
}
check($Rebuilt === str_repeat('🔐', 4700) . "\nlast-key-987", 'chunks lose no keys or Unicode characters');
check(end(HttpClient::$Calls)[1]['reply_markup'] === $Markup, 'navigation on final part');
HttpClient::$Calls = []; HttpClient::$Replies = [['ok' => false], ['ok' => true]];
TelegramClient::sendReadableMessage(1, null, '<a href="https://example.test/123">link</a>', $Markup);
check(str_contains(end(HttpClient::$Calls)[1]['text'], 'https://example.test/123'), 'fallback preserves hyperlink URL');
HttpClient::$Replies = ['throw', ['ok' => false]];
check(!TelegramClient::sendReadableMessage(1, null, 'fail', $Markup), 'network/Telegram failure reported to caller');
// Verify that the removed subscription-details flow has no remaining render path.
$SubscriptionSource = (string)file_get_contents(dirname(__DIR__) . '/Bot/Subscription.php');
$UserSource = (string)file_get_contents(dirname(__DIR__) . '/Bot/User.php');
$AdminSource = (string)file_get_contents(dirname(__DIR__) . '/Bot/Admin.php');
$DispatcherSource = (string)file_get_contents(dirname(__DIR__) . '/Bot/Dispatcher.php');
$CommonSource = (string)file_get_contents(dirname(__DIR__) . '/Bot/Common.php');
$SchedulerSource = (string)file_get_contents(dirname(__DIR__) . '/Bot/Scheduler.php');
$ReleaseCatalogSource = (string)file_get_contents(dirname(__DIR__) . '/Core/App/Release-Catalog.php');
check(str_contains($ReleaseCatalogSource, 'https://api.github.com/repos/') && str_contains($ReleaseCatalogSource, 'App_Release_Catalog_Token'), 'app download details come from a cached public release catalog');
check(str_contains($UserSource, 'appDownloadPlatform') && str_contains($DispatcherSource, "'app_download_windows' => [UserFlow::class, 'appDownloadWindows']") && !str_contains($DispatcherSource, 'app_download_android'), 'Windows download page is wired without Android releases');
check(str_contains($ReleaseCatalogSource, "private const PLATFORMS = ['windows'];"), 'release catalog currently exposes Windows only');
check(!str_contains($SubscriptionSource, 'mySubscriptionActive') && !str_contains($SubscriptionSource, 'configLinks('), 'subscription-details renderer and connection links are removed');
check(!str_contains($SubscriptionSource, 'کلیدهای اتصال') && !str_contains($SubscriptionSource, 'شناسه کلاینت</b>'), 'subscription screen has no client id or keys');
check(!str_contains($SubscriptionSource, 'مشخصات اتصال شما') && !str_contains($SubscriptionSource, 'full-singbox.json'), 'subscription screen has no connection links');
check(str_contains($DispatcherSource, "'اشتراک من' => [UserFlow::class, 'profile']"), 'old subscription callback safely redirects to profile');
check(!str_contains($UserSource, "['💎اشتراک من', 'اشتراک من']"), 'subscription details item is absent from management menu');
check(!str_contains($UserSource, 'شناسه کلاینت'), 'user profile omits the client identifier');
check(str_contains($UserSource, "'اشتراک آماده'") && str_contains($UserSource, "'اشتراک دلخواه'"), 'subscription purchase menu remains available');
check(str_contains($CommonSource, "'package_days'") && str_contains($CommonSource, "'start_date'") && str_contains($CommonSource, "'Expiration_Time_Stamp'"), 'panel start date and package length determine expiry');
check(str_contains($UserSource, 'Common::syncSubscriptionFromServer($User)') && str_contains($UserSource, 'Common::syncSubscriptionFromServer($User, $Live)'), 'profile and subscription menu fetch authoritative panel expiry');
check(str_contains($SchedulerSource, 'Common::subscriptionFieldsFromServer($Row)') && str_contains($SchedulerSource, 'ServerClient::getUser($Client_ID)'), 'scheduler syncs panel expiry before periodic updates and expiry actions');
$Activate_Start = strpos($SubscriptionSource, 'private static function activateSubscription(');
$Renew_Start = strpos($SubscriptionSource, 'private static function renewSubscription(');
$Duration_Start = strpos($SubscriptionSource, 'private static function durationLabel(');
$Activation = substr($SubscriptionSource, $Activate_Start, $Renew_Start - $Activate_Start);
$Renewal = substr($SubscriptionSource, $Renew_Start, $Duration_Start - $Renew_Start);
check(str_contains($Activation, "'👤پروفایل کاربری', 'callback_data' => 'پروفایل کاربری'"), 'activation success leads to profile');
check(str_contains($Renewal, "'👤پروفایل کاربری', 'callback_data' => 'پروفایل کاربری'"), 'renewal success leads to profile');
check(!str_contains($AdminSource, 'کلیدهای کلاینت') && !str_contains($AdminSource, 'کلید خصوصی ادی۲۵۵۱۹'), 'admin account details source has no key display');
echo "OK Telegram rendering ({$N} assertions)\n";
