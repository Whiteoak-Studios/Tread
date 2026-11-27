--[[
    With checks on and bots.agree, a bot's command with a check of 0 is
    acknowledged on every tick that ran it and its stand-in gets the full
    OwnerState, a Player's never is, and with the setting off the bot gets
    full OwnerStates too
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")
local Pings = require("../../Fixtures/Connections/Ping")
local Rig = require("../../Fixtures/Server/Rig")

local Volt = require("@volt")

local CLIENT: string = "src/Network/Client.luau"
local VOLT: string = "ReplicatedStorage.Packages.Volt"
local ACK_BYTES: number = 5 -- An acknowledgment's: an OwnerState's command, tick and queue depth
local BOT_RTT: number = 0.1 -- Seconds, the round trip the bots table needs
local PING: number = 0.1 -- Seconds the engine reports for the Player
local TICKS: number = 8
local SKIP_AT: number = 5 -- The tick the bot sends no command for, so it steps a stand-in
local DELAY: number = 100 -- Milliseconds of interpolation delay each Move reports
local PLAYER_X: number = -28 -- Where each body is built, clear of the fixture's obstacles
local BOT_X: number = -20
local START_Z: number = 10

--[[
    One run with bots.agree as given, a bot on the mock and a Player the
    server files Moves for as Volt's listener would, both sending a check
    of 0 from the second tick: why it went wrong, or nil
--]]

local function run(agree: boolean): string?
	local rig: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.owner = { checks = true }
		settings.bots = { rtt = BOT_RTT, agree = agree }
	end)

	local server: any = rig:start()
	local tread: any = rig.tread
	local Characters: any = rig:require(tread.Server.Characters)
	local Command: any = rig:require(tread.Codec.Command)
	local Fields: any = rig:require(tread.Codec.Fields)
	local Move: any = rig:require(tread.Codec.Move)

	-- The bot's client side is the generated module on its transport
	local volt: any = rig.mock:addBot("Bot")
	local transport: any = rig.mock:connectBot(volt)
	local network: any = Environment.load(CLIENT, {
		[VOLT] = {
			start = function (schema: any): any
				return Volt.start(schema, transport)
			end,
		},
	})

	local newest: string? = nil
	network.Owner.on(function (data: buffer)
		newest = buffer.tostring(data)
	end)

	network.flush()
	rig:deliver()

	-- A Player instance, which the mock can't send to, so what it is sent shows in the counters alone
	local player: any = roblox.Instance.new("Player")
	player.Name = "Player"
	Pings[player] = PING

	server:create(player, rig:at(PLAYER_X, START_Z))
	server:create(volt, rig:at(BOT_X, START_Z))
	server:stats()

	local layout: any = Fields.compile(rig.shared.fields)
	local limits: any = { lean = rig.shared.step.lean, headCone = rig.shared.step.headCone }
	local command: any = Command.new()
	command.fields = { slot = 0, shots = {} }
	local move: any = Move.new()

	for tick: number = 1, TICKS do
		-- From the second tick, since the server files no command before its first
		if tick > 1 then
			command.number = tick
			Move.encode(move, { command }, 1, 0, 0, DELAY, layout, limits)
			Characters.file(player, move.command, move.acknowledged, move.received, move.delay, move.commands)

			if tick ~= SKIP_AT then
				network.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
				network.flush()
			end

			rig:deliver()
		end

		newest = nil
		rig:tick(1)
		rig:deliver()

		local read: any = server:stats()
		local owner: string? = newest
		local due: boolean = agree and tick > 1 and tick ~= SKIP_AT
		local acks: number = due and 1 or 0
		if owner == nil then
			return `Tick {tick} sent the bot no Owner message`
		elseif due and #owner ~= ACK_BYTES then
			return `the bot got {#owner} B on tick {tick}, not an acknowledgment`
		elseif not due and #owner <= ACK_BYTES then
			return `the bot got an acknowledgment on tick {tick}, where the full OwnerState goes`
		elseif due and (buffer.readu16(buffer.fromstring(owner), 0) ~= tick) then
			return `the bot's acknowledgment on tick {tick} named another command`
		elseif read.ownerAcks ~= acks or read.ownerFull ~= 2 - acks then
			-- The Player's own is always one of the full OwnerStates, so an acknowledgment more is the Player's
			return `tick {tick} sent {read.ownerAcks} acknowledgments and {read.ownerFull} full OwnerStates`
		end
	end

	-- The Player's commands ran, so its full OwnerStates were for real commands, as the bot's acknowledgments were
	if #rig:reportedFor("standIn", player) ~= 1 then
		return `the Player ran {#rig:reportedFor("standIn", player)} stand-ins, not the first tick's alone`
	end

	return nil
end

return function (): (boolean, string | nil)
	for _, agree: boolean in { true, false } do
		local failure: string? = run(agree)
		if failure then
			return false, `With bots.agree {agree}, {failure}`
		end
	end

	return true, nil
end
