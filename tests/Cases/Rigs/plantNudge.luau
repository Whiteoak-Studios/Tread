--[[
    A still rig's feet plant from its target and keep their targets on the
    frame its root stands the nudge above that target as on the frames it
    stands on it, with no ray cast for the nudge
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes, implementProperty and implementMethod

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local REAL_ANIMATE: string = "src/Client/Rigs/Animate.luau"
local COLLISION: string = "tests/Fixtures/Step/Collision.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local SLOT: number = 3
local DISTANCE: number = 4 -- Studs from the eye, inside every detail range
local LEGS: number = 2 -- Rays a plant casts, one under each foot
local RISE: number = 1 -- Studs the step stands above the floor, under the left foot alone
local NUDGE: number = 0.001 -- Studs a still rig's root rises on alternate frames, as the pool's constant gives it
local TOLERANCE: number = 1e-4 -- Studs, a tenth of the nudge, since a CFrame holds 32-bit floats

-- A floor whose top is the state's feet, at the origin, and a step under the left foot alone
local FLOOR: { [string]: any } = {
	name = "Floor",
	center = vector.create(0, -0.5, 0),
	size = vector.create(20, 1, 20),
	tilt = 0,
}
local STEP: { [string]: any } = {
	name = "Step",
	center = vector.create(-0.75, RISE / 2, 0),
	size = vector.create(1.5, RISE, 2),
	tilt = 0,
}

-- One plant the pool asked for: the frame it was handed and where the rig's root stood then
type Plant = { frame: any, root: any }

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

	-- Lune loads no animation, so Animate's stand-in plays nothing, but measures and plants the legs as Animate does
	local Real = Environment.load(REAL_ANIMATE)
	local plants: { Plant } = {}
	local function nothing(_: any) end
	local Animate: { [string]: any } = {
		check = nothing,
		places = Real.places,
		load = function (rig: Model, joints: any, _: any, places: any, _: any): any
			return { rig = rig, tracks = {}, planted = false, legs = Real.legs(joints, places) }
		end,
		stop = nothing,
		detail = nothing,
		pose = nothing,
		aim = nothing,
		plant = function (animated: any, frame: any, ...: any)
			table.insert(plants, { frame = frame, root = animated.rig.PrimaryPart.CFrame })
			Real.plant(animated, frame, ...)
		end,
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
	local Collision = Environment.load(COLLISION)

	-- The step's casts over the floor and the step, each ray counted
	local rays: number = 0
	local casts: any = Collision({ FLOOR, STEP })
	local counted: any = table.clone(casts)
	counted.ray = function (origin: vector, direction: vector): any
		rays += 1
		return casts.ray(origin, direction)
	end

	local rigs: any = Rigs.new(Rig.settings({}), Rig.drawDistance, counted)
	local model: any = rigs:checkout(SLOT, {})

	-- Standing still on the floor at the origin, at a facing of 0, so the step lies under the left foot
	local state = State.new()
	state.mode = "Ground"
	state.grounded = true
	state.position = vector.zero

	local height: number = model.PrimaryPart.CFrame.Position.Y
	local target: any = roblox.CFrame.new(0, height, 0)
	local raised: any = target + roblox.Vector3.new(0, NUDGE, 0)

	-- 1) The first frame plants both feet from the target, the left one up the step, and puts the root on the target
	rigs:pose(SLOT, state, DISTANCE, 0)
	rigs:frame()

	local legs: { any } = rigs._slots[SLOT].animated.legs
	local left: any, right: any = legs[1], legs[2]
	local leftTarget: vector = left.target
	local rightTarget: vector = right.target
	local stepped: number = vector.magnitude(leftTarget - (left.place.rest + vector.create(0, RISE, 0)))
	if rays ~= LEGS then
		return false, `The first plant cast {rays} rays, not one under each of {LEGS} feet`
	elseif not left.planted or stepped > TOLERANCE then
		return false, `The left foot planted at {leftTarget}, not {RISE} stud above its rest on the step`
	elseif not right.planted or vector.magnitude(rightTarget - right.place.rest) > TOLERANCE then
		return false, `The right foot planted at {rightTarget}, not its rest on the floor`
	elseif apart(model.PrimaryPart.CFrame, target) > TOLERANCE then
		return false, `The first frame left the root at {model.PrimaryPart.CFrame.Position}, not its target`
	end

	-- 2) Still, the next frame raises the root, and its plant read the target and cast nothing
	-- 3) Still again, the frame after lowers it, its plant read with the root raised, and cast nothing either
	local wanted: { any } = { raised, target }
	local before: { any } = { target, raised }
	for index: number, place: any in wanted do
		local frame: number = index + 1
		rigs:pose(SLOT, state, DISTANCE, 0)
		rigs:frame()

		local plant: Plant = plants[#plants]
		if rays ~= LEGS then
			return false, `Frame {frame}'s plant cast {rays - LEGS} rays for a rig standing still`
		elseif apart(plant.frame, target) > TOLERANCE then
			return false, `Frame {frame}'s plant read {plant.frame.Position}, not the target {target.Position}`
		elseif apart(plant.root, before[index]) > TOLERANCE then
			return false,
				`Frame {frame}'s plant ran with the root at {plant.root.Position}, not {before[index].Position}`
		elseif left.target ~= leftTarget or right.target ~= rightTarget or not left.planted or not right.planted then
			return false, `Frame {frame} moved the feet to {left.target} and {right.target}, from where they planted`
		elseif apart(model.PrimaryPart.CFrame, place) > TOLERANCE then
			return false, `Frame {frame} left the root at {model.PrimaryPart.CFrame.Position}, not {place.Position}`
		end
	end

	rigs:destroy()

	return true, nil
end
