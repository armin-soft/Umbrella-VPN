<?php
declare(strict_types=1);

require_once __DIR__ . '/Context.php';
require_once __DIR__ . '/Common.php';
require_once __DIR__ . '/Admin.php';
require_once __DIR__ . '/User.php';
require_once __DIR__ . '/Profile.php';
require_once __DIR__ . '/App-Link.php';
require_once __DIR__ . '/../Core/App/App-Gateway.php';
require_once __DIR__ . '/Subscription.php';
require_once __DIR__ . '/../Core/Storage/Repository.php';
require_once __DIR__ . '/../Core/Support/Bot-Config.php';

final class Dispatcher {
private const ROUTES = [
'منوی خدمات ربات' => [UserFlow::class, 'serviceMenu'],
'منوی پشتیبانی' => [UserFlow::class, 'supportMenu'],
'گزارش مصرف' => [UserFlow::class, 'usageAnalytics'],
'ویرایش و ثبت پروفایل' => [ProfileFlow::class, 'begin'],
'ویرایش پروفایل' => [ProfileFlow::class, 'begin'],
'اشتراک من' => [SubscriptionFlow::class, 'mySubscription'],
'اشتراک رایگان اول' => [SubscriptionFlow::class, 'freePlan'],
'اشتراک نوروزی اول' => [SubscriptionFlow::class, 'nowruzPlan'],
'اشتراک آماده' => [SubscriptionFlow::class, 'readyPlansMenu'],
'اشتراک دلخواه' => [SubscriptionFlow::class, 'customPlansMenu'],
'ساخت اشتراک دلخواه' => [SubscriptionFlow::class, 'startCustomPlan'],
'حجم اشتراک دلخواه' => [SubscriptionFlow::class, 'startCustomPlanGB'],
'تایید اشتراک دلخواه' => [SubscriptionFlow::class, 'confirmCustomPlanCallback'],
'مدیریت' => [AdminFlow::class, 'menu'],
'آمار کلی' => [AdminFlow::class, 'globalStats'],
'تنظیمات' => [AdminFlow::class, 'menu'],
'اعتبار حساب کاربری' => [AdminFlow::class, 'creditMenu'],
'پیکربندی سرور' => [AdminFlow::class, 'serverConfig'],
'بروز رسانی' => [AdminFlow::class, 'updateMenu'],
'جرایم' => [AdminFlow::class, 'crimes'],
'رتبه بندی' => [AdminFlow::class, 'userRanking'],
'گزارش روزانه' => [AdminFlow::class, 'dailyReport'],
'رتبه بندی کاربران' => [UserFlow::class, 'usageRanking'],
];
private function __construct() {
}

public static function dispatch(Context $Context): void {
if ($Context->UserId <= 0) return;
$Context->saveUser();

if (!$Context->isAdmin() && Repository::isBlocked($Context->UserId)) {
self::blockNotice($Context);
return;
}

if (!$Context->isAdmin() && Common::isRobotOn()) {
$Callback = trim((string)$Context->CallbackData);
$Text = trim((string)$Context->Text);
$Is_Start = $Callback === 'start' || $Callback === '/start'
|| mb_strtolower($Callback) === 'start'
|| $Text === '/start' || mb_strtolower($Text) === 'start'
|| $Callback === 'بررسی عضویت کانال';

if (!$Is_Start && !UserFlow::checkChannelMembershipCached($Context->UserId)) {
self::channelGuard($Context);
return;
}
}

if (!$Context->isAdmin() && !Common::isRobotOn()) {
self::robotOffNotice($Context);
return;
}

if ($Context->IsCallback) {
try {
self::routeCallback($Context);
}

catch (Throwable $Error) {
self::reportDispatchError($Context, 'Callback', $Error);
}

return;
}

try {
self::routeMessage($Context);
}

catch (Throwable $Error) {
self::reportDispatchError($Context, 'Message', $Error);
}
}

private static function reportDispatchError(Context $Context, string $Type, Throwable $Error): void {
error_log('[Umbrella-Bot][Dispatch-' . $Type . '] ' . get_class($Error) . ': ' . $Error->getMessage() . ' @ ' . basename($Error->getFile()) . ':' . $Error->getLine());

if ($Context->ChatId > 0) {
try {
TelegramClient::sendMessage($Context->ChatId, Helper::userGreeting($Context, 'خطا') . "⚠️خطای موقت در پردازش درخواست رخ داد.\n➖➖➖➖➖➖➖➖➖➖\nلطفاً چند لحظه دیگر دوباره تلاش کنید." . Helper::userFooter());
}

catch (Throwable) {
}
}
}

private static function channelGuard(Context $Context): void {
$Channel_Url = BotConfig::getChannelUrl();
$Greeting = Common::greet($Context, 'عضویت در کانال');
$User = Repository::getUser($Context->UserId);
$Client_ID = (string)($User['Client_ID'] ?? '');
$Has_Client = $Client_ID !== '' && $Client_ID !== '_';
$Markup = TelegramClient::inlineKeyboard([
[['text' => '📢عضویت در کانال', 'url' => $Channel_Url]],
[['text' => '✅بررسی مجدد عضویت', 'callback_data' => 'بررسی عضویت کانال']],
]);

if (!$Has_Client) {
$Text = $Greeting . Helper::noticeBlock(
'📢جهت استفاده از امکانات ربات باید عضو کانال شوید.',
'⚠️علت:🚫عدم عضویت در کانال اطلاع رسانی',
'ℹ️پس از عضویت، دسترسی شما به ربات فعال می شود.'
) . Helper::userFooter();
}

else {
$Grace_Seconds = Environment::getChannelGraceSeconds();
$Grace_Started_At = (int)($User['Channel_Grace_Started_At'] ?? 0);

if ($Grace_Started_At <= 0) {
Repository::updateUser($Context->UserId, ['Channel_Grace_Started_At' => time()]);
$Grace_Started_At = time();
}

$Elapsed = time() - $Grace_Started_At;
$Remaining = $Grace_Seconds - $Elapsed;
$Minutes = (int)ceil(max(0, $Remaining) / 60);
$Hours = (int)floor($Minutes / 60);
$Mins = $Minutes % 60;
$Remaining_Label = $Hours > 0
? Helper::toPersian((string)$Hours) . " ساعت و " . Helper::toPersian((string)$Mins) . " دقیقه"
: Helper::toPersian((string)$Minutes) . " دقیقه";
$Text = $Greeting . Helper::noticeBlock(
'⛔️شما از کانال اطلاع رسانی خارج شده اید.',
"⚠️علت:🚫عدم عضویت در کانال اطلاع رسانی\n"
. "⏳مهلت باقیمانده: *{$Remaining_Label}*\n"
. 'ℹ️پس از عضویت مجدد، دسترسی شما به ربات فعال می شود؛ در غیر این صورت کلاینت شما به طور خودکار قطع خواهد شد.'
) . Helper::userFooter();
}

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '⛔️ابتدا عضو کانال شوید.', true);
}

