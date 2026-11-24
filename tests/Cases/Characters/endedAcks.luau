--[[
    An acknowledgment queued for a character that then ends, and one whose
    player then leaves, is passed over when the stage's fire or the next
    tick's drain comes, the next owner's still goes, and the character woken
    into the ended one's slot is never sent the ended one's bytes
--]]

--!strict
local Environment = require("../../Environment")
local Rig = require("../../Fixtures/Server/Rig")

local Volt = require("@volt")

local CLIENT: string = "src/Network/Client.luau"
local VOLT: string = "ReplicatedStorage.Packages.Volt"
local ACK_BYTES: number = 5 -- An acknowledgment's: an OwnerState's command, tick and queue depth
local BOT_RTT: number = 0.1 -- Seconds, the round trip the bots table needs
local TICKS: number = 6
local END_AT: number = 4 -- The tick whose acknowledgments are still queued when two of them end
local DELAY: number = 100 -- Milliseconds of interpolation delay each Move reports
local FULL: number = 0 -- In a beat's expected messages, a full OwnerState, where an acknowledgment names its command

-- The bot whose character sleeps, the one that leaves, the one that keeps on, and the one woken into the sleeper
local NAMES: { string } = { "ended", "left", "next", "woken" }

-- The first three bodies, built in this order so they take ascending slots and queue in it, on the fixture floor 6
-- studs apart as the spectate case builds its three
local BODIES: { { name: string, x: number, z: number } } = {
	{ name = "ended", x = -6, z = 0 },
	{ name = "left", x = 0, z = 0 },
	{ name = "next", x = 6, z = 0 },
}

--[[
    Where the two end: "drain" leaves END_AT's acknowledgments queued past
    the stage and ends them before the next tick, whose owners' part fires
    the queue, and "window" runs the owners' part at the end of each
    history stage and ends them in END_AT's window before the stage fires
--]]
type Mode = "drain" | "window"

local MODES: { Mode } = { "drain", "window" }

-- What one beat heard: each bot's Owner messages in order, by its name, and the acknowledgments stats counted
type Beat = {
	heard: { [string]: { string } },
	acks: number,
}

local function fresh(): Beat
	local beat: Beat = { heard = {}, acks = 0 }
	for _, name: string in NAMES do
		beat.heard[name] = {}
	end

	return beat
end

--[[
    One run of a mode, every bot but the woken one sending a command from
    the second tick until its character ends: each beat, the stages
    reported as throwing, and whether the woken character took the ended
    one's slot
--]]

local function run(mode: Mode): ({ Beat }, { number | string }, boolean)
	local rig: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.owner = { checks = true }
		settings.bots = { rtt = BOT_RTT, agree = true }
	end)

	local server: any = rig:start()
	local tread: any = rig.tread
	local Characters: any = rig:require(tread.Server.Characters)
	local Command: any = rig:require(tread.Codec.Command)
	local Fields: any = rig:require(tread.Codec.Fields)
	local Move: any = rig:require(tread.Codec.Move)

	local beat: Beat = fresh()
	local keys: { [string]: any } = {}
	local networks: { [string]: any } = {}

	-- Each bot's client side is the generated module on its own transport
	for _, name: string in NAMES do
		local bot: any = rig.mock:addBot(name)
		local transport: any = rig.mock:connectBot(bot)
		local network: any = Environment.load(CLIENT, {
			[VOLT] = {
				start = function (schema: any): any
					return Volt.start(schema, transport)
				end,
			},
		})

		network.Owner.on(function (data: buffer)
			table.insert(beat.heard[name], buffer.tostring(data))
		end)

		network.flush()
		keys[name] = bot
		networks[name] = network
	end

	rig:deliver()

	local handles: { [string]: any } = {}
	for _, body: { name: string, x: number, z: number } in BODIES do
		handles[body.name] = server:create(keys[body.name], rig:at(body.x, body.z))
	end

	server:stats()

	-- The ended character sleeps and the woken bot wakes it, so its character takes the slot, and the left bot leaves
	local function finish()
		local sleeper: any = handles.ended:sleep()
		rig.mock:removeBot(keys.left)
		handles.woken = sleeper:wake(keys.woken)
	end

	-- The stage's own fire, passed over on END_AT's tick in the drain mode, as a relay path that never reached it would
	local holding: boolean = false
	local acks: any = Characters.acks
	Characters.acks = function ()
		if not holding then
			acks()
		end
	end

	local ticking: number = 0
	if mode == "window" then
		local history: any = Characters.history
		Characters.history = function (tick: number, relayTick: number)
			history(tick, relayTick)
			Characters.sendOwners(relayTick)

			if ticking == END_AT then
				finish()
			end
		end
	end

	local layout: any = Fields.compile(rig.shared.fields)
	local limits: any = { lean = rig.shared.step.lean, headCone = rig.shared.step.headCone }
	local command: any = Command.new()
	command.fields = { slot = 0, shots = {} }
	local move: any = Move.new()
	local beats: { Beat } = {}

	for tick: number = 1, TICKS do
		beat = fresh()

		-- From the second tick, since the server files no command before its first
		if tick > 1 then
			command.number = tick
			Move.encode(move, { command }, 1, 0, 0, DELAY, layout, limits)

			for _, body: { name: string, x: number, z: number } in BODIES do
				if body.name == "next" or tick <= END_AT then
					local network: any = networks[body.name]
					network.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
					network.flush()
				end
			end

			rig:deliver()
		end

		ticking = tick
		holding = mode == "drain" and tick == END_AT
		rig:tick(1)
		rig:deliver()

		beat.acks = server:stats().ownerAcks
		beats[tick] = beat

		if mode == "drain" and tick == END_AT then
			holding = false
			finish()
		end
	end

	local woken: any = handles.woken
	local reused: boolean = woken ~= nil and woken._slot == handles.ended._slot

	return beats, rig:reported("stage"), reused
