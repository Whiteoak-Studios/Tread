--[[
    A dying rig laid down keeps its rig with no ragdoll, re-keyed to its
    body's slot: its tracks stop at once, its next pose draws it as any
    other rig, and it goes back to the pool on release. The local player's
    own rig shows again as a body and gives its copy back. It refuses a
    ragdoll, a body slot that has a rig, and a slot with none
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out implementProperty and implementMethod

local Environment = require("../../Environment")
local Owner = require("../../Fixtures/Rigs/Owner")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local DYING: number = 3
local BODY: number = 20
local OTHER: number = 4
local OTHER_BODY: number = 30
local OWN: number = 9
local OWN_BODY: number = 40
local NEXT: number = 50
local DISTANCE: number = 4 -- Studs from the eye to each rig's feet
local SHOWN: number = 0

return function (): (boolean, string | nil)
	-- Lune's RunService has no PreSimulation and its Workspace no BulkMoveTo, which a drawn rig needs. Lune takes one
	-- registration of each a run, so a case that ran first may have made it, as these do; with no collision groups a
	-- ragdoll warns and carries on
	pcall(roblox.implementProperty, "RunService", "PreSimulation", function (_: any): any
		return {
			Connect = function (_: any, _: () -> ()): any
				return { Disconnect = function (_: any) end }
			end,
		}
	end)
	pcall(roblox.implementMethod, "Workspace", "BulkMoveTo", function (_: any, parts: { any }, cframes: { any }, _: any)
		for index: number, part: any in parts do
			part.CFrame = cframes[index]
		end
	end)

	-- Lune loads no animation, so a stand-in for Animate writes down each rig's stops
	local stops: { [any]: number } = {}
	local function nothing(...: any) end
	local Animate: { [string]: any } = {
		check = nothing,
		places = function (_: any, _: any): { any }
			return {}
		end,
		load = function (rig: Model, ...: any): any
			return { rig = rig, tracks = {} }
		end,
		stop = function (animated: any)
			stops[animated.rig] = (stops[animated.rig] or 0) + 1
		end,
		detail = nothing,
		pose = nothing,
		aim = nothing,
		plant = nothing,
		layer = nothing,
		watch = nothing,
		release = nothing,
		markers = function (_: any): { string }
			return {}
		end,
	}

	local Rigs = Environment.load(RIGS, { [ANIMATE] = Animate })
	local Rig = Environment.load(RIG)
	local State = Environment.load(STATE)

	local calls: { any } = {}
	local rigs = Rigs.new(Rig.settings(calls), Rig.drawDistance, Rig.collision())

	local state = State.new()
	state.mode = "Ground"
	state.position = vector.create(10, 0, -5)

	local rig: any = rigs:checkout(DYING, {})
	rigs:pose(DYING, state, DISTANCE, 0)

	-- 1) Laid down, the rig is the body's, its tracks stopped, never a ragdoll and still dressed
	table.clear(calls)
	rigs:lie(DYING, BODY)

	if stops[rig] ~= 1 then
		return false, `Laying the rig down stopped its tracks {stops[rig]} times, not once`
	elseif pcall(rigs.pose, rigs, DYING, state, DISTANCE, 0) then
		return false, "The dying slot still had a rig after its rig was laid down"
	elseif rig:FindFirstChildWhichIsA("BallSocketConstraint", true) then
		return false, "The rig laid down was ragdolled"
	elseif #calls ~= 0 then
		return false, `Laying the rig down made {#calls} hook calls, though it keeps its look`
	end

	-- 2) The body's slot poses it as any other rig, where its state lies
	state.posture = "Downed"
	state.position = vector.create(12, 0, -5)
	rigs:pose(BODY, state, DISTANCE, 0)
	if rig.Parent == nil or rig.PrimaryPart.CFrame.Position.X ~= state.position.x then
		return false, `The body's pose left its rig at {rig.PrimaryPart.CFrame.Position}`
	end

	-- 3) What it refuses: a ragdoll, a body slot that has a rig, and a slot with none
	rigs:checkout(OTHER, {})
	rigs:ragdoll(OTHER, OTHER_BODY, nil)
	if pcall(rigs.lie, rigs, OTHER_BODY, OTHER_BODY + 1) then
		return false, "A ragdoll was laid down"
	end

	rigs:checkout(OTHER, {})
	if pcall(rigs.lie, rigs, OTHER, BODY) then
		return false, `Slot {OTHER}'s rig was laid down into slot {BODY}, which has a rig`
	elseif pcall(rigs.lie, rigs, NEXT, NEXT + 1) then
		return false, `Slot {NEXT}, which has no rig, was laid down`
	end

	-- 4) The local player's own rig shows again as a body, and its copy goes back to the pool undressed
	local world: any = rigs:checkout(OWN, {}, true)
	local copy: any = calls[#calls].rig
	table.clear(calls)
	rigs:lie(OWN, OWN_BODY)

	local hidden: string? = Owner.all(world, SHOWN)
	if hidden then
		return false, `The own rig laid down stayed hidden on this screen: {hidden}`
	elseif #calls ~= 1 or calls[1].hook ~= "undress" or calls[1].rig ~= copy then
		return false, `Laying the own rig down made {#calls} hook calls, not the copy's undress`
	end

	-- 5) Released, a body laid down goes back to the pool, unlike a ragdoll
	rigs:release(BODY)
	if rigs:checkout(NEXT, {}) ~= rig then
		return false, "A released body that was laid down didn't go back to the pool"
	end

	rigs:destroy()

	return true, nil
end
