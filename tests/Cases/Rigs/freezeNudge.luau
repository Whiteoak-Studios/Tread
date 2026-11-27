--[[
    A frozen rig is never posed, and the frame's end puts its root in every
    frame's move all the same, the nudge above where it stands and back on
    it on alternate frames, its move's list emptied after each
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
local FRAMES: number = 6 -- Frames run once the rig is frozen

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

	-- Lune loads no animation, so Animate's stand-in plays nothing and counts the poses it is asked for
	local poses: number = 0
	local function nothing(_: any) end
	local Animate: { [string]: any } = {
		check = nothing,
		places = function (_: any, _: any): { any }
			return {}
		end,
		load = function (rig: Model, _: any): any
			return { rig = rig, tracks = {} }
		end,
		pose = function (_: any)
			poses += 1
		end,
		speed = nothing,
		stop = nothing,
		detail = nothing,
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

	-- The state's feet raised by the root's height above the soles, turned to its facing, and that the nudge higher
	local height: number = model.PrimaryPart.CFrame.Position.Y
	local target: any = roblox.CFrame.new(PLACE.x, PLACE.y + height, PLACE.z) * roblox.CFrame.Angles(0, FACING, 0)
	local raised: any = target + roblox.Vector3.new(0, NUDGE, 0)

	-- Its one pose puts it on its target, and the freeze comes at the next frame's start, before any pose
	rigs:pose(SLOT, state, DISTANCE, 0)
	rigs:frame()
	if apart(model.PrimaryPart.CFrame, target) > TOLERANCE then
		return false, `The rig's pose left its root at {model.PrimaryPart.CFrame.Position}, not on its target`
	elseif rigs:freeze(SLOT) ~= true then
		return false, "Rigs.freeze refused a drawn rig"
	elseif #rigs._queued ~= 0 then
		return false, "The freeze itself queued the rig's root, before the frame's end"
	end

	-- Each frame's end alone moves the root: up on the first, back down on the next, and so on
	for frame: number = 1, FRAMES do
		rigs:frame()

		local wanted: any = frame % 2 == 1 and raised or target
		local stands: any = model.PrimaryPart.CFrame
		if apart(stands, wanted) > TOLERANCE then
			return false, `Frozen frame {frame} left the root at {stands.Position}, not at {wanted.Position}`
		elseif #rigs._queued ~= 0 then
			return false, `Frozen frame {frame}'s move left {#rigs._queued} roots queued`
		end
	end

	if poses ~= 1 then
		return false, `The rig was posed {poses} times, {poses - 1} of them while it stood frozen`
	elseif model.Parent == nil then
		return false, "A frozen rig left Workspace"
	end

	rigs:destroy()

	return true, nil
end
