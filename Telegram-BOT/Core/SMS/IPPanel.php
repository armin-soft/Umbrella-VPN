<?php
declare(strict_types=1);

require_once __DIR__ . '/../Support/Http.php';
require_once dirname(__DIR__, 2) . '/Config/Environment.php';
require_once __DIR__ . '/../Support/Helper.php';
require_once __DIR__ . '/../Storage/Repository.php';

final class IppanelClient {
private const SEND_URL = 'https://edge.ippanel.com/v1/api/send';
private const MIN_INTERVAL_SECONDS = 0.4;
private static float $Last_Send_At = 0.0;
private function __construct() {
}

private static function throttle(): void {
$Elapsed = microtime(true) - self::$Last_Send_At;
$Wait = self::MIN_INTERVAL_SECONDS - $Elapsed;

if (self::$Last_Send_At > 0.0 && $Wait > 0) {
usleep((int)round($Wait * 1000000));
}

self::$Last_Send_At = microtime(true);
}

/** Durable at-most-once attempt per business event, across workers and restarts.
 * An ambiguous timeout stays claimed: retrying could charge/send twice.
 * false means failed/unknown, including a previous failed attempt; never success.
 */
public static function sendOnce(int $User_ID, string $Phone, string $Message, string $Event): bool {
if ($User_ID <= 0 || trim($Event) === '' || !Helper::validatePhone($Phone)) return false;
// Configuration errors happen before any network attempt; allow correction.
if (trim(Environment::getSmsApiKey()) === '' || trim(Environment::getSmsSender()) === '') {
error_log('[Umbrella-Bot][SMS-Once] missing configuration');
return false;
}
$Key = 'SmsEvent_' . hash('sha256', $User_ID . ':' . $Event);
try {
$Db = Database::getInstance();
$Claimed = $Db->execute('INSERT IGNORE INTO `Settings` (`Key`, `Value`) VALUES (?, ?)', [$Key, 'attempted'])->rowCount() === 1;
if (!$Claimed) return Repository::getSetting($Key) === 'sent';
$Ok = self::send($User_ID, $Phone, $Message);
Repository::setSetting($Key, $Ok ? 'sent' : 'failed');
return $Ok;
} catch (Throwable $Error) {
// Never delete a claim after transport/logging/database failure.
error_log('[Umbrella-Bot][SMS-Once] ' . $Error->getMessage());
return false;
}
}

/** Same subscription identity for scheduled and manual expiration. */
public static function subscriptionEvent(string $Kind, array $User): string {
return $Kind . ':' . hash('sha256', json_encode([
(string)($User['Client_ID'] ?? ''), (int)($User['Expiration_Time_Stamp'] ?? 0),
], JSON_UNESCAPED_UNICODE));
}

public static function send(int $User_ID, string $Phone, string $Message): bool {
if (!Helper::validatePhone($Phone)) {
error_log('[Umbrella-Bot][Ippanel] شماره نامعتبر: ' . $Phone);
return false;
}

$Name = '';

if ($User_ID > 0) {
$User = \Repository::getUser($User_ID);
$Name = trim((string)($User['Full_Name'] ?? ''));

if ($Name === '') {
$Name = trim((string)($User['First_Name'] ?? ''));
}
}

if ($Name !== '' && !str_contains($Message, $Name)) {
$Message = "{$Name}\n" . ltrim($Message);
}

$Signature = 'سرور آمبرلا';
if (method_exists('Helper', 'repairMojibake')) {
$Message = Helper::repairMojibake($Message);
}
if (method_exists('Helper', 'stripZwnj')) {
$Message = Helper::stripZwnj($Message);
}
if (method_exists('Helper', 'digitsToPersian')) {
$Message = Helper::digitsToPersian($Message);
}
$Message = rtrim($Message);

if (!str_contains($Message, $Signature)) {
$Message = $Message . "\n\n" . $Signature;
}

$Api_Key = trim(Environment::getSmsApiKey());
$Sender_Raw = trim(Environment::getSmsSender());

if ($Api_Key === '') {
error_log('[Umbrella-Bot][Ippanel] کلید API تنظیم نشده است.');
\Repository::logSms($User_ID, $Phone, $Message, false);
return false;
}

if ($Sender_Raw === '') {
error_log('[Umbrella-Bot][Ippanel] شماره فرستنده تنظیم نشده است.');
\Repository::logSms($User_ID, $Phone, $Message, false);
return false;
}

$Sender = self::formatSender($Sender_Raw);
$Recipient = Helper::toE164($Phone);
$Payload = [
'sending_type' => 'webservice',
'from_number' => $Sender,
'message' => $Message,
'params' => [
'recipients' => [$Recipient],
],
];

$Url = trim(Environment::getSmsUrl());

if ($Url === '' || str_contains($Url, '/v1/') === false && str_contains($Url, '/api/send') === false) {
$Url = self::SEND_URL;
}

self::throttle();

$Result = HttpClient::post($Url, $Payload, [
'Content-Type' => 'application/json; charset=utf-8',
'Accept' => 'application/json',
'Authorization' => $Api_Key,
]);

$Status = (int)($Result['StatusCode'] ?? 0);
$Meta_Status = (bool)($Result['Json']['meta']['status'] ?? false);
$Meta_Message = (string)($Result['Json']['meta']['message'] ?? '');
$Meta_Code = (string)($Result['Json']['meta']['message_code'] ?? '');
$Body = (string)($Result['Body'] ?? '');
$Ok = $Status >= 200 && $Status < 300 && $Meta_Status;

if (!$Ok) {
error_log(sprintf(
'[Umbrella-Bot][Ippanel] ارسال ناموفق | User=%d Phone=%s Status=%d Meta=%s Code=%s Body=%s',
$User_ID, $Phone, $Status, $Meta_Message, $Meta_Code, mb_substr($Body, 0, 300)
));
}

\Repository::logSms($User_ID, $Phone, $Message, $Ok);
return $Ok;
}

/**
 * Sends an OTP through an approved IPPanel *pattern*.
 *
 * Pattern sends are the only IPPanel call meant for verification codes: the
 * text lives on IPPanel's side, only the code value crosses the wire, and the
 * recipient goes in `recipients` (one per request) instead of `params`.
 *
 * Approved pattern «کد تایید» (پترن اشتراکی): code `x7fhdaesmlj7vfi`, the text
 * is «سلام کد تایید شما %Code% می باشد. سرور آمبرلا - آرمین سافت» and its only
 * variable is `Code` (عدد) — the placeholder must keep the exact same
 * capitalisation here, or IPPanel answers with an «unknown parameter» error.
 * The code comes from the app as a 5-digit number.
 *
 * Returns true when IPPanel accepted the request.
 */
public static function sendPattern(string $Phone, string $Code, string $Pattern_Code = ''): bool {
if (!Helper::validatePhone($Phone)) {
error_log('[Umbrella-Bot][Ippanel-Pattern] شماره نامعتبر: ' . $Phone);
return false;
}

$Pattern_Code = trim($Pattern_Code !== '' ? $Pattern_Code : Environment::getOtpPatternCode());
$Api_Key = trim(Environment::getSmsApiKey());
$Explicit_Otp_Sender = method_exists('Environment', 'get') ? trim((string)Environment::get('IPPANEL_OTP_SENDER', '')) : '';
$Web_Sender_Raw = trim(Environment::getSmsSender());
$Sender_Raw = trim(method_exists('Environment', 'getOtpSender') ? Environment::getOtpSender() : $Web_Sender_Raw);

if ($Pattern_Code === '') {
error_log('[Umbrella-Bot][Ippanel-Pattern] کد الگو (IPPANEL_OTP_PATTERN) تنظیم نشده است.');
\Repository::logSms(0, $Phone, 'کد الگوی پیامک تایید تنظیم نشده است', false);
return false;
}

if ($Api_Key === '' || ($Sender_Raw === '' && $Web_Sender_Raw === '')) {
error_log('[Umbrella-Bot][Ippanel-Pattern] کلید API یا شماره فرستنده تنظیم نشده است.');
\Repository::logSms(0, $Phone, 'اطلاعات احراز هویت پنل پیامک تنظیم نشده است', false);
return false;
}

$Url = trim(Environment::getSmsUrl());

if ($Url === '' || (str_contains($Url, '/v1/') === false && str_contains($Url, '/api/send') === false)) {
$Url = self::SEND_URL;
}

$Recipient = Helper::toE164($Phone);
$From = self::formatSender($Sender_Raw !== '' ? $Sender_Raw : '+983000505');
$Attempt_Senders = [$From];
if ($Explicit_Otp_Sender === '' && $From !== '+983000505') {
$Attempt_Senders[] = '+983000505';
}

$Ok = false;
$Last_Status = 0;
foreach ($Attempt_Senders as $Candidate_Sender) {
$Payload = [
'sending_type' => 'pattern',
'from_number' => $Candidate_Sender,
'code' => $Pattern_Code,
'recipients' => [$Recipient],
'params' => [
// «کد تایید» پترن: متغیر %Code% از نوع عدد.
'Code' => $Code,
],
];

self::throttle();

$Result = HttpClient::post($Url, $Payload, [
'Content-Type' => 'application/json; charset=utf-8',
'Accept' => 'application/json',
'Authorization' => $Api_Key,
]);

$Last_Status = (int)($Result['StatusCode'] ?? 0);
$Meta_Status = (bool)($Result['Json']['meta']['status'] ?? false);
$Meta_Message = (string)($Result['Json']['meta']['message'] ?? '');
$Meta_Code = (string)($Result['Json']['meta']['message_code'] ?? '');
$Ok = $Last_Status >= 200 && $Last_Status < 300 && $Meta_Status;

if ($Ok) {
\Repository::logSms(0, $Phone, 'پیامک کد تایید ارسال شد', true);
return true;
}

// The code itself must never reach the log or the database.
error_log(sprintf(
'[Umbrella-Bot][Ippanel-Pattern] ارسال ناموفق | Phone=%s Pattern=%s From=%s Status=%d Meta=%s Code=%s Body=%s',
$Phone, $Pattern_Code, $Candidate_Sender, $Last_Status, $Meta_Message, $Meta_Code, mb_substr((string)($Result['Body'] ?? ''), 0, 300)
));

if (!in_array($Last_Status, [400, 422], true)) {
break;
}
}

// If IPPanel rejected pattern parameters/sender with 4xx, try plain webservice delivery
// using the configured sender so login is not deadlocked (still never logging the OTP code).
if (in_array($Last_Status, [400, 404, 422], true) && $Web_Sender_Raw !== '') {
$Fallback_Payload = [
'sending_type' => 'webservice',
'from_number' => self::formatSender($Web_Sender_Raw),
'message' => "سلام کد تایید شما {$Code} می باشد.\nسرور آمبرلا - آرمین سافت",
'params' => [
'recipients' => [$Recipient],
],
];

self::throttle();

$Fallback_Result = HttpClient::post($Url, $Fallback_Payload, [
'Content-Type' => 'application/json; charset=utf-8',
'Accept' => 'application/json',
'Authorization' => $Api_Key,
]);

$Fb_Status = (int)($Fallback_Result['StatusCode'] ?? 0);
$Fb_Meta_Status = (bool)($Fallback_Result['Json']['meta']['status'] ?? false);
$Fb_Meta_Msg = (string)($Fallback_Result['Json']['meta']['message'] ?? '');
$Fb_Meta_Code = (string)($Fallback_Result['Json']['meta']['message_code'] ?? '');
$Fb_Ok = $Fb_Status >= 200 && $Fb_Status < 300 && $Fb_Meta_Status;

if ($Fb_Ok) {
\Repository::logSms(0, $Phone, 'پیامک کد تایید با وب سرویس جایگزین ارسال شد', true);
return true;
}

error_log(sprintf(
'[Umbrella-Bot][Ippanel-OtpFallback] ارسال ناموفق | Phone=%s From=%s Status=%d Meta=%s Code=%s Body=%s',
$Phone, self::formatSender($Web_Sender_Raw), $Fb_Status, $Fb_Meta_Msg, $Fb_Meta_Code, mb_substr((string)($Fallback_Result['Body'] ?? ''), 0, 300)
));
}

\Repository::logSms(0, $Phone, 'ارسال پیامک کد تایید رد شد', false);
return false;
}

private static function formatSender(string $Sender): string {
$Sender = trim($Sender);

if ($Sender === '') return '';
if (str_starts_with($Sender, '+')) return $Sender;
$Normalized = preg_replace('/[\s\-]/', '', $Sender);

if (!ctype_digit($Normalized)) return $Sender;
$Length = strlen($Normalized);

if ($Length >= 4 && $Length <= 5) {
return $Normalized;
}

if ($Length >= 6 && $Length <= 9) {
return '+98' . ltrim($Normalized, '0');
}

if (str_starts_with($Normalized, '0098')) {
return '+' . substr($Normalized, 2);
}

if (str_starts_with($Normalized, '98')) {
return '+' . $Normalized;
}

if (str_starts_with($Normalized, '0') && $Length === 11) {
return '+98' . substr($Normalized, 1);
}

if ($Length === 10) {
return '+98' . $Normalized;
}

return $Sender;
}
}
?>