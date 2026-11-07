--[[
    A bot handed a Move's commands as the server's decode reads them sends
    them on with the same numbers and the same wire values, beside its own
    acknowledgments, as the mirror scenario hands it a player's Moves
--]]

--!strict
local Harness = require("../../Fixtures/DevBot/Harness")

local NEWEST: number = 41
local COUNT: number = 3
local SEQUENCE: number = 9 -- The relay block the bot itself has heard
local THEIRS: number = 77 -- The player's own acknowledgment, which the bot's Move never carries
local SEED: number = 1

-- A player's commands, each with its own inputs, newest first
local function made(harness: Harness.Loaded): { any }
	local Command: any =
		harness.loaded.require(harness.loaded.game:GetService("ReplicatedStorage").Packages.Tread.Codec.Command)
	local commands: { any } = {}

	for index: number = 1, COUNT do
		local command: any = Command.new()
		command.number = NEWEST - (index - 1)
		command.forward = 1 / index
		command.right = -0.5 / index
		command.jump = index == 2
		command.yaw = index
		command.pitch = -0.25 * index
		command.fields = { slot = index, shots = {} }
		table.insert(commands, command)
	end

	return commands
end

return function (): (boolean, string | nil)
	local harness: Harness.Loaded = Harness.load()
	local Move: any =
		harness.loaded.require(harness.loaded.game:GetService("ReplicatedStorage").Packages.Tread.Codec.Move)
	local context: any = harness.context

	-- What the player's client sent, and what the server's decode reads from it
	local sent: any = Move.new()
	Move.encode(sent, made(harness), COUNT, THEIRS, 0, context.delay, context.layout, context.limits)

	local incoming: any = Move.incoming()
	local failed: number? =
		Move.decode(sent.command, THEIRS, 0, sent.delay, sent.commands, context.layout, context.limits, incoming)
	if failed then
		return false, `The player's Move failed to decode at field {failed}`
	end

	local side: Harness.Side = Harness.side()
	local bot: any = harness.Bot.new(side.network, context, nil, nil, SEED)
	side.listeners.Relay(Harness.relay(harness, SEQUENCE))
	bot:send(incoming.commands, incoming.count)

	local fired: Harness.Fired = side.fired[1]
	if #side.fired ~= 1 or fired.command ~= NEWEST or #fired.commands ~= COUNT then
		return false, `The bot sent {#side.fired} Moves, the first's newest {fired and fired.command}`
	elseif fired.acknowledged ~= SEQUENCE then
		return false, `The bot's Move acknowledged {fired.acknowledged}, not its own block {SEQUENCE}`
	elseif side.flushes ~= 2 then
		return false, `The bot flushed {side.flushes} times, not once for its handshake and once for the Move`
	end

	for index: number, wire: Harness.Wire in fired.commands do
		local original: any = sent.commands[index]
		local same: boolean = wire.moveX == original.moveX
			and wire.moveZ == original.moveZ
			and wire.buttons == original.buttons
			and wire.yaw == original.yaw
			and wire.pitch == original.pitch
			and wire.fields == buffer.len(original.fields)

		if not same then
			return false, `The bot's copy of command {wire.number} differs from the player's on the wire`
		end
	end

	bot:destroy()

	return true, nil
end
