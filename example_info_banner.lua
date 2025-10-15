-- Example script demonstrating how to use the InfoBanner module
-- This shows how to integrate the info banner into any norns script

-- Include the info banner module
local InfoBanner = include('lib/info_banner')

-- Screen dimensions (adjust to your screen size)
local screen_w, screen_h = 128, 64

-- Initialize the info banner system
function init()
    InfoBanner.init({
        screen_w = screen_w,
        screen_h = screen_h,
        auto_hide_time = 1.0,   -- Custom auto-hide time
        default_position = "center" -- Custom default position
    })

    -- Show a welcome message
    InfoBanner.show("Info Banner Ready!", "center")
end

-- Main redraw function
function redraw()
    screen.clear()

    -- Draw your main content here
    screen.level(15)
    screen.font_face(1)
    screen.font_size(12)
    screen.move(10, 30)
    screen.text("Press K1-K3 to test")

    screen.move(10, 45)
    screen.text("banner positions")

    -- Always call InfoBanner.draw() at the end of your redraw function
    InfoBanner.draw()

    screen.update()
end

-- Key handler to demonstrate different banner positions
function key(n, z)
    if z == 1 then -- Key press (not release)
        if n == 1 then
            InfoBanner.show("Top Left Banner", "top_left")
        elseif n == 2 then
            InfoBanner.show("Center Banner", "center")
        elseif n == 3 then
            InfoBanner.show("Bottom Center Banner", "bottom_center")
        end
    end
end

-- Encoder handler to demonstrate dynamic messages
function enc(n, delta)
    local value = math.random(1, 100)
    InfoBanner.show("Value: " .. value .. "%", "top_right")
end

-- Cleanup when script ends
function cleanup()
    InfoBanner.cleanup()
end



