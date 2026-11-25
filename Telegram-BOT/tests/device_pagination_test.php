<?php
declare(strict_types=1);

$Root = dirname(__DIR__);
$AppLink = (string)file_get_contents($Root . '/Bot/App-Link.php');
$Admin = (string)file_get_contents($Root . '/Bot/Admin.php');
$User = (string)file_get_contents($Root . '/Bot/User.php');
$Dispatcher = (string)file_get_contents($Root . '/Bot/Dispatcher.php');

$Checks = [
    'device rows are counted and loaded by a bounded page and offset' =>
        str_contains($AppLink, 'SELECT COUNT(*) FROM `App_Devices` WHERE `Is_Trusted` = 1') &&
        str_contains($AppLink, '$PageSize = 5;') &&
        str_contains($AppLink, 'LIMIT ? OFFSET ?'),
    'revoked status callbacks remove untrusted rows instead of leaving them in the list' =>
        str_contains($Dispatcher, "str_starts_with(\$Data, 'app_device_status:')") &&
        str_contains($Dispatcher, 'AppFlow::removeRevokedDevice($Context, $Prefix, (int)$Page)'),
    'previous and next page callbacks are rendered only for multiple pages' =>
        str_contains($AppLink, "'app_devices_page:' . (\$Page - 1)") &&
        str_contains($AppLink, "'app_devices_page:' . (\$Page + 1)") &&
        str_contains($AppLink, '$PageCount > 1'),
    'the dispatcher routes pagination callbacks back to the requested page' =>
        str_contains($Dispatcher, "str_starts_with(\$Data, 'app_devices_page:')") &&
        str_contains($Dispatcher, "AppFlow::devices(\$Context, (int)substr(\$Data, strlen('app_devices_page:')))") ,
    'revocation confirmation preserves the current page' =>
        str_contains($AppLink, "'app_device_revoke_confirm:' . \$Prefix . ':' . \$Page") &&
        str_contains($AppLink, 'self::devices($Context, $Page);'),
    'admin device section lists all devices with pagination and owner details' =>
        str_contains($Admin, 'public static function appDevicesMenu(Context $Context, int $Page = 0)') &&
        str_contains($Admin, "SELECT COUNT(*) FROM `App_Devices`") &&
        str_contains($Admin, 'LIMIT ? OFFSET ?') &&
        str_contains($Admin, '`Owner_Telegram_ID`'),
    'admin can grant or revoke a device permission and invalidate sessions on revoke' =>
        str_contains($Admin, 'public static function toggleAppDevice') &&
        str_contains($Admin, "'UPDATE `App_Devices` SET `Is_Trusted` = 1") &&
        str_contains($Admin, "'UPDATE `App_Devices` SET `Is_Trusted` = 0") &&
        str_contains($Admin, "'UPDATE `App_Sessions` SET `Revoked_At` = CURRENT_TIMESTAMP"),
    'admin device controls and grouped user app actions remain reachable' =>
        str_contains($Dispatcher, "'admin_devices' => AdminFlow::appDevicesMenu(\$Context)") &&
        str_contains($Dispatcher, "str_starts_with(\$Data, 'admin_device_toggle:')") &&
        str_contains($User, "'📱دستگاه های من', 'app_devices'") &&
        str_contains($User, "'🛡کنترل محتوا', 'app_filter'") &&
        !str_contains($User, "'app_filter_domains'") &&
        str_contains($User, "'🔐تأیید دومرحله ای', 'app_2fa'") &&
        !str_contains($User, "'🔔اعلان های برنامه', 'app_notifications'") &&
        !str_contains($User, "'📱حساب و تنظیمات برنامه'") &&
        str_contains($Admin, "'📲دستگاه های برنامه', 'admin_devices'"),
    'app screens return to the device category' =>
        !str_contains($AppLink, "'user_security_menu'") &&
        str_contains($AppLink, "Menu::back('منوی قبلی', 'user_device_menu')") &&
        !str_contains($AppLink, "Menu::back('حساب آمبرلا', 'app_menu')") &&
        !str_contains($AppLink, "Menu::back('کنترل محتوا', 'app_filter')"),
    'direct ticket actions and ticket-description step have proper back and main routes' =>
        str_contains($User, "'➕ایجاد تیکت جدید', 'تیکت جدید'") &&
        str_contains($User, "'🎫تیکت های من', 'لیست تیکت های من'") &&
        !str_contains($User, "'🎫تیکت ها و پشتیبانی', 'منوی پشتیبانی'") &&
        str_contains($User, "Menu::back('ویرایش توضیحات', 'ویرایش توضیحات تیکت')") &&
        str_contains($Dispatcher, "'ویرایش توضیحات تیکت' => UserFlow::ticketDescriptionStart(\$Context)")
];

$Failed = false;
foreach ($Checks as $Name => $Passed) {
    echo ($Passed ? 'PASS' : 'FAIL') . " — {$Name}\n";
    $Failed = $Failed || !$Passed;
}

exit($Failed ? 1 : 0);
