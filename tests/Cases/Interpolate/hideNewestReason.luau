--[[
    A hide still waiting takes the reason of its newest copy, since each
    copy of a pending hide carries its own run's: a later copy turns a
    frozen body off or on, and a copy older than the newest heard is ignored
--]]

--!strict
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local TURNED_OFF: number = 3 -- Anti-ESP made its first copy, and not its later one
local TURNED_ON: number = 4 -- Anti-ESP made only its later copy
local STRAGGLER: number = 5 -- Anti-ESP made the copy heard first, and not an older copy heard after it
local GENERATION: number = 1
local REVEALED: number = 20 -- The relay tick every slot is revealed at
local FIRST: number = 22 -- The tick each hide's first copy is written at
local PAST: number = 0.5 -- Seconds of frame that take the render time past the hides

return function (): (boolean, string | nil)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate

	-- What each hide callback was told of each slot, in the order told
	local told: { [number]: { boolean } } = {}
	Interpolate.onHide(function (slot: number, frozen: boolean)
		told[slot] = told[slot] or {}
		table.insert(told[slot], frozen)
	end)

	local reveals: { any } = {}
	local records: { any } = {}
	for _, slot: number in { TURNED_OFF, TURNED_ON, STRAGGLER } do
		viewer.announce(slot, GENERATION, "A")
		table.insert(reveals, { slot = slot, generation = GENERATION, kind = "Player" })
		table.insert(records, { slot = slot, generation = GENERATION, position = vector.create(slot, 0, 0) })
	end

	viewer.send({ tick = REVEALED, reveals = reveals, records = records })

	-- Each hide rides a block every relay tick until it is acknowledged, each copy with its own run's reason
	viewer.send({
		tick = FIRST,
		hides = {
			{ slot = TURNED_OFF, generation = GENERATION, culled = true },
			{ slot = TURNED_ON, generation = GENERATION, culled = false },
		},
	})
	viewer.send({
		tick = FIRST + 1,
		hides = {
			{ slot = TURNED_OFF, generation = GENERATION, culled = false },
			{ slot = TURNED_ON, generation = GENERATION, culled = true },
			{ slot = STRAGGLER, generation = GENERATION, culled = true },
		},
	})

	-- The block before it, arriving late
	viewer.send({ tick = FIRST, hides = { { slot = STRAGGLER, generation = GENERATION, culled = false } } })

	Interpolate.frame(0)
	if next(told) ~= nil then
		return false, "A hide was told before the render time reached it"
	end

	Interpolate.frame(PAST)

	local wanted: { [number]: boolean } = { [TURNED_OFF] = false, [TURNED_ON] = true, [STRAGGLER] = true }
	for slot: number, frozen: boolean in wanted do
		local heard: { boolean }? = told[slot]
		if heard == nil or #heard ~= 1 then
			return false, `Slot {slot}'s hide was told {heard and #heard or 0} times, not once`
		elseif heard[1] ~= frozen then
			return false, `Slot {slot}'s hide was told with frozen {heard[1]}, not its newest copy's {frozen}`
		end
	end

	return true, nil
end
