# 小应用运行时契约（API 4）

> 真相源：Arcs-mini 固件仓库 `docs/miniapp.md`（设备侧实现说明）+ LingClaw-SDK `docs/api/*`（模拟器侧同源契约）。
> 设备实测能力以 `ls.built_in.get_device_capabilities` 返回值为准；下面数字来自固件 `3.0.2` 的默认配置。

## 1. 它是什么

小应用 = **云端下发（或 adb 上传）的裸 Lua 文本**，在设备 PSRAM 里的受限 Lua 5.4 沙箱中运行：

- 只在内存中，**不写入 Flash / KV**；退出或重启后释放，需要云端重新下发。
- 源码必须是 UTF-8 文本，**不接受字节码**。
- 设备上只有一个"当前运行的小应用"，安装成功即全屏进入，替换掉上一个（替换时新旧两个实例短暂共存）。
- 长按功能键 3 秒退出，回到桌面；运行时**不进入空闲降亮度/休眠**。

## 2. 硬性上限

| 项目 | 上限 | 说明 |
|---|---|---|
| 源码字节 | 65,536 | `MINIAPP_SOURCE_MAX_BYTES`；UTF-8 字节计 |
| 单实例 Lua 堆 | 393,216 | 替换时需容纳两个实例 |
| 源码执行预算 | 500,000 条指令 / ~150 ms | 超预算直接终止实例 |
| 回调预算 | 250,000 条指令 / ~500 ms | `on_tick` / 按键等 |
| tick 间隔 | ~20 ms | `on_tick(dt_ms)` 的典型值 |
| `id` / `version` | 127 字节 | UTF-8 |

## 3. 沙箱能用的东西

**可用**：基础函数、`table`、`string`、`math`、`utf8`。

**不可用**（写了就是运行时报错/加载失败）：

```text
io / os / package / coroutine / debug / require
load / loadfile / dofile / collectgarbage
print / warn / pcall / xpcall / setmetatable
```

> 关键结论：**没有 `pcall`**。参数非法直接终止小应用，所以外部数据（HTTP 响应、存档、
> 时钟）必须显式判类型、判空。

## 4. 接口清单

### 4.1 基础

| 接口 | 说明 |
|---|---|
| `app.api_version` | 当前 API 版本（设备 3.0.2 = 4） |
| `app.width` / `app.height` | 画布尺寸（默认 240×240） |
| `screen.begin(rgb)` | 开始一帧并设背景色，`0xRRGGBB` |
| `screen.rect(x, y, w, h, rgb)` | 每帧 ≤128 个；尺寸为正且必须完全在画布内 |
| `screen.text(text, x, y, rgb)` | 每帧 ≤8 段；每段 ≤63 字节；固定 16 px 字体；`y ≤ height-16` |
| `screen.present()` | 提交当前帧；渲染约每 20 ms 更新一次 |
| `led.on("status")` / `led.off("status")` | 状态灯 |
| `led.blink("status", on_ms, off_ms)` | 亮/灭各 10–5,000 ms |
| `buzzer.play(hz, ms)` | 100–5,000 Hz、20–3,000 ms；异步队列最多 4 项 |

### 4.2 时间与存档（API ≥ 3）

| 接口 | 说明 |
|---|---|
| `clock.now()` | UTC 秒；**未校时返回 `nil`** |
| `clock.localtime()` | `{year, month, day, hour, min, sec, wday, utc_offset}`；未校时 `nil` |
| `storage.load()` | 读当前应用存档；不存在/过期/不可用返回 `nil` |
| `storage.save(data[, ttl_seconds])` | 成功 `true`；失败 `false, reason` |
| `storage.clear()` | 同上 |

存档约束：最多 32 项；键 1–32 字节；值为数字/布尔/≤256 字节字符串（不能嵌套、不能含 NUL）；
序列化总量默认 ≤1,024 字节；最多 4 个应用各有存档；TTL 默认 7 天、最长 30 天；
**同一存储槽写入间隔 ≥10 秒**（`rate_limited`）；未校时时不保存也不恢复。

常见失败原因：`clock_unavailable`、`rate_limited`、`too_large`、`invalid_data`、`invalid_ttl`、
`storage_full`、`io_error`、`no_memory`、`unavailable`。

### 4.3 网络与播报（API ≥ 4）

