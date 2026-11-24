--[[
    What anti-ESP's Actor workers load: the batch, result and box layouts
    both sides read and write, the setup that builds a worker's own casts,
    and the loop that casts each pair's rays until its first open one
--]]

--!strict
--!native
local Engine = require(script.Parent.Parent.Parent.Step.Engine)

local HEADER_BYTES: number = 4 -- A batch's u32 count of pairs, ahead of them
local PAIR_BYTES: number = 1 -- A pair's u8 count of rays, ahead of them, with LEARNS set when it may learn a box
local AXIS_BYTES: number = 4 -- An f32, which holds a vector's component exactly
local RAY_BYTES: number = 6 * AXIS_BYTES -- A ray's origin, then its direction
local RESULT_BYTES: number = 1 -- A pair's u8 result: 0 with every ray blocked, else its open ray's place from 1
local BLOCKED: number = 0
local LEARNS: number = 0x80 -- A pair's count byte's flag for a learner, and its result's for a box sent back
local PLACES: number = 0x7F -- The count's bits of a count byte, and the open ray's place's of a result
local BOX_BYTES: number = 15 * AXIS_BYTES -- A box's center, right, up and look axes and half-size
local AXES_AT: number = 3 * AXIS_BYTES -- Where a box's axes start, each three f32s
local HALVES_AT: number = 12 * AXIS_BYTES -- And its half-size along each of them
local GROWTH: number = 2 -- How many times larger the learned boxes' room grows once a batch outgrows it

-- How far a kept box is shrunk, and how far its origin must sit outside it, past the f32 rounding of positions and
-- axes at the play bound, so a segment the test passes meets the part on the engine too
local INSET: number = 1 / 64

-- What a ray met: the instance, or whether it met anything
export type Met = Instance | boolean | nil

-- A ray's test from an origin along a direction: whether it met an occluder, and what it met
export type Blocked = (origin: vector, direction: vector) -> boolean
export type Query = (origin: vector, direction: vector) -> Met

-- What a worker's setup is handed, which crosses into its VM in a message
export type Settings = {
	include: { Instance },
}

-- This worker's own casts, built in its setup, so no RaycastParams crosses a VM
local Occlusion: Blocked? = nil
local Occluder: Query? = nil

local Learned: buffer = buffer.create(0) -- The boxes one batch's cast learned, in its pairs' order, reused

local Casts = {
	HEADER_BYTES = HEADER_BYTES, -- Where a batch's first pair starts
	RESULT_BYTES = RESULT_BYTES,
	BOX_BYTES = BOX_BYTES,
	INSET = INSET, -- Which the dev place's box check grazes
}

-- The bytes one pair of count rays takes in a batch
function Casts.pairSize(count: number): number
	return PAIR_BYTES + count * RAY_BYTES
end

--[[
    Writes one pair's first count rays at a byte offset of a batch, its
    count and then each ray's origin and the direction from it to its end,
    and gives the offset after them. A pair that learns has its worker send
    back the box of what blocked it, when that was a Block part
--]]

function Casts.writePair(
	batch: buffer,
	at: number,
	count: number,
	origins: { vector },
	ends: { vector },
	learn: boolean?
): number
	local head: number = count
	if learn then
		head = bit32.bor(count, LEARNS)
	end

	buffer.writeu8(batch, at, head)

	local ray: number = at + PAIR_BYTES
	for index: number = 1, count do
		local origin: vector = origins[index]
		local direction: vector = ends[index] - origin

		buffer.writef32(batch, ray, origin.x)
		buffer.writef32(batch, ray + AXIS_BYTES, origin.y)
		buffer.writef32(batch, ray + 2 * AXIS_BYTES, origin.z)
		buffer.writef32(batch, ray + 3 * AXIS_BYTES, direction.x)
		buffer.writef32(batch, ray + 4 * AXIS_BYTES, direction.y)
		buffer.writef32(batch, ray + 5 * AXIS_BYTES, direction.z)
		ray += RAY_BYTES
	end

	return ray
end

-- A batch to send: the first size bytes of what was packed, which pairs pairs fill, with its count written ahead
function Casts.batch(packed: buffer, size: number, pairs: number): buffer
	local batch: buffer = buffer.create(size)
	buffer.copy(batch, 0, packed, 0, size)
	buffer.writeu32(batch, 0, pairs)

	return batch
