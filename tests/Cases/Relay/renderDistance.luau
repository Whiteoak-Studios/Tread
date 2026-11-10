--[[
    A viewer whose client sent a render distance of 400 studs is sent a
    player at 300 and not one at 600, while a viewer that sent none keeps
    the server's whole radius and is sent both
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local DISTANCE: number = 400
local NEAR: number = 300
local FAR: number = 600
local WHOLE: number = 1000 -- The example's relevancy.leave
local RUNS: number = 3 -- Relay ticks, each enough for a reveal or a hide to arrive

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local short: any = harness:viewer("Short")
	local whole: any = harness:viewer("Whole")
	local near: number = harness:spawn("Player", vector.create(NEAR, 0, 0))
	local far: number = harness:spawn("Player", vector.create(FAR, 0, 0))

	Harness.Relay.setDistance(short.viewer.key, DISTANCE)
	harness:runs(RUNS)

	if not short.drawn[near] then
		return false, `The viewer at {DISTANCE} studs was not sent the player at {NEAR}`
	elseif short.drawn[far] then
		return false, `The viewer at {DISTANCE} studs was sent the player at {FAR}`
	elseif not whole.drawn[near] or not whole.drawn[far] then
		return false, `The viewer that sent no distance was not sent both players, at {NEAR} and {FAR}`
	end

	-- Once it sends the whole radius, the farther player is sent too
	Harness.Relay.setDistance(short.viewer.key, WHOLE)
	harness:runs(RUNS)

	if not short.drawn[near] or not short.drawn[far] then
		return false, "The viewer back at the server's whole radius was not sent both players"
	end

	return true, nil
end
