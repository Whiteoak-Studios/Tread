--[[
    An NPC is never hidden from any viewer and never ray-tested, behind
    walls or not, and adds nothing to the counts
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local SLICES: number = 10

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	harness.wall = Harness.solid

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local npc: number = harness:body("Npc", vector.create(0, 0, -50))

	for index: number = 1, SLICES do
		if Harness.AntiEsp.isHidden(viewer, npc) then
			return false, `The NPC was hidden on ask {index}`
		end

		harness:slice(index)

		if #harness.rays ~= 0 then
			return false, `The NPC was ray-tested on slice {index}`
		end
	end

	local tests: number, hidden: number, failOpens: number = Harness.AntiEsp.counts()
	if tests + hidden + failOpens ~= 0 then
		return false, `The NPC added to the counts: {tests} tests, {hidden} hidden, {failOpens} fail-opens`
	end

	return true, nil
end
