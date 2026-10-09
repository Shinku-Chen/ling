-- dial：调谐刻度盘（移植 leo-radio 的 88–108 MHz 刻度 + 指针动画）
-- 原版几何来自 main/radio_ui.cc：
--   频段 88.0–108.0 MHz（880–1080，单位十分之一 MHz）
--   轨道 x = 16 … 198，指针宽 3，画布宽 240
-- 这里用矩形把同样的刻度画出来，指针带缓动动画。

local dial = {}

dial.BAND_LOW = 870
dial.BAND_HIGH = 1080

local TRACK_LEFT = 16
local TRACK_RIGHT = 198
local NEEDLE_W = 3

local x_current = (TRACK_LEFT + TRACK_RIGHT) / 2
local x_from = x_current
local x_target = x_current
local anim_left_ms = 0
local ANIM_MS = 420        -- 指针扫过去的时长
local phase = 0            -- 三角波动画相位（原版 s_animation += 17）

dial.y = 128               -- 刻度线的 y（调用方可改）

dial.track_left = TRACK_LEFT
dial.track_right = TRACK_RIGHT

--------------------------------------------------------------------------
-- 位置计算
--------------------------------------------------------------------------

-- 台 → 刻度 x：有真实频率就按频率落点，否则按序号均匀铺开
-- （与 leo-radio 的 dial_x_for_station 同策略，保证"指针总在动、读数只在有据可依时出现"）
local function x_for_frequency(freq)
    if type(freq) ~= "number" or freq <= 0 then
        return nil
    end
    local ratio = (freq - dial.BAND_LOW) / (dial.BAND_HIGH - dial.BAND_LOW)
    if ratio < 0 then ratio = 0 elseif ratio > 1 then ratio = 1 end
    return TRACK_LEFT + (TRACK_RIGHT - TRACK_LEFT) * ratio
end

function dial.x_for_station(freq, index, count)
    local x = x_for_frequency(freq)
    if x ~= nil then
        return x
    end
    -- 无频率：按序号铺开，并向内收一点，避免指针贴边
    if count <= 1 then
        return (TRACK_LEFT + TRACK_RIGHT) / 2
    end
    local inset = 6
    local lo, hi = TRACK_LEFT + inset, TRACK_RIGHT - inset
    local ratio = (index - 1) / (count - 1)
    return lo + (hi - lo) * ratio
end

--------------------------------------------------------------------------
-- 动画
--------------------------------------------------------------------------

-- 移动到目标位置；animate=false 时直接跳过去
function dial.move_to(x, animate)
    x_target = x
    x_from = x_current
    anim_left_ms = animate and ANIM_MS or 0
    if anim_left_ms == 0 then
        x_current = x_target
    end
end

-- 立即归位（例如刚启动时）
function dial.snap_to(x)
    x_current = x
    x_from = x
    x_target = x
    anim_left_ms = 0
end

function dial.tick(dt_ms)
    if dt_ms <= 0 then return end
    -- 三角波：原版每个 tick 加 17，这里按 20ms 折算保持观感一致
    phase = (phase + dt_ms * 17 / 20) % 256
    if anim_left_ms > 0 then
        anim_left_ms = anim_left_ms - dt_ms
        if anim_left_ms <= 0 then
            anim_left_ms = 0
            x_current = x_target
        else
            local t = 1 - (anim_left_ms / ANIM_MS)          -- 0 → 1
            local eased = 1 - (1 - t) * (1 - t)             -- ease-out
            x_current = x_from + (x_target - x_from) * eased
        end
    end
end

function dial.animating()
    return anim_left_ms > 0
end

-- 三角波 0..1：亮 → 暗 → 亮（原版用于呼吸/闪烁）
function dial.pulse()
    local v = phase
    if v > 128 then v = 256 - v end
    return v / 128
end

--------------------------------------------------------------------------
-- 绘制
--------------------------------------------------------------------------

function dial.draw()
    local y = dial.y
    local left = TRACK_LEFT
    local right = TRACK_RIGHT
    local span = right - left

    -- 轨道
    ui.rect(left, y, span, 2, 0x3A4A55)
    -- 刻度：每 2 MHz 一根，10 MHz 处加长
    local mhz = 88
    while mhz <= 108 do
        local ratio = (mhz - 88) / 20
        local x = math.floor(left + span * ratio)
        local major = (mhz % 10 == 0)
        ui.rect(x, y - (major and 8 or 5), 1, major and 12 or 8, 0x5E7180)
        mhz = mhz + 2
    end

    -- 指针：一段竖线 + 下方短横（原版是 needle + glow）
    local nx = math.floor(x_current)
    local glow = math.floor(dial.pulse() * 2)  -- 0..2
    ui.rect(nx - NEEDLE_W, y - 12, NEEDLE_W * 2 + 1, 28, 0x2E6E63)
    ui.rect(nx - 1, y - 14, NEEDLE_W, 32, 0x55DDCC)
    ui.rect(nx - 3 - glow, y + 18, 7 + glow * 2, 2, 0x2E6E63)
end

-- 刻度两端的固定标注（88 / 108），由调用方决定何时画
function dial.draw_labels(color)
    ui.text("88", TRACK_LEFT - 4, dial.y + 6, color)
    ui.text("108", TRACK_RIGHT - 16, dial.y + 6, color)
end
