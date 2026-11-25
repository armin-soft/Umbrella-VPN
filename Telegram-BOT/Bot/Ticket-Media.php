<?php
declare(strict_types=1);
require_once __DIR__ . '/Context.php';
require_once __DIR__ . '/../Core/Telegram/Telegram.php';

/** Stored Telegram file references, never downloads or executes user uploads. */
final class TicketMedia {
private const METHODS = ['photo' => 'sendPhoto', 'video' => 'sendVideo', 'animation' => 'sendAnimation', 'document' => 'sendDocument', 'audio' => 'sendAudio', 'voice' => 'sendVoice', 'sticker' => 'sendSticker', 'video_note' => 'sendVideoNote'];
public static function extract(Context $Context): ?array {
if ($Context->IsCallback) return null;
$Message = $Context->Raw['message'] ?? $Context->Raw['edited_message'] ?? [];
foreach (self::METHODS as $Type => $Method) {
$Item = $Message[$Type] ?? null;
if ($Type === 'photo' && is_array($Item)) $Item = end($Item);
if (is_array($Item) && is_string($Item['file_id'] ?? null)) return ['type' => $Type, 'file_id' => $Item['file_id'], 'caption' => (string)($Message['caption'] ?? '')];
}
foreach (['venue', 'location', 'contact'] as $Type) {
if (is_array($Message[$Type] ?? null)) return ['type' => $Type, 'data' => $Message[$Type]];
}
return null;
}

public static function send(int $ChatId, array $Media): bool {
$Type = (string)($Media['type'] ?? '');
$Payload = ['chat_id' => $ChatId];
if (isset(self::METHODS[$Type]) && is_string($Media['file_id'] ?? null)) {
$Method = self::METHODS[$Type];
$Payload[$Type] = $Media['file_id'];
if (!in_array($Type, ['sticker', 'video_note'], true)) {
$RawCaption = (string)($Media['caption'] ?? '');
if (method_exists('Helper', 'stripZwnj')) $RawCaption = Helper::stripZwnj($RawCaption);
if (method_exists('Helper', 'digitsToPersian')) $RawCaption = Helper::digitsToPersian($RawCaption);
$Payload['caption'] = mb_substr($RawCaption, 0, 1024);
}
} elseif ($Type === 'venue') {
$Method = 'sendVenue';
$Data = $Media['data'] ?? [];
$Payload += array_intersect_key($Data, array_flip(['title', 'address', 'foursquare_id', 'foursquare_type', 'google_place_id', 'google_place_type']));
$Payload += array_intersect_key($Data['location'] ?? [], array_flip(['latitude', 'longitude']));
} elseif ($Type === 'location') {
$Method = 'sendLocation';
$Payload += array_intersect_key($Media['data'] ?? [], array_flip(['latitude', 'longitude']));
} elseif ($Type === 'contact') {
$Method = 'sendContact';
$Payload += array_intersect_key($Media['data'] ?? [], array_flip(['phone_number', 'first_name', 'last_name', 'vcard']));
} else { return false; }
try { $Result = TelegramClient::call($Method, $Payload); return ($Result['ok'] ?? false) === true; }
catch (Throwable) { return false; }
}

public static function decode(array $Message): ?array {
$Media = json_decode((string)($Message['Media_JSON'] ?? ''), true);
if (is_array($Media)) return $Media;
if (!empty($Message['Photo_File_ID'])) return ['type' => 'photo', 'file_id' => $Message['Photo_File_ID']];
return null;
}

/** Attachment retrieval checks ownership independently of callback contents. */
public static function show(Context $Context, int $MessageId): void {
$Message = Repository::getTicketMessage($MessageId);
$Ticket = $Message !== null ? Repository::getTicket((int)$Message['Ticket_ID']) : null;
if ($Ticket === null || (!$Context->isAdmin() && (int)$Ticket['User_ID'] !== $Context->UserId)) return;
$Media = self::decode($Message);
$Ok = $Media !== null && self::send($Context->ChatId, $Media);
if (!$Ok) {
$Greeting = method_exists('Helper', 'userGreeting') ? Helper::userGreeting($Context, 'پیوست تیکت') : '';
$Footer = method_exists('Helper', 'userFooter') ? Helper::userFooter() : '';
TelegramClient::sendMessage($Context->ChatId, $Greeting . '⚠️پیوست در دسترس نیست؛ لطفاً فرستنده دوباره ارسال کند.' . $Footer);
}
}

public static function buttons(array $Messages, int $Page): array {
$Items = array_values(array_filter($Messages, static fn(array $M): bool => self::decode($M) !== null));
$Count = max(1, (int)ceil(count($Items) / 5));
$Page = max(0, min($Page, $Count - 1));
$Rows = [];
foreach (array_slice($Items, $Page * 5, 5) as $M) {
$Num = method_exists('Helper', 'toPersian') ? Helper::toPersian((string)$M['ID']) : (string)$M['ID'];
$Rows[] = [Menu::button('📎نمایش پیوست شماره ' . $Num, 'ticket_attachment:' . $M['ID'])];
}
return [$Rows, $Page, $Count];
}
}
