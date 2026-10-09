# 拟提交上游的 MR 描述（arcs_mini → arcs-sdk/public/arcs_mini）

上游仓库：https://cloud.listenai.com/CSKG836746/arcs-sdk/public/arcs_mini （`master`）
我的 fork：https://cloud.listenai.com/chenzhuyu/arcs_mini
开 MR 链接模板（替换分支名）：
`https://cloud.listenai.com/chenzhuyu/arcs_mini/-/merge_requests/new?merge_request%5Bsource_branch%5D=pr%2F01-miniapp-audio`
**注意把 Target 改成上游**：`arcs-sdk/public/arcs_mini : master`

建议发布顺序：01 → 03 → 04 → 05 → 02 → 06

---

## pr/01-miniapp-audio —— 小应用支持播放 HTTP(S) 音频流

**动机**：小应用（Lua 沙箱）原先没有任何音频播放能力，限制了"收音机/播客/白噪音"这类应用。

**变更**：为 miniapp 增加 `audio.play/pause/resume/stop/state`；新增 Kconfig 开关
`MINIAPP_HAS_AUDIO`；补 `docs/miniapp.md`；`voice_player_comm.c` 提供播放通道。

**实测证据**：真机连续播放 http 直播流（64kbps MP3）**33 秒、零错误、无卡顿**。

**边界**：仅支持 http(s) 流式播放；不涉及本地文件。

---

## pr/02-radio-demo —— 网络电台演示工程（依赖 01）

**动机**：给音频能力提供可运行的验证用例，也可作为小应用开发的参考工程。

**变更**：新增 `apps/arcs-mini/radio/`（Kconfig + 播放演示），`prj.conf` 加 `CONFIG_RADIO_DEMO=y`。

**实测证据**：真机运行正常，配合 01 的接口连续播放直播流。

---

## pr/03-miniapp-battery —— 新增 `power.battery()`

**动机**：沙箱没有 ADC/GPIO 接口，小应用**读不到电量**，UI 只能画空电池图标。

**变更**：新增 `power.battery()` → `{ percent, mv, charging, status }`，复用既有电池中间件
`src/middleware/battery`（`battery_get_pct_raw()` / `battery_get_status()` / `battery_get_voltage_mv()`）。

**实测证据**：真机顶栏电量显示为**实心填充 + 百分比**；逐像素量测：填充宽度按内腔 20px 满铺，
文字与行盒中心一致（41.5 / 41.5）。

**边界**：数值依赖电池中间件已初始化；无该接口时小应用会退化为只画轮廓（保持兼容）。

---

## pr/04-miniapp-volume —— 新增 `audio.volume()` / `audio.set_volume()`

**动机**：`audio` 原本只有 5 个函数，小应用无法调音量（按键音量键与业务冲突时尤其需要）。

**变更**：新增音量读写接口（0..100，越界自动夹取），复用 `service_volume_set/get()`。

**实测证据**：真机菜单里循环调档立刻生效；重启后自动恢复上次音量。

---

## pr/05-shot —— 新增 `shot` 真机截屏命令

**动机**：小应用 UI 只能靠拍照核对，效率低且不准；需要真机截屏来核对像素级布局。

**变更**：新增 shell 命令 `shot`（整屏快照 → hex 分块输出）+ `shot <start> <len>` 分块拉取 +
`shot free`。配套主机脚本（RGB565 → BMP）在开发工作区。

**设计要点**：一次性输出 230KB 会被 ADB shell 输出缓冲截断（实测只到 980 字节），
因此改为分块协议：头行 `SHOT 240 240 RGB565 115200`，每行 32 字节 hex，块尾 `SHOTPART <start> <len>`。

**实测证据**：抓出完整 240×240 真机图（115,200 字节全部拉回），用于逐像素核对居中/边距。

**边界**：调试用途，建议量产固件用 Kconfig 关闭。

---

## pr/06-warm-boot —— 复位后自动进业务（热启动意图，Kconfig 门控，默认关）

**动机**：开发/量产设备在**复位后**必须长按功能键 3 秒才进入应用，自动化流程（刷机、回归测试）
无法无人值守。

**变更**：`power_mark_warm_boot_intent()` 置位 AON 寄存器 `resume_normal_boot`（bit 21）——
该寄存器**跨复位保持**，boot 读到即跳过冷启动长按等待。功能由 `CONFIG_WARM_BOOT_INTENT`
控制，**默认关闭**，以保持原厂上电行为。

**实测证据**：`adb shell reboot` 与串口 RTS 复位后均 **6 秒**自动进入应用（全过程未按键）。

**边界（重要）**：
- 完全断电冷启动、以及 cskburn 刷机后的复位**行为不变**，仍需长按功能键
- 若上游认为不适合进入量产固件，可仅作为开发配置保留（默认关即可）

**依赖**：分支基底含 pr/02 的电台 demo（main.c 调用点由演示工程引入）。
