--[[
    The relay's Actor workers: clones of the worker template in a folder
    under ServerScriptService, each sent its setup once it reports bound,
    then a round at a time, each round's result read back by its event
--]]

--!strict
local Pool = {}
Pool.__index = Pool

local ServerScriptService = game:GetService("ServerScriptService")

local Layout = require(script.Parent.Worker.Layout)

local Template = script.Parent.Worker -- The Actor every worker is cloned from, which never works itself

local READY_SECONDS: number = 10 -- How long the workers have to report ready before the pool warns once

type Fields = {
	_folder: Folder,
	_actors: { Actor },
	_connections: { RBXScriptConnection },
	_count: number,
	_remote: ModuleScript, -- What each worker requires in its setup
	_settings: unknown, -- And hands Remote.setup, which the pool never opens
	_setUp: { boolean }, -- Whether each worker was sent its setup
	_ready: { boolean },
	_readyCount: number,
	_started: number, -- os.clock() when the pool was made
	_warned: boolean,
	_rounds: { number }, -- The round each worker's event last fired with
	_results: { [number]: buffer? }, -- And its result, or its failure's text
	_failures: { [number]: string? },
	_starts: { number }, -- And when that run began and ended, by the worker's own os.clock()
	_finishes: { number },
}

--[[
    Clones count workers into a folder named name under
    ServerScriptService, each with its index and its own BindableEvent.
    Each worker is set up with remote and settings once ready finds it bound
--]]

function Pool.new(count: number, name: string, remote: ModuleScript, settings: unknown): Self
	local folder: Folder = Instance.new("Folder")
	folder.Name = name

	local self: Self = setmetatable({
		_folder = folder,
		_actors = {} :: { Actor },
		_connections = {} :: { RBXScriptConnection },
		_count = count,
		_remote = remote,
		_settings = settings,
		_setUp = table.create(count, false),
		_ready = table.create(count, false),
		_readyCount = 0,
		_started = os.clock(),
		_warned = false,
		_rounds = table.create(count, 0),
		_results = {} :: { [number]: buffer? },
		_failures = {} :: { [number]: string? },
		_starts = table.create(count, 0),
		_finishes = table.create(count, 0),
	}, Pool)

	for index: number = 1, count do
		local actor: Actor = Template:Clone()
		actor.Name = `Worker{index}`
		actor:SetAttribute(Layout.WORKER, index)

		-- Whiteoak TODO: the event is the only return path; if G0's numbers pick the SharedTable, each worker writes
		-- its result into its own keys of one shared table that landed reads, as anti-ESP's Actor arm does
		local event: BindableEvent = Instance.new("BindableEvent")
		event.Parent = actor

		-- Released in destroy
		table.insert(
			self._connections,
			event.Event:Connect(
				function (round: number, result: buffer?, failure: string?, start: number, finish: number)
					self._rounds[index] = round
					self._results[index] = result
					self._failures[index] = failure
					self._starts[index] = start
					self._finishes[index] = finish
				end
			)
		)

		actor.Parent = folder
		table.insert(self._actors, actor)
	end

	-- Parented last, so every worker finds its index and its event when its script starts
	folder.Parent = ServerScriptService

	return self
end

--[[
    How many workers are ready, polling each one not yet ready without
    waiting: one newly bound is sent its setup, and one whose setup has run
    counts from then on. Once READY_SECONDS have passed with any still
    unready it warns, once
--]]

function Pool.ready(self: Self): number
	if self._readyCount == self._count then
		return self._readyCount
	end

	for index: number, actor: Actor in self._actors do
		if self._ready[index] then
			continue
		end

		if not self._setUp[index] then
			if actor:GetAttribute(Layout.BOUND) == true then
				self._setUp[index] = true
				actor:SendMessage(Layout.SETUP, self._remote, self._settings)
			end
		elseif actor:GetAttribute(Layout.READY) == true then
			self._ready[index] = true
			self._readyCount += 1
		end
	end

	if not self._warned and self._readyCount < self._count and os.clock() - self._started >= READY_SECONDS then
		self._warned = true

		local ready: string = `Only {self._readyCount} of the relay's {self._count} workers`
		warn(`{ready} were ready after {READY_SECONDS} s, so it goes on with those`)
	end

	return self._readyCount
end

-- Whether one worker has loaded Remote and run its setup
function Pool.isReady(self: Self, worker: number): boolean
	return self._ready[worker] == true
end

--[[
    Sends one worker a round's hand-in, the buffer every worker shares and
    its own, whose result or failure landed answers once it is in
--]]

function Pool.send(self: Self, worker: number, round: number, shared: buffer, own: buffer)
	self._actors[worker]:SendMessage(Layout.RUN, round, shared, own)
end

--[[
    Nothing until a worker's round lands, then its result, or the text of
    the failure that stopped it: a throw out of Remote.run, or a round sent
    before its setup
--]]

function Pool.landed(self: Self, worker: number, round: number): (buffer?, string?)
	if self._rounds[worker] ~= round then
		return nil, nil
	end

	return self._results[worker], self._failures[worker]
end

-- When a worker's last landed run began and ended, by its own os.clock()
function Pool.times(self: Self, worker: number): (number, number)
	return self._starts[worker], self._finishes[worker]
end

--[[
    Releases every event connection and destroys the folder, which ends
    each worker's script and the bindings its Actor holds
--]]

function Pool.destroy(self: Self)
	for _, connection: RBXScriptConnection in self._connections do
		connection:Disconnect()
	end

	table.clear(self._connections)
	table.clear(self._actors)
	self._folder:Destroy()
end

export type Pool = Self
type Self = typeof(setmetatable({} :: Fields, Pool))

return Pool
