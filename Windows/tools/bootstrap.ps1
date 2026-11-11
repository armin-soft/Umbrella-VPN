#requires -version 5.1
<#
    آماده سازی پروژه فیلترشکن آمبرلا برای ساخت روی ویندوز.

    این اسکریپت:
      1. نسخه فلوتر را بررسی می کند.
      2. فایل های تولیدی ویندوز (windows/flutter و فایل های پلاگین) را می سازد.
      3. وابستگی های دات را می گیرد.
      4. پروژه را به صورت دیباگ یا ریلیز می سازد.

    فایل های سفارشی پروژه (runner، مانیفست ادمین، آیکون و پلاگین بومی) دست
    نمی خورند، چون flutter create فایل های موجود را بازنویسی نمی کند.
#>
param(
    [switch]$Release,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $ProjectRoot

Write-Host '--- بررسی ابزارها ---' -ForegroundColor Cyan
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'فلوتر نصب نیست یا در PATH نیست. از https://docs.flutter.dev/get-started/install/windows نصب کنید.'
}
if (-not (Get-Command cl -ErrorAction SilentlyContinue)) {
    Write-Host 'توجه: کامپایلر ویژوال استودیو در PATH نیست؛ فلوتر خودش Visual Studio را پیدا می کند.' -ForegroundColor Yellow
}
flutter --version
flutter doctor -v

Write-Host '--- ساخت فایل های ویندوزی پروژه ---' -ForegroundColor Cyan
flutter create --platforms=windows --org ir.umbrella --project-name umbrella_vpn .

if (Test-Path 'windows/flutter/CMakeLists.txt') {
    Write-Host 'windows/flutter/CMakeLists.txt آماده است.'
} else {
    throw 'فایل windows/flutter/CMakeLists.txt ساخته نشد. فلوتر را به روز کنید.'
}

Write-Host '--- گرفتن وابستگی ها ---' -ForegroundColor Cyan
flutter pub get

if (-not $SkipBuild) {
    Write-Host '--- ساخت برنامه ---' -ForegroundColor Cyan
    if ($Release) {
        flutter build windows --release
        $OutDir = 'build\windows\x64\runner\Release'
    } else {
        flutter build windows --debug
        $OutDir = 'build\windows\x64\runner\Debug'
    }
    Write-Host "خروجی ساخت: $ProjectRoot\$OutDir" -ForegroundColor Green
    Write-Host 'برای اجرا: umbrella_vpn.exe (با دسترسی مدیر اجرا می شود)' -ForegroundColor Green
}

Write-Host '--- پایان ---' -ForegroundColor Green
