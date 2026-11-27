--[[
    After a freeze the clock keeps at most the game's time debt, 8 ticks
    in Frontier Zero, so a 10 s frame runs 8 ticks and the next frame runs
    only its own, with nothing of the freeze left owed
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

return function (): (boolean, string | nil)
	local rig: any = Harness.new()
	rig.spawn()

	rig.frames(1, 10)
	if rig.samples ~= 8 or #rig.moves ~= 8 then
		return false, `A 10 s frame ran {rig.samples} ticks and sent {#rig.moves} Moves, not the debt's 8`
	end

	rig.frames(1)
	if rig.samples ~= 9 then
		return false, `The frame after the freeze ran {rig.samples - 8} ticks, not its own 1`
	end

	-- A debt of 3 keeps 3
	local short: any = Harness.new({ ticks = { debt = 3 } })
	short.spawn()
	short.frames(1, 2.5)
	if short.samples ~= 3 then
		return false, `A 2.5 s frame with a debt of 3 ran {short.samples} ticks`
	end

	return true, nil
end
