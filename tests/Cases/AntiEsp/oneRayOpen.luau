--[[
    One open ray keeps an enemy pair visible, whichever of the five it is,
    and the test casts no ray past the first one it finds open
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local RAYS: number = 5

return function (): (boolean, string | nil)
	for open: number = 1, RAYS do
		local Harness: any = Environment.load(HARNESS)
		local harness: any = Harness.new()

		local cast: number = 0
		harness.wall = function (_: vector, _: vector): boolean
			cast += 1

			return cast ~= open
		end

		local _, viewer: any = harness:player("Viewer", vector.zero)
		local target: number = harness:body("Player", vector.create(0, 0, -50))

		Harness.AntiEsp.isHidden(viewer, target)
		harness:slice(0)

		if Harness.AntiEsp.isHidden(viewer, target) then
			return false, `The pair stayed hidden with ray {open} open`
		elseif #harness.rays ~= open then
			return false, `With ray {open} open the test cast {#harness.rays} rays`
		end
	end

	return true, nil
end
