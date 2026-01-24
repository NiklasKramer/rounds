-- rounds is a clocked sample
-- manipulation environment

engine.name = 'Rounds'
-- ARC rotary input smoothing buffer
local arc_buffer = { 0, 0, 0, 0 }
local direction_accumulator = 0  -- Accumulator for playback direction changes
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
local global_screen = 1  -- 1 = tape recorder, 2 = tempo/swing
local number_of_global_screens = 2
local arc_key_hold_time = 0
local long_press_threshold = 0.5
local shift = false
local delay_division_delta_accum = 0  -- Accumulator for delay division encoder
local fileselect_active = false
local selected_file_path = 'none'

local show_info_banner = false
local metro_info_banner
local info_banner_text = ""

-- Step and Pattern Configuration
local active_steps = { 0, 0, 0, 0 }
local pattern_indices = { 1, 1, 1, 1 }
local step_counters = { 1, 1, 1, 1 }

-- Pattern Recording (Automation) - Based on MSG implementation
local num_pattern_slots = 8  -- Columns 5-12 on grid (8 slots, symmetrical)
local pattern_banks = {}     -- Stores recorded param changes per slot
local pattern_timers = {}    -- Metro timers for playback
local pattern_positions = {} -- Playback positions
local record_slot = -1       -- Currently recording slot (-1 = none)
local record_prevtime = -1   -- Previous event time for delta calculation

-- Initialize pattern storage
for i = 1, num_pattern_slots do
  pattern_banks[i] = {}
  table.insert(pattern_positions, 1)
end

-- Timing and Clock
local record_clock_id = 0

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

  -- Hook into PSET save/load for buffer export/import
  params.action_write = function(filename, name, number)
    save_buffers(number)
  end

  params.action_read = function(filename, silent, number)
    -- Stop all tracks immediately to prevent playing with unloaded buffers
    for track = 0, num_tracks - 1 do
      params:set(get_track_param("play", track), 0)
    end

    clock.run(function()
      clock.sleep(1.5) -- Wait for params to load and engine to stabilize
      load_buffers(number)
      clock.sleep(0.5) -- Wait for async buffer loading to complete
      print("=== PSET LOAD COMPLETE - READY TO PLAY ===")
    end)
  end

  params.action_delete = function(filename, name, number)
    delete_buffers(number)
  end

  g.key = function(x, y, z)
    grid_key(x, y, z)
  end

  -- Auto-start the sequencer
  clock.run(start_sequence)
end

