#requires -version 5.1
<#
    ساخت فایل نصبی ویندوز (UmbrellaVPN-Setup-1.0.4-x64.exe).

    پیش نیازها روی ماشین ویندوز:
      - فلوتر و Visual Studio 2022 با بار کاری سی پلاس پلاس
      - Inno Setup 6 (اگر نصب نباشد با سوئیچ -InstallInno از winget نصب می شود)

    مثال ها:
      powershell -ExecutionPolicy Bypass -File tools\build-installer.ps1
      powershell -ExecutionPolicy Bypass -File tools\build-installer.ps1 -SkipBuild
      powershell -ExecutionPolicy Bypass -File tools\build-installer.ps1 -Portable
#>
param(
    [switch]$SkipBuild,
    [switch]$Portable,
    [switch]$InstallInno,
    [string]$InnoPath = ''
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $ProjectRoot

$Version = '1.0.4'
$ReleaseDir = Join-Path $ProjectRoot 'build\windows\x64\runner\Release'

# هسته های اتصال باید داخل فایل نصبی باشند؛ اینجا فقط روی ماشین سازنده گرفته
# می شوند و برنامه هیچ دانلودی انجام نمی دهد.
$coresDir = Join-Path $ProjectRoot 'cores'
if (-not (Test-Path (Join-Path $coresDir 'bin'))) {
    Write-Host 'هسته ها آماده نیستند؛ اجرای tools\fetch-cores.ps1' -ForegroundColor Yellow
}
& (Join-Path $PSScriptRoot 'fetch-cores.ps1')

# تنها هسته ای که همراه نسخه می آید موتور هسته است. کتابخانه اش و کرونتش با
# نام واقعی خودشان کنار هم در cores\umbrella می مانند؛ فایل های اجرایی
# آمبرلا کنار خود برنامه ساخته می شوند.
$requiredCores = @(
    'umbrella\UmbrellaCore.dll',
    'umbrella\libcronet.dll'
)
$missingCores = $requiredCores | Where-Object { -not (Test-Path (Join-Path $coresDir $_)) }
if ($missingCores) {
    throw "هسته های الزامی برای بسته بندی پیدا نشدند: $($missingCores -join ', ') - ابتدا tools\fetch-cores.ps1 را اجرا کنید."
}
# لانچرهای هسته همراه برنامه، از همان ساخت CMake می آیند.
$requiredExes = @(
    'UmbrellaCli.exe',
    'UmbrellaAdmin.exe',
    'UmbrellaCoreEngine.exe'
)
$missingExes = $requiredExes | Where-Object { -not (Test-Path (Join-Path $ReleaseDir $_)) }
if ($missingExes) {
    throw "لانچرهای هسته ساخته نشدند: $($missingExes -join ', ') - ساخت ویندوز را دوباره اجرا کنید."
}
$ReleaseExe = Join-Path $ReleaseDir 'UmbrellaVPN.exe'
$IssFile = Join-Path $ProjectRoot 'installer\umbrella.iss'
$DistDir = Join-Path $ProjectRoot 'dist'

function Write-Step([string]$Text) {
    Write-Host ""
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

# ---------------------------------------------------------------- 1. build
Write-Step 'بررسی خروجی ساخت'
if (-not $SkipBuild -or -not (Test-Path $ReleaseExe)) {
    Write-Host 'ساخت نسخه ریلیز با tools\bootstrap.ps1 ...' -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot 'bootstrap.ps1') -Release
}
if (-not (Test-Path $ReleaseExe)) {
    throw "فایل $ReleaseExe ساخته نشد. ابتدا tools\bootstrap.ps1 -Release را اجرا کنید."
}
# هسته ها باید کنار فایل اجرایی در خروجی ساخت باشند؛ نصب کننده از همین پوشه
# آن ها را در {app}\cores می ریزد.
$releaseCores = Join-Path $ReleaseDir 'cores'
if (-not (Test-Path $releaseCores)) {
    Write-Host 'کپی هسته ها در خروجی ساخت ...' -ForegroundColor Yellow
    Copy-Item $coresDir $releaseCores -Recurse -Force
}
$sizeMb = [math]::Round((Get-ChildItem $ReleaseDir -Recurse -File | Measure-Object Length -Sum).Sum / 1MB, 1)
Write-Host "خروجی آماده است: $ReleaseDir ($sizeMb مگابایت)" -ForegroundColor Green

# ---------------------------------------------------------------- 2. inno
Write-Step 'پیدا کردن Inno Setup'
$candidates = @()
if ($InnoPath) { $candidates += $InnoPath }
$candidates += @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
)
$Iscc = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $Iscc) {
    $cmd = Get-Command iscc.exe -ErrorAction SilentlyContinue
    if ($cmd) { $Iscc = $cmd.Source }
}
if (-not $Iscc) {
    if ($InstallInno) {
        Write-Host 'نصب Inno Setup با winget ...' -ForegroundColor Yellow
        winget install -e --id JRSoftware.InnoSetup --accept-source-agreements --accept-package-agreements
        $candidates = @(
            "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
            "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
            "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
        )
        $Iscc = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    }
    if (-not $Iscc) {
        throw 'Inno Setup 6 پیدا نشد. از https://jrsoftware.org/isdl.php نصب کنید یا سوئیچ -InstallInno را بزنید.'
    }
}
Write-Host "ISCC: $Iscc" -ForegroundColor Green

