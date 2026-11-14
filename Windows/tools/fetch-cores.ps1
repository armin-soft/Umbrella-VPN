#requires -version 5.1
<#
    گرفتن هسته اتصال (هسته هیدیفای) برای بسته بندی همراه فایل نصبی.

    این اسکریپت فقط روی ماشین سازنده اجرا می شود، نه روی رایانه کاربر. هسته در
    پوشه cores\hiddify کنار پروژه ذخیره می شود (فایل ها باید کنار هم بمانند) و
    نصب کننده آن ها را در {app}\cores\hiddify و دو فایل لازم را کنار خود برنامه
    می ریزد. خود برنامه هیچ چیزی دانلود نمی کند.

    نام فایل های هیدیفای هنگام گرفتن به نام های آمبرلا عوض می شود و فقط نام
    عوض می شود، نه محتوا.

    مثال ها:
      powershell -ExecutionPolicy Bypass -File tools\fetch-cores.ps1
      powershell -ExecutionPolicy Bypass -File tools\fetch-cores.ps1 -Force
      powershell -ExecutionPolicy Bypass -File tools\fetch-cores.ps1 -Only hiddify
#>
param(
    [switch]$Force,
    [string[]]$Only
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $ProjectRoot

$ManifestPath = Join-Path $ProjectRoot 'assets\cores\manifest.json'
$DestDir = Join-Path $ProjectRoot 'cores\bin'
New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

if (-not (Test-Path $ManifestPath)) {
    throw "فهرست هسته ها پیدا نشد: $ManifestPath"
}

$manifest = Get-Content $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$tempDir = Join-Path $env:TEMP ("umbrella-cores-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

$failedRequired = @()
$skipped = @()
$fetched = @()

try {
    foreach ($core in $manifest.cores) {
        if ($Only -and ($Only -notcontains $core.id)) { continue }
        # هسته هیدیفای چند فایل دارد و باید کنار هم بماند؛ برای همین در
        # پوشه خودش می رود و باینری اصلی از همان جا خوانده می شود.
        $target = if ($core.cli_prefix) {
            Join-Path (Join-Path $DestDir 'hiddify') $core.binary
        } else {
            Join-Path $DestDir $core.binary
        }
        if ((Test-Path $target) -and (-not $Force)) {
            Write-Host "  موجود است: $($core.binary)" -ForegroundColor DarkGray
            $fetched += $core.id
            continue
        }
        if ($null -ne $core.bundle -and -not $core.bundle) {
            Write-Host "  همراه نسخه عرضه نمی شود: $($core.id)" -ForegroundColor DarkGray
            $skipped += $core.id
            continue
        }
        if ([string]::IsNullOrWhiteSpace($core.url)) {
            Write-Host "  نشانی دانلود ندارد: $($core.id)" -ForegroundColor Yellow
            if ($core.required) { $failedRequired += $core.id } else { $skipped += $core.id }
            continue
        }
        Write-Host "  گرفتن $($core.title) ($($core.version)) ..." -ForegroundColor Cyan
        $archivePath = Join-Path $tempDir ("{0}.{1}" -f $core.id, $core.archive)
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $core.url -OutFile $archivePath -UseBasicParsing -TimeoutSec 300
        } catch {
            Write-Host "  دانلود ناموفق: $($core.id) - $($_.Exception.Message)" -ForegroundColor Yellow
            if ($core.required) { $failedRequired += $core.id } else { $skipped += $core.id }
            continue
        }

        $extractDir = Join-Path $tempDir $core.id
        New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
        $insidePath = ''
        $archiveType = if ([string]::IsNullOrWhiteSpace($core.archive)) { 'raw' } else { $core.archive.ToString().ToLower() }
        try {
            switch ($archiveType) {
                'zip' {
                    Expand-Archive -Path $archivePath -DestinationPath $extractDir -Force
                    if (-not [string]::IsNullOrWhiteSpace($core.inside)) {
                        $insidePath = Join-Path $extractDir ($core.inside -replace '/', '\')
                    }
                    if ([string]::IsNullOrWhiteSpace($insidePath) -or -not (Test-Path $insidePath)) {
                        # نام فایل در بسته ممکن است با فهرست فرق کند؛ همان نام
                        # باینری و بعد تنها فایل اجرایی بسته امتحان می شود.
                        $leaf = if ($insidePath) { Split-Path $insidePath -Leaf } else { $core.binary }
                        $match = Get-ChildItem -Path $extractDir -Recurse -Filter $leaf -ErrorAction SilentlyContinue |
                            Select-Object -First 1
                        if ($null -eq $match) {
                            $match = Get-ChildItem -Path $extractDir -Recurse -Filter $core.binary -ErrorAction SilentlyContinue |
                                Select-Object -First 1
                        }
                        if ($null -eq $match) {
                            $exes = @(Get-ChildItem -Path $extractDir -Recurse -Filter '*.exe' -ErrorAction SilentlyContinue)
                            if ($exes.Count -eq 1) { $match = $exes[0] }
                        }
                        if ($null -eq $match) { throw "فایل $($core.binary) در بسته پیدا نشد" }
                        $insidePath = $match.FullName
                    }
                }
                'msi' {
                    # از بسته ام اس آی فقط فایل اجرایی بیرون کشیده می شود.
                    $admin = Join-Path $extractDir 'admin'
                    $proc = Start-Process msiexec.exe -ArgumentList @(
                        '/a', "`"$archivePath`"", '/qn', "TARGETDIR=`"$admin`""
                    ) -Wait -PassThru
                    if ($proc.ExitCode -ne 0) { throw "msiexec با کد $($proc.ExitCode) تمام شد" }
                    $leaf = Split-Path $core.inside -Leaf
                    $found = Get-ChildItem -Path $admin -Recurse -Filter $leaf -ErrorAction SilentlyContinue |
                        Select-Object -First 1
                    if ($null -eq $found) { throw "فایل $leaf در بسته پیدا نشد" }
                    $insidePath = $found.FullName
                }
                'tgz' {
                    # بسته tar.gz هسته هیدیفای برای ویندوز (tar در ویندوز ۱۰ و
                    # ۱۱ خودش هست و ابزار بیرونی لازم نیست).
                    & tar.exe -xzf $archivePath -C $extractDir
                    if ($LASTEXITCODE -ne 0) { throw 'باز کردن بسته tar.gz ناموفق بود' }

                    # نام های هیدیفای با نام های برنامه عوض می شوند و فقط نام
                    # عوض می شود؛ خود فایل ها دست نمی خورند.
                    if ($core.cli_prefix) {
                        $renames = @(
                            @{ from = 'HiddifyCli.exe'; to = 'UmbrellaCli.exe' },
                            @{ from = 'hiddify-core.dll'; to = 'UmbrellaCore.dll' },
                            @{ from = 'HiddifyCoreEngine.exe'; to = 'UmbrellaCoreEngine.exe' },
                            @{ from = 'HiddifyAdmin.exe'; to = 'UmbrellaAdmin.exe' }
                        )
                        foreach ($item in $renames) {
                            Get-ChildItem -Path $extractDir -Recurse -Filter $item.from -ErrorAction SilentlyContinue |
                                ForEach-Object { Rename-Item -Path $_.FullName -NewName $item.to -Force }
                        }
                    }

                    # همه فایل های هسته (اجرایی و کتابخانه اش) کنار هم در
                    # cores\hiddify می مانند؛ جدایی شان هسته را می شکند.
                    $coreDir = Join-Path $DestDir 'hiddify'
                    New-Item -ItemType Directory -Force -Path $coreDir | Out-Null
                    Copy-Item (Join-Path $extractDir '*') $coreDir -Recurse -Force

                    $leaf = Split-Path $core.inside -Leaf
                    $match = Get-ChildItem -Path $coreDir -Recurse -Filter $leaf -ErrorAction SilentlyContinue |
                        Select-Object -First 1
                    if ($null -eq $match) { throw "فایل $leaf در بسته پیدا نشد" }
                    $insidePath = $match.FullName
                }
                default {
                    $insidePath = $archivePath
                }
            }
            if (-not (Test-Path $insidePath)) {
                throw "فایل $($core.inside) در بسته نیست"
            }
            if (-not [string]::IsNullOrWhiteSpace($core.sha256)) {
                $actual = (Get-FileHash $insidePath -Algorithm SHA256).Hash
                if ($actual -ne $core.sha256.ToUpperInvariant()) {
                    throw "هش فایل با فهرست نمی خواند ($actual)"
                }
            }
            # در بسته tar.gz فایل ها از قبل در جای خودشان (cores\hiddify)
            # هستند؛ کپی فایل روی خودش خطا می دهد و لازم نیست.
            if ([System.IO.Path]::GetFullPath($insidePath) -ne
                [System.IO.Path]::GetFullPath($target)) {
                Copy-Item $insidePath $target -Force
            }
            Write-Host "  آماده شد: $($core.binary)" -ForegroundColor Green
            $fetched += $core.id
        } catch {
            Write-Host "  پردازش ناموفق: $($core.id) - $($_.Exception.Message)" -ForegroundColor Yellow
            if ($core.required) { $failedRequired += $core.id } else { $skipped += $core.id }
        } finally {
            Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $archivePath -Force -ErrorAction SilentlyContinue
        }
    }
} finally {
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("هسته های آماده: " + ($(if ($fetched) { $fetched -join ', ' } else { 'هیچ کدام' }))) -ForegroundColor Cyan
if ($skipped) {
    Write-Host ("هسته های اختیاری که گرفته نشد: " + ($skipped -join ', ')) -ForegroundColor Yellow
}
if ($failedRequired) {
    Write-Host ("هسته های الزامی گرفته نشد: " + ($failedRequired -join ', ')) -ForegroundColor Red
    exit 1
}
Write-Host 'هسته هیدیفای در پوشه cores\hiddify آماده است.' -ForegroundColor Green
exit 0
