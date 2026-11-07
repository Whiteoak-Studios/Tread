--[[
    The server handle a game starts Tread's server with: both tables checked,
    Tread's own Volt endpoints bound at the game's rates, the tick started on
    its stages, and every member a game calls on the server
--]]

--!strict
local Server = {}
Server.__index = Server

local Characters = require(script.Characters)
local Commands = require(script.Commands)
local Config = require(script.Parent.Config)
local Connections = require(script.Connections)
local Constants = require(script.Parent.Constants)
local Fields = require(script.Parent.Codec.Fields)
local History = require(script.History)
local Relay = require(script.Relay)
local Reliable = require(script.Parent.Codec.Reliable)
local Reports = require(script.Reports)
local Slots = require(script.Slots)
local Tick = require(script.Tick)
local Types = require(script.Parent.Types)

local SLOTS: number = Constants.SLOTS
local SLOT_ENTRIES: number = Constants.MAX_SLOT_ENTRIES -- The most entries one Slots message carries
local TICK_WRAP: number = 2 ^ 32 -- The Shared message carries the server's tick in a u32
local P95: number = 0.95 -- The share of a stage's times, or of the players' traffic, its p95 is at or above

-- Volt's failures on Tread's scope by its kind, each reported under its own name, but for decode, a Move Volt refused,
-- which is schema
local FAILURES: { [string]: Reports.Kind } = {
	decode = "schema",
	rate = "rate",
	packet = "packet",
	handshake = "handshake",
	listener = "listener",
	handler = "handler",
	outgoing = "outgoing",
	queue = "queue",
	departed = "departed",
}

type Bot = Types.Bot
type Character = Characters.Character
type Key = Player | Bot
type Landed = Characters.Landed
type Layout = Fields.Layout
type Network = typeof(require(script.Parent.Network.Server))
type Npc = Characters.Npc
type Sample = Characters.Sample
type ServerSettings = Config.ServerSettings
type Shared = Config.Shared
type Target = Characters.Target
type Run = Tick.Run

-- What a report callback a game connects is handed
type Report = (player: Key?, kind: string, measurement: number | string) -> ()

-- One stage's times in a stats read, in seconds
type Times = {
	last: number,
	p95: number,
}

type Fields = {
	_network: Network, -- Tread's own generated server module, required at start
}

local Started: boolean = false
local SimulationRate: number = 0 -- From the shared table at start, Hz
local RelayRate: number = 0

local Joined: { Key } = {} -- Every player and bot Volt has set up on Tread's scope, which the slot table goes to

-- One slot table entry, carried alone in each change's message and rewritten for the next
local ChangeEntry: Reliable.Entry = { slot = 0, taken = nil :: { rig: Reliable.Rig, player: Instance? }? }
local Change: { Reliable.Entry } = { ChangeEntry }

-- The server's counters, each added to where its event is seen, which a stats read gives the change of since the last
local StandIns: number = 0
local Late: number = 0
local BytesOut: number = 0 -- The bytes of every buffer the server's own sends handed Volt
local ReportCounts: { [string]: number } = {} -- Every report by kind

-- What each counter read at the last stats read, and when it was
local ReadAt: number = os.clock()
local ReadTicks: number = 0
local ReadDropped: number = 0
local ReadStandIns: number = 0
local ReadLate: number = 0
local ReadSent: number = 0
local ReadCut: number = 0
local ReadBytes: number = 0
local ReadReports: { [string]: number } = {}

local RelayFailure: string = "" -- What the relay's own work last threw, raised again once the flush has gone

-- Keeps where the relay's error was raised, with its stack, for the relay stage to raise after its flush
local function keepFailure(message: any)
	RelayFailure = debug.traceback(tostring(message), 2)
end

-- The key of the rate each endpoint the server hears takes in the server settings: its name, its first letter lowered
local function rateKey(name: string): string
	return `{string.lower(string.sub(name, 1, 1))}{string.sub(name, 2)}`
end

--[[
    Sets the rate of every endpoint Tread's schema has the server hear from
    the server settings, and errors naming the first one they give none
--]]

local function bindRates(network: Network, server: ServerSettings)
	-- The settings' rates by endpoint name, which Config has checked hold one for each endpoint it knows
	local rates: any = server.rates

	for name: string, handle: any in network.events do
		if handle.on == nil then
			continue
		end

		local key: string = rateKey(name)
		local rate: any = rates[key]
		if rate == nil then
			error(`server.rates.{key} expected the {name} endpoint's rate, since Tread's server hears it`, 3)
		end

		network.rate(name, rate.perSecond, rate.burst)
	end
