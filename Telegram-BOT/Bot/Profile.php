<?php
declare(strict_types=1);

require_once __DIR__ . '/Context.php';
require_once __DIR__ . '/Common.php';
require_once __DIR__ . '/../Core/Telegram/Telegram.php';
require_once __DIR__ . '/../Core/Server/Umbrella-Server.php';
require_once __DIR__ . '/../Core/Support/Helper.php';
require_once __DIR__ . '/../Core/Storage/Repository.php';

final class ProfileFlow {
private const FLOW_NAME = 'profile_name';
private const FLOW_PHONE = 'profile_phone';
private function __construct() {
}

public static function begin(Context $Context): void {
$User = Repository::getUser($Context->UserId);
$Profile_Updated_At = (string)($User['Profile_Updated_At'] ?? '');
$Has_Full_Name = trim((string)($User['Full_Name'] ?? '')) !== '';
$Has_Phone = trim((string)($User['Phone'] ?? '')) !== '';
$Profile_Is_Complete = $Has_Full_Name && $Has_Phone;
$Has_Profile = $Profile_Updated_At !== '' && $Profile_Updated_At !== '0000-00-00 00:00:00';

if ($Profile_Is_Complete && $Has_Profile) {
$Last_Update = (int)strtotime($Profile_Updated_At);
$Now = time();
$Days_Since = (int)(($Now - $Last_Update) / 86400);

if ($Days_Since < 30) {
$Remaining = 30 - $Days_Since;
$Remaining_Fa = Helper::toPersian((string)$Remaining);

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, "⛔️ویرایش پروفایل هر ۳۰ روز یکبار مجاز است.\n⚠️{$Remaining_Fa} روز تا ویرایش بعدی باقی مانده.", true);
}

else {
TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'پروفایل کاربری') . "⛔️ویرایش پروفایل کاربری هر ۳۰ روز یکبار مجاز می باشد.\n➖➖➖➖➖➖➖➖➖➖\n⚠️تعداد روزهای باقی مانده تا ویرایش بعدی: `{$Remaining_Fa}` روز." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '👤پروفایل کاربری', 'callback_data' => 'پروفایل کاربری']],
Menu::userHome(),
]));
}

return;
}
}

if ($Context->IsCallback && $Context->CallbackId !== null) {
TelegramClient::answerCallbackQuery($Context->CallbackId, $Profile_Is_Complete ? '✏️ویرایش پروفایل' : '📝ثبت پروفایل', false);
}

Repository::updateUserSession($Context->UserId, ['Flow' => self::FLOW_NAME]);
$Welcome_Text = $Profile_Is_Complete
? "🙇‍♂️لطفا به پرسش هایی که از شما پرسیده می شود به دقت پاسخ دهید."
: "🙇‍♂️لطفا به پرسش هایی که از شما پرسیده می شود به دقت پاسخ دهید.\n\n⚠️نکته:وارد کردن اطلاعات کاربری الزامی می باشد.";
TelegramClient::editMessageText($Context->ChatId, $Context->MessageId, Common::greet($Context, 'پروفایل کاربری') . $Welcome_Text . Helper::userFooter());
self::askName($Context);
}

private static function askName(Context $Context): void {
TelegramClient::sendMessage($Context->ChatId, Helper::userGreeting($Context, 'پروفایل کاربری') . "⁉️پرسش اول:نام و نام خانوادگی خود را وارد کنید.\n➖➖➖➖➖➖➖➖➖➖\n⚠️نکته:فرمت ارسالی باید حروف فارسی و حداقل دو کلمه باشد." . Helper::userFooter());
}

public static function processName(Context $Context, string $Text): void {
if (!Helper::validateFullName($Text)) {
TelegramClient::sendMessage($Context->ChatId, Helper::userGreeting($Context, 'پروفایل کاربری') . "❌خطا: نام و نام خانوادگی وارد شده صحیح نمی باشد.\n➖➖➖➖➖➖➖➖➖\n⚠️نکته:فرمت ارسالی باید حروف فارسی و حداقل دو کلمه باشد." . Helper::userFooter());
self::askName($Context);
return;
}

$Full_Name = trim((string)preg_replace('/\s+/u', ' ', $Text));
$Old_User = Repository::getUser($Context->UserId);
$Old_Phone = trim((string)($Old_User['Phone'] ?? ''));
$Old_Client_ID = trim((string)($Old_User['Client_ID'] ?? ''));
$Old_Has_Phone = $Old_Phone !== '';
$Old_Has_Client = $Old_Client_ID !== '' && $Old_Client_ID !== '_';
Repository::updateUser($Context->UserId, ['Full_Name' => $Full_Name]);

if ($Old_Has_Client && $Old_Has_Phone) {
self::pushProfileToServer($Old_Client_ID, $Full_Name, $Old_Phone);
}

if ($Old_Has_Phone) {
Repository::updateUserSession($Context->UserId, ['Flow' => null]);
TelegramClient::sendMessage($Context->ChatId, Helper::userGreeting($Context, 'پروفایل کاربری') . "✔️نام و نام خانوادگی وارد شده صحیح می باشد." . Helper::userFooter());
TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'پروفایل کاربری') . "✅ویرایش نام با موفقیت انجام گردید." . Helper::userFooter(), TelegramClient::inlineKeyboard([
[['text' => '👤پروفایل کاربری', 'callback_data' => 'پروفایل کاربری']],
Menu::userHome()
]));

