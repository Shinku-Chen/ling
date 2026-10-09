-- app：网络电台小应用（界面照 leo-radio 的 build_main / timer_callback 逐项实现）
--   单击 → 播放页：换台；列表/城市/菜单：移动选中项
--   双击 → 播放页：进设置菜单并暂停；其它页：确认
--   三击 → 从子页面返回播放页
--   长按 → 退出小应用（系统行为）
--
-- 与原版的已知差异（沙箱限制，非实现取舍）：
--   * 画布 240×240（原版 240×320）→ 各行整体上移压缩
--   * 每帧最多 8 段文字（原版主界面 13 段）→ 省掉 6 个刻度数字中的 4 个、电量百分比、位置文字
--   * 只有一种 16px 字体（原版台名用 radio_font_title 大字体）
--   * 无电量/网络接口 → 电量只画轮廓、WiFi 条用"是否在播放"推断
--   * 读不到音频电平 → 电平条改为"播放活动"指示（分级配色与原版一致）

local SCREEN_PLAYER = 1
local SCREEN_MENU = 2
local SCREEN_LIST = 3
local SCREEN_CITY = 4

-- 配色：与 radio_ui.cc 的调色板逐值一致
local C_BG = 0x071017
local C_PANEL = 0x0D1B23
local C_PANEL_SOFT = 0x11262E
local C_GRID = 0x24404A
local C_TEXT = 0xF4F0DE
local C_MUTED = 0x849BA0
local C_AMBER = 0xFFB74D
local C_AMBER_SOFT = 0x7F5A29
local C_GREEN = 0x4ED39A
local C_RED = 0xFF5D62

local SLEEP_MINUTES = { 0, 15, 30, 60, 90 }
local ROWS = 5
local METER_COUNT = 18   -- kMeterCount
local DIAL_X, DIAL_Y, DIAL_W, DIAL_H = 22, 64, 196, 54
local METER_X, METER_Y, METER_W, METER_H = 13, 124, 214, 46

local state = {
    screen = SCREEN_PLAYER,
    index = 1,
    menu = 1,
    list_sel = 1,
    city_sel = 1,
    paused = false,
    sleep_choice = 1,
    last_draw_ms = 0,
    sleep_left_ms = 0,
    audio_state = "idle",
    err = "-",
    searching = false,
    search_started_ms = 0,
    online = false,
    city_display = "自动定位",
    t_ms = 0,
}

--------------------------------------------------------------------------
-- 工具
--------------------------------------------------------------------------

local function audio_ready()
    return audio ~= nil and audio.play ~= nil
end

-- 状态文案对齐原版 playback_text()
local function state_text(s)
    if s == "playing" then return "正在播放" end
    if s == "paused" then return "已暂停" end
    if s == "preparing" then return "正在连接电台" end
    if s == "prepared" then return "正在缓冲" end
    if s == "stopped" then return "已暂停" end
    if s == "error" then return "播放失败" end
    if s == "unavailable" then return "无音频接口" end
    return "准备播放"
end

local function state_color(s)
    if s == "error" or s == "unavailable" then return C_RED end
    return C_TEXT
end

local function clock_text()
    if clock == nil or clock.localtime == nil then return "--:--" end
    local t = clock.localtime()
    if type(t) ~= "table" or type(t.hour) ~= "number" or type(t.min) ~= "number" then
        return "--:--"
    end
    return string.format("%02d:%02d", t.hour, t.min)
end

local function fmt_mmss(ms)
    local total = math.floor((ms + 999) / 1000)
    if total < 0 then total = 0 end
    return string.format("%02d:%02d", math.floor(total / 60), total % 60)
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
    if paused then audio.pause() else audio.resume() end
    state.paused = paused
end

--------------------------------------------------------------------------
-- 在线目录（城市）
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
    stations.apply(online, state.city_display)
    state.online = true
    state.list_sel = 1
    play_index(1)
    state.screen = SCREEN_LIST
    store.set("city", state.city_sel)
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
    state.search_started_ms = state.t_ms
    state.err = "-"
    draw()

    -- 请求可能同步失败（URL 非法 / 无网络）：必须判返回值，否则 searching 会永远卡住
    local id, err = net.get_json(stations.search_url(city.query or "北京"), on_search_done,
        { max_response_bytes = 32768, timeout_ms = 15000 })
    if id == nil then
        state.searching = false
        state.err = "搜索请求失败：" .. tostring(err)
        draw()
    end
end

--------------------------------------------------------------------------
-- 绘制
--------------------------------------------------------------------------

