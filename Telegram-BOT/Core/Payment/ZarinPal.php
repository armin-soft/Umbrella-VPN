<?php
declare(strict_types=1);

require_once __DIR__ . '/../Support/Http.php';
require_once dirname(__DIR__, 2) . '/Config/Environment.php';

final class Zarinpal {
public const CODE_OK = 100;
public const CODE_ALREADY_VERIFIED = 101;
private const BASE_PRODUCTION = 'https://payment.zarinpal.com/pg/';
private const BASE_SANDBOX = 'https://sandbox.zarinpal.com/pg/';
private function __construct() {
}

private static function base(): string {
return Environment::isZarinpalSandbox() ? self::BASE_SANDBOX : self::BASE_PRODUCTION;
}

private static function requestUrl(): string {
return self::base() . 'v4/payment/request.json';
}

private static function verifyUrl(): string {
return self::base() . 'v4/payment/verify.json';
}

private static function gatewayUrl(): string {
return self::base() . 'StartPay/';
}

public static function startPayUrl(string $Authority): string {
return self::gatewayUrl() . $Authority;
}

public static function payLink(array $Payment): string {
$Bridge = (string)($Payment['BridgeUrl'] ?? '');
return $Bridge !== '' ? $Bridge : (string)($Payment['RedirectUrl'] ?? '');
}

public static function bridgeBaseUrl(): string {
$Base = Environment::getPaymentCallbackUrl();
$Parts = parse_url($Base);
if (!is_array($Parts) || (string)($Parts['host'] ?? '') === '') {
return '';
}

$Dir = rtrim(str_replace('\\', '/', dirname((string)($Parts['path'] ?? '/'))), '/');
$Scheme = (string)($Parts['scheme'] ?? 'https') . '://';
$Port = isset($Parts['port']) ? ':' . (int)$Parts['port'] : '';
return $Scheme . $Parts['host'] . $Port . $Dir . '/Pay.php';
}

public static function bridgeUrl(string $Authority, int $User_Id = 0): string {
$Base = self::bridgeBaseUrl();
$Authority = preg_replace('/[^A-Za-z0-9]/', '', $Authority) ?? '';
if ($Base === '' || $Authority === '') {
return '';
}

return $Base . '?a=' . $Authority . ($User_Id > 0 ? '&u=' . $User_Id : '');
}

public static function isConfigured(): bool {
return Environment::getZarinpalMerchantId() !== '';
}

public static function maskMerchant(string $Merchant_ID): string {
$Merchant_ID = trim($Merchant_ID);
return strlen($Merchant_ID) <= 8 ? $Merchant_ID : substr($Merchant_ID, 0, 4) . '***' . substr($Merchant_ID, -4);
}

public static function callbackHost(string $Call_Back_Url = ''): string {
$Url = trim($Call_Back_Url) !== '' ? trim($Call_Back_Url) : Environment::getPaymentCallbackUrl();
$Host = parse_url($Url, PHP_URL_HOST);
return is_string($Host) && $Host !== '' ? strtolower($Host) : 'unknown';
}

public static function calculateFee(float $Amount_Toman): array {
if ($Amount_Toman <= 0) {
return ['Ok' => false, 'Fee' => 0, 'Final' => $Amount_Toman, 'Fee_Type' => 'Merchant'];
}

$Percent_Fee = $Amount_Toman * 0.005;

if ($Percent_Fee > 16000.0) {
$Percent_Fee = 16000.0;
}

$Fee_Toman = $Percent_Fee + 500.0;
$Final_Toman = $Amount_Toman + $Fee_Toman;

return [
'Ok' => true,
'Fee' => $Fee_Toman,
'Final' => $Final_Toman,
'Fee_Type' => 'Payer',
];
}

public static function request(float $Amount_Toman, string $Call_Back_Url, string $Description, string $Phone_Number = ''): ?array {
$Final_Amount = $Amount_Toman;
$Fee = 0.0;
$Fee_Type = '';
$Calc = self::calculateFee($Amount_Toman);

if ($Calc['Ok'] && (float)$Calc['Final'] > $Amount_Toman) {
$Final_Amount = (float)$Calc['Final'];
$Fee = (float)$Calc['Fee'];
$Fee_Type = (string)$Calc['Fee_Type'];
}

$Payload = [
'merchant_id' => Environment::getZarinpalMerchantId(),
'amount' => (int)round($Final_Amount * 10),
'callback_url' => $Call_Back_Url,
'description' => $Description,
];

if ($Phone_Number !== '') {
$Payload['metadata'] = ['mobile' => $Phone_Number];
}

$Response = HttpClient::post(self::requestUrl(), $Payload, ['Content-Type' => 'application/json', 'Accept' => 'application/json']);

if (($Response['Json']['data']['authority'] ?? '') === '') {
error_log('[Umbrella-Bot][Zarinpal] PaymentRequest FAILED | Merchant=' . self::maskMerchant((string)Environment::getZarinpalMerchantId())
. ' | CallbackHost=' . self::callbackHost($Call_Back_Url)
. ' | Amount=' . (int)round($Final_Amount * 10)
. ' | HTTP=' . (int)($Response['StatusCode'] ?? 0)
. ' | Err=' . ($Response['Error'] !== '' ? $Response['Error'] : 'none')
. ' | Body=' . substr((string)($Response['Body'] ?? ''), 0, 400));
return null;
}

$Authority = (string)$Response['Json']['data']['authority'];
return [
'Authority' => $Authority,
'RedirectUrl' => self::startPayUrl($Authority),
'Amount' => $Final_Amount,
'Original_Amount' => $Amount_Toman,
'Fee' => $Fee,
'Fee_Type' => $Fee_Type, 'BridgeUrl' => self::bridgeUrl($Authority),
];
}

public static function verify(float $Amount_Toman, string $Authority): array {
$Final_Amount = $Amount_Toman;

for ($Attempt = 1; $Attempt <= 2; $Attempt++) {
$Response = HttpClient::post(self::verifyUrl(), [
'merchant_id' => Environment::getZarinpalMerchantId(),
'amount' => (int)round($Final_Amount * 10),
'authority' => $Authority,
], ['Content-Type' => 'application/json', 'Accept' => 'application/json']);

if (is_array($Response['Json'])) {
break;
}

error_log('[Umbrella-Bot][Zarinpal] Verify attempt ' . $Attempt . ' HTTP error: ' . ($Response['Error'] !== '' ? $Response['Error'] : 'invalid JSON - ' . $Response['Body']));

if ($Attempt === 2) {
return ['Ok' => false, 'Code' => -1, 'RefId' => '', 'CardPan' => ''];
}

sleep(1);
}

$Json = $Response['Json'];

if (isset($Json['errors']) && is_array($Json['errors']) && $Json['errors'] !== []) {
$API_Error = $Json['errors'];
error_log('[Umbrella-Bot][Zarinpal] Verify API error: ' . ($API_Error['message'] ?? 'unknown') . ' (code ' . ($API_Error['code'] ?? '?') . ')');
return ['Ok' => false, 'Code' => (int)($API_Error['code'] ?? -1), 'RefId' => '', 'CardPan' => ''];
}

$Data = $Json['data'] ?? [];

if (!is_array($Data)) {
error_log('[Umbrella-Bot][Zarinpal] Verify failed: unexpected data format - ' . $Response['Body']);
return ['Ok' => false, 'Code' => -1, 'RefId' => '', 'CardPan' => ''];
}

$Code = (int)($Data['code'] ?? 0);

return [
'Ok' => in_array($Code, [self::CODE_OK, self::CODE_ALREADY_VERIFIED], true),
'Code' => $Code,
'RefId' => (string)($Data['ref_id'] ?? ''),
'CardPan' => (string)($Data['card_pan'] ?? ''),
];
}
}
?>