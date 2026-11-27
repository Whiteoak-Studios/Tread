--[[
    Views made with the workers switched on and off between runs, two
    moderators each watching across the two kinds of view: every recipient
    gets the blocks, withheld blocks and tap frames a run all in process gives
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local WORKERS: number = 2
local MODULUS: number = 2 ^ 31 - 1 -- Park and Miller's generator
local MULTIPLIER: number = 16807
local SEED: number = 606
local CENTER: vector = vector.create(-300, 0, 500)
local SPREAD: number = 120
local STEP: number = 1.5 -- Studs a body may move along each axis a run
local TURN: number = 0.4 -- Radians a body may turn either way a run
local JUMP: number = 0.1
local HIDDEN: number = 0.25 -- The share of pairs anti-ESP hides at each shuffle
local SHUFFLE: number = 4 -- Runs between shuffles
local RUNS: number = 24
local BATCH: number = 6 -- The viewers each batch joins with
local NEAR: number = 60 -- A render distance some viewers set
local MODERATOR_AT: vector = vector.create(2500, 0, -2500)

-- The runs things happen at, as their names say
local WORKERS_ON_RUN: number = 4 -- Before it the in-process batch alone runs, from it the workers' batch joins
local WORKERS_OFF_RUN: number = 7
local WORKERS_AGAIN_RUN: number = 9
local FIRST_WATCH: number = 10 -- The in-process moderator watches a worker's viewer
local SECOND_WATCH: number = 12 -- The worker's moderator watches an in-process viewer
local FIRST_RETURN: number = 17
local SECOND_RETURN: number = 19
local LOOK_RUN: number = 11
local HELD_RUN: number = 13
local CALLS_RUN: number = 15

type Generator = () -> number

-- One harness and what each of its recipients was sent this run, by name
type Side = {
	Harness: any,
	harness: any,
	names: { [any]: string },
	clients: { any },
	sent: { [string]: { string } },
	frames: { [string]: { string } },
}

local function generator(seed: number): Generator
	local value: number = seed

	return function (): number
		value = value * MULTIPLIER % MODULUS

		return value / MODULUS
	end
end

-- A harness, in process or with the workers, whose every block and withheld block is kept by its recipient's name
local function side(workers: number?): Side
	local Harness: any
	if workers then
		Harness = Layouts.harness()
	else
		Harness = Environment.load(HARNESS)
	end

	local built: Side = {
		Harness = Harness,
		harness = Harness.new(nil, nil, workers),
		names = {},
		clients = {},
		sent = {},
		frames = {},
	}

	local function keep(kind: string, keys: { any }, data: buffer)
		for _, key: any in keys do
			local name: string = built.names[key]
			built.sent[name] = built.sent[name] or {}
			table.insert(built.sent[name], `{kind} {buffer.tostring(data)}`)
		end
	end

	built.harness._deliver = function (self: any, keys: { any }, data: buffer)
		keep("block", keys, data)
		Harness._deliver(self, keys, data)
	end

	built.harness._withhold = function (self: any, keys: { any }, data: buffer)
		keep("withheld", keys, data)
		Harness._withhold(self, keys, data)
	end

	return built
end

-- Why two sides' records by name differ, or nil when they match
local function compare(what: string, serial: { [string]: { string } }, mixed: { [string]: { string } }): string?
	for name: string, lines: { string } in serial do
		local other: { string } = mixed[name] or {}
		for index: number = 1, math.max(#lines, #other) do
			if lines[index] ~= other[index] then
				return `{name}'s {what} {index} differs`
			end
		end
	end

	for name: string in mixed do
		if serial[name] == nil then
			return `{name} got {what}s only with the workers`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local serial: Side = side(nil)
	local mixed: Side = side(WORKERS)
	local sides: { Side } = { serial, mixed }
	local random: Generator = generator(SEED)
	local pool: any = mixed.harness.pool

	-- A viewer on both sides with a body of its own when owned
	local function join(name: string, at: vector, owned: boolean): { any }
		local joined: { any } = {}
		for _, built: Side in sides do
			local client: any = built.harness:viewer(name)
			built.names[client.viewer.key] = name
			table.insert(built.clients, client)
			client.viewer.position = at
			if owned then
				client.viewer.slot = built.harness:spawn("Player", at)
			end

			table.insert(joined, client)
		end

		if owned and joined[1].viewer.slot ~= joined[2].viewer.slot then
			error("The two sides gave a viewer's body different slots")
		end

		return joined
	end

	local function batch(prefix: string): { { any } }
		local joined: { { any } } = {}
		for index: number = 1, BATCH do
			local at: vector = CENTER + vector.create((random() - 0.5) * SPREAD, 0, (random() - 0.5) * SPREAD)
			table.insert(joined, join(`{prefix}{index}`, at, true))
		end

		return joined
	end

	-- A sink on both sides for a viewer's frames, or its withheld records', kept by name
	local function observe(pair: { any }, withheld: boolean)
		for index: number, built: Side in sides do
			local client: any = pair[index]
			local name: string = built.names[client.viewer.key]
			if withheld then
				name = `{name} withheld`
			end

			local function sink(_: number, data: buffer)
				built.frames[name] = built.frames[name] or {}
				table.insert(built.frames[name], buffer.tostring(data))
			end

			if withheld then
				built.Harness.Taps.observeWithheld(client.viewer.key, sink)
			else
				built.Harness.Taps.observe(client.viewer.key, sink)
			end
		end
	end

	mixed.Harness.Relay.useWorkers(false)
	local inProcess: { { any } } = batch("InProcess")
	local onWorkers: { { any } } = {}
	local later: { { any } } = {}
	local first: { any } = join("FirstModerator", MODERATOR_AT, false)
	local second: { any } = {}

	observe(inProcess[1], false)
	observe(first, false)

	local worked: boolean = false
	local reached: { [string]: number } = { blocks = 0, withheld = 0, frames = 0, footsteps = 0, looks = 0 }

	for run: number = 1, RUNS do
		if run == WORKERS_ON_RUN then
			-- No round went out while every view was in process
			for worker: number = 1, WORKERS do
				local started: number = pool:times(worker)
				if started ~= 0 then
					return false, `Worker {worker} ran a round before any view was made on the workers`
				end
			end

			mixed.Harness.Relay.useWorkers(true)
			onWorkers = batch("OnWorkers")
			second = join("SecondModerator", MODERATOR_AT + vector.create(50, 0, 0), false)
			observe(onWorkers[1], false)
			observe(onWorkers[2], true)
			observe(second, false)
		elseif run == WORKERS_OFF_RUN then
			mixed.Harness.Relay.useWorkers(false)
			later = batch("Later")
		elseif run == WORKERS_AGAIN_RUN then
			mixed.Harness.Relay.useWorkers(true)
			for _, pair: { any } in batch("Again") do
				table.insert(later, pair)
			end
		end

		for index: number, built: Side in sides do
			local harness: any = built.harness
			if run == FIRST_WATCH then
				harness:watch(first[index], onWorkers[2][index])
			elseif run == SECOND_WATCH then
				harness:watch(second[index], inProcess[2][index])
			elseif run == FIRST_RETURN then
				harness:watch(first[index], nil)
			elseif run == SECOND_RETURN then
				harness:watch(second[index], nil)
			end

			if run == LOOK_RUN then
				built.Harness.Relay.setLook(inProcess[3][index].viewer.slot, { head = 9 })
				built.Harness.Relay.setLook(onWorkers[3][index].viewer.slot, { shirt = 4 })
			elseif run == HELD_RUN then
				harness.states[onWorkers[4][index].viewer.slot].held = { item = 3, skin = 1 }
				harness.states[inProcess[4][index].viewer.slot].held = { item = 5, skin = 2 }
			elseif run == CALLS_RUN then
				built.Harness.Relay.setDistance(later[1][index].viewer.key, NEAR)
				built.Harness.Relay.setDistance(onWorkers[5][index].viewer.key, NEAR)
				built.Harness.Relay.shotNear(inProcess[5][index].viewer.key, onWorkers[6][index].viewer.slot)
				built.Harness.Relay.reveal(inProcess[6][index].viewer.slot)
				built.Harness.Relay.revealAll(onWorkers[6][index].viewer.key)
			end
		end

		-- Every body moves alike on both sides, the hides reshuffled alike
		local shuffled: boolean = run % SHUFFLE == 1
		local moves: { [number]: { vector | number } } = {}
		local hides: { [string]: { [number]: boolean } } = {}
		for _, client: any in serial.clients do
			local slot: number? = client.viewer.slot
			if slot ~= nil then
				local jumped: number = 0
				if random() < JUMP then
					jumped = 1
				end

				moves[slot] = {
					vector.create((random() - 0.5) * 2 * STEP, 0, (random() - 0.5) * 2 * STEP),
					(random() - 0.5) * 2 * TURN,
					jumped,
				}
			end

			if shuffled then
				local name: string = serial.names[client.viewer.key]
				hides[name] = {}
				for _, other: any in serial.clients do
					local otherSlot: number? = other.viewer.slot
					if other ~= client and otherSlot ~= nil then
						hides[name][otherSlot] = random() < HIDDEN
					end
				end
			end
		end

		for _, built: Side in sides do
			for slot: number, move: { vector | number } in moves do
				local state: any = built.harness.states[slot]
				state.position += move[1] :: vector
				state.facing += move[2] :: number
				state.jumps = (state.jumps + move[3] :: number) % 4
			end

			for _, client: any in built.clients do
				local slot: number? = client.viewer.slot
				if slot ~= nil then
					local state: any = built.harness.states[slot]
					client.viewer.position = state.position
					client.viewer.look = vector.create(-math.sin(state.facing), 0, -math.cos(state.facing))
				end

				local hidden: { [number]: boolean }? = hides[built.names[client.viewer.key]]
				if hidden then
					for otherSlot: number, on: boolean in hidden do
						built.harness:hide(client, otherSlot, on)
					end
				end
			end

			built.sent = {}
			built.frames = {}
			built.harness:run()
		end

		for worker: number = 1, WORKERS do
			local started: number = pool:times(worker)
			worked = worked or started ~= 0
		end

		local why: string? = compare("block", serial.sent, mixed.sent) or compare("frame", serial.frames, mixed.frames)
		if why ~= nil then
			return false, `Run {run}: {why}`
		end

		for _, lines: { string } in serial.sent do
			for _, line: string in lines do
				if string.sub(line, 1, 5) == "block" then
					reached.blocks += 1
				else
					reached.withheld += 1
				end
			end
		end

		for _, frames: { string } in serial.frames do
			reached.frames += #frames
		end

		for _, client: any in serial.clients do
			reached.footsteps += #client.seen.footsteps
			reached.looks += #client.seen.looks
		end
	end

	if not worked then
		return false, "No worker ran a round"
	end

	for name: string, count: number in reached do
		if count == 0 then
			return false, `No run reached any {name}`
		end
	end

	return true, nil
end
