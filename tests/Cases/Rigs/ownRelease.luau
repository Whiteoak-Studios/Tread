--[[
    Releasing the local player's own slot gives its first-person copy back
    to the pool with it, its held item cleared and undressed, both rigs
    shown again, and the next own rig keeps the settings the game made
--]]

--!strict
local Environment = require("../../Environment")
local Owner = require("../../Fixtures/Rigs/Owner")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local OWN: number = 9
local NEXT: number = 14
local OTHER: number = 3
local HIDDEN: number = 1
local SHOWN: number = 0

return function (): (boolean, string | nil)
	local Rigs = Environment.load(RIGS)
	local Rig = Environment.load(RIG)

	local calls: { any } = {}
	local rigs = Rigs.new(Rig.settings(calls), Rig.drawDistance, Rig.collision())

	local world: any = rigs:checkout(OWN, {}, true)
	local copy: any = calls[2].rig
	rigs:hold(OWN, { item = 7 })
	rigs:show("arms", false)
	rigs:show("rig", true)

	table.clear(calls)
	rigs:release(OWN)

	local cleared: { [Model]: { string } } = {}
	for _, call: any in calls do
		cleared[call.rig] = cleared[call.rig] or {}
		table.insert(cleared[call.rig], call.hook)
	end

	local copyHooks: string = table.concat(cleared[copy] or {}, ", ")
	local worldHooks: string = table.concat(cleared[world] or {}, ", ")
	if copyHooks ~= "hold, undress" then
		return false, `The release gave the copy {copyHooks}, not its hands cleared and then undressed`
	elseif worldHooks ~= "hold, undress" then
		return false, `The release gave the world rig {worldHooks}, not its hands cleared and then undressed`
	end

	local worldShown: string? = Owner.all(world, SHOWN)
	local copyShown: string? = Owner.all(copy, SHOWN)
	if worldShown or copyShown then
		return false, `A released rig went back to the pool hidden: {worldShown or copyShown}`
	end

	-- Both are back in the pool, and the copy is posed no more
	local posed: boolean = pcall(rigs.pose, rigs, OWN, Environment.load("src/Step/State.luau").new(), 0, 0)
	if posed then
		return false, "The released slot was still posed"
	end

	table.clear(calls)
	local first: any = rigs:checkout(OTHER, {})
	local second: any = rigs:checkout(NEXT, {}, true)
	local newCopy: any = calls[#calls].rig
	local pooled: { [any]: boolean } = { [world] = true, [copy] = true }

	if not pooled[first] or not pooled[second] or first == second then
		return false, "The next two checkouts built new rigs instead of taking the two pooled ones"
	elseif calls[#calls].copy ~= true or newCopy == second then
		return false, "The next own checkout took no copy"
	end

	-- The settings the game made hold for the next body: its world rig shown and its copy's arms hidden
	local seen: string? = Owner.all(second, SHOWN)
	local arms: string? = Owner.differs(newCopy, Owner.arms, HIDDEN)
	local head: string? = Owner.differs(newCopy, Owner.head, HIDDEN)
	local body: string? = Owner.differs(newCopy, Owner.body, SHOWN)
	if seen or arms or head or body then
		return false, `The next own rigs lost the settings: {seen or arms or head or body}`
	end

	rigs:destroy()

	return true, nil
end
