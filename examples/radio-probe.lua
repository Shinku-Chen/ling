-- 电台播放探针：验证 audio.play 能否连续播直播流
-- 结果写进 storage，可用 adb shell "kv get blob miniapp.save.<n>" 读回

local STATIONS = {
    { name = "中国之声", url = "http://lhttp.qingting.fm/live/15318317/64k.mp3" },
    { name = "第一财经", url = "http://lhttp.qingting.fm/live/276/64k.mp3" },
    { name = "怀旧音乐", url = "http://lhttp.qingting.fm/live/4804/64k.mp3" },
}

local BG, FG, MUTED, ACCENT = 0x101820, 0xFFFFFF, 0x6C7A89, 0x55DDCC

local idx = 1
local cont_ms = 0        -- 当前连续 playing 时长
local max_cont_ms = 0    -- 历史最长连续 playing
local total_ms = 0       -- 累计 playing
local transitions = 0    -- 状态变化次数
local state = ""         -- 上一次看到的 audio.state()
local paused = false
local t_ms = 0
local saved_at = -99999
local clicks = 0
local last_click_ms = -99999
local last_err = "-"
local plays = 0

local function save(note)
    storage.save({
        idx = idx,
        state = state,
        max_cont_ms = max_cont_ms,
        total_ms = total_ms,
        transitions = transitions,
        paused = paused and 1 or 0,
        last_err = last_err,
        plays = plays,
        note = note or "",
    }, 3600)
    saved_at = t_ms
end

local function draw()
    screen.begin(BG)
    screen.text("RADIO PROBE  api" .. tostring(app.api_version), 8, 6, MUTED)
    screen.text(STATIONS[idx].name, 8, 30, FG)
    screen.text("state " .. tostring(state) .. (paused and " PAUSED" or ""), 8, 56, ACCENT)
    screen.text("max " .. math.floor(max_cont_ms / 1000) .. "s  total " .. math.floor(total_ms / 1000) .. "s", 8, 80, FG)
    screen.text("plays " .. plays .. "  sw " .. transitions, 8, 104, MUTED)
    screen.text("err " .. tostring(last_err), 8, 128, MUTED)
    screen.text("#" .. idx .. "/" .. #STATIONS .. "   " .. math.floor(t_ms / 1000) .. "s", 8, 152, MUTED)
    screen.present()
end

local function play_current()
    cont_ms = 0
    paused = false
    plays = plays + 1
    audio.play(STATIONS[idx].url)   -- 异步：成功与否看后续 state
    draw()
end

local function toggle_pause()
    if paused then
        paused = false
        audio.resume()
    elseif state == "playing" or state == "prepared" or state == "preparing" then
        paused = true
        audio.pause()
    end
    draw()
end

function on_start()
    if audio == nil then
        state = "no_audio_api"
        draw()
        return
    end
    play_current()
end

function on_tick(dt_ms)
    t_ms = t_ms + dt_ms

    local now = audio and audio.state() or "unavailable"
    if now ~= state then
        transitions = transitions + 1
        state = now
        if now == "error" then last_err = "stream_error" end
        if now == "stopped" and not paused then last_err = "stopped" end
        draw()
    end

    if now == "playing" then
        cont_ms = cont_ms + dt_ms
        if cont_ms > max_cont_ms then max_cont_ms = cont_ms end
        if not paused then total_ms = total_ms + dt_ms end
    else
        cont_ms = 0
    end

    -- 单击 350ms 后确认：换下一个台
    if clicks == 1 and (t_ms - last_click_ms) > 350 then
        clicks = 0
        idx = idx % #STATIONS + 1
        play_current()
    end

    -- 每 11 秒落一次盘（运行时要求同槽写入间隔 ≥10 秒）
    if (t_ms - saved_at) >= 11000 then
        save("tick")
    end
end

function on_button_click(button_id)
    if button_id ~= "function" then return end
    if (t_ms - last_click_ms) <= 350 then
        clicks = 0
        toggle_pause()
    else
        clicks = 1
    end
    last_click_ms = t_ms
end

function on_exit()
    audio.stop()
    save("exit")
end
