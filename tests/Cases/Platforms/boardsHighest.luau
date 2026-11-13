--[[
    A grounded body boards the platform whose box top is highest within two
    skins under its feet and under its footprint, the lower id on a tie, and
    no box beside it, under it farther down or over its feet; boarding takes
    the platform's velocity from the body's, leaving gives it back, and a
    body off the ground boards nothing
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"
local PLATFORMS: string = "src/Step/Platforms.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local CONSTANTS: string = "src/Constants.luau"

local TICK: number = 10
local FEET: number = 1200 -- Where the body's feet stand
local X: number = 200
local SPEED: number = 5 -- Studs a second the rising plates rise at, a quarter stud a tick at 20 ticks a second

-- A plate 4 studs square whose top stands under the feet by below on the tick, rising at SPEED, centered off the
-- body by offset along X
local function plate(id: number, below: number, offset: number): { [string]: any }
	return {
		id = id,
		boxes = { { center = roblox.Vector3.new(0, -0.5, 0), size = roblox.Vector3.new(4, 1, 4) } },
		path = function (tick: number, _: number?): any
			return roblox.Vector3.new(X + offset, FEET - below + (tick - TICK) * SPEED / 20, 0)
		end,
	}
end

-- The platform a grounded body at the feet boards among the plates given, and its velocity after
local function boards(Riders: any, Platforms: any, Scene: any, plates: { { [string]: any } }): (number, vector)
	local world: any = Riders.world()
	for _, given: { [string]: any } in plates do
		Platforms.add(world, given)
	end

	world.clock = TICK
	world.tick = TICK

	local body: any = Scene.state(vector.create(X, FEET, 0), true)
	Platforms.board(body, world)

	return body.platform, body.velocity
end

return function (): (boolean, string | nil)
	local Riders: any = Environment.load(RIDERS)
	local Platforms: any = Environment.load(PLATFORMS)
	local Scene: any = Environment.load(SCENE)
	local Constants: any = Environment.load(CONSTANTS)
	local skin: number = Constants.SKIN
	local quantum: number = Constants.POSITION_QUANTUM
	local radius: number = Scene.settings.radius
	local rising: vector = vector.create(0, SPEED, 0)

	-- 1) The higher of two tops under the feet, and the platform's velocity taken off the body's
	local higher: number, velocity: vector =
		boards(Riders, Platforms, Scene, { plate(4, 2 * skin, 0), plate(5, skin, 0) })
	if higher ~= 5 then
		return false, `Between tops two skins and one skin under the feet the body boarded {higher}, not 5`
	elseif (velocity + rising).y > 1e-9 or (velocity + rising).y < -1e-9 then
		return false, `Boarding a plate rising at {SPEED} left the body moving at {velocity}`
	end

	-- 2) A tie goes to the lower id
	local tie: number = boards(Riders, Platforms, Scene, { plate(9, skin, 0), plate(6, skin, 0) })
	if tie ~= 6 then
		return false, `Between two tops at the same height the body boarded {tie}, not the lower id 6`
	end

	-- 3) Nothing past two skins down, over the feet, or only touching the footprint's side
	local refusals: { [string]: { [string]: any } } = {
		["a top past two skins down"] = plate(1, 2 * skin + quantum, 0),
		["a top over the feet"] = plate(1, -quantum, 0),
		["a box only touching its side"] = plate(1, skin, 2 + radius),
	}

	for label: string, given: { [string]: any } in refusals do
		local boarded: number = boards(Riders, Platforms, Scene, { given })
		if boarded ~= 0 then
			return false, `The body boarded {boarded} on {label}`
		end
	end

	-- 4) Leaving gives the platform's velocity back, and a body off the ground boards nothing
	local world: any = Riders.world()
	Platforms.add(world, plate(2, skin, 0))
	world.clock = TICK
	world.tick = TICK

	local rider: any = Scene.state(vector.create(X, FEET, 0), false)
	rider.platform = 2
	Platforms.board(rider, world)
	if rider.platform ~= 0 then
		return false, `A body off the ground stayed on {rider.platform}`
	elseif math.abs(rider.velocity.y - SPEED) > 1e-9 then
		return false, `Leaving a plate rising at {SPEED} left the body moving at {rider.velocity}, not with it`
	end

	return true, nil
end
