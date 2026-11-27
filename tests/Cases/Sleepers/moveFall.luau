--[[
    A moved sleeper keeps its slot and generation, and is hit lying at the
    old place before the move's tick, along a fall from rest under gravity
    during it with its yaw on the shortest arc, and at the new place after;
    a move not downward lands on its tick
--]]

--!strict
local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local FROM: vector = vector.create(0, 20, 0)
local FROM_YAW: number = 3
local TO: vector = vector.create(8, 2, -6)
local TO_YAW: number = -3 -- Past the half turn from FROM_YAW, so the short way round crosses it
local TICK: number = 100 -- The relay tick the move's fall starts on
local LEVEL_FROM: vector = vector.create(30, 2, 30)
local LEVEL_TO: vector = vector.create(36, 2, 30)
local RAISED: vector = vector.create(36, 6, 30) -- Above LEVEL_TO, so its move is not downward either
local LEVEL_TICK: number = 200
local RAISED_TICK: number = 210
local SPARE: number = 4000 -- A slot no sleeper holds, whose lying sample is the oracle's shapes
local NEAR: number = 1e-4 -- A vector holds float32, so a place sits within its rounding of the oracle's
local TURN: number = 2 * math.pi

type Read = { time: number, at: vector, yaw: number }

-- The angle between two yaws the short way round
local function apart(a: number, b: number): number
	return math.abs((a - b + math.pi) % TURN - math.pi)
end

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Example: any = globals.require(globals.game:GetService("ServerScriptService").Fixtures.Config.Example)
	local History: any = globals.require(tread.Server.History)
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
	local slot: number, generation: number, state: any = Sleepers.create("Sleeper", FROM, FROM_YAW)

	Sleepers.move(slot, TO, TO_YAW, TICK)

	-- 1) The move keeps the slot, its generation and its entry, and lays the state at the new place
	local kept: number, entry: any = Slots.get(slot)
	if kept ~= generation or entry.kind ~= "Sleeper" or Slots.count("Sleeper") ~= 1 then
		return false, `The move left generation {kept} and a {entry.kind} entry, not {generation} and a Sleeper`
	elseif state.position ~= TO or state.facing ~= TO_YAW or state.posture ~= "Downed" then
		return false, `The moved state lay at {state.position} facing {state.facing} in {state.posture}`
	end

	-- 2) The fall by hand: from rest under gravity, the drop going with the fraction's square
	local drop: number = FROM.y - TO.y
	local ticks: number = math.sqrt(2 * drop / gravity) * relay
	local arc: number = (TO_YAW - FROM_YAW + math.pi) % TURN - math.pi

	local function along(fraction: number): Read
		local at: vector = vector.create(
			FROM.x + (TO.x - FROM.x) * fraction,
			FROM.y - drop * fraction * fraction,
			FROM.z + (TO.z - FROM.z) * fraction
		)

		return { time = TICK + fraction * ticks, at = at, yaw = FROM_YAW + arc * fraction }
	end

	local reads: { Read } = {
		{ time = TICK - 30, at = FROM, yaw = FROM_YAW },
		{ time = TICK - 0.5, at = FROM, yaw = FROM_YAW },
		along(0),
		along(0.25),
		along(0.5),
		along(0.9),
		{ time = TICK + ticks + 0.01, at = TO, yaw = TO_YAW },
		{ time = TICK + 1000, at = TO, yaw = TO_YAW },
	}

	for _, read: Read in reads do
		local oracle: any = History.lying(SPARE, read.at, read.yaw, 0)
		local sample: any = Sleepers.sampleAt(slot, read.time)

		if vector.magnitude(sample.position - read.at) > NEAR or apart(sample.yaw, read.yaw) > NEAR then
			return false,
				`At {read.time} the sleeper lay at {sample.position} yaw {sample.yaw}, not {read.at} {read.yaw}`
		elseif sample.posture ~= "Downed" or sample.platform ~= 0 or sample.epoch ~= 0 then
			return false, `At {read.time} the sleeper was hit {sample.posture} on platform {sample.platform}`
		elseif
			vector.magnitude(sample.body.from - oracle.body.from) > NEAR
			or vector.magnitude(sample.body.to - oracle.body.to) > NEAR
			or vector.magnitude(sample.zones.head.from - oracle.zones.head.from) > NEAR
		then
			return false, `At {read.time} the lying shapes sat apart from a lying sample's at the same place`
		end
	end

	-- 3) A level move lands on its tick, and so does one upward from there
	local level: number = Sleepers.create("Sleeper", LEVEL_FROM, 0)

	local function landed(reads: { Read }): string?
		for _, read: Read in reads do
			local sample: any = Sleepers.sampleAt(level, read.time)

			if sample.position ~= read.at or apart(sample.yaw, read.yaw) > NEAR then
				return `At {read.time} the level sleeper lay at {sample.position} yaw {sample.yaw}, not {read.at}`
			end
		end

		return nil
	end

	Sleepers.move(level, LEVEL_TO, 1, LEVEL_TICK)

	local failure: string? = landed({
		{ time = LEVEL_TICK - 0.1, at = LEVEL_FROM, yaw = 0 },
		{ time = LEVEL_TICK, at = LEVEL_TO, yaw = 1 },
		{ time = LEVEL_TICK + 0.5, at = LEVEL_TO, yaw = 1 },
	})

	if failure then
		return false, failure
	end

	Sleepers.move(level, RAISED, 1, RAISED_TICK)

	failure = landed({
		{ time = RAISED_TICK - 0.5, at = LEVEL_TO, yaw = 1 },
		{ time = RAISED_TICK, at = RAISED, yaw = 1 },
		{ time = RAISED_TICK + 0.5, at = RAISED, yaw = 1 },
	})

	if failure then
		return false, failure
	end

	return true, nil
end
