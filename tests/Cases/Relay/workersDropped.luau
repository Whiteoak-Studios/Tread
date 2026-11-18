--[[
    A round given up and a worker whose run throws: from the run after each,
    every send, tap frame and query on the workers matches a serial relay
    whose matching run's sends were all lost, and the kept calls still run
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local WORKERS: number = 2
local MODULUS: number = 2 ^ 31 - 1 -- Park and Miller's generator
local MULTIPLIER: number = 16807
local SEED: number = 808
local CENTER: vector = vector.create(-900, 0, 300)
local SPREAD: number = 60
local STEP: number = 1.5 -- Studs a body may move along each axis a run, so every viewer is sent a record a run
local TURN: number = 0.3
local HIDDEN: number = 0.2
local SHUFFLE: number = 6
local PLAYERS: number = 10
local RUNS: number = 24
local NEAR: number = 30
local MODERATOR_AT: vector = vector.create(2000, 0, 2000)
local LOST: number = math.huge -- The blocks a client loses in a run whose sends are thrown away
local FAILURE: string = "A planted failure out of worker 2's Remote.run"

local WATCH_RUN: number = 2
local DROP_RUN: number = 8
local THROW_RUN: number = 15
local THROWING: number = 2 -- The worker whose run throws

type Generator = () -> number

type Side = {
	Harness: any,
	harness: any,
	names: { [any]: string },
	clients: { [string]: any },
	keys: { any },
	log: { string },
	frames: { string },
}

local function generator(seed: number): Generator
	local value: number = seed

	return function (): number
		value = value * MULTIPLIER % MODULUS

		return value / MODULUS
	end
end

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
		keys = {},
		log = {},
		frames = {},
	}

	local function label(keys: { any }): string
		local names: { string } = {}
		for index: number, key: any in keys do
			names[index] = built.names[key]
		end

		return table.concat(names, ",")
	end

	built.harness._deliver = function (self: any, keys: { any }, data: buffer)
		table.insert(built.log, `block {label(keys)} {buffer.tostring(data)}`)
		Harness._deliver(self, keys, data)
	end

	built.harness._withhold = function (self: any, keys: { any }, data: buffer)
		table.insert(built.log, `withheld {label(keys)} {buffer.tostring(data)}`)
		Harness._withhold(self, keys, data)
	end

	return built
end

local function queries(built: Side, top: number): { string }
	local Relay: any = built.Harness.Relay
	local answers: { string } = {}

	for _, key: any in built.keys do
		local name: string = built.names[key]
		table.insert(answers, `keyframe {name} {buffer.tostring(Relay.keyframe(key))}`)

		local sent: { string } = {}
		for slot: number = 0, top do
			if Relay.isSent(key, slot) then
				table.insert(sent, `{slot}`)
			end
		end

		table.insert(answers, `isSent {name} {table.concat(sent, ",")}`)
	end

	for slot: number = 0, top do
		local names: { string } = {}
		for index: number, key: any in Relay.viewersOf(slot) do
			names[index] = built.names[key]
		end

		-- As a set, since a key that leaves and comes back may come back elsewhere in a relay's walk of its views
		table.sort(names)
		table.insert(answers, `viewersOf {slot} {table.concat(names, ",")}`)
	end

	return answers
end

local function compare(what: string, serial: { string }, workers: { string }): string?
	for index: number = 1, math.max(#serial, #workers) do
		if serial[index] ~= workers[index] then
			local expected: string = (serial[index] or "nothing"):sub(1, 60)
			local got: string = (workers[index] or "nothing"):sub(1, 60)

			return `{what} {index} was "{expected}" serially and "{got}" on the workers`
		end
	end

	return nil
end

-- Every client of a side loses what it is sent this run, or none of it
local function lose(built: Side, lost: boolean)
	for _, client: any in built.clients do
		client.lose = lost and LOST or 0
	end
end

return function (): (boolean, string | nil)
	local serial: Side = side(nil)
	local workers: Side = side(WORKERS)
	local sides: { Side } = { serial, workers }
	local random: Generator = generator(SEED)
	local top: number = 0

	-- One key object for both sides, so both relays' answers name the same keys
	local function join(name: string, at: vector, owned: boolean)
		local key: { Name: string } = { Name = name }
		for _, built: Side in sides do
			local harness: any = built.harness
			local client: any = harness:viewer(name)
			local made: any = client.viewer.key
			client.viewer.key = key
			harness.clients[key], harness.clients[made] = client, nil
			harness.hidden[key], harness.hidden[made] = harness.hidden[made], nil
			harness.reasons[key], harness.reasons[made] = harness.reasons[made], nil

			built.names[key] = name
			built.clients[name] = client
			table.insert(built.keys, key)
			client.viewer.position = at
			if owned then
				client.viewer.slot = harness:spawn("Player", at)
				top = math.max(top, client.viewer.slot)
			end
		end
	end

	for index: number = 1, PLAYERS do
		join(`Player{index}`, CENTER + vector.create((random() - 0.5) * SPREAD, 0, (random() - 0.5) * SPREAD), true)
	end

	join("Moderator", MODERATOR_AT, false)

	for _, built: Side in sides do
		built.Harness.Taps.observe(built.clients.Player1.viewer.key, function (_: number, data: buffer)
			table.insert(built.frames, buffer.tostring(data))
		end)
	end

	-- The workers' pool: the stand-in, given up at the drop's run and failing its worker at the throw's
	local realPool: any = workers.harness.pool
	local landed: any = realPool.landed
	local throwing: boolean = false
	realPool.landed = function (self: any, worker: number, round: number): (buffer?, string?)
		local result: buffer?, failure: string? = landed(self, worker, round)
		if throwing and worker == THROWING and (result ~= nil or failure ~= nil) then
			return nil, FAILURE
		end

		return result, failure
	end

	local run: number = 0
	local Relay: any = workers.Harness.Relay
	workers.harness.pool = {
		deliver = function (_: any)
			if run == DROP_RUN then
				Relay.setDistance(workers.clients.Player3.viewer.key, NEAR)
				Relay.drop()
			else
				if run == THROW_RUN then
					Relay.shotNear(workers.clients.Player4.viewer.key, workers.clients.Player5.viewer.slot)
				end

				realPool:deliver()
			end
		end,
	}

	local dropCounts: { number } = {}
	local reached: { [string]: boolean } = {}

	for current: number = 1, RUNS do
		run = current

		if run == WATCH_RUN then
			for _, built: Side in sides do
				built.harness:watch(built.clients.Moderator, built.clients.Player2)
			end
		elseif run == DROP_RUN or run == THROW_RUN then
			-- A body every view starts being sent in the run whose round is lost, so the views' copies change with it
			for _, built: Side in sides do
				top = math.max(top, built.harness:spawn("Npc", CENTER))
			end
		end

		local shuffled: boolean = run % SHUFFLE == 1
		local moves: { [number]: { number } } = {}
		local hides: { [string]: { [number]: boolean } } = {}
		for name: string, client: any in serial.clients do
			local slot: number? = client.viewer.slot
			if slot ~= nil then
				moves[slot] = { (random() - 0.5) * 2 * STEP, (random() - 0.5) * 2 * STEP, (random() - 0.5) * 2 * TURN }
			end

			if shuffled then
				hides[name] = {}
				for _, other: any in serial.clients do
					if other ~= client and other.viewer.slot ~= nil then
						hides[name][other.viewer.slot] = random() < HIDDEN
					end
				end
			end
		end

		for _, built: Side in sides do
			for slot: number, move: { number } in moves do
				local state: any = built.harness.states[slot]
				state.position += vector.create(move[1], 0, move[2])
				state.facing += move[3]
			end

			for name: string, client: any in built.clients do
				local slot: number? = client.viewer.slot
				if slot ~= nil then
					local state: any = built.harness.states[slot]
					client.viewer.position = state.position
					client.viewer.look = vector.create(-math.sin(state.facing), 0, -math.cos(state.facing))
				end

				for otherSlot: number, on: boolean in hides[name] or {} do
					built.harness:hide(client, otherSlot, on)
				end
			end

			built.log = {}
			built.frames = {}
		end

		-- The serial run whose sends are thrown away, as the round on the workers gives them up
		local lost: boolean = run == DROP_RUN or run == THROW_RUN
		local before: number, _ = serial.Harness.Relay.counts()
		lose(serial, lost)
		serial.harness:run()
		lose(serial, false)
		if run == DROP_RUN then
			serial.Harness.Relay.setDistance(serial.clients.Player3.viewer.key, NEAR)
			local after: number, _ = serial.Harness.Relay.counts()
			dropCounts = { after - before }
		elseif run == THROW_RUN then
			serial.Harness.Relay.shotNear(serial.clients.Player4.viewer.key, serial.clients.Player5.viewer.slot)
		end

		throwing = run == THROW_RUN
		lose(workers, lost)
		local ran: boolean, failure: any = pcall(workers.harness.run, workers.harness)
		lose(workers, false)
		throwing = false

		if run == THROW_RUN then
			-- The failure raised at the throwing worker's first viewer, the turns before it sent
			if ran or `{failure}` ~= FAILURE then
				return false, `The throwing worker's run gave {ran} "{failure}", not its failure`
			elseif #workers.log == 0 or #workers.log >= #serial.log then
				return false, `The workers sent {#workers.log} of the serial run's {#serial.log} before the failure`
			end

			local sentBefore: { string } = table.move(serial.log, 1, #workers.log, 1, {})
			local why: string? = compare("The throwing run's send", sentBefore, workers.log)
			if why ~= nil then
				return false, why
			end

			-- The taps the run's turns before the failure made go with the lost run's frame
			if workers.Harness.Taps.observing then
				workers.Harness.Taps.finish(workers.harness.tick)
			end

			reached.throw = true
		elseif not ran then
			return false, `Run {run} on the workers threw: {failure}`
		elseif not lost then
			local why: string? = compare(`Run {run}'s send`, serial.log, workers.log)
				or compare(`Run {run}'s frame`, serial.frames, workers.frames)
				or compare(`Run {run}'s answer`, queries(serial, top), queries(workers, top))
			if why ~= nil then
				return false, why
			end

			-- A dropped run's counts are lost, and none after it
			if run > DROP_RUN and run < THROW_RUN then
				local serialSent: number, _ = serial.Harness.Relay.counts()
				local workerSent: number, _ = Relay.counts()
				if workerSent ~= serialSent - dropCounts[1] then
					return false, `Run {run}'s records sent were {workerSent} on the workers, serially {serialSent}`
				end

				reached.counts = true
			end
		else
			reached.drop = true
		end
	end

	if not (reached.drop and reached.throw and reached.counts) or dropCounts[1] == 0 then
		return false, "The runs never reached a drop, a throw and the counts after the drop"
	end

	return true, nil
end
