--[[
    The owner's prediction: a command sampled and stepped each simulation
    tick, a Move each relay tick, each OwnerState reconciled and the clock
    held at its lead, and the body and its eye drawn between ticks
--]]

--!strict
--!native
local Command = require(script.Parent.Parent.Codec.Command)
local Constants = require(script.Parent.Parent.Constants)
local Eye = require(script.Parent.Parent.Step.Eye)
local Fields = require(script.Parent.Parent.Codec.Fields)
local Mantle = require(script.Parent.Parent.Step.Mantle)
local Math = require(script.Parent.Parent.Step.Math)
local Move = require(script.Parent.Parent.Codec.Move)
local OwnerState = require(script.Parent.Parent.Codec.OwnerState)
local Public = require(script.Parent.Parent.Step.Public)
local Sequence = require(script.Parent.Parent.Codec.Sequence)
local State = require(script.Parent.Parent.Step.State)
local Step = require(script.Parent.Parent.Step)

local QUANTUM: number = Constants.POSITION_QUANTUM -- Studs each quantum of a tolerance stands for
local ANGLE_STEPS: number = Constants.ANGLE_STEPS
local LEAN_STEPS: number = Constants.LEAN_STEPS
local MAX_COMMANDS: number = Constants.MAX_COMMANDS
local MOVE_REPEATS: number = Constants.MOVE_REPEATS
local TURN: number = 2 * math.pi -- Radians a turn, which a u16 angle counts in ANGLE_STEPS
local WRAP: number = 2 ^ 16 -- The numbers a u16 command number or wire tick holds
local DELAY_LIMIT: number = 2 ^ 8 - 1 -- The most milliseconds the Move's u8 delay holds
local MILLISECONDS: number = 1000 -- A second's
local HELD_LIMIT: number = 256 -- The most commands kept to replay, past the round trip and lead of any playable link

type Command = State.Command
type Layout = Fields.Layout
type Limits = Command.Limits
type Pressed = State.Pressed
type State = State.State
type Wire = Command.Wire
type World = State.World

-- The shared table's ticks the clock reads
type Ticks = {
	ahead: number, -- How far ahead the server queues a command before it drops it
	leadMin: number, -- The queue the clock holds at the server
	leadMax: number,
	nudge: number, -- The largest share the clock is nudged by
	resync: number, -- How far the lead may drift from the band's middle before the clock snaps
	debt: number, -- The ticks of time debt a frozen client keeps, at least 1
}

-- Each state's correction tolerance, in quanta of a position
type Tolerances = { Ground: number, Air: number, Swim: number, Ladder: number, Rider: number, Mantle: number }

-- What prediction reads from the shared table and the client settings, and the declarations the handle compiled
export type Settings = {
	rates: { simulation: number, relay: number }, -- Hz
	ticks: Ticks,
	tolerances: Tolerances,
	sample: (command: Command) -> (), -- Fills the command about to be sent with this tick's input
	look: () -> (number, number, number, number), -- This frame's base yaw and pitch, radians, and head offset, degrees
	smoothing: { decay: number, snap: number }, -- The visual error offset's shrink a second, and the size that snaps
	delay: () -> number, -- The interpolation delay remote characters are drawn at now, in seconds
	layout: Layout, -- The game's declarations, compiled
}

-- One command made, kept to repeat in a Move and to replay, with the state predicted after it
type Entry = {
	command: Command,
	state: State,
	predicted: boolean, -- Whether state holds its prediction
}

-- What start was handed, which every later call reads
type Run = {
	settings: Settings,
	world: World,
	send: (move: Move.Move) -> (),
	acknowledged: () -> (number, number),
	limits: Limits, -- The step settings' lean limit and head cone, which a command's steps count to
	share: number, -- Relay ticks a simulation tick
}

type Callback = (size: number, flagged: boolean) -> ()
type Listener = { callback: Callback, connected: boolean }

local Running: Run? = nil

-- The body's newest predicted tick, the one before it, the body drawn between them and the server's last state
local Current: State = State.new()
local Previous: State = State.new()
local Drawn: State = State.new()
local Server: State = State.new()

