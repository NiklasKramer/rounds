--_ Rounds

engine.name = 'Rounds'
local g = grid.connect()

steps = 16
active_step = 0
sync = 0

function generate_cubes()
  local positions = {}
  for l = 0, 1 do
    for k = 0, 1 do
      for m = 0, 1 do
        for n = 0, 1 do
          for i = 1, 2 do
            for j = 1, 2 do
              table.insert(positions, { (k * 8) + (n * 2) + j + 2, (l * 8) + (m * 2) + i + 2 })
            end
          end
        end
      end
    end
  end
  return positions
end

local step_positions = generate_cubes()

function grid_key(x, y, z)
  if steps == 64 then
    for i = 1, steps do
      local pos = step_positions[i]
      if pos[1] == x and pos[2] == y then
        if z == 1 then
          local current_value = params:get("active_" .. i)
          params:set("active_" .. i, 1 - current_value)
        end
      end
    end
  elseif steps == 32 then
    local step_order_32 = { 1, 3, 2, 4, 5, 7, 6, 8, 9, 11, 10, 12, 13, 15, 14, 16, 17, 19, 18, 20, 21, 23, 22, 24, 25, 27, 26, 28, 29, 31, 30, 32 }
    for i = 1, steps do
      local step_index = step_order_32[i]
      local pos1 = step_positions[(step_index * 2) - 1]
      local pos2 = step_positions[(step_index * 2)]
      if (pos1[1] == x and pos1[2] == y) or (pos2[1] == x and pos2[2] == y) then
        if z == 1 then
          local current_value = params:get("active_" .. step_index)
          params:set("active_" .. step_index, 1 - current_value)
        end
      end
    end
  elseif steps == 16 then
    for i = 1, steps do
      local pos1 = step_positions[(i * 4) - 3]
      local pos2 = step_positions[(i * 4) - 2]
      local pos3 = step_positions[(i * 4) - 1]
      local pos4 = step_positions[i * 4]
      if (pos1[1] == x and pos1[2] == y) or (pos2[1] == x and pos2[2] == y)
          or (pos3[1] == x and pos3[2] == y) or (pos4[1] == x and pos4[2] == y) then
        if z == 1 then
          local current_value = params:get("active_" .. i)
          params:set("active_" .. i, 1 - current_value)
        end
      end
    end
  elseif steps == 8 then
    for i = 1, steps do
      local pos1 = step_positions[(i * 8) - 7]
      local pos2 = step_positions[(i * 8) - 6]
      local pos3 = step_positions[(i * 8) - 5]
      local pos4 = step_positions[(i * 8) - 4]
      local pos5 = step_positions[(i * 8) - 3]
      local pos6 = step_positions[(i * 8) - 2]
      local pos7 = step_positions[(i * 8) - 1]
      local pos8 = step_positions[i * 8]
      if (pos1[1] == x and pos1[2] == y) or (pos2[1] == x and pos2[2] == y)
          or (pos3[1] == x and pos3[2] == y) or (pos4[1] == x and pos4[2] == y)
          or (pos5[1] == x and pos5[2] == y) or (pos6[1] == x and pos6[2] == y)
          or (pos7[1] == x and pos7[2] == y) or (pos8[1] == x and pos8[2] == y) then
        if z == 1 then
          local current_value = params:get("active_" .. i)
          params:set("active_" .. i, 1 - current_value)
        end
      end
    end
  elseif steps == 4 then
    for i = 1, steps do
      for j = 0, 15 do
        local pos = step_positions[(i * 16) - j]
        if pos[1] == x and pos[2] == y then
          if z == 1 then
            local current_value = params:get("active_" .. i)
            params:set("active_" .. i, 1 - current_value)
          end
        end
      end
    end
  end

  grid_redraw()
end

