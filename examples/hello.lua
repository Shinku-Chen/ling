-- 最小可运行示例：不依赖 src/lib，也不依赖构建脚本
-- 用法：.\tools\screenshot.ps1 -Script examples\hello.lua
-- 说明：运行时要求 on_tick 必须定义；启用屏幕时启动阶段至少要提交一帧。

local clicks = 0
local BG = 0x142534

local function draw()
    screen.begin(BG)
    screen.text("Hello LingClaw", 16, 24, 0xFFFFFF)
    screen.text("clicks: " .. clicks, 16, 56, 0x55DDCC)
    screen.text("press Function", 16, 96, 0x8899AA)
    screen.present()
end

function on_start()
    draw()
end

function on_tick(dt_ms)
end

function on_button_click(button_id)
    if button_id == "function" then
        clicks = clicks + 1
        draw()
    end
end
