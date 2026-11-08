--[[
    A viewer with no body of its own casts every ray from where the relay
    measures it from, unmoved by any velocity, and has no teammates
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local TEAM: number = 1

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	harness.wall = Harness.solid

	local viewer: any = harness:viewer("Spirit")
	viewer.position = vector.create(5, 3, 7)

	local target: number = harness:body("Player", vector.create(0, 0, -50))
	Harness.AntiEsp.setTeam(target, TEAM)

	if not Harness.AntiEsp.isHidden(viewer, target) then
		return false, "A viewer with no body counted a target with a team as its teammate"
	end

	harness:slice(0)

	if #harness.rays ~= 5 then
		return false, `The bodiless viewer's test cast {#harness.rays} rays, not 5`
	end

	for index: number, ray: any in harness.rays do
		if ray.origin ~= viewer.position then
			return false, `Ray {index} started at {ray.origin}, not the viewer's place {viewer.position}`
		end
	end

	return true, nil
end
