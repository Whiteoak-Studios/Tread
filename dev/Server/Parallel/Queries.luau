--[[
    The step-in-parallel probe's queries: slots picked from a part list, the
    parity spike's B4 shapes planned over them for the step's four casts and
    the overlap probe's boxes, kept as raw f64s and compared by their bits
--]]

--!strict
--!native
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local State = require(ReplicatedStorage.Packages.Tread.Step.State)

local RAY: number = 1 -- Each kind's number, its place in Queries.KINDS
local SWEEP: number = 2
local SPHERE: number = 3
local REST: number = 4
local AIMED: number = 16 -- Queries a slot gets in each kind aimed into its box
local GRAZING: number = 16 -- Queries skimming one of its faces
local NEAR: number = 24 -- Queries starting just off one of its faces
local QUERIES_PER_SLOT: number = AIMED + GRAZING + NEAR
local AIM_SPREAD: number = 1.2 -- How far past the box's faces an aimed target may sit, as a share of the box
local AIM_BACK: number = 20 -- Studs an aimed query starts from its target
local AIM_REACH: number = 40
local GRAZE_GAPS: { number } = { 0, 0.001, 0.01, 0.1 } -- Studs above the face a grazing query skims
local GRAZE_SLOPES: { number } = { 0, 0.0001, 0.001, 0.01 } -- How steeply it closes on the face
local GRAZE_MARGIN: number = 4 -- Studs past the box a grazing query starts and ends
local NEAR_GAPS: { number } = { 0.0005, 0.002, 0.005, 0.01, 0.02, 0.05 } -- Studs off the face a near query starts
local NEAR_SPREAD: number = 0.9 -- How far across the face it may start, as a share of the face
local NEAR_TILT: number = 0.2 -- How far its direction may lean from straight into the face
local NEAR_REACH: number = 1
-- Studs a box's nearest point sits off a slot's face, inside it, touching it or clear, at the near queries' gaps
local BOX_GAPS: { number } = { -0.05, -0.02, -0.01, -0.005, -0.002, -0.0005, 0, 0.0005, 0.002, 0.005, 0.01, 0.02, 0.05 }
local MIN_LENGTH: number = 0.001 -- Below this a random direction is replaced by a fixed one
local AXES: number = 3
local SIDES: number = 2 -- A face is on the positive or the negative side of its axis
local HALF: number = 0.5
local ZERO: { number } = { 0, 0, 0 } -- Never written: every helper returns a new table
local UNUSED: number = 0 -- What a record holds in a field its kind leaves unused

local PLAN_WIDTH: number = 8 -- A query's values: its kind's number, origin, direction and sphere radius
local ORIGIN: number = 1 -- Each field's place in its record, from 0
local DIRECTION: number = 4
local RADIUS: number = 7
local RESULT_WIDTH: number = 9 -- A result's values: the hit's index, position, normal, distance and material's Value
local DISTANCE: number = 7
local BOX_WIDTH: number = 6 -- A box's values: its center and size
local SIZE: number = 3
local OVERLAP_WIDTH: number = 1 -- An overlap answer's value
local MISSED: number = 0 -- The index a miss records
local OUTSIDE: number = -1 -- The index of a hit on terrain, on no instance or on a part the index leaves out
local FOUND: number = 1 -- The index field of a rest that found a height, and the answer of a box that overlapped
local RESULT_FIELDS: { string } = {
	"index",
	"position.x",
	"position.y",
	"position.z",
	"normal.x",
	"normal.y",
	"normal.z",
	"distance",
	"material",
}

local F64_BYTES: number = 8
local WORD_BYTES: number = 4
local HIGH_WORD: number = 4 -- The offset of an f64's sign, exponent and top mantissa bits
local MAGNITUDE: number = 0x7FFFFFFF -- An f64's high word without its sign bit
local HEX: string = "%08x%08x" -- An f64's bits, high word first, which interpolation cannot zero-pad
local WORD: number = 4294967296 -- 2^32
local FNV_OFFSET: number = 2166136261
local FNV_SHIFT: number = 24 -- The FNV prime is 2^24 + 403, multiplied in two exact parts
local FNV_LOW: number = 403
local XORSHIFT_LEFT: number = 13
local XORSHIFT_RIGHT: number = 17
local XORSHIFT_LAST: number = 5
local UPPER_SHIFT: number = 5 -- Keeps a word's top 27 bits
local LOWER_SHIFT: number = 6 -- Keeps a word's top 26 bits
local UPPER_SCALE: number = 67108864 -- 2^26, above the lower 26 bits
local FRACTION_SCALE: number = 9007199254740992 -- 2^53

