<?php
declare(strict_types=1);
// Production flows and Context, with no network or database access.
require_once dirname(__DIR__) . '/Bot/Menu.php';
final class Environment {
public static function getAdminUserId(): int { return 99; }
public static function getAdminFullName(): string { return 'admin'; }
}
final class Repository {
public static array $Sessions = [], $Messages = [], $Settings = [], $Tickets = [], $Blocked = [];
public static bool $FailBlocking = false;
public static function setBlocked(int $Id, bool $Value): void { if (self::$FailBlocking) throw new RuntimeException("simulated write failure"); self::$Blocked[$Id] = $Value; }
public static function getSetting(string $K, mixed $Default = null): mixed { return self::$Settings[$K] ?? $Default; }
public static function setSetting(string $K, mixed $Value): void { self::$Settings[$K] = $Value; }
public static function getUser(int $Id): array { return ['Chat_ID' => $Id, 'Full_Name' => 'user', 'Phone' => '']; }
public static function getUserSession(int $Id): array { return self::$Sessions[$Id] ?? []; }
public static function updateUserSession(int $Id, array $Data): void { self::$Sessions[$Id] = array_merge(self::$Sessions[$Id] ?? [], $Data); }
public static function getTicket(int $Id): ?array { return self::$Tickets[$Id] ?? null; }
public static function getTicketMessage(int $Id): ?array { return self::$Messages[$Id] ?? null; }
public static function getTicketMessages(int $Id): array { return array_values(array_filter(self::$Messages, fn($M) => $M['Ticket_ID'] === $Id)); }
public static function addTicketMessage(int $Id, int $Sender, string $Type, ?string $Text, ?string $Photo = null, ?string $Media = null): void {
$N = count(self::$Messages) + 1;
self::$Messages[$N] = ['ID' => $N, 'Ticket_ID' => $Id, 'Sender_ID' => $Sender, 'Sender_Type' => $Type, 'Message' => $Text, 'Photo_File_ID' => $Photo, 'Media_JSON' => $Media];
}
public static function createTicket(int $Owner, string $Subject, string $Category, string $Priority): int {
$Id = count(self::$Tickets) + 1;
self::$Tickets[$Id] = ['ID' => $Id, 'User_ID' => $Owner, 'Subject' => $Subject, 'Category' => $Category, 'Priority' => $Priority, 'Status' => 'open'];
self::addTicketMessage($Id, $Owner, 'user', $Subject);
return $Id;
}
public static function addNotification(...$Args): void {}
}
final class Common { public static function greet(Context $C, string $S): string { return $S . "\n"; } }
final class Helper {
public static bool $Profane = false;
public static function __callStatic(string $Name, array $Args): mixed {
return match ($Name) {
'normalizePhone' => '', 'userFooter', 'adminFooter' => '',
'userGreeting', 'adminGreeting' => (string)$Args[1] . "\n",
'adminGreetingNamed' => (string)$Args[1] . "\n", 'frame' => (string)$Args[2] . "\n",
'isTicketCategory', 'isTicketPriority' => true, 'containsProfanity' => self::$Profane,
'ticketCategories' => ['other' => 'other'], 'ticketPriorities' => ['medium' => 'medium'],
default => (string)($Args[0] ?? ''),
};
}
}
final class TelegramClient {
public static array $Calls = []; public static bool $Fail = false;
public static function call(string $M, array $P): array { self::$Calls[] = [$M, $P]; return ['ok' => !self::$Fail]; }
public static function sendPhoto(int $Id, string $Photo, string $Caption = '', array $Markup = []): array { return self::call('sendPhoto', ['chat_id' => $Id, 'photo' => $Photo, 'caption' => $Caption, 'reply_markup' => $Markup]); }
public static function sendMessage(int $Id, string $Text, array $Markup = []): array { return self::call('sendMessage', ['chat_id' => $Id, 'text' => $Text, 'reply_markup' => $Markup]); }
public static function sendReadableMessage(int $Id, ?int $Message, string $Text, array $Markup = []): bool { self::sendMessage($Id, $Text, $Markup); return !self::$Fail; }
public static function editOrSendMessage(int $Id, ?int $Message, string $Text, array $Markup): void { self::sendMessage($Id, $Text, $Markup); }
public static function answerCallbackQuery(?string $Id, string $Text, bool $Alert = false): void { self::call('answerCallbackQuery', ['text' => $Text]); }
public static function inlineKeyboard(array $Rows): array { return ['inline_keyboard' => $Rows]; }
}
final class PanelClient { public static function findByTelegramId(int $Id): array { return ['uuid' => 'owner-' . $Id]; } }
final class Database {
public static array $Devices = [];
public static function getInstance(): self { return new self(); }
public function fetchAll(string $Sql, array $Params): array {
if (!str_contains($Sql, 'LEFT(`Device_ID`, ?) = ?') || !str_contains($Sql, 'LIMIT 2')) throw new RuntimeException('device query must be bounded and wildcard-free');
[$Length, $Prefix, $Owner, $Telegram] = $Params;
return array_slice(array_values(array_filter(self::$Devices, fn($D) => substr($D['Device_ID'], 0, $Length) === $Prefix && ($D['User_UUID'] === $Owner || $D['Telegram_ID'] === $Telegram))), 0, 2);
}
}
foreach (['Context' => 'Context.php', 'TicketMedia' => 'Ticket-Media.php', 'UserFlow' => 'User.php', 'AdminFlow' => 'Admin.php', 'AppFlow' => 'App-Link.php', 'Dispatcher' => 'Dispatcher.php'] as $Class => $File) {
$S = file_get_contents(dirname(__DIR__) . '/Bot/' . $File);
$Marker = $Class === 'Context' ? 'final readonly class Context {' : 'final class ' . $Class . ' {';
eval(preg_replace('/\?>\s*$/', '', substr($S, strpos($S, $Marker))));
}
$N = 0;
function check(bool $Ok, string $Why): void { global $N; if (!$Ok) throw new RuntimeException($Why); $N++; }
function ctx(int $Id, array $Data = [], bool $Callback = false): Context {
$Msg = ['message_id' => 20, 'from' => ['id' => $Id], 'chat' => ['id' => $Id]] + $Data;
return Context::fromUpdate($Callback ? ['callback_query' => ['id' => 'cb', 'from' => ['id' => $Id], 'message' => $Msg, 'data' => 'test']] : ['message' => $Msg]);
}
$Methods = ['photo' => 'sendPhoto', 'document' => 'sendDocument', 'video' => 'sendVideo', 'voice' => 'sendVoice', 'audio' => 'sendAudio', 'animation' => 'sendAnimation', 'sticker' => 'sendSticker', 'video_note' => 'sendVideoNote'];
foreach ($Methods as $Type => $Method) foreach (['', '<b>caption</b> 123'] as $Caption) {
$Data = [$Type => $Type === 'photo' ? [['file_id' => 'small'], ['file_id' => 'LARGE-123']] : ['file_id' => 'LARGE-123']];
if ($Caption !== '') $Data['caption'] = $Caption;
$C = ctx(1, $Data); $Media = TicketMedia::extract($C);
check($Media['file_id'] === 'LARGE-123' && $Media['caption'] === $Caption, "$Type extraction with/without caption");
check(TicketMedia::send(99, $Media), "$Type resend");
[$M, $P] = end(TelegramClient::$Calls);
check($M === $Method && $P[$Type] === 'LARGE-123' && !isset($P['parse_mode']), 'literal file_id and no caption markup injection');
if (!in_array($Type, ['sticker', 'video_note'], true)) check($P['caption'] === $Caption, 'caption preserved exactly');
}
foreach (['contact' => ['phone_number' => '+123', 'first_name' => 'Name'], 'location' => ['latitude' => 40, 'longitude' => -3], 'venue' => ['title' => 'place', 'address' => 'street', 'location' => ['latitude' => 40, 'longitude' => -3]]] as $Type => $Payload) {
check(TicketMedia::send(99, TicketMedia::extract(ctx(1, [$Type => $Payload]))), "$Type supported");
}
check(TicketMedia::extract(ctx(1, ['photo' => [['file_id' => 'ignored']]], true)) === null, 'callback message never mistaken for incoming attachment');
check(!TicketMedia::send(99, ['type' => 'evil', 'file_id' => 'x']), 'media methods allowlisted');
check(TicketMedia::extract(ctx(1, ['poll' => []])) === null, 'unsupported type not falsely accepted');
check(TicketMedia::extract(ctx(1, ['animation' => ['file_id' => 'gif'], 'document' => ['file_id' => 'compat']]))['type'] === 'animation', 'animation takes precedence over Telegram compatibility document');
$C = ctx(1, ['document' => ['file_id' => 'doc-1']]);
UserFlow::ticketNewStart($C);
UserFlow::ticketCreate($C, '');
check(Repository::$Sessions[1]['Ticket_Subject'] === 'پشتیبانی با پیوست', 'attachment-only initial subject accepted');
UserFlow::ticketDescriptionInput(ctx(1, ['photo' => [['file_id' => 'photo-2']]]), 'second');
$Saved = json_decode(Repository::$Sessions[1]['Ticket_Media_JSON'], true);
check(count($Saved) === 2 && $Saved[1]['file_id'] === 'photo-2', 'sequential/album attachments accumulated');
UserFlow::ticketPriorityCallback(ctx(1, [], true), 'medium');
check(count(Repository::$Tickets) === 1 && count(Repository::$Messages) === 4, 'description and both attachments persisted');
check(Repository::$Sessions[1]['Ticket_Media_JSON'] === null, 'draft media cleared after create');
$Attachment = 3; TelegramClient::$Calls = [];
TicketMedia::show(ctx(2, [], true), $Attachment);
check(TelegramClient::$Calls === [], 'foreign ticket attachment denied');
TicketMedia::show(ctx(1, [], true), $Attachment);
check(end(TelegramClient::$Calls)[1]['document'] === 'doc-1', 'owner can reopen attachment');
TicketMedia::show(ctx(99, [], true), $Attachment);
check(end(TelegramClient::$Calls)[1]['chat_id'] === 99, 'admin can reopen attachment');
Repository::$Messages[50] = ['ID' => 50, 'Ticket_ID' => 1, 'Photo_File_ID' => 'legacy'];
TicketMedia::show(ctx(1, [], true), 50);
check(end(TelegramClient::$Calls)[1]['photo'] === 'legacy', 'legacy photo references still viewable');
TelegramClient::$Calls = []; TicketMedia::show(ctx(1, [], true), 987);
check(TelegramClient::$Calls === [], 'missing attachment safe');
UserFlow::ticketUserReplyStart(ctx(1, [], true), 1);
$Before = count(Repository::$Messages);
UserFlow::ticketUserReplySend(ctx(1, ['voice' => ['file_id' => 'voice-3']]), '');
UserFlow::ticketUserReplySend(ctx(1, ['document' => ['file_id' => 'doc-4'], 'caption' => 'caption']), 'caption');
check(count(Repository::$Messages) === $Before + 2 && Repository::$Sessions[1]['Flow'] === 'user:ticket_reply_text', 'successive replies including captionless voice retained');
Repository::$Sessions[2] = ['Temp_Ticket_ID' => 1];
$Before = count(Repository::$Messages); UserFlow::ticketUserReplySend(ctx(2, ['photo' => [['file_id' => 'stolen']]]), '');
check(count(Repository::$Messages) === $Before, 'cannot write another owner ticket');
AdminFlow::ticketAdminReplyStart(ctx(99, [], true), 1);
AdminFlow::ticketAdminReplySend(ctx(99, ['video' => ['file_id' => 'reply-video']]), '');
check(end(Repository::$Messages)['Sender_Type'] === 'admin' && TicketMedia::decode(end(Repository::$Messages))['file_id'] === 'reply-video', 'admin captionless video saved');
Repository::$Tickets[1]['Status'] = 'closed'; $Before = count(Repository::$Messages);
UserFlow::ticketUserReplySend(ctx(1, ['document' => ['file_id' => 'closed']]), '');
AdminFlow::ticketAdminReplySend(ctx(99, ['voice' => ['file_id' => 'closed']]), '');
check(count(Repository::$Messages) === $Before, 'closed ticket rejects new attachments');
$Items = []; for ($I = 1; $I <= 13; $I++) $Items[] = ['ID' => $I, 'Photo_File_ID' => 'photo'];
[$Rows, $Page, $Count] = TicketMedia::buttons($Items, 999);
check(count($Rows) === 3 && $Page === 2 && $Count === 3, 'attachment pagination bounded and clamped');
check(AppFlow::deviceArt('Android') === 'mobile' && AppFlow::deviceArt('WINDOWS') === 'computer' && AppFlow::deviceArt('mystery') === 'unknown', 'art uses platform, never guesses hardware model');
Database::$Devices = [['Device_ID' => 'my-device', 'User_UUID' => 'owner-1', 'Telegram_ID' => 1, 'Device_Name' => 'My PC', 'Platform' => 'Windows', 'Is_Trusted' => 0]];
TelegramClient::$Calls = []; AppFlow::deviceCard(ctx(2, [], true), 'my-device');
check(!array_filter(TelegramClient::$Calls, fn($C) => $C[0] === 'sendPhoto'), 'foreign device picture denied');
AppFlow::deviceCard(ctx(1, [], true), 'my-device'); $Last = end(TelegramClient::$Calls);
check(str_ends_with($Last[1]['photo'], '/computer.png') && str_contains($Last[1]['caption'], 'شماتیک') && str_contains($Last[1]['caption'], 'لغو شده'), 'default art labelled schematic with current trust state');
AppFlow::devicePhotoStart(ctx(1, [], true), 'my-device', 2);
AppFlow::devicePhotoInput(ctx(1, ['photo' => [['file_id' => 'real-photo']]]), 'my-device', 2);
check(end(TelegramClient::$Calls)[1]['photo'] === 'real-photo' && Repository::$Sessions[1]['Flow'] === null, 'user supplied picture persists per device');
$SavedSettings = Repository::$Settings;
AppFlow::devicePhotoReset(ctx(2, [], true), 'my-device');
check(Repository::$Settings === $SavedSettings, 'other user cannot reset picture');
AppFlow::devicePhotoReset(ctx(1, [], true), 'my-device');
check(str_ends_with(end(TelegramClient::$Calls)[1]['photo'], '/computer.png'), 'owner restores schematic');
Database::$Devices[] = Database::$Devices[0]; Database::$Devices[1]['Device_ID'] = 'my-device-2';
TelegramClient::$Calls = []; AppFlow::deviceCard(ctx(1, [], true), 'my-device');
check(!array_filter(TelegramClient::$Calls, fn($C) => $C[0] === 'sendPhoto'), 'ambiguous prefix fails closed');
TelegramClient::$Fail = true;
check(!TicketMedia::send(99, ['type' => 'document', 'file_id' => 'bad']), 'Telegram media failure propagated');
TelegramClient::$Calls = []; TicketMedia::show(ctx(1, [], true), 3);
check(end(TelegramClient::$Calls)[0] === 'sendMessage', 'unavailable attachment reports retry instructions');
TelegramClient::$Fail = false; Repository::$Tickets[1]['Status'] = 'open';
Repository::$Sessions[1] = ['Flow' => 'user:ticket_reply_text', 'Temp_Ticket_ID' => 1];
$Route = new ReflectionMethod(Dispatcher::class, 'routeMessage');
$Before = count(Repository::$Messages);
foreach (['', '/start', 'لغو', 'admin'] as $Caption) {
$Route->invoke(null, ctx(1, ['document' => ['file_id' => 'routed'], 'caption' => $Caption]));
}
check(count(Repository::$Messages) === $Before + 4, 'dispatcher accepts captionless files and command-like captions as attachments');
TelegramClient::$Calls = [];
$Route->invoke(null, ctx(1, ['poll' => ['question' => 'unsupported']]));
check(str_contains(end(TelegramClient::$Calls)[1]['text'], 'قابل ثبت'), 'unsupported input receives explicit guidance');
// The saved description survives an additional captionless file.
Repository::$Sessions[1] = ['Flow' => 'user:ticket_category', 'Ticket_Subject' => 'test', 'Ticket_Description' => 'original text'];
UserFlow::ticketDescriptionInput(ctx(1, ['document' => ['file_id' => 'extra']]), '');
check(Repository::$Sessions[1]['Ticket_Description'] === 'original text', 'additional attachments do not erase the draft description');
// Dispatcher must inspect media captions, retain the admin exemption, and not
// announce a permanent block when persistence failed.
final class BotConfig { public static function getSupportUrl(): string { return 'https://example.test/support'; } }
Helper::$Profane = true;
Repository::$FailBlocking = false;
$Before = count(Repository::$Messages);
$Route->invoke(null, ctx(1, ['document' => ['file_id' => 'attachment'], 'caption' => 'profanity']));
check((Repository::$Blocked[1] ?? false) && count(Repository::$Messages) === $Before, 'caption moderation blocks before ticket handling');
Repository::$Sessions[99] = ['Flow' => 'user:ticket_reply_text', 'Temp_Ticket_ID' => 1];
$Route->invoke(null, ctx(99, ['text' => 'profanity']));
check(!isset(Repository::$Blocked[99]), 'existing admin moderation exemption retained');
Repository::$FailBlocking = true; TelegramClient::$Calls = [];
$Route->invoke(null, ctx(2, ['text' => 'profanity']));
check(!isset(Repository::$Blocked[2]) && count(TelegramClient::$Calls) === 1 && str_contains(TelegramClient::$Calls[0][1]['text'], 'خطای موقت'), 'failed block has no false success/admin notification');
echo "OK ticket media/device cards ({$N} assertions)\n";
