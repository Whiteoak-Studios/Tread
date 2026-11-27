--[[
    An acknowledgment a relay path left queued is fired once, first, when
    the next relay tick's owners' part runs, ahead of that tick's own, and
    both carry the bytes a run that fired every one on its tick sent
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
local HOLD_AT: number = 4 -- The tick whose acknowledgment the relay stage leaves queued
local DELAY: number = 100 -- Milliseconds of interpolation delay each Move reports
local BOT_X: number = -20 -- Where the bot's body is built, clear of the fixture's obstacles
local START_Z: number = 10

--[[
    One run of a bot that agrees under bots.agree and sends a command from
    the second tick, with HOLD_AT's acknowledgments left queued by the
    relay stage when hold is set: the Owner messages the bot heard each
    beat, and the acknowledgments stats counted, or why it went wrong
--]]

local function run(hold: boolean): ({ { string } }?, number | string)
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

	local heard: { string } = {}
	network.Owner.on(function (data: buffer)
		table.insert(heard, buffer.tostring(data))
	end)

	network.flush()
	rig:deliver()

	server:create(bot, rig:at(BOT_X, START_Z))
	server:stats()

	-- The stage's own fire, passed over on HOLD_AT's tick, as a relay path that never reached it would
	local holding: boolean = false
	local acks: any = Characters.acks
	Characters.acks = function ()
		if not holding then
			acks()
		end
	end

	local layout: any = Fields.compile(rig.shared.fields)
	local limits: any = { lean = rig.shared.step.lean, headCone = rig.shared.step.headCone }
	local command: any = Command.new()
	command.fields = { slot = 0, shots = {} }
	local move: any = Move.new()
	local beats: { { string } } = {}

	for tick: number = 1, TICKS do
		heard = {}

		-- From the second tick, since the server files no command before its first
		if tick > 1 then
			command.number = tick
			Move.encode(move, { command }, 1, 0, 0, DELAY, layout, limits)
			network.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
			network.flush()
			rig:deliver()
		end

		holding = hold and tick == HOLD_AT
		rig:tick(1)
		rig:deliver()
		beats[tick] = heard
	end

	holding = false

	local reported: { number | string } = rig:reported("stage")
	if #reported > 0 then
		return nil, `the {reported[1]} stage threw {#reported} times`
	end

	return beats, server:stats().ownerAcks
end

-- Why a beat's messages are not the ones listed, each named by the tick whose message in the run that fired every
-- acknowledgment on its tick it must be, or nil
local function expect(beat: { string }, reference: { { string } }, ticks: { number }, at: number): string?
	if #beat ~= #ticks then
		return `beat {at} sent the bot {#beat} Owner messages, not {#ticks}`
	end

	for index: number, tick: number in ticks do
		local message: string = beat[index]
		if message ~= reference[tick][1] then
			local named: number = #message >= ACK_BYTES and buffer.readu16(buffer.fromstring(message), 0) or -1
			return `beat {at}'s message {index} was {#message} B naming command {named}, not tick {tick}'s`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local reference: { { string } }?, fired: number | string = run(false)
	if not reference then
		return false, `With every acknowledgment fired on its tick, {fired}`
	end

	-- The command each tick from the second ran is acknowledged, and the first tick's stand-in goes in full
	for tick: number = 1, TICKS do
		local messages: { string } = reference[tick]
		local due: boolean = tick > 1
		if #messages ~= 1 then
			return false, `With every acknowledgment fired on its tick, tick {tick} sent {#messages} Owner messages`
		elseif due and (#messages[1] ~= ACK_BYTES or buffer.readu16(buffer.fromstring(messages[1]), 0) ~= tick) then
			return false, `With every acknowledgment fired on its tick, tick {tick} was not acknowledged`
		elseif not due and #messages[1] <= ACK_BYTES then
			return false, `With every acknowledgment fired on its tick, tick {tick}'s stand-in was acknowledged`
		end
	end

	local held: { { string } }?, counted: number | string = run(true)
	if not held then
		return false, `With tick {HOLD_AT}'s acknowledgment left queued, {counted}`
	end

	-- The held one leaves first on the next tick, then that tick's own, and every other tick is unchanged
	for tick: number = 1, TICKS do
		local ticks: { number } = { tick }
		if tick == HOLD_AT then
			ticks = {}
		elseif tick == HOLD_AT + 1 then
			ticks = { HOLD_AT, tick }
		end

		local wrong: string? = expect(held[tick], reference, ticks, tick)
		if wrong then
			return false, `With tick {HOLD_AT}'s acknowledgment left queued, {wrong}`
		end
	end

	if counted ~= fired or fired ~= TICKS - 1 then
		return false, `Stats counted {counted} acknowledgments with one left queued, against {fired}, not {TICKS - 1}`
	end

	return true, nil
end
