-- stations：电台清单
-- 内置直链（qingting 的 MP3 直播流，实测 Content-Type: audio/mpeg、无 Content-Length）。
-- 想加台直接往 list 里加即可；在线目录（radio-browser）留待后续迭代。

local stations = {}

stations.list = {
    { name = "中国之声", url = "http://lhttp.qingting.fm/live/15318317/64k.mp3" },
    { name = "第一财经", url = "http://lhttp.qingting.fm/live/276/64k.mp3" },
    { name = "怀旧音乐", url = "http://lhttp.qingting.fm/live/4804/64k.mp3" },
}

stations.count = function()
    return #stations.list
end

-- 取第 index 个台，索引自动环绕；返回 (station, 归一化后的 index)
stations.get = function(index)
    local n = #stations.list
    if n == 0 then
        return nil, 1
    end
    index = index or 1
    index = ((index - 1) % n) + 1
    return stations.list[index], index
end

stations.next = function(index)
    return stations.get((index or 1) + 1)
end

stations.prev = function(index)
    return stations.get((index or 1) - 1)
end

-- 短名：屏幕上空间有限，超长时截断（ui.text 也会再兜一层）
stations.short_name = function(station)
    if station == nil or station.name == nil then
        return "未知电台"
    end
    return station.name
end
