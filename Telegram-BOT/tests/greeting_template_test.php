<?php
declare(strict_types=1);
// Run the complete production Helper without bootstrap or network access.
final class Environment {
public static function getDateTimeApiUrl(): string { throw new RuntimeException('offline test'); }
}
final class Context {
public int $UserId = 123456;
public function profileName(): string { return 'علی رضایی'; }
}
$Source = (string)file_get_contents(dirname(__DIR__) . '/Core/Support/Helper.php');
eval(preg_replace('/\?>\s*$/', '', substr($Source, strpos($Source, 'final class Helper {'))));
$Checks = 0;
function check(bool $Passed, string $Message): void {
global $Checks;
if (!$Passed) throw new RuntimeException($Message);
$Checks++;
}
$Context = new Context();
$Cases = [
'💳 مدیریت اعتبار' => 'مدیریت اعتبار',
'🖥️ مدیریت سرور' => 'مدیریت سرور',
'👨‍💻 حساب کاربری' => 'حساب کاربری',
" \n📱  دستگاه های من  " => 'دستگاه های من',
"دستگاه\u{200C}های من" => 'دستگاه های من',
'تیکت #42' => 'تیکت #۴۲',
'تأیید دومرحله ای' => 'تأیید دومرحله ای',
'💳' => 'منوی اصلی',
];
foreach ($Cases as $Input => $Expected) {
foreach (['adminGreeting' => 'مدیریت', 'userGreeting' => 'کاربر'] as $Method => $Type) {
$Text = Helper::$Method($Context, $Input);
check(str_starts_with($Text, "🌹{$Type} گرامی [علی رضایی](tg://user?id=123456) به بخش {$Expected} خوش آمدید.\n"), $Method . ': consistent greeting for ' . $Input);
check(str_contains($Text, '📆تاریخ شمسی:') && str_contains($Text, '🕰زمان:'), 'date and clock retained without network');
check(str_ends_with($Text, Helper::SEPARATOR_LINE . "\n"), 'message body starts after separator on its own line');
}
check(str_contains(Helper::frame('کاربر', 'نام کامل', $Input, 123), "به بخش {$Expected} خوش آمدید."), 'frame uses same section template');
check(str_contains(Helper::adminGreetingNamed('مدیر', $Input, 123), "به بخش {$Expected} خوش آمدید."), 'named admin greeting uses same section template');
}
// Audit all literal greeting/category titles, not just the credit menu.
$Titles = [];
foreach (glob(dirname(__DIR__) . '/Bot/*.php') as $File) {
$Text = (string)file_get_contents($File);
preg_match_all('/(?:adminGreeting|userGreeting|greet|categoryMenu)\(\$Context,\s*([\'"])([^\'"\n]+)\1/u', $Text, $Matches);
foreach ($Matches[2] as $Title) {
check(!preg_match('/^[\s\p{So}\p{Sk}\x{FE0F}\x{200D}]+/u', $Title), basename($File) . ': title is plain: ' . $Title);
$Titles[$Title] = true;
}
}
foreach (array_keys($Titles) as $Title) {
$Text = Helper::adminGreeting($Context, $Title);
check(str_contains($Text, "به بخش {$Title} خوش آمدید.\n"), 'literal title uses shared template: ' . $Title);
}
$Admin = (string)file_get_contents(dirname(__DIR__) . '/Bot/Admin.php');
check(str_contains($Admin, "[['💳مدیریت اعتبار', 'اعتبار حساب کاربری']]"), 'credit button emoji is preserved');
check(str_contains($Admin, "self::categoryMenu(\$Context, 'مدیریت اعتبار',"), 'credit greeting title is plain');
echo "OK greeting template tests ({$Checks} assertions, " . count($Titles) . " distinct titles)\n";
