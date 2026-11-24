--[[
    A server for the split's cases, Lockstep's side on stand-in workers or in
    process with relay.split set at start, run three Heartbeats a tick with
    each one's flags kept, each round's dispatch marked and the players' Moves
--]]

--!strict
local SplitSide = {}

local Environment = require("../../Environment")
local Lockstep = require("./Lockstep")

local WORKERS: number = 2
local TIMEOUT: number = 60 -- Seconds, far past when any round here lands
local BEATS: number = 3 -- Heartbeats a tick, as at 60 Heartbeats a second and 20 ticks
local THIRD: number = 1 / BEATS -- A Heartbeat's share of a tick
local OFFSET: number = 5 / 6 -- The first Heartbeat's share, so each tick begins on the first of its three, past its edge
local CALM: number = 4 -- The first tick the split defers, once the tick loop has counted 3 calm ticks before it
local STEP: number = 1 / 64 -- Seconds the stand-in clock moves a Heartbeat, a power of two so its sums stay exact
local BASE: number = 1000 -- The stand-in clock's reading before the first Heartbeat, seconds
local DELAY: number = 100 -- Milliseconds of interpolation delay each Move reports
local CLIENT: string = "src/Network/Client.luau" -- Tread's generated client module, which a second player loads
local VOLT: string = "ReplicatedStorage.Packages.Volt"

-- What a side is built with
export type Options = {
	split: boolean, -- relay.split at start
	workers: boolean, -- Whether the relay runs on stand-in workers, else in process
	checks: boolean?, -- owner.checks, with each player taken as agreeing on every command it files
	-- Whether the server module's os.clock, and the clock Commands times queue waits on, is a stand-in that moves
	-- STEP a Heartbeat
	clock: boolean?,
}

-- An Owner message or relay block a second player heard, with the Heartbeat it came in
export type Heard = {
	kind: string, -- "owner" or "relay"
	tick: number, -- The tick at its byte 2
	bytes: number,
	beat: number,
}

-- A second player on the side's mock, with a copy of Tread's client module of its own
export type Listener = {
	key: any, -- The player
	network: any,
	heard: { Heard },
}

export type Driven = {
	side: Lockstep.Side,
	flags: { number }, -- Each Heartbeat's flags, by its number, the first Heartbeat's included
	clock: { now: number }?, -- The stand-in clock's reading, while one answers
	tick: number, -- The newest tick SplitSide.ticks ran
	full: { [number]: boolean }, -- The ticks the client files no command for, so each goes as a whole OwnerState
	deliver: boolean, -- Whether each Heartbeat's rounds run on the stand-in workers after it, true from start
	listeners: { Listener }, -- The second players SplitSide.ticks files commands for, as for the client
	file: (tick: number) -> (), -- Files the client's command for a tick, with a check of 0
	fileOn: (network: any, tick: number) -> (), -- Files a command for a tick on a player's network, with a check of 0
}

SplitSide.THIRD = THIRD
SplitSide.CALM = CALM
SplitSide.STEP = STEP

--[[
    A side built as options give, after one Heartbeat of OFFSET, so the
    first tick begins on the next. Each round sent to the first worker
    marks the side's arrivals as "dispatch <tick>"
--]]

function SplitSide.new(options: Options): Driven
	local relay: Lockstep.Relay? = options.workers and { workers = WORKERS, timeout = TIMEOUT } or nil
	local side: Lockstep.Side = Lockstep.side(relay, nil, function (settings: any)
		settings.relay = table.clone(settings.relay)
		settings.relay.split = options.split

		if options.checks then
			settings.owner = { checks = true }
			settings.bots.agree = true
		end
	end)

	local clock: { now: number }? = nil
	if options.clock then
		local reading: { now: number } = { now = BASE }
		clock = reading

		local function now(): number
			return reading.now
		end

		-- The server module's own environment, the one table the test environment gave it, holds the os it reads
		local scope: any = getfenv(side.rig.Server.start)
		scope.os = { clock = now }
		side.rig:require(side.rig.tread.Server.Commands).setClock(now)
	end

	local pool: any = side.pool
	if pool then
		local send: any = pool.send
		pool.send = function (self: any, worker: number, round: number, shared: buffer, own: buffer)
			if worker == 1 then
				local ran: number = side.Tick.counts()
				table.insert(side.arrivals, `dispatch {ran}`)
			end

			send(self, worker, round, shared, own)
		end
	end

	local tread: any = side.rig.tread
	local Command: any = side.rig:require(tread.Codec.Command)
	local Fields: any = side.rig:require(tread.Codec.Fields)
	local Move: any = side.rig:require(tread.Codec.Move)
	local layout: any = Fields.compile(side.rig.shared.fields)
	local limits: any = { lean = side.rig.shared.step.lean, headCone = side.rig.shared.step.headCone }
	local command: any = Command.new()
	command.fields = { slot = 0, shots = {} }
	local move: any = Move.new()

	-- Flushed at once, so the Move is written before the shared tables are filled again
	local function fileOn(network: any, tick: number)
		command.number = tick
		Move.encode(move, { command }, 1, 0, 0, DELAY, layout, limits)
		network.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
		network.flush()
	end

	local driven: Driven = {
		side = side,
		flags = {},
		clock = clock,
		tick = 0,
		full = {},
		deliver = true,
		listeners = {},

		file = function (tick: number)
			fileOn(side.client, tick)
			side.rig:deliver()
		end,

		fileOn = fileOn,
	}

	SplitSide.beat(driven, OFFSET)

	return driven
