--[[
    The owner counters stats gives, ownerFull, ownerAcks, ownerChecked and
    ownerMismatches, count the same on every tick whether the owners' part
    runs early or inside the relay stage, over the mock's player, whose
    checks agree, miss and are 0, beside a bot whose checks are all 0
--]]

--!strict
local Environment = require("../../Environment")
local Rig = require("../../Fixtures/Server/Rig")

local Volt = require("@volt")

local CLIENT: string = "src/Network/Client.luau"
local VOLT: string = "ReplicatedStorage.Packages.Volt"
local HASH: string = "src/Codec/Hash.luau"
local ACK_BYTES: number = 5 -- An acknowledgment's: an OwnerState's command, tick and queue depth
local BOT_RTT: number = 0.1 -- Seconds, the round trip the bots table needs
local TICKS: number = 8
local WRONG_AT: number = 5 -- The tick the player's check misses at
local ZERO_AT: number = 6 -- The tick the player sends a check of 0 at
local DELAY: number = 100 -- Milliseconds of interpolation delay each Move reports
local WORD: number = 2 ^ 32 -- The values a check holds
local PLAYER_X: number = -28 -- Where each body is built, clear of the fixture's obstacles, as the botsAgree case does
local BOT_X: number = -20
local START_Z: number = 10

local COUNTERS: { string } = { "ownerFull", "ownerAcks", "ownerChecked", "ownerMismatches" }

-- What one run gave: each tick's four counters by name, the player's Owner message each tick, and the stages that threw
type Run = {
	counts: { { [string]: number } },
	owners: { string },
	threw: { number | string },
}

--[[
    One run, with the owners' part called at the end of each relay tick's
    history stage when early, and each of the player's commands from the
    second tick checked with hashes, its check of 0 where hashes is nil.
    Volt's mock player is a bot to Tread, so bots.agree stays off and the
    player's checks are compared for real
--]]

local function run(early: boolean, hashes: { [number]: number }?): Run
	local rig: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.owner = { checks = true }
		settings.bots = { rtt = BOT_RTT }
	end)

	local server: any = rig:start()
	local tread: any = rig.tread
	local Characters: any = rig:require(tread.Server.Characters)
	local Command: any = rig:require(tread.Codec.Command)
	local Fields: any = rig:require(tread.Codec.Fields)
	local Move: any = rig:require(tread.Codec.Move)

	local heard: string? = nil
	local client: any = rig:require(tread.Network.Client)
	client.Owner.on(function (data: buffer)
		heard = buffer.tostring(data)
	end)

	client.flush()

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

	network.flush()
	rig:deliver()

	server:create(rig.mock.players[1], rig:at(PLAYER_X, START_Z))
	server:create(bot, rig:at(BOT_X, START_Z))
	server:stats()

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
	local playerMove: any = Move.new()
	local botMove: any = Move.new()
	local result: Run = { counts = {}, owners = {}, threw = {} }

	for tick: number = 1, TICKS do
		-- From the second tick, since the server files no command before its first
		if tick > 1 then
			local check: number = 0
			local hash: number? = hashes and hashes[tick]
			if hash and tick == WRONG_AT then
				check = (hash + 1) % WORD
			elseif hash and tick ~= ZERO_AT then
				check = hash
			end

			command.number = tick
			Move.encode(playerMove, { command }, 1, 0, 0, DELAY, layout, limits, { check })
			client.Move.fire(
				playerMove.command,
				playerMove.acknowledged,
				playerMove.received,
				playerMove.delay,
				playerMove.commands
			)
			client.flush()

			Move.encode(botMove, { command }, 1, 0, 0, DELAY, layout, limits)
			network.Move.fire(botMove.command, botMove.acknowledged, botMove.received, botMove.delay, botMove.commands)
			network.flush()
			rig:deliver()
		end

		heard = nil
		rig:tick(1)
		rig:deliver()

		local read: any = server:stats()
		local counts: { [string]: number } = {}
		for _, counter: string in COUNTERS do
			counts[counter] = read[counter]
		end

		result.counts[tick] = counts
		result.owners[tick] = heard or ""
	end

	result.threw = rig:reported("stage")

	return result
end

--[[
    What each counter must read on a tick, from the checks' rules: both
    first OwnerStates in full, the bot's check of 0 never compared so its
    every OwnerState full, and the player acknowledged and compared where
    its check agrees, compared and missed in full at WRONG_AT, and sent in
    full uncompared at ZERO_AT
--]]

local function due(tick: number): { [string]: number }
	if tick == 1 then
		return { ownerFull = 2, ownerAcks = 0, ownerChecked = 0, ownerMismatches = 0 }
	elseif tick == WRONG_AT then
		return { ownerFull = 2, ownerAcks = 0, ownerChecked = 1, ownerMismatches = 1 }
	elseif tick == ZERO_AT then
		return { ownerFull = 2, ownerAcks = 0, ownerChecked = 0, ownerMismatches = 0 }
	end

	return { ownerFull = 1, ownerAcks = 1, ownerChecked = 1, ownerMismatches = 0 }
end

return function (): (boolean, string | nil)
	-- Each tick's agreeing check is the hash of the player's full OwnerState past its first bytes, from a run with none
	local Hash: any = Environment.load(HASH)
	local first: Run = run(false, nil)
	local hashes: { [number]: number } = {}

	for tick: number, owner: string in first.owners do
		if #owner <= ACK_BYTES then
			return false, `With every check 0, tick {tick} sent the player {#owner} B, not its full OwnerState`
		end

		hashes[tick] = Hash.range(buffer.fromstring(owner), ACK_BYTES, #owner - ACK_BYTES)
	end

	local alone: Run = run(false, hashes)
	local early: Run = run(true, hashes)

	for tick: number = 1, TICKS do
		local expected: { [string]: number } = due(tick)

		for _, counter: string in COUNTERS do
			local inside: number = alone.counts[tick][counter]
			local before: number = early.counts[tick][counter]

			if inside ~= before then
				return false, `Tick {tick}'s {counter} read {before} with the owners' part early and {inside} without`
			elseif inside ~= expected[counter] then
				return false, `Tick {tick}'s {counter} read {inside}, not {expected[counter]}`
			end
		end
	end

	for _, built: { label: string, run: Run } in
		{
			{ label = "every check 0", run = first },
			{ label = "the relay alone", run = alone },
			{ label = "early", run = early },
		}
	do
		if #built.run.threw > 0 then
			return false, `With {built.label}, the {built.run.threw[1]} stage threw {#built.run.threw} times`
		end
	end

	return true, nil
end
