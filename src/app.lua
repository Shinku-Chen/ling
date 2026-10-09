-- app：网络电台小应用
--   单击   → 换下一个电台
--   双击   → 进设置菜单，并暂停播放
--   长按   → 退出小应用（系统行为，脚本不处理）
-- 依赖固件的 audio 接口（audio.play/stop/pause/resume/state）；接口不存在时界面会提示。

local SCREEN_PLAYER = 1
local SCREEN_MENU = 2

local BG = 0x101820
local FG = 0xFFFFFF
local MUTED = 0x6C7A89
local ACCENT = 0x55DDCC
local WARN = 0xFFB020
local TRACK = 0x24313C
local SEL_BG = 0x1E3730

local SLEEP_CHOICES_MIN = { 0, 15, 30, 60 } -- 睡眠定时档位（分钟），0 = 关闭
local MAX_MENU_ROWS = 5                     -- 菜单一屏最多显示几行（screen 每帧上限 8 段文字）

local state = {
    screen = SCREEN_PLAYER,
    index = 1,
    menu = 1,
    paused = false,
    sleep_choice = 1,
    sleep_left_ms = 0,
    sleep_fired = false,
    audio_state = "idle",
    err = "-",
    t_ms = 0,
}

local function audio_ready()
    return audio ~= nil and audio.play ~= nil
end

local function state_text(s)
    if s == nil then return "未知" end
    if s == "playing" then return "播放中" end
    if s == "paused" then return "已暂停" end
    if s == "preparing" or s == "prepared" then return "连接中" end
    if s == "stopped" then return "已停止" end
    if s == "error" then return "播放失败" end
    if s == "unavailable" then return "无音频接口" end
    return "待机"
end

local function fmt_seconds(ms)
    local total = math.floor((ms + 999) / 1000)
    if total < 0 then total = 0 end
    return string.format("%d:%02d", math.floor(total / 60), total % 60)
end

--------------------------------------------------------------------------
-- 播放控制
--------------------------------------------------------------------------

local function play_index(index)
    local station, norm = stations.get(index)
    state.index = norm
    state.paused = false
    state.sleep_fired = false
    if station == nil then
        state.err = "无电台"
        return
    end
    if not audio_ready() then
        state.audio_state = "unavailable"
        state.err = "固件无音频接口"
        return
    end
    state.plays = (state.plays or 0) + 1
    audio.play(station.url)
end

local function next_station()
    play_index(state.index + 1)
end

local function set_paused(paused)
    if not audio_ready() then return end
    if paused then
        audio.pause()
        state.paused = true
    else
        audio.resume()
        state.paused = false
    end
end

--------------------------------------------------------------------------
-- 设置菜单
--------------------------------------------------------------------------

