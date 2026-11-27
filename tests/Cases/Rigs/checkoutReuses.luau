--[[
    A rig given back is the one the next checkout takes, for any slot,
    dressed again with that slot's look
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

	local first: any = rigs:checkout(1, {})
	rigs:release(1)
	table.clear(calls)

	local outfit: { [string]: any } = { shirt = 4 }
	local second: any = rigs:checkout(2, outfit)

	if second ~= first then
		return false, "A checkout after a release built a new rig instead of taking the pooled one"
	elseif #calls ~= 1 or calls[1].hook ~= "dress" or calls[1].rig ~= first or calls[1].outfit ~= outfit then
		return false, "The pooled rig was not dressed once with the new slot's look"
	end

	rigs:destroy()

	return true, nil
end
