--[[
    Destroying the pool destroys every rig it built, checked out or pooled,
    and calls no hook
--]]

--!strict
local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"

-- Lune refuses every call on a destroyed instance, where the engine hands back no children
local function destroyed(instance: any): boolean
	local read: boolean, children: any = pcall(instance.GetChildren, instance)
	return not read or #children == 0
end

return function (): (boolean, string | nil)
	local Rigs = Environment.load(RIGS)
	local Rig = Environment.load(RIG)

	local calls: { any } = {}
	local rigs = Rigs.new(Rig.settings(calls), Rig.drawDistance, Rig.collision())

	local drawn: any = rigs:checkout(0, {})
	local pooled: any = rigs:checkout(1, {})
	rigs:release(1)
	table.clear(calls)

	rigs:destroy()

	if not destroyed(drawn) or not destroyed(pooled) then
		return false, "A rig the pool built kept its parts after the pool was destroyed"
	elseif #calls ~= 0 then
		return false, `Destroying the pool made {#calls} hook calls`
	end

	return true, nil
end