if ($Context->IsCallback && $Context->MessageId !== null) {
try { TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Text, $Markup); } catch (Throwable) {
TelegramClient::sendMessage($Context->ChatId, $Text, $Markup);
}

return;
}

TelegramClient::sendMessage($Context->ChatId, $Text, $Markup);
}

private static function robotOffNotice(Context $Context): void {
$Text = Helper::userGreeting($Context, 'وضعیت ربات')
. Helper::noticeBlock(
'🪫📴ربات در دسترس نمی باشد.',
'⚠️علت:🤖🔴ربات جهت بروزرسانی موقتاً خاموش می باشد.',
'ℹ️لطفاً کمی بعد دوباره تلاش کنید.'
) . Helper::userFooter();
$Markup = TelegramClient::inlineKeyboard([
[['text' => '📞🧑‍💻ارتباط با پشتیبانی (آرمین سافت)', 'url' => BotConfig::getSupportUrl()]],
]);

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '📴ربات خاموش است.', true);
}

if ($Context->IsCallback && $Context->MessageId !== null) {
try { TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Text, $Markup); return; } catch (Throwable) {}
}

TelegramClient::sendMessage($Context->ChatId, $Text, $Markup);
}

private static function blockNotice(Context $Context): void {
$User = Repository::getUser($Context->UserId);
$Name = trim((string)($User['Full_Name'] ?? ''));

if ($Name === '') {
$Name = $Context->profileName();
}

$Text = Helper::userGreeting($Context, 'وضعیت حساب کاربری')
. Helper::noticeBlock(
'⛔️با عرض پوزش کاربر ' . $Name . ' به طور دائمی مسدود شده اید.',
'⚠️علت:🚫ارسال کلمات رکیک و نقض قوانین اخلاقی',
'ℹ️اگر فکر می کنید اشتباهی رخ داده است به پشتیبانی مراجعه کنید.'
) . Helper::userFooter();

$Markup = TelegramClient::inlineKeyboard([
[['text' => '📞🧑‍💻ارتباط با پشتیبانی (آرمین سافت)', 'url' => BotConfig::getSupportUrl()]],
]);

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, '⛔️شما مسدود شده اید.', true);
}

