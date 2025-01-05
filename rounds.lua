-- rounds is a clocked sample
-- manipulation environment

engine.name = 'Rounds'

local g = grid.connect()
local EnvGraph = require "envgraph"
local FilterGraph = require "filtergraph"

local fileselect = require('fileselect')

utils = include('lib/utils')
screens = include('lib/screens')

local screen_w, screen_h = 128, 64
local circle_x, circle_y = screen_w / 2, screen_h / 2

record_pointer = 0


local selected_voice_screen = 1
local number_of_screens = 5
local screen_modes = 3
local screen_mode = 2
local shift = false
local fileselect_active = false
local selected_file_path = 'none'

local show_info_banner = false
local metro_info_banner
local info_banner_text = ""

-- Step and Pattern Configuration
local steps = 16
local active_step = 0

-- Timing and Clock
local play_clock_id = 0
local reocord_clock_id = 0

-- Envelope and Filter Graphics
local env_graph
local filter_graph



-- INIT
function init()
  init_polls()
  init_params()

  init_env_graph()
  init_filter_graph()

  update_delay_time()
  update_record_time()

  g.key = function(x, y, z)
    grid_key(x, y, z)
  end
end

function init_polls()
  metro_screen_refresh = metro.init(function(stage) redraw() end, 1 / 60)
  metro_screen_refresh:start()

  record_pointer_poll = poll.set('recorderPos', function(value)
    if params:get("record") == 1 then
      record_pointer = value
    else
      record_pointer = 0
    end
  end)
  record_pointer_poll.time = 0.05
  record_pointer_poll:start()

  metro_info_banner = metro.init(function(stage)
    show_info_banner = false
    redraw()
  end, 0.6)
end

function init_params()
  params:add_separator("Rounds")
  global_params()
  recording_params()
  filter_params()
  randomization_params()
  delay_params()
  steps_as_params()
end

