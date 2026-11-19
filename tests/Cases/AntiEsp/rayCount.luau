--[[
    A pair's test casts only as many rays as the settings give: a player
    pair's two with antiEsp.aim.Stand cut to its first two points, and a
    sleeper's head alone with sleepers.rays at 1
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local KEPT: number = 2 -- The standing points the cut list keeps

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(function (_: any, server: any)
		local points: { any } = server.antiEsp.aim.Stand
		for index: number = #points, KEPT + 1, -1 do
			points[index] = nil
		end

		server.sleepers.rays = 1
	end)
	harness.wall = Harness.solid

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", vector.create(0, 0, -50))
	local sleeper: number = harness:body("Sleeper", vector.create(40, 0, 0))

	Harness.AntiEsp.isHidden(viewer, target)
	harness:slice(0)

	-- The second point, the left shoulder, lies to the viewer's left, -X, as it looks along -Z
	local shoulder: any = harness.server.antiEsp.aim.Stand[KEPT]
	if #harness.rays ~= KEPT then
		return false, `The player pair cast {#harness.rays} rays, not the {KEPT} the settings give`
	elseif harness:endingAt(vector.create(shoulder.side, shoulder.up, -50)) ~= 1 then
		return false, `The second ray ended at {harness.rays[KEPT].to}, not at the left shoulder`
	end

	-- Before the player pair's 30 Hz recheck inside the near radius, so the sleeper's new pair is the only one due
	Harness.AntiEsp.isHidden(viewer, target)
	Harness.AntiEsp.isHidden(viewer, sleeper)
	harness:slice(0.02)

	-- Facing 0 lies along -Z, so the head is half the box's length that way
	local box: any = harness.shared.step.lyingBox
	local head: vector = vector.create(40, box.lift, -box.length / 2)
	if #harness.rays ~= 1 or harness:endingAt(head) ~= 1 then
		return false, `The sleeper cast {#harness.rays} rays, not the one to its head at {head}`
	end

	return true, nil
end
