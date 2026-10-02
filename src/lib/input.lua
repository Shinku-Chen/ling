-- input：单击 / 双击 / 三击识别
-- 设备只提供 on_button_click（单击释放即触发），多击要靠间隔自己判断。
-- 用 on_tick 的 dt_ms 累加时间，不依赖 clock（clock 未校时返回 nil）。

local input = {}

local WINDOW_MS = 300   -- 判定 n 连击的间隔窗口
local now_ms = 0        -- 由 tick 累加的本地时间轴
local count = 0         -- 待判定的连续点击次数
local last_ms = -1000000
local handlers = { single = nil, double = nil, triple = nil }

local function dispatch(n)
    local fn
    if n <= 1 then
        fn = handlers.single
    elseif n == 2 then
        fn = handlers.double
    else
        fn = handlers.triple
    end
    if fn then
        fn(n)
    end
end

-- 绑定回调：三个都可以省略
function input.bind(on_single, on_double, on_triple)
    handlers.single = on_single
    handlers.double = on_double
    handlers.triple = on_triple
end

function input.reset()
    now_ms = 0
    count = 0
    last_ms = -1000000
end

-- 在 on_tick 里调用
function input.tick(dt_ms)
    if type(dt_ms) ~= "number" or dt_ms <= 0 then
        return
    end
    now_ms = now_ms + dt_ms
    if count > 0 and (now_ms - last_ms) > WINDOW_MS then
        local n = count
        count = 0
        dispatch(n)
    end
end

-- 在 on_button_click 里调用（只处理功能键，其它按键忽略）
function input.button(button_id)
    if button_id ~= nil and button_id ~= "function" then
        return
    end
    count = count + 1
    last_ms = now_ms
    if count >= 3 then
        -- 三击立即判定，不等窗口结束
        count = 0
        dispatch(3)
    end
end
