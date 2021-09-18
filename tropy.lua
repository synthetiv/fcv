-- tremple ov psychick youth

playhead_x = 1
play_clock = nil

notes = {}
erasing = false

function tick()
	local prev_playhead_x = playhead_x
	playhead_x = playhead_x + 1
	if playhead_x > 128 then
		playhead_x = playhead_x - 128
	end
	for i, note in ipairs(notes) do
		if note.x > prev_playhead_x and note.x <= playhead_x then
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
			clock.sync(4/128)
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
			table.insert(notes, { x = playhead_x })
		end
	end
end