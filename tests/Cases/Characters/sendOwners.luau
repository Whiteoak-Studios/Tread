--[[
    The owners' part run early for each relay tick, before the relay stage,
    gives each owner one Owner message, one ping sample, one feed and one
    tap, and every byte the owners, the moderator and the taps get is the
    relay alone's, where the relay runs that part itself
--]]

--!strict
local Environment = require("../../Environment")
local Rig = require("../../Fixtures/Server/Rig")

local Volt = require("@volt")

local CLIENT: string = "src/Network/Client.luau"
local VOLT: string = "ReplicatedStorage.Packages.Volt"
local ACK_BYTES: number = 5 -- An acknowledgment's: an OwnerState's command, tick and queue depth
local BOT_RTT: number = 0.1 -- Seconds, the round trip the bots table needs
local TICKS: number = 8
local DELAY: number = 100 -- Milliseconds of interpolation delay each Move reports
local MODERATOR_X: number = -28 -- Where each body is built, clear of the fixture's obstacles
local BOT_X: number = -20
local START_Z: number = 10

-- The moderator, Volt's mock player sending no command, so its every OwnerState goes in full, and the bot it
-- spectates, which agrees under bots.agree, so its commands are acknowledged
local NAMES: { string } = { "moderator", "bot" }

-- What one beat heard and counted, by the name of the key each is for
type Beat = {
	owners: { [string]: { string } }, -- The Owner messages each client heard, in order
	feeds: { string }, -- The feeds the moderator heard
	taps: { [string]: { string } }, -- The tap frames each key's sink was handed
	samples: { [string]: number }, -- Each connection's ping samples
	fed: { [string]: number }, -- Each key's OwnerState handed to its feed
	tapped: { [string]: number }, -- And to the taps
	before: number, -- The ping samples taken before the relay stage began
}

local function fresh(): Beat
	local beat: Beat = { owners = {}, feeds = {}, taps = {}, samples = {}, fed = {}, tapped = {}, before = 0 }

	for _, name: string in NAMES do
		beat.owners[name] = {}
		beat.taps[name] = {}
		beat.samples[name] = 0
		beat.fed[name] = 0
		beat.tapped[name] = 0
	end

	return beat
end

--[[
    One run of the rig, with the owners' part called at the end of each
    relay tick's history stage when early, or left to the relay stage:
    each beat's messages and counts, and the stages reported as throwing
--]]

local function run(early: boolean): ({ Beat }, { number | string })
	local rig: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.owner = { checks = true }
		settings.bots = { rtt = BOT_RTT, agree = true }
	end)

	local server: any = rig:start()
	local tread: any = rig.tread
	local Characters: any = rig:require(tread.Server.Characters)
	local Commands: any = rig:require(tread.Server.Commands)
	local Connections: any = rig:require(tread.Server.Connections)
	local Spectate: any = rig:require(tread.Server.Spectate)
	local Taps: any = rig:require(tread.Server.Taps)
	local Command: any = rig:require(tread.Codec.Command)
	local Fields: any = rig:require(tread.Codec.Fields)
	local Move: any = rig:require(tread.Codec.Move)

	-- Every queue wait on a clock that stands still, so each tap frame's view lag is the same in both runs
	Commands.setClock(function (): number
		return 0
	end)

	local beat: Beat = fresh()
	local names: { [any]: string } = {}

	local client: any = rig:require(tread.Network.Client)
	client.Owner.on(function (data: buffer)
		table.insert(beat.owners.moderator, buffer.tostring(data))
	end)

	client.Feed.on(function (data: buffer)
		table.insert(beat.feeds, buffer.tostring(data))
	end)

	client.flush()
	rig:deliver()

	-- The bot's client side is the generated module on its transport
	local bot: any = rig.mock:addBot("Bot")
	local transport: any = rig.mock:connectBot(bot)
	local network: any = Environment.load(CLIENT, {
		[VOLT] = {
			start = function (schema: any): any
				return Volt.start(schema, transport)
			end,
		},
	})

	network.Owner.on(function (data: buffer)
		table.insert(beat.owners.bot, buffer.tostring(data))
	end)

	network.flush()
	rig:deliver()

	local moderator: any = rig.mock.players[1]
	names[moderator] = "moderator"
	names[bot] = "bot"

	server:create(moderator, rig:at(MODERATOR_X, START_Z))
	local target: any = server:create(bot, rig:at(BOT_X, START_Z))
	server:spectate(moderator, target)

	for key: any, name: string in names do
		server:observe(key, function (_: number, data: buffer)
			table.insert(beat.taps[name], buffer.tostring(data))
		end)

		-- Counted before it runs, so a second sample in a tick, which throws, is counted too
		local connection: any = Connections.get(key)
		local sample: any = connection.sample
		connection.sample = function (self: any, seconds: number)
			beat.samples[name] += 1
			sample(self, seconds)
		end
	end

	local feed: any = Spectate.feed
	Spectate.feed = function (key: any, data: buffer, length: number)
		beat.fed[names[key]] += 1
		feed(key, data, length)
	end

	local owner: any = Taps.owner
	Taps.owner = function (key: any, ...: any)
		beat.tapped[names[key]] += 1
		owner(key, ...)
	end

	local relay: any = Characters.relay
	Characters.relay = function (relayTick: number, tick: number)
		beat.before = beat.samples.moderator + beat.samples.bot
		relay(relayTick, tick)
	end

	if early then
		local history: any = Characters.history
		Characters.history = function (tick: number, relayTick: number)
			history(tick, relayTick)
			Characters.sendOwners(relayTick)
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
			network.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
			network.flush()
			rig:deliver()
		end

		rig:tick(1)
		rig:deliver()
		beats[tick] = beat
	end

	return beats, rig:reported("stage")
