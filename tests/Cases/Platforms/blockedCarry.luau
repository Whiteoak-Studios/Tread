--[[
    A lift that carries its rider into a roof stops the carry a skin under
    the roof and drops the rider off it, and the lift rising on into its
    feet leaves it pressed between the two with no clear spot, which the
    step gives back as stuck
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"
local PLATFORMS: string = "src/Step/Platforms.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local CONSTANTS: string = "src/Constants.luau"

local LIFT: number = 6
local START: number = 50
local RISE: number = 0.25 -- Studs a tick
local UNDERSIDE: number = 1206 -- The roof's underside, under a stud over a standing rider's head on the lift
local TICKS: number = 8

return function (): (boolean, string | nil)
	local Riders: any = Environment.load(RIDERS)
	local Platforms: any = Environment.load(PLATFORMS)
	local Scene: any = Environment.load(SCENE)
	local Constants: any = Environment.load(CONSTANTS)

	local roof: any = {
		name = "Roof",
		center = vector.create(200, UNDERSIDE + 0.5, 0),
		size = vector.create(20, 1, 20),
		tilt = 0,
	}

	local world: any = Riders.world({ roof })
	Platforms.add(world, Riders.lift(LIFT, roblox.Vector3.new(200, 1200, 0), START, RISE))
	world.clock = START

	local body: any = Riders.standOn(world, LIFT, START, 0, 0)
	local command: any = Riders.command()
	local skin: number = Constants.SKIN
	local quantum: number = Constants.POSITION_QUANTUM

	for tick: number = START + 1, START + TICKS do
		local _, stuck: number? = Riders.step(body, command, world, tick)
		local head: number = body.position.y + Scene.settings.standing

		if body.platform == 0 then
			if math.abs(head - (UNDERSIDE - skin)) > quantum then
				return false, `The blocked carry stopped the head at {head}, not a skin under the roof at {UNDERSIDE}`
			elseif stuck == nil then
				return false, "The lift rising into the dropped rider's feet under the roof gave back no stuck depth"
			end

			return true, nil
		elseif head > UNDERSIDE - skin + quantum then
			return false, `On tick {tick} the rider's head rose to {head}, into the roof at {UNDERSIDE}`
		end
	end

	return false, `The lift carried its rider for {TICKS} ticks into a roof without dropping it`
end
