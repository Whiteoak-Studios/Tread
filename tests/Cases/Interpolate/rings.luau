--[[
    A remote slot's ring keeps its 8 newest records, the newest overwriting
    the oldest, and a record no newer than the ring's newest is dropped
--]]

--!strict
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local SLOT: number = 12
local GENERATION: number = 1
local TOLERANCE: number = 1e-6

return function (): (boolean, string | nil)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate

	viewer.announce(SLOT, GENERATION, "A")

	-- One stud along X a tick, every block at once, so the render time lands 3 ticks behind the newest
	local function send(tick: number, at: vector)
		local reveals: { any }? = nil
		if tick == 100 then
			reveals = { { slot = SLOT, generation = GENERATION, kind = "Player" } }
		end

		viewer.send({
			tick = tick,
			reveals = reveals,
			records = { { slot = SLOT, generation = GENERATION, position = at } },
		})
	end

	for tick: number = 100, 104 do
		send(tick, vector.create(tick, 0, 0))
	end

	Interpolate.frame(0)

	local renderTime: number = Interpolate.renderTime()
	if math.abs(renderTime - 101) > TOLERANCE then
		return false, `Five blocks at once put the render time at {renderTime}, not 3 ticks behind the newest at 101`
	end

	local drawn: boolean, state: any = viewer.pose(SLOT)
	if not drawn or math.abs(state.position.x - 101) > TOLERANCE then
		return false, `The slot drew at {state.position} at render time 101, where its record at 101 puts it`
	end

	-- Five more fill the ring past its 8, so the records at 100 and 101 are overwritten
	for tick: number = 105, 109 do
		send(tick, vector.create(tick, 0, 0))
	end

	drawn = viewer.pose(SLOT)
	if drawn then
		return false, "The slot drew at render time 101 though its ring holds only 102 to 109"
	end

	-- A record at 106 again, somewhere else, is no newer than the ring's newest
	send(106, vector.create(0, 50, 0))

	-- The newest tick the clock estimates is then 109.5, far enough ahead that the render time snaps to 106.5
	Interpolate.frame(0.025)

	renderTime = Interpolate.renderTime()
	if math.abs(renderTime - 106.5) > TOLERANCE then
		return false, `The render time snapped to {renderTime}, not 106.5`
	end

	drawn, state = viewer.pose(SLOT)
	if not drawn then
		return false, "The slot drew nothing at render time 106.5, inside its ring"
	elseif math.abs(state.position.x - 106.5) > TOLERANCE or state.position.y ~= 0 then
		return false, `The slot drew at {state.position}, where the dropped record at 106 would not move it`
	end

	return true, nil
end
