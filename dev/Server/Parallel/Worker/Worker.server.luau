--[[
    One of the parallel probe's workers, run in a clone of its Actor: on each
    batch it desynchronizes, runs the loop, and stamps its start and finish
    into the batch's marks table, its round last
--]]

--!strict
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
local base: number = (index - 1) * Work.FIELDS
local data: buffer = buffer.create(BYTES) -- This worker's own, since a buffer can't be shared between Actor VMs

-- The Actor owns the binding, and the pool destroying it releases it
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

actor:SetAttribute(Work.BOUND, true)
