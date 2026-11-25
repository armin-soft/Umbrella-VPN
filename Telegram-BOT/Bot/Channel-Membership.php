<?php
declare(strict_types=1);
require_once __DIR__ . '/../Core/Storage/Repository.php';
require_once __DIR__ . '/../Core/Server/Umbrella-Server.php';
require_once __DIR__ . '/../Core/App/System-Notifications.php';
require_once __DIR__ . '/../Core/Telegram/Telegram.php';

/** Only undo the suspension this channel policy actually applied. */
final class ChannelMembership {
private const REASON = '🚫قطع به دلیل عدم عضویت';
private static function success(array $Response): bool {
$Code = (int)($Response['StatusCode'] ?? 0);
return $Code >= 200 && $Code < 300;
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
$Text = 'عضویت شما در کانال تایید شد و اشتراکی که به دلیل خروج از کانال متوقف شده بود، دوباره فعال شد.';
if (!method_exists(Repository::class, 'claimDailyNotice') || Repository::claimDailyNotice('channel_restored_app', $UserId)) {
SystemNotifications::queue($UserId, 'فعالسازی پس از عضویت کانال', $Text, 'channel-restored:' . $Disabled, 'success');
}
$Chat = (int)($User['Chat_ID'] ?? 0);
$CanSend = !method_exists(Repository::class, 'claimDailyNotice') || Repository::claimDailyNotice('channel_restored_tg', $UserId);
if ($Chat > 0 && $CanSend) { try { TelegramClient::sendMessage($Chat, '✅' . $Text); } catch (Throwable) {} }
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
