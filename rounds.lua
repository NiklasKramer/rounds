-- rounds is a clocked sample
-- manipulation environment

engine.name = 'Rounds'
-- ARC rotary input smoothing buffer
local arc_buffer = { 0, 0, 0, 0 }
local g = grid.connect()
local EnvGraph = require "envgraph"
local FilterGraph = require "filtergraph"
local fileselect = require('fileselect')
local a = arc.connect()

utils = include('lib/utils')
screens = include('lib/screens')
arc_utils = include('lib/arc_utils')


local screen_w, screen_h = 128, 64
local circle_x, circle_y = screen_w / 2, screen_h / 2

record_pointer = 0

local current_track = 0
local prev_track = 0
local tape_selected_track = 0
local num_tracks = 4
local selected_voice_screen = { 1, 1, 1, 1 }
local number_of_screens = 5
local screen_modes = 6
local screen_mode = 2
local prev_screen_mode = 2
local arc_key_hold_time = 0
local long_press_threshold = 0.5
local shift = false
local fileselect_active = false
local selected_file_path = 'none'

local show_info_banner = false
local metro_info_banner
local info_banner_text = ""

-- Step and Pattern Configuration
local steps = 16
local active_step = 0
local active_steps = { 0, 0, 0, 0 }    -- Independent step position for each track
local pattern_indices = { 1, 1, 1, 1 } -- Independent pattern position for each track
local step_counters = { 1, 1, 1, 1 }   -- Independent step counters for each track

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

  -- Auto-start the sequencer (tracks control themselves with play param)
  play_clock_id = clock.run(start_sequence)
end