local Held: { Entry } = {} -- The commands kept, oldest first, each numbered one past the one before or past a skip
local Spare: { Entry } = {} -- Released entries, which the next commands reuse
local Outgoing: { Command } = {} -- The commands the next Move carries, newest first
local Outbound: Move.Move = Move.new() -- The Move each relay tick encodes into
local Scratch: Wire = Command.wire() -- Each sampled command's trip through the wire and back
local Last: Pressed = { jump = false, crouch = false, sprint = false, aim = false } -- The previous command's levels
local Listeners: { Listener } = {} -- The correction callbacks, in the order they connected

local Body: boolean = false -- Whether an OwnerState has started the body
local Newest: number = 0 -- The newest command number issued, skips included
local Numbered: boolean = false -- Whether any body has numbered a command yet, which a later body numbers past
local Acked: number = 0 -- The newest command the server says it ran
local LastTick: number = 0 -- The server tick of the newest OwnerState read
local TickOffset: number = 0 -- A command's number less the server tick it runs on
local Trip: number? = nil -- The commands the client makes in one round trip, once a queue has shown it
local Top: number? = nil -- The furthest tick the server's queue has reached, its tick plus its depth
local Issued: boolean = false -- Whether a command was made since the last OwnerState read, which a trip counts in
local Doubt: number = 0 -- OwnerStates judged in a row whose empty queue the trip puts a lead in
local Searching: boolean = false -- Whether an empty queue proved the trip wrong, and the clock searches for its lead
local Moved: boolean = false -- Whether that search has moved the clock yet
local Landing: boolean = false -- Whether a search that moved the clock just ended, so the next state lifts its lead
local Easing: boolean = false -- Whether the clock then eases down to the band's bottom from above
local Floor: number = 0 -- While it searches, the least and the most the round trip in commands can be
local Ceiling: number = math.huge
local Limit: number = 0 -- The floor past which the search starts again from none
local Settle: number? = nil -- The first command after a snap, before whose tick the clock judges nothing
local Hold: number = 0 -- Ticks left that issue no command, after a backward snap
local Rate: number = 1 -- The clock's nudged rate
local Clock: number = 0 -- Ticks owed, whose fraction places the drawn body between the last two
local RelayDue: number = 0 -- Relay ticks owed
local Fresh: number = 0 -- Commands made since the last Move
local Correction: vector = vector.zero -- The visual error offset on the drawn body
local LookYaw: number = 0 -- This frame's base look, radians, and its head offset, degrees
local LookPitch: number = 0
local HeadYaw: number = 0
local HeadPitch: number = 0
local Ledge: vector? = nil -- Where a jump press at the newest predicted tick would end a mantle, nil for none
local Searched: boolean = false -- Whether Ledge answers for the newest predicted tick

local Predict = {}

-- What start was handed, erroring for a call made before it
local function started(): Run
	local run: Run? = Running
	if not run then
		error("Predict.start must run before any other Predict call", 3)
	end

	return run
end

--[[
    Starts the owner's prediction, once: settings from the shared table and
    the client settings, the client's world, send, which fires the Move it
    is handed and flushes, and acknowledged, which gives the newest relay
    sequence received and the mask of the 16 before it
--]]

function Predict.start(
	settings: Settings,
	world: World,
	send: (move: Move.Move) -> (),
	acknowledged: () -> (number, number)
)
	if Running then
		error("Predict.start runs once, and it has already run", 2)
	elseif type(settings) ~= "table" or type(world) ~= "table" then
		error(`Predict.start takes the settings and the world as tables, not {typeof(settings)} and {typeof(world)}`, 2)
	elseif type(send) ~= "function" or type(acknowledged) ~= "function" then
		error(`Predict.start's send and acknowledged are functions, not {typeof(send)} and {typeof(acknowledged)}`, 2)
	elseif type(settings.sample) ~= "function" or type(settings.look) ~= "function" then
		error("Predict.start takes settings whose sample and look are functions", 2)
	elseif type(settings.delay) ~= "function" then
		error(`Predict.start takes settings whose delay is a function, not a {typeof(settings.delay)}`, 2)
	elseif not (settings.ticks.debt >= 1) then
		error(`Predict.start takes a ticks.debt of at least 1, or no tick ever runs, not {settings.ticks.debt}`, 2)
	end

	Running = {
		settings = settings,
		world = world,
		send = send,
		acknowledged = acknowledged,
		limits = { lean = world.settings.lean, headCone = world.settings.headCone },
		share = settings.rates.relay / settings.rates.simulation,
	}
