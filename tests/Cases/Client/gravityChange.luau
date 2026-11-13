--[[
    A gravity change reaches the owner's prediction through the client
    handle and applies from its tick: a body falling over no parts beside a
    server twin changed at tick T takes exactly one correction when the
    change arrives after the client predicted T, and none when it arrives
    before
--]]

--!strict
local Environment = require("../../Environment")
local Handle = require("../../Fixtures/Client/Handle")

local COLLISION: string = "tests/Fixtures/Step/Collision.luau"

local SLOT: number = 5
local GENERATION: number = 1
local WIRE: number = 2 ^ 16
local SERVER_TICK: number = 1000 -- The handshake's tick, which command 0 runs on
local HEIGHT: number = 500 -- Studs up the body starts its fall from, inside the 1,024-stud height bound
local CHANGED: number = 30 -- Studs/s², the gravity the change sets
local CHANGE_AT: number = 10 -- The command whose tick the change applies from
local SPAWN_DEPTH: number = 1
local LEAD: number = 2 -- Commands the client runs ahead of each state it is handed, inside the clock's band
local COMMANDS: number = 24
local BUFFER_BYTES: number = 128 -- Past the largest OwnerState

--[[
    One fall from rest at HEIGHT, the server's twin stepping the rest
    commands the client samples under its world's gravity change. The
    change reaches the client before it predicts CHANGE_AT when early, and
    after it predicted the command past it when not. Gives why it went
    wrong, or nil
--]]

local function fall(early: boolean): string?
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local need: any = rig.globals.require
	local tread: any = rig.tread

	local Command: any = need(tread.Codec.Command)
	local Config: any = need(tread.Config)
	local Fields: any = need(tread.Codec.Fields)
	local OwnerState: any = need(tread.Codec.OwnerState)
	local Sequence: any = need(tread.Codec.Sequence)
	local Step: any = need(tread.Step)
	local World: any = need(tread.Step.World)
	local State: any = rig.State

	local shared: any = rig.shared
	local layout: any = Fields.compile(shared.fields)
	local limits: any = { lean = shared.step.lean, headCone = shared.step.headCone }
	local changeTick: number = SERVER_TICK + CHANGE_AT

	-- Both worlds cast over no parts with the fixture's pure casts; the twin's clock is the handshake's tick
	local Casts: any = Environment.load(COLLISION)
	handle._world.collision = Casts({})

	local twinWorld: any = World.new(shared.step, shared.rates.simulation, Casts({}), shared.water, shared.rules, true)
	twinWorld.clock = SERVER_TICK
	World.setGravity(twinWorld, CHANGED, changeTick)

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

	-- The body at rest in the air, and the twin started from exactly what the client reads
	local spawn: any = State.new()
	spawn.position = vector.create(0, HEIGHT, 0)
	spawn.mode = "Air"
	spawn.grounded = false
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

	local sent: boolean = false
	for command: number = LEAD + 1, COMMANDS do
		if early and command == CHANGE_AT then
			rig.send("Gravity", CHANGED, changeTick)
			sent = true
		end

		rig.frames(1)

		if not early and command == CHANGE_AT + 1 then
			rig.send("Gravity", CHANGED, changeTick)
			sent = true
		end

		local ran: number = command - LEAD
		through(ran)
		rig.send("Owner", encode(twin, LEAD))

		if twin.mode ~= "Air" then
			return `The twin left the air on command {ran}, before the fall was done`
		end

		local wanted: number = 0
		if not early and ran >= CHANGE_AT then
			wanted = 1
		end

		if corrections ~= wanted then
			return `The server's state for command {ran} left {corrections} corrections, where {wanted} were expected`
		end
	end

	if not sent then
		return "The case never sent the change"
	end

	return nil
end

return function (): (boolean, string | nil)
	-- 1) The change arrives before the client predicts its tick
	local before: string? = fall(true)
	if before then
		return false, `With the change heard before its tick was predicted: {before}`
	end

	-- 2) The change arrives after the client predicted past its tick
	local after: string? = fall(false)
	if after then
		return false, `With the change heard after its tick was predicted: {after}`
	end

	return true, nil
end
