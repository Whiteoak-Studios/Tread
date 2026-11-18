--[[
    The relay's own check: seeded layouts run through two private copies of
    the relay, one serial and one on workers, every send, withheld send, ask,
    tap frame and query compared byte for byte after each run
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ServerScriptService.Server.Config.RelayCheck)

local LAYOUTS: { [string]: Config.Layout } = require(ServerScriptService.Server.Config.RelayCheck).layouts
local SCHEDULE: { Config.Event } = require(ServerScriptService.Server.Config.RelayCheck).schedule
local LISTED: number = require(ServerScriptService.Server.Config.RelayCheck).listed
local BUSY: number = require(ServerScriptService.Server.Config.RelayCheck).busy
local NEAR: number = require(ServerScriptService.Server.Config.RelayCheck).near
local FAR: number = require(ServerScriptService.Server.Config.RelayCheck).far
local OBSERVED: number = require(ServerScriptService.Server.Config.RelayCheck).observed
local READY: number = require(ServerScriptService.Server.Config.RelayCheck).ready
local LOOK: { [string]: number } = require(ServerScriptService.Server.Config.RelayCheck).look
local OTHER_LOOK: { [string]: number } = require(ServerScriptService.Server.Config.RelayCheck).otherLook
local HELD: { [string]: number } = require(ServerScriptService.Server.Config.RelayCheck).held

local MODULUS: number = 2 ^ 31 - 1 -- Park and Miller's generator, whose products stay exact in a double
local MULTIPLIER: number = 16807
local WRAP: number = 2 ^ 16 -- The values a block's u16 sequence wraps through
local MASK_BITS: number = 16 -- The sequences before the newest a client's acknowledgment covers
local BITS: number = 8 -- A byte's, each one slot's answer in a viewer's row of anti-ESP's answers
local ALL_SHOWN: number = 255 -- A row's byte with every slot's bit set
local LYING: number = 2 -- Anti-ESP's kind for a sleeper or body, whose answer a worker reads from its bit alone
local JUMPS: number = 4 -- The values a state's jump counter wraps through
local TURN: number = 2 * math.pi
local MODERATOR: string = "Moderator"
local WITHHELD: string = "withheld" -- After a viewer's name, its withheld sink's
local SEPARATOR: string = "; "

-- The events that are calls into the relay, made in the window after their run; the rest come before theirs
local CALLS: { [string]: boolean } = {
	look = true,
	otherLook = true,
	invisible = true,
	visible = true,
	reveal = true,
	shotNear = true,
	near = true,
	far = true,
	revealAll = true,
	leave = true,
}

type Key = { Name: string }
type Generator = () -> number

-- One copy of the relay as the check drives it, its modules each its own, required from clones of its own
export type Copy = {
	Relay: any,
	Slots: any,
	Taps: any,
	State: any,
	Fields: any,
	Constants: any,
	Sequence: any,
	Block: any,
}

-- What both copies start with: the game's tables, copy B's workers and round timeout, and a call once B has started
export type Settings = {
	shared: any,
	server: any,
	workers: number,
	timeout: number,
	started: () -> (),
}

-- What one copy sent, asked and tapped in one run, each list by the name of the viewer it went to or came from, in
-- order, and its answers to the queries after the run, by what was asked
export type Record = {
	blocks: { [string]: { string } },
	withheld: { [string]: { string } },
	asks: { [string]: { string } },
	frames: { [string]: { string } },
	queries: { [string]: string },
}

-- A viewer of a layout: its name, where it starts, whether it owns a player body there, and the way it faces
export type Seat = {
	name: string,
	at: vector,
	owned: boolean,
	facing: number,
}

-- A body with no viewer
export type Body = {
	kind: string,
	at: vector,
}

-- One event as a plan runs it, about a seat by its index, with any other seat
export type Step = {
	event: string,
	seat: number,
	other: number?,
}

-- One layout ready to run: its seats, the moderator's last among them, its bodies, and each run's events
export type Plan = {
	name: string,
	layout: Config.Layout,
	seats: { Seat },
	bodies: { Body },
	before: { [number]: { Step } }, -- Each run's events before it
	after: { [number]: { Step } }, -- And its calls in the window after it
	moderator: number?, -- The moderator's seat, nil in a layout with none
}

-- What a layout's runs reached on the serial copy, and every mismatch found
export type Summary = {
	layout: string,
	runs: number,
	blocks: number,
	withheld: number,
	frames: number,
	asks: number,
	reveals: number,
	hides: number,
	calls: { [string]: number }, -- Each of the relay's members called between runs, by name
	mismatches: { string }, -- The first LISTED found
	found: number,
}

-- One copy as a layout runs it
type Side = {
	copy: Copy,
	record: Record,
}

-- A viewer's client as the serial copy's blocks reach it, which its acknowledgments come from
type Client = {
	newest: number,
	received: { [number]: boolean },
}

local RelayCheck = {}

-- A seeded generator of numbers between 0 and 1
local function generator(seed: number): Generator
	local value: number = seed

	return function (): number
		value = value * MULTIPLIER % MODULUS

		return value / MODULUS
	end
end

-- A place on the ground in a square of a side around a center
local function within(random: Generator, center: vector, side: number): vector
	return center + vector.create((random() - 0.5) * side, 0, (random() - 0.5) * side)
end

-- The look of a facing, a unit vector on the ground
local function lookOf(facing: number): vector
	return vector.create(-math.sin(facing), 0, -math.cos(facing))
end

local function stepAt(steps: { [number]: { Step } }, run: number, step: Step)
	local list: { Step } = steps[run] or {}
	steps[run] = list
	table.insert(list, step)
end

--[[
    A layout's plan: its seats drawn from its seed, a moderator last where
    it has one, its other bodies, and every event of the schedule and its
    spectate, each before its run or, for a call, in the window after it
--]]

function RelayCheck.plan(name: string): Plan
	local layout: Config.Layout? = LAYOUTS[name]
	if not layout then
		error(`RelayCheck.plan takes a layout's name, and no layout is named {name}`, 2)
	end

	local random: Generator = generator(layout.seed)
	local plan: Plan =
		{ name = name, layout = layout, seats = {}, bodies = {}, before = {}, after = {}, moderator = nil }

	for index: number = 1, layout.viewers do
		local at: vector = within(random, layout.center, layout.spread)
		table.insert(plan.seats, { name = `{name}{index}`, at = at, owned = true, facing = random() * TURN })
	end

	local others: number = layout.others or 0
	for _, kind: string in { "Sleeper", "Npc", "Body" } do
		local count: number? = nil
		if kind == "Sleeper" then
			count = layout.sleepers
		elseif kind == "Npc" then
			count = layout.npcs
		else
			count = layout.bodies
		end

		for _ = 1, count or 0 do
			table.insert(plan.bodies, { kind = kind, at = within(random, layout.center, others) })
		end
	end

	for _, event: Config.Event in SCHEDULE do
		local step: Step = { event = event.event, seat = event.viewer, other = event.other }
		if CALLS[event.event] then
			stepAt(plan.after, event.run, step)
		else
			stepAt(plan.before, event.run, step)
		end
	end

	-- A spectate starts and ends on the run after its call, as server:spectate's does
	local spot: vector? = layout.moderator
	local watch: number? = layout.watch
	local unwatch: number? = layout.unwatch
	if spot and watch and unwatch then
		table.insert(plan.seats, { name = MODERATOR, at = spot, owned = false, facing = 0 })
		local moderator: number = #plan.seats
		plan.moderator = moderator

		stepAt(plan.after, watch - 1, { event = "revealAll", seat = 1, other = nil })
		stepAt(plan.before, watch, { event = "watch", seat = moderator, other = 1 })
		stepAt(plan.after, unwatch - 1, { event = "revealAll", seat = moderator, other = nil })
		stepAt(plan.before, unwatch, { event = "unwatch", seat = moderator, other = nil })
	end

	return plan
end

local function record(): Record
	return { blocks = {}, withheld = {}, asks = {}, frames = {}, queries = {} }
end

local function append(lists: { [string]: { string } }, name: string, entry: string)
	local list: { string } = lists[name] or {}
	lists[name] = list
	table.insert(list, entry)
end

-- The byte offset two strings first differ at, the shorter's length when one starts the other
local function firstDiffering(a: string, b: string): number
	for index: number = 1, math.min(#a, #b) do
		if string.byte(a, index) ~= string.byte(b, index) then
			return index - 1
		end
	end

	return math.min(#a, #b)
end

-- The byte at an offset of a string, or end past its last
local function byteAt(data: string, offset: number): string
	local value: number? = string.byte(data, offset + 1)
	if value == nil then
		return "end"
	end

	return `{value}`
end

-- A mismatch kept for the summary while fewer than LISTED are, and counted either way
local function keep(summary: Summary, message: string)
	summary.found += 1
	if #summary.mismatches < LISTED then
		table.insert(summary.mismatches, message)
	end
end

-- Why two strings differ, from where they first differ, or nil when they match
local function differ(what: string, serial: string, workers: string): string?
	if serial == workers then
		return nil
	end

	local offset: number = firstDiffering(serial, workers)
	local bytes: string = `{byteAt(serial, offset)} serially, {byteAt(workers, offset)} on the workers`

	return `{what} first differs at byte {offset} of {#serial} and {#workers} B, {bytes}`
end

-- Every name either map holds, sorted, so a report walks them in one order
local function namesOf(serial: { [string]: any }, workers: { [string]: any }): { string }
	local names: { string } = {}
	for name: string in serial do
		table.insert(names, name)
	end

	for name: string in workers do
		if serial[name] == nil then
			table.insert(names, name)
		end
	end

	table.sort(names)

	return names
end

--[[
    Compares what both copies sent, asked and tapped in a run and their
    answers after it, keeping a mismatch for each recipient's or viewer's
    list that differs in length or at its first entry that differs, and for
    each query that differs, each with its first differing byte
--]]

function RelayCheck.compare(layout: string, run: number, serial: Record, workers: Record, summary: Summary)
	local parts: { { name: string, serial: { [string]: { string } }, workers: { [string]: { string } } } } = {
		{ name = "block to", serial = serial.blocks, workers = workers.blocks },
		{ name = "withheld block to", serial = serial.withheld, workers = workers.withheld },
		{ name = "ask from", serial = serial.asks, workers = workers.asks },
		{ name = "tap frame of", serial = serial.frames, workers = workers.frames },
	}

	for _, part in parts do
		for _, name: string in namesOf(part.serial, part.workers) do
			local a: { string } = part.serial[name] or {}
			local b: { string } = part.workers[name] or {}
			local where: string = `{layout} run {run}, {part.name} {name}`

			if #a ~= #b then
				keep(summary, `{where}: {#a} serially and {#b} on the workers`)
			end

			for index: number = 1, math.min(#a, #b) do
				local why: string? = differ(`{where} {index}`, a[index], b[index])
				if why then
					keep(summary, why)
					break
				end
			end
		end
	end

	for _, what: string in namesOf(serial.queries, workers.queries) do
		local why: string? =
			differ(`{layout} run {run}, {what}`, serial.queries[what] or "", workers.queries[what] or "")
		if why then
			keep(summary, why)
		end
	end
end

--[[
    The names of keys, sorted: a relay walks its views by key, and Luau's
    collector marks a removed key's entry dead, so a key that leaves and
    rejoins comes back at a place that differs from one relay to another
--]]

local function label(names: { [Key]: string }, keys: { Key }): string
	local listed: { string } = {}
	for index: number, key: Key in keys do
		listed[index] = names[key] or "?"
	end

	table.sort(listed)

	return table.concat(listed, ",")
end

--[[
    Every query both copies answer after a run, kept in the copy's record:
    its counts, and each key's keyframe and whether it is sent each slot,
    and who is sent each slot, up to the highest slot taken
--]]

local function query(side: Side, everyone: { Key }, names: { [Key]: string }, top: number)
	local relay: any = side.copy.Relay
	local queries: { [string]: string } = side.record.queries

	local sent: number, cut: number, visited: number = relay.counts()
	queries.counts = `{sent} {cut} {visited}`

	for _, key: Key in everyone do
		local name: string = names[key]
		queries[`keyframe of {name}`] = buffer.tostring(relay.keyframe(key))

		local bits: { string } = table.create(top + 1, "0")
		for slot: number = 0, top do
			if relay.isSent(key, slot) then
				bits[slot + 1] = "1"
			end
		end

		queries[`isSent of {name} by slot`] = table.concat(bits)
	end

	for slot: number = 0, top do
		queries[`viewersOf slot {slot}`] = label(names, relay.viewersOf(slot))
	end
end

--[[
    Runs one layout's plan through both copies, started alike on the
    settings: copy A serially, copy B on its workers once all are ready,
    each of B's rounds brought in once wait has passed and its finish
    answers true, inside the timeout. Every call between runs goes into
    both in B's window. Gives what the runs reached and every mismatch
--]]

function RelayCheck.check(plan: Plan, serialCopy: Copy, workersCopy: Copy, settings: Settings, wait: () -> ()): Summary
	local layout: Config.Layout = plan.layout
	local summary: Summary = {
		layout = plan.name,
		runs = 0,
		blocks = 0,
		withheld = 0,
		frames = 0,
		asks = 0,
		reveals = 0,
		hides = 0,
		calls = {},
		mismatches = {},
		found = 0,
	}

	local serial: Side = { copy = serialCopy, record = record() }
	local workers: Side = { copy = workersCopy, record = record() }
	local sides: { Side } = { serial, workers }

	local names: { [Key]: string } = {}
	local hidden: { [Key]: { [number]: boolean } } = {}
	local traffic: { [Key]: number } = {}
	local clients: { [Key]: Client } = {}
	local states: { [number]: any } = {}
	local commands: { [number]: any } = {}
	local viewers: { any } = {}
	local seated: { any } = {} -- Each seat's viewer, by its seat's index
	local everyone: { Key } = {}
	local top: number = 0
	local tick: number = 0
	local random: Generator = generator(layout.seed)
	local scratch: any = serialCopy.Block.new()

	-- Every port of one copy, each writing to the copy's record of the run, the serial copy's feeding the clients
	local function start(side: Side, server: { [string]: any })
		local copy: Copy = side.copy
		local slots: number = copy.Constants.SLOTS
		local row: number = slots // BITS
		local kinds: buffer = buffer.create(slots)
		local teams: buffer = buffer.create(slots * 8)
		buffer.fill(kinds, 0, LYING)
		for slot: number = 0, slots - 1 do
			buffer.writef64(teams, slot * 8, 0 / 0)
		end

		local function send(keys: { Key }, data: buffer)
			local bytes: string = buffer.tostring(data)
			for _, key: Key in keys do
				append(side.record.blocks, names[key], bytes)
			end

			if side ~= serial then
				return
			end

			summary.blocks += 1
			copy.Block.read(data, scratch)
			summary.reveals += scratch.revealCount
			summary.hides += scratch.hideCount

			local sequence: number = buffer.readu16(data, 0)
			for _, key: Key in keys do
				local client: Client = clients[key]
				client.received[sequence] = true
				if client.newest == 0 or copy.Sequence.difference(sequence, client.newest) > 0 then
					client.newest = sequence
				end
			end
		end

		local function sendWithheld(keys: { Key }, data: buffer)
			local bytes: string = buffer.tostring(data)
			for _, key: Key in keys do
				append(side.record.withheld, names[key], bytes)
			end

			if side == serial then
				summary.withheld += 1
			end
		end

		local function isHidden(viewer: any, slot: number): boolean
			append(side.record.asks, names[viewer.key], `{slot}`)
			if side == serial then
				summary.asks += 1
			end

			local own: { [number]: boolean }? = hidden[viewer.key]

			return own ~= nil and own[slot] == true
		end

		-- As the serial copy's isHidden answers: every slot read from its bit, set unless hidden from the viewer
		local function answers(list: { any }): { kinds: buffer, teams: buffer, visible: buffer }
			local visible: buffer = buffer.create(#list * row)
			buffer.fill(visible, 0, ALL_SHOWN)

			for index: number, viewer: any in list do
				for slot: number, off: boolean in hidden[viewer.key] or {} do
					if off then
						local at: number = (index - 1) * row + slot // BITS
						local cleared: number =
							bit32.band(buffer.readu8(visible, at), bit32.bnot(bit32.lshift(1, slot % BITS)))
						buffer.writeu8(visible, at, cleared)
					end
				end
			end

			return { kinds = kinds, teams = teams, visible = visible }
		end

		local layoutOf: any = copy.Fields.compile(settings.shared.fields)
		copy.Slots.start(settings.server.slots.reserve)
		local function trafficOf(key: Key): number
			return traffic[key] or 0
		end

		copy.Relay.start(
			{ shared = settings.shared, server = server, layout = layoutOf },
			send,
			sendWithheld,
			trafficOf,
			isHidden,
			answers
		)

		copy.Taps.start({
			layout = layoutOf,
			wearing = copy.Relay.wearing,
			reason = function (key: Key, slot: number): string
				local own: { [number]: boolean }? = hidden[key]
				if own and own[slot] then
					return "Hidden"
				end

				return "Clear"
			end,
		})
	end

	-- The same server settings for both, copy A's relay with no workers and copy B's with them
	local relaySettings: { [string]: any } = settings.server.relay or {}
	local serialServer: { [string]: any } = table.clone(settings.server)
	serialServer.relay = { changes = relaySettings.changes }
	local workersServer: { [string]: any } = table.clone(settings.server)
	workersServer.relay = { changes = relaySettings.changes, workers = settings.workers, timeout = settings.timeout }

	start(serial, serialServer)
	start(workers, workersServer)
	settings.started()

	-- Each copy's body in a slot, the same in both slot tables
	local function spawn(kind: string, at: vector, facing: number): number
		local slot: number? = serial.copy.Slots.take(kind)
		if slot == nil then
			error(`The copies' slot tables had no slot free for a {kind}`)
		elseif workers.copy.Slots.take(kind) ~= slot then
			error("The two copies' slot tables gave a body different slots")
		end

		for _, side: Side in sides do
			side.copy.Slots.setEntry(slot, { kind = kind, rig = "A" })
		end

		local state: any = serial.copy.State.new()
		state.position = at
		state.facing = facing
		state.mode = "Ground"
		state.grounded = true
		state.groundMaterial = Enum.Material.Grass
		states[slot] = state
		top = math.max(top, slot)

		return slot
	end

	-- Both copies run with the same empty lists until every one of B's workers is ready, so no view is made in process
	local ready: number = 0
	local readyBy: number = os.clock() + READY
	while true do
		tick += 1
		for _, side: Side in sides do
			side.copy.Relay.run(tick, {}, {}, {})
		end

		local _, _, count: number = workers.copy.Relay.homes()
		ready = count
		if ready >= settings.workers then
			break
		elseif os.clock() >= readyBy then
			keep(summary, `{plan.name}: {ready} of copy B's {settings.workers} workers were ready after {READY} s`)
			return summary
		end

		wait()
	end

	for index: number, seat: Seat in plan.seats do
		local key: Key = { Name = seat.name }
		names[key] = seat.name
		hidden[key] = {}
		clients[key] = { newest = 0, received = {} }
		table.insert(everyone, key)

		local viewer: any = { key = key, slot = nil, position = seat.at, acknowledged = 0, received = 0, target = nil }
		if seat.owned then
			viewer.slot = spawn("Player", seat.at, seat.facing)
			viewer.look = lookOf(seat.facing)
		end

		seated[index] = viewer
		table.insert(viewers, viewer)
	end

	for _, body: Body in plan.bodies do
		spawn(body.kind, body.at, 0)
	end

	-- A spectate's target's view is made first and the moderator's next, so they sit on different workers
	local moderator: number? = plan.moderator
	if moderator then
		for _, side: Side in sides do
			side.copy.Relay.setDistance(seated[1].key, FAR)
			side.copy.Relay.setDistance(seated[moderator].key, FAR)
		end
	end

	-- Sinks on both copies for the first viewers' frames, the moderator's, and its target's withheld records
	local function observe(key: Key, withheld: boolean)
		for _, side: Side in sides do
			local name: string = names[key]
			if withheld then
				name = `{name} {WITHHELD}`
			end

			local function sink(_: number, data: buffer)
				append(side.record.frames, name, buffer.tostring(data))
				if side == serial then
					summary.frames += 1
				end
			end

			if withheld then
				side.copy.Taps.observeWithheld(key, sink)
			else
				side.copy.Taps.observe(key, sink)
			end
		end
	end

	for index: number = 1, math.min(OBSERVED, #seated) do
		observe(seated[index].key, false)
	end

	if moderator then
		observe(seated[moderator].key, false)
		observe(seated[1].key, true)
	end

	-- Hides a share of the other seats' bodies from each viewer, and shows the rest
	local function shuffle()
		for _, viewer: any in seated do
			for _, other: any in seated do
				if other ~= viewer and other.slot ~= nil then
					hidden[viewer.key][other.slot] = random() < layout.hidden
				end
			end
		end
	end

	-- One call into both copies, counted by the relay member it calls
	local function call(member: string, ...: any)
		summary.calls[member] = (summary.calls[member] or 0) + 1
		for _, side: Side in sides do
			side.copy.Relay[member](...)
		end
	end

	-- An event before its run: what the states, the anti-ESP stand-in and the viewer list hold changes
	local function before(step: Step)
		local viewer: any = seated[step.seat]
		local event: string = step.event

		if event == "held" then
			states[viewer.slot].held = table.clone(HELD)
		elseif event == "busy" then
			traffic[viewer.key] = BUSY
		elseif event == "calm" then
			traffic[viewer.key] = nil
		elseif event == "death" then
			states[viewer.slot] = nil
			for _, side: Side in sides do
				side.copy.Slots.release(viewer.slot)
			end

			viewer.slot = nil
		elseif event == "rejoin" then
			clients[viewer.key] = { newest = 0, received = {} }
			viewer.acknowledged = 0
			viewer.received = 0
			table.insert(viewers, viewer)
		elseif event == "watch" then
			viewer.target = seated[step.other :: number].key
		elseif event == "unwatch" then
			viewer.target = nil
		else
			error(`The layout's event {event} is none the check makes before a run`)
		end
	end

	-- A call between runs, inside copy B's window, into both copies alike
	local function after(step: Step)
		local viewer: any = seated[step.seat]
		local event: string = step.event

		if event == "look" then
			call("setLook", viewer.slot, LOOK)
		elseif event == "otherLook" then
			call("setLook", viewer.slot, OTHER_LOOK)
		elseif event == "invisible" then
			call("setInvisible", viewer.slot, true)
		elseif event == "visible" then
			call("setInvisible", viewer.slot, false)
		elseif event == "reveal" then
			call("reveal", viewer.slot)
		elseif event == "shotNear" then
			call("shotNear", viewer.key, seated[step.other :: number].slot)
		elseif event == "near" then
			call("setDistance", viewer.key, NEAR)
		elseif event == "far" then
			call("setDistance", viewer.key, FAR)
		elseif event == "revealAll" then
			call("revealAll", viewer.key)
		elseif event == "leave" then
			call("remove", viewer.key)

			local index: number? = table.find(viewers, viewer)
			if index then
				table.remove(viewers, index)
			end
		else
			error(`The layout's event {event} is no call the check makes between runs`)
		end
	end

	-- Copy B's round, brought in at a later Heartbeat once its finish answers true, or why not
	local function land(): string?
		local ends: number = os.clock() + settings.timeout
		while true do
			wait()

			local ran: boolean, finished: any = pcall(workers.copy.Relay.finish)
			if not ran then
				return `copy B's finish threw: {finished}`
			elseif finished then
				return nil
			elseif os.clock() >= ends then
				return `copy B's round was not in {settings.timeout} s after its run`
			end
		end
	end

	for run: number = 1, layout.runs do
		for _, step: Step in plan.before[run] or {} do
			before(step)
		end

		if run % layout.shuffle == 1 then
			shuffle()
		end

		-- Every owned body moves and turns, now and then jumping, and each owned viewer stands where its body does
		for _, viewer: any in seated do
			local state: any = nil
			if viewer.slot ~= nil then
				state = states[viewer.slot]
			end

			if state then
				local step: vector = vector.create((random() - 0.5) * 2, 0, (random() - 0.5) * 2) * layout.step
				state.position += step
				state.facing += (random() - 0.5) * 2 * layout.turn
				if random() < layout.jump then
					state.jumps = (state.jumps + 1) % JUMPS
				end

				viewer.position = state.position
				viewer.look = lookOf(state.facing)
			end
		end

		tick += 1
		serial.record = record()
		workers.record = record()

		local serialRan: boolean, serialError: any = pcall(serial.copy.Relay.run, tick, viewers, states, commands)
		if serial.copy.Taps.observing then
			serial.copy.Taps.finish(tick)
		end

		local workersRan: boolean, workersError: any = pcall(workers.copy.Relay.run, tick, viewers, states, commands)

		for _, step: Step in plan.after[run] or {} do
			after(step)
		end

		local missed: string? = nil
		if workersRan then
			missed = land()
		end

		if not (serialRan and workersRan) or missed then
			local thrown: string = `serially {serialError or "none"}, on the workers {workersError or missed}`
			keep(summary, `{plan.name} run {run}: a run threw or a round never landed, {thrown}`)
			return summary
		end

		if workers.copy.Taps.observing then
			workers.copy.Taps.finish(tick)
		end

		for _, side: Side in sides do
			query(side, everyone, names, top)
		end

		RelayCheck.compare(plan.name, run, serial.record, workers.record, summary)
		summary.runs = run

		-- Each client's acknowledgment of what it read of the serial copy, which both copies take in the next run
		for _, viewer: any in viewers do
			local client: Client = clients[viewer.key]
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

	return summary
end

-- A layout's line for the report: what its runs compared, the calls made, and every mismatch kept
function RelayCheck.line(summary: Summary, seconds: number): string
	local calls: { string } = {}
	for member: string, count: number in summary.calls do
		table.insert(calls, `{member} {count}`)
	end

	table.sort(calls)

	local reached: string = `{summary.blocks} blocks, {summary.withheld} withheld blocks, {summary.frames} tap frames`
	local crossed: string = `{summary.asks} asks, {summary.reveals} reveals and {summary.hides} hides`
	local head: string =
		`RelayCheck {summary.layout}: {summary.runs} runs in {string.format("%.1f", seconds)} s, {reached}, {crossed}`
	local parts: { string } = { head, `calls {table.concat(calls, ", ")}`, `{summary.found} mismatches` }

	for _, mismatch: string in summary.mismatches do
		table.insert(parts, mismatch)
	end

	return table.concat(parts, SEPARATOR)
end

return RelayCheck