end

-- An entry to make a command in, a released one when there is one
local function take(): Entry
	local entry: Entry? = table.remove(Spare)
	if entry then
		return entry
	end

	return { command = Command.new(), state = State.new(), predicted = false }
end

-- Puts Tread's own fields of a reused command back at rest, so a field the sample leaves alone carries nothing old
local function rest(command: Command)
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

--[[
    Steps the body one tick on a command, on the server tick its number
    runs on, keeping the state before it as the previous tick. A step that
    throws leaves the body where it was, warns and gives false
--]]

local function advance(run: Run, command: Command): boolean
	local world: World = run.world
	world.tick = (command.number - TickOffset) % WRAP
	State.copy(Current, Previous)
	Searched = false

	local stepped: boolean, failure: unknown = pcall(Step.advance, Current, command, world)
	if not stepped then
		State.copy(Previous, Current)
		warn(`Predict's step threw on command {command.number}: {failure}`)
	end

	return stepped
end

-- Releases the oldest commands the server ran once no Move repeats them, and any past the held limit
local function release()
	while #Held > HELD_LIMIT or (#Held > MAX_COMMANDS and Sequence.difference(Held[1].command.number, Acked) <= 0) do
		local entry: Entry? = table.remove(Held, 1)
		if entry then
			entry.predicted = false
			table.insert(Spare, entry)
		end
	end
end

--[[
    Makes this tick's command: the game's sample, a trip through the wire
    and back so the step runs the numbers the server will read, the next
    number, its presses against the previous command's levels, and the
    body stepped on it
--]]

local function issue(run: Run)
	local settings: Settings = run.settings
	local entry: Entry = take()
	local command: Command = entry.command

	rest(command)
	settings.sample(command)
	Command.write(command, Scratch, settings.layout, run.limits)

	local failed: number? = Command.read(Scratch, command, settings.layout, run.limits)
	if failed then
		error(`The sampled command's game fields read back failing at field {failed}`)
	end

	Newest = (Newest + 1) % WRAP
	Numbered = true
	command.number = Newest

	local pressed: Pressed = command.pressed
	pressed.jump = command.jump and not Last.jump
	pressed.crouch = command.crouch and not Last.crouch
	pressed.sprint = command.sprint and not Last.sprint
	pressed.aim = command.aim and not Last.aim
	Last.jump = command.jump
	Last.crouch = command.crouch
	Last.sprint = command.sprint
	Last.aim = command.aim

	entry.predicted = advance(run, command)
	if entry.predicted then
		State.copy(Current, entry.state)
	end

	table.insert(Held, entry)
	Fresh += 1
	Issued = true
	release()
end

--[[
    Sends the Move: every command made since the last one and the ones
    before them it repeats, newest first and back only as far as the
    numbers run without a skip, with the acknowledgments and the delay. With
    no command made since the last it carries those alone
--]]

local function sendMove(run: Run)
	local count: number = 0
	if Fresh > 0 then
		local wanted: number = math.min(Fresh + MOVE_REPEATS, MAX_COMMANDS)
		local expected: number = Newest

		for index: number = #Held, 1, -1 do
			local command: Command = Held[index].command
			if count >= wanted or command.number ~= expected then
				break
			end

			count += 1
			Outgoing[count] = command
			expected = (expected - 1) % WRAP
		end
	end

	Fresh = 0

	local settings: Settings = run.settings
	local sequence: number, mask: number = run.acknowledged()
	local delay: number = math.clamp(math.round(settings.delay() * MILLISECONDS), 0, DELAY_LIMIT)
	Move.encode(Outbound, Outgoing, count, sequence, mask, delay, settings.layout, run.limits)
	run.send(Outbound)
end

