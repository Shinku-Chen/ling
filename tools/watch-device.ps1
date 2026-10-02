#requires -Version 5.1
<#
.SYNOPSIS
持续记录开发板的在线状态与 ADB shell 应答情况——用来区分"休眠""USB 掉线""传输通道故障"。

.DESCRIPTION
每轮做两件事：
  1. 设备是否出现在 adb 列表里（按 -Serial 或自动识别 model:listenai）
  2. shell 是否应答（8 秒超时，区分"列出但不应答"）
只在状态变化时记录，避免刷屏。诊断依据见 docs/reference/device-behavior-log.md。

.EXAMPLE
.\tools\watch-device.ps1 -Minutes 5
.\tools\watch-device.ps1 -Serial BOOT-xxxxxxxx -Minutes 2
#>
[CmdletBinding()]
param(
    [string]$Serial = '',
    [int]$Minutes = 10,
    [int]$IntervalSeconds = 10,
    [string]$Log = 'dist\device-watch.log'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Resolve-Adb {
    $local = Join-Path $root '.tools\platform-tools\adb.exe'
    if (Test-Path -LiteralPath $local) { return $local }
    $cmd = Get-Command 'adb' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw '未找到 adb：见 docs/development/flash-and-recovery.md'
}

$adb = Resolve-Adb
$logPath = Join-Path $root $Log
$dir = Split-Path -Parent $logPath
if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$tmp = Join-Path $dir '_watch-out.txt'

function Write-Log([string]$m) {
    ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) | Out-File -FilePath $logPath -Append -Encoding ascii
}

function Get-Devices {
    $lines = @(& $adb devices -l 2>$null | ForEach-Object { ([string]$_) -replace "`r|`0", '' })
    $out = @()
    foreach ($l in $lines) {
        if ($l -match '^(\S+)\s+device') { $out += [pscustomobject]@{ Serial = $Matches[1]; Line = $l } }
    }
    return $out
}

function Get-Target([string]$want) {
    $devs = @(Get-Devices)
    if ($want -ne '') { return ($devs | Where-Object { $_.Serial -eq $want } | Select-Object -First 1) }
    return ($devs | Where-Object { $_.Line -match 'model:listenai' } | Select-Object -First 1)
}

function Probe-Shell([string]$serial) {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    try {
        $p = Start-Process -FilePath $adb -ArgumentList @('-s', $serial, 'shell', 'version') -NoNewWindow -PassThru `
             -RedirectStandardOutput $tmp -RedirectStandardError ($tmp + '.err')
    } catch { return 'SPAWN_FAIL' }
    if (-not $p.WaitForExit(8000)) { try { $p.Kill() } catch {}; return 'TIMEOUT(>8s)' }
    $out = ''
    if (Test-Path -LiteralPath $tmp) { $out = (Get-Content -LiteralPath $tmp -Raw) }
    $out = ($out -replace "`r|`n|`0", '').Trim()
    if ($out -eq '') { return ('EMPTY(exit=' + $p.ExitCode + ')') }
    return $out
}

Write-Log ('watch started (条数上限 ' + [int]($Minutes * 60 / [Math]::Max($IntervalSeconds,1)) + ' 轮)')
$deadline = (Get-Date).AddMinutes($Minutes)
$prev = ''
while ((Get-Date) -lt $deadline) {
    $line = 'absent'
    $t = Get-Target $Serial
    if ($t) {
        $v = Probe-Shell $t.Serial
        $line = 'online(shell=' + $v + ')'
    }
    if ($line -ne $prev) { Write-Log ("state -> " + $line); $prev = $line }
    Start-Sleep -Seconds $IntervalSeconds
}
Write-Log 'watch exit'
Write-Host ("日志: " + $Log)
