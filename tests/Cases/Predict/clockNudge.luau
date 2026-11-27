--[[
    The clock holds the server's queue at 1 to 3 ticks with its nudge: a
    queue of 4 slows it 2%, an empty one with the client late speeds it 2%,
    and one inside the band leaves it at the simulation rate
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

local FRAMES: number = 75 -- Frames of one tick each, which run 73.5, 75 or 76.5 ticks' worth

return function (): (boolean, string | nil)
	-- A queue of 4 behind command 3, with the client at 8: the lead is 4, above the band
	local slow: any = Harness.new()
	slow.spawn()
	slow.frames(8)
	slow.Predict.receive(slow.owner(slow.twin(3), 4))
	slow.frames(FRAMES)
	if slow.samples - 8 ~= 73 then
		return false, `A clock nudged down 2% ran {slow.samples - 8} ticks in 75 frames, not 73`
	end

	-- A queue of 2 shows a round trip of nothing, and then an empty queue at the client's newest shows a lead of 0
	local fast: any = Harness.new()
	fast.spawn()
	fast.frames(4)
	fast.Predict.receive(fast.owner(fast.twin(2), 2))
	fast.Predict.receive(fast.owner(fast.twin(4), 0))
	fast.frames(FRAMES)
	if fast.samples - 4 ~= 76 then
		return false, `A clock nudged up 2% ran {fast.samples - 4} ticks in 75 frames, not 76`
	end

	-- A queue of 2, inside the band
	local held: any = Harness.new()
	held.spawn()
	held.frames(4)
	held.Predict.receive(held.owner(held.twin(2), 2))
	held.frames(FRAMES)
	if held.samples - 4 ~= FRAMES then
		return false, `A clock inside the band ran {held.samples - 4} ticks in 75 frames, not 75`
	end

	if #slow.corrections + #fast.corrections + #held.corrections ~= 0 then
		return false, "A state on the predicted path raised a correction"
	end

	return true, nil
end
