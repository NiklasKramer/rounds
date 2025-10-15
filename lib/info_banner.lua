-- Info Banner Module
-- Reusable temporary text display functionality
-- Usage: local InfoBanner = require 'lib/info_banner'

local InfoBanner = {}

-- Default configuration
local default_config = {
    screen_w = 128,
    screen_h = 64,
    default_position = "bottom_center",
    auto_hide_time = 0.6,
    min_banner_width = 40,
    padding = 5,
    banner_height = 10
}

-- State variables
local show_info_banner = false
local metro_info_banner
local info_banner_text = ""
local banner_position = default_config.default_position
local config = {}

-- Initialize the info banner system
function InfoBanner.init(custom_config)
    config = {}
    -- Merge custom config with defaults
    for k, v in pairs(default_config) do
        config[k] = custom_config and custom_config[k] or v
    end

    banner_position = config.default_position

    -- Initialize the metro timer for auto-hiding
    metro_info_banner = metro.init(function(stage)
        show_info_banner = false
        redraw()
    end, config.auto_hide_time)
end

-- Show an info banner with message and optional position
function InfoBanner.show(message, position)
    if message and message ~= "" then
        info_banner_text = message
        show_info_banner = true

        -- Set the position if provided
        if position then
            banner_position = position
        end

        metro_info_banner:stop()
        metro_info_banner:start()
        redraw()
    else
        print("Warning: Attempted to show an empty info banner.")
    end
end

-- Hide the info banner manually
function InfoBanner.hide()
    show_info_banner = false
    metro_info_banner:stop()
    redraw()
end

-- Check if info banner is currently showing
function InfoBanner.is_showing()
    return show_info_banner
end

-- Get current banner text
function InfoBanner.get_text()
    return info_banner_text
end

-- Draw the info banner (call this from your redraw function)
function InfoBanner.draw()
    if not show_info_banner then return end

    local min_banner_width = config.min_banner_width
    local padding = config.padding
    local banner_height = config.banner_height

    -- Measure the text width
    local text_width = screen.text_extents(info_banner_text)
    local banner_width = math.max(text_width + padding, min_banner_width)

    local banner_x, banner_y

    -- Calculate banner position based on selected option
    if banner_position == "center" then
        banner_x = (config.screen_w - banner_width) / 2
        banner_y = (config.screen_h - banner_height) / 2
    elseif banner_position == "top_left" then
        banner_x = 2
        banner_y = 2
    elseif banner_position == "top_right" then
        banner_x = config.screen_w - banner_width - 2
        banner_y = 2
    elseif banner_position == "bottom_center" then
        banner_x = (config.screen_w - banner_width) / 2
        banner_y = config.screen_h - banner_height - 2
    else
        print("Unknown banner position: " .. banner_position)
        return
    end

    -- Draw banner background
    screen.level(1) -- Dim background level
    screen.rect(banner_x, banner_y, banner_width, banner_height)
    screen.fill()

    -- Draw banner text
    screen.level(15)
    screen.font_face(1)
    screen.font_size(8)
    local text_x = banner_x + (banner_width - text_width) / 2
    local text_y = banner_y + banner_height - 3

    screen.move(text_x, text_y)
    screen.text(info_banner_text)
end

-- Update configuration (call this if you need to change settings)
function InfoBanner.update_config(new_config)
    for k, v in pairs(new_config) do
        if config[k] ~= nil then
            config[k] = v
        end
    end

    -- Reinitialize metro if auto_hide_time changed
    if new_config.auto_hide_time and metro_info_banner then
        metro_info_banner.time = new_config.auto_hide_time
    end
end

-- Cleanup function (call this when done)
function InfoBanner.cleanup()
    if metro_info_banner then
        metro_info_banner:stop()
    end
    show_info_banner = false
end

return InfoBanner
