<?php
declare(strict_types=1);

require_once __DIR__ . '/../Support/Http.php';
require_once dirname(__DIR__, 2) . '/Config/Environment.php';

final class Zarinpal {
public const CODE_OK = 100;
public const CODE_ALREADY_VERIFIED = 101;
public const CODE_NOT_PAID = -51;
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
if ($Base === '' || !self::validAuthority($Authority)) {
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

// Official v4 error list: https://www.zarinpal.com/docs/paymentGateway/errorList.html
public static function errorMessage(int $Code): string {
return match ($Code) {
-9 => 'خطای اعتبارسنجی پارامترها: مرچنت، آدرس بازگشت، توضیحات، مبلغ یا کد معرف را بررسی کنید.',
-10 => 'آی پی یا مرچنت کد پذیرنده صحیح نیست.',
-11 => 'درگاه پذیرنده فعال نیست؛ با پشتیبانی زرین پال تماس بگیرید.',
-12 => 'تعداد تلاش ها از حد مجاز بیشتر شده است؛ کمی بعد دوباره تلاش کنید.',
-13 => 'محدودیت تراکنش پذیرنده؛ تکمیل مدارک و پیگیری از پشتیبانی لازم است.',
-14 => 'دامنه آدرس بازگشت با دامنه ثبت شده درگاه مطابقت ندارد.',
-15 => 'درگاه پذیرنده به حالت تعلیق درآمده است.',
-16 => 'سطح تایید پذیرنده پایین تر از سطح نقره ای است.',
-17 => 'محدودیت پذیرنده در سطح آبی.',
-18 => 'نشانی ارجاع با دامنه ثبت شده درگاه مطابقت ندارد.',
-19 => 'ایجاد تراکنش برای این درگاه ممنوع شده است.',
-40 => 'پارامتر اضافی زمان انقضا نامعتبر است.',
-41 => 'حداکثر مبلغ پرداختی طبق مستندات درگاه ۱۰۰ میلیون تومان است.',
-50 => 'مبلغ تایید با مبلغ سفارش درگاه مطابقت ندارد؛ با پشتیبانی تماس بگیرید.',
-51 => 'پرداخت ناموفق است؛ تلاش پرداخت موفقی برای این سفارش ثبت نشده است.',
-52 => 'خطای غیرمنتظره درگاه؛ با پشتیبانی زرین پال تماس بگیرید.',
-53 => 'پرداخت متعلق به این مرچنت کد نیست.',
-54 => 'شناسه مرجع پرداخت نامعتبر است.',
-55 => 'تراکنش مورد نظر یافت نشد.',
-60 => 'امکان برگشت تراکنش از طریق بانک وجود ندارد.',
-61 => 'تراکنش موفق نیست یا قبلا برگشت داده شده است.',
-62 => 'محدودیت آی پی درگاه برای برگشت تراکنش باید فعال باشد.',
-63 => 'مهلت ۳۰ دقیقه ای برگشت تراکنش پایان یافته است.',
100 => 'عملیات موفق بود.',
101 => 'تراکنش قبلا تایید شده است؛ ثبت محلی آن باید بررسی شود.',
-1000 => 'ارتباط با درگاه برقرار نشد یا پاسخ سرور درگاه ناموفق بود؛ نتیجه پرداخت هنوز مشخص نیست.',
-1001 => 'پاسخ درگاه ناقص یا نامعتبر است؛ نتیجه پرداخت هنوز مشخص نیست.',
-1003 => 'برای دریافت کارمزد فقط در ربات، پرداخت کننده کارمزد در پنل زرین پال باید پذیرنده باشد؛ لینک پرداخت ساخته یا ارائه نشد.',
-1004 => 'مبلغ یا کارمزد پاسخ درگاه با محاسبه سفارش مطابقت ندارد؛ برای جلوگیری از دریافت مبلغ اشتباه، لینک پرداخت ارائه نشد.',
-1002 => 'پارامترهای محلی پرداخت نامعتبر است؛ تنظیمات و مبلغ را بررسی کنید.',
default => 'کد اعلام شده درگاه در فهرست مستندات شناخته نشده است (کد ' . (method_exists('Helper', 'toPersian') ? Helper::toPersian((string)$Code) : (string)$Code) . ')؛ با پشتیبانی پیگیری کنید.',
};
}

private static ?array $RequestError = null;
public static function lastRequestError(): ?array { return self::$RequestError; }
public static function requestErrorMessage(): string {
$Error = self::$RequestError;
if ($Error === null) return 'ساخت درخواست پرداخت انجام نشد؛ با پشتیبانی پیگیری کنید.';
$CodeLabel = method_exists('Helper', 'toPersian') ? Helper::toPersian((string)$Error['Code']) : (string)$Error['Code'];
return $Error['Message'] . ' (کد ' . $CodeLabel . ')';
}

private static function rial(float $Toman): ?int {
if (!is_finite($Toman) || $Toman <= 0 || $Toman > 100000000) return null;
$Rial = (int)round($Toman * 10);
return $Rial > 0 ? $Rial : null;
}

public static function validAuthority(string $Authority): bool {
// Do not silently strip or rewrite an authority supplied by the provider.
return preg_match('/^[AS][A-Za-z0-9]{35}$/D', $Authority) === 1;
}

private static function integer(mixed $Value): ?int {
if (is_int($Value)) return $Value;
if (is_string($Value) && preg_match('/^-?[0-9]{1,10}$/D', $Value)) return (int)$Value;
return null;
}

private static function failure(int $Code, string $Kind, string $Operation, int $Http = 0, ?int $ProviderCode = null): array {
// Never log raw response bodies, card information, merchant IDs or callback queries.
if ($Code !== self::CODE_NOT_PAID || $Kind !== 'api') {
error_log('[Umbrella-Bot][Zarinpal] ' . $Operation . ' failed | kind=' . $Kind . ' | code ' . $Code . ' | HTTP=' . $Http . ($ProviderCode !== null ? ' | provider code ' . $ProviderCode : ''));
}
return ['Ok' => false, 'Code' => $Code, 'Kind' => $Kind, 'Message' => self::errorMessage($Code), 'HttpStatus' => $Http, 'ProviderCode' => $ProviderCode, 'RefId' => '', 'CardPan' => ''];
}

private static function parse(array $Response, string $Operation): array {
$Http = (int)($Response['StatusCode'] ?? 0);
$Json = $Response['Json'] ?? null;
$Errors = is_array($Json) ? ($Json['errors'] ?? []) : [];
$ProviderCode = is_array($Errors) ? self::integer($Errors['code'] ?? null) : null;
if (($Response['Error'] ?? '') !== '' || $Http < 200 || $Http >= 500 || ($Http >= 300 && $Http < 400) || $Http === 429) {
return self::failure(-1000, 'transport', $Operation, $Http, $ProviderCode);
}
if (!is_array($Json) || !is_array($Errors)) return self::failure(-1001, 'protocol', $Operation, $Http);
if ($Errors !== []) {
return $ProviderCode !== null && $ProviderCode < 0
? self::failure($ProviderCode, 'api', $Operation, $Http, $ProviderCode)
: self::failure(-1001, 'protocol', $Operation, $Http, $ProviderCode);
}
if ($Http >= 300) return self::failure(-1000, 'transport', $Operation, $Http);
$Data = $Json['data'] ?? null;
if (!is_array($Data)) return self::failure(-1001, 'protocol', $Operation, $Http);
$Code = self::integer($Data['code'] ?? null);
if ($Code !== null && $Code < 0) return self::failure($Code, 'api', $Operation, $Http, $Code);
$Allowed = $Operation === 'verify' ? [100, 101] : [100];
if (!in_array($Code, $Allowed, true)) return self::failure(-1001, 'protocol', $Operation, $Http, $Code);
if ($Operation === 'request') {
if (!is_string($Data['authority'] ?? null) || !self::validAuthority($Data['authority'])) return self::failure(-1001, 'protocol', $Operation, $Http, $Code);
$Prefix = Environment::isZarinpalSandbox() ? 'S' : 'A';
if ($Data['authority'][0] !== $Prefix) return self::failure(-1001, 'protocol', $Operation, $Http, $Code);
} elseif ($Operation === 'verify') {
$Ref = $Data['ref_id'] ?? null;
if (!(is_int($Ref) || is_string($Ref)) || !preg_match('/^[1-9][0-9]*$/D', (string)$Ref)
|| (isset($Data['card_pan']) && !is_string($Data['card_pan']))) return self::failure(-1001, 'protocol', $Operation, $Http, $Code);
}
return ['Ok' => true, 'Code' => $Code, 'Data' => $Data, 'RefId' => (string)($Data['ref_id'] ?? ''), 'CardPan' => (string)($Data['card_pan'] ?? '')];
}

/** Quote the gross amount that leaves the requested net amount after the merchant fee. */
public static function calculateFee(float $Amount_Toman): array {
$Rial = self::rial($Amount_Toman);
if ($Rial === null || $Rial < 1000 || !self::isConfigured()) return self::failure(-1002, 'validation', 'feeCalculation');
try {
$Response = HttpClient::post(self::base() . 'v4/payment/feeCalculation.json', [
'merchant_id' => Environment::getZarinpalMerchantId(), 'amount' => $Rial, 'currency' => 'IRR',
], ['Content-Type' => 'application/json; charset=utf-8', 'Accept' => 'application/json']);
} catch (Throwable) { return self::failure(-1000, 'transport', 'feeCalculation'); }
$Result = self::parse($Response, 'feeCalculation');
if (!$Result['Ok']) return $Result;
$Data = $Result['Data'];
if (($Data['fee_type'] ?? '') !== 'Merchant') return self::failure(-1003, 'configuration', 'feeCalculation');
$Original = self::integer($Data['amount'] ?? null);
$Fee = self::integer($Data['fee'] ?? null);
$Suggested = self::integer($Data['suggested_amount'] ?? null);
if ($Original !== $Rial || $Fee === null || $Fee < 0 || $Suggested === null
|| $Suggested < $Rial || $Suggested > 1000000000 || $Fee > $Suggested - $Rial) return self::failure(-1004, 'protocol', 'feeCalculation');
// suggested_amount includes the effect of charging fees on the gross amount itself.
// The buyer surcharge is NOT simply the quoted fee on the original net amount.
return ['Ok' => true, 'Original_Rial' => $Rial, 'Final_Rial' => $Suggested,
'Original_Amount' => $Rial / 10, 'Final' => $Suggested / 10, 'Fee' => ($Suggested - $Rial) / 10,
'Fee_Type' => 'Merchant'];
}

public static function request(float $Amount_Toman, string $Call_Back_Url, string $Description, string $Phone_Number = ''): ?array {
self::$RequestError = null;
$Rial = self::rial($Amount_Toman);
$Parts = parse_url($Call_Back_Url);
if ($Rial === null || !self::isConfigured() || !is_array($Parts) || empty($Parts['host'])
|| !in_array($Parts['scheme'] ?? '', ['http', 'https'], true) || isset($Parts['fragment'])
|| trim($Description) === '' || mb_strlen($Description) > 500) {
self::$RequestError = self::failure(-1002, 'validation', 'request');
return null;
}
$Quote = self::calculateFee($Amount_Toman);
if (!$Quote['Ok']) { self::$RequestError = $Quote; return null; }
$Rial = $Quote['Final_Rial'];
$Payload = ['merchant_id' => Environment::getZarinpalMerchantId(), 'amount' => $Rial, 'currency' => 'IRR', 'callback_url' => $Call_Back_Url, 'description' => $Description];
if ($Phone_Number !== '') $Payload['metadata'] = ['mobile' => $Phone_Number];
// Never retry request automatically: a lost response may already have created an order.
try { $Response = HttpClient::post(self::requestUrl(), $Payload, ['Content-Type' => 'application/json; charset=utf-8', 'Accept' => 'application/json']); }
catch (Throwable) { self::$RequestError = self::failure(-1000, 'transport', 'request'); return null; }
$Result = self::parse($Response, 'request');
if (!$Result['Ok']) { self::$RequestError = $Result; return null; }
$Data = $Result['Data'];
$Authority = $Data['authority'];
// Recheck the terminal mode and actual fee on the final request, not only the quote.
if (($Data['fee_type'] ?? '') !== 'Merchant') {
self::$RequestError = self::failure(-1003, 'configuration', 'request'); return null;
}
$ActualFee = self::integer($Data['fee'] ?? null);
if ($ActualFee === null || $ActualFee < 0 || $Rial - $ActualFee !== $Quote['Original_Rial']) {
self::$RequestError = self::failure(-1004, 'protocol', 'request'); return null;
}
return ['Authority' => $Authority, 'RedirectUrl' => self::startPayUrl($Authority), 'Amount' => $Rial / 10,
'Original_Amount' => $Quote['Original_Amount'], 'Fee' => $Quote['Fee'],
'Fee_Type' => 'Merchant', 'Buyer_Pays_Fee' => true, 'BridgeUrl' => self::bridgeUrl($Authority)];
}

public static function verify(float $Amount_Toman, string $Authority): array {
$Rial = self::rial($Amount_Toman);
if ($Rial === null || !self::isConfigured() || !self::validAuthority($Authority)) return self::failure(-1002, 'validation', 'verify');
for ($Attempt = 1; $Attempt <= 2; $Attempt++) {
try { $Response = HttpClient::post(self::verifyUrl(), ['merchant_id' => Environment::getZarinpalMerchantId(), 'amount' => $Rial, 'authority' => $Authority], ['Content-Type' => 'application/json; charset=utf-8', 'Accept' => 'application/json']); }
catch (Throwable) { $Response = ['StatusCode' => 0, 'Error' => 'transport']; }
$Result = self::parse($Response, 'verify');
if ($Result['Ok'] || ($Result['Kind'] ?? '') === 'api' || $Attempt === 2) return $Result;
if (($Result['HttpStatus'] ?? 0) === 429) return $Result;
sleep(1);
}
return self::failure(-1000, 'transport', 'verify');
}
}
?>