<?php
declare(strict_types=1);

require_once __DIR__ . '/../Storage/Repository.php';
require_once __DIR__ . '/../Server/Umbrella-Server.php';
require_once __DIR__ . '/../Support/Helper.php';
require_once __DIR__ . '/../Support/Bot-Config.php';
require_once __DIR__ . '/../Telegram/Telegram.php';
require_once dirname(__DIR__, 2) . '/Bot/Common.php';
require_once __DIR__ . '/../../Config/Environment.php';

final class AutoRenew {
private const PLAN_GB = 1000;
private const PLANS = [
'1' => ['۱ ماهه', 30],
'2' => ['۲ ماهه', 60],
'3' => ['۳ ماهه', 90],
'6' => ['۶ ماهه', 180],
'12' => ['۱ ساله', 360],
];

public static function planName(string $Plan_Key): string {
return self::PLANS[$Plan_Key][0] ?? '';
}


public static function processDue(int $Days_Before = 3): int {
$Threshold = time() + ($Days_Before * 86400);
$Rows = Database::getInstance()->fetchAll(
"SELECT `Telegram_ID`, `Auto_Renew_Plan`, `Balance`
FROM `Users`
WHERE `Auto_Renew_Plan` IS NOT NULL
AND `Auto_Renew_Plan` != ''
AND `Expiration_Time_Stamp` IS NOT NULL
AND `Expiration_Time_Stamp` <= ?
AND `Expiration_Time_Stamp` > ?
AND `Is_Blocked` = 0",
[$Threshold, time()]
);

$Count = 0;

foreach ($Rows as $Row) {
$User_ID = (int)($Row['Telegram_ID'] ?? 0);
$Plan = (string)($Row['Auto_Renew_Plan'] ?? '');
$Balance = (float)($Row['Balance'] ?? 0);

if ($User_ID <= 0 || $Plan === '' || !isset(self::PLANS[$Plan])) continue;
[$Plan_Name, $Days] = self::PLANS[$Plan];
$Price = BotConfig::getPlanPrice($Plan);
$Final_Price = $Price;

if ($Final_Price <= 0) {
error_log('[Umbrella-Bot][AutoRenew] Plan price is not configured for key ' . $Plan);

try {
TelegramClient::sendMessage(
Environment::getAdminUserId(),
Helper::adminGreetingNamed('', 'تمدید خودکار')
. "⚠️*تمدید خودکار انجام نشد.*\n"
. "├─📦پلن: {$Plan_Name}\n"
. "├─🔑کلید تنظیمات: تعرفه اشتراک در پنل\n"
. "└─ℹ️قیمت این پلن در پنل مدیریت (⚙️تنظیمات ربات ← 💰تعرفه اشتراک) ثبت نشده است."
. Helper::adminFooter()
);
}

catch (Throwable) {}
continue;
}

if ($Balance < $Final_Price) {
$User_Now = Repository::getUser($User_ID);
TelegramClient::sendMessage(
(int)($User_Now['Chat_ID'] ?? 0),
Helper::frame('کاربر', (string)($User_Now['Full_Name'] ?? ''), 'تمدید خودکار', $User_ID)
. "⚠️*تمدید خودکار ناموفق بود.*\n"
. "├─📦پلن: {$Plan_Name}\n"
. "├─💰مبلغ لازم: " . Helper::formatCurrency($Final_Price) . "\n"
. "└─💵موجودی کیف پول: " . Helper::formatCurrency($Balance) . "\n"
. "⚠️لطفاً کیف پول خود را شارژ کنید تا تمدید خودکار انجام شود."
. Helper::userFooter()
);
continue;
}

if (!Repository::removeMoney($User_ID, $Final_Price, 'تمدید خودکار اشتراک', 'bot')) continue;

if ($Days <= 0) { Repository::addMoney($User_ID, $Final_Price, 'بازگشت وجه تمدید خودکار', 'bot'); continue; }
$User = Repository::getUser($User_ID);
$Client_ID = (string)($User['Client_ID'] ?? '');

if ($Client_ID === '' || $Client_ID === '_') { Repository::addMoney($User_ID, $Final_Price, 'بازگشت وجه تمدید خودکار', 'bot'); continue; }
$Tehran = new DateTimeZone('Asia/Tehran');
$Now = new DateTimeImmutable('now', $Tehran);
$New_Expire = $Now->modify('+' . $Days . ' days');
$Today = $Now->format('Y-m-d');

$Payload = [
'start_date' => $Today,
'package_days' => $Days,
'usage_limit_GB' => self::PLAN_GB,
'is_active' => true,
'enable' => true,
'last_reset_time' => $Today,
];

$Response = ServerClient::updateUser($Client_ID, $Payload);

if (($Response['StatusCode'] ?? 0) < 300) {
Repository::updateUser($User_ID, [
'Expiration_Time_Stamp' => $New_Expire->getTimestamp(),
'Expiration_Date' => Helper::formatExpiration($New_Expire->getTimestamp()),
'Package_Duration' => Helper::durationLabel($Days),
'Package_Start_Date' => Helper::formatPersianDate($Now->getTimestamp()),
'Subscription' => $Plan_Name,
'Total_Usage_GB' => (float)self::PLAN_GB,
'Used_Usage_GB' => 0.0,
'Remaining_Usage_GB' => (float)self::PLAN_GB,
'Percent_Usage' => 0.0,
'Client_Status' => 'فعال',
]);

$User_Now = Repository::getUser($User_ID);
$Full_Name = (string)($User_Now['Full_Name'] ?? '');

TelegramClient::sendMessage(
(int)($User_Now['Chat_ID'] ?? 0),
Helper::frame('کاربر', $Full_Name, 'تمدید خودکار', $User_ID)
. "✨*تمدید خودکار اشتراک با موفقیت انجام شد.*\n"
. "├─📦پلن: {$Plan_Name}\n"
. "├─📊حجم پلن: " . Helper::formatGB((float)self::PLAN_GB) . "\n"
. "├─💰مبلغ کسرشده: " . Helper::formatCurrency($Final_Price) . "\n"
. "├─💵موجودی کیف پول: " . Helper::formatCurrency((float)(Repository::getBalance($User_ID))) . "\n"
. "└─📅تاریخ انقضای جدید: " . Helper::formatExpirationShort($New_Expire->getTimestamp())
. Helper::userFooter(),
TelegramClient::inlineKeyboard([Common::mainButton()])
);

try {
$Admin_User = Repository::getUser(Environment::getAdminUserId());
$Admin_Name = trim((string)($Admin_User['Full_Name'] ?? '')) ?: (trim((string)($Admin_User['First_Name'] ?? '')) ?: 'مدیر');
$Admin_Text = Helper::adminGreetingNamed($Admin_Name, 'تمدید خودکار', Environment::getAdminUserId())
. "💰✅تمدید خودکار انجام شد.\n"
. "├─👤کاربر: " . Helper::mention($Full_Name, $User_ID) . "\n"
. "├─🆔آیدی: `" . Helper::toPersian((string)$User_ID) . "`\n"
. "├─📦پلن: {$Plan_Name}\n"
. "├─📊حجم پلن: " . Helper::formatGB((float)self::PLAN_GB) . "\n"
. "├─💰مبلغ کسرشده: " . Helper::formatCurrency($Final_Price) . "\n"
. "└─📅انقضای جدید: " . Helper::formatExpirationShort($New_Expire->getTimestamp())
. Helper::adminFooter();

TelegramClient::sendMessage(Environment::getAdminUserId(), $Admin_Text, TelegramClient::inlineKeyboard([
[['text' => '👁👤مشاهده کاربر', 'url' => 'tg://user?id=' . $User_ID]],
]));
}

catch (Throwable) {}

$Count++;
}

else {
Repository::addMoney($User_ID, $Final_Price, 'بازگشت وجه تمدید خودکار', 'bot');
}
}

return $Count;
}
}
?>