# 收音机实现方案（ARCS SDK 路线）

目标：把 [leo-radio](https://github.com/leo0183/leo-radio) 的能力做到 Arcs-mini 上，**要有声音**。

## 1. 路线决策（2026-10-02 定）

| 方案 | 能否出声 | 结论 |
|---|---|---|
| LingClaw 小应用（Lua） | ❌ 官方 API 只有 `buzzer.play(hz,ms)` 与 `tts.speak(text)`，**没有任何播放音频流的接口** | 只能做"无声收音机"，放弃 |
| **ARCS SDK 固件内实现（C）** | ✅ `player_mgr_play()` / `app_player_play()` 是现成的，SDK 自带 MP3 解码与 HTTP 流 | **采用** |

选固件的额外好处：**不需要改 SDK、不需要给上游提 MR**（当年的"给 Lua 加音频接口"补丁另存为
[`../../firmware/miniapp-audio.patch`](../../firmware/miniapp-audio.patch)，暂缓）。
代价：收音机成为固件的一部分，不是可热插拔的小应用。

## 2. 交互定义（用户要求）

设备只有**一个功能键**，映射如下：

| 操作 | 行为 |
|---|---|
| 短按 | **下一个电台**（立即切换，起播） |
| 双击 | **进入设置菜单**，同时**暂停播放** |
| 长按 3 秒 | 退出到桌面（**系统占用**，不能挪作他用） |

> 双击识别需自己做（两个单击间隔阈值，约 350 ms）。参考小应用侧实现
> `../../src/lib/input.lua`（同样的单击/双击/三击判定逻辑，可直接照搬到 C 里的按键状态机）。

## 3. 技术要点

### 3.1 播放入口（现成，无需改 SDK）

```c
/* 应用层已有的两种用法，任选 */
player_mgr_play(int player_id, const char *url, int throw_time_ms);
app_player_play(app_player_t *player, const char *url);
```

- 参考实现：`src/middleware/player/sample/player_sample.c`（直接播 OSS 上的 mp3）。
- 解码：`arcs-sdk/components/lisa_media_player` 支持 **MP3**（`avi_player.c` 里显式处理 `MPEGLAYER3`）。
- **注意**：底层解码器会保留 URL 指针 → 传进去的字符串必须活到播放结束（不能用一次性栈缓冲）。

### 3.2 电台源

- **内置直链（首选，最稳）**：qingting 的 MP3 直播流，实测可达：
  ```
  http://lhttp.qingting.fm/live/15318317/64k.mp3   中国之声
  http://lhttp.qingting.fm/live/276/64k.mp3        第一财经
  http://lhttp.qingting.fm/live/4804/64k.mp3       怀旧音乐
  ```
  实测响应：`HTTP/1.1 200`、`Content-Type: audio/mpeg`、`icy-metadata: 1`、**无 Content-Length**（无限流）。
- **在线目录（可选）**：`http://de1.api.radio-browser.info/json/stations/search?...`
  实测 `200` 且**不重定向**（Lua 的 http 不跟随 302，这点很重要）。
- 城市定位（leo-radio 用 `ip-api.com` / `ipwho.is`）**建议砍掉**，改成内置城市表。

### 3.3 音频焦点（决定"被唤醒时怎么办"）

固件里已有音频焦点管理器，通道优先级（数值越小越优先）：

| 通道 | 优先级 | 被抢占策略 |
|---|---|---|
| tone（本地提示音） | 0 | STOP |
| tts（语音播报） | 10 | STOP |
| alert（闹钟） | 40 | PAUSE / 丢焦 STOP |
| miniapp | 45 | 当前为 STOP（补丁里改成 PAUSE，可自动续播） |
| music（云端音乐） | 50 | PAUSE（获得焦点后自动 resume） |

收音机建议挂在与 `music` 同级/相近的优先级，并把被抢占策略设为 **PAUSE**，这样
"唤醒说话 → 收音机暂停 → 说完自动续播"（焦点管理器有 `auto-resuming from focus pause` 路径）。

### 3.4 UI

- 用 `apps-ui` 的 LVGL 组件（1.54" 240×240，`lv_font_chinese_16` 有中文字库）。
- leo-radio 的"调谐指针沿 88–108 MHz 滑动"可以保留（LVGL 能画任意图元）。

## 4. 风险与前置条件

| 项 | 状态 |
|---|---|
| **无限直播流能否被播放器稳定播** | ⚠️ **最大未知数**。现有用法（mem:// WAV、OSS 上的 mp3、云端曲库）都是有头有尾的资源，必须实测 |
| 非 MP3 电台（AAC/HLS） | 未确认解码器支持，第一期只做 MP3 台 |
| 内存 | 6 MiB PSRAM heap 池要同时容纳解码缓冲与网络缓冲，需实测 |
| TLS | 播放器走固件 TLS 配置，接口不保证证书校验 |
| **设备可用** | 必须先恢复设备（USB 或串口），见 [flashing-and-recovery.md](flashing-and-recovery.md) |

## 5. 建议的实施顺序

1. 设备恢复（串口或 USB），确认能正常启动、屏幕、ADB/串口日志可用。
2. **最小出声验证**：写一个只有 3 个内置台 + 短按换台的最小页面，烧进去，**先验证能不能连续播 30 秒**。
3. 通过后再做：设置菜单（双击）、暂停/恢复、上一台/记忆上次电台、状态显示。
4. 最后再考虑在线目录、城市表等增强项。

## 6. 边界

- **不改 `arcs-sdk/`**（SDK/HAL 层），只在 `apps/` 加应用代码；确需改 SDK 时先说明原因与影响。
- 不碰 `boot` 分区（除串口救砖必须的整体恢复）。
- 电台源的版权/可用性由使用者自行确认；不把内部账号、密钥写进代码或文档。
