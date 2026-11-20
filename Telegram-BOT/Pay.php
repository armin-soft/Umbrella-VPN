<?php
declare(strict_types=1);

if (PHP_VERSION_ID < 80200) {
error_log('[Umbrella-Bot][PHP-Version] PHP >= 8.2 is required but the server runs PHP ' . PHP_VERSION . ' in ' . basename(__FILE__) . '. Set the domain PHP version to 8.2 or newer (cPanel MultiPHP Manager).');
http_response_code(503);
header('Content-Type: text/plain; charset=UTF-8');
echo 'برای اجرای این بخش نسخه ۸.۲ یا جدیدتر پی اچ پی لازم است.';
exit;
}

@ini_set('default_charset', 'UTF-8');
if (function_exists('mb_internal_encoding')) {
mb_internal_encoding('UTF-8');
}

require_once __DIR__ . '/Core/Payment/ZarinPal.php';
$Page_Style = <<<'CSS'

:root{color-scheme:dark;--bg:#07080b;--surface:#12141b;--surface-high:#1a1d26;--line:rgba(255,255,255,.10);--txt:#f3f5f9;--mut:#9aa2b4;--brand:#e11d2e;--brand-deep:#8e0e1b;--ok:#22c55e;--err:#ff6b6b}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%;scrollbar-gutter:stable}
body{margin:0;min-height:100vh;min-height:100svh;display:flex;align-items:center;justify-content:center;padding:24px 16px;font-family:Vazirmatn,Tahoma,"Segoe UI",system-ui,sans-serif;line-height:1.85;background:var(--bg);color:var(--txt);text-align:center;overflow-x:hidden;-webkit-font-smoothing:antialiased}
body::before{content:"";position:fixed;inset:-30%;pointer-events:none;background:radial-gradient(44% 42% at 18% 14%,rgba(225,29,46,.24),transparent 64%),radial-gradient(38% 38% at 84% 84%,rgba(142,14,27,.18),transparent 66%)}
.card{position:relative;width:100%;max-width:472px;padding:38px 28px 28px;overflow:hidden;border:1px solid var(--line);border-radius:26px;background:linear-gradient(145deg,rgba(26,29,38,.96),rgba(18,20,27,.96));box-shadow:0 28px 76px -24px rgba(0,0,0,.82);backdrop-filter:blur(18px);-webkit-backdrop-filter:blur(18px)}
.card::before{content:"";position:absolute;inset:0 18% auto;height:1px;background:linear-gradient(90deg,transparent,rgba(225,29,46,.8),transparent)}
.logo{width:76px;height:76px;margin:0 auto 20px;display:grid;place-items:center;border-radius:23px;background:linear-gradient(145deg,rgba(225,29,46,.24),rgba(26,29,38,.9));border:1px solid rgba(225,29,46,.36);box-shadow:inset 0 1px 0 rgba(255,255,255,.08),0 14px 34px rgba(0,0,0,.22)}
.logo svg{width:42px;height:42px}
h1{margin:0 0 10px;font-size:clamp(19px,4.6vw,23px);font-weight:800;letter-spacing:-.2px;line-height:1.45}
p{margin:0;color:var(--mut);font-size:clamp(13.5px,3.6vw,15px)}
.ring{position:relative;width:66px;height:66px;margin:0 auto 22px}
.ring::before{content:"";position:absolute;inset:0;border-radius:50%;background:conic-gradient(from 0deg,transparent 0 55%,var(--brand-deep) 74%,var(--brand) 100%);-webkit-mask:radial-gradient(farthest-side,transparent calc(100% - 6px),#000 0);mask:radial-gradient(farthest-side,transparent calc(100% - 6px),#000 0);animation:spin 1s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}
.steps{list-style:none;margin:26px 0 4px;padding:16px 18px;display:grid;gap:12px;border:1px solid var(--line);border-radius:18px;background:rgba(7,8,11,.42);text-align:right}
.steps li{position:relative;padding-right:26px;font-size:14px;color:var(--mut);transition:color .3s}
.steps li::before{content:"";position:absolute;right:0;top:.75em;width:9px;height:9px;border-radius:50%;background:var(--mut);opacity:.36;transition:.3s}
.steps li.on{color:var(--txt)}
.steps li.on::before{background:var(--brand);opacity:1;box-shadow:0 0 0 4px rgba(225,29,46,.17)}
.cta{position:relative;display:block;margin-top:24px;padding:15px 24px;border:1px solid rgba(255,255,255,.15);border-radius:16px;font:inherit;font-weight:800;font-size:16px;color:#fff;background:linear-gradient(135deg,var(--brand),var(--brand-deep));text-decoration:none;cursor:pointer;overflow:hidden;box-shadow:0 12px 30px rgba(225,29,46,.23);transition:transform .18s ease,filter .18s ease}
.cta::after{content:"";position:absolute;inset:0;transform:translateX(-120%);background:linear-gradient(90deg,transparent,rgba(255,255,255,.25),transparent);animation:sheen 2.8s ease-in-out infinite}
@keyframes sheen{to{transform:translateX(120%)}}
.cta:hover{filter:brightness(1.08)}
.cta:active{transform:scale(.985)}
.cta:focus-visible,.back:focus-visible{outline:3px solid rgba(225,29,46,.5);outline-offset:4px}
.count{margin-top:16px;font-size:13px;color:var(--mut);font-variant-numeric:tabular-nums}
.count b{color:var(--txt);font-weight:800}
.note{margin-top:18px;font-size:12.5px;color:var(--mut)}
.back{display:inline-block;margin-top:14px;color:#ff6874;text-decoration:none;font-size:13.5px;font-weight:700}
.back:hover{text-decoration:underline}
.bad{width:66px;height:66px;margin:0 auto 20px;display:grid;place-items:center;border-radius:50%;background:rgba(255,107,107,.12);border:1px solid rgba(255,107,107,.34);color:var(--err);font-size:32px;font-weight:800;line-height:1}
.err-t{color:var(--err)}
.foot{margin-top:26px;padding-top:18px;border-top:1px solid var(--line);display:flex;align-items:center;justify-content:center;gap:9px;font-size:12.5px;color:var(--mut)}
.dot{width:7px;height:7px;border-radius:50%;background:var(--ok);box-shadow:0 0 0 4px rgba(34,197,94,.14)}
@media(max-width:480px){body{padding:18px 12px}.card{padding:30px 20px 24px;border-radius:22px}.steps{padding:14px 15px}}
@media(prefers-reduced-motion:reduce){*,*::before,*::after{scroll-behavior:auto!important;animation-duration:.01ms!important;animation-iteration-count:1!important;transition-duration:.01ms!important}}
CSS;

$Page_Script = <<<'JS'
(function(){
var box=document.getElementById('countdown');
var left=parseInt(box.dataset.sec||'0',10);
var step=0;
var fa=['۰','۱','۲','۳','۴','۵','۶','۷','۸','۹'];
function fa_num(n){return String(n).split('').map(function(c){return fa[+c]||c;}).join('');}
function paint(){
var items=document.querySelectorAll('.steps li');
for(var k=0;k<items.length;k++){items[k].classList.toggle('on',k<=step);}
box.innerHTML='تا انتقال خودکار: <b>'+fa_num(left)+'</b> ثانیه';
}

function go(){location.replace(document.getElementById('go').href);}
var timer=setInterval(function(){
if(left<=0){clearInterval(timer);go();return;}
paint();
left--;step++;
},1000);
paint();
setTimeout(function(){clearInterval(timer);go();},20000);
})();
JS;

$Authority = is_string($_GET['a'] ?? null) ? $_GET['a'] : '';
$User_Id = (int)($_GET['u'] ?? 0);

if (!Zarinpal::validAuthority($Authority) || !Zarinpal::isConfigured()) {
http_response_code(400);
header('Content-Type: text/html; charset=UTF-8');
header('X-Robots-Tag: noindex, nofollow');
echo '<!DOCTYPE html><html lang="fa" dir="rtl"><head><meta charset="utf-8">'
. '<meta name="viewport" content="width=device-width,initial-scale=1">'
. '<title>تراکنش نامعتبر است | آمبرلا</title>'
. '<style>' . $Page_Style . '</style>'
. '</head><body><main class="card">'
. '<div class="logo" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="url(#ug2)" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'
. '<defs><linearGradient id="ug2" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#e11d2e"/><stop offset="1" stop-color="#8e0e1b"/></linearGradient></defs>'
. '<path d="M12 12a4 4 0 0 1 4 4v3a2 2 0 0 1-2 2h-1v-5a2 2 0 0 0-4 0v5H8a2 2 0 0 1-2-2v-3a4 4 0 0 1 4-4z"/>'
. '<path d="M12 12V6a2 2 0 0 1 2-2 2 2 0 0 1 2 2"/>'
. '<path d="M2.5 12a9.5 7 0 0 1 19 0 1.2 1.2 0 0 1-1.2 1.2H3.7A1.2 1.2 0 0 1 2.5 12z"/>'
. '</svg></div>'
. '<div class="bad" role="img" aria-label="خطا">!</div>'
. '<h1 class="err-t">تراکنش نامعتبر است</h1>'
. '<p>این لینک پرداخت معتبر نیست یا منقضی شده است.</p>'
. '<p class="note">لطفاً دوباره از داخل ربات اقدام به پرداخت کنید.</p>'
. '<div class="foot"><span class="dot" style="background:#ff6b6b;box-shadow:0 0 0 4px rgba(255,107,107,.15)"></span><span>سرور آمبرلا</span></div>'
. '</main></body></html>';
exit;
}

$Target = Zarinpal::startPayUrl($Authority);
header('Referrer-Policy: strict-origin-when-cross-origin');
header('Content-Type: text/html; charset=UTF-8');
header('X-Robots-Tag: noindex, nofollow');
header('Cache-Control: no-store, no-cache, must-revalidate');
$Safe_Target = htmlspecialchars($Target, ENT_QUOTES, 'UTF-8');

echo '<!DOCTYPE html>'
. '<html lang="fa" dir="rtl">'
. '<head>'
. '<meta charset="utf-8">'
. '<meta name="viewport" content="width=device-width,initial-scale=1">'
. '<meta name="referrer" content="strict-origin-when-cross-origin">'
. '<title>در حال انتقال به درگاه پرداخت</title>'
. '<style>' . $Page_Style . '</style>'
. '</head><body>'
. '<main class="card">'
. '<div class="logo" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="url(#ug)" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'
. '<defs><linearGradient id="ug" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#e11d2e"/><stop offset="1" stop-color="#8e0e1b"/></linearGradient></defs>'
. '<path d="M12 12a4 4 0 0 1 4 4v3a2 2 0 0 1-2 2h-1v-5a2 2 0 0 0-4 0v5H8a2 2 0 0 1-2-2v-3a4 4 0 0 1 4-4z"/>'
. '<path d="M12 12V6a2 2 0 0 1 2-2 2 2 0 0 1 2 2"/>'
. '<path d="M2.5 12a9.5 7 0 0 1 19 0 1.2 1.2 0 0 1-1.2 1.2H3.7A1.2 1.2 0 0 1 2.5 12z"/>'
. '</svg></div>'
. '<div class="ring" aria-hidden="true"></div>'
. '<h1>در حال انتقال به درگاه پرداخت</h1>'
. '<p>در حال اتصال به درگاه امن زرین پال…</p>'
. '<ul class="steps" aria-label="مراحل پرداخت"><li>بررسی اطلاعات تراکنش</li><li>اتصال به درگاه پرداخت</li><li>ثبت پرداخت و بازگشت</li></ul>'
. '<a class="cta" id="go" href="' . $Safe_Target . '">ادامه پرداخت</a>'
. '<div class="count" id="countdown" data-sec="5">انتقال خودکار تا ۵ ثانیه دیگر…</div>'
. '<p class="note">اگر به صورت خودکار منتقل نشدید، روی دکمه بالا کلیک کنید.</p>'
. '<a class="back" href="' . $Safe_Target . '">انتقال فوری به درگاه</a>'
. '<div class="foot"><span class="dot"></span><span>پرداخت امن از طریق زرین پال</span></div>'
. '</main>'
. '<script>' . $Page_Script . '</script>'
. '</body></html>';
?>