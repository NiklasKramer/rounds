--_ Rounds

engine.name = 'Rounds'
local g = grid.connect()

steps = 16
active_step = 0
sync = 0


step_positions_8 = {
  { 2,  2 }, { 3, 2 }, { 6, 2 }, { 7, 2 },
  { 10, 2 }, { 11, 2 }, { 14, 2 }, { 15, 2 }
}

step_positions_16 = {
  { 2, 2 }, { 3, 2 }, { 2, 3 }, { 3, 3 },
  { 6, 2 }, { 7, 2 }, { 6, 3 }, { 7, 3 },
  { 10, 2 }, { 11, 2 }, { 10, 3 }, { 11, 3 },
  { 14, 2 }, { 15, 2 }, { 14, 3 }, { 15, 3 }
}


step_positions_32 = {
  { 2, 2 }, { 3, 2 }, { 2, 3 }, { 3, 3 },
  { 2, 4 }, { 3, 4 }, { 2, 5 }, { 3, 5 },
  { 6, 2 }, { 7, 2 }, { 6, 3 }, { 7, 3 },
  { 6, 4 }, { 7, 4 }, { 6, 5 }, { 7, 5 },
  { 10, 2 }, { 11, 2 }, { 10, 3 }, { 11, 3 },
  { 10, 4 }, { 11, 4 }, { 10, 5 }, { 11, 5 },
  { 14, 2 }, { 15, 2 }, { 14, 3 }, { 15, 3 },
  { 14, 4 }, { 15, 4 }, { 14, 5 }, { 15, 5 },
  { 6, 2 }, { 7, 2 }, { 6, 3 }, { 7, 3 },

}

local step_positions = step_positions_16

function grid_redraw()
  g:all(0)
  -- Draw all steps with brightness 5
  for i = 1, steps do
    local pos = step_positions[i]
    -- print(params:get("active_" .. i))
    if params:get("active_" .. i) == 1 then
      g:led(pos[1], pos[2], 2) -- Normal step brightness
    end
  end
  -- Highlight the active step with brightness 15
  if active_step > 0 and active_step <= steps then
    local active_pos = step_positions[active_step]
    g:led(active_pos[1], active_pos[2], 15)
  end
  g:refresh()
end

function init()
  init_polls()
  init_params()
end

function init_params()
  params:add_separator("Rounds")
  params:add_file("sample", "sample")
  params:set_action("sample", function(file) engine.bufferPath(file) end)

  params:add_binary("play/stop", "play/stop", "toggle", 0)
  params:set_action("play/stop", function(value)
    if value == 1 then
      -- Start playback
      clock.run(function()
        if sync == 1 then
          clock.sync(1 / 4) -- Wait for the next quarter note
        end
        engine.start()      -- Start the engine
      end)
    elseif value == 0 then
      -- Stop playback
      clock.run(function()
        if sync == 1 then
          clock.sync(1 / 4) -- Wait for the next quarter note
        end
        engine.stop()       -- Stop the engine
      end)
    end
  end)

  params:add_binary("sync", "sync", "toggle", 0)
  params:set_action("sync", function(value)
    engine.useSampleLength(1 - value)
    sync = value
    update_step_time() -- Update step time whenever sync is changed
  end)

  params:add_number("bpm", "bpm", 20, 300, 120)
  params:set_action("bpm", function(value)
    params:set("clock_tempo", value)
    update_step_time() -- Update step time whenever bpm is changed
  end)

  -- Add the step division parameter
  params:add_option("step_division", "Step Division", { "1/32", "1/16", "1/8", "1/4", "1/2", "1" }, 4) -- Default to 1/4
  params:set_action("step_division", function(value)
    update_step_time()                                                                                 -- Update step time whenever step division is changed
  end)

  params:add_option("steps", "steps", { 8, 16, 32 }, 2) -- Default to 16 steps
  params:set_action("steps", function(value)
    print("Setting steps to " .. value)

    if value == 1 then
      step_positions = step_positions_8
      steps = 8
      engine.steps(8)
    elseif value == 2 then
      step_positions = step_positions_16
      steps = 16
      engine.steps(16)
    elseif value == 3 then
      step_positions = step_positions_32
      steps = 32
      engine.steps(32)
    end
  end)

  params:add_option("direction", "playback direction", { "forward", "reverse", "random" }, 1)
  params:set_action("direction", function(value)
    engine.direction(value)
  end)

  params:add_separator("Env")
  params:add_binary("env", "env", "toggle", 0)
  params:set_action("env", function(value)
    engine.useEnv(value)
  end)

  params:add_taper("attack", "attack", 0, 1, 0.001, 0)
  params:set_action("attack", function(value)
    engine.attack(value)
  end)

  params:add_taper("release", "release", 0, 5, 0.5, 0)
  params:set_action("release", function(value)
    engine.release(value)
  end)

  -- Initialize step parameters
  init_steps_as_params()

  -- Add randomization parameters
  params:add_separator("Randomization")

  -- Random Octave
  params:add_taper("random_octave", "Random Octave", 0, 1, 0, 0)
  params:set_action("random_octave", function(value)
    engine.randomOctave(value)
  end)

  -- Random Fifth
  params:add_taper("random_fith", "Random Fifth", 0, 1, 0, 0)
  params:set_action("random_fith", function(value)
    engine.randomFith(value)
  end)

  -- Random Pan
  params:add_taper("random_pan", "Random Pan", 0, 1, 0, 0)
  params:set_action("random_pan", function(value)
    engine.randomPan(value)
  end)

  -- Random Reverse
  params:add_taper("random_reverse", "Random Reverse", 0, 1, 0, 0)
  params:set_action("random_reverse", function(value)
    engine.randomReverse(value)
  end)

  -- Random Attack
  params:add_taper("random_attack", "Random Attack", 0, 1, 0, 0)
  params:set_action("random_attack", function(value)
    engine.randomAttack(value)
  end)

  -- Random Release
  params:add_taper("random_release", "Random Release", 0, 1, 0, 0)
  params:set_action("random_release", function(value)
    engine.randomRelease(value)
  end)

  -- Random Amp
  params:add_taper("random_amp", "Random Amp", 0, 1, 0, 0)
  params:set_action("random_amp", function(value)
    engine.randomAmp(value)
  end)
end

function init_steps_as_params()
  params:add_separator("Steps")
  for i = 1, 32 do
    params:add_group("step_" .. i, 7)
    params:add_separator("step: " .. i)

    -- First add the parameter
    params:add_binary("active_" .. i, "active_" .. i, "toggle", 1)

    -- Then set the action for that parameter
    params:set_action("active_" .. i, function(value)
      engine.active(i, value)
    end)

    -- Similarly for other parameters
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
  local phase_poll = poll.set('position', function(pos)
    active_step = pos + 1
  end)
  phase_poll.time = 0.1
  phase_poll:start()

  metro_grid_refresh = metro.init(function(stage) grid_redraw() end, 1 / 40)
  metro_grid_refresh:start()
end

function key(n, z)
  print(n, z)
end

function enc(n, d)
  print(n, d)
end

----- UTIL FUNCTIONS -----
function update_step_time()
  local bpm = params:get("bpm")
  local division = params:get("step_division")

  local division_factors = {
    [1] = 1 / 32,
    [2] = 1 / 16,
    [3] = 1 / 8,
    [4] = 1 / 4,
    [5] = 1 / 2,
    [6] = 1,
  }

  local beat_sec = clock.get_beat_sec()
  local step_time = beat_sec * 4 * division_factors[division]
  engine.stepTime(step_time)
end
