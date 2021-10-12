-- tremple ov psychick youth

engine.name = 'Thebangs'
thebangs = include 'thebangs/lib/thebangs_engine'

musicutil = require 'musicutil'
Voice = require 'voice'

playhead_x = 0
play_quant = 6
play_ticks = 0
play_clock = nil
draw_clock = nil

m = nil
g = nil

-- TODO: make it possible to select notes and alter them as a group (select()...)
notes = {}
erasing = false
anchoring = false

function sort()
	table.sort(notes, function(a, b)
		return a.x < b.x
	end)
end
-- a sufficiently successful sequence:
-- current x, home, midi note
-- .67672059549374 .58333333333327 63 = 14 =  2 =  8/7
-- 1.3312846516363 1.333333333333  72 = 23 = 11 = 16/9
-- 1.4866981696884 1.4166666666666 58 = 9  =  9 =  8/5
-- 1.7618660074246 1.7499999999999 69 = 20 =  8 = 32/21
-- 2.132197774293  2.1666666666666 64 = 15 =  3 =  7/6
-- 2.4836666000621 2.4999999999999 61 = 12 =  0 =  1/1
-- 2.8540553411407 3.0833333333333 50 = 1  =  1 = 64/63
-- 2.939992118522  2.7916666666666 62 = 13 =  1 = 64/63
-- 3.3271179416657 3.4583333333333 62 = 13 =  1 = 64/63
-- 3.6888339679937 3.7916666666666 49 = 0  =  0 =  1/1
-- 4.5219987041017 4.5833333333333 63 = 14 =  2 =  8/7
-- 5.2290980524288 5.333333333333  72 = 23 = 11 = 16/9
-- 5.4086146572805 5.4166666666666 58 = 9  =  9 =  8/5
-- 5.7023812998105 5.7499999999999 69 = 20 =  8 = 32/21
-- 6.1343900537404 6.1666666666666 64 = 15 =  3 =  7/6
-- 6.4943222992263 6.583333333333  53 = 4  =  4 =  6/5
-- 6.6226535705355 6.4999999999999 61 = 12 =  0 =  1/1
-- 6.930494659312  7.0833333333333 50 = 1  =  1 = 64/63
-- 7.0169963005057 6.7916666666666 62 = 13 =  1 = 64/63
-- 7.4153014639616 7.4583333333333 62 = 13 =  1 = 64/63
-- 7.7227328302841 7.6666666666662 57 = 8  =  8 = 32/21
-- 7.9339618998232 7.7916666666666 49 = 0  =  0 =  1/1

width = 4

-- TODO: quantization
-- TODO: OT capture

-- TODO: decouple motion calculations from playhead advancement
-- that would allow play head to move in 16th note increments, or in a rhythmic pattern... <-- priority
-- "you could divide the x axis into zones and make the 'playhead' a highlighted zone instead...
-- playhead jumps from zone to zone, notes start as play head crosses them and end as they leave
-- play head region"
tick_length = 1 / 24 -- ppqn

-- TODO: make these overridable on a per-note basis
d_bound = 0.5
friction = 0
damping = 0.005
inertia = 1000
max_repulsion = 10
dx_max = width / 2
home_attraction = 0.8

current_phase = 0
current_increment = math.pi * tick_length / 7
current_force = 0.03

l_decay = 0.9

grid_octave = 2

playing = false
recording = false

non_recorded_notes = Voice.new(16)

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

midi_voices = Voice.new(8)

function calculate_cents()
	ji_cents = {}
	for i, r in ipairs(ji_ratios) do
		ji_cents[i] = math.log(r) * 1200 / math.log(2)
	end
end
ji_ratios = {
	1,
	64/63, -- 1 / 7 / 3 / 3
	8/7, -- 1 / 7
	7/6, -- 7 / 3
	6/5, -- 3 / 5
	4/3, -- 1 / 3
	7/5, --
	3/2, -- 3 / 1
	32/21, -- 1 / 7 / 3
	8/5, -- 1 / 5
	7/4, -- 7 / 1
	16/9 -- 1 / 3 / 3
}
calculate_cents()

root_midi_note = 49 -- just happens to be the root note of the sequence that's currently playing
root_freq = musicutil.note_num_to_freq(root_midi_note)

function play_note(note)
	-- TODO: use arbitrary callbacks as well or instead
	engine.amp(0.01 + note.velocity / 4000)
	local pitch = note.midi_note - root_midi_note
	local octave = math.floor(pitch / 12)
	local r = math.random(2)
	if r > 1 then
		octave = octave + 1
	elseif r > 0 then
		octave = octave - 1
	end
	local pitch_class = pitch % 12
	local cents = ji_cents[pitch_class + 1] + 1200 * octave
	local note_out = math.floor(cents / 100) + root_midi_note
	-- max MIDI bend = 16383; center = 8191
	local bend_frac = ((cents % 100) / 100)
	local bend_out = math.floor(8191.5 * (1 + bend_frac))
	local midi_voice = midi_voices:get()
	local channel = midi_voice.id + 8
	m:pitchbend(bend_out, channel)
	m:note_on(note_out, 100, channel)
	clock.run(function()
		clock.sleep(1/2)
		m:note_off(note_out, 0, channel)
	end)
	midi_voice.on_steal = function()
		m:note_off(note_out, 0, channel)
	end
	-- local hz = root_freq * ji_ratios[pitch_class + 1] * math.pow(2, octave)
	-- engine.hz(hz)
	print(note.midi_note, note_out, bend_frac, bend_out, channel)
	note.l = 1
