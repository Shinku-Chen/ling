#requires -Version 5.1
<#
.SYNOPSIS
通过 ADB recovery 把一个镜像写到指定分区地址（复刻 adb_download.ps1 的核心动作）。

.DESCRIPTION
设备必须已经在 recovery 模式（adb 里表现为 BOOT-*）。流程：
  push <image> /RAW/NAND/<addr>  →  recovery exit（部分版本无此命令，忽略）  →  reboot hard
远端路径 = /RAW/NAND/ + 地址去掉 0x 与前置零（0x600000 → 600000）。
推送完成后会比对字节数，不一致视为失败。

.EXAMPLE
.\tools\flash-recovery.ps1 -Image D:\fw\arcs-mini.bin                 # app 分区（默认 0x600000）
.\tools\flash-recovery.ps1 -Image D:\fw\ap.bin -Address 0x040000
.\tools\flash-recovery.ps1 -Image D:\fw\app.bin -NoReboot
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Image,
    [string]$Address = '0x600000',
    [string]$Serial = '',
    [switch]$NoReboot
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$imagePath = if ([System.IO.Path]::IsPathRooted($Image)) { $Image } else { Join-Path $root $Image }
if (-not (Test-Path -LiteralPath $imagePath)) { throw "找不到镜像: $imagePath" }
$size = (Get-Item -LiteralPath $imagePath).Length

$addr = $Address.ToLower().TrimStart('0').TrimStart('x')
$remote = '/RAW/NAND/' + $addr

function Resolve-Adb {
    $local = Join-Path $root '.tools\platform-tools\adb.exe'
    if (Test-Path -LiteralPath $local) { return $local }
    $cmd = Get-Command 'adb' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw '未找到 adb'
}

$adb = Resolve-Adb

# 选 recovery 设备：BOOT-* 优先；也可用 -Serial 明确指定
$devs = @(& $adb devices | ForEach-Object { ([string]$_) -replace "`r|`0", '' } |
          Where-Object { $_ -match '^(\S+)\s+device' } | ForEach-Object { $Matches[1] })
if ($Serial -ne '') {
    if ($devs -notcontains $Serial) { throw "设备 $Serial 不在线。当前: $($devs -join ', ')" }
    $target = $Serial
} else {
    $boot = @($devs | Where-Object { $_ -like 'BOOT-*' })
    if ($boot.Count -ne 1) {
        throw "需要且只能有一台 recovery 设备（BOOT-*），当前: $($devs -join ', ')。请按住功能键 + 短按 RST 进入 recovery，或用 -Serial 指定。"
    }
    $target = $boot[0]
}

Write-Host ("[flash] {0} -> {1}  ({2} bytes)  device={3}" -f $Image, $remote, $size, $target)
$sw = [Diagnostics.Stopwatch]::StartNew()
& $adb -s $target push $imagePath $remote
$sw.Stop()
if ($LASTEXITCODE -ne 0) { throw "push 失败（退出码 $LASTEXITCODE）" }
Write-Host ("[flash] push 耗时 {0:N1}s（recovery 约 0.1 MB/s，属正常）" -f $sw.Elapsed.TotalSeconds)

if (-not $NoReboot) {
    & $adb -s $target shell recovery exit 2>&1 | Out-Null   # 部分版本返回 Command not Found，忽略
    & $adb -s $target shell reboot hard   2>&1 | Out-Null
    Write-Host '[flash] 已发送重启；约 20 秒后用 adb shell version 验证版本'
}