function init_polls()
  metro_screen_refresh = metro.init(function(stage)
    redraw()
    arc_redraw()
  end, 1 / 60)
  metro_screen_refresh:start()



  record_pointer_poll = poll.set('recorderPos', function(value)
    -- Check if any track is currently recording
    local any_recording = false
    for track = 0, num_tracks - 1 do
      if params:get(get_track_param("record", track)) == 1 then
        any_recording = true
        break
      end
    end

    if any_recording then
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
  params:add_separator("ROUNDS")

  -- ============================================================
  -- GLOBAL SECTION
  -- ============================================================
  params:add_separator("--- GLOBAL ---")
  params:add_group("Transport", 1)
  params:add_binary("play_stop", "Play All Tracks", "toggle", 0)
  params:set_action("play_stop", function(value)
    -- Toggle all tracks
    for track = 0, num_tracks - 1 do
      params:set(get_track_param("play", track), value)
    end
  end)

  -- ============================================================
  -- MASTER FX SECTION
  -- ============================================================
  params:add_separator("--- MASTER FX ---")
  delay_params()

  -- ============================================================
  -- TRACKS SECTION
  -- ============================================================
  params:add_separator("--- TRACKS ---")
  for track = 0, num_tracks - 1 do
    track_params(track)
  end

  -- ============================================================
  -- STEPS SECTION
  -- ============================================================
  params:add_separator("--- STEPS ---")
  steps_as_params()

  -- ============================================================
  -- ARC SECTION
  -- ============================================================
  params:add_separator("--- ARC ---")
  arc_params()
end

function track_params(track)
  local track_num = track + 1 -- Display as 1-4 instead of 0-3
  local prefix = "t" .. track_num .. "_"

  params:add_separator("TRACK " .. track_num)

  -- Transport
  params:add_group("T" .. track_num .. " Transport", 2)
  params:add_binary(prefix .. "play", "Play", "toggle", 0) -- Default: stopped
  params:add_option(prefix .. "direction", "Direction", { "Forward", "Reverse", "Random" }, 1)

  -- Global
  params:add_group("T" .. track_num .. " Global", 7)

  params:add_file(prefix .. "sample", "Sample")
  params:set_action(prefix .. "sample", function(file)
    engine.bufferPath(track, file)
  end)

  -- Steps parameter moved to track_params function

  params:add_option(prefix .. "step_division", "Step Division", utils.division_factors, 4)

  params:add_number(prefix .. "pattern", "Pattern", 1, #utils.patterns, 1)

  params:add_number(prefix .. "semitones", "Semitones", -24, 24, 0)
  params:set_action(prefix .. "semitones", function(value)
    engine.semitones(track, value)
  end)

  params:add_taper(prefix .. "pan", "Pan", -1, 1, 0, 0)

  params:add_taper(prefix .. "volume", "Volume", 0, 1, 1, 0)

  params:add_taper(prefix .. "steps", "Steps", 4, 64, 16, 0)
  params:set_action(prefix .. "steps", function(value)
    engine.steps(track, value)
  end)

  -- Record
  params:add_group("T" .. track_num .. " Record", 4)

  params:add_binary(prefix .. 'sample_or_record', 'Record Mode On', 'toggle', 0)
  params:set_action(prefix .. 'sample_or_record', function(value)
    params:set(prefix .. "record", 0)
    engine.sampleOrRecord(track, value)
  end)

  params:add_binary(prefix .. 'record', 'Record', 'toggle', 0)
  params:set_action(prefix .. 'record', function(value)
    if value == 1 then
      -- Start recording for this specific track
      record_clock_id = clock.run(start_recording, track)
    else
      -- Stop recording for this specific track
      engine.record(track, 0)
      if record_clock_id then
        clock.cancel(record_clock_id)
      end
    end
  end)

  params:add_binary(prefix .. 'arm_record', 'Arm Record', 'toggle', 0)

  params:add_control(prefix .. 'loop_length_in_beats', 'Loop in Beats', controlspec.new(1, 64, 'lin', 1, 16, "beats"))
  params:set_action(prefix .. 'loop_length_in_beats', function(value)
    local beat_sec = clock.get_beat_sec()
    local loop_length = value * beat_sec
    engine.loopLength(track, loop_length)
  end)

  -- Envelope
  params:add_group("T" .. track_num .. " Envelope", 7)

  params:add_binary(prefix .. "env", "Enable Envelope", "toggle", 1)
  params:set_action(prefix .. "env", function(value)
    engine.useEnv(track, value)
  end)

  params:add_taper(prefix .. "attack", "Attack Time", 0, 1, 0.001, 0)
  params:set_action(prefix .. "attack", function(value)
    engine.attack(track, value)
    if track == current_track then
      update_env_graph()
    end
  end)

  params:add_taper(prefix .. "release", "Release Time", 0, 5, 0.5, 0)
  params:set_action(prefix .. "release", function(value)
    engine.release(track, value)
    if track == current_track then
      update_env_graph()
    end
  end)

  params:add_control(prefix .. "lowpass_freq", "Lowpass Frequency", controlspec.new(10, 20000, 'exp', 1, 20000, "hz"))
  params:set_action(prefix .. 'lowpass_freq', function(value)
    engine.lowpassFreq(track, value)
    if track == current_track then
      update_filter_graph()
    end
  end)

  params:add_taper(prefix .. 'resonance', 'Resonance', 0.01, 1, 0)
  params:set_action(prefix .. 'resonance', function(value)
    engine.resonance(track, 1 - value)
    if track == current_track then
      update_filter_graph()
    end
  end)

  params:add_taper(prefix .. 'highpass_freq', 'Highpass Frequency', 1, 20000, 1)
  params:set_action(prefix .. 'highpass_freq', function(value)
    engine.highpassFreq(track, value)
  end)

  params:add_taper(prefix .. "lowpass_env_strength", "Lowpass Env Strength", 0, 1, 0, 0)
  params:set_action(prefix .. "lowpass_env_strength", function(value)
    engine.lowpassEnvStrength(track, value)
  end)

  -- Randomization
  params:add_group("T" .. track_num .. " Randomization", 10)

  params:add_taper(prefix .. "random_octave", "Randomize Octave", 0, 1, 0, 0)
  params:set_action(prefix .. "random_octave", function(value)
    engine.randomOctave(track, value)
  end)

  params:add_taper(prefix .. "random_fifth", "Randomize Fifth", 0, 1, 0, 0)
  params:set_action(prefix .. "random_fifth", function(value)
    engine.randomFith(track, value)
  end)

  params:add_option(prefix .. "random_scale", "Random Scale", utils.scale_names, 8)

  params:add_taper(prefix .. "random_pan", "Randomize Pan", 0, 1, 0, 0)
  params:set_action(prefix .. "random_pan", function(value)
    engine.randomPan(track, value)
  end)

  params:add_taper(prefix .. "random_reverse", "Randomize Reverse", 0, 1, 0, 0)
  params:set_action(prefix .. "random_reverse", function(value)
    engine.randomReverse(track, value)
  end)

  params:add_taper(prefix .. "random_attack", "Randomize Attack", 0, 1, 0, 0)
  params:set_action(prefix .. "random_attack", function(value)
    engine.randomAttack(track, value)
  end)

  params:add_taper(prefix .. "random_release", "Randomize Release", 0, 1, 0, 0)
  params:set_action(prefix .. "random_release", function(value)
    engine.randomRelease(track, value)
  end)

  params:add_taper(prefix .. "random_amp", "Randomize Amplitude", 0, 1, 0, 0)
  params:set_action(prefix .. "random_amp", function(value)
    engine.randomAmp(track, value)
  end)

  params:add_taper(prefix .. 'random_lowpass', 'Randomize Lowpass', 0, 1, 0, 0)
  params:set_action(prefix .. 'random_lowpass', function(value)
    engine.randomLowPass(track, value)
  end)

  params:add_taper(prefix .. 'random_highpass', 'Randomize Highpass', 0, 1, 0, 0)
  params:set_action(prefix .. 'random_highpass', function(value)
    engine.randomHiPass(track, value)
  end)
end

function arc_params()
  params:add_group("Arc", 1)
  params:add_taper("arc_sensitivity", "Sensitivity", 1, 100, 3)
end

-- Helper function to get the track-specific param name
function get_track_param(param_name, track)
  track = track or current_track
  return "t" .. (track + 1) .. "_" .. param_name
end

function delay_params()
  params:add_group("Delay", 11)

  params:add_taper("delay_mix", "Mix", 0, 1, 0.2, 0)
  params:set_action("delay_mix", function(value) engine.mix(value) end)

  params:add_binary('delay_sync', 'Sync', 'toggle', 1)
  params:set_action('delay_sync', function(value)
    update_delay_time()
  end)

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
  for track = 0, num_tracks - 1 do
    local track_prefix = "t" .. (track + 1) .. "_"
    for i = 1, 64 do
      params:add_group(track_prefix .. "step_" .. i, 7)
      params:add_separator(track_prefix .. "step: " .. i)

      params:add_binary(track_prefix .. "active_" .. i, "active_" .. i, "toggle", 1)

      params:add_taper(track_prefix .. "rate" .. i, "rate" .. i, -4, 4, 1, 0)

      params:add_taper(track_prefix .. "amp" .. i, "amp" .. i, 0, 1, 1, 0)

      params:add_binary(track_prefix .. "reverse" .. i, "reverse" .. i, "toggle", 0)

      params:add_taper(track_prefix .. "pan" .. i, "pan" .. i, -1, 1, 0.0, 0)

      params:add_number(track_prefix .. "segment" .. i, "segment" .. i, 1, 64, i)
    end
  end
end

-- Helper to update displays when switching tracks
function update_track_displays()
  -- Update envelope graph
  update_env_graph()

  -- Update filter graph
  update_filter_graph()

  -- Update steps variable for display
  steps = params:get(get_track_param("steps"))
end

-- SCREENS
function redraw()
  if fileselect_active then return end
  screen.clear()

  if screen_mode ~= prev_screen_mode then
    if prev_screen_mode == 1 and screen_mode >= 2 and screen_mode <= 5 then
      tape_selected_track = current_track
    elseif screen_mode == 1 and prev_screen_mode >= 2 and prev_screen_mode <= 5 then
      current_track = tape_selected_track
    end
    prev_screen_mode = screen_mode
  end

  if screen_mode >= 2 and screen_mode <= 5 then
    current_track = screen_mode - 2
  end

  -- Update displays if track changed
  if current_track ~= prev_track then
    update_track_displays()
    prev_track = current_track
  end

  -- Draw the main screen components
  screens.draw_mode_indicator(screen_modes, screen_mode)

  if screen_mode == 1 then
    screens.draw_tape_recorder(record_pointer, current_track)
  elseif screen_mode >= 2 and screen_mode <= 5 then
    local current_screen = selected_voice_screen[current_track + 1]
    screens.draw_screen_indicator(number_of_screens, current_screen)
    if current_screen == 1 then
      local track_steps = params:get(get_track_param("steps"))
      screens.draw_step_circle(track_steps, active_steps[current_track + 1], current_track)
    elseif current_screen == 2 then
      draw_envelope_screen()
    elseif current_screen == 3 then
      screens.draw_random_pan_amp_screen()
    elseif current_screen == 4 then
      screens.draw_random_fifth_octave_screen()
    elseif current_screen == 5 then
      draw_filter_screen()
    end
  elseif screen_mode == 6 then
    screens.draw_delay_screen()
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
  local lowpass_env_strength_value = params:get(get_track_param("lowpass_env_strength"))
  local env_strength_bar_width = bar_max_width * lowpass_env_strength_value
  local env_strength_bar_x = (screens.screen_w / 2) - bar_max_width - bar_spacing

  screen.level(15)
  screen.rect(env_strength_bar_x, bar_y, env_strength_bar_width, bar_height)
  screen.fill()

  screen.level(1)
  screen.rect(env_strength_bar_x, bar_y, bar_max_width, bar_height)
  screen.stroke()

  -- Randomize Lowpass on the right
  local random_lowpass_value = params:get(get_track_param("random_lowpass"))
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
  local random_attack_value = params:get(get_track_param("random_attack"))
  local random_release_value = params:get(get_track_param("random_release"))
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

  local release = params:get(get_track_param("release"))
  local attack = params:get(get_track_param("attack"))

  env_graph = EnvGraph.new_ar(0, 1, 0, 1, attack, release, 1)
  env_graph:set_position_and_size(env_x, env_y, env_width, env_height)
  env_graph:set_show_x_axis(true)
end

function init_filter_graph()
  local filter_width = 80
  local filter_height = 40
  local filter_x = circle_x - (filter_width / 2)
  local filter_y = circle_y - (filter_height / 2) - 5

  local lowpass_freq = params:get(get_track_param("lowpass_freq"))
  local resonance = params:get(get_track_param("resonance"))

  filter_graph = FilterGraph.new(10, 20000, -60, 32.5, 1, 12, lowpass_freq, resonance)

  filter_graph:set_position_and_size(filter_x, filter_y, filter_width, filter_height)
  filter_graph:set_show_x_axis(true)
  filter_graph:set_active(true)
end

function update_env_graph()
  local attack = params:get(get_track_param("attack"))
  local release = params:get(get_track_param("release"))
  env_graph:edit_ar(attack, release)
end

function update_filter_graph()
  local lowpass_freq = params:get(get_track_param("lowpass_freq"))
  local resonance = params:get(get_track_param("resonance"))
  filter_graph:edit(nil, nil, lowpass_freq, resonance)
end

-- Global track control
function toggle_all_tracks()
  -- Check if any tracks are playing
  local any_playing = false
  for track = 0, num_tracks - 1 do
    if params:get(get_track_param("play", track)) == 1 then
      any_playing = true
      break
    end
  end

  -- If any tracks are playing, stop all; otherwise start all
  local new_state = any_playing and 0 or 1
  local action_text = any_playing and "STOP ALL" or "START ALL"

  for track = 0, num_tracks - 1 do
    params:set(get_track_param("play", track), new_state)
  end

  set_show_info_banner(action_text, "center")
end

-- KEY AND ENC HANDLERS
function key(n, z)
  if n == 1 then
    shift = (z == 1)
  else
    -- Global start/stop for all tracks (Shift+K2)
    if n == 2 and z == 1 and shift then
      toggle_all_tracks()
    else
      -- Delegate to screen-specific handlers
      if screen_mode == 1 then
        handle_tape_recorder_key(n, z)
      elseif screen_mode >= 2 and screen_mode <= 5 then
        handle_voice_screen_key(n, z)
      elseif screen_mode == 6 then
        handle_delay_screen_key(n, z)
      end
    end
  end
end

function handle_delay_screen_key(n, z)
  if z == 1 then
    if n == 2 then
      -- Check if the info banner is already shown for "Sync"
      if show_info_banner then
        -- Update Sync value and toggle it
        params:set("delay_sync", 1 - params:get("delay_sync"))
        local sync_state = params:get("delay_sync") == 1 and "SYNC" or "FREE"
        set_show_info_banner(sync_state)
      else
        -- Show the current Sync state
        local sync_state = params:get("delay_sync") == 1 and "SYNC" or "FREE"
        set_show_info_banner(sync_state)
      end
    elseif n == 3 then
      -- Check if the info banner is already shown for "Subdivision"
      if show_info_banner then
        -- Update Subdivision value and toggle it
        local current_subdivision = params:get("delay_subdivision_type")
        local next_subdivision = (current_subdivision % 3) + 1
        params:set("delay_subdivision_type", next_subdivision)
        local subdivision_name = next_subdivision == 1 and "--" or (next_subdivision == 2 and "•" or "3")
        set_show_info_banner(subdivision_name)
      else
        -- Show the current Subdivision state
        local current_subdivision = params:get("delay_subdivision_type")
        local subdivision_name = current_subdivision == 1 and "--" or (current_subdivision == 2 and "•" or "3")
        set_show_info_banner(subdivision_name)
      end
    end
  end
end

function handle_tape_recorder_key(n, z)
  if n == 2 and z == 1 then
    -- Toggle Record Mode On/Off for current track
    params:set(get_track_param("sample_or_record"),
      1 - params:get(get_track_param("sample_or_record")))
    set_show_info_banner(
      params:get(get_track_param("sample_or_record")) == 1 and "REC MODE" or "SAMPLE MODE", "center")
  elseif n == 3 and z == 1 then
    if shift then
      -- Shift + Button 3: Toggle Arm Record for current track
      if params:get(get_track_param("sample_or_record")) == 1 then
        params:set(get_track_param("arm_record"),
          1 - params:get(get_track_param("arm_record")))
        set_show_info_banner(params:get(get_track_param("arm_record")) == 1 and "ARM ON" or "ARM OFF",
          "center")
      else
        set_show_info_banner("SWITCH TO REC MODE FIRST", "center")
      end
    else
      -- Toggle Record for current track
      if params:get(get_track_param("sample_or_record")) == 1 then
        params:set(get_track_param("record"), 1 - params:get(get_track_param("record")))
      else
        fileselect_active = true
        fileselect.enter(_path.audio, file_select_callback, "audio")
      end
    end
  end
end

function handle_voice_screen_key(n, z)
  if n == 2 and z == 1 then
    local current_screen = selected_voice_screen[current_track + 1]
    if current_screen == 4 then
      if shift then
        -- Show info banner with the name of the selected scale
        local scale_name = utils.scale_names[prev_scale]
        set_show_info_banner(scale_name)
      else
        local scale_name = utils.scale_names[next_scale]
        set_show_info_banner(scale_name)
      end
    else
      -- Toggle Play/Stop for current track
      params:set(get_track_param("play"), 1 - params:get(get_track_param("play")))
    end
  elseif n == 3 and z == 1 then
    -- Handle file selection or pattern change logic
    local current_screen = selected_voice_screen[current_track + 1]
    if current_screen == 1 and params:get(get_track_param("sample_or_record")) == 0 then
      fileselect_active = true
      fileselect.enter(_path.audio, file_select_callback, "audio")
    end
  end
end

function enc(n, delta)
  if n == 1 then
    if shift then
      screen_mode = utils.clamp(screen_mode + delta, 1, screen_modes)
    else
      if screen_mode >= 2 and screen_mode <= 5 then
        selected_voice_screen[current_track + 1] = utils.clamp(selected_voice_screen[current_track + 1] + delta, 1,
          number_of_screens)
      end
    end
  else
    if screen_mode == 1 then
      handle_record_enc(n, delta)
    elseif screen_mode >= 2 and screen_mode <= 5 then
      local current_screen = selected_voice_screen[current_track + 1]
      if current_screen == 1 then
        handle_step_circle_enc(n, delta)
      elseif current_screen == 2 then
        handle_envelope_enc(n, delta)
      elseif current_screen == 3 then
        handle_pan_amp_enc(n, delta)
      elseif current_screen == 4 then
        handle_fifth_octave_enc(n, delta)
      elseif current_screen == 5 then
        handle_filter_enc(n, delta)
      end
    elseif screen_mode == 6 then
      handle_delay_screen_enc(n, delta)
    end
  end
end

function handle_step_circle_enc(n, delta)
  if n == 2 then
    if shift then
      -- Clamp direction between 1 and 3, no wrapping
      local current = params:get(get_track_param("direction"))
      local new_direction = utils.clamp(current + delta, 1, 3)
      print("Changing direction from", current, "to", new_direction)
      params:set(get_track_param("direction"), new_direction)
    else
      utils.handle_param_change(get_track_param("pattern"), delta, 1, #utils.patterns, 1, "lin")
    end
  elseif n == 3 then
    if shift then
      local current_steps = params:get(get_track_param("steps"))
      local new_steps = utils.clamp(current_steps + delta, 4, 64)
      params:set(get_track_param("steps"), new_steps)
      steps = new_steps
      engine.steps(current_track, steps)
    else
      utils.handle_param_change(get_track_param("step_division"), delta, 1, #utils.division_factors, 1, "lin")
    end
  end
end

function handle_envelope_enc(n, delta)
  if shift then
    if n == 2 then utils.handle_param_change(get_track_param("random_attack"), delta, 0, 1, 0.01, "lin") end
    if n == 3 then utils.handle_param_change(get_track_param("random_release"), delta, 0, 1, 0.01, "lin") end
  else
    if n == 2 then
      utils.handle_param_change(get_track_param("attack"), delta, 0.001, 1, 0.001, "lin")
      update_env_graph()
    end
    if n == 3 then
      utils.handle_param_change(get_track_param("release"), delta, 0.001, 5, 0.01, "lin")
      update_env_graph()
    end
  end
end

function handle_pan_amp_enc(n, delta)
  if shift then
    -- Direct pan and volume control
    if n == 2 then utils.handle_param_change(get_track_param("pan"), delta, -1, 1, 0.05, "lin") end
    if n == 3 then utils.handle_param_change(get_track_param("volume"), delta, 0, 1, 0.01, "lin") end
  else
    -- Random pan and amp
    if n == 2 then utils.handle_param_change(get_track_param("random_pan"), delta, 0, 1, 0.01, "lin") end
    if n == 3 then utils.handle_param_change(get_track_param("random_amp"), delta, 0, 1, 0.01, "lin") end
  end
end

function handle_delay_screen_enc(n, delta)
  if n == 2 then
    if shift then
      if show_info_banner then
        -- Update Mix value
        params:delta("delay_mix", delta)
        set_show_info_banner("Mix: " .. string.format("%.2f%%", params:get("delay_mix") * 100))
      else
        -- Show current Mix value
        set_show_info_banner("Mix: " .. string.format("%.2f%%", params:get("delay_mix") * 100))
      end
    else
      if show_info_banner then
        -- Update delay division or time based on sync
        if params:get("delay_sync") == 1 then
          params:delta("delay_division", delta)
          set_show_info_banner(utils.delay_divisions_as_strings[params:get("delay_division")])
        else
          params:delta("delay_time", delta)
          set_show_info_banner(string.format("%.2f", params:get("delay_time")))
        end
      else
        -- Show current delay division or time
        if params:get("delay_sync") == 1 then
          set_show_info_banner(utils.delay_divisions_as_strings[params:get("delay_division")])
        else
          set_show_info_banner(string.format("%.2f", params:get("delay_time")))
        end
      end
    end
  elseif n == 3 then
    if shift then
      if show_info_banner then
        -- Update Rotate value
        params:delta("rotate", delta)
        set_show_info_banner("Rotate: " .. string.format("%.2f", params:get("rotate")))
      else
        -- Show current Rotate value
        set_show_info_banner("Rotate: " .. string.format("%.2f", params:get("rotate")))
      end
    else
      if show_info_banner then
        -- Update Feedback value
        params:delta("delay_feedback", delta)
        set_show_info_banner('FB: ' .. string.format("%.2f", params:get("delay_feedback")))
      else
        -- Show current Feedback value
        set_show_info_banner('FB: ' .. string.format("%.2f", params:get("delay_feedback")))
      end
    end
  end
end

function handle_fifth_octave_enc(n, delta)
  if n == 2 then
    if shift then
      -- Handle semitones adjustment with preview and update
      if show_info_banner then
        -- Update semitones value
        utils.handle_param_change(get_track_param("semitones"), delta, -24, 24, 1, "lin")
        set_show_info_banner("Semitones: " .. params:get(get_track_param("semitones")))
      else
        -- Show current semitones value
        set_show_info_banner("Semitones: " .. params:get(get_track_param("semitones")))
      end
    else
      -- Adjust random fifth strength
      utils.handle_param_change(get_track_param("random_fifth"), delta, 0, 1, 0.01, "lin")
    end
  elseif n == 3 then
    if shift then
      -- Handle random scale adjustment with preview and update
      if show_info_banner then
        -- Update random scale value
        local current_scale = params:get(get_track_param("random_scale"))
        local next_scale = utils.clamp(current_scale + delta, 1, #utils.scale_names)
        if next_scale ~= current_scale then
          params:set(get_track_param("random_scale"), next_scale)
          set_show_info_banner("Scale: " .. utils.scale_names[next_scale])
        end
      else
        -- Show current random scale value
        local current_scale = params:get(get_track_param("random_scale"))
        set_show_info_banner("Scale: " .. utils.scale_names[current_scale])
      end
    else
      -- Adjust random octave strength
      utils.handle_param_change(get_track_param("random_octave"), delta, 0, 1, 0.01, "lin")
    end
  end
end

function handle_filter_enc(n, delta)
  if shift then
    if n == 2 then
      utils.handle_param_change(get_track_param("lowpass_env_strength"), delta, 0, 1, 0.01, "lin")
    elseif n == 3 then
      utils.handle_param_change(get_track_param("random_lowpass"), delta, 0, 1, 0.01, "lin")
    end
  else
    if n == 2 then
      -- Use exponential scaling for lowpass frequency
      utils.handle_param_change(get_track_param("lowpass_freq"), delta, 10, 20000, 0.05, "exp")
      update_filter_graph()
    elseif n == 3 then
      -- Use linear scaling for resonance
      utils.handle_param_change(get_track_param("resonance"), delta, 0.01, 1, 0.01, "lin")
      update_filter_graph()
    end
  end
end

function handle_record_enc(n, delta)
  if n == 2 then
    -- Switch between tracks (this changes which track's recording settings we see)
    current_track = util.clamp(current_track + delta, 0, num_tracks - 1)
  elseif n == 3 then
    -- Adjust loop length for current track
    params:delta(get_track_param("loop_length_in_beats"), delta)
  end
end

-- ARC encoder mappings
a.delta = function(n, delta)
  local sens = params:get("arc_sensitivity")
  arc_buffer[n] = arc_buffer[n] + delta / sens

  if math.abs(arc_buffer[n]) >= 1 then
    local step = math.floor(arc_buffer[n])
    arc_buffer[n] = arc_buffer[n] - step

    -- Tape Recorder (mode 1): Arc 1 = track, Arc 2 = beats, Arc 3/4 = visual only
    if screen_mode == 1 then
      if n == 1 then
        enc(2, step) -- Track selection
      elseif n == 2 then
        enc(3, step) -- Loop length in beats
      end
      -- Arc 3 and 4 are visual only (spool animation), no input

      -- Track modes (2-5) and Delay (6): Use standard mapping
    else
      if n == 1 then
        enc(2, step)
      elseif n == 2 then
        enc(3, step)
      elseif n == 3 then
        shift = true
        enc(2, step)
        shift = false
      elseif n == 4 then
        shift = true
        enc(3, step)
        shift = false
      end
    end
  end
end

a.key = function(n, z)
  if n == 1 then
    if z == 1 then
      arc_key_hold_time = util.time()
    else
      local hold_duration = util.time() - arc_key_hold_time
      if hold_duration >= long_press_threshold then
        -- Long press: toggle screen_mode
        screen_mode = screen_mode + 1
        if screen_mode > screen_modes then
          screen_mode = 1
        end
      else
        -- Short press: advance selected_voice_screen
        selected_voice_screen[current_track + 1] = selected_voice_screen[current_track + 1] + 1
        if selected_voice_screen[current_track + 1] > number_of_screens then
          selected_voice_screen[current_track + 1] = 1
        end
      end
      redraw()
    end
  end
end


-- ARC redraw function for visual feedback
function arc_redraw()
  a:all(0)

  -- Tape Recorder (mode 1)
  if screen_mode == 1 then
    -- Arc 1: Current track selector (4 segments)
    arc_utils.display_selector(a, 1, current_track + 1, 4)
    -- Arc 2: Loop length in beats (1-64)
    arc_utils.display_progress_bar(a, 2, params:get(get_track_param("loop_length_in_beats")), 1, 64)

    -- Arc 3 & 4: Tape spool animation with 3 segments
    local is_recording = params:get(get_track_param("record")) == 1
    local loop_length = params:get(get_track_param("loop_length_in_beats"))

    -- Calculate rotation (only moves when recording)
    local time_based_rotation = 0
    if is_recording then
      -- Speed inversely proportional to loop length (longer loops = slower rotation)
      local rotation_speed = 1 / math.max(1, loop_length / 8) -- Normalize to reasonable speed
      time_based_rotation = (util.time() * rotation_speed) % 1
    end

    -- Arc 3: Left spool with 3 segments
    arc_utils.display_tape_spool(a, 3, time_based_rotation, is_recording)
    -- Arc 4: Right spool with 3 segments (offset for visual variety)
    arc_utils.display_tape_spool(a, 4, time_based_rotation + 0.33, is_recording)
    -- Tracks 1-4 (modes 2-5)
  elseif screen_mode >= 2 and screen_mode <= 5 then
    local current_screen = selected_voice_screen[current_track + 1]
    if current_screen == 1 then
      local current_track_step = active_steps[current_track + 1]
      arc_utils.display_step_pattern(a, 1, utils.patterns[params:get(get_track_param("pattern"))], current_track_step)
      arc_utils.display_step_division(a, 2, params:get(get_track_param("step_division")))
      arc_utils.display_selector(a, 3, params:get(get_track_param("direction")), 3)
      arc_utils.display_steps(a, 4, params:get(get_track_param("steps")), current_track_step)
    elseif current_screen == 2 then
      arc_utils.display_spread_pattern(a, 1, params:get(get_track_param("attack")), 0.001, 1)
      arc_utils.display_spread_pattern(a, 2, params:get(get_track_param("release")), 0.001, 5)
      arc_utils.display_spread_pattern(a, 3, params:get(get_track_param("random_attack")), 0, 1)
      arc_utils.display_spread_pattern(a, 4, params:get(get_track_param("random_release")), 0, 1)
    elseif current_screen == 3 then
      arc_utils.display_random_pattern(a, 1, params:get(get_track_param("random_pan")), 0, 1)
      arc_utils.display_spread_pattern(a, 2, params:get(get_track_param("random_amp")), 0, 1)
      arc_utils.display_panning_value(a, 3, params:get(get_track_param("pan")), -1, 1)
      arc_utils.display_progress_bar(a, 4, params:get(get_track_param("volume")), 0, 1)
    elseif current_screen == 4 then
      arc_utils.display_spread_pattern(a, 1, params:get(get_track_param("random_fifth")), 0, 1)
      arc_utils.display_spread_pattern(a, 2, params:get(get_track_param("random_octave")), 0, 1)
      arc_utils.display_panning_value(a, 3, params:get(get_track_param("semitones")), -24, 24)
      arc_utils.display_selector(a, 4, params:get(get_track_param("random_scale")), 12)
    elseif current_screen == 5 then
      arc_utils.display_exponential_pattern(a, 1, params:get(get_track_param("lowpass_freq")), 10, 20000)
      arc_utils.display_spread_pattern(a, 2, params:get(get_track_param("resonance")), 0.01, 1)
      arc_utils.display_progress_bar(a, 3, params:get(get_track_param("lowpass_env_strength")), 0, 1)
      arc_utils.display_progress_bar(a, 4, params:get(get_track_param("random_lowpass")), 0, 1)
    end
    -- Delay (mode 6)
  elseif screen_mode == 6 then
    arc_utils.display_spread_pattern(a, 1, params:get("delay_time"), 0, 8)
    arc_utils.display_spread_pattern(a, 2, params:get("delay_feedback"), 0, 20)
    arc_utils.display_progress_bar(a, 3, params:get("delay_mix"), 0, 1)
    arc_utils.display_progress_bar(a, 4, params:get("rotate"), 0, 1)
  end
  a:refresh()
end

-- FILE SELECT
function file_select_callback(file_path)
  fileselect_active = false

  if file_path ~= 'cancel' then
    local split_at = string.match(file_path, "^.*()/")
    selected_file_path = string.sub(file_path, 9, split_at)
    selected_file_path = util.trim_string_to_width(selected_file_path, 128)
    selected_file = string.sub(file_path, split_at + 1)
    params:set(get_track_param("sample"), file_path)
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

function start_recording(track)
  print("Starting recording for track:", track + 1)
  params:set(get_track_param("arm_record", track), 0)
  local step_division = params:get(get_track_param("step_division", track))
  local division_factor = utils.division_factors[step_division]
  clock.sync(division_factor * 4)
  engine.record(track, 1)
end

function start_sequence()
  -- Start independent clock for each track
  for track = 0, num_tracks - 1 do
    clock.run(function()
      local i = 1
      local pattern_index = 1
      local track_prefix = "t" .. (track + 1) .. "_"
      local was_playing = false

      while true do
        -- Get parameters once per cycle to avoid issues with parameter changes
        local is_playing = params:get(track_prefix .. "play") == 1
        local direction = params:get(track_prefix .. "direction")
        local track_num_steps = math.floor(params:get(track_prefix .. "steps"))
        local current_pattern = utils.patterns[params:get(track_prefix .. "pattern")]
        local pattern_length = #current_pattern
        local track_division = utils.division_factors[params:get(track_prefix .. "step_division")]

        -- Check if this track just started playing (transition from stopped to playing)
        if is_playing and not was_playing then
          -- Check armed recording for this track
          local arm_record = params:get(get_track_param('arm_record', track))
          local sample_or_record = params:get(get_track_param('sample_or_record', track))

          if arm_record == 1 and sample_or_record == 1 then
            print("Starting armed recording for track:", track + 1)
            params:set(get_track_param('record', track), 1)
          end
        end

        was_playing = is_playing

        -- Only advance sequence and trigger sounds when playing
        if is_playing then
          local index = 0

          if direction == 1 then
            index = i
          elseif direction == 2 then
            index = track_num_steps - i + 1
          elseif direction == 3 then
            index = math.random(1, track_num_steps)
          end

          -- Ensure index is always an integer and within bounds
          index = math.floor(index)
          index = math.max(1, math.min(index, track_num_steps))

          -- Update active step for this track
          active_steps[track + 1] = index

          -- Set global active step for current track (for visual feedback)
          if track == current_track then
            active_pattern_step = pattern_index
            active_step = index
            steps = track_num_steps -- Update global steps for display
          end

          if current_pattern[pattern_index] == 1 then
            local active = params:get(track_prefix .. "active_" .. index) == 1
            if active then
              local start_segment = params:get(track_prefix .. "segment" .. index)
              local reverse = params:get(track_prefix .. "reverse" .. index)
              local step_amp = params:get(track_prefix .. "amp" .. index)
              local step_pan = params:get(track_prefix .. "pan" .. index)

              -- Get track-level pan and volume
              local track_pan = params:get(track_prefix .. "pan")
              local track_volume = params:get(track_prefix .. "volume")

              -- Combine step amp with track volume
              local amp = step_amp * track_volume

              -- Combine step pan with track pan (average weighted by track pan strength)
              local pan = step_pan * 0.5 + track_pan * 0.5

              -- Base semitones
              local semitones = params:get(track_prefix .. "semitones")

              -- Apply random scale note
              local scale_index = params:get(track_prefix .. "random_scale")
              local scale_name = utils.scale_names[scale_index]
              local selected_scale = utils.scales[scale_name]

              if selected_scale and math.random() < params:get(track_prefix .. "random_fifth") then
                local scale_add = selected_scale[math.random(1, #selected_scale)]
                semitones = semitones + scale_add
              end

              -- Apply random octave
              if math.random() < params:get(track_prefix .. "random_octave") then
                semitones = semitones + 12
              end

              -- Calculate playback rate
              local rate = math.pow(2, semitones / 12)

              engine.play(track, start_segment, amp, rate, pan, reverse)
            end
          end

          -- Advance this track's counters
          i = i + 1
          pattern_index = pattern_index + 1

          if i > track_num_steps then i = 1 end
          if pattern_index > pattern_length then pattern_index = 1 end
        end

        -- Always sync to clock to maintain beat alignment (even when stopped)
        clock.sync(track_division * 4)
      end
    end)
  end

  -- Keep the main sequence alive
  while true do
    clock.sleep(1)
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
  -- Update loop length for all tracks
  for track = 0, num_tracks - 1 do
    local loop_length = params:get(get_track_param("loop_length_in_beats", track)) * beat_sec
    engine.loopLength(track, loop_length)
  end
end