local function menu_items()
    local items = {}
    for i = 1, stations.count() do
        local st = stations.get(i)
        items[#items + 1] = { kind = "station", index = i, label = st and st.name or "电台" }
    end
    local sleep_label = "睡眠定时：" .. (SLEEP_CHOICES_MIN[state.sleep_choice] == 0 and "关" or
        (SLEEP_CHOICES_MIN[state.sleep_choice] .. " 分钟"))
    items[#items + 1] = { kind = "sleep", label = sleep_label }
    items[#items + 1] = { kind = "resume", label = "继续播放" }
    return items
end

local function clamp_menu()
    local items = menu_items()
    local n = #items
    if n == 0 then
        state.menu = 1
    elseif state.menu > n then
        state.menu = n
    elseif state.menu < 1 then
        state.menu = 1
    end
end

local function enter_menu()
    state.screen = SCREEN_MENU
    clamp_menu()
    set_paused(true) -- 需求：双击进设置菜单的同时暂停播放
    draw()
end

local function leave_menu(play_again)
    state.screen = SCREEN_PLAYER
    if play_again and not state.sleep_fired then
        set_paused(false)
    end
    draw()
end

local function menu_confirm()
    local items = menu_items()
    local item = items[state.menu]
    if item == nil then
        leave_menu(true)
        return
    end
    if item.kind == "station" then
        play_index(item.index)
        state.screen = SCREEN_PLAYER
        draw()
    elseif item.kind == "sleep" then
        state.sleep_choice = state.sleep_choice % #SLEEP_CHOICES_MIN + 1
        local minutes = SLEEP_CHOICES_MIN[state.sleep_choice]
        state.sleep_left_ms = minutes * 60 * 1000
        store.set("sleep_choice", state.sleep_choice)
        draw()
    else
        leave_menu(true)
    end
end

--------------------------------------------------------------------------
-- 绘制
--------------------------------------------------------------------------

local function draw_player()
    local station = stations.get(state.index)
    ui.begin(BG)
    ui.text("网络电台", 10, 6, MUTED)

    ui.text_center(stations.short_name(station), 34, FG)

    local state_color = ACCENT
    if state.audio_state == "error" or state.audio_state == "unavailable" then
        state_color = WARN
    end
    ui.text_center(state_text(state.audio_state), 60, state_color)

    local count = stations.count()
    ui.text_center(state.index .. " / " .. count .. (state.paused and "  ·  已暂停" or ""), 84, MUTED)

    -- 调谐刻度：一条横轴 + 每个电台一个刻度 + 当前台的指针
    local x0, x1, y = 24, ui.W - 24, 128
    local span = x1 - x0
    ui.rect(x0, y, span, 3, TRACK)
    if count > 1 then
        for k = 0, count - 1 do
            local x = math.floor(x0 + span * k / (count - 1))
            ui.rect(x - 1, y - 5, 2, 13, MUTED)
        end
        local mx = math.floor(x0 + span * (state.index - 1) / (count - 1))
        ui.rect(mx - 2, y - 9, 5, 21, ACCENT)
    else
        ui.rect(x0, y - 9, span, 21, ACCENT)
    end

    if state.sleep_left_ms > 0 then
        ui.text_center("睡眠定时 " .. fmt_seconds(state.sleep_left_ms), 158, MUTED)
    elseif state.err ~= "-" then
        ui.text_center(state.err, 158, MUTED)
    end

    ui.text_center("单击换台  双击设置  长按退出", ui.H - 20, MUTED)
    ui.present()
end

local function draw_menu()
    local items = menu_items()
    ui.begin(BG)
    ui.text("设置", 10, 6, MUTED)

    -- 只渲染选中项附近的若干行，避免超出每帧文字数量上限
    local first = 1
    if state.menu > MAX_MENU_ROWS then
        first = state.menu - MAX_MENU_ROWS + 1
    end
    local row = 0
    for i = first, math.min(#items, first + MAX_MENU_ROWS - 1) do
        local y = 36 + row * 22
        if i == state.menu then
            ui.rect(8, y - 3, ui.W - 16, 19, SEL_BG)
        end
        ui.text(items[i].label, 16, y, i == state.menu and FG or MUTED)
        row = row + 1
    end

    ui.text_center("单击选择 · 双击确认", ui.H - 20, MUTED)
    ui.present()
end

function draw()
    if screen == nil then
        return
    end
    if state.screen == SCREEN_MENU then
        draw_menu()
    else
        draw_player()
    end
end

--------------------------------------------------------------------------
-- 输入
--------------------------------------------------------------------------

local function on_single()
    if state.screen == SCREEN_MENU then
        local items = menu_items()
        state.menu = state.menu % math.max(#items, 1) + 1
        clamp_menu()
        draw()
    else
        next_station()
        draw()
    end
end

local function on_double()
    if state.screen == SCREEN_MENU then
        menu_confirm()
    else
        enter_menu()
    end
end

local function on_triple()
    -- 三击：直接回到播放界面（方便从菜单里退出）
    if state.screen == SCREEN_MENU then
        leave_menu(true)
    end
end

--------------------------------------------------------------------------
-- 生命周期
--------------------------------------------------------------------------

function on_start()
    store.load()
    local saved = store.get("station", 1)
    if type(saved) == "number" and saved >= 1 then
        state.index = math.floor(saved)
    end
    local sleep_saved = store.get("sleep_choice", 1)
    if type(sleep_saved) == "number" and sleep_saved >= 1 and sleep_saved <= #SLEEP_CHOICES_MIN then
        state.sleep_choice = math.floor(sleep_saved)
    end

    input.bind(on_single, on_double, on_triple)
    play_index(state.index)
    draw()
end

function on_tick(dt_ms)
    if type(dt_ms) ~= "number" or dt_ms <= 0 then
        dt_ms = 20
    end
    state.t_ms = state.t_ms + dt_ms
    input.tick(dt_ms)
    store.tick(dt_ms)

    -- 播放状态跟踪（只读取，不重绘整屏）
    if audio ~= nil and audio.state ~= nil then
        local now = audio.state()
        if now ~= state.audio_state then
            state.audio_state = now
            draw()
        end
    end

    -- 睡眠定时
    if state.sleep_left_ms > 0 then
        state.sleep_left_ms = state.sleep_left_ms - dt_ms
        if state.sleep_left_ms <= 0 then
            state.sleep_left_ms = 0
            state.sleep_fired = true
            if audio_ready() then
                audio.stop()
            end
            draw()
        end
    end

    -- 持久化（store 内部按 ≥10 秒节流）
    if state.index ~= store.get("station", -1) then
        store.set("station", state.index)
    end
end

function on_exit()
    if audio_ready() then
        audio.stop()
    end
    store.set("station", state.index)
    store.set("sleep_choice", state.sleep_choice)
    store.flush(true)
end
