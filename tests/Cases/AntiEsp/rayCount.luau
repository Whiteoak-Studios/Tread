--[[
    A pair's test casts only as many rays as the settings give: the first
    two of a player pair's with antiEsp.rays at 2, and a sleeper's head
    alone with sleepers.rays at 1
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.rays = 2
		server.sleepers.rays = 1
	end)
	harness.wall = Harness.solid

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", vector.create(0, 0, -50))
	local sleeper: number = harness:body("Sleeper", vector.create(40, 0, 0))

	Harness.AntiEsp.isHidden(viewer, target)
	harness:slice(0)

	local step: any = harness.shared.step
	if #harness.rays ~= 2 then
		return false, `The player pair cast {#harness.rays} rays, not the 2 the settings give`
	elseif harness:endingAt(vector.create(0, step.standing / 2, -50)) ~= 1 then
		return false, "The second ray was not the one to the hull's center"
	end

	-- Before the player pair's 30 Hz recheck inside the near radius, so the sleeper's new pair is the only one due
	Harness.AntiEsp.isHidden(viewer, target)
	Harness.AntiEsp.isHidden(viewer, sleeper)
	harness:slice(0.02)

	-- Facing 0 lies along -Z, so the head is half the box's length that way
	local box: any = step.lyingBox
	local head: vector = vector.create(40, box.lift, -box.length / 2)
	if #harness.rays ~= 1 or harness:endingAt(head) ~= 1 then
		return false, `The sleeper cast {#harness.rays} rays, not the one to its head at {head}`
	end

	return true, nil
end
