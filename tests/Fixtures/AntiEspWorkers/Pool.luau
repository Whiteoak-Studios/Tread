--[[
    A stand-in for anti-ESP's Actor pool in Lune, which has no Actors: the
    relay pool's members, each batch copied as a message copies it and cast
    at once with Casts.cast through a case's wall, landing unless it is held
--]]

--!strict
local Pool = {}
Pool.__index = Pool

local Environment = require("../../Environment")

local CASTS: string = "src/Server/AntiEspWorkers/Casts.luau"
local FIRED: number = 0 -- Seconds a batch's fire takes, since a stand-in fires nothing

local Casts: any = Environment.load(CASTS)

type Wall = (origin: vector, direction: vector) -> boolean

-- One ray a worker cast, with where it ends
export type Ray = {
	worker: number,
	origin: vector,
	direction: vector,
	to: vector,
}

-- One batch a worker was sent, a copy of its bytes
export type Send = {
	worker: number,
	round: number,
	pairs: number,
	batch: buffer,
}

type Fields = {
	count: number,
	name: string, -- The folder an Actor pool would make
	remote: any, -- The ModuleScript each worker would load
	settings: any, -- What each worker's setup would be handed, as it was handed
	setup: any, -- A copy of the settings as the first ready sent them, nil until then, when no worker is ready
	wall: Wall, -- What each ray meets, true for an occluder
	readyCount: number, -- The first this many workers are ready, every one unless a case lowers it
	held: { [number]: boolean }, -- The workers whose batch out a case keeps from landing
	failing: { [number]: string }, -- The workers whose next batch lands as this failure text
	busy: { [number]: number }, -- Seconds each worker's batches report they took
	rays: { Ray }, -- Every ray cast since a case last cleared the list
	occluded: number, -- The rays cast through the occluder query, which asks what a ray met, since the pool was made
	sends: { Send }, -- Every batch sent since a case last cleared the list
	destroyed: boolean,
	_out: { [number]: boolean }, -- Whether a worker's batch has yet to land
	_rounds: { [number]: number }, -- The round each worker was last sent
	_results: { [number]: buffer? }, -- And its results, or its failure's text
	_failures: { [number]: string? },
}

-- Walls nowhere
local function open(_: vector, _: vector): boolean
	return false
end

-- A copy of a buffer, as an Actor message or a BindableEvent carries one
local function copyBuffer(data: buffer): buffer
	local copied: buffer = buffer.create(buffer.len(data))
	buffer.copy(copied, 0, data)

	return copied
end

-- A copy of a value as a message carries it, every table copied and an Instance crossing as itself
local function cross(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local copied: { [any]: any } = {}
	for key: any, inner: any in value do
		copied[key] = cross(inner)
	end

	return copied
end

--[[
    A pool as anti-ESP makes one, with no walls, its workers ready only once
    a call to ready has sent their setup, as an Actor pool's are, taking
    Instances across as a live setup does
--]]

function Pool.new(count: number, name: string, remote: any, settings: any): Self
	return setmetatable({
		count = count,
		name = name,
		remote = remote,
		settings = settings,
		setup = nil :: any,
		wall = open :: Wall,
		readyCount = count,
		held = {} :: { [number]: boolean },
		failing = {} :: { [number]: string },
		busy = {} :: { [number]: number },
		rays = {} :: { Ray },
		occluded = 0,
		sends = {} :: { Send },
		destroyed = false,
		_out = {} :: { [number]: boolean },
		_rounds = {} :: { [number]: number },
		_results = {} :: { [number]: buffer? },
		_failures = {} :: { [number]: string? },
	}, Pool)
end

--[[
    What a case hands the environment in place of RelayWorkers.Pool: its
    new makes a stand-in and keeps the one made last as made
--]]

function Pool.override(): { [string]: any }
	local override: { [string]: any } = {}

	function override.new(count: number, name: string, remote: any, settings: any): Self
		local made: Self = Pool.new(count, name, remote, settings)
		override.made = made

		return made
	end

	return override
end

-- How many workers are ready, sending every worker its setup at the first call, the first readyCount ready from then
function Pool.ready(self: Self): number
	if self.setup == nil then
		self.setup = cross(self.settings)
	end

	return math.min(self.readyCount, self.count)
end

-- Whether a worker is ready, never before a call to ready has sent the setup
function Pool.isReady(self: Self, worker: number): boolean
	return self.setup ~= nil and worker >= 1 and worker <= math.min(self.readyCount, self.count)
end

--[[
    Takes a batch for a worker and casts a copy of it at once through the
    wall with Casts.cast, logging each ray, or keeps the failure text a case
    set for it. It errors on a worker not ready and one whose last batch is
    still out
--]]

function Pool.send(self: Self, worker: number, round: number, _: buffer, own: buffer)
	if not self:isReady(worker) then
		error(`Worker {worker} was sent a batch while it was not ready`)
	elseif self._out[worker] then
		error(`Worker {worker} was sent a batch while its last one was still out`)
	end

	local batch: buffer = copyBuffer(own)
	table.insert(self.sends, { worker = worker, round = round, pairs = buffer.readu32(batch, 0), batch = batch })

	self._out[worker] = true
	self._rounds[worker] = round
	self._results[worker] = nil
	self._failures[worker] = nil

	local failure: string? = self.failing[worker]
	if failure ~= nil then
		self.failing[worker] = nil
		self._failures[worker] = failure

		return
	end

	local function logged(origin: vector, direction: vector): boolean
		table.insert(self.rays, { worker = worker, origin = origin, direction = direction, to = origin + direction })

		return self.wall(origin, direction)
	end

	-- The same ray logged, and counted apart, as a learner's ask of what its first ray met
	local function occluder(origin: vector, direction: vector): any
		self.occluded += 1

		return logged(origin, direction)
	end

	self._results[worker] = copyBuffer(Casts.cast(logged, occluder, batch))
end

--[[
    Nothing while a case holds the worker's batch or for any other round,
    then its results, or the failure text a case set
--]]

function Pool.landed(self: Self, worker: number, round: number): (buffer?, string?)
	if self.held[worker] or self._rounds[worker] ~= round then
		return nil, nil
	end

	self._out[worker] = false

	return self._results[worker], self._failures[worker]
end

-- When a worker's batch began and ended, as the busy time a case set, then no clocks, as the pool gives them
function Pool.times(self: Self, worker: number): (number, number, buffer?, number, number)
	return 0, self.busy[worker] or 0, nil, 0, FIRED
end

function Pool.destroy(self: Self)
	self.destroyed = true
end

export type Pool = Self
type Self = typeof(setmetatable({} :: Fields, Pool))

return Pool
