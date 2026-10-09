-- stations：电台清单、频率解析、城市、在线目录
-- 移植自 leo-radio：main/radio_player.cc（内置台）、main/radio_catalog.cc（频率解析与目录查询）

local stations = {}

-- 内置电台（与 leo-radio 的 kFallbackStations 一致；同顺序）
stations.builtin = {
    { name = "中国之声", desc = "新闻综合 · 网络直播", url = "http://lhttp.qingting.fm/live/15318317/64k.mp3", freq = 0 },
    { name = "怀旧音乐", desc = "经典老歌 · 网络直播", url = "http://lhttp.qingting.fm/live/4804/64k.mp3", freq = 0 },
    { name = "清晨音乐", desc = "轻松旋律 · 网络直播", url = "http://lhttp.qingting.fm/live/4915/64k.mp3", freq = 0 },
    { name = "两广之声", desc = "粤语音乐 · 网络直播", url = "http://lhttp.qingting.fm/live/20500149/64k.mp3", freq = 0 },
    { name = "羊城交通", desc = "城市资讯 · 网络直播", url = "http://lhttp.qingting.fm/live/1262/64k.mp3", freq = 0 },
    { name = "第一财经", desc = "财经资讯 · 网络直播", url = "http://lhttp.qingting.fm/live/276/64k.mp3", freq = 0 },
}

-- 城市表（与 leo-radio 的 kCityChoices 一致；query 为 nil 表示自动定位）
stations.cities = {
    { query = nil, display = "自动定位" },
    { query = "北京", display = "北京" },
    { query = "上海", display = "上海" },
    { query = "广州", display = "广州" },
    { query = "深圳", display = "深圳" },
    { query = "长沙", display = "长沙" },
    { query = "杭州", display = "杭州" },
    { query = "成都", display = "成都" },
}

stations.MAX_ONLINE = 10          -- 与 leo-radio 的 kMaxStations 一致
stations.DIRECTORY = "http://de1.api.radio-browser.info/json/stations/search"

--------------------------------------------------------------------------
-- 频率解析（忠实移植 radio_catalog.cc 的 read_decihz / in_band / parse_frequency）
--------------------------------------------------------------------------

local BAND_LOW = 870  -- 87.0 MHz，单位十分之一 MHz
local BAND_HIGH = 1080 -- 108.0 MHz

local function is_digit(ch)
    return ch >= "0" and ch <= "9"
end

local function in_band(decihz)
    return decihz >= BAND_LOW and decihz <= BAND_HIGH
end

-- 从 text 的第 i 个字符开始读 "94.7" / "1017" 这类数字，返回 (值, 消耗字符数)
local function read_decihz(text, i)
    local whole = 0
    while is_digit(string.sub(text, i + whole, i + whole)) and whole < 8 do
        whole = whole + 1
    end
    if whole < 2 or whole > 4 then
        return 0, 0
    end
    local value = 0
    for k = 0, whole - 1 do
        value = value * 10 + tonumber(string.sub(text, i + k, i + k))
    end
    local dot = string.sub(text, i + whole, i + whole)
    if dot == "." and is_digit(string.sub(text, i + whole + 1, i + whole + 1)) then
        if whole > 3 or is_digit(string.sub(text, i + whole + 2, i + whole + 2)) then
            return 0, 0
        end
        return value * 10 + tonumber(string.sub(text, i + whole + 1, i + whole + 1)), whole + 2
    end
    if whole == 2 then
        return value * 10, whole         -- "94" → 94.0
    end
    if in_band(value) then
        return value, whole              -- "971" → 97.1
    end
    if in_band(value * 10) then
        return value * 10, whole         -- "101" → 101.0
    end
    return value, whole
end

