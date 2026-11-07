--[[
    The pool's show refuses a part none of the four and a shown flag that is
    no boolean, naming them, and takes each part both ways with no rig out
--]]

--!strict
local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"

return function (): (boolean, string | nil)
	local Rigs = Environment.load(RIGS)
	local Rig = Environment.load(RIG)

	local rigs = Rigs.new(Rig.settings({}), Rig.drawDistance, Rig.collision())

	local part: boolean, partProblem: any = pcall(rigs.show, rigs, "head", false)
	if part then
		return false, "show took head as a part"
	elseif not tostring(partProblem):find("not head", 1, true) then
		return false, `show refused head with the wrong reason: {partProblem}`
	end

	local flag: boolean, flagProblem: any = pcall(rigs.show, rigs, "arms", "no")
	if flag then
		return false, "show took a string as shown"
	elseif not tostring(flagProblem):find("boolean", 1, true) then
		return false, `show refused a string as shown with the wrong reason: {flagProblem}`
	end

	local parts: { string } = { "arms", "chest", "copy", "rig" }
	for _, name: string in parts do
		for _, shown: boolean in { false, true } do
			local took: boolean, problem: any = pcall(rigs.show, rigs, name, shown)
			if not took then
				return false, `show("{name}", {shown}) with no rig out threw: {problem}`
			end
		end
	end

	rigs:destroy()

	return true, nil
end
