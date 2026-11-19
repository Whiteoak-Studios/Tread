--[[
    A seeded stream of Moves gives the same reports, commands, presses and
    acknowledgments with lazy decode on as off, with no game fields, the
    fixture game's 10 to 18 B and 64 B
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local BOT: string = "Bot" -- The bot each Commands hears from
local BOT_RTT: number = 0.1 -- Seconds the bot's connection reports
local SEED: number = 4721
local START: number = 65400 -- The first tick stepped, so the stream runs past the u16 wrap
local TICKS: number = 320 -- Ticks the stream runs for
local WRAP: number = 2 ^ 16 -- A command number and a relay sequence are u16s
local LEAD: number = 2 -- Ticks ahead of the server the client aims its newest command
local RESYNC: number = 3 -- Ticks off that lead past which the client snaps back to it
local RESUME: number = 2 -- Ticks a client goes on numbering from where it froze, before it snaps
local SPARES: number = 3 -- The commands a Move usually carries: the newest and the two before it
local PALETTE: number = 3 -- The inputs a client sends again and again
local BUTTONS: number = 15 -- Jump, crouch, sprint and aim, bits 0 to 3
local BUTTON_BITS: number = 15 -- The top bit of the u16 buttons
local BYTE_BITS: number = 7 -- The top bit of a byte
local BYTE: number = 255
local MASK: number = WRAP - 1 -- Every bit of a received mask
local DELAY: number = 255 -- The most a Move's u8 delay holds
local HALF: number = 0.5
local EDGE: number = 0.25 -- The share of draws that land on each end of a range
local TAMPERS: number = 9 -- The ways a spare is made to differ from its first copy

-- How often each turn of the stream comes, as a share of the ticks or the Moves it can come on
local FREEZE: number = 0.015 -- The client stops for a while, then sends its old commands
local FREEZE_MIN: number = 4
local FREEZE_MAX: number = 14
local JUMP: number = 0.02 -- The client runs past the ahead limit
local JUMP_MIN: number = 6
local JUMP_MAX: number = 9
local IDLE: number = 0.08 -- The client makes no command this tick
local DOUBLE: number = 0.08 -- The client makes two
local USUAL: number = 0.7 -- A Move carries its usual three commands
local EMPTY: number = 0.05 -- A Move carries none
local REPEAT: number = 0.5 -- A new command's inputs are ones the client sent before
local TAMPER: number = 0.06 -- A spare differs from its first copy
local BAD: number = 0.03 -- A command's game fields fail their declarations
local LOST: number = 0.1 -- A Move never arrives
local LATE: number = 0.1 -- A Move arrives after the next one
local TWICE: number = 0.05 -- A Move arrives twice

-- The reports a stream must raise to show it reached each path, the late shots only where the game declares shots
local KINDS: { string } = { "ahead", "late", "moveTamper", "schema", "standIn", "gap" }
local SHOT_KINDS: { string } = { "ahead", "late", "lateShot", "moveTamper", "schema", "standIn", "gap" }

type Wire = {
	moveX: number,
	moveZ: number,
	buttons: number,
	yaw: number,
	pitch: number,
	lean: number,
	headYaw: number,
	headPitch: number,
	fields: buffer,
}

-- One turn of the stream: a tick taken, or a Move delivered when it has no tick
type Event = {
	tick: number?, -- Counted on past the u16 wrap
	clock: number, -- Seconds on the clock it comes at
	command: number,
	acknowledged: number,
	received: number,
	delay: number,
	wires: { Wire },
}

-- A Commands of its own, the bot it hears from and the reports it has fired
type Rig = {
	Commands: any,
	connection: any,
	heard: { string },
	kinds: { [string]: boolean },
}

-- Declarations a stream runs under, and the reports it must raise
type Setup = {
	name: string,
	fields: { [string]: any },
	kinds: { string },
}

local SETUPS: { Setup } = {
	{
		name = "no game fields",
		fields = { command = {}, rules = {}, server = {}, slot = {}, held = {} },
		kinds = KINDS,
	},
	{ name = "the fixture game's fields", fields = Game.fields, kinds = SHOT_KINDS },
	{
		name = "64 B of game fields",
		fields = { command = Game.largest.command, rules = {}, server = {}, slot = {}, held = {} },
		kinds = KINDS,
	},
}

-- A whole number from low to high, on each end a share of the time
local function draw(low: number, high: number): number
	local roll: number = math.random()
	if roll < EDGE then
		return low
	elseif roll < 2 * EDGE then
		return high
	end

	return low + math.floor(math.random() * (high - low + 1))
end

local drawField: (entry: any) -> any

-- One value of a compiled field: a group's fields, a bool or a number in its range
local function drawValue(entry: any): any
	if entry.type == "group" then
		local group: { [string]: any } = {}
		for _, inner: any in entry.fields do
			group[inner.name] = drawField(inner)
		end

		return group
	elseif entry.type == "bool" then
		return draw(0, 1) == 1
	end

	return draw(entry.min, entry.max)
end

-- A compiled field's value, or a list of them as long as its count allows
function drawField(entry: any): any
	if entry.count == 0 then
		return drawValue(entry)
	end

	local list: { any } = {}
	for _ = 1, draw(0, entry.count) do
		table.insert(list, drawValue(entry))
	end

	return list
end

-- A wire command of its own, its game bytes in a buffer of their own
local function copy(wire: Wire): Wire
	local bytes: buffer = buffer.create(buffer.len(wire.fields))
	buffer.copy(bytes, 0, wire.fields)

	return {
		moveX = wire.moveX,
		moveZ = wire.moveZ,
		buttons = wire.buttons,
		yaw = wire.yaw,
		pitch = wire.pitch,
		lean = wire.lean,
		headYaw = wire.headYaw,
		headPitch = wire.headPitch,
		fields = bytes,
	}
end

-- A value one step from where it is, inside high either way
local function nudge(value: number, high: number): number
	return value < high and value + 1 or value - 1
end

-- A value's text, a table's keys in order, so two equal values read the same
local function serialize(value: any): string
	if type(value) ~= "table" then
		return tostring(value)
	end

	local keys: { any } = {}
	for key: any in value do
		table.insert(keys, key)
	end

	table.sort(keys, function (a: any, b: any): boolean
		return tostring(a) < tostring(b)
	end)

	local parts: { string } = {}
	for _, key: any in keys do
		table.insert(parts, `{key}={serialize(value[key])}`)
	end

	return `[{table.concat(parts, ",")}]`
end

--[[
    The stream: a Move before the first tick, then a tick a turn with the
    client's Move after it, the client keeping its lead, freezing, running
    ahead, losing, reordering and repeating Moves, and sending spares that
    differ and game fields that fail
--]]

local function stream(Fields: any, Constants: any, layout: any, rate: number): { Event }
	local list: any = layout.command
	local scratch: buffer = buffer.create(Constants.MAX_COMMAND_FIELDS)
	local move: number = Constants.MOVE_STEPS
	local pitch: number = Constants.PITCH_LIMIT
	local lean: number = Constants.LEAN_STEPS
	local head: number = Constants.HEAD_STEPS
	local angles: number = Constants.ANGLE_STEPS
	local most: number = Constants.MAX_COMMAND_FIELDS

	local function fresh(): Wire
		local values: { [string]: any } = {}
		for _, entry: any in list.entries do
			values[entry.name] = drawField(entry)
		end

		local length: number = Fields.write(list, values, scratch, 0)
		local bytes: buffer = buffer.create(length)
		buffer.copy(bytes, 0, scratch, 0, length)

		return {
			moveX = draw(-move, move),
			moveZ = draw(-move, move),
			buttons = draw(0, BUTTONS),
			yaw = draw(0, angles - 1),
			pitch = draw(-pitch, pitch),
			lean = draw(-lean, lean),
			headYaw = draw(-head, head),
			headPitch = draw(-head, head),
			fields = bytes,
		}
	end

	local palette: { Wire } = {}
	for _ = 1, PALETTE do
		table.insert(palette, fresh())
	end

	-- Every copy of a command the client sends is its first, unless the stream tampers with it
	local canonical: { [number]: Wire } = {}
	local function wireOf(number: number): Wire
		local made: Wire? = canonical[number]
		if made then
			return made
		end

		local wire: Wire
		if math.random() < REPEAT then
			wire = palette[math.random(PALETTE)]
		else
			wire = fresh()
			palette[math.random(PALETTE)] = wire
		end

		canonical[number] = wire

		return wire
	end

	-- One of Tread's fields a step off, a button bit flipped, or the game's bytes changed, from 0 to 64 B
	local function tamper(wire: Wire)
		local way: number = math.random(TAMPERS)
		if way == 1 then
			wire.moveX = nudge(wire.moveX, move)
		elseif way == 2 then
			wire.moveZ = nudge(wire.moveZ, move)
		elseif way == 3 then
			wire.buttons = bit32.bxor(wire.buttons, 2 ^ math.random(0, BUTTON_BITS))
		elseif way == 4 then
			wire.yaw = (wire.yaw + 1) % angles
		elseif way == 5 then
			wire.pitch = nudge(wire.pitch, pitch)
		elseif way == 6 then
			wire.lean = nudge(wire.lean, lean)
		elseif way == 7 then
			wire.headYaw = nudge(wire.headYaw, head)
		elseif way == 8 then
			wire.headPitch = nudge(wire.headPitch, head)
		else
			local length: number = buffer.len(wire.fields)
			if length > 0 and math.random() < HALF then
				local at: number = math.random(0, length - 1)
				local flipped: number = bit32.bxor(buffer.readu8(wire.fields, at), 2 ^ math.random(0, BYTE_BITS))
				buffer.writeu8(wire.fields, at, flipped)
			else
				local other: number = math.random(0, most)
				local bytes: buffer = buffer.create(other)
				buffer.copy(bytes, 0, wire.fields, 0, math.min(length, other))

				for at: number = length, other - 1 do
					buffer.writeu8(bytes, at, math.random(0, BYTE))
				end

				wire.fields = bytes
			end
		end
	end

	-- Game bytes one longer than their fields fill, or one short at 64 B, which their declarations refuse
	local function spoil(wire: Wire)
		local length: number = buffer.len(wire.fields)
		local bytes: buffer = buffer.create(length < most and length + 1 or length - 1)
		buffer.copy(bytes, 0, wire.fields, 0, math.min(length, buffer.len(bytes)))
		wire.fields = bytes
	end

	local events: { Event } = {}
	local newest: number = START + LEAD
	local sequence: number = 0

	local function moveAt(clock: number): Event
		local count: number = SPARES
		if math.random() >= USUAL then
			count = math.random() < EMPTY and 0 or math.random(1, Constants.MAX_COMMANDS)
		end

		local wires: { Wire } = {}
		for position: number = 1, count do
			local wire: Wire = copy(wireOf(newest - (position - 1)))
			if position > 1 and math.random() < TAMPER then
				tamper(wire)
			end

			table.insert(wires, wire)
		end

		if count > 0 and math.random() < BAD then
			spoil(wires[math.random(count)])
		end

		sequence = (sequence + 1) % WRAP

		return {
			tick = nil,
			clock = clock,
			command = count > 0 and newest % WRAP or 0,
			acknowledged = sequence,
			received = math.random(0, MASK),
			delay = math.random(0, DELAY),
			wires = wires,
		}
	end

	-- The first Move comes before any tick has run
	table.insert(events, moveAt(0))

	local frozen: number = 0
	local resume: number = 0
	local held: Event? = nil -- A Move that arrives after the next one

	for index: number = 0, TICKS - 1 do
		local tick: number = START + index
		table.insert(events, {
			tick = tick,
			clock = index / rate,
			command = 0,
			acknowledged = 0,
			received = 0,
			delay = 0,
			wires = {},
		})

		local late: Event? = held
		held = nil

		local roll: number = math.random()
		if frozen > 0 then
			frozen -= 1
			if frozen == 0 then
				resume = RESUME
			end
		elseif roll < FREEZE then
			frozen = math.random(FREEZE_MIN, FREEZE_MAX)
		else
			if roll < FREEZE + JUMP then
				newest += math.random(JUMP_MIN, JUMP_MAX)
			elseif resume > 0 then
				newest += 1
				resume -= 1
			elseif newest < tick + LEAD - RESYNC then
				newest = tick + LEAD
			elseif newest <= tick + LEAD + RESYNC then
				local made: number = math.random()
				newest += made < IDLE and 0 or made < IDLE + DOUBLE and 2 or 1
			end

			local sent: Event = moveAt((index + math.random()) / rate)
			local fate: number = math.random()
			if fate >= LOST + LATE then
				table.insert(events, sent)

				if math.random() < TWICE then
					table.insert(events, sent)
				end
			elseif fate >= LOST then
				held = sent
			end
		end

		if late then
			late.clock = (index + math.random()) / rate
			table.insert(events, late)
		end
	end

	return events
end

-- A fresh Commands started over the declarations and timed on clock, with lazy decode set and its bot's connection
local function build(fields: { [string]: any }, lazy: boolean, clock: () -> number): Rig
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local example: any = globals.require(globals.game:GetService("ServerScriptService").Fixtures.Config.Example)
	local Commands: any = globals.require(tread.Server.Commands)
	local Connections: any = globals.require(tread.Server.Connections)
	local made: Rig = { Commands = Commands, connection = nil, heard = {}, kinds = {} }

	globals.require(tread.Server.Reports).connect(function (_: any, kind: string, measurement: number | string)
		table.insert(made.heard, `{kind} {measurement}`)
		made.kinds[kind] = true
	end)

	Commands.start(example.shared(), globals.require(tread.Codec.Fields).compile(fields))
	Commands.setClock(clock)
	Commands.useLazy(lazy)
	Connections.start(example.server().rewind.rttSmoothing, { rtt = BOT_RTT })
	made.connection = Connections.add({ Name = BOT })

	return made
end

-- Runs one turn of the stream on a rig, and gives what came of it with the reports it fired
local function apply(rig: Rig, event: Event): string
	local Commands: any = rig.Commands
	local connection: any = rig.connection
	local line: string

	local tick: number? = event.tick
	if tick then
		local command: any, standIn: boolean, wait: number = Commands.take(connection, tick % WRAP)
		line = `take {tick}: {standIn} {wait} {serialize(command)}`
	else
		local wires: { Wire } = {}
		for _, wire: Wire in event.wires do
			table.insert(wires, copy(wire))
		end

		Commands.receive(connection, event.command, event.acknowledged, event.received, event.delay, wires)

		local acknowledged: number, received: number = Commands.acknowledged(connection)
		local look: any = Commands.look(connection)
		local seen: string = look and `{look.x} {look.y} {look.z}` or "none"
		line = `move: {acknowledged} {received} {Commands.delay(connection)} {Commands.depth(connection)} {seen}`
	end

	local heard: string = table.concat(rig.heard, "; ")
	table.clear(rig.heard)

	return `{line} | {heard}`
end

return function (): (boolean, string | nil)
	local packer: any = Environment.load(GLOBALS)
	local tread: any = packer.game:GetService("ReplicatedStorage").Packages.Tread
	local example: any = packer.require(packer.game:GetService("ServerScriptService").Fixtures.Config.Example)
	local Fields: any = packer.require(tread.Codec.Fields)
	local Constants: any = packer.require(tread.Constants)
	local rate: number = example.shared().rates.simulation

	for index: number, setup: Setup in SETUPS do
		math.randomseed(SEED + index)
		local events: { Event } = stream(Fields, Constants, Fields.compile(setup.fields), rate)

		local now: number = 0
		local function clock(): number
			return now
		end

		local on: Rig = build(setup.fields, true, clock)
		local off: Rig = build(setup.fields, false, clock)

		for step: number, event: Event in events do
			now = event.clock

			local lazy: string = apply(on, event)
			local eager: string = apply(off, event)
			if lazy ~= eager then
				return false, `With {setup.name}, step {step}: lazy decode on gave "{lazy}", off gave "{eager}"`
			end
		end

		if on.Commands.skipped() == 0 then
			return false, `With {setup.name}, lazy decode passed over no command, so the stream proved nothing`
		elseif off.Commands.skipped() ~= 0 then
			return false, `With {setup.name}, lazy decode off passed over {off.Commands.skipped()} commands`
		end

		for _, kind: string in setup.kinds do
			if not off.kinds[kind] then
				return false, `With {setup.name}, the stream never raised a {kind} report, so it missed that path`
			end
		end
	end

	return true, nil
end
