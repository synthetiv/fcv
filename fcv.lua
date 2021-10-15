-- flash crash V

engine.name = 'Lately'
lately = include 'lately/lib/lately_engine'

musicutil = require 'musicutil'
Voice = require 'voice'

playhead_x = 0
play_clock = nil
draw_clock = nil

ppqn = 24

quant_ticks = 1
quant_accumulator = 0
play_x = 0

width = 4

d_bound = 0.5
friction = 0
damping = 0.005
inertia = 1000
mass = 0.8
dx_max = width / 2
homing = 0.8

current_phase = 0
current_increment = math.pi / ppqn / 7
current_force = 0.05

l_decay = 0.9

grid_octave = 2

playing = false
recording = false

grid_erasing = false
keys_held = {}
n_keys = 128

k1_held = false

m = nil
g = nil

nodes = {}
non_recorded_nodes = Voice.new(16)
erasing = false

function sort_nodes()
	table.sort(nodes, function(a, b)
		return a.home < b.home
	end)
end

function nodes_where(p)
	local selection = {}
	for i, node in ipairs(nodes) do
		if p(node) then
			table.insert(selection, node)
		end
	end
	return selection
end

function do_where(p, a)
	local selection = nodes_where(p)
	for i, node in ipairs(selection) do
		a(node)
		-- clean up, if needed (like if we just added a random offset to all nodes)
		node.x = node.x % width
		node.home = node.home % width
	end
end

function do_all(a)
	do_where(function() return true end, a)
end

function shift(d)
	do_all(function(node)
		node.x = node.x + d
		node.home = node.home + d
	end)
end

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

ji_cents = {}
function calculate_cents()
	for i, r in ipairs(ji_ratios) do
		ji_cents[i] = math.log(r) * 1200 / math.log(2)
	end
end

ji_ratios = {
	1,
	64/63, --  /7/3/3
	8/7,   --  /7
	7/6,   -- 7/3
	6/5,   -- 3/5
	4/3,   --  /3
	7/5,   --
	3/2,   -- 3
	32/21, --  /7/3
	8/5,   --  /5
	7/4,   -- 7
	16/9   --  /3/3
}
calculate_cents()
root_midi_note = 49
root_freq = musicutil.note_num_to_freq(root_midi_note)

-- alt tuning:
--[[
ji_ratios = {
	1,
	49/48,   -- 7*7/3
	21/20,   -- 7*3/5
	147/128, -- 7*7*3
	7/6,     -- 7/3
	4/3,     --  /3
	7/5,     --
	3/2,     -- 3
	49/32,   -- 7*7
	14/9,    -- 7/3/3
	7/4,     -- 7
	16/9,    --  /3/3
}
calculate_cents()
root_midi_note = 51
root_freq = musicutil.note_num_to_freq(49) * 8/7
--]]

esq_voices = Voice.new(8)

function esq_cents(cents, velocity, length)
	local note_out = math.floor(cents / 100) + root_midi_note
	-- max MIDI bend = 16383; center = 8191
	local bend_frac = ((cents % 100) / 100)
	local bend_out = math.floor(8191.5 * (1 + bend_frac))
	local esq_voice = esq_voices:get()
	local channel = esq_voice.id + 8
	m:pitchbend(bend_out, channel)
	m:note_on(note_out, velocity, channel)
	clock.run(function()
		clock.sleep(length)
		m:note_off(note_out, 0, channel)
		esq_voice:release()
	end)
	esq_voice.on_steal = function()
		m:note_off(note_out, 0, channel)
	end
end

function get_pitch_class_and_octave(midi_note)
	local pitch = midi_note - root_midi_note
	local octave = math.floor(pitch / 12)
	local pitch_class = pitch % 12
	return pitch_class, octave
end

function lately_note(midi_note)
	local pitch_class, octave = get_pitch_class_and_octave(midi_note)
	local ratio = ji_ratios[pitch_class + 1] * math.pow(2, octave)
	local hz = root_freq * ratio
	engine.note_on(hz, math.pow(0.6, ratio))
	clock.run(function()
		clock.sleep(1/8)
		engine.note_off()
	end)
end

function esq_note(midi_note)
	local pitch_class, octave = get_pitch_class_and_octave(midi_note)
	local cents = ji_cents[pitch_class + 1] + 1200 * octave
	esq_cents(cents, 100, 1/2)
end

function play_esq(node)
	local octave = math.random(2) - 1
	esq_note(node.midi_note + 12 * octave)
end
-- do_all(function(n) n.play = play_esq end)

function play_lately(node)
	print(get_pitch_class_and_octave(node.midi_note))
	clock.run(function()
		local rate = math.pow(2, math.random(3))
		-- for n = 1, math.random(4) do
			lately_note(node.midi_note)
			-- clock.sleep(clock.get_beat_sec()/rate)
		-- end
	end)
end
-- do_all(function(n) n.play = play_lately end)

