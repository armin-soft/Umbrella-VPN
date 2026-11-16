<?php
declare(strict_types=1);

// Exercise production menu and routing methods with in-memory dependencies only.
require_once dirname(__DIR__) . '/Bot/Menu.php';
if (!function_exists('mb_strlen')) {
function mb_strlen(string $Text): int { return count(preg_split('//u', $Text, -1, PREG_SPLIT_NO_EMPTY) ?: []); }
}
if (!function_exists('mb_substr')) {
function mb_substr(string $Text, int $Start, ?int $Length = null): string { return implode('', array_slice(preg_split('//u', $Text, -1, PREG_SPLIT_NO_EMPTY) ?: [], $Start, $Length)); }
}
final class Context {
public int $UserId = 1;
public int $ChatId = 1;
public ?int $MessageId = 10;
public ?string $CallbackId = 'test';
public bool $IsCallback = true;
public ?string $CallbackData = '';
public function __construct(private bool $Admin = true) {}
public function isAdmin(): bool { return $this->Admin; }
}
final class Repository {
public static array $Session = [];
public static array $Settings = [];
public static array $User = [];
public static function getUser(int $Id): array { return self::$User; }
public static function updateUserSession(int $Id, array $Values): void { self::$Session = array_replace(self::$Session, $Values); }
public static function getUserSession(int $Id): array { return self::$Session; }
public static function setSetting(string $Key, string $Value): void { self::$Settings[$Key] = $Value; }
}
final class Common {
public static function greet(Context $Context, string $Section): string { return $Section; }
public static function isRobotOn(): bool { return (Repository::$Settings['Robot_Status'] ?? '🟢روشن') === '🟢روشن'; }
}
final class Database {
public static function getInstance(): self { return new self(); }
public static array $Devices = [];
public static string $LastQuery = '';
public static array $LastParams = [];
public function scalar(string $Query, array $Params, int $Default): int { return str_contains($Query, 'App_Devices') ? count(self::$Devices) : 0; }
public function fetchAll(string $Query, array $Params): array {
self::$LastQuery = $Query;
self::$LastParams = $Params;
return array_slice(self::$Devices, $Params[1], $Params[0]);
}
}
final class Helper {
public static function adminGreeting(Context $Context, string $Section): string { return $Section; }
public static function adminFooter(): string { return ''; }
public static function userFooter(): string { return ''; }
public static function toPersian(string $Value): string { return $Value; }
}
final class TelegramClient {
public static array $Last = [];
public static string $Text = "";
public static function inlineKeyboard(array $Rows): array { return ['inline_keyboard' => $Rows]; }
public static function sendMessage(int $ChatId, string $Text, array $Markup = []): void { self::$Last = $Markup; self::$Text = $Text; }
public static function editOrSendMessage(int $ChatId, ?int $MessageId, string $Text, array $Markup = []): void { self::$Last = $Markup; self::$Text = $Text; }
public static function sendChatAction(int $ChatId): void {}
public static function answerCallbackQuery(?string $Id, string $Text, bool $Alert = false): void {}
}
// Skip production require_once side effects, but evaluate the entire original
// class declarations unchanged. Any unmocked dependency fails rather than doing I/O.
foreach (['AdminFlow' => 'Admin.php', 'UserFlow' => 'User.php', 'Dispatcher' => 'Dispatcher.php'] as $Class => $File) {
$Source = (string)file_get_contents(dirname(__DIR__) . '/Bot/' . $File);
$Start = strpos($Source, 'final class ' . $Class . ' {');
if ($Start === false) throw new RuntimeException('Missing class ' . $Class);
eval(preg_replace('/\?>\s*$/', '', substr($Source, $Start)));
}
$Passed = 0;
function check(bool $Ok, string $Name): void {
global $Passed;
if (!$Ok) throw new RuntimeException($Name);
$Passed++;
}
function calls(): array {
$Rows = TelegramClient::$Last['inline_keyboard'] ?? [];
check(Menu::problems($Rows) === [], 'valid rendered keyboard');
foreach ($Rows as $Row) check(count($Row) === 1, 'one button per row');
return $Rows === [] ? [] : array_column(array_merge(...$Rows), 'callback_data');
}
$Menus = [
'menu' => ['مدیریت', null, ['خاموش کردن ربات', 'اعتبار حساب کاربری', 'جرایم', 'admin_devices_menu', 'admin_accounts_menu', 'عملیات کلاینت سرور', 'پیکربندی سرور', 'منوی گزارش', 'منوی پیامک', 'admin_support_menu', 'admin_subscriptions_menu', 'منوی سیستم', 'بروز رسانی']],
'creditMenu' => ['اعتبار حساب کاربری', 'مدیریت', ['مشاهده اعتبار اول', 'افزایش اعتبار اول', 'کسر اعتبار اول']],
'crimes' => ['جرایم', 'مدیریت', ['مسدودیت اول', 'رفع مسدودیت اول', 'مشاهده مسدودی ها']],
'devicesMenu' => ['admin_devices_menu', 'مدیریت', ['admin_devices', 'device_limit_menu']],
'accountsMenu' => ['admin_accounts_menu', 'مدیریت', ['حذف کاربر اول', 'منقضی اشتراک اول']],
'serverClientsMenu' => ['عملیات کلاینت سرور', 'مدیریت', ['فعالسازی کلاینت اول', 'غیر فعالسازی کلاینت اول', 'بروز رسانی داده های کاربران اول']],
'serverConfig' => ['پیکربندی سرور', 'مدیریت', ['وضعیت سرور', 'سرویس های سرور', 'بروز رسانی میزان استفاده اول', 'تنظیمات ربات']],
'reportMenu' => ['منوی گزارش', 'مدیریت', ['آمار کلی', 'گزارش روزانه', 'گزارش مالی', 'رتبه بندی']],
'smsMenu' => ['منوی پیامک', 'مدیریت', ['ارسال پیامک تکی اول', 'ارسال پیامک همگانی اول', 'اطلاع رسانی اول', 'اطلاع رسانی سفارشی اول', 'اطلاع رسانی عدم استفاده', 'notify_all_start', 'app_push_start']],
'supportMenu' => ['admin_support_menu', 'مدیریت', ['مدیریت تیکت ها']],
'subscriptionsMenu' => ['admin_subscriptions_menu', 'مدیریت', ['cfg_pricing', 'cfg_links']],
'systemMenu' => ['منوی سیستم', 'مدیریت', ['پشتیبان گیری دیتابیس', 'تنظیم مجدد دیتابیس']],
];
$Context = new Context();
$Route = new ReflectionMethod(Dispatcher::class, 'routeCallbackInner');
foreach ($Menus as $Method => [$Call, $Parent, $Actions]) {
$Expected = $Actions;
if ($Parent !== null && $Parent !== 'مدیریت') $Expected[] = $Parent;
if ($Parent !== null) $Expected[] = 'مدیریت';
foreach ([true, false] as $Callback) {
$Context->IsCallback = $Callback;
Repository::$Session = ['Flow' => 'admin:credit_add_uid', 'Temp_UID' => 123, 'Broadcast_Mode' => 'sms'];
AdminFlow::$Method($Context);
check(calls() === $Expected, $Method . ': exact actions and parent navigation');
check(Repository::$Session === ['Flow' => null, 'Temp_UID' => null, 'Broadcast_Mode' => null], $Method . ': cancels stale input');
check(Repository::$Settings === [], $Method . ': opening menu does not mutate settings');
}
$Context->IsCallback = true;
$Context->CallbackData = $Call;
$Route->invoke(null, $Context);
check(calls() === $Expected, $Method . ': dispatcher reaches correct category');
Repository::$Session = ['Flow' => 'untouched'];
TelegramClient::$Last = [];
$Guest = new Context(false);
$Guest->CallbackData = $Call;
$Route->invoke(null, $Guest);
check(calls() === ['منوی خدمات ربات'], $Method . ': non-admin only gets user home');
check(Repository::$Session === ['Flow' => 'untouched'], $Method . ': unauthorized access cannot clear session');
}
foreach (['usersMenu' => 'menu', 'databaseMenu' => 'systemMenu', 'serverHealthMenu' => 'serverConfig', 'serverSyncMenu' => 'serverConfig', 'serverNotifyMenu' => 'smsMenu'] as $Alias => $Target) {
AdminFlow::$Target($Context);
$Expected = TelegramClient::$Last;
AdminFlow::$Alias($Context);
check(TelegramClient::$Last === $Expected, $Alias . ': legacy alias leads to category');
}
foreach (['credit_add_uid' => 'اعتبار حساب کاربری', 'credit_sub_uid' => 'اعتبار حساب کاربری', 'view_uid' => 'اعتبار حساب کاربری', 'block_uid' => 'جرایم', 'unblock_uid' => 'جرایم', 'activate_uid' => 'عملیات کلاینت سرور', 'deactivate_uid' => 'عملیات کلاینت سرور', 'delete_uid' => 'admin_accounts_menu', 'expire_uid' => 'admin_accounts_menu'] as $Flow => $Parent) {
AdminFlow::startInput($Context, 'admin:' . $Flow, 'prompt');
check(calls() === [$Parent, 'مدیریت'], $Flow . ': input returns to correct submenu');
check(Repository::$Session['Flow'] === 'admin:' . $Flow, $Flow . ': input state preserved');
}
foreach ([false, true] as $On) {
AdminFlow::toggleRobot($Context, $On);
check(Common::isRobotOn() === $On, 'robot toggle sets intended state');
$Expected = $Menus['menu'][2];
$Expected[0] = $On ? 'خاموش کردن ربات' : 'روشن کردن ربات';
check(calls() === $Expected, 'toggle stays on main admin menu');
}
// Reset is still a confirmation screen; merely opening it must not reset anything.
$Context->CallbackData = 'تنظیم مجدد دیتابیس';
$Route->invoke(null, $Context);
check(calls() === ['تایید تنظیم مجدد دیتابیس', 'منوی سیستم', 'مدیریت'], 'database reset confirmation is preserved');

