<?php
declare(strict_types=1);
require_once __DIR__ . '/../Core/Storage/Repository.php';
require_once __DIR__ . '/../Core/Server/Umbrella-Server.php';
require_once __DIR__ . '/../Core/App/System-Notifications.php';
require_once __DIR__ . '/../Core/Telegram/Telegram.php';

/** Only undo the suspension this channel policy actually applied. */
final class ChannelMembership {
private const REASON = '🚫قطع به دلیل عدم عضویت';
private const PENDING_JOIN_KEY = 'App_Channel_Pending_Users';
private const PENDING_JOIN_TTL = 86400;
private const PENDING_JOIN_CAP = 300;
private static function success(array $Response): bool {
$Code = (int)($Response['StatusCode'] ?? 0);
return $Code >= 200 && $Code < 300;
}

/**
 * ذخیره وضعیت انتظار عضویت در کانال تا به محض پیوستن کاربر به کانال،
 * ربات بدون نیاز به زدن هیچ دکمه ای دسترسی را خودکار فعال کند.
 */
public static function markPendingJoin(int $UserId, int $ChatId = 0, ?int $MessageId = null): void {
if ($UserId <= 0 || !method_exists(Repository::class, 'getSetting') || !method_exists(Repository::class, 'setSetting')) return;
$Lock = 'channel_pending_map';
$Locked = method_exists(Repository::class, 'tryCronLock') ? Repository::tryCronLock($Lock, 15) : true;
try {
$Map = self::readPendingJoinMap();
$Now = time();
$Chat = $ChatId > 0 ? $ChatId : $UserId;
$PrevMsg = (int)($Map[(string)$UserId]['message_id'] ?? 0);
$MsgId = ($MessageId !== null && $MessageId > 0) ? $MessageId : $PrevMsg;
$Map[(string)$UserId] = [
'chat_id' => $Chat,
'message_id' => $MsgId,
'at' => $Now,
];
if (count($Map) > self::PENDING_JOIN_CAP) {
uasort($Map, static fn(array $A, array $B): int => ((int)($B['at'] ?? 0)) <=> ((int)($A['at'] ?? 0)));
$Map = array_slice($Map, 0, self::PENDING_JOIN_CAP, true);
}
Repository::setSetting(self::PENDING_JOIN_KEY, json_encode($Map, JSON_UNESCAPED_SLASHES) ?: '{}');
} catch (Throwable) {
} finally {
if ($Locked && method_exists(Repository::class, 'releaseCronLock')) {
Repository::releaseCronLock($Lock);
}
}
}

public static function clearPendingJoin(int $UserId): ?array {
if ($UserId <= 0 || !method_exists(Repository::class, 'getSetting') || !method_exists(Repository::class, 'setSetting')) return null;
$Lock = 'channel_pending_map';
$Locked = method_exists(Repository::class, 'tryCronLock') ? Repository::tryCronLock($Lock, 15) : true;
try {
$Map = self::readPendingJoinMap();
$Key = (string)$UserId;
if (!isset($Map[$Key])) return null;
$Entry = $Map[$Key];
unset($Map[$Key]);
Repository::setSetting(self::PENDING_JOIN_KEY, json_encode($Map, JSON_UNESCAPED_SLASHES) ?: '{}');
return $Entry;
} catch (Throwable) {
return null;
} finally {
if ($Locked && method_exists(Repository::class, 'releaseCronLock')) {
Repository::releaseCronLock($Lock);
}
}
}

/** @return list<int> */
public static function pendingUserIds(): array {
$Map = self::readPendingJoinMap();
if ($Map === []) return [];
$Out = [];
foreach ($Map as $Uid => $_Entry) {
$Id = (int)$Uid;
if ($Id > 0) $Out[] = $Id;
}
return $Out;
}

public static function isPendingJoin(int $UserId): bool {
if ($UserId <= 0) return false;
$Map = self::readPendingJoinMap();
return isset($Map[(string)$UserId]);
}

/** @return array<string, array{chat_id: int, message_id: int, at: int}> */
private static function readPendingJoinMap(): array {
if (!method_exists(Repository::class, 'getSetting')) return [];
try {
$Raw = trim((string)Repository::getSetting(self::PENDING_JOIN_KEY, ''));
if ($Raw === '') return [];
$Decoded = json_decode($Raw, true);
if (!is_array($Decoded)) return [];
$Cutoff = time() - self::PENDING_JOIN_TTL;
$Clean = [];
foreach ($Decoded as $Uid => $Item) {
if (!is_array($Item)) continue;
$At = (int)($Item['at'] ?? 0);
if ($At <= 0 || $At < $Cutoff) continue;
$Id = (int)$Uid;
if ($Id <= 0) continue;
$Clean[(string)$Id] = [
'chat_id' => (int)($Item['chat_id'] ?? $Id),
'message_id' => (int)($Item['message_id'] ?? 0),
'at' => $At,
];
}
return $Clean;
} catch (Throwable) {
return [];
}
}

/**
 * فعال سازی خودکار منوی کاربر و درخواست های معلق به محض پیوستن کاربر به کانال.
 */
public static function fulfillPendingJoin(int $UserId, bool $AlreadyRestored = false): bool {
if ($UserId <= 0) return false;
$Lock = 'channel_fulfill_' . $UserId;
if (method_exists(Repository::class, 'tryCronLock') && !Repository::tryCronLock($Lock, 60)) {
return false;
}
try {
$Pending = self::clearPendingJoin($UserId);
$User = Repository::getUser($UserId);
$Restored = false;
if (!$AlreadyRestored) {
$DisabledAt = (int)($User['Channel_Client_Disabled_At'] ?? 0);
$GraceAt = (int)($User['Channel_Grace_Started_At'] ?? 0);
if ($DisabledAt > 0 || $GraceAt > 0) {
$Restore = self::restore($UserId);
if ($Restore === 'restored') {
$Restored = true;
}
}
}
if ($Pending === null) {
if ($Restored && class_exists('UserFlow') && method_exists('UserFlow', 'onAutoChannelJoinedById')) {
try {
$ChatId = (int)($User['Chat_ID'] ?? $UserId);
$FullName = trim((string)($User['Full_Name'] ?? ($User['First_Name'] ?? 'کاربر'))) ?: 'کاربر';
if ($ChatId > 0) {
UserFlow::onAutoChannelJoinedById($UserId, $ChatId, $FullName);
}
} catch (Throwable) {}
}
return $Restored;
}

$ChatId = (int)($Pending['chat_id'] ?? 0);
if ($ChatId <= 0) $ChatId = (int)($User['Chat_ID'] ?? $UserId);
if ($ChatId <= 0) return false;

$MessageId = (int)($Pending['message_id'] ?? 0);
$FullName = trim((string)($User['Full_Name'] ?? ($User['First_Name'] ?? 'کاربر')));
if ($FullName === '') $FullName = 'کاربر';
$Frame = method_exists('Helper', 'frame')
? Helper::frame('کاربر', $FullName, 'منوی خدمات ربات', $UserId)
: '';
$Footer = method_exists('Helper', 'userFooter') ? Helper::userFooter() : '';
$WelcomeText = $Frame
. "✅عضویت شما در کانال به صورت خودکار تأیید شد!\n\n"
. "🎉به ربات فیلترشکن آمبرلا خوش آمدید.\n👇برای دیدن خدمات ربات، دکمه زیر را بزنید:"
. $Footer;
$Markup = TelegramClient::inlineKeyboard([
[['text' => '🤖📋منوی خدمات ربات', 'callback_data' => 'منوی خدمات ربات']],
]);

$Edited = false;
if ($MessageId > 0 && method_exists('TelegramClient', 'editMessageText')) {
try {
$Res = TelegramClient::editMessageText($ChatId, $MessageId, $WelcomeText, $Markup);
if (is_array($Res) && (($Res['ok'] ?? false) === true)) {
$Edited = true;
}
} catch (Throwable) {}
}
if (!$Edited) {
try {
TelegramClient::sendMessage($ChatId, $WelcomeText, $Markup);
} catch (Throwable) {}
}

if (class_exists('UserFlow') && method_exists('UserFlow', 'onAutoChannelJoinedById')) {
try {
UserFlow::onAutoChannelJoinedById($UserId, $ChatId, $FullName);
} catch (Throwable) {}
}
return true;
} catch (Throwable $Error) {
error_log('[Umbrella-Bot][Channel-Fulfill] ' . $Error->getMessage());
return false;
} finally {
if (method_exists(Repository::class, 'releaseCronLock')) {
Repository::releaseCronLock($Lock);
}
}
}
public static function restore(int $UserId): string {
$Lock = 'channel_client_' . $UserId;
if (!Repository::tryCronLock($Lock, 3600)) return 'pending';
try {
$User = Repository::getUser($UserId);
$Disabled = (int)($User['Channel_Client_Disabled_At'] ?? 0);
if ($Disabled <= 0) {
Repository::updateUser($UserId, ['Channel_Grace_Started_At' => null, 'Channel_Member_Check_At' => time()]);
return 'member';
}
$Client = trim((string)($User['Client_ID'] ?? ''));
if ($Client === '' || $Client === '_' || (int)($User['Is_Blocked'] ?? 0) === 1
|| trim((string)($User['Deactivation_Message'] ?? '')) !== ''
|| (string)($User['Client_Status'] ?? '') !== self::REASON
|| (int)($User['Expiration_Time_Stamp'] ?? 0) <= time()
|| trim((string)($User['Subscription'] ?? '')) === '') return 'ineligible';
$Live = ServerClient::getUser($Client);
$Data = $Live['Json'] ?? null;
if (!self::success($Live) || !is_array($Data)) return 'pending';
$Limit = (float)($Data['usage_limit_GB'] ?? 0);
if ($Limit > 0 && (float)($Data['current_usage_GB'] ?? 0) >= $Limit) return 'ineligible';
$Response = ServerClient::updateUser($Client, ['is_active' => true, 'enable' => true]);
if (!self::success($Response)) { error_log('[Umbrella-Bot][Channel-Restore] server refused user=' . $UserId); return 'pending'; }
Repository::updateUser($UserId, ['Channel_Grace_Started_At' => null, 'Channel_Client_Disabled_At' => null, 'Channel_Member_Check_At' => time(), 'Client_Status' => 'فعال', 'Server_Is_Active' => 1, 'Server_Enable' => 1]);
self::clearPendingJoin($UserId);
$Text = 'عضویت شما در کانال تایید شد و اشتراکی که به دلیل خروج از کانال متوقف شده بود، دوباره فعال شد.';
if (!method_exists(Repository::class, 'claimDailyNotice') || Repository::claimDailyNotice('channel_restored_app', $UserId)) {
SystemNotifications::queue($UserId, 'فعالسازی پس از عضویت کانال', $Text, 'channel-restored:' . $Disabled, 'success');
}
$Chat = (int)($User['Chat_ID'] ?? 0);
$CanSend = !method_exists(Repository::class, 'claimDailyNotice') || Repository::claimDailyNotice('channel_restored_tg', $UserId);
if ($Chat > 0 && $CanSend) {
$Frame = method_exists('Helper', 'frame')
? Helper::frame('کاربر', (string)($User['Full_Name'] ?? ''), 'عضویت در کانال', $UserId)
: '';
$Footer = method_exists('Helper', 'userFooter') ? Helper::userFooter() : '';
try { TelegramClient::sendMessage($Chat, $Frame . '✅' . $Text . $Footer); } catch (Throwable) {}
}
return 'restored';
} catch (Throwable $Error) { error_log('[Umbrella-Bot][Channel-Restore] ' . $Error->getMessage()); return 'pending'; }
finally { Repository::releaseCronLock($Lock); }
}

public static function suspend(int $UserId): bool {
$Lock = 'channel_client_' . $UserId;
if (!Repository::tryCronLock($Lock, 3600)) return false;
try {
$User = Repository::getUser($UserId);
$Client = trim((string)($User['Client_ID'] ?? ''));
if ($Client === '' || $Client === '_' || (int)($User['Channel_Client_Disabled_At'] ?? 0) > 0
|| (int)($User['Is_Blocked'] ?? 0) === 1 || trim((string)($User['Deactivation_Message'] ?? '')) !== ''
|| (int)($User['Expiration_Time_Stamp'] ?? 0) <= time() || str_contains((string)($User['Client_Status'] ?? ''), 'غیر')) return false;
$Live = ServerClient::getUser($Client);
$Data = $Live['Json'] ?? null;
// Never take ownership of a client already disabled by another actor.
if (!self::success($Live) || !is_array($Data) || !($Data['is_active'] ?? false) || !($Data['enable'] ?? true)) return false;
$Response = ServerClient::updateUser($Client, ['is_active' => false, 'enable' => false]);
if (!self::success($Response)) { error_log('[Umbrella-Bot][Channel-Suspend] server refused user=' . $UserId); return false; }
Repository::updateUser($UserId, ['Channel_Client_Disabled_At' => time(), 'Client_Status' => self::REASON, 'Server_Is_Active' => 0, 'Server_Enable' => 0]);
return true;
} catch (Throwable $Error) { error_log('[Umbrella-Bot][Channel-Suspend] ' . $Error->getMessage()); return false; }
finally { Repository::releaseCronLock($Lock); }
}

/**
 * وضعیت خلاصه عضویت کانال را برای برنامه محاسبه می کند و در صورت خروج،
 * مهلت ۵ دقیقه ای را شروع یا پس از اتمام مهلت کلاینت را متوقف می سازد.
 *
 * @return array{status: string, grace_remaining_seconds: int, disabled: bool, changed: bool}
 */
public static function syncForApp(int $UserId, int $CooldownSeconds = 60): array {
if ($UserId <= 0) {
return ['status' => 'unknown', 'grace_remaining_seconds' => 0, 'disabled' => false, 'changed' => false];
}
$User = Repository::getUser($UserId);
if ($User === []) {
return ['status' => 'unknown', 'grace_remaining_seconds' => 0, 'disabled' => false, 'changed' => false];
}
$ChannelUrl = class_exists('BotConfig') && method_exists('BotConfig', 'getChannelUrl')
? BotConfig::getChannelUrl() : '';
$ChannelId = class_exists('BotConfig') && method_exists('BotConfig', 'getTelegramChannelId')
? BotConfig::getTelegramChannelId() : '';
$Link = trim($ChannelUrl, "/ \t\n\r\0\x0B");
$Link = preg_replace('#^https?://#i', '', $Link) ?? $Link;
$Link = preg_replace('#^(?:t\.me|telegram\.me)/#i', '', $Link) ?? $Link;
$Link = preg_replace('~[?#].*$~', '', $Link) ?? $Link;
$Link = preg_replace('/^@/', '', $Link) ?? $Link;
$ChannelName = explode('/', $Link)[0] ?? '';
if (preg_match('/^[A-Za-z0-9_]{3,32}$/', $ChannelName) !== 1) $ChannelName = '';

$GraceSeconds = class_exists('Environment') && method_exists('Environment', 'getChannelGraceSeconds')
? Environment::getChannelGraceSeconds() : 300;
$Now = time();
$LastCheck = (int)($User['Channel_Member_Check_At'] ?? 0);
$GraceStartedAt = (int)($User['Channel_Grace_Started_At'] ?? 0);
$DisabledAt = (int)($User['Channel_Client_Disabled_At'] ?? 0);
$Changed = false;

if (($ChannelName !== '' || $ChannelId !== '') && method_exists('TelegramClient', 'channelMemberStatus')) {
$ShouldQuery = $LastCheck <= 0 || ($Now - $LastCheck) >= max(10, $CooldownSeconds) || $GraceStartedAt > 0 || $DisabledAt > 0;
if ($ShouldQuery) {
$MemberState = TelegramClient::channelMemberStatus($UserId, $ChannelName, $ChannelId);
if ($MemberState === 'member') {
if ($DisabledAt > 0 || $GraceStartedAt > 0) {
$Restore = self::restore($UserId);
$Changed = ($Restore === 'restored');
} else {
Repository::updateUser($UserId, ['Channel_Member_Check_At' => $Now]);
}
self::fulfillPendingJoin($UserId, true);
$User = Repository::getUser($UserId);
} elseif ($MemberState === 'not_member') {
Repository::updateUser($UserId, ['Channel_Member_Check_At' => $Now]);
if ($GraceStartedAt <= 0) {
$GraceStartedAt = $Now;
Repository::updateUser($UserId, ['Channel_Grace_Started_At' => $GraceStartedAt]);
if (!method_exists(Repository::class, 'claimDailyNotice') || Repository::claimDailyNotice('channel_warn_app', $UserId)) {
SystemNotifications::queue(
$UserId,
'هشدار عضویت کانال',
'شما عضو کانال اطلاع رسانی نیستید. اگر ظرف ۵ دقیقه عضو نشوید، اشتراک شما به طور موقت قطع می شود.',
'channel-warning:' . $GraceStartedAt . ':first',
'warning'
);
}
} elseif ($DisabledAt <= 0 && ($Now - $GraceStartedAt) >= $GraceSeconds) {
if (self::suspend($UserId)) {
$Changed = true;
if (!method_exists(Repository::class, 'claimDailyNotice') || Repository::claimDailyNotice('channel_disabled_app', $UserId)) {
SystemNotifications::queue(
$UserId,
'قطع به دلیل عضویت کانال',
'مهلت عضویت در کانال به پایان رسید و سرویس موقتاً قطع شد. پس از عضویت مجدد، اتصال بلافاصله فعال می شود.',
'channel-disabled:' . $GraceStartedAt,
'warning'
);
}
}
}
$User = Repository::getUser($UserId);
} elseif ($MemberState === 'unknown_participant') {
Repository::updateUser($UserId, ['Channel_Member_Check_At' => $Now]);
}
}
}

$GraceStartedAt = (int)($User['Channel_Grace_Started_At'] ?? 0);
$DisabledAt = (int)($User['Channel_Client_Disabled_At'] ?? 0);
if ($DisabledAt > 0 || (string)($User['Client_Status'] ?? '') === self::REASON) {
return ['status' => 'disabled', 'grace_remaining_seconds' => 0, 'disabled' => true, 'changed' => $Changed];
}
if ($GraceStartedAt > 0) {
$Remaining = max(0, $GraceSeconds - max(0, $Now - $GraceStartedAt));
return ['status' => 'grace', 'grace_remaining_seconds' => $Remaining, 'disabled' => false, 'changed' => $Changed];
}
return ['status' => 'member', 'grace_remaining_seconds' => 0, 'disabled' => false, 'changed' => $Changed];
}
}
