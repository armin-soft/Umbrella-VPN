#requires -version 5.1
<#
    آماده سازی پروژه فیلترشکن آمبرلا برای ساخت روی ویندوز.

    هیچ فایل سفارشی پروژه بازنویسی نمی شود. اسکریپت یک پروژه موقت با همان
    نسخه فلوتر می سازد و فقط فایل های زیرساخت تولیدی ویندوز را از آن کپی
    می کند (windows\flutter\CMakeLists.txt و فایل های همراه آن). این کار از
    بازنویسی runner سفارشی، مانیفست ادمین و آیکون جلوگیری می کند.

    مثال ها:
      powershell -ExecutionPolicy Bypass -File tools\bootstrap.ps1
      powershell -ExecutionPolicy Bypass -File tools\bootstrap.ps1 -Release
      powershell -ExecutionPolicy Bypass -File tools\bootstrap.ps1 -SkipBuild
#>
param(
    [switch]$Release,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $ProjectRoot

function Write-Step([string]$Text) {
    Write-Host ""
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

# ------------------------------------------------------------- 1. toolchain
Write-Step 'بررسی فلوتر'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'فلوتر نصب نیست یا در PATH نیست. از https://docs.flutter.dev/get-started/install/windows نصب کنید.'
}
flutter --version
flutter doctor -v

# ------------------------------------------------------- 2. flutter scaffold
Write-Step 'بررسی زیرساخت ویندوز'
$flutterDir = Join-Path $ProjectRoot 'windows\flutter'
$needed = @(
    'windows\flutter\CMakeLists.txt',
    'windows\runner\CMakeLists.txt',
    'windows\runner\main.cpp',
    'windows\CMakeLists.txt'
)
$missingNeeded = $needed | Where-Object { -not (Test-Path (Join-Path $ProjectRoot $_)) }
if ($missingNeeded) {
    Write-Host "فایل های لازم نیستند: $($missingNeeded -join ', ')" -ForegroundColor Yellow
}

# Only the static flutter scaffolding is taken from a fresh template. The
# generated plugin files (generated_plugins.cmake, generated_plugin_registrant)
# are produced by the flutter tool during the build, not copied here.
$scaffoldTargets = @('windows\flutter\CMakeLists.txt')
$needScaffold = $scaffoldTargets | Where-Object { -not (Test-Path (Join-Path $ProjectRoot $_)) }
if ($needScaffold) {
    Write-Host 'ساخت پروژه موقت برای گرفتن فایل های زیرساخت فلوتر ...' -ForegroundColor Yellow
    $tempRoot = Join-Path $env:TEMP ("umbrella-scaffold-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    try {
        Push-Location $tempRoot
        try {
            & flutter create --platforms=windows --org ir.umbrella --project-name umbrella_vpn umbrella_scaffold
            if ($LASTEXITCODE -ne 0) {
                throw 'ساخت پروژه موقت فلوتر ناموفق بود.'
            }
        } finally {
            Pop-Location
        }
        $sourceFlutterDir = Join-Path $tempRoot 'umbrella_scaffold\windows\flutter'
        if (-not (Test-Path (Join-Path $sourceFlutterDir 'CMakeLists.txt'))) {
            throw 'فایل windows\flutter\CMakeLists.txt در پروژه موقت پیدا نشد.'
        }
        New-Item -ItemType Directory -Force -Path $flutterDir | Out-Null
        Copy-Item (Join-Path $sourceFlutterDir 'CMakeLists.txt') $flutterDir -Force
        Write-Host 'windows\flutter\CMakeLists.txt کپی شد.' -ForegroundColor Green
    } finally {
        Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host 'windows\flutter\CMakeLists.txt از قبل موجود است.' -ForegroundColor Green
}

# Keep the generated scaffolding out of git, like the flutter template does.
$flutterGitignore = Join-Path $flutterDir '.gitignore'
if (-not (Test-Path $flutterGitignore)) {
    Set-Content -Path $flutterGitignore -Value "ephemeral/`r`n" -Encoding ASCII
}

# ------------------------------------------------------------ 3. dependencies
Write-Step 'گرفتن وابستگی ها'
flutter pub get
if ($LASTEXITCODE -ne 0) {
    throw 'flutter pub get ناموفق بود.'
}

# ------------------------------------------------------- 3.5 bundled cores
# هسته ها همراه فایل نصبی می روند؛ برنامه خودش چیزی دانلود نمی کند.
Write-Step 'آماده سازی هسته ها برای بسته بندی'
try {
    & (Join-Path $PSScriptRoot 'fetch-cores.ps1')
} catch {
    Write-Host "هشدار: هسته ها کامل آماده نشدند: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host 'فایل نصبی بدون هسته ناقص خواهد بود؛ بعدا tools\fetch-cores.ps1 را اجرا کنید.' -ForegroundColor Yellow
}

# ------------------------------------------------------------------ 4. build
if (-not $SkipBuild) {
    Write-Step 'ساخت برنامه'
    if ($Release) {
        flutter build windows --release
        $OutDir = 'build\windows\x64\runner\Release'
    } else {
        flutter build windows --debug
        $OutDir = 'build\windows\x64\runner\Debug'
    }
    if ($LASTEXITCODE -ne 0) {
        throw 'ساخت برنامه ناموفق بود.'
    }
    $coresSrc = Join-Path $ProjectRoot 'cores'
    if (Test-Path $coresSrc) {
        Copy-Item $coresSrc (Join-Path $ProjectRoot $OutDir) -Recurse -Force
        Write-Host 'هسته ها کنار فایل اجرایی کپی شدند.' -ForegroundColor Green
    } else {
        Write-Host 'پوشه cores پیدا نشد؛ نسخه ساخته شده بدون هسته است.' -ForegroundColor Yellow
    }
    Write-Host "خروجی ساخت: $ProjectRoot\$OutDir" -ForegroundColor Green
    Write-Host 'برای ساخت فایل نصبی: tools\build-installer.ps1 -SkipBuild' -ForegroundColor Green
}

Write-Host ""
Write-Host 'پایان.' -ForegroundColor Green
