-- store：storage 封装
-- 运行时约束：同一存储槽写入间隔 ≥10 秒；总量 ≤1 KiB；值只能是数字/布尔/≤256 字节字符串；
--             未校时时不保存也不恢复；存档只是"可丢失"的进度/设置。
-- 这里做：延迟落盘 + 失败保留 + 类型校验，业务层只管 get/set。

local store = {}

store.TTL_SECONDS = 7 * 24 * 3600   -- 默认 7 天，最长 30 天
local MIN_WRITE_INTERVAL_MS = 10000 -- 运行时要求
local RETRY_LOAD_MS = 2000

local data = {}
local dirty = false
local loaded = false
local elapsed_ms = 0
local last_write_ms = -1000000
local last_load_try_ms = -1000000

function store.available()
    return storage ~= nil and storage.load ~= nil
end

-- 读回存档；返回是否成功（未校时/无存档返回 false）
function store.load()
    if not store.available() then
        return false
    end
    local d = storage.load()
    if type(d) ~= "table" then
        return false
    end
    data = d
    loaded = true
    return true
end

-- 在 on_tick 里调用：负责重试加载与节流落盘
function store.tick(dt_ms)
    if type(dt_ms) ~= "number" or dt_ms <= 0 then
        dt_ms = 20
    end
    elapsed_ms = elapsed_ms + dt_ms
    if not loaded and store.available() and (elapsed_ms - last_load_try_ms) >= RETRY_LOAD_MS then
        last_load_try_ms = elapsed_ms
        store.load()
    end
    if dirty and (elapsed_ms - last_write_ms) >= MIN_WRITE_INTERVAL_MS then
        store.flush()
    end
end

-- force=true 时忽略节流直接尝试（退出前用；可能因 rate_limited 失败，属正常）
function store.flush(force)
    if not dirty then
        return true
    end
    if not store.available() then
        return false, "unavailable"
    end
    if not force and (elapsed_ms - last_write_ms) < MIN_WRITE_INTERVAL_MS then
        return false, "throttled"
    end
    local ok, reason = storage.save(data, store.TTL_SECONDS)
    if ok then
        dirty = false
        last_write_ms = elapsed_ms
        return true
    end
    -- clock_unavailable / rate_limited / too_large ...：保留 dirty，下次 tick 再试
    return false, reason
end

function store.get(key, default)
    local v = data[key]
    if v == nil then
        return default
    end
    return v
end

function store.set(key, value)
    if type(key) ~= "string" or #key < 1 or #key > 32 then
        return false, "bad_key"
    end
    local t = type(value)
    if t == "number" or t == "boolean" then
        data[key] = value
    elseif t == "string" and #value <= 256 then
        data[key] = value
    else
        return false, "bad_value"
    end
    dirty = true
    return true
end

function store.clear()
    data = {}
    dirty = false
    if store.available() and storage.clear then
        storage.clear()
        return true
    end
    return false
end

-- 只读遍历（用于调试/展示，不要改返回的表）
function store.all()
    return data
end
