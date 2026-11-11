--[[
    `lune run changes`: the relay's worst case, 150 viewers each sent 149
    moving players, run with relay.changes off and then on, printing each
    arm's relay run time, bytes and heap growth a run. A report alone
--]]

--!strict
local Environment = require("../tests/Environment")

local SLOTS_PATH: string = "src/Server/Slots.luau"
local RELAY_PATH: string = "src/Server/Relay.luau"
local FIELDS_PATH: string = "src/Codec/Fields.luau"
local STATE_PATH: string = "src/Step/State.luau"
local EXAMPLE_PATH: string = "tests/Fixtures/Config/Example.luau"
local SLOTS_MODULE: string = "ReplicatedStorage.Packages.Tread.Server.Slots" -- Where the relay requires the slot table

local PLAYERS: number = 150 -- Each one a viewer and a target of every other
local ROW: number = 15 -- Players a row of the grid holds
local SPACING: number = 6 -- Studs between them, so all 150 stand inside the near tier
local CIRCLE: number = 2 -- Studs, the radius each walks round its spot
local WALK: number = 0.4 -- Radians round its circle a player walks a run, about 0.8 studs, a 16 studs/s walk at 20 Hz
local TURN: number = 0.05 -- Radians its facing turns a run
local WARMUP: number = 40 -- Runs before measuring, so every reveal is acknowledged and every baseline set
local RUNS: number = 200 -- Runs measured
local FRAME_BYTES: number = 3 -- Volt's framing in front of each block, as the relay counts it
local RECEIVED: number = 2 ^ 16 - 1 -- Every one of the 16 sequences before the newest received
local MILLISECONDS: number = 1000
local KIB: number = 1024 -- Bytes, and the heap's count in KiB
local RELAY_RATE: number = 20 -- The example's relay rate, Hz

type Arm = { milliseconds: number, bytes: number, heap: number }

-- One arm's runs: the relay started on the example with relay.changes as given, every acknowledgment arriving at once
local function arm(changes: boolean): Arm
	local Slots: any = Environment.load(SLOTS_PATH)
	local Relay: any = Environment.load(RELAY_PATH, { [SLOTS_MODULE] = Slots })
	local Fields: any = Environment.load(FIELDS_PATH)
	local State: any = Environment.load(STATE_PATH)
	local Example: any = Environment.load(EXAMPLE_PATH)

	local shared: any = Example.shared()
	local server: any = Example.server()
	server.relay = { changes = changes }
	server.tiers.outOfView = nil

	local bytes: number = 0
	local newest: { [any]: number } = {}

	local function send(keys: { any }, data: buffer)
		for _, key: any in keys do
			bytes += buffer.len(data) + FRAME_BYTES
			newest[key] = buffer.readu16(data, 0)
		end
	end

	local function traffic(_: any): number
		return 0
	end

	local function hidden(_: any, _: number): boolean
		return false
	end

	Slots.start(server.slots.reserve)
	Relay.start(
		{ shared = shared, server = server, layout = Fields.compile(shared.fields) },
		send,
		send,
		traffic,
		hidden
	)

	local states: { [number]: any } = {}
	local spots: { [number]: vector } = {}
	local viewers: { any } = {}

	for index: number = 0, PLAYERS - 1 do
		local slot: number = Slots.take("Player")
		Slots.setEntry(slot, { kind = "Player", rig = "A" })

		local spot: vector = vector.create(index % ROW * SPACING, 0, index // ROW * SPACING)
		local state: any = State.new()
		state.position = spot
		state.mode = "Ground"
		state.grounded = true

		states[slot] = state
		spots[slot] = spot
		table.insert(viewers, {
			key = { Name = `Viewer{index}` },
			slot = slot,
			position = spot,
			acknowledged = 0,
			received = 0,
		})
	end

	local commands: { [number]: any } = {}
	local elapsed: number = 0
	local heapBefore: number = 0

	for run: number = 1, WARMUP + RUNS do
		for slot: number, state: any in states do
			local angle: number = slot + run * WALK
			state.position = spots[slot] + vector.create(math.cos(angle) * CIRCLE, 0, math.sin(angle) * CIRCLE)
			state.facing = (run * TURN) % (2 * math.pi)
		end

		for _, viewer: any in viewers do
			viewer.position = states[viewer.slot].position
		end

		if run == WARMUP + 1 then
			bytes = 0
			heapBefore = collectgarbage("count")
		end

		local started: number = os.clock()
		Relay.run(run, viewers, states, commands, nil)
		if run > WARMUP then
			elapsed += os.clock() - started
		end

		for _, viewer: any in viewers do
			viewer.acknowledged = newest[viewer.key] or 0
			viewer.received = RECEIVED
		end
	end

	return {
		milliseconds = elapsed / RUNS * MILLISECONDS,
		bytes = bytes / RUNS,
		heap = (collectgarbage("count") - heapBefore) / RUNS,
	}
end

local function line(label: string, result: Arm): string
	local perViewer: number = result.bytes / PLAYERS * RELAY_RATE / KIB
	local run: string = string.format("%.2f ms a relay run", result.milliseconds)
	local sent: string = string.format("%.0f B a run, %.2f KiB/s a viewer", result.bytes, perViewer)

	return `{label}: {run}, {sent}, heap {string.format("%+.2f", result.heap)} KiB a run`
end

local whole: Arm = arm(false)
local changed: Arm = arm(true)

print(`{PLAYERS} viewers each sent {PLAYERS - 1} moving players, {RUNS} runs after {WARMUP} of warm-up`)
print(line("relay.changes off", whole))
print(line("relay.changes on ", changed))
print(
	string.format(
		"changes: %+.2f ms a run, %.0f%% of the bytes",
		changed.milliseconds - whole.milliseconds,
		changed.bytes / whole.bytes * 100
	)
)
