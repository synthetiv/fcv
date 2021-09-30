-- tremple ov psychick youth

engine.name = 'Thebangs'
thebangs = include 'thebangs/lib/thebangs_engine'

musicutil = require 'musicutil'

playhead_x = 0 -- TODO: hmmmm
play_clock = nil
draw_clock = nil

m = nil
g = nil

-- TODO: make it possible to select notes and alter them as a group
notes = {}
erasing = false
anchoring = false

width = 4

-- TODO: decouple motion calculations from playhead advancement
-- that would allow play head to move in 16th note increments, or in a rhythmic pattern...
-- "you could divide the x axis into zones and make the 'playhead' a highlighted zone instead...
-- playhead jumps from zone to zone, notes start as play head crosses them and end as they leave
-- play head region"
tick_length = 1 / 24 -- ppqn

-- TODO: make these overridable on a per-note basis
d_bound = 2 / 3
friction = 0.0001
damping = 0.001
inertia = 1000
max_repulsion = 10
dx_max = width / 2

l_decay = 0.9

grid_octave = 2

function wrap_distance(a, b)
	local d = b - a
	while d > width / 2 do
		d = d - width
	end
	while d < -width / 2 do
		d = d + width
	end
	return d
end

function sign(n)
	if n > 0 then
		return 1
	elseif n < 0 then
		return -1
	end
	return 0
end

function play_note(note)
	-- TODO: use arbitrary callbacks as well or instead
	engine.amp(0.01 + note.velocity / 4000)
	-- TODO: support non-12TET
	engine.hz(note.hz)
	note.l = 1
end

function add_note(midi_note, velocity)
	local note = {
		x = playhead_x,
		y = y or 32,
		dx = 0,
		midi_note = midi_note or 60,
		velocity = velocity or 100,
		l = 0,
		anchor = anchoring
	}
	note.hz = musicutil.note_num_to_freq(note.midi_note)
	local octave = (note.midi_note - 60) / 12
	note.mass = (note.velocity / 127) / math.pow(1.1, octave)
	table.insert(notes, note)
	play_note(note)
end

function double_width()
	local n_notes = #notes
	for i = 1, n_notes do
		local note = notes[i]
		notes[i + n_notes] = {
			x = note.x + width,
			dx = note.dx,
			midi_note = note.midi_note,
			velocity = note.velocity,
			l = 0,
			anchor = note.anchor,
			hz = note.hz,
			mass = note.mass
		}
	end
	width = width * 2
end

function halve_width()
	local half_width = width / 2
	-- build a new table of notes containing only those we've just heard
	local new_notes = {}
	for i, note in ipairs(notes) do
		local d = wrap_distance(note.x, playhead_x)
		if d > 0 and d <= half_width then
			if note.x >= half_width then
				note.x = note.x - half_width
			end
			table.insert(new_notes, note)
		end
	end
	-- wrap play head position if needed
	if playhead_x >= half_width then
		playhead_x = playhead_x - half_width
	end
	width = width / 2
	notes = new_notes
end

-- TODO: create repeating note groups -- all repetitions exert + are subject to influence, but their distance from one another is fixed
function tick()
	-- move notes
	for i, note in ipairs(notes) do
		if note.anchor then
			note.dx = 0
		else
			note.x = note.x + note.dx
			while note.x < 0 do
				note.x = note.x + width
			end
			while note.x >= width do
				note.x = note.x - width
			end
		end
		note.l = note.l * l_decay
	end
	-- move playhead
	playhead_x = playhead_x + tick_length
	if playhead_x >= width then
		playhead_x = playhead_x - width
	end
	-- update motion
	for i, note in ipairs(notes) do
		if not note.anchor then
			local ddx = 0
			-- TODO: leftward drift... wtf? it's as if notes are responding only to *some* other notes' forces...
			for j, other in ipairs(notes) do
				if note ~= other then
					local d = wrap_distance(note.x, other.x)
					local abs_d = math.abs(d)
					-- 'd_bound' is the distance at which there is NO attraction or repulsion
					local note_bound = d_bound * other.mass
					if abs_d < 1.5 * note_bound then
						-- repel
						ddx = ddx + d - sign(d) * note_bound
					else
						-- attract
						ddx = ddx - sign(d) * math.max(0, 2 * note_bound - math.abs(d))
					end
					-- TODO: handle note lengths too... a few options:
					-- 1. ignore
					-- 2. increase d_bound from centers of notes <-- this seems like the most interesting option
					-- 3. get distances between starts + ends of notes and choose the smallest
				end
			end
			-- 'inertia' reduces the influence of attraction/repulsion forces
			-- TODO: note that if mass < 0, ddx will be multiplied... which may account for some of the craziness you've observed
			ddx = ddx / note.mass / inertia
			-- 'damping' reduces speed over time, damping oscillation
			-- when damping is 1, notes will find a comfortable spot and stay there, tending to cluster
			-- together, with tighter spacing in the center of the cluster; at 0, they'll move constantly
			note.dx = ddx + note.dx * (1 - damping)
			-- friction applies an opposing force, up to a limit defined by mass * friction constant
			note.dx = sign(note.dx) * math.max(0, math.abs(note.dx) - note.mass * friction)
			-- finally, clamp overall speed
			if math.abs(note.dx) > dx_max then
				note.dx = dx_max * sign(note.dx)
			end
		end
	end
	-- detect note-playhead collisions
	-- count down instead of up because we may end up removing elements from 'notes', which will
	-- affect elements at indices > i
	for i = #notes, 1, -1 do
		local note = notes[i]
		-- find intersection of two lines...
		-- playhead line: x = playhead_x + tick_length * t
		-- note line: x = note.x + note.dx * t
		-- playhead_x + tick_length * t = note.x + note.dx * t
		-- tick_length * t - note.dx * t = note.x - playhead_x
		-- t * (tick_length - note.dx) = note.x - playhead_x
		-- t = (note.x - playhead_x) / (tick_length - note.dx)
		local t_collision = wrap_distance(playhead_x, note.x) / (tick_length - note.dx)
		if t_collision > 0 and t_collision <= 1 then
			if erasing then
				table.remove(notes, i)
			else
				clock.run(function()
					clock.sleep(t_collision * tick_length * clock.get_beat_sec())
					play_note(note)
				end)
			end
		end
	end