# ---------------------------------------------------------------- 3. assets
Write-Step 'بررسی فایل های نصب کننده'
foreach ($file in @(
    'installer\umbrella.iss',
    'installer\wizard-image.bmp',
    'installer\wizard-small.bmp',
    'windows\runner\resources\app_icon.ico'
)) {
    $path = Join-Path $ProjectRoot $file
    if (-not (Test-Path $path)) { throw "فایل لازم برای نصب کننده نیست: $file" }
}
Write-Host 'فایل های نصب کننده کامل هستند.' -ForegroundColor Green

# ---------------------------------------------------------------- 4. compile
Write-Step 'کامپایل نصب کننده'
Push-Location (Join-Path $ProjectRoot 'installer')
try {
    & $Iscc "/Qp" "umbrella.iss"
    if ($LASTEXITCODE -ne 0) {
        throw "کامپایل نصب کننده ناموفق بود (کد $LASTEXITCODE)."
    }
} finally {
    Pop-Location
}

$SetupExe = Join-Path $ProjectRoot "installer\output\UmbrellaVPN-Setup-$Version-x64.exe"
if (-not (Test-Path $SetupExe)) {
    throw "فایل نصبی ساخته نشد: $SetupExe"
}
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
$FinalSetup = Join-Path $DistDir "UmbrellaVPN-Setup-$Version-x64.exe"
Copy-Item $SetupExe $FinalSetup -Force
$hash = (Get-FileHash $FinalSetup -Algorithm SHA256).Hash
$setupMb = [math]::Round((Get-Item $FinalSetup).Length / 1MB, 1)
"$hash  UmbrellaVPN-Setup-$Version-x64.exe" | Set-Content -Path (Join-Path $DistDir 'SHA256SUMS.txt') -Encoding ASCII
Write-Host ""
Write-Host "فایل نصبی آماده است: $FinalSetup ($setupMb مگابایت)" -ForegroundColor Green
Write-Host "SHA256: $hash" -ForegroundColor DarkGray

# ---------------------------------------------------------------- 5. portable
if ($Portable) {
    Write-Step 'ساخت نسخه قابل حمل'
    $portableDir = Join-Path $DistDir 'portable'
    if (Test-Path $portableDir) { Remove-Item $portableDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $portableDir | Out-Null
    Copy-Item "$ReleaseDir\*" $portableDir -Recurse -Force
    $coresDir = Join-Path $ProjectRoot 'cores'
    if (Test-Path $coresDir) {
        Copy-Item $coresDir (Join-Path $portableDir 'cores') -Recurse -Force
    }
    $zipPath = Join-Path $DistDir "UmbrellaVPN-$Version-x64-portable.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path (Join-Path $portableDir '*') -DestinationPath $zipPath
    Write-Host "نسخه قابل حمل: $zipPath" -ForegroundColor Green
}

Write-Host ""
Write-Host 'پایان.' -ForegroundColor Green
