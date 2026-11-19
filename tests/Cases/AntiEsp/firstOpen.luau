--[[
    The rays go in their list's order and stop at the first open one: with
    only the left lower leg's open, the five up to it in the example's
    order, and the two up to it with the list reversed
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local TOLERANCE: number = 1e-6 -- Studs a ray's end may sit from where it should
local LEG: number = 5 -- The example's left lower leg among the standing points

return function (): (boolean, string | nil)
	for _, reversed: boolean in { false, true } do
		local Harness: any = Environment.load(HARNESS)
		local harness: any = Harness.new(function (_: any, server: any)
			local points: { any } = server.antiEsp.aim.Stand
			if reversed then
				local count: number = #points
				for index: number = 1, count // 2 do
					points[index], points[count + 1 - index] = points[count + 1 - index], points[index]
				end
			end
		end)

		-- A line along -Z, so the viewer's right is +X, and every ray blocked but the one to the left lower leg
		local feet: vector = vector.create(0, 0, -40)
		local points: { any } = harness.server.antiEsp.aim.Stand
		local open: number = reversed and #points + 1 - LEG or LEG
		local order: string = reversed and "reversed" or "example's"
		local leg: vector = feet + vector.create(points[open].side, points[open].up, 0)
		harness.wall = function (origin: vector, direction: vector): boolean
			return vector.magnitude(origin + direction - leg) > TOLERANCE
		end

		local _, viewer: any = harness:player("Viewer", vector.zero)
		local target: number = harness:body("Player", feet)
		Harness.AntiEsp.isHidden(viewer, target)
		harness:slice(0)

		if Harness.AntiEsp.isHidden(viewer, target) then
			return false, `With the left lower leg's ray open in the {order} list, the pair was hidden`
		elseif #harness.rays ~= open then
			return false, `The {order} list cast {#harness.rays} rays, not the {open} up to the open one`
		end

		for index: number = 1, open do
			local point: any = points[index]
			local finish: vector = feet + vector.create(point.side, point.up, 0)
			if vector.magnitude(harness.rays[index].to - finish) > TOLERANCE then
				return false, `The {order} list's ray {index} ended at {harness.rays[index].to}, not {finish}`
			end
		end
	end

	return true, nil
end
