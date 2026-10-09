<#
  串口复位设备（Arcs-mini3，CH340）。复位后设备会自动进入小应用（无需按键）。

  原理：小应用运行时会把「热启动意图」写进 AON 寄存器（bit 21）——该寄存器跨复位保持，
  boot 读到它就跳过长按开机等待，直接启动应用。冷启动（断电）后该标志不存在，仍需按键。

  极性（实测 2026-10-10）：
    DTR 高 = 正常运行（DTR 低会进 ROM 烧录模式，不要用）
    RTS 高 = 空闲；RTS 低 = 复位（拉低 250ms 后释放到高，芯片重新启动）
#>
param(
  [string]$Port = "COM9",
  [int]$Baud = 921600,
  [int]$HoldMs = 250
)
$p = New-Object System.IO.Ports.SerialPort $Port, $Baud, "None", 8, "One"
try {
  $p.Open()
  $p.DtrEnable = $true
  $p.RtsEnable = $true
  Start-Sleep -Milliseconds 200
  $p.RtsEnable = $false
  Start-Sleep -Milliseconds $HoldMs
  $p.RtsEnable = $true
  Start-Sleep -Milliseconds 100
  Write-Host "[reset] 复位已发出（$Port）——设备应自动进入小应用（约 5~10 秒后 adb 可见）"
} finally {
  if ($p.IsOpen) { $p.Close() }
}