end

function add_note(midi_note, velocity)
	midi_note = midi_note or 60
	velocity = velocity or 100
	local note = {
		x = playhead_x,
		home = playhead_x,
		y = y or 32,
		dx = 0,
		midi_note = midi_note,
		velocity = velocity,
		hz = musicutil.note_num_to_freq(midi_note),
		mass = (velocity / 127) / math.pow(1.1, (midi_note - 60) / 12),
		l = 0,
		anchor = anchoring
	}
	if recording then
		table.insert(notes, note)
	else
		local slot = non_recorded_notes:get()
		slot.note = note
	end
	play_note(note)
end

function double_width()
	local n_notes = #notes
	for i = 1, n_notes do
		local note = notes[i]
		notes[i + n_notes] = {
			x = note.x + width,
			home = note.home + width,
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
			if note.home >= half_width then
				note.home = note.home - half_width
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

function tick()
	current_phase = current_phase + current_increment
	if current_phase > math.pi then
		current_phase = current_phase - math.pi
	end
	engine.mod1(math.cos(current_phase) * 0.05 + 0.07)
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
	local quant_length = tick_length * play_quant
	if playing then
		playhead_x = playhead_x + tick_length
		if playhead_x >= width then
			playhead_x = playhead_x - width
		end
		play_ticks = play_ticks + 1
		if play_ticks >= play_quant then
			play_ticks = play_ticks - play_quant
		end
	end
	-- update motion
	for i, note in ipairs(notes) do
		if not note.anchor then
			-- tend homeward
			local ddx = home_attraction * wrap_distance(note.x, note.home)
			-- apply current
			ddx = ddx + math.sin(current_phase + note.x / width * 2 * math.pi) * current_force
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
	if playing and play_ticks == 0 then
		-- detect note-playhead collisions
		-- count down instead of up because we may end up removing elements from 'notes', which will
		-- affect elements at indices > i
		for i = #notes, 1, -1 do
			local note = notes[i]
			-- find intersection of two lines...
			-- playhead line: x = playhead_x + quant_length * playing * t
			-- note line: x = note.x + note.dx * t
			-- playhead_x + quant_length * playing * t = note.x + note.dx * t
			-- quant_length * playing * t - note.dx * t = note.x - playhead_x
			-- t * (quant_length * playing - note.dx) = note.x - playhead_x
			-- t = (note.x - playhead_x) / (quant_length - note.dx)
			local t_collision = wrap_distance(playhead_x, note.x) / (quant_length * (playing and 1 or 0) - note.dx)
			if t_collision > 0 and t_collision <= 1 then
				if erasing then
					table.remove(notes, i)
				else
					play_note(note)
				end
			end
		end
	end
	-- decay non-recorded notes
	for i, slot in ipairs(non_recorded_notes.style.slots) do
		if slot.note ~= nil then
			slot.note.l = slot.note.l * l_decay
		end
	end
end

function midi_event(data)
	local message = midi.to_msg(data)
	if message.type == 'note_on' then
		-- TODO: store note lengths
		add_note(message.note, message.vel)
	elseif message.type == 'stop' then
		playing = false
	elseif message.type == 'start' then
		playhead_x = -tick_length
		play_ticks = play_quant
		playing = true
	elseif message.type == 'continue' then
		playing = true
	end
end

function get_grid_note(x, y)
	return grid_octave * 12 + x + (8 - y) * 5
end

function grid_key(x, y, z)
	if x == 1 then
		if y == 1 then
			if z == 1 then
				recording = not recording
			end
		end
	else
		if z == 1 then
			-- TODO: record note ons/offs...
			add_note(get_grid_note(x, y), 100)
		end
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

	params:set('algo', 4)
	engine.release(2.4)
	engine.mod1(0.1)
	engine.mod2(3)
	engine.cutoff(12000)

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
		-- draw link to home
		-- screen.move(x + wrap_distance(note.x, note.home) * scale, 64)
		-- screen.line(x, y)
		-- screen.level(2)
		-- screen.stroke()
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
	g:led(1, 1, recording and 10 or 0)
	note_levels = {}
	for i, note in ipairs(notes) do
		note_levels[note.midi_note] = (note_levels[note.midi_note] or 2) + 15 * note.l
	end
	for i, slot in ipairs(non_recorded_notes.style.slots) do
		if slot.note ~= nil then
			note_levels[slot.note.midi_note] = (note_levels[slot.note.midi_note] or 0) + 15 * slot.note.l
		end
	end
	for y = 1, g.rows do
		for x = 2, g.cols do
			local n = get_grid_note(x, y)
			if note_levels[n] ~= nil then
				g:led(x, y, math.floor(math.min(15, note_levels[n])))
			end
		end
	end
	g:refresh()
end

function key(n, z)
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
