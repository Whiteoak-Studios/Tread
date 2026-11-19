--[[
    A rig whose place or facing changes stands on its new target after
    that frame's move, never the nudge above it, whether its root stood
    raised or on its old target, and its next still frame raises it
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes, implementProperty and implementMethod

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local SLOT: number = 2
local DISTANCE: number = 4 -- Studs from the eye, inside every detail range
local FIRST: vector = vector.create(10, 2, -5)
local SECOND: vector = vector.create(14, 2.5, -9)
local NUDGE: number = 0.001 -- Studs a still rig's root rises on alternate frames, as the pool's constant gives it
local TOLERANCE: number = 1e-4 -- Studs, a tenth of the nudge, since a CFrame holds 32-bit floats

-- One frame's pose, where its root stands after the frame's move, and why
type Step = { place: vector, facing: number, raised: boolean, why: string }

-- A first draw, a facing alone changed while raised, and a place changed while on the target, each then still
local STEPS: { Step } = {
	{ place = FIRST, facing = 0, raised = false, why = "drawn for the first time" },
	{ place = FIRST, facing = 0, raised = true, why = "still" },
	{ place = FIRST, facing = 1, raised = false, why = "turned while raised" },
	{ place = FIRST, facing = 1, raised = true, why = "still after turning" },
	{ place = FIRST, facing = 1, raised = false, why = "still again" },
	{ place = SECOND, facing = 1, raised = false, why = "moved while on its target" },
	{ place = SECOND, facing = 1, raised = true, why = "still after moving" },
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

	-- The root's height above the soles, which stand at 0 on the template every rig is cloned from
	local height: number = model.PrimaryPart.CFrame.Position.Y

	for frame: number, step: Step in STEPS do
		state.position = step.place
		state.facing = step.facing
		rigs:pose(SLOT, state, DISTANCE, 0)
		rigs:frame()

		local at: vector = step.place
		local wanted: any = roblox.CFrame.new(at.x, at.y + height, at.z) * roblox.CFrame.Angles(0, step.facing, 0)
		if step.raised then
			wanted += roblox.Vector3.new(0, NUDGE, 0)
		end

		local stands: any = model.PrimaryPart.CFrame
		if apart(stands, wanted) > TOLERANCE then
			return false, `Frame {frame}, {step.why}, left the root at {stands.Position}, not {wanted.Position}`
		end
	end

	rigs:destroy()

	return true, nil
end
