--[[
    The moderator's feed, once a relay tick: the spectated target's
    OwnerState exactly as the target got it, then the look of each command
    it stepped since the last feed, newest first, a list tap frames share
--]]

--!strict
--!native
local Command = require(script.Parent.Command)
local Constants = require(script.Parent.Parent.Constants)
local State = require(script.Parent.Parent.Step.State)

local YAW_SCALE: number = Constants.ANGLE_STEPS / (2 * math.pi) -- A command's steps a radian, as Move carries them
local PITCH_SCALE: number = Constants.PITCH_LIMIT / (math.pi / 2)

type Limits = Command.Limits

-- One stepped command's look at Move's precision: the base look and the head offset
export type Look = {
	yaw: number, -- Radians
	pitch: number,
	headYaw: number, -- Degrees
	headPitch: number,
}

-- A feed read: the target's OwnerState left in data at its offset, and the looks
export type Feed = {
	ownerData: buffer,
	ownerAt: number,
	ownerLength: number,
	count: number,
	looks: { Look }, -- Newest first, holding at least count
}

local Feed = {}

--[[
    An empty feed, which a reader reads into and reuses
--]]

function Feed.new(): Feed
	return {
		ownerData = buffer.create(0),
		ownerAt = 0,
		ownerLength = 0,
		count = 0,
		looks = {} :: { Look },
	}
end

local function steps(value: number, scale: number, limit: number): number
	return math.clamp(math.round(value * scale), -limit, limit)
end

--[[
    Keeps the look of a command just stepped at the front of looks, whose
    first count are current and newest first, dropping the oldest past a
    Move's worth, and gives the new count. looks holds a table for each
    look a list carries, so a push makes none
--]]

function Feed.push(looks: { State.Command }, count: number, command: State.Command): number
	-- The oldest look past the cap, or the first spare, moves to the front and takes the newest
	local last: number = math.min(count + 1, Constants.MAX_COMMANDS)
	local newest: State.Command = looks[last]

	table.move(looks, 1, last - 1, 2)
	looks[1] = newest

	newest.yaw = command.yaw
	newest.pitch = command.pitch
	newest.headYaw = command.headYaw
	newest.headPitch = command.headPitch

	return last
end

--[[
    Writes a look list at offset, a u8 count and then the look of each of
    the first count commands, newest first, 6 B each at Move's precision,
    and gives the offset after it. It errors on more looks than a Move
    carries, and room for them is the caller's
--]]

function Feed.writeLooks(
	data: buffer,
	offset: number,
	commands: { State.Command },
	count: number,
	limits: Limits
): number
	if not (count >= 0 and count <= Constants.MAX_COMMANDS and count % 1 == 0) then
		error(`A look list carries 0 to {Constants.MAX_COMMANDS} looks, not {count}`)
	end

	buffer.writeu8(data, offset, count)
	offset += Constants.PREFIX_BYTES

	local headScale: number = Constants.HEAD_STEPS / limits.headCone
	for index: number = 1, count do
		local command: State.Command = commands[index]

		buffer.writeu16(data, offset, math.round(command.yaw * YAW_SCALE) % Constants.ANGLE_STEPS)
		buffer.writei16(data, offset + 2, steps(command.pitch, PITCH_SCALE, Constants.PITCH_LIMIT))
		buffer.writei8(data, offset + 4, steps(command.headYaw, headScale, Constants.HEAD_STEPS))
		buffer.writei8(data, offset + 5, steps(command.headPitch, headScale, Constants.HEAD_STEPS))
		offset += Constants.FEED_LOOK_BYTES
	end

	return offset
end

--[[
    Reads the look list at offset in data's first length bytes into looks,
    reusing its tables, and gives its count and the offset after it. It
    errors on a count past a Move's and on looks that pass length
--]]

function Feed.readLooks(data: buffer, offset: number, length: number, into: { Look }, limits: Limits): (number, number)
	if offset + Constants.PREFIX_BYTES > length then
		error(`A look list at byte {offset} passes its {length} B`)
	end

	local count: number = buffer.readu8(data, offset)
	offset += Constants.PREFIX_BYTES

	if count > Constants.MAX_COMMANDS then
		error(`A look list carries at most {Constants.MAX_COMMANDS} looks, not {count}`)
	elseif offset + count * Constants.FEED_LOOK_BYTES > length then
		error(`A look list's {count} looks pass its {length} B`)
	end

	local headScale: number = limits.headCone / Constants.HEAD_STEPS
	for index: number = 1, count do
		local look: Look = into[index]
		if not look then
			look = { yaw = 0, pitch = 0, headYaw = 0, headPitch = 0 }
			into[index] = look
		end

		look.yaw = buffer.readu16(data, offset) / YAW_SCALE
		look.pitch = buffer.readi16(data, offset + 2) / PITCH_SCALE
		look.headYaw = buffer.readi8(data, offset + 4) * headScale
		look.headPitch = buffer.readi8(data, offset + 5) * headScale
		offset += Constants.FEED_LOOK_BYTES
	end

	return count, offset
end

--[[
    Writes a feed into data from its first byte and gives the bytes it
    filled: the ownerLength bytes of owner from ownerAt, which the target
    was sent, then the looks of the first count commands, newest first. It
    errors on more commands than a Move carries, or past data
--]]

function Feed.write(
	data: buffer,
	owner: buffer,
	ownerAt: number,
	ownerLength: number,
	commands: { State.Command },
	count: number,
	limits: Limits
): number
	local bytes: number = 2 * Constants.PREFIX_BYTES + ownerLength + count * Constants.FEED_LOOK_BYTES
	if not (ownerLength <= Constants.MAX_OWNER_STATE and count >= 0 and count <= Constants.MAX_COMMANDS) then
		error(`A feed carries at most {Constants.MAX_OWNER_STATE} B of OwnerState and {Constants.MAX_COMMANDS} looks`)
	elseif bytes > buffer.len(data) then
		error(`A feed of {bytes} B passes its {buffer.len(data)} B buffer`)
	end

	buffer.writeu8(data, 0, ownerLength)
	buffer.copy(data, Constants.PREFIX_BYTES, owner, ownerAt, ownerLength)

	return Feed.writeLooks(data, Constants.PREFIX_BYTES + ownerLength, commands, count, limits)
end

--[[
    Reads a feed into into, reusing its look tables, with the target's
    OwnerState left in data at the offset into names. It errors on bytes
    that aren't a feed
--]]

function Feed.read(data: buffer, into: Feed, limits: Limits)
	local length: number = buffer.len(data)
	if length < 2 * Constants.PREFIX_BYTES then
		error(`A feed is at least {2 * Constants.PREFIX_BYTES} B, not {length}`)
	end

	local ownerLength: number = buffer.readu8(data, 0)
	local countAt: number = Constants.PREFIX_BYTES + ownerLength
	if countAt + Constants.PREFIX_BYTES > length then
		error(`A feed's OwnerState of {ownerLength} B passes its {length} B`)
	end

	-- The looks end the feed, checked before any is read so a refused feed leaves into as it was
	local count: number = buffer.readu8(data, countAt)
	local offset: number = countAt + Constants.PREFIX_BYTES
	if count > Constants.MAX_COMMANDS or offset + count * Constants.FEED_LOOK_BYTES ~= length then
		error(`A feed's {count} looks don't end its {length} B`)
	end

	Feed.readLooks(data, countAt, length, into.looks, limits)

	into.ownerData = data
	into.ownerAt = Constants.PREFIX_BYTES
	into.ownerLength = ownerLength
	into.count = count
end

return Feed