end

-- The result of a batch's pair at its place from 1: 0 with every ray blocked, else its open ray's place from 1
function Casts.opened(results: buffer, place: number): number
	return bit32.band(buffer.readu8(results, (place - 1) * RESULT_BYTES), PLACES)
end

--[[
    Whether a batch's pair at its place from 1 sent back a box, which the
    results hold after every pair's byte, one for each that did in order
--]]

function Casts.boxed(results: buffer, place: number): boolean
	return bit32.btest(buffer.readu8(results, (place - 1) * RESULT_BYTES), LEARNS)
end

-- The part a ray met when it is a Part whose Shape is Block, the one shape a box holds exactly, else nil
function Casts.blocker(met: Instance): Part?
	if met:IsA("Part") and (met :: Part).Shape == Enum.PartType.Block then
		return met :: Part
	end

	return nil
end

--[[
    Writes a Block part's box at a byte offset as f32s: its center, its
    right, up and look axes, and its half-size along each
--]]

function Casts.writeBox(into: buffer, at: number, part: Part)
	local cframe: CFrame = part.CFrame
	local half: Vector3 = part.Size / 2
	local center: Vector3 = cframe.Position
	local right: Vector3 = cframe.RightVector
	local up: Vector3 = cframe.UpVector
	local look: Vector3 = cframe.LookVector

	buffer.writef32(into, at, center.X)
	buffer.writef32(into, at + AXIS_BYTES, center.Y)
	buffer.writef32(into, at + 2 * AXIS_BYTES, center.Z)
	buffer.writef32(into, at + AXES_AT, right.X)
	buffer.writef32(into, at + AXES_AT + AXIS_BYTES, right.Y)
	buffer.writef32(into, at + AXES_AT + 2 * AXIS_BYTES, right.Z)
	buffer.writef32(into, at + AXES_AT + 3 * AXIS_BYTES, up.X)
	buffer.writef32(into, at + AXES_AT + 4 * AXIS_BYTES, up.Y)
	buffer.writef32(into, at + AXES_AT + 5 * AXIS_BYTES, up.Z)
	buffer.writef32(into, at + AXES_AT + 6 * AXIS_BYTES, look.X)
	buffer.writef32(into, at + AXES_AT + 7 * AXIS_BYTES, look.Y)
	buffer.writef32(into, at + AXES_AT + 8 * AXIS_BYTES, look.Z)
	buffer.writef32(into, at + HALVES_AT, half.X)
	buffer.writef32(into, at + HALVES_AT + AXIS_BYTES, half.Y)
	buffer.writef32(into, at + HALVES_AT + 2 * AXIS_BYTES, half.Z)
end

--[[
    Whether the segment from origin to finish crosses the box at a byte
    offset shrunk by INSET on every side, from an origin outside the box
    grown by INSET, so the engine's ray along that segment meets the part
    the box was read from, while it stands as it did then. A segment with
    any part not finite never crosses
--]]

function Casts.crosses(boxes: buffer, at: number, origin: vector, finish: vector): boolean
	local fromX: number = origin.x - buffer.readf32(boxes, at)
	local fromY: number = origin.y - buffer.readf32(boxes, at + AXIS_BYTES)
	local fromZ: number = origin.z - buffer.readf32(boxes, at + 2 * AXIS_BYTES)
	local moveX: number = finish.x - origin.x
	local moveY: number = finish.y - origin.y
	local moveZ: number = finish.z - origin.z
	local enter: number = 0
	local leave: number = 1
	local outside: boolean = false

	-- Each axis's slab, the segment's share inside it narrowing the share inside them all
	for axis: number = 0, 2 do
		local axisAt: number = at + AXES_AT + axis * 3 * AXIS_BYTES
		local x: number = buffer.readf32(boxes, axisAt)
		local y: number = buffer.readf32(boxes, axisAt + AXIS_BYTES)
		local z: number = buffer.readf32(boxes, axisAt + 2 * AXIS_BYTES)
		local half: number = buffer.readf32(boxes, at + HALVES_AT + axis * AXIS_BYTES)
		local inner: number = half - INSET
		local from: number = fromX * x + fromY * y + fromZ * z
		local move: number = moveX * x + moveY * y + moveZ * z

		-- A NaN or infinite end or origin leaves every axis's move NaN or infinite, which no slab settles, so the
		-- engine gets the ray as it does with memory off
		if not (math.abs(move) < math.huge) then
			return false
		end

		if inner < 0 then
			return false
		elseif math.abs(from) > half + INSET then
			outside = true
		end

		if move == 0 then
			if math.abs(from) > inner then
				return false
			end
		else
			local near: number = (-inner - from) / move
			local far: number = (inner - from) / move
			if near > far then
				near, far = far, near
			end

			enter = math.max(enter, near)
			leave = math.min(leave, far)

			if enter > leave then
				return false
			end
		end
	end

	return outside
