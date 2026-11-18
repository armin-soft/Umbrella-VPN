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
$Text = '✅عضویت شما در کانال تأیید شد و کلاینتی که به دلیل خروج از کانال قطع شده بود، دوباره فعال شد.';
SystemNotifications::queue($UserId, 'فعالسازی پس از عضویت کانال', $Text, 'channel-restored:' . $Disabled, 'success');
$Chat = (int)($User['Chat_ID'] ?? 0);
if ($Chat > 0) { try { TelegramClient::sendMessage($Chat, $Text); } catch (Throwable) {} }
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
}
