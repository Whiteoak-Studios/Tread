--[[
    A render distance past relevancy.leave acts as relevancy.leave: at 2,000
    studs a player at 960 is not entered and one at 940 is, as at the
    example's 950 and 1,000; and setDistance refuses what is no distance
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local DISTANCE: number = 2000
local INSIDE: number = 940
local OUTSIDE: number = 960 -- Inside 2,000 times 0.95, outside 950
local RUNS: number = 3 -- Relay ticks, each enough for a reveal to arrive

local REFUSED: { any } = { 0, -400, 0 / 0, "400", false }

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")
	local inside: number = harness:spawn("Player", vector.create(INSIDE, 0, 0))
	local outside: number = harness:spawn("Player", vector.create(0, 0, OUTSIDE))

	for _, value: any in REFUSED do
		if pcall(Harness.Relay.setDistance, client.viewer.key, value) then
			return false, `setDistance took {value}`
		end
	end

	Harness.Relay.setDistance(client.viewer.key, DISTANCE)
	harness:runs(RUNS)

	if not client.drawn[inside] then
		return false, `At {DISTANCE} studs the viewer was not sent the player at {INSIDE}`
	elseif client.drawn[outside] then
		return false, `At {DISTANCE} studs the viewer was sent the player at {OUTSIDE}, past relevancy.enter`
	end

	return true, nil
end
