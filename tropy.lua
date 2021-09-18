-- tremple ov psychick youth

playhead_x = 1
play_clock = nil

notes = {}
erasing = false

width = 128

tick_length = 4 / width

d_bound = 16

friction = 0.001
inertia = 3
ddx_max = 0.001

l_decay = 0.9

function wrap_distance(a, b)
	local d = b - a
	if d > width / 2 then
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

-- TODO: create 'anchor' notes that don't move -- or 'heavy' notes that move less
-- TODO: create repeating note groups -- all repetitions exert + are subject to influence, but their distance from one another is fixed
function tick()
	-- move notes
	for i, note in ipairs(notes) do
		note.x = note.x + note.dx
		if note.x < 1 then
			note.x = note.x + width
		elseif note.x > width then
			note.x = note.x - width
		end
		note.l = note.l * l_decay
	end
	-- move playhead
	local prev_playhead_x = playhead_x
	playhead_x = playhead_x + 1
	if playhead_x > width then
		playhead_x = playhead_x - width
	end
	-- update motion
	for i, note in ipairs(notes) do
		for j, other in ipairs(notes) do
			if note ~= other then
				local d = wrap_distance(note.x, other.x)
				-- base attraction or repulsion: (|d|d_bound - d_bound^2) / (d^2)
				-- 'd_bound' is the distance at which there is NO attraction or repulsion
				-- below d_bound, repulsion increases to infinity as d approaches 0
				-- above d_bound, attraction increases to 0.25 at 2*d_bound, then falls off gradually
				-- 'inertia' reduces the influence of attraction/repulsion forces
				local ddx = sign(d) * d_bound * (math.abs(d) - d_bound) / d / d / (1 + inertia)
				-- 'ddx_max' clips change in dx, preventing sudden bounces, allowing notes to float past one another instead
				-- TODO: it also kinda inhibits all motion within clusters of notes when friction is nonzero.
				-- does pre-scaling ddx (before clipping) help?
				ddx = ddx / (1 + friction)
				if math.abs(ddx) > ddx_max then
					ddx = ddx_max * sign(ddx)
				end
				-- 'friction' reduces speed over time, damping oscillation
				-- when friction is high, notes will tend to cluster together, with tighter spacing in the center of the cluster
				note.dx = ddx + note.dx / (1 + friction)
			end
		end
	end
	-- detect note-playhead collisions
	for i, note in ipairs(notes) do
		-- TODO:
		-- find intersection of two lines...
		-- playhead line: x = playhead_x + t
		-- note line: x = note.x + note.dx * t
		-- playhead_x + t = note.x + note.dx * t
		-- t - note.dx * t = note.x - playhead_x
		-- t * (1 - note.dx) = note.x - playhead_x
		-- t = (note.x - playhead_x) / (1 - note.dx)
		local t_collision = (note.x - playhead_x) / (1 - note.dx)
		if t_collision > 0 and t_collision <= 1 then
			if erasing then
				table.remove(notes, i)
			else
				clock.run(function()
					clock.sleep(t_collision * tick_length * clock.get_beat_sec())
					print 'ping'
					note.l = 1
				end)
			end
		end
	end
end

function init()
	play_clock = clock.run(function()
		while true do
			clock.sync(tick_length)
			tick()
			redraw()
		end
	end)
end

function redraw()
	screen.clear()
	screen.aa(1)

	screen.move(playhead_x + 0.5, 1)
	screen.line_rel(0, 63)
	screen.line_width(1)
	screen.level(1)
	screen.stroke()
	
	for i, note in ipairs(notes) do
		screen.circle(note.x, 32, 1)
		if note.x < 1 then
			screen.circle(note.x + width, 32, 1)
		elseif note.x > width then
			screen.circle(note.x - width, 32, 1)
		end
		screen.level(3 + math.floor(12 * note.l))
		screen.fill()
	end

	screen.update()
end

function key(n, z)
	if n == 2 then
		erasing = z == 1
	elseif n == 3 then
		if z == 1 then
			table.insert(notes, {
				x = playhead_x,
				dx = 0,
				l = 1
			})
		end
	end
end