function add_node(midi_note, velocity)
	midi_note = midi_note or 60
	velocity = velocity or 100
	local node = {
		x = playhead_x,
		home = playhead_x,
		y = y or 32,
		dx = 0,
		midi_note = midi_note,
		velocity = velocity,
		play = play_esq,
		l = 0
	}
	if recording then
		table.insert(nodes, node)
		sort_nodes()
	else
		local slot = non_recorded_nodes:get()
		slot.node = node
	end
	node:play()
	node.l = 1
	screen.ping()
end

function double_width()
	local n_nodes = #nodes
	for i = 1, n_nodes do
		local node = nodes[i]
		-- reduce all distances -- if home is near 0 and x is "before" home, x may be near width --
		-- and when width is doubled, node will be pulled all the way across the screen and may tangle
		-- with other nodes
		node.x = node.home + wrap_distance(node.home, node.x)
		local new_node = {
			x = node.x + width,
			home = node.home + width,
			dx = node.dx,
			midi_note = node.midi_note,
			velocity = node.velocity,
			l = 0,
			play = node.play
		}
		node.x = node.x % (width * 2)
		new_node.x = new_node.x % (width * 2)
		nodes[i + n_nodes] = new_node
	end
	width = width * 2
end

function halve_width()
	local half_width = width / 2
	-- build a new table of nodes containing only those we've just heard
	local new_nodes = {}
	for i, node in ipairs(nodes) do
		local d = wrap_distance(node.x, playhead_x)
		if d > 0 and d <= half_width then
			if node.x >= half_width then
				node.x = node.x - half_width
			end
			if node.home >= half_width then
				node.home = node.home - half_width
			end
			table.insert(new_nodes, node)
		end
	end
	-- wrap play head position if needed
	if playhead_x >= half_width then
		playhead_x = playhead_x - half_width
	end
	width = width / 2
	nodes = new_nodes
end

function tick()
	current_phase = current_phase + current_increment
	if current_phase > math.pi then
		current_phase = current_phase - math.pi
	end
	-- move nodes
	for i, node in ipairs(nodes) do
		node.x = node.x + node.dx
		while node.x < 0 do
			node.x = node.x + width
		end
		while node.x >= width do
			node.x = node.x - width
		end
		node.l = node.l * l_decay
	end
	-- move playhead
	local quant = quant_ticks / ppqn
	if playing then
		playhead_x = playhead_x + 1 / ppqn
		if playhead_x >= width then
			playhead_x = playhead_x - width
		end
		quant_accumulator = (quant_accumulator + 1) % quant_ticks
	end
	-- update motion
	for i, node in ipairs(nodes) do
		-- tend homeward
		local ddx = homing * wrap_distance(node.x, node.home)
		-- apply current
		ddx = ddx + math.sin(current_phase + node.x / width * 2 * math.pi) * current_force
		for j, other in ipairs(nodes) do
			if node ~= other then
				local d = wrap_distance(node.x, other.x)
				local abs_d = math.abs(d)
				-- 'd_bound' is the distance at which there is NO attraction or repulsion
				local node_bound = d_bound * mass
				if abs_d < 1.5 * node_bound then
					-- repel
					ddx = ddx + d - sign(d) * node_bound
				else
					-- attract
					ddx = ddx - sign(d) * math.max(0, 2 * node_bound - math.abs(d))
				end
				-- TODO: handle note lengths too... a few options:
				-- 1. ignore
				-- 2. increase d_bound from centers of nodes <-- this seems like the most interesting option
				-- 3. get distances between starts + ends of notes and choose the smallest
			end
		end
		-- 'inertia' reduces the influence of attraction/repulsion forces
		-- TODO: note that if mass < 0, ddx will be multiplied... which may account for some of the craziness you've observed
		ddx = ddx / mass / inertia
		-- 'damping' reduces speed over time, damping oscillation
		-- when damping is 1, nodes will find a comfortable spot and stay there, tending to cluster
		-- together, with tighter spacing in the center of the cluster; at 0, they'll move constantly
		node.dx = ddx + node.dx * (1 - damping)
		-- friction applies an opposing force, up to a limit defined by mass * friction constant
		node.dx = sign(node.dx) * math.max(0, math.abs(node.dx) - mass * friction)
		-- finally, clamp overall speed
		if math.abs(node.dx) > dx_max then
			node.dx = dx_max * sign(node.dx)
		end
	end
	if playing and quant_accumulator == 0 then
		-- TODO: fix missed nodes when quant > 1
		-- detect node-playhead collisions
		-- count down instead of up because we may end up removing elements from 'nodes', which will
		-- affect elements at indices > i
		for i = #nodes, 1, -1 do
			local node = nodes[i]
			-- find intersection of two lines...
			-- playhead line: x = playhead_x + quant * playing * t
			-- node line: x = node.x + node.dx * t
			-- playhead_x + quant * playing * t = node.x + node.dx * t
			-- quant * playing * t - node.dx * t = node.x - playhead_x
			-- t * (quant * playing - node.dx) = node.x - playhead_x
			-- t = (node.x - playhead_x) / (quant - node.dx)
			local t_collision = wrap_distance(playhead_x, node.x) / (quant * (playing and 1 or 0) - node.dx)
			if t_collision > 0 and t_collision <= 1 then
				if erasing then
					table.remove(nodes, i)
				else
					local did_erase = false
					if grid_erasing then
						for k = 1, n_keys do
							if not did_erase and keys_held[k] then
								local held_note = get_grid_id_note(k)
								if held_note == node.midi_note then
									table.remove(nodes, i)
									did_erase = true
								end
							end
						end
					end
					if not did_erase then
						node:play()
						node.l = 1
						screen.ping()
					end
				end
			end
		end
	end
	-- decay non-recorded nodes
	for i, slot in ipairs(non_recorded_nodes.style.slots) do
		if slot.node ~= nil then
			slot.node.l = slot.node.l * l_decay
		end
	end
