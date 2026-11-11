<?php
declare(strict_types=1);

final class HttpClient {
private const CURLOPT_CONNECTTIMEOUT = 78;
private function __construct() {
}

public static function get(string $Url, array $Headers = [], int $Time_Out = 30): array {
return static::request('GET', $Url, null, $Headers, $Time_Out);
}

public static function post(string $Url, mixed $Body = null, array $Headers = [], int $Time_Out = 30): array {
return static::request('POST', $Url, $Body, $Headers, $Time_Out);
}

public static function postMultipart(string $Url, array $Fields, array $Headers = [], int $Time_Out = 60): array {
$Ch = curl_init($Url);
$Header_List = [];

foreach ($Headers as $Key => $Value) {
$Header_List[] = (string)$Key . ': ' . (string)$Value;
}

$Multipart = [];

foreach ($Fields as $Name => $Value) {
if ($Value instanceof \CURLFile) {
$Multipart[$Name] = $Value;
}

else {
$Multipart[$Name] = (string)$Value;
}
}

curl_setopt_array($Ch, [
CURLOPT_RETURNTRANSFER => true,
CURLOPT_FOLLOWLOCATION => true,
CURLOPT_TIMEOUT => $Time_Out,
self::CURLOPT_CONNECTTIMEOUT => 10,
CURLOPT_POST => true,
CURLOPT_POSTFIELDS => $Multipart,
CURLOPT_HTTPHEADER => $Header_List,
CURLOPT_SSL_VERIFYPEER => true,
CURLOPT_SSL_VERIFYHOST => 2,
...(self::certificateBundle() !== null ? [CURLOPT_CAINFO => self::certificateBundle()] : []),
CURLOPT_USERAGENT => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
]);

$Raw_Body = curl_exec($Ch);
$Status_Code = (int)curl_getinfo($Ch, CURLINFO_RESPONSE_CODE);
$Error = curl_error($Ch);
unset($Ch);

return [
'StatusCode' => $Status_Code,
'Body' => $Raw_Body === false ? '' : (string)$Raw_Body,
'Json' => $Raw_Body === false ? null : json_decode($Raw_Body, true),
'Error' => $Error,
];
}

public static function patch(string $Url, mixed $Body = null, array $Headers = [], int $Time_Out = 30): array {
return static::request('PATCH', $Url, $Body, $Headers, $Time_Out);
}

public static function delete(string $Url, array $Headers = [], int $Time_Out = 30): array {
return static::request('DELETE', $Url, null, $Headers, $Time_Out);
}

private static function request(string $Method, string $Url, mixed $Body, array $Headers, int $Time_Out): array {
$Ch = curl_init($Url);
$Header_List = [];

foreach ($Headers as $Key => $Value) {
$Header_List[] = (string)$Key . ': ' . (string)$Value;
}

curl_setopt_array($Ch, [
CURLOPT_RETURNTRANSFER => true,
CURLOPT_FOLLOWLOCATION => true,
CURLOPT_TIMEOUT => $Time_Out,
self::CURLOPT_CONNECTTIMEOUT => 10,
CURLOPT_HTTPHEADER => $Header_List,
CURLOPT_SSL_VERIFYPEER => true,
CURLOPT_SSL_VERIFYHOST => 2,
...(self::certificateBundle() !== null ? [CURLOPT_CAINFO => self::certificateBundle()] : []),
CURLOPT_USERAGENT => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
]);

if ($Method === 'POST') {
curl_setopt($Ch, CURLOPT_POST, true);

if (is_array($Body) && !array_is_list($Body)) {
curl_setopt($Ch, CURLOPT_POSTFIELDS, json_encode($Body, JSON_UNESCAPED_UNICODE));

if (!self::hasHeader($Header_List, 'Content-Type')) {
$Header_List[] = 'Content-Type: application/json';
curl_setopt($Ch, CURLOPT_HTTPHEADER, $Header_List);
}
}

elseif (is_string($Body) && $Body !== '') {
curl_setopt($Ch, CURLOPT_POSTFIELDS, $Body);
}
}

elseif ($Method === 'PATCH' || $Method === 'DELETE') {
curl_setopt($Ch, CURLOPT_CUSTOMREQUEST, $Method);

if ($Method === 'PATCH' && is_array($Body) && !array_is_list($Body)) {
curl_setopt($Ch, CURLOPT_POSTFIELDS, json_encode($Body, JSON_UNESCAPED_UNICODE));

if (!self::hasHeader($Header_List, 'Content-Type')) {
$Header_List[] = 'Content-Type: application/json';
curl_setopt($Ch, CURLOPT_HTTPHEADER, $Header_List);
}
}
}

$Raw_Body = curl_exec($Ch);
$Status_Code = (int)curl_getinfo($Ch, CURLINFO_RESPONSE_CODE);
$Error = curl_error($Ch);
unset($Ch);

return [
'StatusCode' => $Status_Code,
'Body' => $Raw_Body === false ? '' : (string)$Raw_Body,
'Json' => $Raw_Body === false ? null : json_decode($Raw_Body, true),
'Error' => $Error,
];
}

private static function hasHeader(array $Headers, string $Target): bool {
foreach ($Headers as $Header) {
if (stripos($Header, $Target . ':') !== false) return true;
}

return false;
}

private static function certificateBundle(): ?string {
static $Cached = false;
static $Path = null;

if ($Cached) return $Path;
$Cached = true;
$Ini = (string)(ini_get('curl.cainfo') ?: ini_get('openssl.cafile') ?: '');

if ($Ini !== '' && is_file($Ini)) {
return $Path = $Ini;
}

$Local = dirname(__DIR__, 2) . '/Cert/Cacert.Pem';

if (is_file($Local)) {
return $Path = $Local;
}

return $Path = null;
}
}
?>