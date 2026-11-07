--[[
    A death ends the dying life's stretch with no hide, since its rig
    becomes the body's ragdoll, ignores every later entry for that life, and
    gives the dying slot, the body's slot and the push
--]]

--!strict
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local SLOT: number = 50
local GENERATION: number = 3
local BODY: number = 60
local BODY_GENERATION: number = 1
local PUSH_STEPS: number = 127 -- A death's push components, steps to a unit vector's

return function (): (boolean, string | nil)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate
	local Record: any = viewer.Record

	viewer.announce(SLOT, GENERATION, "A")

	for tick: number = 10, 13 do
		local reveals: { any }? = nil
		if tick == 10 then
			reveals = { { slot = SLOT, generation = GENERATION, kind = "Player" } }
		end

		viewer.send({
			tick = tick,
			reveals = reveals,
			records = { { slot = SLOT, generation = GENERATION, position = vector.create(tick, 0, 0) } },
		})
	end

	Interpolate.frame(0)
	if not viewer.pose(SLOT) then
		return false, "The slot drew nothing before its death"
	end

	-- The body's entry comes first, in the same reliable packet as the death
	viewer.announce(BODY, BODY_GENERATION, "A")

	local slot: number, body: number, push: vector =
		Interpolate.death(Record.id(SLOT, GENERATION), Record.id(BODY, BODY_GENERATION), 0, PUSH_STEPS, 0)

	if slot ~= SLOT or body ~= BODY or push ~= vector.create(0, 1, 0) then
		return false, `The death gave slot {slot}, body {body} and push {push}`
	elseif viewer.pose(SLOT) then
		return false, "The dying slot still drew after its death"
	end

	-- The relay's hide for it, a late record and a repeat of its reveal, all for the life that died
	viewer.send({
		tick = 14,
		reveals = { { slot = SLOT, generation = GENERATION, kind = "Player" } },
		hides = { { slot = SLOT, generation = GENERATION } },
		records = { { slot = SLOT, generation = GENERATION, position = vector.zero } },
	})

	Interpolate.frame(1)

	if #viewer.hides ~= 0 then
		return false, "The dying slot's stretch was told closed, where its rig became the body's"
	elseif #viewer.reveals ~= 1 or viewer.pose(SLOT) then
		return false, "An entry for the life that died was revealed or drawn"
	end

	return true, nil
end
