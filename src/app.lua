-- app：网络电台小应用（界面移植自 leo-radio）
--   单击   → 播放页：换下一个电台；列表/城市页：移动选中项；菜单：移动选中项
--   双击   → 播放页：进设置菜单并暂停；其它页：确认
--   三击   → 从子页面快速返回播放页
--   长按   → 退出小应用（系统行为，脚本不处理）

local SCREEN_PLAYER = 1
local SCREEN_MENU = 2
local SCREEN_LIST = 3
local SCREEN_CITY = 4

-- 配色（取自 leo-radio 的调色板）
local C_BG = 0x0B1418
local C_FG = 0xF2F6F7
local C_MUTED = 0x849BA0
local C_AMBER = 0xFFB74D
local C_AMBER_SOFT = 0x7F5A29
local C_GREEN = 0x4ED39A
local C_RED = 0xFF5D62
local C_PANEL = 0x152229
local C_SEL = 0x1E3730

local SLEEP_MINUTES = { 0, 15, 30, 60, 90 } -- 与 leo-radio 的 kSleepTimerMinutes 一致
local ROWS = 5                              -- 列表一屏显示行数（受每帧 8 段文字限制）

local state = {
    screen = SCREEN_PLAYER,
    index = 1,
    menu = 1,
    list_sel = 1,
    city_sel = 1,
    paused = false,
    sleep_choice = 1,
    sleep_left_ms = 0,
    audio_state = "idle",
    err = "-",
    searching = false,
    online = false,        -- 当前列表是否来自在线目录
    city_display = "自动定位",
    t_ms = 0,
}

--------------------------------------------------------------------------
-- 工具
--------------------------------------------------------------------------

local function audio_ready()
    return audio ~= nil and audio.play ~= nil
end

local function state_text(s)
    if s == "playing" then return "播放中" end
    if s == "paused" then return "已暂停" end
    if s == "preparing" or s == "prepared" then return "连接中" end
    if s == "stopped" then return "已停止" end
    if s == "error" then return "播放失败" end
    if s == "unavailable" then return "无音频接口" end
    return "待机"
end

local function state_color(s)
    if s == "playing" then return C_GREEN end
    if s == "error" or s == "unavailable" then return C_RED end
    if s == "preparing" or s == "prepared" then return C_AMBER end
    return C_MUTED
end

local function clock_text()
    if clock == nil or clock.localtime == nil then
        return "--:--"
    end
    local t = clock.localtime()
    if type(t) ~= "table" or type(t.hour) ~= "number" or type(t.min) ~= "number" then
        return "--:--"
    end
    return string.format("%02d:%02d", t.hour, t.min)
end

local function fmt_mmss(ms)
    local total = math.floor((ms + 999) / 1000)
    if total < 0 then total = 0 end
    return string.format("%d:%02d", math.floor(total / 60), total % 60)
end

--------------------------------------------------------------------------
-- 播放
--------------------------------------------------------------------------

local function play_index(index)
    local station, norm = stations.get(index)
    state.index = norm
    state.paused = false
    if station == nil then
        state.err = "无电台"
        return
    end

    -- 先把界面（刻度指针）指到目标台：即使音频不可用，界面也要跟上
    dial.move_to(dial.x_for_station(station.freq or 0, state.index, stations.count()), true)

    if not audio_ready() then
        state.audio_state = "unavailable"
        state.err = "固件无音频接口"
        return
    end
    state.err = "-"
    audio.play(station.url)
end

local function next_station()
    play_index(state.index + 1)
end

local function set_paused(paused)
    if not audio_ready() then return end
    if paused then
        audio.pause()
    else
        audio.resume()
    end
    state.paused = paused
end

--------------------------------------------------------------------------
-- 在线目录
--------------------------------------------------------------------------

local function on_search_done(data, err)
    state.searching = false
    if data == nil then
        state.err = "搜索失败：" .. tostring(err)
        draw()
        return
    end
    local online, reason = stations.from_json(data)
    if online == nil then
        state.err = "没有可用电台：" .. tostring(reason)
        draw()
        return
    end
    local count = stations.apply(online, state.city_display)
    state.online = true
    state.list_sel = 1
    state.index = 1
    store.set("city", state.city_sel)
    play_index(1)
    state.screen = SCREEN_LIST
    draw()
    store.flush(true)
end

