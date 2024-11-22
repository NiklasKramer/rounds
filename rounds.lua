-- rounds is a clocked sample manipulation environment

engine.name = 'Rounds'

local g = grid.connect()
local EnvGraph = require "envgraph"
local FilterGraph = require "filtergraph"

local fileselect = require('fileselect')

utils = include('lib/utils')
screens = include('lib/screens')

local screen_w, screen_h = 128, 64
local circle_x, circle_y = screen_w / 2, screen_h / 2


local selected_voice_screen = 1
local number_of_screens = 5
local screen_mode = 1
local shift = false
local fileselect_active = false
local selected_file_path = 'none'

-- Step and Pattern Configuration
local steps = 16
local active_step = 0

-- Timing and Clock
local clock_id = 0

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

  params:add_group("Record", 5)
  params:add_binary('sample_or_record', 'Record Mode On', 'toggle', 0)
  params:set_action('sample_or_record', function(value)
    engine.sampleOrRecord(value)
  end)

  params:add_binary('record', 'Record', 'toggle', 0)
  params:set_action('record', function(value)
    if value == 1 then
      clock.run(function()
        clock.sync(1)    -- Synchronize to the next beat
        engine.record(1) -- Start recording
        print("Recording started on clock beat.")
      end)
    else
      engine.record(0) -- Stop recording
      print("Recording stopped.")
    end
  end)

  params:add_control("loop_length", "Loop Length", controlspec.new(0, 60, 'lin', 0, 60, "sec"))
  params:set_action('loop_length', function(value)
    engine.loopLength(value)
  end)

  params:add_binary('synced_loop', 'Synced Loop Time', 'toggle', 1)


  params:add_control('loop_length_in_beats', 'Loop in Beats', controlspec.new(1, 64, 'lin', 1, 16, "beats"))
  params:set_action('loop_length_in_beats', function(value)
    update_record_time()
  end)

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

  params:add_option("delay_division", "Division", utils.delay_divisions_as_strings, 9)
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

  screens.draw_mode_indicator(screen_mode)

  if screen_mode == 1 then
    screens.draw_screen_indicator(number_of_screens, selected_voice_screen, screen_mode)
  end

  -- Draw content based on the selected screen
  if screen_mode == 1 then
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
  elseif screen_mode == 2 then
    screens.draw_delay_screen()
  end

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
  local division_factor = utils.delay_division_factors[params:get("delay_division")]
  local delay_time = beat_sec * division_factor * 4 -- synced time
  print("sync delay time: " .. delay_time)

  -- Set engine delay if sync is enabled
  if params:get("delay_sync") == 1 then
    engine.delay(delay_time)
  end
end

function update_record_time()
  local beat_sec = clock.get_beat_sec()
  local loop_length = params:get("loop_length_in_beats") * beat_sec
  if (params:get("synced_loop") == 1) then
    engine.loopLength(loop_length)
  end
end
