--[[
    A serial relay and the same front over two stand-in workers, run on the
    same runs and keys, give the same sends, asks, taps, errors, counts and
    query answers, the case playing the front's part in place of its Turn
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/Relay/StandIn")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local TURN: string = "src/Server/Relay/Turn.luau"
local TURN_PATH: string = "ReplicatedStorage.Packages.Tread.Server.Relay.Turn"

local WORKERS: number = 2
local SLOTS: number = 4096 -- Constants.SLOTS
local ROW_BYTES: number = SLOTS // 8
local MASK_BITS: number = 16 -- The sequences before the newest a client's acknowledgment covers
local WRAP: number = 2 ^ 16
local MODULUS: number = 2 ^ 31 - 1 -- Park and Miller's generator
local MULTIPLIER: number = 16807
local SEED: number = 505

-- Anti-ESP's kinds as AntiEsp.answers gives them
local FREE: number = 0
local PLAYER: number = 1
local LYING: number = 2
local NPC: number = 3

local PLAYERS: number = 8
local CENTER: vector = vector.create(400, 0, 400)
local SPREAD: number = 50 -- Inside the footsteps' 40-stud walking range for many pairs
local STEP: number = 3 -- Studs a body may move along each axis a run
local JUMP: number = 0.15 -- A body's chance of a jump a run
local RUNS: number = 30
local EXTRA_WATCHERS: number = 31 -- With the moderator, one more than a target takes
local BUSY: number = 95000 -- B a second of traffic that leaves a viewer little of its 96 KB hard room
local INVALID_SLOT: number = SLOTS -- A slot the slot table never has, whose viewer's turn throws

-- The runs things happen before, as their names say
local LOOK_RUN: number = 3
local HELD_RUN: number = 4
local WATCH_RUN: number = 5
local INVISIBLE_RUN: number = 6
local REVEAL_RUN: number = 7
local SHOT_RUN: number = 8
local VISIBLE_RUN: number = 9
local NEAR_RUN: number = 10
local SHUFFLE_RUN: number = 12
local OVERFULL_RUN: number = 13
local REMOVE_RUN: number = 14
local FAR_RUN: number = 15
local BUSY_RUN: number = 16
local CALM_RUN: number = 20
local RETURN_RUN: number = 18
local DEATH_RUN: number = 21
local THROW_RUN: number = 23
local LEAVE_RUN: number = 26
local REJOIN_RUN: number = 28
local RESEND_RUN: number = 11 -- Each worker sends every view it runs whole from here, as after a lost result
local NEAR_DISTANCE: number = 30
local FAR_DISTANCE: number = 1000

type Generator = () -> number

-- What anti-ESP's answers come from on both sides: each slot's kind and team, and each viewer's hidden slots
type Model = {
	kinds: { [number]: number },
	teams: { [number]: number },
	hidden: { [any]: { [number]: boolean } },
	traffic: { [any]: number },
	top: number, -- The highest slot taken
}

-- One relay's environment and what it sent, asked and tapped this run, in order
type Side = {
	name: string,
	globals: any,
	Relay: any,
	Slots: any,
	Taps: any,
	log: { string },
	frames: { [string]: { string } },
}

-- A client of the serial side, which reads every block it is sent
type Client = {
	newest: number,
	received: { [number]: boolean },
}

-- The front's part around the stand-in workers, in place of its Turn
type Front = {
	real: any, -- A Turn of its own VM, whose world the front's walk fills
	stub: { [string]: any }, -- What the front requires as its Turn
	Wire: any,
	Taps: any,
	pool: any,
	ports: any,
	homes: { [any]: number },
	pinned: { [any]: number },
	views: { number },
	ids: { [any]: number },
	keys: { [number]: any },
	nextId: number,
	copies: { [any]: any },
	stale: { [any]: boolean }, -- The copies started again empty when their worker next sends their view whole
	resent: number, -- The views brought into an empty copy
	calls: { any },
	queued: { [number]: number }, -- Each call kind queued so far
	heard: { [any]: number },
	watching: { [any]: any },
	header: { [string]: number },
	snapshot: { lookVersions: buffer, lookLives: buffer, invisible: buffer, heldVersions: buffer },
	readers: { any },
	round: number,
	totals: { number },
	index: { [any]: number },
	expected: { [number]: number },
	answerFrom: { [number]: { number } },
	placeOf: { [number]: number },
	observed: { any },
	model: Model,
	turned: { number }, -- The turns each worker ran
}

local Names: { [any]: string } = {}

-- A seeded generator of numbers between 0 and 1
local function generator(seed: number): Generator
	local value: number = seed

	return function (): number
		value = value * MULTIPLIER % MODULUS

		return value / MODULUS
	end
end

-- Whether anti-ESP's stand-in rule hides a slot from a viewer
local function hides(model: Model, viewer: any, slot: number): boolean
	local kind: number = model.kinds[slot] or FREE
	if kind == FREE or kind == NPC then
		return false
	end

	local own: number? = viewer.slot
	local team: number? = model.teams[slot]
	if kind == PLAYER and own ~= nil and team ~= nil and model.teams[own] == team then
		return false
	end

	local hidden: { [number]: boolean }? = model.hidden[viewer.key]

	return hidden ~= nil and hidden[slot] == true
end

-- The names of keys, in order
local function label(keys: { any }, count: number?): string
	local names: { string } = {}
	for index: number = 1, count or #keys do
		names[index] = Names[keys[index]] or "?"
	end

	return table.concat(names, ",")
end

-- Whether one key's name sorts before another's
local function byName(a: any, b: any): boolean
	return (Names[a] or "?") < (Names[b] or "?")
end

-- One relay's environment, started on the example's tables, logging every send and ask, and feeding clients
local function side(name: string, model: Model, clients: { [any]: Client }?, overrides: { [string]: any }?): Side
	local globals: any = Environment.load(GLOBALS, overrides)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Example: any = globals.require(globals.game:GetService("ServerScriptService").Fixtures.Config.Example)
	local sharedTable: any = Example.shared()
	local server: any = Example.server()
	local layout: any = globals.require(tread.Codec.Fields).compile(sharedTable.fields)
	local Sequence: any = globals.require(tread.Codec.Sequence)

	local self: Side = {
		name = name,
		globals = globals,
		Relay = globals.require(tread.Server.Relay),
		Slots = globals.require(tread.Server.Slots),
		Taps = globals.require(tread.Server.Taps),
		log = {},
		frames = {},
	}

	self.Slots.start(server.slots.reserve)

	local function send(keys: { any }, data: buffer)
		table.insert(self.log, `block {label(keys)} {buffer.tostring(data)}`)

		if clients then
			local sequence: number = buffer.readu16(data, 0)
			for _, key: any in keys do
				local client: Client = clients[key]
				client.received[sequence] = true
				if client.newest == 0 or Sequence.difference(sequence, client.newest) > 0 then
					client.newest = sequence
				end
			end
		end
	end

	local function sendWithheld(keys: { any }, data: buffer)
		table.insert(self.log, `withheld {label(keys)} {buffer.tostring(data)}`)
	end

	local function traffic(key: any): number
		return model.traffic[key] or 0
	end

	local function isHidden(viewer: any, slot: number): boolean
		table.insert(self.log, `ask {Names[viewer.key]} {slot}`)

		return hides(model, viewer, slot)
	end

	self.Relay.start({ shared = sharedTable, server = server, layout = layout }, send, sendWithheld, traffic, isHidden)
	self.Taps.start({
		layout = layout,
		wearing = self.Relay.wearing,
		reason = function (key: any, slot: number): string
			local hidden: { [number]: boolean }? = model.hidden[key]
			if hidden and hidden[slot] then
				return "Hidden"
			end

			return "Clear"
		end,
	})

	return self
end

-- The id the front gives a key, made the first time it is seen
local function idOf(front: Front, key: any): number
	local id: number? = front.ids[key]
	if id then
		return id
	end

	front.nextId += 1
	front.ids[key] = front.nextId
	front.keys[front.nextId] = key

	return front.nextId
end

-- A key's view made as Turn makes one: its copy, and its worker, the one pinned or the one with the fewest views
local function made(front: Front, key: any)
	if front.copies[key] == nil then
		front.copies[key] = front.Wire.copy()
	end

	if front.homes[key] == nil then
		local home: number? = front.pinned[key]
		if home == nil then
			home = 1
			for worker: number = 2, WORKERS do
				if front.views[worker] < front.views[home] then
					home = worker
				end
			end
		end

		front.homes[key] = home
		front.views[home] += 1
	end

	idOf(front, key)
end

-- Queues one call for a key's worker, counting its kind
local function queue(front: Front, worker: number, kind: number, key: any, slot: number, value: number)
	front.Wire.call(front.calls[worker], kind, idOf(front, key), slot, value)
	front.queued[kind] = (front.queued[kind] or 0) + 1
end

--[[
    The front's dispatch at Turn.ready: views made and homed in list order,
    each worker's list of the viewers it hosts and the watchers of its
    targets and its own, latest and back as the front's loops work them
    out, both hand-ins, the rounds delivered, and every view's copy brought
    level from the results
--]]

local function dispatch(front: Front, viewers: { any })
	local Wire: any = front.Wire
	local world: any = front.real.world
	local model: Model = front.model

	for _, viewer: any in viewers do
		made(front, viewer.key)
		if viewer.target ~= nil then
			idOf(front, viewer.target)
		end
	end

	-- Each watcher goes to its target's worker, whose answer counts, and to its own, so its view is made there
	local lists: { { number } } = {}
	local ordinals: { number } = {}
	for worker: number = 1, WORKERS do
		lists[worker] = {}
		ordinals[worker] = 0
	end

	front.index = {}
	front.answerFrom = {}
	front.placeOf = {}
	front.expected = {}

	for index: number, viewer: any in viewers do
		local key: any = viewer.key
		local target: any = viewer.target
		front.index[viewer] = index

		if target == nil then
			local list: { number } = lists[front.homes[key]]
			table.insert(list, index)
			front.placeOf[index] = #list

			if front.watching[key] ~= nil then
				front.expected[index] = front.heard[key] or 0
			end
		else
			local starting: boolean = front.watching[key] ~= target
			front.expected[index] = starting and (front.heard[key] or 0) or 0

			for worker: number = 1, WORKERS do
				if worker == front.homes[target] or worker == front.homes[key] then
					table.insert(lists[worker], index)
					ordinals[worker] += 1
					if worker == front.homes[target] then
						front.answerFrom[index] = { worker, ordinals[worker] }
					end
				end
			end
		end
	end

	-- Anti-ESP's export for the whole list, as AntiEsp.answers lays it out
	local kinds: buffer = buffer.create(SLOTS)
	local teams: buffer = buffer.create(SLOTS * 8)
	local visible: buffer = buffer.create(#viewers * ROW_BYTES)
	for slot: number = 0, SLOTS - 1 do
		buffer.writeu8(kinds, slot, model.kinds[slot] or FREE)
		buffer.writef64(teams, slot * 8, model.teams[slot] or 0 / 0)
	end

	for index: number, viewer: any in viewers do
		local hidden: { [number]: boolean } = model.hidden[viewer.key] or {}
		for slot: number = 0, model.top do
			if not hidden[slot] then
				local at: number = (index - 1) * ROW_BYTES + slot // 8
				buffer.writeu8(visible, at, bit32.bor(buffer.readu8(visible, at), bit32.lshift(1, slot % 8)))
			end
		end
	end

	-- The looks and Invisible marks set since the last run, and the held items this run's walk changed
	local snapshot: any = front.snapshot
	local looks: { number } = {}
	local helds: { number } = {}
	for slot: number = 0, SLOTS - 1 do
		local lookVersion: number = buffer.readu16(world.lookVersions, slot * 2)
		local life: number = buffer.readu8(world.lookLives, slot)
		local invisible: number = buffer.readu8(world.invisible, slot)
		if
			lookVersion ~= buffer.readu16(snapshot.lookVersions, slot * 2)
			or life ~= buffer.readu8(snapshot.lookLives, slot)
			or invisible ~= buffer.readu8(snapshot.invisible, slot)
		then
			table.insert(looks, slot)
			buffer.writeu16(snapshot.lookVersions, slot * 2, lookVersion)
			buffer.writeu8(snapshot.lookLives, slot, life)
			buffer.writeu8(snapshot.invisible, slot, invisible)
		end

		local heldVersion: number = buffer.readu16(world.heldVersions, slot * 2)
		if heldVersion ~= buffer.readu16(snapshot.heldVersions, slot * 2) then
			table.insert(helds, slot)
			buffer.writeu16(snapshot.heldVersions, slot * 2, heldVersion)
		end
	end

	local observed: { number } = {}
	for _, key: any in front.observed do
		table.insert(observed, idOf(front, key))
	end

	local header: { [string]: number } = front.header
	local shared: buffer = Wire.writeShared(world, {
		run = header.run,
		tick = header.tick,
		elapsed = header.elapsed,
		wire = header.wire,
		places = header.places,
		looks = looks,
		lookCount = #looks,
		helds = helds,
		heldCount = #helds,
		observing = front.Taps.observing,
		observed = observed,
		observedCount = #observed,
		kinds = kinds,
		teams = teams,
	})

	front.round += 1
	for worker: number, list: { number } in lists do
		local hands: { any } = {}
		for place: number, index: number in list do
			local viewer: any = viewers[index]
			local key: any = viewer.key
			local target: any = viewer.target
			local slot: number? = viewer.slot
			local expected: number? = front.expected[index]
			local targetId: number? = nil
			local traffic: number = 0
			if target ~= nil then
				targetId = front.ids[target]
			else
				traffic = front.ports.traffic(key)
			end

			local team: number = 0 / 0
			if slot ~= nil and model.teams[slot] ~= nil then
				team = model.teams[slot]
			end

			hands[place] = {
				id = front.ids[key],
				slot = slot,
				target = targetId,
				position = viewer.position,
				look = viewer.look,
				acknowledged = viewer.acknowledged,
				received = viewer.received,
				sequence = expected or 0,
				back = target == nil and expected ~= nil,
				traffic = traffic,
				team = team,
				row = (index - 1) * ROW_BYTES,
			}
		end

		local resend: boolean = header.run == RESEND_RUN
		front.pool:send(worker, front.round, shared, Wire.writeOwn(front.calls[worker], hands, #hands, visible, resend))
		front.calls[worker].count = 0

		if resend then
			for key: any, home: number in front.homes do
				if home == worker then
					front.stale[key] = true
				end
			end
		end
	end

	front.pool:deliver()

	for worker: number = 1, WORKERS do
		local result: buffer?, failure: string? = front.pool:landed(worker, front.round)
		if result == nil then
			error(`Worker {worker}'s round {front.round} failed: {failure}`)
		end

		local reader: any = front.readers[worker]
		Wire.open(reader, result)
		front.totals[1] += reader.sent
		front.totals[2] += reader.cut
		front.totals[3] += reader.visited
		front.turned[worker] += reader.turns

		local id: number = Wire.nextView(reader)
		while id ~= 0 do
			local key: any = front.keys[id]
			if front.stale[key] and front.copies[key] then
				front.copies[key] = Wire.copy()
				front.stale[key] = nil
				front.resent += 1
			end

			local copy: any = front.copies[key]
			if copy then
				Wire.applyView(reader, copy)
			end

			id = Wire.nextView(reader)
		end
	end
end

--[[
    The front's replay of one turn at Turn.turn, in the serial order the
    front's turn loop calls it: the viewer's asks in walk order through its
    isHidden, then its sends, taps and heard sequences through its ports,
    and last the error a throwing turn gave its worker
--]]

local function replay(front: Front, viewer: any, back: number?)
	local Wire: any = front.Wire
	local ports: any = front.ports
	local index: number = front.index[viewer]
	local key: any = viewer.key

	if back ~= front.expected[index] then
		error(`The front's back for {Names[key]} was {back}, where its dispatch handed {front.expected[index]}`)
	elseif front.watching[key] ~= nil then
		front.watching[key] = nil
	end

	local reader: any = front.readers[front.homes[key]]
	if not Wire.nextTurn(reader) or reader.place ~= front.placeOf[index] then
		error(`The front's turn for {Names[key]} found its worker's results out of step`)
	end

	local keys: { any } = {}
	for at: number = 1, reader.recipientCount do
		keys[at] = front.keys[reader.recipients[at]]
	end

	local watchers: { any } = { table.unpack(keys, 2) }
	local walk: buffer = front.real.world.walk

	local places: { number } = {}
	for at: number = 1, Wire.asks(reader, places) do
		ports.isHidden(viewer, buffer.readu16(walk, places[at] * 2))
	end

	local kind: number = Wire.nextEvent(reader)
	while kind ~= 0 do
		if kind == Wire.SEND then
			ports.send(keys, reader.block)
		elseif kind == Wire.RELAYED then
			ports.relayed(keys, #keys, reader.tap, reader.block)
		elseif kind == Wire.HEARD then
			ports.heard(keys, #keys, reader.sequence)
			for _, recipient: any in keys do
				front.heard[recipient] = reader.sequence
			end
		elseif kind == Wire.WITHHELD then
			ports.sendWithheld(watchers, reader.block)
		else
			ports.withheld(keys[1], reader.tap, reader.block)
		end

		kind = Wire.nextEvent(reader)
	end

	if reader.failed == reader.place then
		error(reader.failure, 0)
	end
end

-- The front's part in place of its Turn, over a Turn of a VM of its own whose world the front fills
local function frontOf(model: Model): Front
	local real: any = Environment.load(TURN)
	local front: Front

	local stub: { [string]: any } = {
		world = real.world,
		KIND_CODES = real.KIND_CODES,
		SENT = real.SENT,
		OWN = real.OWN,
		WITHHELD = real.WITHHELD,
	}

	function stub.start(settings: any, ports: any)
		front.ports = ports
		real.start(settings, ports)
		front.pool = StandIn.new(WORKERS, "RelayWorkers", nil, settings)
	end

	function stub.begin(run: number, tick: number, elapsed: number, wire: number)
		real.begin(run, tick, elapsed, wire)
		front.header.run = run
		front.header.tick = tick
		front.header.elapsed = elapsed
		front.header.wire = wire
	end

	function stub.file(count: number)
		front.header.places = count
	end

	function stub.ready(viewers: { any })
		dispatch(front, viewers)
	end

	function stub.watch(viewer: any, target: any, latest: number): boolean?
		local index: number = front.index[viewer]
		if latest ~= front.expected[index] then
			error(
				`The front's latest for {Names[viewer.key]} was {latest}, where its dispatch handed {front.expected[index]}`
			)
		end

		local from: { number }? = front.answerFrom[index]
		local watched: boolean? = nil
		if from then
			watched = front.Wire.watched(front.readers[from[1]], from[2])
		end

		if watched and front.watching[viewer.key] ~= target then
			front.watching[viewer.key] = target
		end

		return watched
	end

	function stub.turn(viewer: any, back: number?)
		replay(front, viewer, back)
	end

	function stub.shotNear(key: any, slot: number, through: number)
		if front.copies[key] then
			queue(front, front.homes[key], front.Wire.SHOT_NEAR, key, slot, through)
		end
	end

	-- Each call that reveals again changes the kinds a copy keeps at the call, as it changes the view's
	function stub.reveal(key: any, slot: number)
		local copy: any = front.copies[key]
		if copy then
			buffer.writeu8(copy.kinds, slot, buffer.readu8(real.world.kinds, slot))
			queue(front, front.homes[key], front.Wire.REVEAL, key, slot, 0)
		end
	end

	function stub.revealAll(key: any, floor: number)
		local copy: any = front.copies[key]
		if copy then
			for _, slot: number in copy.tracked do
				if bit32.btest(buffer.readu16(copy.flags, slot * 2), real.SENT) then
					buffer.writeu8(copy.kinds, slot, buffer.readu8(real.world.kinds, slot))
				end
			end

			queue(front, front.homes[key], front.Wire.REVEAL_ALL, key, 0, floor)
		end
	end

	function stub.setDistance(key: any, distance: number)
		made(front, key)
		queue(front, front.homes[key], front.Wire.SET_DISTANCE, key, 0, distance)
	end

	-- A key keeps its id once given, so a view a worker failed to drop would come back to it when the key rejoins
	function stub.remove(key: any)
		if front.ids[key] then
			for worker: number = 1, WORKERS do
				queue(front, worker, front.Wire.REMOVE, key, 0, 0)
			end
		end

		local home: number? = front.homes[key]
		if home then
			front.views[home] -= 1
			front.homes[key] = nil
		end

		front.copies[key] = nil
		front.heard[key] = nil
		front.watching[key] = nil
	end

	function stub.view(key: any): any
		return front.copies[key]
	end

	function stub.views(): any
		return front.copies
	end

	function stub.counts(): (number, number, number)
		return front.totals[1], front.totals[2], front.totals[3]
	end

	front = {
		real = real,
		stub = stub,
		Wire = nil,
		Taps = nil,
		pool = nil,
		ports = nil,
		homes = {},
		pinned = {},
		views = table.create(WORKERS, 0),
		ids = {},
		keys = {},
		nextId = 0,
		copies = {},
		stale = {},
		resent = 0,
		calls = {},
		queued = {},
		heard = {},
		watching = {},
		header = { run = 0, tick = 0, elapsed = 0, wire = 0, places = 0 },
		snapshot = {
			lookVersions = buffer.create(SLOTS * 2),
			lookLives = buffer.create(SLOTS),
			invisible = buffer.create(SLOTS),
			heldVersions = buffer.create(SLOTS * 2),
		},
		readers = {},
		round = 0,
		totals = { 0, 0, 0 },
		index = {},
		expected = {},
		answerFrom = {},
		placeOf = {},
		observed = {},
		model = model,
		turned = table.create(WORKERS, 0),
	} :: any

	return front
end

-- Why two lists of logged lines differ, or nil when they match
local function compare(what: string, serial: { string }, worker: { string }): string?
	for index: number = 1, math.max(#serial, #worker) do
		if serial[index] ~= worker[index] then
			local expected: string = (serial[index] or "nothing"):sub(1, 80)
			local got: string = (worker[index] or "nothing"):sub(1, 80)

			return `{what} {index} differs: serial gave "{expected}", the workers "{got}"`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local model: Model = { kinds = {}, teams = {}, hidden = {}, traffic = {}, top = 0 }
	local clients: { [any]: Client } = {}
	local front: Front = frontOf(model)

	local serial: Side = side("serial", model, clients, nil)
	local workers: Side = side("workers", model, nil, { [TURN_PATH] = front.stub })

	local tread: any = workers.globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Block: any =
		serial.globals.require(serial.globals.game:GetService("ReplicatedStorage").Packages.Tread.Codec.Block)
	front.Wire = workers.globals.require(tread.Server.Relay.Wire)
	front.Taps = workers.Taps
	for worker: number = 1, WORKERS do
		front.calls[worker] = front.Wire.calls()
		front.readers[worker] = front.Wire.reader(front.real.world.records)
	end

	local random: Generator = generator(SEED)
	local states: { [number]: any } = {}
	local commands: { [number]: any } = {}
	local viewers: { any } = {}
	local State: any =
		serial.globals.require(serial.globals.game:GetService("ReplicatedStorage").Packages.Tread.Step.State)

	-- A body of a kind in both relays' slot tables, resting on the ground
	local function spawn(kind: string, position: vector): number
		local slot: number = serial.Slots.take(kind)
		if workers.Slots.take(kind) ~= slot then
			error("The two slot tables gave a body different slots")
		end

		serial.Slots.setEntry(slot, { kind = kind, rig = "A" })
		workers.Slots.setEntry(slot, { kind = kind, rig = "A" })

		local state: any = State.new()
		state.position = position
		state.mode = "Ground"
		state.grounded = true
		state.groundMaterial = roblox.Enum.Material.Grass
		states[slot] = state

		model.top = math.max(model.top, slot)
		if kind == "Player" then
			model.kinds[slot] = PLAYER
		elseif kind == "Npc" then
			model.kinds[slot] = NPC
		else
			model.kinds[slot] = LYING
		end

		return slot
	end

	local function despawn(slot: number)
		states[slot] = nil
		model.kinds[slot] = nil
		serial.Slots.release(slot)
		workers.Slots.release(slot)
	end

	-- A viewer on both sides, the same key and the same table, with a body when owned and the worker it is pinned to
	local function join(name: string, at: vector, owned: boolean, home: number?): any
		local key: any = { Name = name }
		Names[key] = name
		clients[key] = { newest = 0, received = {} }
		model.hidden[key] = {}
		front.pinned[key] = home

		local viewer: any = { key = key, slot = nil, position = at, acknowledged = 0, received = 0, target = nil }
		if owned then
			viewer.slot = spawn("Player", at)
		end

		table.insert(viewers, viewer)

		return viewer
	end

	local function leave(viewer: any)
		table.remove(viewers, table.find(viewers, viewer))
		serial.Relay.remove(viewer.key)
		workers.Relay.remove(viewer.key)
	end

	-- Sinks on both sides for a viewer's frames, or its withheld records' with withheld
	local function observe(viewer: any, withheld: boolean)
		local name: string = Names[viewer.key]
		if withheld then
			name = `{name} withheld`
		end

		for _, relay: Side in { serial, workers } do
			relay.frames[name] = relay.frames[name] or {}
			local function sink(_: number, data: buffer)
				table.insert(relay.frames[name], buffer.tostring(data))
			end

			if withheld then
				relay.Taps.observeWithheld(viewer.key, sink)
			else
				relay.Taps.observe(viewer.key, sink)
			end
		end

		if not withheld then
			table.insert(front.observed, viewer.key)
		end
	end

	local players: { any } = {}
	for index: number = 1, PLAYERS do
		local at: vector = CENTER + vector.create((random() - 0.5) * SPREAD, 0, (random() - 0.5) * SPREAD)
		players[index] = join(`Player{index}`, at, true, (index - 1) % WORKERS + 1)
	end

	-- Two teammates, an NPC, a sleeper and a body among them
	model.teams[players[1].slot] = 1
	model.teams[players[2].slot] = 1
	model.teams[players[3].slot] = 2
	spawn("Npc", CENTER + vector.create(10, 0, 0))
	spawn("Sleeper", CENTER + vector.create(-10, 0, 5))
	spawn("Body", CENTER + vector.create(0, 0, -12))

	local function shuffle(share: number)
		for _, viewer: any in players do
			for _, other: any in players do
				if other ~= viewer and other.slot ~= nil then
					model.hidden[viewer.key][other.slot] = random() < share
				end
			end
		end
	end

	shuffle(0.35)

	-- The target's worker is the other one from its moderator's
	local target: any = players[2]
	local moderator: any = join("Moderator", CENTER + vector.create(0, 0, 900), false, 1)
	observe(target, false)
	observe(moderator, false)
	observe(target, true)

	local extras: { any } = {}
	local thrower: any = nil
	local tick: number = 0
	local failure: string? = nil

	local totals: { [string]: number } = {
		hides = 0,
		reveals = 0,
		looks = 0,
		footsteps = 0,
		records = 0,
		changes = 0,
		withheld = 0,
		frames = 0,
		asks = 0,
		throws = 0,
		overfull = 0,
	}

	for run: number = 1, RUNS do
		-- The calls between runs, made alike on both relays
		local function both(member: string, ...: any)
			serial.Relay[member](...)
			workers.Relay[member](...)
		end

		if run == LOOK_RUN then
			both("setLook", players[3].slot, { head = 7, shirt = 65535 })
		elseif run == WATCH_RUN then
			moderator.target = target.key
			both("revealAll", target.key)
		elseif run == INVISIBLE_RUN then
			both("setInvisible", players[5].slot, true)
		elseif run == REVEAL_RUN then
			both("reveal", players[6].slot)
		elseif run == SHOT_RUN then
			both("shotNear", players[1].key, players[7].slot)
		elseif run == VISIBLE_RUN then
			both("setInvisible", players[5].slot, false)
			both("setLook", players[4].slot, { face = 3 })
		elseif run == NEAR_RUN then
			both("setDistance", players[8].key, NEAR_DISTANCE)
		elseif run == SHUFFLE_RUN then
			shuffle(0.5)
		elseif run == OVERFULL_RUN then
			for index: number = 1, EXTRA_WATCHERS do
				local extra: any = join(`Extra{index}`, CENTER, false, nil)
				extra.target = target.key
				table.insert(extras, extra)
			end
		elseif run == REMOVE_RUN then
			for _, extra: any in extras do
				leave(extra)
			end
		elseif run == FAR_RUN then
			both("setDistance", players[8].key, FAR_DISTANCE)
		elseif run == BUSY_RUN then
			model.traffic[players[3].key] = BUSY
		elseif run == RETURN_RUN then
			moderator.target = nil
			both("revealAll", moderator.key)
		elseif run == CALM_RUN then
			model.traffic[players[3].key] = nil
		elseif run == DEATH_RUN then
			despawn(players[7].slot)
			players[7].slot = nil
		elseif run == THROW_RUN then
			thrower = join("Thrower", CENTER, false, 1)
			thrower.slot = INVALID_SLOT

			-- A viewer after it on its worker, whose turn the throw skips there as it does serially
			join("Follower", CENTER + vector.create(5, 0, 5), false, 1)
		elseif run == THROW_RUN + 1 then
			leave(thrower)
		elseif run == LEAVE_RUN then
			leave(players[8])
		elseif run == REJOIN_RUN then
			-- The same key back with its body, its view and its client's reads started afresh
			local rejoined: any = players[8]
			clients[rejoined.key] = { newest = 0, received = {} }
			rejoined.acknowledged = 0
			rejoined.received = 0
			table.insert(viewers, rejoined)
		end

		if run == HELD_RUN then
			states[players[4].slot].held = { item = 12, skin = 3 }
		end

		-- Every body moves and turns, now and then jumping, and each owned viewer stands where its body does
		for slot: number, state: any in states do
			if model.kinds[slot] == PLAYER then
				state.position += vector.create((random() - 0.5) * 2 * STEP, 0, (random() - 0.5) * 2 * STEP)
				state.facing += (random() - 0.5)
				if random() < JUMP then
					state.jumps = (state.jumps + 1) % 4
					state.lands = (state.lands + 1) % 4
				end
			end
		end

		for _, viewer: any in viewers do
			local slot: number? = viewer.slot
			if slot ~= nil and states[slot] then
				viewer.position = states[slot].position
				viewer.look = vector.create(-math.sin(states[slot].facing), 0, -math.cos(states[slot].facing))
			end
		end

		tick += 1
		serial.log = {}
		workers.log = {}

		local serialRan: boolean, serialError: any = pcall(serial.Relay.run, tick, viewers, states, commands)
		local workersRan: boolean, workersError: any = pcall(workers.Relay.run, tick, viewers, states, commands)
		if serialRan ~= workersRan or (not serialRan and `{serialError}` ~= `{workersError}`) then
			failure = `Run {run} ended "{serialError}" serially and "{workersError}" on the workers`
			break
		elseif not serialRan then
			if string.find(`{serialError}`, "watchers one target takes", 1, true) then
				totals.overfull += 1
			else
				totals.throws += 1
			end
		end

		for _, relay: Side in { serial, workers } do
			if relay.Taps.observing then
				relay.Taps.finish(tick)
			end
		end

		local why: string? = compare(`Run {run}'s send or ask`, serial.log, workers.log)
		for name: string, frames: { string } in serial.frames do
			why = why or compare(`Run {run}'s {name} frame`, frames, workers.frames[name])
			totals.frames += #frames
			table.clear(frames)
			table.clear(workers.frames[name])
		end

		-- The front's queries, answered from the copies the results keep level
		local serialCounts: { number } = { serial.Relay.counts() }
		local workerCounts: { number } = { workers.Relay.counts() }
		for at: number = 1, 3 do
			if why == nil and serialCounts[at] ~= workerCounts[at] then
				why = `Run {run}'s count {at} was {serialCounts[at]} serially and {workerCounts[at]} on the workers`
			end
		end

		local everyone: { any } = table.clone(viewers)
		for _, extra: any in extras do
			table.insert(everyone, extra)
		end

		for _, viewer: any in everyone do
			local key: any = viewer.key
			if
				why == nil
				and buffer.tostring(serial.Relay.keyframe(key)) ~= buffer.tostring(workers.Relay.keyframe(key))
			then
				why = `Run {run}'s keyframe for {Names[key]} differs`
			end

			for slot: number = 0, model.top do
				if why == nil and serial.Relay.isSent(key, slot) ~= workers.Relay.isSent(key, slot) then
					why = `Run {run}'s isSent for {Names[key]} and slot {slot} differs`
				end
			end
		end

		-- As a set, since a key that leaves and comes back may come back elsewhere in a relay's walk of its views
		for slot: number = 0, model.top do
			local serialKeys: { any } = serial.Relay.viewersOf(slot)
			local workersKeys: { any } = workers.Relay.viewersOf(slot)
			table.sort(serialKeys, byName)
			table.sort(workersKeys, byName)

			local serialOf: string = label(serialKeys)
			local workersOf: string = label(workersKeys)
			if why == nil and serialOf ~= workersOf then
				why = `Run {run}'s viewersOf slot {slot} was "{serialOf}" serially and "{workersOf}" on the workers`
			end
		end

		if why ~= nil then
			failure = why
			break
		end

		-- What the serial side sent, so the totals show each part of a block was reached
		for _, line: string in serial.log do
			local kind: string = line:match("^(%a+)") :: string
			if kind == "ask" then
				totals.asks += 1
			elseif kind == "withheld" then
				totals.withheld += 1
			end
		end

		-- Each client's acknowledgment of everything it read, which both sides take in the next run
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

		local decoded: any = Block.new()
		for _, line: string in serial.log do
			local bytes: string? = line:match("^block [^ ]* (.*)$")
			if bytes then
				Block.read(buffer.fromstring(bytes), decoded)
				totals.hides += decoded.hideCount
				totals.reveals += decoded.revealCount
				totals.looks += decoded.lookCount
				totals.footsteps += decoded.footstepCount
				totals.records += decoded.recordCount
				totals.changes += decoded.changeCount
			end
		end
	end

	if failure ~= nil then
		return false, failure
	end

	-- Each part the case is for was reached, so the matches above cover it
	for name: string, total: number in totals do
		if total == 0 then
			return false, `No run gave any {name}`
		end
	end

	for kind: number = front.Wire.SHOT_NEAR, front.Wire.REMOVE do
		if not front.queued[kind] then
			return false, `No call of kind {kind} was queued for a worker`
		end
	end

	for worker: number = 1, WORKERS do
		if front.turned[worker] == 0 then
			return false, `Worker {worker} ran no turn`
		end
	end

	if front.resent == 0 then
		return false, "No view was sent whole into an empty copy after the resend"
	end

	-- The stand-in refuses what an Actor's boundary refuses in the settings, as the pool's would
	local refused: { [string]: any } = {
		["a function"] = function () end,
		["an Instance"] = roblox.Instance.new("Folder"),
		["a metatable"] = setmetatable({}, {}),
	}

	for what: string, value: any in refused do
		local took: boolean, why: any = pcall(StandIn.new, 1, "RelayWorkers", nil, { nested = { value } })
		if took or not string.find(`{why}`, "can't cross", 1, true) then
			return false, `The stand-in took settings carrying {what}: {why}`
		end
	end

	return true, nil
end
