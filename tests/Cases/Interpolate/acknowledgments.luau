--[[
    The newest relay sequence received and the mask of the 16 before it,
    bit 0 for the one just before, across the u16 wrap: late blocks set
    their bit, duplicates and ones past the mask change nothing
--]]

--!strict
local Viewer = require("../../Fixtures/Interpolate/Viewer")

-- Each block's sequence, and the acknowledgment it leaves
local STEPS: { { sequence: number, newest: number, mask: number } } = {
	{ sequence = 65534, newest = 65534, mask = 0 },
	{ sequence = 65535, newest = 65535, mask = 0b1 },
	{ sequence = 0, newest = 0, mask = 0b11 }, -- Across the wrap
	{ sequence = 2, newest = 2, mask = 0b1110 }, -- 1 missing
	{ sequence = 1, newest = 2, mask = 0b1111 }, -- Late, filling its bit
	{ sequence = 2, newest = 2, mask = 0b1111 }, -- A duplicate
	{ sequence = 65530, newest = 2, mask = 0b10001111 }, -- Late from before the wrap
	{ sequence = 65000, newest = 2, mask = 0b10001111 }, -- Older than the mask holds
	{ sequence = 18, newest = 18, mask = 0b1000000000000000 }, -- 16 ahead, so 2 sits on the top bit
	{ sequence = 40, newest = 40, mask = 0 }, -- 22 ahead, past the mask
	{ sequence = 24, newest = 40, mask = 0b1000000000000000 }, -- 16 back, the top bit
	{ sequence = 23, newest = 40, mask = 0b1000000000000000 }, -- 17 back, past it
}

return function (): (boolean, string | nil)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate

	local newest: number, mask: number = Interpolate.received()
	if newest ~= 0 or mask ~= 0 then
		return false, `Before any block the acknowledgment was {newest} and {mask}, not 0 and 0`
	end

	for index: number, step in STEPS do
		viewer.send({ tick = index, sequence = step.sequence })
		newest, mask = Interpolate.received()

		if newest ~= step.newest or mask ~= step.mask then
			return false,
				`After sequence {step.sequence} it acknowledged {newest} and {mask}, not {step.newest} and {step.mask}`
		end
	end

	return true, nil
end
