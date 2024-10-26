-- "Rounds" step-based sampler
-- Randomize & modulate: steps,
-- semitones, direction, octave,
-- fifth, panning, reverse,
-- attack/release, amplitude.
--
-- Screens:
-- 1. Step Circle: active steps,
-- adjust steps, direction, play/stop.
-- 2. Envelope: attack/release,
-- adjust & randomize.
-- 3. Pan/Amp: pan particles,
-- amp ripple, adjust & randomize.
-- 4. Fifth/Octave: arcs, adjust
-- semitones, randomize fifth/octave.
--
-- Encoders:
-- - Enc1: change screen (1-4).
-- - Enc2: adjust parameters.
-- - Enc3: adjust step division.
-- - Shift + Enc3: adjust steps.
-- - Shift + Enc2: adjust semitones (screen 4).
--
-- Keys:
-- - Key1: shift (fine adjust).
-- - Key2: play/stop.
-- - Key3: open file (screen 1).

engine.name = 'Rounds'
local g = grid.connect()
local EnvGraph = require "envgraph"
local FilterGraph = require "filtergraph"
local fileselect = require('fileselect')
utils = include('lib/utils')

local screen_w, screen_h = 128, 64
local circle_x, circle_y = screen_w / 2, screen_h / 2
local outer_circle_radius, inner_circle_radius = 28, 18
local direction_symbols = { ">", "<", "~" }

local selected_voice_screen = 1
local number_of_screens = 5
local screen_mode = 1
local shift = false
local fileselect_active = false
local selected_file_path = 'none'

-- Step and Pattern Configuration
local steps = 16
local active_step = 0
local active_pattern_step = 1

-- Timing and Clock
local clock_id = 0

-- Envelope and Filter Graphics
local env_graph
local filter_graph




function init()
  init_polls()
  init_params()

  init_env_graph()
  init_filter_graph()

  update_delay_time()

  g.key = function(x, y, z)
    grid_key(x, y, z)
  end
end

function init_polls()
  metro_screen_refresh = metro.init(function(stage) redraw() end, 1 / 60)
  metro_screen_refresh:start()
end

