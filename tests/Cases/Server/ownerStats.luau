--[[
    Stats counts each OwnerState sent in full and as an acknowledgment, and
    each compare against a real check with its misses, a bot taken as
    agreeing and a tick with no check in neither, and bytesOut counts 5 B
    for an acknowledgment
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")
local Pings = require("../../Fixtures/Connections/Ping")
local Rig = require("../../Fixtures/Server/Rig")

local HASH: string = "src/Codec/Hash.luau"
local ACK_BYTES: number = 5 -- An acknowledgment's: an OwnerState's command, tick and queue depth
local BOT_RTT: number = 0.1 -- Seconds, the round trip the bots table needs
local PING: number = 0.1 -- Seconds the engine reports for each Player
local TICKS: number = 10
local BOT_SKIP: number = 6 -- The tick the bot sends no command for
local DELAY: number = 100 -- Milliseconds of interpolation delay each Move reports
local WORD: number = 2 ^ 32 -- The values a check holds
local START_Z: number = 10

-- Seconds anti-ESP's slice may take a Heartbeat, more than the runner gives a whole case, so both runs test every pair
-- by the tick after its first ask and their relay blocks, which bytesOut counts beside the OwnerStates, come out alike
-- however fast the machine runs
local SLICE: number = 60

-- The three keys and where each body is built, clear of the fixture's obstacles
local NAMES: { string } = { "Agreeing", "Other", "Bot" }
local PLACES: { [string]: number } = { Agreeing = -28, Other = -20, Bot = -12 }

-- What one run kept: each key's full OwnerState as the taps had it each tick, and the stats read after each tick
type Run = {
	taps: { [string]: { [number]: string } },
	reads: { [number]: any },
}

-- What the other Player sends on a tick from the second: a check that misses, a check of 0, or no command
local function plan(tick: number): string
	local turn: number = (tick - 2) % 3
	return turn == 0 and "wrong" or turn == 1 and "zero" or "skip"
end

--[[
    One run with checks as given and every bot agreeing: two Players the
    server files Moves for as Volt's listener would, one with each tick's
    check from hashes and one as plan has it, and a bot, all on the same
    commands from the second tick
--]]

local function run(checks: boolean, hashes: { [string]: { [number]: number } }?): Run
	local rig: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.owner = { checks = checks }
		settings.bots = { rtt = BOT_RTT, agree = true }
		settings.antiEsp.slice = SLICE
	end)

	local server: any = rig:start()
	local tread: any = rig.tread
	local Characters: any = rig:require(tread.Server.Characters)
	local Command: any = rig:require(tread.Codec.Command)
	local Fields: any = rig:require(tread.Codec.Fields)
	local Move: any = rig:require(tread.Codec.Move)
	local Tap: any = rig:require(tread.Codec.Tap)

	local keys: { [string]: any } = {}
	local kept: Run = { taps = {}, reads = {} }

	for _, name: string in NAMES do
		local key: any
		if name == "Bot" then
			key = rig.mock:addBot(name)
		else
			key = roblox.Instance.new("Player")
			key.Name = name
			Pings[key] = PING
		end

		keys[name] = key
		kept.taps[name] = {}
		server:create(key, rig:at(PLACES[name], START_Z))
		server:observe(key, function (tick: number, data: buffer)
			kept.taps[name][tick] = buffer.tostring(Tap.read(data).owner.data)
		end)
	end

	local layout: any = Fields.compile(rig.shared.fields)
	local limits: any = { lean = rig.shared.step.lean, headCone = rig.shared.step.headCone }
	local command: any = Command.new()
	command.fields = { slot = 0, shots = {} }
	command.forward = 1
	server:stats()

	-- Files one command for a key's character with its check in a Move of its own, as Volt's Move listener hands it
	local function file(name: string, tick: number, check: number)
		local move: any = Move.new()
		command.number = tick
		Move.encode(move, { command }, 1, 0, 0, DELAY, layout, limits, { check })
		Characters.file(keys[name], move.command, move.acknowledged, move.received, move.delay, move.commands)
	end

	for tick: number = 1, TICKS do
		-- From the second tick, since the server files no command before its first
		if tick > 1 then
			local agreeing: number = hashes and hashes.Agreeing[tick] or 0
			local other: number = hashes and (hashes.Other[tick] + 1) % WORD or 0
			file("Agreeing", tick, agreeing)

			if plan(tick) ~= "skip" then
				file("Other", tick, plan(tick) == "wrong" and other or 0)
			end

			if tick ~= BOT_SKIP then
				file("Bot", tick, 0)
			end
		end

		rig:tick(1)
		kept.reads[tick] = server:stats()
	end

	return kept
end

return function (): (boolean, string | nil)
	local Hash: any = Environment.load(HASH)

	-- With checks off, every OwnerState goes in full and nothing is compared
	local off: Run = run(false, nil)
	local hashes: { [string]: { [number]: number } } = {}
	for _, name: string in NAMES do
		hashes[name] = {}
		for tick: number = 1, TICKS do
			local owner: string? = off.taps[name][tick]
			if owner == nil or #owner <= ACK_BYTES then
				return false, `With checks off, {name}'s tap had no full OwnerState on tick {tick}`
			end

			hashes[name][tick] = Hash.range(buffer.fromstring(owner), ACK_BYTES, #owner - ACK_BYTES)
		end
	end

	for tick: number = 1, TICKS do
		local read: any = off.reads[tick]
		if read.ownerFull ~= #NAMES or read.ownerAcks ~= 0 or read.ownerChecked ~= 0 or read.ownerMismatches ~= 0 then
			local counts: string = `{read.ownerFull} full, {read.ownerAcks} acks, {read.ownerChecked} checked`
			return false, `With checks off, tick {tick} counted {counts} and {read.ownerMismatches} missed`
		end
	end

	local on: Run = run(true, hashes)
	for tick: number = 1, TICKS do
		local read: any = on.reads[tick]
		local real: boolean = tick > 1
		local wrong: boolean = real and plan(tick) == "wrong"
		local botAck: boolean = real and tick ~= BOT_SKIP

		-- The agreeing Player and a missed check are compares, and a check of 0, a stand-in and the bot are none
		local checked: number = (real and 1 or 0) + (wrong and 1 or 0)
		local mismatches: number = wrong and 1 or 0
		local acks: number = (real and 1 or 0) + (botAck and 1 or 0)

		if read.ownerChecked ~= checked or read.ownerMismatches ~= mismatches then
			local counts: string = `{read.ownerChecked} compares and {read.ownerMismatches} misses`
			return false, `With checks on, tick {tick} counted {counts}, not {checked} and {mismatches}`
		elseif read.ownerAcks ~= acks or read.ownerFull ~= #NAMES - acks then
			local counts: string = `{read.ownerAcks} acknowledgments and {read.ownerFull} full`
			return false, `With checks on, tick {tick} counted {counts}, not {acks} and {#NAMES - acks}`
		end

		-- Each acknowledgment sends 5 B where the run with checks off sent its full OwnerState
		local saved: number = 0
		if real then
			saved += #on.taps.Agreeing[tick] - ACK_BYTES
		end

		if botAck then
			saved += #on.taps.Bot[tick] - ACK_BYTES
		end

		if off.reads[tick].bytesOut - read.bytesOut ~= saved then
			local bytes: string = `{read.bytesOut} B out against {off.reads[tick].bytesOut} with checks off`
			return false, `With checks on, tick {tick} counted {bytes}, not {saved} B fewer`
		end
	end

	return true, nil
end
