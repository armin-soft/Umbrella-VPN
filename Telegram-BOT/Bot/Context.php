<?php
declare(strict_types=1);

require_once __DIR__ . '/../Core/Storage/Repository.php';
require_once __DIR__ . '/../Config/Environment.php';

final readonly class Context {
public function __construct(
public array $Raw,
public int $UserId,
public int $ChatId,
public string $FirstName,
public bool $IsCallback,
public ?string $CallbackData,
public ?string $CallbackId,
public ?int $MessageId,
public ?string $Text,
public ?string $Photo = null,
public ?string $Caption = null,
public ?string $Username = null,
) {
}

public static function fromUpdate(array $Update): self {
$Callback = $Update['callback_query'] ?? null;
$Message = $Update['message'] ?? ($Update['edited_message'] ?? null);

if ($Callback !== null) {
$From = $Callback['from'] ?? [];
$Chat = $Callback['message']['chat'] ?? [];

return new self(
$Update,
(int)($From['id'] ?? 0),
(int)($Chat['id'] ?? $From['id'] ?? 0),
(string)($From['first_name'] ?? ''),
true,
isset($Callback['data']) ? (string)$Callback['data'] : null,
isset($Callback['id']) ? (string)$Callback['id'] : null,
isset($Callback['message']['message_id']) ? (int)$Callback['message']['message_id'] : null,
null,
Username: (string)($From['username'] ?? ''),
);
}

$Chat = $Message['chat'] ?? [];
$From = $Message['from'] ?? $Chat;
$Photo = null;

if (isset($Message['photo']) && is_array($Message['photo'])) {
$PhotoArray = $Message['photo'];
$Last = $PhotoArray[count($PhotoArray) - 1];

if (isset($Last['file_id']) && is_string($Last['file_id'])) {
$Photo = $Last['file_id'];
}
}

return new self(
$Update,
(int)($From['id'] ?? 0),
(int)($Chat['id'] ?? 0),
(string)($From['first_name'] ?? 'کاربر'),
false,
null,
null,
isset($Message['message_id']) ? (int)$Message['message_id'] : null,
isset($Message['text']) ? (string)$Message['text'] : null,
$Photo,
isset($Message['caption']) ? (string)$Message['caption'] : null,
Username: (string)($From['username'] ?? ''),
);
}

public function isAdmin(): bool {
$EnvAdmin = Environment::getAdminUserId();
$DbAdmin = (int)Repository::getSetting('Administrator', (string)$EnvAdmin);
return in_array($this->ChatId, [$EnvAdmin, $DbAdmin], true)
|| in_array($this->UserId, [$EnvAdmin, $DbAdmin], true);
}

public function saveUser(): void {
Repository::createUserIfMissing($this->UserId);
$Fields = [
'First_Name' => $this->FirstName,
'Chat_ID' => $this->ChatId,
];

$Username = ltrim(trim((string)$this->Username), '@');

if (preg_match('/^[A-Za-z][A-Za-z0-9_]{3,63}$/', $Username) === 1) {
$Fields['Username'] = $Username;
}

Repository::updateUser($this->UserId, $Fields);
}

public function profileName(): string {
$Full = trim((string)(Repository::getUser($this->UserId)['Full_Name'] ?? ''));
$Display = $Full !== '' ? $Full : $this->FirstName;
return $Display !== '' ? $Display : 'کاربر';
}

public function profileEmoji(): string {
return '👤';
}
}
?>