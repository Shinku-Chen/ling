# 环境搭建

## 0. 当前机器状态（2026-10-02 已核对）

| 组件 | 状态 |
|---|---|
| Node / npm | 已装：Node `v24.18.0`、npm `11.16.0` |
| `ling` CLI（ListenAI 平台 CLI） | 已装：`C:\Users\chenz\bin\ling.exe`，版本 `1.0.1`，已加入用户 PATH |
| `ling` Agent Skill | 已装：`~\.agents\skills\ling`（`npx skills add LISTENAI/ling -g`） |
| LingClaw 模拟器 | 已解压：`D:\Git-Workspace\LingClaw-SDK-0.1.0-windows-x64\lingclaw-sdk.exe`（SDK 0.1.0） |
| adb（Android Platform Tools） | 已装：`.tools\platform-tools\adb.exe`（37.0.1），已被 `tools\*.ps1` 自动探测；该目录走 gitignore |
| 真机 | 已连接（usb adb），实测固件 `3.0.2-5f2bb183`（`adb shell version`），小应用 ADB 调试入口可用 |

## 1. 小应用开发只需要两样东西

1. **LingClaw 模拟器**（写代码、看界面、截图）
2. **adb**（把 Lua 推到真机；看日志）

不需要：ARCS 工具链、固件仓库、Rust。**固件编译/烧录是另一条线**，见
[../reference/README.md](../reference/README.md)。

## 2. 模拟器

```text
D:\Git-Workspace\LingClaw-SDK-0.1.0-windows-x64\
├─ lingclaw-sdk.exe     模拟器本体（GUI + headless）
├─ examples\            counter.lua / clock.lua
├─ docs\api\            API 参考（本仓库运行时契约的来源之一）
└─ docs\getting-started.md, docs\simulator.md
```

本仓库的脚本按这个顺序找模拟器：`$env:LINGCLAW_SDK` → 上面的默认路径 → `PATH`。
换机器或换版本时设一次环境变量即可：

```powershell
[Environment]::SetEnvironmentVariable('LINGCLAW_SDK','D:\path\to\lingclaw-sdk.exe','User')
```

升级方式：到 <https://github.com/LISTENAI/LingClaw-SDK/releases> 下载对应平台压缩包解压覆盖。

## 3. adb（Android Platform Tools）

装法任选：

```powershell
winget install Google.PlatformTools      # 有 winget 时
# 或手动：下载 https://developer.android.com/tools/releases/platform-tools 解压
```

装完把 `adb.exe` 所在目录加进 PATH（或放进本仓库 `.tools\platform-tools\`，该目录已被 gitignore）。
校验：

```powershell
adb devices        # 接上设备后应能看到序列号，状态为 device
adb shell version  # Arcs-mini：打印固件版本（实测 3.0.2-5f2bb183）
adb shell help     # Arcs-mini 的可用命令列表（gain/kv/device/sd/recovery/...）
```

> Git Bash 坑：Git Bash 会把 `/miniapp/xxx.lua` 当路径转换成 `C:/Program Files/Git/miniapp/...`。
> 在 Git Bash 里跑 adb 要加 `MSYS_NO_PATHCONV=1`；用本仓库的 `tools\*.ps1`（PowerShell）没有这个问题。

本机临时可用（不污染系统）的做法：

```powershell
# 下载解压到仓库内的 .tools/（已 gitignore）
$d = "$PWD\.tools"; New-Item -ItemType Directory -Force $d | Out-Null
# 之后把 platform-tools 解压到 $d，脚本会自动探测该路径
```

## 4. 设备侧准备

- 固件 ≥ `3.0.0`（小应用能力），建议 `3.0.2`。实测本机开发板已是 `3.0.2-5f2bb183`（`adb shell version`）。
- 固件 3.0.x 默认 `CONFIG_MINIAPP_ADB_DEBUG=y`，所以 `adb push` 到 `/miniapp/<id>.lua` 就是官方调试入口。
- 需要一根**支持数据传输**的 Type-C 线（只充电的线不行），优先主板后置 USB 口。
- 设备烧录/恢复固件：`docs/reference/README.md` 有《固件烧录教程(ADB工具)》入口。

## 5. 平台侧（可选，涉及云端下发时才需要）

```powershell
ling login          # 在你自己终端里输入 API Key（隐藏输入，别贴到对话里）
ling account        # 验证当前账号
ling app list       # 看账号下可管理的应用
ling wiki search 小应用    # 直接搜官方文档中心
```

API Key 从 <https://platform.listenai.com/keys> 获取。
