--[[
    The crouch slide's mode packs to code 6, the one after the code kept for
    a mounted mode, in the state word's low 3 bits, and unpacks back, alone
    and in a character record
--]]

--!strict
local Environment = require("../../Environment")

local STATE_WORD: string = "src/Codec/StateWord.luau"
local RECORD: string = "src/Codec/Record.luau"
local CODE: number = 6
local MODE_BITS: number = 3
local LIMITS: { lean: number, headCone: number } = { lean = 20, headCone = 75 }

return function (): (boolean, string | nil)
	local StateWord: any = Environment.load(STATE_WORD)
	local Record: any = Environment.load(RECORD)

	local word: { [string]: any } = {
		mode = "Slide",
		posture = "Crouch",
		sprint = false,
		aim = true,
		waterLevel = "Wading",
		jumps = 2,
		lands = 1,
		heavy = false,
		epoch = 3,
	}

	local packed: number = StateWord.pack(word)
	if bit32.extract(packed, 0, MODE_BITS) ~= CODE then
		return false, `The Slide mode packed to code {bit32.extract(packed, 0, MODE_BITS)}, not {CODE}`
	end

	local back: { [string]: any } = table.clone(word)
	back.mode = "Ground"
	StateWord.unpack(packed, back)
	for key: string, value: any in word do
		if back[key] ~= value then
			return false, `{key} unpacked as {back[key]} from a Slide word, not {value}`
		end
	end

	-- Inside a record, as a viewer reads one
	local record: any = Record.new()
	record.slot, record.generation = 12, 3
	record.position = vector.create(10, 20, -30)
	record.word = packed

	local data: buffer = buffer.create(16)
	Record.write(record, data, 0, LIMITS)
	local read: any = Record.new()
	Record.read(data, 0, read, LIMITS)

	local unpacked: { [string]: any } = table.clone(word)
	StateWord.unpack(read.word, unpacked)
	if read.word ~= packed or unpacked.mode ~= "Slide" then
		return false, `A record carried the Slide word {packed} back as {read.word}, mode {unpacked.mode}`
	end

	return true, nil
end
