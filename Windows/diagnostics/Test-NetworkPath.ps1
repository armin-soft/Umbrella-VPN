# Read-only network evidence on the actual Windows machine. No firewall, DNS,
# routes, adapter settings, account data or subscription sources are modified.
[CmdletBinding()]
param(
    [ValidateSet('disconnected', 'tun', 'proxy')]
    [string]$Mode = 'tun',
    [ValidateRange(1, 65535)]
    [int]$ProxyPort = 12334,
    [string]$OutputDirectory = (Join-Path $env:USERPROFILE 'Desktop\Umbrella-Network-Audit')
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Run this diagnostic on Windows.' }
$curl = Join-Path $env:SystemRoot 'System32\curl.exe'
if (-not (Test-Path $curl)) { throw 'The Windows curl.exe is required.' }
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

function Get-Trace([bool]$ViaProxy) {
    $arguments = @('--silent', '--show-error', '--fail', '--max-time', '15', '--connect-timeout', '8')
    if ($ViaProxy) {
        # Never allow a proxy failure to fall back to a direct connection.
        $arguments += @('--proxy', "http://127.0.0.1:$ProxyPort", '--noproxy', 'not-a-host.invalid')
    } else {
        # DIRECT sockets still traverse Windows TUN routes in tunnel mode.
        $arguments += @('--noproxy', '*')
    }
    $arguments += 'https://www.cloudflare.com/cdn-cgi/trace'
    try {
        $raw = @(& $curl @arguments 2>&1)
        $code = $LASTEXITCODE
    } catch { return @{ ok = $false; error = 'HTTPS trace request failed' } }
    if ($code -ne 0) { return @{ ok = $false; exitCode = $code } }
    $values = @{}
    foreach ($line in $raw) {
        if ("$line" -match '^(ip|warp|loc|http)=(.*)$') { $values[$Matches[1]] = $Matches[2] }
    }
    return @{ ok = [bool]$values['ip']; values = $values }
}

$system = Get-Trace $false
$proxy = if ($Mode -eq 'disconnected') { $null } else { Get-Trace $true }
$report = [ordered]@{
    timestamp = (Get-Date).ToUniversalTime().ToString('o')
    mode = $Mode
    systemPath = $system
    proxyPath = $proxy
    sameExit = if ($proxy -and $proxy.ok -and $system.ok) { $proxy['values']['ip'] -eq $system['values']['ip'] } else { $null }
    dnsLeakVerdict = 'NOT_TESTED: requires DNS query/packet evidence; HTTPS/IP comparison is not a DNS leak test.'
    adapters = @(Get-NetAdapter | Select-Object Name, InterfaceDescription, Status, ifIndex)
    dnsServers = @(Get-DnsClientServerAddress | Where-Object { $_.ServerAddresses.Count -gt 0 } | Select-Object InterfaceAlias, InterfaceIndex, AddressFamily, ServerAddresses)
    routes = @(Get-NetRoute | Where-Object { $_.DestinationPrefix -in @('0.0.0.0/0', '0.0.0.0/1', '128.0.0.0/1', '::/0', '::/1', '8000::/1') } | Select-Object DestinationPrefix, InterfaceAlias, NextHop, RouteMetric)
}
$file = Join-Path $OutputDirectory ("network-{0}-{1}.json" -f $Mode, (Get-Date -Format 'yyyyMMdd-HHmmss'))
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $file -Encoding UTF8
Write-Output "Saved: $file"
Write-Output 'This file includes IP addresses and adapter names. Review it before sharing.'
Write-Output 'A successful HTTPS request is not proof of zero DNS/IPv6 leaks or a working kill switch.'
