--[[
    The real anti-ESP over seeded slices and walls, serially and on two
    stand-in workers that send its quiet asks back as marks: the same sends,
    asks, rays, export, tap frames, reasons and counts, and the same stop
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/Relay/StandIn")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 2
local TICK_SLACK: number = 1e-9 -- Ticks a slice's time times the rate may fall short of its tick and still be in it
local RATE: number = Environment.load(EXAMPLE).shared().rates.simulation -- The example's ticks a second
local SLOTS: number = 4096 -- Constants.SLOTS
local INVALID_SLOT: number = SLOTS -- A slot the slot table never has, whose viewer's turn throws
local MASK_BITS: number = 16 -- The sequences before the newest a client's acknowledgment covers
local WRAP: number = 2 ^ 16
local MODULUS: number = 2 ^ 31 - 1 -- Park and Miller's generator
local MULTIPLIER: number = 16807
local SEED: number = 20261117
local RTT: number = 0.2 -- Every bot viewer's round trip, inside the example's look-ahead clamp
local BUDGET: number = 1 -- Seconds a slice may take, more than every due test needs
local CENTER: vector = vector.create(-100, 0, 1200)
local SPREAD: number = 160
local STEP: number = 4 -- Studs a body may move along each axis a step
local PLAYERS: number = 12
local STEPS: number = 36
local DELAYS: { number } = { 0.05, 0.1, 0.4 } -- Seconds from one slice to the next, the last past the fail-open time
local SLICE_CHANCE: number = 0.7 -- A step's chance of a slice before its run, so some runs share a round
local STARVED_CHANCE: number = 0.3 -- A slice's chance of no time to test, so hidden pairs go untested and fail open
local STARVED: number = 0
local RED: number = 1
local BLUE: number = 2
local MODERATOR_AT: vector = vector.create(3000, 0, -3000)
local WATCH_FROM: number = 6
local WATCH_UNTIL: number = 26
local THROW_AT: number = 5 -- The thrower's place in the last step's list, with viewers of both workers after it
local WALLED_FROM: number = 8 -- Every ray blocked these steps, past the hold, so pairs turn hidden and get withheld
local WALLED_UNTIL: number = 22

-- What a wall answers: no ray blocked, every ray blocked, or some by where they end
local OPEN: number = 0
local SOLID: number = 1
local PATTERNS: number = 4 -- The modes a step picks from, the last two both the pattern
local OFFSETS: number = 5

type Generator = () -> number

-- A client that reads every block it is sent
type Client = {
	newest: number,
	received: { [number]: boolean },
}

-- One relay with anti-ESP in an environment of its own, and what it sent, asked and tapped this step, in order
type Side = {
	Relay: any,
	AntiEsp: any,
	Slots: any,
	Taps: any,
	Connections: any,
	State: any,
	states: { [number]: any },
	viewers: { any },
	byName: { [string]: any },
	pool: any,
	log: { string },
	frames: { string },
	rays: { vector }, -- Each ray's origin and direction this step, in turn
	clients: { [any]: Client },
}

local Names: { [any]: string } = {}

local function generator(seed: number): Generator
	local value: number = seed

	return function (): number
		value = value * MULTIPLIER % MODULUS

		return value / MODULUS
	end
end

local function label(keys: { any }): string
	local names: { string } = {}
	for index: number, key: any in keys do
		names[index] = Names[key] or "?"
	end

	return table.concat(names, ",")
end

local function compare(what: string, serial: { string }, workers: { string }): string?
	for index: number = 1, math.max(#serial, #workers) do
		if serial[index] ~= workers[index] then
			local expected: string = (serial[index] or "nothing"):sub(1, 60)
			local got: string = (workers[index] or "nothing"):sub(1, 60)

			return `{what} {index} was "{expected}" serially and "{got}" on the workers`
		end
	end

	return nil
end

--[[
    The workers' log as serial's log gives it: in each viewer's run of asks,
    those the workers marked taken out and put back after the run's other
    asks as marks, in the same order, and every other line as it is
--]]

local function withMarks(serial: { string }, workers: { string }): { string }
	local marked: { [string]: boolean } = {}
	for _, line: string in workers do
		local name: string?, slot: string? = string.match(line, "^mark (%S+) (%d+)$")
		if name then
			marked[`{name} {slot}`] = true
		end
	end

	local expected: { string } = {}
	local held: { string } = {}
	local asker: string? = nil

	for _, line: string in serial do
		local name: string?, slot: string? = string.match(line, "^ask (%S+) (%d+) ")
		if name ~= asker then
			table.move(held, 1, #held, #expected + 1, expected)
			table.clear(held)
			asker = name
		end

		if name and marked[`{name} {slot}`] then
			table.insert(held, `mark {name} {slot}`)
		else
			table.insert(expected, line)
		end
	end

	table.move(held, 1, #held, #expected + 1, expected)

	return expected
end

-- The answers' four buffers as one string, to tell whether two exports are the same
local function bytesOf(answers: any): string
	local kinds: string, teams: string = buffer.tostring(answers.kinds), buffer.tostring(answers.teams)

	return `{kinds}{teams}{buffer.tostring(answers.visible)}{buffer.tostring(answers.quiet)}`
end

return function (): (boolean, string | nil)
	local random: Generator = generator(SEED)
	local mode: number = OPEN
	local offset: number = 0

	local function wall(origin: vector, direction: vector): boolean
		if mode == OPEN then
			return false
		elseif mode == SOLID then
			return true
		end

		local finish: vector = origin + direction

		return (math.floor(finish.x) + math.floor(finish.y * 4) + math.floor(finish.z) + offset) % OFFSETS ~= 0
	end

	-- A relay and anti-ESP started on the example's tables, with that many workers in a stand-in pool when given
	local function side(workers: number?): Side
		local made: { [string]: any } = {}
		function made.new(count: number, name: string, remote: any, settings: any): any
			made.made = StandIn.new(count, name, remote, settings)

			return made.made
		end

		local globals: any = Environment.load(GLOBALS, { [POOL] = made })
		local game: any = globals.game
		local tread: any = game:GetService("ReplicatedStorage").Packages.Tread
		local require: any = globals.require
		local Example: any = require(game:GetService("ServerScriptService").Fixtures.Config.Example)

		local built: Side = {
			Relay = require(tread.Server.Relay),
			AntiEsp = require(tread.Server.AntiEsp),
			Slots = require(tread.Server.Slots),
			Taps = require(tread.Server.Taps),
			Connections = require(tread.Server.Connections),
			State = require(tread.Step.State),
			states = {},
			viewers = {},
			byName = {},
			pool = nil,
			log = {},
			frames = {},
			rays = {},
			clients = {},
		}

		local shared: any = Example.shared()
		local server: any = Example.server()
		server.bots = { rtt = RTT }
		server.antiEsp.lyingShare = BUDGET -- The whole slice, so its sleepers go first and its rays in one order
		if workers then
			server.relay.workers = workers
		end

		local Engine: any = require(tread.Step.Engine)
		local World: any = require(tread.Step.World)
		local Sequence: any = require(tread.Codec.Sequence)
		local layout: any = require(tread.Codec.Fields).compile(shared.fields)

		built.Slots.start(server.slots.reserve)
		built.Connections.start(server.rewind.rttSmoothing, server.bots)

		local world: any = World.new(
			shared.step,
			shared.rates.simulation,
			Engine.casts(shared.collision),
			shared.water,
			shared.rules,
			true
		)
		built.AntiEsp.start(
			{ shared = shared, server = server },
			world,
			built.states,
			function (origin: vector, direction: vector): boolean
				table.insert(built.rays, origin)
				table.insert(built.rays, direction)

				return wall(origin, direction)
			end
		)

		local function send(keys: { any }, data: buffer)
			table.insert(built.log, `block {label(keys)} {buffer.tostring(data)}`)

			local sequence: number = buffer.readu16(data, 0)
			for _, key: any in keys do
				local client: Client = built.clients[key]
				client.received[sequence] = true
				if client.newest == 0 or Sequence.difference(sequence, client.newest) > 0 then
					client.newest = sequence
				end
			end
		end

		local function sendWithheld(keys: { any }, data: buffer)
			table.insert(built.log, `withheld {label(keys)} {buffer.tostring(data)}`)
		end

		local function isHidden(viewer: any, slot: number): boolean
			local hidden: boolean = built.AntiEsp.isHidden(viewer, slot)
			table.insert(built.log, `ask {Names[viewer.key]} {slot} {hidden}`)

			return hidden
		end

		-- Each mark the workers hand in, logged at its call, before anti-ESP stamps its pair
		local function asked(viewer: any, slots: { number }, count: number)
			for index: number = 1, count do
				table.insert(built.log, `mark {Names[viewer.key]} {slots[index]}`)
			end

			built.AntiEsp.asked(viewer, slots, count)
		end

		local function traffic(_: any): number
			return 0
		end

		built.Relay.start(
			{ shared = shared, server = server, layout = layout },
			send,
			sendWithheld,
			traffic,
			isHidden,
			built.AntiEsp.answers,
			asked
		)
		built.Taps.start({ layout = layout, wearing = built.Relay.wearing, reason = built.AntiEsp.reason })
		built.pool = made.made

		return built
	end

	local serial: Side = side(nil)
	local workers: Side = side(WORKERS)
	local sides: { Side } = { serial, workers }

	-- A body of a kind resting on the ground on both sides, in the same slot
	local function spawn(kind: string, at: vector): number
		local slot: number = serial.Slots.take(kind)
		if workers.Slots.take(kind) ~= slot then
			error("The two slot tables gave a body different slots")
		end

		local facing: number = random() * 2 * math.pi
		for _, built: Side in sides do
			built.Slots.setEntry(slot, { kind = kind, rig = "A" })

			local state: any = built.State.new()
			state.position = at
			state.facing = facing
			state.mode = "Ground"
			state.grounded = true
			state.groundMaterial = roblox.Enum.Material.Grass
			built.states[slot] = state
		end

		return slot
	end

	-- A bot viewer on both sides with the same key, at a place in the list, with a body when owned
	local function join(name: string, at: vector, owned: boolean, place: number?): any
		local key: { Name: string } = { Name = name }
		Names[key] = name

		local slot: number? = nil
		if owned then
			slot = spawn("Player", at)
		end

		for _, built: Side in sides do
			built.Connections.add(key)
			built.clients[key] = { newest = 0, received = {} }

			local viewer: any =
				{ key = key, slot = slot, position = at, acknowledged = 0, received = 0, target = nil, look = nil }
			built.byName[name] = viewer
			table.insert(built.viewers, place or #built.viewers + 1, viewer)
		end

		return key
	end

	for index: number = 1, PLAYERS do
		join(`Player{index}`, CENTER + vector.create((random() - 0.5) * SPREAD, 0, (random() - 0.5) * SPREAD), true)
	end

	join("Moderator", MODERATOR_AT, false)
	spawn("Npc", CENTER + vector.create(15, 0, 0))
	spawn("Sleeper", CENTER + vector.create(-20, 0, 10))
	spawn("Body", CENTER + vector.create(0, 0, -25))

	for _, built: Side in sides do
		built.AntiEsp.setTeam(built.byName.Player1.slot, RED)
		built.AntiEsp.setTeam(built.byName.Player2.slot, RED)
		built.AntiEsp.setTeam(built.byName.Player3.slot, BLUE)
		built.AntiEsp.setTeam(built.byName.Player4.slot, BLUE)

		local function sink(_: number, data: buffer)
			table.insert(built.frames, buffer.tostring(data))
		end

		built.Taps.observe(built.byName.Player2.key, sink)
		built.Taps.observe(built.byName.Moderator.key, sink)
		built.Taps.observeWithheld(built.byName.Player2.key, sink)
	end

	local now: number = 0
	local top: number = serial.byName[`Player{PLAYERS}`].slot + 3
	local reached: { [string]: number } = { asks = 0, hidden = 0, withheld = 0, frames = 0, marks = 0, rays = 0 }

	for step: number = 1, STEPS + 1 do
		local throwing: boolean = step > STEPS
		if throwing then
			join("Thrower", CENTER, false, THROW_AT)
			for _, built: Side in sides do
				built.byName.Thrower.slot = INVALID_SLOT
			end
		elseif step == WATCH_FROM then
			for _, built: Side in sides do
				built.byName.Moderator.target = built.byName.Player2.key
			end
		elseif step == WATCH_UNTIL then
			for _, built: Side in sides do
				built.byName.Moderator.target = nil
			end
		end

		-- Every player moves alike on both sides, its viewer standing where it does
		local moves: { [number]: vector } = {}
		for slot: number in serial.states do
			local _, entry: any = serial.Slots.get(slot)
			if entry and entry.kind == "Player" then
				moves[slot] = vector.create((random() - 0.5) * 2 * STEP, 0, (random() - 0.5) * 2 * STEP)
			end
		end

		for _, built: Side in sides do
			for slot: number, move: vector in moves do
				built.states[slot].position += move
				built.AntiEsp.moved(slot)
			end

			for _, viewer: any in built.viewers do
				local slot: number? = viewer.slot
				if slot ~= nil and built.states[slot] then
					viewer.position = built.states[slot].position
				end
			end

			built.log = {}
			built.frames = {}
			built.rays = {}
		end

		-- Walls and a slice, alike on both sides, or none so two runs share a round
		mode = math.floor(random() * PATTERNS)
		offset = math.floor(random() * OFFSETS)
		if step >= WALLED_FROM and step <= WALLED_UNTIL then
			mode = SOLID
		end
		-- The walls' last step starves its slice past the fail-open time, so the hidden pairs fail open
		if random() < SLICE_CHANCE or step == WALLED_UNTIL then
			now += DELAYS[math.floor(random() * #DELAYS) + 1]

			local budget: number = BUDGET
			if random() < STARVED_CHANCE then
				budget = STARVED
			end

			if step == WALLED_UNTIL then
				now += DELAYS[#DELAYS]
				budget = STARVED
			end

			-- On the simulation tick its time falls in, which a near hidden pair's recheck waits for
			local tick: number = math.floor(now * RATE + TICK_SLACK)
			for _, built: Side in sides do
				built.AntiEsp.run(budget, now, tick)
			end
		end

		local serialRan: boolean, serialError: any = pcall(serial.Relay.run, step, serial.viewers, serial.states, {})

		local workersRan: boolean, workersError: any =
			pcall(workers.Relay.run, step, workers.viewers, workers.states, {})
		if workersRan then
			workers.AntiEsp.hold()
			workers.pool:deliver()
			workersRan, workersError = pcall(workers.Relay.finish)
			workers.AntiEsp.release()
		end

		for _, built: Side in sides do
			if built.Taps.observing then
				built.Taps.finish(step)
			end
		end

		local why: string? = compare(`Step {step}'s send, ask or mark`, withMarks(serial.log, workers.log), workers.log)
			or compare(`Step {step}'s frame`, serial.frames, workers.frames)
		if why ~= nil then
			return false, why
		elseif serialRan ~= workersRan or (not serialRan and `{serialError}` ~= `{workersError}`) then
			return false, `Step {step} ended "{serialError}" serially and "{workersError}" on the workers`
		elseif throwing then
			if serialRan or not string.find(`{serialError}`, "not 4096", 1, true) then
				return false, `The thrower's step ended "{serialError}" serially`
			end

			break
		elseif not serialRan then
			return false, `Step {step} threw: {serialError}`
		end

		local tests: number, hidden: number, failOpens: number = serial.AntiEsp.counts()
		local workerTests: number, workerHidden: number, workerFailOpens: number = workers.AntiEsp.counts()
		if tests ~= workerTests or hidden ~= workerHidden or failOpens ~= workerFailOpens then
			return false,
				`Step {step}'s counts were {tests}, {hidden}, {failOpens} serially and {workerTests}, {workerHidden}, {workerFailOpens} on the workers`
		end

		local lying: number, waiting: number = serial.AntiEsp.lying()
		local workerLying: number, workerWaiting: number = workers.AntiEsp.lying()
		if lying ~= workerLying or waiting ~= workerWaiting then
			return false,
				`Step {step}'s lying counts were {lying}, {waiting} serially and {workerLying}, {workerWaiting} on the workers`
		elseif #serial.rays ~= #workers.rays then
			return false, `Step {step} cast {#serial.rays // 2} rays serially and {#workers.rays // 2} on the workers`
		end

		for index: number, ray: vector in serial.rays do
			if workers.rays[index] ~= ray then
				return false, `Step {step}'s ray {(index + 1) // 2} differed on the workers`
			end
		end

		if bytesOf(serial.AntiEsp.answers(serial.viewers)) ~= bytesOf(workers.AntiEsp.answers(workers.viewers)) then
			return false, `Step {step} left anti-ESP's export otherwise on the workers`
		end

		for index: number, viewer: any in serial.viewers do
			for slot: number = 0, top do
				local reason: string = serial.AntiEsp.reason(viewer.key, slot)
				if reason ~= workers.AntiEsp.reason(workers.viewers[index].key, slot) then
					return false, `Step {step}: {Names[viewer.key]}'s reason for slot {slot} differs`
				end
			end
		end

		for _, line: string in serial.log do
			if string.sub(line, 1, 3) == "ask" then
				reached.asks += 1
				if string.sub(line, -4) == "true" then
					reached.hidden += 1
				end
			elseif string.sub(line, 1, 8) == "withheld" then
				reached.withheld += 1
			end
		end

		reached.frames += #serial.frames
		reached.rays += #serial.rays // 2
		for _, line: string in workers.log do
			if string.sub(line, 1, 4) == "mark" then
				reached.marks += 1
			end
		end

		-- Each client's acknowledgment of everything it read, which both sides take in the next run
		for _, built: Side in sides do
			for _, viewer: any in built.viewers do
				local client: Client = built.clients[viewer.key]
				local mask: number = 0
				for back: number = 1, MASK_BITS do
					if client.received[(client.newest - back) % WRAP] then
						mask += 2 ^ (back - 1)
					end
				end

				viewer.acknowledged = client.newest
				viewer.received = mask
			end
		end
	end

	for name: string, count: number in reached do
		if count == 0 then
			return false, `No step reached any {name}`
		end
	end

	local tests: number, _, failOpens: number = serial.AntiEsp.counts()
	if tests == 0 or failOpens == 0 then
		return false, `The slices ran {tests} tests and {failOpens} fail-opens`
	end

	return true, nil
end
