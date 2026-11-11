--[[
    A wake forgets the sleeper and keeps its slot, generation and entry, and
    gives the lying sample the woken history is seeded with: the sleeper's
    epoch and its place at the wake's tick, along a fall it is in
--]]

--!strict
local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local HIGH: vector = vector.create(5, 30, 5)
local LOW: vector = vector.create(5, 10, 5)
local YAW: number = 0.5
local EPOCH: number = 6 -- The character's when it fell asleep
local MOVE_TICK: number = 50
local WAKE_TICK: number = 53 -- Partway through the fall, which lasts about 0.77 s
local BED: vector = vector.create(40, 3, 40)
local BED_YAW: number = 2
local RECORD_STEP: number = 1 / 64 -- The history's position holds X and Z at the record's 1/64 stud
local NEAR: number = 1e-4

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Example: any = globals.require(globals.game:GetService("ServerScriptService").Fixtures.Config.Example)
	local History: any = globals.require(tread.Server.History)
	local Math: any = globals.require(tread.Step.Math)
	local Sleepers: any = globals.require(tread.Server.Sleepers)
	local Slots: any = globals.require(tread.Server.Slots)
	local State: any = globals.require(tread.Step.State)
	local World: any = globals.require(tread.Step.World)

	local shared: any = Example.shared()
	local server: any = Example.server()
	Slots.start(server.slots.reserve)
	History.start(shared, server)
	Sleepers.start(shared, World.new(shared.step, shared.rates.simulation, {}, shared.water, shared.rules, true))

	-- A character falls asleep, and the game drops its sleeper to the ground
	local slot: number, generation: number = Slots.take("Player")
	Slots.setEntry(slot, { kind = "Player", rig = "A" })

	local state: any = State.new()
	state.position = HIGH
	state.facing = YAW
	state.epoch = EPOCH
	Sleepers.adopt(slot, state)
	Sleepers.move(slot, LOW, YAW, MOVE_TICK)

	-- 1) It wakes partway down, where the fall has it then
	local at: vector = Math.fall(HIGH, LOW, shared.step.gravity, (WAKE_TICK - MOVE_TICK) / shared.rates.relay)
	local lying: any = Sleepers.wake(slot, WAKE_TICK)

	if not (at.y < HIGH.y and at.y > LOW.y) then
		return false, `The oracle's fall was not partway at the wake: {at}`
	elseif vector.magnitude(lying.position - at) > NEAR or math.abs(lying.yaw - YAW) > NEAR then
		return false, `The wake's lying sample lay at {lying.position} yaw {lying.yaw}, not {at} {YAW}`
	elseif lying.epoch ~= EPOCH or lying.platform ~= 0 then
		return false, `The wake's lying sample held epoch {lying.epoch} on platform {lying.platform}`
	elseif state.position ~= lying.position or state.posture ~= "Downed" then
		return false, `The woken state lay at {state.position}, not where the wake's sample did`
	end

	-- 2) Its slot, generation and entry stay for the woken character, and the module holds it no longer
	local kept: number, entry: any = Slots.get(slot)
	local read: boolean, readReason: any = pcall(Sleepers.sampleAt, slot, WAKE_TICK)
	local removed: boolean, removeReason: any = pcall(Sleepers.remove, slot)

	if kept ~= generation or entry == nil or entry.kind ~= "Sleeper" or Slots.count("Sleeper") ~= 1 then
		return false, `The wake left generation {kept} and {entry and entry.kind}, not the sleeper's slot as it was`
	elseif read or not string.find(`{readReason}`, "holds neither", 1, true) then
		return false, `A woken sleeper still answered sampleAt: {readReason}`
	elseif removed or not string.find(`{removeReason}`, "holds neither", 1, true) then
		return false, `A woken sleeper could still be removed: {removeReason}`
	end

	-- 3) The sample seeds the woken character's history, lying where it woke in its epoch
	History.seed(slot, WAKE_TICK, lying)

	local seeded: any = History.sampleAt(slot, WAKE_TICK)
	if seeded.posture ~= "Downed" or seeded.epoch ~= EPOCH or vector.magnitude(seeded.position - at) > RECORD_STEP then
		return false, `The seeded history read {seeded.posture} at {seeded.position} in epoch {seeded.epoch}`
	end

	-- 4) A sleeper never moved wakes where it lies
	local still: number = Sleepers.create("Sleeper", BED, BED_YAW)
	local resting: any = Sleepers.wake(still, WAKE_TICK)
	if resting.position ~= BED or math.abs(resting.yaw - BED_YAW) > NEAR or resting.epoch ~= 0 then
		return false, `A sleeper never moved woke at {resting.position} yaw {resting.yaw} epoch {resting.epoch}`
	end

	return true, nil
end
