--[[
    A standing rig the nudge raised that is next posed lying down in the
    same place comes down onto its target in that frame's move, and joins
    no frame's move after while it lies still
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes, implementProperty and implementMethod

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local SLOT: number = 5
local DISTANCE: number = 4 -- Studs from the eye, inside every detail range
local PLACE: vector = vector.create(300, -12, 64)
local FACING: number = 2.3 -- Radians, along neither axis
local NUDGE: number = 0.001 -- Studs a still rig's root rises on alternate frames, as the pool's constant gives it
local TOLERANCE: number = 1e-4 -- Studs, a tenth of the nudge, since a CFrame holds 32-bit floats

-- One frame's posture, whether the frame's move holds the rig's root, and whether it stands raised after
type Step = { posture: string, joins: boolean, raised: boolean }

-- Standing still until raised, then lying down in place
local STEPS: { Step } = {
	{ posture = "Stand", joins = true, raised = false },
	{ posture = "Stand", joins = true, raised = true },
	{ posture = "Downed", joins = true, raised = false },
	{ posture = "Downed", joins = false, raised = false },
	{ posture = "Downed", joins = false, raised = false },
}

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

	-- Lune loads no animation, so Animate's stand-in plays nothing
	local function nothing(_: any) end
	local Animate: { [string]: any } = {
		check = nothing,
		places = function (_: any, _: any): { any }
			return {}
		end,
		load = function (rig: Model, _: any): any
			return { rig = rig, tracks = {} }
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

	local rigs: any = Rigs.new(Rig.settings({}), Rig.drawDistance, Rig.collision())
	local model: any = rigs:checkout(SLOT, {})

	local state = State.new()
	state.mode = "Ground"
	state.position = PLACE
	state.facing = FACING

	-- The state's feet raised by the root's height above the soles, which stand at 0 on the template, turned to its
	-- facing
	local height: number = model.PrimaryPart.CFrame.Position.Y
	local target: any = roblox.CFrame.new(PLACE.x, PLACE.y + height, PLACE.z) * roblox.CFrame.Angles(0, FACING, 0)
	local raised: any = target + roblox.Vector3.new(0, NUDGE, 0)

	for frame: number, step: Step in STEPS do
		state.posture = step.posture
		rigs:pose(SLOT, state, DISTANCE, 0)

		local held: number = #rigs._queued
		if step.joins and held ~= 1 then
			return false, `Frame {frame}, {step.posture}, left the rig out of its move`
		elseif not step.joins and held ~= 0 then
			return false, `Frame {frame}'s move held {held} roots, though the only rig lay still on its target`
		end

		rigs:frame()

		local wanted: any = target
		if step.raised then
			wanted = raised
		end

		local stands: any = model.PrimaryPart.CFrame
		if apart(stands, wanted) > TOLERANCE then
			return false,
				`After frame {frame}, {step.posture}, the root stood at {stands.Position}, not {wanted.Position}`
		end
	end

	rigs:destroy()

	return true, nil
end
