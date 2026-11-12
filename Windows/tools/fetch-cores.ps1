#requires -version 5.1
<#
    گرفتن هسته های اتصال برای بسته بندی همراه فایل نصبی.

    این اسکریپت فقط روی ماشین سازنده اجرا می شود، نه روی رایانه کاربر. هسته ها
    در پوشه cores\bin کنار پروژه ذخیره می شوند و نصب کننده آن ها را در
    {app}\cores کنار فایل اجرایی برنامه می ریزد. خود برنامه هیچ چیزی دانلود
    نمی کند.

    مثال ها:
      powershell -ExecutionPolicy Bypass -File tools\fetch-cores.ps1
      powershell -ExecutionPolicy Bypass -File tools\fetch-cores.ps1 -Force
      powershell -ExecutionPolicy Bypass -File tools\fetch-cores.ps1 -Only xray,mieru
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
        $target = Join-Path $DestDir $core.binary
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
            Copy-Item $insidePath $target -Force
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
    throw ("هسته های الزامی گرفته نشد: " + ($failedRequired -join ', ') + " - ساخت فایل نصبی بدون آن ها کامل نیست.")
}
Write-Host 'همه هسته های الزامی در پوشه cores\bin آماده هستند.' -ForegroundColor Green
