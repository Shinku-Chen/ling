-- ui：帧式绘制助手
-- 运行时约束（见 docs/development/miniapp-runtime.md）：
--   每帧 ≤128 个矩形、≤8 段文字、单段文字 ≤63 字节、字体固定 16 px、颜色 0xRRGGBB
-- 这里统一做边界夹紧与 UTF-8 安全截断，业务代码只调 ui.* 即可。

local ui = {}

local DEFAULT_W = 240
local DEFAULT_H = 240

ui.W = app and app.width or DEFAULT_W
ui.H = app and app.height or DEFAULT_H
ui.LINE_H = 16
-- 实测：设备 16px 字号的墨迹比行盒中心低约 4px，统一上移补偿，使"居中"真的居中
ui.TEXT_DY = -4

-- 单段文字上限（字节），来自运行时契约
ui.MAX_TEXT_BYTES = 63

-- UTF-8 安全截断：按字节截断但不切多字节字符，超出时补省略号
function ui.truncate(text, max_bytes)
    if type(text) ~= "string" then
        text = tostring(text)
    end
    max_bytes = max_bytes or ui.MAX_TEXT_BYTES
    if #text <= max_bytes then
        return text
    end
    local ell = "..."
    local limit = max_bytes - #ell
    if limit < 0 then
        limit = 0
    end
    local cut = limit
    while cut > 0 do
        local b = string.byte(text, cut + 1)
        -- 0x80..0xBF 是续字节，说明切在了字符中间，继续左移
        if b == nil or b < 0x80 or b >= 0xC0 then
            break
        end
        cut = cut - 1
    end
    return string.sub(text, 1, cut) .. ell
end

-- 估算文本像素宽：ASCII 按 8 px，其余（中日韩等）按 16 px
function ui.text_width(text)
    if type(text) ~= "string" then
        text = tostring(text)
    end
    local px = 0
    local i = 1
    local n = #text
    while i <= n do
        local b = string.byte(text, i)
        local step = 1
        if b >= 0xF0 then
            step = 4
        elseif b >= 0xE0 then
            step = 3
        elseif b >= 0xC0 then
            step = 2
        end
        if step == 1 then
            px = px + 8
        else
            px = px + 16
        end
        i = i + step
    end
    return px
end

function ui.begin(bg)
    if screen then
        screen.begin(bg or 0x000000)
    end
end

function ui.present()
    if screen then
        screen.present()
    end
end

-- 矩形：自动夹紧到画布内；完全越界或尺寸非法时直接跳过，避免整帧失败
function ui.rect(x, y, w, h, rgb)
    if not screen then
        return
    end
    x = math.floor(x or 0)
    y = math.floor(y or 0)
    w = math.floor(w or 0)
    h = math.floor(h or 0)
    if w <= 0 or h <= 0 then
        return
    end
    if x < 0 then
        w = w + x
        x = 0
    end
    if y < 0 then
        h = h + y
        y = 0
    end
    if x >= ui.W or y >= ui.H then
        return
    end
    if x + w > ui.W then
        w = ui.W - x
    end
    if y + h > ui.H then
        h = ui.H - y
    end
    if w <= 0 or h <= 0 then
        return
    end
    screen.rect(x, y, w, h, rgb or 0xFFFFFF)
end

-- 文本：截断到 63 字节并夹紧 y（运行时要求 y ≤ height - 16）
function ui.text(text, x, y, rgb)
    y = y + (ui.TEXT_DY or 0)
    if not screen then
        return
    end
    local s = ui.truncate(text)
    if s == "" then
        return
    end
    x = math.floor(x or 0)
    y = math.floor(y or 0)
    if x < 0 then
        x = 0
    end
    if x > ui.W - 1 then
        return
    end
    if y < 0 then
        y = 0
    end
    if y > ui.H - ui.LINE_H then
        y = ui.H - ui.LINE_H
    end
    screen.text(s, x, y, rgb or 0xFFFFFF)
end

-- 圆角矩形：按圆弧逐行内缩（1px 一行），角是真圆，不会出现阶梯位移
function ui.round_rect(x, y, w, h, r, rgb)
    if not screen then return end
    r = math.floor(r or 0)
    if r <= 0 then
        ui.rect(x, y, w, h, rgb)
        return
    end
    if r * 2 > w then r = math.floor(w / 2) end
    if r * 2 > h then r = math.floor(h / 2) end
    ui.rect(x + r, y, w - 2 * r, h, rgb)          -- 中段
    ui.rect(x, y + r, r, h - 2 * r, rgb)          -- 左中
    ui.rect(x + w - r, y + r, r, h - 2 * r, rgb)  -- 右中
    -- 2px 一档：视觉上仍是圆弧，但矩形数减半（小应用每帧上限 128 个）
    local i = 0
    while i < r do
        local bh = 2
        if i + bh > r then bh = r - i end
        local dy = r - i - 0.5
        local inset = r - math.floor(math.sqrt(r * r - dy * dy) + 0.5)
        if inset < 0 then inset = 0 end
        local len = r - inset
        ui.rect(x + inset, y + i, len, bh, rgb)
        ui.rect(x + w - r, y + i, len, bh, rgb)
        ui.rect(x + inset, y + h - i - bh, len, bh, rgb)
        ui.rect(x + w - r, y + h - i - bh, len, bh, rgb)
        i = i + bh
    end
end

-- 垂直居中绘制：cy 是文字行的垂直中心（行高 16）
function ui.text_vcenter(text, x, cy, rgb)
    ui.text(text, x, math.floor(cy - ui.LINE_H / 2), rgb)
end

function ui.text_center_v(text, cy, rgb)
    ui.text_center(text, math.floor(cy - ui.LINE_H / 2), rgb)
end

-- 居中绘制（按估算宽度）
function ui.text_center(text, y, rgb)
    local s = ui.truncate(text)
    local x = math.floor((ui.W - ui.text_width(s)) / 2)
    ui.text(s, x, y, rgb)
end

-- 进度条：ratio 0..1，clamp 后绘制
function ui.progress(x, y, w, h, ratio, fg, bg)
    ui.rect(x, y, w, h, bg or 0x24313C)
    if type(ratio) ~= "number" then
        return
    end
    if ratio < 0 then
        ratio = 0
    elseif ratio > 1 then
        ratio = 1
    end
    if ratio > 0 then
        ui.rect(x, y, math.floor(w * ratio), h, fg or 0x55DDCC)
    end
end
