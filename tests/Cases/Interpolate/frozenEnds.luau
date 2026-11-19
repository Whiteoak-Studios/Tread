--[[
    A frozen body ends with no reveal, told once with frozen false: on a
    later copy of its hide anti-ESP didn't make, its slot freed or renewed,
    its death and a spectate's restart. A copy anti-ESP made leaves it
--]]

--!strict
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local COPIED: number = 3 -- Ended by a later copy of its hide that anti-ESP didn't make
local FREED: number = 4 -- By its slot freed
local RENEWED: number = 5 -- By its slot given a new life
local DIED: number = 6 -- By its death
local RESTARTED: number = 7 -- By a spectate's restart
local STANDS: number = 8 -- Left standing by a later copy anti-ESP made, and by an older one it didn't
local BODY: number = 60 -- The slot the death names its body by
local GENERATION: number = 1
local REVEALED: number = 20 -- The relay tick every slot is revealed at
local HIDDEN: number = 22 -- The one every slot's hide is first carried at
local PAST: number = 0.5 -- Seconds of frame that take the render time past the hides

return function (): (boolean, string | nil)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate
	local Record: any = viewer.Record

	-- What each hide callback was told of each slot, in the order told
	local told: { [number]: { boolean } } = {}
	Interpolate.onHide(function (slot: number, frozen: boolean)
		told[slot] = told[slot] or {}
		table.insert(told[slot], frozen)
	end)

	-- Whether a slot was told frozen at its hide and then ended the times given
	local function ended(slot: number, times: number): boolean
		local heard: { boolean } = told[slot] or {}
		if #heard ~= 1 + times or heard[1] ~= true then
			return false
		end

		for index: number = 2, #heard do
			if heard[index] ~= false then
				return false
			end
		end

		return true
	end

	local slots: { number } = { COPIED, FREED, RENEWED, DIED, RESTARTED, STANDS }
	local reveals: { any } = {}
	local records: { any } = {}
	local hides: { any } = {}
	for _, slot: number in slots do
		viewer.announce(slot, GENERATION, "A")
		table.insert(reveals, { slot = slot, generation = GENERATION, kind = "Player" })
		table.insert(records, { slot = slot, generation = GENERATION, position = vector.create(slot, 0, 0) })
		table.insert(hides, { slot = slot, generation = GENERATION, culled = true })
	end

	viewer.send({ tick = REVEALED, reveals = reveals, records = records })
	viewer.send({ tick = HIDDEN, hides = hides })
	Interpolate.frame(0)
	Interpolate.frame(PAST)

	for _, slot: number in slots do
		if not ended(slot, 0) then
			return false, `Slot {slot}'s hide anti-ESP made left no frozen body`
		end
	end

	-- 1) A later copy of a hide not yet acknowledged carries its own run's reason
	viewer.send({
		tick = HIDDEN + 1,
		hides = {
			{ slot = COPIED, generation = GENERATION, culled = false },
			{ slot = STANDS, generation = GENERATION, culled = true },
		},
	})

	if not ended(COPIED, 1) then
		return false, "A later copy of the hide that anti-ESP didn't make left the frozen body standing"
	elseif not ended(STANDS, 0) then
		return false, "A later copy of the hide that anti-ESP made ended the frozen body"
	end

	-- A copy older than the newest heard is a straggler, whatever it says
	viewer.send({ tick = HIDDEN, hides = { { slot = STANDS, generation = GENERATION, culled = false } } })
	if not ended(STANDS, 0) then
		return false, "An older copy of the hide ended the frozen body its newest copy keeps"
	end

	-- 2) The slot table frees the slot, or gives it a new life
	viewer.announce(FREED, GENERATION, nil)
	viewer.announce(RENEWED, GENERATION + 1, "A")
	if not ended(FREED, 1) or not ended(RENEWED, 1) then
		return false, "A frozen body's slot freed or given a new life left it standing"
	end

	-- 3) Its death, which no stretch is open to take as a dying rig's
	viewer.announce(BODY, GENERATION, "A")
	Interpolate.death(Record.id(DIED, GENERATION), Record.id(BODY, GENERATION), 0, 0, 0)
	if not ended(DIED, 1) then
		return false, "A frozen body's death left it standing"
	end

	-- 4) A spectate's restart ends every one left, here the two still standing, and none already ended again
	Interpolate.restart(HIDDEN + 2)
	if not ended(RESTARTED, 1) or not ended(STANDS, 1) then
		return false, "A spectate's restart left a frozen body standing"
	end

	for _, slot: number in { COPIED, FREED, RENEWED, DIED } do
		if not ended(slot, 1) then
			return false, `Slot {slot}'s frozen body was told ended {#told[slot] - 1} times, not once`
		end
	end

	-- A frozen body once ended is ended for good: its hide's next copy tells nothing more
	viewer.send({ tick = HIDDEN + 3, hides = { { slot = RESTARTED, generation = GENERATION, culled = false } } })
	if not ended(RESTARTED, 1) then
		return false, "A copy of the hide ended a frozen body a second time"
	end

	return true, nil
end
