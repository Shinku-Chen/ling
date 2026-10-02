# 编码约定（Lua 小应用）

## 1. 单文件是运行时事实，多文件是开发便利

运行时没有 `require`/`load`，所以：

- `src/` 里可以拆多个文件（本仓库默认 `lib/` 放通用能力，`app.lua` 放业务与生命周期）。
- **每个模块文件里不要写 `return`**：合并后它们是同一个 chunk，中间的 `return` 是语法错误。
  统一用 `local xxx = {}` 定义、直接挂函数，模块间的可见性靠合并顺序（`src/bundle.conf`）。
- 产物只有一个 `dist/app.lua`，由 `tools/build.ps1` 生成，**不要手改产物**。
- 所有 Lua 源码必须是 **UTF-8 无 BOM**（设备端 Lua 解析器会把 BOM 当语法错误：`unexpected symbol near '<\239>'`）。
  PowerShell 5.1 的 `Set-Content -Encoding UTF8` 会写 BOM，手写文件时注意；本仓库统一由 `write`/`build.ps1` 保证无 BOM。

## 2. 防御式编程（因为没有 pcall）

| 场景 | 写法 |
|---|---|
| 可选硬件/接口 | `if buzzer then buzzer.play(880, 120) end` —— 表不存在时为 nil，直接判空 |
| HTTP 响应 | 先判 `response.error`，再判 `response.status`，最后 `json.decode` 并判返回值类型 |
| 存档读回 | `local d = storage.load(); if type(d) ~= "table" then d = {} end`，然后逐字段判类型 |
| 时间 | `clock.now()` 可能返回 nil（未校时），时钟类界面要显示"等待校时" |
| 外部数字 | 用 `tonumber` 转换后判 `nil`，不要相信字符串能直接运算 |
| 数值范围 | 面板宽度、矩形坐标都要夹紧到 `0..app.width-1`，越界矩形会让它整帧失败 |

## 3. 绘制

- 一帧 = `screen.begin(bg)` → 若干 `rect` / `text` → `screen.present()`。
- 每帧预算：**≤128 矩形、≤8 段文字、每段 ≤63 字节**；静态画面画一次即可，不用每 tick 重画。
- 文本用 `ui.text()` 统一处理截断与边界（`src/lib/ui.lua`），不要直接拼长字符串——中文 1 字 ≈3 字节。
- 颜色统一 `0xRRGGBB` 常量，集中在 `app.lua` 顶部。

## 4. 定时与状态

- 时间推进只信 `on_tick(dt_ms)` 累加，或已校时的 `clock.localtime()`；不要假设 tick 精确 20 ms。
- 按键只有单击回调；双击/三击靠间隔判断，用 `src/lib/input.lua`，不要自己写散落的计时状态。
- 长按 3 秒由系统处理（退出小应用），脚本里不要重复实现长按。

## 5. 存储与网络

- 存档是"可丢失"的：只放进度、设置；不要当作可靠数据库。
- 写入有 **≥10 秒** 间隔限制，用 `src/lib/store.lua` 的延迟落盘，不要每次按键就 `storage.save`。
- 网络请求全部异步：发出请求后先画"加载中"，在 `on_http_response` 里更新；不要在 `on_start`
  里同步等结果（也没法等）。
- 并发上限 4：用 `src/lib/net.lua` 管理 pending，发之前判额度。
- 播报同一时刻只有 1 条：用 `src/lib/speak.lua` 做"最新一条覆盖队列"。

## 6. 代码体积与风格

- 产物上限 64 KiB，多用短函数、少写重复的 UI 代码；注释可以精简，但接口约束（参数含义、
  单位、失败返回）必须写。
- 命名：模块 `local` 变量用模块名（`ui`/`store`/`net`/`input`/`speak`）；常量全大写；
  回调函数名必须是运行时约定的名字（`on_tick` 等），不要重命名。
- 注释写"为什么"和"约束"，不复述代码；中文说明，标识符保持 ASCII。
