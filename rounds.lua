--_ Rounds

engine.name = 'Rounds'
local g = grid.connect()
local EnvGraph = require "envgraph"
local env_graph

local selected_screen = 1
local shift = false

steps = 16
active_step = 0
sync = 0
clock_id = 0

local division_factors = {
  [1] = 1 / 32,
  [2] = 1 / 16,
  [3] = 1 / 8,
  [4] = 1 / 4,
  [5] = 1 / 2,
  [6] = 1,
}

local screen_w = 128
local screen_h = 64
local outer_circle_radius = 28
local inner_circle_radius = 18
local circle_x = screen_w / 2
local circle_y = screen_h / 2
local direction_symbols = { ">", "<", "~" }

function draw_borders_if_shift()
  if shift then
    screen.level(1)
    screen.move(0, 0)
    screen.line(screen_w, 1)
    screen.stroke()
    screen.move(0, screen_h)
    screen.line(screen_w, screen_h)
    screen.stroke()
  end
end

function draw_step_circle(steps, active_step)
  screen.clear()
  draw_borders_if_shift()

  local angle_offset = -math.pi * 2 / 3

  for i = 1, steps do
    local angle_start = (i / steps) * math.pi * 2 + angle_offset
    local angle_end = ((i + 1) / steps) * math.pi * 2 + angle_offset
    local brightness = (i == active_step) and 15 or 1

    local x1 = circle_x + math.cos(angle_start) * outer_circle_radius
    local y1 = circle_y + math.sin(angle_start) * outer_circle_radius
    local x2 = circle_x + math.cos(angle_end) * outer_circle_radius
    local y2 = circle_y + math.sin(angle_end) * outer_circle_radius

    screen.level(brightness)
    screen.move(circle_x, circle_y)
    screen.line(x1, y1)
    screen.line(x2, y2)
    screen.fill()
  end

  screen.level(0)
  screen.circle(circle_x, circle_y, inner_circle_radius)
  screen.fill()

  local direction = params:get("direction")
  local symbol = direction_symbols[direction]
  local is_playing = params:get("play/stop") == 1
  local text_brightness = is_playing and 15 or 1

  screen.font_face(4)
  local text_height = 15
  screen.font_size(text_height)
  local centered_y = (screen_h / 2) + (text_height / 4)

  screen.level(text_brightness)
  screen.move(4, centered_y)
  screen.text(symbol)

  screen.level(15)
  screen.move(screen_w - text_height, circle_y + (text_height / 4))
  screen.text(steps)

  screen.update()
end

function redraw()
  if selected_screen == 1 then
    draw_step_circle(steps, active_step)
  elseif selected_screen == 2 then
    draw_envelope_screen()
  end
end

function draw_envelope_screen()
  screen.clear()
  draw_borders_if_shift()

  env_graph:redraw()

  local bar_max_width = 36
  local random_attack_value = params:get("random_attack")
  local random_release_value = params:get("random_release")
  local attack_bar_width = bar_max_width * random_attack_value
  local release_bar_width = bar_max_width * random_release_value

  local bar_height = 3
  local bar_spacing = 4
  local bar_y = circle_y + 21
  local attack_bar_x = (screen_w / 2) - bar_max_width - bar_spacing
  local release_bar_x = (screen_w / 2) + bar_spacing

  screen.level(15)
  screen.rect(attack_bar_x, bar_y, attack_bar_width, bar_height)
  screen.fill()

  screen.level(1)
  screen.rect(attack_bar_x, bar_y, bar_max_width, bar_height)
  screen.stroke()

  screen.level(15)
  screen.rect(release_bar_x, bar_y, release_bar_width, bar_height)
  screen.fill()

  screen.level(1)
  screen.rect(release_bar_x, bar_y, bar_max_width, bar_height)
  screen.stroke()

  screen.update()
end

function init_env_graph()
  local env_width = 80
  local env_height = 40
  local env_x = circle_x - (env_width / 2)
  local env_y = circle_y - (env_height / 2) - 5

  local release = params:get("release")
  local attack = params:get("attack")

  env_graph = EnvGraph.new_ar(0, 1, 0, 1, attack, release, 1)
  env_graph:set_position_and_size(env_x, env_y, env_width, env_height)
  env_graph:set_show_x_axis(true)
