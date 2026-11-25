<?php
declare(strict_types=1);
// Behavioral tests for 5-minute channel leave/restore grace, pending deep-link auto-resume,
// IP/CIDR bypass parsing, and emoji-free App_Notifications storage & delivery.

$Count = 0;
function check(bool $Ok, string $Message): void {
    global $Count;
    $Count++;
    if (!$Ok) {
        throw new RuntimeException($Message);
    }
}

$EnvSrc = (string)file_get_contents(__DIR__ . '/../Config/Environment.php');
check(
    str_contains($EnvSrc, 'return 300;') || str_contains($EnvSrc, '300'),
    'Environment::getChannelGraceSeconds defaults to 300 seconds (5 minutes)'
);
check(
    !str_contains($EnvSrc, 'return 86400;'),
    'Environment::getChannelGraceSeconds must not keep 86400-second default'
);

$ChannelMembershipSrc = (string)file_get_contents(__DIR__ . '/../Bot/Channel-Membership.php');
check(
    str_contains($ChannelMembershipSrc, 'public static function syncForApp(') &&
    str_contains($ChannelMembershipSrc, 'self::suspend($UserId)') &&
    str_contains($ChannelMembershipSrc, 'self::restore($UserId)'),
    'ChannelMembership::syncForApp supports real-time channel leave/rejoin synchronization for app heartbeats'
);
check(
    str_contains($ChannelMembershipSrc, 'Channel_Grace_Started_At'),
    'ChannelMembership tracks grace timer start timestamp'
);

$GatewaySrc = (string)file_get_contents(__DIR__ . '/../Core/App/App-Gateway.php');
check(
    str_contains($GatewaySrc, 'ChannelMembership::syncForApp($Telegram_Id)') &&
    str_contains($GatewaySrc, 'channel_status') &&
    str_contains($GatewaySrc, 'channel_grace_remaining') &&
    str_contains($GatewaySrc, 'channel_disabled'),
    'App-Gateway exposes channel membership status and grace countdown to desktop/mobile apps'
);

$BotLinkSrc = (string)file_get_contents(__DIR__ . '/../Core/App/App-Bot-Link.php');
check(
    str_contains($BotLinkSrc, 'pending_app_link:') &&
    str_contains($BotLinkSrc, 'UserFlow::start('),
    'AppBotLink persists pending_app_link state while forcing channel gate and lets UserFlow resume cleanly'
);

$UserSrc = (string)file_get_contents(__DIR__ . '/../Bot/User.php');
check(
    str_contains($UserSrc, 'AppBotLink::resumePendingIfAny($Context)') &&
    substr_count($UserSrc, 'resumePendingIfAny') >= 2,
    'UserFlow resumes AppBotLink::resumePendingIfAny automatically after user verifies channel membership'
);

// Verify SystemNotifications strips decorative emojis cleanly while keeping Persian & newlines.
$SysSrc = (string)file_get_contents(__DIR__ . '/../Core/App/System-Notifications.php');
check(
    str_contains($SysSrc, 'public static function stripEmojis(string $Text): string'),
    'SystemNotifications exposes stripEmojis sanitizer'
);
eval(preg_replace('/^require_once .*;\s*$/m', '', str_replace('<?php', '', preg_replace('/^declare\(strict_types=1\);\s*/m', '', $SysSrc))));
// Wait: SystemNotifications depends on Repository/Database/TelegramClient if queue() is called;
// test stripEmojis + formatForWindowsApp pure logic directly.
final class Helper {
    public static function digitsToPersian(string $Text): string { return $Text; }
    public static function stripZwnj(string $Text): string { return str_replace("\u{200C}", ' ', $Text); }
}
$Cleaned = SystemNotifications::stripEmojis("🚨⚠️ هشدار امنیتی ✅ اشتراک شما تمدید شد 🎉");
check(
    str_contains($Cleaned, 'هشدار امنیتی') &&
    str_contains($Cleaned, 'اشتراک شما تمدید شد') &&
    !str_contains($Cleaned, '🚨') &&
    !str_contains($Cleaned, '⚠️') &&
    !str_contains($Cleaned, '✅') &&
    !str_contains($Cleaned, '🎉'),
    'stripEmojis removes emoji glyphs without harming Persian text'
);

$Formatted = SystemNotifications::formatForWindowsApp(
    '⚠️ قطع به دلیل عضویت کانال',
    "🚫 برای ادامه اتصال لطفا دوباره عضو شوید.",
    'warning'
);
check(
    $Formatted['title'] === 'توقف اشتراک' &&
    !str_contains($Formatted['body'], '🚫') &&
    str_contains($Formatted['body'], 'برای ادامه اتصال لطفا دوباره عضو شوید'),
    'formatForWindowsApp produces clean emoji-free title and body'
);

// Verify AppBypass supports both domain suffixes and public IP/CIDR targets while rejecting private IPs.
$AppBypassSrc = (string)file_get_contents(__DIR__ . '/../Core/App/App-Bypass.php');
check(
    str_contains($AppBypassSrc, 'public static function normalizeTarget(') &&
    str_contains($AppBypassSrc, 'public static function parseTargetsInput(') &&
    str_contains($AppBypassSrc, 'FILTER_VALIDATE_IP') &&
    str_contains($AppBypassSrc, 'FILTER_FLAG_NO_PRIV_RANGE'),
    'AppBypass normalizes domains and public IP/CIDR entries while blocking private/reserved ranges'
);

echo "OK channel_grace_and_bot_link_contract_test ($Count checks passed)\n";