--[[
    One tick of the client's clock: this tick's command, or none while a
    backward snap holds them, and the Move when a relay tick comes due
--]]

local function tick(run: Run)
	if Hold > 0 then
		Hold -= 1
		State.copy(Current, Previous)
	else
		issue(run)
	end

	RelayDue += run.share
	if RelayDue >= 1 then
		RelayDue -= math.floor(RelayDue)
		sendMove(run)
	end
end

--[[
    Runs the client's clock for a frame: this frame's look read from the
    game, the nudged time added to what is owed, any past the game's time
    debt dropped, a tick for each whole one owed, and the visual error
    offset shrunk at the game's decay. Between two bodies only the command
    numbers run on, a number for each tick owed
--]]

function Predict.frame(dt: number)
	local run: Run = started()
	if not (dt >= 0 and dt < math.huge) then
		error(`Predict.frame takes a frame's seconds, finite and 0 or more, not {dt}`, 2)
	end

	-- Between two bodies the numbers still run with the time, so the next body's commands keep the last one's lead
	if not Body then
		if Numbered then
			Clock = math.min(Clock + dt / run.world.delta, run.settings.ticks.debt)
			while Clock >= 1 do
				Clock -= 1
				Newest = (Newest + 1) % WRAP
			end
		end

		return
	end

	LookYaw, LookPitch, HeadYaw, HeadPitch = run.settings.look()

	Clock = math.min(Clock + dt / run.world.delta * Rate, run.settings.ticks.debt)
	while Clock >= 1 do
		Clock -= 1
		tick(run)
	end

	local share: number = math.min(run.settings.smoothing.decay * dt, 1)
	Correction = vector.create(
		Math.lerp(Correction.x, 0, share),
		Math.lerp(Correction.y, 0, share),
		Math.lerp(Correction.z, 0, share)
	)
end

-- A u16 angle's steps for an angle in radians, which every realm rounds a facing to
local function steps(angle: number): number
	return math.round(angle / TURN * ANGLE_STEPS) % ANGLE_STEPS
end

-- A vector's length in studs, written out as the step writes its own
local function length(value: vector): number
	return math.sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
end

-- Whether two tables of game values hold the same values, nested lists and groups included
local function same(a: State.Values, b: State.Values): boolean
	for key, value in a do
		local other: any = b[key]

		if type(value) == "table" then
			if type(other) ~= "table" or not same(value, other) then
				return false
			end
		elseif value ~= other then
			return false
		end
	end

	for key in b do
		if a[key] == nil then
			return false
		end
	end

	return true
end

-- A state's tolerance in quanta: a rider's, or its mode's
local function toleranceOf(run: Run, state: State): number
	local tolerances: Tolerances = run.settings.tolerances

	if state.platform ~= 0 then
		return tolerances.Rider
	elseif state.mode == "Ground" then
		return tolerances.Ground
	elseif state.mode == "Air" then
		return tolerances.Air
	elseif state.mode == "Swim" then
		return tolerances.Swim
	elseif state.mode == "Ladder" then
		return tolerances.Ladder
	end

	return tolerances.Mantle
end

--[[
    Whether the server's state for a command keeps its prediction: every
    position and velocity component, the apex and the last ground's height
    within the tolerance, and every other field, the game's blocks among
    them, the same
--]]