function global_params()
  params:add_group("Global", 7)
  params:add_file("sample", "Sample")
  params:set_action("sample", function(file) engine.bufferPath(file) end)

  params:add_binary("play_stop", "Play/Stop", "toggle", 0)
  params:set_action("play_stop", function(value)
    if value == 1 then
      play_clock_id = clock.run(start_sequence)
    else
      clock.cancel(play_clock_id)
    end
  end)

  params:add_option("step_division", "Step Division", utils.division_factors, 4)

  params:add_number("steps", "Steps", 1, 64, 16)
  params:set_action("steps", function(value)
    engine.steps(value)
  end)

  params:add_number("pattern", "Pattern", 1, #utils.patterns, 1)

  params:add_number("semitones", "Semitones", -24, 24, 0)
  params:set_action("semitones", function(value)
    engine.semitones(value)
  end)

  params:add_option("direction", "Playback Direction", { "Forward", "Reverse", "Random" }, 1)
end

function recording_params()
  params:add_group("Record", 4)

  params:add_binary('sample_or_record', 'Record Mode On', 'toggle', 0)
  params:set_action('sample_or_record', function(value)
    params:set("record", 0)
    engine.sampleOrRecord(value)
  end)

  params:add_binary('record', 'Record', 'toggle', 0)
  params:set_action('record', function(value)
    if value == 1 then
      record_clock_id = clock.run(start_recording)
    else
      clock.cancel(record_clock_id)
      engine.record(0)
    end
  end)

  params:add_binary('arm_record', 'Arm Record', 'toggle', 0)

  params:add_control('loop_length_in_beats', 'Loop in Beats', controlspec.new(1, 64, 'lin', 1, 16, "beats"))
  params:set_action('loop_length_in_beats', function(value)
    update_record_time()
  end)
end

function filter_params()
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
end

function randomization_params()
  params:add_group("Randomization", 10)
  params:add_taper("random_octave", "Randomize Octave", 0, 1, 0, 0)
  params:set_action("random_octave", function(value) engine.randomOctave(value) end)

  params:add_taper("random_fifth", "Randomize Fifth", 0, 1, 0, 0)
  params:set_action("random_fifth", function(value) engine.randomFith(value) end)

  params:add_option("random_scale", "Random Scale", utils.scale_names, 7)

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
end

function delay_params()
  params:add_group("Delay", 11)

  params:add_taper("delay_mix", "Mix", 0, 1, 0.2, 0)
  params:set_action("delay_mix", function(value) engine.mix(value) end)

  params:add_binary('delay_sync', 'Sync', 'toggle', 1)

  params:add_option("delay_subdivision_type", "Subdivision Type", { "Straight", "Dotted", "Triplet" }, 1)
  params:set_action("delay_subdivision_type", function(value)
    update_delay_time()
  end)

  params:add_option("delay_division", "Division", utils.delay_divisions_as_strings, 4)
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

function steps_as_params()
  params:add_separator("Steps")
  for i = 1, 64 do
    params:add_group("step_" .. i, 7)
    params:add_separator("step: " .. i)

    params:add_binary("active_" .. i, "active_" .. i, "toggle", 1)
    params:set_action("active_" .. i, function(value) engine.active(i, value) end)

    params:add_taper("rate" .. i, "rate" .. i, -4, 4, 1, 0)

    params:add_taper("amp" .. i, "amp" .. i, 0, 1, 1, 0)

    params:add_binary("reverse" .. i, "reverse" .. i, "toggle", 0)

    params:add_taper("pan" .. i, "pan" .. i, -1, 1, 0.0, 0)

    params:add_number("segment" .. i, "segment" .. i, 1, steps, i)
  end
end

-- SCREENS
function redraw()
  if fileselect_active then return end
  screen.clear()

  -- Draw the main screen components
  screens.draw_mode_indicator(screen_mode)

  if screen_mode == 2 then
    screens.draw_screen_indicator(number_of_screens, selected_voice_screen, screen_mode)
    if selected_voice_screen == 1 then
      screens.draw_step_circle(steps, active_step)
    elseif selected_voice_screen == 2 then
      draw_envelope_screen()
    elseif selected_voice_screen == 3 then
      screens.draw_random_pan_amp_screen()
    elseif selected_voice_screen == 4 then
      screens.draw_random_fifth_octave_screen()
    elseif selected_voice_screen == 5 then
      draw_filter_screen()
    end
  elseif screen_mode == 3 then
    screens.draw_delay_screen()
  elseif screen_mode == 1 then
    screens.draw_tape_recorder(record_pointer)
  end

  -- Draw the info banner if active
  if show_info_banner then
    draw_info_banner()
  end

  screen.update()
end

local banner_position = "bottom_center" -- Default position

function set_show_info_banner(message, position)
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

function draw_info_banner()
  if not show_info_banner then return end

  local min_banner_width = 40
  local padding = 5
  local banner_height = 10

  -- Measure the text width
  local text_width = screen.text_extents(info_banner_text)
  local banner_width = math.max(text_width + padding, min_banner_width)

  local banner_x, banner_y

  -- Calculate banner position based on selected option
  if banner_position == "center" then
    banner_x = (screen_w - banner_width) / 2
    banner_y = (screen_h - banner_height) / 2
  elseif banner_position == "top_left" then
    banner_x = 2
    banner_y = 2
  elseif banner_position == "top_right" then
    banner_x = screen_w - banner_width - 2
    banner_y = 2
  elseif banner_position == "bottom_center" then
    banner_x = (screen_w - banner_width) / 2
    banner_y = screen_h - banner_height - 2
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
  local env_strength_bar_x = (screens.screen_w / 2) - bar_max_width - bar_spacing

  screen.level(15)
  screen.rect(env_strength_bar_x, bar_y, env_strength_bar_width, bar_height)
  screen.fill()

  screen.level(1)
  screen.rect(env_strength_bar_x, bar_y, bar_max_width, bar_height)
  screen.stroke()

  -- Randomize Lowpass on the right
  local random_lowpass_value = params:get("random_lowpass")
  local random_lowpass_bar_width = bar_max_width * random_lowpass_value
  local random_lowpass_bar_x = (screens.screen_w / 2) + bar_spacing

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
  local attack_bar_x = (screens.screen_w / 2) - bar_max_width - bar_spacing
  local release_bar_x = (screens.screen_w / 2) + bar_spacing

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

-- GRAPHS
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

-- KEY AND ENC HANDLERS
function key(n, z)
  if n == 1 then
    shift = (z == 1)
  else
    if screen_mode == 1 then
      handle_tape_recorder_key(n, z)
    elseif screen_mode == 2 then
      handle_voice_screen_key(n, z)
    elseif screen_mode == 3 then
      handle_delay_screen_key(n, z)
    end
  end
end

function handle_delay_screen_key(n, z)
  if n == 2 and z == 1 then
    params:set("delay_sync", 1 - params:get("delay_sync"))
    local sync_state = params:get("delay_sync") == 1 and "SYNC" or "FREE"
    set_show_info_banner(sync_state)
  elseif n == 3 and z == 1 then
    local current_subdivision = params:get("delay_subdivision_type")
    local next_subdivision = (current_subdivision % 3) + 1
    params:set("delay_subdivision_type", next_subdivision)

    local subdivision_name = ""
    if next_subdivision == 1 then
      subdivision_name = "--"
    elseif next_subdivision == 2 then
      subdivision_name = "•"
    elseif next_subdivision == 3 then
      subdivision_name = "3"
    end
    print("Subdivision Name: " .. subdivision_name)
    set_show_info_banner(subdivision_name)
  end
end

function handle_tape_recorder_key(n, z)
  if n == 2 and z == 1 then
    -- Toggle Record Mode On/Off
    params:set("sample_or_record", 1 - params:get("sample_or_record"))
    set_show_info_banner(params:get("sample_or_record") == 1 and "REC MODE" or "SAMPLE MODE", "center")
  elseif n == 3 and z == 1 then
    if shift then
      -- Shift + Button 3: Toggle Arm Record
      if params:get("sample_or_record") == 1 then
        params:set("arm_record", 1 - params:get("arm_record"))
        set_show_info_banner(params:get("arm_record") == 1 and "ARM ON" or "ARM OFF", "center")
      end
    else
      -- Toggle Record
      if params:get("sample_or_record") == 1 then
        params:set("record", 1 - params:get("record"))
      else
        fileselect_active = true
        fileselect.enter(_path.audio, file_select_callback, "audio")
      end
    end
  end
end

function handle_voice_screen_key(n, z)
  if n == 2 and z == 1 then
    if selected_voice_screen == 4 then
      if shift then
        -- Shift + Key 2: Toggle backwards through random scales
        local current_scale = params:get("random_scale")
        local prev_scale = (current_scale - 2) % #utils.scale_names + 1
        params:set("random_scale", prev_scale)

        -- Show info banner with the name of the selected scale
        local scale_name = utils.scale_names[prev_scale]
        set_show_info_banner(scale_name)
      else
        -- Toggle forward through random scales
        local current_scale = params:get("random_scale")
        local next_scale = (current_scale % #utils.scale_names) + 1
        params:set("random_scale", next_scale)

        -- Show info banner with the name of the selected scale
        local scale_name = utils.scale_names[next_scale]
        set_show_info_banner(scale_name)
      end
    else
      -- Toggle Play/Stop
      params:set("play_stop", 1 - params:get("play_stop"))
    end
  elseif n == 3 and z == 1 then
    -- Handle file selection or pattern change logic
    if selected_voice_screen == 1 and params:get("sample_or_record") == 0 then
      fileselect_active = true
      fileselect.enter(_path.audio, file_select_callback, "audio")
    end
  end
end

function enc(n, delta)
  if n == 1 then
    if shift then
      screen_mode = utils.clamp(screen_mode + delta, 1, screen_modes) -- Updated range
    else
      if screen_mode == 2 then
        selected_voice_screen = utils.clamp(selected_voice_screen + delta, 1, number_of_screens)
      end
    end
  else
    -- Delegate to screen-specific handlers
    if screen_mode == 2 then
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
    elseif screen_mode == 3 then
      handle_delay_screen_enc(n, delta)
    elseif screen_mode == 1 then
      handle_record_enc(n, delta) -- Handle tape recorder interactions
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
        set_show_info_banner(utils.delay_divisions_as_strings[params:get("delay_division")])
      else
        params:delta("delay_time", delta)
        set_show_info_banner(params:get("delay_time"))
      end
    elseif n == 3 then
      params:delta("delay_feedback", delta)
      set_show_info_banner('FB: ' .. params:get("delay_feedback"))
    end
  end
end

function handle_fifth_octave_enc(n, delta)
  if shift then
    if n == 2 then utils.handle_param_change("semitones", delta, -24, 24, 1, "lin") end
    set_show_info_banner(params:get("semitones"))
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

function handle_record_enc(n, delta)
  if n == 2 then
    print("loop_length_in_beats", params:get("loop_length_in_beats"))
    -- Adjust loop length in beats using encoder 2
    params:delta("loop_length_in_beats", delta)
  elseif n == 3 then
    -- Reserved for additional encoder 3 functionality if needed
  end
end

-- FILE SELECT
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

-- CLOCK
function clock.transport.start()
  params:set("play_stop", 1)
end

function clock.transport.stop()
  params:set("play_stop", 0)
end

function clock.tempo_change_handler()
  update_delay_time()
  update_record_time()
end

function start_recording()
  params:set("arm_record", 0)
  local step_division = params:get("step_division")
  local division_factor = utils.division_factors[step_division]
  clock.sync(division_factor * 4)
  engine.record(1)
end

function start_sequence()
  local i = 1
  local pattern_index = 1

  if (params:get('arm_record') == 1) and (params:get('sample_or_record') == 1) then
    params:set('record', 1)
    params:set('arm_record', 0)
  end

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
        local reverse = params:get("reverse" .. index)
        local amp = params:get("amp" .. index)
        local pan = params:get("pan" .. index)

        -- Base semitones
        local semitones = params:get("semitones")

        -- Apply random scale note
        local scale_index = params:get("random_scale")
        local scale_name = utils.scale_names[scale_index]
        local selected_scale = utils.scales[scale_name]

        if selected_scale and math.random() < params:get("random_fifth") then
          local scale_add = selected_scale[math.random(1, #selected_scale)]
          semitones = semitones + scale_add
        end

        -- Apply random octave
        if math.random() < params:get("random_octave") then
          semitones = semitones + 12
        end

        -- Calculate playback rate
        local rate = math.pow(2, semitones / 12)

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
  local bpm = clock.get_tempo() -- Get the current BPM
  print("bpm: " .. bpm)

  local division_factor = utils.delay_division_factors[params:get("delay_division")]

  local subdivision_type = params:get("delay_subdivision_type")
  local subdivision_multiplier = 1 -- Default: Straight

  if subdivision_type == 2 then
    subdivision_multiplier = 1.5   -- Dotted
  elseif subdivision_type == 3 then
    subdivision_multiplier = 2 / 3 -- Triplet
  end

  local delay_time = (60 / bpm) * division_factor * 4 * subdivision_multiplier
  print("sync delay time: " .. delay_time)

  -- Set engine delay if sync is enabled
  if params:get("delay_sync") == 1 then
    engine.delay(delay_time)
  end
end

function update_record_time()
  local beat_sec = clock.get_beat_sec()
  local loop_length = params:get("loop_length_in_beats") * beat_sec
  engine.loopLength(loop_length)
end