end

--[[
    The messages a bot is due on a tick in a mode, each the command its
    acknowledgment names, or FULL. The first tick's stand-ins go in full,
    then each command is acknowledged until END_AT, whose acknowledgments
    the ended and left bots never get and the next bot gets at the stage's
    fire in the window mode and first in the next tick's drain otherwise.
    The woken character's first OwnerState comes the tick after END_AT,
    and it sends no command, so each of its own is full
--]]

local function due(mode: Mode, tick: number, name: string): { number }
	if name == "woken" then
		return tick > END_AT and { FULL } or {}
	elseif tick == 1 then
		return { FULL }
	elseif tick < END_AT then
		return { tick }
	elseif name ~= "next" then
		return {}
	elseif tick == END_AT then
		return mode == "window" and { tick } or {}
	elseif tick == END_AT + 1 and mode == "drain" then
		return { END_AT, tick }
	end

	return { tick }
end

-- Why one bot's messages in a beat are not the ones due, or nil
local function check(heard: { string }, expected: { number }, name: string, tick: number): string?
	if #heard ~= #expected then
		return `tick {tick} sent the {name} bot {#heard} Owner messages, not {#expected}`
	end

	for index: number, named: number in expected do
		local message: string = heard[index]
		if named == FULL and #message <= ACK_BYTES then
			return `tick {tick} sent the {name} bot an acknowledgment as message {index}, where a full one goes`
		elseif named ~= FULL then
			local command: number = #message == ACK_BYTES and buffer.readu16(buffer.fromstring(message), 0) or -1
			if command ~= named then
				local sent: string = `{#message} B naming {command}`
				return `tick {tick}'s message {index} to the {name} bot was {sent}, not command {named}'s acknowledgment`
			end
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	for _, mode: Mode in MODES do
		local beats: { Beat }, threw: { number | string }, reused: boolean = run(mode)
		if not reused then
			return false, `In the {mode} mode, the woken character didn't take the ended one's slot`
		end

		for tick: number = 1, TICKS do
			local beat: Beat = beats[tick]
			local counted: number = 0

			for _, name: string in NAMES do
				local expected: { number } = due(mode, tick, name)
				local wrong: string? = check(beat.heard[name], expected, name, tick)
				if wrong then
					return false, `In the {mode} mode, {wrong}`
				end

				for _, named: number in expected do
					if named ~= FULL then
						counted += 1
					end
				end
			end

			-- The left bot hears nothing once it has gone, so only the count shows an acknowledgment fired to it
			if beat.acks ~= counted then
				return false,
					`In the {mode} mode, stats counted {beat.acks} acknowledgments on tick {tick}, not {counted}`
			end
		end

		if #threw > 0 then
			return false, `In the {mode} mode, the {threw[1]} stage threw {#threw} times`
		end
	end

	return true, nil
end
