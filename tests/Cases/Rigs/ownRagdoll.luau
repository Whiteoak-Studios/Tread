--[[
    The local player's own rig ragdolling shows it again on this screen as
    the body others see, and gives its first-person copy back to the pool,
    so the next own rig takes a copy afresh
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out implementMethod

local Environment = require("../../Environment")
local Owner = require("../../Fixtures/Rigs/Owner")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local OWN: number = 9
local BODY: number = 21
local NEXT: number = 14
local SHOWN: number = 0

return function (): (boolean, string | nil)
	-- Lune's Workspace has no collision groups, which a ragdoll sets up the first time
	roblox.implementMethod("Workspace", "IsCollisionGroupRegistered", function (_: any, _: string): boolean
		return true
	end)
	roblox.implementMethod(
		"Workspace",
		"CollisionGroupSetCollidable",
		function (_: any, _: string, _: string, _: boolean) end
	)

	local Rigs = Environment.load(RIGS)
	local Rig = Environment.load(RIG)

	local calls: { any } = {}
	local rigs = Rigs.new(Rig.settings(calls), Rig.drawDistance, Rig.collision())

	local world: any = rigs:checkout(OWN, {}, true)
	local copy: any = calls[2].rig
	rigs:show("arms", false)

	table.clear(calls)
	rigs:ragdoll(OWN, BODY, nil)

	local shown: string? = Owner.all(world, SHOWN)
	if shown then
		return false, `The ragdolled own rig stayed hidden on this screen: {shown}`
	elseif #calls ~= 1 or calls[1].hook ~= "undress" or calls[1].rig ~= copy then
		return false, `The own rig's death made {#calls} hook calls, not the copy's undress`
	elseif Owner.all(copy, SHOWN) ~= nil then
		return false, "The copy went back to the pool hidden"
	end

	-- The body is drawn for its own slot, and the copy waits in the pool for the next own rig
	table.clear(calls)
	local fresh: any = rigs:checkout(NEXT, {}, true)
	if fresh ~= copy then
		return false, "The next own world rig wasn't the pooled copy"
	elseif #calls ~= 2 or calls[2].copy ~= true or calls[2].rig == world then
		return false, "The next own rig took no fresh copy of its own"
	end

	rigs:release(BODY)
	rigs:destroy()

	return true, nil
end
