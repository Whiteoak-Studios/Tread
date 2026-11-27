--[[
    The 16 B character record, encoded once per target a tick and copied to
    each viewer: slot and generation, X, Z, Y, yaw, pitch, the state word and
    one byte of lean or head offset
--]]

--!strict
--!native
local Bits = require(script.Parent.Bits)
local Command = require(script.Parent.Command)
local Constants = require(script.Parent.Parent.Constants)

local POSITION_SCALE: number = 1 / Constants.RECORD_QUANTUM -- Steps a stud of X and Z
local POSITION_ZERO: number = 2 ^ (Constants.RECORD_POSITION_BITS - 1) -- The step 0 studs sits at, so -8,192 is step 0
local POSITION_TOP: number = 2 ^ Constants.RECORD_POSITION_BITS - 1 -- The highest step X and Z hold
local POSITION_HIGH: number = 2 ^ Constants.RECORD_POSITION_BITS -- What X's and Z's top bits count in
local HEIGHT_SCALE: number = 1 / Constants.RECORD_HEIGHT_QUANTUM
local HEIGHT_TOP: number = 2 ^ 16 - 1 -- The highest step Y's u16 holds
local YAW_SCALE: number = Constants.ANGLE_STEPS / (2 * math.pi)
local PITCH_SCALE: number = Constants.RECORD_PITCH_STEPS / (math.pi / 2) -- Steps a radian of pitch, 127 at 90°

-- The platform index's bits in X's top, then in Z's top below the selector, which says what the last byte holds
local PLATFORM_LOW: number = Constants.RECORD_TOP_BITS
local PLATFORM_HIGH: number = Constants.PLATFORM_BITS - Constants.RECORD_TOP_BITS
local LEVELS: number = 2 * (Constants.HEAD_LEVELS + 1) -- The values a signed 4-bit level holds, yaw's the low one

type Limits = Command.Limits

-- One character's record as a viewer draws it
export type Record = {
	slot: number,
	generation: number,
	position: vector, -- The feet, in world coordinates, or in its platform's space while it rides one
	platform: number, -- The ridden platform's id, 0 for none
	yaw: number, -- Radians
	pitch: number,
	word: number, -- The state word
	lean: number, -- Degrees, 0 while the head offset is set
	headYaw: number, -- The head offset, degrees
	headPitch: number,
}

local Record = {}

--[[
    A record at rest at the origin, which a reader fills and reuses
--]]

function Record.new(): Record
	return {
		slot = 0,
		generation = 0,
		position = vector.zero,
		platform = 0,
		yaw = 0,
		pitch = 0,
		word = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
	}
end

--[[
    A slot and its generation as the u16 every layout names a character by,
    12 bits of slot below 4 of generation, erroring on either too wide
--]]

function Record.id(slot: number, generation: number): number
	if
		bit32.extract(slot, 0, Constants.SLOT_BITS) ~= slot
		or bit32.extract(generation, 0, Constants.GENERATION_BITS) ~= generation
	then
		error(`Slot {slot} and generation {generation} don't fit a character's 12 and 4 bits`)
	end

	return slot + generation * Constants.SLOTS
end

--[[
    The slot and generation a u16 character id names
--]]

function Record.split(id: number): (number, number)
	return id % Constants.SLOTS, id // Constants.SLOTS
end

--[[
    Writes a position from offset as X and Z u24, whose low 20 bits hold it
    at 1/64 stud across the play bound, then Y u16 at 1/32 stud across the
    height window, each clamped to what it holds, with xTop and zTop in the
    top 4 bits of X and Z
--]]

function Record.writePosition(position: vector, xTop: number, zTop: number, data: buffer, offset: number)
	local x: number = math.clamp(math.round(position.x * POSITION_SCALE) + POSITION_ZERO, 0, POSITION_TOP)
	local z: number = math.clamp(math.round(position.z * POSITION_SCALE) + POSITION_ZERO, 0, POSITION_TOP)
	local y: number = math.clamp(math.round((position.y - Constants.HEIGHT_MIN) * HEIGHT_SCALE), 0, HEIGHT_TOP)

	Bits.writeu24(data, offset, x + xTop * POSITION_HIGH)
	Bits.writeu24(data, offset + 3, z + zTop * POSITION_HIGH)
	buffer.writeu16(data, offset + 6, y)