local function fits(run: Run, server: State, predicted: State, tolerance: number): boolean
	local at: vector, was: vector = server.position, predicted.position
	local velocity: vector, guessed: vector = server.velocity, predicted.velocity
	local limit: number = run.limits.lean

	return math.abs(at.x - was.x) <= tolerance
		and math.abs(at.y - was.y) <= tolerance
		and math.abs(at.z - was.z) <= tolerance
		and math.abs(velocity.x - guessed.x) <= tolerance
		and math.abs(velocity.y - guessed.y) <= tolerance
		and math.abs(velocity.z - guessed.z) <= tolerance
		and math.abs(server.apex - predicted.apex) <= tolerance
		and math.abs(server.groundHeight - predicted.groundHeight) <= tolerance
		and steps(server.facing) == steps(predicted.facing)
		and math.round(server.lean / limit * LEAN_STEPS) == math.round(predicted.lean / limit * LEAN_STEPS)
		and server.mode == predicted.mode
		and server.posture == predicted.posture
		and server.sprint == predicted.sprint
		and server.aim == predicted.aim
		and server.waterLevel == predicted.waterLevel
		and server.jumps == predicted.jumps
		and server.lands == predicted.lands
		and server.heavy == predicted.heavy
		and server.epoch == predicted.epoch
		and server.platform == predicted.platform
		and server.moveMode == predicted.moveMode
		and server.grounded == predicted.grounded
		and server.eyeHeight == predicted.eyeHeight
		and server.groundTicks == predicted.groundTicks
		and server.airTicks == predicted.airTicks
		and server.mantleTicks == predicted.mantleTicks
		and server.mantleRise == predicted.mantleRise
		and server.ladder == predicted.ladder
		and same(server.fields, predicted.fields)
		and same(server.block, predicted.block)
end

-- Whether a flag a large correction names flipped: grounded, posture, mode or the ridden platform
local function flips(server: State, predicted: State): boolean
	return server.grounded ~= predicted.grounded
		or server.posture ~= predicted.posture
		or server.mode ~= predicted.mode
		or server.platform ~= predicted.platform
end

-- Adds a shift's differences to one state: its position, velocity, apex and last ground's height
local function move(state: State, moved: vector, sped: vector, raised: number, lowered: number)
	state.position += moved
	state.velocity += sped
	state.apex += raised
	state.groundHeight += lowered
end

--[[
    Moves the body and every prediction after the server's command by the
    differences the server's state shows inside the tolerance, with no
    replay
--]]

local function shift(server: State, predicted: State)
	local moved: vector = server.position - predicted.position
	local sped: vector = server.velocity - predicted.velocity
	local raised: number = server.apex - predicted.apex
	local lowered: number = server.groundHeight - predicted.groundHeight
	if moved == vector.zero and sped == vector.zero and raised == 0 and lowered == 0 then
		return
	end

	move(Current, moved, sped, raised, lowered)
	move(Previous, moved, sped, raised, lowered)
	Searched = false

	for _, entry: Entry in Held do
		if entry.predicted and Sequence.difference(entry.command.number, server.command) > 0 then
			move(entry.state, moved, sped, raised, lowered)
		end
	end
end

-- The body's place between its last two predicted ticks by the clock's fraction, before the visual error offset
local function place(): vector
	local from: vector, to: vector = Previous.position, Current.position

	return vector.create(Math.lerp(from.x, to.x, Clock), Math.lerp(from.y, to.y, Clock), Math.lerp(from.z, to.z, Clock))
end

--[[
    Resets the body to the server's state and replays every command after
    the server's from it. A step that throws ends the replay, and the body
    snaps to the server's state and gives false
--]]

local function replay(run: Run): boolean
	State.copy(Server, Current)
	State.copy(Server, Previous)
	Searched = false

	local ran: number = Server.command
	for index: number, entry: Entry in Held do
		if Sequence.difference(entry.command.number, ran) <= 0 then
			continue
		end

		entry.predicted = advance(run, entry.command)
		if not entry.predicted then
			State.copy(Server, Current)
			State.copy(Server, Previous)

			for later: number = index + 1, #Held do
				Held[later].predicted = false
			end

			return false
		end

		State.copy(Current, entry.state)
	end

	return true
end

-- Runs where a callback's error was raised, so its warning keeps the callback's stack
local function warnFailure(message: unknown)
	warn(`A correction callback threw, and the other callbacks still ran: {debug.traceback(tostring(message), 2)}`)
end

--[[
    Tells every correction callback of a replay. Each runs under its own
    xpcall, so one that throws is warned with its stack and stops neither
    the others nor the reconciliation
--]]

local function fire(size: number, flagged: boolean)
	-- A copy, so a callback connected mid-fire waits for the next replay and one disconnected mid-fire is skipped
	for _, listener: Listener in table.clone(Listeners) do
		if listener.connected then
			xpcall(listener.callback, warnFailure, size, flagged)
		end
	end
end

