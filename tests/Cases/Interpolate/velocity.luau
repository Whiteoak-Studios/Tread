--[[
    A pose's velocity is the distance between the two records it draws
    between over their time apart, exactly zero for a body at rest, and a
    move from rest is drawn over the interval the records after it keep
--]]

--!strict
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local MOVING: number = 4 -- Half a stud along X a tick throughout
local RESTING: number = 8
local STARTING: number = 9 -- At rest through 101, then at 1 and 2 studs along X at 105 and 106
local GENERATION: number = 1
local TOLERANCE: number = 1e-6

return function (): (boolean, string | nil)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate
	local rate: number = viewer.rates.relay

	for _, slot: number in { MOVING, RESTING, STARTING } do
		viewer.announce(slot, GENERATION, "A")
	end

	for tick: number = 100, 106 do
		local reveals: { any } = {}
		if tick == 100 then
			for _, slot: number in { MOVING, RESTING, STARTING } do
				table.insert(reveals, { slot = slot, generation = GENERATION, kind = "Player" })
			end
		end

		local records: { any } = {
			{ slot = MOVING, generation = GENERATION, position = vector.create((tick - 100) * 0.5, 0, 0) },
			{ slot = RESTING, generation = GENERATION, position = vector.create(3, 1, 3) },
		}

		if tick <= 101 then
			table.insert(records, { slot = STARTING, generation = GENERATION, position = vector.zero })
		elseif tick >= 105 then
			table.insert(
				records,
				{ slot = STARTING, generation = GENERATION, position = vector.create(tick - 104, 0, 0) }
			)
		end

		viewer.send({ tick = tick, reveals = reveals, records = records })
	end

	-- 3 ticks behind 106
	Interpolate.frame(0)

	local drawn: boolean, state: any = viewer.pose(MOVING)
	if not drawn or state.velocity ~= vector.create(0.5 * rate, 0, 0) then
		return false, `Half a stud a tick at {rate} Hz drew a velocity of {state.velocity}`
	end

	drawn, state = viewer.pose(RESTING)
	if not drawn or state.velocity ~= vector.zero or state.velocity.x ~= 0 then
		return false, `A body at rest drew a velocity of {state.velocity}, not exactly zero`
	end

	-- At 103 the move toward 105 is still a tick off, since the records after it come a tick apart
	drawn, state = viewer.pose(STARTING)
	if not drawn or state.position ~= vector.zero or state.velocity ~= vector.zero then
		return false, `Before its move began the starting slot drew at {state.position} moving {state.velocity}`
	end

	-- At 104.5, half way through that last tick
	Interpolate.frame(0.075)

	drawn, state = viewer.pose(STARTING)
	if not drawn or math.abs(state.position.x - 0.5) > TOLERANCE then
		return false, `Half way through its first tick of moving the slot drew at {state.position}, not 0.5 along X`
	elseif state.velocity ~= vector.create(rate, 0, 0) then
		return false, `Moving a stud in its first tick the slot drew a velocity of {state.velocity}`
	end

	return true, nil
end
