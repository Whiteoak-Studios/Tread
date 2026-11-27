--[[
    A drawn rig posed from one unchanged state joins each frame's move
    once, its root on its target after the first frame, the nudge above
    it after the second and back on its target after the third
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes, implementProperty and implementMethod

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local SLOT: number = 4
local DISTANCE: number = 4 -- Studs from the eye, inside every detail range
local PLACE: vector = vector.create(10, 2, -5)
local FACING: number = 2.3 -- Radians, along neither axis
local NUDGE: number = 0.001 -- Studs a still rig's root rises on alternate frames, as the pool's constant gives it
local TOLERANCE: number = 1e-4 -- Studs, a tenth of the nudge, since a CFrame holds 32-bit floats

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
	local entry: any = rigs._slots[SLOT]

	local state = State.new()
	state.mode = "Ground"
	state.position = PLACE
	state.facing = FACING

	-- The state's feet raised by the root's height above the soles, which stand at 0 on the template, turned to its
	-- facing, and that the nudge higher
	local height: number = model.PrimaryPart.CFrame.Position.Y
	local target: any = roblox.CFrame.new(PLACE.x, PLACE.y + height, PLACE.z) * roblox.CFrame.Angles(0, FACING, 0)
	local raised: any = target + roblox.Vector3.new(0, NUDGE, 0)

	-- Each frame poses the rig once from the same state, and its move holds the rig's root alone
	local wanted: { any } = { target, raised, target }
	local names: { string } = { "its target", "the nudge above its target", "back on its target" }
	for frame: number, place: any in wanted do
		rigs:pose(SLOT, state, DISTANCE, 0)

		local queued: { any } = rigs._queued
		if #queued ~= 1 or queued[1] ~= entry then
			return false, `Frame {frame}'s move held {#queued} roots, not the still rig's alone`
		end

		rigs:frame()

		local stands: any = model.PrimaryPart.CFrame
		if apart(stands, place) > TOLERANCE then
			return false,
				`After frame {frame} the root stood at {stands.Position}, not {names[frame]} at {place.Position}`
		end
	end

	rigs:destroy()

	return true, nil
end