function init_polls()
  metro_screen_refresh = metro.init(function(stage)
    redraw()
    arc_redraw()
    grid_redraw()
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

  -- Initialize pattern timers for automation playback
  for i = 1, num_pattern_slots do
    pattern_timers[i] = metro.init(function() pattern_next(i) end)
  end
end

-- PATTERN RECORDING FUNCTIONS (Automation)
function record_pattern_event(param_id, value)
  if record_slot <= 0 then return end

  local current_time = util.time()
  local delta = current_time - (record_prevtime > 0 and record_prevtime or current_time)
  table.insert(pattern_banks[record_slot], { delta, param_id, value })
  record_prevtime = current_time
end

-- Wrapper to set param and record if pattern recording is active
function param_set_and_record(param_id, value)
  params:set(param_id, value)
  if record_slot > 0 then
    record_pattern_event(param_id, value)
  end
end

-- Override utils.handle_param_change to include recording
local original_handle_param_change = utils.handle_param_change
utils.handle_param_change = function(param_name, delta, min_val, max_val, step, scale_type)
  original_handle_param_change(param_name, delta, min_val, max_val, step, scale_type, function(param_id, value)
    if record_slot > 0 then
      record_pattern_event(param_id, value)
    end
  end)
end

-- Calculate optimal grid dimensions for step display (as square as possible)
function calculate_step_grid_dimensions(num_steps)
  -- Try to make a square-ish grid, but limit to 6 rows max (rows 2-7)
  -- to avoid overlapping with pattern recorder on row 8
  local cols = math.ceil(math.sqrt(num_steps))
  local rows = math.ceil(num_steps / cols)

  -- For common step counts, use nice layouts
  -- Max 6 rows (to avoid pattern recorder), max 14 cols (columns 2-15)
  if num_steps == 16 then
    cols, rows = 4, 4
  elseif num_steps == 32 then
    cols, rows = 8, 4
  elseif num_steps == 64 then
    cols, rows = 11, 6  -- Changed from 8x8 to fit in 6 rows
  elseif num_steps == 24 then
    cols, rows = 6, 4
  elseif num_steps == 48 then
    cols, rows = 8, 6
  elseif num_steps <= 8 then
    cols, rows = num_steps, 1
  elseif num_steps <= 12 then
    cols, rows = 4, 3
  end

  -- Ensure we don't exceed 6 rows
  if rows > 6 then
    cols = math.ceil(num_steps / 6)
    rows = 6
  end

  return cols, rows
end

function start_pattern_playback(n)
  pattern_timers[n]:start(0.001, 1)
end

function stop_pattern_playback(n)
  pattern_timers[n]:stop()
  pattern_positions[n] = 1
end

function arm_pattern_recording(n)
  record_slot = n
  record_prevtime = -1
end

function stop_pattern_recording()
  if record_slot < 1 or record_slot > num_pattern_slots then return end

  local recorded_events = #pattern_banks[record_slot]
  if recorded_events > 0 then
    local current_time = util.time()
    local final_delta = current_time - record_prevtime
    pattern_banks[record_slot][1][1] = final_delta
    start_pattern_playback(record_slot)
  end

  record_slot = -1
  record_prevtime = -1
end

function pattern_next(n)
  local bank = pattern_banks[n]
  local pos = pattern_positions[n]

  if pos > #bank then
    pattern_positions[n] = 1
    pos = 1
  end

  local event = bank[pos]
  if event then
    local delta, param_id, value = table.unpack(event)
    params:set(param_id, value)

    -- Schedule next event
    local next_pos = pos + 1
    if next_pos > #bank then
      next_pos = 1
    end
    pattern_positions[n] = next_pos

    local next_event = bank[next_pos]
    local next_delta = next_event and next_event[1] or 1
    pattern_timers[n]:start(next_delta, 1)
  end
end

function init_params()
  params:add_separator("ROUNDS")

  -- ============================================================
  -- GLOBAL SECTION
  -- ============================================================
  params:add_separator("--- GLOBAL ---")
  params:add_group("Transport", 2)
  params:add_binary("play_stop", "Play All Tracks", "toggle", 0)
  params:set_action("play_stop", function(value)
    -- Toggle all tracks
    for track = 0, num_tracks - 1 do
      params:set(get_track_param("play", track), value)
    end
  end)

  params:add_taper("swing", "Swing", 0, 100, 0, 0, "%")

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
  params:add_group("Delay", 12)

  params:add_taper("delay_mix", "Mix", 0, 1, 0.2, 0)
  params:set_action("delay_mix", function(value) engine.mix(value) end)

  params:add_binary('delay_sync', 'Sync', 'toggle', 1)
  params:set_action('delay_sync', function(value)
    update_delay_time()
  end)

  params:add_taper("delay_lag_time", "Lag Time", 0.001, 2.0, 0.5, 0.001, "s")
  params:set_action("delay_lag_time", function(value) engine.lagTime(value) end)

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

  params:add_taper("delay_feedback", "Feedback", 0, 1, 0.4, 0, "")
  params:set_action("delay_feedback", function(value)
    -- Map 0-1 exponentially to 0.1-30 seconds
    local time = 0.1 * math.exp(value * math.log(300))
    engine.time(time)
  end)

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
  update_env_graph()
  update_filter_graph()
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
    -- Draw sub-screen indicator for global screens
    screens.draw_screen_indicator(number_of_global_screens, global_screen)

    if global_screen == 1 then
      screens.draw_tape_recorder(record_pointer, current_track)
    elseif global_screen == 2 then
      draw_tempo_screen()
    end
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

function draw_tempo_screen()
  local bpm = math.floor(clock.get_tempo() + 0.5)
  local swing = params:get("swing")

  screen.level(15)
  screen.font_face(1)
  screen.font_size(8)
  screen.move(10, 20)
  screen.text("BPM")

  screen.font_size(16)
  screen.move(10, 38)
  screen.text(bpm)

  screen.font_size(8)
  screen.move(70, 20)
  screen.text("SWING")

  screen.font_size(16)
  screen.move(70, 38)
  screen.text(swing .. "%")
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
        if global_screen == 1 then
          handle_tape_recorder_key(n, z)
        elseif global_screen == 2 then
          handle_tempo_key(n, z)
        end
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

function handle_tempo_key(n, z)
  if n == 3 and z == 1 and shift then
    params:set("swing", 0)
    set_show_info_banner("SWING RESET", "center")
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
      if screen_mode == 1 then
        -- Switch between global screens (tape recorder / tempo)
        global_screen = utils.clamp(global_screen + delta, 1, number_of_global_screens)
      elseif screen_mode >= 2 and screen_mode <= 5 then
        selected_voice_screen[current_track + 1] = utils.clamp(selected_voice_screen[current_track + 1] + delta, 1,
          number_of_screens)
      end
    end
  else
    if screen_mode == 1 then
      if global_screen == 1 then
        handle_record_enc(n, delta)
      elseif global_screen == 2 then
        handle_tempo_enc(n, delta)
      end
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
      -- Use accumulator for smoother direction changes (requires 3 steps)
      direction_accumulator = direction_accumulator + delta

      if math.abs(direction_accumulator) >= 3 then
        local steps = math.floor(direction_accumulator / 3)
        direction_accumulator = direction_accumulator - (steps * 3)

        local current = params:get(get_track_param("direction"))
        local new_direction = utils.clamp(current + steps, 1, 3)
        print("Changing direction from", current, "to", new_direction)
        local param_id = get_track_param("direction")
        params:set(param_id, new_direction)
        if record_slot > 0 then
          record_pattern_event(param_id, new_direction)
        end
      end
    else
      utils.handle_param_change(get_track_param("pattern"), delta, 1, #utils.patterns, 1, "lin")
    end
  elseif n == 3 then
    if shift then
      local current_steps = params:get(get_track_param("steps"))
      local new_steps = utils.clamp(current_steps + delta, 4, 64)
      local param_id = get_track_param("steps")
      params:set(param_id, new_steps)
      engine.steps(current_track, new_steps)
      if record_slot > 0 then
        record_pattern_event(param_id, new_steps)
      end
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
        if record_slot > 0 then
          record_pattern_event("delay_mix", params:get("delay_mix"))
        end
        set_show_info_banner("Mix: " .. string.format("%.2f%%", params:get("delay_mix") * 100))
      else
        -- Show current Mix value
        set_show_info_banner("Mix: " .. string.format("%.2f%%", params:get("delay_mix") * 100))
      end
    else
      if show_info_banner then
        if params:get("delay_sync") == 1 then
          delay_division_delta_accum = delay_division_delta_accum + delta
          local threshold = 3
          if math.abs(delay_division_delta_accum) >= threshold then
            local steps = delay_division_delta_accum > 0 and 1 or -1
            delay_division_delta_accum = 0
            local current = params:get("delay_division")
            local new_val = util.clamp(current + steps, 1, #utils.delay_divisions_as_strings)
            params:set("delay_division", new_val)
            if record_slot > 0 then
              record_pattern_event("delay_division", new_val)
            end
          end
          set_show_info_banner(utils.delay_divisions_as_strings[params:get("delay_division")])
        else
          params:delta("delay_time", delta)
          if record_slot > 0 then
            record_pattern_event("delay_time", params:get("delay_time"))
          end
          set_show_info_banner(string.format("%.2f", params:get("delay_time")))
        end
      else
        delay_division_delta_accum = 0
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
        if record_slot > 0 then
          record_pattern_event("rotate", params:get("rotate"))
        end
        set_show_info_banner("Rotate: " .. string.format("%.2f", params:get("rotate")))
      else
        -- Show current Rotate value
        set_show_info_banner("Rotate: " .. string.format("%.2f", params:get("rotate")))
      end
    else
      if show_info_banner then
        -- Update Feedback value
        params:delta("delay_feedback", delta)
        if record_slot > 0 then
          record_pattern_event("delay_feedback", params:get("delay_feedback"))
        end
        set_show_info_banner('FB: ' .. string.format("%.0f%%", params:get("delay_feedback") * 100))
      else
        -- Show current Feedback value
        set_show_info_banner('FB: ' .. string.format("%.0f%%", params:get("delay_feedback") * 100))
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
          local param_id = get_track_param("random_scale")
          params:set(param_id, next_scale)
          if record_slot > 0 then
            record_pattern_event(param_id, next_scale)
          end
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
    local param_id = get_track_param("loop_length_in_beats")
    params:delta(param_id, delta)
    if record_slot > 0 then
      record_pattern_event(param_id, params:get(param_id))
    end
  end
end

function handle_tempo_enc(n, delta)
  if n == 2 then
    local current_bpm = clock.get_tempo()
    local new_bpm = util.clamp(current_bpm + delta, 20, 300)
    params:set("clock_tempo", new_bpm)
    if record_slot > 0 then
      record_pattern_event("clock_tempo", new_bpm)
    end
  elseif n == 3 then
    local current_swing = params:get("swing")
    local new_swing = util.clamp(current_swing + delta, 0, 100)
    params:set("swing", new_swing)
    if record_slot > 0 then
      record_pattern_event("swing", new_swing)
    end
  end
end

a.delta = function(n, delta)
  local sens = params:get("arc_sensitivity")
  arc_buffer[n] = arc_buffer[n] + delta / sens

  if math.abs(arc_buffer[n]) >= 1 then
    local step = math.floor(arc_buffer[n])
    arc_buffer[n] = arc_buffer[n] - step

    if screen_mode == 1 then
      if global_screen == 1 then
        if n == 1 then
          enc(2, step)
        elseif n == 2 then
          enc(3, step)
        end
      elseif global_screen == 2 then
        if n == 1 then
          enc(2, step)
        elseif n == 2 then
          enc(3, step)
        end
      end
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

-- GRID
function grid_key(x, y, z)
  -- Row 8, Column 1: Shift button (hold to clear patterns)
  if x == 1 and y == 8 then
    shift = (z == 1)
    return
  end

  if z == 1 then  -- Button press
    -- Row 8, Columns 5-12: Pattern recording slots (8 slots)
    if y == 8 and x >= 5 and x <= 12 then
      local slot = x - 4  -- Convert column to slot number (1-8)

      -- Clear pattern if shift is held
      if shift then
        if slot == record_slot then
          stop_pattern_recording()
        end
        if pattern_timers[slot].is_running then
          stop_pattern_playback(slot)
        end
        pattern_banks[slot] = {}
        set_show_info_banner("PATTERN " .. slot .. " CLEARED", "center")
        return
      end

      if slot == record_slot then
        -- Stop recording if currently recording this slot
        stop_pattern_recording()
        set_show_info_banner("PATTERN " .. slot .. " SAVED", "center")
      else
        local has_data = #pattern_banks[slot] > 0

        if has_data then
          -- Toggle playback if slot has data
          if pattern_timers[slot].is_running then
            stop_pattern_playback(slot)
            set_show_info_banner("PATTERN " .. slot .. " STOPPED", "center")
          else
            start_pattern_playback(slot)
            set_show_info_banner("PATTERN " .. slot .. " PLAYING", "center")
          end
        else
          -- Arm new recording if slot is empty
          if record_slot > 0 then
            stop_pattern_recording()
          end
          pattern_banks[slot] = {}  -- Clear slot
          arm_pattern_recording(slot)
          set_show_info_banner("RECORDING PATTERN " .. slot, "center")
        end
      end
    end

    -- Column 16 (rightmost): Main mode selection and track control
    if x == 16 then
      -- Row 1: Tape (mode 1)
      if y == 1 then
        if screen_mode == 1 then
          -- Cycle through tape sub-screens
          global_screen = (global_screen % number_of_global_screens) + 1
        else
          screen_mode = 1
        end
      -- Rows 2-5: Tracks 1-4 (modes 2-5)
      elseif y >= 2 and y <= 5 then
        if shift then
          -- Shift + Track button: Toggle play/stop for that track
          local track_index = y - 2  -- Maps rows 2-5 to tracks 0-3
          local track_param = "t" .. (track_index + 1) .. "_play"
          local is_playing = params:get(track_param)
          local new_value = 1 - is_playing
          params:set(track_param, new_value)

          -- Record pattern event
          if record_slot > 0 then
            record_pattern_event(track_param, new_value)
          end

          set_show_info_banner("TRACK " .. (track_index + 1) .. (is_playing == 1 and " STOP" or " START"), "center")
        else
          -- Normal press: Switch to track mode
          if screen_mode == y then
            -- Cycle through track sub-screens
            selected_voice_screen[current_track + 1] = (selected_voice_screen[current_track + 1] % number_of_screens) + 1
          else
            screen_mode = y
          end
        end
      -- Row 6: Delay (mode 6)
      elseif y == 6 then
        screen_mode = 6
      -- Row 8: Start/Stop all tracks
      elseif y == 8 then
        toggle_all_tracks()
      end
    end

    -- Column 1 (leftmost): Sub-screen selection
    if x == 1 then
      if screen_mode == 1 then
        -- Tape mode: 2 sub-screens
        if y >= 1 and y <= number_of_global_screens then
          global_screen = y
        end
      elseif screen_mode >= 2 and screen_mode <= 5 then
        -- Track modes: 5 sub-screens each
        if y >= 1 and y <= number_of_screens then
          selected_voice_screen[current_track + 1] = y
        end
      end
      -- Delay mode has no sub-screens
    end

    -- Step grid for screen 1 (sequencer) on track modes
    if screen_mode >= 2 and screen_mode <= 5 then
      local current_screen = selected_voice_screen[current_track + 1]
      if current_screen == 1 then
        -- Get current track's step count and calculate optimal grid
        local track_steps = params:get(get_track_param("steps"))
        local grid_cols, grid_rows = calculate_step_grid_dimensions(track_steps)

        -- Center the grid horizontally (columns 3-14 available = 12 columns)
        -- Column 2 free on left, column 15 free on right
        local available_cols = 12
        local start_col = 3 + math.floor((available_cols - grid_cols) / 2)
        local start_row = 2

        -- Check if press is in the step grid area
        local end_col = start_col + grid_cols - 1
        local end_row = start_row + grid_rows - 1

        if y >= start_row and y <= end_row and x >= start_col and x <= end_col then
          local row_offset = y - start_row
          local col_offset = x - start_col
          local step_index = row_offset * grid_cols + col_offset + 1

          if step_index <= track_steps then
            local track_prefix = "t" .. (current_track + 1) .. "_"

            if shift then
              -- Shift + step: toggle reverse
              local reverse_param = track_prefix .. "reverse" .. step_index
              local current_reverse = params:get(reverse_param)
              params:set(reverse_param, 1 - current_reverse)
            else
              -- Normal press: toggle step on/off
              local active_param = track_prefix .. "active_" .. step_index
              local current_value = params:get(active_param)
              params:set(active_param, 1 - current_value)
            end
          end
        end
      end

      -- Piano keyboard for screen 4 (pitch screen)
      if current_screen == 4 then
        -- Row 5: Octave selector (4 options: -1, 0, +1, +2)
        -- Centered at columns 7-10
        if y == 5 and x >= 7 and x <= 10 then
          local target_octave = (x - 7) - 1  -- Maps columns 7,8,9,10 to octaves -1,0,+1,+2

          -- Get current semitone and calculate note within octave
          local current_semitone = params:get(get_track_param("semitones"))
          local note_in_octave = current_semitone % 12
          if note_in_octave < 0 then note_in_octave = note_in_octave + 12 end

          -- Calculate new semitone in target octave
          local new_semitone = (target_octave * 12) + note_in_octave

          -- Set the semitone parameter
          local semitone_param = get_track_param("semitones")
          params:set(semitone_param, new_semitone)

          -- Record pattern event
          if record_slot > 0 then
            record_pattern_event(semitone_param, new_semitone)
          end

          set_show_info_banner(new_semitone .. " ST", "center")
          return
        end

        -- Rows 2-3: Piano keyboard (C to C, columns 5-12)
        if (y == 2 or y == 3) and x >= 5 and x <= 12 then
          local col_offset = x - 5  -- 0-7 for white keys
          local note_semitone = -1

          if y == 3 then
            -- Row 3: White keys (C, D, E, F, G, A, B, C) - 8 keys, C to C
            local white_key_semitones = {0, 2, 4, 5, 7, 9, 11, 12}
            note_semitone = white_key_semitones[col_offset + 1]
          elseif y == 2 then
            -- Row 2: Black keys (C#, D#, --, F#, G#, A#, --, C#)
            local black_key_semitones = {1, 3, -1, 6, 8, 10, -1, 13}
            note_semitone = black_key_semitones[col_offset + 1]
          end

          -- Only trigger if valid semitone (not a gap)
          if note_semitone >= 0 then
            -- Get current octave from current semitone setting
            local current_semitone = params:get(get_track_param("semitones"))
            local current_octave = math.floor(current_semitone / 12)

            -- Calculate final semitone
            -- For notes 0-11, use current octave
            -- For note 12 (second C) and 13 (second C#), use next octave
            local final_semitone
            if note_semitone >= 12 then
              final_semitone = (current_octave * 12) + note_semitone
            else
              final_semitone = (current_octave * 12) + note_semitone
            end

            -- Set the semitone parameter for the current track
            local semitone_param = get_track_param("semitones")
            params:set(semitone_param, final_semitone)

            -- Record pattern event
            if record_slot > 0 then
              record_pattern_event(semitone_param, final_semitone)
            end

            -- Trigger a preview sound with calculated pitch
            local rate = 2 ^ (final_semitone / 12)
            local amp = 1.0  -- Default amplitude
            local pan = params:get(get_track_param("pan"))
            local reverse = 0  -- Forward playback

            -- Play step 1 with calculated pitch for preview
            engine.play(current_track, 1, amp, rate, pan, reverse)

            -- Show feedback
            set_show_info_banner(final_semitone .. " ST", "center")
          end
        end
      end
    end
  end
end

function grid_redraw()
  g:all(0)  -- Clear all LEDs

  -- Row 8, Column 1: Shift button (brighter to distinguish from sub-screens)
  g:led(1, 8, shift and 15 or 6)

  -- Row 8, Columns 5-12: Pattern recording slots (8 slots)
  for i = 1, num_pattern_slots do
    local col = i + 4  -- Convert slot to column (5-12)
    local brightness = 0

    if record_slot == i then
      -- Recording: bright
      brightness = 15
    elseif pattern_timers[i].is_running then
      -- Playing back: bright
      brightness = 12
    elseif #pattern_banks[i] > 0 then
      -- Has data: medium
      brightness = 6
    else
      -- Empty: dim
      brightness = 2
    end

    g:led(col, 8, brightness)
  end

  -- Column 16: Main mode indicators
  -- Row 1: Tape (mode 1) - brighter to show it's global
  if screen_mode == 1 then
    g:led(16, 1, 15)
  else
    g:led(16, 1, 6)  -- Brighter when unselected
  end

  -- Rows 2-5: Tracks 1-4 (modes 2-5) - dimmer to show they're track-specific
  for i = 2, 5 do
    if screen_mode == i then
      g:led(16, i, 10)  -- Less bright for tracks
    else
      g:led(16, i, 3)   -- Dimmer when unselected
    end
  end

  -- Row 6: Delay (mode 6) - brighter to show it's global
  if screen_mode == 6 then
    g:led(16, 6, 15)
  else
    g:led(16, 6, 6)  -- Brighter when unselected
  end

  -- Row 8, Column 16: All tracks start/stop indicator
  local any_playing = false
  for track = 0, num_tracks - 1 do
    if params:get("t" .. (track + 1) .. "_play") == 1 then
      any_playing = true
      break
    end
  end
  g:led(16, 8, any_playing and 15 or 6)  -- Bright when playing, dim when stopped

  -- Column 1: Sub-screen indicators (dimmer than shift button)
  if screen_mode == 1 then
    -- Tape mode: show global screen options
    for i = 1, number_of_global_screens do
      if i == global_screen then
        g:led(1, i, 12)  -- Bright but not as bright as shift
      else
        g:led(1, i, 3)   -- Dimmer when unselected
      end
    end
  elseif screen_mode >= 2 and screen_mode <= 5 then
    -- Track mode: show voice screen options
    local current_screen = selected_voice_screen[current_track + 1]
    for i = 1, number_of_screens do
      if i == current_screen then
        g:led(1, i, 12)  -- Bright but not as bright as shift
      else
        g:led(1, i, 3)   -- Dimmer when unselected
      end
    end

    -- Display step grid for screen 1 (sequencer)
    if current_screen == 1 then
      local track_steps = params:get(get_track_param("steps"))
      local current_step = active_steps[current_track + 1]
      local grid_cols, grid_rows = calculate_step_grid_dimensions(track_steps)

      -- Center the grid horizontally (columns 2-15 available = 14 columns)
      -- Avoid column 1 (sub-screen select) and column 16 (mode select)
      -- Rows 2-7 available (6 rows, avoiding row 8 pattern recorder)
      local available_cols = 14
      local start_col = 2 + math.floor((available_cols - grid_cols) / 2)
      local start_row = 2
      local track_prefix = "t" .. (current_track + 1) .. "_"

      for step = 1, track_steps do
        local row_offset = math.floor((step - 1) / grid_cols)
        local col_offset = (step - 1) % grid_cols
        local y = start_row + row_offset
        local x = start_col + col_offset

        local is_active = params:get(track_prefix .. "active_" .. step) == 1
        local is_reverse = params:get(track_prefix .. "reverse" .. step) == 1
        local is_current = step == current_step

        local brightness = 0
        if is_reverse then
          -- Reversed steps have different brightness
          if is_current and is_active then
            brightness = 13  -- Current playing step (active, reversed)
          elseif is_current then
            brightness = 6   -- Current playing step (inactive, reversed)
          elseif is_active then
            brightness = 7   -- Active step (reversed)
          else
            brightness = 2   -- Inactive step (reversed - same as normal inactive)
          end
        else
          -- Normal (forward) steps
          if is_current and is_active then
            brightness = 15  -- Current playing step (active)
          elseif is_current then
            brightness = 8   -- Current playing step (inactive)
          elseif is_active then
            brightness = 10  -- Active step
          else
            brightness = 2   -- Inactive step
          end
        end

        g:led(x, y, brightness)
      end
    end

    -- Display piano keyboard for screen 4 (pitch screen)
    if current_screen == 4 then
      -- Get current track's semitone setting to highlight it
      local current_semitone = params:get(get_track_param("semitones"))
      local semitone_in_octave = current_semitone % 12
      if semitone_in_octave < 0 then semitone_in_octave = semitone_in_octave + 12 end
      local current_octave = math.floor(current_semitone / 12)

      -- Piano keyboard layout - C to C (columns 5-12)
      -- Row 2: Black keys, Row 3: White keys

      -- White keys semitones mapping (row 3, columns 5-12) - C to C (octave up)
      local white_keys = {0, 2, 4, 5, 7, 9, 11, 12}

      -- Draw white keys (row 3) - 8 columns
      for i, semitone in ipairs(white_keys) do
        local col = i + 4  -- columns 5-12
        -- Highlight if current semitone matches (mod 12 for first 7 keys, exact match for 8th)
        local is_current
        if semitone < 12 then
          is_current = (semitone_in_octave == semitone)
        else
          -- Second C (semitone 12) only highlights if current semitone is exactly 12 in this octave
          is_current = (current_semitone == (current_octave * 12) + 12)
        end
        local brightness = is_current and 15 or 6
        g:led(col, 3, brightness)
      end

      -- Black keys positions (some columns are gaps where piano has no black keys)
      local black_keys = {
        {col = 5, semitone = 1},   -- C#
        {col = 6, semitone = 3},   -- D#
        -- col 7 is gap (no black key between E and F)
        {col = 8, semitone = 6},   -- F#
        {col = 9, semitone = 8},   -- G#
        {col = 10, semitone = 10}, -- A#
        -- col 11 is gap (no black key between B and C)
        {col = 12, semitone = 13}, -- C# (octave up)
      }

      -- Draw black keys (row 2)
      for _, key in ipairs(black_keys) do
        local is_current
        if key.semitone < 12 then
          is_current = (semitone_in_octave == key.semitone)
        else
          -- Second C# (semitone 13) only highlights if current semitone is exactly 13 in this octave
          is_current = (current_semitone == (current_octave * 12) + 13)
        end
        local brightness = is_current and 15 or 4
        g:led(key.col, 2, brightness)
      end

      -- Octave selector (row 5, centered at columns 7-10)
      -- Maps to octaves: -1, 0, +1, +2
      for i = 0, 3 do
        local col = 7 + i  -- Centered at columns 7-10
        local octave = i - 1
        local brightness = (current_octave == octave) and 15 or 6
        g:led(col, 5, brightness)
      end
    end
  end

  g:refresh()
end

function arc_redraw()
  a:all(0)

  if screen_mode == 1 then
    if global_screen == 1 then
      arc_utils.display_selector(a, 1, current_track + 1, 4)
      arc_utils.display_progress_bar(a, 2, params:get(get_track_param("loop_length_in_beats")), 1, 64)

      local is_recording = params:get(get_track_param("record")) == 1
      local loop_length = params:get(get_track_param("loop_length_in_beats"))

      local time_based_rotation = 0
      if is_recording then
        local rotation_speed = 1 / math.max(1, loop_length / 8)
        time_based_rotation = (util.time() * rotation_speed) % 1
      end

      arc_utils.display_tape_spool(a, 3, time_based_rotation, is_recording)
      arc_utils.display_tape_spool(a, 4, time_based_rotation + 0.33, is_recording)
    elseif global_screen == 2 then
      arc_utils.display_progress_bar(a, 1, clock.get_tempo(), 20, 300)
      arc_utils.display_progress_bar(a, 2, params:get("swing"), 0, 100)
    end
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
  elseif screen_mode == 6 then
    if params:get("delay_sync") == 1 then
      arc_utils.display_selector(a, 1, params:get("delay_division"), #utils.delay_divisions_as_strings)
    else
      arc_utils.display_spread_pattern(a, 1, params:get("delay_time"), 0, 8)
    end
    arc_utils.display_spread_pattern(a, 2, params:get("delay_feedback"), 0, 1)
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

-- BUFFER EXPORT/IMPORT FOR PSET SUPPORT
function save_buffers(pset_number)
  -- Create directory if it doesn't exist
  local dir = _path.audio .. "rounds/"
  os.execute("mkdir -p \"" .. dir .. "\"")

  print("=== SAVING BUFFERS FOR PSET " .. pset_number .. " ===")
  print("Directory: " .. dir)

  -- Save all tracks' record buffers
  for track = 0, num_tracks - 1 do
    local path = dir .. "pset_" .. pset_number .. "_track_" .. (track + 1)
    local mode = params:get(get_track_param("sample_or_record", track))

    print("Track " .. (track + 1) .. ": mode=" .. mode)

    -- Only save if track is in record mode
    if mode == 1 then
      engine.writeBuffer(track, path)
      print("  -> Writing to: " .. path)
    else
      print("  -> Skipping (sample mode)")
    end
  end

  print("=== BUFFER SAVE REQUESTED ===")
end

function load_buffers(pset_number)
  local dir = _path.audio .. "rounds/"

  print("=== LOADING BUFFERS FOR PSET " .. pset_number .. " ===")
  print("Directory: " .. dir)

  -- Check if directory exists
  local check_dir = io.popen("ls -la \"" .. dir .. "\" 2>&1")
  if check_dir then
    print("Directory contents:")
    print(check_dir:read("*a"))
    check_dir:close()
  end

  -- Load all tracks' record buffers
  for track = 0, num_tracks - 1 do
    local path = dir .. "pset_" .. pset_number .. "_track_" .. (track + 1)
    local file_l = path .. "_L.wav"
    local file_r = path .. "_R.wav"

    -- Check if files exist
    local exists_l = io.open(file_l, "r")
    local exists_r = io.open(file_r, "r")

    if exists_l and exists_r then
      exists_l:close()
      exists_r:close()
      print("Track " .. (track + 1) .. ": Found files, loading...")
      engine.readBuffer(track, path)
    else
      if exists_l then exists_l:close() end
      if exists_r then exists_r:close() end
      print("Track " .. (track + 1) .. ": No saved buffers found")
    end
  end

  print("=== BUFFER LOAD REQUESTED ===")
end

function delete_buffers(pset_number)
  local dir = _path.audio .. "rounds/"

  print("Deleting recorded buffers for PSET " .. pset_number)

  -- Delete all tracks' record buffer files
  for track = 0, num_tracks - 1 do
    local base_path = dir .. "pset_" .. pset_number .. "_track_" .. (track + 1)
    os.execute("rm -f \"" .. base_path .. "_L.wav\"")
    os.execute("rm -f \"" .. base_path .. "_R.wav\"")
  end

  print("Buffer delete complete")
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
  engine.resetRecorder(track)
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

        -- Apply swing to off-beats
        if is_playing and i % 2 == 0 then
          local swing_amount = params:get("swing") / 100
          local swing_ratio = (swing_amount - 0.5) * 2
          if swing_ratio > 0 then
            local swing_delay = swing_ratio * track_division * 4
            clock.sync(swing_delay)
          end
        end

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

          -- Check if step is active before processing
          local active = params:get(track_prefix .. "active_" .. index) == 1

          if active and current_pattern[pattern_index] == 1 then
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

          -- Advance this track's counters
          i = i + 1
          pattern_index = pattern_index + 1

          if i > track_num_steps then i = 1 end
          if pattern_index > pattern_length then pattern_index = 1 end

          -- Only sync clock if step was active (skip inactive steps without pause)
          if active then
            clock.sync(track_division * 4)
          end
        else
          -- When stopped, sync to maintain clock alignment
          clock.sync(track_division * 4)
        end
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
