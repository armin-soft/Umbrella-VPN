<?php
declare(strict_types=1);

/**
 * Contract & regression suite for:
 * 1) Automatic channel membership detection (no manual recheck buttons)
 * 2) Removal of ad-block toggle from Telegram bot filter categories
 * 3) Security shield entry in Bot serviceMenu + detailed shield report screen
 * 4) Immediate admin notification when an app user registers & receives free plan
 * 5) Zero ZWNJ (U+200C) across modified PHP files
 */

$Root = dirname(__DIR__);
$Passed = 0;
$Assert = static function (bool $Cond, string $Msg) use (&$Passed): void {
if (!$Cond) {
fwrite(STDERR, "FAIL: {$Msg}\n");
exit(1);
}
$Passed++;
};

$Files = [
'Core/App/App-Filter.php',
'Core/App/App-Bot-Link.php',
'Core/App/App-Gateway.php',
'Bot/Channel-Membership.php',
'Bot/User.php',
'Bot/Dispatcher.php',
'Bot/Scheduler.php',
];

$Sources = [];
foreach ($Files as $Rel) {
$Content = (string)file_get_contents($Root . '/' . $Rel);
$Assert($Content !== '', "readable {$Rel}");
$Assert(!str_contains($Content, "\u{200C}"), "{$Rel} must contain zero ZWNJ (U+200C)");
$Sources[$Rel] = $Content;
}

// 1. No manual channel membership check buttons remain in User/Dispatcher/Scheduler.
foreach (['Bot/User.php', 'Bot/Dispatcher.php', 'Bot/Scheduler.php'] as $Rel) {
$Src = $Sources[$Rel];
$Assert(!str_contains($Src, '✅بررسی مجدد عضویت'), "{$Rel} must not expose ✅بررسی مجدد عضویت button");
$Assert(!str_contains($Src, '✅بررسی عضویت'), "{$Rel} must not expose ✅بررسی عضویت button");
$Assert(!str_contains($Src, '📢🔍بررسی عضویت در کانال'), "{$Rel} must not expose 📢🔍بررسی عضویت در کانال button");
}
$Assert(str_contains($Sources['Bot/Channel-Membership.php'], 'function markPendingJoin('), 'ChannelMembership tracks pending joiners');
$Assert(str_contains($Sources['Bot/Channel-Membership.php'], 'function fulfillPendingJoin('), 'ChannelMembership unlocks and resumes pending joiners automatically');
$Assert(str_contains($Sources['Bot/Channel-Membership.php'], 'self::fulfillPendingJoin($UserId, true)'), 'syncForApp auto-unlocks Telegram bot flow when user becomes channel member');
$Assert(str_contains($Sources['Bot/Scheduler.php'], 'checkPendingChannelJoins()'), 'Scheduler tick checks pending channel joins');
$Assert(str_contains($Sources['Bot/Scheduler.php'], 'ChannelMembership::fulfillPendingJoin($UserId, true)'), 'chat_member event triggers instant auto-unlock');
$Assert(str_contains($Sources['Core/App/App-Bot-Link.php'], 'function resumePendingById('), 'AppBotLink supports resuming pending link prompts after auto-join');

// 2. Telegram bot content filter excludes ads (always-on in apps), preserves DB compatibility.
$Filter_Code = preg_replace('/^<\?php\s*declare\(strict_types=1\);\s*/', '', $Sources['Core/App/App-Filter.php']) ?? '';
$Filter_Code = preg_replace('/require_once\s+[^;]+;/', '', $Filter_Code) ?? '';
if (!class_exists('Database')) {
eval('final class Database { public static function getInstance(): object { return new class { public function fetch(string $S, array $P = []): ?array { return null; } public function scalar(string $S, array $P = [], mixed $D = null): mixed { return $D; } }; } }');
}
if (!class_exists('AppFilter')) {
eval($Filter_Code);
}
$Assert(!array_key_exists('ads', AppFilter::BOT_CATEGORIES), 'AppFilter::BOT_CATEGORIES must not contain ads');
$Assert(array_key_exists('adult', AppFilter::BOT_CATEGORIES) && array_key_exists('gambling', AppFilter::BOT_CATEGORIES), 'AppFilter::BOT_CATEGORIES retains adult & gambling');
$Assert(array_key_exists('ads', AppFilter::CATEGORIES), 'AppFilter::CATEGORIES retains ads for backwards DB schema compatibility');

// 3. Dispatcher routes security shield & Admin signup notification exists in AppGateway.
$Assert(str_contains($Sources['Bot/Dispatcher.php'], "'user_security_shield' => [UserFlow::class, 'securityShieldMenu']"), 'Dispatcher maps user_security_shield route');
$Assert(str_contains($Sources['Bot/Dispatcher.php'], "str_starts_with(\$Data, 'user_security_shield:')"), 'Dispatcher routes paginated security shield pages');
$Assert(str_contains($Sources['Bot/User.php'], 'public static function securityShieldMenu('), 'UserFlow defines securityShieldMenu');
$Assert(str_contains($Sources['Bot/User.php'], 'public static function installedAppDevices('), 'UserFlow exposes installedAppDevices lookup');
$Assert(str_contains($Sources['Core/App/App-Gateway.php'], 'self::notifyAdminNewAppSignup('), 'resolveAccount notifies admin on new app signup');
$Assert(str_contains($Sources['Core/App/App-Gateway.php'], 'اشتراک رایگان کاربر فعال شد'), 'admin notification explicitly announces free plan activation');
$Assert(str_contains($Sources['Core/App/App-Gateway.php'], 'storeSecurityDeviceState('), 'AppGateway stores live device security shield state');

fwrite(STDOUT, "OK auto-channel, shield & signup tests ({$Passed} assertions)\n");
