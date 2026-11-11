--[[
    Anti-ESP reads no antiEsp.rays: started with a leftover one at 1, which
    the server's check refuses, a player pair's test still casts every ray
    its posture's list gives
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.rays = 1
	end)
	harness.wall = Harness.solid

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", vector.create(0, 0, -50))

	Harness.AntiEsp.isHidden(viewer, target)
	harness:slice(0)

	local rays: number = #harness.server.antiEsp.aim.Stand
	if #harness.rays ~= rays then
		return false, `With a leftover antiEsp.rays of 1 the test cast {#harness.rays} rays, not Stand's {rays}`
	end

	return true, nil
end
