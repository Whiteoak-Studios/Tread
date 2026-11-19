--[[
    A withheld block opens a stretch for a player the target isn't sent,
    with no reveal of its own, its look applied and the slot withheld while
    its records keep coming. It never moves the acknowledgment, a copy's
    hide of a slot it carries closes nothing, a copy's reveal ends the
    withholding, and a slot it stops carrying is dropped after 4 intervals
--]]

--!strict
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local WITHHELD: number = 7 -- Never sent to the target
local CULLED: number = 8 -- Sent to the target, then culled from it
local GENERATION: number = 1
local FIRST: number = 10
local CULL: number = 13 -- The tick the target stops being sent CULLED
local SHOWN: number = 16 -- The tick the target is sent WITHHELD again
local STOP: number = 18 -- The last tick a withheld block carries CULLED
local LAST: number = 30
local FRAME: number = 0.05 -- Seconds a frame, one relay tick at 20 Hz
local INTERVALS: number = 4 -- Relay intervals unrefreshed past which a withheld slot goes
local OUTFIT: { [string]: any } = { chest = 3, colors = { 1, 2 } }

return function (): (boolean, string | nil)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate

	viewer.announce(WITHHELD, GENERATION, "A")
	viewer.announce(CULLED, GENERATION, "A")

	local dropped: number? = nil
	for tick: number = FIRST, LAST do
		-- The copy of the target's own block: CULLED until its cull, WITHHELD revealed again from SHOWN
		local copy: { [string]: any } = { tick = tick, reveals = {}, hides = {}, records = {} }
		if tick == FIRST then
			table.insert(copy.reveals, { slot = CULLED, generation = GENERATION, kind = "Player" })
		elseif tick == CULL then
			table.insert(copy.hides, { slot = CULLED, generation = GENERATION })
		elseif tick == SHOWN then
			table.insert(copy.reveals, { slot = WITHHELD, generation = GENERATION, kind = "Player" })
		end

		if tick < CULL then
			table.insert(copy.records, { slot = CULLED, generation = GENERATION, position = vector.create(tick, 0, 0) })
		elseif tick >= SHOWN then
			table.insert(
				copy.records,
				{ slot = WITHHELD, generation = GENERATION, position = vector.create(0, 0, tick) }
			)
		end

		viewer.send(copy)

		-- The withheld block beside it, in the same flush: WITHHELD until SHOWN, CULLED from its cull until STOP
		local records: { any } = {}
		if tick < SHOWN then
			table.insert(records, { slot = WITHHELD, generation = GENERATION, position = vector.create(0, 0, tick) })
		end
		if tick >= CULL and tick <= STOP then
			table.insert(records, { slot = CULLED, generation = GENERATION, position = vector.create(tick, 0, 0) })
		end

		local looks: { any }? = nil
		if tick == FIRST then
			looks = { { slot = WITHHELD, generation = GENERATION, outfit = OUTFIT } }
		end

		viewer.withhold({ tick = tick, records = records, looks = looks })
		Interpolate.frame(FRAME)

		-- 1) Every withheld block leaves the copy's acknowledgment as it was: each sequence sent, 16 behind at most
		local acknowledged: number, mask: number = Interpolate.received()
		local earlier: number = math.min(2 ^ (tick - FIRST), 2 ^ 16) - 1
		if acknowledged ~= viewer.sequence or mask ~= earlier then
			return false, `At tick {tick} the viewer acknowledged {acknowledged} with mask {mask}, not the copy's`
		end

		-- 2) Each slot is withheld exactly while the withheld block carries it, and a few intervals past
		local withheld: boolean = Interpolate.isWithheld(WITHHELD)
		local culled: boolean = Interpolate.isWithheld(CULLED)
		if tick > STOP and dropped == nil and not culled then
			dropped = tick
		end

		if withheld ~= (tick < SHOWN) then
			return false, `At tick {tick} slot {WITHHELD} read withheld {withheld}`
		elseif culled ~= (tick >= CULL and dropped == nil) then
			return false, `At tick {tick} slot {CULLED} read withheld {culled}`
		elseif Interpolate.renderTime() >= FIRST and not viewer.pose(WITHHELD) then
			return false, `At tick {tick} the withheld slot drew nothing`
		elseif tick <= STOP and Interpolate.renderTime() > CULL and not viewer.pose(CULLED) then
			return false, `At tick {tick}, past the copy's hide, the culled slot drew nothing`
		end
	end

	-- 3) The withheld slot was revealed once, with its look, and the culled one only by the copy
	if #viewer.reveals ~= 2 or viewer.reveals[1].slot ~= CULLED or viewer.reveals[2].slot ~= WITHHELD then
		return false, `The blocks told {#viewer.reveals} reveals, not the culled slot's and then the withheld one's`
	elseif viewer.reveals[2].kind ~= "Player" or viewer.reveals[2].outfit.chest ~= OUTFIT.chest then
		return false, "The withheld slot's reveal wasn't a player in its withheld look"
	end

	-- 4) The culled slot's copy hide closed nothing, and it went once the withheld block stopped carrying it
	if #viewer.hides ~= 1 or viewer.hides[1] ~= CULLED then
		return false, `The blocks told {#viewer.hides} hides, not the culled slot's once`
	elseif dropped == nil or dropped - STOP <= INTERVALS - 1 or dropped - STOP > INTERVALS + 1 then
		return false, `The culled slot's withholding ended at tick {dropped}, not {INTERVALS} intervals after {STOP}`
	elseif viewer.pose(CULLED) then
		return false, "The dropped withheld slot still drew"
	end

	-- 5) One whose copy was lost carries the next sequence, which only the copy's arrival may acknowledge
	local before: number, beforeMask: number = Interpolate.received()
	viewer.withhold({
		tick = LAST + 1,
		sequence = viewer.sequence + 1,
		records = { { slot = WITHHELD, generation = GENERATION, position = vector.zero } },
	})

	local after: number, afterMask: number = Interpolate.received()
	if after ~= before or afterMask ~= beforeMask then
		return false, `A withheld block whose copy was lost moved the acknowledgment to {after}`
	end

	-- 6) A withheld block never carries reveals, hides or footsteps
	local refused: boolean = not pcall(viewer.withhold, {
		tick = LAST + 1,
		reveals = { { slot = WITHHELD, generation = GENERATION, kind = "Player" } },
	})
	if not refused then
		return false, "A withheld block with a reveal was read"
	end

	return true, nil
end
