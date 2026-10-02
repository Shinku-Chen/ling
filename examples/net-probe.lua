-- 联网探针：验证小应用能否直接使用设备已配网的网络
-- 用法（在设备已配网的前提下）：
--   1) adb push examples/net-probe.lua /miniapp/netprobe.lua
--   2) 等约 15 秒
--   3) 读回结果：adb shell "kv get blob miniapp.save.0"（逐个 slot 试，或 kv show 找）
--      设备以 hex dump 输出，把 hex 还原成字节即可看到 JSON。
-- 为什么能这么读：storage.save 的存档落在 KV 的 miniapp.save.<slot>，shell 的 kv 命令可以读 blob。
-- 注意：storage 写入要求设备已校时；未校时时会失败（reason=clock_unavailable），看屏幕即可。

local probe = { a_state = "idle", a_status = "-", a_len = "-", b_state = "idle", b_status = "-", b_len = "-", saved = "-" }
local t = 0
local stage = 0
local saved = false

local URL_A = "http://www.baidu.com/robots.txt"
local URL_B = "https://www.baidu.com/robots.txt"

local function draw()
    screen.begin(0x101820)
    screen.text("net probe", 12, 10, 0x8899AA)
    screen.text("api " .. tostring(app.api_version) .. " " .. (http and "http:yes" or "http:no"), 12, 28, 0x55DDCC)
    screen.text("A " .. probe.a_state .. " " .. probe.a_status .. " " .. probe.a_len, 12, 58, 0xFFFFFF)
    screen.text("B " .. probe.b_state .. " " .. probe.b_status .. " " .. probe.b_len, 12, 78, 0xFFFFFF)
    screen.text("save " .. tostring(probe.saved), 12, 108, 0x8899AA)
    screen.text("t=" .. tostring(math.floor(t / 1000)) .. "s", 12, 128, 0x8899AA)
    screen.present()
end

local function save_once()
    if saved then return end
    saved = true
    local ok, reason = storage.save({
        a_state = probe.a_state, a_status = probe.a_status, a_len = probe.a_len,
        b_state = probe.b_state, b_status = probe.b_status, b_len = probe.b_len,
    }, 3600)
    probe.saved = tostring(ok) .. "/" .. tostring(reason)
    draw()
end

local function send(url, which)
    local id = http.get(url, { timeout_ms = 8000, max_response_bytes = 8192 })
    if id == nil then
        if which == "a" then probe.a_state = "send_fail" else probe.b_state = "send_fail" end
    end
end

function on_start()
    draw()
end

function on_tick(dt_ms)
    t = t + dt_ms
    if stage == 0 and t >= 1500 then
        stage = 1
        send(URL_A, "a")
        draw()
    end
    if not saved and t >= 20000 then
        save_once()
    end
end

function on_http_response(request_id, response)
    if stage == 1 then
        if response.error then
            probe.a_state = "err:" .. tostring(response.error.code)
        else
            probe.a_state = "ok"
            probe.a_status = response.status
            probe.a_len = type(response.body) == "string" and #response.body or 0
        end
        stage = 2
        send(URL_B, "b")
    elseif stage == 2 then
        if response.error then
            probe.b_state = "err:" .. tostring(response.error.code)
        else
            probe.b_state = "ok"
            probe.b_status = response.status
            probe.b_len = type(response.body) == "string" and #response.body or 0
        end
        stage = 3
    end
    draw()
    if stage == 3 then
        save_once()
    end
end

function on_button_click(button_id)
end

function on_exit()
    save_once()
end