end

-- The relay tick a simulation tick starts, nil for one that starts none, as at a 60 Hz simulation with a 30 Hz relay
local function relayTickOf(tick: number): number?
	local relayTick: number = math.floor(tick * RelayRate / SimulationRate)
	if relayTick == math.floor((tick - 1) * RelayRate / SimulationRate) then
		return nil
	end

	return relayTick
end

--[[
    Sends a player or bot who just joined the slot table: every taken
    slot's entry, at most SLOT_ENTRIES a message
--]]

local function sendSlotTable(network: Network, key: Key)
	local entries: { Reliable.Entry } = {}

	for slot: number = 0, SLOTS - 1 do
		local generation: number, entry: Slots.Entry? = Slots.get(slot)
		if entry then
			local written: Reliable.Entry = { slot = 0, taken = nil }
			Reliable.write(written, slot, generation, entry.rig, entry.player)
			table.insert(entries, written)

			if #entries == SLOT_ENTRIES then
				network.Slots.fire(key, entries)
				entries = {}
			end
		end
	end

	if #entries > 0 then
		network.Slots.fire(key, entries)
	end
end

-- Counts every report Tread raises by kind, and the stand-ins and late commands among them, for stats
local function count(_: Key?, kind: Reports.Kind, _: number | string)
	if kind == "standIn" then
		StandIns += 1
	elseif kind == "late" then
		Late += 1
	end

	local counted: number = ReportCounts[kind] or 0
	ReportCounts[kind] = counted + 1
end

