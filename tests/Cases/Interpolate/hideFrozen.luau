--[[
    A hide anti-ESP made closes a player's stretch as a frozen body, told
    with frozen true once the render time passes it, while a player's hide
    it didn't make and an NPC's, a sleeper's or a body's are told false
--]]

--!strict
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local GENERATION: number = 1
local REVEALED: number = 20 -- The relay tick every slot is revealed at
local HIDDEN: number = 22 -- The one every slot is hidden at
local PAST: number = 0.5 -- Seconds of frame that take the render time past the hides

type Hidden = { slot: number, kind: string, culled: boolean, frozen: boolean }

-- Each slot's kind, whether anti-ESP made its hide, and whether its stretch then leaves a frozen body
local SLOTS: { Hidden } = {
	{ slot = 3, kind = "Player", culled = true, frozen = true },
	{ slot = 4, kind = "Player", culled = false, frozen = false },
	{ slot = 5, kind = "Npc", culled = true, frozen = false },
	{ slot = 6, kind = "Sleeper", culled = true, frozen = false },
	{ slot = 7, kind = "Body", culled = true, frozen = false },
}

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
	local hides: { any } = {}
	for _, hidden: Hidden in SLOTS do
		viewer.announce(hidden.slot, GENERATION, "A")
		table.insert(reveals, { slot = hidden.slot, generation = GENERATION, kind = hidden.kind })
		table.insert(
			records,
			{ slot = hidden.slot, generation = GENERATION, position = vector.create(hidden.slot, 0, 0) }
		)
		table.insert(hides, { slot = hidden.slot, generation = GENERATION, culled = hidden.culled })
	end

	viewer.send({ tick = REVEALED, reveals = reveals, records = records })
	viewer.send({ tick = HIDDEN, hides = hides })

	-- The render time lands behind the hides, so each still waits
	Interpolate.frame(0)
	if next(told) ~= nil then
		return false, `A hide was told at render time {Interpolate.renderTime()}, before its tick {HIDDEN}`
	end

	Interpolate.frame(PAST)

	for _, hidden: Hidden in SLOTS do
		local heard: { boolean }? = told[hidden.slot]
		local made: string = hidden.culled and "anti-ESP made" or "anti-ESP didn't make"
		if heard == nil or #heard ~= 1 then
			return false, `The {hidden.kind}'s hide was told {heard and #heard or 0} times, not once`
		elseif heard[1] ~= hidden.frozen then
			return false, `A {hidden.kind}'s hide {made} was told with frozen {heard[1]}, not {hidden.frozen}`
		end
	end

	return true, nil
end
