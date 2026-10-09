#requires -Version 5.1
<#
.SYNOPSIS
抓真机截图：分块调用 `adb shell shot` → 拼接 hex → 生成 BMP。

.DESCRIPTION
设备固件需开启 CONFIG_SHOT（apps/arcs-mini/shot/）。协议：
    adb shell shot                  → 抓帧并返回头行 "SHOT <w> <h> RGB565 <bytes>"
    adb shell shot <start> <len>    → 返回该区间 hex，末尾 "SHOTPART <start> <len>"
为什么分块：一次性打印 230KB hex 会被 ADB shell 输出缓冲截断（实测只到 980 字节）。

.EXAMPLE
.\tools\screenshot-device.ps1
.\tools\screenshot-device.ps1 -ChunkBytes 512 -Out dist\device.bmp
#>
[CmdletBinding()]
param(
    [string]$Serial = '',
    [string]$Out = 'dist\device.bmp',
    [int]$ChunkBytes = 256
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Resolve-Adb {
    $local = Join-Path $root '.tools\platform-tools\adb.exe'
    if (Test-Path -LiteralPath $local) { return $local }
    $cmd = Get-Command 'adb' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw '未找到 adb'
}

$adb = Resolve-Adb
if ($Serial -eq '') {
    $lines = @(& $adb devices -l 2>$null | ForEach-Object { ([string]$_) -replace "`r|`0", '' })
    $board = $lines | Where-Object { $_ -match '^(\S+)\s+device' -and $_ -match 'model:listenai' } | Select-Object -First 1
    if (-not $board) { throw '未找到开发板（adb devices 里没有 model:listenai 的设备）' }
    $Serial = ($board -split '\s+')[0]
}
Write-Host "[shot] device = $Serial"

# 1) 抓帧 + 头行
$head = & $adb -s $Serial shell shot 2>&1
$w = 0; $h = 0; $total = 0
foreach ($line in $head) {
    $t = ([string]$line) -replace "`r|`0", ''
    if ($t -match 'SHOT (\d+) (\d+) RGB565 (\d+)') {
        $w = [int]$Matches[1]; $h = [int]$Matches[2]; $total = [int]$Matches[3]
        break
    }
}
if ($total -le 0) { throw ("未能解析头行，shot 命令是否已烧入？输出：`n" + ($head -join "`n")) }
Write-Host ("[shot] header: {0}x{1} RGB565 {2} 字节（分块 {3} 字节）" -f $w, $h, $total, $ChunkBytes)

# 2) 分块拉取
$data = [byte[]]::new($total)
$filled = 0
$start = 0
$attempts = 0
while ($start -lt $total) {
    $len = [Math]::Min($ChunkBytes, $total - $start)
    $resp = & $adb -s $Serial shell shot $start $len 2>&1
    $hex = New-Object System.Text.StringBuilder
    $ok = $false
    foreach ($line in $resp) {
        $t = ([string]$line) -replace "`r|`0", ''
        if ($t -match 'SHOTPART (\d+) (\d+)') {
            $ok = ([int]$Matches[1] -eq $start) -and ([int]$Matches[2] -eq $len)
            break
        }
        foreach ($chunk in ($t -split '\s+')) {
            if ($hex.Length -ge $len * 2) { break }
            if ($chunk -match '^[0-9a-fA-F]+$' -and $chunk.Length % 2 -eq 0) { [void]$hex.Append($chunk) }
        }
        if ($hex.Length -ge $len * 2) { break }
    }
    $got = [Math]::Min($hex.Length / 2, $len)   # 多余字节截断（流可能粘连）
    if ($got -lt $len) {
        # 丢字节：先降块重试，再对同一块重试若干次（串口/ADB 输出偶发丢包）
        $attempts++
        if ($ChunkBytes -gt 256) {
            Write-Host ("[shot] 第 {0} 块不完整（{1}/{2}），改用 256 字节块重试" -f $start, $got, $len)
            $ChunkBytes = 256
            continue
        }
        if ($attempts -le 6) {
            Write-Host ("[shot] 第 {0} 块重试 #{1}（上轮 {2}/{3}）" -f $start, $attempts, $got, $len)
            continue
        }
        throw ("第 {0} 块拉取不完整（重试 {1} 次仍为 {2}/{3}）" -f $start, $attempts, $got, $len)
    }
    $attempts = 0
    for ($i = 0; $i -lt $len; $i++) {
        $data[$start + $i] = [Convert]::ToByte($hex.ToString().Substring($i * 2, 2), 16)
    }
    $filled += $len
    $start += $len
    if (($start % 8192) -eq 0) { Write-Host ("[shot] {0}/{1} 字节" -f $filled, $total) }
}
Write-Host ("[shot] 拉取完成 {0} 字节" -f $filled)

# 3) RGB565 → 24bit BMP
$rowRaw = $w * 3
$rowPad = (4 - ($rowRaw % 4)) % 4
$rowSize = $rowRaw + $rowPad
$pixelSize = $rowSize * $h
$outPath = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $root $Out }
$dir = Split-Path -Parent $outPath
if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

$fs = [System.IO.File]::Create($outPath)
$bw = New-Object System.IO.BinaryWriter($fs)
try {
    $bw.Write([byte]0x42); $bw.Write([byte]0x4D)
    $bw.Write([int](54 + $pixelSize)); $bw.Write([int]0); $bw.Write([int]54)
    $bw.Write([int]40); $bw.Write([int]$w); $bw.Write([int]$h)
    $bw.Write([int16]1); $bw.Write([int16]24); $bw.Write([int]0)
    $bw.Write([int]$pixelSize); $bw.Write([int]2835); $bw.Write([int]2835)
    $bw.Write([int]0); $bw.Write([int]0)
    for ($y = $h - 1; $y -ge 0; $y--) {
        for ($x = 0; $x -lt $w; $x++) {
            $i = ($y * $w + $x) * 2
            $v = $data[$i] -bor ($data[$i + 1] -shl 8)   # RGB565 little-endian
            $r5 = ($v -shr 11) -band 0x1F
            $g6 = ($v -shr 5) -band 0x3F
            $b5 = $v -band 0x1F
            $bw.Write([byte](($b5 -shl 3) -bor ($b5 -shr 2)))
            $bw.Write([byte](($g6 -shl 2) -bor ($g6 -shr 4)))
            $bw.Write([byte](($r5 -shl 3) -bor ($r5 -shr 2)))
        }
        for ($p = 0; $p -lt $rowPad; $p++) { $bw.Write([byte]0) }
    }
} finally {
    $bw.Close(); $fs.Close()
}
Write-Host ("[shot] 已保存 {0}（{1} 字节）" -f $Out, (Get-Item -LiteralPath $outPath).Length)
