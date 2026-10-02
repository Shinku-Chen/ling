-- net：http + json 封装
-- 运行时约束：并发未完成请求 ≤4；URL ≤511 字节；超时默认 10 s、上限 60 s；
--             响应默认 8 KiB、上限 32 KiB；不自动重试、不跟随重定向。
-- 用法：先画界面，再发请求，在回调里更新状态；不要在 on_start 里同步等结果。

local net = {}

local MAX_PENDING = 4
local DEFAULT_TIMEOUT_MS = 10000
local MAX_TIMEOUT_MS = 60000
local MAX_URL_BYTES = 511

local pending = {}   -- request_id -> callback

function net.available()
    return http ~= nil and http.get ~= nil
end

function net.count()
    local n = 0
    for _ in pairs(pending) do
        n = n + 1
    end
    return n
end

-- GET 请求。on_done(response) 里先判 response.error，再判 response.status。
function net.get(url, on_done, opts)
    if not net.available() then
        return nil, "unavailable"
    end
    if type(url) ~= "string" or #url < 8 or #url > MAX_URL_BYTES then
        return nil, "bad_url"
    end
    if net.count() >= MAX_PENDING then
        return nil, "busy"
    end
    local options = { timeout_ms = DEFAULT_TIMEOUT_MS }
    if type(opts) == "table" then
        if type(opts.timeout_ms) == "number" then
            local t = math.floor(opts.timeout_ms)
            if t < 1 then
                t = 1
            elseif t > MAX_TIMEOUT_MS then
                t = MAX_TIMEOUT_MS
            end
            options.timeout_ms = t
        end
        if type(opts.max_response_bytes) == "number" then
            options.max_response_bytes = math.floor(opts.max_response_bytes)
        end
        if type(opts.headers) == "table" then
            options.headers = opts.headers
        end
    end
    local id = http.get(url, options)
    if id == nil then
        return nil, "request_failed"
    end
    pending[id] = on_done
    return id
end

-- 由 app.lua 的 on_http_response 转发进来
function net.on_response(request_id, response)
    local cb = pending[request_id]
    if cb == nil then
        return
    end
    pending[request_id] = nil
    if type(response) ~= "table" then
        return
    end
    cb(response)
end

function net.cancel(request_id)
    if pending[request_id] == nil then
        return false
    end
    pending[request_id] = nil
    if http ~= nil and http.cancel ~= nil then
        http.cancel(request_id)
    end
    return true
end

function net.cancel_all()
    for id in pairs(pending) do
        if http ~= nil and http.cancel ~= nil then
            http.cancel(id)
        end
        pending[id] = nil
    end
end

-- GET + JSON：成功回调 on_data(data, nil)，失败回调 on_data(nil, err_code)
function net.get_json(url, on_data, opts)
    if json == nil or json.decode == nil then
        on_data(nil, "json_unavailable")
        return nil, "json_unavailable"
    end
    return net.get(url, function(response)
        if response.error then
            local err = response.error
            on_data(nil, err.code or "network_error")
            return
        end
        if response.status ~= 200 then
            on_data(nil, "http_" .. tostring(response.status))
            return
        end
        if type(response.body) ~= "string" or response.body == "" then
            on_data(nil, "empty_body")
            return
        end
        local data, err = json.decode(response.body)
        if data == nil then
            on_data(nil, err or "bad_json")
            return
        end
        on_data(data, nil)
    end, opts)
end