function grid_redraw()
  g:all(0)

  local active_step_brightness = 10
  local step_brightness = 1

  local step_order_32 = { 1, 3, 2, 4, 5, 7, 6, 8, 9, 11, 10, 12, 13, 15, 14, 16, 17, 19, 18, 20, 21, 23, 22, 24, 25, 27, 26, 28, 29, 31, 30, 32 }

  if steps == 64 then
    for i = 1, steps do
      local pos = step_positions[i]
      if params:get("active_" .. i) == 1 then
        g:led(pos[1], pos[2], step_brightness)
      end
    end
  elseif steps == 32 then
    for i = 1, steps do
      local step_index = step_order_32[i]
      local pos1 = step_positions[(step_index * 2) - 1]
      local pos2 = step_positions[(step_index * 2)]
      if params:get("active_" .. step_index) == 1 then
        g:led(pos1[1], pos1[2], step_brightness)
        g:led(pos2[1], pos2[2], step_brightness)
      end
    end
  elseif steps == 16 then
    for i = 1, steps do
      local pos1 = step_positions[(i * 4) - 3]
      local pos2 = step_positions[(i * 4) - 2]
      local pos3 = step_positions[(i * 4) - 1]
      local pos4 = step_positions[i * 4]
      if params:get("active_" .. i) == 1 then
        g:led(pos1[1], pos1[2], step_brightness)
        g:led(pos2[1], pos2[2], step_brightness)
        g:led(pos3[1], pos3[2], step_brightness)
        g:led(pos4[1], pos4[2], step_brightness)
      end
    end
  elseif steps == 8 then
    for i = 1, steps do
      local pos1 = step_positions[(i * 8) - 7]
      local pos2 = step_positions[(i * 8) - 6]
      local pos3 = step_positions[(i * 8) - 5]
      local pos4 = step_positions[(i * 8) - 4]
      local pos5 = step_positions[(i * 8) - 3]
      local pos6 = step_positions[(i * 8) - 2]
      local pos7 = step_positions[(i * 8) - 1]
      local pos8 = step_positions[i * 8]
      if params:get("active_" .. i) == 1 then
        g:led(pos1[1], pos1[2], step_brightness)
        g:led(pos2[1], pos2[2], step_brightness)
        g:led(pos3[1], pos3[2], step_brightness)
        g:led(pos4[1], pos4[2], step_brightness)
        g:led(pos5[1], pos5[2], step_brightness)
        g:led(pos6[1], pos6[2], step_brightness)
        g:led(pos7[1], pos7[2], step_brightness)
        g:led(pos8[1], pos8[2], step_brightness)
      end
    end
  elseif steps == 4 then
    for i = 1, steps do
      for j = 0, 15 do
        local pos = step_positions[(i * 16) - j]
        if params:get("active_" .. i) == 1 then
          g:led(pos[1], pos[2], step_brightness)
        end
      end
    end
  end

  if active_step > 0 and active_step <= steps then
    if steps == 64 then
      local active_pos = step_positions[active_step]
      g:led(active_pos[1], active_pos[2], active_step_brightness)
    elseif steps == 32 then
      local active_pos1 = step_positions[(step_order_32[active_step] * 2) - 1]
      local active_pos2 = step_positions[step_order_32[active_step] * 2]
      g:led(active_pos1[1], active_pos1[2], active_step_brightness)
      g:led(active_pos2[1], active_pos2[2], active_step_brightness)
    elseif steps == 16 then
      local active_pos1 = step_positions[(active_step * 4) - 3]
      local active_pos2 = step_positions[(active_step * 4) - 2]
      local active_pos3 = step_positions[(active_step * 4) - 1]
      local active_pos4 = step_positions[active_step * 4]
      g:led(active_pos1[1], active_pos1[2], active_step_brightness)
      g:led(active_pos2[1], active_pos2[2], active_step_brightness)
      g:led(active_pos3[1], active_pos3[2], active_step_brightness)
      g:led(active_pos4[1], active_pos4[2], active_step_brightness)
    elseif steps == 8 then
      for j = 0, 7 do
        local active_pos = step_positions[(active_step * 8) - j]
        g:led(active_pos[1], active_pos[2], active_step_brightness)
      end
    elseif steps == 4 then
      for j = 0, 15 do
        local active_pos = step_positions[(active_step * 16) - j]
        g:led(active_pos[1], active_pos[2], active_step_brightness)
      end
    end
  end

  g:refresh()
end

function init()
  init_polls()
  init_params()
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
      clock.run(function()
        if sync == 1 then
          clock.sync(1 / 4)
        end
        engine.start()
      end)
    elseif value == 0 then
      clock.run(function()
        if sync == 1 then
          clock.sync(1 / 4)
        end
        engine.stop()
      end)
    end
  end)

  params:add_binary("sync", "sync", "toggle", 0)
  params:set_action("sync", function(value)
    engine.useSampleLength(1 - value)
    sync = value
    update_step_time()
  end)

  params:add_option("step_division", "Step Division", { "1/32", "1/16", "1/8", "1/4", "1/2", "1" }, 4)
  params:set_action("step_division", function(value)
    update_step_time()
  end)

  params:add_option("steps", "steps", { 4, 8, 16, 32, 64 }, 3)
  params:set_action("steps", function(value)
    if value == 1 then
      steps = 4
    elseif value == 2 then
      steps = 8
    elseif value == 3 then
      steps = 16
    elseif value == 4 then
      steps = 32
    elseif value == 5 then
      steps = 64
    end
    engine.steps(steps)
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

  init_steps_as_params()
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
  local phase_poll = poll.set('position', function(pos)
    active_step = pos + 1
  end)
  phase_poll.time = 0.1
  phase_poll:start()

  metro_grid_refresh = metro.init(function(stage) grid_redraw() end, 1 / 40)
  metro_grid_refresh:start()
end

function clock.tempo_change_handler()
  update_step_time()
end

function clock.transport.start()
  if params:get("sync") == 1 then
    params:set("play/stop", 1)
  end
end

function clock.transport.stop()
  params:set("play/stop", 0)
end

function update_step_time()
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
