--[[
    A worker whose run throws before it reads the run's bodies, in a run that
    changes a held item: the failure is raised after the other worker's
    turns, and every later block matches a serial relay's, the held item too
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")
local StandIn = require("../../Fixtures/Relay/StandIn")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local WORKERS: number = 2
local THROWING: number = 2 -- The worker whose run throws, holding only the viewer away that run
local MASK_BITS: number = 16 -- The sequences before the newest a client's acknowledgment covers
local WRAP: number = 2 ^ 16
local CENTER: vector = vector.create(2200, 0, 400)
local AWAY: string = "Second" -- The second viewer, which the fewest-views rule puts on the throwing worker
local RUNS: number = 10
local THROW_RUN: number = 5

type Side = {
	Harness: any,
	harness: any,
	names: { [any]: string },
	clients: { [string]: any },
	log: { string },
}

-- A pool over StandIn whose throwing worker is handed an own hand-in too short to read while corrupt is on
local Corrupting = { corrupt = false, inner = nil :: any }
Corrupting.__index = Corrupting

function Corrupting.new(count: number, name: string, remote: any, settings: any): any
	Corrupting.inner = StandIn.new(count, name, remote, settings)

	return setmetatable({}, Corrupting)
end

function Corrupting.ready(_: any): number
	return Corrupting.inner:ready()
end

function Corrupting.isReady(_: any, worker: number): boolean
	return Corrupting.inner:isReady(worker)
end

function Corrupting.send(_: any, worker: number, round: number, shared: buffer, own: buffer)
	if Corrupting.corrupt and worker == THROWING then
		own = buffer.create(0)
	end

	Corrupting.inner:send(worker, round, shared, own)
end

function Corrupting.landed(_: any, worker: number, round: number): (buffer?, string?)
	return Corrupting.inner:landed(worker, round)
end

function Corrupting.times(_: any, worker: number): (number, number)
	return Corrupting.inner:times(worker)
end

function Corrupting.deliver(_: any)
	Corrupting.inner:deliver()
end

function Corrupting.destroy(_: any)
	Corrupting.inner:destroy()
end

local function side(workers: number?): Side
	local Harness: any
	if workers then
		Harness = Layouts.harness(Corrupting)
	else
		Harness = Environment.load(HARNESS)
	end

	local built: Side =
		{ Harness = Harness, harness = Harness.new(nil, nil, workers), names = {}, clients = {}, log = {} }

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

-- Each client's acknowledgment of everything it read, as the harness takes them at the end of a run that didn't throw
local function acknowledge(built: Side)
	for _, client: any in built.clients do
		local mask: number = 0
		for back: number = 1, MASK_BITS do
			if client.received[(client.newest - back) % WRAP] then
				mask += 2 ^ (back - 1)
			end
		end

		client.viewer.acknowledged = client.newest
		client.viewer.received = mask
	end
end

return function (): (boolean, string | nil)
	local serial: Side = side(nil)
	local workers: Side = side(WORKERS)
	local sides: { Side } = { serial, workers }

	for index: number, name: string in { "First", AWAY, "Third" } do
		for _, built: Side in sides do
			local client: any = built.harness:viewer(name)
			local at: vector = CENTER + vector.create(index * 6, 0, 0)
			built.names[client.viewer.key] = name
			built.clients[name] = client
			client.viewer.position = at
			client.viewer.slot = built.harness:spawn("Player", at)
		end
	end

	local threw: boolean = false
	for run: number = 1, RUNS do
		-- The throwing worker's own hand-in is too short to read in the throwing run
		Corrupting.corrupt = run == THROW_RUN

		for _, built: Side in sides do
			local viewers: { any } = built.harness.viewers
			if run == THROW_RUN then
				table.remove(viewers, table.find(viewers, built.clients[AWAY].viewer))
				built.harness.states[built.clients.First.viewer.slot].held = { item = 6, skin = 3 }
			elseif run == THROW_RUN + 1 then
				table.insert(viewers, 2, built.clients[AWAY].viewer)
			end

			for _, client: any in built.clients do
				local state: any = built.harness.states[client.viewer.slot]
				state.position += vector.create(1, 0, 0.5)
				client.viewer.position = state.position
			end

			built.log = {}
		end

		serial.harness:run()

		local ran: boolean, failure: any = pcall(workers.harness.run, workers.harness)
		if run == THROW_RUN then
			if ran or not string.find(`{failure}`, "out of bounds", 1, true) then
				return false, `The throwing worker's run raised {failure}, not its read past the hand-in's end`
			end

			acknowledge(workers)
			threw = true
		elseif not ran then
			return false, `Run {run} on the workers threw: {failure}`
		end

		for index: number = 1, math.max(#serial.log, #workers.log) do
			if serial.log[index] ~= workers.log[index] then
				local expected: string = (serial.log[index] or "nothing"):sub(1, 60)
				local got: string = (workers.log[index] or "nothing"):sub(1, 60)

				return false, `Run {run}'s send {index} was "{expected}" serially and "{got}" on the workers`
			end
		end
	end

	if not threw then
		return false, "No run threw"
	end

	return true, nil
end
