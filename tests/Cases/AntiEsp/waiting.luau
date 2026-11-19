--[[
    Pairs a slice had no time for wait for the next one: each is tested
    once there, a move while it waits included, and one the relay stopped
    asking about while it waited is dropped untested and starts afresh
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local AntiEsp: any = Harness.AntiEsp
	harness.wall = Harness.solid

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local top: number = harness.server.antiEsp.aim.Stand[1].up -- The head's top, a standing target's first point
	local rays: number = #harness.server.antiEsp.aim.Stand
	local targets: { number } = {}
	local heads: { vector } = {}

	for index: number, z: number in { -20, -30, -40 } do
		targets[index] = harness:body("Player", vector.create(0, 0, z))
		heads[index] = vector.create(0, top, z)
	end

	local function ask(...: number)
		for _, index: number in { ... } do
			AntiEsp.isHidden(viewer, targets[index])
		end
	end

	-- 1) Made and left waiting by a slice with no time, the third moved while it waits
	ask(1, 2, 3)
	harness:slice(0, 0)
	ask(1, 2, 3)
	AntiEsp.moved(targets[3])
	harness:slice(0.01)

	if #harness.rays ~= 3 * rays then
		return false, `The three waiting pairs cast {#harness.rays} rays, not {rays} each`
	end

	for index: number, head: vector in heads do
		if harness:endingAt(head) ~= 1 then
			return false, `Waiting pair {index} was tested {harness:endingAt(head)} times, not once`
		end
	end

	-- 2) Due and left waiting again, then the relay's next run leaves the second out
	ask(1, 2, 3)
	harness:slice(0.12, 0)
	ask(1, 3)
	harness:slice(0.13)

	if #harness.rays ~= 2 * rays or harness:endingAt(heads[2]) ~= 0 then
		return false, `With the second pair left out, the slice cast {#harness.rays} rays, the second's among them`
	end

	-- 3) Asked about again, the second starts afresh, due at once, while the others wait for their recheck
	ask(1, 2, 3)
	harness:slice(0.14)

	if #harness.rays ~= rays or harness:endingAt(heads[2]) ~= 1 then
		return false, `The second pair asked about again cast {#harness.rays} rays, not its own {rays} at once`
	end

	return true, nil
end
