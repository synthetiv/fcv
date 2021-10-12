Voice = require 'voice'

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
	end)
	esq_voice.on_steal = function()
		m:note_off(note_out, 0, channel)
	end
end

return {
	esq_cents = esq_cents
}
