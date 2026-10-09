# ling — Arcs-mini3 小应用工作区

用 Lua 为**聆思 Arcs-mini3（LS26 / LS2663）**写 LingClaw 小应用：在电脑上模拟调试，用 adb 推到设备上跑。
当前主应用是**网络电台**（`src/`）：单击换台、双击进设置菜单并暂停、长按退出。

## 三条链路

| 链路 | 用途 | 入口 |
|---|---|---|
| 模拟器 | 日常开发、界面与逻辑迭代、截图 | `.\tools\screenshot.ps1` 或直接打开 `lingclaw-sdk.exe` |
| adb | 真机调试：上传、拉回、看日志 | `.\tools\upload.ps1` |
| 云端下发 | 让设备"可实时更换"的小应用 | 见 `docs/development/cloud-distribution.md`（含当前边界） |

## 快速开始

```powershell
# 1. 改代码（src/ 下多文件）
# 2. 合并 + 静态检查 + 模拟器实跑
.\tools\validate.ps1

# 3. 只出图
.\tools\screenshot.ps1

# 4. 推到设备（需已装 Android Platform Tools，设备已开 ADB）
.\tools\upload.ps1 -Id timer
```

## 串口复位（复位后自动进入小应用）

```powershell
# 默认 COM9 @ 921600（设备 CH340 串口）
powershell -NoProfile -File tools/reset-device.ps1

# 指定串口 / 波特率 / 复位保持时长
powershell -NoProfile -File tools/reset-device.ps1 -Port COM7 -Baud 921600 -HoldMs 250
```

| 参数 | 默认值 | 说明 |
|---|---|---|
| `-Port` | `COM9` | 串口号 |
| `-Baud` | `921600` | 波特率（仅用于打开串口，本脚本不传数据） |
| `-HoldMs` | `250` | RTS 拉低时长（复位保持时间），一般不需要改 |

**信号极性**（实测确定，别试错）：

| 信号 | 电平 | 含义 |
|---|---|---|
| DTR | 保持**高** | 正常运行；**拉低会进 ROM 烧录模式** ✗ |
| RTS | 高 → **低（HoldMs）** → 高 | 空闲 → 复位 → 释放启动 ✔ |

**原理**：小应用运行时会持续把「热启动意图」写入 AON 寄存器（bit 21）。AON 域跨复位保持，
boot 读到该位就跳过「长按功能键开机」的等待，直接启动应用（约 5~10 秒后 adb 可见）。

**生效范围**：

| 场景 | 自动进业务 |
|---|---|
| 软件重启（`adb shell reboot`） | ✅ |
| 串口 RTS 复位（本脚本） | ✅ |
| cskburn 刷机后的复位 | ❌ 需按一次功能键 |
| 完全断电冷启动（拔 USB） | ❌ 需长按功能键（原厂防误触设计） |

详见 `docs/reference/device-behavior-log.md`。

## 目录

```text
src/           小应用源码（bundle.conf 决定合并顺序，产物 dist/app.lua）
tools/         build / validate / upload / pull / screenshot / reset-device
docs/          硬件、运行时契约、开发流程、云端边界、外部资料索引
examples/      最小可运行示例
```

## 关键约束（详见 AGENTS.md）

- 小应用是云端下发或 adb 上传的**裸 Lua**，只在 PSRAM 运行，**源码不持久化**；重启后需要重新下发。
- 运行时没有 `require`，多文件必须合并成单文件；产物上限 64 KiB。
- 沙箱里没有 `pcall`，参数非法会直接终止应用，必须防御式编程。
- 设备固件 `3.0.2` 的小应用 API 版本为 4（`screen` / `led` / `buzzer` / `clock` / `storage` / `http` / `json` / `tts`）。
- **音频播放**（`audio.play/stop/pause/resume/state`）官方固件没有，需要固件带 `CONFIG_MINIAPP_AUDIO`
  （见 [`firmware/README.md`](firmware/README.md)；当前设备上的 mini3 固件已包含，实测可连续播直播流）。
- 构建与烧录必须用 **`arcs_mini3`** 板型，不要用 `arcs_mini`（两者 SoC 与引脚不同，刷错会黑屏 + USB 不识别）。

## 文档

从 [docs/README.md](docs/README.md) 进。