return;
}

Repository::updateUserSession($Context->UserId, ['Flow' => self::FLOW_PHONE]);
TelegramClient::sendMessage($Context->ChatId, Helper::userGreeting($Context, 'پروفایل کاربری') . "✔️نام و نام خانوادگی وارد شده صحیح می باشد." . Helper::userFooter());
TelegramClient::sendMessage($Context->ChatId, Helper::userGreeting($Context, 'پروفایل کاربری') . "⁉️پرسش دوم:شماره موبایل معتبر خود را وارد کنید." . Helper::userFooter());
}

public static function processPhone(Context $Context, string $Text): void {
if (!Helper::validatePhone($Text)) {
TelegramClient::sendMessage($Context->ChatId, Helper::userGreeting($Context, 'پروفایل کاربری') . "❌خطا: شماره موبایل وارد شده صحیح نمی باشد.\n➖➖➖➖➖➖➖➖➖\n⚠️نکته:فرمت ارسالی باید یکی از اپراتور های (همراه اول،ایرانسل،رایتل) باشد." . Helper::userFooter());
TelegramClient::sendMessage($Context->ChatId, Helper::userGreeting($Context, 'پروفایل کاربری') . "❌شماره موبایل معتبر را دوباره وارد کنید." . Helper::userFooter());
return;
}

$Phone = Helper::normalizePhone($Text);
$Operator = Helper::detectOperator($Phone);

if ($Operator === 'نامعتبر' || !in_array($Operator, ['همراه اول', 'ایرانسل', 'رایتل'], true)) {
TelegramClient::sendMessage($Context->ChatId, Helper::userGreeting($Context, 'پروفایل کاربری') . "❌خطا: شماره موبایل وارد شده متعلق به اپراتور مورد تایید نمی باشد.\n➖➖➖➖➖➖➖➖➖\n⚠️نکته:تنها اپراتورهای مجاز (همراه اول، ایرانسل، رایتل) قابل ثبت می باشند." . Helper::userFooter());
TelegramClient::sendMessage($Context->ChatId, Helper::userGreeting($Context, 'پروفایل کاربری') . "❌شماره موبایل معتبر را دوباره وارد کنید." . Helper::userFooter());
return;
}

$Existing = Repository::findUserByPhone($Phone, $Context->UserId);

if (!empty($Existing)) {
$Existing_Name = (string)($Existing['Full_Name'] ?? 'کاربر دیگر');
TelegramClient::sendMessage($Context->ChatId, Helper::userGreeting($Context, 'پروفایل کاربری') . "⛔️این شماره موبایل قبلاً در سیستم ثبت شده است و مجاز به استفاده مجدد از آن نمی باشید.\n➖➖➖➖➖➖➖➖➖\n⚠️نکته:در صورتی که فکر می کنید اشتباهی رخ داده است به پشتیبانی مراجعه کنید." . Helper::userFooter());
TelegramClient::sendMessage($Context->ChatId, Helper::userGreeting($Context, 'پروفایل کاربری') . "❌لطفاً شماره موبایل دیگری وارد کنید." . Helper::userFooter());
return;
}

$Old_User = Repository::getUser($Context->UserId);
$Full_Name = trim((string)($Old_User['Full_Name'] ?? ''));
$Client_ID = trim((string)($Old_User['Client_ID'] ?? ''));
$Has_Client = $Client_ID !== '' && $Client_ID !== '_';
Repository::updateUser($Context->UserId, ['Phone' => $Phone, 'Operator' => $Operator]);
Repository::touchUserTime($Context->UserId, 'Profile_Updated_At');
Repository::updateUserSession($Context->UserId, ['Flow' => null]);

if ($Has_Client) {
self::pushProfileToServer($Client_ID, $Full_Name, $Phone);
}

TelegramClient::sendMessage($Context->ChatId, Helper::userGreeting($Context, 'پروفایل کاربری') . "✔️شماره موبایل صحیح و مربوط به اپراتور {$Operator} می باشد." . Helper::userFooter());
TelegramClient::sendMessage($Context->ChatId, Common::greet($Context, 'پروفایل کاربری') . "✅ویرایش و ثبت پروفایل با موفقیت انجام گردید." . Helper::userFooter(), TelegramClient::inlineKeyboard(array_merge(
Menu::rows([
[['👤پروفایل کاربری', 'پروفایل کاربری'], ['💎اشتراک من', 'اشتراک من']],
]),
[Menu::userHome()]
)));
}

private static function pushProfileToServer(string $Client_ID, string $Full_Name, string $Phone): void {
if ($Client_ID === '' || $Client_ID === '_') return;
if ($Full_Name === '' || $Phone === '') return;
$Response = ServerClient::updateUser($Client_ID, [
'name' => $Full_Name,
'comment' => $Phone,
]);

if (($Response['StatusCode'] ?? 0) >= 300) {
error_log('[Umbrella-Bot][Profile-Sync] Client_ID=' . $Client_ID . ' Status=' . ($Response['StatusCode'] ?? 0) . ' Body=' . mb_substr((string)($Response['Body'] ?? ''), 0, 200));
}
}
}
?>