--[[
    A withheld block carries its records whole, so one holding a change
    record is refused, the acknowledgment left where the relay blocks put
    it, while the same change in a relay block rebuilds and is acknowledged
--]]

--!strict
local Changes = require("../../Fixtures/Interpolate/Changes")
local Refuses = require("../../Fixtures/Codec/Refuses")
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local SHOWN: number = 5 -- Sent to the target, so its copy carries it
local WITHHELD: number = 6 -- Withheld from the target
local GENERATION: number = 1
local FIRST: number = 10
local START: vector = vector.create(200, 0, -100)
local STEP: vector = vector.create(0.5, 0, 0) -- Where its next record moves it

return function (): (boolean, string | nil)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate
	viewer.announce(SHOWN, GENERATION, "A")
	viewer.announce(WITHHELD, GENERATION, "A")

	local function record(slot: number, at: vector): buffer
		return Changes.record({ slot = slot, generation = GENERATION, position = at })
	end

	-- The copy and the withheld block beside it, both whole
	Interpolate.receive(Changes.block({
		sequence = 1,
		tick = FIRST,
		reveals = { { slot = SHOWN, generation = GENERATION, kind = "Player" } },
		records = { record(SHOWN, START) },
	}))
	Interpolate.withheld(Changes.block({ sequence = 1, tick = FIRST, records = { record(WITHHELD, START) } }))

	if not Interpolate.isWithheld(WITHHELD) then
		return false, "A withheld block of whole records drew nothing"
	end

	-- 1) The next withheld block names its record as a change, which no withheld block carries
	local refused: boolean, why: string = Refuses(
		"never as change records",
		Interpolate.withheld,
		Changes.block({
			sequence = 1,
			tick = FIRST + 1,
			changes = { Changes.change(record(WITHHELD, START + STEP), record(WITHHELD, START), 1) },
		})
	)
	if not refused then
		return false, `A withheld block holding a change was read: {why}`
	end

	local acknowledged: number, mask: number = Interpolate.received()
	if acknowledged ~= 1 or mask ~= 0 then
		return false, `The refused withheld block moved the acknowledgment to {acknowledged} with {mask}`
	end

	-- 2) The same change for the copy's slot, in a relay block, rebuilds and is acknowledged
	Interpolate.receive(Changes.block({
		sequence = 2,
		tick = FIRST + 1,
		changes = { Changes.change(record(SHOWN, START + STEP), record(SHOWN, START), 1) },
	}))

	acknowledged, mask = Interpolate.received()
	if acknowledged ~= 2 or mask ~= 1 then
		return false, `The relay block's change left the acknowledgment at {acknowledged} with {mask}, not 2 with 1`
	end

	return true, nil
end
