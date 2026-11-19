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
// Render the actual subscription flow, including the formerly nullable Send path.
final class Context {
public int $UserId = 1, $ChatId = 1; public ?int $MessageId = 10;
public bool $IsCallback = true; public ?string $CallbackId = 'callback';
public function profileName(): string { return 'offline user'; }
}
final class Common {
public static function greet(Context $C, string $Title): string { return $Title . "\n"; }
public static function isRobotOn(): bool { return true; }
public static function backTo(string $Title, string $Data): array { return [Menu::button($Title, $Data)]; }
}
final class Repository {
public static array $User = ['Phone' => '09123456789', 'Subscription' => 'standard', 'Client_ID' => 'client-123', 'Package_Duration' => '30', 'ED_25519_Private_Key' => 'private-123+/=', 'WireGuard_Private_Key' => 'wire-456+/='];
public static function getUser(int $Id): array { return self::$User; }
public static function updateUser(int $Id, array $Data): void { self::$User = array_merge(self::$User, $Data); }
public static function getSetting(string $K, mixed $Default = null): mixed { return $Default; }
public static function getBalance(int $Id): float { return 0; }
}
final class ServerClient { public static function getUser(string $Id): array { throw new RuntimeException('server offline'); } }
final class BotConfig {
public static function getSupportUrl(): string { return 'https://t.me/support'; }
public static function showEmergency(): bool { return false; }
}
$Source = file_get_contents(dirname(__DIR__) . '/Bot/Subscription.php');
eval(preg_replace('/\?>\s*$/', '', substr($Source, strpos($Source, 'final class SubscriptionFlow {'))));
HttpClient::$Calls = []; HttpClient::$Replies = [];
SubscriptionFlow::mySubscription(new Context());
$Rendered = implode("\n", array_map(fn($C) => $C[1]['text'] ?? '', HttpClient::$Calls));
check(str_contains($Rendered, 'private-123+/=') && str_contains($Rendered, 'wire-456+/='), 'actual subscription preserves all keys');
check(str_contains($Rendered, 'https://sub.test/client-123/sub/'), 'actual subscription includes usable URL');
check(str_contains($Rendered, 'اطلاعات ذخیره شده'), 'server failure explicitly labelled cached, not fresh');
Repository::$User['Client_Status'] = 'غیر فعال'; HttpClient::$Calls = [];
SubscriptionFlow::mySubscriptionActive(new Context());
check(str_contains(end(HttpClient::$Calls)[1]['text'], 'غیرفعال'), 'inactive direct caller has a non-null renderer');
foreach ([['Phone' => ''], ['Subscription' => null], ['Client_ID' => '_']] as $Change) {
Repository::$User = array_merge(['Phone' => '09123456789', 'Subscription' => 'standard', 'Client_ID' => 'client-123'], $Change);
HttpClient::$Calls = []; SubscriptionFlow::mySubscription(new Context());
check(count(array_filter(HttpClient::$Calls, fn($C) => isset($C[1]['text']) && $C[1]['text'] !== '')) > 0, 'missing profile, no plan and inconsistent client all render');
}
echo "OK Telegram rendering ({$N} assertions)\n";
