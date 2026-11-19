--[[
    A stand-in for the relay's Actor pool in Lune, which has no Actors: each
    worker a Remote in an environment of its own, every setting, hand-in and
    result copied as the boundary copies it, and each round run on deliver
--]]

--!strict
local StandIn = {}
StandIn.__index = StandIn

local Environment = require("../../Environment")

local REMOTE: string = "src/Server/Relay/Remote.luau"
local FIRED: number = 0 -- Seconds a round's fire takes, since a stand-in round fires nothing

-- One round sent and not yet delivered
type Round = {
	worker: number,
	round: number,
	shared: buffer,
	own: buffer,
}

type Fields = {
	_count: number,
	_remotes: { any }, -- Each worker's Remote, loaded in an environment of its own
	_queue: { Round },
	_rounds: { number }, -- The round each worker last delivered
	_results: { [number]: buffer? }, -- And its result, or its failure's text
	_failures: { [number]: string? },
	_starts: { number }, -- And when its Remote.run began and ended, by os.clock()
	_finishes: { number },
	_clocks: { [number]: buffer? }, -- And a copy of the clocks it gave, nil for none
	_landed: { number }, -- And when it landed, its finish, 0 with no clocks
}

-- A copy of a buffer, as an Actor message or a BindableEvent carries one
local function copyBuffer(data: buffer): buffer
	local copied: buffer = buffer.create(buffer.len(data))
	buffer.copy(copied, 0, data)

	return copied
end

--[[
    A copy of a value as an Actor message carries it, every table and
    buffer in it copied, erroring on a function, an Instance or a table
    with a metatable, which the boundary refuses
--]]

local function cross(value: any, path: string): any
	local kind: string = typeof(value)
	if kind == "function" or kind == "Instance" then
		error(`Remote.setup's settings carry a {kind} at {path}, which can't cross an Actor's boundary`, 0)
	elseif kind == "buffer" then
		return copyBuffer(value)
	elseif kind ~= "table" then
		return value
	elseif getmetatable(value) ~= nil then
		error(
			`Remote.setup's settings carry a table with a metatable at {path}, which can't cross an Actor's boundary`,
			0
		)
	end

	local copied: { [any]: any } = {}
	for key: any, inner: any in value do
		copied[key] = cross(inner, `{path}.{key}`)
	end

	return copied
end

--[[
    A pool of count workers, each with its own Remote set up with its own
    copy of settings, all ready at once, erroring before any is made on
    settings the boundary refuses. The name and the Remote ModuleScript an
    Actor pool takes are ignored
--]]

function StandIn.new(count: number, _: string, _: any, settings: any): Self
	cross(settings, "settings")

	local remotes: { any } = {}
	for index: number = 1, count do
		local remote: any = Environment.load(REMOTE)
		remote.setup(cross(settings, "settings"))
		remotes[index] = remote
	end

	return setmetatable({
		_count = count,
		_remotes = remotes,
		_queue = {} :: { Round },
		_rounds = table.create(count, 0),
		_results = {} :: { [number]: buffer? },
		_failures = {} :: { [number]: string? },
		_starts = table.create(count, 0),
		_finishes = table.create(count, 0),
		_clocks = {} :: { [number]: buffer? },
		_landed = table.create(count, 0),
	}, StandIn)
end

-- How many workers are ready, every one of them from the start
function StandIn.ready(self: Self): number
	return self._count
end

-- Whether a worker is one of the pool's, each ready from the start
function StandIn.isReady(self: Self, worker: number): boolean
	return worker >= 1 and worker <= self._count
end

-- Queues a round for a worker with copies of its hand-ins, which deliver runs
function StandIn.send(self: Self, worker: number, round: number, shared: buffer, own: buffer)
	table.insert(self._queue, { worker = worker, round = round, shared = copyBuffer(shared), own = copyBuffer(own) })
end

--[[
    Runs every round queued, in the order sent, each its worker's Remote.run
    timed by os.clock(), keeping a copy of its result or the text of what
    it threw, and a copy of any clocks it gave, landed as it finished
--]]

function StandIn.deliver(self: Self)
	local queue: { Round } = self._queue
	self._queue = {}

	for _, round: Round in queue do
		local worker: number = round.worker
		local remote: any = self._remotes[worker]

		local start: number = os.clock()
		local ran: boolean, value: any, clocks: any = pcall(remote.run, round.shared, round.own)
		local finish: number = os.clock()

		self._rounds[worker] = round.round
		self._starts[worker] = start
		self._finishes[worker] = finish
		self._clocks[worker] = nil
		self._landed[worker] = 0

		if ran then
			self._results[worker] = copyBuffer(value)
			self._failures[worker] = nil
		else
			self._results[worker] = nil
			self._failures[worker] = `{value}`
		end

		if ran and clocks ~= nil then
			self._clocks[worker] = copyBuffer(clocks)
			self._landed[worker] = finish
		end
	end
end

--[[
    Nothing until a worker's round is delivered, then its result, or the
    text of what its Remote.run threw
--]]

function StandIn.landed(self: Self, worker: number, round: number): (buffer?, string?)
	if self._rounds[worker] ~= round then
		return nil, nil
	end

	return self._results[worker], self._failures[worker]
end

--[[
    When a worker's last delivered run began and ended, by os.clock(), then
    a copy of its clocks, nil for none, when it landed, and the seconds its
    fire took, as the pool gives them
--]]

function StandIn.times(self: Self, worker: number): (number, number, buffer?, number, number)
	return self._starts[worker], self._finishes[worker], self._clocks[worker], self._landed[worker], FIRED
end

-- Drops every worker and every round still queued
function StandIn.destroy(self: Self)
	table.clear(self._remotes)
	table.clear(self._queue)
end

export type StandIn = Self
type Self = typeof(setmetatable({} :: Fields, StandIn))

return StandIn
