--[[
    A pose only sets its root's target, and the frame's end moves every
    root posed at once to where its pose put it, the newest of two poses in
    a frame; each plant reads that target before the root has moved
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes, implementProperty and implementMethod

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local SLOTS: { number } = { 3, 4, 5 }
local DISTANCE: number = 4 -- Studs from the eye, inside every detail range
local TOLERANCE: number = 1e-4 -- Studs, since a CFrame holds 32-bit floats

-- Where each slot's state stands and faces, radians, and where the second slot's newer pose of the frame puts it
local PLACES: { { position: vector, facing: number } } = {
	{ position = vector.create(10, 2, -5), facing = 0 },
	{ position = vector.create(-40, 7.5, 120), facing = math.pi / 2 },
	{ position = vector.create(300, -12, 64), facing = 2.3 },
}
local NEWER: { position: vector, facing: number } = { position = vector.create(-38, 7.5, 121), facing = 1 }

-- One plant the pool asked for: the rig, the frame it was handed and where the rig's root stood then
type Plant = { rig: any, frame: any, root: any }

local function apart(a: any, b: any): number
	return (a.Position - b.Position).Magnitude + (a.LookVector - b.LookVector).Magnitude
end

return function (): (boolean, string | nil)
	-- Lune's RunService has no PreSimulation and its Workspace no BulkMoveTo, which a drawn rig needs. Lune takes one
	-- registration of each a run, so a case that ran first may have made it
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

	-- Lune loads no animation, so a stand-in for Animate writes down each plant it is asked for
	local plants: { Plant } = {}
	local Animate: { [string]: any } = {
		check = function (_: any) end,
		places = function (_: any, _: any): { any }
			return {}
		end,
		load = function (rig: Model, _: any, _: any, _: any, _: (string, string) -> ()): any
			return { rig = rig, tracks = {} }
		end,
		stop = function (_: any) end,
		detail = function (_: any, _: boolean) end,
		pose = function (_: any, _: any, _: boolean, _: number?) end,
		aim = function (_: any, _: number, _: number, _: number, _: number, _: number) end,
		plant = function (animated: any, frame: any, _: number, _: number, _: any, _: boolean, _: boolean)
			table.insert(plants, { rig = animated.rig, frame = frame, root = animated.rig.PrimaryPart.CFrame })
		end,
		layer = function (_: any) end,
		watch = function (_: any, _: string, _: { string }) end,
		release = function (_: any) end,
		markers = function (_: any): { string }
			return {}
		end,
	}

	local Rigs = Environment.load(RIGS, { [ANIMATE] = Animate })
	local Rig = Environment.load(RIG)
	local State = Environment.load(STATE)

	local rigs: any = Rigs.new(Rig.settings({}), Rig.drawDistance, Rig.collision())
	local models: { any } = {}
	local before: { any } = {}
	local states: { any } = {}
	for index: number, slot: number in SLOTS do
		local model: any = rigs:checkout(slot, {})
		models[index] = model
		before[index] = model.PrimaryPart.CFrame

		local state = State.new()
		state.mode = "Ground"
		state.position = PLACES[index].position
		state.facing = PLACES[index].facing
		states[index] = state
	end

	-- The root's height above the soles, which stand at 0 on the template every rig is cloned from
	local height: number = before[1].Position.Y

	-- Today's per-rig move: the state's feet raised by the root's height, turned to its facing
	local function target(place: { position: vector, facing: number }): any
		local at: vector = place.position
		return roblox.CFrame.new(at.x, at.y + height, at.z) * roblox.CFrame.Angles(0, place.facing, 0)
	end

	-- 1) The poses leave every root where it stood, and each plant reads the target its root goes to
	for index: number, slot: number in SLOTS do
		rigs:pose(slot, states[index], DISTANCE, 0)
	end

	for index: number, model: any in models do
		local plant: Plant = plants[index]
		if model.PrimaryPart.CFrame ~= before[index] then
			return false, `Slot {SLOTS[index]}'s pose moved its root before the frame's end`
		elseif plant.rig ~= model or apart(plant.frame, target(PLACES[index])) > TOLERANCE then
			return false, `Slot {SLOTS[index]}'s plant read {plant.frame}, not its target {target(PLACES[index])}`
		elseif plant.root ~= before[index] then
			return false, `Slot {SLOTS[index]}'s root had moved by its plant`
		end
	end

	-- 2) A second pose in the frame keeps the newer target, and the frame's move holds each root once
	states[2].position = NEWER.position
	states[2].facing = NEWER.facing
	rigs:pose(SLOTS[2], states[2], DISTANCE, 0)

	if #rigs._queued ~= #SLOTS then
		return false, `The frame's move holds {#rigs._queued} roots, not the {#SLOTS} posed`
	end

	-- 3) The frame's end moves every root to where its pose put it, and leaves nothing waiting
	rigs:frame()

	local wanted: { any } = { target(PLACES[1]), target(NEWER), target(PLACES[3]) }
	for index: number, model: any in models do
		local placed: any = model.PrimaryPart.CFrame
		if apart(placed, wanted[index]) > TOLERANCE then
			return false, `The frame's end put slot {SLOTS[index]}'s root at {placed}, not {wanted[index]}`
		end
	end

	if #rigs._queued ~= 0 then
		return false, `The frame's end left {#rigs._queued} roots waiting to move`
	end

	-- 4) A rig posed where it already stands joins the frame's move alone, and its plant still reads where its root
	-- stands
	table.clear(plants)
	rigs:pose(SLOTS[1], states[1], DISTANCE, 0)
	if #rigs._queued ~= 1 or rigs._queued[1].rig ~= models[1] then
		return false,
			`A rig posed where it stood left the frame's move holding {#rigs._queued} roots, not its own alone`
	elseif apart(plants[1].frame, models[1].PrimaryPart.CFrame) > TOLERANCE then
		return false, `A rig posed where it stood planted from {plants[1].frame}, not where its root stands`
	end

	rigs:frame()
	rigs:destroy()

	return true, nil
end
