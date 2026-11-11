--[[
    One bot's client side of Tread's scope: a command each tick from its
    program, a Move each relay tick encoded as the owner's client encodes
    one, its faults or cheat applied, and the relay acknowledged
--]]

--!strict
local Bot = {}
Bot.__index = Bot

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local Root = Packages.Tread
local Block = require(Root.Codec.Block)
local Command = require(Root.Codec.Command)
local Constants = require(Root.Constants)
local Fields = require(Root.Codec.Fields)
local Move = require(Root.Codec.Move)
local OwnerState = require(Root.Codec.OwnerState)
local Sequence = require(Root.Codec.Sequence)
local State = require(Root.Step.State)

local Config = require(ServerScriptService.Server.Bots.Config)
local Programs = require(ServerScriptService.Server.Bots.Programs)
local Seeded = require(ServerScriptService.Server.Bots.Seeded)

local MAX_COMMANDS: number = Constants.MAX_COMMANDS
local MOVE_REPEATS: number = Constants.MOVE_REPEATS
local MOVE_STEPS: number = Constants.MOVE_STEPS
local ACK_MASK_BITS: number = Constants.ACK_MASK_BITS
local MASK: number = 2 ^ ACK_MASK_BITS - 1 -- The acknowledgment mask's bits
local WRAP: number = 2 ^ 16 -- A command number is a u16
local DELAY_LIMIT: number = 2 ^ 8 - 1 -- The most milliseconds the Move's u8 delay holds
local MILLISECONDS: number = 1000 -- A second's

type Layout = Fields.Layout
type Limits = Command.Limits
type Network = typeof(require(Root.Network.Client))
type Steer = Programs.Steer
type Values = State.Values

-- What every bot of one server encodes with: the shared table's declarations and limits, its clock and its rates
export type Context = {
	layout: Layout,
	limits: Limits,
	lead: number, -- Ticks past the server's tick a command is numbered for, the middle of the shared table's band
	simulation: number, -- Ticks a second
	relay: number, -- Relay ticks a second, one Move each
	delay: number, -- The interpolation delay each Move reports, milliseconds
	fields: Values, -- Each command's game fields
}

-- A cheat's windows: when each opens, how long it lasts, and for a relabel how far ahead it renumbers
export type Cheat = {
	kind: Config.Cheat,
	every: number, -- Ticks from one window's start to the next
	phase: number, -- The tick, inside every, each window starts on
	lengths: { number }, -- Ticks each window lasts, taken in turn
	ahead: { number }, -- Ticks past its clock a relabel renumbers by, taken in turn
}

-- What a bot's link does to its Moves on their way
export type Faults = {
	lag: number, -- Ticks each Move is held before it goes, 0 for none
	loss: number, -- The share of Moves dropped, from 0 up to but never 1
	cheat: Cheat?,
}

-- One lag switch's or relabel's hold: its ticks, and how far across the ground the server moved the body meanwhile
export type Hold = {
	ticks: number,
	moved: number,
}

-- What a bot saw and did, which the harness reads for its run's lines
export type Measure = {
	heard: number, -- OwnerStates read
	sent: number, -- Moves handed to Volt
	dropped: number, -- Moves the faults or the cheat dropped
	held: number, -- Moves held back before they went
	first: vector?, -- Where the first OwnerState put the body
	position: vector?, -- Where the newest put it
	fastest: number, -- The fastest the body crossed the ground, studs a second, by its OwnerStates
	holds: { Hold },
}

-- A Move held back, and the tick it goes on, or nil for one a hold keeps until the hold ends
type Queued = {
	move: Move.Move,
	due: number?,
}

type Fields = {
	_network: Network,
	_context: Context,
	_steer: Steer?, -- nil for a bot that sends only what it is handed
	_faults: Faults,
	_seeded: Seeded.Seeded, -- Draws which Moves are lost
	_recent: { State.Command }, -- The newest commands made, newest first
	_fresh: number, -- Commands made since the last Move
	_move: Move.Move,
	_relabeled: { State.Command }, -- The commands a relabel resends, renumbered
	_queue: { Queued }, -- Moves held back, oldest first
	_spare: { Move.Move }, -- Moves sent from the queue, which the next held ones reuse
	_acknowledged: number, -- The newest relay sequence received
	_mask: number, -- The 16 before it
	_receiving: boolean, -- Whether a relay block has arrived
	_owned: boolean, -- Whether an OwnerState has arrived
	_server: State.State, -- The body's state as the newest OwnerState gave it
	_block: Block.Block, -- The newest relay block's sections
	_windows: number, -- The cheat's windows opened so far
	_closes: number, -- The tick the open window closes on, or the last one did
	_open: boolean,
	_start: vector?, -- Where the body stood as a hold began
	_moved: number, -- The farthest it has moved from there
	_stops: { () -> () }, -- Each listener's disconnect
	_live: boolean,
	_measure: Measure,
}

