local screens = {}

local screen_h = 64
local screen_w = 128
local outer_circle_radius, inner_circle_radius = 28, 18
local direction_symbols = { ">", "<", "~" }
local circle_x, circle_y = screen_w / 2, screen_h / 2

screens.screen_h = screen_h
screens.screen_w = screen_w
screens.outer_circle_radius = outer_circle_radius
screens.inner_circle_radius = inner_circle_radius
screens.direction_symbols = direction_symbols
screens.circle_x = circle_x
screens.circle_y = circle_y


function screens.draw_screen_indicator(number_of_screens, selected_voice_screen, screen_mode)
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

function screens.draw_mode_indicator(screen_mode)
    local indicator_width = 1
    local indicator_height = 3
    local indicator_spacing = 2

    local start_y = (screen_h / 2) - ((indicator_height + indicator_spacing) / 1)

    for i = 1, 2 do
        local y_position = start_y + (i - 1) * (indicator_height + indicator_spacing)
        local x_position = screen_w - indicator_width - 2 -- Align to the right side

        if i == screen_mode then
            screen.level(15)
        else
            screen.level(3)
        end

        screen.rect(x_position, y_position, indicator_width, indicator_height)
        screen.fill()
    end
end

function screens.draw_delay_screen()
    local center_x = screen_w / 2
    local center_y = screen_h / 2
    local base_radius = 25
    local trail_decay = 0.9

    local delay_time
    if params:get("delay_sync") == 1 then
        delay_time = clock.get_beat_sec() * utils.delay_division_factors[params:get("delay_division")] * 4
    else
        delay_time = params:get("delay_time")
    end

    local rotation_speed = math.pi * 2 * delay_time / 5
    local feedback = params:get("delay_feedback")

    local mix = params:get("delay_mix")
    local dot_size = 1 + (mix * 2)
    local rotate = params:get("rotate")
    local rotate_offset = rotate * math.pi * 2

    local radius_variation = base_radius * 0.15 * (rotate - 0.5) * 2 -- Scale between -15% and +15%
    local radius = base_radius + radius_variation

    local num_points = math.floor(20 + feedback * 10)

    for i = 1, num_points do
        local angle = i * (math.pi * 2 / num_points) + rotation_speed * clock.get_beats() + rotate_offset
        local trail_level = 15 * (trail_decay ^ i)

        local offset = radius + math.sin(angle * feedback) * 8

        screen.level(math.floor(trail_level))

        local x = center_x + math.cos(angle) * offset
        local y = center_y + math.sin(angle) * offset

        screen.circle(x, y, dot_size)
        screen.fill()
    end
end

function screens.draw_step_circle(steps, current_step)
    draw_step_visual(steps, current_step)
    draw_direction_symbol()
    draw_step_division()
    draw_step_count(steps)
    draw_pattern_grid()
end

function screens.draw_random_pan_amp_screen()
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
end

function screens.draw_random_fifth_octave_screen()
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
end

---------------------

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
        local brightness = current_pattern[i] == 1 and (i == pattern_index and 15 or 5) or
            (i == pattern_index and 3 or 1)
        local x = pattern_x + ((i - 1) % row_length) * (cell_size + cell_spacing)
        local y = pattern_y + math.floor((i - 1) / row_length) * (cell_size + cell_spacing)

        screen.level(brightness)
        screen.rect(x, y, cell_size, cell_size)
        screen.fill()
    end
end

return screens
