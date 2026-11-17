--[[
    A rig posed lying down joins a frame's move only when its place
    changes, so one lying still is in no frame's move after the one that
    placed it, and its root stays on its target
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes, implementProperty and implementMethod

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local SLOT: number = 7
local DISTANCE: number = 4 -- Studs from the eye, inside every detail range
local FIRST: vector = vector.create(-40, 7.5, 120)
local SECOND: vector = vector.create(-38, 7.5, 121)
local FACING: number = math.pi / 2 -- Radians
local TOLERANCE: number = 1e-4 -- Studs, a tenth of the pool's nudge, since a CFrame holds 32-bit floats

-- One frame's pose and whether the frame's move holds the rig's root
type Step = { place: vector, joins: boolean }

-- Placed, still three frames, moved, then still again
local STEPS: { Step } = {
	{ place = FIRST, joins = true },
	{ place = FIRST, joins = false },
	{ place = FIRST, joins = false },
	{ place = FIRST, joins = false },
	{ place = SECOND, joins = true },
	{ place = SECOND, joins = false },
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

	-- Lying on the ground, as a sleeper or a body is posed
	local state = State.new()
	state.mode = "Ground"
	state.posture = "Downed"
	state.facing = FACING

	-- The root's height above the soles, which stand at 0 on the template every rig is cloned from
	local height: number = model.PrimaryPart.CFrame.Position.Y

	for frame: number, step: Step in STEPS do
		state.position = step.place
		rigs:pose(SLOT, state, DISTANCE, 0)

		local held: number = #rigs._queued
		if step.joins and held ~= 1 then
			return false, `Frame {frame} moved the lying rig to a new place, but its move held {held} roots`
		elseif not step.joins and held ~= 0 then
			return false, `Frame {frame}'s move held {held} roots, though the only rig lay still`
		end

		rigs:frame()

		local at: vector = step.place
		local wanted: any = roblox.CFrame.new(at.x, at.y + height, at.z) * roblox.CFrame.Angles(0, FACING, 0)
		local stands: any = model.PrimaryPart.CFrame
		if apart(stands, wanted) > TOLERANCE then
			return false, `After frame {frame} the lying rig's root stood at {stands.Position}, not {wanted.Position}`
		end
	end

	rigs:destroy()

	return true, nil
end