// Parent navigation on the existing leaf screens (whose live data is not mocked).
$AdminSource = (string)file_get_contents(dirname(__DIR__) . '/Bot/Admin.php');
$LeafParents = [
'appDevicesMenu' => 'admin_devices_menu', 'deviceLimitMenu' => 'admin_devices_menu',
'blockedList' => 'جرایم', 'askUpdateUserData' => 'عملیات کلاینت سرور',
'globalStats' => 'منوی گزارش', 'dailyReport' => 'منوی گزارش',
'financialReport' => 'منوی گزارش', 'userRanking' => 'منوی گزارش',
'serverStatus' => 'پیکربندی سرور', 'serverServices' => 'پیکربندی سرور',
'updateAllUsages' => 'پیکربندی سرور', 'configMenu' => 'پیکربندی سرور',
'pricingMenu' => 'admin_subscriptions_menu', 'linksMenu' => 'admin_subscriptions_menu',
'databaseBackup' => 'منوی سیستم', 'databaseReset' => 'منوی سیستم',
'singleSmsMenu' => 'منوی پیامک', 'broadcastMenu' => 'منوی پیامک',
'notifySingleMenu' => 'منوی پیامک', 'serverNotifyCustomStart' => 'منوی پیامک',
'serverNotifyIdle' => 'منوی پیامک', 'appPushStart' => 'منوی پیامک', 'notifyAllStart' => 'منوی پیامک',
'ticketAdminMenu' => 'admin_support_menu',
];
foreach ($LeafParents as $Method => $Parent) {
$Start = strpos($AdminSource, 'public static function ' . $Method . '(');
$Remaining = substr($AdminSource, $Start + 1);
preg_match('/(?:public|private) static function /', $Remaining, $Match, PREG_OFFSET_CAPTURE);
$Body = substr($Remaining, 0, $Match[0][1]);
check(str_contains($Body, "Menu::back('منوی قبلی', '{$Parent}')"), $Method . ': leaf returns to its category');
check(str_contains($Body, 'Menu::adminHome()'), $Method . ': leaf keeps main menu');
}
$UserMenus = [
'serviceMenu' => ['منوی خدمات ربات', ['user_subscriptions_menu', 'user_wallet_menu', 'user_account_menu', 'user_stats_menu', 'منوی پشتیبانی', 'تغییرات نسخه']],
'subscriptionsMenu' => ['user_subscriptions_menu', ['اشتراک من', 'اشتراک آماده', 'اشتراک دلخواه', 'اشتراک رایگان اول', 'منوی تمدید خودکار']],
'walletMenu' => ['user_wallet_menu', ['شارژ اعتبار حساب کاربری', 'سابقه تراکنش']],
'accountMenu' => ['user_account_menu', ['پروفایل کاربری', 'ویرایش پروفایل', 'app_filter', 'app_filter_domains', 'app_notifications', 'app_devices', 'app_2fa']],
'statsMenu' => ['user_stats_menu', ['سابقه اشتراک', 'گزارش مصرف', 'رتبه بندی کاربران']],
'supportMenu' => ['منوی پشتیبانی', ['لیست تیکت های من', 'تیکت جدید']],
];
foreach ($UserMenus as $Method => [$Call, $Actions]) {
$Expected = $Method === 'serviceMenu' ? $Actions : array_merge($Actions, ['منوی خدمات ربات']);
foreach ([true, false] as $Callback) {
$UserContext = new Context(false);
$UserContext->IsCallback = $Callback;
Repository::$Session = ['Flow' => 'custom_plan_days', 'Pending_Payment' => 'preserved'];
UserFlow::$Method($UserContext);
check(calls() === $Expected, 'user ' . $Method . ': correct ordered menu');
check(Repository::$Session === ['Flow' => null, 'Pending_Payment' => 'preserved'], 'user category cancels input but preserves payment');
}
$UserContext->IsCallback = true;
$UserContext->CallbackData = $Call;
$Route->invoke(null, $UserContext);
check(calls() === $Expected, 'user ' . $Method . ': dispatcher routes category');
}
// Old security callbacks now open account settings, never a separate category.
$UserContext->CallbackData = 'user_security_menu';
$Route->invoke(null, $UserContext);
check(calls() === array_merge($UserMenus['accountMenu'][1], ['منوی خدمات ربات']), 'legacy security callback redirects to account');
$Now = time();
foreach ([
'active' => [['Subscription' => '۱ ماهه', 'Expiration_Time_Stamp' => $Now + 86400], true],
'no subscription' => [[], false],
'expired' => [['Subscription' => '۱ ماهه', 'Expiration_Time_Stamp' => $Now - 1], false],
'expiry boundary' => [['Subscription' => '۱ ماهه', 'Expiration_Time_Stamp' => $Now], false],
'unknown expiry' => [['Subscription' => '۱ ماهه'], true],
'blank subscription' => [['Subscription' => '  ', 'Expiration_Time_Stamp' => $Now + 86400], false],
'paused client' => [['Subscription' => '۱ ماهه', 'Expiration_Time_Stamp' => $Now + 86400, 'Server_Enable' => 0], true],
] as $Label => [$User, $HasSubscription]) {
Repository::$User = $User;
foreach ([true, false] as $Callback) {
$UserContext->IsCallback = $Callback;
Repository::$Session = ['Flow' => 'custom_plan_days', 'Pending_Payment' => 'preserved'];
UserFlow::subscriptionsMenu($UserContext);
$Expected = $HasSubscription ? ['اشتراک من', 'منوی تمدید خودکار', 'منوی خدمات ربات'] : array_merge($UserMenus['subscriptionsMenu'][1], ['منوی خدمات ربات']);
check(calls() === $Expected, $Label . ': correct subscription actions');
check(Repository::$Session === ['Flow' => null, 'Pending_Payment' => 'preserved'], $Label . ': navigation preserves payment');
}
}
Repository::$User = [];
$UserContext->IsCallback = true;
$SubscriptionSource = (string)file_get_contents(dirname(__DIR__) . '/Bot/Subscription.php');
preg_match('/public static function mySubscriptionActive\b.*?(?=(?:public|private) static function |\z)/s', $SubscriptionSource, $Match);
foreach (['اشتراک آماده', 'اشتراک دلخواه', 'اشتراک رایگان اول'] as $PurchaseAction) {
check(!str_contains($Match[0], "'callback_data' => '" . $PurchaseAction . "'"), 'active subscription details have no purchase action: ' . $PurchaseAction);
}
$UserLeafParents = [
'User.php' => ['profile' => 'user_account_menu', 'autoRenewMenu' => 'user_subscriptions_menu', 'transactionHistory' => 'user_wallet_menu', 'subscriptionHistory' => 'user_stats_menu', 'usageAnalytics' => 'user_stats_menu', 'usageRanking' => 'user_stats_menu', 'ticketNewStart' => 'منوی پشتیبانی', 'ticketUserList' => 'منوی پشتیبانی'],
'App-Link.php' => ['filterMenu' => 'user_account_menu', 'filterDomainsStart' => 'user_account_menu', 'notifications' => 'user_account_menu', 'devices' => 'user_account_menu', 'renderTwoStep' => 'user_account_menu'],
'Subscription.php' => ['mySubscription' => 'user_subscriptions_menu', 'mySubscriptionActive' => 'user_subscriptions_menu', 'buyMenu' => 'user_subscriptions_menu', 'readyPlansMenu' => 'user_subscriptions_menu', 'customPlansMenu' => 'user_subscriptions_menu', 'walletTopupStart' => 'user_wallet_menu'],
'Profile.php' => ['begin' => 'user_account_menu', 'askName' => 'user_account_menu'],
];
foreach ($UserLeafParents as $File => $Methods) {
$Source = (string)file_get_contents(dirname(__DIR__) . '/Bot/' . $File);
foreach ($Methods as $Method => $Parent) {
preg_match('/(?:public|private) static function ' . $Method . '\b.*?(?=(?:public|private) static function |\z)/s', $Source, $Match);
$Body = $Match[0] ?? '';
check(str_contains($Body, "Menu::back('منوی قبلی', '{$Parent}')"), $Method . ': correct user category parent');
check(str_contains($Body, 'Menu::userHome()'), $Method . ': keeps user home');
}
}
// Device cards: owner links, safe display, stable numbering and bounded pagination.
AdminFlow::devicesMenu($Context);
check(TelegramClient::$Text === "مدیریت دستگاه ها\n📌*بخش مورد نظر را انتخاب کنید:*", 'device category uses plain greeting section and separate prompt');
check(calls() === ['admin_devices', 'device_limit_menu', 'مدیریت'], 'device limit lives only in device management');
for ($Index = 0; $Index < 7; $Index++) {
Database::$Devices[] = [
'Device_ID' => str_pad((string)$Index, 64, 'a'),
'Device_Name' => 'Same device <b>name</b>', 'Platform' => 'Android',
'App_Version' => '1.2.3', 'Phone' => '09123456789',
'Owner_Name' => 'علی رضایی', 'Owner_Telegram_ID' => 123456789,
'Last_Seen_At' => '2026-11-16 12:30:00', 'Last_IP' => '192.0.2.1',
'Is_Trusted' => $Index % 2,
];
}
Database::$Devices[1]['Owner_Telegram_ID'] = null;
Database::$Devices[1]['Owner_Name'] = null;
Database::$Devices[1]['Last_Seen_At'] = null;
AdminFlow::appDevicesMenu($Context, -1);
$DeviceCalls = calls();
check(Database::$LastParams === [3, 0], 'negative device page clamps to first');
check(str_contains(TelegramClient::$Text, '<a href="tg://user?id=123456789">علی رضایی</a>'), 'full owner name opens correct Telegram profile');
check(!str_contains(TelegramClient::$Text, 'tg://user?id=0'), 'unknown owner is not linked to invented ID');
check(str_contains(TelegramClient::$Text, 'نام کامل ثبت نشده') && str_contains(TelegramClient::$Text, 'منشن در دسترس نیست'), 'missing identity is explicit');
check(str_contains(TelegramClient::$Text, 'آخرین فعالیت: ثبت نشده'), 'missing activity is not invented');
check(str_contains(TelegramClient::$Text, '&lt;b&gt;name&lt;/b&gt;'), 'device markup is escaped');
check(substr_count(TelegramClient::$Text, '📱دستگاه شماره') === 3, 'three clearly separated device cards');
check(!in_array('device_limit_menu', $DeviceCalls, true), 'no duplicate device limit shortcut in list');
check(in_array('admin_devices_page:1', $DeviceCalls, true), 'first page has next page');
check(!in_array('admin_devices_page:-1', $DeviceCalls, true), 'first page has no previous page');
check(str_contains(Database::$LastQuery, 'HAVING COUNT(*) = 1') && str_contains(Database::$LastQuery, 'COALESCE(`D`.`Telegram_ID`, 0) <= 0'), 'owner fallback is unique and cannot override Telegram identity');
AdminFlow::appDevicesMenu($Context, 999);
check(Database::$LastParams === [3, 6], 'oversized device page clamps to last');
$DeviceCalls = calls();
check(str_contains(TelegramClient::$Text, '📱دستگاه شماره 7'), 'numbering continues across pages');
check(in_array('admin_devices_page:1', $DeviceCalls, true) && !in_array('admin_devices_page:3', $DeviceCalls, true), 'last page has previous only');
check(str_ends_with($DeviceCalls[0], ':2'), 'toggle preserves page');
Database::$Devices = [];
AdminFlow::appDevicesMenu($Context, 4);
check(calls() === ['admin_devices_menu', 'مدیریت'], 'empty device list retains only parent and home');
check(str_contains(TelegramClient::$Text, 'هنوز دستگاهی'), 'empty device message');
echo "OK menu structure tests ({$Passed} assertions)\n";
