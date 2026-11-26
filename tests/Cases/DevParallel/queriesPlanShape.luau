--[[
    The probe's plan: slots times 56 times 4 records, kind by kind and slot by
    slot, the same bytes twice, each kind restarting the generator so every
    kind casts the same shapes, and near queries off the face by each gap
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")

local SEED: number = 362436069
local RADII: { number } = { 0.5, 1.25 }
local HULL_HALF: { number } = { 1.5, 2.5, 1.5 } -- Half the hull the case plans with, 3 by 5 by 3
local SLOTS: number = 2
local PER_SLOT: number = 56 -- 16 aimed, 16 grazing and 24 near
local KINDS: number = 4 -- ray, sweep, sphere and rest
local WIDTH: number = 8 -- A query's values
local F64_BYTES: number = 8
local RECORDS: number = SLOTS * PER_SLOT * KINDS -- 448
local KIND: number = 0 -- Each value's place in a query, from 0
local ORIGIN: number = 1
local DIRECTION: number = 4
local RADIUS: number = 7
local AXES: number = 3
local AIMED: number = 16
local NEAR_FIRST: number = 33 -- The first near query of a slot
local NEAR_GAPS: { number } = { 0.0005, 0.002, 0.005, 0.01, 0.02, 0.05 }
local AIM_BACK: number = 20 -- Studs an aimed query starts from its target
local AIM_REACH: number = 40
local AIM_SPREAD: number = 1.2
local NEAR_SPREAD: number = 0.9
local SLACK: number = 1e-9 -- Room for the rounding of a sum taken apart again
local RAY: number = 1
local SWEEP: number = 2
local SPHERE: number = 3
local REST: number = 4

-- The two slots, each axis aligned so a face's normal is one axis
local CENTERS: { { number } } = { { 10, 20, 30 }, { -40, 12, 25 } }
local SIZES: { { number } } = { { 4, 6, 8 }, { 2, 10, 6 } }

local function value(plan: buffer, record: number, field: number): number
	return buffer.readf64(plan, (record * WIDTH + field) * F64_BYTES)
end

-- The record of a kind's query on a slot, from 0, each kind's records following the last's, slot by slot
local function recordOf(kind: number, slot: number, query: number): number
	return ((kind - 1) * SLOTS + (slot - 1)) * PER_SLOT + (query - 1)
end

-- How far a kind's shape reaches along an axis: nothing for a ray, its radius for a sphere, the hull for a box
local function extent(kind: number, axis: number, query: number): number
	if kind == RAY then
		return 0
	elseif kind == SPHERE then
		return RADII[query % #RADII + 1]
	end

	return HULL_HALF[axis]
end

-- Each record's kind in order, only a sphere's radius kept, and no direction on a rest
local function fields(plan: buffer): string?
	for record: number = 0, RECORDS - 1 do
		local kind: number = record // (SLOTS * PER_SLOT) + 1
		local query: number = record % PER_SLOT + 1
		local radius: number = kind == SPHERE and RADII[query % #RADII + 1] or 0

		if value(plan, record, KIND) ~= kind then
			return `Record {record + 1} holds kind {value(plan, record, KIND)}, not {kind}`
		elseif value(plan, record, RADIUS) ~= radius then
			return `Record {record + 1} of kind {kind} holds radius {value(plan, record, RADIUS)}, not {radius}`
		end

		for axis: number = 0, AXES - 1 do
			if kind == REST and value(plan, record, DIRECTION + axis) ~= 0 then
				return `Rest record {record + 1} holds a direction`
			end
		end
	end

	return nil
end

-- An aimed query alike in every kind, starting 20 studs back from a target inside its box's faces spread by 1.2
local function aimed(plan: buffer, slot: number, query: number): string?
	local ray: number = recordOf(RAY, slot, query)
	for kind: number = SWEEP, SPHERE do
		for field: number = ORIGIN, DIRECTION + AXES - 1 do
			if value(plan, recordOf(kind, slot, query), field) ~= value(plan, ray, field) then
				return `Slot {slot} aimed query {query} of kind {kind} differs from its ray in value {field}`
			end
		end
	end

	local length: number = 0
	for axis: number = 1, AXES do
		local toward: number = value(plan, ray, DIRECTION + axis - 1)
		local target: number = value(plan, ray, ORIGIN + axis - 1) + toward * AIM_BACK / AIM_REACH
		length += toward * toward

		if math.abs(target - CENTERS[slot][axis]) > SIZES[slot][axis] / 2 * AIM_SPREAD + SLACK then
			return `Slot {slot} aimed query {query} aims outside its box on axis {axis}`
		end
	end

	if math.abs(math.sqrt(length) - AIM_REACH) > SLACK then
		return `Slot {slot} aimed query {query} reaches {math.sqrt(length)} studs, not {AIM_REACH}`
	end

	return nil
end

-- A near query of each kind starting its gap off one face, lifted by the kind's extent, and inside the face's spread
local function near(plan: buffer, slot: number, query: number): string?
	local gap: number = NEAR_GAPS[(query - NEAR_FIRST) % #NEAR_GAPS + 1]

	for kind: number = RAY, REST do
		local record: number = recordOf(kind, slot, query)
		local off: number = 0

		for axis: number = 1, AXES do
			local center: number = CENTERS[slot][axis]
			local half: number = SIZES[slot][axis] / 2
			local at: number = value(plan, record, ORIGIN + axis - 1)
			local lift: number = half + extent(kind, axis, query)

			if at == center + (lift + gap) or at == center - (lift + gap) then
				off += 1
			elseif math.abs(at - center) > half * NEAR_SPREAD + SLACK then
				return `Slot {slot} near query {query} of kind {kind} starts outside its face on axis {axis}`
			end
		end

		if off ~= 1 then
			return `Slot {slot} near query {query} of kind {kind} starts {gap} off {off} faces, not 1`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local loaded: any = Harness.load()
	local Queries: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Parallel.Queries)

	local parts: { any } = {}
	for slot: number = 1, SLOTS do
		local center: { number } = CENTERS[slot]
		local size: { number } = SIZES[slot]
		local part: any = roblox.Instance.new("Part")
		part.Size = roblox.Vector3.new(size[1], size[2], size[3])
		part.CFrame = roblox.CFrame.new(center[1], center[2], center[3])
		table.insert(parts, part)
	end

	local hull: any = roblox.Vector3.new(HULL_HALF[1] * 2, HULL_HALF[2] * 2, HULL_HALF[3] * 2)
	local plan: buffer = Queries.plan(parts, hull, RADII, SEED)

	-- 1) One record a query of every kind on every slot, and the same bytes from the same inputs
	if buffer.len(plan) ~= RECORDS * WIDTH * F64_BYTES then
		return false, `The plan holds {buffer.len(plan)} B, not {RECORDS} records of {WIDTH * F64_BYTES} B`
	end

	if buffer.tostring(Queries.plan(parts, hull, RADII, SEED)) ~= buffer.tostring(plan) then
		return false, "Two plans from the same inputs differ"
	end

	-- 2) Kind by kind in order, a rest with no direction, and only a sphere keeping the radius its query cycles to
	local problem: string? = fields(plan)
	if problem then
		return false, problem
	end

	for slot: number = 1, SLOTS do
		for query: number = 1, PER_SLOT do
			-- 3) Every kind draws the same numbers from the seed, so a rest starts where a sweep does
			local sweep: number = recordOf(SWEEP, slot, query)
			local rest: number = recordOf(REST, slot, query)
			for field: number = ORIGIN, ORIGIN + AXES - 1 do
				if value(plan, rest, field) ~= value(plan, sweep, field) then
					return false, `Slot {slot} query {query}'s rest starts off its sweep's start in value {field}`
				end
			end

			-- 4) And an aimed query is the same in every kind, and a near one sits its gap off a face
			if query <= AIMED then
				problem = aimed(plan, slot, query)
			elseif query >= NEAR_FIRST then
				problem = near(plan, slot, query)
			end

			if problem then
				return false, problem
			end
		end
	end

	return true, nil
end
