--[[
    A moved sleeper is sampled under the gravity the world gives each render
    time: an 18-stud drop under 68.1 changed to 30 from 8 ticks after its
    move follows Math.fall under 68.1 before that tick and 30 from it, going
    from 5.448 studs fallen to 2.4 and at rest from about 1.095 s, and a move
    after the change falls under 30 from its start
--]]

--!strict
local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local HIGH: vector = vector.create(0, 22, 0)
local LOW: vector = vector.create(0, 4, 0) -- 18 studs under HIGH
local LOWER: vector = vector.create(6, -14, 0) -- 18 studs under LOW
local MOVED: number = 100 -- The relay tick the first move falls from
local CHANGE_AFTER: number = 8 -- Relay ticks after the move the gravity changes from, 0.4 s at 20 Hz
local AGAIN: number = 140 -- The relay tick the second falls from, the first long done
local CHANGED: number = 30 -- Studs/s², the gravity the change sets
local SAMPLES: number = 40 -- Relay ticks sampled from each move's tick
local JUST_BEFORE: number = 1e-6 -- Relay ticks before the change's tick a sample still falls under 68.1
local FALLEN_BEFORE: number = 5.448 -- Studs fallen 0.4 s in under 68.1, half of 68.1 times 0.4 squared
local FALLEN_AFTER: number = 2.4 -- The same under 30
local LANDS: number = 1.0954 -- Seconds the drop takes under 30, the square root of 36 over 30
local NEAR: number = 1e-4 -- A vector holds float32, so a place sits within its rounding of the oracle's
local LANDS_NEAR: number = 1e-4 -- Seconds the landing may sit off the known answer, which is rounded

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
	local world: any = World.new(shared.step, shared.rates.simulation, {}, shared.water, shared.rules, true)
	Slots.start(server.slots.reserve)
	History.start(shared, server)
	Sleepers.start(shared, world)

	local gravity: number = shared.step.gravity
	local relay: number = shared.rates.relay
	local changeAt: number = MOVED + CHANGE_AFTER
	local slot: number = Sleepers.create("Sleeper", HIGH, 0)

	-- The gravity a relay time is under, 68.1 before the change's tick and 30 from it
	local function under(time: number): number
		if time < changeAt then
			return gravity
		end

		return CHANGED
	end

	-- Why the sleeper doesn't lie where Math.fall puts it at a relay time under that time's gravity, or nil
	local function follows(from: vector, to: vector, start: number, time: number): string?
		local expected: vector = Math.fall(from, to, under(time), (time - start) / relay)
		local sample: any = Sleepers.sampleAt(slot, time)

		if vector.magnitude(sample.position - expected) > NEAR then
			return `At relay tick {time} the sleeper lay at {sample.position}, not {expected} under {under(time)}`
		end

		return nil
	end

	-- 1) The move under 68.1, then the change from 8 ticks into its fall, in the world's simulation ticks
	Sleepers.move(slot, LOW, 0, MOVED)
	World.setGravity(world, CHANGED, changeAt * shared.rates.simulation / relay)

	for tick: number = MOVED, MOVED + SAMPLES do
		local problem: string? = follows(HIGH, LOW, MOVED, tick)
		if problem then
			return false, `The first fall: {problem}`
		end
	end

	-- 2) The known answer across the change: 5.448 studs fallen just before its tick, 2.4 on it
	local problem: string? = follows(HIGH, LOW, MOVED, changeAt - JUST_BEFORE)
	if problem then
		return false, `Just before the change: {problem}`
	end

	local before: number = HIGH.y - Sleepers.sampleAt(slot, changeAt - JUST_BEFORE).position.y
	local after: number = HIGH.y - Sleepers.sampleAt(slot, changeAt).position.y
	if math.abs(before - FALLEN_BEFORE) > NEAR or math.abs(after - FALLEN_AFTER) > NEAR then
		return false, `The sleeper had fallen {before} studs just before the change and {after} on it`
	end

	-- 3) At rest only once the fall under 30 is done, past where 68.1's would have ended
	local landed: number = math.sqrt(2 * (HIGH.y - LOW.y) / CHANGED)
	local landTick: number = MOVED + landed * relay
	-- Each read rewrites the slot's one sample, so each place is taken as it is read
	local lastFalling: vector = Sleepers.sampleAt(slot, math.ceil(landTick) - 1).position
	local firstAtRest: vector = Sleepers.sampleAt(slot, math.ceil(landTick)).position
	if math.abs(landed - LANDS) > LANDS_NEAR then
		return false, `The drop under {CHANGED} takes {landed} s, not {LANDS}`
	elseif lastFalling.y <= LOW.y or firstAtRest ~= LOW then
		return false, `Around {landTick} the sleeper lay at {lastFalling}, then {firstAtRest}`
	end

	-- 4) A move after the change falls under its gravity, from where the first fall landed
	Sleepers.move(slot, LOWER, 0, AGAIN)

	for tick: number = AGAIN, AGAIN + SAMPLES do
		local later: string? = follows(LOW, LOWER, AGAIN, tick)
		if later then
			return false, `The move after the change: {later}`
		end
	end

	return true, nil
end
