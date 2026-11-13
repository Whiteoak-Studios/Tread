--[[
    The prediction cases' rig: a fresh Predict on the step's fixture floor
    with Frontier Zero's values, a stub send recording every Move, and the
    server's twin, which steps the commands sent to write fixed OwnerStates
--]]

--!strict
local Environment = require("../../Environment")

local PREDICT: string = "src/Client/Predict.luau"
local COMMAND: string = "src/Codec/Command.luau"
local FIELDS: string = "src/Codec/Fields.luau"
local OWNER_STATE: string = "src/Codec/OwnerState.luau"
local SEQUENCE: string = "src/Codec/Sequence.luau"
local STATE: string = "src/Step/State.luau"
local STEP: string = "src/Step/init.luau"
local WORLD: string = "src/Step/World.luau"
local PLATFORMS: string = "src/Step/Platforms.luau"
local MATH: string = "src/Step/Math.luau"
local CONSTANTS: string = "src/Constants.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local COLLISION: string = "tests/Fixtures/Step/Collision.luau"
local GEOMETRY: string = "tests/Fixtures/Step/Geometry.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"

local SIMULATION_RATE: number = 20 -- Frontier Zero's rates.simulation
local WRAP: number = 2 ^ 16
local SPAWN_COMMAND: number = 0 -- The spawn OwnerState's command and tick, unless a case gives its own
local SPAWN_TICK: number = 100
local SPAWN_DEPTH: number = 1 -- Its queue, inside the band, so the clock starts unnudged
local SPAWN_X: number = -20 -- On the fixture floor, clear of every other part for 50 studs along -Z
local SPAWN_Z: number = 25
local DELAY: number = 0.15 -- The stub's interpolation delay, in seconds
local SEQUENCE_ACKED: number = 7 -- The stub's newest relay sequence received and its mask
local MASK: number = 3
local BUFFER_BYTES: number = 128 -- Past the largest OwnerState

export type Recorded = {
	command: number,
	acknowledged: number,
	received: number,
	delay: number,
	numbers: { number }, -- Each command's number, newest first
}

export type Options = {
	relay: number?, -- rates.relay, Frontier Zero's 20 unless given
	snap: number?, -- smoothing.snap, its 2 unless given
	ticks: { [string]: number }?, -- Ticks to set over its own
	tolerances: { [string]: number }?,
	platforms: { { [string]: any } }?, -- Platforms registered alike on the client's world and the twin's
	step: { [string]: any }?, -- The step settings both worlds take, Frontier Zero's unless given
	parts: { any }?, -- The fixture parts both worlds cast against, the step's fixture geometry unless given
	spawn: vector?, -- Where the spawn OwnerState stands the body, on that geometry's floor unless given
}

local Harness = {}

-- A wire command copied, since the Move's sender reuses its wires
local function copyWire(wire: any): any
	local fields: buffer = buffer.create(buffer.len(wire.fields))
	buffer.copy(fields, 0, wire.fields, 0, buffer.len(wire.fields))

	return {
		moveX = wire.moveX,
		moveZ = wire.moveZ,
		buttons = wire.buttons,
		yaw = wire.yaw,
		pitch = wire.pitch,
		lean = wire.lean,
		headYaw = wire.headYaw,
		headPitch = wire.headPitch,
		fields = fields,
	}
end

local function sameWire(a: any, b: any): boolean
	return a.moveX == b.moveX
		and a.moveZ == b.moveZ
		and a.buttons == b.buttons
		and a.yaw == b.yaw
		and a.pitch == b.pitch
		and a.lean == b.lean
		and a.headYaw == b.headYaw
		and a.headPitch == b.headPitch
		and buffer.tostring(a.fields) == buffer.tostring(b.fields)
end

-- A walk ahead with every button up, and the game's declared fields at rest
local function walk(command: any, _: number)
	command.forward = 1
	command.fields.slot = 0
	command.fields.shots = {}
