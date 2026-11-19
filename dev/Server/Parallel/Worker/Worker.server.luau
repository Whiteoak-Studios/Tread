--[[
    One of the parallel probes' workers, run in a clone of its Actor: it runs
    ParallelProbe's loop and ParallelReturn's rounds, echoes, writes and
    returns, stamping a round's times into its marks table, the round last
--]]

--!strict
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Work = require(ServerScriptService.Server.Parallel.Work)

local BYTES: number = require(ServerScriptService.Server.Config.Parallel).bytes

-- The template sits in the dev server's Parallel folder with no index, so only a clone the pool parents ever works
local found: Actor? = script:GetActor()
if not found then
	return
end

local index: unknown = found:GetAttribute(Work.WORKER)
if type(index) ~= "number" then
	return
end

local actor: Actor = found
local worker: number = index
local base: number = (index - 1) * Work.FIELDS
local data: buffer = buffer.create(BYTES) -- This worker's own, since a buffer can't be shared between Actor VMs

-- The error a SharedTable's refused write threw, nil when the write took
local function stored(store: SharedTable, key: string, value: any): string?
	local wrote: boolean, failure: any = pcall(function ()
		store[key] = value
	end)

	if wrote then
		return nil
	end

	return `{failure}`
end

-- The Actor owns every binding below, and the pool destroying it releases them
actor:BindToMessage(Work.TOPIC, function (round: number, passes: number, marks: SharedTable)
	task.desynchronize()

	local start: number = os.clock()
	Work.spin(data, passes)
	local finish: number = os.clock()

	-- A SharedTable takes writes from a desynchronized thread, and each worker writes only its own keys
	marks[base + Work.START] = start
	marks[base + Work.FINISH] = finish
	marks[base + Work.ROUND] = round
end)

-- P1: the round stamped, spun and stamped, fired back through this worker's event, then marked
actor:BindToMessageParallel(Work.TIMING, function (round: number, spin: number, event: BindableEvent, marks: SharedTable)
	local start: number = os.clock()
	Work.busy(spin)
	local finish: number = os.clock()

	event:Fire(worker, round, start, finish)
	marks[base + Work.ROUND] = round
end)

-- P1's arm: each Heartbeat's parallel callback reads the main thread's frame, synchronizes and fires back the frame it
-- reads then. Its connection ends with this script when the pool destroys the clone
actor:BindToMessage(Work.ARM, function (event: BindableEvent, marks: SharedTable)
	RunService.Heartbeat:ConnectParallel(function ()
		local parallel: number = os.clock()
		local frame: number = marks[Work.FRAME]

		task.synchronize()
		event:Fire(parallel, frame, marks[Work.FRAME])
	end)
end)

-- P4: the value described as it arrived, a buffer marked so the main thread can tell a copy, then fired back
actor:BindToMessageParallel(Work.ECHO, function (label: string, event: BindableEvent, value: any)
	local arrived: string = Work.describe(value)
	if type(value) == "buffer" and buffer.len(value) > 0 then
		buffer.writeu8(value, 0, Work.MARK)
	end

	-- A value the event refuses comes back as the refusal
	local fired: boolean, failure: any = pcall(function ()
		event:Fire(label, arrived, nil, value)
	end)

	if not fired then
		event:Fire(label, arrived, `{failure}`)
	end
end)

-- P4: a buffer and a string written into the SharedTable from this desynchronized worker, each refusal fired back
actor:BindToMessageParallel(Work.STORE, function (event: BindableEvent, store: SharedTable, bytes: number)
	local bufferFailure: string? = stored(store, Work.BUFFER, buffer.create(bytes))
	local textFailure: string? = stored(store, Work.TEXT, string.rep(Work.FILL, bytes))

	event:Fire(bufferFailure, textFailure)
end)

-- P5: when a send's message began here
actor:BindToMessageParallel(Work.SEND, function (round: number, marks: SharedTable)
	marks[base + Work.START] = os.clock()
	marks[base + Work.ROUND] = round
end)

-- P5: a payload of that many bytes fired back, the Fire timed
actor:BindToMessageParallel(
	Work.RETURN,
	function (round: number, bytes: number, event: BindableEvent, marks: SharedTable)
		local payload: buffer = buffer.create(bytes)

		local fired: number = os.clock()
		event:Fire(round, fired, payload)
		local finish: number = os.clock()

		marks[base + Work.START] = fired
		marks[base + Work.FINISH] = finish
		marks[base + Work.ROUND] = round
	end
)

-- P5: a string of that many bytes written into the marks table, the write timed
actor:BindToMessageParallel(Work.SHARE, function (round: number, bytes: number, marks: SharedTable)
	local text: string = string.rep(Work.FILL, bytes)

	local wrote: number = os.clock()
	marks[Work.TEXT] = text
	local finish: number = os.clock()

	marks[base + Work.START] = wrote
	marks[base + Work.FINISH] = finish
	marks[base + Work.ROUND] = round
end)

actor:SetAttribute(Work.BOUND, true)
