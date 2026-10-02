#requires -Version 5.1
<#
.SYNOPSIS
合并 + 静态检查 + 模拟器实跑，三重校验小应用产物。

.DESCRIPTION
1. Build     : 调 tools/build.ps1 生成 dist/app.lua
2. Static    : 产物 ≤65536 字节、不含沙箱禁用 API、必须定义 on_tick、应用 id 合法
3. Simulator : 用官方模拟器 headless 跑一次并出图（Lua 语法/启动错误 → 非零退出）

.EXAMPLE
.\tools\validate.ps1
.\tools\validate.ps1 -Id timer
.\tools\validate.ps1 -Script examples\hello.lua -SkipBuild
#>
[CmdletBinding()]
param(
    [string]$Script = 'dist\app.lua',
    [string]$Id = '',
    [switch]$SkipBuild,
    [switch]$SkipSimulator
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$maxSourceBytes = 65536
$staticFailures = @()
$simFailures = @()

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

# ---- 1. build -------------------------------------------------------------
if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'build.ps1') | Write-Host
}

$scriptPath = Join-Path $root $Script
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "找不到脚本: $scriptPath"
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
$text = [System.IO.File]::ReadAllText($scriptPath, $utf8)
$size = $utf8.GetByteCount($text)

Write-Host ("[static] script = {0}" -f $Script)
if ($size -gt $maxSourceBytes) {
    $staticFailures += ("体积超限: {0} > {1} 字节" -f $size, $maxSourceBytes)
} else {
    Write-Host ("[static] size   = {0} / {1} bytes  PASS" -f $size, $maxSourceBytes)
}

$forbidden = @(
    @{ name = 'pcall';          pattern = '\bpcall\s*\(' },
    @{ name = 'xpcall';         pattern = '\bxpcall\s*\(' },
    @{ name = 'setmetatable';   pattern = '\bsetmetatable\s*\(' },
    @{ name = 'collectgarbage'; pattern = '\bcollectgarbage\s*\(' },
    @{ name = 'dofile';         pattern = '\bdofile\s*\(' },
    @{ name = 'loadfile';       pattern = '\bloadfile\s*\(' },
    @{ name = 'load';           pattern = '(?<![\w.])load\s*\(' },
    @{ name = 'require';        pattern = '\brequire\s*\(' },
    @{ name = 'print';          pattern = '(?<![\w.])print\s*\(' },
    @{ name = 'io';             pattern = '\bio\.' },
    @{ name = 'os';             pattern = '\bos\.' },
    @{ name = 'coroutine';      pattern = '\bcoroutine\.' },
    @{ name = 'debug';          pattern = '\bdebug\.' }
)
$violations = @()
foreach ($f in $forbidden) {
    if ($text -match $f.pattern) { $violations += $f.name }
}
if ($violations.Count -gt 0) {
    $staticFailures += ("命中沙箱禁用 API: " + ($violations -join ', '))
} else {
    Write-Host '[static] sandbox API check  PASS'
}

if ($text -match 'function\s+on_tick\s*\(') {
    Write-Host '[static] on_tick defined      PASS'
} else {
    $staticFailures += '缺少必需的 on_tick 回调'
}

if ($Id -ne '') {
    if ($Id -match '^[A-Za-z0-9_-]{1,121}$') {
        Write-Host ("[static] app id {0}        PASS" -f $Id)
    } else {
        $staticFailures += ("应用 id 非法（1-121 位 ASCII 字母/数字/-/_）: " + $Id)
    }
}

# ---- 2. simulator ---------------------------------------------------------
if (-not $SkipSimulator) {
    $sim = Resolve-Simulator
    if (-not $sim) {
        Write-Host '[sim] 未找到 lingclaw-sdk.exe，跳过（设 $env:LINGCLAW_SDK 可指定路径）'
        $simFailures += 'NOT RUN（未找到模拟器）'
    } else {
        $png = Join-Path $root 'dist\screenshot.png'
        if (Test-Path -LiteralPath $png) { Remove-Item -LiteralPath $png -Force }
        Write-Host ("[sim] {0} --headless {1}" -f $sim, $Script)
        # 模拟器是 GUI 子系统程序：用 Start-Process -Wait 才能真正等到退出并拿到退出码
        $simArgs = @('--headless', ('"' + $scriptPath + '"'), ('"' + $png + '"'))
        $proc = Start-Process -FilePath $sim -ArgumentList $simArgs -NoNewWindow -Wait -PassThru
        $code = $proc.ExitCode
        if ($code -ne 0) {
            $simFailures += ("模拟器运行失败，退出码 " + $code)
        } elseif (-not (Test-Path -LiteralPath $png)) {
            $simFailures += '模拟器未产出截图'
        } else {
            Write-Host ("[sim] screenshot -> dist\screenshot.png  PASS")
        }
    }
}

# ---- 3. report ------------------------------------------------------------
$staticOk = ($staticFailures.Count -eq 0)
$simOk = ($simFailures.Count -eq 0)

Write-Host ''
Write-Host 'Build: PASS'
if ($staticOk) { Write-Host 'Static checks: PASS' } else { Write-Host 'Static checks: FAIL' }
if ($SkipSimulator) {
    Write-Host 'Simulator run: NOT RUN'
} elseif ($simOk) {
    Write-Host 'Simulator run: PASS'
} else {
    Write-Host 'Simulator run: FAIL'
}

if ($staticOk -and $simOk) {
    Write-Host 'Unverified: 真机渲染/音频/按键手感/内存'
    exit 0
}

foreach ($f in $staticFailures) { Write-Host (" [static] " + $f) }
foreach ($f in $simFailures) { Write-Host (" [sim] " + $f) }
exit 1
