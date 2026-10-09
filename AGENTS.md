# AGENTS.md — AI 编程助手入口

本仓库是用 Lua 为**聆思 Arcs-mini（LS26）**写 **LingClaw 小应用**的工作区。
这是 AI 在本仓库的唯一规则入口；先读本文件，再按「任务路由」读对应文档。

## 目标与硬事实

- 目标设备：**Arcs-mini3**（`arcs_mini3`，LS2663）。构建必须用 `-DBOARD=arcs_mini3`，固件仓库里对应的资源目录是 `res/arcs-mini3/`。
  - 同一系列的 **`arcs_mini` 是另一块板**（LS2684）、引脚与 boot/ap 镜像都不同：**刷错板型会出现黑屏 + USB 不识别 + 反复重启**（已实测，见 `docs/reference/device-behavior-log.md`）。
- 固件 ≥ `3.0.0` 才有小应用能力，当前设备实测 `3.0.2`。
- 运行时：小应用是**裸 Lua 文本**（不是字节码、不是固件），由云端下发或 adb 上传，只在 PSRAM 中运行，源码不落盘。
- API 版本：设备当前 `app.api_version = 4`（能力以设备 `get_device_capabilities` 为准，不按固件版本推断）。
- 单文件约束：**运行时没有 `require` / `dofile` / `load`**，所以多文件开发必须经 `tools/build.ps1` 合并成单个 `dist/app.lua` 再上传。
- 源码上限 65,536 字节；单实例 Lua 堆上限 393,216 字节；`screen` 每帧 ≤128 个矩形、≤8 段文字、每段 ≤63 字节。
- **音频**：官方固件的小应用**没有**播放接口；播放能力需要固件带 `CONFIG_MINIAPP_AUDIO`（本仓库 `firmware/miniapp-audio.patch`，已在 mini3 上验证可用）。

## 项目与安全基线

- 沙箱内**不存在** `pcall` / `xpcall` / `setmetatable` / `collectgarbage` / `load*` / `print` / `io` / `os` / `package` / `coroutine` / `debug` / `require`。不要写"加个 pcall 兜底"这类代码。
- 参数非法或运行超预算会**直接终止小应用**，没有异常兜底。所有外部输入（HTTP 响应、存档、时间）都要显式判空判类型。
- 硬件事实只有一个真相源：`docs/hardware/`。引脚、外设、内存上限不在这里的文件里定义时，**问用户，不要猜**。
- 不把登录凭证、Product Secret、API Key、设备 SID 写进仓库、日志或提交信息。
- 不擅自升级/刷写设备固件；固件操作属于端侧开发，按 `docs/reference/README.md` 的入口转交官方流程。
- 文件删除走系统回收站，不用 `rm -rf` / `git clean -fd`。

## 任务路由（编辑前先读）

| 任务 | 必读 |
|---|---|
| 写/改小应用代码 | `docs/development/miniapp-runtime.md`、`docs/development/coding-conventions.md` |
| 跑模拟器、抓截图、调试界面 | `docs/development/dev-loop.md` |
| 上传到设备 / 拉回源码 / 看日志 | `docs/development/dev-loop.md` |
| 环境从零搭起（SDK、adb、ling CLI） | `docs/development/environment-setup.md` |
| 云端下发 / 上架 / 发布相关 | `docs/development/cloud-distribution.md`（含明确的边界与未知项） |
| 烧录固件、刷分区、救砖、恢复出厂 | `docs/development/flashing-and-recovery.md` |
| 设备黑屏 / ADB 掉线 / 反复重启 | `docs/reference/device-behavior-log.md`（先排查休眠，再查 USB 链路） |
| 收音机 / 音频播放相关开发 | `docs/development/radio-native-plan.md` |
| 涉及引脚、屏幕、按键、内存、SoC 能力 | `docs/hardware/board-arcs-mini.md`（注意 `arcs_mini` / `arcs_mini3` 是两块不同的板） |
| 想知道外部权威资料在哪 | `docs/reference/README.md` |
| AI 协作方式与交付要求 | `docs/development/ai-guide.md` |

## 必需验证与交付

改动 `src/`、`tools/` 后，提交前至少跑一次：

```powershell
.\tools\validate.ps1
```

它做三件事：合并源码 → 静态检查（体积/禁用 API/必需回调）→ 用官方模拟器 headless 实跑一次并出图。
任何一步失败都不能宣称完成。交付汇报固定四字段：

```text
Build: PASS / FAIL / NOT RUN
Static checks: PASS / FAIL / NOT RUN
Simulator run: PASS / FAIL / NOT RUN
Unverified: 还需真机/人工确认的项（例如实际按键手感、蜂鸣音量、真机内存）
```

模拟器通过**不等于**真机通过：屏幕时序、音频、网络环境、内存调度都可能不同。

## 变更记录

- 2026-10-02：建立仓库文档骨架与 Lua 小应用基础框架（多文件源码 + 合并/校验/上传工具），依据 LingClaw-SDK 0.1.0 与 Arcs-mini 固件 3.0.2。
- 2026-10-02：补充烧录/恢复手册、设备行为实测记录（黑屏=休眠、ADB 掉线、sync 通道故障）与收音机方案（改走 ARCS SDK 固件内实现）；固件侧小应用音频补丁存档到 `firmware/`。
- 2026-10-02：**确认目标板是 `arcs_mini3`（LS2663）而非 `arcs_mini`（LS2684）**，之前的黑屏/USB 故障均源于刷错板型；改用 mini3 固件后全部恢复。小应用音频接口在 mini3 上实测可用（连续播放直播流 33 s），仓库主应用改写为**网络电台小应用**。
