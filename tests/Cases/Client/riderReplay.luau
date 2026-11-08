--[[
    The owner's prediction rides a lift through the client handle as the
    server does across the u16 wrap, each step's tick unwrapped against the
    clock the handshake started: the server's own states along the ride
    raise no correction, and one off the prediction mid-ride replays once
    through the moving lift onto the server's path, raising no other
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")
local Handle = require("../../Fixtures/Client/Handle")

local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"
local COLLISION: string = "tests/Fixtures/Step/Collision.luau"

local SLOT: number = 5
local GENERATION: number = 1
local LIFT: number = 9
local WIRE: number = 2 ^ 16
local SERVER_TICK: number = 3 * WIRE - 6 -- The handshake's tick, six before a u16 wrap, which the ride crosses
local RISES_AT: number = 3 * WIRE -- The lift rises from the wrap's tick on, unwrapped as the server counts it
local RISE: number = 0.25 -- Studs a tick
local FLOOR: number = 50 -- The lift's top before it rises
local SPAWN_DEPTH: number = 1
local LEAD: number = 2 -- Commands the client runs ahead of each state it is handed, inside the clock's band
local COMMANDS: number = 30
local OFF_AT: number = 12 -- The command the off state is for, the lift rising with the body on it
local OFF: vector = vector.create(0.25, 0, 0.5) -- How far the server's state sits from the prediction, still on the lift
local BUFFER_BYTES: number = 128 -- Past the largest OwnerState

--[[
    One ride from the spawn on the lift, the server's twin stepping the
    rest commands the client samples. With offAt, the server's state for
    that command sits off the prediction, and the ride goes on from it.
    Gives why it went wrong, or nil
--]]

local function ride(offAt: number?): string?
	local Riders: any = Environment.load(RIDERS)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local need: any = rig.globals.require
	local tread: any = rig.tread

	local Command: any = need(tread.Codec.Command)
	local Config: any = need(tread.Config)
	local Fields: any = need(tread.Codec.Fields)
	local Math: any = need(tread.Step.Math)
	local OwnerState: any = need(tread.Codec.OwnerState)
	local Platforms: any = need(tread.Step.Platforms)
	local Sequence: any = need(tread.Codec.Sequence)
	local Step: any = need(tread.Step)
	local World: any = need(tread.Step.World)
	local State: any = rig.State

	local shared: any = rig.shared
	local layout: any = Fields.compile(shared.fields)
	local limits: any = { lean = shared.step.lean, headCone = shared.step.headCone }
	local lift: any = Riders.lift(LIFT, roblox.Vector3.new(0, FLOOR, 0), RISES_AT, RISE)

	-- Lune has no engine overlap for the exact depenetration, so both worlds cast over no parts with the fixture's
	-- pure casts, set before the lift wraps them; the twin's clock is the handshake's tick
	local Casts: any = Environment.load(COLLISION)
	handle._world.collision = Casts({})

	local twinWorld: any = World.new(shared.step, shared.rates.simulation, Casts({}), shared.water, shared.rules, true)
	twinWorld.clock = SERVER_TICK
	Platforms.add(twinWorld, lift)
	handle:addPlatform(lift)

	local corrections: number = 0
	handle:onCorrected(function (_: number, _: boolean)
		corrections += 1
	end)

	rig.send("Shared", Config.hash(shared), SERVER_TICK)
	rig.own(SLOT, GENERATION)

	-- An OwnerState of a copy of a state, as Volt hands it over
	local scratch: buffer = buffer.create(BUFFER_BYTES)
	local function encode(state: any, depth: number): buffer
		local copy: any = State.new()
		State.copy(state, copy)
		copy.depth = depth

		local length: number = OwnerState.write(copy, scratch, 0, layout, limits)
		local data: buffer = buffer.create(length)
		buffer.copy(data, 0, scratch, 0, length)

		return data
	end

	-- The spawn, standing a skin over the lift, and the twin started from exactly what the client reads
	local spawn: any = State.new()
	spawn.position = vector.create(0, Math.quantize(FLOOR + rig.Constants.SKIN), 0)
	spawn.mode = "Ground"
	spawn.grounded = true
	spawn.tick = SERVER_TICK % WIRE
	spawn.fields = { beingRevived = false }
	spawn.block = { sinceJump = 0, sinceShot = 15 }

	local twin: any = State.new()
	local data: buffer = encode(spawn, SPAWN_DEPTH)
	OwnerState.read(data, 0, buffer.len(data), twin, layout, limits)
	rig.send("Owner", data)

	-- The command every sample makes, all at rest, through the wire as the server reads it
	local rest: any = Command.new()
	rest.fields = { slot = 0, shots = {} }
	local wire: any = Command.wire()
	Command.write(rest, wire, layout, limits)

	local order: any = Command.new()
	local offset: number = Sequence.difference(twin.command, twin.tick)
	local stepped: number = twin.command

	-- Steps the twin through a command, each on the tick its number runs on
	local function through(number: number)
		while Sequence.difference(number, stepped) > 0 do
			stepped = (stepped + 1) % WIRE
			Command.read(wire, order, layout, limits)
			order.number = stepped

			twinWorld.tick = (stepped - offset) % WIRE
			Step.advance(twin, order, twinWorld)
		end
	end

	rig.frames(LEAD)

	local risen: boolean = false
	local crossed: boolean = false
	for command: number = LEAD + 1, COMMANDS do
		rig.frames(1)

		local ran: number = command - LEAD
		through(ran)
		if ran == offAt then
			twin.position += OFF
		end

		rig.send("Owner", encode(twin, LEAD))

		risen = risen or (twin.platform == LIFT and twin.position.y > FLOOR + RISE)
		crossed = crossed or twin.tick < spawn.tick

		local wanted: number = 0
		if offAt ~= nil and ran >= offAt then
			wanted = 1
		end

		if corrections ~= wanted then
			return `The server's state for command {ran} left {corrections} corrections, where {wanted} were expected`
		end
	end

	if not risen or not crossed then
		return `The ride rose with the lift {risen} and crossed the u16 wrap {crossed}, where it should do both`
	end

	-- The client's own body rode up with it
	local drawn: any = handle:getState()
	if drawn == nil or drawn.root.Y <= FLOOR + RISE or drawn.platform ~= LIFT then
		return "The owner's drawn body didn't ride the lift up"
	end

	return nil
end

return function (): (boolean, string | nil)
	-- 1) The server's own states along the whole ride
	local straight: string? = ride(nil)
	if straight then
		return false, `On the server's own ride: {straight}`
	end

	-- 2) One state off the prediction mid-ride
	local replayed: string? = ride(OFF_AT)
	if replayed then
		return false, `On the ride with a state off it: {replayed}`
	end

	return true, nil
end
