<?php
declare(strict_types=1);

require_once __DIR__ . '/../Storage/Repository.php';
require_once __DIR__ . '/../Server/Umbrella-Server.php';
require_once __DIR__ . '/../Support/Helper.php';
require_once __DIR__ . '/../Telegram/Telegram.php';
require_once __DIR__ . '/../../Config/Environment.php';

final class AutoRenew {
private const PLANS = [
'1' => ['۱ ماهه', 30],
'2' => ['۲ ماهه', 60],
'3' => ['۳ ماهه', 90],
'6' => ['۶ ماهه', 180],
'12' => ['۱۲ ماهه', 360],
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
$Price = Environment::getPlanPrice($Plan);
$Final_Price = $Price;

if ($Final_Price <= 0) {
error_log('[Umbrella-Bot][AutoRenew] Plan price is not configured for key ' . $Plan);

try {
TelegramClient::sendMessage(
Environment::getAdminUserId(),
'⚠️تمدید خودکار انجام نشد: قیمت پلن «' . $Plan_Name . '» در تنظیمات (PLAN_PRICE_' . $Plan . ') ثبت نشده است.'
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

if (!Repository::removeMoney($User_ID, $Final_Price)) continue;

if ($Days <= 0) { Repository::addMoney($User_ID, $Final_Price); continue; }
$User = Repository::getUser($User_ID);
$Client_ID = (string)($User['Client_ID'] ?? '');

if ($Client_ID === '' || $Client_ID === '_') { Repository::addMoney($User_ID, $Final_Price); continue; }
$Tehran = new DateTimeZone('Asia/Tehran');
$Now = new DateTimeImmutable('now', $Tehran);
$New_Expire = $Now->modify('+' . $Days . ' days');
$Today = $Now->format('Y-m-d');

$Payload = [
'start_date' => $Today,
'package_days' => $Days,
'usage_limit_GB' => 1000,
'is_active' => true,
'enable' => true,
'last_reset_time' => $Today,
];

$Response = ServerClient::updateUser($Client_ID, $Payload);

if (($Response['StatusCode'] ?? 0) < 300) {
Repository::updateUser($User_ID, [
'Expiration_Time_Stamp' => $New_Expire->getTimestamp(),
'Expiration_Date' => Helper::formatExpiration($New_Expire->getTimestamp()),
'Package_Duration' => (string)$Days,
'Subscription' => $Plan_Name,
]);

$User_Now = Repository::getUser($User_ID);
$Full_Name = (string)($User_Now['Full_Name'] ?? '');

TelegramClient::sendMessage(
(int)($User_Now['Chat_ID'] ?? 0),
Helper::frame('کاربر', $Full_Name, 'تمدید خودکار', $User_ID)
. "✨*تمدید خودکار اشتراک با موفقیت انجام شد.*\n"
. "├─📦پلن: {$Plan_Name}\n"
. "├─💰مبلغ کسرشده: " . Helper::formatCurrency($Final_Price) . "\n"
. "└─📅تاریخ انقضای جدید: " . Helper::formatExpiration($New_Expire->getTimestamp())
. Helper::userFooter()
);

try {
$Admin_Name = trim((string)(Repository::getUser(Environment::getAdminUserId())['Full_Name'] ?? ''));

TelegramClient::sendMessage(
Environment::getAdminUserId(),
'💰تمدید خودکار انجام شد: '
. ($Admin_Name !== '' ? '[' . str_replace(['[', ']'], '', $Full_Name) . '](tg://user?id=' . $User_ID . ') ' : $Full_Name . ' ')
. '(' . Helper::toPersian((string)$User_ID) . ') | پلن ' . $Plan_Name
. ' | مبلغ ' . Helper::formatCurrency($Final_Price)
);
}

catch (Throwable) {}

$Count++;
}

else {
Repository::addMoney($User_ID, $Final_Price);
}
}

return $Count;
}
}
?>