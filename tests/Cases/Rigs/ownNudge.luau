--[[
    The local player's own first-person copy, standing still, joins each
    frame's move beside its world rig and is raised by the nudge and back
    on the same frames, firstPerson.back studs behind it
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes, implementProperty and implementMethod

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local OWN: number = 9
local DISTANCE: number = 4 -- Studs from the eye to the world rig's feet
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

	local calls: { any } = {}
	local rigs: any = Rigs.new(Rig.settings(calls), Rig.drawDistance, Rig.collision())
	local world: any = rigs:checkout(OWN, {}, true)
	local copy: any = calls[2].rig

	local state = State.new()
	state.mode = "Ground"
	state.position = PLACE
	state.facing = FACING

	-- Each rig's target, its root's height above the soles over the state's feet, the copy's back studs behind along
	-- the facing, which looks along (-sin, 0, -cos)
	local height: number = world.PrimaryPart.CFrame.Position.Y
	local turn: any = roblox.CFrame.Angles(0, FACING, 0)
	local worldTarget: any = roblox.CFrame.new(PLACE.x, PLACE.y + height, PLACE.z) * turn
	local copyX: number = PLACE.x + math.sin(FACING) * Rig.back
	local copyZ: number = PLACE.z + math.cos(FACING) * Rig.back
	local copyTarget: any = roblox.CFrame.new(copyX, PLACE.y + height, copyZ) * turn
	local nudge: any = roblox.Vector3.new(0, NUDGE, 0)

	-- On their targets, both raised, then both back
	local lifted: { boolean } = { false, true, false }
	for frame: number, raised: boolean in lifted do
		rigs:pose(OWN, state, DISTANCE, 0)

		local queued: { any } = rigs._queued
		local both: boolean = #queued == 2
			and table.find(queued, rigs._slots[OWN]) ~= nil
			and table.find(queued, rigs._copy) ~= nil
		if not both then
			return false, `Frame {frame}'s move held {#queued} roots, not the world rig's and its copy's`
		end

		rigs:frame()

		local wantedWorld: any = worldTarget
		local wantedCopy: any = copyTarget
		if raised then
			wantedWorld += nudge
			wantedCopy += nudge
		end

		local drawn: any = copy.PrimaryPart.CFrame
		local placed: any = world.PrimaryPart.CFrame
		if apart(placed, wantedWorld) > TOLERANCE then
			return false, `After frame {frame} the world rig stood at {placed.Position}, not {wantedWorld.Position}`
		elseif apart(drawn, wantedCopy) > TOLERANCE then
			return false, `After frame {frame} the copy stood at {drawn.Position}, not {wantedCopy.Position}`
		end
	end

	rigs:destroy()

	return true, nil
end