-- 顶栏：CH 编号（左上，按用户要求代替原版的 LEO RADIO 品牌字）/ 时钟 / 电量轮廓 / WiFi 条 / 分隔线
local function draw_header()
    ui.text("CH " .. string.format("%02d", state.index) .. " / " ..
        string.format("%02d", stations.count()), 12, 4, C_AMBER)

    local cs = clock_text()
    ui.text_vcenter(cs, (ui.W - ui.text_width(cs)) / 2, 12, C_TEXT)

    -- 电量：小应用没有电池接口，只画轮廓；与顶栏文字同一垂直中心（cy=12）
    ui.rect(199, 7, 22, 10, C_BG)
    ui.rect(199, 7, 22, 1, C_MUTED)
    ui.rect(199, 16, 22, 1, C_MUTED)
    ui.rect(199, 8, 1, 8, C_MUTED)
    ui.rect(220, 8, 1, 8, C_MUTED)
    ui.rect(221, 10, 2, 4, C_MUTED)

    -- WiFi 条：原版联网时绿色、否则暗；这里用"是否正在播放"推断连通
    local online = (state.audio_state == "playing") or (not state.paused and state.online)
    for i = 0, 2 do
        local h = 3 + i * 3
        ui.rect(176 + i * 5, 18 - h, 3, h, online and C_GREEN or C_MUTED)   -- 底边对齐 cy+6
    end

    ui.rect(12, 24, 216, 1, C_GRID)
end

-- 播放图标：原版"播放中显示 II、否则显示 >"
local function draw_play_icon(x, y, playing)
    if playing then
        ui.rect(x, y, 4, 12, C_AMBER)
        ui.rect(x + 7, y, 4, 12, C_AMBER)
    else
        ui.rect(x, y, 5, 12, C_AMBER)
        ui.rect(x + 5, y + 3, 5, 6, C_AMBER)
        ui.rect(x + 10, y + 5, 4, 2, C_AMBER)
    end
end

-- 电平条：几何与配色分级照原版（h = 3 + level*34/100，底部 y=40，>85 红 / >62 琥珀 / 其余绿）
-- 原版由音频电平驱动；小应用读不到电平，这里用播放活动（正弦）驱动，仅作活动指示
local function draw_meter(active)
    for i = 0, METER_COUNT - 1 do
        local level = 0
        if active then
            local w1 = (math.sin(state.t_ms / 420 + i * 0.8) + 1) / 2
            local w2 = (math.sin(state.t_ms / 190 + i * 0.35) + 1) / 2
            level = math.floor((w1 * 0.6 + w2 * 0.4) * 100)
        end
        local h = 3 + math.floor(level * 34 / 100)
        local color = C_GREEN
        if level > 85 then color = C_RED
        elseif level > 62 then color = C_AMBER
        elseif not active then color = C_GRID end
        ui.rect(METER_X + 9 + i * 11, METER_Y + 40 - h, 6, h, color)
    end
end

local function draw_player()
    local station = stations.get(state.index)
    ui.begin(C_BG)
    draw_header()

    -- 台名（原版用大字体居中）
    ui.text_center(ui.truncate(station and station.name or "无电台", 48), 28, C_TEXT)

    -- 描述行（原版 12,105 居中）；频率有解析结果时并入这一行
    local desc = station and tostring(station.desc or "") or ""
    local freq = station and stations.format_frequency(station.freq or 0) or ""
    if freq ~= "" then desc = "FM" .. freq .. " · " .. desc end
    ui.text_center(ui.truncate(desc, 48), 48, C_MUTED)

    -- 刻度盘面板：圆角 8 + 1px 边框（原版 radius 8 / 边框 kGrid）
    ui.round_rect(DIAL_X, DIAL_Y, DIAL_W, DIAL_H, 8, C_GRID, 2)
    ui.round_rect(DIAL_X + 1, DIAL_Y + 1, DIAL_W - 2, DIAL_H - 2, 7, C_PANEL, 2)
    dial.panel_x, dial.panel_y = DIAL_X, DIAL_Y
    dial.draw()
    dial.draw_labels()

    -- 电平条面板：圆角 7
    ui.round_rect(METER_X, METER_Y, METER_W, METER_H, 7, C_PANEL_SOFT, 2)

    local playing = (state.audio_state == "playing") and not state.paused
    draw_meter(playing)

    -- 播放图标 + 状态行（原版 13,270 / 39,272；本机整体上移）
    -- 状态行：图标与文字共用垂直中心 cy=182（图标 12px、文字 16px）
    draw_play_icon(13, 176, playing)
    local status = state_text(state.audio_state)
    if state.sleep_left_ms > 0 then
        status = status .. "   定时 " .. fmt_mmss(state.sleep_left_ms)
    end
    if state.err ~= "-" then status = state.err end
    ui.text_vcenter(ui.truncate(status, 40), 34, 182, state.err ~= "-" and C_RED or state_color(state.audio_state))
    -- 右侧：位置（城市）右对齐，与状态同一垂直中心
    local city = tostring(state.city_display or "内置")
    ui.text_vcenter(city, ui.W - 14 - ui.text_width(city), 182, C_AMBER)

    ui.rect(12, 214, 216, 1, C_GRID)
    ui.text_center("单击换台  双击设置  长按退出", 220, C_MUTED)
    ui.present()
