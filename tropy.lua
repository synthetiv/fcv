-- tremple ov psychick youth

playhead_x = 1
play_clock = nil

notes = {}
erasing = false

attract_distance = 32
attraction = 1 / 128

repel_distance = 16
repulsion = 1 / 128

friction = 1 / 2

width = 128

-- TODO: clip dx
max_dx = 1

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

function tick()
	-- update motion
	for i, note in ipairs(notes) do
		for j, other in ipairs(notes) do
			if note ~= other then
				note.dx = note.dx * friction
				local d = wrap_distance(note.x, other.x)
				-- TODO: what about a kind of logarithmic curve from 0 to 'repel_distance', then a parabola after that...?
				if d <= attract_distance then
					-- one-pole smoother toward the other note
					note.dx = note.dx + d * attraction
				end
				if d <= repel_distance then
					-- more repulsion the closer we are
					note.dx = note.dx - (repel_distance / d) * repulsion
				end
			end
		end
	end
	-- move notes
	for i, note in ipairs(notes) do
		note.x = note.x + note.dx
		if note.x < 1 then
			note.x = note.x + width
		elseif note.x > width then
			note.x = note.x - width
		end
	end
	-- move playhead
	local prev_playhead_x = playhead_x
	playhead_x = playhead_x + 1
	if playhead_x > width then
		playhead_x = playhead_x - width
	end
	-- play notes
	for i, note in ipairs(notes) do
		-- TODO: is this the best way to detect collisions?
		if note.x - note.dx > prev_playhead_x and note.x <= playhead_x then
			if erasing then
				table.remove(notes, i)
			else
				print 'ping'
			end
		end
	end
end

function init()
	play_clock = clock.run(function()
		while true do
			clock.sync(4/width)
			tick()
			redraw()
		end
	end)
end

function redraw()
	screen.clear()

	screen.move(playhead_x, 1)
	screen.line_rel(0, 63)
	screen.line_width(1)
	screen.level(4)
	screen.stroke()
	
	for i, note in ipairs(notes) do
		screen.circle(note.x, 32, 1)
		screen.level(6)
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
				dx = 0
			})
		end
	end
end