| 接口 | 说明 |
|---|---|
| `http.request(opts)` | `url` 必填；`method` 默认 GET（仅 GET/POST）；可选 `headers`/`body`/`timeout_ms`/`max_response_bytes` |
| `http.get(url[, opts])` | GET 简写 |
| `http.cancel(request_id)` | 取消本实例的指定请求 |
| `json.encode(v)` / `json.decode(t)` | 失败返回 `nil, reason`；`json.null` 表示 JSON null |
| `tts.speak(text)` | 非空 UTF-8 文本，用设备当前发音人；返回播报 ID |
| `tts.cancel(speech_id)` | 只取消本实例的播报，不能停对话/闹钟 |

额度：URL ≤511 字节；请求头 ≤16 项且累计 ≤1,024 字节；`body` 仅 POST 且 ≤8,192 字节；
超时默认 10,000 ms、上限 60,000 ms；响应默认 8,192、上限 32,768 字节；**并发未完成请求 ≤4**；
**不自动重试、不跟随重定向**。`tts` 文本 ≤512 字节，**同一时刻只有 1 个播报**，
忙时回调 `failed`（原因 `busy`），不排队不抢占；**禁止在源码执行、`on_start`、
启动第一次 tick、退出期间播报**。

### 4.4 回调（只认这些名字）

| 回调 | 必需 | 说明 |
|---|---|---|
| `on_tick(dt_ms)` | **必需** | 定时更新，约每 20 ms |
| `on_start()` | 可选 | 初始化；启用屏幕时启动阶段必须至少提交一帧 |
| `on_button_click(button_id)` | 可选 | 目前只有 `"function"`；短按释放即触发 |
| `on_exit()` | 可选 | 退出前收尾（不能在这里播报） |
| `on_http_response(request_id, response)` | 可选 | 不定义就丢弃结果并释放额度 |
| `on_tts_result(speech_id, result)` | 可选 | `completed` / `failed` / `interrupted` |

`on_http_response` 的 `response`：完整响应为 `{status, content_type, body}`（4xx/5xx 也算完整响应），
传输失败为 `{error = {code, message}}`（`network_error` / `timeout` / `response_too_large` / `unavailable`）。
**先判 `response.error`，再判 `status`，最后才解析业务数据。**

## 5. 生命周期与系统交互

- 进入小应用：停止当前语音输入与音乐播放，保留触发安装那次交互的 TTS；之后需要重新唤醒才有新会话。
- 小应用活跃时，`start` 帧携带 `mode=miniapp` 与 `{id, version}`；云端据此只处理"重新生成、修改、
  切换、询问玩法"，过滤其它意图。
- 闹钟到点：暂停脚本 tick 与按键输入，提醒结束后继续原实例。
- 蜂鸣：TTS/闹钟播放期间跳过；队列满时丢弃新蜂鸣，不阻塞、不退出。
- 超预算、堆耗尽、回调异常 → 终止该实例；**安装/替换失败时保留仍在运行的旧实例**。

## 6. 从 Lua 拿到的真实额度

不要在代码里硬写上面这些数字来判断"能不能用"。运行时应按能力接口自检：

```lua
-- 例：只在真的有网、有 http 额度时才发请求
local function net_ready()
    return http ~= nil and http.get ~= nil
end
```

设备端对应的能力接口是 MCP 的 `ls.built_in.get_device_capabilities`（面向云端，不是 Lua），
返回 `schema_version` / `firmware_info` / `hardware` / `runtime.lua_sdk`；模拟器里可以在
「设置 → 高级」查看和编辑同结构的 `capabilities` JSON。

## 7. 设备侧安装协议（给云端/平台用，不是开发者手动调的）

| MCP 工具 | 参数 | 说明 |
|---|---|---|
| `ls.built_in.miniapp_install` | `id`、`version`、`name`、`url`、`size`、`hash` | 六个全必填；`url` 是**有效期 300 秒**的裸 Lua 签名直链；`size` 为准确字节数；`hash` 为 32 位小写 MD5 |
| `ls.built_in.miniapp_exit` | 无 | 退出并回桌面；没有运行中的小应用返回 `no miniapp is running` |
| `ls.built_in.get_device_capabilities` | 无 | 能力查询 |

设备会比较 `id`/`version`/`hash`/大小：都一致时复用当前实例；否则下载、校验长度与 MD5，
在 PSRAM 里启动候选实例，成功后才替换。