end

function update_env_graph()
  local attack = params:get("attack")
  local release = params:get("release")
  env_graph:edit_ar(attack, release)
end

function key(n, z)
  if n == 1 then
    shift = (z == 1)
  elseif n == 2 and z == 1 then
    local current_state = params:get("play/stop")
    params:set("play/stop", 1 - current_state)
  end
end

function enc(n, delta)
  if selected_screen == 1 then
    if n == 1 then
      selected_screen = util.clamp(selected_screen + delta, 1, 2)
    elseif n == 2 then
      local direction = params:get("direction")
      params:set("direction", util.clamp(direction + delta, 1, 3))
    elseif n == 3 then
      local new_steps = util.clamp(steps + delta, 4, 64)
      params:set("steps", math.log(new_steps) / math.log(2) - 1)
      steps = new_steps
      engine.steps(steps)
    end
  elseif selected_screen == 2 then
    if shift then
      if n == 2 then
        local random_attack = params:get("random_attack") + delta * 0.01
        params:set("random_attack", util.clamp(random_attack, 0, 1))
      elseif n == 3 then
        local random_release = params:get("random_release") + delta * 0.01
        params:set("random_release", util.clamp(random_release, 0, 1))
      end
    else
      if n == 1 then
        selected_screen = util.clamp(selected_screen + delta, 1, 2)
      elseif n == 2 then
        local attack = params:get("attack") + delta * 0.001
        params:set("attack", util.clamp(attack, 0.001, 1))
        update_env_graph()
      elseif n == 3 then
        local release = params:get("release") + delta * 0.01
        params:set("release", util.clamp(release, 0.001, 5))
        update_env_graph()
      end
    end
  end
end

function init()
  init_polls()
  init_params()

  init_env_graph()

  g.key = function(x, y, z)
    grid_key(x, y, z)
  end
end

function init_params()
  params:add_separator("Rounds")
  params:add_file("sample", "sample")
  params:set_action("sample", function(file) engine.bufferPath(file) end)

  params:add_binary("play/stop", "play/stop", "toggle", 0)
  params:set_action("play/stop", function(value)
    if value == 1 then
      clock_id = clock.run(start_sequence)
    else
      clock.cancel(clock_id)
    end
  end)

  params:add_option("step_division", "Step Division", division_factors, 4)

  params:add_option("steps", "steps", { 4, 8, 16, 32, 64 }, 3)
  params:set_action("steps", function(value)
    steps = ({ 4, 8, 16, 32, 64 })[value]
    engine.steps(steps)
  end)

  params:add_number("semitones", "semitones", -24, 24, 0)
  params:set_action("semitones", function(value)
    engine.semitones(value)
  end)

  params:add_option("direction", "playback direction", { "forward", "reverse", "random" }, 1)

  params:add_separator("Env")
  params:add_binary("env", "env", "toggle", 1)
  params:set_action("env", function(value)
    engine.useEnv(value)
  end)

  params:add_taper("attack", "attack", 0, 1, 0.001, 0)
  params:set_action("attack", function(value)
    engine.attack(value)
    update_env_graph()
  end)

  params:add_taper("release", "release", 0, 5, 0.5, 0)
  params:set_action("release", function(value)
    engine.release(value)
    update_env_graph()
  end)

  params:add_separator("Randomization")
  params:add_taper("random_octave", "Random Octave", 0, 1, 0, 0)
  params:set_action("random_octave", function(value)
    engine.randomOctave(value)
  end)

  params:add_taper("random_fith", "Random Fifth", 0, 1, 0, 0)
  params:set_action("random_fith", function(value)
    engine.randomFith(value)
  end)

  params:add_taper("random_pan", "Random Pan", 0, 1, 0, 0)
  params:set_action("random_pan", function(value)
    engine.randomPan(value)
  end)

  params:add_taper("random_reverse", "Random Reverse", 0, 1, 0, 0)
  params:set_action("random_reverse", function(value)
    engine.randomReverse(value)
  end)

  params:add_taper("random_attack", "Random Attack", 0, 1, 0, 0)
  params:set_action("random_attack", function(value)
    engine.randomAttack(value)
  end)

  params:add_taper("random_release", "Random Release", 0, 1, 0, 0)
  params:set_action("random_release", function(value)
    engine.randomRelease(value)
  end)

  params:add_taper("random_amp", "Random Amp", 0, 1, 0, 0)
  params:set_action("random_amp", function(value)
    engine.randomAmp(value)
  end)

  init_delay_params()
  init_steps_as_params()
