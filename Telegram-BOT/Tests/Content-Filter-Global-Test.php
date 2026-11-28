<?php
declare(strict_types=1);

/** Offline behavioral tests for administrator-wide content-filter policy. */
$Root = dirname(__DIR__);

final class Database {
private static ?self $Instance = null;
/** @var array<string, array<string, mixed>> */
public array $FilterRows = [];
/** @var array<string, string> */
public array $Settings = [];

public static function getInstance(): self {
return self::$Instance ??= new self();
}

public function fetch(string $Sql, array $Params = []): ?array {
if (str_contains($Sql, 'App_Filter_Settings')) {
return $this->FilterRows[(string)($Params[0] ?? '')] ?? null;
}
return null;
}

public function scalar(string $Sql, array $Params = [], mixed $Default = null): mixed {
if (str_contains($Sql, '`Settings`')) {
return $this->Settings[(string)($Params[0] ?? '')] ?? $Default;
}
return $Default;
}

public function execute(string $Sql, array $Params = []): bool {
if (str_contains($Sql, 'INSERT INTO `Settings`')) {
$this->Settings[(string)$Params[0]] = (string)$Params[1];
return true;
}
if (!str_contains($Sql, 'INSERT INTO `App_Filter_Settings`')
|| preg_match('/INSERT INTO `App_Filter_Settings` \(([^)]+)\)/', $Sql, $Match) !== 1) {
throw new RuntimeException('Unexpected SQL: ' . $Sql);
}
$Columns = array_map(static fn(string $Column): string => trim($Column, " `"), explode(',', $Match[1]));
$Row = [];
foreach ($Columns as $Index => $Column) $Row[$Column] = $Params[$Index] ?? null;
$Uuid = (string)$Row['User_UUID'];
$Row['Updated_At'] = gmdate('Y-m-d H:i:s');
$this->FilterRows[$Uuid] = $Row;
return true;
}
}

$Source = (string)file_get_contents($Root . '/Core/App/App-Filter.php');
$Source = preg_replace('/^<\?php\s*declare\(strict_types=1\);\s*/', '', $Source) ?? $Source;
$Source = preg_replace('/require_once\s+[^;]+;/', '', $Source) ?? $Source;
$Source = preg_replace('/\?>\s*$/', '', $Source) ?? $Source;
eval($Source);

$Passed = 0;
$Check = static function (bool $Ok, string $Message) use (&$Passed): void {
if (!$Ok) throw new RuntimeException($Message);
$Passed++;
};

$Global = AppFilter::saveGlobal([
'enabled' => true,
'categories' => ['adult', 'social', 'gambling'],
'custom_domains' => ['https://www.global.example/path'],
]);
$Check($Global['enabled'] === true, 'global policy is enabled when it has rules');
$Check($Global['categories'] === ['adult', 'gambling'], 'global categories are restricted to bot-supported categories');
$Check($Global['custom_domains'] === ['global.example'], 'global domains are normalized');

$Personal = AppFilter::save('account-one', [
'enabled' => true,
'categories' => ['ads', 'dating'],
'custom_domains' => ['personal.example'],
], 'app');
$Effective = AppFilter::loadEffective('account-one');
$Check($Effective['enabled'] === true, 'effective filter is enabled');
$Check($Effective['categories'] === ['adult', 'gambling', 'ads', 'dating'], 'global and active personal categories are merged');
$Check($Effective['custom_domains'] === ['global.example', 'personal.example'], 'global domains are placed first');
$Check($Effective['global']['enabled'] === true && $Effective['personal']['enabled'] === true, 'response carries global and personal snapshots');

$Edit = $Effective;
$Edit['categories'][] = 'messaging'; // app-only categories remain personal
$Edit['custom_domains'][] = 'new-personal.example';
$Saved = AppFilter::saveFromApp('account-one', $Edit);
$Personal_After = AppFilter::load('account-one');
$Check(!in_array('adult', $Personal_After['categories'], true), 'admin category is not copied into per-account storage');
$Check(in_array('messaging', $Personal_After['categories'], true), 'app can still save app-only personal categories');
$Check(!in_array('global.example', $Personal_After['custom_domains'], true), 'admin domain is not copied into per-account storage');
$Check(in_array('new-personal.example', $Personal_After['custom_domains'], true), 'app can still save personal domains');
$Check(in_array('adult', $Saved['categories'], true) && in_array('global.example', $Saved['custom_domains'], true), 'saved response still enforces global policy');

