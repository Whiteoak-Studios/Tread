--[[
    The Move, client to server once a relay tick: the commands made since
    the last one and the ones before them it repeats, newest first, and the
    client's acknowledgments of the relay
--]]

--!strict
--!native
local Command = require(script.Parent.Command)
local Constants = require(script.Parent.Parent.Constants)
local Fields = require(script.Parent.Fields)
local Sequence = require(script.Parent.Sequence)
local State = require(script.Parent.Parent.Step.State)

local WRAP: number = 2 ^ 16 -- A command number is a u16

type Layout = Fields.Layout
type Limits = Command.Limits
type Wire = Command.Wire

-- A Move to send, which its sender keeps and encodes again each relay tick
export type Move = {
	command: number, -- The newest command's number, 0 when it carries none
	acknowledged: number, -- The newest relay sequence the client received, 0 for none
	received: number, -- The 16 sequences before it, bit 0 set when the one just before arrived
	delay: number, -- The interpolation delay, in milliseconds
	commands: { Wire }, -- What Volt sends, newest first
	wires: { Wire }, -- Every wire it has made, which commands reuses
}

-- A Move received, which its receiver keeps and decodes into each time
export type Incoming = {
	command: number,
	acknowledged: number,
	received: number,
	delay: number,
	count: number, -- The commands it decoded into commands
	commands: { State.Command }, -- Newest first, each numbered one below the one before it
}

local Move = {}

--[[
    A Move with nothing in it yet, for one sender to encode into each relay
    tick
--]]

function Move.new(): Move
	return {
		command = 0,
		acknowledged = 0,
		received = 0,
		delay = 0,
		commands = {} :: { Wire },
		wires = {} :: { Wire },
	}
end

--[[
    A received Move with nothing in it yet, for one receiver to decode into
--]]

function Move.incoming(): Incoming
	return {
		command = 0,
		acknowledged = 0,
		received = 0,
		delay = 0,
		count = 0,
		commands = {} :: { State.Command },
	}
end

--[[
    Encodes the first count of commands, newest first and each numbered one
    below the one before it, with the acknowledgments, into move, whose
    fields then go to Volt's Move as they are. Volt copies them as it fires,
    so the next encode may reuse them. It errors on more than a Move
    carries, on numbers out of order and on a game field its declaration
    doesn't hold
--]]

function Move.encode(
	move: Move,
	commands: { State.Command },
	count: number,
	acknowledged: number,
	received: number,
	delay: number,
	layout: Layout,
	limits: Limits
)
	if not (count >= 0 and count <= Constants.MAX_COMMANDS) then
		error(`A Move carries 0 to {Constants.MAX_COMMANDS} commands, not {count}`)
	end

	local newest: number = 0
	if count > 0 then
		newest = commands[1].number
	end

	for position: number = 1, count do
		local command: State.Command = commands[position]

		-- The server numbers every command from the newest, so each is one below the one before it
		if Sequence.difference(newest, command.number) ~= position - 1 then
			error(`A Move's command {position} is numbered {command.number}, out of order below {newest}`)
		end

		local wire: Wire = move.wires[position]
		if not wire then
			wire = Command.wire()
			move.wires[position] = wire
		end

		Command.write(command, wire, layout, limits)
		move.commands[position] = wire
	end

	for position: number = #move.commands, count + 1, -1 do
		move.commands[position] = nil
	end

	move.command = newest
	move.acknowledged = acknowledged
	move.received = received
	move.delay = delay
end

--[[
    Decodes a Move as Volt's listener hands it into into, numbering each
    command down from the newest, and gives nil. When a command's game
    fields fail it gives the index of the first field that failed and
    refuses the whole Move: into keeps its last acknowledgments and a count
    of 0, and its commands are scratch
--]]

function Move.decode(
	command: number,
	acknowledged: number,
	received: number,
	delay: number,
	wires: { Wire },
	layout: Layout,
	limits: Limits,
	into: Incoming
): number?
	local count: number = #wires
	if count > Constants.MAX_COMMANDS then
		error(`A Move carries at most {Constants.MAX_COMMANDS} commands, and Volt handed {count}`)
	end

	for position: number = 1, count do
		local target: State.Command = into.commands[position]
		if not target then
			target = Command.new()
			into.commands[position] = target
		end

		local failed: number? = Command.read(wires[position], target, layout, limits)
		if failed then
			into.count = 0

			return failed
		end

		target.number = (command - (position - 1)) % WRAP
	end

	into.command = command
	into.acknowledged = acknowledged
	into.received = received
	into.delay = delay
	into.count = count

	return nil
end

return Move
