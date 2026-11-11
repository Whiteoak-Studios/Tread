--[[
    The server's intake of each connection's Moves: each command filed by the
    tick it belongs to, the command or stand-in each tick runs with its
    presses, the newest look, and the relay's acknowledgments sent back
--]]

--!strict
--!native
local Command = require(script.Parent.Parent.Codec.Command)
local Config = require(script.Parent.Parent.Config)
local Connections = require(script.Parent.Connections)
local Constants = require(script.Parent.Parent.Constants)
local Fields = require(script.Parent.Parent.Codec.Fields)
local Move = require(script.Parent.Parent.Codec.Move)
local Public = require(script.Parent.Parent.Step.Public)
local Reports = require(script.Parent.Reports)
local Sequence = require(script.Parent.Parent.Codec.Sequence)
local State = require(script.Parent.Parent.Step.State)

local WRAP: number = 2 ^ 16 -- A command number is a u16
local NO_TICK: number = -math.huge -- What an unused slot holds, which no tick equals

-- The longest move an honest client puts on the wire, squared: a full input, and half a step of rounding on each axis
local LONGEST_SQUARED: number = (Constants.MOVE_STEPS + math.sqrt(2) / 2) ^ 2

type Command = State.Command
type Connection = Connections.Connection
type Entry = Fields.Entry
type Layout = Fields.Layout
type Pressed = State.Pressed
type Values = State.Values
type Wire = Command.Wire

-- What became of a command the ring holds: waiting for its tick, run on it, discarded with its presses still to
-- carry, discarded and done with, or dropped from the queue before its tick
type Status = "queued" | "ran" | "late" | "spent" | "dropped"

-- One tick's place in a connection's ring: the command that belongs to it, and its first copy as Volt delivered it
type Slot = {
	full: number, -- The tick, counted on past the u16 wrap
	status: Status,
	arrived: number, -- The clock when Volt delivered its first copy
	command: Command, -- That first copy, decoded
	moveX: number, -- Its wire fields, which every later copy is compared with
	moveZ: number,
	buttons: number,
	yaw: number,
	pitch: number,
	lean: number,
	headYaw: number,
	headPitch: number,
	fields: buffer, -- Its game fields' bytes
	length: number, -- How many of them it filled
}

-- Everything Commands keeps for one connection
type Intake = {
	slots: { Slot }, -- A tick's is at its count modulo the ring's size, plus 1
	acknowledged: number, -- The newest relay sequence the client received, 0 for none
	received: number, -- The 16 sequences before it, bit 0 for the one just before
	delay: number, -- The interpolation delay in milliseconds its newest Move gave
	newest: number?, -- The newest command number filed or reported late
	look: vector?, -- That command's look on the ground, a unit vector
	taken: number?, -- The newest tick a command was taken for
	real: number?, -- The tick of the newest real command it ran
	levels: Pressed, -- That command's button levels, which a press reads when the ring holds no earlier command
	standIns: number, -- Stand-ins in a row since that command
	standIn: Command, -- The stand-in it steps, made once and reused
}

local Intakes: { [Connection]: Intake } = {}
local Incoming: Move.Incoming = Move.incoming() -- Each Move decodes here first, so a refused one changes nothing
local Now: number? = nil -- The newest tick stepped, counted on past the u16 wrap, nil before the first

local Clock: () -> number = os.clock -- Seconds, which a command's arrival and the tick that takes it are timed on
local TookAt: number = 0 -- The clock at the newest tick's first take, which each command that tick takes waited until

-- From the shared table and the compiled layout at start
local Compiled: Layout? = nil
local Limits: Command.Limits = { lean = 0, headCone = 0 }
local Entries: { Entry } = {} -- The game's command fields
local Carried: { Entry } = {} -- Those a discarded command carries into the next real one
local Dropped: { Entry } = {} -- Those whose presses a discarded command loses, such as shots
local StandIn: number = 0 -- Ticks a stand-in repeats the held inputs for
local Ahead: number = 0 -- The furthest ahead of the newest tick stepped a command is filed
local QueueWait: number = 0 -- The most queue wait a command's take reports
local Rate: number = 0 -- Simulation ticks a second
local Behind: number = 0 -- Ticks the ring holds at and before the newest stepped
local Size: number = 0 -- Slots in each ring, the ticks from Behind to Ahead

local Commands = {}

--[[
    Takes the shared table's ticks, its simulation rate and the step's lean
    and head cone limits, and the layout Fields.compile made of its
    declarations. It runs once, before the first Move
--]]

