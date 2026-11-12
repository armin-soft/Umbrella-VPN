# در این پوشه اجرا شود: powershell -ExecutionPolicy Bypass -File join-setup.ps1
# قطعه ها را به هم می چسباند و هش فایل نهایی را بررسی می کند.
$ErrorActionPreference = 'Stop'
$parts = Get-ChildItem -Path $PSScriptRoot -Filter 'UmbrellaVPN-Setup-1.0.0-x64.exe.part*' |
    Sort-Object Name
if ($parts.Count -eq 0) { throw 'قطعه های فایل نصب پیدا نشد' }
$target = Join-Path $PSScriptRoot 'UmbrellaVPN-Setup-1.0.0-x64.exe'
$out = [System.IO.File]::Create($target)
try {
    foreach ($part in $parts) {
        $bytes = [System.IO.File]::ReadAllBytes($part.FullName)
        $out.Write($bytes, 0, $bytes.Length)
        Write-Host ("افزوده شد: " + $part.Name)
    }
} finally { $out.Close() }
$actual = (Get-FileHash $target -Algorithm SHA256).Hash.ToLower()
$expected = ((Get-Content (Join-Path $PSScriptRoot 'SHA256SUMS.txt') -Raw) -split '\s+')[0].ToLower()
Write-Host ("sha256: " + $actual)
if ($actual -ne $expected) { throw 'هش فایل با مقدار انتظار برابر نیست' }
Write-Host 'فایل نصب آماده است.' -ForegroundColor Green
