--[[
    Relay.start's asked port, required as answers is, then the real anti-ESP
    under three relays, serial, on workers marking quiet asks and on workers
    with every quiet row emptied: each step, the marking side ends as the last
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/Relay/StandIn")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 2
local FAILING: number = 2 -- The worker whose run the planted failure throws in
local SLOTS: number = 4096 -- Constants.SLOTS
local ROW_BYTES: number = SLOTS // 8
local INVALID_SLOT: number = SLOTS -- A slot the slot table never has, whose viewer's turn throws
local MASK_BITS: number = 16 -- The sequences before the newest a client's acknowledgment covers
local WRAP: number = 2 ^ 16
local MODULUS: number = 2 ^ 31 - 1 -- Park and Miller's generator
local MULTIPLIER: number = 16807
local SEED: number = 20261118
local RTT: number = 0.2 -- Every bot viewer's round trip, inside the example's look-ahead clamp
local BUDGET: number = 1 -- Seconds a slice may take, more than every due test needs
local CENTER: vector = vector.create(600, 0, -900)
local SPREAD: number = 150
local STEP: number = 4 -- Studs a body may move along each axis a step
local PLAYERS: number = 10
local DELAYS: { number } = { 0.05, 0.1, 0.4 } -- Seconds from one slice to the next, the last past the fail-open time
local SLICE_CHANCE: number = 0.7 -- A step's chance of a slice before its run, so some runs share a round
local STARVED_CHANCE: number = 0.3 -- A slice's chance of no time to test, so hidden pairs go untested and fail open
local STARVED: number = 0
local RED: number = 1
local BLUE: number = 2
local NEAR: number = 60 -- The render distance a call in a window sets
local MODERATOR_AT: vector = vector.create(3600, 0, 2600)
local THROW_AT: number = 4 -- The thrower's place in the list, with viewers of both workers after it
local NOT_A_PORT: number = 5 -- An asked port that is no function, which a relay with no workers ignores

-- The steps each path is taken in, as their names say. Up to MIXED every path keeps serial's order, so the emptied
-- side must match serial there, and from MIXED on a path may leave the workers apart from serial
local STEPS: number = 34
local WATCH_FROM: number = 3
local TEAM_STEP: number = 5 -- A player with pairs joins a team inside the window, so its pairs turn teammates'
local WINDOW_STEP: number = 7 -- A move and the relay's calls inside the window
local LEAVE_STEP: number = 9 -- A viewer leaves inside the window, and is handed in again the step after
local LATE_STEP: number = 11 -- A viewer's first run, on a worker
local WATCH_UNTIL: number = 12
local UNTEAM_STEP: number = 14
local WALLED_FROM: number = 6 -- Every ray blocked these steps, past the hold, so pairs turn hidden and get withheld
local WALLED_UNTIL: number = 15
local MIXED_STEP: number = 18 -- A view made in process, so every run from here is mixed
local THROW_STEP: number = 21 -- A turn that throws, its viewer gone the step after
local FAIL_STEP: number = 24 -- A worker's run throws
local DROP_STEP: number = 27 -- The round lands and is given up anyway
local LATE_DROP_STEP: number = 30 -- The round is given up and lands with the next

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

-- One relay with anti-ESP in an environment of its own, and what it sent, asked, marked, cast and tapped this step
type Side = {
	name: string,
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
	failure: string, -- What the step's run or finish threw, empty for nothing
	lyingTests: number, -- What AntiEsp.lying gave after the step, read once since it counts from its last call
	lyingWaiting: number,
	unexport: () -> (), -- Forgets the marking side's last export, so an in-process turn's asks are never read by it
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

local function compare(what: string, first: { string }, second: { string }): string?
	for index: number = 1, math.max(#first, #second) do
		if first[index] ~= second[index] then
			local expected: string = (first[index] or "nothing"):sub(1, 60)
			local got: string = (second[index] or "nothing"):sub(1, 60)

			return `{what} {index} was "{expected}" against "{got}"`
		end
	end

	return nil
end

--[[
    A side's log as another's gives it: in each viewer's run of asks, those
    the side marked taken out and put back after the run's other asks as
    marks, in the same order, and every other line as it is
--]]

local function withMarks(reference: { string }, marking: { string }): { string }
	local marked: { [string]: boolean } = {}
	for _, line: string in marking do
		local name: string?, slot: string? = string.match(line, "^mark (%S+) (%d+)$")
		if name then
			marked[`{name} {slot}`] = true
		end
	end

	local expected: { string } = {}
	local held: { string } = {}
	local asker: string? = nil

	for _, line: string in reference do
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

--[[
    The first way two sides' step differs, the second side's log read as
    the first's with the second's marks put back, or nil: sends, asks and
    marks, frames, what threw, rays, anti-ESP's export, reasons and counts,
    and the relay's counts, keyframes and sends by key
--]]

local function differs(first: Side, second: Side, everyone: { any }, top: number): string?
	local why: string? = compare("send, ask or mark", withMarks(first.log, second.log), second.log)
		or compare("frame", first.frames, second.frames)
	if why then
		return why
	elseif first.failure ~= second.failure then
		return `the step ended "{first.failure}" against "{second.failure}"`
	elseif #first.rays ~= #second.rays then
		return `{#first.rays // 2} rays were cast against {#second.rays // 2}`
	end

	for index: number, ray: vector in first.rays do
		if second.rays[index] ~= ray then
			return `ray {(index + 1) // 2} differed`
		end
	end

	if bytesOf(first.AntiEsp.answers(first.viewers)) ~= bytesOf(second.AntiEsp.answers(second.viewers)) then
		return "anti-ESP's export differed"
	end

	local tests: number, hidden: number, failOpens: number = first.AntiEsp.counts()
	local otherTests: number, otherHidden: number, otherFailOpens: number = second.AntiEsp.counts()
	if tests ~= otherTests or hidden ~= otherHidden or failOpens ~= otherFailOpens then
		return `anti-ESP's counts were {tests}, {hidden}, {failOpens} against {otherTests}, {otherHidden}, {otherFailOpens}`
	elseif first.lyingTests ~= second.lyingTests or first.lyingWaiting ~= second.lyingWaiting then
		local lying: string = `{first.lyingTests}, {first.lyingWaiting}`

		return `the lying counts were {lying} against {second.lyingTests}, {second.lyingWaiting}`
	end

	local sent: number, cut: number, visited: number = first.Relay.counts()
	local otherSent: number, otherCut: number, otherVisited: number = second.Relay.counts()
	if sent ~= otherSent or cut ~= otherCut or visited ~= otherVisited then
		return `the relay's counts were {sent}, {cut}, {visited} against {otherSent}, {otherCut}, {otherVisited}`
	end

	for _, key: any in everyone do
		if buffer.tostring(first.Relay.keyframe(key)) ~= buffer.tostring(second.Relay.keyframe(key)) then
			return `{Names[key]}'s keyframe differed`
		end

		for slot: number = 0, top do
			if first.AntiEsp.reason(key, slot) ~= second.AntiEsp.reason(key, slot) then
				return `{Names[key]}'s reason for slot {slot} differed`
			elseif first.Relay.isSent(key, slot) ~= second.Relay.isSent(key, slot) then
				return `{Names[key]}'s isSent for slot {slot} differed`
			end
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	-- 1) The asked port: refused while relay.workers is above 0 unless it is a function, and ignored at 0
	for _, workers: number in { WORKERS, 0 } do
		local globals: any = Environment.load(GLOBALS)
		local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
		local Example: any = globals.require(globals.game:GetService("ServerScriptService").Fixtures.Config.Example)
		local shared: any = Example.shared()
		local server: any = Example.server()
		server.relay.workers = workers

		local function nothing(): any
			return false
		end

		local asked: any = nil
		if workers == 0 then
			asked = NOT_A_PORT
		end

		local settings: any = {
			shared = shared,
			server = server,
			layout = globals.require(tread.Codec.Fields).compile(shared.fields),
		}
		local start: any = globals.require(tread.Server.Relay).start
		local started: boolean, refusal: any =
			pcall(start, settings, nothing, nothing, nothing, nothing, nothing, asked)

		if workers > 0 and (started or not string.find(`{refusal}`, "asked as a function", 1, true)) then
			return false, `Relay.start with workers and no asked port gave {started} {refusal}`
		elseif workers == 0 and not started then
			return false, `Relay.start with no workers refused an asked port that is no function: {refusal}`
		end
	end

	-- 2) The three relays, through each path a round takes
	local random: Generator = generator(SEED)
	local mode: number = OPEN
	local offset: number = 0
	local corrupt: boolean = false

	local function wall(origin: vector, direction: vector): boolean
		if mode == OPEN then
			return false
		elseif mode == SOLID then
			return true
		end

		local finish: vector = origin + direction

		return (math.floor(finish.x) + math.floor(finish.y * 4) + math.floor(finish.z) + offset) % OFFSETS ~= 0
	end

	-- What the marking side reached: its marks, and its asks whose quiet bit was set, each a teammate's
	local reached: { [string]: number } = { marks = 0, quietTeammates = 0, leaverMarks = 0 }
	local problem: string? = nil

	--[[
	    A relay and anti-ESP started on the example's tables: serially, or
	    on workers in a stand-in pool whose failing worker is handed an own
	    hand-in too short to read while corrupt is on, either marking quiet
	    asks or with every quiet row emptied
	--]]

	local function side(name: string, workers: number?, emptied: boolean?): Side
		local made: { [string]: any } = {}
		function made.new(count: number, poolName: string, remote: any, settings: any): any
			local inner: any = StandIn.new(count, poolName, remote, settings)
			local send: any = inner.send

			inner.send = function (self: any, worker: number, round: number, shared: buffer, own: buffer)
				if corrupt and worker == FAILING then
					own = buffer.create(0)
				end

				send(self, worker, round, shared, own)
			end

			made.made = inner

			return inner
		end

		local globals: any = Environment.load(GLOBALS, { [POOL] = made })
		local game: any = globals.game
		local tread: any = game:GetService("ReplicatedStorage").Packages.Tread
		local require: any = globals.require
		local Example: any = require(game:GetService("ServerScriptService").Fixtures.Config.Example)

		-- The marking side's last export, its quiet rows and each viewer's row, while its round's asks are replayed
		local quiet: buffer? = nil
		local rows: { [any]: number } = {}

		local function unexport()
			quiet = nil
			table.clear(rows)
		end

		local built: Side = {
			name = name,
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
			failure = "",
			lyingTests = 0,
			lyingWaiting = 0,
			unexport = unexport,
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

		local function answers(list: { any }): any
			local taken: any = built.AntiEsp.answers(list)
			if emptied then
				return {
					kinds = taken.kinds,
					teams = taken.teams,
					visible = taken.visible,
					quiet = buffer.create(#list * ROW_BYTES),
				}
			end

			quiet = buffer.fromstring(buffer.tostring(taken.quiet))
			table.clear(rows)
			for index: number, viewer: any in list do
				rows[viewer.key] = (index - 1) * ROW_BYTES
			end

			return taken
		end

		-- An ask the marking side's workers sent as an ask though its quiet bit was set must be a teammate's
		local function isHidden(viewer: any, slot: number): boolean
			local hidden: boolean = built.AntiEsp.isHidden(viewer, slot)
			table.insert(built.log, `ask {Names[viewer.key]} {slot} {hidden}`)

			local row: number? = rows[viewer.key]
			if quiet and row ~= nil then
				local at: number = row + slot // 8
				if bit32.btest(buffer.readu8(quiet, at), bit32.lshift(1, slot % 8)) then
					if built.AntiEsp.reason(viewer.key, slot) == "Teammate" then
						reached.quietTeammates += 1
					elseif problem == nil then
						problem = `{Names[viewer.key]}'s quiet ask about slot {slot} came back as an ask`
					end
				end
			end

			return hidden
		end

		local function asked(viewer: any, slots: { number }, count: number)
			if emptied or not workers then
				error(`The {name} side was handed a mark`)
			end

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
			answers,
			asked
		)
		built.Taps.start({ layout = layout, wearing = built.Relay.wearing, reason = built.AntiEsp.reason })
		built.pool = made.made

		return built
	end

	local serial: Side = side("serial", nil, nil)
	local marking: Side = side("marking", WORKERS, false)
	local emptied: Side = side("emptied", WORKERS, true)
	local sides: { Side } = { serial, marking, emptied }
	local onWorkers: { Side } = { marking, emptied }
	local everyone: { any } = {}

	-- A body of a kind resting on the ground on every side, in the same slot
	local function spawn(kind: string, at: vector): number
		local slot: number = serial.Slots.take(kind)
		local facing: number = random() * 2 * math.pi

		for _, built: Side in sides do
			if built ~= serial and built.Slots.take(kind) ~= slot then
				error("The slot tables gave a body different slots")
			end

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

	-- A bot viewer on every side with the same key, at a place in the list, with a body when owned
	local function join(name: string, at: vector, owned: boolean, place: number?): any
		local key: { Name: string } = { Name = name }
		Names[key] = name
		table.insert(everyone, key)

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

	-- What a step's window holds on a side: anti-ESP's mutators and the relay's calls, queued while a round is out
	local function window(built: Side, step: number)
		local byName: { [string]: any } = built.byName
		if step == TEAM_STEP then
			built.AntiEsp.setTeam(byName.Player5.slot, RED)
		elseif step == UNTEAM_STEP then
			built.AntiEsp.setTeam(byName.Player5.slot, nil)
		elseif step == WINDOW_STEP then
			built.AntiEsp.moved(byName.Player6.slot)
			built.Relay.reveal(byName.Player6.slot)
			built.Relay.setDistance(byName.Player3.key, NEAR)
			built.Relay.shotNear(byName.Player4.key, byName.Player6.slot)
		elseif step == LEAVE_STEP then
			built.AntiEsp.leave(byName.Player7.key)
			built.Relay.remove(byName.Player7.key)
		end
	end

	local now: number = 0
	local top: number = 0
	local paths: { [string]: boolean } = {}

	for step: number = 1, STEPS do
		-- The viewers each path adds or takes out before the run, alike on every side
		if step == LEAVE_STEP + 1 then
			for _, built: Side in sides do
				local viewer: any = built.byName.Player7
				built.clients[viewer.key] = { newest = 0, received = {} }
				viewer.acknowledged = 0
				viewer.received = 0
				table.insert(built.viewers, viewer)
			end
		elseif step == LATE_STEP then
			join("Late", CENTER + vector.create(30, 0, 30), true)
		elseif step == MIXED_STEP then
			for _, built: Side in onWorkers do
				built.Relay.useWorkers(false)
			end

			join("Local", CENTER + vector.create(-30, 0, -30), true)
		elseif step == THROW_STEP then
			join("Thrower", CENTER, false, THROW_AT)
			for _, built: Side in sides do
				built.byName.Thrower.slot = INVALID_SLOT
			end
		elseif step == THROW_STEP + 1 then
			for _, built: Side in sides do
				local viewer: any = built.byName.Thrower
				table.remove(built.viewers, table.find(built.viewers, viewer))
				built.Relay.remove(viewer.key)
			end
		end

		if step == WATCH_FROM or step == WATCH_UNTIL then
			for _, built: Side in sides do
				built.byName.Moderator.target = step == WATCH_FROM and built.byName.Player2.key or nil
			end
		end

		-- Every player moves alike on every side, its viewer standing where it does
		local moves: { [number]: vector } = {}
		for slot: number in serial.states do
			local _, entry: any = serial.Slots.get(slot)
			top = math.max(top, slot)
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
			built.failure = ""
			built.unexport()
		end

		-- Walls and a slice, alike on every side, or none so two runs share a round
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

			for _, built: Side in sides do
				built.AntiEsp.run(budget, now)
			end
		end

		-- The serial run, then its window's calls as calls made after it
		local ran: boolean, thrown: any = pcall(serial.Relay.run, step, serial.viewers, serial.states, {})
		if not ran then
			serial.failure = `{thrown}`
		end

		window(serial, step)

		-- Each worker side's run, its window's calls queued while its round is out, then its finish or its drop
		corrupt = step == FAIL_STEP
		for _, built: Side in onWorkers do
			ran, thrown = pcall(built.Relay.run, step, built.viewers, built.states, {})
			if ran then
				built.AntiEsp.hold()
				window(built, step)

				if step == DROP_STEP then
					built.pool:deliver()
					built.Relay.drop()
				elseif step == LATE_DROP_STEP then
					built.Relay.drop()
				else
					built.pool:deliver()
					ran, thrown = pcall(built.Relay.finish)
					if ran and thrown ~= true then
						thrown = "its round was still out after its delivery"
						ran = false
					end
				end

				built.AntiEsp.release()
			else
				window(built, step)
			end

			if not ran then
				built.failure = `{thrown}`
			end
		end

		corrupt = false
		if step == MIXED_STEP then
			for _, built: Side in onWorkers do
				built.Relay.useWorkers(true)
			end
		elseif step == LEAVE_STEP then
			for _, built: Side in sides do
				table.remove(built.viewers, table.find(built.viewers, built.byName.Player7))
			end
		end

		for _, built: Side in sides do
			if built.Taps.observing then
				built.Taps.finish(step)
			end

			local lyingTests: number, lyingWaiting: number = built.AntiEsp.lying()
			built.lyingTests = lyingTests
			built.lyingWaiting = lyingWaiting
		end

		-- The marking side against the emptied one on everything, and against serial wherever the emptied side matches
		local why: string? = differs(emptied, marking, everyone, top)
		if why ~= nil then
			return false, `Step {step}: the marking side against the emptied one: {why}`
		elseif problem ~= nil then
			return false, `Step {step}: {problem}`
		end

		local apart: string? = differs(serial, emptied, everyone, top)
		if apart == nil then
			why = differs(serial, marking, everyone, top)
			if why ~= nil then
				return false, `Step {step}: the marking side against serial: {why}`
			end
		elseif step < MIXED_STEP then
			return false, `Step {step}: the emptied side against serial, before any path that may part them: {apart}`
		end

		-- What each path reached on the marking side
		for _, line: string in marking.log do
			if string.sub(line, 1, 4) == "mark" then
				reached.marks += 1
				if step == LEAVE_STEP and string.find(line, "Player7", 1, true) then
					reached.leaverMarks += 1
				end
			end
		end

		if step == THROW_STEP and string.find(marking.failure, "not 4096", 1, true) then
			paths.thrown = true
		elseif step == FAIL_STEP and string.find(marking.failure, "out of bounds", 1, true) then
			paths.failed = true
		elseif step == DROP_STEP or step == LATE_DROP_STEP then
			-- A round given up hands in nothing, though its in-process turns ask at its dispatch
			for _, line: string in marking.log do
				if string.sub(line, 1, 4) == "mark" then
					return false, `Step {step}: the round given up handed anti-ESP a mark`
				end
			end

			paths[`dropped {step}`] = true
		end

		-- Each client's acknowledgment of everything it read, which every side takes in the next run
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

	-- Every path was taken, and the marks were used through them
	for _, path: string in { "thrown", "failed", `dropped {DROP_STEP}`, `dropped {LATE_DROP_STEP}` } do
		if not paths[path] then
			return false, `The {path} path wasn't reached as planned`
		end
	end

	for name: string, count: number in reached do
		if count == 0 then
			return false, `The marking side reached no {name}`
		end
	end

	local tests: number, _, failOpens: number = marking.AntiEsp.counts()
	local homes: number, views: { number } = marking.Relay.homes()
	if tests == 0 or failOpens == 0 then
		return false, `The slices ran {tests} tests and {failOpens} fail-opens`
	elseif homes == 0 or views[1] == 0 or views[2] == 0 then
		return false, `The marking side held {homes} views in process and {views[1]} and {views[2]} on its workers`
	end

	return true, nil
end