-- What the scope's other events are heard with, so none of them ever queues for a listener
local function ignore() end

--[[
    What every bot of a server encodes with, from the shared table: its
    declarations compiled, its limits, the lead its clock keeps, its rates,
    and the delay and game fields each Move carries
--]]

function Bot.context(shared: Tread.Shared, delay: number, fields: Values): Context
	return {
		layout = Fields.compile(shared.fields),
		limits = { lean = shared.step.lean, headCone = shared.step.headCone },
		lead = math.round((shared.ticks.leadMin + shared.ticks.leadMax) / 2),
		simulation = shared.rates.simulation,
		relay = shared.rates.relay,
		delay = math.clamp(math.round(delay * MILLISECONDS), 0, DELAY_LIMIT),
		fields = fields,
	}
end

--[[
    A bot on a client side of Tread's scope: it hears its OwnerState and
    the relay, ignores the rest, and sends its handshake. Its program fills
    each tick's command, and with none it sends only what it is handed. Its
    seed draws which of its Moves its faults lose
--]]

function Bot.new(network: Network, context: Context, steer: Steer?, faults: Faults?, seed: number): Self
	local link: Faults = faults or { lag = 0, loss = 0, cheat = nil }
	if not (link.lag >= 0 and link.lag % 1 == 0) then
		error(`Bot.new takes a lag of whole ticks from 0, not {link.lag}`, 2)
	elseif not (link.loss >= 0 and link.loss < 1) then
		error(`Bot.new takes a loss from 0 up to but never 1, not {link.loss}`, 2)
	end

	local cheat: Cheat? = link.cheat
	if cheat and not (cheat.every > 0 and #cheat.lengths > 0 and #cheat.ahead > 0) then
		error(`Bot.new takes a {cheat.kind} cheat whose windows recur, each with a length and a reach ahead`, 2)
	end

	local self: Self = setmetatable({
		_network = network,
		_context = context,
		_steer = steer,
		_faults = link,
		_seeded = Seeded.new(seed),
		_recent = {} :: { State.Command },
		_fresh = 0,
		_move = Move.new(),
		_relabeled = {} :: { State.Command },
		_queue = {} :: { Queued },
		_spare = {} :: { Move.Move },
		_acknowledged = 0,
		_mask = 0,
		_receiving = false,
		_owned = false,
		_server = State.new(),
		_block = Block.new(),
		_windows = 0,
		_closes = 0,
		_open = false,
		_start = nil :: vector?,
		_moved = 0,
		_stops = {} :: { () -> () },
		_live = true,
		_measure = {
			heard = 0,
			sent = 0,
			dropped = 0,
			held = 0,
			first = nil :: vector?,
			position = nil :: vector?,
			fastest = 0,
			holds = {} :: { Hold },
		},
	}, Bot)

	for name: string, handle: any in network.events do
		-- The client hears every event but the Move it sends
		local on: ((listener: (...any) -> ()) -> () -> ())? = handle.on
		if not on then
			continue
		end

		local listener: (...any) -> () = ignore
		if name == "Owner" then
			listener = function (data: buffer)
				self:_hearOwner(data)
			end
		elseif name == "Relay" then
			listener = function (data: buffer)
				self:_hearRelay(data)
			end
		end

		table.insert(self._stops, on(listener))
	end

	-- The scope's handshake goes out with the first flush
	network.flush()

	return self
end

-- Puts Tread's own fields of a reused command back at rest
local function rest(command: State.Command)
	command.forward = 0
	command.right = 0
	command.jump = false
	command.crouch = false
	command.sprint = false
	command.aim = false
	command.yaw = 0
	command.pitch = 0
	command.lean = 0
	command.headYaw = 0
	command.headPitch = 0
end

-- Copies every input of one command into another, its game fields by reference, since a Move only reads them
local function copy(from: State.Command, into: State.Command)
	into.number = from.number
	into.forward = from.forward
	into.right = from.right
	into.jump = from.jump
	into.crouch = from.crouch
	into.sprint = from.sprint
	into.aim = from.aim
	into.yaw = from.yaw
	into.pitch = from.pitch
	into.lean = from.lean
	into.headYaw = from.headYaw
	into.headPitch = from.headPitch
	into.fields = from.fields
end

-- The horizontal distance between two points
local function across(from: vector, to: vector): number
	local x: number, z: number = to.x - from.x, to.z - from.z

	return math.sqrt(x * x + z * z)
end

--[[
    One simulation tick, from the stage after the server's relay: the
    Moves due go out, the cheat's window opens or closes, the program makes
    the command for the tick its clock is on, and on a relay tick the Move
    is sent, lost or held as the faults have it
--]]

function Bot.tick(self: Self, tick: number)
	if not self._live then
		error("bot:tick ran on a bot already destroyed", 2)
	end

	self:_release(tick)

	local cheat: Cheat? = self._faults.cheat
	if cheat then
		self:_window(cheat, tick)
	end

	local steer: Steer? = self._steer
	if not steer then
		return
	end

	local context: Context = self._context
	local recent: { State.Command } = self._recent
	local command: State.Command = (#recent == MAX_COMMANDS and table.remove(recent)) or Command.new()

	rest(command)
	command.number = (tick + context.lead + self._faults.lag) % WRAP
	command.fields = context.fields

	-- Until its first OwnerState a bot knows nowhere its body stands, so it sends its inputs at rest
	if self._owned then
		steer(command, tick, self._server.position)
	end

	table.insert(recent, 1, command)
	self._fresh += 1

	local relayed: number = math.floor(tick * context.relay / context.simulation)
	if relayed ~= math.floor((tick - 1) * context.relay / context.simulation) then
		self:_send(tick)
	end
end

--[[
    Sends a Move of the commands handed, newest first and each numbered one
    below the one before, as the bot's own, with its acknowledgments, at
    once and past its faults, for a bot that mirrors another's commands
--]]

function Bot.send(self: Self, commands: { State.Command }, count: number)
	if not self._live then
		error("bot:send ran on a bot already destroyed", 2)
	end

	self:_encode(self._move, commands, count)
	self:_fire(self._move)
	self._network.flush()
end

-- What the bot saw and did so far, its own table, which it goes on writing
function Bot.measure(self: Self): Measure
	return self._measure
end

--[[
    Stops the bot: every listener disconnected and every held Move dropped.
    Its Volt bot and its character are its owner's to remove
--]]

function Bot.destroy(self: Self)
	if not self._live then
		error("bot:destroy ran on a bot already destroyed", 2)
	end

	self._live = false

	for _, stop: () -> () in self._stops do
		stop()
	end

	table.clear(self._stops)
	table.clear(self._queue)
end

-- Encodes count commands into a Move with the bot's acknowledgments and delay
function Bot._encode(self: Self, move: Move.Move, commands: { State.Command }, count: number)
	local context: Context = self._context
	Move.encode(move, commands, count, self._acknowledged, self._mask, context.delay, context.layout, context.limits)
end

-- Hands a Move to Volt's Move as the client handle does, to go at the next flush
function Bot._fire(self: Self, move: Move.Move)
	self._network.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
	self._measure.sent += 1
end

--[[
    The relay tick's Move: every command made since the last and the ones
    before them it repeats, back as far as the numbers run on, then lost,
    held or sent as the faults and the cheat's open window have it
--]]

function Bot._send(self: Self, tick: number)
	local recent: { State.Command } = self._recent
	local wanted: number = math.min(self._fresh + MOVE_REPEATS, MAX_COMMANDS)
	local count: number = 0

	self._fresh = 0

	-- The numbers run on unless a stage was skipped, and a Move carries only an unbroken run
	while count < math.min(wanted, #recent) do
		if count > 0 and Sequence.difference(recent[count].number, recent[count + 1].number) ~= 1 then
			break
		end

		count += 1
	end

	local faults: Faults = self._faults
	local cheat: Cheat? = faults.cheat
	local kind: Config.Cheat? = self._open and cheat and cheat.kind or nil
	local holding: boolean = kind == "lagSwitch" or kind == "relabel"
	local measure: Measure = self._measure

	if kind == "freeze" or kind == "crouchLoss" or (faults.loss > 0 and self._seeded:next() < faults.loss) then
		measure.dropped += 1

		return
	end

	if holding or faults.lag > 0 then
		local move: Move.Move = table.remove(self._spare) or Move.new()
		self:_encode(move, recent, count)

		-- A hold keeps its Moves until it ends, and lag keeps each its own ticks
		local due: number? = nil
		if not holding then
			due = tick + faults.lag
		end

		table.insert(self._queue, { move = move, due = due })
		measure.held += 1

		return
	end

	self:_encode(self._move, recent, count)

	-- A tamper's second copy of a command differs from the first copy the last Move carried
	if kind == "tamper" and count >= 2 then
		local wire: Command.Wire = self._move.commands[2]
		wire.moveX = wire.moveX < MOVE_STEPS and wire.moveX + 1 or wire.moveX - 1
	end

	self:_fire(self._move)
	self._network.flush()
end

-- Sends every held Move whose tick has come, oldest first, in one flush
function Bot._release(self: Self, tick: number)
	local queue: { Queued } = self._queue
	local released: number = 0

	while queue[1] do
		local due: number? = queue[1].due
		if due == nil or due > tick then
			break
		end

		local queued: Queued = table.remove(queue, 1) :: Queued
		self:_fire(queued.move)
		table.insert(self._spare, queued.move)
		released += 1
	end

	if released > 0 then
		self._network.flush()
	end
end

--[[
    Opens the cheat's window on its ticks and closes it once its length
    has passed. A hold that closes lets its Moves go: a lag switch's as they
    were, a relabel's commands renumbered ahead in one Move in their place
--]]

function Bot._window(self: Self, cheat: Cheat, tick: number)
	if (tick - cheat.phase) % cheat.every == 0 and not self._open then
		self._windows += 1
		self._closes = tick + cheat.lengths[(self._windows - 1) % #cheat.lengths + 1]
		self._open = true
		self._start = self._measure.position
		self._moved = 0

		return
	end

	if not self._open or tick < self._closes then
		return
	end

	self._open = false

	if cheat.kind ~= "lagSwitch" and cheat.kind ~= "relabel" then
		return
	end

	local length: number = cheat.lengths[(self._windows - 1) % #cheat.lengths + 1]
	table.insert(self._measure.holds, { ticks = length, moved = self._moved })

	if cheat.kind == "lagSwitch" then
		for _, queued: Queued in self._queue do
			queued.due = queued.due or tick
		end

		self:_release(tick)

		return
	end

	-- The held Moves go nowhere, and the newest commands go again, numbered ahead of the clock
	for _, queued: Queued in self._queue do
		if queued.due == nil then
			table.insert(self._spare, queued.move)
		end
	end

	for index: number = #self._queue, 1, -1 do
		if self._queue[index].due == nil then
			table.remove(self._queue, index)
		end
	end

	local recent: { State.Command } = self._recent
	local relabeled: { State.Command } = self._relabeled
	local ahead: number = cheat.ahead[(self._windows - 1) % #cheat.ahead + 1]
	local newest: number = (tick + self._context.lead + ahead) % WRAP

	for index: number = 1, #recent do
		local command: State.Command = relabeled[index] or Command.new()
		relabeled[index] = command
		copy(recent[index], command)
		command.number = (newest - (index - 1)) % WRAP
	end

	self:_encode(self._move, relabeled, #recent)
	self:_fire(self._move)
	self._network.flush()
end

-- Reads an OwnerState for where the body stands and how fast it goes, and how far a hold has let it move
function Bot._hearOwner(self: Self, data: buffer)
	local server: State.State = self._server
	OwnerState.read(data, 0, buffer.len(data), server, nil, self._context.limits)
	self._owned = true

	local measure: Measure = self._measure
	local position: vector = server.position
	local velocity: vector = server.velocity
	local speed: number = math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z)

	measure.heard += 1
	measure.first = measure.first or position
	measure.position = position
	measure.fastest = math.max(measure.fastest, speed)

	local start: vector? = self._start
	if self._open and start then
		self._moved = math.max(self._moved, across(start, position))
	end
end

-- Acknowledges a relay block: a newer sequence shifts the mask, and an older one sets its bit
function Bot._hearRelay(self: Self, data: buffer)
	local block: Block.Block = self._block
	Block.read(data, block)

	-- A bot draws nothing, so it acknowledges each block that arrives and never decodes its change records
	local sequence: number = block.sequence
	if not self._receiving then
		self._receiving = true
		self._acknowledged = sequence
		self._mask = 0

		return
	end

	local ahead: number = Sequence.difference(sequence, self._acknowledged)
	if ahead > 0 then
		if ahead > ACK_MASK_BITS then
			self._mask = 0
		else
			-- The old newest lands on the highest bit the shift leaves clear
			self._mask = bit32.band(bit32.bor(bit32.lshift(self._mask, ahead), bit32.lshift(1, ahead - 1)), MASK)
		end

		self._acknowledged = sequence
	elseif ahead < 0 and -ahead <= ACK_MASK_BITS then
		self._mask = bit32.bor(self._mask, bit32.lshift(1, -ahead - 1))
	end
end

export type Bot = Self
type Self = typeof(setmetatable({} :: Fields, Bot))

return Bot