if ($Context->IsCallback && $Context->MessageId !== null) {
try { TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Text, $Markup); } catch (Throwable) {
TelegramClient::sendMessage($Context->ChatId, $Text, $Markup);
}

return;
}

TelegramClient::sendMessage($Context->ChatId, $Text, $Markup);
}

private static function routeCallback(Context $Context): void {
try {
self::routeCallbackInner($Context);
}

catch (Throwable $E) {
error_log('[Umbrella-Bot][Callback] ' . $E->getMessage());
TelegramClient::sendMessage($Context->ChatId, Helper::userGreeting($Context, 'خطا') . "❌خطایی در پردازش درخواست رخ داد.\n➖➖➖➖➖➖➖➖➖➖\nلطفاً چند لحظه دیگر دوباره تلاش کنید." . Helper::userFooter());
}
}

private static function routeCallbackInner(Context $Context): void {
$Data = trim((string)$Context->CallbackData);

if ($Data === '' || $Data === 'start' || $Data === '/start') {
UserFlow::start($Context);
return;
}

// ── device confirmation from the app ─────────────────────────────────────
// Handled before the channel guard and the menus: a sign-in waiting for an
// answer must always be answerable, whatever state the bot is in.
if (str_starts_with($Data, 'app_approve:') || str_starts_with($Data, 'app_deny:')) {
self::answerAppChallenge($Context, $Data);
return;
}

if (isset(self::ROUTES[$Data])) {
call_user_func(self::ROUTES[$Data], $Context);
return;
}

if (str_starts_with($Data, 'خرید اشتراک ')) {
SubscriptionFlow::payPlan($Context);
return;
}

match($Data) {
'ایجاد کلاینت' => SubscriptionFlow::retryCreation($Context),
'بررسی پرداخت' => SubscriptionFlow::verifyPayment($Context),
'پرداخت کسری کیف پول' => SubscriptionFlow::payTopup($Context),
'شارژ اعتبار حساب کاربری' => SubscriptionFlow::walletTopupStart($Context),
'لغو شارژ اعتبار' => SubscriptionFlow::walletTopupCancel($Context),
'افزایش اعتبار اول' => AdminFlow::startInput($Context, 'admin:credit_add_uid', '👌شناسه عددی یا شماره موبایل کاربر مورد نظر را وارد کنید.'),
'کسر اعتبار اول' => AdminFlow::startInput($Context, 'admin:credit_sub_uid', '👌شناسه عددی یا شماره موبایل کاربر مورد نظر را وارد کنید.'),
'مشاهده اعتبار اول' => AdminFlow::startInput($Context, 'admin:view_uid', '👌شناسه عددی یا شماره موبایل کاربر مورد نظر را وارد کنید.'),
'مشاهده مسدودی ها' => AdminFlow::blockedList($Context),
'مسدودیت اول' => AdminFlow::startInput($Context, 'admin:block_uid', '👌شناسه عددی یا شماره موبایل کاربر مورد نظر را وارد کنید.'),
'رفع مسدودیت اول' => AdminFlow::startInput($Context, 'admin:unblock_uid', '👌شناسه عددی یا شماره موبایل کاربر مورد نظر را وارد کنید.'),
'فعالسازی کلاینت اول' => AdminFlow::startInput($Context, 'admin:activate_uid', '👌شناسه عددی یا شماره موبایل کاربر مورد نظر را وارد کنید.'),
'غیر فعالسازی کلاینت اول' => AdminFlow::startInput($Context, 'admin:deactivate_uid', '👌شناسه عددی یا شماره موبایل کاربر مورد نظر را وارد کنید.'),
'حذف کاربر اول' => AdminFlow::startInput($Context, 'admin:delete_uid', '👌شناسه عددی یا شماره موبایل کاربر مورد نظر را وارد کنید.'),
'تایید حذف کاربر' => AdminFlow::deleteUserConfirm($Context),
'بروز رسانی داده های کاربران اول' => AdminFlow::askUpdateUserData($Context),
'ارسال پیامک همگانی اول' => AdminFlow::broadcastMenu($Context),
'پیام همگانی' => AdminFlow::broadcastMenu($Context),
'اطلاع رسانی همگانی اول' => AdminFlow::broadcastMenu($Context),
'ارسال پیامک همگانی تلگرام اول' => AdminFlow::startInputBroadcast($Context, 'telegram', '👌متن ارسال پیامک همگانی (تلگرام) را وارد کنید.'),
'ارسال پیامک همگانی پیامک اول' => AdminFlow::startInputBroadcast($Context, 'sms', '👌متن ارسال پیامک همگانی (پیامک) را وارد کنید.'),
'ارسال پیامک همگانی هر دو اول' => AdminFlow::startInputBroadcast($Context, 'both', '👌متن ارسال پیامک همگانی (تلگرام + پیامک) را وارد کنید.'),
'ارسال پیامک تکی تلگران اول' => AdminFlow::startInputSingleSmsUid($Context, 'telegram'),
'ارسال پیامک تکی پیامک اول' => AdminFlow::startInputSingleSmsUid($Context, 'sms'),
'ارسال پیامک تکی هر دو اول' => AdminFlow::startInputSingleSmsUid($Context, 'both'),
'اطلاع رسانی تلگران اول' => AdminFlow::startInputNotifyUid($Context, 'telegram'),
'اطلاع رسانی پیامک اول' => AdminFlow::startInputNotifyUid($Context, 'sms'),
'اطلاع رسانی هر دو اول' => AdminFlow::startInputNotifyUid($Context, 'both'),
'افزودن نسخه جدید اول' => AdminFlow::startInput($Context, 'admin:version_number', '👌شماره نسخه جدید ربات را وارد کنید.'),
'اطلاع رسانی اول' => AdminFlow::notifySingleMenu($Context),
'اطلاع رسانی سرور' => AdminFlow::serverNotifyMenu($Context),
'اطلاع رسانی' => AdminFlow::serverNotifyMenu($Context),
'اطلاع رسانی سفارشی اول' => AdminFlow::serverNotifyCustomStart($Context),
'اطلاع رسانی عدم استفاده' => AdminFlow::serverNotifyIdle($Context),
'تایید اطلاع رسانی غیرفعال' => AdminFlow::serverNotifyIdleSend($Context),
'دیتابیس' => AdminFlow::databaseMenu($Context),
'پشتیبان گیری دیتابیس' => AdminFlow::databaseBackup($Context),
'تنظیم مجدد دیتابیس' => AdminFlow::databaseReset($Context),
'تایید تنظیم مجدد دیتابیس' => AdminFlow::databaseResetConfirm($Context),
'منوی گزارش' => AdminFlow::reportMenu($Context),
'رتبه بندی' => AdminFlow::userRanking($Context),
'منوی پیامک' => AdminFlow::smsMenu($Context),
'گزارش مالی' => AdminFlow::financialReport($Context),
'مدیریت تیکت ها' => AdminFlow::ticketAdminMenu($Context),
'لیست تیکت باز' => AdminFlow::ticketAdminList($Context),
'ارسال پیامک تکی اول' => AdminFlow::singleSmsMenu($Context),
'منقضی اشتراک اول' => AdminFlow::startInput($Context, 'admin:expire_uid', '👌شناسه عددی یا شماره موبایل کاربر مورد نظر را وارد کنید.'),
'بروز رسانی میزان استفاده اول' => AdminFlow::updateAllUsages($Context),
'وضعیت سرور' => AdminFlow::serverStatus($Context),
'سرویس های سرور' => AdminFlow::serverServices($Context),
'بررسی عضویت کانال' => UserFlow::recheckChannelMembership($Context),
'حساب آمبرلا' => AppFlow::menu($Context),
'برنامه آمبرلا' => AppFlow::menu($Context),
'app_menu' => AppFlow::menu($Context),
'app_filter' => AppFlow::filterMenu($Context),
'app_2fa' => AppFlow::twoStepMenu($Context),
'app_2fa_on' => AppFlow::setTwoStep($Context, true),
'app_2fa_off' => AppFlow::setTwoStep($Context, false),
'app_devices' => AppFlow::devices($Context),
'app_notifications' => AppFlow::notifications($Context),
'app_filter_domains' => AppFlow::filterDomainsStart($Context),
'app_push_start' => AdminFlow::appPushStart($Context),
'device_limit_menu' => AdminFlow::deviceLimitMenu($Context),
'تنظیمات ربات' => AdminFlow::configMenu($Context),
'emergency_toggle' => AdminFlow::toggleEmergencyConfig($Context),
'emergency_url_start' => AdminFlow::emergencyUrlStart($Context),
'cfg_pricing' => AdminFlow::pricingMenu($Context),
'cfg_links' => AdminFlow::linksMenu($Context),
'notify_all_start' => AdminFlow::notifyAllStart($Context),
'device_limit_set_1' => AdminFlow::deviceLimitSet($Context, 1),
'device_limit_set_2' => AdminFlow::deviceLimitSet($Context, 2),
'device_limit_set_3' => AdminFlow::deviceLimitSet($Context, 3),
'device_limit_set_5' => AdminFlow::deviceLimitSet($Context, 5),
'device_limit_set_10' => AdminFlow::deviceLimitSet($Context, 10),
'روشن کردن ربات' => AdminFlow::toggleRobot($Context, true),
'خاموش کردن ربات' => AdminFlow::toggleRobot($Context, false),
'سابقه تراکنش' => UserFlow::transactionHistory($Context),
'سابقه اشتراک' => UserFlow::subscriptionHistory($Context),
'تیکت جدید' => UserFlow::ticketNewStart($Context),
'انتخاب دسته تیکت' => UserFlow::ticketCategoryMenu($Context),
'لیست تیکت های من' => UserFlow::ticketUserList($Context),
'تیکت های من' => UserFlow::ticketMenu($Context),
'پروفایل کاربری' => UserFlow::profile($Context),
'toggle_auto_renew' => UserFlow::toggleAutoRenew($Context),
'منوی تمدید خودکار' => UserFlow::toggleAutoRenew($Context),
'auto_renew_off' => UserFlow::disableAutoRenew($Context),
'تغییرات نسخه' => UserFlow::changes($Context),
default => null,
};

if (str_starts_with($Data, 'auto_renew_on_')) {
UserFlow::enableAutoRenew($Context);
return;
}

if (str_starts_with($Data, 'دسته تیکت:')) {
UserFlow::ticketCategoryCallback($Context, substr($Data, strlen('دسته تیکت:')));
return;
}

if (str_starts_with($Data, 'اولویت تیکت:')) {
UserFlow::ticketPriorityCallback($Context, substr($Data, strlen('اولویت تیکت:')));
return;
}

if (str_starts_with($Data, 'تیکت بدون تغییر')) {
UserFlow::ticketCategoryMenu($Context);
return;
}

if (str_starts_with($Data, 'حجم اشتراک دلخواه|')) {
SubscriptionFlow::customPlanGBCallback($Context, substr($Data, strlen('حجم اشتراک دلخواه|')));
return;
}

if (str_starts_with($Data, 'سابقه تراکنش|')) {
UserFlow::transactionHistory($Context);
return;
}

if (str_starts_with($Data, 'سابقه اشتراک|')) {
UserFlow::subscriptionHistory($Context);
return;
}

if (str_starts_with($Data, 'ticket_view:')) {
$ID = (int)substr($Data, strlen('ticket_view:'));

if ($ID > 0) AdminFlow::ticketAdminView($Context, $ID);
return;
}

if (str_starts_with($Data, 'ticket_reply:')) {
$ID = (int)substr($Data, strlen('ticket_reply:'));

if ($ID > 0) AdminFlow::ticketAdminReplyStart($Context, $ID);
return;
}

if (str_starts_with($Data, 'ticket_close:')) {
$ID = (int)substr($Data, strlen('ticket_close:'));

if ($ID > 0) AdminFlow::ticketAdminClose($Context, $ID);
return;
}

if (str_starts_with($Data, 'ticket_user_view:')) {
$ID = (int)substr($Data, strlen('ticket_user_view:'));

if ($ID > 0) UserFlow::ticketUserView($Context, $ID);
return;
}

if (str_starts_with($Data, 'ticket_user_reply:')) {
$ID = (int)substr($Data, strlen('ticket_user_reply:'));

if ($ID > 0) UserFlow::ticketUserReplyStart($Context, $ID);
return;
}

if (str_starts_with($Data, 'cfg_set:')) {
AdminFlow::cfgStart($Context, substr($Data, strlen('cfg_set:')));
return;
}

if (str_starts_with($Data, 'app_filter_toggle:')) {
AppFlow::filterToggle($Context, substr($Data, strlen('app_filter_toggle:')));
return;
}

if (str_starts_with($Data, 'app_device_revoke:')) {
AppFlow::revokeDevice($Context, substr($Data, strlen('app_device_revoke:')));
return;
}
}

