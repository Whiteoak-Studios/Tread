--[[
    A move made while a sleeper falls starts its own fall from where the
    first fall has it at the new move's tick, its yaw included, and only
    that latest move is kept, so earlier times answer its start
--]]

--!strict
local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local HIGH: vector = vector.create(0, 40, 0)
local FIRST: vector = vector.create(10, 0, 0)
local FIRST_YAW: number = 1
local SECOND: vector = vector.create(20, 0, 10)
local SECOND_YAW: number = 2
local FIRST_TICK: number = 100
local SECOND_TICK: number = 105 -- A quarter of a second into the first fall, which lasts about 1.08 s
local NEAR: number = 1e-4 -- A vector holds float32, so a place sits within its rounding of the oracle's

type Read = { time: number, at: vector, yaw: number }

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Example: any = globals.require(globals.game:GetService("ServerScriptService").Fixtures.Config.Example)
	local History: any = globals.require(tread.Server.History)
	local Math: any = globals.require(tread.Step.Math)
	local Sleepers: any = globals.require(tread.Server.Sleepers)
	local Slots: any = globals.require(tread.Server.Slots)
	local World: any = globals.require(tread.Step.World)

	local shared: any = Example.shared()
	local server: any = Example.server()
	Slots.start(server.slots.reserve)
	History.start(shared, server)
	Sleepers.start(shared, World.new(shared.step, shared.rates.simulation, {}, shared.water, shared.rules, true))

	local gravity: number = shared.step.gravity
	local relay: number = shared.rates.relay
	local slot: number = Sleepers.create("Sleeper", HIGH, 0)

	Sleepers.move(slot, FIRST, FIRST_YAW, FIRST_TICK)
	Sleepers.move(slot, SECOND, SECOND_YAW, SECOND_TICK)

	-- Where the first fall had it at the second move's tick, partway down and turned partway to its yaw
	local start: vector, done: number = Math.fall(HIGH, FIRST, gravity, (SECOND_TICK - FIRST_TICK) / relay)
	local startYaw: number = FIRST_YAW * done
	if not (start.y > FIRST.y and start.y < HIGH.y and done > 0 and done < 1) then
		return false, `The oracle's first fall was not partway at the second move: {start}, {done}`
	end

	-- The second fall from there, by hand
	local drop: number = start.y - SECOND.y
	local ticks: number = math.sqrt(2 * drop / gravity) * relay
	local half: number = 0.5

	local reads: { Read } = {
		{ time = FIRST_TICK, at = start, yaw = startYaw }, -- Before the latest move's tick, its start
		{ time = SECOND_TICK - 1, at = start, yaw = startYaw },
		{ time = SECOND_TICK, at = start, yaw = startYaw },
		{
			time = SECOND_TICK + half * ticks,
			at = vector.create(
				start.x + (SECOND.x - start.x) * half,
				start.y - drop * half * half,
				start.z + (SECOND.z - start.z) * half
			),
			yaw = startYaw + (SECOND_YAW - startYaw) * half,
		},
		{ time = SECOND_TICK + ticks + 0.01, at = SECOND, yaw = SECOND_YAW },
	}

	for _, read: Read in reads do
		local sample: any = Sleepers.sampleAt(slot, read.time)

		if vector.magnitude(sample.position - read.at) > NEAR or math.abs(sample.yaw - read.yaw) > NEAR then
			return false,
				`At {read.time} the sleeper lay at {sample.position} yaw {sample.yaw}, not {read.at} {read.yaw}`
		end
	end

	return true, nil
end