end

--[[
    Casts each pair of a batch through blocked, its rays in order until the
    first that meets no occluder, and gives a result for each pair. A
    learner's first ray goes through occluder in its place, and a learner
    whose rays were all blocked and whose first ray met a Block part sends
    back that part's box, after every pair's result
--]]

function Casts.cast(blocked: Blocked, occluder: Query, batch: buffer): buffer
	local pairs: number = buffer.readu32(batch, 0)
	local results: buffer = buffer.create(pairs * RESULT_BYTES)
	local at: number = HEADER_BYTES
	local learned: number = 0

	for pair: number = 0, pairs - 1 do
		local head: number = buffer.readu8(batch, at)
		local count: number = bit32.band(head, PLACES)
		local learns: boolean = head ~= count
		local first: number = at + PAIR_BYTES
		local open: number = BLOCKED
		local met: Instance? = nil

		for index: number = 1, count do
			local ray: number = first + (index - 1) * RAY_BYTES
			local origin: vector = vector.create(
				buffer.readf32(batch, ray),
				buffer.readf32(batch, ray + AXIS_BYTES),
				buffer.readf32(batch, ray + 2 * AXIS_BYTES)
			)
			local direction: vector = vector.create(
				buffer.readf32(batch, ray + 3 * AXIS_BYTES),
				buffer.readf32(batch, ray + 4 * AXIS_BYTES),
				buffer.readf32(batch, ray + 5 * AXIS_BYTES)
			)

			-- Only a learner's first ray may give a box, so only it asks what it met
			if learns and index == 1 then
				local hit: Met = occluder(origin, direction)
				if not hit then
					open = index
					break
				elseif typeof(hit) == "Instance" then
					met = hit
				end
			elseif not blocked(origin, direction) then
				open = index
				break
			end
		end

		local result: number = open
		local part: Part? = nil
		if open == BLOCKED and met ~= nil then
			part = Casts.blocker(met)
		end

		if part then
			local size: number = (learned + 1) * BOX_BYTES
			if size > buffer.len(Learned) then
				local grown: buffer = buffer.create(math.max(size, buffer.len(Learned) * GROWTH))
				buffer.copy(grown, 0, Learned, 0, learned * BOX_BYTES)
				Learned = grown
			end

			Casts.writeBox(Learned, learned * BOX_BYTES, part)
			learned += 1
			result = LEARNS
		end

		buffer.writeu8(results, pair * RESULT_BYTES, result)
		at = first + count * RAY_BYTES
	end

	if learned == 0 then
		return results
	end

	-- Every pair's result, then the boxes, one for each result that sent one back
	local whole: buffer = buffer.create(pairs * RESULT_BYTES + learned * BOX_BYTES)
	buffer.copy(whole, 0, results)
	buffer.copy(whole, pairs * RESULT_BYTES, Learned, 0, learned * BOX_BYTES)

	return whole
end

--[[
    A worker's setup, run in the serial phase where require may run: builds
    its own include-list casts from the instances handed across, the test
    and the one that gives what a ray met
--]]

function Casts.setup(settings: Settings)
	Occlusion = Engine.occlusion(settings.include)
	Occluder = Engine.occluder(settings.include)
end

--[[
    A worker's run, desynchronized: casts the batch it was sent, the shared
    buffer beside it unread, and gives the results with no clocks
--]]

function Casts.run(_: buffer, own: buffer): (buffer, buffer?)
	local occlusion: Blocked? = Occlusion
	local occluder: Query? = Occluder
	if not occlusion or not occluder then
		error("An anti-ESP worker was sent a batch before its setup built its casts")
	end

	return Casts.cast(occlusion, occluder, own), nil
end

return Casts