-- The value a share P95 of the samples are at or under, by nearest rank, 0 for none. It sorts the list in place
local function percentile(samples: { number }): number
	if #samples == 0 then
		return 0
	end

	table.sort(samples)

	return samples[math.ceil(#samples * P95)]
end

--- Starts Tread's server with the game's shared table and server settings,
--- checking both first and erroring on the first key missing or wrong. It
--- binds Tread's own Volt endpoints at the rates the settings give, starts
--- the tick on Heartbeat and returns the server handle. It runs once a
--- server, requires Tread's generated server module only inside it, and
--- never yields
--- @function start
--- @within Server
--- @param shared Shared
--- @param server ServerSettings
--- @return Server

function Server.start(shared: Shared, server: ServerSettings): Self
	if Started then
		error("Server.start runs once a server, and it has already run", 2)
	end

	Config.server(shared, server)
	local layout: Layout = Fields.compile(shared.fields)

	local network: Network = require(script.Parent.Network.Server)
	bindRates(network, server)

	Started = true
	SimulationRate = shared.rates.simulation
	RelayRate = shared.rates.relay

	Slots.start(server.slots.reserve)
	Connections.start(server.rewind.rttSmoothing, server.bots)
	Commands.start(shared, layout)
	History.start(shared, server)

	Characters.start({
		shared = shared,
		server = server,
		layout = layout,

		sendOwner = function (key: Key, data: buffer)
			network.Owner.fire(key, data)
			BytesOut += buffer.len(data)
		end,
	})

	Relay.start({ shared = shared, server = server, layout = layout }, function (key: Key, data: buffer)
		network.Relay.fire(key, data)
		BytesOut += buffer.len(data)
	end, function (key: Key): number
		local sent: number, pending: number = network.traffic(key)

		return sent + pending
	end, function (_: Relay.Viewer, _: number): boolean
		-- Hides nothing until anti-ESP joins the tick
		return false
	end)

	local hash: number = Config.hash(shared)

	-- Each lives as long as the server
	network.onFailure(function (player: Key?, kind: string, detail: string)
		local report: Reports.Kind? = FAILURES[kind]
		if report then
			Reports.fire(player, report, detail)
		else
			warn(`Volt failed on Tread's scope with {kind}, which Tread reports under no kind: {detail}`)
		end
	end)

	network.Move.on(Characters.file)

	network.onJoin(function (key: Key)
		local ran: number = Tick.counts()
		table.insert(Joined, key)

		network.Shared.fire(key, hash, ran % TICK_WRAP)
		sendSlotTable(network, key)
	end)

	network.onLeave(function (key: Key)
		local index: number? = table.find(Joined, key)
		if index then
			table.remove(Joined, index)
		end

		Characters.leave(key)
	end)

	Slots.onChange(function (slot: number, generation: number, _: Slots.Entry?, current: Slots.Entry?)
		if current then
			Reliable.write(ChangeEntry, slot, generation, current.rig, current.player)
		else
			Reliable.write(ChangeEntry, slot, generation, nil, nil)
		end

		network.Slots.fireList(Joined, Change)
	end)

	Reports.connect(count)

	Tick.start(shared.rates.simulation, server.catchUp, {
		{
			name = "decode",
			run = function (_: number)
				Characters.decode()
			end,
		},
		{ name = "simulate", run = Characters.simulate },
		{ name = "npcs", run = Characters.npcs },
		{
			name = "history",
			run = function (tick: number)
				local relayTick: number? = relayTickOf(tick)
				if relayTick then
					Characters.history(relayTick)
				end
			end,
		},
		{
			name = "relay",
			run = function (tick: number)
				local relayTick: number? = relayTickOf(tick)
				if not relayTick then
					return
				end

				-- Whiteoak TODO: one flush sends every player's batch on the relay tick; staggering even slots and
				-- odd ones across two Heartbeats needs a flush per player from Volt, a Volt task if G3 shows the need
				local ran: boolean = xpcall(Characters.relay, keepFailure, relayTick)
				network.flush()

				if not ran then
					error(RelayFailure, 0)
				end
			end,
		},
	})

	return setmetatable({ _network = network }, Server)
end

--- Builds a character in a free slot for a player or one of Volt's bots,
--- whose server must give bots.rtt, its feet at the CFrame's position and
--- facing along its look. Errors, naming the held-back count, when no slot
--- is free
--- @method create
--- @within Server
--- @param player Player | Bot
--- @param at CFrame
--- @return Character

function Server.create(self: Self, player: Key, at: CFrame): Character
	return Characters.create(player, at)
end

--- Builds an NPC body in a slot with no player, awake, its feet at the
--- CFrame's position and facing along its look
--- @method createNpc
--- @within Server
--- @param at CFrame
--- @return Npc

function Server.createNpc(self: Self, at: CFrame): Npc
	return Characters.createNpc(at)
end

--- Every live character and NPC, in a list of its own
--- @method getAll
--- @within Server
--- @return { Target }

function Server.getAll(self: Self): { Target }
	return Characters.getAll()
end

--- The names of the players, and of the bots, whose characters stand within
--- range of a point, the edge included
--- @method near
--- @within Server
--- @param at Vector3
--- @param range number
--- @return { string }

function Server.near(self: Self, at: Vector3, range: number): { string }
	return Characters.near(at, range)
end

--- The NPCs within range of a point, the edge included
--- @method npcsNear
--- @within Server
--- @param at Vector3
--- @param range number
--- @return { Npc }

function Server.npcsNear(self: Self, at: Vector3, range: number): { Npc }
	return Characters.npcsNear(at, range)
end

--- Whether a box overlaps the hull of any live character or NPC, for the
--- game's placement and door checks
--- @method overlaps
--- @within Server
--- @param cframe CFrame
--- @param size Vector3
--- @return boolean

function Server.overlaps(self: Self, cframe: CFrame, size: Vector3): boolean
	return Characters.overlaps(cframe, size)
end

--- The history read for a hit test: the target at a render time in relay
--- ticks, its hit shapes placed, or nil for a time the history no longer
--- holds, one spent in Noclip or Parked, or a target destroyed. The command
--- time places a platform rider, and no body rides one yet. The sample is
--- the target's own table, which its next read rewrites
--- @method sampleAt
--- @within Server
--- @param target Target
--- @param renderTime number
--- @param commandTime number?
--- @return Sample?

function Server.sampleAt(self: Self, target: Target, renderTime: number, commandTime: number?): Sample?
	if commandTime ~= nil and type(commandTime) ~= "number" then
		error(
			`server:sampleAt takes the command time as a number of relay ticks or nil, not a {typeof(commandTime)}`,
			2
		)
	end

	return Characters.sampleAt(target, renderTime)
end

--- The render time a shot rewinds to and whether its claimed time was
--- inside the band, from the command the shot rode in, one of the last 8
--- its character stepped, and the claimed render time in relay ticks with
--- its fraction, whose whole ticks may be their low 16 bits. A claim outside
--- the band is reported as band with its offset
--- @method rewindFor
--- @within Server
--- @param player Player | Bot
--- @param command number
--- @param renderTime number
--- @return number
--- @return boolean

function Server.rewindFor(self: Self, player: Key, command: number, renderTime: number): (number, boolean)
	return Characters.rewindFor(player, command, renderTime)
end

--- Registers a ladder and gives back the closure that removes it
--- @method addLadder
--- @within Server
--- @param cframe CFrame
--- @param size Vector3
--- @return () -> ()

function Server.addLadder(self: Self, cframe: CFrame, size: Vector3): () -> ()
	return Characters.addLadder(cframe, size)
end

--- The players currently sent a target, so a cue attached to it reaches
--- only the screens that show it
--- @method viewersOf
--- @within Server
--- @param target Target
--- @return { Player }

function Server.viewersOf(self: Self, target: Target): { Player }
	return Characters.viewersOf(target)
end

--- A shooter's bullet passed near a viewer, which raises the rate the
--- viewer is sent the shooter at for a time
--- @method reportShotNear
--- @within Server
--- @param shooter Player | Bot
--- @param viewer Player | Bot

function Server.reportShotNear(self: Self, shooter: Key, viewer: Key)
	Characters.reportShotNear(shooter, viewer)
end

--- Adds a game stage to every tick from the next, directly after the stage
--- named after, whose run gets the tick as the server counts it. It runs
--- under a pcall of its own, and an error is reported as stage with its name
--- @method addStage
--- @within Server
--- @param name string
--- @param after string
--- @param run (tick: number) -> ()

function Server.addStage(self: Self, name: string, after: string, run: Run)
	Tick.addStage(name, after, run)
end

--- Everything a viewer is sent now, as one buffer a clip ring starts from
--- @method keyframe
--- @within Server
--- @param viewer Player | Bot
--- @return buffer

function Server.keyframe(self: Self, viewer: Key): buffer
	return Relay.keyframe(viewer)
end

--- Calls back on every report Tread raises, with the player or bot it is
--- about, nil for an NPC or the server itself, its kind and its measurement.
--- Returns the closure that disconnects the callback
--- @method onReport
--- @within Server
--- @param callback (player: (Player | Bot)?, kind: string, measurement: number | string) -> ()
--- @return () -> ()

function Server.onReport(self: Self, callback: Report): () -> ()
	return Reports.connect(callback)
end

--- Calls back on every landing that counted, a character's or an NPC's,
--- with the target, the speed it met the ground at, the ground's material,
--- water for a landing in water, and the fall's apex. Returns the closure
--- that disconnects the callback
--- @method onLanded
--- @within Server
--- @param callback (target: Target, speed: number, material: Enum.Material, apex: number) -> ()
--- @return () -> ()

function Server.onLanded(self: Self, callback: Landed): () -> ()
	return Characters.onLanded(callback)
end

--- Tread's aggregate numbers, with no endpoint and no signal, for the game
--- to read once a second: each stage's last time and p95 over 10 s, the
--- live characters, awake NPCs and bodies, the history's bytes, the largest
--- and p95 traffic to a player over the last second, and, as the change
--- since the last read, the ticks run and dropped, stand-ins, late commands,
--- records sent and cut, Tread's bytes out and the reports by kind. It
--- holds no position and no name
--- @method stats
--- @within Server
--- @return { [string]: any }

function Server.stats(self: Self): { [string]: any }
	local now: number = os.clock()
	local ran: number, dropped: number = Tick.counts()
	local sent: number, cut: number = Relay.counts()
	local players: number, awake: number = Characters.counts()

	local stages: { [string]: Times } = {}
	for _, stage: Tick.Stage in Tick.stages() do
		local times: { number } = table.move(stage.times, 1, stage.held, 1, {})
		stages[stage.name] = { last = stage.last, p95 = percentile(times) }
	end

	local traffic: { number } = {}
	for _, key: Key in Joined do
		local bytes: number = self._network.traffic(key)
		table.insert(traffic, bytes)
	end

	local trafficP95: number = percentile(traffic)
	local largest: number = traffic[#traffic] or 0

	local reports: { [string]: number } = {}
	for kind: string, total: number in ReportCounts do
		local before: number = ReadReports[kind] or 0
		reports[kind] = total - before
		ReadReports[kind] = total
	end

	local read: { [string]: any } = {
		seconds = now - ReadAt,
		stages = stages,
		ticks = ran - ReadTicks,
		dropped = dropped - ReadDropped,
		players = players,
		npcs = awake,
		bodies = Slots.count("Body"),
		standIns = StandIns - ReadStandIns,
		late = Late - ReadLate,
		recordsSent = sent - ReadSent,
		recordsCut = cut - ReadCut,
		bytesOut = BytesOut - ReadBytes,
		trafficLargest = largest,
		trafficP95 = trafficP95,
		historyBytes = History.bytes(),
		reports = reports,
	}

	ReadAt = now
	ReadTicks = ran
	ReadDropped = dropped
	ReadStandIns = StandIns
	ReadLate = Late
	ReadSent = sent
	ReadCut = cut
	ReadBytes = BytesOut

	return read
end

export type Server = Self
type Self = typeof(setmetatable({} :: Fields, Server))

return Server
