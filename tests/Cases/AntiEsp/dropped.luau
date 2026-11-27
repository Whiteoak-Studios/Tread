--[[
    A pair the relay didn't ask about on its last run is dropped at the next
    slice, so a later ask starts it afresh, hidden, while a pair it did ask
    about keeps its verdict; a target gone from the states goes untested
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local AntiEsp: any = Harness.AntiEsp

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local first: number = harness:body("Player", vector.create(0, 0, -30))
	local second: number = harness:body("Player", vector.create(0, 0, -40))

	-- Both are seen, and the relay keeps asking about both
	AntiEsp.isHidden(viewer, first)
	AntiEsp.isHidden(viewer, second)
	harness:slice(0)

	if AntiEsp.isHidden(viewer, first) or AntiEsp.isHidden(viewer, second) then
		return false, "A pair with every ray open was hidden"
	end

	harness:slice(0.1)

	-- The relay's next run asks about the second alone
	AntiEsp.isHidden(viewer, second)
	harness:slice(0.2)

	if not AntiEsp.isHidden(viewer, first) then
		return false, "The pair the relay stopped asking about kept its visible verdict"
	elseif AntiEsp.isHidden(viewer, second) then
		return false, "The pair the relay still asked about lost its verdict"
	end

	-- A target taken out of the states is dropped untested, and its slot's pair starts afresh
	harness.states[first] = nil
	harness:slice(0.6)

	if harness:endingAt(vector.create(0, harness.server.antiEsp.aim.Stand[1].up, -30)) ~= 0 then
		return false, "A target gone from the states was ray-tested"
	end

	harness.states[first] = harness.states[second]
	if not AntiEsp.isHidden(viewer, first) then
		return false, "The dropped pair of a target gone from the states came back with its old verdict"
	end

	return true, nil
end
