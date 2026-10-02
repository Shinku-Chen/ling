#requires -Version 5.1
<#
.SYNOPSIS
拉取设备上当前运行的小应用源码：adb pull /miniapp/miniapp.lua

.DESCRIPTION
设备保留活动应用的源码快照（最多一个源码上限大小），可用来找回在真机上改过、但没同步回仓库的版本。
没有小应用运行时拉取会失败。拉取是只读操作，不影响设备上正在运行的应用。

.EXAMPLE
.\tools\pull.ps1
.\tools\pull.ps1 -Serial <serial> -Out dist\timer
#>
[CmdletBinding()]
param(
    [string]$Out = 'dist\device-app.lua',
    [string]$Serial = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Resolve-Adb {
    $local = Join-Path $root '.tools\platform-tools\adb.exe'
    if (Test-Path -LiteralPath $local) { return $local }
    $cmd = Get-Command 'adb' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$adb = Resolve-Adb
if (-not $adb) {
    throw '未找到 adb。见 docs/development/environment-setup.md'
}

$online = @()
foreach ($line in (& $adb devices)) {
    if ($line -match '^(\S+)\s+device\s*$') { $online += $Matches[1] }
}
if ($online.Count -eq 0) {
    throw '未检测到 adb 设备'
}
if ($Serial -eq '') {
    if ($online.Count -eq 1) {
        $Serial = $online[0]
        Write-Host "[pull] 自动选择唯一设备: $Serial"
    } else {
        throw ("检测到多台设备，请用 -Serial 指定开发板。当前: " + ($online -join ', '))
    }
} elseif ($online -notcontains $Serial) {
    throw ("设备 $Serial 不在线。当前: " + ($online -join ', '))
}

$outPath = Join-Path $root $Out
$dir = Split-Path -Parent $outPath
if (-not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

Write-Host "[pull] /miniapp/miniapp.lua -> $Out  (device $Serial)"
& $adb -s $Serial pull /miniapp/miniapp.lua $outPath
if ($LASTEXITCODE -ne 0) {
    throw "adb pull 失败（退出码 $LASTEXITCODE）。没有小应用在运行时无法拉取。"
}
if (-not (Test-Path -LiteralPath $outPath)) {
    throw 'adb pull 报告成功但没有产出文件'
}
Write-Host '[pull] 完成。这是快照，仓库里的 src/ 仍是开发主本。'
