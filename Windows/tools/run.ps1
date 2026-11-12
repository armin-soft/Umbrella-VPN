#requires -version 5.1
<#
    اجرای برنامه در حالت دیباگ با دسترسی مدیر.
    چون مانیفست برنامه requireAdministrator است، اجرا از ترمینال معمولی هم
    ویندوز درخواست دسترسی می دهد. اگر با flutter run کار می کنید و دسترسی
    مدیر ندارید، بخش اتصال پیام «دسترسی مدیر لازم است» می دهد.
#>
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $ProjectRoot

if (-not (Test-Path 'windows/flutter/CMakeLists.txt')) {
    Write-Host 'ابتدا tools\bootstrap.ps1 را اجرا کنید.' -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot 'bootstrap.ps1') -SkipBuild
}

flutter run -d windows
