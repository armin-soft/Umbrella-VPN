<?php
declare(strict_types=1);

/**
 * آزمون جامع کنترل محتوا و دامنه های سفارشی (افزودن، حذف، نرمال سازی، همگام سازی و منوهای ربات).
 *
 * اجرا:  php Telegram-BOT/tests/content_filter_domains_test.php
 */

$Root = dirname(__DIR__);

// شبیه ساز حافظه ای Database تا AppFilter واقعی بدون MySQL به صورت کامل و اتمی اجرا شود.
final class Database {
private static ?self $Instance = null;
/** @var array<string, array<string, mixed>> */
public array $Rows = [];

public static function getInstance(): self {
return self::$Instance ??= new self();
}

public function fetch(string $Sql, array $Params = []): ?array {
$UUID = (string)($Params[0] ?? '');
return $this->Rows[$UUID] ?? null;
}

public function execute(string $Sql, array $Params = []): bool {
if (preg_match('/INSERT INTO `App_Filter_Settings` \(([^)]+)\)/', $Sql, $Match) !== 1) {
throw new RuntimeException('Unexpected SQL: ' . $Sql);
}
$Columns = array_map(
static fn(string $Col): string => trim($Col, " `"),
explode(',', $Match[1])
);
$Row = [];
foreach ($Columns as $Index => $Col) {
$Row[$Col] = $Params[$Index] ?? null;
}
$UUID = (string)$Row['User_UUID'];
$Row['Updated_At'] = '2026-11-17 12:00:00';
$this->Rows[$UUID] = $Row;
return true;
}
}

final class Environment {
public static function get(string $Key, string $Default = ''): string {
return match ($Key) {
'WEBHOOK_URL' => 'https://bot.my-gateway.example/index.php',
default => $Default,
};
}
}

// بارگذاری خود کلاس واقعی AppFilter بدون فراخوانی Database.php واقعی.
$Filter_Source = (string)file_get_contents($Root . '/Core/App/App-Filter.php');
$Filter_Source = preg_replace('/^<\?php\s*declare\(strict_types=1\);\s*/', '', $Filter_Source) ?? $Filter_Source;
$Filter_Source = preg_replace('/require_once\s+[^;]+;/', '', $Filter_Source) ?? $Filter_Source;
$Filter_Source = preg_replace('/\?>\s*$/', '', $Filter_Source) ?? $Filter_Source;
eval($Filter_Source);

$Passed = 0;
$Failures = [];
$Check = static function (bool $Ok, string $Message) use (&$Passed, &$Failures): void {
if ($Ok) {
$Passed++;
return;
}
$Failures[] = $Message;
};

$Public_Account = AppFilter::accountPayload([
'id' => 7,
'uuid' => 'client-7',
'ed25519_private_key' => 'must-not-reach-app',
'ed25519_public_key' => 'must-not-reach-app',
'wg_pk' => 'must-not-reach-app',
'wg_pub' => 'must-not-reach-app',
'wg_psk' => 'must-not-reach-app',
]);
$Sensitive_Fields = ['ed25519_private_key', 'ed25519_public_key', 'wg_pk', 'wg_pub', 'wg_psk'];
$Check(array_intersect($Sensitive_Fields, array_keys($Public_Account)) === [], 'app account payload never includes connection keys');

// ۱. نرمال سازی دامنه ها و نشانی های وب.
$Check(AppFilter::normalizeDomain('Example.COM') === 'example.com', 'lowercases root domain');
$Check(AppFilter::normalizeDomain('https://www.Instagram.com/reel/123?x=1#top') === 'instagram.com', 'strips scheme, www, path, query, fragment');
$Check(AppFilter::normalizeDomain('http://sub.bad-site.org:8080/page') === 'sub.bad-site.org', 'keeps subdomain and strips port');
$Check(AppFilter::normalizeDomain('*.ads.tracker.net.') === 'ads.tracker.net', 'strips leading wildcard and trailing dot');
$Check(AppFilter::normalizeDomain('۱xbet.com') === '1xbet.com', 'converts Persian digits');
$Check(AppFilter::normalizeDomain('١xbet.com') === '1xbet.com', 'converts Arabic digits');
$Check(AppFilter::normalizeDomain('"tiktok.com"') === 'tiktok.com', 'strips surrounding quotes');
$Check(AppFilter::normalizeDomain('xn--mgbh0fb.xn--mgba3a4f16a') === 'xn--mgbh0fb.xn--mgba3a4f16a', 'preserves valid punycode domain');

// ۲. رد ورودی های نامعتبر و دامنه های محافظت شده.
foreach ([
'',
'   ',
'localhost',
'app.localhost',
'printer.local',
'router.lan',
'service.internal',
'127.0.0.1',
'192.168.1.1',
'[::1]',
'2001:db8::1',
'singleword',
'-bad.com',
'bad-.com',
'bad..com',
'site.123',
'umbrella-vpn.ir',
'api.umbrella-vpn.ir',
'bot.my-gateway.example',
] as $Invalid) {
$Check(AppFilter::normalizeDomain($Invalid) === null, "rejects invalid/protected input: {$Invalid}");
}

// ۳. تجزیه ورودی چندتایی (افزودن + حذف با پیشوند - + ویرگول فارسی + خط جدید).
$Parsed = AppFilter::parseDomainsInput("https://www.site-a.com/x، site-b.org\n-old-site.net ; not_a_domain 127.0.0.1");
$Check($Parsed['add'] === ['site-a.com', 'site-b.org'], 'parses bulk add list cleanly');
$Check($Parsed['remove'] === ['old-site.net'], 'parses -domain removal entries cleanly');
$Check(count($Parsed['invalid']) === 2, 'reports invalid items separately');

