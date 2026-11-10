--[[
    A keyframe carries CODEC_VERSION, the declarations' hash and the view's
    tick and sequence, each character's kind, withheld mark, record, look
    and held item at their bounds, every called platform's press, and the
    view's own character, its id 0 for none
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
		own = { id = 2 ^ 16 - 1, look = bytes(64, 9), held = bytes(16, 10) },
	}

	local data: buffer = Keyframe.write(keyframe)
	local ownAt: number = 12 + 4 * 19 + (64 + 16) + 0 + 10 + (1 + 5) + 1 + 2 * 5
	local length: number = ownAt + 4 + 64 + 16
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
	elseif
		buffer.readu16(data, ownAt) ~= 2 ^ 16 - 1
		or buffer.readu8(data, ownAt + 2) ~= 64
		or buffer.readu8(data, ownAt + 3 + 64) ~= 16
	then
		return false, "The keyframe's own id, look length or held length isn't after the platforms"
	end

	local differs: string? = Same(keyframe, Keyframe.read(data), "keyframe")
	if differs then
		return false, differs
	end

	-- A keyframe of no characters, no platforms and no own character is its header, the count and an own id of 0
	local empty: buffer = Keyframe.write({ hash = 0, tick = 0, sequence = 0, characters = {}, platforms = {} })
	local read: any = Keyframe.read(empty)
	if buffer.len(empty) ~= 17 or #read.characters ~= 0 or read.own ~= nil then
		return false, "An empty keyframe isn't its 12 B header, a count and 4 B of no own character"
	elseif buffer.readu32(empty, 13) ~= 0 then
		return false, "An empty keyframe's own character isn't an id of 0 with empty parts"
	end

	-- What a keyframe refuses to write
	local function with(change: (character: { [string]: any }) -> ()): { [string]: any }
		local character: { [string]: any } =
			{ kind = "Player", withheld = false, record = bytes(16, 0), look = bytes(0, 0), held = bytes(0, 0) }
		change(character)

		return { hash = 0, tick = 0, sequence = 0, characters = { character }, platforms = {} }
	end

	local function ownWith(id: number, look: number, held: number): { [string]: any }
		return { id = id, look = bytes(look, 0), held = bytes(held, 0) }
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
		{
			"id is 1 to 65535",
			{ hash = 0, tick = 0, sequence = 0, characters = {}, platforms = {}, own = ownWith(0, 0, 0) },
		},
		{
			"own look of 65 B",
			{ hash = 0, tick = 0, sequence = 0, characters = {}, platforms = {}, own = ownWith(1, 65, 0) },
		},
		{
			"held item of 17 B",
			{ hash = 0, tick = 0, sequence = 0, characters = {}, platforms = {}, own = ownWith(1, 0, 17) },
		},
	}

	for index: number, row: { any } in writes do
		local refused: boolean, why: string = Refuses(row[1], Keyframe.write, row[2])
		if not refused then
			return false, `Keyframe write {index} wasn't refused: {why}`
		end
	end

	-- What a read refuses: another version, bytes cut short, bytes left over, and parts for no own character
	local other: buffer = buffer.create(buffer.len(data))
	buffer.copy(other, 0, data)
	buffer.writeu16(other, 0, Constants.CODEC_VERSION + 1)

	local cut: buffer = buffer.create(buffer.len(data) - 1)
	buffer.copy(cut, 0, data, 0, buffer.len(cut))

	local long: buffer = buffer.create(buffer.len(data) + 1)
	buffer.copy(long, 0, data)

	-- An own id of 0 whose look still has a length and bytes
	local nobody: buffer = buffer.create(buffer.len(empty) + 1)
	buffer.copy(nobody, 0, empty, 0, 15)
	buffer.writeu8(nobody, 15, 1)

	for _, row: { any } in
		{
			{ "that version's decoder", other },
			{ "ends inside", buffer.create(5) },
			{ "ends inside", cut },
			{ "past its own character", long },
			{ "no own character", nobody },
		}
	do
		local refused: boolean, why: string = Refuses(row[1], Keyframe.read, row[2])
		if not refused then
			return false, `A keyframe read that should fail with {row[1]} didn't: {why}`
		end
	end

	return true, nil
end
