-- Screen Indicators Module
-- Reusable screen and mode indicator functionality
-- Usage: local ScreenIndicators = require 'lib/screen_indicators'

local ScreenIndicators = {}

-- Default configuration
local default_config = {
  screen_w = 128,
  screen_h = 64,
  indicator_width = 1,
  indicator_height = 3,
  indicator_spacing = 2,
  left_margin = 1,
  right_margin = 2
}

local config = {}

-- Initialize the screen indicators system
function ScreenIndicators.init(custom_config)
  config = {}
  -- Merge custom config with defaults
  for k, v in pairs(default_config) do
    config[k] = custom_config and custom_config[k] or v
  end
end

-- Draw screen indicator on the left side
-- Shows which sub-screen is selected within a mode
function ScreenIndicators.draw_screen_indicator(number_of_screens, selected_screen, options)
  options = options or {}
  local indicator_x = options.x_position or config.left_margin
  local indicator_height = options.height or config.indicator_height
  local indicator_spacing = options.spacing or config.indicator_spacing
  local start_y = (config.screen_h - (indicator_height + indicator_spacing) * number_of_screens) / 2
  
  for i = 1, number_of_screens do
    local y_position = start_y + (i - 1) * (indicator_height + indicator_spacing)
    
    -- Highlight the selected screen
    if i == selected_screen then
      screen.level(15)
    else
      screen.level(3)
    end
    
    screen.move(indicator_x, y_position)
    screen.line_rel(0, indicator_height)
    screen.stroke()
  end
end

-- Draw mode indicator on the right side
-- Shows which major mode is selected (e.g., voice, delay, record)
function ScreenIndicators.draw_mode_indicator(number_of_modes, selected_mode, options)
  options = options or {}
  local indicator_width = options.width or config.indicator_width
  local indicator_height = options.height or config.indicator_height
  local indicator_spacing = options.spacing or config.indicator_spacing
  
  local start_y = (config.screen_h / 2) - ((indicator_height + indicator_spacing) * (number_of_modes / 2))
  
  for i = 1, number_of_modes do
    local y_position = start_y + (i - 1) * (indicator_height + indicator_spacing)
    local x_position = config.screen_w - indicator_width - config.right_margin
    
    -- Highlight the selected mode
    if i == selected_mode then
      screen.level(15)
    else
      screen.level(3)
    end
    
    screen.rect(x_position, y_position, indicator_width, indicator_height)
    screen.fill()
  end
end

-- Draw a single indicator dot/line at a custom position
function ScreenIndicators.draw_single_indicator(x, y, is_active, style)
  style = style or "line"
  local indicator_height = config.indicator_height
  local indicator_width = config.indicator_width
  
  screen.level(is_active and 15 or 3)
  
  if style == "line" then
    screen.move(x, y)
    screen.line_rel(0, indicator_height)
    screen.stroke()
  elseif style == "rect" then
    screen.rect(x, y, indicator_width, indicator_height)
    screen.fill()
  elseif style == "dot" then
    screen.circle(x, y, indicator_width)
    screen.fill()
  end
end

-- Draw horizontal indicators (useful for tab-like interfaces)
function ScreenIndicators.draw_horizontal_indicator(number_of_items, selected_item, y_position, options)
  options = options or {}
  local indicator_width = options.width or config.indicator_height  -- Use height as width for horizontal
  local indicator_height = options.height or config.indicator_width -- Use width as height for horizontal
  local indicator_spacing = options.spacing or config.indicator_spacing
  local total_width = (indicator_width + indicator_spacing) * number_of_items - indicator_spacing
  local start_x = (config.screen_w - total_width) / 2
  
  for i = 1, number_of_items do
    local x_position = start_x + (i - 1) * (indicator_width + indicator_spacing)
    
    if i == selected_item then
      screen.level(15)
    else
      screen.level(3)
    end
    
    screen.rect(x_position, y_position, indicator_width, indicator_height)
    screen.fill()
  end
end

-- Draw circular indicators (useful for radial menus)
function ScreenIndicators.draw_circular_indicators(number_of_items, selected_item, center_x, center_y, radius, options)
  options = options or {}
  local dot_size = options.dot_size or 1.5
  local start_angle = options.start_angle or -math.pi / 2  -- Start at top
  
  for i = 1, number_of_items do
    local angle = start_angle + (i - 1) * (math.pi * 2 / number_of_items)
    local x = center_x + math.cos(angle) * radius
    local y = center_y + math.sin(angle) * radius
    
    if i == selected_item then
      screen.level(15)
    else
      screen.level(3)
    end
    
    screen.circle(x, y, dot_size)
    screen.fill()
  end
end

-- Update configuration (call this if you need to change settings)
function ScreenIndicators.update_config(new_config)
  for k, v in pairs(new_config) do
    if config[k] ~= nil then
      config[k] = v
    end
  end
end

-- Get current config values
function ScreenIndicators.get_config()
  return config
end

return ScreenIndicators


