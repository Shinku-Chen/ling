<#
  调试一键脚本：复位设备 → 等 adb → 推送小应用 → （可选）抓图判定页面。

  为什么不做固件自启：小应用最终按社区发布机制（云端下发）走，自启与前台由平台决定；
  本脚本只在调试期提供同样的便利，且不引入与发布路径分叉的固件改动。

  用法：
    powershell -NoProfile -File tools/dev-restart.ps1
    powershell -NoProfile -File tools/dev-restart.ps1 -Id radio -SkipScreenshot
#>
param(
  [string]$Port = "COM9",
  [string]$Serial = "FFBBCCDDEE001124",
  [string]$Id = "radio",
  [int]$WaitSeconds = 60,
  [switch]$SkipScreenshot
)
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot

Write-Host "[dev] 1/4 串口复位（$Port）"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "reset-device.ps1") -Port $Port

Write-Host "[dev] 2/4 等待 adb 出现（最多 $WaitSeconds 秒；首次刷机后需长按功能键）"
$adb = Join-Path $root ".tools/platform-tools/adb.exe"
$env:MSYS_NO_PATHCONV = "1"
$t = 0
while ($t -lt $WaitSeconds) {
  Start-Sleep -Seconds 3; $t += 3
  $devs = (& $adb devices) 2>$null | Select-Object -Skip 1 | Where-Object { $_ -match "\tdevice" }
  if ($devs) { Write-Host ("[dev]    t+{0}s 已看到设备" -f $t); break }
}
if (-not $devs) { Write-Host "[dev] 超时未见设备：请长按功能键开机后重跑本脚本"; exit 1 }

Write-Host "[dev] 3/4 推送小应用（$Id）"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "upload.ps1") -Id $Id -Serial $Serial -SkipBuild | Select-Object -Last 1

if (-not $SkipScreenshot) {
  Start-Sleep -Seconds 5
  Write-Host "[dev] 4/4 抓图 + 页面判定"
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "screenshot-device.ps1") -Serial $Serial -Out (Join-Path $root "dist/device.bmp") | Select-Object -Last 1
  & python (Join-Path $PSScriptRoot "screen-analyze.py") (Join-Path $root "dist/device.bmp")
}
Write-Host "[dev] 完成"