-- 解析电台名里的真实频率；解析不出返回 0（与原版一致，宁缺毋滥）
function stations.parse_frequency(name)
    if type(name) ~= "string" or name == "" then
        return 0
    end
    -- 1) 明确的 FM 前缀
    local i = 1
    local n = #name
    while i < n do
        local a = string.sub(name, i, i)
        local b = string.sub(name, i + 1, i + 1)
        if (a == "F" or a == "f") and (b == "M" or b == "m") then
            local j = i + 2
            while string.sub(name, j, j) == " " do j = j + 1 end
            local value = read_decihz(name, j)
            if in_band(value) and value > 0 then
                return value
            end
        end
        i = i + 1
    end
    -- 2) 裸数字（不能紧贴其他数字或小数点）
    i = 1
    while i <= n do
        if is_digit(string.sub(name, i, i)) then
            local prev = string.sub(name, i - 1, i - 1)
            local starts_run = (i == 1) or (not is_digit(prev) and prev ~= ".")
            if starts_run then
                local value, consumed = read_decihz(name, i)
                if consumed > 0 and in_band(value) and value > 0 then
                    return value
                end
            end
        end
        i = i + 1
    end
    return 0
end

-- 频率格式化成 "94.7"（无频率返回 ""）
function stations.format_frequency(decihz)
    if type(decihz) ~= "number" or decihz <= 0 then
        return ""
    end
    return string.format("%d.%d", math.floor(decihz / 10), decihz % 10)
end

--------------------------------------------------------------------------
-- 列表管理
--------------------------------------------------------------------------

local list = {}
local source = "内置"

local function copy_builtin()
    local out = {}
    for i = 1, #stations.builtin do
        local s = stations.builtin[i]
        out[i] = { name = s.name, desc = s.desc, url = s.url, freq = s.freq }
    end
    return out
end

function stations.reset()
    list = copy_builtin()
    source = "内置"
end

function stations.source()
    return source
end

function stations.count()
    return #list
end

function stations.get(index)
    local n = #list
    if n == 0 then
        return nil, 1
    end
    index = index or 1
    index = ((index - 1) % n) + 1
    return list[index], index
end

function stations.next(index)
    return stations.get((index or 1) + 1)
end

function stations.prev(index)
    return stations.get((index or 1) - 1)
end

stations.reset()

--------------------------------------------------------------------------
-- 在线目录（radio-browser）
--------------------------------------------------------------------------

-- 与 leo-radio 一致的查询参数：中国 + MP3 + 隐藏坏源 + 按点击量排序
-- 城市名是中文，必须按 UTF-8 逐字节百分号编码后才能放进 URL
function stations.url_encode(text)
    if type(text) ~= "string" then return "" end
    local out = {}
    for i = 1, #text do
        local b = string.byte(text, i)
        local ch = string.sub(text, i, i)
        if (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or
           ch == "-" or ch == "_" or ch == "." or ch == "~" then
            out[#out + 1] = ch
        else
            out[#out + 1] = string.format("%%%02X", b)
        end
    end
    return table.concat(out)
end

function stations.search_url(city)
    local query = stations.url_encode(city or "北京")
    return stations.DIRECTORY .. "?countrycode=CN&name=" .. query ..
        "&codec=MP3&hidebroken=true&order=clickcount&reverse=true&limit=" .. stations.MAX_ONLINE
end

-- 把 radio-browser 的返回数组转成电台列表（最多 MAX_ONLINE 个）
function stations.from_json(decoded)
    if type(decoded) ~= "table" then
        return nil, "bad_json"
    end
    local out = {}
    for i = 1, #decoded do
        local item = decoded[i]
        if type(item) == "table" then
            local url = item.url_resolved
            if type(url) ~= "string" or url == "" then
                url = item.url
            end
            local name = item.name
            if type(name) == "string" and name ~= "" and type(url) == "string" and url ~= "" then
                local station = {
                    name = name,
                    desc = "城市电台 · 网络直播",
                    url = url,
                    freq = stations.parse_frequency(name),
                }
                out[#out + 1] = station
                if #out >= stations.MAX_ONLINE then
                    break
                end
            end
        end
    end
    if #out == 0 then
        return nil, "no_station"
    end
    return out
end

-- 用在线结果替换当前列表；成功返回数量
function stations.apply(online, city_display)
    if type(online) ~= "table" or #online == 0 then
        return 0
    end
    list = online
    source = city_display or "在线"
    return #list
end
