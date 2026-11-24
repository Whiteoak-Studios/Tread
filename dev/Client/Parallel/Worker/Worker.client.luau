--[[
    One of the client probes' workers, run in a clone of its Actor: it spins
    P6's batches, holds in P6's landing callbacks and bends P8's stand-ins'
    legs, stamping each, and hands an arm's samples in once the arm ends
--]]

--!strict
local InterpretedLoop = require(script.Parent.Parent.Parent.InterpretedLoop)
local Work = require(script.Parent.Parent.Work)

local SIGNALS: { [string]: RBXScriptSignal<number> } = Work.signals()

-- The template sits beside its clones with no index, so only a clone the probe parents ever works
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
local data: buffer = buffer.create(0) -- P6's loop buffer, this worker's own, since a buffer can't be shared between Actor VMs
local samples: { number } = {} -- The arm's samples so far, which its end hands in
local connection: RBXScriptConnection? = nil -- The arm's parallel callback, which its end disconnects

-- Ends the arm's callback, so a new arm, or the end of this one, leaves none behind
local function disconnect()
	local made: RBXScriptConnection? = connection
	if made then
		connection = nil
		made:Disconnect()
	end
end

-- The Actor owns every binding below, and the probe destroying it releases them with any callback still connected
actor:BindToMessage(Work.CORES, function (round: number, passes: number, bytes: number, marks: SharedTable)
	if buffer.len(data) ~= bytes then
		data = buffer.create(bytes)
	end

	task.desynchronize()

	local start: number = os.clock()
	InterpretedLoop(data, passes)
	local finish: number = os.clock()

	-- A SharedTable takes writes from a desynchronized thread, and each worker writes only its own keys
	marks[base + Work.START] = start
	marks[base + Work.FINISH] = finish
	marks[base + Work.ROUND] = round
end)

-- A landing arm: each callback on the event holds its thread, reads every counted event's count, synchronizes and
-- reads them again
actor:BindToMessage(Work.LAND, function (event: string, hold: number, counters: SharedTable)
	disconnect()
	table.clear(samples)

	local layout = Work.LANDING
	local names: { string } = Work.EVENTS

	connection = SIGNALS[event]:ConnectParallel(function ()
		local start: number = os.clock()
		Work.busy(hold)
		local spun: number = os.clock()

		local before: { number } = table.create(#names, 0)
		for offset: number, name: string in names do
			before[offset] = counters[name]
		end

		task.synchronize()
		local synced: number = os.clock()

		local at: number = #samples
		samples[at + layout.START] = start
		samples[at + layout.SPUN] = spun
		samples[at + layout.SYNCED] = synced

		for offset: number, name: string in names do
			samples[at + layout.BEFORE + offset - 1] = before[offset]
			samples[at + layout.AFTER + offset - 1] = counters[name]
		end
	end)
end)

-- A bend arm: each step solves this worker's rigs' legs desynchronized, then synchronizes and writes them
actor:BindToMessage(
	Work.BEND,
	function (rigs: { Model }, names: { [string]: string }, counters: SharedTable, rise: Work.Rise)
		disconnect()
		table.clear(samples)

		local layout = Work.BENDING
		local set: Work.Set = Work.set(rigs, names)

		connection = SIGNALS.PreSimulation:ConnectParallel(function ()
			local start: number = os.clock()
			local before: number = counters[Work.STEPPED]
			local step: number = before + 1

			Work.solve(set, Work.height(rise, step))
			local solved: number = os.clock()

			task.synchronize()
			local synced: number = os.clock()
			local after: number = counters[Work.STEPPED]

			Work.write(set)
			local written: number = os.clock()

			local at: number = #samples
			samples[at + layout.STEP] = step
			samples[at + layout.START] = start
			samples[at + layout.SOLVED] = solved
			samples[at + layout.SYNCED] = synced
			samples[at + layout.WRITTEN] = written
			samples[at + layout.BEFORE] = before
			samples[at + layout.AFTER] = after
		end)

		actor:SetAttribute(Work.ARMED, true)
	end
)

-- An arm's end: its callback gone, then its samples handed in under this worker's index
actor:BindToMessage(Work.STOP, function (results: SharedTable)
	disconnect()
	actor:SetAttribute(Work.ARMED, nil)

	results[worker] = SharedTable.new(samples)
	table.clear(samples)
end)

actor:SetAttribute(Work.BOUND, true)