end

function midi_event(data)
	local message = midi.to_msg(data)
	if message.type == 'note_on' then
		-- TODO: store note lengths
		add_node(message.note, message.vel)
	elseif message.type == 'stop' then
		playing = false
	elseif message.type == 'start' then
		playhead_x = -1 / ppqn
		quant_accumulator = quant_ticks
		playing = true
	elseif message.type == 'continue' then
		playing = true
	end
end

function get_grid_note(x, y)
	return grid_octave * 12 + x + (8 - y) * 5
end

function get_grid_id_note(id)
	local x = (id - 1) % g.cols + 1
	local y = math.floor(id / g.cols) + 1
	return get_grid_note(x, y)
end

function grid_key(x, y, z)
	if x == 1 then
		if y == 1 then
			if z == 1 then
				recording = not recording
			end
		elseif y == 2 then
			grid_erasing = z == 1
		end
	else
		local id = x + (y - 1) * g.cols
		keys_held[id] = z == 1
		if not grid_erasing and z == 1 then
			-- TODO: record note ons/offs...
			-- ...no, really
			add_node(get_grid_note(x, y), 100)
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

	lately.add_params()
	params:bang()

	play_clock = clock.run(function()
		while true do
			clock.sync(1 / ppqn)
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

local screen_width = 127 -- columns 1 and 128 will be identical; 127 unique columns of px
local y_center = 32.5
function redraw()
	local scale = screen_width / width
	screen.clear()
	screen.blend_mode('add')
	if k1_held then
		screen.aa(0)
		-- draw beats
		screen.level(1)
		for i = 0, width do
			local level = 1
			if i % 4 == 0 then
				level = 2
			end
			screen.rect(i * scale, 0, 1, 1)
			screen.rect(i * scale, 64, 1, -1)
			screen.level(level)
			screen.fill()
		end
		-- draw playhead
		screen.move(playhead_x * scale + 0.5, 0)
		screen.line_rel(0, 64)
		screen.line_width(1)
		screen.level(1)
		screen.stroke()
	end
	screen.aa(1)
	-- draw nodes
	screen.move(-127, y_center) -- TODO: ?
	for offset = -screen_width, screen_width, screen_width do
		for i, node in ipairs(nodes) do
			local home_x = (node.home * scale) % screen_width + 0.5 + offset
			local x = home_x + wrap_distance(node.home, node.x) * scale
			-- TODO: only draw this node if we can see it or it's adjacent to one we can see
			local home_y = y_center - (node.midi_note - root_midi_note) / (2 + math.abs(wrap_distance(node.home, node.x)) * scale / 5)
			local y = y_center - (node.midi_note - root_midi_note)
			local offset = 0
			screen.line(home_x, home_y)
			screen.level(2)
			screen.stroke()
			screen.move(home_x, home_y)
			screen.line(x, y)
			screen.level(2 + math.floor(2 * node.l))
			screen.stroke()
			-- draw node itself
			screen.circle(x, y, 1.2 + 1.2 * node.l)
			screen.level(2 + math.floor(13 * node.l))
			screen.fill()
			screen.move(home_x, home_y)
		end
	end
	screen.line(255, y_center)
	screen.level(2)
	screen.stroke()
	screen.update()
end

function grid_redraw()
	g:all(0)
	g:led(1, 1, recording and 10 or 1)
	g:led(1, 2, grid_erasing and 10 or 1)
	note_levels = {}
	for i, node in ipairs(nodes) do
		note_levels[node.midi_note] = (note_levels[node.midi_note] or 2) + 15 * node.l
	end
	for i, slot in ipairs(non_recorded_nodes.style.slots) do
		if slot.node ~= nil then
			note_levels[slot.node.midi_note] = (note_levels[slot.node.midi_note] or 0) + 15 * slot.node.l
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
		k1_held = z == 1
	elseif n == 2 then
		erasing = z == 1
	elseif n == 3 then
		if z == 1 then
			add_node()
		end
	end
end
