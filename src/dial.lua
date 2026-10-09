-- dial：调谐刻度盘（对齐 leo-radio 的 88–108 MHz 刻度）
-- 原版几何（main/radio_ui.cc build_main）：
--   刻度：41 根（0.5 MHz 间隔），每 8 根为长刻度（4 MHz，h=11/w=2），每 2 根为中刻度（1 MHz，h=6/w=1）
--   轨道 y=36（h=2）、指针 3×22 @ y=27、指针下方光晕 18×8 @ y=33
--   面板 13,135,214×69（本应用画布高 240，整体上移）
-- 这里用矩形复刻，指针带缓动动画、光晕带三角波呼吸。

local dial = {}

dial.BAND_LOW = 870   -- 87.0 MHz（十分之一 MHz）
dial.BAND_HIGH = 1080 -- 108.0 MHz

local TRACK_LEFT = 16
local TRACK_RIGHT = 198
local NEEDLE_W = 3
local TICK_COUNT = 41

-- 画布内位置由调用方设置：面板左上角 (panel_x, panel_y)
dial.panel_x = 13
dial.panel_y = 64
dial.panel_w = 214
dial.panel_h = 69

local x_current = (TRACK_LEFT + TRACK_RIGHT) / 2
local x_from = x_current
local x_target = x_current
local anim_left_ms = 0
local ANIM_MS = 420
local phase = 0

-- 绝对坐标辅助
local function ax(x) return dial.panel_x + x end
local function ay(y) return dial.panel_y + y end

--------------------------------------------------------------------------
-- 位置
--------------------------------------------------------------------------

function dial.x_for_station(freq, index, count)
    if type(freq) == "number" and freq > 0 then
        local ratio = (freq - dial.BAND_LOW) / (dial.BAND_HIGH - dial.BAND_LOW)
        if ratio < 0 then ratio = 0 elseif ratio > 1 then ratio = 1 end
        return TRACK_LEFT + (TRACK_RIGHT - TRACK_LEFT) * ratio
    end
    if count <= 1 then
        return (TRACK_LEFT + TRACK_RIGHT) / 2
    end
    local inset = 6
    local lo, hi = TRACK_LEFT + inset, TRACK_RIGHT - inset
    return lo + (hi - lo) * ((index - 1) / (count - 1))
end

--------------------------------------------------------------------------
-- 动画
--------------------------------------------------------------------------

function dial.move_to(x, animate)
    x_target = x
    x_from = x_current
    anim_left_ms = animate and ANIM_MS or 0
    if anim_left_ms == 0 then
        x_current = x_target
    end
end

function dial.snap_to(x)
    x_current = x
    x_from = x
    x_target = x
    anim_left_ms = 0
end

function dial.tick(dt_ms)
    if dt_ms <= 0 then return end
    phase = (phase + dt_ms * 17 / 20) % 256 -- 对应原版 s_animation += 17
    if anim_left_ms > 0 then
        anim_left_ms = anim_left_ms - dt_ms
        if anim_left_ms <= 0 then
            anim_left_ms = 0
            x_current = x_target
        else
            local t = 1 - (anim_left_ms / ANIM_MS)
            local eased = 1 - (1 - t) * (1 - t)   -- ease-out：扫过去时先快后慢
            x_current = x_from + (x_target - x_from) * eased
        end
    end
end

function dial.animating()
    return anim_left_ms > 0
end

-- 三角波 0..1（原版用它做呼吸/闪烁）
function dial.pulse()
    local v = phase
    if v > 128 then v = 256 - v end
    return v / 128
end

--------------------------------------------------------------------------
-- 绘制
--------------------------------------------------------------------------

-- 面板底板 + 边框（对应原版 make_box(..., kPanel, 8) + kGrid 边框）
function dial.draw_panel()
    local x, y = dial.panel_x, dial.panel_y
    ui.rect(x, y, dial.panel_w, dial.panel_h, 0x0D1B23)
    ui.rect(x, y, dial.panel_w, 1, 0x24404A)
    ui.rect(x, y + dial.panel_h - 1, dial.panel_w, 1, 0x24404A)
    ui.rect(x, y, 1, dial.panel_h, 0x24404A)
    ui.rect(x + dial.panel_w - 1, y, 1, dial.panel_h, 0x24404A)
end

function dial.draw()
    -- 刻度：0.5 MHz 间隔，长刻度每 4 MHz，中刻度每 1 MHz
    for i = 0, TICK_COUNT - 1 do
        local major = (i % 8 == 0)
        local medium = (i % 2 == 0)
        if major or medium then
            local x = TRACK_LEFT + i * (TRACK_RIGHT - TRACK_LEFT) / (TICK_COUNT - 1)
            local h = major and 11 or 6
            ui.rect(ax(math.floor(x)), ay(36 - h), major and 2 or 1, h,
                major and 0x24404A or 0x7F5A29)
        end
    end

    -- 轨道
    ui.rect(ax(TRACK_LEFT), ay(36), TRACK_RIGHT - TRACK_LEFT + 1, 2, 0x24404A)

    -- 指针下方的光晕（呼吸） + 指针本体
    local nx = math.floor(x_current)
    local glow = 18 + math.floor(dial.pulse() * 6)
    ui.rect(ax(nx) - glow / 2, ay(33), glow, 8, 0x7F5A29)
    ui.rect(ax(nx) - math.floor(NEEDLE_W / 2), ay(27), NEEDLE_W, 22, 0xFFB74D)
end

-- 刻度两端的数字（原版每 4 MHz 一个数字，受每帧文字上限限制这里只标两端）
function dial.draw_labels()
    ui.text("88", ax(TRACK_LEFT) - 2, ay(6), 0x849BA0)
    ui.text("108", ax(TRACK_RIGHT) - 18, ay(6), 0x849BA0)
end
