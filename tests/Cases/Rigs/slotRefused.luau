--[[
    A checkout refuses a value that is no slot, from 0 to 4,095 and whole,
    and a look that is no table, before any hook runs
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

	local refused: { any } = { -1, 4096, 1.5, "1", math.huge }
	for _, slot: any in refused do
		local took: boolean = pcall(rigs.checkout, rigs, slot, {})
		if took then
			return false, `checkout took {slot} as a slot`
		end
	end

	local tookNil: boolean = pcall(rigs.checkout, rigs, nil, {})
	if tookNil then
		return false, "checkout took nil as a slot"
	end

	local tookLook: boolean = pcall(rigs.checkout, rigs, 0, "outfit")
	if tookLook then
		return false, "checkout took a string as the slot's look"
	elseif #calls ~= 0 then
		return false, `The refused checkouts made {#calls} hook calls`
	end

	local edges: { number } = { 0, 4095 }
	for _, slot: number in edges do
		local took: boolean, problem: any = pcall(rigs.checkout, rigs, slot, {})
		if not took then
			return false, `checkout refused slot {slot}: {problem}`
		end
	end

	rigs:destroy()

	return true, nil
end
