#requires -Version 5.1
<#
.SYNOPSIS
用官方模拟器 headless 执行脚本并出图（不弹窗口）。

.DESCRIPTION
执行"启动阶段 + 50 次 tick"后截图，不等待网络请求完成。
Lua 语法或启动错误会让模拟器返回非零退出码 —— 可以直接当 CI 闸门。

.EXAMPLE
.\tools\screenshot.ps1
.\tools\screenshot.ps1 -Script examples\hello.lua -Out dist\hello.png
.\tools\screenshot.ps1 -Capabilities my-device.json
#>
[CmdletBinding()]
param(
    [string]$Script = 'dist\app.lua',
    [string]$Out = 'dist\screenshot.png',
    [string]$Capabilities = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Resolve-Simulator {
    if ($env:LINGCLAW_SDK -and (Test-Path -LiteralPath $env:LINGCLAW_SDK)) {
        return $env:LINGCLAW_SDK
    }
    $fallback = 'D:\Git-Workspace\LingClaw-SDK-0.1.0-windows-x64\lingclaw-sdk.exe'
    if (Test-Path -LiteralPath $fallback) {
        return $fallback
    }
    $cmd = Get-Command 'lingclaw-sdk.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$sim = Resolve-Simulator
if (-not $sim) {
    throw '未找到 lingclaw-sdk.exe：设 $env:LINGCLAW_SDK，或放到默认路径。见 docs/development/environment-setup.md'
}

$scriptPath = Join-Path $root $Script
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "找不到脚本: $scriptPath"
}
$outPath = Join-Path $root $Out
$dir = Split-Path -Parent $outPath
if (-not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

if ($Capabilities -ne '') {
    $capPath = Join-Path $root $Capabilities
    if (-not (Test-Path -LiteralPath $capPath)) {
        throw "找不到 capabilities 文件: $capPath"
    }
    $simArgs = @('--headless', ('"' + $scriptPath + '"'), ('"' + $outPath + '"'), ('"' + $capPath + '"'))
} else {
    $simArgs = @('--headless', ('"' + $scriptPath + '"'), ('"' + $outPath + '"'))
}

# 模拟器是 GUI 子系统程序：& 不会等待、也拿不到退出码，必须用 Start-Process -Wait
$proc = Start-Process -FilePath $sim -ArgumentList $simArgs -NoNewWindow -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    throw "模拟器执行失败（退出码 $($proc.ExitCode)）"
}
if (-not (Test-Path -LiteralPath $outPath)) {
    throw '模拟器没有产出截图'
}
Write-Host "[screenshot] $Out  OK"