--[[
    Starts the body from the first OwnerState: the server's state, the next
    command numbered one past the server's, or past where an earlier body's
    numbers have run on to, and each number read as running on the server
    tick this one names for it. The round trip is unknown, so the clock
    searches for its lead as when an empty queue proves a trip wrong, and
    judges nothing until the server's tick reaches its first command
--]]

local function adopt(run: Run)
	Body = true
	State.copy(Server, Current)
	State.copy(Server, Previous)
	Searched = false

	-- A number an earlier body sent is never sent again, since the server may still hold that body's command for it,
	-- and past the trip and lead of any playable link no earlier command can still be in flight
	local ahead: number = Sequence.difference(Newest, Server.command)
	if not Numbered or ahead <= 0 or ahead > HELD_LIMIT then
		Newest = Server.command
	end

	Acked = Server.command
	TickOffset = Sequence.difference(Server.command, Server.tick)
	LookYaw = Current.facing
	LookPitch = 0

	-- With no round trip known to forget, the search's limit is the queue's reach alone
	Searching = true
	Moved = false
	Landing = false
	Easing = false
	Floor = 0
	Ceiling = math.huge
	Limit = run.settings.ticks.ahead
	Settle = (Newest + 1) % WRAP
end

--[[
    Holds the prediction to the server's state for the command it ran:
    inside the state's tolerance the body shifts, and past it, or with no
    prediction to hold it to, the body replays from the server's state. The
    drawn body carries over in the visual error offset, which snaps past the
    game's snap, and the callbacks hear the size and whether a flag flipped
--]]

local function reconcile(run: Run)
	local predicted: State? = nil
	for _, entry: Entry in Held do
		if entry.predicted and entry.command.number == Server.command then
			predicted = entry.state
		end
	end

	local size: number = 0
	local flagged: boolean = true
	if predicted then
		if fits(run, Server, predicted, toleranceOf(run, Server) * QUANTUM) then
			shift(Server, predicted)

			return
		end

		size = length(Server.position - predicted.position)
		flagged = flips(Server, predicted)
	end

	-- A number the server already ran is late for good, so the next is numbered past it
	if Sequence.difference(Server.command, Newest) > 0 then
		Newest = Server.command
	end

	local teleported: boolean = Server.epoch ~= Current.epoch
	local before: vector = place()
	local clean: boolean = replay(run)
	local jump: vector = before - place()
	Correction += jump

	if not predicted then
		size = length(jump)
	end

	if teleported or not clean or length(Correction) > run.settings.smoothing.snap then
		Correction = vector.zero
	end

	fire(size, flagged)
end

--[[
    One move of the search for a lead an empty queue doesn't show, with the
    round trip known only to lie from Floor to Ceiling, so the lead lies from
    past less the ceiling to past less the floor. One that may be past the
    queue's reach holds back until even the most it can be is the target.
    Otherwise it is at most 0, so the floor rises to past and the clock
    skips forward by the target. A floor past the search's limit starts the
    search again from no bounds, with the limit doubled
--]]

local function search(ticks: Ticks, past: number, target: number)
	local least: number = past - Ceiling
	local most: number = past - Floor

	if least > 0 or most >= ticks.ahead then
		Hold = math.max(math.round(most - target), 0)
	else
		Floor = past

		if Floor > Ceiling then
			Ceiling = math.huge
		end

		if Floor > Limit then
			Floor = 0
			Ceiling = math.huge
			Limit = math.max(Limit, 1) * 2
			Hold = math.max(math.round(past - target), 0)
		else
			Newest = (Newest + math.max(math.round(target), 1)) % WRAP
		end
	end

	Moved = true
	Settle = (Newest + 1) % WRAP
	Rate = 1
end

--[[
    Holds the client's clock at its lead, the commands the server holds
    queued past the tick it runs. A queue its newest commands are feeding,
    between empty and the ahead limit, shows the lead, and with room left
    the round trip in commands too; any other shows it only through that
    trip. A queue left empty past a trip's OwnerStates where the trip puts a
    lead it would show proves the trip wrong, and the clock searches. A
    search that moved the clock ends with the lead lifted to the target and
    eased down from there to the band's bottom. Past the resync from the
    band's middle it snaps, and judges nothing more until the server's tick
    reaches the first command after the snap
--]]

