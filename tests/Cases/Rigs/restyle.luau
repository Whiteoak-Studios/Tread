--[[
    A new look undresses a slot's rig and dresses it again, a held item goes
    to the hold hook as given, nil clearing it, and both refuse a slot with
    no rig checked out
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

	local rig: any = rigs:checkout(4, { shirt = 1 })
	table.clear(calls)

	local outfit: { [string]: any } = { shirt = 2 }
	rigs:dress(4, outfit)

	if #calls ~= 2 or calls[1].hook ~= "undress" or calls[1].rig ~= rig then
		return false, "A new look did not undress the rig first"
	elseif calls[2].hook ~= "dress" or calls[2].rig ~= rig or calls[2].outfit ~= outfit or calls[2].copy ~= false then
		return false, "A new look did not dress the rig with it as a world rig"
	end

	table.clear(calls)
	local held: { [string]: any } = { item = 7 }
	rigs:hold(4, held)
	rigs:hold(4, nil)

	if #calls ~= 2 or calls[1].hook ~= "hold" or calls[1].rig ~= rig or calls[1].held ~= held then
		return false, "A held item did not reach hold(rig, held)"
	elseif calls[2].hook ~= "hold" or calls[2].held ~= nil then
		return false, "Clearing the hands did not reach hold(rig, nil)"
	end

	table.clear(calls)
	rigs:release(4)
	if #calls ~= 1 or calls[1].hook ~= "undress" then
		return false, "A rig whose hands were cleared was cleared again at its release"
	end

	local dressed: boolean = pcall(rigs.dress, rigs, 4, outfit)
	local holding: boolean = pcall(rigs.hold, rigs, 4, held)
	if dressed or holding then
		return false, `A slot with no rig took a look {dressed} or a held item {holding}`
	end

	rigs:destroy()

	return true, nil
end