// The Windows UI and bot expose only the two bot categories (`adult`, `gambling`),
// so mimic its model dropping legacy/removed categories from both views.
$Check(!array_key_exists('ads', AppFilter::BOT_CATEGORIES), 'ads is removed from BOT_CATEGORIES because ad blocking is always active');
$Windows_View = AppFilter::loadEffective('account-one');
$Windows_View['categories'] = array_values(array_intersect($Windows_View['categories'], array_keys(AppFilter::BOT_CATEGORIES)));
$Windows_View['personal']['categories'] = array_values(array_intersect($Windows_View['personal']['categories'], array_keys(AppFilter::BOT_CATEGORIES)));
AppFilter::saveFromApp('account-one', $Windows_View);
$Check(in_array('messaging', AppFilter::load('account-one')['categories'], true), 'Windows save preserves personal categories not exposed by its UI');

AppFilter::save('account-hidden-disabled', [
'enabled' => false,
'categories' => ['messaging'],
'custom_domains' => [],
], 'app');
$Hidden_Disabled = AppFilter::loadEffective('account-hidden-disabled');
$Hidden_Disabled['categories'] = array_values(array_intersect($Hidden_Disabled['categories'], array_keys(AppFilter::BOT_CATEGORIES)));
$Hidden_Disabled['personal']['categories'] = [];
AppFilter::saveFromApp('account-hidden-disabled', $Hidden_Disabled);
$Hidden_Personal = AppFilter::load('account-hidden-disabled');
$Check(!$Hidden_Personal['enabled'] && in_array('messaging', $Hidden_Personal['categories'], true), 'hidden personal categories stay saved without enabling a disabled filter');

AppFilter::save('account-two', [
'enabled' => false,
'categories' => ['dating'],
'custom_domains' => ['disabled-personal.example'],
], 'app');
$Disabled_Personal = AppFilter::loadEffective('account-two');
$Check($Disabled_Personal['enabled'] === true, 'global policy applies to a user with personal filtering off');
$Check($Disabled_Personal['categories'] === ['adult', 'gambling'], 'disabled personal rules do not become active under global enforcement');
$Check($Disabled_Personal['personal']['enabled'] === false, 'personal disabled state remains separately available');
$Unchanged = AppFilter::saveFromApp('account-two', $Disabled_Personal);
$Check(AppFilter::load('account-two')['enabled'] === false, 'saving an unchanged effective view does not enable personal filtering');
$Check($Unchanged['enabled'] === true, 'global filter remains active after a personal save');

$Edit_Personal = $Disabled_Personal;
$Edit_Personal['categories'][] = 'ads';
$Enabled_Personal = AppFilter::saveFromApp('account-two', $Edit_Personal);
$Check(AppFilter::load('account-two')['enabled'] === true, 'adding a personal rule enables that personal policy');
$Check(in_array('dating', $Enabled_Personal['categories'], true) && in_array('ads', $Enabled_Personal['categories'], true), 'adding a personal rule preserves its saved settings');

AppFilter::saveGlobal([
'enabled' => false,
'categories' => ['adult', 'gambling'],
'custom_domains' => ['global.example'],
]);
$After_Global_Off = AppFilter::loadEffective('account-one');
$Check($After_Global_Off['enabled'] === true, 'personal filter continues after the administrator disables global rules');
$Check(!in_array('adult', $After_Global_Off['categories'], true), 'disabled global rules are removed from effective output');
$Check(!in_array('global.example', $After_Global_Off['custom_domains'], true), 'disabled global domains are removed from effective output');

$Empty = AppFilter::saveGlobal(['enabled' => true, 'categories' => [], 'custom_domains' => []]);
$Check($Empty['enabled'] === false, 'empty global policy cannot be enabled');

fwrite(STDOUT, "OK global content filter tests ({$Passed} assertions)\n");
