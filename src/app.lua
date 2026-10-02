-- app：专注计时器（小应用基础框架示例）
-- 演示：screen 绘制、按键单击/双击/三击、led、buzzer、storage 存档、tts 播报
-- 运行前请先读 docs/development/miniapp-runtime.md；改动后跑 tools/validate.ps1。

local APP_TITLE = "专注计时"
local PRESETS = { 1, 5, 15, 25 }   -- 分钟档位

local BG     = 0x101820
local FG     = 0xFFFFFF
local MUTED  = 0x6C7A89
local ACCENT = 0x55DDCC
local TRACK  = 0x24313C

local BAR_Y   = 150
local BAR_H   = 6
local BAR_PAD = 24

local state = {
    preset = 1,
    left_ms = 0,
    running = false,
    finished = false,
}

local function preset_ms()
    return PRESETS[state.preset] * 60 * 1000
end

local function reset_clock()
    state.left_ms = preset_ms()
    state.running = false
    state.finished = false
    if led ~= nil and led.off ~= nil then
        led.off("status")
    end
end

local function fmt_ms(ms)
    local total = math.floor((ms + 999) / 1000)
    if total < 0 then
        total = 0
    end
    return string.format("%02d:%02d", math.floor(total / 60), total % 60)
end

local function draw()
    if screen == nil then
        return
    end
    ui.begin(BG)
    ui.text(APP_TITLE, 12, 12, MUTED)
    ui.text_center(fmt_ms(state.left_ms), 92, state.finished and ACCENT or FG)

    local total = preset_ms()
    local ratio = 0
    if total > 0 then
        ratio = 1 - (state.left_ms / total)
    end
    ui.progress(BAR_PAD, BAR_Y, ui.W - BAR_PAD * 2, BAR_H, ratio, ACCENT, TRACK)

    local hint = "单击开始"
    if state.finished then
        hint = "双击重置"
    elseif state.running then
        hint = "单击暂停 · 长按退出"
    end
    ui.text_center(hint, ui.H - 40, MUTED)
    ui.text_center(string.format("档位 %d 分钟 · 三击切换", PRESETS[state.preset]), ui.H - 24, MUTED)
    ui.present()
end

local function alert()
    if buzzer ~= nil and buzzer.play ~= nil then
        buzzer.play(1200, 200)
        buzzer.play(1600, 320)
    end
    if led ~= nil and led.blink ~= nil then
        led.blink("status", 120, 120)
    end
    speak.say("时间到，休息一下吧")
end

local function on_single_click()
    if state.finished then
        reset_clock()
    else
        state.running = not state.running
        if not state.running and led ~= nil and led.off ~= nil then
            led.off("status")
        end
    end
    draw()
end

local function on_double_click()
    reset_clock()
    draw()
end

local function on_triple_click()
    state.preset = state.preset % #PRESETS + 1
    store.set("preset", state.preset)
    reset_clock()
    draw()
end

function on_start()
    store.load()
    local saved = store.get("preset", 1)
    if type(saved) == "number" and saved >= 1 and saved <= #PRESETS then
        state.preset = math.floor(saved)
    end
    input.bind(on_single_click, on_double_click, on_triple_click)
    reset_clock()
    draw()
end

function on_tick(dt_ms)
    if type(dt_ms) ~= "number" or dt_ms <= 0 then
        dt_ms = 20
    end
    input.tick(dt_ms)
    store.tick(dt_ms)

    if state.running then
        state.left_ms = state.left_ms - dt_ms
        if state.left_ms <= 0 then
            state.left_ms = 0
            state.running = false
            state.finished = true
            alert()
        end
        draw()
    end
end

function on_button_click(button_id)
    input.button(button_id)
end

function on_http_response(request_id, response)
    net.on_response(request_id, response)
end

function on_tts_result(speech_id, result)
    speak.on_result(speech_id, result)
end

function on_exit()
    -- 退出时尽量落盘；失败（rate_limited 等）属正常，存档本身是可丢失数据
    store.flush(true)
    net.cancel_all()
    speak.cancel()
end
