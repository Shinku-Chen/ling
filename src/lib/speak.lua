-- speak：tts 封装
-- 运行时约束：同一时刻只有 1 条播报；文本 ≤512 字节；忙时失败原因 busy；
--             禁止在源码执行 / on_start / 启动第一次 tick / 退出期间播报。
-- 策略：最新一条覆盖队列（用户连续操作时只念最后一句）。

local speak = {}

local MAX_BYTES = 512
local pending_id = nil
local queued_text = nil
local done_handler = nil

function speak.available()
    return tts ~= nil and tts.speak ~= nil
end

function speak.busy()
    return pending_id ~= nil
end

function speak.set_done_handler(fn)
    done_handler = fn
end

-- UTF-8 安全截断到 MAX_BYTES
local function cut(text)
    if #text <= MAX_BYTES then
        return text
    end
    local cut_at = MAX_BYTES
    while cut_at > 0 do
        local b = string.byte(text, cut_at + 1)
        if b == nil or b < 0x80 or b >= 0xC0 then
            break
        end
        cut_at = cut_at - 1
    end
    return string.sub(text, 1, cut_at)
end

local function send(text)
    if not speak.available() then
        return nil
    end
    local id = tts.speak(text)
    if id == nil then
        return nil
    end
    pending_id = id
    return id
end

-- 播报一句；忙时记下最后一句，等当前播报结束再念
function speak.say(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end
    local t = cut(text)
    if pending_id ~= nil then
        queued_text = t
        return pending_id
    end
    return send(t)
end

-- 由 app.lua 的 on_tts_result 转发进来
function speak.on_result(speech_id, result)
    if pending_id ~= nil and speech_id ~= nil and speech_id ~= pending_id then
        return
    end
    pending_id = nil
    if done_handler then
        done_handler(result)
    end
    if queued_text ~= nil then
        local next_text = queued_text
        queued_text = nil
        send(next_text)
    end
end

function speak.cancel()
    if pending_id ~= nil and tts ~= nil and tts.cancel ~= nil then
        tts.cancel(pending_id)
    end
    pending_id = nil
    queued_text = nil
end
