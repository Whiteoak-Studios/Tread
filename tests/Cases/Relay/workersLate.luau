--[[
    A worker that turns ready only from a later run takes only views made
    after it does, and its first runs carry every look, Invisible mark and
    held item set before it, so every block matches a serial relay's
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")
local StandIn = require("../../Fixtures/Relay/StandIn")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local WORKERS: number = 2
local LATE: number = 2 -- The worker that turns ready late
local MODULUS: number = 2 ^ 31 - 1 -- Park and Miller's generator
local MULTIPLIER: number = 16807
local SEED: number = 909
local CENTER: vector = vector.create(1500, 0, -1500)
local SPREAD: number = 80
local STEP: number = 1
local EARLY: number = 6 -- The players there from the start
local NEWCOMERS: number = 4 -- And those that join once the late worker is ready
local RUNS: number = 14

local LOOK_RUN: number = 2 -- Set while only the first worker is ready
local INVISIBLE_RUN: number = 3
local HELD_RUN: number = 3
local READY_RUN: number = 5 -- The late worker reports ready from this run on
local MARK_RUN: number = 5 -- A look set after the late worker's first run, which reaches it as a mark
local JOIN_RUN: number = 6

type Generator = () -> number

type Side = {
	Harness: any,
	harness: any,
	names: { [any]: string },
	clients: { any },
	log: { string },
}

-- A pool over StandIn whose late worker answers unready until on, counting the viewers each hand-in names
type Late = {
	inner: any,
	on: boolean,
	counts: { { number } }, -- Each worker's own hand-ins' viewer counts, in order
}

local function generator(seed: number): Generator
	local value: number = seed

	return function (): number
		value = value * MULTIPLIER % MODULUS

		return value / MODULUS
	end
end

return function (): (boolean, string | nil)
	local late: Late = { inner = nil, on = false, counts = {} }

	local LatePool = {}
	LatePool.__index = LatePool

	function LatePool.new(count: number, name: string, remote: any, settings: any): any
		late.inner = StandIn.new(count, name, remote, settings)
		for worker: number = 1, count do
			late.counts[worker] = {}
		end

		return setmetatable({}, LatePool)
	end

	function LatePool.ready(_: any): number
		local ready: number = late.inner:ready()
		if not late.on then
			ready -= 1
		end

		return ready
	end

	function LatePool.isReady(_: any, worker: number): boolean
		return late.inner:isReady(worker) and (worker ~= LATE or late.on)
	end

	function LatePool.send(_: any, worker: number, round: number, shared: buffer, own: buffer)
		if worker == LATE and not late.on then
			error("The front sent a round to a worker that wasn't ready")
		end

		table.insert(late.counts[worker], buffer.readu16(own, 4))
		late.inner:send(worker, round, shared, own)
	end

	function LatePool.landed(_: any, worker: number, round: number): (buffer?, string?)
		return late.inner:landed(worker, round)
	end

	function LatePool.times(_: any, worker: number): (number, number)
		return late.inner:times(worker)
	end

	function LatePool.deliver(_: any)
		late.inner:deliver()
	end

	function LatePool.destroy(_: any)
		late.inner:destroy()
	end

	local function side(workers: number?): Side
		local Harness: any
		if workers then
			Harness = Layouts.harness(LatePool)
		else
			Harness = Environment.load(HARNESS)
		end

		local built: Side = {
			Harness = Harness,
			harness = Harness.new(nil, nil, workers),
			names = {},
			clients = {},
			log = {},
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

		return built
	end

	local serial: Side = side(nil)
	local workers: Side = side(WORKERS)
	local sides: { Side } = { serial, workers }
	local random: Generator = generator(SEED)

	local function join(name: string)
		local at: vector = CENTER + vector.create((random() - 0.5) * SPREAD, 0, (random() - 0.5) * SPREAD)
		for _, built: Side in sides do
			local client: any = built.harness:viewer(name)
			built.names[client.viewer.key] = name
			table.insert(built.clients, client)
			client.viewer.position = at
			client.viewer.slot = built.harness:spawn("Player", at)
		end
	end

	for index: number = 1, EARLY do
		join(`Early{index}`)
	end

	for run: number = 1, RUNS do
		if run == READY_RUN then
			late.on = true
		elseif run == JOIN_RUN then
			for index: number = 1, NEWCOMERS do
				join(`Newcomer{index}`)
			end
		end

		for _, built: Side in sides do
			local Relay: any = built.Harness.Relay
			local clients: { any } = built.clients
			if run == LOOK_RUN then
				Relay.setLook(clients[1].viewer.slot, { head = 5, shirt = 900 })
				Relay.setLook(clients[2].viewer.slot, { face = 2 })
			elseif run == INVISIBLE_RUN then
				Relay.setInvisible(clients[3].viewer.slot, true)
			elseif run == MARK_RUN then
				Relay.setLook(clients[4].viewer.slot, { head = 1 })
			end

			if run == HELD_RUN then
				built.harness.states[clients[5].viewer.slot].held = { item = 9, skin = 4 }
			end
		end

		local moves: { vector } = {}
		for index: number = 1, #serial.clients do
			moves[index] = vector.create((random() - 0.5) * 2 * STEP, 0, (random() - 0.5) * 2 * STEP)
		end

		for _, built: Side in sides do
			for index: number, client: any in built.clients do
				local state: any = built.harness.states[client.viewer.slot]
				state.position += moves[index]
				client.viewer.position = state.position
			end

			built.log = {}
			built.harness:run()
		end

		for index: number = 1, math.max(#serial.log, #workers.log) do
			if serial.log[index] ~= workers.log[index] then
				local expected: string = (serial.log[index] or "nothing"):sub(1, 60)
				local got: string = (workers.log[index] or "nothing"):sub(1, 60)

				return false, `Run {run}'s send {index} was "{expected}" serially and "{got}" on the workers`
			end
		end
	end

	-- The first worker kept the early views and the late one took only the newcomers', from its first round
	local first: { number } = late.counts[1]
	local second: { number } = late.counts[LATE]
	if #first ~= RUNS or #second ~= RUNS - READY_RUN + 1 then
		return false, `The workers were sent {#first} and {#second} rounds`
	end

	for index: number, count: number in first do
		if count ~= EARLY then
			return false, `The first worker's hand-in {index} named {count} viewers, not its {EARLY}`
		end
	end

	for index: number, count: number in second do
		local expected: number = NEWCOMERS
		if index + READY_RUN - 1 < JOIN_RUN then
			expected = 0
		end

		if count ~= expected then
			return false, `The late worker's hand-in {index} named {count} viewers, not {expected}`
		end
	end

	return true, nil
end
