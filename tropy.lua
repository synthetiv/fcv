-- tremple ov psychick youth

playhead_x = 1
play_clock = nil

function tick()
	playhead_x = playhead_x + 1
	if playhead_x > 128 then
		playhead_x = playhead_x - 128
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

	screen.update()
end