function Commands.start(shared: Config.Shared, layout: Layout)
	if Compiled then
		error("Commands.start runs once, and it has already run", 2)
	end

	StandIn = shared.ticks.standIn
	Ahead = shared.ticks.ahead
	QueueWait = shared.ticks.queueWait
	Rate = shared.rates.simulation
	Limits.lean = shared.step.lean
	Limits.headCone = shared.step.headCone

	-- A Move's worth of ticks, so a later Move's copy still finds its first, and the stand-in window with the tick it
	-- ends on, so a discarded command is still held when the real command its presses carry into runs
	Behind = math.max(Constants.MAX_COMMANDS, StandIn + 1)
	Size = Ahead + Behind

	Entries = layout.command.entries
	for _, entry: Entry in Entries do
		if entry.kind == "carried" then
			table.insert(Carried, entry)
		elseif entry.kind == "dropped" then
			table.insert(Dropped, entry)
		end
	end

	Compiled = layout
end

--[[
    Hands Commands the clock in seconds it times each command's queue
    wait on, in place of os.clock, so a case can set the time by hand
--]]

function Commands.setClock(clock: () -> number)
	if type(clock) ~= "function" then
		error(`Commands.setClock takes a function giving seconds, not a {typeof(clock)}`, 2)
	end

	Clock = clock
end

--[[
    The time on the clock Commands times queue waits on, which the server
    stamps each Move with as Volt delivers it
--]]

function Commands.now(): number
	return Clock()
end

-- One slot of a ring, holding no tick yet
local function slot(): Slot
	return {
		full = NO_TICK,
		status = "spent",
		arrived = 0,
		command = Command.new(),
		moveX = 0,
		moveZ = 0,
		buttons = 0,
		yaw = 0,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = buffer.create(Constants.MAX_COMMAND_FIELDS),
		length = 0,
	}
end

-- A connection's intake, made the first time Commands hears of it
local function intakeOf(connection: Connection): Intake
	local intake: Intake? = Intakes[connection]
	if intake then
		return intake
	elseif type(connection) ~= "table" or connection.player == nil then
		error(`Commands takes a connection record from Connections.add, not a {typeof(connection)}`, 3)
	end

	local slots: { Slot } = {}
	for _ = 1, Size do
		table.insert(slots, slot())
	end

	local made: Intake = {
		slots = slots,
		acknowledged = 0,
		received = 0,
		delay = 0,
		newest = nil,
		look = nil,
		taken = nil,
		real = nil,
		levels = { jump = false, crouch = false, sprint = false, aim = false },
		standIns = 0,
		standIn = Command.new(),
	}

	Intakes[connection] = made

	return made
end

-- The number nearest 0 that a number field's range holds, its value when it holds no press
local function rest(entry: Entry): number
	return math.clamp(0, entry.min, entry.max)
end

local presses: (entry: Entry, value: any) -> number

-- Whether one value of a field holds a press: true, a number off its rest, or a group with a press inside
local function active(entry: Entry, value: any): boolean
	local entryType: string = entry.type

	if entryType == "bool" then
		return value == true
	elseif entryType == "group" then
		for _, inner: Entry in entry.fields do
			if presses(inner, value[inner.name]) > 0 then
				return true
			end
		end

		return false
	end

	return value ~= rest(entry)
end

-- The presses a field holds, such as the shots in a list of them: one for each element of a list, or one for a value
function presses(entry: Entry, value: any): number
	if entry.count > 0 then
		return #value
	elseif active(entry, value) then
		return 1
	end

	return 0
end

-- A field set to hold no press, into the table already there for a list or a group
local function neutral(entry: Entry, existing: any): any
	if entry.count > 0 then
		if type(existing) ~= "table" then
			return {}
		end

		table.clear(existing)

		return existing
	elseif entry.type == "bool" then
		return false
	elseif entry.type == "group" then
		local group: Values = existing
		if type(existing) ~= "table" then
			group = {}
		end

		for _, inner: Entry in entry.fields do
			group[inner.name] = neutral(inner, group[inner.name])
		end

		return group
	end

	return rest(entry)
end

-- A copy of one of the game's values, a list or a group copied into the table already there
local function copy(value: any, existing: any): any
	if type(value) ~= "table" then
		return value
	end

	local into: Values = existing
	if type(existing) ~= "table" then
		into = {}
	end

	for key: any, inner: any in value do
		into[key] = copy(inner, into[key])
	end

	for key: any in into do
		if value[key] == nil then
			into[key] = nil
		end
	end

	return into
end

