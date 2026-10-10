# 收音机 native 化实施计划（设备端 ADK 方式）

> 决策（2026-10-10）：把收音机**做进固件**（native LVGL + 现有音频中间件），
> 不再依赖小应用热推机制。**硬约束：必须保留系统原有的扫码配网流程。**

## 一、为什么做、做到什么程度

| 目标 | 说明 |
|---|---|
| 开机即收音机 | 上电/复位后直接进入收音机界面（不再需要 adb 推送小应用） |
| 不破坏系统能力 | **扫码配网（二维码）流程保持可用**；语音助手页面保留（可被收音机抢占前台，但配网时必须能显示） |
| 不再受小应用沙箱限制 | native 无「每帧 ≤8 段文字 / ≤128 矩形 / 单段 ≤63 字节」限制，可用真实字体、真实圆角、真实动画 |

## 二、可以复用的现成资产（今天已验证）

### 音频（最关键，已跑通）
- 小应用音频接口补丁：`firmware/miniapp-audio.patch`（提交 `3efeccac`）——播放 http(s) 直播流已验证 33s 无错误
- 底层接口：`apps/arcs-mini/miniapp/miniapp_runtime.c` 里 `audio.play/pause/resume/stop/state` 的实现路径
  → 即 `app_player_*`（`src/category/comm/voice_player_comm.c` 初始化的 miniapp player）
- **native 实现直接用 `app_player_*` 即可**，不必经过 Lua 沙箱

### 音量 / 电量
- 音量：`service_volume_set/get()`（`apps/arcs-mini/services/service_volume.h`）
- 电量：`battery_get_pct_raw() / battery_get_status() / battery_get_voltage_mv()`（`src/middleware/battery/battery.h`）

### 按键事件
- 固件侧：`voice_msg_pub/sub`，动作枚举在 `apps/arcs-mini/button/app_button.c`
  （`VOICE_MSG_BUTTON_ACTION_CLICK / DOUBLE_CLICK / TRIPLE_CLICK / LONG_HOLD` 等）
- 小应用版本的单击/双击/长按判定逻辑可参考 `src/lib/input.lua`（窗口 300ms）

### 屏幕
- 系统 UI = LVGL（`apps-ui/`），小应用画布 240×240（`MINIAPP_SCREEN_WIDTH/HEIGHT`）
- **请勿修改**：`apps-ui/apps/llm/**`（助手页面/扫码配网/设置页）；收音机新增独立 screen

## 三、界面规格（对齐已定稿的小应用版本）

```
CH 01 / 06            12:34        [信号条][电量]
              中国之声
        新闻综合 · 网络直播
   ┌ 88   92   96  100  104  108 ┐     ← 刻度盘面板 x=22 y=78 w=196 h=54（圆角 8）
   │   ──────────┃──────────     │     ← 指针 3×22，直接跳动无缓动、无光晕
   └─────────────────────────────┘
   ┌ ▁▃▅█▅▃▁▃▅█▅▃▁▃▅█▅▃▁ ┐          ← 电平条面板 x=13 y=138 w=214 h=46
   └───────────────────────┘
Ⅱ 正在播放                       上海    ← 状态行中心 y=196（城市右对齐）
   单击换台  双击设置  长按退出           ← 提示行 y≈220
```

配色（实测取自 `radio_ui.cc`）：`BG=071017 PANEL=0D1B23 AMBER=FFB74D GREEN=4ED39A RED=FF5D62 MUTED=849BA0 GRID=24404A`
文本垂直居中注意：真机 16px 字号墨迹比行盒中心**低约 4px**，需按此补偿。

## 四、功能规格

| 功能 | 行为 |
|---|---|
| 换台 | 单击下一个台；刻度指针直接跳到新位置 |
| 菜单 | 双击进入（暂停播放）；菜单项：电台列表 / 城市 / 音量 / 睡眠定时 / 恢复内置 / 继续播放 |
| 返回 | 三击返回 |
| 内置电台 | 6 台默认（中国之声/怀旧音乐/清晨音乐/两广之声/羊城交通/第一财经），开机默认用内置，**不联网** |
| 在线目录 | 仅当用户在「城市」里选择具体地区时联网拉取（radio-browser，`limit=10`） |
| 音量 | 0/20/40/60/80/100 循环，落盘保存，开机恢复 |
| 睡眠定时 | 到点停止播放 |

## 五、实施步骤（建议顺序，每步都可单独验证）

1. **骨架**：新增 `apps/arcs-mini/radio_ui/`（Kconfig + CMakeLists），创建独立 LVGL screen，
   实现顶栏 + 台名/描述 + 提示行（静态文字），按键切换进入/退出该 screen
   - 验收：单击换台时台名变化；三击返回助手页；**扫码配网流程不受影响**
2. **刻度盘 + 电平条**：复刻几何（见上），指针直接跳动；电平条先用拟态数据跑通布局
3. **播放链路**：接 `app_player_*` 播放内置 6 台（http 直链），状态行显示播放/暂停
4. **菜单**：列表 / 音量 / 睡眠定时 / 恢复内置（复用 `service_volume_*`）
5. **在线目录**：城市选择后请求 radio-browser（JSON 解析可用 `cJSON`），失败回退内置并提示
6. **收尾**：Kconfig 门控（`CONFIG_RADIO_NATIVE`，默认关）；开机自启可选；文档与 MR

## 六、风险与注意

- **扫码配网**：收音机 screen 必须是独立层，且提供明确的"退出到助手页"路径；配网触发时强制回助手页
- **音频抢占**：助手/TTS 播放时收音机应暂停；退出收音机应停止播放（避免后台占音频）
- **PSRAM/内存**：native 不再受小应用堆限制，但电台列表与 JSON 缓冲仍应限于一次 10 条以内
- **热更新**：native 后改 UI 需重编重烧（小应用时代的"推送即改"不再适用）
