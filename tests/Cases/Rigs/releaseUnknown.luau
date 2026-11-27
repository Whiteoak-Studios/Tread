--[[
    A release refuses a slot that has no rig checked out, never checked out
    or already given back, and calls no hook for it
--]]

--!strict
local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"

return function (): (boolean, string | nil)
	local Rigs = Environment.load(RIGS)
	local Rig = Environment.load(RIG)

	local calls: { any } = {}
	local rigs = Rigs.new(Rig.settings(calls), Rig.drawDistance, Rig.collision())

	local never: boolean, problem: any = pcall(rigs.release, rigs, 3)
	if never then
		return false, "A release of slot 3, never checked out, was taken"
	elseif not tostring(problem):find("with a rig checked out", 1, true) then
		return false, `A release of an unknown slot failed with the wrong reason: {problem}`
	end

	rigs:checkout(3, {})
	rigs:release(3)
	table.clear(calls)

	local again: boolean = pcall(rigs.release, rigs, 3)
	if again then
		return false, "A second release of slot 3 was taken"
	elseif #calls ~= 0 then
		return false, `The refused release made {#calls} hook calls`
	end

	rigs:destroy()

	return true, nil
end