local function start_search(city_index)
    local city = stations.cities[city_index]
    if city == nil then return end
    state.city_sel = city_index
    state.city_display = city.display
    if not net.available() then
        state.err = "无网络接口"
        draw()
        return
    end
    state.searching = true
    state.err = "-"
    draw()
    net.get_json(stations.search_url(city.query or "北京"), on_search_done,
        { max_response_bytes = 32768, timeout_ms = 15000 })
end

--------------------------------------------------------------------------
-- 绘制
--------------------------------------------------------------------------

local function draw_player()
    local station = stations.get(state.index)
    ui.begin(C_BG)

    ui.text(clock_text(), 8, 6, C_MUTED)

    ui.text_center(station and station.name or "无电台", 26, C_FG)

    -- 描述行：有真实频率时把频率并进去（原版单独有读数，这里受每帧文字数量限制）
    local desc = ""
    if station ~= nil then
        local freq = stations.format_frequency(station.freq)
        desc = (freq ~= "" and ("FM" .. freq .. " · ") or "") .. tostring(station.desc or "")
    end
    ui.text_center(ui.truncate(desc, 54), 50, C_MUTED)

    -- 调谐刻度
    dial.y = 96
    dial.draw()
    dial.draw_labels(C_MUTED)

    -- 状态行
    local status = state_text(state.audio_state)
    if state.paused then status = "已暂停" end
    if state.sleep_left_ms > 0 then
        status = status .. "  ·  睡眠 " .. fmt_mmss(state.sleep_left_ms)
    end
    ui.text(status, 12, 152, state_color(state.audio_state))

    -- 序号 / 来源 / 错误
    local line = state.index .. "/" .. stations.count() .. "  ·  " .. (state.online and state.city_display or "内置电台")
    if state.err ~= "-" then
        line = line .. "  ·  " .. state.err
    end
    ui.text(ui.truncate(line, 54), 12, 174, C_MUTED)

    ui.text_center("单击换台  双击设置  长按退出", ui.H - 18, C_MUTED)
    ui.present()
end

local function menu_items()
    return {
        { kind = "list", label = "电台列表" },
        { kind = "city", label = "城市：" .. state.city_display },
        { kind = "sleep", label = "睡眠定时：" .. (SLEEP_MINUTES[state.sleep_choice] == 0 and "关" or (SLEEP_MINUTES[state.sleep_choice] .. " 分钟")) },
        { kind = "reset", label = "恢复内置电台" },
        { kind = "resume", label = "继续播放" },
    }
end

local source_title = ""

