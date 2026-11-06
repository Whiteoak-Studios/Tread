--[[
    A keyframe carries CODEC_VERSION, the declarations' hash and the view's
    tick and sequence, each character's kind, withheld mark, record, look
    and held item at their bounds, and every called platform's press
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Fixtures/Codec/Refuses")
local Same = require("../../Fixtures/Codec/Same")

local KEYFRAME: string = "src/Codec/Keyframe.luau"
local CONSTANTS: string = "src/Constants.luau"

-- A buffer of length bytes counting up from first
local function bytes(length: number, first: number): buffer
	local made: buffer = buffer.create(length)
	for index: number = 0, length - 1 do
		buffer.writeu8(made, index, (first + index) % 256)
	end

	return made
end

return function (): (boolean, string | nil)
	local Keyframe: any = Environment.load(KEYFRAME)
	local Constants: any = Environment.load(CONSTANTS)

	local keyframe: { [string]: any } = {
		hash = 2 ^ 32 - 1,
		tick = 65535,
		sequence = 1,
		characters = {
			{ kind = "Player", withheld = false, record = bytes(16, 0), look = bytes(64, 1), held = bytes(16, 2) },
			{ kind = "Npc", withheld = true, record = bytes(16, 3), look = bytes(0, 0), held = bytes(0, 0) },
			{ kind = "Body", withheld = false, record = bytes(16, 4), look = bytes(10, 5), held = bytes(0, 0) },
			{ kind = "Sleeper", withheld = true, record = bytes(16, 6), look = bytes(1, 7), held = bytes(5, 8) },
		},
		platforms = { { id = 1, tick = 0 }, { id = 127, tick = 2 ^ 32 - 1 } },
	}

	local data: buffer = Keyframe.write(keyframe)
	local length: number = 12 + 4 * 19 + (64 + 16) + 0 + 10 + (1 + 5) + 1 + 2 * 5
	if buffer.len(data) ~= length then
		return false, `The keyframe is {buffer.len(data)} B, where its parts fill {length}`
	elseif buffer.readu16(data, 0) ~= Constants.CODEC_VERSION or buffer.readu32(data, 2) ~= 2 ^ 32 - 1 then
		return false, "The keyframe doesn't open with CODEC_VERSION and the declarations' hash"
	elseif
		buffer.readu16(data, 10) ~= 4
		or buffer.readu8(data, 12) ~= 0
		or buffer.readu8(data, 12 + 19 + 80) ~= 0x81
	then
		return false, "The keyframe's count, or a character's kind and withheld mark, isn't where its layout puts it"
	end

	local differs: string? = Same(keyframe, Keyframe.read(data), "keyframe")
	if differs then
		return false, differs
	end

	-- A keyframe of no characters and no platforms is its header and the platforms' count
	local empty: buffer = Keyframe.write({ hash = 0, tick = 0, sequence = 0, characters = {}, platforms = {} })
	if buffer.len(empty) ~= 13 or #Keyframe.read(empty).characters ~= 0 then
		return false, "An empty keyframe isn't its 12 B header and a count"
	end

	-- What a keyframe refuses to write
	local function with(change: (character: { [string]: any }) -> ()): { [string]: any }
		local character: { [string]: any } =
			{ kind = "Player", withheld = false, record = bytes(16, 0), look = bytes(0, 0), held = bytes(0, 0) }
		change(character)

		return { hash = 0, tick = 0, sequence = 0, characters = { character }, platforms = {} }
	end

	local writes: { { any } } = {
		{ "record is 16 B", with(function (character: { [string]: any })
			character.record = bytes(15, 0)
		end) },
		{ "passes its bound", with(function (character: { [string]: any })
			character.look = bytes(65, 0)
		end) },
		{ "passes its bound", with(function (character: { [string]: any })
			character.held = bytes(17, 0)
		end) },
		{ "not Ghost", with(function (character: { [string]: any })
			character.kind = "Ghost"
		end) },
		{
			"platform id is 1 to 127",
			{ hash = 0, tick = 0, sequence = 0, characters = {}, platforms = { { id = 0, tick = 0 } } },
		},
	}

	for index: number, row: { any } in writes do
		local refused: boolean, why: string = Refuses(row[1], Keyframe.write, row[2])
		if not refused then
			return false, `Keyframe write {index} wasn't refused: {why}`
		end
	end

	-- What a read refuses: another version, bytes cut short and bytes left over
	local other: buffer = buffer.create(buffer.len(data))
	buffer.copy(other, 0, data)
	buffer.writeu16(other, 0, Constants.CODEC_VERSION + 1)

	local cut: buffer = buffer.create(buffer.len(data) - 1)
	buffer.copy(cut, 0, data, 0, buffer.len(cut))

	local long: buffer = buffer.create(buffer.len(data) + 1)
	buffer.copy(long, 0, data)

	for _, row: { any } in
		{
			{ "that version's decoder", other },
			{ "ends inside", buffer.create(5) },
			{ "don't end", cut },
			{ "don't end", long },
		}
	do
		local refused: boolean, why: string = Refuses(row[1], Keyframe.read, row[2])
		if not refused then
			return false, `A keyframe read that should fail with {row[1]} didn't: {why}`
		end
	end

	return true, nil
end