local function clock(run: Run)
	local ticks: Ticks = run.settings.ticks
	local depth: number = Server.depth
	local top: number = (Server.tick + depth) % WRAP
	local furthest: number? = Top
	local fed: boolean = furthest == nil or Sequence.difference(top, furthest) > 0
	local queued: boolean = fed and depth > 0 and depth < ticks.ahead

	if fed then
		Top = top
	end

	if queued then
		TickOffset = Sequence.difference(Server.command, Server.tick)
	end

	local base: number = (Server.tick + TickOffset) % WRAP -- The number of the command the server's tick runs
	local past: number = Sequence.difference(Newest, base)
	local trip: number? = Trip
	local lead: number = depth

	-- Commands queued arrived before their ticks, so the round trip is at most past less them
	if Searching and depth > 0 then
		Ceiling = math.min(Ceiling, past - depth)

		-- A floor above it was raised before the trip shrank, and holds no more
		if Floor > Ceiling then
			Floor = 0
		end
	end

	-- A full queue may have dropped newer commands, and an OwnerState read with no command made since the last, as
	-- after a frozen frame, misses commands its round trip counts, so neither shows the trip
	if queued and depth < ticks.ahead - 1 and Issued then
		Trip = past - depth

		-- A search's last skip lands anywhere from the band's bottom up, where a drift under a tick empties the queue
		if Searching and Moved then
			Landing = true
			Easing = true
		end

		Searching = false
	end

	Issued = false

	if queued then
		lead = depth
	elseif Searching then
		lead = past - Floor
	elseif trip then
		lead = past - trip
	end

	local settle: number? = Settle
	if settle then
		if Sequence.difference(base, settle) < 0 then
			Rate = 1

			return
		end

		Settle = nil
	end

	-- An empty queue where the trip puts a lead it would show doubts it, until commands in flight would have landed
	local doubted: boolean = depth == 0 and trip ~= nil and lead > 0 and lead < ticks.ahead
	if doubted then
		Doubt += 1
	else
		Doubt = 0
	end

	local landing: boolean = Landing
	Landing = false

	-- Eased down from above, the clock stops as the queue first reads the band's bottom, most of a tick above it
	if Easing and not landing and lead <= ticks.leadMin then
		Easing = false
	end

	local target: number = (ticks.leadMin + ticks.leadMax) / 2
	if depth == 0 and Searching then
		search(ticks, past, target)
	elseif doubted and trip and Doubt > trip then
		Trip = nil
		Searching = true
		Moved = false
		Easing = false
		Floor = 0
		Ceiling = math.huge
		Limit = math.max(trip, 0) + ticks.ahead
		search(ticks, past, target)
	elseif lead < target - ticks.resync or (landing and math.round(target - lead) >= 1) then
		Newest = (Newest + math.round(target - lead)) % WRAP
		Settle = (Newest + 1) % WRAP
		Rate = 1
	elseif lead > target + ticks.resync then
		Hold = math.round(lead - target)
		Settle = (Newest + 1) % WRAP
		Rate = 1
	elseif lead < ticks.leadMin then
		Rate = 1 + ticks.nudge
	elseif lead > ticks.leadMax or (Easing and lead > ticks.leadMin) then
		Rate = 1 - ticks.nudge
	else
		Rate = 1
	end
end

--[[
    Reads an OwnerState, the server's state after the last command it ran.
    The first starts the body, and each newer one is held against the
    prediction, releases the commands it acknowledges and holds the clock
    at its lead. One no newer than the last read changes nothing
--]]

function Predict.receive(data: buffer)
	local run: Run = started()
	if typeof(data) ~= "buffer" then
		error(`Predict.receive takes an OwnerState's buffer, not a {typeof(data)}`, 2)
	end

	OwnerState.read(data, 0, buffer.len(data), Server, run.settings.layout, run.limits)

	if not Body then
		adopt(run)
		LastTick = Server.tick

		return
	elseif Sequence.difference(Server.tick, LastTick) <= 0 then
		return
	else
		reconcile(run)
	end

	LastTick = Server.tick
	if Sequence.difference(Server.command, Acked) > 0 then
		Acked = Server.command
	end

	release()
	clock(run)
