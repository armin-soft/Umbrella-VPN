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
'Content-Type' => 'application/json',
'Accept' => 'application/json',
'Authorization' => $Api_Key,
]);

$Status = (int)($Result['StatusCode'] ?? 0);
$Meta_Status = (bool)($Result['Json']['meta']['status'] ?? false);
$Meta_Message = (string)($Result['Json']['meta']['message'] ?? '');
$Meta_Code = (string)($Result['Json']['meta']['message_code'] ?? '');
$Body = (string)($Result['Body'] ?? '');
$Ok = $Status >= 200 && $Status < 300 && $Meta_Status;

if (!$Ok && ($Status === 429 || $Meta_Code === '400-1' || str_contains($Meta_Message, 'تکراری'))) {
\Repository::logSms($User_ID, $Phone, $Message, true);
return true;
}

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
$Sender_Raw = trim(Environment::getSmsSender());

if ($Pattern_Code === '') {
error_log('[Umbrella-Bot][Ippanel-Pattern] کد الگو (IPPANEL_OTP_PATTERN) تنظیم نشده است.');
\Repository::logSms(0, $Phone, 'OTP pattern missing pattern code', false);
return false;
}

if ($Api_Key === '' || $Sender_Raw === '') {
error_log('[Umbrella-Bot][Ippanel-Pattern] کلید API یا شماره فرستنده تنظیم نشده است.');
\Repository::logSms(0, $Phone, 'OTP pattern missing credentials', false);
return false;
}

$Payload = [
'sending_type' => 'pattern',
'from_number' => self::formatSender($Sender_Raw),
'code' => $Pattern_Code,
'recipients' => [Helper::toE164($Phone)],
'params' => [
// «کد تایید» پترن: متغیر %Code% از نوع عدد.
'Code' => $Code,
],
];

$Url = trim(Environment::getSmsUrl());

if ($Url === '' || str_contains($Url, '/v1/') === false && str_contains($Url, '/api/send') === false) {
$Url = self::SEND_URL;
}

self::throttle();

$Result = HttpClient::post($Url, $Payload, [
'Content-Type' => 'application/json',
'Accept' => 'application/json',
'Authorization' => $Api_Key,
]);

$Status = (int)($Result['StatusCode'] ?? 0);
$Meta_Status = (bool)($Result['Json']['meta']['status'] ?? false);
$Meta_Message = (string)($Result['Json']['meta']['message'] ?? '');
$Ok = $Status >= 200 && $Status < 300 && $Meta_Status;

// The code itself must never reach the log or the database.
if (!$Ok) {
error_log(sprintf(
'[Umbrella-Bot][Ippanel-Pattern] ارسال ناموفق | Phone=%s Status=%d Meta=%s Body=%s',
$Phone, $Status, $Meta_Message, mb_substr((string)($Result['Body'] ?? ''), 0, 300)
));
}

\Repository::logSms(0, $Phone, 'OTP pattern ' . ($Ok ? 'accepted' : 'rejected'), $Ok);
return $Ok;
}

private static function formatSender(string $Sender): string {
$Sender = trim($Sender);

if ($Sender === '') return '';
if (str_starts_with($Sender, '+')) return $Sender;
$Normalized = preg_replace('/[\s\-]/', '', $Sender);

if (!ctype_digit($Normalized)) return $Sender;
$Length = strlen($Normalized);

if ($Length >= 4 && $Length <= 8) {
return $Normalized;
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