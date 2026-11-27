--[[
    A step worker, run in a clone of its Actor: it loads the dev shared
    table, its casts and its world at load, then answers P9's check, P2's
    casts, P7's overlaps, P3's battery and P10's bounds, its index first
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Work = require(ServerScriptService.Server.Parallel.Work)

local PIECE_BYTES: number = require(ServerScriptService.Server.Config.Parallel).step.pieceBytes

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

--[[
    One load under its own pcall, its attribute on the Actor set to true or
    to the failure's message, giving what it made, or nil when it failed
--]]

local function attempt<T>(attribute: string, make: () -> T): T?
	local ran: boolean, result: T = pcall(make)
	if not ran then
		actor:SetAttribute(attribute, tostring(result))
		return nil
	end

	actor:SetAttribute(attribute, true)

	return result
end

-- At load and serially, since require can't run desynchronized, each load the main thread reads before the probes
local Shared = attempt(Work.CONFIG, function ()
	return require(ReplicatedStorage.Shared.Dev.Config)
end)

local Engine = attempt(Work.ENGINE, function ()
	return require(ReplicatedStorage.Packages.Tread.Step.Engine)
end)

local World = attempt(Work.WORLD, function ()
	return require(ReplicatedStorage.Packages.Tread.Step.World)
end)

local Builtins = attempt(Work.BUILTINS, function ()
	return require(ServerScriptService.Server.Parallel.Builtins)
end)

local Queries = attempt(Work.QUERIES, function ()
	return require(ServerScriptService.Server.Parallel.Queries)
end)

-- What an earlier load made, or an error naming that load when it failed
local function needs<T>(made: T?, attribute: string): T
	if made == nil then
		error(`it needs {attribute}, which failed`, 0)
	end

	return made
end

-- The casts and the world the server builds at its start, each from this worker's own copy of the shared table
local casts = attempt(Work.CASTS, function ()
	return needs(Engine, Work.ENGINE).casts(needs(Shared, Work.CONFIG).collision)
end)

attempt(Work.WORLD_BUILT, function ()
	local shared = needs(Shared, Work.CONFIG)
	local collision = needs(casts, Work.CASTS)

	return needs(World, Work.WORLD).new(
		shared.step,
		shared.rates.simulation,
		collision,
		shared.water,
		shared.rules,
		true
	)
end)

-- A part of this worker's own under its Actor, made as Engine makes its probe: anchored, out of every query and touch
local function newPart(): Part
	local part: Part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Parent = actor

	return part
end

local probe: Part = newPart() -- P7's, which each box is written into
local battery: Part = newPart() -- P3's, whose CFrame the battery writes

-- P7's filter, made as Engine's probe makes its own: the shared table's include list, or every part but the probe
local params: OverlapParams = OverlapParams.new()
params.RespectCanCollide = true

local include: { Instance }? = nil
if Shared then
	include = Shared.collision.include
end

if include then
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
else
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { probe }
end

-- P7's query on one box: the probe's Size written, then its CFrame from the center alone, as Engine writes its own
local function overlap(center: vector, size: vector): boolean
	probe.Size = Vector3.new(size.x, size.y, size.z)
	probe.CFrame = CFrame.new(center.x, center.y, center.z)

	return #Workspace:GetPartsInPart(probe, params) > 0
end

-- P10's query on one box through P7's filter, whose exclude of the probe changes nothing, the probe's CanQuery being off
local function bounds(center: vector, size: vector): boolean
	local box: CFrame = CFrame.new(center.x, center.y, center.z)

	return #Workspace:GetPartBoundsInBox(box, Vector3.new(size.x, size.y, size.z), params) > 0
end

--[[
    P7's arm: the boxes rebuilt from the slots and each answered through
    the probe, the answers fired back, or the error a write or a query threw
--]]

local function answer(event: BindableEvent, slots: { BasePart }, hull: Vector3, count: number, seed: number)
	local ran: boolean, result: unknown = pcall(function (): buffer
		local queries = needs(Queries, Work.QUERIES)

		return queries.overlaps(queries.boxes(slots, hull, count, seed), overlap)
	end)

	if ran then
		event:Fire(worker, result, nil)
	else
		event:Fire(worker, nil, tostring(result))
	end
end

-- The Actor owns every binding below, and the pool destroying it releases them. No handler yields or requires

-- P9: whether this worker's own include list holds the main thread's instances in their order, with both counts
actor:BindToMessage(Work.CHECK, function (event: BindableEvent, sent: { Instance })
	if not Shared then
		event:Fire(worker, false, 0, #sent, `it needs {Work.CONFIG}, which failed`)
		return
	end

	local own: { Instance } = Shared.collision.include or {}
	local same: boolean = #own == #sent
	for place: number, instance: Instance in own do
		if sent[place] ~= instance then
			same = false
		end
	end

	event:Fire(worker, same, #own, #sent, nil)
end)

--[[
    P2: the plan rebuilt and hashed, the plan cast through this worker's
    casts with the cast alone timed, and the results fired back in pieces of
    at most PIECE_BYTES, each its own exact length after its offset, then a
    closing fire with the total bytes, the plan's hash and the cast's time
--]]

actor:BindToMessageParallel(
	Work.CAST,
	function (
		pieces: BindableEvent,
		done: BindableEvent,
		slots: { BasePart },
		parts: { BasePart },
		hull: Vector3,
		radii: { number },
		seed: number
	)
		local ran: boolean, failure: unknown = pcall(function ()
			local queries = needs(Queries, Work.QUERIES)
			local collision = needs(casts, Work.CASTS)

			local plan: buffer = queries.plan(slots, hull, radii, seed)
			local hash: number = queries.hash(plan)
			local places: { [Instance]: number } = queries.indexOf(parts)

			local began: number = os.clock()
			local results: buffer = queries.cast(plan, hull, collision, places)
			local seconds: number = os.clock() - began
			local total: number = buffer.len(results)

			for offset: number = 0, total - 1, PIECE_BYTES do
				local length: number = math.min(PIECE_BYTES, total - offset)
				local piece: buffer = buffer.create(length)
				buffer.copy(piece, 0, results, offset, length)
				pieces:Fire(worker, offset, piece)
			end

			done:Fire(worker, total, hash, seconds, nil)
		end)

		if not ran then
			done:Fire(worker, 0, 0, 0, tostring(failure))
		end
	end
)

-- P7: one arm in a serial handler, which tells a probe outside the Workspace from a write refused in parallel
actor:BindToMessage(Work.OVERLAP, answer)
actor:BindToMessageParallel(Work.OVERLAP_PARALLEL, answer)

-- P3: the battery run on this worker's part, its result fired back whole, or the error that stopped it
actor:BindToMessageParallel(Work.BATTERY, function (event: BindableEvent)
	local ran: boolean, result: unknown = pcall(function ()
		return needs(Builtins, Work.BUILTINS).run(battery)
	end)

	if ran then
		event:Fire(worker, result, nil)
	else
		event:Fire(worker, nil, tostring(result))
	end
end)

--[[
    P10: P7's boxes rebuilt from the slots, the boxes sent joined after
    them, and each answered through the bounds query, the answers fired
    back with the first box's place, or the error that stopped them
--]]

actor:BindToMessageParallel(
	Work.BOUNDS,
	function (
		event: BindableEvent,
		at: number,
		slots: { BasePart },
		hull: Vector3,
		count: number,
		seed: number,
		sent: buffer
	)
		local ran: boolean, result: unknown = pcall(function (): buffer
			local queries = needs(Queries, Work.QUERIES)
			local rebuilt: buffer = queries.boxes(slots, hull, count, seed)
			local boxes: buffer = buffer.create(buffer.len(rebuilt) + buffer.len(sent))
			buffer.copy(boxes, 0, rebuilt)
			buffer.copy(boxes, buffer.len(rebuilt), sent)

			return queries.overlaps(boxes, bounds)
		end)

		if ran then
			event:Fire(worker, at, result, nil)
		else
			event:Fire(worker, at, nil, tostring(result))
		end
	end
)

actor:SetAttribute(Work.BOUND, true)