end

--[[
    A started Predict in a fresh environment, with its world, settings and
    stub send, and the twin that plays the server
--]]

function Harness.new(options: Options?): { [string]: any }
	local given: Options = options or {}
	local Command: any = Environment.load(COMMAND)
	local Fields: any = Environment.load(FIELDS)
	local OwnerState: any = Environment.load(OWNER_STATE)
	local Sequence: any = Environment.load(SEQUENCE)
	local State: any = Environment.load(STATE)
	local Step: any = Environment.load(STEP)
	local World: any = Environment.load(WORLD)
	local Scene: any = Environment.load(SCENE)
	local Geometry: any = Environment.load(GEOMETRY)
	local Example: any = Environment.load(EXAMPLE)
	local Predict: any = Environment.load(PREDICT)

	local shared: any = Example.shared()
	local client: any = Example.client()
	local layout: any = Fields.compile(shared.fields)
	local limits: any = { lean = Scene.settings.lean, headCone = Scene.settings.headCone }
	local collision: any = Environment.load(COLLISION)(given.parts or Geometry.parts)

	local rig: { [string]: any } = {
		Predict = Predict,
		State = State,
		Step = Step,
		Math = Environment.load(MATH),
		Constants = Environment.load(CONSTANTS),
		moves = {} :: { Recorded },
		wires = {} :: { [number]: any }, -- The first copy of each command the stub was sent
		samples = 0,
		tampered = false, -- Whether a later copy of a command differed from its first
		corrections = {} :: { { size: number, flagged: boolean } },
		fail = false, -- Makes the client's rules function throw, as a broken game hook does
		input = walk,
		view = { yaw = 0, pitch = 0, headYaw = 0, headPitch = 0 }, -- The look the game gives each frame
		looks = 0, -- How many times Predict read it
	}

	-- The client's rules function refuses nothing, and throws while the case says so
	local function clientRules(_: any, _: any): number
		if rig.fail then
			error("The game's rules function threw")
		end

		return math.huge
	end

	local function serverRules(_: any, _: any): number
		return math.huge
	end

	local step: any = given.step or Scene.settings
	local world: any = World.new(step, SIMULATION_RATE, collision, nil, clientRules, false)
	local twinWorld: any = World.new(step, SIMULATION_RATE, collision, nil, serverRules, true)
	rig.world = world
	rig.twinWorld = twinWorld
	rig.delta = world.delta

	local Platforms: any = Environment.load(PLATFORMS)
	rig.Platforms = Platforms

	for _, platform: { [string]: any } in given.platforms or {} do
		Platforms.add(world, platform)
		Platforms.add(twinWorld, platform)
	end

	local ticks: any = shared.ticks
	for key: string, value: number in given.ticks or {} do
		ticks[key] = value
	end

	local tolerances: any = shared.tolerances
	for key: string, value: number in given.tolerances or {} do
		tolerances[key] = value
	end

	local smoothing: any = client.smoothing
	if given.snap then
		smoothing.snap = given.snap
	end

	local settings: any = {
		rates = { simulation = SIMULATION_RATE, relay = given.relay or SIMULATION_RATE },
		ticks = ticks,
		tolerances = tolerances,
		smoothing = smoothing,
		layout = layout,

		sample = function (command: any)
			rig.samples += 1
			rig.input(command, rig.samples)
		end,

		look = function (): (number, number, number, number)
			local view: any = rig.view
			rig.looks += 1

			return view.yaw, view.pitch, view.headYaw, view.headPitch
		end,

		delay = function (): number
			return DELAY
		end,
	}

	rig.settings = settings

	-- Records each Move as Volt would send it, keeping the first copy of each command, which the server runs
	local function send(move: any)
		local numbers: { number } = {}

		for index: number, wire: any in move.commands do
			local number: number = (move.command - (index - 1)) % WRAP
			table.insert(numbers, number)

			local first: any = rig.wires[number]
			if first == nil then
				rig.wires[number] = copyWire(wire)
			elseif not sameWire(first, wire) then
				rig.tampered = true
			end
		end

		table.insert(rig.moves, {
			command = move.command,
			acknowledged = move.acknowledged,
			received = move.received,
			delay = move.delay,
			numbers = numbers,
		})
	end

	local function acknowledged(): (number, number)
		return SEQUENCE_ACKED, MASK
	end

	Predict.start(settings, world, send, acknowledged)
	Predict.onCorrected(function (size: number, flagged: boolean)
		table.insert(rig.corrections, { size = size, flagged = flagged })
	end)

	local scratch: buffer = buffer.create(BUFFER_BYTES)
	local offset: number = 0 -- A command's number less the server tick it runs on

	-- A copy of a state, its game blocks its own
	function rig.copy(state: any): any
		local made: any = State.new()
		State.copy(state, made)

		return made
	end

	-- An OwnerState of a state, its buffer exactly as long as Volt hands it over
	function rig.owner(state: any, depth: number?): buffer
		state.depth = depth or 0
		local length: number = OwnerState.write(state, scratch, 0, layout, limits)
		local data: buffer = buffer.create(length)
		buffer.copy(data, 0, scratch, 0, length)

		return data
	end

	-- Steps a state on the commands from one number through another, read from their wires as the server reads them
	function rig.step(state: any, from: number, to: number)
		local order: any = Command.new()
		local number: number = from

		while Sequence.difference(to, number) >= 0 do
			local wire: any = rig.wires[number]
			if wire == nil then
				error(`The twin has no command {number} to step`)
			end

			Command.read(wire, order, layout, limits)
			order.number = number

			-- Presses against the previous command's levels, all up when it was never sent
			local before: any = rig.wires[(number - 1) % WRAP]
			local buttons: number = before and before.buttons or 0
			order.pressed.jump = order.jump and bit32.extract(buttons, 0) == 0
			order.pressed.crouch = order.crouch and bit32.extract(buttons, 1) == 0
			order.pressed.sprint = order.sprint and bit32.extract(buttons, 2) == 0
			order.pressed.aim = order.aim and bit32.extract(buttons, 3) == 0

			twinWorld.tick = (number - offset) % WRAP
			Step.advance(state, order, twinWorld)
			number = (number + 1) % WRAP
		end
	end

	-- The server's twin, from the spawn state, and the next command it steps
	local twin: any = State.new()
	local twinNext: number = SPAWN_COMMAND

	-- Hands Predict the spawn OwnerState, and starts the twin from exactly what it read
	function rig.spawn(command: number?, tick: number?, depth: number?)
		local spawned: any = Scene.state(given.spawn or vector.create(SPAWN_X, Geometry.floor, SPAWN_Z), true)
		spawned.command = command or SPAWN_COMMAND
		spawned.tick = tick or SPAWN_TICK
		spawned.fields = { beingRevived = false }
		spawned.block = { sinceJump = 0, sinceShot = 15 }

		local data: buffer = rig.owner(spawned, depth or SPAWN_DEPTH)
		OwnerState.read(data, 0, buffer.len(data), twin, layout, limits)
		offset = Sequence.difference(twin.command, twin.tick)
		twinNext = (twin.command + 1) % WRAP

		Predict.receive(data)
	end

	-- The twin's state after the server ran every command through a number, as a copy
	function rig.twin(through: number): any
		if Sequence.difference(through, twinNext) >= 0 then
			rig.step(twin, twinNext, through)
			twinNext = (through + 1) % WRAP
		end

		return rig.copy(twin)
	end

	-- Runs frames of a tick each, or of the seconds given
	function rig.frames(count: number, dt: number?)
		for _ = 1, count do
			Predict.frame(dt or world.delta)
		end
	end

	return rig
end

return Harness
