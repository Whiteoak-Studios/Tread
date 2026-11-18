--[[
    Keyframes taken while a mixed run's round is out: an in-process view's,
    and a worker's watcher's of it, match a serial relay's after its run,
    and a worker's view's, and an in-process watcher's of it, before its run
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local WORKERS: number = 2
local MODULUS: number = 2 ^ 31 - 1 -- Park and Miller's generator
local MULTIPLIER: number = 16807
local SEED: number = 1212
local CENTER: vector = vector.create(200, 0, -700)
local SPREAD: number = 60
local STEP: number = 1.5 -- Studs a body may move along each axis a run
local PLAYERS: number = 4 -- On each kind of view
local MODERATOR_AT: vector = vector.create(-2500, 0, 2500)
local RUNS: number = 12
local WORKERS_RUN: number = 2 -- The workers' views and their watcher are made this run, the in-process ones' the first
local IN_PROCESS_RUN: number = 3 -- And the in-process watcher this one
local WATCH_RUN: number = 4 -- Both moderators watch from this run, and the windows are read from the run after
local SPAWN_RUN: number = 7 -- A body comes in near everyone, so every view reveals it in this run
local HELD_RUN: number = 9 -- A held item changes, so this run's held items differ from the last

type Generator = () -> number

type Side = {
	Harness: any,
	harness: any,
	clients: { [string]: any },
}

local function generator(seed: number): Generator
	local value: number = seed

	return function (): number
		value = value * MULTIPLIER % MODULUS

		return value / MODULUS
	end
end

return function (): (boolean, string | nil)
	local serial: Side = { Harness = Environment.load(HARNESS), harness = nil, clients = {} }
	serial.harness = serial.Harness.new()

	local mixedHarness: any = Layouts.harness()
	local mixed: Side = { Harness = mixedHarness, harness = mixedHarness.new(nil, nil, WORKERS), clients = {} }
	local sides: { Side } = { serial, mixed }
	local random: Generator = generator(SEED)

	local function join(name: string, at: vector, owned: boolean)
		for _, built: Side in sides do
			local client: any = built.harness:viewer(name)
			built.clients[name] = client
			client.viewer.position = at
			if owned then
				client.viewer.slot = built.harness:spawn("Player", at)
			end
		end
	end

	local function within(): vector
		return CENTER + vector.create((random() - 0.5) * SPREAD, 0, (random() - 0.5) * SPREAD)
	end

	-- The in-process views first, each view homed at its first run
	mixed.Harness.Relay.useWorkers(false)
	for index: number = 1, PLAYERS do
		join(`Near{index}`, within(), true)
	end

	-- Which keyframe a window's must equal: serial's after its run, or before it
	local AFTER: { string } = { "Near1", "Near2", "WorkerModerator" }
	local BEFORE: { string } = { "Far1", "Far2", "NearModerator" }

	local realPool: any = mixed.harness.pool
	local window: { [string]: string } = {}
	mixed.harness.pool = {
		deliver = function (_: any)
			for _, list: { string } in { AFTER, BEFORE } do
				for _, name: string in list do
					local client: any = mixed.clients[name]
					if client then
						window[name] = buffer.tostring(mixed.Harness.Relay.keyframe(client.viewer.key))
					end
				end
			end

			realPool:deliver()
		end,
	}

	local compared: number = 0
	for run: number = 1, RUNS do
		if run == WORKERS_RUN then
			-- The workers' views and a watcher on a worker, then a watcher in process
			mixed.Harness.Relay.useWorkers(true)
			for index: number = 1, PLAYERS do
				join(`Far{index}`, within(), true)
			end

			join("WorkerModerator", MODERATOR_AT, false)
		elseif run == IN_PROCESS_RUN then
			mixed.Harness.Relay.useWorkers(false)
			join("NearModerator", MODERATOR_AT + vector.create(30, 0, 0), false)
		elseif run == WATCH_RUN then
			for _, built: Side in sides do
				built.harness:watch(built.clients.WorkerModerator, built.clients.Near1)
				built.harness:watch(built.clients.NearModerator, built.clients.Far1)
			end
		elseif run == SPAWN_RUN then
			for _, built: Side in sides do
				built.harness:spawn("Player", CENTER)
			end
		elseif run == HELD_RUN then
			for _, built: Side in sides do
				built.harness.states[built.clients.Near2.viewer.slot].held = { item = 4, skin = 6 }
				built.harness.states[built.clients.Far2.viewer.slot].held = { item = 8, skin = 1 }
			end
		end

		local moves: { [string]: vector } = {}
		for name: string, client: any in serial.clients do
			if client.viewer.slot ~= nil then
				moves[name] = vector.create((random() - 0.5) * 2 * STEP, 0, (random() - 0.5) * 2 * STEP)
			end
		end

		for _, built: Side in sides do
			for name: string, move: vector in moves do
				local client: any = built.clients[name]
				local state: any = built.harness.states[client.viewer.slot]
				state.position += move
				client.viewer.position = state.position
			end
		end

		-- Serial's keyframes before its run and after it, for each viewer joined by then
		local function keyframes(names: { string }): { [string]: string }
			local taken: { [string]: string } = {}
			for _, name: string in names do
				local client: any = serial.clients[name]
				if client then
					taken[name] = buffer.tostring(serial.Harness.Relay.keyframe(client.viewer.key))
				end
			end

			return taken
		end

		local before: { [string]: string } = keyframes(BEFORE)
		serial.harness:run()
		mixed.harness:run()
		local after: { [string]: string } = keyframes(AFTER)

		-- Each keyframe once the round is in matches serial's after its run
		for name: string in serial.clients do
			local expected: string = buffer.tostring(serial.Harness.Relay.keyframe(serial.clients[name].viewer.key))
			if buffer.tostring(mixed.Harness.Relay.keyframe(mixed.clients[name].viewer.key)) ~= expected then
				return false, `Run {run}: {name}'s keyframe after the finish differs from serial's after its run`
			end
		end

		if run > WATCH_RUN then
			for name: string, expected: string in after do
				if window[name] ~= expected then
					return false, `Run {run}: {name}'s keyframe inside the window differs from serial's after its run`
				end
			end

			for name: string, expected: string in before do
				if window[name] ~= expected then
					return false, `Run {run}: {name}'s keyframe inside the window differs from serial's before its run`
				end
			end

			compared += 1
		end
	end

	if compared == 0 then
		return false, "No window was compared"
	end

	return true, nil
end