end

--------------------------------------------------------------------------
-- 绘制：列表类页面
--------------------------------------------------------------------------

local source_title = ""
local source_footer = ""

local function draw_list_rows(items, selected, label_of, empty_hint)
    ui.begin(C_BG)
    ui.text_vcenter(ui.truncate(source_title, 48), 12, 14, C_AMBER)
    ui.rect(12, 24, 216, 1, C_GRID)

    if #items == 0 then
        ui.text_center(empty_hint or "（空）", 110, C_MUTED)
    else
        local first = 1
        if selected > ROWS then first = selected - ROWS + 1 end
        local row = 0
        for i = first, math.min(#items, first + ROWS - 1) do
            local y = 34 + row * 26
            local sel = (i == selected)
            ui.round_rect(10, y - 4, 220, 24, 6, sel and C_PANEL_SOFT or C_PANEL, 2)
            ui.rect(14, y - 2, 3, 20, sel and C_AMBER or C_GRID)
            ui.text(ui.truncate(label_of(items[i]), 48), 22, y, sel and C_TEXT or C_MUTED)
            row = row + 1
        end
    end

    ui.rect(12, 214, 216, 1, C_GRID)
    ui.text_center(source_footer, 220, C_MUTED)
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

local function draw_menu()
    source_title = "设置"
    source_footer = "单击选择  双击确认  三击返回"
    draw_list_rows(menu_items(), state.menu, function(item) return item.label end, "（空）")
end

local function draw_station_list()
    local items = {}
    for i = 1, stations.count() do
        local st = stations.get(i)
        local freq = stations.format_frequency(st and st.freq or 0)
        items[i] = { label = (freq ~= "" and ("FM" .. freq .. " ") or "") .. tostring(st and st.name or "") }
    end
    source_title = "电台列表 · " .. (state.online and state.city_display or "内置")
    source_footer = "单击选择  双击确认  三击返回"
    draw_list_rows(items, state.list_sel, function(item) return item.label end, "没有电台")
end

local function draw_city()
    source_title = "选择城市"
    if state.searching then
        source_footer = "正在搜索 " .. state.city_display .. string.rep("·", 1 + math.floor(dial.pulse() * 3))
        draw_list_rows({}, 1, function() return "" end, "正在搜索…")
        return
    end
    source_footer = "单击选择  双击确认  三击返回"
    draw_list_rows(stations.cities, state.city_sel, function(item) return item.display end, "（空）")
end

function draw()
    if screen == nil then return end
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
    set_paused(false)
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
        draw()
    elseif item.kind == "sleep" then
        state.sleep_choice = state.sleep_choice % #SLEEP_MINUTES + 1
        state.sleep_left_ms = SLEEP_MINUTES[state.sleep_choice] * 60 * 1000
        store.set("sleep_choice", state.sleep_choice)
        draw()
    elseif item.kind == "reset" then
        stations.reset()
        state.online = false
        play_index(1)
        state.list_sel = 1
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
        if not state.searching then start_search(state.city_sel) end
    else
        enter_menu()
    end
end

local function on_triple()
    if state.screen ~= SCREEN_PLAYER then back_to_player() end
end

--------------------------------------------------------------------------
-- 生命周期
--------------------------------------------------------------------------

function on_start()
    store.load()
    local saved = store.get("station", 1)
    if type(saved) == "number" and saved >= 1 then state.index = math.floor(saved) end
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

    -- 重绘节流：原来每 tick 全屏重绘（一秒几十次、每次 ~120 矩形）会把 CPU 吃光，
    -- 与音频解码/网络抢资源，表现为按键后几秒才响应。播放页降到 ~8fps，
    -- 动画（刻度盘/搜索）~16fps，都靠 state.last_draw_ms 统一控制。
    do
        local iv = 0
        if state.screen == SCREEN_PLAYER then iv = 120 end
        if dial.animating() or state.searching then iv = 60 end
        if iv > 0 and (state.t_ms - state.last_draw_ms) >= iv then
            state.last_draw_ms = state.t_ms
            draw()
        end
    end

    if audio ~= nil and audio.state ~= nil then
        local now = audio.state()
        if now ~= state.audio_state then
            state.audio_state = now
            state.last_draw_ms = state.t_ms
            draw()
        end
    end

    if state.searching and (state.t_ms - state.search_started_ms) > 25000 then
        state.searching = false
        state.err = "搜索超时"
        draw()
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
    input.button(button_id)
end

function on_http_response(request_id, response)
    net.on_response(request_id, response)
end

function on_exit()
    if audio_ready() then audio.stop() end
    store.set("station", state.index)
    store.set("sleep_choice", state.sleep_choice)
    store.set("city", state.city_sel)
    store.flush(true)
end
