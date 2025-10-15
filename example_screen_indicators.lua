-- Example script demonstrating how to use the ScreenIndicators module
-- This shows various ways to use screen indicators in any norns script

-- Include the screen indicators module
local ScreenIndicators = include('lib/screen_indicators')

-- Screen dimensions
local screen_w, screen_h = 128, 64

-- Example state
local current_mode = 1
local number_of_modes = 3
local current_screen = 1
local number_of_screens = 5

-- Initialize
function init()
  ScreenIndicators.init({
    screen_w = screen_w,
    screen_h = screen_h
  })
end

-- Main redraw function
function redraw()
  screen.clear()
  
  -- Draw mode indicator on the right (3 modes)
  ScreenIndicators.draw_mode_indicator(number_of_modes, current_mode)
  
  -- Draw screen indicator on the left (5 screens) - only show in mode 2
  if current_mode == 2 then
    ScreenIndicators.draw_screen_indicator(number_of_screens, current_screen)
  end
  
  -- Draw main content based on mode
  screen.level(15)
  screen.font_face(1)
  screen.font_size(8)
  
  if current_mode == 1 then
    screen.move(64, 32)
    screen.text_center("Mode 1: Record")
  elseif current_mode == 2 then
    screen.move(64, 20)
    screen.text_center("Mode 2: Voice")
    screen.move(64, 32)
    screen.text_center("Screen " .. current_screen .. " of " .. number_of_screens)
    
    -- Show horizontal indicators at bottom as an example
    ScreenIndicators.draw_horizontal_indicator(number_of_screens, current_screen, 56)
  elseif current_mode == 3 then
    screen.move(64, 32)
    screen.text_center("Mode 3: Delay")
    
    -- Show circular indicators as an example
    ScreenIndicators.draw_circular_indicators(8, current_screen, 64, 32, 20, {dot_size = 2})
  end
  
  -- Instructions
  screen.level(5)
  screen.font_size(6)
  screen.move(64, screen_h - 2)
  screen.text_center("E1: mode | E2/E3: screen")
  
  screen.update()
end

-- Key handler
function key(n, z)
  if z == 1 then
    redraw()
  end
end

-- Encoder handler
function enc(n, delta)
  if n == 1 then
    -- Switch modes
    current_mode = util.clamp(current_mode + delta, 1, number_of_modes)
    current_screen = 1  -- Reset to first screen when changing modes
  elseif n == 2 or n == 3 then
    -- Switch screens (only in mode 2 or 3)
    if current_mode == 2 then
      current_screen = util.clamp(current_screen + delta, 1, number_of_screens)
    elseif current_mode == 3 then
      current_screen = util.clamp(current_screen + delta, 1, 8)
    end
  end
  redraw()
end


