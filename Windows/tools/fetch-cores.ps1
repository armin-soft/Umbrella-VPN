#requires -version 5.1
<#
    گرفتن هسته اتصال (هسته هیدیفای) برای بسته بندی همراه فایل نصبی.

    این اسکریپت فقط روی ماشین سازنده اجرا می شود، نه روی رایانه کاربر. کتابخانه
    موتور و کرونتش در پوشه cores\umbrella کنار پروژه ذخیره می شوند و نصب کننده
    همان ها را در {app}\cores\umbrella می ریزد. خود برنامه هیچ چیزی دانلود نمی کند.

    از بسته رسمی موتور فقط hiddify-core.dll و libcronet.dll برداشته می شود؛
    نامشان عوض نمی شود (نام کتابخانه داخل خودش ثبت است). فایل های اجرایی
    هیدیفای کنار گذاشته می شوند و جایش، لانچرهای آمبرلا در ساخت برنامه ساخته
    می شوند (نگاه کنید به native/umbrella_launcher.c).

    مثال ها:
      powershell -ExecutionPolicy Bypass -File tools\fetch-cores.ps1
      powershell -ExecutionPolicy Bypass -File tools\fetch-cores.ps1 -Force
      powershell -ExecutionPolicy Bypass -File tools\fetch-cores.ps1 -Only hiddify  # شناسه هسته در فهرست
#>
param(
    [switch]$Force,
    [string[]]$Only
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $ProjectRoot

$ManifestPath = Join-Path $ProjectRoot 'assets\cores\manifest.json'
# هسته هیدیفای چند فایل دارد و کتابخانه اش باید کنار فایل اجرایی اش بماند، پس
# در پوشه خودش می رود. نام پوشه را نصب کننده و بررسی CI هم انتظار دارند.
$CoresRoot = Join-Path $ProjectRoot 'cores'
$HiddifyDir = Join-Path $CoresRoot 'umbrella'
$DestDir = Join-Path $CoresRoot 'bin'
New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

if (-not (Test-Path $ManifestPath)) {
    throw "فهرست هسته ها پیدا نشد: $ManifestPath"
}

$manifest = Get-Content $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$tempDir = Join-Path $env:TEMP ("umbrella-cores-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

# پوشه هسته پیش از هر کاری ساخته می شود تا کپی فایل ها به مسیر ناموجود نخورد.
New-Item -ItemType Directory -Force -Path $HiddifyDir | Out-Null

$failedRequired = @()
$skipped = @()
$fetched = @()

try {
    foreach ($core in $manifest.cores) {
        if ($Only -and ($Only -notcontains $core.id)) { continue }
        # هسته هیدیفای چند فایل دارد و باید کنار هم بماند؛ برای همین در
        # پوشه خودش می رود و باینری اصلی از همان جا خوانده می شود.
        $target = if ($core.cli_prefix) {
            Join-Path $HiddifyDir $core.inside
        } else {
            Join-Path $DestDir $core.binary
        }
        if ((Test-Path $target) -and (-not $Force)) {
            Write-Host "  موجود است: $(Split-Path $target -Leaf)" -ForegroundColor DarkGray
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
                    # بسته tar.gz موتور هسته برای ویندوز (tar در ویندوز ۱۰ و
                    # ۱۱ خودش هست و ابزار بیرونی لازم نیست).
                    & tar.exe -xzf $archivePath -C $extractDir
                    if ($LASTEXITCODE -ne 0) { throw 'باز کردن بسته tar.gz ناموفق بود' }

                    # فقط این فایل ها از بسته می مانند:
                    #
                    #   hiddify-core.dll  — خود موتور. نامش عوض نمی شود چون
                    #                       نام کتابخانه هم داخل خودش و هم در
                    #                       وابستگی هایش ثبت است؛ برنامه آن را
                    #                       با همین نام در همین پوشه بار می کند.
                    #   libcronet.dll     — وابسته موتور.
                    #
                    # فایل های اجرایی همراه بسته کنار گذاشته می شوند: آن ها
                    # کتابخانه را با پیوند نام صدا می زنند و همین کار باعث خطای
                    # 0xC0000135 در ۱٫۰٫۲ شد. لانچرهای آمبرلا به جایش با نام و
                    # آیکون خودمان و با بار کردن مسیر کتابخانه ساخته می شوند.
                    $required = @('hiddify-core.dll', 'libcronet.dll')
                    foreach ($name in $required) {
                        $file = Get-ChildItem -Path $extractDir -Recurse -Filter $name -ErrorAction SilentlyContinue |
                            Select-Object -First 1
                        if ($null -eq $file) { throw "فایل $name در بسته هسته پیدا نشد" }
                        if (-not (Test-Path $HiddifyDir)) {
                            New-Item -ItemType Directory -Force -Path $HiddifyDir | Out-Null
                        }
                        $destination = Join-Path $HiddifyDir $name
                        if ([System.IO.Path]::GetFullPath($file.FullName) -ne
                            [System.IO.Path]::GetFullPath($destination)) {
                            Copy-Item $file.FullName $destination -Force
                        }
                        Write-Host "  هسته: $name" -ForegroundColor DarkGray
                    }
                    $insidePath = Join-Path $HiddifyDir $core.inside
                    if (-not (Test-Path $insidePath)) { throw "فایل $($core.inside) در بسته پیدا نشد" }
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
            # در بسته tar.gz فایل ها از قبل در جای خودشان (cores\umbrella)
            # هستند؛ کپی فایل روی خودش خطا می دهد و لازم نیست.
            if ([System.IO.Path]::GetFullPath($insidePath) -ne
                [System.IO.Path]::GetFullPath($target)) {
                Copy-Item $insidePath $target -Force
            }
            Write-Host "  آماده شد: $($core.inside)" -ForegroundColor Green
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
Write-Host 'موتور هسته در پوشه cores\umbrella آماده است؛ فایل های اجرایی آمبرلا در ساخت برنامه ساخته می شوند.' -ForegroundColor Green
exit 0
