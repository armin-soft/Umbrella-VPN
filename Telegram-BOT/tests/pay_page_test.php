<?php
declare(strict_types=1);

$source = file_get_contents(__DIR__ . '/../Pay.php');
if (!is_string($source)) {
    throw new RuntimeException('Pay.php could not be read');
}

$checks = 0;
function checkPayPage(bool $condition, string $message): void {
    global $checks;
    $checks++;
    if (!$condition) {
        throw new RuntimeException($message);
    }
}

checkPayPage(str_contains($source, 'color-scheme:light;--bg:#f3f6fb'), 'payment page uses a bright, accessible background');
checkPayPage(str_contains($source, '--brand:#e11d2e'), 'payment accent matches Umbrella red');
checkPayPage(str_contains($source, '--brand-deep:#8e0e1b'), 'payment gradient matches Umbrella deep red');
checkPayPage(!str_contains($source, 'cdn.jsdelivr.net'), 'payment page has no third-party font dependency');
checkPayPage(str_contains($source, "src:url('Resources/fonts/Vazirmatn-Regular.ttf')"), 'payment page loads the local Persian font');
checkPayPage(str_contains($source, 'src="Logo.png"') && is_file(__DIR__ . '/../Logo.png'), 'payment page uses the real Umbrella logo');
foreach (['Vazirmatn-Regular.ttf', 'Vazirmatn-Bold.ttf', 'Vazirmatn-ExtraBold.ttf', 'OFL.txt'] as $fontAsset) {
    checkPayPage(is_file(__DIR__ . '/../Resources/fonts/' . $fontAsset), 'local font asset exists: ' . $fontAsset);
}
checkPayPage(str_contains($source, 'prefers-reduced-motion:reduce'), 'payment animations respect reduced motion');
checkPayPage(str_contains($source, 'location.replace'), 'automatic checkout redirect remains in place');
checkPayPage(str_contains($source, 'Zarinpal::validAuthority($Authority)'), 'payment authority validation remains in place');
checkPayPage(str_contains($source, 'Zarinpal::startPayUrl($Authority)'), 'validated orders still use the provider redirect');
checkPayPage(str_contains($source, 'X-Robots-Tag'), 'payment page remains hidden from search indexing');
checkPayPage(str_contains($source, 'Cache-Control: no-store'), 'payment page remains non-cacheable');
checkPayPage(str_contains($source, 'aria-label="مراحل پرداخت"'), 'payment progress has an accessible label');

echo "pay_page_test: {$checks} checks passed\n";
