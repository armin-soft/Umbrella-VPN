#requires -version 5.1
<#
    گرفتن هسته اتصال (هسته هیدیفای) برای بسته بندی همراه فایل نصبی.

    این اسکریپت فقط روی ماشین سازنده اجرا می شود، نه روی رایانه کاربر. کتابخانه
    موتور و کرونتش در پوشه cores\umbrella کنار پروژه ذخیره می شوند و نصب کننده
    همان ها را در {app}\cores\umbrella می ریزد. خود برنامه هیچ چیزی دانلود نمی کند.

    از بسته رسمی موتور فقط کتابخانه موتور و libcronet.dll برداشته می شود و
    کتابخانه با نام UmbrellaCore.dll ذخیره می شود، تا در Explorer هم نامی جز
    آمبرلا دیده نشود. این کار فقط چون لانچر خودمان کتابخانه را با مسیر بار می
    کند بی خطر است. فایل های اجرایی همراه بسته کنار گذاشته می شوند و جایش،
    لانچرهای آمبرلا در ساخت برنامه ساخته می شوند (native/umbrella_launcher.c).

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
$CoreDir = Join-Path $CoresRoot 'umbrella'
$DestDir = Join-Path $CoresRoot 'bin'
New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

if (-not (Test-Path $ManifestPath)) {
    throw "فهرست هسته ها پیدا نشد: $ManifestPath"
}

$manifest = Get-Content $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$tempDir = Join-Path $env:TEMP ("umbrella-cores-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

# پوشه هسته پیش از هر کاری ساخته می شود تا کپی فایل ها به مسیر ناموجود نخورد.
New-Item -ItemType Directory -Force -Path $CoreDir | Out-Null

$failedRequired = @()
$skipped = @()
$fetched = @()

try {
    foreach ($core in $manifest.cores) {
        if ($Only -and ($Only -notcontains $core.id)) { continue }
        # موتور هسته چند فایل دارد و باید کنار هم بماند؛ برای همین در پوشه
        # خودش می رود و کتابخانه اصلی از همان جا خوانده می شود.
        $target = if ($core.cli_prefix) {
            Join-Path $CoreDir $core.inside
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

                    # فقط این فایل ها از بسته می مانند، با نام آمبرلا:
                    #
                    #   hiddify-core.dll → UmbrellaCore.dll   خود موتور
                    #   libcronet.dll                         وابسته موتور
                    #
                    # تغییر نام الان بی خطر است چون لانچر آمبرلا کتابخانه را با
                    # «مسیر» بار می کند، نه با پیوند نام (همان وابستگی پیوندی
                    # باعث خطای 0xC0000135 در ۱٫۰٫۲ شده بود). فایل های اجرایی
                    # همراه بسته کنار گذاشته می شوند و جایش لانچرهای خودمان در
                    # ساخت برنامه ساخته می شوند.
                    $required = @(
                        @{ from = 'hiddify-core.dll'; to = 'UmbrellaCore.dll' },
                        @{ from = 'libcronet.dll'; to = 'libcronet.dll' }
                    )
                    foreach ($item in $required) {
                        $file = Get-ChildItem -Path $extractDir -Recurse -Filter $item.from -ErrorAction SilentlyContinue |
                            Select-Object -First 1
                        if ($null -eq $file) { throw "فایل $($item.from) در بسته هسته پیدا نشد" }
                        $destination = Join-Path $CoreDir $item.to
                        if ([System.IO.Path]::GetFullPath($file.FullName) -ne
                            [System.IO.Path]::GetFullPath($destination)) {
                            Copy-Item $file.FullName $destination -Force
                        }
                        Write-Host "  هسته: $($item.to)" -ForegroundColor DarkGray
                    }
                    $insidePath = Join-Path $CoreDir $core.inside
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
