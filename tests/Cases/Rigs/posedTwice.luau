--[[
    A still rig posed twice before one frame's end joins its move once and
    steps once, so two frames of that leave its root where two frames of
    single poses leave another rig's posed from the same state
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes, implementProperty and implementMethod

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local TWICE: number = 1 -- The slot posed twice a frame
local ONCE: number = 2 -- The slot posed once a frame
local DISTANCE: number = 4 -- Studs from the eye, inside every detail range
local PLACE: vector = vector.create(10, 2, -5)
local FACING: number = 1 -- Radians
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
	local twice: any = rigs:checkout(TWICE, {})
	local once: any = rigs:checkout(ONCE, {})
	local entry: any = rigs._slots[TWICE]

	local state = State.new()
	state.mode = "Ground"
	state.position = PLACE
	state.facing = FACING

	-- The state's feet raised by the root's height above the soles, which stand at 0 on the template, turned to its
	-- facing, and that the nudge higher
	local height: number = twice.PrimaryPart.CFrame.Position.Y
	local target: any = roblox.CFrame.new(PLACE.x, PLACE.y + height, PLACE.z) * roblox.CFrame.Angles(0, FACING, 0)
	local raised: any = target + roblox.Vector3.new(0, NUDGE, 0)

	-- The first frame places both rigs, and the second, both still, raises both
	local wanted: { any } = { target, raised }
	for frame: number, place: any in wanted do
		rigs:pose(TWICE, state, DISTANCE, 0)
		rigs:pose(ONCE, state, DISTANCE, 0)
		rigs:pose(TWICE, state, DISTANCE, 0)

		local held: number = 0
		for _, queued: any in rigs._queued do
			if queued == entry then
				held += 1
			end
		end

		if #rigs._queued ~= 2 or held ~= 1 then
			return false,
				`Frame {frame}'s move held {#rigs._queued} roots, the twice-posed rig's {held} times, not once`
		end

		rigs:frame()

		local single: any = once.PrimaryPart.CFrame
		if apart(single, place) > TOLERANCE then
			return false, `After frame {frame} the rig posed once stood at {single.Position}, not {place.Position}`
		elseif twice.PrimaryPart.CFrame ~= single then
			local stands: any = twice.PrimaryPart.CFrame.Position
			return false,
				`After frame {frame} the rig posed twice stood at {stands}, not with the other at {single.Position}`
		end
	end

	rigs:destroy()

	return true, nil
end