end

function midi_event(data)
	local message = midi.to_msg(data)
	if message.type == 'note_on' then
		-- TODO: store note lengths
		add_note(message.note, message.vel)
	end
end

function get_grid_note(x, y)
	return grid_octave * 12 + x + (8 - y) * 5
end

function grid_key(x, y, z)
	if z == 1 then
		add_note(get_grid_note(x, y), 100)
	end
end

function init()
	
	m = midi.connect(1).device
	if m ~= nil then
		m.event = midi_event
	end
	
	g = grid.connect()
	g.key = grid_key

	thebangs.add_additional_synth_params()
	params:add_separator()
	thebangs.add_voicer_params()

	play_clock = clock.run(function()
		while true do
			clock.sync(tick_length)
			tick()
		end
	end)
	
	draw_clock = clock.run(function()
		while true do
			clock.sleep(1/15)
			redraw()
			grid_redraw()
		end
	end)
end

function redraw()
	local scale = 127 / width

	screen.clear()
	screen.aa(0)

	-- draw beats
	screen.level(1)
	for i = 0, width do
		screen.rect(i * scale, 0, 1, 1)
		screen.fill()
	end

	-- draw playhead
	screen.move(playhead_x * scale + 0.5, 0)
	screen.line_rel(0, 64)
	screen.line_width(1)
	screen.level(1)
	screen.stroke()
	
	-- draw notes
	screen.aa(1)
	for i, note in ipairs(notes) do
		-- TODO: draw to indicate lengths
		local x = note.x * scale + 0.5
		local y = 64 - note.midi_note / 2
		local r = note.anchor and 1.4 or 1
		-- draw bound
		--screen.circle(x, y, d_bound * note.mass * scale)
		--screen.level(2)
		--screen.stroke()
		-- draw note itself
		screen.circle(x, y, r)
		if note.anchor then
			screen.circle(x, 64, 1)
		end
		if x <= 0 then
			screen.circle(x + 127, y, r)
			if note.anchor then
				screen.circle(x + 127, 64, 1)
			end
		elseif x > 127 then
			screen.circle(x - 127, y, r)
			if note.anchor then
				screen.circle(x - 127, 64, 1)
			end
		end
		screen.level(3 + math.floor(12 * note.l))
		screen.fill()
	end

	screen.update()
end

function grid_redraw()
	g:all(0)
	
	note_levels = {}
	for i, note in ipairs(notes) do
		note_levels[note.midi_note] = (note_levels[note.midi_note] or 2) + 15 * note.l
	end
	
	for y = 1, g.rows do
		for x = 1, g.cols do
			local n = get_grid_note(x, y)
			if note_levels[n] ~= nil then
				g:led(x, y, math.floor(math.min(15, note_levels[n])))
			end
		end
	end

	g:refresh()
end

function key(n, z)
	-- TODO: key combos for halve/double?
	if n == 1 then
		anchoring = z == 1
	elseif n == 2 then
		erasing = z == 1
	elseif n == 3 then
		if z == 1 then
			add_note()
		end
	end
end