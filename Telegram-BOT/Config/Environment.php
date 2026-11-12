<?php
declare(strict_types=1);

final class Environment {
public const APP_NAME = 'فیلترشکن آمبرلا';
private static bool $Loaded = false;

public static function get(string $Key, string $Default = ''): string {
self::loadDotEnv();

$Value = $_SERVER[$Key] ?? getenv($Key);
return is_string($Value) && $Value !== '' ? trim($Value) : $Default;
}

private static function loadDotEnv(): void {
if (self::$Loaded) return;
self::$Loaded = true;
$File = dirname(__DIR__, 1) . '/.env';

if (!is_file($File)) return;
foreach (file($File, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $Line) {
$Line = trim($Line);

if ($Line === '' || str_starts_with($Line, '#') || !str_contains($Line, '=')) continue;
[$Name, $Value] = explode('=', $Line, 2);
$Name = trim($Name);
$Value = trim($Value);

if ($Name !== '' && !array_key_exists($Name, $_SERVER)) {
$_SERVER[$Name] = $Value;
}
}
}

public static function getInt(string $Key, int $Default = 0): int {
return (int)(self::get($Key, (string)$Default) ?: $Default);
}

public static function getDatabaseHost(): string {
return self::get('DB_HOST', self::get('MYSQL_HOST'));
}

public static function getDatabasePort(): int {
return self::getInt('DB_PORT', 3306);
}

public static function getDatabaseName(): string {
return self::get('DB_NAME', self::get('MYSQL_DATABASE'));
}

public static function getDatabaseUser(): string {
return self::get('DB_USER', self::get('MYSQL_USER', 'root'));
}

public static function getDatabasePassword(): string {
return self::get('DB_PASSWORD', self::get('MYSQL_PASSWORD', ''));
}

public static function getOtpPatternCode(): string {
// الگوی «کد تایید» در IPPanel (text: «سلام کد تایید شما %Code% می باشد.
// سرور آمبرلا - آرمین سافت»). قابل تغییر با IPPANEL_OTP_PATTERN در .env
return self::get('IPPANEL_OTP_PATTERN', 'x7fhdaesmlj7vfi');
}

/** Shared secret the desktop app's gateway calls must present. */
/**
 * Optional operator override for the gateway signing key. Leave it out of
 * `.env`: `AppSecret::get()` generates one and keeps it in `Settings`, so the
 * app works with no manual secret at all. When this returns a value it takes
 * precedence over the stored key (and the diag route asks for it as ?key=).
 */
public static function getAppGatewaySecret(): string {
return self::get('APP_GATEWAY_SECRET');
}

/** Maximum sign-in SMS the gateway may send per hour, globally (0 = unlimited). */
public static function getAppOtpMaxHourly(): int {
return max(0, self::getInt('APP_OTP_MAX_HOURLY', 500));
}

/** Lifetime of one sign-in challenge, in seconds. */
public static function getSignInTtl(): int {
return max(60, self::getInt('APP_SIGNIN_TTL', 300));
}


/** Seconds a number has to wait before another code is sent. */
public static function getOtpCooldown(): int {
return max(30, self::getInt('APP_OTP_COOLDOWN', 120));
}

public static function getBotToken(): string {
return self::get('BOT_TOKEN');
}

public static function getBotUsername(): string {
$Username = self::get('BOT_USERNAME');
return ltrim($Username, '@');
}

public static function getAdminUserId(): int {
return (int)self::get('ADMIN_USER_ID');
}

public static function getChannelUrl(): string {
return self::get('CHANNEL_URL');
}


public static function getChannelGraceSeconds(): int {
return self::getInt('CHANNEL_GRACE_SECONDS', 3600);
}

public static function getSupportUrl(): string {
return self::get('SUPPORT_URL');
}


public static function getUmbrellaBaseUrl(): string {
return self::get('UMBRELLA_BASE_URL');
}

public static function getUmbrellaApiKey(): string {
return self::get('UMBRELLA_API_KEY');
}

public static function getSmsUrl(): string {
return self::get('IPPANEL_API_BASE_URL', self::get('SMS_URL', 'https://edge.ippanel.com/v1/api/send'));
}

public static function getSmsApiKey(): string {
return self::get('IPPANEL_API_KEY', self::get('SMS_API_KEY'));
}

public static function getSmsSender(): string {
return self::get('IPPANEL_SENDER', self::get('SMS_SENDER'));
}

public static function getTelegramChannelId(): string {
return self::get('TELEGRAM_CHANNEL_ID');
}

public static function getZarinpalMerchantId(): string {
return self::get('ZARINPAL_MERCHANT_ID');
}

public static function getZarinpalMode(): string {
$Mode = strtolower(trim(self::get('ZARINPAL_MODE', 'production')));
return in_array($Mode, ['sandbox', 'test', 'sandbox.zarinpal.com'], true) ? 'sandbox' : 'production';
}

public static function isZarinpalSandbox(): bool {
return self::getZarinpalMode() === 'sandbox';
}

public static function getPaymentCallbackUrl(): string {
return rtrim(self::get('PAYMENT_CALLBACK_URL'), '?&');
}

public static function getPlanPrice(int|string $Months): float {
return (float)self::get('PLAN_PRICE_' . $Months);
}

public static function getMinimumPaymentAmount(): float {
return 20000.0;
}

public static function getCustomDayRate(): float {
$Month_Price = (float)self::get('PLAN_PRICE_1');
return $Month_Price > 0 ? $Month_Price / 30.0 : 13333.0;
}

public static function getCustomMinDays(): int {
return self::getInt('CUSTOM_MIN_DAYS', 1);
}

public static function getCustomMaxDays(): int {
return self::getInt('CUSTOM_MAX_DAYS', 365);
}

public static function getCustomMinGB(): float {
return (float)self::get('CUSTOM_MIN_GB', '1');
}

public static function getCustomMaxGB(): float {
return (float)self::get('CUSTOM_MAX_GB', '1000');
}

public static function getAdminFullName(): string {
return self::get('ADMIN_FULL_NAME');
}

public static function getRobotVersion(): string {
return self::get('ROBOT_VERSION');
}

public static function getSubscriptionLinkBase(): string {
return self::get('SUBSCRIPTION_LINK_BASE');
}

public static function getDateTimeApiUrl(): string {
return self::get('DATE_TIME_API_URL', 'https://api.armin-soft.ir/Date-Time/');
}

public static function getDateTimeApiLicense(): string {
return self::get('DATE_TIME_API_LICENSE', '');
}

public static function showEmergencyConfig(): bool {
$Val = strtolower(self::get('SHOW_EMERGENCY_CONFIG', 'true'));
return $Val === 'true' || $Val === '1';
}

public static function getEmergencyConfigUrl(): string {
$Url = self::get('EMERGENCY_CONFIG_URL');
return $Url !== '' ? $Url : 'https://raw.githubusercontent.com/armin-soft/Umbrella-VPN-Config/refs/heads/main/Emergency-Configuration.txt';
}
}
?>