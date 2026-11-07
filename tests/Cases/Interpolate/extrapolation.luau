--[[
    Past its newest record a slot goes on along its last two for one
    interval more, then holds, and two records on different epochs or
    platforms are never drawn between
--]]

--!strict
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local RUNNING: number = 2 -- A stud along X a tick, its records stopping at 101
local TELEPORTED: number = 13 -- At 0 on epoch 0, then from 10 on epoch 1
local BOARDED: number = 14 -- In world space, then on platform 5
local GENERATION: number = 1
local TOLERANCE: number = 1e-6

return function (): (boolean, string | nil)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate
	local rate: number = viewer.rates.relay
	local onEpoch: number = viewer.word({ epoch = 1 })

	for _, slot: number in { RUNNING, TELEPORTED, BOARDED } do
		viewer.announce(slot, GENERATION, "A")
	end

	local reveals: { any } = {}
	for _, slot: number in { RUNNING, TELEPORTED, BOARDED } do
		table.insert(reveals, { slot = slot, generation = GENERATION, kind = "Player" })
	end

	viewer.send({
		tick = 100,
		reveals = reveals,
		records = {
			{ slot = RUNNING, generation = GENERATION, position = vector.zero },
			{ slot = TELEPORTED, generation = GENERATION, position = vector.zero },
			{ slot = BOARDED, generation = GENERATION, position = vector.zero },
		},
	})

	viewer.send({
		tick = 101,
		records = {
			{ slot = RUNNING, generation = GENERATION, position = vector.create(1, 0, 0) },
			{ slot = TELEPORTED, generation = GENERATION, position = vector.create(10, 0, 0), word = onEpoch },
			{ slot = BOARDED, generation = GENERATION, position = vector.create(2, 0, 0), platform = 5 },
		},
	})

	viewer.send({
		tick = 102,
		records = { { slot = TELEPORTED, generation = GENERATION, position = vector.create(11, 0, 0), word = onEpoch } },
	})

	viewer.send({ tick = 103 })

	-- 3 ticks behind 103, then half a tick on, to 100.5
	Interpolate.frame(0)
	Interpolate.frame(0.025)

	local drawn: boolean, state: any = viewer.pose(TELEPORTED)
	if not drawn or state.position ~= vector.zero or state.velocity ~= vector.zero then
		return false, `Before its new epoch the slot drew at {state.position} moving {state.velocity}, toward it`
	end

	drawn, state = viewer.pose(BOARDED)
	if not drawn or state.position ~= vector.zero or state.platform ~= 0 then
		return false, `Before boarding the slot drew at {state.position} on platform {state.platform}`
	end

	-- To 101.5, past the running slot's newest record by half an interval
	Interpolate.frame(0.05)

	drawn, state = viewer.pose(RUNNING)
	if not drawn or math.abs(state.position.x - 1.5) > TOLERANCE then
		return false, `Half an interval past its newest record the slot drew at {state.position}, not 1.5 along X`
	elseif state.velocity ~= vector.create(rate, 0, 0) then
		return false, `Going on past its newest record the slot drew a velocity of {state.velocity}`
	end

	drawn, state = viewer.pose(TELEPORTED)
	if not drawn or math.abs(state.position.x - 10.5) > TOLERANCE or state.epoch ~= 1 then
		return false, `On its new epoch the slot drew at {state.position} on epoch {state.epoch}`
	end

	drawn, state = viewer.pose(BOARDED)
	if not drawn or state.position ~= vector.create(2, 0, 0) or state.platform ~= 5 then
		return false, `Past boarding the slot drew at {state.position} on platform {state.platform}, not as it boarded`
	elseif state.velocity ~= vector.zero then
		return false, "A slot that boarded a platform drew a velocity from its world space record"
	end

	-- To 103.5, two and a half intervals past, where it holds one interval past the newest
	Interpolate.frame(0.1)

	drawn, state = viewer.pose(RUNNING)
	if not drawn or math.abs(state.position.x - 2) > TOLERANCE then
		return false, `Two and a half intervals past its newest record the slot drew at {state.position}, not 2 along X`
	end

	return true, nil
end
