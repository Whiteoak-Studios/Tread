--[[
    A rider keeps its platform-space offset tick after tick, grounded on it
    with no velocity of its own: on a lift rising across the u16 wrap the
    world's tick runs in, its clock set once before it, on a block sliding
    sideways, and on a lift falling faster than the ground snap reaches
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"
local PLATFORMS: string = "src/Step/Platforms.luau"

local LIFT: number = 7
local START: number = 65520 -- A few ticks before the wrap, so the ride crosses it
local RISES_AT: number = 65524
local RISE: number = 0.25 -- Studs a tick, 5 studs a second
local SLIDE: number = 0.4 -- Studs a tick the sideways block slides along X and Z each
local FALL: number = 1.5 -- Studs a tick the falling lift drops, past the walk's ground snap of under a stud
local TICKS: number = 30
local OFFSET_X: number = 2.5 -- Where the body stands across the platform's top
local OFFSET_Z: number = -1.25

-- A platform the elevator's floor's size, its top at its position, moving by step each tick from tick START
local function moving(step: any): { [string]: any }
	return {
		id = LIFT,
		boxes = { { center = roblox.Vector3.new(0, -0.5, 0), size = roblox.Vector3.new(10, 1, 10) } },
		path = function (tick: number, _: number?): any
			return roblox.Vector3.new(200, 1200, 0) + step * (tick - START)
		end,
	}
end

-- Why the rider did not keep its offset on the platform for the ride, or nil, and how far it went
local function ride(Riders: any, Platforms: any, platform: { [string]: any }): (string?, vector)
	local world: any = Riders.world()
	Platforms.add(world, platform)
	world.clock = START

	local body: any = Riders.standOn(world, LIFT, START, OFFSET_X, OFFSET_Z)
	local offset: vector = body.position - Platforms.at(world, LIFT, START)
	local from: vector = body.position
	local command: any = Riders.command()

	-- It stands there on tick START, so it rides from the tick after
	for tick: number = START + 1, START + TICKS do
		Riders.step(body, command, world, tick)

		local now: vector = body.position - Platforms.at(world, LIFT, tick)
		if now ~= offset then
			return `on tick {tick} the rider stood {now} from it, where it started {offset} from it`, vector.zero
		elseif body.platform ~= LIFT or not body.grounded or body.mode ~= "Ground" then
			return `on tick {tick} the rider was on {body.platform}, grounded {body.grounded}, in {body.mode}`,
				vector.zero
		elseif body.velocity ~= vector.zero then
			return `on tick {tick} the rider had a velocity of {body.velocity} of its own on it`, vector.zero
		end
	end

	return nil, body.position - from
end

return function (): (boolean, string | nil)
	local Riders: any = Environment.load(RIDERS)
	local Platforms: any = Environment.load(PLATFORMS)

	local rising: string?, risen: vector =
		ride(Riders, Platforms, Riders.lift(LIFT, roblox.Vector3.new(200, 1200, 0), RISES_AT, RISE))
	local lifted: number = (START + TICKS - RISES_AT) * RISE
	if rising then
		return false, `On the rising lift {rising}`
	elseif risen ~= vector.create(0, lifted, 0) then
		return false, `The rider rose {risen} with the lift, not {lifted} studs straight up`
	end

	local sideways: string?, slid: vector = ride(Riders, Platforms, moving(roblox.Vector3.new(SLIDE, 0, SLIDE)))
	if sideways then
		return false, `On the sliding block {sideways}`
	elseif slid.y ~= 0 or slid.x <= 0 or slid.x ~= slid.z then
		return false, `The rider slid {slid} with the block, not along it`
	end

	local falling: string? = ride(Riders, Platforms, moving(roblox.Vector3.new(0, -FALL, 0)))
	if falling then
		return false, `On the falling lift {falling}`
	end

	return true, nil
end
