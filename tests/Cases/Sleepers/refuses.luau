--[[
    Sleepers refuses a call before its start, a start with no world and a
    second start, a kind, place, yaw, tick, slot or state it cannot take, a
    body where only a sleeper will do, and a move older than the last,
    changing nothing
--]]

--!strict
local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local SLEEPERS: string = "src/Server/Sleepers.luau"
local BED: vector = vector.create(0, 2, 0)
local LOW: vector = vector.create(4, 0, 0)
local TICK: number = 100
local NAN: number = 0 / 0

type Refusal = { name: string, call: () -> (), says: string }

return function (): (boolean, string | nil)
	-- 1) Before start
	local unstarted: any = Environment.load(SLEEPERS)
	local early: { Refusal } = {
		{
			name = "create",
			call = function ()
				unstarted.create("Sleeper", BED, 0)
			end,
			says = "ran before Sleepers.start",
		},
		{
			name = "sampleAt",
			call = function ()
				unstarted.sampleAt(0, 0)
			end,
			says = "ran before Sleepers.start",
		},
		{
			name = "adopt",
			call = function ()
				unstarted.adopt(0, {})
			end,
			says = "ran before Sleepers.start",
		},
	}

	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Example: any = globals.require(globals.game:GetService("ServerScriptService").Fixtures.Config.Example)
	local History: any = globals.require(tread.Server.History)
	local Sleepers: any = globals.require(tread.Server.Sleepers)
	local Slots: any = globals.require(tread.Server.Slots)
	local State: any = globals.require(tread.Step.State)
	local World: any = globals.require(tread.Step.World)

	local shared: any = Example.shared()
	local server: any = Example.server()
	local world: any = World.new(shared.step, shared.rates.simulation, {}, shared.water, shared.rules, true)
	Slots.start(server.slots.reserve)
	History.start(shared, server)
	Sleepers.start(shared, world)

	local sleeper: number, _: number, state: any = Sleepers.create("Sleeper", BED, 0)
	local body: number = Sleepers.create("Body", BED, 0)
	Sleepers.move(sleeper, LOW, 0, TICK)

	local entryless: number = Slots.take("Player") -- Taken, with no entry set yet
	local npc: number = Slots.take("Npc")
	Slots.setEntry(npc, { kind = "Npc", rig = "A" })

	local free: number = 4000 -- A slot no one holds
	local sleepers: number, bodies: number = Slots.count("Sleeper"), Slots.count("Body")

	local refusals: { Refusal } = {
		{
			name = "a start with no world",
			call = function ()
				unstarted.start(shared, nil)
			end,
			says = "takes the server's World",
		},
		{
			name = "a second start",
			call = function ()
				Sleepers.start(shared, world)
			end,
			says = "runs once",
		},
		{
			name = "a Player made",
			call = function ()
				Sleepers.create("Player", BED, 0)
			end,
			says = "takes a Sleeper or a Body",
		},
		{
			name = "a position that is no vector",
			call = function ()
				Sleepers.create("Sleeper", 5, 0)
			end,
			says = "as a vector",
		},
		{
			name = "a position past the play bound",
			call = function ()
				Sleepers.create("Body", vector.create(8193, 0, 0), 0)
			end,
			says = "play bound",
		},
		{
			name = "a height that is not finite",
			call = function ()
				Sleepers.create("Sleeper", vector.create(0, NAN, 0), 0)
			end,
			says = "play bound",
		},
		{
			name = "a yaw that is not finite",
			call = function ()
				Sleepers.create("Sleeper", BED, math.huge)
			end,
			says = "finite yaw",
		},
		{
			name = "a body moved",
			call = function ()
				Sleepers.move(body, LOW, 0, TICK)
			end,
			says = "takes a Sleeper's slot, and slot",
		},
		{
			name = "a free slot moved",
			call = function ()
				Sleepers.move(free, LOW, 0, TICK)
			end,
			says = "holds neither",
		},
		{
			name = "a slot past the table moved",
			call = function ()
				Sleepers.move(4096, LOW, 0, TICK)
			end,
			says = "takes a slot from 0 to 4095",
		},
		{
			name = "a move with a yaw that is not finite",
			call = function ()
				Sleepers.move(sleeper, LOW, NAN, TICK)
			end,
			says = "finite yaw",
		},
		{
			name = "a move with a fractional tick",
			call = function ()
				Sleepers.move(sleeper, LOW, 0, TICK + 0.5)
			end,
			says = "whole number",
		},
		{
			name = "a move with a tick below 0",
			call = function ()
				Sleepers.move(sleeper, LOW, 0, -1)
			end,
			says = "whole number",
		},
		{
			name = "a move older than the last",
			call = function ()
				Sleepers.move(sleeper, BED, 0, TICK - 1)
			end,
			says = "whose last move falls from tick 100",
		},
		{
			name = "a body sampled",
			call = function ()
				Sleepers.sampleAt(body, TICK)
			end,
			says = "takes a Sleeper's slot",
		},
		{
			name = "a render time that is not finite",
			call = function ()
				Sleepers.sampleAt(sleeper, NAN)
			end,
			says = "finite number of relay ticks",
		},
		{
			name = "a render time that is no number",
			call = function ()
				Sleepers.sampleAt(sleeper, "soon")
			end,
			says = "finite number of relay ticks",
		},
		{
			name = "a body woken",
			call = function ()
				Sleepers.wake(body, TICK)
			end,
			says = "takes a Sleeper's slot",
		},
		{
			name = "a wake with a fractional tick",
			call = function ()
				Sleepers.wake(sleeper, 2.5)
			end,
			says = "whole number",
		},
		{
			name = "a free slot removed",
			call = function ()
				Sleepers.remove(free)
			end,
			says = "holds neither",
		},
		{
			name = "a slot below the table removed",
			call = function ()
				Sleepers.remove(-1)
			end,
			says = "takes a slot from 0 to 4095",
		},
		{
			name = "a sleep with no state",
			call = function ()
				Sleepers.adopt(free, "awake")
			end,
			says = "takes the character's State",
		},
		{
			name = "a sleep in a slot past the table",
			call = function ()
				Sleepers.adopt(4096, State.new())
			end,
			says = "takes a slot from 0 to 4095",
		},
		{
			name = "a sleep in a slot with no entry",
			call = function ()
				Sleepers.adopt(entryless, State.new())
			end,
			says = "has no entry",
		},
		{
			name = "a sleep in an NPC's slot",
			call = function ()
				Sleepers.adopt(npc, State.new())
			end,
			says = "holds a Npc",
		},
		{
			name = "a sleep in a sleeper's slot",
			call = function ()
				Sleepers.adopt(sleeper, State.new())
			end,
			says = "holds a Sleeper",
		},
	}

	for _, refusal: Refusal in early do
		table.insert(refusals, refusal)
	end

	for _, refusal: Refusal in refusals do
		local ran: boolean, reason: any = pcall(refusal.call)

		if ran then
			return false, `{refusal.name} was not refused`
		elseif not string.find(`{reason}`, refusal.says, 1, true) then
			return false, `{refusal.name} was refused without saying "{refusal.says}": {reason}`
		end
	end

	-- Nothing a refusal touched changed
	local sample: any = Sleepers.sampleAt(sleeper, TICK + 1000)
	if Slots.count("Sleeper") ~= sleepers or Slots.count("Body") ~= bodies then
		return false, `The refusals left {Slots.count("Sleeper")} sleepers and {Slots.count("Body")} bodies held`
	elseif state.position ~= LOW or sample.position ~= LOW or Sleepers.sampleAt(sleeper, TICK - 1).position ~= BED then
		return false, "A refused move changed the sleeper's place or its fall"
	elseif select(2, Slots.get(npc)).kind ~= "Npc" or select(2, Slots.get(entryless)) ~= nil then
		return false, "A refused sleep changed a slot's entry"
	end

	return true, nil
end