function init_params()
  params:add_separator("Rounds")
  params:add_group("Global", 7)
  params:add_file("sample", "Sample")
  params:set_action("sample", function(file) engine.bufferPath(file) end)

  params:add_binary("play_stop", "Play/Stop", "toggle", 0)
  params:set_action("play_stop", function(value)
    if value == 1 then
      clock_id = clock.run(start_sequence)
    else
      clock.cancel(clock_id)
    end
  end)

  params:add_option("step_division", "Step Division", utils.division_factors, 4)

  params:add_option("steps", "Steps", { 4, 8, 16, 32, 64 }, 3)
  params:set_action("steps", function(value)
    steps = ({ 4, 8, 16, 32, 64 })[value]
    engine.steps(steps)
  end)

  params:add_number("pattern", "Pattern", 1, #utils.patterns, 1)

  params:add_number("semitones", "Semitones", -24, 24, 0)
  params:set_action("semitones", function(value)
    engine.semitones(value)
  end)

  params:add_option("direction", "Playback Direction", { "Forward", "Reverse", "Random" }, 1)

  params:add_group("Envelope/Filter", 7)
  params:add_binary("env", "Enable Envelope", "toggle", 1)
  params:set_action("env", function(value) engine.useEnv(value) end)

  params:add_taper("attack", "Attack Time", 0, 1, 0.001, 0)
  params:set_action("attack", function(value)
    engine.attack(value)
    update_env_graph()
  end)

  params:add_taper("release", "Release Time", 0, 5, 0.5, 0)
  params:set_action("release", function(value)
    engine.release(value)
    update_env_graph()
  end)

  params:add_control("lowpass_freq", "Lowpass Frequency", controlspec.new(10, 20000, 'exp', 1, 20000, "hz"))
  params:set_action('lowpass_freq', function(value) engine.lowpassFreq(value) end)

  params:add_taper('resonance', 'Resonance', 0.01, 1, 0)
  params:set_action('resonance', function(value) engine.resonance(1 - value) end)

  params:add_taper('highpass_freq', 'Highpass Frequency', 1, 20000, 1)
  params:set_action('highpass_freq', function(value) engine.highpassFreq(value) end)

  params:add_taper("lowpass_env_strength", "Lowpass Env Strength", 0, 1, 0, 0)
  params:set_action("lowpass_env_strength", function(value) engine.lowpassEnvStrength(value) end)

  params:add_group("Randomization", 9)
  params:add_taper("random_octave", "Randomize Octave", 0, 1, 0, 0)
  params:set_action("random_octave", function(value) engine.randomOctave(value) end)

  params:add_taper("random_fifth", "Randomize Fifth", 0, 1, 0, 0)
  params:set_action("random_fifth", function(value) engine.randomFith(value) end)

  params:add_taper("random_pan", "Randomize Pan", 0, 1, 0, 0)
  params:set_action("random_pan", function(value) engine.randomPan(value) end)

  params:add_taper("random_reverse", "Randomize Reverse", 0, 1, 0, 0)
  params:set_action("random_reverse", function(value) engine.randomReverse(value) end)

  params:add_taper("random_attack", "Randomize Attack", 0, 1, 0, 0)
  params:set_action("random_attack", function(value) engine.randomAttack(value) end)

  params:add_taper("random_release", "Randomize Release", 0, 1, 0, 0)
  params:set_action("random_release", function(value) engine.randomRelease(value) end)

  params:add_taper("random_amp", "Randomize Amplitude", 0, 1, 0, 0)
  params:set_action("random_amp", function(value) engine.randomAmp(value) end)

  params:add_taper('random_lowpass', 'Randomize Lowpass', 0, 1, 0, 0)
  params:set_action('random_lowpass', function(value) engine.randomLowPass(value) end)

  params:add_taper('random_highpass', 'Randomize Highpass', 0, 1, 0, 0)
  params:set_action('random_highpass', function(value) engine.randomHiPass(value) end)

  init_delay_params()
  init_steps_as_params()
end

function init_delay_params()
  params:add_group("Delay", 10)

  params:add_taper("delay_mix", "Mix", 0, 1, 0.5, 0)
  params:set_action("delay_mix", function(value) engine.mix(value) end)

  params:add_binary('delay_sync', 'Sync', 'toggle', 1)

  params:add_option("delay_division", "Division", { "1/1", "1/2", "1/4", "1/8", "1/16", "1/32" }, 3)
  params:set_action("delay_division", function(value)
    update_delay_time()
  end)

  params:add_taper("delay_time", "Time (non-synced)", 0, 8, 0.5, 0.001)
  params:set_action("delay_time", function(value)
    if params:get("delay_sync") == 0 then
      engine.delay(value)
    end
  end)

  params:add_taper("delay_feedback", "Feedback", 0, 20, 1, 0)
  params:set_action("delay_feedback", function(value) engine.time(value) end)

  params:add_control("delay_lowpass", "Lowpass Frequency", controlspec.new(10, 20000, 'exp', 1, 20000, "hz"))
  params:set_action('delay_lowpass', function(value) engine.lpf(value) end)

  params:add_control("delay_highpass", "Highpass Frequency", controlspec.new(1, 20000, 'exp', 1, 20, "hz"))
  params:set_action("delay_highpass", function(value) engine.hpf(value) end)

  params:add_taper("wiggle_rate", "Wiggle Rate", 0, 20, 0, 0.8)
  params:set_action("wiggle_rate", function(value) engine.w_rate(value) end)

  params:add_taper("wiggle_depth", "Wiggle Depth", 0, 1, 0, 0)
  params:set_action("wiggle_depth", function(value) engine.w_depth(value) end)

  params:add_taper("rotate", "Rotate", 0, 1, 0.5, 0)
  params:set_action("rotate", function(value) engine.rotate(value) end)
end

function init_steps_as_params()
  params:add_separator("Steps")
  for i = 1, 64 do
    params:add_group("step_" .. i, 7)
    params:add_separator("step: " .. i)

    params:add_binary("active_" .. i, "active_" .. i, "toggle", 1)
    params:set_action("active_" .. i, function(value) engine.active(i, value) end)

    params:add_taper("rate" .. i, "rate" .. i, -4, 4, 1, 0)
    params:set_action("rate" .. i, function(value) engine.rate(i, value) end)

    params:add_taper("amp" .. i, "amp" .. i, 0, 1, 1, 0)
    params:set_action("amp" .. i, function(value) engine.amp(i, value) end)

    params:add_binary("reverse" .. i, "reverse" .. i, "toggle", 0)
    params:set_action("reverse" .. i, function(value) engine.reverse(i, value) end)

    params:add_taper("pan" .. i, "pan" .. i, -1, 1, 0.0, 0)
    params:set_action("pan" .. i, function(value) engine.pan(i, value) end)

    params:add_number("segment" .. i, "segment" .. i, 1, steps, i)
    params:set_action("segment" .. i, function(value) engine.segment(i, value) end)
  end
end

function redraw()
  if fileselect_active then return end
  screen.clear()

  if screen_mode == 1 then
    draw_screen_indicator()
    if selected_voice_screen == 1 then
      draw_step_circle(steps, active_step)
    elseif selected_voice_screen == 2 then
      draw_envelope_screen()
    elseif selected_voice_screen == 3 then
      draw_random_pan_amp_screen()
    elseif selected_voice_screen == 4 then
      draw_random_fifth_octave_screen()
    elseif selected_voice_screen == 5 then
      draw_filter_screen()
    end
  elseif screen_mode == 2 then
    draw_delay_screen()
  end


  screen.update()
end

function draw_screen_indicator()
  local indicator_x = 1
  local indicator_height = 3
  local indicator_spacing = 2
  local start_y = (screen_h - (indicator_height + indicator_spacing) * number_of_screens) / 2

  for i = 1, number_of_screens do
    local y_position = start_y + (i - 1) * (indicator_height + indicator_spacing)
    if i == selected_voice_screen and screen_mode == 1 then
      screen.level(15)
    else
      screen.level(3)
    end
    screen.move(indicator_x, y_position)
    screen.line_rel(0, indicator_height)
    screen.stroke()
  end

  -- Draw indicator for FX screens
  if screen_mode == 2 then
    screen.level(15)
    screen.move(screen_w - 8, screen_h / 2 - indicator_height / 2)
    screen.line_rel(0, indicator_height)
    screen.stroke()
  end
end

function draw_delay_screen()
  local center_x = screen_w / 2
  local center_y = screen_h / 2
  local base_radius = 25
  local trail_decay = 0.9

  local delay_time
  if params:get("delay_sync") == 1 then
    delay_time = clock.get_beat_sec() * utils.division_factors[params:get("delay_division")] * 4
  else
    delay_time = params:get("delay_time")
  end

  -- Set rotation speed proportional to delay time
  local rotation_speed = math.pi * 2 * delay_time / 5
  local feedback = params:get("delay_feedback")

  -- Map mix to dot size range from 1 to 3
  local mix = params:get("delay_mix")
  local dot_size = 1 + (mix * 2)
  -- Adjust rotation effect based on rotate parameter
  local rotate = params:get("rotate")
  local rotate_offset = rotate * math.pi * 2 -- Full rotation offset based on rotate value

  -- Adjust radius based on rotate parameter within a ±15% range
  local radius_variation = base_radius * 0.15 * (rotate - 0.5) * 2 -- Scale between -15% and +15%
  local radius = base_radius + radius_variation

  -- Calculate number of waveform points based on delay feedback
  local num_points = math.floor(20 + feedback * 10)

  -- Draw radial waveform with trails
  for i = 1, num_points do
    -- Calculate angle with rotation offset and trail fade level
    local angle = i * (math.pi * 2 / num_points) + rotation_speed * clock.get_beats() + rotate_offset
    local trail_level = 15 * (trail_decay ^ i) -- Using fixed max brightness

    -- Calculate radial offset based on feedback
    local offset = radius + math.sin(angle * feedback) * 8

    -- Set brightness for trail effect
    screen.level(math.floor(trail_level))

    -- Calculate positions
    local x = center_x + math.cos(angle) * offset
    local y = center_y + math.sin(angle) * offset

    -- Draw the dot with variable size based on mix
    screen.circle(x, y, dot_size)
    screen.fill()
  end

  screen.update()
end

function draw_random_pan_amp_screen()
  screen.clear()
  local num_particles = 10
  local particle_radius = 1.5
  local particle_dispersion = screen_h * 0.6
  local pan_center_x = screen_w / 4 + 4
  local center_y = screen_h / 2

  local random_pan_value = params:get("random_pan")
  local pan_spread = (screen_w / 6) * random_pan_value

  if random_pan_value > 0 then
    for i = 1, num_particles do
      local particle_x = pan_center_x + (math.random() * 2 - 1) * pan_spread
      local particle_y = center_y + (math.random() * particle_dispersion - (particle_dispersion / 2))
      local brightness = math.max(1, math.floor(random_pan_value * 15))
      screen.level(brightness)
      screen.circle(particle_x, particle_y, particle_radius)
      screen.fill()
    end
  else
    screen.level(1)
    screen.rect(pan_center_x - 1, center_y - particle_dispersion / 2, 3, particle_dispersion)
    screen.fill()
  end

  -- Amplitude ripple effect
  local ripple_radius_max = screen_h / 4
  local ripple_radius_min = 3
  local amp_center_x = screen_w * 3 / 4
  local random_amp_value = params:get("random_amp")
  local amp_max_radius = ripple_radius_min + (ripple_radius_max * random_amp_value)

  for i = 1, 4 do
    local ripple_radius = ripple_radius_min + (amp_max_radius * (i / 4))
    screen.level(15 - (i * 3))
    screen.circle(amp_center_x, center_y, ripple_radius)
    screen.stroke()
  end

  screen.update()
end

function draw_random_fifth_octave_screen()
  screen.clear()
  local arc_center_x = screen_w / 2
  local arc_center_y = screen_h / 2
  local fifth_arc_radius_min = 10
  local fifth_arc_radius_max = 30
  local octave_arc_radius_min = 15
  local octave_arc_radius_max = 35

  local random_fifth_value = params:get("random_fifth")
  local random_octave_value = params:get("random_octave")
  local semitones = params:get("semitones")
  local total_arcs = 6

  local semitone_range = 48
  local semitone_offset = (semitones / semitone_range) * screen_h / 2

  for i = 1, total_arcs do
    local arc_radius = fifth_arc_radius_min + (i / total_arcs) * (fifth_arc_radius_max - fifth_arc_radius_min)
    local brightness = math.max(1, math.floor((random_fifth_value * i / total_arcs) * 15))
    screen.level(brightness)
    screen.arc(arc_center_x, arc_center_y, arc_radius, -math.pi, 0)
    screen.stroke()
  end

  for i = 1, total_arcs do
    local arc_radius = octave_arc_radius_min + (i / total_arcs) * (octave_arc_radius_max - octave_arc_radius_min)
    local brightness = math.max(1, math.floor((random_octave_value * i / total_arcs) * 15))
    screen.level(brightness)
    screen.arc(arc_center_x, arc_center_y, arc_radius, 0, math.pi)
    screen.stroke()
  end

  local bar_x_left = 10
  local bar_x_right = 118
  local bar_height = 8
  local bar_width = 1
  local bar_y_center = screen_h / 2
  local bar_y = bar_y_center - semitone_offset

  screen.level(15)
  screen.rect(bar_x_left, bar_y - bar_height / 2, bar_width, bar_height)
  screen.fill()

  screen.rect(bar_x_right, bar_y - bar_height / 2, bar_width, bar_height)
  screen.fill()

  screen.update()
end

function draw_filter_screen()
  filter_graph:redraw()

  -- Draw progress bars below filter graph
  local bar_max_width = 36
  local bar_height = 3
  local bar_spacing = 4
  local bar_y = circle_y + 21 -- Position below the filter graph

  -- Lowpass Env Strength on the left
  local lowpass_env_strength_value = params:get("lowpass_env_strength")
  local env_strength_bar_width = bar_max_width * lowpass_env_strength_value
  local env_strength_bar_x = (screen_w / 2) - bar_max_width - bar_spacing

  screen.level(15)
  screen.rect(env_strength_bar_x, bar_y, env_strength_bar_width, bar_height)
  screen.fill()

  screen.level(1)
  screen.rect(env_strength_bar_x, bar_y, bar_max_width, bar_height)
  screen.stroke()

  -- Randomize Lowpass on the right
  local random_lowpass_value = params:get("random_lowpass")
  local random_lowpass_bar_width = bar_max_width * random_lowpass_value
  local random_lowpass_bar_x = (screen_w / 2) + bar_spacing

  screen.level(15)
  screen.rect(random_lowpass_bar_x, bar_y, random_lowpass_bar_width, bar_height)
  screen.fill()

  screen.level(1)
  screen.rect(random_lowpass_bar_x, bar_y, bar_max_width, bar_height)
  screen.stroke()
end

function draw_envelope_screen()
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
end

function draw_step_circle(steps, current_step)
  draw_step_visual(steps, current_step)
  draw_direction_symbol()
  draw_step_division()
  draw_step_count(steps)
  draw_pattern_grid()
end

function draw_step_visual(steps, current_step)
  local angle_offset = -math.pi * 2 / 3

  for i = 1, steps do
    local is_active = params:get("active_" .. i) == 1
    local brightness = is_active and ((i == current_step) and 15 or 4) or 1

    local angle_start = (i / steps) * math.pi * 2 + angle_offset
    local angle_end = ((i + 1) / steps) * math.pi * 2 + angle_offset

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
end

function draw_direction_symbol()
  local direction = params:get("direction")
  local symbol = direction_symbols[direction]
  local is_playing = params:get("play_stop") == 1
  local text_brightness = is_playing and 15 or 1

  screen.level(text_brightness)
  screen.font_face(4)
  screen.font_size(15)
  screen.move(4, screen_h - 4)
  screen.text(symbol)
end

function draw_step_division()
  local step_division = params:get("step_division")
  local division_text = "1/" .. math.floor(1 / utils.division_factors[step_division])

  screen.level(10)
  screen.font_face(1)
  screen.font_size(8)
  screen.move(screen_w - 4, 8)
  screen.text_right(division_text)
end

function draw_step_count(steps)
  screen.level(10)
  screen.font_size(8)
  screen.font_face(1)
  screen.move(screen_w - 4, screen_h - 5)
  screen.text_right(steps)
end

function draw_pattern_grid()
  local current_pattern = utils.patterns[params:get("pattern")]
  local pattern_length = #current_pattern
  local row_length = 4
  local pattern_x = 5
  local pattern_y = 5
  local cell_size = 3
  local cell_spacing = 2
  local pattern_index = active_pattern_step

  for i = 1, pattern_length do
    local brightness = current_pattern[i] == 1 and (i == pattern_index and 15 or 5) or (i == pattern_index and 3 or 1)
    local x = pattern_x + ((i - 1) % row_length) * (cell_size + cell_spacing)
    local y = pattern_y + math.floor((i - 1) / row_length) * (cell_size + cell_spacing)

    screen.level(brightness)
    screen.rect(x, y, cell_size, cell_size)
    screen.fill()
  end
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

function init_filter_graph()
  local filter_width = 80
  local filter_height = 40
  local filter_x = circle_x - (filter_width / 2)
  local filter_y = circle_y - (filter_height / 2) - 5

  local lowpass_freq = params:get("lowpass_freq")
  local resonance = params:get("resonance")

  filter_graph = FilterGraph.new(10, 20000, -60, 32.5, 1, 12, lowpass_freq, resonance)

  filter_graph:set_position_and_size(filter_x, filter_y, filter_width, filter_height)
  filter_graph:set_show_x_axis(true)
  filter_graph:set_active(true)
end

function update_env_graph()
  local attack = params:get("attack")
  local release = params:get("release")
  env_graph:edit_ar(attack, release)
end

function update_filter_graph()
  local lowpass_freq = params:get("lowpass_freq")
  local resonance = params:get("resonance")
  filter_graph:edit(nil, nil, lowpass_freq, resonance)
end

function key(n, z)
  if n == 1 then
    shift = (z == 1)
  elseif n == 2 and z == 1 then
    local current_state = params:get("play_stop")
    params:set("play_stop", 1 - current_state)
  elseif n == 3 and z == 1 then
    if selected_voice_screen == 1 then
      fileselect_active = true
      fileselect.enter(_path.audio, file_select_callback, "audio")
    end
  end
end

function enc(n, delta)
  if n == 1 then
    if shift then
      screen_mode = utils.clamp(screen_mode + delta, 1, 2)
    else
      if screen_mode == 1 then
        selected_voice_screen = utils.clamp(selected_voice_screen + delta, 1, number_of_screens)
      end
    end
  else
    if screen_mode == 1 then
      if selected_voice_screen == 1 then
        handle_step_circle_enc(n, delta)
      elseif selected_voice_screen == 2 then
        handle_envelope_enc(n, delta)
      elseif selected_voice_screen == 3 then
        handle_pan_amp_enc(n, delta)
      elseif selected_voice_screen == 4 then
        handle_fifth_octave_enc(n, delta)
      elseif selected_voice_screen == 5 then
        handle_filter_enc(n, delta)
      end
    elseif screen_mode == 2 then
      handle_delay_screen_enc(n, delta)
    end
  end
end

function handle_step_circle_enc(n, delta)
  if n == 2 then
    if shift then
      utils.handle_param_change("direction", delta, 1, 3, 1, "lin")
    else
      utils.handle_param_change("pattern", delta, 1, #utils.patterns, 1, "lin")
    end
  elseif n == 3 then
    if shift then
      local new_steps = utils.clamp(steps + delta, 4, 64)
      params:set("steps", math.log(new_steps) / math.log(2) - 1)
      steps = new_steps
      engine.steps(steps)
    else
      utils.handle_param_change("step_division", delta, 1, #utils.division_factors, 1, "lin")
    end
  end
end

function handle_envelope_enc(n, delta)
  if shift then
    if n == 2 then utils.handle_param_change("random_attack", delta, 0, 1, 0.01, "lin") end
    if n == 3 then utils.handle_param_change("random_release", delta, 0, 1, 0.01, "lin") end
  else
    if n == 2 then
      utils.handle_param_change("attack", delta, 0.001, 1, 0.001, "lin")
      update_env_graph()
    end
    if n == 3 then
      utils.handle_param_change("release", delta, 0.001, 5, 0.01, "lin")
      update_env_graph()
    end
  end
end

function handle_pan_amp_enc(n, delta)
  if n == 2 then utils.handle_param_change("random_pan", delta, 0, 1, 0.01, "lin") end
  if n == 3 then utils.handle_param_change("random_amp", delta, 0, 1, 0.01, "lin") end
end

function handle_delay_screen_enc(n, delta)
  if shift then
    if n == 2 then
      params:delta("delay_mix", delta)
    elseif n == 3 then
      params:delta("rotate", delta)
    end
  else
    if n == 2 then
      if params:get("delay_sync") == 1 then
        params:delta("delay_division", delta)
      else
        params:delta("delay_time", delta)
      end
    elseif n == 3 then
      params:delta("delay_feedback", delta)
    end
  end
end

function handle_fifth_octave_enc(n, delta)
  if shift then
    if n == 2 then utils.handle_param_change("semitones", delta, -24, 24, 1, "lin") end
  else
    if n == 2 then utils.handle_param_change("random_fifth", delta, 0, 1, 0.01, "lin") end
    if n == 3 then utils.handle_param_change("random_octave", delta, 0, 1, 0.01, "lin") end
  end
end

function handle_filter_enc(n, delta)
  if shift then
    if n == 2 then
      utils.handle_param_change("lowpass_env_strength", delta, 0, 1, 0.01, "lin")
    elseif n == 3 then
      utils.handle_param_change("random_lowpass", delta, 0, 1, 0.01, "lin")
    end
  else
    if n == 2 then
      -- Use exponential scaling for lowpass frequency
      utils.handle_param_change("lowpass_freq", delta, 10, 20000, 0.05, "exp")
      update_filter_graph()
    elseif n == 3 then
      -- Use linear scaling for resonance
      utils.handle_param_change("resonance", delta, 0.01, 1, 0.01, "lin")
      update_filter_graph()
    end
  end
end

function file_select_callback(file_path)
  fileselect_active = false

  if file_path ~= 'cancel' then
    local split_at = string.match(file_path, "^.*()/")
    selected_file_path = string.sub(file_path, 9, split_at)
    selected_file_path = util.trim_string_to_width(selected_file_path, 128)
    selected_file = string.sub(file_path, split_at + 1)
    params:set("sample", file_path)
    engine.bufferPath(file_path)
  end

  redraw()
end

function clock.transport.start()
  params:set("play_stop", 1)
end

function clock.transport.stop()
  params:set("play_stop", 0)
end

function clock.tempo_change_handler()
  update_delay_time()
end

function start_sequence()
  local i = 1
  local pattern_index = 1

  while true do
    local current_pattern = utils.patterns[params:get("pattern")]
    local pattern_length = #current_pattern
    local direction = params:get("direction")
    local index = 0

    if direction == 1 then
      index = i
    elseif direction == 2 then
      index = steps - i + 1
    elseif direction == 3 then
      index = math.random(1, steps)
    end

    active_pattern_step = pattern_index

    if current_pattern[pattern_index] == 1 then
      local active = params:get("active_" .. index) == 1
      if active then
        local start_segment = params:get("segment" .. index)
        local rate = params:get("rate" .. index)
        local reverse = params:get("reverse" .. index)
        local amp = params:get("amp" .. index)
        local pan = params:get("pan" .. index)
        engine.play(start_segment, amp, rate, pan, reverse)

        local step_division = params:get("step_division")
        clock.sync(utils.division_factors[step_division] * 4)

        active_step = index
      end
    else
      local step_division = params:get("step_division")
      clock.sync(utils.division_factors[step_division] * 4)
    end

    i = i + 1
    pattern_index = pattern_index + 1

    if i > steps then i = 1 end
    if pattern_index > pattern_length then pattern_index = 1 end
  end
end

function update_delay_time()
  local beat_sec = clock.get_beat_sec()
  local division_factor = utils.division_factors[params:get("delay_division")]

  local delay_time = beat_sec * division_factor * 4 -- synced time
  print("sync delay time: " .. delay_time)

  -- Set engine delay if sync is enabled
  if params:get("delay_sync") == 1 then
    engine.delay(delay_time)
  end
end
