--[[
    A release clears a held item, then undresses the rig and takes it out of
    Workspace, and a rig holding nothing is only undressed
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

	local holding: any = rigs:checkout(5, {})
	local held: { [string]: any } = { item = 2 }
	rigs:hold(5, held)
	table.clear(calls)

	rigs:release(5)

	if #calls ~= 2 then
		return false, `Releasing a rig that holds an item made {#calls} hook calls, not hold(rig, nil) then undress`
	end

	local cleared: any, undressed: any = calls[1], calls[2]
	if cleared.hook ~= "hold" or cleared.rig ~= holding or cleared.held ~= nil then
		return false, `The release's first call was {cleared.hook} with held {cleared.held}, not hold(rig, nil)`
	elseif undressed.hook ~= "undress" or undressed.rig ~= holding then
		return false, `The release's second call was {undressed.hook}, not undress on its rig`
	elseif holding.Parent ~= nil then
		return false, `A released rig sits in {holding.Parent:GetFullName()}`
	end

	local bare: any = rigs:checkout(6, {})
	table.clear(calls)
	rigs:release(6)

	if #calls ~= 1 or calls[1].hook ~= "undress" or calls[1].rig ~= bare then
		return false, `Releasing a rig that holds nothing made {#calls} calls, not one undress on its rig`
	end

	rigs:destroy()

	return true, nil
end
