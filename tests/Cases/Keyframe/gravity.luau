--[[
    A keyframe's gravity rides as an f64, so 68.1, 1e-3 and 1e6 read back
    exactly, and a write or a read refuses a gravity that is no finite
    number above 0, and a read refuses a keyframe cut before it
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Fixtures/Codec/Refuses")

local KEYFRAME: string = "src/Codec/Keyframe.luau"
local GRAVITY_AT: number = 13 -- After the 12 B header and the platform count, in a keyframe of no characters
local REFUSED: string = "gravity is a finite number above 0"

-- A keyframe of nothing but its gravity
local function bare(gravity: any): { [string]: any }
	return { hash = 0, tick = 0, sequence = 0, characters = {}, platforms = {}, gravity = gravity }
end

return function (): (boolean, string | nil)
	local Keyframe: any = Environment.load(KEYFRAME)

	for _, gravity: number in { 68.1, 1e-3, 1e6 } do
		local data: buffer = Keyframe.write(bare(gravity))
		local read: any = Keyframe.read(data)

		if buffer.len(data) ~= 25 then
			return false, `A keyframe of gravity {gravity} alone is {buffer.len(data)} B, not 25`
		elseif read.gravity ~= gravity or buffer.readf64(data, GRAVITY_AT) ~= gravity then
			return false, `The gravity {gravity} read back as {read.gravity}`
		end
	end

	-- What a write refuses
	for _, gravity: any in { 0, -68.1, math.huge, 0 / 0, "68.1" } do
		local refused: boolean, why: string = Refuses(REFUSED, Keyframe.write, bare(gravity))
		if not refused then
			return false, `A keyframe write of gravity {gravity} wasn't refused: {why}`
		end
	end

	local refused: boolean, why: string = Refuses(REFUSED, Keyframe.write, bare(nil))
	if not refused then
		return false, `A keyframe write with no gravity wasn't refused: {why}`
	end

	-- What a read refuses: each of those gravities in the bytes, and a keyframe whose gravity is cut short
	local good: buffer = Keyframe.write(bare(68.1))
	for _, gravity: number in { 0, -68.1, math.huge, 0 / 0 } do
		local data: buffer = buffer.create(buffer.len(good))
		buffer.copy(data, 0, good)
		buffer.writef64(data, GRAVITY_AT, gravity)

		local read: boolean, message: string = Refuses(REFUSED, Keyframe.read, data)
		if not read then
			return false, `A keyframe read of gravity {gravity} wasn't refused: {message}`
		end
	end

	local cut: buffer = buffer.create(GRAVITY_AT + 4)
	buffer.copy(cut, 0, good, 0, GRAVITY_AT + 4)
	local short: boolean, message: string = Refuses("ends inside", Keyframe.read, cut)
	if not short then
		return false, `A keyframe cut inside its gravity wasn't refused: {message}`
	end

	return true, nil
end
