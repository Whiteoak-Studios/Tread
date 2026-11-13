--[[
    The clock cases' link: the real Predict and the real intake in one game,
    joined by a network whose one-way delays and Heartbeats a case sets, the
    server's tick run on its own accumulator, and every report counted
--]]

--!strict
local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local BOT: string = "Bot" -- The connection's key's Name
local BOT_RTT: number = 0.1 -- Seconds the bot connection reports, which nothing here reads
local WRAP: number = 2 ^ 16 -- A command number and a wire tick are u16
local SPAWN_X: number = -20 -- On the fixture floor, with 50 studs clear along -Z
local SPAWN_Z: number = 25
local WALK_TICKS: number = 40 -- Ticks each way the input walks, forward then back, so the body stays on the floor
local FRAME: number = 1 / 60 -- Seconds between each side's frames, unless a case sets its own
local ONE_WAY: number = 0.05 -- Seconds each way a packet takes, unless a case sets its own
local BUFFER_BYTES: number = 128 -- Past the largest OwnerState
local TOLERANCE: number = 1e-9 -- Seconds two events count as at once

-- A packet in flight, which arrives at its time and no sooner than the one sent before it
type Packet = {
	arrival: number,
	command: number,
	acknowledged: number,
	received: number,
	delay: number,
	wires: { any },
	data: buffer?,
}

-- What the rig counts, all of it since its window last opened
export type Window = {
	seconds: number,
	ticks: number, -- Server ticks run
	dropped: number, -- Ticks the server's Heartbeat dropped past its catch-up
	standIns: number, -- Ticks the body stepped a stand-in
	real: number, -- Ticks the body stepped a real command
	samples: number, -- Commands the client made
	moves: number, -- Moves the client sent
	numbers: { number }, -- The newest command number of each Move that carried any, in sending order
	corrections: number, -- Replays the client raised onCorrected for
	reports: { [string]: number }, -- Reports fired, by kind
	furthest: number, -- The furthest ahead an ahead report measured, 0 for none
	depths: { [number]: number }, -- OwnerStates sent, by their queue depth
	leads: { number }, -- Each decoded Move's newest command less the newest tick stepped, in arrival order
}

local Link = {}

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

local function newWindow(): Window
	return {
		seconds = 0,
		ticks = 0,
		dropped = 0,
		standIns = 0,
		real = 0,
		samples = 0,
		moves = 0,
		numbers = {},
		corrections = 0,
		reports = {},
		furthest = 0,
		depths = {},
		leads = {},
	}
end

--[[
    A started link: the server's body on the fixture floor ticking from
    tick 1, the client waiting for its first OwnerState, each way 50 ms and
    each side's frames at 60 a second until the case changes them
--]]