-- Whether a later copy of a command differs from its first copy, in Tread's own fields or the game's bytes
local function differs(held: Slot, wire: Wire): boolean
	if
		held.moveX ~= wire.moveX
		or held.moveZ ~= wire.moveZ
		or held.buttons ~= wire.buttons
		or held.yaw ~= wire.yaw
		or held.pitch ~= wire.pitch
		or held.lean ~= wire.lean
		or held.headYaw ~= wire.headYaw
		or held.headPitch ~= wire.headPitch
	then
		return true
	end

	local bytes: buffer = wire.fields
	local length: number = buffer.len(bytes)
	if length ~= held.length then
		return true
	end

	for offset: number = 0, length - 1 do
		if buffer.readu8(bytes, offset) ~= buffer.readu8(held.fields, offset) then
			return true
		end
	end

	return false
end

--[[
    Files a command's first copy in its tick's slot: the wire as Volt
    delivered it, which every later copy is compared with, and the decoded
    command, swapped with the one the slot held so neither is made anew
--]]

local function keep(held: Slot, full: number, status: Status, arrived: number, wire: Wire, position: number)
	held.full = full
	held.status = status
	held.arrived = arrived
	held.moveX = wire.moveX
	held.moveZ = wire.moveZ
	held.buttons = wire.buttons
	held.yaw = wire.yaw
	held.pitch = wire.pitch
	held.lean = wire.lean
	held.headYaw = wire.headYaw
	held.headPitch = wire.headPitch

	local length: number = buffer.len(wire.fields)
	buffer.copy(held.fields, 0, wire.fields, 0, length)
	held.length = length

	local decoded: Command = Incoming.commands[position]
	Incoming.commands[position] = held.command
	held.command = decoded
end

-- Reports a command that arrived after its tick ran with a stand-in, and the shots in it, which never carry
local function discard(connection: Connection, command: Command, late: number)
	Reports.fire(connection.player, "late", late)

	local shots: number = 0
	for _, entry: Entry in Dropped do
		shots += presses(entry, command.fields[entry.name])
	end

	if shots > 0 then
		Reports.fire(connection.player, "lateShot", shots)
	end
end

--[[
    Keeps a command numbered past every one filed or reported late as the
    newest, with its look on the ground: its base yaw turned by its head
    offset, held to the head cone, its pitch left out. False for any other
--]]

local function advance(intake: Intake, command: Command): boolean
	local newest: number? = intake.newest
	if newest ~= nil and Sequence.difference(command.number, newest) <= 0 then
		return false
	end

	intake.newest = command.number
	intake.look = Public.look(command.yaw, 0, command.headYaw, 0, Limits.headCone)

	return true
end

--[[
    Files each command of a Move as Volt's Move listener delivers it by the
    tick it belongs to: a first copy up to ticks.ahead past the newest tick
    stepped waits for its tick, one further ahead is dropped, and one whose
    tick has run is discarded, its jump and crouch presses and its carried
    fields kept for the next real command. A later copy that differs from
    the first is ignored and reported. A Move whose game fields fail their
    declarations is refused whole, its acknowledgments included

    @ arrived | the clock when Volt delivered the Move, Commands.now() when left out
--]]

function Commands.receive(
	connection: Connection,
	command: number,
	acknowledged: number,
	received: number,
	delay: number,
	wires: { Wire },
	arrived: number?
)
	local layout: Layout? = Compiled
	if not layout then
		error("Commands.receive ran before Commands.start", 2)
	end

	local intake: Intake = intakeOf(connection)

	local failed: number? = Move.decode(command, acknowledged, received, delay, wires, layout, Limits, Incoming)
	if failed then
		Reports.fire(connection.player, "schema", failed)

		return
	end

	-- A Move that arrives behind a newer one knows no more than it did, so the newest acknowledgment stands
	local newer: number = Sequence.difference(acknowledged, intake.acknowledged)
	if newer > 0 then
		intake.acknowledged = acknowledged
		intake.received = received
	elseif newer == 0 then
		intake.received = bit32.bor(intake.received, received)
	end

	if newer >= 0 then
		intake.delay = delay
	end

	-- Until a tick has run there is none to file a command against
	local now: number? = Now
	if now == nil then
		return
	end

	local at: number = arrived or Clock()
	local furthest: number = 0
	for position: number = 1, Incoming.count do
		local decoded: Command = Incoming.commands[position]
		local number: number = decoded.number
		local lead: number = Sequence.difference(number, now)

		if lead > Ahead then
			furthest = math.max(furthest, lead)
		elseif lead <= -Behind then
			-- Older than the ring holds, so only a number newer than every one filed can be a first copy
			if advance(intake, decoded) then
				discard(connection, decoded, 1 - lead)
			end
		else
			local full: number = now + lead
			local held: Slot = intake.slots[full % Size + 1]
			local wire: Wire = wires[position]

			if held.full == full then
				if differs(held, wire) then
					Reports.fire(connection.player, "moveTamper", number)
				end
			else
				advance(intake, decoded)

				if lead > 0 then
					keep(held, full, "queued", at, wire, position)
				else
					keep(held, full, "late", at, wire, position)
					discard(connection, held.command, 1 - lead)
				end

				if wire.moveX * wire.moveX + wire.moveZ * wire.moveZ > LONGEST_SQUARED then
					Reports.fire(connection.player, "moveTamper", number)
				end
			end
		end
	end

	if furthest > 0 then
		Reports.fire(connection.player, "ahead", furthest)
	end
