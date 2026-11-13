<?php
declare(strict_types=1);

require_once __DIR__ . '/../Support/Http.php';
require_once __DIR__ . '/../Support/Helper.php';
require_once dirname(__DIR__, 2) . '/Config/Environment.php';

final class TelegramClient {
private const API_BASE = 'https://api.telegram.org/bot';
private function __construct() {
}

private static function token(): string {
return Environment::getBotToken();
}

private static function url(string $Method): string {
return self::API_BASE . self::token() . '/' . $Method;
}

public static function call(string $Method, array $Payload = []): array {
$Response = HttpClient::post(self::url($Method), $Payload);

return $Response['Json'] ?? ['ok' => false];
}

private static function normalizeStars(string $Text): string {
if (substr_count($Text, '*') % 2 === 1) {
$Last = strrpos($Text, '*');

if ($Last !== false) {
$Text = substr_replace($Text, '', $Last, 1);
}
}

return $Text;
}

private static function normalizeLayout(string $Text): string {
$Separator = str_repeat('➖', 9);
$Text = preg_replace('/\s*➖{5,}(?:\s*➖{5,})*\s*/u', "\n" . $Separator . "\n", $Text) ?? $Text;
$Text = preg_replace('/\n{3,}/u', "\n\n", $Text) ?? $Text;
return trim($Text);
}

public static function md(string $Text): string {
if ($Text === '') return $Text;
$Text = str_replace(["\r\n", "\r"], "\n", $Text);
// Every message goes through here, so this is the one place that guarantees
// Persian digits — code spans, links and @usernames keep their Latin ones.
$Text = Helper::digitsToPersian($Text);
$Text = static::normalizeStars($Text);
$Text = static::normalizeLayout($Text);
$Link_Map = [];
$Link_Index = 0;
$Text = preg_replace_callback('/\[([^\]\n]+?)\]\(([^\)\n]+?)\)/u', static function(array $M) use (&$Link_Map, &$Link_Index): string {
$Key = "\x01\x02LNK" . $Link_Index . "\x02\x01";
$Link_Map[$Key] = '<a href="' . htmlspecialchars($M[2], ENT_QUOTES, 'UTF-8') . '">' . htmlspecialchars($M[1], ENT_QUOTES, 'UTF-8') . '</a>';
$Link_Index++;
return $Key;
}, $Text) ?? $Text;
$Text = preg_replace('/\*\*(.+?)\*\*/su', '<b>$1</b>', $Text) ?? $Text;
$Text = preg_replace('/(?<![\*\w])\*(.+?)\*(?![\*\w])/su', '<b>$1</b>', $Text) ?? $Text;
$Text = preg_replace('/`([^`\n]+?)`/u', '<code>$1</code>', $Text) ?? $Text;

foreach ($Link_Map as $Key => $Replacement) {
$Text = str_replace($Key, $Replacement, $Text);
}

$Text = static::sanitizeHtml($Text);
$Text = preg_replace('/&(?!(?:amp|lt|gt|quot|#039);)/', '&amp;', $Text) ?? $Text;
// Every message the bot sends is bold. Inner <b> tags add nothing once the
// whole text is bold, so they are dropped and a single pair wraps the message;
// links, code blocks and blockquotes nest inside it, which Telegram accepts.
$Text = str_replace(['<b>', '</b>'], '', $Text);

return '<b>' . $Text . '</b>';
}

/**
 * Telegram parses messages with parse_mode=HTML, so a stray `<` in anything a
 * user typed (a name, a ticket subject, a rule the panel returned) makes the
 * whole API call fail and the message silently never arrives. md() converts
 * our own markup first; this pass then allows only the tags we generate —
 * <b> <code> <pre> <i> <u> <s> <tg-spoiler> <blockquote> and <a href="http(s)/tg://…"> —
 * and escapes everything else.
 */
private static function sanitizeHtml(string $Text): string {
$Text = (string)preg_replace_callback('/<[^>]*>/s', static function (array $M): string {
$Tag = $M[0];

if (preg_match('/^<\s*(\/?)\s*(b|code|pre|i|u|s|tg-spoiler|blockquote)\s*>$/i', $Tag, $M2)) {
return '<' . ($M2[1] === '/' ? '/' : '') . strtolower($M2[2]) . '>';
}

if (preg_match('/^<\s*blockquote\s+expandable\s*>$/i', $Tag)) {
return '<blockquote expandable>';
}

if (preg_match('/^<\s*\/\s*a\s*>$/i', $Tag)) {
return '</a>';
}

if (preg_match('/^<\s*a\s+href="([^"]*)"\s*>$/i', $Tag, $M2)) {
$Url = $M2[1];
$Decoded = html_entity_decode($Url, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');

if (preg_match('#^(https?://|tg://)#i', $Decoded) && !preg_match('/[\s<>]/', $Decoded)) {
// md() escaped the URL once already — pass it through as-is.
return '<a href="' . $Url . '">';
}
}

return htmlspecialchars($Tag, ENT_QUOTES, 'UTF-8');
}, $Text);
// A lone `<` with no closing `>` left anywhere after it would still break the parse.
$Text = (string)preg_replace('/<(?![^>]*>)/', '&lt;', $Text);
return self::balanceTags($Text);
}

/**
 * Telegram rejects the whole message when a tag is unmatched or nested out of
 * order. Our own md() markup is always balanced, but user input is not:
 * `<b>` with no close, or `</b>` with no open. This pass nests everything
 * properly — inner tags are closed before an outer one closes, stragglers at
 * the end are closed, and a close with no open is escaped.
 */
private static function balanceTags(string $Text): string {
$Out = '';
$Stack = [];
$Pos = 0;
$Pattern = '/<(\/?)(b|code|pre|i|u|s|tg-spoiler|blockquote|a)(?:\s[^>]*)?>/i';

while (preg_match($Pattern, $Text, $M, PREG_OFFSET_CAPTURE, $Pos)) {
$Tag = $M[0][0];
$Start = $M[0][1];
$Out .= substr($Text, $Pos, $Start - $Pos);
$Pos = $Start + strlen($Tag);
$Name = strtolower($M[2][0]);
$Is_Close = $M[1][0] === '/';

if (!$Is_Close) {
$Stack[] = $Name;
$Out .= $Tag;
continue;
}

$Index = null;

for ($I = count($Stack) - 1; $I >= 0; $I--) {
if ($Stack[$I] === $Name) { $Index = $I; break; }
}

if ($Index === null) {
$Out .= htmlspecialchars($Tag, ENT_QUOTES, 'UTF-8');
continue;
}

for ($I = count($Stack) - 1; $I >= $Index; $I--) {
$Out .= '</' . array_pop($Stack) . '>';
}
}

$Out .= substr($Text, $Pos);

while ($Stack !== []) {
$Out .= '</' . array_pop($Stack) . '>';
}

return $Out;
}

/**
 * The footer ("…بر روی منوی مورد نظر کلیک کنید") only makes sense when the
 * message actually offers something to pick. Two cases are dropped together
 * with the sentence and its separator:
 *
 *   1. there is no inline keyboard at all, or
 *   2. the keyboard only holds navigation — «بازگشت» and «خانه» — as on the
 *      "send me the user id" screens, where nothing is left to choose.
 */
private static function trimFooterWithoutKeyboard(string $Text, array $Markup): string {
if ($Text === '') return $Text;
if ($Markup !== [] && !self::hasOnlyNavigationButtons($Markup)) return $Text;
return self::stripFooter($Text);
}

/**
 * حذف جمله پایانی «👌جهت استفاده …» همراه با خط جداکننده بالای آن (قاعده در Menu).
 */
private static function stripFooter(string $Text): string {
if (!class_exists('Menu', false)) return $Text;

return Menu::stripFooter($Text);
}

/**
 * آیا کیبورد فقط دکمه های ناوبری دارد؟
 *
 * قاعده در Bot/Menu.php است تا آزمون ها هم همان را بسنجند؛ اگر Menu در دسترس
 * نبود (مثلاً اسکریپت مستقل)، محافظه کارانه «خیر» برمی گردد و جمله پایانی
 * دست نخورده می ماند.
 */
private static function hasOnlyNavigationButtons(array $Markup): bool {
if (!class_exists('Menu', false)) return false;
return Menu::isNavigationOnly($Markup);
}

public static function sendMessage(int $Chat_ID, string $Text, array $Markup = [], string $Parse_Mode = 'HTML', ?int $Reply_To = null): array {
$Payload = [
'chat_id' => $Chat_ID,
'text' => self::md(self::trimFooterWithoutKeyboard($Text, $Markup)),
'parse_mode' => $Parse_Mode,
'disable_web_page_preview' => true,
];

if (!empty($Markup)) $Payload['reply_markup'] = $Markup;
if ($Reply_To !== null) $Payload['reply_to_message_id'] = $Reply_To;
return self::call('sendMessage', $Payload);
}

public static function editMessageText(int $Chat_ID, int $Message_ID, string $Text, array $Markup = []): array {
$Payload = [
'chat_id' => $Chat_ID,
'message_id' => $Message_ID,
'text' => self::md(self::trimFooterWithoutKeyboard($Text, $Markup)),
'parse_mode' => 'HTML',
'disable_web_page_preview' => true,
];

if (!empty($Markup)) $Payload['reply_markup'] = $Markup;
return self::call('editMessageText', $Payload);
}

public static function deleteMessage(int $Chat_ID, int $Message_ID): array {
return self::call('deleteMessage', ['chat_id' => $Chat_ID, 'message_id' => $Message_ID]);
}

public static function editOrSendMessage(int $Chat_ID, ?int $Message_ID, string $Text, array $Markup = []): void {
$Markup = self::sanitizeMarkup($Markup);

if ($Message_ID !== null) {
$Result = self::editMessageText($Chat_ID, $Message_ID, $Text, $Markup);

if (is_array($Result) && ($Result['ok'] ?? false) === true) return;
try { self::deleteMessage($Chat_ID, $Message_ID); } catch (Throwable) {}
$Send_Result = self::sendMessage($Chat_ID, $Text, $Markup);

if (is_array($Send_Result) && ($Send_Result['ok'] ?? false) !== true) {
error_log('[Umbrella-Telegram][editOrSendMessage] sendMessage failed after edit+delete: ' . json_encode($Send_Result));
}

return;
}

self::sendMessage($Chat_ID, $Text, $Markup);
}

private static function sanitizeMarkup(array $Markup): array {
$Rows = $Markup['inline_keyboard'] ?? null;

if (!is_array($Rows) || $Rows === []) return [];
$Clean = [];

foreach ($Rows as $Row) {
if (!is_array($Row)) continue;
$Buttons = [];

foreach ($Row as $Button) {
if (!is_array($Button)) continue;
if (!isset($Button['text']) || !is_string($Button['text']) || trim($Button['text']) === '') continue;
if (!isset($Button['callback_data']) && !isset($Button['url']) && !isset($Button['web_app'])) continue;
$Buttons[] = $Button;
}

if ($Buttons !== []) $Clean[] = $Buttons;
}

return $Clean === [] ? [] : ['inline_keyboard' => $Clean];
}

public static function answerCallbackQuery(string $Callback_Query_ID, string $Text = '', bool $Show_Alert = false): array {
$Payload = ['callback_query_id' => $Callback_Query_ID, 'show_alert' => $Show_Alert];

if ($Text !== '') $Payload['text'] = Helper::digitsToPersian($Text);
return self::call('answerCallbackQuery', $Payload);
}

public static function sendChatAction(int $Chat_ID, string $Action = 'typing'): array {
return self::call('sendChatAction', ['chat_id' => $Chat_ID, 'action' => $Action]);
}

public static function sendPhoto(int $Chat_ID, string $PhotoUrl, string $Caption = '', array $Markup = []): array {
$Is_Local = is_file($PhotoUrl);

if ($Is_Local) {
$Fields = [
'chat_id' => $Chat_ID,
'photo' => new \CURLFile($PhotoUrl),
'caption' => self::md(self::trimFooterWithoutKeyboard($Caption, $Markup)),
'parse_mode' => 'HTML',
'disable_web_page_preview' => true,
];

if (!empty($Markup)) $Fields['reply_markup'] = json_encode($Markup);
$Response = HttpClient::postMultipart(self::url('sendPhoto'), $Fields);
return $Response['Json'] ?? ['ok' => false];
}

$Payload = ['chat_id' => $Chat_ID, 'photo' => $PhotoUrl, 'caption' => self::md(self::trimFooterWithoutKeyboard($Caption, $Markup)), 'parse_mode' => 'HTML', 'disable_web_page_preview' => true];

if (!empty($Markup)) $Payload['reply_markup'] = $Markup;
return self::call('sendPhoto', $Payload);
}

public static function sendMediaGroup(int $Chat_ID, array $Media, array $Markup = []): array {
$Payload = ['chat_id' => $Chat_ID, 'media' => $Media];

if (!empty($Markup)) $Payload['reply_markup'] = $Markup;
return self::call('sendMediaGroup', $Payload);
}

public static function sendDocument(int $Chat_ID, string $Document_Path, string $Caption = '', array $Markup = []): array {
$Fields = [
'chat_id' => $Chat_ID,
'document' => new \CURLFile($Document_Path),
'caption' => self::md(self::trimFooterWithoutKeyboard($Caption, $Markup)),
'parse_mode' => 'HTML',
'disable_web_page_preview' => true,
];

if (!empty($Markup)) $Fields['reply_markup'] = json_encode($Markup);
$Response = HttpClient::postMultipart(self::url('sendDocument'), $Fields);
return $Response['Json'] ?? ['ok' => false];
}


public static function channelMemberStatus(int $User_ID, string $Channel_Username, ?string $Channel_ID = null): string {
$Token = self::token();

if ($Token === '' || ($Channel_Username === '' && $Channel_ID === null)) return 'unknown';
$Configured_Channel_ID = trim((string)$Channel_ID);
$Chat_ID = $Configured_Channel_ID !== '' && preg_match('/^-?\d+$/', $Configured_Channel_ID) === 1
? $Configured_Channel_ID
: '@' . ltrim($Channel_Username, '@');
$Url = self::API_BASE . $Token . '/getChatMember?chat_id=' . urlencode($Chat_ID) . '&user_id=' . $User_ID;
$Response = HttpClient::get($Url);
$Status = self::parseChatMemberStatus($User_ID, $Response, true);

if ($Status === 'unknown_participant') {
usleep(1000000);
$Status = self::parseChatMemberStatus($User_ID, HttpClient::get($Url), false);
}

return $Status;
}

private static function parseChatMemberStatus(int $User_ID, array $Response, bool $Log_Errors): string {
$Json = $Response['Json'] ?? null;

if (!is_array($Json) || ($Json['ok'] ?? false) !== true) {
$Description = mb_strtolower((string)($Json['description'] ?? $Response['Body'] ?? ''));
$Is_NotMember = str_contains($Description, 'user_not_participant')
|| str_contains($Description, 'user_is_not_a_member')
|| str_contains($Description, 'user is not a member');

if ($Is_NotMember) return 'not_member';
if (str_contains($Description, 'participant_id_invalid') || str_contains($Description, 'user_id_invalid')) return 'unknown_participant';

if ($Log_Errors && str_contains($Description, 'participant_id_invalid') === false) {
$Code = (int)($Response['StatusCode'] ?? 0);
error_log('[Umbrella-Bot][ChannelCheck] getChatMember failed | User=' . $User_ID . ' HTTP=' . $Code . ' Body=' . mb_substr((string)($Response['Body'] ?? ''), 0, 200));
}

return 'unknown';
}
$Status = (string)($Json['result']['status'] ?? '');

if (in_array($Status, ['member', 'creator', 'administrator'], true)) return 'member';
if ($Status === 'restricted') return ((bool)($Json['result']['is_member'] ?? false)) ? 'member' : 'not_member';
if (in_array($Status, ['left', 'kicked'], true)) return 'not_member';
return 'unknown';
}

public static function inlineKeyboard(array $Rows): array {
$Clean = [];

foreach ($Rows as $Row) {
if (!is_array($Row)) continue;
$Buttons = [];

foreach ($Row as $Button) {
if (!is_array($Button)) continue;
if (!isset($Button['text']) || !is_string($Button['text']) || trim($Button['text']) === '') continue;
if (!isset($Button['callback_data']) && !isset($Button['url']) && !isset($Button['web_app'])) continue;

if (isset($Button['callback_data'])) {
$Data = (string)$Button['callback_data'];

// تلگرام callback_data بیشتر از ۶۴ بایت را رد می کند و کل پیام ناموفق می شود.
if ($Data === '') continue;

if (strlen($Data) > 64) {
error_log('[Umbrella-Bot][Keyboard] callback_data longer than 64 bytes dropped: ' . mb_substr($Data, 0, 40));
continue;
}
}

$Text = Helper::digitsToPersian($Button['text']);

// متن دکمه حداکثر ۶۴ کاراکتر است.
if (mb_strlen($Text) > 64) $Text = mb_substr($Text, 0, 61) . '…';

$Button['text'] = $Text;
$Buttons[] = $Button;
}

if ($Buttons !== []) $Clean[] = $Buttons;
}

return ['inline_keyboard' => $Clean];
}
}
?>