function Link.new(): { [string]: any }
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local fixtures: any = globals.game:GetService("ServerScriptService").Fixtures
	local load: (any) -> any = globals.require

	local Commands: any = load(tread.Server.Commands)
	local Connections: any = load(tread.Server.Connections)
	local Fields: any = load(tread.Codec.Fields)
	local OwnerState: any = load(tread.Codec.OwnerState)
	local Predict: any = load(tread.Client.Predict)
	local Reports: any = load(tread.Server.Reports)
	local Sequence: any = load(tread.Codec.Sequence)
	local Step: any = load(tread.Step)
	local World: any = load(tread.Step.World)
	local Scene: any = load(fixtures.Step.Scene)
	local Geometry: any = load(fixtures.Step.Geometry)
	local Example: any = load(fixtures.Config.Example)

	local shared: any = Example.shared()
	local client: any = Example.client()
	local server: any = Example.server()
	local layout: any = Fields.compile(shared.fields)
	local limits: any = { lean = shared.step.lean, headCone = shared.step.headCone }
	local collision: any = load(fixtures.Step.Collision)(Geometry.parts)
	local rate: number = shared.rates.simulation

	if shared.rates.relay ~= rate then
		error("The link sends an OwnerState every tick, so it takes a relay rate equal to the simulation rate")
	end

	local function rules(_: any, _: any): number
		return math.huge
	end

	local clientWorld: any = World.new(Scene.settings, rate, collision, nil, rules, false)
	local serverWorld: any = World.new(Scene.settings, rate, collision, nil, rules, true)

	local rig: { [string]: any } = {
		Predict = Predict,
		Sequence = Sequence,
		shared = shared,
		up = ONE_WAY, -- Seconds a Move takes to reach the server
		down = ONE_WAY, -- Seconds an OwnerState takes to reach the client
		serverFrame = FRAME, -- Seconds between the server's Heartbeats
		clientFrame = FRAME, -- Seconds between the client's frames
		catchUp = server.catchUp,
		now = 0,
		tick = 0, -- The newest tick the server ran, unwrapped
		newest = nil :: number?, -- The newest command number the client sent
		window = newWindow(),
	}

	-- The client walks forward and back, so a body the server steps on its commands moves and comes back
	local samples: number = 0
	local settings: any = {
		rates = shared.rates,
		ticks = shared.ticks,
		tolerances = shared.tolerances,
		smoothing = client.smoothing,
		layout = layout,

		sample = function (command: any)
			samples += 1
			rig.window.samples += 1
			command.forward = (samples // WALK_TICKS) % 2 == 0 and 1 or -1
			command.fields.slot = 0
			command.fields.shots = {}
		end,

		look = function (): (number, number, number, number)
			return 0, 0, 0, 0
		end,

		delay = function (): number
			return 0
		end,
	}

	local toServer: { Packet } = {}
	local toClient: { Packet } = {}
	local inbound: { Packet } = {}
	local lastUp: number = 0
	local lastDown: number = 0

	-- Puts each Move in flight, its wires copied, arriving no sooner than the Move before it
	local function send(move: any)
		local wires: { any } = {}
		for _, wire: any in move.commands do
			table.insert(wires, copyWire(wire))
		end

		lastUp = math.max(rig.now + rig.up, lastUp)
		table.insert(toServer, {
			arrival = lastUp,
			command = move.command,
			acknowledged = move.acknowledged,
			received = move.received,
			delay = move.delay,
			wires = wires,
		})

		rig.window.moves += 1
		if #wires > 0 then
			rig.newest = move.command
			table.insert(rig.window.numbers, move.command)
		end
	end

	local function acknowledged(): (number, number)
		return 0, 0
	end

	Predict.start(settings, clientWorld, send, acknowledged)
	Predict.onCorrected(function (_: number, _: boolean)
		rig.window.corrections += 1
	end)

	Reports.connect(function (_: any, kind: string, measurement: number | string)
		local reports: { [string]: number } = rig.window.reports
		reports[kind] = (reports[kind] or 0) + 1

		if kind == "ahead" and type(measurement) == "number" then
			rig.window.furthest = math.max(rig.window.furthest, measurement)
		end
	end)

	Commands.start(shared, layout)
	Connections.start(server.rewind.rttSmoothing, { rtt = BOT_RTT })

	local connection: any = Connections.add({ Name = BOT })
	local body: any = Scene.state(vector.create(SPAWN_X, Geometry.floor, SPAWN_Z), true)
	body.fields = { beingRevived = false }
	body.block = { sinceJump = 0, sinceShot = 15 }
	rig.body = body

	local scratch: buffer = buffer.create(BUFFER_BYTES)
	local pending: number = 0 -- Ticks the server's accumulator owes
	local lastServer: number = 0
	local lastClient: number = 0
	local nextServer: number = rig.serverFrame
	local nextClient: number = rig.clientFrame

	-- One server tick: the Moves that arrived decoded, the body stepped, and its OwnerState put in flight
	local function serverTick()
		for _, packet: Packet in inbound do
			-- A Move with no command carries no number to measure
			if #packet.wires > 0 then
				table.insert(rig.window.leads, Sequence.difference(packet.command, rig.tick % WRAP))
			end

			Commands.receive(
				connection,
				packet.command,
				packet.acknowledged,
				packet.received,
				packet.delay,
				packet.wires
			)
		end

		table.clear(inbound)

		rig.tick += 1
		rig.window.ticks += 1

		local wire: number = rig.tick % WRAP
		local command: any, standIn: boolean = Commands.take(connection, wire)
		if standIn then
			rig.window.standIns += 1
		else
			rig.window.real += 1
		end

		serverWorld.tick = wire
		Step.advance(body, command, serverWorld)

		body.depth = Commands.depth(connection)
		rig.window.depths[body.depth] = (rig.window.depths[body.depth] or 0) + 1

		local length: number = OwnerState.write(body, scratch, 0, layout, limits)
		local data: buffer = buffer.create(length)
		buffer.copy(data, 0, scratch, 0, length)

		lastDown = math.max(rig.now + rig.down, lastDown)
		table.insert(toClient, {
			arrival = lastDown,
			command = 0,
			acknowledged = 0,
			received = 0,
			delay = 0,
			wires = {},
			data = data,
		})
	end

	-- A Heartbeat: the Moves arrived by now handed over, then the ticks owed, at most the catch-up and the rest dropped
	local function serverFrame()
		while toServer[1] and toServer[1].arrival <= rig.now + TOLERANCE do
			table.insert(inbound, table.remove(toServer, 1) :: Packet)
		end

		pending += (rig.now - lastServer) * rate
		lastServer = rig.now

		local due: number = math.floor(pending + TOLERANCE)
		if due <= 0 then
			return
		end

		pending = math.max(pending - due, 0)

		local running: number = math.min(due, rig.catchUp)
		rig.window.dropped += due - running

		for _ = 1, running do
			serverTick()
		end
	end

	-- A client frame: the OwnerStates arrived by now read, then the frame's time run
	local function clientFrame()
		while toClient[1] and toClient[1].arrival <= rig.now + TOLERANCE do
			local packet: Packet = table.remove(toClient, 1) :: Packet
			Predict.receive(packet.data)
		end

		Predict.frame(rig.now - lastClient)
		lastClient = rig.now
	end

	--[[
	    Runs both sides for the seconds given, each event at its own time and
	    the server's first when both fall at once
	--]]

	function rig.run(seconds: number)
		local finish: number = rig.now + seconds

		while true do
			local at: number = math.min(nextServer, nextClient)
			if at > finish + TOLERANCE then
				break
			end

			rig.window.seconds += at - rig.now
			rig.now = at

			if nextServer <= at + TOLERANCE then
				serverFrame()
				nextServer = rig.now + rig.serverFrame
			end

			if nextClient <= at + TOLERANCE then
				clientFrame()
				nextClient = rig.now + rig.clientFrame
			end
		end

		rig.window.seconds += finish - rig.now
		rig.now = finish
	end

	-- Holds the server's next Heartbeat back by the seconds given, as a stalled server frame does
	function rig.stallServer(seconds: number)
		nextServer += seconds
	end

	-- Holds the client's next frame back by the seconds given
	function rig.stallClient(seconds: number)
		nextClient += seconds
	end

	-- What was counted since the window last opened, and a new one opened
	function rig.take(): Window
		local window: Window = rig.window
		rig.window = newWindow()

		return window
	end

	--[[
	    Runs the seconds given in a window of their own, and says whether the
	    server ran a real command every tick with no ahead, late or standIn
	    report, and every OwnerState's queue sat inside the lead band
	--]]

	function rig.settled(seconds: number): (boolean, string | nil)
		local ticks: any = shared.ticks
		rig.take()
		rig.run(seconds)

		local window: Window = rig.take()
		local ahead: number = window.reports.ahead or 0
		local late: number = window.reports.late or 0
		if window.standIns > 0 or ahead > 0 or late > 0 then
			local reports: string = `{ahead} ahead and {late} late reports`
			return false, `the server ran {window.standIns} stand-ins in {window.ticks} ticks, with {reports}`
		end

		for depth: number, count: number in window.depths do
			if depth < ticks.leadMin or depth > ticks.leadMax then
				return false,
					`{count} OwnerStates carried a queue of {depth}, outside {ticks.leadMin} to {ticks.leadMax}`
			end
		end

		return true, nil
	end

	return rig
end

return Link