end

--[[
    A second player joining the side's mock with a copy of Tread's client
    module of its own, keeping each Owner message and relay block it hears
    with its Heartbeat, whose commands SplitSide.ticks files from then on
--]]

function SplitSide.listener(driven: Driven): Listener
	local rig: any = driven.side.rig
	local volt: any = rig.globals.require(rig.globals.game:GetService("ReplicatedStorage").Packages.Volt)
	local network: any = Environment.load(CLIENT, { [VOLT] = volt })
	local heard: { Heard } = {}

	-- Heard while the Heartbeat's delivery runs, before its flags are kept
	local function keep(kind: string, data: buffer)
		table.insert(
			heard,
			{ kind = kind, tick = buffer.readu16(data, 2), bytes = buffer.len(data), beat = #driven.flags + 1 }
		)
	end

	network.Owner.on(function (data: buffer)
		keep("owner", data)
	end)

	network.Relay.on(function (data: buffer)
		keep("relay", data)
	end)

	network.flush()
	rig:deliver()

	local listener: Listener = { key = rig.mock.players[#rig.mock.players], network = network, heard = heard }
	table.insert(driven.listeners, listener)

	return listener
end

--[[
    One Heartbeat of a share of a tick: the stand-in clock moved first, the
    Heartbeat's flags kept, and, while deliver is true, the rounds sent on it
    run on the stand-in workers after, so the next Heartbeat's poll finds them
--]]

function SplitSide.beat(driven: Driven, share: number)
	local clock: { now: number }? = driven.clock
	if clock then
		clock.now += STEP
	end

	Lockstep.beat(driven.side, share)

	local beats: any = driven.side.Tick.heartbeats()
	table.insert(driven.flags, beats.flags[(beats.head - 1) % #beats.flags + 1])

	local pool: any = driven.side.pool
	if pool and driven.deliver then
		pool:deliver()
	end
end

--[[
    Runs count ticks of three Heartbeats each, the client's command and each
    listener's filed before each tick but the first, the client's but for
    full's
--]]

function SplitSide.ticks(driven: Driven, count: number)
	for _ = 1, count do
		driven.tick += 1
		if driven.tick > 1 and not driven.full[driven.tick] then
			driven.fileOn(driven.side.client, driven.tick)
		end

		if driven.tick > 1 then
			for _, listener: Listener in driven.listeners do
				driven.fileOn(listener.network, driven.tick)
			end
		end

		if driven.tick > 1 and (#driven.listeners > 0 or not driven.full[driven.tick]) then
			driven.side.rig:deliver()
		end

		for _ = 1, BEATS do
			SplitSide.beat(driven, THIRD)
		end
	end
end

-- The number of a tick's Heartbeat, place 1 its own and 2 and 3 the two after, while every tick has run three
function SplitSide.place(tick: number, place: number): number
	return BEATS * (tick - 1) + 1 + place
end

-- Each Heartbeat's arrivals, the ones its delivery brought, by the Heartbeat's number
function SplitSide.segments(side: Lockstep.Side): { { string } }
	local split: { { string } } = {}

	for _, arrival: string in side.arrivals do
		if arrival == "beat" then
			table.insert(split, {})
		elseif #split > 0 then
			table.insert(split[#split], arrival)
		end
	end

	return split
end

-- The Heartbeats whose delivery brought an arrival of a kind for a tick, and the bytes each held, 0 with none given
function SplitSide.found(split: { { string } }, kind: string, tick: number): ({ number }, { number })
	local beats: { number } = {}
	local sizes: { number } = {}

	for beat: number, arrived: { string } in split do
		for _, arrival: string in arrived do
			local named: string?, at: string?, bytes: string? = arrival:match("^(%a+) (%d+) ?(%d*)$")
			if named == kind and tonumber(at) == tick then
				table.insert(beats, beat)
				table.insert(sizes, tonumber(bytes) or 0)
			end
		end
	end

	return beats, sizes
end

-- The Heartbeats a listener heard an arrival of a kind for a tick on, and the bytes each held
function SplitSide.heardOf(listener: Listener, kind: string, tick: number): ({ number }, { number })
	local beats: { number } = {}
	local sizes: { number } = {}

	for _, heard: Heard in listener.heard do
		if heard.kind == kind and heard.tick == tick then
			table.insert(beats, heard.beat)
			table.insert(sizes, heard.bytes)
		end
	end

	return beats, sizes
end

return SplitSide