end

function init_delay_params()
  params:add_separator("Delay")

  params:add_taper("delay_mix", "delay_mix", 0, 1, 0.5, 0)
  params:set_action("delay_mix", function(value)
    engine.mix(value)
  end)

  params:add_taper("delay", "delay", 0, 8, 0.5, 0)
  params:set_action("delay", function(value)
    engine.delay(value)
  end)

  params:add_taper("delay_feedback", "delay_feedback", 0, 20, 1, 0)
  params:set_action("delay_feedback", function(value)
    engine.time(value)
  end)

  params:add_taper("lowpass", "lowpass", 1, 20000, 20000)
  params:set_action("lowpass", function(value)
    engine.lpf(value)
  end)

  params:add_number("highpass", "highpass", 1, 20000, 1)
  params:set_action("highpass", function(value)
    engine.hpf(value)
  end)

  params:add_taper("wigglerate", "wigglerate", 0, 20, 0, 0)
  params:set_action("wigglerate", function(value)
    engine.w_rate(value)
  end)

  params:add_taper("wiggleamount", "wiggleamount", 0, 1, 0, 0)
  params:set_action("wiggleamount", function(value)
    engine.w_depth(value)
  end)

  params:add_taper('rotate', 'rotate', 0, 1, 0.5, 0)
  params:set_action('rotate', function(value)
    engine.rotate(value)
  end)
end

function init_steps_as_params()
  params:add_separator("Steps")
  for i = 1, 64 do
    params:add_group("step_" .. i, 7)
    params:add_separator("step: " .. i)

    params:add_binary("active_" .. i, "active_" .. i, "toggle", 1)
    params:set_action("active_" .. i, function(value)
      engine.active(i, value)
    end)

    params:add_taper("rate" .. i, "rate" .. i, -4, 4, 1, 0)
    params:set_action("rate" .. i, function(value)
      engine.rate(i, value)
    end)

    params:add_taper("amp" .. i, "amp" .. i, 0, 1, 1, 0)
    params:set_action("amp" .. i, function(value)
      engine.amp(i, value)
    end)

    params:add_binary("reverse" .. i, "reverse" .. i, "toggle", 0)
    params:set_action("reverse" .. i, function(value)
      engine.reverse(i, value)
    end)

    params:add_taper("pan" .. i, "pan" .. i, -1, 1, 0.0, 0)
    params:set_action("pan" .. i, function(value)
      engine.pan(i, value)
    end)

    params:add_number("segment" .. i, "segment" .. i, 1, steps, i)
    params:set_action("segment" .. i, function(value)
      engine.segment(i, value)
    end)
  end
end

function init_polls()
  metro_screen_refresh = metro.init(function(stage) redraw() end, 1 / 80)
  metro_screen_refresh:start()
end

function clock.transport.start()
  if params:get("sync") == 1 then
    params:set("play/stop", 1)
  end
end

function clock.transport.stop()
  params:set("play/stop", 0)
end

function start_sequence()
  local i = 1
  while true do
    local direction = params:get("direction")
    local index = 0

    if direction == 1 then
      index = i
    elseif direction == 2 then
      index = steps - i + 1
    elseif direction == 3 then
      index = math.random(1, steps)
    end

    local start_segment = params:get("segment" .. index)
    local rate = params:get("rate" .. index)
    local reverse = params:get("reverse" .. index)
    local amp = params:get("amp" .. index)
    local pan = params:get("pan" .. index)
    engine.play(start_segment, amp, rate, pan, reverse)

    local step_devision = params:get("step_division")

    clock.sync(division_factors[step_devision] * 4)

    i = i + 1
    if i > steps then
      i = 1
    end

    active_step = index
  end
end