/**
 * Answers a pending device sign-in.
 *
 * The app polls the challenge, so the decision is written to the row first and
 * the message is then rewritten to show what happened — the same button can
 * never answer twice in different directions.
 */
private static function answerAppChallenge(Context $Context, string $Data): void {
$Approved = str_starts_with($Data, 'app_approve:');
$Raw = str_starts_with($Data, 'app_approve:')
? substr($Data, strlen('app_approve:'))
: substr($Data, strlen('app_deny:'));
$Challenge = preg_replace('/[^a-f0-9]/', '', $Raw) ?? '';

try {
$Ok = AppGateway::decide($Challenge, $Approved, $Context->UserId);
}

catch (Throwable $Error) {
error_log('[Umbrella-Bot][AppChallenge] ' . $Error->getMessage());
$Ok = false;
}

if ($Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery(
$Context->CallbackId,
$Ok
? ($Approved ? '✅ ورود تأیید شد' : '⛔️ ورود مسدود شد')
: 'این درخواست معتبر نیست یا منقضی شده است.',
!$Ok
);
}

$Section = 'تأیید دستگاه';
$Text = $Ok
? ($Approved
? Helper::userGreeting($Context, $Section) . "✅ورود شما به برنامه تأیید شد.\n➖➖➖➖➖➖➖➖➖➖\nحالا برنامه به‌صورت خودکار وارد می‌شود." . Helper::userFooter()
: Helper::userGreeting($Context, $Section) . "⛔️ورود شما به برنامه مسدود شد.\n➖➖➖➖➖➖➖➖➖➖\n⚠️اگر خودتان نبودید، حتماً در ربات پشتیبانی را خبر کنید." . Helper::userFooter())
: Helper::userGreeting($Context, $Section) . "⌛️این درخواست دیگر معتبر نیست.\n➖➖➖➖➖➖➖➖➖➖\nاز برنامه دوباره وارد شوید." . Helper::userFooter();

$Markup = TelegramClient::inlineKeyboard([[
['text' => '📱 حساب آمبرلا', 'callback_data' => 'app_menu'],
]]);

if ($Context->MessageId !== null) {
try {
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, $Text, $Markup);
return;
}

catch (Throwable) {
}
}

