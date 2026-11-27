--[[
    The parity battery B2 under --!native: the lerps, the vector library, %,
    the Vector3 methods, the CFrame constructors and products and a written
    part's CFrame, each section hashed over its values' f64 bits
--]]

--!strict
--!native
local SEED: number = 88675123 -- Where the input generator starts, the same in every VM
local LERP_INPUTS: number = 4096 -- Inputs for each lerp and %, where native code may fuse
local SMALL_INPUTS: number = 512
local EXACT_INPUTS: number = 256 -- Inputs for the operations IEEE rounds exactly
local CFRAME_INPUTS: number = 256
local POSITION_LIMIT: number = 8192 -- The play bound in studs
local DIVISOR_LOW: number = 0.001
local DIVISOR_HIGH: number = 360
local SCALE_LIMIT: number = 4
local CLAMP_LIMIT: number = 4096
local ANGLE_LIMIT: number = math.pi
local SKEW: number = 0.01 -- How far each axis of a skewed matrix strays from orthonormal
local MIN_LENGTH: number = 0.001 -- Below this a random direction is replaced by a fixed one
local LOOP_STEPS: number = 2000000 -- The timing loop, which shows whether this module ran native
local LOOP_DECAY: number = 0.999999

local MILLISECONDS: number = 1000
local F64_BYTES: number = 8
local WORD_BYTES: number = 4
local HASH: string = "%08x"
local EXACT: string = "%.17g" -- Enough digits to tell any two f64 values apart
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
local SALT_SHIFT: number = 20 -- Each section reseeds with its number in high bits, so one that fails moves no other

local LOW: vector = vector.create(-CLAMP_LIMIT, -CLAMP_LIMIT, -CLAMP_LIMIT)
local HIGH: vector = vector.create(CLAMP_LIMIT, CLAMP_LIMIT, CLAMP_LIMIT)

export type Section = {
	name: string,
	width: number, -- Values in each record
	records: number,
	hash: number, -- FNV-1a over the 32-bit words of the section's f64 bits
	failure: string?, -- Why it could not run, its values then zeros
}

-- Plain data, so it crosses a BindableEvent between VMs whole
export type Result = {
	sections: { Section }, -- In the battery's order
	values: number, -- Every value the battery wrote
	hash: number, -- Over the whole stream
	loopMs: number, -- The timing loop's milliseconds, reported and never compared
	loopValue: number, -- What the timing loop ended at
}

-- A section as it ran, before the stream is packed and hashed
type Entry = {
	name: string,
	width: number,
	records: number,
	first: number, -- The stream index of its first value, from 0
	failure: string?,
}

-- One call's battery: the stream, the sections so far and the generator's state
type Battery = {
	values: { number },
	entries: { Entry },
	state: number,
}

local Builtins = {}

local function nextWord(battery: Battery): number
	local state: number = battery.state
	state = bit32.bxor(state, bit32.lshift(state, XORSHIFT_LEFT))
	state = bit32.bxor(state, bit32.rshift(state, XORSHIFT_RIGHT))
	state = bit32.bxor(state, bit32.lshift(state, XORSHIFT_LAST))
	battery.state = state

	return state
end

--[[
    A number from low to high carrying 53 random bits, built from two words
    with exact operations only, so every VM draws the same inputs
--]]

local function uniform(battery: Battery, low: number, high: number): number
	local upper: number = bit32.rshift(nextWord(battery), UPPER_SHIFT)
	local lower: number = bit32.rshift(nextWord(battery), LOWER_SHIFT)

	return low + (high - low) * ((upper * UPPER_SCALE + lower) / FRACTION_SCALE)
end

local function push(battery: Battery, value: number)
	table.insert(battery.values, value)
end

--[[
    Runs one section's records into the stream. A section that throws, or
    writes the wrong number of values, is filled with zeros instead, so the
    sections after it still line up
--]]