end

--[[
    Why one beat sent or counted other than once a key, or nil: each key
    one Owner message, one ping sample, one feed and one tap, the moderator
    one feed of the bot, and the samples all taken before the relay stage
    when early and inside it otherwise. The bot's commands from the second
    tick are acknowledged, and every other OwnerState goes in full
--]]

local function once(beat: Beat, tick: number, early: boolean): string?
	for _, name: string in NAMES do
		local owners: { string } = beat.owners[name]
		local due: boolean = name == "bot" and tick > 1

		if #owners ~= 1 then
			return `tick {tick} sent the {name} {#owners} Owner messages, not one`
		elseif due and #owners[1] ~= ACK_BYTES then
			return `tick {tick} sent the {name} {#owners[1]} B, not an acknowledgment`
		elseif not due and #owners[1] <= ACK_BYTES then
			return `tick {tick} sent the {name} an acknowledgment, where the full OwnerState goes`
		elseif beat.samples[name] ~= 1 then
			return `tick {tick} sampled the {name}'s ping {beat.samples[name]} times, not once`
		elseif beat.fed[name] ~= 1 or beat.tapped[name] ~= 1 then
			local counts: string = `{beat.fed[name]} times and the taps {beat.tapped[name]}`
			return `tick {tick} handed the {name}'s OwnerState to its feed {counts}`
		elseif #beat.taps[name] ~= 1 then
			return `tick {tick} handed the {name}'s sink {#beat.taps[name]} frames, not one`
		end
	end

	local before: number = early and #NAMES or 0
	if #beat.feeds ~= 1 then
		return `tick {tick} sent the moderator {#beat.feeds} feeds, not one`
	elseif beat.before ~= before then
		return `tick {tick} sampled {beat.before} pings before the relay stage began, not {before}`
	end

	return nil
end

-- Why an early beat's bytes differ from the relay alone's, or nil
local function same(early: Beat, alone: Beat, tick: number): string?
	if early.feeds[1] ~= alone.feeds[1] then
		return `tick {tick}'s feed differed from the relay alone's`
	end

	for _, name: string in NAMES do
		if early.owners[name][1] ~= alone.owners[name][1] then
			return `tick {tick}'s Owner message to the {name} differed from the relay alone's`
		elseif early.taps[name][1] ~= alone.taps[name][1] then
			return `tick {tick}'s tap frame of the {name} differed from the relay alone's`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local alone: { Beat }, aloneThrew: { number | string } = run(false)
	local early: { Beat }, earlyThrew: { number | string } = run(true)

	for tick: number = 1, TICKS do
		local wrong: string? = once(alone[tick], tick, false)
		if wrong then
			return false, `With the relay alone, {wrong}`
		end

		wrong = once(early[tick], tick, true)
		if wrong then
			return false, `With the owners' part early, {wrong}`
		end

		wrong = same(early[tick], alone[tick], tick)
		if wrong then
			return false, wrong
		end
	end

	if #aloneThrew > 0 or #earlyThrew > 0 then
		return false,
			`Stages threw {#aloneThrew} times with the relay alone and {#earlyThrew} with the owners' part early`
	end

	return true, nil
end