// ۴. چرخه کامل افزودن، تکرار، حذف با توکن، حذف با متن و پاک سازی کامل.
$UUID = 'user-uuid-filter-test';
$Initial = AppFilter::load($UUID);
$Check($Initial['enabled'] === false && $Initial['custom_domains'] === [], 'starts empty and disabled');

$Step1 = AppFilter::applyDomainChanges($UUID, ['https://www.alpha.com', 'beta.org', 'alpha.com'], [], 'bot');
$Check($Step1['added'] === ['alpha.com', 'beta.org'], 'adds two unique normalized domains');
$Check($Step1['duplicates'] === ['alpha.com'], 'flags duplicate in same batch');
$Check($Step1['settings']['enabled'] === true, 'auto-enables filter when custom domains are added');
$Check($Step1['settings']['custom_domains'] === ['alpha.com', 'beta.org'], 'persists domains in DB');
$Check($Step1['settings']['updated_by'] === 'bot', 'records bot as source');
$Check(str_contains(AppFilter::summary($Step1['settings']), 'دامنه های سفارشی: ۲ مورد'), 'summary shows custom domain count');

// حذف تکی با توکن دکمه اینلاین تلگرام.
$Alpha_Token = AppFilter::domainToken('alpha.com');
$Check(strlen($Alpha_Token) === 12 && strlen('app_fdom_del:' . $Alpha_Token . ':99') <= 64, 'callback_data stays well under 64 bytes');
$Del = AppFilter::removeDomainByToken($UUID, $Alpha_Token, 'bot');
$Check($Del['removed'] === 'alpha.com', 'removes exact domain matching token');
$Check($Del['settings']['custom_domains'] === ['beta.org'], 'keeps remaining custom domain');
$Check($Del['settings']['enabled'] === true, 'stays enabled while beta.org remains');

// حذف آخرین دامنه بدون دسته فعال -> خاموش شدن خودکار کنترل محتوا.
$Del2 = AppFilter::removeDomainByToken($UUID, AppFilter::domainToken('beta.org'), 'bot');
$Check($Del2['removed'] === 'beta.org', 'removes last custom domain');
$Check($Del2['settings']['custom_domains'] === [], 'custom domain list is empty');
$Check($Del2['settings']['enabled'] === false, 'auto-disables when no categories and no custom domains remain');

// همگام سازی دوطرفه با برنامه ویندوز (save از app و clearDomains در حضور دسته فعال).
$From_App = AppFilter::save($UUID, [
'enabled' => true,
'categories' => ['adult', 'ads'],
'custom_domains' => ['gamma.io', 'https://delta.co/path'],
], 'app');
$Check($From_App['categories'] === ['adult'], 'drops retired ads category from app settings');
$Check($From_App['custom_domains'] === ['gamma.io', 'delta.co'], 'stores normalized domains from app');
$Check($From_App['updated_by'] === 'app', 'records app as source');

$Cleared = AppFilter::clearDomains($UUID, 'bot');
$Check($Cleared['custom_domains'] === [], 'clearDomains empties custom domains');
$Check($Cleared['categories'] === ['adult'], 'clearDomains preserves supported categories only');
$Check($Cleared['enabled'] === true, 'clearDomains stays enabled because categories are active');

// خاموش کردن همه دسته ها در نبود دامنه سفارشی -> خاموش شدن خودکار.
AppFilter::toggle($UUID, 'adult', 'bot');
$After_Last_Toggle = AppFilter::toggle($UUID, 'gambling', 'bot');
$Check($After_Last_Toggle['categories'] === [] && $After_Last_Toggle['enabled'] === false, 'toggling off last category auto-disables filter');

// بررسی سقف MAX_CUSTOM_DOMAINS.
$Many = [];
for ($I = 1; $I <= AppFilter::MAX_CUSTOM_DOMAINS + 5; $I++) {
$Many[] = "site{$I}.example.com";
}
$Capped = AppFilter::applyDomainChanges($UUID, $Many, [], 'bot');
$Check(count($Capped['settings']['custom_domains']) === AppFilter::MAX_CUSTOM_DOMAINS, 'enforces MAX_CUSTOM_DOMAINS cap');
$Check(count($Capped['skipped_limit']) === 5, 'reports overflow count in skipped_limit');

// ۵. بررسی اتصال کامل مسیرهای ربات در App-Link.php و Dispatcher.php.
$App_Link = (string)file_get_contents($Root . '/Bot/App-Link.php');
$Dispatcher = (string)file_get_contents($Root . '/Bot/Dispatcher.php');
foreach (['filterDomainsMenu', 'filterDomainsStart', 'filterDomainsInput', 'filterDomainDelete', 'filterDomainsClearAsk', 'filterDomainsClearConfirm'] as $Method) {
$Check(str_contains($App_Link, "function {$Method}("), "AppFlow defines {$Method}()");
$Check(str_contains($Dispatcher, "AppFlow::{$Method}("), "Dispatcher routes to AppFlow::{$Method}()");
}

if ($Failures !== []) {
fwrite(STDERR, "FAILURES (content filter domains)\n");
foreach ($Failures as $Failure) {
fwrite(STDERR, " - {$Failure}\n");
}
exit(1);
}

echo "OK content filter domains tests ({$Passed} assertions)\n";
