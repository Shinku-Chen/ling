#requires -Version 5.1
<#
.SYNOPSIS
把合并后的 Lua 推到设备并立即运行：adb push dist\app.lua /miniapp/<id>.lua

.DESCRIPTION
设备侧把 /miniapp/<id>.lua 当虚拟入口（不需要文件系统），上传成功即启动并替换当前小应用。
注意：这会替换设备上正在运行的小应用；源码只在内存中，设备重启后消失，需要重新 push；
长按功能键 3 秒退出小应用。

.EXAMPLE
.\tools\upload.ps1 -Id timer                       # 只有一台设备时自动选择
.\tools\upload.ps1 -Id timer -Serial FFBBCCDDEE001124
.\tools\upload.ps1 -Id timer -SkipBuild
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Id,
    [string]$Script = 'dist\app.lua',
    [string]$Serial = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

if ($Id -notmatch '^[A-Za-z0-9_-]{1,121}$') {
    throw "应用 id 非法（1-121 位 ASCII 字母/数字/-/_）: $Id"
}

function Resolve-Adb {
    $local = Join-Path $root '.tools\platform-tools\adb.exe'
    if (Test-Path -LiteralPath $local) { return $local }
    $cmd = Get-Command 'adb' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$adb = Resolve-Adb
if (-not $adb) {
    throw '未找到 adb。装 Android Platform Tools，或解压到 .tools\platform-tools\；见 docs/development/environment-setup.md'
}

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'build.ps1') | Write-Host
}

$scriptPath = Join-Path $root $Script
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "找不到脚本: $scriptPath（先跑 tools\validate.ps1 或 tools\build.ps1）"
}

# 选设备：显式 -Serial 优先；只有一台时自动用；多台时要求指定
$online = @()
foreach ($line in (& $adb devices)) {
    if ($line -match '^(\S+)\s+device\s*$') { $online += $Matches[1] }
}
if ($online.Count -eq 0) {
    Write-Host '未检测到 adb 设备。检查：数据线是否支持传输、USB 口、设备是否已开机。'
    & $adb devices
    exit 1
}
if ($Serial -eq '') {
    if ($online.Count -eq 1) {
        $Serial = $online[0]
        Write-Host "[upload] 自动选择唯一设备: $Serial"
    } else {
        throw ("检测到多台设备，请用 -Serial 指定开发板。当前: " + ($online -join ', '))
    }
} elseif ($online -notcontains $Serial) {
    throw ("设备 $Serial 不在线。当前: " + ($online -join ', '))
}

$target = "/miniapp/$Id.lua"
Write-Host ("[upload] {0} -> {1}  (device {2})" -f $Script, $target, $Serial)
& $adb -s $Serial push $scriptPath $target
if ($LASTEXITCODE -ne 0) {
    throw "adb push 失败（退出码 $LASTEXITCODE）。语法/启动错误会从这里返回，旧实例会保留。"
}
Write-Host '[upload] 成功，应用立即运行（替换了设备上原来的小应用）。'
Write-Host '[upload] 长按功能键 3 秒退出；设备重启后需要重新 push。'
