# 开发闭环：写 → 模拟 → 上机 → 抓证据

## 1. 本地校验（每次改完代码）

```powershell
.\tools\validate.ps1                  # 合并 + 静态检查 + 模拟器实跑，出 dist/screenshot.png
.\tools\validate.ps1 -Id timer        # 同时校验应用 id 合法性（1–121 位 ASCII 字母/数字/-/_）
```

`validate.ps1` 的三段：

1. **合并**：`tools/build.ps1` 把 `src/bundle.conf` 里的文件按顺序拼成 `dist/app.lua`。
2. **静态检查**：产物 ≤65,536 字节；不含禁用 API（`pcall`/`require`/`io.`/`os.`/`print` 等）；存在 `on_tick`。
3. **模拟器实跑**：headless 执行并出图；Lua 语法或启动错误会让**进程返回非零**，截图也不会生成。

## 2. 模拟器（GUI）

```powershell
& 'D:\Git-Workspace\LingClaw-SDK-0.1.0-windows-x64\lingclaw-sdk.exe'   # 打开后点「打开 Lua」选 dist\app.lua
```

- 保存文件后约 0.5 秒自动重载；也可以 `Ctrl/Cmd+R`。重载会重新初始化 Lua 状态。
- 右下角「事件」面板看运行信息与错误；**启动失败会保留上一个可用实例**。
- 「设置」里可改设备配置：复制配置 → 硬件页改屏幕/按键 → 按键映射页绑定键盘按键；
  高级页可编辑/导入/导出完整 `capabilities` JSON（含 API 版本与各项额度）。
- 暂停后「单步」推进一次 20 ms 更新。
- 相机按钮保存 PNG，尺寸 = 画布尺寸（不受缩放影响）；鼠标点预览下方按键也能触发点击。

## 3. headless（脚本化、无窗口）

```powershell
.\tools\screenshot.ps1                          # → dist/screenshot.png
.\tools\screenshot.ps1 -Out dist\shot2.png
# 等价原始命令：
#   lingclaw-sdk.exe --headless dist\app.lua dist\screenshot.png [capabilities.json]
```

语义：执行**启动阶段 + 50 次更新**后截图；不创建窗口；Lua 异常返回非零退出码；
**不等网络请求完成**。适合当 CI 闸门，不适合验证异步网络结果。

## 4. 上真机（adb）

```powershell
.\tools\upload.ps1 -Id radio -Serial <serial>   # 多台设备时必须指定；只有一台时可省略
.\tools\pull.ps1   -Serial <serial>             # adb pull /miniapp/miniapp.lua → dist\device-app.lua
```

先确认哪台是开发板（手机和开发板同时插着时 `adb devices` 会列出多台）：

```powershell
adb devices
adb -s <serial> shell version   # Arcs-mini 会打印固件版本，手机则报 Command not Found
adb -s <serial> shell help      # Arcs-mini 的命令列表
```

> Git Bash 用户注意：Git Bash 会把 `/miniapp/x.lua` 改写成 Windows 路径（`C:/Program Files/Git/...`），
> 必须加 `MSYS_NO_PATHCONV=1`；本仓库的 `tools\*.ps1` 走 PowerShell，不受影响。

- `/miniapp/<id>.lua` 是**虚拟入口**，不需要设备文件系统；`id` 为 1–121 位 ASCII 字母/数字/`-`/`_`，
  实际应用 ID 记作 `local:<id>`。
- ⚠️ **push 会替换设备上正在运行的小应用**（包括云端下发的那个）。上机前先确认用户是否同意。
  拉取（`pull.ps1`）是只读的，不影响运行中的应用。
- 每次 push 都会重新启动应用（即使源码没变）；上传成功表示"脚本已通过校验并启动"，
  语法/启动错误会从 `adb push` 返回，旧实例保留。
- **源码只存在内存里**：设备重启后小应用消失，需要重新 push（或由云端下发）。
- 拉取只能取当前运行的源码快照；没有应用运行时拉取失败。

## 5. 抓日志

```powershell
adb devices
adb logcat                                   # 设备整体日志
adb logcat | Select-String -Pattern 'miniapp'  # 过滤小应用相关
cd D:\Git-Workspace\LingClaw-SDK-0.1.0-windows-x64
```

固件 2.x 起支持 ADB 日志（`adb logcat`）；串口日志方式见
[docs/reference/README.md](../reference/README.md) 的《查看日志教程》。
异常现象（黑屏、无提示音、退出）先抓日志再改代码——不要凭现象猜。

## 6. 模拟器测不出来的东西（必须真机确认）

- 屏幕实际刷新观感、亮度、背光（模拟器是 LVGL 软件绘制 + RGB565）
- 蜂鸣/播报的真实音量与音频占用（模拟器不合成语音）
- 网络环境、证书、运营商链路（模拟器走电脑真实网络，不做 TLS 策略校验）
- 内存与调度：真机是 6 MiB PSRAM heap 池 + 双实例回滚，模拟器不会复现 OOM
- 按键手感、长按退出、闹钟打断、睡眠/降亮度策略
