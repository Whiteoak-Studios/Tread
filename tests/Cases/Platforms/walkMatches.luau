--[[
    A walk on a rising lift is the same walk as on a still one in the
    lift's own space: a walk, a sprint and a crouched walk across its top
    give the same platform-space place, velocity and state every tick
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"
local PLATFORMS: string = "src/Step/Platforms.luau"

local LIFT: number = 3
local START: number = 400
local RISE: number = 0.25 -- Studs a tick the moving lift rises
local YAW: number = 0.4 -- Off every axis, so each step's numbers are no round ones

-- Each stretch of the walk: its ticks and its inputs
local LEGS: { { ticks: number, forward: number, right: number, sprint: boolean, crouch: boolean } } = {
	{ ticks = 6, forward = 1, right = 0, sprint = false, crouch = false },
	{ ticks = 3, forward = 1, right = 0.4, sprint = true, crouch = false },
	{ ticks = 5, forward = -0.6, right = -0.7, sprint = false, crouch = true },
}

-- The walk on a lift rising rise studs a tick, each tick's place on it, velocity and state in order
local function walk(Riders: any, Platforms: any, rise: number): { { [string]: any } }
	local world: any = Riders.world()
	Platforms.add(world, Riders.lift(LIFT, roblox.Vector3.new(200, 1200, 0), START, rise))
	world.clock = START

	local body: any = Riders.standOn(world, LIFT, START, 0, 3)
	local command: any = Riders.command()
	command.yaw = YAW

	local ticks: { { [string]: any } } = {}
	local tick: number = START

	for _, leg in LEGS do
		for count: number = 1, leg.ticks do
			command.forward, command.right = leg.forward, leg.right
			command.sprint, command.crouch = leg.sprint, leg.crouch
			command.pressed.sprint = leg.sprint and count == 1
			command.pressed.crouch = leg.crouch and count == 1

			tick += 1
			Riders.step(body, command, world, tick)
			table.insert(ticks, {
				place = body.position - Platforms.at(world, LIFT, tick),
				velocity = body.velocity,
				platform = body.platform,
				grounded = body.grounded,
				posture = body.posture,
			})
		end
	end

	return ticks
end

return function (): (boolean, string | nil)
	local Riders: any = Environment.load(RIDERS)
	local Platforms: any = Environment.load(PLATFORMS)

	local still: { { [string]: any } } = walk(Riders, Platforms, 0)
	local rising: { { [string]: any } } = walk(Riders, Platforms, RISE)

	for index: number, want: { [string]: any } in still do
		local got: { [string]: any } = rising[index]

		for key: string, value: any in want do
			if got[key] ~= value then
				return false, `On the walk's tick {index} the rising lift gave {key} {got[key]}, the still one {value}`
			end
		end
	end

	-- The walk went somewhere, and stayed on the lift throughout
	local last: { [string]: any } = still[#still]
	if last.platform ~= LIFT or (last.place - still[1].place) == vector.zero then
		return false, "The walk left the lift or never moved across it"
	end

	return true, nil
end