end

--[[
    Reads a position Record.writePosition wrote, and the top 4 bits of its
    X and Z
--]]

function Record.readPosition(data: buffer, offset: number): (vector, number, number)
	local x: number = Bits.readu24(data, offset)
	local z: number = Bits.readu24(data, offset + 3)
	local y: number = buffer.readu16(data, offset + 6)

	local position: vector = vector.create(
		(x % POSITION_HIGH - POSITION_ZERO) / POSITION_SCALE,
		y / HEIGHT_SCALE + Constants.HEIGHT_MIN,
		(z % POSITION_HIGH - POSITION_ZERO) / POSITION_SCALE
	)

	return position, x // POSITION_HIGH, z // POSITION_HIGH
end

-- Rounds value to whole steps at scale a unit, inside limit steps either way
local function steps(value: number, scale: number, limit: number): number
	return math.clamp(math.round(value * scale), -limit, limit)
end

-- A signed level from its 4 bits
local function level(bits: number): number
	if bits >= LEVELS / 2 then
		return bits - LEVELS
	end

	return bits
end

--[[
    Encodes a record into the 16 B of data from offset. Its last byte holds
    the head offset while that is set and lean otherwise, since the server
    zeroes lean whenever the offset is set
--]]

function Record.write(record: Record, data: buffer, offset: number, limits: Limits)
	local platform: number = record.platform
	if bit32.extract(platform, 0, Constants.PLATFORM_BITS) ~= platform then
		error(`A record's platform is 0 to {Constants.MAX_PLATFORMS}, not {platform}`)
	end

	local head: boolean = record.headYaw ~= 0 or record.headPitch ~= 0
	local zTop: number = bit32.extract(platform, PLATFORM_LOW, PLATFORM_HIGH)
	if head then
		zTop += 2 ^ PLATFORM_HIGH
	end

	buffer.writeu16(data, offset, Record.id(record.slot, record.generation))
	Record.writePosition(record.position, bit32.extract(platform, 0, PLATFORM_LOW), zTop, data, offset + 2)
	buffer.writeu16(data, offset + 10, math.round(record.yaw * YAW_SCALE) % Constants.ANGLE_STEPS)
	buffer.writei8(data, offset + 12, steps(record.pitch, PITCH_SCALE, Constants.RECORD_PITCH_STEPS))
	buffer.writeu16(data, offset + 13, record.word)

	if head then
		local scale: number = Constants.HEAD_LEVELS / limits.headCone
		local yaw: number = steps(record.headYaw, scale, Constants.HEAD_LEVELS) % LEVELS
		local pitch: number = steps(record.headPitch, scale, Constants.HEAD_LEVELS) % LEVELS

		buffer.writeu8(data, offset + 15, yaw + pitch * LEVELS)
	else
		buffer.writei8(data, offset + 15, steps(record.lean, Constants.LEAN_STEPS / limits.lean, Constants.LEAN_STEPS))
	end
end

--[[
    Decodes the 16 B record at offset of data into into
--]]

function Record.read(data: buffer, offset: number, into: Record, limits: Limits)
	local position: vector, xTop: number, zTop: number = Record.readPosition(data, offset + 2)

	into.slot, into.generation = Record.split(buffer.readu16(data, offset))
	into.position = position
	into.platform = xTop + bit32.extract(zTop, 0, PLATFORM_HIGH) * 2 ^ PLATFORM_LOW
	into.yaw = buffer.readu16(data, offset + 10) / YAW_SCALE
	into.pitch = buffer.readi8(data, offset + 12) / PITCH_SCALE
	into.word = buffer.readu16(data, offset + 13)

	if bit32.extract(zTop, PLATFORM_HIGH) == 1 then
		local last: number = buffer.readu8(data, offset + 15)
		local scale: number = limits.headCone / Constants.HEAD_LEVELS

		into.headYaw = level(last % LEVELS) * scale
		into.headPitch = level(last // LEVELS) * scale
		into.lean = 0
	else
		into.lean = buffer.readi8(data, offset + 15) * limits.lean / Constants.LEAN_STEPS
		into.headYaw = 0
		into.headPitch = 0
	end
end

return Record