end

-- The command held for the newest tick before full, whatever became of it, or nil when the ring holds none
local function before(intake: Intake, full: number): Command?
	local slots: { Slot } = intake.slots

	for back: number = full - 1, full - Size + 1, -1 do
		local held: Slot = slots[back % Size + 1]
		if held.full == back then
			return held.command
		end
	end

	return nil
end

--[[
    Sets a command's presses: each button held in it and not in the
    client's command before it, the newest earlier one the ring holds, or
    the last real command run when it holds none
--]]

local function press(intake: Intake, full: number, command: Command)
	local jump: boolean, crouch: boolean, sprint: boolean, aim: boolean
	local previous: Command? = before(intake, full)

	if previous then
		jump, crouch, sprint, aim = previous.jump, previous.crouch, previous.sprint, previous.aim
	else
		local levels: Pressed = intake.levels
		jump, crouch, sprint, aim = levels.jump, levels.crouch, levels.sprint, levels.aim
	end

	local pressed: Pressed = command.pressed
	pressed.jump = command.jump and not jump
	pressed.crouch = command.crouch and not crouch
	pressed.sprint = command.sprint and not sprint
	pressed.aim = command.aim and not aim
end

-- Carries a discarded command's jump and crouch presses, and its carried fields by OR or by addition, into a real one
local function carry(intake: Intake, full: number, late: Command, command: Command)
	press(intake, full, late)

	local pressed: Pressed = command.pressed
	pressed.jump = pressed.jump or late.pressed.jump
	pressed.crouch = pressed.crouch or late.pressed.crouch

	local fields: Values = command.fields
	for _, entry: Entry in Carried do
		local name: string = entry.name

		if entry.type == "bool" then
			fields[name] = fields[name] or late.fields[name]
		else
			fields[name] = math.min(fields[name] + late.fields[name], entry.max)
		end
	end
end

--[[
    Runs the real command filed for a tick: its presses, those of every
    command discarded since the last real one inside the stand-in window,
    and the gap it ends
--]]

local function takeReal(connection: Connection, intake: Intake, held: Slot, full: number): (Command, boolean, number)
	local command: Command = held.command
	press(intake, full, command)

	local from: number = full - StandIn
	local real: number? = intake.real
	if real ~= nil and real >= from then
		from = real + 1
	end

	for back: number = from, full - 1 do
		local late: Slot = intake.slots[back % Size + 1]
		if late.full == back and late.status == "late" then
			carry(intake, back, late.command, command)
			late.status = "spent"
		end
	end

	held.status = "ran"
	intake.real = full

	local levels: Pressed = intake.levels
	levels.jump = command.jump
	levels.crouch = command.crouch
	levels.sprint = command.sprint
	levels.aim = command.aim

	if intake.standIns > 0 then
		Reports.fire(connection.player, "gap", intake.standIns / Rate)
		intake.standIns = 0
	end

	return command, false, math.min((TookAt - held.arrived) * Rate, QueueWait)
end

--[[
    Readies the stand-in for a run of them: the last real command's held
    inputs and held fields, or none with no real command held, and never a
    press
--]]

local function prepare(intake: Intake)
	local standIn: Command = intake.standIn
	local last: Command? = nil

	local real: number? = intake.real
	if real ~= nil then
		local held: Slot = intake.slots[real % Size + 1]
		if held.full == real then
			last = held.command
		end
	end

	local pressed: Pressed = standIn.pressed
	pressed.jump = false
	pressed.crouch = false
	pressed.sprint = false
	pressed.aim = false
	standIn.jump = false

	if last then
		standIn.forward = last.forward
		standIn.right = last.right
		standIn.crouch = last.crouch
		standIn.sprint = last.sprint
		standIn.aim = last.aim
		standIn.yaw = last.yaw
		standIn.pitch = last.pitch
		standIn.lean = last.lean
		standIn.headYaw = last.headYaw
		standIn.headPitch = last.headPitch
	else
		standIn.forward = 0
		standIn.right = 0
		standIn.crouch = false
		standIn.sprint = false
		standIn.aim = false
		standIn.yaw = 0
		standIn.pitch = 0
		standIn.lean = 0
		standIn.headYaw = 0
		standIn.headPitch = 0
	end

	local fields: Values = standIn.fields
	for _, entry: Entry in Entries do
		local name: string = entry.name

		if last and entry.kind == "held" then
			fields[name] = copy(last.fields[name], fields[name])
		else
			fields[name] = neutral(entry, fields[name])
		end
	end
