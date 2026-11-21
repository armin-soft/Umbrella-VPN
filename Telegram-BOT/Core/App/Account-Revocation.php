<?php
declare(strict_types=1);
require_once __DIR__ . '/../Database/Database.php';

/** Revokes every trusted app session when its panel account is deleted. */
final class AppAccountRevocation {
    private function __construct() {}

    public static function revoke(string $UUID): bool {
        $UUID = trim($UUID);
        if ($UUID === '' || $UUID === '_') return false;

        try {
            Database::getInstance()->transaction(static function (Database $Db) use ($UUID): void {
                // Revoke tokens first; the trusted-device guard then makes the
                // desktop run its normal disconnect, sign-out and node cleanup.
                $Db->execute(
                    'UPDATE `App_Sessions` SET `Revoked_At` = CURRENT_TIMESTAMP WHERE `User_UUID` = ? AND `Revoked_At` IS NULL',
                    [$UUID]
                );
                // Clear pending one-time links and sign-ins before unlinking device rows.
                $Db->execute(
                    'DELETE FROM `App_Bot_Link_Requests` WHERE `User_UUID` = ? OR `Device_ID` IN (
                         SELECT `Device_ID` FROM `App_Devices` WHERE `User_UUID` = ?
                     ) OR `Device_ID` IN (
                         SELECT `Device_ID` FROM `App_Sessions` WHERE `User_UUID` = ?
                     )',
                    [$UUID, $UUID, $UUID]
                );
                $Db->execute(
                    'DELETE FROM `App_SignIn_Requests` WHERE `User_UUID` = ? OR `Device_ID` IN (
                         SELECT `Device_ID` FROM `App_Devices` WHERE `User_UUID` = ?
                     ) OR `Device_ID` IN (
                         SELECT `Device_ID` FROM `App_Sessions` WHERE `User_UUID` = ?
                     )',
                    [$UUID, $UUID, $UUID]
                );
                $Db->execute(
                    'DELETE FROM `App_Notifications` WHERE `User_UUID` = ? OR `Device_ID` IN (
                         SELECT `Device_ID` FROM `App_Devices` WHERE `User_UUID` = ?
                     ) OR `Device_ID` IN (
                         SELECT `Device_ID` FROM `App_Sessions` WHERE `User_UUID` = ?
                     )',
                    [$UUID, $UUID, $UUID]
                );
                $Db->execute(
                    'UPDATE `App_Devices` SET `Is_Trusted` = 0, `User_UUID` = NULL
                     WHERE `User_UUID` = ? OR `Device_ID` IN (
                         SELECT `Device_ID` FROM `App_Sessions` WHERE `User_UUID` = ?
                     )',
                    [$UUID, $UUID]
                );
                $Db->execute(
                    'DELETE FROM `App_Filter_Settings` WHERE `User_UUID` = ?',
                    [$UUID]
                );
            });
            return true;
        } catch (Throwable $Error) {
            error_log('[Umbrella-Bot][App-Account-Revocation] ' . $Error->getMessage());
            return false;
        }
    }
}
?>