local function draw_list_rows(items, selected, label_of, empty_hint)
    ui.begin(C_BG)
    ui.text(source_title or "", 8, 6, C_MUTED)
    if #items == 0 then
        ui.text_center(empty_hint or "（空）", 100, C_MUTED)
    else
        local first = 1
        if selected > ROWS then first = selected - ROWS + 1 end
        local row = 0
        for i = first, math.min(#items, first + ROWS - 1) do
            local y = 28 + row * 24
            if i == selected then
                ui.rect(6, y - 3, ui.W - 12, 21, C_SEL)
            end
            ui.text(ui.truncate(label_of(items[i]), 54), 12, y, i == selected and C_FG or C_MUTED)
            row = row + 1
        end
    end
    ui.text_center("单击选择  双击确认  三击返回", ui.H - 18, C_MUTED)
    ui.present()
end


local function draw_menu()
    local items = menu_items()
    source_title = "设置"
    draw_list_rows(items, state.menu, function(item) return item.label end, "（空）")
end

local function draw_station_list()
    local items = {}
    for i = 1, stations.count() do
        local st = stations.get(i)
        local freq = stations.format_frequency(st and st.freq or 0)
        items[i] = { label = (freq ~= "" and ("FM" .. freq .. " ") or "") .. tostring(st and st.name or "") }
    end
    source_title = "电台列表 · " .. (state.online and state.city_display or "内置")
    draw_list_rows(items, state.list_sel, function(item) return item.label end, "没有电台")
end

local function draw_city()
    source_title = "选择城市"
    if state.searching then
        local dots = string.rep("·", 1 + math.floor(dial.pulse() * 3))
        draw_list_rows({ { label = "正在搜索 " .. state.city_display .. " " .. dots } }, 1,
            function(item) return item.label end, "搜索中")
        return
    end
    draw_list_rows(stations.cities, state.city_sel, function(item) return item.display end, "（空）")
end

function draw()
    if screen == nil then
        return
    end
    if state.screen == SCREEN_MENU then
        draw_menu()
    elseif state.screen == SCREEN_LIST then
        draw_station_list()
    elseif state.screen == SCREEN_CITY then
        draw_city()
    else
        draw_player()
    end
end

--------------------------------------------------------------------------
-- 输入
--------------------------------------------------------------------------

local function enter_menu()
    state.screen = SCREEN_MENU
    set_paused(true) -- 需求：双击进设置菜单的同时暂停
    draw()
end

local function back_to_player()
    state.screen = SCREEN_PLAYER
    set_paused(false)   -- 回到播放页就恢复播放（除非睡眠定时刚结束）
    draw()
end

local function menu_confirm()
    local items = menu_items()
    local item = items[state.menu]
    if item == nil then
        back_to_player()
        return
    end
    if item.kind == "list" then
        state.screen = SCREEN_LIST
        state.list_sel = state.index
        draw()
    elseif item.kind == "city" then
        state.screen = SCREEN_CITY
        state.city_sel = state.city_sel or 1
        draw()
    elseif item.kind == "sleep" then
        state.sleep_choice = state.sleep_choice % #SLEEP_MINUTES + 1
        state.sleep_left_ms = SLEEP_MINUTES[state.sleep_choice] * 60 * 1000
        store.set("sleep_choice", state.sleep_choice)
        draw()
    elseif item.kind == "reset" then
        stations.reset()
        state.online = false
        state.index = 1
        state.list_sel = 1
        play_index(1)
        state.screen = SCREEN_PLAYER
        draw()
    else
        back_to_player()
    end
end

local function on_single()
    if state.screen == SCREEN_MENU then
        state.menu = state.menu % #menu_items() + 1
        draw()
    elseif state.screen == SCREEN_LIST then
        state.list_sel = state.list_sel % math.max(stations.count(), 1) + 1
        draw()
    elseif state.screen == SCREEN_CITY then
        if not state.searching then
            state.city_sel = state.city_sel % #stations.cities + 1
            draw()
        end
    else
        next_station()
        draw()
    end
end

local function on_double()
    if state.screen == SCREEN_MENU then
        menu_confirm()
    elseif state.screen == SCREEN_LIST then
        play_index(state.list_sel)
        state.screen = SCREEN_PLAYER
        draw()
    elseif state.screen == SCREEN_CITY then
        if not state.searching then
            start_search(state.city_sel)
        end
    else
        enter_menu()
    end
end

local function on_triple()
    if state.screen ~= SCREEN_PLAYER then
        back_to_player()
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
    if type(sleep_saved) == "number" and sleep_saved >= 1 and sleep_saved <= #SLEEP_MINUTES then
        state.sleep_choice = math.floor(sleep_saved)
    end
    local city_saved = store.get("city", 1)
    if type(city_saved) == "number" and city_saved >= 1 and city_saved <= #stations.cities then
        state.city_sel = math.floor(city_saved)
        state.city_display = stations.cities[state.city_sel].display
    end

    input.bind(on_single, on_double, on_triple)
    play_index(state.index)
    draw()
end

function on_tick(dt_ms)
    if type(dt_ms) ~= "number" or dt_ms <= 0 then dt_ms = 20 end
    state.t_ms = state.t_ms + dt_ms
    input.tick(dt_ms)
    store.tick(dt_ms)
    dial.tick(dt_ms)

    if dial.animating() or state.screen == SCREEN_PLAYER or state.searching then
        draw()   -- 指针动画 / 呼吸效果 / 搜索动画需要刷新
    end

    if audio ~= nil and audio.state ~= nil then
        local now = audio.state()
        if now ~= state.audio_state then
            state.audio_state = now
            draw()
        end
    end

    if state.sleep_left_ms > 0 then
        state.sleep_left_ms = state.sleep_left_ms - dt_ms
        if state.sleep_left_ms <= 0 then
            state.sleep_left_ms = 0
            if audio_ready() then audio.stop() end
            state.paused = false
            draw()
        end
    end

    if state.index ~= store.get("station", -1) then
        store.set("station", state.index)
    end
end

function on_button_click(button_id)
    -- 运行时通过这个全局回调交付按键；漏写就会「按键无反应」
    input.button(button_id)
end

function on_http_response(request_id, response)
    net.on_response(request_id, response)
end

function on_exit()
    if audio_ready() then
        audio.stop()
    end
    store.set("station", state.index)
    store.set("sleep_choice", state.sleep_choice)
    store.set("city", state.city_sel)
    store.flush(true)
end
