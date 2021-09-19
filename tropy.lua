-- tremple ov psychick youth

engine.name = 'Thebangs'
thebangs = include 'thebangs/lib/thebangs_engine'

musicutil = require 'musicutil'

playhead_x = 0 -- TODO: hmmmm
play_clock = nil

notes = {}
erasing = false
anchoring = false

width = 4

tick_length = 1 / 24 -- ppqn

d_bound = 1 / 2 -- notes will tend to stay 1/8th note apart

friction = 0.0001
inertia = 1000
max_repulsion = 0.05
dx_max = width / 2

l_decay = 0.9

function wrap_distance(a, b)
	local d = b - a
	if d >= width / 2 then
		d = d - width
	elseif d < -width / 2 then
		d = d + width
	end
	return d
end

function sign(n)
	if n >= 0 then return 1 end
	return -1
end

function play_note(note)
	engine.hz(musicutil.note_num_to_freq(note.midi_note))
	note.l = 1
end

function add_note(midi_note)
	local note = {
		x = playhead_x,
		dx = 0,
		midi_note = midi_note or 60,
		l = 0,
		anchor = anchoring
	}
	table.insert(notes, note)
	play_note(note)
end

-- TODO: something seems to go weird after enough double/halve_width()s -- all notes cluster together strangely...
function double_width()
	local n_notes = #notes
	for i = 1, n_notes do
		local note = notes[i]
		notes[i + n_notes] = {
			x = note.x + width,
			dx = note.dx,
			midi_note = note.midi_note,
			l = 0,
			anchor = note.anchor
		}
	end
	width = width * 2
end

function halve_width()
	local half_width = width / 2
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
			if note.x < 0 then
				note.x = note.x + width
			elseif note.x >= width then
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
			for j, other in ipairs(notes) do
				if note ~= other then
					local d = wrap_distance(note.x, other.x)
					-- base attraction or repulsion: (|d|d_bound - d_bound^2) / (d^2)
					-- 'd_bound' is the distance at which there is NO attraction or repulsion
					-- below d_bound, repulsion increases to infinity as d approaches 0
					-- above d_bound, attraction increases to 0.25 at 2*d_bound, then falls off gradually
					-- max_repulsion keeps repulsion force from hitting infinity,
					-- so that notes can float past one another instead of bouncing off
					ddx = ddx + sign(d) * math.max(-max_repulsion, d_bound * (math.abs(d) - d_bound) / d / d)
				end
			end
			-- 'inertia' reduces the influence of attraction/repulsion forces
			ddx = ddx / (1 + inertia)
			-- 'friction' reduces speed over time, damping oscillation
			-- when friction is high, notes will tend to cluster together, with tighter spacing in the center of the cluster
			note.dx = ddx + note.dx / (1 + friction)
			-- finally, clamp overall speed
			if math.abs(note.dx) > dx_max then
				note.dx = dx_max * sign(note.dx)
			end
		end
	end
	-- detect note-playhead collisions
	for i, note in ipairs(notes) do
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
				-- TODO: sometimes notes don't get deleted when there are lots in one place, and I think maybe that's because removing them here throws off ipairs...?
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
		add_note(message.note)
	end
end

function init()
	
	m = midi.connect(1).device
	m.event = midi_event

	thebangs.add_additional_synth_params()
	params:add_separator()
	thebangs.add_voicer_params()

	play_clock = clock.run(function()
		while true do
			clock.sync(tick_length)
			tick()
			redraw()
		end
	end)
end

function redraw()
	local scale = 128 / width

	screen.clear()
	screen.aa(0)

	screen.move(playhead_x * scale + 0.5, 1)
	screen.line_rel(0, 63)
	screen.line_width(1)
	screen.level(1)
	screen.stroke()
	
	screen.aa(1)
	
	for i, note in ipairs(notes) do
		local x = note.x * scale
		local y = 64 - note.midi_note / 2
		local r = note.anchor and 1.4 or 1
		screen.circle(x, y, r)
		if note.anchor then
			screen.circle(x, 64, 1)
		end
		if x <= 0 then
			screen.circle(x + 128, y, r)
			if note.anchor then
				screen.circle(x + 128, 64, 1)
			end
		elseif x > 128 then
			screen.circle(x - 128, y, r)
			if note.anchor then
				screen.circle(x - 128, 64, 1)
			end
		end
		screen.level(3 + math.floor(12 * note.l))
		screen.fill()
	end

	screen.update()
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