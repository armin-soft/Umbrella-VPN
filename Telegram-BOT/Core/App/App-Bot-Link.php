<?php
declare(strict_types=1);

/** Short-lived, single-use capability: the app session and Telegram user both consent. */
final class AppBotLink {
private const TTL = 600;
/** @var array<int, array{token: string, expires_at: int}> */
private static array $pendingByUser = [];
private function __construct() {}

private static function pendingKey(int $UserId): string {
return 'pending_app_link:' . $UserId;
}

private static function savePendingToken(int $UserId, string $Token): void {
if ($UserId <= 0 || preg_match('/^[a-f0-9]{32}$/D', $Token) !== 1) return;
$Payload = ['token' => $Token, 'expires_at' => time() + self::TTL];
self::$pendingByUser[$UserId] = $Payload;
if (class_exists('Repository') && method_exists('Repository', 'setSetting')) {
try {
Repository::setSetting(self::pendingKey($UserId), json_encode($Payload, JSON_UNESCAPED_SLASHES));
} catch (Throwable) {}
}
}

private static function popPendingToken(int $UserId): string {
if ($UserId <= 0) return '';
$Token = '';
$ExpiresAt = 0;
if (isset(self::$pendingByUser[$UserId])) {
$Token = (string)(self::$pendingByUser[$UserId]['token'] ?? '');
$ExpiresAt = (int)(self::$pendingByUser[$UserId]['expires_at'] ?? 0);
unset(self::$pendingByUser[$UserId]);
}
if (class_exists('Repository') && method_exists('Repository', 'getSetting')) {
try {
$Raw = trim((string)Repository::getSetting(self::pendingKey($UserId), ''));
if ($Raw !== '') {
$Decoded = json_decode($Raw, true);
if (is_array($Decoded)) {
$Token = (string)($Decoded['token'] ?? $Token);
$ExpiresAt = (int)($Decoded['expires_at'] ?? $ExpiresAt);
}
if (method_exists('Repository', 'setSetting')) {
Repository::setSetting(self::pendingKey($UserId), '');
}
}
} catch (Throwable) {}
}
if (preg_match('/^[a-f0-9]{32}$/D', $Token) !== 1 || ($ExpiresAt > 0 && $ExpiresAt < time())) {
return '';
}
return $Token;
}

public static function resumePendingIfAny(Context $Context): bool {
if ($Context->ChatId !== $Context->UserId || $Context->UserId <= 0) return false;
if (UserFlow::membershipStatus($Context->UserId) !== 'member') return false;
$Token = self::popPendingToken($Context->UserId);
if ($Token === '') return false;
self::presentPrompt($Context, $Token);
return true;
}

public static function resumePendingById(int $UserId, int $ChatId = 0, string $FullName = 'کاربر'): bool {
$TargetChat = $ChatId > 0 ? $ChatId : $UserId;
if ($UserId <= 0 || $TargetChat !== $UserId) return false;
if (class_exists('UserFlow') && method_exists('UserFlow', 'membershipStatus') && UserFlow::membershipStatus($UserId) !== 'member') {
return false;
}
$Token = self::popPendingToken($UserId);
if ($Token === '') return false;
$Db = Database::getInstance();
$Hash = hash('sha256', $Token);
$Db->execute('UPDATE `App_Bot_Link_Requests` SET `Telegram_ID` = ? WHERE `Token_Hash` = ? AND `Used_At` IS NULL AND `Expires_At` >= ? AND (`Telegram_ID` IS NULL OR `Telegram_ID` = ?)', [$UserId, $Hash, time(), $UserId]);
$Row = $Db->fetch('SELECT `Phone`, `Telegram_ID` FROM `App_Bot_Link_Requests` WHERE `Token_Hash` = ? AND `Used_At` IS NULL AND `Expires_At` >= ?', [$Hash, time()]);
$Greeting = method_exists('Helper', 'frame')
? Helper::frame('کاربر', $FullName !== '' ? $FullName : 'کاربر', 'اتصال برنامه به تلگرام', $UserId)
: '';
if ($Row === null || (int)$Row['Telegram_ID'] !== $UserId) {
TelegramClient::sendMessage($TargetChat, $Greeting . '⚠️این لینک منقضی شده یا متعلق به درخواست دیگری است؛ از حساب من لینک جدید بگیرید.' . self::footerText());
return true;
}
$Phone = (string)$Row['Phone'];
$PhoneLabel = method_exists('Helper', 'formatPhoneDisplay')
? Helper::formatPhoneDisplay($Phone, true)
: Helper::toPersian(substr($Phone, 0, 4) . '***' . substr($Phone, -4));
TelegramClient::sendMessage($TargetChat, $Greeting . '🔗آیا اتصال حساب برنامه با شماره ' . $PhoneLabel . ' به همین حساب تلگرام را تأیید می کنید؟ اگر خودتان درخواست نداده اید، تأیید نکنید.' . self::footerText(), TelegramClient::inlineKeyboard([
[['text' => '✅تأیید اتصال حساب', 'callback_data' => 'app_link:' . $Token]],
]));
return true;
}

public static function issue(array $Session): array {
$UUID = trim((string)($Session['User_UUID'] ?? ''));
$Device = (string)($Session['Device_ID'] ?? '');
$Db = Database::getInstance();
$DeviceRow = $Db->fetch('SELECT `Phone`, `Is_Trusted`, `User_UUID` FROM `App_Devices` WHERE `Device_ID` = ? LIMIT 1', [$Device]);
$SignIn = $Db->fetch("SELECT `Phone` FROM `App_SignIn_Requests` WHERE `Device_ID` = ? AND `User_UUID` = ? AND `Stage` = 'approved' AND SHA2(`Token`, 256) = ? ORDER BY `ID` DESC LIMIT 1", [$Device, $UUID, (string)($Session['Token_Hash'] ?? '')]);
$Phone = Helper::normalizePhone((string)($SignIn['Phone'] ?? ''));
if ($UUID === '' || $UUID === '_' || (string)($DeviceRow['User_UUID'] ?? '') !== $UUID || (int)($DeviceRow['Is_Trusted'] ?? 0) !== 1 || !Helper::validatePhone($Phone)) throw new RuntimeException('invalid_account');
$Linked = $Db->fetch('SELECT `Telegram_ID` FROM `Users` WHERE `Client_ID` = ? LIMIT 1', [$UUID]);
if ((int)($Linked['Telegram_ID'] ?? 0) > 0) {
$Panel = PanelClient::get($UUID);
if (!$Panel) throw new RuntimeException('panel_unavailable');
if ((int)($Panel['telegram_id'] ?? 0) === (int)$Linked['Telegram_ID']) return ['linked' => true];
}
$Username = BotIdentity::username();
if (!preg_match('/^[A-Za-z0-9_]{5,32}$/D', $Username)) throw new RuntimeException('bot_unavailable');
$Token = bin2hex(random_bytes(16));
$Db->execute('DELETE FROM `App_Bot_Link_Requests` WHERE `Expires_At` < ? OR (`Device_ID` = ? AND `Used_At` IS NULL)', [time(), $Device]);
$Db->execute('INSERT INTO `App_Bot_Link_Requests` (`Token_Hash`,`Session_Hash`,`User_UUID`,`Device_ID`,`Phone`,`Expires_At`) VALUES (?, ?, ?, ?, ?, ?)',
[hash('sha256', $Token), (string)$Session['Token_Hash'], $UUID, $Device, $Phone, time() + self::TTL]);
return ['linked' => false, 'url' => 'https://t.me/' . $Username . '?start=app_' . $Token, 'expires_in' => self::TTL];
}

private static function greetText(Context $Context, string $Section = 'اتصال برنامه به تلگرام'): string {
return method_exists('Helper', 'userGreeting') ? Helper::userGreeting($Context, $Section) : '';
}

private static function footerText(): string {
return method_exists('Helper', 'userFooter') ? Helper::userFooter() : '';
}

public static function begin(Context $Context, string $Token): void {
if ($Context->ChatId !== $Context->UserId || preg_match('/^[a-f0-9]{32}$/D', $Token) !== 1) return;
if (UserFlow::membershipStatus($Context->UserId) !== 'member') {
self::savePendingToken($Context->UserId, $Token);
UserFlow::start($Context);
TelegramClient::sendMessage($Context->ChatId, self::greetText($Context) . '⏳پس از عضویت و تأیید کانال، درخواست اتصال حساب به صورت خودکار ادامه پیدا می کند.' . self::footerText());
return;
}
self::presentPrompt($Context, $Token);
}

private static function presentPrompt(Context $Context, string $Token): void {
$Db = Database::getInstance();
$Hash = hash('sha256', $Token);
$Db->execute('UPDATE `App_Bot_Link_Requests` SET `Telegram_ID` = ? WHERE `Token_Hash` = ? AND `Used_At` IS NULL AND `Expires_At` >= ? AND (`Telegram_ID` IS NULL OR `Telegram_ID` = ?)', [$Context->UserId, $Hash, time(), $Context->UserId]);
$Row = $Db->fetch('SELECT `Phone`, `Telegram_ID` FROM `App_Bot_Link_Requests` WHERE `Token_Hash` = ? AND `Used_At` IS NULL AND `Expires_At` >= ?', [$Hash, time()]);
if ($Row === null || (int)$Row['Telegram_ID'] !== $Context->UserId) {
TelegramClient::sendMessage($Context->ChatId, self::greetText($Context) . '⚠️این لینک منقضی شده یا متعلق به درخواست دیگری است؛ از حساب من لینک جدید بگیرید.' . self::footerText()); return;
}
$Phone = (string)$Row['Phone'];
$PhoneLabel = method_exists('Helper', 'formatPhoneDisplay')
? Helper::formatPhoneDisplay($Phone, true)
: Helper::toPersian(substr($Phone, 0, 4) . '***' . substr($Phone, -4));
TelegramClient::sendMessage($Context->ChatId, self::greetText($Context) . '🔗آیا اتصال حساب برنامه با شماره ' . $PhoneLabel . ' به همین حساب تلگرام را تأیید می کنید؟ اگر خودتان درخواست نداده اید، تأیید نکنید.' . self::footerText(), TelegramClient::inlineKeyboard([
[['text' => '✅تأیید اتصال حساب', 'callback_data' => 'app_link:' . $Token]],
]));
}

public static function confirm(Context $Context, string $Token): void {
if ($Context->ChatId !== $Context->UserId || preg_match('/^[a-f0-9]{32}$/D', $Token) !== 1) return;
if (UserFlow::membershipStatus($Context->UserId) !== 'member') {
TelegramClient::sendMessage($Context->ChatId, self::greetText($Context) . '⚠️ابتدا عضویت کانال را تأیید کنید و لینک برنامه را دوباره باز کنید.' . self::footerText());
return;
}
$UuidLock = ''; $UserLock = ''; $PhoneLock = '';
try {
$Db = Database::getInstance();
$Hint = $Db->fetch('SELECT `User_UUID`, `Phone` FROM `App_Bot_Link_Requests` WHERE `Token_Hash` = ?', [hash('sha256', $Token)]);
if (!$Hint) throw new RuntimeException('expired');
$UuidLock = 'app_link_uuid_' . md5((string)$Hint['User_UUID']);
$UserLock = 'app_link_user_' . $Context->UserId;
if (!Repository::tryCronLock($UuidLock, 120)) { $UuidLock = ''; throw new RuntimeException('busy'); }
if (!Repository::tryCronLock($UserLock, 120)) { $UserLock = ''; throw new RuntimeException('busy'); }
$PhoneLock = 'app_link_phone_' . md5((string)$Hint['Phone']);
if (!Repository::tryCronLock($PhoneLock, 120)) { $PhoneLock = ''; throw new RuntimeException('busy'); }
$Linked_Panel = null;
$Db->transaction(static function ($Db) use ($Context, $Token, &$Linked_Panel): void {
$Row = $Db->fetch('SELECT * FROM `App_Bot_Link_Requests` WHERE `Token_Hash` = ? FOR UPDATE', [hash('sha256', $Token)]);
if (!$Row || $Row['Used_At'] !== null || (int)$Row['Expires_At'] < time() || (int)$Row['Telegram_ID'] !== $Context->UserId) throw new RuntimeException('expired');
$UUID = (string)$Row['User_UUID']; $Phone = (string)$Row['Phone']; $Id = $Context->UserId;
$Session = $Db->fetch('SELECT `S`.`User_UUID`, `S`.`Revoked_At`, `D`.`Is_Trusted`, `D`.`User_UUID` AS `Device_UUID` FROM `App_Sessions` AS `S` JOIN `App_Devices` AS `D` ON `D`.`Device_ID` = `S`.`Device_ID` WHERE `S`.`Token_Hash` = ? AND `S`.`Device_ID` = ? FOR UPDATE', [$Row['Session_Hash'], $Row['Device_ID']]);
if (!$Session || $Session['Revoked_At'] !== null || (int)$Session['Is_Trusted'] !== 1 || $Session['User_UUID'] !== $UUID || $Session['Device_UUID'] !== $UUID) throw new RuntimeException('expired');
$User = $Db->fetch('SELECT `Client_ID`, `Phone`, `Is_Blocked` FROM `Users` WHERE `Telegram_ID` = ? FOR UPDATE', [$Id]);
if (!$User || (int)($User['Is_Blocked'] ?? 0) === 1) throw new RuntimeException('conflict');
$Client = trim((string)($User['Client_ID'] ?? '')); $ExistingPhone = trim((string)($User['Phone'] ?? ''));
if (($Client !== '' && $Client !== '_' && $Client !== $UUID) || ($ExistingPhone !== '' && Helper::normalizePhone($ExistingPhone) !== $Phone)) throw new RuntimeException('conflict');
$Other = $Db->fetch('SELECT `Telegram_ID` FROM `Users` WHERE `Client_ID` = ? AND `Telegram_ID` <> ? LIMIT 1 FOR UPDATE', [$UUID, $Id]);
if ($Other || Repository::findUserByPhone($Phone, $Id) !== []) throw new RuntimeException('conflict');
$ExistingPanel = PanelClient::findByTelegramId($Id);
if (PanelClient::lastListError() !== null) throw new RuntimeException('panel_unavailable');
if ($ExistingPanel && (string)($ExistingPanel['uuid'] ?? '') !== $UUID) throw new RuntimeException('conflict');
$Panel = PanelClient::get($UUID);
if (!$Panel) throw new RuntimeException('panel_unavailable');
$PanelId = (int)($Panel['telegram_id'] ?? 0);
if ($PanelId > 0 && $PanelId !== $Id) throw new RuntimeException('conflict');
if ($PanelId !== $Id) {
if (!PanelClient::update($UUID, ['telegram_id' => $Id])) throw new RuntimeException('panel_unavailable');
$Panel = PanelClient::get($UUID);
if ((int)($Panel['telegram_id'] ?? 0) !== $Id) throw new RuntimeException('panel_unavailable');
}
$Linked_Panel = $Panel;
$SignIn = $Db->fetch("SELECT `Full_Name` FROM `App_SignIn_Requests` WHERE `User_UUID` = ? AND `Device_ID` = ? AND `Phone` = ? AND `Stage` = 'approved' ORDER BY `ID` DESC LIMIT 1", [$UUID, $Row['Device_ID'], $Phone]);
$Name = trim((string)($SignIn['Full_Name'] ?? ''));
if ($Name === '' || in_array($Name, ['_', 'کاربر', 'کاربر آمبرلا'], true) || preg_match('/^user-[0-9]+$/i', $Name) === 1) {
$SignInAny = $Db->fetch("SELECT `Full_Name` FROM `App_SignIn_Requests` WHERE (`User_UUID` = ? OR `Phone` = ?) AND `Full_Name` IS NOT NULL AND LENGTH(TRIM(`Full_Name`)) > 0 ORDER BY `ID` DESC LIMIT 1", [$UUID, $Phone]);
$Candidate = trim((string)($SignInAny['Full_Name'] ?? ''));
if ($Candidate !== '' && !in_array($Candidate, ['_', 'کاربر', 'کاربر آمبرلا'], true) && preg_match('/^user-[0-9]+$/i', $Candidate) !== 1) {
$Name = $Candidate;
} else {
$Name = '';
}
}
if ($Name === '') {
$DevRow = $Db->fetch('SELECT `Full_Name` FROM `App_Devices` WHERE `Device_ID` = ? LIMIT 1', [$Row['Device_ID']]);
$Candidate = trim((string)($DevRow['Full_Name'] ?? ''));
if ($Candidate !== '' && !in_array($Candidate, ['_', 'کاربر', 'کاربر آمبرلا'], true) && preg_match('/^user-[0-9]+$/i', $Candidate) !== 1) {
$Name = $Candidate;
}
}
if ($Name === '') {
$Candidate = trim((string)($Panel['name'] ?? ''));
if ($Candidate !== '' && !in_array($Candidate, ['_', 'کاربر', 'کاربر آمبرلا'], true) && preg_match('/^user-[0-9]+$/i', $Candidate) !== 1) {
$Name = $Candidate;
}
}
$Db->execute('UPDATE `Users` SET `Client_ID` = ?, `Phone` = CASE WHEN `Phone` IS NULL OR `Phone` = ? THEN ? ELSE `Phone` END, `Full_Name` = CASE WHEN `Full_Name` IS NULL OR `Full_Name` = ? THEN ? ELSE `Full_Name` END WHERE `Telegram_ID` = ?', [$UUID, '', $Phone, '', $Name, $Id]);
$Db->execute('UPDATE `App_Devices` SET `Telegram_ID` = ?, `Full_Name` = CASE WHEN (`Full_Name` IS NULL OR `Full_Name` = \'\') AND ? <> \'\' THEN ? ELSE `Full_Name` END WHERE `User_UUID` = ? AND (`Telegram_ID` IS NULL OR `Telegram_ID` = 0 OR `Telegram_ID` = ?)', [$Id, $Name, $Name, $UUID, $Id]);
$Db->execute('UPDATE `App_Sessions` SET `Telegram_ID` = ? WHERE `User_UUID` = ? AND (`Telegram_ID` IS NULL OR `Telegram_ID` = 0 OR `Telegram_ID` = ?)', [$Id, $UUID, $Id]);
$Db->execute('UPDATE `App_Bot_Link_Requests` SET `Used_At` = ? WHERE `Token_Hash` = ?', [time(), hash('sha256', $Token)]);
});
if (is_array($Linked_Panel) && class_exists('Common') && method_exists('Common', 'syncSubscriptionFromServer') && method_exists('Repository', 'getUser')) {
try {
$Fresh_User = Repository::getUser($Context->UserId);
if ($Fresh_User !== []) {
Common::syncSubscriptionFromServer($Fresh_User, $Linked_Panel);
}
} catch (Throwable) {}
}
TelegramClient::sendMessage($Context->ChatId, self::greetText($Context) . '✅حساب برنامه و ربات متصل شد. اطلاعات در پنل و برنامه همگام می شود.' . self::footerText());
} catch (Throwable $Error) {
error_log('[Umbrella-Bot][App-Bot-Link] ' . $Error->getMessage());
$Message = match ($Error->getMessage()) {
'conflict' => 'این تلگرام، شماره یا حساب پنل قبلاً به حساب دیگری متصل شده است؛ برای بررسی با پشتیبانی تماس بگیرید.',
'expired' => 'لینک منقضی یا استفاده شده است؛ از برنامه لینک جدید بگیرید.',
default => 'همگام سازی کامل نشد؛ کمی بعد دوباره با همین دکمه تلاش کنید یا با پشتیبانی تماس بگیرید.',
};
TelegramClient::sendMessage($Context->ChatId, self::greetText($Context) . '⚠️' . $Message . self::footerText());
} finally {
if ($PhoneLock !== '') Repository::releaseCronLock($PhoneLock);
if ($UserLock !== '') Repository::releaseCronLock($UserLock);
if ($UuidLock !== '') Repository::releaseCronLock($UuidLock);
}
if ($Context->CallbackId !== null) TelegramClient::answerCallbackQuery($Context->CallbackId);
}
}