TelegramClient::sendMessage($Context->ChatId, $Text, $Markup);
}

private static function routeMessage(Context $Context): void {
$Text = trim((string)$Context->Text);
$Has_Media = $Context->Photo !== null || ($Context->Caption ?? '') !== '';

if (!$Has_Media && $Text === '') return;
if ($Text === '/start' || mb_strtolower($Text) === 'start') {
UserFlow::start($Context);
return;
}

$CleanText = preg_replace('/[\x{200B}-\x{200F}\x{2060}\x{FEFF}]/u', '', $Text);
$CleanText = trim((string)$CleanText);

if (!$Context->isAdmin() && Helper::containsProfanity($CleanText)) {
try { Repository::setBlocked($Context->UserId, true); } catch (Throwable $E) {
error_log('[Umbrella-Bot][Profanity-Block] setBlocked failed: ' . $E->getMessage());
}

$Name = $Context->profileName();
$Safe_Name = str_replace(['[', ']', "\r", "\n"], '', $Name);
$Name_Mention = ($Safe_Name !== '') ? ('[' . $Safe_Name . '](tg://user?id=' . $Context->UserId . ')') : $Name;
$Admin = (int)Repository::getSetting('Administrator', (string)Environment::getAdminUserId());

if ($Admin > 0 && $Admin !== $Context->UserId) {
try {
TelegramClient::sendMessage($Admin, Helper::adminGreetingNamed((string)(Repository::getSetting('Admin_Full_Name') ?: Environment::getAdminFullName()), 'مسدودیت خودکار', $Admin)
. "🚫کاربر {$Name_Mention} (" . Helper::toPersian((string)$Context->UserId) . ") به دلیل ارسال کلمات رکیک به طور خودکار مسدود شد.\n📝متن ارسالی: " . mb_substr($CleanText, 0, 100) . Helper::adminFooter());
}

catch (Throwable) {}
}

TelegramClient::sendMessage($Context->ChatId, Helper::userGreeting($Context, 'وضعیت حساب کاربری')
. "⛔️با عرض پوزش به دلیل رعایت نکردن اصول اخلاقی، حساب کاربری شما به طور دائمی مسدود شد.\n➖➖➖➖➖➖➖➖➖➖\n⚠️نکته:اگر فکر می کنید اشتباهی رخ داده است به پشتیبانی مراجعه کنید." . Helper::userFooter(),
TelegramClient::inlineKeyboard([
[['text' => '📞🧑‍💻ارتباط با پشتیبانی (آرمین سافت)', 'url' => BotConfig::getSupportUrl()]],
]));
return;
}

if ($CleanText === 'مدیریت' || mb_strtolower($CleanText) === '/admin' || mb_strtolower($CleanText) === '/panel' || $CleanText === 'admin' || $CleanText === 'panel') {
if ($Context->isAdmin()) {
try {
AdminFlow::menu($Context);
}

catch (Throwable $E) {
error_log('[Umbrella-Bot][AdminMenu-Error] ' . $E->getMessage());
TelegramClient::sendMessage($Context->ChatId, Helper::adminGreeting($Context, 'منوی مدیریت') . "❌خطا در بارگذاری منوی مدیریت: " . mb_substr($E->getMessage(), 0, 200) . Helper::adminFooter());
}
}

else {
TelegramClient::sendMessage($Context->ChatId, Helper::userGreeting($Context, 'منوی مدیریت') . "⛔️شما دسترسی به این بخش ندارید." . Helper::userFooter());
}

return;
}

$Session = Repository::getUserSession($Context->UserId);
$Flow = (string)($Session['Flow'] ?? '');

if ($Flow !== '') {
if ($Context->isAdmin() && in_array($CleanText, ['مدیریت', '/admin', '/panel', 'admin', 'panel'], true)) {
AdminFlow::menu($Context);
return;
}

if (!str_starts_with($Flow, 'admin:') && in_array($CleanText, ['لغو', 'انصراف', '/cancel', 'cancel'], true)) {
Repository::updateUserSession($Context->UserId, ['Flow' => null, 'Temp_Ticket_ID' => null, 'Ticket_Subject' => null, 'Ticket_Description' => null]);
UserFlow::serviceMenu($Context);
return;
}

if (str_starts_with($Flow, 'admin:')) {
if (!$Context->isAdmin()) { return; }

try {
AdminFlow::handleInput($Context, $Flow, $Text);
}

catch (Throwable $E) {
error_log('[Umbrella-Bot][Admin-Input] Flow=' . $Flow . ' | ' . $E->getMessage());
TelegramClient::sendMessage($Context->ChatId, Helper::adminGreeting($Context, 'خطای ورودی') . '❌خطا در پردازش ورودی مدیریتی؛ لطفاً دوباره تلاش کنید.' . Helper::adminFooter(), TelegramClient::inlineKeyboard([
[['text' => '🏠منوی مدیریت', 'callback_data' => 'مدیریت']],
]));
}

return;
}

if ($Flow === 'profile_name') { ProfileFlow::processName($Context, $Text); return; }
if ($Flow === 'profile_phone') { ProfileFlow::processPhone($Context, $Text); return; }
if ($Flow === 'app:filter_domains') { AppFlow::filterDomainsInput($Context, $Text); return; }
if ($Flow === 'custom_plan_days' || $Flow === 'custom_plan_gb') { SubscriptionFlow::handleCustomPlanInput($Context, $Text); return; }
if ($Flow === 'wallet_topup_amount') { SubscriptionFlow::handleWalletTopupInput($Context, $Text); return; }
if ($Flow === 'user:ticket_subject') { UserFlow::ticketCreate($Context, $Text); return; }
if ($Flow === 'user:ticket_description') { UserFlow::ticketDescriptionInput($Context, $Text); return; }
if ($Flow === 'user:ticket_media') { UserFlow::ticketMediaInput($Context); return; }
if ($Flow === 'user:ticket_reply_text') { UserFlow::ticketUserReplySend($Context, $Text); return; }
// انتخاب دسته تیکت فقط با دکمه انجام می شود؛ متن فرستاده شده دوباره همان صفحه را نشان می دهد.
if ($Flow === 'user:ticket_category') { UserFlow::ticketCategoryMenu($Context); return; }
}

if (!$Has_Media) {
$Typed = preg_replace('/[\x{200B}-\x{200F}\x{2060}\x{FEFF}]/u', '', $Text);
$Typed = trim((string)$Typed);
$Typed_Routes = [
'اشتراک من' => fn() => SubscriptionFlow::mySubscription($Context),
'منوی خدمات کاربری' => fn() => UserFlow::serviceMenu($Context),
'منوی اصلی' => fn() => UserFlow::serviceMenu($Context),
'پروفایل کاربری' => fn() => UserFlow::profile($Context),
'شارژ اعتبار حساب کاربری' => fn() => SubscriptionFlow::walletTopupStart($Context),
'سابقه اشتراک' => fn() => UserFlow::subscriptionHistory($Context),
'گزارش مصرف' => fn() => UserFlow::usageAnalytics($Context),
'پشتیبانی' => fn() => UserFlow::supportMenu($Context),
'تیکت ها و پشتیبانی' => fn() => UserFlow::supportMenu($Context),
'تغییرات نسخه' => fn() => UserFlow::changes($Context),
'حساب آمبرلا' => fn() => AppFlow::menu($Context),
'کنترل محتوا' => fn() => AppFlow::filterMenu($Context),
];

foreach ($Typed_Routes as $Phrase => $Handler) {
if ($Typed === $Phrase) { $Handler(); return; }
}
}
}
}
?>