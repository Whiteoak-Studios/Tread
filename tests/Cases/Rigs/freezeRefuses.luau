--[[
    Rigs.freeze refuses, changing nothing, a rig out of Workspace, the
    local player's own, the spectated target's, an outlined one, a ragdoll
    and a dying one, errors on a slot with no rig, and freezes a drawn rig
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes, implementProperty and implementMethod

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local UNDRAWN: number = 1 -- Checked out and never posed
local FAR_SLOT: number = 2 -- Posed past the draw distance
local OWN: number = 3
local WATCHED: number = 4
local OUTLINED: number = 5
local RAGDOLL: number = 6 -- Dies first, so the frame's end starts its ragdoll
local DYING: number = 7 -- Dies after it, so its ragdoll still waits
local DRAWN: number = 8 -- A drawn rig none of these holds for
local EMPTY: number = 9
local BODY: number = 10 -- A slot's body is this many slots on
local NEAR: number = 4 -- Studs from the eye
local FAR: number = 5000 -- Past the draw distance
local CAP: number = 1 -- Ragdolls started a frame

-- One rig the pool must refuse: the slot it is keyed to now, the slot it was checked out for, and what it is
type Refusal = { slot: number, checked: number, name: string }

return function (): (boolean, string | nil)
	-- Lune's RunService has no PreSimulation and its Workspace no BulkMoveTo, which a drawn rig needs. Lune takes one
	-- registration of each a run, so a case that ran first may have made it; with no collision groups a ragdoll warns
	-- and carries on
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

	-- Lune loads no animation, so a stand-in for Animate counts the speeds each rig's tracks are set
	local speeds: { [any]: number } = {}
	local function nothing(_: any) end
	local Animate: { [string]: any } = {
		check = nothing,
		places = function (_: any, _: any): { any }
			return {}
		end,
		load = function (rig: Model, _: any): any
			return { rig = rig, tracks = {} }
		end,
		speed = function (animated: any, _: number)
			speeds[animated.rig] = (speeds[animated.rig] or 0) + 1
		end,
		stop = nothing,
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

	local settings: any = Rig.settings({})
	settings.perFrame = { ragdolls = CAP }
	settings.spectate = {
		outline = {
			fill = roblox.Color3.fromRGB(255, 60, 60),
			fillTransparency = 0.75,
			outline = roblox.Color3.fromRGB(255, 255, 255),
			outlineTransparency = 0.1,
		},
	}
	local rigs: any = Rigs.new(settings, Rig.drawDistance, Rig.collision())

	local state = State.new()
	state.mode = "Ground"

	-- Every rig but the two out of Workspace is drawn, so each is refused for its own reason alone
	local models: { [number]: any } = {}
	for _, slot: number in { UNDRAWN, FAR_SLOT, OWN, WATCHED, OUTLINED, RAGDOLL, DYING, DRAWN } do
		models[slot] = rigs:checkout(slot, {}, slot == OWN)

		if slot == FAR_SLOT then
			rigs:pose(slot, state, FAR, 0)
		elseif slot ~= UNDRAWN then
			rigs:pose(slot, state, NEAR, 0)
		end
	end
	rigs:frame()

	rigs:watch(WATCHED)
	rigs:outline(OUTLINED, true)

	-- The first death's ragdoll starts at the frame's end, and the second waits past the cap
	rigs:ragdoll(RAGDOLL, RAGDOLL + BODY, nil)
	rigs:frame()
	rigs:ragdoll(DYING, DYING + BODY, nil)

	if not models[RAGDOLL]:FindFirstChildWhichIsA("BallSocketConstraint", true) then
		return false, "The first death's ragdoll never started, so no ragdoll is tested"
	elseif models[DYING]:FindFirstChildWhichIsA("BallSocketConstraint", true) then
		return false, "The second death's ragdoll started past the cap, so no dying rig is tested"
	end

	local refused: { Refusal } = {
		{ slot = UNDRAWN, checked = UNDRAWN, name = "a rig no pose has drawn" },
		{ slot = FAR_SLOT, checked = FAR_SLOT, name = "a rig past the draw distance" },
		{ slot = OWN, checked = OWN, name = "the local player's own rig" },
		{ slot = WATCHED, checked = WATCHED, name = "the spectated target's rig" },
		{ slot = OUTLINED, checked = OUTLINED, name = "an outlined rig" },
		{ slot = RAGDOLL + BODY, checked = RAGDOLL, name = "a ragdoll" },
		{ slot = DYING + BODY, checked = DYING, name = "a dying rig" },
	}

	for _, refusal: Refusal in refused do
		local model: any = models[refusal.checked]
		local before: number = speeds[model] or 0
		local parent: any = model.Parent

		if rigs:freeze(refusal.slot) ~= false then
			return false, `Rigs.freeze froze {refusal.name}`
		elseif rigs._slots[refusal.slot].frozen or #rigs._frozen ~= 0 then
			return false, `Rigs.freeze refused {refusal.name} and marked it frozen all the same`
		elseif (speeds[model] or 0) ~= before or model.Parent ~= parent then
			return false, `Rigs.freeze refused {refusal.name} and changed its tracks' speed or its place all the same`
		end
	end

	if pcall(rigs.freeze, rigs, EMPTY) then
		return false, "Rigs.freeze took a slot with no rig"
	end

	-- The same pool freezes a drawn rig that none of those holds for
	if rigs:freeze(DRAWN) ~= true or #rigs._frozen ~= 1 or speeds[models[DRAWN]] ~= 1 then
		return false, "Rigs.freeze refused a drawn rig, or froze it without holding its tracks"
	end

	rigs:destroy()

	return true, nil
end
