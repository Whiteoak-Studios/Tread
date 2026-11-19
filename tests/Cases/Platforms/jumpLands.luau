--[[
    A jump in a steadily rising lift leaves it with the lift's velocity on
    top of its own, follows the same path in the lift's space as a jump on
    a still lift, and lands where it left, boarding the lift again with
    its velocity its own once more
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"
local PLATFORMS: string = "src/Step/Platforms.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"

local LIFT: number = 4
local START: number = 900
local RISE: number = 0.25 -- Studs a tick, 5 studs a second at 20 ticks a second
local LIFT_SPEED: number = 5
local FLIGHT: number = 30 -- Ticks it watches the jump for, past its landing

-- The jump from a lift rising rise studs a tick: where it left from on the lift, then each tick's place on it, its
-- platform and its world velocity
local function jump(Riders: any, Platforms: any, rise: number): (vector, { { [string]: any } })
	local world: any = Riders.world()
	Platforms.add(world, Riders.lift(LIFT, roblox.Vector3.new(200, 1200, 0), START, rise))
	world.clock = START

	local body: any = Riders.standOn(world, LIFT, START, 1, -2)
	local from: vector = body.position - Platforms.at(world, LIFT, START)
	local command: any = Riders.command()
	local ticks: { { [string]: any } } = {}

	for tick: number = START + 1, START + FLIGHT do
		command.jump = tick == START + 1
		command.pressed.jump = command.jump

		Riders.step(body, command, world, tick)
		table.insert(ticks, {
			place = body.position - Platforms.at(world, LIFT, tick),
			platform = body.platform,
			velocity = body.velocity,
		})
	end

	return from, ticks
end

return function (): (boolean, string | nil)
	local Riders: any = Environment.load(RIDERS)
	local Platforms: any = Environment.load(PLATFORMS)
	local Scene: any = Environment.load(SCENE)

	local _, still: { { [string]: any } } = jump(Riders, Platforms, 0)
	local from: vector, rising: { { [string]: any } } = jump(Riders, Platforms, RISE)

	-- The jump's tick leaves the lift carrying its velocity on top of the jump's own
	local first: { [string]: any } = rising[1]
	local leaving: vector = vector.create(0, Scene.settings.jump + LIFT_SPEED, 0)
	if first.platform ~= 0 then
		return false, `The jump's tick left the body on platform {first.platform}`
	elseif first.velocity ~= leaving then
		return false, `The jump left the lift at {first.velocity}, not its own jump plus the lift's, {leaving}`
	end

	local landed: number? = nil
	for index: number, want: { [string]: any } in still do
		local got: { [string]: any } = rising[index]

		if got.place ~= want.place or got.platform ~= want.platform then
			local over: string = `{got.place} on {got.platform} over the rising lift`
			return false,
				`On the jump's tick {index} it stood {over}, and {want.place} on {want.platform} over the still one`
		end

		if landed == nil and index > 1 and got.platform == LIFT then
			landed = index
		end
	end

	if landed == nil then
		return false, "The jump never landed back on the rising lift"
	end

	-- Back on it, it stands where it left, its velocity its own again
	local back: { [string]: any } = rising[#rising]
	if back.place ~= from or back.velocity ~= vector.zero then
		return false, `After landing it stood {back.place} on the lift at {back.velocity}, where it left from {from}`
	end

	return true, nil
end