type Collision = State.Collision
type Hit = State.Hit

-- A slot in plain numbers, read from its part
type Slot = {
	center: { number },
	axes: { { number } }, -- Its X, Y and Z axes in world space
	half: { number }, -- Half its size along each axis
	reach: number, -- Half its diagonal
}

-- The xorshift generator's state, which the slot pick, each kind's plan and the boxes start from the seed
type Draw = { state: number }

-- One kind's comparison of two runs' results
export type Tally = {
	kind: string,
	queries: number,
	differing: number, -- Queries with any value off in its bits, those one side doesn't hold included
	signOnly: number, -- Of those, the ones off only in the sign of a zero
	missing: number, -- Queries one side's results don't hold
	hits: number, -- Queries whose result on our side has an index other than 0
	first: string?, -- The first difference: its query, its value and both sides' bits
}

-- The comparison of two runs' overlap answers
export type OverlapTally = {
	boxes: number,
	differing: number, -- Boxes answered differently, those one side doesn't hold included
	overlapping: number, -- Boxes our side answered 1
	missing: number, -- Boxes one side's answers don't hold
	first: string?,
}

local Queries = {
	KINDS = { "ray", "sweep", "sphere", "rest" }, -- Each kind's name at its number
	QUERIES_PER_SLOT = QUERIES_PER_SLOT, -- Each kind's queries for one slot
	VALUE_BYTES = F64_BYTES, -- Every record is f64s
	PLAN_WIDTH = PLAN_WIDTH,
	RESULT_WIDTH = RESULT_WIDTH,
	BOX_WIDTH = BOX_WIDTH,
	OVERLAP_WIDTH = OVERLAP_WIDTH,
}

-- The generator from a seed, which xorshift needs whole, inside 32 bits and above zero
local function seeded(seed: number): Draw
	if seed ~= seed // 1 or seed < 1 or seed >= WORD then
		error(`A seed must be a whole number from 1 to {WORD - 1}, and got {seed}`)
	end

	return { state = seed }
end

local function nextWord(draw: Draw): number
	local state: number = draw.state
	state = bit32.bxor(state, bit32.lshift(state, XORSHIFT_LEFT))
	state = bit32.bxor(state, bit32.rshift(state, XORSHIFT_RIGHT))
	state = bit32.bxor(state, bit32.lshift(state, XORSHIFT_LAST))
	draw.state = state

	return state
end

--[[
    A number from low to high carrying 53 random bits, built from two words
    with exact operations only, so every VM draws the same inputs
--]]

local function uniform(draw: Draw, low: number, high: number): number
	local upper: number = bit32.rshift(nextWord(draw), UPPER_SHIFT)
	local lower: number = bit32.rshift(nextWord(draw), LOWER_SHIFT)

	return low + (high - low) * ((upper * UPPER_SCALE + lower) / FRACTION_SCALE)
end

--[[
    Count of the parts with CanCollide and CanQuery on, in an order that
    depends only on the list's order and the seed, erroring with both
    numbers when fewer qualify
--]]

