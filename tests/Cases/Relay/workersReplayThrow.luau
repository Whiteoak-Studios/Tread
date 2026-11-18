--[[
    A send that throws while the finish replays the last viewer's turn: the
    same error as the serial relay's, the call kept in the window still run,
    and every later send, tap frame and query matching the serial relay's
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local WORKERS: number = 2
local MODULUS: number = 2 ^ 31 - 1 -- Park and Miller's generator
local MULTIPLIER: number = 16807
local SEED: number = 1313
local CENTER: vector = vector.create(-1400, 0, 900)
local SPREAD: number = 50
local STEP: number = 1.5 -- Studs a body may move along each axis a run, so every viewer is sent a record a run
local PLAYERS: number = 6
local THROWER: string = "Player6" -- Last in the list, with one block a run and no watcher, so serial stops there too
local RUNS: number = 14
local THROW_RUN: number = 6
local NEAR: number = 20 -- The distance the call kept in the throwing run's window sets

type Generator = () -> number

type Side = {
	Harness: any,
	harness: any,
	names: { [any]: string },
	clients: { [string]: any },
	keys: { any },
	log: { string },
	frames: { string },
	throwing: boolean,
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
		throwing = false,
	}

	local function label(keys: { any }): string
		local names: { string } = {}
		for index: number, key: any in keys do
			names[index] = built.names[key]
		end

		return table.concat(names, ",")
	end

	built.harness._deliver = function (self: any, keys: { any }, data: buffer)
		if built.throwing and built.names[keys[1]] == THROWER then
			error("A planted failure of the send port")
		end

		table.insert(built.log, `block {label(keys)} {buffer.tostring(data)}`)
		Harness._deliver(self, keys, data)
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

return function (): (boolean, string | nil)
	local serial: Side = side(nil)
	local workers: Side = side(WORKERS)
	local sides: { Side } = { serial, workers }
	local random: Generator = generator(SEED)
	local top: number = 0

	-- One key object for both sides, so both relays' answers name the same keys
	for index: number = 1, PLAYERS do
		local name: string = `Player{index}`
		local key: { Name: string } = { Name = name }
		local at: vector = CENTER + vector.create((random() - 0.5) * SPREAD, 0, (random() - 0.5) * SPREAD)

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
			client.viewer.slot = harness:spawn("Player", at)
			top = math.max(top, client.viewer.slot)
		end
	end

	for _, built: Side in sides do
		built.Harness.Taps.observe(built.clients.Player1.viewer.key, function (_: number, data: buffer)
			table.insert(built.frames, buffer.tostring(data))
		end)
	end

	-- The call the throwing run's window makes on the workers, which serial makes after its run
	local realPool: any = workers.harness.pool
	local run: number = 0
	workers.harness.pool = {
		deliver = function (_: any)
			if run == THROW_RUN then
				workers.Harness.Relay.setDistance(workers.clients.Player2.viewer.key, NEAR)
			end

			realPool:deliver()
		end,
	}

	local thrown: number = 0
	for current: number = 1, RUNS do
		run = current

		local moves: { [string]: vector } = {}
		for name: string in serial.clients do
			moves[name] = vector.create((random() - 0.5) * 2 * STEP, 0, (random() - 0.5) * 2 * STEP)
		end

		-- A body every view starts being sent in the throwing run, so the views' copies change with it
		if run == THROW_RUN then
			for _, built: Side in sides do
				top = math.max(top, built.harness:spawn("Npc", CENTER))
			end
		end

		local errors: { string } = {}
		for index: number, built: Side in sides do
			for name: string, move: vector in moves do
				local client: any = built.clients[name]
				local state: any = built.harness.states[client.viewer.slot]
				state.position += move
				client.viewer.position = state.position
			end

			built.log = {}
			built.frames = {}
			built.throwing = run == THROW_RUN

			local ran: boolean, failure: any = pcall(built.harness.run, built.harness)
			built.throwing = false
			errors[index] = ""
			if not ran then
				errors[index] = `{failure}`
			end

			-- A run that threw stopped the harness before its taps' frames and acknowledgments
			if not ran then
				if built.Harness.Taps.observing then
					built.Harness.Taps.finish(built.harness.tick)
				end

				if built == serial then
					serial.Harness.Relay.setDistance(serial.clients.Player2.viewer.key, NEAR)
				end
			end
		end

		if errors[1] ~= errors[2] then
			return false, `Run {run} ended "{errors[1]}" serially and "{errors[2]}" on the workers`
		elseif run == THROW_RUN then
			if not string.find(errors[1], "planted failure", 1, true) then
				return false, `The throwing run ended "{errors[1]}"`
			end

			thrown += 1
		elseif errors[1] ~= "" then
			return false, `Run {run} threw: {errors[1]}`
		end

		local why: string? = compare(`Run {run}'s send`, serial.log, workers.log)
			or compare(`Run {run}'s frame`, serial.frames, workers.frames)
			or compare(`Run {run}'s answer`, queries(serial, top), queries(workers, top))
		if why ~= nil then
			return false, why
		end
	end

	if thrown == 0 then
		return false, "No run threw"
	end

	return true, nil
end