end

--[[
    Steps a stand-in for a tick with no real command: for ticks.standIn
    ticks the last real command's held inputs, and after them no move and
    no sprint, with posture, aim, look, lean and the held fields kept
--]]

local function takeStandIn(connection: Connection, intake: Intake, full: number): (Command, boolean, number)
	intake.standIns += 1

	local standIn: Command = intake.standIn
	if intake.standIns == 1 then
		prepare(intake)
	end

	if intake.standIns > StandIn then
		standIn.forward = 0
		standIn.right = 0
		standIn.sprint = false
	end

	standIn.number = full % WRAP

	Reports.fire(connection.player, "standIn", intake.standIns)

	return standIn, true, 0
end

--[[
    The command a connection's body steps on a tick, whether it is a
    stand-in, and how long it waited in the queue, in simulation ticks with
    their fraction from its arrival to the tick's first take, at most
    ticks.queueWait and 0 for a stand-in. The command is the queue's own
    table, good until the connection's next take
--]]

function Commands.take(connection: Connection, tick: number): (Command, boolean, number)
	if not Compiled then
		error("Commands.take ran before Commands.start", 2)
	elseif type(tick) ~= "number" or tick % 1 ~= 0 then
		error(`Commands.take takes a whole tick, not {tick}`, 2)
	end

	local intake: Intake = intakeOf(connection)

	local now: number = Now or tick
	local full: number = now + Sequence.difference(tick, now)
	if Now == nil or full > now then
		Now = full
		TookAt = Clock()
	end

	local taken: number? = intake.taken
	if taken ~= nil and full <= taken then
		error(`Commands.take ran for tick {tick}, which is not after the last tick it took for this connection`, 2)
	end

	intake.taken = full

	local held: Slot = intake.slots[full % Size + 1]
	if held.full == full and held.status == "queued" then
		return takeReal(connection, intake, held, full)
	end

	return takeStandIn(connection, intake, full)
end

--[[
    The newest relay sequence the client received and the mask of the 16
    before it, bit 0 for the one just before, both 0 until a Move arrives
--]]

function Commands.acknowledged(connection: Connection): (number, number)
	local intake: Intake? = Intakes[connection]
	if not intake then
		return 0, 0
	end

	return intake.acknowledged, intake.received
end

--[[
    The interpolation delay in milliseconds the client's newest Move gave,
    which a shot's rewind reads, 0 until a Move arrives
--]]

function Commands.delay(connection: Connection): number
	local intake: Intake? = Intakes[connection]
	if not intake then
		return 0
	end

	return intake.delay
end

--[[
    The look of the newest command the client sent, on the ground: its base
    yaw turned by its head offset, held to the head cone, as a unit vector,
    which the relay's view cone reads. Nil until a command is filed
--]]

function Commands.look(connection: Connection): vector?
	local intake: Intake? = Intakes[connection]
	if not intake then
		return nil
	end

	return intake.look
end

--[[
    How many commands wait for ticks after the newest one stepped, the
    queue depth OwnerState carries
--]]

function Commands.depth(connection: Connection): number
	local intake: Intake? = Intakes[connection]
	local now: number? = Now
	if not intake or now == nil then
		return 0
	end

	local depth: number = 0
	for full: number = now + 1, now + Ahead do
		local held: Slot = intake.slots[full % Size + 1]
		if held.full == full and held.status == "queued" then
			depth += 1
		end
	end

	return depth
end

--[[
    Drops every command waiting for its tick, and every press a discarded
    command would carry, as a teleport does. A later copy of a dropped
    command is still a copy, so it never comes back into the queue
--]]

function Commands.drop(connection: Connection)
	local intake: Intake? = Intakes[connection]
	if not intake then
		return
	end

	for _, held: Slot in intake.slots do
		if held.status == "queued" then
			held.status = "dropped"
		elseif held.status == "late" then
			held.status = "spent"
		end
	end
end

--[[
    Forgets everything kept for a connection that left
--]]

function Commands.remove(connection: Connection)
	Intakes[connection] = nil
end

return Commands
