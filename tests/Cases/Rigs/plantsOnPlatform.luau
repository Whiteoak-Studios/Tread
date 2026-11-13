--[[
    A pool handed the world plants each foot through the world's casts as
    they stand at the plant, so once a platform registered after the start
    wraps them, a foot over the platform meets its box; a pool handed only
    casts keeps those, and one handed no world refuses anything else
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes, implementProperty and implementMethod

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local PLATFORMS: string = "src/Step/Platforms.luau"
local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local SLOT: number = 6
local LIFT: number = 4
local DISTANCE: number = 4 -- Studs from the eye, inside every detail range
local TOP: number = 1200 -- The lift's floor's top, away from every part of the step's fixture
local DROP: number = 20 -- How far above the top the check's cast starts, and how far it reaches

-- One plant the pool asked for: the casts it was handed and whether the feet plant
type Plant = { collision: any, planting: boolean }

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
		detail = function (_: any, _: boolean) end,
		pose = function (_: any, _: any, _: boolean) end,
		aim = function (_: any, _: number, _: number) end,
		plant = function (_: any, _: any, _: number, _: number, collision: any, planting: boolean, _: boolean)
			table.insert(plants, { collision = collision, planting = planting })
		end,
		layer = function (_: any) end,
		stop = function (_: any) end,
		watch = function (...: any) end,
		markers = function (_: any): { string }
			return {}
		end,
		release = function (_: any) end,
	}

	local Rigs = Environment.load(RIGS, { [ANIMATE] = Animate })
	local Rig = Environment.load(RIG)
	local State = Environment.load(STATE)
	local Platforms: any = Environment.load(PLATFORMS)
	local Riders: any = Environment.load(RIDERS)

	local world: any = Riders.world()
	local casts: any = world.collision
	local rigs = Rigs.new(Rig.settings({}), Rig.drawDistance, casts, world)
	local kept = Rigs.new(Rig.settings({}), Rig.drawDistance, casts)

	-- The lift registers after both pools started, so its wrapper replaces the world's casts
	Platforms.add(world, Riders.lift(LIFT, roblox.Vector3.new(0, TOP, 0), 0, 0))
	if world.collision == casts then
		return false, "Registering the lift left the world's casts unwrapped"
	end

	-- A body standing still on the lift, inside the foot range
	local state = State.new()
	state.position = vector.create(0, TOP, 0)
	state.mode = "Ground"
	state.grounded = true

	rigs:checkout(SLOT, {})
	rigs:pose(SLOT, state, DISTANCE, 0)

	local plant: Plant? = plants[#plants]
	if plant == nil or not plant.planting then
		return false, "A body standing still on the lift planted no feet"
	elseif plant.collision ~= world.collision then
		return false, "The pool handed the world planted through the casts it was started with, not the wrapper"
	end

	-- What the plant's casts meet under the foot: the lift's box top, where the world's own casts meet nothing
	local down: vector = vector.create(0, -2 * DROP, 0)
	local above: vector = vector.create(0, TOP + DROP, 0)
	local met: any = plant.collision.ray(above, down)
	if met == nil or met.position.y ~= TOP or met.material ~= roblox.Enum.Material.Plastic then
		return false, `The plant's casts met {met and met.position} under the foot, not the lift's top at {TOP}`
	elseif casts.ray(above, down) ~= nil then
		return false, "The world's own casts met something under the lift, so the check proves nothing"
	end

	-- A pool handed only casts plants through those, wrapped or not
	kept:checkout(SLOT, {})
	kept:pose(SLOT, state, DISTANCE, 0)

	local bare: Plant? = plants[#plants]
	if bare == nil or bare.collision ~= casts then
		return false, "A pool handed only casts planted through something else"
	end

	-- A world that is no table is refused
	if pcall(Rigs.new, Rig.settings({}), Rig.drawDistance, casts, 5) then
		return false, "Rigs.new took a number as its world"
	end

	rigs:destroy()
	kept:destroy()

	return true, nil
end
