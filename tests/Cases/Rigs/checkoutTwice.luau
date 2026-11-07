--[[
    A slot already holding a rig refuses a second checkout, calls no hook
    for it, and keeps the rig it had
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

	local rig: any = rigs:checkout(7, {})
	table.clear(calls)

	local took: boolean, problem: any = pcall(rigs.checkout, rigs, 7, {})
	if took then
		return false, "A second checkout of slot 7 was taken"
	elseif not tostring(problem):find("already has a rig", 1, true) then
		return false, `A second checkout failed with the wrong reason: {problem}`
	elseif #calls ~= 0 then
		return false, `The refused checkout made {#calls} hook calls`
	end

	rigs:release(7)
	if #calls ~= 1 or calls[1].rig ~= rig then
		return false, "Slot 7 lost its first rig to the refused checkout"
	end

	rigs:destroy()

	return true, nil
end