end

--[[
    The body as drawn: the newest predicted tick placed between it and the
    tick before by the clock's fraction, the visual error offset on top, its
    facing between the two on the shortest arc, and its eased eye and lean
    between them as well
--]]

local function draw(): State
	local from: number = steps(Previous.facing)
	local turned: number = Math.lerp(from, from + Sequence.difference(steps(Current.facing), from), Clock)

	State.copy(Current, Drawn)
	Drawn.position = place() + Correction
	Drawn.facing = turned * TURN / ANGLE_STEPS
	Drawn.eyeHeight = Math.lerp(Previous.eyeHeight, Current.eyeHeight, Clock)
	Drawn.lean = Math.lerp(Previous.lean, Current.lean, Clock)

	return Drawn
end

--[[
    The drawn body's cleared eye and the look it publishes: the base look
    the game gave this frame, turned by its head offset, so a turn never
    waits for a tick. It errors before the first OwnerState starts a body
--]]

function Predict.eye(): (vector, vector)
	local run: Run = started()
	if not Body then
		error("Predict.eye has no body until the first OwnerState starts one", 2)
	end

	local cone: number = run.world.settings.headCone

	return Eye.clear(draw(), run.world), Public.look(LookYaw, LookPitch, HeadYaw, HeadPitch, cone)
end

--[[
    The body as drawn this frame, the same table until the next call, or
    nil before the first OwnerState starts one
--]]

function Predict.state(): State?
	started()
	if not Body then
		return nil
	end

	return draw()
end

--[[
    Where the feet would end if jump were pressed at the newest predicted
    tick: the search a press runs, from that tick's state in prediction's
    own world, at most once a predicted tick. Nil before the first
    OwnerState, where no press would start a mantle, and when the search
    throws, which it warns of
--]]

function Predict.mantle(): vector?
	local run: Run? = Running
	if not run or not Body then
		return nil
	end

	if not Searched then
		Searched = true

		local ran: boolean, answer: unknown = pcall(Mantle.ending, Current, run.world)
		if ran then
			Ledge = answer :: vector?
		else
			Ledge = nil
			warn(`Predict's mantle search threw on command {Current.command}: {answer}`)
		end
	end

	return Ledge
end

--[[
    Ends the body, as when its character dies or the game replaces it, and
    puts prediction back as it was before the first OwnerState: no command
    is kept, no Move goes, and the next OwnerState starts a new body as the
    first did. The command numbers alone run on with the time, so the next
    body sends none again and keeps the lead, and the correction callbacks
    stay connected
--]]

function Predict.reset()
	started()

	for index: number = #Held, 1, -1 do
		local entry: Entry = Held[index]
		entry.predicted = false
		Held[index] = nil
		table.insert(Spare, entry)
	end

	Body = false
	Acked = 0
	LastTick = 0
	TickOffset = 0
	Trip = nil
	Top = nil
	Issued = false
	Doubt = 0
	Searching = false
	Moved = false
	Landing = false
	Easing = false
	Floor = 0
	Ceiling = math.huge
	Limit = 0
	Settle = nil
	Hold = 0
	Rate = 1
	RelayDue = 0
	Fresh = 0
	Correction = vector.zero
	Last.jump = false
	Last.crouch = false
	Last.sprint = false
	Last.aim = false
end

--[[
    Calls back on every replay with the correction's size in studs and
    whether a flag flipped. Returns the closure that disconnects it
--]]

function Predict.onCorrected(callback: Callback): () -> ()
	if type(callback) ~= "function" then
		error(`Predict.onCorrected takes a function, not a {typeof(callback)}`, 2)
	end

	local listener: Listener = { callback = callback, connected = true }
	table.insert(Listeners, listener)

	return function ()
		listener.connected = false

		local index: number? = table.find(Listeners, listener)
		if index then
			table.remove(Listeners, index)
		end
	end
end

return Predict