local function section(battery: Battery, name: string, width: number, records: number, fill: (record: number) -> ())
	local values: { number } = battery.values
	local first: number = #values
	battery.state = bit32.bxor(SEED, bit32.lshift(#battery.entries + 1, SALT_SHIFT))

	local ran: boolean, problem: unknown = pcall(function ()
		for record: number = 1, records do
			fill(record)
		end
	end)

	local failure: string? = nil
	if not ran then
		failure = tostring(problem)
	elseif #values ~= first + width * records then
		failure = `wrote {#values - first} values, not {width * records}`
	end

	if failure then
		for index: number = #values, first + 1, -1 do
			values[index] = nil
		end

		for _ = 1, width * records do
			push(battery, 0)
		end
	end

	table.insert(battery.entries, { name = name, width = width, records = records, first = first, failure = failure })
end

local function pack(values: { number }): buffer
	local stream: buffer = buffer.create(#values * F64_BYTES)

	for index: number, value: number in values do
		buffer.writef64(stream, (index - 1) * F64_BYTES, value)
	end

	return stream
end

-- FNV-1a over the 32-bit words of that many values' f64 bits, from the first, which counts from 0
local function hash(stream: buffer, first: number, count: number): number
	local digest: number = FNV_OFFSET

	for offset: number = first * F64_BYTES, (first + count) * F64_BYTES - 1, WORD_BYTES do
		digest = bit32.bxor(digest, buffer.readu32(stream, offset))
		digest = (bit32.lshift(digest, FNV_SHIFT) + digest * FNV_LOW) % WORD
	end

	return digest
end

local function pushVector(battery: Battery, value: vector)
	push(battery, value.x)
	push(battery, value.y)
	push(battery, value.z)
end

local function pushVector3(battery: Battery, value: Vector3)
	push(battery, value.X)
	push(battery, value.Y)
	push(battery, value.Z)
end

local function pushCFrame(battery: Battery, value: CFrame)
	local x: number, y: number, z: number, r00: number, r01: number, r02: number, r10: number, r11: number, r12: number, r20: number, r21: number, r22: number =
		value:GetComponents()

	push(battery, x)
	push(battery, y)
	push(battery, z)
	push(battery, r00)
	push(battery, r01)
	push(battery, r02)
	push(battery, r10)
	push(battery, r11)
	push(battery, r12)
	push(battery, r20)
	push(battery, r21)
	push(battery, r22)
end

local function randomVector(battery: Battery, limit: number): vector
	local x: number = uniform(battery, -limit, limit)
	local y: number = uniform(battery, -limit, limit)
	local z: number = uniform(battery, -limit, limit)

	return vector.create(x, y, z)
end

local function toVector3(value: vector): Vector3
	return Vector3.new(value.x, value.y, value.z)
end

local function randomDirection(battery: Battery): Vector3
	local x: number = uniform(battery, -1, 1)
	local y: number = uniform(battery, -1, 1)
	local z: number = uniform(battery, -1, 1)
	local length: number = math.sqrt(x * x + y * y + z * z)
	if length < MIN_LENGTH then
		return Vector3.yAxis
	end

	return Vector3.new(x / length, y / length, z / length)
end

local function randomCFrame(battery: Battery): CFrame
	local position: Vector3 = toVector3(randomVector(battery, POSITION_LIMIT))
	local qx: number = uniform(battery, -1, 1)
	local qy: number = uniform(battery, -1, 1)
	local qz: number = uniform(battery, -1, 1)
	local qw: number = uniform(battery, -1, 1)
	local length: number = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
	if length < MIN_LENGTH then
		return CFrame.new(position)
	end

	return CFrame.new(position.X, position.Y, position.Z, qx / length, qy / length, qz / length, qw / length)
end

local function skew(battery: Battery, axis: Vector3): Vector3
	local x: number = uniform(battery, -SKEW, SKEW)
	local y: number = uniform(battery, -SKEW, SKEW)
	local z: number = uniform(battery, -SKEW, SKEW)

	return axis + Vector3.new(x, y, z)
end

-- A rotation whose axes stray from orthonormal, for the engine to straighten
local function skewedCFrame(battery: Battery): CFrame
	local base: CFrame = randomCFrame(battery)
	local right: Vector3 = skew(battery, base.XVector)
	local up: Vector3 = skew(battery, base.YVector)
	local back: Vector3 = skew(battery, base.ZVector)

	return CFrame.fromMatrix(base.Position, right, up, back)
end

-- Plain arithmetic whose milliseconds show whether this module ran native, with the value it ended at
local function loop(): (number, number)
	local started: number = os.clock()
	local value: number = 0

	for step: number = 1, LOOP_STEPS do
		value = value * LOOP_DECAY + step
	end

	return (os.clock() - started) * MILLISECONDS, value
end

-- How one section ran, as a line of differences names it
local function outcome(entry: Section): string
	local failure: string? = entry.failure
	if failure then
		return `failed: {failure}`
	end

	return `ran, hash {string.format(HASH, entry.hash)}`
end

--[[
    Runs the whole battery from the seed, its two Part.CFrame sections
    writing the part handed in, then the timing loop. Nothing carries over
    from one call to the next, so every call in every VM starts alike
--]]

function Builtins.run(part: BasePart): Result
	local battery: Battery = { values = {}, entries = {}, state = SEED }

	-- The inputs every lerp section shares, so a built-in and a hand-written lerp meet the same values
	local aValues: { number } = {}
	local bValues: { number } = {}
	local tValues: { number } = {}
	local divisors: { number } = {}
	local scales: { number } = {}
	local uVectors: { vector } = {}
	local vVectors: { vector } = {}

	for index: number = 1, LERP_INPUTS do
		aValues[index] = uniform(battery, -POSITION_LIMIT, POSITION_LIMIT)
		bValues[index] = uniform(battery, -POSITION_LIMIT, POSITION_LIMIT)
		tValues[index] = uniform(battery, 0, 1)
		divisors[index] = uniform(battery, DIVISOR_LOW, DIVISOR_HIGH)
		scales[index] = uniform(battery, -SCALE_LIMIT, SCALE_LIMIT)
		uVectors[index] = randomVector(battery, POSITION_LIMIT)
		vVectors[index] = randomVector(battery, POSITION_LIMIT)
	end

	section(battery, "math.lerp", 1, LERP_INPUTS, function (record: number)
		push(battery, math.lerp(aValues[record], bValues[record], tValues[record]))
	end)

	section(battery, "a + (b - a) * t", 1, LERP_INPUTS, function (record: number)
		local a: number = aValues[record]
		push(battery, a + (bValues[record] - a) * tValues[record])
	end)

	section(battery, "a % b", 1, LERP_INPUTS, function (record: number)
		push(battery, aValues[record] % divisors[record])
	end)

	section(battery, "vector.lerp", 3, LERP_INPUTS, function (record: number)
		-- Selene's standard library predates vector.lerp
		-- selene: allow(incorrect_standard_library_use)
		pushVector(battery, vector.lerp(uVectors[record], vVectors[record], tValues[record]))
	end)

	section(battery, "u + (v - u) * t", 3, LERP_INPUTS, function (record: number)
		local u: vector = uVectors[record]
		pushVector(battery, u + (vVectors[record] - u) * tValues[record])
	end)

	section(battery, "vector.magnitude", 1, SMALL_INPUTS, function (record: number)
		push(battery, vector.magnitude(uVectors[record]))
	end)

	section(battery, "vector.normalize", 3, SMALL_INPUTS, function (record: number)
		pushVector(battery, vector.normalize(uVectors[record]))
	end)

	section(battery, "vector.dot", 1, SMALL_INPUTS, function (record: number)
		push(battery, vector.dot(uVectors[record], vVectors[record]))
	end)

	section(battery, "vector.cross", 3, SMALL_INPUTS, function (record: number)
		pushVector(battery, vector.cross(uVectors[record], vVectors[record]))
	end)

	section(battery, "vector.angle", 1, SMALL_INPUTS, function (record: number)
		push(battery, vector.angle(uVectors[record], vVectors[record]))
	end)

	section(battery, "vector.floor, ceil, abs, sign", 12, EXACT_INPUTS, function (record: number)
		local u: vector = uVectors[record] / scales[record]
		pushVector(battery, vector.floor(u))
		pushVector(battery, vector.ceil(u))
		pushVector(battery, vector.abs(u))
		pushVector(battery, vector.sign(u))
	end)

	section(battery, "vector.clamp, max, min", 9, EXACT_INPUTS, function (record: number)
		pushVector(battery, vector.clamp(uVectors[record], LOW, HIGH))
		pushVector(battery, vector.max(uVectors[record], vVectors[record]))
		pushVector(battery, vector.min(uVectors[record], vVectors[record]))
	end)

	section(battery, "vector operators", 18, SMALL_INPUTS, function (record: number)
		local u: vector = uVectors[record]
		local v: vector = vVectors[record]
		local s: number = scales[record]
		pushVector(battery, u + v)
		pushVector(battery, u - v)
		pushVector(battery, u * v)
		pushVector(battery, u / v)
		pushVector(battery, u * s)
		pushVector(battery, u / s)
	end)

	section(battery, "Vector3:Lerp", 3, LERP_INPUTS, function (record: number)
		pushVector3(battery, toVector3(uVectors[record]):Lerp(toVector3(vVectors[record]), tValues[record]))
	end)

	section(battery, "U + (V - U) * t", 3, LERP_INPUTS, function (record: number)
		local u: Vector3 = toVector3(uVectors[record])
		pushVector3(battery, u + (toVector3(vVectors[record]) - u) * tValues[record])
	end)

	section(battery, "Vector3.Magnitude", 1, SMALL_INPUTS, function (record: number)
		push(battery, toVector3(uVectors[record]).Magnitude)
	end)

	section(battery, "Vector3.Unit", 3, SMALL_INPUTS, function (record: number)
		pushVector3(battery, toVector3(uVectors[record]).Unit)
	end)

	section(battery, "Vector3:Dot", 1, SMALL_INPUTS, function (record: number)
		push(battery, toVector3(uVectors[record]):Dot(toVector3(vVectors[record])))
	end)

	section(battery, "Vector3:Cross", 3, SMALL_INPUTS, function (record: number)
		pushVector3(battery, toVector3(uVectors[record]):Cross(toVector3(vVectors[record])))
	end)

	section(battery, "Vector3:Angle", 1, SMALL_INPUTS, function (record: number)
		push(battery, toVector3(uVectors[record]):Angle(toVector3(vVectors[record])))
	end)

	section(battery, "Vector3:Floor, Ceil, Abs, Sign", 12, EXACT_INPUTS, function (record: number)
		local u: Vector3 = toVector3(uVectors[record]) / scales[record]
		pushVector3(battery, u:Floor())
		pushVector3(battery, u:Ceil())
		pushVector3(battery, u:Abs())
		pushVector3(battery, u:Sign())
	end)

	section(battery, "Vector3:Max, Min", 6, EXACT_INPUTS, function (record: number)
		local u: Vector3 = toVector3(uVectors[record])
		local v: Vector3 = toVector3(vVectors[record])
		pushVector3(battery, u:Max(v))
		pushVector3(battery, u:Min(v))
	end)

	section(battery, "Vector3 operators", 18, SMALL_INPUTS, function (record: number)
		local u: Vector3 = toVector3(uVectors[record])
		local v: Vector3 = toVector3(vVectors[record])
		local s: number = scales[record]
		pushVector3(battery, u + v)
		pushVector3(battery, u - v)
		pushVector3(battery, u * v)
		pushVector3(battery, u / v)
		pushVector3(battery, u * s)
		pushVector3(battery, u / s)
	end)

	section(battery, "CFrame.new with a quaternion", 12, CFRAME_INPUTS, function ()
		pushCFrame(battery, randomCFrame(battery))
	end)

	section(battery, "CFrame.Angles", 12, CFRAME_INPUTS, function ()
		local x: number = uniform(battery, -ANGLE_LIMIT, ANGLE_LIMIT)
		local y: number = uniform(battery, -ANGLE_LIMIT, ANGLE_LIMIT)
		local z: number = uniform(battery, -ANGLE_LIMIT, ANGLE_LIMIT)
		pushCFrame(battery, CFrame.Angles(x, y, z))
	end)

	section(battery, "CFrame.fromOrientation", 12, CFRAME_INPUTS, function ()
		local x: number = uniform(battery, -ANGLE_LIMIT, ANGLE_LIMIT)
		local y: number = uniform(battery, -ANGLE_LIMIT, ANGLE_LIMIT)
		local z: number = uniform(battery, -ANGLE_LIMIT, ANGLE_LIMIT)
		pushCFrame(battery, CFrame.fromOrientation(x, y, z))
	end)

	section(battery, "CFrame.fromAxisAngle", 12, CFRAME_INPUTS, function ()
		local axis: Vector3 = randomDirection(battery)
		pushCFrame(battery, CFrame.fromAxisAngle(axis, uniform(battery, -ANGLE_LIMIT, ANGLE_LIMIT)))
	end)

	section(battery, "CFrame.lookAt", 12, CFRAME_INPUTS, function ()
		local position: Vector3 = toVector3(randomVector(battery, POSITION_LIMIT))
		pushCFrame(battery, CFrame.lookAt(position, position + randomDirection(battery)))
	end)

	section(battery, "CFrame.lookAlong", 12, CFRAME_INPUTS, function ()
		local position: Vector3 = toVector3(randomVector(battery, POSITION_LIMIT))
		pushCFrame(battery, CFrame.lookAlong(position, randomDirection(battery)))
	end)

	section(battery, "CFrame.fromMatrix", 12, CFRAME_INPUTS, function ()
		pushCFrame(battery, skewedCFrame(battery))
	end)

	section(battery, "CFrame * Vector3", 3, CFRAME_INPUTS, function ()
		local frame: CFrame = randomCFrame(battery)
		pushVector3(battery, frame * toVector3(randomVector(battery, POSITION_LIMIT)))
	end)

	section(battery, "CFrame * CFrame", 12, CFRAME_INPUTS, function ()
		local left: CFrame = randomCFrame(battery)
		pushCFrame(battery, left * randomCFrame(battery))
	end)

	section(battery, "CFrame:Inverse", 12, CFRAME_INPUTS, function ()
		pushCFrame(battery, randomCFrame(battery):Inverse())
	end)

	section(battery, "CFrame:Orthonormalize", 12, CFRAME_INPUTS, function ()
		pushCFrame(battery, skewedCFrame(battery):Orthonormalize())
	end)

	-- The caller's part: these show what writing a part's CFrame does to the components
	section(battery, "Part.CFrame written", 12, CFRAME_INPUTS, function ()
		part.CFrame = randomCFrame(battery)
		pushCFrame(battery, part.CFrame)
	end)

	section(battery, "Part.CFrame written skewed", 12, CFRAME_INPUTS, function ()
		part.CFrame = skewedCFrame(battery)
		pushCFrame(battery, part.CFrame)
	end)

	local stream: buffer = pack(battery.values)
	local sections: { Section } = {}
	for _, entry: Entry in battery.entries do
		table.insert(sections, {
			name = entry.name,
			width = entry.width,
			records = entry.records,
			hash = hash(stream, entry.first, entry.width * entry.records),
			failure = entry.failure,
		})
	end

	local loopMs: number, loopValue: number = loop()

	return {
		sections = sections,
		values = #battery.values,
		hash = hash(stream, 0, #battery.values),
		loopMs = loopMs,
		loopValue = loopValue,
	}
end

--[[
    Each way theirs differs from ours, one line each: a section either side
    failed, a section's shape or hash, a section one side lacks, the
    sections' order, and the timing loop's end value. Empty when they agree,
    and the timing loop's milliseconds never count
--]]

function Builtins.differences(ours: Result, theirs: Result): { string }
	local lines: { string } = {}
	local theirSections: { [string]: Section } = {}
	for _, entry: Section in theirs.sections do
		theirSections[entry.name] = entry
	end

	local ourNames: { [string]: boolean } = {}
	for _, entry: Section in ours.sections do
		ourNames[entry.name] = true

		local other: Section? = theirSections[entry.name]
		if not other then
			table.insert(lines, `{entry.name}: missing from theirs`)
		elseif entry.failure ~= nil or other.failure ~= nil then
			table.insert(lines, `{entry.name}: ours {outcome(entry)}; theirs {outcome(other)}`)
		elseif entry.width ~= other.width or entry.records ~= other.records then
			local shape: string = `{entry.records} records of {entry.width}`
			table.insert(lines, `{entry.name}: ours {shape}, theirs {other.records} of {other.width}`)
		elseif entry.hash ~= other.hash then
			local hashes: string = `ours {string.format(HASH, entry.hash)}, theirs {string.format(HASH, other.hash)}`
			table.insert(lines, `{entry.name}: hash {hashes}`)
		end
	end

	for _, entry: Section in theirs.sections do
		if not ourNames[entry.name] then
			table.insert(lines, `{entry.name}: missing from ours`)
		end
	end

	-- With every section alike by name, a whole stream that hashes apart holds them in another order
	if #lines == 0 and ours.hash ~= theirs.hash then
		local hashes: string = `ours {string.format(HASH, ours.hash)}, theirs {string.format(HASH, theirs.hash)}`
		table.insert(lines, `section order: the whole stream hashes {hashes} with every section alike`)
	end

	if ours.loopValue ~= theirs.loopValue then
		local ends: string = `{string.format(EXACT, ours.loopValue)}, theirs {string.format(EXACT, theirs.loopValue)}`
		table.insert(lines, `timing loop: ours ended at {ends}`)
	end

	return lines
end

return Builtins
