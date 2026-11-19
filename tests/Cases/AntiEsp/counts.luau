--[[
    AntiEsp.counts gives the tests run, the tests that left their pair
    hidden, a held one not among them, and the fail-opens, each since start
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local FAR: number = 50 -- The setup wall blocks rays reaching this far along X

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local AntiEsp: any = Harness.AntiEsp

	local tests: number, hidden: number, failOpens: number = AntiEsp.counts()
	if tests + hidden + failOpens ~= 0 then
		return false, "The counts didn't start at 0"
	end

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local seen: number = harness:body("Player", vector.create(0, 0, -50))
	local blocked: number = harness:body("Player", vector.create(100, 0, 0))
	local starved: number = harness:body("Player", vector.create(-100, 0, 0))

	-- The first two are tested: one seen, one behind the wall past FAR along X
	harness.wall = function (_: vector, direction: vector): boolean
		return direction.x > FAR
	end

	AntiEsp.isHidden(viewer, seen)
	AntiEsp.isHidden(viewer, blocked)
	harness:slice(0)

	-- Walls everywhere: the seen one is held, the other hidden again
	harness.wall = Harness.solid
	AntiEsp.isHidden(viewer, seen)
	AntiEsp.isHidden(viewer, blocked)
	harness:slice(0.5)

	-- The third, made now, fails open untested
	AntiEsp.isHidden(viewer, seen)
	AntiEsp.isHidden(viewer, blocked)
	AntiEsp.isHidden(viewer, starved)
	harness:slice(0.7, 0)
	AntiEsp.isHidden(viewer, starved)

	tests, hidden, failOpens = AntiEsp.counts()
	if tests ~= 4 or hidden ~= 2 or failOpens ~= 1 then
		return false, `The counts were {tests} tests, {hidden} hidden and {failOpens} fail-opens, not 4, 2 and 1`
	end

	return true, nil
end
