<?php
declare(strict_types=1);

if (PHP_VERSION_ID < 80200) {
error_log('[Umbrella-Bot][PHP-Version] PHP >= 8.2 is required but the server runs PHP ' . PHP_VERSION . ' in ' . basename(__FILE__) . '. Set the domain PHP version to 8.2 or newer (cPanel MultiPHP Manager).');
http_response_code(503);
header('Content-Type: text/plain; charset=UTF-8');
echo 'PHP 8.2+ is required.';
exit;
}

require_once __DIR__ . '/Core/Payment/ZarinPal.php';
$Page_Style = <<<'CSS'

:root{--bg:#070b16;--card:rgba(255,255,255,.055);--line:rgba(255,255,255,.12);--txt:#eaf0ff;--mut:#96a3bf;--ok:#34d399;--err:#fb7185;--brand:#7dd3fc}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px 16px;font-family:Vazirmatn,Tahoma,system-ui,sans-serif;line-height:1.95;background:var(--bg);color:var(--txt);text-align:center;overflow-x:hidden;-webkit-font-smoothing:antialiased}
body::before{content:"";position:fixed;inset:-30%;pointer-events:none;background:radial-gradient(45% 45% at 20% 16%,rgba(59,130,246,.30),transparent 60%),radial-gradient(40% 40% at 84% 80%,rgba(52,211,153,.16),transparent 60%)}
.card{position:relative;width:100%;max-width:462px;padding:38px 26px 30px;border:1px solid var(--line);border-radius:26px;background:var(--card);backdrop-filter:blur(18px);-webkit-backdrop-filter:blur(18px);box-shadow:0 28px 70px -22px rgba(0,0,0,.78)}
.logo{width:78px;height:78px;margin:0 auto 20px;display:grid;place-items:center;border-radius:24px;background:linear-gradient(145deg,#1e3a68,#0c1930);border:1px solid var(--line);box-shadow:inset 0 1px 0 rgba(255,255,255,.14)}
.logo svg{width:42px;height:42px}
h1{margin:0 0 10px;font-size:clamp(18px,4.6vw,22px);font-weight:800;letter-spacing:-.2px}
p{margin:0;color:var(--mut);font-size:clamp(13.5px,3.6vw,15px)}
.ring{position:relative;width:66px;height:66px;margin:0 auto 22px}
.ring::before{content:"";position:absolute;inset:0;border-radius:50%;background:conic-gradient(from 0deg,transparent 0 58%,#7dd3fc 82%,#34d399);-webkit-mask:radial-gradient(farthest-side,transparent calc(100% - 6px),#000 0);mask:radial-gradient(farthest-side,transparent calc(100% - 6px),#000 0);animation:spin 1s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}
.steps{list-style:none;margin:26px 0 4px;padding:16px 18px;display:grid;gap:12px;border:1px solid var(--line);border-radius:18px;background:rgba(0,0,0,.20);text-align:right}
.steps li{position:relative;padding-right:26px;font-size:14px;color:var(--mut);transition:color .3s}
.steps li::before{content:"";position:absolute;right:0;top:.75em;width:9px;height:9px;border-radius:50%;background:var(--mut);opacity:.4;transition:.3s}
.steps li.on{color:var(--txt)}
.steps li.on::before{background:var(--ok);opacity:1;box-shadow:0 0 0 4px rgba(52,211,153,.16)}
.cta{position:relative;display:block;margin-top:24px;padding:16px 26px;border:0;border-radius:16px;font:inherit;font-weight:800;font-size:16px;color:#04121f;background:linear-gradient(135deg,#7dd3fc,#34d399);text-decoration:none;cursor:pointer;overflow:hidden}
.cta::after{content:"";position:absolute;inset:0;transform:translateX(-120%);background:linear-gradient(90deg,transparent,rgba(255,255,255,.55),transparent);animation:sheen 2.6s ease-in-out infinite}
@keyframes sheen{to{transform:translateX(120%)}}
.cta:active{transform:scale(.985)}
.count{margin-top:16px;font-size:13px;color:var(--mut);font-variant-numeric:tabular-nums}
.count b{color:var(--txt);font-weight:800}
.note{margin-top:18px;font-size:12.5px;color:var(--mut)}
.back{display:inline-block;margin-top:14px;color:var(--brand);text-decoration:none;font-size:13.5px;font-weight:700}
.bad{width:66px;height:66px;margin:0 auto 20px;display:grid;place-items:center;border-radius:50%;background:rgba(251,113,133,.14);border:1px solid rgba(251,113,133,.34);color:var(--err);font-size:32px;font-weight:800;line-height:1}
.err-t{color:var(--err)}
.foot{margin-top:26px;padding-top:18px;border-top:1px solid var(--line);display:flex;align-items:center;justify-content:center;gap:9px;font-size:12.5px;color:var(--mut)}
.dot{width:7px;height:7px;border-radius:50%;background:var(--ok);box-shadow:0 0 0 4px rgba(52,211,153,.15)}
@media (prefers-reduced-motion:reduce){.ring::before,.cta::after{animation:none}}
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

$Authority = preg_replace('/[^A-Za-z0-9]/', '', (string)($_GET['a'] ?? '')) ?? '';
$User_Id = (int)($_GET['u'] ?? 0);

if ($Authority === '' || !Zarinpal::isConfigured()) {
http_response_code(400);
header('Content-Type: text/html; charset=UTF-8');
header('X-Robots-Tag: noindex, nofollow');
echo '<!DOCTYPE html><html lang="fa" dir="rtl"><head><meta charset="utf-8">'
. '<meta name="viewport" content="width=device-width,initial-scale=1">'
. '<link rel="preconnect" href="https://cdn.jsdelivr.net" crossorigin>'
. '<link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/rastikerdar/vazirmatn@v33.003/Vazirmatn-font-face.css">'
. '<style>' . $Page_Style . '</style>'
. '</head><body><main class="card">'
. '<div class="logo"><svg viewBox="0 0 24 24" fill="none" stroke="url(#ug2)" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'
. '<defs><linearGradient id="ug2" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#7dd3fc"/><stop offset="1" stop-color="#34d399"/></linearGradient></defs>'
. '<path d="M12 12a4 4 0 0 1 4 4v3a2 2 0 0 1-2 2h-1v-5a2 2 0 0 0-4 0v5H8a2 2 0 0 1-2-2v-3a4 4 0 0 1 4-4z"/>'
. '<path d="M12 12V6a2 2 0 0 1 2-2 2 2 0 0 1 2 2"/>'
. '<path d="M2.5 12a9.5 7 0 0 1 19 0 1.2 1.2 0 0 1-1.2 1.2H3.7A1.2 1.2 0 0 1 2.5 12z"/>'
. '</svg></div>'
. '<div class="bad">!</div>'
. '<h1 class="err-t">تراکنش نامعتبر است</h1>'
. '<p>این لینک پرداخت معتبر نیست یا منقضی شده است.</p>'
. '<p class="note">لطفاً دوباره از داخل ربات اقدام به پرداخت کنید.</p>'
. '<div class="foot"><span class="dot" style="background:#fb7185;box-shadow:0 0 0 4px rgba(251,113,133,.15)"></span><span>سرور آمبرلا</span></div>'
. '</main></body></html>';
exit;
}

$Target = Zarinpal::startPayUrl($Authority);
header('Referrer-Policy: strict-origin-when-cross-origin');
header('Content-Type: text/html; charset=UTF-8');
header('X-Robots-Tag: noindex, nofollow');
header('Cache-Control: no-store, no-cache, must-revalidate');
$Safe_Target = htmlspecialchars($Target, ENT_QUOTES, 'UTF-8');
$Auto_Url = json_encode($Target, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);

echo '<!DOCTYPE html>'
. '<html lang="fa" dir="rtl">'
. '<head>'
. '<meta charset="utf-8">'
. '<meta name="viewport" content="width=device-width,initial-scale=1">'
. '<meta name="referrer" content="strict-origin-when-cross-origin">'
. '<title>در حال انتقال به درگاه پرداخت</title>'
. '<link rel="preconnect" href="https://cdn.jsdelivr.net" crossorigin>'
. '<link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/rastikerdar/vazirmatn@v33.003/Vazirmatn-font-face.css">'
. '<style>' . $Page_Style . '</style>'
. '</head><body>'
. '<main class="card">'
. '<div class="logo"><svg viewBox="0 0 24 24" fill="none" stroke="url(#ug)" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'
. '<defs><linearGradient id="ug" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#7dd3fc"/><stop offset="1" stop-color="#34d399"/></linearGradient></defs>'
. '<path d="M12 12a4 4 0 0 1 4 4v3a2 2 0 0 1-2 2h-1v-5a2 2 0 0 0-4 0v5H8a2 2 0 0 1-2-2v-3a4 4 0 0 1 4-4z"/>'
. '<path d="M12 12V6a2 2 0 0 1 2-2 2 2 0 0 1 2 2"/>'
. '<path d="M2.5 12a9.5 7 0 0 1 19 0 1.2 1.2 0 0 1-1.2 1.2H3.7A1.2 1.2 0 0 1 2.5 12z"/>'
. '</svg></div>'
. '<div class="ring"></div>'
. '<h1>در حال انتقال به درگاه پرداخت</h1>'
. '<p>در حال اتصال به درگاه امن زرین پال…</p>'
. '<ul class="steps"><li>بررسی اطلاعات تراکنش</li><li>اتصال به درگاه پرداخت</li><li>ثبت پرداخت و بازگشت</li></ul>'
. '<a class="cta" id="go" href="' . $Safe_Target . '">ادامه پرداخت</a>'
. '<div class="count" id="countdown" data-sec="5"></div>'
. '<p class="note">اگر به صورت خودکار منتقل نشدید، روی دکمهٔ بالا کلیک کنید.</p>'
. '<a class="back" href="' . $Safe_Target . '">انتقال فوری به درگاه</a>'
. '<div class="foot"><span class="dot"></span><span>پرداخت امن از طریق زرین پال</span></div>'
. '</main>'
. '<script>' . $Page_Script . '</script>'
. '</body></html>';
?>