function Queries.slots(parts: { BasePart }, count: number, seed: number): { BasePart }
	local qualifying: { BasePart } = {}
	for _, part: BasePart in parts do
		if part.CanCollide and part.CanQuery then
			table.insert(qualifying, part)
		end
	end

	if #qualifying < count then
		error(`{count} slots were asked for, and {#qualifying} of {#parts} parts have CanCollide and CanQuery on`)
	end

	-- A Fisher-Yates shuffle's first picks, each from the parts not picked yet
	local draw: Draw = seeded(seed)
	local picked: { BasePart } = {}
	for index: number = 1, count do
		local pick: number = index + nextWord(draw) % (#qualifying - index + 1)
		qualifying[index], qualifying[pick] = qualifying[pick], qualifying[index]
		picked[index] = qualifying[index]
	end

	return picked
end

-- Each part's place in the list, from 1, which a result records its hit by
function Queries.indexOf(parts: { BasePart }): { [Instance]: number }
	local index: { [Instance]: number } = {}
	for place: number, part: BasePart in parts do
		index[part] = place
	end

	return index
end

-- Writes values as f64s from a byte offset, giving the offset after them
local function put(stream: buffer, at: number, values: { number }): number
	for index: number, value: number in values do
		buffer.writef64(stream, at + (index - 1) * F64_BYTES, value)
	end

	return at + #values * F64_BYTES
end

local function vectorAt(stream: buffer, at: number): vector
	return vector.create(
		buffer.readf64(stream, at),
		buffer.readf64(stream, at + F64_BYTES),
		buffer.readf64(stream, at + 2 * F64_BYTES)
	)
end

local function along(base: { number }, direction: { number }, distance: number): { number }
	return {
		base[1] + direction[1] * distance,
		base[2] + direction[2] * distance,
		base[3] + direction[3] * distance,
	}
end

local function unit(value: { number }): { number }
	local length: number = math.sqrt(value[1] * value[1] + value[2] * value[2] + value[3] * value[3])
	if length < MIN_LENGTH then
		return { 0, -1, 0 }
	end

	return { value[1] / length, value[2] / length, value[3] / length }
end

-- A part's box in plain numbers: its center, its rotation's three columns and half its size
local function slotOf(part: BasePart): Slot
	local cframe: CFrame = part.CFrame
	local size: Vector3 = part.Size
	local half: { number } = { size.X * HALF, size.Y * HALF, size.Z * HALF }

	return {
		center = { cframe.Position.X, cframe.Position.Y, cframe.Position.Z },
		axes = {
			{ cframe.XVector.X, cframe.XVector.Y, cframe.XVector.Z },
			{ cframe.YVector.X, cframe.YVector.Y, cframe.YVector.Z },
			{ cframe.ZVector.X, cframe.ZVector.Y, cframe.ZVector.Z },
		},
		half = half,
		reach = math.sqrt(half[1] * half[1] + half[2] * half[2] + half[3] * half[3]),
	}
end

local function slotsOf(parts: { BasePart }): { Slot }
	local slots: { Slot } = {}
	for _, part: BasePart in parts do
		table.insert(slots, slotOf(part))
	end

	return slots
end

-- How far an axis-aligned box of that half size reaches along a direction from its center
local function boxSupport(normal: { number }, half: { number }): number
	return math.abs(normal[1]) * half[1] + math.abs(normal[2]) * half[2] + math.abs(normal[3]) * half[3]
end

-- How far a kind's cast shape reaches along a face's normal from its center
local function support(kind: number, normal: { number }, radius: number, hull: { number }): number
	if kind == RAY then
		return 0
	end

	if kind == SPHERE then
		return radius
	end

	return boxSupport(normal, hull)
end

--[[
    One query's start, direction and sphere radius: aimed into the box,
    skimming a face at a small height and slope, or starting a hair off a
    face and closing on it, each shape lifted clear by its own extent
--]]

local function shape(
	draw: Draw,
	slot: Slot,
	kind: number,
	query: number,
	radii: { number },
	hull: { number }
): ({ number }, { number }, number)
	local radius: number = radii[query % #radii + 1]

	if query <= AIMED then
		local x: number = uniform(draw, -1, 1) * slot.half[1] * AIM_SPREAD
		local y: number = uniform(draw, -1, 1) * slot.half[2] * AIM_SPREAD
		local z: number = uniform(draw, -1, 1) * slot.half[3] * AIM_SPREAD
		local target: { number } = along(along(along(slot.center, slot.axes[1], x), slot.axes[2], y), slot.axes[3], z)
		local dx: number = uniform(draw, -1, 1)
		local dy: number = uniform(draw, -1, 1)
		local dz: number = uniform(draw, -1, 1)
		local direction: { number } = unit({ dx, dy, dz })

		return along(target, direction, -AIM_BACK), along(ZERO, direction, AIM_REACH), radius
	end

	local axis: number = nextWord(draw) % AXES + 1
	local sign: number = nextWord(draw) % SIDES == 0 and 1 or -1
	local normal: { number } = along(ZERO, slot.axes[axis], sign)
	local across: number = axis % AXES + 1
	local other: number = across % AXES + 1
	local lift: number = slot.half[axis] + support(kind, normal, radius, hull)

	if query <= AIMED + GRAZING then
		local index: number = query - AIMED - 1
		local gap: number = GRAZE_GAPS[index % #GRAZE_GAPS + 1]
		local slope: number = GRAZE_SLOPES[(index // #GRAZE_GAPS) % #GRAZE_SLOPES + 1]
		local a: number = uniform(draw, -1, 1)
		local b: number = uniform(draw, -1, 1)
		local tangent: { number } = unit(along(along(ZERO, slot.axes[across], a), slot.axes[other], b))
		local run: number = slot.reach + GRAZE_MARGIN
		local start: { number } = along(along(slot.center, normal, lift + gap), tangent, -run)
		local direction: { number } = along(ZERO, unit(along(tangent, normal, -slope)), run + run)

		return start, direction, radius
	end

	local index: number = query - AIMED - GRAZING - 1
	local gap: number = NEAR_GAPS[index % #NEAR_GAPS + 1]
	local a: number = uniform(draw, -1, 1) * slot.half[across] * NEAR_SPREAD
	local b: number = uniform(draw, -1, 1) * slot.half[other] * NEAR_SPREAD
	local leanA: number = uniform(draw, -NEAR_TILT, NEAR_TILT)
	local leanB: number = uniform(draw, -NEAR_TILT, NEAR_TILT)
	local start: { number } =
		along(along(along(slot.center, normal, lift + gap), slot.axes[across], a), slot.axes[other], b)
	local closing: { number } = along(along(along(ZERO, normal, -1), slot.axes[across], leanA), slot.axes[other], leanB)

	return start, along(ZERO, unit(closing), NEAR_REACH), radius
end

--[[
    Every query of every kind over the slots, kind by kind and slot by slot
    within a kind, one record each of PLAN_WIDTH f64s. A rest takes its
    start from the box's shape and has no direction, and only a sphere
    keeps its radius
--]]

function Queries.plan(slots: { BasePart }, hull: Vector3, radii: { number }, seed: number): buffer
	if #radii == 0 then
		error("radii must give at least one sphere radius")
	end

	local shapes: { Slot } = slotsOf(slots)
	local half: { number } = { hull.X * HALF, hull.Y * HALF, hull.Z * HALF }
	local plan: buffer = buffer.create(#Queries.KINDS * #shapes * QUERIES_PER_SLOT * PLAN_WIDTH * F64_BYTES)
	local at: number = 0

	for kind: number = 1, #Queries.KINDS do
		-- Each kind starts its generator from the seed, so every kind casts the same shapes, lifted by its own extent
		local draw: Draw = seeded(seed)

		for _, slot: Slot in shapes do
			for query: number = 1, QUERIES_PER_SLOT do
				local origin: { number }, toward: { number }, radius: number =
					shape(draw, slot, kind, query, radii, half)
				local direction: { number } = kind == REST and ZERO or toward
				local kept: number = kind == SPHERE and radius or UNUSED

				local values: { number } =
					{ kind, origin[1], origin[2], origin[3], direction[1], direction[2], direction[3], kept }
				at = put(plan, at, values)
			end
		end
	end

	return plan
end

-- How many whole records a stream holds
local function held(stream: buffer, width: number): number
	return buffer.len(stream) // (width * F64_BYTES)
end

--[[
    Each query of a plan through its cast, one record each of RESULT_WIDTH
    f64s, zeros for a miss. A rest records 1 and its height in the distance
    field when it finds one. The casts hand back one hit table they reuse,
    so each hit is read before the next cast
--]]

function Queries.cast(plan: buffer, hull: Vector3, collision: Collision, index: { [Instance]: number }): buffer
	if buffer.len(plan) % (PLAN_WIDTH * F64_BYTES) ~= 0 then
		error(`A plan of {buffer.len(plan)} B holds no whole number of {PLAN_WIDTH * F64_BYTES} B queries`)
	end

	local queries: number = held(plan, PLAN_WIDTH)
	local size: vector = vector.create(hull.X, hull.Y, hull.Z)
	local results: buffer = buffer.create(queries * RESULT_WIDTH * F64_BYTES)

	for query: number = 0, queries - 1 do
		local at: number = query * PLAN_WIDTH * F64_BYTES
		local out: number = query * RESULT_WIDTH * F64_BYTES
		local kind: number = buffer.readf64(plan, at)
		local origin: vector = vectorAt(plan, at + ORIGIN * F64_BYTES)
		local direction: vector = vectorAt(plan, at + DIRECTION * F64_BYTES)

		if kind == REST then
			local height: number? = collision.rest(origin, size)
			if height then
				put(results, out, { FOUND })
				put(results, out + DISTANCE * F64_BYTES, { height })
			end

			continue
		end

		local hit: Hit?
		if kind == RAY then
			hit = collision.ray(origin, direction)
		elseif kind == SWEEP then
			hit = collision.sweep(origin, size, direction)
		elseif kind == SPHERE then
			hit = collision.sphere(origin, buffer.readf64(plan, at + RADIUS * F64_BYTES), direction)
		else
			error(`Plan query {query + 1} holds kind {kind}, which no cast has`)
		end

		if hit then
			local place: number = OUTSIDE
			local instance: Instance? = hit.instance
			if instance then
				place = index[instance] or OUTSIDE
			end

			local values: { number } = {
				place,
				hit.position.x,
				hit.position.y,
				hit.position.z,
				hit.normal.x,
				hit.normal.y,
				hit.normal.z,
				hit.distance,
				hit.material.Value,
			}
			put(results, out, values)
		end
	end

	return results
end

--[[
    Count boxes at the hull's size, axis aligned, each near a face of the
    slots in turn, its nearest point off the face by BOX_GAPS in turn and
    its center spread across the face, so some overlap and some do not.
    One record each of BOX_WIDTH f64s
--]]

function Queries.boxes(slots: { BasePart }, hull: Vector3, count: number, seed: number): buffer
	if #slots == 0 then
		error("Boxes need at least one slot to sit beside")
	end

	local shapes: { Slot } = slotsOf(slots)
	local half: { number } = { hull.X * HALF, hull.Y * HALF, hull.Z * HALF }
	local draw: Draw = seeded(seed)
	local boxes: buffer = buffer.create(count * BOX_WIDTH * F64_BYTES)
	local at: number = 0

	for box: number = 1, count do
		local slot: Slot = shapes[(box - 1) % #shapes + 1]
		local gap: number = BOX_GAPS[(box - 1) % #BOX_GAPS + 1]
		local axis: number = nextWord(draw) % AXES + 1
		local sign: number = nextWord(draw) % SIDES == 0 and 1 or -1
		local normal: { number } = along(ZERO, slot.axes[axis], sign)
		local across: number = axis % AXES + 1
		local other: number = across % AXES + 1
		local a: number = uniform(draw, -1, 1) * slot.half[across] * NEAR_SPREAD
		local b: number = uniform(draw, -1, 1) * slot.half[other] * NEAR_SPREAD
		local lift: number = slot.half[axis] + boxSupport(normal, half) + gap
		local center: { number } =
			along(along(along(slot.center, normal, lift), slot.axes[across], a), slot.axes[other], b)

		at = put(boxes, at, { center[1], center[2], center[3], hull.X, hull.Y, hull.Z })
	end

	return boxes
end

-- Each box through the overlap query, one record each of OVERLAP_WIDTH f64s, 1 for an overlap and 0 for none
function Queries.overlaps(boxes: buffer, overlap: (center: vector, size: vector) -> boolean): buffer
	local count: number = held(boxes, BOX_WIDTH)
	local answers: buffer = buffer.create(count * OVERLAP_WIDTH * F64_BYTES)

	for box: number = 0, count - 1 do
		local at: number = box * BOX_WIDTH * F64_BYTES
		if overlap(vectorAt(boxes, at), vectorAt(boxes, at + SIZE * F64_BYTES)) then
			put(answers, box * OVERLAP_WIDTH * F64_BYTES, { FOUND })
		end
	end

	return answers
end

-- Whether the f64s at one byte offset of two streams differ in any bit
local function differs(ours: buffer, theirs: buffer, at: number): boolean
	return buffer.readu32(ours, at) ~= buffer.readu32(theirs, at)
		or buffer.readu32(ours, at + HIGH_WORD) ~= buffer.readu32(theirs, at + HIGH_WORD)
end

-- Whether both f64s there are a zero, so they can differ only in its sign
local function zeros(ours: buffer, theirs: buffer, at: number): boolean
	return bit32.band(buffer.readu32(ours, at + HIGH_WORD), MAGNITUDE) == 0
		and buffer.readu32(ours, at) == 0
		and bit32.band(buffer.readu32(theirs, at + HIGH_WORD), MAGNITUDE) == 0
		and buffer.readu32(theirs, at) == 0
end

local function bits(stream: buffer, at: number): string
	return string.format(HEX, buffer.readu32(stream, at + HIGH_WORD), buffer.readu32(stream, at))
end

--[[
    Two runs' results of one plan compared value by value in their bits, a
    tally a kind in Queries.KINDS order. A query either side's results
    don't hold counts as differing and is never read
--]]

function Queries.compare(plan: buffer, ours: buffer, theirs: buffer): { Tally }
	local tallies: { Tally } = {}
	for _, kind: string in Queries.KINDS do
		table.insert(tallies, { kind = kind, queries = 0, differing = 0, signOnly = 0, missing = 0, hits = 0 })
	end

	local queries: number = held(plan, PLAN_WIDTH)
	local oursHeld: number = held(ours, RESULT_WIDTH)
	local theirsHeld: number = held(theirs, RESULT_WIDTH)

	for query: number = 0, queries - 1 do
		local kind: number = buffer.readf64(plan, query * PLAN_WIDTH * F64_BYTES)
		local tally: Tally? = tallies[kind]
		if not tally then
			error(`Plan query {query + 1} holds kind {kind}, which no cast has`)
		end

		tally.queries += 1

		local at: number = query * RESULT_WIDTH * F64_BYTES
		if query < oursHeld and buffer.readf64(ours, at) ~= MISSED then
			tally.hits += 1
		end

		if query >= oursHeld or query >= theirsHeld then
			tally.missing += 1
			tally.differing += 1

			if not tally.first then
				local sides: string = `ours holds {oursHeld} results and theirs {theirsHeld}`
				tally.first = `query {tally.queries}: {sides}, of {queries} queries`
			end

			continue
		end

		local found: boolean = false
		local valued: boolean = false
		for field: number = 0, RESULT_WIDTH - 1 do
			local place: number = at + field * F64_BYTES
			if differs(ours, theirs, place) then
				if not tally.first then
					local name: string = RESULT_FIELDS[field + 1]
					tally.first = `query {tally.queries} {name}: ours {bits(ours, place)}, theirs {bits(theirs, place)}`
				end

				found = true
				valued = valued or not zeros(ours, theirs, place)
			end
		end

		if found then
			tally.differing += 1

			if not valued then
				tally.signOnly += 1
			end
		end
	end

	return tallies
end

--[[
    Two runs' overlap answers compared box by box in their bits. A box
    either side doesn't hold counts as differing and is never read
--]]

function Queries.compareOverlaps(ours: buffer, theirs: buffer): OverlapTally
	local oursHeld: number = held(ours, OVERLAP_WIDTH)
	local theirsHeld: number = held(theirs, OVERLAP_WIDTH)
	local tally: OverlapTally = { boxes = math.max(oursHeld, theirsHeld), differing = 0, overlapping = 0, missing = 0 }

	for box: number = 0, tally.boxes - 1 do
		local at: number = box * OVERLAP_WIDTH * F64_BYTES
		if box < oursHeld and buffer.readf64(ours, at) == FOUND then
			tally.overlapping += 1
		end

		if box >= oursHeld or box >= theirsHeld then
			tally.missing += 1
			tally.differing += 1

			if not tally.first then
				tally.first = `box {box + 1}: ours holds {oursHeld} answers and theirs {theirsHeld}`
			end

			continue
		end

		if differs(ours, theirs, at) then
			tally.differing += 1

			if not tally.first then
				tally.first = `box {box + 1}: ours {bits(ours, at)}, theirs {bits(theirs, at)}`
			end
		end
	end

	return tally
end

-- The FNV hash of a whole stream's 32-bit words, so a clone can show the main thread its plan matches
function Queries.hash(stream: buffer): number
	local size: number = buffer.len(stream)
	if size % WORD_BYTES ~= 0 then
		error(`A stream of {size} B holds no whole number of {WORD_BYTES} B words to hash`)
	end

	local digest: number = FNV_OFFSET
	for offset: number = 0, size - WORD_BYTES, WORD_BYTES do
		digest = bit32.bxor(digest, buffer.readu32(stream, offset))
		digest = (bit32.lshift(digest, FNV_SHIFT) + digest * FNV_LOW) % WORD
	end

	return digest
end

return Queries
